--------------------------------------------------------------------------------
-- MelloUI - Nameplates
--
-- Large crowd-control icon above the name on enemy nameplates, and a quest
-- marker on enemies you still need for a quest (Forever's default nameplates
-- have no quest icon at all).
--
-- Forever shows crowd-control auras on NPC nameplates in a small list to the
-- right of the health bar (CrowdControlListFrame) and loss-of-control effects
-- on player nameplates in a similar spot (LossOfControlFrame). This module
-- moves both above the name / debuff row and scales them up.
--
-- Blizzard must be showing crowd control on nameplates for this to have any
-- effect: Options > Nameplates > enemy NPC auras > Crowd Control.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Nameplates")
-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer

local BASE_ITEM_SIZE = 25 -- NamePlateConstants.AURA_ITEM_HEIGHT
local BASE_LOC_SIZE = 30  -- LossOfControlFrame size in XML

local M = MelloUI:RegisterModule("Nameplates", {
	title = "Nameplates",
	desc = "Large crowd-control icon above the name and a quest marker on enemy nameplates.",
	icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
	flavour = "Know who is stunned, who is your quest target, and who is about to be a problem.",
	group = "Frames and bars", navOrder = 2,
	role = "adds",
	tweak = { label = "Nameplate Icons", desc = "A large crowd-control icon above the name and a quest marker on enemies you still need. Works with or without the reskin.", order = 4 },
	defaults = {
		nameFormat = "both",   -- set by UI Modifications' "Show Names As" (one setting for every name)
		bigCC = true,
		ccSize = 45,
		ccGap = 4,
		questIcon = true,
		questIconSize = 22,
		threatLine = true,
	},
	options = {
		{ type = "header", name = "Crowd Control" },
		{ type = "toggle", key = "bigCC", name = "Large CC Icon Above Name",
		  desc = "Move the crowd-control icon from the right side of the nameplate to above the name and enlarge it. Requires Blizzard's Crowd Control nameplate aura option to be on." },
		{ type = "slider", key = "ccSize", parent = "bigCC", name = "CC Icon Size", min = 30, max = 120, step = 5,
		  format = function(v) return string.format("%d px", v) end,
		  desc = "Size of the crowd-control icon in pixels." },
		{ type = "slider", key = "ccGap", parent = "bigCC", name = "Gap Above Name", min = 0, max = 30, step = 1,
		  format = function(v) return string.format("%d px", v) end,
		  desc = "Space between the name / debuff row and the crowd-control icon." },
		{ type = "header", name = "Quest Icon" },
		{ type = "toggle", key = "questIcon", name = "Quest Icon",
		  desc = "Show a yellow quest marker left of the health bar on enemies that still count for one of your quests." },
		{ type = "slider", key = "questIconSize", parent = "questIcon", name = "Quest Icon Size", min = 12, max = 40, step = 1,
		  format = function(v) return string.format("%d px", v) end,
		  desc = "Size of the quest marker in pixels." },
		{ type = "header", name = "Threat" },
		{ type = "toggle", key = "threatLine", name = "Threat Line",
		  desc = "In a group fight, a thin bar along the bottom of an enemy's health bar (in the Nameplate Kit's lower rail) fills to the point where it would turn on you: gold while safe, amber when close, red when it is on you. For a tank it turns red when a mob is not on you. Solo it stays away." },
	},
})

local function Active()
	return M.isEnabled and M.db and M.db.bigCC
end

--------------------------------------------------------------------------------
-- The name's form on nameplates (user, 2026-09-22): after the game has set
-- a plate's name (CompactUnitFrame_UpdateName, the plates' compact frames
-- only), the text is set again in the chosen form. A post-hook; a secret
-- name is left as the game shows it. The unit frames are Unit Frames'.
--------------------------------------------------------------------------------

local function IsNamePlateFrame(frame)
	local options = frame.optionTable
	if options and (options == NamePlateEnemyFrameOptions or options == NamePlateFriendlyFrameOptions or options == NamePlatePlayerFrameOptions) then
		return true
	end
	local parent = frame.GetParent and frame:GetParent()
	local name = parent and parent.GetName and parent:GetName()
	return type(name) == "string" and name:sub(1, 9) == "NamePlate"
end

