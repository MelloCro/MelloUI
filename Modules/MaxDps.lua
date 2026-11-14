-- MaxDPS discovers Blizzard's action buttons; mirror its spell mapping onto our replacements.
-- Only MaxDPS's own registration is hooked: no protected button or Blizzard table is changed.
local _, ns = ...
local MelloUI = ns.MelloUI
local OB = MelloUI.OwnBars
local Perf = MelloUI.Perf:Scope("MaxDPS compatibility")
local Finite, Text = MelloUI.Safe.Finite, MelloUI.Safe.Text
local hooked

local function Add(self, spell, button)
	local list = self.Spells and self.Spells[spell]
	if not (button and list) then
		return
	end
	for _, existing in ipairs(list) do
		if existing == button then
			return
		end
	end
	self:AddButton(spell, button)
end

local function Mirror(self, spell, button)
	if not (OB and OB.On("actions") and MelloUI.Integrations.Use("MaxDps")) then
		return
	end
	spell = Finite(spell)
	if not (spell and button and button.GetName) or OB.mine[button] then
		return
	end
	local name = Text(button:GetName())
	Add(self, spell, name and OB.own[name])
	-- Controller bars show non-clickable copies of action slots, rather than the normal replacement buttons.
	local slot = Finite(button.action)
	local actions = OB.Actions
	if slot and OB.Pad and OB.Pad.on and actions then
		for _, display in ipairs(actions.shows or {}) do
			if Finite(display.action) == slot then
				Add(self, spell, display)
			end
		end
	end
end

local function Refresh()
	local maxDps = rawget(_G, "MaxDps")
	if not (type(maxDps) == "table" and type(maxDps.AddButton) == "function" and type(maxDps.ButtonFetch) == "function") then
		return
	end
	if not hooked then
		hooked = true
		Perf.hooksecurefunc(maxDps, "AddButton", Mirror)
	end
	maxDps:ButtonFetch()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
Perf.SetScript(events, "OnEvent", function(_, event, addon)
	if event == "PLAYER_LOGIN" then
		events:UnregisterEvent("PLAYER_LOGIN")
		Refresh()
	elseif addon == "MaxDps" then
		Refresh()
	end
end)
MelloUI:On("ownbars", function(part)
	if part == "actions" then
		Refresh()
	end
end, "MaxDPS compatibility")
MelloUI:On("ownbars:padslots", Refresh, "MaxDPS compatibility: controller slots")
