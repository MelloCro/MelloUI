--------------------------------------------------------------------------------
-- MelloUI - Personal Display: Tracked Spells' list (WoW Forever 1.60.1.70532), every
-- class's short auras that can land on you, from the client's own spell data
-- (written by Tools/group_spells_forever.py with the Group Frames' groups:
-- never edit by hand).
-- ns.TrackedSpells[class] = { { main, kind, seconds, { aura IDs }, { casts } }, ... }:
-- main the spell its name and picture come from; kind "b" a buff, "d" a
-- debuff (a lockout: Weakened Soul); seconds its length from the data; casts the
-- class's spells whose cast puts it on
--------------------------------------------------------------------------------

local _, ns = ...

ns.TrackedSpells = {
	build = "1.60.1.70532",
	DRUID = {
		{ 740, "b", 10, { 740, 8918, 9862, 9863, 21791, 25817 }, { 740, 8918, 9862, 9863 } },   -- Tranquility
		{ 774, "b", 12, { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 }, { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 } },   -- Rejuvenation
		{ 8936, "b", 21, { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 }, { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 } },   -- Regrowth
		{ 2893, "b", 8, { 2893 }, { 2893 } },   -- Abolish Poison
		{ 22812, "b", 15, { 22812 }, { 22812 } },   -- Barkskin
		{ 29166, "b", 20, { 29166 }, { 29166 } },   -- Innervate
	},
	HUNTER = {
		{ 19263, "b", 10, { 19263 }, { 19263 } },   -- Deterrence
	},
	MAGE = {
		{ 543, "b", 30, { 543, 8457, 8458, 10223, 10225 }, { 543, 8457, 8458, 10223, 10225 } },   -- Fire Ward
		{ 6143, "b", 30, { 6143, 8461, 8462, 10177, 28609 }, { 6143, 8461, 8462, 10177, 28609 } },   -- Frost Ward
		{ 11426, "b", 60, { 11426, 13031, 13032, 13033 }, { 11426, 13031, 13032, 13033 } },   -- Ice Barrier
		{ 11958, "b", 10, { 11958 }, { 11958 } },   -- Ice Block
	},
	PALADIN = {
		{ 1022, "b", 10, { 1022, 5599, 10278 }, { 1022, 5599, 10278 } },   -- Blessing of Protection
		{ 6940, "b", 30, { 6940, 20729 }, { 6940, 20729 } },   -- Blessing of Sacrifice
		{ 498, "b", 8, { 498, 5573 }, { 498, 5573 } },   -- Divine Protection
		{ 642, "b", 12, { 642, 1020 }, { 642, 1020 } },   -- Divine Shield
		{ 1044, "b", 10, { 1044 }, { 1044 } },   -- Blessing of Freedom
		{ 25771, "d", 60, { 25771 }, { 498, 642, 1020, 1022, 5573, 5599, 10278 } },   -- Forbearance
	},
	PRIEST = {
		{ 139, "b", 15, { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 }, { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 } },   -- Renew
		{ 7001, "b", 10, { 7001, 27873, 27874 }, { 7001, 27873, 27874 } },   -- Lightwell Renew
		{ 17, "b", 30, { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 }, { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 } },   -- Power Word: Shield
		{ 552, "b", 20, { 552 }, { 552 } },   -- Abolish Disease
		{ 10060, "b", 15, { 10060 }, { 10060 } },   -- Power Infusion
		{ 6788, "d", 15, { 6788 }, { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 } },   -- Weakened Soul
	},
	ROGUE = {
		{ 5277, "b", 15, { 5277 }, { 5277 } },   -- Evasion
	},
	SHAMAN = {
		{ 16177, "b", 15, { 16177 }, { 16177 } },   -- Ancestral Fortitude
	},
	WARLOCK = {
		{ 6229, "b", 30, { 6229, 11739, 11740, 28610 }, { 6229, 11739, 11740, 28610 } },   -- Shadow Ward
	},
	WARRIOR = {
		{ 871, "b", 12, { 871 }, { 871 } },   -- Shield Wall
		{ 12976, "b", 20, { 12976 }, { 12976 } },   -- Last Stand
	},
}
