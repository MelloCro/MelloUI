--------------------------------------------------------------------------------
-- MelloUI - Quest Tracker, the controller's stop (2.1.55, stage 2 of docs/plans/controller-forever.md; the user,
-- 2026-11-16: "full MelloUI Compatibility, that means navigation trough our menus, map, quest tracker etc", then the
-- sketch quest_tracker_pad_sketch's pick: "A plus B's action").
--
-- A, step into the tracker. P.Enter() (the slash command /mellotracker, for a bind or a wheel of the controller
-- addon) moves the pad into the tracker until B: an own window of stops laid over the tracker's parts -- Questie's
-- quests while its tracker stands in MelloUI's place (Core/QuestieLook.lua's TrackerQuests), MelloUI's own tracker's
-- headings and blocks (Modules/QuestTracker.lua's PadParts) -- walked by MelloUI's one pad navigation (G.Own with its
-- nav: the gold frame, the D-pad, A).
--   A      the part's own left click (a quest: what a click on it does, the map with it)
--   X      the quest's item (its own secure button, bound straight to the pad's X while the quest is focused)
--   Y      the part's own right click (a quest's menu)
--   left / right on a guide's heading: its Back and Skip arrows
--   B      back to the game
-- A stop only stands over a part: the click is the part's own, nothing of the tracker is rebuilt or re-parented.
--
-- B's action, pick without leaving the fight. P.Next() (/mellonext) marks the next quest in the tracker and runs its
-- own left click; the pad never leaves the player's binds. The mark: a gold bar and a tint, gone after MARK_SECONDS.
--
-- Nothing at login: the window, the stops and the strip are made at the first Enter, the mark at the first Next.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("QuestTrackerPad")
local W = MelloUI.Widgets
local Num = MelloUI.Safe.Number

local P = {}
MelloUI.QuestTrackerPad = P

local TEXT = { map = "Open", item = "Use Item", menu = "Menu", back = "Back", step = "Back / Skip A Step",
	none = "Nothing in the Quest Tracker to step through.", fight = "The Quest Tracker opens for the controller after the fight." }
local KEYS = { PADDUP = "UP", PADDDOWN = "DOWN", PADDLEFT = "LEFT", PADDRIGHT = "RIGHT",
	PAD1 = "A", PAD2 = "BACK", PAD3 = "X", PAD4 = "MENU" }
local MARK_SECONDS = 4

local win, strip, mark = nil, nil, nil
local stops, entries, marked = {}, {}, 0

--------------------------------------------------------------------------------
-- The tracker's parts, top to bottom
--------------------------------------------------------------------------------

local function Top(e)
	return Num(e.top:GetTop()) or 0
end

