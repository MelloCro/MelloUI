--------------------------------------------------------------------------------
-- MelloUI - Minimap Kit (the painted minimap)
--
-- (onelook D7) The painted half of the minimap, split out of MinimapPanel.lua: MelloUI's minimap itself (its Width
-- and Height, the square mask, the Chat panel, the Services merge, the column under it, its lifecycle) is the core
-- module MinimapPanel. This file dresses it in the painted kit (Modules/Kit.lua) through the one dresser it registers
-- there at load (Core:SetDresser, below): while this module is on (UI Modifications' reskin and its Painted Skin,
-- UIModifications.MinimapKit) and the core minimap is, the core hands the map to it and lays its frame through it.
-- Oldschool's (MelloUI_Oldschool takes this file at the split, unchanged).
-- User's picks (kit_raw/minimap_catalog.png, 2026-09-21): R1 Z2.
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
-- The square map's painted borders (Square Border, the core's values): the window frame with its gem corners and the
-- single rail (a kit rail family laid as a nine-slice, LayRails), the heavy backdrop frames with red or iron gems (a
-- picture cut into eight, LayPicture), and the border library's rims (Kit:NewBorder, laid by the core): each only
-- while this skin dresses the map -- without it the core falls back to its Chat panel (the user's pick 1C). The zone
-- band rides the frame's top rail as every window's title plate does (BandOnRail: the red plate, its caps' gems on
-- the frame's top corners, the tracking button and the calendar on its two caps).
-- Covers the Dark Mode group "minimap" (Kit:Cover): Services' kit rims and box follow it.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Kit = MelloUI.Kit
local ScreenRect = MelloUI.Safe.ScreenRect
-- what the kit keeps beside the game's frames (Kit.lua: weak-keyed, never keys on them)
local pieceOf = MelloUI.Kept.pieceOf

-- the core minimap, and what it lends its dresser (MinimapPanel's M.Lay); an older MinimapPanel.lua has neither
local Core = MelloUI:GetModule("MinimapPanel")
if not (Core and Core.SetDresser and Core.Lay) then
	return
end
local L = Core.Lay
local Shade = L.Shade

local CORNER = 40            -- piece px: a backdrop frame's corner square (as ActionBarPanel's)
-- the cap gem, as Kit:TitleOnRail's (tabs/top caps: the gem's centre from the outer end)
local CAP_GEM_X = 48

local M = MelloUI:RegisterModule("MinimapKit", {
	title = "Minimap Kit",
	desc = "The minimap dressed in the painted kit: the ring round the map (or the square map's painted border), the zone plate, the tracking button's rim and the zoom buttons.",
	window = { label = "Minimap", desc = "The minimap ring (or a square map in a painted border of your choosing), zone band and buttons in the kit.", tab = "HUD" },
	enabledByDefault = true,
})

local skin = nil
local dressed = false

-- a heavy frame's eight parts (Kit:CutNine's), each with the same cut of the
-- frame's shadow (piece px; its reach past the picture's outer sides only),
-- once: CutNine cuts them again at every lay. `corner`: the piece's cut (a
-- border library style's own, 0.19.8; the backdrop frames' CORNER else)
local cutDone = false
local function ShadeCut(parts, piece, corner)
	local p = Kit:Piece(piece)
	if cutDone or not (p and p.w and p.h) then
		return
	end
	cutDone = true
	local c, w, h = corner or CORNER, p.w, p.h
	local cuts = { tl = { 0, c, 0, c }, tr = { w - c, w, 0, c }, bl = { 0, c, h - c, h }, br = { w - c, w, h - c, h },
		t = { c, w - c, 0, c }, b = { c, w - c, h - c, h }, l = { 0, c, c, h - c }, r = { w - c, w, c, h - c } }
	for key, cut in pairs(cuts) do
		Shade.Add(parts[key], { cut = cut })
	end
