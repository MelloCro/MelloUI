--------------------------------------------------------------------------------
-- MelloUI - Books & Letters Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): Books, plaques and letters you read (the item text window) in the kit, on parchment.
--
-- ItemTextFrame (a ButtonFrameTemplate window) dressed by the rule book
-- (docs/WINDOW-RULES.md), on the game's own layout:
--   the window shell -- the outer double rail with its gem corners grown
--   outward, ONE page stone in place of the rock inside it, the title plate
--   riding the top rail with the item's name on it in the title face (2c),
--   the ring with the window's book at the class medallion's size on the dark
--   disc (2b), the close button; the inset's single rail; the game's page --
--   the parchment, the large book's page or a material's picture (stone,
--   marble, bronze, silver ... chosen by ItemTextGetMaterial) -> the kit's
--   parchment page with the painted brush-stroke edge (the quest dialog's
--   page, "QuestDetailsBackgrounds"), the material's picture faded with it;
--   the page's text in dark ink by the parchment rule (QuestInk), whatever
--   colours the game gives it for the material (the ink wins on the kit's
--   parchment); the page arrows on the kit's arrows; the translation bar in
--   the Progress Bar Border; the scroll bar by the kit's sweep.
-- The page number and the arrows' PREV / NEXT stand on the stone band at the
-- top in the game's full-size gold (2e: no small text on brown); the text
-- lies on the page.
--
-- The page's text is a SimpleHTML (ItemTextPageText): its colours are set per
-- kind of text (P, H1, H2, H3), not per string. The ink is laid the same way:
-- every kind's colour inked while the page is on the kit's parchment, the
-- game's own colours (kept from its SetTextColor calls) put back when not.
-- The game sets those colours when a text begins (ITEM_TEXT_BEGIN) and the
-- text itself after (ITEM_TEXT_READY), so a text opened with the skin on is
-- inked from its first line.
--
-- Nothing of the game's is replaced or re-scripted: hooks, regions and child
-- frames of our own, faded game art and our own texture in the ring, all put
-- back when the switch (UI Modifications, Windows) is turned off. Nothing is
-- built at login: the window is dressed on its first open (user, 2026-09-24)
-- and kept.
--
-- /itemtextdump [frames|reps|regions]: what the window is made of and what
-- was dressed.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("ItemTextPanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("ItemTextPanel", {
	title = "Books & Letters Kit",
	desc = "Books, plaques and letters you read (the item text window) in the kit, on parchment.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

-- the ink surface's name (QuestInk): the page
local AREA = "itemtext"
-- the window's own book (its XML's portrait art): the ring's picture when no
-- texture of the window can be read
local BOOK_ICON = "Interface\\Spellbook\\Spellbook-Icon"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- the page's size as the game sets it for every material but the large book
-- (ItemTextFrameMixin:OnEvent, ITEM_TEXT_READY: 299 x 357 at the page's
-- TOPLEFT); the large book's page is the Book-bg atlas at its own size
local PAGE_W, PAGE_H = 299, 357
-- a material's picture: four pieces laid over the page's place
local MATERIALS = { "ItemTextMaterialTopLeft", "ItemTextMaterialTopRight", "ItemTextMaterialBotLeft", "ItemTextMaterialBotRight" }
-- the kinds of text the SimpleHTML colours one by one
local TAGS = { "P", "H1", "H2", "H3" }
-- the page arrows (the spell book's PrevPage / NextPage file art)
local ARROWS = { { "ItemTextPrevPageButton", "UI-SpellbookIcon-PrevPage-Up" }, { "ItemTextNextPageButton", "UI-SpellbookIcon-NextPage-Up" } }
-- the red plates' rule keys: a button on one keeps its label's colour
local RED_PLATES = { ["UI-Panel-Button-Up"] = true, ["_128-RedButton-Center"] = true }

local skin = nil          -- { reps, followers, win }
local active = false
local surfaceMade = false
local arrowReps = {}      -- { rep, button }
local tagGame = {}        -- [tag] = { r, g, b }: the colour the game last gave that kind of text
local tagShadow = {}      -- [tag] = { r, g, b, a }: its shadow before the ink
local tagsInked = false
local tagSetting = false

local function Secret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end

local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Books & letters: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- A frame's name, secret-safe (nil when it has none or it cannot be read)
local function NameOf(f)
	if not (f and f.GetName) then
		return nil
	end
	local ok, name = pcall(f.GetName, f)
	if ok and type(name) == "string" and not Secret(name) then
		return name
	end
	return nil
end

-- A string's text: the text (nil when empty), and whether it read secret
local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	if not ok then
		return nil, false
	end
	if Secret(text) then
		return nil, true
	end
	if type(text) == "string" and text ~= "" then
		return text, false
	end
	return nil, false
end

local function IsTexture(t)
	return type(t) == "table" and t.GetObjectType ~= nil and t:GetObjectType() == "Texture"
end

-- Whether `f` lies under `root` (a few parents up)
local function IsUnder(f, root)
	for _ = 1, 10 do
		if not f then
			return false
		end
		if f == root then
			return true
		end
		f = f.GetParent and f:GetParent()
	end
	return false
end

local function Window()
	return _G.ItemTextFrame
end

--------------------------------------------------------------------------------
-- The page stone: the window's rock (ButtonFrameBaseTemplate's tiled
-- UI-Background-Rock, `Bg`), found by what it is -- the tiled BACKGROUND
-- texture of the window -- since a window may give the `Bg` key to its own
-- parchment. Replaced by the one page stone inside the outer rail (2a); the
-- rail's own body is left out (one background per window).
--------------------------------------------------------------------------------
local function IsTiled(t)
	local ok, tiled = pcall(t.GetHorizTile, t)
	return ok and tiled == true
