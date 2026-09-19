--------------------------------------------------------------------------------
-- MelloUI - Bar Textures
--
-- Replaces the fill texture of status bars: unit frame health and power bars,
-- nameplate health and cast bars, the personal resource display, the
-- experience / reputation / honor bars, cast bars and cooldown manager bars.
--
-- Blizzard's Dragonflight-style bars use pre-coloured atlases with a white bar
-- colour. When a flat texture is swapped in the module applies the matching
-- colour itself (power type colours, experience purple, reputation colours,
-- cast bar yellow / green / red), so bars keep their meaning.
--
-- Textures: shipped ones in Media\Textures, anything registered with
-- LibSharedMedia-3.0 by another addon, two Blizzard textures, and custom files
-- listed in Media\CustomTextures.lua.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\"

local SHIPPED_TEXTURES = {
	{ value = MEDIA .. "Flat",        label = "Flat" },
	{ value = MEDIA .. "Smooth",      label = "Smooth" },
	{ value = MEDIA .. "Gloss",       label = "Gloss" },
	{ value = MEDIA .. "Minimalist",  label = "Minimalist" },
	{ value = "Interface\\TargetingFrame\\UI-StatusBar", label = "Blizzard Classic" },
	{ value = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",  label = "Blizzard Raid" },
}

local function BuildTextureList()
	local list = {}
	local seen = {}
	local function Add(value, label)
		if value and not seen[value] then
			seen[value] = true
			list[#list + 1] = { value = value, label = label or value }
		end
	end
	for _, entry in ipairs(SHIPPED_TEXTURES) do
		Add(entry.value, entry.label)
	end
	if type(MelloUI_CustomTextures) == "table" then
		for _, entry in ipairs(MelloUI_CustomTextures) do
			if type(entry) == "table" and entry.file then
				Add(MEDIA .. entry.file, entry.name or entry.file)
			end
		end
	end
	local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
	if LSM then
		for _, name in ipairs(LSM:List("statusbar")) do
			Add(LSM:Fetch("statusbar", name), name)
		end
	end
	return list
end

local M = MelloUI:RegisterModule("BarTextures", {
	title = "Bar Textures",
	desc = "Change the fill texture of health, power, nameplate, experience, reputation, honor and cast bars.",
	defaults = {
		texture = MEDIA .. "Flat",
		healthColor = "green",
		unitframes = true,
		raidframes = true,
		nameplates = true,
		personal = true,
		statusbars = true,
		castbars = true,
		cooldowns = true,
	},
	options = {
		{ type = "header", name = "Texture" },
		{ type = "dropdown", key = "texture", name = "Bar Texture", values = BuildTextureList(),
		  desc = "Fill texture used for all bars below. Custom files go into MelloUI\\Media\\Textures and are listed in Media\\CustomTextures.lua." },
		{ type = "dropdown", key = "healthColor", name = "Health Bar Colour", values = {
			{ value = "green", label = "Green (Blizzard)" },
			{ value = "class", label = "Class colour for players" },
			{ value = "reaction", label = "Class (players) / reaction (NPCs)" },
		  },
		  desc = "Colour of unit frame health bars. Blizzard bakes the green into its artwork, so the module has to colour flat textures itself." },
		{ type = "header", name = "Apply To" },
		{ type = "toggle", key = "unitframes", name = "Unit Frames",
		  desc = "Health and power bars of the player, target, focus, pet, party, boss and target-of-target frames." },
		{ type = "toggle", key = "raidframes", name = "Raid Frames",
		  desc = "Raid-style party frames, raid groups and their pet frames." },
		{ type = "toggle", key = "nameplates", name = "Nameplates",
		  desc = "Nameplate health and cast bars." },
		{ type = "toggle", key = "personal", name = "Personal Resource Display",
		  desc = "The health and power bars under your character." },
		{ type = "toggle", key = "statusbars", name = "Experience & Reputation Bars",
		  desc = "Experience, reputation and honor bars." },
		{ type = "toggle", key = "castbars", name = "Cast Bars",
		  desc = "Player, pet, target, focus and boss cast bars." },
		{ type = "toggle", key = "cooldowns", name = "Cooldown Manager Bars",
		  desc = "The bars of the Buff Bar cooldown viewer." },
	},
})

--------------------------------------------------------------------------------
-- Colours for bars whose Blizzard atlas carried the colour
--------------------------------------------------------------------------------

local FACTION_FALLBACK = {
	[1] = { r = 0.8, g = 0.3, b = 0.22 },
	[2] = { r = 0.8, g = 0.3, b = 0.22 },
	[3] = { r = 0.75, g = 0.27, b = 0 },
	[4] = { r = 0.9, g = 0.7, b = 0 },
	[5] = { r = 0, g = 0.6, b = 0.1 },
}

local function FactionColor(index)
	local colors = FACTION_BAR_COLORS or FACTION_FALLBACK
	local c = colors[index] or FACTION_FALLBACK[index]
	return c.r, c.g, c.b
end

-- Secret values (e.g. the atlas name of a nameplate cast bar) may not be
-- read by addon code; treat them as if no name was given.
local function IsPlainString(v)
	if type(v) ~= "string" then
		return false
	end
	if issecretvalue and issecretvalue(v) then
		return false
	end
	return true
end

local function IsPlainNumber(v)
	return type(v) == "number" and not (issecretvalue and issecretvalue(v))
end

-- Maps the atlas name Blizzard hands to SetStatusBarTexture to an RGB colour.
local function StatusTrackingColorForAtlas(atlas)
	if not IsPlainString(atlas) then
		return nil
	end
	local a = atlas:lower()
	if a:find("rested") then return 0.0, 0.39, 0.88 end
	if a:find("experience") then return 0.58, 0.0, 0.55 end
	if a:find("honor") then return 1.0, 0.24, 0.0 end
	if a:find("faction%-red") then return FactionColor(2) end
	if a:find("faction%-orange") then return FactionColor(3) end
	if a:find("faction%-yellow") then return FactionColor(4) end
	if a:find("faction%-green") then return FactionColor(5) end
	if a:find("faction%-blue") then return 0.2, 0.5, 1.0 end
	if a:find("reputation") then return FactionColor(5) end
	return nil
end

--------------------------------------------------------------------------------
-- Core apply / hook machinery
--------------------------------------------------------------------------------

local tracked = setmetatable({}, { __mode = "k" })   -- [bar] = group
local originals = setmetatable({}, { __mode = "k" }) -- [bar] = original atlas or file
local hookedBars = setmetatable({}, { __mode = "k" })
local hookedTextures = setmetatable({}, { __mode = "k" }) -- [texture] = bar
local masks = setmetatable({}, { __mode = "k" })     -- [bar] = MaskTexture shaped like the original atlas
local maskedTextures = setmetatable({}, { __mode = "k" }) -- [texture] = mask currently attached
local applied = setmetatable({}, { __mode = "k" })   -- [bar] = true once our texture is on it
local applying = false

local function Active(group)
	return M.isEnabled and M.db and M.db[group]
end

local function RememberOriginal(bar)
	if originals[bar] ~= nil then
		return
	end
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	local value = false
	if tex then
		local atlas = tex.GetAtlas and tex:GetAtlas()
		if IsPlainString(atlas) and atlas ~= "" then
			value = { atlas = atlas }
		else
			local file = tex.GetTexture and tex:GetTexture()
			if IsPlainString(file) then
				value = { file = file }
			end
		end
	end
	originals[bar] = value
end

-- Blizzard draws the bar fills ABOVE the frame border art (the bars live in
-- child frames with a higher frame level) and relies on the shaped bar atlas
-- to stay inside the frame opening. A flat texture fills the whole rectangle
-- and covers the border, so mask the fill with the original atlas: Blizzard's
-- shape, our texture.
local function RemoveMask(bar)
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	local mask = tex and maskedTextures[tex]
	if tex and mask then
		if tex.RemoveMaskTexture then
			tex:RemoveMaskTexture(mask)
		end
		maskedTextures[tex] = nil
	end
end

local function UpdateMask(bar)
	local original = originals[bar]
	local atlas = original and original.atlas
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not tex or not tex.AddMaskTexture or not bar.CreateMaskTexture then
		return
	end
	if not IsPlainString(atlas) then
		RemoveMask(bar)
		return
	end
	local mask = masks[bar]
	if not mask then
		mask = bar:CreateMaskTexture()
		mask:SetAllPoints(bar)
		masks[bar] = mask
	end
	if mask.GetAtlas and mask:GetAtlas() ~= atlas then
		mask:SetAtlas(atlas)
	elseif not mask.GetAtlas then
		mask:SetAtlas(atlas)
	end
	if maskedTextures[tex] ~= mask then
		if maskedTextures[tex] and tex.RemoveMaskTexture then
			tex:RemoveMaskTexture(maskedTextures[tex])
		end
		tex:AddMaskTexture(mask)
		maskedTextures[tex] = mask
	end
end

local function SetTexture(bar)
	local r, g, b, a = bar:GetStatusBarColor()
	applying = true
	bar:SetStatusBarTexture(M.db.texture)
	UpdateMask(bar)
	applying = false
	applied[bar] = true
	if not (issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b) or issecretvalue(a))) then
		bar:SetStatusBarColor(r, g, b, a)
	end
