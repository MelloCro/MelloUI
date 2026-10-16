--------------------------------------------------------------------------------
-- MelloUI - ConfigPreview
--
-- The Configurator's previews (0.15.0, the rebuild; the user, 2026-09-27/28:
-- "a picker + live preview in the header"): samples of what a page sets,
-- drawn from the settings as they are now, so a change shows before the real
-- frame is looked for. One look, stage F: one engine for every kind of
-- sample -- each kind registered once by its owner, its samples built,
-- dressed and painted through this one registry (MelloUI.ConfigPreview = CP).
--
-- The registry (tables only: nothing is made at load)
--   CP.Register(kind, def) -> true   the def stored; a second Register of a
--       kind is told once (geterrorhandler) and the first one stands
--   CP.Kind(kind) -> def | nil
--   CP.OnDress(kind, fn, opts)   another module's dressing of a kind's
--       samples, fn(sample, pick); opts = { picks = { [pick] = true } (nil:
--       every pick), owner = its module's name (its settings and switch are
--       followed with the def's watch), topics = { bus topics } }. Kept per
--       kind, so it may come before the kind's Register; one fn is kept once
--   CP.Build(kind, parent, pick[, onto]) -> sample | nil   the def's Build
--       only (`onto`: a frame of the caller's to build on)
--   CP.Values(kind, pick[, i]) -> a fresh shallow copy of the pick's i-th
--       (nil: the 1st) made-up values, def.Values(pick, i); or nil
--   CP.Dress(kind, sample, pick)   the def's Dress, then each OnDress fn
--       whose picks hold the pick, each once
--   CP.Paint(kind, sample, pick[, values, ctx])   sample.sample = values when
--       given, then def.Paint(sample, pick, sample.sample, ctx); ctx = { try =
--       { id, value }, state = name, only = fn(j, ind) }, or nil (one shared
--       empty table: nothing made per paint)
--   CP.Update(kind, sample, pick, values)   values only: def.Update, else
--       def.Paint; never a dress or a build
--   CP.Sample(kind, parent, pick[, onto, values, ctx]) -> sample | nil
--       Build, its values (`values`, else CP.Values), Dress, then Paint
--   CP.Make(parent, kind, skin[, opts]) -> preview | nil   nil for a kind that
--       is not registered (nothing made). A 'wide' kind: a designer's stage
--       (the section "The wide stage" below). A 'corner' kind: a Frame def.width x
--       def.height on a flat inner panel, placed by the caller, made on its
--       page's first build, never at login, with
--         preview:SetPick(pick)  one of def.picks (any other: def.first)
--         preview:Refresh()      every part read from the settings again, now
--       skin: the window's shell (Kit:OwnWindow), handed to def.Corner
--   CP.PartLabel(kind, key) -> a part's label (def.PartLabel, or def.keys'
--       string for it), or nil
--   CP.Shown(kind) -> a preview (or a stage) of that kind on show, or nil
-- A def: place ('corner' or 'wide'), width, height, picks (a set), first, watch (a set
-- of module names), Build, Values, Dress, Paint, Update; a corner's also
-- Corner(p, skin) (its parts, made once), Lay(p, pick), OnShow(p), Tip(pick).
--
-- The 'unitframe' kind (at the end of this file, until stage G moves it to
-- its module): the designer's corner sample (the Player, Target, Focus and
-- Pet frames' stage slot) -- picks "player", "target", "focus", "pet",
-- "party", "castbars", "personal" (one look C14: the raid frame is the
-- designer stage's, MelloUI_GroupFrames' 'raidframe' kind); its
-- portrait wears the shell's round kit rim while the shell's look is on --
-- and the party pick's sample, a replica of the game's party member frame
-- (Preview's stand-ins, Group Frames' solo frame, the Designer's party).
--
-- SAMPLE values only: no unit value is read at all. The player's own
-- health, class and name may be secret even out of combat on this client
-- (measured on this client), so every name, class, number and portrait here is
-- made up -- except the Player pick's portrait, which the game's own setter
-- is handed the unit for (SetPortraitTexture(texture, "player"): it returns
-- nothing, and Class Icons' hook on it puts the medallion on as on the real
-- frame). The other portraits: the sample's class medallion while Class
-- Icons' Player Portraits are on (players only: an NPC's portrait is never
-- touched, as on the frames), else the game's portrait of a sample creature
-- (SetPortraitTextureFromCreatureDisplayID, a display id, no unit).
--
-- One system per job: what the bars wear and say comes from the modules that
-- put it on the real frames, through their pure preview exports -- Bar
-- Textures (PreviewTexture, PreviewHealthColor, PreviewPowerColor,
-- PreviewCastColor) and Bar Text (PreviewText, PreviewPlace, PreviewShows);
-- the names' form from Unit Frames' own setting (UnitFrames.nameFormat, which
-- UI Modifications' Show Names As drives, with its Centre Names; the
-- painted skin's name plates centre them while it is on), the
-- medallion from Class Icons (MelloUI:ClassIconPath), the Elite mark from
-- Unit Frames Kit's own export (UnitFramePanel.PreviewCrest: the painted
-- skin's marks). A part whose setting is off is dimmed where the frame would
-- show nothing (the values, the mark), or shows the game's own look where the
-- frame would (the bars' art).
--
-- A preview follows the bus's 'setting' and 'module' (its def's watch and the
-- owners of its OnDress), 'palette' and 'fonts' only while one is on show,
-- one NextFrame per preview however many changes came in a frame; on every
-- show it is read again. No OnUpdate, no ticker, nothing made per refresh.
-- Colours: palette keys (W.Paint) for its own ground, name and edge; the
-- bars' colours are the game's (class, reaction, health, power, cast), as on
-- the real frames.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("ConfigPreview")
local Shared = Perf.Shared
local W = MelloUI.Widgets   -- (Core/Widgets.lua loads before this file)

local Preview = {}
MelloUI.ConfigPreview = Preview

-- the registry's own (the 'Registry' section below): the kinds, the other
-- modules' dressings per kind (kept before its Register too), the kinds told
-- twice, and NONE: the one empty table a paint without a ctx is handed
local Reg = { kinds = {}, dress = {}, told = {}, NONE = {} }

local WIDTH, HEIGHT = 220, 96
local PAD = 8                 -- the parts inside the panel's edge
local GAP = 8                 -- a portrait to its bars
local PORTRAIT = 56           -- the portrait's rim (its picture inside)
local CREST = 20              -- the Elite mark on the portrait's top
local DIM = 0.4               -- a part whose setting is off (a gated row's alpha)
local NAME_TOP, BAR1_TOP, BAR2_TOP = -22, -40, -60   -- the unit layout's lines, below the top
local BAR1_H, BAR2_H = 16, 10

-- the game's own bar art, where the settings leave it on the frame (an atlas
-- where the client has it; else the game's plain bar in the game's colour)
local PLAIN_BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local GAME_HEALTH = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"
-- (0.17.0) its white twin, which Default wears under a health colour (Bar
-- Textures' ColouredDefault: the colour on the green art came out grey-green)
local GAME_HEALTH_WHITE = GAME_HEALTH .. "-Status"
local GAME_CAST = "ui-castingbar-filling-standard"
local NO_PORTRAIT = "Interface\\Icons\\INV_Misc_QuestionMark"   -- (a client without the creature portrait)
local CAST_ICON = "Interface\\Icons\\Spell_Holy_Renew"

-- The samples, one per pick: made-up people and numbers (a first and a last
-- name, as characters here have). layout: how the pick is drawn; area: Bar
-- Textures' area for its bars; frame: Bar Text's frame key (the frames it
-- writes values on); centre: Unit Frames' Centre Names reaches it (its
-- ApplyNames: the player's, the target's and the focus's name, never the
-- pet's); plate: the painted unit frame skin centres it on its name plate
-- (UnitFramePanel's CenterName: those three and a party member's); right:
-- the portrait on the right, as the game's target and focus frames have it;
-- display: a creature's display id for its portrait (players with Class
-- Icons off, NPCs always; this client's own displays: an orc warrior, a
-- night elf rogue, a wolf pup, a human priest). class / reaction / fraction /
-- execute are what BarTextures.PreviewHealthColor reads.
local SAMPLES = {
	player = { layout = "unit", area = "unitframes", frame = "player", centre = true, plate = true, you = true,
		first = "Aldric", last = "Vale", class = "PALADIN", reaction = 5,
		health = 8640, max = 12000, power = 5200, powerMax = 6400, token = "MANA",
		label = "Your player frame" },
	target = { layout = "unit", area = "unitframes", frame = "target", centre = true, plate = true, right = true, elite = true,
		first = "Garra", last = "Blackthorn", reaction = 2, execute = true, display = 146966,
		health = 1740, max = 12000, power = 35, powerMax = 100, token = "RAGE",
		label = "The target frame, an elite enemy low on health" },
	focus = { layout = "unit", area = "unitframes", frame = "focus", centre = true, plate = true, right = true,
		first = "Seren", last = "Ashby", class = "ROGUE", reaction = 2, execute = true, display = 147598,
		health = 6200, max = 9800, power = 80, powerMax = 100, token = "ENERGY",
		label = "The focus frame, an enemy player" },
	pet = { layout = "unit", area = "unitframes",
		first = "Ember", last = "Ashpaw", reaction = 5, display = 145568,
		health = 3100, max = 4200, power = 60, powerMax = 100, token = "FOCUS",
		label = "Your pet's frame" },
	party = { layout = "unit", area = "unitframes", plate = true,
		first = "Lina", last = "Brightwater", class = "PRIEST", reaction = 5, display = 147599,
		health = 7900, max = 8800, power = 4100, powerMax = 7000, token = "MANA",
		level = 24,   -- (the party members' level: Unit Frames' on the name line, one-look D5; the painted skin's circle)
		label = "A party member's frame" },
	castbars = { layout = "cast", area = "castbars", spell = "Renew", fraction = 0.62, time = "0.9",
		label = "Your cast bar" },
	personal = { layout = "personal", area = "personal", reaction = 5,
		health = 8640, max = 12000, power = 5200, powerMax = 6400, token = "MANA",
		label = "The personal resource display" },
}
local FIRST_PICK = "player"
-- a health sample's fraction, for the colour (the cast's is its progress)
for _, s in pairs(SAMPLES) do
	if s.health then
		s.fraction = s.health / s.max
	end
end

-- the modules whose settings the preview shows (the bus's 'setting' and
-- 'module' for any other are passed over)
local WATCH = { BarTextures = true, BarText = true, UnitFrames = true, ClassIcons = true, UnitFramePanel = true,
	UIModifications = true }

local weakKeys = { __mode = "k" }

--------------------------------------------------------------------------------
-- Reads (settings only: never a unit)
--------------------------------------------------------------------------------

-- a module that is loaded and running, or nil
local function Running(name)
	local m = MelloUI:GetModule(name)
	return (m and m.isEnabled and m.db) and m or nil
end

-- a module whose preview exports are there (its settings read, on or off)
local function Exports(name, fn)
	local m = MelloUI:GetModule(name)
	return (m and m.db and type(m[fn]) == "function") and m or nil
end

-- the name in the form the frames show it: Unit Frames' own copy of Show
-- Names As (the game's full name while that module is off)
local function NameAs(s)
	local uf = Running("UnitFrames")
	local mode = uf and uf.db.nameFormat or "both"
	if mode == "first" then
		return s.first
	elseif mode == "last" then
		return s.last or s.first
	elseif s.last and mode == "initial" then
		return s.first:sub(1, 1) .. ". " .. s.last
	elseif s.last and mode == "firstinitial" then
		return s.first .. " " .. s.last:sub(1, 1) .. "."
	end
	return s.last and (s.first .. " " .. s.last) or s.first
end

-- is an atlas known to this client? (asked once per name)
local atlasKnown = {}
local function Atlas(name)
	if not name then
		return false
	end
	local known = atlasKnown[name]
	if known == nil then
		known = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) and true or false
		atlasKnown[name] = known
	end
	return known
end

--------------------------------------------------------------------------------
-- Painting the bars
--------------------------------------------------------------------------------

-- a bar's picture: the chosen texture; else the game's own art -- `atlas`
-- where the client has it (true: the art carries its colour), else `file`
-- or the game's plain bar
local function Picture(bar, texture, atlas, file)
	if texture then
		bar:SetStatusBarTexture(texture)
		return false
	end
	if Atlas(atlas) then
		bar:SetStatusBarTexture(atlas)
		return true
	end
	bar:SetStatusBarTexture(file or PLAIN_BAR)
	return false
end

-- (a bar that shows its art's own colour)
local function White(bar)
	bar:SetStatusBarColor(1, 1, 1)
end

local function Fill(bar, value, max)
	bar:SetMinMaxValues(0, max)
	bar:SetValue(value)
end

-- the health bar of a unit or the personal display
local function PaintHealth(bar, s, BT)
	local texture, active = BT.PreviewTexture(s.area)
	if s.layout == "personal" then
		Picture(bar, texture)
		bar:SetStatusBarColor(BT.PreviewHealthColor("green", s))
	else
		local white = active and BT.db.healthColor ~= "green" and Atlas(GAME_HEALTH_WHITE)
		local coloured = Picture(bar, texture, white and GAME_HEALTH_WHITE or GAME_HEALTH)
		if s.healthAtlas then
			-- (a party member's replica: the party frame's own bar art, and
			-- its white twin under a health colour)
			local twin = s.healthAtlas .. "-Status"
			coloured = Picture(bar, texture, (active and BT.db.healthColor ~= "green" and Atlas(twin)) and twin
				or s.healthAtlas)
		end
		if active then
			-- the module colours the unit frames' health, the game's art too
			bar:SetStatusBarColor(BT.PreviewHealthColor(nil, s))
		elseif coloured then
			White(bar)
		else
			bar:SetStatusBarColor(BT.PreviewHealthColor("green", s))
		end
	end
	Fill(bar, s.health, s.max)
end

local function PaintPower(bar, s, BT)
	local texture = BT.PreviewTexture(s.area)
	local r, g, b, atlas = BT.PreviewPowerColor(s.token)
	-- a flat texture takes the power's colour (RecolorManaBar); the game's
	-- own art carries it
	if Picture(bar, texture, atlas) then
		White(bar)
	else
		bar:SetStatusBarColor(r, g, b)
	end
	Fill(bar, s.power, s.powerMax)
end

local function PaintCast(bar, s, BT)
	local texture, active = BT.PreviewTexture(s.area)
	-- the module colours a cast on any art (RecolorCastBar); the game's own
	-- art carries its colour
	if Picture(bar, texture, GAME_CAST) and not active then
		White(bar)
	else
		bar:SetStatusBarColor(BT.PreviewCastColor())
	end
	Fill(bar, s.fraction, 1)
end

-- a value on a bar, as Bar Text writes and places it; dimmed while the
-- frame would show none
local function PaintValue(fs, bar, frame, power, value, max)
	local BX = Exports("BarText", "PreviewText")
	local text = BX and BX.PreviewText(value, max)
	if not (frame and text) then
		fs:Hide()
		return
	end
	BX.PreviewPlace(fs, bar)
	fs:SetText(text)
	fs:SetAlpha(BX.PreviewShows(frame, power) and 1 or DIM)
	fs:Show()
end

--------------------------------------------------------------------------------
-- The portrait and the Elite mark
--------------------------------------------------------------------------------

-- the kit's round rim on the portrait (a shell's dressing: handed the kit)
local function KitRim(Kit, p)
	p.portrait:SetKit(Kit)
end

local previews = setmetatable({}, weakKeys)   -- [preview] = true

-- a shell switched its look: its previews' rims follow (one shared fn)
local function OnShellKit(shell, on)
	for p in pairs(previews) do
		if p.skin == shell then
			if on then
				shell:Kit(KitRim, p)
			else
				p.portrait:SetKit(false)
			end
		end
	end
end

-- (a portrait is drawn again only when what it shows changes -- not for
-- every value a slider passes -- and on every show: OnShow forgets it)
local function PaintPortrait(p, s)
	local tex = p.portrait.icon
	local ci = Running("ClassIcons")
	local medallions = ci and ci.db.portraits and true or false
	local medallion = medallions and s.class and MelloUI:ClassIconPath(s.class) or nil
	local want = s.you and (medallions and "you, medallion" or "you") or medallion or s.display or NO_PORTRAIT
	if p.portraitShows == want then
		return
	end
	p.portraitShows = want
	tex:SetTexCoord(0, 1, 0, 1)
	-- the game's own portrait of the player (and Class Icons' medallion on
	-- it, through its hook): a setter handed the unit, nothing read
	if s.you and type(SetPortraitTexture) == "function" and pcall(SetPortraitTexture, tex, "player") then
		return
	end
	if medallion then
		tex:SetTexture(medallion)
	elseif s.display and type(_G.SetPortraitTextureFromCreatureDisplayID) == "function"
		and pcall(_G.SetPortraitTextureFromCreatureDisplayID, tex, s.display) then
		return
	else
		tex:SetTexture(NO_PORTRAIT)
		tex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	end
end

-- the Elite mark: Unit Frames Kit's to put on (its PreviewCrest export:
-- shown while the unit frames wear the painted skin, the marks living on its
-- ring, dimmed with the marks off); hidden here when that module or its
-- export is not there, or it shows none
local function PaintCrest(p, s)
	local crest = p.crest
	local ufp = Exports("UnitFramePanel", "PreviewCrest")
	if not (ufp and ufp.PreviewCrest(crest, s.elite and true or false)) then
		crest:Hide()
	end