end

local function FindRock(frame, page)
	local name = NameOf(frame)
	for _, t in ipairs({ frame.Bg or false, name and _G[name .. "Bg"] or false }) do
		if IsTexture(t) and t ~= page and (IsTiled(t) or Kit:ArtKey(t) == "UI-Background-Rock") then
			return t
		end
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if IsTexture(region) and region ~= page and not region.kitPiece and region:GetDrawLayer() == "BACKGROUND"
			and (IsTiled(region) or Kit:ArtKey(region) == "UI-Background-Rock") then
			return region
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- The page: the game's parchment region (ItemTextFramePageBg) replaced by the
-- kit's parchment page with the painted edge, the material's four pieces
-- faded with it -- whatever the item is written on, its page is the kit's
-- one parchment. The rect is the game's page: the large book's Book-bg at
-- its own size, else the 299 x 357 page at its place (the game leaves the
-- parchment region at a stale size while it shows a material, so the rect
-- is set from the size the template gives every other page).
--------------------------------------------------------------------------------
local function Material()
	local fn = _G.ItemTextGetMaterial
	if type(fn) ~= "function" then
		return nil
	end
	local ok, material = pcall(fn)
	if ok and type(material) == "string" and not Secret(material) then
		return material
	end
	return nil
end

local function FitPageRect(win)
	local rect, bg = win.pageRect, win.pageBg
	if not (rect and bg) then
		return
	end
	local large = Material() == "ParchmentLarge"
	if win.pageFitted and win.pageLarge == large then
		return
	end
	win.pageFitted, win.pageLarge = true, large
	rect:ClearAllPoints()
	if large then
		rect:SetAllPoints(bg)
	else
		rect:SetPoint("TOPLEFT", bg, "TOPLEFT")
		rect:SetSize(PAGE_W, PAGE_H)
	end
end