local function ApplyPlateName(frame, mode)
	if not (frame and frame.name and frame.unit) then
		return
	end
	local text = MelloUI:UnitNameAs(frame.unit, mode)
	if text ~= nil then
		pcall(frame.name.SetText, frame.name, text)
	end
end

local function OnCompactName(frame)
	if not (M.isEnabled and M.db) or not frame or not frame.name then
		return
	end
	local mode = M.db.nameFormat or "both"
	if mode == "both" or not IsNamePlateFrame(frame) then
		return
	end
	ApplyPlateName(frame, mode)
end

local plateNameHooked = false
local function InstallPlateNameHook()
	if plateNameHooked then
		return
	end
	plateNameHooked = true
	if type(CompactUnitFrame_UpdateName) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateName", OnCompactName)
	end
end

-- Every plate again, in the given form (a setting changed, the module off).
local function RefreshPlateNames(mode)
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if not (ok and type(plates) == "table") then
		return
	end
	for _, plate in ipairs(plates) do
		local frame = plate.UnitFrame
		if frame and not (frame.IsForbidden and frame:IsForbidden()) then
			ApplyPlateName(frame, mode)
		end
	end
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local hookedAuras = setmetatable({}, { __mode = "k" })
local hookedUnitFrames = setmetatable({}, { __mode = "k" })

local function GetUnitFrame(aurasFrame)
	return aurasFrame and aurasFrame:GetParent()
end

-- Vertical offset from the top of the health bar container to the bottom of
-- the crowd-control icon: name row + debuff row (if any) + gap.
local function IsPlainNumber(v)
	return type(v) == "number" and not (issecretvalue and issecretvalue(v))
end

local function ComputeOffset(unitFrame)
	local offset = 0
	local name = unitFrame.name
	if name and name:IsShown() then
		-- The name's measured height can be a secret value (it derives from
		-- the unit's name text); fall back to the font size, then a constant.
		local height = name:GetHeight()
		if not IsPlainNumber(height) then
			local _, size = name:GetFont()
			height = IsPlainNumber(size) and size or 12
		end
		offset = offset + height + 2
	end
	local auras = unitFrame.AurasFrame
	local debuffs = auras and auras.DebuffListFrame
	if debuffs and debuffs:IsShown() then
		local hasChildren = false
		for _, child in ipairs({ debuffs:GetChildren() }) do
			if child:IsShown() then
				hasChildren = true
				break
			end
		end
		if hasChildren then
			local scale = auras.auraItemScale
			if not IsPlainNumber(scale) then
				scale = 1
			end
			offset = offset + BASE_ITEM_SIZE * scale + 2
		end
	end
	return offset + (M.db.ccGap or 0)
end

local function AnchorCC(unitFrame)
	local auras = unitFrame and unitFrame.AurasFrame
	if not auras or not unitFrame.HealthBarsContainer then
		return
	end
	local offset = ComputeOffset(unitFrame)
	local cc = auras.CrowdControlListFrame
	if cc then
		-- the list is scaled (ResizeCCList): an offset on it is in its own,
		-- scaled units, so it is given unscaled to land where it is meant to
		local s = cc:GetScale()
		if not IsPlainNumber(s) or s <= 0 then
			s = 1
		end
		cc:ClearAllPoints()
		cc:SetPoint("BOTTOM", unitFrame.HealthBarsContainer, "TOP", 0, offset / s)
	end
	local loc = auras.LossOfControlFrame
	if loc then
		loc:ClearAllPoints()
		loc:SetPoint("BOTTOM", unitFrame.HealthBarsContainer, "TOP", 0, offset)
	end
end

-- The crowd-control icons at the chosen size: the whole LIST is scaled, not
-- its icons. Sized icon by icon, the list's height had to be written into the
-- game's own `fixedHeight` field and its Layout() called from here, so the
-- game's nameplate layout then ran on a value MelloUI wrote -- the one field of
-- ours the game reads (found 2026-09-23, after the study of how the careful
-- addons stay out of taint). Scaling the list is a widget call: every field of
-- the game's stays its own, and the game lays the list out itself.
local function ResizeCCList(auras)
	local cc = auras.CrowdControlListFrame
	if not cc then
		return
	end
	-- the game draws the icons at its own item scale inside the list
	local itemScale = auras.auraItemScale
	if not IsPlainNumber(itemScale) or itemScale <= 0 then
		itemScale = 1
	end
	cc:SetScale((M.db.ccSize or 45) / BASE_ITEM_SIZE / itemScale)
