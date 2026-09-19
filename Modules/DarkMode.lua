--------------------------------------------------------------------------------
-- MelloUI - Dark Mode
--
-- Darkens the default Blizzard art of unit frames, cast bars, action bars,
-- nameplates, the personal resource display, the cooldown manager, buff and
-- debuff icons, the micro menu and the bag bar by desaturating and tinting the
-- frame textures. No frame layout is touched, so Edit Mode keeps working and
-- nothing taints secure frames.
--
-- Frame keys were taken from the World of Warcraft: Forever (Camelot) UI source,
-- which uses the retail (Dragonflight style) HUD with Camelot specific overrides.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI

local M = MelloUI:RegisterModule("DarkMode", {
	title = "Dark Mode",
	desc = "Darkens the Blizzard artwork of unit frames, cast bars, action bars, nameplates, cooldown manager, auras and menu bars.",
	defaults = {
		shade = 0.25,        -- brightness of the darkened art (0 = black, 1 = untouched)
		desaturate = true,   -- remove the gold / bronze tint
		unitframes = true,
		castbar = true,
		actionbars = true,
		gryphons = true,     -- also darken the main bar end caps (gryphons)
		nameplates = true,
		personal = true,     -- personal resource display
		statusbars = true,   -- experience / reputation / honor bars
		cooldowns = true,    -- cooldown manager icons and bars
		auras = true,        -- buff / debuff icons
		auraIconBorder = true, -- add a dark border around buff / debuff icons
		keepDispelColor = true, -- leave the coloured dispel-type debuff borders alone
		micromenu = true,    -- micro menu and bag bar
		minimap = true,      -- minimap ring, header and buttons
		chat = true,         -- chat tabs, edit box and buttons
	},
	options = {
		{ type = "header", name = "Appearance" },
		{ type = "slider", key = "shade", name = "Brightness", min = 0, max = 1, step = 0.05, percent = true,
		  desc = "How bright the darkened artwork is. Lower values are darker." },
		{ type = "toggle", key = "desaturate", name = "Desaturate",
		  desc = "Remove the gold and bronze colours so the art becomes grey before it is darkened." },
		{ type = "header", name = "Components" },
		{ type = "toggle", key = "unitframes", name = "Unit Frames",
		  desc = "Player, target, focus, pet, party, boss and target-of-target frames." },
		{ type = "toggle", key = "castbar", name = "Cast Bars",
		  desc = "Player, pet, target, focus and boss cast bars." },
		{ type = "toggle", key = "actionbars", name = "Action Bars",
		  desc = "All action bar buttons, the stance bar, pet bar, possess bar and extra action button." },
		{ type = "toggle", key = "gryphons", name = "Action Bar End Caps",
		  desc = "Also darken the gryphons / end caps and border art of the main action bar." },
		{ type = "toggle", key = "nameplates", name = "Nameplates",
		  desc = "Health bar backgrounds/borders and cast bars on nameplates." },
		{ type = "toggle", key = "personal", name = "Personal Resource Display",
		  desc = "The health and power bars shown under your character." },
		{ type = "toggle", key = "statusbars", name = "Experience & Reputation Bars",
		  desc = "Frame, background and segment dividers of the experience, reputation and honor bars." },
		{ type = "toggle", key = "cooldowns", name = "Cooldown Manager",
		  desc = "Icon frames and bar backgrounds of the Essential, Utility and Buff cooldown viewers." },
		{ type = "toggle", key = "micromenu", name = "Micro Menu & Bag Bar",
		  desc = "The menu buttons (character, spellbook, ...) and the bag buttons." },
		{ type = "toggle", key = "minimap", name = "Minimap",
		  desc = "Minimap ring, zone text header, day/night indicator frame, tracking, calendar, zoom and addon buttons." },
		{ type = "toggle", key = "chat", name = "Chat Frame",
		  desc = "Chat tabs, the chat input box and the chat buttons. Window background colours stay as configured in the chat settings." },
		{ type = "header", name = "Buffs & Debuffs" },
		{ type = "toggle", key = "auras", name = "Buffs & Debuffs",
		  desc = "Darken the borders of your buff and debuff icons." },
		{ type = "toggle", key = "auraIconBorder", name = "Icon Border",
		  desc = "Draw a thin dark border around every buff and debuff icon." },
		{ type = "toggle", key = "keepDispelColor", name = "Keep Dispel Colours",
		  desc = "Leave the coloured magic / curse / poison / disease debuff borders untouched." },
	},
})

