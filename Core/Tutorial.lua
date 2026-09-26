--------------------------------------------------------------------------------
-- MelloUI - Tutorial
--
-- A guided tour of the settings window on the game's own help tips (the
-- yellow plates with the arrow, HelpTip in Blizzard_SharedXML): one step per
-- thing worth knowing, each pointing at the part of the window it is about,
-- with the game's Next button. Nothing of it is our own art.
--
-- The first login belongs to the installer (Core/Installer.lua: its one
-- delayed check opens it for a new player); this file asks nothing at login
-- and makes nothing then. The tour is offered on the installer's Done page
-- ("Take the tour"), and is always there as the Tutorial button on the Home
-- page and /mello tutorial.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Tutorial")
local C_Timer = Perf.C_Timer

local SYSTEM = "MelloUITutorial"

local T = { active = false, step = 0 }
MelloUI.Tutorial = T

--------------------------------------------------------------------------------
-- The steps: the page to show, the part to point at (given the window's
-- tour table `c`, the page and the step), where the tip hangs, and what it
-- says. The window's parts come from c.part(name) (the plate's title, the
-- side list, the top bar's controls); a module's entry in the side list from
-- c.navEntry(key), which unfolds its group and brings the row into view at
-- once. A side-list entry's tip hangs off its right edge, over the page.
--------------------------------------------------------------------------------

-- a module's side-list entry: the step's `nav`, else its own page
local function NavTarget(c, _, step)
	return c.navEntry(step.nav or step.page)
end

