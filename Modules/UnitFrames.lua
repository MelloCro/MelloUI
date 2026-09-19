--------------------------------------------------------------------------------
-- MelloUI - Unit Frames
--
-- Layout tweaks for the player, target and focus frames:
--   * names centred above the health bar
--   * transparent name band (the reaction coloured strip behind target names)
--   * no red combat flash / status glow around the frames
--   * adjustable frame art opacity
--
-- Combined with Dark Mode, Bar Textures (class / reaction health colour) and
-- Bar Text this gives the flat "RougeUI" look.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI

local M = MelloUI:RegisterModule("UnitFrames", {
	title = "Unit Frames",
	desc = "Centred names, transparent name band, no combat flash and frame art opacity for player, target and focus.",
	defaults = {
		centerNames = true,
		hideReputationColor = true,
		hideCombatGlow = true,
		hideStatusGlow = true,
		frameAlpha = 1,
	},
	options = {
		{ type = "header", name = "Names" },
		{ type = "toggle", key = "centerNames", name = "Centre Names", desc = "Centre the unit name above the health bar." },
		{ type = "toggle", key = "hideReputationColor", name = "Transparent Name Band",
		  desc = "Hide the reaction coloured strip behind target and focus names." },
		{ type = "header", name = "Glows" },
		{ type = "toggle", key = "hideCombatGlow", name = "Hide Combat Flash",
		  desc = "Hide the red flash around the player, target, focus, pet and party frames while in combat or when a target attacks." },
		{ type = "toggle", key = "hideStatusGlow", name = "Hide Status Glow",
		  desc = "Hide the glow around the player portrait and name that shows resting (yellow) and combat (red)." },
		{ type = "header", name = "Frame Art" },
		{ type = "slider", key = "frameAlpha", name = "Frame Art Opacity", min = 0.1, max = 1, step = 0.05, percent = true,
		  desc = "Opacity of the frame art around the bars and portraits. The bars themselves stay solid." },
	},
})

local hiddenParent = CreateFrame("Frame", "MelloUIUnitFramesHidden", UIParent)
hiddenParent:Hide()

local originalParents = setmetatable({}, { __mode = "k" })
local originalNameLayout = setmetatable({}, { __mode = "k" })
local hooksInstalled = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function TargetLikeFrames()
	return { TargetFrame, FocusFrame }
end

local function SetHidden(region, hidden)
	if not region or not region.SetParent then
		return
	end
	if hidden then
		if region:GetParent() ~= hiddenParent then
			originalParents[region] = region:GetParent()
			region:SetParent(hiddenParent)
		end
	elseif region:GetParent() == hiddenParent then
		region:SetParent(originalParents[region] or UIParent)
	end
end

--------------------------------------------------------------------------------
-- Names
--------------------------------------------------------------------------------

local function RememberName(fs)
	if originalNameLayout[fs] then
		return
	end
	local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
	originalNameLayout[fs] = {
		point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y,
		width = fs:GetWidth(), justify = fs:GetJustifyH(),
	}
end

local function CenterName(fs, container)
	if not fs or not container then
		return
	end
	RememberName(fs)
	fs:ClearAllPoints()
	fs:SetPoint("BOTTOM", container, "TOP", 0, 1)
	fs:SetWidth(container:GetWidth() or 124)
	fs:SetJustifyH("CENTER")
end

local function RestoreName(fs)
	local saved = fs and originalNameLayout[fs]
	if not saved then
		return
	end
	fs:ClearAllPoints()
	if saved.point then
		fs:SetPoint(saved.point, saved.relativeTo, saved.relativePoint, saved.x or 0, saved.y or 0)
	end
	if saved.width and saved.width > 0 then
		fs:SetWidth(saved.width)
	end
	fs:SetJustifyH(saved.justify or "LEFT")
end

local function PlayerNameContainer()
	local content = PlayerFrame and PlayerFrame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	return main and main.HealthBarsContainer
end

local function ApplyNames()
	local on = M.isEnabled and M.db.centerNames
	if PlayerName then
		if on then
			CenterName(PlayerName, PlayerNameContainer())
		else
			RestoreName(PlayerName)
		end
	end
	for _, frame in ipairs(TargetLikeFrames()) do
		local main = frame and frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
		if main and main.Name then
			if on then
				CenterName(main.Name, main.HealthBarsContainer)
			else
				RestoreName(main.Name)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Name band, glows, frame art
--------------------------------------------------------------------------------

local hookedBands = setmetatable({}, { __mode = "k" })

