--------------------------------------------------------------------------------
-- MelloUI - Nameplates
--
-- Large crowd-control icon above the name on enemy nameplates, and a quest
-- marker on enemies you still need for a quest (Forever's default nameplates
-- have no quest icon at all).
--
-- Forever shows crowd-control auras on NPC nameplates in a small list to the
-- right of the health bar (CrowdControlListFrame) and loss-of-control effects
-- on player nameplates in a similar spot (LossOfControlFrame). This module
-- moves both above the name / debuff row and scales them up.
--
-- Blizzard must be showing crowd control on nameplates for this to have any
-- effect: Options > Nameplates > enemy NPC auras > Crowd Control.
--
-- The plate names (one-look D6; the Plate section below RestoreAll): the
-- soft band behind each name above its bar, as long as the name (Name Shade,
-- moved from the Nameplate Kit: the user's 2026-09-25 plate band; bar plates
-- only and part of Nameplate Tweaks since 2026-10-15); Show Names As as a
-- cover of ours, never a write on the game's name; one name watch and one
-- crowd budget for everything made on a plate. The Nameplate Kit (Oldschool)
-- plugs in with SetNamePlacer, WatchName and FollowName.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Nameplates")
-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer

local BASE_ITEM_SIZE = 25 -- NamePlateConstants.AURA_ITEM_HEIGHT
local BASE_LOC_SIZE = 30  -- LossOfControlFrame size in XML

local M = MelloUI:RegisterModule("Nameplates", {
	title = "Nameplates",
	desc = "Large crowd-control icon above the name and a quest marker on enemy nameplates.",
	icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
	flavour = "Know who is stunned, who is your quest target, and who is about to be a problem.",
	group = "Frames and bars", navOrder = 2,
	role = "adds",
	tweak = { label = "Nameplate Tweaks", desc = "On the game's nameplates: the large crowd-control icon above the name, the quest marker on enemies you still need, the threat line, the combo points on your target's plate, the names' form (Show Names As) and the soft shade behind the names (Name Shade). Off: all six go. Works with or without the reskin.", order = 4 },
	defaults = {
		nameFormat = "both",   -- set by UI Modifications' "Show Names As" (one setting for every name)
		bigCC = true,
		ccSize = 45,
		ccGap = 4,
		questIcon = true,
		questIconSize = 22,
		threatLine = true,
		comboPoints = true,
		comboSize = 90,
	},
	options = {
		{ type = "header", name = "Crowd Control" },
		{ type = "toggle", key = "bigCC", name = "Large CC Icon Above Name",
		  desc = "Move the crowd-control icon from the right side of the nameplate to above the name and enlarge it. Requires Blizzard's Crowd Control nameplate aura option to be on." },
		{ type = "slider", key = "ccSize", parent = "bigCC", name = "CC Icon Size", min = 30, max = 120, step = 5,
		  format = function(v) return string.format("%d px", v) end,
		  desc = "Size of the crowd-control icon in pixels." },
		{ type = "slider", key = "ccGap", parent = "bigCC", name = "Gap Above Name", min = 0, max = 30, step = 1,
		  format = function(v) return string.format("%d px", v) end,
		  desc = "Space between the name / debuff row and the crowd-control icon." },
		{ type = "header", name = "Quest Icon" },
		{ type = "toggle", key = "questIcon", name = "Quest Icon",
		  desc = "Show a yellow quest marker left of the health bar on enemies that still count for one of your quests." },
		{ type = "slider", key = "questIconSize", parent = "questIcon", name = "Quest Icon Size", min = 12, max = 40, step = 1,
		  format = function(v) return string.format("%d px", v) end,
		  desc = "Size of the quest marker in pixels." },
		{ type = "header", name = "Threat" },
		{ type = "toggle", key = "threatLine", name = "Threat Line",
		  desc = "In a group fight, a thin bar along the bottom of an enemy's health bar (in the Nameplate Kit's lower rail) fills to the point where it would turn on you: gold while safe, amber when close, red when it is on you. For a tank it turns red when a mob is not on you. Solo it stays away." },
		{ type = "header", name = "Combo Points" },
		{ type = "toggle", key = "comboPoints", name = "Combo Points",
		  desc = "For a rogue, and a druid in Cat Form: your five combo points in a row on the top edge of your target's health bar, empty until you build them. The name moves up a little to make room." },
		{ type = "slider", key = "comboSize", parent = "comboPoints", name = "Combo Point Size", min = 50, max = 150, step = 5,
		  format = function(v) return string.format("%d%%", v) end,
		  desc = "The size of each combo point, as a share of the health bar's height." },
	},
})

local function Active()
	return M.isEnabled and M.db and M.db.bigCC
end

-- the combo points on the target's plate (their section below; the name's
-- lift is read by the crowd-control icon's offset before it)
local Combo = {}
-- the plate names' one table (one-look D6: the band behind the names, Show
-- Names As's cover, the names' watch and the crowd budget; its section below
-- RestoreAll)
local Plate = {}

--------------------------------------------------------------------------------
-- The names' form on nameplates (user, 2026-09-22) is drawn by a cover of
-- ours since one-look D6 (the Plate section below): the game's name text is
-- never written (it was set again after every CompactUnitFrame_UpdateName,
-- that is on every health update of every plate: hard rule 1). The unit
-- frames are Unit Frames'.
--------------------------------------------------------------------------------

-- a plate setup option (NamePlateSetupOptions: plain numbers), else fallback
local function SetupOption(key, fallback)
	local opts = NamePlateSetupOptions
	return (opts and Num(opts[key])) or fallback
end

