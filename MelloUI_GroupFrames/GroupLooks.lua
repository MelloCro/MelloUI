--------------------------------------------------------------------------------
-- MelloUI - Group Frames: the looks
--
-- One indicator's regions and how each look lays them on a frame (a "host":
-- a game compact frame, your frame while solo, a sample in the Designer).
-- The same regions serve a slot of the game's aura container (the engine
-- fills them: the aura's icon, its time, its stacks, its debuff colour) and a
-- sample (filled here with made-up values, nothing read).
--   Looks.Make(b) -> parts        the regions, made once on the button b
--   Looks.Lay(b, parts, ind, host, healthFill)   placed and sized for its
--                                  look; the parts its look does not use hidden
--   Looks.Hand(b, parts, ind)     the parts its look uses handed to the
--                                  slot's button (the others taken back)
--   Looks.Sample(b, parts, ind, frac)   a sample's made-up state (frac: the
--                                  time left, 0..1)
-- The looks (the user, 2026-10-09: "choose if something like renew is going
-- as an icon, or draining icon etc, font sizes and positions is also very
-- important"; pick 1A for the square):
--   icon    the aura's icon, its time as a sweep (a debuff's: the game's
--           border in its type's colour)
--   drain   the aura's icon drawn as a bar's fill, emptying from the top as
--           the time runs out, on its own dark shade
--   square  a square in the player's colour on its own dark shade, draining
--           from the top
--   bar     a thin bar along an edge (TOP / BOTTOM: across, LEFT / RIGHT: up),
--           its length the time left
--   health  the health bar's fill in the player's colour ("recolor your
--           Healthbar when you have certain Hots"): a tint over the fill,
--           drawn in the slot's button so it shows exactly while the game
--           shows the slot
-- The time and the stacks: text in their own size and place (3 x 3 round
-- the indicator, and an offset).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local W = MelloUI.Widgets
local Num = MelloUI.Safe.Number
local RD = ns.RD

local Looks = {}
ns.Looks = Looks

local WHITE = "Interface\\Buttons\\WHITE8X8"   -- look-ok: the square's and the bar's fill, in the player's colour
local CROP = 0.08                              -- an icon's rim cropped off
local SHADE = 0.85                             -- the square's own dark shade

-- a debuff kind's picture on a sample (the game's own icons)
local KIND_ICON = {
	Magic = "Interface\\Icons\\Spell_Holy_DispelMagic",          -- look-ok: a sample's picture
	Curse = "Interface\\Icons\\Spell_Shadow_CurseOfTounges",      -- look-ok: a sample's picture
	Disease = "Interface\\Icons\\Spell_Shadow_CallofBone",        -- look-ok: a sample's picture
	Poison = "Interface\\Icons\\Spell_Nature_CorrosiveBreath",    -- look-ok: a sample's picture
	boss = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",       -- look-ok: a sample's picture
	cc = "Interface\\Icons\\Spell_Nature_Polymorph",              -- look-ok: a sample's picture
}
local KIND_SAMPLE_TYPE = { group = "Magic", mine = "Magic", any = "Magic", Magic = "Magic", Curse = "Curse",
	Disease = "Disease", Poison = "Poison" }
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"   -- look-ok: a spell not known yet

local function FontFile()
	local f = rawget(_G, "NumberFontNormalSmall") or rawget(_G, "GameFontHighlightSmall")
	local file = f and f.GetFont and f:GetFont()
	return file or rawget(_G, "STANDARD_TEXT_FONT")
end

-- a frame drawn at its parent's level (the client's SetUsingParentLevel; one
-- without it: the parent's level, set once)
function Looks.ParentLevel(f, on)
	if type(f.SetUsingParentLevel) == "function" then
		f:SetUsingParentLevel(on)
	elseif on then
		local parent = f:GetParent()
		if parent then
			f:SetFrameLevel(parent:GetFrameLevel())
		end
	end
end

-- a status bar's fill texture (nil where the client gives none)
function Looks.Fill(bar)
	return bar and type(bar.GetStatusBarTexture) == "function" and bar:GetStatusBarTexture() or nil
end

-- the time as the bare number of seconds, rounded up, counting down to 1 (the
-- user, 2026-10-09: "they dont need to state "s" as in for seconds, they
-- should just count down ... just the raw number"): the client's own rule
-- formatter (C_StringUtil.CreateNumericRuleFormatter), one rule from 0 up,
-- made once; nil where the client has none (the game's own then)
local raw = nil
local function RawSeconds()
	if raw == nil then
		raw = false
		local SU = rawget(_G, "C_StringUtil")
		local E = rawget(_G, "Enum")
		if type(SU) == "table" and type(SU.CreateNumericRuleFormatter) == "function" then
			local ok, f = pcall(SU.CreateNumericRuleFormatter)
			if ok and f and f.AddBreakpoint then
				local up = E and E.NumericRuleFormatRounding and E.NumericRuleFormatRounding.Up
				if pcall(f.AddBreakpoint, f, { threshold = 0, step = 1, rounding = up, format = "%d" }) then
					raw = f
				end
			end
		end
	end
	return raw or nil
end
Looks.RawSeconds = RawSeconds

local function Call(obj, method, ...)
	local fn = obj and obj[method]
	if type(fn) ~= "function" then
		return false
	end
	local ok = pcall(fn, obj, ...)
	return ok
end

--------------------------------------------------------------------------------
-- Make
--------------------------------------------------------------------------------

function Looks.Make(b)
	local p = {}
	p.shade = b:CreateTexture(nil, "BACKGROUND")
	p.shade:SetAllPoints(b)
	W.Paint(p.shade, "mainWindow", "fill", SHADE)
	p.icon = b:CreateTexture(nil, "ARTWORK")
	p.icon:SetAllPoints(b)
	p.icon:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
	p.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	p.cd:SetAllPoints(b)
	Call(p.cd, "SetDrawEdge", false)
	Call(p.cd, "SetHideCountdownNumbers", true)
	p.fill = CreateFrame("StatusBar", nil, b)
	p.fill:SetAllPoints(b)
	p.fill:SetStatusBarTexture(WHITE)
	p.fill:SetMinMaxValues(0, 1)
	p.fill:SetValue(1)
	p.border = b:CreateTexture(nil, "OVERLAY")
	p.border:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
	p.border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
	p.edges = W.Edges(b, "mainWindow", "OVERLAY")
	p.tint = b:CreateTexture(nil, "OVERLAY")
	p.tint:SetTexture(WHITE)
	-- the texts over everything of the indicator's (a frame of their own above
	-- the sweep and the fill)
	p.texts = CreateFrame("Frame", nil, b)
	p.texts:SetAllPoints(b)
	p.texts:SetFrameLevel(b:GetFrameLevel() + 5)
	p.text = p.texts:CreateFontString(nil, "OVERLAY")
	p.count = p.texts:CreateFontString(nil, "OVERLAY")
	for _, fs in ipairs({ p.text, p.count }) do
		fs:SetFont(FontFile(), RD.SIZE.text, "OUTLINE")
		W.Paint(fs, "text", "text")
	end
	return p
end

--------------------------------------------------------------------------------
-- Lay
--------------------------------------------------------------------------------

local function ShowEdges(p, on)
	for i = 1, #p.edges do
		p.edges[i]:SetShown(on)
	end
end

-- a text at its place round the indicator (or round the host for a bar
-- and the health colour: their own button is a line or nothing)
local function LayText(fs, t, anchor)
	fs:ClearAllPoints()
	if not (t and t.show) then
		fs:Hide()
		return
	end
	fs:SetFont(FontFile(), t.size or RD.SIZE.text, "OUTLINE")
	local point = t.point or "CENTER"
	fs:SetPoint(point, anchor, point, t.x or 0, t.y or 0)
	fs:Show()
end

local EDGE_INSET = 1

-- a bar's edge: its points on the host and whether it runs up
local function BarPlace(b, ind, host)
	local point = ind.point or "BOTTOM"
	local size = ind.size or 3
	local len = math.max(0.1, math.min(1, ind.length or 1))
	local vertical = point == "LEFT" or point == "RIGHT"
	local w, h = Num(host:GetWidth()) or 72, Num(host:GetHeight()) or 36
	b:ClearAllPoints()
	if vertical then
		b:SetSize(size, math.max(1, (h - 2 * EDGE_INSET) * len))
		b:SetPoint(point, host, point, (point == "LEFT" and EDGE_INSET or -EDGE_INSET) + (ind.x or 0), ind.y or 0)
	else
		local edge = (point:find("TOP") and "TOP") or "BOTTOM"
		local side = (point:find("LEFT") and "LEFT") or (point:find("RIGHT") and "RIGHT") or ""
		b:SetSize(math.max(1, (w - 2 * EDGE_INSET) * len), size)
		local at = edge .. side
		local dx = (side == "LEFT" and EDGE_INSET) or (side == "RIGHT" and -EDGE_INSET) or 0
		b:SetPoint(at, host, at, dx + (ind.x or 0), (edge == "TOP" and -EDGE_INSET or EDGE_INSET) + (ind.y or 0))
	end
	return vertical
end

function Looks.Lay(b, p, ind, host, healthFill)
	local look = ind.look
	local size = ind.size or 12
	-- (a debuff in its type's colour: the game colours the fill or the tint;
	-- a lay leaves it alone)
	local own = not (ind.kind == "debuff" and ind.colourBy == "type")
	p.shade:Hide()
	p.icon:Hide()
	p.cd:Hide()
	p.fill:Hide()
	p.border:Hide()
	p.tint:Hide()
	ShowEdges(p, false)
	if look == "bar" then
		local vertical = BarPlace(b, ind, host)
		p.fill:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
		p.fill:SetStatusBarTexture(WHITE)
		if own then
			p.fill:SetStatusBarColor(ind.r or 1, ind.g or 1, ind.b or 1)
		end
		p.shade:Show()
		p.fill:Show()
	elseif look == "health" then
		b:ClearAllPoints()
		b:SetSize(1, 1)
		b:SetPoint("CENTER", host, "CENTER", 0, 0)
		p.tint:ClearAllPoints()
		if healthFill then
			p.tint:SetAllPoints(healthFill)
		end
		if own then
			p.tint:SetVertexColor(ind.r or 1, ind.g or 1, ind.b or 1, ind.alpha or 0.55)
		else
			p.tint:SetAlpha(ind.alpha or 0.55)
		end
		p.tint:Show()
	else
		b:ClearAllPoints()
		b:SetSize(size, size)
		b:SetPoint(ind.point or "CENTER", host, ind.point or "CENTER", ind.x or 0, ind.y or 0)
		if look == "icon" then
			p.icon:Show()
			p.cd:Show()
			ShowEdges(p, true)
			p.border:SetShown(ind.kind == "debuff" and ind.colourBy == "type")
		elseif look == "drain" then
			p.shade:Show()
			p.fill:SetOrientation("VERTICAL")
			p.fill:SetStatusBarColor(1, 1, 1)
			p.fill:Show()
			ShowEdges(p, true)
		else
			-- square (pick 1A: its own dark shade, draining from the top)
			p.shade:Show()
			p.fill:SetOrientation("VERTICAL")
			p.fill:SetStatusBarTexture(WHITE)
			if own then
				p.fill:SetStatusBarColor(ind.r or 1, ind.g or 1, ind.b or 1)
			end
			p.fill:Show()
			ShowEdges(p, true)
		end
	end
	local anchor = (look == "health") and host or b
	LayText(p.text, look ~= "bar" and ind.text, anchor)
	LayText(p.count, look ~= "bar" and look ~= "health" and ind.count, anchor)
end

--------------------------------------------------------------------------------
-- Hand: the parts a look uses handed to a slot's button, the rest taken back
--------------------------------------------------------------------------------

local function Enum2(group, name)
	local E = rawget(_G, "Enum")
	local t = type(E) == "table" and E[group]
	return type(t) == "table" and t[name] or nil
end

function Looks.Hand(b, p, ind)
	local look = ind.look
	for _, m in ipairs({ "ClearIcon", "ClearDurationCooldown", "ClearDurationBar", "ClearDurationText", "ClearApplicationCount" }) do
		Call(b, m)
	end
	if p.typed then
		Call(b, "RemoveDispelTypeTexture", p.typed)
		p.typed = nil
	end
	local remaining = Enum2("StatusBarTimerDirection", "RemainingTime")
	local barOpts = remaining and { direction = remaining } or nil
	local byType = ind.kind == "debuff" and ind.colourBy == "type"
	local style = Enum2("CustomAuraButtonDispelTypeTextureStyle", byType and look == "icon" and "Border" or "PreserveAsset")
	local typed = nil
	if look == "icon" then
		Call(b, "SetIcon", p.icon)
		Call(b, "SetDurationCooldown", p.cd)
		typed = byType and p.border
	elseif look == "drain" then
		Call(b, "SetIcon", Looks.Fill(p.fill))
		Call(b, "SetDurationBar", p.fill, barOpts)
	elseif look == "square" or look == "bar" then
		Call(b, "SetDurationBar", p.fill, barOpts)
		typed = byType and Looks.Fill(p.fill)
	elseif look == "health" then
		typed = byType and p.tint
	end
	if typed and style ~= nil then
		if Call(b, "AddDispelTypeTexture", typed, { style = style, showWhenHarmful = true, showWithoutDispelType = true }) then
			p.typed = typed
		end
	end
	if look ~= "bar" and ind.text and ind.text.show then
		local f = RawSeconds()
		Call(b, "SetDurationText", p.text, f and { textFormatter = f } or nil)
	end
	if look ~= "bar" and look ~= "health" and ind.count and ind.count.show then
		Call(b, "SetApplicationCount", p.count)
	end
end

--------------------------------------------------------------------------------
-- Sample: a made-up state (the Designer, the fake raid): nothing read
--------------------------------------------------------------------------------

local function SampleTypeColour(ind)
	local t = KIND_SAMPLE_TYPE[ind.what]
	local c = t and rawget(_G, "DEBUFF_TYPE_" .. t:upper() .. "_COLOR")
	if type(c) == "table" and c.GetRGB then
		return c:GetRGB()
	end
	return RD.NamedColour("RED_FONT_COLOR")
end

function Looks.Sample(b, p, ind, frac)
	frac = frac or 0.6
	local look = ind.look
	local icon = (ind.kind == "buff" and (RD:SpellIcon(ind) or UNKNOWN_ICON)) or KIND_ICON[ind.what] or KIND_ICON.Magic
	local byType = ind.kind == "debuff" and ind.colourBy == "type"
	if look == "icon" then
		p.icon:SetTexture(icon)
		Call(p.cd, "SetCooldown", GetTime() - (1 - frac) * 15, 15)
		if byType then
			p.border:SetTexture(WHITE)
			p.border:SetVertexColor(SampleTypeColour(ind))
			p.border:SetDrawLayer("BACKGROUND", -1)
		end
	elseif look == "drain" then
		p.fill:SetStatusBarTexture(icon)
		p.fill:SetValue(frac)
	elseif look == "square" or look == "bar" then
		p.fill:SetValue(frac)
		if byType then
			p.fill:SetStatusBarColor(SampleTypeColour(ind))
		end
	elseif look == "health" and byType then
		local r, g, bl = SampleTypeColour(ind)
		p.tint:SetVertexColor(r, g, bl, ind.alpha or 0.55)
	end
	p.text:SetText(tostring(math.floor(frac * 15 + 0.5)))
	p.count:SetText("2")
	b:Show()
end
