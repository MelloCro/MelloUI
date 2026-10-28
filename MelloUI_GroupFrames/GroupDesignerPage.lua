--------------------------------------------------------------------------------
-- MelloUI - Group Frames: your indicators and the designer stage (one look
-- C10; it was the Designer, the picked sketch raid_designer_page.jpg)
--
--   Your Indicators   the canvas row on the Unit & Group Frames designer's
--                Party and Raid frames (their Indicators part): since 1.2.4
--                the spell groups' tray and block (GroupSpellGroupsPage.lua),
--                which replaced the single-spell list; the helpers it shares
--                (Page.Label, Box, Choices, Spots, Name) and the fake raid
--                and party on screen are here.
--   the stage    the 'raidframe' kind of the configurator's designer stage
--                (below): your frame large, its parts and indicators dragged,
--                sized and picked there.
-- Made with the page (the Configurator's first open of it), never at login.
--   Page.Build(canvas, width)   a canvas's content: the spell groups' page
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local W = MelloUI.Widgets
local RD = ns.RD
local Looks = ns.Looks

local Page = {}
ns.Page = Page
RD.Page = Page   -- (the tests')

local PartyReplica   -- (below: the normal party member's replica)

local TEXT = {
	unnamed = "Spell %s",
}

-- the place grid's measures (Spots: the spell groups' page uses it too)
local G = { spot = 13, spotGap = 3 }

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
	if ind.kind == "group" and ns.SpellGroups then
		return ns.SpellGroups.Label(ind)
	end
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

-- (the spell groups' page, GroupSpellGroupsPage.lua: the same helpers)
Page.Label, Page.Box, Page.Choices, Page.Spots, Page.Name = Label, Box, Choices, Spots, Name
Page.samples = setmetatable({}, { __mode = "v" })   -- [stage pick] = its big sample (a drop's target)

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

-- (laid by the raid's parts: 1.2.4, one look for the raid and a party in raid frames)
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

-- (1.2.4, retail's preview update; the user, 2026-10-24: the preview "a accurate representation of the actual
-- unitframes") the members' aura row as it shows: their debuffs (the game's row shows debuffs only)
local SAMPLE_AURAS = { "Interface\\Icons\\Spell_Shadow_ShadowWordPain",   -- look-ok: a sample's auras
	"Interface\\Icons\\Spell_Shadow_CurseOfTounges" }   -- look-ok: a sample's auras

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
		c:SetSize(#SAMPLE_AURAS * 15 + (#SAMPLE_AURAS - 1) * 2, 15)
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
		local bar = rawget(f, "healthBar") or (rawget(f, "HealthBarContainer") and f.HealthBarContainer.HealthBar)
		if ind.kind == "group" and Page.SampleGroup then
			-- (a spell group's made-up members of the group, laid its way)
			Page.SampleGroup(f, m, ind, frac, Looks.Fill(bar))
		else
			if m.items and Page.HideItems then
				Page.HideItems(m)
			end
			m.p.tint:SetDrawLayer(health and "BORDER" or "OVERLAY", health and 4 or 0)
			Looks.Lay(m.b, m.p, ind, f, Looks.Fill(bar))
			Looks.Sample(m.b, m.p, ind, frac)
		end
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
-- play -- the raid's (a party in raid frames shows it too), or the party
-- frames with portraits' own -- and the picked one's settings. Its place and
-- size are the designer stage's too (drag it there); a pick here picks it there.
--------------------------------------------------------------------------------

-- every canvas on show (one per frame's Indicators part), by its canvas
Page.canvases = setmetatable({}, { __mode = "k" })   -- [canvas] = { canvas, el, kind, spec, ind, Pick }

-- the list a canvas shows: Raid's the raid frames' (the party's too in them), Party's the portraits' own (1.2.4)
local function KindOf(inst)
	return inst.el == "raid" and "group" or "party"
end
Page.KindOf = KindOf

-- the canvas: the spell groups' tray and block (1.2.4, GroupSpellGroupsPage.lua, loaded after this file; the
-- single-spell list it replaced is gone)
function Page.Build(canvas, width)
	return Page.BuildGroups(canvas, width)
end

--------------------------------------------------------------------------------
-- The fake raid on screen (the Preview's Raid Fight, or its part "raid"
-- alone): the samples where your raid frames stand, hurt and healed with the
-- scene, until it stops
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
			return e.kind == "group" or e.kind == "buff" and (n + j) % 2 == 0 or (e.kind == "debuff" and n % 4 == 2)
		end)
	end
	h:Show()
end

-- (one look, F-v3's needs_user 7, the user's yes) the made-up party in raid frames (the Party Fight while your party
-- wears the raid frames, fr-04; or that part alone): the made-up four (Preview.PARTY) where your party's members
-- stand -- after your own frame while the header shows you (you while solo), as a party's members stand after you --
-- in its growth and spacing, hung from the plate's corner as the header is (its top right while Flip Horizontally
-- mirrors the party: fr-03), in the raid frames' look and with their indicators (1.2.4: one look for both)
local fakeParty = { holder = nil, frames = {} }
local FAKE_PARTY = 4
local GROW = { DOWN = { 0, -1, "TOPLEFT" }, UP = { 0, 1, "BOTTOMLEFT" }, RIGHT = { 1, 0, "TOPLEFT" },
	LEFT = { -1, 0, "TOPRIGHT" } }
local MIRROR = { TOPLEFT = "TOPRIGHT", TOPRIGHT = "TOPLEFT", BOTTOMLEFT = "BOTTOMRIGHT", BOTTOMRIGHT = "BOTTOMLEFT" }

local function FakePartyShow()
	if not fakeParty.holder then
		fakeParty.holder = CreateFrame("Frame", "MelloUIGroupFramesFakeParty", UIParent)
		fakeParty.holder:SetFrameStrata("MEDIUM")
	end
	local h = fakeParty.holder
	local db = RD.DB()
	local g = GROW[db.partyGrowth or "DOWN"] or GROW.DOWN
	local H = ns.Headers
	local sp = H and H.Spacing and H.Spacing("party") or db.spacing or 0
	-- (your own frame in the header now: the first place is yours)
	local header = H and H.headers and H.headers.party
	local you = header and header:GetAttribute("child1")
	local skip = (you and you:IsVisible()) and 1 or 0
	local slots = skip + FAKE_PARTY
	-- (the block the header lays, held by the same corner)
	local across = g[1] ~= 0
	h:SetSize(across and (slots * db.width + (slots - 1) * sp) or db.width,
		across and db.height or (slots * db.height + (slots - 1) * sp))
	local corner = g[3]
	if H and H.Corner and H.Corner("party") == "TOPRIGHT" then
		corner = MIRROR[corner] or corner
	end
	h:ClearAllPoints()
	local party = H and H.containers and H.containers.party
	if party then
		h:SetPoint(corner, party, corner, 0, 0)
	elseif H and H.Home then
		H.Home("party")(h)
	end
	local list = RD:List()
	for n = 1, FAKE_PARTY do
		local f = fakeParty.frames[n]
		if not f then
			f = SampleFrame(h, Member(n))
			f.base = f.sample.health
			fakeParty.frames[n] = f
		else
			Resample(f)
		end
		local at = n - 1 + skip
		f:ClearAllPoints()
		f:SetPoint(g[3], h, g[3], g[1] * at * (db.width + sp), g[2] * at * (db.height + sp))
		SampleMarks(f, list, f.sample.frac, function(j, e)
			return e.kind == "group" or e.kind == "buff" and (n + j) % 2 == 0 or (e.kind == "debuff" and n % 4 == 2)
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
		if ns.Headers and ns.Headers.Aside then
			ns.Headers.Aside(false)
		end
		return
	end
	-- (the scene's own, Core/Preview.lua's Plays: the made-up raid in the Raid Fight, the party in raid frames in the
	-- Party Fight while that is the look your party wears -- or either one played alone)
	local raid = Pv and Pv:Plays("raid")
	local party = Pv and Pv:Plays("groupparty")
	if not (RD.module.isEnabled and (raid or party)) then
		return
	end
	if beat == "start" then
		if raid then
			-- (your own frame in the party's place away, as in a raid)
			if ns.Headers and ns.Headers.Aside then
				ns.Headers.Aside(true)
			end
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
-- wide stage) -- our raid frames ("raid": the raid's, and a party's in raid
-- frames, 1.2.4) and the game's normal party frames ("portrait": Party's,
-- asleep while the party wears the raid frames), each laid by its own parts
-- layout (GroupParts.lua) and showing its own indicator list.
-- Registered at load (tables only); its samples made by the stage that shows
-- them. Parts: the frame's (name, health text, icons: placed, sized, shown),
-- the bars (picked for their colours, never moved), each indicator of the
-- list (placed, sized, its look from its list; a bar by its edges, a health
-- tint locked). Nothing reads a unit but the class (RD:Class: pcall).
--------------------------------------------------------------------------------

local Stage = {
	LAYOUT = { raid = "raid", portrait = "portrait" },
	LIST = { raid = "group", portrait = "party" },
	MOVER = { raid = "GroupFramesRaid", portrait = "GroupFramesParty" },
	BAR_SPOTS = { "TOPLEFT", "TOP", "TOPRIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
	SIDE_SPOTS = { "LEFT", "RIGHT" },
	BAR_PLUS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
	BARS = { { key = "bar.health", label = "Health bar", field = "healthBar" },
		{ key = "bar.power", label = "Power bar", field = "powerBar" },
		{ key = "bar.background", label = "Background", field = "background" } },
	TEXT = { empty = "Switch on Group Frames first.", healthLocked = "It tints the health bar: nothing to move.",
		home = "Default place", gameHome = "The game's place",
		raidLook = "Your party uses the raid frames: their look is set on Raid." },
	TRY_TYPES = { dropdown = true, picture = true },
	-- (F-v3's F5b, shell-plan 6.1 item 5: "Normal | Dead / Offline") the state chips over your own frames' picks:
	-- the member as it is, or fallen -- the health text's Dead word and the grey, as a real member shows them; the
	-- Status text part (ConfigLayout's `state`) is picked only then (the Portraits pick: the game's, no chips)
	STATES = { { key = "normal", label = "Normal" }, { key = "down", label = "Dead / Offline" } },
	cache = {},   -- [pick] = { list = {}, frame = { [key] = part }, ind = { [ind] = part } (weak) }
	EMPTY = {},
}

function Stage.Main(stage, pick)
	if pick == "portrait" then
		local r = PartyReplica(stage.holder, 1, true)
		Page.samples[pick] = r
		return r
	end
	-- (made-up states on the big one: ready, a mark, a role; your class)
	local s = Member(1)
	s.class = RD:Class()
	s.health, s.frac, s.power = 0.85, 0.6, 0.7
	s.mark, s.ready, s.role = 1, "ready", s.role or "HEALER"
	local f = SampleFrame(stage.holder, s)
	Page.samples[pick] = f
	return f
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
		f:SetAlpha(Stage.Dim(pick) and Stage.ASLEEP_ALPHA or 1)
		return
	end
	local s = f.sample
	if s then
		s.dead, s.offline = ctx.state == "down", false
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

function Stage.Refresh(stage)
	-- (the state chips over your own frames only: the Portraits pick is the game's frame)
	if stage.chips then
		stage.chips:SetShown(stage.pick ~= "portrait")
	end
end

-- (1.2.4; the user, 2026-10-28: "if the Person selects that he wants to see the Raid Frames, then he should get the
-- Look under the "Raid" category") Party's portraits asleep while the party wears the raid frames: the sample faded
-- (Paint: the sample alone -- the stage's own ground stays whole, so the rows it is pinned over never show through
-- it) and this line its caption (Empty)
Stage.ASLEEP_ALPHA = 0.4
function Stage.Dim(pick)
	if pick == "portrait" and RD.module.isEnabled and RD.DB().partyStyle ~= "party" then
		return Stage.TEXT.raidLook
	end
	return nil
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

-- (1.2.4) a part's place as the portraits stand: Unit Frames' Flip Horizontally mirrors them, so their places show
-- and are taken turned round, and are kept the game's way round (Modules/UnitFrames.lua M:MirrorPlace)
function Stage.AsShown(layout, t)
	if layout ~= "portrait" then
		return t
	end
	local uf = MelloUI:GetModule("UnitFrames")
	if uf and uf.PartyFlipped and uf.MirrorPlace and uf:PartyFlipped() then
		return uf:MirrorPlace(t)
	end
	return t
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
			return Stage.AsShown(layout, Parts:Of(p.key, layout))
		end, set = function(_, t)
			Parts:Place(layout, p.key, Stage.AsShown(layout, t))
		end },
		home = function()
			return Stage.AsShown(layout, Parts:Shown(p.key, layout))
		end,
		size = p.sizes and { min = p.sizes.min, max = p.sizes.max, step = 1 }   -- (a part's own range)
			or { min = text and sizes.textMin or sizes.iconMin, max = text and sizes.textMax or sizes.iconMax, step = 1 },
		hide = true,
		homeLabel = layout == "portrait" and Stage.TEXT.gameHome or Stage.TEXT.home,
		content = p.key == "health" and Stage.HealthContent() or nil,
	}
end

-- (1.2.4; the user, 2026-10-24: the indicators' fonts sized "on the stage itself") an indicator's own texts -- the
-- time and the stacks -- as rows on the Indicators tab, under the stage: the picked indicator's, shown and sized,
-- the same values as its Time and Stacks in the settings below (ind.text, ind.count)
Stage.IND_TEXTS = {
	{ key = "text", label = "Time", field = "textSize", showField = "textShow", min = RD.SIZE.textMin,
	  max = RD.SIZE.textMax,
	  get = function(ind) return type(ind.text) == "table" and ind.text.size or RD.SIZE.text end,
	  shown = function(ind) return type(ind.text) == "table" and ind.text.show end },
	{ key = "count", label = "Stacks", field = "countSize", showField = "countShow", min = RD.SIZE.textMin,
	  max = RD.SIZE.textMax,
	  get = function(ind) return type(ind.count) == "table" and ind.count.size or RD.SIZE.text end,
	  shown = function(ind) return type(ind.count) == "table" and ind.count.show end },
}
-- the Indicators tab's template (ConfigPreview's `templates`): its texts' rows only (the size and the place: the
-- stage's wheel and drag, and the settings below), first on the tab -- in General, over the list -- so they stand
-- right under the stage
Stage.IND_TEMPLATE = { key = "ind:", label = "Indicators", class = "indicator", drag = false, texts = Stage.IND_TEXTS,
	textsSection = "General" }

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
		-- (its time and stacks, shown and sized: the Indicators tab's rows, Stage.IND_TEXTS)
		for _, d in ipairs(Stage.IND_TEXTS) do
			local sub = ind[d.key]
			local v = tonumber(t[d.field])
			if v and type(sub) == "table" then
				sub.size = v
			end
			if type(t[d.showField]) == "boolean" and type(sub) == "table" then
				sub.show = t[d.showField]
			end
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
	-- (a spell group's place is where its first icon stands, Looks.Pin: a drop reads that icon)
	part.lead = function(_, region, f)
		for _, m in ipairs(f and f.marks or Stage.EMPTY) do
			if m.b == region then
				local first = m.items and m.items[1]
				return first and first.b:IsShown() and first.b or nil
			end
		end
		return nil
	end
	part.store = { get = function()
		return ind
	end, set = Stage.SetInd }
	part.texts = Stage.IND_TEXTS
	-- (1.2.4; the user, 2026-10-26: right-clicking a group on the preview to "Remove the whole group") the right-click
	-- list's Remove: taken off the frame, as the page's Remove button does
	part.remove = function()
		RD:Remove(ind, part.listKey)
	end
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
	for _, part in ipairs(Stage.Parts(pick or "raid")) do
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

-- the stage's caption when it has nothing to pick: Group Frames off, or (1.2.4) the portraits asleep
function Stage.Empty(pick)
	return not RD.module.isEnabled and Stage.TEXT.empty or Stage.Dim(pick)
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
			picks = { raid = true, portrait = true }, first = "raid",
			watch = { GroupFrames = true, BarTextures = true, Fonts = true, UnitFrames = true },
			topics = { "groupframes" },
			reset = { { "GroupFrames", "parts" } },
			Main = Stage.Main, Refresh = Stage.Refresh, Paint = Stage.Paint,
			parts = Stage.Parts, PartKeys = Stage.PartKeys, Tries = Stage.Tries, Empty = Stage.Empty, states = Stage.STATES,
			Moved = Stage.Moved, ResetAll = Stage.ResetAll, mover = Stage.Mover, OnSelect = Stage.OnSelect,
			templates = { ["ind:"] = Stage.IND_TEMPLATE },
		})
	end
end
Page.Stage = Stage
