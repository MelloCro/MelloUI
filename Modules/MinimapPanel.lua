--------------------------------------------------------------------------------
-- MelloUI - Minimap Panel
--
-- The minimap cluster dressed in the painted kit (Modules/Kit.lua) on the
-- game's own layout. This client (Blizzard_Minimap/Camelot/Skin.lua) draws a
-- round frame (UI-HUD-Minimap-Frame, 215 x 226) around the 198 px map, the
-- zone band (BorderTop, 175 x 16) above it with the tracking button on its
-- left. User's picks (kit_raw/minimap_catalog.png, 2026-09-21): R1 Z2.
--   R1  the frame → the portrait ring sized from the map's opening x 0.75
--       (user: a quarter smaller, the map untouched), its rim over the map's
--       edge, on a holder one level above the map; the band, its text, the
--       tracking button and the indicators raised above the ring
--   Z2  the zone band → the title plate, as the band's own regions (under
--       its text), standing on the ring's top rim as a title on a rail
--   the tracking button's round plate → the round rim; zoom in / out → the
--   kit's plus / minus. The calendar, mail, crafting-order, landing-page and
--   day / night dial pictures, the compass letters and MelloUI's Services bar
--   stay the game's.
-- Shape (user, 2026-09-23: "Square Minimap with a Square Border of my
-- choosing"): Round (the ring above) or Square: the map's mask a plain
-- square, the ring hidden and a square border of the kit round the map, its
-- inner edge on the map's edge (Square Border: the window frame with its gem
-- corners, the single rail, the heavy backdrop frame with red or iron gems,
-- or none). GetMinimapShape answers "SQUARE" meanwhile, for other addons'
-- minimap buttons.
-- Merge With Services (user, 2026-09-23: "merge the Header, Minimap and the
-- Services window into 1 thing, but there needs to be a border separating the
-- Minimap from the Services Window", example D): with the square shape and a
-- rail border (the window frame or the single rail), one frame runs round the
-- map and MelloUI's Services bar under it; a header plate named "Services"
-- lies between the two, on the frame's stone; the zone band rides the frame's
-- top rail as every window's title plate does (the red plate, its caps' gems
-- on the frame's top corners, which give way), the tracking button and the
-- calendar on its two caps. The game's anchors come back when it is off.
-- The column under the minimap (the map, the Services bar, Route's distance
-- line; the Quest Tracker below it where nobody placed it) is one contract
-- kept here, on or off: M:ColumnSlot, M:ColumnRect, M:LayColumn and the
-- bus's 'column' (below M:Relayout).
-- Covers the Dark Mode group "minimap". /mmdump [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("MinimapPanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Kit = MelloUI.Kit

-- Square Border: `prefix` a kit rail family laid as a nine-slice at `scale`
-- (x Kit.scale), `piece` one frame picture cut into nine (the action bars'
-- backdrop frame: its corner CORNER piece px); `preview` for the picker
local BORDERS = {
	{ value = "window", label = "Window frame", prefix = "window/frame", scale = 1, gem = true, piece = "window/frame_gem_tl" },
	{ value = "single", label = "Single rail", prefix = "window/single", scale = 1.6, piece = "window/single_tl" },
	{ value = "red", label = "Heavy, red gems", piece = "deco/barframe_red" },
	{ value = "iron", label = "Heavy, iron gems", piece = "deco/barframe_iron" },
	{ value = "none", label = "None" },
}
local BORDER = {}
for _, b in ipairs(BORDERS) do
	BORDER[b.value] = b
end
local SHAPES = {
	{ value = "round", label = "Round", piece = "window/portrait_ring" },
	{ value = "square", label = "Square", piece = "deco/barframe_iron" },
}
local CORNER = 40            -- piece px: a backdrop frame's corner square (as ActionBarPanel's)
local ROUND_MASK = "ui-hud-minimap-frame-generic-mask"   -- the game's (Blizzard_Minimap/Camelot/Skin.lua)
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
local HYBRID_ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local M = MelloUI:RegisterModule("MinimapPanel", {
	title = "Minimap Kit",
	desc = "The minimap cluster dressed in the painted kit on the game's own layout.",
	window = { label = "Minimap", desc = "The minimap ring (or a square map in a border of your choosing), zone band and buttons in the kit.", tab = "HUD" },
	enabledByDefault = true,
	defaults = { shape = "round", squareBorder = "window", servicesMerge = true },
	options = {
		{ type = "dropdown", key = "shape", name = "Shape", values = SHAPES,
		  desc = "Round: the map in the painted ring. Square: the whole square map, in the border chosen below." },
		{ type = "dropdown", key = "squareBorder", name = "Square Border", values = BORDERS,
		  desc = "The border round the square map: the windows' frame with its gem corners, a single iron rail, the action bars' heavy frame with red or iron gems, or none. Both are also chosen with previews by Dynamic UI Modification, at the top of the configurator." },
		{ type = "toggle", key = "servicesMerge", name = "Merge With Services",
		  desc = "The square map, its zone header and the Services bar in one frame: the zone name on the frame's top rail, a Services plate between the map and the service icons. For the square shape with the window frame or the single rail." },
	},
})

local skin = nil
local active = false

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Minimap: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

local function Build()
	if skin then
		return
	end
	skin = { reps = {} }
	local cluster = MinimapCluster
	local map = Minimap
	if not (cluster and map) then
		return
	end
	-- the ring (R1): the frame and its rotated-mode pointer / underlay faded,
	-- the ring on a holder at the cluster's level with its opening on the map
	-- the ring one level above the map (its rim lies over the map's edge at
	-- 0.75); the band, its text, the tracking button and the indicators are
	-- raised one level above the ring (they overlap its top), their game
	-- levels put back on disable
	local ringLevel = map:GetFrameLevel() + 1
	skin.ringLevel = ringLevel
	if MinimapCompassTexture then
		local rep = Replace(MinimapCompassTexture, { as = "UI-HUD-Minimap-Frame", parent = cluster, rect = map, level = ringLevel - cluster:GetFrameLevel(),
			alsoFade = { MinimapCompassTextureUnderlay } })
		skin.ring = rep
		if rep then
			local raised = {}
			for _, key in ipairs({ "BorderTop", "ZoneTextButton", "Tracking", "IndicatorFrame" }) do
				local f = cluster[key]
				if f then
					raised[#raised + 1] = { frame = f, level = f:GetFrameLevel() }
				end
			end
			if GameTimeFrame then
				raised[#raised + 1] = { frame = GameTimeFrame, level = GameTimeFrame:GetFrameLevel() }
			end
			rep.onEnable = function()
				for _, entry in ipairs(raised) do
					entry.frame:SetFrameLevel(math.max(ringLevel + 1, entry.level))
				end
			end
			rep.onDisable = function()
				for _, entry in ipairs(raised) do
					entry.frame:SetFrameLevel(entry.level)
				end
			end
			if active then
				rep.onEnable()
			end
		end
	end
	-- the zone band (Z2): the nine-slice's textures faded, the plate as regions
	local band = cluster.BorderTop
	if band then
		local first, extra = nil, {}
		for _, region in ipairs({ band:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not region.kitPiece then
				if first then
					extra[#extra + 1] = region
				else
					first = region
				end
			end
		end
		if first then
			local rep = Replace(first, { as = "MinimapZoneBand", rect = band, alsoFade = extra })
			skin.band = rep
			if rep and MinimapCluster and Kit.RegisterShell then
				-- the cluster's drag handle for the window mover: a grab frame
				-- on the band's own rect (the plate is 1.4 x the band and its
				-- canvas taller than its painted box, so the plate's frame
				-- made an odd click box — user, 2026-09-21)
				local grab = CreateFrame("Frame", nil, band:GetParent() or MinimapCluster)
				grab:SetAllPoints(band)
				grab:SetFrameLevel((band:GetFrameLevel() or 1) + 5)
				grab:EnableMouse(false)
				Kit:RegisterShell(MinimapCluster, { title = grab })
			end
			-- the zone text centred on the plate (user, 2026-09-21); the game's
			-- anchor (LEFT-justified in its button) put back on disable
			local text = MinimapZoneText
			if rep and text then
				local saved = { justify = text:GetJustifyH() }
				for i = 1, text:GetNumPoints() do
					saved[i] = { text:GetPoint(i) }
				end
				local enable = rep.onEnable
				rep.onEnable = function(...)
					if enable then
						enable(...)
					end
					text:ClearAllPoints()
					text:SetPoint("CENTER", band, "CENTER", 0, 0)
					text:SetJustifyH("CENTER")
					Kit:TitleFont(text, true)
				end
				rep.onDisable = function()
					Kit:TitleFont(text, false)
					text:ClearAllPoints()
					for _, pt in ipairs(saved) do
						if type(pt) == "table" then
							text:SetPoint(unpack(pt))
						end
					end
					text:SetJustifyH(saved.justify or "LEFT")
				end
				if active then
					rep.onEnable()
				end
			end
		end
	end
	-- the tracking button's plate, the zoom buttons
	local tracking = cluster.Tracking
	if tracking and tracking.Background then
		Replace(tracking.Background, { as = "ui-hud-minimap-button" })
	end
	for _, entry in ipairs({ { map.ZoomIn, "ui-hud-minimap-zoom-in" }, { map.ZoomOut, "ui-hud-minimap-zoom-out" } }) do
		local button, key = entry[1], entry[2]
		if button and button.GetNormalTexture and button:GetNormalTexture() then
			Replace(button:GetNormalTexture(), { as = key, button = button,
				alsoFade = { button:GetPushedTexture(), button:GetHighlightTexture(), button:GetDisabledTexture() } })
		end
	end
end

--------------------------------------------------------------------------------
-- The square minimap
--------------------------------------------------------------------------------

local savedShapeFn = nil   -- another addon's GetMinimapShape, put back when round

local function SetMask(square)
	local map = Minimap
	if not map then
		return
	end
	pcall(map.SetMaskTexture, map, square and SQUARE_MASK or ROUND_MASK)
	-- a dungeon's own map (Blizzard_HybridMinimap) masks with a circle of its own
	local hybrid = _G.HybridMinimap
	if hybrid and hybrid.CircleMask then
		pcall(hybrid.CircleMask.SetTexture, hybrid.CircleMask, square and SQUARE_MASK or HYBRID_ROUND_MASK)
	end
	if square then
		if not M.shapeFn then
			M.shapeFn = function() return "SQUARE" end
		end
		if _G.GetMinimapShape ~= M.shapeFn then
			savedShapeFn = _G.GetMinimapShape
			_G.GetMinimapShape = M.shapeFn
		end
	elseif M.shapeFn and _G.GetMinimapShape == M.shapeFn then
		_G.GetMinimapShape = savedShapeFn
		savedShapeFn = nil
	end
end

-- The square border's frame on the map, one level above it (the ring's place)
local function BorderFrame()
	if skin.square then
		return skin.square
	end
	-- in the map's own container (Edit Mode's Size scales that, not the
	-- cluster: a frame on the cluster kept its size while the map grew --
	-- user, 2026-09-23: "using the Editmode scaling break the map size")
	local f = CreateFrame("Frame", nil, Minimap:GetParent() or MinimapCluster)
	f:SetFrameLevel(skin.ringLevel or (Minimap:GetFrameLevel() + 1))
	f:EnableMouse(false)
	f.parts = {}
	for _, key in ipairs({ "tl", "t", "tr", "l", "r", "bl", "b", "br" }) do
		f.parts[key] = f:CreateTexture(nil, "ARTWORK")
	end
	f.nine = {}   -- [prefix] = a Kit:NineSlice skin, made on first use
	f:Hide()
	skin.square = f
	return f
end

-- How far a rail family's rails reach inward from their outer edge (the
-- opaque part's inner edge), per side (l, r, t, b), at `sc`
local function RailDepths(prefix, sc)
	local function Depth(name, inner)
		local p = Kit:Piece(name)
		if not (p and p.box) then
			return 0
		end
		local d = inner == "r" and p.box[3] or inner == "l" and (p.w - p.box[1]) or inner == "b" and p.box[4] or (p.h - p.box[2])
		return d * sc
	end
	return Depth(prefix .. "_l", "r"), Depth(prefix .. "_r", "l"), Depth(prefix .. "_t", "b"), Depth(prefix .. "_b", "t")
end

-- A frame picture cut into nine on f (the corners CORNER piece px, the
-- edges stretched between them), k UI units per piece px
local function CutFrame(f, piece, k)
	local p = Kit:Piece(piece)
	if not p then
		return false
	end
	local c = CORNER
	local u0, u1, v0, v1 = p.uv[1], p.uv[2], p.uv[3], p.uv[4]
	local function U(x) return u0 + (u1 - u0) * x / p.w end
	local function V(y) return v0 + (v1 - v0) * y / p.h end
	local cs = c * k
	local parts = f.parts
	for _, tex in pairs(parts) do
		if tex.kitName ~= piece then
			Kit:Apply(tex, piece)
		end
		tex:ClearAllPoints()
		tex:Show()
	end
	parts.tl:SetPoint("TOPLEFT"); parts.tl:SetSize(cs, cs); parts.tl:SetTexCoord(U(0), U(c), V(0), V(c))
	parts.tr:SetPoint("TOPRIGHT"); parts.tr:SetSize(cs, cs); parts.tr:SetTexCoord(U(p.w - c), U(p.w), V(0), V(c))
	parts.bl:SetPoint("BOTTOMLEFT"); parts.bl:SetSize(cs, cs); parts.bl:SetTexCoord(U(0), U(c), V(p.h - c), V(p.h))
	parts.br:SetPoint("BOTTOMRIGHT"); parts.br:SetSize(cs, cs); parts.br:SetTexCoord(U(p.w - c), U(p.w), V(p.h - c), V(p.h))
	parts.t:SetPoint("TOPLEFT", f, "TOPLEFT", cs, 0)
	parts.t:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -cs, -cs)
	parts.t:SetTexCoord(U(c), U(p.w - c), V(0), V(c))
	parts.b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", cs, 0)
	parts.b:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -cs, cs)
	parts.b:SetTexCoord(U(c), U(p.w - c), V(p.h - c), V(p.h))
	parts.l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -cs)
	parts.l:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", cs, cs)
	parts.l:SetTexCoord(U(0), U(c), V(c), V(p.h - c))
	parts.r:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -cs)
	parts.r:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", -cs, cs)
	parts.r:SetTexCoord(U(p.w - c), U(p.w), V(c), V(p.h - c))
	return true
