-- MelloUI Map's gap fills, made by Tools/map_fills.py from the paintings of the gaps between zones (painted
-- for MelloUI, Tools/map_gaps.py's sheets): never edit by hand (run the tool). docs/plans/seamless-map.md.
local _, ns = ...
-- [continent uiMapID] = { { x, y, w, h: its place on the continent's painting (0..1), cols, rows: its grid of
-- tiles, tiles = { column, row, file (Media\\Fills), ... } } }: under the continent's zones, over the ground
ns.MapFills = {
	[1414] = {
		{ x = 0.494957, y = 0.117852, w = 0.130845, h = 0.098129, cols = 4, rows = 2, tiles = {   -- gap 1: Winterspring, Moonglade, Darkshore
			0, 0, "f1414_01_0_0", 1, 0, "f1414_01_0_1", 2, 0, "f1414_01_0_2", 3, 0, "f1414_01_0_3",
			0, 1, "f1414_01_1_0", 1, 1, "f1414_01_1_1", 2, 1, "f1414_01_1_2", 3, 1, "f1414_01_1_3",
		} },
		{ x = 0.486680, y = 0.322717, w = 0.125442, h = 0.094087, cols = 4, rows = 2, tiles = {   -- gap 2: Ashenvale, Mount Hyjal, Azshara, Winterspring
			0, 0, "f1414_02_0_0", 1, 0, "f1414_02_0_1", 2, 0, "f1414_02_0_2", 3, 0, "f1414_02_0_3",
			0, 1, "f1414_02_1_0", 1, 1, "f1414_02_1_1", 2, 1, "f1414_02_1_2", 3, 1, "f1414_02_1_3",
		} },
		{ x = 0.364471, y = 0.368413, w = 0.079441, h = 0.059581, cols = 4, rows = 2, tiles = {   -- gap 3: Stonetalon Mountains, Ashenvale
			0, 0, "f1414_03_0_0", 1, 0, "f1414_03_0_1", 2, 0, "f1414_03_0_2", 3, 0, "f1414_03_0_3",
			0, 1, "f1414_03_1_0", 1, 1, "f1414_03_1_1", 2, 1, "f1414_03_1_2", 3, 1, "f1414_03_1_3",
		} },
		{ x = 0.547771, y = 0.394738, w = 0.131005, h = 0.098249, cols = 4, rows = 2, tiles = {   -- gap 4: Azshara, Durotar, Ashenvale
			0, 0, "f1414_04_0_0", 1, 0, "f1414_04_0_1", 2, 0, "f1414_04_0_2", 3, 0, "f1414_04_0_3",
			0, 1, "f1414_04_1_0", 1, 1, "f1414_04_1_1", 2, 1, "f1414_04_1_2", 3, 1, "f1414_04_1_3",
		} },
		{ x = 0.362650, y = 0.549775, w = 0.064122, h = 0.192365, cols = 2, rows = 4, tiles = {   -- gap 5: Feralas, Desolace, Shen'dralas
			0, 0, "f1414_05_0_0", 0, 1, "f1414_05_1_0", 1, 1, "f1414_05_1_1", 0, 2, "f1414_05_2_0",
			0, 3, "f1414_05_3_0",
		} },
		{ x = 0.297355, y = 0.633870, w = 0.325449, h = 0.366130, cols = 4, rows = 3, tiles = {   -- gap 6: Silithus, Un'Goro Crater, Feralas, Thousand Needles
			1, 0, "f1414_06_0_1", 2, 0, "f1414_06_0_2", 3, 0, "f1414_06_0_3", 0, 1, "f1414_06_1_0",
			1, 1, "f1414_06_1_1", 2, 1, "f1414_06_1_2", 3, 1, "f1414_06_1_3", 0, 2, "f1414_06_2_0",
			1, 2, "f1414_06_2_1", 2, 2, "f1414_06_2_2",
		} },
	},
	[1415] = {
		{ x = 0.462575, y = 0.079716, w = 0.186627, h = 0.139970, cols = 4, rows = 2, tiles = {   -- gap 7: Eastern Plaguelands, Western Plaguelands, Tirisfal Glades
			0, 0, "f1415_07_0_0", 1, 0, "f1415_07_0_1", 2, 0, "f1415_07_0_2", 3, 0, "f1415_07_0_3",
			0, 1, "f1415_07_1_0", 1, 1, "f1415_07_1_1", 2, 1, "f1415_07_1_2", 3, 1, "f1415_07_1_3",
		} },
		{ x = 0.508009, y = 0.289741, w = 0.127695, h = 0.383094, cols = 2, rows = 4, tiles = {   -- gap 8: Wetlands, Arathi Highlands, Loch Modan, Badlands
			0, 0, "f1415_08_0_0", 1, 0, "f1415_08_0_1", 0, 1, "f1415_08_1_0", 1, 1, "f1415_08_1_1",
			0, 2, "f1415_08_2_0", 1, 2, "f1415_08_2_1", 0, 3, "f1415_08_3_0", 1, 3, "f1415_08_3_1",
		} },
		{ x = 0.302944, y = 0.313698, w = 0.329242, h = 0.493862, cols = 4, rows = 4, tiles = {   -- gap 9: Dun Morogh, Wetlands, Elwynn Forest, Burning Steppes
			1, 0, "f1415_09_0_1", 2, 0, "f1415_09_0_2", 0, 1, "f1415_09_1_0", 1, 1, "f1415_09_1_1",
			2, 1, "f1415_09_1_2", 3, 1, "f1415_09_1_3", 1, 2, "f1415_09_2_1", 2, 2, "f1415_09_2_2",
			1, 3, "f1415_09_3_1", 2, 3, "f1415_09_3_2",
		} },
	},
}
