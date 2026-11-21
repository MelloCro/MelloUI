--------------------------------------------------------------------------------
-- MelloUI - Demon Grimoires (a German player, a warlock: "can we save which grimoires for my demons we have already
-- bought, or which are already known, without my having to summon each of them in front of the vendor?")
--
-- A warlock's demon learns its abilities from grimoires, and the game tells whether one is known only while that
-- demon is out. This module notes what each demon knows and says it at the vendor:
--   Noting     whenever a demon of yours is out, its spell book is read (its family, "Imp", "Voidwalker", ..., and each
--              ability with its rank) and kept for this character: summoned once, a demon is known from then on, and
--              noted again as it learns something new.
--   The vendor each grimoire on a merchant's page gets a word at its bottom right: "Known" in grey where the demon
--              knows that rank or a higher one, "New" in green where it knows a lower one or none of it yet (which
--              demon: the tooltip). The pet's commands (Attack, Follow, Passive, ...) are noted with its abilities:
--              this client gives both the same entry type, and a grimoire never names a command.
--   Tooltips   a grimoire's tooltip anywhere (the vendor, your bags) gets the same line.
-- Which grimoire teaches what is read from its own tooltip ("Teaches your Imp Firebolt (Rank 2)"): the noted ability's
-- name in it and the first number after the name its rank -- so it reads the client's language and no list of
-- grimoires is kept. A demon not summoned since this module came is not known yet: "Summon it once" is the line then.
-- Only for warlocks: on any other class it registers nothing.
-- What it keeps, account-wide (`keep`: never in a profile or a share string), only on this computer:
--   demons  [the character's GUID] = { [family] = { [ability] = rank (0: no rank), ... } }
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("DemonGrimoires")
local Safe = MelloUI.Safe
local Num, Text = Safe.Number, Safe.Text

-- (every text a window draws: Tools/languages/strings.py reads this table)
local TEXT = {
	known = "Known",   -- (the vendor's word: short, at the item's bottom right, clear of the price; the demon in the tooltip)
	new = "New",
	tipKnown = "Your %s knows this (rank %s).",
	tipKnownPlain = "Your %s knows this.",
	tipNew = "Your %s does not know this yet.",
	tipLower = "Your %s knows rank %s: this one is new.",
	tipUnseen = "Summon your %s once and MelloUI notes what it knows.",
}

local M = MelloUI:RegisterModule("DemonGrimoires", {
	title = "Demon Grimoires",
	desc = "Notes what each of your demons knows whenever it is out, and marks the grimoires at the vendor and in tooltips as known or new: no need to summon each demon in front of the vendor. Summon each demon once first, so MelloUI can note what it knows.",
	icon = "Interface\\Icons\\INV_Misc_Book_06",
	flavour = "The Imp already knows that one. It told you. Twice.",
	enabledByDefault = false,
	new = "2.1.66",
	slash = "grimoires",
	keep = { "demons" },
	defaults = { merchant = true, tooltip = true },
	options = {
		{ type = "toggle", key = "merchant", name = "Mark Grimoires At The Vendor", new = "2.1.66",
		  desc = "Each grimoire on a merchant's page shows whether your demon knows it: Known in grey, New in green." },
		{ type = "toggle", key = "tooltip", name = "Line In Grimoire Tooltips", new = "2.1.66",
		  desc = "A grimoire's tooltip says whether your demon knows it, or that it still needs summoning once." },
	},
})
MelloUI.DemonGrimoires = M

local G = {
	SETTLE = 0.5,       -- seconds: the spell book read once its events have stopped coming
	RECIPE = 9,         -- the item class of grimoires (Recipe; their subclass Book): no other item is read
}

-- (2.1.66, the follow-up to pull request #61) the words' colours: Known in the palette's muted text, New in the
-- meaning colour of one to learn (MelloUI.Meaning.canLearn, cannotUse's counterpart), "summon it once" in the
-- palette's gold -- read when drawn (the vendor's words at each refresh, a tooltip line at each show)
local function Colour(state)
	local c
	if state == "known" then
		c = MelloUI.Palette.mutedText
	elseif state == "unseen" then
		c = MelloUI.Palette.selectedTrim
	else
		c = MelloUI.Meaning.canLearn
	end
	return c[1], c[2], c[3]
end

local function Tr(text)
	local W = MelloUI.Widgets
	return W and W.Tr and W.Tr(text) or text
end

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c = pcall(fn, ...)
	if ok then
		return a, b, c
	end
	return nil
end

local function IsWarlock()
	local _, class = Call(UnitClass, "player")
	return Text(class) == "WARLOCK"
end

-- this character's record: [family] = { [ability] = rank }
local function Mine()
	local db = M.db
	local guid = Text(Call(UnitGUID, "player"))
	if type(db) ~= "table" or not guid then
		return nil
	end
	if type(db.demons) ~= "table" then
		db.demons = {}
	end
	if type(db.demons[guid]) ~= "table" then
		db.demons[guid] = {}
	end
	return db.demons[guid]
end

-- a rank's number from a spell's sub text ("Rank 3", "Rang 3"); 0 where it has none
local function RankOf(sub)
	sub = Text(sub)
	return sub and tonumber(sub:match("%d+")) or 0
end

--------------------------------------------------------------------------------
-- Noting: the demon's spell book
--------------------------------------------------------------------------------

-- the pet's spell book, each entry's name and sub text (both clients' ways: C_SpellBook, else the old globals)
local function PetSpells()
	local out = {}
	local SB, E = rawget(_G, "C_SpellBook"), rawget(_G, "Enum")
	local bank = type(E) == "table" and type(E.SpellBookSpellBank) == "table" and E.SpellBookSpellBank.Pet
	if type(SB) == "table" and bank ~= nil and type(SB.HasPetSpells) == "function" then
		local n = Num(Call(SB.HasPetSpells)) or 0
		-- (every entry kept: on WoW Forever the demon's abilities are PetAction entries as much as its commands -- a
		-- filter on that type left the player's Succubus with nothing, every grimoire New. The commands are noted
		-- too; a grimoire never names them, so they change nothing)
		for i = 1, n do
			local name, sub = Call(SB.GetSpellBookItemName, i, bank)
			out[#out + 1] = { name = Text(name), sub = sub }
		end
		return out, n
	end
	local has, getName = rawget(_G, "HasPetSpells"), rawget(_G, "GetSpellBookItemName") or rawget(_G, "GetSpellName")
	local getInfo, book = rawget(_G, "GetSpellBookItemInfo"), rawget(_G, "BOOKTYPE_PET") or "pet"
	local n = Num(Call(has)) or 0
	for i = 1, n do
		if Text(Call(getInfo, i, book)) ~= "PETACTION" then
			local name, sub = Call(getName, i, book)
			out[#out + 1] = { name = Text(name), sub = sub }
		end
	end
	return out, n
end

-- what the demon out now knows, noted (its highest rank of each ability)
function G.Note()
	if not (M.isEnabled and IsWarlock()) then
		return
	end
	local family = Text(Call(rawget(_G, "UnitCreatureFamily"), "pet"))
	local mine = Mine()
	if not (family and family ~= "" and mine) then
		return
	end
	local known = {}
	local spells, read = PetSpells()
	for _, s in ipairs(spells) do
		if s.name and s.name ~= "" then
			local rank = RankOf(s.sub)
			if rank >= (known[s.name] or -1) then
				known[s.name] = rank
			end
		end
	end
	-- (a demon that knows only its commands -- a Felhunter just learned, the player: "it can do nothing yet" -- is
	-- noted with none, so its grimoires read New; an empty book, not loaded yet, overwrites nothing)
	if read > 0 then
		mine[family] = known
	end
	G.Refresh()
end

local pending
local function NoteSoon()
	if pending then
		return
	end
	pending = true
	Perf.C_Timer.After(G.SETTLE, function()
		pending = nil
		G.Note()
	end)
end

--------------------------------------------------------------------------------
-- Reading a grimoire: which demon, which ability, which rank
--------------------------------------------------------------------------------

-- an item that may be a grimoire: of the Recipe class (an item whose class cannot be read yet is let through: its
-- text still has to name a demon of yours)
function G.Book(itemID)
	itemID = Num(itemID)
	if not itemID then
		return true
	end
	local CI = rawget(_G, "C_Item")
	local instant = type(CI) == "table" and CI.GetItemInfoInstant or rawget(_G, "GetItemInfoInstant")
	local ok, _, _, _, _, _, classID = pcall(instant, itemID)
	classID = ok and Num(classID) or nil
	return classID == nil or classID == G.RECIPE
end

-- the demon families a grimoire may name, in the client's language: the ones noted on any of your characters (a
-- demon never summoned with this module on is not known by name, and its grimoires get no word)
local function Families()
	local out = {}
	local db = M.db
	for _, char in pairs(type(db) == "table" and type(db.demons) == "table" and db.demons or {}) do
		for family in pairs(type(char) == "table" and char or {}) do
			out[family] = true
		end
	end
	return out
end

-- the text of an item's tooltip lines, joined (tooltip data from the game's own tooltip info)
local function LinesText(data)
	local parts = {}
	for _, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
		local t = type(line) == "table" and Text(line.leftText) or nil
		if t then
			parts[#parts + 1] = t
		end
	end
	return table.concat(parts, "\n")
end

-- what a grimoire's text teaches, against this character's noted demons: family, state ("known", "lower", "new",
-- "unseen"), the rank it teaches, the rank known. nil for an item that teaches no demon of yours
function G.Judge(text)
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local mine = Mine() or {}
	-- an ability a noted demon knows, named in the text: the longest name wins ("Fire Shield" over "Fire")
	local best
	for family, spells in pairs(mine) do
		for name, rank in pairs(type(spells) == "table" and spells or {}) do
			local at = text:find(name, 1, true)
			if at and (not best or #name > #best.name) then
				best = { family = family, name = name, known = rank, at = at }
			end
		end
	end
	if best then
		-- the rank in the brackets right after the name ("'Lash of Pain' (Rank 3)"): only quotes and spaces between.
		-- (Any first number after it read "Requires Level 26" as the rank of Seduction, which has none -- the player's
		-- screenshot: New beside the game's Already Known)
		local rest = text:sub(best.at + #best.name)
		local teaches = tonumber(rest:match("^[^%a%d\n]-%(%D-(%d+)%)")) or 0
		local state = (best.known >= teaches) and "known" or "lower"
		return best.family, state, teaches, best.known
	end
	-- no noted ability in it: a demon named in it that is noted (then the ability is new to it), or one never seen
	for family in pairs(Families()) do
		if text:find(family, 1, true) then
			return family, mine[family] and "new" or "unseen"
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- The vendor: a word under each grimoire's name
--------------------------------------------------------------------------------

local words = setmetatable({}, { __mode = "k" })   -- [the merchant's item frame] = its font string

local function Word(item)
	local fs = words[item]
	if fs then
		return fs
	end
	-- (first under the name: it ran over the price, the player's screenshot of 2026-11-21; now at the bottom right)
	fs = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -4, 3)
	fs:SetJustifyH("RIGHT")
	words[item] = fs
	return fs
end

local function MerchantText(index)
	local TI = rawget(_G, "C_TooltipInfo")
	local data = type(TI) == "table" and Call(TI.GetMerchantItem, index) or nil
	local text = LinesText(data)
	if text == "" then
		text = Text(Call(rawget(_G, "GetMerchantItemInfo"), index)) or ""
	end
	return text
end

function G.Refresh()
	local frame = rawget(_G, "MerchantFrame")
	if not (frame and frame.IsShown and frame:IsShown()) then
		return
	end
	local on = M.isEnabled and IsWarlock() and type(M.db) == "table" and M.db.merchant ~= false
	local per = Num(rawget(_G, "MERCHANT_ITEMS_PER_PAGE")) or 10
	local page = Num(frame.page) or 1
	local buying = (Num(frame.selectedTab) or 1) == 1
	for i = 1, per do
		local item = rawget(_G, "MerchantItem" .. i)
		if item then
			local family, state
			local index = (page - 1) * per + i
			if on and buying and G.Book(Call(rawget(_G, "GetMerchantItemID"), index)) then
				family, state = G.Judge(MerchantText(index))
			end
			local fs = (family or words[item]) and Word(item) or nil
			if fs then
				if family and state ~= "unseen" then
					local known = state == "known"
					fs:SetText(MelloUI.Lang.T(known and TEXT.known or TEXT.new))
					fs:SetTextColor(Colour(known and "known" or "new"))
					fs:Show()
				else
					fs:Hide()
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Tooltips
--------------------------------------------------------------------------------

local function OnItemTooltip(tooltip, data)
	if not (M.isEnabled and type(M.db) == "table" and M.db.tooltip ~= false and IsWarlock()) then
		return
	end
	if not (tooltip and tooltip.AddLine) or (tooltip.IsForbidden and tooltip:IsForbidden()) then
		return
	end
	if not G.Book(type(data) == "table" and data.id) then
		return
	end
	local family, state, _, known = G.Judge(LinesText(data))
	if not family then
		return
	end
	local F = MelloUI.Lang.F
	if state == "known" then
		if known and known > 0 then
			tooltip:AddLine(F(TEXT.tipKnown, family, known), Colour("known"))
		else
			tooltip:AddLine(F(TEXT.tipKnownPlain, family), Colour("known"))
		end
	elseif state == "lower" and known and known > 0 then
		tooltip:AddLine(F(TEXT.tipLower, family, known), Colour("new"))
	elseif state == "unseen" then
		tooltip:AddLine(F(TEXT.tipUnseen, family), Colour("unseen"))
	else
		tooltip:AddLine(F(TEXT.tipNew, family), Colour("new"))
	end
	tooltip:Show()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
local EVENTS = { "UNIT_PET", "PET_BAR_UPDATE", "SPELLS_CHANGED", "MERCHANT_SHOW", "MERCHANT_UPDATE" }

Perf.SetScript(events, "OnEvent", function(_, event, unit)
	if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
		G.Refresh()
	elseif event ~= "UNIT_PET" or unit == "player" then
		NoteSoon()
	end
end)

function M:OnEnable(db)
	self.db = db
	if not IsWarlock() then
		return
	end
	for _, e in ipairs(EVENTS) do
		pcall(events.RegisterEvent, events, e)
	end
	if not G.hooked then
		G.hooked = true
		if type(rawget(_G, "MerchantFrame_UpdateMerchantInfo")) == "function" then
			Perf.hooksecurefunc("MerchantFrame_UpdateMerchantInfo", G.Refresh)
		end
		local P, E = rawget(_G, "TooltipDataProcessor"), rawget(_G, "Enum")
		local kinds = type(E) == "table" and E.TooltipDataType
		if type(P) == "table" and type(P.AddTooltipPostCall) == "function" and type(kinds) == "table" and kinds.Item then
			P.AddTooltipPostCall(kinds.Item, OnItemTooltip)
		end
	end
	NoteSoon()
end

function M:OnDisable()
	events:UnregisterAllEvents()
	G.Refresh()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	G.Refresh()
end

-- /mello grimoires list: what is noted of this character's demons
M.SlashWords = {
	list = function()
		local mine = Mine() or {}
		local any = false
		for family, spells in pairs(mine) do
			local parts = {}
			for name, rank in pairs(type(spells) == "table" and spells or {}) do
				parts[#parts + 1] = rank > 0 and (name .. " " .. rank) or name
			end
			table.sort(parts)
			MelloUI:Print(family .. ": " .. table.concat(parts, ", "))
			any = true
		end
		if not any then
			MelloUI:Print(Tr("Demon Grimoires: nothing noted yet. Summon each demon once."))
		end
	end,
}

-- for the test harness
M.TEXT, M.G = TEXT, G
