--------------------------------------------------------------------------------
-- MelloUI - Tooltip Panel
--
-- Every tooltip built on SharedTooltipTemplate (GameTooltip, ItemRefTooltip,
-- the shopping / comparison tooltips, embedded item tooltips ...) dressed in
-- the painted kit (Modules/Kit.lua) on the game's own layout, by the user's
-- pick (kit_raw/tooltip_catalog.png, 2026-09-21):
--   TT1: the tooltip's NineSlice (the TooltipDefaultLayout pieces, and
--   whatever layout the game swaps in) -> the single rail with the list-box
--   stone, as REGIONS of the NineSlice in its own layers; the texts, item
--   icons and comparison headers stay the game's.
--   The unit health bar under a unit tooltip (GameTooltipStatusBar, a
--   StatusBar with no border art of its own): the P1 bracket around it with
--   the caps outside, the bar set in by the arms — an agreed addition, as the
--   catalogue showed it.
--   The parchment (user, 2026-09-24: "Tooltip Parchment Option"; UI
--   Modifications' parchment_tooltip, off by default): a sheet on the stone
--   inside the rail of every dressed tooltip, its lines in dark ink while it
--   shows (the parchment ink rule, Modules/QuestInk.lua). Names on it (an
--   item's, a player's) with a gem in the game's true colour before them
--   (the quality, the class), in the title ink where they show that colour
--   (user, 2026-09-26: "ink plus gems").
--   Without the parchment, the stone inside the rail lies under the palette's
--   inner panel (user, 2026-09-24: the eye strain rule, WINDOW-RULES 2e).
-- Tooltips are styled by the game on every show (SharedTooltip_SetBackdropStyle):
-- that call is the hook that catches every tooltip the first time.
-- Covers the group "tooltip": the Tooltip tweak module's backdrop colouring
-- acts only while this module is off. /ttdump [frames|reps].
--
-- Taint: the game's secure code reads and fills these tooltips, so nothing is
-- ever written onto a tooltip, its NineSlice, its bar or its font strings (no
-- fields, no SetScript, no method replaced). What this file remembers about
-- them lives in side tables keyed by the frame; it follows them through
-- HookScript, hooksecurefunc on global functions and the tooltip data post-
-- calls -- and one secure post-hook on Show of the game's own tooltips (the
-- KNOWN list: lines refilled in place, with no event of their own, are inked
-- in the call that coloured them; user, 2026-09-24, the flicker). A
-- hooksecurefunc keeps Show secure for the game's callers; the handler runs
-- after it, and nothing else is written. A name's gem is a frame of ours on
-- the tooltip (made the first time a parchment tooltip shows a name), hidden
-- through a HookScript on its OnTooltipCleared.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("TooltipPanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
-- one handler for every object it is hooked on, wrapped once
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("TooltipPanel", {
	title = "Tooltip Kit",
	desc = "Tooltips dressed in the painted kit: the stone box with the single rail, the unit health bar in the bracket.",
	window = { label = "Tooltips", desc = "Tooltips on the stone box with the single rail.", tab = "HUD" },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil
local active = false

-- The side tables (weak keys: a tooltip made by someone else and dropped
-- takes its entries with it)
local dressed = setmetatable({}, { __mode = "k" })   -- [tooltip] = true once SkinTooltip saw it
local insets = setmetatable({}, { __mode = "k" })    -- [health bar] = the game's anchors while the bracket sets it in
local sheets = setmetatable({}, { __mode = "k" })    -- [tooltip] = its parchment sheet
local dims = setmetatable({}, { __mode = "k" })      -- [tooltip] = its eye-strain panel (the stone look's)

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Tooltip: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

local PIECES = { "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }

-- The health bar set in from its anchors by the bracket's arms (a
-- StatusBar's fill cannot be re-anchored): once per game layout.
local function InsetBar(bar, rep)
	if not (bar and rep and rep.GetArms) or insets[bar] then
		return
	end
	local okN, n = pcall(bar.GetNumPoints, bar)
	if not okN or Secret(n) or not n then
		return
	end
	local points = {}
	for i = 1, n do
		local ok, point, rel, relPoint, x, y = pcall(bar.GetPoint, bar, i)
		if not ok or Secret(point) or Secret(x) or Secret(y) or not point then
			return
		end
		points[i] = { point, rel, relPoint, x or 0, y or 0 }
	end
	insets[bar] = points
	local armL, armR = rep:GetArms()
	bar:ClearAllPoints()
	for _, pt in ipairs(points) do
		local point, rel, relPoint, x, y = unpack(pt)
		if point:find("LEFT") then
			x = x + armL
		elseif point:find("RIGHT") then
			x = x - armR
		end
		bar:SetPoint(point, rel, relPoint, x, y)
	end
end

local function RestoreBar(bar)
	local points = bar and insets[bar]
	if not points then
		return
	end
	insets[bar] = nil
	bar:ClearAllPoints()
	for _, pt in ipairs(points) do
		bar:SetPoint(unpack(pt))
	end
end

--------------------------------------------------------------------------------
-- Parchment (user, 2026-09-24: "Tooltip Parchment Option"). A sheet of the
-- kit's one parchment on the stone, inside the rail, its edge in the fine
-- brush strokes; and the tooltip's lines in dark ink on it by the parchment
-- ink rule (Modules/QuestInk.lua): neutral text the body ink, a white or gold
-- header the title ink, grey the faded ink, a colour that means something
-- (an item's quality, the red of a requirement not met, the green of a use or
-- a set bonus, a class or reputation colour) a dark shade of its own hue; no
-- outline and no shadow on inked text. The money lines and the health bar
-- keep their colours (their strings are not the tooltip's lines). Switched
-- off, every line has the colour the game last gave it back at once.
--------------------------------------------------------------------------------

-- The sheet's margin in from the rail's middle: none. A tooltip's text runs
-- about 10 units in from its edge; the rail ends 6.6 units in and the fine
-- strokes are about 6 deep, so the sheet starting under the rail's middle
-- (3.9 in) is solid paper by the first letter; any margin more would put the
-- strokes under the text's first letters.
local SHEET_MARGIN = 0
-- the sweep that catches a colour the game gave a line without any call this
-- file hears (a line recoloured in place): seconds between passes while an
-- inked tooltip shows
local POLL = 0.2

local QI = MelloUI.QuestInk
local lineState = setmetatable({}, { __mode = "k" })   -- [font string] = what its ink replaced (below)
local headers = setmetatable({}, { __mode = "k" })     -- [frame] = its header line (TextLeft1), once found; false: none
local pending = {}                                     -- [tooltip] = true: ink again on the next frame
local inking = false                                   -- our own SetTextColor / SetText / SetFont at work
local flushing, sweeping = false, false                -- the next-frame pass / the sweep armed
-- the gems on names (below)
local gems = setmetatable({}, { __mode = "k" })        -- [tooltip] = its gem (QI.Gem), made when a name first needs one
local notes = setmetatable({}, { __mode = "k" })       -- [tooltip] = what its data last showed (NoteKind; one table per tooltip)
local prelayout = false                                -- the pass runs in a data post-call: the game lays the tooltip out after it

local function InkOn()
	return active and QI ~= nil and Kit.ParchmentOn ~= nil and Kit:ParchmentOn("tooltip")
end

-- The same colour, as read back from the string (the client keeps a colour
-- to its own precision; the ink is stored as read back, so a match is exact
-- in all but rounding)
local function Same(c, r, g, b)
	return c and math.abs(c[1] - r) < 0.002 and math.abs(c[2] - g) < 0.002 and math.abs(c[3] - b) < 0.002
end

-- The line's own outline and shadow back (the colour is left alone)
local function RestoreLook(fs, state)
	if state.flags and state.flags ~= "" then
		local ok, path, size, flags = pcall(fs.GetFont, fs)
		if ok and path and size and (flags == nil or flags == "") then
			pcall(fs.SetFont, fs, path, size, state.flags)
		end
	end
	local sh = state.shadow
	if sh then
		local _, _, _, sa = fs:GetShadowColor()
		if not Secret(sa) and sa ~= nil and sa == 0 then
			fs:SetShadowColor(sh[1], sh[2], sh[3], sh[4])
		end
	end
end

--------------------------------------------------------------------------------
-- Names and their gems (user, 2026-09-26, RC4: on the parchment the dark
-- shades of an item's quality and a class colour all read as one brown;
-- option B, "ink plus gems"). A tooltip's name line -- its first line -- has
-- a gem before it (QI.Gem) in the game's own colour:
--   an item (or a toy) named in its quality colour: that colour, and the
--     name in the title ink;
--   a player: its class's colour, read from its GUID (GetPlayerInfoByGUID,
--     RAID_CLASS_COLORS), never guessed from the name's colour (the Priest's
--     is plain white, as is the game's name of a hostile player one cannot
--     attack). The name in the title ink where it shows that class colour
--     (the Tooltip tweak's Class Coloured Names, on by default), else the
--     ink of the reaction colour the game gave it (a unit frame's tooltip,
--     Class Coloured Names off): the class told by the gem, the reaction by
--     the name;
--   a unit whose GUID the client hid: a class colour its name shows (never
--     plain white), in that colour.
-- An NPC's name keeps the ink of its reaction colour and has no gem. Every
-- other coloured line keeps its inked shade.
-- The text makes room: an invisible lead as wide as the gem before the
-- game's text (QI.GemLead), in the copy the ink writes anyway, put in by the
-- data's post-calls -- before the game's Show lays the tooltip out, so its
-- width counts the lead (nothing of ours calls Show). The gem, one per
-- tooltip, is anchored to the name's string.
--------------------------------------------------------------------------------

-- The header line of a tooltip (its TextLeft1)
local function HeaderOf(frame)
	local header = headers[frame]
	if header == nil then
		local okN, name = pcall(frame.GetName, frame)
		header = okN and type(name) == "string" and _G[name .. "TextLeft1"] or false
		headers[frame] = header
	end
	return header or nil
end

-- A colour as read back from a string (the client's precision) against the
-- game's
local function Near(r, g, b, cr, cg, cb)
	return math.abs(r - cr) < 0.006 and math.abs(g - cg) < 0.006 and math.abs(b - cb) < 0.006
end

-- the item qualities' colours, r, g, b in a row, read from the game once
local qualityColours = nil

local function IsQuality(r, g, b)
	local list = qualityColours
	if not list then
		list = {}
		for q = 0, 8 do
			local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
			local ok, cr, cg, cb = false, nil, nil, nil
			if type(c) == "table" then
				ok, cr, cg, cb = true, c.r, c.g, c.b
			elseif C_Item and C_Item.GetItemQualityColor then
				ok, cr, cg, cb = pcall(C_Item.GetItemQualityColor, q)
			end
			if ok and not (Secret(cr) or Secret(cg) or Secret(cb))
				and type(cr) == "number" and type(cg) == "number" and type(cb) == "number" then
				local n = #list
				list[n + 1], list[n + 2], list[n + 3] = cr, cg, cb
			end
		end
		qualityColours = list
	end
	for i = 1, #list, 3 do
		if Near(r, g, b, list[i], list[i + 1], list[i + 2]) then
			return true
		end
	end
	return false
end

-- a class's colour (the game's table, read as it is: nothing made); never
-- plain white, the Priest's and the game's own for other names
local function IsClassColour(r, g, b)
	local list = RAID_CLASS_COLORS
	if type(list) ~= "table" or (r > 0.99 and g > 0.99 and b > 0.99) then
		return false
	end
	for _, c in pairs(list) do
		if type(c) == "table" then
			local cr, cg, cb = c.r, c.g, c.b
			if not (Secret(cr) or Secret(cg) or Secret(cb)) and type(cr) == "number" and type(cg) == "number"
				and type(cb) == "number" and Near(r, g, b, cr, cg, cb) then
				return true
			end
		end
	end
	return false
end

-- What a tooltip's data is, from its post-call: "item", "player" (and its
-- GUID), "npc", "unit" (its GUID secret) or false
local dataKinds = nil   -- [Enum.TooltipDataType value] = "item" / "unit", read once

local function KindOf(data)
	if Secret(data) or type(data) ~= "table" then
		return false, nil
	end
	local t = data.type
	if Secret(t) or t == nil then
		return false, nil
	end
	local map = dataKinds
	if not map then
		map = {}
		local types = Enum and Enum.TooltipDataType
		if type(types) == "table" then
			if types.Item ~= nil then
				map[types.Item] = "item"
			end
			if types.Toy ~= nil then
				map[types.Toy] = "item"
			end
			if types.Unit ~= nil then
				map[types.Unit] = "unit"
			end
		end
		dataKinds = map
	end
	local kind = map[t] or false
	if kind == "unit" then
		local guid = data.guid
		if not Secret(guid) and type(guid) == "string" then
			if guid:find("^Player%-") then
				return "player", guid
			end
			return "npc", nil
		end
	end
	return kind, nil
end

-- A player's class colour, from its GUID (the game's own table), kept in
-- the tooltip's note for as long as the same player shows
local function NoteClass(note, guid)
	if note.guid == guid and note.cr then
		return
	end
	note.guid, note.cr, note.cg, note.cb = guid, false, false, false
	if type(GetPlayerInfoByGUID) ~= "function" then
		return
	end
	local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
	if not ok or Secret(class) or type(class) ~= "string" then
		return
	end
	local list = RAID_CLASS_COLORS
	local c = type(list) == "table" and list[class]
	if type(c) ~= "table" then
		return
	end
	local cr, cg, cb = c.r, c.g, c.b
	if not (Secret(cr) or Secret(cg) or Secret(cb)) and type(cr) == "number" and type(cg) == "number"
		and type(cb) == "number" then
		note.cr, note.cg, note.cb = cr, cg, cb
	end
end

-- The data a post-call handed us, with the name line's text then: a line
-- refilled since without data (a tooltip built line by line) is not that
-- thing any more. One note per tooltip, made the first time the parchment
-- shows it filled, then written over (`false`: none)
local function NoteKind(tip, data)
	local note = notes[tip]
	if not note then
		note = { kind = false, text = false, guid = false, cr = false, cg = false, cb = false }
		notes[tip] = note
	end
	local kind, guid = KindOf(data)
	local text = false
	if kind then
		local fs = HeaderOf(tip)
		if fs then
			local ok, t = pcall(fs.GetText, fs)
			if ok and not Secret(t) and type(t) == "string" then
				local state = lineState[fs]
				if state and state.inkedText == t then
					t = state.text
				end
				text = t
			end
		end
	end
	note.kind, note.text = kind, text
	if guid then
		NoteClass(note, guid)
	end
end

-- The gem of the name line of `tip`, with the game's text `own` and colour
-- r, g, b: the gem's colour, and whether the name itself shows it (then it
-- is written in the title ink); nil: no gem
local function GemFor(tip, own, r, g, b)
	local note = notes[tip]
	local kind = note and note.kind
	if not kind or kind == "npc" or note.text ~= own then
		return nil
	end
	if kind == "item" then
		if IsQuality(r, g, b) then
			return r, g, b, true
		end
		return nil
	end
	-- a player whose class the game told: its gem whatever its name shows
	if kind == "player" and note.cr then
		local cr, cg, cb = note.cr, note.cg, note.cb
		return cr, cg, cb, Near(r, g, b, cr, cg, cb)
	end
	if IsClassColour(r, g, b) then
		return r, g, b, true
	end
	return nil
end

local function HideGem(tip)
	local gem = gems[tip]
	if gem and gem:IsShown() then
		gem:Hide()
	end
end

-- a tooltip cleared (the game fills it anew): its gem goes until the ink
-- says again, and what its data was is forgotten
local GemCleared = Shared("OnTooltipCleared on tooltips with a gem", function(tip)
	local note = notes[tip]
	if note then
		note.kind, note.text = false, false
	end
	HideGem(tip)
end)

-- The gem before a name: made once per tooltip (the first name it shows on
-- the parchment), then moved and tinted
local function ShowGem(tip, fs, size, drop, r, g, b)
	local gem = gems[tip]
	if not gem then
		gem = QI.Gem(tip, size)
		gems[tip] = gem
		local ok, has = pcall(tip.HasScript, tip, "OnTooltipCleared")
		if ok and has then
			Perf.HookScript(tip, "OnTooltipCleared", GemCleared)
		end
	end
	gem:SetGemSize(size)
	if gem.anchor ~= fs or gem.drop ~= drop then
		gem.anchor, gem.drop = fs, drop
		gem:ClearAllPoints()
		gem:SetPoint("TOPLEFT", fs, "TOPLEFT", 0, -drop)
	end
	gem:SetColour(r, g, b)
end

-- One line to its ink. State per string (a side table, never a field on the
-- game's string): `game` the colour the game gave it, `ink` our colour as
-- read back, `text` / `inkedText` the game's text and ours where its colour
-- codes were inked or a gem's lead put before it (`lead`; `codes` and
-- `leadText` the copies, kept with the text they were made from), `flags` /
-- `shadow` the outline and shadow the ink took off. The game refills and
-- recolours its lines on every show: a colour or text that is not ours any
-- more is the game's new one, inked afresh. `tip`: the tooltip whose name
-- line this is (a header line), for its gem.
local function InkLine(fs, header, tip)
	local state = lineState[fs]
	local r, g, b, a = fs:GetTextColor()
	local text = fs:GetText()
	-- a secret colour or text (a unit's line in combat): never compared or
	-- worked on; the line keeps what the game gave it (its text back where
	-- our copy still shows), with its own outline and shadow again if the
	-- ink had them, and no gem
	if Secret(r) or Secret(g) or Secret(b) or Secret(a) or Secret(text) then
		if state then
			lineState[fs] = nil
			if not Secret(text) and state.inkedText ~= nil and text == state.inkedText then
				inking = true
				fs:SetText(state.text)
				inking = false
			end
			RestoreLook(fs, state)
		end
		if tip then
			HideGem(tip)
		end
		return
	end
	if not state then
		state = {}
		lineState[fs] = state
	end
	-- (the colour tables are the string's own, filled again: a sweep over
	-- lines that did not change makes nothing)
	if not (state.game and Same(state.ink, r, g, b)) then
		local c = state.game
		if c then
			c[1], c[2], c[3] = r, g, b
		else
			state.game = { r, g, b }
		end
	end
	local gr, gg, gb = state.game[1], state.game[2], state.game[3]
	-- the game's own text (ours is the game's with its colour codes inked
	-- and a gem's lead before it)
	local own = text
	if type(text) == "string" and text == state.inkedText then
		own = state.text
	end
	-- the font: its size places a gem, its outline goes (below)
	local okF, path, size, flags = pcall(fs.GetFont, fs)
	if okF and (Secret(path) or Secret(size) or Secret(flags)) then
		okF = false
	end
	-- a name (an item's, a player's): a gem in the game's own colour before it
	local lead, gemSize, drop, er, eg, eb, titled
	if tip and okF and type(size) == "number" and size > 0 and type(own) == "string" then
		er, eg, eb, titled = GemFor(tip, own, gr, gg, gb)
		if er then
			lead, gemSize, drop = QI.GemLead(size)
			-- the lead goes in before the game lays the tooltip out (the data's
			-- post-calls), or stays where its layout counted it: one put in
			-- after the layout would run the name past the tooltip's edge, so
			-- that name keeps its inked shade and has no gem
			if not prelayout and not (lead == state.lead and text == state.inkedText) then
				lead, er, titled = nil, nil, nil
			end
		end
	end
	local ir, ig, ib
	local mx, mn = math.max(gr, gg, gb), math.min(gr, gg, gb)
	if (lead and titled) or (header and mx >= 0.8 and (mx - mn) / mx < 0.25) then
		-- a name in the colour its gem shows, or a white header (a spell's or
		-- an ability's name): the sheet's title ink, as the gold ones get
		local c = QI.SHEET_TITLE or QI.INK.title
		ir, ig, ib = c[1], c[2], c[3]
	else
		-- the tooltip's sheet is the kit's darker parchment: its own inks
		-- (4.5 : 1 there; user rule, readability first)
		ir, ig, ib = QI.InkOf(gr, gg, gb, true)
	end
	if not (state.ink and Same(state.ink, ir, ig, ib) and Same(state.ink, r, g, b)) then
		inking = true
		fs:SetTextColor(ir, ig, ib, a)
		inking = false
		local kr, kg, kb = fs:GetTextColor()
		local c = state.ink
		if c then
			c[1], c[2], c[3] = kr, kg, kb
		else
			state.ink = { kr, kg, kb }
		end
	end
	-- colour codes in the text (a name in its class colour, an added line's
	-- own colours) and a name's lead: in a copy, the game's text kept to put
	-- back
	if type(text) == "string" and (text ~= state.inkedText or lead ~= state.lead) then
		-- (each copy kept with the text it was made from: the game writing
		-- the same text again -- a tooltip refilled while it is hovered, a
		-- player's name losing and taking its lead on each refresh -- makes
		-- nothing)
		if own ~= state.codesOf then
			state.codesOf = own
			state.codes = own:find("|c", 1, true) and QI.InkCodes(own, true) or own
		end
		local inked = state.codes
		if lead then
			if state.leadOf ~= inked or state.leadWith ~= lead then
				state.leadOf, state.leadWith, state.leadText = inked, lead, lead .. inked
			end
			inked = state.leadText
		end
		state.lead = lead
		if inked ~= own then
			if inked ~= text then
				inking = true
				fs:SetText(inked)
				inking = false
			end
			state.text, state.inkedText = own, inked
		else
			if own ~= text then
				inking = true
				fs:SetText(own)
				inking = false
			end
			state.text, state.inkedText = nil, nil
		end
	end
	-- no outline and no shadow (a black edge round dark ink smudges it); what
	-- the game (or a font object set since) gave it kept to put back
	if okF and path and size and flags and flags ~= "" then
		state.flags = flags
		inking = true
		pcall(fs.SetFont, fs, path, size, "")
		inking = false
	end
	local sr, sg, sb, sa = fs:GetShadowColor()
	if not Secret(sa) and sa ~= nil and sa > 0 then
		local sh = state.shadow
		if sh then
			sh[1], sh[2], sh[3], sh[4] = sr, sg, sb, sa
		else
			state.shadow = { sr, sg, sb, sa }
		end
		fs:SetShadowColor(0, 0, 0, 0)
	end
	-- the name's gem in the game's own colour (never the ink); any other
	-- first line has none
	if tip then
		if lead then
			ShowGem(tip, fs, gemSize, drop, er, eg, eb)
		else
			HideGem(tip)
		end
	end
end

-- One line back: the game's colour where our ink still shows (a colour the
-- game gave it since is its own and stays), the game's text where ours still
-- shows, its outline and shadow
local function PlainLine(fs, state)
	local r, g, b, a = fs:GetTextColor()
	if state.game and not (Secret(r) or Secret(g) or Secret(b)) and Same(state.ink, r, g, b) then
		inking = true
		fs:SetTextColor(state.game[1], state.game[2], state.game[3], (not Secret(a)) and a or nil)
		inking = false
	end
	if state.inkedText then
		local text = fs:GetText()
		if not Secret(text) and text == state.inkedText then
			inking = true
			fs:SetText(state.text)
			inking = false
		end
	end
	RestoreLook(fs, state)
end

-- The walk's lists: a frame's regions, its children, a holder's children,
-- each kept and filled again (one per depth where the walk nests), so a
-- sweep makes no garbage (user, 2026-09-24 /melloperf: garbage is stutter)
local regionList = {}
local childLists, subLists = {}, {}

local function Fill(list, ...)
	local n = select("#", ...)
	for i = 1, n do
		list[i] = (select(i, ...))
	end
	return n
end

local function ListAt(lists, depth)
	local list = lists[depth]
	if not list then
		list = {}
		lists[depth] = list
	end
	return list
end

-- The strings of one frame that are its lines (a tooltip's regions: its
-- TextLeftN / TextRightN, made as the game needs them; a friends tooltip's
-- labels)
local function InkLines(frame)
	local header = HeaderOf(frame)
	local n = Fill(regionList, frame:GetRegions())
	for i = 1, n do
		local region = regionList[i]
		regionList[i] = nil
		if region.GetObjectType and region:GetObjectType() == "FontString" and region:IsShown() then
			local isHeader = region == header
			local ok = pcall(InkLine, region, isHeader, isHeader and frame or nil)
			if not ok then
				inking = false
			end
		end
	end
end

-- A tooltip's lines, and those of the tooltips inside it (an embedded item's
-- tooltip lies on the same sheet). Other children are left: the money frames
-- (their amounts keep their colours), the health bar and its text, a
-- comparison header on its own plate, and the kit's own frames.
local function InkTooltip(tip, depth)
	depth = depth or 0
	InkLines(tip)
	if depth >= 3 then
		return
	end
	local children = ListAt(childLists, depth)
	local n = Fill(children, tip:GetChildren())
	for i = 1, n do
		local child = children[i]
		children[i] = nil
		local kind = child.GetObjectType and child:GetObjectType()
		if child:IsShown() then
			if kind == "GameTooltip" then
				InkTooltip(child, depth + 1)
			elseif kind == "Frame" then
				-- a holder of tooltips (the embedded item's frame): only the
				-- tooltips under it, never its own strings (the item's count)
				local subs = ListAt(subLists, depth)
				local m = Fill(subs, child:GetChildren())
				for j = 1, m do
					local sub = subs[j]
					subs[j] = nil
					if sub.GetObjectType and sub:GetObjectType() == "GameTooltip" and sub:IsShown() then
						InkTooltip(sub, depth + 2)
					end
				end
			end
		end
	end
end
MelloUI:Profile("TooltipPanel", "tooltip ink", InkTooltip)

-- The dressed tooltip whose sheet a tooltip lies on (itself, or the tooltip
-- an embedded one is part of). The post-calls hand us every tooltip the game
-- fills, a forbidden one among them (the store's, the secure ones): only the
-- side table is looked at before its methods, and they are called guarded.
local function ParentOf(f)
	return f:GetParent()
end

local function SheetOwner(tip)
	local f = tip
	for _ = 1, 4 do
		if not f then
			return nil
		end
		if sheets[f] then
			return f
		end
		local ok, parent = pcall(ParentOf, f)
		f = ok and parent or nil
	end
	return nil
end

-- The driver, two timers rather than a script on every frame: the tooltips
-- an event named inked again on the next frame (the game or another handler
-- may colour a line after the call that told us), and every inked tooltip
-- that shows swept every POLL seconds; the sweep ends when no inked tooltip
-- shows, and the next event on one starts it again.
-- a walk guarded: it runs on every Show of the game's tooltips and from the
-- timers, in combat too (one strange child raising would do so on every
-- hover, twice a second)
local function SafeInk(tip)
	if not pcall(InkTooltip, tip) then
		inking = false
	end
end

local function Flush()
	flushing = false
	if not InkOn() then
		wipe(pending)
		return
	end
	for tip in pairs(pending) do
		pending[tip] = nil
		if tip:IsVisible() then
			SafeInk(tip)
		end
	end
end

local function Sweep()
	sweeping = false
	if not InkOn() then
		return
	end
	local any = false
	for tip, sheet in pairs(sheets) do
		if sheet:IsShown() and tip:IsVisible() then
			any = true
			SafeInk(tip)
		end
	end
	if any then
		sweeping = true
		C_Timer.After(POLL, Sweep)
	end
end

-- An event on a tooltip: ink it now and once more on the next frame
-- (`walk` false: only the next frame's -- the caller inked what changed)
local function Touch(tip, walk)
	if inking or not InkOn() then
		return
	end
	local owner = SheetOwner(tip)
	if not (owner and owner:IsVisible()) then
		return
	end
	if walk ~= false then
		SafeInk(owner)
	end
	pending[owner] = true
	if not flushing then
		flushing = true
		C_Timer.After(0, Flush)
	end
	if not sweeping then
		sweeping = true
		C_Timer.After(POLL, Sweep)
	end
end

-- A tooltip the game has just filled from its data (a post-call): its name
-- line inked at once, its gem's lead in before the game's Show lays it out.
-- The tooltip may not show yet (a fresh hover is filled while it is hidden,
-- and Touch waits for its Show), so the name is not left to the walk.
local function InkName(tip)
	local fs = HeaderOf(tip)
	if fs and fs:IsShown() then
		prelayout = true
		if not pcall(InkLine, fs, true, tip) then
			inking = false
		end
		prelayout = false
	end
end

local function DataPostCall(tip, data)
	if tip and not inking and InkOn() and SheetOwner(tip) then
		if not pcall(NoteKind, tip, data) then
			local note = notes[tip]
			if note then
				note.kind = false
			end
		end
		InkName(tip)
		prelayout = true
		Touch(tip)
		prelayout = false
	end
end

-- a unit's, once more after the other post-calls of its type (the Tooltip
-- tweak's colours a player's name by its class after the AllTypes ones):
-- still before the layout
local function UnitPostCall(tip)
	if tip and not inking and InkOn() and SheetOwner(tip) then
		InkName(tip)
	end
end

-- The game's own tooltips followed through Show (user, 2026-09-24: the lines
-- flickered white, the Game Menu button's most of all): every builder ends
-- with it -- the data's post-calls then Show, a Lua-built tooltip's AddLines
-- then Show, the Game Menu's latency and framerate lines refilled each
-- second while it is hovered (no OnShow: it already shows) -- so its lines
-- are inked in the call that coloured them, before they are drawn; and once
-- more on the next frame (a line coloured after Show). A secure post-hook:
-- the game's calls to Show stay secure. Other addons' tooltips dressed
-- through the backdrop hook are left to their events and the sweep
local showHooked = setmetatable({}, { __mode = "k" })   -- [tooltip] = true: its Show followed
local ShowInk = Shared("Show on the game's tooltips", function(tip)
	Touch(tip)
end)

local function HookShow(tip)
	if not tip or showHooked[tip] or not tip.Show then
		return
	end
	local ok, forbidden = pcall(tip.IsForbidden, tip)
	if ok and not forbidden then
		showHooked[tip] = true
		hooksecurefunc(tip, "Show", ShowInk)
	end
end

-- A unit frame's tooltip (player, target, party ...) refreshed each 0.2 s
-- while hovered: the game colours the name line after Show -- that line
-- inked again (the Show hook walked the rest), the next frame still looks
local unitHooked = false
local UnitTooltipInk = Shared("UnitFrame_UpdateTooltip", function()
	local tip = GameTooltip
	if inking or not InkOn() or not (tip and sheets[tip] and tip:IsVisible()) then
		return
	end
	local line = _G.GameTooltipTextLeft1
	if line and line:IsShown() and not pcall(InkLine, line, true, tip) then
		inking = false
	end
	Touch(tip, false)
end)

-- Every line inked (the parchment came) or put back (it went, or the
-- reskin did)
local function InkAll(on)
	if on then
		for tip, sheet in pairs(sheets) do
			if sheet:IsShown() and tip:IsVisible() then
				Touch(tip)
			end
		end
	else
		wipe(pending)
		for fs, state in pairs(lineState) do
			lineState[fs] = nil
			local ok = pcall(PlainLine, fs, state)
			if not ok then
				inking = false
			end
		end
		-- no gems without the parchment: the names in the game's colours
		for _, gem in pairs(gems) do
			gem:Hide()
		end
	end
end

-- The sheets shown while the reskin is on and the parchment chosen; the dark
-- panels while the reskin is on and the parchment is not
local function ShowSheets()
	local paper = Kit.ParchmentOn and Kit:ParchmentOn("tooltip")
	local on = (active and paper) and true or false
	for _, sheet in pairs(sheets) do
		sheet:SetShown(on)
	end
	local dark = (active and not paper) and true or false
	for _, dim in pairs(dims) do
		dim:SetShown(dark)
	end
end

-- The parchment on a dressed tooltip: a region of its NineSlice in the layer
-- stack the kit's stone and rail live in (the stone BACKGROUND 0, the sheet
-- BACKGROUND 3, the rail BORDER), under the tooltip's texts as the game's
-- own pieces are. It follows the tooltip's every size by its anchors; the
-- tile and the painted edge are laid again as the kit's skin (our frame, the
-- tooltip's size) changes size or shows, and the lines inked then too.
local function AddSheet(tip, rep)
	local nine = tip.NineSlice
	if not (rep and rep.skin and nine) then
		return
	end
	-- no eye strain (user, 2026-09-24: "too much small text over a plain
	-- brown border is just an eye strain" / "apply the eye strain rule to all
	-- existing windows"; WINDOW-RULES 2e): a tooltip is nothing but text, so
	-- on the stone look (its parchment off) the stone inside the rail lies
	-- under the palette's inner panel. A region of the NineSlice as the sheet
	-- is (the tooltip's texts are drawn over the NineSlice's layers, a frame
	-- of ours could come over them), in its stack between the stone
	-- (BACKGROUND 0) and the sheet (BACKGROUND 3); Kit:SetParchment switches
	-- it against the sheet, ShowSheets with the reskin.
	if not dims[tip] and Kit.StoneDim then
		dims[tip] = Kit:StoneDim(nine, { area = "tooltip", sublevel = 2, alive = function() return active end })
	end
	if sheets[tip] or not Kit.ParchmentSheet then
		return
	end
	local sheet = Kit:ParchmentSheet(nine, rep.skin, { margin = SHEET_MARGIN, fine = true, area = "tooltip",
		alive = function() return active end })
	if not sheet then
		return
	end
	sheets[tip] = sheet
	Perf.HookScript(rep.skin, "OnShow", function()
		Touch(tip)
	end)
	Perf.HookScript(rep.skin, "OnSizeChanged", function()
		Touch(tip)
	end)
end

local function SkinTooltip(tip)
	if not (tip and tip.NineSlice) or dressed[tip] then
		return
	end
	-- a forbidden tooltip (the store's, the secure ones) is never dressed:
	-- every later look at it would raise
	local okF, forbidden = pcall(tip.IsForbidden, tip)
	if not okF or forbidden then
		return
	end
	dressed[tip] = true
	local nine = tip.NineSlice
	local corner = nine.TopLeftCorner
	if corner then
		local others = {}
		for _, key in ipairs(PIECES) do
			others[#others + 1] = nine[key]
		end
		local rep = Replace(corner, { as = "Tooltip-NineSlice-CornerTopLeft", rect = nine, alsoFade = others })
		AddSheet(tip, rep)
	end
	local bar = tip.StatusBar
	if bar and bar.GetStatusBarTexture then
		local layer, sublevel, troughLayer, troughSub = Kit:BracketLayers(bar)
		local rep = Replace(bar, { as = "TooltipStatusBar", parent = bar, rect = bar, noFade = true,
			layer = layer, sublevel = sublevel, troughLayer = troughLayer, troughSub = troughSub })
		if rep then
			local enable, disable = rep.onEnable, rep.onDisable
			rep.onEnable = function(...)
				if enable then
					enable(...)
				end
				InsetBar(bar, rep)
			end
			rep.onDisable = function(...)
				if disable then
					disable(...)
				end
				RestoreBar(bar)
			end
			Perf.HookScript(bar, "OnShow", function()
				if active then
					InsetBar(bar, rep)
					rep:Refit()
				end
			end)
			if active then
				InsetBar(bar, rep)
			end
		end
	end
end

local KNOWN = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
	"EmbeddedItemTooltip", "GameSmallHeaderTooltip", "FriendsTooltip" }

local function Build()
	if skin then
		return
	end
	skin = { reps = {}, followers = {} }
	for _, name in ipairs(KNOWN) do
		local tip = _G[name]
		if tip then
			SkinTooltip(tip)
			HookShow(tip)
			if tip.Tooltip then
				SkinTooltip(tip.Tooltip)
				HookShow(tip.Tooltip)
			end
		end
	end
	if type(_G.UnitFrame_UpdateTooltip) == "function" then
		hooksecurefunc("UnitFrame_UpdateTooltip", UnitTooltipInk)
		unitHooked = true
	end
	if SharedTooltip_SetBackdropStyle then
		hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tip)
			if active then
				SkinTooltip(tip)
			end
		end)
	end
	-- every tooltip the game fills from its data (items, units, spells ...)
	-- inked once it is filled (a post-call runs after the game's lines, and
	-- the game's Show lays it out after it); what the data is kept for the
	-- gem on its name. A unit's name once more after the Unit type's own
	-- post-calls (registered after the Tooltip tweak's: its module comes
	-- first in the TOC)
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipDataProcessor.AllTypes then
		TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, DataPostCall)
		local types = Enum and Enum.TooltipDataType
		if type(types) == "table" and types.Unit ~= nil then
			TooltipDataProcessor.AddTooltipPostCall(types.Unit, UnitPostCall)
		end
	end
	-- the ink's surface: switched with the parchment (Kit:SetParchment
	-- refreshes the surface named after its area) and with the reskin
	if QI and QI.Surface and not QI.surfaces.tooltip then
		QI.Surface("tooltip", { noWalk = true, on = InkOn, onRefresh = InkAll })
	end
end

local function RefreshInk()
	if QI and QI.surfaces and QI.surfaces.tooltip then
		QI.RefreshSurface("tooltip")
	end
end

local function Activate()
	if active then
		return
	end
	active = true
	Build()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	ShowSheets()
	Kit:Cover("tooltip")
	RefreshInk()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	-- the sheets are the NineSlice's regions, not the skin's: hidden by hand
	ShowSheets()
	Kit:Uncover("tooltip")
	RefreshInk()
end

function M:OnEnable(db)
	self.db = db
	Activate()
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /ttdump [frames|reps]: the GameTooltip's art (hover something, then type
-- it: the tooltip is dumped as last shown). Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOTTDUMP1 = "/ttdump"
SlashCmdList.MELLOTTDUMP = function(msg)
	msg = (msg or ""):lower()
	MelloUI:ClearLog()
	-- the ink's hooks as they went in on this client
	local shows = 0
	for _ in pairs(showHooked) do
		shows = shows + 1
	end
	MelloUI:Print("ink: Show followed on %d tooltips, unit frame refresh %s", shows, unitHooked and "followed" or "NOT followed")
	-- the names' gems: made, and what the tooltip's data was
	for tip, gem in pairs(gems) do
		local okN, name = pcall(tip.GetName, tip)
		local note = notes[tip]
		MelloUI:Print("gem on %s: %s, data %s", tostring(okN and name or "?"), gem:IsShown() and "shown" or "hidden",
			tostring(note and note.kind))
	end
	if not GameTooltip then
		MelloUI:Print("No tooltip.")
	else
		Kit:DumpWindow(GameTooltip, skin, msg ~= "" and msg or nil)
	end
	MelloUI:ShowLog("ttdump " .. msg)
end
