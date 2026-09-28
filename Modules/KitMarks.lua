--------------------------------------------------------------------------------
-- MelloUI - Kit marks: Elite / Rare / Rare Elite / Boss (0.15.0)
--
-- A unit's class shown in metal (user, 2026-09-28, the approved sketch:
-- MelloUI-BuildData/output/elite_sketch): an Elite in gold with a crown, a
-- Rare in silver with a star, a Rare Elite in silver with a gold star (no
-- wings on any crest: user, 2026-09-28, every crest the same square size), a
-- Boss in red-bronze with a skull. One system for every frame that shows
-- them. The art is baked (Tools/kit_marks.py: the kit's group marks/, its
-- metals and crests never recoloured by a palette -- the metals mean what a
-- unit is; a ring's compass gems are the look's, as the plain ring's are,
-- Tools/kit_palette.py GEM_TWINS): each piece a
-- mark touches has a metal twin of the same shape and geometry, so a mark is
-- a piece swapped on the texture that already stands there (Kit:Apply), and
-- nothing is laid out anew. Its shade follows by itself: Kit:Apply fits the
-- piece's shade partner to the twin (the twins share their plain piece's
-- shadow; the rings and crests have their own, Tools/make_kit_shadows.py).
--
--   Kit:MarkOf(unit) -> "elite" | "rare" | "rareelite" | "boss" | nil
--       from UnitClassification ("worldboss" is a boss); a boss also when the
--       unit is an encounter's boss (UnitIsBossMob, the boss1-5 units). A
--       hidden level (UnitLevel -1) is no boss: the game hides the level of
--       every unit ten or more levels above the player (an elite ogre while
--       levelling), the game's own boss portrait asks UnitIsBossMob. A
--       normal unit, no unit, or an answer that reads secret: nil. Asked on
--       the events that change it (the frames' own: a target change, a
--       nameplate shown, UNIT_CLASSIFICATION_CHANGED, an encounter's boss
--       units changed: INSTANCE_ENCOUNTER_ENGAGE_UNIT), never polled.
--   Kit:MarkPiece(piece, kind) -> the piece's metal twin for the kind, or nil
--       window/portrait_ring   the ring in the metal with the kind's crest on
--                              its top gem (the unit frames' style B)
--       buttons/orb_*          the level orb in the metal
--       bars/<family>_cap_l    a Nameplate Border's left cap in the metal
--   Kit:MarkCrest(kind) -> the crest alone ("marks/crest_<kind>"), or nil
--   Kit:WearMark(tex, piece, kind): the kit texture shows `piece` or, for a
--       kind, its twin -- swapped only when that changes
--   Kit.markDisc: the white disc that fits inside the level orb's ring (the
--       nameplates' dark ground under the level number, painted there)
-- Its users: UnitFramePanel (the target's and focus's ring and level orb,
-- their targets' rings) and NameplatePanel (the left cap, the level orb and a
-- crest before the name); each has its own switch (its `marks` option).
-- Nothing is made at load, and nothing per call once a twin was looked up.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret
local Value = MelloUI.Safe.Value
local Text = MelloUI.Safe.Text

local METAL = { elite = "gold", rare = "silver", rareelite = "silver", boss = "boss" }
-- UnitClassification's answers that are marked ("normal", "trivial", "minus":
-- none)
local CLASS = { elite = "elite", rare = "rare", rareelite = "rareelite", worldboss = "boss" }
local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }
local CRESTS = { elite = "marks/crest_elite", rare = "marks/crest_rare", rareelite = "marks/crest_rareelite", boss = "marks/crest_boss" }
local twins = {}   -- [piece] = { [kind] = its twin, or false: none } (filled as asked)

Kit.markDisc = "marks/orb_disc"

-- a yes from the game: true, never a secret or failed answer (each call
-- protected: a unit the client refuses answers nothing)
local function Yes(ok, answer)
	return ok and Value(answer) == true
end

-- an encounter's boss: the game says so (UnitIsBossMob, where the client has
-- it), or the unit is one of the boss frames' (each slot asked: an encounter
-- may leave boss1 empty while boss2 holds a unit, as the game's boss frames
-- read them)
local function IsBoss(unit)
	if type(UnitIsBossMob) == "function" and Yes(pcall(UnitIsBossMob, unit)) then
		return true
	end
	if type(UnitIsUnit) ~= "function" then
		return false
	end
	for i = 1, #BOSS_UNITS do
		if Yes(pcall(UnitIsUnit, unit, BOSS_UNITS[i])) then
			return true
		end
	end
	return false
end

function Kit:MarkOf(unit)
	if type(unit) ~= "string" or Secret(unit) or type(UnitClassification) ~= "function" then
		return nil
	end
	local ok, class = pcall(UnitClassification, unit)
	local kind = ok and CLASS[Text(class) or ""] or nil
	if kind == "boss" then
		return kind
	end
	if IsBoss(unit) then
		return "boss"
	end
	return kind
end

function Kit:MarkPiece(piece, kind)
	local metal = kind and METAL[kind]
	if not metal or type(piece) ~= "string" then
		return nil
	end
	local row = twins[piece]
	if not row then
		row = {}
		twins[piece] = row
	end
	local twin = row[kind]
	if twin == nil then
		local name
		if piece == "window/portrait_ring" then
			name = "marks/ring_" .. kind
		elseif piece:find("^buttons/orb_") then
			name = "marks/orb_" .. metal
		else
			local family = piece:match("^bars/(%a+)_cap_l$")
			name = family and ("marks/cap_" .. family .. "_" .. metal) or nil
		end
		twin = (name and self:Piece(name)) and name or false
		row[kind] = twin
	end
	return twin or nil
end

function Kit:MarkCrest(kind)
	local name = kind and CRESTS[kind]
	return (name and self:Piece(name)) and name or nil
end

function Kit:WearMark(tex, piece, kind)
	if not (tex and piece) then
		return
	end
	local want = (kind and self:MarkPiece(piece, kind)) or piece
	if tex.kitName ~= want then
		self:Apply(tex, want)
	end
end