end

local function ResizeLossOfControl(auras)
	local loc = auras.LossOfControlFrame
	if loc then
		loc:SetScale((M.db.ccSize or 45) / BASE_LOC_SIZE)
	end
end

local function StyleAuras(auras)
	if not auras then
		return
	end
	ResizeCCList(auras)
	ResizeLossOfControl(auras)
	AnchorCC(GetUnitFrame(auras))
end

local function HookAuras(auras)
	if not auras or hookedAuras[auras] then
		return
	end
	hookedAuras[auras] = true
	if type(auras.RefreshList) == "function" then
		hooksecurefunc(auras, "RefreshList", function(self, listFrame)
			if not Active() then
				return
			end
			if listFrame == self.CrowdControlListFrame then
				ResizeCCList(self)
			end
			-- Debuff row height changed, so the icon above it may need to move.
			AnchorCC(GetUnitFrame(self))
		end)
	end
	if type(auras.RefreshLossOfControl) == "function" then
		hooksecurefunc(auras, "RefreshLossOfControl", function(self)
			if Active() then
				ResizeLossOfControl(self)
				AnchorCC(GetUnitFrame(self))
			end
		end)
	end
end

local function HookUnitFrame(unitFrame)
	if not unitFrame or hookedUnitFrames[unitFrame] then
		return
	end
	hookedUnitFrames[unitFrame] = true
	if type(unitFrame.UpdateAnchors) == "function" then
		hooksecurefunc(unitFrame, "UpdateAnchors", function(self)
			if Active() then
				AnchorCC(self)
			end
		end)
	end
end

local function StyleUnitFrame(unitFrame)
	if not unitFrame or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then
		return
	end
	HookUnitFrame(unitFrame)
	HookAuras(unitFrame.AurasFrame)
	StyleAuras(unitFrame.AurasFrame)
end

local function StylePlate(plate)
	if plate and not (plate.IsForbidden and plate:IsForbidden()) then
		StyleUnitFrame(plate.UnitFrame)
	end
end

local function ApplyAll()
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			StylePlate(plate)
		end
	end
end

-- Let Blizzard lay the plate out again with its own anchors and sizes.
local function RestoreAll()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unitFrame = plate and not (plate.IsForbidden and plate:IsForbidden()) and plate.UnitFrame
		local auras = unitFrame and unitFrame.AurasFrame
		if auras then
			local scale = IsPlainNumber(auras.auraItemScale) and auras.auraItemScale or 1
			if auras.CrowdControlListFrame then
				auras.CrowdControlListFrame:SetScale(1)
			end
			if auras.LossOfControlFrame then
				auras.LossOfControlFrame:SetScale(scale)
			end
		end
		if unitFrame and type(unitFrame.UpdateAnchors) == "function" then
			pcall(unitFrame.UpdateAnchors, unitFrame)
		end
	end
end

--------------------------------------------------------------------------------
-- Quest icon
--------------------------------------------------------------------------------

local QUEST_ICON_TEXTURE = "Interface\\GossipFrame\\AvailableQuestIcon"
local LINE_QUEST_OBJECTIVE = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective) or 8
local LINE_QUEST_TITLE = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle) or 17

local function QuestActive()
	return M.isEnabled and M.db and M.db.questIcon
end

