--------------------------------------------------------------------------------
-- MelloUI - Threat (0.16.0)
--
-- One threat reader for the nameplates' threat line (Modules/Nameplates.lua)
-- and the Threat widget (Modules/Widgets.lua): the user's pick of
-- 2026-09-30, "threat without a meter" (MelloUI-BuildData/output/
-- threat_sketch, look D without the number, and the widget; pulled into
-- 0.16.0 after the RC2 home test).
--
--   Threat.Read(unit, mob) -> status, fraction, tanking, value
--       status    0 / 1 / 2 / 3 as the game's (0 lower threat, 1 higher than
--                 the one tanking, 2 tanking insecurely, 3 tanking); false
--                 when `unit` is not on the mob's list; nil when the game
--                 keeps it secret
--       fraction  the share of the pull (the game's scaledPercentage / 100:
--                 1 pulls), nil when the numbers are secret
--       tanking   true when the mob is on `unit`
--       value     the game's scaledPercentage (0-100) as it came, plain or
--                 SECRET: only ever handed to a StatusBar's SetValue (which
--                 takes a secret, SecretArguments AllowedWhenTainted, and
--                 draws it), never read here; nil when there is none
--     Every answer tested through MelloUI.Safe before it is used: nothing
--     secret is compared, not even with nil (hard rule 3). (User,
--     2026-09-30: the nameplates' numbers came secret in the open world, so
--     the line showed only a "!"; the bar now takes the secret itself.)
--   Threat.State(status, fraction, tank) -> "safe" | "close" | "aggro" | nil
--       what it means for the player: a tank is safe while the mob is on
--       them, close while it is loosely on them, aggro when it is not (a
--       loose mob); anyone else safe below CLOSE of the pull, close from
--       there, aggro once it is on them
--   Threat.IsTank()    the group's tank: the TANK role, else a tanking form
--                      (Defensive Stance, Bear or Dire Bear Form)
--   Threat.Grouped()   in a party or a raid (solo, threat says nothing new)
--   Threat.Colour(state) -> r, g, b   gold (the palette's selectedTrim)
--                      while safe; the fixed meaning colours threatClose
--                      and threatAggro (MelloUI.Meaning) otherwise
--   Threat.CLOSE       0.8
-- Makes nothing: no table per call, no frame.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number

local Threat = { CLOSE = 0.8 }
MelloUI.Threat = Threat

-- a call's first result, or nil when it raised or that is secret
local function Ask(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, ...)
	if ok and not Secret(v) then
		return v
	end
	return nil
end

function Threat.Read(unit, mob)
	local value = nil
	local fn = _G.UnitDetailedThreatSituation
	if type(fn) == "function" then
		local ok, tanking, status, scaled = pcall(fn, unit, mob)
		if ok then
			-- (asked for secret first; a secret one kept for a bar only)
			if Secret(scaled) then
				value = scaled
			else
				value = Num(scaled)
			end
			if not (Secret(tanking) or Secret(status) or Secret(scaled)) then
				if status == nil then
					return false, nil, false, nil
				end
				status = Num(status)
				if status then
					return status, value and value / 100 or nil, tanking == true, value
				end
			end
		end
	end
	-- the state alone (open in more cases than the numbers)
	local ok, status = pcall(_G.UnitThreatSituation, unit, mob)
	if not ok or Secret(status) then
		return nil, nil, false, value
	end
	if status == nil then
		return false, nil, false, nil
	end
	status = Num(status)
	return status, nil, status ~= nil and status >= 2, value
end

function Threat.State(status, fraction, tank)
	if type(status) ~= "number" then
		return nil
	end
	if tank then
		if status == 3 then
			return "safe"
		elseif status == 2 then
			return "close"
		end
		return "aggro"
	end
	if status >= 2 then
		return "aggro"
	elseif status == 1 or (fraction and fraction >= Threat.CLOSE) then
		return "close"
	end
	return "safe"
end

-- tanking forms (GetShapeshiftFormID): Defensive Stance, Bear Form, Dire Bear Form
local TANK_FORMS = { [18] = true, [5] = true, [8] = true }

function Threat.IsTank()
	local role = Ask(_G.UnitGroupRolesAssigned, "player")
	if role == "TANK" then
		return true
	elseif role == "HEALER" or role == "DAMAGER" then
		return false
	end
	local form = Num(Ask(_G.GetShapeshiftFormID))
	return form ~= nil and TANK_FORMS[form] == true
end

function Threat.Grouped()
	return Ask(_G.IsInGroup) == true or Ask(_G.IsInRaid) == true
end

function Threat.Colour(state)
	local c
	if state == "aggro" then
		c = MelloUI.Meaning.threatAggro
	elseif state == "close" then
		c = MelloUI.Meaning.threatClose
	else
		c = MelloUI.Palette.selectedTrim
	end
	return c[1], c[2], c[3]
end
