--------------------------------------------------------------------------------
-- MelloUI - Loot Sparkles
--
-- (0.20.1, the user: a quality of life addition) Two sparkles: one the game has
-- and loses, one it never had.
--   * Quest items: the game's own loot sparkle on quest objects you can loot
--     shows only while its outline mode is off and
--     outlineModeShowLootEffectWhenDisabled is on, and a graphics preset sets
--     those back. They are held while this is on (MelloUI:HoldCVar: the
--     player's own values given back when off; a preset picked meanwhile is
--     the player's newest choice). The client takes the sparkle away again
--     only after a restart, its own.
--   * Gathering: a few golden glints (Media/FrameFX/spark_gold, MelloUI's own)
--     twinkling over the ore vein or herb -- or, if wanted, the quest object
--     -- you walk up to: dim while it is out of reach, bright in reach, grey
--     when the game refuses it (a skill too low). The game's soft targeting
--     picks the nearest object you could use (the "softinteract" unit) and can
--     give it a nameplate; the glints hang under that nameplate. What the
--     object is comes from the cursor the game would show over it (Mine,
--     GatherHerbs, Quest; an "Unable" one when it refuses). Soft targeting's
--     settings are held while any kind sparkles, given back when none does;
--     its nameplate is switched on only for an object that sparkles, so NPCs
--     and mailboxes keep theirs as the player had them.
-- Nothing runs while nothing sparkles: the soft target's and the nameplates'
-- events bring the glints in and out, and only while they show does their
-- own animation read the object's reach, a few times a second. Reduce Motion
-- (MelloUI.Anim): the glints hold still. Game settings change out of combat
-- only (in a fight, at its end). Nothing is made until the first glint shows.
--------------------------------------------------------------------------------
local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Sparkles")
local C_Timer = Perf.C_Timer
local Shared = Perf.Shared
local Secret = MelloUI.Safe.IsSecret

local NEW = "0.20.1"
local M = MelloUI:RegisterModule("Sparkles", {
	title = "Loot Sparkles",
	desc = "The game's sparkle on quest items you can loot, kept on through its graphics presets, and golden glints over the ore veins and herbs you walk up to: dim out of reach, bright in reach, grey when your skill is too low. The game settings it needs come back as you had them when it is off.",
	icon = "Interface\\Icons\\Trade_Mining",
	flavour = "What you can loot, at a glance.",
	role = "adds",
	new = NEW,
	enabledByDefault = false,
	installer = false,
	-- the player's own game settings, given back when off: never in a profile
	keep = { "savedLoot", "savedOutline", "savedOutlineEngine", "savedRaidOutline", "savedRaidOutlineEngine",
		"savedSoftInteract", "savedSoftRange", "savedSoftArc", "savedSoftOnlyInRange", "savedSoftIcon",
		"savedSoftIconObject", "savedSoftLowPriority", "savedSoftPlate" },
	defaults = { questItems = true, ore = true, herbs = true, questObjects = false },
	options = {
		{ type = "toggle", key = "questItems", name = "Quest Item Sparkles", new = NEW,
		  desc = "Keeps the game's sparkle on quest items you can loot. It needs the game's outline mode off, which its graphics presets switch back on: held while this is on, given back as you had it when off. Switching this off takes the sparkles away after the next game restart (the client's own; /reload is not enough)." },
		{ type = "toggle", key = "ore", name = "Ore Veins", new = NEW,
		  desc = "Golden glints over the ore vein you walk up to (the game's soft targeting picks the nearest one, within about 15 yards): dim out of reach, bright once you can mine it, grey when your skill is too low." },
		{ type = "toggle", key = "herbs", name = "Herbs", new = NEW,
		  desc = "The same glints over the herb you walk up to." },
		{ type = "toggle", key = "questObjects", name = "Quest Objects", new = NEW,
		  desc = "The same glints over a quest object you walk up to. Off by default: the game's own sparkle (Quest Item Sparkles) already marks most of them." },
	},
})

--------------------------------------------------------------------------------
-- The game settings
--------------------------------------------------------------------------------

-- each: the CVar, the value held, the key the player's own value is kept under
local LOOT = {
	{ "outlineModeShowLootEffectWhenDisabled", "1", "savedLoot" },
	{ "graphicsOutlineMode", "0", "savedOutline" },
	{ "OutlineEngineMode", "0", "savedOutlineEngine" },
	{ "raidGraphicsOutlineMode", "0", "savedRaidOutline" },
	{ "RAIDOutlineEngineMode", "0", "savedRaidOutlineEngine" },
}
-- soft targeting, while any kind sparkles: the interaction target always picked, all around, as far as the client lets
-- it reach (it stops near 15 yards whatever is asked), also before it is in reach; the game's interact icon over it
local SOFT = {
	{ "SoftTargetInteract", "3", "savedSoftInteract" },
	{ "SoftTargetInteractRange", "60", "savedSoftRange" },
	{ "SoftTargetInteractArc", "2", "savedSoftArc" },
	{ "SoftTargetInteractOnlyInRange", "0", "savedSoftOnlyInRange" },
	{ "SoftTargetIconInteract", "1", "savedSoftIcon" },
	{ "SoftTargetIconGameObject", "1", "savedSoftIconObject" },
	{ "SoftTargetLowPriorityIcons", "1", "savedSoftLowPriority" },
}
-- the soft target's nameplate: on only while the object sparkles (the glints hang on it)
local PLATE = { "SoftTargetNameplateInteract", "1", "savedSoftPlate" }
-- a graphics preset: the CVars it sets back (lower case, as CVAR_UPDATE may name them)
local PRESETS = { graphicsquality = true, raidgraphicsquality = true }
for _, c in ipairs(LOOT) do
	PRESETS[c[1]:lower()] = true
end

local S = {
	due = false,        -- the settings asked for in a fight: at its end
	presetDue = false,  -- a preset's settings to look at, a second after it
	plate = false,      -- the soft target's nameplate held on
	units = {},         -- nameplate tokens shown now (the soft target's own token may give none for an object)
}

local function Gathering()
	local db = M.db
	return M.isEnabled and db ~= nil and (db.ore or db.herbs or db.questObjects) and true or false
end

local function Plate(on)
	if on == S.plate or MelloUI.InCombat() then
		return
	end
	S.plate = on
	MelloUI:HoldCVar(M.db, PLATE[1], PLATE[3], on, PLATE[2])
end

local Evaluate

-- every held setting as the switches say (out of combat)
local function Holds()
	if MelloUI.InCombat() then
		S.due = true
		return
	end
	S.due = false
	local db = M.db
	if not db then
		return
	end
	local loot = M.isEnabled and db.questItems and true or false
	for _, c in ipairs(LOOT) do
		MelloUI:HoldCVar(db, c[1], c[3], loot, c[2])
	end
	local gather = Gathering()
	for _, c in ipairs(SOFT) do
		MelloUI:HoldCVar(db, c[1], c[3], gather, c[2])
	end
	if not gather then
		S.plate = false
		MelloUI:HoldCVar(db, PLATE[1], PLATE[3], false, PLATE[2])
	end
end

-- a graphics preset set the outline back: the player's newest choice kept for when this is off, held again
local function AfterPreset()
	S.presetDue = false
	local db = M.db
	if not (M.isEnabled and db and db.questItems) then
		return
	end
	if MelloUI.InCombat() then
		S.due = true
		return
	end
	for _, c in ipairs(LOOT) do
		local now = MelloUI:CVarText(c[1])
		if now ~= nil and now ~= c[2] and db[c[3]] ~= nil then
			db[c[3]] = now
		end
		MelloUI:HoldCVar(db, c[1], c[3], true, c[2])
	end
end

--------------------------------------------------------------------------------
-- What the soft target is
--------------------------------------------------------------------------------

local SOFT_UNIT = "softinteract"
-- the cursor the game would show over it: the words its file or atlas names carry
local KINDS = { { "gatherherbs", "herb" }, { "herb", "herb" }, { "mine", "ore" }, { "quest", "quest" } }
local probe          -- a hidden texture the game paints the cursor into (made on first need)
local cursorIds      -- [file id] = lower-case name of the cursor files (made on first need)

local function Call(fn, ...)
	if not fn then
		return nil
	end
	local ok, v = pcall(fn, ...)
	if not ok or Secret(v) then
		return nil
	end
	return v
end

local function CursorIds()
	if cursorIds then
		return cursorIds
	end
	cursorIds = {}
	if GetFileIDFromPath then
		for _, name in ipairs({ "Mine", "GatherHerbs", "Quest", "QuestRepeatable", "QuestTurnIn" }) do
			for _, prefix in ipairs({ "", "Unable" }) do
				local path = "Interface\\Cursor\\" .. prefix .. name
				local id = Call(GetFileIDFromPath, path) or Call(GetFileIDFromPath, path .. ".blp")
				if id then
					cursorIds[id] = (prefix .. name):lower()
				end
			end
		end
	end
	return cursorIds
end

-- a cursor's name -> its kind (nil: none that sparkles) and whether the game refuses it ("Unable")
local function KindOf(name)
	if type(name) ~= "string" then
		return nil, false
	end
	name = name:lower()
	local refused = name:find("unable", 1, true) ~= nil
	for _, k in ipairs(KINDS) do
		if name:find(k[1], 1, true) then
			return k[2], refused
		end
	end
	return nil, refused
end

local function Classify(unit)
	if not probe then
		probe = UIParent:CreateTexture(nil, "BACKGROUND")
		probe:Hide()
	end
	local kind, refused
	if Call(SetUnitCursorTexture, probe, unit, nil, true) then
		local file = Call(probe.GetTexture, probe)
		local atlas = probe.GetAtlas and Call(probe.GetAtlas, probe)
		if type(file) == "number" then
			file = CursorIds()[file]
		end
		kind, refused = KindOf(file)
		if not kind then
			local k, r = KindOf(atlas)
			kind, refused = k, refused or r
		end
	end
	if kind ~= "ore" and kind ~= "herb" and C_QuestLog and Call(C_QuestLog.UnitIsRelatedToActiveQuest, unit) == true then
		kind = "quest"
	end
	return kind, refused or false
end

local WANT = { ore = "ore", herb = "herbs", quest = "questObjects" }

-- "far": out of reach; "ready": in reach; "refused": in reach, and the game says no
local function Reach(unit, refused)
	local inRange = UnitIsInInteractRange and Call(UnitIsInInteractRange, unit)
	if inRange == false then
		return "far"
	end
	if refused then
		return inRange == true and "refused" or "far"
	end
	return "ready"
end

local function PlateFor(unit)
	return C_NamePlate and Call(C_NamePlate.GetNamePlateForUnit, unit)
end

-- the soft target's token and its nameplate (some clients give a world object's plate only under its nameplate
-- token: those shown are asked too)
local function Target()
	if Call(UnitIsGameObject, SOFT_UNIT) ~= true then
		return nil
	end
	local plate = PlateFor(SOFT_UNIT)
	if plate then
		return SOFT_UNIT, plate
	end
	for unit in pairs(S.units) do
		if Call(UnitIsUnit, unit, SOFT_UNIT) == true then
			plate = PlateFor(unit)
			if plate then
				return unit, plate
			end
		end
	end
	return SOFT_UNIT, nil
end

--------------------------------------------------------------------------------
-- The glints
--------------------------------------------------------------------------------

local SPARK = "Interface\\AddOns\\MelloUI\\Media\\FrameFX\\spark_gold.tga"
-- how many, how big (px at the nameplate's scale), how far apart (the ellipse's half width; its height 0.6 of it),
-- how far under the nameplate (on the object), how often the reach is read, the fades (seconds): in, between looks,
-- and how long a new look must hold first (at the edge of reach it flickers), a refusal longer
local G = { COUNT = 7, SIZE = 32, SPREAD = 44, FLAT = 0.6, BELOW = -44, READ = 0.15, FADE_IN = 0.35, BLEND = 0.3,
	HOLD = 0.15, HOLD_REFUSED = 0.6 }

local glints      -- the frame and its glints (made on the first one shown)

local function Twinkle(g, fresh)
	local a, r = math.random() * 2 * math.pi, math.sqrt(math.random())
	g.x, g.y = math.cos(a) * r * G.SPREAD, math.sin(a) * r * G.SPREAD * G.FLAT
	g.life = 0.7 + 0.7 * math.random()
	g.scale = 0.55 + 0.6 * math.random()
	g.spin = (math.random() - 0.5) * 1.6
	g.turn = math.random() * 2 * math.pi
	g.age = fresh and 0 or -0.5 * math.random()
end

local function Toward(v, goal, step)
	if v < goal then
		return math.min(v + step, goal)
	end
	return math.max(v - step, goal)
end

-- a new look shows once it has held a moment
local function Propose(look)
	if look == glints.look then
		glints.next = nil
		return
	end
	local now = GetTime()
	if glints.next ~= look then
		glints.next, glints.since = look, now
	elseif now - glints.since >= (look == "refused" and G.HOLD_REFUSED or G.HOLD) then
		glints.next, glints.look = nil, look
		if look == "ready" then
			for _, g in ipairs(glints.list) do
				Twinkle(g, true)   -- all at once: in reach
			end
		end
	end
end

local Animate = Shared("OnUpdate of the loot sparkles' glints", function(frame, elapsed)
	elapsed = math.min(elapsed, 0.1)
	glints.read = glints.read + elapsed
	if glints.read >= G.READ then
		glints.read = 0
		Propose(Reach(glints.unit, glints.refused))
	end
	glints.shown = Toward(glints.shown, 1, elapsed / G.FADE_IN)
	glints.ready = Toward(glints.ready, glints.look == "ready" and 1 or 0, elapsed / G.BLEND)
	glints.no = Toward(glints.no, glints.look == "refused" and 1 or 0, elapsed / G.BLEND)
	local still = MelloUI.Anim and MelloUI.Anim.reduceMotion
	-- dimmer out of reach, grey and slower when refused
	local light = glints.shown * (0.5 + 0.5 * glints.ready) * (1 - 0.5 * glints.no)
	local speed = still and 0 or (0.8 + 0.4 * glints.ready) * (1 - 0.5 * glints.no)
	local grey = glints.no > 0.5
	for _, g in ipairs(glints.list) do
		g.age = g.age + elapsed * speed
		if g.age >= g.life then
			Twinkle(g)
		end
		local age = still and g.life / 2 or math.max(g.age, 0)
		local shine = (still or g.age > 0) and math.sin(math.pi * age / g.life) or 0
		local tex = g.tex
		tex:SetPoint("CENTER", frame, "CENTER", g.x, g.y + (still and 0 or 9 * age))
		local size = math.max(G.SIZE * g.scale * (0.35 + 0.65 * shine), 0.01)
		tex:SetSize(size, size)
		tex:SetRotation(g.turn + (still and 0 or g.spin * age))
		tex:SetDesaturated(grey)
		tex:SetAlpha(math.min(light * shine, 1))
	end
end, "script")

local function Glints()
	if glints then
		return glints
	end
	local frame = CreateFrame("Frame")
	frame:SetSize(1, 1)
	frame:Hide()
	glints = { frame = frame, list = {}, read = 0, shown = 0, ready = 0, no = 0 }
	for i = 1, G.COUNT do
		local tex = frame:CreateTexture(nil, "OVERLAY")
		tex:SetTexture(SPARK)
		tex:SetBlendMode("ADD")
		tex:SetAlpha(0)
		glints.list[i] = { tex = tex }
	end
	Perf.SetScript(frame, "OnUpdate", Animate)
	return glints
end

local function Release()
	if not (glints and glints.anchor) then
		return
	end
	local frame = glints.frame
	frame:Hide()
	frame:ClearAllPoints()
	frame:SetParent(nil)
	glints.anchor, glints.retarget = nil, nil
end

local function Attach(plate, unit, refused)
	local gl = Glints()
	local frame = gl.frame
	frame:SetParent(plate)
	-- under the nameplate's own parts: its name stays readable
	local ok, level = pcall(plate.GetFrameLevel, plate)
	if ok and type(level) == "number" and not Secret(level) then
		frame:SetFrameLevel(math.max(level - 1, 0))
	end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", plate, "CENTER", 0, G.BELOW)
	frame:SetIgnoreParentAlpha(true)
	gl.anchor, gl.unit, gl.refused, gl.retarget = plate, unit, refused, nil
	gl.look, gl.next = Reach(unit, refused), nil
	gl.ready = gl.look == "ready" and 1 or 0
	gl.no = gl.look == "refused" and 1 or 0
	gl.shown, gl.read = 0, 0
	for _, g in ipairs(gl.list) do
		Twinkle(g)
	end
	frame:Show()
end

-- the soft target now: the nameplate on for an object that sparkles, the glints on it
function Evaluate()
	if not Gathering() then
		Release()
		return
	end
	local unit, plate = Target()
	if not unit then
		Plate(false)
		Release()
		return
	end
	local kind, refused = Classify(unit)
	local db = M.db
	local wanted = kind ~= nil and db[WANT[kind]] == true
	Plate(wanted)
	if not (wanted and plate) then
		-- (no plate yet: just asked for; the glints follow when it comes, NAME_PLATE_UNIT_ADDED)
		Release()
		return
	end
	if glints and glints.anchor == plate and not glints.retarget then
		glints.unit, glints.refused = unit, refused
		Propose(Reach(unit, refused))
	else
		Release()
		Attach(plate, unit, refused)
	end
end

--------------------------------------------------------------------------------
-- Events and switches
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
local EVENTS = { "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
	"PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "CVAR_UPDATE" }
local Listen

local OnEvent = Shared("OnEvent of the loot sparkles", function(_, event, a1, a2)
	if event == "PLAYER_SOFT_INTERACT_CHANGED" then
		-- (a nameplate handed from one object to the next does not show the change by itself)
		if glints and glints.anchor and a1 and a2 and not Secret(a1) and not Secret(a2) and a1 ~= a2 then
			glints.retarget = true
		end
		Evaluate()
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		if type(a1) == "string" and not Secret(a1) then
			S.units[a1] = true
		end
		Evaluate()
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		if type(a1) == "string" and not Secret(a1) then
			S.units[a1] = nil
			if glints and glints.anchor and glints.anchor == PlateFor(a1) then
				Release()
			end
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if S.due then
			Holds()
		end
		if not M.isEnabled then
			Listen(false)   -- (switched off in the fight: its settings given back now, nothing more to hear)
			return
		end
		Evaluate()
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- (the account's synced settings can land after login over ours)
		Holds()
		Evaluate()
	elseif event == "CVAR_UPDATE" then
		if type(a1) == "string" and not Secret(a1) and PRESETS[a1:lower()] and not S.presetDue then
			S.presetDue = true
			C_Timer.After(1, AfterPreset)
		end
	end
end, "event")
Perf.SetScript(events, "OnEvent", OnEvent)

function Listen(on)
	for _, event in ipairs(EVENTS) do
		if on then
			pcall(events.RegisterEvent, events, event)
		else
			events:UnregisterEvent(event)
		end
	end
end

-- (switched on after the login's world: its PLAYER_ENTERING_WORLD replayed, Core's startup)
function M:OnLoginWorld(...)
	MelloUI:ReplayWorld(events, ...)
end

function M:OnEnable(db)
	self.db = db
	Listen(true)
	Holds()
	Evaluate()
end

function M:OnDisable()
	Holds()   -- (isEnabled is false now: every setting given back)
	Release()
	if not S.due then
		Listen(false)
	else
		-- (switched off in a fight: the settings come back at its end)
		for _, event in ipairs(EVENTS) do
			if event ~= "PLAYER_REGEN_ENABLED" then
				events:UnregisterEvent(event)
			end
		end
	end
end

function M:OnSettingChanged()
	Holds()
	Evaluate()
end

-- (for the tests: the parts that decide)
M.KindOf, M.Reach, M.Evaluate = KindOf, Reach, function() Evaluate() end