end

--------------------------------------------------------------------------------
-- Layout (a pick's parts where they go; made once, moved per pick)
--------------------------------------------------------------------------------

local function Lay(p)
	local s = SAMPLES[p.pick]
	local portrait, crest, name, bar1, bar2 = p.portrait, p.crest, p.name, p.bar1, p.bar2
	local layout = s.layout
	portrait:SetShown(layout == "unit")
	crest:Hide()
	name:SetShown(layout == "unit")
	bar2:SetShown(layout == "unit" or layout == "personal")
	p.icon:SetShown(layout == "cast")
	p.castText:SetShown(layout == "cast")
	p.castTime:SetShown(layout == "cast")
	p.text1:Hide()
	p.text2:Hide()
	bar1:ClearAllPoints()
	bar2:ClearAllPoints()
	name:ClearAllPoints()
	if layout == "unit" then
		local w = WIDTH - 2 * PAD - PORTRAIT - GAP
		local x = s.right and PAD or (PAD + PORTRAIT + GAP)
		portrait:ClearAllPoints()
		if s.right then
			portrait:SetPoint("RIGHT", p, "RIGHT", -PAD, 0)
		else
			portrait:SetPoint("LEFT", p, "LEFT", PAD, 0)
		end
		name:SetPoint("TOPLEFT", p, "TOPLEFT", x, NAME_TOP)
		name:SetWidth(w)
		bar1:SetSize(w, BAR1_H)
		bar1:SetPoint("TOPLEFT", p, "TOPLEFT", x, BAR1_TOP)
		bar2:SetSize(w, BAR2_H)
		bar2:SetPoint("TOPLEFT", p, "TOPLEFT", x, BAR2_TOP)
	elseif layout == "cast" then
		p.icon:ClearAllPoints()
		p.icon:SetPoint("LEFT", p, "LEFT", 16, 0)
		bar1:SetSize(160, 18)
		bar1:SetPoint("LEFT", p.icon, "RIGHT", 4, 0)
	else   -- personal
		bar1:SetSize(150, BAR2_H)
		bar1:SetPoint("CENTER", p, "CENTER", 0, 5)
		bar2:SetSize(150, 6)
		bar2:SetPoint("TOP", bar1, "BOTTOM", 0, -3)
	end
end

--------------------------------------------------------------------------------
-- The unit frame preview's paint (the 'unitframe' kind's corner: its def's
-- Paint, below)
--------------------------------------------------------------------------------

local function PaintCorner(p)
	local s = SAMPLES[p.pick]
	local BT = Exports("BarTextures", "PreviewHealthColor")
	if s.layout == "unit" then
		PaintPortrait(p, s)
		PaintCrest(p, s)
		-- centred as the frame's name is: on its plate while the painted skin
		-- is on (Unit Frames' Centre Names then leaves the names to it), else
		-- by Centre Names where it reaches
		local uf = Running("UnitFrames")
		local centred = (s.plate and Running("UnitFramePanel")) or (s.centre and uf and uf.isEnabled)
		p.name:SetJustifyH(centred and "CENTER" or "LEFT")
		p.name:SetText(NameAs(s))
	end
	if BT then
		if s.layout == "cast" then
			PaintCast(p.bar1, s, BT)
		else
			PaintHealth(p.bar1, s, BT)
			if s.token then
				PaintPower(p.bar2, s, BT)
			end
		end
	end
	if s.frame then
		PaintValue(p.text1, p.bar1, s.frame, false, s.health, s.max)
		PaintValue(p.text2, p.bar2, s.frame, true, s.power, s.powerMax)
	end
end

--------------------------------------------------------------------------------
-- The registry (one look, stage F: every kind of sample the configurator
-- draws, registered once by its owner; tables only, nothing made at load)
--------------------------------------------------------------------------------

-- (a second Register of a kind is a mistake: told once, the first stands)
function Preview.Register(kind, def)
	if type(kind) ~= "string" or type(def) ~= "table" then
		return false
	end
	if Reg.kinds[kind] then
		if not Reg.told[kind] then
			Reg.told[kind] = true
			geterrorhandler()("MelloUI.ConfigPreview: the kind '" .. kind .. "' was registered twice (the first stands)")
		end
		return false
	end
	Reg.kinds[kind] = def
	return true
end

function Preview.Kind(kind)
	return Reg.kinds[kind]
end

-- another module's dressing of a kind's samples, kept per kind (before its
-- Register too); the same fn handed again takes the new opts, still once
function Preview.OnDress(kind, fn, opts)
	if type(kind) ~= "string" or type(fn) ~= "function" then
		return false
	end
	opts = type(opts) == "table" and opts or Reg.NONE
	local list = Reg.dress[kind]
	if not list then
		list = {}
		Reg.dress[kind] = list
	end
	local entry
	for i = 1, #list do
		if list[i].fn == fn then
			entry = list[i]
		end
	end
	if not entry then
		entry = { fn = fn }
		list[#list + 1] = entry
	end
	entry.picks = type(opts.picks) == "table" and opts.picks or nil
	entry.owner = type(opts.owner) == "string" and opts.owner or nil
	entry.topics = type(opts.topics) == "table" and opts.topics or nil
	return true
end

function Preview.Build(kind, parent, pick, onto)
	local def = Reg.kinds[kind]
	if not (def and def.Build) then
		return nil
	end
	return def.Build(parent, pick, onto)
end

function Preview.Values(kind, pick, i)
	local def = Reg.kinds[kind]
	local from = def and def.Values and def.Values(pick, i or 1)
	if type(from) ~= "table" then
		return nil
	end
	local s = {}
	for k, v in pairs(from) do
		s[k] = v
	end
	return s
end

-- the def's own dressing, then the other modules' for this pick (each fn
-- once; one that fails is told, the rest still dress)
function Preview.Dress(kind, sample, pick)
	local def = Reg.kinds[kind]
	if not (def and sample) then
		return
	end
	if def.Dress then
		def.Dress(sample, pick)
	end
	local list = Reg.dress[kind]
	for i = 1, list and #list or 0 do
		local d = list[i]
		if not d.picks or d.picks[pick] then
			local ok, err = pcall(d.fn, sample, pick)
			if not ok then
				geterrorhandler()(err)
			end
		end
	end
end

function Preview.Paint(kind, sample, pick, values, ctx)
	local def = Reg.kinds[kind]
	if not (def and def.Paint and sample) then
		return
	end
	if values then
		sample.sample = values
	end
	def.Paint(sample, pick, sample.sample, ctx or Reg.NONE)
end

function Preview.Update(kind, sample, pick, values)
	local def = Reg.kinds[kind]
	local paint = def and (def.Update or def.Paint)
	if not (paint and sample) then
		return
	end
	if values then
		sample.sample = values
	end
	paint(sample, pick, sample.sample, Reg.NONE)
end

function Preview.Sample(kind, parent, pick, onto, values, ctx)
	local f = Preview.Build(kind, parent, pick, onto)
	if type(f) ~= "table" then
		return nil
	end
	f.sample = values or Preview.Values(kind, pick)
	Preview.Dress(kind, f, pick)
	Preview.Paint(kind, f, pick, nil, ctx)
	return f
end

function Preview.PartLabel(kind, key)
	local def = Reg.kinds[kind]
	if not def or key == nil then
		return nil
	end
	if def.PartLabel then
		return def.PartLabel(key)
	end
	local label = type(def.keys) == "table" and def.keys[key]
	return type(label) == "string" and label or nil
end

-- does a kind follow this module's settings and switch? (its def's watch, or
-- a module that dresses its samples)
function Reg.Watches(kind, name)
	local def = Reg.kinds[kind]
	if def and def.watch and def.watch[name] then
		return true
	end
	local list = Reg.dress[kind]
	for i = 1, list and #list or 0 do
		if list[i].owner == name then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- A corner preview's methods (its def's Lay and Paint)
