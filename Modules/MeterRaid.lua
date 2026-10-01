--------------------------------------------------------------------------------
-- MelloUI - Damage Meter: the number on the raid-style frames (0.17.1)
--
-- The user, 2026-10-01: "how does that look when i change the party
-- unitframes to raid frames?" -- docs/plans/meter-raid-frames.md, the picked
-- sketch docs/plans/next-update-refs/raid_frames_side.jpg ("anchor it
-- alongside the Current HP% on the right middle side of the unitframe, you
-- can remove the shading when used on Raid Frames"). On every raid-style
-- party frame and every raid frame, ONE small number on the frame's right
-- middle, beside the game's health %: a damage dealer's DPS (gold, the
-- sword), a healer's HPS (green, the cross) -- the meter's own parts
-- (Meter.PaintPart). No shade behind it: a dark outline and shadow.
--   In a fight: the live number where MelloUI can tell who the frame is
--   (Meter.SourceFor: you, or a class no one else in the group has),
--   else empty -- never a dash: thirty dashes in a raid look broken.
--   After a fight: that player's number from the last fight (the records,
--   by GUID), until the next one starts.
--   The pointer on such a frame: three lines in its tooltip -- this fight,
--   this run, healing -- out of a fight; in one only where the line takes
--   the game's secret value (tried, never assumed).
--   Never on a pet's, an enemy's or an arena frame: only the units player,
--   partyN, raidN.
-- The role: UnitGroupRolesAssigned's HEALER gives HPS; NONE (an unqueued
-- group) the larger side of their last fight, kept through the next.
--
-- Built from the game's own setup (DefaultCompactUnitFrameSetup, post-hook):
-- one small Frame of ours per compact frame, its child, holding the glyph
-- and the number; its RIGHT on the game's statusText's RIGHT (the game lays
-- that text across the frame at a third of its height: the health %'s
-- line), the glyph left of the number (a secret text has no width to read:
-- the engine lays it). Its size 0.8 x the game's statusText's font, read
-- again at every setup. Nothing of the game's frame is written: no key, no
-- point, no font -- our weak table keeps the holders. Made out of combat
-- (one sweep after a fight for a setup that came in one), never while the
-- switch is off; the Fader's alpha on the frames carries it.
-- Updates at the meter's own cadence (its live read, at most 4 a second,
-- and the fight's end), never an OnUpdate; out of a fight a text is written
-- only when it changed.
--   Meter.Raid.Apply()           the switch (Damage Meter: On Raid-Style Frames)
--   Meter.Raid.Live(dmg, heal)   the live read's sources (Meter.lua LiveRead)
--   Meter.Raid.Fight()           a fight began: every number empty until read
--   Meter.Raid.After()           the last fight's numbers (Meter.LinesAfter)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("MeterRaid")
local Shared = Perf.Shared
local hooksecurefunc = Perf.hooksecurefunc
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text
local W = MelloUI.Widgets
local Meter = ns.Meter
local M = Meter.M

local Raid = { hooked = false, tipHooked = false, pending = false, dmg = nil, heal = nil }
Meter.Raid = Raid

local R = {
	SIZE = 0.8,      -- the number's size: a share of the game's health % font
	GLYPH = 0.9,     -- the glyph: a share of the number's size
	GAP = 2,         -- between the glyph and the number
	FALLBACK = 12,   -- the health %'s size when it cannot be read
	TIP_GLYPH = 12,  -- the tooltip lines' glyphs
}

Raid.TEXT = {
	fight = "This fight",
	run = "This run",
	heal = "Healing",
	perSecond = "%s/s",
}
local TEXT = Raid.TEXT

local holders = setmetatable({}, { __mode = "k" })   -- [compact frame] = its holder
local list = {}                                       -- the holders, made in order

local function On()
	return M.isEnabled and M.db ~= nil and M.db.raid ~= false
end

