--------------------------------------------------------------------------------
-- MelloUI - Loot Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): the loot window (LootFrame) and the group loot rolls
-- (GroupLootFrame1..4) in the painted kit (Modules/Kit.lua), on the game's
-- own layout (docs/WINDOW-RULES.md): every kit piece stands in for one of the
-- game's art regions, the game's art faded in its place.
--
-- The loot window (Blizzard_UIPanels_Game, Mainline/LootFrame.xml on this
-- client: a ScrollingFlatPanelTemplate -- a flat window with no portrait, a
-- scrolling list of item cards; an older client's window with fixed
-- LootButton1..4 and page arrows is handled the same way where it has them):
--   the window shell     outer double rail with gem corners (no ring: the
--                        window has no portrait), the page stone on the flat
--                        background, the title plate on the rail with the
--                        title ("Items") ON it in the title face (2c), the
--                        close button
--   the list             the whole page is the list: the palette's inner
--                        panel over the page stone inside the outer rail
--                        (2e); an older window's inset is the list box L1
--   the item cards       each card's picture (looting_itemcard_bg, tinted by
--                        the item's quality) and its stroke -> a card in the
--                        main window's tone (2e's row stripe); the game's
--                        hover / click strokes and the rarity tag stay
--   the item buttons     the Button Border rim hugging the icon, the quality
--                        border kept on the icon; the buttons are the game's
--                        loot slots: nothing of theirs is moved, resized or
--                        re-scripted, the rim is our own texture
--   the scroll bar       T2 / H1 / S1 (Kit:SkinScrollBar)
--   page arrows          (an older window) buttons/arrow_left / _right
--
-- The roll frames (GroupLootFrameN, a DefaultDialogPanelTemplate toast: the
-- LootToast background and border, the item's icon, its name, the Need /
-- Greed / Pass / Transmog (/ Disenchant) buttons, the timer bar):
--   the box              the single rail with its stone round the toast, as
--                        the dialogs' popups (DialogPanel), on the game's
--                        border's rect; the stone under the palette's inner
--                        panel (2e: the name is text); the toast art faded
--   the item icon        the Button Border rim round the icon, tinted with
--                        the item's quality colour (the colour the game gives
--                        the toast's border and the name); the game's quality
--                        ring round the icon faded (the rim is that ring)
--   the timer            the Progress Bar Border's bracket (P1, the look every
--                        progress bar follows) with the caps outside, the bar
--                        set in by the arms; its black backing faded (the
--                        bracket's trough stands in)
--   the roll buttons     their icons kept (the dice, the coin, the cross are
--                        the buttons' own pictures): the kit's cog plate K2
--                        under each, as a button whose glyph is its plate;
--                        their disabled look (the game's 0.35 alpha and grey)
--                        is kept, the plate fading with the button
--
-- Taint: loot slots and roll buttons are the game's to click: no SetScript,
-- no move, no resize, no loot or roll call; only textures and frames of our
-- own are added and the game's art faded. Hooks are post-hooks (HookScript,
-- hooksecurefunc on regions and the scroll box's callbacks); what is kept
-- about the game's frames lives in weak side tables (the kit's melloRep /
-- melloNoInk markers aside). Switching the module off disables every
-- replacement and puts the moved timer back: the windows are the game's.
--
-- /lootdump [roll [n] | frames | reps | regions]: what the windows are made
-- of on this client and what the skin dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("LootPanel")
local hooksecurefunc = Perf.hooksecurefunc
-- a handler made once and run for many asks, wrapped once: its time stays
-- on this file's own /melloperf row (review, 2026-09-24)
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("LootPanel", {
	title = "Loot Kit",
	desc = "The loot window and the group loot rolls in the kit.",
	window = { label = "Loot windows", desc = "The loot window and the group loot rolls in the kit.", tab = "Windows" },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local CARD_ALPHA = 0.85     -- WINDOW-RULES 2e: rows striped in the main window tone at about 0.85
local PANEL_ALPHA = 0.8     -- WINDOW-RULES 2e: the inner panel over the stone
local OLD_BUTTONS = 8       -- an older window's LootButton1..N (4 on the classic window; looked for up to this)
local ROLL_FRAMES = 4       -- GroupLootFrame1..4 (NUM_GROUP_LOOT_FRAMES)
local ROLL_KEYS = { "NeedButton", "GreedButton", "PassButton", "TransmogButton", "DisenchantButton" }

local skin = nil            -- the loot window's { reps, followers, layout, page, panel, close, scrollBar, arrows }
local rollSkin = nil        -- the roll frames' { reps }
local active = false
local hooked = false

-- what this module made or looked at, kept OFF the game's frames (weak keys)
local done = setmetatable({}, { __mode = "k" })         -- [frame / region] = true: looked at once
local rolls = setmetatable({}, { __mode = "k" })        -- [roll frame] = { nine, dim, rim, timer, buttons, faded }
local insetBars = setmetatable({}, { __mode = "k" })    -- [timer] = its game anchors while the bracket sets it in
local cards = {}                                        -- { tex, source, host }
local rims = {}                                         -- item rims { rep, icon, button, tint (roll frame) }
local fadedArt = {}                                     -- game art faded with no piece of its own on its rect
local arrows = {}                                       -- { rep, button }
local stats = { rows = 0, cards = 0, rims = 0, rolls = 0, rollButtons = 0 }

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

-- A replacement the library knows, registered in `into` (the window's skin or
-- the rolls') so enable / disable reach it.
local function ReplaceInto(into, region, opts)
	if not (region and into) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Loot kit: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	into.reps[#into.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

local function Replace(region, opts)
	return ReplaceInto(skin, region, opts)
end

local function RollReplace(region, opts)
	return ReplaceInto(rollSkin, region, opts)
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

-- every game texture of a frame (its own regions, ours skipped)
local function Textures(frame)
	local list = {}
	if not (frame and frame.GetRegions) then
		return list
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece then
			list[#list + 1] = region
		end
	end
	return list
end

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
	return _G.LootFrame
end

-- the modern scrolling list, or the older fixed buttons
local function Layout(f)
	if f and f.ScrollBox then
		return "scroll"
	elseif _G.LootButton1 then
		return "buttons"
	end
	return "unknown"
end

--------------------------------------------------------------------------------
-- The item cards (WINDOW-RULES 2e). A modern card (LootFrameElementTemplate,
-- 46 px) is painted by its NameFrame (looting_itemcard_bg, which the game
-- tints with the item's quality) under its BorderFrame stroke; an older
-- button's name sits on its NameFrame plate. The card stands in for both: a
-- texture of the card's own frame (or the old button's, on its plate's rect)
-- in BACKGROUND under the name, in the palette's main window tone -- a stripe
-- a step lighter than the inner panel round it. The item's quality stays on
-- its name's colour and on the icon's border.
--------------------------------------------------------------------------------
local function SkinCard(host, plate, rect, extra)
	if not (host and plate and host.CreateTexture) or done[plate] then
		return
	end
	local tex = host:CreateTexture(nil, "BACKGROUND", nil, -2)
	tex.kitPiece = true   -- ours: never faded as the game's art
	tex:SetAllPoints(rect or host)
	local P = MelloUI.Palette
	local c = P and P.mainWindow or { 0.12, 0.11, 0.09 }
	tex:SetColorTexture(c[1], c[2], c[3], CARD_ALPHA)
	tex:SetShown(active)
	cards[#cards + 1] = { tex = tex, source = plate, host = host }
	-- faded while the card stands in (Kit:Fade re-fades after each
	-- SetVertexColor: the game re-tints the picture on every row's Init)
	FadeArt(plate)
	for _, obj in ipairs(extra or {}) do
		FadeArt(obj)
	end
	stats.cards = stats.cards + 1
end

--------------------------------------------------------------------------------
-- The item icons: every window's Button Border rim round the icon, its inner
-- edge 2 px over the icon's (the merchant's tool buttons' recipe), a texture
-- of our own on the button; the button's normal, pushed and highlight squares
-- faded (the rim carries hover and press). The game's quality border stays on
-- the icon inside the rim's opening; a roll frame's quality ring (a separate
-- 42 px atlas round its icon) is faded and the rim takes its colour instead.
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
		ok, iw, ih = pcall(entry.button.GetSize, entry.button)
	end
	if not (p and l and ok and iw and ih) or Secret(iw) or Secret(ih) or iw <= 0 or ih <= 0 then
		return
	end
	rim:ClearAllPoints()
	rim:SetPoint("CENTER", icon, "CENTER")
	rim:SetSize((iw - 4) * p.w / (p.w - l - r), (ih - 4) * p.h / (p.h - t - b))
end

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

-- the rim's colour: the item's quality (a roll frame's), white otherwise
local function TintRim(entry)
	local rim = entry.rep and entry.rep.object
	if not (rim and rim.SetVertexColor) then
		return
	end
	local c = entry.tint or { 1, 1, 1 }
	rim:SetVertexColor(c[1], c[2], c[3])
end

local function SkinRim(replace, button, icon, extraFade)
	if not (button and icon) or done[button] or button.melloRep ~= nil then
		return nil
	end
	done[button] = true
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	local extra = List(button.GetPushedTexture and button:GetPushedTexture(), button.GetHighlightTexture and button:GetHighlightTexture())
	for _, obj in ipairs(extraFade or {}) do
		extra[#extra + 1] = obj
	end
	-- the rim stands in for the normal square; without one the icon is only
	-- the rect it is keyed on, and it is not faded
	local rep = replace(normal or icon, { as = Kit:ButtonRimRule(), button = button, parent = button, rect = icon,
		noFade = normal == nil, alsoFade = extra })
	button.melloRep = rep or false   -- the Kit's own "dressed" marker
	if not rep then
		return nil
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
	stats.rims = stats.rims + 1
	return entry
end

--------------------------------------------------------------------------------
-- The loot window's rows. Modern: the scroll box's element frames, pooled
-- (Kit:HookScrollBoxRows: each once, as it is acquired while the kit is on,
-- and the ones already there when it is switched on); a coin or empty
-- element (LootFrameBaseElementTemplate) has no card. Older: LootButton1..N.
--------------------------------------------------------------------------------
local function SkinRow(row)
	if not row or done[row] then
		return
	end
	done[row] = true
	if not row.Item then
		return
	end
	SkinCard(row, row.NameFrame, row, List(row.BorderFrame))
	SkinRim(Replace, row.Item, row.Item.icon or row.Item.Icon)
	stats.rows = stats.rows + 1
end

local function SkinOldButtons()
	for i = 1, OLD_BUTTONS do
		local b = _G["LootButton" .. i]
		if b and not done[b] then
			local plate = Part(b, "NameFrame", "NameFrame")
			if plate then
				SkinCard(b, plate, plate)
			end
			SkinRim(Replace, b, b.icon or b.Icon or Part(b, nil, "IconTexture"))
			stats.rows = stats.rows + 1
		end
	end
end

-- An older window's page arrows (LootFrameUpButton / DownButton: the spell
-- book's PrevPage / NextPage file art): the kit's arrows at the button's
-- height by that art's rule, the button's other textures faded, a disabled
-- arrow at a lower alpha, read again after the game's Enable / Disable.
local ARROWS = { { "LootFrameUpButton", "UI-SpellbookIcon-PrevPage-Up" }, { "LootFrameDownButton", "UI-SpellbookIcon-NextPage-Up" },
	{ "LootFramePrevPageButton", "UI-SpellbookIcon-PrevPage-Up" }, { "LootFrameNextPageButton", "UI-SpellbookIcon-NextPage-Up" } }

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
				arrows[#arrows + 1] = entry
				for _, method in ipairs({ "Enable", "Disable", "SetEnabled" }) do
					if b[method] then
						hooksecurefunc(b, method, function()
							ArrowLook(entry)
						end)
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The loot window's shell. A modern window (DefaultPanelFlatTemplate): its
-- NineSlice -> the outer rail with its body OFF (one background per window);
-- its flat background (FlatPanelBackgroundTemplate, a frame at level 0) ->
-- the page stone as a region of it, inside the outer rail's bevel, its other
-- pieces faded (the options panel's recipe); the title container -> the
-- title plate with the title on it; ClosePanelButton -> the close states. An
-- older ButtonFrameTemplate window: the shell as every such window, the
-- ring on its portrait at the medallion size on the disc (2b).
--
-- No eye strain (2e): the whole page is a list of names. On the modern window
-- the palette's inner panel lies over the page stone inside the outer rail
-- (a region of the flat background above the stone, so it comes and goes with
-- the skin); an older window's inset is the list box L1 (single rail, stone,
-- the inner panel: the inset rule's `dim`).
--------------------------------------------------------------------------------
local function Portrait(f)
	local pc = f and f.PortraitContainer
	return (pc and pc.portrait) or (f and f.portrait) or _G.LootFramePortrait
end

local function PanelShown()
	if skin and skin.panel then
		skin.panel:SetShown(active)
	end
end

local function SkinPage(f)
	local bg = f.Bg
	if not bg then
		return
	end
	if IsTexture(bg) then
		skin.page = Replace(bg, { as = "UI-Background-Rock", parent = f, rect = f, inset = Kit:OuterRailInset() })
		return
	end
	local art = Textures(bg)
	local first = table.remove(art, 1)
	if not first then
		return
	end
	skin.page = Replace(first, { as = "UI-Background-Rock", parent = bg, rect = f, inset = Kit:OuterRailInset(), alsoFade = art })
	-- the inner panel over the stone (BACKGROUND 7: above the picture, which
	-- takes the replaced piece's sublevel; the list's frames are above the
	-- flat background's level 0)
	local ins = Kit:OuterRailInset()
	local panel = bg:CreateTexture(nil, "BACKGROUND", nil, 7)
	panel.kitPiece = true
	panel:SetPoint("TOPLEFT", f, "TOPLEFT", ins[1], -ins[3])
	panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ins[2], ins[4])
	local c = MelloUI.Palette.innerPanel
	panel:SetColorTexture(c[1], c[2], c[3], PANEL_ALPHA)
	skin.panel = panel
	PanelShown()
end

local function SkinClose(f)
	local close = f.ClosePanelButton or (not f.CloseButton and _G.LootFrameCloseButton) or nil
	local normal = close and close.GetNormalTexture and close:GetNormalTexture()
	if normal and not done[close] then
		done[close] = true
		skin.close = Replace(normal, { as = "RedButton-Exit", button = close, alsoFade = Kit:OtherTextures(close, normal) })
	end
end

local function SkinWindow(f)
	local portrait = Portrait(f)
	local hasRing = portrait ~= nil and f.NineSlice ~= nil and f.NineSlice.TopLeftCorner ~= nil
	local flatBg = f.Bg and not IsTexture(f.Bg)
	local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = portrait, noRing = not hasRing, body = false,
		bg = (not flatBg and f.Bg) and "UI-Background-Rock" or nil })
	if ring and portrait then
		skin.ring = ring
		ring.onEnable = function()
			pcall(Kit.FitPortrait, Kit, portrait, ring)
		end
		ring.onDisable = function()
			pcall(Kit.UnfitPortrait, Kit, portrait)
		end
		Kit:RingDisc(ring, nil, f.PortraitContainer or ring.object:GetParent(), 0)
		if active then
			ring.onEnable(ring)
		end
	end
	if flatBg then
		SkinPage(f)
	end
	SkinClose(f)
	-- an older window's list box
	local inset = f.Inset or _G.LootFrameInset
	if inset and not done[inset] then
		done[inset] = true
		Kit:SkinInset(inset, Replace, f, true)
	end
	-- the scroll bar (T2 / H1 / S1)
	if f.ScrollBar and f.ScrollBar.Track then
		skin.scrollBar = Kit:SkinScrollBar(f.ScrollBar, Replace)
	end
end

local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
	end
end

-- An older window's title string (no title container): the plate's
-- TitleText is the one the plate centres; nothing else to find
local function TitleText(f)
	local tc = f and f.TitleContainer
	return (tc and tc.TitleText) or _G.LootFrameTitleText
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

local function BuildWindow()
	local f = Window()
	if not f then
		return
	end
	skin = skin or { reps = {}, followers = {} }
	if skin.built then
		return
	end
	skin.built = true
	skin.layout = Layout(f)
	SkinWindow(f)
	if skin.layout == "scroll" then
		Kit:HookScrollBoxRows(f.ScrollBox, SkinRow, function()
			return active
		end)
	elseif skin.layout == "buttons" then
		SkinOldButtons()
		SkinArrows()
	end
end

-- the rows already in the list (switched on with the window open, or rows
-- acquired while the kit was off)
local function SkinExistingRows()
	local f = Window()
	local box = f and f.ScrollBox
	if box and box.ForEachFrame then
		box:ForEachFrame(function(row)
			SkinRow(row)
		end)
	end
end

-- RefreshWindow's pass a frame later, once the window is laid out (made
-- once: Kit:NextFrame runs it once however often it was asked -- audit,
-- 2026-09-24; timed on this window's own /melloperf row, not the Kit's
-- timer -- review)
local RefreshWindowLater = Shared("RefreshWindow a frame later", function()
	local f = Window()
	if active and f and f:IsShown() then
		PlaceTitle()
		for _, entry in ipairs(rims) do
			FitIconRim(entry)
		end
	end
end, "timer")

local function RefreshWindow()
	local f = Window()
	if not (active and skin and f) then
		return
	end
	if skin.layout == "scroll" then
		SkinExistingRows()
	end
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	for _, entry in ipairs(arrows) do
		ArrowLook(entry)
	end
	if skin.ring then
		pcall(Kit.FitPortrait, Kit, Portrait(f), skin.ring)
	end
	PlaceTitle()
	Kit:NextFrame(skin, RefreshWindowLater)
end

--------------------------------------------------------------------------------
-- The roll frames. Each is dressed once, the first time the kit sees it (at
-- switch-on, all four exist from load):
--   the box: a nine-slice of the single rail with its stone (Kit:NineSlice,
--     as the dialogs' popups) on the rect of the game's Border art (286 x 76
--     round the 277 x 67 toast: the border it replaces is drawn there), its
--     frame TWO levels under the toast: the game puts its Timer one level
--     under the toast (SetupItemDisplay, on every show) and the timer must
--     stay over our stone; the palette's inner panel on the stone (Kit:
--     StoneDim with no area: always, there is no parchment for these); the
--     toast's Background and Border faded
--   the icon: the rim (above), tinted with the quality colour the game puts
--     on the toast's Border (post-hook on its SetVertexColor)
--   the timer: P1 with the caps outside (the tooltip bar's rule: a
--     StatusBar with no border art of its own), its Background faded, the bar
--     set in from its anchors by the caps' arms (the tooltip panel's recipe)
--     and put back on disable
--   the buttons: K2 under each icon, the icon kept
--------------------------------------------------------------------------------
local function RollFrames()
	local list = {}
	local n = tonumber(_G.NUM_GROUP_LOOT_FRAMES) or ROLL_FRAMES
	for i = 1, n do
		local f = _G["GroupLootFrame" .. i]
		if f and f.GetChildren then
			list[#list + 1] = f
		end
	end
	return list
end

local function RollButtons(f)
	local list, seen = {}, {}
	local c = f.LootButtonContainer
	local function Add(b)
		if b and not seen[b] and b.GetNormalTexture then
			seen[b] = true
			list[#list + 1] = b
		end
	end
	for _, key in ipairs(ROLL_KEYS) do
		Add(c and c[key])
		Add(f[key])
		Add(Part(f, nil, key))
	end
	for _, b in ipairs((c and c.LootButtons) or f.LootButtons or {}) do
		Add(b)
	end
	return list
end

local function InsetBar(bar, rep)
	if not (bar and rep and rep.GetArms) or insetBars[bar] then
		return
	end
	local okN, n = pcall(bar.GetNumPoints, bar)
	if not okN or Secret(n) or not n then
		return
	end
	local points = {}
	for i = 1, n do
		local ok, point, rel, relPoint, x, y = pcall(bar.GetPoint, bar, i)
		if not ok or Secret(point) or Secret(x) or Secret(y) or not point then
			return
		end
		points[i] = { point, rel, relPoint, x or 0, y or 0 }
	end
	insetBars[bar] = points
	local armL, armR = rep:GetArms()
	bar:ClearAllPoints()
	for _, pt in ipairs(points) do
		local point, rel, relPoint, x, y = unpack(pt)
		if point:find("LEFT") then
			x = x + armL
		elseif point:find("RIGHT") then
			x = x - armR
		end
		bar:SetPoint(point, rel, relPoint, x, y)
	end
end

local function RestoreBar(bar)
	local points = bar and insetBars[bar]
	if not points then
		return
	end
	insetBars[bar] = nil
	bar:ClearAllPoints()
	for _, pt in ipairs(points) do
		bar:SetPoint(unpack(pt))
	end
end

-- the box two levels under the toast, the timer over it (the game resets the
-- timer to the toast's level - 1 on every show; at a toast level too low for
-- that, the timer goes one over the box and back to the game's on disable)
local function RollLevels(f, r)
	local okF, fl = pcall(f.GetFrameLevel, f)
	if not okF or Secret(fl) or not fl then
		return
	end
	r.nine:SetFrameLevel(math.max(fl - 2, 0))
	local timer = f.Timer
	if timer then
		local okT, tl = pcall(timer.GetFrameLevel, timer)
		if okT and tl and not Secret(tl) and tl <= r.nine:GetFrameLevel() then
			r.timerLevel = r.timerLevel or tl
			timer:SetFrameLevel(r.nine:GetFrameLevel() + 1)
		end
	end
end

local function ReadQuality(f, r)
	local src = f.Border
	if not (src and src.GetVertexColor and r.rim) then
		return
	end
	local ok, cr, cg, cb = pcall(src.GetVertexColor, src)
	if ok and type(cr) == "number" and not (Secret(cr) or Secret(cg) or Secret(cb)) then
		r.rim.tint = { cr, cg, cb }
	end
	TintRim(r.rim)
end

local function DressRoll(f)
	if rolls[f] or not (Kit and Kit.NineSlice) then
		return rolls[f]
	end
	local ok, nine = pcall(Kit.NineSlice, Kit, f, { prefix = Kit.framePrefix, scale = Kit.scale * (Kit.frameScale or 1.6),
		gems = false, body = true, level = -2 })
	if not (ok and nine) then
		return nil
	end
	if f.Border then
		nine:ClearAllPoints()
		nine:SetAllPoints(f.Border)
	end
	local dim = Kit.StoneDim and Kit:StoneDim(nine, { alpha = PANEL_ALPHA })
	local r = { nine = nine, dim = dim, buttons = {}, faded = List(f.Background, f.Border) }
	rolls[f] = r
	-- the item's icon
	local iconFrame = f.IconFrame
	local icon = iconFrame and (iconFrame.Icon or iconFrame.icon)
	if iconFrame and icon then
		r.rim = SkinRim(RollReplace, iconFrame, icon, List(iconFrame.Border))
		if r.rim and f.Border then
			hooksecurefunc(f.Border, "SetVertexColor", function(_, cr, cg, cb)
				if type(cr) == "number" and not (Secret(cr) or Secret(cg) or Secret(cb)) then
					r.rim.tint = { cr, cg, cb }
					if active then
						TintRim(r.rim)
					end
				end
			end)
		end
	end
	-- the timer
	local timer = f.Timer
	if timer and timer.GetStatusBarTexture then
		local layer, sublevel, troughLayer, troughSub = Kit:BracketLayers(timer)
		local rep = RollReplace(timer, { as = "TooltipStatusBar", parent = timer, rect = timer, noFade = true,
			layer = layer, sublevel = sublevel, troughLayer = troughLayer, troughSub = troughSub, alsoFade = List(timer.Background) })
		if rep then
			r.timer = rep
			local enable, disable = rep.onEnable, rep.onDisable
			rep.onEnable = function(...)
				if enable then
					enable(...)
				end
				InsetBar(timer, rep)
			end
			rep.onDisable = function(...)
				if disable then
					disable(...)
				end
				RestoreBar(timer)
			end
			-- a new Progress Bar Border has other arms: set in again by them
			rep.onBarChanged = function()
				if active then
					RestoreBar(timer)
					InsetBar(timer, rep)
				end
			end
			if active then
				InsetBar(timer, rep)
			end
		end
	end
	-- the roll buttons: K2 under the icon (the button's normal texture IS its
	-- icon: kept, never faded)
	for _, b in ipairs(RollButtons(f)) do
		local normal = b:GetNormalTexture()
		if normal and not done[b] then
			done[b] = true
			b.melloNoInk = true
			local rep = RollReplace(normal, { as = "bags-button-autosort-up", button = b, noFade = true })
			if rep then
				r.buttons[#r.buttons + 1] = { button = b, rep = rep }
				stats.rollButtons = stats.rollButtons + 1
			end
		end
	end
	nine:SetShown(active)
	stats.rolls = stats.rolls + 1
	return r
end

local function ShowRoll(f, on)
	local r = rolls[f]
	if not r then
		return
	end
	r.nine:SetShown(on)
	for _, obj in ipairs(r.faded) do
		if on then
			Kit:Fade(obj)
		else
			Kit:Unfade(obj)
		end
	end
	if on then
		RollLevels(f, r)
		ReadQuality(f, r)
		if r.rim then
			FitIconRim(r.rim)
		end
	elseif r.timerLevel and f.Timer then
		f.Timer:SetFrameLevel(r.timerLevel)
		r.timerLevel = nil
	end
end

local function BuildRolls()
	rollSkin = rollSkin or { reps = {} }
	for _, f in ipairs(RollFrames()) do
		DressRoll(f)
	end
end

--------------------------------------------------------------------------------
-- Switching on and off
--------------------------------------------------------------------------------
local function Activate()
	if active then
		return
	end
	BuildWindow()
	BuildRolls()
	active = true
	-- (either set may be missing: a client without the loot window, or one
	-- without roll frames)
	for _, set in pairs({ window = skin, rolls = rollSkin }) do
		for _, rep in ipairs(set.reps) do
			rep:Enable()
		end
	end
	for _, obj in ipairs(fadedArt) do
		Kit:Fade(obj)
	end
	for _, entry in ipairs(cards) do
		entry.tex:Show()
	end
	PanelShown()
	for _, f in ipairs(RollFrames()) do
		ShowRoll(f, true)
	end
	RefreshWindow()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, set in pairs({ window = skin, rolls = rollSkin }) do
		for _, rep in ipairs(set.reps) do
			rep:Disable()
		end
	end
	for _, obj in ipairs(fadedArt) do
		Kit:Unfade(obj)
	end
	for _, entry in ipairs(cards) do
		entry.tex:Hide()
	end
	PanelShown()
	for _, f in ipairs(RollFrames()) do
		ShowRoll(f, false)
	end
end

local function Sync()
	if M.isEnabled then
		Activate()
	else
		Deactivate()
	end
end

-- (geometry of the windows' children changes here: out of combat only)
local function SyncSafe()
	Kit:WhenOutOfCombat(Sync)
end

local function Hook()
	if hooked then
		return
	end
	hooked = true
	local f = Window()
	if f then
		Perf.HookScript(f, "OnShow", function()
			if M.isEnabled and not active then
				SyncSafe()
			end
			RefreshWindow()
		end)
	end
	-- a roll frame shown: its game refresh (SetupItemDisplay: the icon, the
	-- quality colours, the buttons, the timer's level) ran first (a HookScript
	-- runs after the frame's own OnShow); ours after it
	for _, rf in ipairs(RollFrames()) do
		Perf.HookScript(rf, "OnShow", function(self)
			if not active then
				return
			end
			local r = DressRoll(self)
			if r then
				ShowRoll(self, true)
				if r.timer then
					InsetBar(self.Timer, r.timer)
					r.timer:Refit()
				end
			end
		end)
	end
end

function M:OnEnable(db)
	self.db = db
	Hook()
	SyncSafe()
end

function M:OnDisable()
	SyncSafe()
end

--------------------------------------------------------------------------------
-- /lootdump [roll [n] | frames | reps | regions]: with no mode, the loot
-- window -- its layout, every part found or not and what it was dressed as,
-- the title on its plate and its font, the page picture's rect, every row
-- now in the list -- and a line per roll frame; `roll n` (1 by default) one
-- roll frame's parts, levels and state; the other modes are Kit:DumpWindow's
-- on the loot window. Opens the copy window.
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

local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.0f", v) or "?"
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

local function Text(fs)
	local ok, t = pcall(fs.GetText, fs)
	return (ok and type(t) == "string" and not Secret(t)) and t or "?"
end

local function Rect(obj)
	local ok, l, b, w, h = pcall(function() return obj:GetRect() end)
	if ok and l and not (Secret(l) or Secret(b) or Secret(w) or Secret(h)) then
		return string.format("x=%.0f y=%.0f w=%.0f h=%.0f", l, b, w, h)
	end
	return "(no rect)"
end

local function Level(obj)
	local ok, lv = pcall(obj.GetFrameLevel, obj)
	return ok and Num(lv) or "?"
end

local function DumpWindow(f)
	MelloUI:Print("LootFrame: shown %s, level %s, strata %s, layout %s, kit %s, reps %d, faded art %d", Shown(f), Level(f),
		tostring(select(2, pcall(f.GetFrameStrata, f))), skin and skin.layout or Layout(f), active and "on" or "off",
		skin and #skin.reps or 0, #fadedArt)
	Found("outer rail (NineSlice)", f.NineSlice, f.NineSlice and (" layout " .. tostring(f.NineSlice.layoutType)) or nil)
	Found("background (Bg)", f.Bg, f.Bg and (IsTexture(f.Bg) and " (a texture)" or " (a flat frame, level " .. Level(f.Bg) .. ")") or nil)
	Found("page stone", skin and skin.page and skin.page.object, (skin and skin.page) and (" " .. Rect(skin.page.inner or skin.page.object)) or nil)
	Found("inner panel (2e)", skin and skin.panel, (skin and skin.panel) and (" alpha " .. PANEL_ALPHA .. ", shown " .. Shown(skin.panel) .. ", " .. Rect(skin.panel)) or nil)
	local portrait = Portrait(f)
	Found("portrait", portrait, portrait and string.format(" ring %s, fitted %s", tostring(skin and skin.ring ~= nil), tostring(portrait.melloSaved ~= nil))
		or " (none: no ring on this window, as the game's)")
	local rep = TitleRep()
	local title = TitleText(f)
	Found("title plate", rep and rep.object, rep and (" shown " .. Shown(rep.object) .. ", " .. Rect(rep.object)) or nil)
	if title then
		local okF, face = pcall(title.GetFont, title)
		Found("title text", title, string.format(" '%s', %s, face %s, title face %s", Text(title), Rect(title),
			(okF and type(face) == "string" and not Secret(face)) and (face:match("([^\\/]+)$") or face) or "?", tostring(title.melloFontSaved ~= nil)))
	else
		Found("title text", nil)
	end
	local close = f.ClosePanelButton or f.CloseButton or _G.LootFrameCloseButton
	Found("close button", close, skin and skin.close and " (kit close)" or nil)
	Found("scroll bar", f.ScrollBar, f.ScrollBar and (" dressed " .. Dressed(f.ScrollBar) .. ", shown " .. Shown(f.ScrollBar)) or nil)
	Found("scroll box", f.ScrollBox, f.ScrollBox and (" level " .. Level(f.ScrollBox)) or nil)
	local inset = f.Inset or _G.LootFrameInset
	Found("inset (older window)", inset, inset and (" dressed " .. Dressed(inset)) or nil)
	local n = 0
	if f.ScrollBox and f.ScrollBox.ForEachFrame then
		f.ScrollBox:ForEachFrame(function(row)
			n = n + 1
			local item = row.Item
			Found("row " .. n, row, string.format(" %s, shown %s, card %s, stroke %s, rim %s, quality border %s, text '%s'",
				item and "item" or "empty", Shown(row), tostring(done[row] == true and item ~= nil), FadedState(row.BorderFrame),
				Dressed(item), (item and item.IconBorder) and ("shown " .. Shown(item.IconBorder)) or "none", row.Text and Text(row.Text) or ""))
		end)
	end
	for i = 1, OLD_BUTTONS do
		local b = _G["LootButton" .. i]
		if b then
			Found("old button " .. i, b, string.format(" shown %s, rim %s, plate %s", Shown(b), Dressed(b), FadedState(Part(b, "NameFrame", "NameFrame"))))
		end
	end
	for _, a in ipairs(ARROWS) do
		if _G[a[1]] then
			Found("page arrow", _G[a[1]], " dressed " .. tostring(done[_G[a[1]]] == true))
		end
	end
	MelloUI:Print("  tabs: none on this window; inked strings: none (no parchment)")
	MelloUI:Print("  rows %d, cards %d, rims %d (loot + roll icons), roll frames dressed %d, roll buttons %d",
		stats.rows, stats.cards, stats.rims, stats.rolls, stats.rollButtons)
end

local function DumpRoll(i)
	local f = _G["GroupLootFrame" .. i]
	if not f then
		MelloUI:Print("GroupLootFrame%d: not on this client", i)
		return
	end
	local r = rolls[f]
	MelloUI:Print("GroupLootFrame%d: shown %s, level %s, strata %s, %s, dressed %s", i, Shown(f), Level(f),
		tostring(select(2, pcall(f.GetFrameStrata, f))), Rect(f), tostring(r ~= nil))
	Found("background (faded)", f.Background, f.Background and (" " .. FadedState(f.Background) .. ", " .. Rect(f.Background)) or nil)
	Found("border (faded)", f.Border, f.Border and (" " .. FadedState(f.Border) .. ", " .. Rect(f.Border)) or nil)
	Found("kit box", r and r.nine, r and string.format(" level %s, shown %s, %s, panel %s", Level(r.nine), Shown(r.nine), Rect(r.nine),
		tostring(r.dim ~= nil)) or nil)
	Found("name", f.Name, f.Name and (" '" .. Text(f.Name) .. "'") or nil)
	local iconFrame = f.IconFrame
	local tint = r and r.rim and r.rim.tint
	Found("icon", iconFrame, iconFrame and string.format(" rim %s, tint %s, quality ring %s", Dressed(iconFrame),
		tint and string.format("%.2f %.2f %.2f", tint[1], tint[2], tint[3]) or "white", FadedState(iconFrame.Border)) or nil)
	local timer = f.Timer
	Found("timer", timer, timer and string.format(" level %s (kept from %s), bracket %s, set in %s, backing %s, %s", Level(timer),
		tostring(r and r.timerLevel or "-"), tostring(r ~= nil and r.timer ~= nil), tostring(insetBars[timer] ~= nil),
		FadedState(timer.Background), Rect(timer)) or nil)
	for _, b in ipairs(RollButtons(f)) do
		local okE, enabled = pcall(b.IsEnabled, b)
		local okA, alpha = pcall(b.GetAlpha, b)
		local plate = false
		for _, entry in ipairs(r and r.buttons or {}) do
			plate = plate or entry.button == b
		end
		Found("roll button", b, string.format(" id %s, shown %s, enabled %s, alpha %s, K2 plate %s", tostring(select(2, pcall(b.GetID, b))),
			Shown(b), (okE and not Secret(enabled)) and tostring(enabled) or "?",
			(okA and type(alpha) == "number" and not Secret(alpha)) and string.format("%.2f", alpha) or "?", tostring(plate)))
	end
	if f.NeedRollAnim then
		Found("need roll animation", f.NeedRollAnim, " (the game's)")
	end
end

SLASH_MELLOLOOTDUMP1 = "/lootdump"
SlashCmdList.MELLOLOOTDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	local rollN = msg:match("^roll%s*(%d*)$")
	if rollN then
		DumpRoll(tonumber(rollN) or 1)
	elseif msg == "" then
		if f then
			DumpWindow(f)
		else
			MelloUI:Print("/lootdump: no LootFrame: not on this client")
		end
		local frames = RollFrames()
		MelloUI:Print("Roll frames: %d on this client%s (/lootdump roll n for one)", #frames, #frames == 0 and " (not on this client: nothing dressed)" or "")
		for i, rf in ipairs(frames) do
			MelloUI:Print("  %s shown %s, dressed %s, buttons %d", Label(rf), Shown(rf), tostring(rolls[rf] ~= nil), #RollButtons(rf))
			if i >= ROLL_FRAMES * 2 then
				break
			end
		end
	elseif f then
		-- frames / reps / regions (the visible game textures): the Kit's dump
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	else
		MelloUI:Print("/lootdump: no LootFrame: not on this client")
	end
	MelloUI:ShowLog("lootdump " .. msg)
end
