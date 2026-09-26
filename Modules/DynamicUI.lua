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
local Perf = MelloUI.Perf:Scope("DynamicUI")
local C_Timer = Perf.C_Timer
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
		return
	end
	-- its texts (the pickers' headings, current values and tile names, the
	-- overview's introduction) lay on the plain brown: the palette's inner
	-- panel over the stone inside the rail (user, 2026-09-24: "apply the eye
	-- strain rule to all existing windows"; WINDOW-RULES 2e), a region of the
	-- skin between its stone (BACKGROUND 0) and its rails (BORDER). The
	-- previews are pictures on their own frames, above it.
	local skin = f.kitSkin
	if skin.body and Kit.StoneDim then
		Kit:StoneDim(skin, { rect = skin, margin = (skin.thickness or 0) * 0.6, sublevel = 1 })
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
			-- the palette's text, its gold on the chosen one (WINDOW-RULES 2e)
			local c = on and MelloUI.Palette.selectedTrim or MelloUI.Palette.text
			tile.label:SetTextColor(c[1], c[2], c[3])
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

-- the catchers placed again a moment after a pick, once the backdrop that
-- changed has laid itself out (one function, not a new one per pick)
local function RearmIfRunning()
	if running then
		ArmCatchers()
	end
end

-- `module`: a section whose setting is another module's (the Character
-- group's Side Tabs are UI Modifications')
local function Pick(panel, key, value, module)
	MelloUI:NotifySettingChanged(module or panel.group.module or "ActionBarPanel", key, value)
	MelloUI:PlayUISound("option_on")
	RefreshMarks(panel)
	if popup and popup.Refresh then
		popup:Refresh()   -- the overview's dropdowns show the pick
	end
	-- the outline follows a backdrop that changed (after its layout settles)
	C_Timer.After(0.15, RearmIfRunning)
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
		-- the heading in the palette's gold, the current choice in its text
		-- colour, on the dark panel (WINDOW-RULES 2e)
		local pal = MelloUI.Palette
		if pal then
			head:SetTextColor(pal.selectedTrim[1], pal.selectedTrim[2], pal.selectedTrim[3])
			s.current:SetTextColor(pal.text[1], pal.text[2], pal.text[3])
		end
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
			-- the tooltip's texts made once, not on every hover
			local tipTitle = section.title .. ": " .. choice.label
			local tipLine = "Click to put it on the " .. group.title:lower() .. "."
			Perf.SetScript(tile, "OnEnter", function(self)
				self.hover(true)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(tipTitle, 1, 0.82, 0)
				GameTooltip:AddLine(tipLine, 0.9, 0.9, 0.9)
				GameTooltip:Show()
			end)
			Perf.SetScript(tile, "OnLeave", function(self)
				self.hover(false)
				GameTooltip:Hide()
			end)
			Perf.SetScript(tile, "OnClick", function()
				Pick(f, section.key, choice.value, section.module)
			end)
			s.tiles[#s.tiles + 1] = tile
		end
		f.sections[#f.sections + 1] = s
		y = y - sectionH
	end
	local done = Button(f, "Done", 100)
	done:SetPoint("BOTTOM", 0, 18)
	Perf.SetScript(done, "OnClick", function() D:Stop() end)
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
	Perf.SetScript(c, "OnEnter", function(self)
		Light(id)
		-- the group's title and hint as the catcher was placed (ArmCatchers):
		-- a hover no longer asks every panel for its groups
		local group = rawget(self, "melloGroup") or GroupInfo(id)   -- (a field of our own, never a method)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(group and group.title or "", 1, 0.82, 0)
		GameTooltip:AddLine(group and group.hint or "Click to choose the button border, the backdrop and the backgrounds.", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	Perf.SetScript(c, "OnLeave", function()
		Light(openId)   -- back to the group whose selector is open, if any
		GameTooltip:Hide()
	end)
	Perf.SetScript(c, "OnClick", function()
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
				c.melloGroup = group
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
-- selector with pictures. Its content follows the panels switched on: laid
-- the first time they are on offer, and kept for the next start with the
-- same ones (user, 2026-09-24: every start laid a new copy of it).
--------------------------------------------------------------------------------

local OVERVIEW_W = 860
local ROW_H = 32
local DD_W = 200
-- depth (user, 2026-09-24: "too much small text over a plain brown border
-- is just an eye strain"): each column on a dark panel of the palette (the
-- inner panel inside the kit's single rail), its rows striped, the text at
-- the interface's full size in the palette's text colour
local PAL = MelloUI.Palette
local PANEL_M, PANEL_GAP, PANEL_PAD = 18, 16, 14   -- outer margin, gap between the columns, text inset in a panel
local COL_W = (OVERVIEW_W - 2 * PANEL_M - PANEL_GAP) / 2

local function Dropdown(parent, getValue, choices, onPick)
	local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dd:SetSize(DD_W, 25)
	dd:SetupMenu(function(_, root)
		for _, c in ipairs(choices or {}) do
			root:CreateRadio(c.label or tostring(c.value), function() return getValue() == c.value end, function() onPick(c.value) end, c.value)
		end
	end)
	-- the menu is made again only when the setting has changed since it was
	-- last made (user, 2026-09-24: every refresh of the overview made all
	-- sixteen menus again); made at SetupMenu when the box already names the
	-- setting's choice, otherwise on the first refresh
	dd.shownValue = dd   -- (the box itself: equal to no setting)
	local text, current = dd.Text, getValue()
	if type(text) == "table" and text.GetText then
		for _, c in ipairs(choices or {}) do
			if c.value == current then
				if text:GetText() == (c.label or tostring(c.value)) then
					dd.shownValue = current
				end
				break
			end
		end
	end
	dd.Refresh = function(self)
		local value = getValue()
		if value == self.shownValue then
			return
		end
		self.shownValue = value
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

-- A switch row (a kit check box when the kit is there)
local function Check(parent, label, getValue, onPick)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	if cb.Text then
		cb.Text:Hide()
	end
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	fs:SetJustifyH("LEFT")
	fs:SetText(label)
	if PAL and PAL.text then
		fs:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
	end
	Perf.SetScript(cb, "OnClick", function(self)
		onPick(self:GetChecked() and true or false)
	end)
	if Kit and Kit.SkinCheckButton then
		pcall(Kit.SkinCheckButton, Kit, cb, Replace, "UI-CheckBox-Up")
	end
	cb.Refresh = function(self)
		self:SetChecked(getValue() and true or false)
	end
	cb:Refresh()
	return cb, fs
end

-- The look's switches beside the dropdowns (user, 2026-09-24: the look is
-- chosen here only): the parchment sheets (UI Modifications' keys), and the
-- layout switches of the panels that are on
local PARCHMENTS = {
	{ "parchment_tracker", "Objective Tracker" },
	{ "parchment_questTracker", "Quest Tracker" },
	{ "parchment_chat", "Chat" },
	{ "parchment_whisper", "Whisper Popup" },
	{ "parchment_meter", "Damage Meter" },
	{ "parchment_character", "Character Window" },
	{ "parchment_tooltip", "Tooltips" },
	{ "parchment_dialog", "Dialogs" },     -- (user, 2026-09-24: the popup dialogs, "add a parchment to it")   -- (user, 2026-09-24: "Tooltip Parchment Option")
}
MelloUI.ParchmentAreas = PARCHMENTS   -- (read only: the installer's Fresh start lists the same areas, one list)
local LAYOUT = {
	{ module = "ActionBarPanel", key = "hidePageArrows", label = "Action bars: hide the page arrows" },
	{ module = "MinimapPanel", key = "servicesMerge", label = "Square minimap: merge with the Services bar" },
}

-- The overview laid a few milliseconds a frame (user, 2026-09-24: the
-- Dynamic UI button took 44 ms in one frame): the laying runs as a coroutine
-- that stops between two rows once the frame's time is spent (`deadline`,
-- a debugprofilestop time) and goes on in the next.
local STEP_BUDGET = 3   -- ms of the picker's start a frame (one row or one window past it at most: under the 5 ms of a slow call)
local Now = debugprofilestop or function() return 0 end
local deadline = nil
local function Pause()
	if deadline and Now() >= deadline then
		coroutine.yield()
	end
end

-- What the overview offers this start, read once: the groups of the panels
-- that are on and the layout switches of those that are on, and its
-- signature -- the same panels, groups and choices as a start before find
-- the content laid then (kept, one per signature), where every start laid
-- a new one before
local function Offer()
	local groups, layout, parts = {}, {}, {}
	for _, m in ipairs(Providers()) do
		parts[#parts + 1] = m.name
		for _, g in ipairs(m:PickerGroups()) do
			groups[#groups + 1] = { m = m, g = g }
			parts[#parts + 1] = tostring(g.id) .. "=" .. tostring(g.title)
			for _, sct in ipairs(g.sections or {}) do
				parts[#parts + 1] = tostring(sct.module) .. ":" .. tostring(sct.key) .. ":" .. tostring(sct.title)
				for _, c in ipairs(sct.choices or {}) do
					parts[#parts + 1] = tostring(c.value) .. "=" .. tostring(c.label)
				end
			end
		end
	end
	for _, entry in ipairs(LAYOUT) do
		local m = MelloUI:GetModule(entry.module)
		if m and m.isEnabled then
			layout[#layout + 1] = entry
			parts[#parts + 1] = entry.module .. "." .. entry.key
		end
	end
	return { groups = groups, layout = layout }, table.concat(parts, "|")
end

-- The panel's rows: the borders and parchment on the left, the backgrounds
-- and the layout switches on the right, on `body` (the popup's content for
-- this offer); run as the laying coroutine
local function FillOverview(f, body, offer)
	local stripes = { left = {}, right = {} }
	local function Heading(text, x, y)
		local fs = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetPoint("TOPLEFT", x, y)
		fs:SetText(text)
		if PAL and PAL.selectedTrim then
			fs:SetTextColor(PAL.selectedTrim[1], PAL.selectedTrim[2], PAL.selectedTrim[3])
		end
		return fs
	end
	local function Row(label, x, y, getValue, choices, onPick, side)
		local fs = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		fs:SetPoint("LEFT", body, "TOPLEFT", x, y - ROW_H / 2 + 3)
		fs:SetWidth(COL_W - DD_W - PANEL_PAD * 2 - 8)
		fs:SetJustifyH("LEFT")
		fs:SetText(label)
		if PAL and PAL.text then
			fs:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
		end
		local dd = Dropdown(body, getValue, choices, onPick)
		dd:SetPoint("TOPLEFT", x + COL_W - DD_W - PANEL_PAD * 2, y - 2)
		body.dropdowns[#body.dropdowns + 1] = dd
		local list = stripes[side]
		list[#list + 1] = y
		Pause()
		return dd
	end
	local leftPanel, rightPanel = PANEL_M, PANEL_M + COL_W + PANEL_GAP
	local left, right = leftPanel + PANEL_PAD, rightPanel + PANEL_PAD
	local top = -96
	Heading("Borders (every window)", left, top)
	local y = top - 24
	for _, k in ipairs(Kit and Kit.borderKinds or {}) do
		Row(k.name, left, y, function() return UMValue(k.key, k.default) end, k.values, function(v)
			MelloUI:NotifySettingChanged("UIModifications", k.key, v)
			MelloUI:PlayUISound("option_on")
			if f.Refresh then
				f:Refresh()
			end
		end, "left")
		y = y - ROW_H
	end
	-- the parchment sheets, two to a row
	y = y - 12
	Heading("Parchment", left, y)
	y = y - 26
	for i, entry in ipairs(PARCHMENTS) do
		local x = left + ((i - 1) % 2) * ((COL_W - PANEL_PAD * 2) / 2)
		local cb = Check(body, entry[2], function() return UMValue(entry[1], false) end, function(v)
			MelloUI:NotifySettingChanged("UIModifications", entry[1], v)
			MelloUI:PlayUISound(v and "option_on" or "option_off")
		end)
		cb:SetPoint("TOPLEFT", x, y)
		body.dropdowns[#body.dropdowns + 1] = cb
		if i % 2 == 0 then
			y = y - 28
		end
		Pause()
	end
	-- an odd count leaves the last switch alone on its row: below it too
	if #PARCHMENTS % 2 == 1 then
		y = y - 28
	end
	local leftBottom = y
	Heading("Backgrounds (or click a bar or window)", right, top)
	y = top - 24
	for _, e in ipairs(offer.groups) do
		local m, g = e.m, e.g
		for _, s in ipairs(g.sections or {}) do
			local module = s.module or m.name
			Row(g.title .. ": " .. s.title, right, y, function() return CurrentValue(module, s.key) end, s.choices, function(v)
				MelloUI:NotifySettingChanged(module, s.key, v)
				MelloUI:PlayUISound("option_on")
				if f.Refresh then
					f:Refresh()
				end
				C_Timer.After(0.15, RearmIfRunning)
			end, "right")
			y = y - ROW_H
		end
	end
	-- the layout switches of the panels that are on
	local shownLayout = false
	for _, entry in ipairs(offer.layout) do
		if not shownLayout then
			y = y - 12
			Heading("Layout", right, y)
			y = y - 26
			shownLayout = true
		end
		local cb = Check(body, entry.label, function() return CurrentValue(entry.module, entry.key) end, function(v)
			MelloUI:NotifySettingChanged(entry.module, entry.key, v)
			MelloUI:PlayUISound(v and "option_on" or "option_off")
			C_Timer.After(0.15, RearmIfRunning)
		end)
		cb:SetPoint("TOPLEFT", right, y)
		body.dropdowns[#body.dropdowns + 1] = cb
		y = y - 28
		Pause()
	end
	local rightBottom = y
	local bottom = math.min(leftBottom, rightBottom)
	-- the two column panels, as tall as the taller column: the kit's single
	-- rail round the palette's inner panel, the dropdown rows striped
	local panelTop = top + 12
	for _, col in ipairs({ { x = leftPanel, rows = stripes.left }, { x = rightPanel, rows = stripes.right } }) do
		local panel = CreateFrame("Frame", nil, body)
		panel:SetFrameLevel(f:GetFrameLevel() + 2)
		panel:SetPoint("TOPLEFT", f, "TOPLEFT", col.x, panelTop)
		panel:SetSize(COL_W, panelTop - bottom + 6)
		panel:EnableMouse(false)
		local anchor = panel:CreateTexture(nil, "BACKGROUND")
		anchor:SetAllPoints()
		anchor:SetColorTexture(0, 0, 0, 0)
		Replace(anchor, { as = "Professions-background-summarylist", rect = panel, parent = panel, level = -1 })
		-- (the L1 box lays the palette's inner panel over its stone itself:
		-- its rule's `dim`, WINDOW-RULES 2e)
		for i, ry in ipairs(col.rows) do
			if i % 2 == 1 then
				local band = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
				band:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, ry - panelTop)
				band:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, ry - panelTop)
				band:SetHeight(ROW_H)
				band:SetColorTexture(PAL.mainWindow[1], PAL.mainWindow[2], PAL.mainWindow[3], 0.85)
			end
		end
		Pause()
	end
	body.height = -bottom + 64
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
	text:SetText("The look of the whole reskin in one place. The borders and colours go on every window at once; "
		.. "for the backgrounds, move the mouse over your action bars, micro menu, bag bar, bags, character window, "
		.. "minimap or an open professions window and click it to pick with pictures.")
	if PAL and PAL.text then
		text:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])   -- on the dark panel (Framed), in the palette's text colour
	end
	local done = Button(f, "Done", 100)
	done:SetPoint("BOTTOM", 0, 16)
	Perf.SetScript(done, "OnClick", function() D:Stop() end)
	f.Refresh = function(self)
		for _, dd in ipairs(self.dropdowns or {}) do
			dd:Refresh()
		end
	end
	-- hidden before it listens: its first Hide would end the picker it opens for
	f:Hide()
	-- Escape closes it (and with it the picker)
	tinsert(UISpecialFrames, "MelloUIDynamicUIPopup")
	Perf.SetScript(f, "OnHide", function()
		if running then
			D:Stop()
		end
	end)
	return f
end

--------------------------------------------------------------------------------
-- Start / stop
--------------------------------------------------------------------------------

-- A start in steps, one a frame (user, 2026-09-24: 44 ms in the click's
-- frame): the configurator closes and the world darkens at once; the
-- overview is laid (or found laid) and the popup shows once it is whole;
-- then each window the picker opens (the bags, the character window) in a
-- frame of its own, the catchers placed on them after the last and again
-- once they have laid themselves out. A Stop (Done, Escape, a fight) ends
-- the steps where they are; a half-laid overview goes on at the next start.
local bodies = {}     -- offer signature -> the popup's content for it
local starting = nil  -- the start under way: { body, offer, sig, opening = { providers }, n, shown, t0 }

-- every window open: the catchers on them, and again once they have laid
-- themselves out
local function StartDone()
	ArmCatchers()
	C_Timer.After(0.2, RearmIfRunning)
	return true
end

-- this frame's step of the start; true when it is complete
local function Advance(st)
	local body = st.body
	local laying = rawget(body, "laying")   -- (fields of our own, never a method)
	if laying then
		local ok, err = coroutine.resume(laying, popup, body, st.offer)
		if not ok then
			body.laying = nil
			bodies[st.sig] = nil
			body:Hide()
			error(err, 0)
		end
		if coroutine.status(laying) ~= "dead" then
			return false
		end
		body.laying = nil
	end
	-- (the catchers once, when every window is open, in this frame when its
	-- time is not spent, else in the next: each placing lays out the bars'
	-- backdrops whole for every group it outlines)
	if not st.shown then
		st.shown = true
		popup:SetHeight(rawget(body, "height"))
		if st.reused then
			popup:Refresh()   -- the overview's dropdowns show the settings as they are now
		end
		popup:Show()
		if st.opening[1] ~= nil or Now() >= deadline then
			return false
		end
		return StartDone()
	end
	local m = st.opening[st.n]
	if m then
		st.n = st.n + 1
		pcall(m.PickerStart, m)
		if st.opening[st.n] ~= nil or Now() >= deadline then
			return false
		end
	end
	return StartDone()
end

local function Step()
	local st = starting
	if not (st and running) then
		return
	end
	deadline = (st.t0 or Now()) + STEP_BUDGET
	st.t0 = nil
	local ok, done = pcall(Advance, st)
	deadline = nil
	if not ok then
		-- the picker ended, not left half-started under its veil
		starting = nil
		D:Stop()
		error(done, 0)
	end
	if done then
		starting = nil
	else
		C_Timer.After(0, Step)
	end
end

-- The picker's look switch: Kit:IsOn('dynamicui'), the reskin (the one
-- answer every own window asks, audit 2026-09-24 rank 1; it read UI
-- Modifications' reskin setting itself, and only when it opened)
local LOOK_OWNER = "Dynamic UI picker"

local function LookOn()
	return (Kit and Kit.IsOn and Kit:IsOn("dynamicui")) and true or false
end

-- While it is open it follows that switch (the bus's 'look:dynamicui', the
-- frame after a change): the look is the reskin's, so with the reskin gone
-- (a profile, a slash command, UI Modifications switched off) the picker
-- ends rather than stay over bars that no longer wear what it picks
local function LookFollows(on)
	if running and not on then
		D:Stop()
		MelloUI:Print("Dynamic UI Modification ended: the reskin is off.")
	end
end

function D:Start()
	if running then
		return
	end
	if InCombatLockdown() then
		MelloUI:Print("Dynamic UI Modification: not in combat.")
		return
	end
	-- the look is the reskin's: nothing to show without it (any one area is
	-- enough; the action bars are no longer needed)
	if not LookOn() then
		MelloUI:Print("Dynamic UI Modification: the reskin is off (UI Modifications, General, Painted kit reskin).")
		return
	end
	local t0 = Now()
	local config = _G.MelloUIConfigFrame
	if config and config:IsShown() then
		config:Hide()
	end
	running = true
	MelloUI:On("look:dynamicui", LookFollows, LOOK_OWNER)
	ShowVeil(true)
	popup = popup or BuildPopup()
	-- the content for what is on offer: laid before for the same offer, or
	-- laid now (a new frame of our own, hidden with the popup)
	local offer, sig = Offer()
	local body = bodies[sig]
	-- (one laid before, whole or half: a start stopped while it was being
	-- laid left rows showing the settings as they were then)
	local reused = body ~= nil
	if not body then
		body = CreateFrame("Frame", nil, popup)
		body:SetAllPoints()
		-- the text and controls over the column panels (which sit over the
		-- popup's own stone)
		body:SetFrameLevel(popup:GetFrameLevel() + 4)
		body.dropdowns = {}
		body.laying = coroutine.create(FillOverview)
		bodies[sig] = body
	end
	for _, other in pairs(bodies) do
		if other ~= body then
			other:Hide()
		end
	end
	body:Show()
	popup.dropdowns = body.dropdowns
	-- the windows the picker opens (PickerStart), a frame each
	local opening = {}
	for _, m in ipairs(Providers()) do
		if m.PickerStart then
			opening[#opening + 1] = m
		end
	end
	starting = { body = body, offer = offer, sig = sig, opening = opening, n = 1, t0 = t0, reused = reused }
	MelloUI:PlayUISound("menu_open")
	Step()
end

function D:Stop()
	if not running then
		return
	end
	running = false
	starting = nil
	MelloUI:Off(LOOK_OWNER, "look:dynamicui")
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
	MelloUI:PlayUISound("menu_close")
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
Perf.SetScript(events, "OnEvent", function()
	if running then
		D:Stop()
		MelloUI:Print("Dynamic UI Modification ended: combat.")
	end
end)

-- The UI Scale changed while the picker runs (user, 2026-09-24: "UI Scaling
-- Break the UI"): the catchers were placed from the groups' outlines in
-- screen px at the old scale, and hung off the bars they should cover; they
-- are measured and placed again (the kit's watcher calls this a moment
-- after the change, the backdrops laid out by then)
if Kit and Kit.OnUIScaleChanged then
	Kit:OnUIScaleChanged(function()
		if running then
			ArmCatchers()
			-- the backdrops re-lay themselves a beat after the kit's watcher
			C_Timer.After(0.2, function()
				if running then
					ArmCatchers()
				end
			end)
		end
	end)
end