-- The game's own anchors for a plate's name, `lift` units higher: as the
-- game's UpdateAnchors lays them for its setup style and the plate's
-- name-only state (Blizzard_NamePlateUnitFrame.lua:741-790; the name's own
-- anchors read secret here, so they are laid again from the plain options,
-- never read). Everything is decided before the name's anchors are cleared.
-- A name inside the bar (a name-only one too: the game lays it LEFT/RIGHT
-- inside the container) is left to the game, and so is a name-only answer
-- read secret. The look that holds the name registers with SetNamePlacer;
-- M:PlaceName below is the one seam (the combo points lift the name there).
function M:LayGameName(uf, lift)
	local name = uf and uf.name
	local container = uf and uf.HealthBarsContainer
	local styles = NamePlateConstants and NamePlateConstants.NAME_ANCHOR_STYLES
	if not (name and container and styles) then
		return
	end
	local style = SetupOption("unitNameAnchorStyle", styles.InsideHealthBar)
	if style == styles.InsideHealthBar then
		return
	end
	lift = lift or 0
	-- a name-only plate (a friendly player's): the game's :742, :748-749
	if type(uf.IsShowOnlyName) == "function" then
		local ok, only = pcall(uf.IsShowOnlyName, uf)
		if not ok or Secret(only) then
			return
		end
		if only == true then
			name:ClearAllPoints()
			name:SetJustifyH("CENTER")
			name:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 4, 2 + lift)
			name:SetPoint("BOTTOMRIGHT", container, "TOPRIGHT", -4, 2 + lift)
			return
		end
	end
	local y = SetupOption("healthBarToNameAboveSpacing", 2) + lift
	name:ClearAllPoints()
	if style == styles.CenteredAboveHealthBar then
		name:SetJustifyH("CENTER")
		name:SetPoint("BOTTOM", container, "TOP", 0, y)
		return
	end
	local opts = NamePlateSetupOptions
	name:SetJustifyH(opts and opts.nameJustificationWhenAboveHealthBar or "LEFT")
	name:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, y)
	-- the right end (the game's :772-788): on the level frame while it shows
	-- (it stands in for the game's displayLevelFrame and 'RIGHT' test, whose
	-- anchor reads secret), else on the container's right with the health
	-- text inside the bar (Camelot's setting), else left of the health text
	local lf = uf.PlayerLevelDiffFrame
	local hbText = container.healthBar and container.healthBar.Text
	local inside = opts and opts.healthTextInsideBarWhenNameAboveHealthBar
	if lf and MelloUI.Safe.Call(lf, "IsShown") then
		name:SetPoint("RIGHT", lf, "RIGHT", 0, 0)
	elseif not Secret(inside) and inside == true then
		name:SetPoint("RIGHT", container, "RIGHT", 0, 0)
	elseif hbText then
		name:SetPoint("RIGHT", hbText, "LEFT", -2, 0)
	end
end

-- A plate's name laid again with its lift (the combo points): where the look
-- that holds the name lays it (its placer answers true), else on the game's
-- own anchors. true while that look holds it.
function M:PlaceName(uf)
	local placer = Plate.placer
	if placer and placer(uf) then
		return true
	end
	M:LayGameName(uf, M:NameLift(uf))
	return false
end

-- the look that holds the plates' names (the Nameplate Kit's CentreName):
-- fn(uf) lays the name and answers true while it holds it; nil: none
function M:SetNamePlacer(fn)
	Plate.placer = type(fn) == "function" and fn or nil
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local hookedAuras = setmetatable({}, { __mode = "k" })
local hookedUnitFrames = setmetatable({}, { __mode = "k" })

local function GetUnitFrame(aurasFrame)
	return aurasFrame and aurasFrame:GetParent()
end

-- Vertical offset from the top of the health bar container to the bottom of
-- the crowd-control icon: name row + debuff row (if any) + gap.
local function IsPlainNumber(v)
	return type(v) == "number" and not (issecretvalue and issecretvalue(v))
end

local function ComputeOffset(unitFrame)
	local offset = 0
	local name = unitFrame.name
	if name and name:IsShown() then
		-- The name's measured height can be a secret value (it derives from
		-- the unit's name text); fall back to the font size, then a constant.
		local height = name:GetHeight()
		if not IsPlainNumber(height) then
			local _, size = name:GetFont()
			height = IsPlainNumber(size) and size or 12
		end
		offset = offset + height + 2
	end
	local auras = unitFrame.AurasFrame
	local debuffs = auras and auras.DebuffListFrame
	if debuffs and debuffs:IsShown() then
		local hasChildren = false
		for _, child in ipairs({ debuffs:GetChildren() }) do
			if child:IsShown() then
				hasChildren = true
				break
			end
		end
		if hasChildren then
			local scale = auras.auraItemScale
			if not IsPlainNumber(scale) then
				scale = 1
			end
			offset = offset + BASE_ITEM_SIZE * scale + 2
		end
	end
	-- (the name lifted over the combo points: the icon rises with it)
	return offset + (M.db.ccGap or 0) + M:NameLift(unitFrame)
end

local function AnchorCC(unitFrame)
	local auras = unitFrame and unitFrame.AurasFrame
	if not auras or not unitFrame.HealthBarsContainer then
		return
	end
	local offset = ComputeOffset(unitFrame)
	local cc = auras.CrowdControlListFrame
	if cc then
		-- the list is scaled (ResizeCCList): an offset on it is in its own,
		-- scaled units, so it is given unscaled to land where it is meant to
		local s = cc:GetScale()
		if not IsPlainNumber(s) or s <= 0 then
			s = 1
		end
		cc:ClearAllPoints()
		cc:SetPoint("BOTTOM", unitFrame.HealthBarsContainer, "TOP", 0, offset / s)
	end
	local loc = auras.LossOfControlFrame
	if loc then
		loc:ClearAllPoints()
		loc:SetPoint("BOTTOM", unitFrame.HealthBarsContainer, "TOP", 0, offset)
	end
end

-- The crowd-control icons at the chosen size: the whole LIST is scaled, not
-- its icons. Sized icon by icon, the list's height had to be written into the
-- game's own `fixedHeight` field and its Layout() called from here, so the
-- game's nameplate layout then ran on a value MelloUI wrote -- the one field of
-- ours the game reads (found 2026-09-23, after the study of how the careful
-- addons stay out of taint). Scaling the list is a widget call: every field of
-- the game's stays its own, and the game lays the list out itself.
local function ResizeCCList(auras)
	local cc = auras.CrowdControlListFrame
	if not cc then
		return
	end
	-- the game draws the icons at its own item scale inside the list
	local itemScale = auras.auraItemScale
	if not IsPlainNumber(itemScale) or itemScale <= 0 then
		itemScale = 1
	end
	cc:SetScale((M.db.ccSize or 45) / BASE_ITEM_SIZE / itemScale)
end

local function ResizeLossOfControl(auras)
	local loc = auras.LossOfControlFrame
	if loc then
		loc:SetScale((M.db.ccSize or 45) / BASE_LOC_SIZE)
	end
end

local function StyleAuras(auras)
	if not auras then
		return
	end
	ResizeCCList(auras)
	ResizeLossOfControl(auras)
	AnchorCC(GetUnitFrame(auras))
end

local function HookAuras(auras)
	if not auras or hookedAuras[auras] then
		return
	end
	hookedAuras[auras] = true
	if type(auras.RefreshList) == "function" then
		hooksecurefunc(auras, "RefreshList", function(self, listFrame)
			if not Active() then
				return
			end
			if listFrame == self.CrowdControlListFrame then
				ResizeCCList(self)
			end
			-- Debuff row height changed, so the icon above it may need to move.
			AnchorCC(GetUnitFrame(self))
		end)
	end
	if type(auras.RefreshLossOfControl) == "function" then
		hooksecurefunc(auras, "RefreshLossOfControl", function(self)
			if Active() then
				ResizeLossOfControl(self)
				AnchorCC(GetUnitFrame(self))
			end
		end)
	end
end

local function HookUnitFrame(unitFrame)
	if not unitFrame or hookedUnitFrames[unitFrame] then
		return
	end
	hookedUnitFrames[unitFrame] = true
	-- (UpdateAnchors runs on an add, an option or style change, a name-only
	-- flip and the debuff-padding CVar -- Blizzard_NamePlateUnitFrame.lua:246,
	-- :585, :137 -- never per frame)
	if type(unitFrame.UpdateAnchors) == "function" then
		hooksecurefunc(unitFrame, "UpdateAnchors", function(self)
			-- (the game laid the name again: lifted again over the combo points,
			-- then the plate names' parts on it -- after the lift, so a cover's
			-- justify is read back after the name's last layout)
			Combo.Relaid(self)
			Plate.Relaid(self)
			if Active() then
				AnchorCC(self)
			end
		end)
	end
	-- (the plate names: the realm display -- a unit set, a friend or player
	-- change, the realm-name CVar, :140 :164 :275 :315 :630-644, never per
	-- update -- and the unit cleared on a removal, ClearUnit: never per update)
	if type(unitFrame.UpdateNameRealmDisplay) == "function" then
		hooksecurefunc(unitFrame, "UpdateNameRealmDisplay", Plate.OnRealm)
	end
	if type(unitFrame.OnUnitCleared) == "function" then
		hooksecurefunc(unitFrame, "OnUnitCleared", Plate.Cleared)
	end
end

local function StyleUnitFrame(unitFrame)
	if not unitFrame or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then
		return
	end
	HookUnitFrame(unitFrame)
	HookAuras(unitFrame.AurasFrame)
	StyleAuras(unitFrame.AurasFrame)
end

local function StylePlate(plate)
	if plate and not (plate.IsForbidden and plate:IsForbidden()) then
		StyleUnitFrame(plate.UnitFrame)
	end
end

local function ApplyAll()
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			StylePlate(plate)
		end
	end
end

-- The game's own gap between the health bars and its crowd-control lists:
-- 5 px, plus the level frame's width and gap while that frame shows on the
-- bars' right (the game's UpdateAnchors, Blizzard_NamePlateUnitFrame.lua).
-- Every read can be secret on a plate: then the plain 5 px.
local function GameCCGap(unitFrame)
	local level = unitFrame.PlayerLevelDiffFrame
	if not level then
		return 5
	end
	local okS, shown = pcall(level.IsShown, level)
	if not okS or Secret(shown) or not shown then
		return 5
	end
	local okP, _, _, relativePoint, x = pcall(level.GetPoint, level, 1)
	local okW, width = pcall(level.GetWidth, level)
	if not (okP and okW) or Secret(relativePoint) or relativePoint ~= "RIGHT"
		or not IsPlainNumber(x) or not IsPlainNumber(width) then
		return 5
	end
	return 5 + width + math.abs(x)
end

-- Put back what MelloUI changed: the lists' scales and the game's own anchor
-- for them. Never by running the game's UpdateAnchors from here: a layout
-- function of the game's, run by an addon, taints the plate (hard rule 1).
-- The game lays the plate again itself whenever it next needs to (a new
-- unit on it, an option), and the hook above then stays out (not Active).
local function RestoreAll()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unitFrame = plate and not (plate.IsForbidden and plate:IsForbidden()) and plate.UnitFrame
		local auras = unitFrame and unitFrame.AurasFrame
		local bars = unitFrame and unitFrame.HealthBarsContainer
		if auras then
			local scale = IsPlainNumber(auras.auraItemScale) and auras.auraItemScale or 1
			local gap = bars and GameCCGap(unitFrame)
			local cc = auras.CrowdControlListFrame
			if cc then
				cc:SetScale(1)
				if bars then
					cc:ClearAllPoints()
					cc:SetPoint("LEFT", bars, "RIGHT", gap, 0)
				end
			end
			local loc = auras.LossOfControlFrame
			if loc then
				loc:SetScale(scale)
				if bars then
					loc:ClearAllPoints()
					loc:SetPoint("LEFT", bars, "RIGHT", gap, 0)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The plate names (one-look D6): the soft band behind each name above its
-- bar, as long as the name (the user's 2026-09-25 plate band; 2026-10-15: bar
-- plates only, none on friendly players' name-only plates, part of Nameplate
-- Tweaks), and Show Names As as a cover, never a write on the game's name.
-- The game sets a plate's name on every health update (CompactUnitFrame.lua
-- :737, :827-891: UpdateName -- SetText :858, its SetVertexColor, Show :890 /
-- Hide :842); UNIT_NAME_UPDATE only marks the health dirty (:125-127). Each
-- add runs the name's SetFontObject (Blizzard_NamePlateUnitFrame.lua:225) and
-- UpdateAnchors (:246), then SetUpFrame's UpdateAll (Blizzard_NamePlateBase.lua
-- :29-35, :62-70; Blizzard_NamePlateUnitFrame.lua:213-247); a name-only plate
-- is laid at :561-587; the hit test hangs on the name's TOPLEFT (:589-612); the
-- health text follows the name's IsShown (Blizzard_NamePlateHealthBar.lua
-- :46-73). So the game's name is never shown, hidden or written here: only
-- its glyphs are hidden (Plate.HIDE) while a cover of ours shows the form.
--   The band: MelloUI.Shade's soft band (the 09-25 look), anchored once on an
--   unseen measure of the name (Shade:Measure: the engine sizes it to the
--   text, nothing is read), fed on events only -- our NAME_PLATE_UNIT_ADDED,
--   UNIT_NAME_UPDATE then the game's next Show, the plate's
--   UpdateNameRealmDisplay. No SetText hook.
--   The watch: Show, Hide and SetShown on the name, the only Lua run per game
--   update (a table read or two when nothing changed).
--   The cover: Shade:Cover on the name's rect in its look; the game's glyphs
--   hidden on an add, after its UpdateAnchors and after a Font Style change,
--   never per update; undone when the plate's unit is cleared
--   (OnUnitCleared, a removal), so a pooled frame never carries a hidden name
--   to its next unit, nor to the Settings' preview plate (which takes a frame
--   from the same pool without our add).
--   The crowd: one budget, MAKE_PER_FRAME plates a frame, and one hold queue
--   (the next-frame queue), shared with the Nameplate Kit's Whole plate partners.
-- Nothing is made at login or per event; every part is Core/Shade.lua's; no
-- size or position is read here.
--------------------------------------------------------------------------------

