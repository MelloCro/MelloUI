--------------------------------------------------------------------------------
-- MelloUI - Loot Roll Window (2.1.61)
--
-- The user, 2026-11-20: "We need a redesign of the OldSchool Loot Roll Window, currently its attached by the Widget,
-- but i need to see this data, Which Loot Dropped, who has rolled what and what roll they got, your own options to
-- roll and the overall default Functionality ... then we can add an animation after somebody wins the Item, that the
-- icon Flys onto its Unitframe, but also make sure that this new Loot Window also has the same function to highlight
-- when a favorited item drops"; to the sketch (BuildData/output/oldschool_loot_roll_sketch): "B Looks good, how do we
-- go about up to 40 man raid?", "Sketch it first", "Yes, build it"; then "After you are done with oldschool, then
-- adjust for the other 2 themes aswell".
--
-- The group loot rolls in a window of their own, take B (the open row), in place of the widget column's loot rows:
--   a row     the item in a ring (a thin ring of its quality's colour inside it), its name in that colour; under it
--             who leads (the game's own numbers, live) or how many picked -- in a raid the leader and the counts by
--             kind; your three buttons (Need, Greed, Pass: the game's icons) that give way to your choice and number;
--             the time left as the gold line under the row
--   the open row   one row opens into a table of every roll: Need then Greed, high to low, each with its number; in
--             a raid (past 10) the passes and the undecided folded into a line each (point at the passes for their
--             names); at most 8 lines, scrolled by the wheel, your line kept in sight on the last place with your rank.
--             Opens: a row you click, else a favourite, else the first you have not answered, else the first
--   a favourite    an item on your Dungeon Info list: the star on its ring, the rays once, the ring lit, Need lit,
--             "On your list", the picked row's ground
--   the win   the row names the winner (their line gold, the star), then the item flies to their unit frame
--             (MelloUI.FrameFX's item flight, FX.Loot, to FX.FrameOf) and stays beside it two seconds; the row folds
--             away and the next roll takes its place. Reduce Motion: no flight, the item beside the frame
-- Four rows at a time; more wait ("+N more waiting").
-- Master Loot (the user: "how do we handle the "Master Loot" option?", "Sketch 1 and 2", "Yes build both"):
--   everyone     the header names the loot master; an item handed out shows as a row, "Given to Kaelith", and flies to
--                that player's frame (found in the loot history -- a drop won with no roll -- or, failing that, the
--                game's "receives loot" chat line)
--   the master   the items on the boss at or over the threshold, a row each, with Roll (the game's Request Roll: a
--                normal roll for everyone, its row then shows it -- told apart by the item's own link, then by its drop's
--                place) and Assign (the raid by group or class, a search; MelloUI's question; then the flight)
--
-- One reader of the rolls (MelloUI.LootRolls, Modules/Widgets.lua: the game's roll calls and its loot history; the
-- bus's 'lootrolls' says what changed); while this window shows them the column has no loot rows. In every look, each
-- its dress (R.Dress): Oldschool's frame set (its own file, MelloUI_Oldschool/Modules/LootRollWindowPainted.lua),
-- else MelloUI's own panel and gold ring (R.plain: Modern, and the Default skin's game art through the same pieces).
--
-- Nothing at login: the window and its rows are made at the first roll (or when Edit Layout opens, for its plate).
-- Plain frames only: rolling is no protected call, so the window works in a fight. The game's Gamepad UI keeps the
-- game's own boxes (MelloUI.LootRolls.On).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local W = MelloUI.Widgets
local Anim = MelloUI.Anim
local Safe = MelloUI.Safe
local Secret, Num, Text = Safe.IsSecret, Safe.Number, Safe.Text
local max, min, floor = math.max, math.min, math.floor

local ICON = { need = "Interface\\Buttons\\UI-GroupLoot-Dice-Up", greed = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
	pass = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" }
local ROLL_OF = { need = 1, greed = 2, pass = 0 }
local KINDS = { "need", "greed", "pass" }
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local TEXT = {
	title = "Loot Rolls", items = "%d items", item = "1 item", waiting = "+%d more waiting",
	picked = "%d of %d picked", mine = "On your list", wins = "%s wins", youWin = "You win", passedAll = "Everyone passed",
	passed = "%d passed", deciding = "%d deciding", decidingOne = "deciding", names = "point for names", you = "You",
	need = "Need", greed = "Greed", pass = "Pass", needDesc = "Roll for it as Need.", greedDesc = "Roll for it as Greed.",
	passDesc = "Pass on it.", noNeed = "You cannot roll Need on this.", noGreed = "You cannot roll Greed on this.",
	rank = "#%d",
	-- (Master Loot)
	master = "Master Loot", masterOf = "Master Loot \194\183 %s", onBoss = "On the boss \194\183 not given yet",
	roll = "Roll", assign = "Assign", rolling = "Rolling", givenTo = "Given to %s", givenYou = "Given to you",
	givenBy = "Given by %s, the loot master", givenByAny = "Given by the loot master", give = "Give", giveAsk = "Give %s to %s?", byGroup = "By group",
	byClass = "By class", rollDesc = "Starts a roll for it: Need, Greed or Pass for everyone who can use it.",
	assignDesc = "Give it to a player of your choice.",
	cantGive = "The game keeps this for its own menu here: right-click the item in the loot window.",
}

-- the window's numbers (UI units: the sketch's, one a pixel at 1920 x 1080) and its state; one table, so no file local
-- is spent on each
local R = {
	W = 424, HEAD = 40, ROW = 46, LINE = 19, CAP = 8, FOOT = 26, BOTTOM = 12, SHOWN = 4, BIG = 10,
	HR = 13, BTN = 25, STEP = 31, NAME_X = 74, MEDAL_X = 42, CAND_X = 58,
	HOLD = 0.6,          -- the winner named, then the flight
	LINGER = 2,          -- the item beside the winner's frame
	AFTER_WIN = 2.4,     -- the row stays this long after the win, then folds
	PASSED = 2,          -- "Everyone passed" this long
	NO_WINNER = 4,       -- a roll over with no winner in the history: folded this long after
	FOLD_A = 0.25, FOLD_H = 0.35,
	RAYS_K = 2.2, RAYS_T = 1.2,   -- the favourite's rays: how far they grow, how long
	KEY = "MelloUILootRolls",
	rows = {},           -- the rolls shown or waiting, in the order they came
	byId = {},           -- [roll ID] = row
	pool = {},           -- row frames not in use
	scroll = 0,
	painted = nil,       -- Oldschool's dress (R.SetDress, from its own file)
	worn = nil,          -- the dress laid on the window now
}
MelloUI.LootRollWindow = R

local function L()
	return MelloUI.LootRolls
end

-- the window shows the rolls: MelloUI's to show (Loot Rolls on, not the Gamepad UI) -- in every look, each its dress
function R.Active()
	local rolls = L()
	return rolls ~= nil and rolls.On()
end

-- MelloUI's own dress (Modern, and the Default skin: the panel, its rim and the round icons' ring follow the skin
-- themselves -- MelloUI.Skin): the windows' panel (W.Panel: its fill, its gold hairline, the gold rim round it --
-- none while Oldschool's frame set dresses it), the round icons' gold ring round each item, the set's loot mark
R.plain = { MARK = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\chat_loot",
	RIM = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\ring_gold", OPENING = 0.775 }

local function PanelShown(frame, on)
	if frame.panelFill then
		frame.panelFill:SetShown(on)
	end
	local edges = frame.panelEdges
	if type(edges) == "table" then
		for _, t in pairs(edges) do
			if type(t) == "table" and t.SetShown then
				t:SetShown(on)
			end
		end
	end
end

function R.plain.On()
	return true
end

function R.plain.Shell(frame, mark)
	if not frame.panelFill then
		W.Panel(frame, { on = true, rim = "effects" })
	end
	PanelShown(frame, true)
	if mark then
		MelloUI.Icons.Set(mark, R.plain.MARK, 18)
	end
end

function R.plain.Off(frame)
	PanelShown(frame, false)
end

function R.plain.Ring(tex, hr)
	local size = hr * 2 / R.plain.OPENING
	MelloUI.Icons.Set(tex, R.plain.RIM, size)   -- (its sharp copy for the size: the helper sets its part of the sheet)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", tex:GetParent(), "CENTER", 0, 0)
	tex:SetSize(size, size)
	tex:Show()
end

-- the dress the window wears now: Oldschool's while its reskin dresses, else MelloUI's own
function R.Dress()
	local d = R.painted
	if d and d.On() then
		return d
	end
	return R.plain
end

local function Tr(s)
	return W.Tr and W.Tr(s) or s
end

local function Hex(colour, fallback)
	if type(colour) == "table" and colour.GenerateHexColor then
		local ok, h = pcall(colour.GenerateHexColor, colour)
		if ok and type(h) == "string" then
			return h
		end
	end
	return fallback
end

-- the kinds' colours: the game's own (Need its gold, Greed its light blue, Pass its red)
local function KindHex(kind)
	if kind == "need" then
		return Hex(_G.NORMAL_FONT_COLOR, "ffffd100")
	elseif kind == "greed" then
		return Hex(_G.LIGHTBLUE_FONT_COLOR, "ff88aaff")
	end
	return Hex(_G.RED_FONT_COLOR, "ffff2020")
end

local function ClassHex(class)
	local C = MelloUI.Colours
	return C and C.ClassHex and C.ClassHex(class) or "ffffffff"
end

local function Mark(kind, size)
	return "|T" .. ICON[kind] .. ":" .. size .. ":" .. size .. "|t"
end

local function TipHide()
	GameTooltip:Hide()
end

local function Paint(region, key, how)
	W.Paint(region, key, how or "text")
end

--------------------------------------------------------------------------------
-- The rolls read (MelloUI.LootRolls) into the rows
--------------------------------------------------------------------------------

local function NewRow(id, entry)
	local rolls = L()
	local icon, name, count, quality, canNeed, canGreed, link = rolls.Info(id)
	local row = { id = id, icon = icon, name = name, count = count, quality = quality or 1, canNeed = canNeed,
		canGreed = canGreed, link = link, startAt = entry.startAt, total = entry.total, picks = { n = 0 },
		fav = rolls.Mine(id) == true, born = GetTime() }
	R.rows[#R.rows + 1] = row
	R.byId[id] = row
	return row
end

-- the drop's state on the row: the picks, your answer if the game has it, the winner, everyone passed
local function ReadDrop(row)
	if row.test then
		return   -- (a test row: its picks come from the test, R.Test)
	end
	local rolls = L()
	if row.master and not row.rolling and not row.rollId then
		return   -- (the loot master's item still on the boss: no roll asked for yet)
	end
	if row.ml then
		return   -- (an item handed out: its winner is known)
	end
	local d = rolls.Drop(row.id, row.link)
	row.drop = d ~= nil
	rolls.Picks(d, row.picks)
	for i = 1, row.picks.n do
		local p = row.picks[i]
		if p.self and p.kind ~= "wait" and not row.you then
			row.you, row.youAt = p.kind, GetTime()
		end
	end
	if type(d) ~= "table" then
		return
	end
	local w = d.winner
	if not row.winner and type(w) == "table" and not Secret(w) then
		local name = Text(w.playerName)
		if name then
			local kind, roll = nil, Num(w.roll)
			for i = 1, row.picks.n do
				local p = row.picks[i]
				if p.name == name then
					kind = p.kind
					roll = roll or p.roll
				end
			end
			row.winner = { name = name, class = Text(w.playerClass), self = not Secret(w.isSelf) and w.isSelf == true,
				kind = kind, roll = roll }
		end
	end
	if not Secret(d.allPassed) and d.allPassed == true then
		row.allPassed = true
	end
end

-- what the game told: a roll began, ended (CANCEL_LOOT_ROLL: everyone answered or the time ran out) or all ended
function R.Heard(event, id)
	if event == "CANCEL_LOOT_ROLL" and id and R.byId[id] then
		R.byId[id].ended = R.byId[id].ended or GetTime()
	elseif event == "CANCEL_ALL_LOOT_ROLLS" then
		for _, row in ipairs(R.rows) do
			row.ended = row.ended or GetTime()
		end
	end
	R.Want()
end

-- one pass a frame however many events came (a raid's forty picks in a breath)
function R.Want()
	if R.wanted then
		return
	end
	R.wanted = true
	C_Timer.After(0, R.Run)
end

function R.Run()
	R.wanted = false
	if not R.Active() then
		R.Hide()
		return
	end
	local list, n = L().List()
	for i = 1, n do
		local e = list[i]
		if not R.byId[e.id] and not R.Adopt(e) then
			NewRow(e.id, e)
		end
	end
	R.GivenFromHistory()
	if #R.rows == 0 then
		R.Hide()
		return
	end
	local now = GetTime()
	for _, row in ipairs(R.rows) do
		ReadDrop(row)
		-- (a roll the game no longer lists and you did not answer here: over -- a reload, another window's answer)
		if not row.ended and row.startAt and now > row.startAt + (row.total or 60) + 1 then
			row.ended = now
		end
		if row.winner and not row.wonAt then
			row.ended = row.ended or now
			R.Win(row)
		elseif row.ended and row.allPassed and not row.passedAt then
			row.passedAt = now
			C_Timer.After(R.PASSED, function()
				R.Fold(row)
			end)
		elseif row.ended and not row.winner and not row.allPassed and not row.lost then
			row.lost = true
			C_Timer.After(R.NO_WINNER, function()
				if not row.wonAt and not row.passedAt then
					R.Fold(row)
				end
			end)
		end
	end
	R.Build()
	R.Layout()
end

--------------------------------------------------------------------------------
-- The window (made at the first roll)
--------------------------------------------------------------------------------

-- its standard place: the left of the screen, between the party frames and your character
local function Home(f)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 290, -372)
	return true
end

local function Button(parent, kind)
	local b = W.RoundIcon(parent, R.BTN, ICON[kind])
	b:SetKit(false)
	b.kind = kind
	b.lit = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
	b.lit:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.lit:SetSize(R.BTN * 2, R.BTN * 2)
	b.lit:SetTexture(MelloUI.FrameFX.Art("glow_white.tga"))
	b.lit:SetBlendMode("ADD")
	Paint(b.lit, "selectedTrim", "vertex")
	b.lit:Hide()
	b:SetScript("OnClick", function(self)
		local row = self:GetParent().row
		if row then
			R.Answer(row, self.kind)
		end
	end)
	b:SetScript("OnEnter", function(self)
		local row = self:GetParent().row
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		local k = self.kind
		local can = not row or (k == "need" and row.canNeed) or (k == "greed" and row.canGreed) or k == "pass"
		GameTooltip:SetText(Tr(TEXT[k]))
		GameTooltip:AddLine(Tr(can and TEXT[k .. "Desc"] or (k == "need" and TEXT.noNeed or TEXT.noGreed)), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", TipHide)
	return b
end

-- a row's frame: its ground, the medal (the item in its ring), the star, the rays, the texts, the three buttons, your
-- choice's chip, the time's line
local function MakeRow()
	local f = CreateFrame("Button", nil, R.body)
	f:SetHeight(R.ROW)
	f:RegisterForClicks("LeftButtonUp")
	f:SetScript("OnClick", function(self)
		if self.row then
			R.openId = self.row.id
			R.scroll = 0
			R.Layout()
		end
	end)
	f.ground = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.ground:SetTexture("Interface\\Buttons\\WHITE8X8")
	f.ground:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -2)
	f.ground:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 2)
	-- the medal: a dark disc, the quality's disc a little wider (its thin ring), the icon, the look's ring over them
	local m = CreateFrame("Button", nil, f)
	m:SetSize(R.HR * 2, R.HR * 2)
	m:SetPoint("CENTER", f, "TOPLEFT", R.MEDAL_X, -23)
	m:SetFrameLevel(f:GetFrameLevel() + 2)
	m.mask = m:CreateMaskTexture()
	m.mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	m.mask:SetPoint("CENTER")
	m.mask:SetSize((R.HR + 1.6) * 2, (R.HR + 1.6) * 2)
	m.qual = m:CreateTexture(nil, "BACKGROUND", nil, 1)
	m.qual:SetTexture("Interface\\Buttons\\WHITE8X8")
	m.qual:SetAllPoints(m.mask)
	m.qual:AddMaskTexture(m.mask)
	m.imask = m:CreateMaskTexture()
	m.imask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	m.imask:SetPoint("CENTER")
	m.imask:SetSize(R.HR * 2, R.HR * 2)
	m.disc = m:CreateTexture(nil, "BACKGROUND", nil, 2)
	m.disc:SetTexture("Interface\\Buttons\\WHITE8X8")
	m.disc:SetAllPoints(m.imask)
	m.disc:AddMaskTexture(m.imask)
	Paint(m.disc, "innerPanel", "vertex")
	m.icon = m:CreateTexture(nil, "ARTWORK")
	m.icon:SetPoint("CENTER")
	m.icon:SetSize(R.HR * 2.3, R.HR * 2.3)
	m.icon:AddMaskTexture(m.imask)
	m.ring = m:CreateTexture(nil, "OVERLAY", nil, 2)
	m:SetScript("OnEnter", function(self)
		local row = f.row
		if not row then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local shown = false
		local rollID = row.rollId or (type(row.id) == "number" and row.id)
		if rollID and not row.ended and GameTooltip.SetLootRollItem then
			shown = pcall(GameTooltip.SetLootRollItem, GameTooltip, rollID)
		elseif row.slot and GameTooltip.SetLootItem then
			shown = pcall(GameTooltip.SetLootItem, GameTooltip, row.slot)
		end
		if not shown and row.link then
			pcall(GameTooltip.SetHyperlink, GameTooltip, row.link)
		end
		GameTooltip:Show()
	end)
	m:SetScript("OnLeave", TipHide)
	-- (the game's own modified clicks: Shift links it in the chat, Ctrl tries it on)
	m:SetScript("OnClick", function()
		local row = f.row
		local fn = rawget(_G, "HandleModifiedItemClick")
		if row and row.link and fn and IsModifiedClick() then
			pcall(fn, row.link)
		elseif row then
			R.openId = row.id
			R.scroll = 0
			R.Layout()
		end
	end)
	f.medal = m
	local FX = MelloUI.FrameFX
	f.lit = f:CreateTexture(nil, "BORDER", nil, 1)
	f.lit:SetTexture(FX.Art("glow_white.tga"))
	f.lit:SetBlendMode("ADD")
	f.lit:SetPoint("CENTER", m, "CENTER", 0, 0)
	f.lit:SetSize(R.HR * 5, R.HR * 5)
	Paint(f.lit, "selectedTrim", "vertex")
	f.rays = f:CreateTexture(nil, "BORDER", nil, 2)
	f.rays:SetTexture(FX.Art("rays_gold_small.tga"))
	f.rays:SetBlendMode("ADD")
	f.rays:SetPoint("CENTER", m, "CENTER", 0, 0)
	f.rays:SetSize(R.HR * 5, R.HR * 5)
	f.rays:Hide()
	local over = CreateFrame("Frame", nil, f)
	over:SetAllPoints(f)
	over:SetFrameLevel(m:GetFrameLevel() + 2)
	f.star = over:CreateTexture(nil, "OVERLAY", nil, 6)
	f.star:SetTexture(FX.Art("star_gold.tga"))
	f.star:SetSize(14, 14)
	f.star:SetPoint("CENTER", m, "CENTER", R.HR * 0.82, R.HR * 0.82)
	m.count = over:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	m.count:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 3, -2)
	f.name = W.Text(f, "GameFontHighlight")
	f.name:SetPoint("LEFT", f, "TOPLEFT", R.NAME_X, -16)
	f.name:SetWordWrap(false)
	f.sub = W.Text(f, "GameFontHighlight", nil, "text")
	f.sub:SetPoint("LEFT", f, "TOPLEFT", R.NAME_X, -32.5)
	f.sub:SetWordWrap(false)
	f.btns = {}
	for i, kind in ipairs(KINDS) do
		local b = Button(f, kind)
		b:SetPoint("CENTER", f, "TOPRIGHT", -18 - (3 - i) * R.STEP - 13, -22)
		f.btns[i] = b
	end
	-- (Master Loot: the loot master's two, on a slot row)
	f.mlAssign = W.Button(f, TEXT.assign, 66, nil, { height = 22, gold = true, onClick = function(self)
		R.AssignOpen(self:GetParent().row)
	end })
	f.mlAssign:SetPoint("RIGHT", f, "TOPRIGHT", -18, -22)
	f.mlRoll = W.Button(f, TEXT.roll, 58, nil, { height = 22, onClick = function(self)
		R.MLRoll(self:GetParent().row)
	end })
	f.mlRoll:SetPoint("RIGHT", f.mlAssign, "LEFT", -6, 0)
	for _, b in ipairs({ f.mlAssign, f.mlRoll }) do
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(Tr(self == f.mlRoll and TEXT.roll or TEXT.assign))
			GameTooltip:AddLine(Tr(self == f.mlRoll and TEXT.rollDesc or TEXT.assignDesc), 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", TipHide)
		b:Hide()
	end
	f.chip = W.Box(f, "raisedPanel", "border", 1)
	f.chip:SetHeight(22)
	f.chip:SetPoint("RIGHT", f, "TOPRIGHT", -18, -22)
	f.chip.text = W.Text(f.chip, "GameFontHighlight")
	f.chip.text:SetPoint("CENTER", f.chip, "CENTER", 0, 0)
	f.chip:Hide()
	-- the time left: a fine line under the row, the gold that drains over it (the engine's own timer: no Lua a frame)
	f.line = W.Solid(f, "ARTWORK", "border", 1)
	f.line:SetHeight(1)
	f.time = CreateFrame("StatusBar", nil, f)
	f.time:SetHeight(2)
	f.time:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	local fill = f.time.GetStatusBarTexture and f.time:GetStatusBarTexture()
	if fill then
		W.Paint(fill, "selectedTrim", "vertex")   -- (the bar's own fill, gold)
	end
	f.time:SetMinMaxValues(0, 1)
	f.time:SetValue(1)
	R.Dress().Ring(m.ring, R.HR)
	return f
end

-- a table line: its ground (yours, the winner's, a hover), the kind's mark, the name, the kind's word, the number,
-- the star
local function MakeLine(parent)
	local l = CreateFrame("Button", nil, parent)
	l:SetHeight(R.LINE)
	l.ground = l:CreateTexture(nil, "BACKGROUND")
	l.ground:SetTexture("Interface\\Buttons\\WHITE8X8")
	l.ground:SetPoint("TOPLEFT", l, "TOPLEFT", -8, 0)
	l.ground:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", 6, 1)
	l.edge = l:CreateTexture(nil, "BORDER")
	l.edge:SetTexture("Interface\\Buttons\\WHITE8X8")
	l.edge:SetHeight(1)
	l.edge:SetPoint("TOPLEFT", l, "TOPLEFT", -8, 1)
	l.edge:SetPoint("TOPRIGHT", l, "TOPRIGHT", 6, 1)
	Paint(l.edge, "selectedTrim", "vertex")
	l.mark = l:CreateTexture(nil, "ARTWORK")
	l.mark:SetSize(14, 14)
	l.mark:SetPoint("LEFT", l, "LEFT", -1, 0)
	l.name = W.Text(l, "GameFontHighlight")
	l.name:SetPoint("LEFT", l, "LEFT", 18, 0)
	l.name:SetWordWrap(false)
	l.num = W.Text(l, "GameFontHighlight")
	l.num:SetPoint("RIGHT", l, "RIGHT", 0, 0)
	l.num:SetJustifyH("RIGHT")
	l.word = W.Text(l, "GameFontHighlight", nil, "text")
	l.word:SetPoint("RIGHT", l, "RIGHT", -34, 0)
	l.word:SetJustifyH("RIGHT")
	l.star = l:CreateTexture(nil, "OVERLAY")
	l.star:SetTexture(MelloUI.FrameFX.Art("star_gold.tga"))
	l.star:SetSize(11, 11)
	l.star:SetPoint("CENTER", l, "LEFT", -12, 5)
	l:SetScript("OnEnter", function(self)
		local names = self.names
		if not names then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.title or "")
		for i = 1, #names, 3 do
			local parts = {}
			for j = i, min(i + 2, #names) do
				local e = names[j]
				parts[#parts + 1] = "|c" .. ClassHex(e.class) .. e.name .. "|r"
			end
			GameTooltip:AddLine(table.concat(parts, "   "))
		end
		GameTooltip:Show()
	end)
	l:SetScript("OnLeave", TipHide)
	return l
end

function R.Build()
	if R.frame then
		return R.frame
	end
	local f = CreateFrame("Frame", R.KEY, UIParent)
	f:SetSize(R.W, R.HEAD + R.ROW + 20)
	f:SetFrameStrata("MEDIUM")
	f:SetFrameLevel(30)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:Hide()
	Home(f)
	R.frame = f
	R.shell = CreateFrame("Frame", nil, f)
	R.shell:SetAllPoints(f)
	R.shell:SetFrameLevel(f:GetFrameLevel())
	R.body = CreateFrame("Frame", nil, f)
	R.body:SetAllPoints(f)
	R.body:SetFrameLevel(f:GetFrameLevel() + 2)
	-- the header: the look's mark, the title in the heading gold, the count
	R.mark = R.body:CreateTexture(nil, "ARTWORK")
	R.mark:SetSize(18, 18)
	R.mark:SetPoint("CENTER", f, "TOPLEFT", 27, -24)
	R.title = W.Text(R.body, "GameFontNormalLarge", TEXT.title, "selectedTrim")
	R.title:SetPoint("LEFT", f, "TOPLEFT", 41, -24)
	R.count = W.Text(R.body, "GameFontHighlight", nil, "text")
	R.count:SetPoint("RIGHT", f, "TOPRIGHT", -22, -24)
	R.count:SetJustifyH("RIGHT")
	R.rule = W.Solid(R.body, "ARTWORK", "border", 1)
	R.rule:SetHeight(1)
	R.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -(R.HEAD - 1))
	R.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -(R.HEAD - 1))
	R.foot = W.Text(R.body, "GameFontHighlight", nil, "text")
	R.foot:SetJustifyH("CENTER")
	-- the open row's table: its lines in a clipping holder, the wheel scrolls it, the thin bar beside it
	R.tbl = CreateFrame("Frame", nil, R.body)
	R.tbl:SetClipsChildren(true)
	R.tbl:SetFrameLevel(R.body:GetFrameLevel() + 6)
	R.tbl:EnableMouseWheel(true)
	R.tbl:SetScript("OnMouseWheel", function(_, delta)
		R.scroll = R.scroll - (delta > 0 and 1 or -1)
		R.Layout()
	end)
	R.lines = {}
	for i = 1, R.CAP do
		R.lines[i] = MakeLine(R.tbl)
	end
	R.pin = MakeLine(R.tbl)
	R.pin:SetFrameLevel(R.tbl:GetFrameLevel() + 3)
	R.pinBack = R.pin:CreateTexture(nil, "BACKGROUND", nil, -1)
	R.pinBack:SetTexture("Interface\\Buttons\\WHITE8X8")
	R.pinBack:SetPoint("TOPLEFT", R.pin, "TOPLEFT", -8, 1)
	R.pinBack:SetPoint("BOTTOMRIGHT", R.pin, "BOTTOMRIGHT", 12, 0)
	Paint(R.pinBack, "innerPanel", "vertex")
	R.bar = W.ThinScrollBar(R.body, 3)
	R.bar:SetFrameLevel(R.tbl:GetFrameLevel() + 2)
	R.bar:Hide()
	R.bar:SetScript("OnValueChanged", function(_, v)
		v = floor((Num(v) or 0) + 0.5)
		if v ~= R.scroll then
			R.scroll = v
			R.Layout()
		end
	end)
	-- the look's frame round it all
	R.worn = R.Dress()
	R.worn.Shell(R.shell, R.mark)
	R.entry = MelloUI:RegisterMover(f, f, { key = R.KEY, anchor = "TOPLEFT", default = Home, min = 0.6, max = 1.6, base = 1,
		label = TEXT.title, page = "Widgets", category = "windows", placeholder = { R.W, R.HEAD + 2 * R.ROW + 20 },
		when = R.Active })
	return f
end

--------------------------------------------------------------------------------
-- The layout (on every change: a roll, a pick, a click, the wheel, a fold's step)
--------------------------------------------------------------------------------

-- the rows on show (the first four still standing) and the one open
local function Shown()
	local shown, waiting = {}, 0
	for _, row in ipairs(R.rows) do
		if #shown < R.SHOWN then
			shown[#shown + 1] = row
		else
			waiting = waiting + 1
		end
	end
	return shown, waiting
end

local function OpenRow(shown)
	-- (a row you opened; else a favourite you have not answered; else the first roll with picks you have not answered;
	-- else the first with picks -- never one already won or handed out, nor the loot master's item before its roll)
	local function Can(row)
		return not row.folding and not (row.winner and row.wonAt) and row.picks.n > 0
	end
	for _, row in ipairs(shown) do
		if row.id == R.openId and not row.folding then
			return row
		end
	end
	for _, row in ipairs(shown) do
		if row.fav and not row.you and Can(row) then
			return row
		end
	end
	for _, row in ipairs(shown) do
		if not row.you and Can(row) then
			return row
		end
	end
	for _, row in ipairs(shown) do
		if Can(row) then
			return row
		end
	end
	return nil
end

local RANK = { need = 1, greed = 2, pass = 3, wait = 4 }
local function ByRoll(a, b)
	if RANK[a.kind] ~= RANK[b.kind] then
		return RANK[a.kind] < RANK[b.kind]
	end
	return (a.roll or -1) > (b.roll or -1)
end

-- the open row's lines: Need and Greed (high to low); in a raid the passes and the undecided folded in a line each,
-- in a party every pass and every undecided name on its own
local function Lines(row)
	local picks, lines, rolled = row.picks, {}, {}
	for i = 1, picks.n do
		rolled[#rolled + 1] = picks[i]
	end
	table.sort(rolled, ByRoll)
	local big = picks.n > R.BIG
	local passed, deciding = {}, {}
	for _, p in ipairs(rolled) do
		if p.kind == "need" or p.kind == "greed" then
			lines[#lines + 1] = { pick = p }
		elseif p.kind == "pass" then
			passed[#passed + 1] = p
		else
			deciding[#deciding + 1] = p
		end
	end
	if big then
		if #passed > 0 then
			lines[#lines + 1] = { passed = passed }
		end
		if #deciding > 0 then
			lines[#lines + 1] = { deciding = #deciding }
		end
	else
		for _, p in ipairs(passed) do
			lines[#lines + 1] = { pick = p }
		end
		for _, p in ipairs(deciding) do
			lines[#lines + 1] = { pick = p }
		end
	end
	return lines, big
end

local function Counts(row)
	local c = { need = 0, greed = 0, pass = 0, wait = 0 }
	for i = 1, row.picks.n do
		local k = row.picks[i].kind
		c[k] = (c[k] or 0) + 1
	end
	return c
end

-- a party's size while the history has no list yet
local function GroupSize()
	local ok, n = pcall(GetNumGroupMembers)
	n = ok and Num(n) or 0
	return max(1, n)
end

-- the second line: the leader (live), in a raid the counts by kind; "On your list" before anyone picked; how many picked
local function SubLine(row)
	local c, top = Counts(row), nil
	for i = 1, row.picks.n do
		local p = row.picks[i]
		if (p.kind == "need" or p.kind == "greed") and p.roll and (not top or ByRoll(p, top)) then
			top = p
		end
	end
	if row.allPassed then
		return Tr(TEXT.passedAll)
	end
	local rolled = c.need + c.greed + c.pass
	if row.fav and rolled == 0 then
		return MelloUI:PaletteCode("selectedTrim") .. Tr(TEXT.mine) .. "|r"
	end
	local s = ""
	if top then
		s = Mark(top.kind, 13) .. " |c" .. KindHex(top.kind) .. top.roll .. "|r |c" .. ClassHex(top.class)
			.. (top.self and Tr(TEXT.you) or top.name) .. "|r"
	end
	if row.picks.n > R.BIG then
		for _, k in ipairs(KINDS) do
			if c[k] > 0 then
				s = s .. "   " .. Mark(k, 12) .. " " .. c[k]
			end
		end
	elseif not top then
		s = Tr(TEXT.picked):format(rolled, row.picks.n > 0 and row.picks.n or GroupSize())
	end
	return s
end

local function LayRow(f, row, open)
	local q = MelloUI.FrameFX.LootTint(row.quality)
	local m = f.medal
	m.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	m.icon:SetShown(not row.flown)
	m.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	if q then
		m.qual:SetVertexColor(q[1], q[2], q[3], 0.95)
		f.name:SetTextColor(q[1], q[2], q[3])
	end
	m.count:SetText(row.count and row.count > 1 and row.count or "")
	f.name:SetText(row.name or "")
	-- (the name clear of the buttons or the chip)
	f.name:SetWidth(R.W - R.NAME_X - 3 * R.STEP - 30)
	f.sub:SetWidth(R.W - R.NAME_X - 3 * R.STEP - 30)
	local looter = R.Looter()
	if row.ml and row.winner then
		f.sub:SetText(looter and Tr(TEXT.givenBy):format(looter) or Tr(TEXT.givenByAny))
	elseif row.master and not row.rolling and not row.rollId and not row.winner then
		f.sub:SetText(Tr(TEXT.onBoss))
	else
		f.sub:SetText(SubLine(row))
	end
	-- the favourite's and the open row's ground; the favourite's star, the ring lit
	local fav = row.fav
	if fav then
		Paint(f.ground, "selectedTab", "vertex")
		f.ground:SetAlpha(0.55)
	else
		Paint(f.ground, "raisedPanel", "vertex")
		f.ground:SetAlpha(open and 0.55 or 0)
	end
	f.ground:SetShown(fav or open)
	f.star:SetShown(fav)
	f.lit:SetShown(fav)
	f.lit:SetAlpha(fav and 0.6 or 0)
	if fav and not row.burst then
		row.burst = true
		f.rays:Show()
		Anim:Burst(f.rays, R.RAYS_K, 1, R.RAYS_T)
	end
	-- the buttons, or your choice, or the winner; the loot master's Roll and Assign
	local chip = f.chip
	local master = row.master and not row.rollId and not (row.winner and row.wonAt)
	f.mlRoll:SetShown(master and not row.rolling)
	f.mlAssign:SetShown(master and not row.rolling)
	if master then
		for _, b in ipairs(f.btns) do
			b:Hide()
			b.lit:Hide()
		end
		if row.rolling then
			chip.text:SetText(MelloUI:PaletteCode("text") .. Tr(TEXT.rolling) .. "|r")
			chip:Show()
		else
			chip:Hide()
		end
	elseif row.winner and row.wonAt then
		for _, b in ipairs(f.btns) do
			b:Hide()
			b.lit:Hide()
		end
		local w = row.winner
		local words
		if row.ml then
			words = w.self and Tr(TEXT.givenYou) or Tr(TEXT.givenTo):format("|c" .. ClassHex(w.class) .. w.name .. "|r")
		else
			words = w.self and Tr(TEXT.youWin) .. (w.roll and (" \194\183 " .. w.roll) or "")
				or Tr(TEXT.wins):format("|c" .. ClassHex(w.class) .. w.name .. "|r")
		end
		chip.text:SetText("|T" .. MelloUI.FrameFX.Art("star_gold.tga") .. ":13:13|t " .. words)
		chip:Show()
	elseif row.you then
		for _, b in ipairs(f.btns) do
			b:Hide()
			b.lit:Hide()
		end
		local mine
		for i = 1, row.picks.n do
			if row.picks[i].self then
				mine = row.picks[i]
			end
		end
		local roll = mine and mine.roll
		chip.text:SetText(Mark(row.you, 15) .. " |c" .. KindHex(row.you) .. Tr(TEXT[row.you]) .. (roll and (" " .. roll) or "")
			.. "|r")
		chip:Show()
	else
		chip:Hide()
		for _, b in ipairs(f.btns) do
			local can = (b.kind == "need" and row.canNeed) or (b.kind == "greed" and row.canGreed) or b.kind == "pass"
			b:SetOn(can and true or false)
			b:EnableMouse(true)
			b:Show()
			b.lit:SetShown(fav and b.kind == "need" and row.canNeed or false)
		end
	end
	if chip:IsShown() then
		chip:SetWidth(chip.text:GetStringWidth() + 22)
	end
	-- the time: the engine drains the gold from the roll's start (a roll over: empty)
	local timed = (row.ended and "over:" or "on:") .. tostring(row.id) .. tostring(row.startAt)
	if f.timed ~= timed then
		f.timed = timed
		if row.ended or not (row.startAt and row.total) or not Anim:Timer(f.time, row.total, false, row.startAt) then
			Anim:StopTimer(f.time, false)
			if not row.ended and row.startAt and row.total then
				f.time:SetValue(max(0, 1 - (GetTime() - row.startAt) / row.total))
			end
		end
	end
end

-- the open row's table under it: its lines from the scroll on, your line kept in sight
local function LayTable(row, top, left, width)
	local lines, big = Lines(row)
	local n = #lines
	local shown = min(R.CAP, n)
	local maxScroll = max(0, n - R.CAP)
	R.scroll = max(0, min(R.scroll, maxScroll))
	local you
	for i, l in ipairs(lines) do
		if l.pick and l.pick.self then
			you = i
		end
	end
	local pinned = you and (you <= R.scroll or you > R.scroll + R.CAP) and true or false
	R.tbl:ClearAllPoints()
	R.tbl:SetPoint("TOPLEFT", R.frame, "TOPLEFT", left, -top)
	R.tbl:SetSize(width, shown * R.LINE + 10)
	local tx, tw = R.NAME_X - left, R.W - R.NAME_X - 24
	local function Fill(l, e, place)
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", R.tbl, "TOPLEFT", tx, -(5 + place * R.LINE))
		l:SetWidth(tw)
		l.names, l.title = nil, nil
		l.edge:Hide()
		l.star:Hide()
		l.ground:Hide()
		l.word:SetText("")
		l.num:SetText("")
		l.name:SetAlpha(1)
		if e.pick then
			local p = e.pick
			l.mark:SetTexture(ICON[p.kind] or ICON.need)
			l.mark:SetDesaturated(p.kind == "wait")
			l.mark:SetAlpha(p.kind == "wait" and 0.35 or 1)
			l.name:SetText((p.self and Tr(TEXT.you) or p.name) .. (e.rank and ("  " .. MelloUI:PaletteCode("text")
				.. Tr(TEXT.rank):format(e.rank) .. "|r") or ""))
			local r, g, b = MelloUI.Colours.Class(p.class)
			l.name:SetTextColor(r or 1, g or 1, b or 1)
			if p.kind == "pass" or p.kind == "wait" then
				l.name:SetAlpha(0.55)
			end
			l.word:SetText(p.kind == "wait" and Tr(TEXT.decidingOne) or Tr(TEXT[p.kind]))
			if (p.kind == "need" or p.kind == "greed") then
				l.num:SetText(p.roll and ("|c" .. KindHex(p.kind) .. p.roll .. "|r") or (MelloUI:PaletteCode("mutedText") .. "\226\128\147|r"))
			end
			local isWin = row.winner and row.wonAt and row.winner.name == p.name
			if p.self then
				Paint(l.ground, "selectedTab", "vertex")
				l.ground:SetAlpha(0.85)
				l.ground:Show()
			end
			if isWin then
				Paint(l.ground, "selectedTrim", "vertex")
				l.ground:SetAlpha(0.22)
				l.ground:Show()
				l.star:Show()
			end
		elseif e.passed then
			l.mark:SetTexture(ICON.pass)
			l.mark:SetDesaturated(false)
			l.mark:SetAlpha(0.85)
			l.name:SetTextColor(1, 1, 1)
			l.name:SetText(MelloUI:PaletteCode("text") .. Tr(TEXT.passed):format(#e.passed) .. "|r")
			l.word:SetText(Tr(TEXT.names))
			l.names, l.title = e.passed, Tr(TEXT.passed):format(#e.passed)
		elseif e.deciding then
			l.mark:SetTexture(nil)
			l.name:SetTextColor(1, 1, 1)
			l.name:SetText(MelloUI:PaletteCode("text") .. Tr(TEXT.deciding):format(e.deciding) .. "|r")
			l.name:SetAlpha(0.6)
		end
		l:Show()
	end
	local used = 0
	for i = 1, R.CAP do
		local idx = R.scroll + i
		local l = R.lines[i]
		if idx <= n and i <= shown and not (pinned and i == shown) then
			Fill(l, lines[idx], i - 1)
			used = used + 1
		else
			l:Hide()
		end
	end
	if pinned then
		local place = 0
		for i, l in ipairs(lines) do
			if l.pick and (l.pick.kind == "need" or l.pick.kind == "greed") then
				place = place + 1
				if i == you then
					break
				end
			end
		end
		Fill(R.pin, { pick = lines[you].pick, rank = place > 0 and place or nil }, shown - 1)
		R.pin.edge:Show()
		R.pinBack:Show()
	else
		R.pin:Hide()
	end
	-- the thin bar: only when the lines are more than the table holds
	if n > R.CAP then
		R.bar:ClearAllPoints()
		R.bar:SetPoint("TOPRIGHT", R.frame, "TOPRIGHT", -12, -(top + 6))
		R.bar:SetHeight(R.CAP * R.LINE - 2)
		R.bar:SetMinMaxValues(0, maxScroll)
		R.bar:SetValue(R.scroll)
		R.bar.thumb:SetHeight(max(12, (R.CAP * R.LINE - 2) * R.CAP / n))
		R.bar:Show()
	else
		R.bar:Hide()
	end
	R.tbl:Show()
	return shown * R.LINE + 10, big
end

function R.Layout()
	local f = R.frame
	if not f then
		return
	end
	if not R.Active() or #R.rows == 0 then
		R.Hide()
		return
	end
	local shown, waiting = Shown()
	local open = OpenRow(shown)
	if open and open.id ~= R.openRow then
		R.openRow = open.id
		R.scroll = 0
	end
	-- the rows: each its frame (from the pool), laid down from the header, a folding one shrinking
	local y = R.HEAD
	local inUse = {}
	for _, row in ipairs(shown) do
		local rf = row.frame
		if not rf then
			rf = table.remove(R.pool) or MakeRow()
			row.frame = rf
			rf.row = row
			rf:SetAlpha(0)
			rf:Show()
			Anim:To(rf, "alpha", 1, 0.25)
		end
		inUse[rf] = true
		local k = row.k or 1
		rf:ClearAllPoints()
		rf:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
		rf:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
		rf:SetHeight(R.ROW)
		LayRow(rf, row, row == open)
		local h = R.ROW * k
		local th = 0
		if row == open and k >= 1 and row.assignOpen and row.master and not row.rolling and not row.winner then
			th = R.LayCand(row, y + R.ROW - 4)
		elseif row == open and row.picks.n > 0 and k >= 1 then
			th = LayTable(row, y + R.ROW - 4, 0, R.W)
		end
		if th > 0 then
			h = h + th
			rf.ground:SetPoint("BOTTOMRIGHT", rf, "BOTTOMRIGHT", -6, 2 - th)
		else
			rf.ground:SetPoint("BOTTOMRIGHT", rf, "BOTTOMRIGHT", -6, 2)
		end
		rf.line:ClearAllPoints()
		rf.line:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -(y + h - 2))
		rf.line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -(y + h - 2))
		rf.time:ClearAllPoints()
		rf.time:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -(y + h - 2.5))
		rf.time:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -(y + h - 2.5))
		y = y + h
	end
	if not (open and open.picks.n > 0 and (open.k or 1) >= 1) or (open.assignOpen and open.master and not open.rolling) then
		R.tbl:Hide()
		R.bar:Hide()
	end
	if R.cand and not (open and open.assignOpen and open.master and not open.rolling and not open.winner) then
		R.cand:Hide()
	end
	-- frames no longer on show back to the pool
	for _, row in ipairs(R.rows) do
		if row.frame and not inUse[row.frame] then
			row.frame:Hide()
			row.frame.row = nil
			R.pool[#R.pool + 1] = row.frame
			row.frame = nil
		end
	end
	local total = #R.rows
	local looter = R.Looter()
	local mastering = false
	for _, row in ipairs(R.rows) do
		mastering = mastering or (row.master and not row.rollId) or false
	end
	R.title:SetText(Tr(mastering and TEXT.master or TEXT.title))
	if looter then
		R.count:SetText(Tr(TEXT.masterOf):format(looter))
	else
		R.count:SetText(total == 1 and Tr(TEXT.item) or Tr(TEXT.items):format(total))
	end
	if waiting > 0 then
		R.foot:SetText(Tr(TEXT.waiting):format(waiting))
		R.foot:ClearAllPoints()
		R.foot:SetPoint("CENTER", f, "TOPLEFT", R.W / 2, -(y + 14))
		R.foot:Show()
		y = y + R.FOOT
	else
		R.foot:Hide()
		y = y + 8
	end
	f:SetHeight(y + R.BOTTOM)
	if not f:IsShown() then
		f:SetAlpha(0)
		f:Show()
		Anim:To(f, "alpha", 1, 0.2)
	end
end

function R.Hide()
	if R.frame and R.frame:IsShown() then
		R.frame:Hide()
	end
	for _, row in ipairs(R.rows) do
		if row.ended then
			L().Forget(row.id)
		end
	end
	-- (rolls no longer MelloUI's to show: let go, the game's boxes have them)
	if not R.Active() then
		for _, row in ipairs(R.rows) do
			L().Forget(row.id)   -- (each drop's place let go too: the reader would hold it for a roll nobody shows)
			if row.frame then
				row.frame:Hide()
				row.frame.row = nil
				R.pool[#R.pool + 1] = row.frame
				row.frame = nil
			end
		end
		wipe(R.rows)
		wipe(R.byId)
	end
end

--------------------------------------------------------------------------------
-- Your answer, the win, the fold
--------------------------------------------------------------------------------

function R.Answer(row, kind)
	if row.you or row.ended or (row.master and not row.rollId and not row.rolling) then
		return
	end
	if (kind == "need" and not row.canNeed) or (kind == "greed" and not row.canGreed) then
		return
	end
	row.you, row.youAt = kind, GetTime()
	if row.test then
		R.TestAnswer(row, kind)   -- (nothing sent to the game)
	else
		L().Roll(row.rollId or row.id, ROLL_OF[kind])
	end
	R.Layout()
end

-- the unit token of a winner (you, or the member of that name), nil when not in the group any more
local function UnitOf(w)
	if w.self then
		return "player"
	end
	local FX = MelloUI.FrameFX
	local units = FX.Members()
	for _, unit in ipairs(units) do
		local ok, name, realm = pcall(UnitName, unit)
		name, realm = ok and Text(name), ok and Text(realm)
		if name then
			local full = realm and realm ~= "" and (name .. "-" .. realm) or name
			if full == w.name or name == w.name then
				return unit
			end
		end
	end
	return nil
end

-- the item beside the winner's frame: a small medal, two seconds (one, reused)
local function Badge(target, row)
	local b = R.badge
	if not b then
		b = CreateFrame("Frame", nil, UIParent)
		b:SetFrameStrata("HIGH")
		b:SetSize(22, 22)
		b.mask = b:CreateMaskTexture()
		b.mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		b.mask:SetAllPoints(b)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints(b)
		b.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
		b.icon:AddMaskTexture(b.mask)
		b.ring = b:CreateTexture(nil, "OVERLAY")
		b:Hide()
		R.badge = b
	end
	R.Dress().Ring(b.ring, 11)
	b.icon:SetTexture(row.icon)
	b:ClearAllPoints()
	b:SetPoint("LEFT", target, "RIGHT", 6, 0)
	Anim:Stop(b, "alpha")
	b:SetAlpha(0)
	b:Show()
	Anim:To(b, "alpha", 1, 0.25)
	C_Timer.After(R.LINGER, function()
		Anim:To(b, "alpha", 0, 0.4, "linear", function()
			b:Hide()
		end)
	end)
end

function R.Win(row)
	row.wonAt = GetTime()
	R.Layout()
	C_Timer.After(R.HOLD, function()
		local FX = MelloUI.FrameFX
		local unit = UnitOf(row.winner)
		local target = unit and FX.FrameOf(FX.Canon(unit))
		local medal = row.frame and row.frame.medal
		if target and medal then
			local l, b, r, t = FX.Rect(medal)
			local layer = l and FX.Loot((l + r) / 2, (b + t) / 2, target, FX.LootTier(row.quality), row.icon,
				FX.LootTint(row.quality))
			local S = layer and FX.state and FX.state[layer]
			if layer then
				row.flown = true
				R.Layout()
			end
			C_Timer.After(S and S.loot and S.loot.total or 0, function()
				Badge(target, row)
			end)
		end
		C_Timer.After(R.AFTER_WIN - R.HOLD, function()
			R.Fold(row)
		end)
	end)
end

-- a row away: faded, then closed (the rows under it come up), then gone
function R.Fold(row)
	if row.folding or not R.byId[row.id] then
		return
	end
	row.folding = true
	local function Gone()
		for i, r in ipairs(R.rows) do
			if r == row then
				table.remove(R.rows, i)
				break
			end
		end
		R.byId[row.id] = nil
		L().Forget(row.id)
		if row.frame then
			row.frame:Hide()
			row.frame.row = nil
			R.pool[#R.pool + 1] = row.frame
			row.frame = nil
		end
		if R.openId == row.id then
			R.openId = nil
		end
		R.Layout()
	end
	local f = row.frame
	if not f then
		Gone()
		return
	end
	Anim:To(f, "alpha", 0, R.FOLD_A, "linear", function()
		Anim:Drive(f, function(_, p)
			row.k = 1 - p
			R.Layout()
		end, R.FOLD_H, "inOutCubic", Gone)
	end)
end

--------------------------------------------------------------------------------
-- Master Loot (the user, 2026-11-20: "Yes build both, but when you click "Roll" on master loot, and a player rolls,
-- where do we see their roll numbers? ... how do we make sure that we are tracking the roll for the correct item?")
-- A roll the loot master asks for is the game's own group roll: its picks and numbers are in the loot history like
-- any roll's, so its row shows them. It is told apart by the item's exact link (the slot row's, then the roll's) and,
-- once found, by its drop's own place (encounter, list key: two of the same item each their own)
--------------------------------------------------------------------------------

R.ML = { seen = {}, primed = false, sort = "group", recent = {}, n = 0 }

-- the loot method now: "master" while the master looter hands out, and the looter's party / raid index
local function Method()
	local P = _G.C_PartyInfo
	if type(P) == "table" and type(P.GetLootMethod) == "function" then
		local ok, m, partyID, raidID = pcall(P.GetLootMethod)
		if ok and not Secret(m) and m ~= nil then
			return (Num(m) == 2 or m == "master") and "master" or "other", Num(partyID), Num(raidID)
		end
	end
	local fn = _G.GetLootMethod
	if type(fn) == "function" then
		local ok, m, partyID, raidID = pcall(fn)
		if ok and not Secret(m) then
			return m == "master" and "master" or "other", Num(partyID), Num(raidID)
		end
	end
	return nil
end

-- the master looter's name and whether it is you; nil while the loot is not the master looter's
function R.Looter()
	if R.testLooter then
		return R.testLooter, true
	end
	local m, partyID, raidID = Method()
	if m ~= "master" then
		return nil
	end
	local unit = raidID and ("raid" .. raidID) or (partyID == 0 and "player") or (partyID and ("party" .. partyID)) or nil
	if not unit then
		return nil
	end
	local ok, name = pcall(UnitName, unit)
	name = ok and Text(name) or nil
	local me = unit == "player"
	if not me then
		local okU, same = pcall(UnitIsUnit, unit, "player")
		me = okU and not Secret(same) and same == true
	end
	return name, me
end

-- a member's class token by name (nil when not in the group)
local function ClassOf(name)
	local FX = MelloUI.FrameFX
	for _, unit in ipairs(FX.Members()) do
		local ok, n = pcall(UnitName, unit)
		if ok and Text(n) == name then
			local okC, _, class = pcall(UnitClass, unit)
			return okC and Text(class) or nil
		end
	end
	return nil
end

local function MyName()
	local ok, n = pcall(UnitName, "player")
	return ok and Text(n) or nil
end

-- (the loot master, the loot window open) the items at or over the threshold, a row each (key "slot:N")
function R.ReadSlots()
	local okN, n = pcall(GetNumLootItems)
	n = okN and Num(n) or 0
	local okT, threshold = pcall(_G.GetLootThreshold)
	threshold = okT and Num(threshold) or 2
	R.ML.open = true
	for slot = 1, n do
		local okK, kind = pcall(GetLootSlotType, slot)
		local ok, icon, name, count, _, quality = pcall(GetLootSlotInfo, slot)
		local okL, link = pcall(GetLootSlotLink, slot)
		quality, link = ok and Num(quality), okL and Text(link)
		if okK and Num(kind) == 1 and quality and quality >= threshold and link then
			local id = "slot:" .. slot
			local row = R.byId[id]
			if not row or row.link ~= link then
				row = { id = id, slot = slot, link = link, icon = ok and not Secret(icon) and icon or nil, name = Text(name),
					count = Num(count), quality = quality, picks = { n = 0 }, born = GetTime(), master = true }
				R.byId[id] = row
				-- (the loot master's items first, in the boss's order)
				local at = 1
				for i, r in ipairs(R.rows) do
					if r.master then
						at = i + 1
					end
				end
				table.insert(R.rows, at, row)
			end
		end
	end
end

-- a roll the game started for an item the loot master asked a roll for: that row takes it (the same link, the oldest
-- asked first -- two of one item in the order Roll was pressed); true when one did
function R.Adopt(e)
	local link
	for _, row in ipairs(R.rows) do
		if row.master and row.rolling and not row.rollId then
			link = link or select(7, L().Info(e.id))
			if link and row.link == link then
				local _, _, _, _, canNeed, canGreed = L().Info(e.id)
				row.rollId, row.startAt, row.total = e.id, e.startAt, e.total
				row.canNeed, row.canGreed = canNeed, canGreed
				R.byId[e.id] = row
				return true
			end
		end
	end
	return false
end

function R.MLRoll(row)
	if row and row.test and row.master and not row.rolling then
		R.TestRoll(row)
		return
	end
	if not (row and row.master and row.slot) or row.rolling then
		return
	end
	local ok = pcall(_G.DoMasterLootRoll, row.slot)
	if ok then
		row.rolling, row.rollAt = true, GetTime()
		R.Layout()
	elseif MelloUI.Announce then
		MelloUI:Announce(Tr(TEXT.cantGive))
	end
end

function R.AssignOpen(row)
	if not (row and row.master) then
		return
	end
	row.assignOpen = not row.assignOpen
	R.openId = row.assignOpen and row.id or nil
	R.Layout()
end

-- the item handed out: MelloUI's question, then the game's call; the row then names the player and the item flies
function R.Give(row, cand)
	if not (row and (row.slot or row.test) and cand) then
		return
	end
	local q = MelloUI.FrameFX.LootTint(row.quality)
	local item = (q and ("|cff" .. q.hex:sub(2)) or "") .. (row.name or "?") .. "|r"
	MelloUI:Confirm({ text = Tr(TEXT.giveAsk):format(item, "|c" .. ClassHex(cand.class) .. cand.name .. "|r"),
		accept = TEXT.give, onAccept = function()
			local ok = row.test or pcall(_G.GiveMasterLoot, row.slot, cand.index)
			if not ok then
				if MelloUI.Announce then
					MelloUI:Announce(Tr(TEXT.cantGive))
				end
				return
			end
			row.ml, row.assignOpen = true, nil
			row.winner = { name = cand.name, class = cand.class, self = cand.self }
			R.ML.recent[(row.link or "") .. cand.name] = GetTime()
			R.Win(row)
		end })
end

-- an item handed out, seen by everyone: a row with its winner, the flight (R.Win from the next pass)
function R.Given(link, name, class, isSelf)
	if not (link and name) then
		return
	end
	local key = link .. name
	local at = R.ML.recent[key]
	if at and GetTime() - at < 20 then
		return
	end
	R.ML.recent[key] = GetTime()
	local itemName, quality, icon
	local CI = _G.C_Item
	if type(CI) == "table" and CI.GetItemInfo then
		local ok, n, _, q, _, _, _, _, _, _, tex = pcall(CI.GetItemInfo, link)
		if ok then
			itemName, quality, icon = Text(n), Num(q), (not Secret(tex)) and tex or nil
		end
	end
	if not icon and type(CI) == "table" and CI.GetItemInfoInstant then
		local ok, _, _, _, _, tex = pcall(CI.GetItemInfoInstant, link)
		icon = ok and not Secret(tex) and tex or nil
	end
	itemName = itemName or link:match("%[(.-)%]")
	R.ML.n = R.ML.n + 1
	local id = "given:" .. R.ML.n
	local row = { id = id, link = link, icon = icon, name = itemName, quality = quality or 4, picks = { n = 0 }, ml = true,
		born = GetTime(), ended = GetTime(),
		winner = { name = name, class = class or ClassOf(name), self = isSelf or name == MyName() } }
	R.rows[#R.rows + 1] = row
	R.byId[id] = row
	R.Want()
end

-- (each pass while the loot is the master looter's) a drop of the newest encounter won with no roll and held by no
-- roll: handed out. The first pass only notes what is there already (no old hand-out shown again)
function R.GivenFromHistory()
	if Method() ~= "master" then
		return
	end
	local drops, enc = L().Latest()
	if not drops then
		return
	end
	for _, d in ipairs(drops) do
		local key = type(d) == "table" and Num(d.lootListKey)
		local w = key and d.winner
		if type(w) == "table" and not Secret(w) then
			local seen = enc .. ":" .. key
			if not R.ML.seen[seen] then
				R.ML.seen[seen] = true
				local rolled = false
				if type(d.rollInfos) == "table" then
					for _, ri in ipairs(d.rollInfos) do
						rolled = rolled or (type(ri) == "table" and Num(ri.roll) ~= nil) or false
					end
				end
				if R.ML.primed and not rolled and not L().Holds(enc, key) then
					R.Given(Text(d.itemHyperlink), Text(w.playerName), Text(w.playerClass), not Secret(w.isSelf) and w.isSelf == true)
				end
			end
		end
	end
	R.ML.primed = true
end

-- (the history has no hand-out) the game's own chat line: "<name> receives loot: <item>." (its LOOT_ITEM, read as a
-- pattern), while the loot is the master looter's and the item is at or over the threshold; a secret line is passed by
function R.GivenFromChat(msg)
	msg = Text(msg)
	local fmt = _G.LOOT_ITEM
	if not (msg and type(fmt) == "string") or Method() ~= "master" then
		return
	end
	if not R.ML.pattern then
		R.ML.pattern = "^" .. fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$"
	end
	local name, link = msg:match(R.ML.pattern)
	if not (name and link and link:find("|Hitem:")) then
		return
	end
	local okT, threshold = pcall(_G.GetLootThreshold)
	threshold = okT and Num(threshold) or 2
	local CI = _G.C_Item
	local ok, _, _, q = false, nil, nil, nil
	if type(CI) == "table" and CI.GetItemInfo then
		ok, _, _, q = pcall(CI.GetItemInfo, link)
	end
	if ok and Num(q) and Num(q) < threshold then
		return
	end
	R.Given(link, name:gsub("%-.*$", ""), nil, nil)
end

-- the loot master's list under a row: the search, By group / By class, the raid in lines of five (one made, kept)
local function BuildCand()
	local c = CreateFrame("Frame", nil, R.body)
	c:SetFrameLevel(R.body:GetFrameLevel() + 6)
	local search = CreateFrame("EditBox", nil, c, "SearchBoxTemplate")
	search:SetSize(176, 20)
	search:SetPoint("TOPLEFT", c, "TOPLEFT", R.NAME_X - 2, -7)
	search:SetAutoFocus(false)
	if W.FlatSearch then
		W.FlatSearch(search)
	end
	search:HookScript("OnTextChanged", function()
		R.Layout()
	end)
	c.search = search
	if W.Chips then
		local chips = W.Chips(c, { height = 20, onPick = function(_, key)
			R.ML.sort = key
			R.Layout()
		end })
		chips:SetItems({ { key = "group", label = TEXT.byGroup }, { key = "class", label = TEXT.byClass } })
		chips:Select(R.ML.sort)
		chips:SetPoint("TOPRIGHT", c, "TOPRIGHT", -18, -7)
		c.chips = chips
	end
	c.labels, c.cells = {}, {}
	for g = 1, 8 do
		local l = W.Text(c, "GameFontHighlightSmall", nil, "text")
		l:SetJustifyH("RIGHT")
		c.labels[g] = l
	end
	for i = 1, 40 do
		local b = CreateFrame("Button", nil, c)
		b:SetHeight(18)
		b.hi = W.Solid(b, "BACKGROUND", "hover", 1)
		b.hi:SetAllPoints(b)
		b.hi:Hide()
		b.text = W.Text(b, "GameFontHighlightSmall")
		b.text:SetPoint("LEFT", b, "LEFT", 3, 0)
		b.text:SetPoint("RIGHT", b, "RIGHT", -2, 0)
		b.text:SetWordWrap(false)
		b:SetScript("OnEnter", function(self)
			self.hi:Show()
		end)
		b:SetScript("OnLeave", function(self)
			self.hi:Hide()
		end)
		b:SetScript("OnClick", function(self)
			R.Give(R.candRow, self.cand)
		end)
		c.cells[i] = b
	end
	R.cand = c
	return c
end

-- a raid member's group by name (a party: 1)
local function Groups()
	local out = {}
	for i = 1, 40 do
		local ok, name, _, sub = pcall(_G.GetRaidRosterInfo, i)
		name = ok and Text(name)
		if name then
			out[name:gsub("%-.*$", "")] = Num(sub) or 1
		end
	end
	return out
end

local CAND_LINES = 8
function R.LayCand(row, top)
	local c = R.cand or BuildCand()
	R.candRow = row
	local list, groups, me = {}, Groups(), MyName()
	for i = 1, row.test and #(row.cands or {}) or 0 do
		list[#list + 1] = row.cands[i]
	end
	for i = 1, row.test and 0 or 40 do
		local ok, name, _, className = pcall(_G.GetMasterLootCandidate, row.slot, i)
		name = ok and Text(name)
		if name then
			local short = name:gsub("%-.*$", "")
			list[#list + 1] = { index = i, name = short, class = Text(className), group = groups[short] or 1, self = short == me }
		end
	end
	local byClass = R.ML.sort == "class"
	table.sort(list, function(a, b)
		if byClass and a.class ~= b.class then
			return (a.class or "") < (b.class or "")
		elseif not byClass and a.group ~= b.group then
			return a.group < b.group
		end
		return a.name < b.name
	end)
	local find = (c.search:GetText() or ""):lower()
	local left = R.CAND_X
	local cellW = (R.W - 22 - left) / 5
	-- the places: by group, a line a group (five a line); by class, five a line in that order
	local line, col, lastGroup = 0, 0, nil
	for _, l in ipairs(c.labels) do
		l:Hide()
	end
	for i, b in ipairs(c.cells) do
		local e = list[i]
		if e then
			if not byClass then
				if lastGroup ~= e.group then
					if lastGroup ~= nil then
						line = line + 1
					end
					col, lastGroup = 0, e.group
					local lab = c.labels[line + 1]
					if lab then
						lab:SetText("G" .. e.group)
						lab:ClearAllPoints()
						lab:SetPoint("RIGHT", c, "TOPLEFT", left - 4, -(44 + line * R.LINE))
						lab:Show()
					end
				elseif col >= 5 then
					line, col = line + 1, 0
				end
			elseif col >= 5 then
				line, col = line + 1, 0
			end
			b.cand = e
			b:ClearAllPoints()
			b:SetPoint("LEFT", c, "TOPLEFT", left + col * cellW, -(44 + line * R.LINE))
			b:SetWidth(cellW - 4)
			b.text:SetText(e.self and Tr(TEXT.you) or e.name)
			local r, g, bl = MelloUI.Colours.Class(e.class)
			b.text:SetTextColor(r or 1, g or 1, bl or 1)
			local match = find == "" or e.name:lower():find(find, 1, true) ~= nil
			b:SetAlpha(match and 1 or 0.3)
			b:EnableMouse(match)
			b:SetShown(line < CAND_LINES)
			col = col + 1
		else
			b:Hide()
		end
	end
	if c.chips then
		c.chips:Select(R.ML.sort)
	end
	-- (as tall as the lines in use: a party's one or two, a raid's eight)
	local used = #list > 0 and min(CAND_LINES, line + 1) or 1
	local h = 30 + used * R.LINE + 14
	c:ClearAllPoints()
	c:SetPoint("TOPLEFT", R.frame, "TOPLEFT", 0, -top)
	c:SetSize(R.W, h)
	c:Show()
	return h
end

-- the loot window and the loot method: the loot master's items read or let go, the header's looter
function R.LootEvent(event, a1)
	if event == "LOOT_OPENED" or event == "LOOT_READY" then
		local _, me = R.Looter()
		if me and R.Active() then
			R.ReadSlots()
		end
	elseif event == "LOOT_SLOT_CLEARED" then
		local row = R.byId["slot:" .. tostring(Num(a1))]
		if row and not row.winner and not row.rolling then
			R.Fold(row)   -- (taken another way: the game's own menu, or looted)
		end
	elseif event == "LOOT_CLOSED" then
		R.ML.open = false
		for _, row in ipairs(R.rows) do
			if row.master and not row.rolling and not row.winner and not row.rollId then
				R.Fold(row)
			end
		end
	elseif event == "CHAT_MSG_LOOT" then
		R.GivenFromChat(a1)
	end
	R.Want()
end

--------------------------------------------------------------------------------
-- A look's dress, the listeners
--------------------------------------------------------------------------------

-- the window in the dress of the look now (a look switched, a skin, a new frame set): the old dress taken off, the
-- new one's frame, the rings of every medal (the rows', the pool's, the winner's)
function R.Relook()
	if not R.frame then
		return
	end
	local d = R.Dress()
	if R.worn and R.worn ~= d and R.worn.Off then
		R.worn.Off(R.shell)
	end
	R.worn = d
	d.Shell(R.shell, R.mark)
	for _, row in ipairs(R.rows) do
		if row.frame then
			d.Ring(row.frame.medal.ring, R.HR)
		end
	end
	for _, rf in ipairs(R.pool) do
		d.Ring(rf.medal.ring, R.HR)
	end
	if R.badge then
		d.Ring(R.badge.ring, 11)
	end
	R.Layout()
end

-- a look's own dress (Oldschool's file): d = { On() -> bool, Shell(frame, mark) (its frame round the window, its
-- header mark), Off(frame) (taken off again), Ring(texture, radius) (its ring round a medal of that radius: the
-- texture's parent), OnChange(fn) (fn after its own art changed) }
function R.SetDress(d)
	R.painted = d
	if d and d.OnChange then
		d.OnChange(R.Relook)
	end
	R.Changed()
end

-- the window may now show or not: the column's loot rows looked at again, the window with them
function R.Changed()
	local rolls = L()
	if rolls and rolls.Changed then
		rolls.Changed()
	end
	R.Want()
end

--------------------------------------------------------------------------------
-- The test (the user, 2026-11-20: "need a command to test it ingame"): /mello widgets loot | loot raid | loot master
-- -- sample rolls in the window as it is now, in your look and place, nothing sent to the game: your answer, a roll or
-- a give on a test row stays here. Its people: your group's members first (the flight then lands on their frames),
-- then made-up names; one item each run is won by you (its flight to your own frame). Over after about 20 seconds
--------------------------------------------------------------------------------

R.TEST = {
	NAMES = { "Thornwick", "Maybell", "Oakhand", "Greywater", "Brakka", "Senna", "Quill", "Kaelith", "Varn", "Tamsin" },
	CLASSES = { "WARRIOR", "PRIEST", "HUNTER", "MAGE", "ROGUE", "DRUID", "WARLOCK", "SHAMAN", "PALADIN" },
	-- item ID, icon, name, quality (Deadmines and Molten Core's)
	PARTY = { { 5191, "Interface\\Icons\\INV_Sword_31", "Cruel Barb", 3 }, { 5193, "Interface\\Icons\\INV_Misc_Cape_13",
		"Cape of the Brotherhood", 3 }, { 7230, "Interface\\Icons\\INV_Hammer_15", "Smite's Mighty Hammer", 3 },
		{ 10399, "Interface\\Icons\\INV_Belt_06", "Blackened Defias Belt", 2 }, { 1206, "Interface\\Icons\\INV_Misc_Gem_Emerald_01",
		"Moss Agate", 2 } },
	RAID = { { 18816, "Interface\\Icons\\INV_Weapon_ShortBlade_05", "Perdition's Blade", 4 }, { 19145,
		"Interface\\Icons\\INV_Chest_Cloth_33", "Robe of Volatile Power", 4 }, { 19137, "Interface\\Icons\\INV_Belt_18",
		"Onslaught Girdle", 4 } },
	LAST = 20,   -- the test's rows folded this long after it began
	n = 0, run = 0,
	SAYS = "Loot window test: sample rolls for about 20 seconds. Your clicks stay here; nothing is sent to the game.",
	OFF = "Loot window test: the window is off (Reminders > Widgets > Loot Rolls), or the game's Gamepad UI keeps its own boxes.",
}

-- your group's members (name, class token) then made-up ones, `count` in all (you not among them)
local function TestPeople(count)
	local out, seen = {}, {}
	local FX = MelloUI.FrameFX
	for _, unit in ipairs(FX.Members()) do
		local okN, name = pcall(UnitName, unit)
		local okC, _, class = pcall(UnitClass, unit)
		name, class = okN and Text(name), okC and Text(class)
		local okS, isMe = pcall(UnitIsUnit, unit, "player")
		if name and not (okS and not Secret(isMe) and isMe) and not seen[name] and #out < count then
			seen[name] = true
			out[#out + 1] = { name = name, class = class }
		end
	end
	local T, i = R.TEST, 0
	while #out < count do
		i = i + 1
		local name = T.NAMES[(i - 1) % #T.NAMES + 1] .. (i > #T.NAMES and tostring(math.floor((i - 1) / #T.NAMES) + 1) or "")
		if not seen[name] then
			seen[name] = true
			out[#out + 1] = { name = name, class = T.CLASSES[(i - 1) % #T.CLASSES + 1] }
		end
	end
	return out
end

local function MyClass()
	local ok, _, class = pcall(UnitClass, "player")
	return ok and Text(class) or "WARRIOR"
end

-- a test row of item `it`: its link built from the item's ID (the game's tooltip shows it); everyone of `people` and
-- you still to pick, as the game lists a group (a loot master's row: none until its roll)
local function TestRow(it, opts, people)
	local T = R.TEST
	T.n = T.n + 1
	local q = MelloUI.FrameFX.LootTint(it[4])
	local hex = q and q.hex:sub(2) or "ffffff"
	local row = { id = "test:" .. T.n, test = T.run, icon = it[2], name = it[3], quality = it[4], canNeed = true, canGreed = true,
		link = "|cff" .. hex .. "|Hitem:" .. it[1] .. "::::::::60:::::|h[" .. it[3] .. "]|h|r", picks = { n = 0 },
		startAt = GetTime(), total = opts.total or 30, born = GetTime(), fav = opts.fav, master = opts.master }
	if not opts.master then
		R.TestWaiting(row, people or {})
	end
	R.rows[#R.rows + 1] = row
	R.byId[row.id] = row
	return row
end

-- everyone of `people` and you, still deciding
function R.TestWaiting(row, people)
	row.picks.n = 0
	for _, who in ipairs(people) do
		if not who.self then
			row.picks.n = row.picks.n + 1
			row.picks[row.picks.n] = { name = who.name, class = who.class, kind = "wait" }
		end
	end
	row.picks.n = row.picks.n + 1
	row.picks[row.picks.n] = { name = MyName() or "You", class = MyClass(), kind = "wait", self = true }
end

-- a pick on a test row at `at` seconds (its number as it comes in), then the window looked at again
local function TestPick(row, at, who, kind, roll)
	C_Timer.After(at, function()
		if R.byId[row.id] ~= row or row.winner then
			return
		end
		for i = 1, row.picks.n do
			local p = row.picks[i]
			if p.name == who.name and not p.self then
				p.kind, p.roll = kind, kind ~= "pass" and roll or nil
			end
		end
		R.Want()
	end)
end

-- your answer on a test row: your number drawn here
function R.TestAnswer(row, kind)
	for i = 1, row.picks.n do
		local p = row.picks[i]
		if p.self then
			p.kind, p.roll = kind, kind ~= "pass" and math.random(1, 100) or nil
		end
	end
end

-- a test row's end: the highest Need, else the highest Greed, wins (you, if `mine` and you did not pass); then the
-- window's own win (the flight) on its next pass
local function TestEnd(row, at, mine)
	C_Timer.After(at, function()
		if R.byId[row.id] ~= row or row.winner then
			return
		end
		local best
		for i = 1, row.picks.n do
			local p = row.picks[i]
			if mine and p.self and p.kind ~= "pass" then
				p.roll = 100
				if p.kind == "wait" then
					p.kind = "need"
				end
			end
			if (p.kind == "need" or p.kind == "greed") and p.roll and (not best or ByRoll(p, best)) then
				best = p
			end
		end
		row.ended = GetTime()
		if best then
			row.winner = { name = best.name, class = best.class, self = best.self, kind = best.kind, roll = best.roll }
		else
			row.allPassed = true
		end
		R.Want()
	end)
end

-- a sample roll for the loot master's test row (Roll): picks for six seconds, then its winner
function R.TestRoll(row)
	row.rolling = true
	local people = row.cands or TestPeople(4)
	R.TestWaiting(row, people)
	for i, who in ipairs(people) do
		if not who.self then
			TestPick(row, 0.5 + i * 0.7, who, i % 3 == 0 and "pass" or (i % 2 == 0 and "greed" or "need"), math.random(1, 100))
		end
	end
	TestEnd(row, 6.5, false)
	R.Layout()
end

function R.Test(kind)
	if not R.Active() then
		MelloUI:Print(R.TEST.OFF)
		return
	end
	local T = R.TEST
	T.run = T.run + 1
	local run = T.run
	-- (an earlier test's rows away at once: one test at a time)
	R.testLooter = nil
	for i = #R.rows, 1, -1 do
		local row = R.rows[i]
		if row.test then
			if row.frame then
				row.frame:Hide()
				row.frame.row = nil
				R.pool[#R.pool + 1] = row.frame
				row.frame = nil
			end
			table.remove(R.rows, i)
			R.byId[row.id] = nil
		end
	end
	R.openId = nil
	MelloUI:Print(T.SAYS)
	if kind == "raid" then
		local people = TestPeople(39)
		local big = TestRow(T.RAID[1], { total = 16 }, people)
		for i, who in ipairs(people) do
			local k, roll = "pass", nil
			if i <= 7 then
				k, roll = "need", 100 - i * 4
			elseif i <= 11 then
				k, roll = "greed", 95 - i * 3
			elseif i > 32 then
				k = nil   -- (still deciding when the roll ends)
			end
			if k then
				TestPick(big, 0.3 + (i % 13) * 0.35, who, k, roll)
			end
		end
		TestEnd(big, 12, false)
		for j = 2, 3 do
			local row = TestRow(T.RAID[j], { total = 30 }, people)
			for i = 1, 14 do
				local who = people[(i * j) % #people + 1]
				TestPick(row, 0.5 + i * 0.4, who, i % 3 == 0 and "greed" or (i % 4 == 0 and "need" or "pass"), math.random(1, 100))
			end
		end
	elseif kind == "master" then
		R.testLooter = MyName() or "You"
		local people = TestPeople(4)
		local cands = { { index = 0, name = MyName() or "You", class = MyClass(), group = 1, self = true } }
		for i, who in ipairs(people) do
			cands[#cands + 1] = { index = i, name = who.name, class = who.class, group = i < 3 and 1 or 2 }
		end
		for j = 1, 3 do
			local row = TestRow(T.RAID[j], { master = true })
			row.cands = cands
		end
	else
		local people = TestPeople(4)
		local fav = TestRow(T.PARTY[1], { fav = true, total = 30 }, people)
		local mine = TestRow(T.PARTY[2], { total = 30 }, people)
		local theirs = TestRow(T.PARTY[3], { total = 30 }, people)
		local belt = TestRow(T.PARTY[4], { total = 30 }, people)
		TestRow(T.PARTY[5], { total = 30 }, people)
		for i, who in ipairs(people) do
			TestPick(mine, 0.6 + i * 0.6, who, i == 3 and "pass" or "greed", 20 + i * 11)
			TestPick(theirs, 0.9 + i * 0.7, who, i == 1 and "need" or (i == 2 and "pass" or "greed"), i == 1 and 97 or 30 + i * 9)
			TestPick(belt, 1.2 + i * 0.8, who, i % 2 == 0 and "greed" or "pass", 15 + i * 13)
			TestPick(fav, 3 + i * 0.9, who, i == 2 and "need" or "pass", 41 + i)
		end
		TestEnd(mine, 7, true)     -- (yours: its flight to your own frame)
		TestEnd(theirs, 10, false) -- (a member's: to their frame when they are in your group)
	end
	R.Want()
	-- (the test's rows still up then folded; the Master Loot test's looter let go)
	C_Timer.After(T.LAST, function()
		if T.run ~= run then
			return
		end
		R.testLooter = nil
		for _, row in ipairs(R.rows) do
			if row.test == run and not row.folding then
				R.Fold(row)
			end
		end
	end)
end

local LR = L()
if LR then
	LR.Display = R.Active
	MelloUI:On("lootrolls", R.Heard, "Loot Roll Window")
	MelloUI:On("look:effects", function()
		R.Relook()
		R.Changed()
	end, "Loot Roll Window (the look)")
	MelloUI:On("skin", R.Relook, "Loot Roll Window (the skin)")
	MelloUI:On("setting", function(name, key)
		if name == "Widgets" and key == "loot" then
			R.Changed()
		end
	end, "Loot Roll Window (Loot Rolls)")
	MelloUI:AddMoverSource(function()
		if R.Active() then
			R.Build()
		end
	end)
	-- (/mello widgets loot | loot raid | loot master: the test, on the Widgets module's own words -- Core/Config.lua's
	-- "<module> <word>")
	local widgets = MelloUI:GetModule("Widgets")
	if widgets then
		widgets.SlashWords = widgets.SlashWords or {}
		widgets.SlashWords.loot = function() R.Test("party") end
		widgets.SlashWords["loot raid"] = function() R.Test("raid") end
		widgets.SlashWords["loot master"] = function() R.Test("master") end
	end
	-- (Master Loot: the loot window, the loot method, the game's "receives loot" line; one frame of events, nothing
	-- drawn until a roll or the loot master's items need the window)
	R.events = CreateFrame("Frame")
	for _, e in ipairs({ "LOOT_OPENED", "LOOT_READY", "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "PARTY_LOOT_METHOD_CHANGED",
		"CHAT_MSG_LOOT" }) do
		pcall(R.events.RegisterEvent, R.events, e)
	end
	R.events:SetScript("OnEvent", function(_, event, a1)
		R.LootEvent(event, a1)
	end)
end
