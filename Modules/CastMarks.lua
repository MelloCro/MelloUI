--------------------------------------------------------------------------------
-- MelloUI - Cast Marks (a German player: "it does not have the steps the cast bar addon has -- the ticks of the
-- spell, for example -- and I don't see the latency either")
--
-- Two marks on your cast bar, the game's (PlayerCastingBarFrame, in MelloUI's look) and the Personal Display's:
--   Latency        the end of a cast shaded by your latency (the world's, GetNetStats): once the fill reaches it, the
--                  next spell can be pressed. On a channel the shade is at the bar's left end, where it runs out.
--                  Latency Text adds "25ms" just above that end.
--   Channel Ticks  a thin mark where each tick of a channel lands (Drain Life, Hellfire, Arcane Missiles, Blizzard,
--                  Mind Flay, ...: CHANNELS, the seconds between ticks), laid again when a hit pushes the channel back.
-- Read from the cast's own times (UnitCastingInfo, UnitChannelInfo); a cast whose times are secret gets no marks.
-- Nothing of the game's is changed: the marks are textures of MelloUI's on the bar, over its fill and under its text.
-- On by default: the marks are quiet. Their switches are on Bars > Cast Bar > Bar.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("CastMarks")
local Safe = MelloUI.Safe
local Secret, Num, Text = Safe.IsSecret, Safe.Number, Safe.Text

local M = MelloUI:RegisterModule("CastMarks", {
	title = "Cast Marks",
	desc = "Your latency at the end of each cast and a mark for each tick of a channel, on your cast bar and the Personal Display's.",
	icon = "Interface\\Icons\\Spell_Shadow_LifeDrain02",
	flavour = "Press the next spell the moment you can.",
	enabledByDefault = true,
	slash = "castmarks",
	defaults = { latency = true, latencyText = false, ticks = true },
	options = {
		{ type = "toggle", key = "latency", name = "Latency",
		  desc = "The end of each cast shaded by your latency: once the fill reaches it, you can press the next spell." },
		{ type = "toggle", key = "latencyText", name = "Latency Text",
		  desc = "Your latency in milliseconds just above the shaded end." },
		{ type = "toggle", key = "ticks", name = "Channel Ticks",
		  desc = "A thin mark where each tick of a channelled spell lands, such as Drain Life, Hellfire or Arcane Missiles." },
	},
})
MelloUI.CastMarks = M

local C = {
	SHADE = { 0.85, 0.15, 0.15, 0.45 },   -- the latency's shade
	TICK = { 1, 1, 1, 0.75 },             -- a tick's mark
	TICK_W = 2,                           -- pixels
	MAX_SHARE = 0.5,                      -- the most of the bar the shade takes (a very short cast on a slow line)
	-- the channels that tick: the spell (its base id, read in the client's language) and the seconds between ticks
	CHANNELS = {
		[689] = 1,      -- Drain Life
		[5138] = 1,     -- Drain Mana
		[1120] = 3,     -- Drain Soul
		[755] = 1,      -- Health Funnel
		[1949] = 1,     -- Hellfire
		[5740] = 2,     -- Rain of Fire
		[5143] = 1,     -- Arcane Missiles
		[10] = 1,       -- Blizzard
		[12051] = 2,    -- Evocation
		[15407] = 1,    -- Mind Flay
		[740] = 2,      -- Tranquility
		[16914] = 1,    -- Hurricane
		[1510] = 1,     -- Volley
	},
	byName = nil,   -- [the spell's name] = seconds between ticks (made at the first channel)
}

local function Db()
	return type(M.db) == "table" and M.db or {}
end

local function SpellName(id)
	local CS = rawget(_G, "C_Spell")
	if type(CS) == "table" and type(CS.GetSpellName) == "function" then
		local ok, name = pcall(CS.GetSpellName, id)
		if ok and type(name) == "string" and not Secret(name) then
			return name
		end
	end
	local info = rawget(_G, "GetSpellInfo")
	if type(info) == "function" then
		local ok, name = pcall(info, id)
		if ok and type(name) == "string" and not Secret(name) then
			return name
		end
	end
	return nil
end

-- the seconds between a channel's ticks, by its name; nil for a channel that does not tick
function C.Interval(name)
	if type(name) ~= "string" or Secret(name) then
		return nil
	end
	if not C.byName then
		C.byName = {}
		for id, every in pairs(C.CHANNELS) do
			local n = SpellName(id)
			if n then
				C.byName[n] = every
			end
		end
	end
	return C.byName[name]
end

-- your latency in milliseconds (the world's, the home's where the world's is not given)
function C.Latency()
	local ok, _, _, home, world = pcall(GetNetStats)
	if not ok then
		return nil
	end
	local ms = Num(world)
	if not ms or ms <= 0 then
		ms = Num(home)
	end
	return ms and ms > 0 and ms or nil
end

-- a bar's marks: textures on the bar itself, over its fill (the fill's layer, the top sublevel) and under its text
-- (made once a bar)
local holders = setmetatable({}, { __mode = "k" })
local function Holder(bar)
	local h = holders[bar]
	if h then
		return h
	end
	h = { bar = bar, ticks = {} }
	h.shade = bar:CreateTexture(nil, "ARTWORK", nil, 7)
	h.shade:SetColorTexture(unpack(C.SHADE))
	h.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	holders[bar] = h
	return h
end

-- the marks of one cast on `bar`: `seconds` the cast's length, `channel` true for a channel (its bar runs down, its
-- end on the left), `name` the spell's. Nothing (the marks hidden) without a length
function M.Lay(bar, seconds, channel, name)
	if type(bar) ~= "table" or type(bar.GetWidth) ~= "function" then
		return
	end
	local h = Holder(bar)
	local db = Db()
	local w = Num(bar:GetWidth()) or 0
	local on = M.isEnabled and type(seconds) == "number" and not Secret(seconds) and seconds > 0 and w > 0
	-- the latency's shade at the cast's end
	local ms = on and db.latency ~= false and C.Latency() or nil
	h.shade:ClearAllPoints()
	h.label:ClearAllPoints()
	if ms then
		local share = math.min(ms / 1000 / seconds, C.MAX_SHARE)
		local side = channel and "LEFT" or "RIGHT"
		h.shade:SetPoint("TOP" .. side, bar, "TOP" .. side)
		h.shade:SetPoint("BOTTOM" .. side, bar, "BOTTOM" .. side)
		h.shade:SetWidth(math.max(1, w * share))
		h.label:SetPoint("BOTTOM" .. side, bar, "TOP" .. side, 0, 2)
		h.label:SetText(math.floor(ms + 0.5) .. "ms")
	end
	h.shade:SetShown(ms ~= nil)
	h.label:SetShown(ms ~= nil and db.latencyText == true)
	-- the ticks of a channel: the fill runs down from the right, the k-th tick lands at 1 - k * every / seconds
	local every = on and channel and db.ticks ~= false and C.Interval(name) or nil
	local n = every and math.floor(seconds / every + 0.5) or 0
	for k = 1, math.max(n - 1, #h.ticks) do
		local t = h.ticks[k]
		local at = k < n and (1 - k * every / seconds) or nil
		if at and at > 0 and not t then
			t = bar:CreateTexture(nil, "ARTWORK", nil, 7)
			t:SetColorTexture(unpack(C.TICK))
			t:SetWidth(C.TICK_W)
			h.ticks[k] = t
		end
		if t then
			if at and at > 0 then
				t:ClearAllPoints()
				t:SetPoint("TOP", bar, "TOPLEFT", w * at, 0)
				t:SetPoint("BOTTOM", bar, "BOTTOMLEFT", w * at, 0)
				t:Show()
			else
				t:Hide()
			end
		end
	end
end

function M.Clear(bar)
	local h = bar and holders[bar]
	if h then
		h.shade:Hide()
		h.label:Hide()
		for _, t in ipairs(h.ticks) do
			t:Hide()
		end
	end
end

--------------------------------------------------------------------------------
-- The game's cast bar (the Personal Display lays its own: M.Lay from its CastShow)
--------------------------------------------------------------------------------

-- your cast or channel as it is now: its length in seconds and its name (nil while its times are secret)
function M.Read(channel)
	local info = channel and UnitChannelInfo or UnitCastingInfo
	local ok, name, _, _, startMS, endMS = pcall(info, "player")
	if not ok or Secret(startMS) or Secret(endMS) or type(startMS) ~= "number" or type(endMS) ~= "number" then
		return nil
	end
	return math.max(0.05, (endMS - startMS) / 1000), Text(name)
end

local function LayGame(channel)
	local bar = rawget(_G, "PlayerCastingBarFrame")
	if not bar then
		return
	end
	local seconds, name = M.Read(channel)
	M.Lay(bar, seconds, channel, name)
end

local events = CreateFrame("Frame")
local EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP" }

Perf.SetScript(events, "OnEvent", function(_, event)
	if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
		LayGame(false)
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		LayGame(true)
	else
		M.Clear(rawget(_G, "PlayerCastingBarFrame"))
	end
end)

function M:OnEnable(db)
	self.db = db
	for _, e in ipairs(EVENTS) do
		pcall(events.RegisterUnitEvent, events, e, "player")
	end
end

function M:OnDisable()
	events:UnregisterAllEvents()
	M.Clear(rawget(_G, "PlayerCastingBarFrame"))
end

function M:OnSettingChanged(key, value, db)
	self.db = db
end

-- for the test harness
M.C = C