Plate.MAKE_PER_FRAME = 6
-- the band's middle 4 past the text's ends and 5 above and below
Plate.PAD_X, Plate.PAD_Y = 4, 5
-- The measure stands on the name's BOTTOM, whose bottom edge every layout sets
-- (Above's BOTTOMLEFT :770, Classic's BOTTOM :767, name-only :748-749, the
-- kit's CentreName): with the name's own font height its box is the name's
-- line. Its middle is the glyphs' middle while the name is centred (justify
-- CENTER: Camelot's Overrides L3 for Above, the name-only and Classic layouts
-- and every placer), the assumption here (the base game's Above default is
-- LEFT). 'CENTER' is the one-constant fallback.
Plate.POINT = "BOTTOM"
Plate.OWNER = "Nameplates names"
Plate.KEY = "Nameplates plate parts"
Plate.MODES = { name = true, plate = true, off = true }
-- the band's look (Shade:Band's options, read once a band; alpha set to the
-- soft text look's at each making: a readability band, as the notice's)
Plate.LOOK = { colour = "innerPanel", feather = 20, layer = "BACKGROUND", sublevel = -8, pixel = true }
Plate.MEASURE = { pixel = true, smooth = true }
Plate.COVER = { pixel = true }
-- How the game's glyphs are hidden under a cover: "alpha" -- the user's probe
-- B, 2026-10-15: SetAlpha(0) on a plate's name holds while the mob is hit, the
-- game's per-update SetText / SetVertexColor / Show never set it back;
-- "gradient" (SetAlphaGradient); false: no cover (Show Names As then stays
-- off the plates)
Plate.HIDE = "alpha"
Plate.GRADIENT_START, Plate.GRADIENT_LENGTH = 0, 1
-- by unit frame (weak keys: nothing written on the game's frames)
Plate.bandOf = setmetatable({}, { __mode = "k" })      -- its band
Plate.measureOf = setmetatable({}, { __mode = "k" })   -- its name's measure
Plate.measured = setmetatable({}, { __mode = "k" })    -- true: the measure holds the name's text
Plate.textOf = setmetatable({}, { __mode = "k" })      -- the last plain text fed
Plate.formOf = setmetatable({}, { __mode = "k" })      -- the cover's form (plain or secret)
Plate.at = setmetatable({}, { __mode = "k" })          -- true: met (in Plate.plates)
Plate.live = setmetatable({}, { __mode = "k" })        -- true: holds a unit, seen while on
Plate.slotAt = setmetatable({}, { __mode = "k" })      -- the frame's time its making slot was taken
Plate.jobs = setmetatable({}, { __mode = "k" })        -- its held jobs (one small array, made once)
Plate.queued = setmetatable({}, { __mode = "k" })      -- true: in the hold queue
-- by name region
Plate.watched = setmetatable({}, { __mode = "k" })     -- true: its 3 watch hooks are on
Plate.ownerOf = setmetatable({}, { __mode = "k" })     -- its unit frame
Plate.shown = setmetatable({}, { __mode = "k" })       -- shown by the game as last seen
Plate.stale = setmetatable({}, { __mode = "k" })       -- true: fed again at the game's next Show
Plate.coverOf = setmetatable({}, { __mode = "k" })     -- its cover (made once)
Plate.coverOn = setmetatable({}, { __mode = "k" })     -- its cover while it covers the name
Plate.coverShown = setmetatable({}, { __mode = "k" })  -- true: its cover shown (ours, never read back)
Plate.hidden = setmetatable({}, { __mode = "k" })      -- true: its glyphs hidden by us
Plate.tinted = setmetatable({}, { __mode = "k" })      -- true: its SetVertexColor hook is on
Plate.plates = {}      -- every plate frame met, once
Plate.followers = {}   -- FollowName's functions
Plate.queue, Plate.queueN, Plate.queueFrom = {}, 0, 1
Plate.madeCount = 0
Plate.listening = false

-- the names' part runs while the module does
function Plate.On()
	return (M.isEnabled and M.db ~= nil) and true or false
end

-- Name Shade's mode: NameplatePanel's key until it moves (stage G). Read raw
-- first (MelloUI.db.modules.NameplatePanel: the table GetModuleDB hands that
-- module, Core.lua), then that module's own db (the test worlds).
function Plate.Mode()
	local db = MelloUI.db
	local all = type(db) == "table" and db.modules
	local own = type(all) == "table" and all.NameplatePanel
	local mode = type(own) == "table" and own.nameShade or nil
	if mode == nil then
		local panel = MelloUI:GetModule("NameplatePanel")
		local pdb = panel and panel.db
		mode = type(pdb) == "table" and pdb.nameShade or nil
	end
	return Plate.MODES[mode] and mode or "name"
end

-- the names stand above the bars (not inside them)
function Plate.Above()
	local styles = NamePlateConstants and NamePlateConstants.NAME_ANCHOR_STYLES
	if type(styles) ~= "table" or styles.InsideHealthBar == nil then
		return false
	end
	return SetupOption("unitNameAnchorStyle", styles.InsideHealthBar) ~= styles.InsideHealthBar
end

-- a name-only plate (an answer read secret or refused counts as one: no band)
function Plate.NameOnly(uf)
	local fn = uf.IsShowOnlyName
	if type(fn) ~= "function" then
		return false
	end
	local ok, only = pcall(fn, uf)
	if not ok or Secret(only) then
		return true
	end
	return only == true
end

-- the band is wanted on this plate: the module on, Name Shade not Off, the
-- name above a bar
function Plate.Want(uf)
	return Plate.On() and Plate.Mode() ~= "off" and Plate.Above() and not Plate.NameOnly(uf)
end

-- a form other than the full name is chosen (Show Names As)
function Plate.FormWanted()
	if not Plate.On() then
		return false
	end
	local f = M.db.nameFormat
	return f ~= nil and f ~= "both"
end

-- the frame that draws the name: the band lies under it, the cover beside it
function Plate.Host(uf)
	local name = uf.name
	local ok, host = pcall(name.GetParent, name)
	if ok and type(host) == "table" and host.CreateTexture then
		return host
	end
	return uf
end

-- The watch: the name's show and hide (once per name, kept as the plates
-- recycle). Made by Make, Cover and M:WatchName only.
function Plate.Watch(uf)
	local name = uf and uf.name
	if not name or Plate.watched[name] then
		return
	end
	Plate.watched[name] = true
	Plate.ownerOf[name] = uf
	-- (asked for secret first: a secret or refused answer counts as shown)
	local ok, v = pcall(name.IsShown, name)
	Plate.shown[name] = (not ok or Secret(v) or v) and true or false
	hooksecurefunc(name, "Show", Plate.OnShow)
	hooksecurefunc(name, "Hide", Plate.OnHide)
	hooksecurefunc(name, "SetShown", Plate.OnSetShown)
end

-- every function FollowName gave, with the plate (no garbage)
function Plate.Follow(uf)
	local list = Plate.followers
	for i = 1, #list do
		list[i](uf)
	end
end

