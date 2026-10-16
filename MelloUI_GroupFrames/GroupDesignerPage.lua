--------------------------------------------------------------------------------
-- MelloUI - Group Frames: your indicators and the designer stage (one look
-- C10; it was the Designer, the picked sketch raid_designer_page.jpg)
--
--   Your Indicators   the canvas row on the Unit & Group Frames designer's
--                Party and Raid frames (their Indicators part): the list of
--                the spec you play -- a buff added by its spell's name or ID,
--                a debuff by its kind, Copy from another list -- and the
--                picked one's look, spot and offset, size (a bar: thickness
--                and length), whose / which, when, its colour on a colour
--                wheel (the user: "there should be a color wheel for people
--                to self decide the colour of it"), and its time and stacks as
--                text (the user: "font sizes and positions is also very
--                important"); "Show the fake raid on screen" on the raid's.
--   the stage    the 'raidframe' kind of the configurator's designer stage
--                (below): your frame large, its parts and indicators dragged,
--                sized and picked there.
-- Made with the page (the Configurator's first open of it), never at login.
--   Page.Build(canvas, width)   a canvas's content (its Refresh set)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local W = MelloUI.Widgets
local RD = ns.RD
local Looks = ns.Looks

local Page = {}
ns.Page = Page

local PartyReplica   -- (below: the normal party member's replica)

local TEXT = {
	list = "Indicators for %s",
	-- (one look C9b: each frame its own list)
	lists = { group = "Raid Frames: indicators for %s", groupParty = "Group Frames Party: indicators for %s",
		party = "Party Frames (Portraits): indicators for %s" },
	buffs = "BUFFS by spell (yours and your group's)",
	spellHint = "Spell name or ID",
	addBuff = "+ Buff",
	addDebuff = "+ Debuff (by kind)",
	copy = "Copy from a spec",
	none = "Pick an indicator above, or add one.",
	look = "Look", spot = "Spot", offset = "X / Y", size = "Size", length = "Length", whose = "Whose",
	kind = "Which", when = "Show", colour = "Colour", colourBy = "Colour from", strength = "Strength",
	time = "Its time", stacks = "Its stacks", remove = "Remove",
	show = "Show the fake raid on screen",
	showTip = "Made-up members where your raid frames stand, your indicators on them, until the preview ends. Out of combat only.",
	showParty = "Show the fake party on screen",
	showPartyTip = "Made-up members where your party frames stand, this list's indicators on them, until the preview ends. Out of combat only.",
	removeTip = "Take this indicator off the list (this spec only).",
	unnamed = "Spell %s",
}
local WHOSE = { { value = "mine", label = "Mine" }, { value = "any", label = "Anyone's" } }
local WHEN = { { value = "always", label = "Always" }, { value = "combat", label = "In a fight" } }
local COLOUR_BY = { { value = "type", label = "Its type's colour" }, { value = "mine", label = "My colour" } }
local SHORT_LOOK = { icon = "Icon", drain = "Draining", square = "Square", bar = "Bar", health = "Health" }

-- the canvas's measures: the list over the picked one's settings, the fake
-- raid's button under them
local G = { pad = 10, gap = 8, listH = 252, rowH = 20, rows = 8, setH = 318, labelW = 78, wheel = 96, spot = 13,
	spotGap = 3 }
Page.HEIGHT = G.listH + G.gap + G.setH + G.gap + 30

local Parts = ns.Parts

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function Label(parent, text, key, font)
	return W.Text(parent, font or "GameFontHighlightSmall", text, key or "text")
end

local function Box(parent, x, y, w, h)
	local f = CreateFrame("Frame", nil, parent)
	f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	f:SetSize(w, h)
	W.Panel(f, { on = true })
	return f
end

local function Name(ind)
	if ind.kind == "debuff" then
		local k = RD.KIND[ind.what]
		return k and k.label or "?"
	end
	return ind.name or string.format(TEXT.unnamed, tostring(ind.spell))
end

-- a row of choice buttons; the chosen one outlined in selectedTrim
local function Choices(parent, x, y, values, width, get, set)
	local row = { buttons = {} }
	local cx = x
	for i, v in ipairs(values) do
		local b = W.Button(parent, v.label, width, nil, { height = 20 })
		b:SetPoint("TOPLEFT", parent, "TOPLEFT", cx, -y)
		b.mark = W.Edges(b, "selectedTrim", "OVERLAY")
		b.value = v.value
		b:HookScript("OnClick", function()
			MelloUI:PlayUISound("tab")
			set(v.value)
		end)
		if v.tooltip then
			b:HookScript("OnEnter", function(self)
				W.ShowTooltip(self, v.label, v.tooltip)
			end)
			b:HookScript("OnLeave", W.TipLeave)
		end
		row.buttons[i] = b
		cx = cx + width + 4
	end
	function row:Refresh()
		local now = get()
		for _, b in ipairs(self.buttons) do
			for _, e in ipairs(b.mark) do
				e:SetShown(b.value == now)
			end
		end
	end
	return row
end

-- the nine spots as a small 3 x 3 grid of buttons
local function Spots(parent, x, y, get, set)
	local grid = { buttons = {} }
	for i, point in ipairs(RD.POINTS) do
		local col, line = (i - 1) % 3, math.floor((i - 1) / 3)
		local b = CreateFrame("Button", nil, parent)
		b:SetSize(G.spot, G.spot)
		b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + col * (G.spot + G.spotGap), -(y + line * (G.spot + G.spotGap)))
		b.fill = W.Solid(b, "ARTWORK", "raisedPanel", 1)
		b.fill:SetAllPoints(b)
		b.edges = W.Edges(b, "border", "OVERLAY")
		b.on = W.Solid(b, "OVERLAY", "selectedTrim", 1)
		b.on:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
		b.on:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
		b.point = point
		b:SetScript("OnClick", function()
			MelloUI:PlayUISound("tab")
			set(point)
		end)
		grid.buttons[i] = b
	end
	function grid:Refresh()
		local now = get()
		for _, b in ipairs(self.buttons) do
			b.on:SetShown(b.point == now)
		end
	end
	return grid
end

--------------------------------------------------------------------------------
-- Samples: a frame of the group frames' own (GroupButton.lua: the same builder
-- and painters as the secure frames, made-up values), its indicators drawn by
-- GroupLooks with made-up states
--------------------------------------------------------------------------------

local Button = ns.Button

local SAMPLE_MEMBERS = {
	{ class = "PRIEST", health = 0.9, frac = 0.7, role = "HEALER", power = 0.6 },
	{ class = "WARRIOR", health = 0.45, frac = 0.35, role = "TANK", power = 0.3, powerToken = "RAGE", mark = 8 },
	{ class = "MAGE", health = 0.75, frac = 0.85, role = "DAMAGER", power = 0.8 },
	{ class = "DRUID", health = 0.6, frac = 0.5, role = "HEALER", power = 0.5 },
	{ class = "ROGUE", health = 0.3, frac = 0.2, role = "DAMAGER", power = 0.9, powerToken = "ENERGY" },
}

-- a member's sample (its name from the Preview's made-up group)
local function Member(i)
	local m = SAMPLE_MEMBERS[(i - 1) % #SAMPLE_MEMBERS + 1]
	local pm = MelloUI.Preview and MelloUI.Preview.PARTY and MelloUI.Preview.PARTY[(i - 1) % 4 + 1]
	local s = {}
	for k, v in pairs(m) do
		s[k] = v
	end
	s.name = pm and pm.name or (m.class:sub(1, 1) .. m.class:sub(2):lower())
	return s
end

-- (`layout`, one look C9: the parts layout it is laid by -- "groupParty" for
-- our party's; nil the raid's)
local function SampleFrame(parent, sample, layout)
	local f = CreateFrame("Frame", nil, parent)
	local db = RD.DB()
	f:SetSize(db.width, db.height)
	f.marks = {}   -- [i] = { b, p }
	f.partsLayout = layout
	Button.Sample(f, sample)
	-- dressed as the frames are (the kit's rail and stone while the painted
	-- skin is on), its bars laid again inside that border: the preview is the
	-- frame (the user: "match exactly the Unitframe")
	local rfp = MelloUI:GetModule("RaidFramePanel")
	if rfp and rfp.DressStandIn then
		pcall(rfp.DressStandIn, rfp, f)
		Button.Lay(f)
	end
	return f
end

-- a normal party member's replica (ConfigPreview's: the game's party member
-- frame's keys and geometry, the Preview's stand-ins), painted as a made-up
-- member, dressed by the unit frame skin as the members are, with the parts it
-- lacks at the game's own places (its role, its ready check, its aura row)

local SAMPLE_AURAS = { "Interface\\Icons\\Spell_Holy_Renew", "Interface\\Icons\\Spell_Holy_WordFortitude",   -- look-ok: a sample's auras
	"Interface\\Icons\\Spell_Shadow_ShadowWordPain" }   -- look-ok: a sample's auras

PartyReplica = function(parent, i, ready)
	local CP = MelloUI.ConfigPreview
	local s = CP and CP.Build and CP.Dress and CP.Paint and CP.Values and CP.Values("unitframe", "party", i)
	if not s then
		return nil
	end
	local ok, f = pcall(CP.Build, "unitframe", parent, "party")
	if not ok or type(f) ~= "table" then
		return nil
	end
	-- (the unit frame kind's party sample: its values with the member's,
	-- dressed as a member -- Unit Frames' DressStandIn, once -- then painted)
	local m = Member(i)
	s.first, s.last, s.class = m.name, nil, m.class
	s.max, s.powerMax, s.token = 7000, 6000, m.powerToken or "MANA"
	s.health, s.power = math.floor(7000 * (m.health or 1) + 0.5), 4200
	f.sample = s
	pcall(CP.Dress, "unitframe", f, "party")
	pcall(CP.Paint, "unitframe", f, "party", s)
	local function At(region, part)
		local h = Parts.BY[part].home
		region:SetPoint(h.point, f, h.point, h.x, h.y)
	end
	-- (the role icon in the overlay, as the game keeps it)
	local overlay = rawget(f, "PartyMemberOverlay") or f
	if not rawget(overlay, "RoleIcon") then
		local role = overlay:CreateTexture(nil, "OVERLAY")
		role:SetSize(12, 12)
		At(role, "party.role")
		-- (the round badge the party frames show: GroupHeaders' SharpRole)
		local atlas = Button.RoleAtlas(m.role or "DAMAGER")
		if atlas and role.SetAtlas then
			pcall(role.SetAtlas, role, atlas)
		end
		overlay.RoleIcon = role
	end
	-- (the leader's crown on the first: the Leader Icon part to move)
	if not rawget(overlay, "LeaderIcon") then
		local leader = overlay:CreateTexture(nil, "OVERLAY")
		if leader.SetAtlas then
			pcall(leader.SetAtlas, leader, "UI-HUD-UnitFrame-Player-Group-LeaderIcon", true)
		end
		At(leader, "party.leader")
		leader:SetShown(i == 1)
		overlay.LeaderIcon = leader
	end
	if not rawget(f, "ReadyCheck") then
		f.ReadyCheck = f:CreateTexture(nil, "OVERLAY")
		f.ReadyCheck:SetSize(25, 25)
		At(f.ReadyCheck, "party.ready")
		local atlas = rawget(_G, "READY_CHECK_READY_TEXTURE_RAID")
		if type(atlas) == "string" and f.ReadyCheck.SetAtlas then
			f.ReadyCheck:SetAtlas(atlas)
		end
		f.ReadyCheck:SetShown(ready and true or false)
	end
	if not rawget(f, "AuraFrameContainer") then
		local c = CreateFrame("Frame", nil, f)
		c:SetSize(3 * 15 + 2 * 2, 15)
		At(c, "party.buffs")
		for j, icon in ipairs(SAMPLE_AURAS) do
			local t = c:CreateTexture(nil, "ARTWORK")
			t:SetSize(15, 15)
			t:SetPoint("TOPLEFT", c, "TOPLEFT", (j - 1) * 17, 0)
			t:SetTexture(icon)
		end
		f.AuraFrameContainer = c
	end
	f.marks = {}
	return f
end

-- a sample again with the settings as they are (size, colours, parts)
local function Resample(f)
	local db = RD.DB()
	f:SetSize(db.width, db.height)
	Button.Sample(f, f.sample)
end

-- the marks on a sample: one per indicator (`only`: which to show)
local function SampleMarks(f, inds, frac, only)
	for i, ind in ipairs(inds) do
		local m = f.marks[i]
		if not m then
			local b = CreateFrame("Frame", nil, f)
			m = { b = b, p = Looks.Make(b) }
			f.marks[i] = m
		end
		m.ind = ind
		local health = ind.look == "health"
		Looks.ParentLevel(m.b, health)
		if not health then
			m.b:SetFrameLevel(f:GetFrameLevel() + 3)
		end
		m.p.tint:SetDrawLayer(health and "BORDER" or "OVERLAY", health and 4 or 0)
		local bar = rawget(f, "healthBar") or (rawget(f, "HealthBarContainer") and f.HealthBarContainer.HealthBar)
		Looks.Lay(m.b, m.p, ind, f, Looks.Fill(bar))
		Looks.Sample(m.b, m.p, ind, frac)
		m.b:SetShown(not only or only(i, ind))
	end
	for i = #inds + 1, #f.marks do
		f.marks[i].b:Hide()
		f.marks[i].ind = nil
	end
end

--------------------------------------------------------------------------------
-- Your Indicators (one look C10: the canvas row on the Unit & Group Frames
-- designer's Party and Raid frames, Indicators): the list of the spec you
-- play -- the raid's, or your party's (its Portraits style's own while the
-- stage shows that) -- and the picked one's settings. Its place and size are
-- the designer stage's too (drag it there); a pick here picks it there.
--------------------------------------------------------------------------------

-- every canvas on show (one per frame's Indicators part), by its canvas
Page.canvases = setmetatable({}, { __mode = "k" })   -- [canvas] = { canvas, el, kind, spec, ind, Pick }

-- the list a canvas shows: the raid's, or the party's in the style the
-- stage shows (the portraits' own list while it shows them)
local function KindOf(inst)
	if inst.el == "raid" then
		return "group"
	end
	local CP = MelloUI.ConfigPreview
	local stage = CP and CP.Shown and CP.Shown("raidframe")
	return (stage and stage.pick == "portrait") and "party" or "groupParty"
end
Page.KindOf = KindOf

local function ListRow(parent, i, inst)
	local r = CreateFrame("Button", nil, parent)
	r:SetHeight(G.rowH)
	r.hover = W.Solid(r, "BACKGROUND", "hover", 0.6)
	r.hover:SetAllPoints(r)
	r.hover:Hide()
	r.sel = W.Solid(r, "BACKGROUND", "selectedTab", 0.9)
	r.sel:SetAllPoints(r)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(G.rowH - 4, G.rowH - 4)
	r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.name = Label(r, "", "text", "GameFontHighlight")
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
	r.look = Label(r, "", "text")
	r.look:SetPoint("RIGHT", r, "RIGHT", -8, 0)
	r.name:SetPoint("RIGHT", r.look, "LEFT", -6, 0)
	r.name:SetWordWrap(false)
	r:SetScript("OnEnter", function(self) self.hover:Show() end)
	r:SetScript("OnLeave", function(self) self.hover:Hide() end)
	r:SetScript("OnClick", function(self)
		MelloUI:PlayUISound("tab")
		inst.Pick(self.ind)
	end)
	r.index = i
	return r
end

local KIND_ICON = "Interface\\Icons\\Spell_Holy_DispelMagic"   -- look-ok: a debuff row's picture

function Page.Build(canvas, width)
	-- (the frame it is for: its section's, "party:indicators" or "raid:indicators")
	local row = canvas:GetParent()
	local sec = row and row:GetParent()
	local tab = type(sec) == "table" and rawget(sec, "name")
	local inst = { canvas = canvas, el = (type(tab) == "string" and tab:match("^party:")) and "party" or "raid",
		spec = RD:Spec() }
	inst.kind = KindOf(inst)
	Page.canvases[canvas] = inst
	local function Key()
		return RD:KeyOf(inst.spec, inst.kind)
	end
	local function Changed()
		if inst.ind then
			RD:Changed(inst.ind, Key())
		end
	end
	-- a pick: its settings here, and the stage picks it too
	function inst.Pick(ind)
		inst.ind = ind
		canvas:Refresh()
		local CP = MelloUI.ConfigPreview
		local stage = CP and CP.Shown and CP.Shown("raidframe")
		if stage and ind and Page.ListKind(stage.pick) == inst.kind and not Page.syncing then
			Page.syncing = true
			stage:Select("ind:" .. tostring(ind.id))
			Page.syncing = nil
		end
	end
	inst.ind = RD:List(Key())[1]
	local controls = {}   -- every control with a Refresh

	-- the list
	local listBox = Box(canvas, 0, 0, width, G.listH)
	local title = Label(listBox, "", "selectedTrim", "GameFontNormal")
	title:SetPoint("TOPLEFT", listBox, "TOPLEFT", G.pad, -G.pad)
	local rows = {}
	for i = 1, G.rows do
		local r = ListRow(listBox, i, inst)
		r:SetPoint("TOPLEFT", listBox, "TOPLEFT", 4, -(G.pad + 22 + (i - 1) * G.rowH))
		r:SetPoint("RIGHT", listBox, "RIGHT", -4, 0)
		rows[i] = r
	end
	-- the adds, under the rows
	local addY = G.pad + 22 + G.rows * G.rowH + 6
	local typed = CreateFrame("EditBox", nil, listBox)
	typed:SetSize(140, 20)
	typed:SetPoint("TOPLEFT", listBox, "TOPLEFT", G.pad + 6, -addY)
	typed:SetAutoFocus(false)
	typed:SetFontObject("GameFontHighlightSmall")
	typed:SetTextInsets(4, 4, 0, 0)
	W.FlatField(typed)
	local hint = Label(typed, TEXT.spellHint, "text")
	hint:SetPoint("LEFT", typed, "LEFT", 4, 0)
	typed:SetScript("OnTextChanged", function(self)
		hint:SetShown(self:GetText() == "")
	end)
	typed:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	local function AddBuff()
		local text = typed:GetText()
		local id, name = RD:Resolve(text)
		if not (id or name) then
			return
		end
		local ind = RD:Add({ kind = "buff", spell = id, name = name, look = "icon", point = "TOPRIGHT" }, Key())
		typed:SetText("")
		typed:ClearFocus()
		MelloUI:Print(RD.TEXT.added, Name(ind))
		inst.Pick(ind)
	end
	typed:SetScript("OnEnterPressed", AddBuff)
	local addBuff = W.Button(listBox, TEXT.addBuff, 64, nil, { height = 20 })
	addBuff:SetPoint("LEFT", typed, "RIGHT", 6, 0)
	addBuff:HookScript("OnClick", AddBuff)
	local addDebuff = W.Dropdown(listBox, 150, function() return nil end, function(value)
		local ind = RD:Add({ kind = "debuff", what = value, look = "bar", point = "BOTTOM", colourBy = "type" }, Key())
		inst.Pick(ind)
	end, RD.KINDS, { default = TEXT.addDebuff })
	addDebuff:SetPoint("LEFT", addBuff, "RIGHT", 6, 0)
	local copy = W.Dropdown(listBox, 150, function() return nil end, function(value)
		if value ~= Key() then
			RD:CopyFrom(value, Key())
			inst.ind = RD:List(Key())[1]
			Changed()
			canvas:Refresh()
		end
	end, RD:SpecValues(), { default = TEXT.copy })
	copy:SetPoint("LEFT", addDebuff, "RIGHT", 6, 0)

	-- the picked one's settings
	local set = Box(canvas, 0, G.listH + G.gap, width, G.setH)
	local none = Label(set, TEXT.none, "text", "GameFontHighlight")
	none:SetPoint("CENTER", set, "CENTER", 0, 0)
	local body = CreateFrame("Frame", nil, set)
	body:SetAllPoints(set)
	local heading = Label(body, "", "selectedTrim", "GameFontNormalLarge")
	heading:SetPoint("TOPLEFT", body, "TOPLEFT", G.pad, -G.pad)
	-- (two columns: the second from 370, its labels shorter)
	local x1, x2 = G.pad, 370
	local cx1, cx2 = x1 + G.labelW, x2 + 60
	local y = G.pad + 28
	local function Line(x, yy, text)
		local l = Label(body, text, "text", "GameFontHighlight")
		l:SetPoint("TOPLEFT", body, "TOPLEFT", x, -(yy + 3))
		return l
	end
	local function Ind()
		return inst.ind or {}
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
			Changed()
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

	-- column 1: look, spot, offset, size, length, whose / which, when, remove
	Line(x1, y, TEXT.look)
	controls.look = Choices(body, cx1, y, RD.LOOKS, 52, Getter("look"), Setter("look"))
	for i, b in ipairs(controls.look.buttons) do
		b:SetText(SHORT_LOOK[RD.LOOKS[i].value])
	end
	y = y + 28
	Line(x1, y, TEXT.spot)
	controls.spot = Spots(body, cx1, y, Getter("point"), function(point)
		local ind = inst.ind
		if ind then
			ind.point, ind.x, ind.y = point, 0, 0
			Changed()
		end
	end)
	Line(cx1 + 3 * (G.spot + G.spotGap) + 12, y, TEXT.offset)
	controls.x = W.NumberBox(body, 44, Getter("x"), Setter("x"), { min = -60, max = 60, step = 1 })
	controls.x:SetPoint("TOPLEFT", body, "TOPLEFT", cx1 + 3 * (G.spot + G.spotGap) + 64, -y)
	controls.y = W.NumberBox(body, 44, Getter("y"), Setter("y"), { min = -60, max = 60, step = 1 })
	controls.y:SetPoint("LEFT", controls.x, "RIGHT", 6, 0)
	controls.x.melloNext = controls.y
	y = y + 3 * (G.spot + G.spotGap) + 8
	Line(x1, y, TEXT.size)
	controls.size = W.Slider(body, 200, Getter("size"), Setter("size"), { min = 1, max = RD.SIZE.max, step = 1 })
	controls.size:SetPoint("TOPLEFT", body, "TOPLEFT", cx1, -y)
	y = y + 30
	local lengthLabel = Line(x1, y, TEXT.length)
	controls.length = W.Slider(body, 200, Getter("length"), Setter("length"), { min = 0.1, max = 1, step = 0.05 })
	controls.length:SetPoint("TOPLEFT", body, "TOPLEFT", cx1, -y)
	y = y + 30
	local whoseLabel = Line(x1, y, TEXT.whose)
	controls.whose = W.Dropdown(body, 150, Getter("whose"), Setter("whose"), WHOSE)
	controls.whose:SetPoint("TOPLEFT", body, "TOPLEFT", cx1, -y)
	controls.what = W.Dropdown(body, 200, Getter("what"), Setter("what"), RD.KINDS)
	controls.what:SetPoint("TOPLEFT", body, "TOPLEFT", cx1, -y)
	y = y + 28
	Line(x1, y, TEXT.when)
	controls.when = W.Dropdown(body, 150, Getter("when"), Setter("when"), WHEN)
	controls.when:SetPoint("TOPLEFT", body, "TOPLEFT", cx1, -y)
	y = y + 34
	local remove = W.Button(body, TEXT.remove, 90, nil, { height = 22 })
	remove:SetPoint("TOPLEFT", body, "TOPLEFT", x1, -y)
	remove:HookScript("OnClick", function()
		local ind = inst.ind
		if ind then
			RD:Remove(ind, Key())
			inst.ind = RD:List(Key())[1]
			canvas:Refresh()
		end
	end)
	remove:HookScript("OnEnter", function(self)
		W.ShowTooltip(self, TEXT.remove, TEXT.removeTip)
	end)
	remove:HookScript("OnLeave", W.TipLeave)

	-- column 2: colour, then the time and the stacks as text
	local y2 = G.pad + 28
	Line(x2, y2, TEXT.colour)
	controls.wheel = W.ColorWheel(body, G.wheel, function()
		local ind = Ind()
		return ind.r or 1, ind.g or 1, ind.b or 1
	end, function(r, g, b)
		local ind = inst.ind
		if ind then
			ind.r, ind.g, ind.b = r, g, b
			Changed()
		end
	end)
	controls.wheel:SetPoint("TOPLEFT", body, "TOPLEFT", cx2, -y2)
	local byLabel = Label(body, TEXT.colourBy, "text")
	byLabel:SetPoint("TOPLEFT", controls.wheel, "TOPRIGHT", 12, 0)
	controls.colourBy = W.Dropdown(body, 130, Getter("colourBy"), Setter("colourBy"), COLOUR_BY)
	controls.colourBy:SetPoint("TOPLEFT", byLabel, "BOTTOMLEFT", 0, -4)
	local strengthLabel = Label(body, TEXT.strength, "text")
	strengthLabel:SetPoint("TOPLEFT", controls.colourBy, "BOTTOMLEFT", 0, -10)
	controls.alpha = W.Slider(body, 130, Getter("alpha"), Setter("alpha"), { min = 0.1, max = 1, step = 0.05 })
	controls.alpha:SetPoint("TOPLEFT", strengthLabel, "BOTTOMLEFT", 0, -4)
	y2 = y2 + G.wheel + 12
	-- the time and the stacks: shown, size, spot, offset
	local function TextBlock(sub, label, yy)
		Line(x2, yy, label)
		local sw = W.Switch(body, Getter("show", sub), Setter("show", sub))
		sw:SetPoint("TOPLEFT", body, "TOPLEFT", cx2, -yy)
		local sl = W.Slider(body, 150, Getter("size", sub), Setter("size", sub),
			{ min = RD.SIZE.textMin, max = RD.SIZE.textMax, step = 1 })
		sl:SetPoint("TOPLEFT", body, "TOPLEFT", cx2 + 34, -yy)
		local grid = Spots(body, cx2, yy + 28, Getter("point", sub), function(point)
			local ind = inst.ind
			if ind then
				ind[sub].point, ind[sub].x, ind[sub].y = point, 0, 0
				Changed()
			end
		end)
		local bx = W.NumberBox(body, 44, Getter("x", sub), Setter("x", sub), { min = -40, max = 40, step = 1 })
		bx:SetPoint("TOPLEFT", body, "TOPLEFT", cx2 + 3 * (G.spot + G.spotGap) + 12, -(yy + 28))
		local by = W.NumberBox(body, 44, Getter("y", sub), Setter("y", sub), { min = -40, max = 40, step = 1 })
		by:SetPoint("LEFT", bx, "RIGHT", 6, 0)
		bx.melloNext = by
		controls[sub .. "Show"], controls[sub .. "Size"], controls[sub .. "Spot"] = sw, sl, grid
		controls[sub .. "X"], controls[sub .. "Y"] = bx, by
		return yy + 28 + 3 * (G.spot + G.spotGap) + 8
	end
	y2 = TextBlock("text", TEXT.time, y2)
	TextBlock("count", TEXT.stacks, y2)

	-- the made-up raid where your raid frames stand
	local show = W.Button(canvas, TEXT.show, 220, nil, { height = 22 })
	show:SetPoint("TOPLEFT", canvas, "TOPLEFT", G.pad, -(G.listH + G.gap + G.setH + G.gap))
	-- (one look: on the Party frame too -- your Group Frames party's own made-up party, or the portraits' stand-ins)
	local function ShowPart()
		if inst.el == "raid" then
			return "raid"
		end
		return inst.kind == "groupParty" and "groupparty" or "party"
	end
	show:HookScript("OnClick", function()
		local Pv = MelloUI.Preview
		if Pv and Pv.Start then
			local ok, why = Pv:Start("party", ShowPart())
			if not ok and why == "combat" then
				MelloUI:Print(Pv.TEXT.inCombat)
			end
		end
	end)
	show:HookScript("OnEnter", function(self)
		if inst.el == "raid" then
			W.ShowTooltip(self, TEXT.show, TEXT.showTip)
		else
			W.ShowTooltip(self, TEXT.showParty, TEXT.showPartyTip)
		end
	end)
	show:HookScript("OnLeave", W.TipLeave)

	-- the canvas's refresh: the list, the picked one's controls
	function canvas.Refresh()
		local spec, specLabel = RD:Spec()
		local kind = KindOf(inst)
		if spec ~= inst.spec or kind ~= inst.kind then
			inst.spec, inst.kind, inst.ind = spec, kind, nil
		end
		local list = RD:List(Key())
		local found = false
		for _, ind in ipairs(list) do
			if ind == inst.ind then
				found = true
			end
		end
		if not found then
			inst.ind = list[1]
		end
		title:SetText(string.format(TEXT.lists[inst.kind] or TEXT.list, specLabel))
		show:SetShown(inst.el == "raid" or inst.el == "party")
		show:SetText(inst.el == "raid" and TEXT.show or TEXT.showParty)
		for i, r in ipairs(rows) do
			local ind = list[i]
			r.ind = ind
			if ind then
				r.icon:SetTexture(ind.kind == "buff" and (RD:SpellIcon(ind) or "Interface\\Icons\\INV_Misc_QuestionMark") or KIND_ICON)   -- look-ok: a spell not known yet
				r.name:SetText(Name(ind))
				r.look:SetText((RD.LOOK[ind.look] or RD.LOOKS[1]).label)
				r.sel:SetShown(ind == inst.ind)
				r:Show()
			else
				r:Hide()
			end
		end
		copy:SetValues(RD:SpecValues())
		local ind = inst.ind
		none:SetShown(ind == nil)
		body:SetShown(ind ~= nil)
		if ind then
			heading:SetText(Name(ind) .. (ind.kind == "buff" and "" or "  (debuff)"))
			for _, c in pairs(controls) do
				if c.Refresh then
					c:Refresh()
				end
			end
			local isBar, isBuff, isHealth = ind.look == "bar", ind.kind == "buff", ind.look == "health"
			lengthLabel:SetShown(isBar)
			controls.length:SetShown(isBar)
			whoseLabel:SetText(isBuff and TEXT.whose or TEXT.kind)
			controls.whose:SetShown(isBuff)
			controls.what:SetShown(not isBuff)
			byLabel:SetShown(not isBuff)
			controls.colourBy:SetShown(not isBuff)
			strengthLabel:SetShown(isHealth)
			controls.alpha:SetShown(isHealth)
		end
	end
	canvas:Refresh()
	-- the list changed elsewhere (another spec, the ranks found, the stage):
	-- drawn again (one listener a canvas)
	MelloUI:On("groupframes", function(what)
		if canvas:IsVisible() and (what == "spec" or what == "ids" or what == "list" or what == "paint") then
			canvas:Refresh()
		end
	end, canvas)
end

--------------------------------------------------------------------------------
-- The fake raid on screen (the Preview's part "raid"): the samples where your
-- raid frames stand, hurt and healed with the scene, until it stops
--------------------------------------------------------------------------------

local fake = { holder = nil, frames = {} }
local FAKE_COUNT = 10

local function FakeShow()
	if not fake.holder then
		fake.holder = CreateFrame("Frame", "MelloUIGroupFramesFake", UIParent)
		fake.holder:SetFrameStrata("MEDIUM")
	end
	local h = fake.holder
	local db = RD.DB()
	h:ClearAllPoints()
	local raid = ns.Headers and ns.Headers.containers and ns.Headers.containers.raid
	if raid then
		h:SetPoint("TOPLEFT", raid, "TOPLEFT", 0, 0)
	elseif ns.Headers and ns.Headers.Home then
		ns.Headers.Home("raid")(h)
	end
	h:SetSize(1, 1)
	local list = RD:List()
	local per = math.max(1, db.raidPerLine or 5)
	local sp = ns.Headers and ns.Headers.Spacing and ns.Headers.Spacing("raid") or db.spacing   -- (0.20.2: the raid's own)
	for n = 1, FAKE_COUNT do
		local f = fake.frames[n]
		if not f then
			f = SampleFrame(h, Member(n))
			f.base = f.sample.health
			fake.frames[n] = f
		else
			Resample(f)
		end
		-- (the raid header's own order: down a column, the next column across --
		-- or across a row, the next row down)
		local line, at = math.floor((n - 1) / per), (n - 1) % per
		local x, y
		if db.raidFlow == "across" then
			x, y = at * (db.width + sp), -line * (db.height + (db.raidGap or 0))
		else
			x, y = line * (db.width + (db.raidGap or 0)), -at * (db.height + sp)
		end
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", h, "TOPLEFT", x, y)
		SampleMarks(f, list, f.sample.frac, function(j, e)
			return e.kind == "buff" and (n + j) % 2 == 0 or (e.kind == "debuff" and n % 4 == 2)
		end)
	end
	h:Show()
end

-- (one look, F-v3's needs_user 7, the user's yes) the made-up Group Frames party (the Preview's part
-- "groupparty", played alone): five samples where your party stands, laid in your party's own places
-- ("groupParty") and growth, its own list's indicators on them
local fakeParty = { holder = nil, frames = {} }
local FAKE_PARTY = 5
local GROW = { DOWN = { 0, -1, "TOPLEFT" }, UP = { 0, 1, "BOTTOMLEFT" }, RIGHT = { 1, 0, "TOPLEFT" },
	LEFT = { -1, 0, "TOPRIGHT" } }

local function FakePartyShow()
	if not fakeParty.holder then
		fakeParty.holder = CreateFrame("Frame", "MelloUIGroupFramesFakeParty", UIParent)
		fakeParty.holder:SetFrameStrata("MEDIUM")
	end
	local h = fakeParty.holder
	local db = RD.DB()
	local g = GROW[db.partyGrowth or "DOWN"] or GROW.DOWN
	h:ClearAllPoints()
	local party = ns.Headers and ns.Headers.containers and ns.Headers.containers.party
	if party then
		h:SetPoint(g[3], party, g[3], 0, 0)
	elseif ns.Headers and ns.Headers.Home then
		ns.Headers.Home("party")(h)
	end
	h:SetSize(1, 1)
	local list = RD:List(RD:KeyOf(nil, "groupParty"))
	local sp = ns.Headers and ns.Headers.Spacing and ns.Headers.Spacing("party") or db.spacing or 0
	for n = 1, FAKE_PARTY do
		local f = fakeParty.frames[n]
		if not f then
			f = SampleFrame(h, Member(n), "groupParty")
			f.base = f.sample.health
			fakeParty.frames[n] = f
		else
			Resample(f)
		end
		f:ClearAllPoints()
		f:SetPoint(g[3], h, g[3], g[1] * (n - 1) * (db.width + sp), g[2] * (n - 1) * (db.height + sp))
		SampleMarks(f, list, f.sample.frac, function(j, e)
			return e.kind == "buff" and (n + j) % 2 == 0 or (e.kind == "debuff" and n % 4 == 2)
		end)
	end
	h:Show()
end

local function FakeHit(n)
	for _, set in ipairs({ fake.frames, fakeParty.frames }) do
		for i, f in ipairs(set) do
			local wave = (n or 0) <= 8 and (n or 0) / 8 or math.max(0, (12 - n) / 4)
			f.sample.health = math.max(0.05, (f.base or 1) - 0.35 * wave * ((i % 3) + 1) / 3)
			Button.Health(f)
		end
	end
end

-- (heard from the module's first switch-on, as Healer Frames' preview: nothing
-- at load)
local listening = false
local PreviewBeat = function(beat, _, n)
	local Pv = MelloUI.Preview
	if beat == "stop" then
		if fake.holder then
			fake.holder:Hide()
		end
		if fakeParty.holder then
			fakeParty.holder:Hide()
		end
		return
	end
	-- (the fake party only while its part plays alone: the whole Party Fight has its stand-ins)
	local raid = Pv and Pv:Plays("raid")
	local party = Pv and Pv.Part and Pv:Part() == "groupparty"
	if not (RD.module.isEnabled and (raid or party)) then
		return
	end
	if beat == "start" then
		if raid then
			FakeShow()
		end
		if party then
			FakePartyShow()
		end
	elseif beat == "hit" then
		FakeHit(n)
	end
end

-- (0.20.1, the user: "the Group frames background should also switch the background of the group frames") a look
-- setting changed while the fake raid shows: its members painted again
local FakePaint = function(what)
	if what ~= "paint" then
		return
	end
	if fake.holder and fake.holder:IsShown() then
		for _, f in ipairs(fake.frames) do
			Resample(f)
		end
	end
	if fakeParty.holder and fakeParty.holder:IsShown() then
		for _, f in ipairs(fakeParty.frames) do
			Resample(f)
		end
	end
end

function Page.Listen()
	if not listening then
		listening = true
		MelloUI:On("preview", PreviewBeat, "GroupFrames.fake")
		MelloUI:On("groupframes", FakePaint, "GroupFrames.fakepaint")
	end
end

--------------------------------------------------------------------------------
-- The designer stage (one look C10: F-v3's F5b, docs/plans/onelook-designer):
-- the 'raidframe' kind of the configurator's stage (Core/ConfigPreview.lua's
-- wide stage) -- our raid frames ("raid"), our Group Frames party
-- ("groupParty") and the game's normal party frames ("portrait"), each laid by
-- its own parts layout (GroupParts.lua) and showing its own indicator list.
-- Registered at load (tables only); its samples made by the stage that shows
-- them. Parts: the frame's (name, health text, icons: placed, sized, shown),
-- the bars (picked for their colours, never moved), each indicator of the
-- list (placed, sized, its look from its list; a bar by its edges, a health
-- tint locked). Nothing reads a unit but the class (RD:Class: pcall).
--------------------------------------------------------------------------------

local Stage = {
	LAYOUT = { raid = "raid", groupParty = "groupParty", portrait = "portrait" },
	LIST = { raid = "group", groupParty = "groupParty", portrait = "party" },
	MOVER = { raid = "GroupFramesRaid", groupParty = "GroupFramesParty", portrait = "GroupFramesParty" },
	BAR_SPOTS = { "TOPLEFT", "TOP", "TOPRIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
	SIDE_SPOTS = { "LEFT", "RIGHT" },
	BAR_PLUS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
	BARS = { { key = "bar.health", label = "Health bar", field = "healthBar" },
		{ key = "bar.power", label = "Power bar", field = "powerBar" },
		{ key = "bar.background", label = "Background", field = "background" } },
	STYLES = { { key = "groupParty", label = "Group Frames" }, { key = "portrait", label = "Portraits" } },
	TEXT = { empty = "Switch on Group Frames first.", healthLocked = "It tints the health bar: nothing to move.",
		home = "Default place", gameHome = "The game's place" },
	TRY_TYPES = { dropdown = true, picture = true },
	-- (F-v3's F5b) the state chips over your own frames' picks: the member as it is, dead or offline -- the health
	-- text's Dead / Offline word and the grey, as a real member shows them (the Portraits pick: the game's, none)
	STATES = { { key = "normal", label = "Normal" }, { key = "dead", label = "Dead" }, { key = "offline", label = "Offline" } },
	cache = {},   -- [pick] = { list = {}, frame = { [key] = part }, ind = { [ind] = part } (weak) }
	EMPTY = {},
}

function Stage.Main(stage, pick)
	if pick == "portrait" then
		return PartyReplica(stage.holder, 1, true)
	end
	-- (made-up states on the big one: ready, a mark, a role; your class)
	local s = Member(1)
	s.class = RD:Class()
	s.health, s.frac, s.power = 0.85, 0.6, 0.7
	s.mark, s.ready, s.role = 1, "ready", s.role or "HEALER"
	return SampleFrame(stage.holder, s, pick == "groupParty" and "groupParty" or nil)
end

-- the sample as the frames are now (a try's choice painted on it only), its
-- list's marks on it
function Stage.Paint(f, pick, _, ctx)
	ctx = ctx or Stage.EMPTY
	if pick == "portrait" then
		local CP = MelloUI.ConfigPreview
		if CP and CP.Paint and f.sample then
			pcall(CP.Paint, "unitframe", f, "party", f.sample)
		end
		Parts:Lay(f, "party", true)
		SampleMarks(f, RD:List(nil, "party"), 0.6, ctx.only)
		return
	end
	local s = f.sample
	if s then
		s.dead, s.offline = ctx.state == "dead", ctx.state == "offline"
	end
	local try = ctx.try
	local key = try and type(try.id) == "string" and try.id:match("^GroupFrames%.(.+)$")
	if key then
		RD.WithTry(key, try.value, Resample, f)
	else
		Resample(f)
	end
	SampleMarks(f, RD:List(nil, Stage.LIST[pick]), 0.6, ctx.only)
end

-- the party's two styles (Group Frames | Portraits) over the stage
function Stage.Furnish(stage, holder)
	local chips = W.Chips(holder, { width = 220, onPick = function(_, key)
		stage:Pick(key)
	end })
	chips:SetItems(Stage.STYLES)
	chips:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, -8)
	stage.styleChips = chips
end

function Stage.Refresh(stage)
	local chips = stage.styleChips
	if chips then
		local party = stage.pick ~= "raid"
		chips:SetShown(party)
		if party and chips:Selected() ~= stage.pick then
			chips:Select(stage.pick)
		end
	end
	-- (the state chips over your own frames only: the Portraits pick is the game's frame)
	if stage.chips then
		stage.chips:SetShown(stage.pick ~= "portrait")
	end
	-- (the party's style switched: its canvases show that style's list)
	for canvas, inst in pairs(Page.canvases) do
		if inst.kind ~= Page.KindOf(inst) then
			canvas:Refresh()
		end
	end
end

function Page.ListKind(pick)
	return Stage.LIST[pick]
end

-- a part picked on the stage: an indicator picked in the canvases of its list
function Stage.OnSelect(stage, key)
	local id = type(key) == "string" and key:match("^ind:(.+)$")
	if not id or Page.syncing then
		return
	end
	local kind = Stage.LIST[stage.pick]
	for canvas, inst in pairs(Page.canvases) do
		if Page.KindOf(inst) == kind then
			for _, ind in ipairs(RD:List(RD:KeyOf(inst.spec, kind))) do
				if tostring(ind.id) == id then
					inst.ind = ind
					Page.syncing = true
					canvas:Refresh()
					Page.syncing = nil
				end
			end
		end
	end
end

-- the Health Text part's list: its forms (one setting)
function Stage.HealthContent()
	if not Stage.health then
		Stage.health = { values = RD.CHOICES.healthText, get = function()
			return RD.DB().healthText
		end, set = function(v)
			MelloUI:NotifySettingChanged(RD.module.name, "healthText", v)
		end }
	end
	return Stage.health
end

function Stage.FramePart(p, layout)
	local text = p.text and true or nil
	local sizes = Parts.SIZE
	return {
		key = p.key, label = p.label, class = "part", text = text,
		region = function(f)
			return Parts.RegionOf(f, p.key)
		end,
		store = { get = function()
			return Parts:Of(p.key, layout)
		end, set = function(_, t)
			Parts:Place(layout, p.key, t)
		end },
		home = function()
			return Parts:Shown(p.key, layout)
		end,
		size = { min = text and sizes.textMin or sizes.iconMin, max = text and sizes.textMax or sizes.iconMax, step = 1 },
		hide = true,
		homeLabel = layout == "portrait" and Stage.TEXT.gameHome or Stage.TEXT.home,
		content = p.key == "health" and Stage.HealthContent() or nil,
	}
end

-- an indicator's place written onto it (nil: its default place), its list
-- told once
function Stage.SetInd(part, t)
	local ind = part.ind
	if t == nil then
		local h = RD:Home(ind, part.listKey)
		ind.point, ind.x, ind.y = h.point, h.x, h.y
	else
		ind.point, ind.x, ind.y = t.point or ind.point, tonumber(t.x) or 0, tonumber(t.y) or 0
		if tonumber(t.size) then
			ind.size = tonumber(t.size)
		end
	end
	RD:Changed(ind, part.listKey)
end

function Stage.LookValues()
	if not Stage.looks then
		Stage.looks = {}
		for i, l in ipairs(RD.LOOKS) do
			Stage.looks[i] = { value = l.value, label = l.label }
		end
	end
	return Stage.looks
end

function Stage.IndPart(ind)
	local part = { key = "ind:" .. tostring(ind.id), class = "indicator", ind = ind }
	part.region = function(f)
		for _, m in ipairs(f.marks or Stage.EMPTY) do
			if m.ind == ind and m.b:IsShown() then
				return m.b
			end
		end
		return nil
	end
	part.store = { get = function()
		return ind
	end, set = Stage.SetInd }
	part.content = { values = Stage.LookValues(), get = function()
		return ind.look
	end, set = function(v)
		ind.look = v
		RD:Changed(ind, part.listKey)
	end }
	return part
end

-- a bar indicator's drop: its edges (a drag keeps its direction); a '+'
-- puts it on that spot (one at a side turns it upright, on purpose)
function Stage.BarDrop(part, l, b, r, t, w, h, _, spot)
	if spot then
		return { point = spot, x = 0, y = 0 }
	end
	local point, x, y = Looks.BarDrop(l, b, r, t, w, h, part.ind, true)
	return { point = point, x = x, y = y }
end

-- the fields an indicator's look decides
function Stage.Shape(part, ind)
	part.label = Name(ind)
	part.locked, part.spots, part.plus, part.Drop = nil, nil, nil, nil
	part.size = { min = RD.SIZE.min, max = RD.SIZE.max, step = 1 }
	if ind.look == "health" then
		part.locked, part.size = Stage.TEXT.healthLocked, nil
	elseif ind.look == "bar" then
		local upright = ind.point == "LEFT" or ind.point == "RIGHT"
		part.spots = upright and Stage.SIDE_SPOTS or Stage.BAR_SPOTS
		part.plus, part.Drop = Stage.BAR_PLUS, Stage.BarDrop
	end
end

-- the pick's parts: its layout's frame parts, the bars (ours), its list's
-- indicators; each part's table made once (the list's tables reused)
function Stage.Parts(pick)
	local c = Stage.cache[pick]
	if not c then
		c = { list = {}, frame = {}, ind = setmetatable({}, { __mode = "k" }) }
		Stage.cache[pick] = c
	end
	local list = wipe(c.list)
	local layout = Stage.LAYOUT[pick] or "raid"
	for _, p in ipairs(Parts:ListOfLayout(layout)) do
		local part = c.frame[p.key]
		if not part then
			part = Stage.FramePart(p, layout)
			c.frame[p.key] = part
		end
		-- (a row the game lays itself, scaled whole: its offsets in its own units)
		local shown = p.scale and Parts:Shown(p.key, layout)
		part.scale = shown and math.max(0.2, (shown.size or p.home.size) / p.home.size) or nil
		list[#list + 1] = part
	end
	if pick ~= "portrait" then
		for _, bar in ipairs(Stage.BARS) do
			local part = c.frame[bar.key]
			if not part then
				part = { key = bar.key, label = bar.label, class = "bar", drag = false, region = function(f)
					return rawget(f, bar.field)
				end }
				c.frame[bar.key] = part
			end
			list[#list + 1] = part
		end
	end
	local listKey = RD:KeyOf(nil, Stage.LIST[pick])
	for _, ind in ipairs(RD:List(listKey)) do
		local part = c.ind[ind]
		if not part then
			part = Stage.IndPart(ind)
			c.ind[ind] = part
		end
		part.listKey = listKey
		Stage.Shape(part, ind)
		list[#list + 1] = part
	end
	return list
end

-- the pick's parts with no sample (the Parts line, the search)
function Stage.PartKeys(pick)
	local out = {}
	for _, part in ipairs(Stage.Parts(pick or "groupParty")) do
		out[#out + 1] = { key = part.key, label = part.label, class = part.class, size = part.size ~= nil,
			hide = part.hide and true or false, drag = part.drag ~= false and not part.locked, locked = part.locked }
	end
	return out
end

-- the options a hover may try on the samples: Group Frames' lists and pictures
function Stage.Tries(id)
	local key = type(id) == "string" and id:match("^GroupFrames%.(.+)$")
	if not key then
		return false
	end
	for _, o in ipairs(RD.module.options or Stage.EMPTY) do
		if o.key == key then
			return Stage.TRY_TYPES[o.type] or false
		end
	end
	return false
end

function Stage.Empty()
	return not RD.module.isEnabled and Stage.TEXT.empty or nil
end

function Stage.Moved(pick)
	return Parts:Moved(Stage.LAYOUT[pick] or "raid")
end

-- the shown layout's frame parts back (its indicators left alone)
function Stage.ResetAll(pick)
	Parts:ResetLayout(Stage.LAYOUT[pick] or "raid")
end

function Stage.Mover(pick)
	return Stage.MOVER[pick]
end

do
	local CP = MelloUI.ConfigPreview
	if CP and CP.Register then
		CP.Register("raidframe", {
			place = "wide", height = 214, maxScale = 3,
			picks = { raid = true, groupParty = true, portrait = true }, first = "groupParty",
			watch = { GroupFrames = true, BarTextures = true, Fonts = true, UnitFrames = true },
			topics = { "groupframes" },
			reset = { { "GroupFrames", "parts" }, { "GroupFrames", "partyParts" } },
			Furnish = Stage.Furnish, Main = Stage.Main, Refresh = Stage.Refresh, Paint = Stage.Paint,
			parts = Stage.Parts, PartKeys = Stage.PartKeys, Tries = Stage.Tries, Empty = Stage.Empty, states = Stage.STATES,
			Moved = Stage.Moved, ResetAll = Stage.ResetAll, mover = Stage.Mover, OnSelect = Stage.OnSelect,
		})
	end
end
Page.Stage = Stage
