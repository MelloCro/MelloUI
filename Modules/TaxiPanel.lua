--------------------------------------------------------------------------------
-- MelloUI - Flight Map Kit
--
-- (user, 2026-09-24: "we didnt do quest dialogs, shops, Auction House,
-- profession training window, class trainers, Guild Crest Vendors, Flight
-- map, all should follow the rules"): The flight map window in the kit.
--
-- This client's flight map is TaxiFrame (Blizzard_UIPanels_Game, Shared/
-- TaxiFrame.xml): a BasicFrameTemplateWithInset window, 590 x 608, the
-- "Flight Map" title on the template's thin title bar, a close button, no
-- portrait. The painted map IS the template's InsetBg (TaxiFrame_OnShow hands
-- it to SetTaxiMap), the route lines are textures of TaxiRouteMap (a child
-- frame on the InsetBg's rect) and the nodes are TaxiButton1..n on it. A
-- client with the newer flight map (FlightMapFrame, the load-on-demand
-- Blizzard_FlightMap) gets the world map's dress on its BorderFrame instead.
--
-- Dressed by the rule book (docs/WINDOW-RULES.md) as a window WITHOUT a
-- portrait, the way the world map's window is: the outer double rail with
-- its gem corners grown outward (it reaches only ~3 px into the window, the
-- map starts 4 px in, so the rail frames the map and never lies on it), the
-- title plate riding the top rail with the game's own "Flight Map" string on
-- it in the kit's title face (2c), the page stone for the template's rock
-- (the title band and the slivers round the map), the kit's close button.
-- The template's thin inset border round the map gives way to the outer
-- rail, as on the world map, whose canvas meets the rail directly: a single
-- rail there (8-9 px at 1.6) would lie on the map's edge, which the picture
-- rule forbids, and would double the rails 4 px inside the outer one.
--
-- The map is a PICTURE (user, 2026-09-24): it is never faded, covered,
-- tinted or darkened, nor are its nodes and lines moved; the finder below
-- keeps it out of every list it builds. The taxi API is never called (the
-- Route module reads the flight points on TAXIMAP_OPENED; nothing here
-- listens to it). Nothing of the game's is replaced or re-scripted: post
-- hooks, HookScript and events only, our state in weak side tables.
-- Switched off, every piece is hidden, every faded region comes back and the
-- title is put back where, and in the font, it was.
--
-- /taxidump [art | frames | reps]: what the window is made of on this
-- client and what the skin made of it.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("TaxiPanel")
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("TaxiPanel", {
	title = "Flight Map Kit",
	desc = "The flight map window in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local TITLE_H = 20       -- BasicFrameTemplate's title bar: the rock starts 21 px down, the title tile is 20 px tall

local active = false
local skins = setmetatable({}, { __mode = "k" })         -- [window] = { reps = {}, followers = {}, kind = "taxi" | "flight", ... }
local hooked = setmetatable({}, { __mode = "k" })        -- [window] = true once its OnShow is hooked
local titleHome = setmetatable({}, { __mode = "k" })     -- [title string] = the frame it belongs to, while it rides our plate's band

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

-- The flight map windows this client has (either may be missing; a client
-- with both uses TaxiFrame for some maps and FlightMapFrame for others)
local function Windows()
	local list = {}
	for _, name in ipairs({ "TaxiFrame", "FlightMapFrame" }) do
		local f = _G[name]
		if type(f) == "table" and f.GetObjectType and f.HookScript then
			list[#list + 1] = f
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- Finding the parts by what they are
--------------------------------------------------------------------------------

-- The painted map: the inset's texture the game hands to SetTaxiMap (the
-- older template's TaxiMap region on a client that still has it). It is the
-- one texture of the window nothing of ours may ever touch.
local function MapTexture(tf)
	return tf.InsetBg or _G.TaxiMap
end

-- The window's title string, whatever this client calls it (WINDOW-RULES 2c:
-- TitleText, <Name>TitleText, a title container's TitleText, the older
-- window's TaxiMerchant), else the string that reads "Flight Map"
local function TitleString(tf)
	local candidates = { tf.TitleText, tf.TitleContainer and tf.TitleContainer.TitleText, _G.TaxiFrameTitleText, _G.TaxiMerchant }
	for _, fs in ipairs(candidates) do
		if type(fs) == "table" and fs.GetObjectType and fs:GetObjectType() == "FontString" then
			return fs
		end
	end
	local words = type(_G.FLIGHT_MAP) == "string" and _G.FLIGHT_MAP or nil
	if words then
		for _, region in ipairs({ tf:GetRegions() }) do
			if region:GetObjectType() == "FontString" then
				local ok, text = pcall(region.GetText, region)
				if ok and not Secret(text) and text == words then
					return region
				end
			end
		end
	end
	return nil
end

-- A texture that is a picture, not a border piece: more than half the
-- window both ways (a size that reads secret or 0 -- the window not laid out
-- yet -- counts as not known, and the keyed parts decide)
local function IsPicture(region, tf)
	local ok, w, h, fw, fh = pcall(function()
		local a, b = region:GetSize()
		local c, d = tf:GetSize()
		return a, b, c, d
	end)
	if not ok or Secret(w) or Secret(h) or Secret(fw) or Secret(fh) or not (w and h and fw and fh) or fw <= 0 or fh <= 0 then
		return false
	end
	return w > fw * 0.5 and h > fh * 0.5
end

-- The template's border art: the outer frame (corners, title tile, bottom,
-- sides) and the thin inset border round the map -- every texture of the
-- window in the BORDER and OVERLAY layers (BaseBasicFrameTemplate /
-- BasicFrameTemplateWithInset put exactly those there), never the map, the
-- rock, the title bar's tile or the streaks, which have pieces of their own
local BORDER_KEYS = {
	"TopLeftCorner", "TopRightCorner", "TopBorder", "BotLeftCorner", "BotRightCorner", "BottomBorder", "LeftBorder", "RightBorder",
	"InsetBorderTopLeft", "InsetBorderTopRight", "InsetBorderBottomLeft", "InsetBorderBottomRight",
	"InsetBorderTop", "InsetBorderBottom", "InsetBorderLeft", "InsetBorderRight",
}

local function BorderArt(tf)
	local map = MapTexture(tf)
	local keep = { [map or false] = true, [tf.Bg or false] = true, [tf.TitleBg or false] = true, [tf.TopTileStreaks or false] = true }
	local list, seen = {}, {}
	local function Add(region)
		if region and not seen[region] and not keep[region] and region.GetObjectType and region:GetObjectType() == "Texture"
			and not region.kitPiece then
			seen[region] = true
			list[#list + 1] = region
		end
	end
	for _, key in ipairs(BORDER_KEYS) do
		Add(tf[key])
	end
	for _, region in ipairs({ tf:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece and not keep[region] and not seen[region] then
			local ok, layer = pcall(region.GetDrawLayer, region)
			if ok and (layer == "BORDER" or layer == "OVERLAY") and not IsPicture(region, tf) then
				Add(region)
			end
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- Building the skin
--------------------------------------------------------------------------------

-- A skin's own Replace: Kit:Replace registered with the skin, enabled at
-- once while the kit is on. A region the library has no rule for is nil.
local function NewSkin(window, kind)
	local s = { reps = {}, followers = {}, kind = kind, window = window }
	s.Replace = function(region, opts)
		if not region then
			return nil
		end
		local ok, rep, key = pcall(Kit.Replace, Kit, region, opts)
		if not ok then
			MelloUI:Notice("Flight map: could not dress %s (%s)", tostring(opts and opts.as), tostring(rep))
			return nil
		end
		if not rep then
			if key then
				MelloUI:Notice("Flight map: no kit piece mapped for %s", tostring(key))
			end
			return nil
		end
		s.reps[#s.reps + 1] = rep
		if active then
			rep:Enable()
		end
		return rep
	end
	skins[window] = s
	return s
end

-- An invisible region of OUR frame to hand to Kit:Replace where the game has
-- no one piece to stand in for (the rail over sixteen loose border textures,
-- the plate over a title bar made of a tile and a string)
local function Anchor(host)
	local tex = host:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints(host)
	tex:SetColorTexture(0, 0, 0, 0)
	tex.kitPiece = true
	return tex
end

-- TaxiFrame (BasicFrameTemplateWithInset: no NineSlice, no title container)
local function BuildTaxi(tf)
	local s = NewSkin(tf, "taxi")
	local R = s.Replace
	s.map = MapTexture(tf)
	-- the shell parts the kit knows by key: the rock as the page stone (ONE
	-- picture for the window, inside the outer rail; a region of the window
	-- in the rock's layer, BACKGROUND -1, so the map at BACKGROUND 1 stays
	-- over it), the streak band faded, the close button on the kit's. No
	-- rail body: it would lie on the map (the world map's rule, body = false).
	Kit:SkinWindowShell(tf, R, s, { noRing = true, bg = tf.Bg and "UI-Background-Rock" or nil, body = false })
	-- our own frame for the anchors handed to Kit:Replace
	local host = CreateFrame("Frame", nil, tf)
	host:SetAllPoints(tf)
	host:EnableMouse(false)
	s.host = host
	if not tf.NineSlice then
		-- the outer double rail with its gem corners, grown outward, in place
		-- of the template's loose border textures (the window's frame and the
		-- map's thin inset border, 4 px inside it); at the window's own level,
		-- which is the rule's: it lies outside the map's rect, so the level
		-- decides nothing over the map
		s.borderArt = BorderArt(tf)
		s.outer = R(Anchor(host), { as = "NineSlicePanelTemplate", parent = tf, rect = tf, body = false, noFade = true, alsoFade = s.borderArt })
	end
	s.title = TitleString(tf)
	if tf.TitleContainer then
		-- a client whose template has a title container: the shell put the
		-- plate on it and moves its TitleText itself
		return s
	end
	-- the title plate riding the top rail (2c), on a band of ours over the
	-- title bar. The band stands three levels over the window: the plate (one
	-- under the band) above the rail (the window's level), the title above
	-- the plate. The game's title string is a region of the WINDOW, i.e. at
	-- the rail's level and under the plate: it is lent to the band while the
	-- kit is on (its parent put back on disable), so it is the game's own
	-- string that stands on the plate, as 2c asks, and not a copy.
	local band = CreateFrame("Frame", nil, tf)
	band:SetPoint("TOPLEFT", tf, "TOPLEFT", 0, 0)
	band:SetPoint("TOPRIGHT", tf, "TOPRIGHT", 0, 0)
	band:SetHeight(TITLE_H)
	band:EnableMouse(false)
	band:SetFrameLevel(tf:GetFrameLevel() + 3)
	band.TitleText = s.title   -- the TitleBar rule centres the band's TitleText on the plate in the title face, and puts it back on disable
	s.band = band
	s.plate = R(Anchor(band), { as = "TitleBar", parent = band, rect = band, fitHeight = TITLE_H, level = -1, noFade = true,
		alsoFade = { tf.TitleBg } })
	return s
end

-- FlightMapFrame (the newer flight map, a map canvas with a portrait
-- window's BorderFrame): dressed as MelloUI dresses the world map's window.
-- Not on this client (Blizzard_FlightMap is not in its interface): kept so a
-- client that has it is not left in the game's art.
local function BuildFlight(fm)
	local s = NewSkin(fm, "flight")
	local bf = fm.BorderFrame
	if not bf then
		return s
	end
	local pc = bf.PortraitContainer
	local portrait = pc and pc.portrait
	-- edges only: a body would cover the map canvas (the world map's rule)
	Kit:SkinWindowShell(bf, s.Replace, s, { portrait = portrait, noRing = portrait == nil, body = false })
	-- the title band (window top to the title container's bottom) is bare
	-- with the body off: the page stone there, inside the outer rail, as on
	-- the world map (MapTitleBand, an agreed addition)
	if bf.TitleContainer then
		local ins = Kit:OuterRailInset()
		local band = CreateFrame("Frame", nil, bf)
		band:EnableMouse(false)
		band:SetPoint("TOPLEFT", bf, "TOPLEFT", ins[1], -ins[3])
		band:SetPoint("TOPRIGHT", bf, "TOPRIGHT", -ins[2], -ins[3])
		band:SetPoint("BOTTOM", bf.TitleContainer, "BOTTOM", 0, -4)
		s.Replace(band, { as = "MapTitleBand", parent = bf, rect = band, noFade = true })
		s.title = bf.TitleContainer.TitleText
	end
	-- the portrait at the medallion size on the dark disc (2b: the flight
	-- master's icon is no full round picture)
	if s.ring and portrait then
		s.portrait = portrait
		Kit:RingDisc(s.ring)
	end
	return s
end

local function Build(window)
	if skins[window] then
		return skins[window]
	end
	if window == _G.FlightMapFrame then
		return BuildFlight(window)
	end
	return BuildTaxi(window)
end

--------------------------------------------------------------------------------
-- On / off
--------------------------------------------------------------------------------

-- The game's title string on our band (or back on its window)
local function LendTitle(s, on)
	local fs, band = s.title, s.band
	if not (fs and band and fs.SetParent) then
		return
	end
	if on then
		if not titleHome[fs] then
			titleHome[fs] = fs:GetParent()
			pcall(fs.SetParent, fs, band)
		end
	elseif titleHome[fs] then
		pcall(fs.SetParent, fs, titleHome[fs])
		titleHome[fs] = nil
	end
end

local function EnableSkin(s)
	for _, rep in ipairs(s.reps) do
		rep:Enable()
	end
	for _, entry in ipairs(s.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	LendTitle(s, true)
	if s.portrait and s.ring then
		Kit:FitPortrait(s.portrait, s.ring)
	end
end

local function DisableSkin(s)
	for _, rep in ipairs(s.reps) do
		rep:Disable()
	end
	LendTitle(s, false)
	if s.portrait then
		Kit:UnfitPortrait(s.portrait)
	end
end

-- whether a window is shown right now (secret-safe: unreadable is "no")
local function IsOpen(window)
	local ok, shown = pcall(window.IsShown, window)
	return ok and not Secret(shown) and shown and true or false
end

-- (user, 2026-09-24: "dress rarely used windows on first open") nothing of
-- the look is made while a window has never been shown this session: its
-- first show dresses it (OnShow below), a window already open when the kit
-- goes on (a reload with it open) at once. Once made, a window's skin stays
-- for the session and is only switched on and off. The dress makes frames
-- and textures of our own and moves only the game's title string onto our
-- band, never a protected frame, and never touches the map: it runs in
-- combat too, so the first frame the window draws is already dressed.
local function Activate()
	if active then
		return
	end
	local list = Windows()
	if #list == 0 then
		return
	end
	active = true
	for _, window in ipairs(list) do
		if skins[window] then
			EnableSkin(skins[window])
		elseif IsOpen(window) then
			EnableSkin(Build(window))
		end
	end
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, s in pairs(skins) do
		DisableSkin(s)
	end
end

-- A window shown: dressed on its first show (or if it came since: a
-- load-on-demand flight map), else its plate and portrait fitted again (the
-- window is laid out only now)
local function OnShow(window)
	if not active then
		return
	end
	local s = skins[window]
	if not s then
		EnableSkin(Build(window))
		return
	end
	for _, rep in ipairs(s.reps) do
		if rep.key == "TitleBar" and rep.object and rep.object:IsShown() then
			rep:Refit()
		end
	end
	for _, entry in ipairs(s.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	if s.portrait and s.ring then
		Kit:FitPortrait(s.portrait, s.ring)
	end
end

local function Hook()
	for _, window in ipairs(Windows()) do
		if not hooked[window] then
			hooked[window] = true
			Perf.HookScript(window, "OnShow", OnShow)
		end
	end
end

local function Sync()
	Hook()
	if M.isEnabled then
		Activate()
		-- a window that turned up after the kit went on (Blizzard_FlightMap
		-- loaded on demand) and is open already; a closed one waits for its
		-- first show like any other
		if active then
			for _, window in ipairs(Windows()) do
				if not skins[window] and IsOpen(window) then
					EnableSkin(Build(window))
				end
			end
		end
	else
		Deactivate()
	end
end

-- The windows come with the interface (TaxiFrame) or with their own
-- load-on-demand addon (FlightMapFrame): looked for again whenever an addon
-- loads, until both are known
local watcher = CreateFrame("Frame")
Perf.SetScript(watcher, "OnEvent", function()
	if M.isEnabled then
		Sync()
	else
		Hook()
	end
	if _G.TaxiFrame and _G.FlightMapFrame then
		watcher:UnregisterAllEvents()
	end
end)

function M:OnEnable(db)
	self.db = db
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:RegisterEvent("PLAYER_LOGIN")
	Sync()
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /taxidump [art | frames | reps]: the flight map window on this client.
-- No argument: which window this client has, the parts found (by key) and
-- what the skin made of each, the map's own state (it must read untouched:
-- alpha 1, white, not faded), the node buttons and route lines (counted from
-- their frames: no taxi API is called). "art" / "frames" / "reps": the kit's
-- window dump. Opens the copy window.
--------------------------------------------------------------------------------

local function KeyOf(parent, obj)
	if not (parent and obj) then
		return nil
	end
	local ok, key = pcall(function()
		for k, v in pairs(parent) do
			if type(k) == "string" and not Secret(v) and v == obj then
				return k
			end
		end
		return nil
	end)
	return ok and key or nil
end

local function Describe(obj)
	if not obj then
		return "-"
	end
	local okN, name = pcall(obj.GetName, obj)
	if okN and name and not Secret(name) then
		return name
	end
	local okD, dname = pcall(obj.GetDebugName, obj)
	if okD and dname and not Secret(dname) then
		return dname
	end
	return "[secret name]"
end

local function SizeText(obj)
	local ok, w, h = pcall(obj.GetSize, obj)
	if ok and w and h and not Secret(w) and not Secret(h) then
		return string.format("%.0f x %.0f", w, h)
	end
	return "? x ?"
end

local function LevelText(obj)
	local ok, level = pcall(obj.GetFrameLevel, obj)
	return (ok and level and not Secret(level)) and tostring(level) or "?"
end

-- a texture's art: its atlas or file (a file reads back as a number here)
local function ArtText(region)
	local key = Kit:ArtKey(region)
	if key then
		return key
	end
	local ok, tex = pcall(region.GetTexture, region)
	if ok and tex ~= nil and not Secret(tex) then
		return "file " .. tostring(tex)
	end
	return "?"
end

local function Contains(list, obj)
	for _, v in ipairs(list or {}) do
		if v == obj then
			return true
		end
	end
	return false
end

-- what the skin did with one region of the window
local function RoleOf(s, window, region)
	if not s then
		return "(not dressed)"
	end
	if region == s.map then
		return "THE MAP (untouched)"
	end
	if region == s.title then
		return "title -> on the plate, title face"
	end
	if region == window.Bg then
		return "rock -> page stone"
	end
	if region == window.TitleBg then
		return "title bar tile -> faded under the plate"
	end
	if region == window.TopTileStreaks then
		return "streaks -> faded"
	end
	if Contains(s.borderArt, region) then
		return "border -> outer rail (faded)"
	end
	return "left as the game's"
end

local function RegionLine(s, tf, region)
	local kind = region:GetObjectType()
	local okL, layer, sub = pcall(region.GetDrawLayer, region)
	local okA, alpha = pcall(region.GetAlpha, region)
	MelloUI:Print("   %s key=%s layer=%s %s %s alpha %s -> %s", kind, tostring(KeyOf(tf, region)),
		okL and (tostring(layer) .. " " .. tostring(sub)) or "?", SizeText(region),
		kind == "Texture" and ArtText(region) or "", (okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?",
		RoleOf(s, tf, region))
end

-- the route map, its lines and the nodes, counted from their frames
local function CountShown(prefix)
	local n, shown = 0, 0
	for i = 1, 200 do
		local obj = _G[prefix .. i]
		if not obj then
			break
		end
		n = n + 1
		if obj:IsShown() then
			shown = shown + 1
		end
	end
	return n, shown
end

local function DumpTaxi(tf)
	local s = skins[tf]
	MelloUI:Print("TaxiFrame: shown %s, size %s, level %s, strata %s; kit %s, pieces %d", tostring(tf:IsShown()), SizeText(tf),
		LevelText(tf), tostring(tf:GetFrameStrata()), active and "on" or "off", s and #s.reps or 0)
	MelloUI:Print("  template parts: NineSlice %s, TitleContainer %s, PortraitContainer %s, CloseButton %s",
		tostring(tf.NineSlice ~= nil), tostring(tf.TitleContainer ~= nil), tostring(tf.PortraitContainer ~= nil), tostring(tf.CloseButton ~= nil))
	-- the map: found, and untouched?
	local map = MapTexture(tf)
	if map then
		local okA, alpha = pcall(map.GetAlpha, map)
		local okC, r, g, b = pcall(map.GetVertexColor, map)
		local _, layer = pcall(map.GetDrawLayer, map)
		MelloUI:Print("  map: %s key=%s art=%s %s layer %s; alpha %s, colour %s, faded by the kit %s", Describe(map), tostring(KeyOf(tf, map)),
			ArtText(map), SizeText(map), tostring(layer), (okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?",
			(okC and not Secret(r)) and string.format("%.2f %.2f %.2f", r, g, b) or "?", tostring(Kit.faded[map] == true))
	else
		MelloUI:Print("  map: none found (no InsetBg / TaxiMap)")
	end
	local title = s and s.title or TitleString(tf)
	if title then
		local okT, text = pcall(title.GetText, title)
		local okF, face, size = pcall(title.GetFont, title)
		MelloUI:Print("  title: key=%s text=%s parent %s, font %s %s, title face %s", tostring(KeyOf(tf, title) or Describe(title)),
			(okT and not Secret(text)) and tostring(text) or "?", Describe(title:GetParent()),
			(okF and not Secret(face)) and (tostring(face):match("([^\\/]+)$") or tostring(face)) or "?",
			(okF and not Secret(size)) and tostring(size) or "?", tostring(title.melloFontSaved ~= nil))
	else
		MelloUI:Print("  title: none found")
	end
	if s then
		MelloUI:Print("  outer rail %s, title plate %s (band level %s), border textures faded %d", tostring(s.outer ~= nil),
			tostring(s.plate ~= nil), s.band and LevelText(s.band) or "-", #(s.borderArt or {}))
	end
	-- the game's regions only (the page stone is a region of the window too,
	-- but ours: it carries the kit's scale)
	for _, region in ipairs({ tf:GetRegions() }) do
		if not (region.kitPiece or region.kitScale) then
			RegionLine(s, tf, region)
		end
	end
	-- the title string is on our band while the kit is on: listed there
	if s and s.band and titleHome[s.title] then
		RegionLine(s, tf, s.title)
	end
	local rm = _G.TaxiRouteMap
	local buttons, shownButtons = CountShown("TaxiButton")
	local lines, shownLines = CountShown("TaxiRoute")
	MelloUI:Print("  route map: %s level %s %s; nodes %d (%d shown), route lines %d (%d shown) -- untouched",
		rm and Describe(rm) or "none", rm and LevelText(rm) or "-", rm and SizeText(rm) or "", buttons, shownButtons, lines, shownLines)
	local close = tf.CloseButton
	if close then
		MelloUI:Print("  close button: level %s %s, kit %s", LevelText(close), SizeText(close), tostring(close.GetNormalTexture
			and Kit.faded[close:GetNormalTexture()] == true))
	end
end

local function DumpFlight(fm)
	local s = skins[fm]
	local bf = fm.BorderFrame
	MelloUI:Print("FlightMapFrame: shown %s, size %s, level %s; kit %s, pieces %d; BorderFrame %s (NineSlice %s, TitleContainer %s, portrait %s, ring %s)",
		tostring(fm:IsShown()), SizeText(fm), LevelText(fm), active and "on" or "off", s and #s.reps or 0, tostring(bf ~= nil),
		tostring(bf and bf.NineSlice ~= nil), tostring(bf and bf.TitleContainer ~= nil),
		tostring(bf and bf.PortraitContainer and bf.PortraitContainer.portrait ~= nil), tostring(s and s.ring ~= nil))
end

SLASH_MELLOTAXIDUMP1 = "/taxidump"
SlashCmdList.MELLOTAXIDUMP = function(msg)
	msg = (msg or ""):lower()
	MelloUI:ClearLog()
	local list = Windows()
	if #list == 0 then
		local lod = "?"
		if C_AddOns and C_AddOns.IsAddOnLoadOnDemand then
			local ok, v = pcall(C_AddOns.IsAddOnLoadOnDemand, "Blizzard_FlightMap")
			lod = ok and tostring(v) or "?"
		end
		MelloUI:Print("/taxidump: no TaxiFrame and no FlightMapFrame yet (Blizzard_FlightMap load on demand: %s); talk to a flight master once and try again", lod)
	else
		for _, window in ipairs(list) do
			if not skins[window] then
				-- (dressed on its first open: until then the game's window as it is)
				MelloUI:Print("/taxidump: %s is not dressed yet (%s)", Describe(window), M.isEnabled
					and "the kit dresses it the first time it opens this session: talk to a flight master, then try again" or "the Flight Map Kit is off")
			end
			if msg == "art" or msg == "frames" or msg == "reps" then
				Kit:DumpWindow(window, skins[window], msg ~= "art" and msg or nil)
			elseif window == _G.FlightMapFrame then
				DumpFlight(window)
			else
				DumpTaxi(window)
			end
		end
	end
	MelloUI:ShowLog("taxidump " .. msg)
end