end

local StatusTrackingColorForAtlasRef -- forward declared below the helper section

-- Some Blizzard code (target classification, boss frames, nameplate styles)
-- changes the bar art directly on the texture object instead of through
-- SetStatusBarTexture. Hook the texture so those changes are undone too.
local function HookBarTexture(bar)
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not tex or hookedTextures[tex] then
		return
	end
	hookedTextures[tex] = bar
	local function OnDirectChange(self, newTexture)
		if applying then
			return
		end
		local owner = hookedTextures[self]
		local grp = owner and tracked[owner]
		if not grp or not Active(grp) then
			return
		end
		if IsPlainString(newTexture) then
			originals[owner] = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(newTexture)
				and { atlas = newTexture } or { file = newTexture }
		end
		SetTexture(owner)
		if grp == "statusbars" and StatusTrackingColorForAtlasRef then
			local r, g, b = StatusTrackingColorForAtlasRef(newTexture)
			if r then
				owner:SetStatusBarColor(r, g, b)
			end
		end
	end
	if type(tex.SetAtlas) == "function" then
		hooksecurefunc(tex, "SetAtlas", OnDirectChange)
	end
	if type(tex.SetTexture) == "function" then
		hooksecurefunc(tex, "SetTexture", OnDirectChange)
	end
end

