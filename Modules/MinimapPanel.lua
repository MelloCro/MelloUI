--------------------------------------------------------------------------------
-- MelloUI - Minimap Panel
--
-- The minimap cluster dressed in the painted kit (Modules/Kit.lua) on the
-- game's own layout. This client (Blizzard_Minimap/Camelot/Skin.lua) draws a
-- round frame (UI-HUD-Minimap-Frame, 215 x 226) around the 198 px map, the
-- zone band (BorderTop, 175 x 16) above it with the tracking button on its
-- left. User's picks (kit_raw/minimap_catalog.png, 2026-09-21): R1 Z2.
--   R1  the frame → the portrait ring sized from the map's opening x 0.75
--       (user: a quarter smaller, the map untouched), its rim over the map's
--       edge, on a holder one level above the map; the band, its text, the
--       tracking button and the indicators raised above the ring
--   Z2  the zone band → the title plate, as the band's own regions (under
--       its text), standing on the ring's top rim as a title on a rail
--   the tracking button's round plate → the round rim; zoom in / out → the
--   kit's plus / minus. The calendar, mail, crafting-order, landing-page and
--   day / night dial pictures, the compass letters and MelloUI's Services bar
--   stay the game's.
-- Covers the Dark Mode group "minimap". /mmdump [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("MinimapPanel", {
	title = "Minimap Kit",
	desc = "The minimap cluster dressed in the painted kit on the game's own layout.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil
local active = false

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Minimap: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

local function Build()
	if skin then
		return
	end
	skin = { reps = {} }
	local cluster = MinimapCluster
	local map = Minimap
	if not (cluster and map) then
		return
	end
	-- the ring (R1): the frame and its rotated-mode pointer / underlay faded,
	-- the ring on a holder at the cluster's level with its opening on the map
	-- the ring one level above the map (its rim lies over the map's edge at
	-- 0.75); the band, its text, the tracking button and the indicators are
	-- raised one level above the ring (they overlap its top), their game
	-- levels put back on disable
	local ringLevel = map:GetFrameLevel() + 1
	if MinimapCompassTexture then
		local rep = Replace(MinimapCompassTexture, { as = "UI-HUD-Minimap-Frame", parent = cluster, rect = map, level = ringLevel - cluster:GetFrameLevel(),
			alsoFade = { MinimapCompassTextureUnderlay } })
		if rep then
			local raised = {}
			for _, key in ipairs({ "BorderTop", "ZoneTextButton", "Tracking", "IndicatorFrame" }) do
				local f = cluster[key]
				if f then
					raised[#raised + 1] = { frame = f, level = f:GetFrameLevel() }
				end
			end
			if GameTimeFrame then
				raised[#raised + 1] = { frame = GameTimeFrame, level = GameTimeFrame:GetFrameLevel() }
			end
			rep.onEnable = function()
				for _, entry in ipairs(raised) do
					entry.frame:SetFrameLevel(math.max(ringLevel + 1, entry.level))
				end
			end
			rep.onDisable = function()
				for _, entry in ipairs(raised) do
					entry.frame:SetFrameLevel(entry.level)
				end
			end
			if active then
				rep.onEnable()
			end
		end
	end
	-- the zone band (Z2): the nine-slice's textures faded, the plate as regions
	local band = cluster.BorderTop
	if band then
		local first, extra = nil, {}
		for _, region in ipairs({ band:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not region.kitPiece then
				if first then
					extra[#extra + 1] = region
				else
					first = region
				end
			end
		end
		if first then
			local rep = Replace(first, { as = "MinimapZoneBand", rect = band, alsoFade = extra })
			if rep and MinimapCluster and Kit.RegisterShell then
				-- the cluster's drag handle for the window mover: a grab frame
				-- on the band's own rect (the plate is 1.4 x the band and its
				-- canvas taller than its painted box, so the plate's frame
				-- made an odd click box — user, 2026-09-21)
				local grab = CreateFrame("Frame", nil, band:GetParent() or MinimapCluster)
				grab:SetAllPoints(band)
				grab:SetFrameLevel((band:GetFrameLevel() or 1) + 5)
				grab:EnableMouse(false)
				Kit:RegisterShell(MinimapCluster, { title = grab })
			end
			-- the zone text centred on the plate (user, 2026-09-21); the game's
			-- anchor (LEFT-justified in its button) put back on disable
			local text = MinimapZoneText
			if rep and text then
				local saved = { justify = text:GetJustifyH() }
				for i = 1, text:GetNumPoints() do
					saved[i] = { text:GetPoint(i) }
				end
				local enable = rep.onEnable
				rep.onEnable = function(...)
					if enable then
						enable(...)
					end
					text:ClearAllPoints()
					text:SetPoint("CENTER", band, "CENTER", 0, 0)
					text:SetJustifyH("CENTER")
					Kit:TitleFont(text, true)
				end
				rep.onDisable = function()
					Kit:TitleFont(text, false)
					text:ClearAllPoints()
					for _, pt in ipairs(saved) do
						if type(pt) == "table" then
							text:SetPoint(unpack(pt))
						end
					end
					text:SetJustifyH(saved.justify or "LEFT")
				end
				if active then
					rep.onEnable()
				end
			end
		end
	end
	-- the tracking button's plate, the zoom buttons
	local tracking = cluster.Tracking
	if tracking and tracking.Background then
		Replace(tracking.Background, { as = "ui-hud-minimap-button" })
	end
	for _, entry in ipairs({ { map.ZoomIn, "ui-hud-minimap-zoom-in" }, { map.ZoomOut, "ui-hud-minimap-zoom-out" } }) do
		local button, key = entry[1], entry[2]
		if button and button.GetNormalTexture and button:GetNormalTexture() then
			Replace(button:GetNormalTexture(), { as = key, button = button,
				alsoFade = { button:GetPushedTexture(), button:GetHighlightTexture(), button:GetDisabledTexture() } })
		end
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
	Kit:Cover("minimap")
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	Kit:Uncover("minimap")
end

function M:OnEnable(db)
	self.db = db
	if MinimapCluster then
		Activate()
	end
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /mmdump [frames|reps]: the cluster's art. Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOMMDUMP1 = "/mmdump"
SlashCmdList.MELLOMMDUMP = function(msg)
	msg = (msg or ""):lower()
	MelloUI:ClearLog()
	if not MinimapCluster then
		MelloUI:Print("No minimap cluster.")
	else
		MelloUI:Print("== MinimapCluster  %s L%d; Minimap L%d; backdrop L%d", MinimapCluster:GetFrameStrata(), MinimapCluster:GetFrameLevel(),
			Minimap and Minimap:GetFrameLevel() or -1, MinimapBackdrop and MinimapBackdrop:GetFrameLevel() or -1)
		Kit:DumpWindow(MinimapCluster, skin, msg ~= "" and msg or nil)
	end
	MelloUI:ShowLog("mmdump " .. msg)
end
