--------------------------------------------------------------------------------
-- MelloUI - Calendar Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): The calendar and its event windows in the kit.
--
-- The calendar is the load-on-demand Blizzard_Calendar: hooked on its
-- ADDON_LOADED, or at once when it is in already, and dressed on its first
-- show (user, 2026-09-24: "dress rarely used windows on first open"); a
-- client without it gets nothing done and /calendardump says so.
-- CalendarFrame is no template window: twelve loose file textures make its
-- border and header band, the
-- 7 x 6 grid of CalendarDayButton1..42 (91 px squares, each painted with a
-- piece of the CalendarBackground file) lies under a row of weekday
-- headers, the month and year stand in their own small plates between the
-- month arrows. Dressed by the rule book (docs/WINDOW-RULES.md) as a window
-- WITHOUT a portrait (the game draws none: no ring is made, so none is
-- empty):
--
--   the border           the outer double rail with gem corners, grown
--                        outward, in place of the twelve border textures
--   the page             the page stone, one picture inside the outer rail
--                        (a region of the window, under everything of it)
--   the title            the title plate riding the top rail with the month
--                        AND the year on it, the game's own two strings,
--                        side by side in the title face (2c); their two
--                        small plates faded
--   month arrows         buttons/arrow_left / _right at the button's height
--                        (the spell book's PrevPage / NextPage art's rule),
--                        dimmed while the game disables them
--   weekday headers      the header plate (GC1, as the raid info's column
--                        headers) on each column's band, the name over it
--   the days             each day's CalendarBackground piece -> the single-
--                        rail card with stone under the palette's inner
--                        panel (2e: the event text reads on dark), as the
--                        day button's own regions, on the button grown by
--                        the rail's centre inset so neighbours share ONE
--                        rail (the grid's lines); the event pictures, the
--                        other month's shadows and the hover / selection
--                        glows stay the game's
--   today                the game's golden today frame (CalendarTodayFrame,
--                        moved by the game onto today's button) -> the same
--                        single rail lit gold on today's card, on the today
--                        frame (above every day, so its gold is never under
--                        a neighbour's shared rail); the pulsing glow faded
--   filter, close        the filter plate (the sweep), the kit's close
--   the event windows    (view / create event, holiday, raid reset, mass
--                        invite, event and texture pickers: DialogBorder
--                        popups with a DialogHeader) -> kit popups, as the
--                        game's dialogs: the single rail with its stone
--                        under the inner panel, as the popup's own regions;
--                        the header -> the title plate with the header's
--                        text on it in the title face; the invite lists and
--                        the description boxes (tooltip backdrops) -> the
--                        list box L1 (single rail, stone, inner panel); the
--                        dividers -> the divider strip; text buttons on the
--                        red plates, edit boxes on the edit plate, dropdowns
--                        on the dropdown plate, check boxes and scroll bars
--                        the kit's; the class counts' icons in the Button
--                        Border rim
--
-- Taint: nothing of the game's is replaced or re-scripted. Post-hooks
-- (CalendarFrame_Update, the popups' OnShow, the arrows' Enable / Disable)
-- and HookScript only, our state in weak side tables (the kit's melloRep
-- markers on the controls it dresses are the only fields written on game
-- frames). No calendar function is called: no event is opened, created,
-- answered or invited to. Nothing is moved but the title strings, which are
-- lent to the plate and put back. Switching the module off disables every
-- replacement and puts the strings' fonts, layers, parents and points back:
-- the calendar is the game's again.
--
-- /calendardump [days | popups | frames | reps | regions]: what the calendar
-- is made of on this client and what the skin dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("CalendarPanel")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("CalendarPanel", {
	title = "Calendar Kit",
	desc = "The calendar and its event windows in the kit.",
	window = { label = "Calendar", desc = "The calendar and its event windows in the kit.", tab = "Windows",
		addon = "Blizzard_Calendar", firstOpen = true },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local ADDON = "Blizzard_Calendar"
local DAYS = 42                                   -- CALENDAR_MAX_DAYS_PER_MONTH: 6 weeks of 7
local TITLE_H = 20                                -- the title plate is fitted to a window's 20 px title bar (1.5 x by its rule)
local POPUP_TITLE_H = 20                          -- the popups' header plates the same
local DAY_RULE = "CalendarBackground"             -- the day card (a rule of its own: owner regions, rails over the event picture)
local TODAY_RULE = "uiframe-activetab-left"       -- the single rail lit gold (the open tab's, a selected row's)
local HEADER_RULE = "ColumnDisplayButton"         -- GC1: the header plate on a column's band
local POPUP_TITLE_RULE = "ui-questtracker-primary-objective-header"   -- the title plate (tabs/top, title look) as regions of its header
local DIVIDER_RULE = "UI-FriendsFrame-OnlineDivider"                   -- the divider strip (window/divider)
local LIST_RULE = "common-insideframe"            -- L1: single rail, stone under the inner panel
local STONE_RULE = "UI-Background-Rock"           -- the page stone
local POPUPS = {
	"CalendarViewHolidayFrame", "CalendarViewRaidFrame", "CalendarViewEventFrame", "CalendarCreateEventFrame",
	"CalendarMassInviteFrame", "CalendarEventPickerFrame", "CalendarTexturePickerFrame",
}
-- the boxes in the popups that hold text (tooltip backdrops): the list box
local LIST_BOXES = { "CalendarViewEventInviteList", "CalendarCreateEventInviteList", "CalendarViewEventDescriptionContainer", "CalendarCreateEventDescriptionContainer" }
local DIVIDERS = { "CalendarViewEventDivider", "CalendarCreateEventDivider" }
-- the popups' X buttons (CalendarCloseButtonTemplate: UIPanelCloseButton)
local CLOSERS = { "CalendarViewHolidayCloseButton", "CalendarViewRaidCloseButton", "CalendarViewEventCloseButton", "CalendarCreateEventCloseButton", "CalendarMassInviteCloseButton" }
local BORDER_PIECES = {
	"TopLeftTexture", "TopMiddleTexture", "TopRightTexture", "LeftTopTexture", "LeftMiddleTexture", "LeftBottomTexture",
	"RightTopTexture", "RightMiddleTexture", "RightBottomTexture", "BottomLeftTexture", "BottomMiddleTexture", "BottomRightTexture",
}
local ARROWS = { { "CalendarPrevMonthButton", "UI-SpellbookIcon-PrevPage-Up" }, { "CalendarNextMonthButton", "UI-SpellbookIcon-NextPage-Up" } }

local skin = nil          -- { reps = {}, followers = {}, outer, stone, plate, band, today, ... }
local active = false
local hooked = setmetatable({}, { __mode = "k" })      -- [frame] = true once hooked

-- what this module made or looked at, kept OFF the game's frames (weak keys)
local done = setmetatable({}, { __mode = "k" })        -- [frame / region] = true: looked at once
local fadedArt = {}                                    -- game art faded with no piece of its own on its rect
local dayCards = {}                                    -- { button, rep, rect }
local weekdays = {}                                    -- { bg, name, rep }
local arrowReps = {}                                   -- { rep, button }
local popups = {}                                      -- { frame, nine, dim, plate, header }
local listBoxes = {}                                   -- { frame, rep }
local rims = {}                                        -- the class icons' rims { melloRep, icon, button }
local raised = setmetatable({}, { __mode = "k" })      -- [fs] = { layer, sublevel }: a string lifted over our plate while dressed
local lent = setmetatable({}, { __mode = "k" })        -- [fs] = { parent, points, font }: a title string riding the plate
local stats = { days = 0, weekdays = 0, popups = 0, lists = 0, edits = 0, buttons = 0, dividers = 0, rims = 0 }

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local ok, rep, key = pcall(Kit.Replace, Kit, region, opts)
	if not ok then
		MelloUI:Notice("Calendar kit: could not dress %s (%s)", tostring(opts and opts.as), tostring(rep))
		return nil
	end
	if not rep then
		if key then
			MelloUI:Notice("Calendar kit: no kit piece mapped for %s", tostring(key))
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

-- An invisible region of OUR frame to hand to Kit:Replace where the game has
-- no one piece to stand in for (the rail over twelve loose border textures,
-- the plate over two small title plates, the page under the grid)
local function Anchor(host, layer, sublevel)
	local tex = host:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
	tex:SetAllPoints(host)
	tex:SetColorTexture(0, 0, 0, 0)
	tex.kitPiece = true
	return tex
end

-- A string lifted over our plate (its own layer back on disable)
local function Raise(fs, layer, sublevel)
	if not fs or not fs.GetDrawLayer then
		return
	end
	if not raised[fs] then
		local ok, l, s = pcall(fs.GetDrawLayer, fs)
		raised[fs] = { layer = ok and l or nil, sub = ok and s or 0, to = layer, toSub = sublevel or 0 }
	end
	if active then
		pcall(fs.SetDrawLayer, fs, layer, sublevel or 0)
	end
end

local function Lower(fs)
	local r = fs and raised[fs]
	if r and r.layer then
		pcall(fs.SetDrawLayer, fs, r.layer, r.sub or 0)
	end
end

local function Window()
	return _G.CalendarFrame
end

-- the rail's centre inset on each side (UI px at the single rail's weight):
-- a card grown by it has its rails' centre lines on the button's edges
local function RailInsets()
	local pre = Kit.framePrefix
	return Kit:RailInset(pre .. "_l", "l"), Kit:RailInset(pre .. "_r", "r"), Kit:RailInset(pre .. "_t", "t"), Kit:RailInset(pre .. "_b", "b")
end

-- `rect` laid on `button`'s rect grown by the rail's centre inset
local function GrowOver(rect, button)
	local l, r, t, b = RailInsets()
	rect:ClearAllPoints()
	rect:SetPoint("TOPLEFT", button, "TOPLEFT", -l, t)
	rect:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", r, -b)
end

--------------------------------------------------------------------------------
-- The shell: the outer rail, the page, the title plate, the close button
--------------------------------------------------------------------------------

-- The window's border: its twelve named file textures (BORDER), else every
-- BORDER texture of the window (a client that names them otherwise)
local function BorderArt(cf)
	local list, seen = {}, {}
	for _, key in ipairs(BORDER_PIECES) do
		local t = _G["CalendarFrame" .. key]
		if t and not seen[t] then
			seen[t] = true
			list[#list + 1] = t
		end
	end
	if #list == 0 then
		for _, region in ipairs({ cf:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not region.kitPiece then
				local ok, layer = pcall(region.GetDrawLayer, region)
				if ok and layer == "BORDER" then
					list[#list + 1] = region
				end
			end
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- The title ON the plate (WINDOW-RULES 2c: the month and the year, the
-- window's own two strings). They are regions of the WINDOW, under the plate
-- (the plate rides the rail on a band three levels up): both are lent to the
-- band while the kit is on (parents and points put back on disable). The
-- plate's rule centres the band's TitleText (the month) on it in the title
-- face; the year follows it at the month's size in the same face (the year's
-- small font is too small for the display face) and the pair is centred
-- together.
--------------------------------------------------------------------------------
local YEAR_GAP = 6

local function Lend(fs, band)
	if not (fs and band) or lent[fs] then
		return
	end
	local points = {}
	for i = 1, fs:GetNumPoints() do
		points[i] = { fs:GetPoint(i) }
	end
	local okF, obj = pcall(fs.GetFontObject, fs)
	local okC, r, g, b, a = pcall(fs.GetTextColor, fs)
	lent[fs] = { parent = fs:GetParent(), points = points, font = okF and obj or nil,
		colour = (okC and type(r) == "number" and not Secret(r)) and { r, g, b, a or 1 } or nil }
	pcall(fs.SetParent, fs, band)
end

local function Return(fs, restorePoints)
	local home = fs and lent[fs]
	if not home then
		return
	end
	pcall(fs.SetParent, fs, home.parent)
	if restorePoints then
		fs:ClearAllPoints()
		for _, pt in ipairs(home.points) do
			fs:SetPoint(unpack(pt))
		end
	end
	lent[fs] = nil
end

local function PlaceYear()
	local month, year = _G.CalendarMonthName, _G.CalendarYearName
	local plate = skin and skin.plate
	if not (active and month and year and plate and plate.object and plate.object:IsShown()) then
		return
	end
	if not year.melloFontSaved then
		-- the month's size first (saved to put back), then the title face
		local home = lent[year]
		local okM, obj = pcall(month.GetFontObject, month)
		if home and okM and obj then
			pcall(year.SetFontObject, year, obj)
		end
		Kit:TitleFont(year, true)
	end
	-- the pair centred: the month moved left by half the year's width
	local okW, yw = pcall(year.GetStringWidth, year)
	local okP, point, rel, relPoint, x, y = pcall(month.GetPoint, month, 1)
	if okW and okP and point and type(yw) == "number" and not Secret(yw) and type(x) == "number" and not Secret(x) then
		local base = skin.monthX or x
		skin.monthX = base
		month:ClearAllPoints()
		month:SetPoint(point, rel, relPoint, base - (yw + YEAR_GAP) / 2, y)
	end
	year:ClearAllPoints()
	year:SetPoint("LEFT", month, "RIGHT", YEAR_GAP, 0)
end

local function ReturnYear()
	local year = _G.CalendarYearName
	if not year then
		return
	end
	Kit:TitleFont(year, false)
	local home = lent[year]
	if home then
		if home.font then
			pcall(year.SetFontObject, year, home.font)
		end
		if home.colour then
			pcall(year.SetTextColor, year, unpack(home.colour))
		end
	end
	Return(year, true)
end

local function SkinTitle(cf)
	local month = _G.CalendarMonthName
	if not month then
		return
	end
	-- the band over the window's top edge, three levels over the window: the
	-- plate (one under the band) above the rail (the window's level), the
	-- strings above the plate (TaxiPanel's recipe for a window with no title
	-- container)
	local band = CreateFrame("Frame", nil, cf)
	band:SetPoint("TOPLEFT", cf, "TOPLEFT", 0, 0)
	band:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 0, 0)
	band:SetHeight(TITLE_H)
	band:EnableMouse(false)
	band:SetFrameLevel(cf:GetFrameLevel() + 3)
	band.TitleText = month   -- the TitleBar rule centres the band's TitleText on the plate in the title face, and puts it back on disable
	skin.band = band
	local plate = Replace(Anchor(band), { as = "TitleBar", parent = band, rect = band, fitHeight = TITLE_H, level = -1, noFade = true,
		alsoFade = List(_G.CalendarMonthBackground, _G.CalendarYearBackground) })
	if not plate then
		return
	end
	skin.plate = plate
	-- the year after the rule has placed the month, whenever it does
	local centre, refit, undo = plate.onEnable, plate.Refit, plate.onDisable
	plate.onEnable = function(self)
		skin.monthX = nil
		if centre then
			centre(self)
		end
		PlaceYear()
	end
	plate.Refit = function(self)
		skin.monthX = nil
		refit(self)
		PlaceYear()
	end
	plate.onDisable = function(self)
		if undo then
			undo(self)
		end
		skin.monthX = nil
		ReturnYear()
	end
end

-- the title strings on the band (or home) with the kit
local function LendTitle(on)
	local band = skin and skin.band
	for _, fs in ipairs(List(_G.CalendarMonthName, _G.CalendarYearName)) do
		if on and band then
			Lend(fs, band)
		elseif not on then
			-- the month's points are the plate rule's to put back; the year's
			-- went back with ReturnYear
			Return(fs, false)
		end
	end
end

--------------------------------------------------------------------------------
-- The month arrows (CalendarPrevMonthButton / NextMonthButton: the spell
-- book's PrevPage / NextPage file art): the kit's arrows at the button's
-- height by that art's rule, the pushed, disabled and highlight looks faded.
-- The arrow pieces have no disabled look: a disabled arrow (the first or the
-- last month the calendar allows, a modal dialog up) is shown at a lower
-- alpha, read again after the game's Enable / Disable.
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
			end
		end
	end
end

-- The filter (WowStyle1FilterDropdownTemplate: Background, Text): the
-- dropdown plate (D1), its painted cap on the right, as the merchant's
-- filter -- a strip of the button's own regions over its Background, so
-- nothing of ours ties with the window's level (the sweep's filter card
-- would sit a level under the button, at the window's own level). The
-- sweep leaves a dressed one alone.
local function SkinFilter(dd)
	if not (dd and dd.Background) or done[dd] or dd.melloRep ~= nil then
		return
	end
	done[dd] = true
	dd.melloRep = Replace(dd.Background, { as = "common-dropdown-textholder", rect = dd, button = dd, alsoFade = List(dd.Arrow) }) or false
end

-- A close button (UIPanelCloseButton) on the kit's
local function SkinClose(b)
	local normal = b and b.GetNormalTexture and b:GetNormalTexture()
	if not normal or done[b] then
		return
	end
	done[b] = true
	Replace(normal, { as = "RedButton-Exit", button = b, alsoFade = Kit:OtherTextures(b, normal) })
end

--------------------------------------------------------------------------------
-- The weekday headers (CalendarWeekday1..7Background: 91 x 28 pieces of the
-- CalendarBackground file, BACKGROUND regions of the window, the day's name
-- centred on each): the header plate (GC1) as regions of the window one
-- sublevel over the piece's; the names, BACKGROUND strings too, are lifted to
-- ARTWORK over their plates while dressed.
--------------------------------------------------------------------------------
local function SkinWeekdays()
	for i = 1, 7 do
		local bg, name = _G["CalendarWeekday" .. i .. "Background"], _G["CalendarWeekday" .. i .. "Name"]
		if bg and not done[bg] then
			done[bg] = true
			local rep = Replace(bg, { as = HEADER_RULE })
			weekdays[#weekdays + 1] = { bg = bg, name = name, rep = rep }
			if rep then
				stats.weekdays = stats.weekdays + 1
				Raise(name, "ARTWORK", 0)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The days (WINDOW-RULES 2e: "too much small text over a plain brown border
-- is just an eye strain"): each day's NormalTexture (its piece of the
-- CalendarBackground file, BACKGROUND) -> the day card (the CalendarBackground
-- rule): the single rail with stone under the palette's inner panel, as
-- REGIONS of the day button -- the stone and panel under the event picture
-- (BORDER 0), the rails over it, the event text and date (child frames and
-- higher layers) over all -- on the button's rect grown by the rail's centre
-- inset (a helper frame of ours on the button), so a day's rails lie on its
-- edges and neighbouring days' rails coincide: one rail between two days,
-- as the game's grid lines.
--------------------------------------------------------------------------------
local function SkinDay(button)
	if not button or done[button] then
		return
	end
	done[button] = true
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if not normal then
		return
	end
	local rect = CreateFrame("Frame", nil, button)
	rect:EnableMouse(false)
	GrowOver(rect, button)
	local rep = Replace(normal, { as = DAY_RULE, parent = button, rect = rect })
	if rep then
		dayCards[#dayCards + 1] = { button = button, rep = rep, rect = rect }
		stats.days = stats.days + 1
	end
end

--------------------------------------------------------------------------------
-- Today (the game's CalendarTodayFrame: a 145 x 140 golden frame the game
-- re-parents onto today's button, a level over the day's own frames, with a
-- pulsing additive glow): the single rail lit gold (the kit's selected look)
-- on today's card rect, edges only, a region-holder on the today frame -- so
-- it moves with it, and it lies over every day's shared rails. The golden
-- frame and its glow are faded (the game pulses the glow through SetAlpha,
-- which the kit's fade answers).
--------------------------------------------------------------------------------
local function PlaceToday()
	local tf = _G.CalendarTodayFrame
	local t = skin and skin.today
	if not (tf and t) then
		return
	end
	local ok, day = pcall(tf.GetParent, tf)
	if ok and day and day ~= Window() and day.GetNormalTexture then
		GrowOver(t.rect, day)
		t.day = day
	end
end

local function SkinToday()
	local tf, tex = _G.CalendarTodayFrame, _G.CalendarTodayTexture
	if not (tf and tex) or done[tf] then
		return
	end
	done[tf] = true
	local rect = CreateFrame("Frame", nil, tf)
	rect:EnableMouse(false)
	rect:SetAllPoints(tf)
	local rep = Replace(tex, { as = TODAY_RULE, parent = tf, rect = rect, body = false, level = 0,
		alsoFade = List(_G.CalendarTodayTextureGlow) })
	if rep then
		skin.today = { rep = rep, rect = rect }
		PlaceToday()
	end
end

--------------------------------------------------------------------------------
-- The event windows: kit popups (the game's dialogs' dress)
--------------------------------------------------------------------------------

-- A one-line edit box (InputBoxTemplate: Left / Middle / Right art reaching
-- a few px past the box): the edit plate S1 on the art's own span, its LEFT
-- cap dropped -- that cap is the search glass (the chat's, Edit Mode's and
-- the auction house's rule).
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

-- A text button (UIPanelButtonTemplate) on the red plate, the frame the
-- game draws round some of them (<name>Border: UI-Button-Borders) faded
local function SkinTextButton(b)
	if not b or done[b] then
		return
	end
	done[b] = true
	local name = NameOf(b)
	if name then
		FadeArt(_G[name .. "Border"])
	end
	if Kit:SkinRedButton(b, Replace) then
		stats.buttons = stats.buttons + 1
	end
end

-- The controls under a popup the sweep does not know (or cannot know yet:
-- a button whose text the game writes on first show), found by what they are
local function WalkControls(root, depth)
	depth = depth or 0
	if not root or depth > 6 then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		local kind = child:GetObjectType()
		if kind == "EditBox" and child.Left and child.Middle and child.Right then
			SkinEdit(child)
		elseif kind == "Button" and child.Left and child.Middle and child.Right and not child.Icon then
			SkinTextButton(child)
		end
		WalkControls(child, depth + 1)
	end
end

-- The divider strip's own thickness (its painted box), as the other windows' lines
local function DividerThickness()
	local p = Kit:Piece("window/divider_mid")
	if p and p.box then
		return (p.box[4] - p.box[2]) * Kit.scale
	end
	return p and p.h * Kit.scale or 8
end

-- A text box (a tooltip backdrop: the invite lists, the description boxes,
-- a black 0.9 fill in a thin tooltip border, its rows or text children one
-- level up) -> the list box L1: the single rail with its stone under the
-- inner panel on the box's rect, a holder at the box's own level (its only
-- regions are the backdrop's, faded; its rows are above), the backdrop
-- (its NineSlice) faded
local function SkinListBox(box)
	if not box or done[box] then
		return
	end
	done[box] = true
	local rep = Replace(box, { as = LIST_RULE, parent = box, rect = box, level = 0, body = true, noFade = true,
		alsoFade = List(box.NineSlice, box.Center) })
	if rep then
		listBoxes[#listBoxes + 1] = { frame = box, rep = rep }
		stats.lists = stats.lists + 1
	end
end

-- The popup's header (DialogHeaderTemplate: the diamond-metal plate, three
-- ARTWORK pieces, its Text over them, hanging over the popup's top edge; the
-- game sizes it to its text in Setup) -> the title plate (tabs/top in its
-- title look) as regions of the header one sublevel over the plate's piece,
-- on the header's rect (it refits when Setup resizes it), the text lifted
-- over it and set in the title face (2c).
local function SkinHeader(entry, header)
	if not header or done[header] then
		return
	end
	done[header] = true
	local center = header.CenterBG
	if not center then
		return
	end
	entry.plate = Replace(center, { as = POPUP_TITLE_RULE, rect = header, fitHeight = POPUP_TITLE_H * 1.5,
		alsoFade = List(header.LeftBG, header.RightBG) })
	entry.header = header
	if entry.plate and header.Text then
		Raise(header.Text, "OVERLAY", 7)
		local onEnable, onDisable = entry.plate.onEnable, entry.plate.onDisable
		entry.plate.onEnable = function(self)
			if onEnable then
				onEnable(self)
			end
			Kit:TitleFont(header.Text, true)
		end
		entry.plate.onDisable = function(self)
			if onDisable then
				onDisable(self)
			end
			Kit:TitleFont(header.Text, false)
		end
	end
end

-- One popup, made once: the game's dialog border (a Dialog NineSlice and its
-- dark tile, at the popup's level) faded, the single rail with the stone
-- under the inner panel laid as the popup's OWN regions in BACKGROUND under
-- its strings (the popups are children of the calendar, a level or more
-- above it: a frame of ours at the popup's level minus one could tie with
-- the calendar's rail), the header's plate, the close X, the text boxes,
-- the dividers, the buttons and edit boxes.
local function SkinPopup(p)
	if not p or done[p] then
		return
	end
	done[p] = true
	local entry = { frame = p }
	popups[#popups + 1] = entry
	FadeArt(p.Border)
	local name = NameOf(p)
	if name then
		FadeArt(_G[name .. "ButtonBackground"])
	end
	local ok, nine = pcall(Kit.NineSlice, Kit, p, { prefix = Kit.framePrefix, scale = Kit.scale * Kit.frameScale, gems = false, body = true,
		owner = p, bodyLayer = "BACKGROUND", bodySub = -7, edgeLayer = "BACKGROUND", edgeSub = -4 })
	if ok and nine then
		entry.nine = nine
		-- the inner panel over the stone inside the rail (2e: a popup is text)
		local l, r, t, b = RailInsets()
		local dim = p:CreateTexture(nil, "BACKGROUND", nil, -6)
		dim.kitPiece = true
		dim:SetPoint("TOPLEFT", p, "TOPLEFT", l, -t)
		dim:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -r, b)
		local c = MelloUI.Palette.innerPanel
		dim:SetColorTexture(c[1], c[2], c[3], 0.8)
		entry.dim = dim
		nine:SetShown(active)
		dim:SetShown(active)
	end
	SkinHeader(entry, p.Header)
	stats.popups = stats.popups + 1
end

local function SkinPopups()
	for _, pname in ipairs(POPUPS) do
		SkinPopup(_G[pname])
	end
	for _, bname in ipairs(LIST_BOXES) do
		SkinListBox(_G[bname])
	end
	for _, dname in ipairs(DIVIDERS) do
		local div = _G[dname]
		if div and not done[div] then
			done[div] = true
			-- the strip frame at the section's own level (level 0): a level
			-- lower it would tie with the popup's regions
			if Replace(div, { as = DIVIDER_RULE, fitHeight = DividerThickness(), level = 0 }) then
				stats.dividers = stats.dividers + 1
			end
		end
	end
	for _, cname in ipairs(CLOSERS) do
		SkinClose(_G[cname])
	end
	for _, pname in ipairs(POPUPS) do
		WalkControls(_G[pname])
	end
end

--------------------------------------------------------------------------------
-- The class counts (CalendarClassButton1..n: a class icon, the NormalTexture
-- the game desaturates and disables for a class nobody brings, over a
-- SpellBook-SkillLineTab square in BACKGROUND): every window's Button Border
-- rim hugging the icon (its edge 2 px under the rim's inner edge -- the
-- merchant's tools' recipe) in place of the tab square; the count stays on
-- top. The totals button under them keeps the game's art.
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
	if not (p and l and ok and iw and ih) or Secret(iw) or Secret(ih) or iw <= 0 or ih <= 0 then
		return
	end
	rim:ClearAllPoints()
	rim:SetPoint("CENTER", icon, "CENTER")
	rim:SetSize((iw - 4) * p.w / (p.w - l - r), (ih - 4) * p.h / (p.h - t - b))
end

Kit:OnBorderChanged("button", function()
	for _, holder in ipairs(rims) do
		FitIconRim(holder)
	end
end)

local function SkinClassButtons()
	for i = 1, 20 do
		local b = _G["CalendarClassButton" .. i]
		if not b then
			break
		end
		if not done[b] then
			done[b] = true
			local icon = b.GetNormalTexture and b:GetNormalTexture()
			local back
			for _, region in ipairs({ b:GetRegions() }) do
				if region ~= icon and region:GetObjectType() == "Texture" and not region.kitPiece then
					local ok, layer = pcall(region.GetDrawLayer, region)
					if ok and layer == "BACKGROUND" then
						back = region
					end
				end
			end
			if icon then
				local rep = Replace(back or icon, { as = Kit:ButtonRimRule(), button = b, parent = b, rect = icon, noFade = back == nil })
				if rep then
					local holder = { melloRep = rep, icon = icon, button = b }
					rims[#rims + 1] = holder
					Kit:RegisterButtonRim(holder)
					FitIconRim(holder)
					for _, method in ipairs({ "Enable", "Disable", "SetEnabled" }) do
						if b[method] then
							hooksecurefunc(b, method, function()
								local rim = holder.melloRep.object
								if active and rim and rim.Update then
									rim:Update()
								end
							end)
						end
					end
					stats.rims = stats.rims + 1
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Building, switching on and off
--------------------------------------------------------------------------------
local function Build()
	local cf = Window()
	if not cf then
		return
	end
	skin = skin or { reps = {}, followers = {} }
	if skin.built then
		return
	end
	skin.built = true

	-- the outer double rail in place of the twelve border pieces, on our own
	-- invisible anchor (no one piece of the game's stands for it), at the
	-- window's own level; no rail body: the page stone below is the window's
	-- one background (one per window, WINDOW-RULES 4)
	local host = CreateFrame("Frame", nil, cf)
	host:SetAllPoints(cf)
	host:EnableMouse(false)
	skin.borderArt = BorderArt(cf)
	skin.outer = Replace(Anchor(host), { as = "NineSlicePanelTemplate", parent = cf, rect = cf, body = false, noFade = true, alsoFade = skin.borderArt })
	-- the page stone: ONE picture for the window inside the outer rail, a
	-- region of the window at the bottom of its BACKGROUND (under the weekday
	-- plates; the days are frames above), on an anchor of ours: the game
	-- paints no page under its grid
	skin.stone = Replace(Anchor(cf, "BACKGROUND", -8), { as = STONE_RULE, parent = cf, rect = cf, inset = Kit:OuterRailInset(), noFade = true })

	SkinTitle(cf)
	SkinArrows()
	SkinClose(_G.CalendarCloseButton)
	SkinFilter(cf.FilterButton)
	SkinWeekdays()
	for i = 1, DAYS do
		SkinDay(_G["CalendarDayButton" .. i])
	end
	SkinToday()
	SkinPopups()
	SkinClassButtons()
	-- the rest by what it is: the popups' dropdowns, check boxes, scroll
	-- bars and any text button with its text already
	Kit:SweepControls(cf, Replace, skin)
end

-- After every show and every game refresh (a month change, an event list
-- update): today's place, the arrows' states, the title's plate
local function Refresh()
	local cf = Window()
	if not (active and skin and cf) then
		return
	end
	PlaceToday()
	for _, entry in ipairs(arrowReps) do
		ArrowLook(entry)
	end
	local plate = skin.plate
	if plate and plate.object and plate.object:IsShown() then
		plate:Refit()
	end
end

-- A popup shown: whatever it made since (a button whose text came late) and
-- its header's plate fitted to the header the game sized
local function OnPopupShow(p)
	if not (active and skin) then
		return
	end
	WalkControls(p)
	Kit:SweepControls(p, Replace, skin)
	for _, entry in ipairs(popups) do
		if entry.frame == p and entry.plate and entry.plate.object:IsShown() then
			entry.plate:Refit()
		end
	end
	for _, holder in ipairs(rims) do
		FitIconRim(holder)
	end
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
	-- the title strings onto the band first: the plate's onEnable places
	-- them (and the year takes the month's font, kept to put back, there)
	LendTitle(true)
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for _, obj in ipairs(fadedArt) do
		Kit:Fade(obj)
	end
	for _, entry in ipairs(popups) do
		if entry.nine then
			entry.nine:Show()
		end
		if entry.dim then
			entry.dim:Show()
		end
	end
	for fs, r in pairs(raised) do
		pcall(fs.SetDrawLayer, fs, r.to, r.toSub or 0)
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
	for _, entry in ipairs(popups) do
		if entry.nine then
			entry.nine:Hide()
		end
		if entry.dim then
			entry.dim:Hide()
		end
	end
	for fs in pairs(raised) do
		Lower(fs)
	end
	-- the plate's onDisable put the month's points and font back and the
	-- year home; the month's parent goes back here
	LendTitle(false)
end

-- the calendar shown now (secret-safe)
local function IsOpen(cf)
	local ok, shown = pcall(cf.IsShown, cf)
	return ok and not Secret(shown) and shown == true
end

-- (user, 2026-09-24: "dress rarely used windows on first open") nothing of
-- the calendar's look is made while it has never been shown this session:
-- it is dressed on its first show (the OnShow hook, before the first frame
-- is drawn), or at once when it is up already, then kept for the session.
-- The hooks below only listen until then (Refresh and the popups' shows
-- wait for the kit to be on).
local function Sync()
	local cf = Window()
	if M.isEnabled and cf and ((skin and skin.built) or IsOpen(cf)) then
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
	local cf = Window()
	if not cf or hooked[cf] then
		return
	end
	hooked[cf] = true
	-- the first show dresses the calendar there and then, in combat too:
	-- dressing makes frames of ours and moves only the game's own title
	-- strings (lent to our band), and nothing in the calendar is protected
	Perf.HookScript(cf, "OnShow", function()
		if M.isEnabled and not active then
			Sync()
		end
		Refresh()
	end)
	-- the game's own refresh (a month change, an event list update, today
	-- moved): a post-hook of the global, never a replacement
	if type(_G.CalendarFrame_Update) == "function" then
		hooksecurefunc("CalendarFrame_Update", Refresh)
	end
	for _, pname in ipairs(POPUPS) do
		local p = _G[pname]
		if p and not hooked[p] then
			hooked[p] = true
			Perf.HookScript(p, "OnShow", OnPopupShow)
		end
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

-- The calendar comes with its load-on-demand addon: hooked when it loads
-- (dressed then only if it is up already)
local watcher = CreateFrame("Frame")
Perf.SetScript(watcher, "OnEvent", function(_, event, name)
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
		-- not loaded yet, or not on this client at all: nothing to do until
		-- (and unless) the addon loads
		watcher:RegisterEvent("ADDON_LOADED")
	end
end

function M:OnDisable()
	SyncSafe()
end

--------------------------------------------------------------------------------
-- /calendardump [days | popups | frames | reps | regions]: with no mode, what
-- the skin found and dressed on the calendar (every part, found or not, the
-- title's place and font, today, the arrows, the popups in brief) and the
-- window's own regions; "days" every day's card; "popups" every event
-- window's parts; the other modes are Kit:DumpWindow's. Opens the copy
-- window.
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
	if not obj then
		return "-"
	end
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

local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	return (ok and type(text) == "string" and not Secret(text)) and text or "?"
end

local function FontText(fs)
	local okF, face, size = pcall(fs.GetFont, fs)
	if not okF or Secret(face) then
		return "?"
	end
	return string.format("%s %s", tostring(face):match("([^\\/]+)$") or tostring(face), Num(size))
end

local function LayerText(region)
	local ok, layer, sub = pcall(region.GetDrawLayer, region)
	return ok and (tostring(layer) .. " " .. tostring(sub)) or "?"
end

local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "") .. (Kit.faded[region] and " faded" or "")
		elseif kind == "FontString" then
			art = "text: " .. TextOf(region):sub(1, 40) .. ", font " .. FontText(region)
		end
		local okA, alpha = pcall(region.GetAlpha, region)
		MelloUI:Print("  region %s %s %s %s alpha %s shown %s", kind, Label(region), LayerText(region), art,
			(okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?", Shown(region))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local okLv, lv = pcall(child.GetFrameLevel, child)
		MelloUI:Print("  child %s %s level %s shown %s%s", tostring(child:GetObjectType()), Label(child),
			okLv and Num(lv) or "?", Shown(child), child.melloRep ~= nil and " (dressed)" or "")
	end
end

local function DumpCalendar(cf)
	local okLv, lv = pcall(cf.GetFrameLevel, cf)
	MelloUI:Print("CalendarFrame: shown %s, level %s, strata %s, %s, kit %s, reps %d, faded art %d", Shown(cf), okLv and Num(lv) or "?",
		tostring(cf:GetFrameStrata()), RectText(cf), active and "on" or "off", skin and #skin.reps or 0, #fadedArt)
	if not (skin and skin.built) then
		MelloUI:Print("  not dressed yet: the kit dresses the calendar the first time it opens (open it once for the kit's side)")
	end
	local art = skin and skin.borderArt or BorderArt(cf)
	local fadedN = 0
	for _, t in ipairs(art) do
		if Kit.faded[t] then
			fadedN = fadedN + 1
		end
	end
	MelloUI:Print("  border pieces found %d of %d, faded %d; outer rail %s (%s)", #art, #BORDER_PIECES, fadedN,
		tostring(skin and skin.outer ~= nil), skin and skin.outer and Shown(skin.outer.object) or "-")
	Found("page stone", skin and skin.stone and skin.stone.tex, skin and skin.stone and (" " .. RectText(skin.stone.inner) .. ", shown " .. Shown(skin.stone.tex)) or nil)
	MelloUI:Print("  portrait: none on this window (the game draws no ring or portrait): no ring made")
	-- the title: both strings, where they are and in which face
	for _, fs in ipairs(List(_G.CalendarMonthName, _G.CalendarYearName)) do
		Found("title string", fs, string.format(" text %s, parent %s, font %s, title face %s, lent %s, %s", TextOf(fs), Label(fs:GetParent()),
			FontText(fs), tostring(fs.melloFontSaved ~= nil), tostring(lent[fs] ~= nil), RectText(fs)))
	end
	if not _G.CalendarMonthName then
		Found("title string", nil)
	end
	local plate = skin and skin.plate
	Found("title plate", plate and plate.object, plate and (" " .. RectText(plate.object) .. ", shown " .. Shown(plate.object)) or nil)
	Found("month plate (game)", _G.CalendarMonthBackground, " " .. FadedState(_G.CalendarMonthBackground))
	Found("year plate (game)", _G.CalendarYearBackground, " " .. FadedState(_G.CalendarYearBackground))
	for _, a in ipairs(ARROWS) do
		local b = _G[a[1]]
		local entry
		for _, e in ipairs(arrowReps) do
			if e.button == b then
				entry = e
			end
		end
		local okE, enabled = false, nil
		if b then
			okE, enabled = pcall(b.IsEnabled, b)
		end
		Found("month arrow", b, b and string.format(" kit arrow %s, enabled %s", tostring(entry ~= nil),
			(okE and not Secret(enabled)) and tostring(enabled) or "?") or nil)
	end
	Found("close button", _G.CalendarCloseButton, " dressed " .. tostring(done[_G.CalendarCloseButton or false] == true))
	local filter = cf.FilterButton
	Found("filter dropdown", filter, filter and string.format(" dressed %s, shown %s", Dressed(filter), Shown(filter)) or nil)
	MelloUI:Print("  weekday headers: %d found, %d plated", #weekdays, stats.weekdays)
	for _, w in ipairs(weekdays) do
		MelloUI:Print("    %s: %s, plate %s, name layer %s", Label(w.bg), w.name and TextOf(w.name) or "?", tostring(w.rep ~= nil),
			w.name and LayerText(w.name) or "-")
	end
	local found = 0
	for i = 1, DAYS do
		if _G["CalendarDayButton" .. i] then
			found = found + 1
		end
	end
	MelloUI:Print("  days: %d of %d found, %d carded (/calendardump days for each)", found, DAYS, stats.days)
	local tf = _G.CalendarTodayFrame
	local t = skin and skin.today
	Found("today frame", tf, tf and string.format(" shown %s, on %s, golden frame %s, glow %s; kit gold rail %s on %s", Shown(tf),
		Label(tf:GetParent()), FadedState(_G.CalendarTodayTexture), FadedState(_G.CalendarTodayTextureGlow),
		tostring(t ~= nil), t and RectText(t.rect) or "-") or nil)
	MelloUI:Print("  popups: %d dressed, list boxes %d, dividers %d, edit plates %d, red plates %d, class rims %d",
		stats.popups, stats.lists, stats.dividers, stats.edits, stats.buttons, stats.rims)
	for _, pname in ipairs(POPUPS) do
		local p = _G[pname]
		Found("popup", p, p and string.format(" shown %s", Shown(p)) or nil)
	end
	MelloUI:Print("  tabs: none on this window; page picture %s; inked strings: none (no parchment on this window)",
		skin and skin.stone and RectText(skin.stone.inner) or "-")
end

local function DumpDays()
	for i = 1, DAYS do
		local b = _G["CalendarDayButton" .. i]
		if not b then
			MelloUI:Print("  day %d: -- not found", i)
		else
			local card
			for _, c in ipairs(dayCards) do
				if c.button == b then
					card = c
				end
			end
			local name = NameOf(b)
			local date = name and _G[name .. "DateFrameDate"]
			local ev = name and _G[name .. "EventTexture"]
			MelloUI:Print("  day %d: %s date %s, normal %s, card %s %s, event picture %s, dark %s, today %s", i, RectText(b),
				date and TextOf(date) or "?", FadedState(b.GetNormalTexture and b:GetNormalTexture()), tostring(card ~= nil),
				card and RectText(card.rect) or "", ev and Shown(ev) or "-", name and Shown(_G[name .. "DarkFrame"]) or "-",
				tostring(skin and skin.today and skin.today.day == b))
		end
	end
end

local function DumpPopups()
	for _, pname in ipairs(POPUPS) do
		local p = _G[pname]
		if not p then
			MelloUI:Print("%s: not on this client", pname)
		else
			local entry
			for _, e in ipairs(popups) do
				if e.frame == p then
					entry = e
				end
			end
			local okLv, lv = pcall(p.GetFrameLevel, p)
			MelloUI:Print("%s: shown %s, level %s, %s; rail %s, dim %s, border %s", pname, Shown(p), okLv and Num(lv) or "?", RectText(p),
				tostring(entry and entry.nine ~= nil), tostring(entry and entry.dim ~= nil), FadedState(p.Border))
			local h = p.Header
			if h then
				Found("header", h, string.format(" %s, text %s, font %s, layer %s, plate %s %s", RectText(h), h.Text and TextOf(h.Text) or "?",
					h.Text and FontText(h.Text) or "?", h.Text and LayerText(h.Text) or "?", tostring(entry and entry.plate ~= nil),
					entry and entry.plate and entry.plate.object and RectText(entry.plate.object) or ""))
			else
				Found("header", nil)
			end
			local function Walk(root, depth)
				for _, child in ipairs({ root:GetChildren() }) do
					local kind = child:GetObjectType()
					if kind == "Button" or kind == "CheckButton" or kind == "EditBox" or child.Background or child.Track then
						MelloUI:Print("    %s %s shown %s, dressed %s%s", kind, Label(child), Shown(child),
							tostring(Dressed(child) == "true" or done[child] == true), child.Track and " (scroll bar)" or "")
					end
					if depth < 4 then
						Walk(child, depth + 1)
					end
				end
			end
			Walk(p, 0)
		end
	end
	for _, bname in ipairs(LIST_BOXES) do
		local box = _G[bname]
		local entry
		for _, e in ipairs(listBoxes) do
			if e.frame == box then
				entry = e
			end
		end
		Found("list box", box, box and string.format(" L1 %s, dim %s, backdrop %s", tostring(entry ~= nil),
			tostring(entry and entry.rep.skin and entry.rep.skin.dimFill ~= nil), FadedState(box.NineSlice)) or nil)
	end
	for _, dname in ipairs(DIVIDERS) do
		Found("divider", _G[dname], _G[dname] and (" " .. FadedState(_G[dname])) or nil)
	end
	for i = 1, 20 do
		local b = _G["CalendarClassButton" .. i]
		if not b then
			break
		end
		local rimmed = false
		for _, holder in ipairs(rims) do
			rimmed = rimmed or holder.button == b
		end
		Found("class button", b, " rim " .. tostring(rimmed))
	end
end

SLASH_MELLOCALENDARDUMP1 = "/calendardump"
SlashCmdList.MELLOCALENDARDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local cf = Window()
	MelloUI:ClearLog()
	if not cf then
		local exists, lod, reason = "?", "?", nil
		if C_AddOns and C_AddOns.GetAddOnInfo then
			local ok, name, _, _, loadable, why = pcall(C_AddOns.GetAddOnInfo, ADDON)
			exists = (ok and name ~= nil) and "yes" or "no"
			reason = ok and (why or (loadable and "loadable") or nil) or nil
		end
		if C_AddOns and C_AddOns.IsAddOnLoadOnDemand then
			local ok, v = pcall(C_AddOns.IsAddOnLoadOnDemand, ADDON)
			lod = ok and tostring(v) or "?"
		end
		MelloUI:Print("/calendardump: no CalendarFrame. %s on this client: %s (load on demand %s, loaded %s%s).", ADDON, exists, lod,
			tostring(IsLoaded()), reason and (", " .. tostring(reason)) or "")
		MelloUI:Print("If it is on this client, open the calendar once (the minimap's calendar button) and try again; if it is not, the calendar is not on this client and the Calendar Kit does nothing.")
	elseif msg == "" then
		DumpCalendar(cf)
		MelloUI:Print("CalendarFrame's own regions and children:")
		DumpOwn(cf)
	else
		if not (skin and skin.built) then
			MelloUI:Print("/calendardump: the calendar is not dressed yet (the kit dresses it the first time it opens)")
		end
		if msg == "days" then
			DumpDays()
		elseif msg == "popups" then
			DumpPopups()
		else
			Kit:DumpWindow(cf, skin, msg ~= "regions" and msg or nil)
		end
	end
	MelloUI:ShowLog("calendardump " .. msg)
end