local function ApplyToBar(bar, group)
	if not bar or type(bar.SetStatusBarTexture) ~= "function" then
		return
	end
	-- Nameplate and cooldown layouts call back in here on every relayout.
	-- Once our texture is on the bar, its hooks keep it there; nothing to do.
	if applied[bar] and tracked[bar] == group then
		local tex = bar:GetStatusBarTexture()
		if tex and hookedTextures[tex] == bar then
			return
		end
	end
	RememberOriginal(bar)
	tracked[bar] = group
	SetTexture(bar)
	HookBarTexture(bar)

	if not hookedBars[bar] then
		hookedBars[bar] = true
		-- Blizzard swaps atlases on power type changes, nameplate style changes,
		-- cast bar states and experience bar states; put ours back afterwards.
		hooksecurefunc(bar, "SetStatusBarTexture", function(self, newTexture)
			if applying then
				return
			end
			local grp = tracked[self]
			if not grp or not Active(grp) then
				return
			end
			-- Keep track of what Blizzard wanted so disabling can restore it.
			if IsPlainString(newTexture) then
				originals[self] = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(newTexture)
					and { atlas = newTexture } or { file = newTexture }
			end
			SetTexture(self)
			if grp == "statusbars" then
				local r, g, b = StatusTrackingColorForAtlas(newTexture)
				if r then
					self:SetStatusBarColor(r, g, b)
				end
			end
		end)
	end