-- The window's inset (ButtonFrameTemplate's, round the page): the single
-- rail, its marble faded. Its holder goes two levels over the window: above
-- the page (a region of the window), below the text's scroll frame -- the
-- rail lies over the page's edge (the quest dialogs' way). Without a page on
-- the kit's parchment the inset gets its stone under the inner panel, so no
-- text is on plain brown (2e).
local function DressInset(win, frame)
	local inset = frame.Inset
	if not inset or inset.melloRep ~= nil then
		return
	end
	local extra = { inset.Bg }
	if inset.NineSlice then
		for _, region in ipairs({ inset.NineSlice:GetRegions() }) do
			if region:GetObjectType() == "Texture" then
				extra[#extra + 1] = region
			end
		end
	end
	inset.melloRep = Replace(inset, { as = "common-insideframe", parent = frame, rect = inset, level = 2,
		body = not win.paper, noFade = true, alsoFade = extra }) or false
end

--------------------------------------------------------------------------------
-- The portrait (2b / 2c: an empty ring is a bug). The window draws its book
-- as a texture of its own (the Spellbook-Icon at its top-left corner, off the
-- ring's centre, in the window's stack under the kit's ring), and the
-- template's portrait stays empty. So the book is drawn by the kit itself, as
-- the quest dialogs' NPC is: a texture of the RING's holder, round-masked on
-- the dark disc at the class medallion's size (Kit:RingDisc: 0.759 x the
-- ring), showing the art the window's own portrait holds (the book when none
-- can be read). The game's portraits are faded meanwhile.
--------------------------------------------------------------------------------
local function PortraitCandidates(frame)
	local list, seen = {}, {}
	local function Add(t)
		if IsTexture(t) and not seen[t] and not t.kitPiece then
			seen[t] = true
			list[#list + 1] = t
		end
	end
	-- the book: the window's OVERLAY texture one sublevel down, a portrait's size
	for _, region in ipairs({ frame:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece then
			local layer, sub = region:GetDrawLayer()
			local ok, w = pcall(region.GetWidth, region)
			if layer == "OVERLAY" and sub == -1 and ok and w and not Secret(w) and w > 20 and w < 90 then
				Add(region)
			end
		end
	end
	local pc = frame.PortraitContainer
	Add(pc and pc.portrait)
	Add(frame.portrait)
	return list
end

local function PortraitArt(list)
	for _, t in ipairs(list or {}) do
		local ok, file = pcall(t.GetTexture, t)
		if ok and file ~= nil and not Secret(file) and ((type(file) == "number" and file > 0) or (type(file) == "string" and file ~= "")) then
			return file
		end
	end
	return BOOK_ICON
end

local function UpdatePortrait(win)
	local icon = win.icon
	if icon and active then
		icon:SetTexture(PortraitArt(win.portraits))
	end
end

local function SkinPortrait(win, frame)
	local ring = win.ring
	local holder = ring and ring.object
	if not (holder and holder.CreateTexture and ring.tex) then
		return
	end
	win.portraits = PortraitCandidates(frame)
	-- the disc and the book on the ring's holder: disc BACKGROUND 6, book
	-- ARTWORK, the ring itself OVERLAY -- one stack, nothing of the game's
	-- between them
	local disc = Kit:RingDisc(ring, nil, holder, 6)
	local icon = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	icon.kitPiece = true
	if disc then
		icon:SetAllPoints(disc)
	else
		icon:SetPoint("CENTER", ring.tex, "CENTER")
		icon:SetSize(1, 1)
	end
	local mask = holder:CreateMaskTexture()
	mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	icon:AddMaskTexture(mask)
	win.icon = icon
	local onEnable, onDisable = ring.onEnable, ring.onDisable
	ring.onEnable = function(r)
		if onEnable then
			onEnable(r)
		end
		if not disc then
			local okW, w = pcall(ring.tex.GetWidth, ring.tex)
			if okW and w and not Secret(w) and w > 0 then
				icon:SetSize(w * 0.759, w * 0.759)
			end
		end
		UpdatePortrait(win)
		for _, t in ipairs(win.portraits) do
			Kit:Fade(t)
		end
	end
	ring.onDisable = function(r)
		if onDisable then
			onDisable(r)
		end
		for _, t in ipairs(win.portraits) do
			Kit:Unfade(t)
		end
	end
end

--------------------------------------------------------------------------------
-- The title (2c). SetTitle writes the item's name into the title container's
-- TitleText, which the title plate's rule centres on the plate in the kit's
-- title face (Kit:TitleFont: the Fonts options and the Font Style). Any other
-- title string a layout of the window may carry (frame.TitleText when it is
-- not the container's) goes on the plate in the title face while the
-- container's is empty, or is faded where the container shows the same
-- words; its points and font put back on disable.
--------------------------------------------------------------------------------
local function TitleStrings(frame)
	local tc = frame.TitleContainer
	local own = tc and tc.TitleText
	local list = {}
	local fs = frame.TitleText
	if fs and fs ~= own and fs.GetObjectType and fs:GetObjectType() == "FontString" then
		list[#list + 1] = fs
	end
	return list, own
end

local function PlaceTitles(win, on)
	local moved, faded = win.titleMoved, win.titleFaded
	if not on then
		for fs, points in pairs(moved) do
			Kit:TitleFont(fs, false)
			fs:ClearAllPoints()
			for _, pt in ipairs(points) do
				fs:SetPoint(unpack(pt))
			end
		end
		wipe(moved)
		for fs in pairs(faded) do
			Kit:Unfade(fs)
		end
		wipe(faded)
		return
	end
	local rep = win.title
	if not rep then
		return
	end
	local list, own = TitleStrings(win.frame)
	local ownText, ownSecret = nil, false
	if own then
		ownText, ownSecret = TextOf(own)
	end
	for _, fs in ipairs(list) do
		local text = TextOf(fs)
		if text and ownText and text == ownText then
			if not faded[fs] then
				faded[fs] = true
				Kit:Fade(fs)
			end
		elseif text and not ownText and not ownSecret then
			if faded[fs] then
				faded[fs] = nil
				Kit:Unfade(fs)
			end
			if not moved[fs] then
				local points = {}
				for i = 1, fs:GetNumPoints() do
					points[i] = { fs:GetPoint(i) }
				end
				moved[fs] = points
			end
			fs:ClearAllPoints()
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
-- The page arrows (ItemTextPrevPageButton / NextPageButton: the spell book's
-- PrevPage / NextPage file art): the kit's arrows at the button's height by
-- that art's existing rule, the button's other textures faded (pushed,
-- disabled, the additive highlight). The game shows and hides the buttons
-- (first / last page); the arrows are the buttons' own, so they follow. A
-- disabled arrow is shown at a lower alpha, as the game greys its own.
--------------------------------------------------------------------------------
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
		if normal and b.melloRep == nil then
			local rep = Replace(normal, { as = a[2], button = b, rect = b, alsoFade = Kit:OtherTextures(b, normal) })
			b.melloRep = rep or false
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
			end
		end
	end
end

-- The translation bar (ItemTextStatusBar: a StatusBar with the skills' bar
-- border as its own OVERLAY texture, shown while a text is translated): the
-- Progress Bar Border (P1) as regions of the bar above its fill
local function SkinStatusBar()
	local bar = _G.ItemTextStatusBar
	if not bar or bar.melloRep ~= nil then
		return
	end
	local border
	for _, region in ipairs({ bar:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece and region:GetDrawLayer() == "OVERLAY" then
			border = region
			break
		end
	end
	if not border then
		bar.melloRep = false
		return
	end
	local layer, sublevel, troughLayer, troughSub = Kit:BracketLayers(bar)
	bar.melloRep = Replace(border, { as = "UI-Character-Skills-BarBorder", parent = bar, rect = bar,
		layer = layer, sublevel = sublevel, troughLayer = troughLayer, troughSub = troughSub }) or false
end

-- Buttons the kit's sweep put on a red plate (the window has none of its
-- own; a client may add one): their labels kept out of the ink
local function MarkRedButtons(root, depth)
	if not root or depth > 8 then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		local rep = rawget(child, "melloRep")
		if type(rep) == "table" and RED_PLATES[rep.key] and not child.melloNoInk then
			child.melloNoInk = true
		end
		MarkRedButtons(child, depth + 1)
	end
end

--------------------------------------------------------------------------------
-- The ink (the parchment rule, user 2026-09-23 / 24). The page's text is the
-- SimpleHTML's: each kind of text (P, H1 .. H3) takes the ink of the colour
-- the game gave it for the material (QuestInk.InkOf on the kit's sheet: light
-- text -> ink, a colour that means something -> a dark shade of its hue),
-- with no shadow; the game's colours come back when the page is not on the
-- kit's parchment. A colour the game sets while inked (the next text's
-- material) is kept as the game's and inked over at once. The surface itself
-- walks the text's scroll frame for any plain string a client adds there.
--------------------------------------------------------------------------------
local function Html()
	return _G.ItemTextPageText
end

local function HtmlColour(html, tag)
	local ok, r, g, b = pcall(html.GetTextColor, html, tag)
	if ok and type(r) == "number" and not Secret(r) and not Secret(g) and not Secret(b) then
		return r, g, b
	end
	return nil
end

local function InkTag(html, tag)
	local QI = MelloUI.QuestInk
	if not (QI and QI.InkOf) then
		return
	end
	local c = tagGame[tag]
	if not c then
		local r, g, b = HtmlColour(html, tag)
		if not r then
			return
		end
		c = { r, g, b }
		tagGame[tag] = c
	end
	if not tagShadow[tag] then
		local ok, sr, sg, sb, sa = pcall(html.GetShadowColor, html, tag)
		if ok and type(sr) == "number" and not Secret(sr) then
			tagShadow[tag] = { sr, sg, sb, sa or 1 }
		end
	end
	local r, g, b = QI.InkOf(c[1], c[2], c[3], true)
	tagSetting = true
	pcall(html.SetTextColor, html, tag, r, g, b)
	pcall(html.SetShadowColor, html, tag, 0, 0, 0, 0)
	tagSetting = false
end

local function PlainTag(html, tag)
	local c, s = tagGame[tag], tagShadow[tag]
	tagSetting = true
	if c then
		pcall(html.SetTextColor, html, tag, c[1], c[2], c[3])
	end
	if s then
		pcall(html.SetShadowColor, html, tag, s[1], s[2], s[3], s[4])
	end
	tagSetting = false
	tagShadow[tag] = nil
end

local function InkTags(on)
	local html = Html()
	if not html then
		return
	end
	-- nothing to put back when it was never inked
	if not on and not tagsInked then
		return
	end
	tagsInked = on and true or false
	for _, tag in ipairs(TAGS) do
		if on then
			InkTag(html, tag)
		else
			PlainTag(html, tag)
		end
	end
end

local htmlHooked = false
local function HookHtml()
	local html = Html()
	if htmlHooked or not (html and html.SetTextColor) then
		return
	end
	htmlHooked = true
	hooksecurefunc(html, "SetTextColor", function(self, a, b, c, d)
		if tagSetting then
			return
		end
		if type(a) == "string" then
			if type(b) == "number" and not Secret(b) and not Secret(c) and not Secret(d) then
				tagGame[a] = { b, c, d }
			end
			if tagsInked then
				InkTag(self, a)
			end
		elseif type(a) == "number" and not Secret(a) and not Secret(b) and not Secret(c) then
			for _, tag in ipairs(TAGS) do
				tagGame[tag] = { a, b, c }
				if tagsInked then
					InkTag(self, tag)
				end
			end
		end
	end)
	-- a font object set again (the large book's fonts) may bring its own colour
	if html.SetFontObject then
		hooksecurefunc(html, "SetFontObject", function(self, a)
			if tagSetting or not tagsInked then
				return
			end
			if type(a) == "string" then
				InkTag(self, a)
			else
				for _, tag in ipairs(TAGS) do
					InkTag(self, tag)
				end
			end
		end)
	end
end

local function InkOn()
	return active and skin ~= nil and skin.win ~= nil and skin.win.paper == true
end

local function InkRoots()
	return _G.ItemTextScrollFrame
end

-- the SimpleHTML's own strings are inked by kind (above), never one by one
local function InkSkip(fs)
	local html = Html()
	if html and IsUnder(fs, html) then
		return true
	end
	return MelloUI.QuestInk.DefaultSkip(fs)
end

local function Surface()
	local QI = MelloUI.QuestInk
	if not (QI and QI.Surface) then
		InkTags(InkOn())
		return
	end
	if not surfaceMade then
		surfaceMade = true
		QI.Surface(AREA, { on = InkOn, sheet = true, skip = InkSkip, roots = InkRoots, onRefresh = InkTags })
	else
		QI.RefreshSurface(AREA)
	end
end

--------------------------------------------------------------------------------
-- Building the skin
--------------------------------------------------------------------------------
local function Refresh()
	local win = active and skin and skin.win
	if not win then
		return
	end
	FitPageRect(win)
	UpdatePortrait(win)
	PlaceTitles(win, true)
	for _, f in ipairs(skin.followers) do
		f.rep:SetShown(f.region:IsShown())
	end
	for _, entry in ipairs(arrowReps) do
		ArrowLook(entry)
	end
	Kit:SweepControls(win.frame, Replace, skin)
	MarkRedButtons(win.frame, 0)
	if tagsInked then
		InkTags(true)
	end
	if surfaceMade then
		MelloUI.QuestInk.RefreshSurface(AREA)
	end
end

local function OnShown()
	Refresh()
	if C_Timer and C_Timer.After then
		C_Timer.After(0, Refresh)
	end
end

-- (user, 2026-09-24: dress rarely used windows on first open): nothing is
-- built while the window has never been shown this session; its first show
-- builds it (the OnShow hook in Hook, below, before its first frame is drawn)
-- and it is kept from then on.
local function Build()
	local frame = Window()
	if not frame or not Kit then
		return false
	end
	if skin then
		return true
	end
	if not frame:IsShown() then
		return false
	end
	skin = { reps = {}, followers = {} }
	local win = { frame = frame, followers = skin.followers, titleMoved = {}, titleFaded = {} }
	skin.win = win
	win.pageBg = _G.ItemTextFramePageBg
	win.rock = FindRock(frame, win.pageBg)
	local pc = frame.PortraitContainer
	local portraits = PortraitCandidates(frame)
	local first = #skin.reps + 1
	-- the rail without its body when the rock becomes the page stone (one
	-- background per window); with its body when no rock was found
	local body = nil
	if win.rock then
		body = false
	end
	win.ring = Kit:SkinWindowShell(frame, Replace, win, { portrait = (pc and pc.portrait) or portraits[1], body = body })
	for i = first, #skin.reps do
		if skin.reps[i].key == "TitleBar" then
			win.title = skin.reps[i]
		end
	end
	if win.rock then
		win.rockRep = Replace(win.rock, { as = "UI-Background-Rock", parent = frame, rect = frame, inset = Kit:OuterRailInset() })
	end
	if win.ring then
		SkinPortrait(win, frame)
	end
	-- the page
	win.pageRect = CreateFrame("Frame", nil, frame)
	win.pageRect:EnableMouse(false)
	FitPageRect(win)
	if win.pageBg then
		local art = {}
		for _, name in ipairs(MATERIALS) do
			if IsTexture(_G[name]) then
				art[#art + 1] = _G[name]
			end
		end
		win.pageRep = Replace(win.pageBg, { as = "QuestDetailsBackgrounds", rect = win.pageRect, alsoFade = art })
		win.paper = win.pageRep ~= nil
	end
	DressInset(win, frame)
	SkinArrows()
	SkinStatusBar()
	Kit:SweepControls(frame, Replace, skin)
	MarkRedButtons(frame, 0)
	HookHtml()
	return true
end

local function Activate()
	if active or not Build() then
		return
	end
	active = true
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for _, f in ipairs(skin.followers) do
		f.rep:SetShown(f.region:IsShown())
	end
	local win = skin.win
	win.pageFitted = nil
	FitPageRect(win)
	PlaceTitles(win, true)
	for _, entry in ipairs(arrowReps) do
		ArrowLook(entry)
	end
	if win.frame:IsShown() then
		UpdatePortrait(win)
	end
	Surface()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	for _, entry in ipairs(arrowReps) do
		local tex = entry.rep.object
		if tex and tex.SetAlpha then
			tex:SetAlpha(1)
		end
	end
	PlaceTitles(skin.win, false)
	-- the page's text in the game's colours again (the surface is off now)
	Surface()
	InkTags(false)
end

-- The window's hooks, installed at enable and listen-only until it is built.
-- Its first show dresses it there and then (Activate builds it), so the
-- first frame it draws is dressed -- also in combat: the build makes frames
-- and textures of ours and moves only the game's own title string, nothing
-- protected (the window was never held back for combat).
local hooked = false
local function Hook()
	local frame = Window()
	if hooked or not frame then
		return
	end
	hooked = true
	Perf.HookScript(frame, "OnShow", function()
		if M.isEnabled and not active then
			Activate()
		end
		if active then
			OnShown()
		end
	end)
	-- the game's own events: the colours are set when a text begins, the
	-- page (material, size, arrows) when it is ready
	Perf.HookScript(frame, "OnEvent", function(_, event)
		if not (active and skin) then
			return
		end
		if event == "ITEM_TEXT_BEGIN" then
			if InkOn() then
				InkTags(true)
			end
		elseif event == "ITEM_TEXT_READY" then
			skin.win.pageFitted = nil
			Refresh()
		end
	end)
end

-- The window loads with the interface (Blizzard_UIPanels_Game); wait for it
-- if not.
local events = CreateFrame("Frame")
Perf.SetScript(events, "OnEvent", function(_, event)
	if (event == "ADDON_LOADED" or event == "PLAYER_LOGIN") and M.isEnabled and not active and Window() then
		events:UnregisterEvent("ADDON_LOADED")
		events:UnregisterEvent("PLAYER_LOGIN")
		Hook()
		Activate()
	end
end)

function M:OnEnable(db)
	self.db = db
	if Window() then
		Hook()
		Activate()
	else
		events:RegisterEvent("ADDON_LOADED")
		events:RegisterEvent("PLAYER_LOGIN")
	end
end

function M:OnDisable()
	events:UnregisterEvent("ADDON_LOADED")
	events:UnregisterEvent("PLAYER_LOGIN")
	Deactivate()
end

--------------------------------------------------------------------------------
-- /itemtextdump [frames|reps|regions]: what was found and what each part was
-- dressed as -- the shell, the portrait against the medallion, the title's
-- position and font, the page (its rect, the material, the faded pieces),
-- the arrows, the page number, the bar, the scroll bar and the inked text.
-- The modes are Kit:DumpWindow's. Opens the copy window.
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
	if v == nil then
		return "nil"
	end
	if Secret(v) then
		return "[secret]"
	end
	return type(v) == "number" and string.format("%.0f", v) or tostring(v)
end

local function Shown(obj)
	local ok, s = pcall(obj.IsShown, obj)
	return (ok and not Secret(s)) and tostring(s) or "?"
end

local function RectOf(obj)
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if ok and l and not Secret(l) and not Secret(b) and not Secret(w) and not Secret(h) then
		return string.format("x=%.0f y=%.0f w=%.0f h=%.0f", l, b, w, h)
	end
	return "(no rect)"
end

local function Found(label, obj, more)
	MelloUI:Print("  %-26s %s%s", label, obj and Label(obj) or "-- not found", more or "")
end

local function RepState(rep)
	if rep == nil then
		return "not looked at"
	elseif rep == false then
		return "not dressed"
	end
	local shown = rep.object and rep.object.IsShown and rep.object:IsShown()
	return tostring(rep.key) .. (shown and " (shown)" or " (hidden)")
end

local function Colour(r, g, b)
	if type(r) ~= "number" or Secret(r) or type(g) ~= "number" or type(b) ~= "number" then
		return "?"
	end
	return string.format("%.0f %.0f %.0f", r * 255, g * 255, b * 255)
end

local function DumpShell(f)
	local win = skin and skin.win
	local okLv, lv = pcall(f.GetFrameLevel, f)
	MelloUI:Print("ItemTextFrame: shown %s, rect %s, level %s, kit %s, reps %d", Shown(f), RectOf(f),
		okLv and Num(lv) or "?", active and "on" or "off", skin and #skin.reps or 0)
	Found("outer rail (NineSlice)", f.NineSlice, f.NineSlice and (" layout " .. tostring(f.NineSlice.layoutType)) or " (no shell)")
	Found("rock -> page stone", win and win.rock, win and (" " .. RepState(win.rockRep)) or nil)
	Found("ring", win and win.ring and win.ring.object, win and win.ring and (" " .. RepState(win.ring)) or nil)
	if win and win.ring and win.ring.tex then
		local okR, rw = pcall(win.ring.tex.GetWidth, win.ring.tex)
		local disc = win.ring.disc
		local okD, dw = false, nil
		if disc then
			okD, dw = pcall(disc.GetWidth, disc)
		end
		local icon = win.icon
		local okI, iw, ih, okT, file = false, nil, nil, false, nil
		if icon then
			okI, iw, ih = pcall(icon.GetSize, icon)
			okT, file = pcall(icon.GetTexture, icon)
		end
		MelloUI:Print("  portrait vs medallion: ring %s, medallion (0.759) %s, disc %s, book %s x %s, art %s",
			okR and Num(rw) or "?", (okR and type(rw) == "number" and not Secret(rw)) and string.format("%.0f", rw * 0.759) or "?",
			okD and Num(dw) or "none", okI and Num(iw) or "?", okI and Num(ih) or "?", okT and Num(file) or "?")
		for _, t in ipairs(win.portraits or {}) do
			local okF, art = pcall(t.GetTexture, t)
			Found("  game portrait", t, string.format(" art %s, alpha %s, faded %s", okF and Num(art) or "?", Num(t:GetAlpha()), tostring(Kit.faded[t] == true)))
		end
	end
	local tc = f.TitleContainer
	local title = tc and tc.TitleText
	if title then
		local text, secret = TextOf(title)
		local okF, face, size = pcall(title.GetFont, title)
		local okC, cx = pcall(title.GetCenter, title)
		local plate = win and win.title and (win.title.strip or win.title.object)
		local okP, px = false, nil
		if plate then
			okP, px = pcall(plate.GetCenter, plate)
		end
		Found("title", title, string.format(" text %s, face %s %s, title face %s, centre x %s (plate %s), plate %s",
			secret and "[secret]" or tostring(text or "(empty)"), (okF and type(face) == "string" and not Secret(face)) and face or "?",
			okF and Num(size) or "?", tostring(title.melloFontSaved ~= nil), okC and Num(cx) or "?", okP and Num(px) or "?",
			win and RepState(win.title) or "-"))
		if plate then
			MelloUI:Print("    plate rect %s, title rect %s", RectOf(plate), RectOf(title))
		end
	else
		Found("title", nil)
	end
	if win then
		for _, fs in ipairs((TitleStrings(f))) do
			local text, secret = TextOf(fs)
			Found("other title string", fs, string.format(" text %s, moved %s, faded %s", secret and "[secret]" or tostring(text or "(empty)"),
				tostring(win.titleMoved[fs] ~= nil), tostring(win.titleFaded[fs] == true)))
		end
	end
	MelloUI:Print("  tabs: none (one page); close button %s", f.CloseButton and RepState(rawget(f.CloseButton, "melloRep")) or "none")
end

local function DumpPage(f)
	local win = skin and skin.win
	local bg = _G.ItemTextFramePageBg
	local okA, atlas = false, nil
	if bg then
		okA, atlas = pcall(bg.GetAtlas, bg)
	end
	MelloUI:Print("page: material %s, on the kit's parchment %s", tostring(Material() or "?"), tostring(win and win.paper or false))
	Found("game page (PageBg)", bg, bg and string.format(" atlas %s, rect %s, shown %s, alpha %s, faded %s", (okA and not Secret(atlas)) and tostring(atlas) or "?",
		RectOf(bg), Shown(bg), Num(bg:GetAlpha()), tostring(Kit.faded[bg] == true)) or nil)
	if win then
		Found("page picture", win.pageRep and win.pageRep.tex, string.format(" %s, rect %s (large book %s)", RepState(win.pageRep),
			win.pageRect and RectOf(win.pageRect) or "?", tostring(win.pageLarge == true)))
		MelloUI:Print("    page picture per tab: no tabs -- one page, the same rect for every text")
	end
	for _, name in ipairs(MATERIALS) do
		local t = _G[name]
		local okT, file = false, nil
		if t then
			okT, file = pcall(t.GetTexture, t)
		end
		Found("material piece", t, t and string.format(" art %s, shown %s, alpha %s, faded %s", okT and Num(file) or "?", Shown(t), Num(t:GetAlpha()),
			tostring(Kit.faded[t] == true)) or nil)
	end
	local inset = f.Inset
	Found("inset", inset, inset and (" " .. RepState(rawget(inset, "melloRep"))) or nil)
	for _, entry in ipairs(ARROWS) do
		local b = _G[entry[1]]
		local okE, enabled = false, nil
		if b then
			okE, enabled = pcall(b.IsEnabled, b)
		end
		Found("page arrow", b, b and string.format(" %s, shown %s, enabled %s", RepState(rawget(b, "melloRep")), Shown(b),
			(okE and not Secret(enabled)) and tostring(enabled) or "?") or nil)
	end
	local pn = _G.ItemTextCurrentPage
	if pn then
		local text, secret = TextOf(pn)
		local okF, face, size = pcall(pn.GetFont, pn)
		Found("page number", pn, string.format(" text %s, shown %s, face %s %s, colour %s, rect %s (on the stone band, the game's gold)",
			secret and "[secret]" or tostring(text or "(empty)"), Shown(pn), (okF and type(face) == "string" and not Secret(face)) and face or "?",
			okF and Num(size) or "?", Colour(pn:GetTextColor()), RectOf(pn)))
	else
		Found("page number", nil)
	end
	local bar = _G.ItemTextStatusBar
	Found("translation bar", bar, bar and string.format(" %s, shown %s", RepState(rawget(bar, "melloRep")), Shown(bar)) or nil)
	local sf = _G.ItemTextScrollFrame
	local sb = sf and sf.ScrollBar
	Found("scroll bar", sb, sb and string.format(" %s, shown %s", RepState(rawget(sb, "melloRep")), Shown(sb)) or nil)
end

local function DumpInk()
	local html = Html()
	MelloUI:Print("ink: page text %s, inked %s", html and Label(html) or "-- not found", tostring(tagsInked))
	if html then
		for _, tag in ipairs(TAGS) do
			local c = tagGame[tag]
			local okS, _, _, _, sa = pcall(html.GetShadowColor, html, tag)
			MelloUI:Print("  %s colour now %s, the game's %s, shadow alpha %s", tag, Colour(HtmlColour(html, tag)),
				c and Colour(c[1], c[2], c[3]) or "(not seen)", (okS and type(sa) == "number" and not Secret(sa)) and string.format("%.2f", sa) or "?")
		end
		-- the SimpleHTML's own strings, where the client hands them out
		local n = 0
		for _, region in ipairs({ html:GetRegions() }) do
			if region.GetObjectType and region:GetObjectType() == "FontString" then
				n = n + 1
				if n <= 12 then
					local text, secret = TextOf(region)
					MelloUI:Print("  string %d colour %s: %s", n, Colour(region:GetTextColor()), secret and "[secret]" or tostring(text or ""):sub(1, 40))
				end
			end
		end
		MelloUI:Print("  the page text's own strings: %d", n)
	end
	local QI = MelloUI.QuestInk
	local def = QI and QI.surfaces and QI.surfaces[AREA]
	if def then
		local n = 0
		for fs in pairs(def.strings) do
			n = n + 1
			if n <= 20 then
				local text, secret = TextOf(fs)
				MelloUI:Print("  inked %s %s colour %s: %s", tostring(fs.melloInk == true), Label(fs), Colour(fs:GetTextColor()),
					secret and "[secret]" or tostring(text or ""):sub(1, 40))
			end
		end
		MelloUI:Print("ink surface: on %s, other strings %d", tostring(def.active == true), n)
	else
		MelloUI:Print("ink surface: not made")
	end
end

SLASH_MELLOITEMTEXTDUMP1 = "/itemtextdump"
SlashCmdList.MELLOITEMTEXTDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if not f then
		MelloUI:Print("/itemtextdump: ItemTextFrame is not on this client")
	elseif msg == "" then
		MelloUI:Print("Books & letters kit: module %s, dressed %s, built %s", tostring(M.isEnabled == true), tostring(active), tostring(skin ~= nil))
		if not skin then
			MelloUI:Print("ItemTextFrame: not dressed yet (the kit dresses it on its first open this session)")
		end
		DumpShell(f)
		DumpPage(f)
		DumpInk()
		MelloUI:Print("ItemTextFrame's own regions and children:")
		for _, region in ipairs({ f:GetRegions() }) do
			local kind = region:GetObjectType()
			local okL, layer, sub = pcall(region.GetDrawLayer, region)
			local what = ""
			if kind == "Texture" then
				what = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "")
			elseif kind == "FontString" then
				local text, secret = TextOf(region)
				what = "text: " .. (secret and "[secret]" or tostring(text or ""):sub(1, 40))
			end
			MelloUI:Print("  region %s %s %s/%s %s alpha %s shown %s", kind, Label(region), okL and tostring(layer) or "?", okL and tostring(sub) or "?",
				what, Num(region:GetAlpha()), Shown(region))
		end
		for _, child in ipairs({ f:GetChildren() }) do
			local okLv, lv = pcall(child.GetFrameLevel, child)
			MelloUI:Print("  child %s %s level %s shown %s kit %s", tostring(child:GetObjectType()), Label(child), okLv and Num(lv) or "?",
				Shown(child), RepState(rawget(child, "melloRep")))
		end
	else
		if not skin then
			MelloUI:Print("ItemTextFrame: not dressed yet (the kit dresses it on its first open this session)")
		end
		-- frames / reps / regions (the visible game textures): the Kit's dump
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	end
	MelloUI:ShowLog("itemtextdump " .. msg)
end
