--------------------------------------------------------------------------------
-- MelloUI - Dynamic UI Modification
--
-- The action bars' look picked on the bars themselves (user, 2026-09-23: "a
-- button that its called Dynamic UI Modification ... a all in one selector of
-- each Action Bar Button Border selector, Backdrop Border and Background
-- texture selector. Once you press that button, it closes the UI
-- Configurator and opens a Popup window telling the user that the
-- Configurator is running and to mouseover the action bar button, the game in
-- the background becomes dark"; "it should also have a preview on how those
-- button borders / textures look in action").
--
-- Started from the configurator's top bar (MelloUI:StartDynamicUI). The world
-- darkens under a veil at the bottom of the UI; a popup says what to do; a
-- catcher over the action bar group (Action Bar 1 and the bars snapped to it,
-- ActionBarPanel:BarOutline) lights the bars when the mouse is on them and,
-- clicked, opens the selector: a row of picture tiles for each choice (the
-- rim round a spell icon, the backdrop's border, the background's tile), the
-- current one marked. A tile applies at once, on the real bars. The catcher
-- takes the clicks, so nothing is cast while picking. Done, Escape or the
-- popup's close ends it. Not in combat.
-- The groups come from the panels that offer them (PROVIDERS: PickerGroups,
-- BarOutline, optionally PickerStart / PickerStop); the bag windows and the
-- character window joined the action bars there (user, 2026-09-23: "onto
-- the backpack icons next", "onto the Character Pane next"), opened for the
-- picker when closed.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local D = {}
MelloUI.DynamicUI = D

local GOLD = { 1, 0.82, 0 }
local TILE = 52            -- a preview tile's picture, UI px
local TILE_STEP = 78       -- tile to tile
local SAMPLE_ICON = "Interface\\Icons\\INV_Sword_04"

local running = false
local veil, popup
local catchers = {}   -- group id -> { catcher per outline rect }
local panels = {}     -- group id -> its selector
local openId = nil    -- the group whose selector is open

local function Bars()
	return MelloUI:GetModule("ActionBarPanel")
end

-- The panels whose looks are picked here, in the order their groups are offered
local PROVIDERS = { "ActionBarPanel", "BackpackPanel", "CharacterPanel", "MinimapPanel", "ProfessionsPanel" }

local function Providers()
	local out = {}
	for _, name in ipairs(PROVIDERS) do
		local m = MelloUI:GetModule(name)
		if m and m.isEnabled and m.PickerGroups and m.BarOutline then
			out[#out + 1] = m
		end
	end
	return out
end

local function Replace(region, opts)
	local rep = Kit and Kit.Replace and Kit:Replace(region, opts)
	if rep and rep.Enable then
		rep:Enable()
	end
	return rep
end

-- A window in the kit's single rail and stone (plain dark without the kit)
local function Framed(f)
	local ok = Kit and Kit.NineSlice and pcall(function()
		f.kitSkin = Kit:NineSlice(f, { prefix = "window/single", scale = Kit.scale * (Kit.frameScale or 1.6), gems = false, body = true })
	end)
	if not (ok and f.kitSkin) then
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.06, 0.055, 0.05, 0.94)
	end
end

local function Button(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 90, 22)
	b:SetText(text)
	if Kit and Kit.SkinRedButton then
		pcall(Kit.SkinRedButton, Kit, b, Replace)
	end
	return b
end

-- A gold outline (and a faint gold fill) on a frame, shown on demand
local function Outline(f, thickness, fill)
	local o = {}
	local function Edge(a, b, w, h)
		local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.95)
		t:SetPoint(a, f, a)
		t:SetPoint(b, f, b)
		if w then t:SetWidth(w) end
		if h then t:SetHeight(h) end
		o[#o + 1] = t
	end
	Edge("TOPLEFT", "TOPRIGHT", nil, thickness)
	Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, thickness)
	Edge("TOPLEFT", "BOTTOMLEFT", thickness, nil)
	Edge("TOPRIGHT", "BOTTOMRIGHT", thickness, nil)
	if fill then
		local t = f:CreateTexture(nil, "OVERLAY", nil, 6)
		t:SetAllPoints()
		t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], fill)
		o[#o + 1] = t
	end
	return function(shown)
		for _, t in ipairs(o) do
			t:SetShown(shown)
		end
	end
end

--------------------------------------------------------------------------------
-- The veil: the world darkens (a black sheet at the very bottom of the UI:
-- every window and bar stays bright over it), as while a window is dragged
--------------------------------------------------------------------------------

local function ShowVeil(on)
	if on and not veil then
		veil = CreateFrame("Frame", nil, UIParent)
		veil:SetAllPoints(UIParent)
		veil:SetFrameStrata("BACKGROUND")
		veil:SetFrameLevel(0)
		veil:EnableMouse(false)
		local tex = veil:CreateTexture(nil, "BACKGROUND")
		tex:SetAllPoints()
		tex:SetColorTexture(0, 0, 0, 0.6)
	end
	if veil then
		veil:SetShown(on and true or false)
	end
end

--------------------------------------------------------------------------------
-- The selector: a row of preview tiles per choice
--------------------------------------------------------------------------------

local function CurrentValue(module, key)
	local m = MelloUI:GetModule(module or "ActionBarPanel")
	return m and m.db and m.db[key]
end

-- Draw one tile's preview: what the choice looks like on the bar
local function DrawPreview(tile, kind, choice)
	local pic = tile.pic
	for _, t in ipairs(tile.layers) do
		t:Hide()
	end
	local nine = rawget(tile, "melloNine")   -- (fields of our own, never a method)
	if nine then
		nine:Hide()
	end
	local strip = rawget(tile, "melloStrip")
	if strip then
		strip:Hide()
	end
	tile.none:Hide()
	local function Layer(i, level)
		local t = tile.layers[i]
		if not t then
			t = pic:CreateTexture(nil, "ARTWORK", nil, level or 0)
			tile.layers[i] = t
		end
		t:ClearAllPoints()
		t:SetAllPoints(pic)
		t:SetTexCoord(0, 1, 0, 1)
		t:SetVertexColor(1, 1, 1, 1)
		t:Show()
		return t
	end
	if kind == "rim" then
		-- the rim round a spell icon on stone, as on the bar
		local back = Layer(1, 0)
		back.kitScale, back.kitOwnScale = Kit.scale, true
		Kit:Apply(back, "tiles/stone")
		Kit:Retile(back)
		local icon = Layer(2, 1)
		icon:SetTexture((GetActionTexture and GetActionTexture(1)) or SAMPLE_ICON)
		local p = Kit:Piece(choice.piece)
		if p and p.open then
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", pic, "TOPLEFT", TILE * p.open[1] / p.w, -TILE * p.open[2] / p.h)
			icon:SetPoint("BOTTOMRIGHT", pic, "BOTTOMRIGHT", -TILE * (p.w - p.open[3]) / p.w, TILE * (p.h - p.open[4]) / p.h)
		end
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		Kit:Apply(Layer(3, 2), choice.piece)
	elseif kind == "bar" and Kit.Strip then
		-- a progress bar in that bracket: a fill two thirds along, on stone
		local back = Layer(1, 0)
		back.kitScale, back.kitOwnScale = Kit.scale, true
		Kit:Apply(back, "tiles/stone")
		Kit:Retile(back)
		local base = "bars/" .. (choice.bar or "frame")
		strip = rawget(tile, "melloStrip")
		if not strip then
			strip = Kit:Strip(tile.pic, base, { scale = Kit.scale, layer = "ARTWORK", sublevel = 2 })
			rawset(tile, "melloStrip", strip)
		elseif strip.SetBase then
			strip:SetBase(base)
		end
		local yoff = strip:FitBox(TILE * 0.36)
		strip:ClearAllPoints()
		strip:SetPoint("LEFT", tile.pic, "LEFT", 2, yoff)
		strip:SetPoint("RIGHT", tile.pic, "RIGHT", -2, yoff)
		strip:SetHeight(strip.height)
		strip:FitCaps(TILE - 4)
		strip:Show()
		local fill = Layer(2, 1)
		fill:ClearAllPoints()
		fill:SetPoint("LEFT", tile.pic, "LEFT", 4, 0)
		fill:SetSize((TILE - 8) * 0.66, TILE * 0.36 * 0.5)
		fill:SetColorTexture(0.16, 0.6, 0.24, 1)
	elseif kind == "frame" then
		-- the border piece itself: its corner gems and rim round the stone
		local back = Layer(1, 0)
		back.kitScale, back.kitOwnScale = Kit.scale, true
		Kit:Apply(back, "tiles/stone")
		Kit:Retile(back)
		if choice.prefix and Kit.NineSlice then
			-- a rail family (the minimap's square borders): a small nine-slice
			-- of it round the stone, as it is laid on the real frame
			local skin = rawget(tile, "melloNine") or Kit:NineSlice(tile.pic, { prefix = choice.prefix, scale = Kit.scale * (choice.scale or 1) * 0.5,
				gems = false, body = false, corners = choice.gem and "gem" or nil })
			rawset(tile, "melloNine", skin)
			skin:Show()
		elseif choice.piece then
			Kit:Apply(Layer(2, 2), choice.piece)
		else
			back:SetVertexColor(0.45, 0.45, 0.45)
			tile.none:Show()
		end
	else
		-- a swatch of the background
		local back = Layer(1, 0)
		if choice.piece then
			back.kitScale, back.kitOwnScale = Kit.scale * 0.5, true   -- a swatch: more of the tile than the UI's resolution would show
			Kit:Apply(back, choice.piece)
			Kit:Retile(back)
		elseif choice.value == "dark" then
			back:SetColorTexture(0.05, 0.045, 0.04, 0.88)
		else
			back:Hide()
			tile.none:Show()
		end
	end
end

local function RefreshMarks(panel)
	if not panel then
		return
	end
	for _, section in ipairs(panel.sections) do
		local current = CurrentValue(section.module or panel.group.module, section.key)
		for _, tile in ipairs(section.tiles) do
			local on = tile.choice.value == current
			tile.mark(on)
			tile.label:SetTextColor(on and GOLD[1] or 0.85, on and GOLD[2] or 0.85, on and GOLD[3] or 0.85)
		end
		local label = "?"
		for _, tile in ipairs(section.tiles) do
			if tile.choice.value == current then
				label = tile.choice.label
			end
		end
		section.current:SetText(label)
	end
end

local ArmCatchers   -- below

-- `module`: a section whose setting is another module's (the Character
-- group's Side Tabs are UI Modifications')
local function Pick(panel, key, value, module)
	MelloUI:NotifySettingChanged(module or panel.group.module or "ActionBarPanel", key, value)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	RefreshMarks(panel)
	if popup and popup.Refresh then
		popup:Refresh()   -- the overview's dropdowns show the pick
	end
	-- the outline follows a backdrop that changed (after its layout settles)
	C_Timer.After(0.15, function()
		if running then
			ArmCatchers()
		end
	end)
end

-- The group the picker offers under this id (a provider's PickerGroups),
-- with the module whose settings it changes
local function GroupInfo(id)
	for _, m in ipairs(Providers()) do
		for _, g in ipairs(m:PickerGroups()) do
			if g.id == id then
				g.module = m.name
				return g
			end
		end
	end
	return nil
end

local function BuildPanel(group)
	local most = 0
	for _, section in ipairs(group.sections) do
		most = math.max(most, #(section.choices or {}))
	end
	local f = CreateFrame("Frame", "MelloUIDynamicUIPanel_" .. group.id, UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	local width = most * TILE_STEP + 48
	local sectionH = 20 + TILE + 30
	f:SetSize(width, 44 + #group.sections * sectionH + 40)
	Framed(f)
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -18)
	title:SetText(group.title)
	if Kit and Kit.TitleFont then
		pcall(Kit.TitleFont, Kit, title, true)
	end
	f.group = group
	f.sections = {}
	local y = -46
	for _, section in ipairs(group.sections) do
		local s = { key = section.key, module = section.module, tiles = {} }
		local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		head:SetPoint("TOPLEFT", 24, y)
		head:SetText(section.title .. ":")
		s.current = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		s.current:SetPoint("LEFT", head, "RIGHT", 6, 0)
		for i, choice in ipairs(section.choices or {}) do
			local tile = CreateFrame("Button", nil, f)
			tile:SetSize(TILE + 8, TILE + 8)
			tile:SetPoint("TOPLEFT", f, "TOPLEFT", 24 + (i - 1) * TILE_STEP, y - 20)
			tile.pic = CreateFrame("Frame", nil, tile)
			tile.pic:SetSize(TILE, TILE)
			tile.pic:SetPoint("CENTER")
			tile.layers = {}
			tile.none = tile.pic:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			tile.none:SetPoint("CENTER")
			tile.none:SetText("None")
			tile.none:SetTextColor(0.7, 0.7, 0.7)
			tile.choice = choice
			tile.label = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			tile.label:SetPoint("TOP", tile, "BOTTOM", 0, -1)
			tile.label:SetWidth(TILE_STEP - 4)
			tile.label:SetWordWrap(false)
			tile.label:SetText(choice.label)
			tile.mark = Outline(tile, 2, 0.12)
			tile.hover = Outline(tile, 1)
			tile.mark(false)
			tile.hover(false)
			DrawPreview(tile, section.kind, choice)
			tile:SetScript("OnEnter", function(self)
				self.hover(true)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(section.title .. ": " .. choice.label, 1, 0.82, 0)
				GameTooltip:AddLine("Click to put it on the " .. group.title:lower() .. ".", 0.9, 0.9, 0.9)
				GameTooltip:Show()
			end)
			tile:SetScript("OnLeave", function(self)
				self.hover(false)
				GameTooltip:Hide()
			end)
			tile:SetScript("OnClick", function()
				Pick(f, section.key, choice.value, section.module)
			end)
			s.tiles[#s.tiles + 1] = tile
		end
		f.sections[#f.sections + 1] = s
		y = y - sectionH
	end
	local done = Button(f, "Done", 100)
	done:SetPoint("BOTTOM", 0, 18)
	done:SetScript("OnClick", function() D:Stop() end)
	f:Hide()
	return f
end

-- Light a group's catchers (or none)
local function Light(id)
	for gid, list in pairs(catchers) do
		for _, c in ipairs(list) do
			c.lit(gid == id and c:IsShown())
		end
	end
end

local function OpenPanel(id, anchor)
	local group = GroupInfo(id)
	if not group then
		return
	end
	panels[id] = panels[id] or BuildPanel(group)
	for other, p in pairs(panels) do
		if other ~= id then
			p:Hide()
		end
	end
	local panel = panels[id]
	openId = id
	RefreshMarks(panel)
	panel:ClearAllPoints()
	-- above the bar, or below it when it sits high on the screen
	-- (beside it when neither fits: a tall window such as the bags)
	local ok, top, bottom, left = pcall(function() return anchor:GetTop(), anchor:GetBottom(), anchor:GetLeft() end)
	local need = panel:GetHeight() + 30
	local above = ok and top and (UIParent:GetTop() - top) or 0
	local below = ok and bottom or 0
	if above > need then
		panel:SetPoint("BOTTOM", anchor, "TOP", 0, 16)
	elseif below > need then
		panel:SetPoint("TOP", anchor, "BOTTOM", 0, -16)
	elseif ok and left and left > panel:GetWidth() + 30 then
		panel:SetPoint("RIGHT", anchor, "LEFT", -16, 0)
	else
		panel:SetPoint("LEFT", anchor, "RIGHT", 16, 0)
	end
	panel:Show()
	Light(id)
end

--------------------------------------------------------------------------------
-- The catchers over the bars (a set per group): light the group under the
-- mouse, open its selector on a click, and keep the clicks from casting
--------------------------------------------------------------------------------

local function Catcher(id, i)
	catchers[id] = catchers[id] or {}
	local c = catchers[id][i]
	if c then
		return c
	end
	c = CreateFrame("Button", nil, UIParent)
	c:SetFrameStrata("HIGH")
	c:EnableMouse(true)
	c:RegisterForClicks("AnyUp")
	c.lit = Outline(c, 2, 0.10)
	c.lit(false)
	c:SetScript("OnEnter", function(self)
		Light(id)
		local group = GroupInfo(id)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(group and group.title or "", 1, 0.82, 0)
		GameTooltip:AddLine(group and group.hint or "Click to choose the button border, the backdrop and the backgrounds.", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	c:SetScript("OnLeave", function()
		Light(openId)   -- back to the group whose selector is open, if any
		GameTooltip:Hide()
	end)
	c:SetScript("OnClick", function()
		GameTooltip:Hide()
		OpenPanel(id, catchers[id][1])
	end)
	catchers[id][i] = c
	return c
end

ArmCatchers = function()
	for _, list in pairs(catchers) do
		for _, c in ipairs(list) do
			c:Hide()
		end
	end
	local us = UIParent:GetEffectiveScale()
	local any = false
	for _, m in ipairs(Providers()) do
		for _, group in ipairs(m:PickerGroups()) do
			local rects = m:BarOutline(group.id)
			for i, r in ipairs(rects or {}) do
				local c = Catcher(group.id, i)
				c:ClearAllPoints()
				c:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", r[1] / us, r[2] / us)
				c:SetSize((r[3] - r[1]) / us, (r[4] - r[2]) / us)
				c:Show()
				any = true
			end
		end
	end
	Light(openId)
	return any
end

--------------------------------------------------------------------------------
-- The overview (user, 2026-09-23: "why dont we just make 1 Screen cover all
-- of the options instead of clicking on each individual window and action
-- bar, those functions should still exist"): one panel with every border
-- (UI Modifications' one choice per kind, every window's) and every group's
-- backgrounds as dropdowns; clicking a bar or a window still opens its
-- selector with pictures. Its content is laid again on every start (the
-- groups offered are the panels switched on).
--------------------------------------------------------------------------------

local OVERVIEW_W = 720
local ROW_H = 30
local DD_W = 180

local function Dropdown(parent, getValue, choices, onPick)
	local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dd:SetSize(DD_W, 25)
	dd:SetupMenu(function(_, root)
		for _, c in ipairs(choices or {}) do
			root:CreateRadio(c.label or tostring(c.value), function() return getValue() == c.value end, function() onPick(c.value) end, c.value)
		end
	end)
	dd.Refresh = function(self)
		if self.GenerateMenu then
			pcall(self.GenerateMenu, self)
		end
	end
	return dd
end

local function UMValue(key, default)
	local um = MelloUI:GetModule("UIModifications")
	local v = um and um.db and um.db[key]
	if v == nil then
		return default
	end
	return v
end

-- The panel's rows: the borders on the left, the backgrounds on the right
local function FillOverview(f)
	local old = rawget(f, "melloBody")   -- (a field of our own, never a method)
	if old then
		old:Hide()
	end
	local body = CreateFrame("Frame", nil, f)
	body:SetAllPoints()
	rawset(f, "melloBody", body)
	f.dropdowns = {}
	local function Heading(text, x, y)
		local fs = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetPoint("TOPLEFT", x, y)
		fs:SetText(text)
		return fs
	end
	local function Row(label, x, y, getValue, choices, onPick)
		local fs = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", x, y - 7)
		fs:SetWidth(OVERVIEW_W / 2 - DD_W - 40)
		fs:SetJustifyH("LEFT")
		fs:SetText(label)
		local dd = Dropdown(body, getValue, choices, onPick)
		dd:SetPoint("TOPLEFT", x + OVERVIEW_W / 2 - DD_W - 36, y)
		f.dropdowns[#f.dropdowns + 1] = dd
		return dd
	end
	local left, right = 24, OVERVIEW_W / 2 + 8
	local top = -84
	Heading("Borders (every window)", left, top)
	local y = top - 22
	for _, k in ipairs(Kit and Kit.borderKinds or {}) do
		Row(k.name, left, y, function() return UMValue(k.key, k.default) end, k.values, function(v)
			MelloUI:NotifySettingChanged("UIModifications", k.key, v)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			if f.Refresh then
				f:Refresh()
			end
		end)
		y = y - ROW_H
	end
	local leftBottom = y
	Heading("Backgrounds (or click a bar or window)", right, top)
	y = top - 22
	for _, m in ipairs(Providers()) do
		for _, g in ipairs(m:PickerGroups()) do
			for _, s in ipairs(g.sections or {}) do
				local module = s.module or m.name
				Row(g.title .. ": " .. s.title, right, y, function() return CurrentValue(module, s.key) end, s.choices, function(v)
					MelloUI:NotifySettingChanged(module, s.key, v)
					PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
					if f.Refresh then
						f:Refresh()
					end
					C_Timer.After(0.15, function()
						if running then
							ArmCatchers()
						end
					end)
				end)
				y = y - ROW_H
			end
		end
	end
	local bottom = math.min(leftBottom, y)
	f:SetHeight(-bottom + 60)
end

local function BuildPopup()
	local f = CreateFrame("Frame", "MelloUIDynamicUIPopup", UIParent)
	f:SetSize(OVERVIEW_W, 300)
	f:SetPoint("TOP", UIParent, "TOP", 0, -80)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	Framed(f)
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -18)
	title:SetText("Dynamic UI Modification")
	if Kit and Kit.TitleFont then
		pcall(Kit.TitleFont, Kit, title, true)
	end
	local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOP", title, "BOTTOM", 0, -8)
	text:SetWidth(OVERVIEW_W - 60)
	text:SetText("The borders go on every window at once. The backgrounds are here too, or move the mouse over your "
		.. "action bars, micro menu, bag bar, bags, character window or minimap and click one to pick with pictures.")
	local done = Button(f, "Done", 100)
	done:SetPoint("BOTTOM", 0, 16)
	done:SetScript("OnClick", function() D:Stop() end)
	f.Refresh = function(self)
		for _, dd in ipairs(self.dropdowns or {}) do
			dd:Refresh()
		end
	end
	-- hidden before it listens: its first Hide would end the picker it opens for
	f:Hide()
	-- Escape closes it (and with it the picker)
	tinsert(UISpecialFrames, "MelloUIDynamicUIPopup")
	f:SetScript("OnHide", function()
		if running then
			D:Stop()
		end
	end)
	return f
end

--------------------------------------------------------------------------------
-- Start / stop
--------------------------------------------------------------------------------

function D:Start()
	if running then
		return
	end
	if InCombatLockdown() then
		MelloUI:Print("Dynamic UI Modification: not in combat.")
		return
	end
	local bars = Bars()
	if not (bars and bars.isEnabled and bars.BarOutline and bars:BarOutline("bars")) then
		MelloUI:Print("Dynamic UI Modification: the action bars reskin is off (UI Modifications, Action bars).")
		return
	end
	for _, m in ipairs(Providers()) do
		if m.PickerStart then
			pcall(m.PickerStart, m)
		end
	end
	local config = _G.MelloUIConfigFrame
	if config and config:IsShown() then
		config:Hide()
	end
	running = true
	ShowVeil(true)
	popup = popup or BuildPopup()
	FillOverview(popup)
	popup:Show()
	ArmCatchers()
	-- a window opened for the picker (the bags) lays itself out a beat later
	C_Timer.After(0.2, function()
		if running then
			ArmCatchers()
		end
	end)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
end

function D:Stop()
	if not running then
		return
	end
	running = false
	ShowVeil(false)
	for _, list in pairs(catchers) do
		for _, c in ipairs(list) do
			c.lit(false)
			c:Hide()
		end
	end
	for _, p in pairs(panels) do
		p:Hide()
	end
	openId = nil
	for _, m in ipairs(Providers()) do
		if m.PickerStop then
			pcall(m.PickerStop, m)
		end
	end
	if popup and popup:IsShown() then
		popup:Hide()
	end
	GameTooltip:Hide()
	-- the configurator's dropdowns show the choices made here when it opens again
	if MelloUI.RefreshConfig then
		MelloUI:RefreshConfig()
	end
	PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
end

function D:IsRunning()
	return running
end

function MelloUI:StartDynamicUI()
	D:Start()
end

-- A fight ends the picker (its catcher sits over the bars)
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
	if running then
		D:Stop()
		MelloUI:Print("Dynamic UI Modification ended: combat.")
	end
end)