end

StatusTrackingColorForAtlasRef = StatusTrackingColorForAtlas

local function RestoreBar(bar)
	local original = originals[bar]
	if not original then
		return
	end
	applying = true
	RemoveMask(bar)
	if original.atlas then
		bar:SetStatusBarTexture(original.atlas)
	elseif original.file then
		bar:SetStatusBarTexture(original.file)
	end
	applying = false
	applied[bar] = nil
end

local function RestoreGroup(group)
	for bar, grp in pairs(tracked) do
		if grp == group then
			RestoreBar(bar)
			tracked[bar] = nil
		end
	end
end

local function ReapplyGroup(group)
	for bar, grp in pairs(tracked) do
		if grp == group then
			SetTexture(bar)
		end
	end
end

--------------------------------------------------------------------------------
-- Unit frames
--------------------------------------------------------------------------------

local function TargetLikeFrames()
	local frames = { TargetFrame, FocusFrame }
	for i = 1, 5 do
		frames[#frames + 1] = _G["Boss" .. i .. "TargetFrame"]
	end
	return frames
end

local healthBars = setmetatable({}, { __mode = "k" })

local function AddHealth(list, bar)
	if bar then
		healthBars[bar] = true
		list[#list + 1] = bar
	end
end

local function AddPower(list, bar)
	if bar then
		list[#list + 1] = bar
	end
end

local function CollectUnitFrameBars(list)
	if PlayerFrame and PlayerFrame.PlayerFrameContent then
		local main = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
		if main then
			if main.HealthBarsContainer then
				AddHealth(list, main.HealthBarsContainer.HealthBar)
				AddPower(list, main.HealthBarsContainer.PlayerFrameHealthBarAnimatedLoss)
			end
			if main.ManaBarArea then
				AddPower(list, main.ManaBarArea.ManaBar)
			end
		end
	end
	for _, frame in ipairs(TargetLikeFrames()) do
		if frame and frame.TargetFrameContent then
			local main = frame.TargetFrameContent.TargetFrameContentMain
			if main then
				if main.HealthBarsContainer then
					AddHealth(list, main.HealthBarsContainer.HealthBar)
				end
				AddPower(list, main.ManaBar)
			end
			if frame.totFrame then
				AddHealth(list, frame.totFrame.HealthBar)
				AddPower(list, frame.totFrame.ManaBar)
			end
		end
	end
	AddHealth(list, PetFrameHealthBar)
	AddPower(list, PetFrameManaBar)
	if PartyFrame then
		for i = 1, 4 do
			local member = PartyFrame["MemberFrame" .. i]
			if member then
				if member.HealthBarContainer then
					AddHealth(list, member.HealthBarContainer.HealthBar)
				end
				AddPower(list, member.ManaBar)
				if member.PetFrame then
					AddHealth(list, member.PetFrame.HealthBar)
				end
			end
		end
	end
end

-- Several Forever health bars lock their colour and rely on a green atlas, so a
-- flat texture has to be coloured here.
local function HealthColorFor(bar)
	local unit = bar.unit
	if unit then
		-- Blizzard greys only disconnected units (it stores the flag on the bar
		-- before this runs); dead or ghost units keep their colour.
		if bar.disconnected then
			return 0.5, 0.5, 0.5
		end
		local mode = M.db.healthColor
		if mode == "class" or mode == "reaction" then
			local ok2, r, g, b = pcall(function()
				if UnitIsPlayer(unit) then
					local _, class = UnitClass(unit)
					local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
					if color then
						return color.r, color.g, color.b
					end
				elseif mode == "reaction" then
					-- Hostile red, unfriendly orange, neutral yellow, friendly green.
					local reaction = UnitReaction(unit, "player")
					local color = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
					if color then
						return color.r, color.g, color.b
					end
				end
			end)
			if ok2 and IsPlainNumber(r) and IsPlainNumber(g) and IsPlainNumber(b) then
				return r, g, b
			end
		end
	end
	return 0.0, 1.0, 0.0
end

local function RecolorHealthBar(bar)
	if not bar or not healthBars[bar] or tracked[bar] ~= "unitframes" or not Active("unitframes") then
		return
	end
	bar:SetStatusBarColor(HealthColorFor(bar))
end

local function RecolorAllHealthBars()
	for bar in pairs(healthBars) do
		RecolorHealthBar(bar)
	end
end

-- Bars that lock their colour expect white so their own green atlas shows.
local function ResetHealthColors()
	for bar in pairs(healthBars) do
		if bar.lockColor then
			bar:SetStatusBarColor(1, 1, 1)
		end
	end
end

local function ApplyUnitFrames()
	local list = {}
	CollectUnitFrameBars(list)
	for _, bar in ipairs(list) do
		ApplyToBar(bar, "unitframes")
	end
	RecolorAllHealthBars()
end

-- Power bars get a pre-coloured atlas plus a white bar colour from Blizzard;
-- with a flat texture the colour has to come from the power type instead.
local function RecolorManaBar(manaBar)
	if not manaBar or tracked[manaBar] ~= "unitframes" or not Active("unitframes") then
		return
	end
	local info = manaBar.overrideInfo or (PowerBarColor and manaBar.powerToken and PowerBarColor[manaBar.powerToken])
	if info and info.r then
		manaBar:SetStatusBarColor(info.r, info.g, info.b)
	end
end

--------------------------------------------------------------------------------
-- Raid-style frames (compact party / raid frames)
--------------------------------------------------------------------------------

local function ApplyCompactFrame(frame)
	if not frame or (frame.IsForbidden and frame:IsForbidden()) then
		return
	end
	if frame.healthBar then
		ApplyToBar(frame.healthBar, "raidframes")
	end
	if frame.powerBar then
		ApplyToBar(frame.powerBar, "raidframes")
	end
end

local function ApplyCompactList(list)
	if type(list) == "table" then
		for _, frame in ipairs(list) do
			ApplyCompactFrame(frame)
		end
	end
end

local function ApplyRaidFrames()
	if CompactPartyFrame then
		ApplyCompactList(CompactPartyFrame.memberUnitFrames)
		ApplyCompactList(CompactPartyFrame.petUnitFrames)
	end
	for i = 1, 8 do
		local group = _G["CompactRaidGroup" .. i]
		if group then
			ApplyCompactList(group.memberUnitFrames)
		end
	end
	for i = 1, 80 do
		ApplyCompactFrame(_G["CompactRaidFrame" .. i])
	end
	local container = CompactRaidFrameContainer
	if container and type(container.ApplyToFrames) == "function" then
		pcall(container.ApplyToFrames, container, "normal", ApplyCompactFrame)
		pcall(container.ApplyToFrames, container, "mini", ApplyCompactFrame)
	end
end

--------------------------------------------------------------------------------
-- Cast bars
--------------------------------------------------------------------------------

local hookedCastBars = setmetatable({}, { __mode = "k" })

local function RecolorCastBar(bar, isFull)
	local ok, color = pcall(function()
		local info = bar:GetTypeInfo(bar.barType or CastingBarType.Standard)
		return isFull and info.classicFullColor or info.classicFillColor
	end)
	if ok and color and color.GetRGB then
		bar:SetStatusBarColor(color:GetRGB())
	else
		bar:SetStatusBarColor(1.0, 0.7, 0.0)
	end
end

local function ApplyToCastBar(bar, group)
	if not bar or type(bar.SetStatusBarTexture) ~= "function" then
		return
	end
	ApplyToBar(bar, group)
	if not bar.classicStyleCastBar then
		RecolorCastBar(bar, false)
	end
	if not hookedCastBars[bar] and type(bar.UpdateBarFillTexture) == "function" then
		hookedCastBars[bar] = true
		hooksecurefunc(bar, "UpdateBarFillTexture", function(self, isFull)
			local grp = tracked[self]
			if grp and Active(grp) and not self.classicStyleCastBar then
				RecolorCastBar(self, isFull)
			end
		end)
	end
end

local function ApplyCastBars()
	ApplyToCastBar(PlayerCastingBarFrame, "castbars")
	ApplyToCastBar(PetCastingBarFrame, "castbars")
	for _, frame in ipairs(TargetLikeFrames()) do
		if frame then
			ApplyToCastBar(frame.spellbar, "castbars")
		end
	end
end

--------------------------------------------------------------------------------
-- Nameplates
--------------------------------------------------------------------------------

local hookedNamePlates = setmetatable({}, { __mode = "k" })

local function ApplyNamePlateUnitFrame(unitFrame)
	if not unitFrame or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then
		return
	end
	local healthBar = unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar
	if healthBar then
		ApplyToBar(healthBar, "nameplates")
	end
	local castBar = unitFrame.CastBarsContainer and unitFrame.CastBarsContainer.castBar
	if castBar then
		ApplyToCastBar(castBar, "nameplates")
	end
	if not hookedNamePlates[unitFrame] and type(unitFrame.UpdateAnchors) == "function" then
		hookedNamePlates[unitFrame] = true
		-- UpdateAnchors sets the bar atlas directly on the texture, bypassing
		-- SetStatusBarTexture, so re-apply here.
		hooksecurefunc(unitFrame, "UpdateAnchors", function(self)
			if Active("nameplates") then
				ApplyNamePlateUnitFrame(self)
			end
		end)
	end
end

local function ApplyNamePlates()
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			if plate and not (plate.IsForbidden and plate:IsForbidden()) then
				ApplyNamePlateUnitFrame(plate.UnitFrame)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Personal resource display
--------------------------------------------------------------------------------

local function ApplyPersonal()
	local prd = PersonalResourceDisplayFrame
	if not prd then
		return
	end
	if prd.HealthBarsContainer then
		ApplyToBar(prd.HealthBarsContainer.healthBar, "personal")
	end
	ApplyToBar(prd.PowerBar, "personal")
	ApplyToBar(prd.AlternatePowerBar, "personal")
end

--------------------------------------------------------------------------------
-- Experience / reputation / honor bars
--------------------------------------------------------------------------------

local function ApplyStatusBars()
	local manager = StatusTrackingBarManager
	if not manager then
		return
	end
	local containers = manager.barContainers
	if type(containers) ~= "table" then
		containers = { manager.MainStatusTrackingBarContainer, manager.SecondaryStatusTrackingBarContainer }
	end
	for _, container in ipairs(containers) do
		if container and type(container.bars) == "table" then
			for _, bar in pairs(container.bars) do
				local statusBar = bar.StatusBar
				if statusBar then
					local tex = statusBar:GetStatusBarTexture()
					local atlas = tex and tex.GetAtlas and tex:GetAtlas()
					ApplyToBar(statusBar, "statusbars")
					local r, g, b = StatusTrackingColorForAtlas(atlas)
					if r then
						statusBar:SetStatusBarColor(r, g, b)
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Cooldown manager bars
--------------------------------------------------------------------------------

local hookedViewers = setmetatable({}, { __mode = "k" })

local function ApplyCooldownViewer(viewer)
	if not viewer or not viewer.itemFramePool then
		return
	end
	for item in viewer.itemFramePool:EnumerateActive() do
		if item.Bar then
			ApplyToBar(item.Bar, "cooldowns")
		end
	end
	if not hookedViewers[viewer] and type(viewer.RefreshLayout) == "function" then
		hookedViewers[viewer] = true
		hooksecurefunc(viewer, "RefreshLayout", function(self)
			if Active("cooldowns") then
				ApplyCooldownViewer(self)
			end
		end)
	end
end

local function ApplyCooldowns()
	ApplyCooldownViewer(BuffBarCooldownViewer)
end

--------------------------------------------------------------------------------
-- Events & hooks
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" and Active("nameplates") then
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		if plate and not (plate.IsForbidden and plate:IsForbidden()) then
			ApplyNamePlateUnitFrame(plate.UnitFrame)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if Active("personal") then
			ApplyPersonal()
		end
	end
end)

local hooksInstalled = false

local function InstallHooks()
	if hooksInstalled then
		return
	end
	hooksInstalled = true
	if type(UnitFrameManaBar_UpdateType) == "function" then
		hooksecurefunc("UnitFrameManaBar_UpdateType", function(manaBar)
			pcall(RecolorManaBar, manaBar)
		end)
	end
	if type(UnitFrameManaBar_UpdateTypeOld) == "function" then
		hooksecurefunc("UnitFrameManaBar_UpdateTypeOld", function(manaBar)
			pcall(RecolorManaBar, manaBar)
		end)
	end
	if type(UnitFrameHealthBar_Update) == "function" then
		hooksecurefunc("UnitFrameHealthBar_Update", function(statusbar)
			pcall(RecolorHealthBar, statusbar)
		end)
	end
	-- Compact frames are (re)configured through these whenever they are created
	-- or the raid layout changes.
	for _, fname in ipairs({ "DefaultCompactUnitFrameSetup", "DefaultCompactMiniFrameSetup" }) do
		if type(_G[fname]) == "function" then
			hooksecurefunc(fname, function(frame)
				if Active("raidframes") then
					ApplyCompactFrame(frame)
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

local appliers = {
	unitframes = ApplyUnitFrames,
	raidframes = ApplyRaidFrames,
	nameplates = ApplyNamePlates,
	personal = ApplyPersonal,
	statusbars = ApplyStatusBars,
	castbars = ApplyCastBars,
	cooldowns = ApplyCooldowns,
}

local function ApplyAll()
	for group, apply in pairs(appliers) do
		if M.db[group] then
			apply()
		end
	end
	-- Power bars need their colour re-derived after the texture swap.
	local list = {}
	CollectUnitFrameBars(list)
	for _, bar in ipairs(list) do
		if bar and bar.powerToken then
			pcall(RecolorManaBar, bar)
		end
	end
end

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	InstallHooks()
	ApplyAll()
	eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function M:OnDisable()
	eventFrame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
	eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
	for group in pairs(appliers) do
		RestoreGroup(group)
	end
	ResetHealthColors()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if appliers[key] then
		if value then
			appliers[key]()
			if key == "unitframes" then
				local list = {}
				CollectUnitFrameBars(list)
				for _, bar in ipairs(list) do
					if bar and bar.powerToken then
						pcall(RecolorManaBar, bar)
					end
				end
			end
		else
			RestoreGroup(key)
			if key == "unitframes" then
				ResetHealthColors()
			end
		end
	elseif key == "texture" then
		for group in pairs(appliers) do
			if db[group] then
				ReapplyGroup(group)
			end
		end
		RecolorAllHealthBars()
	elseif key == "healthColor" then
		RecolorAllHealthBars()
	end
end

MelloUI:Profile("BarTextures", "nameplate events", eventFrame)
MelloUI:Profile("BarTextures", "nameplate relayout", ApplyNamePlateUnitFrame)
MelloUI:Profile("BarTextures", "texture (re)apply", SetTexture)
MelloUI:Profile("BarTextures", "health recolour", RecolorHealthBar)
