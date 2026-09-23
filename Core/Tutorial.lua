--------------------------------------------------------------------------------
-- MelloUI - Tutorial
--
-- A guided tour of the settings window on the game's own help tips (the
-- yellow plates with the arrow, HelpTip in Blizzard_SharedXML): one step per
-- thing worth knowing, each pointing at the part of the window it is about,
-- with the game's Next button. Nothing of it is our own art.
--
-- On the first login after the install (user, 2026-09-22) one of the game's
-- popups asks whether to take the tour; every module is off then (the
-- built-in "Everything Off" profile, Core.lua), so the popup also says so.
-- The answer is remembered; the tour is always there again as the Tutorial
-- button on the Home page and /mello tutorial.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local SYSTEM = "MelloUITutorial"
local ASK_DELAY = 12   -- seconds after entering the world (after the menu button tip)

local T = { active = false, step = 0 }
MelloUI.Tutorial = T

--------------------------------------------------------------------------------
-- The steps: the page to show, the part to point at (given the window's
-- parts and the page), where the tip hangs, and what it says.
--------------------------------------------------------------------------------

local STEPS = {
	{ page = "Home", point = "BottomEdgeCenter",
	  target = function(c) return c.band.title or c.band end,
	  text = "Welcome to MelloUI. This is its settings window: /mello opens it, or the MelloUI button in the game menu (Escape). Every module has a page here, and on a fresh install every module is off until you switch it on. This tour shows where things live; close the window to stop it." },
	{ page = "Home", point = "BottomEdgeCenter",
	  target = function(c) return c.strip end,
	  text = "The icon strip: one icon per module with its name under it, gold for the page you are on. Click an icon to open its page. Home, the first, lists every module as a tile." },
	{ page = "Home", point = "RightEdgeCenter",
	  target = function(c, page) return page.tiles and page.tiles.UIModifications end,
	  text = "A tile per module: its switch, whether it is on, and Open page. UI Modifications is the important one: the painted reskin of the whole interface and the quality-of-life tweaks, all in one place." },
	{ page = "UIModifications", point = "RightEdgeTop",
	  target = function(_, page) return page.sections and page.sections[1] end,
	  text = "The painted kit reskin: one switch for the whole look, then one toggle per area under it (the windows, then the HUD). Off, the game's own art stays everywhere and the tweaks on this page keep working." },
	{ page = "UIModifications", point = "BottomEdgeLeft",
	  target = function(c) return c.window and c.window.placementUnlock or c.band end,
	  text = "Up in the title bar: Unlock the Windows. Tick it and drag any window by its title, the minimap by its zone band, the trackers by their headers, the damage meter and the chat anywhere. The mouse wheel scales a window while you drag. Auto Snapping beside it snaps a dropped window's corner to the grid; Reset positions puts everything back. It works with the reskin off as well, and positions stay across reloads." },
	{ page = "UIModifications", point = "BottomEdgeLeft",
	  target = function(_, page) return page.tabs and page.tabs[1] end,
	  text = "The tabs: Nameplates, Tooltips, Chat, Unit Frames, Tweaks, Vendor, FPS / Latency, Fonts (one font per role and a size slider for each), Bar Textures, Bar Text, Class Icons, Cooldown Timers and Dark Mode. Each starts with its own switch, and each works with the reskin off." },
	{ page = "VoiceOver", point = "BottomEdgeCenter",
	  target = function(c) return c.stripButton("VoiceOver") end,
	  text = "Voice Over: every quest giver and greeting read aloud, in a voice matched to the NPC's race and gender. With the voice pack installed the recorded lines play; without it the text-to-speech voices do. The overlay shows who is speaking. In chat: /vo stop, /vo packs. The quest log gets a Read button." },
	{ page = "QuestList", point = "BottomEdgeCenter",
	  target = function(c) return c.stripButton("QuestList") end,
	  text = "Quest List: on the world map, every quest of the zone you look at, with its giver, turn-in, chain and dungeon, plus docks, zeppelins and instance doors as pins. The filters are on this page. /qlmap explains the pins." },
	{ page = "Route", point = "BottomEdgeCenter",
	  target = function(c) return c.stripButton("Route") end,
	  text = "Route: an arrow and a line on the map to the tracked quest or any map pin, along paths learned as you walk, flights and boats included. It keeps the route you are following and never sends you back for a corner you cut. /route shows what it knows, /route clear stops it." },
	{ page = "Services", point = "BottomEdgeCenter",
	  target = function(c) return c.stripButton("Services") end,
	  text = "Services: the bar under the minimap routes you to the nearest repair, mailbox, inn, flight master, auction house, bank or trainer, learning the ones it meets. /services <kind> does the same from chat." },
	{ page = "PartyMarkers", point = "BottomEdgeCenter",
	  target = function(c) return c.stripButton("PartyMarkers") end,
	  text = "Party Markers: a class medallion over every party member's head, ringed in their role's colour, on their friendly nameplate (turn those on in the game's options). In the open world; inside instances this game keeps friendly nameplates to itself." },
	{ page = "CustomSounds", point = "BottomEdgeCenter",
	  target = function(c) return c.stripButton("CustomSounds") end,
	  text = "Custom Sounds: the interface's own sounds replaced by a recorded library, iron, leather, parchment and stone: clicks, windows, bags, gear, vendors, whispers, the group finder, targets, loot, the level up, the scroll wheel. Off until you switch it on here; each family has its own toggle." },
	{ page = "CustomSounds", point = "BottomEdgeLeft",
	  target = function(c, page) return page.tabs and page.tabs[3] or c.stripButton("CustomSounds") end,
	  text = "The Preview tab: every sound with a Play button and where the game uses it, so you can listen before switching a family on. /sfx log in chat prints what the game plays and what replaced it." },
	{ page = "Profiles", point = "BottomEdgeLeft",
	  target = function(_, page) return page.saveButton end,
	  text = "Profiles: save every setting under a name, load or delete one, mark one as the default for a fresh install. Everything Off is built in and is that default out of the box. On this client the settings live in hidden account macros, since it never reads its saved variables back; /mello status shows that store." },
	{ page = "Home", point = "RightEdgeCenter",
	  target = function(_, page) return page.news end,
	  text = "What's new: the changes of each version, newest first, so you know what a fresh update brought." },
	{ page = "Home", point = "LeftEdgeCenter", last = true,
	  target = function(_, page) return page.tutorialButton end,
	  text = "That is the tour. Help at the bottom of this page lists the slash commands and the links; /mello help prints the commands in chat. Take the tour again with this button or /mello tutorial." },
}