--------------------------------------------------------------------------------

local function Refresh(p)
	Preview.Paint(p.kind, p, p.pick)
end

-- (a hidden preview is read on its show)
local function SetPick(p, pick)
	local def = Reg.kinds[p.kind]
	p.pick = def.picks[pick] and pick or def.first
	if def.Lay then
		def.Lay(p, p.pick)
	end
	if p:IsVisible() then
		Refresh(p)
	end
end

--------------------------------------------------------------------------------
-- Following the settings while on show
--------------------------------------------------------------------------------

local shown = setmetatable({}, weakKeys)   -- [preview] = true while on show
local nShown = 0

-- the frame after the changes: read again if still on show
local function Later(p)
	if p:IsVisible() then
		Refresh(p)
	end
end

-- each preview on show read again on the next frame: one NextFrame each, its
-- key the preview, however many changes came in a frame; `name`: only the
-- previews whose kind follows that module. MelloUI.Schedule where there is
-- one, else the Kit's: looked up at each call, never kept
function Reg.Ask(name)
	local S = MelloUI.Schedule or MelloUI.Kit
	for p in pairs(shown) do
		if not name or Reg.Watches(p.kind, name) then
			S:NextFrame(p, Later)
		end
	end
end

-- 'palette' and 'fonts': every preview
local function AskAll()
	Reg.Ask(nil)
end

-- 'setting' (module, key, value) and 'module' (name, enabled)
local function OnSetting(name)
	if type(name) == "string" then
		Reg.Ask(name)
	end
end