-- Does the unit's tooltip list an unfinished objective of one of our quests?
local function IsQuestTarget(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return false
	end
	local ok, result = pcall(function()
		if UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then
			return false
		end
		local data = C_TooltipInfo.GetUnit(unit)
		if not data or type(data.lines) ~= "table" then
			return false
		end
		local sawTitle = false
		local sawObjective = false
		for _, line in ipairs(data.lines) do
			if line.type == LINE_QUEST_TITLE then
				sawTitle = true
			elseif line.type == LINE_QUEST_OBJECTIVE then
				sawObjective = true
				local text = line.leftText
				if type(text) == "string" then
					local cur, total = text:match("(%d+)%s*/%s*(%d+)")
					if cur and total then
						if tonumber(cur) < tonumber(total) then
							return true
						end
					else
						local pct = text:match("(%d+)%%")
						if pct then
							if tonumber(pct) < 100 then
								return true
							end
						else
							return true
						end
					end
				else
					return true
				end
			end
		end
		-- A quest title without any objective lines still means the mob is
		-- relevant. If objectives were listed and none was unfinished (6/6,
		-- 100%), the quest is done for this mob and the icon must go.
		return sawTitle and not sawObjective
	end)
	return ok and result == true
end

local function GetQuestIcon(unitFrame)
	local icon = unitFrame.MelloUIQuestIcon
	if not icon then
		-- on a layer frame above the health bar: the unit frame's own regions
		-- draw under its children, so the Nameplate Kit's gem cap (a region
		-- of the bar, standing outside it) hid the icon (user, 2026-09-23)
		local layer = CreateFrame("Frame", nil, unitFrame)
		layer:SetAllPoints(unitFrame)
		layer:EnableMouse(false)
		local hb = unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar
		local ok, level = pcall(function() return (hb or unitFrame):GetFrameLevel() end)
		if ok and IsPlainNumber(level) then
			layer:SetFrameLevel(level + 5)
		end
		icon = layer:CreateTexture(nil, "OVERLAY")
		icon:SetTexture(QUEST_ICON_TEXTURE)
		icon:Hide()
		unitFrame.MelloUIQuestIcon = icon
	end
	local size = M.db.questIconSize or 22
	icon:SetSize(size, size)
	icon:ClearAllPoints()
	-- beside the Nameplate Kit's left gem cap while it dresses the plate
	-- (the cap stands outside the bar), else beside the raid mark / bar
	local anchor = unitFrame.melloBracketLeft or unitFrame.RaidTargetFrame or unitFrame.HealthBarsContainer
	if anchor then
		icon:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
	end
	return icon
end

local function GetPlateUnit(plate)
	local unitFrame = plate.UnitFrame
	local unit = (unitFrame and unitFrame.unit) or plate.namePlateUnitToken or plate.unitToken
	if not unit and plate.GetUnit then
		local ok, value = pcall(plate.GetUnit, plate)
		if ok then
			unit = value
		end
	end
	return unit
end

local function UpdateQuestIcon(plate)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	local unitFrame = plate.UnitFrame
	if not unitFrame then
		return
	end
	if not QuestActive() then
		if unitFrame.MelloUIQuestIcon then
			unitFrame.MelloUIQuestIcon:Hide()
		end
		return
	end
	local unit = GetPlateUnit(plate)
	local show = unit and IsQuestTarget(unit)
	local icon = GetQuestIcon(unitFrame)
	icon:SetShown(show and true or false)
end

local function UpdateAllQuestIcons()
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			UpdateQuestIcon(plate)
		end
	end
end

local questRescanPending = false

local function ScheduleQuestRescan()
	if questRescanPending then
		return
	end
	questRescanPending = true
	C_Timer.After(0.3, function()
		questRescanPending = false
		if QuestActive() then
			UpdateAllQuestIcons()
		end
	end)
end

--------------------------------------------------------------------------------
-- The threat line (0.16.0; user, 2026-09-30: threat_sketch look D without the
-- number, pulled into 0.16.0): a thin bar along an enemy plate's health bar
-- filling to the pull (MelloUI.Threat, Core/Threat.lua: one reader with the
-- Threat widget), gold while safe, amber when close, red when the mob is on
-- you -- for a tank, red when it is not. Only in a group fight, only on the
-- plates of mobs whose list the player is on. Where the game keeps the numbers
-- secret the bar takes the secret value itself (StatusBar:SetValue draws it;
-- nothing here reads it) and its colour follows the state while that is open,
-- gold otherwise (user, 2026-09-30: "i dont want anything else, just the
-- progress bar": the "!" went). Made on a plate's first threat (a crowd out of a fight makes none),
-- kept in a table of this file's (nothing written on the game's frame).
-- UNIT_THREAT_LIST_UPDATE lays the plate it names; UNIT_THREAT_SITUATION_UPDATE,
-- the fight's start and end every plate. A StatusBar: the engine fills it
-- (every size under a plate reads secret). Where it lies (user, 2026-09-30:
-- pick C of threat_sketch/threat_castbar_looks.jpg -- the game keeps the
-- cast bar's place right under the health bar, so a line there was covered
-- by every cast): in the groove of the Nameplate Kit's lower rail, as wide
-- as the bar, the bracket its outline; without the kit, along the bar's own
-- bottom edge with a thin dark edge above it. Never under the cast bar.
--------------------------------------------------------------------------------

