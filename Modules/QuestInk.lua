--------------------------------------------------------------------------------
-- MelloUI - Quest ink
--
-- Quest titles in black ink on parchment, their difficulty in pips (user,
-- 2026-09-23: "to have it all in Black color we first need to find a
-- solution ... to still show the dificulty information to the player", then
-- "D"). The game colours a quest's title by its difficulty; on parchment those
-- colours are unreadable (1.2 to 1.9 : 1). Where a quest view lies on
-- parchment (the quest log, the quest list, the quest tracker with its
-- parchment sheet) its titles are dark ink without an outline, and 1 to 5
-- diamonds beside each title say how hard it is: by their count (readable
-- without colour) and their colour (the game's grey, green, yellow, orange,
-- red, darkened to stand on parchment). A trivial quest's text is faded.
--
--   local QI = MelloUI.QuestInk
--   QI.Tier(level)            1 trivial .. 5 impossible, nil without a level
--   QI.TierForQuest(id, level) the game's own verdict for the quest where the
--                             client has one, else from the level
--   QI.TierOfColour(r, g, b)  the same from the game's difficulty colour
--   QI.Pips(parent, size)     a row of five pips: pips:SetTier(tier)
--   QI.Ink(fs, role)          ink on a font string: "title", "text", "faded"
--   QI.Plain(fs)              back to the font string's own font and colour
--   QI.WatchColour(fs)        remember the colours others (the game) give fs:
--   QI.GameColour(fs)         the last of them (a done objective is grey)
--   QI.onParchment            the quest log's reskin is on (its pages and the
--                             quest list are parchment); QuestLogPanel sets it
--
-- The rule for the whole interface (user, 2026-09-23: "if the Background of
-- the text trought the whole UI is set to Parchment, it should use the Black
-- colored letters, if its Disabled, it should rewert back to its original
-- colors"): every surface that can lie on parchment registers here.
--   QI.InkOf(r, g, b)         the ink for a colour: light text -> ink, the
--                             interface gold -> heading ink, grey -> faded, a
--                             colour that means something (quality, class,
--                             channel, red / green) -> a dark shade of its hue
--   QI.InkCodes(text)         the same for the |c colour codes in a text
--   QI.InkText(fs)            ink on a string by its own colour ("auto"), kept
--                             as the game recolours it; QI.PlainText(fs) back
--   QI.Surface(name, def)     a surface: def.roots() the frames whose strings
--                             lie on it, def.on() whether its background is
--                             parchment now, def.skip(fs) a string on a plate
--                             or bar over it; QI.RefreshSurface(name) after a
--                             change (Kit:SetParchment(area) refreshes the
--                             surface named after its area by itself)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("QuestInk")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
-- one handler for every string it is hooked on, wrapped once (user,
-- 2026-09-24: the shared handlers, low-risk steps only)
local Shared = Perf.Shared or function(_, fn) return fn end

local QI = {}
MelloUI.QuestInk = QI
QI.onParchment = false

local ROOT = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Quests\\"

-- the inks (dark brown on the vellum: 8 : 1 for titles)
QI.INK = {
	title = { 0.165, 0.114, 0.071 },   -- #2A1D12
	text  = { 0.227, 0.165, 0.110 },   -- #3A2A1C, objectives
	faded = { 0.310, 0.255, 0.200 },   -- #4F4133, a trivial or done quest: 5 : 1, still readable
	                                   -- (user, 2026-09-23: the first, #7E6C54 at 2.5 : 1, was hard to read)
}
-- a tier's pip: the game's difficulty colours, deep enough to stand on parchment
QI.TIER_COLOUR = {
	{ 0.46, 0.42, 0.37 },   -- 1 trivial (grey)
	{ 0.23, 0.48, 0.13 },   -- 2 easy (green)
	{ 0.77, 0.57, 0.08 },   -- 3 fair (yellow)
	{ 0.77, 0.35, 0.10 },   -- 4 hard (orange)
	{ 0.65, 0.11, 0.08 },   -- 5 very hard (red)
}
QI.TIER_NAME = { "Trivial", "Easy", "Fair", "Hard", "Very hard" }

-- A colour's ink. Linear luminance TARGET gives about 4.8 : 1 on the vellum
-- (#D5B075), the least a text colour needs there.
local TARGET = 0.055
local function Lin(c)
	return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end
local function Srgb(c)
	return c <= 0.0031308 and c * 12.92 or 1.055 * c ^ (1 / 2.4) - 0.055
end

-- The kit's parchment SHEETS (Kit:ParchmentSheet: the vellum at
-- Kit.parchmentTint, about #AA824A, luminance 0.25) are darker than the
-- vellum pages the inks above were set for (2026-09-24, measured: body ink
-- 3.9 : 1, coloured inks about 3 : 1 on a sheet). `sheet`: the ink for
-- text on such a sheet -- 4.5 : 1 for a colour that means something, the
-- title ink (4.7 : 1) for light text, the text ink for grey.
local SHEET_TARGET = 0.0167

function QI.InkOf(r, g, b, sheet)
	r, g, b = r or 1, g or 1, b or 1
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local sat = mx > 0 and (mx - mn) / mx or 0
	if sat < 0.25 then
		-- neutral: light text is the text ink, grey the faded ink, dark kept
		local c
		if sheet then
			c = (mx >= 0.8 and QI.INK.title) or (mx >= 0.4 and QI.INK.text) or nil
		else
			c = (mx >= 0.8 and QI.INK.text) or (mx >= 0.4 and QI.INK.faded) or nil
		end
		if c then
			return c[1], c[2], c[3]
		end
		return r, g, b
	end
	-- the interface's gold (headings, the normal font's colour): heading ink
	if r >= 0.8 and g >= 0.6 and b <= 0.35 and g / r > 0.65 and g / r <= 0.9 then
		local c = QI.INK.title
		return c[1], c[2], c[3]
	end
	-- a colour that means something: its own hue, dark enough to read
	local R, G, B = Lin(r), Lin(g), Lin(b)
	local L = 0.2126 * R + 0.7152 * G + 0.0722 * B
	local target = sheet and SHEET_TARGET or TARGET
	if L <= target then
		return r, g, b
	end
	local k = target / L
	return Srgb(R * k), Srgb(G * k), Srgb(B * k)
end

-- The |cAARRGGBB codes in a text inked alike (a chat line's names, links,
-- channel colours)
local function Code(r, g, b, a, sheet)
	r, g, b = QI.InkOf(r, g, b, sheet)
	return string.format("|c%s%02x%02x%02x", a or "ff", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- (the two replacers are made once: a tooltip refilled every frame while it
-- is hovered is inked each time -- no functions made per call. `codeSheet`:
-- the call's sheet flag while its replacements run)
local codeSheet = nil

local function HexCode(a, rh, gh, bh)
	return Code(tonumber(rh, 16) / 255, tonumber(gh, 16) / 255, tonumber(bh, 16) / 255, a, codeSheet)
end

-- a named colour (|cnHIGHLIGHT_FONT_COLOR:...|r, this client's newer form;
-- user, 2026-09-23: the PvP tab's numbers stayed white): its colour inked
local function NamedCode(name)
	local sheet = codeSheet
	local c = _G[name]
	if type(c) == "table" and c.GetRGB then
		local ok, r, g, b = pcall(c.GetRGB, c)
		if ok and r then
			return Code(r, g, b, nil, sheet)
		end
	end
	-- an item's quality (|cnIQ4:, the links' form on this client; user,
	-- 2026-09-24: the chat's links stayed bright on the parchment)
	local quality = tonumber(name:match("^IQ(%d+)$"))
	if quality then
		local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		if qc and qc.r then
			return Code(qc.r, qc.g, qc.b, nil, sheet)
		end
		if C_Item and C_Item.GetItemQualityColor then
			local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
			if ok and type(r) == "number" then
				return Code(r, g, b, nil, sheet)
			end
		end
	end
	-- a colour this client names that is not known here: the text ink,
	-- readable rather than bright on the paper
	local ink = QI.INK.text
	return Code(ink[1], ink[2], ink[3], nil, sheet)
end

function QI.InkCodes(text, sheet)
	if type(text) ~= "string" or not text:find("|c", 1, true) then
		return text
	end
	codeSheet = sheet
	text = text:gsub("|c(%x%x)(%x%x)(%x%x)(%x%x)", HexCode)
	text = text:gsub("|cn([%w_]+):", NamedCode)
	codeSheet = nil
	return text
end

-- The game's difficulty colour -> tier: grey, green, yellow, orange, red
-- (QuestDifficultyColors trivial, standard, difficult, verydifficult,
-- impossible; the shades differ between clients, the hues do not)
function QI.TierOfColour(r, g, b)
	if not (r and g and b) then
		return nil
	end
	if math.abs(r - g) < 0.08 and math.abs(g - b) < 0.08 then
		return 1
	end
	if g > r then
		return 2
	end
	if g >= 0.7 then
		return 3
	end
	if g >= 0.35 then
		return 4
	end
	return 5
end

-- The client's relative difficulty for a quest (what the quest log colours
-- by: the old level formula disagreed with it, user 2026-09-23 -- a green
-- quest showed three yellow pips): Enum.RelativeContentDifficulty Trivial,
-- Easy, Fair, Difficult, Impossible -> 1 .. 5
local RELATIVE = {}
if Enum and Enum.RelativeContentDifficulty then
	for name, tier in pairs({ Trivial = 1, Easy = 2, Fair = 3, Difficult = 4, Impossible = 5 }) do
		local v = Enum.RelativeContentDifficulty[name]
		if v ~= nil then
			RELATIVE[v] = tier
		end
	end
end

function QI.TierForQuest(questID, level)
	if questID and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer then
		local ok, v = pcall(C_PlayerInfo.GetContentDifficultyQuestForPlayer, questID)
		if ok and not (issecretvalue and issecretvalue(v)) and v ~= nil then
			local tier = RELATIVE[v] or (type(v) == "number" and v >= 0 and v <= 4 and v + 1) or nil
			if tier then
				return tier
			end
		end
	end
	return QI.Tier(level)
end

function QI.Tier(level)
	level = tonumber(level)
	if not (level and level > 0 and GetQuestDifficultyColor) then
		return nil
	end
	local ok, c = pcall(GetQuestDifficultyColor, level)
	if ok and type(c) == "table" and c.r then
		return QI.TierOfColour(c.r, c.g, c.b)
	end
	return nil
end

--------------------------------------------------------------------------------
-- Pips
--------------------------------------------------------------------------------

local PipsMixin = {}

function PipsMixin:SetTier(tier)
	self.tier = tier
	if not tier then
		self:Hide()
		return
	end
	local c = QI.TIER_COLOUR[tier] or QI.TIER_COLOUR[3]
	for i, pip in ipairs(self.pips) do
		local on = i <= tier
		pip.fill:SetShown(on)
		pip.fill:SetVertexColor(c[1], c[2], c[3])
		pip.ring:SetAlpha(on and 0.9 or 0.4)
	end
	self:Show()
end

-- The row's width for `size` px pips
function QI.PipsWidth(size)
	size = size or 11
	return 5 * size + 4 * math.floor(size * 0.18 + 0.5)
end

function QI.Pips(parent, size)
	size = size or 11
	local gap = math.floor(size * 0.18 + 0.5)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(QI.PipsWidth(size), size)
	f:EnableMouse(true)
	Mixin(f, PipsMixin)
	f.pips = {}
	for i = 1, 5 do
		local fill = f:CreateTexture(nil, "ARTWORK", nil, 1)
		fill:SetTexture(ROOT .. "pip_fill")
		fill:SetSize(size, size)
		fill:SetPoint("LEFT", f, "LEFT", (i - 1) * (size + gap), 0)
		local ring = f:CreateTexture(nil, "ARTWORK", nil, 2)
		ring:SetTexture(ROOT .. "pip_ring")
		ring:SetAllPoints(fill)
		f.pips[i] = { fill = fill, ring = ring }
	end
	-- the words for the count, on hover
	Perf.SetScript(f, "OnEnter", function(self)
		if self.tier then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(QI.TIER_NAME[self.tier] .. " (" .. self.tier .. " of 5)", 1, 1, 1)
			GameTooltip:AddLine("How hard the quest is for your level.", 0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end
	end)
	Perf.SetScript(f, "OnLeave", function()
		GameTooltip:Hide()
	end)
	f:Hide()
	return f
end

--------------------------------------------------------------------------------
-- Ink on font strings: the string's own font kept, its outline and shadow
-- dropped (a black outline round dark ink smudges it); Plain puts it back.
--------------------------------------------------------------------------------

function QI.Ink(fs, role)
	if not (fs and fs.GetFont) then
		return
	end
	if not fs.melloInkSaved then
		local ok, path, size, flags = pcall(fs.GetFont, fs)
		if not (ok and path and size) then
			return
		end
		local sr, sg, sb, sa = fs:GetShadowColor()
		local tr, tg, tb = fs:GetTextColor()
		fs.melloInkSaved = { path = path, size = size, flags = flags or "", shadow = { sr, sg, sb, sa }, colour = { tr, tg, tb } }
	end
	local ok, path, size = pcall(fs.GetFont, fs)
	if ok and path and size then
		pcall(fs.SetFont, fs, path, size, "")
	end
	fs:SetShadowColor(0, 0, 0, 0)
	fs.melloInkRole = role or "title"
	local gr, gg, gb = QI.GameColour(fs)
	local r, g, b = QI.RoleColour(fs.melloInkRole, gr, gg, gb, QI.onSheet[fs])
	QI.inking = true
	fs:SetTextColor(r, g, b)
	QI.inking = false
	fs.melloInk = true
end

-- A role's ink; "auto" inks the game's own colour (QI.InkOf)
-- `sheet`: the string lies on a kit parchment SHEET (darker than the vellum
-- pages; a surface's def.sheet): the inks set for it (QI.InkOf's `sheet`)
QI.onSheet = setmetatable({}, { __mode = "k" })

function QI.RoleColour(role, r, g, b, sheet)
	if role == "auto" then
		return QI.InkOf(r, g, b, sheet)
	end
	-- the body ink on a sheet is the darker title ink (4.7 : 1 there)
	if sheet and role == "text" then
		role = "title"
	end
	local c = QI.INK[role] or QI.INK.title
	return c[1], c[2], c[3]
end

-- The colour the game (or its template) last gave fs, not our ink. While fs
-- is inked, a colour the game gives it later (the quest log recolours a
-- title and its objectives on hover and on leave -- user, 2026-09-23: the
-- difficulty colours came back) is inked over at once; `roleOf(r, g, b)`,
-- when given, picks the ink from the game's colour (a done objective faded).
-- The colour kept in the string's one table (the game recolours often: no
-- table made each time)
local function SetGameColour(fs, r, g, b)
	local c = fs.melloGameColour
	if c then
		c[1], c[2], c[3] = r, g, b
	else
		fs.melloGameColour = { r, g, b }
	end
end

-- a colour the game gives a watched string: kept, and inked over at once
-- while the string is inked. One handler for every watched string: all it
-- keeps is on the string itself
local OnGameColour = Shared("SetTextColor on inked strings", function(self, cr, cg, cb)
	if QI.inking then
		return
	end
	SetGameColour(self, cr, cg, cb)
	if self.melloInk then
		local role = self.melloInkRoleOf and self.melloInkRoleOf(cr, cg, cb) or self.melloInkRole
		self.melloInkRole = role
		local r, g, b = QI.RoleColour(role, cr, cg, cb, QI.onSheet[self])
		QI.inking = true
		self:SetTextColor(r, g, b)
		QI.inking = false
	end
end)

function QI.WatchColour(fs, roleOf)
	if not fs then
		return
	end
	fs.melloInkRoleOf = roleOf or fs.melloInkRoleOf
	if fs.melloColourWatched then
		return
	end
	fs.melloColourWatched = true
	SetGameColour(fs, fs:GetTextColor())
	hooksecurefunc(fs, "SetTextColor", OnGameColour)
end

function QI.GameColour(fs)
	local c = fs and fs.melloGameColour
	if c then
		return c[1], c[2], c[3]
	end
	return 1, 1, 1
end

-- `restoreColour`: the colour it had before the first ink too (a label
-- nothing else colours again)
function QI.Plain(fs, restoreColour)
	local saved = fs and fs.melloInkSaved
	if not (saved and fs.melloInk) then
		return
	end
	local ok, path, size = pcall(fs.GetFont, fs)
	if ok and path and size then
		pcall(fs.SetFont, fs, path, size, saved.flags)
	end
	local s = saved.shadow
	if s and s[1] then
		fs:SetShadowColor(s[1], s[2], s[3], s[4] or 1)
	end
	fs.melloInk = nil
	local c = saved.colour
	if restoreColour and c and c[1] then
		QI.inking = true
		fs:SetTextColor(c[1], c[2], c[3])
		QI.inking = false
	end
end

--------------------------------------------------------------------------------
-- Any string by its own colour, and the surfaces of the interface
--------------------------------------------------------------------------------

-- A string's text with colour codes of its own (a stat's value, a name in its
-- class colour): the codes inked while the string is, the text as the game
-- wrote it put back after
local function InkTextCodes(fs)
	if QI.texting or not fs.melloInk then
		return
	end
	local ok, text = pcall(fs.GetText, fs)
	if not ok or type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or not text:find("|c", 1, true) then
		return
	end
	local inked = QI.InkCodes(text, QI.onSheet[fs])
	if inked ~= text then
		fs.melloPlainText = text
		QI.texting = true
		fs:SetText(inked)
		QI.texting = false
	end
end

-- The hooks on every watched string, one handler each for all of them. A
-- new text: its colour codes inked again (SetText and SetFormattedText, one
-- body under two report rows)
local function NewText(self)
	if not QI.texting then
		self.melloPlainText = nil
		InkTextCodes(self)
	end
end
local OnSetText = Shared("SetText on inked strings", NewText)
local OnSetFormattedText = Shared("SetFormattedText on inked strings", NewText)
-- a font object set again brings its colour and outline back: ink again
local OnSetFontObject = Shared("SetFontObject on inked strings", function(self)
	if self.melloInk then
		SetGameColour(self, self:GetTextColor())
		QI.Ink(self, self.melloInkRole)
	end
end)

local function WatchText(fs)
	if fs.melloTextWatched then
		return
	end
	fs.melloTextWatched = true
	hooksecurefunc(fs, "SetText", OnSetText)
	if fs.SetFormattedText then
		hooksecurefunc(fs, "SetFormattedText", OnSetFormattedText)
	end
	if fs.SetFontObject then
		hooksecurefunc(fs, "SetFontObject", OnSetFontObject)
	end
end

function QI.InkText(fs)
	QI.WatchColour(fs)
	QI.Ink(fs, "auto")
	WatchText(fs)
	InkTextCodes(fs)
end

-- back to its own look and the colour the game last gave it
function QI.PlainText(fs)
	if not (fs and fs.melloInk) then
		return
	end
	QI.Plain(fs)
	if fs.melloColourWatched then
		QI.inking = true
		fs:SetTextColor(QI.GameColour(fs))
		QI.inking = false
	end
	if fs.melloPlainText then
		QI.texting = true
		fs:SetText(fs.melloPlainText)
		QI.texting = false
		fs.melloPlainText = nil
	end
end

QI.surfaces = {}

local WEAK = { __mode = "k" }

-- Every string under `frame` (twelve levels down), a frame or string marked
-- melloNoInk left out (/inkwhy's; the passes walk the same way, below)
local function Walk(frame, depth, fn)
	if depth > 12 or not frame or frame.melloNoInk then
		return
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" and not region.melloNoInk then
			fn(region)
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		Walk(child, depth + 1, fn)
	end
end

--------------------------------------------------------------------------------
-- Kept cheap (/melloperf, user 2026-09-24: the pass over every surface once
-- a second took 37-50 ms, a hitch each second, and made a quarter MB of
-- garbage; a window shown cost three more such passes). What a pass decides
-- is what it always decided; how it gets there:
--  * nothing is made in a pass: a frame's regions and children are read into
--    scratch lists, a frame's own plates and the parchment sheets are
--    measured once a batch (a frame's work) in screen space, not again for
--    every string
--  * which of the kit's plates show (Kit.repList only grows: thousands of an
--    evening) is asked once a pass, as it always was, in slices like the
--    pass itself, afresh for a change and for a row a list fills; where
--    those lie, again for each frame the pass goes on in
--  * each frame once a pass, however many of the surface's roots hold it
--  * a pass runs a little each frame (SLICE_MS), the frames that show first;
--    a change (a window shown, the parchment switched) inks what shows at
--    once, within SYNC_MS a frame (FIRST_MS for a surface just switched on,
--    every string of it new: a window's first open shows no game colours on
--    its paper), the hidden frames the next frames; the roots of one window
--    shown together are one pass, and the passes after they show one set
--  * a row a list fills is inked at once, and looked at again the next frame
--------------------------------------------------------------------------------
local SLICE_MS = 1                   -- the passes' share of a frame
local SYNC_MS = 1.5                  -- what the changes of one frame may take at once
local FIRST_MS = 8                   -- ... a surface just switched on (once: its first open)
local MAX_DEPTH = 12                 -- a root's levels walked
local SETTLE = { 0.05, 0.15, 0.3 }   -- a root shown: looked at again as its rows settle

-- A batch: the work of one frame (GetTime is the frame's), or of a change
-- (Batch(true): a window just shown) -- what is measured holds within it.
-- `stamp`: the same for what a frame holds itself (its plates, where its
-- strings lie), measured afresh for a row just filled as well.
local batch, stamp, batchTime = 0, 0, nil
local function Batch(fresh)
	local t = GetTime()
	if fresh or t ~= batchTime then
		batch, stamp, batchTime = batch + 1, stamp + 1, t
	end
end

local select = select

-- `...` into t[1 .. n], no table made; returns n (t's entries past n are
-- stale, never read)
local function Pack(t, ...)
	local n = select("#", ...)
	local i = 1
	while i + 7 <= n do
		t[i], t[i + 1], t[i + 2], t[i + 3], t[i + 4], t[i + 5], t[i + 6], t[i + 7] = select(i, ...)
		i = i + 8
	end
	while i <= n do
		t[i] = (select(i, ...))
		i = i + 1
	end
	return n
end

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

-- obj's rect in screen space (its scale applied): left, bottom, right, top;
-- nil while it is not laid out (or secret)
local function ScreenRect(obj)
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if not (ok and l and b and w and h) or Secret(l) or Secret(b) or Secret(w) or Secret(h) then
		return nil
	end
	local s = obj:GetEffectiveScale()
	l, b, w, h = l * s, b * s, w * s, h * s
	if l ~= l or b ~= b or w ~= w or h ~= h then
		return nil   -- (not a number: no cell of the grid holds it)
	end
	return l, b, l + w, b + h
end

-- a string's centre in screen space (nil while it is not laid out), the
-- last string's kept for its stamp (the skip and the sheet ask alike)
local centreOf, centreStamp, centreX, centreY = nil, nil, nil, nil
local function Centre(fs)
	if fs == centreOf and centreStamp == stamp then
		return centreX, centreY
	end
	local ok, x, y = pcall(fs.GetCenter, fs)
	if ok and x and y and not (Secret(x) or Secret(y)) then
		local s = fs:GetEffectiveScale()
		x, y = x * s, y * s
	else
		x, y = nil, nil
	end
	centreOf, centreStamp, centreX, centreY = fs, stamp, x, y
	return x, y
end

-- whether (x, y) lies in the rect at list[i .. i + 3]; nil when either is not
-- laid out (list[i] false)
local function In(list, i, x, y)
	local l = list[i]
	if not (x and l) then
		return nil
	end
	return x >= l and x <= list[i + 2] and y >= list[i + 1] and y <= list[i + 3]
end

-- a widget's type, asked once (it never changes)
local kindOf = setmetatable({}, WEAK)
local function KindOf(obj)
	local kind = kindOf[obj]
	if kind == nil then
		kind = obj.GetObjectType and obj:GetObjectType() or false
		kindOf[obj] = kind
	end
	return kind
end

-- a replacement that is a plate behind text (a header, a row's plate, a
-- bar's bracket, a slot); not a line (a divider) nor a picture or tile
local PLATE_KIND = { strip = true, frame = true, bar = true, slot = true }
-- the kit's plates a string may lie over wherever they were put (OverPlate)
local GLOBAL_PLATE = { strip = true, bar = true, slot = true }

-- a replacement's painted base ("" when it has none)
local function PlateBase(rep)
	return (rep.strip and rep.strip.base) or (rep.rule and rep.rule.base) or ""
end

-- The kit's replacements, taken in as the kit makes them (Kit.repList only
-- grows): each by its region, and those of the kinds above for OverPlate
-- (a divider's line never: its base is the kit's rule, fixed when made)
local regionRep, repCount = setmetatable({}, WEAK), 0
local plateReps = {}
local function SyncReps()
	local Kit = MelloUI.Kit
	local list = Kit and Kit.repList
	if not list or #list == repCount then
		return
	end
	for i = repCount + 1, #list do
		local rep = list[i]
		if rep then
			if rep.region then
				regionRep[rep.region] = rep
			end
			if GLOBAL_PLATE[rep.kind] and not PlateBase(rep):find("divider", 1, true) then
				plateReps[#plateReps + 1] = rep
			end
		end
	end
	repCount = #list
end

-- The kit's replacement for a region
local function RepOf(region)
	SyncReps()
	return regionRep[region]
end

-- a texture of the game's that is a plate (its atlas a kit rule's strip,
-- bar or frame), shown and solid
local GAME_PLATE_KIND = { strip = true, bar = true, frame = true }
local function GamePlate(region)
	if KindOf(region) ~= "Texture" or region.kitName or not region:IsShown() then
		return false
	end
	local okA, alpha = pcall(region.GetAlpha, region)
	if not okA or not alpha or alpha < 0.3 then
		return false
	end
	local okT, atlas = pcall(region.GetAtlas, region)
	if not (okT and type(atlas) == "string") then
		return false
	end
	local Kit = MelloUI.Kit
	local rule = Kit and Kit.Replacements and Kit.Replacements[atlas]
	if not (rule and GAME_PLATE_KIND[rule.kind]) then
		return false
	end
	-- the game's row bands (UI-Character-Info-Line-Bounce and the like) are
	-- faint see-through stripes on the paper, not plates: the stats' every
	-- other row kept its yellow (user, 2026-09-23: "changing colors from
	-- Yellow to Black randomly")
	local base = tostring(rule.base or rule.prefix or "")
	if base:find("divider", 1, true) or base:find("^lists/plate") or base:find("^lists/row") then
		return false
	end
	return true
end

local function IsPlate(rep)
	if not (rep and PLATE_KIND[rep.kind]) then
		return false
	end
	return not PlateBase(rep):find("divider", 1, true)
end

-- Whether fs's centre lies in frame f (their scales apart; /inkwhy's)
local function Inside(fs, f)
	local okF, fx, fy = pcall(fs.GetCenter, fs)
	local okB, l, b, w, h = pcall(f.GetRect, f)
	if not (okF and okB and fx and l and w) or (issecretvalue and (issecretvalue(fx) or issecretvalue(l))) then
		return nil
	end
	local k = fs:GetEffectiveScale() / f:GetEffectiveScale()
	fx, fy = fx * k, fy * k
	return fx >= l and fx <= l + w and fy >= b and fy <= b + h
end

-- The kit's plates shown now: the strips (headers, row plates, a row's
-- hover or selection), the bars' brackets and the slot rims -- not the
-- dividers (lines), nor the frames (a window's frame lies under everything
-- in it). A string over one keeps its colours, however the plate was put
-- there (user, 2026-09-23: the stats' category plates belong to another
-- frame than their names). Measured into a coarse grid of the screen: a
-- string's centre looks only at the plates of its cell (the first in the
-- kit's order that holds it, as when every plate was asked). As the list
-- of them always was, the plates that show are taken once a pass (a pass
-- asks for them as it begins, a change and a row a list fills as they are
-- then): every replacement asked whether it shows, many and more as the
-- evening goes on, so in slices within the pass's time. Where each lies is
-- measured again for each frame the pass goes on in (a list scrolled, a
-- window dragged: the old passes asked every plate's place as they went),
-- those that showed only; one found under a string that was measured in an
-- earlier batch is asked again as it is now.
local CELL, CELLS_X, CELLS_Y = 64, 64, 16
local PLATE_AGE = 0.2   -- s: a pass that runs longer takes the plates that show again
local members, memberN = {}, 0   -- the plates that showed when every one was last asked
local plateObj, plateL, plateB, plateR, plateT = {}, {}, {}, {}, {}   -- the grid's plates, where each lay
local plateSeen, nowL, nowB, nowR, nowT = {}, {}, {}, {}, {}   -- one asked again: the stamp, its rect then
local cells, gen, gridGen = {}, 0, nil
local gridWant, gridHave, gridBegan = 1, 0, nil   -- every plate asked: the asking wanted, the one done (begun then)
local placedTime, placedStamp, placedUsed = nil, nil, false   -- the grid's places: measured then, read since
local building, buildNo, buildAt, buildN, buildBegan, buildStamp = nil, nil, 1, 0, nil, nil   -- a grid being measured
local lookNoForce = false   -- a pane the game just refreshed is looked at (QI.LookRow): no grid finished for it

local function CellOf(v, last)
	local c = math.floor(v / CELL)
	return (c < 0 and 0) or (c > last and last) or c
end

-- Every plate asked again, begun at `t` or later; nil: begun now (a change)
local function WantPlates(t)
	local began
	if building == "all" and buildNo == gridWant then
		began = buildBegan
	elseif gridHave == gridWant then
		began = gridBegan
	else
		return   -- asked for already, not begun: it begins now or later
	end
	if t == nil or not began or began < t then
		gridWant = gridWant + 1
	end
end

-- The grid measured, on until `deadline` (debugprofilestop; nil: to the
-- end): every plate asked when that is wanted; else the plates that showed
-- measured where they lie, when their places were measured before `since`
-- (a pass: this frame's, once the last places were read -- a slice at
-- least between two) or at `since` (`after`: a row filled then). True once
-- the grid is there.
local function BuildPlates(deadline, since, after)
	local all = gridHave ~= gridWant
	if not (all or building == "place") then
		local older = since and (not placedTime or placedTime < since or (after and placedTime == since))
		if not (older and (placedUsed or after)) then
			return true
		end
	end
	SyncReps()
	local kind = all and "all" or "place"
	if building ~= kind or (all and buildNo ~= gridWant) then
		Batch()
		gen = gen + 1
		building, buildNo, buildAt, buildN, buildBegan, buildStamp = kind, gridWant, 1, 0, GetTime(), stamp
		if all then
			memberN = 0
		end
	end
	local n, count = buildN, 0
	for i = buildAt, all and #plateReps or memberN do
		if deadline and count >= 16 then
			count = 0
			if debugprofilestop() >= deadline then
				buildAt, buildN = i, n
				return false
			end
		end
		count = count + 1
		local obj
		if all then
			local rep = plateReps[i]
			obj = rep.object
			if obj and obj.IsVisible and not PlateBase(rep):find("divider", 1, true) and obj:IsVisible() then
				memberN = memberN + 1
				members[memberN] = obj
			else
				obj = nil
			end
		else
			obj = members[i]
			if not obj:IsVisible() then
				obj = nil
			end
		end
		local l, b, r, t
		if obj then
			l, b, r, t = ScreenRect(obj)
		end
		if l then
			n = n + 1
			plateObj[n], plateL[n], plateB[n], plateR[n], plateT[n] = obj, l, b, r, t
			plateSeen[n] = nil
			for cx = CellOf(l, CELLS_X - 1), CellOf(r, CELLS_X - 1) do
				for cy = CellOf(b, CELLS_Y - 1), CellOf(t, CELLS_Y - 1) do
					local key = cx * CELLS_Y + cy + 1
					local cell = cells[key]
					if not cell then
						cell = { n = 0 }
						cells[key] = cell
					end
					if cell.gen ~= gen then
						cell.gen, cell.n = gen, 0
					end
					cell.n = cell.n + 1
					cell[cell.n] = n
				end
			end
		end
	end
	if all then
		gridHave, gridBegan = buildNo, buildBegan
	end
	gridGen, placedTime, placedStamp, placedUsed, building = gen, buildBegan, buildStamp, false, nil
	return true
end

-- The window a widget lies in: its ancestor just under UIParent (or under
-- WorldFrame: a nameplate). A plate of another window or of the HUD (a
-- nameplate's or a unit frame's bar, the tooltip's, an action slot) is drawn
-- under or over this window, never between its paper and its text: it once
-- put a line's game colour back for a second or two whenever one passed
-- behind it (user, 2026-09-24: the Reputation, Skill and PvP text "flickers
-- White then black every now and then"). Kept per widget with the parent it
-- was found through (walked again when that changes; all of them again when
-- a surface changes, StartPass)
local topOf, topVia = setmetatable({}, WEAK), setmetatable({}, WEAK)
local function TopOf(obj)
	local up = obj:GetParent()
	local top = topOf[obj]
	if top and topVia[obj] == up then
		return top
	end
	top = obj
	local p = up
	while p and p ~= UIParent and p ~= WorldFrame and not (p.IsForbidden and p:IsForbidden()) do
		top, p = p, p:GetParent()
	end
	topOf[obj], topVia[obj] = top, up
	return top
end

local function OverPlate(fs)
	Batch()
	if building or gridHave ~= gridWant then
		-- a pane the game has just refreshed never waits on every plate being
		-- asked (a whole grid in the frame it shows: a hitch); its own plates
		-- it has from its frames, the next pass the rest
		if lookNoForce and (building == "all" or gridHave ~= gridWant) then
			return nil
		end
		BuildPlates(nil)   -- (a pass or a row list has it measured before it asks)
	end
	placedUsed = true
	local x, y = Centre(fs)
	if not x then
		return nil
	end
	local cell = cells[CellOf(x, CELLS_X - 1) * CELLS_Y + CellOf(y, CELLS_Y - 1) + 1]
	if cell and cell.gen == gridGen then
		local stale = placedStamp ~= stamp
		local win = nil   -- fs's window, asked at the first plate under it
		for j = 1, cell.n do
			local i = cell[j]
			if x >= plateL[i] and x <= plateR[i] and y >= plateB[i] and y <= plateT[i] then
				win = win or TopOf(fs)
				-- only a plate of its own window
				if TopOf(plateObj[i]) == win then
					if not stale then
						return plateObj[i]
					end
					-- measured in an earlier batch: shown and there now?
					if plateSeen[i] ~= stamp then
						plateSeen[i] = stamp
						local obj, l, b, r, t = plateObj[i], nil, nil, nil, nil
						if obj:IsVisible() then
							l, b, r, t = ScreenRect(obj)
						end
						nowL[i], nowB[i], nowR[i], nowT[i] = l or false, b, r, t
					end
					local l = nowL[i]
					if l and x >= l and x <= nowR[i] and y >= nowB[i] and y <= nowT[i] then
						return plateObj[i]
					end
				end
			end
		end
	end
	return nil
end
QI.OverPlate = OverPlate

-- What a frame holds that may lie under a string of it, as DefaultSkip asks
-- it, measured once a stamp (the strings of a row share it): its kit strips
-- that show, for a string's row and the row's parent the plates among its
-- regions, whether it is a bar that shows, whether a plate or an icon of
-- its own shows. A rect is four numbers in screen space, false first while
-- it is not laid out.
local OWN_PLATES = { "melloRep", "melloHeader", "melloPlate" }
local OWN_ICONS = { "icon", "Icon" }
local stripsOf = setmetatable({}, WEAK)
local infoOf = setmetatable({}, WEAK)
local kidScratch, regionScratch = {}, {}

-- A frame's children that are kit strips (a Kit:Strip: `base`, `mid`), read
-- again only when its children change (UIParent has hundreds)
local function StripsOf(f)
	local list = stripsOf[f]
	local count = f:GetNumChildren()
	if list and list.count == count then
		return list
	end
	if not list then
		list = { n = 0 }
		stripsOf[f] = list
	end
	local n = 0
	for i = 1, Pack(kidScratch, f:GetChildren()) do
		local child = kidScratch[i]
		if rawget(child, "base") ~= nil or rawget(child, "mid") ~= nil then
			n = n + 1
			list[n] = child
		end
	end
	for i = n + 1, list.n do
		list[i] = nil
	end
	list.n, list.count = n, count
	return list
end

local function AddRect(list, n, obj)
	local l, b, r, t = ScreenRect(obj)
	list[n + 1], list[n + 2], list[n + 3], list[n + 4] = l or false, b, r, t
	return n + 4
end

local function Info(f, regions)
	local info = infoOf[f]
	if not info then
		info = { s = {}, r = {}, b = {}, sn = 0, rn = 0 }
		infoOf[f] = info
	end
	if info.stamp ~= stamp then
		info.stamp = stamp
		-- a painted plate of the kit (a Kit:Strip: a header, a row's hover or
		-- selection, a bar's bracket) shown behind it, however it was put
		-- there (user, 2026-09-23: the stats' category names on their dark
		-- plates were inked)
		local list, n = StripsOf(f), 0
		for i = 1, list.n do
			local child = list[i]
			local base = rawget(child, "base")
			if base and rawget(child, "mid") and child:IsShown() and not tostring(base):find("divider", 1, true) then
				n = AddRect(info.s, n, child)
			end
		end
		info.sn = n
		-- only the text over a bar (a rank, a standing); a name beside it on
		-- the paper, though the bar's child, is inked (user, 2026-09-23)
		info.bar = KindOf(f) == "StatusBar" and f:IsShown()
		if info.bar then
			AddRect(info.b, 0, f)
		end
		local own = false
		for i = 1, #OWN_PLATES do
			local rep = rawget(f, OWN_PLATES[i])
			local obj = type(rep) == "table" and rep.object
			if obj and obj.IsShown and obj:IsShown() then
				own = true
				break
			end
		end
		if not own then
			for i = 1, #OWN_ICONS do
				local tex = rawget(f, OWN_ICONS[i])
				if type(tex) == "table" and tex.IsShown and KindOf(tex) == "Texture" and tex:IsShown() then
					own = true
					break
				end
			end
		end
		info.own = own
	end
	if regions and info.rStamp ~= stamp then
		info.rStamp = stamp
		local n = 0
		for i = 1, Pack(regionScratch, f:GetRegions()) do
			local region = regionScratch[i]
			-- the row's own art replaced by a kit plate drawn elsewhere (the
			-- stats' category headers: their Background, the plate on another
			-- frame)
			local rep = RepOf(region)
			if IsPlate(rep) and rep.object and rep.object.IsShown and rep.object:IsShown() then
				n = AddRect(info.r, n, rep.object)
			end
			-- the game's own plate art, not reskinned (a pooled row made after
			-- the reskin: the PvP tab's "Next Rewards" header, user 2026-09-23):
			-- a shown texture whose atlas the kit knows as a plate
			if GamePlate(region) then
				n = AddRect(info.r, n, region)
			end
		end
		info.rn = n
	end
	return info
end

-- The strings a surface leaves as they are: on a bar (a reputation, a
-- skill), on a kit plate that is showing (a header, a selected row), over an
-- icon (a count), or under a frame marked melloNoInk. nil: not laid out yet
-- (undecided).
function QI.DefaultSkip(fs)
	-- the plates that show now lie under a string whose frame shows; a hidden
	-- tab's strings under them belong to the tab shown in its place (user,
	-- 2026-09-24: its text came up in the game's colours as its tab showed).
	-- A string hidden by itself on a shown frame keeps the plate it will show on
	Batch()
	if (fs:GetParent() or fs):IsVisible() and OverPlate(fs) then
		return true
	end
	local x, y = Centre(fs)
	local f = fs:GetParent()
	for depth = 1, 4 do
		-- (never past its window: what lies under UIParent is another's)
		if not f or f == UIParent or f == WorldFrame then
			return false
		end
		if f.melloNoInk then
			return true
		end
		-- its plates (the regions' of the row and its parent only: further up
		-- a whole box's stone frame would count as a plate under everything
		-- in it), in the order they were always asked
		local info = Info(f, depth <= 2)
		for i = 1, info.sn, 4 do
			local inside = In(info.s, i, x, y)
			if inside ~= false then
				return inside
			end
		end
		for i = 1, depth <= 2 and info.rn or 0, 4 do
			local inside = In(info.r, i, x, y)
			if inside ~= false then
				return inside
			end
		end
		if info.bar then
			local inside = In(info.b, 1, x, y)
			if inside ~= false then
				return inside
			end
		end
		if info.own then
			return true
		end
		f = f.GetParent and f:GetParent()
	end
	return false
end

-- Whether a string lies on a shown parchment sheet of `area` (a sheet that
-- covers part of its window only: the character window's lies on its right
-- pane, and the Skills tab's rows beside it are on stone -- user, 2026-09-23:
-- "i cant read the left side of the text like that")
-- nil while it cannot tell yet (the string or the sheet not laid out, no
-- sheet shown for the moment: a tab being switched -- user, 2026-09-23: the
-- text went white for a moment on quick tab switches)
local sheetsOf = {}   -- [area] = the sheets shown and their rects, for a stamp
function QI.OnSheet(fs, area)
	local Kit = MelloUI.Kit
	local list = Kit and Kit.parchmentSheets and Kit.parchmentSheets[area]
	if not list then
		return false
	end
	Batch()
	local x, y = Centre(fs)
	if not x then
		return nil
	end
	local sheets = sheetsOf[area]
	if not sheets then
		sheets = { n = 0 }
		sheetsOf[area] = sheets
	end
	if sheets.stamp ~= stamp then
		sheets.stamp, sheets.any = stamp, false
		local n = 0
		for _, entry in ipairs(list) do
			local sheet = entry.sheet
			if sheet and sheet:IsVisible() then
				sheets.any = true
				n = AddRect(sheets, n, sheet)   -- (one not laid out holds nothing)
			end
		end
		sheets.n = n
	end
	if not sheets.any then
		return nil
	end
	for i = 1, sheets.n, 4 do
		if In(sheets, i, x, y) then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- The passes
--------------------------------------------------------------------------------

-- One string inked or put back by its surface's rules
-- the strings last decided, while they showed, as lying on a plate or bar:
-- QI.LookRow leaves them to the passes (it may look while every plate is
-- being asked again, and would ink one on a plate only that asking sees). One
-- decided while hidden (a pane's empty text under another tab's plate) it
-- looks at as it shows
local plated = setmetatable({}, WEAK)

local function Evaluate(def, fs)
	if not def.active then
		return
	end
	local skip = false
	if def.skip then
		skip = def.skip(fs)
		if skip == nil then
			return   -- cannot tell yet: as it is, the next pass decides
		end
	end
	plated[fs] = (skip and fs:IsVisible()) or nil
	if def.strings[fs] then
		if skip then
			-- now on a plate or bar (a row selected): its own colours
			QI.PlainText(fs)
			def.strings[fs] = nil
		elseif not fs.melloInk then
			QI.InkText(fs)
		end
	elseif not skip then
		def.strings[fs] = true
		if def.sheet then
			QI.onSheet[fs] = true
		end
		-- def.plainInk(fs): a text whose colour means nothing here (the
		-- game's system blue on a notice) takes the body ink, not a
		-- shade of its hue (user, 2026-09-24: "the text is blue")
		if def.plainInk and def.plainInk(fs) then
			QI.WatchColour(fs, function() return "text" end)
			QI.Ink(fs, "text")
		else
			QI.InkText(fs)
		end
	end
end

-- The passes run from a frame of ours while they have work, a slice a frame
local driver = CreateFrame("Frame")
driver:Hide()
local inPass, inRow = false, false   -- a pass / a row being walked now

-- A pass walks its roots from two stacks: the frames that show first, then
-- the hidden ones. Each frame once a pass, however many roots hold it (the
-- character window's roots lie inside one another); one reached again
-- nearer a root is walked again below, as far as a root's twelve levels go.
-- The next frame to walk: it, its level, whether it shows, the first of its
-- regions to look at (nil: its strings were done, only its children again);
-- `shownOnly`: nil once the frames that show are done
local function NextFrame(job, shownOnly)
	while true do
		local frame, depth, shows
		local n = job.shown
		if n > 0 then
			frame, depth, shows = job.shownF[n], job.shownD[n], true
			job.shown = n - 1
		elseif shownOnly then
			return nil
		else
			n = job.hidden
			if n == 0 then
				return nil
			end
			frame, depth, shows = job.hiddenF[n], job.hiddenD[n], false
			job.hidden = n - 1
		end
		if not frame.melloNoInk then
			local again = job.visit[frame] == job.id
			if not (again and job.depth[frame] <= depth) then
				job.visit[frame], job.depth[frame] = job.id, depth
				return frame, depth, shows and frame:IsVisible(), not again and 1 or nil
			end
		end
	end
end

-- One frame: its strings from the `from`th region on, then its children onto
-- the stacks. False when the slice ran out among its strings (a frame of
-- many): the rest of them first the next time.
local travRegions, travKids = {}, {}
local function Visit(def, job, frame, depth, shows, from, deadline)
	if from then
		local n = Pack(travRegions, frame:GetRegions())
		for i = from, n do
			local region = travRegions[i]
			if KindOf(region) == "FontString" and not region.melloNoInk then
				Evaluate(def, region)
				if i < n and debugprofilestop() >= deadline then
					job.at, job.atDepth, job.atShows, job.atFrom = frame, depth, shows, i + 1
					return false
				end
			end
		end
	end
	if depth < MAX_DEPTH then
		for i = Pack(travKids, frame:GetChildren()), 1, -1 do
			local child = travKids[i]
			if shows and child:IsShown() then
				local n = job.shown + 1
				job.shown, job.shownF[n], job.shownD[n] = n, child, depth + 1
			else
				local n = job.hidden + 1
				job.hidden, job.hiddenF[n], job.hiddenD[n] = n, child, depth + 1
			end
		end
	end
	return true
end

-- On until `deadline` (debugprofilestop), the kit's plates measured first
-- (where they lie this frame); true when the pass is done. `shownOnly`: the
-- frames that show, the hidden ones left to the driver
local function RunJob(def, job, deadline, shownOnly)
	if not BuildPlates(deadline, GetTime()) then
		return false
	end
	inPass = true
	while true do
		local frame, depth, shows, from = job.at, job.atDepth, job.atShows, job.atFrom
		if frame then
			if shownOnly and not shows then
				inPass = false
				return false
			end
			job.at = nil   -- a frame left half done
		else
			frame, depth, shows, from = NextFrame(job, shownOnly)
			if not frame then
				inPass = false
				return job.hidden == 0
			end
		end
		local done = Visit(def, job, frame, depth, shows, from, deadline)
		if not done or debugprofilestop() >= deadline then
			inPass = false
			return done and job.shown == 0 and job.hidden == 0
		end
	end
end

local function Wake()
	driver:Show()
end

-- A scrolling list among a surface's frames: each row inked the moment the
-- list fills it (user, 2026-09-23: scrolling the stats showed their game
-- colours until the next pass), and looked at again the next frame, when the
-- list has laid it out
local rowRegions, rowKids = {}, {}   -- a scratch list for each level
local rowFrame, rowDef, rowAt, rowHead, rowTail = {}, {}, {}, 1, 0
local rowQueued = setmetatable({}, WEAK)

local function WalkRow(def, frame, depth)
	if depth > MAX_DEPTH or not frame or frame.melloNoInk then
		return
	end
	local regions, kids = rowRegions[depth], rowKids[depth]
	if not regions then
		regions, kids = {}, {}
		rowRegions[depth], rowKids[depth] = regions, kids
	end
	for i = 1, Pack(regions, frame:GetRegions()) do
		local region = regions[i]
		if KindOf(region) == "FontString" and not region.melloNoInk then
			Evaluate(def, region)
		end
	end
	for i = 1, Pack(kids, frame:GetChildren()) do
		WalkRow(def, kids[i], depth + 1)
	end
end

local function RowFilled(name, frame)
	local def = QI.surfaces[name]
	if not (def and def.active and frame) then
		return
	end
	if not inRow then
		inRow = true
		Batch()
		stamp = stamp + 1   -- its own plates and places measured anew
		WantPlates(GetTime())   -- the kit's as they are this frame (the list has moved)
		WalkRow(def, frame, 0)
		inRow = false
	end
	if not rowQueued[frame] then
		rowQueued[frame] = true
		rowTail = rowTail + 1
		rowFrame[rowTail], rowDef[rowTail], rowAt[rowTail] = frame, def, GetTime()
		Wake()
	end
end

-- A frame the game has just filled and laid out itself (a character side
-- pane's Refresh / SetEmpty: LayoutRows, its empty text shown): the strings
-- that show and carry no ink (a pooled row made just now, a text left plain
-- while it was hidden) decided now, before the frame is drawn -- they showed
-- in the game's colours until the next pass (user, 2026-09-24); the inked
-- ones the hooks keep. On the game's own call only: nothing between. Never
-- finishes the grid of every plate in that frame (lookNoForce)
local function LookNew(def, frame, depth)
	if depth > MAX_DEPTH or not frame or frame.melloNoInk then
		return
	end
	local regions, kids = rowRegions[depth], rowKids[depth]
	if not regions then
		regions, kids = {}, {}
		rowRegions[depth], rowKids[depth] = regions, kids
	end
	for i = 1, Pack(regions, frame:GetRegions()) do
		local region = regions[i]
		if KindOf(region) == "FontString" and not region.melloNoInk and not region.melloInk and not plated[region]
			and region:IsVisible() then
			Evaluate(def, region)
		end
	end
	for i = 1, Pack(kids, frame:GetChildren()) do
		local kid = kids[i]
		if kid:IsShown() then
			LookNew(def, kid, depth + 1)
		end
	end
end

function QI.LookRow(name, frame)
	local def = QI.surfaces[name]
	if not (def and def.active and frame) or inRow or inPass or not frame:IsVisible() then
		return
	end
	inRow, lookNoForce = true, true
	Batch()
	stamp = stamp + 1   -- laid out just now: its places measured anew
	pcall(LookNew, def, frame, 0)
	inRow, lookNoForce = false, false
end

local rowsHooked = setmetatable({}, WEAK)   -- [box] = { [surface] = true }
local function HookRows(name, root)
	local box = (root.ForEachFrame and root) or (root.ScrollBox and root.ScrollBox.ForEachFrame and root.ScrollBox) or nil
	local hooked = box and rowsHooked[box]
	if not (box and ScrollUtil and ScrollUtil.AddInitializedFrameCallback) or (hooked and hooked[name]) then
		return
	end
	if not hooked then
		hooked = {}
		rowsHooked[box] = hooked
	end
	hooked[name] = true
	ScrollUtil.AddInitializedFrameCallback(box, function(_, frame)
		RowFilled(name, frame)
	end, QI, false)
end

-- a root shown: looked at at once, and again as its rows settle (a tab
-- switched: the rows are laid out after it shows; a row seen before it
-- settled could stand on the sheet for a moment -- user, 2026-09-23: the
-- reputation names "sometimes" changed) -- the passes at SETTLE, one set a
-- surface however many of its roots show. A root that already showed when
-- a change began the surface's pass this frame (the character window's
-- roots lie inside one another: each tells of the same show) goes on with
-- that pass, not one begun again.
local RunNow   -- below
local shownHooked = setmetatable({}, WEAK)   -- [root] = { [surface] = true }
local function HookRoot(def, root)
	local name = def.name
	local hooked = shownHooked[root]
	if root.HookScript and not (hooked and hooked[name]) then
		if not hooked then
			hooked = {}
			shownHooked[root] = hooked
		end
		hooked[name] = true
		Perf.HookScript(root, "OnShow", function(self)
			local d = QI.surfaces[name]
			local job = d and d.job
			if job and job.running and job.full and job.began == GetTime() and job.rootShown[self] == job.id then
				RunNow(d)
			else
				QI.RefreshSurface(name)
			end
			if d and d.active then
				d.settleFrom, d.settleStep = GetTime(), 1
				Wake()
			end
		end)
	end
	if not def.noWalk then
		HookRows(name, root)
	end
end

-- A pass over a surface's roots, from the top: `full`, the hidden roots too
-- (a change); else those that show (the pass each second)
local passes = 0
local function StartPass(def, full)
	local job = def.job
	if not job then
		job = {
			id = 0, visit = setmetatable({}, WEAK), depth = setmetatable({}, WEAK), roots = {},
			shown = 0, shownF = {}, shownD = {}, hidden = 0, hiddenF = {}, hiddenD = {},
			rootShown = setmetatable({}, WEAK),   -- [root] = the pass it showed at the start of
		}
		def.job = job
	end
	passes = passes + 1
	job.id, job.shown, job.hidden, job.at = passes, 0, 0, nil
	job.full, job.began = full, GetTime()
	if full then
		wipe(topOf)   -- a change: the windows found again (a frame further up moved elsewhere)
	end
	-- the roots as the surface names them now, up to the first it lacks
	-- (the list always ended there)
	local roots = job.roots
	local n = Pack(roots, def.roots())
	for i = 1, n do
		local root = roots[i]
		if root == nil then
			break
		end
		if root and root.GetRegions then
			local shows = root:IsVisible()
			if full or shows then
				HookRoot(def, root)
				if not def.noWalk then
					if shows then
						job.shown = job.shown + 1
						job.shownF[job.shown], job.shownD[job.shown] = root, 0
						job.rootShown[root] = job.id
					else
						job.hidden = job.hidden + 1
						job.hiddenF[job.hidden], job.hiddenD[job.hidden] = root, 0
					end
				end
			end
		end
	end
	job.running = job.shown > 0 or job.hidden > 0
	if job.running then
		WantPlates(job.began)   -- the kit's plates as the pass begins
		Wake()
	end
end

local function StopPass(def)
	local job = def.job
	if job then
		job.running, job.shown, job.hidden, job.at = false, 0, 0, nil
	end
	def.settleStep = nil
end

-- A change's pass: what shows, at once, as far as this frame's SYNC_MS goes
-- (`first`: a surface just switched on, every string of it new -- a
-- window's first open: FIRST_MS), on from there the next frames; `fresh`:
-- everything measured anew (a change just made)
local syncTime, syncLeft = nil, 0
RunNow = function(def, fresh, first)
	local job = def.job
	if not (job and job.running) or inPass then
		return   -- (asked from within a pass: the driver goes on with it)
	end
	local now = GetTime()
	if now ~= syncTime then
		syncTime, syncLeft = now, SYNC_MS
	end
	if fresh then
		Batch(true)
		WantPlates(nil)
	end
	local budget = syncLeft
	if first and budget < FIRST_MS then
		budget = FIRST_MS
	end
	if budget > 0 then
		local t0 = debugprofilestop()
		if RunJob(def, job, t0 + budget, true) then
			job.running = false
		end
		syncLeft = syncLeft - (debugprofilestop() - t0)
	end
end

local function Drive()
	inPass, inRow = false, false   -- a handler that raised left them set
	local now = GetTime()
	Batch()
	local deadline = debugprofilestop() + SLICE_MS
	local more = false
	-- the rows filled in an earlier frame, laid out now (where the kit's
	-- plates lie measured since, in the slice)
	while rowHead <= rowTail do
		local at = rowAt[rowHead]
		if at >= now or debugprofilestop() >= deadline then
			more = true
			break
		end
		if not BuildPlates(deadline, at, true) then
			more = true
			break
		end
		local frame, def = rowFrame[rowHead], rowDef[rowHead]
		rowFrame[rowHead], rowDef[rowHead] = nil, nil
		rowHead = rowHead + 1
		rowQueued[frame] = nil
		if def.active then
			inRow = true
			WalkRow(def, frame, 0)
			inRow = false
		end
	end
	if rowHead > rowTail then
		rowHead, rowTail = 1, 0
	end
	-- the settling passes of the surfaces whose roots showed
	for _, def in pairs(QI.surfaces) do
		local step = def.settleStep
		if step then
			local elapsed = now - def.settleFrom
			if elapsed >= SETTLE[step] then
				while step and elapsed >= SETTLE[step] do
					step = step < #SETTLE and step + 1 or nil
				end
				def.settleStep = step
				if def.active then
					-- from the top, what shows first (a pass under way began
					-- before the rows settled; the hidden roots still in it
					-- when it has them)
					local job = def.job
					StartPass(def, job and job.running and job.full or false)
				end
			end
			more = more or def.settleStep ~= nil
		end
	end
	-- the passes, while the slice lasts (one that runs long: the plates that
	-- show taken again now and then; one being measured goes on)
	if gridHave == gridWant and gridBegan and gridBegan < now - PLATE_AGE then
		for _, def in pairs(QI.surfaces) do
			if def.job and def.job.running then
				gridWant = gridWant + 1
				break
			end
		end
	end
	for _, def in pairs(QI.surfaces) do
		local job = def.job
		if job and job.running then
			if not def.active then
				StopPass(def)
			elseif debugprofilestop() < deadline then
				if RunJob(def, job, deadline) then
					job.running = false
				end
				more = more or job.running
			else
				more = true
			end
		end
	end
	if not more then
		driver:Hide()
	end
end
Perf.SetScript(driver, "OnUpdate", Drive)

local ticker = nil
local function Tick()
	local any = false
	for name, def in pairs(QI.surfaces) do
		if def.active then
			any = true
			QI.RefreshSurface(name, true)
		end
	end
	if not any and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- Ink a surface's strings while it is on parchment, put them back when not.
-- `quiet`: the periodic pass (only shown roots; strings made since, inked),
-- run in slices by the driver; else a change (the hidden roots too), what
-- shows inked at once.
function QI.RefreshSurface(name, quiet)
	local def = QI.surfaces[name]
	if not def then
		return
	end
	local ok, on = pcall(def.on)
	on = ok and on and true or false
	local was = def.active
	def.active = on
	if on then
		if not quiet then
			StartPass(def, true)
			RunNow(def, true, not was)
		elseif not (def.job and def.job.running) then
			StartPass(def, false)
		end
		if not ticker and C_Timer and C_Timer.NewTicker then
			ticker = C_Timer.NewTicker(1, Tick)
		end
	elseif was or not quiet then
		StopPass(def)
		for fs in pairs(def.strings) do
			QI.PlainText(fs)
			def.strings[fs] = nil
		end
	end
	if def.onRefresh and (was ~= on or not quiet) then
		pcall(def.onRefresh, on)
	end
end

function QI.Surface(name, def)
	def.name = name
	def.skip = def.skip or QI.DefaultSkip
	def.roots = def.roots or function() return nil end
	def.strings = setmetatable({}, WEAK)
	QI.surfaces[name] = def
	QI.RefreshSurface(name)
	return def
end

-- a parchment sheet switched on or off: its surface follows (the bus's
-- 'parchment', fired once the kit's sheets are switched, where the hook on
-- Kit.SetParchment ran: audit 2026-09-24 rank 5)
MelloUI:On("parchment", Shared("'parchment' on the bus", function(area)
	if QI.surfaces[area] then
		QI.RefreshSurface(area)
	end
end), QI)

--------------------------------------------------------------------------------
-- /inkwhy: the strings under the mouse on the ink surfaces, and why each is
-- inked or left alone (its parents, the kit plates beside it). Opens the copy
-- window.
--------------------------------------------------------------------------------
SLASH_MELLOINKWHY1 = "/inkwhy"
SlashCmdList.MELLOINKWHY = function()
	MelloUI:ClearLog()
	Batch(true)
	WantPlates(nil)   -- everything measured as it is now
	local seen = 0
	for name, def in pairs(QI.surfaces) do
		local ok, on = pcall(def.on)
		MelloUI:Print("surface %s: on=%s active=%s", name, tostring(ok and on), tostring(def.active))
		for _, root in ipairs({ def.roots() }) do
			if root and root.GetRegions and root:IsVisible() then
				Walk(root, 0, function(fs)
					local okM, over = pcall(fs.IsMouseOver, fs)
					if okM and over and fs:IsVisible() then
						seen = seen + 1
						local okT, text = pcall(fs.GetText, fs)
						local r, g, b = fs:GetTextColor()
						MelloUI:Print("  %q recorded=%s ink=%s role=%s colour=%.2f,%.2f,%.2f skip=%s default=%s",
							tostring(okT and text or "?"):sub(1, 40), tostring(def.strings[fs] or false), tostring(fs.melloInk or false),
							tostring(fs.melloInkRole), r, g, b, tostring(def.skip and def.skip(fs)), tostring(QI.DefaultSkip(fs)))
						local plate = OverPlate(fs)
						MelloUI:Print("    over plate: %s", plate and (tostring(rawget(plate, "base")) .. " " .. tostring(plate:GetDebugName())) or "none")
						-- every kit replacement under it, whatever its kind
						local Kit = MelloUI.Kit
						for _, rep in ipairs(Kit and Kit.repList or {}) do
							local obj = rep.object
							if obj and obj.IsVisible and obj:IsVisible() and Inside(fs, obj) then
								local body = rep.skin and rep.skin.body
								MelloUI:Print("    kit %s key=%s base=%s body=%s obj=%s level=%s", tostring(rep.kind), tostring(rep.key),
									tostring((rep.strip and rep.strip.base) or (rep.rule and (rep.rule.base or rep.rule.piece or rep.rule.prefix))),
									tostring(body and body:IsShown() or false), tostring(obj.GetDebugName and obj:GetDebugName()),
									tostring(obj.GetFrameLevel and obj:GetFrameLevel()))
							end
						end
						-- and every shown texture of its frames under it (the game's own art)
						local up = fs:GetParent()
						for depth = 1, 5 do
							if not up then
								break
							end
							for _, region in ipairs({ up:GetRegions() }) do
								if region.GetObjectType and region:GetObjectType() == "Texture" and region:IsShown() and (region:GetAlpha() or 0) > 0.05 and Inside(fs, region) then
									local okA, atlas = pcall(region.GetAtlas, region)
									local okX, tex = pcall(region.GetTexture, region)
									MelloUI:Print("    texture d%d %s atlas=%s tex=%s kit=%s alpha=%.2f", depth, tostring(region:GetDebugName()),
										tostring(okA and atlas), tostring(okX and tex), tostring(region.kitName), region:GetAlpha() or 0)
								end
							end
							up = up.GetParent and up:GetParent()
						end
						local f = fs:GetParent()
						for depth = 1, 4 do
							if not f then
								break
							end
							MelloUI:Print("    parent%d %s %s shown=%s rep=%s", depth, f:GetObjectType(), tostring(f:GetName() or f:GetDebugName()),
								tostring(f:IsShown()), tostring(rawget(f, "melloRep") ~= nil))
							for _, child in ipairs({ f:GetChildren() }) do
								if rawget(child, "base") then
									MelloUI:Print("      strip %s shown=%s inside=%s", tostring(rawget(child, "base")), tostring(child:IsShown()), tostring(Inside(fs, child)))
								end
							end
							for _, region in ipairs({ f:GetRegions() }) do
								if region.kitName then
									MelloUI:Print("      kit texture %s shown=%s inside=%s", tostring(region.kitName), tostring(region:IsShown()), tostring(Inside(fs, region)))
								end
							end
							f = f.GetParent and f:GetParent()
						end
					end
				end)
			end
		end
	end
	MelloUI:Print("%d string(s) under the mouse.", seen)
	MelloUI:ShowLog("inkwhy")
end
