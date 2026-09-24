--------------------------------------------------------------------------------
-- MelloUI - Tweaks
--
-- Small quality of life switches:
--   * hide the micro menu (character / spellbook / ... buttons)
--   * hide the bag bar (the bag slots then dock under the open bag window,
--     with or without Combine Bags, so bags can still be equipped and removed)
--   * world text scale (floating combat text / damage numbers)
--
-- Hidden frames are re-parented to an invisible frame instead of calling Hide(),
-- so Blizzard code that calls Show() on them cannot bring them back. While Edit
-- Mode is active they are shown again so their layout can still be changed.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Tweaks")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer

local M = MelloUI:RegisterModule("Tweaks", {
	title = "Tweaks",
	desc = "Hide the micro menu and bag bar, and scale the floating combat text.",
	defaults = {
		hideMicroMenu = false,
		hideBagBar = false,
		bagSlotsOnBags = true,
		hideMinimapCoords = true,
		worldTextScale = 1,
		chatNotices = true,
		menuTipShown = false,
	},
	options = {
		{ type = "header", name = "Hide Frames" },
		{ type = "toggle", key = "hideMicroMenu", name = "Hide Micro Menu",
		  desc = "Hide the row of menu buttons (character, spellbook, talents, ...). Still shown while Edit Mode is open." },
		{ type = "toggle", key = "hideBagBar", name = "Hide Bag Bar",
		  desc = "Hide the backpack and bag slot buttons. Still shown while Edit Mode is open. Bags can still be opened with their keybinds." },
		{ type = "toggle", key = "hideMinimapCoords", name = "Hide Minimap Coordinates",
		  desc = "Hide the player coordinates the client writes under the minimap." },
		{ type = "toggle", key = "bagSlotsOnBags", parent = "hideBagBar", name = "Bag Slots on Bag Window",
		  desc = "While the bag bar is hidden, show the bag slots under the open bag window so bags can still be equipped and removed. Works with and without the Combine Bags option." },
		{ type = "header", name = "Chat" },
		{ type = "toggle", key = "chatNotices", name = "Chat Notices",
		  desc = "Lines MelloUI writes to chat on its own: a learned dungeon entrance, settings restored from the backup, hints. Replies to slash commands always show." },
		{ type = "header", name = "Combat Text" },
		{ type = "slider", key = "worldTextScale", name = "World Text Scale", min = 0.5, max = 3, step = 0.1,
		  format = function(v) return string.format("%.1fx", v) end,
		  desc = "Scale of the floating damage and healing numbers in the world (WorldTextScale). Default is 1.0." },
	},
})

--------------------------------------------------------------------------------
-- Frame hiding
--------------------------------------------------------------------------------

local hiddenParent = CreateFrame("Frame", "MelloUIHiddenFrame", UIParent)
hiddenParent:Hide()

local HIDE_TARGETS = {
	hideMicroMenu = function() return MicroMenuContainer end,
	hideBagBar = function() return BagsBar end,
	hideMinimapCoords = function()
		return (Minimap and Minimap.PlayerCoords)
			or (MinimapCluster and MinimapCluster.MinimapContainer and MinimapCluster.MinimapContainer.PlayerCoords)
			or (MinimapCluster and MinimapCluster.PlayerCoords)
	end,
}

local originalParents = setmetatable({}, { __mode = "k" })
local editModeActive = false
local UpdateBagSlots = nil   -- defined in the bag slots section

local function SetFrameHidden(frame, hidden)
	if not frame or not frame.SetParent then
		return
	end
	if hidden then
		if frame:GetParent() ~= hiddenParent then
			originalParents[frame] = frame:GetParent() or UIParent
			frame:SetParent(hiddenParent)
		end
	else
		if frame:GetParent() == hiddenParent then
			frame:SetParent(originalParents[frame] or UIParent)
		end
	end
end

local function UpdateHiddenFrames()
	local db = M.db
	for key, getter in pairs(HIDE_TARGETS) do
		local frame = getter()
		local shouldHide = M.isEnabled and db and db[key] and not editModeActive
		SetFrameHidden(frame, shouldHide)
	end
	if UpdateBagSlots then
		UpdateBagSlots()
	end
end

local callbacksRegistered = false

local function RegisterEditModeCallbacks()
	if callbacksRegistered or not EventRegistry then
		return
	end
	callbacksRegistered = true
	EventRegistry:RegisterCallback("EditMode.Enter", function()
		editModeActive = true
		UpdateHiddenFrames()
	end, M)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		editModeActive = false
		UpdateHiddenFrames()
	end, M)
end

--------------------------------------------------------------------------------
-- Bag slots on the bag window
--
-- With the bag bar hidden the four bag slot buttons (and the reagent bag and
-- key ring when this client has them) are re-parented to a small holder that
-- sits under the first open bag window: the combined bags frame, or the
-- backpack when bags are separate. Both stack upwards from the bottom right of
-- the screen, so the strip below them, where the bag bar was, is always free.
-- Blizzard's BagsBar:Layout() re-anchors the buttons whenever the cursor picks
-- something up; a hook puts them back.
--------------------------------------------------------------------------------

