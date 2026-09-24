--------------------------------------------------------------------------------
-- MelloUI - Game Menu Panel
--
-- Dresses the game menu (Escape) in one painted frame
-- (Media/Textures/GameMenuFrame.tga, from docs/gamemenu-frame.webp, and its
-- Kit Colours looks GameMenuFrame_warm / _bronze): the
-- gold "Game Menu" header, nine red plates in an iron and stone frame. The
-- game's own buttons are laid on the plates by their labels (Options, AddOns,
-- Edit Mode, Support, Macros, MelloUI, Log Out, Exit Game, Return to Game),
-- their art hidden and their text kept; a button with any other label is
-- stacked under the last plate with its usual look.
--
-- Every box was measured on the 910 x 1728 art in pixels; S turns them into
-- frame units.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local M = MelloUI:RegisterModule("GameMenuPanel", {
	title = "Game Menu Panel",
	desc = "The Escape menu on a painted stone and iron frame with red plates for its buttons.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local TEXTURE = "Interface\\AddOns\\MelloUI\\Media\\Textures\\GameMenuFrame"
-- the art in each Kit Colours look (user, 2026-09-24: the menu kept its
-- painted colours in Warm iron and Bronze; Tools/kit_palette.py recolours it)
local LOOK_SUFFIX = { warm = "_warm", bronze = "_bronze" }

local function TextureFile()
	local Kit = MelloUI.Kit
	local look = Kit and Kit.BorderValue and Kit:BorderValue("colours")
	return TEXTURE .. (LOOK_SUFFIX[look] or "") .. ".tga"
end
local ART_W, ART_H = 910, 1728
local TEX_RIGHT, TEX_BOTTOM = ART_W / 1024, ART_H / 2048
local FRAME_W = 340
local S = FRAME_W / ART_W
local FRAME_H = math.floor(ART_H * S + 0.5)

local function Box(x0, y0, x1, y1)
	return { x = x0 * S, y = y0 * S, w = (x1 - x0) * S, h = (y1 - y0) * S }
end

local PLATE_ROWS = { { 258, 326 }, { 394, 461 }, { 523, 590 }, { 653, 720 }, { 782, 849 }, { 977, 1043 }, { 1154, 1220 }, { 1281, 1347 }, { 1452, 1525 } }
local PLATES = {}
for i, r in ipairs(PLATE_ROWS) do
	PLATES[i] = Box(149, r[1], 761, r[2])
end

-- Which plate a button belongs on, by the labels the game uses.
local function Labels()
	return {
		{ GAMEMENU_OPTIONS, OPTIONS, "Options" },
		{ ADDONS, GAMEMENU_ADDONS, "AddOns" },
		{ HUD_EDIT_MODE_MENU, GAMEMENU_EDIT_MODE, "Edit Mode" },
		{ GAMEMENU_SUPPORT, GAMEMENU_HELP, HELP_LABEL, "Support" },
		{ MACROS, "Macros" },
		{ "MelloUI" },
		{ LOG_OUT, LOGOUT, "Log Out" },
		{ EXIT_GAME, QUIT, "Exit Game" },
		{ RETURN_TO_GAME, "Return to Game" },
	}
end

local skin = nil
local active = false
local saved = {}
local hooked = false
local pinnedHidden = {}   -- Blizzard parts kept hidden even when the game shows them

local faded = {}          -- objects held at alpha 0 while the skin is up
local dressed = {}        -- buttons in the skin's layout and font

local function Fade(obj)
	if obj and obj.SetAlpha and not obj.melloFaded then
		obj.melloFaded = true
		faded[obj] = true
		obj:SetAlpha(0)
		if not obj.melloFadeHooked then
			obj.melloFadeHooked = true
			hooksecurefunc(obj, "SetAlpha", function(self, a)
				if a ~= 0 and self.melloFaded and active then
					self:SetAlpha(0)
				end
			end)
		end
	end
end

local function Unfade()
	for obj in pairs(faded) do
		obj.melloFaded = nil
		obj:SetAlpha(1)
	end
	wipe(faded)
end

local function SaveSize(frame)
	if not saved[frame] then
		saved[frame] = { w = frame:GetWidth(), h = frame:GetHeight() }
	end
end

local function PlateIndex(text)
	if not text then
		return nil
	end
	for i, names in ipairs(Labels()) do
		for _, name in ipairs(names) do
			if name == text then
				return i
			end
		end
	end
	return nil
end

local function DressButton(button)
	if button.melloDressed then
		return
	end
	button.melloDressed = true
	dressed[button] = true
	-- the game's look, for Deactivate
	if not button.melloSaved then
		local look = { points = {}, w = button:GetWidth(), h = button:GetHeight() }
		for i = 1, button:GetNumPoints() do
			look.points[i] = { button:GetPoint(i) }
		end
		local hl = button:GetHighlightTexture()
		if hl then
			look.hlAtlas = hl.GetAtlas and hl:GetAtlas() or nil
			look.hlFile = hl.GetTexture and hl:GetTexture() or nil
			look.hlPoints = {}
			for i = 1, hl:GetNumPoints() do
				look.hlPoints[i] = { hl:GetPoint(i) }
			end
		end
		local fs0 = button.GetFontString and button:GetFontString()
		if fs0 then
			look.font = fs0:GetFontObject()
			look.shadow = { fs0:GetShadowColor() }
			look.shadowOffset = { fs0:GetShadowOffset() }
		end
		button.melloSaved = look
	end
	for _, key in ipairs({ "Left", "Center", "Right", "Middle" }) do
		Fade(button[key])
	end
	local function Slices(self)
		if not active then
			return
		end
		for _, key in ipairs({ "Left", "Center", "Right", "Middle" }) do
			if self[key] and self[key].SetAlpha then
				self[key]:SetAlpha(0)
			end
		end
	end
	if button.UpdateButton and not button.melloUpdateHooked then
		button.melloUpdateHooked = true
		hooksecurefunc(button, "UpdateButton", Slices)
	end
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= button:GetHighlightTexture() then
			Fade(region)
		end
	end
	button:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
	button:GetHighlightTexture():SetVertexColor(1, 0.85, 0.4, 0.12)
	button:GetHighlightTexture():ClearAllPoints()
	button:GetHighlightTexture():SetPoint("TOPLEFT", 4, -4)
	button:GetHighlightTexture():SetPoint("BOTTOMRIGHT", -4, 4)
	local fs = button.GetFontString and button:GetFontString()
	if fs then
		fs:SetFontObject("GameFontHighlightLarge")
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetShadowOffset(1, -1)
	end
end

local function UndressButton(button)
	local look = button.melloSaved
	button.melloDressed = nil
	dressed[button] = nil
	if not look then
		return
	end
	if look.hlAtlas and button.SetHighlightAtlas then
		button:SetHighlightAtlas(look.hlAtlas)
	elseif look.hlFile then
		button:SetHighlightTexture(look.hlFile)
	end
	local hl = button:GetHighlightTexture()
	if hl then
		hl:SetVertexColor(1, 1, 1, 1)
		hl:ClearAllPoints()
		if look.hlPoints and #look.hlPoints > 0 then
			for _, pt in ipairs(look.hlPoints) do
				hl:SetPoint(unpack(pt))
			end
		else
			hl:SetAllPoints()
		end
	end
	local fs = button.GetFontString and button:GetFontString()
	if fs then
		if look.font then
			fs:SetFontObject(look.font)
		end
		if look.shadow then
			fs:SetShadowColor(unpack(look.shadow))
		end
		if look.shadowOffset then
			fs:SetShadowOffset(unpack(look.shadowOffset))
		end
	end
	button:ClearAllPoints()
	for _, pt in ipairs(look.points) do
		button:SetPoint(unpack(pt))
	end
	if look.w and look.w > 0 and look.h and look.h > 0 then
		button:SetSize(look.w, look.h)
	end
	button.melloSaved = nil
end

local function Buttons()
	local list = {}
	local frame = GameMenuFrame
	if frame.buttonPool and frame.buttonPool.EnumerateActive then
		for button in frame.buttonPool:EnumerateActive() do
			list[#list + 1] = button
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		if child:GetObjectType() == "Button" and child.GetFontString and child:GetFontString() then
			local dup = false
			for _, b in ipairs(list) do
				if b == child then
					dup = true
				end
			end
			if not dup then
				list[#list + 1] = child
			end
		end
	end
	return list
end

local function Arrange()
	if not (active and skin) then
		return
	end
	local frame = GameMenuFrame
	frame:SetSize(FRAME_W, FRAME_H)
	local extra = 0
	for _, button in ipairs(Buttons()) do
		local fs = button:GetFontString()
		local index = PlateIndex(fs and fs:GetText())
		if index and PLATES[index] then
			DressButton(button)
			local box = PLATES[index]
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", frame, "TOPLEFT", box.x, -box.y)
			button:SetSize(box.w, box.h)
		else
			-- a label the art has no plate for: under the last plate, as it is
			local last = PLATES[#PLATES]
			button:ClearAllPoints()
			button:SetPoint("TOP", frame, "TOPLEFT", last.x + last.w / 2, -(last.y + last.h + 8 + extra))
			extra = extra + button:GetHeight() + 4
		end
	end
	if extra > 0 then
		frame:SetHeight(FRAME_H + extra)
	end
end

local function BuildSkin()
	if skin then
		return skin
	end
	local frame = GameMenuFrame
	skin = CreateFrame("Frame", "MelloUIGameMenuSkin", frame)
	skin:SetPoint("TOPLEFT")
	skin:SetPoint("TOPRIGHT")
	skin:SetHeight(FRAME_H)
	skin:SetFrameLevel(frame:GetFrameLevel())
	skin:EnableMouse(false)
	skin.art = skin:CreateTexture(nil, "BACKGROUND")
	skin.art:SetAllPoints()
	skin.art:SetTexture(TextureFile())
	skin.art:SetTexCoord(0, TEX_RIGHT, 0, TEX_BOTTOM)
	local Kit = MelloUI.Kit
	if Kit and Kit.OnBorderChanged then
		Kit:OnBorderChanged("colours", function()
			skin.art:SetTexture(TextureFile())
			skin.art:SetTexCoord(0, TEX_RIGHT, 0, TEX_BOTTOM)
		end)
	end
	return skin
end

local function Activate()
	local frame = GameMenuFrame
	if active or not frame then
		return
	end
	active = true
	BuildSkin()
	SaveSize(frame)
	for _, key in ipairs({ "Border", "Header" }) do
		local part = frame[key]
		if part then
			part:Hide()
			Fade(part)
			if not pinnedHidden[part] then
				pinnedHidden[part] = true
				hooksecurefunc(part, "Show", function(self)
					if active then
						self:Hide()
					end
				end)
			end
		end
	end
	skin.art:SetTexture(TextureFile())
	skin:Show()
	Arrange()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	skin:Hide()
	Unfade()
	for _, key in ipairs({ "Border", "Header" }) do
		local part = GameMenuFrame[key]
		if part then
			part:Show()
		end
	end
	for button in pairs(dressed) do
		UndressButton(button)
	end
	local s = saved[GameMenuFrame]
	if s then
		GameMenuFrame:SetSize(s.w, s.h)
	end
end

local function Hook()
	if hooked or not GameMenuFrame then
		return
	end
	hooked = true
	if GameMenuFrame.InitButtons then
		hooksecurefunc(GameMenuFrame, "InitButtons", function() Arrange() end)
	end
	if GameMenuFrame.Layout then
		hooksecurefunc(GameMenuFrame, "Layout", function() Arrange() end)
	end
	GameMenuFrame:HookScript("OnShow", function()
		if M.isEnabled then
			Activate()
			Arrange()
		end
	end)
end

function M:OnEnable(db)
	self.db = db
	Hook()
	if GameMenuFrame and GameMenuFrame:IsShown() then
		Activate()
	end
end

function M:OnDisable()
	Deactivate()
end
