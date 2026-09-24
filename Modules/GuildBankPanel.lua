--------------------------------------------------------------------------------
-- MelloUI - Guild Bank Kit
--
-- (user, 2026-09-24: "Bank and GUild Bank Aswell"; then "Banks and Guild Banks
-- have Tabs, make sure to get them also right, we have rules"): the guild
-- bank (GuildBankFrame, from the load-on-demand Blizzard_GuildBankUI: seven
-- columns of item slots, the bank tabs down the right side, the Guild Bank /
-- Log / Money Log / Info tabs under the window, the tab-settings icon picker)
-- dressed in the painted kit (Modules/Kit.lua) on the game's own layout, as
-- every other window is (docs/WINDOW-RULES.md): every kit piece stands in for
-- one of the game's art regions, on that region's rectangle, the game's art
-- faded in its place.
--
-- The window's source is not in the extracted interface files, so every part
-- is found at run time by its key, its global name or what it is, with
-- fallbacks, and /guildbankdump says what this client really has.
--
--   the window shell     a PortraitFrame / ButtonFrame window by
--                        Kit:SkinWindowShell; a window with its own border
--                        (corner and edge pieces, a black background) gets
--                        the same parts by hand: the outer double rail with
--                        gem corners on the window's rect, ONE page stone
--                        inside it (WINDOW-RULES 2a), the title plate on the
--                        rail with the title ON it in the title face (2c),
--                        the kit's close button
--   the ring             on the portrait corner (the shell's) or on the
--                        guild emblem's place: the guild's emblem drawn by
--                        the kit at the class medallion's size on the dark
--                        disc (2b), else the open bank tab's icon, else a
--                        bank icon -- never an empty ring
--   the item area        one stone (the page stone: the columns' own slot
--                        pictures faded, one stone per surface), the inner
--                        border on the single rail; every slot in the bags'
--                        Button Border rim with the bags' Item Background in
--                        an empty slot, the quality border kept on the icon
--   the bank tabs        every window's side tabs (common-sidetab): the gold
--                        rim at rest, the same rim additively at 0.7 on the
--                        open tab and 0.35 under the mouse, the icon fitted
--                        into the opening, all in the Side Tab Border
--   the bottom tabs      TB6 cards (Kit:SkinPanelTab; an older tab template
--                        gets the same two cards), their text held centred
--   the logs and info    the dark inner panel over the stone inside the
--                        inner rail (2e), their text at full size in the
--                        palette's text colour (names, links and money keep
--                        the colours the game writes into the lines)
--   the bottom band      the withdraw limit line and the money on the dark
--                        panel inside the outer rail; the money bars on the
--                        coin plate (B2)
--   the buttons          Deposit / Withdraw / Purchase / Save on the red
--                        plates (B1), their labels in their own colour
--   the icon picker      GuildBankPopupFrame dressed as the macros' picker:
--                        the single rail with stone, the name box on the
--                        edit plate, the icons in the Button Border
--   the rest             scroll bars, dropdowns, check boxes by the sweep
--
-- Taint: nothing of the game's is replaced or re-scripted. The skin is made
-- and kept from post-hooks (hooksecurefunc on the window's own update
-- methods and functions, HookScript, the regions' own Show / Hide) and from
-- this module's own event frame; what it keeps about the game's frames lives
-- in weak side tables (melloRep / melloNoInk are the only marks it leaves on
-- them, as every kit module); no guild bank function is called (no deposit,
-- withdrawal or tab query: the open tab's icon is read from its button).
-- Switching the module off disables every replacement (the game's art faded
-- back in, ours hidden), puts the fonts, colours, the title and the tab
-- texts back: the window is the game's again.
--
-- /guildbankdump [frames | reps | regions | slots | tabs | popup]: what the
-- window is made of on this client and what the skin dressed, in the copy
-- window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("GuildBankPanel", {
	title = "Guild Bank Kit",
	desc = "The guild bank (its tabs, slots, logs and money) in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local ADDON = "Blizzard_GuildBankUI"
local NUM_COLUMNS = 7          -- the game's columns of slots
local NUM_SLOTS = 14           -- slots per column
local MAX_TABS = 8             -- bank tabs down the right side
local TITLE_H = 20             -- a title container's height (the plate is 1.5 x it)
local TEXT_FONT = "GameFontHighlight"   -- WINDOW-RULES 2e: text at the interface's full size
local BANK_ICON = "Interface\\ICONS\\ACHIEVEMENT_GUILDPERK_MOBILEBANKING"
local RING_MIN, RING_MAX = 40, 100      -- UI px: a ring laid on the emblem's place stays a portrait's size
local DIM_ALPHA = 0.8                   -- 2e: the inner panel over the stone

local skin = nil          -- { reps = { every replacement }, followers = { { rep, region } }, ... }
local active = false
local hooked = false

-- what this module made or looked at, kept OFF the game's frames (weak keys)
local weak = { __mode = "k" }
local done = setmetatable({}, weak)         -- [frame / region] = true: looked at once
local boxHooked = setmetatable({}, weak)    -- [scroll box] = true: its callback registered
local pageHooked = setmetatable({}, weak)   -- [page] = true: its OnShow hooked
local seenDim = setmetatable({}, weak)      -- [host] = true: its dark panel made
local seenText = setmetatable({}, weak)     -- [text object] = true: made readable
local claimed = setmetatable({}, weak)      -- [game texture] = what it became (for the dump)
local fadedArt = {}                         -- game art faded with no piece on its own rect
local tabReps = {}                          -- the bottom tabs' cards { rep, region }
local bottomTabs = {}                       -- { tab, text, points (the game's last), kind, older }
local sideTabs = {}                         -- { tab, button, icon, back, rep }
local items = {}                            -- the item buttons in rims
local columns = {}                          -- { frame, background, buttons }
local iconRims = {}                         -- the icon picker's rim holders
local dims = {}                             -- { tex, label, host } the eye-strain panels
local readable = {}                         -- { obj, saved, label } text set to full size / palette
local titleMoved = {}                       -- [fs] = { points } extra title strings on the plate
local pageRects = {}                        -- [page] = the page picture's rect seen there (2a)
local stats = { items = 0, sideTabs = 0, tabs = 0, buttons = 0, plates = 0, icons = 0 }

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

-- plain numbers only (no secret, no nil)
local function Plain(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if type(v) ~= "number" or Secret(v) then
			return false
		end
	end
	return true
end

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Guild bank kit: no kit piece mapped for %s", tostring(key))
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
-- ("$parent<suffix>")
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

local function IsType(obj, kind)
	if type(obj) ~= "table" or not obj.GetObjectType then
		return false
	end
	local ok, t = pcall(obj.GetObjectType, obj)
	return ok and t == kind
end

-- the first of the objects given that is a texture / a font string
local function FirstTexture(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if IsType(v, "Texture") then
			return v
		end
	end
end

local function FirstString(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if IsType(v, "FontString") then
			return v
		end
	end
end

-- the key a region sits under in its frame's table (for the dump and to know
-- a piece of art by what the template calls it)
local function KeyOf(frame, region)
	if not (frame and region) then
		return nil
	end
	for k, v in pairs(frame) do
		if rawequal(v, region) and type(k) == "string" then
			return k
		end
	end
end

local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	if ok and type(text) == "string" and not Secret(text) then
		return text
	end
	return nil
end

-- Art faded while the kit is on with no piece on its own rect (the stone
-- stands in for the columns' pictures, the rail and stone for the window's
-- own leftover art)
local function FadeArt(obj, why)
	if not obj or done[obj] then
		return
	end
	done[obj] = true
	claimed[obj] = why or "faded"
	fadedArt[#fadedArt + 1] = obj
	if active then
		Kit:Fade(obj)
	end
end

local function Window()
	return _G.GuildBankFrame
end

local function Popup()
	return _G.GuildBankPopupFrame
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

-- a helper frame of ours spanning `a`'s TOPLEFT to `b`'s BOTTOMRIGHT (two
-- parts of the game's layout: its rect follows them)
local function Span(parent, a, b)
	local f = CreateFrame("Frame", nil, parent)
	f:EnableMouse(false)
	f:SetPoint("TOPLEFT", a, "TOPLEFT")
	f:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
	return f
end

-- a rect as text, secret-safe
local function RectText(obj)
	if not obj then
		return "-"
	end
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if ok and Plain(l, b, w, h) then
		return string.format("x=%.0f y=%.0f w=%.0f h=%.0f", l, b, w, h)
	end
	return "(no rect)"
end

-- a size the template states (readable before the window is laid out)
local function ExplicitSize(obj)
	local ok, w, h = pcall(obj.GetSize, obj)
	if ok and Plain(w, h) and w > 0 and h > 0 then
		return w, h
	end
end

-- How far into its rect the single rail's INNER edge lies, in UI px (the
-- widest of the four sides): a dark panel drawn above the rail's frame
-- starts there, so it never covers the rail's inner half
local function RailInnerEdge()
	local pre = Kit.framePrefix
	local sc = Kit.scale * Kit.frameScale
	local best = 0
	for _, side in ipairs({ "l", "r", "t", "b" }) do
		local p = Kit:Piece(pre .. "_" .. side)
		local v
		if p and p.box then
			if side == "l" then
				v = p.box[3]
			elseif side == "r" then
				v = p.w - p.box[1]
			elseif side == "t" then
				v = p.box[4]
			else
				v = p.h - p.box[2]
			end
			v = v * sc
		else
			v = Kit:RailInset(pre .. "_" .. side, side) * 2
		end
		best = math.max(best, v or 0)
	end
	return best
end

--------------------------------------------------------------------------------
-- The window's own art. A PortraitFrame / ButtonFrame window has the shell's
-- parts (NineSlice, Bg, TitleContainer, PortraitContainer); a window with its
-- own border names its pieces. These are the names the guild bank's art has
-- gone by; each is looked up as a key and as "<window name><key>".
--------------------------------------------------------------------------------
local OUTER_KEYS = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "BotLeftCorner", "BotRightCorner",
	"LeftBorder", "RightBorder", "TopBorder", "BottomBorder", "LeftEdge", "RightEdge", "TopEdge", "BottomEdge", "Left", "Right" }
local INNER_KEYS = { "TopLeftInner", "TopRightInner", "BottomLeftInner", "BottomRightInner", "LeftInner", "RightInner", "TopInner", "BottomInner" }
local BG_KEYS = { "BlackBG", "Bg", "Background", "BG", "Backdrop" }
local TITLE_BG_KEYS = { "TitleBg", "TitleBG", "TitleBackground" }
local TAB_TITLE_BG_KEYS = { "TabTitleBG", "TabTitleBg", "TabTitleBackground" }
local MONEY_BG_KEYS = { "MoneyFrameBG", "MoneyBG", "MoneyFrameBackground", "MoneyBackground" }
local LIMIT_KEYS = { "LimitLabel", "TabLimit", "WithdrawLimit", "WithdrawLimitLabel", "MoneyLimitLabel", "RemainingLabel", "MoneyUnlimitedLabel" }
local LIMIT_GLOBALS = { "GuildBankLimitLabel", "GuildBankMoneyLimitLabel", "GuildBankMoneyUnlimitedLabel", "GuildBankTabLimit", "GuildBankFrameLimitLabel" }

local function Named(f, keys)
	local list, seen = {}, {}
	for _, key in ipairs(keys) do
		local obj = Part(f, key, key)
		if type(obj) == "table" and not seen[obj] then
			seen[obj] = true
			list[#list + 1] = obj
		end
	end
	return list
end

-- The guild emblem (the window's portrait): a frame of its own, or named
-- textures -- the tabard's background / border / symbol, whole or in four
-- quarters. Returns the holder frame (or nil) and every texture of it.
local EMBLEM_KEYS = { "Emblem", "EmblemFrame", "GuildEmblem", "Tabard" }
local EMBLEM_TEXTURE_KEYS = { "TabardBackground", "TabardEmblem", "TabardBorder", "EmblemBackground", "EmblemBorder", "EmblemIcon", "EmblemSymbol" }
local EMBLEM_GLOBAL_PARTS = { "BackgroundUL", "BackgroundUR", "BackgroundBL", "BackgroundBR", "BorderUL", "BorderUR", "BorderBL", "BorderBR",
	"Icon", "Symbol", "Background", "Border", "Emblem" }

local function EmblemParts(f)
	local holder
	local parts, seen = {}, {}
	local function Add(t)
		if IsType(t, "Texture") and not seen[t] and not t.kitPiece then
			seen[t] = true
			parts[#parts + 1] = t
		end
	end
	local function AddRegionsOf(frame, depth)
		for _, region in ipairs({ frame:GetRegions() }) do
			Add(region)
		end
		if depth < 2 then
			for _, child in ipairs({ frame:GetChildren() }) do
				AddRegionsOf(child, depth + 1)
			end
		end
	end
	for _, key in ipairs(EMBLEM_KEYS) do
		local e = Part(f, key, key)
		if type(e) == "table" and not holder then
			if IsType(e, "Texture") then
				Add(e)
			elseif e.GetRegions then
				holder = e
				AddRegionsOf(e, 0)
			end
		end
	end
	if not holder and IsType(_G.GuildBankEmblemFrame, "Frame") then
		holder = _G.GuildBankEmblemFrame
		AddRegionsOf(holder, 0)
	end
	for _, key in ipairs(EMBLEM_TEXTURE_KEYS) do
		Add(Part(f, key, key))
	end
	for _, suffix in ipairs(EMBLEM_GLOBAL_PARTS) do
		Add(_G["GuildBankEmblem" .. suffix])
	end
	return holder, parts
end

-- a game portrait texture, if the window has one (the shell's container)
local function Portrait(f)
	local pc = f and f.PortraitContainer
	return FirstTexture(pc and pc.portrait, f and f.portrait, _G.GuildBankFramePortrait)
end

--------------------------------------------------------------------------------
-- The title (WINDOW-RULES 2c). The guild's name is the window's title; the
-- open tab's name has a band of its own. On a shell window the title plate's
-- rule takes its container's TitleText; on a window with its own border a
-- container of ours (the title plate is an agreed addition where the client
-- paints none) holds the title string for the rule, which centres it on the
-- plate in Kit:TitleFont (the Fonts options, the Font Style) and puts it back
-- on disable. With no guild-name string at all, the tab's name is the title.
--------------------------------------------------------------------------------
local function MainTitle(f)
	local tc = f.TitleContainer
	return FirstString(tc and tc.TitleText, f.TitleText, _G.GuildBankFrameTitle, _G.GuildBankFrameTitleText, f.Title, f.GuildName, _G.GuildBankFrameGuildName)
end

local function TabTitle(f)
	return FirstString(f.TabTitle, _G.GuildBankTabTitle, f.TabName, _G.GuildBankFrameTabTitle)
end

local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
	end
end

-- Title strings other than the plate's own (a shell window that also names a
-- title of its own): on the plate under the title, in the title face; their
-- points and font back on disable.
local function PlaceExtraTitles(on)
	if not on then
		for fs, points in pairs(titleMoved) do
			Kit:TitleFont(fs, false)
			fs:ClearAllPoints()
			for _, pt in ipairs(points) do
				fs:SetPoint(unpack(pt))
			end
		end
		wipe(titleMoved)
		return
	end
	local own = skin and skin.titleText
	if not (own and TitleRep()) then
		return
	end
	for _, fs in ipairs(skin.extraTitles or {}) do
		local text = TextOf(fs)
		if fs ~= own and text and text ~= "" and text ~= TextOf(own) then
			if not titleMoved[fs] then
				local points = {}
				for i = 1, fs:GetNumPoints() do
					points[i] = { fs:GetPoint(i) }
				end
				titleMoved[fs] = points
			end
			fs:ClearAllPoints()
			fs:SetPoint("TOP", own, "BOTTOM", 0, -2)
			Kit:TitleFont(fs, true)
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
	local text = skin.titleText
	if text and not text.melloFontSaved then
		Kit:TitleFont(text, true)
	end
	PlaceExtraTitles(true)
end

-- the plate on a window with its own border (no TitleContainer)
local function SkinOwnTitle(f)
	local main, tab = MainTitle(f), TabTitle(f)
	local text = main or tab
	skin.titleRole = main and "guild name" or (tab and "tab name (no guild-name string found)" or "none found")
	if not text then
		return
	end
	skin.titleText = text
	local tc = CreateFrame("Frame", nil, f)
	tc:EnableMouse(false)
	tc:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	tc:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	tc:SetHeight(TITLE_H)
	tc.TitleText = text   -- our container: the plate's rule reads its string here
	skin.titleContainer = tc
	local bg = FirstTexture(unpack(Named(f, TITLE_BG_KEYS)))
	if bg then
		claimed[bg] = "title plate"
		done[bg] = true
		Replace(bg, { as = "TitleBar", parent = tc, rect = tc })
	else
		Replace(tc, { as = "TitleBar", parent = tc, rect = tc, noFade = true })
	end
end

--------------------------------------------------------------------------------
-- The ring and its icon (WINDOW-RULES 2b / 2c: an empty ring is a bug). The
-- guild bank's portrait is the guild's emblem. The kit draws it in the ring
-- itself -- a texture of the ring's holder, on the dark disc at the class
-- medallion's size (Kit:RingDisc) -- from the guild's tabard (the game's own
-- SetLargeGuildTabardTextures on a texture of ours); without an emblem the
-- open bank tab's icon (read from its button), else a bank icon, round-masked.
-- The game's portrait / emblem textures are faded meanwhile, back on disable.
--------------------------------------------------------------------------------
local function TabardInfo()
	local gi = _G.C_GuildInfo
	if not (gi and gi.GetGuildTabardInfo) then
		return nil
	end
	local ok, info = pcall(gi.GetGuildTabardInfo, "player")
	if ok and type(info) == "table" and info.emblemFileID ~= nil and not Secret(info.emblemFileID) then
		return info
	end
	return nil
end

local function TabChecked(button)
	if not (button and button.GetChecked) then
		return false
	end
	local ok, c = pcall(button.GetChecked, button)
	return ok and not Secret(c) and c == true
end

-- the open bank tab's icon art (a file path or id; secret-safe)
local function SelectedTabIcon()
	for _, entry in ipairs(sideTabs) do
		if entry.icon and TabChecked(entry.button) then
			local ok, file = pcall(entry.icon.GetTexture, entry.icon)
			if ok and file ~= nil and not Secret(file) and file ~= "" and file ~= 0 then
				return file
			end
		end
	end
	return nil
end

local function UpdatePortraitArt()
	local p = skin and skin.portrait
	if not (p and active) then
		return
	end
	local okD, dw = pcall(p.disc.GetWidth, p.disc)
	local size = (okD and Plain(dw) and dw > 0) and dw or nil
	local info = TabardInfo()
	local setter = _G.SetLargeGuildTabardTextures
	if info and type(setter) == "function" and size then
		-- the emblem inside the disc; the game's function gives it its aspect
		p.emblem:SetSize(size * 0.8, size * 0.8)
		if pcall(setter, "player", p.emblem, nil, nil, info) then
			p.emblem:Show()
			p.icon:Hide()
			p.mode = "guild emblem"
			return
		end
	end
	p.emblem:Hide()
	local art = SelectedTabIcon()
	p.icon:SetTexture(art or BANK_ICON)
	p.icon:Show()
	p.mode = art and "open tab's icon" or "bank icon"
end

local function SkinPortrait(ring, gameArt)
	local holder = ring and ring.object
	if not (holder and holder.CreateTexture and ring.tex) then
		return
	end
	-- disc BACKGROUND 6, icon / emblem ARTWORK, the ring itself OVERLAY: one
	-- stack on the ring's holder, nothing of the game's between them
	local disc = Kit:RingDisc(ring, nil, holder, 6)
	if not disc then
		return
	end
	local icon = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	icon.kitPiece = true
	icon:SetAllPoints(disc)
	local mask = holder:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	icon:AddMaskTexture(mask)
	local emblem = holder:CreateTexture(nil, "ARTWORK", nil, 2)
	emblem.kitPiece = true
	emblem:SetPoint("CENTER", disc, "CENTER")
	emblem:Hide()
	skin.portrait = { disc = disc, icon = icon, emblem = emblem, gameArt = gameArt or {} }
	for _, t in ipairs(skin.portrait.gameArt) do
		claimed[t] = "portrait (the kit's ring draws it)"
	end
	local onEnable, onDisable = ring.onEnable, ring.onDisable
	ring.onEnable = function(r)
		if onEnable then
			onEnable(r)
		end
		for _, t in ipairs(skin.portrait.gameArt) do
			Kit:Fade(t)
		end
		UpdatePortraitArt()
	end
	ring.onDisable = function(r)
		if onDisable then
			onDisable(r)
		end
		for _, t in ipairs(skin.portrait.gameArt) do
			Kit:Unfade(t)
		end
	end
end

-- whether `obj` hangs on the window's top-left corner (its first anchor on
-- the window's TOPLEFT, near it): the ring then IS that corner
local function OnTopLeft(obj, f)
	local ok, point, rel, relPoint, x, y = pcall(obj.GetPoint, obj, 1)
	if not ok or not point or not Plain(x or 0, y or 0) then
		return false
	end
	rel = rel or f
	return (rel == f) and (relPoint == "TOPLEFT") and math.abs(x or 0) < 60 and math.abs(y or 0) < 60
end

-- A window with its own border: the ring on the emblem's place (sized from
-- the template's own sizes: the window may not be laid out yet). Returns the
-- ring rep and whether it stands on the window's top-left corner.
local function EmblemRing(f)
	local holder, parts = EmblemParts(f)
	skin.emblemHolder, skin.emblemParts = holder, parts
	if not holder and #parts == 0 then
		return nil, false
	end
	local anchor, point, size
	if holder then
		local w, h = ExplicitSize(holder)
		if w then
			anchor, point, size = holder, "CENTER", math.max(w, h)
		end
	end
	local ul = FirstTexture(_G.GuildBankEmblemBackgroundUL)
	if not anchor and ul then
		local w, h = ExplicitSize(ul)
		if w then
			anchor, point, size = ul, "BOTTOMRIGHT", 2 * math.max(w, h)
		end
	end
	if not anchor then
		for _, t in ipairs(parts) do
			local w, h = ExplicitSize(t)
			if w then
				anchor, point, size = t, "CENTER", math.max(w, h)
				break
			end
		end
	end
	if not anchor then
		return nil, false
	end
	size = math.min(math.max(size, RING_MIN), RING_MAX)
	local rect = CreateFrame("Frame", nil, f)
	rect:EnableMouse(false)
	rect:SetSize(size, size)
	rect:SetPoint("CENTER", anchor, point)
	skin.ringRect = rect
	for _, t in ipairs(parts) do
		claimed[t] = "emblem (the kit's ring draws it)"
		done[t] = true
	end
	local ring = Replace(rect, { as = "UI-Frame-PortraitMetal-CornerTopLeft", parent = f, rect = rect, center = rect, noFade = true, alsoFade = parts })
	return ring, OnTopLeft(holder or ul or anchor, f)
end

--------------------------------------------------------------------------------
-- The shell of a window with its own border: the outer double rail on the
-- window's rect (its corner and edge pieces faded), the page stone inside it
-- (WINDOW-RULES 2a: ONE picture fitted to the WINDOW's rect, inset by the
-- outer rail, so it never moves between pages), the title plate, the close
-- button.
--------------------------------------------------------------------------------
local function SkinOwnShell(f)
	local ring, onCorner = EmblemRing(f)
	skin.ring = ring
	local pieces = {}
	for _, t in ipairs(Named(f, OUTER_KEYS)) do
		if IsType(t, "Texture") and not done[t] then
			done[t] = true
			claimed[t] = "outer rail"
			pieces[#pieces + 1] = t
		end
	end
	skin.outerPieces = pieces
	Replace(f, { as = "NineSlicePanelTemplate", parent = f, rect = f, skip = (ring and onCorner) and "tl" or nil, body = false, noFade = true, alsoFade = pieces })
	-- the page stone: a region of the window in its background's layer (the
	-- black background the game paints), else a holder under the window's
	-- own art
	local bg
	for _, t in ipairs(Named(f, BG_KEYS)) do
		if not bg and IsType(t, "Texture") and not done[t] then
			bg = t
		end
	end
	if not bg then
		for _, region in ipairs({ f:GetRegions() }) do
			if not bg and IsType(region, "Texture") and not region.kitPiece and not done[region] then
				local ok, layer = pcall(region.GetDrawLayer, region)
				if ok and layer == "BACKGROUND" then
					bg = region
				end
			end
		end
	end
	if bg then
		done[bg] = true
		claimed[bg] = "page stone"
		skin.page = Replace(bg, { as = "UI-Background-Rock", parent = f, rect = f, inset = Kit:OuterRailInset() })
	else
		skin.page = Replace(f, { as = "UI-Background-Rock", parent = f, rect = f, inset = Kit:OuterRailInset(), noFade = true })
	end
	SkinOwnTitle(f)
	local close = f.CloseButton or _G.GuildBankFrameCloseButton
	local normal = close and close.GetNormalTexture and close:GetNormalTexture()
	if normal and close.melloRep == nil then
		close.melloRep = Replace(normal, { as = "RedButton-Exit", button = close, alsoFade = Kit:OtherTextures(close, normal) }) or false
	end
end

-- the rest of the window's own textures, once it is laid out: its background
-- layer and any picture over a quarter of the window is window art (the rail
-- and the stone stand in: faded); the rest is left and listed by the dump
local function ClassifyOwnArt(f)
	if skin.classified or f.NineSlice then
		return
	end
	local fw, fh = ExplicitSize(f)
	if not fw then
		return
	end
	skin.classified = true
	for _, region in ipairs({ f:GetRegions() }) do
		if IsType(region, "Texture") and not region.kitPiece and not done[region] then
			local okL, layer = pcall(region.GetDrawLayer, region)
			local w, h = ExplicitSize(region)
			local big = w and w * h >= fw * fh * 0.25
			if (okL and layer == "BACKGROUND") or big then
				FadeArt(region, "window art (the rail and stone stand in)")
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The item area. The inner border round the columns (its corner and tile
-- pieces) on the single rail, edges only (one stone: the page's runs under
-- it); the columns' own slot pictures faded; every slot in the bags' rim.
--------------------------------------------------------------------------------
local function Columns(f)
	local list, seen = {}, {}
	local function Add(c)
		if type(c) == "table" and not seen[c] and c.GetChildren then
			seen[c] = true
			list[#list + 1] = c
		end
	end
	if type(f.Columns) == "table" then
		for _, c in ipairs(f.Columns) do
			Add(c)
		end
	end
	for i = 1, NUM_COLUMNS do
		Add(f["Column" .. i])
		Add(_G["GuildBankColumn" .. i])
	end
	if #list == 0 then
		-- found by what they are: frames (up to two levels down) holding a
		-- Buttons list or a Button1
		local function Walk(root, depth)
			for _, child in ipairs({ root:GetChildren() }) do
				if type(child.Buttons) == "table" or child.Button1 then
					Add(child)
				elseif depth < 2 then
					Walk(child, depth + 1)
				end
			end
		end
		Walk(f, 0)
	end
	return list
end

local function ColumnButtons(column)
	local list, seen = {}, {}
	local function Add(b)
		if type(b) == "table" and not seen[b] and b.GetObjectType then
			seen[b] = true
			list[#list + 1] = b
		end
	end
	if type(column.Buttons) == "table" then
		for _, b in ipairs(column.Buttons) do
			Add(b)
		end
	end
	local name = NameOf(column)
	for i = 1, NUM_SLOTS do
		Add(column["Button" .. i])
		Add(name and _G[name .. "Button" .. i] or nil)
	end
	if #list == 0 then
		-- found by what they are: the column's children with an icon
		for _, child in ipairs({ column:GetChildren() }) do
			if child.icon then
				Add(child)
			end
		end
	end
	return list
end

-- The grid's pitch: the smallest gap between two laid-out buttons on each
-- axis (the bags' measure), else the button's own size
local function ItemPitch(buttons)
	local a = buttons[1]
	local w, h
	if a then
		w, h = ExplicitSize(a)
	end
	if not w then
		return nil
	end
	local lefts, tops = {}, {}
	for _, b in ipairs(buttons) do
		local okP, l, t = pcall(function() return b:GetLeft(), b:GetTop() end)
		if okP and Plain(l, t) then
			lefts[#lefts + 1] = l
			tops[#tops + 1] = t
		end
	end
	local function SmallestGap(list, size)
		table.sort(list)
		local best = nil
		for i = 2, #list do
			local d = list[i] - list[i - 1]
			if d > 1 and d < size * 2 and (not best or d < best) then
				best = d
			end
		end
		return best
	end
	local pitch = { SmallestGap(lefts, w) or w, SmallestGap(tops, h) or h }
	local pad = math.max(pitch[1] - w, pitch[2] - h, 0)
	return { w + pad, h + pad }
end

-- The bags' Item Background (Backpack Kit's choice, which Dynamic UI
-- Modification also sets): read from its settings, never written
local function ItemBackground()
	local bp = MelloUI:GetModule("BackpackPanel")
	local v = bp and bp.db and bp.db.itemBackground
	if type(v) ~= "string" and MelloUI.db and MelloUI.GetModuleDB then
		local db = MelloUI:GetModuleDB("BackpackPanel")
		v = db and db.itemBackground
	end
	return type(v) == "string" and v or "stone"
end

local function ApplyItemBackground(force)
	local value = ItemBackground()
	if not force and skin and skin.itemBackground == value then
		return
	end
	if skin then
		skin.itemBackground = value
	end
	for _, button in ipairs(items) do
		Kit:SetButtonBackground(button, value)
	end
end

-- `remeasure`: the grid's pitch measured again (on show: laid out by then)
local function SkinItems(f, remeasure)
	for _, column in ipairs(Columns(f)) do
		if not done[column] then
			done[column] = true
			local entry = { frame = column, buttons = ColumnButtons(column) }
			entry.background = FirstTexture(column.Background, Part(column, nil, "Background"))
			if not entry.background then
				-- the column's picture: its first texture of its own
				for _, region in ipairs({ column:GetRegions() }) do
					if not entry.background and IsType(region, "Texture") and not region.kitPiece then
						entry.background = region
					end
				end
			end
			-- one stone per surface: the page's stone runs under the grid
			FadeArt(entry.background, "column picture (the page stone stands in)")
			columns[#columns + 1] = entry
		end
	end
	local all, fresh = {}, false
	for _, entry in ipairs(columns) do
		for _, b in ipairs(entry.buttons) do
			all[#all + 1] = b
			fresh = fresh or b.melloRep == nil
		end
	end
	if #all == 0 or not (fresh or remeasure) then
		return
	end
	local pitch = ItemPitch(all)
	for _, button in ipairs(all) do
		if button.melloRep == nil and button.icon then
			local rep = Kit:SkinActionButton(button, Replace, pitch, { as = Kit:ButtonRimRule(), emptyStone = true, qualityBorder = button.IconBorder })
			if rep then
				items[#items + 1] = button
				stats.items = stats.items + 1
				Kit:SetButtonBackground(button, ItemBackground())
			end
		elseif button.melloRep and button.melloRep.SetPitch and pitch then
			button.melloRep:SetPitch(pitch[1], pitch[2])
		end
	end
end

-- The inner border (the corner / tile pieces round the item area): the
-- single rail, edges only; and the item area's rect for the dark panels
local function SkinInnerBorder(f)
	local pieces = {}
	for _, t in ipairs(Named(f, INNER_KEYS)) do
		if IsType(t, "Texture") and not done[t] then
			pieces[#pieces + 1] = t
		end
	end
	local tl = FirstTexture(Part(f, "TopLeftInner", "TopLeftInner"))
	local br = FirstTexture(Part(f, "BottomRightInner", "BottomRightInner"))
	if tl and br and #pieces > 0 then
		local rect = Span(f, tl, br)
		local extra = {}
		for _, t in ipairs(pieces) do
			done[t] = true
			claimed[t] = "inner rail"
			if t ~= tl then
				extra[#extra + 1] = t
			end
		end
		skin.innerRail = Replace(tl, { as = "common-insideframe", parent = f, rect = rect, level = 0, body = false, alsoFade = extra })
		skin.area = rect
		return
	end
	-- no inner border: the item area is the columns' span
	local cols = Columns(f)
	if #cols > 1 then
		skin.area = Span(f, cols[1], cols[#cols])
	end
end

--------------------------------------------------------------------------------
-- The eye-strain panels (WINDOW-RULES 2e: "too much small text over a plain
-- brown border is just an eye strain"). The palette's inner panel over the
-- one stone (Kit:StoneDim: a tint, never a second stone) as a REGION of the
-- page that holds the text -- the log (both logs share it), the tab info,
-- the tab purchase notice -- inside the inner rail; and one of the window
-- itself behind the bottom band (the withdraw limit line and the money),
-- inside the outer rail. Each comes and goes with its page and the skin.
--------------------------------------------------------------------------------
local function Dim(host, label, rect, margin)
	if not host or seenDim[host] then
		return nil
	end
	seenDim[host] = true
	local tex = Kit:StoneDim(host, { rect = rect, margin = margin, alpha = DIM_ALPHA })
	if not tex then
		return nil
	end
	tex.kitPiece = true
	tex:SetShown(active)
	dims[#dims + 1] = { tex = tex, label = label, host = host }
	return tex
end

-- the first frame under `root` that passes `test`
local function FindFirst(root, test, depth)
	depth = depth or 0
	if not root or depth > 5 or not root.GetChildren then
		return nil
	end
	for _, child in ipairs({ root:GetChildren() }) do
		if test(child) then
			return child
		end
		local found = FindFirst(child, test, depth + 1)
		if found then
			return found
		end
	end
end

local function IsMessageFrame(obj)
	return IsType(obj, "ScrollingMessageFrame") or (obj.AddMessage ~= nil and obj.ScrollToBottom ~= nil)
end

-- the log page and its message frame, by key, by name, else by what it is
local function LogParts(f)
	local page = f.Log or f.LogFrame or _G.GuildBankLogFrame
	local msg = page and (page.MessageFrame or page.Messages or FindFirst(page, IsMessageFrame)) or _G.GuildBankMessageFrame
	if not msg then
		msg = FindFirst(f, IsMessageFrame)
	end
	if not page and msg then
		local parent = msg:GetParent()
		page = (parent and parent ~= f) and parent or msg
	end
	return page, msg
end

local function IsMultiEdit(obj)
	if not IsType(obj, "EditBox") then
		return false
	end
	local ok, multi = pcall(obj.IsMultiLine, obj)
	return ok and multi == true
end

-- the info page and its edit box, the same way
local function InfoParts(f)
	local page = f.Info or f.InfoFrame or _G.GuildBankInfo
	local sf = page and (page.ScrollFrame or page.ScrollBox)
	local edit = (sf and (sf.EditBox or (sf.GetScrollChild and sf:GetScrollChild()))) or (page and page.EditBox)
		or _G.GuildBankTabInfoEditBox or _G.GuildBankInfoEditBox
	if not IsType(edit, "EditBox") then
		edit = (page and FindFirst(page, IsMultiEdit)) or FindFirst(f, IsMultiEdit)
	end
	if not page and edit then
		local up, depth = edit, 0
		while up and up:GetParent() and up:GetParent() ~= f and depth < 4 do
			up, depth = up:GetParent(), depth + 1
		end
		page = up
	end
	return page, edit
end

local function BuyInfo(f)
	return f.BuyInfo or _G.GuildBankFrameBuyInfo or _G.GuildBankBuyInfo
end

-- The withdraw limit lines: by key, by name, else a string of the window's
-- own whose key or name speaks of a limit
local function LimitLabels(f)
	local list, seen = {}, {}
	local function Add(fs)
		if IsType(fs, "FontString") and not seen[fs] then
			seen[fs] = true
			list[#list + 1] = fs
		end
	end
	for _, key in ipairs(LIMIT_KEYS) do
		Add(Part(f, key, key))
	end
	for _, name in ipairs(LIMIT_GLOBALS) do
		Add(_G[name])
	end
	for _, region in ipairs({ f:GetRegions() }) do
		if IsType(region, "FontString") and not seen[region] then
			local label = NameOf(region) or KeyOf(f, region) or ""
			if label:find("Limit") or label:find("Remaining") then
				Add(region)
			end
		end
	end
	return list
end

-- Text at the interface's full size in the palette's text colour (2e); the
-- game's font and colour kept and put back on disable. A string already at
-- full size or larger keeps its own size. Colours the game writes into the
-- text itself (a name, a link, money) stay as they are.
local function MakeReadable(obj, label)
	if not obj or seenText[obj] then
		return
	end
	seenText[obj] = true
	local saved = {}
	local okO, fo = pcall(obj.GetFontObject, obj)
	saved.object = okO and fo or nil
	local okF, face, size, flags = pcall(obj.GetFont, obj)
	if okF and type(face) == "string" and not Secret(face) and Plain(size) then
		saved.font = { face, size, flags or "" }
	end
	local okC, r, g, b, a = pcall(obj.GetTextColor, obj)
	if okC and Plain(r, g, b) then
		saved.colour = { r, g, b, Plain(a) and a or 1 }
	end
	readable[#readable + 1] = { obj = obj, saved = saved, label = label }
end

local function ApplyReadable(entry, on)
	local obj, saved = entry.obj, entry.saved
	if on then
		local fo = _G[TEXT_FONT]
		local okT, _, target = pcall(function() return fo:GetFont() end)
		local okS, _, size = pcall(obj.GetFont, obj)
		if fo and okT and okS and Plain(target, size) and size < target - 0.5 then
			pcall(obj.SetFontObject, obj, fo)
			entry.grown = true
		end
		local c = MelloUI.Palette.text
		local okR, r, g, b = pcall(obj.GetTextColor, obj)
		local same = okR and Plain(r, g, b) and math.abs(r - c[1]) < 0.01 and math.abs(g - c[2]) < 0.01 and math.abs(b - c[3]) < 0.01
		if not same then
			pcall(obj.SetTextColor, obj, c[1], c[2], c[3])
		end
	else
		if entry.grown then
			if saved.object then
				pcall(obj.SetFontObject, obj, saved.object)
			elseif saved.font then
				pcall(obj.SetFont, obj, saved.font[1], saved.font[2], saved.font[3])
			end
			entry.grown = nil
		end
		if saved.colour then
			pcall(obj.SetTextColor, obj, saved.colour[1], saved.colour[2], saved.colour[3], saved.colour[4])
		end
	end
end

-- A page's own backdrop (its BACKGROUND pictures): faded -- every page shows
-- the window's one stone (2a: the stone must not change between tabs) under
-- its dark panel; nothing is re-pictured per page
local function FadePageArt(page, label)
	if not (page and page.GetRegions) then
		return
	end
	for _, region in ipairs({ page:GetRegions() }) do
		if IsType(region, "Texture") and not region.kitPiece and not done[region] then
			local ok, layer = pcall(region.GetDrawLayer, region)
			if ok and layer == "BACKGROUND" then
				FadeArt(region, label .. " backdrop (the page stone and dark panel stand in)")
			end
		end
	end
end

local function SkinTextAreas(f)
	local area = skin.area
	local margin = area and (skin.innerRail and RailInnerEdge() or -4) or nil
	local logPage, msg = LogParts(f)
	skin.logPage, skin.logText = logPage, msg
	FadePageArt(logPage, "log page")
	FadePageArt(InfoParts(f), "info page")
	FadePageArt(BuyInfo(f), "tab purchase notice")
	Dim(logPage, "log", area, margin)
	MakeReadable(msg, "log text")
	local infoPage, edit = InfoParts(f)
	skin.infoPage, skin.infoText = infoPage, edit
	Dim(infoPage, "tab info", area, margin)
	MakeReadable(edit, "tab info text")
	local buy = BuyInfo(f)
	skin.buyInfo = buy
	if buy then
		Dim(buy, "tab purchase notice", area, margin)
		for _, region in ipairs({ buy:GetRegions() }) do
			if IsType(region, "FontString") then
				MakeReadable(region, "tab purchase text")
			end
		end
	end
	for _, fs in ipairs(LimitLabels(f)) do
		MakeReadable(fs, "withdraw limit line")
	end
	-- the bottom band's panel: a region of the window, fitted on refresh
	-- (it needs the laid-out item area)
	if area and not skin.band then
		local tex = f:CreateTexture(nil, "BACKGROUND", nil, 2)
		tex.kitPiece = true
		local c = MelloUI.Palette.innerPanel
		tex:SetColorTexture(c[1], c[2], c[3], DIM_ALPHA)
		tex:Hide()
		skin.band = tex
		dims[#dims + 1] = { tex = tex, label = "bottom band (limit line, money)", host = f, band = true }
	end
end

-- the band from the outer rail's inside up to the item area's bottom
local function FitBand(f)
	local band, area = skin.band, skin.area
	if not (band and area) then
		return
	end
	local okA, ab = pcall(area.GetBottom, area)
	local okF, fb = pcall(f.GetBottom, f)
	if not (okA and okF and Plain(ab, fb)) then
		band:Hide()
		return
	end
	local ins = Kit:OuterRailInset()
	local top = ab - fb + (skin.innerRail and Kit:RailInset(Kit.framePrefix .. "_b", "b") or 0)
	local h = top - ins[4]
	if h <= 4 then
		band:Hide()
		return
	end
	band:ClearAllPoints()
	band:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", ins[1], ins[4])
	band:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ins[2], ins[4])
	band:SetHeight(h)
	band:SetShown(active)
end

--------------------------------------------------------------------------------
-- The tab title band (the open tab's name over the grid): the header plate
-- as a region under the name (GH1's rule); its side pieces faded with it.
-- The money bars: the coin plate (B2), the header plate under the coins
-- (its own rule on a three-piece bar frame, as the merchant's).
--------------------------------------------------------------------------------
local function SkinBand(f, keys, label)
	local mid = Named(f, keys)[1]
	if not mid or done[mid] then
		return nil
	end
	done[mid] = true
	claimed[mid] = label
	if IsType(mid, "Texture") then
		local name = NameOf(mid)
		local key = KeyOf(f, mid)
		local left = FirstTexture(name and _G[name .. "Left"], key and f[key .. "Left"])
		local right = FirstTexture(name and _G[name .. "Right"], key and f[key .. "Right"])
		local rect = (left and right) and Span(f, left, right) or mid
		for _, t in ipairs(List(left, right)) do
			claimed[t], done[t] = label, true
		end
		return Replace(mid, { as = "GuildFrame-Header", rect = rect, alsoFade = List(left, right) })
	end
	-- a bar frame of three pieces (ThinGoldEdgeTemplate): the coin plate's rule
	local m = FirstTexture(Part(mid, "Middle", "Middle"))
	if m then
		return Replace(m, { as = "common-coinbox-center", rect = mid, alsoFade = List(Part(mid, "Left", "Left"), Part(mid, "Right", "Right")) })
	end
	return nil
end

local function SkinMoneyBars(f)
	if SkinBand(f, MONEY_BG_KEYS, "coin plate") then
		stats.plates = stats.plates + 1
	end
	-- a named three-piece background under a money frame
	for _, base in ipairs({ "GuildBankMoneyFrameBackground", "GuildBankWithdrawMoneyFrameBackground" }) do
		local mid = FirstTexture(_G[base .. "Middle"], _G[base])
		if mid and not done[mid] then
			done[mid] = true
			claimed[mid] = "coin plate"
			local left, right = FirstTexture(_G[base .. "Left"]), FirstTexture(_G[base .. "Right"])
			local rect = (left and right) and Span(f, left, right) or mid
			if Replace(mid, { as = "GuildFrame-Header", rect = rect, alsoFade = List(left, right) }) then
				stats.plates = stats.plates + 1
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The bank tabs (square icon tabs down the right side: a frame with its tab
-- picture and a check button holding the icon). Every window's side tab
-- (common-sidetab, Kit:RegisterSideTab through the rule): the gold rim at
-- rest on every tab, the same rim additively at 0.7 on the open one (the
-- game checks its button) and 0.35 under the mouse; the tab at the Character
-- window's tab size, the icon fitted into the opening and fitted again after
-- the game's press / release and any re-anchoring; all in the Side Tab
-- Border. A tab the player may not view, or the "buy a tab" tab, keeps the
-- icon the game gives it (desaturated, the new-tab glyph) in the same rim.
--------------------------------------------------------------------------------
local function SideTabList(f)
	local list, seen = {}, {}
	local function Add(t)
		if type(t) == "table" and not seen[t] and t.GetObjectType then
			seen[t] = true
			list[#list + 1] = t
		end
	end
	if type(f.BankTabs) == "table" then
		for _, t in ipairs(f.BankTabs) do
			Add(t)
		end
	end
	for i = 1, MAX_TABS do
		Add(_G["GuildBankTab" .. i])
	end
	if #list == 0 then
		-- found by what they are: children holding a check button with an icon
		for _, child in ipairs({ f:GetChildren() }) do
			local b = child.Button
			if IsType(b, "CheckButton") and (b.IconTexture or b.icon or b.Icon) then
				Add(child)
			end
		end
	end
	return list
end

local function SideTabParts(tab)
	local name = NameOf(tab)
	local button = tab.Button or (name and _G[name .. "Button"]) or (IsType(tab, "CheckButton") and tab) or nil
	local bname = NameOf(button)
	local icon = button and FirstTexture(button.IconTexture, button.Icon, button.icon, bname and _G[bname .. "IconTexture"], bname and _G[bname .. "Icon"])
	local back = FirstTexture(tab ~= button and tab.Background or nil, name and _G[name .. "Background"])
	return button, icon, back
end

local function SkinSideTab(tab)
	if not tab or done[tab] then
		return
	end
	done[tab] = true
	local button, icon, back = SideTabParts(tab)
	local entry = { tab = tab, button = button, icon = icon, back = back }
	sideTabs[#sideTabs + 1] = entry
	if not button then
		entry.why = "no button found"
		return
	end
	if button.melloRep ~= nil then
		entry.why = "already dressed"
		return
	end
	-- (marked at once: the sweep would take a 36 px check button for a check box)
	button.melloRep = false
	if not icon then
		entry.why = "no icon found"
		return
	end
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	local plate = back or normal
	if not plate then
		entry.why = "no tab picture found"
		return
	end
	-- everything the game draws round the icon gives way to the rim: its tab
	-- picture, the quickslot frame, the pushed / highlight / checked looks
	local extra = {}
	local seen = { [plate] = true, [icon] = true }
	local function Add(t)
		if t and not seen[t] and IsType(t, "Texture") and not t.kitPiece then
			seen[t] = true
			extra[#extra + 1] = t
		end
	end
	Add(normal)
	Add(button.GetPushedTexture and button:GetPushedTexture())
	Add(button.GetHighlightTexture and button:GetHighlightTexture())
	Add(button.GetCheckedTexture and button:GetCheckedTexture())
	for _, holder in ipairs(List(tab, button ~= tab and button or nil)) do
		for _, region in ipairs({ holder:GetRegions() }) do
			Add(region)
		end
	end
	for _, t in ipairs(extra) do
		claimed[t] = "side tab (the rim stands in)"
	end
	claimed[plate] = "side tab rim"
	local rep = Replace(plate, { as = "common-sidetab", button = button, parent = button, rect = button, icon = icon,
		checked = function() return TabChecked(button) end, alsoFade = extra })
	button.melloRep = rep or false
	entry.rep = rep
	if not rep then
		entry.why = "no replacement"
		return
	end
	stats.sideTabs = stats.sideTabs + 1
	-- the press / release: the icon back into the opening (the rule fits it
	-- again after the game's own anchoring methods and every SetPoint on it;
	-- the scripts here as well)
	local function Refit()
		local rim = rep.object
		if active and rim and rim.IsShown and rim:IsShown() and rim.icon then
			Kit:SlotPlaceIcon(rim)
		end
	end
	button:HookScript("OnMouseDown", Refit)
	button:HookScript("OnMouseUp", Refit)
	button:HookScript("OnShow", Refit)
	-- the open tab's icon is the ring's fallback: read again as it changes
	if button.SetChecked then
		hooksecurefunc(button, "SetChecked", function()
			if skin and skin.portrait and skin.portrait.mode ~= "guild emblem" then
				UpdatePortraitArt()
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- The bottom tabs (Guild Bank / Log / Money Log / Info). TB6 cards by
-- Kit:SkinPanelTab (PanelTabButtonTemplate), the text held centred on the
-- card; an older tab template (Left for the closed tab, LeftDisabled for the
-- open one) gets the same two cards and its text held centred here. The
-- cards follow their tab's textures on every Show / Hide, also while the kit
-- is off: after those hooks, every card is set from its texture while the
-- kit is on and hidden while it is off (the macros' guard). The game's own
-- placing of each tab's text is recorded and put back on disable.
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

local function PointsOf(fs)
	local points = {}
	for i = 1, fs:GetNumPoints() do
		points[i] = { fs:GetPoint(i) }
	end
	return points
end

local function SkinTab(tab)
	if not tab or done[tab] then
		return
	end
	done[tab] = true
	local name = NameOf(tab)
	local text = FirstString(tab.Text, name and _G[name .. "Text"], tab.GetFontString and tab:GetFontString() or nil)
	local entry = { tab = tab, text = text }
	bottomTabs[#bottomTabs + 1] = entry
	-- the game's own placing of the text, recorded before any card holds it
	-- (the Kit's steadier marks its own SetPoint with melloSteadying)
	if text then
		entry.points = PointsOf(text)
		hooksecurefunc(text, "SetPoint", function()
			if not (tab.melloSteadying or entry.steadying) then
				entry.points = PointsOf(text)
			end
		end)
	end
	local plainTex, openTex
	local first = #skin.followers + 1
	if tab.Left and tab.LeftActive then
		plainTex, openTex = tab.Left, tab.LeftActive
		entry.kind = "TB6 (PanelTabButtonTemplate)"
		Kit:SkinPanelTab(tab, Replace, skin)
	else
		plainTex, openTex = FirstTexture(Part(tab, "Left", "Left")), FirstTexture(Part(tab, "LeftDisabled", "LeftDisabled"))
		if not (plainTex and openTex) or tab.melloRep ~= nil then
			entry.kind = "unknown template: left as the game's"
			-- (marked: the sweep would take a Left / Middle / Right tab for a red button)
			if tab.melloRep == nil then
				tab.melloRep = false
			end
			return
		end
		entry.kind = "TB6 (older template: Left / LeftDisabled)"
		entry.older = true
		local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
		local plain = Replace(plainTex, { as = "uiframe-tab-left", rect = tab, button = tab,
			alsoFade = List(Part(tab, "Middle", "Middle"), Part(tab, "Right", "Right"), hl) })
		local open = Replace(openTex, { as = "uiframe-activetab-left", rect = tab,
			alsoFade = List(Part(tab, "MiddleDisabled", "MiddleDisabled"), Part(tab, "RightDisabled", "RightDisabled")) })
		tab.melloRep = plain or open or false
		Follow(plain, plainTex)
		Follow(open, openTex)
		-- the text centred on the card, whatever the game's select / deselect
		-- nudge (as Kit:SkinPanelTab does for the newer template)
		if text and (plain or open) then
			local function Steady()
				if entry.steadying or not active then
					return
				end
				entry.steadying = true
				local okP, _, _, _, x = pcall(text.GetPoint, text, 1)
				text:ClearAllPoints()
				text:SetPoint("CENTER", tab, "CENTER", (okP and Plain(x)) and x or 0, 0)
				entry.steadying = nil
			end
			hooksecurefunc(text, "SetPoint", Steady)
			entry.steady = Steady
		end
	end
	entry.plainTex, entry.openTex = plainTex, openTex
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

local function BottomTabList(f)
	local list, seen = {}, {}
	local function Add(t)
		if type(t) == "table" and not seen[t] then
			seen[t] = true
			list[#list + 1] = t
		end
	end
	for i = 1, 4 do
		Add(_G["GuildBankFrameTab" .. i])
	end
	if type(f.Tabs) == "table" then
		for _, t in ipairs(f.Tabs) do
			Add(t)
		end
	end
	return list
end

-- the open bottom tab: the game's PanelTemplates selection, else the tab
-- whose open look shows
local function OpenBottomTab(f)
	local sel = f.selectedTab
	if Plain(sel) then
		local tab = _G["GuildBankFrameTab" .. sel] or (type(f.Tabs) == "table" and f.Tabs[sel]) or nil
		return sel, tab
	end
	for i, entry in ipairs(bottomTabs) do
		local open = entry.openTex
		if open and open:IsShown() then
			return i, entry.tab
		end
	end
	return nil, nil
end

-- (on show / enable) the text of each Kit-dressed tab put through its
-- steadier again: the Kit centres it after the game's SetPoint only
local function SteadyTabTexts()
	for _, entry in ipairs(bottomTabs) do
		if entry.steady then
			entry.steady()
		elseif entry.text and entry.kind and not entry.older and entry.points and entry.points[1] then
			entry.steadying = true
			pcall(entry.text.SetPoint, entry.text, unpack(entry.points[1]))
			entry.steadying = nil
		end
	end
end

-- the game's text placing back on the tabs (on disable)
local function RestoreTabTexts()
	for _, entry in ipairs(bottomTabs) do
		local text, points = entry.text, entry.points
		if text and points and #points > 0 then
			entry.steadying = true
			text:ClearAllPoints()
			for _, pt in ipairs(points) do
				text:SetPoint(unpack(pt))
			end
			entry.steadying = nil
		end
	end
end

--------------------------------------------------------------------------------
-- The buttons: Deposit, Withdraw, the tab purchase and the info's Save on
-- the red plates (B1, Kit:SkinRedButton), each marked melloNoInk (a button's
-- label keeps its own colour, never the parchment's ink); the plate follows
-- the button's disabled state.
--------------------------------------------------------------------------------
local function RedButtons(f)
	local buy = BuyInfo(f)
	local infoPage = InfoParts(f)
	return List(f.DepositButton, _G.GuildBankFrameDepositButton, f.WithdrawButton, _G.GuildBankFrameWithdrawButton,
		buy and buy.PurchaseButton, _G.GuildBankFramePurchaseButton, infoPage and infoPage.SaveButton, _G.GuildBankInfoSaveButton)
end

local function SkinButtons(f)
	for _, b in ipairs(RedButtons(f)) do
		if not done[b] and b.GetObjectType then
			done[b] = true
			b.melloNoInk = true
			if b.melloRep == nil and Kit:SkinRedButton(b, Replace) then
				stats.buttons = stats.buttons + 1
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The tab settings (GuildBankPopupFrame, the icon selector popup): dressed as
-- the macros' picker -- its box (the popup's own art and its BorderBox) on
-- the single rail with its stone, the name box on the edit plate (its left
-- cap, the search glass, dropped), the current icon and the grid in the
-- Button Border hugging each icon, gold on the chosen one; Okay / Cancel and
-- the scroll bar by the sweep.
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
	if not (p and l and ok and Plain(iw, ih)) or iw <= 0 or ih <= 0 then
		return
	end
	rim:ClearAllPoints()
	rim:SetPoint("CENTER", icon, "CENTER")
	rim:SetSize((iw - 4) * p.w / (p.w - l - r), (ih - 4) * p.h / (p.h - t - b))
end

-- a new Button Border has a new opening: every picker rim fitted again
Kit:OnBorderChanged("button", function()
	for _, holder in ipairs(iconRims) do
		FitIconRim(holder)
	end
end)

local function IconOf(button)
	local icon = button.Icon or button.icon
	if not icon then
		local name = NameOf(button)
		icon = name and _G[name .. "Icon"] or nil
	end
	if not icon and button.GetNormalTexture then
		icon = button:GetNormalTexture()
	end
	return icon
end

local function BackOf(button, icon)
	for _, region in ipairs({ button:GetRegions() }) do
		if region ~= icon and IsType(region, "Texture") and not region.kitPiece then
			local ok, layer = pcall(region.GetDrawLayer, region)
			if ok and layer == "BACKGROUND" then
				return region
			end
		end
	end
end

local function SkinIconButton(button, selectable)
	if not button or done[button] or button.melloRep ~= nil then
		return
	end
	done[button] = true
	local icon = IconOf(button)
	local back = BackOf(button, icon)
	if not (icon and back) then
		return
	end
	local extra = {}
	local glow = button.Highlight or (button.GetHighlightTexture and button:GetHighlightTexture())
	if glow then
		extra[#extra + 1] = glow
	end
	local checkedTex = button.GetCheckedTexture and button:GetCheckedTexture()
	if checkedTex then
		extra[#extra + 1] = checkedTex
	end
	local sel = selectable and button.SelectedTexture or nil
	if sel then
		extra[#extra + 1] = sel
	end
	local checked
	if sel then
		checked = function() return sel:IsShown() end
	elseif selectable and button.GetChecked then
		checked = function() return TabChecked(button) end
	end
	local rep = Replace(back, { as = Kit:ButtonRimRule(), button = button, parent = button, checked = checked, alsoFade = extra })
	button.melloRep = rep or false
	if not rep then
		return
	end
	local holder = { melloRep = rep, icon = icon }
	iconRims[#iconRims + 1] = holder
	Kit:RegisterButtonRim(holder)
	FitIconRim(holder)
	stats.icons = stats.icons + 1
	local function Update()
		local rim = holder.melloRep.object
		if active and rim and rim.Update then
			rim:Update()
		end
	end
	if sel then
		hooksecurefunc(sel, "Show", Update)
		hooksecurefunc(sel, "Hide", Update)
		hooksecurefunc(sel, "SetShown", Update)
	elseif checked and button.SetChecked then
		hooksecurefunc(button, "SetChecked", Update)
	end
end

local function PopupBox(popup)
	return popup and popup.IconSelector and popup.IconSelector.ScrollBox or nil
end

local function PopupEdit(popup)
	local box = popup.BorderBox
	return (box and box.IconSelectorEditBox) or popup.IconSelectorEditBox or popup.EditBox or _G.GuildBankPopupEditBox
end

local function WalkBox(box, selectable)
	if not (box and box.ForEachFrame) then
		return
	end
	if box.HasView and not box:HasView() then
		return
	end
	pcall(box.ForEachFrame, box, function(frame)
		SkinIconButton(frame, selectable)
	end)
end

local function HookBox(box, selectable)
	if not box or boxHooked[box] or not ScrollUtil then
		return
	end
	local add = ScrollUtil.AddInitializedFrameCallback or ScrollUtil.AddAcquiredFrameCallback
	if not add then
		return
	end
	boxHooked[box] = true
	add(box, function(_, frame)
		if active then
			SkinIconButton(frame, selectable)
		end
	end, M, false)
end

-- The name box: the S1 edit plate with its LEFT cap dropped (a name box,
-- not a search box), spanning the game's box art past the edit box's ends
local function SkinPopupEdit(popup)
	local edit = PopupEdit(popup)
	if not edit or done[edit] then
		return
	end
	done[edit] = true
	local left = edit.IconSelectorPopupNameLeft
	local mid = edit.IconSelectorPopupNameMiddle
	local right = edit.IconSelectorPopupNameRight
	if not mid then
		-- another template: the widest texture is the middle, the rest its ends
		local textures = {}
		for _, region in ipairs({ edit:GetRegions() }) do
			if IsType(region, "Texture") and not region.kitPiece then
				textures[#textures + 1] = region
			end
		end
		local best = 0
		for _, tex in ipairs(textures) do
			local ok, w = pcall(tex.GetWidth, tex)
			if ok and Plain(w) and w > best then
				mid, best = tex, w
			end
		end
		local ends = {}
		for _, tex in ipairs(textures) do
			if tex ~= mid then
				ends[#ends + 1] = tex
			end
		end
		left, right = ends[1], ends[2]
	end
	if not mid then
		return
	end
	local reach = 0
	if left then
		local ok, _, _, _, x = pcall(left.GetPoint, left, 1)
		if ok and Plain(x) and x < 0 then
			reach = -x
		end
	end
	local rect = CreateFrame("Frame", nil, edit)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", edit, "TOPLEFT", -reach, 0)
	rect:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", reach, 0)
	Replace(mid, { as = "UI-ChatInputBorder-Mid2", rect = rect, parent = edit, edit = edit, dropCap = "l", alsoFade = List(left, right) })
end

local function SkinPopup()
	local popup = Popup()
	if not popup or done[popup] then
		return
	end
	done[popup] = true
	-- the popup's box: its own textures and its BorderBox's; the rail and
	-- stone on a holder at the popup's own level (under the BorderBox, its
	-- texts and the current icon, under the icon grid)
	local extra = {}
	for _, holder in ipairs(List(popup, popup.BorderBox)) do
		for _, region in ipairs({ holder:GetRegions() }) do
			if IsType(region, "Texture") and not region.kitPiece then
				extra[#extra + 1] = region
			end
		end
	end
	Replace(popup.BorderBox or popup, { as = "common-insideframe", parent = popup, rect = popup, level = 0, body = true, noFade = true, alsoFade = extra })
	SkinPopupEdit(popup)
	local area = popup.BorderBox and popup.BorderBox.SelectedIconArea
	SkinIconButton(area and area.SelectedIconButton, false)
	local grid = PopupBox(popup)
	HookBox(grid, true)
	if active then
		WalkBox(grid, true)
	end
	-- the older named buttons, should this client's picker have them
	for i = 1, 200 do
		local b = _G["GuildBankPopupButton" .. i]
		if not b then
			break
		end
		SkinIconButton(b, true)
	end
	popup:HookScript("OnShow", function(self)
		if active then
			WalkBox(PopupBox(self), true)
			Kit:SweepControls(self, Replace, skin, PopupBox(self))
		end
	end)
	Kit:SweepControls(popup, Replace, skin, PopupBox(popup))
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

	-- the shell
	if f.NineSlice then
		skin.shellKind = "PortraitFrame / ButtonFrame shell (Kit:SkinWindowShell)"
		local portrait = Portrait(f)
		Kit:SkinWindowShell(f, Replace, skin, { portrait = portrait, bg = f.Bg and "UI-Background-Rock" or nil })
		for _, rep in ipairs(skin.reps) do
			if rep.key == "UI-Background-Rock" then
				skin.page = rep
			end
		end
		local tc = f.TitleContainer
		skin.titleText = tc and tc.TitleText or nil
		skin.titleRole = skin.titleText and "the title container's" or "none found"
		skin.extraTitles = List(FirstString(f.TitleText), FirstString(_G.GuildBankFrameTitle), FirstString(_G.GuildBankFrameTitleText))
		local holder, parts = EmblemParts(f)
		skin.emblemHolder, skin.emblemParts = holder, parts
		local art = { portrait }
		for _, t in ipairs(parts) do
			art[#art + 1] = t
		end
		SkinPortrait(skin.ring, art)
	else
		skin.shellKind = "own border (the shell's parts by hand)"
		SkinOwnShell(f)
		SkinPortrait(skin.ring, {})
	end

	-- the item area: its border, the columns, the slots
	SkinInnerBorder(f)
	SkinItems(f, true)

	-- the open tab's name on its band (or, should that name be the window's
	-- title, the band faded under the plate), the money on the coin plate
	local tabTitle = TabTitle(f)
	if tabTitle and skin.titleText == tabTitle then
		for _, t in ipairs(Named(f, TAB_TITLE_BG_KEYS)) do
			if IsType(t, "Texture") then
				FadeArt(t, "tab title band (its name is on the title plate)")
			end
		end
	else
		SkinBand(f, TAB_TITLE_BG_KEYS, "tab title plate")
	end
	SkinMoneyBars(f)

	-- the tabs (before the sweep: it would take a tab's check button for a
	-- check box, an older bottom tab for a red button)
	for _, tab in ipairs(SideTabList(f)) do
		SkinSideTab(tab)
	end
	for _, tab in ipairs(BottomTabList(f)) do
		SkinTab(tab)
	end

	SkinButtons(f)
	SkinTextAreas(f)
	SkinPopup()

	-- every common control left (scroll bars, dropdowns, check boxes); the
	-- picker is swept on its own
	Kit:SweepControls(f, Replace, skin, Popup())
end

-- the page picture's rect on the open page, kept per page (2a)
local function RecordPage(f)
	local rep = skin and skin.page
	if not (rep and rep.inner and f:IsShown()) then
		return
	end
	local idx, tab = OpenBottomTab(f)
	local label = "page " .. tostring(idx or "?")
	for _, e in ipairs(bottomTabs) do
		if e.tab == tab and e.text and TextOf(e.text) then
			label = label .. " (" .. TextOf(e.text) .. ")"
		end
	end
	pageRects[label] = RectText(rep.inner)
end

-- After every show and every game refresh (a tab or page switch, a deposit,
-- the logs arriving): what the game re-laid or re-showed since. `full` (on
-- show): the grid measured again and the controls swept.
local function RefreshNow(full)
	local f = Window()
	if not (active and skin and f) then
		return
	end
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	GuardTabs()
	ClassifyOwnArt(f)
	SkinItems(f, full)
	ApplyItemBackground(false)
	for _, entry in ipairs(sideTabs) do
		local rim = entry.rep and entry.rep.object
		if rim and rim.Update then
			rim:Update()
		end
	end
	for _, entry in ipairs(readable) do
		ApplyReadable(entry, true)
	end
	FitBand(f)
	UpdatePortraitArt()
	PlaceTitle()
	SkinPopup()
	local popup = Popup()
	if popup and popup:IsShown() then
		WalkBox(PopupBox(popup), true)
	end
	if full then
		SteadyTabTexts()
		Kit:SweepControls(f, Replace, skin, Popup())
	end
	RecordPage(f)
end

-- one pass pending at a time, on the next frame (after the game's own
-- handler and layout; the game refreshes on every slot change). Called by
-- the hooks with their own arguments: only a literal `true` asks for a full
-- pass.
local function Refresh(full)
	if not (active and skin) then
		return
	end
	if full == true then
		skin.full = true
	end
	if skin.pending then
		return
	end
	skin.pending = true
	C_Timer.After(0, function()
		if not skin then
			return
		end
		skin.pending = nil
		local wantFull = skin.full
		skin.full = nil
		local f = Window()
		if active and f and f:IsShown() then
			RefreshNow(wantFull)
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
	for _, d in ipairs(dims) do
		if not d.band then
			d.tex:Show()
		end
	end
	ApplyItemBackground(true)
	RefreshNow(true)
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
	for _, d in ipairs(dims) do
		d.tex:Hide()
	end
	for _, entry in ipairs(readable) do
		ApplyReadable(entry, false)
	end
	-- the tabs' cards hidden for good while off and the game's text placing
	-- back; the extra titles back (the plate's rule put its own string back,
	-- the ring's onDisable the portrait art)
	GuardTabs()
	RestoreTabTexts()
	PlaceExtraTitles(false)
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

-- the window's own refresh methods and functions (whichever this client has)
local METHODS = { "Update", "UpdateTabs", "UpdateTabBuyingInfo", "UpdateTabInfo", "UpdateLog", "UpdateMoneyLog", "UpdateWithdrawMoney",
	"UpdateMoney", "UpdateFiltered", "SelectTab", "SetMode" }
local FUNCTIONS = { "GuildBankFrame_Update", "GuildBankFrame_UpdateTabs", "GuildBankFrame_UpdateLog", "GuildBankFrame_UpdateMoneyLog",
	"GuildBankFrame_UpdateTabBuyingInfo", "GuildBankFrame_UpdateTabInfo", "GuildBankFrame_UpdateWithdrawMoney", "GuildBankFrameTab_OnClick",
	"GuildBankTab_OnClick", "GuildBankFrame_SelectAvailableTab" }

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
		Refresh(true)
	end)
	for _, method in ipairs(METHODS) do
		if type(f[method]) == "function" then
			hooksecurefunc(f, method, Refresh)
		end
	end
	for _, fname in ipairs(FUNCTIONS) do
		if type(_G[fname]) == "function" then
			hooksecurefunc(fname, Refresh)
		end
	end
	-- the pages as they show (the logs, the info, the tab purchase notice)
	local logPage = LogParts(f)
	local infoPage = InfoParts(f)
	for _, page in ipairs(List(logPage, infoPage, BuyInfo(f))) do
		if page.HookScript and not pageHooked[page] then
			pageHooked[page] = true
			page:HookScript("OnShow", function()
				Refresh()
			end)
		end
	end
end

-- Blizzard_GuildBankUI is loaded on demand (the first visit to a guild
-- vault): dressed as it loads; the bank's own events bring a refresh on the
-- next frame (registered one by one: a client without one refuses it)
local EVENTS = { "GUILDBANKBAGSLOTS_CHANGED", "GUILDBANK_UPDATE_TABS", "GUILDBANKLOG_UPDATE", "GUILDBANK_UPDATE_MONEY",
	"GUILDBANK_UPDATE_WITHDRAWMONEY", "GUILDBANK_UPDATE_TEXT", "GUILDBANK_TEXT_CHANGED", "GUILDTABARD_UPDATE", "GUILDBANK_ITEM_LOCK_CHANGED" }
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, addon)
	if event == "ADDON_LOADED" then
		if addon == ADDON then
			Hook()
			if M.isEnabled then
				SyncSafe()
			end
		end
		return
	end
	Refresh()
end)
eventFrame:RegisterEvent("ADDON_LOADED")
for _, ev in ipairs(EVENTS) do
	pcall(eventFrame.RegisterEvent, eventFrame, ev)
end

-- the bags' Item Background changed (Backpack Kit's option, or Dynamic UI
-- Modification's picker): the guild bank's empty slots follow at once
hooksecurefunc(MelloUI, "NotifySettingChanged", function(_, name, key)
	if name == "BackpackPanel" and key == "itemBackground" and active then
		ApplyItemBackground(true)
	end
end)

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
-- /guildbankdump [frames | reps | regions | slots | tabs | popup]: with no
-- mode, what the skin found and dressed (every part, found or not, and its
-- state) and the window's own regions and children, each texture with what
-- it became (UNMAPPED: left as the game's); "slots" the columns and their
-- buttons; "tabs" every tab (side and bottom) and the page picture's rect on
-- each page seen (2a); "popup" the icon picker; the other modes are
-- Kit:DumpWindow's. Opens the copy window.
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
	MelloUI:Print("  %-28s %s%s", label, obj and Label(obj) or "-- not found", more or "")
end

local function Shown(obj)
	if not obj then
		return "-"
	end
	local ok, s = pcall(obj.IsShown, obj)
	return (ok and not Secret(s)) and tostring(s) or "?"
end

local function Dressed(obj)
	return tostring(obj ~= nil and obj.melloRep ~= nil and obj.melloRep ~= false)
end

local function Num(v)
	return Plain(v) and string.format("%.0f", v) or "?"
end

local function ArtOf(region)
	local key = Kit:ArtKey(region)
	if key == nil then
		local ok, file = pcall(region.GetTexture, region)
		key = (ok and file ~= nil and not Secret(file)) and tostring(file) or "?"
	end
	return tostring(key)
end

local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer, sub = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = ArtOf(region) .. (region.kitPiece and " (kit)" or "")
				.. (claimed[region] and (" -> " .. claimed[region]) or (region.kitPiece and "" or " -> UNMAPPED"))
		elseif kind == "FontString" then
			local text = TextOf(region)
			art = "text: " .. (text and text:sub(1, 40) or "?")
		end
		local okA, alpha = pcall(region.GetAlpha, region)
		MelloUI:Print("  region %s %s [%s] %s %s %s alpha %s shown %s %s", kind, Label(region), tostring(KeyOf(frame, region) or "-"),
			okL and tostring(layer) or "?", okL and tostring(sub) or "", art, (okA and Plain(alpha)) and string.format("%.2f", alpha) or "?",
			Shown(region), RectText(region))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local okLv, lv = pcall(child.GetFrameLevel, child)
		MelloUI:Print("  child %s %s [%s] level %s shown %s%s %s", tostring(child:GetObjectType()), Label(child), tostring(KeyOf(frame, child) or "-"),
			okLv and Num(lv) or "?", Shown(child), child.melloRep ~= nil and " (dressed)" or "", RectText(child))
	end
end

local function DumpSummary(f)
	local okLv, lv = pcall(f.GetFrameLevel, f)
	MelloUI:Print("GuildBankFrame: shown %s, level %s, kit %s, reps %d, followers %d, faded art %d, %s", Shown(f), okLv and Num(lv) or "?",
		active and "on" or "off", skin and #skin.reps or 0, skin and #skin.followers or 0, #fadedArt, RectText(f))
	MelloUI:Print("  shell: %s", skin and skin.shellKind or "not built")
	Found("NineSlice", f.NineSlice, f.NineSlice and (" layout " .. tostring(f.NineSlice.layoutType)) or " (own border)")
	Found("Bg", f.Bg)
	for _, t in ipairs(skin and skin.outerPieces or {}) do
		Found("outer rail piece", t, " [" .. tostring(KeyOf(f, t) or "-") .. "] " .. ArtOf(t))
	end
	local page = skin and skin.page
	Found("page stone", page and (page.tex or page.object) or nil, page and (" inner " .. RectText(page.inner)) or nil)
	-- the title
	local title = skin and skin.titleText
	Found("title string", title, title and string.format(" (%s) text %s, title face %s, plate %s", tostring(skin.titleRole),
		tostring(TextOf(title)), tostring(title.melloFontSaved ~= nil), tostring(TitleRep() ~= nil))
		or (skin and (" (" .. tostring(skin.titleRole) .. ")") or nil))
	local tabTitle = TabTitle(f)
	Found("tab title", tabTitle, tabTitle and (" text " .. tostring(TextOf(tabTitle))) or nil)
	for _, fs in ipairs(skin and skin.extraTitles or {}) do
		Found("other title string", fs, " text " .. tostring(TextOf(fs)) .. (titleMoved[fs] and ", on the plate" or ""))
	end
	-- the portrait and emblem
	Found("game portrait", Portrait(f))
	Found("emblem holder", skin and skin.emblemHolder or nil)
	for _, t in ipairs(skin and skin.emblemParts or {}) do
		Found("emblem part", t, " " .. ArtOf(t) .. " " .. RectText(t))
	end
	local p = skin and skin.portrait
	Found("ring", skin and skin.ring and skin.ring.object or nil,
		p and (" shows: " .. tostring(p.mode) .. ", disc " .. RectText(p.disc)) or " (no ring: nothing to hang it on)")
	local close = f.CloseButton or _G.GuildBankFrameCloseButton
	Found("close button", close, close and (" dressed " .. Dressed(close)) or nil)
	-- the item area
	Found("inner rail", skin and skin.innerRail and skin.innerRail.object or nil)
	Found("item area rect", skin and skin.area or nil, skin and skin.area and (" " .. RectText(skin.area)) or nil)
	MelloUI:Print("  columns %d, slots in rims %d, Item Background %s, Button Border %s", #columns, stats.items, ItemBackground(),
		tostring(Kit:BorderValue("button")))
	-- the pages
	Found("log page", skin and skin.logPage or nil, skin and skin.logPage and (" shown " .. Shown(skin.logPage)) or nil)
	Found("log text", skin and skin.logText or nil)
	Found("info page", skin and skin.infoPage or nil, skin and skin.infoPage and (" shown " .. Shown(skin.infoPage)) or nil)
	Found("info text", skin and skin.infoText or nil)
	local buy = BuyInfo(f)
	Found("tab purchase notice", buy, buy and (" shown " .. Shown(buy)) or nil)
	for _, d in ipairs(dims) do
		MelloUI:Print("  %-28s shown %s %s", "dark panel: " .. d.label, Shown(d.tex), RectText(d.tex))
	end
	for _, entry in ipairs(readable) do
		Found("readable: " .. entry.label, entry.obj, entry.grown and " (grown to full size)" or " (size kept)")
	end
	-- buttons and money
	for _, b in ipairs(RedButtons(f)) do
		local okE, enabled = pcall(b.IsEnabled, b)
		Found("button", b, string.format(" red plate %s, enabled %s", Dressed(b), (okE and not Secret(enabled)) and tostring(enabled) or "?"))
	end
	Found("money", _G.GuildBankMoneyFrame or f.MoneyFrame)
	Found("withdraw money", _G.GuildBankWithdrawMoneyFrame or f.WithdrawMoneyFrame)
	for _, t in ipairs(Named(f, MONEY_BG_KEYS)) do
		Found("money background", t, " " .. tostring(claimed[t] or "not dressed"))
	end
	MelloUI:Print("  side tabs dressed %d, bottom tabs %d, red plates %d, coin plates %d, picker icons %d (see /guildbankdump tabs, slots, popup)",
		stats.sideTabs, stats.tabs, stats.buttons, stats.plates, stats.icons)
end

local function DumpSlots(f)
	MelloUI:Print("GuildBankFrame slots: columns %d, rimmed %d, Item Background %s, Button Border %s", #columns, stats.items, ItemBackground(),
		tostring(Kit:BorderValue("button")))
	for i, entry in ipairs(columns) do
		local bg = entry.background
		MelloUI:Print("  column %d %s buttons %d picture %s (%s) %s", i, Label(entry.frame), #entry.buttons, bg and ArtOf(bg) or "none",
			bg and (Kit.faded[bg] and "faded" or "shown") or "-", RectText(entry.frame))
		for j, b in ipairs(entry.buttons) do
			if j <= 2 or j == #entry.buttons then
				local stone = b.melloSlotStone and b.melloSlotStone.tex
				local okI, iconShown = pcall(function() return b.icon and b.icon:IsShown() end)
				MelloUI:Print("    slot %d %s rim %s icon shown %s empty stone %s quality border %s %s", j, Label(b), Dressed(b),
					(okI and not Secret(iconShown)) and tostring(iconShown) or "?", stone and Shown(stone) or "-",
					b.IconBorder and Shown(b.IconBorder) or "-", RectText(b))
			end
		end
	end
	if #columns == 0 then
		MelloUI:Print("  no columns found: GuildBankFrame's own regions and children follow")
		DumpOwn(f)
	end
end

local function DumpTabs(f)
	MelloUI:Print("GuildBankFrame tabs: Side Tab Border %s, kit %s", tostring(Kit:BorderValue("sidetab")), active and "on" or "off")
	MelloUI:Print(" side (bank) tabs: %d found", #sideTabs)
	for i, entry in ipairs(sideTabs) do
		local rim = entry.rep and entry.rep.object
		local okG, ga = false, nil
		if rim and rim.glow then
			okG, ga = pcall(rim.glow.GetAlpha, rim.glow)
		end
		local art = "-"
		if entry.icon then
			local ok, file = pcall(entry.icon.GetTexture, entry.icon)
			art = (ok and file ~= nil and not Secret(file)) and tostring(file) or "?"
		end
		MelloUI:Print("  %d %s shown %s button %s icon %s", i, Label(entry.tab), Shown(entry.tab), Label(entry.button), art)
		MelloUI:Print("     dressed as %s, rim shown %s (%s), selected %s, glow %s, rim %s, icon %s%s",
			entry.rep and "common-sidetab (gold slot rim)" or "nothing", rim and Shown(rim) or "-", rim and tostring(rim.base) or "-",
			tostring(TabChecked(entry.button)), (okG and Plain(ga)) and string.format("%.2f", ga) or "-", RectText(rim), RectText(entry.icon),
			entry.why and (" (" .. entry.why .. ")") or "")
	end
	local idx = OpenBottomTab(f)
	MelloUI:Print(" bottom tabs: %d found, open %s", #bottomTabs, tostring(idx))
	for i, entry in ipairs(bottomTabs) do
		local plainShown, openShown = "-", "-"
		for _, fr in ipairs(tabReps) do
			if fr.region == entry.plainTex then
				plainShown = Shown(fr.rep.object)
			elseif fr.region == entry.openTex then
				openShown = Shown(fr.rep.object)
			end
		end
		MelloUI:Print("  %d %s text %s, %s, open look %s, cards plain %s open %s, text %s", i, Label(entry.tab),
			tostring(entry.text and TextOf(entry.text)), tostring(entry.kind), entry.openTex and Shown(entry.openTex) or "-", plainShown, openShown,
			entry.text and RectText(entry.text) or "-")
	end
	MelloUI:Print(" page picture (2a: the same rect on every page):")
	MelloUI:Print("  now %s", skin and skin.page and RectText(skin.page.inner) or "no page picture")
	local seen = 0
	for label, rect in pairs(pageRects) do
		seen = seen + 1
		MelloUI:Print("  %s: %s", label, rect)
	end
	if seen == 0 then
		MelloUI:Print("  (open each tab once with the kit on, then dump again)")
	end
	MelloUI:Print("  the window (the outer rail's rect) %s", RectText(f))
end

local function DumpPopup()
	local popup = Popup()
	if not popup then
		MelloUI:Print("/guildbankdump popup: no GuildBankPopupFrame yet (open a tab's settings once)")
		return
	end
	local area = popup.BorderBox and popup.BorderBox.SelectedIconArea
	MelloUI:Print("GuildBankPopupFrame: shown %s, kit %s, BorderBox %s, edit %s, grid %s, current icon %s, picker icons in rims %d", Shown(popup),
		active and "on" or "off", tostring(popup.BorderBox ~= nil), Label(PopupEdit(popup)), tostring(PopupBox(popup) ~= nil),
		tostring(area ~= nil and area.SelectedIconButton ~= nil), stats.icons)
	DumpOwn(popup)
	if popup.BorderBox then
		MelloUI:Print("BorderBox:")
		DumpOwn(popup.BorderBox)
	end
end

SLASH_MELLOGUILDBANKDUMP1 = "/guildbankdump"
SlashCmdList.MELLOGUILDBANKDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if not f then
		MelloUI:Print("/guildbankdump: no GuildBankFrame yet (the guild bank loads with its first opening: visit a guild vault, then try again)")
	elseif msg == "" then
		DumpSummary(f)
		MelloUI:Print("GuildBankFrame's own regions and children:")
		DumpOwn(f)
		-- the pages' own art (a page backdrop would show a second picture)
		local logPage, infoPage = LogParts(f), InfoParts(f)
		for _, entry in ipairs({ { "log page", logPage }, { "info page", infoPage }, { "tab purchase notice", BuyInfo(f) } }) do
			if entry[2] and entry[2] ~= f and entry[2].GetRegions then
				MelloUI:Print("%s (%s) regions and children:", entry[1], Label(entry[2]))
				DumpOwn(entry[2])
			end
		end
	elseif msg == "slots" then
		DumpSlots(f)
	elseif msg == "tabs" then
		DumpTabs(f)
	elseif msg:match("^popup") then
		local rest = msg:match("^popup%s*(.*)$")
		if rest ~= "" and Popup() then
			Kit:DumpWindow(Popup(), skin, rest ~= "regions" and rest or nil)
		else
			DumpPopup()
		end
	else
		-- frames / reps / regions (the visible game textures): the Kit's dump
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	end
	MelloUI:ShowLog("guildbankdump " .. msg)
end