--------------------------------------------------------------------------------
-- Texture registry
--------------------------------------------------------------------------------

local function NewGroup()
	return setmetatable({}, { __mode = "k" })
end

local COMPONENTS = { "unitframes", "castbar", "actionbars", "nameplates", "personal", "statusbars", "cooldowns", "auras", "micromenu", "minimap", "chat" }

local groups = {}
for _, name in ipairs(COMPONENTS) do
	groups[name] = NewGroup()
end

-- Textures created by this module (e.g. aura icon borders): hidden instead of
-- reset when a component is switched off.
local ownedTextures = setmetatable({}, { __mode = "k" })

local function IsTexture(obj)
	return type(obj) == "table" and obj.SetVertexColor ~= nil and obj.GetObjectType ~= nil
end

local function Shade(group, tex)
	if not IsTexture(tex) then
		return
	end
	local db = M.db
	groups[group][tex] = true
	if tex.SetDesaturated then
		tex:SetDesaturated(db.desaturate)
	end
	tex:SetVertexColor(db.shade, db.shade, db.shade)
	if ownedTextures[tex] then
		tex:Show()
	end
end

local function Unshade(tex)
	if ownedTextures[tex] then
		tex:Hide()
		return
	end
	if tex.SetDesaturated then
		tex:SetDesaturated(false)
	end
	tex:SetVertexColor(1, 1, 1)
end

local function ShadeAll(group, list)
	for _, tex in ipairs(list) do
		Shade(group, tex)
	end
end

local function RestoreGroup(group)
	for tex in pairs(groups[group]) do
		Unshade(tex)
	end
	groups[group] = NewGroup()
end

local function ReapplyGroup(group)
	for tex in pairs(groups[group]) do
		Shade(group, tex)
	end
end

local function Active(component)
	return M.isEnabled and M.db and M.db[component]
end