local BAG_SLOT_NAMES = { "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot" }
local SLOT_GAP = 2
local SLOT_SCALE = 0.8

local holder = nil
local slotsAttached = false
local slotParents = setmetatable({}, { __mode = "k" })
local bagHooksDone = false

local function SlotButtons()
	local list = {}
	for _, name in ipairs(BAG_SLOT_NAMES) do
		if _G[name] then
			list[#list + 1] = _G[name]
		end
	end
	local reagentSlots = Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumReagentBagSlots
	if CharacterReagentBag0Slot and reagentSlots and reagentSlots > 0 then
		list[#list + 1] = CharacterReagentBag0Slot
	end
	if KeyRingButton and KeyRingButton:IsShown() then
		list[#list + 1] = KeyRingButton
	end
	return list
end

-- Another module may take the bag slots over while a window of its own shows
-- them (the Backpack panel's painted bag bar): ns.BagSlotOverride returns
-- true when it has placed them itself.
local function LayoutBagSlots()
	if not (slotsAttached and holder) then
		return
	end
	if ns.BagSlotOverride and ns.BagSlotOverride(SlotButtons(), holder) then
		return
	end
	local previous, width = nil, 0
	for _, button in ipairs(SlotButtons()) do
		button:ClearAllPoints()
		if previous then
			button:SetPoint("RIGHT", previous, "LEFT", -SLOT_GAP, 0)
			width = width + SLOT_GAP
		else
			button:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
		end
		width = width + button:GetWidth()
		previous = button
	end
	holder:SetWidth(math.max(width, 1))
end

-- The bag window the slots hang from: the first one shown, which is the one
-- in the bottom right corner.
local function FirstBagFrame()
	if ContainerFrameSettingsManager and ContainerFrameSettingsManager.GetBagsShown then
		local ok, shown = pcall(ContainerFrameSettingsManager.GetBagsShown, ContainerFrameSettingsManager)
		if ok and type(shown) == "table" and shown[1] and shown[1]:IsShown() then
			return shown[1]
		end
	end
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
		return ContainerFrameCombinedBags
	end
	if ContainerFrame1 and ContainerFrame1:IsShown() then
		return ContainerFrame1
	end
	return nil
end

local function PositionBagSlots()
	if not holder then
		return
	end
	if slotsAttached and ns.BagSlotOverride and ns.BagSlotOverride(SlotButtons(), holder) then
		holder:Show()
		return
	end
	local anchor = slotsAttached and FirstBagFrame()
	if not anchor then
		holder:Hide()
		return
	end
	holder:ClearAllPoints()
	holder:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", -4 / SLOT_SCALE, -4 / SLOT_SCALE)
	holder:Show()
end

local function ScheduleBagSlotUpdate()
	if slotsAttached then
		C_Timer.After(0, PositionBagSlots)
	end
end

local function HookBagFrames()
	if bagHooksDone then
		return
	end
	bagHooksDone = true
	if type(UpdateContainerFrameAnchors) == "function" then
		hooksecurefunc("UpdateContainerFrameAnchors", ScheduleBagSlotUpdate)
	end
	local frames = { ContainerFrameCombinedBags }
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		frames[#frames + 1] = _G["ContainerFrame" .. i]
	end
	for _, frame in ipairs(frames) do
		if frame and frame.HookScript then
			Perf.HookScript(frame, "OnShow", ScheduleBagSlotUpdate)
			Perf.HookScript(frame, "OnHide", ScheduleBagSlotUpdate)
		end
	end
	if BagsBar and BagsBar.Layout then
		hooksecurefunc(BagsBar, "Layout", function()
			if slotsAttached then
				LayoutBagSlots()
			end
		end)
	end
	-- Picking something up expands the bag bar, which runs BagsBar:Layout()
	-- through a callback registered with the original function at load time,
	-- so the hook above never sees it. Re-anchor a frame later instead.
	local function Relayout()
		if slotsAttached then
			C_Timer.After(0, LayoutBagSlots)
		end
	end
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("MainMenuBarManager.OnExpandChanged", Relayout, M)
	end
	local cursorFrame = CreateFrame("Frame")
	cursorFrame:RegisterEvent("CURSOR_CHANGED")
	cursorFrame:RegisterEvent("BAG_UPDATE_DELAYED")
	Perf.SetScript(cursorFrame, "OnEvent", Relayout)
end

local function AttachBagSlots()
	if slotsAttached then
		return
	end
	if not holder then
		holder = CreateFrame("Frame", "MelloUIBagSlots", UIParent)
		holder:SetSize(1, 45)
		holder:SetScale(SLOT_SCALE)
		holder:SetFrameStrata("MEDIUM")
		holder:SetFrameLevel(20)
		holder:Hide()
	end
	for _, button in ipairs(SlotButtons()) do
		slotParents[button] = button:GetParent()
		button:SetParent(holder)
	end
	slotsAttached = true
	HookBagFrames()
	LayoutBagSlots()
	PositionBagSlots()
end

local function DetachBagSlots()
	if not slotsAttached then
		return
	end
	slotsAttached = false
	for button, parent in pairs(slotParents) do
		if button:GetParent() == holder then
			button:SetParent(parent)
		end
	end
	if holder then
		holder:Hide()
	end
	if BagsBar and BagsBar.Layout then
		pcall(BagsBar.Layout, BagsBar)   -- Blizzard's own anchors again
	end
end

function UpdateBagSlots()
	local db = M.db
	local want = M.isEnabled and db and db.hideBagBar and db.bagSlotsOnBags and not editModeActive and BagsBar ~= nil
	if want then
		AttachBagSlots()
	else
		DetachBagSlots()
	end
end

--------------------------------------------------------------------------------
-- World text scale
--------------------------------------------------------------------------------

local WORLD_TEXT_CVAR = "WorldTextScale"
local worldTextWarned = false

-- The player's own WorldTextScale is kept in the saved settings
-- (db.savedWorldTextScale, as Chat keeps the class colour cvar), taken ONCE,
-- just before this module first writes the cvar, and never taken again
-- while it is kept: a reload or the next login find MelloUI's own value in
-- the cvar and must not keep that as the player's (the 2026-09-24 review:
-- the original was read once per session, so after a /reload switching the
-- module off gave back MelloUI's value). The slider is written only once
-- the player has moved it -- a value other than the default, or the
-- original already kept -- so a scale set in the game's options is not
-- overwritten with 1.0 at every login. Written back and forgotten when the
-- module goes off. This session's copy of it (`keptWorldTextScale`) is the
-- one written back when both are there: loading a profile clears every
-- setting before the module is restarted (Core's ApplySettingsText), which
-- would lose the saved one and leave MelloUI's value in the cvar for good.
local keptWorldTextScale = nil

local function ReadWorldTextScale()
	if not (C_CVar and C_CVar.GetCVar) then
		return nil
	end
	local ok, current = pcall(C_CVar.GetCVar, WORLD_TEXT_CVAR)
	if not ok or type(current) ~= "string" or (issecretvalue and issecretvalue(current)) then
		return nil
	end
	return current
end

-- The client accepts a cvar it knows and ignores the rest without a word
-- (user, 2026-09-22: the slider did nothing, Config.wtf never got the
-- entry): a name this build does not have is reported once.
local function ApplyWorldTextScale(value)
	if not C_CVar or not C_CVar.SetCVar then
		return
	end
	local current = ReadWorldTextScale()
	if current == nil then
		-- said once, and only to someone who moved the slider
		if not worldTextWarned and math.abs((tonumber(value) or 1) - 1) > 0.001 then
			worldTextWarned = true
			MelloUI:Print("Tweaks: this client has no '%s' cvar; the World Text Scale slider cannot work on it.", WORLD_TEXT_CVAR)
		end
		return
	end
	value = tonumber(value) or 1
	local db = M.db
	if db and db.savedWorldTextScale == nil then
		db.savedWorldTextScale = keptWorldTextScale or current   -- the player's own, before the first write
	end
	keptWorldTextScale = db and db.savedWorldTextScale or keptWorldTextScale
	if math.abs((tonumber(current) or -1) - value) < 0.001 then
		return   -- already so
	end
	local okS, done = pcall(C_CVar.SetCVar, WORLD_TEXT_CVAR, string.format("%.2f", value))
	if not (okS and done) and not worldTextWarned then
		worldTextWarned = true
		MelloUI:Print("Tweaks: the client refused '%s'; the World Text Scale slider cannot work on it.", WORLD_TEXT_CVAR)
	end
end

-- At login: the slider's value only once the player has moved it
local function WorldTextScaleWanted(db)
	if db.savedWorldTextScale ~= nil then
		return true
	end
	return math.abs((tonumber(db.worldTextScale) or 1) - 1) > 0.001
end

-- The player's own value back (the module off)
local function RestoreWorldTextScale()
	local db = M.db
	local saved = keptWorldTextScale or (db and db.savedWorldTextScale)
	keptWorldTextScale = nil
	if db then
		db.savedWorldTextScale = nil
	end
	if saved ~= nil and C_CVar and C_CVar.SetCVar then
		pcall(C_CVar.SetCVar, WORLD_TEXT_CVAR, saved)
	end
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	RegisterEditModeCallbacks()
	if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive then
		editModeActive = EditModeManagerFrame:IsEditModeActive()
	end
	UpdateHiddenFrames()
	if WorldTextScaleWanted(db) then
		ApplyWorldTextScale(db.worldTextScale)
	end
end

function M:OnDisable()
	UpdateHiddenFrames()
	RestoreWorldTextScale()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if HIDE_TARGETS[key] or key == "bagSlotsOnBags" then
		UpdateHiddenFrames()
	elseif key == "worldTextScale" then
		ApplyWorldTextScale(value)
	end
end
