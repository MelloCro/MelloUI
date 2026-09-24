--------------------------------------------------------------------------------
-- MelloUI - Stats
--
-- Small FPS / latency readout in the bottom right corner of the screen. The
-- numbers are coloured on a green -> yellow -> red gradient (good -> bad), and
-- hovering the text shows home / world latency, bandwidth and addon memory.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI

local M = MelloUI:RegisterModule("Stats", {
	title = "FPS / Latency",
	desc = "Small coloured FPS and latency readout in the bottom right corner.",
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

local LABEL = "|cff9b8cff"
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
	text:SetShadowColor(0, 0, 0, 0.8)
end

local function ApplyPosition()
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", tonumber(M.db.offsetX) or -12, tonumber(M.db.offsetY) or 8)
end

local function Refresh()
	local db = M.db
	local parts = {}
	if db.showFps then
		local fps = math.floor((GetFramerate() or 0) + 0.5)
		parts[#parts + 1] = FpsColor(fps) .. fps .. "|r" .. LABEL .. " fps|r"
	end
	if db.showLatency then
		local _, _, home, world = GetNetStats()
		home, world = home or 0, world or 0
		local latency = LatencyColor(home) .. home .. "|r"
		if db.worldLatency then
			latency = latency .. LABEL .. "/|r" .. LatencyColor(world) .. world .. "|r"
		end
		parts[#parts + 1] = latency .. LABEL .. " ms|r"
	end
	text:SetText(table.concat(parts, LABEL .. "  |r"))
	local width = text:GetStringWidth() or 0
	frame:SetWidth(math.max(20, width))
	frame:SetHeight(math.max(10, text:GetStringHeight() or 10))
end

local elapsedAcc = 0
frame:SetScript("OnUpdate", function(_, elapsed)
	elapsedAcc = elapsedAcc + elapsed
	if elapsedAcc >= (tonumber(M.db.interval) or 1) then
		elapsedAcc = 0
		Refresh()
	end
end)

frame:SetScript("OnEnter", function(self)
	if not GameTooltip then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
	local bandwidthIn, bandwidthOut, home, world = GetNetStats()
	GameTooltip:AddLine("MelloUI Stats")
	GameTooltip:AddDoubleLine("FPS", string.format("%d", math.floor((GetFramerate() or 0) + 0.5)), 1, 1, 1, Gradient(GetFramerate() or 0, 60, 20))
	GameTooltip:AddDoubleLine("Home latency", string.format("%d ms", home or 0), 1, 1, 1, Gradient(home or 0, 50, 300))
	GameTooltip:AddDoubleLine("World latency", string.format("%d ms", world or 0), 1, 1, 1, Gradient(world or 0, 50, 300))
	GameTooltip:AddDoubleLine("Bandwidth", string.format("%.1f KB/s in, %.1f KB/s out", bandwidthIn or 0, bandwidthOut or 0), 1, 1, 1, 0.8, 0.8, 0.8)
	if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
		UpdateAddOnMemoryUsage()
		local kb = GetAddOnMemoryUsage(ADDON_NAME) or 0
		GameTooltip:AddDoubleLine("MelloUI memory", string.format("%.1f MB", kb / 1024), 1, 1, 1, 0.8, 0.8, 0.8)
	end
	GameTooltip:Show()
end)
frame:SetScript("OnLeave", function()
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
	elapsedAcc = 0
	frame:SetShown(M.isEnabled and (M.db.showFps or M.db.showLatency))
end

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	ApplyAll()
end

function M:OnDisable()
	frame:Hide()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	ApplyAll()
end

MelloUI:Profile("Stats", "fps/latency refresh", frame)
