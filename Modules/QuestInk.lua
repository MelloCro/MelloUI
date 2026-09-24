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

function QI.InkCodes(text, sheet)
	if type(text) ~= "string" or not text:find("|c", 1, true) then
		return text
	end
	text = text:gsub("|c(%x%x)(%x%x)(%x%x)(%x%x)", function(a, rh, gh, bh)
		return Code(tonumber(rh, 16) / 255, tonumber(gh, 16) / 255, tonumber(bh, 16) / 255, a, sheet)
	end)
	-- a named colour (|cnHIGHLIGHT_FONT_COLOR:...|r, this client's newer form;
	-- user, 2026-09-23: the PvP tab's numbers stayed white): its colour inked
	text = text:gsub("|cn([%w_]+):", function(name)
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
	end)
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
		if ok and v ~= nil and not (issecretvalue and issecretvalue(v)) then
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
	f:SetScript("OnEnter", function(self)
		if self.tier then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(QI.TIER_NAME[self.tier] .. " (" .. self.tier .. " of 5)", 1, 1, 1)
			GameTooltip:AddLine("How hard the quest is for your level.", 0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end
	end)
	f:SetScript("OnLeave", function()
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
	local c = QI.INK[role] or QI.INK.title
	return c[1], c[2], c[3]
end

-- The colour the game (or its template) last gave fs, not our ink. While fs
-- is inked, a colour the game gives it later (the quest log recolours a
-- title and its objectives on hover and on leave -- user, 2026-09-23: the
-- difficulty colours came back) is inked over at once; `roleOf(r, g, b)`,
-- when given, picks the ink from the game's colour (a done objective faded).
function QI.WatchColour(fs, roleOf)
	if not fs then
		return
	end
	fs.melloInkRoleOf = roleOf or fs.melloInkRoleOf
	if fs.melloColourWatched then
		return
	end
	fs.melloColourWatched = true
	local r0, g0, b0 = fs:GetTextColor()
	fs.melloGameColour = { r0, g0, b0 }
	hooksecurefunc(fs, "SetTextColor", function(self, cr, cg, cb)
		if QI.inking then
			return
		end
		self.melloGameColour = { cr, cg, cb }
		if self.melloInk then
			local role = self.melloInkRoleOf and self.melloInkRoleOf(cr, cg, cb) or self.melloInkRole
			self.melloInkRole = role
			local r, g, b = QI.RoleColour(role, cr, cg, cb, QI.onSheet[self])
			QI.inking = true
			self:SetTextColor(r, g, b)
			QI.inking = false
		end
	end)
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

local function WatchText(fs)
	if fs.melloTextWatched then
		return
	end
	fs.melloTextWatched = true
	hooksecurefunc(fs, "SetText", function(self)
		if not QI.texting then
			self.melloPlainText = nil
			InkTextCodes(self)
		end
	end)
	if fs.SetFormattedText then
		hooksecurefunc(fs, "SetFormattedText", function(self)
			if not QI.texting then
				self.melloPlainText = nil
				InkTextCodes(self)
			end
		end)
	end	-- a font object set again brings its colour and outline back: ink again
	if fs.SetFontObject then
		hooksecurefunc(fs, "SetFontObject", function(self)
			if self.melloInk then
				local r, g, b = self:GetTextColor()
				self.melloGameColour = { r, g, b }
				QI.Ink(self, self.melloInkRole)
			end
		end)
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

local passPlates, VisiblePlates -- below (the kit's plates shown now, a pass's)
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
-- `quiet`: the periodic pass (only shown roots; strings made since, inked).
-- One frame's strings inked or put back by the surface's rules
local function WalkInk(def, frame)
	Walk(frame, 0, function(fs)
		local skip = false
		if def.skip then
			skip = def.skip(fs)
			if skip == nil then
				return   -- cannot tell yet: as it is, the next pass decides
			end
		end
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
			QI.InkText(fs)
		end
	end)
end

-- A scrolling list among a surface's frames: each row inked the moment the
-- list fills it (user, 2026-09-23: scrolling the stats showed their game
-- colours until the next pass)
local function HookRows(name, root)
	local box = (root.ForEachFrame and root) or (root.ScrollBox and root.ScrollBox.ForEachFrame and root.ScrollBox) or nil
	if not (box and ScrollUtil and ScrollUtil.AddInitializedFrameCallback) or (box.melloInkRows and box.melloInkRows[name]) then
		return
	end
	box.melloInkRows = box.melloInkRows or {}
	box.melloInkRows[name] = true
	ScrollUtil.AddInitializedFrameCallback(box, function(_, frame)
		local def = QI.surfaces[name]
		if def and def.active and frame then
			passPlates = VisiblePlates()
			WalkInk(def, frame)
			passPlates = nil
		end
	end, QI, false)
end

function QI.RefreshSurface(name, quiet)
	local def = QI.surfaces[name]
	if not def then
		return
	end
	local ok, on = pcall(def.on)
	on = ok and on and true or false
	if on then
		passPlates = VisiblePlates()
		for _, root in ipairs({ def.roots() }) do
			if root and root.GetRegions and (not quiet or root:IsVisible()) then
				if root.HookScript and not (root.melloInkShown and root.melloInkShown[name]) then
					root.melloInkShown = root.melloInkShown or {}
					root.melloInkShown[name] = true
					-- once it shows, and again as its rows settle (a tab switched:
					-- the rows are laid out after it shows; a row seen before it
					-- settled could stand on the sheet for a moment -- user,
					-- 2026-09-23: the reputation names "sometimes" changed)
					root:HookScript("OnShow", function()
						QI.RefreshSurface(name)
						if C_Timer and C_Timer.After then
							C_Timer.After(0.05, function() QI.RefreshSurface(name, true) end)
							C_Timer.After(0.15, function() QI.RefreshSurface(name, true) end)
							C_Timer.After(0.3, function() QI.RefreshSurface(name, true) end)
						end
					end)
				end
				if def.roots and not def.noWalk then
					HookRows(name, root)
					WalkInk(def, root)
				end
			end
		end
		passPlates = nil
		if not ticker and C_Timer and C_Timer.NewTicker then
			ticker = C_Timer.NewTicker(1, Tick)
		end
	elseif def.active or not quiet then
		for fs in pairs(def.strings) do
			QI.PlainText(fs)
			def.strings[fs] = nil
		end
	end
	local changed = def.active ~= on
	def.active = on
	if def.onRefresh and (changed or not quiet) then
		pcall(def.onRefresh, on)
	end
end

-- The kit's replacement for a region (Kit.repList, kept by region)
local regionRep, repCount = setmetatable({}, { __mode = "k" }), 0
local function RepOf(region)
	local Kit = MelloUI.Kit
	local list = Kit and Kit.repList
	if not list then
		return nil
	end
	if #list ~= repCount then
		for i = repCount + 1, #list do
			local rep = list[i]
			if rep and rep.region then
				regionRep[rep.region] = rep
			end
		end
		repCount = #list
	end
	return regionRep[region]
end

-- a replacement that is a plate behind text (a header, a row's plate, a
-- bar's bracket, a slot); not a line (a divider) nor a picture or tile
local PLATE_KIND = { strip = true, frame = true, bar = true, slot = true }
-- a texture of the game's that is a plate (its atlas a kit rule's strip,
-- bar or frame), shown and solid
local GAME_PLATE_KIND = { strip = true, bar = true, frame = true }
local function GamePlate(region)
	if not (region.GetObjectType and region:GetObjectType() == "Texture") or region.kitName or not region:IsShown() then
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
	local base = (rep.strip and rep.strip.base) or (rep.rule and rep.rule.base) or ""
	return not base:find("divider", 1, true)
end

-- Whether fs's centre lies in frame f (their scales apart)
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

-- The kit's plates shown now, gathered once a pass (Kit.repList): the
-- strips (headers, row plates, a row's hover or selection), the bars'
-- brackets and the slot rims -- not the dividers (lines), nor the frames
-- (a window's frame lies under everything in it). A string over one keeps
-- its colours, however the plate was put there (user, 2026-09-23: the
-- stats' category plates belong to another frame than their names).
local GLOBAL_PLATE = { strip = true, bar = true, slot = true }
VisiblePlates = function()
	local list = {}
	local Kit = MelloUI.Kit
	for _, rep in ipairs(Kit and Kit.repList or {}) do
		local obj = rep.object
		if GLOBAL_PLATE[rep.kind] and obj and obj.IsVisible and obj:IsVisible() then
			local base = (rep.strip and rep.strip.base) or (rep.rule and rep.rule.base) or ""
			if not base:find("divider", 1, true) then
				list[#list + 1] = obj
			end
		end
	end
	return list
end

local function OverPlate(fs)
	for _, obj in ipairs(passPlates or VisiblePlates()) do
		if Inside(fs, obj) then
			return obj
		end
	end
	return nil
end
QI.OverPlate = OverPlate

-- The strings a surface leaves as they are: on a bar (a reputation, a
-- skill), on a kit plate that is showing (a header, a selected row), over an
-- icon (a count), or under a frame marked melloNoInk
function QI.DefaultSkip(fs)
	if OverPlate(fs) then
		return true
	end
	local f = fs:GetParent()
	for depth = 1, 4 do
		if not f then
			return false
		end
		if f.melloNoInk then
			return true
		end
		-- a painted plate of the kit (a Kit:Strip: a header, a row's hover or
		-- selection, a bar's bracket) shown behind it, however it was put
		-- there (user, 2026-09-23: the stats' category names on their dark
		-- plates were inked)
		for _, child in ipairs({ f:GetChildren() }) do
			local base = rawget(child, "base")
			if base and rawget(child, "mid") and child:IsShown() and not tostring(base):find("divider", 1, true) then
				local inside = Inside(fs, child)
				if inside == nil then
					return nil   -- not laid out yet: undecided
				elseif inside then
					return true
				end
			end
		end
		-- the row's own art replaced by a kit plate drawn elsewhere (the stats'
		-- category headers: their Background, the plate on another frame)
		-- (the row and its parent only: further up a whole box's stone frame
		-- would count as a plate under everything in it)
		for _, region in ipairs(depth <= 2 and { f:GetRegions() } or {}) do
			local rep = RepOf(region)
			if IsPlate(rep) and rep.object and rep.object.IsShown and rep.object:IsShown() then
				local inside = Inside(fs, rep.object)
				if inside == nil then
					return nil   -- not laid out yet: undecided
				elseif inside then
					return true
				end
			end
			-- the game's own plate art, not reskinned (a pooled row made after
			-- the reskin: the PvP tab's "Next Rewards" header, user 2026-09-23):
			-- a shown texture whose atlas the kit knows as a plate
			if GamePlate(region) then
				local inside = Inside(fs, region)
				if inside == nil then
					return nil   -- not laid out yet: undecided
				elseif inside then
					return true
				end
			end
		end
		local kind = f.GetObjectType and f:GetObjectType()
		if kind == "StatusBar" and f:IsShown() then
			-- only the text over the bar (a rank, a standing); a name beside it
			-- on the paper, though the bar's child, is inked (user, 2026-09-23)
			local okF, fx, fy = pcall(fs.GetCenter, fs)
			local okB, l, b, w, h = pcall(f.GetRect, f)
			if not (okF and okB and fx and l and w) or (issecretvalue and (issecretvalue(fx) or issecretvalue(l))) then
				return nil   -- not laid out yet: undecided
			end
			local k = fs:GetEffectiveScale() / f:GetEffectiveScale()
			fx, fy = fx * k, fy * k
			if fx >= l and fx <= l + w and fy >= b and fy <= b + h then
				return true
			end
		end
		for _, key in ipairs({ "melloRep", "melloHeader", "melloPlate" }) do
			local rep = rawget(f, key)
			local obj = type(rep) == "table" and rep.object
			if obj and obj.IsShown and obj:IsShown() then
				return true
			end
		end
		for _, key in ipairs({ "icon", "Icon" }) do
			local tex = rawget(f, key)
			if type(tex) == "table" and tex.IsShown and tex.GetObjectType and tex:GetObjectType() == "Texture" and tex:IsShown() then
				return true
			end
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
function QI.OnSheet(fs, area)
	local Kit = MelloUI.Kit
	local list = Kit and Kit.parchmentSheets and Kit.parchmentSheets[area]
	if not list then
		return false
	end
	local okF, fx, fy = pcall(fs.GetCenter, fs)
	if not (okF and fx and fy) or (issecretvalue and (issecretvalue(fx) or issecretvalue(fy))) then
		return nil
	end
	local anyShown = false
	for _, entry in ipairs(list) do
		if entry.sheet and entry.sheet:IsVisible() then
			anyShown = true
		end
	end
	if not anyShown then
		return nil
	end
	local fe = fs:GetEffectiveScale()
	for _, entry in ipairs(list) do
		local sheet = entry.sheet
		if sheet and sheet:IsVisible() then
			local okR, l, b, w, h = pcall(sheet.GetRect, sheet)
			if okR and l and w and not (issecretvalue and issecretvalue(l)) then
				local k = fe / sheet:GetEffectiveScale()
				local x, y = fx * k, fy * k
				if x >= l and x <= l + w and y >= b and y <= b + h then
					return true
				end
			end
		end
	end
	return false
end

function QI.Surface(name, def)
	def.name = name
	def.skip = def.skip or QI.DefaultSkip
	def.roots = def.roots or function() return nil end
	def.strings = setmetatable({}, { __mode = "k" })
	QI.surfaces[name] = def
	QI.RefreshSurface(name)
	return def
end

-- a parchment sheet switched on or off: its surface follows
function QI.HookParchment()
	local Kit = MelloUI.Kit
	if Kit and Kit.SetParchment and not QI.parchmentHooked then
		QI.parchmentHooked = true
		hooksecurefunc(Kit, "SetParchment", function(_, area)
			if QI.surfaces[area] then
				QI.RefreshSurface(area)
			end
		end)
	end
end
QI.HookParchment()

--------------------------------------------------------------------------------
-- /inkwhy: the strings under the mouse on the ink surfaces, and why each is
-- inked or left alone (its parents, the kit plates beside it). Opens the copy
-- window.
--------------------------------------------------------------------------------
SLASH_MELLOINKWHY1 = "/inkwhy"
SlashCmdList.MELLOINKWHY = function()
	MelloUI:ClearLog()
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