--------------------------------------------------------------------------------
-- Running the tour
--------------------------------------------------------------------------------

local function HelpTipsAvailable()
	return type(HelpTip) == "table" and type(HelpTip.Show) == "function" and HelpTip.ButtonStyle and HelpTip.Point
end

function T:Stop()
	if not self.active then
		return
	end
	self.active = false
	self.step = 0
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

ShowStep = function(index)
	local step = STEPS[index]
	local c = MelloUI.ConfigTour and MelloUI:ConfigTour()
	if not (step and c and c.window) then
		T:Stop()
		return
	end
	T.step = index
	c.select(step.page)
	-- the page needs a frame to lay out before its parts have a place
	C_Timer.After(0, function()
		if not T.active or T.step ~= index then
			return
		end
		local page = c.page(step.page)
		local ok, target = pcall(step.target, c, page)
		if not ok or not target then
			NextStep()   -- a part this build does not have: on to the next
			return
		end
		pcall(c.scrollTo, target)
		local shown = HelpTip:Show(c.window, {
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
				-- closed without the button (the window went away): the tour ends
				if not acknowledged and T.active and T.step == index then
					T:Stop()
				end
			end,
		}, target)
		if not shown then
			T:Stop()
			MelloUI:Print("The game's help tips are turned off (Options, Gameplay, Help), and the tour is made of them.")
		end
	end)
end

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
	if not c.window.melloTourHooked then
		c.window.melloTourHooked = true
		c.window:HookScript("OnHide", function() T:Stop() end)
	end
	-- shown directly: OpenConfig without a page toggles an open window closed
	c.window:Show()
	self.active = true
	ShowStep(1)
	return true
end

--------------------------------------------------------------------------------
-- First login after the install: the question
--------------------------------------------------------------------------------

local function Flags()
	return MelloUI.GetModuleDB and MelloUI:GetModuleDB("UIModifications") or nil
end

if type(StaticPopupDialogs) == "table" then
	StaticPopupDialogs["MELLOUI_WELCOME_TOUR"] = {
		text = "MelloUI is installed. Everything is off to begin with: switch on what you want in its settings window (/mello, or the MelloUI button in the game menu).\n\nTake a short tour of that window now? It shows where every feature lives. Later: the Tutorial button on its Home page, or /mello tutorial.",
		button1 = "Take the tour",
		button2 = "Not now",
		OnAccept = function()
			T:Start()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

local asked = false
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self)
	if asked then
		return
	end
	asked = true
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	C_Timer.After(ASK_DELAY, function()
		local flags = Flags()
		if not flags or flags.welcomeAsked or not MelloUI.initialized or not StaticPopup_Show then
			return
		end
		-- remembered before the question, so a session that ends mid-way
		-- does not ask again and again
		MelloUI:NotifySettingChanged("UIModifications", "welcomeAsked", true)
		StaticPopup_Show("MELLOUI_WELCOME_TOUR")
	end)
end)
