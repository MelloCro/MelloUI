--------------------------------------------------------------------------------
-- MelloUI - Raid Frame Panel
--
-- The compact unit frames (the raid frames, the raid-style party frames,
-- the compact pet / mini frames) and the raid groups' borders dressed in the
-- painted kit (Modules/Kit.lua) on the game's own layout, and the totem
-- bar's round borders. User's picks (kit_raw/raidframe_catalog.png,
-- 2026-09-21): F1 G1.
--   F1  a compact frame's dark backing (`background`) becomes the single
--       rail at a small scale with the stone under the fills — as REGIONS of
--       the frame (the stone above the faded backing, the rails above the
--       BORDER fills and under the ARTWORK icons and name); the white target
--       edge and the red aggro glow stay the game's
--   G1  a group's border (`borderFrame`, Edit Mode's 'display border') on
--       the single rail 1.6, following the game's show / hide
--   O2  a totem's round border → the round rim on its rect
-- Frames are set up by the game's DefaultCompactUnitFrameSetup /
-- DefaultCompactMiniFrameSetup on every roster and profile change: skinned
-- from those post-hooks, once per frame. Rules: docs/WINDOW-RULES.md 2d.
-- Covers the Dark Mode group "raidframes". /rfdump [frame name] [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("RaidFramePanel", {
	title = "Raid Frames Kit",
	desc = "The compact raid and party frames and the totem bar dressed in the painted kit on the game's own layout.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil
local active = false
local hooked = false

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Raid frames: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- A compact unit frame (raid member, raid-style party member, pet / mini):
-- F1 on its backing.
local function SkinCompact(frame)
	if not (frame and frame.background) or frame.melloRep ~= nil then
		return
	end
	frame.melloRep = Replace(frame.background, { as = "raidframe-hp-bg-white" }) or false
end

-- A raid group's border (G1), following the game's show / hide as its child.
local function SkinGroup(group)
	local border = group and group.borderFrame
	if not (border and border.Background) or border.melloRep ~= nil then
		return
	end
	border.melloRep = Replace(border.Background, { as = "options_frame_child", parent = border, rect = border, level = 0 }) or false
end

-- The totem bar's pooled buttons: the round rim on each Border.
local function SkinTotems()
	local tf = TotemFrame
	if not (tf and tf.totemPool) then
		return
	end
	for button in tf.totemPool:EnumerateActive() do
		if button.Border and button.melloRep == nil then
			button.melloRep = Replace(button.Border, { as = "UI-HUD-UnitFrame-TotemFrame" }) or false
		end
	end
end

local function Hook()
	if hooked then
		return
	end
	hooked = true
	for _, fname in ipairs({ "DefaultCompactUnitFrameSetup", "DefaultCompactMiniFrameSetup" }) do
		if type(_G[fname]) == "function" then
			hooksecurefunc(fname, function(frame)
				if active then
					Kit:WhenOutOfCombat(function() SkinCompact(frame) end)
				end
			end)
		end
	end
	if type(CompactRaidGroup_UpdateBorder) == "function" then
		hooksecurefunc("CompactRaidGroup_UpdateBorder", function(group)
			if active then
				Kit:WhenOutOfCombat(function() SkinGroup(group) end)
			end
		end)
	end
	if TotemFrame and TotemFrame.Update then
		hooksecurefunc(TotemFrame, "Update", function()
			if active then
				Kit:WhenOutOfCombat(SkinTotems)
			end
		end)
	end
end

-- The frames already set up when the module comes on (a /reload in a group).
local function SkinExisting()
	for i = 1, 8 do
		local group = _G["CompactRaidGroup" .. i]
		if group then
			SkinGroup(group)
			for j = 1, 5 do
				SkinCompact(_G["CompactRaidGroup" .. i .. "Member" .. j])
			end
		end
	end
	for i = 1, 40 do
		SkinCompact(_G["CompactRaidFrame" .. i])
	end
	for i = 1, 5 do
		SkinCompact(_G["CompactPartyFrameMember" .. i])
		SkinCompact(_G["CompactPartyFramePet" .. i])
	end
	SkinTotems()
end

local function Activate()
	if active then
		return
	end
	active = true
	if not skin then
		skin = { reps = {} }
	end
	SkinExisting()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	Kit:Cover("raidframes")
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	Kit:Uncover("raidframes")
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function M:OnEnable(db)
	self.db = db
	Hook()
	Kit:WhenOutOfCombat(Activate)
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /rfdump [frame name] [frames|reps]: a compact frame's art (default: the
-- first raid-style party member, else the first raid frame). Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLORFDUMP1 = "/rfdump"
SlashCmdList.MELLORFDUMP = function(msg)
	msg = (msg or ""):gsub("^%s+", "")
	local name, mode = msg:match("^(%S*)%s*(%a*)$")
	if name == "frames" or name == "reps" then
		name, mode = "", name
	end
	local frame = name ~= "" and _G[name] or CompactPartyFrameMember1 or CompactRaidGroup1Member1 or CompactRaidFrame1
	MelloUI:ClearLog()
	if not frame then
		MelloUI:Print("No compact frame: give a frame name (CompactPartyFrameMember1, CompactRaidGroup1Member1, CompactRaidFrame1, TotemFrame).")
	else
		local ok, w, h = pcall(frame.GetSize, frame)
		MelloUI:Print("== %s %s x %s  %s L%d %s", frame:GetName() or "?", ok and w or "?", ok and h or "?", frame:GetFrameStrata(), frame:GetFrameLevel(), frame:IsShown() and "shown" or "hidden")
		Kit:DumpWindow(frame, skin, mode ~= "" and mode or nil)
	end
	MelloUI:ShowLog("rfdump " .. msg)
end
