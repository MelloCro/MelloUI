--------------------------------------------------------------------------------
-- MelloUI - Party Markers
--
-- A class medallion above every party or raid member's friendly nameplate
-- (user, 2026-09-22: "where the healer is, at a glance"; picks PM4 PR3 from
-- kit_raw/partymark_catalog.png): the medallion alone, larger than a
-- portrait's, and a coloured ring around it for the member's assigned
-- group role (green healer, blue tank, red damage) when the group has
-- roles set. Rides on the game's friendly nameplates: nothing else can
-- hang over a player's head (the controller's interact icon is the same
-- mechanism, the nameplate's SoftTargetFrame). INSIDE INSTANCES the engine
-- draws friendly nameplates on its own side and hands none of them to Lua
-- (/pmdump lists 0 plates there even with forbidden ones included; user,
-- 2026-09-22): no addon can mark them there. The open world is where the
-- markers show.
--
-- Every unit read on a nameplate can be secret on this client: all of them
-- go through pcall and a plainness check; a marker is only drawn when the
-- class is readable.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("PartyMarkers")

local defaults = {
	who = "group",          -- "group": party and raid members; "friends": every friendly player
	size = 30,
	roleRing = true,
	offset = 4,             -- px above the name
}

local options = {
	{ type = "header", name = "Markers" },
	{ type = "dropdown", key = "who", name = "Mark", values = {
		{ value = "group", label = "Party and raid members" },
		{ value = "friends", label = "Every friendly player" },
	}, desc = "Whose nameplate gets the class medallion above the name." },
	{ type = "slider", key = "size", name = "Marker Size", min = 16, max = 150, step = 2,
	  format = function(v) return string.format("%d px", v) end,
	  desc = "The medallion's size above the name." },
	{ type = "slider", key = "offset", name = "Height Above The Name", min = 0, max = 20, step = 1,
	  format = function(v) return string.format("%d px", v) end,
	  desc = "The gap between the name and the medallion." },
	{ type = "toggle", key = "roleRing", name = "Role Ring",
	  desc = "A coloured ring around the medallion for the member's assigned role: green healer, blue tank, red damage. Only when the group has roles set (the group finder sets them; a party can set them by hand)." },
	{ type = "subheader", name = "Open world only: inside instances the game keeps friendly nameplates to itself" },
}

local M = MelloUI:RegisterModule("PartyMarkers", {
	title = "Party Markers",
	desc = "A class medallion above every party member's friendly nameplate, with a ring in their role's colour. In the open world; inside instances the game keeps friendly nameplates to itself.",
	icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
	flavour = "A class medallion over every party member's head, ringed in their role's colour: the healer, found at a glance.",
	group = "Frames and bars", navOrder = 4,
	role = "feature",
	enabledByDefault = true,
	defaults = defaults,
	options = options,
})

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua); Plain(v)
-- is v, or nil when v is secret
local Secret = MelloUI.Safe.IsSecret
local Plain = MelloUI.Safe.Value

