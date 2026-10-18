--------------------------------------------------------------------------------
-- MelloUI - Guide: the choice window, the step bar and the session's plan
--
-- What the player sees of the guide, all of it MelloUI's own parts:
--   the choice window   at a break point ("guide" "choice"): "Where next?",
--                       Kit:OwnWindow in the installer's look (the corner
--                       ring, the rail's plate, the calm ground), a lead line
--                       (level, XP, rested XP), one W.Card per area offered
--                       (its picture, title, levels and time, quests and
--                       chains, travel; the planner's "Recommended" or
--                       "Short stay" tag), the recommended one picked (gold),
--                       the mode line, and two buttons: "Plan the session"
--                       (the picked area chosen and the plan window opened)
--                       and "Go to <area>" (the picked area chosen)
--   the step bar        one row of the Reminders' widget column (column =
--                       true): the current step's label, step n of the
--                       session, its quests' names and, on a hard step, the
--                       fight tip's first clause (the whole tip in the
--                       tooltip); two round buttons on hover: Change route
--                       (the choice window from any step: the cards open, or
--                       the planner's areas from where the character is now)
--                       and Plan (the plan window); a click on the row opens
--                       the plan window too
--   the plan window     the session's steps from the current one on, the
--                       current one in gold
-- Area pictures: MelloUI_Guide/Media/Areas/<name>.tga (512 x 256, our own,
-- made on Denis's box), <name> from the area's zone name (GuideData's
-- areaTitles, the planner's title): lower case, letters only, the first of
-- AREA_ART it starts with ("Redridge Mountains" -> redridge), else "default".
-- Nothing is made at load: the bus listener only; the row is registered with
-- the first "guide" event (the module switched on), the windows made at
-- their first open.
--
--   MelloUI.Guide.UI (ns.UI):
--   UI.OpenChoice([areas])  the choice window (areas: Guide:Areas())
--   UI.OpenPlan()           the plan window
--   UI.Refresh()            the step bar and an open plan window again
--   UI.ART_DIR, UI.ArtFor(title) -> the picture's path
--   UI.choiceFrame, UI.cards (the shown ones), UI.goButton, UI.planButton,
--   UI.planFrame, UI.ROW_KEY, UI.row (the row's spec)  (for the specs)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local CreateFrame = MelloUI.Safe.CreateFrame

local UI = {}
ns.UI = UI
if ns.Guide then
	ns.Guide.UI = UI
end

local floor, max, min = math.floor, math.max, math.min

UI.ART_DIR = "Interface\\AddOns\\MelloUI_Guide\\Media\\Areas\\"
UI.ROW_KEY = "guide"
local LOGO = "Interface\\AddOns\\MelloUI\\Media\\Textures\\LogoIcon.tga"
local ICON = "Interface\\Icons\\INV_Misc_Book_09"

-- the pictures there are (Media/Areas), matched by the zone name's start
local AREA_ART = { "elwynn", "westfall", "redridge", "duskwood", "lochmodan", "dunmorogh", "wetlands", "teldrassil",
	"darkshore", "ashenvale", "stonetalon", "hillsbrad", "arathi", "zephras", "darnassus", "stormwind", "ironforge" }

local CARD_W, CARD_H, PIC_H, GAP, EDGE, TOP = 300, 236, 132, 16, 16, -64
local CARDS = 3
local WIN_W, WIN_H = EDGE * 2 + CARD_W * CARDS + GAP * (CARDS - 1), 400
local PLAN_W, PLAN_ROWS, PLAN_ROW_H = 440, 14, 18

local MODES = { fast = "Fast leveling", scenic = "Scenic", zones = "Zones in your order", complete = "Every quest" }

local function Guide()
	return ns.Guide
end

local function Plain(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return v
end

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, ...)
	return ok and Plain(v) or nil
end

-- 4210 -> "4,210"
local function Thousands(n)
	local s = tostring(floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- seconds -> "1 h 40 min", "35 min"
local function Duration(seconds)
	local m = max(1, floor((seconds or 0) / 60 + 0.5))
	if m >= 60 then
		local h = floor(m / 60)
		m = m - h * 60
		return m > 0 and (h .. " h " .. m .. " min") or (h .. " h")
	end
	return m .. " min"
end

function UI.ArtFor(title)
	local name = type(title) == "string" and title:lower():gsub("[^a-z]", "") or ""
	for _, art in ipairs(AREA_ART) do
		if name ~= "" and name:sub(1, #art) == art then
			return UI.ART_DIR .. art
		end
	end
	return UI.ART_DIR .. "default"
end

local function AreaTitle(area)
	if area.title then
		return area.title
	end
	local titles = ns.Data and ns.Data.areaTitles and ns.Data.areaTitles() or {}
	return titles[area.key] or "Somewhere new"
end

local function CardText(area)
	local from, to = floor(area.levelsFrom or 0), floor(area.levelsTo or 0)
	local levels = (to > from) and ("Levels " .. from .. " to " .. to) or ("Level " .. from)
	local chains = area.chains or 0
	return levels .. ", about " .. Duration(area.seconds) .. "\n"
		.. (area.quests or 0) .. (area.quests == 1 and " quest" or " quests")
		.. (chains > 0 and (", " .. chains .. (chains == 1 and " chain" or " chains")) or "") .. "\n"
		.. "Travel: " .. Duration(area.travel) .. (area.estimated and " (estimated)" or "")
end

local function LeadText(count)
	local level = Call(UnitLevel, "player") or 0
	local class = Call(UnitClass, "player")
	local where = Call(_G.GetMinimapZoneText) or Call(_G.GetZoneText)
	local xp, xpMax = Call(UnitXP, "player"), Call(UnitXPMax, "player")
	local rested = Call(_G.GetXPExhaustion)
	local parts = { "Level " .. level .. (class and (" " .. class:lower()) or "") .. ((where and where ~= "") and (" in " .. where) or "") }
	if xp and xpMax and xpMax > 0 then
		parts[#parts + 1] = Thousands(xp) .. " / " .. Thousands(xpMax) .. " XP"
	end
	if rested and rested > 0 then
		parts[#parts + 1] = Thousands(rested) .. " rested (kills give double)"
	end
	local ways = count == 1 and "One good way on." or ((count == 2 and "Two" or "Three") .. " good ways on.")
	return table.concat(parts, "  ·  ") .. "\n" .. ways
		.. " Each keeps you questing there until the next break, your class's training and quests on the way."
end

local function ModeText()
	local G = Guide()
	local mode = G and G.db and G.db.mode or "fast"
	return "Mode: " .. (MODES[mode] or mode) .. "   ·   Change route any time from the guide's bar"
end

--------------------------------------------------------------------------------
-- The choice window
--------------------------------------------------------------------------------

local choice   -- { frame, shell, lead, mode, go, plan, pool = { [slot] = { [tag] = card } } }
local picked   -- the picked area

local function Pick(area)
	picked = area
	for _, card in ipairs(UI.cards or {}) do
		card:SetSelected(card.area == area)
	end
	if choice and area then
		choice.go:SetText("Go to " .. AreaTitle(area))
	end
end

local function Choose(thenPlan)
	local area = picked
	if choice then
		choice.frame:Hide()
	end
	local G = Guide()
	if area and G then
		G:ChooseArea(area.key)
	end
	if thenPlan then
		UI.OpenPlan()
	end
end

local function MakeChoice()
	local W, Kit = MelloUI.Widgets, MelloUI.Kit
	local f = CreateFrame("Frame", "MelloUIGuideChoice", UIParent)
	f:SetSize(WIN_W, WIN_H)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:Hide()
	local shell = Kit:OwnWindow(f, { area = "installer", ring = { at = "tl", texture = LOGO }, plate = "rail",
		title = "Where next?", close = true, escape = true, fit = true, calm = true })
	local lead = W.Text(f, "GameFontHighlight", "", "text")
	lead:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + 8, TOP)
	lead:SetPoint("RIGHT", f, "RIGHT", -EDGE - 8, 0)
	lead:SetJustifyH("LEFT")
	local go = W.Button(f, "Go to", 210, shell, { height = 26, gold = true, onClick = function() Choose(false) end })
	go:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -EDGE - 4, 18)
	local plan = W.Button(f, "Plan the session", 170, shell, { height = 26, onClick = function() Choose(true) end })
	plan:SetPoint("RIGHT", go, "LEFT", -10, 0)
	local mode = W.Text(f, "GameFontHighlight", "", "text")
	mode:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", EDGE + 8, 24)
	choice = { frame = f, shell = shell, lead = lead, mode = mode, go = go, plan = plan, pool = {} }
	UI.choiceFrame, UI.goButton, UI.planButton = f, go, plan
end

-- a card for the slot with this tag (W.Card makes its tag once: one card per
-- slot and tag, kept and reused)
local function CardFor(slot, tag)
	local W = MelloUI.Widgets
	local pool = choice.pool[slot] or {}
	choice.pool[slot] = pool
	local key = tag or ""
	local card = pool[key]
	if not card then
		card = W.Card(choice.frame, { width = CARD_W, height = CARD_H, title = "", text = "", tag = tag,
			picture = UI.ART_DIR .. "default", pictureHeight = PIC_H, onClick = function(self)
				Pick(self.area)
			end }, choice.shell)
		-- (512 x 256 into 284 x 132: the full width, a little cut off top and bottom)
		card.picture:SetTexCoord(0, 1, 0.035, 0.965)
		pool[key] = card
	end
	return card
end

function UI.OpenChoice(areas)
	local G = Guide()
	if not areas then
		areas = G and G.Areas and G:Areas() or nil
	end
	if type(areas) ~= "table" or #areas == 0 then
		return false
	end
	if not choice then
		MakeChoice()
	end
	for _, pool in pairs(choice.pool) do
		for _, card in pairs(pool) do
			card:Hide()
			card.area = nil
		end
	end
	local n = min(#areas, CARDS)
	local left = (WIN_W - (n * CARD_W + (n - 1) * GAP)) / 2
	local shown, first = {}, nil
	for i = 1, n do
		local area = areas[i]
		local card = CardFor(i, area.tag)
		card.area = area
		card:SetTexts(AreaTitle(area), CardText(area))
		card.picture:SetTexture(UI.ArtFor(AreaTitle(area)))
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", choice.frame, "TOPLEFT", left + (i - 1) * (CARD_W + GAP), TOP - 46)
		card:Show()
		shown[i] = card
		if not first and area.tag == "Recommended" then
			first = area
		end
	end
	UI.cards = shown
	choice.lead:SetText(LeadText(n))
	choice.mode:SetText(ModeText())
	Pick(first or areas[1])
	choice.frame:Show()
	choice.frame:Raise()
	return true
end

--------------------------------------------------------------------------------
-- The plan window
--------------------------------------------------------------------------------

local planWin   -- { frame, shell, head, rows = { fontstring }, more }

local function MakePlan()
	local W, Kit = MelloUI.Widgets, MelloUI.Kit
	local f = CreateFrame("Frame", "MelloUIGuidePlan", UIParent)
	f:SetSize(PLAN_W, 120 + PLAN_ROWS * PLAN_ROW_H)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:Hide()
	local shell = Kit:OwnWindow(f, { area = "installer", ring = { at = "tl", texture = LOGO }, plate = "rail",
		title = "The session", close = true, escape = true, fit = true, calm = true })
	local head = W.Text(f, "GameFontHighlight", "", "text")
	head:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + 8, TOP)
	head:SetPoint("RIGHT", f, "RIGHT", -EDGE - 8, 0)
	local rows = {}
	for i = 1, PLAN_ROWS do
		local row = W.Text(f, "GameFontHighlight", "", "text")
		row:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + 8, TOP - 28 - (i - 1) * PLAN_ROW_H)
		row:SetPoint("RIGHT", f, "RIGHT", -EDGE - 8, 0)
		row:SetWordWrap(false)
		rows[i] = row
	end
	local more = W.Text(f, "GameFontHighlight", "", "text")
	more:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + 8, TOP - 28 - PLAN_ROWS * PLAN_ROW_H - 4)
	planWin = { frame = f, shell = shell, head = head, rows = rows, more = more }
	UI.planFrame = f
end

local function FillPlan()
	local W = MelloUI.Widgets
	local G = Guide()
	local session = G and G:Plan()
	local steps = session and session.steps or {}
	local at = G and G.index or 1
	if #steps == 0 then
		planWin.head:SetText("No session planned: pick an area with Change route.")
	else
		local titles = ns.Data and ns.Data.areaTitles and ns.Data.areaTitles() or {}
		planWin.head:SetText((titles[session.area] or "The session") .. ": step " .. at .. " of " .. #steps
			.. (session.seconds and (", about " .. Duration(session.seconds) .. " in all") or ""))
	end
	for i, row in ipairs(planWin.rows) do
		local j = at + i - 1
		local s = steps[j]
		row:SetText(s and (j .. ".  " .. tostring(s.label or s.kind)) or "")
		W.Paint(row, j == at and "selectedTrim" or "text", "text")
	end
	local rest = #steps - (at + PLAN_ROWS - 1)
	planWin.more:SetText(rest > 0 and ("and " .. rest .. (rest == 1 and " more step" or " more steps")) or "")
end

function UI.OpenPlan()
	if not planWin then
		MakePlan()
	end
	FillPlan()
	planWin.frame:Show()
	planWin.frame:Raise()
	return true
end

--------------------------------------------------------------------------------
-- The step bar (a row of the widget column)
--------------------------------------------------------------------------------

local function QuestNames(step)
	local G = Guide()
	local names = {}
	local ids = step.questIDs or (step.quest and { step.quest }) or {}
	for _, id in ipairs(ids) do
		local r = G and G.records and G.records[id]
		local title = r and r.title
		if not title and C_QuestLog and C_QuestLog.GetTitleForQuestID then
			title = Call(C_QuestLog.GetTitleForQuestID, id)
		end
		if type(title) == "string" and title ~= "" then
			names[#names + 1] = title
		end
	end
	if #names > 3 then
		return names[1] .. ", " .. names[2] .. " and " .. (#names - 2) .. " more"
	end
	return table.concat(names, ", ")
end

-- the tip's first clause, for the row (the whole tip is in the tooltip)
local function ShortTip(tip)
	local cut = tip:match("^([^,%.]+)")
	return cut or tip
end

local function Current()
	local G = Guide()
	return G and G.isEnabled and G:Current() or nil
end

local function Waiting()
	local G = Guide()
	return G and G.isEnabled and not G:Current() and type(G.choice) == "table" and #G.choice > 0
end

local registered = false

local function Register()
	local Rem = MelloUI.Reminders
	if registered or not (Rem and Rem.Register) then
		return
	end
	registered = true
	UI.row = {
		key = UI.ROW_KEY, column = true, label = "Guide", enabled = true, icon = ICON,
		check = function()
			return (Current() ~= nil or Waiting()) and true or false
		end,
		title = function()
			local s = Current()
			if s then
				return tostring(s.label or s.kind)
			end
			return "Where next? Pick an area"
		end,
		text = function()
			local s, G = Current(), Guide()
			local session = G and G:Plan()
			if s and session and session.steps then
				return "Step " .. (G.index or 1) .. " of " .. #session.steps
			end
			return ""
		end,
		sub = function()
			local s = Current()
			if not s then
				return "Change route opens the cards."
			end
			local names = QuestNames(s)
			if s.tip then
				local tip = ShortTip(s.tip)
				return names ~= "" and (names .. "\n" .. tip) or tip
			end
			return names
		end,
		tooltip = function(_, tooltip)
			local s = Current()
			if s and s.tip and tooltip and tooltip.AddLine then
				tooltip:AddLine(s.tip, 1, 0.82, 0, true)
			end
		end,
		hint = "Click: the session's steps",
		onClick = function()
			UI.OpenPlan()
		end,
		actions = {
			{ glyph = "way", tip = "Change route", desc = "The areas to choose from, from where you are now.",
			  fn = function() UI.OpenChoice() end },
			{ glyph = "list", tip = "Plan", desc = "The session's steps.",
			  fn = function() UI.OpenPlan() end },
		},
	}
	Rem:Register(UI.row)
end

function UI.Refresh()
	local Rem = MelloUI.Reminders
	if registered and Rem and Rem.Refresh then
		Rem:Refresh(UI.ROW_KEY)
	end
	if planWin and planWin.frame:IsShown() then
		FillPlan()
	end
end

MelloUI:On("guide", function(kind, a)
	Register()
	if kind == "choice" then
		UI.OpenChoice(a)
	elseif choice and choice.frame:IsShown() and kind == "plan" then
		-- (an area chosen elsewhere: the cards are done)
		choice.frame:Hide()
	end
	UI.Refresh()
end, UI)