local function Entries()
	local out = {}
	local QL = MelloUI.QuestieLook
	local base = rawget(_G, "Questie_BaseFrame")
	if QL and QL.TrackerQuests and base and base:IsVisible() then
		for _, q in ipairs(QL.TrackerQuests()) do
			out[#out + 1] = { kind = "quest", top = q.line, bottom = q.bottom, click = q.line, item = q.item, questID = q.questID }
		end
	end
	local QT = MelloUI:GetModule("QuestTracker")
	if QT and QT.PadParts then
		for _, p in ipairs(QT.PadParts()) do
			out[#out + 1] = p
		end
	end
	table.sort(out, function(a, b)
		return Top(a) > Top(b)
	end)
	return out
end

-- a part's own click: a Button's Click, else its mouse-up script
local function Click(frame, button)
	if not frame then
		return
	end
	if frame.Click then
		frame:Click(button)
		return
	end
	local fn = frame:GetScript("OnMouseUp")
	if fn then
		fn(frame, button)
	end
end

--------------------------------------------------------------------------------
-- The stops and the window
--------------------------------------------------------------------------------

local Stop_OnClick = Perf.Shared("OnClick on a Quest Tracker pad stop", function(self)
	local e = self.entry
	if e then
		Click(e.click, "LeftButton")
	end
end, "script")

local function Hover(self, script)
	local e = self.entry
	local fn = e and e.click and e.click:GetScript(script)
	if fn then
		pcall(fn, e.click)
	end
end
local Stop_OnEnter = Perf.Shared("OnEnter on a Quest Tracker pad stop", function(self)
	Hover(self, "OnEnter")
end, "script")
local Stop_OnLeave = Perf.Shared("OnLeave on a Quest Tracker pad stop", function(self)
	Hover(self, "OnLeave")
end, "script")

local function Stop(i)
	local b = stops[i]
	if not b then
		b = CreateFrame("Button", "MelloUIPadTrackerStop" .. i, win)
		b:RegisterForClicks("AnyUp")
		Perf.SetScript(b, "OnClick", Stop_OnClick)
		Perf.SetScript(b, "OnEnter", Stop_OnEnter)
		Perf.SetScript(b, "OnLeave", Stop_OnLeave)
		stops[i] = b
	end
	return b
end

local function Lay()
	entries = Entries()
	for i, e in ipairs(entries) do
		local b = Stop(i)
		b.entry = e
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", e.top, "TOPLEFT", 0, 0)
		b:SetPoint("BOTTOMRIGHT", e.bottom, "BOTTOMRIGHT", 0, 0)
		b:Show()
	end
	for i = #entries + 1, #stops do
		stops[i].entry = nil
		stops[i]:Hide()
	end
	return #entries
end

local function Current()
	local G = MelloUI.Gamepad
	local c = G and G.Current()
	return c and c.entry or nil, c
end

-- the strip of prompts under the tracker's lowest part (as the bag window's: coins and their words)
local function Strip()
	local G = MelloUI.Gamepad
	local on = win ~= nil and G ~= nil and G.Holder() == win and #entries > 0
	if not on then
		if strip then
			strip:Hide()
		end
		return
	end
	if not strip then
		strip = CreateFrame("Frame", nil, win)
		strip:SetHeight(24)
		strip:EnableMouse(false)
		W.Solid(strip, "BACKGROUND", "innerPanel", 0.9):SetAllPoints(strip)
		strip.items = {}
		for i, key in ipairs({ "PAD1", "PAD3", "PAD4", "PAD2" }) do
			local coin = G.Coin()
			coin:SetParent(strip)
			coin:SetFrameLevel(strip:GetFrameLevel() + 2)
			local words = W.Text(strip, "GameFontHighlight", "", "text")
			words:SetPoint("LEFT", coin, "RIGHT", 4, 0)
			strip.items[i] = { coin = coin, words = words, key = key }
		end
	end
	local e = Current()
	local last = entries[#entries]
	strip:ClearAllPoints()
	strip:SetPoint("TOPLEFT", last.bottom, "BOTTOMLEFT", 0, -6)
	strip:SetPoint("TOPRIGHT", last.bottom, "BOTTOMRIGHT", 0, -6)
	local Tr = W.Tr
	local texts = { Tr(TEXT.map), e and e.item and Tr(TEXT.item) or nil, e and e.kind ~= "section" and Tr(TEXT.menu) or nil,
		Tr(TEXT.back) }
	local prev
	for i, item in ipairs(strip.items) do
		local text = texts[i]
		item.coin:ClearAllPoints()
		if text then
			if prev then
				item.coin:SetPoint("LEFT", prev, "RIGHT", 12, 0)
			else
				item.coin:SetPoint("LEFT", strip, "LEFT", 8, 0)
			end
			G.SetCoin(item.coin, item.key)
			item.words:SetText(text)
			item.coin:Show()
			item.words:Show()
			prev = item.words
		else
			item.coin:Hide()
			item.words:Hide()
		end
	end
	strip:Show()
end

local Press = Perf.Shared("the Quest Tracker's pad keys", function(name, down, dir)
	if not down then
		return
	end
	local e = Current()
	if name == "BACK" then
		P.Leave()
	elseif name == "MENU" then
		if e and e.kind ~= "section" then
			Click(e.click, "RightButton")
		end
	elseif name == "EDGE" and e then
		-- (nothing that way to walk to: on a guide's heading, its Back and Skip arrows)
		if dir == "LEFT" and e.back then
			Click(e.back, "LeftButton")
		elseif dir == "RIGHT" and e.skip then
			Click(e.skip, "LeftButton")
		end
	end
end, "script")

function P.Leave()
	if win and win:IsShown() then
		win:Hide()
	end
	if strip then
		strip:Hide()
	end
end

function P.Enter()
	local G = MelloUI.Gamepad
	if not (G and G.On()) then
		return false
	end
	if InCombatLockdown() then
		MelloUI:Announce(W.Tr(TEXT.fight), "info")
		return false
	end
	if win and win:IsShown() then
		P.Leave()
		return false
	end
	if not win then
		win = CreateFrame("Frame", "MelloUIPadTracker", UIParent)
		win:SetFrameStrata("HIGH")
		win:SetAllPoints(UIParent)
		win:EnableMouse(false)
		win:Hide()
		G.Window(win, { back = function()
			P.Leave()
			return true
		end, first = function()
			return stops[1]
		end })
	end
	if Lay() == 0 then
		MelloUI:Announce(W.Tr(TEXT.none), "info")
		return false
	end
	win:Show()
	G.Own(win, { keys = KEYS, press = Press, nav = win })
	Strip()
	return true
end

-- the pad left (a fight, the window gone): the window with it; the focus moved: the item on X, the strip's words
MelloUI:On("gamepad:nav", function(on, starting)
	if not on and starting and win and win:IsShown() then
		P.Leave()
	end
	Strip()
end, "Quest Tracker: the pad's stop (the pad taken or given back)")
MelloUI:On("gamepad:focus", function(c)
	if not (win and win:IsShown()) then
		return
	end
	local e = c and c.entry
	local G = MelloUI.Gamepad
	local item = e and e.item and e.item:GetName()
	G.OwnKey("PAD3", item and ("click:" .. item) or "X")
	Strip()
end, "Quest Tracker: the pad's stop (the focus moved)")

--------------------------------------------------------------------------------
-- Next Quest: the next quest marked, the pad left alone
--------------------------------------------------------------------------------

local function Unmark()
	if mark then
		mark:Hide()
	end
end

function P.Next()
	local quests = {}
	for _, e in ipairs(Entries()) do
		if e.questID then
			quests[#quests + 1] = e
		end
	end
	if #quests == 0 then
		Unmark()
		return nil
	end
	marked = marked % #quests + 1
	local e = quests[marked]
	if not mark then
		mark = CreateFrame("Frame", nil, UIParent)
		mark:SetFrameStrata("HIGH")
		mark:EnableMouse(false)
		W.Solid(mark, "BACKGROUND", "selectedTrim", 0.14):SetAllPoints(mark)
		local bar = W.Solid(mark, "ARTWORK", "selectedTrim", 1)
		bar:SetPoint("TOPLEFT", mark, "TOPLEFT", -1, 0)
		bar:SetPoint("BOTTOMLEFT", mark, "BOTTOMLEFT", -1, 0)
		bar:SetWidth(3)
	end
	mark:ClearAllPoints()
	mark:SetPoint("TOPLEFT", e.top, "TOPLEFT", 0, 0)
	mark:SetPoint("BOTTOMRIGHT", e.bottom, "BOTTOMRIGHT", 0, 0)
	mark:Show()
	mark.stamp = (mark.stamp or 0) + 1
	local stamp = mark.stamp
	C_Timer.After(MARK_SECONDS, function()
		if mark.stamp == stamp then
			Unmark()
		end
	end)
	Click(e.click, "LeftButton")
	return e.questID
end

-- (the two as key bindings too: Bindings.xml; a controller addon may bind a named action, a macro with the slash
-- command works in any of them)
BINDING_NAME_MELLOUI_TRACKER_PAD = "Quest Tracker: step in with the controller"
BINDING_NAME_MELLOUI_TRACKER_NEXT = "Quest Tracker: next quest"

SLASH_MELLOTRACKERPAD1 = "/mellotracker"
SlashCmdList.MELLOTRACKERPAD = function()
	P.Enter()
end
SLASH_MELLONEXTQUEST1 = "/mellonext"
SlashCmdList.MELLONEXTQUEST = function()
	P.Next()
end
