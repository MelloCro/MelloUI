--------------------------------------------------------------------------------
-- MelloUI - Clock Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): The clock settings and the stopwatch in the kit.
--
-- Both windows come with the load-on-demand Blizzard_TimeManager (the
-- minimap loads it for its clock): dressed on its ADDON_LOADED, or at once
-- when it is in already. Dressed by the rule book (docs/WINDOW-RULES.md):
-- every kit piece stands in for one of the game's art regions on that
-- region's rectangle, the game's art faded in its place.
--
-- TimeManagerFrame (a ButtonFrameTemplate window: the alarm time dropdowns,
-- the alarm message box, three check boxes, the stopwatch toggle):
--   the window shell     outer double rail with gem corners, the page stone
--                        for the template's rock, the ring on the portrait
--                        corner with the window's own clock icon (the globe
--                        the game draws there, TimeManagerGlobe) at the class
--                        medallion's size on the dark disc (2b), the title
--                        plate on the rail with the window's "Clock" string
--                        ON it in the title face (2c), the close button
--                        (Kit:SkinWindowShell)
--   the settings         the window's inset as the list box L1 with its body:
--                        single rail, stone under the palette's inner panel
--                        (2e); the labels at the interface's full size, the
--                        two headings ("Alarm Time", "Alarm Message") in the
--                        palette's gold, the other labels in its text colour
--   dropdowns            the dropdown plate (D1), by the sweep
--   check boxes          the kit's check box, by the sweep
--   the message box      the edit plate (S1), its search-glass cap dropped
--   the stopwatch toggle the pocket watch icon in every window's Button
--                        Border rim, gold while the stopwatch is shown
--
-- StopwatchFrame (the small stopwatch: the timer, play / pause, reset, the
-- title tab that fades in under the mouse):
--   the timer bar        its two TimerBackground pieces -> the small single
--                        rail (the raid frames' 0.8 weight) with the stone
--                        under the inner panel: the timer reads on dark
--   the title tab        its ChatFrameTab pieces -> the same small box; it
--                        fades in and out with the game's tab
--   close                the kit's close button
--   play / reset         the kit's cog plate (K2) under the game's glyphs;
--                        the play glyph (the spell book's NextPage art) is
--                        the kit's right arrow by that art's rule, the pause
--                        glyph the game swaps in stays the game's
--
-- The minimap clock (TimeManagerClockButton) is the minimap module's: it is
-- never touched here.
--
-- Taint: nothing of the game's is replaced or re-scripted. Post-hooks and
-- HookScript only, our state in weak side tables (the kit's own melloRep
-- marker on the stopwatch toggle is the one field written on a game frame).
-- No time, alarm or stopwatch function is ever called. Switching the module
-- off disables every replacement and puts the labels' fonts and colours,
-- the title and the clock icon back: the windows are the game's again.
--
-- /clockdump [stopwatch | frames | reps | regions]: what the windows are
-- made of on this client and what the skin dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("ClockPanel", {
	title = "Clock Kit",
	desc = "The clock settings and the stopwatch in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local ADDON = "Blizzard_TimeManager"
local SMALL_BOX = "UI-RaidFrame-GroupOutline"   -- the single rail at the raid frames' 0.8 weight with its stone body (G3): the kit's small box
local SMALL_DIM = 0.8                           -- WINDOW-RULES 2e: the inner panel over its stone
local COG = "UI-SquareButton-Up"                -- K2: the cog plate under a small square button's glyph
local ARROW = "UI-SpellbookIcon-NextPage-Up"    -- the play glyph's own art: the kit's right arrow (keyed by hand: file art reads back as ids)

local skin = nil          -- { reps = { every replacement }, followers = {}, ring, title, stopwatch = {} }
local active = false
local hooked = setmetatable({}, { __mode = "k" })      -- [frame] = true once hooked

-- what this module made or looked at, kept OFF the game's frames (weak keys)
local done = setmetatable({}, { __mode = "k" })        -- [frame / region] = true: looked at once
local labels = {}                                      -- { fs, heading }: the labels set at full size
local labelSaved = setmetatable({}, { __mode = "k" })  -- [fs] = { obj, colour }: the game's font and colour
local titleHome = setmetatable({}, { __mode = "k" })   -- [fs] = { parent, points }: the title string while it rides the plate
local rims = {}                                        -- the icon rims { button, icon }
local stats = { labels = 0, edits = 0, rims = 0, cogs = 0 }

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local ok, rep, key = pcall(Kit.Replace, Kit, region, opts)
	if not ok then
		MelloUI:Notice("Clock kit: could not dress %s (%s)", tostring(opts and opts.as), tostring(rep))
		return nil
	end
	if not rep then
		if key then
			MelloUI:Notice("Clock kit: no kit piece mapped for %s", tostring(key))
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

local function Window()
	return _G.TimeManagerFrame
end

local function Stopwatch()
	return _G.StopwatchFrame
end

-- The window's icon: the globe the game draws on the portrait corner (a
-- client that fills the template's own portrait: that one)
local function Portrait(f)
	return _G.TimeManagerGlobe or (f and f.PortraitContainer and f.PortraitContainer.portrait)
end

-- The window's title (2c: whatever the window calls it): this window writes
-- "Clock" into an unnamed string of its own, not into the template's title
-- container; found by its text, else the container's string when the
-- client writes it there
local function TitleString(f)
	local words = _G.TIMEMANAGER_TITLE
	if type(words) == "string" then
		for _, region in ipairs({ f:GetRegions() }) do
			if region:GetObjectType() == "FontString" then
				local ok, text = pcall(region.GetText, region)
				if ok and type(text) == "string" and not Secret(text) and text == words then
					return region
				end
			end
		end
	end
	local tc = f.TitleContainer
	return tc and tc.TitleText or nil
end

local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
	end
end

--------------------------------------------------------------------------------
-- The title ON the plate (WINDOW-RULES 2c). The shell's plate centres the
-- title container's TitleText on it; this window leaves that string empty
-- and writes its "Clock" into a string of its own, which is a region of the
-- WINDOW (under the plate, which rides the rail on a frame above the
-- window). That string is lent to the title container while the kit is on
-- (its parent and points put back on disable), centred where the plate puts
-- the container's own string, in Kit:TitleFont (the Font Style's Titles &
-- headers face): the game's own string on the plate, not a copy.
--------------------------------------------------------------------------------
local function PlaceTitle()
	local f = Window()
	local fs = skin and skin.title
	local tc = f and f.TitleContainer
	local rep = TitleRep()
	if not (active and fs and tc and rep) then
		return
	end
	if rep.object and rep.object:IsShown() and rep.Refit then
		rep:Refit()
	end
	if fs == tc.TitleText then
		-- the container's own string: the plate carries it itself
		if not fs.melloFontSaved then
			Kit:TitleFont(fs, true)
		end
		return
	end
	if not titleHome[fs] then
		local points = {}
		for i = 1, fs:GetNumPoints() do
			points[i] = { fs:GetPoint(i) }
		end
		titleHome[fs] = { parent = fs:GetParent(), points = points }
		pcall(fs.SetParent, fs, tc)
	end
	fs:ClearAllPoints()
	fs:SetPoint("CENTER", tc.TitleText or rep.object, "CENTER")
	Kit:TitleFont(fs, true)
end

local function ReturnTitle()
	local fs = skin and skin.title
	local home = fs and titleHome[fs]
	if not home then
		return
	end
	Kit:TitleFont(fs, false)
	pcall(fs.SetParent, fs, home.parent)
	fs:ClearAllPoints()
	for _, pt in ipairs(home.points) do
		fs:SetPoint(unpack(pt))
	end
	titleHome[fs] = nil
end

--------------------------------------------------------------------------------
-- The portrait (WINDOW-RULES 2b: an empty ring is a bug). The window's clock
-- icon is the globe the game draws on the portrait corner (64 px, the time
-- ticker centred on it): the kit's ring is centred on it, the globe brought
-- to the class medallion's size in it (Kit:FitPortrait, its aspect kept) on
-- the dark disc (Kit:RingDisc: the globe is a round picture with open
-- corners, not a full portrait). The disc is a region of the WINDOW, in
-- BACKGROUND over the page stone and under the globe (an OVERLAY region of
-- the window); the portrait container is a frame far above the window and
-- would put the disc over the globe. Fitted again on every show; put back
-- on disable.
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
	Kit:RingDisc(ring, nil, f, 7)
end

--------------------------------------------------------------------------------
-- The settings on the dark panel (WINDOW-RULES 2e). The window's inset
-- (ButtonFrameTemplate's Inset, at the window's own level: useParentLevel)
-- frames the alarm settings and the two format check boxes: dressed WITH
-- its body (Kit:SkinInset), the list-box stone under the palette's inner
-- panel inside its rail. Its holder is kept AT the window's level: the
-- settings are frames one level up whose labels are their own regions, and
-- a holder tied with them could draw its stone over the labels (the
-- merchant's rule).
--------------------------------------------------------------------------------
local function InsetOf(f)
	return f.Inset or _G.TimeManagerFrameInset
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

-- The labels at the interface's full size (2e: no small font for a column
-- of settings): the two headings in the palette's gold, the rest in its
-- text colour. The game's font object and colour are kept and put back.
local function LabelOn(fs, heading)
	if not fs then
		return
	end
	if not labelSaved[fs] then
		local okF, obj = pcall(fs.GetFontObject, fs)
		local okC, r, g, b, a = pcall(fs.GetTextColor, fs)
		labelSaved[fs] = { obj = okF and obj or nil, colour = (okC and type(r) == "number" and not Secret(r)) and { r, g, b, a or 1 } or nil }
	end
	local font = _G.GameFontHighlight
	if font then
		pcall(fs.SetFontObject, fs, font)
	end
	local P = MelloUI.Palette
	local c = P and (heading and P.selectedTrim or P.text)
	if c then
		pcall(fs.SetTextColor, fs, c[1], c[2], c[3], 1)
	end
end

local function LabelOff(fs)
	local saved = fs and labelSaved[fs]
	if not saved then
		return
	end
	if saved.obj then
		pcall(fs.SetFontObject, fs, saved.obj)
	end
	if saved.colour then
		pcall(fs.SetTextColor, fs, unpack(saved.colour))
	end
end

local function CollectLabels()
	local function Add(fs, heading)
		if fs and not done[fs] and fs.GetObjectType and fs:GetObjectType() == "FontString" then
			done[fs] = true
			labels[#labels + 1] = { fs = fs, heading = heading }
			stats.labels = stats.labels + 1
		end
	end
	Add(_G.TimeManagerAlarmTimeLabel, true)
	Add(_G.TimeManagerAlarmMessageLabel, true)
	Add(_G.TimeManagerStopwatchFrameText, false)
	for _, name in ipairs({ "TimeManagerAlarmEnabledButton", "TimeManagerMilitaryTimeCheck", "TimeManagerLocalTimeCheck" }) do
		local cb = _G[name]
		Add((cb and cb.Text) or _G[name .. "Text"], false)
	end
end

-- A one-line edit box (InputBoxTemplate: Left / Middle / Right art reaching
-- a few px past the box): the edit plate S1 on the art's own span, its LEFT
-- cap dropped -- that cap is the search glass, and this is a message box
-- (the chat's, Edit Mode's and the auction house's rule).
local function SkinEdit(edit)
	if not edit or done[edit] or edit.melloRep ~= nil or edit.searchIcon then
		return
	end
	done[edit] = true
	local left, mid, right = edit.Left, edit.Middle or edit.Mid, edit.Right
	if not (left and mid and right) then
		return
	end
	local rect = CreateFrame("Frame", nil, edit)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", left, "TOPLEFT")
	rect:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT")
	if Replace(mid, { as = "common-search-border-middle", rect = rect, edit = edit, dropCap = "l", alsoFade = { left, right } }) then
		stats.edits = stats.edits + 1
	end
end

--------------------------------------------------------------------------------
-- The stopwatch toggle (TimeManagerStopwatchCheck: a 28 px check button whose
-- NormalTexture IS the pocket watch icon, a square additive highlight, an
-- additive checked glow): every window's Button Border rim hugging the icon
-- (its edge 2 px under the rim's inner edge, on the icon's centre -- the
-- merchant's tools' recipe), the highlight and checked glows faded (the rim
-- carries hover and the checked gold: it reads GetChecked itself). The kit's
-- melloRep marker keeps the sweep from taking it for a check box.
--------------------------------------------------------------------------------
local function FitIconRim(entry)
	local rep = entry.button and entry.button.melloRep
	local rim = rep and rep.object
	local icon = entry.icon
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

-- a new Button Border has a new opening: every rim fitted again
Kit:OnBorderChanged("button", function()
	for _, entry in ipairs(rims) do
		FitIconRim(entry)
	end
end)

local function SkinIconCheck(cb)
	if not cb or done[cb] or cb.melloRep ~= nil then
		return
	end
	done[cb] = true
	local icon = cb.GetNormalTexture and cb:GetNormalTexture()
	if not icon then
		return
	end
	local rep = Replace(icon, { as = Kit:ButtonRimRule(), button = cb, parent = cb, rect = icon, noFade = true,
		alsoFade = List(cb.GetHighlightTexture and cb:GetHighlightTexture(), cb.GetCheckedTexture and cb:GetCheckedTexture(),
			cb.GetPushedTexture and cb:GetPushedTexture()) })
	cb.melloRep = rep or false
	if rep then
		local entry = { button = cb, icon = icon }
		rims[#rims + 1] = entry
		Kit:RegisterButtonRim(cb)
		FitIconRim(entry)
		stats.rims = stats.rims + 1
	end
end

--------------------------------------------------------------------------------
-- The stopwatch (StopwatchFrame, 132 x 44: a 29 px timer bar of two
-- TimerBackground pieces at the bottom, the title tab of three ChatFrameTab
-- pieces on top, which the game fades in under the mouse)
--------------------------------------------------------------------------------

-- the timer bar's two pieces: the named left one and the unnamed right one
-- (the frame's other BACKGROUND texture)
local function TimerPieces(sw)
	local left = _G.StopwatchFrameBackgroundLeft
	local right
	for _, region in ipairs({ sw:GetRegions() }) do
		if region ~= left and region:GetObjectType() == "Texture" and not region.kitPiece then
			local ok, layer = pcall(region.GetDrawLayer, region)
			if ok and layer == "BACKGROUND" then
				right = region
			end
		end
	end
	return left, right
end

-- The small box on `rect`, standing in for `region` (and `extra`), a child
-- of `parent` one level under it: the stopwatch's own regions are only the
-- pieces it replaces, its timer and title are regions of its children
local function SmallBox(region, rect, parent, extra)
	if not (region and rect) then
		return nil
	end
	return Replace(region, { as = SMALL_BOX, parent = parent, rect = rect, dim = SMALL_DIM, level = -1, alsoFade = extra })
end

-- The play / pause glyph: the kit's arrow while the game shows its play
-- glyph (the spell book's NextPage art), the game's own pause glyph while
-- the stopwatch runs (Stopwatch_Play swaps it in with SetNormalTexture and
-- sets the button's `playing`; read, never written)
local function SyncPlay()
	local e = skin and skin.stopwatch and skin.stopwatch.play
	if not (active and e and e.rep) then
		return
	end
	local b = e.button
	local playing = b.playing
	if Secret(playing) or type(playing) ~= "boolean" then
		playing = false
	end
	local normal = b.GetNormalTexture and b:GetNormalTexture()
	if playing then
		if normal then
			Kit:Unfade(normal)
		end
		e.rep.object:Hide()
	else
		if normal then
			Kit:Fade(normal)
		end
		e.rep.object:Show()
	end
end

-- a cog plate under a small button's glyph (the user's K2 for small square
-- buttons; the glyph stays over it), the button's additive highlight faded
-- (the cog has its own hover)
local function SkinCog(b)
	if not b or done[b] then
		return nil
	end
	done[b] = true
	local normal = b.GetNormalTexture and b:GetNormalTexture()
	if not normal then
		return nil
	end
	local rep = Replace(normal, { as = COG, button = b, parent = b, rect = b, noFade = true,
		alsoFade = List(b.GetHighlightTexture and b:GetHighlightTexture()) })
	if rep then
		stats.cogs = stats.cogs + 1
	end
	return rep
end

local function BuildStopwatch()
	local sw = Stopwatch()
	if not sw or skin.stopwatch then
		return
	end
	local s = {}
	skin.stopwatch = s
	-- the timer bar: the small box on the two pieces' span
	local left, right = TimerPieces(sw)
	if left then
		local rect = CreateFrame("Frame", nil, sw)
		rect:EnableMouse(false)
		rect:SetPoint("TOPLEFT", left, "TOPLEFT")
		rect:SetPoint("BOTTOMRIGHT", right or left, "BOTTOMRIGHT")
		s.bar = SmallBox(left, rect, sw, List(right))
	end
	-- the title tab: the same box on the tab's rect, a child of the tab frame
	-- so it fades with it, one level under the tab (its title is a region of
	-- the tab)
	local tab = _G.StopwatchTabFrame
	if tab and _G.StopwatchTabFrameMiddle then
		s.tab = SmallBox(_G.StopwatchTabFrameMiddle, tab, tab, List(_G.StopwatchTabFrameLeft, _G.StopwatchTabFrameRight))
	end
	-- close
	local close = _G.StopwatchCloseButton
	local normal = close and close.GetNormalTexture and close:GetNormalTexture()
	if normal then
		s.close = Replace(normal, { as = "RedButton-Exit", button = close, alsoFade = Kit:OtherTextures(close, normal) })
	end
	-- reset: the cog under the game's glyph
	s.reset = SkinCog(_G.StopwatchResetButton)
	-- play / pause: the cog, and the kit's arrow for the play glyph (on a
	-- square three quarters of the button, centred: the cog's face shows
	-- round it)
	local pp = _G.StopwatchPlayPauseButton
	s.playCog = SkinCog(pp)
	local ppNormal = pp and pp.GetNormalTexture and pp:GetNormalTexture()
	if ppNormal then
		local rect = CreateFrame("Frame", nil, pp)
		rect:EnableMouse(false)
		rect:SetPoint("CENTER", pp, "CENTER")
		local ok, w = pcall(pp.GetWidth, pp)
		local size = (ok and type(w) == "number" and not Secret(w) and w > 0) and w * 0.75 or 18
		rect:SetSize(size, size)
		local rep = Replace(ppNormal, { as = ARROW, button = pp, parent = pp, rect = rect })
		if rep then
			s.play = { rep = rep, button = pp }
			local onEnable = rep.onEnable
			rep.onEnable = function(...)
				if onEnable then
					onEnable(...)
				end
				SyncPlay()
			end
			hooksecurefunc(pp, "SetNormalTexture", SyncPlay)
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

	-- the shell: outer rail, one page stone, the ring round the clock icon,
	-- the title plate on the rail, the close button
	local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = Portrait(f), bg = "UI-Background-Rock" })
	SkinPortrait(f, ring)
	skin.title = TitleString(f)

	-- the settings on the dark panel, the stopwatch toggle's rim (before the
	-- sweep, which would take the list box for a bare inset and the toggle
	-- for a check box), then every control by what it is
	SkinListBox(f)
	SkinIconCheck(_G.TimeManagerStopwatchCheck)
	SkinEdit(_G.TimeManagerAlarmMessageEditBox)
	Kit:SweepControls(f, Replace, skin)
	CollectLabels()

	BuildStopwatch()
end

-- After every show: what the game laid out since (the portrait's size, the
-- title's plate, the list box's level, the rims)
local function Refresh()
	local f = Window()
	if not (active and skin and f) then
		return
	end
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	KeepInsetUnder(f)
	FitPortrait()
	PlaceTitle()
	for _, entry in ipairs(rims) do
		FitIconRim(entry)
	end
	if skin.laterPending then
		return
	end
	skin.laterPending = true
	C_Timer.After(0, function()
		skin.laterPending = nil
		if active and f:IsShown() then
			FitPortrait()
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
	for _, entry in ipairs(labels) do
		LabelOn(entry.fs, entry.heading)
	end
	SyncPlay()
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
	for _, entry in ipairs(labels) do
		LabelOff(entry.fs)
	end
	-- the ring's onDisable put the icon back, the title plate its own
	-- string; the lent title goes home
	ReturnTitle()
end

local function Sync()
	if M.isEnabled and Window() then
		Activate()
	else
		Deactivate()
	end
end

-- (geometry of the windows' children changes here: out of combat only)
local function SyncSafe()
	if Kit.WhenOutOfCombat then
		Kit:WhenOutOfCombat(Sync)
	else
		Sync()
	end
end

local function Hook()
	local f = Window()
	if f and not hooked[f] then
		hooked[f] = true
		f:HookScript("OnShow", function()
			if M.isEnabled and not active then
				SyncSafe()
			end
			Refresh()
		end)
	end
	local sw = Stopwatch()
	if sw and not hooked[sw] then
		hooked[sw] = true
		sw:HookScript("OnShow", SyncPlay)
	end
end

local function IsLoaded()
	local fn = C_AddOns and C_AddOns.IsAddOnLoaded
	if type(fn) ~= "function" then
		return Window() ~= nil
	end
	local ok, loaded = pcall(fn, ADDON)
	return ok and loaded and true or false
end

-- The windows come with their load-on-demand addon: dressed when it loads
local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name ~= ADDON then
		return
	end
	if Window() then
		watcher:UnregisterEvent("ADDON_LOADED")
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
		watcher:RegisterEvent("ADDON_LOADED")
	end
end

function M:OnDisable()
	SyncSafe()
end

--------------------------------------------------------------------------------
-- /clockdump [stopwatch | frames | reps | regions]: with no mode, what the
-- skin found and dressed on the clock settings (every part, found or not,
-- the icon against the medallion, the title's place and font, the labels)
-- and the window's own regions and children; "stopwatch" the stopwatch's
-- parts; the other modes are Kit:DumpWindow's on both windows. Opens the
-- copy window.
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

local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.0f", v) or "?"
end

local function RectText(obj)
	if not obj then
		return "(none)"
	end
	local ok, l, b, w, h = pcall(function() return obj:GetRect() end)
	if ok and type(l) == "number" and not Secret(l) and not Secret(w) then
		return string.format("x=%.0f y=%.0f w=%.0f h=%.0f", l, b, w, h)
	end
	return "(no rect)"
end

local function FontText(fs)
	local okF, face, size = pcall(fs.GetFont, fs)
	if not okF or Secret(face) then
		return "?"
	end
	return string.format("%s %s", tostring(face):match("([^\\/]+)$") or tostring(face), Num(size))
end

local function Width(tex)
	if not tex then
		return nil
	end
	local ok, w = pcall(tex.GetWidth, tex)
	if ok and type(w) == "number" and not Secret(w) then
		return w
	end
	return nil
end

local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "") .. (Kit.faded[region] and " faded" or "")
		elseif kind == "FontString" then
			local okT, text = pcall(region.GetText, region)
			art = "text: " .. ((okT and type(text) == "string" and not Secret(text)) and text:sub(1, 40) or "?") .. ", font " .. FontText(region)
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

local function DumpClock(f)
	local okLv, lv = pcall(f.GetFrameLevel, f)
	MelloUI:Print("TimeManagerFrame: shown %s, level %s, %s, kit %s, reps %d", Shown(f), okLv and Num(lv) or "?",
		RectText(f), active and "on" or "off", skin and #skin.reps or 0)
	Found("outer rail (NineSlice)", f.NineSlice, f.NineSlice and (" layout " .. tostring(f.NineSlice.layoutType)) or " (no NineSlice: no rail)")
	Found("page stone (Bg)", f.Bg, f.Bg and (" " .. RectText(f.Bg) .. (Kit.faded[f.Bg] and ", faded under the stone" or "")) or nil)
	-- the icon against the medallion: the ring's size, the medallion's
	-- (0.759 x the ring) and the icon's
	local portrait = Portrait(f)
	local ring = skin and skin.ring
	local ringW = ring and Width(ring.tex)
	if portrait then
		local okS, w, h = pcall(portrait.GetSize, portrait)
		Found("clock icon (portrait)", portrait, string.format(" size %s x %s, medallion %s, fitted %s, shown %s",
			okS and Num(w) or "?", okS and Num(h) or "?", ringW and Num(ringW * 0.759) or "?",
			tostring(portrait.melloSaved ~= nil), Shown(portrait)))
	else
		Found("clock icon (portrait)", nil)
	end
	Found("ring", ring and ring.object, ring and string.format(" %s px, disc %s", ringW and Num(ringW) or "?", tostring(ring.disc ~= nil)) or nil)
	Found("time ticker", _G.TimeManagerFrameTicker)
	local title = skin and skin.title or TitleString(f)
	if title then
		local okT, text = pcall(title.GetText, title)
		local rep = TitleRep()
		Found("title text", title, string.format(" text %s, parent %s, font %s, title face %s, lent to the plate %s, %s; plate %s %s",
			(okT and type(text) == "string" and not Secret(text)) and text or "?", Label(title:GetParent()), FontText(title),
			tostring(title.melloFontSaved ~= nil), tostring(titleHome[title] ~= nil), RectText(title),
			tostring(rep ~= nil), rep and rep.object and RectText(rep.object) or ""))
	else
		Found("title text", nil)
	end
	local inset = InsetOf(f)
	Found("settings (Inset)", inset, inset and string.format(" dressed %s, dim %s, %s", Dressed(inset),
		tostring(inset.melloRep and inset.melloRep.skin and inset.melloRep.skin.dimFill ~= nil), RectText(inset)) or nil)
	local atf = f.AlarmTimeFrame or _G.TimeManagerAlarmTimeFrame
	for _, key in ipairs({ "HourDropdown", "MinuteDropdown", "AMPMDropdown" }) do
		local dd = atf and atf[key]
		Found("dropdown " .. key, dd, dd and string.format(" dressed %s, shown %s", Dressed(dd), Shown(dd)) or nil)
	end
	local edit = _G.TimeManagerAlarmMessageEditBox
	Found("message box", edit, edit and (" plate " .. tostring(done[edit] == true)) or nil)
	for _, name in ipairs({ "TimeManagerAlarmEnabledButton", "TimeManagerMilitaryTimeCheck", "TimeManagerLocalTimeCheck" }) do
		local cb = _G[name]
		Found("check box", cb, cb and (" dressed " .. Dressed(cb)) or nil)
	end
	local sc = _G.TimeManagerStopwatchCheck
	local okC, checked = false, nil
	if sc then
		okC, checked = pcall(sc.GetChecked, sc)
	end
	Found("stopwatch toggle", sc, sc and string.format(" rim %s, checked %s", Dressed(sc),
		(okC and not Secret(checked)) and tostring(checked) or "?") or nil)
	for _, entry in ipairs(labels) do
		local okT, text = pcall(entry.fs.GetText, entry.fs)
		MelloUI:Print("  label %-18s %s: font %s, %s", (okT and type(text) == "string" and not Secret(text)) and text:sub(1, 18) or "?",
			entry.heading and "heading (gold)" or "label (text colour)", FontText(entry.fs), labelSaved[entry.fs] and "set" or "not set")
	end
	Found("close button", f.CloseButton)
	Found("minimap clock", _G.TimeManagerClockButton, " (the minimap module's: untouched here)")
	MelloUI:Print("  tabs: none on this window; page picture %s; inked strings: none (no parchment on this window)", RectText(f.Bg))
	MelloUI:Print("  labels %d, edit plates %d, icon rims %d, cogs %d", stats.labels, stats.edits, stats.rims, stats.cogs)
end

local function DumpStopwatch()
	local sw = Stopwatch()
	if not sw then
		MelloUI:Print("StopwatchFrame: not on this client")
		return
	end
	local s = skin and skin.stopwatch
	local okLv, lv = pcall(sw.GetFrameLevel, sw)
	MelloUI:Print("StopwatchFrame: shown %s, level %s, strata %s, %s, kit %s", Shown(sw), okLv and Num(lv) or "?",
		tostring(sw:GetFrameStrata()), RectText(sw), active and "on" or "off")
	local left, right = TimerPieces(sw)
	Found("timer bar (left piece)", left, left and (" " .. RectText(left) .. (Kit.faded[left] and ", faded" or "")) or nil)
	Found("timer bar (right piece)", right, right and (" " .. RectText(right) .. (Kit.faded[right] and ", faded" or "")) or nil)
	Found("small box (bar)", s and s.bar and s.bar.object, s and s.bar and (" " .. RectText(s.bar.rect)) or nil)
	local tab = _G.StopwatchTabFrame
	local okA, alpha = false, nil
	if tab then
		okA, alpha = pcall(tab.GetAlpha, tab)
	end
	Found("title tab", tab, tab and (" alpha " .. ((okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?")) or nil)
	Found("small box (tab)", s and s.tab and s.tab.object, s and s.tab and (" " .. RectText(s.tab.rect)) or nil)
	Found("title", _G.StopwatchTitle, _G.StopwatchTitle and (" font " .. FontText(_G.StopwatchTitle)) or nil)
	Found("timer text", _G.StopwatchTickerSecond, _G.StopwatchTickerSecond and (" font " .. FontText(_G.StopwatchTickerSecond)) or nil)
	Found("close", _G.StopwatchCloseButton, " dressed " .. tostring(s and s.close ~= nil))
	Found("reset", _G.StopwatchResetButton, " cog " .. tostring(s and s.reset ~= nil))
	local pp = _G.StopwatchPlayPauseButton
	local playing = pp and pp.playing
	Found("play / pause", pp, string.format(" cog %s, kit arrow %s (shown %s), playing %s", tostring(s and s.playCog ~= nil),
		tostring(s and s.play ~= nil), (s and s.play) and Shown(s.play.rep.object) or "-",
		(not Secret(playing)) and tostring(playing) or "?"))
end

SLASH_MELLOCLOCKDUMP1 = "/clockdump"
SlashCmdList.MELLOCLOCKDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if not f then
		local lod = "?"
		if C_AddOns and C_AddOns.IsAddOnLoadOnDemand then
			local ok, v = pcall(C_AddOns.IsAddOnLoadOnDemand, ADDON)
			lod = ok and tostring(v) or "?"
		end
		MelloUI:Print("/clockdump: no TimeManagerFrame (%s loaded %s, load on demand %s): open the clock from the minimap once and try again; if it stays missing, it is not on this client",
			ADDON, tostring(IsLoaded()), lod)
	elseif msg == "" then
		DumpClock(f)
		MelloUI:Print("TimeManagerFrame's own regions and children:")
		DumpOwn(f)
	elseif msg == "stopwatch" then
		DumpStopwatch()
		if Stopwatch() then
			MelloUI:Print("StopwatchFrame's own regions and children:")
			DumpOwn(Stopwatch())
		end
	else
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
		-- (the reps list is the one skin's: both windows' pieces are in it)
		if Stopwatch() and msg ~= "reps" then
			MelloUI:Print("-- StopwatchFrame --")
			Kit:DumpWindow(Stopwatch(), skin, msg ~= "regions" and msg or nil)
		end
	end
	MelloUI:ShowLog("clockdump " .. msg)
end
