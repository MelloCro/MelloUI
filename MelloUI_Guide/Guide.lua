--------------------------------------------------------------------------------
-- MelloUI - Guide: the module
--
-- The leveling guide as one of MelloUI's modules (its own addon, as Route and
-- the Quest List are: MelloUI.Features.Guide). It hears the game's quest and
-- XP events and has the steps (GuideSteps.lua) check the current step after
-- each, once a frame however many came in it.
--
--   MelloUI.Guide (also the namespace's Guide):
--   Guide:Current()        -> step: the one being led, nil while the choice
--                             cards wait for a pick (Guide.choice holds them)
--   Guide:Plan()           -> session: Plan.session's, the steps as led
--                             (Guide.index is the current one's place in it)
--   Guide:ChooseArea(key)  the session in that area, from where you are now
--   Guide:Replan(reason)   the session made again in the chosen area
--   Guide:Allows(questID, kind)  Quest Auto's filter (kind "accept" or
--                             "turnin"): only the plan's quests, while
--                             Auto Accept Plan Quests is on
--   Guide.choice, Guide.index, Guide.routed  (beside the four functions the
--                             plan named, for the choice window and the
--                             specs) the open cards or nil, the current
--                             step's place in the plan, whether Route took
--                             the current step's place
-- The module is off by default (MelloUI's own switch, the configurator's
-- page): nothing is planned or led, and Route keeps no destination of the
-- guide's, until the player switches it on.
-- The bus topic "guide" (MelloUI:On("guide", fn)):
--   "step", step, index     a new current step (Route leads there)
--   "plan", session         a new session plan
--   "choice", areas         a break point: the areas to choose from (the
--                           choice cards, GuidePlan.areas'), best first
-- Events: PLAYER_LEVEL_UP plans again (a level opens quests, spells and class
-- quests); QUEST_TURNED_IN of a quest the plan does not hold plans again;
-- QUEST_ACCEPTED, QUEST_REMOVED, QUEST_LOG_UPDATE (objectives done),
-- PLAYER_XP_UPDATE (a grind step), TRAINER_CLOSED (a train step) check the
-- step; Route's "arrived" ends a travel or train step.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("MelloUI_Guide (Guide)")
local C_Timer = Perf.C_Timer

local Steps = ns.Steps

local M = MelloUI:RegisterModule("Guide", {
	title = "Guide",
	desc = "Where to go next for your level: the quests of an area bundled by place, then step by step with Route's arrow, with your class's training and pet quests on the way.",
	icon = "Interface\\Icons\\INV_Misc_Book_09",
	flavour = "Where next, by level and XP, and every step of the way.",
	-- (after the group's six: the Quest List 1 ... Gains 6)
	group = "Quests and travel", navOrder = 7,
	-- (a feature, as Route and the Quest List declare it, and no installer
	-- field as they have none: its switch is on the installer's Features step)
	role = "feature",
	-- (off until the player switches it on: a new feature, opt-in until Mello
	-- decides otherwise; Full experience leaves it off too, as it is not in
	-- Mello's profile. Switched on, it leads at once: Steps.Login below)
	enabledByDefault = false,
	defaults = {
		mode = "fast",
		autoQuests = true,
	},
	-- (each control names the update it came with, Core's rule: its New tag)
	options = {
		{ type = "header", name = "Planning" },
		{ type = "dropdown", key = "mode", name = "Route Style", new = "0.23.1", values = {
			{ value = "fast", label = "Fast Leveling" },
			{ value = "scenic", label = "Scenic" },
		  }, desc = "Fast Leveling: the most XP for the time, travel counted. Scenic: an area's own story chains first, with less hopping between areas." },
		{ type = "toggle", key = "autoQuests", name = "Auto Accept Plan Quests Only", new = "0.23.1",
		  desc = "While Auto Accept & Hand In is on, it takes and hands in only the quests of the guide's plan; the others are left to you." },
	},
})

MelloUI.Guide = M
ns.Guide = M

M.index = 1

-- one check a frame, whatever came in it; a replan asked wins over a check
local pending, replanWhy = false, nil

local function Run()
	pending = false
	if not M.isEnabled then
		return
	end
	local why = replanWhy
	replanWhy = nil
	if why then
		Steps.Replan(M, why)
	else
		Steps.Check(M)
	end
end

local function Soon(why)
	if why and not replanWhy then
		replanWhy = why
	end
	if not pending then
		pending = true
		C_Timer.After(0, Run)
	end
end

local eventFrame

local function OnEvent(_, event, a)
	if event == "PLAYER_LEVEL_UP" then
		Soon("level up")
	elseif event == "QUEST_TURNED_IN" then
		local id = MelloUI.Safe.Value(a)
		Soon((type(id) == "number" and not Steps.HoldsQuest(M, id)) and "a quest the plan does not hold" or nil)
	elseif event == "TRAINER_CLOSED" then
		Steps.Trained(M)
		Soon()
	else
		Soon()
	end
end

local EVENTS = { "PLAYER_LEVEL_UP", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_XP_UPDATE",
	"QUEST_LOG_UPDATE", "TRAINER_CLOSED" }

function M.filter(questID, kind)
	return Steps.Allows(M, questID, kind)
end

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	if not eventFrame then
		eventFrame = CreateFrame("Frame")
		eventFrame:SetScript("OnEvent", OnEvent)
	end
	for _, event in ipairs(EVENTS) do
		eventFrame:RegisterEvent(event)
	end
	MelloUI:On("route", function(kind, d)
		if kind == "arrived" then
			Steps.Arrived(M, d)
			Soon()
		end
	end, M)
	-- (after the other modules: Route and the Quest List lead and know the quests)
	MelloUI:WhenModulesOn(function()
		if M.isEnabled then
			Steps.Login(M)
		end
	end)
end

function M:OnDisable()
	if eventFrame then
		eventFrame:UnregisterAllEvents()
	end
	MelloUI:Off(M)
	Steps.SyncFilter(M)
end

function M:OnSettingChanged(key)
	if key == "mode" then
		Soon("the route style changed")
	elseif key == "autoQuests" then
		Steps.SyncFilter(M)
	end
end

function M:Current()
	return Steps.Current(M)
end

function M:Plan()
	return M.session
end

function M:ChooseArea(key)
	Steps.Choose(M, key)
end

function M:Replan(reason)
	Steps.Replan(M, reason or "asked")
end

function M:Allows(questID, kind)
	return Steps.Allows(M, questID, kind)
end
