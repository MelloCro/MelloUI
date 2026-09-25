--------------------------------------------------------------------------------
-- MelloUI - PvP Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): The battleground and arena windows and the scoreboard in the kit.
--
-- What this client has (its interface is of the mainline family with the
-- Camelot overrides; checked against the TOCs of the game's own addons):
--   PVPMatchScoreboard  the battleground scoreboard (Blizzard_PVPMatch, loaded
--                       with the interface for "standard, camelot"): a
--                       1024 x 420 window with a nine-slice laid on the window
--                       itself per match (GenericMetal, or the Horde /
--                       Alliance mission frame), a groupfinder-background
--                       rock, the table (a header band, a WowScrollBoxList of
--                       16 px rows tinted by faction, a MinimalScrollBar) in a
--                       Content inset, and the All / Alliance / Horde filter
--                       tabs (PanelTabButtonTemplate)
--   PVPMatchResults     the end-of-match window of the same addon: the same
--                       table and tabs, the outcome as its heading ("Victory"),
--                       a faction banner standing on its top edge, the
--                       rewards (item buttons, the honour / conquest rings)
--                       and Leave / Queue Again buttons
-- and what it does NOT have: BattlefieldFrame (the battlemaster's window;
-- the game's files load for vanilla / tbc / wrath only -- here a battlemaster
-- queues you at once), ArenaFrame (tbc / wrath), WorldStateScoreFrame (the
-- classic scoreboard: vanilla .. mists) and PVPUIFrame (Blizzard_PVPUI
-- excludes this client). Should a client have one of those, it gets the
-- window shell (a modern template's), the insets on the dark panel, the tabs
-- and the common controls; /pvpdump says which are here. The character
-- window's honour page (PVPRankFrame / HonorFrame / PVPFrame) is the
-- character kit's; the queue pop-ups (PVPReadyDialog ...) the ready kit's.
--
-- The scoreboard and the results, by the rule book (docs/WINDOW-RULES.md):
--   the window shell   the outer double rail in place of the nine-slice the
--                      game lays on the window (every theme's pieces faded,
--                      whichever it lays), ONE page stone for the rock
--                      inside the rail, the kit's close button; no portrait
--                      ring (the windows have none); the results' heading on
--                      the title plate riding the rail (2c) in the title
--                      face, in place of the faction banner; the scoreboard
--                      has no title of its own (nothing to replace)
--   the table          the Content inset as the list box L1 with the
--                      palette's inner panel (2e: a big text-dense table);
--                      the column headers on header plates, capless side by
--                      side (the guild roster's GC1), their labels in the
--                      palette's gold; each row's faction-tinted highlight
--                      replaced by a stripe in the main window's tone with
--                      the game's faction tint mixed into it, every other
--                      row fainter (striped rows); names, numbers and class
--                      icons keep the game's colours
--   the tabs           TB6 cards (Kit:SkinPanelTab), with the guard that
--                      keeps them hidden while the module is off; the lines
--                      over / under the tab strip as the kit's divider
--   the controls       the scroll bar T2 / H1 / S1; Leave / Queue Again on
--                      red plates (their disabled look kept); the reward
--                      items in every window's Button Border rim (their
--                      quality border kept on the icon), the honour /
--                      conquest rings as the round rim
--
-- Each window is dressed on its first show, not at login (user, 2026-09-24:
-- "dress rarely used windows on first open"; see DressOpen).
--
-- Taint: nothing of the game's is replaced or re-scripted; the skin is made
-- and kept from post-hooks (the windows' Init / SetupArtwork / UpdateTable /
-- DisplayRewards, HookScript, the scroll box's row callbacks, the regions'
-- own Show / Hide / SetVertexColor), what it keeps lives in weak side
-- tables, and no PvP, queue or score function is ever called. Nothing is
-- moved but the results' heading (lent to the plate's band, put back on
-- disable). Switched off, every piece is hidden, every faded region comes
-- back, the colours and the heading are put back: the windows are the game's.
--
-- /pvpdump [frames | reps | regions]: what the PvP windows are made of on
-- this client and what the skin dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("PvPPanel")
local hooksecurefunc = Perf.hooksecurefunc
-- a handler made once and run for many asks, wrapped once: its time stays
-- on this file's own /melloperf row (review, 2026-09-24)
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("PvPPanel", {
	title = "PvP Kit",
	desc = "The battleground and arena windows and the scoreboard in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local HEADER_H = 24        -- a column header plate's height on the 50 px header band (the guild roster's column plates)
local ROW_ALPHA = 0.85     -- WINDOW-RULES 2e: rows striped in the main window tone at about 0.85 ...
local ROW_ALPHA_ALT = 0.5  -- ... every other row fainter
local FACTION_MIX = 0.25   -- how much of the game's faction tint goes into a row's stripe

-- The windows looked for, in the order the dump lists them. `kind` "match":
-- Blizzard_PVPMatch's two windows; "generic": a classic window this client
-- does not load (dressed by its template's parts, should one be here).
local WINDOWS = {
	{ name = "PVPMatchScoreboard", kind = "match", label = "battleground scoreboard" },
	{ name = "PVPMatchResults", kind = "match", results = true, label = "match results" },
	{ name = "BattlefieldFrame", kind = "generic", label = "battlemaster's window",
		absent = "its files load for vanilla / tbc / wrath only; a battlemaster queues you at once here" },
	{ name = "ArenaFrame", kind = "generic", label = "arena battlemaster's window", absent = "its files load for tbc / wrath only" },
	{ name = "WorldStateScoreFrame", kind = "generic", label = "classic scoreboard",
		absent = "its files load for vanilla .. mists only; this client's scoreboard is PVPMatchScoreboard" },
	{ name = "PVPUIFrame", kind = "generic", label = "PvP queue window", absent = "Blizzard_PVPUI excludes this client" },
}

local active = false
local skins = setmetatable({}, { __mode = "k" })        -- [window] = its skin
local hooked = setmetatable({}, { __mode = "k" })       -- [window] = true once its scripts are hooked
local done = setmetatable({}, { __mode = "k" })         -- [frame / region] = true: looked at once
local rows = setmetatable({}, { __mode = "k" })         -- [row] = { tex, row, tint, odd }
local headers = setmetatable({}, { __mode = "k" })      -- [header] = { rep, text, colour = the game's }
local titleHome = setmetatable({}, { __mode = "k" })    -- [heading] = the frame it belongs to, while it rides our plate's band

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe and MelloUI.Safe.IsSecret or issecretvalue

-- the non-nil values given, as a list
local function List(...)
	local list = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if v then
			list[#list + 1] = v
		end
	end
	return list
end

-- a frame's name, secret-safe (nil when it has none or it reads secret)
local function NameOf(obj)
	if not obj then
		return nil
	end
	local ok, n = pcall(obj.GetName, obj)
	if ok and type(n) == "string" and not Secret(n) then
		return n
	end
	return nil
end

local function Frame(name)
	local f = _G[name]
	if type(f) == "table" and f.GetObjectType and f.HookScript then
		return f
	end
	return nil
end

--------------------------------------------------------------------------------
-- A skin per window
--------------------------------------------------------------------------------

local function NewSkin(window, def)
	local s = { reps = {}, followers = {}, faded = {}, tabReps = {}, nineArt = {}, nineSeen = {}, rimHolders = {},
		window = window, def = def }
	s.Replace = function(region, opts)
		if not region then
			return nil
		end
		local ok, rep, key = pcall(Kit.Replace, Kit, region, opts)
		if not ok then
			MelloUI:Notice("PvP kit: could not dress %s (%s)", tostring(opts and opts.as), tostring(rep))
			return nil
		end
		if not rep then
			if key then
				MelloUI:Notice("PvP kit: no kit piece mapped for %s", tostring(key))
			end
			return nil
		end
		s.reps[#s.reps + 1] = rep
		if active then
			rep:Enable()
		end
		return rep
	end
	-- art faded while the kit is on with no piece on its own rect (the
	-- stripe stands in for a row's highlight, the list box's panel for a tint)
	s.Fade = function(obj)
		if not obj or done[obj] then
			return
		end
		done[obj] = true
		s.faded[#s.faded + 1] = obj
		if active then
			Kit:Fade(obj)
		end
	end
	skins[window] = s
	return s
end

-- An invisible region of OUR frame to hand to Kit:Replace where the game has
-- no one piece to stand in for (the rail over the nine loose pieces, the
-- title plate over a banner, a header plate on a text-only button)
local function Anchor(host, layer, sublevel)
	local tex = host:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
	tex:SetAllPoints(host)
	tex:SetColorTexture(0, 0, 0, 0)
	tex.kitPiece = true
	return tex
end

--------------------------------------------------------------------------------
-- Finding the parts (Blizzard_PVPMatch names them in two cases: the
-- scoreboard's Content / ScrollBox, the results' content / scrollBox)
--------------------------------------------------------------------------------

local function Content(f)
	return f.Content or f.content
end

local function ScrollBox(f)
	local c = Content(f)
	return f.ScrollBox or f.scrollBox or (c and (c.ScrollBox or c.scrollBox))
end

local function ScrollBar(f)
	local c = Content(f)
	return f.ScrollBar or f.scrollBar or (c and (c.ScrollBar or c.scrollBar))
end

local function Categories(f)
	local c = Content(f)
	return f.ScrollCategories or f.scrollCategories or (c and (c.ScrollCategories or c.scrollCategories))
end

local function TabContainer(f)
	local c = Content(f)
	return f.TabContainer or (c and (c.TabContainer or c.tabContainer))
end

-- The filter tabs: the window's Tabs list, its keyed tabs, the named ones
local TAB_NAMES = { PVPMatchScoreboard = "PVPScoreboardTab", PVPMatchResults = "PVPScoreFrameTab" }

local function Tabs(f)
	local list, seen = {}, {}
	local function Add(tab)
		if tab and not seen[tab] then
			seen[tab] = true
			list[#list + 1] = tab
		end
	end
	for _, tab in ipairs(f.Tabs or {}) do
		Add(tab)
	end
	for i = 1, 3 do
		Add(f["Tab" .. i] or f["tab" .. i])
	end
	local name = NameOf(f)
	local prefix = name and (TAB_NAMES[name] or (name .. "Tab"))
	if prefix then
		for i = 1, 6 do
			Add(_G[prefix .. i])
		end
	end
	return list
end

-- The window's rock: its BACKGROUND texture with the group finder's rock
-- atlas (the template gives it no key), else the largest BACKGROUND texture
local function PageTexture(f)
	local best, bestArea
	for _, region in ipairs({ f:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			local okL, layer = pcall(region.GetDrawLayer, region)
			if okL and layer == "BACKGROUND" then
				if Kit:ArtKey(region) == "groupfinder-background" then
					return region
				end
				local ok, w, h = pcall(region.GetSize, region)
				local area = (ok and w and h and not Secret(w) and not Secret(h)) and w * h or 0
				if not best or area > bestArea then
					best, bestArea = region, area
				end
			end
		end
	end
	return best
end

-- The nine-slice the game lays on the WINDOW itself per match
-- (NineSliceUtil.ApplyLayoutByName on the frame: the pieces become keys of
-- it, made on the first layout): collected whenever the game lays one, and
-- faded while the outer rail stands in for them
local NINE_KEYS = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }

local function CollectNine(s)
	local f = s.window
	for _, key in ipairs(NINE_KEYS) do
		local piece = f[key]
		if type(piece) == "table" and piece.GetObjectType and piece:GetObjectType() == "Texture" and not s.nineSeen[piece] then
			s.nineSeen[piece] = true
			-- the outer rail's alsoFade list is this very table: its Enable /
			-- Disable reach every piece found since
			s.nineArt[#s.nineArt + 1] = piece
			if active and s.outer then
				Kit:Fade(piece)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The tabs (TB6, Kit:SkinPanelTab). The Kit's cards follow their tab's
-- textures on every Show / Hide, also while the kit is off, which would
-- bring a card back over the game's own tab on the next tab switch; after
-- those hooks this one sets every card from its texture while the kit is on
-- and hides them all while it is off (the merchant's guard).
--------------------------------------------------------------------------------
local function GuardTabs(s)
	for _, entry in ipairs(s.tabReps) do
		if active then
			entry.rep:SetShown(entry.region:IsShown())
		else
			entry.rep.object:Hide()
		end
	end
end

local function SkinTab(s, tab)
	if not (tab and tab.Left and tab.LeftActive) or done[tab] or tab.melloRep ~= nil then
		return
	end
	done[tab] = true
	local first = #s.followers + 1
	Kit:SkinPanelTab(tab, s.Replace, s)
	for i = first, #s.followers do
		s.tabReps[#s.tabReps + 1] = s.followers[i]
	end
	local function Guard()
		GuardTabs(s)
	end
	for _, tex in ipairs({ tab.Left, tab.LeftActive }) do
		hooksecurefunc(tex, "Show", Guard)
		hooksecurefunc(tex, "Hide", Guard)
		hooksecurefunc(tex, "SetShown", Guard)
	end
end

--------------------------------------------------------------------------------
-- The table's rows (PVPTableRowTemplate: 16 px, three file textures of
-- WorldStateFinalScore-Highlight tinted by the row's faction in the game's
-- Populate). WINDOW-RULES 2e: rows on the dark panel are striped in the
-- main window's tone -- the stripe stands in for the three textures (faded),
-- a region of the row under its cells; the game's faction tint is kept in
-- it (a quarter of it mixed into the tone, read from the game's own
-- SetVertexColor), and every other row is fainter, so the table reads as
-- stripes and Alliance / Horde rows still tell apart.
--------------------------------------------------------------------------------
local function PaintRow(entry)
	local P = MelloUI.Palette
	local base = P and P.mainWindow or { 0.12, 0.11, 0.09 }
	local r, g, b = base[1], base[2], base[3]
	local t = entry.tint
	if t then
		r = r + (t[1] - r) * FACTION_MIX
		g = g + (t[2] - g) * FACTION_MIX
		b = b + (t[3] - b) * FACTION_MIX
	end
	entry.tex:SetColorTexture(r, g, b, entry.odd and ROW_ALPHA or ROW_ALPHA_ALT)
	entry.tex:SetShown(active)
end

local function ReadTint(r, g, b)
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" or Secret(r) or Secret(g) or Secret(b) then
		return nil
	end
	return { r, g, b }
end

-- the row's place in the list (the data provider's `index`), for the stripe
local function RowIndex(row)
	if row.GetElementData then
		local ok, data = pcall(row.GetElementData, row)
		if ok and type(data) == "table" then
			local i = data.index
			if type(i) == "number" and not Secret(i) then
				return i
			end
		end
	end
	if row.GetElementDataIndex then
		local ok, i = pcall(row.GetElementDataIndex, row)
		if ok and type(i) == "number" and not Secret(i) then
			return i
		end
	end
	return nil
end

local function RowSkin(s, row)
	if not (row and row.CreateTexture) then
		return
	end
	local entry = rows[row]
	if not entry then
		local tex = row:CreateTexture(nil, "BACKGROUND", nil, -8)
		tex.kitPiece = true   -- ours: never faded as the game's art
		tex:SetAllPoints(row)
		entry = { tex = tex, row = row, odd = true }
		rows[row] = entry
		s.rowList = s.rowList or {}
		s.rowList[#s.rowList + 1] = entry
		local bgs = row.Backgrounds or List(row.backgroundLeft, row.backgroundRight, row.backgroundCenter)
		for _, bg in ipairs(bgs) do
			s.Fade(bg)
		end
		local first = bgs[1]
		if first then
			local ok, r, g, b = pcall(first.GetVertexColor, first)
			if ok then
				entry.tint = ReadTint(r, g, b)
			end
			hooksecurefunc(first, "SetVertexColor", function(_, nr, ng, nb)
				local tint = ReadTint(nr, ng, nb)
				if tint then
					entry.tint = tint
					PaintRow(entry)
				end
			end)
		end
	end
	local i = RowIndex(row)
	if i then
		entry.odd = (i % 2) == 1
	end
	PaintRow(entry)
end

local function SkinRows(s)
	local box = ScrollBox(s.window)
	if not (box and box.ForEachFrame) then
		return
	end
	box:ForEachFrame(function(row)
		RowSkin(s, row)
	end)
end

--------------------------------------------------------------------------------
-- The column headers (PVPHeaderStringTemplate / PVPHeaderIconTemplate
-- buttons the table builder pools on the 50 px header band and lays out to
-- the columns' widths): the header plate per column, capless so the plates
-- run on side by side as one band (the guild roster's GC1), at the roster's
-- plate height on the band's middle, hover from the button; a label on it
-- in the palette's gold (2e: headings in gold), the game's colour put back
-- on disable. The buttons paint nothing: the plate is keyed on an invisible
-- region of ours, the plate's pieces regions of the button under its text.
--------------------------------------------------------------------------------
local function Gold()
	local P = MelloUI.Palette
	local c = P and P.selectedTrim or { 0.68, 0.52, 0.27 }
	return c[1], c[2], c[3]
end

local function HeaderColour(entry, on)
	local text = entry.text
	if not text then
		return
	end
	if on then
		if not entry.colour then
			local ok, r, g, b, a = pcall(text.GetTextColor, text)
			if ok and type(r) == "number" and not (Secret(r) or Secret(g) or Secret(b)) then
				entry.colour = { r, g, b, a or 1 }
			end
		end
		local r, g, b = Gold()
		text:SetTextColor(r, g, b)
	elseif entry.colour then
		local c = entry.colour
		entry.colour = nil
		text:SetTextColor(c[1], c[2], c[3], c[4])
	end
end

local function SkinHeader(s, header)
	if not (header and header.CreateTexture) or headers[header] then
		return
	end
	local anchor = Anchor(header, "BACKGROUND", -8)
	local rep = s.Replace(anchor, { as = "ColumnDisplayButton", rect = header, button = header, capless = true, fitHeight = HEADER_H, noFade = true })
	local text = header.text
	if not (type(text) == "table" and text.GetObjectType and text:GetObjectType() == "FontString") then
		text = nil
	end
	local entry = { rep = rep, text = text }
	headers[header] = entry
	s.headerList = s.headerList or {}
	s.headerList[#s.headerList + 1] = header
	if active then
		HeaderColour(entry, true)
	end
end

local function SkinHeaders(s)
	local band = Categories(s.window)
	if not band then
		return
	end
	for _, child in ipairs({ band:GetChildren() }) do
		SkinHeader(s, child)
	end
end

--------------------------------------------------------------------------------
-- The results' heading (WINDOW-RULES 2c: the title ON the plate, in the title
-- face). The window has no title bar: its title is the outcome heading
-- ("Victory", a Game42Font string of the window between its top and the
-- table), and a faction banner (overlay.decorator) stands on its top edge in
-- factional matches. The title plate rides the outer rail in the banner's
-- place (the banner faded), on a band of ours three levels over the window;
-- the heading is lent to the band (its parent put back on disable) and
-- centred on the plate in the title face by the TitleBar rule, which puts
-- back its points and font on disable. The plate is sized to the heading's
-- own size (the band as tall as the string's font), so the heading fits it.
--------------------------------------------------------------------------------
local function HeadingSize(fs)
	local ok, _, size = pcall(fs.GetFont, fs)
	if ok and type(size) == "number" and not Secret(size) and size > 0 then
		return math.max(20, math.min(size, 42))
	end
	return 32
end

local function BuildTitle(s, f)
	local heading = f.header
	if not (type(heading) == "table" and heading.GetObjectType and heading:GetObjectType() == "FontString") then
		return
	end
	local h = HeadingSize(heading)
	local band = CreateFrame("Frame", nil, f)
	band:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	band:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	band:SetHeight(h)
	band:EnableMouse(false)
	band:SetFrameLevel(f:GetFrameLevel() + 3)
	band.TitleText = heading   -- the TitleBar rule centres the band's TitleText on the plate in the title face
	s.band, s.title = band, heading
	s.plate = s.Replace(Anchor(band), { as = "TitleBar", parent = band, rect = band, fitHeight = h, level = -1, noFade = true,
		alsoFade = List(f.overlay and f.overlay.decorator) })
end

-- The game's heading on our band (or back on its window)
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

local function PlaceTitle(s)
	local rep = s.plate
	if not (active and rep and rep.object and rep.object:IsShown()) then
		return
	end
	if rep.Refit then
		rep:Refit()
	end
	if s.title and not s.title.melloFontSaved then
		Kit:TitleFont(s.title, true)
	end
end

--------------------------------------------------------------------------------
-- The results' rewards. An item (PVPMatchResultsLoot, LootItemExtended: a
-- 52 px Icon, its quality's loot-toast IconBorder, a drop shadow under it):
-- every window's Button Border rim hugging the icon (its edge 2 px under the
-- rim's inner edge, the merchant's recipe) in place of the drop shadow, the
-- quality border kept on the icon's rect inside the rim. The honour /
-- conquest rewards (a 30 px icon masked round in a honorsystem ring): the
-- round rim (O2) whose opening is the icon.
--------------------------------------------------------------------------------
local function FitIconRim(holder)
	local rim = holder.melloRep and holder.melloRep.object
	local icon = holder.icon
	if not (rim and rim.base and icon) then
		return
	end
	local name = rim.base .. "_normal"
	local p = Kit:Piece(name)
	local l, r, t, b = Kit:Insets(name, 1)
	local ok, iw, ih = pcall(icon.GetSize, icon)
	if not (p and l and ok and iw and ih) or Secret(iw) or Secret(ih) or iw <= 0 or ih <= 0 then
		return
	end
	rim:ClearAllPoints()
	rim:SetPoint("CENTER", icon, "CENTER")
	rim:SetSize((iw - 4) * p.w / (p.w - l - r), (ih - 4) * p.h / (p.h - t - b))
end

-- a new Button Border has a new opening: every reward rim fitted again
Kit:OnBorderChanged("button", function()
	for _, s in pairs(skins) do
		for _, holder in ipairs(s.rimHolders) do
			FitIconRim(holder)
		end
	end
end)

local function SkinLoot(s, button)
	local icon = button and button.Icon
	if not icon or done[button] then
		return
	end
	done[button] = true
	local shadow = button.IconBorderDropShadow
	local rep = s.Replace(shadow or icon, { as = Kit:ButtonRimRule(), button = button, parent = button, rect = icon, noFade = shadow == nil })
	if not rep then
		return
	end
	local holder = { melloRep = rep, icon = icon, button = button }
	s.rimHolders[#s.rimHolders + 1] = holder
	Kit:RegisterButtonRim(holder)
	-- the quality border on the icon's rect while the rim is on (the game's
	-- anchors put back on disable)
	local quality = button.IconBorder
	local saved = {}
	if quality then
		for i = 1, quality:GetNumPoints() do
			saved[i] = { quality:GetPoint(i) }
		end
	end
	local onEnable, onDisable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if onEnable then
			onEnable(...)
		end
		FitIconRim(holder)
		if quality then
			quality:ClearAllPoints()
			quality:SetAllPoints(icon)
		end
	end
	rep.onDisable = function(...)
		if onDisable then
			onDisable(...)
		end
		if quality and #saved > 0 then
			quality:ClearAllPoints()
			for _, pt in ipairs(saved) do
				quality:SetPoint(unpack(pt))
			end
		end
	end
	if active then
		rep.onEnable(rep)
	end
end

local function SkinCurrency(s, button)
	local ring, icon = button and button.Ring, button and button.Icon
	if not (ring and icon) or done[button] then
		return
	end
	done[button] = true
	local ok, w = pcall(icon.GetWidth, icon)
	local size = (ok and type(w) == "number" and not Secret(w) and w > 0) and w or 30
	local rect = Kit:RimRect(button, "roundslot", size, icon)
	s.Replace(ring, { as = "communities-ring-gold", button = button, parent = button, rect = rect })
end

local function SkinRewards(s)
	local f = s.window
	local items = f.itemContainer or (f.rewardsContainer and f.rewardsContainer.items)
	if items and items.GetChildren then
		for _, b in ipairs({ items:GetChildren() }) do
			SkinLoot(s, b)
		end
	end
	SkinCurrency(s, f.honorButton)
	SkinCurrency(s, f.conquestButton)
end

--------------------------------------------------------------------------------
-- Building a match window (the scoreboard, the results)
--------------------------------------------------------------------------------

-- The lines over / under the tab strip (the tab container's inner border
-- tiles): the kit's divider at its natural weight across most of the box
-- (the quest greeting's horizontal break), on the tab container's level,
-- over the list box's panel
local function SkinTabLines(s, tc)
	for _, key in ipairs({ "InsetBorderTop", "InsetBorderBottom" }) do
		local line = tc and tc[key]
		if line and not done[line] then
			done[line] = true
			s.Replace(line, { as = "UI-HorizontalBreak", parent = tc, level = 0 })
		end
	end
end

-- The Content inset: the list box L1 (single rail, list-box stone under the
-- palette's inner panel: the `common-insideframe` rule's dim), on a holder
-- AT the content's level: the header band, the list, the bar and the tabs
-- are frames one level up; the inset's pieces and the list's faction tint
-- faded (the panel stands in)
local INSET_KEYS = { "InsetBorderTopLeft", "InsetBorderTopRight", "InsetBorderBottomLeft", "InsetBorderBottomRight",
	"InsetBorderTop", "InsetBorderBottom", "InsetBorderLeft", "InsetBorderRight" }

local function SkinContent(s, f)
	local c = Content(f)
	if not c or done[c] then
		return
	end
	done[c] = true
	local bg = c.Background or c.background
	local box = ScrollBox(f)
	local extra = List(box and (box.Background or box.background))
	for _, key in ipairs(INSET_KEYS) do
		if c[key] then
			extra[#extra + 1] = c[key]
		end
	end
	if bg then
		s.box = s.Replace(bg, { as = "common-insideframe", parent = c, rect = c, level = 0, alsoFade = extra })
	else
		for _, tex in ipairs(extra) do
			s.Fade(tex)
		end
	end
end

-- The results' decorations over the table's lower band: the reward band's
-- faction-tinted picture and its shadow, and the faction glow over the
-- table's top: faded (the list box's panel runs on under them); the burst
-- effects that play when the rewards come stay the game's
local function FadeResultsArt(s, f)
	s.Fade(f.glowTop)
	local art = f.earningsArt or (Content(f) and Content(f).earningsArt)
	if art then
		s.Fade(art.background)
		for _, region in ipairs({ art:GetRegions() }) do
			if region:GetObjectType() == "Texture" and Kit:ArtKey(region) == "pvpscoreboard-background-reward-shadow" then
				s.Fade(region)
			end
		end
	end
end

local function BuildMatch(s, f)
	local host = CreateFrame("Frame", nil, f)
	host:SetAllPoints(f)
	host:EnableMouse(false)
	s.host = host
	-- the outer rail, edges only (the page stone is the window's one
	-- background), in place of whichever nine-slice the game lays
	s.outer = s.Replace(Anchor(host), { as = "NineSlicePanelTemplate", parent = f, rect = f, body = false, noFade = true, alsoFade = s.nineArt })
	CollectNine(s)
	-- ONE page stone for the rock, inside the rail (WINDOW-RULES 2a)
	s.page = PageTexture(f)
	if s.page then
		s.pageRep = s.Replace(s.page, { as = "UI-Background-Rock", parent = f, rect = f, inset = Kit:OuterRailInset() })
	end
	-- the close button
	local close = f.CloseButton
	local normal = close and close.GetNormalTexture and close:GetNormalTexture()
	if normal then
		s.close = s.Replace(normal, { as = "RedButton-Exit", button = close, alsoFade = Kit:OtherTextures(close, normal) })
	end
	-- the table
	SkinContent(s, f)
	SkinTabLines(s, TabContainer(f))
	for _, tab in ipairs(Tabs(f)) do
		SkinTab(s, tab)
	end
	local bar = ScrollBar(f)
	if bar then
		Kit:SkinScrollBar(bar, s.Replace)
	end
	local box = ScrollBox(f)
	if box then
		Kit:HookScrollBoxRows(box, function(row)
			RowSkin(s, row)
		end, function()
			return active
		end, true)
	end
	SkinHeaders(s)
	if s.def.results then
		BuildTitle(s, f)
		FadeResultsArt(s, f)
		local bc = f.buttonContainer
		for _, b in ipairs(List(f.requeueButton or (bc and bc.requeueButton), f.leaveButton or (bc and bc.leaveButton))) do
			Kit:SkinRedButton(b, s.Replace)
		end
		SkinRewards(s)
	end
	-- whatever else is a common control (the rows' scroll box is not walked)
	Kit:SweepControls(f, s.Replace, s, box)
end

--------------------------------------------------------------------------------
-- A classic window this client does not load (should one be here): the
-- window shell of a modern template (rail, page stone, ring with the NPC on
-- the dark disc, the title plate, close), its insets as list boxes on the
-- dark panel, the tabs, every common control. A window of loose file art
-- has no parts the kit knows by key: it gets the controls only, and the
-- dump says so.
--------------------------------------------------------------------------------
local function Portrait(f)
	local pc = f.PortraitContainer
	return (pc and pc.portrait) or f.portrait or _G[(NameOf(f) or "") .. "Portrait"]
end

local function BuildGeneric(s, f)
	if f.NineSlice then
		local portrait = Portrait(f)
		local ring = Kit:SkinWindowShell(f, s.Replace, s, { portrait = portrait, bg = f.Bg and "UI-Background-Rock" or nil })
		if ring and portrait then
			s.ring, s.portrait = ring, portrait
			ring.onEnable = function()
				pcall(Kit.FitPortrait, Kit, portrait, ring)
			end
			ring.onDisable = function()
				pcall(Kit.UnfitPortrait, Kit, portrait)
			end
			Kit:RingDisc(ring, nil, f.PortraitContainer or ring.object:GetParent(), 0)
		end
		s.shell = true
	end
	for _, child in ipairs({ f:GetChildren() }) do
		if child.NineSlice and child.Bg and (child.layoutType == "InsetFrameTemplate" or child.NineSlice.layoutType == "InsetFrameTemplate") then
			Kit:SkinInset(child, s.Replace, f, true)
		end
	end
	for _, tab in ipairs(Tabs(f)) do
		SkinTab(s, tab)
	end
	Kit:SweepControls(f, s.Replace, s)
end

local function Build(f, def)
	if skins[f] then
		return skins[f]
	end
	local s = NewSkin(f, def)
	if def.kind == "match" then
		BuildMatch(s, f)
	else
		BuildGeneric(s, f)
	end
	return s
end

--------------------------------------------------------------------------------
-- On / off, and the game's refreshes
--------------------------------------------------------------------------------

-- The list box's holder kept AT the content's level, the title band three
-- over the window (the windows are toplevel: the game raises them when
-- clicked, and a holder must never come to tie with the rows' frames)
local function KeepLevels(s)
	local f = s.window
	local c = Content(f)
	local rep = s.box
	local holder = rep and rep.object
	if c and holder and holder.SetFrameLevel then
		local ok, level = pcall(c.GetFrameLevel, c)
		if ok and type(level) == "number" and not Secret(level) then
			holder:SetFrameLevel(level)
			if rep.skin and rep.skin.SetFrameLevel then
				rep.skin:SetFrameLevel(level)
			end
		end
	end
	if s.band then
		local ok, level = pcall(f.GetFrameLevel, f)
		if ok and type(level) == "number" and not Secret(level) then
			s.band:SetFrameLevel(level + 3)
		end
	end
end

-- Refresh's pass a frame later for the window `s` dresses, once it is laid
-- out (made once: Kit:NextFrame runs it once per window however often it was
-- asked -- audit, 2026-09-24; timed on this file's own /melloperf row, not
-- the Kit's timer -- review)
local RefreshLater = Shared("Refresh a frame later", function(s)
	if active and s.window:IsShown() then
		PlaceTitle(s)
		for _, holder in ipairs(s.rimHolders) do
			FitIconRim(holder)
		end
		if s.ring and s.portrait then
			pcall(Kit.FitPortrait, Kit, s.portrait, s.ring)
		end
	end
end, "timer")

-- After every show and every game refresh (a match's layout, a tab switch, a
-- score update, the rewards): what the game made or re-laid since
local function Refresh(s)
	if not (active and s) then
		return
	end
	for _, entry in ipairs(s.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	GuardTabs(s)
	if s.def.kind == "match" then
		KeepLevels(s)
		CollectNine(s)
		SkinHeaders(s)
		SkinRows(s)
		if s.def.results then
			SkinRewards(s)
			PlaceTitle(s)
		end
	end
	if s.ring and s.portrait then
		pcall(Kit.FitPortrait, Kit, s.portrait, s.ring)
	end
	-- once laid out (a frame after it shows): the title and the rims again,
	-- one pass pending at a time (the scoreboard refreshes every score update)
	Kit:NextFrame(s, RefreshLater)
end

local function EnableSkin(s)
	for _, rep in ipairs(s.reps) do
		rep:Enable()
	end
	for _, obj in ipairs(s.faded) do
		Kit:Fade(obj)
	end
	for _, entry in ipairs(s.rowList or {}) do
		PaintRow(entry)
	end
	for _, header in ipairs(s.headerList or {}) do
		HeaderColour(headers[header], true)
	end
	LendTitle(s, true)
	Refresh(s)
end

local function DisableSkin(s)
	for _, rep in ipairs(s.reps) do
		rep:Disable()
	end
	for _, obj in ipairs(s.faded) do
		Kit:Unfade(obj)
	end
	for _, entry in ipairs(s.rowList or {}) do
		entry.tex:Hide()
	end
	for _, header in ipairs(s.headerList or {}) do
		HeaderColour(headers[header], false)
	end
	-- (the plate's onDisable put the heading's points and font back first)
	LendTitle(s, false)
	GuardTabs(s)
end

-- the windows this client has now
local function Present()
	local list = {}
	for _, def in ipairs(WINDOWS) do
		local f = Frame(def.name)
		if f then
			list[#list + 1] = { f = f, def = def }
		end
	end
	return list
end

local function OnWindowRefresh(f)
	local s = skins[f]
	if s then
		Refresh(s)
	end
end

-- a window shown now (secret-safe)
local function IsOpen(f)
	local ok, shown = pcall(f.IsShown, f)
	return ok and not Secret(shown) and shown == true
end

local Sync

local function Hook()
	for _, entry in ipairs(Present()) do
		local f = entry.f
		if not hooked[f] then
			hooked[f] = true
			-- its first show dresses a window there and then, in combat too
			-- (the scoreboard is opened mid-fight): dressing makes frames of
			-- ours and moves only the results' heading (lent to our band);
			-- none of these windows or their controls is protected
			Perf.HookScript(f, "OnShow", function(self)
				if M.isEnabled and not (active and skins[self]) then
					Sync()
					return
				end
				OnWindowRefresh(self)
			end)
			-- the game's own refreshes: the match layout (a new theme's
			-- nine-slice, the table's columns), the scores, the rewards
			for _, method in ipairs({ "Init", "SetupArtwork", "UpdateTable", "DisplayRewards", "AddItemReward", "OnTabGroupClicked" }) do
				if type(f[method]) == "function" then
					hooksecurefunc(f, method, OnWindowRefresh)
				end
			end
		end
	end
end

-- The kit on: the windows dressed before come back on (the switch thrown
-- again); the others wait for their first show (DressOpen)
local function Activate()
	if active then
		return
	end
	if #Present() == 0 then
		return
	end
	active = true
	for _, s in pairs(skins) do
		EnableSkin(s)
	end
end

-- (user, 2026-09-24: "dress rarely used windows on first open") nothing of
-- a window's look is made while it has never been shown this session: each
-- is dressed on its first show (its OnShow hook, before the first frame is
-- drawn), or at once when it is up already (a /reload with it open), then
-- kept for the session. The game's refreshes (Hook) only listen until then.
local function DressOpen()
	for _, entry in ipairs(Present()) do
		if not skins[entry.f] and IsOpen(entry.f) then
			EnableSkin(Build(entry.f, entry.def))
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

Sync = function()
	Hook()
	if M.isEnabled then
		Activate()
		-- the windows up now (a window that turned up after the kit went on,
		-- an addon loaded later, is hooked above and dressed on its show)
		if active then
			DressOpen()
		end
	else
		Deactivate()
	end
end

-- (the switch and an addon's load: out of combat, as before; a window's
-- first show is dressed at once, see Hook)
local function SyncSafe()
	Kit:WhenOutOfCombat(Sync)
end

-- The windows come with Blizzard_PVPMatch (loaded with the interface here)
-- or another addon: looked for again whenever an addon loads (hooked at
-- once, even in a fight: the hooks only listen)
local watcher = CreateFrame("Frame")
Perf.SetScript(watcher, "OnEvent", function()
	Hook()
	SyncSafe()
end)

function M:OnEnable(db)
	self.db = db
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:RegisterEvent("PLAYER_LOGIN")
	Hook()
	SyncSafe()
end

function M:OnDisable()
	SyncSafe()
end

--------------------------------------------------------------------------------
-- /pvpdump [frames | reps | regions]: with no mode, every PvP window this
-- client has or lacks, and for each one here what the skin found and
-- dressed: the shell (rail, the game's nine-slice pieces, the page picture
-- and its rect, the close button, the portrait against the medallion), the
-- title (its text, font and place), the list box, the tabs (with the page
-- picture's rect, the same on every tab: one picture for the window), the
-- header plates, the rows' stripes, the rewards and buttons. The modes are
-- Kit:DumpWindow's, for every window here. Opens the copy window.
--------------------------------------------------------------------------------

local function Label(obj)
	if not obj then
		return "nil"
	end
	local n = NameOf(obj)
	if n then
		return n
	end
	local ok, d = pcall(obj.GetDebugName, obj)
	if ok and type(d) == "string" and not Secret(d) then
		return d
	end
	return "[unnamed]"
end

local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.0f", v) or "?"
end

local function Shown(obj)
	if not obj then
		return "-"
	end
	local ok, s = pcall(obj.IsShown, obj)
	return (ok and not Secret(s)) and tostring(s) or "?"
end

local function RectText(obj)
	if not obj then
		return "-"
	end
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if ok and l and not (Secret(l) or Secret(b) or Secret(w) or Secret(h)) then
		return string.format("x=%s y=%s w=%s h=%s", Num(l), Num(b), Num(w), Num(h))
	end
	return "(no rect)"
end

local function Found(label, obj, more)
	MelloUI:Print("  %-24s %s%s", label, obj and Label(obj) or "-- not found", more or "")
end

local function FadedState(obj)
	if not obj then
		return "-"
	end
	return Kit.faded[obj] and "faded" or (done[obj] and "known, not faded" or "the game's")
end

local function RepShown(rep)
	return rep and rep.object and Shown(rep.object) or "no piece"
end

local function FontText(fs)
	local okT, text = pcall(fs.GetText, fs)
	local okF, face, size = pcall(fs.GetFont, fs)
	return string.format("text %s, font %s %s, title face %s",
		(okT and type(text) == "string" and not Secret(text)) and text or "?",
		(okF and type(face) == "string" and not Secret(face)) and (face:match("([^\\/]+)$") or face) or "?",
		okF and Num(size) or "?", tostring(fs.melloFontSaved ~= nil))
end

local function DumpShell(s, f)
	Found("outer rail", s.outer and s.outer.object, " shown " .. RepShown(s.outer))
	local pieces = {}
	for _, key in ipairs(NINE_KEYS) do
		local piece = f[key]
		if type(piece) == "table" and piece.GetObjectType then
			pieces[#pieces + 1] = string.format("%s=%s (%s)", key, tostring(Kit:ArtKey(piece) or "?"), FadedState(piece))
		end
	end
	MelloUI:Print("  the game's nine-slice      %s", #pieces > 0 and table.concat(pieces, ", ") or "none laid yet (the game lays it when a match starts)")
	Found("page rock", s.page, s.page and string.format(" art %s, %s", tostring(Kit:ArtKey(s.page) or "?"), FadedState(s.page)) or nil)
	local rep = s.pageRep
	MelloUI:Print("  page picture               %s, shown %s, inner %s", rep and tostring(rep.tex and rep.tex.kitName) or "none",
		RepShown(rep), rep and rep.inner and RectText(rep.inner) or "-")
	Found("close button", f.CloseButton, " kit " .. RepShown(s.close))
	MelloUI:Print("  portrait                   none: this window has no portrait ring (nothing to fit to the medallion)")
end

local function DumpTitle(s, f)
	if not s.def.results then
		MelloUI:Print("  title                      none: the scoreboard has no title string or title art (nothing to replace)")
		return
	end
	local heading = s.title or f.header
	if heading then
		local okP, point, rel = pcall(heading.GetPoint, heading, 1)
		Found("title (the heading)", heading, string.format(" %s; parent %s, anchored %s on %s, %s", FontText(heading),
			Label(heading:GetParent()), okP and tostring(point) or "?", okP and rel and Label(rel) or "-", RectText(heading)))
	else
		Found("title (the heading)", nil)
	end
	Found("title plate", s.plate and s.plate.object, s.plate and string.format(" shown %s, %s, band %s level %s", RepShown(s.plate),
		RectText(s.plate.object), RectText(s.band), s.band and Num(s.band:GetFrameLevel()) or "-") or nil)
	local deco = f.overlay and f.overlay.decorator
	Found("faction banner", deco, deco and string.format(" art %s, shown %s, %s", tostring(Kit:ArtKey(deco) or "?"), Shown(deco), FadedState(deco)) or nil)
end

local function DumpTable(s, f)
	local c = Content(f)
	Found("list box (Content)", c, c and string.format(" %s, dressed %s, dim %s", RectText(c), RepShown(s.box),
		tostring(s.box and s.box.skin and s.box.skin.dimFill ~= nil)) or nil)
	local box = ScrollBox(f)
	Found("rows (ScrollBox)", box, box and string.format(" %s, tint %s", RectText(box), FadedState(box.Background or box.background)) or nil)
	local nRows, striped, sample = 0, 0, nil
	for _, entry in ipairs(s.rowList or {}) do
		nRows = nRows + 1
		if entry.tex:IsShown() then
			striped = striped + 1
		end
		if not sample and entry.tint then
			sample = string.format("%.2f %.2f %.2f", entry.tint[1], entry.tint[2], entry.tint[3])
		end
	end
	MelloUI:Print("  rows seen %d, stripes shown %d (every other one fainter), a faction tint read %s", nRows, striped, sample or "none yet")
	local band = Categories(f)
	local nHeaders, plated = 0, 0
	for _, header in ipairs(s.headerList or {}) do
		nHeaders = nHeaders + 1
		local entry = headers[header]
		if entry and entry.rep and entry.rep.object:IsShown() then
			plated = plated + 1
		end
	end
	Found("header band", band, band and string.format(" %s, headers %d, plates shown %d (labels in gold while on)", RectText(band), nHeaders, plated) or nil)
	for i, header in ipairs(s.headerList or {}) do
		if i > 12 then
			break
		end
		local entry = headers[header]
		local text = entry and entry.text
		local okT, t = false, nil
		if text then
			okT, t = pcall(text.GetText, text)
		end
		MelloUI:Print("    header %d: %s %s shown %s, plate %s", i, (okT and type(t) == "string" and not Secret(t)) and t or "(icon)",
			RectText(header), Shown(header), entry and RepShown(entry.rep) or "-")
	end
	local bar = ScrollBar(f)
	Found("scroll bar", bar, bar and (" dressed " .. tostring(bar.melloRep ~= nil and bar.melloRep ~= false)) or nil)
	local tc = TabContainer(f)
	Found("tab strip", tc, tc and string.format(" top line %s, bottom line %s", FadedState(tc.InsetBorderTop), FadedState(tc.InsetBorderBottom)) or nil)
	local pageRect = s.pageRep and s.pageRep.inner and RectText(s.pageRep.inner) or "-"
	for _, tab in ipairs(Tabs(f)) do
		local okT, t = pcall(tab.GetText, tab)
		local open = tab.LeftActive and tab.LeftActive:IsShown()
		local cards = 0
		for _, entry in ipairs(s.tabReps) do
			if (entry.region == tab.Left or entry.region == tab.LeftActive) and entry.rep.object:IsShown() then
				cards = cards + 1
			end
		end
		Found("tab", tab, string.format(" %s, shown %s, open %s, TB6 cards shown %d, page picture %s",
			(okT and type(t) == "string" and not Secret(t)) and t or "?", Shown(tab), tostring(open), cards, pageRect))
	end
end

local function DumpResults(s, f)
	if not s.def.results then
		return
	end
	local bc = f.buttonContainer
	for _, b in ipairs(List(f.requeueButton or (bc and bc.requeueButton), f.leaveButton or (bc and bc.leaveButton))) do
		local okE, enabled = pcall(b.IsEnabled, b)
		Found("button", b, string.format(" shown %s, enabled %s, red plate %s", Shown(b), (okE and not Secret(enabled)) and tostring(enabled) or "?",
			tostring(b.melloRep ~= nil and b.melloRep ~= false)))
	end
	MelloUI:Print("  reward rims %d (items in the Button Border rim, quality border kept); honour %s, conquest %s", #s.rimHolders,
		tostring(f.honorButton and done[f.honorButton] == true), tostring(f.conquestButton and done[f.conquestButton] == true))
	Found("header glow", f.glowTop, " " .. FadedState(f.glowTop))
	local art = f.earningsArt
	Found("reward band", art and art.background, art and (" " .. FadedState(art.background)) or nil)
end

local function DumpWindow(entry)
	local f, def = entry.f, entry.def
	local s = skins[f]
	local okLv, lv = pcall(f.GetFrameLevel, f)
	MelloUI:Print("%s (%s): shown %s, %s, strata %s, level %s; kit %s, pieces %d, faded art %d", def.name, def.label, Shown(f), RectText(f),
		tostring(f:GetFrameStrata()), okLv and Num(lv) or "?", active and "on" or "off", s and #s.reps or 0, s and #s.faded or 0)
	if not s then
		MelloUI:Print("  not dressed yet: the kit dresses it the first time it opens (open it once for the kit's side)")
		return
	end
	if def.kind == "match" then
		DumpShell(s, f)
		DumpTitle(s, f)
		DumpTable(s, f)
		DumpResults(s, f)
	else
		MelloUI:Print("  a classic window: shell %s (a modern template's NineSlice %s), ring %s, portrait fitted %s", tostring(s.shell == true),
			tostring(f.NineSlice ~= nil), tostring(s.ring ~= nil), tostring(s.portrait and s.portrait.melloSaved ~= nil))
		if not s.shell then
			MelloUI:Print("  loose file art: only its common controls are dressed; paste /pvpdump regions to map the rest")
		end
		for _, tab in ipairs(Tabs(f)) do
			Found("tab", tab, " dressed " .. tostring(tab.melloRep ~= nil and tab.melloRep ~= false))
		end
	end
	MelloUI:Print("  inked strings: none (no parchment on this window)")
end

SLASH_MELLOPVPDUMP1 = "/pvpdump"
SlashCmdList.MELLOPVPDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	MelloUI:ClearLog()
	local loaded = "?"
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		local ok, v = pcall(C_AddOns.IsAddOnLoaded, "Blizzard_PVPMatch")
		loaded = ok and tostring(v) or "?"
	end
	MelloUI:Print("/pvpdump: Blizzard_PVPMatch loaded %s; kit %s", loaded, active and "on" or "off")
	local present = Present()
	local here = {}
	for _, entry in ipairs(present) do
		here[entry.def.name] = true
	end
	for _, def in ipairs(WINDOWS) do
		if not here[def.name] then
			MelloUI:Print("%s (%s): not on this client%s", def.name, def.label, def.absent and (" -- " .. def.absent) or "")
		end
	end
	for _, entry in ipairs(present) do
		if msg == "frames" or msg == "reps" or msg == "regions" then
			MelloUI:Print("%s:%s", entry.def.name, skins[entry.f] and "" or " (not dressed yet: the kit dresses it the first time it opens)")
			Kit:DumpWindow(entry.f, skins[entry.f], msg ~= "regions" and msg or nil)
		else
			DumpWindow(entry)
		end
	end
	MelloUI:ShowLog("pvpdump " .. msg)
end