local STEPS = {
	{ page = "Home", point = "BottomEdgeCenter",
	  target = function(c) return c.part("title") end,
	  text = "Welcome to MelloUI. This is its settings window: /mello opens it, or the MelloUI button in the game menu (Escape); its emblem and its name sit on top. Every module has its page here. This tour shows where things live; close the window to stop it." },
	{ page = "Home", point = "RightEdgeTop",
	  target = function(c) return c.part("nav") end,
	  text = "The side list: the modules by group, gold for the page you are on. Click a group's name to fold it; the mouse wheel scrolls the list. Dark Mode, Fonts, Chat and the other features folded into UI Modifications open their place on its tabs." },
	{ page = "Home", point = "RightEdgeCenter", target = NavTarget, nav = "UIModifications",
	  text = "UI Modifications is the important one: the painted reskin of the whole interface and every feature that tunes it, all in one place." },
	{ page = "Home", point = "LeftEdgeCenter",
	  target = function(_, page) return page.setup end,
	  text = "Your setup: the profile in use (choosing another asks first), the Kit Colours, your screen and what is on. The installer sets everything up again from here." },
	{ page = "UIModifications", point = "RightEdgeTop",
	  target = function(_, page) return page.sections and page.sections[1] end,
	  text = "General: the painted kit reskin, one switch for the whole look, and the button that opens Dynamic UI Modification, where the look itself is chosen. Off, the game's own art stays everywhere and the features on the other tabs keep working." },
	{ page = "UIModifications", point = "BottomEdgeLeft",
	  target = function(c) return c.part("unlock") end,
	  text = "In the top bar's Layout group: Unlock the Windows. Tick it and drag any window by its title, the minimap by its zone band, the trackers by their headers, the damage meter and the chat anywhere. The mouse wheel scales a window while you drag. Auto Snapping beside it snaps a dropped window's corner to the grid; Reset positions puts everything back. It needs UI Modifications on, works with the reskin off as well, and positions stay across reloads." },
	{ page = "UIModifications", point = "BottomEdgeLeft",
	  target = function(_, page) return page.tabs and page.tabs[1] end,
	  text = "The tabs: Windows and HUD (which areas the reskin dresses), Combat (buffs and debuffs, error messages, cooldown timers, nameplate icons), Unit Frames & Bars, Chat & Tooltips, Text (a font style and the sizes) and Dark Mode / Other. Each feature starts with its own switch; its options wake when it is on." },
	{ page = "UIModifications", point = "BottomEdgeCenter",
	  target = function(c) return c.part("dynamic") end,
	  text = "Dynamic UI Modification, in the top bar on the right: the look of the reskin in one place. The borders and Kit Colours of every window, the backgrounds and backdrops, the parchment sheets and the minimap's shape, chosen on the interface itself with pictures." },
	-- (the top bar's Install… is there while the installer is)
	{ page = "UIModifications", point = "BottomEdgeCenter",
	  target = function(c)
		local install = c.part("install")
		return (install and install:IsShown()) and install or nil
	  end,
	  text = "Install…, beside it: the installer. It sets MelloUI up in a few steps, fitted to your screen: Full experience, No reskin, Reskin only or Fresh start. You have 15 seconds to keep the new setup, and Revert on Home's Your setup goes back later." },
	{ page = "VoiceOver", point = "RightEdgeCenter", target = NavTarget,
	  text = "Voice Over: every quest giver and greeting read aloud, in a voice matched to the NPC's race and gender. With the voice pack installed the recorded lines play; without it the text-to-speech voices do. The overlay shows who is speaking. In chat: /vo stop, /vo packs. The quest log gets a Read button." },
	{ page = "QuestList", point = "RightEdgeCenter", target = NavTarget,
	  text = "Quest List: on the world map, every quest of the zone you look at, with its giver, turn-in, chain and dungeon, plus docks, zeppelins and instance doors as pins. The filters are on this page. /qlmap explains the pins." },
	{ page = "Route", point = "RightEdgeCenter", target = NavTarget,
	  text = "Route: an arrow and a line on the map to the tracked quest or any map pin, along paths learned as you walk, flights and boats included. It keeps the route you are following and never sends you back for a corner you cut. /route shows what it knows, /route clear stops it." },
	{ page = "Services", point = "RightEdgeCenter", target = NavTarget,
	  text = "Services: the bar under the minimap routes you to the nearest repair, mailbox, inn, flight master, auction house, bank or trainer, learning the ones it meets. /services <kind> does the same from chat." },
	{ page = "QuestTracker", point = "RightEdgeCenter", target = NavTarget,
	  text = "Quest Tracker: the quests you watch in a tracker under the minimap, as wide as the map above it, that scrolls when the list runs long. With the reskin on, its own switch under UI Modifications, Windows dresses it in the kit." },
	{ page = "PartyMarkers", point = "RightEdgeCenter", target = NavTarget,
	  text = "Party Markers: a class medallion over every party member's head, ringed in their role's colour, on their friendly nameplate (turn those on in the game's options). In the open world; inside instances this game keeps friendly nameplates to itself." },
	{ page = "CustomSounds", point = "RightEdgeCenter", target = NavTarget,
	  text = "Custom Sounds: the interface's own sounds replaced by a recorded library, iron, leather, parchment and stone: clicks, windows, bags, gear, vendors, whispers, the group finder, targets, loot, the level up, the scroll wheel. Off until you switch it on here; each family has its own toggle." },
	{ page = "CustomSounds", point = "BottomEdgeLeft",
	  target = function(_, page) return page.tabs and page.tabs[3] end,
	  text = "The Preview tab: every sound with a Play button and where the game uses it, so you can listen before switching a family on. /sfx log in chat prints what the game plays and what replaced it." },
	{ page = "Profiles", point = "BottomEdgeLeft",
	  target = function(_, page) return page.saveButton end,
	  text = "Profiles: save every setting under a name, load one (it asks first) or delete one, and mark one as the default for a fresh install. Everything Off is built in and is that default out of the box. A copy of your settings is also kept in hidden account macros and brings them back if the saved settings ever go missing; /mello status shows both." },
	-- (the What's new card runs long: the tip at its top, where the view is)
	{ page = "Home", point = "RightEdgeTop",
	  target = function(_, page) return page.news end,
	  text = "What's new: this version's changes. Earlier versions, under them, opens the ones before." },
	{ page = "Home", point = "TopEdgeCenter",
	  target = function(_, page) return page.helpSection end,
	  text = "Help: the slash commands and the links (select one and copy it). /mello help prints the commands in chat." },
	{ page = "Home", point = "LeftEdgeCenter", last = true,
	  target = function(_, page) return page.tutorialButton end,
	  text = "That is the tour. Take it again with this button or /mello tutorial." },
}

--------------------------------------------------------------------------------
-- Running the tour
--------------------------------------------------------------------------------

local function HelpTipsAvailable()
	return type(HelpTip) == "table" and type(HelpTip.Show) == "function" and HelpTip.ButtonStyle and HelpTip.Point
end

-- The window's tour table (MelloUI:ConfigTour, one table made with the
-- window) is taken once, in T:Start, as T.c. A step selects its page at
-- once, and its tip comes a frame later (the page needs a frame to lay out
-- before its parts have a place): one shared function reads the step from
-- T.pending. Each step's tip description is made once and kept.

function T:Stop()
	if not self.active then
		return
	end
	self.active = false
	self.step = 0
	self.pending, self.lost = nil, nil
	if HelpTipsAvailable() then
		pcall(HelpTip.HideAllSystem, HelpTip, SYSTEM)
	end
end

local ShowStep

local function NextStep()
	if not T.active then
		return
	end
	local index = T.step + 1
	if index > #STEPS then
		T:Stop()
		return
	end
	ShowStep(index)
end

-- the window hidden with the whole interface (Alt+Z: its parent hid, the
-- window itself is still shown): the tour waits, and a tip that went with
-- it comes back with the interface
local function ParentOnly()
	local w = T.c and T.c.window
	return w ~= nil and w:IsShown() and not w:IsVisible()
end

local infos = {}   -- [index] = the step's tip description (HelpTip), made once
local function TipInfo(index)
	local info = infos[index]
	if info then
		return info
	end
	local step = STEPS[index]
	info = {
		text = step.text,
		buttonStyle = step.last and HelpTip.ButtonStyle.Okay or HelpTip.ButtonStyle.Next,
		targetPoint = HelpTip.Point[step.point] or HelpTip.Point.BottomEdgeCenter,
		alignment = HelpTip.Alignment.Center,
		useParentStrata = true,   -- above everything in the window
		system = SYSTEM,
		systemPriority = index,
		autoHorizontalSlide = true,
		onAcknowledgeCallback = function()
			if T.active and T.step == index then
				if step.last then
					T:Stop()
				else
					NextStep()
				end
			end
		end,
		onHideCallback = function(acknowledged)
			if acknowledged or not (T.active and T.step == index) then
				return
			end
			if ParentOnly() then
				T.lost = index   -- (shown again when the interface comes back)
				return
			end
			-- closed without the button (the window went away): the tour ends
			T:Stop()
		end,
	}
	infos[index] = info
	return info
end

local function ShowTip()
	local index = T.pending
	T.pending = nil
	if not (T.active and index and T.step == index) then
		return
	end
	local step, c = STEPS[index], T.c
	local page = c.page(step.page)
	local ok, target = pcall(step.target, c, page, step)
	if not ok or not target then
		NextStep()   -- a part this build does not have: on to the next
		return
	end
	pcall(c.scrollTo, target)
	local shown = HelpTip:Show(c.window, TipInfo(index), target)
	if not shown then
		T:Stop()
		MelloUI:Print("The game's help tips are turned off (Options, Gameplay, Help), and the tour is made of them.")
	end
end

ShowStep = function(index)
	local step, c = STEPS[index], T.c
	if not (step and c and c.window) then
		T:Stop()
		return
	end
	T.step, T.lost = index, nil
	c.select(step.page)
	T.pending = index
	C_Timer.After(0, ShowTip)
end

-- the window closed: the tour ends; hidden with the interface (Alt+Z) it
-- waits, and a step whose tip went with it shows again when it comes back
local Tour_OnHide = Perf.Shared("OnHide on the configurator (the tour)", function()
	if T.active and not ParentOnly() then
		T:Stop()
	end
end, "script")
local Tour_OnShow = Perf.Shared("OnShow on the configurator (the tour)", function()
	local lost = T.lost
	if T.active and lost then
		T.lost = nil
		ShowStep(lost)
	end
end, "script")

function T:Start()
	if not HelpTipsAvailable() then
		MelloUI:Print("This client has no help tips; the tour needs them.")
		return false
	end
	if not (MelloUI.OpenConfig and MelloUI.ConfigTour) then
		return false
	end
	self:Stop()
	local c = MelloUI:ConfigTour()
	if not (c and c.window) then
		return false
	end
	self.c = c
	local w = c.window
	if not w.melloTourHooked then
		w.melloTourHooked = true
		Perf.HookScript(w, "OnHide", Tour_OnHide)
		Perf.HookScript(w, "OnShow", Tour_OnShow)
	end
	-- shown directly: OpenConfig without a page toggles an open window closed
	w:Show()
	self.active = true
	ShowStep(1)
	return true
end
