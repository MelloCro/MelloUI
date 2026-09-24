--------------------------------------------------------------------------------
-- MelloUI - Trade Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): the trade window (TradeFrame, a ButtonFrameTemplate window of
-- Blizzard_UIPanels_Game, Mainline/TradeFrame.xml on this client: the two
-- sides, each with six items to trade and the "will not be traded" slot,
-- the money boxes, Trade / Cancel) dressed in the painted kit (Modules/
-- Kit.lua) on the game's own layout, as every other window is
-- (docs/WINDOW-RULES.md): every kit piece stands in for one of the game's
-- art regions, on that region's rectangle, the game's art faded in its
-- place.
--
--   the window shell     outer double rail with gem corners, the page stone,
--                        the ring with the player's portrait at the class
--                        medallion's size on the dark disc (2b), the title
--                        plate on the rail, the close button
--                        (Kit:SkinWindowShell)
--   the two names        the window's title is the two players' names: both
--                        stand ON the plate (2c), in the title face, the
--                        player's between the two rings, the other player's
--                        right of theirs; put back on disable
--   the other player's   the recipient's own portrait corner (RecipientOverlay:
--   portrait             the metal ring over their portrait) -> the kit's ring,
--                        their portrait at the medallion size on the disc (2b)
--   the item lists       the four item insets (six items, the enchant slot)
--                        as list boxes L1: single rail, stone under the
--                        palette's inner panel (2e); the window's big inset
--                        behind them faded (one box per list, never two)
--   the item rows        each row's name plate (UI-QuestItemNameFrame) -> a
--                        card in the main window's tone (2e's row stripe),
--                        the palette's dark red while the game paints the
--                        plate red (the other player's item you cannot use)
--   the item buttons     the Button Border rim hugging the icon (the icon and
--                        the button untouched: the rim is ours), the quality
--                        border kept on the icon; the empty-slot square faded
--   the divider          the metal rail between the two sides (!UI-Frame-
--                        LeftTile + its bottom corner) -> the pane divider
--                        (common-framedivider: the single rail's edge)
--   money                the coin plate (B2, the bags' money strip) on each
--                        money box; the small insets' art faded (the plate is
--                        the box); the gold / silver / copper boxes get the
--                        edit plate (S1) where this client lets an addon reach
--                        them (the game marks the player's input forbidden)
--   Trade / Cancel       the red plates (B1), labels readable (melloNoInk)
--
-- Left as the game's: the acceptance highlights (the green glow over a side
-- that has accepted: the game's state, shown and hidden by it), the item
-- change alert flipbook, the enchant slot's scroll picture, the warning icon
-- on Trade, the texts.
--
-- Taint: nothing of the game's is replaced or re-scripted, no trade function
-- is ever called. The skin is made and kept from post-hooks (TradeFrame_Update,
-- HookScript, the regions' own SetVertexColor, the buttons' Enable /
-- Disable); what it keeps about the game's frames lives in weak side tables.
-- The item buttons are never moved or resized: the rims are our own textures
-- round their icons. Switching the module off disables every replacement and
-- puts the portraits, the names and their font back: the window is the
-- game's again.
--
-- /tradedump [frames | reps | regions]: what the window is made of on this
-- client and what the skin dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("TradePanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("TradePanel", {
	title = "Trade Kit",
	desc = "The trade window in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local ITEMS = 7           -- MAX_TRADE_ITEMS: six to trade, the seventh the "will not be traded" (enchant) slot
local CARD_ALPHA = 0.85   -- WINDOW-RULES 2e: rows striped in the main window tone at about 0.85

-- the two sides, by the names the XML gives their parts
local SIDES = {
	{ key = "player", items = "TradePlayerItem", name = "TradeFramePlayerNameText", list = "TradePlayerItemsInset",
		enchant = "TradePlayerEnchantInset", label = "TradeFramePlayerEnchantText" },
	{ key = "recipient", items = "TradeRecipientItem", name = "TradeFrameRecipientNameText", list = "TradeRecipientItemsInset",
		enchant = "TradeRecipientEnchantInset", label = "TradeFrameRecipientEnchantText" },
}

local skin = nil          -- { reps = { every replacement }, followers = { { rep, region } }, ring, recipientRing, divider }
local active = false
local hooked = false

-- what this module made or looked at, kept OFF the game's frames (weak keys)
local done = setmetatable({}, { __mode = "k" })         -- [frame / region] = true: looked at once
local cards = {}                                        -- { tex, source (the game's name plate), item, red }
local rims = {}                                         -- the item buttons' rims { rep, icon, button }
local fadedArt = {}                                     -- game art faded with no piece of its own on its rect
local insets = {}                                       -- the list boxes { inset, side, kind }
local names = {}                                        -- the two names on the plate { fs, points (the game's), side }
local moneyNotes = {}                                   -- [side key] = how its money box was dressed
local stats = { items = 0, cards = 0, insets = 0, plates = 0, edits = 0, buttons = 0 }

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Trade kit: no kit piece mapped for %s", tostring(key))
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
	-- (the method looked up inside the pcall: the game's forbidden frames --
	-- the player's money input -- refuse an addon on the lookup itself)
	local ok, n = pcall(function() return obj:GetName() end)
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

local function IsTexture(obj)
	return obj ~= nil and obj.GetObjectType ~= nil and obj:GetObjectType() == "Texture"
end

-- Art faded while the kit is on with no piece on its own rect (the kit piece
-- that stands in for it sits elsewhere: the card for the slot's square, the
-- coin plate for a small inset's box, the list boxes for the big inset)
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
	return _G.TradeFrame
end

-- whether the window is shown right now (secret-safe: unreadable is "no")
local function IsOpen(f)
	local ok, shown = pcall(f.IsShown, f)
	return ok and not Secret(shown) and shown and true or false
end

-- The player's portrait: PortraitFrameTemplate's container (SetPortraitToUnit
-- draws into it), else an older window's own named texture.
local function Portrait(f)
	local pc = f and f.PortraitContainer
	return (pc and pc.portrait) or (f and f.portrait) or _G.TradeFramePortrait
end

-- an inset's art: its marble and its nine-slice pieces
local function InsetArt(inset)
	local list = List(inset and inset.Bg)
	if inset and inset.NineSlice then
		for _, region in ipairs({ inset.NineSlice:GetRegions() }) do
			if IsTexture(region) and not region.kitPiece then
				list[#list + 1] = region
			end
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- The item cards (WINDOW-RULES 2e: "too much small text over a plain brown
-- border is just an eye strain"). The game frames each row's name with its
-- name plate (TradeXItemNNameFrame, UI-QuestItemNameFrame) and paints the
-- other player's plate red for an item the player cannot use. The card
-- stands in for the plate: a texture of the row's own frame over the row's
-- rect, UNDER its name (BACKGROUND, below the name's sublevel; the list box's
-- panel is on a holder under the row's frame), in the palette's main window
-- tone -- a stripe a step lighter than the inner panel round it; the palette's
-- red (#4E1812) while the game paints the plate red.
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

-- red while the game's plate is clearly red ((0.9, 0, 0) on this window);
-- the plain white is not. nil: unreadable.
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

--------------------------------------------------------------------------------
-- The item buttons (ItemButton: icon, count, the quality's IconBorder, the
-- UI-Quickslot2 NormalTexture, the pushed and highlight squares): every
-- window's Button Border rim round the icon, its inner edge 2 px over the
-- icon's (the merchant's tool buttons' recipe), the normal, pushed and
-- highlight squares faded (the rim carries hover and press). The rim is a
-- texture of our own on the button: the button and its icon are never moved
-- or resized, and the game's quality border stays on the icon, inside the
-- rim's opening.
--------------------------------------------------------------------------------
local function FitIconRim(entry)
	local rim = entry.rep and entry.rep.object
	local icon = entry.icon
	if not (rim and rim.base and icon) then
		return
	end
	local name = rim.base .. "_normal"
	local p = Kit:Piece(name)
	local l, r, t, b = Kit:Insets(name, 1)
	local ok, iw, ih = pcall(icon.GetSize, icon)
	if not ok or Secret(iw) or Secret(ih) or not (iw and ih) or iw <= 0 or ih <= 0 then
		-- an icon laid out by its points only reads 0 until the frame is drawn:
		-- the button's size stands in (the icon fills it on these buttons)
		ok, iw, ih = pcall(entry.button.GetSize, entry.button)
	end
	if not (p and l and ok and iw and ih) or Secret(iw) or Secret(ih) or iw <= 0 or ih <= 0 then
		return
	end
	rim:ClearAllPoints()
	rim:SetPoint("CENTER", icon, "CENTER")
	rim:SetSize((iw - 4) * p.w / (p.w - l - r), (ih - 4) * p.h / (p.h - t - b))
end

-- a new Button Border has a new opening: every rim fitted again
Kit:OnBorderChanged("button", function()
	for _, entry in ipairs(rims) do
		FitIconRim(entry)
	end
end)

local function UpdateRim(entry)
	local rim = entry.rep and entry.rep.object
	if active and rim and rim.Update then
		rim:Update()
	end
end

local function SkinItemButton(button)
	if not button or done[button] or button.melloRep ~= nil then
		return
	end
	done[button] = true
	local icon = button.icon or button.Icon or Part(button, nil, "IconTexture")
	if not icon then
		return
	end
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	local extra = List(button.GetPushedTexture and button:GetPushedTexture(), button.GetHighlightTexture and button:GetHighlightTexture())
	-- the rim stands in for the normal square; without one the icon is only
	-- the rect it is keyed on, and it is not faded
	local rep = Replace(normal or icon, { as = Kit:ButtonRimRule(), button = button, parent = button, rect = icon,
		noFade = normal == nil, alsoFade = extra })
	button.melloRep = rep or false   -- the Kit's own "dressed" marker
	if not rep then
		return
	end
	local entry = { rep = rep, icon = icon, button = button }
	rims[#rims + 1] = entry
	Kit:RegisterButtonRim(button)
	FitIconRim(entry)
	for _, method in ipairs({ "Enable", "Disable", "SetEnabled" }) do
		if button[method] then
			hooksecurefunc(button, method, function()
				UpdateRim(entry)
			end)
		end
	end
	stats.items = stats.items + 1
end

-- One row (TradeItemTemplate: SlotTexture, the empty-slot square round the
-- button; NameFrame, the name plate; Name; the ItemButton): the square
-- faded, the card for the plate, the rim on the button. The enchant slot's
-- scroll picture (an unnamed ARTWORK texture of row 7) stays the game's.
local function SkinItem(item)
	if not item or done[item] then
		return
	end
	done[item] = true
	FadeArt(Part(item, "SlotTexture", "SlotTexture"))
	SkinCard(item, Part(item, "NameFrame", "NameFrame"))
	SkinItemButton(Part(item, "ItemButton", "ItemButton"))
end

--------------------------------------------------------------------------------
-- The list boxes (WINDOW-RULES 2e). Each side's two insets (the six items;
-- the enchant slot with its "will not be traded" line) are InsetFrameTemplates
-- at the window's own level (useParentLevel): dressed WITH their body
-- (Kit:SkinInset), the list-box stone under the palette's inner panel inside
-- the rail (the inset rule's `dim`). Their holders are kept AT the window's
-- level: the rows are frames one level up whose names are BACKGROUND
-- regions, and a holder tied with them could draw its stone over the names.
-- The window's own big inset (ButtonFrameTemplate's Inset, behind all of
-- them) is faded: a second box round the boxes would stack two rails.
--------------------------------------------------------------------------------
local function KeepUnder(f, inset)
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

local function SkinListBox(f, inset, side, kind)
	if not inset or done[inset] then
		return
	end
	done[inset] = true
	Kit:SkinInset(inset, Replace, f, true)
	insets[#insets + 1] = { inset = inset, side = side, kind = kind }
	KeepUnder(f, inset)
	stats.insets = stats.insets + 1
end

--------------------------------------------------------------------------------
-- The divider between the two sides (TradeRecipientLeftBorder, the
-- !UI-Frame-LeftTile rail from under the other player's portrait down to the
-- window's foot, and TradeRecipientBotLeftCorner, its corner piece): the pane
-- divider (common-framedivider, the single rail's edge), its line centred on
-- the gap between the two sides' boxes (the tile's left edge is the player's
-- boxes' right edge; the other side's boxes start 9 px further: the XML's
-- 166 / 175), from the tile's top to the corner's foot (the outer rail covers
-- the end). The corner is faded with the tile.
--------------------------------------------------------------------------------
local GAP_MIDDLE = 4.5   -- UI px from the tile's left edge to the middle of the gap between the sides' boxes

local function SkinDivider(f)
	local border, corner = _G.TradeRecipientLeftBorder, _G.TradeRecipientBotLeftCorner
	if not border or skin.divider then
		return
	end
	local scale = Kit.scale * Kit.frameScale
	local piece = Kit.framePrefix .. "_l"
	local w = Kit:Size(piece, scale)
	local centre = Kit:RailInset(piece, "l", scale)
	if not (w and w > 0) then
		return
	end
	local sizer = CreateFrame("Frame", nil, f)
	sizer:EnableMouse(false)
	sizer:SetPoint("TOPLEFT", border, "TOPLEFT", GAP_MIDDLE - centre, 0)
	sizer:SetPoint("BOTTOMLEFT", corner or border, "BOTTOMLEFT", GAP_MIDDLE - centre, 0)
	sizer:SetWidth(w)
	-- level 2: over the boxes' holders (at the window's level) and the
	-- acceptance glows (+1), under the item buttons (+3); nothing of the
	-- game's at +2 lies in the gap
	skin.divider = Replace(border, { as = "common-framedivider", parent = f, rect = sizer, level = 2, alsoFade = List(corner) })
end

--------------------------------------------------------------------------------
-- The money boxes. The other player's (TradeRecipientMoneyBg, a
-- ThinGoldEdgeTemplate bar the game shows at 0.6, the coins on it, in a small
-- inset whose marble the game hides): the coin plate (B2, the bags' money
-- strip) on the bar's rect, on a holder of the WINDOW (the bar's own alpha
-- would dim it) one level over it -- the coins (a frame one level up too,
-- with no art of its own under them) stay readable on it; the inset's rail
-- faded. The player's (TradePlayerInputMoneyInset round the gold / silver /
-- copper input boxes): the same plate on the inset's rect; the game marks the
-- input frame forbidden to addons (TradeFrame_OnLoad: SetForbidden), so its
-- boxes keep their own art on the plate. On a client that lets them be
-- reached, the boxes get the edit plate S1 instead (their LEFT cap dropped:
-- that cap is the search glass, these are number boxes) and the inset's art
-- is only faded.
--------------------------------------------------------------------------------
local function Reachable(frame)
	if not frame then
		return false
	end
	local ok, forbidden = pcall(function() return frame:IsForbidden() end)
	if not ok or Secret(forbidden) or forbidden then
		return false
	end
	local okC = pcall(function() return frame:GetChildren() end)
	return okC
end

-- an edit box's three art pieces (Left / Middle / Right, by key or name)
local function EditArt(edit)
	local name = NameOf(edit)
	local function Get(key)
		local v = edit[key] or (name and _G[name .. key])
		return IsTexture(v) and v or nil
	end
	return Get("Left"), Get("Middle") or Get("Mid"), Get("Right")
end

local function SkinEdit(edit)
	if done[edit] or edit.melloRep ~= nil then
		return false
	end
	done[edit] = true
	local left, mid, right = EditArt(edit)
	if not (left and mid and right) then
		return false
	end
	local rect = CreateFrame("Frame", nil, edit)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", left, "TOPLEFT")
	rect:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT")
	edit.melloRep = Replace(mid, { as = "common-search-border-middle", rect = rect, edit = edit, dropCap = "l", alsoFade = { left, right } }) or false
	if edit.melloRep then
		stats.edits = stats.edits + 1
		return true
	end
	return false
end

local function SkinMoney(f)
	-- the other player's bar
	local bar = _G.TradeRecipientMoneyBg
	for _, region in ipairs(InsetArt(_G.TradeRecipientMoneyInset)) do
		FadeArt(region)
	end
	local mid = Part(bar, "Middle", "Middle")
	if mid and not done[bar] then
		done[bar] = true
		if Replace(mid, { as = "common-coinbox-center", parent = f, rect = bar, level = 1, alsoFade = List(Part(bar, "Left", "Left"), Part(bar, "Right", "Right")) }) then
			stats.plates = stats.plates + 1
			moneyNotes.recipient = "coin plate (B2) on TradeRecipientMoneyBg"
		end
	elseif not bar then
		moneyNotes.recipient = "no TradeRecipientMoneyBg: not dressed"
	end
	-- the player's input
	local pinset = _G.TradePlayerInputMoneyInset
	local input = _G.TradePlayerInputMoneyFrame
	if not pinset or done[pinset] then
		return
	end
	done[pinset] = true
	local edits = 0
	if Reachable(input) then
		for _, child in ipairs({ input:GetChildren() }) do
			if child.GetObjectType and child:GetObjectType() == "EditBox" and SkinEdit(child) then
				edits = edits + 1
			end
		end
	end
	local art = InsetArt(pinset)
	if edits > 0 then
		for _, region in ipairs(art) do
			FadeArt(region)
		end
		moneyNotes.player = string.format("edit plates (S1) on %d input boxes, the inset's art faded", edits)
		return
	end
	local first = table.remove(art, 1)
	if first and Replace(first, { as = "common-coinbox-center", parent = f, rect = pinset, level = 1, alsoFade = art }) then
		stats.plates = stats.plates + 1
		moneyNotes.player = "coin plate (B2) on TradePlayerInputMoneyInset (the input boxes " .. (input and "forbidden to addons: their own art" or "not found") .. ")"
	end
end

--------------------------------------------------------------------------------
-- Trade / Cancel (UIPanelButtonTemplate): the red plates (B1). The labels
-- stay readable on them: the parchment ink never enters a button marked
-- melloNoInk (the kit's accepted marker; no parchment lies here today, but a
-- label on a red plate is never inked). Trade's disabled look follows the
-- game's Enable / Disable (the plate's disabled state).
--------------------------------------------------------------------------------
local function SkinButtons()
	for _, bname in ipairs({ "TradeFrameTradeButton", "TradeFrameCancelButton" }) do
		local b = _G[bname]
		if b and not done[b] then
			done[b] = true
			b.melloNoInk = true
			if Kit:SkinRedButton(b, Replace) then
				stats.buttons = stats.buttons + 1
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The portraits (WINDOW-RULES 2b / 2c: an empty ring is a bug). The game
-- draws the player into the window's PortraitContainer (SetPortraitToUnit)
-- and the other player into RecipientOverlay.portrait, under that overlay's
-- own metal corner (UI-Frame-PortraitMetal-CornerTopLeft, the same atlas as
-- the window's corner): the kit's ring on both, each portrait brought to the
-- class medallion's size in its ring (Kit:FitPortrait, aspect kept) on the
-- dark disc (Kit:RingDisc; a round unit portrait covers it). Fitted again on
-- every show and update; put back on disable.
--
-- The other player's ring is made BEFORE the shell: a ring replacement tells
-- the window mover which ring the title plate runs behind, and the last one
-- made wins -- the window's own ring must be that one.
--------------------------------------------------------------------------------
local function RecipientParts(f)
	local o = f and f.RecipientOverlay
	return o, o and o.portrait, o and o.portraitFrame
end

local function FitPortraits()
	if not (active and skin) then
		return
	end
	local f = Window()
	local portrait = Portrait(f)
	if skin.ring and portrait then
		pcall(Kit.FitPortrait, Kit, portrait, skin.ring)
	end
	local _, rp = RecipientParts(f)
	if skin.recipientRing and rp then
		pcall(Kit.FitPortrait, Kit, rp, skin.recipientRing)
	end
end

local function SkinRecipientRing(f)
	local overlay, portrait, corner = RecipientParts(f)
	if not (overlay and portrait and corner) then
		return
	end
	local ring = Replace(corner, { as = "UI-Frame-PortraitMetal-CornerTopLeft", parent = overlay, center = portrait })
	if not ring then
		return
	end
	skin.recipientRing = ring
	ring.onEnable = function()
		pcall(Kit.FitPortrait, Kit, portrait, ring)
	end
	ring.onDisable = function()
		pcall(Kit.UnfitPortrait, Kit, portrait)
	end
	-- a region of the overlay, BACKGROUND under its ARTWORK portrait; never
	-- part of the overlay's layout (a ResizeLayoutFrame)
	local disc = Kit:RingDisc(ring, nil, overlay, 0)
	if disc then
		disc.ignoreInLayout = true
	end
	if active then
		ring.onEnable(ring)
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
	if active then
		ring.onEnable(ring)
	end
end

--------------------------------------------------------------------------------
-- The title (WINDOW-RULES 2c: the title ON the plate, in the title face).
-- This window's title container stays empty: its title is the two players'
-- names, TradeFramePlayerNameText / TradeFrameRecipientNameText, strings of an
-- unnamed HIGH strata frame on the title band. Both are laid ON the plate in
-- Kit:TitleFont (which follows the Fonts options and the Font Style): each
-- centred on the plate's painted box, the player's between the right of the
-- player's ring and the left of the other player's, the other player's
-- between the right of their ring and the window's right edge (read from the
-- rings as laid out, the XML's places until then). Their size and text stay
-- the game's; their points and font are put back on disable.
--------------------------------------------------------------------------------
local FALLBACK_X = { player = { 66, 158 }, recipient = { 242, 344 } }   -- the rings' edges and the window's width in the XML's layout

local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
	end
end

-- a region's left / right edge in UI px right of the window's left edge
-- (nil while not laid out or secret)
local function EdgeX(region, edge, f)
	if not (region and f) then
		return nil
	end
	local ok, x, left, rs, ws = pcall(function()
		return (edge == "left" and region:GetLeft() or region:GetRight()), f:GetLeft(), region:GetEffectiveScale(), f:GetEffectiveScale()
	end)
	if not (ok and x and left and rs and ws) or Secret(x) or Secret(left) or Secret(rs) or Secret(ws) or ws == 0 then
		return nil
	end
	return x * rs / ws - left
end

local function WindowWidth(f)
	local ok, w = pcall(f.GetWidth, f)
	if ok and w and not Secret(w) and w > 0 then
		return w
	end
	return nil
end

-- the plate's painted box: how far above the strip's centre line its middle is
local function PlateDy(strip)
	local p = Kit:Piece(Kit:StripPieceName(strip.base, "mid", strip.state))
	if p and p.box then
		return (p.h / 2 - (p.box[2] + p.box[4]) / 2) * (strip.scale or Kit.scale)
	end
	return 0
end

local function PlaceNames()
	local rep = TitleRep()
	local f = Window()
	if not (active and f and rep and rep.strip and rep.object and rep.object:IsShown()) then
		return
	end
	local lift = Kit:TitleOnRail(rep.strip)
	local y = lift + PlateDy(rep.strip)
	local ringR = skin.ring and skin.ring.tex
	local recR = skin.recipientRing and skin.recipientRing.tex
	local bounds = {
		player = { EdgeX(ringR, "right", f) or FALLBACK_X.player[1], EdgeX(recR, "left", f) or FALLBACK_X.player[2] },
		recipient = { EdgeX(recR, "right", f) or FALLBACK_X.recipient[1], WindowWidth(f) or FALLBACK_X.recipient[2] },
	}
	for _, entry in ipairs(names) do
		local b = bounds[entry.side]
		local fs = entry.fs
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", f, "TOPLEFT", (b[1] + b[2]) / 2, y)
		if not fs.melloFontSaved then
			Kit:TitleFont(fs, true)
		end
	end
end

local function RestoreNames()
	for _, entry in ipairs(names) do
		local fs = entry.fs
		Kit:TitleFont(fs, false)
		if entry.points and #entry.points > 0 then
			fs:ClearAllPoints()
			for _, pt in ipairs(entry.points) do
				fs:SetPoint(unpack(pt))
			end
		end
	end
end

local function CollectNames()
	for _, side in ipairs(SIDES) do
		local fs = _G[side.name]
		if fs and not done[fs] then
			done[fs] = true
			local points = {}
			local okN, n = pcall(fs.GetNumPoints, fs)
			if okN and n and not Secret(n) then
				for i = 1, n do
					points[i] = { fs:GetPoint(i) }
				end
			end
			names[#names + 1] = { fs = fs, points = points, side = side.key }
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
	PlaceNames()
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

	-- the other player's ring first (see above), then the shell: outer rail,
	-- one page stone, the player's ring, the title plate on the rail, the
	-- close button
	SkinRecipientRing(f)
	local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = Portrait(f), bg = "UI-Background-Rock" })
	SkinPortrait(f, ring)
	CollectNames()

	-- the big inset faded, the other side's white wash with it (its list box
	-- is the dark panel now), then each side's boxes and rows
	for _, region in ipairs(InsetArt(f.Inset or _G.TradeFrameInset)) do
		FadeArt(region)
	end
	FadeArt(_G.TradeRecipientBG)
	for _, side in ipairs(SIDES) do
		SkinListBox(f, _G[side.list], side.key, "items")
		SkinListBox(f, _G[side.enchant], side.key, "enchant")
		for i = 1, ITEMS do
			SkinItem(_G[side.items .. i])
		end
	end
	SkinDivider(f)
	SkinMoney(f)
	SkinButtons()
end

-- After every show and every game refresh: what the game re-laid or
-- re-showed since (the portraits, the plate and the names, the cards' tints,
-- the rims' states, the boxes' levels).
local function Refresh()
	local f = Window()
	if not (active and skin and f) then
		return
	end
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	for _, box in ipairs(insets) do
		KeepUnder(f, box.inset)
	end
	for _, entry in ipairs(cards) do
		ReadTint(entry)
	end
	for _, entry in ipairs(rims) do
		FitIconRim(entry)
		UpdateRim(entry)
	end
	FitPortraits()
	PlaceTitle()
	-- once laid out (a frame after it shows): the portraits, the title and
	-- the rims again -- one pass pending at a time
	if skin.laterPending then
		return
	end
	skin.laterPending = true
	C_Timer.After(0, function()
		skin.laterPending = nil
		if active and f:IsShown() then
			FitPortraits()
			PlaceTitle()
			for _, entry in ipairs(rims) do
				FitIconRim(entry)
			end
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
	-- (the rings' onDisable put the portraits back, the title plate its own
	-- string; the names are ours to put back)
	RestoreNames()
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
	if Kit.WhenOutOfCombat then
		Kit:WhenOutOfCombat(Sync)
	else
		Sync()
	end
end

-- The module switch and a dressed window go through SyncSafe, as always; the
-- first dress runs at once, in combat too, so the first frame the window
-- draws is already dressed. The dress makes frames and textures of our own
-- and moves only the game's textures and strings (the portraits, the two
-- names), never a protected frame -- the item buttons are never moved, the
-- forbidden money input is never reached: nothing in it is refused in combat.
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
	-- the game's own refresh (both portraits, both names, every row: on
	-- TRADE_SHOW / TRADE_UPDATE)
	if type(_G.TradeFrame_Update) == "function" then
		hooksecurefunc("TradeFrame_Update", Refresh)
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
-- /tradedump [frames | reps | regions]: with no mode, what the skin found and
-- dressed (every part, found or not, and its state: the shell, the portraits
-- against the medallion, the names on the plate and their font, the boxes,
-- every row, the divider, the money, the buttons) and the window's own
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
	local ok, d = pcall(function() return obj:GetDebugName() end)
	if ok and type(d) == "string" and not Secret(d) then
		return d
	end
	return "[unnamed]"
end

local function Found(label, obj, more)
	MelloUI:Print("  %-28s %s%s", label, obj and Label(obj) or "-- not found", more or "")
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

local function Text(fs)
	local ok, t = pcall(fs.GetText, fs)
	return (ok and type(t) == "string" and not Secret(t)) and t or "?"
end

local function Face(fs)
	local ok, face, size = pcall(fs.GetFont, fs)
	if ok and type(face) == "string" and not Secret(face) then
		return string.format("%s %s", face:match("([^\\/]+)$") or face, Num(size))
	end
	return "?"
end

-- a region's rect relative to the window's top-left corner
local function RelRect(region, f)
	local l, r = EdgeX(region, "left", f), EdgeX(region, "right", f)
	local ok, top, ftop, rs, ws = pcall(function() return region:GetTop(), f:GetTop(), region:GetEffectiveScale(), f:GetEffectiveScale() end)
	if not (l and r and ok and top and ftop and rs and ws) or Secret(top) or Secret(ftop) or Secret(rs) or Secret(ws) or ws == 0 then
		return "(not laid out)"
	end
	return string.format("x %.0f..%.0f, top %.0f", l, r, top * rs / ws - ftop)
end

local function DumpPortrait(label, portrait, ring, f)
	if not portrait then
		Found(label, nil)
		return
	end
	local okT, file = pcall(portrait.GetTexture, portrait)
	local okS, w, h = pcall(portrait.GetSize, portrait)
	local rw
	if ring and ring.tex then
		local okW, v = pcall(ring.tex.GetWidth, ring.tex)
		rw = okW and v or nil
	end
	local medallion = (type(rw) == "number" and not Secret(rw)) and rw * 0.759 or nil
	Found(label, portrait, string.format(" file %s, size %s x %s, medallion %s, fitted %s, ring %s (%s), disc %s",
		(okT and not Secret(file)) and tostring(file) or "?", okS and Num(w) or "?", okS and Num(h) or "?",
		medallion and string.format("%.0f", medallion) or "?", tostring(portrait.melloSaved ~= nil),
		ring and "kit" or "none", (ring and ring.tex) and RelRect(ring.tex, f) or "-", tostring(ring ~= nil and ring.disc ~= nil)))
end

local function DumpShell(f)
	local okLv, lv = pcall(f.GetFrameLevel, f)
	MelloUI:Print("TradeFrame: shown %s, level %s, kit %s, reps %d, followers %d, faded art %d", Shown(f),
		okLv and Num(lv) or "?", active and "on" or "off", skin and #skin.reps or 0, skin and #skin.followers or 0, #fadedArt)
	Found("outer rail (NineSlice)", f.NineSlice, f.NineSlice and (" layout " .. tostring(f.NineSlice.layoutType)) or " (an older frame: no shell)")
	Found("page stone (Bg)", f.Bg, f.Bg and (" " .. FadedState(f.Bg)) or nil)
	local page
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "UI-Background-Rock" then
			page = rep
		end
	end
	local pageRect = page and (page.inner or page.object)
	Found("page picture", pageRect, pageRect and (" " .. RelRect(pageRect, f) .. ", shown " .. Shown(page.object)) or nil)
	DumpPortrait("player portrait", Portrait(f), skin and skin.ring, f)
	local _, rp = RecipientParts(f)
	DumpPortrait("other player's portrait", rp, skin and skin.recipientRing, f)
	local rep = TitleRep()
	Found("title plate", rep and rep.object, rep and (" shown " .. Shown(rep.object) .. ", " .. RelRect(rep.object, f)) or nil)
	local tt = f.TitleContainer and f.TitleContainer.TitleText
	Found("title container text", tt, tt and (" '" .. Text(tt) .. "' (this window's title is the two names)") or nil)
	for _, side in ipairs(SIDES) do
		local fs = _G[side.name]
		Found(side.key .. " name", fs, fs and string.format(" '%s', %s, face %s, title face %s", Text(fs), RelRect(fs, f), Face(fs),
			tostring(fs.melloFontSaved ~= nil)) or nil)
	end
end

local function DumpParts(f)
	local main = f.Inset or _G.TradeFrameInset
	Found("big inset (faded)", main, main and (" art " .. FadedState(main.Bg) .. ", shown " .. Shown(main)) or nil)
	Found("other side's wash", _G.TradeRecipientBG, _G.TradeRecipientBG and (" " .. FadedState(_G.TradeRecipientBG)) or nil)
	for _, side in ipairs(SIDES) do
		for _, key in ipairs({ "list", "enchant" }) do
			local inset = _G[side[key]]
			Found(side.key .. " " .. key .. " box", inset, inset and string.format(" dressed %s, dim %s", Dressed(inset),
				tostring(inset.melloRep and inset.melloRep.skin and inset.melloRep.skin.dimFill ~= nil)) or nil)
		end
		for i = 1, ITEMS do
			local item = _G[side.items .. i]
			local card
			for _, entry in ipairs(cards) do
				if entry.item == item then
					card = entry
				end
			end
			local button = Part(item, "ItemButton", "ItemButton")
			local qb = button and button.IconBorder
			Found(side.key .. " row " .. i, item, item and string.format(" rim %s, card %s%s, square %s, quality border %s",
				Dressed(button), tostring(card ~= nil), card and (card.red and " (red: unusable)" or " (plain)") or "",
				FadedState(Part(item, "SlotTexture", "SlotTexture")), qb and ("shown " .. Shown(qb)) or "none") or nil)
		end
		local label = _G[side.label]
		Found(side.key .. " enchant label", label, label and (" '" .. Text(label) .. "'") or nil)
		MelloUI:Print("  %-28s %s", side.key .. " money", moneyNotes[side.key] or "not dressed")
	end
	Found("divider", _G.TradeRecipientLeftBorder, (skin and skin.divider) and (" -> pane divider, shown " .. Shown(skin.divider.object)) or " (not dressed)")
	Found("player money input", _G.TradePlayerInputMoneyFrame, " reachable " .. tostring(Reachable(_G.TradePlayerInputMoneyFrame)))
	Found("other player's money", _G.TradeRecipientMoneyFrame)
	for _, bname in ipairs({ "TradeFrameTradeButton", "TradeFrameCancelButton" }) do
		local b = _G[bname]
		local okE, enabled = false, nil
		if b then
			okE, enabled = pcall(b.IsEnabled, b)
		end
		Found("button", b, b and string.format(" red plate %s, enabled %s", Dressed(b), (okE and not Secret(enabled)) and tostring(enabled) or "?") or nil)
	end
	for _, hname in ipairs({ "TradeHighlightPlayer", "TradeHighlightRecipient", "TradeHighlightPlayerEnchant", "TradeHighlightRecipientEnchant" }) do
		Found("acceptance glow (game's)", _G[hname], _G[hname] and (" shown " .. Shown(_G[hname])) or nil)
	end
	MelloUI:Print("  tabs: none on this window (one page, one page picture: above)")
	MelloUI:Print("  inked strings: none (no parchment on this window)")
	MelloUI:Print("  rims %d, cards %d, list boxes %d, coin plates %d, edit plates %d, red plates %d",
		stats.items, stats.cards, stats.insets, stats.plates, stats.edits, stats.buttons)
end

local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "")
		elseif kind == "FontString" then
			art = "text: " .. Text(region):sub(1, 40)
		end
		local okA, alpha = pcall(region.GetAlpha, region)
		MelloUI:Print("  region %s %s %s %s alpha %s shown %s", kind, Label(region), okL and tostring(layer) or "?", art,
			(okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?", Shown(region))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		-- (a forbidden child -- the player's money input -- answers nothing)
		local ok = pcall(function()
			local okLv, lv = pcall(child.GetFrameLevel, child)
			MelloUI:Print("  child %s %s level %s shown %s%s", tostring(child:GetObjectType()), Label(child),
				okLv and Num(lv) or "?", Shown(child), child.melloRep ~= nil and " (dressed)" or "")
		end)
		if not ok then
			MelloUI:Print("  child [forbidden to addons]")
		end
	end
end

SLASH_MELLOTRADEDUMP1 = "/tradedump"
SlashCmdList.MELLOTRADEDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if f and not Built() then
		-- (dressed on its first open: until then the game's window as it is)
		MelloUI:Print("/tradedump: TradeFrame is not dressed yet (%s)", M.isEnabled
			and "the kit dresses it the first time it opens this session: open a trade, then try again" or "the Trade Kit is off")
	end
	if not f then
		MelloUI:Print("/tradedump: no TradeFrame: not on this client (the module does nothing)")
	elseif msg == "" then
		DumpShell(f)
		DumpParts(f)
		MelloUI:Print("TradeFrame's own regions and children:")
		DumpOwn(f)
	else
		-- frames / reps / regions (the visible game textures): the Kit's dump
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	end
	MelloUI:ShowLog("tradedump " .. msg)
end
