--------------------------------------------------------------------------------
-- MelloUI - Auction House Kit
--
-- (user, 2026-09-24: "we didnt do quest dialogs, shops, Auction House,
-- profession training window, class trainers, Guild Crest Vendors, Flight
-- map, all should follow the rules"): the auction house (AuctionHouseFrame,
-- from the load-on-demand Blizzard_AuctionHouseUI: Buy, Sell and Auctions)
-- dressed in the painted kit (Modules/Kit.lua) on the game's own layout, by
-- the rule book's fixed looks (docs/WINDOW-RULES.md):
--
--   the window shell     outer double rail with gem corners, one page stone,
--                        the ring on the portrait corner with the auctioneer
--                        at the class medallion's size on the dark disc
--                        (2b), the title plate riding the rail with the
--                        title ON it in the title face (2c), the close button
--   the bottom tabs and  TB6 cards (Kit:SkinPanelTab; an older tab template
--   the sub-tabs         with a LeftDisabled set gets the same two cards)
--   every box            the game's boxes (AuctionHouseBackgroundTemplate: a
--                        Background picture and an inset NineSlice -- the
--                        category list, the results, the sell form, the sell
--                        lists, your auctions and bids, the item headers) on
--                        the list box L1: the single rail with its stone
--                        under the palette's inner panel (eye strain, 2e),
--                        drawn as REGIONS of the box, so the stone always
--                        lies under the box's scroll box and rows
--   the category rows    the list plate (plain, hover from the button), the
--                        selected plate while the game marks the row
--   the list rows        the quest log's hover plate on hover only, the
--                        selected plate while the game marks the row
--   column headers       the header plate (GC1, cap-less as the guild's)
--   inputs               the edit plate (S1) with its plain left end on the
--                        quantity and the gold / silver / copper boxes; the
--                        search box by the sweep
--   dropdowns, check     D1, the kit's check box, red plates (B1), the
--   boxes, buttons,      minimal scroll bar -- by the sweep
--   scroll bars          (Kit:SweepControls); an older dropdown on D1 too
--   small buttons        the favourites star and the refresh buttons on the
--                        cog plate (K2) under the game's icon; the Filter
--                        button on the kit's filter-dropdown plate
--   the item slot        the round rim (O2, the Round Border) tinted like
--                        the game's quality border -- or, on a client whose
--                        slot is square, the Button Border rim
--   the money box        the coin plate (B2, as the bags'), the inset behind
--                        it faded
--
-- Nothing of the game's is replaced or re-scripted: post hooks, HookScript,
-- scroll box callbacks under our own owner key and events only, our state in
-- weak side tables; no auction API is ever called. Switching the module off
-- disables every replacement (the game's art faded back in, ours hidden),
-- un-fades what was faded, hides the inner panels and the tab cards, and
-- puts the portrait and the title back: the window is the game's again.
--
-- The game's source for this window is not at hand for this client, so every
-- part is found by what it IS at run time; /auctiondump says what was found
-- and dressed on each tab, and what was seen but left as the game's.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("AuctionHousePanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("AuctionHousePanel", {
	title = "Auction House Kit",
	desc = "The auction house (buy, sell, your auctions) in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local ADDON = "Blizzard_AuctionHouseUI"
-- the rule keys this window's parts are dressed as (the same atlas, the same
-- piece: every one is a mapping the kit already has, but the box's)
local BOX_KEY = "AuctionHouseBackgroundTemplate"   -- L1 as regions of the box, with the inner panel
local PLATE_KEY = "QuestListFilter"                -- lists/plate plain (a category row)
local SELECTED_KEY = "QuestListFilter-Selected"    -- lists/plate selected
local HOVER_KEY = "questlog-quest-glow-yellow"     -- lists/plate hover (the quest log's row hover)
local HEADER_KEY = "ColumnDisplayButton"           -- lists/header (GC1)
local EDIT_KEY = "common-search-border-middle"     -- inputs/edit (S1)
local COIN_KEY = "common-coinbox-center"           -- lists/header under the money (B2)
local SQUARE_KEY = "UI-SquareButton-Up"            -- buttons/cog under a square icon button (K2)
local FILTER_KEY = "common-dropdown-b-button"      -- the filter dropdown's plate
local OLD_DROPDOWN_KEY = "UIDropDownMenu"          -- inputs/dropdown on an older dropdown (D1)
local ROUND_KEY = "auctionhouse-itemicon-border-white"   -- buttons/roundslot, tinted (O2)
-- the ring's picture when the game gives the portrait none (2b: a ring is
-- never empty): the auctioneer's own mark, drawn UNDER the game's portrait
local PORTRAIT_FALLBACK = "Interface\\Minimap\\Tracking\\Auctioneer"

local skin = nil          -- { reps = {}, followers = {}, eyePanels = {} } once built
local active = false
local hooked = false

-- Our state beside the game's frames, never written onto them (weak keys:
-- a pooled row the game lets go of takes its entry with it). The Kit's own
-- `melloRep` markers are the one exception, as in every window module: the
-- sweep reads them to leave a control it did not dress alone.
local done = setmetatable({}, { __mode = "k" })         -- [frame / region] = true: looked at once
local rowState = setmetatable({}, { __mode = "k" })     -- [row] = { plate, hover, selected, sel }
local listKind = setmetatable({}, { __mode = "k" })     -- [scroll box] = "category" | "list": hooked
local listRows = setmetatable({}, { __mode = "k" })     -- [scroll box] = rows dressed, for the dump
local headerHooked = setmetatable({}, { __mode = "k" }) -- [item list] = true
local tabReps = {}        -- the tabs' cards { rep, region } (kept hidden while the kit is off)
local fadedArt = {}       -- art faded with no piece of its own standing in (the money inset)
local rimHolders = {}     -- { melloRep = rim }: the square item rims, for the Button Border registry (strong: it is weak)
local titleMoved = {}     -- [fs] = { points } while another title string sits on the plate
local titleFaded = {}     -- [fs] = true while faded as a duplicate of the plate's title
local listOwner = {}      -- our own key in the lists' callback registries (never the game's)
local found = { parts = {}, missing = {}, missed = setmetatable({}, { __mode = "k" }) }
local stats = { boxes = 0, rows = 0, headers = 0, edits = 0, squares = 0, items = 0, tabs = 0 }

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe and MelloUI.Safe.IsSecret or issecretvalue

local function Window()
	return _G.AuctionHouseFrame
end

-- a frame's name for the dump (a pooled frame's can read secret)
local function NameOf(obj)
	if not obj then
		return "nil"
	end
	local ok, n = pcall(obj.GetName, obj)
	if ok and type(n) == "string" and not Secret(n) then
		return n
	end
	local okD, d = pcall(obj.GetDebugName, obj)
	if okD and type(d) == "string" and not Secret(d) then
		return d
	end
	return "[" .. tostring(obj.GetObjectType and obj:GetObjectType() or "?") .. "]"