local Threat = MelloUI.Threat
local W = MelloUI.Widgets
local THREAT_H = 3
local WHITE = "Interface\\Buttons\\WHITE8X8"
local threatLines = setmetatable({}, { __mode = "k" })   -- [the plate's UnitFrame] = its line
local PLATE_UNITS = {}
for i = 1, 40 do
	PLATE_UNITS[i] = "nameplate" .. i
end

local function ThreatOn()
	return M.isEnabled and M.db ~= nil and M.db.threatLine ~= false
end

-- a group fight: the player in combat, in a party or a raid
local function GroupFight()
	local ok, fighting = pcall(UnitAffectingCombat, "player")
	return ok and fighting == true and Threat.Grouped()
end

local function ThreatLine(uf)
	local line = threatLines[uf]
	if line then
		return line
	end
	line = CreateFrame("Frame", nil, uf)
	line:EnableMouse(false)
	local hb = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
	local ok, level = pcall(function() return (hb or uf):GetFrameLevel() end)
	if ok and IsPlainNumber(level) then
		line:SetFrameLevel(level + 5)
	end
	local bar = CreateFrame("StatusBar", nil, line)
	bar:SetStatusBarTexture(WHITE)
	bar:SetMinMaxValues(0, 100)   -- (the game's scaledPercentage, as it comes)
	bar:SetHeight(THREAT_H)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(bar)
	bg:SetTexture(WHITE)
	W.Paint(bg, "innerPanel", "vertex", 0.85)
	-- (without the kit: a thin dark edge between it and the bar's fill)
	local edge = bar:CreateTexture(nil, "BORDER")
	edge:SetTexture(WHITE)
	edge:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 0)
	edge:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 0)
	edge:SetHeight(1)
	W.Paint(edge, "mainWindow", "vertex", 1)
	line.bar, line.hb, line.edge = bar, hb, edge
	threatLines[uf] = line
	return line
end

-- in the Kit's lower rail while it dresses the plate (hanging from the bar's
-- bottom into the rail's groove), else along the bar's own bottom edge;
-- anchored again on a change only
local function HangThreat(uf, line)
	local hb = line.hb or uf
	local rail = uf.melloBracketLeft ~= nil
	if line.hbAt == hb and line.rail == rail then
		return
	end
	line.hbAt, line.rail = hb, rail
	local bar = line.bar
	bar:ClearAllPoints()
	if rail then
		bar:SetPoint("TOPLEFT", hb, "BOTTOMLEFT", 0, 0)
		bar:SetPoint("TOPRIGHT", hb, "BOTTOMRIGHT", 0, 0)
	else
		bar:SetPoint("BOTTOMLEFT", hb, "BOTTOMLEFT", 0, 0)
		bar:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", 0, 0)
	end
	line.edge:SetShown(not rail)
end

local function HideThreat(uf)
	local line = threatLines[uf]
	if line then
		line:Hide()
	end
end

-- one plate as the fight stands now (tank, fight: read once for all plates)
local function ThreatPlate(uf, unit, tank, fight)
	if not (fight and ThreatOn() and unit) then
		HideThreat(uf)
		return
	end
	local ok, hostile = pcall(UnitCanAttack, "player", unit)
	if not ok or hostile ~= true then
		HideThreat(uf)
		return
	end
	local status, fraction, tanking, value = Threat.Read("player", unit)
	-- (a value there: plain, or secret -- asked for secret before the nil test)
	local hasValue = Secret(value) or value ~= nil
	if status == false or (status == nil and not hasValue) then
		HideThreat(uf)
		return
	end
	local line = ThreatLine(uf)
	HangThreat(uf, line)
	local r, g, b = Threat.Colour(Threat.State(status, fraction, tank) or "safe")
	local bar = line.bar
	if tank and tanking then
		bar:SetValue(100)
	elseif hasValue then
		bar:SetValue(value)
	else
		bar:SetValue(0)
	end
	bar:SetStatusBarColor(r, g, b)
	line:Show()
end

local function ThreatUnit(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	local uf = plate and not (plate.IsForbidden and plate:IsForbidden()) and plate.UnitFrame
	if uf then
		ThreatPlate(uf, unit, Threat.IsTank(), GroupFight())
	end
end

local function ThreatAll()
	local tank, fight = Threat.IsTank(), GroupFight()
	for i = 1, #PLATE_UNITS do
		local unit = PLATE_UNITS[i]
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		local uf = plate and not (plate.IsForbidden and plate:IsForbidden()) and plate.UnitFrame
		if uf then
			ThreatPlate(uf, unit, tank, fight)
		end
	end
end

local function HideAllThreat()
	for uf in pairs(threatLines) do
		HideThreat(uf)
	end
end

local THREAT_EVENTS = { "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE" }

local QUEST_EVENTS = {
	"QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
	"QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_ENTERING_WORLD",
}

--------------------------------------------------------------------------------
-- Events & lifecycle
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		if Active() then
			StylePlate(plate)
		end
		if QuestActive() then
			UpdateQuestIcon(plate)
		end
		if ThreatOn() then
			ThreatUnit(unit)
		end
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		if plate and plate.UnitFrame and plate.UnitFrame.MelloUIQuestIcon then
			plate.UnitFrame.MelloUIQuestIcon:Hide()
		end
		if plate and plate.UnitFrame then
			HideThreat(plate.UnitFrame)
		end
	elseif event == "UNIT_THREAT_LIST_UPDATE" then
		-- (a plate's mob: that plate; the target's or a boss's plate has its
		-- own nameplateN event too)
		if not Secret(unit) and type(unit) == "string" and unit:sub(1, 9) == "nameplate" then
			ThreatUnit(unit)
		end
	elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "PLAYER_REGEN_DISABLED" or event == "GROUP_ROSTER_UPDATE" then
		ThreatAll()
	elseif event == "PLAYER_REGEN_ENABLED" then
		HideAllThreat()
	else
		ScheduleQuestRescan()
	end
end)

local function RegisterThreatEvents(register)
	for _, event in ipairs(THREAT_EVENTS) do
		if register then
			eventFrame:RegisterEvent(event)
		else
			eventFrame:UnregisterEvent(event)
		end
	end
	if not register then
		HideAllThreat()
	end
end

local function RegisterQuestEvents(register)
	for _, event in ipairs(QUEST_EVENTS) do
		if register then
			if event == "UNIT_QUEST_LOG_CHANGED" then
				eventFrame:RegisterUnitEvent(event, "player")
			else
				eventFrame:RegisterEvent(event)
			end
		else
			eventFrame:UnregisterEvent(event)
		end
	end
end

local function HideAllQuestIcons()
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			local unitFrame = plate and not (plate.IsForbidden and plate:IsForbidden()) and plate.UnitFrame
			if unitFrame and unitFrame.MelloUIQuestIcon then
				unitFrame.MelloUIQuestIcon:Hide()
			end
		end
	end
end

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	RegisterQuestEvents(true)
	RegisterThreatEvents(ThreatOn())
	InstallPlateNameHook()
	if db.nameFormat and db.nameFormat ~= "both" then
		RefreshPlateNames(db.nameFormat)
	end
	if db.bigCC then
		ApplyAll()
	end
	if db.questIcon then
		UpdateAllQuestIcons()
	end
end

-- (Kit.lua loads before this file, so its combat queue is always there:
-- audit 2026-09-24, a dead guard gone)
local function OutOfCombat(fn)
	MelloUI.Kit:WhenOutOfCombat(fn)
end

function M:OnDisable()
	eventFrame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
	eventFrame:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
	RegisterQuestEvents(false)
	RegisterThreatEvents(false)
	OutOfCombat(RestoreAll)
	HideAllQuestIcons()
	RefreshPlateNames("both")
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "nameFormat" then
		RefreshPlateNames(value or "both")
		return
	end
	if key == "threatLine" then
		RegisterThreatEvents(value ~= false)
		if value ~= false then
			ThreatAll()
		end
		return
	end
	if key == "questIcon" or key == "questIconSize" then
		if db.questIcon then
			UpdateAllQuestIcons()
		else
			HideAllQuestIcons()
		end
		return
	end
	if db.bigCC then
		OutOfCombat(ApplyAll)
	else
		OutOfCombat(RestoreAll)
	end
end

MelloUI:Profile("Nameplates", "events", eventFrame)
MelloUI:Profile("Nameplates", "quest icon rescan", UpdateAllQuestIcons)
MelloUI:Profile("Nameplates", "cc anchoring", AnchorCC)