end

-- the merge's measures: the divider band's height (UI px); the cap gem, as
-- Kit:TitleOnRail's (tabs/top caps: the gem's centre from the outer end)
local DIVIDER_H = 26
local CAP_GEM_X = 48

-- Whether the Services bar joins the square map's frame (Services asks too)
function M:WantsServices()
	if not (active and M.db and M.db.shape == "square" and M.db.servicesMerge ~= false) then
		return false
	end
	local b = BORDER[M.db.squareBorder or "window"]
	return b and b.prefix ~= nil or false
end

function M:DividerHeight()
	return DIVIDER_H
end

-- the stone of the frame's family, under the divider and the bar
function M:BodyPiece()
	local b = BORDER[M.db and M.db.squareBorder or "window"]
	return (b and b.prefix or "window/frame") .. "_body"
end

local function ServicesBar()
	local bar = _G.MelloUIServicesBar
	if bar and bar:IsShown() then
		return bar
	end
	return nil
end

-- The divider: the frame's stone across the map's width under it, a header
-- plate on it with "Services" in the title face
local function Divider(f)
	if skin.divider then
		return skin.divider
	end
	local d = CreateFrame("Frame", nil, f)
	d:SetFrameLevel(f:GetFrameLevel() + 1)
	d:EnableMouse(false)
	d.stone = d:CreateTexture(nil, "BACKGROUND")
	d.stone:SetAllPoints(d)
	local ok, plate = pcall(Kit.Strip, Kit, d, "lists/header", { scale = Kit.scale })
	d.plate = ok and plate or nil
	-- the name on a layer above the plate (the plate is a child frame of the
	-- divider and drew over the divider's own text)
	d.textLayer = CreateFrame("Frame", nil, d)
	d.textLayer:SetAllPoints(d)
	d.textLayer:SetFrameLevel(d:GetFrameLevel() + 4)
	d.text = d.textLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	d.text:SetText("Services")
	d:Hide()
	skin.divider = d
	return d
end

local function LayoutDivider(f, b)
	local d = Divider(f)
	local map = Minimap
	d:ClearAllPoints()
	d:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, 0)
	d:SetPoint("TOPRIGHT", map, "BOTTOMRIGHT", 0, 0)
	d:SetHeight(DIVIDER_H)
	local piece = b.prefix .. "_body"
	if d.stone.kitName ~= piece then
		Kit:Apply(d.stone, piece)
	end
	Kit:Retile(d.stone)
	local plate = d.plate
	local dy = 0
	if plate then
		local h = DIVIDER_H - 4
		local yoff = plate.FitBox and plate:FitBox(h) or 0
		plate:ClearAllPoints()
		plate:SetPoint("LEFT", d, "LEFT", 0, yoff)
		plate:SetPoint("RIGHT", d, "RIGHT", 0, yoff)
		plate:SetHeight(plate.height)
		local okW, w = pcall(d.GetWidth, d)
		if okW and w and not (issecretvalue and issecretvalue(w)) and w > 0 and plate.FitCaps then
			plate:FitCaps(w)
		end
	end
	d.text:ClearAllPoints()
	d.text:SetPoint("CENTER", d, "CENTER", 0, dy)
	Kit:TitleFont(d.text, true)
	d:Show()