local function PlainCall(fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		return nil
	end
	return Plain(a), Plain(b)
end

local ROLE_COLORS = {
	HEALER = { 0.35, 0.86, 0.35 },
	TANK = { 0.35, 0.55, 0.90 },
	DAMAGER = { 0.90, 0.35, 0.35 },
}

-- The unit's class file and role, plain or nil.
local function UnitMark(unit)
	if not unit then
		return nil
	end
	local exists = PlainCall(UnitExists, unit)
	if not exists then
		return nil
	end
	local isPlayer = PlainCall(UnitIsPlayer, unit)
	if not isPlayer then
		return nil
	end
	if M.db.who == "group" then
		local inParty = PlainCall(UnitInParty, unit)
		local inRaid = PlainCall(UnitInRaid, unit)
		if not (inParty or inRaid) then
			return nil
		end
	else
		local friend = PlainCall(UnitIsFriend, "player", unit)
		if not friend then
			return nil
		end
	end
	local _, classFile = PlainCall(UnitClass, unit)
	if type(classFile) ~= "string" then
		return nil
	end
	local role = nil
	if M.db.roleRing and UnitGroupRolesAssigned then
		role = PlainCall(UnitGroupRolesAssigned, unit)
		if role ~= "HEALER" and role ~= "TANK" and role ~= "DAMAGER" then
			role = nil
		end
	end
	return classFile, role
end

local function InInstance()
	local ok, inInstance = pcall(IsInInstance)
	return ok and inInstance and true or false
end

--------------------------------------------------------------------------------
-- The marker on a plate
--------------------------------------------------------------------------------

-- The marker's parent: the nameplate's base frame when it does not clip
-- its children, else the world frame (a frame outside the plate's box was
-- cut off at the top — user, 2026-09-22: "mage icons cut off on the
-- top"); anchored to the plate's name either way, so it follows the plate.
local function MarkerParent(plate, unitFrame)
	local okC, clips = pcall(plate.DoesClipChildren, plate)
	if okC and not Secret(clips) and not clips then
		return plate
	end
	return WorldFrame or unitFrame
end

local function GetMarker(plate, unitFrame)
	local marker = unitFrame.MelloUIPartyMarker
	if marker then
		return marker
	end
	local parent = MarkerParent(plate, unitFrame)
	marker = CreateFrame("Frame", nil, parent)
	marker:EnableMouse(false)
	if parent == WorldFrame then
		-- at the plate's strata, above it
		local okS, strata = pcall(plate.GetFrameStrata, plate)
		if okS and not Secret(strata) and strata then
			marker:SetFrameStrata(strata)
		end
	end
	local okL, level = pcall(unitFrame.GetFrameLevel, unitFrame)
	marker:SetFrameLevel(((okL and not Secret(level) and level) or 1) + 2)
	marker.icon = marker:CreateTexture(nil, "ARTWORK")
	marker.icon:SetAllPoints()
	-- the role ring: the medallion's own round mask on a flat colour, a
	-- little larger than the medallion, under it (PR3)
	marker.ring = marker:CreateTexture(nil, "BORDER")
	marker.ring:SetColorTexture(1, 1, 1, 1)
	marker.ringMask = marker:CreateMaskTexture()
	marker.ringMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	marker.ringMask:SetAllPoints(marker.ring)
	marker.ring:AddMaskTexture(marker.ringMask)
	marker.ring:Hide()
	marker:Hide()
	unitFrame.MelloUIPartyMarker = marker
	return marker
end

local function PlaceMarker(unitFrame, marker)
	local size = tonumber(M.db.size) or 30
	local gap = tonumber(M.db.offset) or 4
	marker:SetSize(size, size)
	marker:ClearAllPoints()
	-- above the name where the game shows it (the name's anchors read
	-- secret, its rect too: the marker hangs on the name's TOP by anchor
	-- alone, which needs no reading)
	local name = unitFrame.name
	if name then
		marker:SetPoint("BOTTOM", name, "TOP", 0, gap)
	else
		marker:SetPoint("BOTTOM", unitFrame.HealthBarsContainer or unitFrame, "TOP", 0, gap + 14)
	end
	local ringPad = math.max(2, math.floor(size * 0.08 + 0.5))
	marker.ring:SetSize(size + ringPad * 2, size + ringPad * 2)
	marker.ring:ClearAllPoints()
	marker.ring:SetPoint("CENTER", marker, "CENTER")
end

local function UpdatePlate(plate)
	local unitFrame = plate and plate.UnitFrame
	if not unitFrame or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then
		return
	end
	local marker = unitFrame.MelloUIPartyMarker
	if not (M.isEnabled and M.db) then
		if marker then
			marker:Hide()
		end
		return
	end
	local unit = unitFrame.unit or plate.namePlateUnitToken
	local classFile, role = UnitMark(unit)
	if not classFile then
		if marker then
			marker:Hide()
		end
		return
	end
	local path = MelloUI.ClassIconPath and MelloUI:ClassIconPath(classFile)
	if not path then
		if marker then
			marker:Hide()
		end
		return
	end
	marker = GetMarker(plate, unitFrame)
	PlaceMarker(unitFrame, marker)
	marker.icon:SetTexture(path)
	marker.icon:SetTexCoord(0, 1, 0, 1)
	local color = role and ROLE_COLORS[role]
	if color then
		marker.ring:SetVertexColor(color[1], color[2], color[3], 1)
		marker.ring:Show()
	else
		marker.ring:Hide()
	end
	marker:Show()
end

local function UpdateAll()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if ok and type(plates) == "table" then
		for _, plate in ipairs(plates) do
			if not (plate.IsForbidden and plate:IsForbidden()) then
				UpdatePlate(plate)
			end
		end
	end
end

local function HideAll()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if ok and type(plates) == "table" then
		for _, plate in ipairs(plates) do
			local uf = plate.UnitFrame
			if uf and uf.MelloUIPartyMarker then
				uf.MelloUIPartyMarker:Hide()
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Events and lifecycle
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
		if ok and plate then
			UpdatePlate(plate)
		end
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
		local uf = ok and plate and plate.UnitFrame
		if uf and uf.MelloUIPartyMarker then
			uf.MelloUIPartyMarker:Hide()
		end
	else
		-- the group changed, a role was set, a zone entered: every plate again
		UpdateAll()
	end
end)

local EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	for _, event in ipairs(EVENTS) do
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
	UpdateAll()
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	HideAll()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	UpdateAll()
end

-- /pmdump: every nameplate, whether the client lets an addon touch it
-- (friendly plates in instances can be forbidden on this engine), the
-- unit on it, whether the class and role were readable, and whether a
-- marker is shown. The dungeon test (user, 2026-09-22: "is that going to
-- work inside of a dungeon?").
SLASH_MELLOPMDUMP1 = "/pmdump"
SlashCmdList.MELLOPMDUMP = function()
	MelloUI:ClearLog()
	-- the forbidden plates too (the list leaves them out by default): a
	-- friendly plate inside an instance is one on this engine, the game
	-- draws it and no addon may touch it (user, 2026-09-22: "i literally
	-- see the nameplate", with 0 plates listed)
	local ok, plates = pcall(C_NamePlate.GetNamePlates, true)
	if not (ok and type(plates) == "table") then
		MelloUI:Print("No nameplates readable.")
		MelloUI:ShowLog("pmdump")
		return
	end
	MelloUI:Print("Party Markers: module %s, instance=%s, %d plates handed to addons", M.isEnabled and "on" or "off",
		tostring(InInstance()), #plates)
	for i, plate in ipairs(plates) do
		local forbidden = plate.IsForbidden and plate:IsForbidden()
		local uf = not forbidden and plate.UnitFrame or nil
		local ufForbidden = uf and uf.IsForbidden and uf:IsForbidden()
		local unit = (uf and not ufForbidden and uf.unit) or plate.namePlateUnitToken or "?"
		local classFile, role = "-", "-"
		local steps = ""
		if not forbidden and not ufForbidden then
			local c, r = UnitMark(unit)
			classFile, role = tostring(c), tostring(r)
			-- each read on its own: which one answers nothing or secret
			local function Step(label, fn, ...)
				local okS, v = pcall(fn, ...)
				local shown
				if not okS then
					shown = "error"
				elseif Secret(v) then
					shown = "secret"
				else
					shown = tostring(v)
				end
				steps = steps .. " " .. label .. "=" .. shown
			end
			Step("exists", UnitExists, unit)
			Step("player", UnitIsPlayer, unit)
			Step("party", UnitInParty, unit)
			Step("raid", UnitInRaid, unit)
			Step("friend", UnitIsFriend, "player", unit)
			Step("name", UnitName, unit)
			Step("class", function(u) return select(2, UnitClass(u)) end, unit)
			Step("plateClips", plate.DoesClipChildren, plate)
			Step("frameClips", uf.DoesClipChildren, uf)
		end
		local marker = uf and not ufForbidden and uf.MelloUIPartyMarker
		MelloUI:Print("%d %s: plate forbidden=%s frame forbidden=%s  class=%s role=%s  marker=%s  |%s", i, tostring(unit),
			tostring(forbidden), tostring(ufForbidden), classFile, role, marker and (marker:IsShown() and "shown" or "hidden") or "none", steps)
	end
	if InInstance() then
		MelloUI:Print("Inside an instance this game draws friendly nameplates on its own side and hands none of them to addons: they cannot carry a marker here.")
	end
	MelloUI:ShowLog("pmdump")
end

MelloUI:Profile("PartyMarkers", "nameplate events", eventFrame)
