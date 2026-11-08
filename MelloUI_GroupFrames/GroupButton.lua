--------------------------------------------------------------------------------
-- MelloUI - Group Frames: one member's frame (stage 1 of MelloUI's own group
-- frames; the user, 2026-10-09: "i want the exact same functionality as
-- danders frames has", "make sure that the changes, size etc that is on the
-- preview, match exactly the Unitframe")
--
-- ONE builder and ONE set of painters for every frame: the secure header's
-- children (GroupHeaders.lua) and the Designer's preview and fake raid, which
-- are the same frame fed made-up values (Button.Sample) -- so the preview is
-- the frame, size for size and colour for colour.
--   Button.Build(f)         the regions, made once
--   Button.Lay(f)           the bars' places and fill (the power bar shown or
--                           not, its height, the fill direction), the parts
--                           (name, health text, icons: GroupParts)
--   Button.Refresh(f)       everything of f's unit painted again
--   Button.Health / Power / Name / Role / Mark / Ready / Range / Paint (f)
--   Button.InRange(unit)    the range rule (true, false, or the client's secret answer and its secret "checked")
--   Button.RangeAlpha(f, unit, alpha, away)   f faded by it (away: out of range)
--   Button.Sample(f, s)     a made-up member: s = { class, name, health (0..1),
--                           power (0..1), role, dead, offline, mark, ready,
--                           outOfRange, shield (0..1 of the maximum) }
-- Every value of the unit goes to the client's own widgets as it is (secret
-- or not): the health as the client's percent (UnitHealthPercent with the
-- game's 0..100 curve), the missing health (UnitHealthMissing), the colours by
-- health through a colour curve, the health text through the client's string
-- helpers (RoundToNearestString, AbbreviateNumbers, TruncateWhenZero,
-- WrapString), the range through SetAlphaFromBoolean. Nothing compared,
-- nothing added up in Lua.
-- The frame's regions keep the game's raid frame's names (background,
-- healthBar, powerBar, name, statusText, roleIcon, readyCheckIcon,
-- centerStatusIcon) so the kit's raid dressing and the parts take them as they
-- take the game's.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local W = MelloUI.Widgets
local Secret = MelloUI.Safe.IsSecret
local Text = MelloUI.Safe.Text
local RD = ns.RD
local Looks = ns.Looks
local GREY = MelloUI.Meaning.groupGrey   -- (no class to read, offline, dead)

local Button = {}
ns.Button = Button