end

-- The zone band on the frame's top rail (merged) or back where the game put
-- it, with the tracking button, the calendar and the zone text's width
local function PlaceBand(merged, f, b)
	local cluster = MinimapCluster
	local band = cluster and cluster.BorderTop
	local rep = skin.band
	if not band then
		return
	end
	local movers = { band, cluster.Tracking, _G.GameTimeFrame, _G.TimeManagerClockButton }
	if merged then
		if not skin.bandSaved then
			local saved = {}
			for i, frame in ipairs(movers) do
				if frame then
					local pts = {}
					for j = 1, frame:GetNumPoints() do
						pts[j] = { frame:GetPoint(j) }
					end
					saved[i] = { points = pts, w = frame:GetWidth(), scale = frame:GetScale(), level = frame:GetFrameLevel() }
				end
			end
			saved.textWidth = MinimapZoneText and MinimapZoneText:GetWidth()
			skin.bandSaved = saved
		end
		-- each at the frame's (the map's) scale, one after the other (a
		-- button inside the band follows it; its own ratio is then 1)
		for i, frame in ipairs(movers) do
			if frame and skin.bandSaved[i] then
				local okE, fe = pcall(f.GetEffectiveScale, f)
				local okM, me = pcall(frame.GetEffectiveScale, frame)
				if okE and okM and fe and me and me > 0 then
					frame:SetScale(frame:GetScale() * fe / me)
				end
			end
		end
		local sc = Kit.scale * (b.scale or 1)
		local rail = Kit:Piece(b.prefix .. "_t")
		local middle = rail and rail.box and (rail.box[2] + rail.box[4]) / 2 * sc or 9
		-- the plate is 1.4 x the band (MinimapZoneBand): the band sized so the
		-- plate spans the frame, its caps' gems on the frame's top corners
		local strip = rep and rep.strip
		local ss = strip and strip.scale or Kit.scale
		local okW, fw = pcall(f.GetWidth, f)
		if not (okW and fw and not (issecretvalue and issecretvalue(fw)) and fw > 0) then
			return
		end
		local reach = CAP_GEM_X * ss - 20 * sc
		local plateW = fw + 2 * reach
		local bandW = plateW / 1.4
		band:ClearAllPoints()
		band:SetPoint("CENTER", f, "TOP", 0, -middle)
		band:SetWidth(bandW)
		if strip and strip.SetState then
			strip:SetState("open")
		end
		if rep and rep.Refit then
			rep:Refit()
		end
		-- the tracking button and the calendar on the caps' gems
		local over = bandW * 0.2
		local tracking, clock = cluster.Tracking, _G.GameTimeFrame
		if tracking then
			tracking:ClearAllPoints()
			tracking:SetPoint("CENTER", band, "LEFT", -over + CAP_GEM_X * ss, 0)
		end
		if clock then
			clock:ClearAllPoints()
			clock:SetPoint("CENTER", band, "RIGHT", over - CAP_GEM_X * ss, 0)
		end
		if MinimapZoneText then
			MinimapZoneText:SetWidth(math.max(40, plateW - 2 * 70 * ss))
		end
		-- the clock on the Services plate's right end, clear of the header
		local timeButton = _G.TimeManagerClockButton
		local d = skin.divider
		if timeButton and d then
			timeButton:ClearAllPoints()
			timeButton:SetPoint("RIGHT", d, "RIGHT", -DIVIDER_H * 1.6, 0)
			timeButton:SetFrameLevel(d:GetFrameLevel() + 6)
		end
		skin.bandMerged = true
	elseif skin.bandMerged then
		local saved = skin.bandSaved or {}
		for i, frame in ipairs(movers) do
			local entry = saved[i]
			if frame and entry then
				frame:ClearAllPoints()
				for _, pt in ipairs(entry.points) do
					frame:SetPoint(unpack(pt))
				end
				if i == 1 and entry.w then
					frame:SetWidth(entry.w)
				end
				if entry.scale then
					frame:SetScale(entry.scale)
				end
				if entry.level then
					frame:SetFrameLevel(entry.level)
				end
			end
		end
		if MinimapZoneText and saved.textWidth then
			MinimapZoneText:SetWidth(saved.textWidth)
		end
		local strip = rep and rep.strip
		if strip and strip.SetState then
			strip:SetState("title")
		end
		if rep and rep.Refit then
			rep:Refit()
		end
		skin.bandMerged = nil
		skin.bandSaved = nil
	end
