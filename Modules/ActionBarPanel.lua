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
-- "actionbars", "micromenu", "bagbar" and "statusbars". /abdump [bar|micro|
-- bags|xp] [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

-- The looks a group of buttons can take (action bars, micro menu, bag bar;
-- the rims are UI Modifications' Button Border, every window's)
local BACKDROP_VALUES = {
	{ value = "red", label = "Red gems" },
	{ value = "iron", label = "Iron gems" },
	{ value = "none", label = "None" },
}
local BACKGROUND_VALUES = Kit.buttonLooks.backgrounds

-- The groups (user, 2026-09-23: the action bars first, then "onto the micro
-- bar and bag buttons next"): each its own four choices
local GROUPS = {
	{ id = "bars", title = "Action Bars", keys = { backdrop = "barBackdrop", background = "barBackground", buttonBackground = "buttonBackground" } },
	{ id = "micro", title = "Micro Menu", keys = { backdrop = "microBackdrop", background = "microBackground", buttonBackground = "microButtonBackground" } },
	{ id = "bags", title = "Bag Bar", keys = { backdrop = "bagBackdrop", background = "bagBackground", buttonBackground = "bagButtonBackground" } },
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
	local what = g.id == "bars" and "Action Bar 1 (and the bars snapped to it in Edit Mode: as wide a bar widens it, a narrower one gets a tab tucked under it)"
		or (g.id == "micro" and "the micro menu" or "the bag bar")
	-- (the buttons' rim: UI Modifications' Button Border, every window's)
	options[#options + 1] = { type = "dropdown", key = g.keys.backdrop, name = "Backdrop", values = BACKDROP_VALUES,
		desc = "A frame round " .. what .. ", with a gem on each corner." }
	options[#options + 1] = { type = "dropdown", key = g.keys.background, name = "Backdrop Background", values = BACKGROUND_VALUES,
		desc = "What lies behind the buttons inside the backdrop. All of these are also chosen with previews by Dynamic UI Modification, at the top of the configurator." }
	options[#options + 1] = { type = "dropdown", key = g.keys.buttonBackground, name = "Button Background", values = BACKGROUND_VALUES,
		desc = "What a button shows inside its rim where it has no icon." }
end

local M = MelloUI:RegisterModule("ActionBarPanel", {
	title = "Action Bars Kit",
	desc = "The action bars, micro menu, bag bar and experience bars dressed in the painted kit on the game's own layout.",
	enabledByDefault = true,
	defaults = defaults,
	options = options,
})

local skin = nil
local active = false
local hooked = false

local BAR_NAMES = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
	"MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar" }
local BAG_BUTTONS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
	"CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }

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
-- The backdrop (user, 2026-09-23, sketched on the bars: "make a backdrop border
-- behind the action bar, that resizes the currently used action bar border
-- texture ... the whole action bar only has 4 gems and they are on the
-- backdrop ... a concrete texture which stands behind the actionbar buttons";
-- "attached to the Action Bar 1, but once another action bar is snapped to
-- the action bar 1 it should dynamically expand to cover the other one").
-- The slot rim as painted (deco/barframe, red gems) cut as a nine-slice round
-- Action Bar 1, the stone inside it behind the buttons (which wear thin rims
-- now). A bar Edit Mode snapped to it (or to one snapped to it) as wide as it
-- widens the backdrop; a narrower one (the stance or pet bar) gets a tab of
-- the same frame that tucks under the backdrop, so only its outer gems show.
-- Frames of Action Bar 1 at the BACKGROUND strata (over the end caps, under
-- every button): they follow its moves, scale and hiding; laid out again
-- out of combat when Edit Mode re-lays a bar or a bar is shown or hidden.
--------------------------------------------------------------------------------

-- the slot rim as painted (red gems), or the kit's toned slot (iron gems):
-- the same border, the same geometry
-- Backdrop -> the border piece: the slot rim with heavier top and bottom rails
-- (Tools/build_kit.py heavy_frame), its gems red or iron
local FRAME_PIECES = { red = "deco/barframe_red", iron = "deco/barframe_iron" }
local FRAME_PIECE = FRAME_PIECES.red

-- The choices as the Configurator and the Dynamic UI Modification picker
-- show them (label, and the piece a preview is drawn with)
M.choices = {
	barBackdrop = {
		{ value = "red", label = "Red gems", piece = FRAME_PIECES.red },
		{ value = "iron", label = "Iron gems", piece = FRAME_PIECES.iron },
		{ value = "none", label = "None" },
	},
	barBackground = BACKGROUND_VALUES,
}
-- the buttons' own backing: the same textures
M.choices.buttonBackground = M.choices.barBackground
local FRAME_CORNER = 40      -- piece px: the corner square (the gem and the mitre) of the nine-slice
local FRAME_GAP = 0.12       -- of a button's size: stone between the buttons' rims and the frame's inner edge
local SNAP_GAP = 0.35        -- of a button's size: a bar this close to the group counts as snapped
local FULL_WIDTH = 0.85      -- a snapped bar at least this share of the backdrop's width widens it (else a tab)

-- A frame's rect in screen px (l, b, r, t), secret-safe.
local function ScreenRect(f)
	local ok, l, b, w, h = pcall(f.GetRect, f)
	if not ok or Secret(l) or Secret(b) or Secret(w) or Secret(h) or not (l and w and w > 0 and h and h > 0) then
		return nil
	end
	local s = f:GetEffectiveScale()
	return { l * s, b * s, (l + w) * s, (b + h) * s }
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
	local rect, size
	for i, button in ipairs(entry.buttons) do
		if i <= count and (not shownOnly or button:IsShown()) then
			local r = ScreenRect(button)
			if r then
				size = size or (r[3] - r[1])
				rect = rect and { math.min(rect[1], r[1]), math.min(rect[2], r[2]), math.max(rect[3], r[3]), math.max(rect[4], r[4]) } or r
			end
		end
	end
	return rect, size
end

-- The gap between two rects (0 when they touch or overlap) and whether they
-- run side by side on the other axis.
local function Gap(a, b)
	local dx = math.max(0, math.max(a[1], b[1]) - math.min(a[3], b[3]))
	local dy = math.max(0, math.max(a[2], b[2]) - math.min(a[4], b[4]))
	return math.max(dx, dy), (dx == 0 or dy == 0)
end

--------------------------------------------------------------------------------
-- Joining backdrops that meet (user, 2026-09-23: "when the backdrop is not
-- equaly wide ... make a L shapped texture that aplies here"). Where a
-- narrower backdrop sits on a wider one (the bag bar on the micro menu, a
-- bar snapped to Action Bar 1), the two become one shape: the narrower one
-- loses its edge and corners on that side, its side rails run on into the
-- wider one's rail, its background meets the wider one's; the wider one's
-- rail opens under it; at each step the L joint (deco/barjoin) turns the
-- side rail into the wider one's rail. A side that lines up with the wider
-- frame's side runs straight on, the wider frame's corner there dropped.
--------------------------------------------------------------------------------

local JOIN_PIECE = "deco/barjoin"
-- A frame's rails: outer and inner edge from each side of its piece (px); the
-- inner edges from the piece's opening (its top and bottom rails are heavier)
local function Rails(f)
	local p = Kit:Piece(f.piece or FRAME_PIECE)
	local o = p and p.open or { 29, 28, 106, 102 }
	local w, h = p and p.w or 135, p and p.h or 130
	return { top = { 6, o[2] }, bottom = { 5, h - o[4] }, left = { 7, o[1] }, right = { 7, w - o[3] } }
end
local JOIN_REACH = 110        -- piece px: frames overlapping this much still meet (both grow round their buttons)

-- Local units of frame f for a screen point (from its bottom-left corner)
local function Local(f, x, y)
	return (x - f.screen[1]) / f.s, (y - f.screen[2]) / f.s
end

local function Pooled(f, pool, piece, layer, sublevel)
	f[pool] = f[pool] or {}
	f[pool].used = (f[pool].used or 0) + 1
	local tex = f[pool][f[pool].used]
	if not tex then
		tex = f:CreateTexture(nil, layer, nil, sublevel)
		f[pool][f[pool].used] = tex
	end
	if tex.kitName ~= piece then
		Kit:Apply(tex, piece)
	end
	tex:ClearAllPoints()
	tex:Show()
	return tex
end

-- Before a layout: every part shown, the extras put away
local function ResetJoins(f)
	for _, tex in pairs(f.parts) do
		tex:Show()
	end
	for _, pool in ipairs({ "segs", "joins" }) do
		if f[pool] then
			for _, tex in ipairs(f[pool]) do
				tex:Hide()
			end
			f[pool].used = 0
		end
	end
	f.spans = nil
end

-- The narrower frame n into the wider frame w; `above`: n sits on w's top
local function Join(n, w, above)
	local N, W = n.screen, w.screen
	local side = above and "top" or "bottom"
	local RAIL, NRAIL = Rails(w), Rails(n)
	-- w's rail on that side, and n's side rails (screen px)
	local wOuter = above and (W[4] - RAIL.top[1] * w.ks) or (W[2] + RAIL.bottom[1] * w.ks)
	local wInner = above and (W[4] - RAIL.top[2] * w.ks) or (W[2] + RAIL.bottom[2] * w.ks)
	local lOuter, lInner = N[1] + NRAIL.left[1] * n.ks, N[1] + NRAIL.left[2] * n.ks
	local rOuter, rInner = N[3] - NRAIL.right[1] * n.ks, N[3] - NRAIL.right[2] * n.ks
	local half = (RAIL.left[2] - RAIL.left[1]) * w.ks / 2
	local alignedL = math.abs(lOuter - (W[1] + RAIL.left[1] * w.ks)) <= half
	local alignedR = math.abs(rOuter - (W[3] - RAIL.right[1] * w.ks)) <= half
	local parts, cs = n.parts, n.cs
	-- n: its edge and corners on that side go; its side rails run to w's rail;
	-- its background reaches w's
	local _, yOuter = Local(n, 0, wOuter)
	local _, yInner = Local(n, 0, wInner)
	if above then
		parts.b:Hide(); parts.bl:Hide(); parts.br:Hide()
		parts.l:SetPoint("BOTTOMRIGHT", n, "BOTTOMLEFT", cs, yOuter)
		parts.r:SetPoint("BOTTOMLEFT", n, "BOTTOMRIGHT", -cs, yOuter)
		n.stone:SetPoint("BOTTOMRIGHT", n, "BOTTOMRIGHT", -n.stoneInset[3], yInner)
	else
		parts.t:Hide(); parts.tl:Hide(); parts.tr:Hide()
		parts.l:SetPoint("TOPLEFT", n, "BOTTOMLEFT", 0, yOuter)
		parts.r:SetPoint("TOPRIGHT", n, "BOTTOMRIGHT", 0, yOuter)
		n.stone:SetPoint("TOPLEFT", n, "BOTTOMLEFT", n.stoneInset[1], yInner)
	end
	-- the L joints at the steps (not where a side lines up)
	local y0, y1 = math.min(wOuter, wInner), math.max(wOuter, wInner)
	for _, step in ipairs({ { not alignedL, lOuter, lInner, false }, { not alignedR, rInner, rOuter, true } }) do
		if step[1] then
			local x0, x1 = step[2], step[3]
			local tex = Pooled(n, "joins", JOIN_PIECE, "ARTWORK", 1)
			local lx, ly = Local(n, x0, y0)
			tex:SetPoint("BOTTOMLEFT", n, "BOTTOMLEFT", lx, ly)
			tex:SetSize((x1 - x0) / n.s, (y1 - y0) / n.s)
			local p = Kit:Piece(JOIN_PIECE)
			local u0, u1, v0, v1 = p.uv[1], p.uv[2], p.uv[3], p.uv[4]
			if step[4] then u0, u1 = u1, u0 end            -- the right step: mirrored
			if not above then v0, v1 = v1, v0 end          -- n below w: flipped
			tex:SetTexCoord(u0, u1, v0, v1)
		end
	end
	n:SetFrameLevel(w:GetFrameLevel() + 1)
	-- w: its rail on that side opens under n (collected: several may sit there)
	w.spans = w.spans or { top = {}, bottom = {}, left = {}, right = {} }
	table.insert(w.spans[side], { l = lOuter, r = rOuter, alignedL = alignedL, alignedR = alignedR })
end

-- w's rail on a side with openings: the pieces between them, the corners of a
-- side that n lines up with dropped (its side rail running to w's edge)
local function OpenRail(w, side)
	local spans = w.spans and w.spans[side]
	if not spans or #spans == 0 then
		return
	end
	table.sort(spans, function(a, b) return a.l < b.l end)
	local W, parts, cs = w.screen, w.parts, w.cs
	local top = side == "top"
	parts[top and "t" or "b"]:Hide()
	local left, right = W[1] + cs * w.s, W[3] - cs * w.s
	if spans[1].alignedL then
		parts[top and "tl" or "bl"]:Hide()
		if top then parts.l:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0) else parts.l:SetPoint("BOTTOMRIGHT", w, "BOTTOMLEFT", cs, 0) end
	end
	if spans[#spans].alignedR then
		parts[top and "tr" or "br"]:Hide()
		if top then parts.r:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0) else parts.r:SetPoint("BOTTOMLEFT", w, "BOTTOMRIGHT", -cs, 0) end
	end
	local x = left
	local pieces = {}
	for _, span in ipairs(spans) do
		if span.l > x then
			pieces[#pieces + 1] = { x, span.l }
		end
		x = math.max(x, span.r)
	end
	if right > x then
		pieces[#pieces + 1] = { x, right }
	end
	local u0, u1, v0, v1 = unpack(w.railTC[side])
	for _, seg in ipairs(pieces) do
		local tex = Pooled(w, "segs", w.piece, "ARTWORK", 0)
		local lx = (seg[1] - W[1]) / w.s
		if top then
			tex:SetPoint("TOPLEFT", w, "TOPLEFT", lx, 0)
		else
			tex:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", lx, 0)
		end
		tex:SetSize((seg[2] - seg[1]) / w.s, cs)
		tex:SetTexCoord(u0, u1, v0, v1)
	end
end

-- The shorter frame n beside the taller frame w (user, 2026-09-23: "snapping
-- a horizontal and vertical bar does not result in a L shape"): the same
-- joining turned on its side. `leftOf`: n sits against w's left side. n's
-- facing edge and corners go, its top and bottom rails run on into w's side
-- rail, its background reaches w's; w's side rail opens beside n; at each
-- step the L joint turns w's side rail into n's top / bottom rail (the same
-- art: w's side rail is the thin upright band, n's rail the heavy one;
-- flipped at the bottom step, mirrored on w's right side). An edge that
-- lines up with w's runs straight on, w's corner there dropped.
local function JoinSide(n, w, leftOf)
	local N, W = n.screen, w.screen
	local side = leftOf and "left" or "right"
	local RAIL, NRAIL = Rails(w), Rails(n)
	-- w's side rail facing n, and n's top and bottom rails (screen px)
	local wOuter = leftOf and (W[1] + RAIL.left[1] * w.ks) or (W[3] - RAIL.right[1] * w.ks)
	local wInner = leftOf and (W[1] + RAIL.left[2] * w.ks) or (W[3] - RAIL.right[2] * w.ks)
	local tOuter, tInner = N[4] - NRAIL.top[1] * n.ks, N[4] - NRAIL.top[2] * n.ks
	local bOuter, bInner = N[2] + NRAIL.bottom[1] * n.ks, N[2] + NRAIL.bottom[2] * n.ks
	local alignedT = math.abs(tOuter - (W[4] - RAIL.top[1] * w.ks)) <= (RAIL.top[2] - RAIL.top[1]) * w.ks / 2
	local alignedB = math.abs(bOuter - (W[2] + RAIL.bottom[1] * w.ks)) <= (RAIL.bottom[2] - RAIL.bottom[1]) * w.ks / 2
	local parts, cs = n.parts, n.cs
	local xOuter = Local(n, wOuter, 0)
	local xInner = Local(n, wInner, 0)
	if leftOf then
		parts.r:Hide(); parts.tr:Hide(); parts.br:Hide()
		parts.t:SetPoint("BOTTOMRIGHT", n, "TOPLEFT", xOuter, -cs)
		parts.b:SetPoint("TOPRIGHT", n, "BOTTOMLEFT", xOuter, cs)
		n.stone:SetPoint("BOTTOMRIGHT", n, "BOTTOMLEFT", xInner, n.stoneInset[4])
	else
		parts.l:Hide(); parts.tl:Hide(); parts.bl:Hide()
		parts.t:SetPoint("TOPLEFT", n, "TOPLEFT", xOuter, 0)
		parts.b:SetPoint("BOTTOMLEFT", n, "BOTTOMLEFT", xOuter, 0)
		n.stone:SetPoint("TOPLEFT", n, "TOPLEFT", xInner, -n.stoneInset[2])
	end
	-- the L joints at the steps (not where an edge lines up)
	local x0, x1 = math.min(wOuter, wInner), math.max(wOuter, wInner)
	for _, step in ipairs({ { not alignedT, tInner, tOuter, false }, { not alignedB, bOuter, bInner, true } }) do
		if step[1] then
			local y0, y1 = step[2], step[3]
			local tex = Pooled(n, "joins", JOIN_PIECE, "ARTWORK", 1)
			local lx, ly = Local(n, x0, y0)
			tex:SetPoint("BOTTOMLEFT", n, "BOTTOMLEFT", lx, ly)
			tex:SetSize((x1 - x0) / n.s, (y1 - y0) / n.s)
			local p = Kit:Piece(JOIN_PIECE)
			local u0, u1, v0, v1 = p.uv[1], p.uv[2], p.uv[3], p.uv[4]
			if not leftOf then u0, u1 = u1, u0 end         -- on w's right side: mirrored
			if step[4] then v0, v1 = v1, v0 end            -- the bottom step: flipped
			tex:SetTexCoord(u0, u1, v0, v1)
		end
	end
	n:SetFrameLevel(w:GetFrameLevel() + 1)
	-- w: its side rail opens beside n
	w.spans = w.spans or { top = {}, bottom = {}, left = {}, right = {} }
	table.insert(w.spans[side], { l = bOuter, r = tOuter, alignedL = alignedB, alignedR = alignedT })
end

-- w's side rail ("left" / "right") with openings: the pieces between them
-- (bottom to top), the corners of an edge n lines up with dropped (w's top or
-- bottom rail running on to its side)
local function OpenSideRail(w, side)
	local spans = w.spans and w.spans[side]
	if not spans or #spans == 0 then
		return
	end
	table.sort(spans, function(a, b) return a.l < b.l end)
	local W, parts, cs = w.screen, w.parts, w.cs
	local left = side == "left"
	parts[left and "l" or "r"]:Hide()
	local bottom, top = W[2] + cs * w.s, W[4] - cs * w.s
	if spans[1].alignedL then
		parts[left and "bl" or "br"]:Hide()
		if left then parts.b:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 0, 0) else parts.b:SetPoint("TOPRIGHT", w, "BOTTOMRIGHT", 0, cs) end
	end
	if spans[#spans].alignedR then
		parts[left and "tl" or "tr"]:Hide()
		if left then parts.t:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0) else parts.t:SetPoint("BOTTOMRIGHT", w, "TOPRIGHT", 0, -cs) end
	end
	local y = bottom
	local pieces = {}
	for _, span in ipairs(spans) do
		if span.l > y then
			pieces[#pieces + 1] = { y, span.l }
		end
		y = math.max(y, span.r)
	end
	if top > y then
		pieces[#pieces + 1] = { y, top }
	end
	local u0, u1, v0, v1 = unpack(w.railTC[side])
	for _, seg in ipairs(pieces) do
		local tex = Pooled(w, "segs", w.piece, "ARTWORK", 0)
		local ly = (seg[1] - W[2]) / w.s
		if left then
			tex:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 0, ly)
		else
			tex:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", 0, ly)
		end
		tex:SetSize(cs, (seg[2] - seg[1]) / w.s)
		tex:SetTexCoord(u0, u1, v0, v1)
	end
end

-- Two frames side by side: one's right edge on the other's left, their
-- heights overlapping, the shorter one within the taller one's height
local function TrySide(a, b)
	local A, B = a.screen, b.screen
	if math.min(A[4], B[4]) - math.max(A[2], B[2]) <= 0 then
		return
	end
	local L, R = a, b
	if A[1] > B[1] then
		L, R = b, a
	end
	local Ls, Rs = L.screen, R.screen
	local ks = math.max(L.ks, R.ks)
	if Ls[3] < Rs[1] or Ls[3] > Rs[1] + JOIN_REACH * ks or Ls[3] >= Rs[3] then
		return   -- apart, or one over the other rather than beside it
	end
	local narrow, wide = L, R
	if (Ls[4] - Ls[2]) > (Rs[4] - Rs[2]) then
		narrow, wide = R, L
	end
	local N, W = narrow.screen, wide.screen
	local RAIL = Rails(wide)
	local band = (RAIL.top[2] - RAIL.top[1]) * wide.ks
	if N[2] < W[2] - band or N[4] > W[4] + band then
		return   -- staggered: neither sits within the other's height
	end
	JoinSide(narrow, wide, narrow == L)
	return true
end

-- Do two shown frames meet? Joined when one sits on the other within the
-- other's width, or beside it within its height.
local function TryJoin(a, b)
	local A, B = a.screen, b.screen
	if math.min(A[3], B[3]) - math.max(A[1], B[1]) <= 0 then
		return
	end
	if TrySide(a, b) then
		return
	end
	local up, down = a, b
	if A[4] < B[4] then
		up, down = b, a
	end
	local U, D = up.screen, down.screen
	local ks = math.max(up.ks, down.ks)
	if U[2] > D[4] or U[2] < D[4] - JOIN_REACH * ks or U[4] <= D[4] then
		return   -- apart, or one inside the other rather than on it
	end
	local narrow, wide = up, down
	if (U[3] - U[1]) > (D[3] - D[1]) then
		narrow, wide = down, up
	end
	local N, W = narrow.screen, wide.screen
	local RAIL = Rails(wide)
	local band = (RAIL.left[2] - RAIL.left[1]) * wide.ks
	if N[1] < W[1] - band or N[3] > W[3] + band then
		return   -- staggered: neither sits within the other
	end
	Join(narrow, wide, narrow == up)
end

-- The background tiled at one on-screen size and from the screen's origin
-- rather than its own corner, so two backdrops that meet show one surface
-- (their stone's patches carried on across the join, not restarted at it)
local function AlignStone(f)
	local tex, p = f.stone, f.stone.kitPiece
	if not (f.screen and type(p) == "table" and p.tile and tex:IsShown()) then
		return
	end
	-- one repeat the same size ON SCREEN for every backdrop, whatever its
	-- bar's scale (user, 2026-09-23: with the micro menu scaled up in Edit
	-- Mode its stone came out stretched next to the bag bar's sharper one):
	-- the kit's one background resolution, its phase from the screen's
	-- origin, so backdrops that meet show one surface
	tex.kitAlign = "screen"
	Kit:Retile(tex)
end

local function JoinFrames()
	local list = {}
	for _, g in ipairs(GROUPS) do
		local bd = skin.groups[g.id].backdrop
		if bd.main and bd.main:IsShown() and bd.main.screen then
			list[#list + 1] = bd.main
		end
		for _, tab in ipairs(bd.tabs) do
			if tab:IsShown() and tab.screen then
				list[#list + 1] = tab
			end
		end
	end
	for i = 1, #list do
		for j = i + 1, #list do
			TryJoin(list[i], list[j])
		end
	end
	for _, f in ipairs(list) do
		OpenRail(f, "top")
		OpenRail(f, "bottom")
		OpenSideRail(f, "left")
		OpenSideRail(f, "right")
		AlignStone(f)
	end
end

local function NewFrame(parent)
	local f = CreateFrame("Frame", nil, parent)
	-- not part of the bar's size: an action bar is a layout frame that grows
	-- round its shown children, so the backdrop (a child reaching past the
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
	f.stone = f:CreateTexture(nil, "BACKGROUND", nil, 0)
	f.stone.kitScale = Kit.scale
	Kit:Apply(f.stone, "tiles/stone")
	f.parts = {}
	for _, key in ipairs({ "tl", "t", "tr", "l", "r", "bl", "b", "br" }) do
		local tex = f:CreateTexture(nil, "ARTWORK")
		Kit:Apply(tex, FRAME_PIECE)
		f.parts[key] = tex
	end
	f:SetScript("OnSizeChanged", function(self)
		if self.screen then
			AlignStone(self)
		else
			Kit:Retile(self.stone)
		end
	end)
	if Kit.RegisterTexture then
		Kit:RegisterTexture(f.stone)
	end
	f:Hide()
	return f
end

-- Lay a frame out: the nine-slice at k UI units per piece px, the group's
-- background inside the rim.
local function LayoutFrame(f, k, g)
	local name = FRAME_PIECES[Setting(g, "backdrop")] or FRAME_PIECE
	local p = Kit:Piece(name)
	if not p then
		return
	end
	ResetJoins(f)
	if f.piece ~= name then
		f.piece = name
		for _, tex in pairs(f.parts) do
			Kit:Apply(tex, name)
		end
	end
	local c = FRAME_CORNER
	local u0, u1, v0, v1 = p.uv[1], p.uv[2], p.uv[3], p.uv[4]
	local function U(x) return u0 + (u1 - u0) * x / p.w end
	local function V(y) return v0 + (v1 - v0) * y / p.h end
	local cs = c * k
	local parts = f.parts
	local function Place(tex, pa, pb, xa, ya, xb, yb, l, r, t, b)
		tex:ClearAllPoints()
		tex:SetPoint(pa[1], f, pa[2], xa, ya)
		tex:SetPoint(pb[1], f, pb[2], xb, yb)
		tex:SetTexCoord(U(l), U(r), V(t), V(b))
	end
	-- corners (the gems)
	parts.tl:ClearAllPoints(); parts.tl:SetPoint("TOPLEFT"); parts.tl:SetSize(cs, cs); parts.tl:SetTexCoord(U(0), U(c), V(0), V(c))
	parts.tr:ClearAllPoints(); parts.tr:SetPoint("TOPRIGHT"); parts.tr:SetSize(cs, cs); parts.tr:SetTexCoord(U(p.w - c), U(p.w), V(0), V(c))
	parts.bl:ClearAllPoints(); parts.bl:SetPoint("BOTTOMLEFT"); parts.bl:SetSize(cs, cs); parts.bl:SetTexCoord(U(0), U(c), V(p.h - c), V(p.h))
	parts.br:ClearAllPoints(); parts.br:SetPoint("BOTTOMRIGHT"); parts.br:SetSize(cs, cs); parts.br:SetTexCoord(U(p.w - c), U(p.w), V(p.h - c), V(p.h))
	-- edges, stretched between the corners (the rim is even along them)
	Place(parts.t, { "TOPLEFT", "TOPLEFT" }, { "BOTTOMRIGHT", "TOPRIGHT" }, cs, 0, -cs, -cs, c, p.w - c, 0, c)
	Place(parts.b, { "BOTTOMLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" }, cs, 0, -cs, cs, c, p.w - c, p.h - c, p.h)
	-- the rails' coordinates, for the pieces a joined rail is cut into (a
	-- texture's own GetTexCoord answers with its four corners, eight numbers)
	f.railTC = { top = { U(c), U(p.w - c), V(0), V(c) }, bottom = { U(c), U(p.w - c), V(p.h - c), V(p.h) },
		left = { U(0), U(c), V(c), V(p.h - c) }, right = { U(p.w - c), U(p.w), V(c), V(p.h - c) } }
	Place(parts.l, { "TOPLEFT", "TOPLEFT" }, { "BOTTOMRIGHT", "BOTTOMLEFT" }, 0, -cs, cs, cs, 0, c, c, p.h - c)
	Place(parts.r, { "TOPRIGHT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, 0, -cs, -cs, cs, p.w - c, p.w, c, p.h - c)
	-- the background (stone by default) reaches just under the rim's inner edge
	local choice = Setting(g, "background") or "stone"
	local bg = BACKGROUND_PIECES[choice]
	if bg then
		if f.stone.kitName ~= bg then
			Kit:Apply(f.stone, bg)
		end
		f.stone:SetVertexColor(1, 1, 1)
		f.stone.darkFill = nil
		f.stone:Show()
	elseif choice == "dark" then
		if f.stone.kitName ~= nil or not f.stone.darkFill then
			f.stone:SetColorTexture(0.05, 0.045, 0.04, 0.88)
			f.stone.kitPiece, f.stone.kitName, f.stone.darkFill = true, nil, true   -- still ours (a plain mark): never faded with the game's art
		end
		f.stone:Show()
	else
		f.stone:Hide()
	end
	local open = p.open or { 29, 28, 106, 102 }
	f.stoneInset = { (open[1] - 3) * k, (open[2] - 3) * k, (p.w - open[3] - 3) * k, (p.h - open[4] - 3) * k }
	f.stone:ClearAllPoints()
	f.stone:SetPoint("TOPLEFT", f, "TOPLEFT", f.stoneInset[1], -f.stoneInset[2])
	f.stone:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -f.stoneInset[3], f.stoneInset[4])
	Kit:Retile(f.stone)
end

-- Put frame f round the screen rect r (screen px, the buttons' outline):
-- grown by the rim and the gap, in the anchor frame's units. The outline on
-- the screen is kept in bd.rects (the Dynamic UI Modification picker covers it).
local function PlaceFrame(f, anchor, r, k, level, show, g, bd)
	local p = Kit:Piece(FRAME_PIECE)
	if not p then
		return false
	end
	local open = p.open or { 29, 28, 106, 102 }
	local s = anchor:GetEffectiveScale()
	local base = ScreenRect(anchor)
	if not base then
		return false
	end
	local gap = FRAME_GAP * (bd.size or 0) / s
	-- in the anchor's units: the rect, grown by the frame's rim and the gap
	local l = (r[1] - base[1]) / s - open[1] * k - gap
	local b = (r[2] - base[2]) / s - (p.h - open[4]) * k - gap
	local rr = (r[3] - base[1]) / s + (p.w - open[3]) * k + gap
	local t = (r[4] - base[2]) / s + open[2] * k + gap
	bd.rects[#bd.rects + 1] = { base[1] + l * s, base[2] + b * s, base[1] + rr * s, base[2] + t * s }
	if not show then
		f.screen = nil
		f:Hide()
		return true
	end
	-- what the joins need: its screen rect and scales
	f.screen = bd.rects[#bd.rects]
	f.s, f.k, f.ks, f.cs = s, k, k * s, FRAME_CORNER * k
	f:ClearAllPoints()
	f:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", l, b)
	f:SetSize(rr - l, t - b)
	f:SetFrameLevel(level)
	LayoutFrame(f, k, g)
	f:Show()
	return true
end

local function HideGroup(bd)
	if bd.main then
		bd.main:Hide()
	end
	for _, tab in ipairs(bd.tabs) do
		tab:Hide()
	end
end

-- The rect of a set of buttons (the shown ones, screen px) and the size of
-- the smallest one's shorter side.
local function ShownRect(buttons)
	local rect, size
	for _, button in ipairs(buttons) do
		if button:IsShown() then
			-- the rim's rect where it has one (a micro button's rim is a
			-- square on a taller button: the backdrop keeps the same distance
			-- to the rims on every bar)
			local rim = button.melloRep and button.melloRep.object
			local r = (rim and rim.IsShown and rim:IsShown() and ScreenRect(rim)) or ScreenRect(button)
			if r then
				local side = math.min(r[3] - r[1], r[4] - r[2])
				size = size and math.min(size, side) or side
				rect = rect and { math.min(rect[1], r[1]), math.min(rect[2], r[2]), math.max(rect[3], r[3]), math.max(rect[4], r[4]) } or r
			end
		end
	end
	return rect, size
end

-- Action Bar 1 and the bars snapped to it: the backdrop's rect, the button
-- size, and the narrower snapped bars' rects (its tabs)
local function BarsGeometry(main)
	local core, size = ButtonsRect(main)
	if not (core and size and size > 0) then
		return nil
	end
	local members, order = { [main] = core }, {}
	local grew = true
	while grew do
		grew = false
		for _, name in ipairs(BAR_NAMES) do
			local bar = _G[name]
			if bar and bar ~= main and not members[bar] and skin.bars[bar] and bar:IsShown() then
				local r = ButtonsRect(bar)
				if r then
					for _, mr in pairs(members) do
						local gap, beside = Gap(r, mr)
						if beside and gap <= SNAP_GAP * size then
							members[bar], order[#order + 1], grew = r, bar, true
							break
						end
					end
				end
			end
		end
	end
	-- Action Bar 1 widened by every snapped bar lined up with it (a row as
	-- wide, a column as tall), again as it grows
	local rect = { core[1], core[2], core[3], core[4] }
	local pending = order
	repeat
		local rest, widened = {}, false
		for _, bar in ipairs(pending) do
			local r = members[bar]
			local w, h = rect[3] - rect[1], rect[4] - rect[2]
			local overX = math.min(r[3], rect[3]) - math.max(r[1], rect[1])
			local overY = math.min(r[4], rect[4]) - math.max(r[2], rect[2])
			local row = overX >= FULL_WIDTH * w and (r[3] - r[1]) <= w / FULL_WIDTH
			local column = overY >= FULL_WIDTH * h and (r[4] - r[2]) <= h / FULL_WIDTH
			if (row or column) and Gap(r, rect) <= SNAP_GAP * size then
				rect = { math.min(rect[1], r[1]), math.min(rect[2], r[2]), math.max(rect[3], r[3]), math.max(rect[4], r[4]) }
				widened = true
			else
				rest[#rest + 1] = bar
			end
		end
		pending = rest
	until not widened
	local tabs = {}
	for _, bar in ipairs(pending) do
		tabs[#tabs + 1] = members[bar]
	end
	return rect, size, tabs
end

-- Where each group's backdrop hangs
local ANCHORS = {
	bars = function() return _G.MainActionBar or _G.MainMenuBar end,
	micro = function() return _G.MicroMenu end,
	bags = function() return _G.BagsBar end,
}

-- `ks`: screen px per piece px of the rails, the same for every backdrop (so
-- the rails match where two meet); nil: from the group's own buttons
local function LayoutGroup(g, ks)
	local bd = skin and skin.groups[g.id].backdrop
	if not bd then
		return
	end
	bd.rects = {}
	local anchor = ANCHORS[g.id]()
	if not (active and anchor and anchor:IsShown() and #GroupButtons(g) > 0) then
		HideGroup(bd)
		return
	end
	local rect, size, tabs
	if g.id == "bars" then
		if not skin.bars[anchor] then
			HideGroup(bd)
			return
		end
		rect, size, tabs = BarsGeometry(anchor)
	else
		rect, size = ShownRect(GroupButtons(g))
		tabs = {}
	end
	if not (rect and size and size > 0) then
		HideGroup(bd)
		return
	end
	-- Backdrop None: laid out all the same (its outline is what the picker
	-- covers), only not shown
	local show = FRAME_PIECES[Setting(g, "backdrop")] ~= nil
	bd.size = size
	bd.main = bd.main or NewFrame(anchor)
	local s = anchor:GetEffectiveScale()
	-- UI units per piece px: the rim as the slot rims were drawn (97 px of the
	-- slot = one pitch), on Action Bar 1's buttons for every group (user,
	-- 2026-09-23: the bag bar's rails, on its larger buttons, came out
	-- thicker than the micro menu's where the two joined)
	local k = (ks or size / 97) / s
	PlaceFrame(bd.main, anchor, rect, k, 3, show, g, bd)
	-- the narrower snapped bars: a tab each, joined to the backdrop where
	-- they meet (JoinFrames: one shape, an L joint at each step)
	for i, r in ipairs(tabs) do
		bd.tabs[i] = bd.tabs[i] or NewFrame(anchor)
		PlaceFrame(bd.tabs[i], anchor, r, k, 2, show, g, bd)
	end
	for i = #tabs + 1, #bd.tabs do
		bd.tabs[i]:Hide()
	end
end

-- The rails' scale for every backdrop: Action Bar 1's buttons (else each
-- group's own)
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

local function LayoutAll()
	MatchMicroToBags()
	local ks = RailScale()
	for _, g in ipairs(GROUPS) do
		LayoutGroup(g, ks)
	end
	if active and skin then
		JoinFrames()   -- backdrops that meet become one shape
	end
end

local function HideAll()
	if not skin then
		return
	end
	for _, g in ipairs(GROUPS) do
		HideGroup(skin.groups[g.id].backdrop)
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
		Kit:WhenOutOfCombat(LayoutAll)
	end)
end

-- What moves a group: a bar re-laid, shown or hidden, resized, dragged in
-- Edit Mode, Edit Mode closed.
WatchForBackdrop = function(bar)
	if not bar or bar.melloBackdropWatch then
		return
	end
	bar.melloBackdropWatch = true
	bar:HookScript("OnShow", ScheduleBackdrop)
	bar:HookScript("OnHide", ScheduleBackdrop)
	bar:HookScript("OnSizeChanged", ScheduleBackdrop)
	for _, method in ipairs({ "UpdateGridLayout", "Layout", "OnDragStop", "OnSystemPositionChange" }) do
		if type(bar[method]) == "function" then
			hooksecurefunc(bar, method, ScheduleBackdrop)
		end
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
				pitch = pitch, icon = glyph, alsoFade = { button.PushedBackground, button.Shadow, button.PushedShadow } })
			button.melloRep = rep or false
			if rep then
				AddToGroup("micro", button)
				Kit:RegisterButtonRim(button)
			end
			if rep and glyph then
				local others = {}
				for _, tex in ipairs({ button.GetPushedTexture and button:GetPushedTexture(), button.GetHighlightTexture and button:GetHighlightTexture(),
					button.GetDisabledTexture and button:GetDisabledTexture(), (not isPortrait) and button.Portrait or nil }) do
					if tex and tex ~= glyph then
						others[#others + 1] = tex
					end
				end
				local function Follow()
					for _, tex in ipairs(others) do
						tex:ClearAllPoints()
						tex:SetAllPoints(glyph)
					end
				end
				Follow()
				-- the character button re-anchors its portrait on press and
				-- release (CharacterMicroButtonMixin:SetPushed / SetNormal):
				-- back onto the glyph after each
				for _, m in ipairs({ "SetPushed", "SetNormal" }) do
					if type(button[m]) == "function" then
						hooksecurefunc(button, m, function()
							if active and rep.object and rep.object:IsShown() then
								if isPortrait then
									Kit:SlotPlaceIcon(rep.object)   -- the game just re-anchored the portrait
								end
								Follow()
							end
						end)
					end
				end
				-- setting a button's state texture anchors it to fill the
				-- button again, and the game sets the glyph atlas after load
				-- (LoadMicroButtonTextures: the spellbook button on its
				-- update, the guild one on a tabard change; the game menu
				-- one on every net-stats tick): the glyph back into the rim's
				-- opening after each (user, 2026-09-22: "they still don't fit")
				local function Refit()
					if not (active and rep.object and rep.object:IsShown()) then
						return
					end
					local current = button:GetNormalTexture()
					if current and current ~= glyph then
						glyph = current   -- a new texture object: the rim follows it
						rep.object.icon = current
					end
					Kit:SlotPlaceIcon(rep.object)
					Follow()
					if button.melloStone then
						button.melloStone:ClearAllPoints()
						button.melloStone:SetAllPoints(glyph)   -- the stone stays on the (possibly new) glyph
					end
				end
				for _, m in ipairs({ "SetNormalAtlas", "SetNormalTexture", "SetPushedAtlas", "SetHighlightAtlas", "SetDisabledAtlas" }) do
					if type(button[m]) == "function" then
						hooksecurefunc(button, m, Refit)
					end
				end
				button.melloRefitGlyph = Refit
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
			-- backdrop round the bar (user, 2026-09-23)
			local rep = Kit:SkinActionButton(button, Replace, pitch, { as = Kit:ButtonRimRule() })
			if rep then
				AddToGroup("bags", button)
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
		rep.onEnable = function() Flag(true) end
		rep.onDisable = function() Flag(false) end
		if active then
			Flag(true)
		end
		container:HookScript("OnSizeChanged", function()
			if active then
				Kit:WhenOutOfCombat(function() rep:Refit() end)
			end
		end)
	end
	for _, bar in pairs(container.bars or {}) do
		if bar.StatusBar and bar.StatusBar.Background then
			Replace(bar.StatusBar.Background, { as = "UI-HUD-ExperienceBar-Background" })
		end
	end
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

--------------------------------------------------------------------------------
-- Build / lifecycle
--------------------------------------------------------------------------------

local function Build()
	if not skin then
		skin = { reps = {}, bars = {}, status = {}, capSync = {}, groups = {} }
		for _, g in ipairs(GROUPS) do
			skin.groups[g.id] = { buttons = {}, backdrop = { tabs = {}, rects = {} } }
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
	-- a group's choice, live
	local owner = KEY_GROUP[key]
	if not owner then
		return
	end
	local g, role = owner.group, owner.role
	if role == "buttonBackground" then
		ApplyButtonBackground(g, value)
	elseif active then
		LayoutAll()               -- the backdrop on, off, its gems or its background (and the joins with it)
	end
end

-- For the Dynamic UI Modification picker. The groups there are to pick
-- from: { id, title, sections = { { key, title, kind, choices } } }, in order.
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

-- A group's outline on the screen (screen px rects, laid out afresh), nil
-- while its buttons are not skinned or not shown
function M:BarOutline(id)
	local g = GROUP[id or "bars"]
	if not (active and skin and g) then
		return nil
	end
	LayoutAll()   -- every group: the joins between them are laid out together
	local rects = skin.groups[g.id].backdrop.rects
	return rects and #rects > 0 and rects or nil
end

local function Hook()
	if hooked then
		return
	end
	hooked = true
	-- Edit Mode closed: the bars may have been snapped together or apart
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Exit", ScheduleBackdrop, M)
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

function M:OnEnable(db)
	self.db = db
	-- the one Action Bar Border choice of earlier the same day, split in two
	local old = db.border
	if old ~= nil then
		db.barBackdrop = (old == "backdrop" and "red") or (old == "backdrop_iron" and "iron") or "none"
		db.border = nil
	end
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
-- the micro menu, the bag bar, the main status bar). Opens the copy window.
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
		for _, g in ipairs(GROUPS) do
			local bd = skin and skin.groups[g.id] and skin.groups[g.id].backdrop
			for _, f in ipairs({ bd and bd.main, unpack(bd and bd.tabs or {}) }) do
				if f then
					MelloUI:Print("backdrop %s: shown=%s %s L%d", g.id, tostring(f:IsShown()), f:GetFrameStrata(), f:GetFrameLevel())
				end
			end
		end
		MelloUI:ShowLog("abdump icons")
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
