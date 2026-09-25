--------------------------------------------------------------------------------
-- MelloUI - Channels Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): the chat channels window (ChannelFrame of the load-on-demand
-- Blizzard_Channels, opened from the social window or the chat menu; a
-- ButtonFrameTemplate window: the channel list on the left, the selected
-- channel's members on the right, Add and Settings under them) dressed in
-- the painted kit (Modules/Kit.lua) on the game's own layout, as every other
-- window is (docs/WINDOW-RULES.md): every kit piece stands in for one of the
-- game's art regions, on that region's rectangle, the game's art faded in
-- its place; nothing of the game's is moved but the portrait (brought to the
-- medallion size and put back on disable).
--
--   the window shell     outer double rail with gem corners, the page stone,
--                        the ring with the window's chat-bubble icon (its
--                        Icon, the Battle.net bubble) at the class
--                        medallion's size on the dark disc (2b), the title
--                        plate on the rail with "Chat Channels" ON it in the
--                        title face (2c), the close button
--   the two lists        LeftInset / RightInset as the list box L1: single
--                        rail, the list stone under the palette's inner
--                        panel (2e), kept under the lists' rows
--   channel rows         the row picture (voicechat-channellist-row-
--                        background) faded; every other row of a category
--                        striped in the main window tone (2e), the plate's
--                        hover look while the mouse is on the row, the
--                        selected plate on the channel the game selects (it
--                        locks the row's highlight: faded, the plate stands in)
--   category headers     voicechat-channellist-category-background -> the
--                        category plate (closed), the game's additive hover
--                        kept; the +/- glyph -> the kit's plus / minus,
--                        switched with the atlas the game puts there
--   member rows          the same row picture faded, stripes and the hover
--                        plate, as the channel rows
--   voice toggles        the headset / transcription / mute / deafen buttons
--                        (small icon buttons): the cog plate under the
--                        game's glyph (K2), the glyph kept
--   Add / Settings       the red plates (B1), labels readable on them
--   scroll bars          THE scroll bar (T2 / H1 / S1) by the sweep
--   new channel popup    CreateChannelPopup (a DialogBorderTemplate box): the
--                        single rail with stone under the inner panel, the
--                        header band on the header plate with its text in
--                        the title face, the edit boxes on the edit plate
--                        (its left cap dropped: no search glass on a name
--                        box), OK / Cancel on red plates, the kit's close
--
-- Nothing of MelloUI touched this window before: the chat window's own
-- channel / voice buttons are ChatPanel's (children of the chat frames, not
-- of this window), and the social window (SocialPanel) has no channels pane
-- on this client.
--
-- The window is dressed on its first show, not at login (user, 2026-09-24:
-- "dress rarely used windows on first open"; see Sync).
--
-- Taint: nothing of the game's is replaced or re-scripted. The skin is made
-- and kept from post-hooks (the list's Update / SetSelectedChannel, a row's
-- SetIsSelectedChannel, the glyph's SetAtlas, HookScript on shows and on the
-- rows' OnEnter / OnLeave); what it keeps about the game's frames lives in
-- weak side tables; no channel, voice or chat function is ever called. The
-- window is never moved or reparented (Unlock the Windows keeps working).
-- Switching the module off disables every replacement (the game's art faded
-- back in, ours hidden) and puts the portrait and the title back.
--
-- /channeldump [frames | reps | regions | popup]: what the window is made of
-- on this client and what the skin dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("ChannelPanel")
local hooksecurefunc = Perf.hooksecurefunc
-- a handler made once and run for many asks, wrapped once: its time stays
-- on this file's own /melloperf row (review, 2026-09-24)
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("ChannelPanel", {
	title = "Channels Kit",
	desc = "The chat channels window in the kit.",
	window = { label = "Chat channels", desc = "The chat channels window in the kit.", tab = "Windows",
		addon = "Blizzard_Channels", firstOpen = true },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local ADDON = "Blizzard_Channels"
local STRIPE_ALPHA = 0.85   -- WINDOW-RULES 2e: rows striped in the main window tone at about 0.85
local CHAT_ICON = "Interface\\FriendsFrame\\Battlenet-Portrait"   -- the window's own chat bubble (its Icon's art): the ring is never empty
local ICON_BUTTON_MAX = 34  -- a voice toggle is a small square button (27 px in this window's templates)

local skin = nil          -- { reps = { every replacement }, followers = { { rep, region } } }
local active = false
local hooked = false

-- what this module made or looked at, kept OFF the game's frames (weak keys)
local done = setmetatable({}, { __mode = "k" })         -- [frame / region] = true: looked at once
local rowInfo = setmetatable({}, { __mode = "k" })      -- [row] = { header, list, stripe, hover, selected, plate, glyph, plus, minus }
local hoverRows = setmetatable({}, { __mode = "k" })    -- [row] = true while the mouse is on it
local iconButtons = setmetatable({}, { __mode = "k" })  -- [button] = its cog plate rep (false: looked at, nothing made)
local fadedArt = {}                                     -- game art faded with no piece of its own on its rect
local titleMoved = {}                                   -- [fs] = { points } while on the plate
local titleFaded = {}                                   -- [fs] = true while faded as a duplicate
local boxes = {}                                        -- the list boxes { rep, content, label, inset }
local popupSkin = nil                                   -- the new channel popup: { nine, dim, art, header, title }
local stats = { rows = 0, headers = 0, members = 0, icons = 0, edits = 0 }

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

local function IsActive()
	return active
end

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local ok, rep, key = pcall(Kit.Replace, Kit, region, opts)
	if not ok then
		MelloUI:Notice("Channels kit: could not dress %s (%s)", tostring(opts and opts.as), tostring(rep))
		return nil
	end
	if not rep then
		if key then
			MelloUI:Notice("Channels kit: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- A replacement whose visibility is the module's to decide (a hover plate, a
-- selected plate, one of two glyphs): after the library's own Enable (which
-- shows it) `sync` puts the wanted state back.
local function AfterEnable(rep, sync)
	if not rep then
		return
	end
	local enable = rep.Enable
	rep.Enable = function(self, ...)
		enable(self, ...)
		sync()
	end
end

-- the non-nil values given, as a list
local function Compact(...)
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

local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	if ok and type(text) == "string" and not Secret(text) and text ~= "" then
		return text
	end
	return nil
end

local function Shown(obj)
	local ok, s = pcall(obj.IsShown, obj)
	return ok and not Secret(s) and s == true
end

-- Art faded while the kit is on with no piece on its own rect (a row's
-- picture: the stripe and the plates stand in for it)
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
	return _G.ChannelFrame
end

local function Popup()
	return _G.CreateChannelPopup
end

local function ChannelList(f)
	return f and f.ChannelList or nil
end

local function Roster(f)
	return f and f.ChannelRoster or nil
end

-- The window's portrait: its own Icon (the chat bubble the XML lays over the
-- portrait corner), else the template's portrait.
local function Portrait(f)
	local pc = f and f.PortraitContainer
	return (f and f.Icon) or (pc and pc.portrait) or (f and f.portrait) or _G.ChannelFrameIcon
end

--------------------------------------------------------------------------------
-- The portrait (WINDOW-RULES 2b / 2c: an empty ring is a bug). The game's
-- chat bubble is brought to the class medallion's size in the kit's ring
-- (Kit:FitPortrait, aspect kept) on the dark disc (Kit:RingDisc: the bubble
-- is no full round picture), as the social window's same icon. Should this
-- client leave the icon blank or hidden, the bubble is put in it while the
-- kit is on (and taken out on disable), so the ring is never empty.
--------------------------------------------------------------------------------
local portraitFilled = setmetatable({}, { __mode = "k" })   -- [texture] = { art = set by us, shown = shown by us }

local function PortraitArt(t)
	local ok, file = pcall(t.GetTexture, t)
	if ok and not Secret(file) and file ~= nil and (type(file) == "number" and file > 0 or type(file) == "string" and file ~= "") then
		return file
	end
	return nil
end

local function FillPortrait(portrait, on)
	if on then
		local entry = portraitFilled[portrait] or {}
		if not PortraitArt(portrait) then
			pcall(portrait.SetTexture, portrait, CHAT_ICON)
			entry.art = true
		end
		if not Shown(portrait) then
			pcall(portrait.Show, portrait)
			entry.shown = true
		end
		portraitFilled[portrait] = entry
	else
		local entry = portraitFilled[portrait]
		if entry then
			if entry.art then
				pcall(portrait.SetTexture, portrait, nil)
			end
			if entry.shown then
				pcall(portrait.Hide, portrait)
			end
			portraitFilled[portrait] = nil
		end
	end
end

local function FitPortrait()
	if active and skin and skin.ring and skin.portrait then
		pcall(Kit.FitPortrait, Kit, skin.portrait, skin.ring)
	end
end

local function SkinPortrait(f, ring)
	local portrait = Portrait(f)
	if not (ring and portrait) then
		return
	end
	skin.ring, skin.portrait = ring, portrait
	ring.onEnable = function()
		FillPortrait(portrait, true)
		pcall(Kit.FitPortrait, Kit, portrait, ring)
	end
	ring.onDisable = function()
		pcall(Kit.UnfitPortrait, Kit, portrait)
		FillPortrait(portrait, false)
	end
	-- (chains onto the fit above; a region of the window, BACKGROUND over its
	-- rock and under the OVERLAY icon)
	Kit:RingDisc(ring, nil, f, 0)
	hooksecurefunc(portrait, "SetTexture", function()
		if active then
			FitPortrait()
		end
	end)
end

--------------------------------------------------------------------------------
-- The title (WINDOW-RULES 2c: the title ON the plate, in the title face).
-- The shell's plate centres the title container's TitleText (SetTitle writes
-- "Chat Channels" there) on itself in Kit:TitleFont, which follows the Fonts
-- options and the Font Style, and puts it back on disable. A client whose
-- window carries its own TitleText too (an older ChannelFrame.xml lays one
-- on the frame) gets that string moved onto the plate in the title face, or
-- faded where the container already shows the same words there.
--------------------------------------------------------------------------------
local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
	end
end

local function TitleStrings(f)
	local tc = f.TitleContainer
	local own = tc and tc.TitleText
	local words = {}
	if type(_G.CHAT_CHANNELS) == "string" then
		words[_G.CHAT_CHANNELS] = true
	end
	if own and TextOf(own) then
		words[TextOf(own)] = true
	end
	local list, seen = {}, { [own or false] = true }
	local function Add(fs, named)
		if fs and not seen[fs] and fs.GetObjectType and fs:GetObjectType() == "FontString" then
			local text = TextOf(fs)
			if text and (named or words[text]) then
				seen[fs] = true
				list[#list + 1] = fs
			end
		end
	end
	Add(f.TitleText, true)
	Add(_G.ChannelFrameTitleText, true)
	for _, holder in ipairs(Compact(f, tc, f.NineSlice)) do
		if holder.GetRegions then
			for _, region in ipairs({ holder:GetRegions() }) do
				Add(region, false)
			end
		end
	end
	return list, own
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
	if rep.object and rep.object:IsShown() and rep.Refit then
		rep:Refit()
	end
	local list, own = TitleStrings(f)
	if own and not own.melloFontSaved then
		Kit:TitleFont(own, true)
	end
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
-- The two list boxes (WINDOW-RULES 2e: the channel names and the members are
-- small text, never on the plain brown). The window's LeftInset / RightInset
-- (InsetFrameTemplate round the channel list and the roster) are dressed WITH
-- their body (Kit:SkinInset): the list stone under the palette's inner panel
-- inside the single rail (the inset rule's `dim`). Their holders are kept
-- under the lists' rows (a holder tied with the rows' level could draw its
-- stone over them). A client without one of the insets gets the same box
-- laid round the list itself.
--------------------------------------------------------------------------------
local function KeepUnder(rep, content)
	local holder = rep and rep.object
	if not (holder and holder.SetFrameLevel and content) then
		return
	end
	local ok, hl, cl = pcall(function() return holder:GetFrameLevel(), content:GetFrameLevel() end)
	if ok and hl and cl and not Secret(hl) and not Secret(cl) and hl >= cl then
		local level = math.max(cl - 1, 0)
		holder:SetFrameLevel(level)
		if rep.skin and rep.skin.SetFrameLevel then
			rep.skin:SetFrameLevel(level)
		end
	end
end

-- what the rows of a list are children of (the level the box must stay under)
local function ListContent(list)
	if not list then
		return nil
	end
	return list.Child or (list.GetScrollChild and list:GetScrollChild()) or list.ScrollBox or list
end

local function SkinBox(f, inset, list, label)
	if not list then
		return
	end
	local content = ListContent(list)
	if inset then
		if done[inset] then
			return
		end
		done[inset] = true
		Kit:SkinInset(inset, Replace, f, true)
		local rep = inset.melloRep
		if rep then
			boxes[#boxes + 1] = { rep = rep, content = content, label = label, inset = inset }
			KeepUnder(rep, content)
		end
		return
	end
	if done[list] then
		return
	end
	done[list] = true
	-- no inset: the list box laid round the list (4 px out, the insets' own
	-- margin round the lists in this window's XML)
	local rect = CreateFrame("Frame", nil, f)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", list, "TOPLEFT", -4, 4)
	rect:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 4, -4)
	local rep = Replace(list, { as = "common-insideframe", parent = f, rect = rect, level = 1, body = true, noFade = true })
	if rep then
		boxes[#boxes + 1] = { rep = rep, content = content, label = label .. " (own box)" }
		KeepUnder(rep, content)
	end
end

local function KeepBoxesUnder()
	for _, box in ipairs(boxes) do
		KeepUnder(box.rep, box.content)
	end
end

--------------------------------------------------------------------------------
-- Small icon buttons (the voice toggles: a channel row's headset and
-- transcription buttons, a member row's mute / deafen buttons; 27 px buttons
-- whose NormalTexture IS the glyph, re-atlased by the game with the state):
-- K2, the cog plate UNDER the game's glyph (the chat window's icon buttons'
-- rule), the glyph and its additive highlight kept.
--------------------------------------------------------------------------------
local function IsIconButton(b)
	if not (b and b.GetObjectType and b:GetObjectType() == "Button" and b.GetNormalTexture and b:GetNormalTexture()) then
		return false
	end
	local fs = b.GetFontString and b:GetFontString()
	if fs and TextOf(fs) then
		return false
	end
	local ok, w, h = pcall(b.GetSize, b)
	if not ok or Secret(w) or Secret(h) or not (w and h) or w <= 0 or h <= 0 then
		-- not laid out yet: the templates' voice buttons are known by key
		return false
	end
	return w <= ICON_BUTTON_MAX and h <= ICON_BUTTON_MAX
end

local function SkinIconButton(b)
	if not b or iconButtons[b] ~= nil then
		return
	end
	local normal = b.GetNormalTexture and b:GetNormalTexture()
	if not normal then
		return
	end
	iconButtons[b] = Replace(normal, { as = "ChatIconButton", button = b, noFade = true }) or false
	if iconButtons[b] then
		stats.icons = stats.icons + 1
	end
end

-- every small icon button under `root` (a row): by key first, then by shape
local VOICE_KEYS = { "SelfDeafenButton", "SelfMuteButton", "MemberMuteButton" }

local function SkinIconButtonsIn(root, depth)
	depth = depth or 0
	if not root or depth > 3 then
		return
	end
	if depth == 0 then
		for _, key in ipairs(VOICE_KEYS) do
			if root[key] then
				SkinIconButton(root[key])
			end
		end
		local speaker = root.Speaker
		if speaker then
			SkinIconButton(speaker.Button)
			if speaker.Transcription then
				SkinIconButton(speaker.Transcription.Button)
			end
		end
	end
	for _, child in ipairs({ root:GetChildren() }) do
		if IsIconButton(child) then
			SkinIconButton(child)
		end
		SkinIconButtonsIn(child, depth + 1)
	end
end

--------------------------------------------------------------------------------
-- The rows (WINDOW-RULES 2e: rows striped in the main window tone on the
-- dark panel; the fixed looks: the plate's hover and selected looks on list
-- rows, the category plate on category headers, the kit's +/-).
--
-- A channel row (ChannelButtonTemplate: the additive row picture as its
-- NormalTexture, the row / selected highlight as its HighlightTexture, which
-- the game switches with SetHighlightAtlas and locks while selected): the
-- picture is faded, a stripe of ours lies under every other row of a
-- category (a region of the row, BACKGROUND -8), the plate's hover look is
-- shown while the mouse is on the row and the selected plate while the game
-- selects it (its locked highlight faded: the plate stands in).
-- A header (ChannelButtonHeaderTemplate): its picture -> the category plate
-- (closed), the game's additive hover kept (the plate has no hover look);
-- its Collapsed glyph (voicechat-channellist-category-plus / -minus) -> the
-- kit's plus / minus, following the atlas and the glyph's own show / hide.
-- A member row (ChannelRosterButtonTemplate): the picture faded, the stripe
-- and the hover plate as a channel row's.
--------------------------------------------------------------------------------
local function IsHeader(row)
	if type(row.IsHeader) == "function" then
		local ok, v = pcall(row.IsHeader, row)
		if ok and not Secret(v) then
			return v == true
		end
	end
	return row.Collapsed ~= nil
end

local function IsSelected(row)
	local list = ChannelList(Window())
	if list and type(list.GetSelectedChannelButton) == "function" then
		local ok, sel = pcall(list.GetSelectedChannelButton, list)
		if ok then
			return sel == row
		end
	end
	return false
end

local function SyncRow(row)
	local info = rowInfo[row]
	if not (info and active) then
		return
	end
	-- the game may hand the row a new highlight region with SetHighlightAtlas
	local hl = row.GetHighlightTexture and row:GetHighlightTexture()
	if hl and info.hover and not Kit.faded[hl] then
		FadeArt(hl)
		Kit:Fade(hl)
	end
	local sel = info.list and IsSelected(row) or false
	if info.selected then
		info.selected:SetShown(sel)
	end
	if info.hover then
		info.hover:SetShown(hoverRows[row] == true and not sel)
	end
end

local function SyncGlyph(info)
	if not (active and info and info.glyph) then
		return
	end
	local shown = Shown(info.glyph)
	local key = (Kit:ArtKey(info.glyph) or ""):lower()
	local plus = shown and key:find("plus", 1, true) ~= nil
	if info.plus then
		info.plus:SetShown(plus)
	end
	if info.minus then
		info.minus:SetShown(shown and not plus)
	end
end

local function Stripe(row)
	local tex = row:CreateTexture(nil, "BACKGROUND", nil, -8)
	tex.kitPiece = true
	tex:SetAllPoints(row)
	local c = MelloUI.Palette.mainWindow
	tex:SetColorTexture(c[1], c[2], c[3], STRIPE_ALPHA)
	tex:Hide()
	return tex
end

local function HoverAndSelect(row, info, selectable)
	local hl = row.HighlightTexture or (row.GetHighlightTexture and row:GetHighlightTexture())
	if not hl then
		return
	end
	info.hover = Replace(hl, { as = "FriendsRowHighlight", rect = row, button = row })
	if selectable then
		info.selected = Replace(hl, { as = "Professions_Recipe_Active", rect = row, noFade = true })
	end
	local function Sync()
		SyncRow(row)
	end
	AfterEnable(info.hover, Sync)
	AfterEnable(info.selected, Sync)
	Perf.HookScript(row, "OnEnter", function()
		hoverRows[row] = true
		Sync()
	end)
	Perf.HookScript(row, "OnLeave", function()
		hoverRows[row] = nil
		Sync()
	end)
	if selectable and type(row.SetIsSelectedChannel) == "function" then
		hooksecurefunc(row, "SetIsSelectedChannel", Sync)
	end
	Sync()
end

local function DressHeader(row, info)
	local normal = row.NormalTexture or (row.GetNormalTexture and row:GetNormalTexture())
	if normal then
		info.plate = Replace(normal, { as = "LFGBrowse-Grouping", rect = row })
	end
	local glyph = row.Collapsed
	if glyph then
		info.glyph = glyph
		info.plus = Replace(glyph, { as = "common-button-list-plus", button = row, rect = glyph })
		info.minus = Replace(glyph, { as = "common-button-list-minus", button = row, rect = glyph })
		local function Sync()
			SyncGlyph(info)
		end
		AfterEnable(info.plus, Sync)
		AfterEnable(info.minus, Sync)
		for _, method in ipairs({ "SetAtlas", "Show", "Hide", "SetShown" }) do
			hooksecurefunc(glyph, method, Sync)
		end
		Sync()
	end
	stats.headers = stats.headers + 1
end

-- a channel list row (header or channel), dressed once
local function DressRow(row)
	if not row or rowInfo[row] then
		return rowInfo[row]
	end
	local info = { header = IsHeader(row), list = true }
	rowInfo[row] = info
	if info.header then
		DressHeader(row, info)
		return info
	end
	FadeArt(row.NormalTexture or (row.GetNormalTexture and row:GetNormalTexture()))
	info.stripe = Stripe(row)
	HoverAndSelect(row, info, true)
	SkinIconButtonsIn(row)
	stats.rows = stats.rows + 1
	return info
end

-- a member row, dressed once
local function DressMember(row)
	if not row or rowInfo[row] then
		return rowInfo[row]
	end
	local info = { header = false, list = false }
	rowInfo[row] = info
	FadeArt(row.NormalTexture or (row.GetNormalTexture and row:GetNormalTexture()))
	info.stripe = Stripe(row)
	HoverAndSelect(row, info, false)
	SkinIconButtonsIn(row)
	stats.members = stats.members + 1
	return info
end

-- the channel list's rows in the game's order (its `buttons`, filled on each
-- Update), else the scroll child's shown buttons
local function ChannelRows(list)
	if not list then
		return {}
	end
	if type(list.buttons) == "table" and #list.buttons > 0 then
		return list.buttons
	end
	local rows = {}
	local content = ListContent(list)
	if content and content ~= list then
		for _, child in ipairs({ content:GetChildren() }) do
			if child.GetObjectType and child:GetObjectType() == "Button" and Shown(child) then
				rows[#rows + 1] = child
			end
		end
	end
	return rows
end

-- After each of the game's list updates: new rows dressed, the stripes on
-- every other row of each category (counted from its header), the plates
-- following hover and selection.
local function ListPass()
	local list = ChannelList(Window())
	if not (skin and list) then
		return
	end
	local n = 0
	for _, row in ipairs(ChannelRows(list)) do
		local info = DressRow(row)
		if info then
			if info.header then
				n = 0
				SyncGlyph(info)
			else
				n = n + 1
				if info.stripe then
					info.stripe:SetShown(active and n % 2 == 0)
				end
				SyncRow(row)
			end
		end
	end
end

-- a member row's stripe by its place in the list (the data's index)
local function StripeMember(row)
	local info = rowInfo[row]
	if not (info and info.stripe) then
		return
	end
	local even = false
	for _, method in ipairs({ "GetElementDataIndex", "GetOrderIndex" }) do
		if type(row[method]) == "function" then
			local ok, index = pcall(row[method], row)
			if ok and type(index) == "number" and not Secret(index) then
				even = index % 2 == 0
				break
			end
		end
	end
	info.stripe:SetShown(active and even)
end

local function MemberRow(row)
	DressMember(row)
	StripeMember(row)
	SyncRow(row)
end

local function RosterPass()
	local roster = Roster(Window())
	local box = roster and roster.ScrollBox
	if not (skin and box and box.ForEachFrame) then
		return
	end
	box:ForEachFrame(function(row)
		pcall(MemberRow, row)
	end)
end

--------------------------------------------------------------------------------
-- The new channel popup (CreateChannelPopup: a DialogBorderTemplate box, a
-- DialogHeaderTemplate band with "New Channel", two InputBoxTemplate edit
-- boxes, OK / Cancel, a close button, a voice check box). Dressed as the
-- game's small dialogs are (DialogPanel): the single rail with its stone
-- round the popup, the palette's inner panel over the stone (2e: its labels
-- lie on it), the game's box faded; the header band on the header plate with
-- its text in the title face; each edit box on the edit plate with its left
-- cap dropped (a name box, not a search); the buttons on red plates, the
-- close button and the check box the kit's.
--------------------------------------------------------------------------------
local function PopupArt(p)
	local list, seen = {}, {}
	local function Add(obj)
		if obj and not seen[obj] and obj ~= (popupSkin and popupSkin.nine) then
			seen[obj] = true
			list[#list + 1] = obj
		end
	end
	for _, key in ipairs({ "BG", "Border", "NineSlice", "Bg", "Background" }) do
		Add(p[key])
	end
	for _, region in ipairs({ p:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			local ok, layer = pcall(region.GetDrawLayer, region)
			if ok and (layer == "BACKGROUND" or layer == "BORDER") then
				Add(region)
			end
		end
	end
	return list
end

local function SkinEditBox(box)
	if not (box and box.Middle and box.Left and box.Right) or done[box] then
		return
	end
	done[box] = true
	local rect = CreateFrame("Frame", nil, box)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", box.Left, "TOPLEFT")
	rect:SetPoint("BOTTOMRIGHT", box.Right, "BOTTOMRIGHT")
	if Replace(box.Middle, { as = "common-search-border-middle", rect = rect, edit = box, dropCap = "l", alsoFade = { box.Left, box.Right } }) then
		stats.edits = stats.edits + 1
	end
end

local function ShowPopupSkin(on)
	local ps = popupSkin
	if not ps then
		return
	end
	ps.nine:SetShown(on and true or false)
	for _, obj in ipairs(ps.art) do
		if on then
			Kit:Fade(obj)
		else
			Kit:Unfade(obj)
		end
	end
	if ps.title then
		if on then
			if not ps.title.melloFontSaved then
				Kit:TitleFont(ps.title, true)
			end
		else
			Kit:TitleFont(ps.title, false)
		end
	end
end

local function DressPopup()
	local p = Popup()
	if not p or popupSkin or not skin then
		return
	end
	local ok, nine = pcall(Kit.NineSlice, Kit, p, { prefix = "window/single", scale = Kit.scale * (Kit.frameScale or 1.6),
		gems = false, body = true, level = -1 })
	if not (ok and nine) then
		return
	end
	popupSkin = { nine = nine, art = {} }
	popupSkin.dim = Kit.StoneDim and Kit:StoneDim(nine)
	popupSkin.art = PopupArt(p)
	-- the header band: the header plate on its rect, its text in the title face
	local header = p.Header
	if header then
		local center = header.CenterBG or header.Center
		if center then
			popupSkin.header = Replace(center, { as = "battlenet-friends-main", rect = header,
				alsoFade = Compact(header.LeftBG, header.RightBG, header.Left, header.Right) })
		end
		popupSkin.title = header.Text or header.TitleText
	end
	SkinEditBox(p.Name)
	SkinEditBox(p.Password)
	for _, key in ipairs({ "OKButton", "CancelButton" }) do
		local b = p[key]
		if b then
			b.melloNoInk = true
			Kit:SkinRedButton(b, Replace)
		end
	end
	local close = p.CloseButton
	local normal = close and close.GetNormalTexture and close:GetNormalTexture()
	if normal then
		Replace(normal, { as = "RedButton-Exit", button = close, alsoFade = Kit:OtherTextures(close, normal) })
	end
	-- the check box and any other common control
	Kit:SweepControls(p, Replace, skin)
	ShowPopupSkin(active)
end

--------------------------------------------------------------------------------
-- A piece the game shows and hides itself (the shell's maximize / minimize
-- pair, a tab's cards): shown with its region while the kit is on, hidden
-- for good while it is off (the Kit's own tab hooks follow the textures on
-- every Show / Hide, also while the kit is off: the merchant's guard).
--------------------------------------------------------------------------------
local guarded = setmetatable({}, { __mode = "k" })

local function GuardFollowers()
	for _, entry in ipairs(skin and skin.followers or {}) do
		if active then
			entry.rep:SetShown(entry.region:IsShown())
		elseif entry.rep.object then
			entry.rep.object:Hide()
		end
	end
end

local function HookFollowers()
	for _, entry in ipairs(skin and skin.followers or {}) do
		local region = entry.region
		if region and not guarded[region] and region.Show then
			guarded[region] = true
			for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
				hooksecurefunc(region, method, GuardFollowers)
			end
		end
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
	-- rail with "Chat Channels" on it, the close button
	local portrait = Portrait(f)
	local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = portrait, noRing = portrait == nil, bg = f.Bg and "UI-Background-Rock" or nil })
	SkinPortrait(f, ring)

	-- the two list boxes on the dark panel
	local list, roster = ChannelList(f), Roster(f)
	SkinBox(f, f.LeftInset, list, "channel list")
	SkinBox(f, f.RightInset, roster, "roster")

	-- the rows: the channel list's after the game's own updates, the
	-- roster's as its scroll box lays them out
	if list then
		for _, method in ipairs({ "Update", "SetSelectedChannel" }) do
			if type(list[method]) == "function" then
				hooksecurefunc(list, method, ListPass)
			end
		end
	end
	if roster and roster.ScrollBox then
		Kit:HookScrollBoxRows(roster.ScrollBox, MemberRow, IsActive, true)
	end

	-- Add / Settings on red plates (their labels readable on them), then
	-- every common control left: the scroll bars, the template's own inset
	for _, key in ipairs({ "NewButton", "SettingsButton" }) do
		local b = f[key]
		if b then
			b.melloNoInk = true
			Kit:SkinRedButton(b, Replace)
		end
	end
	Kit:SweepControls(f, Replace, skin)
	HookFollowers()

	DressPopup()
end

-- Refresh's pass a frame later, once the window is laid out (made once:
-- Kit:NextFrame runs it once however often it was asked -- audit, 2026-09-24;
-- timed on this window's own /melloperf row, not the Kit's timer -- review)
local RefreshLater = Shared("Refresh a frame later", function()
	local f = Window()
	if active and f and f:IsShown() then
		FitPortrait()
		PlaceTitles(true)
		ListPass()
		RosterPass()
		KeepBoxesUnder()
	end
end, "timer")

-- After every show and every game refresh: what the game re-laid or made
-- since (the portrait's size, the title's plate, the rows, the boxes' level).
local function Refresh()
	local f = Window()
	if not (active and skin and f) then
		return
	end
	GuardFollowers()
	FitPortrait()
	PlaceTitles(true)
	ListPass()
	RosterPass()
	KeepBoxesUnder()
	-- once laid out (a frame after it shows): the portrait, title and rows
	-- again, one pass pending at a time
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
	ShowPopupSkin(true)
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
	for _, info in pairs(rowInfo) do
		if info.stripe then
			info.stripe:Hide()
		end
	end
	ShowPopupSkin(false)
	GuardFollowers()
	-- the title strings back where the game put them, in its font (the
	-- ring's onDisable put the portrait back, the plate's the container's title)
	PlaceTitles(false)
end

-- (user, 2026-09-24: "dress rarely used windows on first open") nothing of
-- the window's look is made while it has never been shown this session: it
-- is dressed on its first show (the OnShow hook, before the first frame is
-- drawn), or at once when it is up already, then kept for the session. The
-- list's and the rows' hooks are made with the skin; the popup's show waits
-- for the kit to be on.
local function Sync()
	local f = Window()
	if M.isEnabled and f and ((skin and skin.built) or Shown(f)) then
		Activate()
	else
		Deactivate()
	end
end

-- (the switch and the addon's load: out of combat, as before; the first
-- show is dressed at once, see Hook)
local function SyncSafe()
	Kit:WhenOutOfCombat(Sync)
end

local function Hook()
	local f = Window()
	if hooked or not f then
		return
	end
	hooked = true
	-- the first show dresses the window there and then, in combat too:
	-- dressing makes frames of ours and moves only the game's portrait and
	-- title strings, and nothing in this window is protected
	Perf.HookScript(f, "OnShow", function()
		if M.isEnabled and not active then
			Sync()
		end
		Refresh()
	end)
	local p = Popup()
	if p then
		Perf.HookScript(p, "OnShow", function()
			if active then
				DressPopup()
				ShowPopupSkin(true)
			end
		end)
	end
end

-- Blizzard_Channels is loaded on demand (the first time the window opens,
-- unless other UI pulls it in sooner): hooked as it loads, or at once when
-- it already is (OnEnable); dressed on the window's first show.
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
-- /channeldump [frames | reps | regions | popup]: with no mode, what the
-- skin found and dressed (every part, found or not, and its state: the
-- portrait against the medallion, the title's place and font, the page
-- picture's rect, the boxes and their levels, the rows) and the window's own
-- regions and children; "popup" the new channel popup's; the other modes
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
	MelloUI:Print("  %-26s %s%s", label, obj and Label(obj) or "-- not found", more or "")
end

local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.0f", v) or "?"
end

local function RectText(obj)
	if not obj then
		return "no rect"
	end
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if ok and l and b and w and h and not Secret(l) and not Secret(b) and not Secret(w) and not Secret(h) then
		return string.format("x=%.0f y=%.0f w=%.0f h=%.0f", l, b, w, h)
	end
	return "no rect"
end

local function LevelText(obj)
	if not (obj and obj.GetFrameLevel) then
		return "-"
	end
	local ok, lv = pcall(obj.GetFrameLevel, obj)
	return ok and Num(lv) or "?"
end

local function FontText(fs)
	local ok, face, size = pcall(fs.GetFont, fs)
	if ok and type(face) == "string" and not Secret(face) then
		return string.format("%s %s", face:match("([^\\/]+)$") or face, Num(size))
	end
	return "?"
end

local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. ((region.kitPiece or region.kitScale) and " (kit)" or "")
		elseif kind == "FontString" then
			art = "text: " .. (TextOf(region) or "?"):sub(1, 40)
		end
		local okA, alpha = pcall(region.GetAlpha, region)
		MelloUI:Print("  region %s %s %s %s alpha %s shown %s", kind, Label(region), okL and tostring(layer) or "?", art,
			(okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?", tostring(Shown(region)))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		MelloUI:Print("  child %s %s level %s shown %s%s", tostring(child:GetObjectType()), Label(child),
			LevelText(child), tostring(Shown(child)), child.melloRep ~= nil and " (dressed)" or "")
	end
end

local function DumpShell(f)
	MelloUI:Print("ChannelFrame: shown %s, %s, level %s, strata %s, kit %s, reps %d, faded art %d", tostring(Shown(f)), RectText(f),
		LevelText(f), tostring(f:GetFrameStrata()), active and "on" or "off", skin and #skin.reps or 0, #fadedArt)
	if not (skin and skin.built) then
		MelloUI:Print("  not dressed yet: the kit dresses the chat channels window the first time it opens (open it once for the kit's side)")
	end
	Found("outer rail (NineSlice)", f.NineSlice, f.NineSlice and (" layout " .. tostring(f.NineSlice.layoutType)) or " (no shell)")
	local bgRep
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.region == f.Bg then
			bgRep = rep
		end
	end
	Found("page stone (Bg)", f.Bg, bgRep and (" -> page picture, inner " .. RectText(bgRep.inner or bgRep.object)) or " (not dressed)")
	local portrait = skin and skin.portrait or Portrait(f)
	if portrait then
		local okS, w, h = pcall(portrait.GetSize, portrait)
		local ring = skin and skin.ring
		local rw
		if ring and ring.tex then
			local okR, v = pcall(ring.tex.GetWidth, ring.tex)
			rw = okR and v or nil
		end
		local medallion = (type(rw) == "number" and not Secret(rw)) and rw * 0.759 or nil
		Found("portrait", portrait, string.format(" art %s, size %s x %s, medallion %s (ring %s), fitted %s, disc %s, filled by the kit %s, shown %s",
			tostring(PortraitArt(portrait) or "none"), okS and Num(w) or "?", okS and Num(h) or "?", Num(medallion), Num(rw),
			tostring(portrait.melloSaved ~= nil), tostring(ring ~= nil and ring.disc ~= nil), tostring(portraitFilled[portrait] ~= nil), tostring(Shown(portrait))))
	else
		Found("portrait", nil)
	end
	Found("ring", skin and skin.ring and skin.ring.object)
	Found("title container", f.TitleContainer)
	local list, own = TitleStrings(f)
	local rep = TitleRep()
	local plate = rep and (rep.strip or rep.object)
	for _, fs in ipairs(Compact(own, unpack(list))) do
		local okC, cx, cy = pcall(fs.GetCenter, fs)
		local okP, px, py = false, nil, nil
		if plate then
			okP, px, py = pcall(plate.GetCenter, plate)
		end
		local off = "?"
		if okC and okP and cx and cy and px and py and not Secret(cx) and not Secret(cy) and not Secret(px) and not Secret(py) then
			off = string.format("%.0f, %.0f", cx - px, cy - py)
		end
		Found("title string", fs, string.format(" text %s, font %s, title face %s, off the plate's centre %s, %s", tostring(TextOf(fs)),
			FontText(fs), tostring(fs.melloFontSaved ~= nil), off, titleFaded[fs] and "faded (duplicate)" or (titleMoved[fs] and "moved onto the plate" or "the container's")))
	end
	Found("title plate", plate, plate and (" " .. RectText(plate)) or nil)
	Found("close button", f.CloseButton)
	MelloUI:Print("  tabs: none on this window; inked strings: none (no parchment in this window)")
end

local function DumpParts(f)
	local list, roster = ChannelList(f), Roster(f)
	Found("channel list", list, list and string.format(" %s, level %s, rows %d", RectText(list), LevelText(list), #ChannelRows(list)) or nil)
	Found("roster", roster, roster and string.format(" %s, level %s", RectText(roster), LevelText(roster)) or nil)
	for _, key in ipairs({ "LeftInset", "RightInset", "Inset" }) do
		local inset = f[key]
		Found(key, inset, inset and string.format(" dressed %s, dim %s, shown %s", tostring(inset.melloRep ~= nil and inset.melloRep ~= false),
			tostring(inset.melloRep and inset.melloRep.skin and inset.melloRep.skin.dimFill ~= nil), tostring(Shown(inset))) or nil)
	end
	for _, box in ipairs(boxes) do
		MelloUI:Print("  box %-22s holder level %s, rows' parent %s level %s", box.label, LevelText(box.rep.object), Label(box.content), LevelText(box.content))
	end
	local n = 0
	for _, row in ipairs(ChannelRows(list)) do
		n = n + 1
		local info = rowInfo[row]
		local text = row.Text and TextOf(row.Text) or "?"
		if info and info.header then
			MelloUI:Print("  row %d HEADER %s: category plate %s, glyph %s (%s)", n, text:sub(1, 30), tostring(info.plate ~= nil),
				info.glyph and tostring(Kit:ArtKey(info.glyph)) or "none", info.glyph and (Shown(info.glyph) and "shown" or "hidden") or "-")
		elseif info then
			MelloUI:Print("  row %d %s: stripe %s, hover plate %s, selected %s, voice button on the cog %s", n, text:sub(1, 30),
				tostring(info.stripe ~= nil and info.stripe:IsShown()), tostring(info.hover ~= nil), tostring(IsSelected(row)),
				tostring(row.Speaker ~= nil and iconButtons[row.Speaker.Button] and true or false))
		else
			MelloUI:Print("  row %d %s: not dressed", n, text:sub(1, 30))
		end
	end
	local members, striped = 0, 0
	if roster and roster.ScrollBox and roster.ScrollBox.ForEachFrame then
		roster.ScrollBox:ForEachFrame(function(row)
			members = members + 1
			local info = rowInfo[row]
			if info and info.stripe and info.stripe:IsShown() then
				striped = striped + 1
			end
		end)
	end
	MelloUI:Print("  member rows laid out %d (striped %d); roster heading %s", members, striped,
		(roster and roster.ChannelName) and tostring(TextOf(roster.ChannelName)) or "-")
	for _, key in ipairs({ "NewButton", "SettingsButton" }) do
		local b = f[key]
		local fs = b and b.GetFontString and b:GetFontString()
		Found(key, b, b and string.format(" red plate %s, text %s", tostring(b.melloRep ~= nil and b.melloRep ~= false), tostring(fs and TextOf(fs))) or nil)
	end
	MelloUI:Print("  dressed so far: channel rows %d, headers %d, member rows %d, voice buttons on the cog %d, edit plates %d",
		stats.rows, stats.headers, stats.members, stats.icons, stats.edits)
end

local function DumpPopup()
	local p = Popup()
	if not p then
		MelloUI:Print("CreateChannelPopup: not on this client (or Blizzard_Channels not loaded yet)")
		return
	end
	MelloUI:Print("CreateChannelPopup: shown %s, %s, level %s, strata %s; dressed %s, game box faded %d", tostring(Shown(p)), RectText(p),
		LevelText(p), tostring(p:GetFrameStrata()), tostring(popupSkin ~= nil), popupSkin and #popupSkin.art or 0)
	Found("header", p.Header, popupSkin and (" plate " .. tostring(popupSkin.header ~= nil)) or nil)
	if popupSkin and popupSkin.title then
		Found("header text", popupSkin.title, string.format(" text %s, font %s, title face %s", tostring(TextOf(popupSkin.title)),
			FontText(popupSkin.title), tostring(popupSkin.title.melloFontSaved ~= nil)))
	end
	for _, key in ipairs({ "Name", "Password", "OKButton", "CancelButton", "CloseButton", "UseVoiceChat" }) do
		local obj = p[key]
		Found(key, obj, obj and (" dressed " .. tostring(done[obj] or (obj.melloRep ~= nil and obj.melloRep ~= false))) or nil)
	end
	DumpOwn(p)
end

SLASH_MELLOCHANNELDUMP1 = "/channeldump"
SlashCmdList.MELLOCHANNELDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if not f then
		local loaded = "?"
		if C_AddOns and C_AddOns.IsAddOnLoaded then
			local ok, v = pcall(C_AddOns.IsAddOnLoaded, ADDON)
			loaded = ok and tostring(v) or "?"
		end
		MelloUI:Print("/channeldump: no ChannelFrame yet (%s loaded: %s); open the chat channels window once (the chat menu's Chat Channels) and try again", ADDON, loaded)
	elseif msg == "" then
		DumpShell(f)
		DumpParts(f)
		MelloUI:Print("ChannelFrame's own regions and children:")
		DumpOwn(f)
	else
		if not (skin and skin.built) then
			MelloUI:Print("/channeldump: the chat channels window is not dressed yet (the kit dresses it the first time it opens)")
		end
		if msg == "popup" then
			DumpPopup()
		else
			-- frames / reps / regions (the visible game textures): the Kit's dump
			Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
		end
	end
	MelloUI:ShowLog("channeldump " .. msg)
end