local WHITE = "Interface\\Buttons\\WHITE8X8"   -- look-ok: the background's flat fill, in the player's colour
local INSET = 1                                -- the bars' room from the frame's edge (the game's)
local GAP = 1                                  -- between the health and the power bar

-- the game's own role atlases and ready check pictures, by name
local READY = { ready = "READY_CHECK_READY_TEXTURE_RAID", notready = "READY_CHECK_NOT_READY_TEXTURE_RAID",
	waiting = "READY_CHECK_WAITING_TEXTURE_RAID" }

local function DB()
	return RD.DB()
end

local RANGE_ALPHA = 0.4   -- (2.1.0: Out Of Range Opacity's default -- the fade of the best-known group frames)

-- a call guarded: its first answer, or nil (an error, a missing API, a secret)
local function Ask(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, ...)
	if ok and not Secret(v) then
		return v
	end
	return nil
end

--------------------------------------------------------------------------------
-- Reads (each one guarded: a secret or a missing API is "unknown")
--------------------------------------------------------------------------------

local Value = MelloUI.Safe.Value

-- a call's answer: nil when it failed or is secret
local function Answer(ok, v)
	if not ok then
		return nil
	end
	return Value(v)
end

local function Dead(unit)
	return MelloUI.Units.Gone(unit)   -- (the one rule of every bar of a unit: its bars at none)
end

local function Ghost(unit)
	return Answer(pcall(UnitIsGhost, unit)) == true
end

local function Offline(unit)
	return Answer(pcall(UnitIsConnected, unit)) == false
end

local function ClassOf(f)
	if f.sample then
		return f.sample.class
	end
	if not f.unit then
		return nil
	end
	local ok, _, class = pcall(UnitClass, f.unit)
	return ok and class or nil   -- (a secret class: the game's own lookup takes it as it is)
end

-- a unit's class colour (a secret class: the client's own lookup answers in kind)
local function ClassRGB(f)
	local class = ClassOf(f)
	if class == nil then
		return GREY[1], GREY[2], GREY[3]
	end
	local r, g, b = MelloUI.Colours.Class(class)
	if type(r) == "number" then
		return r, g, b
	end
	return GREY[1], GREY[2], GREY[3]
end

-- the colour a mode names: the class's, a setting's, or nil (another way)
local function ModeRGB(f, mode, customKey)
	if mode == "class" then
		return ClassRGB(f)
	elseif mode == "custom" then
		return W.ColourValue(DB()[customKey])
	elseif mode == "green" then
		return W.ColourValue("GREEN_FONT_COLOR")
	elseif mode == "white" then
		return 1, 1, 1
	end
	return nil
end

--------------------------------------------------------------------------------
-- The health curve (By Health: the player's three colours, full / half / low)
--------------------------------------------------------------------------------

-- (the three colours it was made from kept and compared: asked on every
-- health update, so nothing is made per call)
local curve = { built = false, low = nil, mid = nil, high = nil, obj = nil }

local function HealthCurve()
	local db = RD.Health()   -- (one look Q7: the one Health Colour's colours, Bar Textures')
	if curve.built and curve.low == db.healthLow and curve.mid == db.healthMid and curve.high == db.healthHigh then
		return curve.obj
	end
	curve.built, curve.low, curve.mid, curve.high, curve.obj = true, db.healthLow, db.healthMid, db.healthHigh, nil
	local CU = rawget(_G, "C_CurveUtil")
	if type(CU) == "table" and type(CU.CreateColorCurve) == "function" and CreateColor then
		local ok, c = pcall(function()
			local made = CU.CreateColorCurve()
			local E = rawget(_G, "Enum")
			if E and E.LuaCurveType then
				made:SetType(E.LuaCurveType.Linear)
			end
			for _, stop in ipairs({ { 0, db.healthLow }, { 0.5, db.healthMid }, { 1, db.healthHigh } }) do
				local r, g, b = W.ColourValue(stop[2])
				made:AddPoint(stop[1], CreateColor(r, g, b, 1))
			end
			return made
		end)
		if ok then
			curve.obj = c
		end
	end
	return curve.obj
end

-- the colour at the unit's health on the curve (nil: no curve, no unit)
local function HealthRGB(f)
	local c = HealthCurve()
	if not c then
		return nil
	end
	if f.sample then
		local h = f.sample.health or 1
		local ok, col = pcall(c.Evaluate, c, h)
		if ok and col and col.GetRGB then
			return col:GetRGB()
		end
		return nil
	end
	local ok, col = pcall(UnitHealthPercent, f.unit, true, c)
	if ok and col and col.GetRGB then
		return col:GetRGB()
	end
	return nil
end

--------------------------------------------------------------------------------
-- Build and lay
--------------------------------------------------------------------------------

local function Bar(parent)
	local b = CreateFrame("StatusBar", nil, parent)
	Looks.ParentLevel(b, true)
	b:SetMinMaxValues(0, 1)
	b:SetValue(0)
	return b
end

-- (1.2.4, the Default skin's wave C: the user's pick A, docs/plans/default-skin.md 5e) under the Default skin a cell
-- is the game's own compact raid frame in place (MelloUI.Skin's raid pieces, CompactUnitFrameTemplate's art): its
-- health and resource fills (unless the raid frames' Bar Texture is the player's own pick), its dark ground under a
-- Flat Background, its separators along the bottom and the right in place of the frame's 1-unit edges. Every piece
-- tiles, so it is sharp at any size
local SEP, SEP_TEXELS, SEP_LEN = 2, 8, 128   -- the separators: their line the outer 2 of 8 texels, 128 long
local Finite = MelloUI.Safe.Finite

-- the skin while the Default skin shows (nil: MelloUI's own look)
local function GameSkin()
	local Skin = rawget(MelloUI, "Skin")
	return (Skin and Skin.IsDefault()) and Skin or nil
end

local function Tile(tex, across, down)
	tex:SetHorizTile(across)
	tex:SetVertTile(down)
end

-- the separators' length a texel a unit, repeated (never drawn bigger than their picture)
local function SeparatorsFit(f)
	local s = f.separators
	local okW, w = pcall(f.GetWidth, f)
	local okH, h = pcall(f.GetHeight, f)
	w, h = okW and Finite(w) or SEP_LEN, okH and Finite(h) or SEP_LEN
	s[1]:SetTexCoord(0, w / SEP_LEN, 0, SEP / SEP_TEXELS)
	s[2]:SetTexCoord(0, SEP / SEP_TEXELS, 0, h / SEP_LEN)
end

-- the game's separators shown (made on their first need) and the frame's own edges hidden, or the other way round
local function Separators(f, Skin)
	local s = f.separators
	for i = 1, #f.edges do
		f.edges[i]:SetShown(not Skin)
	end
	if not Skin then
		if s then
			s[1]:Hide()
			s[2]:Hide()
		end
		return
	end
	if not s then
		local across = f:CreateTexture(nil, "OVERLAY", nil, 7)
		across:SetTexture(Skin.ART.raidSepH, "REPEAT", "CLAMP")
		across:SetHeight(SEP)
		across:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
		across:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		local down = f:CreateTexture(nil, "OVERLAY", nil, 7)
		down:SetTexture(Skin.ART.raidSepV, "CLAMP", "REPEAT")
		down:SetWidth(SEP)
		down:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
		down:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		s = { across, down }
		f.separators = s
		-- (1.2.4, lk-11: the game's edges under Dark Mode as the frame's own, the kit's shade)
		local Kit = MelloUI.Kit
		if Kit and Kit.RegisterTexture then
			Kit:RegisterTexture(across)
			Kit:RegisterTexture(down)
		end
	end
	SeparatorsFit(f)
	s[1]:Show()
	s[2]:Show()
end

-- a background picture tiled again as its frame changes size (one handler for every frame); the separators too
local function Background_OnSize(f)
	local Kit = MelloUI.Kit
	if Kit and f.background and Kit.pieceNameOf[f.background] then
		Kit:Retile(f.background)
	end
	if f.separators and f.separators[1]:IsShown() then
		SeparatorsFit(f)
	end
end

function Button.Build(f)
	if f.healthBar then
		return f
	end
	f.background = f:CreateTexture(nil, "BACKGROUND")
	f.background:SetAllPoints(f)
	f.background:SetTexture(WHITE)
	-- (1.2.4, lk-11) the frame's ground under Dark Mode, in its colours: the kit's shade at the Unit Frames area's
	-- brightness (a kit piece on it is registered the same way, Kit:Apply)
	local Kit = MelloUI.Kit
	if Kit and Kit.RegisterTexture then
		Kit:RegisterTexture(f.background)
	end
	f:HookScript("OnSizeChanged", Background_OnSize)
	f.healthBar = Bar(f)
	f.healthBar:SetMinMaxValues(0, 100)
	f.missingBar = Bar(f.healthBar)
	f.missingBar:SetAllPoints(f.healthBar)
	f.powerBar = Bar(f)
	f.name = f:CreateFontString(nil, "ARTWORK", "MelloUIFont_GameFontHighlightSmall")
	f.name:SetWordWrap(false)
	f.statusText = f:CreateFontString(nil, "ARTWORK", "MelloUIFont_GameFontHighlightSmall")
	f.statusText:SetWordWrap(false)
	f.roleIcon = f:CreateTexture(nil, "ARTWORK")
	f.roleIcon:Hide()
	f.raidIcon = f:CreateTexture(nil, "OVERLAY")
	f.raidIcon:Hide()
	f.readyCheckIcon = f:CreateTexture(nil, "OVERLAY")
	f.readyCheckIcon:Hide()
	f.centerStatusIcon = f:CreateTexture(nil, "OVERLAY")
	f.centerStatusIcon:Hide()
	f.edges = W.Edges(f, "border", "OVERLAY")
	Button.Lay(f)
	return f
end

-- who shows a power bar: the setting, the role, solo (your own while solo)
local function ShowsPower(f)
	local db = DB()
	if f.sample then
		if db.power == "off" then
			return false
		end
		return db.power == "all" or f.sample.role == "HEALER"
	end
	local unit = f.unit
	if not unit then
		return false
	end
	if db.powerSolo and unit == "player" and not IsInGroup() then
		return true
	end
	if db.power == "all" then
		return true
	elseif db.power == "healers" then
		local ok, role = pcall(UnitGroupRolesAssigned, unit)
		return ok and not Secret(role) and role == "HEALER"
	end
	return false
end

local VERTICAL = { UP = true, DOWN = true }
local REVERSE = { LEFT = true, DOWN = true }

local function Fill(bar, dir, reverse)
	bar:SetOrientation(VERTICAL[dir] and "VERTICAL" or "HORIZONTAL")
	if bar.SetReverseFill then
		bar:SetReverseFill(reverse)
	end
	if bar.SetRotatesTexture then
		bar:SetRotatesTexture(VERTICAL[dir] and true or false)
	end
end

function Button.Lay(f)
	local db = DB()
	local power = ShowsPower(f)
	f.showsPower = power
	local ph = power and db.powerHeight or 0
	local hb, pb = f.healthBar, f.powerBar
	-- (inside the kit's border round the frame, both bars: the user,
	-- 2026-10-09, "the power bar however should be inside of the borders, and
	-- fitting the width of the hp bar")
	local ix, iy = INSET, INSET
	local K = MelloUI.Kit
	if K and K.RaidFrameInset then
		local x, y = K:RaidFrameInset(f)
		ix, iy = math.max(INSET, tonumber(x) or 0), math.max(INSET, tonumber(y) or 0)
	end
	hb:ClearAllPoints()
	hb:SetPoint("TOPLEFT", f, "TOPLEFT", ix, -iy)
	hb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ix, iy + (power and (ph + GAP) or 0))
	pb:ClearAllPoints()
	pb:SetPoint("TOPLEFT", hb, "BOTTOMLEFT", 0, -GAP)
	pb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ix, iy)
	pb:SetShown(power)
	-- (the Default skin: the game's fills, tiled as its own frame tiles them, unless the player picked a Bar Texture)
	local Skin = GameSkin()
	local bt = Skin and MelloUI:GetModule("BarTextures")
	local game = Skin and not (bt and bt.PickedTexture and bt.PickedTexture("raidframes")) and Skin.ART or nil
	local file = W.BarFill("raidframes")
	for _, b in ipairs({ hb, f.missingBar, pb }) do
		b:SetStatusBarTexture(game and (b == pb and game.raidPower or game.raidFill) or file)
		local fill = Looks.Fill(b)
		if fill then
			Tile(fill, game ~= nil, game ~= nil and b ~= pb)
		end
		-- (every bar's ends soft: the user, 2026-10-16; the game's own art keeps its own look)
		W.SoftEnds(b, game ~= nil)
	end
	Separators(f, Skin)
	local dir = db.fillDirection or "RIGHT"
	Fill(hb, dir, REVERSE[dir] or false)
	Fill(pb, dir, REVERSE[dir] or false)
	-- the missing health fills from the other end
	Fill(f.missingBar, dir, not (REVERSE[dir] or false))
	local fill = Looks.Fill(hb)
	if fill then
		fill:SetDrawLayer("BORDER", 0)
	end
	local mfill = Looks.Fill(f.missingBar)
	if mfill then
		mfill:SetDrawLayer("BORDER", -1)
	end
	-- (the power bar's fill under the kit's rails too, as the health's: the
	-- rails draw above the BORDER fills -- "raidframe-hp-bg-white" -- and an
	-- ARTWORK fill drew over them)
	local pfill = Looks.Fill(pb)
	if pfill then
		pfill:SetDrawLayer("BORDER", 0)
	end
	if ns.Parts then
		ns.Parts:Lay(f)   -- (by its partsLayout: the raid's when it has none)
	end
	Button.Paint(f)
end

--------------------------------------------------------------------------------
-- The painters
--------------------------------------------------------------------------------

-- the colours that do not follow the health: background, health (but By
-- Health), missing health (but By Health), alphas
function Button.Paint(f)
	local db = DB()
	-- (0.20.1) Background: one of the kit's shared backgrounds in its own colours (tiled at the UI's one background
	-- density, a gradient laid over the whole frame), else the flat fill in the Background Colour; none: see-through
	local bg, Kit = f.background, MelloUI.Kit
	local look = db.backgroundTexture or "flat"
	local piece = look ~= "flat" and Kit and Kit.buttonLooks and Kit.buttonLooks.backgroundPiece[look]
	-- (1.2.4) Flat under the Default skin: the game's dark ground, tiled, in its own colours while the Background
	-- Colour is one of the palette's (the skin's: the palette follows it), else in the player's colour
	local Skin = look == "flat" and GameSkin() or nil
	bg:SetShown(look ~= "none")
	if bg.gameGround and not Skin then
		bg.gameGround = nil
		Tile(bg, false, false)
		bg:SetTexture(WHITE)
		bg:SetTexCoord(0, 1, 0, 1)
	end
	if piece then
		if Kit.pieceNameOf[bg] ~= piece then
			Kit:Apply(bg, piece)
		end
		Kit:Retile(bg)
		bg:SetVertexColor(1, 1, 1, db.backgroundAlpha or 0.9)
	else
		if Kit and Kit.pieceNameOf[bg] then
			Kit.pieceOf[bg], Kit.pieceNameOf[bg], Kit.backgroundOf[bg] = nil, nil, nil
			bg:SetTexture(WHITE)
			bg:SetTexCoord(0, 1, 0, 1)
		end
		local bgR, bgG, bgB = ModeRGB(f, db.background, "backgroundCustom")
		if Skin then
			if not bg.gameGround then
				bg.gameGround = true
				bg:SetAtlas(Skin.ART.raidGround)
				Tile(bg, true, true)
			end
			local skins = db.background == "custom" and type(db.backgroundCustom) == "string"
				and db.backgroundCustom:find("^palette:")
			if skins then
				bgR, bgG, bgB = 1, 1, 1
			end
		end
		bg:SetVertexColor(bgR or 0, bgG or 0, bgB or 0, db.backgroundAlpha or 0.9)
	end
	local fill = Looks.Fill(f.healthBar)
	if fill then
		fill:SetAlpha(db.healthAlpha or 1)
	end
	-- (one look Q7: the one Health Colour, Bar Textures'; Class & Reaction is
	-- the class's here -- every member a player -- and My Colour its colour)
	local health = RD.Health()
	local mode = health.healthColor
	if mode ~= "health" then
		local r, g, b
		if mode == "reaction" then
			r, g, b = ClassRGB(f)
		elseif mode == "custom" then
			r, g, b = W.ColourValue(health.healthCustom)
		else
			r, g, b = ModeRGB(f, mode)
		end
		if r then
			f.healthBar:SetStatusBarColor(r, g, b)
		end
	end
	mode = db.missing or "off"
	f.missingBar:SetShown(mode ~= "off")
	if mode ~= "off" and mode ~= "health" then
		local r, g, b = ModeRGB(f, mode, "missingCustom")
		f.missingBar:SetStatusBarColor(r or 1, g or 0, b or 0, db.missingAlpha or 0.5)
	end
	Button.NameColour(f)
end

function Button.NameColour(f)
	local db = DB()
	local r, g, b = ModeRGB(f, db.nameColour or "white", "nameCustom")
	if f.offline or f.dead then
		r, g, b = 0.6, 0.6, 0.6
	end
	f.name:SetTextColor(r or 1, g or 1, b or 1)
end

local INTERP = nil
local function Interp()
	if INTERP == nil then
		local E = rawget(_G, "Enum")
		INTERP = E and E.StatusBarInterpolation and E.StatusBarInterpolation.ExponentialEaseOut or false
	end
	return INTERP or nil
end

local function SetBar(bar, v, smooth)
	local it = smooth and Interp()
	if it then
		local ok = pcall(bar.SetValue, bar, v, it)
		if ok then
			return
		end
	end
	pcall(bar.SetValue, bar, v)
end

-- the health text: the setting's form, or the member's state
local function HealthText(f, pct)
	local db = DB()
	local fs = f.statusText
	if db.statusText and (f.offline or f.dead) then
		local word = f.offline and (rawget(_G, "PLAYER_OFFLINE") or "Offline")
			or (f.ghost and (rawget(_G, "DEAD") or "Dead")) or (rawget(_G, "DEAD") or "Dead")
		fs:SetText(word)
		fs:Show()
		return
	end
	local form = db.healthText or "none"
	if form == "none" then
		fs:Hide()
		return
	end
	fs:Show()
	if f.sample then
		local h = f.sample.health or 1
		if form == "percent" then
			fs:SetText(math.floor(h * 100 + 0.5) .. "%")
		elseif form == "current" then
			fs:SetText(string.format("%.1fK", h * 12))
		else
			fs:SetText(h >= 1 and "" or string.format("-%.1fK", (1 - h) * 12))
		end
		return
	end
	local SU = rawget(_G, "C_StringUtil")
	local unit = f.unit
	if form == "percent" then
		if SU and SU.RoundToNearestString and SU.WrapString and pct ~= nil then
			local ok, s = pcall(SU.RoundToNearestString, pct, 1)
			if ok then
				local ok2, t = pcall(SU.WrapString, s, nil, "%")
				fs:SetText(ok2 and t or s)
				return
			end
		end
		pcall(fs.SetFormattedText, fs, "%.0f%%", pct)
	elseif form == "current" then
		local ok, s = pcall(AbbreviateNumbers, UnitHealth(unit, true))
		fs:SetText(ok and s or "")
	else
		local ok, missing = pcall(UnitHealthMissing, unit, true)
		if ok and SU and SU.TruncateWhenZero and SU.WrapString then
			local ok2, s = pcall(SU.TruncateWhenZero, missing)
			local ok3, t = pcall(SU.WrapString, ok2 and s or "", "-")
			fs:SetText(ok3 and t or "")
		else
			fs:SetText("")
		end
	end
end

function Button.Health(f)
	local db = DB()
	local hb = f.healthBar
	local was = nil
	if f.sample then
		local s = f.sample
		f.dead, f.offline, f.ghost = s.dead, s.offline, false
		hb:SetValue((s.dead and 0) or (s.offline and 100) or (s.health or 1) * 100)
		f.missingBar:SetMinMaxValues(0, 1)
		f.missingBar:SetValue(1 - (s.health or 1))
	else
		local unit = f.unit
		if not unit then
			return
		end
		was = f.dead
		f.dead, f.offline, f.ghost = Dead(unit), Offline(unit), Ghost(unit)
		local pct = nil
		if f.offline then
			hb:SetValue(100)
		elseif f.dead then
			hb:SetValue(0)
		else
			local CC = rawget(_G, "CurveConstants")
			local ok, v = pcall(UnitHealthPercent, unit, true, CC and CC.ScaleTo100)
			if ok then
				pct = v
				SetBar(hb, v, db.smooth)
			end
		end
		if (db.missing or "off") ~= "off" then
			pcall(f.missingBar.SetMinMaxValues, f.missingBar, 0, UnitHealthMax(unit))
			local ok, m
			if f.dead then
				ok, m = pcall(UnitHealthMax, unit)   -- (gone: all of it missing, whatever the client still hands out)
			else
				ok, m = pcall(UnitHealthMissing, unit, true)
			end
			if ok then
				SetBar(f.missingBar, m, db.smooth)
			end
		end
		HealthText(f, pct)
	end
	if f.sample then
		HealthText(f, nil)
		-- (2.1.0) a made-up shield (Core/Shields.lua): an overshield where it is more than the missing health. A live
		-- member's is Healer Frames' (its heals and shield on every button: GroupHeaders' Dress)
		local s = f.sample
		local share = not (s.dead or s.offline) and s.shield or nil
		if share then
			MelloUI.Shields.Attach(hb)
		end
		MelloUI.Shields.Sample(hb, share, share and share > 1 - (s.health or 1))
	end
	-- the colours that follow the health
	if f.offline or f.dead then
		hb:SetStatusBarColor(GREY[1], GREY[2], GREY[3])
	elseif RD.Health().healthColor == "health" then
		local r, g, b = HealthRGB(f)
		if r then
			hb:SetStatusBarColor(r, g, b)
		end
	end
	if db.missing == "health" then
		local r, g, b = HealthRGB(f)
		if r then
			f.missingBar:SetStatusBarColor(r, g, b, db.missingAlpha or 0.5)
		end
	end
	Button.NameColour(f)
	-- (gone or back: its power with it -- no power event comes for that)
	if was ~= nil and was ~= f.dead then
		Button.Power(f)
	end
end

-- a power's own colour (the game's PowerBarColor), the class's or the player's
local function PowerRGB(f)
	local db = DB()
	local mode = db.powerColour or "type"
	if mode ~= "type" then
		return ModeRGB(f, mode, "powerCustom")
	end
	local token = "MANA"
	if f.unit and not f.sample then
		local ok, _, t = pcall(UnitPowerType, f.unit)
		token = ok and Text(t) or token
	elseif f.sample and f.sample.powerToken then
		token = f.sample.powerToken
	end
	local r, g, b = MelloUI.Colours.Power(token)
	if r then
		return r, g, b
	end
	return 0, 0.4, 1
end

function Button.Power(f)
	local power = ShowsPower(f)
	if power ~= f.showsPower then
		-- (who shows one changed: a role came, solo ended -- regions only, no
		-- secure geometry)
		Button.Lay(f)
	end
	if not power then
		return
	end
	local pb = f.powerBar
	if f.sample then
		pb:SetMinMaxValues(0, 1)
		pb:SetValue(f.sample.power or 0.7)
	else
		pcall(pb.SetMinMaxValues, pb, 0, UnitPowerMax(f.unit))
		local ok, v = pcall(UnitPower, f.unit)
		if ok then
			SetBar(pb, MelloUI.Units.Value(f.unit, v), DB().smooth)
		end
	end
	local r, g, b = PowerRGB(f)
	pb:SetStatusBarColor(r or 0, g or 0.4, b or 1)
end

-- a name, cut to the setting's length (a plain one; a secret one as it is)
function Button.Name(f)
	local name = f.sample and f.sample.name
	if not f.sample and f.unit then
		local ok, n = pcall(UnitName, f.unit)
		name = ok and n or nil
	end
	local most = DB().nameLength or 0
	if most > 0 and type(name) == "string" and not Secret(name) and #name > most then
		-- (by letters, not bytes: a name's UTF-8 kept whole)
		local cut, count = 0, 0
		for pos = 1, #name do
			local byte = name:byte(pos)
			if byte < 128 or byte >= 192 then
				count = count + 1
				if count > most then
					break
				end
			end
			cut = pos
		end
		name = name:sub(1, cut)
	end
	f.name:SetText(name or "")
	Button.NameColour(f)
end

-- a role's icon (the user, 2026-10-09: "the role icons on the unitframes are
-- too low resolution"): the game's round role badge at 61 px (the dungeon
-- finder's UI-LFG-RoleIcon-*-Micro), the same picture as its 21 px micro icon
-- (GetMicroIconForRole), which shows soft at a frame's size on a sharp screen;
-- that one where this client lacks the large. Asked once per role
local ROLE_SHARP = { TANK = "UI-LFG-RoleIcon-Tank-Micro", HEALER = "UI-LFG-RoleIcon-Healer-Micro",
	DAMAGER = "UI-LFG-RoleIcon-DPS-Micro" }
local roleAtlas = {}
function Button.RoleAtlas(role)
	if not ROLE_SHARP[role] then
		return nil
	end
	local atlas = roleAtlas[role]
	if atlas == nil then
		local CT = rawget(_G, "C_Texture")
		local ok, info = false, nil
		if type(CT) == "table" and type(CT.GetAtlasInfo) == "function" then
			ok, info = pcall(CT.GetAtlasInfo, ROLE_SHARP[role])
		end
		if ok and info then
			atlas = ROLE_SHARP[role]
		else
			local okM, a = pcall(rawget(_G, "GetMicroIconForRole"), role)
			atlas = okM and a or false
		end
		roleAtlas[role] = atlas
	end
	return atlas or nil
end

function Button.Role(f)
	local role = f.sample and f.sample.role
	if not f.sample and f.unit then
		local ok, r = pcall(UnitGroupRolesAssigned, f.unit)
		role = ok and not Secret(r) and r or nil
	end
	local atlas = Button.RoleAtlas(role)
	if atlas and f.roleIcon.SetAtlas then
		f.roleIcon:SetAtlas(atlas)
		f.roleIcon:Show()
	else
		f.roleIcon:Hide()
	end
end

function Button.Mark(f)
	local index = f.sample and f.sample.mark
	if not f.sample and f.unit then
		local ok, i = pcall(GetRaidTargetIndex, f.unit)
		index = ok and not Secret(i) and i or nil
	end
	local set = rawget(_G, "SetRaidTargetIconTexture")
	if type(index) == "number" and type(set) == "function" then
		f.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")   -- look-ok: the game's raid marks
		pcall(set, f.raidIcon, index)
		f.raidIcon:Show()
	else
		f.raidIcon:Hide()
	end
end

function Button.Ready(f, status)
	if status == nil and not f.sample and f.unit then
		local ok, s = pcall(GetReadyCheckStatus, f.unit)
		status = ok and not Secret(s) and s or nil
	elseif f.sample then
		status = f.sample.ready
	end
	local name = status and READY[status]
	local atlas = name and rawget(_G, name)
	if type(atlas) == "string" and f.readyCheckIcon.SetAtlas then
		f.readyCheckIcon:SetAtlas(atlas)
		f.readyCheckIcon:Show()
	else
		f.readyCheckIcon:Hide()
	end
end

-- (2.1.0; the user, 2026-11-03: "...how ... handles out of range party/raid
-- members fade, and update the behaviour to match in Default, Modern and
-- Oldschool theme"; docs/plans/group-range.md) the range rule, one for every
-- frame of a member (these buttons, the portrait party and its pets: GroupSolo):
-- you, and anyone while you are not in a group, always in range; a member in
-- another phase never; else the client's own answer (UnitInRange, about 40
-- yards -- a secret as it is: the client picks the alpha from it); a unit the
-- client does not range (its "checked" false) by the interact distance out of
-- a fight (28 yards), in range in one. Read again on the client's range and
-- phase events, and for every frame as a fight starts or ends (GroupHeaders)
function Button.InRange(unit)
	if not unit or unit == "player" or Ask(UnitIsUnit, unit, "player") == true then
		return true
	end
	if Ask(IsInGroup) ~= true and Ask(IsInRaid) ~= true then
		return true
	end
	if Ask(rawget(_G, "UnitPhaseReason"), unit) ~= nil then
		return false
	end
	local ok, inRange, checked = pcall(UnitInRange, unit)
	if not ok then
		return true
	end
	-- (2.1.22; a player, 2026-11-08: "why does party frames act like im out of range or not close when im near?") the
	-- game's own rule (CompactUnitFrame_UpdateInRange): out only when the client checked the range and the member is
	-- not in it -- an unchecked one answers "not in range" too. This client's answers are secret (UnitInRange's
	-- SecretReturns): a secret "checked" goes with the answer, Button.RangeAlpha joins the two
	if Secret(checked) then
		return inRange, checked
	end
	if checked == false then
		if Ask(InCombatLockdown) ~= true then
			local near = Ask(rawget(_G, "CheckInteractDistance"), unit, 4)
			if near ~= nil then
				return near and true or false
			end
		end
		return true
	end
	if Secret(inRange) then
		return inRange
	end
	return inRange == true
end

-- (2.1.22) f at the client's secret answers: `alpha` only when checked (a secret, or nil: not asked) and not in range,
-- as the game joins them -- C_CurveUtil picks a value from a secret boolean, the second pick from the first's; without
-- it, the answer alone (the frame through SetAlphaFromBoolean)
local function SecretAlpha(f, inRange, checked, alpha)
	local CU = rawget(_G, "C_CurveUtil")
	local pick = CU and CU.EvaluateColorValueFromBoolean
	if pick and Secret(checked) then
		local ok, near = pcall(pick, inRange, 1, alpha)
		local okF, final = false, nil
		if ok then
			okF, final = pcall(pick, checked, near, 1)
		end
		if okF and pcall(f.SetAlpha, f, final) then
			return
		end
	end
	if f.SetAlphaFromBoolean then
		pcall(f.SetAlphaFromBoolean, f, inRange, 1, alpha)
	end
end

-- f faded out of range to `alpha`, whole and at once (away: out of range
-- whatever the rule says -- a member in another group)
function Button.RangeAlpha(f, unit, alpha, away)
	local inRange, checked = false, nil
	if not away then
		inRange, checked = Button.InRange(unit)
	end
	if Secret(inRange) or Secret(checked) then
		SecretAlpha(f, inRange, checked, alpha)
		return
	end
	f:SetAlpha(inRange and 1 or alpha)
end

-- the Out Of Range Opacity (100%: no fade)
function Button.RangeOpacity()
	return DB().rangeAlpha or RANGE_ALPHA
end

-- this button's fade (a made-up member: its outOfRange, so the preview shows it)
function Button.Range(f)
	local alpha = Button.RangeOpacity()
	if f.sample then
		f:SetAlpha(f.sample.outOfRange and alpha < 1 and alpha or 1)
		return
	end
	if alpha >= 1 or not f.unit then
		f:SetAlpha(1)
		return
	end
	Button.RangeAlpha(f, f.unit, alpha)
end

function Button.Refresh(f)
	if not (f.unit or f.sample) then
		return
	end
	Button.Name(f)
	Button.Role(f)
	Button.Mark(f)
	Button.Ready(f)
	Button.Paint(f)
	Button.Health(f)
	Button.Power(f)
	Button.Range(f)
end

-- a made-up member (the Designer's preview, the fake raid): the same frame,
-- the same painters, plain values
function Button.Sample(f, s)
	f.sample = s
	f.unit = nil
	Button.Build(f)
	Button.Lay(f)
	Button.Refresh(f)
end
