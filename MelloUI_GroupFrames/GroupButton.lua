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
--   Button.Sample(f, s)     a made-up member: s = { class, name, health (0..1),
--                           power (0..1), role, dead, offline, mark, ready }
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
	return Answer(pcall(UnitIsDeadOrGhost, unit)) == true
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
		return 0.5, 0.5, 0.5
	end
	local CC = rawget(_G, "C_ClassColor")
	if type(CC) == "table" and type(CC.GetClassColor) == "function" then
		local ok, c = pcall(CC.GetClassColor, class)
		if ok and c and c.GetRGB then
			return c:GetRGB()
		end
	end
	if not Secret(class) then
		local t = rawget(_G, "RAID_CLASS_COLORS") and RAID_CLASS_COLORS[class]
		if t then
			return t.r, t.g, t.b
		end
	end
	return 0.5, 0.5, 0.5
end
Button.ClassRGB = ClassRGB

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

local curve = { key = nil, obj = nil }

local function HealthCurve()
	local db = DB()
	local key = tostring(db.healthLow) .. "|" .. tostring(db.healthMid) .. "|" .. tostring(db.healthHigh)
	if curve.key == key then
		return curve.obj
	end
	curve.key, curve.obj = key, nil
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

function Button.Build(f)
	if f.healthBar then
		return f
	end
	f.background = f:CreateTexture(nil, "BACKGROUND")
	f.background:SetAllPoints(f)
	f.background:SetTexture(WHITE)
	f.healthBar = Bar(f)
	f.healthBar:SetMinMaxValues(0, 100)
	f.missingBar = Bar(f.healthBar)
	f.missingBar:SetAllPoints(f.healthBar)
	f.powerBar = Bar(f)
	f.name = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.name:SetWordWrap(false)
	f.statusText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
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
	local file = W.BarFill("raidframes")
	for _, b in ipairs({ hb, f.missingBar, pb }) do
		b:SetStatusBarTexture(file)
	end
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
		ns.Parts:Lay(f, true)
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
	local bgR, bgG, bgB = ModeRGB(f, db.background, "backgroundCustom")
	f.background:SetVertexColor(bgR or 0, bgG or 0, bgB or 0, db.backgroundAlpha or 0.9)
	local fill = Looks.Fill(f.healthBar)
	if fill then
		fill:SetAlpha(db.healthAlpha or 1)
	end
	if db.healthColour ~= "health" then
		local r, g, b = ModeRGB(f, db.healthColour, "healthCustom")
		if r then
			f.healthBar:SetStatusBarColor(r, g, b)
		end
	end
	local mode = db.missing or "off"
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
			local ok, m = pcall(UnitHealthMissing, unit, true)
			if ok then
				SetBar(f.missingBar, m, db.smooth)
			end
		end
		HealthText(f, pct)
	end
	if f.sample then
		HealthText(f, nil)
	end
	-- the colours that follow the health
	if f.offline or f.dead then
		hb:SetStatusBarColor(0.5, 0.5, 0.5)
	elseif db.healthColour == "health" then
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
	local pc = rawget(_G, "PowerBarColor") and PowerBarColor[token]
	if type(pc) == "table" and type(pc.r) == "number" then
		return pc.r, pc.g, pc.b
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
			SetBar(pb, v, DB().smooth)
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

-- out of range: the frame faded (the client's answer, secret or not: the
-- alpha chosen from it by the client)
function Button.Range(f)
	local db = DB()
	if not db.rangeFade or f.sample or not f.unit or f.unit == "player" then
		f:SetAlpha(1)
		return
	end
	local ok, inRange, checked = pcall(UnitInRange, f.unit)
	if not ok then
		f:SetAlpha(1)
		return
	end
	if not Secret(checked) and checked == false then
		f:SetAlpha(1)   -- (not checked: a unit the client cannot range)
		return
	end
	local alpha = db.rangeAlpha or 0.45
	if Secret(inRange) and f.SetAlphaFromBoolean then
		pcall(f.SetAlphaFromBoolean, f, inRange, 1, alpha)
	elseif not Secret(inRange) then
		f:SetAlpha(inRange and 1 or alpha)
	end
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
