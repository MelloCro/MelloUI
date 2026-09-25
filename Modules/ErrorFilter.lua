--------------------------------------------------------------------------------
-- MelloUI - Error Messages
--
-- Hides the red error messages you choose ("Not enough energy", "Spell is not
-- ready yet", "Out of range", ...) from the middle of the screen, a kind at a
-- time (user, 2026-09-23, from the addon study: filter the game's messages
-- instead of replacing the error frame's scripts).
--
-- How: while any kind is hidden, MelloUI takes the error event from the
-- game's error frame (UnregisterEvent, nothing replaced) and hands every
-- message it does not hide straight to the frame's own handler, so those show
-- as always, sound included. Off: the event goes back to the frame. The
-- messages are told apart by the game's own strings (ERR_OUT_OF_ENERGY and
-- the rest), so the filter follows the client's language; a secret message
-- is always passed on.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("ErrorFilter")

-- The kinds, each the names of the game's strings it covers (a string this
-- client lacks is skipped)
local KINDS = {
	{ key = "resources", strings = { "ERR_OUT_OF_ENERGY", "ERR_OUT_OF_RAGE", "ERR_OUT_OF_MANA", "ERR_OUT_OF_FOCUS",
		"ERR_OUT_OF_RUNIC_POWER", "ERR_OUT_OF_HEALTH", "SPELL_FAILED_NO_COMBO_POINTS", "ERR_NO_COMBO_POINTS" } },
	{ key = "cooldowns", strings = { "ERR_ABILITY_COOLDOWN", "ERR_SPELL_COOLDOWN", "ERR_ITEM_COOLDOWN",
		"SPELL_FAILED_NOT_READY", "ERR_POTION_COOLDOWN" } },
	{ key = "range", strings = { "ERR_OUT_OF_RANGE", "SPELL_FAILED_OUT_OF_RANGE", "ERR_TOO_FAR_TO_INTERACT",
		"ERR_USE_TOO_FAR", "SPELL_FAILED_TOO_CLOSE" } },
	{ key = "targeting", strings = { "ERR_BADATTACKFACING", "SPELL_FAILED_UNIT_NOT_INFRONT", "ERR_GENERIC_NO_TARGET",
		"SPELL_FAILED_BAD_TARGETS", "SPELL_FAILED_BAD_IMPLICIT_TARGETS", "ERR_INVALID_ATTACK_TARGET",
		"SPELL_FAILED_TARGETS_DEAD", "ERR_NO_ATTACK_TARGET", "SPELL_FAILED_LINE_OF_SIGHT", "ERR_BADATTACKPOS" } },
	{ key = "busy", strings = { "SPELL_FAILED_SPELL_IN_PROGRESS", "ERR_SPELL_FAILED_ANOTHER_IN_PROGRESS",
		"SPELL_FAILED_MOVING", "ERR_NOT_WHILE_MOVING", "ERR_ATTACK_STUNNED", "SPELL_FAILED_STUNNED",
		"SPELL_FAILED_NOT_MOUNTED", "ERR_ATTACK_MOUNTED" } },
}

local M = MelloUI:RegisterModule("ErrorFilter", {
	title = "Error Messages",
	desc = "Hide the red error messages you choose, such as \"Not enough energy\" or \"Spell is not ready yet\", from the middle of the screen.",
	icon = "Interface\\Icons\\Spell_Holy_Silence",
	flavour = "Quiet, please. The red shouts in the middle of the screen, a kind at a time.",
	group = "Frames and bars",
	tweak = { label = "Error Messages", desc = "Hides the red error messages you choose (not enough energy, not ready yet, out of range...) from the middle of the screen.", order = 2, off = true },
	enabledByDefault = false,
	defaults = {
		resources = true,
		cooldowns = true,
		range = false,
		targeting = false,
		busy = false,
	},
	options = {
		{ type = "header", name = "Hide" },
		{ type = "toggle", key = "resources", name = "Not Enough Resources",
		  desc = "Not enough energy, rage, mana or focus, and no combo points." },
		{ type = "toggle", key = "cooldowns", name = "Not Ready Yet",
		  desc = "Ability, spell or item is not ready yet." },
		{ type = "toggle", key = "range", name = "Out Of Range",
		  desc = "Out of range, too far away, too close." },
		{ type = "toggle", key = "targeting", name = "Facing And Target",
		  desc = "Facing the wrong way, target needs to be in front of you, no target, invalid target, target not in line of sight." },
		{ type = "toggle", key = "busy", name = "Busy Or Moving",
		  desc = "Another action is in progress, can't do that while moving, while stunned or while mounted." },
	},
})

local hidden = {}         -- [message text] = true, from the kinds switched on
local took = false        -- the error event is ours (taken from the game's frame)
local eventFrame = CreateFrame("Frame")

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

local function Rebuild(db)
	hidden = {}
	local any = false
	for _, kind in ipairs(KINDS) do
		if db and db[kind.key] then
			for _, name in ipairs(kind.strings) do
				local text = _G[name]
				if type(text) == "string" and text ~= "" then
					hidden[text] = true
					any = true
				end
			end
		end
	end
	return any
end

-- The event back to the game's frame, or taken from it
local function Take(on)
	local ef = UIErrorsFrame
	if not ef then
		return
	end
	if on and not took then
		if ef:IsEventRegistered("UI_ERROR_MESSAGE") then
			ef:UnregisterEvent("UI_ERROR_MESSAGE")
			eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
			took = true
		end
	elseif not on and took then
		eventFrame:UnregisterEvent("UI_ERROR_MESSAGE")
		ef:RegisterEvent("UI_ERROR_MESSAGE")
		took = false
	end
end

Perf.SetScript(eventFrame, "OnEvent", function(_, event, messageType, message, ...)
	-- the secret test first: a secret refuses even the nil test (audit, 2026-09-24)
	if not Secret(message) and message ~= nil and hidden[message] then
		return
	end
	-- not hidden: to the game's frame, as if it had the event itself
	local ef = UIErrorsFrame
	local handler = ef and ef:GetScript("OnEvent")
	if handler then
		handler(ef, event, messageType, message, ...)
	end
end)

local function Apply(db)
	Take(M.isEnabled and Rebuild(db) or false)
end

function M:OnEnable(db)
	self.db = db
	Apply(db)
end

function M:OnDisable()
	Take(false)
end

function M:OnSettingChanged(_, _, db)
	self.db = db
	Apply(db)
end

-- for the test harness
M.KINDS = KINDS
