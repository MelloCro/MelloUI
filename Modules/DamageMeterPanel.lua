--------------------------------------------------------------------------------
-- MelloUI - Damage Meter Panel
--
-- The game's damage meter (Blizzard_DamageMeter: `DamageMeter`, an Edit
-- Mode system, with its session windows `DamageMeterSessionWindowN` and
-- their source / spell breakdown windows) dressed in the painted kit
-- (Modules/Kit.lua) on the game's own layout, by the rule book's fixed
-- looks and the user's pick (kit_raw/dpsmeter_catalog.png, 2026-09-21):
--   D1 / P1: every entry bar in the hollow bracket, the class-coloured fill
--   behind it filling its inner area (as the character window's bars).
--   Fixed: the meter body on L1 (single rail + stone) on the background's
--   rect, its alpha following the meter's transparency setting; the header
--   band on `lists/header`; the minimize button on minus / plus; the
--   settings button on the cog plate under its glyph; the session / type
--   dropdowns D1 and the scroll bar T2-H1-S1 by the sweep; the class icon of
--   a source entry swapped for the painted class medallion (a spec icon
--   stays). Left as the game's: the scale handles (functional grips), the
--   "not active" text, the entries' texts.
-- Covers the Dark Mode group "damagemeter". /dmdump [n] [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("DamageMeterPanel")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("DamageMeterPanel", {
	title = "Damage Meter Kit",
	desc = "The game's damage meter (window, header, entry bars, breakdown windows) dressed in the painted kit on its own layout.",
	window = { label = "Damage meter", desc = "The damage meter and its breakdown window in the kit.", tab = "HUD", addon = "Blizzard_DamageMeter" },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil
local active = false

local function IsActive()
	return active
end

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Damage meter: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- A source entry's class icon: the painted class medallion (a spec icon,
-- which the game prefers when it knows the spec, stays); put back to the
-- game's atlas on disable.
local function Medallion(entry)
	local icon = entry.Icon and entry.Icon.Icon
	if not icon then
		return
	end
	local ok, classFile = pcall(function() return entry.classFilename end)
	local okS, spec = pcall(function() return entry.specIconID end)
	if not active or not ok or Secret(classFile) or not classFile or classFile == "" or (okS and spec and not Secret(spec) and spec ~= 0) then
		if entry.melloMedallion then
			entry.melloMedallion = nil
			local atlas = entry.iconAtlasElement
			if atlas and not Secret(atlas) then
				icon:SetAtlas(atlas)
			end
		end
		return
	end
	local path = MelloUI.ClassIconPath and MelloUI:ClassIconPath(classFile)
	if path then
		icon:SetTexture(path)
		icon:SetTexCoord(0, 1, 0, 1)
		entry.melloMedallion = classFile
	end
end

-- An entry's contents condensed into its bracket (user, 2026-09-21: the
-- bars as well): the name and value at 0.8 of the meter's text scale, set
-- in from the bracket's arms so the rails and gems do not touch them; the
-- icon square (24 px in the XML whatever the bar height) at the entry's
-- height. Re-applied after the game's SetTextScale / UpdateStyle /
-- SetBarHeight, which set those; the game's values put back on disable.
local ENTRY_TEXT_SCALE = 0.8

local function CondenseEntry(entry, rep)
	if entry.melloCondensed then
		return
	end
	entry.melloCondensed = true
	local bar, icon = entry.StatusBar, entry.Icon
	local name, value = bar.Name, bar.Value
	if not (name and value and icon) then
		return
	end
	local ok, base = pcall(name.GetTextScale, name)
	entry.melloBaseText = (ok and base and not Secret(base)) and base or 1
	local okW, iconW = pcall(icon.GetWidth, icon)
	local okH, iconH = pcall(icon.GetHeight, icon)
	local savedIcon = (okW and okH and not Secret(iconW) and not Secret(iconH)) and { iconW, iconH } or { 24, 24 }
	-- the status bar set in from the game's anchors by the bracket's arms
	-- (the caps stand outside the bar, `capOut`): a StatusBar's fill cannot
	-- be re-anchored, so the bar itself ends where the gems begin. Done once
	-- per game layout (UpdateStyle re-anchors it, then this shifts it again).
	local savedBar = {}
	for i = 1, bar:GetNumPoints() do
		savedBar[i] = { bar:GetPoint(i) }
	end
	entry.melloBarFresh = true
	-- the game's own anchors for the current layout, read right after the game
	-- set them (melloBarFresh) and kept: every fit is computed from these, so it
	-- can be redone at any time — after SetBarHeight, which only resizes the
	-- row — without shifting an already shifted bar a second time
	local basePoints
	local function ShiftBar()
		if entry.melloBarFresh or not basePoints then
			local okN, n = pcall(bar.GetNumPoints, bar)
			if not okN or Secret(n) or not n then
				return
			end
			local read = {}
			for i = 1, n do
				local okP, point, rel, relPoint, x, y = pcall(bar.GetPoint, bar, i)
				if not okP or Secret(point) or Secret(x) or Secret(y) or not point then
					return
				end
				read[i] = { point, rel, relPoint, x or 0, y or 0 }
			end
			basePoints = read
		end
		local points = basePoints
		local armL, armR = rep:GetArms()
		-- the WHOLE bracket, its gem caps included, as tall as the row (user,
		-- 2026-09-23: "scale down the artwork here on the DPS meter bars to
		-- fit" — fitted to the bar, the caps stood out of the row and the right
		-- one into the window's rail). The bracket follows the bar's height,
		-- so the bar is what is shortened: to the opening the bracket has at
		-- the scale where the whole strip is the row's height, which scales the
		-- caps and their arms down with it. The arms below are taken at that
		-- scale, not the current one, since the refit comes after.
		local inset = 0
		local okR, rowH = pcall(entry.GetHeight, entry)
		local strip = rep.strip
		if okR and rowH and not Secret(rowH) and rowH > 0 and strip and strip.FitWhole and strip.scale and strip.scale > 0 then
			local fitScale, box = strip:FitWhole(rowH)
			if fitScale then
				local k = fitScale / strip.scale
				armL, armR = armL * k, armR * k
				-- the bar's height from its own top and bottom anchors on the row
				-- (the game's default: TOP -1, BOTTOMRIGHT +1)
				local topY, bottomY
				for _, pt in ipairs(points) do
					if pt[1]:find("^TOP") then
						topY = pt[5]
					elseif pt[1]:find("^BOTTOM") then
						bottomY = pt[5]
					end
				end
				if topY and bottomY then
					inset = math.max(0, (rowH + topY - bottomY - box) / 2)
				end
			end
		end
		entry.melloBarFresh = nil
		bar:ClearAllPoints()
		for _, pt in ipairs(points) do
			local point, rel, relPoint, x, y = unpack(pt)
			if point == "LEFT" or point == "TOPLEFT" or point == "BOTTOMLEFT" then
				x = x + armL
			elseif point == "RIGHT" or point == "TOPRIGHT" or point == "BOTTOMRIGHT" then
				x = x - armR
			end
			if point:find("^TOP") then
				y = y - inset
			elseif point:find("^BOTTOM") then
				y = y + inset
			end
			bar:SetPoint(point, rel, relPoint, x, y)
		end
	end
	local function Apply()
		if not (active and rep.GetArms) then
			return
		end
		ShiftBar()
		local k = entry.melloBaseText * ENTRY_TEXT_SCALE
		entry.melloScaling = true
		name:SetTextScale(k)
		value:SetTextScale(k)
		entry.melloScaling = nil
		-- the texts inside the bar, which now ends at the gems
		name:SetPoint("LEFT", 4, 0)
		value:SetPoint("RIGHT", -4, 0)
		local okE, h = pcall(entry.GetHeight, entry)
		if okE and h and not Secret(h) and h > 0 then
			icon:SetSize(h, h)
		end
	end
	local function Restore()
		name:SetTextScale(entry.melloBaseText)
		value:SetTextScale(entry.melloBaseText)
		name:SetPoint("LEFT", 2, 0)
		value:SetPoint("RIGHT", -3, 0)
		icon:SetSize(savedIcon[1], savedIcon[2])
		bar:ClearAllPoints()
		for _, pt in ipairs(savedBar) do
			bar:SetPoint(unpack(pt))
		end
		entry.melloBarFresh = true
	end
	hooksecurefunc(entry, "SetTextScale", function(_, textScale)
		if entry.melloScaling then
			return
		end
		if textScale and not Secret(textScale) then
			entry.melloBaseText = textScale
		end
		Apply()
	end)
	hooksecurefunc(entry, "UpdateStyle", function()
		entry.melloBarFresh = true
		Apply()
	end)
	hooksecurefunc(entry, "SetBarHeight", Apply)
	Perf.HookScript(bar, "OnSizeChanged", function()
		if active then
			rep:Refit()
		end
	end)
	local enable, disable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if enable then
			enable(...)
		end
		Apply()
	end
	rep.onDisable = function(...)
		if disable then
			disable(...)
		end
		Restore()
	end
	Apply()
end

-- An entry (DamageMeterEntryTemplate, 24 px: the icon frame at the left,
-- the status bar to its right with `Background` (the shadow band, its alpha
-- the meter's transparency) and `BackgroundEdge` around the fill): P1, the
-- bracket as regions of the status bar one layer above its fill, the
-- trough under the fill, the shadow pieces faded.
local function SkinEntry(entry)
	if not (entry and entry.StatusBar) or entry.melloRep ~= nil then
		return
	end
	local bar = entry.StatusBar
	local layer, sublevel, troughLayer, troughSub = Kit:BracketLayers(bar)
	entry.melloRep = Replace(bar.Background, { as = "ui-damagemeters-bar-shadowbg", parent = bar, rect = bar,
		layer = layer, sublevel = sublevel, troughLayer = troughLayer, troughSub = troughSub,
		alsoFade = { bar.BackgroundEdge } }) or false
	if entry.UpdateIcon and not entry.melloIconHooked then
		entry.melloIconHooked = true
		hooksecurefunc(entry, "UpdateIcon", Medallion)
		skin.entries[#skin.entries + 1] = entry
	end
	Medallion(entry)
	if entry.melloRep then
		CondenseEntry(entry, entry.melloRep)
	end
end

-- The minimize button: minus / plus following the atlas the game sets.
local function SkinToggle(button)
	if not (button and button.GetNormalTexture and button:GetNormalTexture()) or button.melloToggle then
		return
	end
	button.melloToggle = true
	local normal = button:GetNormalTexture()
	local extra = { button:GetPushedTexture(), button:GetHighlightTexture() }
	Kit:StateIconReps(button, normal, button, Replace, extra)
	hooksecurefunc(normal, "SetAtlas", function()
		if active then
			Kit:StateIconReps(button, normal, button, Replace, extra)
		end
	end)
end

-- A body backdrop (the session window's `MinimizeContainer.Background`, the
-- source window's `Background`): L1 as the container's child one level under
-- it, its alpha the session window's transparency setting.
local function SkinBody(container, background, key, session)
	if not (container and background) or background.melloRep ~= nil then
		return
	end
	-- one level UNDER the window's, so the header plate (a region of the
	-- window) draws over the body's rail where they cross (user,
	-- 2026-09-21: the border covered the header artwork)
	local rep = Replace(background, { as = key, parent = container, rect = background, level = -1 })
	background.melloRep = rep or false
	-- the parchment laid on the stone, inside the rails, its edge painted
	-- (user, 2026-09-23: "lets make it on chat and dps meter aswell"); it
	-- follows the body's opacity with it (a texture of the body's skin)
	if rep and rep.skin and Kit.ParchmentSheet then
		Kit:ParchmentSheet(rep.skin, rep.object, { area = "meter" })
	end
	-- no eye strain (user, 2026-09-24: "too much small text over a plain
	-- brown border is just an eye strain" / "apply the eye strain rule to all
	-- existing windows"; WINDOW-RULES 2e): the rows' names and numbers, the
	-- gaps between the bars and the "not active" line lie on the body, so on
	-- the stone look (the meter's parchment off) the stone inside the rails
	-- lies under the palette's inner panel. A region of the body's skin
	-- between the stone and the sheet (the bars, their fills and texts are
	-- the game's frames above it), following the body's opacity with it;
	-- Kit:SetParchment switches it against the sheet.
	if rep and rep.skin and Kit.StoneDim then
		Kit:StoneDim(rep.skin, { area = "meter" })
	end
	if not (rep and session and session.GetBackgroundAlpha) then
		return
	end
	local holder = rep.object
	local function Opacity()
		if not active then
			return
		end
		local ok, alpha = pcall(session.GetBackgroundAlpha, session)
		if ok and alpha and not Secret(alpha) then
			holder:SetAlpha(alpha)
		end
	end
	if session.SetBackgroundAlpha then
		hooksecurefunc(session, "SetBackgroundAlpha", Opacity)
	end
	local enable = rep.onEnable
	rep.onEnable = function(...)
		if enable then
			enable(...)
		end
		Opacity()
	end
	if active then
		Opacity()
	end
end

-- Both windows start their hover effect (the resize grip and the scroll
-- bar fading in) from their own OnEnter, which a cursor landing on a row
-- never fires (the rows take the mouse; the main window's poll only runs
-- while a session timer is live). A row's OnEnter hands it on (user,
-- 2026-09-21: no mouseover effect over the bars).
local function HandOnHover(row, window)
	if not row or row.melloHoverHook then
		return
	end
	row.melloHoverHook = true
	Perf.HookScript(row, "OnEnter", function()
		if active and window.OnEnter and window:IsShown() then
			window:OnEnter()
		end
	end)
end

local function SkinSourceWindow(sw, session)
	if not sw or sw.melloSkinned then
		return
	end
	sw.melloSkinned = true
	SkinBody(sw, sw.Background, "DamageMeterSourceBackground", session)
	if sw.ScrollBox then
		Kit:HookScrollBoxRows(sw.ScrollBox, function(row)
			SkinEntry(row)
			HandOnHover(row, sw)
		end, IsActive, true)
	end
	Kit:SweepControls(sw, Replace, skin)
end

-- The header's controls condensed into the plate's band (user, 2026-09-21:
-- the buttons and the text should sit inside the top bar): the timer, the
-- type and session dropdowns, the settings cog and the minimize button at
-- 0.8 of their size, each centred on the band's line, the outer ones kept
-- off the caps' gems (23 % of a header cap, measured); the game's own
-- anchors put back on disable. The game never re-anchors these (it only
-- sets the session dropdown's width), so once is enough.
local HEADER_SCALE = 0.8
local GEM_SHARE = 0.23

local function CondenseHeader(win, rep)
	local header = win.Header
	local timer, typeDD, sessionDD, settings, minimize = win.SessionTimer, win.DamageMeterTypeDropdown, win.SessionDropdown, win.SettingsDropdown, win.MinimizeButton
	if not (header and rep and rep.strip and minimize and settings and sessionDD and typeDD and timer) then
		return
	end
	local frames = { minimize, settings, sessionDD, typeDD }
	local saved = {}
	for _, f in ipairs(frames) do
		local points = {}
		for i = 1, f:GetNumPoints() do
			points[i] = { f:GetPoint(i) }
		end
		saved[f] = points
	end
	local timerPoints = {}
	for i = 1, timer:GetNumPoints() do
		timerPoints[i] = { timer:GetPoint(i) }
	end
	local function Condense()
		local k = HEADER_SCALE
		local wl, wr = (rep.strip.wl or 0) * GEM_SHARE, (rep.strip.wr or 0) * GEM_SHARE
		for _, f in ipairs(frames) do
			f:SetScale(k)
		end
		timer:SetTextScale(k)
		timer:ClearAllPoints()
		timer:SetPoint("LEFT", header, "LEFT", wl + 4, 0)
		typeDD:ClearAllPoints()
		typeDD:SetPoint("LEFT", timer, "RIGHT", 0, 0)
		minimize:ClearAllPoints()
		minimize:SetPoint("RIGHT", header, "RIGHT", -(wr + 2) / k, 0)
		settings:ClearAllPoints()
		settings:SetPoint("RIGHT", minimize, "LEFT", -2, 0)
		sessionDD:ClearAllPoints()
		sessionDD:SetPoint("RIGHT", settings, "LEFT", -2, 0)
		for _, fs in ipairs({ timer, typeDD.TypeName, sessionDD.SessionName }) do
			Kit:TitleFont(fs, true)
		end
	end
	local function Restore()
		for _, fs in ipairs({ timer, typeDD.TypeName, sessionDD.SessionName }) do
			Kit:TitleFont(fs, false)
		end
		for _, f in ipairs(frames) do
			f:SetScale(1)
			f:ClearAllPoints()
			for _, pt in ipairs(saved[f]) do
				f:SetPoint(unpack(pt))
			end
		end
		timer:SetTextScale(1)
		timer:ClearAllPoints()
		for _, pt in ipairs(timerPoints) do
			timer:SetPoint(unpack(pt))
		end
	end
	local enable, disable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if enable then
			enable(...)
		end
		Condense()
	end
	rep.onDisable = function(...)
		if disable then
			disable(...)
		end
		Restore()
	end
	Perf.HookScript(win, "OnShow", function()
		if active then
			Condense()
		end
	end)
	if active then
		Condense()
	end
end

local function SkinSession(win)
	if not win or win.melloSkinned then
		return
	end
	win.melloSkinned = true
	if win.Header then
		local rep = Replace(win.Header, { as = "ui-damagemeters-header-bar", rect = win.Header })
		win.melloHeaderRep = rep
		if rep then
			CondenseHeader(win, rep)
		end
	end
	local container = win.MinimizeContainer
	if container then
		SkinBody(container, container.Background, "damagemeters-background", win)
		local body = container.Background and container.Background.melloRep
		if Kit.RegisterShell and DamageMeter and DamageMeter.GetPrimarySessionWindow
			and DamageMeter:GetPrimarySessionWindow() == win then
			-- only the lit rail is registered here. The meter is dragged by
			-- its HEADER (user, 2026-09-22: "the damage meter should be
			-- dragable by the windows header, not the Bar"), and the grab
			-- for it -- the band between the header's own controls -- is
			-- made by UI Modifications' sweep, with or without the reskin,
			-- so there is one handle and one highlight rather than two.
			Kit:RegisterShell(DamageMeter, { outer = body or nil })
		end
		if container.ScrollBox then
			Kit:HookScrollBoxRows(container.ScrollBox, function(row)
				SkinEntry(row)
				HandOnHover(row, win)
			end, IsActive, true)
		end
		SkinEntry(container.LocalPlayerEntry)
		HandOnHover(container.LocalPlayerEntry, win)
		SkinSourceWindow(container.SourceWindow, win)
	end
	SkinToggle(win.MinimizeButton)
	-- the settings button: the kit's cog IN PLACE of the game's gear, not under
	-- it. It was laid under the glyph (noFade) and read as two gears stacked
	-- (user, 2026-09-23: "has its reskined version under the default one"); the
	-- other settings cogs of the kit (quest log, spell book) already fade theirs.
	local settings = win.SettingsDropdown
	if settings and settings.Icon and settings.melloRep == nil then
		settings.melloRep = Replace(settings.Icon, { as = "DamageMeterSettingsIcon", button = settings }) or false
	end
	-- the session dropdown (current / overall segment): a WowStyle2Dropdown
	-- (the compact common-dropdown-c-button) that the game sizes to 18 or 32 px
	-- for a short name. The sweep below would dress it as a text dropdown with
	-- the D1 plate, whose two caps alone are wider than the button, so it
	-- collapsed into a stub of rail and gems (user, 2026-09-23: "looking
	-- wierd"). It takes B6 instead, the single-rail band the user picked for the
	-- c-button's sibling (common-dropdown-b-button), which holds at any width;
	-- the c-button's hover arrow under it goes too. Claimed here, the sweep
	-- skips it (melloRep).
	local sessionDD = win.SessionDropdown
	if sessionDD and sessionDD.Background and sessionDD.melloRep == nil then
		sessionDD.melloRep = Replace(sessionDD.Background, { as = "common-dropdown-b-button", rect = sessionDD, button = sessionDD,
			parent = sessionDD, alsoFade = { sessionDD.Arrow } }) or false
	end
	-- the type dropdown ("Damage Done", "Healing Done", ...): a
	-- WowStyle1ArrowDropdownTemplate with hasShadow false, whose Arrow the game
	-- re-atlases on every state change (the -shadowless set). The kit's down
	-- arrow takes its place and follows the button's hover / press; the game's
	-- arrow stays faded whatever atlas it is given. (The sweep below skips this
	-- dropdown: it has no Background / Text, so nothing dresses it twice.)
	local typeDD = win.DamageMeterTypeDropdown
	if typeDD and typeDD.Arrow and typeDD.melloRep == nil then
		typeDD.melloRep = Replace(typeDD.Arrow, { as = "common-dropdown-a-button-shadowless", button = typeDD, rect = typeDD.Arrow }) or false
	end
	Kit:SweepControls(win, Replace, skin)
end

local function SkinAll()
	local meter = DamageMeter
	if not meter then
		return
	end
	if meter.ForEachSessionWindow then
		meter:ForEachSessionWindow(SkinSession)
	end
end

local function Build()
	if skin then
		return
	end
	skin = { reps = {}, followers = {}, entries = {} }
	SkinAll()
	local meter = DamageMeter
	if meter and meter.SetupSessionWindow then
		-- secondary session windows are made on demand
		hooksecurefunc(meter, "SetupSessionWindow", function(self, index)
			if active and self.GetSessionWindow then
				SkinSession(self:GetSessionWindow(index))
			end
		end)
	end
end

local function Activate()
	if active then
		return
	end
	active = true
	Build()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for _, entry in ipairs(skin.entries) do
		Medallion(entry)
	end
	SkinAll()
	Kit:Cover("damagemeter")
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	for _, entry in ipairs(skin.entries) do
		Medallion(entry)
	end
	Kit:Uncover("damagemeter")
end

local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(_, _, addon)
	if addon == "Blizzard_DamageMeter" and DamageMeter then
		eventFrame:UnregisterAllEvents()
		if M.db then
			Activate()
		end
	end
end)

function M:OnEnable(db)
	self.db = db
	if DamageMeter then
		Activate()
	else
		eventFrame:RegisterEvent("ADDON_LOADED")
	end
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /dmdump [n] [frames|reps]: a session window's art (n = 1 by default).
-- Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLODMDUMP1 = "/dmdump"
SlashCmdList.MELLODMDUMP = function(msg)
	msg = (msg or ""):lower()
	local n = tonumber(msg:match("^(%d+)")) or 1
	local what = msg:match("%a+")
	MelloUI:ClearLog()
	local win = DamageMeter and DamageMeter.GetSessionWindow and DamageMeter:GetSessionWindow(n)
	if not win then
		MelloUI:Print("No damage meter window %d.", n)
	else
		Kit:DumpWindow(win, skin, what)
	end
	MelloUI:ShowLog("dmdump " .. msg)
end