end

local function LaySquare()
	local square = active and M.db and M.db.shape == "square"
	SetMask(square)
	if not skin then
		return
	end
	local ring = skin.ring
	if ring and ring.object then
		ring.object:SetShown(active and not square)
	end
	local f = BorderFrame()
	local b = BORDER[M.db and M.db.squareBorder or "window"] or BORDER.window
	local merged = square and M:WantsServices() and ServicesBar() ~= nil
	if not merged then
		PlaceBand(false)
		if skin.divider then
			skin.divider:Hide()
		end
	end
	if not square or b.value == "none" then
		f:Hide()
		return
	end
	local map = Minimap
	for _, tex in pairs(f.parts) do
		tex:Hide()
	end
	for _, nine in pairs(f.nine) do
		nine:Hide()
	end
	local over = 1   -- UI px: the rail's inner edge just over the map's, no line of world between
	f:ClearAllPoints()
	if b.prefix then
		local sc = Kit.scale * b.scale
		local l, r, t, bo = RailDepths(b.prefix, sc)
		f:SetPoint("TOPLEFT", map, "TOPLEFT", -(l - over), t - over)
		if merged then
			-- down round the Services bar (as wide as the map, under it)
			f:SetPoint("BOTTOMRIGHT", ServicesBar(), "BOTTOMRIGHT", r - over, -(bo - over))
		else
			f:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", r - over, -(bo - over))
		end
		local nine = f.nine[b.prefix]
		if not nine then
			nine = Kit:NineSlice(f, { prefix = b.prefix, scale = sc, gems = false, body = false, corners = b.gem and "gem" or nil })
			f.nine[b.prefix] = nine
		end
		nine:Show()
		-- merged: the zone band's caps take the top corners
		if nine.SetTopGems then
			nine:SetTopGems(not merged)
		end
		if merged then
			LayoutDivider(f, b)
			f:Show()
			PlaceBand(true, f, b)
			return
		end
	else
		local p = Kit:Piece(b.piece)
		local k = Kit.scale
		local open = (p and p.open) or { 29, 34, 106, 97 }
		local w, h = p and p.w or 135, p and p.h or 130
		f:SetPoint("TOPLEFT", map, "TOPLEFT", -(open[1] * k - over), open[2] * k - over)
		f:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", (w - open[3]) * k - over, -((h - open[4]) * k - over))
		if not CutFrame(f, b.piece, k) then
			f:Hide()
			return
		end
	end
	f:Show()
