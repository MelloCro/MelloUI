--------------------------------------------------------------------------------
-- MelloUI - Frame Effects: the tanks' tools and defensives, their kinds and
-- how long each lasts, from the client's own spell data (written by
-- Tools/heal_flight_spells.py: never edit by hand)
--   W roar (3), U taunt (8), F fortify (3), L more health (3), I immunity (5), E evasion (2)
--------------------------------------------------------------------------------

local _, ns = ...

ns.EffectKinds = {
	[355] = "U", [498] = "I", [642] = "I", [694] = "U", [871] = "F", [1020] = "I", [1161] = "W", [5209] = "W",
	[5277] = "E", [5573] = "I", [6795] = "U", [7400] = "U", [7402] = "U", [11958] = "I", [12975] = "L", [12976] = "L",
	[19263] = "E", [20559] = "U", [20560] = "U", [22812] = "F", [403828] = "U", [412789] = "W", [425294] = "F", [426195] = "L",
}

-- how long each lasts (s): its family's aura (SpellMisc, SpellDuration)
ns.EffectLasts = {
	[355] = 3, [498] = 8, [642] = 12, [694] = 6, [871] = 12, [1020] = 12, [1161] = 6, [5209] = 6,
	[5277] = 15, [5573] = 8, [6795] = 3, [7400] = 6, [7402] = 6, [11958] = 10, [12975] = 20, [12976] = 20,
	[19263] = 10, [20559] = 6, [20560] = 6, [22812] = 15, [403828] = 3, [412789] = 6, [425294] = 6, [426195] = 20,
}

-- one spell a kind for the Every Effect preview: its class's oldest (the lowest spell ID)
-- { kind, class, name, spell }
ns.EffectExamples = {
	{ "W", "Warrior", "Challenging Shout", 1161 },
	{ "U", "Warrior", "Taunt", 355 },
	{ "F", "Warrior", "Shield Wall", 871 },
	{ "L", "Warrior", "Last Stand", 12975 },
	{ "I", "Paladin", "Divine Protection", 498 },
	{ "E", "Rogue", "Evasion", 5277 },
}
