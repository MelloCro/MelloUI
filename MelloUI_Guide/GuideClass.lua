--------------------------------------------------------------------------------
-- MelloUI - Guide: class help (the warlock for the demo)
--
-- What the steps (GuideSteps.lua) need to know of a class: where it trains
-- and at which levels, its class quests, and its fight tips for a hard
-- quest. One table per class file; a class with none gets no train or class
-- steps and the plain "find a group" on a hard quest.
--
--   Class[classFile] = {
--     trainer       the trainers' subname in the Quest List's services
--                   (MelloUI_QuestListData.services: "trainer", name,
--                   subname, side, continent, world x, y): the train step
--                   goes to the nearest of the character's side
--     trainerLevels the levels new spells come at
--     pets          the class quests' keys in the order they come
--     classQuests   [key] = { level, title, the chain's quests in order }:
--                   a quest ID, or a list of IDs any one of which does
--                   (the ways into a chain from different home towns; the
--                   nearest giver is led to)
--     tips          [kind] = text: "fight" for a quest 3 levels above the
--                   character, "group" for 5 above or elite
--   }
--
-- Sources: the class quests' IDs are the warlock's class-masked Alliance
-- quests of Mello's data (MelloUI_QuestListData, class bit 256) whose chains
-- end in a pet's "The Binding" (the Horde's chains are the same pets; their
-- IDs come with the Horde). Left out: the data's Succubus quests with no
-- chain (1717, 65602, 65603). The trainer levels are INFERRED (vanilla's
-- rule: new spell ranks at every even level; no open table names them for
-- Forever). The tips are our own writing.
--------------------------------------------------------------------------------

local _, ns = ...

local Class = {}
ns.Class = Class

Class.WARLOCK = {
	trainer = "Warlock Trainer",
	trainerLevels = { 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30 },
	pets = { "voidwalker", "succubus", "felhunter" },
	classQuests = {
		-- Gakin's Summons (Goldshire, or The Slaughtered Lamb from Ironforge),
		-- Surena Caledon, The Binding: the Voidwalker
		voidwalker = { level = 10, title = "the Voidwalker", { 1685, 1715 }, 1688, 1689 },
		-- Devourer of Souls, Heartswood, The Binding: the Succubus
		succubus = { level = 20, title = "the Succubus", 1716, 1738, 1739 },
		-- Seeking Strahad, the Tome of the Cabal three times, The Binding: the Felhunter
		felhunter = { level = 30, title = "the Felhunter", 1798, 1758, 1802, 1804, 1795 },
	},
	tips = {
		fight = "Hard fight: send the pet in first and let it hold the mob, put your curses and Corruption on, then "
			.. "Drain Life while it lasts. Life Tap and drink between pulls, and pull one at a time.",
		group = "Elite or well above your level: find a group for this one, or come back a few levels later.",
	},
}

-- the plain advice for a class with no tips of its own
Class.GROUP = "Elite or well above your level: find a group for this one, or come back a few levels later."
