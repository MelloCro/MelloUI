--------------------------------------------------------------------------------
-- MelloUI - Tabard Kit
--
-- (user, 2026-09-24: "we didnt do quest dialogs, shops, Auction House,
-- profession training window, class trainers, Guild Crest Vendors, Flight
-- map, all should follow the rules"): the guild tabard vendor's designer
-- (TabardFrame: a ButtonFrameTemplate window in the game's UI panels, or a
-- load-on-demand Blizzard_TabardUI on a client that splits it off) dressed
-- in the painted kit (Modules/Kit.lua) on the game's own layout, by the rule
-- book (docs/WINDOW-RULES.md): every kit piece stands in for one of the
-- game's art regions, on that region's rectangle, faded in place of it.
--
--   the window shell     outer double rail with gem corners, the page stone,
--                        the portrait ring with the vendor's portrait at the
--                        class medallion's size on the dark disc (2b), the
--                        title plate on the rail with the vendor's name ON it
--                        in the title face (2c), the close button
--   the greeting         ("You must be a guild master to purchase a tabard,
--                        but feel free to browse."): body text, not a title.
--                        It stays where the game puts it, under the plate,
--                        in the game's font, on a band of the palette's inner
--                        panel (2e: no small text on the plain stone)
--   the content inset    its single rail, the palette's inner panel inside it
--                        (the model's dark backdrop, the emblem's ghost on
--                        it); the gold frame the game draws round the same
--                        area faded, so the rail is not doubled
--   the cost box         the tooltip box it is (TT1: the single rail with the
--                        list-box stone), a step lighter than the panel it
--                        lies on (2e, as the social window's raid boxes)
--   the selector column  the L1 box in place of the game's customization
--                        border picture, a step lighter than the panel; each
--                        row's label frame on the plain plate, its label at
--                        the interface's full size; the arrows on the kit's
--                        arrow_left / arrow_right (the pane-toggle look)
--   the rotate buttons   the cog plate (K2) under the game's round glyph
--                        buttons, as the bags' sort button: the curved-arrow
--                        glyph says "rotate", the kit's straight arrows are
--                        the selectors' own look beside it
--   the money box        the coin plate (B2, as the bags), standing in for
--                        both the money inset and its gold edge
--   Accept / Cancel      the red plates (B1), the game's labels on them
--
-- Nothing of the game's is replaced or re-anchored but the portrait (brought
-- to the medallion size), the vendor's name (moved onto the plate) and the
-- selector labels' font and layer; each is put back on disable. Hooks only,
-- no tabard API is ever called.
--
-- /tabarddump [frames | reps | regions]: what the window is made of on this
-- client and what the skin found and dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("TabardPanel", {
	title = "Tabard Kit",
	desc = "The guild tabard designer in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil          -- { reps = { every replacement }, built, ring, portrait, disc }
local active = false
local hooked = false

-- what this module made or changed, kept OFF the game's frames (weak keys)
local done = setmetatable({}, { __mode = "k" })        -- [frame / region] = true: looked at once
local labels = setmetatable({}, { __mode = "k" })      -- [selector label] = its saved font, height and layer (false: not yet saved)
local titleMoved = setmetatable({}, { __mode = "k" })  -- [fs] = its points while on the plate
local titleFaded = setmetatable({}, { __mode = "k" })  -- [fs] = true while faded as a duplicate
local fadedArt = {}                                    -- art faded with no piece of its own (the gold frame)
local panels = {}                                      -- our inner-panel textures (the inset's, the greeting's band)
local found = {}                                       -- [part] = a line for /tabarddump

-- the palette's tones (WINDOW-RULES 2e): a box ON the dimmed inset takes the
-- main window's tone, a step lighter than the panel round it
local PAL = MelloUI.Palette or {}
local BOX_TONE = PAL.mainWindow
local BOX_DIM = 0.85

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Tabard kit: no kit piece mapped for %s", tostring(key))
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

-- a frame's name for the finders (a name can read secret)
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

-- ... and for the dump
local function Label(obj)
	if not obj then
		return "nil"
	end
	local n = NameOf(obj)
	if n then
		return n
	end
	local ok, d = pcall(obj.GetDebugName, obj)
	return (ok and type(d) == "string" and not Secret(d)) and d or "[unnamed]"
end

-- a font string's text when it can be read (nil when empty or secret)
local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	if ok and type(text) == "string" and not Secret(text) and text ~= "" then
		return text
	end
	return nil
end

-- whether a font string shows anything: a secret text (the vendor's name may
-- come secret on this client) is shown by the game all the same
local function HasText(fs)
	local ok, text = pcall(fs.GetText, fs)
	if not ok then
		return false
	end
	if Secret(text) then
		return true
	end
	return type(text) == "string" and text ~= ""
end

-- a frame's level, or nil when it cannot be read
local function LevelOf(frame)
	local ok, lv = pcall(frame.GetFrameLevel, frame)
	if ok and type(lv) == "number" and not Secret(lv) then
		return lv
	end
	return nil
end

local function Width(obj)
	local ok, w = pcall(obj.GetWidth, obj)
	if ok and type(w) == "number" and not Secret(w) then
		return w
	end
	return nil
end

-- a part of the window: the key the template gives it, else its global name
-- (the tabard templates name their pieces "$parentLeft", no parentKey)
local function Part(owner, key, suffix)
	if not owner then
		return nil
	end
	local v = owner[key]
	if v then
		return v
	end
	local n = NameOf(owner)
	return n and suffix and _G[n .. suffix] or nil
end

local function Window()
	return _G.TabardFrame
end

local function Model(f)
	return _G.TabardModel or (f and (f.TabardModel or f.ModelScene or f.Model)) or nil
end

--------------------------------------------------------------------------------
-- The portrait in the ring (WINDOW-RULES 2b / 2c: an empty ring is a bug).
-- The game draws the vendor into TabardFramePortrait (SetPortraitTexture on
-- "npc"), a texture of the window itself -- not the PortraitContainer's own
-- portrait, which this window leaves blank. The ring stands on the portrait
-- container (above the window); the vendor's portrait, a region of the
-- window under it, shows through the ring's opening at the class medallion's
-- size (Kit:FitPortrait), with the dark disc right under it (Kit:RingDisc, one
-- sublevel below the portrait in the window's own stack), so the ring is
-- never empty even when the game has no portrait to give.
--------------------------------------------------------------------------------
local function PortraitCandidates(f)
	local list, seen = {}, {}
	local pc = f.PortraitContainer
	for _, t in ipairs({ _G.TabardFramePortrait or false, f.portrait or false, pc and pc.portrait or false }) do
		if t and not seen[t] and t.GetObjectType and t:GetObjectType() == "Texture" then
			seen[t] = true
			list[#list + 1] = t
		end
	end
	return list
end

-- the portrait the game fills: the first with any art, else the window's own
local function Portrait(f)
	local list = PortraitCandidates(f)
	for _, t in ipairs(list) do
		local ok, file = pcall(t.GetTexture, t)
		if ok and file ~= nil then
			return t
		end
	end
	return list[1]
end

local function SkinPortrait(portrait, ring)
	if not (portrait and ring and ring.tex) then
		return
	end
	local function Fit()
		pcall(Kit.FitPortrait, Kit, portrait, ring)
	end
	ring.onEnable = Fit
	ring.onDisable = function()
		pcall(Kit.UnfitPortrait, Kit, portrait)
	end
	-- the disc one sublevel under the portrait, in the portrait's own frame
	-- (a disc on the portrait container would lie OVER a portrait that is a
	-- texture of the window)
	local okL, layer, sub = pcall(portrait.GetDrawLayer, portrait)
	local parent = portrait:GetParent()
	local disc
	if okL and layer == "BACKGROUND" and parent then
		disc = Kit:RingDisc(ring, nil, parent, math.max((sub or 0) - 1, -8))
	else
		disc = Kit:RingDisc(ring)   -- chains onto the fit above
	end
	skin.ring, skin.portrait, skin.disc = ring, portrait, disc
	found.portrait = string.format("%s (layer %s %s), disc %s", Label(portrait), okL and tostring(layer) or "?",
		okL and tostring(sub) or "", disc and "made" or "NOT made")
end

--------------------------------------------------------------------------------
-- The title (WINDOW-RULES 2c, user 2026-09-24: "the text header is not on the
-- header"). The title plate's rule centres the title container's TitleText
-- on the plate in the kit's title face; this window writes its title -- the
-- vendor's name -- into its own TabardFrameNameText in the old title band.
-- That string is moved onto the plate (on the container's string, which the
-- rule centred there) in the title face, or faded where the container shows
-- the same words; its points and font put back on disable. The greeting is
-- never taken for a title: it is a sentence of body text.
--------------------------------------------------------------------------------
local GREETING_KEYS = { "TABARDVENDORGREETING", "TABARDVENDORNOGUILDGREETING", "TABARDVENDORALREADYSETGREETING",
	"PERSONALTABARDVENDORGREETING", "PERSONALTABARDVENDORUNOWNEDGREETING" }

local function Greeting(f)
	return _G.TabardFrameGreetingText or (f and f.GreetingText) or nil
end

local function IsGreeting(fs, f)
	if fs == Greeting(f) then
		return true
	end
	local text = TextOf(fs)
	if not text then
		return false
	end
	for _, key in ipairs(GREETING_KEYS) do
		if _G[key] == text then
			return true
		end
	end
	-- a whole sentence is not a title (a plate holds a name)
	return #text > 40
end

local function TitleStrings(f)
	local tc = f.TitleContainer
	local own = tc and tc.TitleText
	local list, seen = {}, {}
	if own then
		seen[own] = true
	end
	for _, fs in ipairs({ _G.TabardFrameNameText or false, f.NameText or false, f.TitleText or false, _G.TabardFrameTitleText or false }) do
		if fs and not seen[fs] and fs.GetObjectType and fs:GetObjectType() == "FontString" then
			seen[fs] = true
			if HasText(fs) and not IsGreeting(fs, f) then
				list[#list + 1] = fs
			end
		end
	end
	return list, own
end

local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
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
	local list, own = TitleStrings(f)
	local ownText = own and TextOf(own)
	for _, fs in ipairs(list) do
		if ownText and TextOf(fs) == ownText then
			-- the same words already on the plate: this copy gives way
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
			-- on the container's string (the rule centred it on the plate's
			-- painted box), else on the plate itself
			if own then
				fs:SetPoint("CENTER", own, "CENTER")
			else
				fs:SetPoint("CENTER", rep.strip or rep.object, "CENTER")
			end
			Kit:TitleFont(fs, true)
		end
	end
end

--------------------------------------------------------------------------------
-- The palette's inner panel (WINDOW-RULES 2e): regions of the game's own
-- frames under their text, shown while the kit is on. BACKGROUND -4: over
-- the page stone (the window's Bg, -6) and the inset's faded marble (-5),
-- under the vendor's portrait and its disc (0 / -1) -- the greeting's band
-- runs up to the ring and must not lie over the portrait there. (Frames at
-- one level share one layer order: the inset draws at the window's level.)
--------------------------------------------------------------------------------
local PANEL_SUB = -4

local function Panel(host, opts)
	if not (host and Kit.StoneDim) then
		return nil
	end
	opts = opts or {}
	opts.sublevel = PANEL_SUB
	local tex = Kit:StoneDim(host, opts)
	if tex then
		tex.kitPiece = true      -- ours: never taken for the game's art
		tex:SetShown(active)
		panels[#panels + 1] = tex
	end
	return tex
end

-- The content inset (ButtonFrameTemplate's): its single rail (the inset's
-- look, edges only: a holder with a stone body would lie over the emblem,
-- which is the window's own art at the inset's level) and the inner panel
-- inside it as the inset's own region -- the model's dark backdrop, the
-- emblem's ghost drawn over it. The gold frame the game draws round the same
-- area (the TabardFrameOuterFrame pieces, a few px inside the inset) is
-- faded: two rails 4 px apart would be the doubled-rail bug.
local function SkinContent(f)
	local inset = f.Inset
	if inset and not done[inset] then
		done[inset] = true
		Kit:SkinInset(inset, Replace, f)
		local tex = Panel(inset)
		found.inset = string.format("%s, rail %s, inner panel %s", Label(inset), tostring(inset.melloRep ~= nil and inset.melloRep ~= false),
			tex and "on" or "NOT made")
	end
	for _, region in ipairs({ f:GetRegions() }) do
		local name = NameOf(region)
		if name and name:find("^TabardFrameOuterFrame") and not done[region] then
			done[region] = true
			fadedArt[#fadedArt + 1] = region
			if active then
				Kit:Fade(region)
			end
		end
	end
	found.outerFrame = string.format("%d gold frame pieces faded", #fadedArt)
end

-- The greeting: body text, left where the game puts it (under the title
-- plate, beside the ring) in the game's font -- a sentence on the rune plate
-- would be squeezed and in the display face, which is for names only -- on a
-- band of the inner panel that hugs the string (it grows with a second line).
local function SkinGreeting(f)
	local fs = Greeting(f)
	if not fs then
		found.greeting = "-- not found"
		return
	end
	if done[fs] then
		return
	end
	done[fs] = true
	local rect = CreateFrame("Frame", nil, f)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", fs, "TOPLEFT", -6, 4)
	rect:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 6, -4)
	local tex = Panel(f, { rect = rect })
	found.greeting = string.format("%s, band %s", Label(fs), tex and "on" or "NOT made")
end

--------------------------------------------------------------------------------
-- The cost box (TabardFrameCostFrame, a TooltipBackdropTemplate box): the
-- tooltip look it is (TT1: the single rail with the list-box stone as
-- regions of its NineSlice, in the pieces' own layers, under the "Cost:"
-- label and the coins on the money frame above it), with the main window's
-- tone over the stone (2e). The rect grows by half a rail on each side, so
-- the rails' centre lines lie where the game's border was and its text keeps
-- the game's room inside them. A client whose box is built otherwise gets
-- the L1 box on the same rect in place of its own textures.
--------------------------------------------------------------------------------
local function RailPad()
	local t = Kit:Size((Kit.framePrefix or "window/single") .. "_tl", Kit.scale * (Kit.frameScale or 1.6))
	return (t or 0) / 2
end

local function PadRect(target)
	local pad = RailPad()
	local rect = CreateFrame("Frame", nil, target)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", target, "TOPLEFT", -pad, pad)
	rect:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", pad, -pad)
	return rect
end

-- an invisible texture of `host` on `rect`: the region a box with no game art
-- of its own is handed to Kit:Replace as (never faded: noFade)
local function Anchor(host, rect)
	local tex = host:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints(rect or host)
	tex:SetColorTexture(0, 0, 0, 0)
	tex.kitPiece = true
	return tex
end

local function CostFrame(f)
	return _G.TabardFrameCostFrame or (f and f.CostFrame) or nil
end

local function SkinCost(f)
	local cost = CostFrame(f)
	if not cost then
		found.cost = "-- not found"
		return
	end
	if done[cost] then
		return
	end
	done[cost] = true
	local rect = PadRect(cost)
	local nine = cost.NineSlice
	local corner = nine and nine.TopLeftCorner
	local rep
	if corner then
		local others = {}
		for _, region in ipairs({ nine:GetRegions() }) do
			if region ~= corner and region:GetObjectType() == "Texture" and not region.kitPiece then
				others[#others + 1] = region
			end
		end
		rep = Replace(corner, { as = "Tooltip-NineSlice-CornerTopLeft", rect = rect, dim = BOX_DIM, dimColor = BOX_TONE, alsoFade = others })
		found.cost = string.format("%s: tooltip box (TT1) %s", Label(cost), rep and "dressed" or "NOT dressed")
	else
		local art = {}
		for _, region in ipairs({ cost:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not region.kitPiece then
				art[#art + 1] = region
			end
		end
		local first = table.remove(art, 1)
		rep = Replace(first or Anchor(cost), { as = "common-insideframe", parent = cost, rect = rect, level = 0,
			dim = BOX_DIM, dimColor = BOX_TONE, noFade = first == nil, alsoFade = art })
		found.cost = string.format("%s: L1 box %s (no NineSlice on this client)", Label(cost), rep and "dressed" or "NOT dressed")
	end
end

--------------------------------------------------------------------------------
-- The selector column (TabardFrameCustomization1..5 in their frame, over the
-- game's TabardFrameCustomizationBorder picture):
--   * the L1 box in place of that picture, on the rows' own extent (the first
--     row's left arrow to the last row's right arrow, grown by half a rail),
--     a holder under the rows' level, the main window's tone over its stone
--   * each row's label frame (Left / Middle / Right, the old character-create
--     label picture) -> the plain plate on the three pieces' own span, as
--     regions of the row under its label; the label raised out of the
--     BACKGROUND layer it shares with that art, and set at the interface's
--     full size (2e: no small font for a column of settings)
--   * the arrows -> the kit's arrow_left / arrow_right (the pane toggle's
--     look, PrevPage / NextPage keyed by hand: file art reads back as ids),
--     at the row's height on the buttons' centres -- the game's 32 px buttons
--     draw a much smaller arrow in the middle of a transparent square
--------------------------------------------------------------------------------
local function Rows()
	local list = {}
	for i = 1, 10 do
		local row = _G["TabardFrameCustomization" .. i]
		if not row then
			break
		end
		list[#list + 1] = row
	end
	return list
end

local function RowParts(row)
	return {
		left = Part(row, "Left", "Left"),
		middle = Part(row, "Middle", "Middle"),
		right = Part(row, "Right", "Right"),
		text = Part(row, "Text", "Text"),
		prev = Part(row, "LeftButton", "LeftButton"),
		next = Part(row, "RightButton", "RightButton"),
	}
end

-- the label's full-size font and its own layer over the plate (put back on
-- disable). The template gives it a 10 px tall box for the small font: the
-- box follows the new font's height, so no line is cut.
local function LabelOn(fs)
	local saved = labels[fs]
	if not saved then
		local okF, obj = pcall(fs.GetFontObject, fs)
		local okD, layer, sub = pcall(fs.GetDrawLayer, fs)
		local okH, h = pcall(fs.GetHeight, fs)
		saved = { obj = okF and obj or nil, layer = okD and layer or nil, sub = okD and sub or 0,
			h = (okH and type(h) == "number" and not Secret(h)) and h or nil }
		labels[fs] = saved
	end
	local font = _G.GameFontHighlight
	if font then
		pcall(fs.SetFontObject, fs, font)
		local okS, _, size = pcall(font.GetFont, font)
		if okS and type(size) == "number" and saved.h then
			pcall(fs.SetHeight, fs, math.max(saved.h, size + 2))
		end
	end
	pcall(fs.SetDrawLayer, fs, "ARTWORK", 0)
end

local function LabelOff(fs)
	local saved = labels[fs]
	if not saved then
		return
	end
	if saved.obj then
		pcall(fs.SetFontObject, fs, saved.obj)
	end
	if saved.h then
		pcall(fs.SetHeight, fs, saved.h)
	end
	if saved.layer then
		pcall(fs.SetDrawLayer, fs, saved.layer, saved.sub or 0)
	end
end

local ARROWS = { prev = "UI-SpellbookIcon-PrevPage-Up", next = "UI-SpellbookIcon-NextPage-Up" }

local function SkinArrow(button, key, size)
	if not button or done[button] or not button.GetNormalTexture then
		return false
	end
	done[button] = true
	local normal = button:GetNormalTexture()
	if not normal then
		return false
	end
	local rect = CreateFrame("Frame", nil, button)
	rect:EnableMouse(false)
	rect:SetSize(size, size)
	rect:SetPoint("CENTER", button, "CENTER")
	local rep = Replace(normal, { as = key, button = button, rect = rect,
		alsoFade = List(button:GetPushedTexture(), button:GetDisabledTexture(), button:GetHighlightTexture()) })
	return rep ~= nil
end

local function SkinRow(row)
	if done[row] then
		return
	end
	done[row] = true
	local p = RowParts(row)
	local plate = false
	-- the plate on the label frame's own span: its three pieces side by side,
	-- the middle centred on the row (the template's anchors), the row's height
	if p.middle then
		local rect = row
		local w, mw = Width(row), Width(p.middle)
		if w and mw and w > 0 and mw > 0 then
			local lw, rw = (p.left and Width(p.left)) or 0, (p.right and Width(p.right)) or 0
			local side = (w - mw) / 2
			rect = CreateFrame("Frame", nil, row)
			rect:EnableMouse(false)
			rect:SetPoint("TOPLEFT", row, "TOPLEFT", side - lw, 0)
			rect:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -(side - rw), 0)
		end
		plate = Replace(p.middle, { as = "GuildNewsRow", rect = rect, alsoFade = List(p.left, p.right) }) ~= nil
	end
	if p.text then
		labels[p.text] = labels[p.text] or false
		if active then
			LabelOn(p.text)
		end
	end
	local okH, h = pcall(row.GetHeight, row)
	local size = (okH and type(h) == "number" and not Secret(h) and h > 0) and h or 20
	local prev = SkinArrow(p.prev, ARROWS.prev, size)
	local nxt = SkinArrow(p.next, ARROWS.next, size)
	found.rows = found.rows or {}
	found.rows[#found.rows + 1] = string.format("%s: plate %s, label %s, arrows %s / %s", Label(row), tostring(plate),
		p.text and ("'" .. tostring(TextOf(p.text) or "?") .. "' full size") or "-- none", tostring(prev), tostring(nxt))
end

local function SkinColumn(f)
	local rows = Rows()
	if #rows == 0 then
		found.column = "-- no TabardFrameCustomizationN rows"
		return
	end
	local container = _G.TabardFrameCustomizationFrame or rows[1]:GetParent() or f
	if not done[container] then
		done[container] = true
		local border = _G.TabardFrameCustomizationBorder
		local first, last = RowParts(rows[1]), RowParts(rows[#rows])
		local tl, br = first.prev or rows[1], last.next or rows[#rows]
		local pad = RailPad()
		local rect = CreateFrame("Frame", nil, container)
		rect:EnableMouse(false)
		rect:SetPoint("TOPLEFT", tl, "TOPLEFT", -pad, pad)
		rect:SetPoint("BOTTOMRIGHT", br, "BOTTOMRIGHT", pad, -pad)
		-- a holder under the rows (the lowest row's level less one), never
		-- below the container itself (the model lies under the container)
		local cl = LevelOf(container) or 0
		local low
		for _, row in ipairs(rows) do
			local lv = LevelOf(row)
			if lv and (not low or lv < low) then
				low = lv
			end
		end
		local offset = low and math.max(low - cl - 1, 0) or 0
		local isTex = border and border.GetObjectType and border:GetObjectType() == "Texture"
		local rep = Replace(isTex and border or Anchor(container, rect), { as = "common-insideframe", parent = container, rect = rect,
			level = offset, body = true, dim = BOX_DIM, dimColor = BOX_TONE, noFade = not isTex })
		found.column = string.format("%s, %d rows, border %s, L1 box %s (holder at +%d)", Label(container), #rows,
			isTex and Label(border) or "-- none", rep and "dressed" or "NOT dressed", offset)
	end
	for _, row in ipairs(rows) do
		SkinRow(row)
	end
end

--------------------------------------------------------------------------------
-- The model's rotate buttons: K2, the cog plate UNDER the game's round
-- buttons (their curved-arrow glyph is their plate: not faded), as the bags'
-- sort button. A client whose model has the scene's control strip (square
-- buttons with an Icon) gets the cog plate in place of the square, the icon
-- on top, as the group finder's refresh button.
--------------------------------------------------------------------------------
local function RotateButtons(f)
	local list, seen = {}, {}
	local function Add(b)
		if b and not seen[b] and b.GetObjectType and b:GetObjectType() == "Button" then
			seen[b] = true
			list[#list + 1] = b
		end
	end
	Add(_G.TabardCharacterModelRotateLeftButton)
	Add(_G.TabardCharacterModelRotateRightButton)
	local model = Model(f)
	local strip = model and model.ControlFrame
	for _, holder in ipairs({ model or false, strip or false }) do
		if holder and holder.GetChildren then
			for _, child in ipairs({ holder:GetChildren() }) do
				local n = NameOf(child) or ""
				if child ~= strip and (holder == strip or n:find("Rotate") or n:find("Zoom") or n:find("Reset")) then
					Add(child)
				end
			end
		end
	end
	return list
end

local function SkinRotate(f)
	local buttons = RotateButtons(f)
	local n = 0
	for _, b in ipairs(buttons) do
		if not done[b] then
			done[b] = true
			local normal = b.GetNormalTexture and b:GetNormalTexture()
			local rep
			if normal and b.Icon then
				rep = Replace(normal, { as = "UI-SquareButton-Up", button = b, alsoFade = Kit:OtherTextures(b, b.Icon) })
			elseif normal then
				rep = Replace(normal, { as = "bags-button-autosort-up", button = b, noFade = true })
			end
			if rep then
				n = n + 1
			end
		end
	end
	found.rotate = string.format("%d of %d buttons on the cog plate", n, #buttons)
end

--------------------------------------------------------------------------------
-- The money box: the coin plate (B2, the bags' money strip on the header
-- plate) on the gold edge's rect (TabardFrameMoneyBg, a ThinGoldEdgeTemplate:
-- Left / Middle / Right), standing in for the money inset round it too --
-- that inset's rail on its 21 px would lie over the plate. The inset is
-- marked with the plate (the Kit's own marker, which its sweep reads) so the
-- sweep leaves it; the game hides and shows the three itself (a personal
-- tabard vendor shows no money), and the plate goes with the gold edge. The
-- plate at the gold edge's own level: over the window's stone, under the
-- coins (the money frame's buttons one level up).
--------------------------------------------------------------------------------
local function SkinMoney(f)
	local bg = _G.TabardFrameMoneyBg or f.MoneyBg
	if not bg then
		found.money = "-- not found"
		return
	end
	if done[bg] then
		return
	end
	done[bg] = true
	local middle = Part(bg, "Middle", "Middle")
	local inset = _G.TabardFrameMoneyInset or f.MoneyInset
	local fade = List(Part(bg, "Left", "Left"), Part(bg, "Right", "Right"))
	if inset then
		fade[#fade + 1] = inset.Bg
		if inset.NineSlice then
			for _, region in ipairs({ inset.NineSlice:GetRegions() }) do
				if region:GetObjectType() == "Texture" then
					fade[#fade + 1] = region
				end
			end
		end
	end
	local rep = middle and Replace(middle, { as = "common-coinbox-center", parent = bg, rect = bg, level = 0, alsoFade = fade }) or nil
	if inset and inset.melloRep == nil then
		inset.melloRep = rep or false
	end
	found.money = string.format("%s: coin plate %s, inset %s%s", Label(bg), rep and "dressed" or "NOT dressed",
		inset and Label(inset) or "-- none", inset and " faded with it" or "")
end

--------------------------------------------------------------------------------
-- Building, switching on and off
--------------------------------------------------------------------------------
local function Build()
	local f = Window()
	if not f then
		return
	end
	skin = skin or { reps = {} }
	if skin.built then
		return
	end
	skin.built = true

	-- the shell: outer rail, one page stone, the ring on the vendor's
	-- portrait, the title plate on the rail, the close button
	local portrait = Portrait(f)
	local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = portrait, bg = "UI-Background-Rock" })
	found.shell = string.format("NineSlice %s, page stone %s, title container %s, close %s", tostring(f.NineSlice ~= nil),
		tostring(f.Bg ~= nil), tostring(f.TitleContainer ~= nil), tostring(f.CloseButton ~= nil))
	if ring then
		SkinPortrait(portrait, ring)
	else
		found.portrait = "-- no ring (no NineSlice corner or no portrait on this client)"
	end

	SkinContent(f)
	SkinGreeting(f)
	SkinCost(f)
	SkinColumn(f)
	SkinRotate(f)
	SkinMoney(f)

	-- Accept / Cancel on the red plates, and whatever else the sweep knows
	-- (the model is not walked into: its buttons are the rotate plates above)
	Kit:SweepControls(f, Replace, skin, Model(f))
	local b1, b2 = _G.TabardFrameAcceptButton, _G.TabardFrameCancelButton
	found.buttons = string.format("Accept %s, Cancel %s", tostring(b1 ~= nil and b1.melloRep ~= nil and b1.melloRep ~= false),
		tostring(b2 ~= nil and b2.melloRep ~= nil and b2.melloRep ~= false))
end

local function FitRing()
	if skin and skin.portrait and skin.ring then
		pcall(Kit.FitPortrait, Kit, skin.portrait, skin.ring)
	end
end

-- On every show: the portrait fitted (it has a place only once laid out),
-- the vendor's name onto the plate (the game writes it as the window opens),
-- and both again a frame later, once the game's own layout has run.
local function Refresh()
	local f = Window()
	if not (active and skin and f) then
		return
	end
	FitRing()
	PlaceTitles(true)
	C_Timer.After(0, function()
		if active and f:IsShown() then
			FitRing()
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
	for _, tex in ipairs(panels) do
		tex:Show()
	end
	for fs in pairs(labels) do
		LabelOn(fs)
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
	for _, tex in ipairs(panels) do
		tex:Hide()
	end
	for fs in pairs(labels) do
		LabelOff(fs)
	end
	-- the vendor's name back where the game put it, in its font (the ring's
	-- onDisable put the portrait back)
	PlaceTitles(false)
end

local function Sync()
	if M.isEnabled and Window() then
		Activate()
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

local function Hook()
	local f = Window()
	if hooked or not f then
		return
	end
	hooked = true
	f:HookScript("OnShow", function()
		if M.isEnabled and not active then
			SyncSafe()
		end
		Refresh()
	end)
end

-- The window is in the game's UI panels on this family of clients; a client
-- that loads it on demand (Blizzard_TabardUI) makes it later: every addon
-- load is a chance, until it exists.
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self)
	if Window() then
		self:UnregisterEvent("ADDON_LOADED")
		Hook()
		if M.isEnabled then
			SyncSafe()
		end
	end
end)

function M:OnEnable(db)
	self.db = db
	if Window() then
		Hook()
		SyncSafe()
	else
		eventFrame:RegisterEvent("ADDON_LOADED")
	end
end

function M:OnDisable()
	SyncSafe()
end

--------------------------------------------------------------------------------
-- /tabarddump [frames | reps | regions]: with no mode, what the skin found
-- and dressed and the window's own regions and children; the modes are
-- Kit:DumpWindow's. Opens the copy window.
--------------------------------------------------------------------------------
local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer, sub = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "")
		elseif kind == "FontString" then
			art = "text: " .. tostring(TextOf(region) or (HasText(region) and "[secret]" or "")):sub(1, 50)
		end
		local okA, alpha = pcall(region.GetAlpha, region)
		MelloUI:Print("  region %s %s %s %s %s alpha %s shown %s", kind, Label(region), okL and tostring(layer) or "?", okL and tostring(sub) or "",
			art, (okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?", tostring(region:IsShown()))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		MelloUI:Print("  child %s %s level %s shown %s%s", tostring(child:GetObjectType()), Label(child),
			tostring(LevelOf(child) or "?"), tostring(child:IsShown()), child.melloRep ~= nil and " (dressed)" or "")
	end
end

local function Line(label, text)
	MelloUI:Print("  %-16s %s", label, text or "-- not looked at yet (the kit has not dressed the window)")
end

local function Summary(f)
	MelloUI:Print("TabardFrame: shown %s, level %s, kit %s, reps %d", tostring(f:IsShown()), tostring(LevelOf(f) or "?"),
		active and "on" or "off", skin and #skin.reps or 0)
	Line("shell", found.shell)
	for _, t in ipairs(PortraitCandidates(f)) do
		local okT, file = pcall(t.GetTexture, t)
		local okL, layer, sub = pcall(t.GetDrawLayer, t)
		Line("portrait cand.", string.format("%s art %s, layer %s %s, shown %s, parent %s%s", Label(t),
			okT and (Secret(file) and "[secret]" or tostring(file)) or "?", okL and tostring(layer) or "?", okL and tostring(sub) or "",
			tostring(t:IsShown()), Label(t:GetParent()), (skin and skin.portrait == t) and "  <- in the ring" or ""))
	end
	Line("portrait", found.portrait)
	local titles, own = TitleStrings(f)
	Line("container title", own and string.format("%s text %s", Label(own), tostring(TextOf(own) or (HasText(own) and "[secret]" or "(empty)"))) or "-- none")
	if #titles == 0 then
		Line("title string", "-- none with text (the plate carries no title: the game gave the window none)")
	end
	for _, fs in ipairs(titles) do
		Line("title string", string.format("%s text %s, %s", Label(fs), tostring(TextOf(fs) or "[secret]"),
			titleMoved[fs] and "on the plate (title face)" or titleFaded[fs] and "faded (duplicate)" or "not placed"))
	end
	local greet = Greeting(f)
	Line("greeting", found.greeting and string.format("%s; text '%s'", found.greeting, greet and tostring(TextOf(greet) or "?") or "-") or nil)
	Line("inset", found.inset)
	Line("gold frame", found.outerFrame)
	Line("cost box", found.cost)
	Line("selectors", found.column)
	for _, text in ipairs(found.rows or {}) do
		Line("  row", text)
	end
	Line("rotate", found.rotate)
	Line("money box", found.money)
	Line("buttons", found.buttons)
	MelloUI:Print("  inner panels %d, gold frame pieces faded %d", #panels, #fadedArt)
	MelloUI:Print("TabardFrame's own regions and children:")
	DumpOwn(f)
end

SLASH_MELLOTABARDDUMP1 = "/tabarddump"
SlashCmdList.MELLOTABARDDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if not f then
		MelloUI:Print("/tabarddump: no TabardFrame yet (it may load with the first visit to a guild tabard vendor: talk to one, then try again)")
	elseif msg == "" then
		Summary(f)
	else
		-- frames / reps / regions (the visible game textures): the Kit's dump
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	end
	MelloUI:ShowLog("tabarddump " .. msg)
end
