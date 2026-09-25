--------------------------------------------------------------------------------
-- MelloUI - Merchant Kit
--
-- (user, 2026-09-24: "we didnt do quest dialogs, shops, Auction House,
-- profession training window, class trainers, Guild Crest Vendors, Flight
-- map, all should follow the rules"): the merchant window (MerchantFrame, a
-- ButtonFrameTemplate window of Blizzard_UIPanels_Game: the vendor's items,
-- the buyback list, the repairs) dressed in the painted kit (Modules/Kit.lua)
-- on the game's own layout, as every other window is (docs/WINDOW-RULES.md):
-- every kit piece stands in for one of the game's art regions, on that
-- region's rectangle, the game's art faded in its place; nothing of the
-- game's is moved but the portrait (brought to the medallion size and put
-- back on disable).
--
--   the window shell     outer double rail with gem corners, the page stone,
--                        the ring with the vendor's portrait at the class
--                        medallion's size on the dark disc (2b), the title
--                        plate on the rail with the vendor's name ON it in
--                        the title face (2c), the close button
--                        (Kit:SkinWindowShell)
--   the list area        the window's inset as the list box L1: single rail,
--                        stone under the palette's inner panel (2e)
--   the item cards       each slot's label plate (UI-Merchant-LabelSlots) ->
--                        a card in the main window's tone, a step lighter
--                        than the panel (2e's row stripe); the card turns the
--                        palette's dark red while the game paints the plate
--                        red (an item the player cannot use)
--   the item buttons     every window's Button Border rim (Kit:SkinActionButton:
--                        the icon in its opening, the quality border kept on
--                        the icon); the game's empty-slot square faded
--   repair / junk        the same rim round the game's icon, gold while the
--                        game is in single-item repair mode
--   the buyback slot     the item button's rim, as the grid's
--   page arrows          buttons/arrow_left / _right at the button's height
--                        (the file art's existing rule), dimmed while disabled
--   the bottom band      UI-Merchant-BotFrame -> the divider strip across the
--                        list box where the band's top edge was
--   money / currencies   the coin plate (B2, the bags' money strip) on the
--                        gold-edged bars; their small insets' art faded (the
--                        plate is the box)
--   the two tabs         TB6 cards (Kit:SkinPanelTab; an older tab template
--                        gets the same two cards)
--   the filter dropdown  the dropdown plate (D1)
--
-- Taint: nothing of the game's is replaced or re-scripted. The skin is made
-- and kept from post-hooks (MerchantFrame_Update, HookScript, the regions'
-- own Show / Hide / SetVertexColor, the buttons' Enable / Disable); what it
-- keeps about the game's frames lives in weak side tables; no buy, sell or
-- repair function is ever called. Switching the module off disables every
-- replacement (the game's art faded back in, ours hidden) and puts the
-- portrait and the title back: the window is the game's again.
--
-- /merchantdump [frames | reps | regions]: what the window is made of on
-- this client and what the skin dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("MerchantPanel")
local hooksecurefunc = Perf.hooksecurefunc
-- a handler made once and run for many asks, wrapped once: its time stays
-- on this file's own /melloperf row (review, 2026-09-24)
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("MerchantPanel", {
	title = "Merchant Kit",
	desc = "The merchant window (items, buyback, repair) in the kit.",
	window = { label = "Merchants", desc = "The merchant window (items, buyback, repair) in the kit.", tab = "Windows",
		frames = { "MerchantFrame" }, plainGrab = true, firstOpen = true },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local ITEM_SLOTS = 12     -- MerchantItem1..12 (10 on the merchant page, 12 on the buyback page)
local CARD_ALPHA = 0.85   -- WINDOW-RULES 2e: rows striped in the main window tone at about 0.85

local skin = nil          -- { reps = { every replacement }, followers = { { rep, region } } }
local active = false
local hooked = false

-- what this module made or looked at, kept OFF the game's frames (weak keys)
local done = setmetatable({}, { __mode = "k" })         -- [frame / region] = true: looked at once
local cards = {}                                        -- { tex, source (the game's label plate), item, red }
local toolRims = {}                                     -- the repair / junk buttons' rim holders { melloRep, icon, button }
local arrowReps = {}                                    -- the page arrows { rep, button }
local tabReps = {}                                      -- the tabs' cards { rep, region } (kept hidden while the kit is off)
local fadedArt = {}                                     -- game art faded with no piece of its own on its rect
local stats = { items = 0, cards = 0, tools = 0, tabs = 0, arrows = 0, plates = 0 }

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
			MelloUI:Notice("Merchant kit: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
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

-- a part by its key on the frame, else by the global name the XML gives it
-- ("$parent<suffix>"): the templates name some parts only
local function Part(frame, key, suffix)
	if not frame then
		return nil
	end
	if key and frame[key] then
		return frame[key]
	end
	local name = NameOf(frame)
	return name and suffix and _G[name .. suffix] or nil
end

-- Art faded while the kit is on with no piece on its own rect (the kit piece
-- that stands in for it sits elsewhere: the card for the slot's square, the
-- coin plate for the small inset's box, the divider for the band)
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

local function Window()
	return _G.MerchantFrame
end

-- whether the window is shown right now (secret-safe: unreadable is "no")
local function IsOpen(f)
	local ok, shown = pcall(f.IsShown, f)
	return ok and not Secret(shown) and shown and true or false
end

-- The vendor's portrait: PortraitFrameTemplate's container (SetPortraitToUnit
-- draws into it), else an older window's own named texture.
local function Portrait(f)
	local pc = f and f.PortraitContainer
	return (pc and pc.portrait) or (f and f.portrait) or _G.MerchantFramePortrait
end

-- The title string: the title container's (SetTitle writes the vendor's
-- name there), else an older window's named string.
local function TitleText(f)
	local tc = f and f.TitleContainer
	return (tc and tc.TitleText) or _G.MerchantNameText
end

--------------------------------------------------------------------------------
-- The item cards (WINDOW-RULES 2e: "too much small text over a plain brown
-- border is just an eye strain"). The game frames each slot's name and price
-- with its label plate (MerchantItemNNameFrame, UI-Merchant-LabelSlots) and
-- tints that plate by the item: grey for a normal item, red for one the
-- player cannot use. The card stands in for the plate: a texture of the
-- slot's own frame over the slot's rect, UNDER its name (BACKGROUND, below
-- the name's sublevel; the list box's panel is on a holder under the slot's
-- frame), in the palette's main window tone -- a stripe a step lighter than
-- the inner panel round it. The red is kept readable: while the game paints
-- the plate red, the card takes the palette's red (#4E1812, the selected
-- tab's), dark enough for the item's quality colour to read on it.
--------------------------------------------------------------------------------
local function CardColour(red)
	local P = MelloUI.Palette
	local c = P and (red and P.selectedTab or P.mainWindow) or (red and { 0.31, 0.09, 0.07 } or { 0.12, 0.11, 0.09 })
	return c[1], c[2], c[3]
end

local function PaintCard(entry)
	local r, g, b = CardColour(entry.red)
	entry.tex:SetColorTexture(r, g, b, CARD_ALPHA)
end

-- red while the game's plate is clearly red: (1, 0, 0) or (0.5, 0, 0); the
-- plain (0.5, 0.5, 0.5) and the empty slot's grey are not. nil: unreadable.
local function IsRed(r, g)
	if type(r) ~= "number" or type(g) ~= "number" or Secret(r) or Secret(g) then
		return nil
	end
	return r > 0.3 and g < 0.2
end

local function ReadTint(entry)
	local ok, r, g = pcall(entry.source.GetVertexColor, entry.source)
	if ok then
		local red = IsRed(r, g)
		if red ~= nil then
			entry.red = red
		end
	end
	PaintCard(entry)
end

local function SkinCard(item, plate)
	if not (item and plate and item.CreateTexture) or done[plate] then
		return
	end
	local tex = item:CreateTexture(nil, "BACKGROUND", nil, -2)
	tex.kitPiece = true   -- ours: never faded as the game's art
	tex:SetAllPoints(item)
	tex:SetShown(active)
	local entry = { tex = tex, source = plate, item = item, red = false }
	cards[#cards + 1] = entry
	ReadTint(entry)
	-- the plate is faded while the card stands in (Kit:Fade re-fades it after
	-- each SetVertexColor, which resets a texture's alpha on this client)
	FadeArt(plate)
	hooksecurefunc(plate, "SetVertexColor", function(_, r, g)
		local red = IsRed(r, g)
		if red ~= nil and red ~= entry.red then
			entry.red = red
			PaintCard(entry)
		end
	end)
	stats.cards = stats.cards + 1
end

-- An item button (ItemButton: icon, count, the quality's IconBorder, the
-- UI-Quickslot2 NormalTexture): every window's Button Border rim on the
-- button's rect with the icon in its opening and the quality border kept on
-- the icon (Kit:SkinActionButton, as the character window's slots). The
-- game's red / grey tint of an unusable item stays on the icon itself.
local function SkinItemButton(button)
	if not button or done[button] then
		return
	end
	done[button] = true
	if Kit:SkinActionButton(button, Replace, nil, { as = Kit:ButtonRimRule(), qualityBorder = button.IconBorder }) then
		stats.items = stats.items + 1
	end
end

-- One merchant slot (MerchantItemTemplate): its square (SlotTexture, the
-- empty-slot picture round the button) faded, the card for its label plate,
-- the rim on its button.
local function SkinItem(item)
	if not item or done[item] then
		return
	end
	done[item] = true
	FadeArt(Part(item, "SlotTexture", "SlotTexture"))
	SkinCard(item, Part(item, "NameFrame", "NameFrame"))
	SkinItemButton(Part(item, "ItemButton", "ItemButton"))
end

-- The buyback slot at the bottom (MerchantBuyBackItem, the last item sold):
-- the rim on its button, its square faded. The game hides its label plate
-- (its name and price lie on the list box's panel), so it gets no card.
local function SkinBuyback()
	local bb = _G.MerchantBuyBackItem
	if not bb or done[bb] then
		return
	end
	done[bb] = true
	FadeArt(Part(bb, "SlotTexture", "SlotTexture"))
	SkinItemButton(Part(bb, "ItemButton", "ItemButton"))
end

--------------------------------------------------------------------------------
-- The repair and junk buttons (36 px Buttons: a BACKGROUND empty-slot square,
-- the BORDER icon, the quickslot pushed look and the square highlight): the
-- Button Border rim hugging the icon (its edge 2 px under the rim's inner
-- edge, on the icon's centre -- the professions' and the macros' recipe),
-- the square, pushed and highlight looks faded (the rim carries hover and
-- press). The game switches these with Enable / Disable, which the rim's
-- own follower does not hear: its look is read again after each. The single
-- repair's rim is gold while the game is in repair mode (the game locks the
-- button's highlight then, faded here).
--------------------------------------------------------------------------------
local TOOL_BUTTONS = { "MerchantRepairAllButton", "MerchantRepairItemButton", "MerchantGuildBankRepairButton", "MerchantSellAllJunkButton" }

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

-- a new Button Border has a new opening: every tool rim fitted again
Kit:OnBorderChanged("button", function()
	for _, holder in ipairs(toolRims) do
		FitIconRim(holder)
	end
end)

-- a button's first texture in `layer`, other than `skip` and ours
local function TextureIn(button, layer, skip)
	for _, region in ipairs({ button:GetRegions() }) do
		if region ~= skip and region:GetObjectType() == "Texture" and not region.kitPiece then
			local ok, l = pcall(region.GetDrawLayer, region)
			if ok and l == layer then
				return region
			end
		end
	end
end

-- a rim's look read again from its button (enabled, hovered, pressed)
local function UpdateRim(holder)
	local rim = holder.melloRep and holder.melloRep.object
	if active and rim and rim.Update then
		rim:Update()
	end
end

-- (read through _G: a client without the function answers false)
local function InRepairMode()
	local fn = _G.InRepairMode
	if type(fn) ~= "function" then
		return false
	end
	local ok, v = pcall(fn)
	return ok and not Secret(v) and v == true
end

local function SkinTool(button)
	if not button or done[button] then
		return
	end
	done[button] = true
	-- the icon: the template's Icon key, an older window's "<name>Icon", else
	-- the button's BORDER texture
	local icon = Part(button, "Icon", "Icon") or TextureIn(button, "BORDER")
	if not icon then
		return
	end
	local back = TextureIn(button, "BACKGROUND", icon)
	local extra = List(button.GetPushedTexture and button:GetPushedTexture(), button.GetHighlightTexture and button:GetHighlightTexture())
	-- the rim stands in for the square; without one the icon itself is the
	-- region it is keyed on, and it is not faded. It starts on the icon's
	-- rect (the square is 64 px round a 36 px button) until FitIconRim can
	-- read the icon's laid-out size.
	local checked = (NameOf(button) == "MerchantRepairItemButton") and InRepairMode or nil
	local rep = Replace(back or icon, { as = Kit:ButtonRimRule(), button = button, parent = button, rect = icon, noFade = back == nil,
		checked = checked, alsoFade = extra })
	if not rep then
		return
	end
	local holder = { melloRep = rep, icon = icon, button = button }
	toolRims[#toolRims + 1] = holder
	Kit:RegisterButtonRim(holder)
	FitIconRim(holder)
	for _, method in ipairs({ "Enable", "Disable", "SetEnabled" }) do
		if button[method] then
			hooksecurefunc(button, method, function()
				UpdateRim(holder)
			end)
		end
	end
	stats.tools = stats.tools + 1
end

--------------------------------------------------------------------------------
-- The page arrows (MerchantPrevPageButton / NextPageButton: the spell book's
-- PrevPage / NextPage file art, a round UI-PageButton-Background behind
-- them): the kit's arrows at the button's height by that art's existing
-- rule, every other texture of the button faded (the background, the
-- pushed, disabled and highlight looks). The arrow pieces have no disabled
-- look: a disabled arrow (first / last page) is shown at a lower alpha, as
-- the game greys its own, read again after the game's Enable / Disable.
--------------------------------------------------------------------------------
local ARROWS = { { "MerchantPrevPageButton", "UI-SpellbookIcon-PrevPage-Up" }, { "MerchantNextPageButton", "UI-SpellbookIcon-NextPage-Up" } }

local function ArrowLook(entry)
	local tex = entry.rep.object
	if not (active and tex and tex.SetAlpha) then
		return
	end
	local ok, enabled = pcall(entry.button.IsEnabled, entry.button)
	if ok and not Secret(enabled) then
		tex:SetAlpha(enabled and 1 or 0.4)
	end
	if tex.Update then
		tex:Update()
	end
end

local function SkinArrows()
	for _, a in ipairs(ARROWS) do
		local b = _G[a[1]]
		local normal = b and b.GetNormalTexture and b:GetNormalTexture()
		if normal and not done[b] then
			done[b] = true
			local rep = Replace(normal, { as = a[2], button = b, rect = b, alsoFade = Kit:OtherTextures(b, normal) })
			if rep then
				local entry = { rep = rep, button = b }
				arrowReps[#arrowReps + 1] = entry
				for _, method in ipairs({ "Enable", "Disable", "SetEnabled" }) do
					if b[method] then
						hooksecurefunc(b, method, function()
							ArrowLook(entry)
						end)
					end
				end
				stats.arrows = stats.arrows + 1
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The list box (WINDOW-RULES 2e). The window's inset (ButtonFrameTemplate's
-- Inset, at the window's own level: useParentLevel) frames the item grid and
-- the bottom tools: dressed WITH its body (Kit:SkinInset), the list-box
-- stone under the palette's inner panel inside its rail (the inset rule's
-- `dim`). Its holder is kept AT the window's level: the slots are frames one
-- level up whose names are BACKGROUND regions, and a holder tied with them
-- could draw its stone over the names.
--------------------------------------------------------------------------------
local function InsetOf(f)
	return f.Inset or _G.MerchantFrameInset
end

local function KeepInsetUnder(f)
	local inset = InsetOf(f)
	local rep = inset and inset.melloRep
	local holder = rep and rep.object
	if not (holder and holder.SetFrameLevel) then
		return
	end
	local ok, fl = pcall(f.GetFrameLevel, f)
	if ok and fl and not Secret(fl) then
		holder:SetFrameLevel(fl)
		-- the rail and stone are drawn by the skin frame inside the holder,
		-- which was given its own level when it was made: it goes down too
		if rep.skin and rep.skin.SetFrameLevel then
			rep.skin:SetFrameLevel(fl)
		end
	end
end

local function SkinListBox(f)
	local inset = InsetOf(f)
	if not inset or done[inset] then
		return
	end
	done[inset] = true
	Kit:SkinInset(inset, Replace, f, true)
	KeepInsetUnder(f)
end

--------------------------------------------------------------------------------
-- The bottom band (MerchantFrameBottomLeftBorder, the UI-Merchant-BotFrame
-- atlas the game shows on the merchant page and hides on the buyback page;
-- an older window's two UI-Merchant-BottomBorder halves): the frame art
-- round the tools under the grid. The list box is the tools' box now, so the
-- band gives way to the one line it drew across the window: the divider
-- strip (window/divider, as a header's line) across the list box where the
-- band's top edge was, from rail to rail. The strip is made of REGIONS of
-- the list box's skin (over its stone and panel, under its rails and under
-- every frame of the window: the page arrows cross that line), shown while
-- the game shows the band.
--------------------------------------------------------------------------------
local function Bands()
	return List(_G.MerchantFrameBottomLeftBorder, _G.MerchantFrameBottomRightBorder)
end

-- the divider strip's own thickness (its painted box), as the other windows' lines
local function DividerThickness()
	local p = Kit:Piece("window/divider_mid")
	if p and p.box then
		return (p.box[4] - p.box[2]) * Kit.scale
	end
	return p and p.h * Kit.scale or 8
end

local function SyncDivider()
	local d = skin and skin.divider
	if not d then
		return
	end
	d.strip:SetShown((active and d.band:IsShown()) and true or false)
end

local function SkinBand(f)
	local bands = Bands()
	local band = bands[1]
	local inset = InsetOf(f)
	local rep = inset and inset.melloRep
	local host = rep and rep.skin
	for _, b in ipairs(bands) do
		FadeArt(b)
	end
	if not (band and host and host.CreateTexture) or skin.divider then
		return
	end
	-- the line's ends on the list box's side rails' centre lines, its height
	-- on the band's top edge: a WoW point carries both coordinates, so two
	-- helpers each span from the inset's top corner to the band's top on the
	-- far side, and the line hangs on their bottom corners
	local railIn = Kit:RailInset(Kit.framePrefix .. "_l", "l")
	local left = CreateFrame("Frame", nil, host)
	left:EnableMouse(false)
	left:SetPoint("TOPLEFT", inset, "TOPLEFT")
	left:SetPoint("BOTTOMRIGHT", band, "TOPRIGHT")
	local right = CreateFrame("Frame", nil, host)
	right:EnableMouse(false)
	right:SetPoint("TOPRIGHT", inset, "TOPRIGHT")
	right:SetPoint("BOTTOMLEFT", band, "TOPLEFT")
	-- BACKGROUND 3: over the box's stone (0) and panel (1), under its rails
	-- (BORDER: the line runs into them) and under the window's own "Page 1 of
	-- 2" (a BORDER string of the window, which sits at this level too and
	-- whose foot touches the line)
	local strip = Kit:Strip(host, "window/divider", { scale = Kit.scale, owner = host, layer = "BACKGROUND", sublevel = 3 })
	strip:EnableMouse(false)
	local yoff = strip:FitBox(DividerThickness())
	strip:ClearAllPoints()
	strip:SetPoint("LEFT", left, "BOTTOMLEFT", railIn, yoff)
	strip:SetPoint("RIGHT", right, "BOTTOMRIGHT", -railIn, yoff)
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
	skin.divider = { strip = strip, band = band }
	for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
		hooksecurefunc(band, method, SyncDivider)
	end
	SyncDivider()
end

--------------------------------------------------------------------------------
-- The money and the vendor's currencies (MerchantMoneyBg /
-- MerchantExtraCurrencyBg: ThinGoldEdgeTemplate bars, Left / Middle / Right
-- file pieces known by their names; each in a small inset of its own): the
-- coin plate (B2, the bags' money strip: the header plate on the bar's rect,
-- the coins on it). The small insets' art (their marble and rail) is faded:
-- the plate is the box, and a rail round a 19 px plate would stack two
-- frames on one bar. The plate's holder sits a level under the bar's frame,
-- so the coins and tokens (frames at the bar's level) are drawn over it.
--------------------------------------------------------------------------------
local function InsetArt(inset)
	local list = List(inset.Bg)
	if inset.NineSlice then
		for _, region in ipairs({ inset.NineSlice:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not region.kitPiece then
				list[#list + 1] = region
			end
		end
	end
	return list
end

local function SkinCoinBar(bar, inset)
	if bar and not done[bar] then
		done[bar] = true
		local mid = Part(bar, "Middle", "Middle")
		if mid and Replace(mid, { as = "common-coinbox-center", rect = bar, alsoFade = List(Part(bar, "Left", "Left"), Part(bar, "Right", "Right")) }) then
			stats.plates = stats.plates + 1
		end
	end
	if inset and not done[inset] then
		done[inset] = true
		for _, region in ipairs(InsetArt(inset)) do
			FadeArt(region)
		end
	end
end

--------------------------------------------------------------------------------
-- The tabs (Merchant / Buyback; PanelTabButtonTemplate on this client): TB6
-- cards by Kit:SkinPanelTab; an older CharacterFrameTabButtonTemplate
-- (Left for the closed tab, LeftDisabled for the open one, as the game
-- selects a tab by disabling it) gets the same two cards. The Kit's cards
-- follow their tab's textures on every Show / Hide, also while the kit is
-- off, which would bring a card back over the game's own tab on the next
-- tab switch; after those hooks this one sets every card from its texture
-- while the kit is on and hides them all while it is off (the macros' guard).
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

-- A piece the game shows and hides itself: shown with its region while the
-- kit is on.
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

local function SkinTab(tab)
	if not tab or done[tab] then
		return
	end
	done[tab] = true
	local plainTex, openTex
	local first = #skin.followers + 1
	if tab.Left and tab.LeftActive then
		plainTex, openTex = tab.Left, tab.LeftActive
		Kit:SkinPanelTab(tab, Replace, skin)
	else
		plainTex, openTex = Part(tab, "Left", "Left"), Part(tab, "LeftDisabled", "LeftDisabled")
		if not (plainTex and openTex) or tab.melloRep ~= nil then
			return
		end
		local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
		local plain = Replace(plainTex, { as = "uiframe-tab-left", rect = tab, button = tab,
			alsoFade = List(Part(tab, "Middle", "Middle"), Part(tab, "Right", "Right"), hl) })
		local open = Replace(openTex, { as = "uiframe-activetab-left", rect = tab,
			alsoFade = List(Part(tab, "MiddleDisabled", "MiddleDisabled"), Part(tab, "RightDisabled", "RightDisabled")) })
		-- the Kit's own "dressed" marker, as its tab helper sets it
		tab.melloRep = plain or open or false
		Follow(plain, plainTex)
		Follow(open, openTex)
	end
	for i = first, #skin.followers do
		tabReps[#tabReps + 1] = skin.followers[i]
	end
	for _, tex in ipairs(List(plainTex, openTex)) do
		hooksecurefunc(tex, "Show", GuardTabs)
		hooksecurefunc(tex, "Hide", GuardTabs)
		hooksecurefunc(tex, "SetShown", GuardTabs)
	end
	stats.tabs = stats.tabs + 1
end

local function Tabs(f)
	local list, seen = {}, {}
	for _, tab in ipairs(List(_G.MerchantFrameTab1, _G.MerchantFrameTab2)) do
		seen[tab] = true
		list[#list + 1] = tab
	end
	for _, tab in ipairs(f.Tabs or {}) do
		if not seen[tab] then
			seen[tab] = true
			list[#list + 1] = tab
		end
	end
	return list
end

-- The filter dropdown (WowStyle1DropdownTemplate: Background, Arrow, Text):
-- the dropdown plate (D1), its painted cap in place of the arrow. A client
-- whose rules turn the filter off hides the dropdown: the plate goes with it.
local function SkinDropdown(dd)
	if not (dd and dd.Background) or done[dd] or dd.melloRep ~= nil then
		return
	end
	done[dd] = true
	dd.melloRep = Replace(dd.Background, { as = "common-dropdown-textholder", rect = dd, button = dd, alsoFade = List(dd.Arrow) }) or false
end

--------------------------------------------------------------------------------
-- The portrait (WINDOW-RULES 2b / 2c: an empty ring is a bug). The game
-- draws the vendor into the PortraitContainer's portrait (SetPortraitToUnit;
-- the buyback page puts its scales icon there, SetPortraitToAsset): the
-- kit's ring on the corner, the portrait brought to the class medallion's
-- size in it (Kit:FitPortrait, its aspect kept) on the dark disc
-- (Kit:RingDisc) -- the round unit portrait covers the disc, the buyback
-- icon sits on it. Fitted again on every show and page switch (the window is
-- laid out only while shown); put back on disable.
--------------------------------------------------------------------------------
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
-- The title (WINDOW-RULES 2c: the title ON the plate, in the title face).
-- The shell's title plate centres the title container's TitleText on it in
-- Kit:TitleFont (which follows the Fonts options and the Font Style) and
-- puts it back on disable. SetTitle (the vendor's name, "Buyback") only
-- writes the text: the plate is fitted again on every show, and the face put
-- on again should anything have reset the string's font.
--------------------------------------------------------------------------------
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

	-- the shell: outer rail, one page stone, the ring, the title plate on the
	-- rail with the vendor's name on it, the close button
	local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = Portrait(f), bg = "UI-Background-Rock" })
	SkinPortrait(f, ring)

	-- the list box, then the band's line on it
	SkinListBox(f)
	SkinBand(f)
	-- the buyback page's translucent white wash over the list area: the list
	-- box's panel stands in (a white veil over it would undo the dark panel)
	FadeArt(_G.BuybackBG)

	-- the slots
	for i = 1, ITEM_SLOTS do
		SkinItem(_G["MerchantItem" .. i])
	end
	SkinBuyback()

	-- the tools, the arrows, the tabs, the dropdown, the money
	for _, bname in ipairs(TOOL_BUTTONS) do
		SkinTool(_G[bname])
	end
	SkinArrows()
	for _, tab in ipairs(Tabs(f)) do
		SkinTab(tab)
	end
	SkinDropdown(f.FilterDropdown)
	SkinCoinBar(_G.MerchantMoneyBg, _G.MerchantMoneyInset)
	SkinCoinBar(_G.MerchantExtraCurrencyBg, _G.MerchantExtraCurrencyInset)
end

-- Refresh's pass a frame later, once the window is laid out (made once:
-- Kit:NextFrame runs it once however often it was asked -- audit, 2026-09-24;
-- timed on this window's own /melloperf row, not the Kit's timer -- review)
local RefreshLater = Shared("Refresh a frame later", function()
	local f = Window()
	if active and f and f:IsShown() then
		FitPortrait()
		PlaceTitle()
		for _, holder in ipairs(toolRims) do
			FitIconRim(holder)
		end
	end
end, "timer")

-- After every show and every game refresh (a page or tab switch, a sale):
-- what the game re-laid or re-showed since (the portrait's size, the title's
-- plate, the cards' tints, the arrows' and tools' states, the followers).
local function Refresh()
	local f = Window()
	if not (active and skin and f) then
		return
	end
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	GuardTabs()
	SyncDivider()
	KeepInsetUnder(f)
	for _, entry in ipairs(cards) do
		ReadTint(entry)
	end
	for _, entry in ipairs(arrowReps) do
		ArrowLook(entry)
	end
	for _, holder in ipairs(toolRims) do
		FitIconRim(holder)
		UpdateRim(holder)
	end
	FitPortrait()
	PlaceTitle()
	-- once laid out (a frame after it shows): the portrait, title and rims
	-- again -- one pass pending at a time (the game refreshes on every bag
	-- change while the window is open)
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
	for _, entry in ipairs(cards) do
		entry.tex:Show()
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
	for _, entry in ipairs(cards) do
		entry.tex:Hide()
	end
	-- the tabs' cards hidden for good while off, the divider with them (the
	-- ring's onDisable put the portrait back, the title plate's the title's
	-- points and font)
	GuardTabs()
	SyncDivider()
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
		if Built() or IsOpen(f) then
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
-- and moves only the game's textures and strings (the portrait, the title,
-- the icons, the tabs' labels), never a protected frame: nothing in it is
-- refused in combat.
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
	-- the game's own refresh (a page or tab switch, a sale, a bag change: the
	-- title, the portrait, the band and the slots' tints change there); it
	-- runs both page updates, so one post-hook sees them all. A client
	-- without it: the two page updates themselves.
	if type(_G.MerchantFrame_Update) == "function" then
		hooksecurefunc("MerchantFrame_Update", Refresh)
	else
		for _, fname in ipairs({ "MerchantFrame_UpdateMerchantInfo", "MerchantFrame_UpdateBuybackInfo" }) do
			if type(_G[fname]) == "function" then
				hooksecurefunc(fname, Refresh)
			end
		end
	end
end

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
-- /merchantdump [frames | reps | regions]: with no mode, what the skin found
-- and dressed (every part, found or not, and its state) and the window's own
-- regions and children; the modes are Kit:DumpWindow's. Opens the copy window.
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
	local ok, s = pcall(obj.IsShown, obj)
	return (ok and not Secret(s)) and tostring(s) or "?"
end

local function Dressed(obj)
	return tostring(obj ~= nil and obj.melloRep ~= nil and obj.melloRep ~= false)
end

local function FadedState(obj)
	if not obj then
		return "-"
	end
	return Kit.faded[obj] and "faded" or (done[obj] and "known, not faded" or "untouched")
end

local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.0f", v) or "?"
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

local function DumpShell(f)
	local okLv, lv = pcall(f.GetFrameLevel, f)
	MelloUI:Print("MerchantFrame: shown %s, level %s, kit %s, reps %d, followers %d, faded art %d", Shown(f),
		okLv and Num(lv) or "?", active and "on" or "off", skin and #skin.reps or 0, skin and #skin.followers or 0, #fadedArt)
	Found("outer rail (NineSlice)", f.NineSlice, f.NineSlice and (" layout " .. tostring(f.NineSlice.layoutType)) or " (an older frame: no shell)")
	Found("page stone (Bg)", f.Bg)
	local portrait = Portrait(f)
	if portrait then
		local okT, file = pcall(portrait.GetTexture, portrait)
		local okS, w, h = pcall(portrait.GetSize, portrait)
		Found("portrait", portrait, string.format(" file %s, size %s x %s, fitted %s, shown %s",
			(okT and not Secret(file)) and tostring(file) or "?", okS and Num(w) or "?", okS and Num(h) or "?",
			tostring(portrait.melloSaved ~= nil), Shown(portrait)))
	else
		Found("portrait", nil)
	end
	Found("ring", skin and skin.ring and skin.ring.object, skin and skin.ring and (" disc " .. tostring(skin.ring.disc ~= nil)) or nil)
	Found("title container", f.TitleContainer)
	local title = TitleText(f)
	if title then
		local okT, text = pcall(title.GetText, title)
		local okF, face = pcall(title.GetFont, title)
		Found("title text", title, string.format(" text %s, face %s, title face %s, plate %s",
			(okT and type(text) == "string" and not Secret(text)) and text or "?",
			(okF and type(face) == "string" and not Secret(face)) and face or "?",
			tostring(title.melloFontSaved ~= nil), tostring(TitleRep() ~= nil)))
	else
		Found("title text", nil)
	end
end

local function DumpParts(f)
	local inset = InsetOf(f)
	Found("list box (Inset)", inset, inset and string.format(" dressed %s, dim %s", Dressed(inset),
		tostring(inset.melloRep and inset.melloRep.skin and inset.melloRep.skin.dimFill ~= nil)) or nil)
	for _, band in ipairs(Bands()) do
		Found("bottom band", band, string.format(" %s, shown %s", FadedState(band), Shown(band)))
	end
	Found("band's divider", skin and skin.divider and skin.divider.strip, skin and skin.divider and (" shown " .. Shown(skin.divider.strip)) or nil)
	Found("buyback wash (BuybackBG)", _G.BuybackBG, _G.BuybackBG and (" " .. FadedState(_G.BuybackBG)) or nil)
	for i = 1, ITEM_SLOTS do
		local item = _G["MerchantItem" .. i]
		local card
		for _, entry in ipairs(cards) do
			if entry.item == item then
				card = entry
			end
		end
		Found("slot " .. i, item, item and string.format(" shown %s, rim %s, card %s%s, square %s", Shown(item),
			Dressed(Part(item, "ItemButton", "ItemButton")), tostring(card ~= nil), card and (card.red and " (red: unusable)" or " (plain)") or "",
			FadedState(Part(item, "SlotTexture", "SlotTexture"))) or nil)
	end
	local bb = _G.MerchantBuyBackItem
	Found("buyback slot", bb, bb and string.format(" shown %s, rim %s", Shown(bb), Dressed(Part(bb, "ItemButton", "ItemButton"))) or nil)
	for _, bname in ipairs(TOOL_BUTTONS) do
		local b = _G[bname]
		local rimmed = false
		for _, holder in ipairs(toolRims) do
			rimmed = rimmed or holder.button == b
		end
		local okE, enabled = false, nil
		if b then
			okE, enabled = pcall(b.IsEnabled, b)
		end
		Found("tool button", b, b and string.format(" rim %s, shown %s, enabled %s", tostring(rimmed), Shown(b),
			(okE and not Secret(enabled)) and tostring(enabled) or "?") or nil)
	end
	for _, a in ipairs(ARROWS) do
		local b = _G[a[1]]
		local dressed = false
		for _, entry in ipairs(arrowReps) do
			dressed = dressed or entry.button == b
		end
		Found("page arrow", b, b and string.format(" dressed %s, shown %s", tostring(dressed), Shown(b)) or nil)
	end
	Found("page text", _G.MerchantPageText)
	for _, tab in ipairs(Tabs(f)) do
		local kind = "unknown template"
		if tab.Left and tab.LeftActive then
			kind = "TB6 (Left / LeftActive)"
		elseif Part(tab, "LeftDisabled", "LeftDisabled") then
			kind = "older (Left / LeftDisabled)"
		end
		Found("tab", tab, string.format(" %s, dressed %s", kind, Dressed(tab)))
	end
	local dd = f.FilterDropdown
	Found("filter dropdown", dd, dd and string.format(" dressed %s, shown %s", Dressed(dd), Shown(dd)) or nil)
	Found("money bar", _G.MerchantMoneyBg)
	local mi = _G.MerchantMoneyInset
	Found("money inset", mi, mi and (" art " .. FadedState(mi.Bg)) or nil)
	Found("money", _G.MerchantMoneyFrame)
	Found("currency bar", _G.MerchantExtraCurrencyBg, _G.MerchantExtraCurrencyBg and (" shown " .. Shown(_G.MerchantExtraCurrencyBg)) or nil)
	MelloUI:Print("  slots in rims %d, cards %d, tool rims %d, arrows %d, tabs %d, coin plates %d",
		stats.items, stats.cards, stats.tools, stats.arrows, stats.tabs, stats.plates)
end

SLASH_MELLOMERCHANTDUMP1 = "/merchantdump"
SlashCmdList.MELLOMERCHANTDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if f and not Built() then
		-- (dressed on its first open: until then the game's window as it is)
		MelloUI:Print("/merchantdump: MerchantFrame is not dressed yet (%s)", M.isEnabled
			and "the kit dresses it the first time it opens this session: visit a merchant, then try again" or "the Merchant Kit is off")
	end
	if not f then
		MelloUI:Print("/merchantdump: no MerchantFrame on this client")
	elseif msg == "" then
		DumpShell(f)
		DumpParts(f)
		MelloUI:Print("MerchantFrame's own regions and children:")
		DumpOwn(f)
	else
		-- frames / reps / regions (the visible game textures): the Kit's dump
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	end
	MelloUI:ShowLog("merchantdump " .. msg)
end
