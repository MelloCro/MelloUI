--------------------------------------------------------------------------------
-- MelloUI - Group Frames: the spell groups' data (WoW Forever 1.60.1.70532), every
-- class's auras that belong on party and raid frames in their groups, from the
-- client's own spell data (written by Tools/group_spells_forever.py: never edit
-- by hand).
--   hot 6, shield 1, yours 7, external 3, defensive 12, raidcd 0, power 3, movement 2, raidbuff 44, lockout 2
-- ns.GroupSpells[class][group] = { { main, id, id, ... }, ... }: main the spell
-- its name and picture come from, the IDs every aura of that name in that group
-- (includeSpellIDs); off = true: listed but off from the start (a lockout that
-- only lands on you)
--------------------------------------------------------------------------------

local _, ns = ...

ns.GroupSpells = {
	build = "1.60.1.70532",
	DRUID = {
		hot = {
			{ 740, 740, 8918, 9862, 9863, 21791, 25817 },   -- Tranquility
			{ 774, 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 },   -- Rejuvenation
			{ 8936, 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 },   -- Regrowth
		},
		yours = {
			{ 467, 467, 782, 1075, 8914, 9756, 9910 },   -- Thorns
			{ 2893, 2893 },   -- Abolish Poison
		},
		defensive = {
			{ 22812, 22812 },   -- Barkskin
		},
		power = {
			{ 29166, 29166 },   -- Innervate
		},
		raidbuff = {
			{ 1126, 1126, 5232, 5234, 6756, 8907, 9884, 9885 },   -- Mark of the Wild
			{ 21849, 21849, 21850 },   -- Gift of the Wild
			{ 24907, 24907 },   -- Moonkin Aura
			{ 17007, 24932 },   -- Leader of the Pack
		},
	},
	HUNTER = {
		defensive = {
			{ 19263, 19263 },   -- Deterrence
		},
		movement = {
			{ 13159, 13159 },   -- Aspect of the Pack
		},
		raidbuff = {
			{ 19506, 19506, 20905, 20906 },   -- Trueshot Aura
			{ 20043, 20043, 20190 },   -- Aspect of the Wild
		},
	},
	MAGE = {
		yours = {
			{ 1008, 1008, 8455, 10169, 10170 },   -- Amplify Magic
		},
		defensive = {
			{ 543, 543, 8457, 8458, 10223, 10225 },   -- Fire Ward
			{ 6143, 6143, 8461, 8462, 10177, 28609 },   -- Frost Ward
			{ 11426, 11426, 13031, 13032, 13033 },   -- Ice Barrier
			{ 11958, 11958 },   -- Ice Block
		},
		raidbuff = {
			{ 604, 604, 8450, 8451, 10173, 10174 },   -- Dampen Magic
			{ 1459, 1459, 1460, 1461, 10156, 10157 },   -- Arcane Intellect
			{ 23028, 23028 },   -- Arcane Brilliance
		},
	},
	PALADIN = {
		external = {
			{ 1022, 1022, 5599, 10278 },   -- Blessing of Protection
			{ 6940, 6940, 20729 },   -- Blessing of Sacrifice
			{ 19752, 19753 },   -- Divine Intervention
		},
		defensive = {
			{ 498, 498, 5573 },   -- Divine Protection
			{ 642, 642, 1020 },   -- Divine Shield
		},
		movement = {
			{ 1044, 1044 },   -- Blessing of Freedom
		},
		raidbuff = {
			{ 465, 465, 643, 1032, 8258, 10290, 10291, 10292, 10293, 17232 },   -- Devotion Aura
			{ 1038, 1038 },   -- Salvation
			{ 7294, 7294, 8990, 10298, 10299, 10300, 10301, 13008 },   -- Retribution Aura
			{ 19740, 19740, 19834, 19835, 19836, 19837, 19838, 25291 },   -- Blessing of Might
			{ 19742, 19742, 19850, 19852, 19853, 19854, 25290 },   -- Blessing of Wisdom
			{ 19746, 19746 },   -- Concentration Aura
			{ 19876, 19876, 19895, 19896 },   -- Shadow Resistance Aura
			{ 19888, 19888, 19897, 19898 },   -- Frost Resistance Aura
			{ 19891, 19891, 19899, 19900 },   -- Fire Resistance Aura
			{ 19977, 19977, 19978, 19979 },   -- Blessing of Light
			{ 20217, 20217 },   -- Blessing of Kings
			{ 20218, 20218 },   -- Sanctity Aura
			{ 25782, 25782, 25916 },   -- Greater Blessing of Might
			{ 25890, 25890 },   -- Greater Blessing of Light
			{ 25894, 25894, 25918 },   -- Greater Blessing of Wisdom
			{ 25895, 25895 },   -- Mass Salvation
			{ 25898, 25898 },   -- Greater Blessing of Kings
		},
		lockout = {
			{ 25771, 25771 },   -- Forbearance
		},
	},
	PRIEST = {
		hot = {
			{ 139, 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 },   -- Renew
			{ 7001, 7001, 27873, 27874 },   -- Lightwell Renew
		},
		shield = {
			{ 17, 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 },   -- Power Word: Shield
		},
		yours = {
			{ 552, 552 },   -- Abolish Disease
			{ 6346, 6346 },   -- Fear Ward
		},
		power = {
			{ 10060, 10060 },   -- Power Infusion
		},
		raidbuff = {
			{ 976, 976, 10957, 10958 },   -- Shadow Protection
			{ 1243, 1243, 1244, 1245, 2791, 10937, 10938 },   -- Power Word: Fortitude
			{ 14752, 14752, 14818, 14819, 27841 },   -- Divine Spirit
			{ 21562, 21562, 21564 },   -- Prayer of Fortitude
			{ 27681, 27681 },   -- Prayer of Spirit
			{ 27683, 27683 },   -- Prayer of Shadow Protection
		},
		lockout = {
			{ 6788, 6788 },   -- Weakened Soul
		},
	},
	ROGUE = {
		defensive = {
			{ 5277, 5277 },   -- Evasion
		},
	},
	SHAMAN = {
		hot = {
			{ 5672, 5672, 6371, 6372, 10460, 10461 },   -- Healing Stream
		},
		yours = {
			{ 16177, 16177 },   -- Ancestral Fortitude
		},
		power = {
			{ 16191, 16191, 17355, 17360 },   -- Mana Tide
		},
		raidbuff = {
			{ 5677, 5677, 10491, 10493, 10494, 24853 },   -- Mana Spring
			{ 8072, 8072, 8156, 8157, 10403, 10404, 10405 },   -- Stoneskin
			{ 8076, 8076, 8162, 8163, 10441, 25362 },   -- Strength of Earth
			{ 8177, 8178 },   -- Grounding Totem
			{ 8182, 8182, 10476, 10477 },   -- Frost Resistance
			{ 8185, 8185, 10534, 10535 },   -- Fire Resistance
			{ 8227, 8230, 8250, 10521, 15036 },   -- Flametongue Totem
			{ 8512, 8515, 10609, 10612 },   -- Windfury Totem
			{ 8836, 8836, 10626, 25360 },   -- Grace of Air
			{ 10596, 10596, 10598, 10599 },   -- Nature Resistance
			{ 15108, 15108, 15109, 15110 },   -- Windwall
		},
	},
	WARLOCK = {
		yours = {
			{ 132, 132, 2970, 11743 },   -- Detect Invisibility
		},
		defensive = {
			{ 6229, 6229, 11739, 11740, 28610 },   -- Shadow Ward
		},
	},
	WARRIOR = {
		defensive = {
			{ 871, 871 },   -- Shield Wall
			{ 12976, 12976 },   -- Last Stand
		},
		raidbuff = {
			{ 5242, 5242, 6192, 6673, 11549, 11550, 11551, 25289 },   -- Battle Shout
		},
	},
}