end

-- the map's frame laid, then the column under it (below): what hangs from
-- it follows on the next frame
local function LayoutSquare()
	LaySquare()
	M:LayColumn()
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
	LayoutSquare()
	Kit:Cover("minimap")
end


local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	LayoutSquare()   -- the round mask and the game's shape answer back
	Kit:Uncover("minimap")
end

local hooked = false
local function Hook()
	if hooked then
		return
	end
	hooked = true
	-- Edit Mode's Size scales the map's container: the merged frame's band,
	-- buttons and clock follow it at once
	local container = Minimap and Minimap:GetParent()
	if container and container ~= MinimapCluster and container.SetScale then
		hooksecurefunc(container, "SetScale", function()
			C_Timer.After(0, function()
				if active then
					M:Relayout()
				end
			end)
		end)
	end
	-- the UI Scale changed (user, 2026-09-24: "UI Scaling Break the UI"): the
	-- merged band and its buttons were scaled to the frame's EFFECTIVE scale
	-- (PlaceBand), measured at the old UI scale; laid out again with the rest
	if Kit.OnUIScaleChanged then
		Kit:OnUIScaleChanged(function(reason)
			if reason == "uiscale" and active then
				Kit:WhenOutOfCombat(function()
					if active then
						M:Relayout()
					end
				end)
			end
		end)
	end
	-- the game sets the round mask again when the minimap's rotation is
	-- switched (UpdateMinimapConfig); the square one after it
	if CVarCallbackRegistry and CVarCallbackRegistry.RegisterCallback then
		CVarCallbackRegistry:RegisterCallback("rotateMinimap", function()
			C_Timer.After(0, function()
				if active then
					LayoutSquare()
				end
			end)
		end, M)
	end
	-- a dungeon's own map, loaded on demand
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("ADDON_LOADED")
	Perf.SetScript(ev, "OnEvent", function(_, _, name)
		if name == "Blizzard_HybridMinimap" and active then
			LayoutSquare()
		end
	end)
