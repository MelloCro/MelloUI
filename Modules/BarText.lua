--------------------------------------------------------------------------------
-- MelloUI - Bar Text
--
-- Always-visible value text on the health and power bars of the player, target
-- and focus frames ("8.2k", "85", "2.1k / 2.4k", "82%", ...).
--
-- The module keeps its own font strings instead of driving Blizzard's
-- TextStatusBar fields: those fields would be tainted, and Blizzard's text
-- code compares bar values, which fails for secret values while tainted.
-- Blizzard's own text strings are faded out while the module is active so the
-- mouseover text does not draw on top of ours.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("BarText")
local hooksecurefunc = Perf.hooksecurefunc

local M = MelloUI:RegisterModule("BarText", {
	title = "Bar Text",
	desc = "Always show health and power values on the player, target and focus frames.",
	icon = "Interface\\Icons\\INV_Misc_Note_02",
	flavour = "Numbers where they belong. Health and power values, always in view.",
	role = "adds",
	-- (one look Q9 and the user's A, 2026-10-16: no master switch -- the
	-- three frames' own switches are; all three off, nothing of it runs.
	-- Core.lua's MERGES turns them off for a save whose Bar Values was off)
	tweak = { label = "Bar Values", desc = "Health and power values always shown on the player, target and focus frames.", order = 6, always = true },
	switches = { "player", "target", "focus" },
	defaults = {
		player = true,
		target = true,
		focus = true,
		health = true,
		power = true,
		format = "short",   -- (one look C13d: Show Maximum folded in -- shortmax / fullmax / bothmax)
		position = "center",
		offsetX = 0,
		offsetY = 0,
		fontSize = 0,
		valueFont = "shared",
	},
	options = {
		{ type = "header", name = "Frames" },
		{ type = "toggle", key = "player", name = "Player Frame", desc = "Show values on the player frame." },
		{ type = "toggle", key = "target", name = "Target Frame", desc = "Show values on the target frame." },
		{ type = "toggle", key = "focus", name = "Focus Frame", desc = "Show values on the focus frame." },
		{ type = "header", name = "Bars" },
		{ type = "toggle", key = "health", name = "Health Bars", desc = "Show the health value." },
		{ type = "toggle", key = "power", name = "Power Bars", desc = "Show the mana / rage / energy value." },
		{ type = "header", name = "Style" },
		{ type = "dropdown", key = "format", name = "Format", desc = "How the value is written.",
		  values = {
			{ value = "short", label = "Short (8.2k)" },
			{ value = "full", label = "Full (8,234)" },
			{ value = "percent", label = "Percent (82%)" },
			{ value = "both", label = "Short + Percent (8.2k | 82%)" },
			{ value = "shortmax", label = "Short / Max (8.2k / 10k)" },
			{ value = "fullmax", label = "Full / Max (8,234 / 10,000)" },
			{ value = "bothmax", label = "Short / Max + Percent (8.2k / 10k | 82%)" },
		  } },
		{ type = "dropdown", key = "position", name = "Position", desc = "Where the text sits on the bar.",
		  values = {
			{ value = "center", label = "Center" },
			{ value = "left", label = "Left" },
			{ value = "right", label = "Right" },
		  } },
		{ type = "slider", key = "offsetX", name = "Horizontal Offset", min = -30, max = 30, step = 1,
		  format = function(v) return tostring(math.floor(v + 0.5)) end,
		  desc = "Nudge the text left (negative) or right (positive) from where Blizzard places its own bar text." },
		{ type = "slider", key = "offsetY", name = "Vertical Offset", min = -10, max = 10, step = 1,
		  format = function(v) return tostring(math.floor(v + 0.5)) end,
		  desc = "Nudge the text down (negative) or up (positive)." },
		{ type = "slider", key = "fontSize", name = "Font Size", min = 0, max = 20, step = 1,
		  format = function(v) v = math.floor(v + 0.5) return v == 0 and "Default" or tostring(v) end,
		  desc = "Text size. Default follows the status bar text font of the game (and the Fonts module)." },
		{ type = "dropdown", key = "valueFont", name = "Values Font", values = MelloUI.FontFaces,
		  desc = "The face of the health and power values on the player, target and focus frames. Shared: the Interface text's face (Look > Fonts)." },
	},
})

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------

local function Abbreviate(n)
	local sign = n < 0 and "-" or ""
	n = math.abs(n)
	local text
	if n >= 1e9 then
		text = string.format("%.1fb", n / 1e9)
	elseif n >= 1e6 then
		text = string.format("%.1fm", n / 1e6)
	elseif n >= 1e3 then
		text = string.format("%.1fk", n / 1e3)
	else
		return sign .. tostring(math.floor(n + 0.5))
	end
	text = text:gsub("%.0([kmb])$", "%1")
	return sign .. text
end

local function Full(n)
	n = math.floor(n + 0.5)
	local text = tostring(n)
	local sign, digits = text:match("^(%-?)(%d+)$")
	if not digits then
		return text
	end
	digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return sign .. digits
end

local function Percent(value, max)
	if max <= 0 then
		return "0%"
	end
	return string.format("%d%%", math.ceil(value / max * 100))
end

-- the formats that show the maximum too, and those that add the percent (one
-- look C13d: Show Maximum folded into Format)
local FORMAT = { max = { shortmax = true, fullmax = true, bothmax = true }, pct = { both = true, bothmax = true },
	full = { full = true, fullmax = true } }

-- May raise for secret values; always called through pcall.
local function FormatText(value, max)
	local db = M.db
	local fmt = db.format
	if fmt == "percent" then
		return Percent(value, max)
	end
	local number = FORMAT.full[fmt] and Full or Abbreviate
	local text = number(value)
	if FORMAT.max[fmt] then
		text = text .. " / " .. number(max)
	end
	if FORMAT.pct[fmt] then
		text = text .. " | " .. Percent(value, max)
	end
	return text
end

--------------------------------------------------------------------------------
-- Bars
--------------------------------------------------------------------------------

local texts = setmetatable({}, { __mode = "k" }) -- [bar] = FontString
local hooked = setmetatable({}, { __mode = "k" })
-- [bar] = { unit = "player" | "target" | "focus", power = true for a power bar }:
-- a SECRET value is formatted through the unit (the percentage), not the bar
local barUnit = setmetatable({}, { __mode = "k" })
local fontHooked = false
-- (2026-10-21, the user: "when somebody is dead, it shows the dead tag and 0 hp at the same time") a target-like
-- frame's health bar wears the game's own label while its unit is dead or unconscious (TargetFrameMixin:CheckDead:
-- HealthBarsContainer.DeadText / UnconsciousText): the value gives way to it, following its show and hide
local labelsOf = setmetatable({}, { __mode = "k" })    -- [health bar] = { the dead label, the unconscious one }
local barOfLabel = setmetatable({}, { __mode = "k" })  -- [label] = its health bar
local labelShown = setmetatable({}, { __mode = "k" })  -- [health bar] = a label of the game's shows

local function BarList()
	local list = {}
	local db = M.db
	local function Add(frameKey, health, power)
		if not db[frameKey] then
			return
		end
		if db.health and health then
			list[#list + 1] = health
			barUnit[health] = { unit = frameKey }
		end
		if db.power and power then
			list[#list + 1] = power
			barUnit[power] = { unit = frameKey, power = true }
		end
	end
	if PlayerFrame and PlayerFrame.PlayerFrameContent then
		local main = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
		if main then
			Add("player",
				main.HealthBarsContainer and main.HealthBarsContainer.HealthBar,
				main.ManaBarArea and main.ManaBarArea.ManaBar)
		end
	end
	local function TargetLike(frameKey, frame)
		if frame and frame.TargetFrameContent then
			local main = frame.TargetFrameContent.TargetFrameContentMain
			if main then
				local box = main.HealthBarsContainer
				local health = box and box.HealthBar
				Add(frameKey, health, main.ManaBar)
				if health and not labelsOf[health] then
					labelsOf[health] = { box.DeadText, box.UnconsciousText }
				end
			end
		end
	end
	TargetLike("target", TargetFrame)
	TargetLike("focus", FocusFrame)
	return list
end

local function SetBlizzardTextAlpha(bar, alpha)
	local keys = { "TextString", "LeftText", "RightText" }
	for _, key in ipairs(keys) do
		local fs = bar[key]
		if fs and fs.SetAlpha then
			fs:SetAlpha(alpha)
		end
	end
end

local function ApplyFont(fs)
	local object = TextStatusBarText or GameFontHighlightSmall
	local size = math.floor((tonumber(M.db.fontSize) or 0) + 0.5)
	-- (one look C11: the values' own face, Values Font; Shared the object's)
	local face = MelloUI:FaceOf(M.db.valueFont)
	if (size <= 0 and not face) or not object then
		if object then
			fs:SetFontObject(object)
		end
		return
	end
	local path, own, flags = object:GetFont()
	if size <= 0 then
		-- (the object's own size; none readable: the object as it is)
		size = MelloUI.Safe.Number(own)
		if not size then
			fs:SetFontObject(object)
			return
		end
		-- (the picked face's own correction in place of the object's face's)
		size = MelloUI:FaceSize(size, face, path)
	end
	path = face or path
	if path then
		fs:SetFont(path, size, flags or "")
	end
end

-- Some bars are wider than their visible part (the target power bar runs
-- under the portrait, for example). Blizzard's own text strings carry the
-- offsets that compensate for that, so anchor to them when they exist and
-- fall back to the bar itself otherwise.
-- (2026-10-20, the user: drag the values on the frames; docs/plans/preview-drag.md) a frame's own place for one of
-- its values, set on the Unit & Group Frames designer's stage: Unit Frames' `parts` (M.PartPlace there), or nil
local function PlaceOf(frameKey, power)
	local uf = frameKey and MelloUI.modules.UnitFrames
	return uf and uf.PartPlace and uf.PartPlace(frameKey, power and "power" or "health") or nil
end

local function ApplyPosition(fs, bar, frameKey, power)
	local unit = barUnit[bar]
	if frameKey == nil and unit then
		frameKey, power = unit.unit, unit.power
	end
	local uf = MelloUI.modules.UnitFrames
	local place = PlaceOf(frameKey, power)
	if place and uf.LayPlace then
		uf.LayPlace(fs, bar, place)
		return
	end
	if uf and uf.UnlayPlace then
		uf.UnlayPlace(fs)
	end
	local position = M.db.position
	local dx = math.floor((tonumber(M.db.offsetX) or 0) + 0.5)
	local dy = math.floor((tonumber(M.db.offsetY) or 0) + 0.5)
	local point, ref, fallbackX
	if position == "left" then
		point, ref, fallbackX = "LEFT", bar.LeftText, 3
	elseif position == "right" then
		point, ref, fallbackX = "RIGHT", bar.RightText, -3
	else
		point, ref, fallbackX = "CENTER", bar.TextString, 0
	end
	fs:ClearAllPoints()
	if ref and ref ~= fs and ref.GetObjectType and ref:GetObjectType() == "FontString" then
		fs:SetPoint(point, ref, point, dx, dy)
	else
		fs:SetPoint(point, bar, point, fallbackX + dx, dy)
	end
	fs:SetJustifyH(point)
end

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

-- A SECRET value in the chosen format. The client refuses to compare a secret
-- or do arithmetic on it, but it lets one be joined into text, formatted and
-- abbreviated, the result staying secret and still showable (/mello secrets on
-- this client, 2026-09-23). So: AbbreviateNumbers for the short form, the
-- game's own percentage of the unit for the percent, the pieces joined.
-- Nothing here tests or compares the value.
local function SecretPercent(bar)
	local info = barUnit[bar]
	if not (info and CurveConstants) then
		return nil
	end
	local pct
	if info.power then
		if not UnitPowerPercent then
			return nil
		end
		pct = UnitPowerPercent(info.unit, nil, true, CurveConstants.ScaleTo100)
	else
		if not UnitHealthPercent then
			return nil
		end
		pct = UnitHealthPercent(info.unit, true, CurveConstants.ScaleTo100)
	end
	if C_StringUtil and C_StringUtil.RoundToNearestString then
		local ok, rounded = pcall(C_StringUtil.RoundToNearestString, pct)
		if ok and (Secret(rounded) or rounded) then
			return rounded .. "%"
		end
	end
	return string.format("%d%%", pct)
end

local function SecretNumber(n)
	if FORMAT.full[M.db.format] then
		-- 8,234 where the client can group a secret, else 8234
		local ok, text = pcall(BreakUpLargeNumbers, n)
		if ok and (Secret(text) or text) then
			return text
		end
		return string.format("%d", n)
	end
	return AbbreviateNumbers(n)
end

local function SecretText(bar, value, max)
	local fmt = M.db.format
	if fmt == "percent" then
		-- a unit with no percentage to read (a power type the client does not
		-- give one for): the short number rather than nothing
		local okP, pct = pcall(SecretPercent, bar)
		if okP and (Secret(pct) or pct) then
			return pct
		end
		return AbbreviateNumbers(value)
	end
	local text = SecretNumber(value)
	if FORMAT.max[fmt] then
		text = text .. " / " .. SecretNumber(max)
	end
	if FORMAT.pct[fmt] then
		local okP, pct = pcall(SecretPercent, bar)
		if okP and (Secret(pct) or pct) then
			text = text .. " | " .. pct
		end
	end
	return text
end

-- Runs under pcall for anything unexpected, but a SECRET value is asked about
-- first and never compared: comparing one is blocked by the client and logged
-- as taint every time (Logs/taint.log, ~88 a session from here until
-- 2026-09-23), even though the pcall hid it. Secret: formatted by SecretText,
-- which only joins and abbreviates (user, 2026-09-23: the text had fallen back
-- to the raw number in every fight).
local function ReadBar(bar)
	local value = bar:GetValue()
	local _, max = bar:GetMinMaxValues()
	if Secret(value) or Secret(max) then
		return SecretText(bar, value, max)
	end
	if not max or max <= 0 then
		return nil
	end
	return FormatText(value, max)
end

local function SetRawValue(fs, bar)
	fs:SetText(bar:GetValue())
end

-- a label of the game's on the bar shows (a secret answer counts as hidden)
local function GameLabel(bar)
	local labels = labelsOf[bar]
	if not labels then
		return false
	end
	for i = 1, 2 do
		local label = labels[i]
		if label then
			local ok, shown = pcall(label.IsShown, label)
			if ok and not Secret(shown) and shown then
				return true
			end
		end
	end
	return false
end

-- Called on every value change of every tracked bar, so no closures here.
local function UpdateBar(bar)
	local fs = texts[bar]
	if not fs then
		return
	end
	if not M.isEnabled or not fs.active then
		fs:Hide()
		return
	end
	if GameLabel(bar) then
		fs.lastText = nil
		fs:Hide()
		return
	end
	local ok, text = pcall(ReadBar, bar)
	-- a secret text is set as it is: comparing it with the last one is refused
	if ok and Secret(text) then
		fs.lastText = nil
		fs:SetText(text)
		fs:Show()
		return
	end
	if ok and text then
		if text ~= fs.lastText then
			fs.lastText = text
			fs:SetText(text)
		end
		fs:Show()
		return
	end
	-- Formatting failed (an API this client lacks): the raw value if the
	-- client lets us show it, otherwise nothing.
	fs.lastText = nil
	local shown = pcall(SetRawValue, fs, bar)
	if shown then
		fs:Show()
	else
		fs:SetText("")
		fs:Hide()
	end
end

local function RefreshAll()
	for bar in pairs(texts) do
		UpdateBar(bar)
	end
end

-- a game label shown or hidden (the game runs CheckDead on every health event:
-- the value is laid again only when a label's state changed)
local function LabelChanged(label)
	local bar = barOfLabel[label]
	if not bar then
		return
	end
	local now = GameLabel(bar)
	if now ~= labelShown[bar] then
		labelShown[bar] = now
		UpdateBar(bar)
	end
end

local function EnsureText(bar)
	local fs = texts[bar]
	if not fs then
		fs = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
		texts[bar] = fs
	end
	if not hooked[bar] then
		hooked[bar] = true
		Perf.HookScript(bar, "OnValueChanged", function(self) UpdateBar(self) end)
		Perf.HookScript(bar, "OnMinMaxChanged", function(self) UpdateBar(self) end)
		Perf.HookScript(bar, "OnShow", function(self) UpdateBar(self) end)
		-- (the game's dead and unconscious labels: post-hooks, nothing written on them)
		for _, label in ipairs(labelsOf[bar] or {}) do
			if label.Show and not barOfLabel[label] then
				barOfLabel[label] = bar
				hooksecurefunc(label, "Show", LabelChanged)
				hooksecurefunc(label, "Hide", LabelChanged)
				hooksecurefunc(label, "SetShown", LabelChanged)
			end
		end
		labelShown[bar] = GameLabel(bar)
	end
	return fs
end

local function HookFontObject()
	if fontHooked or not TextStatusBarText then
		return
	end
	fontHooked = true
	-- The Fonts module changes the font object; keep an explicit size in sync.
	hooksecurefunc(TextStatusBarText, "SetFont", function()
		if M.isEnabled then
			for _, fs in pairs(texts) do
				if fs.active then
					ApplyFont(fs)
				end
			end
		end
	end)
end

local function ApplyAll()
	HookFontObject()
	local wanted = {}
	for _, bar in ipairs(BarList()) do
		wanted[bar] = true
	end
	for bar, fs in pairs(texts) do
		if not wanted[bar] then
			fs.active = false
			fs:Hide()
			SetBlizzardTextAlpha(bar, 1)
		end
	end
	for bar in pairs(wanted) do
		local fs = EnsureText(bar)
		fs.active = true
		ApplyFont(fs)
		ApplyPosition(fs, bar)
		SetBlizzardTextAlpha(bar, 0)
		UpdateBar(bar)
	end
end

local function RemoveAll()
	for bar, fs in pairs(texts) do
		fs.active = false
		fs.lastText = nil
		fs:SetText("")
		fs:Hide()
		SetBlizzardTextAlpha(bar, 1)
	end
end

--------------------------------------------------------------------------------
-- The Configurator's unit frame preview (0.15.0, Core/ConfigPreview.lua):
-- the value text of SAMPLE numbers, as this module writes and places it on
-- the frames (one system for the text: the preview copies none of it). No
-- bar of the game and no unit is read, and nothing is kept.
--   M.PreviewText(value, max) -> the text FormatText makes for two plain
--       numbers ("8.6k", "8,640 / 12,000", "72%" ...), or nil (not two plain
--       numbers, max 0 or less, the settings not read yet)
--   M.PreviewPlace(fs, bar)   the chosen font size and place on the
--       preview's own font string and bar (a bar with no game text strings:
--       placed on the bar's own edges, as a frame without them is)
--   M.PreviewShows(frameKey, power) -> true while this module shows the
--       value on that frame's ("player", "target", "focus") health bar, or
--       its power bar with `power`: the module on, the frame's and the
--       bar's switches on (BarList's rule)
--------------------------------------------------------------------------------

function M.PreviewText(value, max)
	if not M.db or type(value) ~= "number" or type(max) ~= "number" or Secret(value) or Secret(max) or max <= 0 then
		return nil
	end
	return FormatText(value, max)
end

-- (the configurator's copy: frameKey and power name the frame's own place, as its real bar has it)
function M.PreviewPlace(fs, bar, frameKey, power)
	if M.db and fs and bar then
		ApplyFont(fs)
		ApplyPosition(fs, bar, frameKey or false, power)
	end
end

function M.PreviewShows(frameKey, power)
	local db = M.db
	return (M.isEnabled and db and db[frameKey] and db[power and "power" or "health"]) and true or false
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
Perf.SetScript(frame, "OnEvent", function()
	if M.isEnabled then
		RefreshAll()
	end
end)

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function M:OnInit(db)
	self.db = db
end

-- (0.19.8) switched on after the login's PLAYER_ENTERING_WORLD (Core's
-- start-up pass over the login's first frames): that event as it came
function M:OnLoginWorld(...)
	MelloUI:ReplayWorld(frame, ...)
end

-- (one look Q9: the three frames' switches are its switches) its events
-- and its texts only while one of them is on: all three off, nothing at all
local function AnyFrame()
	local db = M.db
	return M.isEnabled and db and (db.player or db.target or db.focus) and true or false
end

local function Listen()
	if AnyFrame() then
		frame:RegisterEvent("PLAYER_TARGET_CHANGED")
		frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
		frame:RegisterEvent("PLAYER_ENTERING_WORLD")
		frame:RegisterEvent("UNIT_DISPLAYPOWER")
		ApplyAll()
	else
		frame:UnregisterAllEvents()
		RemoveAll()
	end
end

function M:OnEnable(db)
	self.db = db
	Listen()
end

function M:OnDisable()
	frame:UnregisterAllEvents()
	RemoveAll()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	Listen()
end

-- a value moved on the designer's stage (Unit Frames' `parts`): every value laid again, once
MelloUI:On("setting", Perf.Shared("'setting' on the bus: Bar Text's places (Unit Frames' parts)", function(name, key)
	if name == "UnitFrames" and key == "parts" and AnyFrame() then
		ApplyAll()
	end
end), "BarText places")

MelloUI:Profile("BarText", "bar value updates", UpdateBar)
