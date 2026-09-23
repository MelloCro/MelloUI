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
-- Covers the Dark Mode group "minimap". /mmdump [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
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
	enabledByDefault = true,
	defaults = { shape = "round", squareBorder = "window" },
	options = {
		{ type = "dropdown", key = "shape", name = "Shape", values = SHAPES,
		  desc = "Round: the map in the painted ring. Square: the whole square map, in the border chosen below." },
		{ type = "dropdown", key = "squareBorder", name = "Square Border", values = BORDERS,
		  desc = "The border round the square map: the windows' frame with its gem corners, a single iron rail, the action bars' heavy frame with red or iron gems, or none. Both are also chosen with previews by Dynamic UI Modification, at the top of the configurator." },
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
	local f = CreateFrame("Frame", nil, MinimapCluster)
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

local function LayoutSquare()
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
		f:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", r - over, -(bo - over))
		local nine = f.nine[b.prefix]
		if not nine then
			nine = Kit:NineSlice(f, { prefix = b.prefix, scale = sc, gems = false, body = false, corners = b.gem and "gem" or nil })
			f.nine[b.prefix] = nine
		end
		nine:Show()
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
	ev:SetScript("OnEvent", function(_, _, name)
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

function M:OnSettingChanged(key, _, db)
	self.db = db
	if key == "shape" or key == "squareBorder" then
		LayoutSquare()
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