end

function M:OnEnable(db)
	self.db = db
	Hook()
	if MinimapCluster then
		Activate()
	end
end

-- the Services bar joins or leaves the frame: it lays itself out first
local function LayoutWithServices()
	local services = MelloUI:GetModule("Services")
	if services and services.isEnabled and services.LayoutForMinimap then
		services:LayoutForMinimap()
	end
	LayoutSquare()
end

-- Services calls this after laying its bar out (Edit Mode, its settings)
function M:Relayout()
	LayoutSquare()
end

--------------------------------------------------------------------------------
-- The column under the minimap (audit, 2026-09-24, rank 18; user, 2026-09-25:
-- "everything should be lined up and working flawlessly with one another").
-- One contract for what stands under the map, top to bottom: the map's block
-- (the map with its zone band; the square border round it, or the merged
-- frame that runs round the Services bar too), the Services bar while it
-- shows and is not merged into that frame, and Route's distance line. Kept
-- here whether this module is on or not (the minimap's column either way):
--   M:ColumnSlot(part)  where a part hangs its TOP from: region, its point,
--                       x, y ("services": the bar, "route": the distance line)
--   M:ColumnRect()      the stack on the screen, the distance line's slot
--                       included while Route keeps the line: left, bottom,
--                       right, top in screen pixels; nil when a rect cannot
--                       be read plainly
--   M:LayColumn()       something in it changed: the bus's 'column' goes out
--                       on the next frame, once for everything of that frame
-- Services hangs its bar and Route its line from it; the Quest Tracker hangs
-- below its bottom only where nobody placed it (QuestTracker.lua). The places
-- are the ones they had -- the bar under the map by its offset (by the
-- divider's height merged), the line 2 px under the map (inside the square
-- border and the merged frame too, as before) -- except that the line goes
-- under the bar where a bar offset leaves it no room. The pairwise calls
-- above (WantsServices, DividerHeight, BodyPiece, Relayout) stay as they were.
--------------------------------------------------------------------------------

local LINE_GAP = 2        -- the distance line under what it hangs from
local LINE_H = 12         -- its height when Route cannot say

local Num = MelloUI.Safe.Number

-- a region's edges on the screen (pixels); nil when one cannot be read plainly
local function ScreenRect(region)
	if not region then
		return nil
	end
	local ok, l, b, w, h = pcall(region.GetRect, region)
	if not ok then
		return nil
	end
	l, b, w, h = Num(l), Num(b), Num(w), Num(h)
	local okS, s = pcall(region.GetEffectiveScale, region)
	s = okS and Num(s) or nil
	if not (l and b and w and h and s) then
		return nil
	end
	return l * s, b * s, (l + w) * s, (b + h) * s
end

local Column = {}

-- the Services bar merged into the square map's frame (Services asks the
-- very same: the minimap's cover, this module on, and its WantsServices)
function Column.Merged()
	return Kit:IsCovered("minimap") and M.isEnabled and M:WantsServices() and true or false
end

-- the map's block: the square border's frame while it shows round the map
-- (merged, it runs round the Services bar too), else the map
function Column.Block()
	local f = skin and skin.square
	if active and f and f:IsShown() then
		return f
	end
	return Minimap
end

-- the Services bar while it shows beside the block, not merged into it
function Column.LooseBar()
	local bar = ServicesBar()
	if bar and not Column.Merged() then
		return bar
	end
	return nil
end

-- the distance line's height while Route keeps it, else nil
function Column.LineHeight()
	local route = MelloUI:GetModule("Route")
	return route and route.ColumnLine and route:ColumnLine() or nil
end

function M:ColumnSlot(part)
	local map = Minimap
	if part == "services" then
		if Column.Merged() then
			return map, "BOTTOM", 0, -DIVIDER_H
		end
		local services = MelloUI:GetModule("Services")
		local db = services and services.db
		return map, "BOTTOM", 0, tonumber(db and db.barOffset) or -26
	end
	-- the distance line: 2 px under the map as it always lay (square and
	-- merged too: nothing moves for a user who changes nothing, user,
	-- 2026-09-25), or under the bar where a bar offset leaves it no room there
	-- (measured on the screen; under the map when that cannot be read)
	local bar = Column.LooseBar()
	if bar then
		local _, bottom = ScreenRect(map)
		local _, barBottom, _, barTop = ScreenRect(bar)
		local okS, s = pcall(map.GetEffectiveScale, map)
		s = okS and Num(s) or nil
		if bottom and barBottom and s then
			local top = bottom - LINE_GAP * s
			local h = Column.LineHeight() or LINE_H
			if top - h * s < barTop and top > barBottom then
				return bar, "BOTTOM", 0, -LINE_GAP
			end
		end
	end
	return map, "BOTTOM", 0, -LINE_GAP
end

function M:ColumnRect()
	local l, b, r, t = ScreenRect(Column.Block())
	if not l then
		return nil
	end
	local bar = Column.LooseBar()
	if bar then
		local bl, bb, br, bt = ScreenRect(bar)
		if not bl then
			return nil
		end
		l, b, r, t = math.min(l, bl), math.min(b, bb), math.max(r, br), math.max(t, bt)
	end
	local h = Column.LineHeight()
	if h then
		local rel, _, _, y = self:ColumnSlot("route")
		local _, relBottom = ScreenRect(rel)
		local okS, s = pcall(Minimap.GetEffectiveScale, Minimap)
		s = okS and Num(s) or nil
		if not (relBottom and s) then
			return nil
		end
		b = math.min(b, relBottom + (y - h) * s)
	end
	return l, b, r, t
end

function Column.Fire()
	MelloUI:Fire("column")
end

function M:LayColumn()
	if Kit.NextFrame then
		Kit:NextFrame("Minimap column", Column.Fire)
	else
		C_Timer.After(0, Column.Fire)
	end
end

-- What moves the column without the map's frame being laid again: Route's
-- line (or Route) switched, the minimap cluster dragged by the window mover
-- (its place is a setting) or UI Modifications switched, Edit Mode closed
-- (the map moved or sized there), the UI Scale, a Font Style (the line's
-- height), a profile; and the world entered and Edit Mode's layout applied
-- (at login the map and the game's tracker take their places then). Heard
-- whether this module is on or not; each only asks for the next frame's
-- 'column'.
function Column.Lay()
	M:LayColumn()
end

MelloUI:On("setting", function(module, key)
	if (module == "Route" and key == "distanceText") or (module == "UIModifications" and key == "positions") then
		M:LayColumn()
	end
end, "Minimap column")
MelloUI:On("module", function(name)
	if name == "Route" or name == "UIModifications" then
		M:LayColumn()
	end
end, "Minimap column")
MelloUI:On("editmode", function(entering)
	if not entering then
		M:LayColumn()
	end
end, "Minimap column")
MelloUI:On("scale", Column.Lay, "Minimap column")
MelloUI:On("fonts", Column.Lay, "Minimap column")
MelloUI:On("restart", Column.Lay, "Minimap column")
do
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	pcall(ev.RegisterEvent, ev, "EDIT_MODE_LAYOUTS_UPDATED")
	Perf.SetScript(ev, "OnEvent", Column.Lay)
end

function M:OnSettingChanged(key, _, db)
	self.db = db
	if key == "shape" or key == "squareBorder" or key == "servicesMerge" then
		LayoutWithServices()
	end
end

-- For the Dynamic UI Modification picker (Modules/DynamicUI.lua)
function M:PickerGroups()
	return { { id = "minimap", title = "Minimap", hint = "Click to choose the minimap's shape and its square border.", sections = {
		{ key = "shape", title = "Shape", kind = "frame", choices = SHAPES },
		{ key = "squareBorder", title = "Square Border", kind = "frame", choices = BORDERS },
	} } }
end

function M:BarOutline()
	local map = Minimap
	if not (active and map and map:IsShown()) then
		return nil
	end
	local ok, l, b, w, h = pcall(map.GetRect, map)
	if not (ok and l and w) or (issecretvalue and (issecretvalue(l) or issecretvalue(w))) or w <= 0 then
		return nil
	end
	local sc = map:GetEffectiveScale()
	return { { l * sc, b * sc, (l + w) * sc, (b + h) * sc } }
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /mmdump [frames|reps]: the cluster's art. Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOMMDUMP1 = "/mmdump"
SlashCmdList.MELLOMMDUMP = function(msg)
	msg = (msg or ""):lower()
	MelloUI:ClearLog()
	if not MinimapCluster then
		MelloUI:Print("No minimap cluster.")
	else
		MelloUI:Print("== MinimapCluster  %s L%d; Minimap L%d; backdrop L%d", MinimapCluster:GetFrameStrata(), MinimapCluster:GetFrameLevel(),
			Minimap and Minimap:GetFrameLevel() or -1, MinimapBackdrop and MinimapBackdrop:GetFrameLevel() or -1)
		Kit:DumpWindow(MinimapCluster, skin, msg ~= "" and msg or nil)
	end
	MelloUI:ShowLog("mmdump " .. msg)
end
