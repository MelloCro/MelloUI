--------------------------------------------------------------------------------
-- MelloUI - Dark Mode
--
-- Darkens the default Blizzard art of unit frames, cast bars, action bars,
-- nameplates, the personal resource display, the cooldown manager, buff and
-- debuff icons, the micro menu and the bag bar by desaturating and tinting the
-- frame textures. No frame layout is touched, so Edit Mode keeps working and
-- nothing taints secure frames.
--
-- With the painted reskin on (user, 2026-09-21): the groups the kit covers are
-- left to the kit, and the kit itself is darkened as one through
-- Kit:SetShade with the "Reskin Brightness" setting (its hue kept: the gems
-- stay red); where the reskin is off, the default art is darkened as before.
--
-- Frame keys were taken from the World of Warcraft: Forever (Camelot) UI source,
-- which uses the retail (Dragonflight style) HUD with Camelot specific overrides.
--
-- (onelook D9) Dark Mode is core: it darkens the game's own art. The painted
-- reskin under it (Kit:SetShade) is a part of this module (M:AddPart, UI
-- Modifications' one contract MelloUI.ModuleParts), in
-- MelloUI_Oldschool/Modules/DarkModePainted.lua (one look stage I); its hooks Enabled,
-- Disabled and Setting are asked where ShadeKit ran. (1.2.4, the user: "1
-- slider that dims all UI elements") one Brightness (`shade`) for all of it:
-- the game's art, the painted reskin (Reskin Brightness, kitShade, is gone)
-- and MelloUI's own UI -- the palette's fills and edges (Look.SetDim), its
-- text kept -- and never an icon (the micro menu's and bag bar's pictures).
-- (lk-11) MelloUI's own frames and windows by the same areas as the game's
-- art: each part follows the switch of the frame it hangs on (the section
-- "MelloUI's own frames and windows"), Windows for the rest.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("DarkMode")
local hooksecurefunc = Perf.hooksecurefunc

-- (fr-17) the player frame on the screen -- MelloUI's own while it stands in (MelloUI.Units, Modules/UnitFramesOwn.lua),
-- else the game's -- and the game's update hooks through it (a world without that file: the game's frame, a plain hook)
local function ScreenPlayer()
	local U = MelloUI.Units
	return U and U.Player() or _G.PlayerFrame
end
-- (fr-17 stage 2) the target frame on the screen -- MelloUI's own while it stands in (Modules/UnitFramesTarget.lua)
local function ScreenTarget()
	local U = MelloUI.Units
	return U and U.Target() or rawget(_G, "TargetFrame")
end
-- (fr-17 stage 3) the focus frame on the screen -- MelloUI's own while it stands in (Modules/UnitFramesTarget.lua)
local function ScreenFocus()
	local U = MelloUI.Units
	return U and U.Focus() or rawget(_G, "FocusFrame")
end
-- (fr-17 stage 4) the pet frame's parts on the screen by the game's global names -- MelloUI's own while it stands in
-- (Modules/UnitFramesPet.lua), else the game's
local PET_GLOBALS = { texture = "PetFrameTexture", portrait = "PetPortrait", name = "PetName", health = "PetFrameHealthBar",
	mana = "PetFrameManaBar", healthMask = "PetFrameHealthBarMask", flash = "PetFrameFlash", attack = "PetAttackModeTexture" }
local function PetPart(key)
	local U = MelloUI.Units
	if U and U.PetPart then
		return U.PetPart(key)
	end
	return rawget(_G, PET_GLOBALS[key])
end
local function UnitsHook(fname, fn)
	local U = MelloUI.Units
	if U then
		U.Hook(fname, fn)
	elseif type(rawget(_G, fname)) == "function" then
		hooksecurefunc(fname, fn)
	end
end
local Secret = MelloUI.Safe.IsSecret
-- ONELOOK HEADER END (the painted reskin's part, MelloUI_Oldschool/Modules/DarkModePainted.lua, uses only public tables)

local M = MelloUI:RegisterModule("DarkMode", {
	title = "Dark Mode",
	desc = "Dims the whole interface: MelloUI's windows and frames, the game's own art and the painted reskin. Icons and text keep their colours.",
	icon = "Interface\\Icons\\Spell_Shadow_Twilight",
	flavour = "Dim the gold and the glare. The interface steps back, the world steps forward.",
	group = "The look", navOrder = 2,
	-- (off until switched on: a personal preference, never on by default)
	tweak = { label = "Dark Mode", desc = "Dims the whole interface. Icons and text keep their colours.", order = 12, off = true },
	-- Dark Mode's switch is the player's own preference (user, 2026-09-26:
	-- "Dark mode ... should be a personal preference"): no profile, share
	-- string or setup carries it, and loading one leaves it as it is (it is
	-- in UI Modifications' keep list). (1.0, the user, 2026-10-20: the Full
	-- experience carries the rest -- "Dark Mode strengths" -- so its
	-- settings travel in profiles; it stays off until a player turns it on)
	keep = {},
	defaults = {
		-- (1.2.4) THE brightness under Dark Mode: the game's art, the painted reskin (Kit:SetShade) and MelloUI's own
		-- UI (the palette's fills and edges: Look.SetDim) -- one slider (it was the game's art's alone, 0.25)
		shade = 0.5,
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
		keepDispelColor = true, -- leave the coloured dispel-type debuff borders alone
		micromenu = true,    -- micro menu and bag bar
		minimap = true,      -- minimap ring, header and buttons
		chat = true,         -- chat tabs, edit box and buttons
		windows = true,      -- (1.2.4, lk-11) MelloUI's windows and panels: every own part in no other area
	},
	options = {
		{ type = "header", name = "Appearance" },
		{ type = "slider", key = "shade", name = "Brightness", min = 0.2, max = 1, step = 0.05, percent = true,
		  desc = "How bright the interface is with Dark Mode on. Lower is darker." },
		{ type = "toggle", key = "desaturate", name = "Desaturate",
		  desc = "Turns the gold and bronze art grey before dimming it." },
		-- (Reskin Brightness: the painted reskin's part puts it here, after Desaturate)
		{ type = "header", name = "Components" },
		{ type = "toggle", key = "unitframes", name = "Unit Frames",
		  desc = "Dark Mode on the unit frames: player, target, focus, pet, boss, target of target, and the party and raid frames." },
		{ type = "toggle", key = "castbar", name = "Cast Bars",
		  desc = "Dark Mode on the cast bars." },
		{ type = "toggle", key = "actionbars", name = "Action Bars",
		  desc = "Dark Mode on the action buttons and the stance, pet, possess and extra action bars." },
		{ type = "toggle", key = "gryphons", parent = "actionbars", name = "Action Bar End Caps",
		  desc = "Dark Mode on the main bar's end caps and art." },
		{ type = "toggle", key = "nameplates", name = "Nameplates",
		  desc = "Dark Mode on the nameplates' bars and cast bars." },
		{ type = "toggle", key = "personal", name = "Personal Display",
		  desc = "Dark Mode on the Personal Display's bars." },
		{ type = "toggle", key = "statusbars", name = "Experience & Reputation Bars",
		  desc = "Dark Mode on the experience, reputation and honor bars." },
		{ type = "toggle", key = "cooldowns", name = "Cooldown Manager",
		  desc = "Dark Mode on the Cooldown Manager's icons and bars." },
		{ type = "toggle", key = "micromenu", name = "Micro Menu & Bag Bar",
		  desc = "Dark Mode on the micro menu's and bag bar's frames. Their icons stay as they are." },
		{ type = "toggle", key = "minimap", name = "Minimap",
		  desc = "Dark Mode on the minimap's ring, header and buttons." },
		{ type = "toggle", key = "chat", name = "Chat Frame",
		  desc = "Chat tabs, the chat input box and the chat buttons. Window background colours stay as configured in the chat settings." },
		{ type = "toggle", key = "windows", name = "Windows", new = "2.0.0",
		  desc = "Dark Mode on MelloUI's windows and panels: the bags, the map, the Quest Tracker, the configurator and the rest." },
		{ type = "header", name = "Buffs & Debuffs" },
		{ type = "toggle", key = "auras", name = "Buffs & Debuffs",
		  desc = "Dark Mode on the game's buff and debuff icons." },
		-- (no parent: it serves the Cooldown Manager's icons as well as the
		-- buffs and debuffs, and must not dim while only that one is on)
		{ type = "toggle", key = "keepDispelColor", name = "Keep Dispel Colours",
		  desc = "Dark Mode leaves the coloured debuff borders (magic, curse, poison, disease) alone." },
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

-- A kit module dressing the same group covers it (user rule, 2026-09-21:
-- Dark Mode only applies while the modified appearance is off).
local function Covered(group)
	local Kit = MelloUI.Kit
	return Kit and Kit:IsCovered(group)
end

local function Active(component)
	return M.isEnabled and M.db and M.db[component] and not Covered(component)
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
	-- (client 70425: the minimap header's buttons -- the zone button, the tracking button, the calendar -- draw one
	-- state texture each, re-atlased as the mouse moves: its tint stays)
	local state = rawget(button, "StateTexture")
	if state then
		list[#list + 1] = state
	end
end

--------------------------------------------------------------------------------
-- Unit frames
--------------------------------------------------------------------------------

local function CollectPlayerFrame(list)
	-- (fr-17: the player frame on the screen -- MelloUI's own while it stands in, else the game's)
	local pf = ScreenPlayer()
	local container = pf and pf.PlayerFrameContainer
	local content = pf and pf.PlayerFrameContent
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

local function CollectMember(member, list)
	list[#list + 1] = member.Texture
	list[#list + 1] = member.VehicleTexture
	if member.PetFrame then
		list[#list + 1] = member.PetFrame.Texture
	end
end

local function CollectPartyFrames(list)
	if not PartyFrame then
		return
	end
	for i = 1, 4 do
		local member = PartyFrame["MemberFrame" .. i]
		if member then
			CollectMember(member, list)
		end
	end
end

-- A party member shaded again after its art is laid: the game's own (its ToPlayerArt / ToVehicleArt) and Unit
-- Frames' sharp art (the bus's "partyart") set its frame's atlas anew, which lets the shade go (the user,
-- 2026-10-16: the party frames "still dont follow the same dark mode"; the player frame's art swaps are hooked the
-- same way below).
local membersHooked = setmetatable({}, { __mode = "k" })

local function ShadeMember(member)
	if type(member) == "table" and Active("unitframes") and not Covered("partyframes") then
		local list = {}
		CollectMember(member, list)
		ShadeAll("unitframes", list)
	end
end

local function HookMembers()
	if not PartyFrame then
		return
	end
	for i = 1, 4 do
		local member = PartyFrame["MemberFrame" .. i]
		if member and not membersHooked[member] then
			membersHooked[member] = true
			for _, method in ipairs({ "ToPlayerArt", "ToVehicleArt" }) do
				if type(member[method]) == "function" then
					hooksecurefunc(member, method, ShadeMember)
				end
			end
		end
	end
end

local function TargetLikeFrames()
	local frames = { ScreenTarget(), ScreenFocus() }   -- (fr-17: the target and focus frames on the screen)
	for i = 1, 5 do
		frames[#frames + 1] = _G["Boss" .. i .. "TargetFrame"]
	end
	return frames
end

local function ApplyUnitFrames()
	local list = {}
	if not Covered("unitframes") then
		CollectPlayerFrame(list)
		for _, frame in ipairs(TargetLikeFrames()) do
			CollectTargetLikeFrame(frame, list)
		end
		list[#list + 1] = PetPart("texture")   -- (fr-17: the pet frame on the screen)
	end
	if not Covered("partyframes") then
		HookMembers()
		CollectPartyFrames(list)
	end
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

-- (fr-18b) the game's bar or button by its global name, or MelloUI's own standing in for it (MelloUI.OwnBars)
local function OwnG(name)
	local OB = MelloUI.OwnBars
	if OB then
		return OB.G(name)
	end
	return rawget(_G, name)
end

local function CollectMainBarArt(list)
	local bar = OwnG("MainActionBar") or MainMenuBar
	if not bar then
		return
	end
	list[#list + 1] = bar.BorderArt
	-- (the end caps are the game's own Edit Mode systems inside the game's bar, MelloUI's own bar standing in or not)
	local game = rawget(_G, "MainActionBar") or bar
	if game.EndCaps then
		if game.EndCaps.LeftEndCap then
			list[#list + 1] = game.EndCaps.LeftEndCap.Texture
		end
		if game.EndCaps.RightEndCap then
			list[#list + 1] = game.EndCaps.RightEndCap.Texture
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
			CollectActionButton(OwnG(entry[1] .. i), list)
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
Perf.SetScript(eventFrame, "OnEvent", function(_, event, unit)
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
	local bars = {}
	for _, bar in ipairs({ prd.HealthBarsContainer and prd.HealthBarsContainer.healthBar or false, prd.PowerBar or false, prd.AlternatePowerBar or false }) do
		if bar then
			bars[#bars + 1] = bar   -- no holes: ipairs stopped at a missing health bar
		end
	end
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
	-- (fr-18: MelloUI's own status bars while they stand in, MelloUI.OwnBars -- their manager, the game's shape)
	local OB = MelloUI.OwnBars
	local manager = (OB and OB.Frame("StatusTrackingBarManager")) or StatusTrackingBarManager
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
	list[#list + 1] = GetAuraIconBorder(button)
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
	-- (1.2.4, the user: Dark Mode must "not touch the icons like it currently does on the Micro Bar and Bag Bar") a
	-- micro button's own pictures (its normal, pushed and lit art: the icon) and the bag buttons' are left as they are;
	-- the round backgrounds under the micro buttons and the bars' frames are darkened
	for _, name in ipairs(MICRO_BUTTONS) do
		local button = _G[name]
		if button then
			list[#list + 1] = button.Background
			list[#list + 1] = button.PushedBackground
		end
	end
	-- (fr-18: MelloUI's own bag bar while it stands in)
	local OB = MelloUI.OwnBars
	local bags = (OB and OB.Frame("BagsBar")) or BagsBar
	if bags then
		list[#list + 1] = bags.BorderArt
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
		-- Zone text header (nine-slice; client 70425: the zone button's own art) and tracking button.
		CollectNineSlice(cluster.BorderTop, list)
		if not cluster.BorderTop then
			CollectButtonStateTextures(cluster.ZoneTextButton, list)
		end
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

	-- the medallion rims of MelloUI's services bar
	if MelloUIServicesBar and MelloUIServicesBar.buttons then
		for _, b in ipairs(MelloUIServicesBar.buttons) do
			if b.rim then
				list[#list + 1] = b.rim
			end
		end
	end

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
-- MelloUI's own frames and windows (1.2.4, lk-11)
--------------------------------------------------------------------------------
-- (the user, 2026-10-28: Dark Mode "only covers some of the windows, it ignores almost every custom made window,
-- Unitframes, Party Unitframes, Raid Unitframe Borders etc." -- "and dont forget cast bar, action bars, personal
-- reource hp, power bar and cast bar aswell as the shield bar") One rule for everything MelloUI draws: a part belongs
-- to the area of the frame it hangs on -- one of the game's frames this module darkens (by its name), one of MelloUI's
-- own (by its name, or given by M:Area) -- and anything else to Windows. Its frame art takes that area's switch at the
-- one Brightness through the two shared paths it is drawn by: the palette's fills and edges (MelloUI.Look: Look.Palette
-- by the region, asking M.Lit) and the pictures under the kit's shade (Kit:RegisterTexture: the kit's pieces and every
-- frame picture of MelloUI's own, Kit.Lit). Never a bar's fill, an icon or a text, as on the game's art; the hue kept
-- (Desaturate is the game's art's). The painted reskin's pieces are MelloUI's own art on the game's frames: each row
-- reaches them too (the user, 2026-10-28: "Keep the Dark Mode settings in the Dark Mode Tab", every row live there).

local OWN_AREAS = {
	-- the game's frames (MelloUI's parts on them: the Modern frame pictures, the party's sharp art, the action
	-- buttons' frames ...)
	PlayerFrame = "unitframes", MelloUIPlayerFrame = "unitframes", TargetFrame = "unitframes", FocusFrame = "unitframes", PetFrame = "unitframes",
	TargetFrameToT = "unitframes", FocusFrameToT = "unitframes", PartyFrame = "unitframes",
	MelloUITargetFrame = "unitframes", MelloUITargetFrameToT = "unitframes", MelloUIFocusFrame = "unitframes",
	MelloUIFocusFrameToT = "unitframes", MelloUIPetFrame = "unitframes",
	PlayerCastingBarFrame = "castbar", PetCastingBarFrame = "castbar", TargetFrameSpellBar = "castbar",
	FocusFrameSpellBar = "castbar",
	MainActionBar = "actionbars", MainMenuBar = "actionbars", MultiBarBottomLeft = "actionbars",
	MultiBarBottomRight = "actionbars", MultiBarRight = "actionbars", MultiBarLeft = "actionbars",
	MultiBar5 = "actionbars", MultiBar6 = "actionbars", MultiBar7 = "actionbars", StanceBar = "actionbars",
	PetActionBar = "actionbars", PossessActionBar = "actionbars", ExtraActionBarFrame = "actionbars",
	MicroMenu = "micromenu", MicroMenuContainer = "micromenu", BagsBar = "micromenu", MelloUIBagBar = "micromenu",
	StatusTrackingBarManager = "statusbars", MainStatusTrackingBarContainer = "statusbars",
	SecondaryStatusTrackingBarContainer = "statusbars", BuffFrame = "auras", DebuffFrame = "auras",
	MelloUIStatusBar1 = "statusbars", MelloUIStatusBar2 = "statusbars",
	MelloUIActionBar1 = "actionbars", MelloUIActionBar2 = "actionbars", MelloUIActionBar3 = "actionbars",
	MelloUIActionBar4 = "actionbars", MelloUIActionBar5 = "actionbars", MelloUIActionBar6 = "actionbars",
	MelloUIActionBar7 = "actionbars", MelloUIActionBar8 = "actionbars",
	MinimapCluster = "minimap", PersonalResourceDisplayFrame = "personal", GeneralDockManager = "chat",
	-- MelloUI's own (the party and raid frames with the unit frames, as the game's party frames are)
	MelloUIGroupParty = "unitframes", MelloUIGroupRaid = "unitframes", MelloUIGroupSoloParty = "unitframes",
	MelloUIGroupFramesFake = "unitframes", MelloUIGroupFramesFakeParty = "unitframes",
	MelloUIPersonalDisplay = "personal", MelloUIPersonalShield = "personal",
	MelloUIChatView = "chat", MelloUIWhispers = "chat",
}
for i = 1, 5 do
	OWN_AREAS["Boss" .. i .. "TargetFrame"] = "unitframes"
end
for _, name in ipairs(COOLDOWN_VIEWERS) do
	OWN_AREAS[name] = "cooldowns"
end
local OWN_PATTERNS = { { "^ChatFrame%d", "chat" }, { "^MelloUIWhisperPopup", "chat" }, { "^NamePlate%d", "nameplates" } }

local ownRoots = setmetatable({}, { __mode = "k" })   -- [frame] = its area (M:Area)
-- [frame] = the area it names itself (by its name, M:Area), or false: read once a frame (its name never changes);
-- the frames above it are walked each time, so a part made later or moved to another parent is in its area now
local ownTag = setmetatable({}, { __mode = "k" })
local byGlobal, globalsRead = setmetatable({}, { __mode = "k" }), false   -- [the frame a name above is] = its area

-- the frames named above, as the globals they are now (read again with the areas: a frame made since)
local function Globals()
	globalsRead = true
	for name, area in pairs(OWN_AREAS) do
		local f = rawget(_G, name)
		if type(f) == "table" then
			byGlobal[f] = area
		end
	end
end

local function NameArea(f)
	local ok, name = pcall(f.GetName, f)
	if not ok or type(name) ~= "string" or Secret(name) then
		return nil
	end
	local area = OWN_AREAS[name]
	if area then
		return area
	end
	for i = 1, #OWN_PATTERNS do
		if name:find(OWN_PATTERNS[i][1]) then
			return OWN_PATTERNS[i][2]
		end
	end
	return nil
end

local function Tag(f)
	local tag = ownTag[f]
	if tag == nil then
		tag = ownRoots[f] or byGlobal[f] or NameArea(f) or false
		ownTag[f] = tag
	end
	return tag
end

-- the area a region of MelloUI's own belongs to: the first frame up from it with one (itself first), else Windows
local function AreaOf(region)
	if not globalsRead then
		Globals()
	end
	local f = region
	for _ = 1, 40 do
		local tag = Tag(f)
		if tag then
			return tag
		end
		local ok, parent = pcall(f.GetParent, f)
		if not ok or type(parent) ~= "table" then
			break
		end
		f = parent
	end
	return "windows"
end

-- a part of MelloUI's own kept at full brightness under Dark Mode: its area switched off -- the painted reskin's
-- pieces too (they stand where the game's art stood, on its frames); no region: the windows'
local function OwnLit(region)
	local db = M.db
	if not db then
		return false
	end
	return db[type(region) == "table" and AreaOf(region) or "windows"] == false
end

-- (asked by the palette, Core/GameLook.lua's Look.Palette, and the kit's shade, Modules/Kit.lua: whether a region
-- keeps its colours)
M.Lit = OwnLit
if type(MelloUI.Kit) == "table" then
	MelloUI.Kit.Lit = OwnLit
end

-- a region's brightness under Dark Mode now: the one Brightness, 1 while Dark Mode or its area is off (the Default
-- skin's lines, Core/Skin.lua's Skin.LayHair)
function M.LevelOf(region)
	local db = M.db
	if not (M.isEnabled and db) or OwnLit(region) then
		return 1
	end
	return tonumber(db.shade) or 1
end

-- every own part laid again at its area's brightness (an area's switch moved, a frame given its area); their areas
-- found again too (a frame moved to another parent since)
local function OwnRelit()
	ownTag = setmetatable({}, { __mode = "k" })
	globalsRead = false
	local Look, Kit = MelloUI.Look, MelloUI.Kit
	if type(Look) == "table" and Look.SetDim then
		Look.SetDim(M.isEnabled and M.db and tonumber(M.db.shade) or 1, true)
	end
	if type(Kit) == "table" and Kit.Reshade then
		Kit:Reshade()
	end
end

-- (lk-11) a frame of MelloUI's own given its Dark Mode area (one of COMPONENTS, or "windows"): every part on it follows
-- that area's switch. Its module calls it once, as it makes the frame
function M:Area(frame, area)
	if type(frame) ~= "table" or type(area) ~= "string" or ownRoots[frame] == area then
		return
	end
	ownRoots[frame] = area
	if self.isEnabled then
		OwnRelit()
	else
		ownTag, globalsRead = setmetatable({}, { __mode = "k" }), false
	end
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
	-- (fr-17: through MelloUI.Units -- the game's frame kept away skipped, ours as it lays its art)
	local function PlayerArt()
		if Active("unitframes") then
			local list = {}
			CollectPlayerFrame(list)
			ShadeAll("unitframes", list)
		end
	end
	for _, fname in ipairs({ "PlayerFrame_ToPlayerArt", "PlayerFrame_ToVehicleArt", "PlayerFrame_UpdateArt" }) do
		UnitsHook(fname, PlayerArt)
	end
	-- (fr-17) the player frame of ours come or gone: shaded as it stands now
	MelloUI:On("units", PlayerArt, "Dark Mode: the player frame of ours")

	-- The party's members: the game's pool acquires them as the group forms -- after this module's apply (the user,
	-- 2026-10-16: "the Party Unitframes dont follow the same Dark mode setting"); shaded as they come.
	local pf = PartyFrame
	if pf and type(pf.InitializePartyMemberFrames) == "function" then
		hooksecurefunc(pf, "InitializePartyMemberFrames", function()
			HookMembers()
			if Active("unitframes") and not Covered("partyframes") then
				local list = {}
				CollectPartyFrames(list)
				ShadeAll("unitframes", list)
			end
		end)
	end
	MelloUI:On("partyart", ShadeMember, "Dark Mode: the party's art")

	-- Target style frames swap atlases for elite / rare / boss classifications. (fr-17: each frame on the screen once --
	-- the game's, or MelloUI's own target standing in -- and again as ours comes)
	local classHooked = setmetatable({}, { __mode = "k" })
	local function OnClassification(self)
		if Active("unitframes") then
			local list = {}
			CollectTargetLikeFrame(self, list)
			ShadeAll("unitframes", list)
		end
	end
	local function HookClassification()
		for _, frame in ipairs(TargetLikeFrames()) do
			if frame and type(frame.CheckClassification) == "function" and not classHooked[frame] then
				classHooked[frame] = true
				hooksecurefunc(frame, "CheckClassification", OnClassification)
			end
		end
	end
	HookClassification()
	MelloUI:On("units", function()
		HookClassification()
		if Active("unitframes") then
			ApplyUnitFrames()
		end
	end, "Dark Mode: the target frame of ours")

	-- Bag buttons re-set their atlases when bags change. (fr-18: MelloUI's own bag buttons while they stand in --
	-- hooked as they come, the bag bar and the status bars shaded again)
	local bagsHooked = setmetatable({}, { __mode = "k" })
	local function HookBagButtons()
		local OB = MelloUI.OwnBars
		for _, name in ipairs(BAG_BUTTONS) do
			local button = (OB and OB.Frame(name)) or _G[name]
			if button and not bagsHooked[button] and type(button.UpdateTextures) == "function" then
				bagsHooked[button] = true
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
	HookBagButtons()
	MelloUI:On("ownbars", function(part)
		if part == "bags" then
			HookBagButtons()
			if Active("micromenu") then
				ApplyMicroMenu()
			end
		elseif part == "status" and Active("statusbars") then
			ApplyStatusBars()
		elseif (part == "actions" or part == "special") and Active("actionbars") then
			ApplyActionBars()   -- (fr-18b: MelloUI's own action bars)
		end
	end, "Dark Mode: the bars of ours")
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
	keepDispelColor = { "auras", "cooldowns" },
}

local function Rebuild(component)
	RestoreGroup(component)
	if M.db[component] and not Covered(component) then
		appliers[component]()
	end
end

-- the kit's cover groups that share a Dark Mode component
local COVER_COMPONENT = { partyframes = "unitframes", bagbar = "micromenu" }
local coverWatched = false

local function WatchCovers()
	if coverWatched or not MelloUI.Kit then
		return
	end
	coverWatched = true
	MelloUI.Kit:OnCover(function(group)
		local component = COVER_COMPONENT[group] or group
		if M.isEnabled and appliers[component] then
			Rebuild(component)
		end
	end)
end

function M:OnInit(db)
	self.db = db
end

-- (onelook D9) the parts extending these settings (the painted reskin's
-- Reskin Brightness: the end of this file): UI Modifications' one contract,
-- MelloUI.ModuleParts (Modules/UIModifications.lua, loaded before this
-- file). Enabled where the kit's shade was set, Disabled as the module goes,
-- Setting first (true: the part applied it)
local Parts = MelloUI.ModuleParts
M.AddPart = Parts and Parts.Add
local function RunParts(hook, ...)
	return Parts ~= nil and Parts.Run(M, hook, ...)
end

-- (1.2.4) MelloUI's own UI dimmed by the one Brightness while Dark Mode is on: the palette's fills and edges, and
-- (lk-11) the pictures under the kit's shade -- the painted kit's pieces and MelloUI's own frame art, in every skin
-- (the painted reskin's part drove the kit's shade alone until then)
local function DimOwn(on, db)
	local v = on and db and tonumber(db.shade) or 1
	local Look, Kit = MelloUI.Look, MelloUI.Kit
	if type(Look) == "table" and Look.SetDim then
		Look.SetDim(v)
	end
	if type(Kit) == "table" and Kit.SetShade then
		Kit:SetShade(v)
	end
end

function M:OnEnable(db)
	self.db = db
	DimOwn(true, db)
	InstallHooks()
	WatchCovers()
	RunParts("Enabled", db)
	for _, component in ipairs(COMPONENTS) do
		if db[component] and not Covered(component) then
			appliers[component]()
		end
	end
	eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
end

-- Other modules call this after creating art that belongs to a component
-- (the Services bar's rims), so it is shaded right away.
function M:Reapply(component)
	if Active(component) and appliers[component] then
		appliers[component]()
	end
end

function M:OnDisable(db)
	eventFrame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
	for _, component in ipairs(COMPONENTS) do
		RestoreGroup(component)
	end
	RunParts("Disabled", db)
	DimOwn(false)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	-- (synchronous, inside a Batch too: never through the bus)
	if key ~= "shade" and RunParts("Setting", key, value, db) then
		return
	end
	if key == "shade" then
		RunParts("Setting", key, value, db)   -- (the painted reskin's shade follows the one Brightness too)
	end
	-- (lk-11: Windows is MelloUI's own parts alone, no game art)
	if appliers[key] or key == "windows" then
		if appliers[key] and value and not Covered(key) then
			appliers[key]()
		elseif appliers[key] then
			RestoreGroup(key)
		end
		OwnRelit()   -- (lk-11) MelloUI's own parts in that area, at its brightness now
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
		if key == "shade" then
			DimOwn(true, db)
		end
	end
end

MelloUI:Profile("DarkMode", "nameplate events", eventFrame)
MelloUI:Profile("DarkMode", "nameplate relayout", StyleNamePlateUnitFrame)
MelloUI:Profile("DarkMode", "shading", ShadeAll)

-- (the painted reskin's part: MelloUI_Oldschool/Modules/DarkModePainted.lua, one look stage I)
