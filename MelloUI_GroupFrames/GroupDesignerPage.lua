--------------------------------------------------------------------------------
-- MelloUI - Group Frames: the Designer (the Configurator's canvas row
-- on the Group Frames page; the picked sketch raid_designer_page.jpg,
-- picks 1A 2A 3C 4B)
--
--   top left     your frame four times its size: every indicator on it as a
--                sample (made-up values: nothing read). Drag one to move it
--                (it takes the nearest of the nine spots and the offset from
--                it), the mouse wheel over it sizes it, a click picks it.
--   top right    the indicators of the spec you play: a row each (its
--                picture, its name, its look); a buff added by its spell's
--                name or ID, a debuff by its kind; Copy from another spec.
--   middle       the picked one: its look, its spot (3 x 3) and offset, its
--                size (a bar: thickness and length), whose / which, when, its
--                colour on a colour wheel (the user: "there should be a color
--                wheel for people to self decide the colour of it"), and its
--                time and stacks as text -- each with its size, spot and
--                offset (the user: "font sizes and positions is also very
--                important").
--   bottom       a made-up group at the game's size, and "Show the fake raid
--                on screen": the Preview's part "raid" (MelloUI.Preview), the
--                same samples where your raid frames stand.
-- Made with the page (the Configurator's first open of it), never at login.
--   Page.Build(canvas, width)   the canvas's content (its Refresh set)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_GroupFrames (the Designer)")
local Shared = Perf.Shared
local W = MelloUI.Widgets
local RD = ns.RD
local Looks = ns.Looks

local Page = {}
ns.Page = Page

local PartyReplica, PARTY_SIZE   -- (below: the normal party member's replica)

local TEXT = {
	frame = "Your frame, as large as it fits: drag an indicator to move it, the mouse wheel over it to size it",
	list = "Indicators for %s",
	buffs = "BUFFS by spell (yours and your group's)",
	debuffs = "DEBUFFS on your group, by kind (the game forbids picking one out by spell)",
	spellHint = "Spell name or ID",
	addBuff = "+ Buff",
	addDebuff = "+ Debuff (by kind)",
	copy = "Copy from a spec",
	none = "Pick an indicator above, or add one.",
	look = "Look", spot = "Spot", offset = "X / Y", size = "Size", length = "Length", whose = "Whose",
	kind = "Which", when = "Show", colour = "Colour", colourBy = "Colour from", strength = "Strength",
	time = "Its time", stacks = "Its stacks", textSize = "Size", remove = "Remove",
	group = "A made-up group at the game's size",
	show = "Show the fake raid on screen",
	showTip = "Made-up members where your raid frames stand, your indicators on them, until the preview ends. Out of combat only.",
	removeTip = "Take this indicator off the list (this spec only).",
	unnamed = "Spell %s",
	parts = "Frame parts:",
	designing = "Designing:",
	kinds = { group = "Group Frames", party = "Party Frames" },
	partyList = "Indicators for %s (Party Frames)",
	partyGroup = "Your party at the frames' size (the normal party frames)",
	partShow = "Show",
	partSize = "Size",
	partReset = "The Game's",
	partResetTip = "Back to the game's own place and size (the frames take it on their next update: a /reload, or someone joining).",
	partNote = "One of the game's own parts of every party and raid frame (and of your frame while solo).",
}
local WHOSE = { { value = "mine", label = "Mine" }, { value = "any", label = "Anyone's" } }
local WHEN = { { value = "always", label = "Always" }, { value = "combat", label = "In a fight" } }
local COLOUR_BY = { { value = "type", label = "Its type's colour" }, { value = "mine", label = "My colour" } }
local SHORT_LOOK = { icon = "Icon", drain = "Draining", square = "Square", bar = "Bar", health = "Health" }

-- the canvas's measures (the frame at the game's native 72 x 36, shown 4x)
local G = { pad = 10, gap = 8, scale = 4, fw = 72, fh = 36, topH = 276, rowH = 20, rows = 8, chips = 26,
	setY = 288, setH = 318, raidY = 616, labelW = 78, wheel = 96, spot = 13, spotGap = 3, groupH = 100 }
Page.HEIGHT = G.raidY + 100

local P = { ind = nil, part = nil, spec = nil, kind = "group" }   -- the picked indicator (or frame part), the spec shown, the frame kind designed
local Parts = ns.Parts

Page.P = P

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

local function Changed()
	if P.ind then
		RD:Changed(P.ind)
	end
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

-- the list designed now: the spec's, of the frame kind on show
local function Key()
	return RD:KeyOf(P.spec, P.kind)
end

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

local function SampleFrame(parent, sample)
	local f = CreateFrame("Frame", nil, parent)
	local db = RD.DB()
	f:SetSize(db.width, db.height)
	f.marks = {}   -- [i] = { b, p }
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
PARTY_SIZE = { w = 120, h = 53 }   -- (the game's party member frame)

local SAMPLE_AURAS = { "Interface\\Icons\\Spell_Holy_Renew", "Interface\\Icons\\Spell_Holy_WordFortitude",   -- look-ok: a sample's auras
	"Interface\\Icons\\Spell_Shadow_ShadowWordPain" }   -- look-ok: a sample's auras

PartyReplica = function(parent, i, ready)
	local CP = MelloUI.ConfigPreview
	if not (CP and CP.MakeParty and CP.PaintParty and CP.PartySample) then
		return nil
	end
	local ok, f = pcall(CP.MakeParty, parent)
	if not ok or type(f) ~= "table" then
		return nil
	end
	local m = Member(i)
	local s = CP.PartySample()
	s.first, s.last, s.class = m.name, nil, m.class
	s.max, s.powerMax, s.token = 7000, 6000, m.powerToken or "MANA"
	s.health, s.power = math.floor(7000 * (m.health or 1) + 0.5), 4200
	pcall(CP.PaintParty, f, s)
	local ufp = MelloUI:GetModule("UnitFramePanel")
	if ufp and ufp.DressStandIn then
		pcall(ufp.DressStandIn, ufp, f)
	end
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
local function SampleMarks(f, inds, frac, only, mouse)
	for i, ind in ipairs(inds) do
		local m = f.marks[i]
		if not m then
			local b = CreateFrame("Frame", nil, f)
			m = { b = b, p = Looks.Make(b) }
			f.marks[i] = m
			if mouse then
				mouse(b, m)
			end
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
-- The big frame: drag, wheel, click
--------------------------------------------------------------------------------

local big = nil
local drag = { m = nil }

-- the cursor in the big frame's own units
local function CursorIn(f)
	local x, y = GetCursorPosition()
	local s = f:GetEffectiveScale()
	local l, b = f:GetLeft(), f:GetBottom()
	if not (l and b) then
		return nil
	end
	return x / s - l, y / s - b
end

-- the spot nearest a point of the frame, and the offset from it
local SPOT_AT = {
	TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 },
	RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
local function Nearest(x, y)
	local best, bd, bx, by = "CENTER", math.huge, 0, 0
	local fw, fh = big:GetWidth(), big:GetHeight()
	for _, point in ipairs(RD.POINTS) do
		local at = SPOT_AT[point]
		local px, py = at[1] * fw, at[2] * fh
		local d = (x - px) ^ 2 + (y - py) ^ 2
		if d < bd then
			best, bd, bx, by = point, d, px, py
		end
	end
	return best, math.floor(x - bx + 0.5), math.floor(y - by + 0.5)
end

local DragTick = Shared("OnUpdate on the Designer's drag", function()
	local m = drag.m
	if not (m and big) then
		return
	end
	local x, y = CursorIn(big)
	if x then
		m.b:ClearAllPoints()
		m.b:SetPoint("CENTER", big, "BOTTOMLEFT", x, y)
	end
end, "script")

local function Pick(ind)
	P.ind, P.part = ind, nil
	if Page.canvas then
		Page.canvas:Refresh()
	end
end

local function MarkMouse(b, m)
	b:EnableMouse(true)
	b:EnableMouseWheel(true)
	b:SetScript("OnMouseDown", function()
		if not m.ind then
			return
		end
		Pick(m.ind)
		drag.m = m
		big.dragger:SetScript("OnUpdate", DragTick)
		big.dragger:Show()
	end)
	b:SetScript("OnMouseUp", function()
		if drag.m ~= m then
			return
		end
		drag.m = nil
		big.dragger:SetScript("OnUpdate", nil)
		big.dragger:Hide()
		local ind = m.ind
		local x, y = CursorIn(big)
		if ind and x and ind.look ~= "health" then
			local point, dx, dy = Nearest(x, y)
			-- (the indicator's own point sits on the spot: its middle under the
			-- cursor means half its size off a corner)
			local half = (ind.look == "bar") and 0 or (ind.size or 12) / 2
			local at = SPOT_AT[point]
			dx = dx + (at[1] == 0 and -half or at[1] == 1 and half or 0)
			dy = dy + (at[2] == 0 and -half or at[2] == 1 and half or 0)
			ind.point, ind.x, ind.y = point, math.floor(dx + 0.5), math.floor(dy + 0.5)
		end
		Changed()
	end)
	b:SetScript("OnMouseWheel", function(_, delta)
		local ind = m.ind
		if not ind then
			return
		end
		Pick(ind)
		local key = "size"
		ind[key] = math.max(RD.SIZE.min, math.min(RD.SIZE.max, (ind[key] or 12) + delta))
		Changed()
	end)
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

local function ListRow(parent, i)
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
		Pick(self.ind)
	end)
	r.index = i
	return r
end

local KIND_ICON = "Interface\\Icons\\Spell_Holy_DispelMagic"   -- look-ok: a debuff row's picture

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

function Page.Build(canvas, width)
	Page.canvas = canvas
	P.spec = RD:Spec()
	local inds = RD:List(Key())
	P.ind = inds[1]
	local controls = {}   -- every control with a Refresh

	-- top left: the big frame -- your frame at its own size, scaled to fit
	local bigW = G.fw * G.scale + 2 * G.pad
	local frameBox = Box(canvas, 0, 0, bigW, G.topH)
	local cap = Label(frameBox, TEXT.frame, "text")
	cap:SetPoint("TOPLEFT", frameBox, "TOPLEFT", G.pad, -G.pad)
	cap:SetWidth(bigW - 2 * G.pad)
	local _, class = UnitClass("player")
	local okR, role = pcall(UnitGroupRolesAssigned, "player")
	local bigGroup = SampleFrame(frameBox, { class = class, name = UnitName("player"), health = 0.85, power = 0.7,
		role = (okR and type(role) == "string" and role ~= "NONE") and role or "HEALER", mark = 1, ready = "ready" })
	local bigParty = PartyReplica(frameBox, 1, true)
	big = bigGroup
	local TOP = G.pad + 58   -- (under the caption and the kind switch)
	local function FitBig()
		local w, h = big:GetWidth(), big:GetHeight()
		local roomW, roomH = bigW - 2 * G.pad, G.topH - TOP - G.pad
		local scale = math.min(G.scale, roomW / w, roomH / h)
		big:SetScale(scale)
		big:ClearAllPoints()
		big:SetPoint("TOPLEFT", frameBox, "TOPLEFT", (G.pad + (roomW - w * scale) / 2) / scale, -TOP / scale)
	end
	-- (a clear frame over the box while a mark is dragged: the mark follows)
	local dragger = CreateFrame("Frame", nil, frameBox)
	dragger:Hide()
	bigGroup.dragger = dragger
	if bigParty then
		bigParty.dragger = dragger
	end
	-- the kind designed: our group frames, or the normal party frames
	local kindLabel = Label(frameBox, TEXT.designing, "text")
	kindLabel:SetPoint("TOPLEFT", frameBox, "TOPLEFT", G.pad, -(G.pad + 32))
	controls.kind = Choices(frameBox, G.pad + 70, G.pad + 28, {
		{ value = "group", label = TEXT.kinds.group }, { value = "party", label = TEXT.kinds.party },
	}, 98, function() return P.kind end, function(v)
		if v ~= P.kind and (v == "group" or bigParty) then
			P.kind, P.ind, P.part = v, nil, nil
			canvas:Refresh()
		end
	end)

	-- top right: the list
	local listX = bigW + G.gap
	local listW = width - listX
	local listBox = Box(canvas, listX, 0, listW, G.topH)
	local title = Label(listBox, "", "selectedTrim", "GameFontNormal")
	title:SetPoint("TOPLEFT", listBox, "TOPLEFT", G.pad, -G.pad)
	-- the frame's own parts, a button each (picked: their settings below)
	local chipsLabel = Label(listBox, TEXT.parts, "text")
	chipsLabel:SetPoint("TOPLEFT", listBox, "TOPLEFT", G.pad, -(G.pad + 22))
	local chips = {}
	for _, kind in ipairs(RD.KINDS_OF_FRAME) do
		local cx = G.pad + 66
		for _, part in ipairs(Parts:ListOf(kind)) do
			local w = 46
			local b = W.Button(listBox, part.short, w, nil, { height = 18 })
			b:SetPoint("TOPLEFT", listBox, "TOPLEFT", cx, -(G.pad + 18))
			b.mark = W.Edges(b, "selectedTrim", "OVERLAY")
			b.key, b.kind = part.key, kind
			b:HookScript("OnClick", function()
				MelloUI:PlayUISound("tab")
				P.ind, P.part = nil, part.key
				canvas:Refresh()
			end)
			chips[#chips + 1] = b
			cx = cx + w + 4
		end
	end
	local rows = {}
	for i = 1, G.rows do
		local r = ListRow(listBox, i)
		r:SetPoint("TOPLEFT", listBox, "TOPLEFT", 4, -(G.pad + 18 + G.chips + (i - 1) * G.rowH))
		r:SetPoint("RIGHT", listBox, "RIGHT", -4, 0)
		rows[i] = r
	end
	-- the adds, under the rows
	local addY = G.pad + 18 + G.chips + G.rows * G.rowH + 6
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
		Pick(ind)
	end
	typed:SetScript("OnEnterPressed", AddBuff)
	local addBuff = W.Button(listBox, TEXT.addBuff, 64, nil, { height = 20 })
	addBuff:SetPoint("LEFT", typed, "RIGHT", 6, 0)
	addBuff:HookScript("OnClick", AddBuff)
	local addDebuff = W.Dropdown(listBox, 150, function() return nil end, function(value)
		local ind = RD:Add({ kind = "debuff", what = value, look = "bar", point = "BOTTOM", colourBy = "type" }, Key())
		Pick(ind)
	end, RD.KINDS, { default = TEXT.addDebuff })
	addDebuff:SetPoint("LEFT", addBuff, "RIGHT", 6, 0)
	local copy = W.Dropdown(listBox, 150, function() return nil end, function(value)
		if value ~= P.spec then
			RD:CopyFrom(value, Key())
			P.ind = RD:List(P.spec)[1]
			Changed()
			canvas:Refresh()
		end
	end, RD:SpecValues(), { default = TEXT.copy })
	copy:SetPoint("TOPLEFT", typed, "BOTTOMLEFT", 0, -6)

	-- middle: the picked one's settings
	local set = Box(canvas, 0, G.setY, width, G.setH)
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
		return P.ind or {}
	end
	local function Setter(key, sub)
		return function(v)
			local ind = P.ind
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
		local ind = P.ind
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
		local ind = P.ind
		if ind then
			RD:Remove(ind, Key())
			P.ind = RD:List(P.spec)[1]
			canvas:Refresh()
		end
	end)
	remove:HookScript("OnEnter", function(self)
		W.ShowTooltip(self, TEXT.remove, TEXT.removeTip)
	end)
	remove:HookScript("OnLeave", W.TipLeave)

	-- a frame part's settings (in place of an indicator's)
	local partBody = CreateFrame("Frame", nil, set)
	partBody:SetAllPoints(set)
	local partHeading = Label(partBody, "", "selectedTrim", "GameFontNormalLarge")
	partHeading:SetPoint("TOPLEFT", partBody, "TOPLEFT", G.pad, -G.pad)
	local partNote = Label(partBody, TEXT.partNote, "text")
	partNote:SetPoint("TOPLEFT", partHeading, "BOTTOMLEFT", 0, -4)
	local function PartLine(yy, text)
		local l = Label(partBody, text, "text", "GameFontHighlight")
		l:SetPoint("TOPLEFT", partBody, "TOPLEFT", x1, -(yy + 3))
	end
	local function PartGet(field)
		return function()
			return P.part and Parts:Shown(P.part)[field]
		end
	end
	local function PartSet(field)
		return function(v)
			if P.part then
				Parts:Set(P.part, field, v)
			end
		end
	end
	local py = G.pad + 48
	local partControls = {}
	PartLine(py, TEXT.partShow)
	partControls.show = W.Switch(partBody, function() return PartGet("show")() ~= false end, PartSet("show"))
	partControls.show:SetPoint("TOPLEFT", partBody, "TOPLEFT", cx1, -py)
	py = py + 28
	PartLine(py, TEXT.spot)
	partControls.spot = Spots(partBody, cx1, py, PartGet("point"), function(point)
		if P.part then
			Parts:SetSpot(P.part, point)
		end
	end)
	partControls.x = W.NumberBox(partBody, 44, PartGet("x"), PartSet("x"), { min = -60, max = 60, step = 1 })
	partControls.x:SetPoint("TOPLEFT", partBody, "TOPLEFT", cx1 + 3 * (G.spot + G.spotGap) + 64, -py)
	partControls.y = W.NumberBox(partBody, 44, PartGet("y"), PartSet("y"), { min = -60, max = 60, step = 1 })
	partControls.y:SetPoint("LEFT", partControls.x, "RIGHT", 6, 0)
	partControls.x.melloNext = partControls.y
	local offLabel = Label(partBody, TEXT.offset, "text", "GameFontHighlight")
	offLabel:SetPoint("TOPLEFT", partBody, "TOPLEFT", cx1 + 3 * (G.spot + G.spotGap) + 12, -(py + 3))
	py = py + 3 * (G.spot + G.spotGap) + 8
	PartLine(py, TEXT.partSize)
	partControls.size = W.Slider(partBody, 200, PartGet("size"), PartSet("size"),
		{ min = Parts.SIZE.textMin, max = Parts.SIZE.iconMax, step = 1 })
	partControls.size:SetPoint("TOPLEFT", partBody, "TOPLEFT", cx1, -py)
	py = py + 34
	local partReset = W.Button(partBody, TEXT.partReset, 110, nil, { height = 22 })
	partReset:SetPoint("TOPLEFT", partBody, "TOPLEFT", x1, -py)
	partReset:HookScript("OnClick", function()
		if P.part then
			Parts:Reset(P.part)
		end
	end)
	partReset:HookScript("OnEnter", function(self)
		W.ShowTooltip(self, TEXT.partReset, TEXT.partResetTip)
	end)
	partReset:HookScript("OnLeave", W.TipLeave)

	-- column 2: colour, then the time and the stacks as text
	local y2 = G.pad + 28
	Line(x2, y2, TEXT.colour)
	controls.wheel = W.ColorWheel(body, G.wheel, function()
		local ind = Ind()
		return ind.r or 1, ind.g or 1, ind.b or 1
	end, function(r, g, b)
		local ind = P.ind
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
			local ind = P.ind
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

	-- bottom: the made-up group, and the on-screen fake raid
	local raidLabel = Label(canvas, TEXT.group, "text", "GameFontHighlight")
	raidLabel:SetPoint("TOPLEFT", canvas, "TOPLEFT", G.pad, -G.raidY)
	local group, row = {}, CreateFrame("Frame", nil, canvas)
	row:SetSize(1, 1)
	for i = 1, #SAMPLE_MEMBERS do
		group[i] = SampleFrame(row, Member(i))
	end
	local function FitGroup()
		local db = RD.DB()
		local need = #group * db.width + (#group - 1) * 8
		local scale = math.min(1, (width - 2 * G.pad) / need, G.groupH / db.height)
		row:SetScale(scale)
		-- (its place in its own scaled units: under the label and the button)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", canvas, "TOPLEFT", G.pad / scale, -(G.raidY + 30) / scale)
		for i, f in ipairs(group) do
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (db.width + 8), 0)
		end
	end
	FitGroup()
	-- (designing the normal party frames: their replicas in place of the group)
	local partyRow = CreateFrame("Frame", nil, canvas)
	partyRow:SetSize(1, 1)
	local party = {}
	for i = 1, 4 do
		party[i] = PartyReplica(partyRow, i + 1)
	end
	local function FitParty()
		local scale = math.min(1, (width - 2 * G.pad) / (4 * PARTY_SIZE.w + 3 * 8), G.groupH / PARTY_SIZE.h)
		partyRow:SetScale(scale)
		partyRow:ClearAllPoints()
		partyRow:SetPoint("TOPLEFT", canvas, "TOPLEFT", G.pad / scale, -(G.raidY + 30) / scale)
		for i, f in ipairs(party) do
			if f then
				f:ClearAllPoints()
				f:SetPoint("TOPLEFT", partyRow, "TOPLEFT", (i - 1) * (PARTY_SIZE.w + 8), 0)
			end
		end
	end
	local show = W.Button(canvas, TEXT.show, 220, nil, { height = 22 })
	show:SetPoint("LEFT", raidLabel, "RIGHT", 16, 0)
	show:HookScript("OnClick", function()
		local Pv = MelloUI.Preview
		if Pv and Pv.Start then
			local ok, why = Pv:Start("party", "raid")
			if not ok and why == "combat" then
				MelloUI:Print(Pv.TEXT.inCombat)
			end
		end
	end)
	show:HookScript("OnEnter", function(self)
		W.ShowTooltip(self, TEXT.show, TEXT.showTip)
	end)
	show:HookScript("OnLeave", W.TipLeave)

	-- the canvas's refresh: the list, the picked one's controls, the samples
	function canvas.Refresh()
		local spec, specLabel = RD:Spec()
		if spec ~= P.spec then
			P.spec, P.ind = spec, nil
		end
		local list = RD:List(Key())
		local found = false
		for _, ind in ipairs(list) do
			if ind == P.ind then
				found = true
			end
		end
		if not found and not P.part then
			P.ind = list[1]
		end
		title:SetText(string.format(P.kind == "party" and TEXT.partyList or TEXT.list, specLabel))
		raidLabel:SetText(P.kind == "party" and TEXT.partyGroup or TEXT.group)
		controls.kind:Refresh()
		for i, r in ipairs(rows) do
			local ind = list[i]
			r.ind = ind
			if ind then
				r.icon:SetTexture(ind.kind == "buff" and (RD:SpellIcon(ind) or "Interface\\Icons\\INV_Misc_QuestionMark") or KIND_ICON)   -- look-ok: a spell not known yet
				r.name:SetText(Name(ind))
				r.look:SetText((RD.LOOK[ind.look] or RD.LOOKS[1]).label)
				r.sel:SetShown(ind == P.ind)
				r:Show()
			else
				r:Hide()
			end
		end
		copy:SetValues(RD:SpecValues())
		for _, b in ipairs(chips) do
			b:SetShown(b.kind == P.kind)
			for _, e in ipairs(b.mark) do
				e:SetShown(b.key == P.part)
			end
		end
		local ind = P.ind
		none:SetShown(ind == nil and P.part == nil)
		body:SetShown(ind ~= nil)
		partBody:SetShown(P.part ~= nil)
		if P.part then
			partHeading:SetText(Parts.BY[P.part].label)
			for _, c in pairs(partControls) do
				if c.Refresh then
					c:Refresh()
				end
			end
		end
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
		-- the samples: your frame and the group (or the party's replicas) as the
		-- frames are now (their size, colours, parts), everything on the big
		-- one, a mix on the others
		local partyKind = P.kind == "party" and bigParty ~= nil
		bigGroup:SetShown(not partyKind)
		if bigParty then
			bigParty:SetShown(partyKind)
		end
		row:SetShown(not partyKind)
		partyRow:SetShown(partyKind)
		if partyKind then
			big = bigParty
			Parts:Lay(bigParty, "party", true)
			FitBig()
			SampleMarks(bigParty, list, 0.6, nil, MarkMouse)
			FitParty()
			for i, f in ipairs(party) do
				if f then
					Parts:Lay(f, "party", true)
					SampleMarks(f, list, SAMPLE_MEMBERS[(i % #SAMPLE_MEMBERS) + 1].frac, function(j, e)
						return e.kind == "buff" and (i + j) % 2 == 0 or (e.kind == "debuff" and i == 2)
					end)
				end
			end
		else
			big = bigGroup
			Resample(bigGroup)
			FitBig()
			SampleMarks(bigGroup, list, 0.6, nil, MarkMouse)
			FitGroup()
			for i, f in ipairs(group) do
				Resample(f)
				SampleMarks(f, list, SAMPLE_MEMBERS[i].frac, function(j, e)
					return e.kind == "buff" and (i + j) % 2 == 0 or (e.kind == "debuff" and (i == 2 or i == 5))
				end)
			end
		end
	end
	canvas:Refresh()
	-- the list changed elsewhere (another spec, the ranks found): drawn again
	MelloUI:On("groupframes", function(what)
		if canvas:IsVisible() and (what == "spec" or what == "ids" or what == "part") then
			canvas:Refresh()
		end
	end, "GroupFrames.page")
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
			x, y = at * (db.width + db.spacing), -line * (db.height + (db.raidGap or 0))
		else
			x, y = line * (db.width + (db.raidGap or 0)), -at * (db.height + db.spacing)
		end
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", h, "TOPLEFT", x, y)
		SampleMarks(f, list, f.sample.frac, function(j, e)
			return e.kind == "buff" and (n + j) % 2 == 0 or (e.kind == "debuff" and n % 4 == 2)
		end)
	end
	h:Show()
end

local function FakeHit(n)
	for i, f in ipairs(fake.frames) do
		local wave = (n or 0) <= 8 and (n or 0) / 8 or math.max(0, (12 - n) / 4)
		f.sample.health = math.max(0.05, (f.base or 1) - 0.35 * wave * ((i % 3) + 1) / 3)
		Button.Health(f)
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
		return
	end
	if not (RD.module.isEnabled and Pv and Pv:Plays("raid")) then
		return
	end
	if beat == "start" then
		FakeShow()
	elseif beat == "hit" then
		FakeHit(n)
	end
end

function Page.Listen()
	if not listening then
		listening = true
		MelloUI:On("preview", PreviewBeat, "GroupFrames.fake")
	end
end
