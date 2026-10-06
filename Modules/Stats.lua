--------------------------------------------------------------------------------
-- MelloUI - Stats
--
-- Small FPS / latency readout in the bottom right corner of the screen. The
-- numbers are coloured on a green -> yellow -> red gradient (good -> bad), and
-- hovering the text shows home / world latency, bandwidth and addon memory.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Stats")
local C_Timer = Perf.C_Timer

local M = MelloUI:RegisterModule("Stats", {
	title = "FPS / Latency",
	desc = "Small coloured FPS and latency readout in the bottom right corner.",
	icon = "Interface\\Icons\\Spell_Nature_Lightning",
	flavour = "Frames per second and latency in the corner. Blame the server with confidence.",
	role = "adds",
	tweak = { label = "FPS / Latency", desc = "A small coloured FPS and latency readout in the bottom right corner.", order = 14 },
	defaults = {
		showFps = true,
		showLatency = true,
		worldLatency = false,
		fontSize = 12,
		offsetX = -12,
		offsetY = 8,
		interval = 1,
	},
	options = {
		{ type = "header", name = "Values" },
		{ type = "toggle", key = "showFps", name = "Show FPS", desc = "Frames per second." },
		{ type = "toggle", key = "showLatency", name = "Show Latency", desc = "Home latency in milliseconds." },
		{ type = "toggle", key = "worldLatency", parent = "showLatency", name = "Show World Latency Too",
		  desc = "Also show the world server latency next to the home latency." },
		{ type = "header", name = "Look" },
		{ type = "slider", key = "fontSize", name = "Font Size", min = 8, max = 20, step = 1,
		  format = function(v) return tostring(math.floor(v + 0.5)) end },
		{ type = "slider", key = "offsetX", name = "Horizontal Offset", min = -400, max = 0, step = 1,
		  format = function(v) return tostring(math.floor(v + 0.5)) end,
		  desc = "Distance from the right edge of the screen." },
		{ type = "slider", key = "offsetY", name = "Vertical Offset", min = 0, max = 400, step = 1,
		  format = function(v) return tostring(math.floor(v + 0.5)) end,
		  desc = "Distance from the bottom edge of the screen." },
		{ type = "slider", key = "interval", name = "Update Interval", min = 0.5, max = 5, step = 0.5,
		  format = function(v) return string.format("%.1fs", v) end },
	},
})

--------------------------------------------------------------------------------
-- Colours
--------------------------------------------------------------------------------

-- Returns a colour on a green -> yellow -> red gradient. 'good' maps to
-- green, 'bad' maps to red, anything in between is blended.
local function Gradient(value, good, bad)
	local t
	if good < bad then
		t = (value - good) / (bad - good)
	else
		t = (good - value) / (good - bad)
	end
	if t < 0 then t = 0 elseif t > 1 then t = 1 end
	local r, g
	if t < 0.5 then
		r, g = t * 2, 1
	else
		r, g = 1, 1 - (t - 0.5) * 2
	end
	return r, g, 0.15
end

local function Hex(r, g, b)
	return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function FpsColor(fps)
	return Hex(Gradient(fps, 60, 20))
end

local function LatencyColor(ms)
	return Hex(Gradient(ms, 50, 300))
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

-- The labels (fps, ms, the separators) in the palette's text colour, as a
-- colour code: made again when the palette is a new table (0.14.0: the
-- palettes; the numbers keep their good -> bad gradient, a meaning colour).
-- The palette as MelloUI.Look shows it: the game's white with the reskin off
-- (docs/plans/game-look.md), its own table, so a switch makes them again.
local label = { from = nil, code = nil, gap = nil }

local function Label()
	local palette = MelloUI.Look.Palette()
	if label.from ~= palette then
		label.from = palette
		label.code = MelloUI:PaletteCode("text")
		label.gap = label.code .. "  |r"
	end
	return label.code
end

local frame = CreateFrame("Frame", "MelloUIStatsFrame", UIParent)
frame:SetSize(120, 16)
frame:SetFrameStrata("LOW")
frame:EnableMouse(true)
frame:Hide()

local text = frame:CreateFontString(nil, "OVERLAY")
text:SetFontObject(GameFontHighlightSmall or GameFontNormal)
text:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
text:SetJustifyH("RIGHT")

local function ApplyFont()
	local object = GameFontHighlightSmall or SystemFont_Shadow_Small
	local path = object:GetFont()
	if path then
		text:SetFont(path, tonumber(M.db.fontSize) or 12, "OUTLINE")
	end
	text:SetShadowOffset(1, -1)
	-- the palette's inner panel as the shadow (read when applied; again on
	-- 'palette'; the reskin off: the game's black)
	MelloUI.Look.Shadow(text, 0.8)
end

local function ApplyPosition()
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", tonumber(M.db.offsetX) or -12, tonumber(M.db.offsetY) or 8)
end

-- the readout's pieces, one table for every refresh (a new one each interval
-- before; user, 2026-09-24: no garbage on the hot paths)
local parts = {}