local OnShow = Shared("OnShow on the Configurator's preview", function(p)
	if not shown[p] then
		shown[p] = true
		nShown = nShown + 1
		if nShown == 1 then
			MelloUI:On("setting", OnSetting, Preview)
			MelloUI:On("module", OnSetting, Preview)
			MelloUI:On("palette", AskAll, Preview)
			MelloUI:On("fonts", AskAll, Preview)
		end
	end
	-- (a change made while it was hidden reached no listener: read again,
	-- with what its def forgets on a show -- the unit frame's portrait)
	local def = Reg.kinds[p.kind]
	if def and def.OnShow then
		def.OnShow(p)
	end
	Refresh(p)
end, "script")

local OnHide = Shared("OnHide on the Configurator's preview", function(p)
	if shown[p] then
		shown[p] = nil
		nShown = nShown - 1
		if nShown == 0 then
			MelloUI:Off(Preview)
		end
	end
end, "script")

local OnEnter = Shared("OnEnter on the Configurator's preview (tooltip)", function(p)
	local def = Reg.kinds[p.kind]
	local tip = def and def.Tip and def.Tip(p.pick)
	if tip then
		W.ShowTooltip(p, "Preview", tip)
	end
end, "script")

-- a preview of the kind on show, else a stage of it (nil: none)
function Preview.Shown(kind)
	for p in pairs(shown) do
		if p.kind == kind then
			return p
		end
	end
	return Reg.ShownStage and Reg.ShownStage(kind) or nil
end

--------------------------------------------------------------------------------
-- Make
--------------------------------------------------------------------------------

local function Bar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetMinMaxValues(0, 1)
	bar:SetStatusBarTexture(PLAIN_BAR)
	return bar
end

-- a corner preview: its frame on a flat inner panel, its def's parts on it
local function MakeCorner(parent, kind, def, skin)
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(def.width or WIDTH, def.height or HEIGHT)
	W.Panel(p, { on = true })
	p.kind, p.skin = kind, skin
	p.SetPick, p.Refresh = SetPick, Refresh
	def.Corner(p, skin)
	p:EnableMouse(true)
	p:SetScript("OnShow", OnShow)
	p:SetScript("OnHide", OnHide)
	p:SetScript("OnEnter", OnEnter)
	p:SetScript("OnLeave", W.TipLeave)
	p.pick = def.first
	if def.Lay then
		def.Lay(p, p.pick)
	end
	if p:IsVisible() then
		OnShow(p)   -- (made on show: no OnShow comes)
	end
	return p
end

-- (a wide stage: below, "The wide stage")
function Preview.Make(parent, kind, skin, opts)
	local def = parent and Reg.kinds[kind]
	if def and def.place == "corner" and def.Corner then
		return MakeCorner(parent, kind, def, skin)
	end
	if def and def.place == "wide" and Reg.MakeStage then
		return Reg.MakeStage(parent, kind, def, skin, opts)
	end
	return nil
end

--------------------------------------------------------------------------------
-- The wide stage (one look C6: F-v3's F2 and the shell plan's 6.1): a
-- designer's one interactive sample -- its parts picked, dragged, put on a
-- spot with a '+', sized with the wheel, nudged with the arrow keys and
-- right-clicked for what they show. One engine for every wide kind (C10's
-- raid frames the first); proven on a test kind until a page hosts one.
--   CP.Make(parent, kind, skin, opts) -> stage   a def with place 'wide':
--       opts = { width, x, y0 (its place on `anchor`, `parent` when nil,
--       pinned from y0 down: Stick), anchor, scroll (the page's ScrollFrame),
--       onSelect(stage, key | nil), onPick(stage, pick), dim(stage) -> nil |
--       the reason it sleeps }
--   CP.PartKeys(kind[, pick]) -> the def's PartKeys(pick): the parts with no
--       sample and no stage (the Parts line, the search index)
--   CP.RowEnter(row) / CP.RowLeave(row)   row.melloOutline = { kind = ...,
--       key = ... }: that part outlined on the kind's stage on show
-- A wide def: height, picks, first, watch, topics (bus topics that repaint),
--   maxScale (3), Furnish(stage, holder, w, h) (its furniture, laid once),
--   Main(stage, pick) -> the sample (built once per pick), Room(stage) ->
--   left, top, w, h (the sample's room; the stage less PAD when absent),
--   Refresh(stage, ctx) (the furniture painted after the sample),
--   parts(pick, sample) -> { part, ... }, PartKeys(pick), states ({ { key,
--   label } }: chips), Tries(id) -> true, Empty(pick) -> a caption,
--   Moved(pick) -> n, ResetAll(pick), mover(pick) -> a mover key, reset ({ {
--   module, key } }: Wants), Panel(class, stage, parent, y) -> frame, height,
--   OnSelect(stage, key) (a part picked or let go: the kind's own followers)
-- The page sets stage.pinAbove (what it pins over the stage, px) for Stick.
-- A part: key, label, class, region(sample) -> region | nil (none: no hit,
--   no outline), box(sample) (the frame its place is on: the sample when
--   absent), text (a font string: its string on its justify side is what
--   shows), justify, spots and plus (the spots it may take and the '+' marks
--   it shows: the nine when absent), scale (1: its offsets in its own units),
--   range (60), hysteresis (a text's columns: max(12, box width / 5)),
--   store = { get(part) -> place | nil, set(part, place | nil) } (nil: back
--   to its default), home(part) -> place, homeLabel, size = { min, max, step
--   }, hide (Show / Hide offered), locked (the reason: picked, never moved),
--   drag (false: picked, never moved), content = { values = { { value,
--   label } }, get(), set(value) }, Drop(part, l, b, r, t, w, h, place,
--   spot) -> place (the box's units; `spot`: the place for that '+').
-- A place: { point, x, y, size, show } -- exactly ONE store write a gesture,
-- inside one MelloUI:Batch, seeded from home when the part has none yet.
-- The def's Paint lays every part from its store on every paint (a drag moves
-- the region and puts it back); a store that moves secure frames waits for
-- the fight's end itself. stage:PartSpec's builders make their frames on each
-- call: the page builds each part's block once and keeps it.
-- No unit is read; the keys are borrowed (MelloUI:LendKeyboard), never taken.
--------------------------------------------------------------------------------

do
	local K = { HEIGHT = 214, PAD = 8, CLICK = 3, H_TEXT = 12, H = 4, RANGE = 60, MAGNET = 2, GHOST = 0.35,
		DIM = 0.4, LIFT = 40, PLUS = 14, MAX_SCALE = 3, ROW_H = 26, LABEL_W = 110 }
	local TEXT = {
		pick = "Click a part to pick it; drag it to move it.",
		gestures = "Drag to move it, click a + for a spot, the arrow keys move it 1 px (Shift: 10).",
		size = " The wheel sizes it (%s).",
		menu = " Right-click it for more.",
		place = "%s %d, %d",
		noKeys = " The arrow keys are not free now (a fight, or Edit Layout open).",
		show = "Show", hide = "Hide", home = "Default place", x = "X", y = "Y", placeRow = "Place",
		resetAsk = "Put the %d moved parts back in their places?",
		resetAccept = "Reset", cancel = "Cancel",
		nothing = "Nothing to reset: every part is in its place.",
	}
	K.NINE = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
	K.COL = { TOPLEFT = "LEFT", LEFT = "LEFT", BOTTOMLEFT = "LEFT", TOP = "CENTER", CENTER = "CENTER",
		BOTTOM = "CENTER", TOPRIGHT = "RIGHT", RIGHT = "RIGHT", BOTTOMRIGHT = "RIGHT" }
	K.ROW = { TOPLEFT = "TOP", TOP = "TOP", TOPRIGHT = "TOP", LEFT = "MIDDLE", CENTER = "MIDDLE", RIGHT = "MIDDLE",
		BOTTOMLEFT = "BOTTOM", BOTTOM = "BOTTOM", BOTTOMRIGHT = "BOTTOM" }
	K.FX = { LEFT = 0, CENTER = 0.5, RIGHT = 1 }
	K.FY = { BOTTOM = 0, MIDDLE = 0.5, TOP = 1 }
	K.ARROW = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
	K.MENU_SHOW, K.MENU_HIDE, K.MENU_HOME = "\001show", "\001hide", "\001home"
	local Safe = MelloUI.Safe
	local Num, Fin = Safe.Number, Safe.Finite
	-- (the engine's functions, one table: the file's main chunk keeps its locals)
	local E = {}

	-- the engine's own: the stages on show, the drag under way (one at a
	-- time), the stage the keys are lent to, the one to lend them back to
	-- after a fight, the one event frame and the topic listeners (each made
	-- once)
	local ST = { shown = setmetatable({}, weakKeys), nShown = 0, drag = nil, lent = nil, relend = nil,
		dragger = nil, events = nil, topicFns = {}, EMPTY = {} }

	-- (MelloUI.Schedule where there is one, else the Kit's: looked up at each call)
	function E.Sched()
		return MelloUI.Schedule or MelloUI.Kit
	end

	function E.SpotOf(col, row)
		if row == "MIDDLE" then
			return col == "CENTER" and "CENTER" or col
		end
		return col == "CENTER" and row or row .. col
	end

	function E.Round(v)
		return math.floor(v + 0.5)
	end

	function E.Has(list, v)
		for i = 1, #list do
			if list[i] == v then
				return true
			end
		end
		return false
	end

	-- a part's place now: its store's, else its home (nil: none)
	function E.Current(part)
		local t = part.store and part.store.get and part.store.get(part)
		if t == nil and part.home then
			t = part.home(part)
		end
		return type(t) == "table" and t or nil
	end

	-- the place a write gives: the current one (its home's when it has none)
	-- with `changes` over it
	function E.With(part, changes)
		local t = {}
		for k, v in pairs(E.Current(part) or ST.EMPTY) do
			t[k] = v
		end
		for k, v in pairs(changes) do
			t[k] = v
		end
		return t
	end

	-- `region`'s edges on the screen, a text part's narrowed to its string on
	-- its justify side (nil: not readable)
	function E.Visible(part, region)
		local l, b, r, t = Safe.ScreenRect(region)
		if not l then
			return nil
		end
		if part.text then
			local sw = Fin(Safe.Call(region, "GetStringWidth"))
			local s = Num(Safe.Call(region, "GetEffectiveScale"))
			if sw and s and sw * s < r - l then
				sw = sw * s
				local j = part.justify or Safe.Call(region, "GetJustifyH") or "LEFT"
				if j == "RIGHT" then
					l = r - sw
				elseif j == "CENTER" then
					local m = (l + r) / 2
					l, r = m - sw / 2, m + sw / 2
				else
					r = l + sw
				end
			end
		end
		return l, b, r, t
	end

	-- screen edges in `box`'s units, from its bottom left; and the box's size
	function E.InBox(box, l, b, r, t)
		local bl, bb, br, bt = Safe.ScreenRect(box)
		local s = Num(Safe.Call(box, "GetEffectiveScale"))
		if not (bl and s and s > 0) then
			return nil
		end
		return (l - bl) / s, (b - bb) / s, (r - bl) / s, (t - bb) / s, (br - bl) / s, (bt - bb) / s
	end

	-- the column or row nearest, the current one kept until another is nearer
	-- by more than `h`
	function E.Nearest(options, current, offsetOf, h)
		local best, bestD
		for i = 1, #options do
			local d = math.abs(offsetOf(options[i]))
			if not bestD or d < bestD then
				best, bestD = options[i], d
			end
		end
		if current and best ~= current then
			local ok = false
			for i = 1, #options do
				ok = ok or options[i] == current
			end
			if ok and bestD >= math.abs(offsetOf(current)) - h then
				return current
			end
		end
		return best
	end

	-- the place a part dropped at l, b, r, t (its box's units; the box w x h)
	-- takes: the column and the row each nearest on their own (F-v3's rule),
	-- the offset in the part's units, rounded, in its range, 0 within the
	-- magnet; `keep`: the current spot kept (Shift), only the offset changed
	do
		local cols, rows = {}, {}
		local dl, db, dr, dt, dw, dh   -- (the rect the offsets read, set per drop)
		local function DX(col)
			local f = K.FX[col]
			return dl + f * (dr - dl) - f * dw
		end
		local function DY(row)
			local f = K.FY[row]
			return db + f * (dt - db) - f * dh
		end
		local function Clamp(v, range)
			v = E.Round(v)
			if math.abs(v) <= K.MAGNET then
				return 0
			end
			return math.max(-range, math.min(range, v))
		end
		function E.Drop(part, l, b, r, t, w, h, cur, keep)
			dl, db, dr, dt, dw, dh = l, b, r, t, w, h
			local spots = part.spots or K.NINE
			local at = cur and cur.point
			local col, row
			if keep and at and K.COL[at] then
				col, row = K.COL[at], K.ROW[at]
			else
				wipe(cols)
				for i = 1, #spots do
					local c = K.COL[spots[i]]
					if c and not E.Has(cols, c) then
						cols[#cols + 1] = c
					end
				end
				local hc = part.hysteresis or (part.text and math.max(K.H_TEXT, math.floor(w / 5))) or K.H
				col = E.Nearest(cols, at and K.COL[at], DX, hc)
				wipe(rows)
				for i = 1, #spots do
					if K.COL[spots[i]] == col and not E.Has(rows, K.ROW[spots[i]]) then
						rows[#rows + 1] = K.ROW[spots[i]]
					end
				end
				row = E.Nearest(rows, at and K.COL[at] == col and K.ROW[at] or nil, DY, K.H)
			end
			if not (col and row) then
				return nil
			end
			local s, range = part.scale or 1, part.range or K.RANGE
			return E.SpotOf(col, row), Clamp(DX(col) / s, range), Clamp(DY(row) / s, range)
		end
	end

	-- one write a gesture: the store's set inside one Batch; the stage
	-- painted again on the next frame
	function E.Write(stage, part, t)
		if not (part.store and part.store.set) then
			return
		end
		MelloUI:Batch(part.store.set, part, t)
		stage:Repaint()
	end

	----------------------------------------------------------------------
	-- Painting and the parts' hit frames (after each paint, never per frame)
	----------------------------------------------------------------------

	function E.BoxOf(part, sample)
		return part.box and part.box(sample) or sample
	end

	-- the sample in its room, as big as fits (to maxScale), again when its
	-- size changed
	function E.Fit(stage)
		local main, def = stage.main, stage.def
		local w, h = Fin(Safe.Call(main, "GetWidth")), Fin(Safe.Call(main, "GetHeight"))
		if not (w and h and w > 0 and h > 0) then
			return
		end
		local left, top, rw, rh
		if def.Room then
			left, top, rw, rh = def.Room(stage)
		end
		if not (rw and rh) then
			left, top = K.PAD, K.PAD
			rw = (Fin(stage:GetWidth()) or 0) - 2 * K.PAD
			rh = (Fin(stage:GetHeight()) or 0) - 2 * K.PAD
		end
		local scale = math.max(0.25, math.min(def.maxScale or K.MAX_SCALE, rw / w, rh / h))
		if scale ~= stage.fitScale or left ~= stage.fitLeft or top ~= stage.fitTop then
			stage.fitScale, stage.fitLeft, stage.fitTop = scale, left, top
			main:SetScale(scale)
			main:ClearAllPoints()
			main:SetPoint("CENTER", stage, "TOPLEFT", (left + rw / 2) / scale, -(top + rh / 2) / scale)
		end
	end

	function E.HideFrom(list, from)
		for i = from, #list do
			list[i]:Hide()
		end
	end

	-- the screen edges l, b, r, t on `frame` (TOPLEFT at its bottom left + x, y)
	function E.PlaceOn(frame, stage, l, b, r, t)
		local sl, sb = Safe.ScreenRect(stage)
		local s = Num(stage:GetEffectiveScale())
		if not (sl and s and s > 0) then
			return false
		end
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", (l - sl) / s, (t - sb) / s)
		frame:SetSize(math.max(1, (r - l) / s), math.max(1, (t - b) / s))
		return true
	end

	function E.NewHit(stage, i)
		local hit = CreateFrame("Button", nil, stage)
		hit.stage = stage
		hit:SetScript("OnMouseDown", E.HitDown)
		hit:SetScript("OnMouseUp", E.HitUp)
		hit:SetScript("OnEnter", E.HitEnter)
		hit:SetScript("OnLeave", E.HitLeave)
		hit:SetScript("OnMouseWheel", E.HitWheel)
		stage.hits[i] = hit
		return hit
	end

	function E.NewMark(stage, i)
		local mark = CreateFrame("Button", nil, stage)
		mark.stage = stage
		mark:SetSize(K.PLUS, K.PLUS)
		mark.tex = mark:CreateTexture(nil, "OVERLAY")
		mark.tex:SetAllPoints(mark)
		W.PlusMark(mark.tex, K.PLUS, false)
		mark:SetScript("OnClick", E.MarkClick)
		mark:SetScript("OnEnter", E.MarkEnter)
		mark:SetScript("OnLeave", E.MarkLeave)
		stage.marks[i] = mark
		return mark
	end

	-- the '+' marks of the picked part on its box: its free spots, or while
	-- it is dragged the spots it may take (dots: not clicked)
	function E.Marks(stage)
		local part = stage:Selected()
		local n = 0
		if part and not part.locked and part.drag ~= false and stage.main and not stage.dim then
			local box = E.BoxOf(part, stage.main)
			local bl, bb, br, bt = Safe.ScreenRect(box)
			local cur = E.Current(part)
			local list = stage.dragging and (part.spots or K.NINE) or (part.plus or part.spots or K.NINE)
			for i = 1, bl and #list or 0 do
				local spot = list[i]
				if K.FX[K.COL[spot]] and (stage.dragging or not (cur and cur.point == spot)) then
					n = n + 1
					local mark = stage.marks[n] or E.NewMark(stage, n)
					local x, y = bl + K.FX[K.COL[spot]] * (br - bl), bb + K.FY[K.ROW[spot]] * (bt - bb)
					local s = Num(stage:GetEffectiveScale()) or 1
					local half = K.PLUS / 2 * s
					E.PlaceOn(mark, stage, x - half, y - half, x + half, y + half)
					mark.spot = spot
					mark:SetFrameLevel(stage.level + 30)
					mark:EnableMouse(not stage.dragging)
					mark:Show()
				end
			end
		end
		E.HideFrom(stage.marks, n + 1)
	end

	function E.ByArea(a, b)
		return a.area > b.area
	end

	function E.Outline(stage, box, hit)
		if hit and hit:IsShown() then
			box:ClearAllPoints()
			box:SetAllPoints(hit)
			box:Show()
		else
			box:Hide()
		end
	end

	function E.HitOf(stage, key)
		for i = 1, key and #stage.hits or 0 do
			local hit = stage.hits[i]
			if hit.key == key and hit:IsShown() then
				return hit
			end
		end
		return nil
	end

	function E.Outlines(stage)
		E.Outline(stage, stage.selBox, E.HitOf(stage, stage.selected))
		E.Outline(stage, stage.hoverBox, E.HitOf(stage, stage.hovered or stage.outlined))
	end

	-- what the caption and a part's tooltip say: the gestures with the
	-- part's place and size now
	function E.Gestures(stage, part)
		if part.locked then
			return part.locked
		end
		local cur = E.Current(part)
		local out = ""
		if part.drag ~= false then
			out = TEXT.gestures
			if cur and cur.point then
				out = string.format(TEXT.place, cur.point, Num(cur.x) or 0, Num(cur.y) or 0) .. ". " .. out
			end
		end
		if part.size then
			out = out .. string.format(TEXT.size, tostring(cur and cur.size or part.size.min))
		end
		if part.content or part.hide or part.store then
			out = out .. TEXT.menu
		end
		if stage.noKeys and stage.selected == part.key then
			out = out .. TEXT.noKeys
		end
		return out
	end

	function E.Caption(stage)
		local def, text = stage.def, nil
		if stage.dim then
			text = type(stage.dim) == "string" and stage.dim or nil
		elseif def.Empty then
			text = def.Empty(stage.pick)
		end
		if not text then
			local part = stage:Selected()
			text = part and E.Gestures(stage, part) or TEXT.pick
		end
		if stage.caption:GetText() ~= text then
			stage.caption:SetText(text)
		end
	end

	-- the hit frames laid over the parts' visible rects, the smaller on top;
	-- a ghost (a hidden part) drawn faint on the sample, a locked one dimmed
	function E.Sync(stage)
		local def, main = stage.def, stage.main
		local parts = main and def.parts and def.parts(stage.pick, main) or ST.EMPTY
		stage.parts = parts
		wipe(stage.byKey)
		local order, n = stage.order, 0
		wipe(order)
		for i = 1, #parts do
			local part = parts[i]
			stage.byKey[part.key] = part
			local region = part.region and part.region(main)
			if region then
				local cur = E.Current(part)
				local ghost = cur and cur.show == false
				if ghost or part.locked then
					region:Show()
					region:SetAlpha(ghost and K.GHOST or K.DIM)
					stage.faded[region] = true
				elseif stage.faded[region] then
					region:SetAlpha(1)
					stage.faded[region] = nil
				end
				local l, b, r, t = E.Visible(part, region)
				if l and r > l and t > b then
					n = n + 1
					local hit = stage.hits[n] or E.NewHit(stage, n)
					E.PlaceOn(hit, stage, l, b, r, t)
					hit.key, hit.area = part.key, (r - l) * (t - b)
					order[n] = hit
				end
			end
		end
		E.HideFrom(stage.hits, n + 1)
		table.sort(order, E.ByArea)
		local mouse = not stage.dim
		for i = 1, n do
			local hit = order[i]
			local part = stage.byKey[hit.key]
			hit:SetFrameLevel(stage.level + 10 + math.min(i, 15))
			hit:EnableMouse(mouse)
			hit:EnableMouseWheel(mouse and stage.selected == hit.key and part.size ~= nil and not part.locked
				and part.drag ~= false)
			hit:Show()
		end
		if stage.selected and not stage.byKey[stage.selected] then
			stage:Select(nil)
		end
		E.Outlines(stage)
		E.Marks(stage)
	end

	-- the stage painted from the settings now (frozen while a part is
	-- dragged: once after the drop)
	function E.RepaintNow(stage)
		if stage.dragging or not stage:IsVisible() then
			stage.stale = true
			return
		end
		stage.stale = nil
		local def = stage.def
		local reason = stage.opts.dim and stage.opts.dim(stage) or nil
		stage.dim = reason
		if reason and stage.selected then
			stage:Select(nil)
		end
		stage:SetAlpha(reason and K.DIM or 1)
		local main = stage.main
		if main then
			if stage.redress then
				stage.redress = nil
				Preview.Dress(stage.kind, main, stage.pick)
			end
			Preview.Paint(stage.kind, main, stage.pick, nil, stage.ctx)
			E.Fit(stage)
		end
		if def.Refresh then
			def.Refresh(stage, stage.ctx)
		end
		E.Sync(stage)
		E.Caption(stage)
	end

	----------------------------------------------------------------------
	-- The keys: borrowed while a part is picked, out of a fight
	----------------------------------------------------------------------

	function E.WriteNudge(key)
		local stage = key.stage
		local dx, dy = stage.nudgeX or 0, stage.nudgeY or 0
		stage.nudgeX, stage.nudgeY = nil, nil
		local part = stage:Selected()
		if not part or (dx == 0 and dy == 0) or part.locked or part.drag == false then
			return
		end
		local cur = E.Current(part) or ST.EMPTY
		local range = part.range or K.RANGE
		local x = math.max(-range, math.min(range, (Num(cur.x) or 0) + dx))
		local y = math.max(-range, math.min(range, (Num(cur.y) or 0) + dy))
		E.Write(stage, part, E.With(part, { point = cur.point or "CENTER", x = x, y = y }))
	end

	-- the borrowed keys (Edit Layout's key frame calls it out of a fight
	-- only): Escape closes an open list first, then lets the part go; an
	-- arrow nudges it (one write a frame); any other key is the game's
	function E.KeyHandler(key)
		local stage = ST.lent
		local part = stage and stage:Selected()
		if not part or stage.dim then
			return false
		end
		if key == "ESCAPE" then
			-- (a question or the game menu on top: the Escape is theirs)
			local ask, menu = rawget(_G, "MelloUIConfirmDialog"), rawget(_G, "GameMenuFrame")
			if (ask and ask:IsShown()) or (menu and menu:IsShown()) then
				return false
			end
			if W.CloseFlyouts() then
				return true
			end
			local d = ST.drag
			if d and d.moved and d.stage == stage then
				E.StopDrag(true)   -- (a drag under way: back where it was, the part still picked)
				return true
			end
			stage:Select(nil)
			return true
		end
		local dir = K.ARROW[key]
		if not dir or part.locked or part.drag == false or IsControlKeyDown() or IsAltKeyDown() then
			return false
		end
		local n = IsShiftKeyDown() and 10 or 1
		stage.nudgeX = (stage.nudgeX or 0) + dir[1] * n
		stage.nudgeY = (stage.nudgeY or 0) + dir[2] * n
		E.Sched():NextFrame(stage.nudgeKey, E.WriteNudge)
		return true
	end

	function E.Events()
		if not ST.events then
			ST.events = CreateFrame("Frame")
			ST.events:SetScript("OnEvent", E.OnEvent)
		end
		return ST.events
	end

	-- the keys taken over by another borrower (Keybind Mode): this stage's
	-- arrows not free, its fight's events off
	function E.KeysLost()
		local stage = ST.lent
		ST.lent = nil
		if ST.events then
			ST.events:UnregisterEvent("PLAYER_REGEN_DISABLED")
		end
		if stage then
			stage.noKeys = true
			E.Caption(stage)
		end
	end
	ST.lendOpts = { polite = true, onLost = E.KeysLost }

	function E.Lend(stage)
		if ST.lent == stage and MelloUI.KeyboardLentTo and MelloUI:KeyboardLentTo() == E.KeyHandler then
			return true
		end
		if MelloUI:LendKeyboard(E.KeyHandler, ST.lendOpts) then
			ST.lent, stage.noKeys = stage, nil
			local ev = E.Events()
			ev:RegisterEvent("PLAYER_REGEN_DISABLED")
			if ST.relend == stage then
				ST.relend = nil
				ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
			end
			return true
		end
		stage.noKeys = true
		if InCombatLockdown() and stage:IsVisible() then
			ST.relend = stage
			E.Events():RegisterEvent("PLAYER_REGEN_ENABLED")
		end
		return false
	end

	-- the keys given back (`stage`: only if they are its); nothing left to
	-- wait for, no event kept
	function E.TakeBack(stage)
		if ST.lent == stage then
			ST.lent = nil
			MelloUI:TakeBackKeyboard(E.KeyHandler)
		end
		if ST.relend == stage then
			ST.relend = nil
		end
		stage.nudgeX, stage.nudgeY = nil, nil
		if ST.events and not ST.lent then
			ST.events:UnregisterEvent("PLAYER_REGEN_DISABLED")
			if not ST.relend then
				ST.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
			end
		end
	end

	-- a fight starts: the keys go back to the game at once; after it they are
	-- lent again while the stage shows with a part still picked
	E.OnEvent = Shared("OnEvent on the designer stage's keys (a fight's edges)", function(self, event)
		if event == "PLAYER_REGEN_DISABLED" then
			local stage = ST.lent
			if stage then
				E.TakeBack(stage)
				if stage:IsVisible() and stage.selected then
					ST.relend = stage
					self:RegisterEvent("PLAYER_REGEN_ENABLED")
				end
				stage.noKeys = true
				E.Caption(stage)
			end
		elseif event == "PLAYER_REGEN_ENABLED" then
			local stage = ST.relend
			ST.relend = nil
			self:UnregisterEvent("PLAYER_REGEN_ENABLED")
			if stage and stage:IsVisible() and stage.selected then
				E.Lend(stage)
				E.Caption(stage)
			end
		end
	end, "script")

	----------------------------------------------------------------------
	-- Drag and drop, the wheel, the '+' marks, the right-click list
	----------------------------------------------------------------------

	function E.Cursor()
		local x, y = GetCursorPosition()
		return Num(x) or 0, Num(y) or 0
	end

	-- the region's anchors as they were before the drag
	function E.Restore(d)
		local region, points = d.region, d.points
		if not (region and points) then
			return
		end
		region:ClearAllPoints()
		for i = 1, #points do
			local pt = points[i]
			region:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
		end
	end

	-- the drag under way ended, the dragger stopped; `cancel`: a part that
	-- moved goes back where it was, nothing written, its stage painted again
	function E.StopDrag(cancel)
		local d = ST.drag
		ST.drag = nil
		if ST.dragger then
			ST.dragger:SetScript("OnUpdate", nil)
		end
		if d and cancel and d.moved then
			E.Restore(d)
			d.stage.dragging = false
			d.stage.stale = true
			d.stage:Repaint()
		end
		return d
	end

	-- the dragged part follows the cursor (every anchor of it, in its own
	-- units); past CLICK px it is a drag, and the stage stops repainting until
	-- the drop. A release the hit never heard (the game's window left) ends it
	-- here: a drop if it moved
	E.DragTick = Shared("OnUpdate on the designer stage's dragger (a part dragged)", function()
		local d = ST.drag
		if not d then
			return
		end
		if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
			E.StopDrag()
			if d.moved then
				E.Dropped(d.stage, d)
			end
			return
		end
		local x, y = E.Cursor()
		local dx, dy = (x - d.x0) / d.scale, (y - d.y0) / d.scale
		if not d.moved then
			if math.abs(dx) < K.CLICK and math.abs(dy) < K.CLICK then
				return
			end
			d.moved = true
			d.stage.dragging = true
			GameTooltip:Hide()
			E.Marks(d.stage)
		end
		-- (in the region's own units: its effective scale, the box's times its scale)
		local ox, oy = (x - d.x0) / d.regionScale, (y - d.y0) / d.regionScale
		d.region:ClearAllPoints()
		for i = 1, #d.points do
			local pt = d.points[i]
			d.region:SetPoint(pt[1], pt[2], pt[3], pt[4] + ox, pt[5] + oy)
		end
		local sx = d.scale / d.stageScale
		d.hit:ClearAllPoints()
		d.hit:SetPoint("TOPLEFT", d.stage, "BOTTOMLEFT", d.hl + dx * sx, d.ht + dy * sx)
	end, "script")

	-- a part's anchors, each read plainly (a secret one: no drag), or nil
	function E.Points(region)
		local n = Num(Safe.Call(region, "GetNumPoints")) or 0
		if n < 1 then
			return nil
		end
		local points = {}
		for i = 1, n do
			local ok, point, rel, relPoint, x, y = pcall(region.GetPoint, region, i)
			if not ok then
				return nil
			end
			x, y, point, relPoint = Num(x), Num(y), Safe.Text(point), Safe.Text(relPoint)
			if not (x and y and point and relPoint) or Safe.IsSecret(rel) then
				return nil
			end
			points[i] = { point, rel, relPoint, x, y }
		end
		return points
	end

	E.HitDown = Shared("OnMouseDown on a designer stage's part", function(hit, button)
		local stage = hit.stage
		local part = stage.byKey[hit.key]
		if button ~= "LeftButton" or not part or stage.dim then
			return
		end
		E.StopDrag(true)   -- (a drag whose release never came: back where it was)
		local region = part.region and part.region(stage.main)
		local box = E.BoxOf(part, stage.main)
		local x0, y0 = E.Cursor()
		local d = { stage = stage, part = part, hit = hit, x0 = x0, y0 = y0, moved = false }
		ST.drag = d
		if part.locked or part.drag == false or not region then
			return   -- (a click only: picked on the release)
		end
		local points = E.Points(region)
		local scale, stageScale = Num(Safe.Call(box, "GetEffectiveScale")), Num(stage:GetEffectiveScale())
		local hl, _, _, ht = Safe.ScreenRect(hit)
		local sl, sb = Safe.ScreenRect(stage)
		if not (points and scale and stageScale and hl and sl) then
			return
		end
		d.region, d.points = region, points
		d.scale, d.stageScale = scale, stageScale
		d.regionScale = Num(Safe.Call(region, "GetEffectiveScale")) or scale * (part.scale or 1)
		d.hl, d.ht = (hl - sl) / stageScale, (ht - sb) / stageScale
		if not ST.dragger then
			ST.dragger = CreateFrame("Frame")
		end
		ST.dragger:SetScript("OnUpdate", E.DragTick)
	end, "script")

	-- a drop: where the part shows now, through its Drop hook or the rule;
	-- the region back on its anchors, then ONE write (the paint lays it at
	-- its new place); the stage picked on it
	function E.Dropped(stage, d)
		stage.dragging = false
		local part = d.part
		local box = E.BoxOf(part, stage.main)
		local l, b, r, t = E.Visible(part, d.region)
		local cur = E.Current(part)
		local t2
		if l then
			local bl, bb, br, bt, w, h = E.InBox(box, l, b, r, t)
			if bl then
				if part.Drop then
					t2 = part.Drop(part, bl, bb, br, bt, w, h, cur, nil)
				else
					local point, x, y = E.Drop(part, bl, bb, br, bt, w, h, cur, IsShiftKeyDown())
					t2 = point and E.With(part, { point = point, x = x, y = y }) or nil
				end
			end
		end
		E.Restore(d)
		stage:Select(part.key)
		if t2 then
			E.Write(stage, part, t2)
		else
			stage:Repaint()
		end
	end

	-- the release: a drag dropped (on its own stage; else back where it was),
	-- else a click picks the part; the right button opens its list
	E.HitUp = Shared("OnMouseUp on a designer stage's part", function(hit, button)
		local stage = hit.stage
		if button == "LeftButton" then
			local d = E.StopDrag()
			if d and d.moved then
				if d.stage == stage then
					E.Dropped(stage, d)
				else
					ST.drag = d
					E.StopDrag(true)
				end
				return
			end
			local part = stage.byKey[hit.key]
			if part and not stage.dim then
				stage:Select(part.key)
			end
		elseif button == "RightButton" then
			local part = stage.byKey[hit.key]
			if part and not stage.dim then
				stage:Menu(part.key)
			end
		end
	end, "script")

	E.HitEnter = Shared("OnEnter on a designer stage's part", function(hit)
		local stage = hit.stage
		local part = stage.byKey[hit.key]
		if not part or stage.dragging then
			return
		end
		stage.hovered = hit.key
		E.Outlines(stage)
		W.ShowTooltip(hit, part.label or tostring(part.key), E.Gestures(stage, part))
	end, "script")

	E.HitLeave = Shared("OnLeave on a designer stage's part", function(hit)
		local stage = hit.stage
		if stage.hovered == hit.key then
			stage.hovered = nil
			E.Outlines(stage)
		end
		W.TipLeave(hit)
	end, "script")

	function E.WriteWheel(key)
		local stage = key.stage
		local size = stage.pendSize
		stage.pendSize = nil
		local part = stage:Selected()
		if part and size and part.size then
			E.Write(stage, part, E.With(part, { size = size }))
		end
	end

	-- the wheel over the picked part sizes it: the notches of a frame added
	-- up, kept in its range, ONE write on the next frame (its own key: a
	-- repaint asked for in the same frame never takes its place)
	E.HitWheel = Shared("OnMouseWheel on a designer stage's part", function(hit, delta)
		local stage = hit.stage
		local part = stage:Selected()
		if not (part and part.size and hit.key == part.key and Num(delta)) then
			return
		end
		local sz = part.size
		local cur = E.Current(part)
		local from = stage.pendSize or (cur and Num(cur.size)) or sz.min or 0
		local step = sz.step or 1
		stage.pendSize = math.max(sz.min or from, math.min(sz.max or from, from + (delta > 0 and step or -step)))
		E.Sched():NextFrame(stage.wheelKey, E.WriteWheel)
	end, "script")

	E.MarkClick = Shared("OnClick on a designer stage's '+' mark", function(mark)
		local stage = mark.stage
		stage:PlaceAt(stage.selected, mark.spot)
	end, "script")

	E.MarkEnter = Shared("OnEnter on a designer stage's '+' mark", function(mark)
		W.PlusMark(mark.tex, K.PLUS, true)
	end, "script")

	E.MarkLeave = Shared("OnLeave on a designer stage's '+' mark", function(mark)
		W.PlusMark(mark.tex, K.PLUS, false)
	end, "script")

	-- the right-click list's box (one per stage, laid over the part)
	function E.MenuGet()
		return nil
	end

	function E.MenuSet(value)
		local box = ST.menuBox
		local stage = box and box.stage
		local part = stage and stage.byKey[box.melloKey]
		if not part then
			return
		end
		if value == K.MENU_SHOW or value == K.MENU_HIDE then
			E.Write(stage, part, E.With(part, { show = value == K.MENU_SHOW }))
		elseif value == K.MENU_HOME then
			E.Write(stage, part, nil)
		elseif part.content and part.content.set then
			MelloUI:Batch(part.content.set, value)
			stage:Repaint()
		end
	end

	function E.NoOp()
	end

	----------------------------------------------------------------------
	-- The stage's methods
	----------------------------------------------------------------------

	local M = {}

	function M.Repaint(stage)
		E.Sched():NextFrame(stage, E.RepaintNow)
	end

	function M.Selected(stage)
		return stage.selected and stage.byKey[stage.selected] or nil
	end

	-- a part picked (nil: none): the keys borrowed for it out of a fight,
	-- given back with none
	function M.Select(stage, key)
		if key ~= nil and not stage.byKey[key] then
			key = nil
		end
		local was = stage.selected
		stage.selected = key
		if key then
			E.Lend(stage)
		else
			E.TakeBack(stage)
			stage.noKeys = nil
		end
		for i = 1, #stage.hits do
			local hit = stage.hits[i]
			local part = stage.byKey[hit.key]
			hit:EnableMouseWheel(not stage.dim and key ~= nil and hit.key == key and part ~= nil and part.size ~= nil
				and not part.locked and part.drag ~= false)
		end
		E.Outlines(stage)
		E.Marks(stage)
		E.Caption(stage)
		if was ~= key then
			if stage.opts.onSelect then
				stage.opts.onSelect(stage, key)
			end
			-- (the kind's own: its lists following the pick -- one look C10)
			if stage.def.OnSelect then
				stage.def.OnSelect(stage, key)
			end
		end
	end

	M.Reveal = M.Select

	-- a part outlined from outside (a row under the mouse), nil: none
	function M.Outline(stage, key)
		stage.outlined = key
		E.Outlines(stage)
	end

	function M.SetPick(stage, pick)
		local def = stage.def
		pick = def.picks and def.picks[pick] and pick or def.first
		if stage.selected then
			stage:Select(nil)
		end
		stage.pick = pick
		local main = stage.samples[pick]
		if not main and def.Main then
			main = def.Main(stage, pick)
			if main then
				stage.samples[pick] = main
				Preview.Dress(stage.kind, main, pick)
			end
		end
		for p, sample in pairs(stage.samples) do
			sample:SetShown(p == pick)
		end
		stage.main = main
		stage.fitScale = nil
		E.RepaintNow(stage)
	end

	-- a pick from the stage's own furniture (a strip clicked): the page told
	function M.Pick(stage, pick)
		stage:SetPick(pick)
		if stage.opts.onPick then
			stage.opts.onPick(stage, stage.pick)
		end
	end

	-- a part put on a spot ('+'): offset 0, or its Drop hook's place for it
	function M.PlaceAt(stage, key, spot)
		local part = key and stage.byKey[key]
		if not part or part.locked or part.drag == false or not K.COL[spot or ""] then
			return
		end
		local t
		if part.Drop then
			t = part.Drop(part, nil, nil, nil, nil, nil, nil, E.Current(part), spot)
		else
			t = E.With(part, { point = spot, x = 0, y = 0 })
		end
		if t then
			E.Write(stage, part, t)
		end
	end

	-- the right-click list on a part: what it shows (its content), Show or
	-- Hide, its default place; each choice one write
	function M.Menu(stage, key)
		local part = key and stage.byKey[key]
		local hit = E.HitOf(stage, key)
		if not (part and hit) then
			return
		end
		local box = stage.menuBox
		if not box then
			box = CreateFrame("Button", nil, stage)
			box:EnableMouse(false)   -- (a place for the list only: never over its part)
			box.stage, box.melloList, box.Refresh = stage, true, E.NoOp
			box.melloValues = {}
			stage.menuBox = box
		end
		local values = box.melloValues
		wipe(values)
		local content = part.content
		for i = 1, content and content.values and #content.values or 0 do
			values[#values + 1] = content.values[i]
		end
		if part.hide then
			local cur = E.Current(part)
			values[#values + 1] = (cur and cur.show == false) and stage.entries.show or stage.entries.hide
		end
		if part.store and part.store.set then
			values[#values + 1] = stage.entries.home
		end
		if #values == 0 then
			return
		end
		box.melloKey = key
		box.melloGet = content and content.get or E.MenuGet
		box.melloSet = E.MenuSet
		box:ClearAllPoints()
		box:SetAllPoints(hit)
		box:SetFrameLevel(stage.level + 31)
		ST.menuBox = box
		W.OpenList(box)
	end

	-- a choice tried on the stage only (a row's list under the mouse): one
	-- function per option id, made once; nil when the kind does not try it
	function M.TryFor(stage, id)
		local def = stage.def
		if not (id and def.Tries and def.Tries(id)) then
			return nil
		end
		local fn = stage.tries[id]
		if not fn then
			fn = function(value)
				if value == nil then
					stage.ctx.try = nil
				else
					stage.tryT.id, stage.tryT.value = id, value
					stage.ctx.try = stage.tryT
				end
				stage:Repaint()
			end
			stage.tries[id] = fn
		end
		return fn
	end

	function M.SetState(stage, state)
		stage.ctx.state = state
		if stage.chips and stage.chips:Selected() ~= state then
			stage.chips:Select(state)
		end
		stage:Repaint()
		-- (the host told: a part that shows only in a state -- the designer's Parts line)
		if stage.opts.onState then
			stage.opts.onState(stage, state)
		end
	end

	function M.Moved(stage)
		local def = stage.def
		return def.Moved and Num(def.Moved(stage.pick)) or 0
	end

	-- (the designers' Reset part) one part of the pick shown moved from its
	-- home (its store holds a place; never an indicator: Q10), and put back
	function M.PartMoved(stage, key)
		local part = key and stage.byKey[key]
		return part ~= nil and part.class ~= "indicator" and part.store ~= nil and part.store.get ~= nil
			and part.store.get(part) ~= nil
	end

	function M.ResetPart(stage, key)
		if stage:PartMoved(key) then
			E.Write(stage, stage.byKey[key], nil)
		end
	end

	-- every moved part back, after one question (none moved: the line at once)
	function M.ResetAll(stage)
		local def = stage.def
		local n = stage:Moved()
		if n == 0 or not def.ResetAll then
			MelloUI:Print(TEXT.nothing)
			return
		end
		MelloUI:Confirm({
			text = string.format(TEXT.resetAsk, n),
			accept = TEXT.resetAccept,
			cancel = TEXT.cancel,
			onAccept = function()
				MelloUI:Batch(def.ResetAll, stage.pick)
				stage:Repaint()
			end,
		})
	end

	function M.PlaceOnScreen(stage)
		local def = stage.def
		MelloUI:StartEditLayout("configurator", def.mover and def.mover(stage.pick) or nil)
	end

	-- the deep settings Reset this page would write: each def.reset table
	-- that holds something
	function M.Wants(stage)
		local n = 0
		local list = stage.def.reset
		for i = 1, type(list) == "table" and #list or 0 do
			local db = MelloUI:GetModuleDB(list[i][1])
			local v = db and db[list[i][2]]
			if type(v) == "table" and next(v) ~= nil then
				n = n + 1
			end
		end
		return n
	end

	-- pinned at the page's top as it scrolls: one SetPoint when the place
	-- changes, none per frame
	function M.Stick(stage, offset)
		local y = math.max(stage.y0, Num(offset) or 0)
		if y ~= stage.stuckY then
			stage.stuckY = y
			stage:ClearAllPoints()
			stage:SetPoint("TOPLEFT", stage.anchor, "TOPLEFT", stage.x0, -y)
		end
	end

	-- a part's settings block for the page: which = "show" | "size" | "place"
	-- | "panel"; a builder(parent, y) -> frame, height, or nil when the part
	-- has none of it. Its get and set read the part picked when they run.
	-- opts.row(parent, y, label, which) -> a row: the host's own (the
	-- designer's part tabs: a configurator row, its control at the right as
	-- every row's)
	function M.PartSpec(stage, part, which, opts)
		if not part then
			return nil
		end
		local typed = opts and opts.row
		local function Picked()
			return stage:Selected()
		end
		local function Row(parent, y, label)
			if typed then
				return typed(parent, y, label, which)
			end
			local row = CreateFrame("Frame", nil, parent)
			row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
			row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
			row:SetHeight(K.ROW_H)
			local fs = W.Text(row, "GameFontHighlight", label, "text")
			fs:SetPoint("LEFT", row, "LEFT", 0, 0)
			return row
		end
		-- the control: at the host row's right (`right` px in), else after
		-- the label's room
		local function Place(control, row, right)
			if typed then
				control:SetPoint("RIGHT", row, "RIGHT", -right, 0)
			else
				control:SetPoint("LEFT", row, "LEFT", K.LABEL_W, 0)
			end
		end
		local function Height(row)
			return typed and row:GetHeight() or K.ROW_H
		end
		if which == "show" and part.hide then
			return function(parent, y)
				local row = Row(parent, y, TEXT.show)
				local sw = W.Switch(row, function()
					local p = Picked()
					local cur = p and E.Current(p)
					return not (cur and cur.show == false)
				end, function(v)
					local p = Picked()
					if p then
						E.Write(stage, p, E.With(p, { show = v and true or false }))
					end
				end)
				Place(sw, row, 12)
				return row, Height(row)
			end
		elseif which == "size" and part.size then
			local sz = part.size
			return function(parent, y)
				local row = Row(parent, y, part.sizeLabel or "Size")
				local sl = W.Slider(row, typed and 256 or 180, function()
					local p = Picked()
					local cur = p and E.Current(p)
					return cur and Num(cur.size) or sz.min or 0
				end, function(v)
					local p = Picked()
					if p and p.size then
						E.Write(stage, p, E.With(p, { size = v }))
					end
				end, { min = sz.min, max = sz.max, step = sz.step or 1 })
				Place(sl, row, 14)
				return row, Height(row)
			end
		elseif which == "place" and part.drag ~= false and not part.locked then
			return function(parent, y)
				local row = Row(parent, y, typed and TEXT.placeRow or TEXT.x)
				local function Get(axis)
					return function()
						local p = Picked()
						local cur = p and E.Current(p)
						return cur and Num(cur[axis]) or 0
					end
				end
				local function Set(axis)
					return function(v)
						local p = Picked()
						v = Num(v)
						if p and v then
							local range = p.range or K.RANGE
							local cur = E.Current(p) or ST.EMPTY
							E.Write(stage, p, E.With(p, { point = cur.point or "CENTER",
								[axis] = math.max(-range, math.min(range, E.Round(v))) }))
						end
					end
				end
				local bx = W.NumberBox(row, 52, Get("x"), Set("x"))
				local ly = W.Text(row, "GameFontHighlight", TEXT.y, "text")
				local by = W.NumberBox(row, 52, Get("y"), Set("y"))
				if typed then
					-- (X [ ]  Y [ ] at the row's right)
					by:SetPoint("RIGHT", row, "RIGHT", -14, 0)
					ly:SetPoint("RIGHT", by, "LEFT", -8, 0)
					bx:SetPoint("RIGHT", ly, "LEFT", -16, 0)
					local lx = W.Text(row, "GameFontHighlight", TEXT.x, "text")
					lx:SetPoint("RIGHT", bx, "LEFT", -8, 0)
				else
					bx:SetPoint("LEFT", row, "LEFT", K.LABEL_W, 0)
					ly:SetPoint("LEFT", bx, "RIGHT", 16, 0)
					by:SetPoint("LEFT", ly, "RIGHT", 8, 0)
				end
				return row, Height(row)
			end
		elseif which == "panel" and stage.def.Panel then
			local def = stage.def
			return function(parent, y)
				return def.Panel(part.class, stage, parent, y)
			end
		end
		return nil
	end

	----------------------------------------------------------------------
	-- Following the settings while on show (the bus: only while a stage
	-- shows; one repaint a stage a frame)
	----------------------------------------------------------------------

	function E.DressTopic(kind, topic)
		local list = Reg.dress[kind]
		for i = 1, list and #list or 0 do
			local topics = list[i].topics
			for j = 1, topics and #topics or 0 do
				if topics[j] == topic then
					return true
				end
			end
		end
		return false
	end

	function E.KindTopic(kind, topic)
		local def = Reg.kinds[kind]
		local topics = def and def.topics
		for j = 1, topics and #topics or 0 do
			if topics[j] == topic then
				return true
			end
		end
		return false
	end

	function E.OnStageSetting(name)
		if type(name) ~= "string" then
			return
		end
		for stage in pairs(ST.shown) do
			if Reg.Watches(stage.kind, name) then
				stage:Repaint()
			end
		end
	end

	-- a module switched: its dressing may come or go, so dressed again first
	function E.OnStageModule(name)
		if type(name) ~= "string" then
			return
		end
		for stage in pairs(ST.shown) do
			if Reg.Watches(stage.kind, name) then
				stage.redress = true
				stage:Repaint()
			end
		end
	end

	function E.OnStageAll()
		for stage in pairs(ST.shown) do
			stage:Repaint()
		end
	end

	function E.TopicFn(topic)
		local fn = ST.topicFns[topic]
		if not fn then
			fn = function()
				for stage in pairs(ST.shown) do
					local dress = E.DressTopic(stage.kind, topic)
					if dress or E.KindTopic(stage.kind, topic) then
						stage.redress = stage.redress or dress
						stage:Repaint()
					end
				end
			end
			ST.topicFns[topic] = fn
		end
		return fn
	end

	function E.Listen(stage)
		MelloUI:On("setting", E.OnStageSetting, ST)
		MelloUI:On("module", E.OnStageModule, ST)
		MelloUI:On("palette", E.OnStageAll, ST)
		MelloUI:On("fonts", E.OnStageAll, ST)
		local topics = stage.def.topics
		for i = 1, topics and #topics or 0 do
			MelloUI:On(topics[i], E.TopicFn(topics[i]), ST)
		end
		local list = Reg.dress[stage.kind]
		for i = 1, list and #list or 0 do
			local dt = list[i].topics
			for j = 1, dt and #dt or 0 do
				MelloUI:On(dt[j], E.TopicFn(dt[j]), ST)
			end
		end
	end

	E.StageShow = Shared("OnShow on a designer stage", function(stage)
		if not ST.shown[stage] then
			ST.shown[stage] = true
			ST.nShown = ST.nShown + 1
		end
		E.Listen(stage)
		local scroll = stage.opts.scroll
		-- (pinned under what the page lays over it: its chips -- stage.pinAbove)
		stage:Stick((scroll and Num(Safe.Call(scroll, "GetVerticalScroll")) or 0) + (stage.pinAbove or 0))
		E.RepaintNow(stage)
	end, "script")

	-- hidden: a drag under way cancelled (no write; painted again on the next
	-- show), the part let go, the keys given back; the bus left with the last
	E.StageHide = Shared("OnHide on a designer stage", function(stage)
		local d = ST.drag
		if d and d.stage == stage then
			E.StopDrag(true)
		end
		stage.dragging = false
		stage.pendSize = nil
		if stage.selected then
			stage:Select(nil)
		end
		E.TakeBack(stage)
		if ST.shown[stage] then
			ST.shown[stage] = nil
			ST.nShown = ST.nShown - 1
			if ST.nShown == 0 then
				MelloUI:Off(ST)
			end
		end
	end, "script")

	-- a click on the stage's empty ground lets the part go (the rows under it
	-- never see it: the stage takes the mouse)
	E.StageUp = Shared("OnMouseUp on a designer stage's ground", function(stage)
		if stage.selected then
			stage:Select(nil)
		end
	end, "script")

	function E.StateChip(chips, key)
		chips.melloStage:SetState(key)
	end

	function E.Edged(stage, key, level)
		local f = CreateFrame("Frame", nil, stage)
		W.Edges(f, key, "OVERLAY")
		f:SetFrameLevel(level)
		f:EnableMouse(false)
		f:Hide()
		return f
	end

	function Reg.MakeStage(parent, kind, def, skin, opts)
		opts = type(opts) == "table" and opts or Reg.NONE
		local stage = CreateFrame("Frame", nil, parent)
		stage.kind, stage.def, stage.skin, stage.opts = kind, def, skin, opts
		local w = Fin(opts.width) or Fin(Safe.Call(parent, "GetWidth")) or 400
		local h = def.height or K.HEIGHT
		stage:SetSize(w, h)
		stage.level = (Num(Safe.Call(parent, "GetFrameLevel")) or 0) + K.LIFT
		stage:SetFrameLevel(stage.level)
		stage:EnableMouse(true)
		W.Solid(stage, "BACKGROUND", "mainWindow", 1):SetAllPoints(stage)
		W.Edges(stage, "border", "BORDER")
		stage.x0, stage.y0, stage.anchor = Num(opts.x) or 0, Num(opts.y0) or 0, opts.anchor or parent
		stage.stuckY = stage.y0
		stage:SetPoint("TOPLEFT", stage.anchor, "TOPLEFT", stage.x0, -stage.y0)
		for name, fn in pairs(M) do
			stage[name] = fn
		end
		stage.ctx, stage.tryT, stage.tries = {}, {}, {}
		stage.samples, stage.hits, stage.marks, stage.order = {}, {}, {}, {}
		stage.byKey, stage.faded = {}, setmetatable({}, weakKeys)
		stage.wheelKey, stage.nudgeKey = { stage = stage }, { stage = stage }
		stage.entries = { show = { value = K.MENU_SHOW, label = TEXT.show }, hide = { value = K.MENU_HIDE, label = TEXT.hide },
			home = { value = K.MENU_HOME, label = def.homeLabel or TEXT.home } }
		stage.holder = CreateFrame("Frame", nil, stage)
		stage.holder:SetAllPoints(stage)
		stage.selBox = E.Edged(stage, "selectedTrim", stage.level + 28)
		stage.hoverBox = E.Edged(stage, "hover", stage.level + 29)
		stage.caption = W.Text(stage, "GameFontHighlightSmall", nil, "text")
		stage.caption:SetPoint("BOTTOMLEFT", stage, "BOTTOMLEFT", K.PAD, K.PAD / 2)
		stage.caption:SetPoint("RIGHT", stage, "RIGHT", -K.PAD, 0)
		if type(def.states) == "table" and #def.states > 0 then
			local chips = W.Chips(stage, { width = math.floor(w / 2), onPick = E.StateChip })
			chips.melloStage = stage
			chips:SetItems(def.states)
			chips:Select(def.states[1].key)
			chips:SetPoint("TOPRIGHT", stage, "TOPRIGHT", -K.PAD, -K.PAD)
			chips:SetFrameLevel(stage.level + 32)
			stage.chips = chips
			stage.ctx.state = def.states[1].key
		end
		if def.Furnish then
			def.Furnish(stage, stage.holder, w, h)
		end
		stage:SetScript("OnShow", E.StageShow)
		stage:SetScript("OnHide", E.StageHide)
		stage:SetScript("OnMouseUp", E.StageUp)
		stage:SetPick(def.first)
		if stage:IsVisible() then
			E.StageShow(stage)   -- (made on show: no OnShow comes)
		end
		return stage
	end

	function Reg.ShownStage(kind)
		for stage in pairs(ST.shown) do
			if stage.kind == kind then
				return stage
			end
		end
		return nil
	end

	function Preview.PartKeys(kind, pick)
		local def = Reg.kinds[kind]
		if not (def and def.PartKeys) then
			return nil
		end
		return def.PartKeys(pick or def.first)
	end

	-- a part of the kind's pick by its key, without a stage (the def's
	-- parts(pick) take no sample: the designer's part tabs, laid before a
	-- stage shows)
	function Preview.PartOf(kind, pick, key)
		local def = Reg.kinds[kind]
		local list = def and def.parts and def.parts(pick or def.first)
		for i = 1, type(list) == "table" and #list or 0 do
			if list[i].key == key then
				return list[i]
			end
		end
		return nil
	end

	function Preview.RowEnter(row)
		local o = row and row.melloOutline
		local stage = o and Reg.ShownStage(o.kind)
		if stage then
			stage:Outline(o.key)
		end
	end

	function Preview.RowLeave(row)
		local o = row and row.melloOutline
		local stage = o and Reg.ShownStage(o.kind)
		if stage then
			stage:Outline(nil)
		end
	end

	-- (the engine's functions and its state, read by the suite)
	E.state = ST
	Preview.StageEngine = E
end

--------------------------------------------------------------------------------
-- A party member's replica (0.17.0: Preview's stand-ins, Core/Preview.lua; the
-- user, 2026-10-01: "the party frames are not a 1-1 replica on how they
-- actually look ingame"): the game's party member frame as its own template
-- draws it (Blizzard_UnitFrame PartyFrameTemplates.xml, PartyMemberFrameTemplate,
-- and PartyMemberFrame.lua's ToPlayerArt: 120 x 53; the portrait 37 at 7,-6
-- in its circle mask under the frame's picture at 1,-2; the name 57 x 12 at
-- 46,-6; the health bar 70 x 10 at 45,-19 in its container, its fill masked
-- by the health mask at -29,3; the mana bar 74 x 7 at 41,-30, its fill masked
-- at 14,-26 of the frame), with the same keys, so the unit frame skin dresses
-- it as it dresses a member (Unit Frames' M:DressStandIn) -- never a secure
-- template of the game's: no unit, no events, no scripts of the game's.
-- Painted from a sample as the configurator's preview is: the bars wear what
-- the settings put on the real ones (Bar Textures' preview exports), the name
-- in Unit Frames' form, the portrait Class Icons' medallion or a creature's.
-- The 'unitframe' kind's party sample (stage F: no names of its own):
--   CP.Build("unitframe", parent, "party", onto) -> frame   (`onto`: a frame
--       of the caller's to build it on -- Group Frames' solo party frame, a
--       unit button of its own -- else a new frame on `parent`)
--   CP.Values("unitframe", "party", i) -> a fresh copy of its made-up values,
--       for the caller's own name, class, health and power
--   CP.Dress("unitframe", frame, "party")   Unit Frames' DressStandIn
--   CP.Paint / CP.Update("unitframe", frame, "party", values)
--------------------------------------------------------------------------------

local PARTY_W, PARTY_H = 120, 53
local PARTY_ART = "UI-HUD-UnitFrame-Party-PortraitOn"
local PARTY_HEALTH = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health"

local function Masked(region, parent, atlas, rel, x, y)
	local mask = parent:CreateMaskTexture()
	if Atlas(atlas) then
		mask:SetAtlas(atlas, true)
	end
	mask:SetPoint("TOPLEFT", rel, "TOPLEFT", x, y)
	if region and region.AddMaskTexture then
		region:AddMaskTexture(mask)
	end
	return mask
end

local function MakeParty(parent, onto)
	local f = onto or CreateFrame("Frame", nil, parent)
	f:SetSize(PARTY_W, PARTY_H)
	f.Portrait = f:CreateTexture(nil, "BACKGROUND")
	f.Portrait:SetSize(37, 37)
	f.Portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -6)
	local circle = f:CreateMaskTexture()
	circle:SetAtlas("CircleMask")
	circle:SetAllPoints(f.Portrait)
	f.Portrait:AddMaskTexture(circle)
	f.PortraitMask = circle
	f.Texture = f:CreateTexture(nil, "ARTWORK")
	f.Texture:SetAtlas(PARTY_ART, true)
	f.Texture:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -2)
	f.Flash = f:CreateTexture(nil, "ARTWORK")
	f.Flash:SetAtlas("UI-HUD-UnitFrame-Party-PortraitOn-InCombat", true)
	f.Flash:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -2)
	f.Flash:Hide()
	f.Name = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	f.Name:SetSize(57, 12)
	f.Name:SetJustifyH("LEFT")
	f.Name:SetPoint("TOPLEFT", f, "TOPLEFT", 46, -6)
	local hc = CreateFrame("Frame", nil, f)
	hc:SetSize(70, 10)
	hc:SetPoint("TOPLEFT", f, "TOPLEFT", 45, -19)
	local health = Bar(hc)
	health:SetSize(70, 10)
	health:SetPoint("TOPLEFT", hc, "TOPLEFT", 0, 0)
	health:SetStatusBarTexture(PARTY_HEALTH)
	hc.HealthBar = health
	Masked(health:GetStatusBarTexture(), hc, PARTY_HEALTH .. "-Mask", hc, -29, 3)
	f.HealthBarContainer = hc
	local mana = Bar(f)
	mana:SetSize(74, 7)
	mana:SetPoint("TOPLEFT", f, "TOPLEFT", 41, -30)
	Masked(mana:GetStatusBarTexture(), mana, "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Mana-Mask", f, 14, -26)
	f.ManaBar = mana
	f.PartyMemberOverlay = CreateFrame("Frame", nil, f)
	f.PartyMemberOverlay:SetAllPoints(f)
	return f
end

-- the portrait: Class Icons' medallion while its player portraits are on,
-- else the game's portrait of a sample creature (as on the real frame: a
-- player's own picture; none of this client's units is read here)
local function PaintPartyPortrait(f, s)
	local tex = f.Portrait
	local ci = Running("ClassIcons")
	local medallion = ci and ci.db.portraits and s.class and MelloUI:ClassIconPath(s.class) or nil
	local want = medallion or s.display or NO_PORTRAIT
	if f.portraitShows == want then
		return
	end
	f.portraitShows = want
	tex:SetTexCoord(0, 1, 0, 1)
	if medallion then
		tex:SetTexture(medallion)
	elseif s.display and type(_G.SetPortraitTextureFromCreatureDisplayID) == "function"
		and pcall(_G.SetPortraitTextureFromCreatureDisplayID, tex, s.display) then
		return
	else
		tex:SetTexture(NO_PORTRAIT)
	end
end

local function PaintParty(f, s)
	s.healthAtlas = PARTY_HEALTH
	f.sample = s
	f.Name:SetText(NameAs(s))
	PaintPartyPortrait(f, s)
	local BT = Exports("BarTextures", "PreviewHealthColor")
	if BT then
		PaintHealth(f.HealthBarContainer.HealthBar, s, BT)
		PaintPower(f.ManaBar, s, BT)
	else
		Fill(f.HealthBarContainer.HealthBar, s.health, s.max)
		Fill(f.ManaBar, s.power, s.powerMax)
	end
end

--------------------------------------------------------------------------------
-- The 'unitframe' kind (here until stage G moves it to its module): the Unit
-- Frames page's corner preview, and the party pick's sample (the replica
-- above) for Preview's stand-ins, Group Frames' solo frame and the Designer's
-- party. No parts. Its party sample is dressed through Unit Frames' own skin
-- seam (DressStandIn, the painted skin's tail in it), which also dresses the
-- real solo frame and the stand-ins: two dress seams on purpose (CP.OnDress
-- is the other kinds')
--------------------------------------------------------------------------------

-- the corner's parts, made once (MakeCorner: its frame, panel and scripts)
local function UnitCorner(p, skin)
	local portrait = W.RoundIcon(p, PORTRAIT)
	portrait:EnableMouse(false)   -- (a picture: no hover light, the preview's tooltip stands)
	p.portrait = portrait
	p.crest = portrait:CreateTexture(nil, "OVERLAY", nil, 7)
	p.crest:SetSize(CREST, CREST)
	p.crest:SetPoint("CENTER", portrait, "TOP", 0, -2)
	p.name = W.Text(p, "GameFontNormal", nil, "text")
	p.name:SetWordWrap(false)
	p.bar1, p.bar2 = Bar(p), Bar(p)
	p.text1 = p.bar1:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	p.text2 = p.bar2:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	p.icon = p:CreateTexture(nil, "ARTWORK")
	p.icon:SetSize(24, 24)
	p.icon:SetTexture(CAST_ICON)
	p.castText = p.bar1:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	p.castText:SetPoint("LEFT", p.bar1, "LEFT", 4, 0)
	p.castText:SetText(SAMPLES.castbars.spell)
	p.castTime = p.bar1:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	p.castTime:SetPoint("RIGHT", p.bar1, "RIGHT", -4, 0)
	p.castTime:SetText(SAMPLES.castbars.time)

	previews[p] = true
	if skin and skin.OnKit then
		skin:OnKit(OnShellKit)
		if skin.kit then
			skin:Kit(KitRim, p)
		end
	end
end

-- a party sample painted from its values (the stand-ins' hits too: values
-- only, no dress)
local function UnitUpdate(f, pick, s)
	if pick == "party" and s then
		PaintParty(f, s)
	end
end

Preview.Register("unitframe", {
	place = "corner", width = WIDTH, height = HEIGHT,
	picks = SAMPLES, first = FIRST_PICK, watch = WATCH,
	Corner = UnitCorner,
	Lay = Lay,
	-- (a show draws the portrait again: it may have changed)
	OnShow = function(p)
		p.portraitShows = nil
	end,
	Tip = function(pick)
		local s = SAMPLES[pick]
		return s and (s.label .. ", drawn with your settings as they are now. The name and the numbers are made up.")
	end,
	Build = function(parent, pick, onto)
		if pick == "party" then
			return MakeParty(parent, onto)
		end
		return nil
	end,
	Values = function(pick)
		return SAMPLES[pick]
	end,
	-- (dressed as a member: its level and name band, the painted skin's
	-- dressing while that is on -- Unit Frames' own, looked up at each call)
	Dress = function(f, pick)
		local uf = pick == "party" and MelloUI:GetModule("UnitFrames")
		if uf and uf.DressStandIn then
			uf:DressStandIn(f)
		end
	end,
	Paint = function(f, pick, s)
		if previews[f] then
			PaintCorner(f)
		else
			UnitUpdate(f, pick, s)
		end
	end,
	Update = UnitUpdate,
})
