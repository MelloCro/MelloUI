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
--       rings/<id>             (0.19.8) a ring style (Portrait Ring) the same way
--       buttons/orb_*          the level orb in the metal
--       bars/<family>_cap_l    a Nameplate Border's left cap in the metal
--   Kit:MarkCrest(kind) -> the crest alone ("marks/crest_<kind>"), or nil
--       (the Rare Alert's and the configurator's preview's)
--   Kit:MarkTop(kind) -> the nameplates' mark on top for the kind (2026-10-05,
--       docs/plans/rank-marks-top.md): its pieces' names, { crest, line, endL,
--       endR, bead } -- the crest with its wings, the line (stretched between
--       the ends and the crest), its two ends (a plain line's gems, a boss's
--       winged scrolled ends) and a boss's bead (nil for the others) -- or nil
--   Kit:WearMark(tex, piece, kind): the kit texture shows `piece` or, for a
--       kind, its twin -- swapped only when that changes
--   Kit.markDisc: the white disc that fits inside the level orb's ring
--   Kit:OrbDisc(rep, host[, number]) -> the level number's dark ground on a
--       level orb (Kit.markDisc in the palette's inner panel; the nameplates'
--       since 0.15.0, the unit frames' since 2026-10-03, below)
-- Its users: UnitFramePanel (the target's and focus's ring and level orb,
-- their targets' rings) and NameplatePanel (the mark on top: a metal line
-- over the name with the crest on it; 2026-10-05, the plate itself no longer
-- in the metal); each has its own switch (its `marks` option).
-- Nothing is made at load, and nothing per call once a twin was looked up.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit
-- what the kit keeps beside the game's frames (Kit.lua: weak-keyed, never keys on them)
local pieceNameOf = MelloUI.Kept.pieceNameOf
local hooksecurefunc = MelloUI.Perf:Scope("KitMarks").hooksecurefunc

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
		elseif piece:find("^rings/") then
			-- (0.19.8) a ring style of the border library's as the portrait ring: its own metal twins
			name = "marks/" .. piece:sub(7) .. "_" .. kind
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

local TOPS = {
	elite = { crest = "marks/topcrest_elite", line = "marks/topline_gold", endL = "marks/topgem_gold", endR = "marks/topgem_gold" },
	rare = { crest = "marks/topcrest_rare", line = "marks/topline_silver", endL = "marks/topgem_silver", endR = "marks/topgem_silver" },
	rareelite = { crest = "marks/topcrest_rareelite", line = "marks/topline_silver", endL = "marks/topgem_gold",
		endR = "marks/topgem_gold" },
	boss = { crest = "marks/topcrest_boss", line = "marks/topline_boss", endL = "marks/topend_boss_l",
		endR = "marks/topend_boss_r", bead = "marks/topbead_boss" },
}

function Kit:MarkTop(kind)
	local top = kind and TOPS[kind]
	return (top and self:Piece(top.crest)) and top or nil
end

function Kit:WearMark(tex, piece, kind)
	if not (tex and piece) then
		return
	end
	local want = (kind and self:MarkPiece(piece, kind)) or piece
	if pieceNameOf[tex] ~= want then
		self:Apply(tex, want)
	end
end

-- The level number's dark ground (0.15.0 on the nameplates; the user: readable
-- on any art and colour. The unit frames' too, 2026-10-03: "the circle is
-- fine but ... make it the same as on the nameplates, circle with a black
-- background"): the palette's inner panel at DISC_ALPHA on the baked disc
-- that fits inside the orb's ring (Kit.markDisc, the ring's inner edge), a
-- region of `host` (the frame that draws the number) one sublevel over the
-- orb (and its metal twin, worn on the same texture), on the orb's own rect.
-- It shows while the orb does (the orb texture's own show and hide, hooked:
-- the rep's switch and the game's show and hide of the circle alike). It lies
-- inside the orb's outline: no shade partner of its own. Its strength is the
-- region's alpha, not the colour's (Dark Mode's shade sets a kit texture's
-- colour again with no alpha): opaque since 2026-10-03 (the user: "the
-- untiframe and the nameplate Disc Darkness can be 100%"; 0.85 before).
-- `number`: the level text where it shares the orb's draw layer (the unit
-- frames': both OVERLAY, the number drawn over the orb only by the order of
-- the two) -- raised to the top of that layer while the rep is on, so the
-- disc never covers it; its own sublevel back with the rep off. Made once per
-- orb: asked again, the same disc.
local DISC_ALPHA = 1
local discs = setmetatable({}, { __mode = "k" })   -- [orb texture] = its disc

function Kit:OrbDisc(rep, host, number)
	local tex = rep and rep.tex
	if not (tex and type(host) == "table" and host.CreateTexture and self.markDisc) then
		return nil
	end
	local disc = discs[tex]
	if disc then
		return disc
	end
	local layer, sub = tex:GetDrawLayer()
	disc = host:CreateTexture(nil, layer or "BACKGROUND", nil, math.min((sub or 0) + 1, 7))
	self:Apply(disc, self.markDisc)
	disc:SetAllPoints(tex)
	self:Paint(disc, "innerPanel", "vertex", 1)
	disc:SetAlpha(DISC_ALPHA)
	discs[tex] = disc
	local function Sync()
		disc:SetShown(tex:IsShown())
	end
	hooksecurefunc(tex, "Show", Sync)
	hooksecurefunc(tex, "Hide", Sync)
	hooksecurefunc(tex, "SetShown", Sync)
	Sync()
	local okL, numberLayer, numberSub = false, nil, nil
	if type(number) == "table" and number.SetDrawLayer then
		okL, numberLayer, numberSub = pcall(number.GetDrawLayer, number)
	end
	if okL and type(numberLayer) == "string" then
		numberSub = tonumber(numberSub) or 0
		local function Raise(on)
			number:SetDrawLayer(numberLayer, on and 7 or numberSub)
		end
		local enable, disable = rep.onEnable, rep.onDisable
		rep.onEnable = function(...)
			if enable then
				enable(...)
			end
			Raise(true)
		end
		rep.onDisable = function(...)
			if disable then
				disable(...)
			end
			Raise(false)
		end
		-- (asked for while its skin is on: a rep made then is enabled at once)
		Raise(true)
	end
	return disc
end
