--------------------------------------------------------------------------------
-- MelloUI - Mailbox Kit
--
-- (user, 2026-09-24: "we forgot the mailbox"): the mailbox -- MailFrame with
-- its Inbox and Send Mail pages, and OpenMailFrame, the letter being read,
-- a window of its own -- dressed in the painted kit (Modules/Kit.lua) on the
-- game's own layout, by the rule book (docs/WINDOW-RULES.md): every kit piece
-- stands in for one of the game's art regions, on that region's rectangle,
-- the game's art faded in its place.
--
--   the window shells    outer double rail with gem corners, ONE page stone
--                        per window on the window's rect inside the rail (2a:
--                        the Inbox and Send Mail pages show the same picture
--                        in the same place), the ring with the mail icon at
--                        the class medallion's size on the dark disc (2b),
--                        the title plate on the rail with the title ON it in
--                        the title face (2c), the close button
--                        (Kit:SkinWindowShell)
--   the insets           the list box L1 as regions of the inset: single
--                        rail, list-box stone, the palette's inner panel at
--                        0.8 (2e) -- the attachments and the money to send
--                        lie on it
--   the pages            the game's paper (the inbox's page, the stationery
--                        of a letter being written or read) -> the kit's
--                        parchment page with the painted brush edge
--                        (QuestDetailsBackgrounds, the quest log's paper),
--                        kept inside the inset's rail; every text on it in
--                        dark ink by the parchment rule (QuestInk), the text
--                        the player types and the letter too
--   the header blocks    To / Subject / Postage and the letter's sender and
--                        subject: small text on stone, so a dark panel of its
--                        own (the same L1, an agreed addition of 2e) where the
--                        block lies outside the inset; labels at full size in
--                        the palette's text colour, headings in its gold
--   the mail rows        the item slot in every window's Button Border rim
--                        (the quality border kept), the empty-slot art faded;
--                        thin ruled lines faded
--   the controls         edit boxes on the edit plate (S1, the search glass's
--                        cap dropped, the coin icons kept), the radio buttons
--                        in the kit's check box, attachment slots in the rim,
--                        Prev / Next as the kit's arrows (dimmed while
--                        disabled), the text buttons on the red plates, the
--                        money bar on the coin plate, the tabs as TB6 cards,
--                        the scroll bars as THE scroll bar
--
-- Taint: nothing of the game's is replaced or re-scripted. The skin is made
-- and kept from post-hooks (the game's inbox / send / open updates,
-- HookScript, the regions' own Show / Hide / SetTextColor, the buttons'
-- Enable / Disable); what it keeps about the game's frames lives in weak side
-- tables; no mail function is ever called and MailFrame is never moved.
-- Switching the module off disables every replacement (the game's art faded
-- back in, ours hidden) and puts the portraits, titles, labels and text
-- colours back: the windows are the game's again. Nothing is built at login:
-- each window is dressed on its first open (user, 2026-09-24) and kept.
--
-- /maildump [rows | send | open | ink | reps | frames | regions] [open]: what
-- the windows are made of on this client and what the skin dressed.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("MailPanel")
local hooksecurefunc = Perf.hooksecurefunc
-- a handler made once and run for many asks, wrapped once: its time stays
-- on this file's own /melloperf row (review, 2026-09-24)
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("MailPanel", {
	title = "Mailbox Kit",
	desc = "The mailbox (inbox, reading a letter, send mail) in the kit.",
	window = { label = "Mailbox", desc = "The mailbox (inbox, reading a letter, send mail) in the kit.", tab = "Windows",
		frames = { "MailFrame", "OpenMailFrame" }, plainGrab = true, firstOpen = true },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local AREA = "mailbox"                           -- the ink surface's name (QuestInk)
local ROWS_MAX = 20                              -- MailItem1.. (7 on a page on this client): read until one is missing
local ATTACH_MAX = 16                            -- SendMailAttachment1.. / OpenMailAttachmentButton1..
local MAIL_ICON = "Interface\\MailFrame\\Mail-Icon"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local STONE_KEY = "UI-Background-Rock"           -- the page stone (ButtonFrameTemplate's rock)
local PAGE_KEY = "QuestDetailsBackgrounds"       -- the parchment page with the painted edge
local BOX_KEY = "AuctionHouseBackgroundTemplate" -- L1 as REGIONS of its frame, dimmed (2e)
local EDIT_KEY = "common-search-border-middle"   -- the edit plate (S1)
local PANEL_PAD = 6                              -- UI px a header block's panel reaches past its controls
local RED_PLATES = { ["UI-Panel-Button-Up"] = true, ["_128-RedButton-Center"] = true, ["_128-RedButton-Center-Disabled"] = true }
local TEXT_BUTTONS = { "OpenAllMail", "SendMailMailButton", "SendMailCancelButton", "OpenMailReplyButton", "OpenMailDeleteButton",
	"OpenMailCancelButton", "OpenMailReportSpamButton" }
local RADIOS = { "SendMailSendMoneyButton", "SendMailCODButton" }
local ARROWS = { { "InboxPrevPageButton", "UI-SpellbookIcon-PrevPage-Up" }, { "InboxNextPageButton", "UI-SpellbookIcon-NextPage-Up" } }
-- a title string a layout of these windows may write its title into instead
-- of the title container's TitleText
local EXTRA_TITLES = { MailFrame = { "InboxTitleText", "SendMailTitleText", "MailFrameTitleText" },
	OpenMailFrame = { "OpenMailTitleText", "OpenMailFrameTitleText" } }
-- the strings on a dark panel that head a block (the palette's gold); every
-- other string there is a label (the palette's text colour)
local HEADINGS = { SendMailMoneyText = true, OpenMailAttachmentText = true }
-- the horizontal bars the game draws between a page's blocks (file art, the
-- class trainer's bar): faded, as the guild's (UI-ClassTrainer-HorizontalBar)
local BARS = { "SendMailHorizontalBarLeft", "SendMailHorizontalBarRight", "SendMailHorizontalBarLeft2", "SendMailHorizontalBarRight2",
	"OpenMailHorizontalBarLeft", "OpenMailHorizontalBarRight" }

local skin = nil          -- { reps, followers, windows = { [frame] = win }, paper }
local active = false
local hooked = false
local surfaceMade = false
local looking = false     -- a look being put on (its own SetTextColor / SetFont calls pass the hooks)

-- what this module made or looked at, kept OFF the game's frames (weak keys)
local done = setmetatable({}, { __mode = "k" })         -- [frame / region] = true: looked at once
local fadedArt = {}                                     -- game art faded with no piece of its own on its rect
local itemRims = {}                                     -- { button, host, icon, rep, row, square }
local arrowReps = {}                                    -- { rep, button }
local tabReps = {}                                      -- the tabs' cards { rep, region }
local oldTabTexts = setmetatable({}, { __mode = "k" })  -- [text] = { game = its last point, steadyFn }: an older tab's text
local radios = {}                                       -- { button, rep }
local labelLayers = setmetatable({}, { __mode = "k" })  -- [label] = { layer, sublevel }: a plate's label raised over it
local looks = setmetatable({}, { __mode = "k" })        -- [fs] = { font, colour, role, on }: a label on a dark panel
local titleOwned = setmetatable({}, { __mode = "k" })   -- [fs] = true: a title on the plate (never inked, never a label)
local bodies = {}                                       -- { obj, kind, saved }: the typed letter and the read letter
local stats = { rows = 0, rims = 0, edits = 0, radios = 0, buttons = 0, arrows = 0, tabs = 0, plates = 0, bars = 0, papers = 0, panels = 0 }

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
			MelloUI:Notice("Mailbox kit: no kit piece mapped for %s", tostring(key))
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
	if not (obj and obj.GetName) then
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

local function IsTexture(obj)
	return type(obj) == "table" and obj.GetObjectType ~= nil and obj:GetObjectType() == "Texture"
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

-- Art faded while the kit is on with no piece on its own rect
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

-- An object's edges (left, right, top, bottom) in `ref`'s units; nil while
-- it is not laid out or reads secret
local function Edges(obj, ref)
	if not (obj and obj.GetLeft and ref) then
		return nil
	end
	local ok, l, r, t, b = pcall(function()
		return obj:GetLeft(), obj:GetRight(), obj:GetTop(), obj:GetBottom()
	end)
	if not (ok and l and r and t and b) or Secret(l) or Secret(r) or Secret(t) or Secret(b) then
		return nil
	end
	local okS, k = pcall(function()
		return obj:GetEffectiveScale() / ref:GetEffectiveScale()
	end)
	if not okS or type(k) ~= "number" or Secret(k) then
		k = 1
	end
	return l * k, r * k, t * k, b * k
end

-- Whether fs's centre lies in `f` (nil while either is not laid out)
local function Inside(fs, f)
	local okC, x, y = pcall(fs.GetCenter, fs)
	if not (okC and x and y) or Secret(x) or Secret(y) then
		return nil
	end
	local l, r, t, b = Edges(f, fs)
	if not l then
		return nil
	end
	return x >= l and x <= r and y >= b and y <= t
end

-- whether `f` lies under `root` (a few parents up)
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

local function Windows()
	return _G.MailFrame, _G.OpenMailFrame
end

--------------------------------------------------------------------------------
-- The portrait (2b / 2c: an empty ring is a bug). The game draws the mail
-- icon into the template's portrait (SetPortraitToAsset): the kit's ring on
-- the corner, the icon brought to the class medallion's size in it
-- (Kit:FitPortrait, its aspect kept) on the dark disc (Kit:RingDisc) -- a
-- round icon covers the disc, one that does not sits on it. A window whose
-- portrait holds no art when it shows (the letter window on a client that
-- draws none there) gets the mailbox's icon drawn on the disc instead,
-- round-masked, so the ring is never empty; hidden again the moment the
-- game's has art.
--------------------------------------------------------------------------------
local function PortraitOf(f)
	local pc = f and f.PortraitContainer
	local name = NameOf(f)
	return (pc and pc.portrait) or (f and f.portrait) or (name and _G[name .. "Portrait"]) or nil
end

-- the art a texture holds (nil when none), secret-safe
local function ArtOf(tex)
	if not tex then
		return nil
	end
	local ok, file = pcall(tex.GetTexture, tex)
	if ok and not Secret(file) and file ~= nil and ((type(file) == "number" and file > 0) or (type(file) == "string" and file ~= "")) then
		return file
	end
	local okA, atlas = pcall(tex.GetAtlas, tex)
	if okA and type(atlas) == "string" and not Secret(atlas) and atlas ~= "" then
		return atlas
	end
	return nil
end

local function FitPortrait(win)
	if not (active and win and win.ring and win.portrait) then
		return
	end
	pcall(Kit.FitPortrait, Kit, win.portrait, win.ring)
	-- the stand-in icon while the game's portrait is empty
	local stand = win.standIn
	if not stand then
		return
	end
	if ArtOf(win.portrait) then
		stand:Hide()
		return
	end
	local main = PortraitOf(_G.MailFrame)
	local art = (main ~= win.portrait) and ArtOf(main) or nil
	if type(art) == "string" and not art:find("\\", 1, true) and not art:find("/", 1, true) then
		pcall(stand.SetAtlas, stand, art)
	else
		stand:SetTexture(art or MAIL_ICON)
	end
	stand:Show()
end

local function SkinPortrait(win)
	local ring, portrait = win.ring, win.portrait
	if not (ring and portrait) then
		return
	end
	local host = win.frame.PortraitContainer or ring.object:GetParent()
	ring.onEnable = function()
		pcall(Kit.FitPortrait, Kit, portrait, ring)
	end
	ring.onDisable = function()
		pcall(Kit.UnfitPortrait, Kit, portrait)
		if win.standIn then
			win.standIn:Hide()
		end
	end
	-- (chains onto the fit above; a region of the portrait's own frame,
	-- BACKGROUND 0 under its OVERLAY portrait)
	local disc = Kit:RingDisc(ring, nil, host, 0)
	if disc and host.CreateTexture then
		local stand = host:CreateTexture(nil, "ARTWORK", nil, 1)
		stand.kitPiece = true
		stand:SetAllPoints(disc)
		local mask = host:CreateMaskTexture()
		mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(stand)
		stand:AddMaskTexture(mask)
		stand:Hide()
		win.standIn = stand
	end
end

--------------------------------------------------------------------------------
-- The title (2c: the title ON the plate, in the title face). The shell's
-- title plate centres the title container's TitleText on it in Kit:TitleFont
-- (which follows the Fonts options and the Font Style) and puts it back on
-- disable. A layout that writes the page's title into a string of its own
-- (InboxTitleText, SendMailTitleText, OpenMailTitleText) gets that string on
-- the plate in the title face while the container's is empty, or faded where
-- the container already shows the same words; points and font put back on
-- disable. A string read secret is left alone, never doubled on the plate.
--------------------------------------------------------------------------------
local function TitleStrings(frame)
	local tc = frame.TitleContainer
	local own = tc and tc.TitleText
	local list, seen = {}, {}
	if own then
		seen[own] = true
		titleOwned[own] = true
	end
	local function Add(fs)
		if fs and not seen[fs] and fs.GetObjectType and fs:GetObjectType() == "FontString" then
			seen[fs] = true
			list[#list + 1] = fs
		end
	end
	for _, name in ipairs(EXTRA_TITLES[NameOf(frame) or ""] or {}) do
		Add(_G[name])
	end
	Add(frame.TitleText)
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
	local plate = win.title
	if not plate then
		return
	end
	if plate.object and plate.object:IsShown() and plate.Refit then
		plate:Refit()
	end
	local list, own = TitleStrings(win.frame)
	local ownText, ownSecret = nil, false
	if own then
		ownText, ownSecret = TextOf(own)
		if not own.melloFontSaved then
			Kit:TitleFont(own, true)
		end
	end
	for _, fs in ipairs(list) do
		local text = TextOf(fs)
		if text and ownText and text == ownText then
			-- the same words already on the plate: this copy gives way
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
			titleOwned[fs] = true
			fs:ClearAllPoints()
			-- on the container's string (the plate's rule centred it on the
			-- plate's painted box), else on the plate itself
			if own then
				fs:SetPoint("CENTER", own, "CENTER")
			else
				fs:SetPoint("CENTER", plate.strip or plate.object, "CENTER")
			end
			Kit:TitleFont(fs, true)
		end
	end
end

--------------------------------------------------------------------------------
-- The inset (ButtonFrameTemplate's Inset: a marble Bg and a NineSlice at the
-- window's own level): the list box L1 as REGIONS of the inset (the rule the
-- auction house's boxes use: the rails in BORDER, the list-box stone in
-- BACKGROUND 1, the palette's inner panel at 0.8 over it in BACKGROUND 2), so
-- it always lies under the pages, their paper and their controls (frames a
-- level up) and never ties with them. The game re-anchors the inset when it
-- switches pages (the Send page's taller header): the regions follow it.
--------------------------------------------------------------------------------
local function DressInset(win)
	local f = win.frame
	local inset = f.Inset or Part(f, nil, "Inset")
	if not (inset and inset.Bg) or inset.melloRep ~= nil then
		return
	end
	local extra = {}
	if inset.NineSlice then
		for _, region in ipairs({ inset.NineSlice:GetRegions() }) do
			if IsTexture(region) then
				extra[#extra + 1] = region
			end
		end
	end
	local rep = Replace(inset.Bg, { as = BOX_KEY, rect = inset, alsoFade = extra })
	inset.melloRep = rep or false
	if rep then
		win.inset = inset
		win.insetRep = rep
		win.insetRail = (rep.skin and rep.skin.thickness) or 8
	end
end

--------------------------------------------------------------------------------
-- The pages (the parchment rule; "replace, never add"): the game's paper --
-- the inbox's page (InboxFrameBg, else the page's largest picture), the
-- stationery of the letter being written or read (Left / Right halves) --
-- becomes the kit's parchment page with the painted brush edge on the paper's
-- own rect (the halves' union), kept inside the inset's rail so the paper
-- never covers it. The game changes the stationery per letter: its art stays
-- faded, the kit's one parchment stays.
--------------------------------------------------------------------------------
local function FitPaper(paper)
	local parts, rect = paper.parts, paper.rect
	local page = rect:GetParent()
	local L, R, T, B
	for _, part in ipairs(parts) do
		local l, r, t, b = Edges(part, page)
		if l then
			L, R = L and math.min(L, l) or l, R and math.max(R, r) or r
			T, B = T and math.max(T, t) or t, B and math.min(B, b) or b
		end
	end
	local pl, _, _, pb = Edges(page, page)
	if not (L and pl) then
		if not paper.placed then
			rect:ClearAllPoints()
			rect:SetAllPoints(parts[1])
		end
		return
	end
	paper.clipped = false
	local il, ir, it, ib = Edges(paper.win.inset, page)
	if il then
		local rail = paper.win.insetRail or 0
		local cl, cr, ct, cb = il + rail, ir - rail, it - rail, ib + rail
		if L < cl or R > cr or T > ct or B < cb then
			paper.clipped = true
			L, R, T, B = math.max(L, cl), math.min(R, cr), math.min(T, ct), math.max(B, cb)
		end
	end
	if R - L < 8 or T - B < 8 then
		return
	end
	paper.placed = true
	rect:ClearAllPoints()
	rect:SetPoint("TOPLEFT", page, "BOTTOMLEFT", L - pl, T - pb)
	rect:SetPoint("BOTTOMRIGHT", page, "BOTTOMLEFT", R - pl, B - pb)
end

local function DressPaper(win, name, parts, root)
	local main = parts[1]
	if not main or done[main] then
		return nil
	end
	done[main] = true
	local rect = CreateFrame("Frame", nil, main:GetParent())
	rect:EnableMouse(false)
	local paper = { name = name, parts = parts, rect = rect, win = win, root = root or main:GetParent() }
	FitPaper(paper)
	local extra = {}
	for i = 2, #parts do
		extra[#extra + 1] = parts[i]
	end
	paper.rep = Replace(main, { as = PAGE_KEY, rect = rect, alsoFade = extra })
	if not paper.rep then
		return nil
	end
	win.papers[#win.papers + 1] = paper
	skin.paper = true
	stats.papers = stats.papers + 1
	return paper
end

-- the inbox's paper: its named page, else the page's largest picture
local function InboxPaperArt(inbox)
	local bg = _G.InboxFrameBg or inbox.Bg or inbox.Background
	if IsTexture(bg) then
		return bg
	end
	local best, area = nil, 0
	for _, region in ipairs({ inbox:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece then
			local okL, layer = pcall(region.GetDrawLayer, region)
			local okS, w, h = pcall(region.GetSize, region)
			if okL and (layer == "BACKGROUND" or layer == "BORDER") and okS and w and h and not Secret(w) and not Secret(h)
				and w > 150 and h > 150 and w * h > area then
				best, area = region, w * h
			end
		end
	end
	return best
end

-- a letter's stationery (two halves, by their names), else the scroll frame's
-- own pictures
local function Stationery(prefix, scroll)
	local list = List(_G[prefix .. "StationeryBackgroundLeft"], _G[prefix .. "StationeryBackgroundRight"])
	if #list > 0 or not scroll then
		return list
	end
	for _, region in ipairs({ scroll:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece then
			local okL, layer = pcall(region.GetDrawLayer, region)
			local okS, w = pcall(region.GetWidth, region)
			if okL and (layer == "BACKGROUND" or layer == "BORDER") and okS and w and not Secret(w) and w > 40 then
				list[#list + 1] = region
			end
		end
	end
	return list
end

-- One page picture per window (2a): a picture of a page (the Inbox or the
-- Send page, set on the window's whole rect) that covers most of the window
-- would lie over the window's one stone on that page only -- the stone would
-- change with the tab. Faded, as a band the game paints over its rock is.
local function FadePageStones(page, window)
	if not (page and window) then
		return
	end
	local wl, wr, wt, wb = Edges(window, window)
	if not wl then
		return
	end
	for _, region in ipairs({ page:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece and not done[region] then
			local okL, layer = pcall(region.GetDrawLayer, region)
			local l, r, t, b = Edges(region, window)
			if okL and layer == "BACKGROUND" and l and (r - l) >= (wr - wl) * 0.8 and (t - b) >= (wt - wb) * 0.6 then
				FadeArt(region)
			end
		end
	end
end

-- Whether fs lies on a shown kit paper (nil while it cannot tell)
local function OnPaper(fs)
	local okC, x = pcall(fs.GetCenter, fs)
	if not (okC and x) or Secret(x) then
		return nil
	end
	for _, win in pairs(skin and skin.windows or {}) do
		for _, paper in ipairs(win.papers) do
			local obj = paper.rep and paper.rep.object
			if obj and obj:IsVisible() then
				local inside = Inside(fs, paper.rep.inner or paper.rect)
				if inside == nil then
					return nil
				elseif inside then
					return true
				end
			end
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- The header blocks (2e: "too much small text over a plain brown border is
-- just an eye strain"): To / Subject / Postage on the Send page and the
-- letter's sender and subject stand on the page stone above the inset. Each
-- block gets the list box L1 of its own -- the single rail, the list-box
-- stone, the palette's inner panel at 0.8 -- as REGIONS of its page (under
-- the page's labels and edit boxes), on the block's span: the inset's width,
-- from above its top control to below its lowest, stopping short of the
-- inset. An agreed addition of the eye-strain rule (the game draws nothing
-- there); it stands aside where the block lies inside the inset already (a
-- layout whose inset reaches up to it: the inset's panel is the block's).
--------------------------------------------------------------------------------
local function FitSpan(span)
	local page, rect = span.page, span.rect
	local L, R, T, B
	for _, obj in ipairs(span.objs) do
		local l, r, t, b = Edges(obj, page)
		if l then
			L, R = L and math.min(L, l) or l, R and math.max(R, r) or r
			T, B = T and math.max(T, t) or t, B and math.min(B, b) or b
		end
	end
	local pl, pr, pt, pb = Edges(page, page)
	if not (L and pl) then
		return
	end
	local il, ir, it = Edges(span.win.inset, page)
	if il then
		L, R = il, ir
	else
		-- no inset: the page's width inside the outer rail
		local ins = Kit:OuterRailInset()
		L, R = pl + ins[1] + 2, pr - ins[2] - 2
	end
	local bottom = B
	T, B = math.min(T + PANEL_PAD, pt - 2), B - PANEL_PAD
	span.inside = false
	if it and B < it + 2 then
		if bottom < it then
			span.inside = true   -- the block's controls are in the inset: its panel is theirs
		else
			B = it + 2           -- stop short of the inset's rail
		end
	end
	if R - L < 20 or T - B < 10 then
		span.inside = true
	end
	span.placed = true
	rect:ClearAllPoints()
	rect:SetPoint("TOPLEFT", page, "BOTTOMLEFT", L - pl, T - pb)
	rect:SetPoint("BOTTOMRIGHT", page, "BOTTOMLEFT", R - pl, B - pb)
	if span.rep and active then
		span.rep:SetShown(not span.inside)
	end
end

local function DressSpan(win, name, page, objs)
	if not page or #objs == 0 or done[page] then
		return nil
	end
	done[page] = true
	-- the key region: a texture of the page that only names the frame the
	-- panel's regions belong to (noFade: it draws nothing and stands in for
	-- nothing)
	local key = page:CreateTexture(nil, "BACKGROUND", nil, 0)
	key.kitPiece = true
	key:Hide()
	local rect = CreateFrame("Frame", nil, page)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", page, "TOPLEFT")
	rect:SetSize(1, 1)
	local span = { name = name, page = page, objs = objs, rect = rect, win = win }
	span.rep = Replace(key, { as = BOX_KEY, parent = page, rect = rect, noFade = true })
	if not span.rep then
		return nil
	end
	win.spans[#win.spans + 1] = span
	stats.panels = stats.panels + 1
	FitSpan(span)
	return span
end

--------------------------------------------------------------------------------
-- The labels on the dark panels (2e: labels at the interface's full size in
-- the palette's text colour, headings in its gold): every string of a window
-- lying on a header block's panel or on the inset's, not on the paper (that
-- is the ink's) and not a button's plate, a coin's or a title's. Its size is
-- raised to GameFontHighlight's where it is smaller; its colour follows the
-- game's (a greyed label -- the C.O.D. choice while nothing is attached -- is
-- the palette's muted text, a colour that means something stays), kept as
-- the game recolours it; the game's font and colour back when the kit is off.
--------------------------------------------------------------------------------
local function FullSize()
	local fo = _G.GameFontHighlight
	if not (fo and fo.GetFont) then
		return 12
	end
	local ok, _, size = pcall(fo.GetFont, fo)
	if ok and type(size) == "number" and not Secret(size) and size > 0 then
		return size
	end
	return 12
end

local function Tone(key, fallback)
	local P = MelloUI.Palette
	local c = P and P[key] or fallback
	return c[1], c[2], c[3]
end

local function LookColour(role, r, g, b)
	if role == "heading" then
		return Tone("selectedTrim", { 0.68, 0.52, 0.27 })
	end
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local sat = mx > 0 and (mx - mn) / mx or 0
	if sat < 0.25 then
		if mx < 0.65 then
			return Tone("mutedText", { 0.5, 0.41, 0.27 })   -- a greyed, disabled label
		end
		return Tone("text", { 0.78, 0.69, 0.52 })
	end
	-- the interface's gold on a label: the text colour
	if r >= 0.8 and g >= 0.6 and b <= 0.35 and g / r > 0.65 and g / r <= 0.9 then
		return Tone("text", { 0.78, 0.69, 0.52 })
	end
	return r, g, b
end

local function ApplyLook(fs, entry)
	looking = true
	local ok, path, size, flags = pcall(fs.GetFont, fs)
	if ok and path and type(size) == "number" and not Secret(path) and not Secret(size) then
		local full = FullSize()
		if size < full then
			pcall(fs.SetFont, fs, path, full, flags or "")
		end
	end
	local c = entry.colour
	local r, g, b = LookColour(entry.role, c[1], c[2], c[3])
	pcall(fs.SetTextColor, fs, r, g, b)
	looking = false
end

-- the game's font and colour, read now (while the look is off they are the
-- game's own)
local function ReadGame(fs, entry)
	local ok, path, size, flags = pcall(fs.GetFont, fs)
	if ok and path and type(size) == "number" and not Secret(path) and not Secret(size) then
		entry.font = { path, size, flags or "" }
	end
	local okC, r, g, b = pcall(fs.GetTextColor, fs)
	if okC and type(r) == "number" and not (Secret(r) or Secret(g) or Secret(b)) then
		entry.colour = { r, g, b }
	end
	return entry.font ~= nil and entry.colour ~= nil
end

local function Look(fs, role)
	local entry = looks[fs]
	if not entry then
		entry = { role = role }
		if not ReadGame(fs, entry) then
			return
		end
		looks[fs] = entry
		hooksecurefunc(fs, "SetTextColor", function(self, cr, cg, cb)
			local e = looks[self]
			if looking or not e then
				return
			end
			if type(cr) == "number" and not (Secret(cr) or Secret(cg) or Secret(cb)) then
				e.colour = { cr, cg, cb }
			end
			if e.on and active then
				ApplyLook(self, e)
			end
		end)
		if fs.SetFontObject then
			hooksecurefunc(fs, "SetFontObject", function(self)
				local e = looks[self]
				if looking or not e then
					return
				end
				-- the object's own size and colour came back: those are the game's now
				ReadGame(self, e)
				if e.on and active then
					ApplyLook(self, e)
				end
			end)
		end
	elseif not entry.on then
		ReadGame(fs, entry)
	end
	entry.role = role
	entry.on = true
	ApplyLook(fs, entry)
end

local function Unlook(fs)
	local e = looks[fs]
	if not (e and e.on) then
		return
	end
	e.on = false
	looking = true
	local f = e.font
	if f then
		pcall(fs.SetFont, fs, f[1], f[2], f[3])
	end
	local c = e.colour
	if c then
		pcall(fs.SetTextColor, fs, c[1], c[2], c[3])
	end
	looking = false
end

-- a coin's amount (a money frame's gold / silver / copper button): its size
-- is the money frame's layout, left alone
local function IsCoinText(fs)
	local p = fs:GetParent()
	local pp = p and p.GetParent and p:GetParent()
	if not pp then
		return false
	end
	if pp.GoldButton or pp.CopperButton or pp.SilverButton then
		return true
	end
	local n = NameOf(pp)
	return n ~= nil and (n:find("MoneyFrame$") ~= nil or n:find("Money$") ~= nil) and p:GetObjectType() == "Button"
end

-- the dark panels a window's labels may lie on: its header blocks and inset
local function Panels(win)
	local list = {}
	for _, span in ipairs(win.spans) do
		if span.rep and span.rep.object and span.rep.object:IsVisible() and not span.inside then
			list[#list + 1] = span.rect
		end
	end
	if win.inset and win.insetRep and win.inset:IsVisible() then
		list[#list + 1] = win.inset
	end
	return list
end

local function LookWalk(frame, fn, depth, skip)
	if not frame or depth > 8 or frame.melloNoInk or skip[frame] then
		return
	end
	local kind = frame:GetObjectType()
	if kind == "ScrollFrame" then
		return   -- a page's paper: the ink's
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "FontString" and not region.melloNoInk then
			fn(region, frame, kind)
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		LookWalk(child, fn, depth + 1, skip)
	end
end

local function LookPass(win)
	if not active then
		return
	end
	local panels = Panels(win)
	local skip = {}
	if win.frame.TitleContainer then
		skip[win.frame.TitleContainer] = true
	end
	for _, tab in ipairs(win.tabs or {}) do
		skip[tab] = true
	end
	LookWalk(win.frame, function(fs, owner, kind)
		local want = false
		if not titleOwned[fs] and not IsCoinText(fs) and fs:IsVisible() then
			-- an edit box's own strings inside it (its typed text, its
			-- instructions) are the box's; its label beside it is a label
			local inBox = kind == "EditBox" and Inside(fs, owner)
			if not inBox and OnPaper(fs) == false then
				for _, panel in ipairs(panels) do
					if Inside(fs, panel) then
						want = true
						break
					end
				end
			end
		end
		if want then
			Look(fs, HEADINGS[NameOf(fs) or ""] and "heading" or "label")
		elseif looks[fs] and looks[fs].on and fs:IsVisible() then
			Unlook(fs)
		end
	end, 0, skip)
end

--------------------------------------------------------------------------------
-- The letters' bodies (the parchment rule): the text the player types into
-- the Send page's body (an EditBox, its colour its own, not a region's) and
-- the letter being read (a SimpleHTML on some layouts) in dark ink on the
-- kit's paper -- the game's colour inked by QI.InkOf for the paper's tone
-- (the game's mail font is dark already: it stays dark), no shadow; the
-- game's colour and shadow back when the kit is off. A letter written as a
-- plain FontString is the ink surface's, as every other text on the paper.
--------------------------------------------------------------------------------
local HTML_TYPES = { "P", "H1", "H2", "H3" }

local function InkBody(entry, on)
	local obj, QI = entry.obj, MelloUI.QuestInk
	if not (QI and QI.InkOf) then
		return
	end
	if on then
		if entry.saved then
			return
		end
		local saved = {}
		if entry.kind == "EditBox" then
			local ok, r, g, b = pcall(obj.GetTextColor, obj)
			local okS, sr, sg, sb, sa = pcall(obj.GetShadowColor, obj)
			if not (ok and type(r) == "number") or Secret(r) or Secret(g) or Secret(b) then
				return
			end
			saved.colour = { r, g, b }
			saved.shadow = okS and type(sr) == "number" and not Secret(sr) and { sr, sg, sb, sa } or nil
			entry.saved = saved
			local ir, ig, ib = QI.InkOf(r, g, b, true)
			pcall(obj.SetTextColor, obj, ir, ig, ib)
			pcall(obj.SetShadowColor, obj, 0, 0, 0, 0)
		else
			for _, t in ipairs(HTML_TYPES) do
				local ok, r, g, b = pcall(obj.GetTextColor, obj, t)
				if ok and type(r) == "number" and not (Secret(r) or Secret(g) or Secret(b)) then
					local okS, sr, sg, sb, sa = pcall(obj.GetShadowColor, obj, t)
					saved[t] = { colour = { r, g, b }, shadow = okS and type(sr) == "number" and not Secret(sr) and { sr, sg, sb, sa } or nil }
					local ir, ig, ib = QI.InkOf(r, g, b, true)
					pcall(obj.SetTextColor, obj, t, ir, ig, ib)
					pcall(obj.SetShadowColor, obj, t, 0, 0, 0, 0)
				end
			end
			entry.saved = saved
		end
	elseif entry.saved then
		local saved = entry.saved
		entry.saved = nil
		if entry.kind == "EditBox" then
			local c, s = saved.colour, saved.shadow
			pcall(obj.SetTextColor, obj, c[1], c[2], c[3])
			if s then
				pcall(obj.SetShadowColor, obj, s[1], s[2], s[3], s[4] or 1)
			end
		else
			for t, v in pairs(saved) do
				pcall(obj.SetTextColor, obj, t, v.colour[1], v.colour[2], v.colour[3])
				if v.shadow then
					pcall(obj.SetShadowColor, obj, t, v.shadow[1], v.shadow[2], v.shadow[3], v.shadow[4] or 1)
				end
			end
		end
	end
end

local function AddBody(obj)
	if not (obj and obj.GetObjectType) or done[obj] then
		return
	end
	local kind = obj:GetObjectType()
	if kind ~= "EditBox" and kind ~= "SimpleHTML" then
		return
	end
	done[obj] = true
	bodies[#bodies + 1] = { obj = obj, kind = kind }
end

local function InkBodies(on)
	for _, entry in ipairs(bodies) do
		InkBody(entry, on and skin ~= nil and skin.paper == true)
	end
end

--------------------------------------------------------------------------------
-- Item slots -- a mail row's item, the attachments being sent or received,
-- the letter and the money of a letter read: every window's Button Border rim
-- (R1, as the merchant's items and the quest rewards), hugging the icon (its
-- edge 2 px under the rim's inner edge, on the icon's centre); the game's
-- quality border kept on the icon; the empty-slot art faded (the rim stands
-- in for it), with the pushed, highlight and checked looks (the rim carries
-- hover, press and the open mail's check). Where the empty-slot art is the
-- ROW's (it shows while the row's button is hidden, an empty inbox's rows),
-- the rim is a region of a frame of the row one level over the button, so it
-- shows where the art showed; its hover and press come from the button.
--------------------------------------------------------------------------------
local SLOT_KEYS = { "SlotBackground", "EmptySlot", "ItemSlot", "Slot" }
local SLOT_SUFFIXES = { "Slot", "SlotTexture", "EmptySlot", "SlotBackground", "Background" }

local function IconOf(button)
	local icon = button.icon or button.Icon
	local name = NameOf(button)
	if not icon and name then
		icon = _G[name .. "IconTexture"] or _G[name .. "Icon"]
	end
	return IsTexture(icon) and icon or nil
end

-- a texture roughly square and slot-sized
local function Squareish(region)
	local ok, w, h = pcall(region.GetSize, region)
	if not (ok and w and h) or Secret(w) or Secret(h) then
		return false
	end
	return w >= 24 and w <= 80 and math.abs(w - h) <= 4
end

local function SquareOf(button, row, icon)
	for _, key in ipairs(SLOT_KEYS) do
		local t = button[key]
		if IsTexture(t) and t ~= icon then
			return t
		end
	end
	local name = NameOf(button)
	for _, suffix in ipairs(SLOT_SUFFIXES) do
		local t = name and _G[name .. suffix]
		if IsTexture(t) and t ~= icon then
			return t
		end
	end
	if row then
		for _, region in ipairs({ row:GetRegions() }) do
			if IsTexture(region) and not region.kitPiece and Squareish(region) then
				return region
			end
		end
	end
	return nil
end

local function FitItemRim(entry)
	local rim = entry.rep and entry.rep.object
	local target = entry.icon or entry.button
	if not (rim and rim.base and target) then
		return
	end
	local name = rim.base .. "_normal"
	local p = Kit:Piece(name)
	local l, r, t, b = Kit:Insets(name, 1)
	local ok, iw, ih = pcall(target.GetSize, target)
	if not (p and l and ok and iw and ih) or Secret(iw) or Secret(ih) or iw <= 4 or ih <= 4 then
		return
	end
	rim:ClearAllPoints()
	rim:SetPoint("CENTER", target, "CENTER")
	rim:SetSize((iw - 4) * p.w / (p.w - l - r), (ih - 4) * p.h / (p.h - t - b))
end

-- a new Button Border has a new opening: every rim fitted again
Kit:OnBorderChanged("button", function()
	for _, entry in ipairs(itemRims) do
		FitItemRim(entry)
	end
end)

local function SkinItemSlot(button, row)
	if not (button and button.GetObjectType) or done[button] or button.melloRep ~= nil then
		return
	end
	done[button] = true
	local icon = IconOf(button)
	local square = SquareOf(button, row, icon)
	local extra = List(button.GetPushedTexture and button:GetPushedTexture(), button.GetHighlightTexture and button:GetHighlightTexture(),
		button.GetCheckedTexture and button:GetCheckedTexture())
	-- an item frame drawn as the NormalTexture round a separate icon (the
	-- item button's quickslot square) is slot art too; a NormalTexture that
	-- IS the item's picture (no icon of its own) stays
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if icon and normal and normal ~= icon and normal ~= button.IconBorder and normal ~= square then
		extra[#extra + 1] = normal
	end
	for i = #extra, 1, -1 do
		if extra[i] == square or extra[i] == icon then
			table.remove(extra, i)
		end
	end
	local host = button
	if square and square:GetParent() ~= button then
		host = CreateFrame("Frame", nil, square:GetParent())
		host:EnableMouse(false)
		host:SetAllPoints(icon or button)
		local okL, lv = pcall(button.GetFrameLevel, button)
		if okL and type(lv) == "number" and not Secret(lv) then
			host:SetFrameLevel(lv + 1)
		end
	end
	local checked = nil
	if host ~= button and button.GetChecked then
		checked = function()
			return button:GetChecked()
		end
	end
	local rep = Replace(square or button, { as = Kit:ButtonRimRule(), button = host, parent = host, rect = icon or button,
		noFade = square == nil, checked = checked, alsoFade = extra })
	-- the rim's hooks (OnEnter / OnMouseDown ...) turn a frame's mouse on: a
	-- host over the item's icon would catch its clicks, so off again (the
	-- button's own hooks below give the rim its hover and press)
	if host ~= button then
		host:EnableMouse(false)
	end
	button.melloRep = rep or false
	if not rep then
		return
	end
	local entry = { button = button, host = host, icon = icon, rep = rep, row = row, square = square }
	itemRims[#itemRims + 1] = entry
	Kit:RegisterButtonRim(button)
	FitItemRim(entry)
	if host ~= button then
		-- hover and press from the button (the rim's own frame takes no mouse)
		local function Set(hover, pressed)
			local rim = rep.object
			rim.hover, rim.pressed = hover, pressed
			if active and rim.Update then
				rim:Update()
			end
		end
		Perf.HookScript(button, "OnEnter", function() Set(true, nil) end)
		Perf.HookScript(button, "OnLeave", function() Set(nil, nil) end)
		Perf.HookScript(button, "OnMouseDown", function() Set(true, true) end)
		Perf.HookScript(button, "OnMouseUp", function() Set(true, nil) end)
		if button.SetChecked then
			hooksecurefunc(button, "SetChecked", function()
				local rim = rep.object
				if active and rim.Update then
					rim:Update()
				end
			end)
		end
	end
	stats.rims = stats.rims + 1
end

--------------------------------------------------------------------------------
-- The inbox's rows (MailItem1..7: a button with the item, the sender, the
-- subject and the days left; made by the XML, found by name, else by what
-- they are -- a child of the inbox with an icon button and two strings). The
-- item in the rim; thin ruled lines between the rows faded (the paper and
-- the rims keep the rows apart); the row's texts are the ink's.
--------------------------------------------------------------------------------
local function RowButton(row)
	local name = NameOf(row)
	local b = row.Button or (name and _G[name .. "Button"])
	if b and b.GetObjectType then
		return b
	end
	for _, child in ipairs({ row:GetChildren() }) do
		local kind = child:GetObjectType()
		if (kind == "CheckButton" or kind == "Button") and IconOf(child) then
			return child
		end
	end
	return nil
end

local function IsRow(frame)
	if not RowButton(frame) then
		return false
	end
	local n = 0
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "FontString" then
			n = n + 1
		end
	end
	return n >= 2
end

local function Rows()
	local list = {}
	for i = 1, ROWS_MAX do
		local row = _G["MailItem" .. i]
		if not row then
			break
		end
		list[#list + 1] = row
	end
	local inbox = _G.InboxFrame
	if #list == 0 and inbox then
		for _, child in ipairs({ inbox:GetChildren() }) do
			if IsRow(child) then
				list[#list + 1] = child
			end
		end
	end
	return list
end

-- a thin line (a ruled line, a separator): long and at most 6 px across
local function IsLine(region)
	local ok, w, h = pcall(region.GetSize, region)
	if not (ok and w and h) or Secret(w) or Secret(h) then
		return false
	end
	return (h <= 6 and w >= 60) or (w <= 6 and h >= 60)
end

local function SkinRow(row)
	if done[row] then
		return
	end
	done[row] = true
	SkinItemSlot(RowButton(row), row)
	for _, region in ipairs({ row:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece and IsLine(region) then
			FadeArt(region)
		end
	end
	stats.rows = stats.rows + 1
end

--------------------------------------------------------------------------------
-- Text buttons on the red plates (B1), their labels in their own colour: the
-- parchment rule's exception for button labels -- the ink's walk never enters
-- a button marked melloNoInk. Kit:SkinRedButton knows the game's two button
-- layouts; a button laid out otherwise gets the plate on its LOWEST texture
-- (DialogPanel's way), its other art faded, its label raised over the plate.
-- The plate follows the button's Enable / Disable (the disabled plate, the
-- game's grey label: Send while nobody is named).
--------------------------------------------------------------------------------
local function PlainLabels(button)
	local QI = MelloUI.QuestInk
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "FontString" and region.melloInk and QI and QI.PlainText then
			pcall(QI.PlainText, region)
		end
	end
end

local function SkinTextButton(button)
	if not button then
		return
	end
	button.melloNoInk = true
	PlainLabels(button)
	if button.melloRep ~= nil then
		return
	end
	local ok, rep = pcall(Kit.SkinRedButton, Kit, button, Replace)
	if ok and rep then
		stats.buttons = stats.buttons + 1
		return
	end
	local anchor, extra, anchorRank = nil, {}, 99
	local RANK = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4 }
	for _, region in ipairs({ button:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece then
			local rank = RANK[region:GetDrawLayer()]
			if rank and rank < anchorRank then
				if anchor then
					extra[#extra + 1] = anchor
				end
				anchor, anchorRank = region, rank
			else
				extra[#extra + 1] = region
			end
		end
	end
	for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local tex = button[get] and button[get](button)
		if tex and tex ~= anchor then
			extra[#extra + 1] = tex
		end
	end
	button.melloRep = anchor and Replace(anchor, { as = "_128-RedButton-Center", rect = button, button = button, alsoFade = extra }) or false
	local label = button.GetFontString and button:GetFontString()
	if button.melloRep and label and label.GetDrawLayer then
		local layer, sub = label:GetDrawLayer()
		labelLayers[label] = { layer, sub }
		if active then
			pcall(label.SetDrawLayer, label, "OVERLAY", 7)
		end
	end
	if button.melloRep then
		stats.buttons = stats.buttons + 1
	end
end

local function RaiseLabels(on)
	for label, was in pairs(labelLayers) do
		if on then
			pcall(label.SetDrawLayer, label, "OVERLAY", 7)
		elseif was[1] then
			pcall(label.SetDrawLayer, label, was[1], was[2] or 0)
		end
	end
end

-- buttons the kit's sweep put on a red plate: their labels kept out of the ink too
local function MarkRedButtons(root, depth)
	if not root or depth > 8 then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		local rep = rawget(child, "melloRep")
		if type(rep) == "table" and RED_PLATES[rep.key] and not child.melloNoInk then
			child.melloNoInk = true
			PlainLabels(child)
		end
		MarkRedButtons(child, depth + 1)
	end
end

--------------------------------------------------------------------------------
-- Prev / Next (InboxPrevPageButton / NextPageButton: the spell book's page
-- arrows as file art, their "Prev" / "Next" labels beside them): the kit's
-- arrows at the button's height by that art's existing rule, the button's
-- other textures faded. The arrows have no disabled look: a disabled arrow
-- (the first / last page) is shown at a lower alpha, as the game greys its
-- own, read again after the game's Enable / Disable. The labels lie on the
-- paper: dark ink, as every word on it.
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
-- The radio buttons (Send Money / C.O.D.; UIRadioButtonTemplate, file art
-- with no pushed look): the kit's check box, off / on / hover, as every check
-- box of every window (the consistency rule; the kit has no round radio of
-- its own). The radio's checked dot, highlight and disabled looks are faded
-- here as well (the helper's own list stops at the first look a template
-- lacks). The game disables C.O.D. while nothing is attached: the box is
-- dimmed then, its label greyed by the game (the palette's muted text).
--------------------------------------------------------------------------------
local function RadioLook(entry)
	local tex = entry.rep and entry.rep.object
	if not (active and tex and tex.SetAlpha) then
		return
	end
	local ok, enabled = pcall(entry.button.IsEnabled, entry.button)
	if ok and not Secret(enabled) then
		tex:SetAlpha(enabled and 1 or 0.5)
	end
end

local function SkinRadio(cb)
	if not cb or done[cb] then
		return
	end
	done[cb] = true
	local rep = Kit:SkinCheckButton(cb, Replace, "UI-CheckBox-Up")
	if not rep then
		return
	end
	for _, get in ipairs({ "GetPushedTexture", "GetCheckedTexture", "GetHighlightTexture", "GetDisabledTexture", "GetDisabledCheckedTexture" }) do
		local tex = cb[get] and cb[get](cb)
		if tex then
			FadeArt(tex)
		end
	end
	local entry = { button = cb, rep = rep }
	radios[#radios + 1] = entry
	for _, method in ipairs({ "Enable", "Disable", "SetEnabled" }) do
		if cb[method] then
			hooksecurefunc(cb, method, function()
				RadioLook(entry)
			end)
		end
	end
	stats.radios = stats.radios + 1
end

--------------------------------------------------------------------------------
-- One-line edit boxes (To, Subject, the gold / silver / copper to send: an
-- InputBoxTemplate-like Left / Middle / Right art reaching a few px past the
-- box): the edit plate S1 on the art's own span, focused while typing, its
-- LEFT cap dropped -- that cap is the search glass, and these are a name, a
-- subject and numbers; the plain end piece closes the plate (the chat's and
-- the auction house's rule). The money boxes' coin icons stay over the plate.
--------------------------------------------------------------------------------
local function ThreeSlice(frame)
	local name = NameOf(frame)
	local function Get(...)
		for i = 1, select("#", ...) do
			local key = select(i, ...)
			local v = frame[key] or (name and _G[name .. key])
			if IsTexture(v) then
				return v
			end
		end
	end
	local left, mid, right = Get("Left"), Get("Middle", "Mid", "Center"), Get("Right")
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

local function SkinEdit(edit)
	if done[edit] or edit.melloRep ~= nil or edit.searchIcon then
		return
	end
	done[edit] = true
	local okM, multi = pcall(edit.IsMultiLine, edit)
	if okM and multi and not Secret(multi) then
		return   -- the letter's body: on the paper, no plate
	end
	local left, mid, right = ThreeSlice(edit)
	if not (left and mid and right) then
		return
	end
	local rect = CreateFrame("Frame", nil, edit)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", left, "TOPLEFT")
	rect:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT")
	edit.melloRep = Replace(mid, { as = EDIT_KEY, rect = rect, edit = edit, dropCap = "l", alsoFade = { left, right } }) or false
	if edit.melloRep then
		stats.edits = stats.edits + 1
	end
end

local function SkinEditsIn(root, depth)
	if not root or depth > 6 then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		if child:GetObjectType() == "EditBox" then
			SkinEdit(child)
		elseif child:GetObjectType() ~= "ScrollFrame" then
			SkinEditsIn(child, depth + 1)
		end
	end
end

--------------------------------------------------------------------------------
-- The money bar (SendMailMoneyBg: a ThinGoldEdgeTemplate bar, Left / Middle /
-- Right file pieces known by their names, in a small inset of its own): the
-- coin plate (B2, the bags' money strip), the coins on it. The small inset's
-- art (its marble and rail) is faded: the plate is the box, and a rail round
-- a 20 px plate would stack two frames on one bar.
--------------------------------------------------------------------------------
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
		FadeArt(inset.Bg)
		if inset.NineSlice then
			for _, region in ipairs({ inset.NineSlice:GetRegions() }) do
				if IsTexture(region) and not region.kitPiece then
					FadeArt(region)
				end
			end
		end
		-- (the kit's marker: looked at, nothing to replace -- the sweep leaves it)
		if inset.melloRep == nil then
			inset.melloRep = false
		end
	end
end

--------------------------------------------------------------------------------
-- Scroll bars: a MinimalScrollBar is the kit's; an older one (a Slider with
-- ScrollUpButton / ScrollDownButton and a thumb texture, the stationery's
-- UIPanelScrollFrame bar) gets THE scroll bar the same way (T2 / H1 / S1: the
-- trough on the slider, the gem slab thumb, the kit's arrows), as the
-- trainer window's list.
--------------------------------------------------------------------------------
local SCROLL_ARROWS = {
	["minimal-scrollbar-arrow-top"] = { "ScrollUpButton", "UpButton" },
	["minimal-scrollbar-arrow-bottom"] = { "ScrollDownButton", "DownButton" },
}

local function SkinOldScrollBar(sb)
	if not (type(sb) == "table" and sb.GetObjectType) or sb.melloRep ~= nil then
		return
	end
	if sb.Track and sb.Track.Thumb and sb.Back and sb.Forward then
		Kit:SkinScrollBar(sb, Replace)
		stats.bars = stats.bars + 1
		return
	end
	if sb:GetObjectType() ~= "Slider" then
		return
	end
	local thumb = sb.GetThumbTexture and sb:GetThumbTexture()
	local track = {}
	for _, region in ipairs({ sb:GetRegions() }) do
		if IsTexture(region) and region ~= thumb and not region.kitPiece then
			track[#track + 1] = region
		end
	end
	local reps = {}
	local first = table.remove(track, 1)
	reps[#reps + 1] = Replace(first or sb, { as = "minimal-scrollbar-track-middle", rect = sb, parent = sb, noFade = (first == nil) or nil, alsoFade = track })
	if thumb then
		reps[#reps + 1] = Replace(thumb, { as = "minimal-scrollbar-small-thumb-middle", rect = thumb, button = sb })
	end
	for key, names in pairs(SCROLL_ARROWS) do
		local b = Part(sb, names[1], names[1]) or Part(sb, names[2], names[2])
		local normal = type(b) == "table" and b.GetNormalTexture and b:GetNormalTexture()
		if normal then
			reps[#reps + 1] = Replace(normal, { as = key, button = b, alsoFade = Kit:OtherTextures(b, normal) })
		end
	end
	sb.melloRep = reps
	stats.bars = stats.bars + 1
end

local function SkinScrollBarsIn(root, depth)
	if not root or depth > 8 then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		if child:GetObjectType() == "Slider" and (child.ScrollUpButton or Part(child, nil, "ScrollUpButton")) then
			SkinOldScrollBar(child)
		elseif child.Track and child.Track.Thumb and child.Back and child.Forward then
			SkinOldScrollBar(child)
		else
			SkinScrollBarsIn(child, depth + 1)
		end
	end
end

--------------------------------------------------------------------------------
-- The tabs (Inbox / Send Mail; PanelTabButtonTemplate): TB6 cards by
-- Kit:SkinPanelTab, which also holds the tab's text centred on the card (the
-- game bobs it on select); an older CharacterFrameTabButtonTemplate (Left for
-- the closed tab, LeftDisabled for the open one) gets the same two cards and
-- its text held centred the same way. The Kit's cards follow their tab's
-- textures on every Show / Hide, also while the kit is off; after those
-- hooks this one sets every card from its texture while the kit is on and
-- hides them all while it is off (the macros' and merchants' guard).
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

-- an older tab's text on the card's centre (the game's x kept), while the
-- kit is on; the game's own point back when it is off
local function SteadyOldText(tab)
	local text = tab.Text or Part(tab, nil, "Text")
	if not (text and text.SetPoint) or oldTabTexts[text] then
		return
	end
	local entry = { steady = false }
	oldTabTexts[text] = entry
	local function Steady()
		if not active or entry.steady then
			return
		end
		entry.steady = true
		local okP, point, rel, relPoint, x, y = pcall(text.GetPoint, text, 1)
		if okP and point then
			entry.game = { point, rel, relPoint, x, y }
		end
		text:ClearAllPoints()
		text:SetPoint("CENTER", tab, "CENTER", (okP and type(x) == "number" and not Secret(x)) and x or 0, 0)
		entry.steady = false
	end
	hooksecurefunc(text, "SetPoint", Steady)
	entry.steadyFn = Steady
	Steady()
end

local function UnsteadyOldTexts()
	for text, entry in pairs(oldTabTexts) do
		local g = entry.game
		if g then
			entry.steady = true
			text:ClearAllPoints()
			-- (by index: the relative frame may be nil, a hole unpack would stop at)
			text:SetPoint(g[1], g[2], g[3], g[4] or 0, g[5] or 0)
			entry.steady = false
		end
	end
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
		tab.melloRep = plain or open or false
		Follow(plain, plainTex)
		Follow(open, openTex)
		SteadyOldText(tab)
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
	local name = NameOf(f)
	for i = 1, 4 do
		local tab = name and _G[name .. "Tab" .. i]
		if tab and not seen[tab] then
			seen[tab] = true
			list[#list + 1] = tab
		end
	end
	for _, tab in ipairs(f.Tabs or {}) do
		if not seen[tab] then
			seen[tab] = true
			list[#list + 1] = tab
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- The ink (the parchment rule, user 2026-09-23 / 24: text on parchment is
-- dark ink, meaningful colours -- the days left in red or green, a C.O.D. --
-- as dark shades of their hue, button labels excepted): a QuestInk surface
-- over the pages that lie on the kit's paper (the inbox, the letter being
-- written, the letter being read), inked for the paper's tone (the sheet
-- inks: the page is the vellum in the kit's one parchment tone). Only a
-- string that lies ON the paper is inked; one beside it is a label on a dark
-- panel (above), a title on the plate is the plate's.
--------------------------------------------------------------------------------
local function InkOn()
	return active and skin ~= nil and skin.paper == true
end

local function InkRoots()
	local list = {}
	for _, win in pairs(skin and skin.windows or {}) do
		for _, paper in ipairs(win.papers) do
			list[#list + 1] = paper.root
		end
	end
	return unpack(list)
end

local function InkSkip(fs)
	if titleOwned[fs] then
		return true
	end
	local on = OnPaper(fs)
	if on == nil then
		return nil
	end
	if not on then
		return true
	end
	return MelloUI.QuestInk.DefaultSkip(fs)
end

local function Surface()
	local QI = MelloUI.QuestInk
	if not (QI and QI.Surface) then
		return
	end
	if not surfaceMade then
		surfaceMade = true
		QI.Surface(AREA, { on = InkOn, sheet = true, skip = InkSkip, roots = InkRoots })
	else
		QI.RefreshSurface(AREA)
	end
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

-- The shell every mail window shares: rail, page stone, ring, title, close.
local function BuildShell(frame)
	local win = { frame = frame, followers = skin.followers, titleMoved = {}, titleFaded = {}, papers = {}, spans = {}, stoneRects = {} }
	skin.windows[frame] = win
	win.portrait = PortraitOf(frame)
	local first = #skin.reps + 1
	win.ring = Kit:SkinWindowShell(frame, Replace, win, { portrait = win.portrait, bg = frame.Bg and STONE_KEY or nil })
	for i = first, #skin.reps do
		local rep = skin.reps[i]
		if rep.key == "TitleBar" then
			win.title = rep
		elseif rep.key == STONE_KEY then
			win.stone = rep
		end
	end
	SkinPortrait(win)
	DressInset(win)
	return win
end

-- the game's text buttons of a window, the old scroll bars, the sweep for
-- what is left, and the plates' labels kept out of the ink
local function FinishWindow(frame)
	for _, bname in ipairs(TEXT_BUTTONS) do
		local b = _G[bname]
		if b and IsUnder(b, frame) then
			SkinTextButton(b)
		end
	end
	for _, bname in ipairs(BARS) do
		local bar = _G[bname]
		if bar and IsUnder(bar, frame) then
			FadeArt(bar)
		end
	end
	SkinScrollBarsIn(frame, 0)
	Kit:SweepControls(frame, Replace, skin)
	MarkRedButtons(frame, 0)
end

local function BuildMail(f)
	local win = BuildShell(f)
	win.tabs = Tabs(f)
	for _, tab in ipairs(win.tabs) do
		SkinTab(tab)
	end

	-- the Inbox: its page, the rows, the page arrows
	local inbox = _G.InboxFrame
	if inbox then
		local bg = InboxPaperArt(inbox)
		if bg then
			DressPaper(win, "inbox", { bg }, inbox)
		end
		for _, region in ipairs({ inbox:GetRegions() }) do
			if IsTexture(region) and region ~= bg and not region.kitPiece and IsLine(region) then
				FadeArt(region)
			end
		end
		for _, row in ipairs(Rows()) do
			SkinRow(row)
		end
		SkinArrows()
	end

	-- Send Mail: the stationery, the header block, the controls, the money
	local send = _G.SendMailFrame
	if send then
		local scroll = _G.SendMailScrollFrame
		local sheets = Stationery("Send", scroll)
		if #sheets > 0 then
			DressPaper(win, "send", sheets, scroll)
		end
		DressSpan(win, "send header", send, List(_G.SendMailNameEditBox, _G.SendMailSubjectEditBox, _G.SendMailCostMoneyFrame))
		SkinEditsIn(send, 0)
		for _, rname in ipairs(RADIOS) do
			SkinRadio(_G[rname])
		end
		for i = 1, ATTACH_MAX do
			SkinItemSlot(_G["SendMailAttachment" .. i])
		end
		SkinCoinBar(_G.SendMailMoneyBg, _G.SendMailMoneyInset)
		AddBody(_G.SendMailBodyEditBox)
	end
	FinishWindow(f)
end

local function BuildOpen(of)
	local win = BuildShell(of)
	local scroll = _G.OpenMailScrollFrame
	local sheets = Stationery("Open", scroll)
	if #sheets > 0 then
		DressPaper(win, "letter", sheets, scroll)
	end
	DressSpan(win, "letter header", of, List(_G.OpenMailSender, _G.OpenMailSubject, _G.OpenMailSenderLabel, _G.OpenMailSubjectLabel))
	for i = 1, ATTACH_MAX do
		SkinItemSlot(_G["OpenMailAttachmentButton" .. i])
	end
	SkinItemSlot(_G.OpenMailLetterButton)
	SkinItemSlot(_G.OpenMailMoneyButton)
	AddBody(_G.OpenMailBodyText)
	FinishWindow(of)
end

-- (user, 2026-09-24: dress rarely used windows on first open): a mail window
-- is built the first time it shows -- from its OnShow hook (Hook, below),
-- before its first frame is drawn -- never at login; the letter window on its
-- own first show, which may be long after the mailbox's or never. What was
-- built is kept for the session. True once anything is built.
local function Build()
	local mf, of = Windows()
	if not (mf or of) or not Kit then
		return false
	end
	if mf and not (skin and skin.windows[mf]) and mf:IsShown() then
		skin = skin or { reps = {}, followers = {}, windows = {} }
		BuildMail(mf)
	end
	if of and not (skin and skin.windows[of]) and of:IsShown() then
		skin = skin or { reps = {}, followers = {}, windows = {} }
		BuildOpen(of)
	end
	return skin ~= nil
end

-- a mail window shown that has not been built yet
local function Unbuilt()
	for _, frame in ipairs(List(Windows())) do
		if frame:IsShown() and not (skin and skin.windows[frame]) then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Refreshing: after every show, page switch and game update (a new page of
-- mail, an attachment added, a letter opened) -- what the game re-laid or
-- re-showed since: the papers' and panels' rects, the portraits, the titles,
-- the rows made since, the rims, the arrows and radios, the followers, the
-- labels and the ink. One deferred pass at a time follows, once the game has
-- laid it all out.
--------------------------------------------------------------------------------
local function RefreshWindow(win)
	for _, paper in ipairs(win.papers) do
		FitPaper(paper)
	end
	for _, span in ipairs(win.spans) do
		FitSpan(span)
	end
	FitPortrait(win)
	PlaceTitles(win, true)
end

-- the page stone's rect, noted per page (2a: the same on every page)
local function NoteStone(win, page)
	local inner = win.stone and win.stone.inner
	if not (inner and page) then
		return
	end
	local ok, l, b, w, h = pcall(inner.GetRect, inner)
	if ok and l and not (Secret(l) or Secret(b) or Secret(w) or Secret(h)) then
		win.stoneRects[page] = { l, b, w, h }
	end
end

local function CurrentPage()
	local inbox, send = _G.InboxFrame, _G.SendMailFrame
	if send and send:IsShown() then
		return "Send Mail"
	elseif inbox and inbox:IsShown() then
		return "Inbox"
	end
	return nil
end

local function Pass()
	if not (active and skin) then
		return
	end
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	GuardTabs()
	-- (the mailbox's own parts only once the mailbox is built: the letter
	-- window may have been dressed first)
	local mf = _G.MailFrame
	local mailBuilt = mf ~= nil and skin.windows[mf] ~= nil
	if mailBuilt and mf:IsShown() then
		FadePageStones(_G.InboxFrame, mf)
		FadePageStones(_G.SendMailFrame, mf)
	end
	for _, win in pairs(skin.windows) do
		if win.frame:IsShown() then
			RefreshWindow(win)
		end
	end
	if mailBuilt then
		for _, row in ipairs(Rows()) do
			SkinRow(row)
		end
	end
	for _, entry in ipairs(itemRims) do
		FitItemRim(entry)
	end
	for _, entry in ipairs(arrowReps) do
		ArrowLook(entry)
	end
	for _, entry in ipairs(radios) do
		RadioLook(entry)
	end
	InkBodies(true)
	if surfaceMade then
		MelloUI.QuestInk.RefreshSurface(AREA)
	end
	for _, win in pairs(skin.windows) do
		if win.frame:IsShown() then
			LookPass(win)
		end
	end
end

-- Refresh's pass a frame later, and the mailbox page's stone noted (made
-- once: Kit:NextFrame runs it once however often it was asked -- audit,
-- 2026-09-24; timed on this window's own /melloperf row, not the Kit's
-- timer -- review)
local RefreshLater = Shared("Refresh a frame later", function()
	Pass()
	local mf = _G.MailFrame
	local win = mf and skin and skin.windows[mf]
	local page = CurrentPage()
	if active and win and page and mf:IsShown() then
		NoteStone(win, page)
	end
end, "timer")

local function Refresh()
	if not (active and skin) then
		return
	end
	Pass()
	Kit:NextFrame(skin, RefreshLater)
end

--------------------------------------------------------------------------------
-- Switching on and off
--------------------------------------------------------------------------------
local function Activate()
	if active or not Build() then
		return
	end
	active = true
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for _, obj in ipairs(fadedArt) do
		Kit:Fade(obj)
	end
	RaiseLabels(true)
	for _, entry in pairs(oldTabTexts) do
		if entry.steadyFn then
			entry.steadyFn()
		end
	end
	Surface()
	Refresh()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	for _, obj in ipairs(fadedArt) do
		Kit:Unfade(obj)
	end
	-- the tabs' cards hidden for good while off (the rings' onDisable put the
	-- portraits back, the title plates' the titles' points and font)
	GuardTabs()
	UnsteadyOldTexts()
	RaiseLabels(false)
	for _, win in pairs(skin.windows) do
		PlaceTitles(win, false)
	end
	for fs in pairs(looks) do
		Unlook(fs)
	end
	InkBodies(false)
	for _, entry in ipairs(radios) do
		local tex = entry.rep and entry.rep.object
		if tex and tex.SetAlpha then
			tex:SetAlpha(1)
		end
	end
	-- every string on the paper back in the game's colours (the surface is off now)
	Surface()
end

local function Sync()
	if M.isEnabled and (_G.MailFrame or _G.OpenMailFrame) then
		Activate()
	else
		Deactivate()
	end
end

-- (the mail windows are not protected; the switch is queued out of combat as
-- the other windows' skins are)
local function SyncSafe()
	Kit:WhenOutOfCombat(Sync)
end

-- A mail window's first show (user, 2026-09-24: dress rarely used windows on
-- first open): its look built and switched on now, in its OnShow, so the
-- first frame it draws is dressed. Also in combat: the build makes frames and
-- textures of ours, and what of the game's it moves are regions of these
-- unprotected windows (the portrait, the title and tab strings) -- nothing
-- protected, and MailFrame is never moved -- so a first open in a fight is
-- dressed at once instead of showing the stock window until it ends.
local function Dress()
	if not active then
		Sync()
		return
	end
	-- a window first shown while the kit is on (the letter after the
	-- mailbox): its pieces were enabled as they were made, before their own
	-- enable (the ring's portrait fit, its disc) was chained on -- enabled
	-- once more now
	local first = #skin.reps + 1
	Build()
	for i = first, #skin.reps do
		skin.reps[i]:Enable()
	end
end

-- (listen-only until a window is built: every handler here does nothing while
-- the kit is off)
local function Hook()
	local mf, of = Windows()
	if hooked or not (mf or of) then
		return
	end
	hooked = true
	for _, frame in ipairs(List(mf, of, _G.InboxFrame, _G.SendMailFrame)) do
		Perf.HookScript(frame, "OnShow", function()
			if M.isEnabled and (not active or Unbuilt()) then
				Dress()
			end
			Refresh()
		end)
	end
	-- the game's own updates (a page of mail, an attachment, the C.O.D.
	-- choice, a letter opened, a tab clicked): post-hooks only
	for _, fname in ipairs({ "InboxFrame_Update", "SendMailFrame_Update", "OpenMail_Update", "MailFrameTab_OnClick", "OpenMailFrame_UpdateButtonPositions" }) do
		if type(_G[fname]) == "function" then
			hooksecurefunc(fname, Refresh)
		end
	end
end

local events = CreateFrame("Frame")
Perf.SetScript(events, "OnEvent", function()
	if M.isEnabled and not active and (_G.MailFrame or _G.OpenMailFrame) then
		events:UnregisterAllEvents()
		Hook()
		SyncSafe()
	end
end)

function M:OnEnable(db)
	self.db = db
	if _G.MailFrame or _G.OpenMailFrame then
		Hook()
		SyncSafe()
	else
		events:RegisterEvent("ADDON_LOADED")
		events:RegisterEvent("PLAYER_LOGIN")
	end
end

function M:OnDisable()
	events:UnregisterAllEvents()
	SyncSafe()
end

--------------------------------------------------------------------------------
-- /maildump [rows | send | open | ink | reps | frames | regions] [open]: with
-- no mode, the mailbox's shell (portrait against the medallion, the title's
-- place and font), both tabs and the page picture on each page, its papers,
-- panels and parts, and the inked strings with their colours; rows / send /
-- open the parts of one page (open: the letter window's shell too); reps /
-- frames / regions are Kit:DumpWindow's (add "open" for the letter window).
-- Opens the copy window.
--------------------------------------------------------------------------------
local function Num(v)
	if v == nil then
		return "nil"
	end
	if Secret(v) then
		return "[secret]"
	end
	return type(v) == "number" and string.format("%.0f", v) or tostring(v)
end

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

local function Shown(obj)
	if not obj then
		return "-"
	end
	local ok, s = pcall(obj.IsShown, obj)
	return (ok and not Secret(s)) and tostring(s) or "?"
end

local function Found(what, obj, more)
	MelloUI:Print("  %-24s %s%s", what, obj and Label(obj) or "-- not found", more or "")
end

local function RectOf(obj)
	if not obj then
		return "-"
	end
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if not (ok and l) or Secret(l) then
		return "(no rect)"
	end
	return string.format("x %s y %s w %s h %s", Num(l), Num(b), Num(w), Num(h))
end

local function RepState(rep)
	if rep == nil then
		return "not looked at"
	elseif rep == false then
		return "not dressed"
	end
	local obj = rep.object
	local ok, shown = pcall(function() return obj and obj:IsShown() end)
	return tostring(rep.key) .. ((ok and shown) and " (shown)" or " (hidden)")
end

local function FadedState(obj)
	if not obj then
		return "-"
	end
	return Kit.faded[obj] and "faded" or (done[obj] and "known, not faded" or "untouched")
end

local function Colour(fs)
	local ok, r, g, b = pcall(fs.GetTextColor, fs)
	if not ok or type(r) ~= "number" or Secret(r) or Secret(g) or Secret(b) then
		return "?"
	end
	return string.format("%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function FontOf(fs)
	local ok, path, size = pcall(fs.GetFont, fs)
	if not ok or not path or Secret(path) then
		return "?"
	end
	return string.format("%s %s", tostring(path):match("([^\\/]+)$") or tostring(path), Num(size))
end

local function DumpShell(win)
	local f = win.frame
	local okLv, lv = pcall(f.GetFrameLevel, f)
	MelloUI:Print("%s: shown %s, level %s, kit %s", Label(f), Shown(f), okLv and Num(lv) or "?", active and "on" or "off")
	Found("outer rail (NineSlice)", f.NineSlice, f.NineSlice and (" layout " .. tostring(f.NineSlice.layoutType)) or " (no shell)")
	Found("page stone (Bg)", f.Bg, win.stone and string.format(" -> %s, inner %s", RepState(win.stone), RectOf(win.stone.inner)) or " (not dressed)")
	-- the portrait against the medallion (2b)
	local portrait = win.portrait
	local ringTex = win.ring and win.ring.tex
	local okR, rw = false, nil
	if ringTex then
		okR, rw = pcall(ringTex.GetWidth, ringTex)
	end
	local medallion = (okR and type(rw) == "number" and not Secret(rw)) and rw * 0.759 or nil
	if portrait then
		local okS, w, h = pcall(portrait.GetSize, portrait)
		MelloUI:Print("  portrait %s art %s size %s x %s, medallion %s (ring %s), fitted %s, disc %s, stand-in %s",
			Label(portrait), tostring(ArtOf(portrait) or "none"), okS and Num(w) or "?", okS and Num(h) or "?", Num(medallion),
			okR and Num(rw) or "?", tostring(portrait.melloSaved ~= nil), tostring(win.ring and win.ring.disc ~= nil),
			win.standIn and Shown(win.standIn) or "-")
	else
		Found("portrait", nil)
	end
	Found("ring", win.ring and win.ring.object, win.ring and (" " .. RepState(win.ring)) or nil)
	-- the title (2c): where it is and in which font
	local list, own = TitleStrings(f)
	if own then
		local text, secret = TextOf(own)
		local okP, point, rel = pcall(own.GetPoint, own, 1)
		local onPlate = okP and win.title ~= nil and win.title.strip ~= nil and rel == win.title.strip
		MelloUI:Print("  title %s text %s, font %s, title face %s, on the plate %s (%s), plate %s", Label(own),
			secret and "[secret]" or tostring(text or "(empty)"), FontOf(own), tostring(own.melloFontSaved ~= nil),
			tostring(onPlate or false), okP and tostring(point) or "?", RepState(win.title))
	else
		Found("title container text", nil)
	end
	for _, fs in ipairs(list) do
		local text, secret = TextOf(fs)
		MelloUI:Print("  other title %s text %s, moved onto the plate %s, faded %s, font %s", Label(fs),
			secret and "[secret]" or tostring(text or "(empty)"), tostring(win.titleMoved[fs] ~= nil), tostring(win.titleFaded[fs] == true), FontOf(fs))
	end
	local inset = win.inset or f.Inset
	Found("inset (L1, dim 0.8)", inset, inset and string.format(" %s, %s, rail %s", RepState(rawget(inset, "melloRep")), RectOf(inset), Num(win.insetRail)) or nil)
	for _, paper in ipairs(win.papers) do
		MelloUI:Print("  paper %s: %s on %s, clipped to the inset %s, game art %s", paper.name, RepState(paper.rep), RectOf(paper.rect),
			tostring(paper.clipped == true), FadedState(paper.parts[1]))
	end
	for _, span in ipairs(win.spans) do
		MelloUI:Print("  dark panel %s: %s on %s, inside the inset %s", span.name, RepState(span.rep), RectOf(span.rect), tostring(span.inside == true))
	end
end

local function DumpTabs(win)
	for _, tab in ipairs(win.tabs or {}) do
		local kind = "unknown template"
		local plainTex, openTex
		if tab.Left and tab.LeftActive then
			kind, plainTex, openTex = "TB6 (Left / LeftActive)", tab.Left, tab.LeftActive
		elseif Part(tab, "LeftDisabled", "LeftDisabled") then
			kind, plainTex, openTex = "older (Left / LeftDisabled)", Part(tab, "Left", "Left"), Part(tab, "LeftDisabled", "LeftDisabled")
		end
		local cards = {}
		for _, entry in ipairs(tabReps) do
			if entry.region == plainTex or entry.region == openTex then
				cards[#cards + 1] = (entry.region == openTex and "open " or "plain ") .. Shown(entry.rep.object)
			end
		end
		local text = tab.Text or Part(tab, nil, "Text")
		local tp = "?"
		if text then
			local okP, point, rel, relPoint, x, y = pcall(text.GetPoint, text, 1)
			if okP and point then
				tp = string.format("%s on %s %s %s,%s", tostring(point), Label(rel), tostring(relPoint), Num(x), Num(y))
			end
		end
		Found("tab", tab, string.format(" %s, dressed %s, cards [%s], text %s", kind, tostring(tab.melloRep ~= nil and tab.melloRep ~= false),
			table.concat(cards, ", "), tp))
	end
end

local function DumpRows()
	for i, row in ipairs(Rows()) do
		local button = RowButton(row)
		local rim
		for _, entry in ipairs(itemRims) do
			if entry.button == button then
				rim = entry
			end
		end
		local parts = {}
		for _, key in ipairs({ "Sender", "Subject", "ExpireTime" }) do
			local fs = Part(row, key, key)
			if fs and fs.GetObjectType and fs:GetObjectType() ~= "FontString" then
				fs = Part(fs, "Text", "Text")
			end
			if fs and fs.GetText then
				local text, secret = TextOf(fs)
				parts[#parts + 1] = string.format("%s %q #%s ink %s", key, secret and "[secret]" or tostring(text or ""):sub(1, 24), Colour(fs), tostring(fs.melloInk == true))
			end
		end
		MelloUI:Print("  row %d %s shown %s: rim %s (on %s, square %s %s), %s", i, Label(row), Shown(row),
			rim and RepState(rim.rep) or "none", rim and (rim.host == rim.button and "the button" or "the row") or "-",
			rim and Label(rim.square) or "-", rim and FadedState(rim.square) or "-", table.concat(parts, "; "))
	end
	for _, entry in ipairs(arrowReps) do
		local ok, enabled = pcall(entry.button.IsEnabled, entry.button)
		Found("page arrow", entry.button, string.format(" %s, enabled %s", RepState(entry.rep), ok and tostring(enabled) or "?"))
	end
	local oa = _G.OpenAllMail
	Found("Open All", oa, oa and (" " .. RepState(rawget(oa, "melloRep")) .. ", noInk " .. tostring(oa.melloNoInk == true)) or nil)
end

local function DumpSend()
	local send = _G.SendMailFrame
	Found("SendMailFrame", send, send and (" shown " .. Shown(send)) or nil)
	for _, name in ipairs({ "SendMailNameEditBox", "SendMailSubjectEditBox", "SendMailMoneyGold", "SendMailMoneySilver", "SendMailMoneyCopper" }) do
		local e = _G[name]
		Found("edit box", e, e and (" " .. RepState(rawget(e, "melloRep"))) or nil)
	end
	for _, entry in ipairs(radios) do
		local ok, checked = pcall(entry.button.GetChecked, entry.button)
		Found("radio", entry.button, string.format(" %s, checked %s", RepState(entry.rep), ok and tostring(checked) or "?"))
	end
	for i = 1, ATTACH_MAX do
		local b = _G["SendMailAttachment" .. i]
		if b then
			Found("attachment " .. i, b, " " .. RepState(rawget(b, "melloRep")))
		end
	end
	local bar = _G.SendMailMoneyBg
	Found("money bar", bar, bar and (" middle " .. FadedState(Part(bar, "Middle", "Middle"))) or nil)
	for _, entry in ipairs(bodies) do
		Found("letter body", entry.obj, string.format(" %s, inked %s", entry.kind, tostring(entry.saved ~= nil)))
	end
	for _, bname in ipairs(BARS) do
		if _G[bname] then
			Found("horizontal bar", _G[bname], " " .. FadedState(_G[bname]))
		end
	end
end

local function DumpOpen()
	local of = _G.OpenMailFrame
	local win = of and skin and skin.windows[of]
	if not win then
		MelloUI:Print("OpenMailFrame: %s", of and "not dressed yet (the kit dresses it the first time a letter is opened)" or "not on this client")
		return
	end
	DumpShell(win)
	for i = 1, ATTACH_MAX do
		local b = _G["OpenMailAttachmentButton" .. i]
		if b then
			Found("attachment " .. i, b, " " .. RepState(rawget(b, "melloRep")) .. ", shown " .. Shown(b))
		end
	end
	for _, name in ipairs({ "OpenMailLetterButton", "OpenMailMoneyButton" }) do
		local b = _G[name]
		Found(name, b, b and (" " .. RepState(rawget(b, "melloRep"))) or nil)
	end
end

-- the inked strings with their colours, and the labels on the dark panels
local function DumpText(root)
	local QI = MelloUI.QuestInk
	local def = QI and QI.surfaces and QI.surfaces[AREA]
	local n = 0
	if def then
		for fs in pairs(def.strings) do
			if IsUnder(fs, root) then
				n = n + 1
				if n <= 40 then
					local text, secret = TextOf(fs)
					MelloUI:Print("  ink %s %s #%s: %s", tostring(fs.melloInk == true), Label(fs), Colour(fs), secret and "[secret]" or tostring(text or ""):sub(1, 40))
				end
			end
		end
		MelloUI:Print("ink surface: on %s, strings in this window %d", tostring(def.active == true), n)
	else
		MelloUI:Print("ink surface: not made")
	end
	local m = 0
	for fs, entry in pairs(looks) do
		if IsUnder(fs, root) then
			m = m + 1
			local text, secret = TextOf(fs)
			MelloUI:Print("  label %s (%s, on %s) #%s %s: %s", Label(fs), tostring(entry.role), tostring(entry.on == true), Colour(fs), FontOf(fs),
				secret and "[secret]" or tostring(text or ""):sub(1, 30))
		end
	end
	MelloUI:Print("labels on the dark panels: %d", m)
end

-- 2a: the page picture's rect noted on each page (one picture on the
-- window's rect: it must not move between the tabs)
local function DumpStone(win)
	local rects, first, same = {}, nil, true
	for page, r in pairs(win.stoneRects) do
		rects[#rects + 1] = string.format("%s: x %s y %s w %s h %s", page, Num(r[1]), Num(r[2]), Num(r[3]), Num(r[4]))
		if first then
			for k = 1, 4 do
				same = same and math.abs(first[k] - r[k]) < 0.5
			end
		else
			first = r
		end
	end
	MelloUI:Print("  page picture per page: %s%s", #rects > 0 and table.concat(rects, "; ") or "(open each tab once first)",
		#rects > 1 and (same and " -- the same on both" or " -- MOVED between the pages") or "")
end

SLASH_MELLOMAILDUMP1 = "/maildump"
SlashCmdList.MELLOMAILDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local mode, arg = msg:match("^(%S*)%s*(%S*)$")
	local mf, of = Windows()
	MelloUI:ClearLog()
	if not (mf or of) then
		MelloUI:Print("/maildump: no MailFrame on this client")
	elseif mode == "reps" or mode == "frames" or mode == "regions" then
		local root = (arg == "open") and of or mf
		if root and not (skin and skin.windows[root]) then
			MelloUI:Print("%s: not dressed yet (the kit dresses it on its first open this session)", Label(root))
		end
		if root then
			Kit:DumpWindow(root, skin, mode ~= "regions" and mode or nil)
		end
	elseif mode == "open" then
		DumpOpen()
		if of then
			DumpText(of)
		end
	else
		local win = mf and skin and skin.windows[mf]
		MelloUI:Print("Mailbox kit: module %s, dressed %s, built %s, paper %s, page now %s", tostring(M.isEnabled == true), tostring(active),
			tostring(win ~= nil), tostring(skin and skin.paper or false), tostring(CurrentPage() or "none"))
		if not win then
			MelloUI:Print("MailFrame: not dressed yet (the kit dresses it on its first open this session)")
		elseif mode == "rows" then
			DumpRows()
			DumpText(_G.InboxFrame or mf)
		elseif mode == "send" then
			DumpSend()
			DumpText(_G.SendMailFrame or mf)
		elseif mode == "ink" then
			DumpText(mf)
		else
			DumpShell(win)
			DumpTabs(win)
			DumpStone(win)
			MelloUI:Print("  rows %d, item rims %d, edit plates %d, radios %d, red plates %d, arrows %d, tabs %d, coin plates %d, scroll bars %d, papers %d, dark panels %d, faded art %d",
				stats.rows, stats.rims, stats.edits, stats.radios, stats.buttons, stats.arrows, stats.tabs, stats.plates, stats.bars, stats.papers, stats.panels, #fadedArt)
			DumpRows()
			DumpSend()
			DumpText(mf)
		end
	end
	MelloUI:ShowLog("maildump " .. msg)
end
