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
-- side list, the top bar's controls); a page's entry in the side list from
-- c.navEntry(key), which unfolds its group and brings the row into view at
-- once; a page's header parts (its switch, its picker, the preview) and its
-- tabs from the built page. A side-list entry's tip hangs off its right
-- edge, over the page. A step whose part this build does not have (no Edit
-- Layout yet, the installer left out) is passed over.
--------------------------------------------------------------------------------

local EMPTY = {}

-- a page's side-list entry: the step's `nav`, else its own page
local function NavTarget(c, _, step)
	return c.navEntry(step.nav or step.page)
end

-- a page's tab by its name (the step's `tab`); none on a page with one tab
local function TabTarget(_, page, step)
	for _, tab in ipairs(page and page.tabs or EMPTY) do
		if tab.section and tab.section.name == step.tab then
			return tab
		end
	end
	return nil
end

-- a part of the page's header, by its field on the page (the step's
-- `header`): its switch, its picker, the live preview
local function HeaderTarget(_, page, step)
	return page and page[step.header] or nil
end

-- a top bar control (the step's `part`) while it is there: shown
local function BarTarget(c, _, step)
	local part = c.part(step.part)
	return (part and part:IsShown()) and part or nil
end

-- Edit Layout's button: only in a build that has Edit Layout (its entry,
-- MelloUI.StartEditLayout; the button shows only then)
local function EditLayoutTarget(c, page, step)
	if type(MelloUI.StartEditLayout) ~= "function" then
		return nil
	end
	return BarTarget(c, page, step)
end