end

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
	if dressed then
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
	-- levels put back on disable. Every level here is kept as an OFFSET from
	-- the map's (user, 2026-09-26: the column and the Quest Tracker took
	-- turns on top): the cluster is toplevel, a click in it lifts the whole
	-- tree, and a level saved as a number put the band and its buttons back
	-- under the lifted map on the next re-skin.
	local ringLevel = map:GetFrameLevel() + 1
	if MinimapCompassTexture then
		local rep = Replace(MinimapCompassTexture, { as = "UI-HUD-Minimap-Frame", parent = cluster, rect = map, level = ringLevel - cluster:GetFrameLevel(),
			alsoFade = { MinimapCompassTextureUnderlay } })
		skin.ring = rep
		Shade.Add(rep, Shade.DRAWN)   -- (hidden with its holder: the square shape)
		if rep then
			local raised = {}
			for _, key in ipairs({ "BorderTop", "ZoneTextButton", "Tracking", "IndicatorFrame" }) do
				local f = cluster[key]
				if f then
					raised[#raised + 1] = { frame = f, offset = f:GetFrameLevel() - map:GetFrameLevel() }
				end
			end
			if GameTimeFrame then
				raised[#raised + 1] = { frame = GameTimeFrame, offset = GameTimeFrame:GetFrameLevel() - map:GetFrameLevel() }
			end
			rep.onEnable = function()
				local base = map:GetFrameLevel()
				for _, entry in ipairs(raised) do
					entry.frame:SetFrameLevel(base + math.max(2, entry.offset))
				end
			end
			rep.onDisable = function()
				local base = map:GetFrameLevel()
				for _, entry in ipairs(raised) do
					entry.frame:SetFrameLevel(math.max(0, base + entry.offset))
				end
			end
			if dressed then
				rep.onEnable()
			end
		end
	end
	-- the zone band (Z2): the nine-slice's textures faded, the plate as regions (client 70425: the zone button's
	-- own art -- the core's Band)
	local band = Core.Lay.Band()
	if band then
		local first, extra = nil, {}
		for _, region in ipairs({ band:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not pieceOf[region] then
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
			Shade.Add(rep)
			-- (no drag handle of its own: the minimap cluster is moved on its
			-- plate in Edit Layout, which covers the whole cluster)
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
				if dressed then
					rep.onEnable()
				end
			end
		end
	end
	-- the tracking button's plate, the zoom buttons
	local tracking = cluster.Tracking
	if tracking and tracking.Background then
		-- (its rim drawn square to the button's plate, not at its kitScale)
		Shade.Add(Replace(tracking.Background, { as = "ui-hud-minimap-button" }), Shade.DRAWN)
	end
	for _, entry in ipairs({ { map.ZoomIn, "ui-hud-minimap-zoom-in" }, { map.ZoomOut, "ui-hud-minimap-zoom-out" } }) do
		local button, key = entry[1], entry[2]
		if button and button.GetNormalTexture and button:GetNormalTexture() then
			Replace(button:GetNormalTexture(), { as = key, button = button,
				alsoFade = { button:GetPushedTexture(), button:GetHighlightTexture(), button:GetDisabledTexture() } })
		end
	end
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

-- How far a rail family's bottom gem corners paint below the frame, in the
-- frame's units at `sc` (Kit:NineSlice sets each gem's canvas its overhang
-- past the frame's corner; the clear rows under its box give some of it
-- back): 0 without gem corners
local function GemReach(prefix, sc)
	local reach = 0
	for i = 1, 2 do
		local p = Kit:Piece(prefix .. (i == 1 and "_gem_bl" or "_gem_br"))
		if p and p.overhang and p.box and p.h then
			reach = math.max(reach, p.overhang - (p.h - p.box[4]))
		end
	end
	return reach * sc
end

--------------------------------------------------------------------------------
-- The dresser: what the core asks of the painted skin (MinimapPanel.lua's Dress and LaySquare). `on`: this module's
-- switch; the core dresses while it and itself are on (Dress.Sync) and hands back what it holds on the game's
-- regions first (the zone band's art and name, the game's ring), so the fades here record the game's own.
--------------------------------------------------------------------------------
local Dresser = { module = "MinimapKit", on = false }

-- the skin built (once) and put on, or taken off: the game's art back. (Built while already dressed, as the old
-- Activate built it: each piece put on as it is made, so the band's plate is made over the band raised above the ring;
-- then every piece put on, as ever.)
function Dresser:Dress(on)
	if on then
		dressed = true
		Build()
		for _, rep in ipairs(skin.reps) do
			rep:Enable()
		end
	elseif skin and dressed then
		dressed = false
		for _, rep in ipairs(skin.reps) do
			rep:Disable()
		end
	end
end

-- the minimap's look area: covered while the painted minimap is on (Services' kit rims and box, Dark Mode's gate)
function Dresser:Covered(on)
	if on then
		Kit:Cover("minimap")
	else
		Kit:Uncover("minimap")
	end
end

-- the Square Borders this skin draws: every one but the Chat panel and None (the core's own)
function Dresser:Owns(b)
	return b ~= nil and not b.panel and b.value ~= "none"
end

-- the ring sized from the shown part (cw x ch): its opening on the map's (Size.Place)
function Dresser:RingSize(cw, ch)
	local ring = skin and skin.ring
	local p = ring and ring.tex and ring.rule and Kit:Piece(ring.rule.piece)
	if p and p.w and p.open and p.open[3] > p.open[1] then
		local size = math.min(cw, ch) * p.w / (p.open[3] - p.open[1]) * (ring.rule.openingScale or 1)
		ring.tex:SetSize(size, size)
	end
end

-- the ring shown round the round map, hidden on the square one
function Dresser:RingShown(show)
	local ring = skin and skin.ring
	if ring and ring.object then
		ring.object:SetShown(show and true or false)
	end
end

-- the ring's opaque part on the screen (its piece's box on its canvas) while it shows: left, bottom, right, top;
-- nil while it is hidden or cannot be read (the core's Column.Frame then takes the map's block)
function Dresser:RingRect()
	local ring = skin and skin.ring
	local tex = ring and ring.tex
	if tex and ring.object and ring.object:IsShown() then
		local l, b, r, t = ScreenRect(tex)
		local p = l and ring.rule and Kit:Piece(ring.rule.piece)
		if p and p.box and p.w and p.h and p.w > 0 and p.h > 0 then
			local w, h = r - l, t - b
			return l + p.box[1] / p.w * w, t - p.box[4] / p.h * h, l + p.box[3] / p.w * w, t - p.box[2] / p.h * h
		end
		if l then
			return l, b, r, t
		end
	end
	return nil
end

-- the zone band's plate (Z2), 1.4 x the band (the core's Size.Drop reads how low it hangs)
function Dresser:BandPlate()
	return skin and skin.band and skin.band.strip or nil
end

-- the plate shown or hidden under the Chat panel's zone row (the game's art stays faded under it)
function Dresser:PlateShown(on)
	local plate = self:BandPlate()
	if plate then
		plate:SetAlpha(on and 1 or 0)
	end
end

-- another border after the Chat panel: the plate shown again, the zone name
-- centred on it as the band's dressing laid it (its onEnable)
function Dresser:BandUnpanel()
	self:PlateShown(true)
	local text = MinimapZoneText
	local band = Core.Lay.Band()
	if text and band then
		text:ClearAllPoints()
		text:SetPoint("CENTER", band, "CENTER", 0, 0)
		text:SetJustifyH("CENTER")
	end
end

-- The zone band on the frame's top rail (the core's PlaceBand, its movers saved and scaled to the frame already),
-- with the tracking button, the calendar and the zone text's width; `groups`: Services' one row of groups (the
-- core's ServicesRow), the clock on the band. -> false when the frame's width cannot be read plainly (nothing laid)
function Dresser:BandOnRail(f, b, groups)
	local cluster = MinimapCluster
	local band = Core.Lay.Band()
	local rep = skin and skin.band
	if not band then
		return false
	end
	local sc = Kit.scale * (b.scale or 1)
	local rail = b.prefix and Kit:Piece(b.prefix .. "_t")
	local middle = rail and rail.box and (rail.box[2] + rail.box[4]) / 2 * sc or 9
	local side = 20 * sc   -- (the side rail's depth the plate's caps reach past)
	-- (0.20.1) a library style's rails inside the frame: the top rail's middle and the side rail's depth its own
	local lib = not b.prefix and f.library
	if lib then
		local ix, iy = lib:Inset()
		middle, side = iy / 2, ix
	end
	-- the plate is 1.4 x the band (MinimapZoneBand): the band sized so the
	-- plate spans the frame, its caps' gems on the frame's top corners
	local strip = rep and rep.strip
	local ss = strip and strip.scale or Kit.scale
	local okW, fw = pcall(f.GetWidth, f)
	if not (okW and fw and not (issecretvalue and issecretvalue(fw)) and fw > 0) then
		return false
	end
	local reach = CAP_GEM_X * ss - side
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
	-- the clock on the Services plate's right end, clear of the header;
	-- with Services' one row of groups (layout E) on the zone band's
	-- right end, just inside the calendar, the zone name kept
	-- as far clear of it at both ends
	local timeButton = _G.TimeManagerClockButton
	local d = L.Divider()
	-- (the clock on the Services rail only while that rail shows: merged
	-- with Services' two rows; else on the band, beside the calendar)
	local onRail = not groups and d and d:IsShown()
	if MinimapZoneText then
		if timeButton and not onRail then
			local margin = CAP_GEM_X * ss + L.PlainWidth(clock, 19) / 2 + 2 + L.PlainWidth(timeButton, 40) + 4
			MinimapZoneText:SetWidth(math.max(40, plateW - 2 * math.max(70 * ss, margin)))
		else
			MinimapZoneText:SetWidth(math.max(40, plateW - 2 * 70 * ss))
		end
	end
	if timeButton and not onRail then
		timeButton:ClearAllPoints()
		if clock then
			timeButton:SetPoint("RIGHT", clock, "LEFT", -2, 0)
		else
			timeButton:SetPoint("RIGHT", band, "RIGHT", over - CAP_GEM_X * ss, 0)
		end
		timeButton:SetFrameLevel(band:GetFrameLevel() + 2)
	elseif timeButton then
		timeButton:ClearAllPoints()
		timeButton:SetPoint("RIGHT", d, "RIGHT", -L.DIVIDER_H * 1.6, 0)
		timeButton:SetFrameLevel(d:GetFrameLevel() + 6)
	end
	return true
end

-- the band back on the game's place (the core's PlaceBand put its movers back): the plate a title again
function Dresser:BandHome()
	local rep = skin and skin.band
	local strip = rep and rep.strip
	if strip and strip.SetState then
		strip:SetState("title")
	end
	if rep and rep.Refit then
		rep:Refit()
	end
end

-- A rail family round the square map (the window frame with its gem corners, the single rail): the frame's points
-- (its rails inside it, their inner edge `over` just over the map's; merged: down round the Services bar `bar`), its
-- nine-slice (made on first use, its rails' shade with it), how far its bottom gems paint under it (f.gemReach)
function Dresser:LayRails(f, b, map, bar, over)
	local sc = Kit.scale * b.scale
	local l, r, t, bo = RailDepths(b.prefix, sc)
	f:SetPoint("TOPLEFT", map, "TOPLEFT", -(l - over), t - over)
	if bar then
		-- down round the Services bar (as wide as the map, under it)
		f:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", r - over, -(bo - over))
	else
		f:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", r - over, -(bo - over))
	end
	local nine = f.nine[b.prefix]
	if not nine then
		nine = Kit:NineSlice(f, { prefix = b.prefix, scale = sc, gems = false, body = false, corners = b.gem and "gem" or nil })
		f.nine[b.prefix] = nine
		Shade.Add(nine)   -- (its rails' nine and gem corners; hidden with it)
	end
	nine:Show()
	f.gemReach = b.gem and GemReach(b.prefix, sc) or 0
	-- the zone band on the top rail: its caps take the top corners
	if nine.SetTopGems then
		nine:SetTopGems(false)
	end
end

-- A heavy frame picture round the square map (the action bars' backdrop frame, red or iron gems), cut into the
-- frame's eight parts (Kit:CutNine). -> false when it cannot be laid (the core hides the frame)
function Dresser:LayPicture(f, b, map, over)
	local p = Kit:Piece(b.piece)
	local k = Kit.scale
	local open = (p and p.open) or { 29, 34, 106, 97 }
	local w, h = p and p.w or 135, p and p.h or 130
	f:SetPoint("TOPLEFT", map, "TOPLEFT", -(open[1] * k - over), open[2] * k - over)
	f:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", (w - open[3]) * k - over, -((h - open[4]) * k - over))
	f.gemReach = 0   -- (the picture fills the frame)
	if not p or Kit:CutNine(f, f.parts, b.piece, k, CORNER, true) == false then
		return false
	end
	ShadeCut(f.parts, b.piece)
	return true
end

-- /mmdump's painted part: the cluster's art and this skin's pieces
function Dresser:Dump(msg)
	Kit:DumpWindow(MinimapCluster, skin, msg)
end

function M:OnEnable()
	Dresser.on = true
	Core:DresserChanged()
end

function M:OnDisable()
	Dresser.on = false
	Core:DresserChanged()
end

-- (at load: known to the core before any module comes up)
Core:SetDresser(Dresser)
