--------------------------------------------------------------------------------
-- MelloUI - Group Frames: the spell groups' page (1.2.4, from the user's
-- retail copy: the picked sketch B, 2026-10-24, "Build layout B (tray +
-- rows)"; docs/plans/forever-preview-update.md phase 2)
--
-- The Designer's Indicators canvas, under the designer stage (your frame,
-- pinned on top):
--   the tray   your class's spell groups as cards -- yours, everyone's, the
--              debuffs -- and your single spells; drag a card onto the frame on
--              the stage and the group lands on the nearest of its nine spots
--              (a placed one moves there); a click opens its block
--   the block  the picked one: its spells as rows (a switch each, its picture,
--              its name; everyone's by class),
--              a spell typed in, the group's look, place, grow, how many show,
--              per line, room, whose, order, when, its time and stacks, its
--              colour (your order: a spell's own, its swatch picked in its row)
-- Drag a spell's row onto another group's card: moved there. Onto another row:
-- your order. Onto the frame: a single spell of its own there (today's
-- indicator). Made with the page (the Configurator's first open of it), never
-- at login; nothing moves while no drag is under way.
--   Page.BuildGroups(canvas, width)
--   Page.SampleGroup(f, m, ind, frac, fill), Page.HideItems(m)   the stage's
--              and the fake raid's made-up members of a group
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local SG = ns.SpellGroups
local Page = ns.Page
if not (SG and Page) then
	return
end
local W = MelloUI.Widgets
local RD = ns.RD
local Looks = ns.Looks
local Label, Box, Choices, Spots = Page.Label, Page.Box, Page.Choices, Page.Spots

local EMPTY = {}

local TEXT = {
	title = "Spell groups for %s: drag one onto your frame",
	sections = { own = "Yours", all = "Everyone's", debuff = "Debuffs", single = "Single spells" },
	spells = "Spells (%d of %d on)",
	kinds = "Kinds",
	none = "Pick a group in the tray, or drag one onto your frame.",
	unplaced = "Not on the frame yet: drag its card onto the frame, or put it on.",
	reset = "Reset group", resetTip = "Every spell back as it started: switched, moved, added and your order.",
	off = "Off the frame", on = "Onto the frame", remove = "Remove",
	spellHint = "Spell name or ID", add = "+ Add", single = "+ Spell",
	noSpell = "No spell of that name: type it as the game writes it, or its spell ID.",
	look = "Look", size = "Size", spot = "Place", offset = "X / Y", grow = "Grow", most = "Most shown",
	perLine = "Per line", spacing = "Room", whose = "Whose", which = "Which", order = "Order", when = "When",
	time = "Its time", stacks = "Its stacks", colour = "Colour", colourOf = "Colour: %s", strength = "Strength",
	colourBy = "Colour from",
	hidden = "The game hides this one on others: it cannot show here.",
	startsOff = "Off from the start: a lockout of your own.",
	moveTip = "Drag it onto another group's card to move it there, onto another row for your order, onto the frame for a spell of its own.",
	added = "Added by you",
	more = "+%d more",
	show = "Show the fake raid on screen", showParty = "Show the fake party on screen",
	showTip = "Made-up members where your frames stand, your groups on them, until the preview ends. Out of combat only.",
	copy = "Copy from a spec",
}
local LOOKS = { { value = "icon", label = "Icon" }, { value = "drain", label = "Drain" }, { value = "square", label = "Square" },
	{ value = "bar", label = "Bar" }, { value = "health", label = "Health" } }
local GROW = { { value = "RIGHT", label = "Right" }, { value = "LEFT", label = "Left" }, { value = "UP", label = "Up" },
	{ value = "DOWN", label = "Down" } }
local WHOSE = { { value = "mine", label = "Yours only" }, { value = "any", label = "Anyone's" } }
local WHEN = { { value = "always", label = "Always" }, { value = "combat", label = "In a fight" } }
local COLOUR_BY = { { value = "type", label = "Its type's colour" }, { value = "mine", label = "My colour" } }

-- the page's measures (the canvas: GroupFrames.lua's height, 900)
local G = { pad = 10, gap = 8, trayH = 300, cardW = 128, cardH = 40, cardGap = 6, secW = 84, line = 46, rowH = 22,
	rows = 9, labelW = 84, wheel = 90, icons = 5, drag = 6 }
G.blockH = 900 - G.trayH - G.gap - G.gap - 30
-- (Suggestion 1 point 1, layout C: the designer's rows in the column beside the stage, ~360 wide) narrower than
-- stackW the tray's section names stand over their cards, two wider cards a line (their names whole), and the block's
-- settings come under its spells and colour (its buttons under its heading): the canvas as tall as that needs
G.stackW, G.labelLine, G.blockStackH, G.stackTop = 560, 20, 850, 92

-- the page's measures at `width`: the tray's height, the block's, whether it stacks, cards a line, a card's width,
-- the section names' column (0: over the cards), the tray's first line
function Page.Measures(width)
	local narrow = width < G.stackW
	local secW = narrow and 0 or G.secW
	local cardW = narrow and math.floor((width - 2 * G.pad - G.cardGap) / 2) or G.cardW
	local perLine = math.max(1, math.floor((width - 2 * G.pad - secW + G.cardGap) / (cardW + G.cardGap)))
	local count = { own = 0, all = 0, debuff = 0 }
	for _, d in ipairs(SG.DEFS) do
		if count[d.scope] then
			count[d.scope] = count[d.scope] + 1
		end
	end
	local first = narrow and G.pad + 40 or G.pad + 24
	local y = first
	for _, s in ipairs({ "own", "all", "debuff", "single" }) do
		local lines = s == "single" and 1 or math.max(1, math.ceil(count[s] / perLine))
		y = y + (narrow and G.labelLine or 0) + lines * G.line
	end
	local trayH = math.max(G.trayH, y + G.pad)
	return trayH, narrow and G.blockStackH or G.blockH, narrow, perLine, cardW, secW, first
end

-- the canvas's height at `width` (GroupFrames.lua's Designer row: Config.lua's RowH asks it)
function Page.Height(width)
	local trayH, blockH = Page.Measures(width)
	return trayH + G.gap + blockH + G.gap + 30
end

local function ShowEdges(edges, on)
	for _, e in ipairs(edges) do
		e:SetShown(on)
	end
end

-- a control shown or put away: a widget, or a row of choice buttons (Page.Choices, Page.Spots: their buttons)
local function ShowControl(c, on)
	if c.SetShown then
		c:SetShown(on)
	elseif c.buttons then
		for _, b in ipairs(c.buttons) do
			b:SetShown(on)
		end
	end
end

--------------------------------------------------------------------------------
-- The made-up members of a group on a sample (the stage, the fake raid):
-- its first spells switched on, laid its way (Looks.Block); nothing read
--------------------------------------------------------------------------------

local FRACS = { 0.8, 0.55, 0.3, 0.7, 0.45, 0.2 }
local at = {}

local function ItemOf(m, i)
	m.items = m.items or {}
	local it = m.items[i]
	if not it then
		local b = CreateFrame("Frame", nil, m.b)
		it = { b = b, p = Looks.Make(b) }
		-- (the item's look as its group's, its spell its own)
		it.proxy = setmetatable({}, { __index = function(_, k)
			return it.ind and it.ind[k]
		end })
		m.items[i] = it
	end
	return it
end

function Page.HideItems(m)
	for _, it in ipairs(m.items or EMPTY) do
		it.b:Hide()
	end
end

function Page.SampleGroup(f, m, ind, frac, fill)
	Looks.HideAll(m.p)
	local shown = {}
	local most = ind.look == "health" and 1 or (ind.max or 3)
	for _, e in ipairs(SG.List(ind)) do
		if #shown < most and SG.IsOn(ind, e) and SG.Trackable(ind, e) then
			shown[#shown + 1] = e
		end
	end
	local n = math.max(1, #shown)
	local iw, ih = ind.size or 10, ind.size or 10
	if ind.look == "bar" then
		iw = math.max(1, ((tonumber(f:GetWidth()) or 72) - 2) * math.max(0.1, math.min(1, ind.length or 1)))
	end
	local bw, bh, pos = Looks.Block(ind, n, iw, ih, at)
	local pin, pinX, pinY = Looks.Pin(ind, iw, ih)
	m.b:ClearAllPoints()
	m.b:SetSize(math.max(1, bw), math.max(1, bh))
	m.b:SetPoint(pin, f, ind.point or "TOPRIGHT", pinX, pinY)
	local health = ind.look == "health"
	for i = 1, n do
		local it = ItemOf(m, i)
		local e = shown[i]
		it.ind = ind
		local px = it.proxy
		if e and e.kind then
			px.kind, px.what, px.spell = "debuff", e.kind, nil
		else
			px.kind, px.what, px.spell = "buff", nil, e and e.main or nil
		end
		Looks.ParentLevel(it.b, health)
		it.p.tint:SetDrawLayer(health and "BORDER" or "OVERLAY", health and 4 or 0)
		Looks.Lay(it.b, it.p, ind, f, fill, true, SG.ColourOf(ind, e))
		if not health then
			it.b:ClearAllPoints()
			it.b:SetPoint("TOPLEFT", m.b, "TOPLEFT", pos[i][1], -pos[i][2])
		end
		-- (each member its own made-up time left, round the sample's)
		Looks.Sample(it.b, it.p, px, math.min(1, FRACS[(i - 1) % #FRACS + 1] * (0.5 + (frac or 0.6))))
		it.b:SetAlpha(e and 1 or 0.5)
	end
	for i = n + 1, #(m.items or EMPTY) do
		m.items[i].b:Hide()
	end
end

--------------------------------------------------------------------------------
-- Dragging: a card or a row under the cursor, its ghost following it (an
-- OnUpdate only while the button is held), dropped onto the stage's frame, a
-- card or a row
--------------------------------------------------------------------------------

local drag = { what = nil }
local ghost = nil

local function Cursor()
	local x, y = GetCursorPosition()
	return x or 0, y or 0
end

local function GhostAtCursor(self)
	local x, y = Cursor()
	if not drag.on then
		if math.abs(x - drag.x0) + math.abs(y - drag.y0) < G.drag * (UIParent:GetEffectiveScale() or 1) then
			return
		end
		drag.on = true
		self:SetAlpha(1)
	end
	local s = UIParent:GetEffectiveScale() or 1
	self:ClearAllPoints()
	self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / s + 14, y / s)
end

local function Ghost()
	if not ghost then
		ghost = CreateFrame("Frame", nil, UIParent)
		ghost:SetFrameStrata("TOOLTIP")
		ghost:SetSize(170, 26)
		W.Panel(ghost, { on = true })
		ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
		ghost.icon:SetSize(18, 18)
		ghost.icon:SetPoint("LEFT", ghost, "LEFT", 4, 0)
		ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		ghost.text = Label(ghost, "", "text", "GameFontHighlight")
		ghost.text:SetPoint("LEFT", ghost.icon, "RIGHT", 6, 0)
		ghost.text:SetPoint("RIGHT", ghost, "RIGHT", -6, 0)
		ghost.text:SetWordWrap(false)
		ghost:Hide()
	end
	return ghost
end

local function BeginDrag(what, label, icon)
	local x, y = Cursor()
	drag.what, drag.x0, drag.y0, drag.on = what, x, y, false
	local g = Ghost()
	g.text:SetText(label or "")
	g.icon:SetTexture(icon or Looks.UNKNOWN_ICON)
	g:SetAlpha(0)
	g:Show()
	g:SetScript("OnUpdate", GhostAtCursor)
end

-- the drag let go: what it was, and whether it moved at all (else a click)
local function EndDrag()
	local what, moved = drag.what, drag.on
	drag.what, drag.on = nil, false
	if ghost then
		ghost:SetScript("OnUpdate", nil)
		ghost:Hide()
	end
	return what, moved
end

-- the spot of `f` nearest the cursor (nil: the cursor not over it)
local function SpotUnder(f, pad)
	if not (f and f:IsVisible()) then
		return nil
	end
	local x, y = Cursor()
	local s = f:GetEffectiveScale() or 1
	x, y = x / s, y / s
	local l, r, b, t = f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop()
	if not (l and r and b and t) then
		return nil
	end
	pad = pad or 0
	if x < l - pad or x > r + pad or y < b - pad or y > t + pad then
		return nil
	end
	local best, bd = nil, nil
	for _, p in ipairs(RD.POINTS) do
		local px, py = l + Looks.FX[p] * (r - l), t - Looks.FY[p] * (t - b)
		local d = (px - x) ^ 2 + (py - y) ^ 2
		if not bd or d < bd then
			best, bd = p, d
		end
	end
	return best
end

local function Tip(frame, title, body)
	frame:HookScript("OnEnter", function(self)
		W.ShowTooltip(self, title, body)
	end)
	frame:HookScript("OnLeave", W.TipLeave)
end

local function TypedBox(parent, width, onEnter)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box:SetFontObject("MelloUIFont_GameFontHighlightSmall")
	box:SetTextInsets(4, 4, 0, 0)
	W.FlatField(box)
	local hint = Label(box, TEXT.spellHint, "text")
	hint:SetPoint("LEFT", box, "LEFT", 4, 0)
	box:SetScript("OnTextChanged", function(self)
		hint:SetShown(self:GetText() == "")
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", onEnter)
	return box
end

-- a list's class as the tray names it, and its talents' (the list is your talents': RD:Spec)
local function Owner(spec)
	local _, label = RD:Spec()
	local class = SG.ClassName(SG.SpecOf(spec))
	return label and (class .. " (" .. label .. ")") or class
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

function Page.BuildGroups(canvas, width)
	local row = canvas:GetParent()
	local sec = row and row:GetParent()
	local tab = type(sec) == "table" and rawget(sec, "name")
	local inst = { canvas = canvas, el = (type(tab) == "string" and tab:match("^party:")) and "party" or "raid",
		spec = RD:Spec(), virtual = {}, width = width }
	inst.kind = Page.KindOf(inst)
	Page.canvases[canvas] = inst
	local function Key()
		return RD:KeyOf(nil, inst.kind)   -- (Suggestion 1, point 3: the layout every character shares)
	end
	local function List()
		return RD:List(Key())
	end
	local function Changed(ind)
		RD:Changed(ind, Key())
	end
	-- the placed group of a key (nil: not on the frame)
	local function PlacedOf(key)
		for _, ind in ipairs(List()) do
			if ind.kind == "group" and ind.group == key then
				return ind
			end
		end
		return nil
	end
	local function FreeSpot()
		local used = {}
		for _, ind in ipairs(List()) do
			used[ind.point or ""] = true
		end
		for _, p in ipairs(RD.POINTS) do
			if not used[p] then
				return p
			end
		end
		return "CENTER"
	end
	-- the one picked: a placed indicator (inst.ind) or a group not on the frame (inst.group)
	function inst.Pick(ind)
		inst.ind, inst.group, inst.colourSpell = ind, nil, nil
		canvas:Refresh()
		local CP = MelloUI.ConfigPreview
		local stage = CP and CP.Shown and CP.Shown("raidframe")
		if stage and ind and Page.ListKind(stage.pick) == inst.kind and not Page.syncing then
			Page.syncing = true
			stage:Select("ind:" .. tostring(ind.id))
			Page.syncing = nil
		end
	end
	local function PickGroup(key)
		local ind = PlacedOf(key)
		if ind then
			inst.Pick(ind)
		else
			inst.ind, inst.group, inst.colourSpell = nil, key, nil
			canvas:Refresh()
		end
	end
	-- a group put on the frame at a spot (a placed one moved there)
	local function Place(key, spot)
		local ind = PlacedOf(key)
		if ind then
			ind.point, ind.x, ind.y = spot, 0, 0
			Changed(ind)
		else
			ind = RD:Add(SG.New(key, spot), Key())
		end
		MelloUI:PlayUISound("tab")
		inst.Pick(ind)
		return ind
	end
	local function Sample()
		local CP = MelloUI.ConfigPreview
		local stage = CP and CP.Shown and CP.Shown("raidframe")
		if stage and Page.ListKind(stage.pick) == inst.kind then
			return Page.samples[stage.pick]
		end
		return nil
	end
	local Refresh   -- (below)

	------------------------------------------------------------------ the tray
	-- (layout C: narrow, the section names over their cards, two wider cards a line, the title wrapping beside the
	-- copy menu -- Page.Measures)
	local trayH, blockH, narrow, perLine, cardW, secW, firstY = Page.Measures(width)
	local tray = Box(canvas, 0, 0, width, trayH)
	local title = Label(tray, "", "selectedTrim", "GameFontNormal")
	title:SetPoint("TOPLEFT", tray, "TOPLEFT", G.pad, -G.pad)
	local copy = W.Dropdown(tray, 150, function() return nil end, function(value)
		if value ~= Key() then
			RD:CopyFrom(value, Key())
			inst.ind, inst.group = nil, nil
			canvas:Refresh()
		end
	end, RD:SpecValues(), { default = TEXT.copy })
	copy:SetPoint("TOPRIGHT", tray, "TOPRIGHT", -G.pad, -6)
	if narrow then
		title:SetPoint("RIGHT", copy, "LEFT", -8, 0)
		title:SetJustifyH("LEFT")
		title:SetWordWrap(true)
	end
	local SECTIONS = { "own", "all", "debuff", "single" }
	local secLabel = {}
	for _, s in ipairs(SECTIONS) do
		secLabel[s] = Label(tray, TEXT.sections[s], "text", "GameFontHighlight")
	end
	local cards = {}
	local more = Label(tray, "", "text", "GameFontHighlightSmall")

	local function Card(i)
		local c = cards[i]
		if c then
			return c
		end
		c = CreateFrame("Button", nil, tray)
		c:SetSize(cardW, G.cardH)
		c.fill = W.Solid(c, "BACKGROUND", "raisedPanel", 1)
		c.fill:SetAllPoints(c)
		c.hover = W.Solid(c, "BORDER", "hover", 0.8)
		c.hover:SetAllPoints(c)
		c.hover:Hide()
		c.edge = W.Edges(c, "border", "OVERLAY")
		c.placed = W.Edges(c, "trim", "OVERLAY")
		c.sel = W.Edges(c, "selectedTrim", "OVERLAY")
		c.title = Label(c, "", "text", "GameFontHighlight")
		c.title:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -4)
		c.title:SetPoint("RIGHT", c, "RIGHT", -6, 0)
		c.title:SetWordWrap(false)
		c.title:SetJustifyH("LEFT")
		c.icons = {}
		for j = 1, G.icons do
			local t = c:CreateTexture(nil, "ARTWORK")
			t:SetSize(14, 14)
			t:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 6 + (j - 1) * 15, 5)
			t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			c.icons[j] = t
		end
		c.count = Label(c, "", "text", "GameFontHighlightSmall")
		c.count:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -6, 5)
		c:SetScript("OnEnter", function(self)
			self.hover:Show()
			W.ShowTooltip(self, self.label, self.tip)
		end)
		c:SetScript("OnLeave", function(self)
			self.hover:Hide()
			W.TipLeave(self)
		end)
		c:SetScript("OnMouseDown", function(self, button)
			if button == "LeftButton" then
				BeginDrag({ type = self.group and "group" or "single", key = self.group, ind = self.ind },
					self.label, self.icons[1]:GetTexture())
			end
		end)
		c:SetScript("OnMouseUp", function(self)
			local what, moved = EndDrag()
			if not what then
				return
			end
			if not moved then
				MelloUI:PlayUISound("tab")
				if self.group then
					PickGroup(self.group)
				else
					inst.Pick(self.ind)
				end
				return
			end
			local spot = SpotUnder(Sample(), 12)
			if spot and what.type == "group" then
				Place(what.key, spot)
			elseif spot and what.ind then
				what.ind.point, what.ind.x, what.ind.y = spot, 0, 0
				Changed(what.ind)
				inst.Pick(what.ind)
			end
		end)
		cards[i] = c
		return c
	end

	-- a card's face: its title, the first pictures of its spells, how many are on
	local function FillCard(c, key, ind)
		c.group, c.ind = key, ind
		local placed = key and PlacedOf(key) or ind
		local list, on = {}, 0
		if key then
			local src = placed or inst.virtual
			if not placed then
				wipe(inst.virtual)
				inst.virtual.group = key
			end
			list = SG.List(src, inst.spec)
			for _, e in ipairs(list) do
				if SG.IsOn(src, e) then
					on = on + 1
				end
			end
			c.label = SG.DEF[key].label
			c.tip = SG.DEF[key].tip
		else
			c.label = Page.Name(ind)
			c.tip = nil
		end
		c.title:SetText(c.label)
		local n = 0
		for _, e in ipairs(list) do
			if n < G.icons then
				n = n + 1
				c.icons[n]:SetTexture(e.kind and Looks.KIND_ICON[e.kind] or SG.Icon(e) or Looks.UNKNOWN_ICON)
				c.icons[n]:Show()
			end
		end
		if not key then
			n = 1
			c.icons[1]:SetTexture(ind.kind == "buff" and (RD:SpellIcon(ind) or Looks.UNKNOWN_ICON) or Looks.KIND_ICON[ind.what]
				or Looks.KIND_ICON.Magic)
			c.icons[1]:Show()
		end
		for j = n + 1, G.icons do
			c.icons[j]:Hide()
		end
		c.count:SetText(key and (SG.DEF[key].scope == "debuff" and "" or (on .. " / " .. #list)) or (RD.LOOK[ind.look] or RD.LOOKS[1]).label)
		ShowEdges(c.placed, placed ~= nil and placed ~= inst.ind)
		ShowEdges(c.sel, (placed ~= nil and placed == inst.ind) or (key ~= nil and key == inst.group))
		ShowEdges(c.edge, true)
	end

	-- the typed single spell (today's indicator: one spell, its own spot)
	local single
	local function AddSingle()
		local id, name = RD:Resolve(single:GetText())
		if not (id or name) then
			return
		end
		local ind = RD:Add({ kind = "buff", spell = id, name = name, look = "icon", point = FreeSpot() }, Key())
		single:SetText("")
		single:ClearFocus()
		MelloUI:Print(RD.TEXT.added, Page.Name(ind))
		inst.Pick(ind)
	end
	single = TypedBox(tray, 110, AddSingle)
	local singleAdd = W.Button(tray, TEXT.single, 56, nil, { height = 20 })
	singleAdd:SetPoint("LEFT", single, "RIGHT", 4, 0)
	singleAdd:HookScript("OnClick", AddSingle)

	local function LayTray()
		title:SetText(string.format(TEXT.title, Owner(inst.spec)))
		local class = SG.SpecOf(inst.spec)
		local groups = { own = {}, all = {}, debuff = {}, single = {} }
		for _, d in ipairs(SG.DEFS) do
			-- (a group with no spell of the data, yours or everyone's: left out, unless it is on the frame)
			if d.scope == "debuff" or #SG.Entries(d.key, class) > 0 or PlacedOf(d.key) then
				local t = groups[d.scope]
				t[#t + 1] = { key = d.key }
			end
		end
		for _, ind in ipairs(List()) do
			if ind.kind ~= "group" then
				groups.single[#groups.single + 1] = { ind = ind }
			end
		end
		local y, n = firstY, 0
		more:Hide()
		for _, s in ipairs(SECTIONS) do
			local items = groups[s]
			secLabel[s]:ClearAllPoints()
			if narrow then
				-- (the section's name over its cards)
				secLabel[s]:SetPoint("TOPLEFT", tray, "TOPLEFT", G.pad, -y)
				y = y + G.labelLine
			else
				secLabel[s]:SetPoint("TOPLEFT", tray, "TOPLEFT", G.pad, -(y + 12))
			end
			local lines = math.max(1, math.ceil((#items + (s == "single" and 1 or 0)) / perLine))
			if s == "single" then
				lines = 1   -- (one line: the rest counted)
			end
			for j, item in ipairs(items) do
				local line, col = math.floor((j - 1) / perLine), (j - 1) % perLine
				if line < lines and not (s == "single" and j >= perLine) then
					n = n + 1
					local c = Card(n)
					c:ClearAllPoints()
					c:SetPoint("TOPLEFT", tray, "TOPLEFT", G.pad + secW + col * (cardW + G.cardGap), -(y + line * G.line))
					FillCard(c, item.key, item.ind)
					c:Show()
				elseif s == "single" then
					more:SetText(string.format(TEXT.more, #items - perLine + 1))
					more:ClearAllPoints()
					if narrow then
						more:SetPoint("LEFT", secLabel[s], "RIGHT", 8, 0)
					else
						more:SetPoint("TOPLEFT", secLabel[s], "BOTTOMLEFT", 0, -4)
					end
					more:Show()
				end
			end
			if s == "single" then
				-- (the typed spell's box after the single spells)
				local col = math.min(#items, perLine - 1)
				single:ClearAllPoints()
				single:SetPoint("TOPLEFT", tray, "TOPLEFT", G.pad + secW + col * (cardW + G.cardGap), -(y + 10))
			end
			y = y + lines * G.line
		end
		for j = n + 1, #cards do
			cards[j]:Hide()
		end
		copy:SetValues(RD:SpecValues())
	end

	------------------------------------------------------------------ the block
	local block = Box(canvas, 0, trayH + G.gap, width, blockH)
	local none = Label(block, TEXT.none, "text", "GameFontHighlight")
	none:SetPoint("CENTER", block, "CENTER", 0, 0)
	local body = CreateFrame("Frame", nil, block)
	body:SetAllPoints(block)
	local heading = Label(body, "", "selectedTrim", "GameFontNormalLarge")
	heading:SetPoint("TOPLEFT", body, "TOPLEFT", G.pad, -G.pad)
	local scope = Label(body, "", "text", "GameFontHighlightSmall")
	scope:SetPoint("BOTTOMLEFT", heading, "BOTTOMRIGHT", 10, 1)
	local blurb = Label(body, "", "mutedText", "GameFontHighlight")
	blurb:SetPoint("TOPLEFT", body, "TOPLEFT", G.pad, -(G.pad + 24))
	blurb:SetPoint("RIGHT", body, "RIGHT", -G.pad, 0)
	blurb:SetJustifyH("LEFT")
	blurb:SetWordWrap(false)
	local placeBtn = W.Button(body, TEXT.on, 110, nil, { height = 22 })
	local resetBtn = W.Button(body, TEXT.reset, 100, nil, { height = 22 })
	if narrow then
		-- (layout C: the buttons under the blurb, the heading's line left whole)
		placeBtn:SetPoint("TOPLEFT", body, "TOPLEFT", G.pad, -(G.pad + 46))
		resetBtn:SetPoint("LEFT", placeBtn, "RIGHT", 6, 0)
	else
		placeBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", -G.pad, -G.pad + 2)
		resetBtn:SetPoint("RIGHT", placeBtn, "LEFT", -6, 0)
	end
	Tip(resetBtn, TEXT.reset, TEXT.resetTip)

	-- (layout C, narrow: the spells across the block, the settings under them and the colour)
	local lx, lw = G.pad, narrow and (width - 2 * G.pad - 10) or math.floor(width * 0.47)
	local rx = narrow and lx or lx + lw + 22
	local top = narrow and G.stackTop or 62
	local spellsLabel = Label(body, "", "text", "GameFontHighlight")
	spellsLabel:SetPoint("TOPLEFT", body, "TOPLEFT", lx, -top)
	local unplaced = Label(body, TEXT.unplaced, "text", "GameFontHighlight")
	-- (where the settings start: beside the spells, or under the spells, the typed box and the colour -- narrow)
	local setY = narrow and (top + 20 + G.rows * G.rowH + 6 + 44 + G.wheel + 16) or top
	unplaced:SetPoint("TOPLEFT", body, "TOPLEFT", rx, -setY)
	unplaced:SetPoint("RIGHT", body, "RIGHT", -G.pad, 0)
	unplaced:SetJustifyH("LEFT")

	-- the rows: a class's heading, or a spell (its switch, picture, name; its
	-- colour's swatch in your order)
	local area = CreateFrame("Frame", nil, body)
	area:SetPoint("TOPLEFT", body, "TOPLEFT", lx, -(top + 20))
	area:SetSize(lw, G.rows * G.rowH)
	area:EnableMouseWheel(true)
	local scroll = W.ThinScrollBar(body, 6)
	scroll:SetPoint("TOPLEFT", area, "TOPRIGHT", 3, 0)
	scroll:SetPoint("BOTTOMLEFT", area, "BOTTOMRIGHT", 3, 0)
	local lines, offset = {}, 0
	local rows = {}
	local DrawRows   -- (below)

	local function Sel()
		return inst.ind or inst.virtual
	end

	local function RowTip(r)
		local e = r.e
		if not e then
			return
		end
		local body_ = {}
		if e.off then
			body_[#body_ + 1] = TEXT.startsOff
		end
		if not SG.Trackable(Sel(), e) then
			body_[#body_ + 1] = TEXT.hidden
		end
		if not e.kind and inst.ind then
			body_[#body_ + 1] = TEXT.moveTip
		end
		W.ShowTooltip(r, SG.Name(e), table.concat(body_, "\n"))
	end

	for i = 1, G.rows do
		local r = CreateFrame("Button", nil, area)
		r:SetHeight(G.rowH)
		r:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(i - 1) * G.rowH)
		r:SetPoint("RIGHT", area, "RIGHT", 0, 0)
		r.hover = W.Solid(r, "BACKGROUND", "hover", 0.6)
		r.hover:SetAllPoints(r)
		r.hover:Hide()
		r.switch = W.Switch(r, function()
			return r.e and SG.IsOn(Sel(), r.e)
		end, function(v)
			if r.e and inst.ind then
				SG.Switch(inst.ind, r.e, v)
				Changed(inst.ind)
			end
		end)
		r.switch:SetPoint("LEFT", r, "LEFT", 2, 0)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(18, 18)
		r.icon:SetPoint("LEFT", r.switch, "RIGHT", 6, 0)
		r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.swatch = CreateFrame("Button", nil, r)
		r.swatch:SetSize(18, 12)
		r.swatch:SetPoint("RIGHT", r, "RIGHT", -24, 0)
		r.swatch.fill = r.swatch:CreateTexture(nil, "ARTWORK")
		r.swatch.fill:SetAllPoints(r.swatch)
		r.swatch.edge = W.Edges(r.swatch, "border", "OVERLAY")
		r.swatch:SetScript("OnClick", function()
			if r.e then
				MelloUI:PlayUISound("tab")
				inst.colourSpell = r.e.main
				Refresh()
			end
		end)
		r.handle = r:CreateTexture(nil, "ARTWORK")
		r.handle:SetSize(12, 12)
		r.handle:SetPoint("RIGHT", r, "RIGHT", -4, 0)
		W.Glyph(r.handle, "list")
		W.Paint(r.handle, "mutedText", "fill")
		r.name = Label(r, "", "text", "GameFontHighlight")
		r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
		r.name:SetPoint("RIGHT", r.swatch, "LEFT", -6, 0)
		r.name:SetJustifyH("LEFT")
		r.name:SetWordWrap(false)
		r.head = Label(r, "", "text", "GameFontNormal")
		r.head:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
		r:SetScript("OnEnter", function(self)
			if self.e then
				self.hover:Show()
				RowTip(self)
			end
		end)
		r:SetScript("OnLeave", function(self)
			self.hover:Hide()
			W.TipLeave(self)
		end)
		r:SetScript("OnMouseWheel", function(_, d)
			area:GetScript("OnMouseWheel")(area, d)
		end)
		r:SetScript("OnMouseDown", function(self, button)
			if button == "LeftButton" and self.e and not self.e.kind and inst.ind then
				BeginDrag({ type = "spell", e = self.e, from = inst.ind }, SG.Name(self.e), self.icon:GetTexture())
			end
		end)
		r:SetScript("OnMouseUp", function(self)
			local what, moved = EndDrag()
			if not (what and moved) then
				return
			end
			local e, from = what.e, what.from
			-- onto another group's card: moved there (put on the frame if it was not)
			for _, c in ipairs(cards) do
				if c:IsShown() and c.group and c.group ~= from.group and SG.DEF[c.group].scope ~= "debuff"
					and c:IsMouseOver() then
					local to = PlacedOf(c.group) or RD:Add(SG.New(c.group, FreeSpot()), Key())
					SG.Move(from, e, to)
					Changed(from)
					Changed(to)
					MelloUI:PlayUISound("tab")
					return
				end
			end
			-- onto another row: your order
			for _, other in ipairs(rows) do
				if other:IsShown() and other.e and other.e ~= e and not other.e.kind and other:IsMouseOver() then
					SG.Rank(from, SG.List(from, inst.spec), e, other.e)
					from.order = "list"
					Changed(from)
					MelloUI:PlayUISound("tab")
					return
				end
			end
			-- onto the frame: a spell of its own there
			local spot = SpotUnder(Sample(), 12)
			if spot then
				local ind = RD:Add({ kind = "buff", spell = e.main, name = SG.Name(e), look = "icon", point = spot }, Key())
				MelloUI:PlayUISound("tab")
				inst.Pick(ind)
			end
		end)
		rows[i] = r
	end

	DrawRows = function()
		local sel = Sel()
		local own = inst.ind and inst.ind.order == "list" and (inst.ind.look == "square" or inst.ind.look == "bar")
		for i, r in ipairs(rows) do
			local line = lines[offset + i]
			r.e = line and line.e or nil
			if not line then
				r:Hide()
			elseif line.head then
				r.switch:Hide()
				r.swatch:Hide()
				r.handle:Hide()
				r.name:Hide()
				r.head:SetText(line.head)
				r.head:SetTextColor(line.r or 1, line.g or 1, line.b or 1)
				r.head:Show()
				r.icon:SetTexture(nil)
				if line.class and r.icon.SetAtlas then
					pcall(r.icon.SetAtlas, r.icon, "classicon-" .. line.class:lower())
				end
				r:Show()
			else
				local e = line.e
				r.head:Hide()
				r.switch:Show()
				r.switch:Refresh()
				r.switch:SetEnabled(inst.ind ~= nil and not e.fixed)
				r.icon:SetTexture(e.kind and Looks.KIND_ICON[e.kind] or SG.Icon(e) or Looks.UNKNOWN_ICON)
				r.name:SetText(SG.Name(e))
				r.name:Show()
				W.Paint(r.name, SG.Trackable(sel, e) and SG.IsOn(sel, e) and "text" or "mutedText", "text")
				r.handle:SetShown(inst.ind ~= nil and not e.kind)
				r.swatch:SetShown(own and not e.kind or false)
				if own and not e.kind then
					local c = SG.ColourOf(inst.ind, e)
					r.swatch.fill:SetColorTexture(c and c[1] or inst.ind.r or 1, c and c[2] or inst.ind.g or 1,
						c and c[3] or inst.ind.b or 1)
					ShowEdges(r.swatch.edge, true)
				end
				r:Show()
			end
		end
		local maxOff = math.max(0, #lines - G.rows)
		scroll:SetMinMaxValues(0, maxOff)
		scroll:SetShown(maxOff > 0)
		if scroll.thumb then
			scroll.thumb:SetHeight(math.max(12, G.rows * G.rowH * G.rows / math.max(G.rows, #lines)))
		end
	end
	area:SetScript("OnMouseWheel", function(_, d)
		local maxOff = math.max(0, #lines - G.rows)
		offset = math.max(0, math.min(maxOff, offset - d))
		scroll:SetValue(offset)
		DrawRows()
	end)
	scroll:SetScript("OnValueChanged", function(_, v)
		local o = math.floor((v or 0) + 0.5)
		if o ~= offset then
			offset = o
			DrawRows()
		end
	end)

	-- the rows' lines: the group's spells (everyone's by class, a typed one under its own heading)
	local function BuildLines(sel)
		wipe(lines)
		local list = SG.List(sel, inst.spec)
		local def = SG.DEF[sel.group]
		if def.scope ~= "all" then
			for _, e in ipairs(list) do
				lines[#lines + 1] = { e = e }
			end
			return list
		end
		local byClass, added = {}, {}
		for _, e in ipairs(list) do
			if e.class then
				byClass[e.class] = byClass[e.class] or {}
				local t = byClass[e.class]
				t[#t + 1] = e
			else
				added[#added + 1] = e
			end
		end
		for _, class in ipairs(SG.Classes()) do
			if byClass[class] then
				local r, g, b = SG.ClassColour(class)
				lines[#lines + 1] = { head = SG.ClassName(class), class = class, r = r, g = g, b = b }
				for _, e in ipairs(byClass[class]) do
					lines[#lines + 1] = { e = e }
				end
			end
		end
		if #added > 0 then
			lines[#lines + 1] = { head = TEXT.added }
			for _, e in ipairs(added) do
				lines[#lines + 1] = { e = e }
			end
		end
		return list
	end

	-- a spell typed into the group
	local typedMsg = Label(body, "", "text", "GameFontHighlightSmall")
	local typed
	local function AddTyped()
		if not inst.ind then
			return
		end
		if SG.Add(inst.ind, typed:GetText()) then
			typed:SetText("")
			typed:ClearFocus()
			typedMsg:SetText("")
			Changed(inst.ind)
		else
			typedMsg:SetText(TEXT.noSpell)
		end
	end
	local addY = top + 20 + G.rows * G.rowH + 6
	typed = TypedBox(body, 150, AddTyped)
	typed:SetPoint("TOPLEFT", body, "TOPLEFT", lx + 4, -addY)
	local typedAdd = W.Button(body, TEXT.add, 56, nil, { height = 20 })
	typedAdd:SetPoint("LEFT", typed, "RIGHT", 4, 0)
	typedAdd:HookScript("OnClick", AddTyped)
	typedMsg:SetPoint("TOPLEFT", typed, "BOTTOMLEFT", 0, -3)
	typedMsg:SetPoint("RIGHT", area, "RIGHT", 0, 0)
	typedMsg:SetJustifyH("LEFT")

	------------------------------------------------------------------ the settings
	local controls = {}
	local function Ind()
		return inst.ind or EMPTY
	end
	local function Setter(key, sub)
		return function(v)
			local ind = inst.ind
			if not ind then
				return
			end
			if sub then
				ind[sub][key] = v
			else
				ind[key] = v
			end
			Changed(ind)
		end
	end
	local function Getter(key, sub)
		return function()
			local ind = Ind()
			if sub then
				return ind[sub] and ind[sub][key]
			end
			return ind[key]
		end
	end
	local labels = {}
	local function Line(name, x, y, text)
		local l = Label(body, text, "text", "GameFontHighlight")
		l:SetPoint("TOPLEFT", body, "TOPLEFT", x, -(y + 3))
		labels[name] = l
		return l
	end
	local cx = rx + G.labelW
	local y = setY
	Line("look", rx, y, TEXT.look)
	controls.look = Choices(body, cx, y, LOOKS, 46, Getter("look"), Setter("look"))
	y = y + 28
	Line("size", rx, y, TEXT.size)
	controls.size = W.Slider(body, 170, Getter("size"), Setter("size"), { min = 1, max = RD.SIZE.max, step = 1 })
	controls.size:SetPoint("TOPLEFT", body, "TOPLEFT", cx, -y)
	y = y + 30
	Line("spot", rx, y, TEXT.spot)
	controls.spot = Spots(body, cx, y, Getter("point"), function(point)
		local ind = inst.ind
		if ind then
			ind.point, ind.x, ind.y = point, 0, 0
			Changed(ind)
		end
	end)
	controls.x = W.NumberBox(body, 44, Getter("x"), Setter("x"), { min = -60, max = 60, step = 1 })
	controls.x:SetPoint("TOPLEFT", body, "TOPLEFT", cx + 64, -y)
	controls.y = W.NumberBox(body, 44, Getter("y"), Setter("y"), { min = -60, max = 60, step = 1 })
	controls.y:SetPoint("LEFT", controls.x, "RIGHT", 6, 0)
	controls.x.melloNext = controls.y
	y = y + 54
	Line("grow", rx, y, TEXT.grow)
	controls.grow = Choices(body, cx, y, GROW, 56, Getter("grow"), Setter("grow"))
	y = y + 28
	Line("max", rx, y, TEXT.most)
	controls.max = W.Slider(body, 170, Getter("max"), Setter("max"), { min = 1, max = 10, step = 1 })
	controls.max:SetPoint("TOPLEFT", body, "TOPLEFT", cx, -y)
	y = y + 30
	Line("perLine", rx, y, TEXT.perLine)
	controls.perLine = W.Slider(body, 170, Getter("perLine"), Setter("perLine"), { min = 1, max = 10, step = 1 })
	controls.perLine:SetPoint("TOPLEFT", body, "TOPLEFT", cx, -y)
	y = y + 30
	Line("spacing", rx, y, TEXT.spacing)
	controls.spacing = W.Slider(body, 170, Getter("spacing"), Setter("spacing"), { min = 0, max = 8, step = 1 })
	controls.spacing:SetPoint("TOPLEFT", body, "TOPLEFT", cx, -y)
	y = y + 30
	Line("whose", rx, y, TEXT.whose)
	controls.whose = Choices(body, cx, y, WHOSE, 92, Getter("whose"), Setter("whose"))
	controls.which = W.Dropdown(body, 200, Getter("what"), Setter("what"), SG.DISPEL)
	controls.which:SetPoint("TOPLEFT", body, "TOPLEFT", cx, -y)
	controls.kind = W.Dropdown(body, 200, Getter("what"), Setter("what"), RD.KINDS)
	controls.kind:SetPoint("TOPLEFT", body, "TOPLEFT", cx, -y)
	y = y + 28
	Line("order", rx, y, TEXT.order)
	controls.order = Choices(body, cx, y, SG.ORDERS, 80, Getter("order"), Setter("order"))
	y = y + 28
	Line("when", rx, y, TEXT.when)
	controls.when = Choices(body, cx, y, WHEN, 80, Getter("when"), Setter("when"))
	y = y + 28
	local function TextRow(sub, name, text, yy)
		Line(name, rx, yy, text)
		local sw = W.Switch(body, Getter("show", sub), Setter("show", sub))
		sw:SetPoint("TOPLEFT", body, "TOPLEFT", cx, -yy)
		local sl = W.Slider(body, 140, Getter("size", sub), Setter("size", sub), { min = RD.SIZE.textMin, max = RD.SIZE.textMax, step = 1 })
		sl:SetPoint("TOPLEFT", body, "TOPLEFT", cx + 34, -yy)
		controls[sub .. "Show"], controls[sub .. "Size"] = sw, sl
	end
	TextRow("text", "time", TEXT.time, y)
	y = y + 28
	TextRow("count", "stacks", TEXT.stacks, y)

	-- the colour (left, under the spells): the group's, or in your order the spell picked by its swatch
	local cy = addY + 44
	local colourLabel = Label(body, TEXT.colour, "text", "GameFontHighlight")
	colourLabel:SetPoint("TOPLEFT", body, "TOPLEFT", lx, -cy)
	controls.wheel = W.ColorWheel(body, G.wheel, function()
		local ind = Ind()
		local c = inst.colourSpell and ind.colours and ind.colours[inst.colourSpell]
		if c then
			return c[1], c[2], c[3]
		end
		return ind.r or 1, ind.g or 1, ind.b or 1
	end, function(r, g, b)
		local ind = inst.ind
		if not ind then
			return
		end
		if inst.colourSpell and ind.order == "list" then
			ind.colours = ind.colours or {}
			ind.colours[inst.colourSpell] = { r, g, b }
		else
			ind.r, ind.g, ind.b = r, g, b
		end
		Changed(ind)
	end)
	controls.wheel:SetPoint("TOPLEFT", body, "TOPLEFT", lx + G.labelW, -cy)
	local byLabel = Label(body, TEXT.colourBy, "text")
	byLabel:SetPoint("TOPLEFT", controls.wheel, "TOPRIGHT", 12, 0)
	controls.colourBy = W.Dropdown(body, 130, Getter("colourBy"), Setter("colourBy"), COLOUR_BY)
	controls.colourBy:SetPoint("TOPLEFT", byLabel, "BOTTOMLEFT", 0, -4)
	local strengthLabel = Label(body, TEXT.strength, "text")
	strengthLabel:SetPoint("TOPLEFT", controls.colourBy, "BOTTOMLEFT", 0, -10)
	controls.alpha = W.Slider(body, 130, Getter("alpha"), Setter("alpha"), { min = 0.1, max = 1, step = 0.05 })
	controls.alpha:SetPoint("TOPLEFT", strengthLabel, "BOTTOMLEFT", 0, -4)

	-- the buttons over the block
	placeBtn:HookScript("OnClick", function()
		if inst.ind then
			local ind = inst.ind
			RD:Remove(ind, Key())
			if ind.kind == "group" then
				inst.ind, inst.group = nil, ind.group
			else
				inst.ind = nil
			end
			canvas:Refresh()
		elseif inst.group then
			Place(inst.group, FreeSpot())
		end
	end)
	resetBtn:HookScript("OnClick", function()
		local ind = inst.ind
		if ind and ind.kind == "group" then
			for _, k in ipairs({ "spells", "out", "add", "colours", "ranks" }) do
				ind[k] = {}
			end
			inst.colourSpell = nil
			Changed(ind)
		end
	end)

	-- the fake raid (or party) where your frames stand
	local show = W.Button(canvas, TEXT.show, 220, nil, { height = 22 })
	show:SetPoint("TOPLEFT", canvas, "TOPLEFT", G.pad, -(trayH + G.gap + blockH + G.gap))
	show:HookScript("OnClick", function()
		local Pv = MelloUI.Preview
		if Pv and Pv.Start then
			-- (that part alone, in its own scene: the strip names the Raid Fight or the Party Fight)
			local part = inst.el == "raid" and "raid" or "party"
			local ok, why = Pv:Start(part, part)
			if not ok and why == "combat" then
				MelloUI:Print(Pv.TEXT.inCombat)
			end
		end
	end)
	Tip(show, TEXT.show, TEXT.showTip)

	------------------------------------------------------------------ refresh
	local SETTINGS = { "look", "size", "spot", "x", "y", "grow", "max", "perLine", "spacing", "whose", "which", "kind",
		"order", "when", "textShow", "textSize", "countShow", "countSize" }
	local LABELS = { look = "look", size = "size", spot = "spot", grow = "grow", max = "max", perLine = "perLine",
		spacing = "spacing", whose = "whose", order = "order", when = "when", time = "time", stacks = "stacks" }

	Refresh = function()
		local spec = RD:Spec()
		local kind = Page.KindOf(inst)
		if spec ~= inst.spec or kind ~= inst.kind then
			inst.spec, inst.kind, inst.ind, inst.group, inst.colourSpell = spec, kind, nil, nil, nil
		end
		local list = List()
		if inst.ind then
			local found = false
			for _, ind in ipairs(list) do
				if ind == inst.ind then
					found = true
				end
			end
			if not found then
				inst.ind = nil
			end
		end
		if not inst.ind and inst.group then
			-- (a group picked by its card that is on the frame after all: the placed one)
			inst.ind = PlacedOf(inst.group)
			inst.group = not inst.ind and inst.group or nil
		end
		if not inst.ind and not inst.group then
			inst.ind = list[1]
		end
		show:SetText(inst.el == "raid" and TEXT.show or TEXT.showParty)
		LayTray()
		local ind = inst.ind
		local key = (ind and ind.kind == "group" and ind.group) or (not ind and inst.group) or nil
		if not ind and key then
			wipe(inst.virtual)
			inst.virtual.group = key
		end
		none:SetShown(not ind and not key)
		body:SetShown(ind ~= nil or key ~= nil)
		if not (ind or key) then
			return
		end
		local def = key and SG.DEF[key]
		local debuff = def and def.scope == "debuff"
		heading:SetText(key and def.label or Page.Name(ind))
		scope:SetText(def and (def.scope == "own" and SG.ClassName(SG.SpecOf(inst.spec)) or (def.scope == "all" and TEXT.sections.all)
			or TEXT.sections.debuff) or "")
		blurb:SetText(def and def.tip or "")
		placeBtn:SetText(ind and (ind.kind == "group" and TEXT.off or TEXT.remove) or TEXT.on)
		resetBtn:SetShown(ind ~= nil and ind.kind == "group")
		-- the spells (a group's); a single spell has none
		local sel = Sel()
		if key then
			local all = BuildLines(sel)
			local on = 0
			for _, e in ipairs(all) do
				if SG.IsOn(sel, e) then
					on = on + 1
				end
			end
			spellsLabel:SetText(debuff and TEXT.kinds or string.format(TEXT.spells, on, #all))
			local maxOff = math.max(0, #lines - G.rows)
			offset = math.min(offset, maxOff)
		else
			wipe(lines)
			spellsLabel:SetText("")
		end
		spellsLabel:SetShown(key ~= nil)
		area:SetShown(key ~= nil)
		DrawRows()
		local canType = key ~= nil and not debuff and ind ~= nil
		typed:SetShown(canType)
		typedAdd:SetShown(canType)
		typedMsg:SetShown(canType)
		-- the settings: a placed one's only
		unplaced:SetShown(ind == nil)
		for _, k in ipairs(SETTINGS) do
			local c = controls[k]
			if c then
				ShowControl(c, ind ~= nil)
				if ind and c.Refresh then
					c:Refresh()
				end
			end
		end
		for _, l in pairs(labels) do
			l:SetShown(ind ~= nil)
		end
		local isGroup = ind ~= nil and ind.kind == "group"
		if ind then
			for _, k in ipairs({ "grow", "max", "perLine", "spacing", "order" }) do
				ShowControl(controls[k], isGroup)
				labels[LABELS[k]]:SetShown(isGroup)
			end
			local buffs = (isGroup and not debuff and key ~= "lockout") or ind.kind == "buff"
			ShowControl(controls.whose, buffs)
			ShowControl(controls.which, isGroup and key == "dispel")
			ShowControl(controls.kind, ind.kind == "debuff")
			labels.whose:SetText((buffs and TEXT.whose) or TEXT.which)
			labels.whose:SetShown(buffs or key == "dispel" or ind.kind == "debuff")
			-- (a debuff group: no order of your own -- the game never names its spells)
			if isGroup then
				controls.order.buttons[3]:SetShown(not debuff)
			end
		end
		-- the colour: a placed one's
		local hasColour = ind ~= nil
		colourLabel:SetShown(hasColour)
		controls.wheel:SetShown(hasColour)
		if hasColour then
			controls.wheel:Refresh()
			local e = inst.colourSpell and ind.order == "list" and inst.colourSpell
			colourLabel:SetText(e and string.format(TEXT.colourOf, SG.Name({ main = e })) or TEXT.colour)
		end
		local typedColour = ind ~= nil and (ind.kind == "debuff" or (isGroup and (debuff or key == "lockout")))
		byLabel:SetShown(typedColour)
		controls.colourBy:SetShown(typedColour)
		if typedColour then
			controls.colourBy:Refresh()
		end
		local health = ind ~= nil and ind.look == "health"
		strengthLabel:SetShown(health)
		controls.alpha:SetShown(health)
		if health then
			controls.alpha:Refresh()
		end
	end
	canvas.Refresh = Refresh
	canvas:Refresh()
	-- the list changed elsewhere (another spec, the ranks found, the stage): drawn again
	MelloUI:On("groupframes", function(what)
		if canvas:IsVisible() and (what == "spec" or what == "ids" or what == "list" or what == "paint") then
			canvas:Refresh()
		end
	end, canvas)
end