local STEPS = {
	{ page = "Home", point = "BottomEdgeCenter",
	  target = function(c) return c.part("title") end,
	  text = "Welcome to MelloUI. This is its settings window: /mello opens it, or the MelloUI button in the game menu (Escape); its emblem and its name sit on top. Every part of your interface has its page here. This tour shows where things live; close the window to stop it." },
	{ page = "Home", point = "RightEdgeTop",
	  target = function(c) return c.part("nav") end,
	  text = "The side list: the pages by group (The look, Frames and bars, Chat and text, Quests and travel, Sound), gold for the page you are on. Click a group's name to fold it. The box over it searches every setting: each result shows where it lives (page, tab and section), and a click takes you there." },
	{ page = "Home", point = "LeftEdgeCenter",
	  target = function(_, page) return page.setup end,
	  text = "Your setup: the profile in use (choosing another asks first), the palette and the Kit Colours with Change… to their place on Look, your screen and what is on. The installer sets everything up again from here." },
	{ page = "Look", point = "RightEdgeCenter", target = NavTarget,
	  text = "Look: the look of the whole interface in one place. The painted reskin, the palette, the soft shade, the borders, the fonts, Dark Mode, the bar texture and the parchment sheets. The other pages link here for these." },
	{ page = "Look", point = "BottomEdgeCenter", target = HeaderTarget, header = "switch",
	  text = "UI Modifications, the switch at the top of Look: the painted reskin and every feature that tunes the interface (Dark Mode, Fonts, Chat, Tooltip, Buffs & Debuffs, the windows' skins and more) go with it. Off, the game's own art stays everywhere; the palette, the UI Shade and Reduce Motion keep working." },
	{ page = "Look", point = "BottomEdgeLeft", target = TabTarget, tab = "General",
	  text = "Every page works the same way: its tabs on top, and on every tab the same sections in the same order (General, Look, Text, Layout, Behaviour, Sound, Text-to-Speech, Advanced), each tab showing only the ones it has. An option that needs another switch is dimmed and says which one. A link row shows a setting whose place is another page, with a button to it (Look >, Minimap >). Reset this page, at the top, puts the page back to its defaults (on a page with a picker, the one picked); it asks first." },
	{ page = "UnitFrames", point = "BottomEdgeLeft", target = HeaderTarget, header = "picker",
	  text = "Unit Frames has a picker: the frame the page is for (Player, Target, Focus, Pet, Party, Raid Frames, Cast Bars, Personal Resource). Copy from… gives this frame another frame's settings (it asks first); All, beside a setting, gives its value to every frame. A setting marked shared is one setting for several frames. Action Bars and Windows have pickers too." },
	{ page = "UnitFrames", point = "LeftEdgeCenter", target = HeaderTarget, header = "preview",
	  text = "The preview: a sample of the picked frame that follows your settings as you change them." },
	{ page = "Windows", point = "BottomEdgeLeft", target = HeaderTarget, header = "picker",
	  text = "Windows: the game's windows in the painted look, one at a time. Pick a window for its Painted Skin, its backgrounds (click one to see every choice as a picture) and links to its shade, parchment and borders on Look." },
	-- (Edit Layout's step, in its own words, while the build has it: the
	-- one step about moving things, on the top bar's Edit Layout button;
	-- 0.15.0: it replaced the step at the old Layout group)
	{ page = "Windows", point = "BottomEdgeCenter", target = EditLayoutTarget, part = "edit",
	  text = "Edit Layout: move and resize everything. Drag an element, wheel to resize, right-click for its size, position and snapping, Ctrl+right-click to reset it. Nothing is kept until you choose Save. Action bars and unit frames open the game's Edit Mode from there." },
	-- (the top bar's Install… is there while the installer is)
	{ page = "Windows", point = "BottomEdgeCenter", target = BarTarget, part = "install",
	  text = "Install…, in the top bar: the installer. It sets MelloUI up in a few steps, fitted to your screen: Full experience, No reskin, Reskin only or Fresh start. You have 15 seconds to keep the new setup, and Revert on Home's Your setup goes back later." },
	{ page = "VoiceOver", point = "RightEdgeCenter", target = NavTarget,
	  text = "Voice Over: every quest giver and greeting read aloud, in a voice matched to the NPC's race and gender. With the voice pack installed the recorded lines play; without it the text-to-speech voices do. The overlay shows who is speaking. In chat: /vo stop, /vo packs. The quest log gets a Read button." },
	{ page = "QuestList", point = "RightEdgeCenter", target = NavTarget,
	  text = "Quest List: on the world map, every quest of the zone you look at, with its giver, turn-in, chain and dungeon, plus docks, zeppelins and instance doors as pins. The filters are on this page. /qlmap explains the pins." },
	{ page = "Route", point = "RightEdgeCenter", target = NavTarget,
	  text = "Route: an arrow and a line on the map to the tracked quest or any map pin, along paths learned as you walk, flights and boats included. It keeps the route you are following and never sends you back for a corner you cut. /route shows what it knows, /route clear stops it." },
	{ page = "Minimap", point = "BottomEdgeLeft", target = TabTarget, tab = "Services Bar",
	  text = "Services Bar, a tab of the Minimap page: the bar under the minimap, in six groups, routes you to the nearest repair, mailbox, inn, flight master, auction house, bank or trainer, learning the ones it meets; Errands holds your reminders. /services <kind> does the same from chat." },
	{ page = "QuestTracker", point = "RightEdgeCenter", target = NavTarget,
	  text = "Quest Tracker: the quests you watch in a tracker under the minimap, as wide as the map above it, that scrolls when the list runs long. The nearest quest comes first (the arrow on its title switches it), each with its distance. With the reskin on, its Painted Skin switch dresses it in the kit." },
	{ page = "Reminders", point = "RightEdgeCenter", target = NavTarget,
	  text = "Reminders: a small round button beside your portrait for supplies running low, new mail, worn gear and new training. Click it to go there. The page's other tabs: Restock keeps your list and buys only when you click Buy; Vendor repairs your gear and sells your junk." },
	{ page = "Nameplates", point = "BottomEdgeLeft", target = TabTarget, tab = "Party Markers",
	  text = "Party Markers, a tab of the Nameplates page: a class medallion over every party member's head, ringed in their role's colour, on their friendly nameplate (turn those on in the game's options). In the open world; inside instances this game keeps friendly nameplates to itself." },
	{ page = "CustomSounds", point = "RightEdgeCenter", target = NavTarget,
	  text = "Custom Sounds: the interface's own sounds replaced by a recorded library, iron, leather, parchment and stone: clicks, windows, bags, gear, vendors, whispers, the group finder, targets, loot, the level up, the scroll wheel. Off until you switch it on here; each family has its own toggle." },
	{ page = "CustomSounds", point = "BottomEdgeLeft", target = TabTarget, tab = "Preview",
	  text = "The Preview tab: every sound with a Play button and where the game uses it, so you can listen before switching a family on. /sfx log in chat prints what the game plays and what replaced it." },
	{ page = "Profiles", point = "BottomEdgeLeft",
	  target = function(_, page) return page.saveButton end,
	  text = "Profiles: save every setting under a name, load one (it asks first) or delete one, and mark one as the default for a fresh install. Everything Off is built in and is that default out of the box. The game keeps your settings. Macro Backup on this page can also keep a copy in account macros, brought back only when you ask; /mello status shows both." },
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
