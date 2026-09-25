--------------------------------------------------------------------------------
-- MelloUI - Bank Kit
--
-- (user, 2026-09-24: "Bank and GUild Bank Aswell"): The bank window (the bank's slots, bag slots, purchase) in the kit, in the bags' looks.
--
-- The bank window (BankFrame: this client's Camelot skin of it,
-- Blizzard_UIPanels_Game/Camelot/BankFrame.xml over the shared
-- Mainline/BankFrameTemplates.xml: a PortraitFrameTemplate window with the
-- BankPanel inside, its item grid, the bag slots row, the purchase row and
-- the money bar; the pages as side tabs on the window's right) dressed in the
-- painted kit (Modules/Kit.lua) on the game's own layout, as every other
-- window is (docs/WINDOW-RULES.md). The bank wears the BAGS' looks: the item
-- rims, the empty slots' Item Background and the Window Background are the
-- Backpack Kit's choices (read from its settings, followed live), so the
-- bank and the bags always read as one set.
--
--   the window shell     outer double rail with gem corners, ONE page picture
--                        fitted to the window's rect inside the rail (2a), the
--                        ring with the banker's portrait at the class
--                        medallion's size on the dark disc (2b), the title
--                        plate on the rail with "Bank" ON it in the title
--                        face (2c), the close button (Kit:SkinWindowShell)
--   window background    the bags' Window Background on that one picture,
--                        repeated at the UI's one density, laid from the
--                        window's top so a taller page does not move it; the
--                        game's dark bank stone (bank-frame-background) faded
--                        (one stone per surface), the content inset's rails
--                        (they ran along the outer rail: two rails on one
--                        edge) and its edge shadows faded
--   item slots           the bank's slots and the bag slots (the purchasable,
--                        locked ones too) in every window's Button Border rim
--                        (Kit:SkinActionButton, as the bags), the quality
--                        border kept on the icon, an empty slot on the bags'
--                        Item Background; the game's slot frame and slot
--                        picture faded; the padlock on a locked bag slot stays
--   the lower band       "Bag Slots" / "Cost" / Purchase lie on the palette's
--                        inner panel inside a single rail (2e), open at the
--                        top where the game's divider (bank-divider) becomes
--                        the kit's divider strip; the labels in the palette
--                        (the heading in its gold, the label in its text)
--   search / sort        the edit plate (S1) / the cog plate under the game's
--                        round button (K2), as the bags'
--   purchase, withdraw,
--   deposit              the red plate (B1), the game's disabled look kept
--   the money bar        the coin plate (B2, the bags' money strip)
--   the page tabs        the side tabs (common-sidetab: the gold rim, the
--                        selected one lit, the hovered one half lit, the icon
--                        fitted into the opening), every page of every bank
--                        type the client shows, in the Side Tab Border; a
--                        client in bank-tab mode gets its tabs and the
--                        purchase tab dressed the same; a TabSystem's tabs
--                        (none on this client) TB6
--   the prompts          the lock / purchase prompts' inner border -> the
--                        single rail (their black panel stays: text on dark)
--   the rest             Kit:SweepControls (check boxes, dropdowns, red
--                        buttons, scroll bars)
--
-- Taint: nothing of the game's is replaced or re-scripted, no bank function
-- is ever called. The skin is made and kept from post-hooks (the window's
-- OnShow, RefreshBagButtons / RefreshPageTabs / GenerateItemSlotsForSelectedTab
-- on the instances); what the module keeps about the game's frames lives in
-- weak side tables. The item buttons get only textures of our own over them
-- and faded art; the window is never moved (the window mover in UI
-- Modifications keeps it). Switching the module off disables every
-- replacement, un-fades the game's art, hides the band, puts the portrait,
-- the title and the labels' colours back: the window is the game's again.
--
-- /bankdump [slots | tabs | reps | regions | frames]: what the window is
-- made of on this client and what the skin dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("BankPanel")
local hooksecurefunc = Perf.hooksecurefunc
-- a handler made once and run for many asks, wrapped once: its time stays
-- on this file's own /melloperf row (review, 2026-09-24)
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("BankPanel", {
	title = "Bank Kit",
	desc = "The bank window (the bank's slots, bag slots, purchase) in the kit, in the bags' looks.",
	window = { label = "Bank", desc = "The bank window (the bank's slots, bag slots, purchase) in the kit, in the bags' looks.", tab = "Windows",
		frames = { "BankFrame" }, plainGrab = true, firstOpen = true },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local DIM = 0.8                  -- WINDOW-RULES 2e: the inner panel's alpha over the stone
local MEDALLION_TO_RING = 0.759  -- WINDOW-RULES 2b: the portrait's size in the ring (for the dump)
-- template facts (Camelot/BankFrame.xml, Mainline/BankFrameTemplates.xml),
-- used only where the game's own region cannot be found to anchor to:
local DIVIDER_Y = 220 * 0.48     -- the divider's BOTTOM offset, given in its own 0.48 scale
local CONTENT_BOTTOM = 30        -- BankPanel.NineSlice's bottom edge above the window's bottom

local skin = nil          -- { reps = { every replacement }, followers = { { rep, region } }, ... }
local active = false
local hooked = false

-- what this module made or looked at, kept OFF the game's frames (weak keys)
local done = setmetatable({}, { __mode = "k" })         -- [frame / region] = true: looked at once
local slotKind = setmetatable({}, { __mode = "k" })     -- [item button] = "item" | "bag": wears the bags' Item Background
local labelSaved = setmetatable({}, { __mode = "k" })   -- [font string] = { r, g, b, a }: the game's colour
local held = setmetatable({}, { __mode = "k" })         -- [region] = { points, target }: laid on another rect while on
local fadedArt = {}                                     -- game art faded with no piece on its own rect
local tabReps = {}                                      -- a TabSystem's cards { rep, region } (kept hidden while the kit is off)
local seenPictures = {}                                 -- [bank type .. ":" .. page] = the page picture's rect seen there (2a)
local stats = { items = 0, bags = 0, pageTabs = 0, bankTabs = 0, panelTabs = 0, prompts = 0 }

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Bank kit: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

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

-- a region's IsShown, secret-safe (nil: unknown)
local function IsShownSafe(obj)
	if not (obj and obj.IsShown) then
		return nil
	end
	local ok, s = pcall(obj.IsShown, obj)
	if ok and not Secret(s) then
		return s and true or false
	end
	return nil
end

local function Window()
	return _G.BankFrame
end

-- the BankPanel inside the window (the grid, the money, the prompts)
local function Panel(f)
	return (f and f.BankPanel) or _G.BankPanel
end

-- The bags' looks (Backpack Kit's settings, read whether or not that module
-- is on): the empty slots' Item Background and the Window Background.
local function BagLook(key, default)
	local db = MelloUI.GetModuleDB and MelloUI:GetModuleDB("BackpackPanel")
	local v = db and db[key]
	if v == nil or v == "page" then   -- (the bags' old first choice is the concrete now)
		return default
	end
	return v
end

-- Art faded while the kit is on with no piece of its own on its rect (the
-- window's picture, the band or the rim stands in for it elsewhere)
local function FadeArt(obj)
	if not obj or done[obj] then
		return
	end
	done[obj] = true
	fadedArt[#fadedArt + 1] = obj
	if active then
		Kit:Fade(obj)
	end
end

-- every game texture of a frame (not ours)
local function TexturesOf(frame)
	local list = {}
	if not (frame and frame.GetRegions) then
		return list
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			list[#list + 1] = region
		end
	end
	return list
end

-- A game region laid on another rect while the kit is on (a tab's dark fill
-- and search shade onto its icon, which the rim moved), its own points kept
-- and put back on disable.
local function Hold(region, target)
	if not (region and target) or held[region] then
		return
	end
	local points = {}
	for i = 1, region:GetNumPoints() do
		points[i] = { region:GetPoint(i) }
	end
	held[region] = { points = points, target = target }
	if active then
		region:ClearAllPoints()
		region:SetAllPoints(target)
	end
end

local function Unhold(region, entry)
	region:ClearAllPoints()
	for _, pt in ipairs(entry.points) do
		region:SetPoint(unpack(pt))
	end
end

--------------------------------------------------------------------------------
-- The page picture (WINDOW-RULES 2a) and the bags' Window Background. The
-- shell lays ONE picture on the window's rect inside the outer rail (the
-- game's rock, Bg): every bank page and bank type shows that same picture.
-- It takes the bags' Window Background (Kit's picture SetPiece: one surface,
-- the chosen tile repeated at the UI's one density). It is laid from the
-- window's TOP: a page with more rows makes the window taller at the bottom
-- (GenerateItemSlotsForSelectedTab), and a picture centred on the window
-- would shift under the grid when switching to such a page.
--------------------------------------------------------------------------------
local function ApplyWindowBackground()
	local rep = skin and skin.bgRep
	if rep and rep.SetPiece then
		rep:SetPiece(BagLook("windowBackground", "concrete"))
	end
end

local function WatchBackground(f)
	for _, r in ipairs(skin.reps) do
		if r.region == f.Bg and r.key == "UI-Background-Rock" and r.tex and r.inner then
			skin.bgRep = r
		end
	end
	local rep = skin.bgRep
	if not rep then
		return
	end
	local refit = rep.Refit
	rep.Refit = function(self)
		refit(self)
		if self.tex.kitBackground then
			self.tex.kitAlign = "top"
			Kit:Retile(self.tex)
		end
	end
	local enable = rep.onEnable
	rep.onEnable = function(...)
		if enable then
			enable(...)
		end
		ApplyWindowBackground()
	end
	if active then
		ApplyWindowBackground()
	end
end

--------------------------------------------------------------------------------
-- The window's own content art. The game paints its dark bank stone
-- (Background, bank-frame-background) over the rock, a content inset
-- (BankPanel.NineSlice, InsetFrameTemplate) whose rails run along the
-- window's own border on three sides, and soft edge shadows inside it. The
-- page picture is the bank's one surface (the bags' Window Background, as
-- the bags lie on it); the outer rail is the edge: the three are faded.
--------------------------------------------------------------------------------
local function SkinContent(f)
	FadeArt(f.Background)
	local P = Panel(f)
	if P and P.NineSlice then
		for _, tex in ipairs(TexturesOf(P.NineSlice)) do
			FadeArt(tex)
		end
	end
	if P and P.EdgeShadows then
		for _, tex in ipairs(TexturesOf(P.EdgeShadows)) do
			FadeArt(tex)
		end
	end
end

-- the unnamed divider texture (bank-divider) among the window's regions
-- (the client may hand the atlas back in another case)
local function FindDivider(f)
	for _, tex in ipairs(TexturesOf(f)) do
		local key = Kit:ArtKey(tex)
		if type(key) == "string" and key:lower() == "bank-divider" then
			return tex
		end
	end
end

-- the divider strip's own thickness (its painted box), as the other windows' lines
local function DividerThickness()
	local p = Kit:Piece("window/divider_mid")
	if p and p.box then
		return (p.box[4] - p.box[2]) * Kit.scale
	end
	return p and p.h * Kit.scale or 8
end

--------------------------------------------------------------------------------
-- The lower band (WINDOW-RULES 2e: "too much small text over a plain brown
-- border is just an eye strain"). Under the grid the game draws a divider,
-- then "Bag Slots:" with the bag slots and "Cost:" with the price and the
-- Purchase button, all straight on the stone. They get the palette's inner
-- panel over the list-box stone inside the single rail (L1), across the
-- window inside the outer rail (one rail's width in from its bevel), from the
-- divider's line down to where the game's content inset ended (the money bar
-- below it keeps its coin plate). The box is open at the top: the divider
-- becomes the kit's divider strip ON that edge, from rail to rail, closing
-- it. All of it is REGIONS of the window itself (the labels are the window's
-- ARTWORK strings, the page picture its BACKGROUND -6 region): the stone at
-- BACKGROUND 1, the panel at 2, the rails at BORDER, the divider over them;
-- the bag slots and the purchase row are frames above.
--------------------------------------------------------------------------------
local function SkinBand(f)
	if skin.band then
		return
	end
	local P = Panel(f)
	local divider = FindDivider(f)
	FadeArt(divider)
	local prefix = Kit.framePrefix
	local fscale = Kit.scale * Kit.frameScale
	local rail = select(1, Kit:Size(prefix .. "_tl", fscale))
	local outer = Kit:OuterRailInset()
	-- a WoW point carries both coordinates: a helper spans from the window's
	-- top-left corner to the divider's centre, the band hangs on its bottom
	local topRef = CreateFrame("Frame", nil, f)
	topRef:EnableMouse(false)
	topRef:SetPoint("TOPLEFT", f, "TOPLEFT")
	if divider then
		topRef:SetPoint("BOTTOMRIGHT", divider, "CENTER")
	else
		topRef:SetPoint("BOTTOMRIGHT", f, "BOTTOM", 0, DIVIDER_Y)
	end
	local rect = CreateFrame("Frame", nil, f)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", topRef, "BOTTOMLEFT", (outer[1] or 0) + rail, 0)
	if P and P.NineSlice then
		rect:SetPoint("BOTTOMRIGHT", P.NineSlice, "BOTTOMRIGHT", -((outer[2] or 0) + rail), 0)
	else
		rect:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -((outer[2] or 0) + rail), CONTENT_BOTTOM)
	end
	local nine = Kit:NineSlice(rect, { scale = fscale, gems = false, body = true, prefix = prefix, owner = f,
		bodyLayer = "BACKGROUND", bodySub = 1, edgeLayer = "BORDER", edgeSub = 0, open = "t" })
	-- the inner panel over the stone, inside the side and bottom rails, up to the open top
	local inset = (nine.thickness or 0) * 0.6
	local fill = f:CreateTexture(nil, "BACKGROUND", nil, 2)
	fill.kitPiece = true   -- ours: never faded as the game's art
	fill:SetPoint("TOPLEFT", nine, "TOPLEFT", inset, 0)
	fill:SetPoint("BOTTOMRIGHT", nine, "BOTTOMRIGHT", -inset, inset)
	local c = MelloUI.Palette.innerPanel
	fill:SetColorTexture(c[1], c[2], c[3], DIM)
	nine.dimFill = fill
	table.insert(nine.all, fill)
	-- the divider on the band's open top, its ends on the side rails' centre lines
	local strip = Kit:Strip(rect, "window/divider", { scale = Kit.scale, owner = f, layer = "BORDER", sublevel = 3 })
	local yoff = strip:FitBox(DividerThickness())
	local railIn = Kit:RailInset(prefix .. "_l", "l")
	strip:ClearAllPoints()
	strip:SetPoint("LEFT", rect, "TOPLEFT", railIn, yoff)
	strip:SetPoint("RIGHT", rect, "TOPRIGHT", -railIn, yoff)
	strip:SetHeight(strip.height)
	local function FitCaps()
		local ok, w = pcall(strip.GetWidth, strip)
		if ok and w and not Secret(w) and w > 0 then
			strip:FitCaps(w)
		end
	end
	Perf.HookScript(strip, "OnSizeChanged", FitCaps)
	Perf.HookScript(strip, "OnShow", FitCaps)
	FitCaps()
	skin.band = { rect = rect, nine = nine, fill = fill, strip = strip, divider = divider }
	nine:SetShown(active)
	strip:SetShown(active)
end

local function ShowBand(on)
	local band = skin and skin.band
	if band then
		band.nine:SetShown(on and true or false)
		band.strip:SetShown(on and true or false)
	end
end

-- The band's labels in the palette (2e): "Bag Slots:" a heading (its gold),
-- "Cost:" a label (its text colour), both already at a full size; the game's
-- colours put back on disable.
local function InkLabels(on)
	local f = Window()
	if not f then
		return
	end
	local P = MelloUI.Palette
	for _, entry in ipairs({ { f.BagText, "selectedTrim" }, { f.BagCost, "text" } }) do
		local fs, role = entry[1], entry[2]
		if fs and fs.SetTextColor then
			if on then
				if not labelSaved[fs] then
					local ok, r, g, b, a = pcall(fs.GetTextColor, fs)
					if ok and type(r) == "number" and not (Secret(r) or Secret(g) or Secret(b) or Secret(a)) then
						labelSaved[fs] = { r, g, b, a or 1 }
					end
				end
				local col = P and P[role]
				if col and labelSaved[fs] then
					fs:SetTextColor(col[1], col[2], col[3], 1)
				end
			elseif labelSaved[fs] then
				local s = labelSaved[fs]
				fs:SetTextColor(s[1], s[2], s[3], s[4])
				labelSaved[fs] = nil
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The item slots: the bank's (BankPanel.itemButtonPool, CamelotBankItemButton:
-- its slot frame bank-frame-item-slotframe as NormalTexture, re-atlased on
-- every Refresh, its slot picture Background under the icon) and the bag
-- slots (BankFrame.itemButtonBagPool, BankItemButtonBag at 0.75 scale: the
-- same two, the padlock DisabledOverlay over an unbought one). Every one in
-- the bags' dress: every window's Button Border rim on the button's rect, the
-- icon in its opening, the quality border kept on the icon, the empty slot
-- on the bags' Item Background (Kit:SkinActionButton, emptyStone: the game
-- hides the icon of an empty slot); the game's slot picture faded. The
-- padlock (ARTWORK 1) is not touched: it lies over the Item Background.
--------------------------------------------------------------------------------
local function SkinSlot(button, kind)
	if not button or done[button] then
		return
	end
	done[button] = true
	local rep = Kit:SkinActionButton(button, Replace, nil, { as = Kit:ButtonRimRule(), emptyStone = true, qualityBorder = button.IconBorder })
	if rep then
		slotKind[button] = kind
		Kit:SetButtonBackground(button, BagLook("itemBackground", "stone"))
		local key = kind == "bag" and "bags" or "items"
		stats[key] = stats[key] + 1
	end
	FadeArt(button.Background)
end

--------------------------------------------------------------------------------
-- The side tabs. This client (bags in the bank) shows its pages as
-- LargeSideTabButtonTemplate frames on the window's right (BankPageTab, one
-- per page of each bank type the player may view: the character's bank, the
-- account's), pooled and laid again on every page change (RefreshPageTabs):
-- the kit's side tab (Kit:SkinSideTab: the gold rim, the same rim lit while
-- the game shows the tab selected, half lit on hover, the icon fitted into
-- the opening and fitted again after the game's press / release / interior
-- re-anchoring; every window's Side Tab Border, at the Character window's
-- size). A client in bank-tab mode shows BankPanelTabTemplate buttons and a
-- purchase tab instead (the spell book's 32 px tab art, keyed by hand as the
-- guild window's side tabs are): the same rim, the glow following the game's
-- SelectedTexture; the purchase tab's dark fill and a tab's search shade laid
-- on the icon the rim moved.
--------------------------------------------------------------------------------
local function SkinPageTab(tab)
	if not tab or done[tab] then
		return
	end
	done[tab] = true
	if Kit:SkinSideTab(tab, Replace) then
		stats.pageTabs = stats.pageTabs + 1
	end
end

local function SkinBankTab(tab)
	if not tab or done[tab] then
		return
	end
	done[tab] = true
	local plate = tab.Border
	local sel = tab.SelectedTexture
	if not (plate and tab.Icon) or tab.melloRep ~= nil then
		return
	end
	local rep = Replace(plate, { as = "common-sidetab", button = tab, parent = tab, rect = tab, icon = tab.Icon,
		checked = function() return sel ~= nil and sel:IsShown() end,
		alsoFade = List(sel, tab.GetHighlightTexture and tab:GetHighlightTexture()) })
	tab.melloRep = rep or false
	if not rep then
		return
	end
	-- the glow follows the game's selection (a Button: no SetChecked to hear)
	if sel then
		local function Update()
			local rim = rep.object
			if rim and rim:IsShown() and rim.Update then
				rim:Update()
			end
		end
		for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
			hooksecurefunc(sel, method, Update)
		end
	end
	Hold(tab.Background, tab.Icon)
	Hold(tab.SearchOverlay, tab.Icon)
	stats.bankTabs = stats.bankTabs + 1
end

--------------------------------------------------------------------------------
-- A TabSystem's tabs (the bank / account tabs of a client that has one: not
-- this one's Camelot window): TB6 cards by Kit:SkinPanelTab, which follow
-- their tab's textures on every Show / Hide, also while the kit is off; after
-- those hooks this one sets every card from its texture while the kit is on
-- and hides them all while it is off (the merchant's guard).
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

local function SkinPanelTab(tab)
	if not tab or done[tab] or not (tab.Left and tab.LeftActive) then
		return
	end
	done[tab] = true
	local first = #skin.followers + 1
	Kit:SkinPanelTab(tab, Replace, skin)
	for i = first, #skin.followers do
		tabReps[#tabReps + 1] = skin.followers[i]
	end
	for _, tex in ipairs({ tab.Left, tab.LeftActive }) do
		hooksecurefunc(tex, "Show", GuardTabs)
		hooksecurefunc(tex, "Hide", GuardTabs)
		hooksecurefunc(tex, "SetShown", GuardTabs)
	end
	stats.panelTabs = stats.panelTabs + 1
end

local function PanelTabs(f)
	local ts = f and f.TabSystem
	if not ts then
		return {}
	end
	return ts.tabs or { ts:GetChildren() }
end

-- Every pooled part the game has out now: the slots, the bag slots, the tabs
local function SkinPools(f)
	local P = Panel(f)
	if P and P.itemButtonPool then
		for button in P.itemButtonPool:EnumerateActive() do
			SkinSlot(button, "item")
		end
	end
	if f.itemButtonBagPool then
		for button in f.itemButtonBagPool:EnumerateActive() do
			SkinSlot(button, "bag")
		end
	end
	if f.bankPageTabPool then
		for tab in f.bankPageTabPool:EnumerateActive() do
			SkinPageTab(tab)
		end
	end
	if P and P.bankTabPool then
		for tab in P.bankTabPool:EnumerateActive() do
			SkinBankTab(tab)
		end
	end
	if P and P.PurchaseTab then
		SkinBankTab(P.PurchaseTab)
	end
	for _, tab in ipairs(PanelTabs(f)) do
		SkinPanelTab(tab)
	end
end

--------------------------------------------------------------------------------
-- The controls: the search box (S1) and the sort button (K2: the cog plate
-- under the game's round button, which is its own plate: not faded), as the
-- bags'; the red plates (B1) on Purchase and, where the bank type moves
-- money, Withdraw / Deposit; the money bar's gold-edged strip (Left / Middle /
-- Right, named only through an unnamed parent here: taken as the strip's
-- textures) on the coin plate (B2), the money on it.
--------------------------------------------------------------------------------
local function SkinControls(f)
	local P = Panel(f)
	local search = f.BankItemSearchBox or _G.BankItemSearchBox
	if search then
		Kit:SkinSearchBox(search, Replace)
	end
	local sort = P and P.AutoSortButton
	local normal = sort and sort.GetNormalTexture and sort:GetNormalTexture()
	if normal and not done[sort] then
		done[sort] = true
		Replace(normal, { as = "bags-button-autosort-up", button = sort, noFade = true })
	end
	local money = P and P.MoneyFrame
	for _, b in ipairs(List(P and P.PurchaseButton, _G.BankFramePurchaseButton,
		money and money.WithdrawButton, money and money.DepositButton)) do
		Kit:SkinRedButton(b, Replace)
	end
	local border = money and money.Border
	if border and not done[border] then
		done[border] = true
		local pieces = TexturesOf(border)
		local first = table.remove(pieces, 1)
		if first then
			skin.coinPlate = Replace(first, { as = "common-coinbox-center", rect = border, alsoFade = pieces })
		end
	end
end

-- The lock / purchase prompts (BankPanelPromptBackgroundTemplate: the guild
-- bank's file corners and tiles round a black panel): the eight border pieces
-- -> the single rail (the inset rule, edges only) on the prompt's rect, a
-- level above it (only its edges: the text is centred); the black panel stays.
local PROMPT_PIECES = { "TopLeftInner", "TopRightInner", "BottomLeftInner", "BottomRightInner", "LeftInner", "RightInner", "TopInner", "BottomInner" }

local function SkinPrompt(prompt)
	if not prompt or done[prompt] then
		return
	end
	done[prompt] = true
	local pieces = {}
	for _, key in ipairs(PROMPT_PIECES) do
		if prompt[key] then
			pieces[#pieces + 1] = prompt[key]
		end
	end
	local first = table.remove(pieces, 1)
	if first and Replace(first, { as = "common-insideframe", parent = prompt, rect = prompt, body = false, level = 1, alsoFade = pieces }) then
		stats.prompts = stats.prompts + 1
	end
end

--------------------------------------------------------------------------------
-- The portrait (WINDOW-RULES 2b / 2c: an empty ring is a bug). The game draws
-- the banker into the PortraitContainer's portrait on every open
-- (SetPortraitToUnit("npc")): the kit's ring on the corner, the portrait
-- brought to the class medallion's size in it (Kit:FitPortrait) on the dark
-- disc (Kit:RingDisc; a round unit portrait covers it). Fitted again on every
-- show (the window is laid out only while shown); put back on disable.
--------------------------------------------------------------------------------
local function Portrait(f)
	local pc = f and f.PortraitContainer
	return (pc and pc.portrait) or _G.BankFramePortrait
end

local function FitPortrait()
	local portrait = Portrait(Window())
	if active and skin and skin.ring and portrait then
		pcall(Kit.FitPortrait, Kit, portrait, skin.ring)
	end
end

local function SkinPortrait(f, ring)
	local portrait = Portrait(f)
	if not (ring and portrait) then
		return
	end
	skin.ring = ring
	ring.onEnable = function()
		pcall(Kit.FitPortrait, Kit, portrait, ring)
	end
	ring.onDisable = function()
		pcall(Kit.UnfitPortrait, Kit, portrait)
	end
	-- (chains onto the fit above; a region of the portrait's own container,
	-- BACKGROUND under its OVERLAY portrait)
	Kit:RingDisc(ring, nil, f.PortraitContainer or ring.object:GetParent(), 0)
end

--------------------------------------------------------------------------------
-- The title (WINDOW-RULES 2c: the title ON the plate, in the title face). The
-- shell's title plate centres the title container's TitleText ("Bank", or the
-- account bank's title: SetTitle on every bank type change) on it in
-- Kit:TitleFont and puts it back on disable; fitted again on every show, the
-- face put on again should anything have reset the string's font.
--------------------------------------------------------------------------------
local function TitleText(f)
	local tc = f and f.TitleContainer
	return tc and tc.TitleText
end

local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
	end
end

local function PlaceTitle()
	local rep = TitleRep()
	if not (active and rep and rep.object and rep.object:IsShown()) then
		return
	end
	if rep.Refit then
		rep:Refit()
	end
	local text = TitleText(Window())
	if text and not text.melloFontSaved then
		Kit:TitleFont(text, true)
	end
end

--------------------------------------------------------------------------------
-- 2a, for the dump: the page picture's rect on each page / bank type the
-- window has shown since the reload (it must be the same on every one).
--------------------------------------------------------------------------------
local function PictureRect()
	local rep = skin and skin.bgRep
	local inner = rep and rep.inner
	if not inner then
		return nil
	end
	local ok, l, b, w, h = pcall(inner.GetRect, inner)
	if not ok or not l or Secret(l) or Secret(b) or Secret(w) or Secret(h) then
		return nil
	end
	return string.format("left %.0f top %.0f w %.0f h %.0f, align %s, piece %s", l, b + h, w, h,
		tostring(rep.tex and rep.tex.kitAlign), tostring(rep.tex and rep.tex.kitName))
end

local function CurrentPage()
	local P = Panel(Window())
	if not P then
		return "?"
	end
	return tostring(P.bankType) .. ":" .. tostring(P.currentPage)
end

local function RecordPicture()
	local r = PictureRect()
	if r then
		seenPictures[CurrentPage()] = r
	end
end

--------------------------------------------------------------------------------
-- Building, switching on and off
--------------------------------------------------------------------------------
local function Build()
	local f = Window()
	if not f then
		return
	end
	skin = skin or { reps = {}, followers = {} }
	if skin.built then
		return
	end
	skin.built = true

	-- the shell: outer rail, the one page picture, the ring, the title plate
	-- on the rail with the title on it, the close button
	local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = Portrait(f), bg = "UI-Background-Rock" })
	SkinPortrait(f, ring)
	WatchBackground(f)

	-- the content's own art, then the lower band on the page
	SkinContent(f)
	SkinBand(f)

	-- the controls, the prompts, the pooled slots and tabs, the rest
	SkinControls(f)
	local P = Panel(f)
	SkinPrompt(P and P.LockPrompt)
	SkinPrompt(P and P.PurchasePrompt)
	SkinPools(f)
	-- (the tab settings popup of bank-tab mode is an icon picker window of
	-- its own that this client never opens: not walked into)
	Kit:SweepControls(f, Replace, skin, P and P.TabSettingsMenu)
end

-- Refresh's pass a frame later, once the window is laid out (made once:
-- Kit:NextFrame runs it once however often it was asked -- audit, 2026-09-24;
-- timed on this window's own /melloperf row, not the Kit's timer -- review)
local RefreshLater = Shared("Refresh a frame later", function()
	local f = Window()
	if active and f and f:IsShown() then
		FitPortrait()
		PlaceTitle()
		RecordPicture()
	end
end, "timer")

-- After every show and every game refresh (a page or bank type switch, the
-- bag slots laid again): what the game made or re-laid since (new pooled
-- slots and tabs, the portrait's size, the title's plate, the followers).
local function Refresh()
	local f = Window()
	if not (active and skin and f) then
		return
	end
	SkinPools(f)
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	GuardTabs()
	FitPortrait()
	PlaceTitle()
	-- once laid out (a frame after it shows): the portrait and the title
	-- again, and the page picture's rect noted for this page (2a); one pass
	-- pending at a time (the game refreshes on every bag change)
	Kit:NextFrame(skin, RefreshLater)
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
	for region, entry in pairs(held) do
		region:ClearAllPoints()
		region:SetAllPoints(entry.target)
	end
	ShowBand(true)
	InkLabels(true)
	ApplyWindowBackground()
	for button in pairs(slotKind) do
		Kit:SetButtonBackground(button, BagLook("itemBackground", "stone"))
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
	end
	for _, obj in ipairs(fadedArt) do
		Kit:Unfade(obj)
	end
	for region, entry in pairs(held) do
		Unhold(region, entry)
	end
	-- the band hidden, the labels' colours back, the TabSystem's cards hidden
	-- for good while off (the ring's onDisable put the portrait back, the
	-- title plate's the title's points and font)
	ShowBand(false)
	InkLabels(false)
	GuardTabs()
end

-- (user, 2026-09-24: "dress rarely used windows on first open") nothing of
-- the look is made while the window has never been shown this session: its
-- first show dresses it (the OnShow hook below), a window already open when
-- the module comes on (a reload with it open) at once. Once made, the skin
-- stays for the session and is only switched on and off.
local function Built()
	return skin ~= nil and skin.built == true
end

local function Sync()
	local f = Window()
	if M.isEnabled and f then
		if Built() or IsShownSafe(f) == true then
			Activate()
		end
	else
		Deactivate()
	end
end

-- (geometry of the window's children changes here: out of combat only)
local function SyncSafe()
	Kit:WhenOutOfCombat(Sync)
end

-- The module switch and a dressed window go through SyncSafe, as always; the
-- first dress runs at once, in combat too, so the first frame the window
-- draws is already dressed. The dress makes frames and textures of our own
-- and moves only the game's textures and strings and the page tabs' size
-- (plain buttons of the game's pool), never a protected frame: nothing in it
-- is refused in combat.
local function SyncOrDress()
	if Built() then
		SyncSafe()
	else
		Sync()
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
			SyncOrDress()
		end
		Refresh()
	end)
	-- the game's own layout passes, post-hooked on the instances (the mixin
	-- methods live on the frames and the game calls them through self, so
	-- the hook hears every call): the bag slots, the page tabs, the item
	-- grid, a bank-tab client's tabs
	local P = Panel(f)
	for _, entry in ipairs({ { f, "RefreshBagButtons" }, { f, "RefreshPageTabs" }, { P, "GenerateItemSlotsForSelectedTab" }, { P, "RefreshBankTabs" } }) do
		local obj, method = entry[1], entry[2]
		if obj and type(obj[method]) == "function" then
			hooksecurefunc(obj, method, Refresh)
		end
	end
end

-- The bags' looks changed (Backpack Kit's options or the Dynamic UI picker,
-- both through NotifySettingChanged, whether that module is on or off): the
-- bank follows at once. The Button Border and the Side Tab Border reach the
-- rims and tabs through the Kit's own registries.
-- (the bus's 'setting', fired at the end of NotifySettingChanged where the
-- hook on it ran: audit 2026-09-24 rank 5, that hook ran for every setting
-- of every module and could never be taken off)
MelloUI:On("setting", Shared("'setting' on the bus", function(name, key, value)
	if name ~= "BackpackPanel" or not skin then
		return
	end
	if key == "itemBackground" then
		for button in pairs(slotKind) do
			Kit:SetButtonBackground(button, value)
		end
	elseif key == "windowBackground" then
		ApplyWindowBackground()
	end
end), M)

function M:OnEnable(db)
	self.db = db
	if Window() then
		Hook()
		SyncOrDress()
	end
end

function M:OnDisable()
	SyncSafe()
end

--------------------------------------------------------------------------------
-- /bankdump [slots | tabs | reps | regions | frames]: with no mode, what the
-- skin found and dressed (the shell, the portrait against the medallion, the
-- title's place and face, the band, the controls, the tabs and the page
-- picture per page) and the window's own regions and children; "slots" every
-- item and bag slot, "tabs" the tabs and the pictures alone; the other modes
-- are Kit:DumpWindow's. Opens the copy window.
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

local function Found(label, obj, more)
	MelloUI:Print("  %-26s %s%s", label, obj and Label(obj) or "-- not found", more or "")
end

local function Shown(obj)
	local s = IsShownSafe(obj)
	return s == nil and "?" or tostring(s)
end

local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.0f", v) or "?"
end

local function SizeOf(obj)
	if not (obj and obj.GetSize) then
		return "?", "?"
	end
	local ok, w, h = pcall(obj.GetSize, obj)
	if not ok then
		return "?", "?"
	end
	return Num(w), Num(h)
end

local function FadedState(obj)
	if not obj then
		return "-"
	end
	return Kit.faded[obj] and "faded" or (done[obj] and "known, not faded" or "untouched")
end

local function Dressed(obj)
	return tostring(obj ~= nil and obj.melloRep ~= nil and obj.melloRep ~= false)
end

local function DumpShell(f)
	local okLv, lv = pcall(f.GetFrameLevel, f)
	MelloUI:Print("BankFrame: shown %s, level %s, kit %s, reps %d, faded art %d, bank type:page %s", Shown(f),
		okLv and Num(lv) or "?", active and "on" or "off", skin and #skin.reps or 0, #fadedArt, CurrentPage())
	Found("outer rail (NineSlice)", f.NineSlice, f.NineSlice and (" layout " .. tostring(f.NineSlice.layoutType)) or nil)
	Found("page picture (Bg)", f.Bg, skin and skin.bgRep and (" -> " .. tostring(PictureRect())) or " (not dressed)")
	-- the portrait against the medallion (2b)
	local portrait = Portrait(f)
	local ring = skin and skin.ring
	if portrait then
		local okT, file = pcall(portrait.GetTexture, portrait)
		local w, h = SizeOf(portrait)
		local ringW = ring and ring.tex and select(1, SizeOf(ring.tex)) or "?"
		local medallion = tonumber(ringW) and string.format("%.0f", tonumber(ringW) * MEDALLION_TO_RING) or "?"
		Found("portrait", portrait, string.format(" file %s, size %s x %s, medallion %s (ring %s), fitted %s, shown %s",
			(okT and not Secret(file)) and tostring(file) or "?", w, h, medallion, ringW,
			tostring(portrait.melloSaved ~= nil), Shown(portrait)))
	else
		Found("portrait", nil)
	end
	Found("ring", ring and ring.object, ring and string.format(" shown %s, disc %s", Shown(ring.object), ring.disc and Shown(ring.disc) or "none") or nil)
	-- the title's place and face (2c)
	local title = TitleText(f)
	if title then
		local okT, text = pcall(title.GetText, title)
		local okF, face, size = pcall(title.GetFont, title)
		local rep = TitleRep()
		local plate = rep and rep.strip
		local on = "?"
		if plate then
			local okA, tx, ty = pcall(title.GetCenter, title)
			local okB, px, py = pcall(plate.GetCenter, plate)
			if okA and okB and tx and px and not (Secret(tx) or Secret(ty) or Secret(px) or Secret(py)) then
				on = string.format("text centre %.0f,%.0f, plate centre %.0f,%.0f", tx, ty, px, py)
			end
		end
		Found("title text", title, string.format(" text %s, face %s %s, title face %s, plate shown %s (%s)",
			(okT and type(text) == "string" and not Secret(text)) and text or "?",
			(okF and type(face) == "string" and not Secret(face)) and face or "?", okF and Num(size) or "?",
			tostring(title.melloFontSaved ~= nil), plate and Shown(plate) or "no plate", on))
	else
		Found("title text", nil)
	end
	local close = f.CloseButton
	local closeArt = close and close.GetNormalTexture and close:GetNormalTexture()
	Found("close button", close, close and (" game art " .. FadedState(closeArt)) or nil)
end

local function DumpParts(f)
	local P = Panel(f)
	Found("bank stone (Background)", f.Background, " " .. FadedState(f.Background))
	local insetPieces, insetFaded = 0, 0
	for _, tex in ipairs(TexturesOf(P and P.NineSlice)) do
		insetPieces = insetPieces + 1
		insetFaded = insetFaded + (Kit.faded[tex] and 1 or 0)
	end
	Found("content inset rails", P and P.NineSlice, string.format(" %d of %d faded", insetFaded, insetPieces))
	Found("edge shadows", P and P.EdgeShadows)
	local band = skin and skin.band
	Found("divider (bank-divider)", band and band.divider, band and band.divider and (" " .. FadedState(band.divider)) or " (fallback: the template's offset)")
	if band then
		local okR, l, b, w, h = pcall(band.rect.GetRect, band.rect)
		Found("band (2e panel)", band.rect, string.format(" rect %s, shown %s, panel alpha %.2f, divider strip shown %s",
			(okR and l and not Secret(l)) and string.format("x %.0f y %.0f w %.0f h %.0f", l, b, w, h) or "?",
			Shown(band.fill), DIM, Shown(band.strip.mid)))
	else
		Found("band (2e panel)", nil)
	end
	for _, fs in ipairs(List(f.BagText, f.BagCost)) do
		local okC, r, g, b = pcall(fs.GetTextColor, fs)
		local okF, _, size = pcall(fs.GetFont, fs)
		Found("label", fs, string.format(" colour %s, size %s, in the palette %s",
			(okC and type(r) == "number" and not Secret(r)) and string.format("%.2f %.2f %.2f", r, g, b) or "?",
			okF and Num(size) or "?", tostring(labelSaved[fs] ~= nil)))
	end
	local search = f.BankItemSearchBox or _G.BankItemSearchBox
	Found("search box", search, search and (" dressed " .. Dressed(search)) or nil)
	local sort = P and P.AutoSortButton
	Found("sort button", sort, sort and (" cog " .. tostring(done[sort] == true)) or nil)
	local money = P and P.MoneyFrame
	for _, b in ipairs(List(P and P.PurchaseButton, money and money.WithdrawButton, money and money.DepositButton)) do
		local okE, enabled = pcall(b.IsEnabled, b)
		Found("red button", b, string.format(" dressed %s, shown %s, enabled %s", Dressed(b), Shown(b),
			(okE and not Secret(enabled)) and tostring(enabled) or "?"))
	end
	Found("money bar", money and money.Border, skin and skin.coinPlate and " coin plate" or " (no plate)")
	Found("cost display", P and P.MoneyDisplay, P and P.MoneyDisplay and (" shown " .. Shown(P.MoneyDisplay)) or nil)
	for _, prompt in ipairs(List(P and P.LockPrompt, P and P.PurchasePrompt)) do
		Found("prompt", prompt, string.format(" shown %s, rail %s", Shown(prompt), tostring(done[prompt] == true)))
	end
	MelloUI:Print("  looks: Item Background %s, Window Background %s, Button Border %s, Side Tab Border %s",
		tostring(BagLook("itemBackground", "stone")), tostring(BagLook("windowBackground", "concrete")),
		tostring(Kit:BorderValue("button")), tostring(Kit:BorderValue("sidetab")))
	MelloUI:Print("  dressed: item slots %d, bag slots %d, page tabs %d, bank tabs %d, panel tabs %d, prompts %d",
		stats.items, stats.bags, stats.pageTabs, stats.bankTabs, stats.panelTabs, stats.prompts)
end

local function DumpTab(tab, kind)
	local rep = tab.melloRep
	local rim = rep and rep.object
	local iw, ih = SizeOf(tab.Icon)
	local rimW, rimH = SizeOf(rim)
	local glow = "none"
	if rim and rim.glow then
		local okA, a = pcall(rim.glow.GetAlpha, rim.glow)
		glow = (okA and not Secret(a)) and string.format("%.2f", rim.glow:IsShown() and a or 0) or "?"
	end
	Found(kind, tab, string.format(" bank %s page %s, shown %s, dressed %s, selected %s, rim %s %sx%s glow %s, icon %sx%s",
		tostring(tab.bankType), tostring(tab.pageNumber or (tab.tabData and tab.tabData.ID)), Shown(tab),
		Dressed(tab), Shown(tab.SelectedTexture), tostring(rim and rim.base), rimW, rimH, glow, iw, ih))
end

local function DumpTabs(f)
	local P = Panel(f)
	MelloUI:Print("Side tabs (Side Tab Border %s; the selected one's rim lit at 0.70, a hovered one's at 0.35):", tostring(Kit:BorderValue("sidetab")))
	local n = 0
	if f.bankPageTabPool then
		for tab in f.bankPageTabPool:EnumerateActive() do
			n = n + 1
			DumpTab(tab, "page tab")
		end
	end
	if P and P.bankTabPool then
		for tab in P.bankTabPool:EnumerateActive() do
			n = n + 1
			DumpTab(tab, "bank tab")
		end
	end
	if P and P.PurchaseTab and IsShownSafe(P.PurchaseTab) then
		n = n + 1
		DumpTab(P.PurchaseTab, "purchase tab")
	end
	for _, tab in ipairs(PanelTabs(f)) do
		if tab.Left and tab.LeftActive then
			n = n + 1
			Found("panel tab (TB6)", tab, string.format(" shown %s, dressed %s, open %s", Shown(tab), Dressed(tab), Shown(tab.LeftActive)))
		end
	end
	if n == 0 then
		MelloUI:Print("  (no tabs out: open the bank)")
	end
	MelloUI:Print("Page picture on each bank type:page seen since the reload (2a: the same rect on every one):")
	local any = false
	for page, rect in pairs(seenPictures) do
		any = true
		MelloUI:Print("  %-8s %s", page, rect)
	end
	if not any then
		MelloUI:Print("  (none yet: open the bank and switch its tabs)")
	end
	MelloUI:Print("  now (%s): %s", CurrentPage(), tostring(PictureRect()))
end

local function DumpSlot(button, kind, i)
	local rep = button.melloRep
	local rim = rep and rep.object
	local stone = button.melloSlotStone and button.melloSlotStone.tex
	local w, h = SizeOf(button)
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	Found(string.format("%s %d", kind, i), button, string.format(" %sx%s, rim %s, empty (Item Background shown) %s, quality border %s, slot picture %s, slot frame %s%s",
		w, h, tostring(rim and rim.base), stone and Shown(stone) or "?", Shown(button.IconBorder), FadedState(button.Background),
		(normal and Kit.faded[normal]) and "faded" or "shown", button.DisabledOverlay and (", padlock " .. Shown(button.DisabledOverlay)) or ""))
end

local function DumpSlots(f)
	local P = Panel(f)
	MelloUI:Print("Slots (Button Border %s, Item Background %s):", tostring(Kit:BorderValue("button")), tostring(BagLook("itemBackground", "stone")))
	local i = 0
	if P and P.itemButtonPool then
		for button in P.itemButtonPool:EnumerateActive() do
			i = i + 1
			DumpSlot(button, "item slot", i)
		end
	end
	i = 0
	if f.itemButtonBagPool then
		for button in f.itemButtonBagPool:EnumerateActive() do
			i = i + 1
			DumpSlot(button, "bag slot", i)
		end
	end
end

local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "")
		elseif kind == "FontString" then
			local okT, text = pcall(region.GetText, region)
			art = "text: " .. ((okT and type(text) == "string" and not Secret(text)) and text:sub(1, 40) or "?")
		end
		local okA, alpha = pcall(region.GetAlpha, region)
		MelloUI:Print("  region %s %s %s %s alpha %s shown %s", kind, Label(region), okL and tostring(layer) or "?", art,
			(okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?", Shown(region))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local okLv, lv = pcall(child.GetFrameLevel, child)
		MelloUI:Print("  child %s %s level %s shown %s%s", tostring(child:GetObjectType()), Label(child),
			okLv and Num(lv) or "?", Shown(child), child.melloRep ~= nil and " (dressed)" or "")
	end
end

SLASH_MELLOBANKDUMP1 = "/bankdump"
SlashCmdList.MELLOBANKDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if f and not Built() then
		-- (dressed on its first open: until then the game's window as it is)
		MelloUI:Print("/bankdump: BankFrame is not dressed yet (%s)", M.isEnabled
			and "the kit dresses it the first time it opens this session: visit a banker, then try again" or "the Bank Kit is off")
	end
	if not f then
		MelloUI:Print("/bankdump: no BankFrame on this client")
	elseif msg == "" then
		DumpShell(f)
		DumpParts(f)
		DumpTabs(f)
		MelloUI:Print("BankFrame's own regions and children:")
		DumpOwn(f)
	elseif msg == "slots" then
		DumpSlots(f)
	elseif msg == "tabs" then
		DumpTabs(f)
	else
		-- reps / frames / regions (the visible game textures): the Kit's dump
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	end
	MelloUI:ShowLog("bankdump " .. msg)
end