local function Refresh()
	local db = M.db
	local n = 0
	local LABEL = Label()
	if db.showFps then
		local fps = math.floor((GetFramerate() or 0) + 0.5)
		n = n + 1
		parts[n] = FpsColor(fps) .. fps .. "|r" .. LABEL .. " fps|r"
	end
	if db.showLatency then
		local _, _, home, world = GetNetStats()
		home, world = home or 0, world or 0
		local latency = LatencyColor(home) .. home .. "|r"
		if db.worldLatency then
			latency = latency .. LABEL .. "/|r" .. LatencyColor(world) .. world .. "|r"
		end
		n = n + 1
		parts[n] = latency .. LABEL .. " ms|r"
	end
	text:SetText(table.concat(parts, label.gap, 1, n))
	local width = text:GetStringWidth() or 0
	frame:SetWidth(math.max(20, width))
	frame:SetHeight(math.max(10, text:GetStringHeight() or 10))
end

-- The refresh rides a ticker at the chosen interval, running only while the
-- readout shows (user, 2026-09-24: no idle work): an OnUpdate counted every
-- frame up to the interval before. A new interval starts a new ticker.
local ticker, tickerEvery = nil, nil

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker, tickerEvery = nil, nil
	end
end

local function StartTicker()
	local every = tonumber(M.db and M.db.interval) or 1
	if ticker and tickerEvery == every then
		return
	end
	StopTicker()
	ticker, tickerEvery = C_Timer.NewTicker(every, Refresh), every
end

-- hidden with its parent too (the interface hidden): the ticker goes with it
Perf.SetScript(frame, "OnShow", StartTicker)
Perf.SetScript(frame, "OnHide", StopTicker)

Perf.SetScript(frame, "OnEnter", function(self)
	if not GameTooltip then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
	local bandwidthIn, bandwidthOut, home, world = GetNetStats()
	-- the palette's gold and text, as MelloUI's one tooltip (W.ShowTooltip);
	-- the FPS and latency figures keep their good -> bad gradient
	local P = MelloUI.Look.Palette()   -- (the reskin off: the game's gold and white)
	local gold, ink = P.selectedTrim, P.text
	GameTooltip:AddLine("MelloUI Stats", gold[1], gold[2], gold[3])
	GameTooltip:AddDoubleLine("FPS", string.format("%d", math.floor((GetFramerate() or 0) + 0.5)), ink[1], ink[2], ink[3], Gradient(GetFramerate() or 0, 60, 20))
	GameTooltip:AddDoubleLine("Home latency", string.format("%d ms", home or 0), ink[1], ink[2], ink[3], Gradient(home or 0, 50, 300))
	GameTooltip:AddDoubleLine("World latency", string.format("%d ms", world or 0), ink[1], ink[2], ink[3], Gradient(world or 0, 50, 300))
	GameTooltip:AddDoubleLine("Bandwidth", string.format("%.1f KB/s in, %.1f KB/s out", bandwidthIn or 0, bandwidthOut or 0),
		ink[1], ink[2], ink[3], ink[1], ink[2], ink[3])
	-- with the route data companion's once it is loaded (MelloUI:MemoryKB,
	-- Core/Companions.lua): the data lives next door now, and MelloUI's own
	-- figure alone would show a drop that is not there
	local kb = MelloUI.MemoryKB and MelloUI:MemoryKB()
	if not kb and UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
		UpdateAddOnMemoryUsage()
		kb = GetAddOnMemoryUsage(ADDON_NAME) or 0
	end
	if kb then
		GameTooltip:AddDoubleLine("MelloUI memory", string.format("%.1f MB", kb / 1024), ink[1], ink[2], ink[3], ink[1], ink[2], ink[3])
	end
	GameTooltip:Show()
end)
Perf.SetScript(frame, "OnLeave", function()
	if GameTooltip then
		GameTooltip:Hide()
	end
end)

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

local function ApplyAll()
	ApplyFont()
	ApplyPosition()
	Refresh()
	frame:SetShown(M.isEnabled and (M.db.showFps or M.db.showLatency))
	-- shown already, OnShow does not come again: a new interval is taken here
	if frame:IsVisible() then
		StartTicker()
	else
		StopTicker()
	end
end

-- A new palette: the shadow and the labels in it at once (the ticker would
-- bring the labels only at its next beat). Only a palette TABLE the readout
-- was not drawn in: 'palette' goes out for a Kit Colours change too, the
-- palette unchanged
local function OnPalette()
	if M.isEnabled and M.db and label.from ~= MelloUI.Look.Palette() then
		ApplyFont()
		Label()
		if frame:IsShown() then
			Refresh()
		end
	end
end

-- A new face or Font Style (Look > Fonts): the readout in it at once, its
-- width measured again (0.19.4, the options audit: it waited for a change
-- of its own settings)
local function OnFonts()
	if M.isEnabled and M.db then
		ApplyFont()
		if frame:IsShown() then
			Refresh()
		end
	end
end

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	-- (one listener: On again with the same owner keeps it)
	MelloUI:On("palette", OnPalette, "Stats")
	MelloUI:On("look:own", OnPalette, "Stats")   -- (the reskin switched: the game's colours, or the palette)
	MelloUI:On("fonts", OnFonts, "Stats")
	ApplyAll()
end

function M:OnDisable()
	frame:Hide()
	StopTicker()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	ApplyAll()
end

MelloUI:Profile("Stats", "fps/latency refresh", Refresh)
