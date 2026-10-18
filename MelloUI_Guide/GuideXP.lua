--------------------------------------------------------------------------------
-- MelloUI - Guide: XP, estimated and learned
--
--   XP.estimate(record, playerLevel)  -> lo, hi: the XP a quest gives the
--                       character at that level. Learned (below) when the
--                       guide has seen it turned in: that XP, scaled by the
--                       grey-quest reduction once the character has outgrown
--                       the quest further than when it was learned (lo = hi).
--                       Else from the open data's XP table at the quest's
--                       level: difficulty 4 as the lowest, 5 as the highest
--                       (INFERRED: the open data names no quest's difficulty,
--                       and most quests are one of the two), reduced the same
--                       way. A quest of level 0 or below scales: the
--                       character's level.
--   XP.learn(questID, xp[, playerLevel])  the XP a quest gave, kept in
--                       MelloUIGuideLearned (account-wide: a quest gives every
--                       character the same at the same level); QUEST_TURNED_IN
--                       calls it
--   XP.kill(mobLevel, playerLevel, rested)  -> xp, bonus: the XP of one kill
--                       (vanilla's rule, INFERRED for Forever: cmangos
--                       XP::BaseGain for Azeroth's 45), the bonus counted in it
--                       while rested (true: the kill's XP again; a number: the
--                       rested pool, the bonus as much of the kill's XP as it
--                       still holds). At the character's own level it is
--                       45 + 5 x level, the planner's own rule (GuidePlan.lua).
-- The grey-quest reduction (vanilla's rule, INFERRED for Forever): full XP up
-- to 5 levels below the character, then 80, 60, 40 and 20%, and 10% from 10
-- levels below on.
--------------------------------------------------------------------------------

local addonName, ns = ...

local XP = {}
ns.XP = XP

local floor, min = math.floor, math.min

local VERSION = 1              -- MelloUIGuideLearned's format; another one is dropped
local LOW, HIGH = 4, 5         -- the open data's difficulties for a quest's lowest and highest estimate
local REDUCED = { [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 }
local GREY = 0.1               -- 10 levels and more below the character
local BASE = 45                -- kill XP's base in Azeroth

local function Plain(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return v
end

local function PlayerLevel()
	local ok, level = pcall(UnitLevel, "player")
	level = ok and Plain(level) or nil
	return type(level) == "number" and level > 0 and level or 1
end

local function Round(v)
	return floor(v + 0.5)
end

-- the share of a quest's XP a character gets: by how far below it the quest is
local function Share(questLevel, playerLevel)
	local below = playerLevel - questLevel
	if below <= 5 then
		return 1
	end
	return REDUCED[below] or GREY
end
XP.Share = Share

--------------------------------------------------------------------------------
-- Learned XP
--------------------------------------------------------------------------------

-- MelloUIGuideLearned = { version = 1, quests = { [questID] = { xp, level } } }:
-- the XP a quest gave and the character's level then
local function Store()
	local store = rawget(_G, "MelloUIGuideLearned")
	if type(store) ~= "table" or store.version ~= VERSION or type(store.quests) ~= "table" then
		store = { version = VERSION, quests = {} }
		_G.MelloUIGuideLearned = store
	end
	return store
end

function XP.learn(questID, xp, playerLevel)
	questID, xp = Plain(questID), Plain(xp)
	if type(questID) ~= "number" or type(xp) ~= "number" or xp <= 0 then
		return false
	end
	Store().quests[questID] = { xp, playerLevel or PlayerLevel() }
	return true
end

function XP.learned(questID)
	local q = Store().quests[questID]
	if type(q) == "table" and type(q[1]) == "number" then
		return q[1], q[2]
	end
	return nil
end

--------------------------------------------------------------------------------
-- Estimates
--------------------------------------------------------------------------------

local function TableRow(level)
	local open = ns.OpenData or rawget(_G, "MelloUI_GuideOpenData")
	local t = open and open.questXP
	if not t then
		return nil
	end
	if t[level] then
		return t[level]
	end
	local top
	for l in pairs(t) do
		if not top or l > top then
			top = l
		end
	end
	return top and t[level > top and top or 1]
end

function XP.estimate(record, playerLevel)
	playerLevel = playerLevel or PlayerLevel()
	local level = record and record.level
	if type(level) ~= "number" or level <= 0 then
		level = playerLevel
	end
	local share = Share(level, playerLevel)
	local xp, at = XP.learned(record and record.id)
	if xp then
		local v = Round(xp / Share(level, at or playerLevel) * share)
		return v, v
	end
	local row = TableRow(level)
	if not row then
		return 0, 0
	end
	return Round((row[LOW] or 0) * share), Round((row[HIGH] or 0) * share)
end

--------------------------------------------------------------------------------
-- Kills
--------------------------------------------------------------------------------

-- levels below the character at which a mob gives nothing more (cmangos
-- GetZeroDifference)
local function ZeroDifference(level)
	if level < 8 then return 5
	elseif level < 10 then return 6
	elseif level < 12 then return 7
	elseif level < 16 then return 8
	elseif level < 20 then return 9
	elseif level < 30 then return 11
	elseif level < 40 then return 12
	elseif level < 45 then return 13
	elseif level < 50 then return 14
	elseif level < 55 then return 15
	elseif level < 60 then return 16
	end
	return 17
end

-- the highest level of a grey mob (cmangos GetGrayLevel)
local function GreyLevel(level)
	if level <= 5 then return 0
	elseif level <= 39 then return level - 5 - floor(level / 10)
	elseif level <= 59 then return level - 1 - floor(level / 5)
	end
	return level - 9
end

function XP.kill(mobLevel, playerLevel, rested)
	playerLevel = playerLevel or PlayerLevel()
	mobLevel = mobLevel or playerLevel
	local base = playerLevel * 5 + BASE
	local xp
	if mobLevel >= playerLevel then
		xp = floor((floor(base * (20 + min(mobLevel - playerLevel, 4)) / 10) + 1) / 2)
	elseif mobLevel <= GreyLevel(playerLevel) then
		xp = 0
	else
		local zd = ZeroDifference(playerLevel)
		xp = floor(base * (zd + mobLevel - playerLevel) / zd)
	end
	local bonus = 0
	if rested == true then
		bonus = xp
	elseif type(rested) == "number" and rested > 0 then
		bonus = min(xp, floor(rested))
	end
	return xp + bonus, bonus
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("QUEST_TURNED_IN")
events:SetScript("OnEvent", function(self, event, a, b)
	if event == "ADDON_LOADED" then
		if Plain(a) == addonName then
			self:UnregisterEvent("ADDON_LOADED")
			Store()   -- (a saved format of another version is dropped here)
		end
	elseif event == "QUEST_TURNED_IN" then
		-- (the level the quest's XP was given at: the event comes before the
		-- level it may bring, INFERRED)
		XP.learn(a, b)
	end
end)
