--------------------------------------------------------------------------------
-- MelloUI - NPC voice overrides
--
-- Media\NPCVoiceData.lua is generated from the vanilla NPC list and covers
-- almost every NPC that Forever inherited. NPCs that are new to Forever are
-- not in it and are read with the plain male / female voice. List them here
-- to give them a race profile. Talk to (or target) an NPC and type  /vo npc
-- to see its ID and whether it is already known.
--
-- Race codes: human, dwarf, gnome, nightelf, highelf, orc, troll, tauren,
-- undead, goblin, ogre, giant, kobold, murloc, gnoll, trogg, furbolg, naga,
-- satyr, harpy, centaur, quilboar, dragon, demon, imp, succubus, elemental,
-- spirit, treant, keeper, dryad, insect, mechanical, beast, other
-- Gender: "m", "f" or "n".
--
-- Entries here also win over the generated data, so they can correct it too.
-- A /reload picks up changes.
--------------------------------------------------------------------------------

MelloUI_NPCVoiceOverrides = {
	[265003] = { race = "gnome", gender = "m" },   -- Thom Filch (Important Heirlooms)
	-- [248242] = { race = "human", gender = "m" },   -- Hamish Bergwort (Tower of Azora)
}
