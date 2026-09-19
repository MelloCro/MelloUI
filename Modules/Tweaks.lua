--------------------------------------------------------------------------------
-- MelloUI - Tweaks
--
-- Small quality of life switches:
--   * hide the micro menu (character / spellbook / ... buttons)
--   * hide the bag bar
--   * world text scale (floating combat text / damage numbers)
--
-- Hidden frames are re-parented to an invisible frame instead of calling Hide(),
-- so Blizzard code that calls Show() on them cannot bring them back. While Edit
-- Mode is active they are shown again so their layout can still be changed.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI

local M = MelloUI:RegisterModule("Tweaks", {
	title = "Tweaks",
	desc = "Hide the micro menu and bag bar, and scale the floating combat text.",
	defaults = {
		hideMicroMenu = false,
		hideBagBar = false,
		worldTextScale = 1,
	},
	options = {
		{ type = "header", name = "Hide Frames" },
		{ type = "toggle", key = "hideMicroMenu", name = "Hide Micro Menu",
		  desc = "Hide the row of menu buttons (character, spellbook, talents, ...). Still shown while Edit Mode is open." },
		{ type = "toggle", key = "hideBagBar", name = "Hide Bag Bar",
		  desc = "Hide the backpack and bag slot buttons. Still shown while Edit Mode is open. Bags can still be opened with their keybinds." },
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
}

local originalParents = setmetatable({}, { __mode = "k" })
local editModeActive = false

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
-- World text scale
--------------------------------------------------------------------------------

local WORLD_TEXT_CVAR = "WorldTextScale"

local function ApplyWorldTextScale(value)
	if not C_CVar or not C_CVar.SetCVar then
		return
	end
	value = tonumber(value) or 1
	C_CVar.SetCVar(WORLD_TEXT_CVAR, string.format("%.2f", value))
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
	ApplyWorldTextScale(db.worldTextScale)
end

function M:OnDisable()
	UpdateHiddenFrames()
	ApplyWorldTextScale(1)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if HIDE_TARGETS[key] then
		UpdateHiddenFrames()
	elseif key == "worldTextScale" then
		ApplyWorldTextScale(value)
	end
end
