--------------------------------------------------------------------------------
-- MelloUI - Dialogs Kit
--
-- The game's popup dialogs (StaticPopup1..4: the world refresh notice, a
-- confirmation, "Release spirit", ...) in the painted kit (user, 2026-09-24:
-- "this window popus up every now and then, can we reskin this aswell"):
-- the single rail with its stone round the dialog, the game's own box faded,
-- its buttons on the kit's red plates. With the Parchment option for dialogs
-- (Dynamic UI Modification, Parchment: Dialogs; "and also add a parchment to
-- it") a parchment sheet with the painted edge lies on the stone and the
-- message is dark ink by the parchment rule, set for the sheet's darker
-- paper (QuestInk's sheet inks, 4.5 : 1). The dialogs' size, place and
-- behaviour stay the game's; nothing of theirs is replaced.
--
-- /dialogdump [n]: what a dialog is made of (its regions and children), to
-- fit the skin to a client whose dialog differs.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("DialogPanel", {
	title = "Dialogs Kit",
	desc = "The game's popup dialogs on the kit's stone and rail with red plate buttons, and a parchment sheet if you choose one.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local MAX_POPUPS = 4
local AREA = "dialog"
local active = false
local reps = {}                                         -- every replacement (the buttons), for enable / disable
local skins = setmetatable({}, { __mode = "k" })        -- [dialog] = { nine, sheet }
local fadedArt = setmetatable({}, { __mode = "k" })     -- [dialog] = { the game's art we faded }

local function Replace(region, opts)
	local rep = Kit and Kit.Replace and Kit:Replace(region, opts)
	if rep then
		reps[#reps + 1] = rep
		if active then
			rep:Enable()
		end
	end
	return rep
end

local function Dialogs()
	local list = {}
	for i = 1, MAX_POPUPS do
		local f = _G["StaticPopup" .. i]
		if f then
			list[#list + 1] = f
		end
	end
	return list
end

-- The game's dialog box: its border and background, whatever this client
-- makes them of -- a nine-slice child (Border, NineSlice or one with a
-- layout), a background child, and the dialog's own textures in its
-- BACKGROUND and BORDER layers (the icon, the text and the buttons are in
-- higher layers or are frames of their own, and stay)
local function GameArt(dialog)
	local list, seen = {}, {}
	local function Add(obj)
		if obj and not seen[obj] and obj ~= skins[dialog] and not (skins[dialog] and obj == skins[dialog].nine) then
			seen[obj] = true
			list[#list + 1] = obj
		end
	end
	for _, key in ipairs({ "Border", "NineSlice", "BG", "Bg", "Background", "DialogBG" }) do
		Add(dialog[key])
	end
	for _, child in ipairs({ dialog:GetChildren() }) do
		local name = child.GetName and child:GetName()
		if child.layoutType or (type(name) == "string" and (name:find("Border$") or name:find("NineSlice$"))) then
			Add(child)
		end
	end
	for _, region in ipairs({ dialog:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			local layer = region:GetDrawLayer()
			if layer == "BACKGROUND" or layer == "BORDER" then
				Add(region)
			end
		end
	end
	return list
end

local function DialogButtons(dialog)
	local list = {}
	local name = dialog:GetName()
	for i = 1, 4 do
		local b = dialog["button" .. i] or (name and _G[name .. "Button" .. i])
		if b then
			list[#list + 1] = b
		end
	end
	for _, key in ipairs({ "extraButton", "ExtraButton" }) do
		if dialog[key] then
			list[#list + 1] = dialog[key]
		end
	end
	return list
end

-- the kit on one dialog, made once: the rail and stone under it (a frame one
-- level below the dialog, so its text and icon stay over it), the parchment
-- sheet on the stone, the buttons on the red plates
local function Dress(dialog)
	if skins[dialog] or not (Kit and Kit.NineSlice) then
		return skins[dialog]
	end
	local ok, nine = pcall(Kit.NineSlice, Kit, dialog, { prefix = "window/single", scale = Kit.scale * (Kit.frameScale or 1.6),
		gems = false, body = true, level = -1 })
	if not (ok and nine) then
		return nil
	end
	local sheet = Kit.ParchmentSheet and Kit:ParchmentSheet(nine, nine, { area = AREA, fine = true, margin = 2,
		alive = function() return active end })
	skins[dialog] = { nine = nine, sheet = sheet }
	for _, button in ipairs(DialogButtons(dialog)) do
		if Kit.SkinRedButton then
			pcall(Kit.SkinRedButton, Kit, button, Replace)
		end
	end
	nine:SetShown(active)
	return skins[dialog]
end

local function FadeArt(dialog)
	fadedArt[dialog] = fadedArt[dialog] or {}
	for _, obj in ipairs(GameArt(dialog)) do
		Kit:Fade(obj)
		fadedArt[dialog][obj] = true
	end
end

local function UnfadeArt(dialog)
	for obj in pairs(fadedArt[dialog] or {}) do
		Kit:Unfade(obj)
	end
	fadedArt[dialog] = nil
end

-- the dialogs' text on the parchment: a QuestInk surface (on while the
-- dialogs are dressed and their parchment is on), its strings on a sheet
local function InkOn()
	return active and Kit.ParchmentOn and Kit:ParchmentOn(AREA) or false
end

local surfaceMade = false
local function Surface()
	local QI = MelloUI.QuestInk
	if not QI then
		return
	end
	if not surfaceMade then
		surfaceMade = true
		QI.Surface(AREA, { on = InkOn, sheet = true, roots = function() return unpack(Dialogs()) end })
	else
		QI.RefreshSurface(AREA)
	end
end

local function Activate()
	if active then
		return
	end
	active = true
	for _, dialog in ipairs(Dialogs()) do
		local skin = Dress(dialog)
		if skin then
			skin.nine:Show()
			FadeArt(dialog)
		end
	end
	for _, rep in ipairs(reps) do
		rep:Enable()
	end
	if Kit.SetParchment then
		Kit:SetParchment(AREA, Kit:ParchmentOn(AREA))
	end
	Surface()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, dialog in ipairs(Dialogs()) do
		local skin = skins[dialog]
		if skin then
			skin.nine:Hide()
			if skin.sheet then
				skin.sheet:Hide()
			end
		end
		UnfadeArt(dialog)
	end
	for _, rep in ipairs(reps) do
		rep:Disable()
	end
	Surface()
end

-- a dialog shown: dressed (a client may make its frames late), its art
-- faded again (the game re-lays its border on every show), its text inked
local hooked = false
local function Hook()
	if hooked then
		return
	end
	hooked = true
	for _, dialog in ipairs(Dialogs()) do
		dialog:HookScript("OnShow", function(self)
			if not active then
				return
			end
			local skin = Dress(self)
			if skin then
				skin.nine:Show()
				FadeArt(self)
			end
			local QI = MelloUI.QuestInk
			if QI and surfaceMade then
				QI.RefreshSurface(AREA)
			end
		end)
	end
end

function M:OnEnable()
	Hook()
	if Kit and Kit.WhenOutOfCombat then
		Kit:WhenOutOfCombat(Activate)
	else
		Activate()
	end
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /dialogdump [n]: dialog n (1 by default) -- its regions and children, what
-- the skin faded and made; opens the copy window
--------------------------------------------------------------------------------
SLASH_MELLODIALOGDUMP1 = "/dialogdump"
SlashCmdList.MELLODIALOGDUMP = function(msg)
	local n = tonumber(msg) or 1
	local dialog = _G["StaticPopup" .. n]
	MelloUI:ClearLog()
	if not dialog then
		MelloUI:Print("/dialogdump: no StaticPopup%d", n)
		return
	end
	MelloUI:Print("StaticPopup%d: shown %s, size %.0f x %.0f, level %d, strata %s; kit %s, parchment %s", n, tostring(dialog:IsShown()),
		dialog:GetWidth(), dialog:GetHeight(), dialog:GetFrameLevel(), tostring(dialog:GetFrameStrata()),
		active and "on" or "off", tostring(Kit.ParchmentOn and Kit:ParchmentOn(AREA)))
	for _, region in ipairs({ dialog:GetRegions() }) do
		local kind = region:GetObjectType()
		local layer = region.GetDrawLayer and region:GetDrawLayer() or "?"
		local art = kind == "Texture" and (Kit:ArtKey(region) or "?") or (kind == "FontString" and ("text: " .. tostring(region:GetText()):sub(1, 40)) or "")
		MelloUI:Print("  region %s %s %s alpha %.2f shown %s", kind, tostring(layer), tostring(art), region:GetAlpha(), tostring(region:IsShown()))
	end
	for _, child in ipairs({ dialog:GetChildren() }) do
		MelloUI:Print("  child %s %s layout %s level %d alpha %.2f shown %s", tostring(child:GetObjectType()),
			tostring(child:GetName() or child:GetDebugName()), tostring(child.layoutType), child:GetFrameLevel(), child:GetAlpha(), tostring(child:IsShown()))
	end
	local faded = 0
	for _ in pairs(fadedArt[dialog] or {}) do
		faded = faded + 1
	end
	MelloUI:Print("  kit: dressed %s, game art faded %d, buttons %d", tostring(skins[dialog] ~= nil), faded, #DialogButtons(dialog))
	MelloUI:ShowLog("dialogdump")
end