-- Collect texture regions of a frame whose atlas matches (case-insensitive).
local function CollectRegionsByAtlas(frame, atlasName, list)
	if not frame or not frame.GetRegions then
		return
	end
	atlasName = atlasName:lower()
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetAtlas then
			local atlas = region:GetAtlas()
			if type(atlas) == "string" and atlas:lower() == atlasName then
				list[#list + 1] = region
			end
		end
	end
end

local function CollectButtonStateTextures(button, list)
	if not button then
		return
	end
	if button.GetNormalTexture then list[#list + 1] = button:GetNormalTexture() end
	if button.GetPushedTexture then list[#list + 1] = button:GetPushedTexture() end
	if button.GetDisabledTexture then list[#list + 1] = button:GetDisabledTexture() end
end

--------------------------------------------------------------------------------
-- Unit frames
--------------------------------------------------------------------------------

local function CollectPlayerFrame(list)
	local container = PlayerFrame and PlayerFrame.PlayerFrameContainer
	local content = PlayerFrame and PlayerFrame.PlayerFrameContent
	if container then
		list[#list + 1] = container.FrameTexture
		list[#list + 1] = container.AlternatePowerFrameTexture
		list[#list + 1] = container.VehicleFrameTexture
	end
	if content then
		local main = content.PlayerFrameContentMain
		local ctx = content.PlayerFrameContentContextual
		if main then
			list[#list + 1] = main.LevelBackgroundCircle
			list[#list + 1] = main.PvpBackgroundCircle
		end
		if ctx then
			list[#list + 1] = ctx.PlayerPortraitCornerIcon
		end
	end
end

-- TargetFrame, FocusFrame and Boss1-5TargetFrame all share TargetFrameTemplate.
local function CollectTargetLikeFrame(frame, list)
	if not frame then
		return
	end
	local container = frame.TargetFrameContainer
	local content = frame.TargetFrameContent
	if container then
		list[#list + 1] = container.FrameTexture
		list[#list + 1] = container.BossPortraitFrameTexture
	end
	if content then
		local main = content.TargetFrameContentMain
		local ctx = content.TargetFrameContentContextual
		if main then
			list[#list + 1] = main.LevelBackgroundCircle
		end
		if ctx then
			list[#list + 1] = ctx.PvpBackgroundCircle
		end
	end
	if frame.totFrame then
		list[#list + 1] = frame.totFrame.FrameTexture
	end
end

local function CollectPartyFrames(list)
	if not PartyFrame then
		return
	end
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

local function TargetLikeFrames()
	local frames = { TargetFrame, FocusFrame }
	for i = 1, 5 do
		frames[#frames + 1] = _G["Boss" .. i .. "TargetFrame"]
	end
	return frames
end

local function ApplyUnitFrames()
	local list = {}
	CollectPlayerFrame(list)
	for _, frame in ipairs(TargetLikeFrames()) do
		CollectTargetLikeFrame(frame, list)
	end
	list[#list + 1] = PetFrameTexture
	CollectPartyFrames(list)
	ShadeAll("unitframes", list)
end

--------------------------------------------------------------------------------
-- Cast bars
--------------------------------------------------------------------------------

local function CollectCastBar(bar, list)
	if not bar then
		return
	end
	list[#list + 1] = bar.Border
	list[#list + 1] = bar.TextBorder
	list[#list + 1] = bar.Background
	list[#list + 1] = bar.BorderShield
end

local function ApplyCastBars()
	local list = {}
	CollectCastBar(PlayerCastingBarFrame, list)
	CollectCastBar(PetCastingBarFrame, list)
	for _, frame in ipairs(TargetLikeFrames()) do
		if frame then
			CollectCastBar(frame.spellbar, list)
		end
	end
	ShadeAll("castbar", list)
end

--------------------------------------------------------------------------------
-- Action bars
--------------------------------------------------------------------------------

local BUTTON_PREFIXES = {
	{ "ActionButton", 12 },
	{ "MultiBarBottomLeftButton", 12 },
	{ "MultiBarBottomRightButton", 12 },
	{ "MultiBarRightButton", 12 },
	{ "MultiBarLeftButton", 12 },
	{ "MultiBar5Button", 12 },
	{ "MultiBar6Button", 12 },
	{ "MultiBar7Button", 12 },
	{ "StanceButton", 10 },
	{ "PetActionButton", 10 },
	{ "PossessButton", 2 },
}

local function CollectActionButton(button, list)
	if not button then
		return
	end
	list[#list + 1] = button.NormalTexture or (button.GetNormalTexture and button:GetNormalTexture())
	list[#list + 1] = button.PushedTexture or (button.GetPushedTexture and button:GetPushedTexture())
	list[#list + 1] = button.SlotBackground
	list[#list + 1] = button.SlotArt
	list[#list + 1] = button.style -- ExtraActionButton art
end

local function CollectMainBarArt(list)
	local bar = MainActionBar or MainMenuBar
	if not bar then
		return
	end
	list[#list + 1] = bar.BorderArt
	if bar.EndCaps then
		if bar.EndCaps.LeftEndCap then
			list[#list + 1] = bar.EndCaps.LeftEndCap.Texture
		end
		if bar.EndCaps.RightEndCap then
			list[#list + 1] = bar.EndCaps.RightEndCap.Texture
		end
	end
	local pager = bar.ActionBarPageNumber
	if pager then
		CollectActionButton(pager.UpButton, list)
		CollectActionButton(pager.DownButton, list)
	end
end

local function ApplyActionBars()
	local list = {}
	for _, entry in ipairs(BUTTON_PREFIXES) do
		for i = 1, entry[2] do
			CollectActionButton(_G[entry[1] .. i], list)
		end
	end
	CollectActionButton(ExtraActionButton1, list)
	if M.db.gryphons then
		CollectMainBarArt(list)
	end
	ShadeAll("actionbars", list)
end

--------------------------------------------------------------------------------
-- Nameplates
--------------------------------------------------------------------------------

local hookedNamePlates = setmetatable({}, { __mode = "k" })

local function StyleNamePlateUnitFrame(unitFrame)
	if not unitFrame or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then
		return
	end
	local list = {}
	local healthBar = unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar
	if healthBar then
		list[#list + 1] = healthBar.bgTexture
	end
	local castBar = unitFrame.CastBarsContainer and unitFrame.CastBarsContainer.castBar
	if castBar then
		list[#list + 1] = castBar.Border
		list[#list + 1] = castBar.Background
	end
	ShadeAll("nameplates", list)

	-- Blizzard re-anchors and re-textures the bars whenever the nameplate style
	-- or size changes; re-apply afterwards.
	if not hookedNamePlates[unitFrame] and type(unitFrame.UpdateAnchors) == "function" then
		hookedNamePlates[unitFrame] = true
		hooksecurefunc(unitFrame, "UpdateAnchors", function(self)
			if Active("nameplates") then
				StyleNamePlateUnitFrame(self)
			end
		end)
	end
end

local function StyleNamePlate(plate)
	if plate and not (plate.IsForbidden and plate:IsForbidden()) then
		StyleNamePlateUnitFrame(plate.UnitFrame)
	end
end

local function ApplyNamePlates()
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			StyleNamePlate(plate)
		end
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" and Active("nameplates") then
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		StyleNamePlate(plate)
	end
end)

--------------------------------------------------------------------------------
-- Personal resource display
--------------------------------------------------------------------------------

local function ApplyPersonalResourceDisplay()
	local prd = PersonalResourceDisplayFrame
	if not prd then
		return
	end
	local list = {}
	local bars = {
		prd.HealthBarsContainer and prd.HealthBarsContainer.healthBar,
		prd.PowerBar,
		prd.AlternatePowerBar,
	}
	for _, bar in ipairs(bars) do
		CollectRegionsByAtlas(bar, "UI-HUD-CoolDownManager-Bar-BG", list)
	end
	ShadeAll("personal", list)
end

--------------------------------------------------------------------------------
-- Experience / reputation / honor bars
--------------------------------------------------------------------------------

local hookedStatusContainers = setmetatable({}, { __mode = "k" })

local function CollectStatusDividers(container, list)
	local pool = container.HorizontalDividersPool
	if pool and pool.EnumerateActive then
		for divider in pool:EnumerateActive() do
			list[#list + 1] = divider.BarDividerTexture
		end
	end
end

local function StyleStatusContainer(container)
	if not container then
		return
	end
	local list = { container.BarFrameTexture }
	if type(container.bars) == "table" then
		for _, bar in pairs(container.bars) do
			if bar.StatusBar then
				list[#list + 1] = bar.StatusBar.Background
			end
		end
	end
	CollectStatusDividers(container, list)
	ShadeAll("statusbars", list)

	-- Dividers are re-created from a pool whenever the segment count changes.
	if not hookedStatusContainers[container] and type(container.UpdateDividers) == "function" then
		hookedStatusContainers[container] = true
		hooksecurefunc(container, "UpdateDividers", function(self)
			if Active("statusbars") then
				local dividers = {}
				CollectStatusDividers(self, dividers)
				ShadeAll("statusbars", dividers)
			end
		end)
	end
end

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
		StyleStatusContainer(container)
	end
end

--------------------------------------------------------------------------------
-- Cooldown manager
--------------------------------------------------------------------------------

local COOLDOWN_VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }

local function StyleCooldownItem(item)
	if not item then
		return
	end
	local list = {}
	-- Icon overlay (bevelled frame around the icon). For bar items the icon
	-- lives in a child frame that is also called Icon.
	CollectRegionsByAtlas(item, "UI-HUD-CoolDownManager-IconOverlay", list)
	if item.Icon and item.Icon.GetRegions then
		CollectRegionsByAtlas(item.Icon, "UI-HUD-CoolDownManager-IconOverlay", list)
	end
	if item.Bar then
		list[#list + 1] = item.Bar.BarBG
	end
	if item.DebuffBorder and not M.db.keepDispelColor then
		list[#list + 1] = item.DebuffBorder.Texture
	end
	ShadeAll("cooldowns", list)
end

local hookedViewers = setmetatable({}, { __mode = "k" })

local function StyleCooldownViewer(viewer)
	if not viewer or not viewer.itemFramePool then
		return
	end
	for item in viewer.itemFramePool:EnumerateActive() do
		StyleCooldownItem(item)
	end
	if not hookedViewers[viewer] and type(viewer.RefreshLayout) == "function" then
		hookedViewers[viewer] = true
		hooksecurefunc(viewer, "RefreshLayout", function(self)
			if Active("cooldowns") then
				StyleCooldownViewer(self)
			end
		end)
	end
end

local function ApplyCooldownManager()
	for _, name in ipairs(COOLDOWN_VIEWERS) do
		StyleCooldownViewer(_G[name])
	end
end

--------------------------------------------------------------------------------
-- Buffs & debuffs
--------------------------------------------------------------------------------

local auraIconBorders = setmetatable({}, { __mode = "k" })

local function GetAuraIconBorder(button)
	local border = auraIconBorders[button]
	if border then
		return border
	end
	if not button.Icon or not button.CreateTexture then
		return nil
	end
	border = button:CreateTexture(nil, "BACKGROUND", nil, -1)
	border:SetColorTexture(1, 1, 1)
	border:SetPoint("TOPLEFT", button.Icon, "TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", button.Icon, "BOTTOMRIGHT", 1, -1)
	border:Hide()
	ownedTextures[border] = true
	auraIconBorders[button] = border
	return border
end

local function CollectAuraButton(button, list)
	-- Only real aura buttons: the private aura anchors in the same list have an
	-- Icon *frame* instead of a texture and no border regions.
	if not button or type(button) ~= "table" or not IsTexture(button.Icon) then
		return
	end
	if button.TempEnchantBorder then
		list[#list + 1] = button.TempEnchantBorder
	end
	if button.DebuffBorder and not M.db.keepDispelColor then
		list[#list + 1] = button.DebuffBorder
	end
	if M.db.auraIconBorder then
		list[#list + 1] = GetAuraIconBorder(button)
	end
end

local function CollectAuraFrame(auraFrame, list)
	if not auraFrame or type(auraFrame.auraFrames) ~= "table" then
		return
	end
	for _, button in ipairs(auraFrame.auraFrames) do
		CollectAuraButton(button, list)
	end
end

local function ApplyAuras()
	local list = {}
	CollectAuraFrame(BuffFrame, list)
	CollectAuraFrame(DebuffFrame, list)
	if BuffFrame and BuffFrame.ConsolidatedBuffs and BuffFrame.ConsolidatedBuffs.Tooltip then
		CollectAuraFrame(BuffFrame.ConsolidatedBuffs.Tooltip.Auras, list)
	end
	if DeadlyDebuffFrame then
		CollectAuraButton(DeadlyDebuffFrame.Debuff, list)
	end
	ShadeAll("auras", list)
end

--------------------------------------------------------------------------------
-- Micro menu & bag bar
--------------------------------------------------------------------------------

local MICRO_BUTTONS = {
	"CharacterMicroButton", "ProfessionMicroButton", "SpellbookMicroButton", "TalentMicroButton",
	"PlayerSpellsMicroButton", "LegacyMicroButton", "AchievementMicroButton", "QuestLogMicroButton",
	"HousingMicroButton", "GuildMicroButton", "LFDMicroButton", "CollectionsMicroButton",
	"EJMicroButton", "HelpMicroButton", "StoreMicroButton", "MainMenuMicroButton",
}

local BAG_BUTTONS = {
	"MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
	"CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton", "BagBarExpandToggle",
}

local function ApplyMicroMenu()
	local list = {}
	if MicroMenu then
		list[#list + 1] = MicroMenu.BorderArt
		list[#list + 1] = MicroMenu.BackgroundArt
	end
	for _, name in ipairs(MICRO_BUTTONS) do
		local button = _G[name]
		if button then
			CollectButtonStateTextures(button, list)
			list[#list + 1] = button.Background
			list[#list + 1] = button.PushedBackground
		end
	end
	if BagsBar then
		list[#list + 1] = BagsBar.BorderArt
	end
	for _, name in ipairs(BAG_BUTTONS) do
		CollectButtonStateTextures(_G[name], list)
	end
	ShadeAll("micromenu", list)
end

--------------------------------------------------------------------------------
-- Minimap
--------------------------------------------------------------------------------

local NINE_SLICE_PIECES = {
	"TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
	"TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

local function CollectNineSlice(frame, list)
	if not frame then
		return
	end
	for _, piece in ipairs(NINE_SLICE_PIECES) do
		list[#list + 1] = frame[piece]
	end
end

local function ApplyMinimap()
	local list = {}
	-- Ring around the map (Camelot swaps the atlas when the map rotation setting changes).
	list[#list + 1] = MinimapCompassTexture
	list[#list + 1] = MinimapCompassTextureUnderlay

	local cluster = MinimapCluster
	if cluster then
		-- Zone text header (nine-slice) and tracking button.
		CollectNineSlice(cluster.BorderTop, list)
		if cluster.Tracking then
			list[#list + 1] = cluster.Tracking.Background
			CollectButtonStateTextures(cluster.Tracking.Button, list)
		end
		-- Camelot day / night cycle indicator: only its border ring, not the sun / moon art.
		CollectRegionsByAtlas(cluster.DielFrame, "UI-HUD-Minimap-Frame-Cycle", list)
	end

	if Minimap then
		CollectButtonStateTextures(Minimap.ZoomIn, list)
		CollectButtonStateTextures(Minimap.ZoomOut, list)
	end
	CollectButtonStateTextures(GameTimeFrame, list)
	CollectButtonStateTextures(AddonCompartmentFrame, list)
	CollectButtonStateTextures(ExpansionLandingPageMinimapButton, list)

	ShadeAll("minimap", list)
end

--------------------------------------------------------------------------------
-- Chat frame
--------------------------------------------------------------------------------

local CHAT_BUTTONS = {
	"ChatFrameMenuButton", "ChatFrameChannelButton",
	"ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
}

local function CollectChatWindow(index, list)
	local name = "ChatFrame" .. index
	local frame = _G[name]
	if not frame then
		return
	end

	-- Tab background (the selected / highlight overlays keep the user's tab colour).
	local tab = _G[name .. "Tab"]
	if tab then
		list[#list + 1] = tab.Left
		list[#list + 1] = tab.Middle
		list[#list + 1] = tab.Right
	end
	local minimized = _G[name .. "Minimized"]
	if minimized then
		list[#list + 1] = minimized.Left
		list[#list + 1] = minimized.Middle
		list[#list + 1] = minimized.Right
	end

	-- Input box border.
	local editBox = frame.editBox or _G[name .. "EditBox"]
	if editBox then
		local editName = editBox:GetName()
		if editName then
			list[#list + 1] = _G[editName .. "Left"]
			list[#list + 1] = _G[editName .. "Mid"]
			list[#list + 1] = _G[editName .. "Right"]
		end
		list[#list + 1] = editBox.focusLeft
		list[#list + 1] = editBox.focusMid
		list[#list + 1] = editBox.focusRight
	end

	-- Small buttons attached to the window.
	CollectButtonStateTextures(frame.ResizeButton, list)
	CollectButtonStateTextures(frame.ScrollToBottomButton, list)
	if frame.buttonFrame then
		CollectButtonStateTextures(frame.buttonFrame.minimizeButton, list)
	end
	if minimized then
		CollectButtonStateTextures(_G[name .. "MinimizedMaximizeButton"], list)
	end
end

local function ApplyChat()
	local list = {}
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		CollectChatWindow(i, list)
	end
	for _, buttonName in ipairs(CHAT_BUTTONS) do
		CollectButtonStateTextures(_G[buttonName], list)
	end
	if GeneralDockManager then
		CollectButtonStateTextures(GeneralDockManager.overflowButton, list)
	end
	ShadeAll("chat", list)
end

--------------------------------------------------------------------------------
-- Hooks (installed once, gated by Active())
--------------------------------------------------------------------------------

local hooksInstalled = false

local function InstallHooks()
	if hooksInstalled then
		return
	end
	hooksInstalled = true

	-- Player frame swaps art when entering / leaving vehicles.
	for _, fname in ipairs({ "PlayerFrame_ToPlayerArt", "PlayerFrame_ToVehicleArt", "PlayerFrame_UpdateArt" }) do
		if type(_G[fname]) == "function" then
			hooksecurefunc(fname, function()
				if Active("unitframes") then
					local list = {}
					CollectPlayerFrame(list)
					ShadeAll("unitframes", list)
				end
			end)
		end
	end

	-- Target style frames swap atlases for elite / rare / boss classifications.
	for _, frame in ipairs(TargetLikeFrames()) do
		if frame and type(frame.CheckClassification) == "function" then
			hooksecurefunc(frame, "CheckClassification", function(self)
				if Active("unitframes") then
					local list = {}
					CollectTargetLikeFrame(self, list)
					ShadeAll("unitframes", list)
				end
			end)
		end
	end

	-- Bag buttons re-set their atlases when bags change.
	for _, name in ipairs(BAG_BUTTONS) do
		local button = _G[name]
		if button and type(button.UpdateTextures) == "function" then
			hooksecurefunc(button, "UpdateTextures", function(self)
				if Active("micromenu") then
					local list = {}
					CollectButtonStateTextures(self, list)
					ShadeAll("micromenu", list)
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
	castbar = ApplyCastBars,
	actionbars = ApplyActionBars,
	nameplates = ApplyNamePlates,
	personal = ApplyPersonalResourceDisplay,
	statusbars = ApplyStatusBars,
	cooldowns = ApplyCooldownManager,
	auras = ApplyAuras,
	micromenu = ApplyMicroMenu,
	minimap = ApplyMinimap,
	chat = ApplyChat,
}

-- Sub-options that require their parent component to be rebuilt.
local subOptions = {
	gryphons = "actionbars",
	auraIconBorder = "auras",
	keepDispelColor = { "auras", "cooldowns" },
}

local function Rebuild(component)
	RestoreGroup(component)
	if M.db[component] then
		appliers[component]()
	end
end

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	InstallHooks()
	for _, component in ipairs(COMPONENTS) do
		if db[component] then
			appliers[component]()
		end
	end
	eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
end

function M:OnDisable()
	eventFrame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
	for _, component in ipairs(COMPONENTS) do
		RestoreGroup(component)
	end
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if appliers[key] then
		if value then
			appliers[key]()
		else
			RestoreGroup(key)
		end
	elseif subOptions[key] then
		local parents = subOptions[key]
		if type(parents) == "string" then
			Rebuild(parents)
		else
			for _, parent in ipairs(parents) do
				Rebuild(parent)
			end
		end
	elseif key == "shade" or key == "desaturate" then
		for _, component in ipairs(COMPONENTS) do
			if db[component] then
				ReapplyGroup(component)
			end
		end
	end
end

MelloUI:Profile("DarkMode", "nameplate events", eventFrame)
MelloUI:Profile("DarkMode", "nameplate relayout", StyleNamePlateUnitFrame)
MelloUI:Profile("DarkMode", "shading", ShadeAll)
