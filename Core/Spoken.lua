--------------------------------------------------------------------------------
-- MelloUI - Spoken (2.1.96; the user, 2026-11-28: "can we add full integration with Spoken addon?", then the four
-- parts picked -- a MelloUI narrator window, Play buttons, no double voices, its Addons page row -- with "Spoken
-- first"; docs/plans/spoken.md)
--
-- Spoken (Rusty Key's voice-over for WoW Forever: quests and gossip, books, zone lore, boss stories, each from its own
-- module and voice pack) publishes an API for other addons: one global, `Spoken`, its Public calls a contract that
-- never breaks (Spoken:IsCompatible(1); a later call is found by its field, never by a version). MelloUI meets it only
-- there: nothing of Spoken's hooked, written or copied. Its Addons page switch (Core/Integrations.lua, key "Spoken")
-- off: MelloUI leaves it alone, as if it were not there.
--
--   MelloUI.Spoken.API() -> Spoken | nil        loaded, keeping contract 1, its switch on
--   MelloUI.Spoken.Speaks(part) -> bool         Spoken reads that part now: "quests" (quest dialogue and gossip),
--                                               "readables" (books), "places", "bosses" -- its module loaded and the
--                                               part on in Spoken's settings
--   MelloUI.Spoken.Story(kind, id) -> bool      a voiced story Spoken can play now: "quest" (quest id), "instance"
--                                               (instance map id), "boss" (encounter id)
--   MelloUI.Spoken.Playing(kind, id) -> bool    that story speaking now
--   MelloUI.Spoken.Toggle(kind, id) -> bool     played (behind the line speaking), or stopped while it speaks or
--                                               waits; the switch's sound. False: no such story
--   MelloUI.Spoken.On(event, fn)                one of Spoken's Public events (AUDIO_CHANGED, CLIP_STARTED, ...),
--                                               registered once Spoken is there; nothing without it
-- Who uses it: MelloUI_VoiceOver (Spoken first: it stands aside where Spoken reads; its Read buttons play Spoken's
-- recording of a quest where there is one), the Quest Tracker's menu, Dungeon Info's story buttons.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Plain = MelloUI.Safe.Value

local SP = { MODULES = { quests = "Spoken_Quests", readables = "Spoken_Readables", places = "Spoken_Places",
	bosses = "Spoken_Bosses" } }
MelloUI.Spoken = SP

local function Loaded(folder)
	local fn = C_AddOns and C_AddOns.IsAddOnLoaded
	if not (folder and fn) then
		return false
	end
	local ok, on = pcall(fn, folder)
	return ok and Plain(on) == true
end

function SP.API()
	local S = rawget(_G, "Spoken")
	if type(S) ~= "table" or type(S.IsCompatible) ~= "function" then
		return nil
	end
	local ok, yes = pcall(S.IsCompatible, S, 1)
	if not (ok and yes == true) then
		return nil
	end
	local I = MelloUI.Integrations
	if I and I.Use and not I.Use("Spoken") then
		return nil
	end
	return S
end

-- one of Spoken's calls on it, answered safely (nil: no Spoken, no such call, or it raised)
local function Ask(name, ...)
	local S = SP.API()
	local fn = S and S[name]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a = pcall(fn, S, ...)
	if ok then
		return a
	end
	return nil
end

function SP.Speaks(part)
	if not Loaded(SP.MODULES[part]) then
		return false
	end
	return Ask("IsPartOn", part) == true
end

function SP.Story(kind, id)
	return type(id) == "number" and Ask("HasStory", kind, id) == true or false
end

function SP.Playing(kind, id)
	return type(id) == "number" and Ask("IsPlayingStory", kind, id) == true or false
end

function SP.Toggle(kind, id)
	if not SP.Story(kind, id) then
		return false
	end
	-- (a story waiting behind another line counts as playing it: StopStory takes it out, as the second click)
	if Ask("StopStory", kind, id) == true then
		MelloUI:PlayUISound("option_off")
		return true
	end
	if Ask("PlayStory", kind, id) == true then
		MelloUI:PlayUISound("option_on")
		return true
	end
	return false
end

-- Spoken's Public events, each registered once Spoken is there (MelloUI's addons load before or after it: asked again
-- at the login)
SP.waiting = {}
function SP.On(event, fn)
	local S = SP.API()
	if S and type(S.RegisterCallback) == "function" then
		pcall(S.RegisterCallback, S, event, fn)
	else
		SP.waiting[#SP.waiting + 1] = { event, fn }
	end
end

function SP.Login()
	local S = SP.API()
	if not (S and type(S.RegisterCallback) == "function") then
		return
	end
	local list = SP.waiting
	SP.waiting = {}
	for _, w in ipairs(list) do
		pcall(S.RegisterCallback, S, w[1], w[2])
	end
end

do
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents()
		SP.Login()
	end)
end