end

local function MouseOver(frame)
	local ok, over = pcall(frame.IsMouseOver, frame)
	return ok and not Secret(over) and over == true
end

local function IsTexture(obj)
	return type(obj) == "table" and obj.GetObjectType ~= nil and obj:GetObjectType() == "Texture"
end

-- the non-nil values given, as a list (alsoFade stops at the first nil)
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

-- for the dump: what was dressed as what, and what was seen but left alone
local function Note(obj, piece)
	if obj then
		found.parts[#found.parts + 1] = { obj = obj, piece = piece }
	end
end

local function Miss(obj, why)
	if obj and not found.missed[obj] then
		found.missed[obj] = why
		found.missing[#found.missing + 1] = obj
	end
end

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Auction house kit: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- A piece the game shows and hides itself (a selection, a tab's two looks):
-- shown with its region while the kit is on.
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

-- Art with no piece of its own standing in for it (the money inset behind
-- the coin plate): faded while the kit is on, back on disable.
local function FadeArt(obj)
	if obj and not done[obj] then
		done[obj] = true
		fadedArt[#fadedArt + 1] = obj
		if active then
			Kit:Fade(obj)
		end
	end
end

local function IsScrollBox(frame)
	return frame.ForEachFrame ~= nil and frame.ScrollTarget ~= nil
end

-- Every frame under `root`, parents before children; a list's scroll box is
-- handed over but never walked into (its rows are the list's, dressed as the
-- list initialises them), nor are the kit's own frames.
local function Walk(root, fn, depth)
	depth = depth or 0
	if not (root and root.GetChildren) or depth > 10 then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		if not child.melloSkin then
			fn(child)
			if not IsScrollBox(child) then
				Walk(child, fn, depth + 1)
			end
		end
	end
end

-- A three-piece art strip (Left / Middle / Right, by key, by a name's
-- suffix, else the widest of exactly three textures as the middle and the
-- other two its ends).
local function ThreeSlice(frame)
	local name = frame.GetName and frame:GetName()
	name = type(name) == "string" and not Secret(name) and name or nil
	local function Part(...)
		for i = 1, select("#", ...) do
			local key = select(i, ...)
			local v = frame[key] or (name and _G[name .. key])
			if IsTexture(v) then
				return v
			end
		end
	end
	local left, mid, right = Part("Left"), Part("Middle", "Mid", "Center"), Part("Right")
	if left and mid and right then
		return left, mid, right
	end
	local textures, best, widest = {}, 0, nil
	for _, region in ipairs({ frame:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece then
			local okL, layer = pcall(region.GetDrawLayer, region)
			if okL and (layer == "BACKGROUND" or layer == "BORDER") then
				textures[#textures + 1] = region
				local ok, w = pcall(region.GetWidth, region)
				if ok and w and not Secret(w) and w > best then
					widest, best = region, w
				end
			end
		end
	end
	if widest and #textures == 3 then
		local ends = {}
		for _, tex in ipairs(textures) do
			if tex ~= widest then
				ends[#ends + 1] = tex
			end
		end
		return ends[1], widest, ends[2]
	end
end

--------------------------------------------------------------------------------
-- The window shell: the rail, the page stone, the ring with the auctioneer,
-- the title plate with the title on it, the close button.
--------------------------------------------------------------------------------
local function Portrait(f)
	local pc = f.PortraitContainer
	return (pc and pc.portrait) or f.portrait or _G.AuctionHouseFramePortrait
end

local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
	end
end

-- The portrait (the auctioneer the game draws with SetPortraitToUnit) at the
-- class medallion's size on the dark disc (WINDOW-RULES 2b): a unit portrait
-- is a round picture that covers the opening at that size; the disc lies
-- under it all the same, and under the portrait -- never over it -- the
-- auctioneer's mark, which shows only where the game gives the portrait no
-- picture, so the ring is never empty (2c: "an empty ring is a bug").
local function SkinPortrait(f, ring)
	local portrait = Portrait(f)
	if not (ring and portrait) then
		Miss(f, "no portrait ring: the window has no portrait corner on this client")
		return
	end
	local disc = Kit:RingDisc(ring)
	local host = disc and disc:GetParent()
	local mark
	if host and host.CreateTexture then
		-- a region of the portrait's own frame, in the layer under the
		-- portrait (OVERLAY in PortraitFrameTemplate) and over the disc
		mark = host:CreateTexture(nil, "ARTWORK", nil, 7)
		mark.kitPiece = true
		mark:SetTexture(PORTRAIT_FALLBACK)
		mark:SetAllPoints(disc)
		local mask = host:CreateMaskTexture()
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(mark)
		mark:AddMaskTexture(mask)
		mark:SetShown(active)
	end
	skin.portrait, skin.mark = portrait, mark
	local onEnable, onDisable = ring.onEnable, ring.onDisable
	ring.onEnable = function(r)
		if onEnable then
			onEnable(r)
		end
		pcall(Kit.FitPortrait, Kit, portrait, ring)
		if mark then
			mark:Show()
		end
	end
	ring.onDisable = function(r)
		if onDisable then
			onDisable(r)
		end
		pcall(Kit.UnfitPortrait, Kit, portrait)
		if mark then
			mark:Hide()
		end
	end
	Note(portrait, "portrait at the medallion size on the disc (2b)")
end

-- Title strings other than the title container's (an older window's own
-- TitleText): put on the plate in the title face, or faded where they only
-- repeat the plate's words; points and font back on disable. (2c: the title
-- plate's rule itself centres the container's TitleText on the plate in the
-- title face, Kit:TitleFont, and puts it back on disable.)
local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	if ok and type(text) == "string" and not Secret(text) and text ~= "" then
		return text
	end
end

local function PlaceTitles(on)
	local f = Window()
	if not f then
		return
	end
	if not on then
		for fs, points in pairs(titleMoved) do
			Kit:TitleFont(fs, false)
			fs:ClearAllPoints()
			for _, pt in ipairs(points) do
				fs:SetPoint(unpack(pt))
			end
		end
		wipe(titleMoved)
		for fs in pairs(titleFaded) do
			Kit:Unfade(fs)
		end
		wipe(titleFaded)
		return
	end
	local rep = TitleRep()
	if not rep then
		return
	end
	local own = f.TitleContainer and f.TitleContainer.TitleText
	local ownText = own and TextOf(own)
	for _, fs in ipairs(List(f.TitleText, _G.AuctionHouseFrameTitleText)) do
		if fs ~= own and type(fs) == "table" and fs.GetObjectType and fs:GetObjectType() == "FontString" and TextOf(fs) then
			if ownText and TextOf(fs) == ownText then
				if not titleFaded[fs] then
					titleFaded[fs] = true
					Kit:Fade(fs)
				end
			else
				if not titleMoved[fs] then
					local points = {}
					for i = 1, fs:GetNumPoints() do
						points[i] = { fs:GetPoint(i) }
					end
					titleMoved[fs] = points
				end
				fs:ClearAllPoints()
				fs:SetPoint("CENTER", own or rep.strip or rep.object, "CENTER")
				Kit:TitleFont(fs, true)
			end
		end
	end
end

local function SkinShell(f)
	local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = Portrait(f), bg = "UI-Background-Rock" })
	skin.ring = ring
	Note(f.NineSlice, "outer double rail with gem corners, page stone")
	Note(f.TitleContainer, "title plate on the rail, title in the title face (2c)")
	Note(f.CloseButton, "close button")
	SkinPortrait(f, ring)
end

--------------------------------------------------------------------------------
-- Tabs: the bottom tabs (Buy / Sell / Auctions) and the Auctions page's
-- sub-tabs, TB6 cards. The Kit's cards follow their tab's textures on every
-- Show / Hide, also while the kit is off (a card would come back over the
-- game's own tab on the next tab switch): after those hooks, GuardTabs sets
-- every card from its texture while the kit is on and hides them while off
-- (the macro window's lesson, 2026-09-24).
--------------------------------------------------------------------------------
local function GuardTabs()
	for _, entry in ipairs(tabReps) do
		if active then
			entry.rep:SetShown(entry.region:IsShown())
		else
			entry.rep.object:Hide()
		end
	end
end

local function TabPart(tab, key)
	local v = tab[key]
	if v == nil then
		local name = tab.GetName and tab:GetName()
		v = type(name) == "string" and not Secret(name) and _G[name .. key] or nil
	end
	return IsTexture(v) and v or nil
end

local function IsTab(frame)
	return frame:GetObjectType() == "Button" and IsTexture(frame.Left) and (IsTexture(frame.LeftActive) or TabPart(frame, "LeftDisabled") ~= nil)
end

local function SkinTab(tab)
	if done[tab] then
		return
	end
	done[tab] = true
	local plainTex, openTex
	local first = #skin.followers + 1
	if IsTexture(tab.LeftActive) then
		plainTex, openTex = tab.Left, tab.LeftActive
		Kit:SkinPanelTab(tab, Replace, skin)
	else
		-- an older tab (Left for the closed tab, LeftDisabled for the open
		-- one: the game selects a tab by disabling it): the same two cards
		plainTex, openTex = TabPart(tab, "Left"), TabPart(tab, "LeftDisabled")
		if not (plainTex and openTex) or tab.melloRep ~= nil then
			return
		end
		tab.melloRep = false
		local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
		local plain = Replace(plainTex, { as = "uiframe-tab-left", rect = tab, button = tab, alsoFade = List(TabPart(tab, "Middle"), TabPart(tab, "Right"), hl) })
		local open = Replace(openTex, { as = "uiframe-activetab-left", rect = tab, alsoFade = List(TabPart(tab, "MiddleDisabled"), TabPart(tab, "RightDisabled")) })
		tab.melloRep = plain or open or false
		Follow(plain, plainTex)
		Follow(open, openTex)
	end
	for i = first, #skin.followers do
		tabReps[#tabReps + 1] = skin.followers[i]
	end
	for _, tex in ipairs({ plainTex, openTex }) do
		hooksecurefunc(tex, "Show", GuardTabs)
		hooksecurefunc(tex, "Hide", GuardTabs)
		hooksecurefunc(tex, "SetShown", GuardTabs)
	end
	stats.tabs = stats.tabs + 1
	Note(tab, "TB6 tab card")
end

--------------------------------------------------------------------------------
-- The boxes (AuctionHouseBackgroundTemplate: a Background picture and an
-- InsetFrameTemplate NineSlice at the box's own level): the list box L1 --
-- the single rail at the one inside weight, the list-box stone, the
-- palette's inner panel over it (the rule's dim, WINDOW-RULES 2e: a list, a
-- form of prices, is text on a dark panel, never on the brown) -- all as
-- REGIONS of the box, where the game's own inset border is drawn too (under
-- the rows: the same point in the stack). A region of the box is drawn under
-- every frame the box holds, whatever its level: the stone can never cover
-- the scroll box and its rows (the AddOn list's lesson, user 2026-09-24: a
-- holder a level too high hid every row), nor tie with the page stone below.
--------------------------------------------------------------------------------
local function IsBox(frame)
	if frame == Window() then
		return false
	end
	local nine = frame.NineSlice
	if not (type(nine) == "table" and nine.GetRegions) then
		return false
	end
	-- a Background picture, or an inset nine-slice with no marble of its own
	-- (one with a Bg is an InsetFrameTemplate: the sweep's)
	return IsTexture(frame.Background) or (nine.layoutType == "InsetFrameTemplate" and frame.Bg == nil)
end

local function SkinBox(box)
	if done[box] then
		return
	end
	done[box] = true
	local extra = {}
	for _, region in ipairs({ box.NineSlice:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece then
			extra[#extra + 1] = region
		end
	end
	local art = IsTexture(box.Background) and box.Background or table.remove(extra, 1)
	if not art then
		Miss(box, "a box with no art to stand in for")
		return
	end
	if Replace(art, { as = BOX_KEY, rect = box, parent = box, alsoFade = extra }) then
		stats.boxes = stats.boxes + 1
		Note(box, "L1 box: single rail, stone, inner panel 0.8 (2e)")
	end
end

-- the box a list's scroll box lies in (a parent or grandparent dressed as one)
local function BoxOf(frame)
	local p = frame:GetParent()
	for _ = 1, 3 do
		if not p then
			return nil
		end
		if done[p] and IsBox(p) then
			return p
		end
		p = p:GetParent()
	end
end

--------------------------------------------------------------------------------
-- The column headers (a table builder's header buttons in the list's
-- HeaderContainer, made when the game lays the list out): the header plate
-- GC1 on each, cap-less (one wide column took the caps on the guild roster,
-- its gem under the text), the sort arrow and the text the game's. Dressed
-- before any sweep, which would read a header as a red button.
--------------------------------------------------------------------------------
local function SkinHeader(header)
	if done[header] or header.melloRep ~= nil then
		return
	end
	done[header] = true
	local mid = IsTexture(header.Middle) and header.Middle or (IsTexture(header.Center) and header.Center) or nil
	local extra = {}
	for _, region in ipairs({ header:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece and region ~= header.Arrow and region ~= mid then
			local ok, layer = pcall(region.GetDrawLayer, region)
			if ok and (layer == "BACKGROUND" or layer == "BORDER" or layer == "HIGHLIGHT") then
				if not mid and layer ~= "HIGHLIGHT" then
					mid = region
				else
					extra[#extra + 1] = region
				end
			end
		end
	end
	local hl = header.GetHighlightTexture and header:GetHighlightTexture()
	if hl and hl ~= mid then
		extra[#extra + 1] = hl
	end
	if not mid then
		-- a header that draws no art of its own: nothing to replace
		header.melloRep = false
		Miss(header, "a column header with no art (text only): left as the game's")
		return
	end
	header.melloRep = Replace(mid, { as = HEADER_KEY, rect = header, button = header, capless = true, alsoFade = extra }) or false
	if header.melloRep then
		stats.headers = stats.headers + 1
		Note(header, "GC1 header plate")
	end
end

local function SkinHeaders(list)
	local container = list.HeaderContainer
	if not (type(container) == "table" and container.GetChildren) then
		return
	end
	for _, child in ipairs({ container:GetChildren() }) do
		if child:GetObjectType() == "Button" then
			SkinHeader(child)
		end
	end
end

-- the headers are (re)made when the game lays the list out: after each
local function HookHeaders(list)
	if headerHooked[list] then
		return
	end
	headerHooked[list] = true
	local function Again()
		if active then
			SkinHeaders(list)
		end
	end
	for _, method in ipairs({ "SetTableBuilderLayout", "RefreshScrollFrame", "Reset" }) do
		if type(list[method]) == "function" then
			hooksecurefunc(list, method, Again)
		end
	end
	local container = list.HeaderContainer
	if type(container) == "table" and container.HookScript then
		Perf.HookScript(container, "OnShow", Again)
	end
end

--------------------------------------------------------------------------------
-- The rows of a list (pooled by its scroll box; each dressed once, the looks
-- then follow its re-use through the game's own textures):
--   a category row (the grey navigation buttons): the list plate on its
--   button art, its hover from the button;
--   a list row (results, sell lists, your auctions and bids): the quest
--   log's hover plate while the mouse is on the row (the game's highlight
--   draws only on hover too), under the row's cells;
--   either: the selected plate while the game shows the row's selection.
--------------------------------------------------------------------------------
local function RowHighlights(row)
	local list, seen = {}, {}
	local hl = row.GetHighlightTexture and row:GetHighlightTexture()
	if hl then
		list[1], seen[hl] = hl, true
	end
	for _, region in ipairs({ row:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece and not seen[region] then
			local ok, layer = pcall(region.GetDrawLayer, region)
			if ok and layer == "HIGHLIGHT" then
				list[#list + 1], seen[region] = region, true
			end
		end
	end
	return list
end

local function RowSelection(row)
	for _, key in ipairs({ "SelectedHighlight", "SelectedTexture", "Selected", "SelectionHighlight", "Selection" }) do
		if IsTexture(row[key]) then
			return row[key]
		end
	end
end

-- a category row's button art (the grey navigation plate the game atlases)
local function RowPlateArt(row, kind)
	local normal = IsTexture(row.NormalTexture) and row.NormalTexture or (row.GetNormalTexture and row:GetNormalTexture())
	if not normal then
		return nil
	end
	local key = Kit:ArtKey(normal)
	if kind == "category" or (type(key) == "string" and key:find("nav%-button")) then
		return normal
	end
end

local function SyncHover(row)
	local st = rowState[row]
	if st and st.hover then
		local over = active and MouseOver(row)
		st.hover.object:SetShown(over and true or false)
		if over then
			st.hover:Refit()
		end
	end
end

local function RowEnterLeave(self)
	SyncHover(self)
end

-- the row's own controls stay the row's: the sweep, which walks every frame,
-- leaves a control marked as looked at alone
local function MarkRowControls(row, depth)
	depth = depth or 0
	if depth > 3 then
		return
	end
	for _, child in ipairs({ row:GetChildren() }) do
		local kind = child:GetObjectType()
		if child.melloRep == nil and (kind == "CheckButton" or (kind == "Button" and (child.Center or (child.Left and child.Middle and child.Right)))) then
			child.melloRep = false
		end
		MarkRowControls(child, depth + 1)
	end
end

local function SkinRow(row, kind, box)
	if not (row and row.GetRegions) then
		return
	end
	local st = rowState[row]
	if not st then
		st = {}
		rowState[row] = st
		stats.rows = stats.rows + 1
		listRows[box] = (listRows[box] or 0) + 1
		local highlights = RowHighlights(row)
		local plateArt = RowPlateArt(row, kind)
		if plateArt then
			st.plate = Replace(plateArt, { as = PLATE_KEY, rect = row, button = row, alsoFade = highlights })
		else
			-- a frame of ours one level under the row, under its cells
			st.hover = Replace(row, { as = HOVER_KEY, parent = row, rect = row, noFade = true, alsoFade = highlights })
			if st.hover then
				st.hover.onEnable = function()
					SyncHover(row)
				end
				Perf.HookScript(row, "OnEnter", RowEnterLeave)
				Perf.HookScript(row, "OnLeave", RowEnterLeave)
			end
		end
		local sel = RowSelection(row)
		if sel then
			st.sel = sel
			st.selected = Replace(sel, { as = SELECTED_KEY, rect = row })
			Follow(st.selected, sel)
		end
		MarkRowControls(row)
	end
	-- (re-initialised for another entry: its looks from the game's state now)
	SyncHover(row)
	if active and st.selected and st.sel then
		st.selected:SetShown(st.sel:IsShown())
	end
end

local function WalkRows(box, kind)
	if not (box and box.ForEachFrame) or (box.HasView and not box:HasView()) then
		return
	end
	pcall(box.ForEachFrame, box, function(row)
		SkinRow(row, kind, box)
		-- (nothing returned: a value would stop the iteration)
	end)
end

local function HookList(box, kind)
	if listKind[box] then
		return
	end
	listKind[box] = kind
	listRows[box] = listRows[box] or 0
	local add = ScrollUtil and (ScrollUtil.AddInitializedFrameCallback or ScrollUtil.AddAcquiredFrameCallback)
	if add then
		-- after the row's own Init (its look is known only then), under our
		-- own owner key, so no listener of the game's is displaced
		add(box, function(_, row)
			if active then
				SkinRow(row, kind, box)
			end
		end, listOwner, false)
	end
	if active then
		WalkRows(box, kind)
	end
end

--------------------------------------------------------------------------------
-- Inputs, dropdowns and small buttons
--------------------------------------------------------------------------------

-- A one-line edit box (the quantity, the gold / silver / copper boxes; an
-- InputBoxTemplate's Left / Middle / Right art reaching a few px past the
-- box): the edit plate S1 on the art's own span, its LEFT cap dropped -- that
-- cap is the search glass, and these are number boxes; the plain end piece
-- closes the plate (the chat's and Edit Mode's rule). A narrow box goes
-- cap-less by itself; the coin icon of a money box stays over the plate.
local function SkinEdit(edit)
	if done[edit] or edit.melloRep ~= nil or edit.searchIcon then
		return
	end
	done[edit] = true
	local left, mid, right = ThreeSlice(edit)
	if not (left and mid and right) then
		Miss(edit, "an edit box with no Left / Middle / Right art")
		return
	end
	local rect = CreateFrame("Frame", nil, edit)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", left, "TOPLEFT")
	rect:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT")
	if Replace(mid, { as = EDIT_KEY, rect = rect, edit = edit, dropCap = "l", alsoFade = { left, right } }) then
		stats.edits = stats.edits + 1
		Note(edit, "S1 edit plate, plain left end")
	end
end

-- An older dropdown (UIDropDownMenuTemplate: Left / Middle / Right art 64 px
-- tall round a 24 px box, an arrow Button): D1 on the box, the arrow's art
-- faded, as the AddOn list's. A modern one (Background / Arrow / Text) is
-- the sweep's.
local function SkinOldDropdown(dd)
	if done[dd] or dd.melloRep ~= nil then
		return
	end
	done[dd] = true
	local extra = List(dd.Left, dd.Right)
	for _, region in ipairs({ dd.Button:GetRegions() }) do
		if IsTexture(region) then
			extra[#extra + 1] = region
		end
	end
	dd.melloRep = Replace(dd.Middle, { as = OLD_DROPDOWN_KEY, rect = dd, fitHeight = 24, alsoFade = extra }) or false
	if dd.melloRep then
		Note(dd, "D1 dropdown plate")
	end
end

-- The Filter button on an older client (UIMenuButtonStretchTemplate: nine
-- pieces round a text and an arrow icon): the plate the kit gives the
-- modern filter dropdown (common-dropdown-b-button, hover / pressed from the
-- button) on its rect, its text and arrow on top. The modern one
-- (WowStyle1FilterDropdown) is the sweep's, as that same plate.
local STRETCH_PIECES = { "TopLeft", "TopRight", "BottomLeft", "BottomRight", "TopMiddle", "MiddleLeft", "MiddleRight", "BottomMiddle" }
local function SkinFilter(button)
	if done[button] or button.melloRep ~= nil then
		return
	end
	done[button] = true
	local extra = {}
	for _, key in ipairs(STRETCH_PIECES) do
		if IsTexture(button[key]) then
			extra[#extra + 1] = button[key]
		end
	end
	local hl = button.GetHighlightTexture and button:GetHighlightTexture()
	if hl then
		extra[#extra + 1] = hl
	end
	button.melloRep = Replace(button.MiddleMiddle, { as = FILTER_KEY, rect = button, button = button, parent = button, alsoFade = extra }) or false
	if button.melloRep then
		Note(button, "filter dropdown plate")
	end
end

-- A square icon button (the favourites star, the lists' refresh): the cog
-- plate K2 under the game's icon, which stays; a button whose picture is its
-- own normal texture (no separate icon) is left as the game's -- fading it
-- would take the picture with it.
local function IsSquare(button)
	if button:GetObjectType() ~= "Button" or button.IconBorder or not IsTexture(button.Icon) then
		return false
	end
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if not normal or normal == button.Icon then
		return false
	end
	local ok, w, h = pcall(button.GetSize, button)
	if not (ok and w and h) or Secret(w) or Secret(h) then
		return false
	end
	return w >= 16 and w <= 44 and math.abs(w - h) <= 6
end

local function SkinSquare(button)
	if done[button] or button.melloRep ~= nil then
		return
	end
	done[button] = true
	button.melloRep = Replace(button:GetNormalTexture(), { as = SQUARE_KEY, button = button, alsoFade = Kit:OtherTextures(button, button.Icon) }) or false
	if button.melloRep then
		stats.squares = stats.squares + 1
		Note(button, "K2 cog plate under the game's icon")
	end
end

--------------------------------------------------------------------------------
-- The item slot (the sell form's item, the buy pages' and your auctions'
-- item headers). The auction house's item button is round: its border is
-- the auctionhouse-itemicon-border atlas the professions' output icon wears
-- too, which has its mapping already -- the round rim O2, following the
-- Round Border option, tinted with the game's quality colour. Unlike the
-- output icon it stays on while the slot is empty (untinted then): the
-- empty slot's frame is the game's too, and a slot without its rim reads as
-- a hole in the form. The game's empty-slot emblem stays inside the rim. A
-- client whose slot is square gets the Button Border rim every window's
-- square buttons wear.
--------------------------------------------------------------------------------
local function ItemArtIsRound(button)
	if button.IconMask or button.CircleMask then
		return true
	end
	for _, region in ipairs({ button:GetRegions() }) do
		if IsTexture(region) then
			local key = Kit:ArtKey(region)
			if type(key) == "string" and key:find("^auctionhouse%-itemicon") then
				return true
			end
		end
	end
	return false
end

local function SkinItemButton(button)
	if done[button] or button.melloRep ~= nil then
		return
	end
	done[button] = true
	local border = button.IconBorder
	if not IsTexture(border) then
		Miss(button, "an item button with no border texture")
		return
	end
	local extra = {}
	for _, region in ipairs({ button:GetRegions() }) do
		if region ~= border and IsTexture(region) and not region.kitPiece then
			local key = Kit:ArtKey(region)
			if type(key) == "string" and key:find("^auctionhouse%-itemicon%-border") then
				extra[#extra + 1] = region      -- the border's hover copy
			end
		end
	end
	local hl = button.GetHighlightTexture and button:GetHighlightTexture()
	if hl then
		extra[#extra + 1] = hl
	end
	if not ItemArtIsRound(button) then
		local rep = Replace(border, { as = Kit:ButtonRimRule(), button = button, parent = button, alsoFade = extra })
		button.melloRep = rep or false
		if rep then
			local holder = { melloRep = rep }
			rimHolders[#rimHolders + 1] = holder
			Kit:RegisterButtonRim(holder)
			stats.items = stats.items + 1
			Note(button, "Button Border rim (a square slot)")
		end
		return
	end
	local rep = Replace(border, { as = ROUND_KEY, button = button, parent = button, alsoFade = extra })
	button.melloRep = rep or false
	if not rep then
		return
	end
	local function Tint()
		if not active then
			return
		end
		local ok, r, g, b = pcall(border.GetVertexColor, border)
		if border:IsShown() and ok and r and not Secret(r) then
			rep.object:SetVertexColor(r, g, b)
		else
			rep.object:SetVertexColor(1, 1, 1)
		end
	end
	for _, method in ipairs({ "SetVertexColor", "Show", "Hide", "SetShown" }) do
		hooksecurefunc(border, method, Tint)
	end
	Perf.HookScript(button, "OnEnter", Tint)     -- after the rim's own state change
	Perf.HookScript(button, "OnLeave", Tint)
	local onEnable = rep.onEnable
	rep.onEnable = function(r)
		if onEnable then
			onEnable(r)
		end
		Tint()
	end
	Tint()
	stats.items = stats.items + 1
	Note(button, "O2 round rim, tinted like the quality border")
end

--------------------------------------------------------------------------------
-- The money box (bottom left): the coin plate B2 on the gold edge's rect, as
-- the bags' money strip; the dark inset behind it faded (one box, not two;
-- the sweep would take it for a list's inset). A client with the inset only
-- gets the plate on the inset.
--------------------------------------------------------------------------------
local function SkinMoney(f)
	if done[f] then
		return
	end
	done[f] = true
	local inset, border = f.MoneyFrameInset, f.MoneyFrameBorder
	if inset and inset.melloRep == nil then
		inset.melloRep = false
		FadeArt(inset.Bg)
		if inset.NineSlice then
			for _, region in ipairs({ inset.NineSlice:GetRegions() }) do
				if IsTexture(region) then
					FadeArt(region)
				end
			end
		end
	end
	local left, mid, right
	if border then
		left, mid, right = ThreeSlice(border)
	end
	-- the plate at the edge's own level (its own pieces are faded), under the
	-- money frame, which is the edge's child
	if mid and Replace(mid, { as = COIN_KEY, rect = border, level = 0, alsoFade = List(left, right) }) then
		Note(border, "B2 coin plate")
	elseif inset and IsTexture(inset.Bg) and Replace(inset.Bg, { as = COIN_KEY, rect = inset, parent = inset, level = 0 }) then
		Note(inset, "B2 coin plate (on the inset)")
	else
		Miss(border or inset or f, "no money box art found")
	end
end

--------------------------------------------------------------------------------
-- The sell forms, should one of them not be a box on this client: their
-- labels and price boxes on the inner panel all the same (2e), a region of
-- the form under everything it holds (Kit:StoneDim), over the page stone.
--------------------------------------------------------------------------------
local SELL_FORMS = { "ItemSellFrame", "CommoditiesSellFrame", "WoWTokenSellFrame" }
local function SkinFormPanels(f)
	for _, key in ipairs(SELL_FORMS) do
		local form = f[key]
		if form and form.CreateTexture and not done[form] and skin.eyePanels[form] == nil and Kit.StoneDim then
			local tex = Kit:StoneDim(form, { rect = form, sublevel = 0 })
			skin.eyePanels[form] = tex or false
			if tex then
				tex.kitPiece = true
				tex:SetShown(active)
				Note(form, "inner panel (2e; the form has no box of its own here)")
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Finding the parts: one walk over the window, each part by what it is.
--------------------------------------------------------------------------------
local function Scan(f)
	Walk(f, function(child)
		local kind = child:GetObjectType()
		if IsTab(child) then
			SkinTab(child)
		elseif IsBox(child) then
			SkinBox(child)
			if child.HeaderContainer then
				SkinHeaders(child)
				HookHeaders(child)
			end
		elseif IsScrollBox(child) then
			local box = BoxOf(child)
			if box then
				HookList(child, (box == f.CategoriesList) and "category" or "list")
			end
		elseif kind == "EditBox" then
			SkinEdit(child)
		elseif kind == "Frame" and IsTexture(child.Middle) and child.Left and child.Right and child.Text
			and type(child.Button) == "table" and child.Button.GetRegions then
			SkinOldDropdown(child)
		elseif kind == "Button" and IsTexture(child.MiddleMiddle) and child.TopLeft then
			SkinFilter(child)
		elseif kind == "Button" and child.IconBorder and (child.Icon or child.icon) then
			SkinItemButton(child)
		elseif IsSquare(child) then
			SkinSquare(child)
		end
	end)
end

local function Build()
	local f = Window()
	if not f then
		return
	end
	skin = skin or { reps = {}, followers = {}, eyePanels = setmetatable({}, { __mode = "k" }) }
	if skin.built then
		return
	end
	skin.built = true
	SkinShell(f)
	SkinMoney(f)
	-- the tabs, boxes, headers and lists first: the sweep would read a tab or
	-- a column header as a red button
	Scan(f)
	SkinFormPanels(f)
	-- every common control left: the search box (S1), the red buttons (B1),
	-- the check box, the modern dropdowns (D1 / the filter plate), scroll bars
	Kit:SweepControls(f, Replace, skin)
end

-- On every show and display-mode change: what the game made or re-laid
-- since (pooled rows, headers, a page shown for the first time), the
-- followers' state, the portrait and the title once the window is laid out.
local function Refresh()
	local f = Window()
	if not (active and skin and f) then
		return
	end
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	GuardTabs()
	Scan(f)
	for box, kind in pairs(listKind) do
		WalkRows(box, kind)
	end
	Kit:SweepControls(f, Replace, skin)
	PlaceTitles(true)
	C_Timer.After(0, function()
		if active and f:IsShown() then
			if skin.ring and skin.portrait then
				pcall(Kit.FitPortrait, Kit, skin.portrait, skin.ring)
			end
			PlaceTitles(true)
		end
	end)
end

local function Activate()
	if active or not Window() then
		return
	end
	Build()
	if not skin then
		return
	end
	active = true
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for _, obj in ipairs(fadedArt) do
		Kit:Fade(obj)
	end
	for _, tex in pairs(skin.eyePanels) do
		if tex then
			tex:Show()
		end
	end
	Refresh()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	if skin then
		for _, rep in ipairs(skin.reps) do
			rep:Disable()
		end
		for _, tex in pairs(skin.eyePanels) do
			if tex then
				tex:Hide()
			end
		end
	end
	for _, obj in ipairs(fadedArt) do
		Kit:Unfade(obj)
	end
	GuardTabs()
	-- the other title strings back where the game put them, in its font
	-- (the ring's onDisable put the portrait back, the title plate's rule
	-- the container's title)
	PlaceTitles(false)
end

-- (user, 2026-09-24: "dress rarely used windows on first open") nothing of
-- the look is built while the window has never been shown this session: a
-- skin already built is switched on (and off), else only a window open right
-- now (a /reload with it open) is dressed at once; its first show dresses it
-- (the OnShow hook below), in that same frame, so it never draws undressed.
local function Sync()
	local f = Window()
	if M.isEnabled and f and ((skin and skin.built) or f:IsShown()) then
		Activate()
	else
		Deactivate()
	end
end

-- (the portrait and title strings are moved: out of combat only)
local function SyncSafe()
	Kit:WhenOutOfCombat(Sync)
end

-- The first show in combat dresses at once all the same: the dressing adds
-- frames and textures of ours and moves only the window's own portrait and
-- title strings, never a protected frame (the auction house has none). A
-- window the game protects waits for the fight's end, as before.
local function DressOnShow()
	local f = Window()
	local ok, protected = pcall(f.IsProtected, f)
	if InCombatLockdown() and ok and not Secret(protected) and not protected then
		Sync()
	else
		SyncSafe()
	end
end

local function Hook()
	local f = Window()
	if hooked or not f then
		return
	end
	hooked = true
	Perf.HookScript(f, "OnShow", function()
		if M.isEnabled and not active then
			DressOnShow()     -- (Activate refreshes what it dressed)
		else
			Refresh()
		end
	end)
	-- Buy / Sell / Auctions and the item pages are display modes of the one
	-- window: its pages come and go with them
	if type(f.SetDisplayMode) == "function" then
		hooksecurefunc(f, "SetDisplayMode", Refresh)
	end
end

-- Blizzard_AuctionHouseUI is loaded on demand (the first talk to an
-- auctioneer): hooked as it loads, dressed as it first shows.
local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(_, _, addon)
	if addon == ADDON then
		Hook()
		if M.isEnabled then
			SyncSafe()
		end
	end
end)
eventFrame:RegisterEvent("ADDON_LOADED")

function M:OnEnable(db)
	self.db = db
	if Window() then
		Hook()
		SyncSafe()
	end
end

function M:OnDisable()
	SyncSafe()
end

--------------------------------------------------------------------------------
-- /auctiondump [frames | reps | regions]: with no mode, what the skin found
-- and dressed on each tab (the window, Buy, Sell, Auctions), what the sweep
-- dressed, and what was seen but left as the game's; the shell's checks
-- (portrait size, title on the plate and in the title face); the sell forms'
-- own regions (to fit a part this client builds otherwise, the Create
-- Auction header). The modes are Kit:DumpWindow's. Opens the copy window.
--------------------------------------------------------------------------------

-- the key a frame is kept under in its parent (for a readable path)
local function KeyIn(parent, child)
	local ok, key = pcall(function()
		for k, v in pairs(parent) do
			if v == child and type(k) == "string" then
				return k
			end
		end
	end)
	return ok and key or nil
end

-- the path from the window to `obj` (keys, else names), and its first step
local function Path(obj)
	local f = Window()
	local parts, cur = {}, obj
	for _ = 1, 14 do
		if not cur or cur == f then
			break
		end
		local parent = cur.GetParent and cur:GetParent()
		if not parent then
			break
		end
		table.insert(parts, 1, KeyIn(parent, cur) or NameOf(cur))
		cur = parent
	end
	return table.concat(parts, "."), parts[1] or ""
end

local GROUPS = { "Window", "Buy", "Sell", "Auctions" }
local function GroupOf(first)
	if first:find("Tab$") or first:find("^Money") then
		return "Window"
	elseif first:find("Sell") then
		return "Sell"
	elseif first:find("Auctions") or first:find("Bid") then
		return "Auctions"
	elseif first:find("Buy") or first:find("Browse") or first:find("Categor") or first:find("Search") or first:find("Token") then
		return "Buy"
	end
	return "Window"
end

-- what a control the sweep dressed is
local function SweptKind(obj)
	local kind = obj:GetObjectType()
	if obj.Track and obj.Track.Thumb then
		return "scroll bar (T2 / H1 / S1)"
	elseif kind == "EditBox" and obj.searchIcon then
		return "search box (S1)"
	elseif kind == "CheckButton" then
		return "kit check box"
	elseif obj.Left and obj.LeftActive then
		return "TB6 tab card"
	elseif obj.Background and obj.Text then
		return "dropdown plate (D1 / filter)"
	elseif kind == "Button" then
		return "red plate (B1)"
	elseif obj.NineSlice then
		return "inset (single rail, inner panel)"
	end
	return kind
end

local function DumpOwn(frame, label)
	MelloUI:Print("%s's own regions:", label)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "")
		elseif kind == "FontString" then
			art = "text: " .. tostring(TextOf(region) or ""):sub(1, 40)
		end
		local okA, alpha = pcall(region.GetAlpha, region)
		MelloUI:Print("  %s %s %s %s alpha %s shown %s", kind, KeyIn(frame, region) or NameOf(region), okL and tostring(layer) or "?", art,
			(okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?", tostring(region:IsShown()))
	end
end

local function Summary(f)
	local mode = f.displayMode
	MelloUI:Print("AuctionHouseFrame: shown %s, kit %s, reps %d, followers %d, display mode %s", tostring(f:IsShown()), active and "on" or "off",
		skin and #skin.reps or 0, skin and #skin.followers or 0, type(mode) == "table" and "(a table)" or tostring(mode))
	MelloUI:Print("  boxes %d, rows %d, headers %d, edit plates %d, small buttons %d, item slots %d, tabs %d",
		stats.boxes, stats.rows, stats.headers, stats.edits, stats.squares, stats.items, stats.tabs)
	-- the shell's checks (2b / 2c)
	local portrait = Portrait(f)
	local ring = skin and skin.ring
	if portrait then
		local okT, file = pcall(portrait.GetTexture, portrait)
		local okS, w = pcall(portrait.GetWidth, portrait)
		local rw = ring and ring.tex and ring.tex:GetWidth() or 0
		MelloUI:Print("  portrait: art %s, width %s, medallion size %.1f (ring %.1f), fallback mark %s",
			(okT and not Secret(file)) and tostring(file) or "?", (okS and not Secret(w)) and string.format("%.1f", w) or "?",
			rw * 0.759, rw, skin and skin.mark and (skin.mark:IsShown() and "under the portrait" or "hidden") or "none")
	else
		MelloUI:Print("  portrait: -- not found")
	end
	local own = f.TitleContainer and f.TitleContainer.TitleText
	local rep = skin and TitleRep()
	if own then
		local okF, face = pcall(own.GetFont, own)
		local okP, _, rel = pcall(own.GetPoint, own, 1)
		MelloUI:Print("  title: \"%s\", face %s, on the plate %s", tostring(TextOf(own)), okF and tostring(face) or "?",
			tostring(okP and rep ~= nil and rel == rep.strip))
	else
		MelloUI:Print("  title: -- no TitleContainer.TitleText")
	end
	for fs in pairs(titleMoved) do
		MelloUI:Print("  other title string moved onto the plate: %s", tostring(TextOf(fs)))
	end
	-- everything dressed, by tab: ours, the lists, then the sweep's
	local lines = { Window = {}, Buy = {}, Sell = {}, Auctions = {} }
	local seen = {}
	local function Add(obj, text)
		local path, first = Path(obj)
		local list = lines[GroupOf(first)]
		list[#list + 1] = string.format("    %-58s %s", path, text)
	end
	for _, part in ipairs(found.parts) do
		seen[part.obj] = true
		Add(part.obj, part.piece)
	end
	for box, kind in pairs(listKind) do
		Add(box, string.format("%s list, rows dressed %d", kind, listRows[box] or 0))
	end
	Walk(f, function(child)
		if child.melloRep and not seen[child] then
			Add(child, SweptKind(child) .. " (sweep)")
		end
	end)
	for _, group in ipairs(GROUPS) do
		MelloUI:Print("  %s:", group == "Window" and "Window and bottom tabs" or (group .. " tab"))
		table.sort(lines[group])
		for _, line in ipairs(lines[group]) do
			MelloUI:Print("%s", line)
		end
		if #lines[group] == 0 then
			MelloUI:Print("    (nothing -- open this tab once, then dump again)")
		end
	end
	MelloUI:Print("  seen, left as the game's:")
	for _, obj in ipairs(found.missing) do
		MelloUI:Print("    %-58s %s", (Path(obj)), tostring(found.missed[obj]))
	end
	if #found.missing == 0 then
		MelloUI:Print("    (none)")
	end
	MelloUI:Print("  the window's pages:")
	for _, child in ipairs({ f:GetChildren() }) do
		if not child.melloSkin then
			MelloUI:Print("    %-40s %s shown %s%s", KeyIn(f, child) or NameOf(child), child:GetObjectType(), tostring(child:IsShown()),
				done[child] and " (dressed)" or "")
		end
	end
	for _, key in ipairs(SELL_FORMS) do
		if f[key] then
			DumpOwn(f[key], key)
		end
	end
end

SLASH_MELLOAUCTIONDUMP1 = "/auctiondump"
SlashCmdList.MELLOAUCTIONDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if not f then
		MelloUI:Print("/auctiondump: the auction house is not loaded yet (it loads when you first talk to an auctioneer)")
	elseif not skin then
		MelloUI:Print("/auctiondump: the auction house is not dressed yet (%s)", M.isEnabled
			and "the kit dresses it the first time it opens: open it, then try again" or "the Auction House Kit is off")
	elseif msg == "" then
		Summary(f)
	else
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	end
	MelloUI:ShowLog("auctiondump " .. msg)
end