-- the name shown or hidden by the game: the band, the cover and the
-- followers on a change only (every health update Shows the name again)
function Plate.Shown(name, v)
	if Plate.shown[name] == v then
		return
	end
	Plate.shown[name] = v
	local uf = Plate.ownerOf[name]
	if not uf then
		return
	end
	if Plate.On() then
		Plate.Sync(uf)
		Plate.CoverShow(uf)
	end
	-- (the kit's marks follow the name with the module off too)
	Plate.Follow(uf)
end

Plate.OnShow = Perf.Shared("Show on a nameplate's name (the names' watch)", function(name)
	if Plate.stale[name] then
		Plate.stale[name] = nil
		Plate.Renamed(Plate.ownerOf[name])
	end
	Plate.Shown(name, true)
end)
Plate.OnHide = Perf.Shared("Hide on a nameplate's name (the names' watch)", function(name)
	Plate.Shown(name, false)
end)
Plate.OnSetShown = Perf.Shared("SetShown on a nameplate's name (the names' watch)", function(name, v)
	-- (asked for secret first: a secret answer counts as shown)
	Plate.Shown(name, Secret(v) or (v and true or false))
end)

-- The name's text to its measure (the form while the cover shows it): a
-- secret handed on, never compared; a plain one only when it changed
function Plate.Feed(uf)
	local m = Plate.measureOf[uf]
	if not m then
		return
	end
	local name = uf.name
	local text
	if Plate.coverOn[name] then
		text = Plate.formOf[uf]
	else
		local ok, t = pcall(name.GetText, name)
		if not ok then
			Plate.measured[uf] = false
			Plate.Sync(uf)
			return
		end
		text = t
	end
	if not Secret(text) then
		if text == nil or text == "" then
			Plate.measured[uf], Plate.textOf[uf] = false, nil
			Plate.Sync(uf)
			return
		end
		if Plate.measured[uf] and Plate.textOf[uf] == text then
			Plate.Sync(uf)
			return
		end
	end
	local taken = MelloUI.Shade:MeasureText(m, text)
	Plate.measured[uf] = taken
	Plate.textOf[uf] = (taken and not Secret(text)) and text or nil
	Plate.Sync(uf)
end

-- a name changed (UNIT_NAME_UPDATE, then the game's Show): its form and text
function Plate.Renamed(uf)
	if uf and Plate.On() and Plate.live[uf] then
		Plate.Cover(uf)
		Plate.Feed(uf)
	end
end

-- The crowd's budget (review, 2026-09-25: a reload among many plates made
-- every plate's parts in one frame): MAKE_PER_FRAME plates a frame (GetTime:
-- the frame's time) get their parts made; one plate takes one slot however
-- many of its parts are made in that frame. The rest wait in one queue, swept
-- on the next frames (Plate.Later). Showing, hiding and feeding what is
-- there already are never held back.
function Plate.MayMake(uf)
	local now = GetTime()
	if Plate.slotAt[uf] == now then
		return true
	end
	if Plate.madeAt ~= now then
		Plate.madeAt, Plate.madeCount = now, 0
	end
	if Plate.madeCount >= Plate.MAKE_PER_FRAME then
		return false
	end
	Plate.madeCount = Plate.madeCount + 1
	Plate.slotAt[uf] = now
	return true
end

-- fn(uf) run once in a later frame's sweep (the plate queued once, the job
-- once; no table made per hold)
function Plate.Hold(uf, fn)
	local list = Plate.jobs[uf]
	if not list then
		list = {}
		Plate.jobs[uf] = list
	end
	local have = false
	for i = 1, #list do
		if list[i] == fn then
			have = true
			break
		end
	end
	if not have then
		list[#list + 1] = fn
	end
	if not Plate.queued[uf] then
		Plate.queued[uf] = true
		Plate.queueN = Plate.queueN + 1
		Plate.queue[Plate.queueN] = uf
	end
	Plate.Later()
end

-- the sweep on the next frame: the core's next-frame queue (Core/Schedule.lua
-- since one look D1; the kit's old name where that is not loaded)
function Plate.Later()
	local queue = MelloUI.Schedule or MelloUI.Kit
	queue:NextFrame(Plate.KEY, Plate.Sweep)
end

-- the held plates in order, up to the ones queued when it started, until
-- this frame's slots are spent (then on from there the next frame); a plate's
-- jobs run once each in order (one held again is queued anew); drained, the
-- queue starts again at its first place
function Plate.Sweep(key)
	if key ~= Plate.KEY then
		return
	end
	local last, i = Plate.queueN, Plate.queueFrom
	while i <= last do
		local uf = Plate.queue[i]
		if uf then
			if not Plate.MayMake(uf) then
				Plate.queueFrom = i
				Plate.Later()
				return
			end
			Plate.queue[i], Plate.queued[uf] = nil, nil
			local list = Plate.jobs[uf]
			for _ = 1, list and #list or 0 do
				local fn = table.remove(list, 1)
				fn(uf)
			end
		end
		i = i + 1
	end
	Plate.queueFrom = i
	if Plate.queueFrom > Plate.queueN then
		Plate.queueN, Plate.queueFrom = 0, 1
	end
end

-- a held plate seen again, while it still holds its unit
function Plate.Retry(uf)
	if Plate.live[uf] then
		Plate.Seen(uf)
	end
end

-- The band and the name's measure, made once per plate frame (with a slot)
-- and kept as the plates recycle; the band anchored once on the measure
function Plate.Make(uf)
	Plate.Watch(uf)
	local Shade = MelloUI.Shade
	local host = Plate.Host(uf)
	local m = Plate.measureOf[uf] or Shade:Measure(host, uf.name, Plate.POINT, Plate.MEASURE)
	Plate.measureOf[uf] = m
	Plate.LOOK.alpha = Shade.TEXT.alpha
	local band = Shade:Band(host, Plate.LOOK)
	if not band then
		return
	end
	Plate.bandOf[uf] = band
	band:SetShown(false)
	if m then
		band:Anchor(m, Plate.PAD_X, Plate.PAD_Y)
	end
	Plate.measured[uf] = false
end

-- the band shown while the plate holds a unit, the band is wanted, the
-- measure holds the name's text and the game shows the name (on a change only)
function Plate.Sync(uf)
	local band = Plate.bandOf[uf]
	if not band then
		return
	end
	local want = (Plate.live[uf] and Plate.measured[uf] == true and Plate.shown[uf.name] == true
		and Plate.Want(uf)) and true or false
	if band:IsShown() ~= want then
		band:SetShown(want)
	end
end

-- The form on this plate (Show Names As), or nil while the game's full name
-- stands: a secret returned as it is; the full name (no surname) gives nil.
-- (Each asked for secret first: the form and the full name come from two
-- calls, NameUtil's, and their secrecy can differ.)
function Plate.Form(uf)
	if not Plate.FormWanted() then
		return nil
	end
	local unit = uf.unit
	if Secret(unit) or type(unit) ~= "string" then
		return nil
	end
	local text = MelloUI:UnitNameAs(unit, M.db.nameFormat)
	if not Secret(text) and text == nil then
		return nil
	end
	local full = MelloUI:UnitNameAs(unit, "both")
	if Secret(text) or Secret(full) or text ~= full then
		return text
	end
	return nil
end

-- the game's glyphs hidden under the cover (true when it took) and back
function Plate.Hide(name)
	local how = Plate.HIDE
	if how == "alpha" then
		return (pcall(name.SetAlpha, name, 0))
	elseif how == "gradient" then
		return (pcall(name.SetAlphaGradient, name, Plate.GRADIENT_START, Plate.GRADIENT_LENGTH))
	end
	return false
end

function Plate.Reveal(name)
	local how = Plate.HIDE
	if how == "alpha" then
		pcall(name.SetAlpha, name, 1)
	elseif how == "gradient" then
		if type(name.ClearAlphaGradient) == "function" then
			pcall(name.ClearAlphaGradient, name)
		else
			pcall(name.SetAlphaGradient, name, 1024, 1)
		end
	end
end

-- The cover on a plate's name with its form (`form` given, or asked now);
-- `again`: the glyphs hidden again (an add, a layout). No form, or no way to
-- hide the glyphs: uncovered. The cover is made once per name (with a slot:
-- else held), its colour copied from the name when it first covers it and
-- then at each of the game's SetVertexColor (hooked once per name)
function Plate.Cover(uf, again, form)
	local name = uf.name
	if not Secret(form) and form == nil then
		form = Plate.Form(uf)
	end
	if (not Secret(form) and form == nil) or not Plate.HIDE then
		Plate.Uncover(uf)
		return
	end
	local fs = Plate.coverOf[name]
	if not fs then
		if not Plate.MayMake(uf) then
			Plate.Hold(uf, Plate.Recover)
			return
		end
		fs = MelloUI.Shade:Cover(Plate.Host(uf), name, Plate.COVER)
		if not fs then
			return
		end
		Plate.coverOf[name] = fs
		Plate.coverShown[name] = true
		Plate.Watch(uf)
		if not Plate.tinted[name] then
			Plate.tinted[name] = true
			hooksecurefunc(name, "SetVertexColor", Plate.OnColour)
		end
	end
	Plate.formOf[uf] = form
	MelloUI.Shade:CoverText(fs, form)
	if again or not Plate.hidden[name] then
		Plate.hidden[name] = Plate.Hide(name) or nil
	end
	if Plate.hidden[name] then
		if not Plate.coverOn[name] then
			Plate.coverOn[name] = fs
			-- (the game's colour as it is now, handed on untouched: a secret too)
			local ok, r, g, b, a = pcall(name.GetVertexColor, name)
			if ok then
				MelloUI.Shade:CoverColour(fs, r, g, b, a)
			end
		end
	else
		-- (refused: the game's name stays as it is, uncovered)
		Plate.coverOn[name] = nil
	end
	Plate.CoverShow(uf)
end

-- a held cover made, then the measure on its form
function Plate.Recover(uf)
	if Plate.live[uf] and Plate.On() then
		Plate.Cover(uf, true)
		Plate.Feed(uf)
	end
end

-- the cover away and the game's glyphs back (the band then on the full name)
function Plate.Uncover(uf)
	local name = uf.name
	local was = Plate.coverOn[name]
	Plate.coverOn[name] = nil
	Plate.formOf[uf] = nil
	Plate.CoverShow(uf)
	if Plate.hidden[name] then
		Plate.Reveal(name)
		Plate.hidden[name] = nil
	end
	if was then
		Plate.Feed(uf)
	end
end

-- the cover shown while it covers the name and the game shows the name (on a
-- change only; our own state, never read back)
function Plate.CoverShow(uf)
	local name = uf.name
	local fs = name and Plate.coverOf[name]
	if not fs then
		return
	end
	local want = (Plate.coverOn[name] ~= nil and Plate.shown[name] == true) and true or false
	if Plate.coverShown[name] ~= want then
		Plate.coverShown[name] = want
		fs:SetShown(want)
	end
end

-- the game's colour on a covered name (every health update, on names that
-- ever had a cover): handed to the cover, set there only on a change
Plate.OnColour = Perf.Shared("SetVertexColor on a covered nameplate name", function(name, r, g, b, a)
	local fs = Plate.coverOn[name]
	if fs then
		MelloUI.Shade:CoverColour(fs, r, g, b, a)
	end
end)

-- after a Font Style copy of a cover (Shade's RefontAll, a frame after the
-- change; never per update): the glyphs hidden again, or uncovered where
-- that is refused
function Plate.Refont(_, name)
	if Plate.coverOn[name] and Plate.On() then
		Plate.hidden[name] = Plate.Hide(name) or nil
		local uf = Plate.ownerOf[name]
		if not Plate.hidden[name] then
			-- (refused now after an earlier hide: the glyphs back here, since
			-- Uncover reveals only what it knows is hidden)
			Plate.Reveal(name)
			if uf then
				Plate.Uncover(uf)
			end
		end
	end
end
Plate.COVER.refont = Plate.Refont

-- The plate pass: a plate's parts as the settings want them, made with a
-- slot (else held), the measure fed now or at the name's next Show
function Plate.Seen(uf)
	local name = uf and uf.name
	if not name then
		return
	end
	if uf.IsForbidden then
		local okF, forbidden = pcall(uf.IsForbidden, uf)
		if not okF or Secret(forbidden) or forbidden then
			return
		end
	end
	if not Plate.at[uf] then
		Plate.at[uf] = true
		Plate.plates[#Plate.plates + 1] = uf
	end
	if not Plate.On() then
		Plate.Off(uf)
		return
	end
	Plate.live[uf] = true
	-- (every plate's layout hook, first: a style change or a name-only flip
	-- makes the band on its UpdateAnchors)
	HookUnitFrame(uf)
	local want = Plate.Want(uf)
	local form = Plate.Form(uf)
	local formOn = Secret(form) or form ~= nil
	if not (want or formOn or Plate.bandOf[uf] or Plate.coverOf[name]) then
		return
	end
	local needBand = want and not Plate.bandOf[uf]
	local needCover = Plate.HIDE and formOn and not Plate.coverOf[name]
	if (needBand or needCover) and not Plate.MayMake(uf) then
		-- (a cover made already goes on now, only the band waits: a pooled
		-- frame never shows the full name until the sweep)
		if not needCover then
			Plate.Cover(uf, true, form)
		end
		-- (a band there already is fed now: it never shows the last unit's text)
		Plate.Feed(uf)
		Plate.Hold(uf, Plate.Retry)
		Plate.Sync(uf)
		Plate.CoverShow(uf)
		return
	end
	if needBand then
		Plate.Make(uf)
	end
	Plate.Cover(uf, true, form)
	if Plate.bandOf[uf] or Plate.coverOn[name] then
		if Plate.shown[name] then
			Plate.Feed(uf)
		else
			Plate.stale[name] = true
		end
	end
	Plate.Sync(uf)
end

-- a plate's band hidden and its cover off (the module off, the unit cleared)
function Plate.Off(uf)
	local band = Plate.bandOf[uf]
	if band and band:IsShown() then
		band:SetShown(false)
	end
	Plate.Uncover(uf)
end

-- the plate's unit cleared (the game's ClearUnit on a removal,
-- Blizzard_NamePlateBase.lua:42-47 -> OnUnitCleared; never per update): the
-- cover off and the glyphs back, the band hidden, the text forgotten
Plate.Cleared = Perf.Shared("OnUnitCleared on a nameplate (the names' undo)", function(uf)
	if not (uf and Plate.at[uf]) then
		return
	end
	Plate.live[uf] = nil
	if uf.name then
		Plate.stale[uf.name] = nil
	end
	Plate.Off(uf)
	Plate.measured[uf], Plate.textOf[uf] = false, nil
end)

-- our NAME_PLATE_UNIT_ADDED (after the game's driver and its post-hooks): the
-- one core plate-add path
function Plate.Added(plate)
	local uf = type(plate) == "table" and plate.UnitFrame
	if type(uf) == "table" then
		Plate.Seen(uf)
	end
end

-- every plate shown now, the ones put away hidden, the event as wanted
function Plate.All()
	local ok, list = pcall(C_NamePlate.GetNamePlates)
	if ok and type(list) == "table" then
		for _, base in ipairs(list) do
			if type(base) == "table" and base.UnitFrame then
				Plate.Seen(base.UnitFrame)
			end
		end
	end
	local plates = Plate.plates
	for i = 1, #plates do
		Plate.Sync(plates[i])
		Plate.CoverShow(plates[i])
	end
	Plate.Listen()
end

-- the module off (or restarting: OnDisable runs with isEnabled still true,
-- Core's RestartEach): every plate's parts away
function Plate.Stop()
	local plates = Plate.plates
	for i = 1, #plates do
		Plate.live[plates[i]] = nil
		Plate.Off(plates[i])
	end
	Plate.Listen()
end

-- after the game laid a plate out (UpdateAnchors only): the measure in the
-- name's new font; a covered name's cover too, its glyphs hidden again (the
-- layout's SetFontObject may have put them back); a band now wanted made (a
-- style change, a name-only flip). An existing band is not fed here: during
-- an add the text is still the last unit's (Seen feeds after the game's
-- UpdateAll)
function Plate.Relaid(uf)
	if not Plate.at[uf] then
		return
	end
	local m = Plate.measureOf[uf]
	if m then
		MelloUI.Shade:MeasureFont(m)
	end
	if not (Plate.On() and Plate.live[uf]) then
		return
	end
	local name = uf.name
	local fs = Plate.coverOn[name]
	if fs then
		MelloUI.Shade:CoverFont(fs)
		Plate.hidden[name] = Plate.Hide(name) or nil
		if not Plate.hidden[name] then
			-- (refused now after an earlier hide: the glyphs back, as in Refont)
			Plate.Reveal(name)
			Plate.Uncover(uf)
		end
	end
	if Plate.Want(uf) and not Plate.bandOf[uf] then
		if Plate.MayMake(uf) then
			Plate.Make(uf)
			if Plate.shown[name] then
				Plate.Feed(uf)
			else
				Plate.stale[name] = true
			end
		else
			Plate.Hold(uf, Plate.Retry)
		end
	end
	Plate.Sync(uf)
end

-- the realm display changed (the game's UpdateNameRealmDisplay, whose own
-- UpdateName has set the text): the measure fed
Plate.OnRealm = Perf.Shared("UpdateNameRealmDisplay on a nameplate (the names' text)", function(uf)
	local name = uf and uf.name
	if not (name and Plate.On() and Plate.live[uf] and (Plate.bandOf[uf] or Plate.coverOn[name])) then
		return
	end
	if Plate.shown[name] then
		Plate.Feed(uf)
	else
		Plate.stale[name] = true
	end
end)

-- UNIT_NAME_UPDATE on a plate's unit: the game sets the text at its next
-- UpdateName and Shows the name; that Show feeds it (OnShow)
function Plate.OnNameUpdate(unit)
	if Secret(unit) or type(unit) ~= "string" or unit:sub(1, 9) ~= "nameplate" then
		return
	end
	local ok, base = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	local uf = ok and type(base) == "table" and base.UnitFrame
	if type(uf) == "table" and Plate.live[uf] and uf.name then
		Plate.stale[uf.name] = true
	end
end

-- Name Shade changed (the bus's 'setting': its key is NameplatePanel's)
function Plate.OnSetting(module, key)
	if module == "NameplatePanel" and key == "nameShade" and Plate.On() then
		Plate.All()
	end
end

-- UNIT_NAME_UPDATE while a band or a form is wanted (on a change only)
function Plate.Listen()
	local want = (Plate.On() and (Plate.Mode() ~= "off" or Plate.FormWanted())) and true or false
	if want == Plate.listening or not Plate.frame then
		return
	end
	Plate.listening = want
	if want then
		Plate.frame:RegisterEvent("UNIT_NAME_UPDATE")
	else
		Plate.frame:UnregisterEvent("UNIT_NAME_UPDATE")
	end
end

-- the bus's 'setting', once
function Plate.Start()
	if not Plate.started then
		Plate.started = true
		MelloUI:On("setting", Plate.OnSetting, Plate.OWNER)
	end
end

-- For the look that holds the names (the Nameplate Kit) and the dumps: the
-- name's watch (works with the module off), the frame that draws the name,
-- whether the game shows it, a function told of each show or hide change
-- (fn(uf), appended once), the crowd's budget and hold queue, and whether a
-- cover is on
function M:WatchName(uf)
	Plate.Watch(uf)
end

function M:NameHost(uf)
	return Plate.Host(uf)
end

function M:NameShownOn(uf)
	return (uf and uf.name and Plate.shown[uf.name]) or false
end

function M:FollowName(fn)
	if type(fn) ~= "function" then
		return
	end
	local list = Plate.followers
	for i = 1, #list do
		if list[i] == fn then
			return
		end
	end
	list[#list + 1] = fn
end

function M:MayMakeOnPlate(uf)
	return Plate.MayMake(uf)
end

function M:HoldPlate(uf, fn)
	Plate.Hold(uf, fn)
end

function M:IsNameCovered(uf)
	return uf ~= nil and uf.name ~= nil and Plate.coverOn[uf.name] ~= nil
end

--------------------------------------------------------------------------------
-- Quest icon
--------------------------------------------------------------------------------

local QUEST_ICON_TEXTURE = "Interface\\GossipFrame\\AvailableQuestIcon"
local LINE_QUEST_OBJECTIVE = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective) or 8
local LINE_QUEST_TITLE = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle) or 17

local function QuestActive()
	return M.isEnabled and M.db and M.db.questIcon
end

-- Does the unit's tooltip list an unfinished objective of one of our quests?
local function IsQuestTarget(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return false
	end
	local ok, result = pcall(function()
		if UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then
			return false
		end
		local data = C_TooltipInfo.GetUnit(unit)
		if not data or type(data.lines) ~= "table" then
			return false
		end
		local sawTitle = false
		local sawObjective = false
		for _, line in ipairs(data.lines) do
			if line.type == LINE_QUEST_TITLE then
				sawTitle = true
			elseif line.type == LINE_QUEST_OBJECTIVE then
				sawObjective = true
				local text = line.leftText
				if type(text) == "string" then
					local cur, total = text:match("(%d+)%s*/%s*(%d+)")
					if cur and total then
						if tonumber(cur) < tonumber(total) then
							return true
						end
					else
						local pct = text:match("(%d+)%%")
						if pct then
							if tonumber(pct) < 100 then
								return true
							end
						else
							return true
						end
					end
				else
					return true
				end
			end
		end
		-- A quest title without any objective lines still means the mob is
		-- relevant. If objectives were listed and none was unfinished (6/6,
		-- 100%), the quest is done for this mob and the icon must go.
		return sawTitle and not sawObjective
	end)
	return ok and result == true
end

-- each plate's quest icon, keyed by the game's unit frame: kept here, never
-- as a key on the game's frame (hard rule 1); weak, so a frame the game
-- drops takes its entry along
local questIcons = setmetatable({}, { __mode = "k" })

-- the Nameplate Kit's left gem cap on a plate it dresses (MelloUI.Kept.bracketLeftOf,
-- set by NameplatePanel), or nil
local function BracketLeft(unitFrame)
	local caps = MelloUI.Kit and MelloUI.Kit.bracketLeftOf
	return caps and caps[unitFrame]
end

local function GetQuestIcon(unitFrame)
	local icon = questIcons[unitFrame]
	if not icon then
		-- on a layer frame above the health bar: the unit frame's own regions
		-- draw under its children, so the Nameplate Kit's gem cap (a region
		-- of the bar, standing outside it) hid the icon (user, 2026-09-23)
		local layer = CreateFrame("Frame", nil, unitFrame)
		layer:SetAllPoints(unitFrame)
		layer:EnableMouse(false)
		local hb = unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar
		local ok, level = pcall(function() return (hb or unitFrame):GetFrameLevel() end)
		if ok and IsPlainNumber(level) then
			layer:SetFrameLevel(level + 5)
		end
		icon = layer:CreateTexture(nil, "OVERLAY")
		icon:SetTexture(QUEST_ICON_TEXTURE)
		icon:Hide()
		questIcons[unitFrame] = icon
	end
	local size = M.db.questIconSize or 22
	icon:SetSize(size, size)
	icon:ClearAllPoints()
	-- beside the Nameplate Kit's left gem cap while it dresses the plate
	-- (the cap stands outside the bar), else beside the raid mark / bar
	local anchor = BracketLeft(unitFrame) or unitFrame.RaidTargetFrame or unitFrame.HealthBarsContainer
	if anchor then
		icon:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
	end
	return icon
end

local function GetPlateUnit(plate)
	local unitFrame = plate.UnitFrame
	local unit = (unitFrame and unitFrame.unit) or plate.namePlateUnitToken or plate.unitToken
	if not unit and plate.GetUnit then
		local ok, value = pcall(plate.GetUnit, plate)
		if ok then
			unit = value
		end
	end
	return unit
end

local function UpdateQuestIcon(plate)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then
		return
	end
	local unitFrame = plate.UnitFrame
	if not unitFrame then
		return
	end
	if not QuestActive() then
		if questIcons[unitFrame] then
			questIcons[unitFrame]:Hide()
		end
		return
	end
	local unit = GetPlateUnit(plate)
	local show = unit and IsQuestTarget(unit)
	local icon = GetQuestIcon(unitFrame)
	icon:SetShown(show and true or false)
end

local function UpdateAllQuestIcons()
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			UpdateQuestIcon(plate)
		end
	end
end

local questRescanPending = false

local function ScheduleQuestRescan()
	if questRescanPending then
		return
	end
	questRescanPending = true
	C_Timer.After(0.3, function()
		questRescanPending = false
		if QuestActive() then
			UpdateAllQuestIcons()
		end
	end)
end

--------------------------------------------------------------------------------
-- The threat line (0.16.0; user, 2026-09-30: threat_sketch look D without the
-- number, pulled into 0.16.0): a thin bar along an enemy plate's health bar
-- filling to the pull (MelloUI.Threat, Core/Threat.lua: one reader with the
-- Threat widget), gold while safe, amber when close, red when the mob is on
-- you -- for a tank, red when it is not. Only in a group fight, only on the
-- plates of mobs whose list the player is on. Where the game keeps the numbers
-- secret the bar takes the secret value itself (StatusBar:SetValue draws it;
-- nothing here reads it) and its colour follows the state while that is open,
-- gold otherwise (user, 2026-09-30: "i dont want anything else, just the
-- progress bar": the "!" went). Made on a plate's first threat (a crowd out of a fight makes none),
-- kept in a table of this file's (nothing written on the game's frame).
-- UNIT_THREAT_LIST_UPDATE lays the plate it names; UNIT_THREAT_SITUATION_UPDATE,
-- the fight's start and end every plate. A StatusBar: the engine fills it
-- (every size under a plate reads secret). Where it lies (user, 2026-09-30:
-- pick C of threat_sketch/threat_castbar_looks.jpg -- the game keeps the
-- cast bar's place right under the health bar, so a line there was covered
-- by every cast): in the groove of the Nameplate Kit's lower rail, as wide
-- as the bar, the bracket its outline; without the kit, along the bar's own
-- bottom edge with a thin dark edge above it. Never under the cast bar.
--------------------------------------------------------------------------------

local Threat = MelloUI.Threat
local W = MelloUI.Widgets
local THREAT_H = 3
local WHITE = "Interface\\Buttons\\WHITE8X8"
local threatLines = setmetatable({}, { __mode = "k" })   -- [the plate's UnitFrame] = its line
local PLATE_UNITS = {}
for i = 1, 40 do
	PLATE_UNITS[i] = "nameplate" .. i
end

local function ThreatOn()
	return M.isEnabled and M.db ~= nil and M.db.threatLine ~= false
end

-- a group fight: the player in combat, in a party or a raid
local function GroupFight()
	local ok, fighting = pcall(UnitAffectingCombat, "player")
	return ok and fighting == true and Threat.Grouped()
end

local function ThreatLine(uf)
	local line = threatLines[uf]
	if line then
		return line
	end
	line = CreateFrame("Frame", nil, uf)
	line:EnableMouse(false)
	local hb = uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
	local ok, level = pcall(function() return (hb or uf):GetFrameLevel() end)
	if ok and IsPlainNumber(level) then
		line:SetFrameLevel(level + 5)
	end
	local bar = CreateFrame("StatusBar", nil, line)
	bar:SetStatusBarTexture(WHITE)
	bar:SetMinMaxValues(0, 100)   -- (the game's scaledPercentage, as it comes)
	bar:SetHeight(THREAT_H)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(bar)
	bg:SetTexture(WHITE)
	W.Paint(bg, "innerPanel", "vertex", 0.85)
	-- (without the kit: a thin dark edge between it and the bar's fill)
	local edge = bar:CreateTexture(nil, "BORDER")
	edge:SetTexture(WHITE)
	edge:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 0)
	edge:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 0)
	edge:SetHeight(1)
	W.Paint(edge, "mainWindow", "vertex", 1)
	line.bar, line.hb, line.edge = bar, hb, edge
	threatLines[uf] = line
	return line
end

-- in the Kit's lower rail while it dresses the plate (hanging from the bar's
-- bottom into the rail's groove), else along the bar's own bottom edge;
-- anchored again on a change only
local function HangThreat(uf, line)
	local hb = line.hb or uf
	local rail = BracketLeft(uf) ~= nil
	if line.hbAt == hb and line.rail == rail then
		return
	end
	line.hbAt, line.rail = hb, rail
	local bar = line.bar
	bar:ClearAllPoints()
	if rail then
		bar:SetPoint("TOPLEFT", hb, "BOTTOMLEFT", 0, 0)
		bar:SetPoint("TOPRIGHT", hb, "BOTTOMRIGHT", 0, 0)
	else
		bar:SetPoint("BOTTOMLEFT", hb, "BOTTOMLEFT", 0, 0)
		bar:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", 0, 0)
	end
	line.edge:SetShown(not rail)
end

local function HideThreat(uf)
	local line = threatLines[uf]
	if line then
		line:Hide()
	end
end

-- one plate as the fight stands now (tank, fight: read once for all plates)
local function ThreatPlate(uf, unit, tank, fight)
	if not (fight and ThreatOn() and unit) then
		HideThreat(uf)
		return
	end
	local ok, hostile = pcall(UnitCanAttack, "player", unit)
	if not ok or hostile ~= true then
		HideThreat(uf)
		return
	end
	local status, fraction, tanking, value = Threat.Read("player", unit)
	-- (a value there: plain, or secret -- asked for secret before the nil test)
	local hasValue = Secret(value) or value ~= nil
	if status == false or (status == nil and not hasValue) then
		HideThreat(uf)
		return
	end
	local line = ThreatLine(uf)
	HangThreat(uf, line)
	local r, g, b = Threat.Colour(Threat.State(status, fraction, tank) or "safe")
	local bar = line.bar
	if tank and tanking then
		bar:SetValue(100)
	elseif hasValue then
		bar:SetValue(value)
	else
		bar:SetValue(0)
	end
	bar:SetStatusBarColor(r, g, b)
	line:Show()
end

local function ThreatUnit(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	local uf = plate and not (plate.IsForbidden and plate:IsForbidden()) and plate.UnitFrame
	if uf then
		ThreatPlate(uf, unit, Threat.IsTank(), GroupFight())
	end
end

local function ThreatAll()
	local tank, fight = Threat.IsTank(), GroupFight()
	for i = 1, #PLATE_UNITS do
		local unit = PLATE_UNITS[i]
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		local uf = plate and not (plate.IsForbidden and plate:IsForbidden()) and plate.UnitFrame
		if uf then
			ThreatPlate(uf, unit, tank, fight)
		end
	end
end

local function HideAllThreat()
	for uf in pairs(threatLines) do
		HideThreat(uf)
	end
end

local THREAT_EVENTS = { "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE" }

local QUEST_EVENTS = {
	"QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
	"QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_ENTERING_WORLD",
}

--------------------------------------------------------------------------------
-- Combo points on the target's plate (0.18.5; user, 2026-10-04: look A of
-- BuildData/output/combo_sketch, sketch 2): a rogue's, and a druid's in Cat
-- Form, five points in a row centred on the target plate's health bar, half
-- over its top edge, empty sockets from the moment a hostile mob is targeted
-- (the plate's height never jumps; the user's pick). The game's own art by
-- atlas ELEMENT (the client picks its style: Camelot's bronze rim and red ball
-- for a rogue, the druid's grey sockets), so the reskin changes nothing here:
-- the same art in both looks. Layers as the game's templates
-- (Blizzard_UnitFrame/Mainline/RogueComboPointBar.xml, DruidComboPointBar.xml):
-- the shadow under the socket, the socket empty or lit, the point on it, the
-- frame glow over all when all five are lit (at 1.3 of its size, the sketch's,
-- so it shows round the socket); each piece at its atlas's size scaled to the
-- socket. The count can be secret (GetComboPoints:
-- SecretWhenUnitPowerRestricted) and is never read here: each lit socket,
-- point and glow is a StatusBar's fill on the range its point covers -- (i - 1,
-- i), the glow (4, 5) -- handed the count with SetValue, so the engine shows
-- the bar empty or full. One row, made on the first target that needs it and
-- moved between plates, kept in this table (nothing written on the game's
-- frames). The plate's name rises to clear it (M:NameLift: the look that
-- holds the name, SetNamePlacer, else M:LayGameName), the crowd-control icon
-- with it (ComputeOffset); the debuff rows and the raid mark hang on the name
-- (the game's UpdateAnchors) and rise too. The game's own combo bars for
-- plates (ClassNameplateBarRogue / Druid) are not loaded in this client
-- (Blizzard_NamePlates.toc: ExcludeLoadGameType camelot): no CVar to steer.
-- The target frame's ComboFrame (CVar comboPointLocation) is UnitFramePanel's.
--------------------------------------------------------------------------------

Combo.ART = {
	ROGUE = { shadow = "uf-roguecp-bg-shadow", empty = "uf-roguecp-bg-dis", lit = "uf-roguecp-bg",
		point = "uf-roguecp-icon-red", glow = "uf-roguecp-frame-glow" },
	DRUID = { shadow = "UF-DruidCP-BG-Shadow", empty = "UF-DruidCP-BG-Dis", lit = "UF-DruidCP-BG-Active",
		point = "UF-DruidCP-Icon", glow = "UF-DruidCP-Ring-Glow" },
}
Combo.N = 5
Combo.GLOW = 1.3        -- the glow's size over its scaled atlas (the sketch's)
Combo.GAP = 1 / 16      -- between two sockets, of a socket (the sketch's 1 px at 16)
Combo.DROP = 1 / 16     -- the shadow under its socket, of a socket (the sketch's)
Combo.CAT = 1           -- GetShapeshiftFormID's Cat Form (DRUID_CAT_FORM)
Combo.LEVEL = 8         -- over the health bar: over the kit's bracket rail and the threat line
Combo.lifted = setmetatable({}, { __mode = "k" })   -- [a plate's UnitFrame] = its name's lift

-- the player's class when it has combo points (ROGUE or DRUID), else false
function Combo.Class()
	if Combo.class == nil then
		local _, class = UnitClass("player")
		class = MelloUI.Safe.Text(class)
		Combo.class = (class == "ROGUE" or class == "DRUID") and class or false
	end
	return Combo.class
end

-- whether the row belongs on the target's plate now: the option on, a rogue
-- or a druid in Cat Form, a target the player can attack (a value read
-- secret counts as no)
function Combo.Wanted()
	local class = Combo.Class()
	if not (class and M.isEnabled and M.db and M.db.comboPoints ~= false) then
		return false
	end
	if class == "DRUID" then
		local okF, form = pcall(GetShapeshiftFormID)
		if not okF or Num(form) ~= Combo.CAT then
			return false
		end
	end
	local ok, hostile = pcall(UnitCanAttack, "player", "target")
	return ok and not Secret(hostile) and hostile == true
end

-- the target's plate's UnitFrame, or nil
function Combo.TargetFrame()
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
	if not ok or Secret(plate) or type(plate) ~= "table" or (plate.IsForbidden and plate:IsForbidden()) then
		return nil
	end
	local uf = plate.UnitFrame
	return uf and uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar and uf or nil
end

-- a StatusBar whose fill is `atlas`, shown full from `lo` + 1 on (the
-- engine compares the count it is handed: nothing here does)
function Combo.Bar(row, atlas, lo)
	local bar = CreateFrame("StatusBar", nil, row)
	bar:SetStatusBarTexture(atlas)
	bar:SetMinMaxValues(lo, lo + 1)
	bar:SetValue(lo)
	bar:EnableMouse(false)
	return bar
end

function Combo.Make()
	local art = Combo.ART[Combo.Class()]
	local row = CreateFrame("Frame", nil, UIParent)
	row:EnableMouse(false)
	row:Hide()
	row.shadow, row.empty, row.lit, row.point, row.glow = {}, {}, {}, {}, {}
	for i = 1, Combo.N do
		row.shadow[i] = row:CreateTexture(nil, "BACKGROUND")
		row.shadow[i]:SetAtlas(art.shadow)
		row.empty[i] = row:CreateTexture(nil, "BORDER")
		row.empty[i]:SetAtlas(art.empty)
		row.lit[i] = Combo.Bar(row, art.lit, i - 1)
		row.point[i] = Combo.Bar(row, art.point, i - 1)
		row.glow[i] = Combo.Bar(row, art.glow, Combo.N - 1)
	end
	row.art = art
	Combo.row = row
	return row
end

-- the socket's size: a share of the plate's health bar height (the setup
-- option: a plate's own sizes read secret), the user's Combo Point Size
function Combo.Socket()
	return SetupOption("healthBarHeight", 12) * (Num(M.db.comboSize) or 90) / 100
end

-- the name's lift over a row of `s`: from the bar's top to the sockets' top,
-- less the game's gap under the name and a pixel (the sketch's 5 at 16)
function Combo.NameLift(s)
	return math.max(0, s / 2 - SetupOption("healthBarToNameAboveSpacing", 2) - 1)
end

-- a piece at its atlas's size times f (s x s where the client gives none),
-- centred x units from the row's left edge, y up
function Combo.Piece(region, row, atlas, f, s, x, y)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	local w, h = info and Num(info.width), info and Num(info.height)
	if w and h then
		region:SetSize(w * f, h * f)
	else
		region:SetSize(s, s)
	end
	region:ClearAllPoints()
	region:SetPoint("CENTER", row, "LEFT", x, y)
end

-- the row's pieces for a socket of s, laid again only when s changed
function Combo.Lay(row, s)
	if row.size == s then
		return
	end
	row.size = s
	local art = row.art
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(art.empty)
	local base = info and Num(info.width)
	local f = (base and base > 0) and s / base or 1
	local gap = s * Combo.GAP
	row:SetSize(Combo.N * s + (Combo.N - 1) * gap, s)
	for i = 1, Combo.N do
		local x = (i - 1) * (s + gap) + s / 2
		Combo.Piece(row.shadow[i], row, art.shadow, f, s, x, -s * Combo.DROP)
		Combo.Piece(row.empty[i], row, art.empty, f, s, x, 0)
		Combo.Piece(row.lit[i], row, art.lit, f, s, x, 0)
		Combo.Piece(row.point[i], row, art.point, f, s, x, 0)
		Combo.Piece(row.glow[i], row, art.glow, f * Combo.GLOW, s * Combo.GLOW, x, 0)
	end
end

-- the name of a plate laid again with its lift: the one seam, M:PlaceName
-- (the look that holds the name through its placer, else the game's own
-- anchors with the lift)
function Combo.PlaceName(uf)
	M:PlaceName(uf)
end

-- a plate's name lifted by `lift` (0: back down), the crowd-control icon
-- with it; nothing done when the lift is the same
function Combo.Lift(uf, lift)
	if (Combo.lifted[uf] or 0) == lift then
		return
	end
	Combo.lifted[uf] = lift > 0 and lift or nil
	Combo.PlaceName(uf)
	if Active() then
		AnchorCC(uf)
	end
end

-- after the game laid a plate out again (UpdateAnchors: an acquire, an option
-- change; never per frame): its name lifted again
function Combo.Relaid(uf)
	if Combo.lifted[uf] then
		Combo.PlaceName(uf)
	end
end

-- the row onto the target's plate (its plate before: the name back down)
function Combo.Attach(uf)
	local row = Combo.row or Combo.Make()
	local hb = uf.HealthBarsContainer.healthBar
	if Combo.at ~= uf then
		local old = Combo.at
		Combo.at = uf
		HookUnitFrame(uf)   -- (its layout hook: the lift kept through the game's)
		row:SetParent(uf)
		row:ClearAllPoints()
		row:SetPoint("CENTER", hb, "TOP", 0, 0)
		local ok, level = pcall(hb.GetFrameLevel, hb)
		level = ((ok and Num(level)) or 0) + Combo.LEVEL
		row:SetFrameLevel(level)
		for i = 1, Combo.N do
			-- (the game's template layers: the lit socket, its point, the glow over all)
			row.lit[i]:SetFrameLevel(level + 1)
			row.point[i]:SetFrameLevel(level + 2)
			row.glow[i]:SetFrameLevel(level + 3)
		end
		if old then
			Combo.Lift(old, 0)
		end
	end
	local s = Combo.Socket()
	Combo.Lay(row, s)
	Combo.Lift(uf, Combo.NameLift(s))
	row:Show()
end

function Combo.Detach()
	local uf = Combo.at
	Combo.at = nil
	if Combo.row then
		Combo.row:Hide()
	end
	if uf then
		Combo.Lift(uf, 0)
	end
end

-- the count handed to the bars (plain or secret alike: never compared here)
function Combo.Count()
	local row = Combo.row
	if not (row and Combo.at) then
		return
	end
	local ok, n = pcall(GetComboPoints, "player", "target")
	if not ok then
		return
	end
	if not Secret(n) and type(n) ~= "number" then
		n = 0
	end
	for i = 1, Combo.N do
		row.lit[i]:SetValue(n)
		row.point[i]:SetValue(n)
		row.glow[i]:SetValue(n)
	end
end

-- the row where it belongs now: on the target's plate with the count, or away
function Combo.Update()
	local uf = Combo.Wanted() and Combo.TargetFrame()
	if not uf then
		Combo.Detach()
		return
	end
	Combo.Attach(uf)
	Combo.Count()
end

-- the name's lift on a plate (0 where the row is not): for the crowd-control
-- icon's offset and the look that holds the name (SetNamePlacer)
function M:NameLift(uf)
	return Combo.lifted[uf] or 0
end

--------------------------------------------------------------------------------
-- Events & lifecycle
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
-- (the plate names' UNIT_NAME_UPDATE is registered on it while wanted: Plate.Listen)
Plate.frame = eventFrame
Perf.SetScript(eventFrame, "OnEvent", function(_, event, unit, power)
	if event == "NAME_PLATE_UNIT_ADDED" then
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		if Active() then
			StylePlate(plate)
		end
		if QuestActive() then
			UpdateQuestIcon(plate)
		end
		if ThreatOn() then
			ThreatUnit(unit)
		end
		if Combo.on then
			Combo.Update()   -- (the target's plate may come after the target)
		end
		-- (the plate names: the one core plate-add path, after the game's driver
		-- and its post-hooks; last, so nothing above waits on it)
		Plate.Added(plate)
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		if plate and plate.UnitFrame and questIcons[plate.UnitFrame] then
			questIcons[plate.UnitFrame]:Hide()
		end
		if plate and plate.UnitFrame then
			HideThreat(plate.UnitFrame)
			if plate.UnitFrame == Combo.at then
				Combo.Detach()
			end
			-- (the plate names undone: its OnUnitCleared hook does it too, when
			-- the game's driver ran first and the frame is already put away)
			Plate.Cleared(plate.UnitFrame)
		end
	elseif event == "UNIT_POWER_FREQUENT" then
		-- (the player's; only a combo point change: energy ticks pass by)
		if Secret(power) or power == nil or power == "COMBO_POINTS" then
			Combo.Count()
		end
	elseif event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then
		Combo.Update()
	elseif event == "UNIT_THREAT_LIST_UPDATE" then
		-- (a plate's mob: that plate; the target's or a boss's plate has its
		-- own nameplateN event too)
		if not Secret(unit) and type(unit) == "string" and unit:sub(1, 9) == "nameplate" then
			ThreatUnit(unit)
		end
	elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "PLAYER_REGEN_DISABLED" or event == "GROUP_ROSTER_UPDATE" then
		ThreatAll()
	elseif event == "PLAYER_REGEN_ENABLED" then
		HideAllThreat()
	elseif event == "UNIT_NAME_UPDATE" then
		Plate.OnNameUpdate(unit)
	else
		ScheduleQuestRescan()
		if event == "PLAYER_ENTERING_WORLD" and Combo.on then
			Combo.Update()
		end
	end
end)

-- the combo points' events while the row is wanted at all (the option on, a
-- class with combo points): the target, the player's power (a unit event),
-- a druid's form; off: the row away
local COMBO_EVENTS = { "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM" }
function Combo.Register(on)
	on = (on and Combo.Class()) and true or false
	if Combo.on == on then
		return
	end
	Combo.on = on
	for _, event in ipairs(COMBO_EVENTS) do
		if not on then
			eventFrame:UnregisterEvent(event)
		elseif event ~= "UPDATE_SHAPESHIFT_FORM" or Combo.Class() == "DRUID" then
			eventFrame:RegisterEvent(event)
		end
	end
	if on then
		eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	else
		eventFrame:UnregisterEvent("UNIT_POWER_FREQUENT")
		Combo.Detach()
	end
end

local function RegisterThreatEvents(register)
	for _, event in ipairs(THREAT_EVENTS) do
		if register then
			eventFrame:RegisterEvent(event)
		else
			eventFrame:UnregisterEvent(event)
		end
	end
	if not register then
		HideAllThreat()
	end
end

local function RegisterQuestEvents(register)
	for _, event in ipairs(QUEST_EVENTS) do
		if register then
			if event == "UNIT_QUEST_LOG_CHANGED" then
				eventFrame:RegisterUnitEvent(event, "player")
			else
				eventFrame:RegisterEvent(event)
			end
		else
			eventFrame:UnregisterEvent(event)
		end
	end
end

local function HideAllQuestIcons()
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			local unitFrame = plate and not (plate.IsForbidden and plate:IsForbidden()) and plate.UnitFrame
			if unitFrame and questIcons[unitFrame] then
				questIcons[unitFrame]:Hide()
			end
		end
	end
end

function M:OnInit(db)
	self.db = db
end

-- (0.19.8) switched on after the login's PLAYER_ENTERING_WORLD (Core's
-- start-up pass over the login's first frames): that event as it came
function M:OnLoginWorld(...)
	MelloUI:ReplayWorld(eventFrame, ...)
end

function M:OnEnable(db)
	self.db = db
	eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	RegisterQuestEvents(true)
	RegisterThreatEvents(ThreatOn())
	-- (the plate names: the bus's 'setting' once, every plate shown now through
	-- the budget, UNIT_NAME_UPDATE as wanted)
	Plate.Start()
	Plate.All()
	if db.bigCC then
		ApplyAll()
	end
	if db.questIcon then
		UpdateAllQuestIcons()
	end
	Combo.Register(db.comboPoints ~= false)
	if Combo.on then
		Combo.Update()   -- (no target at login: nothing made)
	end
end

-- (Kit.lua loads before this file, so its combat queue is always there:
-- audit 2026-09-24, a dead guard gone)
local function OutOfCombat(fn)
	MelloUI.Kit:WhenOutOfCombat(fn)
end

function M:OnDisable()
	-- (the names first: an error below must never leave a name hidden)
	Plate.Stop()
	eventFrame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
	eventFrame:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
	RegisterQuestEvents(false)
	RegisterThreatEvents(false)
	Combo.Register(false)
	OutOfCombat(RestoreAll)
	HideAllQuestIcons()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "nameFormat" then
		Plate.All()
		return
	end
	if key == "threatLine" then
		RegisterThreatEvents(value ~= false)
		if value ~= false then
			ThreatAll()
		end
		return
	end
	if key == "questIcon" or key == "questIconSize" then
		if db.questIcon then
			UpdateAllQuestIcons()
		else
			HideAllQuestIcons()
		end
		return
	end
	if key == "comboPoints" or key == "comboSize" then
		Combo.Register(db.comboPoints ~= false)
		Combo.Update()
		return
	end
	if db.bigCC then
		OutOfCombat(ApplyAll)
	else
		OutOfCombat(RestoreAll)
	end
end

MelloUI:Profile("Nameplates", "events", eventFrame)
MelloUI:Profile("Nameplates", "quest icon rescan", UpdateAllQuestIcons)
MelloUI:Profile("Nameplates", "cc anchoring", AnchorCC)
MelloUI:Profile("Nameplates", "plate names", Plate.Seen)

-- What the plate names keep beside the game's frames (weak-keyed tables,
-- never keys on the frames), for the dumps (/npdump) and the tests: read only
M.kept = { nameBandOf = Plate.bandOf, nameMeasureOf = Plate.measureOf, nameMeasured = Plate.measured,
	nameShown = Plate.shown, nameCoverOf = Plate.coverOf, nameCoverOn = Plate.coverOn, nameHidden = Plate.hidden,
	plateSlotAt = Plate.slotAt, nameHide = Plate.HIDE }