local function Ask(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(fn, ...)
	if ok then
		return a, b
	end
	return nil
end

-- the player unit a compact frame shows (player, partyN, raidN), else nil:
-- never a pet's (partypetN, raidpetN), an enemy's or an arena frame
local function UnitOf(frame)
	local unit = frame and frame.unit
	if type(unit) ~= "string" or Secret(unit) then
		return nil
	end
	if unit == "player" or unit:match("^party%d$") or unit:match("^raid%d+$") then
		return unit
	end
	return nil
end

-- the number's size: a share of the game's health % font (read, never set)
local function SizeOf(frame)
	local fs = frame.statusText
	local size = nil
	if fs and fs.GetFont then
		local ok, _, s = pcall(fs.GetFont, fs)
		size = ok and Num(s) or nil
	end
	return math.max(6, math.floor((size or R.FALLBACK) * R.SIZE + 0.5))
end

local function Style(h, frame)
	local size = SizeOf(frame)
	if h.size == size then
		return
	end
	h.size = size
	local object = _G.GameFontHighlight
	if type(object) == "table" then
		h.text:SetFontObject(object)
		if MelloUI.StyleFont then
			-- (no shade: an outline, the user's "remove the shading")
			MelloUI:StyleFont(h.text, "fontText", object, size, "", true)
		end
	end
	h.glyph:SetSize(math.floor(size * R.GLYPH + 0.5), math.floor(size * R.GLYPH + 0.5))
end

-- the glyph and colours of a side (HPS: the cross, green; DPS: the sword, gold)
local function Side(h, healer)
	local kind = healer and "heal" or "sword"
	if h.part.kind == kind then
		return
	end
	h.part.kind = kind
	W.Glyph(h.glyph, kind)
	Meter.PaintPart(h.part)
end

-- a number: plain or secret; nil, zero or less: empty (never a dash)
local function Write(h, v)
	if v ~= nil and not Secret(v) and (Num(v) or 0) <= 0 then
		v = nil
	end
	if v == nil then
		if h.shown ~= "" then
			h.shown = ""
			h.text:SetText("")
			h.glyph:Hide()
		end
		return
	end
	local text = Meter.Format(v)
	if Secret(v) or Secret(text) then
		h.shown = nil   -- (a secret: set at the read's cadence, never compared)
		h.text:SetText(text)
		h.glyph:Show()
		return
	end
	if h.shown ~= text then
		h.shown = text
		h.text:SetText(text or "")
		h.glyph:SetShown(text ~= nil)
	end
end

-- HPS for a healer; for NONE the side of their last fight (kept in one)
local function Healer(unit, h, e)
	local role = Ask(_G.UnitGroupRolesAssigned, unit)
	if not Secret(role) then
		if role == "HEALER" then
			return true
		elseif role == "TANK" or role == "DAMAGER" then
			return false
		end
	end
	if e then
		h.lean = (e.h or 0) > (e.d or 0)
	end
	return h.lean == true
end

local function Make(frame)
	local h = CreateFrame("Frame", nil, frame)
	h:SetAllPoints(frame)
	h:EnableMouse(false)
	local bar = frame.healthBar
	local ok, level = pcall(function() return (bar or frame):GetFrameLevel() end)
	if ok and Num(level) then
		h:SetFrameLevel(level + 2)
	end
	h.frame = frame
	h.text = h:CreateFontString(nil, "OVERLAY")
	h.text:SetJustifyH("RIGHT")
	h.text:SetShadowOffset(1, -1)
	h.text:SetPoint("RIGHT", frame.statusText, "RIGHT", 0, 0)
	h.glyph = h:CreateTexture(nil, "OVERLAY")
	h.glyph:SetPoint("RIGHT", h.text, "LEFT", -R.GAP, 0)
	h.glyph:Hide()
	h.part = { kind = nil, glyph = h.glyph, text = h.text }
	h.shown = ""
	Side(h, false)
	holders[frame] = h
	list[#list + 1] = h
	return h
end

-- a frame's number from the last fight's record (out of a fight)
local function Settle(h)
	local unit = UnitOf(h.frame)
	if not (unit and On()) then
		h:Hide()
		return
	end
	h:Show()
	Style(h, h.frame)
	local guid = Text((Ask(_G.UnitGUID, unit)))
	local e = guid and Meter.LastEntry(guid) or nil
	local healer = Healer(unit, h, e)
	Side(h, healer)
	Write(h, e and (healer and e.hps or e.dps) or nil)
end

-- a compact frame set up by the game: its holder (made out of combat) laid
local function Ensure(frame)
	if not (frame and frame.statusText) or not UnitOf(frame) then
		local h = frame and holders[frame]
		if h then
			h:Hide()
		end
		return
	end
	if InCombatLockdown() then
		Raid.pending = true   -- (made after the fight: After's sweep)
		return
	end
	local h = holders[frame] or Make(frame)
	if not Meter.InFight() then
		Settle(h)
	end
end

local OnSetup = Shared("DefaultCompactUnitFrameSetup: the meter's number", function(frame)
	if On() then
		Ensure(frame)
	end
end)

-- the compact frames the game has set up already (switched on, a /reload)
local function Sweep()
	local G = _G
	for i = 1, 5 do
		Ensure(G["CompactPartyFrameMember" .. i])
	end
	for i = 1, 40 do
		Ensure(G["CompactRaidFrame" .. i])
	end
	for g = 1, 8 do
		for i = 1, 5 do
			Ensure(G["CompactRaidGroup" .. g .. "Member" .. i])
		end
	end
end

--------------------------------------------------------------------------------
-- The tooltip: three lines on a raid-style frame
--------------------------------------------------------------------------------

local function TipLine(tip, glyph, label, value, r, g, b)
	local mark = W.GlyphMarkup(glyph, R.TIP_GLYPH, r, g, b)
	return pcall(tip.AddDoubleLine, tip, mark .. " " .. label, value, r, g, b, r, g, b)
end

local function Colour(kind)
	if kind == "heal" then
		local c = MelloUI.Meaning.combatHeal
		return c[1], c[2], c[3]
	end
	local c = MelloUI.Palette[kind == "sword" and "selectedTrim" or "text"]
	return c[1], c[2], c[3]
end

local OnTooltip = Shared("the meter's lines on a raid-style frame's tooltip", function(tip)
	if not (On() and tip and tip.GetOwner) then
		return
	end
	local ok, owner = pcall(tip.GetOwner, tip)
	local h = ok and owner and holders[owner]
	local unit = h and UnitOf(owner)
	if not unit then
		return
	end
	local fight, heal
	if Meter.InFight() then
		-- (in a fight: the live sources, where this one can be told apart)
		local d = Meter.SourceFor(unit, Raid.dmg)
		local hs = Meter.SourceFor(unit, Raid.heal)
		fight, heal = d and d.amountPerSecond, hs and hs.amountPerSecond
	else
		local guid = Text((Ask(_G.UnitGUID, unit)))
		local e = guid and Meter.LastEntry(guid) or nil
		fight, heal = e and e.dps, e and e.hps
	end
	local guid = Text((Ask(_G.UnitGUID, unit)))
	local run = guid and Meter.RunRate(guid, false) or nil
	if fight == nil and heal == nil and run == nil then
		return
	end
	local dash = Meter.TEXT.dash
	local function Value(v)
		local t = v ~= nil and Meter.Format(v) or nil
		return t and TEXT.perSecond:format(t) or dash
	end
	local r, g, b = Colour("sword")
	TipLine(tip, "sword", TEXT.fight, Value(fight), r, g, b)
	r, g, b = Colour("hourglass")
	TipLine(tip, "hourglass", TEXT.run, Value(run), r, g, b)
	r, g, b = Colour("heal")
	TipLine(tip, "heal", TEXT.heal, Value(heal), r, g, b)
	pcall(tip.Show, tip)
end)

--------------------------------------------------------------------------------
-- The meter's calls
--------------------------------------------------------------------------------

function Raid.HolderOf(frame)   -- (read only: the tests)
	return holders[frame]
end

function Raid.Apply()
	if not On() then
		for _, h in ipairs(list) do
			h:Hide()
		end
		return
	end
	if not Raid.hooked and type(_G.DefaultCompactUnitFrameSetup) == "function" then
		Raid.hooked = true
		hooksecurefunc("DefaultCompactUnitFrameSetup", OnSetup)
	end
	if not Raid.tipHooked then
		local P = _G.TooltipDataProcessor
		local kinds = _G.Enum and _G.Enum.TooltipDataType
		if type(P) == "table" and type(P.AddTooltipPostCall) == "function" and type(kinds) == "table" and kinds.Unit then
			Raid.tipHooked = true
			P.AddTooltipPostCall(kinds.Unit, OnTooltip)
		end
	end
	if not InCombatLockdown() then
		Sweep()
	else
		Raid.pending = true
	end
end

function Raid.Live(dmg, heal)
	Raid.dmg, Raid.heal = dmg, heal
	if not On() then
		return
	end
	for _, h in ipairs(list) do
		local unit = UnitOf(h.frame)
		if unit and h:IsShown() then
			local healer = Healer(unit, h, nil)
			Side(h, healer)
			local src = Meter.SourceFor(unit, healer and heal or dmg)
			Write(h, src and src.amountPerSecond)
		end
	end
end

function Raid.Fight()
	Raid.dmg, Raid.heal = nil, nil
	for _, h in ipairs(list) do
		Write(h, nil)
	end
end

function Raid.After()
	if not On() then
		return
	end
	if Raid.pending and not InCombatLockdown() then
		Raid.pending = false
		Sweep()
	end
	for _, h in ipairs(list) do
		Settle(h)
	end
end