local function ApplyReputationColor()
	local hide = M.isEnabled and M.db.hideReputationColor
	for _, frame in ipairs(TargetLikeFrames()) do
		local main = frame and frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
		local band = main and main.ReputationColor
		if band then
			band:SetAlpha(hide and 0 or 1)
			if not hookedBands[band] then
				hookedBands[band] = true
				-- Blizzard recolours the band on every target change with
				-- SetVertexColor(r, g, b, a), which also resets its alpha.
				hooksecurefunc(band, "SetVertexColor", function(self)
					if M.isEnabled and M.db.hideReputationColor then
						self:SetAlpha(0)
					end
				end)
			end
		end
	end
end

local function CombatFlashTextures()
	local list = {}
	if PlayerFrame and PlayerFrame.PlayerFrameContainer then
		list[#list + 1] = PlayerFrame.PlayerFrameContainer.FrameFlash
	end
	for _, frame in ipairs(TargetLikeFrames()) do
		if frame and frame.TargetFrameContainer then
			list[#list + 1] = frame.TargetFrameContainer.Flash
		end
	end
	list[#list + 1] = PetFrameFlash
	if PartyFrame then
		for i = 1, 4 do
			local member = PartyFrame["MemberFrame" .. i]
			if member then
				list[#list + 1] = member.Flash
				if member.PetFrame then
					list[#list + 1] = member.PetFrame.Flash
				end
			end
		end
	end
	return list
end

local function StatusGlowTextures()
	local list = {}
	local content = PlayerFrame and PlayerFrame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	if main then
		list[#list + 1] = main.StatusTexture
	end
	list[#list + 1] = PetAttackModeTexture
	return list
end

local function ApplyGlows()
	local hideCombat = M.isEnabled and M.db.hideCombatGlow
	for _, tex in ipairs(CombatFlashTextures()) do
		SetHidden(tex, hideCombat)
	end
	local hideStatus = M.isEnabled and M.db.hideStatusGlow
	for _, tex in ipairs(StatusGlowTextures()) do
		SetHidden(tex, hideStatus)
	end
end

local function FrameArtTextures()
	local list = {}
	local container = PlayerFrame and PlayerFrame.PlayerFrameContainer
	if container then
		list[#list + 1] = container.FrameTexture
		list[#list + 1] = container.VehicleFrameTexture
		list[#list + 1] = container.AlternatePowerFrameTexture
	end
	for _, frame in ipairs(TargetLikeFrames()) do
		local c = frame and frame.TargetFrameContainer
		if c then
			list[#list + 1] = c.FrameTexture
			list[#list + 1] = c.BossPortraitFrameTexture
		end
		if frame and frame.totFrame then
			list[#list + 1] = frame.totFrame.FrameTexture
		end
	end
	list[#list + 1] = PetFrameTexture
	if PartyFrame then
		for i = 1, 4 do
			local member = PartyFrame["MemberFrame" .. i]
			if member then
				list[#list + 1] = member.Texture
				list[#list + 1] = member.VehicleTexture
				if member.PetFrame then
					list[#list + 1] = member.PetFrame.Texture
				end
			end
		end
	end
	return list
end

local function ApplyFrameAlpha()
	local alpha = M.isEnabled and (tonumber(M.db.frameAlpha) or 1) or 1
	for _, tex in ipairs(FrameArtTextures()) do
		if tex and tex.SetAlpha then
			tex:SetAlpha(alpha)
		end
	end
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

local function InstallHooks()
	if hooksInstalled then
		return
	end
	hooksInstalled = true
	-- Blizzard re-anchors the player name when switching to / from vehicle art.
	if type(PlayerFrame_UpdatePlayerNameTextAnchor) == "function" then
		hooksecurefunc("PlayerFrame_UpdatePlayerNameTextAnchor", function()
			if M.isEnabled and M.db.centerNames and PlayerName then
				originalNameLayout[PlayerName] = nil
				CenterName(PlayerName, PlayerNameContainer())
			end
		end)
	end
	-- Art swaps (vehicle, alternate power) re-show textures; re-apply then.
	for _, name in ipairs({ "PlayerFrame_ToPlayerArt", "PlayerFrame_ToVehicleArt" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function()
				if M.isEnabled then
					ApplyGlows()
					ApplyFrameAlpha()
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

local function ApplyAll()
	ApplyNames()
	ApplyReputationColor()
	ApplyGlows()
	ApplyFrameAlpha()
end

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	InstallHooks()
	ApplyAll()
end

function M:OnDisable()
	ApplyAll()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	ApplyAll()
end
