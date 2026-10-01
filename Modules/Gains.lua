--------------------------------------------------------------------------------
-- MelloUI - Gains
--
-- (user, 2026-09-26: "a small window widget next to the character, which
-- shows the changes in Skills gained, for example, "+1 to Defense", "+1 1h
-- Sword""; sketch B picked -- floating lines, each on a soft shade, "ofc
-- course that text also has shading behind it"; then "can we also include
-- there gained items, and bought items in that skillups window?")
--
-- ONE feed of what the character gains, floating beside it: right of the
-- screen's centre, a little below (where the character stands in the usual
-- camera), no frame. Each line lies on the soft dark band that hugs its text
-- (MelloUI.Shade:Band in the look every soft-shaded line shares,
-- MelloUI.Shade.TEXT: the on-screen notice's colour, strength and soft ends;
-- the stacked lines' padding, Shade:LinePadY, so two bands that meet read as
-- one), the notice's soft text shadow (MelloUI.CentreLook.Shadow), no
-- outline unless the notice's Outlined Text is on (Tweaks noticeOutline),
-- Font Style applying (MelloUI:StyleFont, the interface text role).
--   a skill   "+1  Defense  57 / 80": the "+1" in the palette's gold
--             (selectedTrim), the name in its text colour, the value and the
--             cap after it quiet (Show Skill Values): smaller, in the text
--             colour a little faded (TAIL_ALPHA), never mutedText -- over
--             bright ground (snow, sand, the pale stone of the user's spot)
--             under the band mutedText reads at about 1.5-2.6 : 1 (the
--             notice's COLOUR note), the faded text at 3.1 : 1 and more
--   an item   "+3  <gem> Linen Cloth": the count in gold, the item's quality
--             gem (MelloUI.QuestInk's QI.Gem, the one gem of the interface,
--             in the game's own quality colour, ITEM_QUALITY_COLORS), the
--             name in the palette's text colour. Not the quality colour: on
--             the dark band the game's blue and purple read at about 3-4 : 1
--             and less over bright ground (the eye-strain rule wants the
--             full text colour for a line to read), and darkened they would
--             read worse; the gem says the quality at a glance, as the
--             tooltips' "ink plus gems" does. A long name is cut ("...") at
--             MAX_NAME, so the longest line still fits the holder, which the
--             mover keeps on the screen
--   bought    the same line with a quiet "bought" after it (as the value)
-- Newest on top, at most MAX_LINES; each holds for Show For (5 s), then fades
-- out, so the older ones go first. A gain of the same skill or item while its
-- line shows adds to that line ("+2 Defense", "+6 Linen Cloth"), brings it to
-- the top and starts its hold again. A burst (a loot window, a stack bought)
-- makes one line per item, never a flood: the pass's items are put lowest
-- quality first, so the best end on top, and only the last MAX_LINES of them
-- (the lower ones would only be dropped); past MAX_LINES the oldest line goes.
-- The hold and the fades are one engine-driven group per line
-- (MelloUI.Anim:Mirror: in, held, out, then hidden; asked again it starts
-- again); the lines below a new one slide down a slot (Anim:To). Reduce
-- Motion: no slide, the lines jump to their slots, and a plain fade.
--
-- What counts, read locale-free (never from chat text):
--   skills    C_SkillInfo (Forever's API: GetNumSkillLines, GetSkillLineInfo
--             (index) -> a table of skillID, name, isHeader, rank, maxRank,
--             skillLineCategoryID, parentSkillLineID ...; Blizzard_UIPanels_
--             Game/Camelot/SkillsFrame.lua reads it the same way). The lines
--             the game's Skills tab lists: not a header, not a Class Skills
--             line (category 7, which the tab leaves out), no parent line.
--             Kept by skillID from the snapshot on; SKILL_LINES_CHANGED is
--             compared with it on the next frame. A line under a collapsed
--             header is not listed (the client leaves it out; the Skills tab
--             filters nothing itself): one known keeps its value and is read
--             by its ID (GetSkillLineInfoByID); while a header is collapsed
--             the skill lines a character can have (SEED: the Skills tab's
--             weapon lines, Defense, the professions, the secondary skills,
--             the languages) are read by their IDs too, so a /reload with a
--             header collapsed still knows them. The headers are never
--             expanded (the player's Skills tab left as it is). A newly
--             learned line is only noted, never a "+1"; a raised cap only
--             updates the cap a line shows, and so does a rank that comes
--             with it and lands on the new cap in one jump (a trainer's or a
--             book's rank: Riding 75 / 75 -> 150 / 150)
--   items     what the character owns, per item: C_Item.GetItemCount(id,
--             includeBank, false, includeReagentBank, includeAccountBank):
--             the bags, the gear (the game's own count includes what is worn:
--             its tabard vendor takes that count as "owned"), the bank as the
--             client knows it. A count that rises is a gain, so moving items
--             between the bags, the bank or your gear is never one. The items
--             looked at: every item of a bag the game says changed
--             (BAG_UPDATE, then the pass on the next frame: a whole loot
--             window, a purchase and its money come in together), the
--             carried bags only (the backpack, the bags, the reagent bag, the
--             keyring). Around the edges:
--               worn    an item that goes on or off (the gear's and the bag
--                       slots' items read at every pass) is never a gain,
--                       whatever the client counts
--               bank    while the bank is open an item never seen before is
--                       taken as come from the bank; at its opening and its
--                       closing every count is taken again, silently (the
--                       client may know the bank's items only while it is
--                       open). Whether a bank or a merchant is open when the
--                       items start (a profile load, a switch) is asked of
--                       the game (C_PlayerInteractionManager)
--               hidden  a bag slot read secret keeps what it held and asks
--                       for the pass again after combat; one secret at the
--                       snapshot (a /reload in a fight) leaves the bag not
--                       snapshotted: its next read takes the items never
--                       seen before as they are, silently
--               new     an item seen for the first time: what is in the bags
--                       and the gear is the gain, what lies in the bank was
--                       there before
--   bought    an item gained while a merchant is open and your money went
--             down in the same moment (PLAYER_MONEY, heard only while the
--             merchant is open; the purchase's money and its item come in
--             one update, and the pass runs on the next frame): a purchase,
--             a buyback too. A sale takes an item: no line for it (its money
--             is one, below).
--   money     (0.17.0, the user's meter-and-gains plan) a rise of your money
--             (GetMoney, PLAYER_MONEY while Money is on): loot, quest
--             rewards, sales, mail, trades. "+" in gold and the game's own
--             money string with its coins (GetMoneyString: never coin
--             textures by hand); ONE line that sums while it shows. Spending
--             makes no line. A secret read is skipped: the next one compares
--             with the last plain sum, so nothing is lost
--   currency  (0.17.0) another currency gained (CURRENCY_DISPLAY_UPDATE with
--             a plain positive change, while Currencies is on): "+15 <icon>
--             Honor Points", the currency's own icon and name
--             (C_CurrencyInfo.GetCurrencyInfo), one line per currency
-- Stacks gained together sum: the counts are compared, not the stacks.
-- Item Names In Quality Colour (0.17.0, off): an item's name in the game's
-- quality colour beside its gem (else the palette's text colour; the
-- names' colour is set by Fill and again on the palette).
--
-- Secret values (MelloUI.Safe, the secret test first): a skill or item read
-- that comes back secret or fails leaves what was known as it was; it is read
-- again after combat (PLAYER_REGEN_ENABLED, registered only while one waits)
-- or with the next change. An item whose name or quality the client has not
-- loaded yet waits for it (GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT,
-- registered only while one waits; a load that failed drops its gain).
--
-- Its place: MelloUI's one mover and position store (key "gains", anchor
-- TOPLEFT; its default TOPLEFT at the screen's centre, 110 right and 30
-- down): Edit Layout shows four sample lines there on its plate to drag,
-- its Reset puts it back, profiles carry it as every mover's.
--
-- Cost. Nothing is made at login: the module's OnEnable waits for the
-- login's frames to be over (MelloUI:AfterLogin) and then makes one event
-- frame and takes the snapshot (data only: numbers in tables). The lines, the
-- holder and the mover come with the first gain (or Edit Layout's first
-- open). Only a switched-on kind's events are registered; PLAYER_MONEY
-- while Money is on or a merchant is open. Nothing runs per frame: no OnUpdate of its
-- own, no ticker, no timer (Kit:NextFrame for the pass); Anim's driver runs
-- only while a line slides. A bag event makes no garbage; the pass makes the
-- line's texts only. The game's skill API hands a table per line
-- (GetSkillLineInfo), read once per change.
--
-- Settings (this page): the module's switch (on), Skill Ups, Show Skill
-- Values, Looted & Received Items, Bought Items, Junk Items, Money,
-- Currencies, Item Names In Quality Colour, Show For.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Gains")

local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text

local pairs, type, pcall, format = pairs, type, pcall, string.format

local OWNER = "Gains"
local MOVER_KEY = "gains"
local MAX_LINES = 5
local SIZE, TAIL_SIZE = 16, 13      -- the line's text, and its value / cap or "bought"
local TAIL_ALPHA = 0.85             -- the tail's text colour, a little faded: quiet, still 3 : 1 over snow
local PITCH = 26                    -- one line's slot
local MAX_NAME = 230                -- a longer name is cut ("...")
local WIDTH = 420                   -- the holder (the drag area): as wide as the longest line, its soft ends too
local GAP = 5                       -- between the count, the gem and the name
local FADE_IN, FADE_OUT, SLIDE = 0.2, 1.2, 0.2
local HOLD_DEFAULT, HOLD_MIN, HOLD_MAX = 5, 2, 15
local SAMPLE_HOLD = 3600            -- Edit Layout's samples: held until it closes or pauses
local BUY_WINDOW = 2                -- seconds: money spent at a merchant and the item it bought
local POOR = 0                      -- the junk (grey) quality
local CLASS_SKILLS = 7              -- the category the game's Skills tab leaves out (SkillsFrame.lua)
local TAIL_VALUE, TAIL_BOUGHT = "  %d / %d", "  bought"

-- the skill lines a character can have, read by their IDs while a header of
-- the Skills tab is collapsed (the client leaves a collapsed header's lines
-- out of its list): the weapon lines (SkillsFrame.lua's WEAPON_SKILL_LINES,
-- Fist Weapons too), Defense (its DEFENSE_SKILL_ID), the professions, the
-- secondary skills, the languages. A line the character lacks answers
-- nothing and is left out
local SEED = {
	43, 44, 45, 46, 54, 55, 136, 160, 162, 172, 173, 176, 226, 228, 229, 473, 3014,   -- weapons
	95,                                                                                  -- Defense
	164, 165, 171, 182, 186, 197, 202, 333, 393, 755, 773,                               -- professions
	129, 185, 356, 762, 633,                                                             -- secondary
	98, 109, 111, 113, 115, 137, 138, 139, 140, 141, 313, 315, 673, 759,                  -- languages
}

-- the look every soft-shaded line shares (Core/Shade.lua): the band's colour,
-- strength and soft ends, the text's shadow; stacked lines' padding
local TEXT = MelloUI.Shade.TEXT
local PAD_X, FEATHER = TEXT.padX, TEXT.feather
local PAD_Y = MelloUI.Shade:LinePadY(SIZE)

-- Edit Layout's sample lines, top to bottom (English, as the notice's)
local SAMPLES = {
	{ kind = "skill", count = 1, name = "Defense", rank = 57, cap = 80 },
	{ kind = "item", count = 3, name = "Linen Cloth", quality = 1 },
	{ kind = "bought", count = 5, name = "Refreshing Spring Water", quality = 1 },
	{ kind = "money", count = 25734 },
}

local function Seconds(value)
	return format("%d s", value)
end

local M = MelloUI:RegisterModule("Gains", {
	title = "Gains",
	desc = "Short lines beside your character show what you just gained: a skill point, the items you loot or receive, and what you buy. You can move them in Edit Layout.",
	icon = "Interface\\Icons\\INV_Misc_Bag_08",
	flavour = "Every skill point and every new item, told softly beside your character, then gone.",
	group = "Quests and travel", navOrder = 6,
	role = "feature",
	enabledByDefault = true,
	defaults = {
		skills = true,
		values = true,
		items = true,
		bought = true,
		junk = true,
		money = true,
		currencies = true,
		qualityNames = false,
		hold = HOLD_DEFAULT,
	},
	options = {
		{ type = "header", name = "Show" },
		{ type = "toggle", key = "skills", name = "Skill Ups",
		  desc = "A line when one of your skills goes up: weapon skills, Defense, professions, secondary skills and languages." },
		{ type = "toggle", key = "values", parent = "skills", name = "Show Skill Values",
		  desc = "The skill's new value and its cap after its name, such as 57 / 80." },
		{ type = "toggle", key = "items", name = "Looted & Received Items",
		  desc = "A line for each item that comes into your bags: loot, quest rewards, crafted items, mail and trades. Moving items between your bags, the bank and your gear never counts." },
		{ type = "toggle", key = "bought", name = "Bought Items",
		  desc = "A line for what you buy from a merchant, buybacks too, marked as bought." },
		{ type = "toggle", key = "junk", name = "Junk Items",
		  desc = "Also show junk (grey) items. Off: they are left out." },
		{ type = "toggle", key = "money", name = "Money", new = "0.17.0",
		  desc = "A line when your money goes up: loot, quest rewards, sales, mail and trades, with the game's coins. Several gains in a row add up on one line. Spending makes no line." },
		{ type = "toggle", key = "currencies", name = "Currencies", new = "0.17.0",
		  desc = "A line for the other currencies you gain (honor, tokens, marks), with the currency's own icon." },
		{ type = "toggle", key = "qualityNames", name = "Item Names In Quality Colour", new = "0.17.0",
		  desc = "Item names in their quality colour (green, blue, purple) beside the quality gem. Blue and purple read less well over bright ground. Off: the names in the text colour." },
		{ type = "header", name = "Lines" },
		{ type = "slider", key = "hold", name = "Show For", min = HOLD_MIN, max = HOLD_MAX, step = 1, format = Seconds,
		  desc = "How long each line stays before it fades. Gaining the same skill or item again adds to its line and starts it over." },
	},
})

--------------------------------------------------------------------------------
-- Reads (secret-safe: a secret or failed answer is nil; the game's functions
-- are looked up when called, a client without one simply lacks that part)
--------------------------------------------------------------------------------

-- f(...)'s first result as it came (a secret one too), nil when f is not a
-- function or raised
local function Ask(f, ...)
	if type(f) ~= "function" then
		return nil
	end
	local ok, a = pcall(f, ...)
	if not ok then
		return nil
	end
	return a
end

-- a function of a game namespace (C_Item.GetItemCount), or nil
local function Api(space, name)
	local t = _G[space]
	local f = type(t) == "table" and t[name]
	return type(f) == "function" and f or nil
end

-- what the character owns of an item: the bags, the gear, the bank as the
-- client knows it (the character's, its reagent part and the account's)
local function Count(id)
	local f = Api("C_Item", "GetItemCount")
	if f then
		return Num(Ask(f, id, true, false, true, true))
	end
	return Num(Ask(_G.GetItemCount, id, true))
end

-- what the bags and the gear hold of it (no bank)
local function Carried(id)
	local f = Api("C_Item", "GetItemCount")
	if f then
		return Num(Ask(f, id))
	end
	return Num(Ask(_G.GetItemCount, id))
end

local function ItemName(id)
	local f = Api("C_Item", "GetItemNameByID")
	local name = f and Ask(f, id)
	if name == nil and type(_G.GetItemInfo) == "function" then
		name = Ask(_G.GetItemInfo, id)
	end
	return Text(name)
end

local function ItemQuality(id)
	local f = Api("C_Item", "GetItemQualityByID")
	local q = f and Num(Ask(f, id))
	if q == nil and type(_G.GetItemInfo) == "function" then
		local ok, _, _, third = pcall(_G.GetItemInfo, id)
		q = ok and Num(third) or nil
	end
	return q
end

-- the game's own colour of an item quality, or nil (ITEM_QUALITY_COLORS, the
-- game's table, as the bag gems read it; a client without it asks C_Item)
local function QualityColour(q)
	local list = _G.ITEM_QUALITY_COLORS
	local r, g, b
	if type(list) == "table" then
		local c = list[q]
		if type(c) ~= "table" then
			return nil
		end
		r, g, b = c.r, c.g, c.b
	else
		local f = Api("C_Item", "GetItemQualityColor")
		if not f then
			return nil
		end
		local ok
		ok, r, g, b = pcall(f, q)
		if not ok then
			return nil
		end
	end
	r, g, b = Num(r), Num(g), Num(b)
	if r and g and b then
		return r, g, b
	end
	return nil
end

local function Money()
	return Num(Ask(_G.GetMoney))
end

local function InCombat()
	return MelloUI.InCombat()
end

--------------------------------------------------------------------------------
-- The lines: MelloUI.Feed (Core/Feed.lua, 0.17.0: the engine lifted from
-- here, now shared with Combat Text's feed). Its holder (the mover's frame,
-- click-through) and lines come with the first gain (or Edit Layout's first
-- open); a skill's or an item's line is its kind and id there.
--------------------------------------------------------------------------------

local feed   -- (made at the end of this section)
local S = {
	started = false, skillsOn = false, itemsOn = false, moneyOn = false, currenciesOn = false, preview = false,
	merchant = false, bank = false, money = nil, spentAt = nil,
	itemsQueued = false, skillsQueued = false, skillRetry = false, slotRetry = false, nRetry = 0, nWait = 0,
}

local function Hold()
	local v = Num(M.db and M.db.hold) or HOLD_DEFAULT
	if v < 1 then
		v = 1
	end
	return v
end

-- the notice's Outlined Text (Tweaks noticeOutline, off by default)
local function Outline()
	local Look = MelloUI.CentreLook
	return Look and Look.Setting and Look.Setting("noticeOutline") and true or false
end

local function StyleText(fs, size, outline)
	local object = _G.GameFontHighlight
	if type(object) == "table" then
		fs:SetFontObject(object)
		if MelloUI.StyleFont then
			MelloUI:StyleFont(fs, "fontText", object, size, "", outline)
		end
	end
end

local function Shadow(fs)
	local Look = MelloUI.CentreLook
	if Look and Look.Shadow then
		Look.Shadow(fs)
	end
end

-- a long name cut at MAX_NAME ("..."), a short one as wide as its text (the
-- band follows by its anchors); a width that cannot be read is left
local function Cut(name)
	name:SetWidth(0)
	local w = Num(Ask(name.GetUnboundedStringWidth, name)) or Num(Ask(name.GetStringWidth, name))
	if w and w > MAX_NAME then
		name:SetWidth(MAX_NAME)
	end
end

local function Restyle(row)
	local outline = Outline()
	StyleText(row.plus, SIZE, outline)
	StyleText(row.name, SIZE, outline)
	StyleText(row.tail, TAIL_SIZE, outline)
	Cut(row.name)   -- (measured again in the new font)
end

local function Home(frame)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "CENTER", 110, -30)
end

-- its mover live (its plate in Edit Layout) while the module is on
local function ModuleOn()
	return M.isEnabled and true or false
end

-- a line's texts and band (the feed made the line)
local function NewRow(row)
	local plus = row:CreateFontString(nil, "OVERLAY")
	local name = row:CreateFontString(nil, "OVERLAY")
	local tail = row:CreateFontString(nil, "OVERLAY")
	for _, fs in pairs({ plus, name, tail }) do
		fs:SetWordWrap(false)
		fs:SetJustifyH("LEFT")
		fs:SetShadowOffset(TEXT.shadowX, TEXT.shadowY)
		Shadow(fs)
	end
	row.plus, row.name, row.tail = plus, name, tail
	-- the count's left edge in far enough that the band's soft end starts
	-- at the holder's
	plus:SetPoint("LEFT", row, "LEFT", PAD_X + FEATHER, 0)
	local QI = MelloUI.QuestInk
	local _, gemSize = QI.GemLead(SIZE)
	local gem = QI.Gem(row, gemSize)
	gem:SetPoint("LEFT", plus, "RIGHT", GAP, 0)
	row.gem = gem
	-- the value / cap or "bought" on the name's baseline, right after it
	tail:SetPoint("BOTTOMLEFT", name, "BOTTOMRIGHT", 0, 0)
	local W = MelloUI.Widgets
	W.Paint(plus, "selectedTrim", "text")
	W.Paint(tail, "text", "text", TAIL_ALPHA)   -- (small text is never mutedText: the palette rule)
	-- (the name's colour is Fill's: the text colour, or an item's quality
	-- colour with Item Names In Quality Colour; Repaint sets it again)
	Restyle(row)
	-- the band from the count's left to the tail's right: it follows the
	-- texts by its anchors, whatever their length
	row.band = MelloUI.Shade:Band(row, TEXT)
	row.band:Anchor(plus, tail, PAD_X, PAD_Y)
end

-- the money a line says, in the game's own string with its coins
local function MoneyText(copper)
	local fn = _G.GetMoneyString
	if type(fn) == "function" then
		local ok, text = pcall(fn, copper, true)
		if ok and Text(text) then
			return text
		end
	end
	local coin = Api("C_CurrencyInfo", "GetCoinTextureString")
	if coin then
		local ok, text = pcall(coin, copper)
		if ok and Text(text) then
			return text
		end
	end
	return tostring(copper)
end

-- the name's colour: an item's quality colour with Item Names In Quality
-- Colour on, else the palette's text colour (a sample as the kind it stands for)
local function NameColour(row)
	local kind = row.kind
	if kind == "sample" then
		kind = SAMPLES[row.id] and SAMPLES[row.id].kind
	end
	local c = MelloUI.Palette.text
	local r, g, b = c[1], c[2], c[3]
	if (kind == "item" or kind == "bought") and M.db and M.db.qualityNames then
		local qr, qg, qb = QualityColour(row.quality)
		if qr then
			r, g, b = qr, qg, qb
		end
	end
	row.name:SetTextColor(r, g, b)
end

-- what a line says, from its row's fields
local function Fill(row)
	local kind = row.kind
	if kind == "money" then
		row.plus:SetText("+")
	else
		row.plus:SetText("+" .. row.count)
	end
	local gem, name = row.gem, row.name
	local layout = (kind == "item" or kind == "bought") and "item" or "skill"
	if row.layout ~= layout then
		row.layout = layout
		name:ClearAllPoints()
		if layout == "skill" then
			name:SetPoint("LEFT", row.plus, "RIGHT", GAP, 0)
		else
			name:SetPoint("LEFT", gem, "RIGHT", GAP, 0)
		end
	end
	if kind == "money" then
		name:SetText(MoneyText(row.count))
	else
		name:SetText(row.label)
	end
	Cut(name)
	NameColour(row)
	if layout == "skill" then
		gem:Hide()
		if kind == "skill" and M.db and M.db.values ~= false and row.rank and row.cap and row.cap > 0 then
			row.tail:SetText(format(TAIL_VALUE, row.rank, row.cap))
		else
			row.tail:SetText("")
		end
	else
		local r, g, b = QualityColour(row.quality)
		if r then
			gem:SetColour(r, g, b)
		else
			gem:Hide()
		end
		row.tail:SetText(kind == "bought" and TAIL_BOUGHT or "")
	end
end

local Preview   -- (below)

-- a line's fields and texts: a new one counts from 0; a sample shows as
-- the kind it stands for
local function Apply(row, new, count, label, quality, rank, cap)
	if new then
		row.count = 0
	end
	local sample = row.kind == "sample"
	if sample then
		row.count = count
	else
		row.count = row.count + count
	end
	row.label, row.quality, row.rank, row.cap = label, quality, rank, cap
	if sample then
		row.kind = SAMPLES[row.id].kind
		Fill(row)
		row.kind = "sample"
	else
		Fill(row)
	end
end

-- a line for a skill or item: a new one on top, or the one it has added to,
-- raised to the top with its hold started again
local function Put(kind, id, count, label, quality, rank, cap, hold)
	return feed:Put(kind, id, hold or Hold(), Apply, count, label, quality, rank, cap)
end

-- the sample lines while Edit Layout shows, so the place can be dragged on
-- its plate; paused or closed, they fade
Preview = function()
	local want = M.isEnabled and MelloUI:EditingLayout() and true or false
	if want == S.preview then
		return
	end
	S.preview = want
	if want then
		for i = #SAMPLES, 1, -1 do
			local s = SAMPLES[i]
			Put("sample", i, s.count, s.name, s.quality, s.rank, s.cap, SAMPLE_HOLD)
		end
	elseif feed.ui then
		local map = feed:Rows("sample")
		for i = 1, #SAMPLES do
			local row = map[i]
			if row then
				feed:Fade(row)
			end
		end
	end
end

-- the preview's kill (0.17.0, Core/Preview.lua): what a kill brings, as
-- sample lines with the usual hold -- the skill, the loot, the money (not
-- the bought line: no vendor after a kill); its stop fades what is left
local KILL_SAMPLES = { 4, 2, 1 }
local function OnPreview(beat)
	if not M.isEnabled then
		return
	end
	if beat == "kill" and MelloUI.Preview and MelloUI.Preview:Plays("gains") then
		for _, i in ipairs(KILL_SAMPLES) do
			local s = SAMPLES[i]
			Put("sample", i, s.count, s.name, s.quality, s.rank, s.cap)
		end
	elseif beat == "stop" and feed.ui and not S.preview then
		local map = feed:Rows("sample")
		for i = 1, #SAMPLES do
			local row = map[i]
			if row then
				feed:Fade(row)
			end
		end
	end
end

-- the value / cap after every skill line again (Show Skill Values)
local function Tails()
	if not feed.ui then
		return
	end
	for _, row in pairs(feed:Rows("skill")) do
		Fill(row)
	end
end

local function RestyleAll()
	feed:Each(Restyle)
end

-- the text shadows from the palette as it is now (the colours are Kit:Paint's)
local function ShadowRow(row)
	Shadow(row.plus)
	Shadow(row.name)
	Shadow(row.tail)
end

local function Repaint()
	feed:Each(ShadowRow)
	feed:Each(NameColour)
end

-- (Edit Layout open while the first line comes: the samples come first, so
-- the gain is the newest, on top)
local function OnBuild()
	Preview()
end

feed = MelloUI.Feed:New({ name = "MelloUIGains", key = MOVER_KEY, label = "Gains", page = "Gains", when = ModuleOn,
	width = WIDTH, pitch = PITCH, max = MAX_LINES, home = Home, newRow = NewRow, onBuild = OnBuild,
	fadeIn = FADE_IN, fadeOut = FADE_OUT, slide = SLIDE })

--------------------------------------------------------------------------------
-- Skills
--------------------------------------------------------------------------------

local skillRank, skillCap, skillName, skillSeen = {}, {}, {}, {}
local skillPass = 0

local function SkillRose(id, n)
	local db = M.db
	if not (db and db.skills ~= false) then
		return
	end
	local label = skillName[id]
	if label then
		Put("skill", id, n, label, nil, skillRank[id], skillCap[id])
	end
end

-- a cap that changed (a trainer's new rank, a rank given with it): the line
-- shown says it, its count kept
local function SkillCap(id)
	local row = feed:Row("skill", id)
	if row then
		row.rank, row.cap = skillRank[id], skillCap[id]
		Fill(row)
	end
end

-- one skill line: false when a part of it came back secret (read again
-- later), true otherwise (taken, or not one of the Skills tab's lines)
local function SkillLine(info, report, only)
	local id = info.skillID
	if Secret(id) then
		return false
	end
	id = Num(id)
	if not id or (only and id ~= only) then
		return true
	end
	local header, cat, parent = info.isHeader, info.skillLineCategoryID, info.parentSkillLineID
	if Secret(header) or Secret(cat) or Secret(parent) then
		return false
	end
	if header or Num(cat) == CLASS_SKILLS or (Num(parent) or 0) ~= 0 then
		return true
	end
	local rank, cap, name = info.rank, info.maxRank, info.name
	if Secret(rank) or Secret(cap) then
		return false
	end
	rank, cap = Num(rank), Num(cap)
	local old, oldCap = skillRank[id], skillCap[id]
	if not rank or (old == nil and rank <= 0) then
		return true   -- (no rank: a line the character lacks)
	end
	skillSeen[id] = skillPass
	skillRank[id], skillCap[id] = rank, cap
	name = Text(name)
	if name then
		skillName[id] = name
	end
	if report and old then
		-- a rank that comes with a new cap and lands on it in one jump is a
		-- trainer's or a book's (Riding 75 / 75 -> 150 / 150): the cap only
		local given = cap ~= oldCap and rank == cap and rank - old > 1
		if rank > old and not given then
			SkillRose(id, rank - old)
		elseif cap ~= oldCap then
			SkillCap(id)
		end
	end
	return true
end

-- every skill line compared with what was known (report: a rise makes a
-- line; else only noted, the snapshot). false when a read failed
local function ReadSkills(report)
	local num = Num(Ask(Api("C_SkillInfo", "GetNumSkillLines")))
	local get = Api("C_SkillInfo", "GetSkillLineInfo")
	if not (num and get) then
		return false
	end
	skillPass = skillPass + 1
	local whole, collapsed = true, false
	for i = 1, num do
		local info = Ask(get, i)
		if Secret(info) then
			whole = false
		elseif type(info) == "table" then
			if not SkillLine(info, report) then
				whole = false
			end
			local shut = info.isCollapsed
			if Secret(shut) or shut == true then
				collapsed = true
			end
		end
	end
	-- the lines under a collapsed header are not listed: by their ID, the
	-- known ones, and while a header is collapsed the ones a character can
	-- have (SEED)
	local byID = Api("C_SkillInfo", "GetSkillLineInfoByID")
	if byID then
		for id in pairs(skillRank) do
			if skillSeen[id] ~= skillPass then
				local info = Ask(byID, id)
				if Secret(info) then
					whole = false
				elseif type(info) == "table" and not SkillLine(info, report, id) then
					whole = false
				end
			end
		end
		if collapsed then
			for i = 1, #SEED do
				local id = SEED[i]
				if skillSeen[id] ~= skillPass and skillRank[id] == nil then
					local info = Ask(byID, id)
					if Secret(info) then
						whole = false
					elseif type(info) == "table" and not SkillLine(info, report, id) then
						whole = false
					end
				end
			end
		end
	end
	return whole
end

--------------------------------------------------------------------------------
-- Items
--------------------------------------------------------------------------------

local known = {}        -- [itemID] = its count at the last look (Count)
local unread = {}       -- [itemID] = true: its snapshot read failed; the next plain read is its count
local retry = {}        -- [itemID] = true: a read that failed, read again at the next pass
local slots = {}        -- [bag] = { [slot] = itemID or false, n = slots read }
local worn = {}         -- [inventory slot] = itemID or false
local dirty = {}        -- [bag] = true: changed since the last pass
local unsnap = {}       -- [bag] = true: a slot was secret at the snapshot; its items never seen are taken silently
local candidates = {}   -- [itemID] = true: to look at in this pass
local quiet = {}        -- [itemID] = true: put on or taken off in this pass (never a gain)
local carried = {}      -- [bag] = true: the bags looked at
local BAGS, WORN = {}, {}
local waitPlain, waitBought = {}, {}   -- [itemID] = count gained, waiting for the item's data

local function LastBag()
	return Num(_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS) or Num(_G.NUM_BAG_SLOTS) or 4
end

-- the carried bags (the keyring where the client has one) and the worn
-- slots (the gear's, and the bag slots'), once per start
local function Lists()
	for i = #BAGS, 1, -1 do
		BAGS[i] = nil
	end
	for i = #WORN, 1, -1 do
		WORN[i] = nil
	end
	for bag in pairs(carried) do
		carried[bag] = nil
	end
	local getSlots = Api("C_Container", "GetContainerNumSlots")
	local index = type(_G.Enum) == "table" and type(_G.Enum.BagIndex) == "table" and _G.Enum.BagIndex
	local keyring = index and Num(index.Keyring)
	if keyring and keyring < 0 and (Num(Ask(getSlots, keyring)) or 0) > 0 then
		BAGS[#BAGS + 1] = keyring
	end
	local last = LastBag()
	for bag = 0, last do
		BAGS[#BAGS + 1] = bag
	end
	for i = 1, #BAGS do
		carried[BAGS[i]] = true
	end
	local first = Num(_G.INVSLOT_FIRST_EQUIPPED) or 1
	local lastWorn = Num(_G.INVSLOT_LAST_EQUIPPED) or 19
	for slot = first, lastWorn do
		WORN[#WORN + 1] = slot
	end
	local toInv = Api("C_Container", "ContainerIDToInventoryID")
	for bag = 1, last do
		local inv = Num(Ask(toInv, bag))
		if inv and (inv < first or inv > lastWorn) then
			WORN[#WORN + 1] = inv
		end
	end
end

-- a bag's slots read again: every item it held and holds is looked at (a
-- stack that grew keeps its ID). A secret slot (or slot count) keeps what it
-- held; the bag is read again with the next pass, which the end of combat
-- asks for (slotRetry). first: the snapshot's read -- a secret there leaves
-- the bag not snapshotted (unsnap), and a later read of it takes the items
-- it finds that were never seen as they are (unread: no gain), so what was
-- carried all along never shows as come in
local function ScanBag(bag, first)
	local ids = slots[bag]
	if not ids then
		ids = { n = 0 }
		slots[bag] = ids
	end
	for slot = 1, ids.n do
		local old = ids[slot]
		if old then
			candidates[old] = true
		end
	end
	local silent = unsnap[bag]
	local hidden = false
	local n = Ask(Api("C_Container", "GetContainerNumSlots"), bag)
	if Secret(n) then
		hidden = true   -- (what the bag held kept)
	else
		n = Num(n) or 0
		local getID = Api("C_Container", "GetContainerItemID")
		for slot = 1, n do
			local id = Ask(getID, bag, slot)
			if Secret(id) then
				hidden = true
			else
				id = Num(id) or false
				ids[slot] = id
				if id then
					candidates[id] = true
					if silent and known[id] == nil then
						unread[id] = true
					end
				end
			end
		end
		for slot = n + 1, ids.n do
			ids[slot] = nil
		end
		ids.n = n
	end
	if hidden then
		dirty[bag] = true
		S.slotRetry = true
		if first then
			unsnap[bag] = true
		end
	else
		unsnap[bag] = nil
	end
end

-- the worn items: one that went on or came off is never a gain
local function Worn(first)
	local get = _G.GetInventoryItemID
	for i = 1, #WORN do
		local slot = WORN[i]
		local id = Ask(get, "player", slot)
		if not Secret(id) then
			id = Num(id) or false
			local old = worn[slot]
			if old ~= id then
				worn[slot] = id
				if old then
					candidates[old] = true
				end
				if id then
					candidates[id] = true
				end
				if not first then
					if old then
						quiet[old] = true
					end
					if id then
						quiet[id] = true
					end
				end
			end
		end
	end
end

local function Retry(id)
	if not retry[id] then
		retry[id] = true
		S.nRetry = S.nRetry + 1
	end
end

-- reads that failed wait for the end of combat (or the next change)
local events
local function RetryLater()
	if (S.nRetry > 0 or S.skillRetry or S.slotRetry) and events and InCombat() then
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
	end
end

-- the snapshot: every carried and worn item's count (data only)
local function Baseline()
	for _, t in pairs({ known, unread, retry, slots, worn, dirty, unsnap, candidates, quiet }) do
		for k in pairs(t) do
			t[k] = nil
		end
	end
	S.nRetry, S.slotRetry = 0, false
	Lists()
	for i = 1, #BAGS do
		ScanBag(BAGS[i], true)
	end
	Worn(true)
	for id in pairs(candidates) do
		candidates[id] = nil
		local n = Count(id)
		if n then
			known[id] = n
		else
			unread[id] = true
			Retry(id)
		end
	end
	RetryLater()
end

-- the gains of one pass, shown together (ShowGains): lowest quality first,
-- so the best are put last and end on top; only the last MAX_LINES are put
-- (the ones before would be dropped by them). Kept in arrays that are
-- emptied, never made again (a pass makes no table)
local gainId, gainN, gainBought, gainQuality, gainLabel, gainOrder = {}, {}, {}, {}, {}, {}
local nGains = 0

local function Earlier(a, b)
	local qa, qb = gainQuality[a], gainQuality[b]
	if qa ~= qb then
		return qa < qb
	end
	return gainId[a] > gainId[b]   -- (a tie: in a fixed order)
end

local function ShowGains()
	local n = nGains
	if n == 0 then
		return
	end
	for i = 1, n do
		gainOrder[i] = i
	end
	for i = n + 1, #gainOrder do
		gainOrder[i] = nil
	end
	if n > 1 then
		table.sort(gainOrder, Earlier)
	end
	local from = n - MAX_LINES + 1
	for k = from > 1 and from or 1, n do
		local i = gainOrder[k]
		Put(gainBought[i] and "bought" or "item", gainId[i], gainN[i], gainLabel[i], gainQuality[i])
	end
	for i = 1, n do
		gainLabel[i] = nil
	end
	nGains = 0
end

local Gained   -- (below)

local function Wait(id, n, bought)
	if waitPlain[id] == nil and waitBought[id] == nil then
		S.nWait = S.nWait + 1
		if S.nWait == 1 and events then
			events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
			events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
		end
		local request = Api("C_Item", "RequestLoadItemDataByID")
		if request then
			pcall(request, id)
		end
	end
	if bought then
		waitBought[id] = (waitBought[id] or 0) + n
	else
		waitPlain[id] = (waitPlain[id] or 0) + n
	end
end

local function StopWaiting()
	for id in pairs(waitPlain) do
		waitPlain[id] = nil
	end
	for id in pairs(waitBought) do
		waitBought[id] = nil
	end
	S.nWait = 0
	if events then
		events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
		events:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
	end
end

-- an item's data came (or failed): its waiting gains shown (or dropped)
local function Arrived(id, success)
	id = Num(id)
	if not id or (waitPlain[id] == nil and waitBought[id] == nil) then
		return
	end
	local ready = ItemName(id) and ItemQuality(id)
	if not ready and success ~= false then
		return   -- (still coming)
	end
	local plain, bought = waitPlain[id], waitBought[id]
	waitPlain[id], waitBought[id] = nil, nil
	S.nWait = S.nWait - 1
	if S.nWait <= 0 then
		StopWaiting()
	end
	if ready then
		if plain then
			Gained(id, plain, false)
		end
		if bought then
			Gained(id, bought, true)
		end
		ShowGains()
	end
end

Gained = function(id, n, bought)
	local db = M.db
	if not db then
		return
	end
	if bought then
		if db.bought == false then
			return
		end
	elseif db.items == false then
		return
	end
	local label, quality = ItemName(id), ItemQuality(id)
	if not (label and quality) then
		Wait(id, n, bought)
		return
	end
	if quality == POOR and db.junk == false then
		return
	end
	-- (shown with the pass's other gains: ShowGains)
	local i = nGains + 1
	nGains = i
	gainId[i], gainN[i], gainBought[i], gainQuality[i], gainLabel[i] = id, n, bought and true or false, quality, label
end

-- the item held on the cursor (a stack split or picked up), or nil
local function CursorItem()
	local get = _G.GetCursorInfo
	if type(get) ~= "function" then
		return nil
	end
	local ok, what, id = pcall(get)
	if not ok or Secret(what) or what ~= "item" then
		return nil
	end
	return Num(id)
end

-- an item looked at: its count now against the last one. held: the item on
-- the cursor, whose count is not lowered while it is held (put down again it
-- is no gain)
local function Settle(id, bought, held)
	local n = Count(id)
	if not n then
		Retry(id)
		return
	end
	local old = known[id]
	if unread[id] then
		unread[id] = nil
		known[id] = n
		return
	end
	if id == held and old and n < old then
		return
	end
	if quiet[id] or (old == nil and S.bank) then
		known[id] = n
		return
	end
	if old == nil then
		-- first seen: what the bags and the gear hold came in; what lies in
		-- the bank was there before
		local c = Carried(id)
		if not c then
			Retry(id)
			return
		end
		old = n - c
		if old < 0 then
			old = 0
		end
	end
	known[id] = n
	if n > old then
		Gained(id, n - old, bought)
	end
end

-- bought: at a merchant, the money down in the same moment
local function Bought()
	local at = S.spentAt
	return S.merchant and at ~= nil and GetTime() - at <= BUY_WINDOW
end

local function ItemsPass()
	S.itemsQueued = false
	if not S.itemsOn then
		return
	end
	Worn(false)
	S.slotRetry = false
	for i = 1, #BAGS do
		local bag = BAGS[i]
		if dirty[bag] then
			dirty[bag] = nil
			ScanBag(bag)   -- (a secret slot: dirty again, slotRetry)
		end
	end
	if S.nRetry > 0 then
		for id in pairs(retry) do
			retry[id] = nil
			candidates[id] = true
		end
		S.nRetry = 0
	end
	local bought, held = Bought(), CursorItem()
	for id in pairs(candidates) do
		candidates[id] = nil
		Settle(id, bought, held)
	end
	for id in pairs(quiet) do
		quiet[id] = nil
	end
	ShowGains()
	RetryLater()
end

-- every count taken again, silently (the bank opened or closed: the client
-- may count the bank's items only while it is open)
local function Rebase()
	for id in pairs(known) do
		local n = Count(id)
		if n then
			known[id] = n
		end
	end
end

--------------------------------------------------------------------------------
-- The passes: the next frame after the game's changes (a whole loot window,
-- a purchase's money and its item, come in together), one per burst
--------------------------------------------------------------------------------

local function Later(key, fn)
	local Kit = MelloUI.Kit
	if Kit and Kit.NextFrame then
		Kit:NextFrame(key, fn)
	else
		fn()
	end
end

local function QueueItems()
	if not S.itemsQueued then
		S.itemsQueued = true
		Later("Gains items", ItemsPass)
	end
end

local function SkillsPass()
	S.skillsQueued = false
	if not S.skillsOn then
		return
	end
	if not ReadSkills(true) then
		S.skillRetry = true
		RetryLater()
	end
end

local function QueueSkills()
	if not S.skillsQueued then
		S.skillsQueued = true
		Later("Gains skills", SkillsPass)
	end
end

-- a pass waiting runs now (before the bank's or a merchant's state changes)
local function Flush()
	if S.itemsQueued then
		ItemsPass()
	end
end

local ITEM_EVENTS = { "BAG_UPDATE", "BAG_UPDATE_DELAYED", "MERCHANT_SHOW", "MERCHANT_CLOSED", "BANKFRAME_OPENED",
	"BANKFRAME_CLOSED" }

-- a currency gained: its own icon and name (the game's), a line per currency
local function CurrencyGained(id, change)
	local info = Ask(Api("C_CurrencyInfo", "GetCurrencyInfo"), id)
	if type(info) ~= "table" then
		return
	end
	local name = Text(info.name)
	if not name or name == "" then
		return
	end
	local icon = Num(info.iconFileID)
	local label = icon and ("|T" .. icon .. ":0|t " .. name) or name
	Put("currency", id, change, label)
end

local function OnEvent(_, event, a1, a2, a3)
	if event == "BAG_UPDATE" then
		local bag = Num(a1)
		if bag and carried[bag] then
			dirty[bag] = true
			QueueItems()
		end
	elseif event == "BAG_UPDATE_DELAYED" then
		QueueItems()
	elseif event == "SKILL_LINES_CHANGED" then
		QueueSkills()
	elseif event == "PLAYER_MONEY" then
		-- (a secret read is skipped: the next plain one is compared with the
		-- last plain sum)
		local money = Money()
		if money then
			local last = S.money
			if last and money > last and S.moneyOn then
				Put("money", "money", money - last)
			elseif S.merchant and last and money < last then
				S.spentAt = GetTime()
			end
			S.money = money
		end
	elseif event == "CURRENCY_DISPLAY_UPDATE" then
		local id, change = Num(a1), Num(a3)
		if S.currenciesOn and id and change and change > 0 then
			CurrencyGained(id, change)
		end
	elseif event == "MERCHANT_SHOW" then
		Flush()
		S.merchant, S.spentAt = true, nil
		S.money = Money() or S.money
		events:RegisterEvent("PLAYER_MONEY")
	elseif event == "MERCHANT_CLOSED" then
		Flush()
		S.merchant, S.spentAt = false, nil
		if not S.moneyOn then
			events:UnregisterEvent("PLAYER_MONEY")
		end
	elseif event == "BANKFRAME_OPENED" then
		Flush()
		S.bank = true
		Rebase()
	elseif event == "BANKFRAME_CLOSED" then
		Flush()
		S.bank = false
		Rebase()
	elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
		-- (the success flag as it came: false drops the waiting gain)
		local ok = a2
		if Secret(ok) then
			ok = nil
		end
		Arrived(a1, ok)
	elseif event == "PLAYER_REGEN_ENABLED" then
		events:UnregisterEvent("PLAYER_REGEN_ENABLED")
		if S.skillRetry then
			S.skillRetry = false
			QueueSkills()
		end
		if S.nRetry > 0 or S.slotRetry then
			QueueItems()
		end
	end
end

-- whether the character stands at an NPC of one of these kinds now (Enum.
-- PlayerInteractionType names): the game asked, a secret or failed answer
-- is no
local function Interacting(...)
	local f = Api("C_PlayerInteractionManager", "IsInteractingWithNpcOfType")
	local E = type(_G.Enum) == "table" and _G.Enum.PlayerInteractionType
	if not (f and type(E) == "table") then
		return false
	end
	for i = 1, select("#", ...) do
		local t = Num(E[(select(i, ...))])
		if t then
			local v = Ask(f, t)
			if not Secret(v) and v == true then
				return true
			end
		end
	end
	return false
end

-- the kinds switched on read and heard; the ones switched off let go
local function Sync()
	if not (S.started and M.db) then
		return
	end
	local db = M.db
	local wantSkills = db.skills ~= false
	local wantItems = db.items ~= false or db.bought ~= false
	if wantSkills and not S.skillsOn then
		S.skillsOn = true
		for _, t in pairs({ skillRank, skillCap, skillName, skillSeen }) do
			for k in pairs(t) do
				t[k] = nil
			end
		end
		S.skillRetry = false
		if not ReadSkills(false) then
			S.skillRetry = true
			RetryLater()
		end
		events:RegisterEvent("SKILL_LINES_CHANGED")
	elseif not wantSkills and S.skillsOn then
		S.skillsOn, S.skillRetry = false, false
		events:UnregisterEvent("SKILL_LINES_CHANGED")
	end
	if wantItems and not S.itemsOn then
		S.itemsOn = true
		-- (a profile load or a switch at the bank or a merchant: the game
		-- asked, not assumed closed)
		S.bank = Interacting("Banker", "CharacterBanker", "AccountBanker")
		S.merchant, S.spentAt = Interacting("Merchant"), nil
		S.money = Money() or S.money
		Baseline()
		for i = 1, #ITEM_EVENTS do
			events:RegisterEvent(ITEM_EVENTS[i])
		end
		if S.merchant then
			events:RegisterEvent("PLAYER_MONEY")
		end
	elseif not wantItems and S.itemsOn then
		S.itemsOn = false
		S.nRetry, S.slotRetry = 0, false
		for i = 1, #ITEM_EVENTS do
			events:UnregisterEvent(ITEM_EVENTS[i])
		end
		if not S.moneyOn then
			events:UnregisterEvent("PLAYER_MONEY")
		end
		StopWaiting()
	end
	-- money: PLAYER_MONEY while Money is on (a merchant's bought check too)
	local wantMoney = db.money ~= false
	if wantMoney and not S.moneyOn then
		S.moneyOn = true
		S.money = Money()
		events:RegisterEvent("PLAYER_MONEY")
	elseif not wantMoney and S.moneyOn then
		S.moneyOn = false
		if not S.merchant then
			events:UnregisterEvent("PLAYER_MONEY")
		end
	end
	local wantCurrencies = db.currencies ~= false
	if wantCurrencies and not S.currenciesOn then
		S.currenciesOn = true
		events:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
	elseif not wantCurrencies and S.currenciesOn then
		S.currenciesOn = false
		events:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
	end
	if not (S.skillRetry or S.nRetry > 0 or S.slotRetry) then
		events:UnregisterEvent("PLAYER_REGEN_ENABLED")
	end
end

-- after the login's frames: the one event frame, the snapshot, the events
local function Start()
	if S.started or not M.isEnabled then
		return
	end
	S.started = true
	if not events then
		events = CreateFrame("Frame")
		Perf.SetScript(events, "OnEvent", OnEvent)
	end
	Sync()
end

local function Stop()
	S.started, S.skillsOn, S.itemsOn, S.moneyOn, S.currenciesOn = false, false, false, false, false
	S.merchant, S.bank, S.spentAt, S.skillRetry, S.nRetry, S.slotRetry = false, false, nil, false, 0, false
	if events then
		events:UnregisterAllEvents()
	end
	StopWaiting()
	S.preview = false
	feed:Clear()
end

--------------------------------------------------------------------------------
-- The bus: Edit Layout shown or not, the notice's outline, a profile load.
-- Taken while the module is on.
--------------------------------------------------------------------------------

local function OnSetting(module, key)
	if module == "Tweaks" and key == "noticeOutline" then
		RestyleAll()
	end
end

local function OnEditLayout()
	Preview()
end

local function OnRestart()
	if feed.ui and M.isEnabled then
		RestyleAll()
		feed:Place()
	end
	Preview()
end

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	MelloUI:On("setting", OnSetting, OWNER)
	MelloUI:On("editlayout", OnEditLayout, OWNER)
	MelloUI:On("restart", OnRestart, OWNER)
	MelloUI:On("palette", Repaint, OWNER)
	MelloUI:On("preview", OnPreview, OWNER)
	MelloUI:AfterLogin(Start)
end

function M:OnDisable()
	MelloUI:Off(OWNER)
	Stop()
end

function M:OnSettingChanged(key, _, db)
	self.db = db
	if key == "skills" or key == "items" or key == "bought" or key == "money" or key == "currencies" then
		Sync()
	elseif key == "values" then
		Tails()
	elseif key == "qualityNames" then
		feed:Each(NameColour)
	end
end
