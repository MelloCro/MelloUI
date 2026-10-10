--------------------------------------------------------------------------------
-- MelloUI - Kit
--
-- The painted UI kit (Media/Kit, described by Media/KitLayout.lua, naming per
-- docs/UI-KIT.md) as building blocks for the panel modules: a nine-slice
-- window, cap/mid/cap strips with states, bars with a trough and a fill area,
-- icon slots whose rim sits over the icon, and the replacement library
-- (Kit.Replacements + Kit:Replace) that maps the game's art to those blocks
-- so a panel never chooses a piece itself. A replacement takes the game
-- art's rectangle, size, visibility AND place in the draw order (strata,
-- frame level, layer): check all of them before mapping. Not a module with settings; other
-- modules use MelloUI.Kit. `/kitdemo [scale]` shows every block in one window.
--
-- Pieces are 2x art; Kit.scale is how many UI units one painted pixel covers
-- (0.375 = the "1x is 0.75 UI units" rule the painted bars use). The files
-- are BLP or TGA made from the TGA masters (outside the addon) by
-- Tools/texture_pack.py ship, the small pieces packed into atlas sheets.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
-- frames made in a game window: Core's maker, so the game's gamepad
-- navigation never walks an open window for each one (MelloUI.Safe.CreateFrame)
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("Kit")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
-- one handler for every object it is hooked on, wrapped once (user,
-- 2026-09-24: the shared handlers, low-risk steps only)
local Shared = Perf.Shared or function(_, fn) return fn end

local LAYOUT = MelloUI_KitLayout
local PIECES = LAYOUT and LAYOUT.pieces or {}
local ROOT = LAYOUT and LAYOUT.root or "Interface\\AddOns\\MelloUI\\Media\\Kit\\"

local Kit = { scale = 0.375 }
MelloUI.Kit = Kit

-- What the kit keeps about the game's frames and regions it dresses: beside
-- them in weak-keyed tables, never on them (hard rule 1: no key written on a
-- game frame or table; 0.19.8). The panels read and write the shared ones
-- through these fields (Kit.repOf[button], not a key on the button); a
-- control of MelloUI's own is marked here too (Widgets: false in repOf, so
-- the kit's sweeps pass it by).
local KEPT = { __mode = "k" }
-- (the tables themselves: Core's MelloUI.Kept; made here when the kit loads
-- without Core, as in the kit editor)
-- (rawget: Core's own table or none -- never what a stand-in MelloUI answers
-- for any key)
if type(rawget(MelloUI, "Kept")) ~= "table" then
	rawset(MelloUI, "Kept", setmetatable({}, { __index = function(kept, name)
		local t = setmetatable({}, KEPT)
		rawset(kept, name, t)
		return t
	end }))
end
local Kept = rawget(MelloUI, "Kept")
Kit.repOf = Kept.repOf            -- [frame / region] = its rep from Kit:Replace (false: looked at, nothing replaced)
Kit.slotStoneOf = Kept.slotStoneOf      -- [button] = its stone under an empty slot (Kit:SlotStone)
Kit.glyphStoneOf = Kept.glyphStoneOf     -- [micro button] = the stone under its glyph (ActionBarPanel)
Kit.fontSavedOf = Kept.fontSavedOf      -- [font string] = { path, size, flags }: its font before Kit:TitleFont
Kit.fontTriesOf = Kept.fontTriesOf      -- [font string] = the title font's failed tries (a face not loaded yet)
Kit.portraitSavedOf = Kept.portraitSavedOf  -- [portrait] = { points, w, h }: its place before Kit:FitPortrait
Kit.steadyingOf = Kept.steadyingOf      -- [tab] = true while the kit (or a panel's steadier) sets its label's point
Kit.stateIconsOf = Kept.stateIconsOf     -- [owner] = { [atlas] = rep }: Kit:StateIconReps' plates, one per glyph
Kit.kitHookedOf = Kept.kitHookedOf      -- [frame] = true: the kit's hooks on it made (a scroll box's rows, a pane)
Kit.bracketOf = Kept.bracketOf        -- [status bar] = true while it wears the kit's bracket (BarTextures' mask)
Kit.kitRingOn = Kept.kitRingOn        -- [portrait] = true while it wears the kit's ring (ClassIcons)
Kit.bracketLeftOf = Kept.bracketLeftOf    -- [nameplate's unit frame] = its bracket's left cap (Nameplates' quest icon)
Kit.headerPlateOf = Kept.headerPlateOf    -- [quest log header] = its plate (QuestLogPanel; QuestInk's own plates)
Kit.plateOf = Kept.plateOf          -- [button] = its plate rep (ProfessionsPanel, QuestDialogPanel; QuestInk's own plates)
-- a texture wearing a kit piece (Kit:Apply: the kit's own textures, and two
-- of the game's that take a piece in place, the profession window's portrait
-- and the map's waypoint pins); every reader asks these, never the texture
Kit.pieceOf = Kept.pieceOf          -- [texture] = its piece (or true: ours, never faded with the game's art)
Kit.pieceNameOf = Kept.pieceNameOf      -- [texture] = its piece's name
Kit.backgroundOf = Kept.backgroundOf     -- [texture] = true: a background tile (laid again when scales change)
Kit.tintBaseOf = Kept.tintBaseOf       -- [texture] = { r, g, b }: the tint a module gave it, before Dark Mode's shade
Kit.shadingNow = Kept.shadingNow       -- [texture] = true while the shade sets its colour (the hook passes it by)
Kit.fadeHooked = Kept.fadeHooked       -- [region] = true: Kit:Fade's hooks on it made
-- the kit's own (Kit.lua only): the tuning's changes to the game's regions,
-- and the item slots' empty state
Kit.tunedArt = Kept.tunedArt         -- [region] = its texture before the tuning's (false: none)
Kit.tunedHidden = Kept.tunedHidden      -- [region] = true: hidden by the tuning
Kit.tunedAt = Kept.tunedAt          -- [region] = the tuning's stamp when it was laid
Kit.slotEmpty = Kept.slotEmpty        -- [item button] = true while its slot is empty

-- The kit's colours (user, 2026-09-23: "We can make A and B and let the users
-- select when in game"): the pieces as painted (Media\Kit) or recoloured to
-- the palette by Tools/kit_palette.py, one folder per look holding the same
-- files, so the layout is shared. Pictures and the tiles already warm are not
-- recoloured: every look reads them from Media\Kit (kit_palette's SKIP).
-- Nor are the Elite / Rare / Boss marks (marks/, Modules/KitMarks.lua): their
-- metals mean what a unit is, under every palette.
-- The palettes (0.14.0, user 2026-09-26: one recoloured kit per palette for
-- all six, and the Original): the folder is chosen from the palette in use
-- (MelloUI:PaletteId(), the one MelloUI.Palette is) AND the Kit Colours
-- setting, which stays the palette's own choice:
--   Kit:LookFolder(paletteId, kitColours) -> the folder's path, its name
--       Ember (nil, or an id MelloUI:KnownPalette does not know, is Ember):
--       today's three looks,
--       Warm iron (warm, the default), Bronze, the Original (painted).
--       Any other palette: "painted" is the Original (Media\Kit), anything
--       else (warm, bronze, nil) that palette's own kit, Media\Kit<Id>; one
--       with Ember's two looks (Ember Vibrant, 0.19.1: Core's `looks`
--       "ember") its Bronze in Media\Kit<Id>Bronze, its warm iron in Kit<Id>.
--   Kit:ColourLooks([paletteId]) -> the Kit Colours choices under a palette
--       (nil: the one in use): Ember's three (and an Ember-style palette's,
--       in its own folders); another palette's own kit (value "warm", its
--       name, its folder) and the Original
--   Kit.colourLooks: the choices under the palette in use (the Kit Colours
--       row's values), the same table kept and filled again on a switch
--   Kit:ColourLookShown() -> the entry of Kit.colourLooks the kit draws:
--       the stored Kit Colours, or the choice read from the same folder (a
--       Bronze kept from Ember is that palette's own kit elsewhere); nil if none
--   Kit:LookRoot([look][, piece][, paletteId]) -> the folder a piece is read
--       from: look a Kit Colours value or one of the choices above (its own
--       folder), nil the one in use; piece: an uncoloured piece is always
--       read from Media\Kit; paletteId nil: the one in use
Kit.colourLooks = {
	{ value = "warm", label = "Warm iron", folder = "KitWarm" },
	{ value = "bronze", label = "Bronze", folder = "KitBronze" },
	{ value = "painted", label = "Original (painted)" },
}
-- (the marks' metals and crests, the nameplates' mark on top; their rings are in every look, their gems the look's:
-- Tools/kit_palette.py GEM_TWINS)
local UNCOLOURED = { "^backdrops/", "^cards/", "^icons/", "^parchment/", "^borders/rpg", "^rings/rpg", "^buttons/orb_rpg", "^tiles/vellum", "^tiles/parchment", "^tiles/agedparchment", "^tiles/leather", "^tiles/quilt_", "^tiles/crackle", "^marks/orb_", "^marks/cap_", "^marks/crest_", "^marks/top", "^marks/r%d_" }
local lookRoot = nil   -- the chosen look's folder, once the settings are there
-- LOOK.PaletteId(): the palette in use (its id, "ember" for one Core does not
-- know); LOOK.ShowChoices(id): Kit.colourLooks refilled with that
-- palette's Kit Colours choices (one table: Kit.lua has few locals to spare)
local LOOK = {}
-- A painted look (a palette's kit painted for it, not recoloured; Tools/
-- build_art_look.py) holds its own pages, parchment and rank marks: only the
-- content every look shares is read from Media\Kit (Tools/kit_palette.py
-- ART_SKIP; texture_pack.py checks the two agree)
LOOK.ART_UNCOLOURED = { "^cards/", "^icons/", "^parchment/", "^borders/rpg", "^rings/rpg", "^buttons/orb_rpg", "^backdrops/profession_", "^backdrops/schematic_", "^tiles/leather", "^tiles/quilt_", "^tiles/crackle" }
-- [the look's root] = the ending of its own shadow sheet (Media\Textures\KitShadows_<id>: its shapes, the same
-- layout as KitShadows.lua's, Tools/make_kit_shadows.py build_look). None: Forged Steel, the one painted look,
-- was taken out again (user, 2026-10-04: "i want the forged steel deleted from the addon, i dont like it")
LOOK.ART_ROOTS = {}
-- the shadow sheet for the look in use (`base` the sheet's file, KitShadows.lua's; nil: nil)
function LOOK.ShadowSheet(base)
	local ending = base and lookRoot and LOOK.ART_ROOTS[lookRoot]
	return ending and (base .. ending) or base
end
-- a texture shown from another file, its coordinates kept (SetTexture resets them; Kit:SetKitColours' way)
function LOOK.Retexture(tex, file)
	if tex then
		local ulx, uly, llx, lly, urx, ury, lrx, lry = tex:GetTexCoord()
		tex:SetTexture(file)
		if lry ~= nil then
			tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
		end
	end
end

do
	-- every palette of Core's registry but Ember has kit art of its own
	-- (Media\Kit<Id>, made for each by Tools/kit_palette.py from the same
	-- palettes.json): the registry is the one list
	local EMBER, EMBER_ROOT = {}, {}
	for i, look in ipairs(Kit.colourLooks) do
		EMBER[i] = look
		EMBER_ROOT[look.value] = look.folder and (ROOT:gsub("Kit\\$", look.folder .. "\\")) or ROOT
	end
	local PAINTED = EMBER[3]
	local roots, folders, looks = {}, {}, { ember = EMBER }   -- per palette id, made once
	local byFolder = {}                                          -- [folder name] = its path
	local shownFor = "ember"                                     -- the palette Kit.colourLooks holds the choices of

	-- a palette id as Core reads the setting (MelloUI:KnownPalette, the one
	-- rule: a registry id, anything else Ember); a core without that answer
	-- (a test world) reads Ember, as LOOK.PaletteId without MelloUI:PaletteId
	local function Known(id)
		local fn = MelloUI.KnownPalette
		if type(fn) == "function" then
			local ok, known = pcall(fn, MelloUI, id)
			if ok and type(known) == "string" then
				return known
			end
		end
		return "ember"
	end

	-- (0.19.1) a palette with Ember's two looks, Warm iron and Bronze (Core's registry: `looks` "ember")
	function LOOK.EmberStyle(id)
		local reg = MelloUI.Palettes
		local entry = type(reg) == "table" and reg[id]
		return type(entry) == "table" and entry.looks == "ember"
	end

	function LOOK.PaletteId()
		local fn = MelloUI.PaletteId
		if type(fn) == "function" then
			local ok, id = pcall(fn, MelloUI)
			if ok then
				return Known(id)
			end
		end
		return "ember"
	end

	local function RootOf(folder)
		local root = byFolder[folder]
		if not root then
			root = (ROOT:gsub("Kit\\$", folder .. "\\"))
			byFolder[folder] = root
		end
		return root
	end

	function Kit:LookFolder(paletteId, kitColours)
		local id = Known(paletteId)
		if id == "ember" then
			if kitColours == nil then
				kitColours = "warm"
			end
			local root = EMBER_ROOT[kitColours] or ROOT
			for _, look in ipairs(EMBER) do
				if look.value == kitColours then
					return root, look.folder or "Kit"
				end
			end
			return root, "Kit"
		end
		if kitColours == "painted" then
			return ROOT, "Kit"
		end
		local root = roots[id]
		if not root then
			folders[id] = "Kit" .. id:sub(1, 1):upper() .. id:sub(2)
			root = RootOf(folders[id])
			roots[id] = root
		end
		-- (0.19.1) a palette with Ember's two looks (its registry entry's `looks`, "ember": Ember Vibrant): its
		-- Bronze in Kit<Id>Bronze beside its warm iron, Kit<Id> (Tools/kit_palette.py, the same rule)
		if kitColours == "bronze" and LOOK.EmberStyle(id) then
			return RootOf(folders[id] .. "Bronze"), folders[id] .. "Bronze"
		end
		return root, folders[id]
	end

	function Kit:ColourLooks(paletteId)
		local id = paletteId == nil and LOOK.PaletteId() or Known(paletteId)
		local list = looks[id]
		if not list then
			local reg = MelloUI.Palettes
			local entry = type(reg) == "table" and reg[id]
			local name = type(entry) == "table" and type(entry.name) == "string" and entry.name
				or (id:sub(1, 1):upper() .. id:sub(2)):gsub("(%l)(%u)", "%1 %2")
			local _, folder = self:LookFolder(id, "warm")
			if LOOK.EmberStyle(id) then
				-- Ember's three choices, in that palette's own folders
				local _, bronze = self:LookFolder(id, "bronze")
				list = { { value = "warm", label = EMBER[1].label, folder = folder }, { value = "bronze", label = EMBER[2].label, folder = bronze }, PAINTED }
			else
				list = { { value = "warm", label = name, folder = folder }, PAINTED }
			end
			looks[id] = list
		end
		return list
	end

	-- The Kit Colours choice the kit draws under the palette in use: the
	-- stored one when the palette offers it, else the choice read from the
	-- same folder (a Bronze kept from Ember shows, under another palette, as
	-- that palette's own kit); nil when none is (the configurator's label
	-- and row and the installer read it here). With a palette id
	-- and a Kit Colours value (the installer's draft), the same rule for
	-- that pair instead of the stored one.
	function Kit:ColourLookShown(paletteId, value)
		if value == nil then
			value = self:BorderValue("colours")
		end
		local live = paletteId == nil and Kit.colourLooks or self:ColourLooks(paletteId)
		for _, look in ipairs(live) do
			if look.value == value then
				return look
			end
		end
		local id = paletteId == nil and LOOK.PaletteId() or Known(paletteId)
		local _, folder = self:LookFolder(id, value)
		for _, look in ipairs(live) do
			local _, f = self:LookFolder(id, look.value)
			if f == folder then
				return look
			end
		end
		return nil
	end

	function LOOK.ShowChoices(id)
		if id == shownFor then
			return
		end
		shownFor = id
		local list, live = Kit:ColourLooks(id), Kit.colourLooks
		for i = #live, 1, -1 do
			live[i] = nil
		end
		for i, look in ipairs(list) do
			live[i] = look
		end
	end

	function Kit:LookRoot(look, piece, paletteId)
		local root
		if type(look) == "table" then
			root = look.folder and RootOf(look.folder) or ROOT
		else
			if look == nil then
				look = self:BorderValue("colours")
			end
			root = self:LookFolder(paletteId == nil and LOOK.PaletteId() or paletteId, look)
		end
		if type(piece) == "string" and root ~= ROOT then
			for _, pattern in ipairs(LOOK.ART_ROOTS[root] and LOOK.ART_UNCOLOURED or UNCOLOURED) do
				if piece:find(pattern) then
					return ROOT
				end
			end
		end
		return root
	end
end

-- The folder a piece is read from in the chosen look
local function PieceRoot(name)
	if not lookRoot then
		local um = MelloUI:GetModule("UIModifications")
		if not (um and um.db and Kit.BorderValue) then
			-- the default look, until the settings are loaded (Kit.colourLooks
			-- already the palette's choices: a reader of the Kit Colours' values
			-- need not read the setting first)
			local id = LOOK.PaletteId()
			LOOK.ShowChoices(id)
			return (Kit:LookFolder(id))
		end
		local id = LOOK.PaletteId()
		LOOK.ShowChoices(id)
		lookRoot = Kit:LookFolder(id, Kit:BorderValue("colours"))
	end
	if lookRoot == ROOT then
		return ROOT
	end
	for _, pattern in ipairs(LOOK.ART_ROOTS[lookRoot] and LOOK.ART_UNCOLOURED or UNCOLOURED) do
		if name:find(pattern) then
			return ROOT
		end
	end
	return lookRoot
end

local STATES = { "normal", "hover", "pressed", "checked", "disabled", "plain", "open", "closed", "selected", "focused", "off", "on", "title" }

-- this client hands out secret numbers under unit frames: never compare one.
-- The test is MelloUI.Safe's (Core.lua), one set for the addon.
local Secret = MelloUI.Safe.IsSecret
-- (0.17.0) a write back onto a game region, counted for /melloperf
local WriteBack = MelloUI.Perf.WriteBack or function() end

--------------------------------------------------------------------------------
-- Pieces
--------------------------------------------------------------------------------

function Kit:Piece(name)
	return PIECES[name]
end

--------------------------------------------------------------------------------
-- Preload (user, 2026-09-23: "for a split it waits for the artwork to load in
-- ... can we make it so that it load everything at the loading screen?").
-- The client loads a texture file the first time something asks for it and
-- draws nothing until it is in, so a window's first open after a reload (the
-- professions' cards and parchment, above all) showed its art popping in. One
-- holder texture per file, set during the loading screen and kept, has every
-- file in memory before any window asks. The holder is shown but fully
-- transparent and 1 px: nothing to see, nothing to click.
--------------------------------------------------------------------------------

local preload

--------------------------------------------------------------------------------
-- Painted edges (user, 2026-09-23: pick B "dry brush" of
-- kit_raw/edge_mask_catalog.png, on the spell book's parchment pages). Two
-- masks on one texture: the corner mask, rough along its left and top sides,
-- at the texture's top-left, and its 180-degree twin at the bottom-right, so
-- all four sides of the texture end in bristle strokes. Each mask is at least
-- 512 UI units square (the file's size, the strokes 18 units deep) and grows
-- with a larger texture. Made by Tools/make_edge_mask.py.
--------------------------------------------------------------------------------

local EDGE_ROOT = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Masks\\"
local EDGE_SIZE = 512
Kit.edgeMasks = { EDGE_ROOT .. "edge_brush_tl", EDGE_ROOT .. "edge_brush_br" }
-- the same strokes a third as deep, for a wide panel whose text runs close to
-- its edge (the chat windows)
Kit.edgeMasksFine = { EDGE_ROOT .. "edge_brush_fine_tl", EDGE_ROOT .. "edge_brush_fine_br" }
-- deep strokes on the left and right, shallow ones top and bottom (a chat
-- window's grown backdrop)
Kit.edgeMasksWide = { EDGE_ROOT .. "edge_brush_wide_tl", EDGE_ROOT .. "edge_brush_wide_br" }

local EdgeMixin = {}

-- Size and place the two masks for a texture of w x h on `anchor`.
function EdgeMixin:Fit(w, h)
	local sizeX, sizeY = EDGE_SIZE, EDGE_SIZE
	if w and h and not Secret(w) and not Secret(h) then
		if self.tight then
			-- `tight`: the masks at the texture's own size, so a small panel
			-- gets shorter strokes in proportion (a 340-wide popup: about 12)
			sizeX = math.max(w, h)
			sizeY = sizeX
		else
			-- each way at least the texture's own length: a tall panel (the
			-- objective tracker) stretches the masks up and down only, so its
			-- side strokes keep their depth
			sizeX, sizeY = math.max(EDGE_SIZE, w), math.max(EDGE_SIZE, h)
		end
	end
	local tl, br = self.masks[1], self.masks[2]
	tl:ClearAllPoints()
	br:ClearAllPoints()
	if self.mirror then
		-- flipped left-right: rough on the top and right, then bottom and left
		tl:SetPoint("TOPRIGHT", self.anchor, "TOPRIGHT")
		br:SetPoint("BOTTOMLEFT", self.anchor, "BOTTOMLEFT")
	else
		tl:SetPoint("TOPLEFT", self.anchor, "TOPLEFT")
		br:SetPoint("BOTTOMRIGHT", self.anchor, "BOTTOMRIGHT")
	end
	tl:SetSize(sizeX, sizeY)
	br:SetSize(sizeX, sizeY)
end

-- Rough painted edges on `tex` (a texture filling `anchor`); `mirror` flips
-- the strokes left-right (a left page, so it is not the right page's twin);
-- `tight` scales the strokes with a panel smaller than the masks' 512 units;
-- `fine` uses the shallow strokes (Kit.edgeMasksFine), or "wide" the deep-
-- sided, shallow-topped ones (Kit.edgeMasksWide).
-- Returns the edge (edge:Fit(w, h) once the size is known), or nil where the
-- client has no masks.
function Kit:PaintedEdge(tex, anchor, mirror, tight, fine)
	local owner = tex and tex:GetParent()
	if not (owner and owner.CreateMaskTexture and tex.AddMaskTexture) then
		return nil
	end
	local edge = Mixin({ tex = tex, anchor = anchor or tex, mirror = mirror, tight = tight, masks = {} }, EdgeMixin)
	local set = (fine == "wide" and self.edgeMasksWide) or (fine and self.edgeMasksFine) or self.edgeMasks
	for i, path in ipairs(set) do
		local m = owner:CreateMaskTexture()
		m:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		if mirror then
			pcall(m.SetTexCoord, m, 1, 0, 0, 1)
		end
		edge.masks[i] = m
		tex:AddMaskTexture(m)
	end
	edge:Fit()
	return edge
end

-- A parchment sheet laid on a railed panel's stone (a Kit:NineSlice skin),
-- inside its rails, ending in the painted edge (user, 2026-09-23: the
-- objective tracker, the whisper popup, the chat windows and the damage meter:
-- "leave the background how it was and the borders, but add the parchment
-- layer on top of that and mask it"). It lies in the skin's own layer stack
-- between the stone (BACKGROUND 0) and the rails, a little stone showing
-- between the rails and its strokes; darkened as aged paper, so white and
-- yellow text stays readable on it; the picture cropped to the sheet's shape,
-- never stretched, again whenever `watch` (the frame whose size the skin
-- follows) changes size.
--   opts: margin (6; less than 0 reaches out under the rails), tint
--         { r, g, b }, tight / fine / wide (see PaintedEdge), layer
--         ("BACKGROUND") and sublevel (3); rect: lay it on this instead of
--         inside the skin's rails (a chat window, whose rails stand outside
--         its body), `margin` in from each side; piece (Kit.parchmentPiece)
-- ONE tone for every parchment in the kit (user, 2026-09-23: "a lot of
-- inconsistencies in the brightness of the parchment background" -- the added
-- sheets were tinted to 60 % as aged paper, the pages kept the picture's own
-- light, 112 against 191; pick B of kit_raw/parchment_tone_catalog.png, about
-- 146: white chat and tracker text reads with its shadow, dark ink too).
Kit.parchmentTint = { 0.80, 0.74, 0.64 }
-- the parchment as a tile cut from the page's middle (tiles/vellum, as
-- bright on average as the whole page was): a sheet of any size shows it at
-- the UI's one background resolution, never a stretched picture
Kit.parchmentPiece = "tiles/vellum"

-- Each area's sheets on a switch of its own (user, 2026-09-23: "some people
-- like it, some dont, off by default"): UI Modifications' parchment_<area>
-- settings. opts.area names the area; opts.alive, when given, says whether
-- the sheet's own frame is dressed at all (a sheet that is the chat window's
-- region, not the skin's, shows only while the chat reskin is on).
Kit.parchmentSheets = {}   -- [area] = { { sheet, alive }, ... }
-- [area] = the paper the area's sheets and panels were last switched to
-- (SetParchment, or the first made): a profile load writes parchment_<area>
-- past UI Modifications' OnSettingChanged, so the bus's 'restart' compares
-- (below, with the Kit Colours' recheck)
Kit.parchmentShown = {}

-- an area's saved parchment value as on / off: a switch, or a choice whose
-- "off" is off (the character window's, 0.19.4: "pane" / "window", UI
-- Modifications' PARCHMENTS)
function Kit.ParchmentValueOn(v)
	return (v == true or (type(v) == "string" and v ~= "off")) and true or false
end

function Kit:ParchmentOn(area)
	if not area then
		return true
	end
	local um = MelloUI:GetModule("UIModifications")
	local db = um and um.db
	return Kit.ParchmentValueOn(db and db["parchment_" .. area])
end

function Kit:SetParchment(area, on)
	for _, entry in ipairs(self.parchmentSheets[area] or {}) do
		entry.sheet:SetShown((on and (not entry.alive or entry.alive())) and true or false)
	end
	-- the area's eye-strain panels (Kit:StoneDim) take the other turn: shown
	-- while the paper is off
	for _, entry in ipairs(self.parchmentDims[area] or {}) do
		entry.tex:SetShown((not on and (not entry.alive or entry.alive())) and true or false)
	end
	if area ~= nil then
		self.parchmentShown[area] = on and true or false
	end
	-- last, once the kit's own sheets and panels are switched (the bus's
	-- 'parchment' topic, audit 2026-09-24 rank 5; the files that still hook
	-- this function run after it, as before)
	MelloUI:Fire("parchment", area, on)
end

-- Palette colours on the kit's own regions ("Palette-ready", user
-- 2026-09-25: more palettes are planned). Every region the kit colours
-- from MelloUI.Palette -- the eye-strain panels (Kit:StoneDim), a frame
-- rule's `dim` fill (the L1 boxes), a ring's disc given a palette key, the
-- own-window shell's plain parts (Kit:OwnWindow) -- is painted by its KEY,
-- looked up when painted, and kept in a weak list; the bus's 'palette'
-- paints them all again from the table MelloUI.Palette holds then.
--   Kit:Paint(region, key, how, alpha)
--     key    a MelloUI.Palette role ("innerPanel", "selectedTrim", ...)
--     how    "fill" (SetColorTexture, the default), "vertex"
--            (SetVertexColor), "text" (SetTextColor), "backdrop"
--            (SetBackdropColor) or "border" (SetBackdropBorderColor); a
--            backdrop and its border are kept apart, so one frame has both
--     alpha  the colour's alpha (1)
--   Kit:PaletteKeyOf(colour) -> the role a palette colour table is, or nil
--   Kit:Unpaint(region[, how])   the region out of the lists again (a flat
--     fill that gave way to a kit piece: a new palette leaves the piece)
-- 'palette' also goes out for a Kit Colours change (the topic's contract,
-- Core.lua: after both are in place; a new palette is always a NEW table):
-- while MelloUI.Palette is the table last painted from, nothing is painted.
-- The listener is taken on the first Paint, never at load; a Paint of a
-- region painted before reuses its entry (no garbage).
-- The colours are the palette as MelloUI.Look shows it (docs/plans/
-- game-look.md wave 4): MelloUI.Palette while the reskin is on, the game's
-- own colours by the same keys with it off (Look.Palette), so every own
-- window's flat part follows the reskin; painted again at 'look:own'.
do
	local weak = { __mode = "k" }
	local lists = {
		main = setmetatable({}, weak),       -- [region] = { key, how, alpha }: fill, vertex, text
		backdrop = setmetatable({}, weak),   -- [frame] = { key, how, alpha }
		border = setmetatable({}, weak),
	}
	local paintedFrom, listening = nil, false

	-- the palette as the look shows it now (MelloUI.Look; without it, the palette)
	local function Colours()
		local Look = MelloUI.Look
		return type(Look) == "table" and type(Look.Palette) == "function" and Look.Palette() or MelloUI.Palette
	end

	local function Apply(region, key, how, alpha)
		local c = Colours()[key]
		if not c then
			return
		end
		alpha = alpha or 1
		if how == "fill" then
			-- the region's own alpha kept (a plain part the kit faded, a dim
			-- a caller set): a colour set again must not bring it back
			local was = region:GetAlpha()
			region:SetColorTexture(c[1], c[2], c[3], alpha)
			if not Secret(was) then
				local now = region:GetAlpha()
				if not Secret(now) and now ~= was then
					region:SetAlpha(was)
				end
			end
		elseif how == "vertex" then
			region:SetVertexColor(c[1], c[2], c[3], alpha)
		elseif how == "text" then
			region:SetTextColor(c[1], c[2], c[3], alpha)
		elseif how == "backdrop" then
			region:SetBackdropColor(c[1], c[2], c[3], alpha)
		elseif how == "border" then
			region:SetBackdropBorderColor(c[1], c[2], c[3], alpha)
		elseif how == "swipe" then
			region:SetSwipeColor(c[1], c[2], c[3], alpha)   -- (a Cooldown's swipe: the widget column's ring)
		end
	end

	local function RepaintAll()
		for _, list in pairs(lists) do
			for region, e in pairs(list) do
				Apply(region, e.key, e.how, e.alpha)
			end
		end
	end

	local function OnPalette()
		local palette = MelloUI.Palette
		if palette == paintedFrom then
			return
		end
		paintedFrom = palette
		RepaintAll()
	end

	function Kit:Paint(region, key, how, alpha)
		if not (region and key) then
			return
		end
		how = how or "fill"
		local list = lists[how] or lists.main
		local e = list[region]
		if e then
			e.key, e.how, e.alpha = key, how, alpha
		else
			list[region] = { key = key, how = how, alpha = alpha }
		end
		Apply(region, key, how, alpha)
		if not listening and MelloUI.On then
			listening = true
			paintedFrom = MelloUI.Palette
			MelloUI:On("palette", OnPalette, "Kit palette")
			MelloUI:On("look:own", RepaintAll, "Kit palette")   -- (the reskin switched: the game's colours or the palette)
		end
	end

	-- a region that no longer shows a palette fill (a kit piece put on it
	-- again): out of the lists, so a new palette leaves it as it is
	function Kit:Unpaint(region, how)
		if region == nil then
			return
		end
		local list = lists[how or "fill"] or lists.main
		list[region] = nil
	end

	function Kit:PaletteKeyOf(colour)
		if type(colour) == "string" then
			return MelloUI.Palette[colour] and colour or nil
		end
		if type(colour) ~= "table" then
			return nil
		end
		for key, c in pairs(MelloUI.Palette) do
			if c == colour then
				return key
			end
		end
		return nil
	end
end

-- The eye-strain panel of a HUD frame (user, 2026-09-24: "too much small text
-- over a plain brown border is just an eye strain" / "apply the eye strain
-- rule to all existing windows"; WINDOW-RULES 2e): the palette's inner panel
-- laid over the frame's stone inside its rails, so its text does not lie on
-- the plain brown. Only while that frame's parchment is OFF: with the sheet
-- on, the text lies on paper in dark ink (the parchment ink rule) and a dark
-- panel there would be wrong. A region of `host` (the skin, or the frame
-- whose regions the stone is) between the stone and the sheet, so it is a
-- tint over the one stone, never a second one; kept per area next to the
-- sheets, and Kit:SetParchment switches it the other way round.
--   opts: area, alive (as ParchmentSheet's; no area: always shown), alpha
--         (0.8), layer ("BACKGROUND") and sublevel (2: over the stone at 0,
--         under a sheet at 3); rect + margin (0) as ParchmentSheet's, else
--         from the middle of the skin's rails (their inner half lies over the
--         panel's edge, so no brown seam shows between them)
Kit.parchmentDims = {}   -- [area] = { { tex, alive }, ... }

function Kit:StoneDim(host, opts)
	opts = opts or {}
	if not (host and host.CreateTexture) then
		return nil
	end
	local margin = opts.margin or 0
	local tex = host:CreateTexture(nil, opts.layer or "BACKGROUND", nil, opts.sublevel or 2)
	if opts.rect then
		tex:SetPoint("TOPLEFT", opts.rect, "TOPLEFT", margin, -margin)
		tex:SetPoint("BOTTOMRIGHT", opts.rect, "BOTTOMRIGHT", -margin, margin)
	else
		local pre = self.framePrefix
		tex:SetPoint("TOPLEFT", host, "TOPLEFT", self:RailInset(pre .. "_l", "l") + margin, -(self:RailInset(pre .. "_t", "t") + margin))
		tex:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(self:RailInset(pre .. "_r", "r") + margin), self:RailInset(pre .. "_b", "b") + margin)
	end
	-- (by its palette key: a new palette paints it again, Kit:Paint)
	self:Paint(tex, "innerPanel", "fill", opts.alpha or 0.8)
	if opts.area then
		local list = self.parchmentDims[opts.area] or {}
		self.parchmentDims[opts.area] = list
		list[#list + 1] = { tex = tex, alive = opts.alive }
		local on = self:ParchmentOn(opts.area)
		tex:SetShown((not on and (not opts.alive or opts.alive())) and true or false)
		if self.parchmentShown[opts.area] == nil then
			self.parchmentShown[opts.area] = on
		end
	end
	return tex
end

-- The parchment (0.20.1; the user, 2026-10-10: the RPG UI pack's parchment, used with its creator's permission, in
-- the place of tiles/vellum and our own brush-stroke torn edges -- "it has to be scaleable for different elements"):
-- a kit nine-slice (Tools/make_parchment.py: parchment/sheet_*) laid on a rect as REGIONS of `owner`, in its layer
-- stack (Kit:NineSlice's owner mode: the paper at `sublevel`, its burnt edges one over it, its corners one over
-- those), at any size: the paper repeats at the tiles' one density, the edges along their length, the corners stay
-- whole; the torn outline is in the edges' and corners' own alpha, no mask. In the pack's own tone (the user's pick):
-- no tint. `curls` ("tl", "br", "tl br"): a big page's curled corners (the user's pick: the quest and spell book
-- pages, the character stats pane's top left): the page family (parchment/page_*), its corners big enough to hold
-- a curl and the shading under it whole (a sheet's cut them off and its square showed -- in game, 2026-10-10), the
-- corners without a curl its plain ones (_plain). `place(f)` anchors the frame the regions are laid out on; the
-- returned frame's Show / Hide / SetShown / SetAlpha act on the regions. scale (UI units per painted px; the paper
-- at the same, so its grain is the edges' own): a sheet's 80 px corner at 0.375 (30 UI units), a small panel's at
-- 0.3; a page at 0.6, the pack's own proportions on a quest page's width.
-- `tone`: the brightness every piece is drawn at, the hue the pack's (the user, 2026-10-10, the spell book: "perfect,
-- its just a bit too bright"); kept as the pieces' base under the kit's shade (Kit.tintBaseOf).
Kit.parchment = { prefix = "parchment/sheet", pagePrefix = "parchment/page", body = "parchment/sheet_body", scale = 0.375,
	small = 0.3, page = 0.6, tone = 0.86 }

function Kit:ParchmentNine(owner, opts)
	opts = opts or {}
	local P = self.parchment
	local lay = CreateFrame("Frame", nil, owner)
	lay:EnableMouse(false)
	if opts.place then
		opts.place(lay)
	else
		lay:SetAllPoints(owner)
	end
	-- (room over the paper for its edges and corners: sublevels run to 7)
	local sub = math.max(math.min(opts.sublevel or 3, 5), -8)
	local layer = opts.layer or "BACKGROUND"
	local curls = opts.curls or ""
	local page = curls ~= ""
	local scale = opts.scale or P.scale
	local nine = self:NineSlice(lay, { owner = owner, prefix = page and P.pagePrefix or P.prefix, body = P.body, scale = scale,
		bodyScale = scale, gems = false, slices = false, bodyLayer = layer, bodySub = sub, edgeLayer = layer, edgeSub = sub + 1 })
	-- (a page curled at one corner: its other curled corner the plain one)
	if page then
		for _, c in ipairs({ "tl", "br" }) do
			local tex = rawget(nine, c)
			if tex and not curls:find(c, 1, true) then
				self:Apply(tex, P.pagePrefix .. "_" .. c .. "_plain")
			end
		end
	end
	local k = P.tone
	for _, t in ipairs(nine.all) do
		t:SetVertexColor(k, k, k)
	end
	nine.SetAlpha = function(me, a)
		for _, t in ipairs(me.all) do
			t:SetAlpha(a)
		end
	end
	return nine
end

-- (0.20.1: the parchment nine, Kit:ParchmentNine; the returned sheet is its frame, the second value nil -- no
-- caller read the painted edge)
function Kit:ParchmentSheet(skin, watch, opts)
	opts = opts or {}
	if not (skin and skin.CreateTexture) then
		return nil
	end
	local margin = opts.margin or 6
	local pre = self.framePrefix
	local function Place(f)
		if opts.rect then
			f:SetPoint("TOPLEFT", opts.rect, "TOPLEFT", margin, -margin)
			f:SetPoint("BOTTOMRIGHT", opts.rect, "BOTTOMRIGHT", -margin, margin)
		else
			f:SetPoint("TOPLEFT", skin, "TOPLEFT", self:RailInset(pre .. "_l", "l") + margin, -(self:RailInset(pre .. "_t", "t") + margin))
			f:SetPoint("BOTTOMRIGHT", skin, "BOTTOMRIGHT", -(self:RailInset(pre .. "_r", "r") + margin), self:RailInset(pre .. "_b", "b") + margin)
		end
	end
	local P = self.parchment
	local sheet = self:ParchmentNine(skin, { place = Place, layer = opts.layer, sublevel = opts.sublevel, curls = opts.curls,
		scale = opts.scale or ((opts.tight or opts.fine) and P.small) or P.scale })
	-- (laid again as the frame it follows changes size or shows: a skin sized while hidden gets no OnSizeChanged)
	local function Fit()
		for _, t in ipairs(sheet.tiled) do
			self:Retile(t)
		end
	end
	watch = watch or skin
	if watch.HookScript then
		Perf.HookScript(watch, "OnSizeChanged", Fit)
		Perf.HookScript(watch, "OnShow", Fit)
	end
	Fit()
	if opts.area then
		local list = self.parchmentSheets[opts.area] or {}
		self.parchmentSheets[opts.area] = list
		list[#list + 1] = { sheet = sheet, alive = opts.alive }
		local on = self:ParchmentOn(opts.area)
		sheet:SetShown((on and (not opts.alive or opts.alive())) and true or false)
		if self.parchmentShown[opts.area] == nil then
			self.parchmentShown[opts.area] = on
		end
	end
	return sheet, nil
end

-- Every file the kit draws from, as full paths, each once (the painted-edge
-- masks with them). Pieces packed into one atlas sheet share its file, so
-- a look holds about a third of the files it did as one file per piece.
function Kit:KitFiles()
	local files, seen = {}, {}
	for _, list in ipairs({ self.edgeMasks, self.edgeMasksFine, self.edgeMasksWide }) do
		for _, path in ipairs(list) do
			files[#files + 1] = path
		end
	end
	for name, p in pairs(PIECES) do
		local file = p.file and PieceRoot(name) .. p.file
		if file and not seen[file] then
			seen[file] = true
			files[#files + 1] = file
		end
	end
	-- the one-texture rails' pictures, while the rails are drawn so
	if Kit.SliceFiles then
		for _, file in ipairs(Kit:SliceFiles()) do
			if not seen[file] then
				seen[file] = true
				files[#files + 1] = file
			end
		end
	end
	table.sort(files)
	return files
end

-- Hold these files (full paths) in memory; nil or an empty list lets every
-- one go again. Returns how many are held.
function Kit:Preload(files)
	files = files or {}
	if #files == 0 and not preload then
		return 0
	end
	if not preload then
		preload = CreateFrame("Frame", nil, UIParent)
		preload:SetSize(1, 1)
		preload:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		preload:SetAlpha(0)
		preload:EnableMouse(false)
		preload.textures = {}
	end
	for i, path in ipairs(files) do
		local tex = preload.textures[i]
		if not tex then
			tex = preload:CreateTexture(nil, "BACKGROUND")
			tex:SetAllPoints(preload)
			preload.textures[i] = tex
		end
		tex:SetTexture(path)
	end
	for i = #files + 1, #preload.textures do
		preload.textures[i]:SetTexture(nil)
	end
	preload.count = #files
	preload:SetShown(#files > 0)
	return #files
end

-- How many files are held, and how many the client reports as loaded (nil
-- when this client cannot say).
function Kit:PreloadStatus()
	if not (preload and preload.count and preload.count > 0) then
		return 0, nil
	end
	local loaded
	for i = 1, preload.count do
		local tex = preload.textures[i]
		if tex.IsObjectLoaded then
			local ok, yes = pcall(tex.IsObjectLoaded, tex)
			if ok and not Secret(yes) then
				loaded = (loaded or 0) + (yes and 1 or 0)
			end
		end
	end
	return preload.count, loaded
end

-- Size of a piece on screen, in UI units.
function Kit:Size(name, scale)
	local p = PIECES[name]
	if not p then
		return 0, 0
	end
	scale = scale or self.scale
	return p.w * scale, p.h * scale
end

-- The transparent interior of a hollow piece as insets from its edges
-- (left, right, top, bottom) in UI units; nil when the piece has none.
function Kit:Insets(name, scale)
	local p = PIECES[name]
	if not p or not p.open then
		return nil
	end
	scale = scale or self.scale
	local o = p.open
	return o[1] * scale, (p.w - o[3]) * scale, o[2] * scale, (p.h - o[4]) * scale
end

-- The kit's title face (user, 2026-09-21: "Enchanted Land", titles and
-- headers ONLY — window title plates, the tracker's and the damage meter's
-- headers, the minimap's zone band; body text, names, numbers and chat stay
-- the game's). `Kit:TitleFont(fs, true)` puts it on a FontString at the
-- string's own size and flags (remembered, restored with `false`); a string
-- whose font reads secret is left alone. The face itself is the Fonts
-- module's "Titles & headers" choice (user, 2026-09-22: it was hard-coded
-- here and the setting changed nothing on the plates): `Kit:SetTitleFace`
-- takes a path, `false` for the game's own face on the plates ("Keep the
-- game's"), or nil for the default, Enchanted Land.
Kit.defaultTitleFont = "Interface\\AddOns\\MelloUI\\Media\\Fonts\\EnchantedLand.ttf"
Kit.titleFont = Kit.defaultTitleFont
Kit.titleFontScale = 1.5   -- user, 2026-09-21: the face at 1.5 x the string's size (a custom face only; the game's own keeps its size)
Kit.titleSizeFactor = 1    -- the Fonts module's "Titles & headers size" slider (user, 2026-09-22: it did nothing on the plates), times the face's correction
Kit.titleFaceFactor = 1    -- the face's correction alone (0.19.4): a string with a size of its own (Kit:TitleFont's ownSize)
-- every string in the title face, for a re-size: true, or "own" for a string
-- whose size is its own setting's (the slider passes it by)
local titleStrings = setmetatable({}, { __mode = "k" })

-- The Fonts' factors (the slider's times the face's, and the face's alone);
-- every title string re-set at the new size.
function Kit:SetTitleSizeFactor(factor, faceFactor)
	factor = tonumber(factor) or 1
	faceFactor = tonumber(faceFactor) or 1
	if math.abs(factor - (self.titleSizeFactor or 1)) < 0.001
		and math.abs(faceFactor - (self.titleFaceFactor or 1)) < 0.001 then
		return
	end
	self.titleSizeFactor = factor
	self.titleFaceFactor = faceFactor
	for fs in pairs(titleStrings) do
		if Kit.fontSavedOf[fs] then
			self:TitleFont(fs, true)
		end
	end
end

-- The face on every title string: a path, false (the game's own), nil
-- (the default). Every string in the title face is re-set.
function Kit:SetTitleFace(face)
	if face == nil then
		face = self.defaultTitleFont
	end
	if face == self.titleFont then
		return
	end
	self.titleFont = face
	for fs in pairs(titleStrings) do
		if Kit.fontSavedOf[fs] then
			Kit.fontTriesOf[fs] = nil
			self:TitleFont(fs, true)
		end
	end
end

-- ownSize (0.19.4): true, the string's size is a setting of its own (the
-- Quest Tracker's Header Text Size, Combat Text's Size): the Fonts' title
-- size slider passes it by, the face's correction still reaches it; false,
-- it follows the slider; nil keeps what it was given before (a re-set)
function Kit:TitleFont(fs, on, ownSize)
	if not (fs and fs.GetFont and fs.SetFont) then
		return
	end
	if on then
		if not Kit.fontSavedOf[fs] then
			local ok, path, size, flags = pcall(fs.GetFont, fs)
			if not ok or Secret(path) or Secret(size) or not (size and size > 0) then
				return
			end
			Kit.fontSavedOf[fs] = { path, size, flags or "" }
		end
		local saved = Kit.fontSavedOf[fs]
		local own = titleStrings[fs] == "own"
		if ownSize ~= nil then
			own = ownSize and true or false
		end
		titleStrings[fs] = own and "own" or true
		-- SetFont answers false when the face cannot be used yet (the file
		-- is read on first use; a string fonted during loading lost its text
		-- — the tracker's "All Objectives" came up blank, 2026-09-21): then
		-- the game's font goes back at once and the face is tried again a
		-- moment later, a few times
		local face = self.titleFont or saved[1]
		local scale = self.titleFont and (self.titleFontScale or 1) or 1
		local factor = own and (self.titleFaceFactor or 1) or (self.titleSizeFactor or 1)
		local okSet, applied = pcall(fs.SetFont, fs, face, saved[2] * scale * factor, saved[3])
		if not (okSet and applied) then
			pcall(fs.SetFont, fs, saved[1], saved[2], saved[3])
			Kit.fontTriesOf[fs] = (Kit.fontTriesOf[fs] or 0) + 1
			if Kit.fontTriesOf[fs] <= 8 and C_Timer and C_Timer.After then
				C_Timer.After(1, function()
					if Kit.fontSavedOf[fs] then
						Kit:TitleFont(fs, true)
					end
				end)
			end
		else
			Kit.fontTriesOf[fs] = nil
		end
	elseif Kit.fontSavedOf[fs] then
		local saved = Kit.fontSavedOf[fs]
		Kit.fontSavedOf[fs] = nil
		Kit.fontTriesOf[fs] = nil
		titleStrings[fs] = nil
		fs:SetFont(saved[1], saved[2], saved[3])
	end
end

-- Every kit texture is registered here, so Dark Mode can darken the painted
-- interface as one (user, 2026-09-21: Dark Mode darkens the modified UI
-- while it is on, the default art while it is off). `Kit:SetShade(s)` puts
-- s x the texture's own tint on each piece; tints set later by the modules
-- (a lit tab, the target's gold bracket, a hover) go through the same
-- multiplier: a SetVertexColor post-hook remembers the tint as the BASE and
-- re-applies it shaded. Only the brightness is touched, never the hue: the
-- red gems stay red.
Kit.shade = 1
local SHADED = setmetatable({}, { __mode = "k" })

local function ShadeTexture(tex)
	local base = Kit.tintBaseOf[tex]
	local r, g, b = 1, 1, 1
	if base then
		r, g, b = base[1], base[2], base[3]
	end
	local k = Kit.shade
	Kit.shadingNow[tex] = true
	tex:SetVertexColor(r * k, g * k, b * k)
	Kit.shadingNow[tex] = nil
end

-- The tint a module gives a kit texture, kept as its base and shaded. One
-- handler for every kit texture: all it keeps is beside it (Kit.tintBaseOf,
-- Kit.shadingNow), never on it
local OnKitVertexColour = Shared("SetVertexColor on every kit texture", function(t, r, g, b)
	if Kit.shadingNow[t] then
		return
	end
	-- (0.19.0) a colour that is secret (a debuff's dispel colour in a fight,
	-- Kit:TintSkin): shown as it is, neither kept as the base nor shaded --
	-- no arithmetic on a secret
	if Secret(r) or Secret(g) or Secret(b) then
		return
	end
	-- kept in the one table (a hover tints a whole skin's pieces: no new
	-- table per piece per hover)
	local base = Kit.tintBaseOf[t]
	if base then
		base[1], base[2], base[3] = r or 1, g or 1, b or 1
	else
		Kit.tintBaseOf[t] = { r or 1, g or 1, b or 1 }
	end
	if Kit.shade < 1 then
		ShadeTexture(t)
	end
end)

function Kit:RegisterTexture(tex)
	if SHADED[tex] then
		return
	end
	SHADED[tex] = true
	hooksecurefunc(tex, "SetVertexColor", OnKitVertexColour)
	if self.shade < 1 then
		ShadeTexture(tex)
	end
end

function Kit:SetShade(shade)
	shade = tonumber(shade) or 1
	if shade < 0 then
		shade = 0
	elseif shade > 1 then
		shade = 1
	end
	if math.abs(shade - self.shade) < 0.001 then
		return
	end
	self.shade = shade
	for tex in pairs(SHADED) do
		ShadeTexture(tex)
	end
end

-- Put a piece on an existing texture. Repeatable pieces get the REPEAT wrap
-- mode; call Kit:Retile(tex) whenever their size changes. A small piece's
-- file is an atlas sheet it shares with others (KitLayout.lua; see
-- Kit:ApplyTuning): its uv is its rectangle there, so whatever crops or
-- mirrors a piece works inside p.uv, never on 0..1 of the file.
-- BACKGROUNDS keep one resolution across the whole UI (user, 2026-09-23:
-- "Scaling something should not stretch the Background artwork, it should
-- dynamically expand it and the background resolution should stay
-- persistant across the whole UI"): a background piece (a tile, a window's
-- stone body) repeats at Kit.scale UI units per piece px of the SCREEN
-- (UIParent's scale), whatever the scale of the frame it is on and whatever
-- scale its caller asked for. A bigger or scaled-up frame shows more of it,
-- never a bigger copy. The page pictures were replaced by tiles cut from
-- their middles (tiles/concrete, tiles/vellum) for this: a picture can only
-- be fitted by stretching. `tex.kitOwnScale`: a texture that keeps its
-- caller's scale (the Configurator's picture rows' small previews).
local BACKGROUNDS = setmetatable({}, { __mode = "k" })   -- every background texture, to lay again when scales change

local function IsBackground(name)
	return name:find("^tiles/") ~= nil or name:find("_body$") ~= nil
end

-- The share of one repeat a tiled texture spans on an axis, and where it
-- starts (Kit:Retile's, below; out here, not in it, so a retile makes no
-- closure: every skin's, holder's and tile rect's show and resize runs it,
-- and a tab click still made garbage -- review, 2026-09-24)
local function RetileSpan(align, size, repeatSize, from, centred, far)
	local f = size / repeatSize
	if align == "screen" then
		return f, (from % repeatSize) / repeatSize
	elseif centred then
		return f, (1 - f) / 2
	elseif far then
		return f, 1 - f
	end
	return f, 0
end

-- a texture's left and top edges (Kit:Retile's, for pcall without a closure)
local function RetileTopLeft(tex)
	return tex:GetLeft(), tex:GetTop()
end

-- `later`: the caller lays the repeat itself once the texture is placed (a
-- nine-slice's body and rails, tiled together when the skin is done)
function Kit:Apply(tex, name, later)
	local p = PIECES[name]
	if not p then
		tex:SetTexture(nil)
		Kit.pieceOf[tex], Kit.pieceNameOf[tex] = nil, nil
		if tex.kitShadow then
			self:ShadowFit(tex)   -- no piece: its shadow partner hides
		end
		return false
	end
	if p.tile then
		tex:SetTexture(PieceRoot(name) .. p.file, "REPEAT", "REPEAT")
	else
		tex:SetTexture(PieceRoot(name) .. p.file)
	end
	tex:SetTexCoord(p.uv[1], p.uv[2], p.uv[3], p.uv[4])
	Kit.pieceOf[tex], Kit.pieceNameOf[tex] = p, name
	Kit.backgroundOf[tex] = (p.tile and IsBackground(name)) or nil
	if Kit.backgroundOf[tex] then
		BACKGROUNDS[tex] = true
	end
	self:RegisterTexture(tex)
	if p.tile and not later then
		self:Retile(tex)
	end
	if tex.kitShadow then
		self:ShadowFit(tex)   -- its shadow partner takes the new piece's shape (Kit:Shadow, below)
	end
	return true
end

local ApplySlice   -- a one-texture nine-slice's picture on its texture (with the nine-slices, below)

-- Kit Colours changed: every kit texture shown again from the chosen look's
-- folder, where it is (its texture coordinates -- a strip's tiling, a mirror,
-- a crop -- kept as they are, read into eight locals: no table per texture,
-- configurator build 2026-09-25). The bus's 'palette' goes out after it, from
-- Kit:ApplyBorder, once every texture is in the new look. The folder is the
-- palette in use's (Kit:LookFolder): a palette switch comes this way too
-- (Core swaps MelloUI.Palette, then Kit:ApplyBorder("colours")).
function Kit:SetKitColours(value)
	local id = LOOK.PaletteId()
	LOOK.ShowChoices(id)
	lookRoot = self:LookFolder(id, value)
	for tex in pairs(SHADED) do
		local p, name = Kit.pieceOf[tex], Kit.pieceNameOf[tex]
		if p and name and p.file then
			local ulx, uly, llx, lly, urx, ury, lrx, lry = tex:GetTexCoord()
			if p.tile then
				tex:SetTexture(PieceRoot(name) .. p.file, "REPEAT", "REPEAT")
			else
				tex:SetTexture(PieceRoot(name) .. p.file)
			end
			if lry ~= nil then
				tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
			end
		elseif type(p) == "table" and p.tile == "slice" then
			-- a skin's rails as one texture: the look's picture, cut as before
			ApplySlice(tex, p)
		end
	end
end

-- A profile load (and the late settings at login, the macro backup) writes
-- the Kit Colours past UI Modifications' OnSettingChanged, the other caller
-- of ApplyBorder: once they are in (the bus's 'restart', at the end of
-- Core's RestartModules) the chosen look is read again, and the textures
-- follow only when it is not the folder they are drawn from. The look is
-- read as PieceRoot reads it, through the umbrella's bound settings (and the
-- palette in use: Core applies a loaded profile's palette through
-- Kit:ApplyBorder("colours") itself, and then nothing is left here). While
-- those are not bound (UI Modifications off since the login) a folder can
-- still be cached (the installer binds them for its look refresh), so the
-- same check runs again when UI Modifications is switched on (the bus's
-- 'module', after its OnEnable bound them) by the player: a profile load's
-- switch (MelloUI.restartingModules) comes before its palette is in place,
-- and always ends in the 'restart' that checks with the new palette (one
-- walk, one 'palette').
do
	local function Recheck()
		local um = lookRoot ~= nil and MelloUI:GetModule("UIModifications")
		if um and um.db and (Kit:LookFolder(LOOK.PaletteId(), Kit:BorderValue("colours"))) ~= lookRoot then
			Kit:ApplyBorder("colours")
		end
	end
	local RestartColours = Shared("'restart' on the bus: the Kit Colours", Recheck)
	local UmbrellaOn = Shared("'module' on the bus: the Kit Colours", function(name, enabled)
		if enabled and name == "UIModifications" and not MelloUI.restartingModules then
			Recheck()
		end
	end)
	if MelloUI.On then
		MelloUI:On("restart", RestartColours, "Kit colours")
		MelloUI:On("module", UmbrellaOn, "Kit colours")
	end
end

-- The parchment the same way: a profile load writes parchment_<area> past UI
-- Modifications' OnSettingChanged too (SetParchment's caller), so on the
-- frame after the bus's 'restart' each area whose setting is not the paper
-- it was last switched to (Kit.parchmentShown) is switched, once: a caller's
-- own refresh in the restart's frame (the installer's Revert makes one) has
-- set it by then. The areas are gathered first (a switch may make sheets).
do
	local areas = {}   -- reused
	local function PaperSync()
		for area in pairs(Kit.parchmentSheets) do
			areas[#areas + 1] = area
		end
		for area in pairs(Kit.parchmentDims) do
			areas[#areas + 1] = area
		end
		for i = 1, #areas do
			local area = areas[i]
			areas[i] = nil
			local on = Kit:ParchmentOn(area)
			if Kit.parchmentShown[area] ~= on then
				Kit:SetParchment(area, on)
			end
		end
	end
	local RestartPaper = Shared("'restart' on the bus: the parchment", function()
		if Kit.NextFrame then
			Kit:NextFrame("Kit parchment after a restart", PaperSync)
		end
	end)
	if MelloUI.On then
		MelloUI:On("restart", RestartPaper, "Kit parchment")
	end
end

--------------------------------------------------------------------------------
-- Shadow partners (user, 2026-09-25: the nameplates' "Whole plate" shade is
-- the first user; 0.14.0 gives every kit piece one). A kit texture's partner
-- is a soft, dark copy of its OWN piece's shape, made offline from the
-- piece's alpha (grown, blurred, a quarter of the painted size) by
-- Tools/make_kit_shadows.py into one sheet, Media\Textures\KitShadows;
-- Media\KitShadows.lua says where each piece's lies and how far its blur
-- reaches past the piece (`pad`, painted px: left, top, right, bottom; a
-- strip's parts reach past their outer sides only, so the three join). One
-- set for every Kit Colours look: the shapes are the same. The partner is a
-- region of the piece's own frame at BACKGROUND -8 (under all that frame
-- draws), anchored to the piece and grown by its pad at the piece's scale,
-- tinted with a palette colour. Anchors only: nothing is measured, so it
-- works where every size reads secret (a nameplate).
--   Kit:Shadow(tex[, opts]) -> partner, or nil (no sheet, no frame)
--       made once per kit texture (asked again: the same one); opts, read
--       once and not kept: colour (a MelloUI.Palette key, "innerPanel"),
--       alpha (its strength 0..1, 0.7), scale (UI units per painted px, for
--       a texture drawn at another scale than its tex.kitScale), and (v2):
--         host   the frame the partner is a region of, instead of the
--                piece's own (an element's shade frame, one level under
--                everything the element draws); its reach is then converted
--                by the two frames' effective scales, again on the bus's
--                'scale' and a Kit:SetFrameScale
--         cut    { x0, x1, y0, y1 [, sides = "lt..."] }: the part of the
--                piece (piece px) the texture shows (a picture cut into
--                nine): the partner shows that part of the shadow, reaching
--                past the texture only on the piece's own outer sides (or
--                the `sides` given); Kit:ShadowCut changes it
--         shape  another shadow than the piece's own (a synthetic
--                "shade/square", "shade/round", "shade/capsule")
--         area   the look area it belongs to (Kit:ShadowAreaSet)
--         rep    the replacement the piece stands in: hidden with its
--                Disable and SetShown(false) (a partner on another frame no
--                longer hides with the holder)
--         mask   a mask texture of the host (the ring's corner cut,
--                Kit:TitleBehindRing's title.outerCut), put on the partner
--         ends   true: a strip mid's partner takes the sheet's soft ends
--                where the mid runs to the strip's end with no cap
--                (StripMixin:FitCaps); left out, it stays whole there (the
--                nameplates' brackets, capless under a plate's secret width,
--                keep their 0.13.7 cost)
--         follow a frame the partner is shown and hidden with too (drawn
--                by another frame, it no longer hides with the piece's
--                own: a strip, a skin, a holder); its own flag, so a piece
--                hidden by itself (a gem under a title plate) stays so
--       The partner is flagged in Kit.pieceOf and `kitPartner` (a region walker
--       takes it for ours, never for the game's art) and never registered
--       with Dark Mode or the Kit Colours (Kit:RegisterTexture): its colour
--       is the palette's.
--   Kit:ShadowFit(tex[, scale])   its shape and reach again, after the
--       piece's scale changed. Kit:Apply calls it when the piece changes and
--       a strip's Rescale (StripMixin) for its three parts; any other change
--       of a piece's scale (its kitScale, or a partner's own scale) needs
--       this call from whoever made it. A nine (below): its scale and open
--       sides, Kit:ShadowFit(nine[, scale][, open])
--   Kit:ShadowSet(tex, wanted[, alpha])   shown with its piece, or not at
--       all; its strength (a nine: all its parts)
--   Kit:GlowNine(host, rect, family, opts) -> nine   (0.19.0) a soft outline
--       as light round `rect` (an outline family's nine, hidden at first);
--       not a shade: no area switch or strength reaches it
--   Kit:GlowShow(nine, r, g, b[, alpha])   shown in a colour of meaning
--       (perhaps secret), drawn as light; r = nil: hidden
--   Kit:ShadowCut(tex, x0, x1, y0, y1[, sides])   the part of the piece the
--       texture shows (nil: all of it)
--   Kit:ShadowNine(host, rect, family, opts) -> nine, or nil (no nine of that
--       family in the sheet): a rail family's outline (window/frame,
--       window/single, deco/barframe_red ...) round `rect` as eight regions
--       of `host` cut from the family's one shadow (four corners, four edges
--       stretched between them, nothing inside: the profile is dark only
--       outside the rails); or a synthetic shape cut as a nine, its middle
--       filled (shade/square; shade/capsule, at a scale that makes the rect's
--       height its two corners). opts: scale (UI units per painted px, rect's
--       kitScale or Kit.scale), open (sides with no rail: "b" ..., no reach
--       there), skip (corners left out: "tl" ...; a gem corner that has a
--       partner of its own), follow (a frame whose Show / Hide the parts
--       follow), and colour, alpha, area, rep, mask as Kit:Shadow's (any
--       number of nines may follow one frame)
--   Kit:ShadowAreaSet(area, wanted[, alpha]) -> how many: every partner of
--       an area at once
--   Kit:ShadowMask(tex or nine, mask)   a mask of the partner's own frame
--       put on it (and on a nine's parts, a mid's soft ends) after it was
--       made: the ring's corner cut, made once the ring came
--   Kit:ShadowShape(name) -> the sheet's entry for a piece or a synthetic
--       shape, or nil (no shadow for it: nothing to make)
--   Kit:ShadowRefit([soon])   every partner drawn by another frame fitted
--       again where its frames' scales changed (a nine re-laid only then);
--       soon: once on the next frame for any number of asks
--       (Kit:SetFrameScale's, a mouse wheel's burst)
-- It follows its piece's Show, Hide, SetShown and SetAlpha (one shared
-- handler each, hooked on the piece: our own texture), shows only while its
-- piece has a shape in the sheet, and repaints on the bus's 'palette'. A
-- change of piece, scale, strength, colour, cut or a strip's open end
-- allocates nothing.
-- Media\KitShadows.lua, version 2 (a version 1 file, pieces only, still
-- works): file, size, texel (painted px per sheet texel, 4), pieces (as
-- before; a strip mid's entry may carry endL / endR = { uv, pad [, w] }: the
-- soft end its shadow (made with opts.ends) takes where the mid runs to the
-- strip's end with no cap there, just past the mid's end, pad[1] / pad[3] px wide (`w`: painted
-- px it also covers of the mid, none when left out)), nines = { [family] =
-- { uv, pad (the reach past the rails' outer edge: left, top, right,
-- bottom), corner (the rails' corner, painted px), margins (painted px from
-- the picture's left, top, right and bottom to where the corners end; pad +
-- corner when left out), size (the picture's painted width and height; else
-- from uv) } }, shapes = { [name] = { uv, pad [, corner, margins, size] } }:
-- one with margins is cut as a nine with its middle filled (shade/square,
-- shade/capsule: Kit:ShadowNine(host, rect, "shade/square", ...)), one
-- without is stretched whole (shade/round: Kit:Shadow's opts.shape).
--------------------------------------------------------------------------------
do
	local data = _G.MelloUI_KitShadows
	local Num = MelloUI.Safe.Number
	local SHAPES = type(data) == "table" and type(data.pieces) == "table" and data.pieces or {}
	local NINES = type(data) == "table" and type(data.nines) == "table" and data.nines or {}
	local SYNTH = type(data) == "table" and type(data.shapes) == "table" and data.shapes or {}
	local SHEET = type(data) == "table" and type(data.file) == "string" and data.file or nil
	local SIZE = type(data) == "table" and type(data.size) == "table" and data.size or {}
	local SHEET_W, SHEET_H = Num(SIZE[1]) or 0, Num(SIZE[2]) or 0
	local TEXEL = type(data) == "table" and Num(data.texel) or 4
	local NO_OPTIONS = {}
	local WEAK = { __mode = "k" }
	local partners = setmetatable({}, WEAK)   -- every partner (a nine's parts too), for the repaint
	local hosted = setmetatable({}, WEAK)     -- [piece or nine] = true: drawn by another frame (fitted again on a scale change)
	local followers = setmetatable({}, WEAK)  -- [frame] = { the nines and partners that follow it }
	local areas = {}                          -- [area] = { [partner] = true } (weak)
	local listening, scaleListening = false, false
	local NINE_PARTS = { "tl", "tr", "bl", "br", "t", "b", "l", "r", "c" }   -- (the middle, c: a filled shape's only)

	-- a name's shadow: a piece's (a piece of the same shape followed once: a
	-- red end gem's cap), or a synthetic shape; nil when the sheet has none
	local function ShapeOf(name)
		if name == nil then
			return nil
		end
		local e = SHAPES[name]
		if e == nil then
			e = SYNTH[name]
		end
		if type(e) == "string" then
			e = SHAPES[e] or SYNTH[e]
		end
		if type(e) ~= "table" or type(e.uv) ~= "table" or type(e.pad) ~= "table" then
			return nil
		end
		return e
	end

	-- (a partner's strip ends with it)
	local function Paint(sh)
		local palette = MelloUI.Palette
		local c = palette[sh.kitColour] or palette.innerPanel
		if sh.kitTinted then
			-- (a glow's colour of meaning, Kit:GlowShow: perhaps secret, kept
			-- through a new palette)
			c = sh.kitTint
		end
		sh:SetVertexColor(c[1], c[2], c[3], sh.kitStrength)
		local l, r = sh.kitEndL, sh.kitEndR
		if l then
			l:SetVertexColor(c[1], c[2], c[3], sh.kitStrength)
		end
		if r then
			r:SetVertexColor(c[1], c[2], c[3], sh.kitStrength)
		end
	end

	local function Repaint()
		-- a painted look's own sheet (0.19.1: Forged Steel's shapes, the same
		-- layout): swapped in once the look in use is another
		local sheet = LOOK and LOOK.ShadowSheet(SHEET and data.file)   -- (LOOK: none where a test world runs this block alone)
		if sheet and sheet ~= SHEET then
			SHEET = sheet
			for sh in pairs(partners) do
				LOOK.Retexture(sh, SHEET)
				LOOK.Retexture(sh.kitEndL, SHEET)
				LOOK.Retexture(sh.kitEndR, SHEET)
			end
		end
		for sh in pairs(partners) do
			Paint(sh)
		end
	end

	local function Sync(sh)
		local on = (sh.kitWanted and sh.kitShape and sh.kitPieceShown and sh.kitRepOn ~= false and sh.kitFollowShown ~= false) and true or false
		sh:SetShown(on)
		local l, r = sh.kitEndL, sh.kitEndR
		if l then
			l:SetShown(on and l.kitShape ~= nil and sh.kitOpenL == true)
		end
		if r then
			r:SetShown(on and r.kitShape ~= nil and sh.kitOpenR == true)
		end
	end

	-- the host's units per the piece's (1 on the piece's own frame; an
	-- effective scale that reads secret or not at all counts as 1)
	local function Ratio(region, host)
		if not host or host == region then
			return 1
		end
		local okA, a = pcall(region.GetEffectiveScale, region)
		local okB, b = pcall(host.GetEffectiveScale, host)
		a, b = okA and Num(a), okB and Num(b)
		if a and b and a > 0 and b > 0 then
			return a / b
		end
		return 1
	end

	-- a mask of the partner's own frame put on it (a mask only works on the
	-- textures of the frame that made it)
	local function AddMask(sh, mask)
		if type(mask) ~= "table" or type(sh.AddMaskTexture) ~= "function" or type(mask.GetParent) ~= "function" then
			return
		end
		local okM, owner = pcall(mask.GetParent, mask)
		local okS, host = pcall(sh.GetParent, sh)
		if okM and okS and owner ~= nil and owner == host then
			pcall(sh.AddMaskTexture, sh, mask)
		end
	end

	local function JoinArea(sh, area)
		sh.kitArea = area
		local set = areas[area]
		if not set then
			set = setmetatable({}, WEAK)
			areas[area] = set
		end
		set[sh] = true
	end

	local function JoinRep(sh, rep)
		local list = rep.kitShadows
		if not list then
			list = {}
			rep.kitShadows = list
		end
		list[#list + 1] = sh
		sh.kitRep = rep
		-- shown as the rep's holder is now (its own frame: a plain answer)
		local object = rawget(rep, "object")
		if object then
			local ok, shown = pcall(object.IsShown, object)
			sh.kitRepOn = not ok or Secret(shown) or (shown and true or false)
		else
			sh.kitRepOn = rep.holderShown ~= false
		end
	end

	-- a region of `host` for a partner, painted, not yet placed
	local function NewPartner(host, colour, strength)
		local sh = host:CreateTexture(nil, "BACKGROUND", nil, -8)
		sh:SetTexture(LOOK and LOOK.ShadowSheet(SHEET and data.file) or SHEET)
		Kit.pieceOf[sh], sh.kitPartner = true, true
		sh.kitColour, sh.kitStrength = colour, strength
		sh.kitWanted, sh.kitPieceShown = true, true
		return sh
	end

	-- painted px of a picture `texels` wide in the sheet (whole texels: the uv
	-- are written rounded)
	local function Painted(span, sheet)
		return math.floor(span * sheet + 0.5) * TEXEL
	end

	-- a shadow picture's painted width and height (its `size`, else from its uv)
	local function PictureSize(e)
		local size, uv = e.size, e.uv
		local w = type(size) == "table" and Num(size[1])
		local h = type(size) == "table" and Num(size[2])
		return w or Painted(uv[2] - uv[1], SHEET_W), h or Painted(uv[4] - uv[3], SHEET_H)
	end

	-- how much of the mid a soft end covers inward, painted px (its `w`, else
	-- its picture's width less its reach: none when it lies just past the end)
	local function EndWidth(en)
		local w = Num(en.w)
		if w then
			return w
		end
		local pad = en.pad
		return (PictureSize(en)) - (Num(pad[1]) or 0) - (Num(pad[3]) or 0)
	end

	-- a strip mid's soft end (StripMixin:FitCaps opened it), made when first
	-- needed: a region of the partner's frame beside the partner
	local function EndPartner(sh, key)
		local part = sh[key]
		if not part then
			part = NewPartner(sh:GetParent(), sh.kitColour, sh.kitStrength)
			part.kitEndOf = sh
			sh[key] = part
			if sh.kitMask then
				AddMask(part, sh.kitMask)
			end
			local okA, a = pcall(sh.GetAlpha, sh)
			a = okA and Num(a)
			if a then
				part:SetAlpha(a)
			end
			Paint(sh)
		end
		return part
	end

	-- the piece's shape and the reach at its scale (set again only when one
	-- changed): whole, cut (sh.kitCutX0 ...), or a strip mid with a soft end
	-- where it runs to the strip's end (tex.kitOpenL / kitOpenR; only for a
	-- partner made with opts.ends)
	local function Fit(tex, sh)
		local e = ShapeOf(sh.kitShapeName or Kit.pieceNameOf[tex])
		local scale = sh.kitOwnScale or Num(tex.kitScale) or Kit.scale
		if sh.kitHost then
			scale = scale * Ratio(tex, sh.kitHost)
		end
		local ends = sh.kitEnds == true
		local openL, openR = ends and tex.kitOpenL == true, ends and tex.kitOpenR == true
		if e and (e ~= sh.kitShape or scale ~= sh.kitFitScale or sh.kitRefit or openL ~= sh.kitOpenL or openR ~= sh.kitOpenR) then
			local pad, uv = e.pad, e.uv
			local p = sh.kitCutX0 and PIECES[Kit.pieceNameOf[tex]]
			local el = not p and openL and e.endL
			local er = not p and openR and e.endR
			el = type(el) == "table" and type(el.uv) == "table" and type(el.pad) == "table" and el or nil
			er = type(er) == "table" and type(er.uv) == "table" and type(er.pad) == "table" and er or nil
			sh:ClearAllPoints()
			if p then
				-- the part of the piece the texture shows: its reach past the
				-- piece's own outer sides only (or the sides given)
				local x0, x1, y0, y1, sides = sh.kitCutX0, sh.kitCutX1, sh.kitCutY0, sh.kitCutY1, sh.kitCutSides
				local L = ((sides and sides:find("l", 1, true)) or (not sides and x0 <= 0)) and pad[1] or 0
				local T = ((sides and sides:find("t", 1, true)) or (not sides and y0 <= 0)) and pad[2] or 0
				local R = ((sides and sides:find("r", 1, true)) or (not sides and x1 >= p.w)) and pad[3] or 0
				local B = ((sides and sides:find("b", 1, true)) or (not sides and y1 >= p.h)) and pad[4] or 0
				local W, H = pad[1] + p.w + pad[3], pad[2] + p.h + pad[4]
				local du, dv = uv[2] - uv[1], uv[4] - uv[3]
				sh:SetPoint("TOPLEFT", tex, "TOPLEFT", -L * scale, T * scale)
				sh:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", R * scale, -B * scale)
				sh:SetTexCoord(uv[1] + (x0 - L + pad[1]) / W * du, uv[1] + (x1 + R + pad[1]) / W * du,
					uv[3] + (y0 - T + pad[2]) / H * dv, uv[3] + (y1 + B + pad[2]) / H * dv)
			elseif el or er then
				-- the profile from the soft ends' inner edges; the ends beside it
				local wl, wr = el and EndWidth(el), er and EndWidth(er)
				sh:SetPoint("TOPLEFT", tex, "TOPLEFT", el and wl * scale or -pad[1] * scale, pad[2] * scale)
				sh:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", er and -wr * scale or pad[3] * scale, -pad[4] * scale)
				sh:SetTexCoord(uv[1], uv[2], uv[3], uv[4])
				if el then
					local part = EndPartner(sh, "kitEndL")
					part:ClearAllPoints()
					part:SetPoint("TOPLEFT", tex, "TOPLEFT", -el.pad[1] * scale, el.pad[2] * scale)
					part:SetPoint("BOTTOMRIGHT", tex, "BOTTOMLEFT", wl * scale, -el.pad[4] * scale)
					part:SetTexCoord(el.uv[1], el.uv[2], el.uv[3], el.uv[4])
				end
				if er then
					local part = EndPartner(sh, "kitEndR")
					part:ClearAllPoints()
					part:SetPoint("TOPRIGHT", tex, "TOPRIGHT", er.pad[3] * scale, er.pad[2] * scale)
					part:SetPoint("BOTTOMLEFT", tex, "BOTTOMRIGHT", -wr * scale, -er.pad[4] * scale)
					part:SetTexCoord(er.uv[1], er.uv[2], er.uv[3], er.uv[4])
				end
			else
				sh:SetPoint("TOPLEFT", tex, "TOPLEFT", -pad[1] * scale, pad[2] * scale)
				sh:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", pad[3] * scale, -pad[4] * scale)
				sh:SetTexCoord(uv[1], uv[2], uv[3], uv[4])
			end
			if sh.kitEndL then
				sh.kitEndL.kitShape = el
			end
			if sh.kitEndR then
				sh.kitEndR.kitShape = er
			end
			sh.kitFitScale, sh.kitRefit = scale, nil
			sh.kitOpenL, sh.kitOpenR = openL, openR
		end
		sh.kitShape = e
		Sync(sh)
	end

	-- one part of a nine: used or not, its two points on `rect`, its crop
	local function NinePart(sh, used, e, rect, pa, ra, xa, ya, pb, rb, xb, yb, l, r, t, b)
		if used then
			sh:ClearAllPoints()
			sh:SetPoint(pa, rect, ra, xa, ya)
			sh:SetPoint(pb, rect, rb, xb, yb)
			sh:SetTexCoord(l, r, t, b)
			sh.kitShape = e
		else
			sh.kitShape = nil
		end
		Sync(sh)
	end

	-- a nine's parts laid round its rect at its scale, its open sides left
	-- out (the edges beside one run to the rect's edge there); a picture with
	-- no middle columns or rows (a capsule's height) has no edges there, and
	-- a filled shape's middle (nine.c) is laid between the corners
	local function LayNine(nine)
		local e, rect = nine.entry, nine.rect
		local s = nine.scale * nine.ratio
		local pad, uv, m = e.pad, e.uv, e.margins
		local PW, PH = PictureSize(e)
		local c = Num(e.corner) or 0
		local mL = type(m) == "table" and Num(m[1]) or pad[1] + c
		local mT = type(m) == "table" and Num(m[2]) or pad[2] + c
		local mR = type(m) == "table" and Num(m[3]) or pad[3] + c
		local mB = type(m) == "table" and Num(m[4]) or pad[4] + c
		local wide, tall = mL + mR < PW - 0.5, mT + mB < PH - 0.5
		local open, skip = nine.open, nine.skip
		local oL, oR = open:find("l", 1, true) ~= nil, open:find("r", 1, true) ~= nil
		local oT, oB = open:find("t", 1, true) ~= nil, open:find("b", 1, true) ~= nil
		-- (a corner left out: a gem corner with its own partner)
		local sTL, sTR = skip:find("tl", 1, true) ~= nil, skip:find("tr", 1, true) ~= nil
		local sBL, sBR = skip:find("bl", 1, true) ~= nil, skip:find("br", 1, true) ~= nil
		-- the reach past the rect, and how far the corners and edges come in
		local pL, pT, pR, pB = pad[1] * s, pad[2] * s, pad[3] * s, pad[4] * s
		local iL, iT, iR, iB = (mL - pad[1]) * s, (mT - pad[2]) * s, (mR - pad[3]) * s, (mB - pad[4]) * s
		local u0, u1, v0, v1 = uv[1], uv[2], uv[3], uv[4]
		local uL, uR = u0 + mL / PW * (u1 - u0), u1 - mR / PW * (u1 - u0)
		local vT, vB = v0 + mT / PH * (v1 - v0), v1 - mB / PH * (v1 - v0)
		NinePart(nine.tl, not (oL or oT or sTL), e, rect, "TOPLEFT", "TOPLEFT", -pL, pT, "BOTTOMRIGHT", "TOPLEFT", iL, -iT, u0, uL, v0, vT)
		NinePart(nine.tr, not (oR or oT or sTR), e, rect, "TOPRIGHT", "TOPRIGHT", pR, pT, "BOTTOMLEFT", "TOPRIGHT", -iR, -iT, uR, u1, v0, vT)
		NinePart(nine.bl, not (oL or oB or sBL), e, rect, "BOTTOMLEFT", "BOTTOMLEFT", -pL, -pB, "TOPRIGHT", "BOTTOMLEFT", iL, iB, u0, uL, vB, v1)
		NinePart(nine.br, not (oR or oB or sBR), e, rect, "BOTTOMRIGHT", "BOTTOMRIGHT", pR, -pB, "TOPLEFT", "BOTTOMRIGHT", -iR, iB, uR, u1, vB, v1)
		NinePart(nine.t, wide and not oT, e, rect, "TOPLEFT", "TOPLEFT", oL and 0 or iL, pT, "BOTTOMRIGHT", "TOPRIGHT", oR and 0 or -iR, -iT, uL, uR, v0, vT)
		NinePart(nine.b, wide and not oB, e, rect, "BOTTOMLEFT", "BOTTOMLEFT", oL and 0 or iL, -pB, "TOPRIGHT", "BOTTOMRIGHT", oR and 0 or -iR, iB, uL, uR, vB, v1)
		NinePart(nine.l, tall and not oL, e, rect, "TOPLEFT", "TOPLEFT", -pL, oT and 0 or -iT, "BOTTOMRIGHT", "BOTTOMLEFT", iL, oB and 0 or iB, u0, uL, vT, vB)
		NinePart(nine.r, tall and not oR, e, rect, "TOPRIGHT", "TOPRIGHT", pR, oT and 0 or -iT, "BOTTOMLEFT", "BOTTOMRIGHT", -iR, oB and 0 or iB, uR, u1, vT, vB)
		if nine.c then
			NinePart(nine.c, wide and tall, e, rect, "TOPLEFT", "TOPLEFT", oL and 0 or iL, oT and 0 or -iT, "BOTTOMRIGHT", "BOTTOMRIGHT",
				oR and 0 or -iR, oB and 0 or iB, uL, uR, vT, vB)
		end
	end

	local OnShow = Shared("Show on a kit piece with a shadow", function(tex)
		local sh = tex.kitShadow
		if sh then
			sh.kitPieceShown = true
			Sync(sh)
		end
	end)
	local OnHide = Shared("Hide on a kit piece with a shadow", function(tex)
		local sh = tex.kitShadow
		if sh then
			sh.kitPieceShown = false
			Sync(sh)
		end
	end)
	local OnSetShown = Shared("SetShown on a kit piece with a shadow", function(tex, shown)
		local sh = tex.kitShadow
		if sh then
			-- (asked for secret first: a secret answer counts as shown)
			sh.kitPieceShown = Secret(shown) or (shown and true or false)
			Sync(sh)
		end
	end)
	local OnSetAlpha = Shared("SetAlpha on a kit piece with a shadow", function(tex, alpha)
		local sh = tex.kitShadow
		alpha = Num(alpha)
		if sh and alpha then
			sh:SetAlpha(alpha)
			if sh.kitEndL then
				sh.kitEndL:SetAlpha(alpha)
			end
			if sh.kitEndR then
				sh.kitEndR:SetAlpha(alpha)
			end
		end
	end)

	-- a frame a nine or a partner follows shown or hidden: its parts with it
	-- (a partner's own flag: its piece's Show / Hide stays its own)
	local function Followed(entry, shown)
		local parts = entry.kitParts
		if not parts then
			entry.kitFollowShown = shown
			Sync(entry)
			return
		end
		for i = 1, #parts do
			local sh = parts[i]
			sh.kitPieceShown = shown
			Sync(sh)
		end
	end
	local FollowShow = Shared("OnShow on a frame a kit shadow follows", function(f)
		local list = followers[f]
		if list then
			for i = 1, #list do
				Followed(list[i], true)
			end
		end
	end, "script")
	local FollowHide = Shared("OnHide on a frame a kit shadow follows", function(f)
		local list = followers[f]
		if list then
			for i = 1, #list do
				Followed(list[i], false)
			end
		end
	end, "script")

	-- a frame to follow: seen now (IsVisible: a frame shown under a hidden
	-- parent is not, and its OnShow comes when that parent shows; a refused
	-- or secret answer counts as seen), and `entry` put on its list (the
	-- frame's two hooks once)
	local function Follow(follow, entry)
		local list = followers[follow]
		if list == nil then
			list = {}
			followers[follow] = list
			Perf.HookScript(follow, "OnShow", FollowShow)
			Perf.HookScript(follow, "OnHide", FollowHide)
		end
		list[#list + 1] = entry
	end
	local function Seen(f)
		local ok, v = pcall(f.IsVisible, f)
		return not ok or Secret(v) or (v and true or false)
	end
	local function CanFollow(f)
		return type(f) == "table" and type(f.HookScript) == "function" and type(f.IsVisible) == "function"
	end

	-- every partner drawn by another frame fitted again where the two
	-- frames' scales changed (its reach in that frame's units: the 'scale'
	-- bus, Kit:SetFrameScale): a nine re-laid only when its ratio moved, a
	-- piece's partner only when its scale did (Fit). A scale change of one
	-- frame reads each hosted entry's two effective scales, no more: finding
	-- whether an entry lies under that frame costs as many reads.
	local function Refit()
		for obj in pairs(hosted) do
			if obj.kitParts then
				local r = Ratio(obj.rect, obj.host)
				if r ~= obj.ratio then
					obj.ratio = r
					LayNine(obj)
				end
			elseif obj.kitShadow then
				Fit(obj, obj.kitShadow)
			end
		end
	end
	local OnScale = Shared("'scale' on the bus: the kit's shadows on other frames", Refit)
	local REFIT_KEY = "Kit shadows on other frames"   -- (Kit:NextFrame: one pass a frame)
	local RefitSoon = Shared("next frame: the kit's shadows on other frames", Refit)

	local function Listen(hostedToo)
		if not MelloUI.On then
			return
		end
		if not listening then
			listening = true
			MelloUI:On("palette", Repaint, "Kit shadows")
		end
		if hostedToo and not scaleListening then
			scaleListening = true
			MelloUI:On("scale", OnScale, "Kit shadows")
		end
	end

	-- one partner shown or not, at a strength (unchanged: not painted again)
	local function SetOne(sh, wanted, alpha)
		sh.kitWanted = wanted and true or false
		alpha = Num(alpha)
		if alpha then
			alpha = alpha < 0 and 0 or alpha > 1 and 1 or alpha
			if alpha ~= sh.kitStrength then
				sh.kitStrength = alpha
				Paint(sh)
			end
		end
		Sync(sh)
	end

	function Kit:Shadow(tex, opts)
		if type(tex) ~= "table" then
			return nil
		end
		local sh = tex.kitShadow
		if sh or not SHEET then
			return sh
		end
		if type(opts) ~= "table" then
			opts = NO_OPTIONS
		end
		local ok, parent = pcall(tex.GetParent, tex)
		local host = opts.host
		if type(host) ~= "table" or not host.CreateTexture then
			host = nil
			if not ok or type(parent) ~= "table" or not parent.CreateTexture then
				return nil
			end
		end
		local a = Num(opts.alpha) or 0.7
		sh = NewPartner(host or parent, type(opts.colour) == "string" and opts.colour or "innerPanel", a < 0 and 0 or a > 1 and 1 or a)
		if host and host ~= parent then
			sh.kitHost = host
		end
		local s = Num(opts.scale)
		sh.kitOwnScale = s and s > 0 and s or nil
		sh.kitShapeName = type(opts.shape) == "string" and opts.shape or nil
		sh.kitEnds = opts.ends == true or nil
		local cut = opts.cut
		if type(cut) == "table" then
			local x0, x1, y0, y1 = Num(cut[1]), Num(cut[2]), Num(cut[3]), Num(cut[4])
			if x0 and x1 and y0 and y1 then
				sh.kitCutX0, sh.kitCutX1, sh.kitCutY0, sh.kitCutY1 = x0, x1, y0, y1
				sh.kitCutSides = type(cut.sides) == "string" and cut.sides or nil
			end
		end
		if opts.mask then
			sh.kitMask = opts.mask
			AddMask(sh, opts.mask)
		end
		if type(opts.area) == "string" then
			JoinArea(sh, opts.area)
		end
		if type(opts.rep) == "table" then
			JoinRep(sh, opts.rep)
		end
		local follow = opts.follow
		if CanFollow(follow) then
			sh.kitFollow, sh.kitFollowShown = follow, Seen(follow)
			Follow(follow, sh)
		end
		-- where the piece is now (our own texture: its answers are plain; a
		-- refused or secret one counts as shown, at full alpha)
		local okS, shown = pcall(tex.IsShown, tex)
		sh.kitPieceShown = not okS or Secret(shown) or (shown and true or false)
		local okA, alpha = pcall(tex.GetAlpha, tex)
		alpha = okA and Num(alpha)
		if alpha then
			sh:SetAlpha(alpha)
		end
		tex.kitShadow = sh
		partners[sh] = true
		if sh.kitHost then
			hosted[tex] = true
		end
		hooksecurefunc(tex, "Show", OnShow)
		hooksecurefunc(tex, "Hide", OnHide)
		hooksecurefunc(tex, "SetShown", OnSetShown)
		hooksecurefunc(tex, "SetAlpha", OnSetAlpha)
		Paint(sh)
		Fit(tex, sh)
		Listen(sh.kitHost ~= nil)
		return sh
	end

	-- A partner for `tex` made as `from`'s was (a top corner's plain twin,
	-- StripMixin / NineSlice's SetTopGems), shown as that one is wanted
	function Kit:ShadowLike(tex, from)
		local was = type(from) == "table" and from.kitShadow
		if not was or type(tex) ~= "table" then
			return nil
		end
		if tex.kitShadow then
			return tex.kitShadow
		end
		local sh = self:Shadow(tex, { host = was.kitHost, colour = was.kitColour, alpha = was.kitStrength, scale = was.kitOwnScale,
			shape = was.kitShapeName, area = was.kitArea, rep = was.kitRep, mask = was.kitMask, ends = was.kitEnds, follow = was.kitFollow })
		if sh then
			sh.kitWanted = was.kitWanted
			Sync(sh)
		end
		return sh
	end

	function Kit:ShadowFit(tex, scale, open)
		if type(tex) ~= "table" then
			return
		end
		if tex.kitParts then
			scale = Num(scale)
			if scale and scale > 0 then
				tex.scale = scale
			end
			if type(open) == "string" then
				tex.open = open
			end
			tex.ratio = tex.host == tex.rect and 1 or Ratio(tex.rect, tex.host)
			LayNine(tex)
			return
		end
		local sh = tex.kitShadow
		if not sh then
			return
		end
		scale = Num(scale)
		if scale and scale > 0 then
			sh.kitOwnScale = scale
		end
		Fit(tex, sh)
	end

	function Kit:ShadowCut(tex, x0, x1, y0, y1, sides)
		local sh = type(tex) == "table" and tex.kitShadow
		if not sh then
			return
		end
		x0, x1, y0, y1 = Num(x0), Num(x1), Num(y0), Num(y1)
		if not (x0 and x1 and y0 and y1) then
			x0, x1, y0, y1 = nil, nil, nil, nil
		end
		sides = type(sides) == "string" and sides or nil
		if x0 ~= sh.kitCutX0 or x1 ~= sh.kitCutX1 or y0 ~= sh.kitCutY0 or y1 ~= sh.kitCutY1 or sides ~= sh.kitCutSides then
			sh.kitCutX0, sh.kitCutX1, sh.kitCutY0, sh.kitCutY1, sh.kitCutSides = x0, x1, y0, y1, sides
			sh.kitRefit = true
		end
		Fit(tex, sh)
	end

	function Kit:ShadowNine(host, rect, family, opts)
		local e = type(family) == "string" and NINES[family]
		local filled = false
		if e == nil and type(family) == "string" then
			-- a synthetic shape cut as a nine (shade/square, shade/capsule): its middle filled
			e = SYNTH[family]
			filled = type(e) == "table" and e.margins ~= nil
			if not filled then
				e = nil
			end
		end
		if not (SHEET and type(e) == "table" and type(e.uv) == "table" and type(e.pad) == "table") then
			return nil
		end
		if type(host) ~= "table" or not host.CreateTexture or type(rect) ~= "table" then
			return nil
		end
		if type(opts) ~= "table" then
			opts = NO_OPTIONS
		end
		local a = Num(opts.alpha) or 0.7
		a = a < 0 and 0 or a > 1 and 1 or a
		local colour = type(opts.colour) == "string" and opts.colour or "innerPanel"
		local s = Num(opts.scale) or Num(rect.kitScale) or Kit.scale
		local nine = { kitParts = {}, kitNine = true, host = host, rect = rect, family = family, entry = e,
			scale = s > 0 and s or Kit.scale, open = type(opts.open) == "string" and opts.open or "",
			skip = type(opts.skip) == "string" and opts.skip or "" }
		nine.ratio = host == rect and 1 or Ratio(rect, host)
		local follow = opts.follow
		if not CanFollow(follow) then
			follow = nil
		end
		local shown = not follow or Seen(follow)
		for i, key in ipairs(NINE_PARTS) do
			if key == "c" and not filled then
				break
			end
			local sh = NewPartner(host, colour, a)
			sh.kitNinePart = key
			sh.kitPieceShown = shown
			nine.kitParts[i], nine[key] = sh, sh
			partners[sh] = true
			if opts.mask then
				sh.kitMask = opts.mask
				AddMask(sh, opts.mask)
			end
			if type(opts.area) == "string" then
				JoinArea(sh, opts.area)
			end
			if type(opts.rep) == "table" then
				JoinRep(sh, opts.rep)
			end
			Paint(sh)
		end
		if follow then
			-- (the frame's two hooks once; each nine that follows it on its list)
			Follow(follow, nine)
		end
		-- (laid on another frame than its host: fitted again when the scales change)
		if host ~= rect then
			hosted[nine] = true
		end
		LayNine(nine)
		Listen(hosted[nine] == true)
		return nine
	end

	function Kit:ShadowAreaSet(area, wanted, alpha)
		local set = areas[area]
		if not set then
			return 0
		end
		local n = 0
		for sh in pairs(set) do
			SetOne(sh, wanted, alpha)
			n = n + 1
		end
		return n
	end

	-- a mask put on a partner made before it (the ring's corner cut, made when
	-- the ring came after the rail's shadow): once per mask
	local function MaskOne(sh, mask)
		if sh.kitMask == mask then
			return
		end
		sh.kitMask = mask
		AddMask(sh, mask)
		if sh.kitEndL then
			AddMask(sh.kitEndL, mask)
		end
		if sh.kitEndR then
			AddMask(sh.kitEndR, mask)
		end
	end

	function Kit:ShadowMask(obj, mask)
		if type(obj) ~= "table" or type(mask) ~= "table" then
			return
		end
		local parts = obj.kitParts
		if parts then
			for i = 1, #parts do
				MaskOne(parts[i], mask)
			end
			return
		end
		local sh = obj.kitShadow
		if sh then
			MaskOne(sh, mask)
		end
	end

	function Kit:ShadowShape(name)
		if not SHEET then
			return nil
		end
		return ShapeOf(name) or (type(name) == "string" and type(NINES[name]) == "table" and NINES[name]) or nil
	end

	-- a replacement enabled or disabled (ReplacementMixin): its partners on
	-- other frames with it
	function Kit:ShadowRepOn(rep, on)
		local list = rep.kitShadows
		if not list then
			return
		end
		on = on and true or false
		for i = 1, #list do
			local sh = list[i]
			sh.kitRepOn = on
			Sync(sh)
		end
	end

	function Kit:ShadowRefit(soon)
		if next(hosted) == nil then
			return
		end
		if soon then
			self:NextFrame(REFIT_KEY, RefitSoon)
		else
			Refit()
		end
	end

	-- (0.19.0) A partner (or a nine's parts) in a colour of meaning instead
	-- of the palette's, and drawn as light (blend "ADD"): the soft outline as
	-- a glow (HealerFrames: a raid frame's rail glowing in its unit's debuff
	-- colour). The colour may be secret: only handed on. r = nil: the
	-- palette's colour and the shade's blend back.
	local function TintOne(sh, r, g, b, blend)
		if not Secret(r) and r == nil then
			sh.kitTinted = false
			sh:SetBlendMode("BLEND")
		else
			local t = sh.kitTint
			if not t then
				t = {}
				sh.kitTint = t
			end
			t[1], t[2], t[3] = r, g, b
			sh.kitTinted = true
			sh:SetBlendMode(blend == "ADD" and "ADD" or "BLEND")
		end
		Paint(sh)
	end

	-- (0.19.0) A soft outline as light: the sheet's nine of `family` (an
	-- outline family: nothing inside) round `rect`, hidden until shown in a
	-- colour (HealerFrames' debuff glow round a frame). Not a shade: no area,
	-- so no UI Shade switch or strength reaches it. opts as Kit:ShadowNine's.
	function Kit:GlowNine(host, rect, family, opts)
		local nine = self:ShadowNine(host, rect, family, opts)
		if nine then
			for i = 1, #nine.kitParts do
				SetOne(nine.kitParts[i], false)
			end
		end
		return nine
	end

	-- shown in a colour of meaning (perhaps secret: handed on) at `alpha`,
	-- drawn as light; r = nil: hidden
	function Kit:GlowShow(nine, r, g, b, alpha)
		if type(nine) ~= "table" or type(nine.kitParts) ~= "table" then
			return
		end
		local on = Secret(r) or r ~= nil
		for i = 1, #nine.kitParts do
			local sh = nine.kitParts[i]
			if on then
				TintOne(sh, r, g, b, "ADD")
				SetOne(sh, true, alpha)
			else
				SetOne(sh, false)
			end
		end
	end

	function Kit:ShadowSet(tex, wanted, alpha)
		if type(tex) ~= "table" then
			return
		end
		local parts = tex.kitParts
		if parts then
			for i = 1, #parts do
				SetOne(parts[i], wanted, alpha)
			end
			return
		end
		local sh = tex.kitShadow
		if sh then
			SetOne(sh, wanted, alpha)
		end
	end
end

-- A background's scale in its own UI units per piece px: Kit.scale on the
-- screen, whatever its frame's effective scale
function Kit:BackgroundScale(tex)
	local ok, s = pcall(tex.GetEffectiveScale, tex)
	local us = UIParent and UIParent:GetEffectiveScale()
	-- (finite and above 0 only: NaN passed "s <= 0" and reached SetTexCoord)
	if not (ok and s and us) or Secret(s) or Secret(us) or not (s > 0 and s < math.huge and us > 0 and us < math.huge) then
		return self.scale
	end
	return self.scale * us / s
end

-- Texture coordinates of a repeatable piece for its current size, so the art
-- repeats at its native scale instead of stretching. A background's phase
-- (`tex.kitAlign`): from its top-left corner (nil), centred ("center"),
-- centred across and from the top or bottom ("top" / "bottom"), or from the
-- screen's origin ("screen": backdrops that meet show one surface).
function Kit:Retile(tex)
	local p = Kit.pieceOf[tex]
	if type(p) ~= "table" or not p.tile then
		return
	end
	local background = Kit.backgroundOf[tex] and not tex.kitOwnScale
	local scale = background and self:BackgroundScale(tex) or tex.kitScale
	if not scale or scale <= 0 then
		scale = self.scale
	end
	local ok, w, h = pcall(tex.GetSize, tex)
	if not ok or (issecretvalue and (issecretvalue(w) or issecretvalue(h))) then
		-- a region under a unit frame answers with secret sizes: `kitTileSize`
		-- (set by whoever sized it) stands in, else the art stays as applied
		w, h = tex.kitTileW or 0, tex.kitTileH or 0
	end
	local align = background and tex.kitAlign or nil
	local left, top
	if align == "screen" then
		local okP, l, t = pcall(RetileTopLeft, tex)
		if okP and l and t and not Secret(l) and not Secret(t) then
			left, top = l, t
		else
			align = nil
		end
	end
	local u1, u2, v1, v2 = p.uv[1], p.uv[2], p.uv[3], p.uv[4]
	local du, dv = u2 - u1, v2 - v1
	if p.tile:find("x") and w > 0 then
		local f, o = RetileSpan(align, w, p.w * scale, left, align == "center" or align == "top" or align == "bottom")
		u1 = u1 + du * o
		u2 = u1 + du * f
	end
	if p.tile:find("y") and h > 0 then
		local f, o = RetileSpan(align, h, p.h * scale, top and -top, align == "center", align == "bottom")
		v1 = v1 + dv * o
		v2 = v1 + dv * f
	end
	-- the same cut as the texture has: nothing written (0.17.0: a nameplate's
	-- strips are sized again nearly every frame, docs/plans/fps-portrait-fix.md;
	-- a height change of a strip that tiles across only gives the same cut)
	local okC, ulx, uly, _, lly, urx = pcall(tex.GetTexCoord, tex)
	if okC and type(ulx) == "number" and type(uly) == "number" and type(lly) == "number" and type(urx) == "number"
		and not (Secret(ulx) or Secret(uly) or Secret(lly) or Secret(urx))
		and math.abs(ulx - u1) < 1e-6 and math.abs(urx - u2) < 1e-6 and math.abs(uly - v1) < 1e-6 and math.abs(lly - v2) < 1e-6 then
		return
	end
	tex:SetTexCoord(u1, u2, v1, v2)
end

-- Every background laid again (a frame scaled, the UI scale changed, Edit
-- Mode closed): their repeat stays the same size on the screen. A texture
-- whose size reads secret (under a unit frame, in combat) and that has no
-- `kitTileW` standing in is left as it was last laid: Retile would otherwise
-- fall back to one whole copy of the piece, the stretched look this rule
-- exists to prevent. Returns how many were laid and how many left. (The
-- secret test comes before any other on the size: a boolean test on a
-- secret is refused too -- audit, 2026-09-24.)
function Kit:RetileBackgrounds()
	local laid, left = 0, 0
	for tex in pairs(BACKGROUNDS) do
		if Kit.backgroundOf[tex] then
			local ok, w, h = pcall(tex.GetSize, tex)
			if (ok and not Secret(w) and not Secret(h) and w and h) or tex.kitTileW then
				self:Retile(tex)
				laid = laid + 1
			else
				left = left + 1
			end
		end
	end
	return laid, left
end

do
	-- A texture in `frame` or under it (its parents up to the top), the
	-- frames seen on the way kept for the rest of one retile: the backgrounds
	-- of one window share most of them, so no frame is asked twice
	local underOf, trail = {}, {}   -- [frame] = in it or not; the frames of one walk

	local function InFrame(tex, frame)
		local f, n, answer = tex:GetParent(), 0, false
		while f do
			if f == frame then
				answer = true
				break
			end
			local known = underOf[f]
			if known ~= nil then
				answer = known
				break
			end
			n = n + 1
			trail[n] = f
			if n > 64 then
				break
			end
			f = f:GetParent()
		end
		for i = 1, n do
			underOf[trail[i]] = answer
			trail[i] = nil
		end
		return answer
	end

	-- The backgrounds in `frame` (or under it) laid again, the rest left as
	-- they are (RetileBackgrounds' rule for each). Returns how many were laid
	-- and how many left (size unreadable).
	function Kit:RetileBackgroundsIn(frame)
		local laid, left = 0, 0
		if not frame then
			return laid, left
		end
		for tex in pairs(BACKGROUNDS) do
			if Kit.backgroundOf[tex] then
				local okU, inFrame = pcall(InFrame, tex, frame)
				if okU and inFrame then
					local ok, w, h = pcall(tex.GetSize, tex)
					if (ok and not Secret(w) and not Secret(h) and w and h) or tex.kitTileW then
						self:Retile(tex)
						laid = laid + 1
					else
						left = left + 1
					end
				end
			end
		end
		wipe(underOf)
		wipe(trail)   -- (a walk an error cut short)
		return laid, left
	end
end

-- Kit:SetFrameScale(frame, scale, setScale): the frame's scale set (through
-- setScale(frame, scale) when given: a caller's own unhooked SetScale) and
-- the backgrounds in it laid again -- only those, and only when the frame's
-- scale on the screen really changed (audit, 2026-09-24: six places set a
-- scale and then laid every background in the UI again, the Quest Tracker
-- on each of its settings, a header's collapse too). A scale that reads
-- secret counts as changed. Returns true when it changed, and how many were
-- laid. A protected frame's scale is the caller's to keep out of combat.
-- A background that only hangs off the frame by its anchors (its holder
-- parented elsewhere) changes size, not scale: the holder's OnSizeChanged
-- lays it, as it always has.
function Kit:SetFrameScale(frame, scale, setScale)
	if not frame then
		return false, 0
	end
	local okB, before = pcall(frame.GetEffectiveScale, frame)
	if setScale then
		setScale(frame, scale)
	else
		frame:SetScale(scale)
	end
	local okA, after = pcall(frame.GetEffectiveScale, frame)
	if okB and okA and not Secret(before) and not Secret(after) and before == after then
		return false, 0
	end
	-- (a shadow partner drawn by another frame than its piece's reaches in
	-- that frame's units: fitted again on the next frame, once for a burst --
	-- a mouse wheel's turns, the saved frames' scales at login -- and only
	-- where the scales changed)
	self:ShadowRefit(true)
	return true, (self:RetileBackgroundsIn(frame))
end

--------------------------------------------------------------------------------
-- The UI scale watcher (user, 2026-09-24: "UI Scaling Break the UI"). One
-- place that answers a change of the game's UI Scale (the uiScale /
-- useUiScale settings), of the window's resolution, and of an Edit Mode
-- setting (a system's Size): every background laid again at the screen's
-- one density, then every panel that measured something on the screen told
-- through Kit:OnUIScaleChanged(fn), fn(reason) with reason "uiscale" (the UI
-- Scale or the resolution) or "editmode" (a setting in Edit Mode): the bus's
-- 'scale' topic (Core.lua), this watcher its one source.
-- The work waits a moment and runs once for a burst of changes: when the
-- event comes the game has not yet re-laid everything for the new scale
-- (Edit Mode re-scales and re-places the right-hand action bars and the
-- panel manager moves its windows in their own handlers of the same events),
-- and the settings' slider sends several changes in a row. What a listener
-- does to a protected frame it puts through Kit:WhenOutOfCombat itself.
-- Bars, rails, caps and pieces in general need nothing: they are sized in
-- their frame's own units and follow any scale with it; only the
-- backgrounds (measured on the screen) and what a panel laid out from
-- screen positions (the action bar backdrops, the saved window places, the
-- drag grid) go stale.
--------------------------------------------------------------------------------
Kit.scaleListenerCount = 0   -- how many came through Kit:OnUIScaleChanged, for /uiscaledump
Kit.lastScaleRefit = nil   -- what the last refit did, for /uiscaledump

-- (an alias of the bus's 'scale' topic, audit 2026-09-24 rank 5: a listener
-- that raises goes to the error handler, the others still run)
function Kit:OnUIScaleChanged(fn)
	if type(fn) == "function" then
		MelloUI:On("scale", fn)
		self.scaleListenerCount = self.scaleListenerCount + 1
	end
end

-- The refit itself, at once (the watcher calls it a moment after a change;
-- /uiscaledump refit calls it by hand)
function Kit:RefitForScale(reason)
	reason = reason or "uiscale"
	local laid, left = self:RetileBackgrounds()
	MelloUI:Fire("scale", reason)
	local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
	self.lastScaleRefit = {
		reason = reason, when = GetTime and GetTime() or 0,
		backgrounds = laid, skipped = left,
		effectiveScale = (okU and not Secret(us)) and us or nil,
	}
	return laid
end

do
	local pending, pendingReason = nil, nil
	local function Run()
		pending = nil
		local reason = pendingReason
		pendingReason = nil
		Kit:RefitForScale(reason)
	end
	-- a change of the UI Scale outranks an Edit Mode one: its listeners do more
	local function Schedule(reason)
		if pendingReason ~= "uiscale" then
			pendingReason = reason
		end
		if pending then
			pending:Cancel()
		end
		pending = C_Timer.NewTimer(0.15, Run)
	end
	Kit.ScheduleScaleRefit = function(_, reason)
		Schedule(reason or "uiscale")
	end
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("UI_SCALE_CHANGED")
	ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
	Perf.SetScript(ev, "OnEvent", function()
		Schedule("uiscale")
	end)
	-- the settings themselves, for a client that changes the scale without
	-- the event (it costs nothing twice: the timer runs once)
	if CVarCallbackRegistry and CVarCallbackRegistry.RegisterCallback then
		for _, cvar in ipairs({ "uiScale", "useUiScale" }) do
			CVarCallbackRegistry:RegisterCallback(cvar, function() Schedule("uiscale") end, Kit)
		end
	end
	-- Edit Mode opened and closed: the addon's ONE registration (audit,
	-- 2026-09-24, rank 5: six files each had their own), told on the bus as
	-- 'editmode' (entering) from inside the game's event, as theirs were;
	-- a close also lays the backgrounds again, here
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", function()
			MelloUI:Fire("editmode", true)
		end, Kit)
		EventRegistry:RegisterCallback("EditMode.Exit", function()
			MelloUI:Fire("editmode", false)
			Schedule("editmode")
		end, Kit)
	end
	-- a system's Size (or any setting) changed in Edit Mode: laid again while
	-- the window is still open, not only when it closes (a post-hook: Edit
	-- Mode's own code runs untouched)
	local manager = EditModeManagerFrame
	if manager and type(manager.OnSystemSettingChange) == "function" then
		hooksecurefunc(manager, "OnSystemSettingChange", function()
			Schedule("editmode")
		end)
	end
end

-- /uiscaledump [refit]: the UI scale as the game and the kit see it, and what
-- the last refit did (user, 2026-09-24: to check the UI Scale fix in game).
-- "refit" runs a refit now first. Opens the copy window.
SLASH_MELLOUISCALEDUMP1 = "/uiscaledump"
SlashCmdList.MELLOUISCALEDUMP = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "refit" then
		Kit:RefitForScale("uiscale")
	end
	MelloUI:ClearLog()
	local function Num(v, fmt)
		if type(v) ~= "number" or Secret(v) then
			return tostring(v)
		end
		return string.format(fmt or "%.4f", v)
	end
	local GetCVarFn = (C_CVar and C_CVar.GetCVar) or GetCVar
	local okC, uiScale = pcall(GetCVarFn, "uiScale")
	local okU, useUiScale = pcall(GetCVarFn, "useUiScale")
	MelloUI:Print("cvar uiScale = %s, useUiScale = %s", okC and tostring(uiScale) or "?", okU and tostring(useUiScale) or "?")
	local okS, s = pcall(UIParent.GetScale, UIParent)
	local okE, es = pcall(UIParent.GetEffectiveScale, UIParent)
	local okW, w, h = pcall(UIParent.GetSize, UIParent)
	MelloUI:Print("UIParent scale = %s, effective = %s, size = %s x %s UI units", okS and Num(s) or "?", okE and Num(es) or "?",
		okW and Num(w, "%.1f") or "?", okW and Num(h, "%.1f") or "?")
	if GetPhysicalScreenSize then
		local okP, pw, ph = pcall(GetPhysicalScreenSize)
		if okP and type(ph) == "number" and not Secret(ph) and ph > 0 then
			MelloUI:Print("physical screen = %s x %s px; a pixel-exact UI scale here would be %s", Num(pw, "%d"), Num(ph, "%d"), Num(768 / ph))
			if okE and type(es) == "number" and not Secret(es) and es > 0 then
				MelloUI:Print("one UI unit = %s screen px", Num(es * ph / 768, "%.3f"))
			end
		end
	end
	local backgrounds = 0
	for tex in pairs(BACKGROUNDS) do
		if Kit.backgroundOf[tex] then
			backgrounds = backgrounds + 1
		end
	end
	-- (the listeners are the bus's 'scale' topic: one that raises goes to the
	-- error handler when it runs)
	MelloUI:Print("Kit.scale = %s UI units per piece px; backgrounds registered = %d; scale listeners through the kit = %d",
		Num(Kit.scale, "%.3f"), backgrounds, Kit.scaleListenerCount)
	local last = Kit.lastScaleRefit
	if last then
		local ago = GetTime and (GetTime() - (last.when or 0)) or 0
		MelloUI:Print("last refit (%s, %.0f s ago, UIParent effective %s): %d backgrounds laid again, %d left (size unreadable), the 'scale' listeners told",
			tostring(last.reason), ago, Num(last.effectiveScale), last.backgrounds or 0, last.skipped or 0)
		if last.effectiveScale and okE and type(es) == "number" and not Secret(es) and math.abs(last.effectiveScale - es) > 0.0001 then
			MelloUI:Print("the UI scale changed since the last refit and none ran: /uiscaledump refit")
		end
	else
		MelloUI:Print("no refit since the last reload (the UI scale has not changed); /uiscaledump refit runs one")
	end
	MelloUI:ShowLog("uiscaledump")
end

-- A new texture showing a piece at its natural size.
function Kit:Texture(parent, name, layer, sublevel, scale)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
	tex.kitScale = scale
	self:Apply(tex, name)
	tex:SetSize(self:Size(name, scale))
	return tex
end

-- A painted part stood in for by another of the same family (the user's
-- pick for that state): the title plate's red middle is the open tab's
-- brighter red (H3, user 2026-09-21: the painted title middle did not fit
-- its rune caps).
local STRIP_ALIAS = {
	["tabs/top_mid_title"] = "tabs/top_mid_open",
}

-- "buttons/textbtn", "cap_l", "hover" -> "buttons/textbtn_cap_l_hover"
local function StripName(base, part, state)
	local name = base .. "_" .. part
	if state and PIECES[name .. "_" .. state] then
		return STRIP_ALIAS[name .. "_" .. state] or name .. "_" .. state
	end
	return name
end

-- The piece a strip part is drawn with (aliases resolved), for code that
-- measures the painted pieces.
function Kit:StripPieceName(base, part, state)
	return StripName(base, part, state)
end

-- First state a strip part exists in ("normal", "plain", ...), nil when stateless.
function Kit:FirstState(base, part)
	return self:FirstStateOf(base .. "_" .. part)
end

-- First state a piece exists in: "buttons/cog" -> "normal", "buttons/checkbox" -> "off".
function Kit:FirstStateOf(base)
	for _, s in ipairs(STATES) do
		if PIECES[base .. "_" .. s] then
			return s
		end
	end
	return nil
end

-- The state name a piece should show for a button's condition, among the
-- states it was painted in (a checkbox has off/on/hover, a slot has
-- normal/hover/pressed/checked, a text button also disabled).
local FALLBACK = {
	disabled = { "disabled" },
	pressed = { "pressed", "hover" },
	checked = { "checked", "on", "open", "selected" },
	hover = { "hover" },
}
local REST = { "normal", "off", "plain", "closed" }

-- What each condition shows in a family, looked up once per family: this
-- runs on every hover, press and SetChecked of every rim and plate, and the
-- lookups built names (garbage) each time. Emptied when the tuning changes
-- the pieces (Kit:ApplyTuning).
local resolved = {}   -- [base] = { disabled = , pressed = , checked = , hover = , rest = } (a state, or false)

local function Resolution(base)
	local r = resolved[base]
	if r then
		return r
	end
	r = {}
	for want, list in pairs(FALLBACK) do
		r[want] = false
		for _, s in ipairs(list) do
			if PIECES[base .. "_" .. s] then
				r[want] = s
				break
			end
		end
	end
	r.rest = false
	for _, s in ipairs(REST) do
		if PIECES[base .. "_" .. s] then
			r.rest = s
			break
		end
	end
	if not r.rest then
		r.rest = Kit:FirstStateOf(base) or false
	end
	resolved[base] = r
	return r
end

function Kit:ResolveState(base, hover, pressed, checked, disabled)
	-- in priority order, each condition only if a piece for it exists: a
	-- family without a disabled piece shows a disabled AND checked button
	-- as checked (the game disables the selected category tab; the slot
	-- rim then lost its gold on a reload — user, 2026-09-22)
	-- (each flag tested on its own: a list of them once had a hole where a
	-- flag was nil and ipairs stopped there — every checked box showed as
	-- off, user 2026-09-22)
	local r = Resolution(base)
	if disabled and r.disabled then
		return r.disabled
	end
	if pressed and r.pressed then
		return r.pressed
	end
	if checked and r.checked then
		return r.checked
	end
	if hover and r.hover then
		return r.hover
	end
	return r.rest or nil
end

--------------------------------------------------------------------------------
-- Nine-slice window: body tiled under everything, edges tiled, corners on top,
-- optional gems on the crossings and the ornament over the top-left.
--   Kit:NineSlice(parent, { prefix = "window/frame", scale = , level = ,
--                           gems = true, ornament = true, body = true,
--                           corners = "gem", skip = "tl",
--                           open = "l" })  -- sides left open: "l", "r", "t", "b"
-- An open side has no edge and no corners: the bracket shape of an attached
-- tab or a bar cap. corners = "gem" draws the painted gem corners
-- (<prefix>_gem_tl..br, oversized, over the edges; their `overhang` puts the
-- gem past the frame's corner) instead of the mitred ones; `skip` names
-- corners to leave mitred (e.g. "tl" where a portrait ring is the corner).
-- The skin fills `parent`; keep content inside Kit:NineSliceInset(skin).
-- skin:SetTint(r, g, b) colours the edges.
-- While `/mellokit slices` is on the edges and mitred corners are one texture
-- (skin.slice; below): skin.t / .b / .l / .r are then not made, and
-- Kit:RailAnchor(skin, side) stands in for them (`railAnchors = true` makes
-- all four at once); `slices = true / false` overrides the switch.
--------------------------------------------------------------------------------

-- (tiled by NineSlice_Retile once the skin's textures are placed)
local function Tiled(skin, name, layer, sublevel, scale)
	local tex = skin:CreateTexture(nil, layer, nil, sublevel)
	tex.kitScale = scale
	Kit:Apply(tex, name, true)
	return tex
end

local function NineSlice_Retile(self)
	for _, tex in ipairs(self.tiled) do
		Kit:Retile(tex)
	end
end
-- one handler for every skin's OnSizeChanged and OnShow (user, 2026-09-24:
-- the shared handlers), the skin being the frame the script runs on
local NineSlice_OnSize = Shared("OnSizeChanged on a kit nine-slice", NineSlice_Retile, "script")
local NineSlice_OnShow = Shared("OnShow on a kit nine-slice", NineSlice_Retile, "script")

--------------------------------------------------------------------------------
-- One-texture nine-slices (user, 2026-09-24: stage 2 of the performance
-- programme, behind a switch that is off by default; `/mellokit slices
-- on|off`, `/mellokit slicetest` to compare). A rail family's eight pieces
-- laid into ONE picture by Tools/build_nineslice.py (Media\<look>\slices\,
-- described by Media\KitSlices.lua): the corners at the corners, whole
-- repeats of each edge between them, an empty middle. The client cuts it by four
-- margins (SetTextureSliceMargins: left, top, right, bottom, in the file's
-- texels from the edges of the texture's crop) and repeats the edges itself
-- (UITextureSliceMode.Tiled; taken as from the start of each edge, as
-- Kit:Retile lays the pieces -- the test window shows it), so a skin's rails
-- are one texture instead of eight and nothing re-tiles them when the skin
-- changes size. The texture is scaled so a corner covers what the corner
-- piece covers today (side x scale UI units). What stays its own texture:
-- the body (a background, at the screen's one density), the gems and the
-- ornament. A skin with a gem corner (a window's outer rail) stays in
-- pieces altogether: under the gem the picture's corner would have to be
-- empty, and the client's filtering then reads that emptiness at every
-- repeat of the edge beside it -- a dark tick across the rail every repeat,
-- and the gem corners are not solid enough over the joint to hide anything
-- laid there instead (review, 2026-09-24). A family whose pieces were tuned
-- or rebuilt since the pictures were made stays in pieces. Every texel is
-- the pieces' own, so the rails' dark edge lines (their shadow) are as
-- painted.
--------------------------------------------------------------------------------

local Slices = {
	tiled = (Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Tiled) or 1,
	families = {},   -- [prefix] = its MelloUI_KitSlices entry while its pieces are as built, or false; emptied by Kit:ApplyTuning
	cuts = {},       -- [prefix .. open] = the picture as one skin shows it (a kitPiece for the texture)
	api = nil,       -- whether this client's textures can be cut (known at the first try)
	noted = nil,     -- the session's one notice given
}

-- The switch (MelloUI's own setting, off unless turned on)
function Kit:SlicesOn()
	local db = MelloUI.db
	return (type(db) == "table" and db.kitSlices == true) or false
end

-- UI units one margin texel covers at texture scale 1 (taken as 1: the
-- client drawing a slice's corner at its texel count in the texture's own
-- units; /mellokit slicetest shows whether it does). A setting only so a
-- client that measures otherwise can be matched without a new build:
-- `/mellokit slices unit <n>`
local function SliceUnit()
	local db = MelloUI.db
	local u = type(db) == "table" and tonumber(db.kitSliceUnit) or nil
	return (u and u > 0) and u or 1
end

-- Media\KitSlices.lua's table (read when asked: nil while that file is not
-- loaded, and the kit then draws in pieces)
local function SliceData()
	local data = _G.MelloUI_KitSlices
	return type(data) == "table" and data or nil
end

-- The pictures' files in the chosen look while the switch is on (Preload
-- Artwork holds them with the pieces); none while it is off
function Kit:SliceFiles()
	local files, data = {}, SliceData()
	if data and self:SlicesOn() then
		for prefix, entry in pairs(data) do
			if entry.full then
				files[#files + 1] = PieceRoot(prefix .. "_t") .. entry.full
			end
		end
	end
	return files
end

-- A family's entry, if its eight pieces still have the geometry the pictures
-- were built from (a piece tuned in the kit editor, or rebuilt by build_kit
-- without build_nineslice after it, keeps the family in pieces)
local function SliceFamily(prefix)
	local known = Slices.families[prefix]
	if known ~= nil then
		return known or nil
	end
	local data = SliceData()
	local entry = data and data[prefix]
	local ok = type(entry) == "table" and type(entry.pieces) == "table"
	if ok then
		for part, src in pairs(entry.pieces) do
			local p = PIECES[prefix .. "_" .. part]
			if not (p and p.file == src.file and p.w == src.w and p.h == src.h and type(p.uv) == "table") then
				ok = false
				break
			end
			for i = 1, 4 do
				if math.abs((p.uv[i] or -1) - (src.uv[i] or -2)) > 1e-5 then
					ok = false
				end
			end
		end
	end
	Slices.families[prefix] = ok and entry or false
	return ok and entry or nil
end

-- The picture as one skin shows it, cut down on the open sides (an open side
-- has no edge and no corners; the edges then start at the rect's edge, as
-- their pieces do there). Shared by every skin of that shape; `tile`
-- "slice" keeps Kit:Retile and the tuning's crop off it.
local function SliceCut(prefix, entry, oL, oR, oT, oB)
	local key = prefix .. "|" .. (oL and "l" or "") .. (oR and "r" or "") .. (oT and "t" or "") .. (oB and "b" or "")
	local cut = Slices.cuts[key]
	if cut then
		return cut
	end
	local file = entry.full
	local c, gw, gh, fw, fh = entry.corner, entry.grid[1], entry.grid[2], entry.size[1], entry.size[2]
	if not (file and c and gw and gh and fw and fh) then
		return nil
	end
	local x1, x2 = oL and c or 0, oR and gw - c or gw
	local y1, y2 = oT and c or 0, oB and gh - c or gh
	local texel = entry.texel or 1
	cut = {
		prefix = prefix, file = file, texel = texel,
		w = (x2 - x1) * texel, h = (y2 - y1) * texel,   -- painted px shown (/kitwhat)
		uv = { x1 / fw, x2 / fw, y1 / fh, y2 / fh },
		margins = { oL and 0 or c, oT and 0 or c, oR and 0 or c, oB and 0 or c },   -- left, top, right, bottom
		open = (oL or oR or oT or oB) and ((oL and "l" or "") .. (oR and "r" or "") .. (oT and "t" or "") .. (oB and "b" or "")) or nil,
		tile = "slice",
	}
	Slices.cuts[key] = cut
	return cut
end

-- The picture on `tex`: file (in the chosen look), crop, margins, tiling
function ApplySlice(tex, cut)
	tex:SetTexture(PieceRoot(cut.prefix .. "_t") .. cut.file)
	tex:SetTexCoord(cut.uv[1], cut.uv[2], cut.uv[3], cut.uv[4])
	tex:SetTextureSliceMargins(cut.margins[1], cut.margins[2], cut.margins[3], cut.margins[4])
	tex:SetTextureSliceMode(Slices.tiled)
end

-- The rails of `skin` as one texture, or nil (the switch off, a gem corner
-- on the skin, the family not built or tuned, a client that cannot cut
-- textures): the caller then lays the pieces. `force`: the test window's
-- true / false over the switch. `was` / `unit`: the switch and the margin
-- unit as they stood when a skin whose rails wait (NineSlice's `defer`) was
-- made, so they are laid as they would have been then.
local function NineSlice_Slice(skin, host, prefix, scale, layer, sub, gemCorners, skip, oL, oR, oT, oB, force, was, unit)
	local want = force
	if want == nil then
		want = was
	end
	if want == nil then
		want = Kit:SlicesOn()
	end
	if not want or Slices.api == false then
		return nil
	end
	-- a gem corner standing in one of the corners: the skin stays in pieces
	-- (above); a corner left mitred, or an open one, does not count
	if gemCorners and ((not (oT or oL) and not skip:find("tl", 1, true)) or (not (oT or oR) and not skip:find("tr", 1, true))
		or (not (oB or oL) and not skip:find("bl", 1, true)) or (not (oB or oR) and not skip:find("br", 1, true))) then
		return nil
	end
	local entry = SliceFamily(prefix)
	local cut = entry and SliceCut(prefix, entry, oL, oR, oT, oB)
	if not cut then
		if force == nil and not Slices.noted then
			Slices.noted = true
			MelloUI:Notice("Kit: no one-texture picture for %s (Media\\KitSlices.lua not loaded, or its pieces tuned): drawn in pieces.", tostring(prefix))
		end
		return nil
	end
	local tex = host:CreateTexture(nil, layer, nil, sub)
	if Slices.api == nil then
		Slices.api = (tex.SetTextureSliceMargins and tex.SetTextureSliceMode and tex.SetScale) and true or false
		if not Slices.api then
			tex:Hide()
			MelloUI:Notice("Kit: this client cannot draw a texture as a nine-slice; the rails stay in pieces.")
			return nil
		end
	end
	ApplySlice(tex, cut)
	tex:SetScale(scale * cut.texel / (unit or SliceUnit()))
	tex:SetAllPoints(skin)
	Kit.pieceOf[tex] = cut
	Kit:RegisterTexture(tex)
	if force == nil and not Slices.noted then
		Slices.noted = true
		MelloUI:Notice("Kit: window rails drawn as one texture each (a test; /mellokit slices off goes back).")
	end
	return tex
end

-- The region along one side of a skin's rails ("t", "b", "l", "r"), to lay
-- something by the rail's rect or centre line: the edge piece; on a skin
-- drawn as one texture, an empty region where that edge would lie (made on
-- first ask, drawn never), shown and hidden with the skin's textures. nil on
-- an open side.
function Kit:RailAnchor(skin, side)
	if not skin then
		return nil
	end
	local have = skin[side]
	if have or not skin.slice then
		return have
	end
	local cut = Kit.pieceOf[skin.slice]
	local open = type(cut) == "table" and cut.open or ""
	if open:find(side, 1, true) then
		return nil
	end
	local oL, oR, oT, oB = open:find("l") ~= nil, open:find("r") ~= nil, open:find("t") ~= nil, open:find("b") ~= nil
	local T = skin.thickness or 0
	local layer, sub = skin.slice:GetDrawLayer()
	local anchor = skin.slice:GetParent():CreateTexture(nil, layer, nil, sub)
	if side == "t" or side == "b" then
		local point = side == "t" and "TOP" or "BOTTOM"
		anchor:SetPoint(point .. "LEFT", skin, point .. "LEFT", oL and 0 or T, 0)
		anchor:SetPoint(point .. "RIGHT", skin, point .. "RIGHT", oR and 0 or -T, 0)
		anchor:SetHeight(T)
	else
		local point = side == "l" and "LEFT" or "RIGHT"
		anchor:SetPoint("TOP" .. point, skin, "TOP" .. point, 0, oT and 0 or -T)
		anchor:SetPoint("BOTTOM" .. point, skin, "BOTTOM" .. point, 0, oB and 0 or T)
		anchor:SetWidth(T)
	end
	Kit.pieceOf[anchor] = true   -- ours: never faded as the game's art
	anchor:SetShown(skin.slice:IsShown())
	skin[side] = anchor
	table.insert(skin.all, anchor)
	return anchor
end

-- a colour on the iron (the selected state of an attached tab). One function
-- for every skin; a skin whose rails wait (`defer`, below) keeps the colour
-- and its rails take it when they are laid
local function NineSlice_SetTint(self, r, g, b)
	if self.pendingArt then
		self.tinted, self.tintR, self.tintG, self.tintB = true, r, g, b
		return
	end
	for _, tex in ipairs(self.art) do
		tex:SetVertexColor(r or 1, g or 1, b or 1)
	end
end

-- A colour of meaning on a skin's rails and corners for a while (0.19.0: a
-- raid frame's rail in the colour of the debuff its unit has, HealerFrames),
-- perhaps secret: handed to the textures as it is (the Dark Mode hook leaves
-- a secret alone). r = nil: each piece's own colour back (the tint it was
-- given before, its base, shaded by Dark Mode as ever).
function Kit:TintSkin(skin, r, g, b)
	if type(skin) ~= "table" or type(skin.art) ~= "table" then
		return
	end
	-- (0.19.8: a border of the library's standing in for the skin's rails --
	-- a raid frame's Raid Frame Border, Kit:RaidBorder -- takes the tint too)
	local more = skin.libraryArt
	if not Secret(r) and r == nil then
		for _, tex in ipairs(skin.art) do
			local base = Kit.tintBaseOf[tex]
			tex:SetVertexColor(base and base[1] or 1, base and base[2] or 1, base and base[3] or 1)
		end
		for _, tex in ipairs(more or {}) do
			tex:SetVertexColor(1, 1, 1)
		end
		return
	end
	for _, tex in ipairs(skin.art) do
		tex:SetVertexColor(r, g, b)
	end
	for _, tex in ipairs(more or {}) do
		tex:SetVertexColor(r, g, b)
	end
end

-- The skin's textures (body, rails, corners, gems, ornament) and the scripts
-- that tile them, from the options it was made with
local function NineSlice_Art(skin, opts)
	local self = Kit
	local prefix = opts.prefix or "window/frame"
	local scale = skin.kitScale
	local host = opts.owner or skin
	local edgeHost = rawget(skin, "railHost") or host   -- (the rails' own frame: Kit:NineSlice's edgeLevel)
	local bodyLayer, bodySub = opts.bodyLayer or "BACKGROUND", opts.bodySub or 0
	local edgeLayer, edgeSub = opts.edgeLayer or "BORDER", opts.edgeSub or 0
	local T = skin.thickness
	local open = opts.open or ""
	local oL, oR, oT, oB = open:find("l") ~= nil, open:find("r") ~= nil, open:find("t") ~= nil, open:find("b") ~= nil

	-- (a painted look draws its plain mitred corners: its gem corners would be plain corners in a shared sheet, which
	-- a border style (Window Border) cannot swap)
	local gemCorners = opts.corners == "gem" and PIECES[prefix .. "_gem_tl"] ~= nil and not LOOK.ART_ROOTS[PieceRoot(prefix .. "_body")]
	local skip = opts.skip or ""
	if opts.body ~= false then
		-- the body reaches under the whole edge when gem corners sit on it:
		-- the interior shows inside their rounded elbows
		local inset = gemCorners and 0 or T / 2
		-- the family's own stone, or another tile (`body` = its name, `bodyScale` its scale)
		local bodyName = type(opts.body) == "string" and opts.body or (prefix .. "_body")
		local body = Tiled(host, bodyName, bodyLayer, bodySub, opts.bodyScale or scale)
		body:SetPoint("TOPLEFT", skin, "TOPLEFT", oL and 0 or inset, oT and 0 or -inset)
		body:SetPoint("BOTTOMRIGHT", skin, "BOTTOMRIGHT", oR and 0 or -inset, oB and 0 or inset)
		skin.body = body
		table.insert(skin.tiled, body)
		table.insert(skin.all, body)
	end

	-- the rails as one texture while the switch is on (opts.slices: the test
	-- window's own choice): the edges and the mitred corners below are then
	-- in it, in the edges' layer
	local slice = NineSlice_Slice(skin, edgeHost, prefix, scale, edgeLayer, edgeSub, gemCorners, skip, oL, oR, oT, oB, opts.slices,
		skin.slicesWas, skin.sliceUnit)
	if slice then
		skin.slice = slice
		table.insert(skin.art, slice)
		table.insert(skin.all, slice)
	end

	-- edges run to the rect's edge on an open side (no corner there)
	local edges = {
		t = { "TOPLEFT", oL and 0 or T, 0, "TOPRIGHT", oR and 0 or -T, 0, skip = oT },
		b = { "BOTTOMLEFT", oL and 0 or T, 0, "BOTTOMRIGHT", oR and 0 or -T, 0, skip = oB },
		l = { "TOPLEFT", 0, oT and 0 or -T, "BOTTOMLEFT", 0, oB and 0 or T, skip = oL },
		r = { "TOPRIGHT", 0, oT and 0 or -T, "BOTTOMRIGHT", 0, oB and 0 or T, skip = oR },
	}
	for e, a in pairs(edges) do
		if not a.skip and not slice then
			local tex = Tiled(edgeHost, prefix .. "_" .. e, edgeLayer, edgeSub, scale)
			tex:SetPoint(a[1], skin, a[1], a[2], a[3])
			tex:SetPoint(a[4], skin, a[4], a[5], a[6])
			if e == "t" or e == "b" then
				tex:SetHeight(T)
			else
				tex:SetWidth(T)
			end
			skin[e] = tex
			table.insert(skin.tiled, tex)
			table.insert(skin.art, tex)
			table.insert(skin.all, tex)
		end
	end

	local corners = { tl = { "TOPLEFT", oT or oL }, tr = { "TOPRIGHT", oT or oR }, bl = { "BOTTOMLEFT", oB or oL }, br = { "BOTTOMRIGHT", oB or oR } }
	for c, a in pairs(corners) do
		if not a[2] then
			local gem = gemCorners and not skip:find(c, 1, true)
			if not gem then
				-- (one texture: in the picture)
				if not slice then
					local tex = self:Texture(edgeHost, prefix .. "_" .. c, edgeLayer, math.min(edgeSub + 1, 7), scale)
					tex:SetPoint(a[1], skin, a[1])
					skin[c] = tex
					table.insert(skin.art, tex)
					table.insert(skin.all, tex)
				end
			else
				-- the painted corner, anchored past the frame's corner by its overhang
				local name = prefix .. "_gem_" .. c
				local o = (PIECES[name].overhang or 0) * scale
				local tex = self:Texture(skin, name, "ARTWORK", 1, scale)
				local sx = (c == "tl" or c == "bl") and -1 or 1
				local sy = (c == "tl" or c == "tr") and 1 or -1
				tex:SetPoint(a[1], skin, a[1], sx * o, sy * o)
				skin[c] = tex
				table.insert(skin.art, tex)
				skin.gemCorner = skin.gemCorner or {}
				skin.gemCorner[c] = { tex = tex, point = a[1] }
			end
		end
	end
	-- `railAnchors`: a region per side on one texture, for a skin whose
	-- rails' rects are read as skin.t / .b / .l / .r (sheets and dims laid
	-- clear of the rails, something riding a rail's centre line). The
	-- window's outer rail, which the character window reads so, has gem
	-- corners and stays in pieces.
	if slice and opts.railAnchors then
		for _, side in ipairs({ "t", "b", "l", "r" }) do
			self:RailAnchor(skin, side)
		end
	end

	if opts.gems ~= false and PIECES["deco/gem_large"] then
		skin.gems = {}
		for c, point in pairs(corners) do
			local gem = self:Texture(skin, c == "tl" and "deco/gem_large" or "deco/gem_small", "ARTWORK", 1, scale)
			local sx = (c == "tl" or c == "bl") and 1 or -1
			local sy = (c == "tl" or c == "tr") and -1 or 1
			gem:SetPoint("CENTER", skin, point, sx * T / 2, sy * T / 2)
			skin.gems[c] = gem
		end
	end
	local ornName = (prefix:gsub("frame$", "corner_ornament_tl"))
	if opts.ornament and PIECES[ornName] then
		local orn = self:Texture(skin, ornName, "ARTWORK", 2, scale)
		orn:SetPoint("TOPLEFT", -4 * scale, 4 * scale)
		skin.ornament = orn
	end

	Perf.SetScript(skin, "OnSizeChanged", NineSlice_OnSize)
	-- a skin sized while hidden gets no OnSizeChanged on this client (the
	-- configurator's sections behind the first tab: one tile stretched over
	-- the box, "blurred" — user, 2026-09-22): tiled again when it shows
	Perf.HookScript(skin, "OnShow", NineSlice_OnShow)
	NineSlice_Retile(skin)
end

-- A skin whose rails wait (`defer`) laid now, with the colour given to it
-- meanwhile. True when it was laid here.
local function NineSlice_Lay(skin)
	local opts = skin and skin.pendingArt
	if not opts then
		return false
	end
	skin.pendingArt = nil
	NineSlice_Art(skin, opts)
	if skin.tinted then
		skin.tinted = nil
		NineSlice_SetTint(skin, skin.tintR, skin.tintG, skin.tintB)
	end
	return true
end

-- `defer` (a panel tab's open card, Kit:SkinPanelTab): the skin frame is
-- made at once, in its place among its siblings, but its textures and
-- scripts wait for NineSlice_Lay, when the card is first shown (user,
-- 2026-09-24: a tab's two cards were ~200 engine calls, and only one of
-- them is ever seen at a time). Not for a skin whose textures are an
-- owner's regions or that has gem corners (SetTopGems reads them).
function Kit:NineSlice(parent, opts)
	opts = opts or {}
	local prefix = opts.prefix or "window/frame"
	local scale = opts.scale or self.scale
	local skin = CreateFrame("Frame", nil, parent)
	skin:SetFrameStrata(parent:GetFrameStrata())
	skin:SetFrameLevel(math.max(parent:GetFrameLevel() + (opts.level or 0), 0))
	skin:EnableMouse(false)
	skin:SetAllPoints(parent)
	skin.melloSkin = true
	skin.kitScale = scale
	-- its rail family and open sides, as made (the shade system lays the
	-- family's shadow round it: Modules/KitShade.lua)
	skin.kitPrefix, skin.kitOpen = prefix, opts.open or ""
	-- `owner`: the textures are REGIONS of that frame (drawn in ITS layer
	-- stack: `bodyLayer` / `bodySub`, `edgeLayer` / `edgeSub`), the skin frame
	-- only laying them out — a compact raid frame's rail above its fill and
	-- under its icons. Show / Hide then toggle the regions.
	local host = opts.owner or skin
	local edgeLayer, edgeSub = opts.edgeLayer or "BORDER", opts.edgeSub or 0
	-- `edgeLevel`: the rails (edges, corners, the one-texture slice) on a frame of their own at that level, the body
	-- and whatever a window hangs on the skin staying at the skin's (a window's thin rail over its panes, as the
	-- game's border: Kit:Replace's rule.atBorder)
	if opts.edgeLevel and not opts.owner then
		local rails = CreateFrame("Frame", nil, skin)
		rails:SetFrameLevel(opts.edgeLevel)
		rails:EnableMouse(false)
		rails:SetAllPoints(skin)
		skin.railHost = rails
	end
	if opts.owner then
		local show, hide = skin.Show, skin.Hide
		skin.Show = function(self)
			show(self)
			for _, tex in ipairs(self.all) do tex:Show() end
		end
		skin.Hide = function(self)
			hide(self)
			for _, tex in ipairs(self.all) do tex:Hide() end
		end
		skin.SetShown = function(self, shown) if shown then self:Show() else self:Hide() end end
	end
	skin.all = {}

	local T = self:Size(prefix .. "_tl", scale)   -- corner = edge thickness
	skin.thickness = T
	skin.tiled = {}
	skin.art = {}

	-- The top gem corners give way to a title plate riding the top rail (its
	-- caps' own gems sit there): plain corners in their place, made when first
	-- needed. `on` false: plain; true: the gems again.
	skin.SetTopGems = function(me, on)
		for _, c in ipairs({ "tl", "tr" }) do
			local gem = me.gemCorner and me.gemCorner[c]
			if gem then
				local plain = me.plainCorner and me.plainCorner[c]
				if not on and not plain then
					plain = self:Texture(host, prefix .. "_" .. c, edgeLayer, edgeSub + 1, scale)
					plain:SetPoint(gem.point, me, gem.point)
					me.plainCorner = me.plainCorner or {}
					me.plainCorner[c] = plain
					table.insert(me.art, plain)
				end
				-- a gem with a shadow partner: its plain twin gets one the same
				-- (each follows its own piece's Show / Hide below)
				if plain and gem.tex.kitShadow and not plain.kitShadow then
					self:ShadowLike(plain, gem.tex)
				end
				gem.tex:SetShown(on and true or false)
				if plain then
					plain:SetShown(not on)
				end
			end
		end
	end

	skin.SetTint = NineSlice_SetTint

	if opts.defer and not opts.owner and opts.corners ~= "gem" then
		-- the switch and its unit as they are now (read again later, they
		-- could have come in with the saved settings meanwhile)
		skin.slicesWas = opts.slices
		if skin.slicesWas == nil then
			skin.slicesWas = self:SlicesOn()
		end
		skin.sliceUnit = SliceUnit()
		skin.pendingArt = opts
		return skin
	end
	NineSlice_Art(skin, opts)
	return skin
end

function Kit:NineSliceInset(skin)
	return skin.thickness
end

-- A frame picture cut into nine on `f` (0.14.0: the action bars' backdrop and
-- the minimap's square frame each had a copy): `parts` = { tl, tr, bl, br, t,
-- b, l, r }, textures on f; `piece` the picture, `k` UI units per piece px,
-- `corner` the corner square (piece px). The corners at f's corners, the
-- edges stretched between them (the picture is even along them). A part
-- showing another piece gets this one (Kit:Apply); `show` shows every part.
-- A part with a shadow partner (Kit:Shadow) shows the same part of the
-- piece's shadow, reaching past the picture's outer sides only
-- (Kit:ShadowCut). Nothing is written onto f: it may be the game's region (a
-- Cooldown Manager icon's; 0.19.8 dropped f.railTC, read by nothing since the
-- action bars' cut moved here). False when the kit has no such piece.
Kit.nineParts = { "tl", "tr", "bl", "br", "t", "b", "l", "r" }

-- The cut itself, as file coordinates ({ u0, u1, v0, v1 } each): the corners
-- tl / tr / bl / br and the rails top / bottom / left / right of `piece`
-- with a `corner` px square. Made once per piece and corner, never changed:
-- CutNine's parts and the action bars' joined backdrops (ActionBarPanel)
-- cut by it. Nil when the kit has no such piece.
local nineCoords = {}   -- [piece][corner] = the cut (no key made per call: CutNine runs on every relayout)
function Kit:NineCoords(piece, corner)
	local byPiece = nineCoords[piece]
	local tc = byPiece and byPiece[corner]
	if tc then
		return tc
	end
	local p = PIECES[piece]
	if not p then
		return nil
	end
	local c, w, h = corner, p.w, p.h
	local u0, u1, v0, v1 = p.uv[1], p.uv[2], p.uv[3], p.uv[4]
	-- (the picture's lines as file coordinates, as u0 + (u1 - u0) * x / w)
	local ua, ub, uc, ud = u0 + (u1 - u0) * 0 / w, u0 + (u1 - u0) * c / w, u0 + (u1 - u0) * (w - c) / w, u0 + (u1 - u0) * w / w
	local va, vb, vc, vd = v0 + (v1 - v0) * 0 / h, v0 + (v1 - v0) * c / h, v0 + (v1 - v0) * (h - c) / h, v0 + (v1 - v0) * h / h
	tc = { tl = { ua, ub, va, vb }, tr = { uc, ud, va, vb }, bl = { ua, ub, vc, vd }, br = { uc, ud, vc, vd },
		top = { ub, uc, va, vb }, bottom = { ub, uc, vc, vd }, left = { ua, ub, vb, vc }, right = { uc, ud, vb, vc } }
	byPiece = byPiece or {}
	nineCoords[piece] = byPiece
	byPiece[corner] = tc
	return tc
end

function Kit:CutNine(f, parts, piece, k, corner, show)
	local p = PIECES[piece]
	if not p then
		return false
	end
	local c, w, h = corner, p.w, p.h
	local nc = self:NineCoords(piece, corner)
	local ua, ub, uc, ud = nc.tl[1], nc.tl[2], nc.tr[1], nc.tr[2]
	local va, vb, vc, vd = nc.tl[3], nc.tl[4], nc.bl[3], nc.bl[4]
	local cs = c * k
	for _, key in ipairs(self.nineParts) do
		local tex = parts[key]
		if Kit.pieceNameOf[tex] ~= piece then
			self:Apply(tex, piece)
		end
		tex.kitScale = k   -- (drawn at k: a shadow partner reaches as far)
		tex:ClearAllPoints()
		if show then
			tex:Show()
		end
	end
	local tl, tr, bl, br = parts.tl, parts.tr, parts.bl, parts.br
	tl:SetPoint("TOPLEFT", f, "TOPLEFT"); tl:SetSize(cs, cs); tl:SetTexCoord(ua, ub, va, vb)
	tr:SetPoint("TOPRIGHT", f, "TOPRIGHT"); tr:SetSize(cs, cs); tr:SetTexCoord(uc, ud, va, vb)
	bl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT"); bl:SetSize(cs, cs); bl:SetTexCoord(ua, ub, vc, vd)
	br:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT"); br:SetSize(cs, cs); br:SetTexCoord(uc, ud, vc, vd)
	local t, b, l, r = parts.t, parts.b, parts.l, parts.r
	t:SetPoint("TOPLEFT", f, "TOPLEFT", cs, 0)
	t:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -cs, -cs)
	t:SetTexCoord(ub, uc, va, vb)
	b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", cs, 0)
	b:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -cs, cs)
	b:SetTexCoord(ub, uc, vc, vd)
	l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -cs)
	l:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", cs, cs)
	l:SetTexCoord(ua, ub, vb, vc)
	r:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -cs)
	r:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", -cs, cs)
	r:SetTexCoord(uc, ud, vb, vc)
	-- the parts' shadow partners: the same cut of the piece's shadow
	if tl.kitShadow then self:ShadowCut(tl, 0, c, 0, c) end
	if tr.kitShadow then self:ShadowCut(tr, w - c, w, 0, c) end
	if bl.kitShadow then self:ShadowCut(bl, 0, c, h - c, h) end
	if br.kitShadow then self:ShadowCut(br, w - c, w, h - c, h) end
	if t.kitShadow then self:ShadowCut(t, c, w - c, 0, c) end
	if b.kitShadow then self:ShadowCut(b, c, w - c, h - c, h) end
	if l.kitShadow then self:ShadowCut(l, 0, c, c, h - c) end
	if r.kitShadow then self:ShadowCut(r, w - c, w, c, h - c) end
	-- (0.20.1) `parts.m`: the middle too (a border style's background, KitBorders' Border:LayBackground)
	local m = parts.m
	if m then
		if Kit.pieceNameOf[m] ~= piece then
			self:Apply(m, piece)
		end
		m.kitScale = k
		m:ClearAllPoints()
		m:SetPoint("TOPLEFT", f, "TOPLEFT", cs, -cs)
		m:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -cs, cs)
		m:SetTexCoord(ub, uc, vb, vc)
		if show then
			m:Show()
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Strip: cap_l + tiled mid + cap_r, all the same height, top-aligned.
--   Kit:Strip(parent, "buttons/textbtn", { state = "normal", width = 200, scale = })
-- strip:SetState("hover"); strip:SetWidth(w); strip.height
--------------------------------------------------------------------------------

local StripMixin = {}

function StripMixin:SetState(state)
	if state == self.state and self.applied then
		return
	end
	self.state, self.applied = state, true
	Kit:Apply(self.capL, StripName(self.base, self.endL and "end_l" or "cap_l", state))
	Kit:Apply(self.mid, StripName(self.base, "mid", state))
	Kit:Apply(self.capR, StripName(self.base, self.endR and "end_r" or "cap_r", state))
	self:SyncActive()
end

-- A list's selected plate (a strip in its "selected" state) wears the active
-- look (Kit:SetActive, 0.15.0) round the strip: regions of the strip frame,
-- shown and hidden with it, or with an `owner` of the frame its pieces are
-- regions of (a row: over its plate), then following the strip's own Show /
-- Hide. Only a strip that was selected turns it off (a row's plain and hover
-- plates share its owner with the selected one)
function StripMixin:SyncActive()
	local on = self.state == "selected"
	if not (on or self.activeWas) then
		return
	end
	local owner = self.kitOwner
	if owner then
		on = on and self:IsShown()
	end
	self.activeWas = on or nil
	Kit:SetActive(owner or self, on, self, "rect")
end

-- Another family of pieces for the strip (a bar's Bar Border), in its state
-- where the family has it: the caps and the mid re-applied and re-sized
function StripMixin:SetBase(base)
	if base == self.base then
		return
	end
	self.base = base
	local state = self.state
	self.state, self.applied = nil, nil
	self.capless, self.noL, self.noR, self.endL, self.endR = nil, nil, nil, nil, nil
	self:SetState(state)
	local scale = self.scale
	self.scale = 0          -- sized afresh for the new pieces
	self:Rescale(scale)
end

-- Change the strip's scale (e.g. once the game element it replaces has its
-- real height): caps resize, the mid retiles, the frame keeps its anchors.
function StripMixin:Rescale(scale)
	if not scale or scale <= 0 or math.abs(scale - self.scale) < 0.001 then
		return
	end
	self.scale = scale
	self.kitScale = scale
	self.capL.kitScale, self.mid.kitScale, self.capR.kitScale = scale, scale, scale
	local wl, h = Kit:Size(StripName(self.base, self.endL and "end_l" or "cap_l", self.state), scale)
	local wr = Kit:Size(StripName(self.base, self.endR and "end_r" or "cap_r", self.state), scale)
	self.height = h
	self.wl, self.wr = wl, wr
	self.capL:SetSize(wl, h)
	self.capR:SetSize(wr, h)
	self.mid:ClearAllPoints()
	self.mid:SetPoint("TOPLEFT", self, "TOPLEFT", (self.capless or (self.noL and not self.endL)) and 0 or wl, 0)
	self.mid:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", (self.capless or (self.noR and not self.endR)) and 0 or -wr, 0)
	Kit:Retile(self.mid)
	-- the parts' shadow partners reach as far at the new scale (Kit:Shadow)
	if self.capL.kitShadow or self.mid.kitShadow or self.capR.kitShadow then
		Kit:ShadowFit(self.capL)
		Kit:ShadowFit(self.mid)
		Kit:ShadowFit(self.capR)
	end
end

-- Scale so the strip's natural height equals `height` (0 or nil: no change).
function StripMixin:FitHeight(height)
	if not height or height <= 0 then
		return
	end
	local natural = select(2, Kit:Size(StripName(self.base, "cap_l", self.state), 1))
	if natural > 0 then
		self:Rescale(height / natural)
	end
end

-- Scale so the OPAQUE part of the mid (its box) is `height` tall, and return
-- the vertical offset that puts that box on the centre line of whatever the
-- strip is anchored to (the art is not always centred in its canvas).
function StripMixin:FitBox(height)
	if not height or height <= 0 then
		return 0
	end
	local p = PIECES[StripName(self.base, "mid", self.state)]
	if not (p and p.box) then
		self:FitHeight(height)
		return 0
	end
	local boxH = p.box[4] - p.box[2]
	if boxH <= 0 then
		self:FitHeight(height)
		return 0
	end
	self:Rescale(height / boxH)
	local boxCentre = (p.box[2] + p.box[4]) / 2
	return (boxCentre - p.h / 2) * self.scale
end

-- The scale at which the WHOLE strip, its caps included, is `height` tall,
-- and the height its box (the opening) has at that scale. Both come from the
-- art alone, never from the current layout, so a panel can size what sits in
-- the opening before the strip has been refitted. For a bracket that must fit
-- a row rather than hug its bar (the damage meter's rows, user 2026-09-23:
-- "scale down the artwork ... to fit").
function StripMixin:FitWhole(height)
	if not height or height <= 0 then
		return nil
	end
	local natural = select(2, Kit:Size(StripName(self.base, self.endL and "end_l" or "cap_l", self.state), 1))
	local p = PIECES[StripName(self.base, "mid", self.state)]
	if not (natural and natural > 0 and p and p.box) then
		return nil
	end
	local scale = height / natural
	return scale, (p.box[4] - p.box[2]) * scale
end

-- A rect narrower than the two caps shows the mid alone (the caps would
-- overlap): the caps are hidden and the mid spans the whole strip.
function StripMixin:FitCaps(width)
	-- the caps' widths as computed (never read back: a region under a unit
	-- frame answers with a secret number on this client)
	local wl, wr = self.wl or 0, self.wr or 0
	local capless = self.forceCapless or (width and width > 0 and width < wl + wr + 4)
	-- `dropCap`: one cap left out ("l" / "r"), the mid running to that edge
	local noL = capless or self.dropCap == "l"
	local noR = capless or self.dropCap == "r"
	if capless == self.capless and noL == self.noL and noR == self.noR then
		if width and width > 0 then
			self.mid.kitTileW = width - ((noL and not self.endL) and 0 or wl) - ((noR and not self.endR) and 0 or wr)
			self.mid.kitTileH = self.height
			Kit:Retile(self.mid)
		end
		return
	end
	-- (the caps' shadow partners follow their Show / Hide; the mid's, made
	-- with opts.ends, takes a soft end where it now runs to the strip's end,
	-- below)
	self.capless, self.noL, self.noR = capless, noL, noR
	-- a dropped cap closes with the family's gemless end piece
	-- (<base>_end_l/r_<state>, made by Tools/make_plain_plate.py) when it has one
	local endL = noL and not capless and PIECES[StripName(self.base, "end_l", self.state)]
	local endR = noR and not capless and PIECES[StripName(self.base, "end_r", self.state)]
	if endL then
		Kit:Apply(self.capL, StripName(self.base, "end_l", self.state))
		wl = select(1, Kit:Size(StripName(self.base, "end_l", self.state), self.scale))
		self.capL:SetWidth(wl)
		self.wl = wl
	end
	if endR then
		Kit:Apply(self.capR, StripName(self.base, "end_r", self.state))
		wr = select(1, Kit:Size(StripName(self.base, "end_r", self.state), self.scale))
		self.capR:SetWidth(wr)
		self.wr = wr
	end
	self.endL, self.endR = endL and true or nil, endR and true or nil
	self.capL:SetShown(not noL or endL)
	self.capR:SetShown(not noR or endR)
	self.mid:ClearAllPoints()
	self.mid:SetPoint("TOPLEFT", self, "TOPLEFT", (noL and not endL) and 0 or wl, 0)
	self.mid:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", (noR and not endR) and 0 or -wr, 0)
	-- the mid's size as laid out, for a Retile that cannot read it back
	if width and width > 0 then
		self.mid.kitTileW = width - ((noL and not endL) and 0 or wl) - ((noR and not endR) and 0 or wr)
		self.mid.kitTileH = self.height
	end
	Kit:Retile(self.mid)
	-- the mid's ends with no cap and no end piece: its shadow partner (one
	-- made with opts.ends) fades out softly there instead of stopping square
	-- (Kit:Shadow)
	self.mid.kitOpenL = (noL and not endL) and true or false
	self.mid.kitOpenR = (noR and not endR) and true or false
	if self.mid.kitShadow then
		Kit:ShadowFit(self.mid)
	end
end

-- Insets of the mid's opening (left cap, right cap, top, bottom), for content.
function StripMixin:GetInsets()
	local _, _, top, bottom = Kit:Insets(StripName(self.base, "mid", self.state), self.scale)
	return self.wl or 0, self.wr or 0, top or 0, bottom or 0
end

function Kit:Strip(parent, base, opts)
	opts = opts or {}
	local scale = opts.scale
	if not scale or scale <= 0 then
		scale = self.scale
	end
	local state = opts.state or self:FirstState(base, "mid")
	local f = CreateFrame("Frame", nil, parent)
	f:EnableMouse(false)
	Mixin(f, StripMixin)
	f.base, f.scale, f.kitScale = base, scale, scale

	local layer, sub = opts.layer or "ARTWORK", opts.sublevel or 0
	-- `owner`: the textures are regions of that frame (drawn in ITS layer
	-- stack, between its own regions); the strip frame only lays them out
	local host = opts.owner or f
	f.capL = host:CreateTexture(nil, layer, nil, sub)
	f.mid = host:CreateTexture(nil, layer, nil, sub - 1)
	f.capR = host:CreateTexture(nil, layer, nil, sub)
	f.capL.kitScale, f.mid.kitScale, f.capR.kitScale = scale, scale, scale
	if opts.owner then
		local show, hide = f.Show, f.Hide
		f.kitOwner = opts.owner   -- (its active look is the owner's regions: StripMixin:SyncActive)
		f.Show = function(self) show(self); self.capL:SetShown(not self.noL or self.endL); self.mid:Show(); self.capR:SetShown(not self.noR or self.endR); self:SyncActive() end
		f.Hide = function(self) hide(self); self.capL:Hide(); self.mid:Hide(); self.capR:Hide(); self:SyncActive() end
		f.SetShown = function(self, shown) if shown then self:Show() else self:Hide() end end
	end

	local wl, h = self:Size(StripName(base, "cap_l", state), scale)
	local wr = self:Size(StripName(base, "cap_r", state), scale)
	f.height = h
	f.wl, f.wr = wl, wr
	f:SetSize(opts.width or (wl + wr + 4 * self:Size(StripName(base, "mid", state), scale)), h)

	f.capL:SetPoint("TOPLEFT", f, "TOPLEFT")
	f.capL:SetSize(wl, h)
	f.capR:SetPoint("TOPRIGHT", f, "TOPRIGHT")
	f.capR:SetSize(wr, h)
	f.mid:SetPoint("TOPLEFT", f, "TOPLEFT", wl, 0)
	f.mid:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -wr, 0)
	Perf.SetScript(f, "OnSizeChanged", function(self)
		Kit:Retile(self.mid)
	end)
	f:SetState(state)
	Kit:Retile(f.mid)
	return f
end

--------------------------------------------------------------------------------
-- VStrip: an upright strip, cap_t + tiled mid + cap_b, all the same width,
-- for a scroll thumb. The caps shrink when the strip is shorter than both.
--   Kit:VStrip(parent, "lists/scrollthumb", { state = "normal", scale = })
-- strip:SetState("hover"); strip:FitWidth(w) scales it to that width.
--------------------------------------------------------------------------------

local VStripMixin = {}

function VStripMixin:SetState(state)
	if state == self.state and self.applied then
		return
	end
	self.state, self.applied = state, true
	Kit:Apply(self.capT, StripName(self.base, "cap_t", state))
	Kit:Apply(self.mid, StripName(self.base, "mid", state))
	Kit:Apply(self.capB, StripName(self.base, "cap_b", state))
end

function VStripMixin:Layout()
	local w, h = self:GetSize()
	local capH = self.capH
	if h > 0 and capH * 2 > h then
		capH = h / 2                          -- a thumb shorter than its two gems
	end
	self.capT:SetSize(w, capH)
	self.capB:SetSize(w, capH)
	self.mid:ClearAllPoints()
	self.mid:SetPoint("TOPLEFT", 0, -capH)
	self.mid:SetPoint("BOTTOMRIGHT", 0, capH)
	Kit:Retile(self.mid)
end

-- Scale so the piece's natural width equals `width` (0 or nil: no change).
function VStripMixin:FitWidth(width)
	if not width or width <= 0 then
		return
	end
	local natural, capH = Kit:Size(StripName(self.base, "cap_t", self.state), 1)
	if natural <= 0 then
		return
	end
	local scale = width / natural
	self.scale, self.kitScale = scale, scale
	self.capT.kitScale, self.mid.kitScale, self.capB.kitScale = scale, scale, scale
	self.capH = capH * scale
	self:SetWidth(width)
	self:Layout()
	-- the parts' shadow partners reach as far at the new scale (as a Strip's)
	if self.capT.kitShadow or self.mid.kitShadow or self.capB.kitShadow then
		Kit:ShadowFit(self.capT)
		Kit:ShadowFit(self.mid)
		Kit:ShadowFit(self.capB)
	end
end

function Kit:VStrip(parent, base, opts)
	opts = opts or {}
	local scale = opts.scale
	if not scale or scale <= 0 then
		scale = self.scale
	end
	local state = opts.state or self:FirstState(base, "mid")
	local f = CreateFrame("Frame", nil, parent)
	f:EnableMouse(false)
	Mixin(f, VStripMixin)
	f.base, f.scale, f.kitScale = base, scale, scale
	local layer, sub = opts.layer or "ARTWORK", opts.sublevel or 0
	f.capT = f:CreateTexture(nil, layer, nil, sub)
	f.mid = f:CreateTexture(nil, layer, nil, sub - 1)
	f.capB = f:CreateTexture(nil, layer, nil, sub)
	f.capT.kitScale, f.mid.kitScale, f.capB.kitScale = scale, scale, scale
	local w, capH = self:Size(StripName(base, "cap_t", state), scale)
	f.capH = capH
	f:SetSize(w, 3 * capH)
	f.capT:SetPoint("TOPLEFT")
	f.capB:SetPoint("BOTTOMLEFT")
	Perf.SetScript(f, "OnSizeChanged", function(self)
		self:Layout()
	end)
	f:SetState(state)
	f:Layout()
	return f
end

--------------------------------------------------------------------------------
-- Bar: trough tiled under the frame strip, the frame over it, and `fill`, a
-- frame covering the opening, for a StatusBar (or any fill texture).
--   Kit:Bar(parent, { kind = "frame" | "castbar", width = , scale = })
--------------------------------------------------------------------------------

function Kit:Bar(parent, opts)
	opts = opts or {}
	local kind = opts.kind or "frame"
	local scale = opts.scale or self.scale
	local base = "bars/" .. kind
	local strip = self:Strip(parent, base, { width = opts.width, scale = scale, layer = "ARTWORK", sublevel = 2 })

	-- the opening runs from inside the left cap's hollow arm to inside the right one
	local _, _, top, bottom = strip:GetInsets()
	local capL, capR = PIECES[base .. "_cap_l"], PIECES[base .. "_cap_r"]
	local left = capL and capL.open and capL.open[1] * scale or strip.wl
	local right = capR and capR.open and (capR.w - capR.open[3]) * scale or strip.wr
	-- frame art two levels above the fill, so a StatusBar parented to `fill`
	-- (one level above it) still draws under the rim
	local base_level = parent:GetFrameLevel()
	strip:SetFrameLevel(base_level + 3)
	local fill = CreateFrame("Frame", nil, strip)
	fill:SetFrameLevel(base_level + 1)
	fill:SetPoint("TOPLEFT", left, -top)
	fill:SetPoint("BOTTOMRIGHT", -right, bottom)
	strip.fill = fill

	local trough = fill:CreateTexture(nil, "BACKGROUND", nil, 0)
	trough.kitScale = scale
	self:Apply(trough, "bars/trough")
	trough:SetPoint("TOPLEFT", -2 * scale, 0)
	trough:SetPoint("BOTTOMRIGHT", 2 * scale, 0)
	strip.trough = trough
	Perf.SetScript(fill, "OnSizeChanged", function()
		Kit:Retile(trough)
	end)
	Kit:Retile(trough)
	return strip
end

--------------------------------------------------------------------------------
-- The active look (0.15.0; user, 2026-09-28: "people cant see in which stance
-- they are as a warrior ... dont just make the stance bar, do it across the
-- board"; option C of the sketch): a thick gold ring lit additively round the
-- button, a soft halo just outside it, a soft glow inside its edge, and the
-- button's icon lifted about 1.2 x with no tint. ONE look for everything the
-- game or MelloUI shows as active, checked or selected, fed by the kit's own
-- followers of that state (the game's calls and its own updates, never a
-- poll):
--   a slot rim's or a state texture's checked flag (Slot_Update: the action,
--     stance, pet and possess bars, the bag bar, the micro menu, side tabs,
--     the spell book's category tabs, icon boxes, check boxes); a rim's own
--     checked colour gives way to it, a check box keeps its tick beside it
--   a frame kind's checked() (a selected tall row, R3: FrameTint)
--   a strip in its "selected" state (a list's selected plate)
--   a rule marked `active`, while its piece shows (the open tab's card, TB6)
--   a rule of kind "active": a check button of the game's own art the kit
--     does not dress (the extra action button, the vehicle bar), the look in
--     place of its checked art
--   the own windows' chosen card and side-list marker (Core/Widgets.lua)
-- The art is Media\Textures\ActiveLook (Tools\make_active_look.py): white
-- cells, the light (ring, halo, glow) tinted with the palette's selectedTrim
-- and added as light, the ring's two dark edge lines (the kit art rule) tinted
-- with its innerPanel and blended over it, both by palette key (Kit:Paint: a
-- new palette paints them again). A square button or a round rim takes a
-- whole cell, one texture a layer; an oblong rect (a tab, a row, a card) the
-- cell cut into nine (the corners CORNER units at the look's scale, the edges
-- stretched along their length, the middle never drawn). A tab, a row or a
-- card hold text: their cut stops at the ring's inner dark line, so they wear
-- the ring, its lines and the halo without the inner glow.
--   Kit:SetActive(host, on, rect, shape, icon)
--     host   the frame whose REGIONS the look is, in its OVERLAY layer: over
--            its art, under its child frames (a pet button's autocast shine
--            and a cooldown's swipe stay on top). On a secure button only
--            regions of ours are made, set and shown: allowed in combat
--     on     true / false, or a SECRET boolean (a flag handed over secret in
--            combat): shown then with SetAlphaFromBoolean, the client's way
--            to show what cannot be read (again after a palette's repaint);
--            the next plain answer lays it again. A look first made for a
--            secret is its two layers only (no icon copy, no hooks) until a
--            plain answer shows it
--     rect   the region the ring lies round (default host); shape "square"
--            (a button: the look scales with its size, HOST units at 1),
--            "rect" (a tab, a row, a card: RECT_SCALE, thinner) or
--            "round" (a round rim); icon: the texture it lifts, a copy of it
--            added as light at LIFT one sublevel over it (a cooldown's swipe
--            still darkens it). Read when the look is made; an icon handed
--            over later is lifted instead
--   Kit:ActiveShown(host) -> whether its look shows now (tests, dumps)
--   Kit:ActiveFamily(rim) -> how a rim or state texture shows its checked
--            state: "look" (the active look stands in for its checked
--            colour), "both" (a check box: its tick stays, the look beside
--            it) or nil (it has none: a cog, an arrow, a close button)
--   Kit:RimDrivesLook(rim) -> whether its checked state is the look (it has
--            a checked source of its own), Kit:ActiveShape(rim) -> "round"
--            for the round rims' families, else "square"
--   Kit:ActiveCounts() -> looks made, textures made
-- Nothing is made for a host that is never active, and a look wanted while
-- its host cannot be seen is made on the host's next show (a window dressed
-- at login makes none, WINDOW-RULES 2f). Once made, a change is a Show / Hide
-- of its textures: no table, no closure.
--------------------------------------------------------------------------------
do
	local FILE = "Interface\\AddOns\\MelloUI\\Media\\Textures\\ActiveLook"
	-- the art's geometry (Tools/make_active_look.py; the tests hold the two
	-- equal): four cells, each a quarter of the file, drawn round a HOST-unit
	-- square (an action button at scale 1) with HALO units of light outside
	-- it and INNER inside. A square or round rect takes a whole cell (one
	-- texture a layer, HALO / HOST of its size past each side); an oblong one
	-- the nine-slice, its corners CORNER units, CUT of the cell
	local HALO, INNER, HOST = 8, 12, 45
	local CORNER = HALO + INNER
	local CUT = CORNER / (HOST + 2 * HALO)
	-- a tab, a row, a card (shape "rect") hold text: their nine-slice is cut
	-- through the ring's inner dark line, RING_IN units in (the tool's RING_H
	-- + GAP), and the glow past it is never drawn (review, 2026-09-28: it
	-- washed the selected row's label gold)
	local RING_IN = 4.4
	local RECT_CORNER = HALO + RING_IN
	local RECT_CUT = RECT_CORNER / (HOST + 2 * HALO)
	local RECT_SCALE = 0.7     -- a tab's, a row's, a card's look
	local MIN_SCALE, MAX_SCALE = 0.4, 1.3
	local ROUND_SIZE = 36      -- a round rim not laid out yet
	local LIFT = 0.2           -- the icon's copy added at this: the icon about 1.2 x as bright
	local LIGHT_SUB, EDGE_SUB = 6, 7   -- OVERLAY sublevels: over the rims (3) and their glow (4)
	local Num = MelloUI.Safe.Number
	-- the nine pieces (the middle never drawn): where each is cut from, u0,
	-- u1, v0, v1 as shares of its cell
	local PARTS = { "tl", "t", "tr", "l", "r", "bl", "b", "br" }
	local function Cuts(c)
		return {
			tl = { 0, c, 0, c }, t = { c, 1 - c, 0, c }, tr = { 1 - c, 1, 0, c },
			l = { 0, c, c, 1 - c }, r = { 1 - c, 1, c, 1 - c },
			bl = { 0, c, 1 - c, 1 }, b = { c, 1 - c, 1 - c, 1 }, br = { 1 - c, 1, 1 - c, 1 },
		}
	end
	local CUTS, RECT_CUTS = Cuts(CUT), Cuts(RECT_CUT)
	local WHOLE = { 0, 1, 0, 1 }
	local looks = setmetatable({}, { __mode = "k" })   -- [host] = its look
	local liftOf = setmetatable({}, { __mode = "k" })  -- [icon] = the look lifting it
	local secretLooks = setmetatable({}, { __mode = "k" })   -- [look] = true while a secret flag shows it
	local made, textures = 0, 0

	-- the host can be seen (a secret answer: taken as seen, the look made)
	local function Seen(frame)
		local ok, v = pcall(frame.IsVisible, frame)
		return not ok or Secret(v) or v == true
	end

	-- the look's scale (k), the rect's short side (nil: not known yet) and
	-- whether it takes a whole cell: a round rim always, a square one while
	-- its scale is in range (short / HOST); an oblong one (a tab, a row) the
	-- nine-slice at RECT_SCALE, a square one out of range or of no known size
	-- the nine-slice at its clamped scale, the inner light of two opposite
	-- edges never meeting (a short row, a small box)
	local function ScaleOf(look)
		local w, h = Kit:DrawnSize(look.rect)
		local short = (w > 0 and h > 0) and math.min(w, h) or nil
		if look.shape == "round" then
			return (short or ROUND_SIZE) / HOST, short, true
		end
		if look.shape ~= "rect" and short and math.abs(w - h) < 0.5 then
			local k = short / HOST
			if k >= MIN_SCALE and k <= MAX_SCALE then
				return k, short, true
			end
		end
		local k, inner = RECT_SCALE, RING_IN
		if look.shape ~= "rect" then
			k, inner = math.max(MIN_SCALE, math.min(MAX_SCALE, short and short / HOST or 1)), INNER
		end
		if short and 2 * inner * k > short then
			k = short / (2 * inner)
		end
		return k, short, false
	end

	-- the pieces laid round the rect at scale k: a whole cell HALO * k past
	-- each side of it; the nine-slice's corners hung on the rect's (HALO * k
	-- outside it), its edges between them
	local function Lay(look, k)
		look.k = k
		local rect = look.rect
		for layer = 1, 2 do
			local list = layer == 1 and look.light or look.edge
			if look.whole then
				local pad = HALO * k
				local tex = list[1]
				tex:ClearAllPoints()
				tex:SetPoint("TOPLEFT", rect, "TOPLEFT", -pad, pad)
				tex:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", pad, -pad)
			else
				local h, c = HALO * k, (look.shape == "rect" and RECT_CORNER or CORNER) * k
				local tl, t, tr, l, r, bl, b, br = list[1], list[2], list[3], list[4], list[5], list[6], list[7], list[8]
				tl:ClearAllPoints()
				tl:SetPoint("TOPLEFT", rect, "TOPLEFT", -h, h)
				tr:ClearAllPoints()
				tr:SetPoint("TOPRIGHT", rect, "TOPRIGHT", h, h)
				bl:ClearAllPoints()
				bl:SetPoint("BOTTOMLEFT", rect, "BOTTOMLEFT", -h, -h)
				br:ClearAllPoints()
				br:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", h, -h)
				tl:SetSize(c, c)
				tr:SetSize(c, c)
				bl:SetSize(c, c)
				br:SetSize(c, c)
				if not look.laid then
					t:SetPoint("TOPLEFT", tl, "TOPRIGHT")
					t:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
					b:SetPoint("TOPLEFT", bl, "TOPRIGHT")
					b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
					l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
					l:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
					r:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
					r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
				end
			end
		end
		look.laid = true
	end

	-- the rect's size again (a new size read on the host's OnSizeChanged or a
	-- new show of the look): laid again only when its scale moved (a look
	-- keeps the pieces it was made with: a whole cell stays one)
	local function Refit(look)
		local k = ScaleOf(look)
		if k ~= look.k then
			Lay(look, k)
		end
	end

	-- the lifted icon's copy as the game has the icon now: its picture,
	-- crop, colour, grey and alpha (secret answers passed straight on: the
	-- client takes them), shown while the icon is and the look on
	local function LiftSync(look)
		local copy, icon = look.lift, look.icon
		if not (copy and icon) then
			return
		end
		copy:SetTexture(icon:GetTexture())
		copy:SetTexCoord(icon:GetTexCoord())
		copy:SetVertexColor(icon:GetVertexColor())
		if icon.IsDesaturated and copy.SetDesaturated then
			copy:SetDesaturated(icon:IsDesaturated())
		end
		-- (after the colour: this client resets a texture's alpha in
		-- SetVertexColor); the icon's own alpha too (an empty extra button's
		-- is 0), when it reads plainly
		local a = Num(icon:GetAlpha())
		copy:SetAlpha(LIFT * (a or 1))
		local ok, shown = pcall(icon.IsShown, icon)
		copy:SetShown(look.on == true and (not ok or Secret(shown) or shown == true))
	end

	-- the icon's own changes while the look is on (one handler for every
	-- lifted icon's methods, the look kept by its icon)
	local Lift_OnIcon = Shared("the icon of a button in the active look", function(icon)
		local look = liftOf[icon]
		if look and look.on == true and look.lift then
			LiftSync(look)
		end
	end)
	local LIFT_METHODS = { "SetTexture", "SetAtlas", "SetTexCoord", "SetVertexColor", "SetDesaturated", "SetAlpha",
		"Show", "Hide", "SetShown" }

	-- the copy that lifts the icon, a region of the icon's own frame one
	-- sublevel over it (made once a look; a new icon moves it there)
	local function Lift(look)
		local icon = look.icon
		if not (icon and icon.GetTexture and icon.GetParent) then
			return
		end
		local copy = look.lift
		if not copy then
			local owner = icon:GetParent() or look.host
			local okL, layer, sub = pcall(icon.GetDrawLayer, icon)
			if not (okL and type(layer) == "string" and not Secret(layer)) then
				layer, sub = "ARTWORK", 0
			end
			sub = Num(sub) or 0
			copy = owner:CreateTexture(nil, layer, nil, math.min(sub + 1, 7))
			copy:SetBlendMode("ADD")
			Kit.pieceOf[copy] = true   -- ours: never faded as the game's art
			copy:Hide()
			look.lift = copy
			textures = textures + 1
		end
		copy:ClearAllPoints()
		copy:SetAllPoints(icon)
		-- the icon's own masks on the copy too (a button the kit leaves in
		-- the game's art keeps its rounded mask: the extra action button)
		local okN, n = pcall(icon.GetNumMaskTextures, icon)
		n = okN and Num(n) or 0
		for i = 1, n do
			local okM, mask = pcall(icon.GetMaskTexture, icon, i)
			if okM and mask and not Secret(mask) then
				pcall(copy.AddMaskTexture, copy, mask)
			end
		end
		if liftOf[icon] == nil then
			for _, m in ipairs(LIFT_METHODS) do
				if type(icon[m]) == "function" then
					hooksecurefunc(icon, m, Lift_OnIcon)
				end
			end
		end
		liftOf[icon] = look
	end

	-- a look's textures, made the first time it shows: a light and an edge
	-- texture (a whole cell), or eight of each (the nine-slice), hidden,
	-- painted by palette key; the host's size followed from then on
	local Active_OnSize = Shared("OnSizeChanged on a host of the active look", function(host)
		local look = looks[host]
		if look and look.built then
			Refit(look)
		end
	end, "script")

	-- the icon lifted and the host's size followed: on a look's first plain
	-- show (a look first made for a secret flag in a fight waits for one)
	local function Complete(look)
		look.lean = nil
		if look.icon then
			Lift(look)
		end
		if look.host.HookScript then
			Perf.HookScript(look.host, "OnSizeChanged", Active_OnSize)
		end
	end

	-- `lean`: the two layers only (a fight's first secret flags reach every
	-- action button: no copy of its icon, no hooks, until one reads true)
	local function Build(look, lean)
		look.built = true
		local host = look.host
		local k, _, whole = ScaleOf(look)
		look.whole = whole
		look.light, look.edge = {}, {}
		local cuts = look.shape == "rect" and RECT_CUTS or CUTS
		for layer = 1, 2 do
			local list = layer == 1 and look.light or look.edge
			local u0, v0 = layer == 1 and 0 or 0.5, look.shape == "round" and 0.5 or 0
			for i = 1, whole and 1 or #PARTS do
				local c = whole and WHOLE or cuts[PARTS[i]]
				local tex = host:CreateTexture(nil, "OVERLAY", nil, layer == 1 and LIGHT_SUB or EDGE_SUB)
				tex:SetTexture(FILE)
				tex:SetTexCoord(u0 + c[1] * 0.5, u0 + c[2] * 0.5, v0 + c[3] * 0.5, v0 + c[4] * 0.5)
				if layer == 1 then
					tex:SetBlendMode("ADD")
				end
				Kit.pieceOf[tex] = true   -- ours: never faded as the game's art
				Kit:Paint(tex, layer == 1 and "selectedTrim" or "innerPanel", "vertex", 1)
				tex:Hide()
				list[i] = tex
			end
			textures = textures + #list
		end
		Lay(look, k)
		if lean then
			look.lean = true
		else
			Complete(look)
		end
	end

	-- a secret flag shown (look.secretOn): the pieces take it as their alpha,
	-- the client's way to show what cannot be read; the icon's copy with them
	local function ShowSecret(look)
		local on = look.secretOn
		for layer = 1, 2 do
			local list = layer == 1 and look.light or look.edge
			for i = 1, #list do
				local tex = list[i]
				if tex.SetAlphaFromBoolean then
					tex:SetAlphaFromBoolean(on, 1, 0)
					tex:Show()
				end
			end
		end
		look.alphaSet = true
		local copy = look.lift
		if copy and copy.SetAlphaFromBoolean then
			LiftSync(look)
			copy:SetAlphaFromBoolean(on, LIFT, 0)
			copy:Show()
		end
	end

	-- a new palette's repaint (Kit:Paint: SetVertexColor, which resets a
	-- texture's alpha on this client) showed every piece a secret flag had
	-- hidden: those looks take their flag again. Heard after the repaint (the
	-- listener is taken on the first secret show, after the look's own Paint
	-- took Kit:Paint's)
	local paletteHeard = false
	local function Active_OnPalette()
		for look in pairs(secretLooks) do
			if look.secret and look.built then
				ShowSecret(look)
			end
		end
	end

	-- plain: every piece shown or hidden at full strength (after a secret
	-- answer their alpha is the client's), the icon's copy with them
	local function ShowLook(look, on)
		for layer = 1, 2 do
			local list = layer == 1 and look.light or look.edge
			for i = 1, #list do
				local tex = list[i]
				if look.alphaSet then
					tex:SetAlpha(1)
				end
				tex:SetShown(on)
			end
		end
		look.alphaSet = nil
		if look.lift then
			if on then
				LiftSync(look)
			else
				look.lift:Hide()
			end
		end
	end

	-- a look wanted while its host could not be seen: made on its next show
	-- (one handler for every host)
	local Active_OnShow = Shared("OnShow on a host of the active look", function(host)
		local look = looks[host]
		if look and look.on == true and not look.built then
			Build(look)
			ShowLook(look, true)
		end
	end, "script")

	-- a look first wanted: made on the next frame, when whatever dressed its
	-- host this frame is through (a piece is dressed shown and hidden at the
	-- end of its dress: a list's selected plate on every row), if it is still
	-- wanted and its host can be seen; else on the host's next show (hooked
	-- once, the hook idle afterwards)
	local function Active_Later(look)
		if look.on ~= true or look.built then
			return
		end
		local host = look.host
		if Seen(host) then
			Build(look)
			ShowLook(look, true)
		elseif not look.waiting then
			look.waiting = true
			if host.HookScript then
				Perf.HookScript(host, "OnShow", Active_OnShow)
			end
		end
	end

	function Kit:SetActive(host, on, rect, shape, icon)
		if type(host) ~= "table" or type(host.CreateTexture) ~= "function" then
			return   -- (no frame to hang it on: a stand-in, a region)
		end
		local look = looks[host]
		local secret = Secret(on)
		if not look then
			if secret then
				-- (a hidden bar's buttons get their flags too: laid by the next
				-- plain answer, as it shows)
				if not Seen(host) then
					return
				end
			elseif not on then
				return   -- never active: nothing made
			end
			look = { host = host, rect = rect or host, shape = shape or "square", on = false }
			looks[host] = look
			made = made + 1
		end
		if icon ~= nil and icon ~= look.icon then
			look.icon = icon
			if look.built and not look.lean then
				Lift(look)
			end
		end
		if secret then
			-- (the flag cannot be read: the pieces take it as their alpha, and
			-- the next plain answer lays the look again, whatever it was)
			look.on, look.secret, look.secretOn = "secret", true, on
			if not look.built then
				Build(look, true)
			end
			ShowSecret(look)
			secretLooks[look] = true
			if not paletteHeard and MelloUI.On then
				paletteHeard = true
				MelloUI:On("palette", Active_OnPalette, "Kit active look")
			end
			return
		end
		on = on and true or false
		if on == look.on and not look.secret then
			return
		end
		look.on, look.secret, look.secretOn = on, nil, nil
		secretLooks[look] = nil
		if not look.built then
			if on then
				Kit:NextFrame(look, Active_Later)
			end
			return
		elseif on then
			if look.lean then
				Complete(look)
			end
			Refit(look)
		end
		ShowLook(look, on)
	end

	function Kit:ActiveShown(host)
		local look = host and looks[host]
		if not (look and look.built and look.on) then
			return false
		end
		local ok, shown = pcall(look.light[1].IsVisible, look.light[1])
		return ok and not Secret(shown) and shown == true
	end

	function Kit:ActiveFamily(rim)
		local fixed = rawget(rim, "activeFamily")   -- (the kit's own field, never an object's)
		if fixed ~= nil then
			return fixed or nil
		end
		local base = rim.base
		if type(base) ~= "string" then
			return nil
		end
		local c = Resolution(base).checked
		if c == "checked" or (not c and rim.glow) then
			return "look"   -- a rim's lit colour, or its additive glow: the look stands in for it
		end
		return c and "both" or nil
	end

	-- Kit:RimDrivesLook(rim): its checked state is its button's active look
	-- (a checked source of its own: a panel's checked(), a check button's
	-- flag; and a family that shows it). An icon's rim on a list row only
	-- hovers: it never switches off the look the row's selected plate lays
	-- (one look a host; review, 2026-09-28)
	function Kit:RimDrivesLook(rim)
		local b = rim.button
		return (rim.isChecked or (b and b.GetChecked)) and self:ActiveFamily(rim) ~= nil or false
	end

	-- Kit:ActiveShape(rim): round for the round rims' families (Round
	-- Border: buttons/roundslot, buttons/roundrim*), square for every other.
	-- Button Border's "Rounded corners" (buttons/rimround) is a square: the
	-- round look on it was a circle across the icon's corners (review,
	-- 2026-09-28). Read from the rim's base as it is (a border switch keeps
	-- to its family: square rims stay square, round ones round)
	function Kit:ActiveShape(rim)
		local base = rim.base
		return (type(base) == "string" and base:find("^buttons/round")) and "round" or "square"
	end

	function Kit:ActiveCounts()
		return made, textures
	end
end

--------------------------------------------------------------------------------
-- Slot: the painted rim over a button's icon; hover / pressed / checked follow
-- the button. The button's own art should be faded by the caller.
--   Kit:Slot(button, { kind = "slot" | "roundslot", icon = texture, scale = , checked = function })
-- The icon is anchored into the opening when given.
--------------------------------------------------------------------------------

-- the rims whose hover is set, for the re-read after a mouse release (below);
-- kept here, as a panel may set a rim's hover itself before its Update
local hoverRims = setmetatable({}, { __mode = "k" })
-- LitWatch(rim, lit): a rim lit (hovered or pressed) is read again a second
-- on, and on while it stays lit (the readers below)
local LitWatch

local function Slot_Update(rim)
	hoverRims[rim] = rim.hover and true or nil
	LitWatch(rim, rim.hover or rim.pressed)
	local b = rim.button
	-- secret-safe, as the reads below: this runs from the button's own
	-- OnEnter / OnMouseDown / SetChecked hooks, and an action button can
	-- answer IsEnabled / GetChecked with a secret in combat; a secret keeps
	-- the rim's last known value instead of being tested (user, 2026-09-23)
	local disabled = rim.lastDisabled or false
	if b.IsEnabled then
		local okE, enabled = pcall(b.IsEnabled, b)
		if okE and not Secret(enabled) then
			disabled = enabled == false
		end
	end
	local checked = rim.lastChecked
	local okC, c
	if rim.isChecked then
		okC, c = pcall(rim.isChecked)
	elseif b.GetChecked then
		okC, c = pcall(b.GetChecked, b)
	else
		okC, c = true, nil
	end
	local unread = okC and Secret(c)
	if okC and not unread then
		checked = c
	end
	rim.lastDisabled = disabled
	-- a flat control (the "flat" kind, 0.19.1): its parts painted by the state
	if rim.flatParts then
		MelloUI.Widgets.FlatState(rim.flatParts, rim.hover, rim.pressed, checked, disabled, rim.flatFocus)
	end
	-- the active look (Kit:SetActive) shows the checked state: a rim's own
	-- checked colour and its glow's selected strength give way to it, a
	-- check box keeps its tick (0.15.0)
	local active = Kit:ActiveFamily(rim)
	local state
	if rim.restState then
		-- a fixed look (the game's tab art is the same on every tab); the
		-- states are shown by the glow the replacement adds over it
		state = rim.restState
	elseif rim.base then
		state = Kit:ResolveState(rim.base, rim.hover, rim.pressed, checked and active ~= "look", disabled)
	end
	rim.lastChecked = checked and true or false   -- for the reads below
	if rim.glow then
		local a = (checked and not active) and 0.7 or rim.hover and 0.35 or 0
		rim.glow:SetAlpha(a)
		rim.glow:SetShown(a > 0)
	end
	if state and state ~= rim.state then
		rim.state = state
		Kit:Apply(rim, rim.base .. "_" .. state)
	end
	-- (0.19.8) a border of the library's standing in for the rim: its states
	-- (the shared glow under the mouse, a darken pressed or disabled)
	if rim.libraryBorder then
		rim.libraryBorder:SetLit(rim.hover, rim.pressed, disabled)
	end
	-- on the button, round the rim, while the rim shows (its skin on). Only a
	-- rim with a checked flag of its own drives it: a hover-only rim (an
	-- icon's on a list row) would switch off the look the row's selected
	-- plate lays, one look a host (review, 2026-09-28). A flag that read
	-- secret leaves it as the flag's own SetChecked showed it (Rim_Checked):
	-- the last plain answer would undo that on every hover and key press
	if active and not unread and (rim.isChecked or b.GetChecked) then
		Kit:SetActive(b, (checked and rim:IsShown()) and true or false, rim, Kit:ActiveShape(rim), rim.icon)
	end
end

-- A flat control's opening (rep:GetOpening, as a bar's): its face is the whole rect
local function FlatOpening()
	return 0, 0, 0, 0
end

-- A flat control's button greyed out (FLAT_OFF) as it is: its Enable /
-- Disable read again (the rims follow SetEnabled alone; a panel button
-- turned off with Disable kept its lit plate -- one handler for all)
local flatButtons = setmetatable({}, { __mode = "k" })   -- [button] = { its flat reps' drivers }
local FlatButton_Enabled = Shared("Enable / Disable on a kit flat control's button", function(button)
	local list = flatButtons[button]
	if list then
		for i = 1, #list do
			Slot_Update(list[i])
		end
	end
end, "hook")

-- A flat arrow over art the game turns (a rule's `rotates`: the bag bar's
-- arrow): SetRotation's angle, a quarter turn counter-clockwise at a time
-- from the art's own way (the rule's `dir`), lays the arrow's lines again
local FLAT_TURNS = { "left", "down", "right", "up" }   -- each a quarter turn counter-clockwise from the one before
local FLAT_TURN_OF = { left = 0, down = 1, right = 2, up = 3 }
local flatTurns = setmetatable({}, { __mode = "k" })   -- [the game's art] = the flat arrow's parts
local FlatArrow_Turn = Shared("SetRotation on a kit flat arrow's art", function(region, angle)
	local parts = flatTurns[region]
	if not parts or type(angle) ~= "number" or Secret(angle) then
		return
	end
	local q = (math.floor(angle / (math.pi / 2) + 0.5) + (parts.turnFrom or 0)) % 4
	MelloUI.Widgets.FlatDir(parts, FLAT_TURNS[q + 1])
end, "hook")

-- A flat edit box's field (the "flat" kind): its edge in `trim` while it has
-- the keyboard, as the Configurator's search box's (one handler for all)
local flatFields = setmetatable({}, { __mode = "k" })   -- [edit box] = its flat rep's driver
local FlatField_Focus = Shared("OnEditFocusGained / Lost on a kit flat field", function(edit)
	local driver = flatFields[edit]
	if driver then
		local ok, focus = pcall(edit.HasFocus, edit)
		driver.flatFocus = (ok and not Secret(focus) and focus) and true or nil
		Slot_Update(driver)
	end
end, "script")

-- A check button's flag set: a secret one (handed over in combat) can only
-- be shown, by the active look (the rim keeps its last look until the flag
-- reads plainly again, the pass after the fight at the latest); a plain one
-- re-reads the rim
local function Rim_Checked(rim, value)
	if Secret(value) then
		if rim:IsShown() and Kit:RimDrivesLook(rim) then
			Kit:SetActive(rim.button, value, rim, Kit:ActiveShape(rim), rim.icon)
		end
		return
	end
	Slot_Update(rim)
end

-- A press latched by OnMouseDown ends on ANY mouse release, and when the
-- cursor leaves the button: a button gets no OnMouseUp when the cursor
-- left it before the release or a drag began, and its rim stayed pressed
-- until the next click (user, 2026-09-22: action buttons stuck pressed).
local pressedLatches = setmetatable({}, { __mode = "k" })   -- [rim or rep] = its Update

-- A rim is read again from its button's live state (the mouse over it, the
-- widget's own pushed state, the checked flag) when something can have
-- changed what the hooks below do not hear, and a clock runs only while a
-- rim is lit (audit, 2026-09-24: a sweep of every rim ten times a second
-- woke from load to logout, with the kit off and nothing dressed too). The
-- rims stuck pressed, hovered and checked (user, 2026-09-22 and 09-23) each
-- have their reader here:
--   its button shown (a window opened)        that rim, at once
--   any mouse release                         the latched and hovered rims, the rim under
--                                             the mouse when the release ended no rim's
--                                             press, and every shown rim on a panel's
--                                             selection test (a click elsewhere moves a
--                                             selection; a right-click ends the merchant's
--                                             repair mode), next frame
--   the mouse entering a rim's button         any other rim still marked hovered (its
--                                             OnLeave was missed), next frame
--   a rim lit (hovered or pressed)            that rim a second on, and on each second
--                                             while it stays lit: a missed OnLeave or
--                                             release, or a hover read off the button's
--                                             place, is right within a second (nothing
--                                             lit: no timer)
--   a click on a check button (mouse, key     that rim, next frame: the client flips a
--   binding, /click)                          CheckButton's flag itself, past SetChecked
--   the bars' state events                    every shown check button's flag, next frame,
--                                             at most every FLAG_GAP s (FLAG_GAP_COMBAT
--                                             in a fight)
--   the end of a fight                        every shown rim, a tenth of them a frame: a
--                                             read in combat can come back secret, and the
--                                             rim keeps its last look until then
-- "Next frame": the game's own handlers of the moment have run by then, and
-- a rim asked for many times in one frame is read once. A rim whose button
-- cannot be seen is left alone; it is read the moment it shows.
local allRims = setmetatable({}, { __mode = "k" })
local rimList = {}           -- the same rims in the order they came, for the pass after a fight

-- One rim re-read from its button; `flagOnly`: the checked flag alone (the
-- hover and press have their scripts). Returns false when the rim has
-- nothing to read or its button cannot be seen (a pass drops it then).
local function ReadRim(rim, flagOnly)
	local b = rim.button
	if rim.restState or not b then
		return false
	end
	-- EVERY read below can come back SECRET on this client (an action
	-- button's mouse-over in combat: "attempt to perform boolean test on
	-- local 'over' (a secret boolean value)", user 2026-09-23). A secret
	-- answer means "cannot know right now": the rim keeps what it had and
	-- is read again on the next occasion; nothing is tested or compared.
	local okV, visible = pcall(b.IsVisible, b)
	if not okV then
		return false
	end
	if Secret(visible) then
		if rim.hover or rim.pressed then
			LitWatch(rim, true)   -- (cannot know: a lit one stays watched)
		end
		return true
	end
	if not visible then
		return false
	end
	local hover, pressed = rim.hover, rim.pressed
	if not flagOnly then
		local okO, over = pcall(b.IsMouseOver, b)
		if okO and not Secret(over) then
			hover = over and true or nil
		end
		-- (no widget state to read on a plain frame: the latch stands)
		if b.GetButtonState then
			local okS, state = pcall(b.GetButtonState, b)
			if okS and not Secret(state) then
				pressed = (state == "PUSHED") and true or nil
			end
		end
	end
	-- the checked flag as well: a check button flips it on the C side
	-- when clicked, past the SetChecked hook (the action bars' rims
	-- stayed "checked" with the button long unchecked, user 2026-09-22)
	local okC, c = false, nil
	if rim.isChecked then
		okC, c = pcall(rim.isChecked)
	elseif b.GetChecked then
		okC, c = pcall(b.GetChecked, b)   -- (none on a plain button: no error string made)
	end
	local checked = rim.lastChecked or false
	if okC and not Secret(c) then
		checked = c and true or false
	end
	if rim.hover ~= hover or rim.pressed ~= pressed or (rim.lastChecked or false) ~= checked then
		rim.hover, rim.pressed = hover, pressed
		pcall(Slot_Update, rim)
	end
	-- still lit (a hover found here, the mouse resting, a secret answer):
	-- read again a second on
	if rim.hover or rim.pressed then
		LitWatch(rim, true)
	end
	return true
end

-- A rim follows its button through one handler per script and method for
-- every rim (user, 2026-09-24: 16 hooks and their closures per bag slot):
-- the rim is kept by its button. A second rim on a button that has one
-- keeps handlers of its own, so every hook still runs where it did. (Here,
-- above the readers: a release reads the rim under the mouse by it.)
local rimOf = setmetatable({}, { __mode = "k" })   -- [button] = its (first) rim

-- The readers, in a block of their own (the file's main chunk nears Lua's
-- 200 locals): ReadNext(rim) reads it on the next frame, RimJoin(rim) puts
-- it in the passes that read it (as it is made and as its button shows),
-- StaleHover(rim), LitWatch(rim) and RimEventsFor(onCheckButton) are below
local ReadNext, RimJoin, StaleHover, RimEventsFor
do
	-- The shown rims whose look hangs on a flag nothing calls a method to
	-- change: a check button's (checkRims) and a panel's selection test
	-- (selectRims, rim.isChecked). A rim joins as its button shows and
	-- leaves at the first pass that finds it hidden, so a pass reads only
	-- what can be seen.
	local checkRims = setmetatable({}, { __mode = "k" })
	local selectRims = setmetatable({}, { __mode = "k" })

	-- The next frame's reads, however many asked for them in this one:
	-- `readRims` the rims asked for by name, `readHover` every rim marked
	-- hovered, `readSelect` every shown rim on a selection test. Two sets in
	-- turn, so a rim asked for while they run waits for the frame after.
	local readRims, readSpare = {}, {}   -- [rim] = true
	local readQueued, readHover, readSelect = false, false, false

	local function ReadQueued()
		readQueued = false
		local list = readRims
		readRims, readSpare = readSpare, list
		if readHover then
			readHover = false
			for rim in pairs(hoverRims) do
				list[rim] = true
			end
		end
		for rim in pairs(list) do
			ReadRim(rim)
		end
		if readSelect then
			-- (their flag alone, as the old release pass: hover and press
			-- have their scripts, and these are neither hovered nor latched)
			readSelect = false
			for rim in pairs(selectRims) do
				if not list[rim] and not ReadRim(rim, true) then
					selectRims[rim] = nil
				end
			end
		end
		wipe(list)
	end

	local function QueueRead()
		if not readQueued then
			readQueued = true
			C_Timer.After(0, ReadQueued)
		end
	end

	function ReadNext(rim)
		readRims[rim] = true
		QueueRead()
	end

	function RimJoin(rim)
		if rim.isChecked then
			selectRims[rim] = true
		elseif rim.onCheckButton then
			checkRims[rim] = true
		end
	end

	-- The mouse entering a rim's button while another rim is still marked
	-- hovered: that one's OnLeave was missed (its button hidden or moved
	-- from under the cursor); every hovered rim is read on the next frame
	function StaleHover(rim)
		for other in pairs(hoverRims) do
			if other.button ~= rim.button then
				readHover = true
				QueueRead()
				return
			end
		end
	end

	-- The lit rims (hovered or pressed), each read again a second after it
	-- lit and on each second while it stays lit: an OnLeave or release that
	-- never came (a button hidden or moved from under the cursor, the game
	-- setting a button's scripts anew, a key's release the client took
	-- itself) and a hover read off the button's place (after a fight, on
	-- show; a bag over the bar) are right within a second, as under the old
	-- sweep (review, 2026-09-24). Nothing lit: no timer. A rim hidden or on a
	-- fixed look leaves the watch (its OnShow reads it). Two sets in turn: a
	-- read that re-watches a rim fills the other one (plain tables: a rim
	-- stays in one a second at most after it goes out).
	local LIT_GAP = 1
	local litRims, litSpare = {}, {}   -- [rim] = true
	local litQueued = false

	local function LitPass()
		litQueued = false
		local list = litRims
		litRims, litSpare = litSpare, list
		for rim in pairs(list) do
			ReadRim(rim)   -- (watches it again while it stays lit)
		end
		wipe(list)
	end

	-- LitWatch(rim, lit): watched while lit; out of the watch at once when a
	-- script or hook put it out (nothing left to read then)
	function LitWatch(rim, lit)
		if not lit then
			if litRims[rim] then
				litRims[rim] = nil
			end
			return
		end
		litRims[rim] = true
		if not litQueued then
			litQueued = true
			C_Timer.After(LIT_GAP, LitPass)
		end
	end

	-- The rim of the frame under the mouse, or nil: a release that ended no
	-- rim's press reads it too, so a click is seen on a button whose scripts
	-- the game set anew since it was dressed (the kit's hooks went with
	-- them). The client makes a new list on every ask, so none over the
	-- world (the camera's drags), where there is no rim.
	local function RimUnderMouse()
		local world = WorldFrame
		if world and world.IsMouseMotionFocus then
			local ok, onWorld = pcall(world.IsMouseMotionFocus, world)
			if ok and not Secret(onWorld) and onWorld then
				return nil
			end
		end
		local ok, f
		if GetMouseFoci then
			local list
			ok, list = pcall(GetMouseFoci)
			if ok and not Secret(list) and type(list) == "table" then
				f = list[1]
			end
		elseif GetMouseFocus then
			ok, f = pcall(GetMouseFocus)
		end
		if not ok or Secret(f) or f == nil then
			return nil
		end
		return rimOf[f]
	end

	-- The press latches end on any release (above), then the rims it can
	-- have changed are read: the ones it ended a press on, the ones under the
	-- cursor (the click's C-side toggle of a check button is in by then) and
	-- the shown selection rims. Any mouse release fires this (the camera's
	-- right button too), so only those: a bare release with none of them
	-- reads nothing.
	local releaseFrame = CreateFrame("Frame")
	releaseFrame:RegisterEvent("GLOBAL_MOUSE_UP")
	Perf.SetScript(releaseFrame, "OnEvent", function()
		local latched = false
		for latch, update in pairs(pressedLatches) do
			pressedLatches[latch] = nil
			if allRims[latch] then
				readRims[latch] = true
				latched = true
			end
			if latch.pressed then
				latch.pressed = nil
				update(latch)
			end
		end
		if not latched and next(allRims) then   -- (no rim dressed: nothing to find)
			local rim = RimUnderMouse()
			if rim then
				readRims[rim] = true
			end
		end
		if next(readRims) or next(hoverRims) or next(selectRims) then
			readHover, readSelect = true, true
			QueueRead()
		end
	end)

	-- The check buttons' flags after the bars' state events (the action,
	-- stance and pet bars check their buttons in their own handlers of
	-- these), one pass for a burst, at most one every FLAG_GAP s. The flag
	-- alone: hover and press have their scripts. ACTIONBAR_UPDATE_USABLE is
	-- not among them: being usable colours the icon and never moves the flag.
	-- In a fight at most one a second (review, 2026-09-24): every cast's
	-- start and stop sends ACTIONBAR_UPDATE_STATE, the action buttons' flags
	-- mostly read secret then, and the pass after the fight reads them all;
	-- a flag that does read is still right within a second, as under the
	-- old sweep.
	local BAR_EVENTS = { "ACTIONBAR_UPDATE_STATE", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "PET_BAR_UPDATE" }
	local FLAG_GAP, FLAG_GAP_COMBAT = 0.2, 1
	local flagQueued, flagAt = false, nil

	local function FlagPass()
		flagQueued = false
		flagAt = GetTime()
		for rim in pairs(checkRims) do
			if not ReadRim(rim, true) then
				checkRims[rim] = nil
			end
		end
	end

	-- After a fight every rim that can be seen, a tenth of them a frame (the
	-- whole lot in one frame was 2.8 ms, /melloperf 2026-09-24), from the
	-- top again if another fight ends before it is through
	local REGEN_SLICES = 10
	local regenAt, regenRunning = 1, false

	local function RegenPass()
		local n = #rimList
		local last = math.min(regenAt + math.ceil(n / REGEN_SLICES) - 1, n)
		for i = regenAt, last do
			ReadRim(rimList[i])
		end
		regenAt = last + 1
		if regenAt <= n then
			C_Timer.After(0, RegenPass)
		else
			regenRunning = false
		end
	end

	local function RimEvents_OnEvent(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			regenAt = 1
			if not regenRunning then
				regenRunning = true
				C_Timer.After(0, RegenPass)
			end
		elseif not flagQueued and next(checkRims) then
			flagQueued = true
			local gap = InCombatLockdown() and FLAG_GAP_COMBAT or FLAG_GAP
			local wait = flagAt and (flagAt + gap - GetTime()) or 0
			C_Timer.After(wait > 0 and wait or 0, FlagPass)
		end
	end

	-- The events' frame, made with the first rim; the bars' events with the
	-- first rim on a check button (the kit off or nothing dressed: none)
	local rimEvents, barEventsOn = nil, false
	function RimEventsFor(onCheckButton)
		if not rimEvents then
			rimEvents = CreateFrame("Frame")
			rimEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
			Perf.SetScript(rimEvents, "OnEvent", RimEvents_OnEvent)
		end
		if onCheckButton and not barEventsOn then
			barEventsOn = true
			for _, event in ipairs(BAR_EVENTS) do
				pcall(rimEvents.RegisterEvent, rimEvents, event)   -- (a client without one of them)
			end
		end
	end
end

local Rim_OnEnter = Shared("OnEnter on a kit rim's button", function(b)
	local tex = rimOf[b]
	tex.hover = true
	Slot_Update(tex)
	StaleHover(tex)
end, "script")
local Rim_OnLeave = Shared("OnLeave on a kit rim's button", function(b)
	local tex = rimOf[b]
	tex.hover = nil
	tex.pressed = nil
	Slot_Update(tex)
end, "script")
local Rim_OnMouseDown = Shared("OnMouseDown on a kit rim's button", function(b)
	local tex = rimOf[b]
	tex.pressed = true
	pressedLatches[tex] = Slot_Update
	Slot_Update(tex)
end, "script")
local Rim_OnMouseUp = Shared("OnMouseUp on a kit rim's button", function(b)
	local tex = rimOf[b]
	tex.pressed = nil
	Slot_Update(tex)
end, "script")
local Rim_OnShow = Shared("OnShow on a kit rim's button", function(b)
	local tex = rimOf[b]
	RimJoin(tex)
	ReadRim(tex)
end, "script")
-- a check button's flag flipped by the click itself: read on the next frame
-- (PostClick's own SetChecked, if any, is in by then)
local Rim_OnClick = Shared("OnClick on a kit rim's check button", function(b)
	ReadNext(rimOf[b])
end, "script")
local Rim_OnSetChecked = Shared("SetChecked on a kit rim's button", function(b, value)
	Rim_Checked(rimOf[b], value)
end)
local Rim_OnSetEnabled = Shared("SetEnabled on a kit rim's button", function(b)
	Slot_Update(rimOf[b])
end)
local Rim_OnSetButtonState = Shared("SetButtonState on a kit rim's button", function(b, state)
	local tex = rimOf[b]
	tex.pressed = (state == "PUSHED") or nil
	Slot_Update(tex)
end)

-- The mouse a rim's hooks leave on a frame that is no button (0.14.0: a
-- mouse script set or hooked on a frame turns that input on, so a plain
-- holder over the colour picker's wheel and a mail item's icon took their
-- clicks; those two callers put it back themselves). What FollowButton
-- found OFF on such a frame is turned off again after its hooks: clicks and
-- motion each (the client's own IsMouseClickEnabled / IsMouseMotionEnabled,
-- or the one IsMouseEnabled where those are missing). A Button or a
-- CheckButton keeps what the hooks give it: its rim's hover and press are
-- the point. A protected frame in combat waits for the fight's end. Each
-- frame so kept is listed (Kit.mouseKept, weak: [frame] = what was put
-- back) for /mellokit mouse: the in-game audit of who relied on it.
Kit.mouseKept = setmetatable({}, { __mode = "k" })
local FollowButton
do
	local function Flag(frame, method)
		local fn = frame[method]
		if type(fn) ~= "function" then
			return nil
		end
		local ok, on = pcall(fn, frame)
		if not ok or Secret(on) then
			return nil
		end
		return on and true or false
	end

	-- click, motion (nil: unknown), and whether the frame answers them apart
	local function MouseWas(frame, objectType)
		if objectType == "Button" or objectType == "CheckButton" or objectType == "ItemButton" then
			return nil, nil, nil
		end
		if type(frame.IsObjectType) == "function" then
			local ok, isButton = pcall(frame.IsObjectType, frame, "Button")
			if ok and not Secret(isButton) and isButton then
				return nil, nil, nil
			end
		end
		local click, motion = Flag(frame, "IsMouseClickEnabled"), Flag(frame, "IsMouseMotionEnabled")
		if click ~= nil and motion ~= nil then
			return click, motion, true
		end
		local any = Flag(frame, "IsMouseEnabled")
		return any, any, false
	end

	local function PutBack(frame, click, motion, apart)
		local kept = nil
		if apart then
			if click == false and Flag(frame, "IsMouseClickEnabled") then
				pcall(frame.SetMouseClickEnabled, frame, false)
				kept = "clicks"
			end
			if motion == false and Flag(frame, "IsMouseMotionEnabled") then
				pcall(frame.SetMouseMotionEnabled, frame, false)
				kept = kept and "clicks and motion" or "motion"
			end
		elseif click == false and Flag(frame, "IsMouseEnabled") then
			pcall(frame.EnableMouse, frame, false)
			kept = "mouse"
		end
		if kept then
			Kit.mouseKept[frame] = kept
		end
	end

	local function MouseBack(frame, click, motion, apart)
		if click ~= false and motion ~= false then
			return
		end
		if InCombatLockdown() and Flag(frame, "IsProtected") then
			Kit:WhenOutOfCombat(function()
				PutBack(frame, click, motion, apart)
			end)
			return
		end
		PutBack(frame, click, motion, apart)
	end

	function FollowButton(tex, button)
		if not allRims[tex] then
			allRims[tex] = true
			rimList[#rimList + 1] = tex
		end
		tex.Update = Slot_Update
		-- a CheckButton flips its own flag when clicked (read after each click)
		local okT, objectType = pcall(button.GetObjectType, button)
		local onCheck = okT and not Secret(objectType) and objectType == "CheckButton"
		tex.onCheckButton = onCheck or nil
		RimEventsFor(onCheck)
		RimJoin(tex)
		-- (the mouse as it was, on a frame that is no button: put back after the hooks)
		local click, motion, apart = MouseWas(button, (okT and not Secret(objectType)) and objectType or nil)
		if rimOf[button] == nil then
			rimOf[button] = tex
			Perf.HookScript(button, "OnEnter", Rim_OnEnter)
			Perf.HookScript(button, "OnLeave", Rim_OnLeave)
			Perf.HookScript(button, "OnMouseDown", Rim_OnMouseDown)
			Perf.HookScript(button, "OnMouseUp", Rim_OnMouseUp)
			-- shown again (its window opened): read at once, the passes leave it
			-- alone while it cannot be seen
			Perf.HookScript(button, "OnShow", Rim_OnShow)
			if onCheck then
				Perf.HookScript(button, "OnClick", Rim_OnClick)
			end
			if type(button.SetChecked) == "function" then
				hooksecurefunc(button, "SetChecked", Rim_OnSetChecked)
			end
			if type(button.SetEnabled) == "function" then
				hooksecurefunc(button, "SetEnabled", Rim_OnSetEnabled)
			end
			-- a keybind presses an action button through SetButtonState, not the
			-- mouse: the pressed look follows that too
			if type(button.SetButtonState) == "function" then
				hooksecurefunc(button, "SetButtonState", Rim_OnSetButtonState)
			end
			MouseBack(button, click, motion, apart)
			return
		end
		Perf.HookScript(button, "OnEnter", function() tex.hover = true; Slot_Update(tex); StaleHover(tex) end)
		Perf.HookScript(button, "OnLeave", function() tex.hover = nil; tex.pressed = nil; Slot_Update(tex) end)
		Perf.HookScript(button, "OnMouseDown", function() tex.pressed = true; pressedLatches[tex] = Slot_Update; Slot_Update(tex) end)
		Perf.HookScript(button, "OnMouseUp", function() tex.pressed = nil; Slot_Update(tex) end)
		Perf.HookScript(button, "OnShow", function() RimJoin(tex); ReadRim(tex) end)
		if onCheck then
			Perf.HookScript(button, "OnClick", function() ReadNext(tex) end)
		end
		if type(button.SetChecked) == "function" then
			hooksecurefunc(button, "SetChecked", function(_, value) Rim_Checked(tex, value) end)
		end
		if type(button.SetEnabled) == "function" then
			hooksecurefunc(button, "SetEnabled", function() Slot_Update(tex) end)
		end
		if type(button.SetButtonState) == "function" then
			hooksecurefunc(button, "SetButtonState", function(b, state)
				tex.pressed = (state == "PUSHED") or nil
				Slot_Update(tex)
			end)
		end
		MouseBack(button, click, motion, apart)
	end
end

function Kit:Slot(button, opts)
	opts = opts or {}
	local scale = opts.scale or self.scale
	local base = "buttons/" .. (opts.kind or "slot")
	local owner = button
	if opts.under then
		-- the rim under the button's own art (icon, quality border), as the
		-- game's slot picture is: a frame one level below the button
		owner = CreateFrame("Frame", nil, button)
		owner:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
		owner:EnableMouse(false)
		owner:SetAllPoints(button)
	end
	local rim = owner:CreateTexture(nil, opts.layer or (opts.under and "ARTWORK" or "OVERLAY"), nil, opts.sublevel or 3)
	rim.owner = owner
	rim.kitScale = scale
	-- a round rim wears every window's Round Border (Kit.borderKinds)
	if base == "buttons/roundslot" and self.roundRims then
		self.roundRims[rim] = true
		local look = self:BorderValue("round")
		if look and PIECES["buttons/" .. look .. "_normal"] then
			base = "buttons/" .. look
		end
	end
	rim.button, rim.base = button, base
	rim.isChecked = opts.checked           -- function(): true when the piece should show its checked state
	rim:SetAllPoints(button)
	rim.state = nil

	rim.icon = opts.icon
	if opts.icon then
		self:SlotPlaceIcon(rim)
	end

	FollowButton(rim, button)
	Slot_Update(rim)
	-- (0.19.8) Round Border in a ring style of the border library's: the ring on it
	if self.roundRims and self.roundRims[rim] and self.RoundLibraryRing then
		self:RoundLibraryRing(rim, self:BorderValue("round"))
	end
	return rim
end

-- The frame a region covers whole (SetAllPoints: its two corners on the
-- frame's, no offsets), or nil
local function FilledFrame(region)
	if region:GetNumPoints() ~= 2 then
		return nil
	end
	local p1, rel1, rp1, x1, y1 = region:GetPoint(1)
	local p2, rel2, rp2, x2, y2 = region:GetPoint(2)
	if not (rel1 and rel1 == rel2 and rel1.GetSize and x1 == 0 and y1 == 0 and x2 == 0 and y2 == 0) then
		return nil
	end
	if (p1 == "TOPLEFT" and rp1 == "TOPLEFT" and p2 == "BOTTOMRIGHT" and rp2 == "BOTTOMRIGHT")
		or (p1 == "BOTTOMRIGHT" and rp1 == "BOTTOMRIGHT" and p2 == "TOPLEFT" and rp2 == "TOPLEFT") then
		return rel1
	end
	return nil
end

local function DrawnSizeOf(region)
	-- filling a frame: the frame's size (the same once laid out, and known
	-- before)
	local frame = FilledFrame(region)
	if frame then
		local w, h = frame:GetSize()
		-- in the region's own units, where the frame is scaled otherwise
		local parent = region:GetParent()
		if parent and parent ~= frame and frame.GetEffectiveScale and parent.GetEffectiveScale then
			local fs, ps = frame:GetEffectiveScale(), parent:GetEffectiveScale()
			if ps > 0 and fs ~= ps then
				w, h = w * fs / ps, h * fs / ps
			end
		end
		return w, h
	end
	-- laid out: its own size
	if region:GetRect() then
		return region:GetSize()
	end
	-- one point or none: a size of its own (SetSize), else nothing known
	if region:GetNumPoints() <= 1 then
		return region:GetSize()
	end
	return 0, 0
end

-- A kit texture's size as it will be drawn. One not laid out yet (its frame
-- not placed: a bag's slots before their first layout) answers GetSize with
-- its FILE's size, and since the small pieces were packed into atlas sheets
-- that is a whole sheet: a bag slot's rim read 512 x 256, its icon was fitted
-- into that and crushed to nothing, the empty slot's stone with it (user,
-- 2026-09-24). Such a texture is measured on the frame it fills (a frame's
-- own size is known before it is placed); 0, 0 when nothing is known yet
-- (callers fit nothing then) or the size reads secret.
function Kit:DrawnSize(region)
	local ok, w, h = pcall(DrawnSizeOf, region)
	if not ok or Secret(w) or Secret(h) then
		return 0, 0
	end
	return w or 0, h or 0
end

-- Rims whose size was not known yet when they were fitted (Kit:DrawnSize
-- 0, 0): fitted again a frame later, a few times at most, all on one timer.
-- Their icon and whatever follows the rim (rim.onBaseChanged: the empty
-- slot's stone); a rim switched off meanwhile is left as it is
local refitQueue, refitting = {}, {}
local refitQueued = false

local function RefitQueued()
	refitQueued = false
	refitQueue, refitting = refitting, refitQueue
	for rim, tries in pairs(refitting) do
		if rim:IsShown() then
			rim.kitRefitTries = tries
			if rim.icon then
				Kit:SlotPlaceIcon(rim)
			end
			if rim.onBaseChanged then
				rim.onBaseChanged()
			end
		end
	end
	wipe(refitting)
end

function Kit:RefitLater(rim)
	local tries = (rim.kitRefitTries or 0) + 1
	if tries > 4 or refitQueue[rim] then
		return
	end
	refitQueue[rim] = tries
	if not refitQueued then
		refitQueued = true
		C_Timer.After(0, RefitQueued)
	end
end

-- Kit:NextFrame(key, fn): fn(key) once on the next frame, however often it
-- was asked for before then (audit, 2026-09-24: panels kept a pending flag
-- each and made a new closure for C_Timer.After(0) on every ask). One timer
-- a frame for every key. A key asked for again before it ran runs once, in
-- the place it was first asked for, with the fn given last. `fn` is made
-- once by the caller -- a file's own function, handed the key (the skin or
-- frame it works on) -- so an ask makes no closure. An error in one is
-- reported and the rest still run. A key asked for while they run (from
-- inside one of them) waits for the frame after once it has run; one still
-- waiting further on in the same run runs there only, with the fn given last
-- (review, 2026-09-24: it ran twice, then and on the next frame).
do
	local nextKeys, nextFns = {}, {}   -- the keys in the order asked, [key] = its fn
	local runKeys, runFns = {}, {}     -- the same two, emptied as they run
	local nextQueued = false

	local function RunNextFrame()
		nextQueued = false
		local keys, fns = nextKeys, nextFns
		nextKeys, nextFns, runKeys, runFns = runKeys, runFns, keys, fns
		for i = 1, #keys do
			local key = keys[i]
			local fn = fns[key]
			keys[i], fns[key] = nil, nil
			local ok, err = pcall(fn, key)
			if not ok then
				geterrorhandler()(err)
			end
		end
	end

	function Kit:NextFrame(key, fn)
		if key == nil or type(fn) ~= "function" then
			return
		end
		if runFns[key] ~= nil then
			runFns[key] = fn   -- (still waiting in the run under way)
			return
		end
		if nextFns[key] == nil then
			nextKeys[#nextKeys + 1] = key
		end
		nextFns[key] = fn
		if not nextQueued then
			nextQueued = true
			C_Timer.After(0, RunNextFrame)
		end
	end
end

-- Anchor the rim's icon into the rim's opening (insets as fractions of the
-- rim, so any button size works). Callers restore the icon's own points to undo.
function Kit:SlotPlaceIcon(rim)
	if rim.placingIcon then
		return
	end
	local name = rim.base .. "_" .. (self:FirstStateOf(rim.base) or "normal")
	local p = PIECES[name]
	local icon = rim.icon
	-- the icon fills the rim's opening: measured on the RIM's own rect (the
	-- rim may be a square on a rectangular button, or larger than the button)
	local rw, rh = self:DrawnSize(rim)
	local l, r, t, b = self:Insets(name, 1)
	if p and l and icon and rw > 0 and rh > 0 then
		local il, ir, it, ib = rw * l / p.w, rw * r / p.w, rh * t / p.h, rh * b / p.h
		-- rim.iconGrow: the icon that share larger than the opening, reaching
		-- under the rim's inner bevel (the action bars' thin rims: the icons
		-- looked smaller than their frames, user 2026-09-23)
		local grow = rim.iconGrow
		if grow and grow ~= 0 then
			local gw, gh = (rw - il - ir) * grow / 2, (rh - it - ib) * grow / 2
			il, ir, it, ib = il - gw, ir - gw, it - gh, ib - gh
		end
		-- rim.iconBleed: UI px the icon reaches under the rim's inner edge on
		-- every side (the side tabs: "about 2px bigger than the inner border",
		-- user 2026-09-23)
		local bleed = rim.iconBleed
		if bleed and bleed ~= 0 then
			il, ir, it, ib = il - bleed, ir - bleed, it - bleed, ib - bleed
		end
		rim.placingIcon = true
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", rim, "TOPLEFT", il, -it)
		icon:SetPoint("BOTTOMRIGHT", rim, "BOTTOMRIGHT", -ir, ib)
		rim.placingIcon = nil
		rim.kitRefitTries = nil
	elseif p and l and icon then
		-- its size not known yet: the icon keeps the game's anchors meanwhile
		self:RefitLater(rim)
	end
end

-- Swap a slot rim's art family live (a border choice changed: the spell
-- book's Spell Border): the same states from another base, the
-- icon fitted into the new opening, and whoever follows the rim told
-- (rim.onBaseChanged: the empty slot's stone).
function Kit:SetSlotBase(rim, base)
	if not rim or rim.base == base or not PIECES[base .. "_normal"] then
		return
	end
	rim.base, rim.state = base, nil
	Slot_Update(rim)
	-- the icon into the new opening while the rim is on; a rim switched off
	-- leaves the game's icon where the game put it (its skin's enable fits
	-- it again) -- a hidden round rim took a round-icon button's icon away
	-- from the square rim shown (2026-09-24 sweep)
	if rim.icon and rim:IsShown() then
		self:SlotPlaceIcon(rim)
	end
	if rim.onBaseChanged then
		rim.onBaseChanged()
	end
end

-- Same idea for the small painted buttons (cog, arrows, checkbox, plus, minus,
-- orb, close): one texture that follows the button's state.
function Kit:StateTexture(button, base, opts)
	opts = opts or {}
	local tex = button:CreateTexture(nil, opts.layer or "ARTWORK", nil, opts.sublevel or 0)
	tex.kitScale = opts.scale or self.scale
	tex.button, tex.base = button, base
	tex.isChecked = opts.checked
	tex:SetAllPoints(button)
	FollowButton(tex, button)
	Slot_Update(tex)
	return tex
end

--------------------------------------------------------------------------------
-- Replacement library: which kit piece stands in for which game art.
--
-- Keyed by the game's atlas name (or a texture file's base name, or a name
-- of ours for art that has no atlas, like "TitleBar"). A panel module never
-- picks a piece itself: it hands Kit:Replace the game region and the library
-- looks the piece up here, builds it on the region's own rectangle as a child
-- of the region's frame, and fades the original. docs/KIT-MAPPING.md is the
-- human-readable copy of this table; keep both in step.
--
-- kind:
--   frame   an inner nine-slice (edges + stone body) on the rect; `scale` is
--           a multiplier on Kit.scale, `prefix` another edge family
--           ("window/single": one rail instead of the window's double rail),
--           `body = false` for edges only, `open`
--           the sides without edge (an attached tab: "l"), `checkedTint`
--           the colour of the iron when opts.checked() is true, `corners = "gem"`
--           the painted gem corners over the edges (opts.skip leaves some out)
--           `outset` grows the frame outward from the rect by that many piece px
--           `hover` / `pressed` / `disabled`: tint factors for the button's states
--   strip   ... `capOverhang`: the caps may reach that fraction of their width past the rect
--   edge    one edge tile on the rect (`piece`), for divider lines
--   strip   a cap/mid/cap strip (`base`, `state`) fitted to the rect's height;
--           `owner` draws it as regions of the replaced texture's frame (its
--           layer one sublevel up, or `layer` / `sublevel`) instead of a child frame;
--           `natural` keeps the kit size instead (a thin line inside a large
--           glow atlas) and `widthFrac` spans that fraction of the rect, centred;
--           `heightScale` multiplies the fitted height (the width stays the rect's)
--   slot    the slot rim on a button (`slot` = "slot" | "roundslot"); `under`
--           puts it below the button's icon and quality border, as the game's
--           slot picture is (equipment); without it the rim is over the icon (tabs);
--           `rest` fixes the rim's look (e.g. "checked" = the gold rim on every
--           tab, as the game's tab art is) and `glow` adds the same rim
--           additively for the hovered (0.35) button, standing in for the
--           game's TabGlow / Highlight; the selected one wears the active
--           look (Kit:SetActive) for the game's SelectedTexture
--   state   a state texture on a button (`base`), e.g. the close button;
--           `natural` keeps the kit size centred on the rect, `layer` its
--           draw layer (OVERLAY unless the game's icon must stay on top)
--   flat    (0.19.1) a control in the Configurator's flat look (`flat` =
--           button / check / dropdown / edit / close / arrow (`dir`) / plus /
--           minus / cog / tab / tabActive / track / thumb / slider / knob; the
--           check, close, arrows, + / -, cog and an icon button's plate the
--           kit's NewUI2 pieces, 0.19.9:
--           W.FlatOver's parts on a holder on the rect, painted by its state
--           as the rims are; `rect = "normal"` the button's normal texture's
--           rect); opts.left an edit box's fill reaching left over its glass,
--           opts.body = false the edge alone, opts.fitHeight a centred height
--   active  the active look alone (Kit:SetActive) on a check button the kit
--           does not dress, while it is checked; `active = true` on a rule
--           of another kind puts the active look round its piece whenever
--           the piece shows (the open tab's card)
--   vstrip  an upright cap_t / mid / cap_b strip on the rect (a scroll thumb),
--           `widthScale` x the rect's width, its state from the button
--   bar     a hollow bar bracket (`bar` = "frame" | "castbar") fitted to the
--           rect's height with the trough in its opening, both regions of the
--           rect's frame (bracket in BORDER over the game's fill, under its
--           text); `thicken` makes it that many px taller than the rect,
--           `into` how far the fill goes into the rails (1 = all the way),
--           `artScale` (rule or opts) the border art at that fraction of its
--           fitted scale, in every look (the opening shrinks with it);
--           rep:GetOpening() gives the fill area's insets from the rect
--   texture one piece (`piece`) sized to the rect (`square`: to its shorter side,
--           `natural`: the kit size, centred on the rect or opts.center; `body`
--           with `square`: the piece sized so its round body is that piece's
--           on the rect -- a ring with wings reaches past it)
--   tile    a repeatable tile (`piece`) filling the rect at its native scale
--   fade    nothing: the region is only faded (decoration with no kit equivalent)
--   picture a painted picture (`piece`, its greyscale twin `grey`) cropped to
--           the rect's aspect (`crop` = "bottom" | "top" | "middle"), or with
--           `fit = "right"` shown whole at the rect's height against its right
--           edge, its own left columns mirrored across the rest (a banner whose
--           subject sits at the right on plain stone); the single-rail edges
--           over it when `frame`
--------------------------------------------------------------------------------

-- RULES (user, 2026-09-21): borders are SINGLE-LINE and ONE WEIGHT unless
-- stated otherwise for an element. Every `frame` / `edge` rule uses the
-- single-rail family (window/single_*) at Kit.frameScale unless it names its
-- own prefix or scale; the window's double rail (window/frame_*) is only used
-- where the user asks for it. The family's edge is 11 px at 2x; 1.6 is the
-- user's pick (B1, ~7 px on screen at the kit scale).
Kit.framePrefix = "window/single"
Kit.frameScale = 1.6

Kit.Replacements = {
	-- window frames and their parts
	-- the OUTER border of every window (user, 2026-09-21): the window sheet as
	-- painted, double rail at 1.0 with the painted gem corners on top; the
	-- one place the single-rail rule does not apply
	-- (user: the wider border expands OUTSIDE the window, not into it: outset
	-- = the rail band's 48 px less its 6 px inner bevel, which stays on the edge)
	["NineSlicePanelTemplate"]                = { kind = "frame", level = 0, prefix = "window/frame", scale = 1.0, corners = "gem", outset = 42 },
	["TitleBar"]                              = { kind = "strip", base = "tabs/top", state = "open", heightScale = 1.5, onRail = true },   -- rune caps, red plate (the user's pick H), red matched to buttons/redbtn (F); 1.5 x the bar's height, same width; `onRail`: riding the OUTER rail across the whole window width, its caps' red gems on the rail's top corners in place of the frame's own gems (Kit:TitleOnRail), the title text with it (user, 2026-09-23: "combining B1 and having H3 as a header", layout C; was standing on the rail with the title caps, H1)
	["_UI-Frame-TopTileStreaks"]              = { kind = "fade" },   -- the streak band under the title: a stone band there read as a second, different backdrop (user, 2026-09-21); the page shows through
	["UI-Frame-PortraitMetal-CornerTopLeft"]  = { kind = "texture", piece = "rings/r5", square = true, body = "window/portrait_ring", level = 1 },   -- (0.19.9, the user's pick 4c 2026-10-08) the NewUI2 winged border (Tools/make_newui2_glyphs.py), its ring body the gem ring's on the rect, its wings past it; the minimap, the crest and the unit frames keep window/portrait_ring
	-- the configurator's crest and the short plate under it (approved sketch,
	-- 2026-09-24; Kit:OwnWindow, Modules/KitWindow.lua): the portrait ring
	-- centred on the top rail's middle line with the emblem on its disc, and
	-- the title plate without `onRail`. Keys of their own, so neither is taken
	-- for a window's corner ring or title plate (Kit.shells keeps them as
	-- crest / plate, for their shade only: never a drag handle, nothing cut
	-- by TitleBehindRing)
	["MelloUI-Crest"]                         = { kind = "texture", piece = "window/portrait_ring", square = true, level = 1 },
	["MelloUI-TitlePlate"]                    = { kind = "strip", base = "tabs/top", state = "open", heightScale = 1.5 },
	["RedButton-Exit"]                        = { kind = "flat", flat = "close", rect = "normal" },   -- (0.19.1) flat: the close button (was the red cross)
	-- inset frames and backdrops
	["common-insideframe"]                    = { kind = "frame", dim = 0.8 },   -- an inset: single rail + stone, the stone under the palette's inner panel (no eye strain, WINDOW-RULES 2e)
	["common-insideframe-2x"]                 = { kind = "frame" },
	-- ONE stone per surface (user, 2026-09-23, the skills tab: "background 1
	-- and 2 are basically the same, they are loading 2 times for no reason"):
	-- a pane or backdrop picture that would look like the window's own stone
	-- is faded, not replaced with a second stone on top (tiles/stone over
	-- window/frame_body, each tiled from its own corner, showed its edge).
	-- The window's body runs on under it as one surface. A second surface is
	-- drawn only where it is meant to read as different (the darker list-box
	-- stone of an inset, a page picture, the parchment).
	-- The two pane backdrops: faded; the seam between the panes is drawn by
	-- common-framedivider alone, as in the default. The right pane's holder
	-- still carries its parchment sheet.
	["UI-Character-Info-General-BG"]          = { kind = "fade" },
	["UI-Character-Info-Stat-BG"]             = { kind = "fade" },
	["UI-Character-Info-Stat-StoneBG"]        = { kind = "frame" },
	["UI-Character-Info-Stat-StoneBG2"]       = { kind = "frame" },
	["common-framedivider"]                   = { kind = "edge", piece = "window/single_l" },
	-- lines, plates and list rows
	["UI-Character-Info-ScrollLine"]          = { kind = "strip", base = "window/divider" },
	["UI-Character-Info-ScrollLine-Long"]     = { kind = "strip", base = "window/divider" },
	-- a thin line inside a big soft-glow atlas: the atlas box says nothing about
	-- the line, so the divider keeps its natural kit size and spans half the box
	["UI-Character-Info-Honor-LevelBG"]       = { kind = "strip", base = "window/divider", natural = true, widthFrac = 0.5 },
	["UI-Character-Info-Title"]               = { kind = "strip", base = "lists/header" },
	["UI-Character-Info-ItemLevel-Bounce"]    = { kind = "strip", base = "lists/header" },
	["UI-Character-Info-Line-Bounce"]         = { kind = "strip", base = "lists/plate", state = "plain" },   -- a plain line in the game: the gemless plate
	["UI-Character-Info-Line-Bounce2"]        = { kind = "strip", base = "lists/plate", state = "plain" },
	["common-button-list-collapseExpand"]     = { kind = "strip", base = "lists/catplate", state = "closed" },   -- the plain category plate: one texture, no chevron (the game's +/- glyph stays)
	["charactercreate-customize-dropdown-linemouseover-middle"] = { kind = "strip", base = "lists/plate", state = "plain" },   -- the gemless plate: the gemmed row's gems overshoot a list row
	-- backdrop pictures with no frame of their own
	["ModelSceneBackground"]                  = { kind = "fade" },   -- the race landscape behind the character: faded, the window's stone runs on behind the model (one stone per surface)
	-- the ONE addition the default window does not have (the user's decision, catalogue pick B1):
	-- a single-rail iron frame around the character viewport, over its backdrop
	["ViewportFrame"]                         = { kind = "frame", body = false, level = 1, open = "r" },   -- open where it meets the pane divider
	-- slots and tabs
	-- gemSpan: the gems' centre-to-centre span as a fraction of the piece; with
	-- opts.pitch (the distance between neighbouring slots) the rim is sized so
	-- neighbours share a gem, as the game's slot pictures share their diamonds
	["UI-Character-Info-GearSlot"]            = { kind = "fade" },   -- a gear slot's frame art (its BorderFrame's picture): faded, the slot wears the action bars' thin rim on the button itself (CharacterPanel, Item Border; user 2026-09-23: "onto the Character Pane next"). Was the gemmed slot sized so neighbours shared a gem
	["common-sidetab"]                        = { kind = "slot", slot = "slot", rest = "checked", glow = true, sideTab = true, iconBleed = 2, keepIcon = true },   -- gold rim on every tab (the user's pick, I), additive glow when selected; `sideTab`: every window's at the Character window's size, in the one Side Tab Border (Kit:RegisterSideTab)
	-- small controls
	["checkbox-minimal"]                      = { kind = "flat", flat = "check" },   -- (0.19.1) flat: a check box (was the kit's)
	-- scroll bars (user, 2026-09-21: T2 / H1 / S1 is THE scroll bar, the only
	-- look for every MinimalScrollBar): the dark trough as the track, the gem
	-- slab thumb stretching with the content, the kit arrow buttons as steppers
	["minimal-scrollbar-track-middle"]        = { kind = "flat", flat = "track", level = -1 },   -- (0.19.1) flat: a scroll bar's track (was T2's trough)
	["minimal-scrollbar-small-thumb-middle"]  = { kind = "flat", flat = "thumb", level = 0 },   -- (0.19.1) flat: its thumb (was H1's slab)
	["minimal-scrollbar-arrow-top"]           = { kind = "flat", flat = "arrow", dir = "up" },   -- (0.19.1) flat: a scroll bar's up stepper (was S1's arrow)
	["minimal-scrollbar-arrow-bottom"]        = { kind = "flat", flat = "arrow", dir = "down" },   -- (0.19.1) flat: ... its down stepper
	-- progress bars (user, 2026-09-21: P1): the hollow bar bracket with the
	-- trough in its opening, under the game's tinted fill and its text
	["common-stat-bar-BG"]                    = { kind = "bar", bar = "frame", heightScale = 0.85 },   -- the character pane's skill / reputation bars: P1 at 0.85 of the bar's height (user, 2026-09-21: the borders 15 % smaller), the fill fitted into the smaller opening by the panel
	-- list glyphs (user, 2026-09-21: consistency — every check box, expand /
	-- collapse control and toggle in a window is the kit's): the +/- plates
	-- on the glyph's rect, the plus for a collapsed header, the minus for an open one
	["common-button-list-plus"]               = { kind = "flat", flat = "plus" },   -- (0.19.1) flat: a list's expand (was the kit's +)
	["common-button-list-minus"]              = { kind = "flat", flat = "minus" },   -- (0.19.1) flat: ... collapse (was the kit's -)
	["campaign_headericon_closed"]            = { kind = "flat", flat = "plus", rect = "normal" },   -- (0.19.1) flat: a sub-header's toggle, closed (was the kit's +)
	["campaign_headericon_open"]              = { kind = "flat", flat = "minus", rect = "normal" },   -- (0.19.1) flat: ... open
	-- the character window's equipment manager
	["UI-Character-Info-OutfitCard"]          = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 0 },   -- an outfit card: the gemless plate ...
	["UI-Character-Info-OutfitCard-Hover"]    = { kind = "strip", base = "lists/plate", state = "hover", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- ... its hover (shown / hidden by the game)
	["UI-Character-Info-OutfitCard-Selected"] = { kind = "strip", base = "lists/plate", state = "selected", owner = true, layer = "BACKGROUND", sublevel = 2 },   -- ... its selected bar (likewise)
	["common-button-tertiary-normal"]         = { kind = "strip", base = "buttons/redbtn", state = "normal", owner = true, heightScale = 0.8 },   -- (0.19.1) the red plate again, gemless (B1; user, 2026-10-04: "no more diamonds on the sides"; was flat for a day): New Set, the game's + icon and text on top
	-- the spell book (user's picks, 2026-09-21: P1 C1 H3 K1 T1); the talents
	-- page stays the game's until the user's per-class art arrives
	-- The PAGES (user, 2026-09-23: backgrounds keep one resolution, never
	-- stretched): the painted page pictures are gone from them; the stone
	-- pages repeat tiles/concrete (the page stone's own middle), the paper
	-- pages tiles/vellum (the parchment page's middle), from the rect's
	-- middle or top (`crop`), their painted edges as before.
	["spellbook-Page-Right-C60"]              = { kind = "picture", piece = "tiles/vellum", crop = "middle", level = -1, parchment = "br" },   -- (0.20.1: the parchment nine, its curl at the bottom right)   -- the book page: the user's parchment page painting (parchmentnew, 2026-09-21; painted at the page's 1.15 aspect), one UNDER the SpellBookFrame (level 100: well above the window's skin, below every control on the page)
	["spellbook-Page-Left-C60"]               = { kind = "picture", piece = "tiles/vellum", crop = "middle", level = -1, parchment = "tl" },   -- (0.20.1: the parchment nine, its curl at the top left: a spread's two outer corners)   -- the left page's strokes flipped, so the two pages are not twins
	["spellbook-Tab-Frame-C60"]               = { kind = "slot", slot = "slot" },   -- a category tab (C1): the slot rim over the icon, gold (checked) while the tab is selected
	["spellbook-list-backplate"]              = { kind = "fade" },   -- the list header's backplate (H3: the text on the page)
	["spellbook-divider"]                     = { kind = "strip", base = "window/divider" },   -- the line under the header (H3)
	["spellbook-item-backplate"]              = { kind = "fade" },   -- a spell card: no plate (user re-picked K4 from K1 on sight), the rim and text on the page
	["spellbook-item-iconframe"]              = { kind = "slot", slot = "slot" },   -- an active spell's icon frame: the square rim
	["spellbook-item-iconframe-inactive"]     = { kind = "slot", slot = "slot" },
	["spellbook-item-iconframe-passive"]      = { kind = "slot", slot = "roundslot" },   -- a passive's: the round rim (the icon is round)
	["spellbook-item-iconframe-passive-inactive"] = { kind = "slot", slot = "roundslot" },
	["talents-node-circle-gray"]              = { kind = "slot", slot = "roundslot" },   -- what this client puts on a passive spell's icon
	["uiframe-tab-left"]                      = { kind = "flat", flat = "tab", level = -1 },   -- (0.19.1) flat: a window's tab at rest (was TB6)
	["uiframe-activetab-left"]                = { kind = "flat", flat = "tabActive", level = -1, active = true },   -- (0.19.1) flat: the open tab (was TB6 lit gold); `active`: the active look round it, as the Configurator's open tab
	["common-dropdown-a-button"]              = { kind = "flat", flat = "arrow", dir = "down" },   -- (0.19.1) flat: the small round dropdown arrow (was K2's cog under it)
	["common-dropdown-a-button-shadowless"]   = { kind = "flat", flat = "arrow", dir = "down" },   -- (0.19.1) flat: ... without its shadow (was the kit's arrow)
	["RedButton-Expand"]                      = { kind = "flat", flat = "arrow", dir = "up", rect = "normal" },   -- (0.19.1) flat: the window's maximize (was the kit's arrow)
	["RedButton-Condense"]                    = { kind = "flat", flat = "arrow", dir = "down", rect = "normal" },   -- (0.19.1) flat: ... minimize
	-- the professions window (user's picks, 2026-09-21: A, F crop 1, K1)
	-- the book page's backdrop: the user's own page painting (the kit's soft
	-- stones, tiles/crackle and a plain grey were all tried before it)
	["Profession-Background-Overview"]        = { kind = "picture", piece = "tiles/concrete", crop = "middle", level = 1, edge = "brush" },   -- one ABOVE the window (the window's own skin is at its level: a tie there draws in an order the client may change between loads)   -- the user's grey stone page with gothic pilasters (2026-09-21), painted at the page's own aspect
	["Profession-overview-Card"]              = { kind = "frame" },   -- a primary card with no profession in it (A): single rail, stone body
	-- a primary card with a profession: the game re-atlases its Background to
	-- -<Profession> in FormatProfession; each gets its painted banner (the
	-- still-life at the right on stone, user's sheets 2026-09-21), whole at the
	-- card's height against its right edge (nothing of the still-life cut
	-- off), the stone mirrored across the rest, the single rail over it
	["Profession-overview-Card-Alchemy"]       = { kind = "picture", piece = "cards/alchemy", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Alchemy"]     = { kind = "picture", piece = "backdrops/profession_alchemy", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Blacksmithing"] = { kind = "picture", piece = "cards/blacksmithing", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Blacksmithing"]= { kind = "picture", piece = "backdrops/profession_blacksmithing", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Enchanting"]    = { kind = "picture", piece = "cards/enchanting", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Enchanting"]  = { kind = "picture", piece = "backdrops/profession_enchanting", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Engineering"]   = { kind = "picture", piece = "cards/engineering", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Engineering"] = { kind = "picture", piece = "backdrops/profession_engineering", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Herbalism"]     = { kind = "picture", piece = "cards/herbalism", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Herbalism"]   = { kind = "picture", piece = "backdrops/profession_herbalism", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Leatherworking"]= { kind = "picture", piece = "cards/leatherworking", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Leatherworking"]= { kind = "picture", piece = "backdrops/profession_leatherworking", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Mining"]        = { kind = "picture", piece = "cards/mining", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Mining"]      = { kind = "picture", piece = "backdrops/profession_mining", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Skinning"]      = { kind = "picture", piece = "cards/skinning", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Skinning"]    = { kind = "picture", piece = "backdrops/profession_skinning", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	["Profession-overview-Card-Tailoring"]     = { kind = "picture", piece = "cards/tailoring", fit = "right", frame = true, desaturate = 0.9 },
	["Profession-background-card-Tailoring"]   = { kind = "picture", piece = "backdrops/profession_tailoring", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },   -- the schematic backdrop (T1): the tall colour panel ending in dry-brush strokes (user, 2026-09-23: "crafting tabs aswell"; was the inset rail) on the same holder (the form's own inset texture is faded with it)
	-- the secondary professions' schematics: their own tall panels (user's sheet 3d259005, 2026-09-21), cut at the schematic's aspect on the band with the still-life
	["Profession-background-card-Cooking"]    = { kind = "picture", piece = "backdrops/schematic_cooking", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },
	["Profession-background-card-Fishing"]    = { kind = "picture", piece = "backdrops/schematic_fishing", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },
	["Profession-background-card-FirstAid"]   = { kind = "picture", piece = "backdrops/schematic_firstaid", crop = "bottom", edge = "brush", desaturate = 0.9, dim = 0.42 },
	["Profession-overview-card-generic-Cooking"]  = { kind = "picture", piece = "backdrops/profession_cooking", grey = "backdrops/profession_cooking_grey", crop = "bottom", frame = true, desaturate = 0.9 },   -- a secondary card (F, crop 1): the still-life, grey while not learned, single rail over it
	["Profession-overview-card-generic-Fishing"]  = { kind = "picture", piece = "backdrops/profession_fishing", grey = "backdrops/profession_fishing_grey", crop = "bottom", frame = true, desaturate = 0.9 },
	["Profession-overview-card-generic-FirstAid"] = { kind = "picture", piece = "backdrops/profession_firstaid", grey = "backdrops/profession_firstaid_grey", crop = "bottom", frame = true, desaturate = 0.9 },
	["Profession-square-frame"]               = { kind = "slot", slot = "slot" },   -- the frame over a profession spell's icon: the rim over the icon, as the game's is
	-- the crafting page (user's picks, 2026-09-21: S1 D1 B1 N1 R1 O1 K2 L1 T1)
	["Profession-Background-Template2"]       = { kind = "picture", piece = "tiles/concrete", crop = "middle", level = -2, edge = "brush" },   -- the crafting page's backdrop: the same page stone as the book's; TWO under the page, so the list box and the schematic picture (one under their frames, which may sit at the page's level) never tie with it
	["Professions-background-summarylist"]    = { kind = "frame", dim = 0.8 },   -- the recipe list box (L1): single rail, stone body under the palette's inner panel (no eye strain, WINDOW-RULES 2e)
	["common-search-border-middle"]           = { kind = "flat", flat = "edit" },   -- (0.19.1) flat: a search box / the quantity box (was S1 / N1; a search box's fill over its glass: Kit:SkinSearchBox's opts.left)
	["common-dropdown-b-button"]              = { kind = "flat", flat = "dropdown", level = -1 },   -- (0.19.1) flat: a filter dropdown (was B6)
	["_128-RedButton-Center"]                 = { kind = "strip", base = "buttons/redbtn", state = "normal", owner = true, heightScale = 0.8 },   -- (0.19.1) the red plate again, gemless (B1, user 2026-10-04): the plate at the button's height, its closed ends on the button's (no gem caps reaching past them now)
	["_128-RedButton-Center-Disabled"]        = { kind = "strip", base = "buttons/redbtn", state = "disabled", owner = true, heightScale = 0.8 },
	["UI-SpellbookIcon-PrevPage-Up"]          = { kind = "flat", flat = "arrow", dir = "left" },   -- (0.19.1) flat: a spinner's / pager's back arrow (was the kit's)
	["UI-SpellbookIcon-NextPage-Up"]          = { kind = "flat", flat = "arrow", dir = "right" },   -- (0.19.1) flat: ... its forward arrow
	["Professions-Slot-Frame"]                = { kind = "slot", slot = "slot" },   -- a reagent slot's frame over its icon (R1)
	["auctionhouse-itemicon-border-white"]    = { kind = "slot", slot = "roundslot" },   -- the output icon's quality-coloured border (O2, user 2026-09-21): the round rim, tinted like the border
	["AuctionHouseBackgroundTemplate"]        = { kind = "frame", owner = true, bodyLayer = "BACKGROUND", bodySub = 1, edgeLayer = "BORDER", dim = 0.8 },   -- an auction house box (a Background picture + an inset NineSlice at the box's level; keyed by hand, its atlas differs per box): L1, the single rail with the list-box stone under the inner panel (2e), as REGIONS of the box, so the stone always lies under the box's scroll box and rows (user, 2026-09-24)
	["common-button-tertiary-square-normal"]  = { kind = "flat", flat = "button" },   -- (0.19.1) flat: a square icon button's plate (was K2's cog)
	["Professions_Recipe_Hover"]              = { kind = "strip", base = "lists/plate", state = "hover", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a region of the row under its text (the game's translucent hover is HIGHLIGHT over it)
	["Professions_Recipe_Active"]             = { kind = "strip", base = "lists/plate", state = "selected", owner = true, layer = "BACKGROUND", sublevel = 2 },
	["Professions-skillbar-bg"]               = { kind = "bar", bar = "frame", layer = "ARTWORK", sublevel = 4 },   -- the crafting page's rank bar: the same P1 as the book's
	["Profession-ProgressBar-BG"]             = { kind = "bar", bar = "frame", layer = "ARTWORK", sublevel = 4 },   -- the rank bars (P1): the masked fill is ARTWORK 2, so the bracket's caps go to 4 and its middle (one below the caps) to 3, both over the fill
	-- shared controls met in the legacy / quest log / guild windows (2026-09-21)
	["UI-Panel-Button-Up"]                    = { kind = "strip", base = "buttons/redbtn", state = "normal", owner = true, heightScale = 0.8 },   -- (0.19.1) the red plate again, gemless (B1, user 2026-10-04): UIPanelButtonTemplate (Left / Middle / Right file pieces; keyed by hand, file textures read back as ids)
	["UI-CheckBox-Up"]                        = { kind = "flat", flat = "check" },   -- (0.19.1) flat: the classic check box (keyed by hand; was the kit's)
	["questlog-icon-ticksquare"]              = { kind = "flat", flat = "check" },   -- (0.19.1) flat: the quest log's tracking tick box (was the kit's)
	["ui-journeys-delve-arrow-small-left"]    = { kind = "flat", flat = "arrow", dir = "left", rect = "normal" },   -- (0.19.1) flat: a reward track's arrow (was the kit's)
	["ui-journeys-delve-arrow-small-right"]   = { kind = "flat", flat = "arrow", dir = "right", rect = "normal" },   -- (0.19.1) flat: ...
	["128-redbutton-plus"]                    = { kind = "flat", flat = "plus" },   -- (0.19.1) flat: a card's expand glyph (was the kit's +)
	["128-redbutton-minus"]                   = { kind = "flat", flat = "minus" },   -- (0.19.1) flat: ...
	-- the legacy window (Blizzard_LegacySystem: the reward track, challenges
	-- and tree pages; the tree's nodes are talent buttons and stay the game's,
	-- as the talents page does). Picks pending the user's catalogue choice
	-- for the cards (kit_raw/legacy_catalog.png); the rest are the fixed looks.
	["Legacy-Rewards-Tracker-background"]     = { kind = "picture", piece = "tiles/concrete", crop = "middle", owner = true, edge = "brush" },   -- a page's backdrop: the page stone as a REGION of the page in the backdrop's own layer (the pages sit at level 100 with children at 800: no holder, no tie), fitted to the WINDOW's rect so all three pages show the same picture in the same place
	["Legacy-Challenge-BG"]                   = { kind = "picture", piece = "tiles/concrete", crop = "middle", owner = true, edge = "brush" },
	["Legacy-Tree-Frame-background"]          = { kind = "picture", piece = "tiles/concrete", crop = "middle", owner = true, edge = "brush" },
	["Legacy-Tree-Frame-divider-Vertical"]    = { kind = "edge", piece = "window/single_l" },   -- the pane divider (12 x 503): the single rail, as common-framedivider
	["Legacy-Progressbar-Frame"]              = { kind = "bar", bar = "frame", layer = "ARTWORK", sublevel = 2 },   -- LegacyProgressBarTemplate (a StatusBar: the fill at ARTWORK 0, the bracket in OVERLAY, the text over it): P1, the bracket's caps at ARTWORK 2 and its middle at 1 over the fill, the StatusBar moved into the opening (Kit:SkinStatusBar)
	["Legacy-Challenge-Left-Sub-Tab"]         = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a category list leaf (the button's normal texture, re-atlased with the selection): the plain plate ...
	["Legacy-Challenge-Left-Sub-Tab-selected"] = { kind = "strip", base = "lists/plate", state = "selected", owner = true, layer = "BACKGROUND", sublevel = 2 },   -- ... and the selected one (one rep per atlas seen, the current shown)
	["Legacy-Challenge-Cards-Bar"]            = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a criteria row's bar (180 x 30) under its text: the plain plate
	["Legacy-Tree-Frame-Points-Bar"]          = { kind = "strip", base = "lists/header" },   -- the "Available points" plate: the header plate
	["Legacy-Tree-Frame-icon-frame"]          = { kind = "slot", slot = "roundslot" },   -- a challenge's icon frame (the icon is masked round by UI-Frame-IconMask): the round rim (O2)
	["Legacy-Tree-Frame-Ring-big"]            = { kind = "slot", slot = "roundslot" },   -- the selected tree's big ring (130 on a 110 icon)
	["Legacy-Tree-Frame-Card-Ring"]           = { kind = "slot", slot = "roundslot", glow = true },   -- a tree card's ring (70 on a 67 icon); LT4 (user, 2026-09-21): the rim only, lit (the rim's hover look, additive) while the card is checked
	["Legacy-Tree-Frame-Card"]                = { kind = "fade" },   -- LT4: no card behind the ring ...
	["Legacy-Tree-Frame-Card-Glow"]           = { kind = "fade" },   -- ... and the game's selection glow is the rim's own glow now
	["Legacy-Tree-Frame-level-circle"]        = { kind = "texture", piece = "deco/gem_large", square = true, owner = true },   -- the spent-points circle (LS1): the large gem, the frame's own text over it
	["Legacy-Challenge-Cards"]                = { kind = "frame" },   -- a challenge card's body (LC1): single rail + stone on the card's rect, whatever the game atlases its Background to (complete / incomplete, collapsed / the expanded tiled trio)
	["Legacy-Challenge-Cards-Disable"]        = { kind = "frame" },
	["Legacy-Challenge-Cards-Ribbon-Brown"]   = { kind = "strip", base = "lists/header", owner = true },   -- the card's title ribbon (LC1): the header plate as a region under the Label, one rep per atlas seen (brown / blue = account-wide, each with a -Disable)
	["Legacy-Challenge-Cards-Ribbon-Blue"]    = { kind = "strip", base = "lists/header", owner = true },
	["Legacy-Challenge-Cards-Ribbon-Brown-Disable"] = { kind = "strip", base = "lists/header", owner = true },
	["Legacy-Challenge-Cards-Ribbon-Blue-Disable"]  = { kind = "strip", base = "lists/header", owner = true },
	["Legacy-Rewards-Tracker-Cards"]          = { kind = "frame" },   -- a reward card's body (LR1): single rail + stone on the card's rect (re-atlased -Green / -Disable by the game)
	["Legacy-Rewards-Tracker-Cards-Green"]    = { kind = "frame" },
	["Legacy-Rewards-Tracker-Cards-Disable"]  = { kind = "frame" },
	["Legacy-Rewards-Tracker-Diamond"]        = { kind = "texture", piece = "deco/gem_large", square = true, owner = true },   -- the card's level diamond (LD2): the large gem on its rect, the Level text over it; one rep per atlas
	["Legacy-Rewards-Tracker-Diamond-Disable"] = { kind = "texture", piece = "deco/gem_large", square = true, owner = true },
	["Legacy-Rewards-Tracker-Icons-Frame"]    = { kind = "slot", slot = "slot" },   -- a reward card's icon border (80 on a 64 square icon; re-atlased -Disable while unearned): the square rim (R1), one rep per atlas
	["Legacy-Rewards-Tracker-Icons-Frame-Disable"] = { kind = "slot", slot = "slot" },
	-- the quest log (QuestMapFrame in the world map window; 2026-09-21)
	["QuestLog-main-background"]              = { kind = "picture", piece = "tiles/vellum", crop = "middle", owner = true, parchment = "tl br" },   -- (0.20.1: the parchment nine with both curls; no stone backing: its square showed round the curls' fold -- the window behind shows there, as on the pack's page)   -- the list's page (QP2, user 2026-09-21): the parchment page painting, as the spell book's; also MelloUI's own quest list window
	["QuestDetailsBackgrounds"]               = { kind = "picture", piece = "tiles/vellum", crop = "top", owner = true, parchment = "tl br" },   -- (0.20.1: the parchment nine with both curls; no stone backing: its square showed round the curls' fold -- the window behind shows there, as on the pack's page)   -- a quest's details page: the same parchment
	-- the quest giver's dialogs (QuestDialogPanel; user, 2026-09-24): an item / reward / spell button's name plate (file art, keyed by hand) -> the plain gemless plate under the name, as a list row's; the greeting's horizontal break -> the scroll line at its natural weight across most of the page
	["UI-QuestItemNameFrame"]                 = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },
	["UI-HorizontalBreak"]                    = { kind = "strip", base = "window/divider", natural = true, widthFrac = 0.8 },
	["MapTitleBand"]                          = { kind = "picture", piece = "tiles/concrete", crop = "top", level = 0 },   -- an agreed addition (user, 2026-09-21): a body-off window's title band (the map for its canvas; the collections and LFG pages, whose rock starts below the title) filled with the page stone, inside the outer rail, so it is not bare once the title plate stands on the rail
	["questlog-frame"]                        = { kind = "frame", body = false },   -- the border around the list / details (QuestLogBorderFrameTemplate): the single rail, edges only
	["QuestLog-frame-devider"]                = { kind = "strip", base = "window/divider" },   -- the line under a header
	["questlog-icon-setting"]                 = { kind = "flat", flat = "cog" },   -- (0.19.9, the user's pick 0A) the NewUI2 cog plate in place of the game's gear (0.19.1: a bare flat plate; was K2)
	["questlog-quest-glow-yellow"]            = { kind = "strip", base = "lists/plate", state = "hover", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a quest title's highlight (the game shows it on hover / selection): the plate's hover look
	["QuestListFilter"]                       = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- the Quest List's switch on the quest log's count box (the side window's filter buttons were the first, F7, user 2026-09-21), the Auction House's category rows: the plain plate (hover from the button) ...
	["QuestListFilter-Selected"]              = { kind = "strip", base = "lists/plate", state = "selected", owner = true, layer = "BACKGROUND", sublevel = 2 },   -- ... the selected plate (the Auction House's chosen category)
	-- the guild and communities window (CommunitiesFrame; file art keyed by hand; 2026-09-21)
	["UI-Background-Rock"]                    = { kind = "picture", piece = "tiles/concrete", crop = "middle", owner = true },   -- ButtonFrameTemplate's rock background: the page stone as a region of the frame
	["bluemenu-main"]                         = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a communities list entry's background (the sheet's blue plate): the plain plate
	["bluemenu-main-selected"]                = { kind = "fade" },   -- ... its selection bar: faded, the card's iron lights instead
	["CommunitiesListEntry"]                  = { kind = "frame", hover = 1.15, pressed = 0.9, checkedTint = { 1.45, 1.3, 0.85 } },   -- a communities list entry (68 px tall: a TALL row, R3 — the plate's rails got fat): the single-rail card with stone, its iron lit gold while the game shows its Selection
	["communities-ring-gold"]                 = { kind = "slot", slot = "roundslot" },   -- the entry's icon ring: the round rim
	["CommunitiesListBody"]                   = { kind = "tile", piece = "window/single_body", owner = true },   -- the communities list's box (L1), in two parts: the stone body as a REGION of the list under its rows (the list's blue Bg, filigrees faded) ...
	["CommunitiesListBox"]                    = { kind = "frame", body = false },   -- ... and the single rail on the list's InsetFrame rect at that frame's own level (200: over the rows), the gold border faded
	["common-dropdown-textholder"]            = { kind = "flat", flat = "dropdown" },   -- (0.19.1) flat: a text dropdown, WowStyle1DropdownTemplate (was D1)
	["UI-Background-Marble"]                  = { kind = "fade" },   -- the marble strip under a list's scroll bar: nothing stands in (the trough is the bar's)
	["UI-ChatInputBorder-Mid2"]               = { kind = "flat", flat = "edit" },   -- (0.19.1) flat: the chat edit box (was S1)
	["UI-ClassTrainer-HorizontalBar"]         = { kind = "fade" },   -- the guild info page's horizontal bars over its headers: faded — a gem-capped divider stacked on a gem-capped header plate read as clutter (user, 2026-09-21); the plate alone marks the section
	["GuildFrame-Header"]                     = { kind = "strip", base = "lists/header", owner = true },   -- a guild page header (GH1, user 2026-09-21; a region of the GuildFrame sheet, keyed by hand): the header plate as a region under the page's text
	["ColumnDisplayButton"]                   = { kind = "strip", base = "lists/header", owner = true },   -- a roster column header (GC1, user 2026-09-21; WhoFrame-ColumnTabs file pieces, keyed by hand): the header plate per column, hover from the button
	["GuildNewsRow"]                          = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a guild news row (GP1, user 2026-09-21): the plain plate under the row's text, hover from the button; the blue highlight faded
	["GuildFrame-Bar"]                        = { kind = "bar", bar = "frame" },   -- the guild reputation bar (CommunitiesGuildProgressBarTemplate): P1
	["GuildFrame-Sheet"]                      = { kind = "fade" },   -- the guild info / news pages' sheet backgrounds (GuildFrame file pieces, keyed by hand): faded, the page stone shows
	["UI-Frame-InnerBorderPiece"]             = { kind = "fade" },   -- loose inset-border textures (the roster's column band, the info page's two columns): faded — the inset rail and the pane divider stand in
	["UIDropDownMenu"]                        = { kind = "flat", flat = "dropdown" },   -- (0.19.1) flat: an old-style dropdown (was D1)
	-- the dungeon finder (PVEFrame) and the collections (CollectionsJournal), 2026-09-21 first pass
	["bluemenu-Ring"]                         = { kind = "slot", slot = "roundslot" },   -- a group button's ring on its masked icon (the dungeon finder's left column): the round rim
	["bluemenu-shadowcovers"]                 = { kind = "fade" },   -- the shadow strips beside the left column: nothing stands in
	["UI-LFG-BlueBG"]                         = { kind = "fade" },   -- the listing page's blue role band (file art, keyed by hand): faded — the window's one page picture runs under it; only the INSIDE of the inset rail is the darker stone (user, 2026-09-21)
	["UI-LFG-BACKGROUND-QUESTPAPER"]          = { kind = "picture", piece = "tiles/vellum", crop = "middle", owner = true, parchment = true },   -- (0.20.1: the parchment nine)   -- the queue frame's paper (file art, keyed by hand): the parchment page, as the quest lists
	["PetList-ButtonBackground"]              = { kind = "strip", base = "lists/plate", state = "plain", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a mount / pet list row: the plain plate (hover from the button) ...
	["PetList-ButtonSelect"]                  = { kind = "strip", base = "lists/plate", state = "selected", owner = true, layer = "BACKGROUND", sublevel = 2 },   -- ... and the selected plate, shown / hidden by the game
	["WhiteIconFrame"]                        = { kind = "slot", slot = "slot" },   -- a list row's icon border (file art, keyed by hand): the square rim (R1) on the icon
	["collections-background-tile"]           = { kind = "tile", piece = "window/single_body", owner = true },   -- an icon grid's tiled backdrop (the wardrobe's items, toys, heirlooms): the list box's stone (L1) as a region under the slots, set off from the window's page stone (user, 2026-09-21), the single rail around it
	["collections-background-shadow-large"]   = { kind = "fade" },   -- the grid's shadowed edges and corners: nothing stands in (the inset rail is the edge)
	["collections-background-shadow-small"]   = { kind = "fade" },
	["collections-background-corner"]         = { kind = "fade" },
	-- the vanilla-style group finder (LFGParentFrame; 2026-09-21)
	["groupfinder-background"]                = { kind = "tile", piece = "window/single_body", owner = true },   -- the pages' INSET backdrop (the listing's category area, the browse list): the darker list-box stone as a region (user, 2026-09-21: the page stone there was too light)
	["WhoListBody"]                           = { kind = "tile", piece = "window/single_body", owner = true },   -- the who list's box: the darker list-box stone as a region under its rows (the page has no inset picture of its own there; user, 2026-09-21)
	["groupfinder-background-page"]           = { kind = "fade" },   -- the browse page's page-level painting (over its inset): faded — the window's page stone is under it already, and the inset's darker stone must show
	["groupfinder-button-cover"]              = { kind = "frame", body = false, level = 0 },   -- a category button's cover (the border over its painted banner; user, 2026-09-21): the single rail, edges only, at the button's own level so it sits over the painting (a region of the button); the painting, selection and hover stay the game's
	["groupfinder-Stat-StoneBG"]              = { kind = "fade" },   -- the who list's header band: faded — the window's one page picture runs under it (a second stone met it with a seam)
	["glues-characterSelect-searchbar"]       = { kind = "fade" },   -- the who search box's own backdrop (the S1 plate stands in)
	["UI-SquareButton-Up"]                    = { kind = "flat", flat = "button" },   -- (0.19.1) flat: a square icon button's plate (was K2)
	["shop-list-rule"]                        = { kind = "strip", base = "window/divider" },   -- the activity list's rule line
	["LFGBrowse-Result"]                      = { kind = "frame", hover = 1.15, pressed = 0.9, checkedTint = { 1.45, 1.3, 0.85 } },   -- a TALL list row (R3, user 2026-09-21; the plate's rails got fat stretched to 50-60 px): a single-rail card with stone under the row, its iron lit gold while the game marks it selected, brighter on hover
	["LFGBrowse-Grouping"]                    = { kind = "strip", base = "lists/catplate", state = "closed", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a browse grouping header: the category plate
	["groupfinder-highlightbar-yellow"]       = { kind = "fade" },   -- the selected result's bar: faded, the card's iron lights instead (R3)
	["QuestLog-icon-Expand"]                  = { kind = "flat", flat = "plus" },   -- (0.19.1) flat: a grouping header's glyphs (was the kit's + / -)
	["QuestLog-icon-shrink"]                  = { kind = "flat", flat = "minus" },   -- (0.19.1) flat: ...
	["common-button-list-large"]              = { kind = "frame", hover = 1.15, pressed = 0.9, checkedTint = { 1.45, 1.3, 0.85 } },   -- a who list row (the large list plate, 58 px tall): R3, as the browse rows
	["common-button-list-large-selected"]     = { kind = "fade" },   -- its selected bar: faded, the card's iron lights instead
	-- junctions of rails (T and +): the game has no art there, so this is an
	-- agreed addition (user, 2026-09-21: pick K, the slider thumb's gem, on
	-- every junction), placed by Kit:Joint at the kit's natural size
	["RailJoint"]                             = { kind = "texture", piece = "inputs/slider_thumb_normal", natural = true, level = 1 },

	-- The HUD's unit frames (UnitFramePanel; user's picks B3 R1 L1 N3 from
	-- kit_raw/unitframe_catalog.png, 2026-09-21). The game's frame picture
	-- (ring + name band + both bar rims in ONE texture) is faded and pieces
	-- stand on the frame's own sub-rects:
	["UI-HUD-UnitFrame-Player-PortraitOn"]    = { kind = "fade" },   -- the composite picture (player; the vehicle / class-resource / rare / minus variants are the same region re-atlased)
	["UI-HUD-UnitFrame-Target-PortraitOn"]    = { kind = "fade" },   -- ... target / focus
	["UI-HUD-UnitFrame-TargetofTarget-PortraitOn"] = { kind = "fade" },   -- ... target of target / pet
	["UI-HUD-UnitFrame-Player-PortraitOn-Vehicle"] = { kind = "fade" },
	["UI-HUD-UnitFrame-Player-PortraitOn-ClassResource"] = { kind = "fade" },
	["UI-HUD-UnitFrame-Player-PortraitOn-InCombat"] = { kind = "fade" },   -- the combat / threat flashes and status rings: faded (decoration)
	["UI-HUD-UnitFrame-Target-PortraitOn-InCombat"] = { kind = "fade" },
	["UI-HUD-UnitFrame-TargetofTarget-PortraitOn-InCombat"] = { kind = "fade" },
	["UI-HUD-UnitFrame-Player-PortraitOn-Status"] = { kind = "fade" },
	["UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Status"] = { kind = "fade" },
	["UI-HUD-UnitFrame-Player-PortraitOn-CornerEmbellishment"] = { kind = "fade" },   -- the corner flourish on the player ring
	["UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold"] = { kind = "fade" },   -- the elite / rare / boss rings: faded, the kit ring tinted gold / silver instead
	["UnitFramePortraitRing"]                 = { kind = "texture", piece = "window/portrait_ring", opening = true, owner = true },   -- R1: the ring's OPENING on the game's portrait rect, as a region in the faded picture's layer
	["UnitFrameBar"]                          = { kind = "bar", bar = "frame", dropCap = "l", capOut = true, troughSub = -1, borderGroup = "unitframe" },   -- B3: the P1 bracket on the bar, ring side capless, the far cap grown outward; the trough under the BACKGROUND-0 fill
	["UnitFrameBarMirrored"]                  = { kind = "bar", bar = "frame", dropCap = "r", capOut = true, troughSub = -1, borderGroup = "unitframe" },   -- ... the target's (ring on the right)
	["UnitFrameHealthBar"]                    = { kind = "bar", bar = "frame", dropCap = "l", capOut = true, troughSub = -1, state = "red", borderGroup = "unitframe" },   -- a health bar: the same B3, its end gem kept red (user, 2026-09-23, painted on the player frame) where every other bracket's is iron
	["UnitFrameHealthBarMirrored"]            = { kind = "bar", bar = "frame", dropCap = "r", capOut = true, troughSub = -1, state = "red", borderGroup = "unitframe" },
	["UI-HUD-UnitFrame-SmallCircle"]          = { kind = "texture", piece = "buttons/orb_normal", square = true, owner = true },   -- L1: the level circle (and the PvP badge's circle): the orb plate under the frame's own text / faction icon
	["UI-HUD-UnitFrame-Target-PortraitOn-Type"] = { kind = "fade" },   -- the target's reaction strip (the name band): faded, the plate below stands on its rect

	-- ... the party frames (UnitFramePanel too, the same picks; the member frame's picture is ARTWORK 0 with the
	-- name after it in ARTWORK, so the ring and the band go to BACKGROUND above the portrait, under the name)
	["UI-HUD-UnitFrame-Party-PortraitOn"]     = { kind = "fade" },   -- a party member's picture (and the pet's, `ui-hud-unitframe-party-portraiton` at half scale)
	["UI-HUD-UnitFrame-Party-PortraitOn-Vehicle"] = { kind = "fade" },
	["UI-HUD-UnitFrame-Party-PortraitOn-InCombat"] = { kind = "fade" },
	["UI-HUD-UnitFrame-Party-PortraitOn-Status"] = { kind = "fade" },
	["UnitFramePortraitRingParty"]            = { kind = "texture", piece = "window/portrait_ring", opening = true, owner = true, layer = "BACKGROUND", sublevel = 2 },   -- R1 on a party member / pet portrait
	["PartyFrameBackground"]                  = { kind = "frame" },   -- Edit Mode's optional party backdrop (a BackdropTemplate frame): L1, the single rail with the stone body, as its child

	-- The HUD's compact raid frames (RaidFramePanel; user's picks F1 G1 from kit_raw/raidframe_catalog.png, 2026-09-21)
	["raidframe-hp-bg-white"]                 = { kind = "frame", scale = 0.8, owner = true, bodyLayer = "BACKGROUND", bodySub = 1, edgeLayer = "ARTWORK", edgeSub = -1 },   -- F1: a compact frame's dark backing → the single rail at a small scale with the stone under the fills, as REGIONS of the frame: the stone above the faded backing, the rails above the BORDER fills and under the ARTWORK icons / name
	["options_frame_child"]                   = { kind = "frame", body = false },   -- G1: a raid group's border (`borderFrame`, shown by Edit Mode's 'display border'): the single rail 1.6, following the game's show / hide
	["UI-HUD-UnitFrame-TotemFrame"]           = { kind = "texture", piece = "buttons/roundslot_normal", square = true, owner = true },   -- a totem's round border (30 px OVERLAY over its 22 px masked icon): the round rim (O2) on its rect

	-- The HUD's action bars, micro menu, bag bar and status bars (ActionBarPanel; user's picks X2 M1 from
	-- kit_raw/actionbar_catalog.png, 2026-09-21; the buttons R1 by the rule book, the bar art faded as it lies under the rims)
	["ActionButtonRim"]                       = { kind = "slot", slot = "rim", layer = "ARTWORK", sublevel = 2, iconGrow = 0.15 },   -- an action / stance / pet button on the action bars: the THIN rim on the button's own rect, no gems (user, 2026-09-23: the gems moved to one backdrop round the bar, ActionBarPanel); its states hover / pressed / checked as the slot's. Button Border "Thin iron"; the four below are its other looks (Tools/build_kit.py THIN_RIMS)
	["ActionButtonRimHairline"]               = { kind = "slot", slot = "rimhair", layer = "ARTWORK", sublevel = 2, iconGrow = 0.15 },
	["ActionButtonRimRounded"]                = { kind = "slot", slot = "rimround", layer = "ARTWORK", sublevel = 2, iconGrow = 0.15 },
	["ActionButtonRimGold"]                   = { kind = "slot", slot = "rimgold", layer = "ARTWORK", sublevel = 2, iconGrow = 0.15 },
	["ActionButtonRimSunk"]                   = { kind = "slot", slot = "rimsunk", layer = "ARTWORK", sublevel = 2, iconGrow = 0.15 },
	["ActionButtonActiveLook"]                = { kind = "active" },   -- a check button of the game's own art the kit does not dress (the extra action button, the vehicle bar's; keyed by hand): the active look (Kit:SetActive, 0.15.0) while it is checked, in place of its checked art (an agreed addition where it has none)
	["UI-HUD-ActionBar-IconFrame"]            = { kind = "slot", slot = "slot", gemSpan = { 97 / 135, 92 / 130 }, layer = "ARTWORK", sublevel = 2 },   -- an action / stance / pet / bag button's rim (its NormalTexture): R1 — the slot rim sized to the bar's pitch so neighbours share a gem, at the NormalTexture's ARTWORK under the OVERLAY name, count, keybind and highlights; the icon fitted into its opening (Kit:SkinActionButton)
	["UI-HUD-ActionBar-IconFrame-Background"] = { kind = "tile", piece = "tiles/stone", owner = true, sublevel = -1 },   -- an empty slot's backing: the stone in the rim's opening, UNDER the icon (BACKGROUND -1), shown as the game shows the backing (empty slots only)
	["ui-hud-actionbar-iconframe-slot"]       = { kind = "fade" },   -- the empty slot's ornament
	["UI-HUD-ActionBar-IconFrame-Border"]     = { kind = "fade" },   -- the equipped-item border: faded, the rim tinted green while the game shows it
	["UI-HUD-ActionBar-Frame"]                = { kind = "fade" },   -- a bar's frame art (main bar, micro menu, bag bar): it lies under the pitch-sized rims
	["MicroMenuBackgroundArt"]                = { kind = "fade" },   -- the micro menu's backing (an IconFrame-Background region, keyed by hand)
	["ui-hud-actionbar-gryphon-left"]         = { kind = "texture", piece = "deco/rail_cap_l", fit = "height", anchor = "BOTTOMRIGHT" },   -- X2: the left end cap → the rail's orb cap, the gryphon's height, standing at the bar's end — on a holder at the BAR's level, under its buttons (user, 2026-09-21: the caps behind the bar)
	["ui-hud-actionbar-gryphon-right"]        = { kind = "texture", piece = "deco/rail_cap_r", fit = "height", anchor = "BOTTOMLEFT" },
	["ui-hud-actionbar-pageuparrow-up"]       = { kind = "flat", flat = "arrow", dir = "up" },   -- (0.19.1) flat: the action bar's page arrows (was the kit's)
	["ui-hud-actionbar-pagedownarrow-up"]     = { kind = "flat", flat = "arrow", dir = "down" },   -- (0.19.1) flat: ...
	["bag-arrow"]                             = { kind = "flat", flat = "arrow", dir = "left", rotates = true },   -- (0.19.1) flat: the bag bar's fold arrow (BagBarExpandToggle, shown by Tweaks' Collapse Arrow); its art points left unturned, the game turns it (SetRotation): the flat arrow follows
	["MicroButtonRim"]                        = { kind = "slot", slot = "rim", pitchSize = 1, layer = "OVERLAY", sublevel = 1 },   -- a micro button's plate -> the THIN rim, a square of the size ActionBarPanel gives it (SetPitch): the bag bar's slot size, the buttons spaced as the bag slots are (user, 2026-09-23: "make the microbar buttons match the bag button slots in size and have the same distance to borders"); the game's glyph fitted inside
	["UI-HUD-MicroMenu-ButtonBG-Up"]          = { kind = "slot", slot = "slot", gemSpan = { 97 / 135, 92 / 130 }, layer = "OVERLAY", sublevel = 1 },   -- a micro button's plate → the R1 slot rim sized to the button's pitch (neighbours share a gem), the game's glyph inside it, nothing painted behind (user, 2026-09-22: the cog plates M1 were not wanted, the rim is)
	["UI-HUD-MicroMenu-ButtonBG-Down"]        = { kind = "fade" },
	["UI-HUD-ExperienceBar-Frame"]            = { kind = "bar", bar = "frame", capOut = true },   -- the XP / reputation / honour bar's frame: P1, the caps outside the bar so the fill keeps its width
	["UI-HUD-ExperienceBar-Background"]       = { kind = "fade" },   -- its trough art: the bracket's trough
	["UI-HUD-ExperienceBar-Divider"]          = { kind = "texture", piece = "bars/tick", natural = true, owner = true },   -- the status bar's 20 segment dividers (pooled StatusBarDividerTemplate frames): the kit's tick at its size on each
	["UI-HUD-ActionBar-Frame-Divider-ThreeSlice-EdgeTop"] = { kind = "fade" },   -- the main bar's dividers between its buttons (pooled three-slice frames): under the rims
	["UI-HUD-ActionBar-Frame-Divider-ThreeSlice-EdgeBottom"] = { kind = "fade" },
	["!UI-HUD-ActionBar-Frame-Divider-ThreeSlice-Center"] = { kind = "fade" },
	["!UI-HUD-ActionBar-Frame-Divider-ThreeSlice-EdgeLeft"] = { kind = "fade" },
	["!UI-HUD-ActionBar-Frame-Divider-ThreeSlice-EdgeRight"] = { kind = "fade" },

	-- The backpack and bag windows (BackpackPanel, 2026-09-21): the flat portrait window shell + R1 item rims
	["uiframebackground-nineslice-cornerbottomleft"] = { kind = "fade" },   -- PortraitFrameFlatTemplate's Bg pieces: faded, the page stone stands in (SkinWindowShell bg)
	["BagSlotBackground"]                     = { kind = "fade" },   -- the combined bags' slot-cell picture (UI-Bag-Components, keyed by hand): faded, the rims and stone stand in
	["UI-Bag-1Slot"]                          = { kind = "fade" },   -- a one-slot bag's picture
	["UI-Quickslot2"]                         = { kind = "slot", slot = "slot", gemSpan = { 97 / 135, 92 / 130 }, layer = "ARTWORK", sublevel = 2 },   -- a bag slot's NormalTexture (the classic quickslot rim): R1 as the action buttons
	["bags-button-autosort-up"]               = { kind = "flat", flat = "button" },   -- (0.19.1) flat: the bags' Clean Up button's plate (was K2)
	["common-coinbox-center"]                 = { kind = "strip", base = "lists/header" },   -- the money strip (Left / Middle / Right, keyed on the middle): B2 (user, 2026-09-21), the header plate on its rect, the coins on it

	-- The minimap cluster (MinimapPanel; user's picks R1 Z2 from kit_raw/minimap_catalog.png, 2026-09-21)
	["UI-HUD-Minimap-Frame"]                  = { kind = "texture", piece = "window/portrait_ring", opening = true, openingScale = 0.75 },   -- R1 at 0.75 (user, 2026-09-21): the round frame (MinimapCompassTexture, also its -Pointer / -Circle rotated variants) → the portrait ring sized from the 198 px map's opening x 0.75, its rim over the map's edge, on a holder one level above the map; the band and buttons raised above it
	["UI-HUD-Minimap-Frame-Circle"]           = { kind = "fade" },   -- the rotated mode's underlay
	["MinimapZoneBand"]                       = { kind = "strip", base = "tabs/top", state = "title", owner = true, heightScale = 1.4, widthScale = 1.4 },   -- Z2: the zone band (BorderTop, a nine-slice of textures keyed by hand) → the title plate as regions of the band, 1.4 x the band's height and width (user, 2026-09-21), standing on the ring's top rim as a window title on its rail; the zone text centred on it
	["ui-hud-minimap-button"]                 = { kind = "texture", piece = "buttons/roundslot_normal", square = true, owner = true },   -- the tracking button's round plate: the round rim under the game's glyph
	["ui-hud-minimap-zoom-in"]                = { kind = "flat", flat = "plus" },   -- (0.19.1) flat: the minimap's zoom buttons (was the kit's + / -)
	["ui-hud-minimap-zoom-out"]               = { kind = "flat", flat = "minus" },   -- (0.19.1) flat: ...

	-- The objective tracker (TrackerPanel; user's pick T2 from the same catalogue)
	["ui-questtracker-primary-objective-header"] = { kind = "strip", base = "tabs/top", state = "title", owner = true },   -- T2: the tracker's header band → the title plate
	["UI-QuestTracker-Secondary-Objective-Header"] = { kind = "strip", base = "lists/header", owner = true },   -- a module's header band → the header plate
	["ui-questtrackerbutton-collapse-all"]    = { kind = "flat", flat = "minus" },   -- (0.19.1) flat: the tracker's collapse / expand (was the kit's - / +)
	["ui-questtrackerbutton-expand-all"]      = { kind = "flat", flat = "plus" },   -- (0.19.1) flat: ...
	["ui-questtrackerbutton-secondary-collapse"] = { kind = "flat", flat = "minus" },   -- (0.19.1) flat: ...
	["ui-questtrackerbutton-secondary-expand"] = { kind = "flat", flat = "plus" },   -- (0.19.1) flat: ...
	["ui-questtrackerbutton-filter"]          = { kind = "flat", flat = "button" },   -- (0.19.1) flat: the tracker's filter button's plate (was K2)
	["ObjectiveTrackerBackground"]            = { kind = "frame" },   -- Edit Mode's tracker backdrop (a NineSlicePanelTemplate child): L1, the single rail with stone, its child (follows the opacity); TrackerPanel lays the parchment sheet with the painted edge on its stone
	["UI-Character-Skills-BarBorder"]         = { kind = "bar", bar = "frame" },   -- a tracker progress bar's border pieces (file art, keyed by hand): P1

	-- MelloUI's own configurator (Core/Config.lua, 2026-09-21; user's picks CT2 SI1 from kit_raw/config_catalog.png): its
	-- sliders are MinimalSliderWithSteppersTemplate; everything else goes through the fixed looks' existing keys
	["_Minimal_SliderBar_Middle"]             = { kind = "flat", flat = "slider" },   -- (0.19.1) flat: a minimal slider's track (was the kit slider, SL1)
	["Minimal_SliderBar_Button"]              = { kind = "flat", flat = "knob" },   -- (0.19.1) flat: its thumb (was the gem thumb)
	["Minimal_SliderBar_Button_Left"]         = { kind = "flat", flat = "arrow", dir = "left" },   -- (0.19.1) flat: a slider's steppers (was the kit's arrows)
	["Minimal_SliderBar_Button_Right"]        = { kind = "flat", flat = "arrow", dir = "right" },   -- (0.19.1) flat: ...

	-- Tooltips (TooltipPanel, 2026-09-21; user's pick TT1 from kit_raw/tooltip_catalog.png)
	["Tooltip-NineSlice-CornerTopLeft"]       = { kind = "frame", owner = true, bodyLayer = "BACKGROUND", bodySub = -8, edgeLayer = "BORDER" },   -- TT1: a tooltip's NineSlice (the TooltipDefaultLayout pieces, keyed on the top-left corner; the other eight faded) -> the single rail with the list-box stone as REGIONS of the NineSlice in its own layers (under the tooltip's texts as the game's pieces are); the stone at the bottom of BACKGROUND (-8): the game's line icons (AddTexture's GameTooltipTextureN, the quest objectives' check marks) lie at BACKGROUND 0 of the tooltip, on the NineSlice's level (/ttdump icons, 2026-10-03)
	["TooltipStatusBar"]                      = { kind = "bar", bar = "frame", capOut = true },   -- the unit tooltip's health bar (a StatusBar with no border art; an agreed addition, as the catalogue showed it): P1 with the caps outside, the bar set in by the arms
	-- Nameplates (NameplatePanel, 2026-09-21; user's picks NP1 = P1, NC2 from kit_raw/nameplate_catalog.png)
	["NamePlateHealthBarBG"]                  = { kind = "bar", bar = "frame", capOut = true, borderGroup = "nameplate", into = 0.5 },   -- NP1: the health bar's backing (UI-HUD-CoolDownManager-Bar-BG, keyed by hand) -> P1 as the bar's regions above the fill, the caps outside, the bar set in by the arms after the game's UpdateAnchors; the trough under the fill. into 0.5 (user, 2026-10-04: "pixel perfect"): the trough's and the fill's edges at the rails' centres, under solid metal, never on the rails' soft outer rows (NameplatePanel sets the fill in and thickens the bracket by the same)
	["NamePlateCastBarBackground"]            = { kind = "frame", scale = 0.8, owner = true, bodyLayer = "BACKGROUND", edgeLayer = "ARTWORK", edgeSub = 1, outset = 2 },   -- outset 2: the single rail's 2 px outer pad, so the painted line's outer edge is ON the bar's edge and the fill (which reaches that edge, a StatusBar's fill cannot be set in) ends under the line (user, 2026-09-22: "spilling on the bottom")   -- NC2: the cast bar's background (ui-castingbar-background on a nameplate, keyed by hand; its Border faded) -> the single rail at 0.8 with the stone body as the bar's regions: the stone under the ARTWORK fill, the rails one sublevel above it, under the OVERLAY text
	["UI-HUD-Nameplates-Selected"]            = { kind = "fade" },   -- the target / focus outline around the health bar: faded; the bracket's iron shines gold while the game shows it (NameplatePanel)
	["ui-hud-nameplates-levelindicator"]      = { kind = "texture", piece = "buttons/orb_normal", square = true, owner = true },
	["ui-hud-nameplates-levelindicator-selected"] = { kind = "fade" },   -- the target ring around the level circle: faded (the bar's gold iron is the highlight)   -- the level indicator's circle: the orb, as the unit frames' level circle (the -selected ring and the skull stay the game's)

	-- The chat windows (ChatPanel, 2026-09-21; user's picks CH1 CT2 from kit_raw/chat_catalog.png)
	["ChatFrameBorder"]                       = { kind = "frame", body = false, owner = true, edgeLayer = "BORDER", outset = 8 },   -- CH1: a FloatingBorderedFrame's eight border pieces (UI-ChatFrame-BorderCorner / -BorderTop / -BorderLeft file art, keyed by hand on the top-left corner) -> the single rail as regions of the chat frame in the pieces' BORDER layer, centred on the Background's edge (the pieces reach 4 px past it); the Background stays the game's, the rail stays at full alpha (the Background Opacity moves the stone only), and so does its shade
	["ChatFrameBody"]                         = { kind = "tile", piece = "window/single_body", owner = true },   -- the window's Background (ChatFrameBackground file art, the translucent black at the alpha slider; keyed by hand): the list-box stone as a region in its place, at the slider's alpha (user, 2026-09-21: the dark cracked stone, not a flat colour)
	["ChatIconButton"]                        = { kind = "flat", flat = "button" },   -- (0.19.1) flat: a chat menu / channel button's plate (was K2)
	["chatframe-button-up"]                   = { kind = "flat", flat = "button" },   -- (0.19.1) flat: a voice button's plate (was K2)
	["ChatColumnButton"]                      = { kind = "slot", slot = "roundslot" },   -- (0.17.0, the user's pick C of chat_menu_sketch) the chat column's three game buttons -- the chat menu (UI-ChatIcon-Chat-Up), Channels (chatframe-button-up) and Friends (quickjoin-button-friendslist-up), keyed by hand: the round rim (the Round Border) on a 22-unit rect in the column, ChatPanel's disc and glyph in its opening (the whisper header's look)
	["minimal-scrollbar-arrow-returntobottom"] = { kind = "flat", flat = "arrow", dir = "down" },   -- (0.19.1) flat: scroll-to-bottom (was the kit's arrow)
	-- the chat tabs (ChatTabTemplate Left / ActiveLeft, keyed by hand) reuse the TB6 tab rules `uiframe-tab-left` / `uiframe-activetab-left`; the edit box reuses `UI-ChatInputBorder-Mid2`

	-- The damage meter (DamageMeterPanel, 2026-09-21; user's pick D1 = P1 from kit_raw/dpsmeter_catalog.png)
	["ui-damagemeters-bar-shadowbg"]          = { kind = "bar", bar = "frame", capOut = true },   -- an entry's shadow band under its status bar (+ BackgroundEdge, faded): P1, the bracket as the bar's regions above the fill, the trough under it; the caps OUTSIDE the bar's rect (a StatusBar's fill cannot be re-anchored, so the bar is set in by the arms and the fill ends under the gems — user, 2026-09-21: the fill overflowed the caps)
	["ui-damagemeters-header-bar"]            = { kind = "strip", base = "lists/header", owner = true },   -- a session window's header band: the header plate as its regions, the game's timer / dropdowns / buttons on it
	["damagemeters-background"]               = { kind = "frame" },   -- a session window's body (MinimizeContainer.Background, alpha = the transparency setting): L1 as the container's child at its level, its alpha following the setting
	["DamageMeterSourceBackground"]           = { kind = "frame" },   -- the source / spell breakdown window's Background (common-dropdown-bg, keyed by hand): L1 the same
	["DamageMeterSettingsIcon"]               = { kind = "flat", flat = "cog" },   -- (0.19.9, the user's pick 0A) the NewUI2 cog plate in place of the game's gear (0.19.1: a bare flat plate; was K2)

	-- The social window (SocialPanel, 2026-09-21): fixed looks; the raid pane's group box per the user's G pick
	["FriendsRowHighlight"]                   = { kind = "strip", base = "lists/plate", state = "hover", owner = true, layer = "BACKGROUND", sublevel = 1 },   -- a friend / ignore / raid-info row's highlight (UI-QuestLogTitleHighlight file art, keyed by hand): the plate's hover look, shown on hover only
	["FriendsPendingHeader"]                  = { kind = "strip", base = "lists/catplate", state = "closed", owner = true },   -- a pending-invite header (UI-Background-Rock BG + arrows, keyed by hand): the category plate, the game's arrows on it
	["UI-FriendsFrame-OnlineDivider"]         = { kind = "strip", base = "window/divider" },   -- the online / offline divider line
	["battlenet-friends-main"]                = { kind = "strip", base = "lists/header", owner = true },   -- the Battle.net tag band under the tabs: the header plate
	["friendslist-invitebutton-default-normal"] = { kind = "flat", flat = "button" },   -- (0.19.1) flat: the friends list's invite button's plate (was K2)
	["UI-RaidFrame-GroupOutline"]             = { kind = "frame", scale = 0.8 },   -- a raid group box's outline (162 x 80 file picture): G3 (user, 2026-09-21), the single rail at the raid frames' small weight with the stone body
	["UI-RaidInfo-Header"]                    = { kind = "fade" },   -- the raid info popup's header / footer bands: faded (the dialog's own border stands)
	["CalendarBackground"]                    = { kind = "frame", owner = true, bodyLayer = "BACKGROUND", bodySub = 1, edgeLayer = "BORDER", edgeSub = 1, dim = 0.8 },   -- a calendar day (CalendarPanel, 2026-09-24; its NormalTexture, the CalendarBackground file keyed by hand): the single-rail card with stone under the inner panel (2e: the day's event text reads on dark), as REGIONS of the day button -- the stone and panel under its BORDER event picture, the rails one sublevel over it -- on the button's rect grown by the rail's centre inset, so neighbouring days share one rail

	-- The HUD's cast bars (CastBarPanel; user's picks C1 T1 from kit_raw/castbar_catalog.png, 2026-09-21)
	["ui-castingbar-frame"]                   = { kind = "bar", bar = "castbar", capOut = true, borderGroup = "castbar" },   -- C1: the cast bar bracket (gem-cluster caps) with the game's bar as its opening: the caps stand outside the bar, which the panel narrows by their arms so the whole reads the game's width
	["ui-castingbar-background"]              = { kind = "fade" },   -- the trough art: the bracket's trough stands in
	["ui-castingbar-textbox"]                 = { kind = "strip", base = "lists/header", owner = true },   -- T1: the header plate on the 12 px under the bar (the box's lower part), the spell name on it
	["ui-castingbar-full-glow-standard"]      = { kind = "fade" },   -- the completion flash
	["castbar_shadow_embedded"]               = { kind = "fade" },   -- the overlay look's drop shadow
	["CastBarFX"]                             = { kind = "fade" },   -- the glows, flakes, wisps, sparkles and shine (keyed by hand: their animations drive alpha, the panel stops those)
}

--------------------------------------------------------------------------------
-- Covers: which HUD groups a kit module currently dresses (user rule,
-- 2026-09-21: Dark Mode and the Chat module's art hiding act on a group ONLY
-- while no kit module covers it). A kit module calls Kit:Cover(group) in
-- OnEnable and Kit:Uncover(group) in OnDisable; the tweak modules ask
-- Kit:IsCovered(group) before every sweep and re-run it from Kit:OnCover
-- (the bus's 'cover' topic: group, covered).
-- Groups: unitframes, castbar, partyframes, raidframes, actionbars, micromenu,
-- bagbar, statusbars, backpack, minimap, tracker, social, chat, damagemeter,
-- tooltip, nameplates.
--------------------------------------------------------------------------------
Kit.covers = {}

-- Every window dressed by Kit:SkinWindowShell: [frame] = { outer = rep,
-- title = rep, ring = rep, crest = rep, plate = rep }, and each new one told
-- on the bus's 'shell' topic (frame, shell): UI Modifications registers a
-- dressed window's stored place with the mover, the shade system lays every
-- window's shade (Modules/KitShade.lua). Kit.shells holds the ones already
-- there for a listener that comes later.
Kit.shells = {}

local RegisterShell

-- A panel registers a window (or a HUD element: the minimap cluster, the
-- tracker, the damage meter, a chat frame) with its drag handle — a title /
-- header plate's rep, or a plain frame — and the outer frame rep whose iron
-- lights while it moves (user, 2026-09-21: the HUD's elements too).
function Kit:RegisterShell(frame, shell)
	RegisterShell(frame, shell)
end

do
	-- every outer rail by the frame it was dressed on (rep.kitParent: a
	-- window, each bag's ContainerFrameN, a group finder page, the ignore
	-- list), as the shade keeps them (Modules/KitShade.lua): Kit.shells keeps
	-- only a window's last outer, which need not be the title's
	local rails = setmetatable({}, { __mode = "k" })

	-- the rail the title plate rides: the first one up the title's own frames,
	-- else the top window's own, else its last (a window with one rail)
	local function RailOf(frame, known)
		local f = known.title and known.title.kitParent
		for _ = 1, 16 do
			if type(f) ~= "table" or f == UIParent then
				break
			end
			local rail = rails[f]
			if rail then
				return rail
			end
			f = type(f.GetParent) == "function" and f:GetParent() or nil
		end
		return rails[frame] or known.outer
	end

	RegisterShell = function(frame, shell)
		local known = Kit.shells[frame] or {}
		known.outer = shell.outer or known.outer
		known.title = shell.title or known.title
		known.ring = shell.ring or known.ring
		-- (an own window's crest on the top rail and its short plate: their
		-- shade, Modules/KitShade.lua; never a corner ring or a drag handle)
		known.crest = shell.crest or known.crest
		known.plate = shell.plate or known.plate
		Kit.shells[frame] = known
		local outer = shell.outer
		if type(outer) == "table" then
			rails[outer.kitParent or frame] = outer
		end
		-- the title plate rides its outer rail (the rail dressed on the title's
		-- own frame, not the window's last): its caps' gems take the corners,
		-- and it runs behind the portrait ring
		local onRail = known.title and known.title.rule and known.title.rule.onRail
		if onRail then
			local rail = RailOf(frame, known)
			local skin = rail and rail.skin
			if skin and skin.SetTopGems then
				skin:SetTopGems(false)
			end
			if known.ring then
				Kit:TitleBehindRing(known.title, known.ring, rail)
			end
		end
		MelloUI:Fire("shell", frame, known)
	end
end

function Kit:IsCovered(group)
	return self.covers[group] == true
end

--------------------------------------------------------------------------------
-- Look areas (audit, 2026-09-24, rank 1: MelloUI's own windows answered "is
-- the kit on for me?" seven ways, some only once, so a switch left them in a
-- mixed look until /reload). Kit:IsOn(area), one answer per area:
--   a HUD group above  while a kit module covers it (Kit:IsCovered)
--   questTracker       MelloUI's Quest Tracker: the reskin and its own switch,
--                      UI Modifications' questTrackerKit (on unless switched off)
--   whisper            the whisper popups: as the chat windows ('chat')
--   services           the Services bar: as the minimap ('minimap')
--   questList          the Quest List, a page of the world map's quest log:
--                      while the quest log's kit (QuestLogPanel) is on
--   loot               the loot window's own parts (0.18.2: the Discard
--                      button): while the loot window's kit (LootPanel) is on
--   config, copy       the configurator and the copy window: the reskin (UI
--                      Modifications on, its reskin switch on; the Voice
--                      Over overlay's area went with it in 0.16.0: Voice
--                      Over is a row of the widget column)
--   installer          the installer: always (user, 2026-09-25: it
--                      wears the kit for every player, a new one's reskin
--                      off too -- the approved sketch, and a preview of what
--                      Full experience and Reskin only give)
-- Kit.Areas[area] = { name, topic = "look:<area>", and cover | follows = area
-- | module = name | reskin (+ switch = key) | always }; a name not listed is
-- read as a cover group. The bus's 'look:<area>' (on) goes out when an area's answer
-- changes: looked at again after a cover, a module switched ('module'), a UI
-- Modifications setting ('setting') and a profile or late settings load
-- ('restart') -- on the next frame, once for all that came together, so what
-- is switched off and on again in one go (a restart takes every kit module's
-- cover off and puts it back) tells nothing. From the frame after the world's
-- first load on (its answers then, the late settings Core takes at that load
-- included, are where it starts; nothing is told at login). Nothing polls; a
-- Fire makes nothing.
--------------------------------------------------------------------------------
Kit.Areas = {}

do
	local SWITCHES = "UIModifications"   -- the module whose settings hold the reskin and the areas' switches
	-- (in this order their changes go out)
	local LIST = {
		{ "unitframes", cover = true }, { "partyframes", cover = true }, { "castbar", cover = true },
		{ "raidframes", cover = true }, { "actionbars", cover = true }, { "micromenu", cover = true },
		{ "bagbar", cover = true }, { "statusbars", cover = true }, { "backpack", cover = true },
		{ "minimap", cover = true }, { "tracker", cover = true }, { "social", cover = true },
		{ "chat", cover = true }, { "damagemeter", cover = true }, { "tooltip", cover = true },
		{ "nameplates", cover = true },
		{ "questTracker", reskin = true, switch = "questTrackerKit" },
		{ "whisper", follows = "chat" },
		{ "services", follows = "minimap" },
		{ "questList", module = "QuestLogPanel" },
		{ "loot", module = "LootPanel" },
		-- (the settings windows; on through the installer's showcase too: its
		-- confirm boxes and the windows it opens wear the same look)
		{ "config", reskin = true, showcase = true }, { "copy", reskin = true },
		-- (0.17.1, docs/plans/game-look.md) MelloUI's own parts -- the widget
		-- column, the meter, Combat Text, the notices ... -- painted with the
		-- reskin, in the game's own look without it (MelloUI.Look). On
		-- through the installer's showcase as well: its window is built from
		-- the shared controls, the colour registry and the shell, which all
		-- ask this area (review 2026-10-02: a hybrid first window otherwise)
		{ "own", reskin = true, showcase = true },
		-- (docs/plans/game-look.md wave 4) the installer: the kit's look on
		-- its first run (the showcase, before the player chooses:
		-- Kit:Showcase), the reskin's after it
		{ "installer", reskin = true, showcase = true },
	}
	for _, area in ipairs(LIST) do
		area.name, area.topic = area[1], "look:" .. area[1]
		Kit.Areas[area.name] = area
	end

	-- UI Modifications' settings as saved: read straight, no defaults laid
	-- in (every switch read here is on by default, so a key not saved yet
	-- reads as on)
	local function Switches()
		local db = MelloUI.db
		local modules = db and db.modules
		return modules and modules[SWITCHES]
	end

	-- the reskin: UI Modifications on (its switch, as the configurator reads
	-- it) and its reskin switch on
	local function Reskin()
		if not (MelloUI.db and MelloUI:IsModuleEnabled(SWITCHES)) then
			return false
		end
		local s = Switches()
		return not (s and s.reskin == false)
	end

	-- read live for each area, the reskin too (review, 2026-09-25: read once
	-- per pass, a listener that switched it left the later areas told from
	-- before)
	local function AreaOn(area)
		if area.follows then
			area = Kit.Areas[area.follows]
		end
		if area.always or (area.showcase and Kit.showcaseOn) then
			return true
		elseif area.cover then
			return Kit.covers[area.name] == true
		elseif area.module then
			local module = MelloUI:GetModule(area.module)
			return (module and module.isEnabled) and true or false
		elseif area.reskin then
			if not Reskin() then
				return false
			end
			local s = area.switch and Switches()
			return not (s and s[area.switch] == false)
		end
		return false
	end

	function Kit:IsOn(area)
		local entry = self.Areas[area]
		if not entry then
			return self.covers[area] == true
		end
		return AreaOn(entry)
	end

	-- each area's answer as last told (nil until the first pass); watched
	-- from the world's first load on
	local told = {}
	local watching, started = false, false
	local KEY = "Kit look areas"   -- the bus owner and the Kit:NextFrame key

	-- every area read again, a change told (in LIST's order); the first pass
	-- only takes the answers down
	local function Pass()
		local tell = started
		started = true
		for i = 1, #LIST do
			local area = LIST[i]
			local on = AreaOn(area)
			if told[area.name] ~= on then
				told[area.name] = on
				if tell then
					MelloUI:Fire(area.topic, on)
				end
			end
		end
	end

	-- something that can change an answer: the pass on the next frame, once
	-- however often it was asked for (review, 2026-09-25: rechecked at once, a
	-- restart -- every profile load, the late settings at login -- told each
	-- covered area off and on again). What a look listener switches is looked
	-- at on the frame after, so a pass never runs inside another.
	local function Later()
		if watching then
			Kit:NextFrame(KEY, Pass)
		end
	end

	-- a cover changed: its listeners at once, the areas it answers for on the
	-- next frame
	local function NotifyCover(group, covered)
		MelloUI:Fire("cover", group, covered)
		Later()
	end

	-- the installer's first run open (on) or closed (off): the areas marked
	-- showcase (the installer's, the settings windows', MelloUI's own parts')
	-- answer on meanwhile, whatever the reskin (the kit's look is its
	-- showcase); their 'look:<area>' goes out on the next frame as for any
	-- switch
	function Kit:Showcase(on)
		on = on and true or false
		if self.showcaseOn ~= on then
			self.showcaseOn = on
			Later()
		end
	end

	function Kit:Cover(group)
		if not self.covers[group] then
			self.covers[group] = true
			NotifyCover(group, true)
		end
	end

	function Kit:Uncover(group)
		if self.covers[group] then
			self.covers[group] = nil
			NotifyCover(group, false)
		end
	end

	-- (an alias of the bus's 'cover' topic, audit 2026-09-24 rank 5)
	function Kit:OnCover(fn)
		MelloUI:On("cover", fn)
	end

	-- the world's first load (PLAYER_ENTERING_WORLD: after Core's start-up
	-- pass, before anyone can switch a thing): the changes watched, and the
	-- answers taken down on the next frame, after Core's own handler of the
	-- event (a late settings load and its restart) whichever of the two runs
	-- first
	local function OnSetting(module)
		if module == SWITCHES then
			Later()
		end
	end
	-- (0.19.8: the modules come up over the login's first frames, Core's
	-- start-up pass; a module area's answer is its module being on, so the
	-- first answers are taken once they all are)
	local function Watch()
		watching = true
		MelloUI:On("setting", OnSetting, KEY)
		MelloUI:On("module", Later, KEY)
		MelloUI:On("restart", Later, KEY)
		Later()
	end
	local world = CreateFrame("Frame")
	world:RegisterEvent("PLAYER_ENTERING_WORLD")
	Perf.SetScript(world, "OnEvent", function(self)
		self:UnregisterAllEvents()
		if MelloUI.WhenModulesOn then
			MelloUI:WhenModulesOn(Watch)
		else
			Watch()
		end
	end)
end

--------------------------------------------------------------------------------
-- Combat: geometry on a protected frame's children is refused while the
-- player is in combat; the HUD modules queue it here and it runs at
-- PLAYER_REGEN_ENABLED (at once when out of combat). A refit hook on the
-- game's own layout method goes through the same queue.
-- A fight can leave a lot queued (/melloperf 2026-09-24: 16.8 ms in the
-- frame the fight ended): it runs in order, a few ms of it per frame, and
-- stops if a new fight starts before it is through (the rest waits for that
-- one to end). The same work queued twice in a row runs once. Anything asked
-- for out of combat while some is still waiting goes in behind it, in the
-- same slices, so the order is kept and no frame pays for the lot; what a
-- queued piece asks for runs at once, as it did.
-- A caller can name its work: Kit:WhenOutOfCombat(fn, key), the key being
-- the frame or rep it refits. Asked for again under the same key while the
-- first is still waiting, the waiting one is dropped and the new one goes in
-- at the end: a fight's many asks for one refit (a hook on every target
-- change makes a new closure each time) run once, last, as the last of them
-- did. Only for work that just re-reads the frame: an on / off pair must not
-- share a key.
--------------------------------------------------------------------------------
local combatQueue, queueAt = {}, 1   -- the queued work and the next piece to run
local queueKeys = {}                 -- [index] = the key its piece was queued under
local waitingKeys = {}               -- [key] = the index of that key's piece still waiting
local QUEUE_BUDGET = 3               -- ms of queued work per frame after a fight
local runningQueued = false
local combatFrame = CreateFrame("Frame")
combatFrame:Hide()

-- Kit:WhenQueueIdle(fn): fn() once the queue is through, for work that can
-- wait and must not add to the frames the queue works in (the windows built
-- ahead in idle turns). On the next frame when out of combat with nothing
-- waiting; else on the frame after the last queued piece ran, after the
-- fight's end (a new fight before then keeps it waiting). Never at once, so
-- an fn that asks again goes on a frame later, not inside itself. The same
-- fn asked for again while it waits runs once (still waiting further on in
-- a run under way: there only). An error in one is reported and the rest
-- still run. Kit:IsQueueBusy(): in combat, or queued work still waiting.
-- QueueIdleWaiters(): the queue's end hands on to them.
local QueueIdleWaiters
do
	local idleWaiters, idleRunning = {}, {}   -- the fns in the order asked; the same, being run
	local idleQueued = false
	local runFrom, runTo = 1, 0               -- idleRunning[runFrom..runTo]: yet to run in this one

	local function QueueBusy()
		return InCombatLockdown() or queueAt <= #combatQueue
	end

	local function RunIdleWaiters()
		idleQueued = false
		if QueueBusy() then
			return   -- a new fight or new work since: they wait for that to be through
		end
		local list = idleWaiters
		idleWaiters, idleRunning = idleRunning, list
		runTo = #list
		for i = 1, runTo do
			runFrom = i + 1
			local fn = list[i]
			list[i] = nil
			local ok, err = pcall(fn)
			if not ok then
				geterrorhandler()(err)
			end
		end
		runFrom, runTo = 1, 0
	end

	function QueueIdleWaiters()
		if not idleQueued and idleWaiters[1] ~= nil then
			idleQueued = true
			C_Timer.After(0, RunIdleWaiters)
		end
	end

	function Kit:WhenQueueIdle(fn)
		if type(fn) ~= "function" then
			return
		end
		for i = runFrom, runTo do
			if idleRunning[i] == fn then
				return
			end
		end
		for i = 1, #idleWaiters do
			if idleWaiters[i] == fn then
				return
			end
		end
		idleWaiters[#idleWaiters + 1] = fn
		if not QueueBusy() then
			QueueIdleWaiters()
		end
	end

	function Kit:IsQueueBusy()
		return QueueBusy()
	end
end

-- Runs what waits, in order; with a budget only until that many ms have
-- gone (the frame's OnUpdate goes on with the rest). An error in one piece
-- is reported and the rest still run. A dropped piece is a false.
local function RunQueued(budget)
	local t0 = budget and debugprofilestop()
	while queueAt <= #combatQueue do
		if InCombatLockdown() then
			combatFrame:Hide()
			return
		end
		local at = queueAt
		local fn, key = combatQueue[at], queueKeys[at]
		queueAt = at + 1
		if key ~= nil and waitingKeys[key] == at then
			waitingKeys[key] = nil
		end
		if fn then
			runningQueued = true
			local ok, err = pcall(fn)
			runningQueued = false
			if not ok then
				geterrorhandler()(err)
			end
		end
		if budget and queueAt <= #combatQueue and debugprofilestop() - t0 >= budget then
			combatFrame:Show()
			return
		end
	end
	if queueAt > 1 then
		combatQueue, queueKeys, queueAt = {}, {}, 1
	end
	combatFrame:Hide()
	-- through: what waited for that goes on, on the next frame
	QueueIdleWaiters()
end

local function Enqueue(fn, key)
	if key ~= nil then
		local at = waitingKeys[key]
		if at then
			combatQueue[at] = false
		end
	elseif queueAt <= #combatQueue and combatQueue[#combatQueue] == fn then
		return
	end
	local n = #combatQueue + 1
	combatQueue[n], queueKeys[n] = fn, key
	if key ~= nil then
		waitingKeys[key] = n
	end
end

combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
Perf.SetScript(combatFrame, "OnEvent", function()
	RunQueued(QUEUE_BUDGET)
end)
Perf.SetScript(combatFrame, "OnUpdate", function()
	RunQueued(QUEUE_BUDGET)
end)

function Kit:WhenOutOfCombat(fn, key)
	if InCombatLockdown() then
		Enqueue(fn, key)
	elseif not runningQueued and queueAt <= #combatQueue then
		-- a fight's work is still being worked through: behind it
		Enqueue(fn, key)
		combatFrame:Show()
	else
		fn()
	end
end

-- An action-style button's hooks, one handler each for every button (user,
-- 2026-09-24: the bags' first open, 16 hooks per slot, each with closures of
-- its own): the slot's state is kept by its button and its icon (slotOf), a
-- border's rim rep by the border (borderOf).
local slotOf = setmetatable({}, { __mode = "k" })     -- [button or icon] = the slot's state (Kit:SlotStone): { rep, stone, icon, button, itemButton, ... }
local borderOf = setmetatable({}, { __mode = "k" })   -- [border] = the rim rep

-- the icon's atlas (a pcall with no closure made per call)
local function IconAtlas(icon)
	return icon.GetAtlas and icon:GetAtlas()
end

-- whether the slot is empty (an item button's by its SetItemButtonTexture,
-- below in Kit:SlotStone)
local function SlotEmpty(st)
	local icon, button = st.icon, st.button
	if not icon:IsShown() then
		return true
	end
	if not st.itemButton then
		return false
	end
	if Kit.slotEmpty[button] ~= nil then
		return Kit.slotEmpty[button]
	end
	local ok, atlas = pcall(IconAtlas, icon)
	return ok and atlas ~= nil and atlas == button.emptyBackgroundAtlas
end

-- the stone shown while the slot is empty, an item button's icon see-through
local function SlotSync(st)
	if st.rep.object:IsShown() then
		local empty = SlotEmpty(st)
		st.stone:SetShown(empty)
		if st.itemButton then
			st.icon:SetAlpha(empty and 0 or 1)
		end
	end
end

local Slot_OnItemTexture = Shared("SetItemButtonTexture on a kit slot", function(button, texture)
	Kit.slotEmpty[button] = texture == nil
	SlotSync(slotOf[button])
end)
local Slot_OnIcon = Shared("Show / Hide on a kit slot's icon", function(icon)
	SlotSync(slotOf[icon])
end)

--------------------------------------------------------------------------------
-- Kit:SlotStone(rep, button, bg, opts): the stone in a slot rim's opening,
-- one for every slot that has one (audit, 2026-09-24: the pet stable kept a
-- copy of the action buttons' fit and missed its fixes; the next slot fix
-- lands here, once). The stone stands in for `bg` (the slot's own backing,
-- faded) in the opening of the rim `rep` put on `button`, fitted into that
-- opening again when the rim's art changes (rim.onBaseChanged: a Button
-- Border), when it is re-pitched (rep:SetPitch), and a frame later when the
-- rim's size was not known yet (Kit:DrawnSize 0, 0: Kit:RefitLater).
--   replace    the panel's Replace: the stone is one of its reps (required)
--   base       the rim's art family while it has none of its own
--              (default "buttons/slot", the action buttons' R1)
--   showWhen   "empty" (default): shown only while the slot is empty, an item
--              button's picture see-through then (SlotSync); "always": shown
--              whenever the kit is (the pet stable's slots)
--   tintFrom   a region whose tint the stone wears, copied on each of its
--              SetVertexColor (the stable's empty-slot picture: red for a slot
--              not bought yet)
--   noFade     `bg` left as the game's (a bag slot has no backing: the stone
--              is put on the button itself)
--   icon       the slot's icon (default the rim's, else button.icon)
-- Returns the stone rep, or nil. Made once per slot; a refit makes nothing.
-- Kit:SyncSlotStone(button) reads the game's state onto the stone again.
--------------------------------------------------------------------------------
do
	local tintOf = setmetatable({}, { __mode = "k" })   -- [tintFrom region] = the slot's state

	-- the stone's opening: the opening of the rim it is in (its art can change
	-- live), measured as drawn (not laid out yet a rim reads as its atlas sheet)
	local function SlotFit(st)
		local rim, opening = st.rim, st.opening
		local name = (rim.base or st.base) .. "_normal"
		local piece = PIECES[name]
		local l, r, t, b = Kit:Insets(name, 1)
		local rw, rh = Kit:DrawnSize(rim)
		opening:ClearAllPoints()
		if piece and l and rw > 0 and rh > 0 then
			opening:SetPoint("TOPLEFT", rim, "TOPLEFT", rw * l / piece.w, -rh * t / piece.h)
			opening:SetPoint("BOTTOMRIGHT", rim, "BOTTOMRIGHT", -rw * r / piece.w, rh * b / piece.h)
		else
			opening:SetAllPoints(st.button)
			if piece and l then
				Kit:RefitLater(rim)   -- the rim's size not known yet: fitted again a frame later
			end
		end
	end

	-- the stone in the tint the game gives the region it copies (secret-safe:
	-- a secret colour leaves the stone as it is)
	local function SlotTint(st)
		local tex, from = st and st.stone and st.stone.tex, st and st.tintFrom
		if not (tex and from) then
			return
		end
		local ok, r, g, b = pcall(from.GetVertexColor, from)
		if ok and not Secret(r) and not Secret(g) and not Secret(b) and type(r) == "number" then
			tex:SetVertexColor(r, g, b)
		end
	end
	local Slot_OnTint = Shared("SetVertexColor on a kit slot stone's tint", function(region)
		SlotTint(tintOf[region])
	end)

	function Kit:SlotStone(rep, button, bg, opts)
		opts = opts or {}
		local rim = rep and rep.object
		local replace = opts.replace
		if not (rim and button and bg and replace) then
			return nil
		end
		local opening = CreateFrame("Frame", nil, button)
		opening:EnableMouse(false)
		-- (the slot's state: the shared handlers and the refit read it)
		local st = { rep = rep, rim = rim, button = button, opening = opening, base = opts.base or "buttons/slot",
			icon = opts.icon or rim.icon or button.icon }
		local function Fit()
			SlotFit(st)
		end
		Fit()
		rim.onBaseChanged = Fit
		-- (the opening is the stone's own sizer: no frame made for it per slot)
		local stone = replace(bg, { as = "UI-HUD-ActionBar-IconFrame-Background", rect = opening, noFade = opts.noFade,
			sizer = opening }) or nil
		st.stone = stone
		local icon = st.icon
		if stone then
			slotOf[button] = st
			if opts.showWhen ~= "always" and icon then
				-- the stone shows while the slot is EMPTY: the game hides the icon
				-- then (its own backing shows only on a bar whose art is hidden —
				-- on the main bar the faded frame art was the empty slot's look).
				-- An ITEM button (a bag window's slot, a bag bar slot) keeps its
				-- icon shown when empty, painted with its empty-slot picture
				-- (`emptyBackgroundAtlas` / `emptyBackgroundTexture`, put there by
				-- SetItemButtonTexture(nil)): the Item Background never showed
				-- (user, 2026-09-23). Its emptiness is read from that call; while
				-- empty the icon (the game's picture) is see-through.
				st.whileEmpty = true
				st.itemButton = ((button.emptyBackgroundAtlas or button.emptyBackgroundTexture) and button.SetItemButtonTexture) and true or false
				slotOf[icon] = st
				if st.itemButton then
					hooksecurefunc(button, "SetItemButtonTexture", Slot_OnItemTexture)
					local disable = rep.onDisable
					rep.onDisable = function(...)
						if disable then
							disable(...)
						end
						icon:SetAlpha(1)
					end
				end
				hooksecurefunc(icon, "Show", Slot_OnIcon)
				hooksecurefunc(icon, "Hide", Slot_OnIcon)
				hooksecurefunc(icon, "SetShown", Slot_OnIcon)
				local enable = stone.Enable
				stone.Enable = function(self)
					enable(self)
					SlotSync(st)
				end
				SlotSync(st)
			end
			-- tinted as the game tints the picture it stands for (one shared
			-- handler for every slot, no closure of its own: audit, 2026-09-24)
			local from = opts.tintFrom
			if from and from.SetVertexColor then
				st.tintFrom = from
				tintOf[from] = st
				hooksecurefunc(from, "SetVertexColor", Slot_OnTint)
				SlotTint(st)
			end
		end
		-- a rim re-sized to a new pitch: the opening fitted again
		local setPitch = rep.SetPitch
		rep.SetPitch = function(self, px, py)
			if setPitch then
				setPitch(self, px, py)
			end
			Fit()
		end
		return stone
	end

	-- The game's state onto a slot's stone again (a window's refresh): the tint
	-- it copies and, for a stone shown while empty, whether it shows
	function Kit:SyncSlotStone(button)
		local st = button and slotOf[button]
		if not st then
			return
		end
		if st.tintFrom then
			SlotTint(st)
		end
		if st.whileEmpty then
			SlotSync(st)
		end
	end
end

-- the rim green while the game shows the equipped border
local function BorderTint(rep, border)
	if rep.object:IsShown() then
		if border:IsShown() then
			rep.object:SetVertexColor(0.5, 1, 0.5)
		else
			rep.object:SetVertexColor(1, 1, 1)
		end
	end
end
local Slot_OnBorder = Shared("Show / Hide on a kit slot's border", function(border)
	BorderTint(borderOf[border], border)
end)

-- An action-style button (ActionButtonTemplate and its small kin: action,
-- stance, pet, possess and bag slot buttons): the R1 rim on its NormalTexture
-- sized to the bar's pitch { x, y } so neighbours share a gem, the icon fitted
-- into the rim's opening (its rounded mask taken off while the rim is on),
-- the empty-slot backing on stone, the pushed / highlight / checked textures
-- faded (the rim carries the states), the equipped border faded and the rim
-- tinted green while the game shows it. `replace` is the panel's Replace.
-- opts.qualityGem: an item slot of the bag windows, the bank or the guild
-- bank wears its item's quality gem (Kit:ItemGem; the value is the window's
-- reader of the slot's quality, for a slot the game filled before it was
-- dressed). Returns the rim rep; rep:SetPitch(x, y) re-sizes it after a
-- re-layout.
function Kit:SkinActionButton(button, replace, pitch, opts)
	opts = opts or {}
	-- the rim texture: the template's key, else the widget's own (a bag
	-- button has no NormalTexture key; one is never written onto it -- the
	-- game reads that key, 2026-09-23 audit)
	local normal = button and (button.NormalTexture or (button.GetNormalTexture and button:GetNormalTexture()))
	if not (button and normal and button.icon) or Kit.repOf[button] ~= nil then
		return button and Kit.repOf[button] or nil
	end
	local extra = { button.PushedTexture, button.HighlightTexture, button.CheckedTexture }
	if button.GetPushedTexture then
		extra[#extra + 1] = button:GetPushedTexture()
	end
	if button.GetHighlightTexture then
		extra[#extra + 1] = button:GetHighlightTexture()
	end
	if button.GetCheckedTexture then
		extra[#extra + 1] = button:GetCheckedTexture()
	end
	-- opts.alsoFade: more of the game's art the rim stands in for, and
	-- opts.checked its checked state where the button has no flag (a bag
	-- slot: an item button, its open bag shown by a highlight region)
	if opts.alsoFade then
		for _, region in ipairs(opts.alsoFade) do
			extra[#extra + 1] = region
		end
	end
	-- opts.as: another slot rule (the action bars' thin rim, "ActionButtonRim")
	local rep = replace(normal, { as = opts.as or "UI-HUD-ActionBar-IconFrame", button = button, rect = button, pitch = pitch,
		icon = button.icon, alsoFade = extra, checked = opts.checked })
	Kit.repOf[button] = rep or false
	if not rep then
		return nil
	end
	-- a thin rim follows the one Button Border of every window
	for _, rule in pairs(self.buttonLooks.rimRule) do
		if opts.as == rule then
			self:RegisterButtonRim(button)
			break
		end
	end
	-- the icon's rounded mask off while the rim is on (its square opening)
	local mask = button.IconMask or button.SquareMask
	local icon = button.icon
	local onEnable, onDisable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if onEnable then
			onEnable(...)
		end
		if mask and icon.RemoveMaskTexture then
			pcall(icon.RemoveMaskTexture, icon, mask)
		end
	end
	rep.onDisable = function(...)
		if onDisable then
			onDisable(...)
		end
		if mask and icon.AddMaskTexture then
			pcall(icon.AddMaskTexture, icon, mask)
		end
	end
	-- the empty slot's backing: the kit's slot stone in the rim's opening,
	-- shown while the slot is empty (Kit:SlotStone); its ornament faded (a bag
	-- slot has no backing region: `opts.emptyStone` puts the stone on the
	-- button itself, replacing its NormalTexture's empty look)
	if button.SlotBackground or opts.emptyStone then
		local stone = self:SlotStone(rep, button, button.SlotBackground or normal, { replace = replace, base = "buttons/slot",
			showWhen = "empty", noFade = not button.SlotBackground, icon = icon })
		Kit.slotStoneOf[button] = stone   -- its texture (stone.tex) can be swapped: Action Bars Kit's Button Background
	end
	if button.SlotArt then
		replace(button.SlotArt, { as = "ui-hud-actionbar-iconframe-slot" })
	end
	-- a quality border (a bag slot's WhiteIconFrame, tinted by the game): the
	-- game's, kept over the icon — anchored to the icon so it follows the
	-- icon into the rim's opening (user, 2026-09-21: the rim itself is not
	-- recoloured by the quality); the game's anchors put back on disable
	local quality = opts.qualityBorder
	if quality then
		local saved = {}
		for i = 1, quality:GetNumPoints() do
			saved[i] = { quality:GetPoint(i) }
		end
		local enable2, disable2 = rep.onEnable, rep.onDisable
		rep.onEnable = function(...)
			if enable2 then
				enable2(...)
			end
			quality:ClearAllPoints()
			quality:SetAllPoints(icon)
		end
		rep.onDisable = function(...)
			if disable2 then
				disable2(...)
			end
			quality:ClearAllPoints()
			for _, pt in ipairs(saved) do
				quality:SetPoint(unpack(pt))
			end
		end
	end
	-- the item's quality as a gem in the slot's corner (a bag window's, the
	-- bank's or the guild bank's slot: `opts.qualityGem`, Kit:ItemGem below)
	if opts.qualityGem then
		self:ItemGem(button, rep, opts.qualityGem)
	end
	-- the equipped border: faded, the rim green while the game shows it
	if button.Border then
		replace(button.Border, { as = "UI-HUD-ActionBar-IconFrame-Border" })
		local border = button.Border
		borderOf[border] = rep
		hooksecurefunc(border, "Show", Slot_OnBorder)
		hooksecurefunc(border, "Hide", Slot_OnBorder)
		hooksecurefunc(border, "SetShown", Slot_OnBorder)
		BorderTint(rep, border)
	end
	-- a button skinned while the panel is already on was enabled by `replace`
	-- before the hooks above existed: run them now
	if rep.object:IsShown() and rep.onEnable then
		rep.onEnable(rep)
	end
	return rep
end

--------------------------------------------------------------------------------
-- Quality gems on item slots (user, 2026-09-26: "can we also add those
-- tooltip gems onto the items in the backpack themselves, to easy as a glance
-- separate normal items from Junk Items etc"; option A of the bag gems
-- mockup). Every item in a slot of the bag windows, the bank and the guild
-- bank shows a small gem in its quality's TRUE colour, the game's own
-- (ITEM_QUALITY_COLORS: junk grey, common white, uncommon green, rare blue,
-- epic purple, legendary orange, artifact and heirloom in theirs): the
-- tooltip's gem, MelloUI.QuestInk's QI.Gem (one gem for the interface). An
-- empty slot, and a quality the game hands over secret, not at all or one
-- ITEM_QUALITY_COLORS has no colour for, shows none.
--   where       the slot's top-left corner, 2 px in from the icon's corner
--               (the icon in the rim's opening), about 37 % of the button's
--               size (14 px on the 37 px slot; the mockup's 15 on 40); a
--               child of the button, so it scales with it
--   layering    over the button's own art (the icon, the quality border, the
--               stack count's layer) and over its cooldown child, two levels
--               up: a level of its own (WINDOW-RULES: never tie with the
--               game's frame; between the button and its cooldown, one level
--               apart, there is none). The diamond keeps to its corner: the
--               count stays in the bottom-right one, the cooldown's time in
--               the middle
--   the corner  the game's own marks there: the merchant's junk coin
--               (JunkIcon), the upgrade arrow (UpgradeIcon), a quest
--               starter's "!" (IconQuestTexture set to TEXTURE_ITEM_QUEST_BANG,
--               its "!" down the icon's left side) and a crafting reagent's
--               quality badge (ProfessionQualityOverlay: the game makes it
--               the first time the slot holds one, TOPLEFT -3, 2, its atlas
--               33 x 28; crafted gear wears it only while the Professions
--               window is open). While one shows, the gem steps over to the
--               top-right corner, and back when it goes: both stay readable
--               (the badge's box reaches past the middle of a 37 px slot, so
--               no corner is clear of the box itself; the top-right one is
--               the furthest from its picture, which hangs off the top-left)
--   dimmed      a slot the game dims (the search box, or an item that does
--               not fit what an open window wants: its ItemContextOverlay
--               in the game's dim mode, ItemButtonConstants.ContextMatch
--               .Standard; an older client's searchOverlay) dims its gem as
--               well. The same overlay as the runeforge glow round an item
--               the game highlights is not a dim: the gem stays bright
--   when        from the game's own update of the slot, post-hooked on the
--               button at its first dress: SetItemButtonQuality (the bags,
--               the bank and the guild bank all call it with the quality,
--               poor and common too; the game's own border is none for
--               poor, grey for common, the quality's colour from uncommon
--               up), UpdateItemContextOverlay (the search's shade; each
--               window's update of a slot ends with it, the junk coin, the
--               quest mark and the reagent's badge set by then), the quest
--               texture's SetTexture (the "!" or the plain border), and the
--               reagent badge's SetShown (hooked when the gem first meets
--               it: the Professions window shows and hides crafted gear's
--               badge on its own). A gem is made the first time its slot
--               has an item to show with the switch on (nothing at login,
--               none for an empty slot), kept with the pooled button and
--               recoloured on those updates; no OnUpdate, no timer
--   the switch  one for the three windows: Quality Gems, with the bags' looks
--               that the bank and the guild bank wear (Backpack Kit's
--               `qualityGems`, on; its row under Bags on UI Modifications'
--               Windows tab, so it is changed while Bags is on, as the Item
--               Background is picked on the bag windows). Off: every gem
--               hidden at once, none made. Heard on the bus's 'setting' and,
--               after a profile load, its 'restart'
--   kit off     a slot whose kit is off (its window's module, or the reskin)
--               shows none: the gem belongs to the dressed slot
--   Kit:ItemGem(button, rep, read)  from Kit:SkinActionButton's
--               opts.qualityGem; `read(button)` -> the slot's quality and
--               whether it starts a quest, the game's record of a slot it
--               filled before the dress (the bank fills its slots as it makes
--               them, the guild bank in its own OnShow, before the kit's)
--   junk        (0.16.0, user 2026-09-30: "the junk items should be
--               desaturated in the inventory") a slot holding a poor item
--               (quality 0) shows its icon grey while Grey Out Junk (Backpack
--               Kit's `greyJunk`, on) is on and the slot's kit is on; kept
--               through the game's own SetItemButtonDesaturated (a picked-up
--               item's grey), one post-hook for all slots; the colour back as
--               the item goes or the switch goes off
--   Kit:SyncItemGems()  every slot again (the switches)
--   Kit:ItemGemCounts() -> slots dressed, gems made, gems shown
--------------------------------------------------------------------------------
do
	local SIZE, INSET, DIM = 0.37, 2, 0.25   -- of the button's width; px in from the icon's corner; a dimmed slot's gem
	local SWITCH_MODULE, SWITCH_KEY, JUNK_KEY = "BackpackPanel", "qualityGems", "greyJunk"
	local Num, Finite, Text = MelloUI.Safe.Number, MelloUI.Safe.Finite, MelloUI.Safe.Text
	local slots = {}                                     -- every slot that wears one, in the order dressed
	local gemOf = setmetatable({}, { __mode = "k" })     -- [button] = its slot's state
	local gemOfArt = setmetatable({}, { __mode = "k" })  -- [quest texture] = its slot's state
	local gemOfBadge = setmetatable({}, { __mode = "k" }) -- [reagent quality badge] = its slot's state
	local wanted = nil                                   -- the switch as last read (nil: read it again)
	local junkWanted = nil                               -- Grey Out Junk as last read (nil: read it again)
	local desatHooked = false
	local made = 0

	local function JunkWanted()
		if junkWanted == nil then
			if not MelloUI.db then
				return true
			end
			local db = MelloUI:GetModuleDB(SWITCH_MODULE)
			junkWanted = not (db and db[JUNK_KEY] == false)
		end
		return junkWanted
	end

	-- a poor item's icon grey (the slot's kit on, the switch on); the colour
	-- back once it is not
	local function Grey(st)
		local icon = st.icon
		if not icon then
			return
		end
		if st.on and st.q == 0 and JunkWanted() then
			st.grey = true
			icon:SetDesaturated(true)
		elseif st.grey then
			st.grey = false
			icon:SetDesaturated(false)
		end
	end

	local function Wanted()
		if wanted == nil then
			if not MelloUI.db then
				return true   -- (the settings not bound yet: read again next time)
			end
			local db = MelloUI:GetModuleDB(SWITCH_MODULE)
			wanted = not (db and db[SWITCH_KEY] == false)
		end
		return wanted
	end

	-- the game's own colour of an item quality (`q` a plain number); nil when
	-- it has none plainly. ITEM_QUALITY_COLORS is the game's (its colour
	-- manager fills it for every quality there is, 0 .. NumValues - 1): a
	-- quality it lacks is unknown, no gem. Only a client without that table
	-- asks C_Item, for a quality in range (it answers a colour for any number)
	local function Colour(q)
		local list = ITEM_QUALITY_COLORS
		local r, g, b
		if type(list) == "table" then
			local c = list[q]
			if type(c) ~= "table" then
				return nil
			end
			r, g, b = c.r, c.g, c.b
		else
			local meta = Enum and Enum.ItemQualityMeta
			local count = meta and Num(meta.NumValues) or 9
			if not (C_Item and C_Item.GetItemQualityColor) or q < 0 or q >= count or q ~= math.floor(q) then
				return nil
			end
			local ok
			ok, r, g, b = pcall(C_Item.GetItemQualityColor, q)
			if not ok then
				return nil
			end
		end
		r, g, b = Num(r), Num(g), Num(b)
		if r and g and b then
			return r, g, b
		end
		return nil
	end

	-- a region of the game's shown (a secret reads as not shown)
	local function Shown(region)
		if not region then
			return false
		end
		local ok, shown = pcall(region.IsShown, region)
		return ok and not Secret(shown) and shown == true
	end

	-- one of the game's own marks in the top-left corner (the reagent's
	-- badge read from the button each time: the game makes it late)
	local function CornerTaken(st)
		local b = st.button
		return Shown(b.JunkIcon) or Shown(b.UpgradeIcon) or (st.bang and Shown(b.IconQuestTexture))
			or Shown(b.ProfessionQualityOverlay) or false
	end

	-- a slot the game dims: its context overlay shown in the dim mode (the
	-- search box, an item that does not fit the open window), not as the
	-- glow round an item it highlights (runeforging); the game's own reader
	-- of the mode, where there is one. An older client's searchOverlay
	local function Dimmed(button)
		if Shown(button.ItemContextOverlay) then
			local read = button.GetItemContextOverlayMode
			local match = _G.ItemButtonConstants and _G.ItemButtonConstants.ContextMatch
			local standard = match and match.Standard
			if type(read) ~= "function" or standard == nil then
				return true   -- (no mode on this client: the overlay is the dim)
			end
			local ok, mode = pcall(read, button)
			return ok and not Secret(mode) and mode == standard
		end
		return Shown(button.searchOverlay)
	end

	-- its size (of the button's) and level (over the button's children):
	-- when made, when the slot's kit comes on and when the switch does (the
	-- button keeps both for the session: not read again on every update)
	local function Fit(st, gem)
		local b = st.button
		local okW, w = pcall(b.GetWidth, b)
		w = okW and Finite(w) or nil
		gem:SetGemSize(w and w > 0 and math.floor(w * SIZE + 0.5) or 14)
		local okL, level = pcall(b.GetFrameLevel, b)
		level = okL and Num(level) or nil
		if level and level + 2 ~= st.level then
			st.level = level + 2
			gem:SetFrameLevel(level + 2)
		end
	end

	-- the reagent badge's own shows and hides (the Professions window's, for
	-- crafted gear): a gem shown moved (below, with the other hooks)
	local Gem_OnBadge

	-- its corner (the top-right one while the game's own mark takes the
	-- top-left) and its alpha (a slot the game dims)
	local function Marks(st, gem)
		local button = st.button
		-- the reagent's badge, heard from the first time the gem meets it
		local badge = button.ProfessionQualityOverlay
		if badge and not gemOfBadge[badge] and badge.SetShown then
			gemOfBadge[badge] = st
			hooksecurefunc(badge, "SetShown", Gem_OnBadge)
		end
		local aside = CornerTaken(st)
		if aside ~= st.aside then
			st.aside = aside
			local icon = st.icon or button
			gem:ClearAllPoints()
			if aside then
				gem:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -INSET, -INSET)
			else
				gem:SetPoint("TOPLEFT", icon, "TOPLEFT", INSET, -INSET)
			end
		end
		local dim = Dimmed(button)
		if dim ~= st.dim then
			st.dim = dim
			gem:SetAlpha(dim and DIM or 1)
		end
	end

	-- the slot's gem as the game's slot now is: shown in its quality's colour
	-- (made the first time), or hidden; `refit`: its size and level again
	local function Sync(st, refit)
		local q = st.on and st.q or nil
		local r, g, b = nil, nil, nil
		if q and Wanted() then
			r, g, b = Colour(q)
		end
		local gem = st.gem
		if not r then
			if gem then
				gem:Hide()
			end
			return
		end
		if not gem then
			local QI = MelloUI.QuestInk
			if not (QI and QI.Gem) then
				return
			end
			gem = QI.Gem(st.button)
			st.gem = gem
			made = made + 1
			refit = true
		end
		if refit then
			Fit(st, gem)
		end
		Marks(st, gem)
		gem:SetColour(r, g, b)
	end

	-- the game's own updates of a dressed slot (one handler each for every
	-- slot, no closure of their own)
	local Gem_OnQuality = Shared("SetItemButtonQuality on a kit item slot", function(button, quality)
		local st = gemOf[button]
		if st then
			st.q = Num(quality)
			Sync(st)
			Grey(st)
		end
	end)
	-- the game's own grey on a slot (a picked-up item's): a junk one stays grey
	local Junk_OnDesaturated = Shared("SetItemButtonDesaturated on a kit item slot (junk)", function(button)
		local st = gemOf[button]
		if st and st.grey then
			st.icon:SetDesaturated(true)
		end
	end)
	-- the corner's marks and the search's shade: a gem shown moved or dimmed
	-- (none shown: nothing to do; the next quality update places it)
	local Gem_OnMarks = Shared("the corner and search marks on a kit item slot", function(button)
		local st = gemOf[button]
		local gem = st and st.gem
		if gem and gem:IsShown() then
			Marks(st, gem)
		end
	end)
	Gem_OnBadge = Shared("SetShown on a kit item slot's reagent quality badge", function(region)
		local st = gemOfBadge[region]
		local gem = st and st.gem
		if gem and gem:IsShown() then
			Marks(st, gem)
		end
	end)
	local Gem_OnQuestArt = Shared("SetTexture on a kit item slot's quest mark", function(region, art)
		local st = gemOfArt[region]
		if st then
			local bang = _G.TEXTURE_ITEM_QUEST_BANG
			st.bang = bang ~= nil and Text(art) == bang
		end
	end)

	function Kit:ItemGem(button, rep, read)
		if not (button and rep and button.SetItemButtonQuality) or gemOf[button] then
			return
		end
		local st = { button = button, icon = button.icon, on = false }
		gemOf[button] = st
		slots[#slots + 1] = st
		hooksecurefunc(button, "SetItemButtonQuality", Gem_OnQuality)
		if not desatHooked and type(_G.SetItemButtonDesaturated) == "function" then
			desatHooked = true
			hooksecurefunc("SetItemButtonDesaturated", Junk_OnDesaturated)
		end
		-- (the search's shade, called last in each window's update of a slot:
		-- the corner's marks are set by then)
		local dim = (button.UpdateItemContextOverlay and "UpdateItemContextOverlay") or (button.SetMatchesSearch and "SetMatchesSearch")
		if dim then
			hooksecurefunc(button, dim, Gem_OnMarks)
		end
		local quest = button.IconQuestTexture
		if quest and quest.SetTexture then
			gemOfArt[quest] = st
			hooksecurefunc(quest, "SetTexture", Gem_OnQuestArt)
		end
		-- what the game gave the slot before it was dressed
		if type(read) == "function" then
			local ok, q, bang = pcall(read, button)
			if ok then
				st.q = Num(q)
				st.bang = not Secret(bang) and bang == true
			end
		end
		-- shown with the slot's kit only
		local enable, disable = rep.onEnable, rep.onDisable
		rep.onEnable = function(...)
			if enable then
				enable(...)
			end
			st.on = true
			Sync(st, true)
			Grey(st)
		end
		rep.onDisable = function(...)
			if disable then
				disable(...)
			end
			st.on = false
			Sync(st)
			Grey(st)
		end
	end

	-- the switch read again (Quality Gems changed, a profile loaded): every
	-- slot at once, nothing made while it is off
	function Kit:SyncItemGems()
		wanted, junkWanted = nil, nil
		local on = Wanted()
		for i = 1, #slots do
			local st = slots[i]
			if on then
				Sync(st, true)
			elseif st.gem then
				st.gem:Hide()
			end
			Grey(st)
		end
	end

	function Kit:ItemGemCounts()
		local shown = 0
		for i = 1, #slots do
			local gem = slots[i].gem
			if gem and gem:IsShown() then
				shown = shown + 1
			end
		end
		return #slots, made, shown
	end

	-- (a profile load writes the settings past 'setting', then says
	-- 'restart'; nothing read yet: nothing to follow)
	local OnSetting = Shared("'setting' on the bus: the quality gems", function(name, key)
		if name == SWITCH_MODULE and (key == SWITCH_KEY or key == JUNK_KEY) then
			Kit:SyncItemGems()
		end
	end)
	local OnRestart = Shared("'restart' on the bus: the quality gems", function()
		if wanted ~= nil or junkWanted ~= nil then
			Kit:SyncItemGems()
		end
	end)
	if MelloUI.On then
		MelloUI:On("setting", OnSetting, "Kit quality gems")
		MelloUI:On("restart", OnRestart, "Kit quality gems")
	end
end

--------------------------------------------------------------------------------
-- The looks a button can take, shared by every panel that offers them (the
-- action bars, micro menu and bag bar in Action Bars Kit, the bag windows'
-- slots in Backpack Kit) and by the Configurator's picture rows.
--   borders:      Button Border (a dropdown's values; `piece` the preview)
--   backgrounds:  Button / Backdrop Background ("dark" a flat fill, "none" nothing)
--   rimRule / rimKind: a border's slot rule and its rim piece family
--------------------------------------------------------------------------------

Kit.buttonLooks = {
	borders = {
		{ value = "thin", label = "Thin iron", piece = "buttons/rim_normal" },
		{ value = "hairline", label = "Hairline", piece = "buttons/rimhair_normal" },
		{ value = "rounded", label = "Rounded corners", piece = "buttons/rimround_normal" },
		{ value = "gold", label = "Iron with gold line", piece = "buttons/rimgold_normal" },
		{ value = "sunk", label = "Sunk", piece = "buttons/rimsunk_normal" },
		-- (0.19.8) the border library's own styles (Modules/KitBorders.lua),
		-- drawn by it where the rim stands: no slot rim of their own
		{ value = "single", label = "Single rail", style = "single" },
		{ value = "backdrop", label = "Backdrop", style = "backdrop", piece = "borders/backdrop" },
		-- (the NewUI2 rims the user picked: Tools/make_newui2_borders.py)
		{ value = "n4", label = "Medium iron, corner studs", style = "n4", piece = "borders/n4" },
		{ value = "n4g", label = "Thin gold, corner studs", style = "n4g", piece = "borders/n4g" },
		{ value = "n5", label = "Hairline, corner nubs", style = "n5", piece = "borders/n5" },
		{ value = "n1", label = "Heavy bevel, corner studs", style = "n1", piece = "borders/n1" },
		-- (0.20.1, the RPG pack's frame with its trough: Tools/make_rpg_frames.py)
		{ value = "rpg", label = "Stone rail", style = "rpg", piece = "borders/rpg" },
	},
	backgrounds = {
		{ value = "stone", label = "Stone", piece = "tiles/stone" },
		{ value = "concrete", label = "Cracked concrete", piece = "tiles/concrete" },
		{ value = "ironplate", label = "Iron plate", piece = "tiles/ironplate" },
		{ value = "parchment", label = "Parchment", piece = "parchment/sheet_body", paper = true },   -- (0.20.1: the RPG pack's paper, Tools/make_parchment.py)
		{ value = "leather", label = "Leather", piece = "tiles/quilt_brown" },
		-- (0.19.8, the NewUI2 textures the user picked: Tools/make_newui2_borders.py)
		{ value = "brushedmetal", label = "Brushed dark metal", piece = "tiles/brushedmetal" },
		{ value = "agedparchment", label = "Aged parchment", piece = "tiles/agedparchment", paper = true },
		{ value = "dark", label = "Dark" },
		-- (0.20.1, the user: the RPG pack's dark panel gradient, "scaleable and reusable": Tools/make_rpg_gradient.py;
		-- no tile, laid over the whole rect)
		{ value = "gradient", label = "Dark gradient", piece = "backdrops/gradient_dark" },
		{ value = "radial", label = "Dark round gradient", piece = "backdrops/gradient_radial" },   -- (0.20.1: the pack's slot boxes')
		{ value = "none", label = "None" },
	},
	-- a progress bar's bracket (a bar replacement's `bar`): the ornate P1,
	-- the cast bar's, or the thin rims made into bars (Tools/build_kit.py
	-- thin_bar); `piece` the preview's middle
	barBorders = {
		{ value = "frame", label = "Ornate", bar = "frame" },
		{ value = "castbar", label = "Cast bar", bar = "castbar" },
		{ value = "rim", label = "Thin iron", bar = "rim" },
		{ value = "rimhair", label = "Hairline", bar = "rimhair" },
		{ value = "rimround", label = "Rounded", bar = "rimround" },
		{ value = "rimgold", label = "Iron with gold line", bar = "rimgold" },
		{ value = "rimsunk", label = "Sunk", bar = "rimsunk" },
		-- (0.19.8, the border library's stage 2: Modules/KitBorders.lua) drawn
		-- by it round the bar, the bracket put out
		{ value = "single", label = "Single rail", style = "single" },
		{ value = "backdrop", label = "Backdrop", style = "backdrop" },
		{ value = "n4", label = "Medium iron, corner studs", style = "n4" },
		{ value = "n4g", label = "Thin gold, corner studs", style = "n4g" },
		{ value = "n5", label = "Hairline, corner nubs", style = "n5" },
		{ value = "n1", label = "Heavy bevel, corner studs", style = "n1" },
		{ value = "rpg", label = "Stone rail", style = "rpg" },   -- (0.20.1: its trough the bar's ground)
	},
	rimRule = { thin = "ActionButtonRim", hairline = "ActionButtonRimHairline", rounded = "ActionButtonRimRounded",
		gold = "ActionButtonRimGold", sunk = "ActionButtonRimSunk" },
	rimKind = { thin = "rim", hairline = "rimhair", rounded = "rimround", gold = "rimgold", sunk = "rimsunk" },
	borderDesc = "The rim on each button: a thin iron rim, a hairline, rounded corners, iron with a gold line round the icon, "
		.. "or sunk (a soft shadow inside the rim). Each lights up under the mouse and turns gold when checked.",
}
Kit.buttonLooks.backgroundPiece = {}
Kit.buttonLooks.backgroundPaper = {}
for _, v in ipairs(Kit.buttonLooks.backgrounds) do
	Kit.buttonLooks.backgroundPiece[v.value] = v.piece
	Kit.buttonLooks.backgroundPaper[v.value] = v.paper or nil
end

-- A background that is paper (0.19.8: the parchment, the aged parchment):
-- the text on it is dark ink (the parchment ink rule, QuestInk.lua), and a
-- window that has its own parchment choice does not offer it
function Kit:BackgroundIsPaper(value)
	return self.buttonLooks.backgroundPaper[value] == true
end

-- A Button Border's slot rule (for Kit:SkinActionButton's `as`); without a
-- style, the one every window's buttons wear (UI Modifications' Button Border)
function Kit:ButtonRimRule(style)
	local looks = self.buttonLooks
	style = style or (self.BorderValue and self:BorderValue("button"))
	return looks.rimRule[style] or looks.rimRule.thin
end

-- A new Button Border on a skinned button (its rim's art swapped live)
function Kit:SetButtonBorder(button, style)
	-- (0.19.8) a style of the border library's: drawn by it where the rim
	-- stands, the rim put out (Modules/KitBorders.lua); another style puts
	-- such a border away and swaps the rim's art as before
	if self.ButtonLibraryBorder and self:ButtonLibraryBorder(button, style) then
		return
	end
	local kind = self.buttonLooks.rimKind[style]
	local rep = button and Kit.repOf[button]
	if kind and rep and rep.object and rep.object.base then
		self:SetSlotBase(rep.object, "buttons/" .. kind)
	end
end

-- A button's background: the texture in its opening where it shows no icon
-- (an action / bag / item slot's empty backing, Kit.slotStoneOf; a micro
-- button's stone under its glyph, Kit.glyphStoneOf)
function Kit:SetButtonBackground(button, value)
	local tex = button and ((Kit.slotStoneOf[button] and Kit.slotStoneOf[button].tex) or Kit.glyphStoneOf[button])
	if not tex then
		return
	end
	local piece = self.buttonLooks.backgroundPiece[value]
	if piece then
		if Kit.pieceNameOf[tex] ~= piece then
			self:Unpaint(tex)   -- (the dark fill's palette colour no longer on it)
			self:Apply(tex, piece)
		end
		self:Retile(tex)
		tex:SetAlpha(1)
	elseif value == "dark" then
		-- the palette's inner panel, by its key (a new palette paints it again)
		self:Paint(tex, "innerPanel", "fill", 0.88)
		-- still ours: a plain mark, no piece
		Kit.pieceOf[tex], Kit.pieceNameOf[tex] = true, nil
		tex:SetAlpha(1)
	else
		tex:SetAlpha(0)   -- none: the game shows it with the empty slot; it stays see-through
	end
end

-- The layer above a status bar's fill for its bracket, and the one below it
-- for the trough (a unit frame's health fill draws at BACKGROUND, its power
-- bar and a cast bar at ARTWORK — no drawLayer in their XML — their texts at
-- OVERLAY 1). Secret-safe.
-- `strict`: nil when the fill's layer cannot be read (a secret string on the
-- target side's bars), for a caller that would rather leave things as they
-- are than guess (the relayer).
local function DrawLayerOf(tex)
	return tex:GetDrawLayer()
end

function Kit:BracketLayers(bar, strict)
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	-- no closure per call: the relayer asks on every SetStatusBarTexture,
	-- dozens of times a second on some bars
	local ok, layer = false, nil
	if tex then
		ok, layer = pcall(DrawLayerOf, tex)
	end
	if not ok or type(layer) ~= "string" or Secret(layer) then
		if strict then
			return nil
		end
		layer = "BACKGROUND"
	end
	if layer == "ARTWORK" then
		return "OVERLAY", 0, "BORDER", 0
	elseif layer == "BORDER" then
		return "ARTWORK", 1, "BACKGROUND", 7
	elseif layer == "OVERLAY" then
		return "OVERLAY", 7, "ARTWORK", 7
	end
	return "BORDER", 1, "BACKGROUND", -1
end

-- Alpha 0 that survives the game's own SetAlpha / Show calls (shared by the
-- panel modules so one registry knows what is faded).
Kit.faded = {}
local FADED = Kit.faded

-- The two hooks on every faded region, one handler each for all of them:
-- whether a region is faded is read from Kit.faded when the game calls.
-- Some faded art is re-set by the game every frame (the player frame's
-- resting / combat glow pulses its alpha from the frame's OnUpdate while it
-- is shown, wherever it is parked): kept to a lookup and one call. Our own
-- SetAlpha(0) comes straight back through here and stops at the test; a
-- secret alpha cannot be compared: faded again
local Faded_OnSetAlpha = Shared("SetAlpha on faded art", function(o, a)
	if FADED[o] and (Secret(a) or a ~= 0) then
		WriteBack("Kit: faded art's alpha put back to 0")
		o:SetAlpha(0)
	end
end)
-- a vertex colour with an alpha (UnitSelectionColor's fourth value on a
-- reaction band) resets the region's alpha on this client
local Faded_OnSetVertexColor = Shared("SetVertexColor on faded art", function(o)
	if FADED[o] then
		o:SetAlpha(0)
	end
end)

function Kit:Fade(obj)
	if not obj or self.faded[obj] then
		return
	end
	self.faded[obj] = true
	obj:SetAlpha(0)
	if not Kit.fadeHooked[obj] then
		Kit.fadeHooked[obj] = true
		hooksecurefunc(obj, "SetAlpha", Faded_OnSetAlpha)
		if obj.SetVertexColor then
			hooksecurefunc(obj, "SetVertexColor", Faded_OnSetVertexColor)
		end
	end
end

function Kit:Unfade(obj)
	if obj and self.faded[obj] then
		self.faded[obj] = nil
		obj:SetAlpha(1)
	end
end

-- The name the library keys on: the region's atlas, else its texture file's
-- base name. Secret values (this client) read as unknown.
function Kit:ArtKey(region)
	if not region or not region.GetAtlas then
		return nil
	end
	local ok, atlas = pcall(region.GetAtlas, region)
	if ok and atlas and not (issecretvalue and issecretvalue(atlas)) and atlas ~= "" then
		return atlas
	end
	local okT, tex = pcall(region.GetTexture, region)
	if okT and tex and not (issecretvalue and issecretvalue(tex)) and type(tex) == "string" then
		return tex:match("([^\\/]+)$")
	end
	return nil
end

local ReplacementMixin = {}

-- The holder frame a replacement is drawn on: on its rect, `lvl` levels over
-- its parent's, never part of a layout frame's size. `strata`: Kit:Replace's
-- opts.strata.
local function MakeHolder(parent, rect, lvl, strata)
	local f = CreateFrame("Frame", nil, parent)
	-- never part of the parent's size: a layout frame (an action bar, a
	-- ResizeLayoutFrame) grows round its shown children, and a holder on
	-- a rect past its content would make it grow (user, 2026-09-23: Action
	-- Bar 1 swelling in Edit Mode with the backdrop)
	f.ignoreInLayout = true
	-- opts.strata: a holder below everything at the parent's strata (the
	-- main bar's end caps under every bar and the status bars)
	if strata then
		f:SetFrameStrata(strata)
		-- kept there when its parent is raised (the game lifts the action
		-- bars to TOOLTIP while a spell is dragged: a holder that followed
		-- would come over the buttons)
		if f.SetFixedFrameStrata then
			f:SetFixedFrameStrata(true)
		end
	end
	f:SetFrameLevel(math.max(parent:GetFrameLevel() + lvl, 0))
	f:EnableMouse(false)
	f:SetAllPoints(rect)
	return f
end

-- A 'fade' draws nothing, and its holder was an empty frame per faded
-- region (user, 2026-09-24: every bag slot's picture, every spell card's and
-- header's backplate): its rep has no frame until something asks for
-- rep.object (a panel hanging a parchment sheet on it, a dump). The holder is
-- then made as Kit:Replace made it, shown or hidden as the rep is; until
-- then the rep keeps that itself (`holderShown`).
local BareRep = {
	__index = function(rep, key)
		if key ~= "object" then
			return nil
		end
		local f = MakeHolder(rawget(rep, "holderParent"), rawget(rep, "rect"), rawget(rep, "holderLevel"), rawget(rep, "holderStrata"))
		if not rawget(rep, "holderShown") then
			f:Hide()
		end
		rawset(rep, "object", f)
		return f
	end,
}

-- A rep whose skin waits for its first show (a panel tab's open card, Kit:
-- SkinPanelTab) laid now, the editor's tune on it as on every rep
local function LayRep(rep)
	local skin = rep.skin
	if not (skin and skin.pendingArt) then
		return
	end
	local holder = rawget(rep, "object")
	if holder and holder.kitWaiting then
		holder.kitWaiting = nil
		Perf.SetScript(holder, "OnUpdate", nil)
	end
	NineSlice_Lay(skin)
	if rep.tune then
		Kit:TuneObject(rep, rep.tune)
	end
end

-- ... and a waiting card whose holder is on screen without it (shown by an
-- Enable that no sync to the game's art followed): laid in that frame's
-- update, before it is drawn, as it would have shown. A hidden holder gets
-- no OnUpdate, so the cards that wait cost nothing here.
local Waiting_OnUpdate = Shared("OnUpdate on a waiting kit card", function(f)
	LayRep(f.kitWaiting)
end, "update")

-- Fade the game art, show ours.
function ReplacementMixin:Enable()
	if not self.noFade then
		Kit:Fade(self.region)
	end
	for _, extra in ipairs(self.alsoFade) do
		Kit:Fade(extra)
	end
	-- (a fade's holder only once asked for; a waiting card laid when the
	-- art it stands for is shown)
	local object = rawget(self, "object")
	if object then
		local wait = self.layWith
		if wait and self.skin.pendingArt and wait:IsShown() then
			LayRep(self)
		end
		object:Show()
		-- a rim or state texture read again: its button's active look (its
		-- regions, not the rim's) follows it back on (Kit:SetActive); a flat
		-- control's driver likewise (the "flat" kind)
		if object.Update == Slot_Update then
			Slot_Update(object)
		end
		if self.flatDriver then
			Slot_Update(self.flatDriver)
		end
	else
		self.holderShown = true
	end
	if self.backing then
		self.backing:Show()
	end
	-- its shadow partners drawn by another frame (Kit:Shadow's rep)
	Kit:ShadowRepOn(self, true)
	self:Refit()
	if self.checked then
		self:SetState()
	end
	if self.onEnable then
		self.onEnable(self)
	end
end

-- Show the game art again, hide ours.
function ReplacementMixin:Disable()
	if not self.noFade then
		Kit:Unfade(self.region)
	end
	for _, extra in ipairs(self.alsoFade) do
		Kit:Unfade(extra)
	end
	local object = rawget(self, "object")
	if object then
		object:Hide()
	else
		self.holderShown = false
	end
	if self.backing then
		self.backing:Hide()
	end
	if object and object.glow then
		object.glow:Hide()
	end
	-- a rim's active look is regions of its button: off with the rim (one
	-- that drives it: a hover-only rim leaves a row's plate its look)
	if object and object.Update == Slot_Update and Kit:RimDrivesLook(object) then
		Kit:SetActive(object.button, false)
	end
	local driver = self.flatDriver
	if driver and Kit:RimDrivesLook(driver) then
		Kit:SetActive(driver.button, false)
	end
	Kit:ShadowRepOn(self, false)
	if self.onDisable then
		self.onDisable(self)
	end
end

-- The rect's height / width, or nil when unreadable (secret). With the editing
-- tools' proxy in front of the element, measured from the ELEMENT plus the
-- proxy's padding: a proxy made this frame reads 0 x 0 until the next layout
-- pass, so a bar bracket and the fill fitted into its opening were sized from
-- two different heights and the fill spilled past the rails (user, 2026-09-23:
-- the skill / reputation bars, only while the editor addon was installed).
function ReplacementMixin:RectSize(method)
	local target, pad = self.rect, 0
	if self.proxy and self.proxyOf then
		target = self.proxyOf
		local tune = self.tune
		if tune then
			if method == "GetHeight" then
				pad = (tune.padT or 0) + (tune.padB or 0)
			else
				pad = (tune.padL or 0) + (tune.padR or 0)
			end
		end
	end
	local ok, v = pcall(target[method], target)
	if not ok or Secret(v) or v == nil then
		return nil
	end
	return v + pad
end

-- Re-fit to the rectangle (rows get their height after layout), or to the
-- fit height when one is set: the strip spans the rect's width and its
-- opaque part is exactly that tall, centred on the rect's centre line.
function ReplacementMixin:Refit()
	if not (self.strip and self.rect) then
		return
	end
	if self.rule.natural then
		-- the kit size, centred on the rect, spanning widthFrac of its width
		local mid = PIECES[StripName(self.strip.base, "mid", self.strip.state)]
		local boxH = mid and mid.box and (mid.box[4] - mid.box[2]) or (mid and mid.h) or 0
		local yoff = self.strip:FitBox(boxH * Kit.scale)
		local w = (self:RectSize("GetWidth") or 0) * (self.rule.widthFrac or 1)
		self.strip:ClearAllPoints()
		self.strip:SetPoint("CENTER", self.rect, "CENTER", 0, yoff)
		self.strip:SetSize(math.max(w, 1), self.strip.height)
		return
	end
	local h = self.fitHeight
	if not (h and h > 0) then
		h = self:RectSize("GetHeight")
		if not h then
			return
		end
	end
	if not (h and h > 0) then
		return
	end
	h = h * (self.rule.heightScale or 1)
	local yoff = self.strip:FitBox(h)
	self.strip:ClearAllPoints()
	-- `capOverhang`: the caps may reach that fraction of their width past
	-- the rect's edges (a gemmed button plate on a short button: the gems
	-- stand outside, as the game's own Left / Right button pieces do)
	local over = 0
	if self.rule.capOverhang then
		over = (self.strip.wl or 0) * self.rule.capOverhang
	end
	-- `widthScale`: the plate wider than its rect by that factor, centred
	-- (the minimap's zone band at 1.4 — user, 2026-09-21)
	if self.rule.widthScale then
		local w0 = self:RectSize("GetWidth")
		if w0 and w0 > 0 then
			over = over + w0 * (self.rule.widthScale - 1) / 2
		end
	end
	local overL = self.strip.dropCap == "l" and 0 or over
	local overR = self.strip.dropCap == "r" and 0 or over
	self.strip:SetPoint("LEFT", self.rect, "LEFT", -overL, yoff)
	self.strip:SetPoint("RIGHT", self.rect, "RIGHT", overR, yoff)
	self.strip:SetHeight(self.strip.height)
	local w = self:RectSize("GetWidth")
	if not (w and w > 0) then
		w = self.fitWidth or 0
	end
	self.strip:FitCaps(w + overL + overR)
end

function ReplacementMixin:SetFitHeight(h)
	if h and h > 0 and h ~= self.fitHeight then
		self.fitHeight = h
		self:Refit()
	end
end

function ReplacementMixin:SetState(state)
	if self.kind == "picture" then
		self:Refit()
	elseif self.vstrip then
		local b = self.button
		if not state and b then
			-- ButtonStateBehaviorMixin keeps `over` / `down` on the button
			state = Kit:ResolveState(self.vstrip.base .. "_mid", b.over, b.down, nil, b.IsEnabled and not b:IsEnabled())
		end
		self.vstrip:SetState(state or Kit:FirstState(self.vstrip.base, "mid"))
	elseif self.flatDriver then
		-- (a flat control reads its state from its button; a given state is
		-- the edit field's lit edge: "focused" / "normal", a binding button)
		if state then
			self.flatDriver.flatFocus = (state == "focused") or nil
		end
		Slot_Update(self.flatDriver)
	elseif self.strip then
		self.strip:SetState(state)
	elseif self.skin and self.Update then
		self.Update()
	elseif self.skin and self.checked then
		local tint = self.rule.checkedTint
		local on = self.checked() and true or false
		if tint and on then
			self.skin:SetTint(tint[1], tint[2], tint[3])
		else
			self.skin:SetTint(1, 1, 1)
		end
		-- the selected row's active look (Kit:SetActive), round its card
		Kit:SetActive(self.skin, on, self.skin, "rect")
	else
		local object = rawget(self, "object")
		if object and object.Update then
			object:Update()
		end
	end
end

function ReplacementMixin:SetShown(shown)
	-- (its shadow partners on other frames with its holder)
	Kit:ShadowRepOn(self, shown)
	local object = rawget(self, "object")
	if not object then
		self.holderShown = shown and true or false
		return
	end
	if shown and self.skin and self.skin.pendingArt then
		LayRep(self)
	end
	object:SetShown(shown)
end

-- Replace one game region (or frame) with the kit piece the library maps it
-- to. opts:
--   as        rule key when the region's art can't be read (or is a frame)
--   parent    the frame to parent to (default: the region's own frame; pass
--             another when that frame is faded, since alpha inherits)
--   rect      the rectangle to cover (default: the region)
--   button    the button for slot / state kinds
--   pitch     { x, y } distance between neighbouring slots: a slot rim with a
--             gemSpan rule is sized so neighbours share a corner gem
--   fitHeight a strip's height, when it should be the distance between
--             neighbouring rows (the rows' pitch) rather than the art's rect;
--             rep:SetFitHeight(h) changes it later
--   checked   function() -> true for the checked / selected state
--   state     the strip's first state
--   center    for `square` / `natural` pieces: the region to centre on;
--             centerPoint the point of it (default "CENTER")
--   alsoFade  other regions the piece stands in for (a row's side pieces)
--   noFade    the piece stands in for nothing (an agreed addition): the
--             region is only the rect / parent, it is not faded
--   level     frame level relative to the parent (overrides the rule)
--   skip      frame kind: gem corners to leave out ("tl" under a portrait ring)
--   grey      picture kind: function() -> true while the greyscale twin shows
--   button    strip kind: the plate follows this button's hover / pressed / disabled
--   edit      strip kind: the plate shows its focused look while this edit box has focus
--   capless   strip kind: the middle alone, never the caps
--   dropCap   strip kind: one cap left out ("l" / "r"), the middle to that edge
--   icon      slot kind: the button's icon texture, fitted into the rim's opening
-- Returns the replacement, or nil and the key that had no rule.
-- The rule for an art key. The client hands atlas names back in their
-- canonical case ("UI-QuestTrackerButton-Collapse-All" for the XML's
-- "ui-questtrackerbutton-collapse-all"), so a miss is retried ignoring case
-- (an index built once from the table).
local LOWER_RULES = nil
local function BaseRule(key)
	local rule = Kit.Replacements[key]
	if rule then
		return rule
	end
	if not LOWER_RULES then
		LOWER_RULES = {}
		for k, v in pairs(Kit.Replacements) do
			LOWER_RULES[k:lower()] = v
		end
	end
	return LOWER_RULES[key:lower()]
end

-- The rule an element key is drawn by, with the editing tools' overrides
-- (Core\KitTuning.lua) merged on top. A tuned rule is built once per tuning
-- change and cached; an untuned key hands back the library's own table.
local tunedRules = { serial = -1 }

function Kit:RuleFor(key)
	if not key then
		return nil
	end
	if key == "NineSlicePanelTemplate" or key == "TitleBar" then
		self:SyncWindowLookOnce()
	elseif (key == "UI-HUD-UnitFrame-SmallCircle" or key == "ui-hud-nameplates-levelindicator") and self.OrbLook then
		-- (0.20.1) the level orb in the look chosen (Level Orb, KitBorders.lua)
		self.Replacements[key].piece = self:OrbLook().piece
	end
	local base = BaseRule(key)
	local KT = MelloUI.KitTuning
	if not KT then
		return base
	end
	if tunedRules.serial ~= KT.serial then
		tunedRules = { serial = KT.serial }
	end
	local cached = tunedRules[key]
	if cached ~= nil then
		return cached or base
	end
	local over = KT:Rule(key)
	if not over or not next(over) then
		tunedRules[key] = false
		return base
	end
	local merged = base and KT:Copy(base) or {}
	KT:Merge(merged, over)
	-- an override may INVENT a rule for an element the library never mapped,
	-- but it has to say what kind of piece to draw
	if not merged.kind then
		tunedRules[key] = false
		return base
	end
	merged.tuned = true
	tunedRules[key] = merged
	return merged
end

--------------------------------------------------------------------------------
-- Tuning (the editing tools' overrides; see Core\KitTuning.lua)
--
-- Nothing here runs unless a tuning table carries something: with an empty
-- one every function below is a no-op and the kit behaves as it always has.
--------------------------------------------------------------------------------

-- `liveEdit` is switched on by the companion editor addon while it is
-- installed: every replacement then gets a proxy rectangle the editor can
-- drag, instead of only those that already carry an offset.
Kit.liveEdit = false

local GONE = {}                 -- "this field did not exist before the override"
local pieceBackup = {}          -- [piece name] = { field = original value }
local invented = {}             -- [piece name] = true: a piece the layout lacks, made by the tuning
local WHOLE = { 0, 1, 0, 1 }    -- a whole file, as a uv

-- The shipped textures (user, 2026-09-24: "textures look good", option (d)):
-- Tools/texture_pack.py ship packs the small pieces of each look into atlas
-- sheets (Media\<look>\atlas\...) and gives some pieces a smaller file.
-- KitLayout.lua then names the sheet as such a piece's `file`, its
-- rectangle there as its `uv`, and keeps `was`: its uv in its own former
-- file (file = its name), the frame build_kit.py wrote and the kit tools
-- write a `pieces` uv or file override in. Everything that draws a piece
-- reads file + uv (Kit:Apply) and crops or mirrors inside that uv, so it
-- draws the piece's rectangle of the sheet; an override is mapped from the
-- `was` frame into that rectangle here.
local function InSheet(file)
	return type(file) == "string" and file:find("^atlas\\") ~= nil
end

-- `uv` (left, right, top, bottom in the `was` frame) into `rect` (the
-- piece's rectangle now); a value past the piece is held at its edge (in a
-- sheet the neighbouring pieces lie there)
local function MapInto(uv, was, rect)
	local out = {}
	for i = 1, 4 do
		local lo, hi = (i <= 2) and 1 or 3, (i <= 2) and 2 or 4
		local span = was[hi] - was[lo]
		local f = span > 0 and (uv[i] - was[lo]) / span or 0
		if f < 0 then
			f = 0
		elseif f > 1 then
			f = 1
		end
		out[i] = rect[lo] + f * (rect[hi] - rect[lo])
	end
	return out
end

local LAYOUT_FIELDS = { "file", "uv", "was", "tile" }

-- A piece's values as the layout has them, whatever tuning has put into
-- PIECES since: a backed-up field's original, else the live field (one no
-- override has touched is still the layout's)
local function LayoutOf(name)
	local p = PIECES[name]
	if not p then
		return nil
	end
	local backup, out = pieceBackup[name], {}
	for _, field in ipairs(LAYOUT_FIELDS) do
		local value = p[field]
		if backup and backup[field] ~= nil then
			value = backup[field]
			if value == GONE then
				value = nil
			end
		end
		out[field] = value
	end
	return out
end

-- The piece a file override names ("buttons\\cog_hover"), also written in
-- another case or with its old extension (the files it named were found so)
local lowerNames = nil   -- [lower-case name] = the piece's name, made on a miss; emptied by Kit:ApplyTuning
local function PieceNamed(file)
	local name = file:gsub("\\", "/"):gsub("%.[Tt][Gg][Aa]$", ""):gsub("%.[Bb][Ll][Pp]$", "")
	if PIECES[name] then
		return name
	end
	if not lowerNames then
		lowerNames = {}
		for n in pairs(PIECES) do
			lowerNames[n:lower()] = n
		end
	end
	return lowerNames[name:lower()]
end

-- A tuned piece's uv / file override (copied into `p`) put where its art is
-- now. `base`: the piece's layout values. Returns the fields it changed.
local function RemapTunedPiece(p, over, base, NIL)
	local changed = {}
	local file = over.file ~= NIL and type(over.file) == "string" and over.file or nil
	local uv = over.uv ~= NIL and type(over.uv) == "table" and over.uv or nil
	-- the piece whose art the override means: the one its file names, else
	-- this piece (as the layout has them)
	local target = base
	if file ~= nil then
		local named = PieceNamed(file)
		target = named and LayoutOf(named) or nil
	end
	if file ~= nil or uv ~= nil then
		if target and target.was and target.uv then
			-- the art the override means has moved: its file now, the uv
			-- mapped from its former frame into its rectangle there
			-- (a piece the tuning invents may bring no uv: the whole piece)
			p.file = target.file
			p.uv = MapInto(uv or base.was or base.uv or target.was, target.was, target.uv)
			changed.file, changed.uv = true, true
		else
			if file ~= nil and target and file ~= target.file then
				-- a piece's own file in another case or with an extension:
				-- as the layout names it (it may ship as .blp or .tga)
				p.file = target.file
				changed.file = true
			end
			if file ~= nil and uv == nil and base.was then
				-- a file that was not moved, named for a piece that was: the
				-- piece's uv in its former file is what the override meant
				p.uv = { base.was[1], base.was[2], base.was[3], base.was[4] }
				changed.uv = true
			end
		end
	end
	-- a piece left without a uv (one the tuning invents, given only a file;
	-- an override that removes the uv) is drawn whole: the target's
	-- rectangle as the layout has it, else the whole file (Kit:Apply reads a
	-- uv for every piece)
	if p.uv == nil then
		local whole = target and target.uv or WHOLE
		p.uv = { whole[1], whole[2], whole[3], whole[4] }
		changed.uv = true
	end
	-- one piece cannot repeat inside a sheet (the ship never puts a tiling
	-- piece in one)
	if p.tile and InSheet(p.file) then
		p.tile = nil
		changed.tile = true
	end
	return changed
end

-- The frame a `pieces` uv / file override is written in (above): the
-- piece's own file (its name, for a piece the ship moved into a sheet) and
-- its uv there, as the layout has them whatever tuning did since; and
-- whether the piece is drawn from a sheet now (it cannot repeat there).
-- nil for a piece the kit does not know. The kit editor shows these.
function Kit:PieceFrame(name)
	local base = LayoutOf(name)
	if not base then
		return nil
	end
	local inSheet = InSheet(PIECES[name].file)
	if base.was then
		return (name:gsub("/", "\\")), base.was, inSheet
	end
	return base.file, base.uv, inSheet
end

-- Globals and painted-piece geometry, applied to the kit itself. Called by
-- MelloUI.KitTuning whenever the tuning changes: every pass starts each
-- piece tuned so far from its layout values again (its backup) before the
-- overrides go in, so the same tuning applied twice gives the same pieces
-- (a remapped uv never feeds the next mapping) and a field an override
-- stops carrying goes back to the layout's.
function Kit:ApplyTuning(KT)
	local g = KT:Globals()
	self.baseScale = self.baseScale or self.scale
	self.baseFrameScale = self.baseFrameScale or self.frameScale
	self.baseFramePrefix = self.baseFramePrefix or self.framePrefix
	self.scale = tonumber(g.scale) or self.baseScale
	self.frameScale = tonumber(g.frameScale) or self.baseFrameScale
	self.framePrefix = g.framePrefix or self.baseFramePrefix

	-- every piece tuned before back to what the layout says; the ones not
	-- tuned any more are done with (a piece the tuning made goes with it)
	local section = KT:Section("pieces")
	lowerNames = nil
	for name, backup in pairs(pieceBackup) do
		local p = PIECES[name]
		if p then
			for field, value in pairs(backup) do
				if value == GONE then
					p[field] = nil
				else
					p[field] = value
				end
			end
		end
		if not section[name] then
			pieceBackup[name] = nil
			if invented[name] then
				PIECES[name], invented[name] = nil, nil
			end
		end
	end
	for name, over in pairs(section) do
		local p = PIECES[name]
		if not p then
			p = { file = (name:gsub("/", "\\")) }
			PIECES[name] = p
			invented[name] = true
		end
		local backup = pieceBackup[name]
		if not backup then
			backup = {}
			pieceBackup[name] = backup
		end
		local base = LayoutOf(name)
		for field, value in pairs(over) do
			if backup[field] == nil then
				backup[field] = p[field] == nil and GONE or p[field]
			end
			if value == KT.NIL then
				p[field] = nil
			else
				p[field] = value
			end
		end
		for field in pairs(RemapTunedPiece(p, over, base, KT.NIL)) do
			if backup[field] == nil then
				backup[field] = base[field] == nil and GONE or base[field]
			end
		end
	end

	LOWER_RULES = nil
	tunedRules = { serial = -1 }
	resolved = {}
	-- a tuned rail piece keeps its family's skins in pieces (checked again)
	Slices.families, Slices.cuts = {}, {}
	self:RefreshTuning()
end

-- Every painted texture inside a replacement, whatever kind it is.
function Kit:Textures(rep)
	local out, seen = {}, {}
	local function add(tex)
		if tex and not seen[tex] and tex.SetVertexColor then
			seen[tex] = true
			out[#out + 1] = tex
		end
	end
	add(rep.tex)
	if rep.skin then
		for _, tex in ipairs(rep.skin.art or {}) do
			add(tex)
		end
		add(rep.skin.body)
	end
	for _, strip in ipairs({ rep.strip, rep.vstrip }) do
		if strip then
			add(strip.capL)
			add(strip.mid)
			add(strip.capR)
		end
	end
	local obj = rep.object
	if obj and obj.GetRegions and obj.GetObjectType and obj:GetObjectType() ~= "Texture" then
		local ok, regions = pcall(function() return { obj:GetRegions() } end)
		if ok then
			for _, region in ipairs(regions) do
				if region.GetObjectType and region:GetObjectType() == "Texture" then
					add(region)
				end
			end
		end
	end
	return out
end

-- One texture's look. Only what `tune` actually names is touched; a field
-- that was tuned and is not any more goes back to what the piece (or the
-- module that tinted it) said, so clearing a box in the editor undoes it
-- without a reload and without flattening a module's own colours.
-- (0.19.1) A texture of a window moved or resized by the kit editor (an element's `regions` entry: x, y, padL /
-- padR / padT / padB, Core/KitTuning.lua; user 2026-10-04, "move each individual thing on the windows"): against
-- the points it had when first tuned, taken again when its owner has laid it out anew since, so the same tuning
-- applied any number of times gives the same place. Weak tables: nothing is written on the texture.
LOOK.geomBase = setmetatable({}, { __mode = "k" })   -- [texture] = its own points { point, relative, relativePoint, x, y } (+ w, h)
LOOK.geomSet = setmetatable({}, { __mode = "k" })    -- [texture] = the points the tuning last set
LOOK.geomTune = setmetatable({}, { __mode = "k" })   -- [texture] = the tuning on it, for Kit:RefitRegion
LOOK.centeredOn = setmetatable({}, { __mode = "k" }) -- [texture] = the replacement centred on it (a portrait's ring)
function LOOK.Points(tex)
	local out = {}
	for i = 1, tex:GetNumPoints() do
		local point, relative, relativePoint, x, y = tex:GetPoint(i)
		if Secret(x) or Secret(y) then
			return nil
		end
		out[i] = { point, relative, relativePoint, x or 0, y or 0 }
	end
	return out
end
function LOOK.SamePoints(a, b)
	if not (a and b) or #a ~= #b then
		return false
	end
	for i = 1, #a do
		local p, q = a[i], b[i]
		if p[1] ~= q[1] or p[2] ~= q[2] or p[3] ~= q[3] or math.abs(p[4] - q[4]) > 0.01 or math.abs(p[5] - q[5]) > 0.01 then
			return false
		end
	end
	return true
end
function LOOK.TuneGeometry(tex, tune)
	local cur = LOOK.Points(tex)
	if not cur or #cur == 0 then
		return false
	end
	local base = LOOK.geomBase[tex]
	if not base or not LOOK.SamePoints(cur, LOOK.geomSet[tex]) then
		base = cur
		local ok, w, h = pcall(tex.GetSize, tex)
		if ok and not Secret(w) and not Secret(h) then
			base.w, base.h = w, h
		end
		LOOK.geomBase[tex] = base
	end
	local x, y = tune.x or 0, tune.y or 0
	local L, R, T, B = tune.padL or 0, tune.padR or 0, tune.padT or 0, tune.padB or 0
	local set = {}
	tex:ClearAllPoints()
	for i, p in ipairs(base) do
		local point = p[1]
		local px, py = p[4] + x, p[5] + y
		local centreX, centreY = not (point:find("LEFT") or point:find("RIGHT")), not (point:find("TOP") or point:find("BOTTOM"))
		-- a side's point moves with its side; one point alone keeps the box's middle in step with its growth
		if point:find("LEFT") then px = px - L elseif point:find("RIGHT") then px = px + R elseif #base == 1 and centreX then px = px + (R - L) / 2 end
		if point:find("TOP") then py = py + T elseif point:find("BOTTOM") then py = py - B elseif #base == 1 and centreY then py = py + (T - B) / 2 end
		tex:SetPoint(point, p[2], p[3], px, py)
		set[i] = { point, p[2], p[3], px, py }
	end
	if #base == 1 and base.w and base.h then
		tex:SetSize(math.max(1, base.w + L + R), math.max(1, base.h + T + B))
	end
	LOOK.geomSet[tex], LOOK.geomTune[tex] = set, tune
	return true
end
function LOOK.UntuneGeometry(tex)
	local base = LOOK.geomBase[tex]
	if base and LOOK.SamePoints(LOOK.Points(tex), LOOK.geomSet[tex]) then
		-- still where the tuning put it: back to its own points
		tex:ClearAllPoints()
		for _, p in ipairs(base) do
			tex:SetPoint(p[1], p[2], p[3], p[4], p[5])
		end
		if #base == 1 and base.w and base.h then
			tex:SetSize(base.w, base.h)
		end
	end
	LOOK.geomBase[tex], LOOK.geomSet[tex], LOOK.geomTune[tex] = nil, nil, nil
end

-- A window's texture tuned (Kit:TuneRegions; the kit editor's live drag): Kit:TuneTexture, and its place and size
-- (x, y, pad*; a replacement's own textures take their move from its rectangle instead, Kit:TuneObject).
-- A ring centred on the texture keeps its own place: the portrait moves under it (user, 2026-10-04).
function Kit:TuneRegion(tex, tune)
	self:TuneTexture(tex, tune)
	if tune and (tune.x or tune.y or tune.padL or tune.padR or tune.padT or tune.padB) then
		pcall(LOOK.TuneGeometry, tex, tune)
	elseif LOOK.geomBase[tex] then
		pcall(LOOK.UntuneGeometry, tex)
	end
	local ring = LOOK.centeredOn[tex]
	if ring and ring.tex then
		pcall(LOOK.CenterTune, ring, ring.tune)
	end
end

-- A texture its owner has just laid out again (a portrait fitted to its ring on every refresh): its tuning on the
-- new place, and the ring centred on it back where it was
function Kit:RefitRegion(tex)
	if not tex then
		return
	end
	local tune = LOOK.geomTune[tex]
	if tune then
		pcall(LOOK.TuneGeometry, tex, tune)
		local ring = LOOK.centeredOn[tex]
		if ring and ring.tex then
			pcall(LOOK.CenterTune, ring, ring.tune)
		end
	end
end

function Kit:TuneTexture(tex, tune)
	tune = tune or {}
	local had = Kit.tunedAt[tex] or nil
	local now = nil
	local function mark(field)
		now = now or {}
		now[field] = true
	end
	-- (Kit.pieceOf is `true` on a flat colour of ours: no piece to read)
	local piece = type(Kit.pieceOf[tex]) == "table" and Kit.pieceOf[tex] or nil
	-- the window of the file the art is cut from: the piece's uv, or under a
	-- texture of the tuning's own the piece's uv in its own former file
	-- (`was`: its rectangle in an atlas sheet means nothing on another file)
	local window = piece and piece.uv
	if tune.texture and piece and piece.was then
		window = piece.was
	end

	if tune.texture then
		if Kit.tunedArt[tex] == nil then
			Kit.tunedArt[tex] = (tex.GetTexture and tex:GetTexture()) or false
		end
		pcall(tex.SetTexture, tex, tune.texture)
		if piece and piece.was and not piece.tile then
			pcall(tex.SetTexCoord, tex, window[1], window[2], window[3], window[4])
		end
		mark("texture")
	elseif Kit.tunedArt[tex] ~= nil then
		if piece and Kit.pieceNameOf[tex] then
			self:Apply(tex, Kit.pieceNameOf[tex])
		elseif Kit.tunedArt[tex] then
			pcall(tex.SetTexture, tex, Kit.tunedArt[tex])
		end
		Kit.tunedArt[tex] = nil
	end

	local t = tune.tint
	if t then
		pcall(tex.SetVertexColor, tex, t[1] or 1, t[2] or 1, t[3] or 1, t[4])
		mark("tint")
	elseif had and had.tint then
		-- back to the tint whoever owns this texture last asked for
		local base = Kit.tintBaseOf[tex]
		pcall(tex.SetVertexColor, tex, base and base[1] or 1, base and base[2] or 1, base and base[3] or 1)
	end

	if tune.desat ~= nil then
		if tex.SetDesaturated then
			pcall(tex.SetDesaturated, tex, tune.desat and true or false)
		end
		mark("desat")
	elseif had and had.desat and tex.SetDesaturated then
		pcall(tex.SetDesaturated, tex, false)
	end

	if tune.blend then
		pcall(tex.SetBlendMode, tex, tune.blend)
		mark("blend")
	elseif had and had.blend then
		pcall(tex.SetBlendMode, tex, "BLEND")
	end

	if tune.layer then
		pcall(tex.SetDrawLayer, tex, tune.layer, tune.sublevel or 0)
		mark("layer")
	end

	if tune.texAlpha then
		pcall(tex.SetAlpha, tex, tune.texAlpha)
		mark("texAlpha")
	elseif had and had.texAlpha then
		pcall(tex.SetAlpha, tex, 1)
	end

	-- cropping and mirroring work on the piece's own uv window; a repeatable
	-- piece re-computes its uv from its size, so it is left alone
	if not (piece and piece.tile) then
		local cropping = tune.coord or tune.flipH or tune.flipV
		if cropping then
			local u1, u2, v1, v2 = 0, 1, 0, 1
			if window then
				u1, u2, v1, v2 = window[1], window[2], window[3], window[4]
			end
			local c = tune.coord
			if c then
				local c1, c2, c3, c4 = c[1] or 0, c[2] or 1, c[3] or 0, c[4] or 1
				-- a crop reaching past the piece (the editor allows -1..2) is
				-- held at its edge in an atlas sheet: the neighbouring pieces
				-- lie there
				if piece and not tune.texture and InSheet(piece.file) then
					c1, c2 = math.max(0, math.min(1, c1)), math.max(0, math.min(1, c2))
					c3, c4 = math.max(0, math.min(1, c3)), math.max(0, math.min(1, c4))
				end
				local du, dv = u2 - u1, v2 - v1
				u1, u2 = u1 + du * c1, u1 + du * c2
				v1, v2 = v1 + dv * c3, v1 + dv * c4
			end
			if tune.flipH then
				u1, u2 = u2, u1
			end
			if tune.flipV then
				v1, v2 = v2, v1
			end
			pcall(tex.SetTexCoord, tex, u1, u2, v1, v2)
			mark("coord")
		elseif had and had.coord then
			if window then
				pcall(tex.SetTexCoord, tex, window[1], window[2], window[3], window[4])
			else
				pcall(tex.SetTexCoord, tex, 0, 1, 0, 1)
			end
		end
	end

	Kit.tunedAt[tex] = now
end

-- (0.19.1) The editor's proxy rectangle on its element, the tuning's offsets on it. ProxyTo lays it on another
-- rectangle (a close button's face, Replace's rect = "normal": the plate hung from the face itself and the
-- editor's drag moved nothing, user 2026-10-04); CenterTune moves a piece centred on something other than its
-- rect (a portrait's ring on the portrait) by the same offsets, its size by the pads
function LOOK.PlaceProxy(rep, tune)
	local x, y = tune and tune.x or 0, tune and tune.y or 0
	rep.proxy:ClearAllPoints()
	rep.proxy:SetPoint("TOPLEFT", rep.proxyOf, "TOPLEFT", x - (tune and tune.padL or 0), y + (tune and tune.padT or 0))
	rep.proxy:SetPoint("BOTTOMRIGHT", rep.proxyOf, "BOTTOMRIGHT", x + (tune and tune.padR or 0), y - (tune and tune.padB or 0))
end
function LOOK.ProxyTo(rep, rect)
	if not rep.proxy then
		return rect
	end
	rep.proxyOf, rep.proxy.melloProxyOf = rect, rect
	LOOK.PlaceProxy(rep, rep.tune)
	return rep.proxy
end
function LOOK.CenterTune(rep, tune)
	local tex = rep.tex
	local L, R, T, B = tune and tune.padL or 0, tune and tune.padR or 0, tune and tune.padT or 0, tune and tune.padB or 0
	if not rep.centerSize then
		local w, h = tex:GetSize()
		if Secret(w) or Secret(h) then
			return
		end
		rep.centerSize = { w, h }
	end
	-- the centre's own move (a portrait moved by the editor, Kit:TuneRegion) taken back off: the ring stays
	-- where it was and the portrait moves under it; its middle moves by x + (R - L) / 2 however it is held
	local own = LOOK.geomTune[rep.centerOn]
	local ox = own and (own.x or 0) + ((own.padR or 0) - (own.padL or 0)) / 2 or 0
	local oy = own and (own.y or 0) + ((own.padT or 0) - (own.padB or 0)) / 2 or 0
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", rep.centerOn, rep.centerPoint or "CENTER", (tune and tune.x or 0) + (R - L) / 2 - ox, (tune and tune.y or 0) + (T - B) / 2 - oy)
	-- (a square piece that waited for its rect's size is sized by its sizer, from the proxy, pads and all)
	if not rep.sizer then
		tex:SetSize(math.max(1, rep.centerSize[1] + L + R), math.max(1, rep.centerSize[2] + T + B))
	end
end

-- The whole replacement: its rectangle (through the proxy made in Replace),
-- its alpha and every texture in it.
function Kit:TuneObject(rep, tune)
	local obj = rep.object
	if not obj then
		return
	end
	-- a tune arriving for a tab's open card whose rails still wait (it was
	-- untuned when dressed, the editor off): laid now, before the tune, so the
	-- tune lands on its textures as on a card built at dressing, and a tune
	-- taken off again later leaves it as it leaves every built card (review,
	-- 2026-09-24)
	if tune and rep.skin and rep.skin.pendingArt then
		LayRep(rep)
	end
	rep.tune = tune
	if rep.proxy and rep.proxyOf then
		LOOK.PlaceProxy(rep, tune)
		if rep.centerOn and rep.tex then
			pcall(LOOK.CenterTune, rep, tune)
		end
	elseif not InCombatLockdown() and not (obj.IsProtected and obj:IsProtected()) then
		-- (0.19.1) no proxy to move it by (built before the editor was there, or
		-- laid by its window's own code: the kit editor's drag did nothing,
		-- user 2026-10-04): its own frame moved against its own points
		if tune and (tune.x or tune.y or tune.padL or tune.padR or tune.padT or tune.padB) then
			pcall(LOOK.TuneGeometry, obj, tune)
		elseif LOOK.geomBase[obj] then
			pcall(LOOK.UntuneGeometry, obj)
		end
	end
	if obj.SetAlpha then
		pcall(obj.SetAlpha, obj, (tune and tune.alpha) or 1)
	end
	for _, tex in ipairs(self:Textures(rep)) do
		self:TuneTexture(tex, tune)
	end
	-- a tuned layer is the bar relayer's to follow again on the next fill change
	rep.relayered = nil
	if rep.Refit then
		pcall(rep.Refit, rep)
	end
end

-- Re-apply (or undo) the tuning of every replacement already on screen, so
-- the editor's handles and sliders move the art immediately. Structural
-- changes -- a different kind or a different painted piece -- still need
-- the panels rebuilt, which the editor asks for with a reload.
function Kit:RefreshTuning()
	local KT = MelloUI.KitTuning
	if not KT then
		return
	end
	for _, rep in ipairs(self.repList) do
		local tune = KT:Tune(rep.key)
		if tune or rep.tune then
			self:TuneObject(rep, tune)
		end
	end
end

-- Every replacement built this session, so the editor can list what is
-- actually on screen instead of guessing from the library.
Kit.repList = {}
Kit.repByKey = {}

function Kit:RegisterReplacement(rep)
	if not rep or rep.registered then
		return
	end
	rep.registered = true
	self.repList[#self.repList + 1] = rep
	local key = rep.key
	if key then
		local list = self.repByKey[key]
		if not list then
			list = {}
			self.repByKey[key] = list
		end
		list[#list + 1] = rep
	end
end

-- How the editor names one region of a frame: its global name, the key it
-- sits under in the frame table, or the art it shows.
function Kit:RegionKey(frame, region)
	local ok, name = pcall(region.GetName, region)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	for key, value in pairs(frame) do
		if rawequal(value, region) and type(key) == "string" then
			return key
		end
	end
	return self:ArtKey(region)
end

-- Per-region tuning of a window the kit does not otherwise touch (the
-- `regions` table of an element; MelloUI's own windows use this).
function Kit:TuneRegions(frame, regions)
	if not (frame and frame.GetRegions and regions) then
		return
	end
	local ok, list = pcall(function() return { frame:GetRegions() } end)
	if not ok then
		return
	end
	for index, region in ipairs(list) do
		if region.GetObjectType and region:GetObjectType() == "Texture" then
			-- a texture with no name and no key is addressed by its position,
			-- the same way the editor wrote it down
			local key = self:RegionKey(frame, region)
			local tune = (key and regions[key]) or regions["#" .. index]
			if tune then
				if tune.hidden then
					Kit.tunedHidden[region] = true
					pcall(region.Hide, region)
				else
					if Kit.tunedHidden[region] then
						Kit.tunedHidden[region] = nil
						pcall(region.Show, region)
					end
					self:TuneRegion(region, tune)
				end
			elseif Kit.tunedAt[region] or Kit.tunedHidden[region] then
				-- it was changed and is not listed any more: put it back.
				-- Only ever a texture we touched, so the game's own tints and
				-- hidden states are left alone.
				if Kit.tunedHidden[region] then
					Kit.tunedHidden[region] = nil
					pcall(region.Show, region)
				end
				self:TuneRegion(region, nil)
			end
		end
	end
end

-- The frame kind under a button (a tab's card, a list row): its hover /
-- pressed / disabled tint, one handler per script for every such button
-- (user, 2026-09-24: shared handlers), the rep kept by its button
local frameTints = setmetatable({}, { __mode = "k" })   -- [button] = the rep it tints
-- the iron as painted: the one table the tint reads while nothing is checked
-- (a new { 1, 1, 1 } on every hover, leave, press and Update before)
local NO_TINT = { 1, 1, 1 }

local function FrameTint(rep, k)
	local on = rep.checked and rep.checked() and true or false
	local t = (on and rep.rule.checkedTint) or NO_TINT
	for _, tex in ipairs(rep.skin.art) do
		tex:SetVertexColor(math.min(t[1] * k, 1), math.min(t[2] * k, 1), math.min(t[3] * k, 1))
	end
	if rep.skin.body then
		rep.skin.body:SetVertexColor(math.min(k, 1), math.min(k, 1), math.min(k, 1))
	end
	-- the selected row's active look (Kit:SetActive), round its card
	if rep.checked then
		Kit:SetActive(rep.skin, on, rep.skin, "rect")
	end
end

local FrameTint_OnEnter = Shared("OnEnter on a kit frame's button", function(b)
	local rep = frameTints[b]
	rep.hover = true
	rep.Update()
end, "script")
local FrameTint_OnLeave = Shared("OnLeave on a kit frame's button", function(b)
	local rep = frameTints[b]
	rep.hover = nil
	rep.pressed = nil
	rep.Update()
end, "script")
local FrameTint_OnMouseDown = Shared("OnMouseDown on a kit frame's button", function(b)
	local rep = frameTints[b]
	rep.pressed = true
	pressedLatches[rep] = rep.Update
	rep.Update()
end, "script")
local FrameTint_OnMouseUp = Shared("OnMouseUp on a kit frame's button", function(b)
	local rep = frameTints[b]
	rep.pressed = nil
	rep.Update()
end, "script")
local FrameTint_OnSetEnabled = Shared("SetEnabled on a kit frame's button", function(b)
	frameTints[b].Update()
end)

-- A holder tiling one texture (the edge and tile kinds: holder.kitTile), and
-- a sizer re-fitting a tile that is a region (sizer.kitRefit): one handler
-- each for all of them
local Holder_OnSize = Shared("OnSizeChanged on a kit holder", function(f)
	Kit:Retile(f.kitTile)
end, "script")
local Holder_OnShow = Shared("OnShow on a kit holder", function(f)
	Kit:Retile(f.kitTile)
end, "script")
local Sizer_OnSize = Shared("OnSizeChanged on a kit tile's rect", function(f)
	f.kitRefit()
end, "script")
local Sizer_OnShow = Shared("OnShow on a kit tile's rect", function(f)
	f.kitRefit()
end, "script")

-- A slot's icon fitted into its rim again after the game re-anchors it: one
-- handler for every button's methods (slotIcons) and every kept icon's
-- SetPoint (keptIcons)
local ICON_METHODS = { "InitializeIconAnchoring", "UpdateIconInterior", "OnMouseDown", "OnMouseUp" }
local slotIcons = setmetatable({}, { __mode = "k" })   -- [button] = its slot rep
local keptIcons = setmetatable({}, { __mode = "k" })   -- [icon] = its slot rep
local SlotIcon_Refit = Shared("icon anchoring on a kit slot's button", function(b)
	local rep = slotIcons[b]
	if rep.object:IsShown() then
		Kit:SlotPlaceIcon(rep.object)
	end
end)
local SlotIcon_Keep = Shared("SetPoint on a kit slot's kept icon", function(icon)
	local rim = keptIcons[icon].object
	if rim:IsShown() and not rim.placingIcon then
		Kit:SlotPlaceIcon(rim)
	end
end)

-- The WINDOW a replacement is in: the top frame under UIParent (a title
-- container may sit in a page inside the window: the group finder's tabs
-- stayed behind when only the page moved — user, 2026-09-21)
local function WindowOf(frame)
	local depth = 0
	while frame and frame ~= UIParent and depth < 6 do
		local up = frame.GetParent and frame:GetParent()
		if not up or up == UIParent then
			return frame
		end
		frame = up
		depth = depth + 1
	end
	return frame
end

-- A game window's portrait corner stays the game's (the user, 2026-10-10: "the sizes of the icons and their
-- borders in the top left returns to default values, and to not make any custom changes to them anymore"): no
-- ring of ours over it, its portrait neither fitted nor given a disc (the panels' FitPortrait / RingDisc need
-- the ring: without it they leave the portrait alone). MelloUI's own windows keep their corner ring (`own`:
-- KitWindow's DressRing), there being no game ring to keep. (No top-level local for the name: the file is at
-- Lua 5.1's 200.)
function Kit:Replace(region, opts)
	opts = opts or {}
	local key = opts.as or self:ArtKey(region)
	if key == "UI-Frame-PortraitMetal-CornerTopLeft" and not opts.own then
		-- (no key: a refusal, not a piece missing -- the panels' Replace helpers tell a missing piece by the key, and
		-- printed "no kit piece mapped" for every game window's corner; the user, 2026-10-10)
		return nil
	end
	-- (and the game's border round such a window, skipped at that corner: its
	-- other pieces faded one by one, not the whole border -- the corner ring is
	-- one of its pieces and would fade with it; its rail stubs cut, Kit:CutGameCorner)
	local keptCorner
	if key == "NineSlicePanelTemplate" and type(opts.skip) == "string" and opts.skip:find("tl", 1, true)
		and not opts.noFade then
		local corner = rawget(region, "TopLeftCorner")
		keptCorner = corner
		if corner then
			local fade = {}
			for _, t in ipairs(opts.alsoFade or {}) do
				fade[#fade + 1] = t
			end
			for _, t in ipairs(self:OtherTextures(region, corner)) do
				fade[#fade + 1] = t
			end
			opts.noFade, opts.alsoFade = true, fade
		end
	end
	local rule = self:RuleFor(key)
	if not rule then
		return nil, key
	end
	local isFrame = region.GetObjectType and region:GetObjectType() ~= "Texture" and region.CreateTexture
	local parent = opts.parent or (isFrame and region:GetParent()) or region:GetParent()
	local rect = opts.rect or region
	-- the editing tools' tuning for this element (Core\KitTuning.lua)
	local KT = MelloUI.KitTuning
	local tune = KT and KT:Tune(key) or nil
	if tune and tune.hidden then
		-- "leave this one alone": the game's own art stays, as if the library
		-- had no rule for it
		return nil, key
	end
	-- a proxy rectangle stands between the game's element and our piece so
	-- the editor can move and resize the piece without touching the game's
	-- layout; it is made whenever there is something to offset, and always
	-- while the editor addon is installed (so a drag has something to move)
	local proxy
	if tune or self.liveEdit then
		proxy = CreateFrame("Frame", nil, parent)
		proxy.ignoreInLayout = true   -- never part of a layout frame's size (see Holder)
		proxy:EnableMouse(false)
		local x, y = tune and tune.x or 0, tune and tune.y or 0
		proxy:SetPoint("TOPLEFT", rect, "TOPLEFT", x - (tune and tune.padL or 0), y + (tune and tune.padT or 0))
		proxy:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", x + (tune and tune.padR or 0), y - (tune and tune.padB or 0))
		proxy.melloProxyOf = rect
		rect = proxy
	end
	local level = (tune and tune.level) or opts.level or rule.level or -1
	-- (rule.atBorder: the rails alone at the game's border frame's level, one under it -- its corner ring stays over
	-- them -- on a frame of their own, Kit:NineSlice's edgeLevel; the skin, which a window hangs its stone and its
	-- sheets on, stays at the rule's level: raised whole, it covered the window -- in game, 2026-10-10)
	local edgeLevel
	if rule.atBorder and isFrame and not (tune and tune.level) and not opts.level then
		local l = region:GetFrameLevel() - 1
		if l > parent:GetFrameLevel() + level then
			edgeLevel = l
		end
	end
	-- fitHeight / fitWidth: the element's size as the template states it, used
	-- where its rect reads SECRET (the target's spell bar) or is not laid out yet
	local rep = Mixin({ kind = rule.kind, key = key, rule = rule, region = region, rect = rect, alsoFade = opts.alsoFade or {}, fitHeight = opts.fitHeight, fitWidth = opts.fitWidth, noFade = opts.noFade }, ReplacementMixin)
	rep.proxy, rep.proxyOf, rep.tune = proxy, proxy and proxy.melloProxyOf or nil, tune
	-- (the frame it is dressed on: a bag, a page of a window, a window -- each
	-- rail's shade its own, Modules/KitShade.lua)
	rep.kitParent = parent
	if keptCorner then
		self:CutGameCorner(rep, keptCorner)
	end

	if rule.kind == "frame" then
		local f = MakeHolder(parent, rect, level, opts.strata)
		local fscale = self.scale * (rule.scale or self.frameScale)
		if rule.outset then
			-- the frame grows OUTWARD from the rect by `outset` piece px: the
			-- rails lie outside the window, their inner bevel on its edge
			local o = rule.outset * fscale
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", rect, "TOPLEFT", -o, o)
			f:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", o, -o)
		end
		-- opts.body overrides the rule's (false: edges only, for a window whose
		-- middle must stay open — the world map's canvas)
		local body = rule.body == nil and true or rule.body
		if opts.body ~= nil then
			body = opts.body
		end
		-- rule.owner: the rails and body as regions of the replaced texture's
		-- frame in the rule's layers (edgeLayer / edgeSub, bodyLayer / bodySub)
		local owner = (rule.owner and not isFrame) and region:GetParent() or nil
		-- `dim` (rule or opts; user, 2026-09-24: "apply the eye strain rule to
		-- all existing windows"): a box that holds text -- a list, an inset,
		-- a section of options -- gets the palette's inner panel over its
		-- stone inside the rail at that alpha (WINDOW-RULES 2e), a region of
		-- the box's own host, shown and hidden with it
		local dim = opts.dim
		if dim == nil then
			dim = rule.dim
		end
		-- opts.layWith (Kit:SkinPanelTab's open card): the skin's textures wait
		-- until the card is first to be seen, that is while this region (the
		-- game's own open art) shows (NineSlice's `defer`). Never while the
		-- editing tools are on or the element is tuned (their handles and
		-- tints work on the textures), nor for a skin that tints itself
		local defer = opts.layWith and not (tune or self.liveEdit or owner or dim or rule.corners)
			and not (opts.button and (rule.hover or rule.pressed or rule.disabled)) or nil
		rep.skin = self:NineSlice(f, { scale = fscale, gems = false, body = body, bodyScale = rule.bodyScale and self.scale * rule.bodyScale,
			open = opts.open or rule.open, prefix = rule.prefix or self.framePrefix, corners = rule.corners, skip = opts.skip,
			owner = owner, bodyLayer = rule.bodyLayer, bodySub = rule.bodySub, edgeLayer = rule.edgeLayer, edgeSub = rule.edgeSub,
			defer = defer, edgeLevel = edgeLevel })
		if key == "NineSlicePanelTemplate" and not rep.skin.pendingArt then
			self:TitleRail(rep, region)
		end
		if rep.skin.pendingArt then
			rep.layWith = opts.layWith
			f.kitWaiting = rep
			Perf.SetScript(f, "OnUpdate", Waiting_OnUpdate)
		end
		rep.checked = opts.checked
		rep.object = owner and rep.skin or f
		if dim and body and rep.skin.body then
			-- the fill on the frame the BODY is a region of (the skin frame, or
			-- the owner): on the holder it tied with the skin frame at one level
			-- and could draw under the stone, unseen
			local host = owner or rep.skin
			local inset = (rep.skin.thickness or 0) * 0.6
			local fill = host:CreateTexture(nil, rule.bodyLayer or "BACKGROUND", nil, math.min((rule.bodySub or 0) + 1, 7))
			fill:SetPoint("TOPLEFT", rep.skin, "TOPLEFT", inset, -inset)
			fill:SetPoint("BOTTOMRIGHT", rep.skin, "BOTTOMRIGHT", -inset, inset)
			-- opts.dimColor: another palette tone (a card or row lying ON a
			-- dimmed list takes the main window's tone, a stripe lighter than
			-- the panel around it, as WINDOW-RULES 2e has rows), its key or
			-- the palette's table; painted by its key (Kit:Paint), so a new
			-- palette paints it again. A colour of no palette role stays as given.
			local c = opts.dimColor
			local tone = c == nil and "innerPanel" or self:PaletteKeyOf(c)
			if tone then
				self:Paint(fill, tone, "fill", dim)
			elseif type(c) == "table" then
				fill:SetColorTexture(c[1], c[2], c[3], dim)
			end
			rep.skin.dimFill = fill
			table.insert(rep.skin.all, fill)
		end
		if rule.lit then
			rep.skin:SetTint(rule.lit[1], rule.lit[2], rule.lit[3])
		end
		-- `active`: the piece stands for the game's active / selected art
		-- (the open tab's card): the active look round it whenever it shows,
		-- as regions of its skin (made on the skin's first show)
		if rule.active then
			self:SetActive(rep.skin, true, rep.skin, "rect")
		end
		local button = opts.button
		if button and (rule.hover or rule.pressed or rule.disabled) then
			-- a frame under a button: its states are a tint of the whole
			-- skin (edges and body), hover lighter, pressed / disabled darker
			-- the iron takes the rule's checkedTint while opts.checked() (a
			-- selected row); the state factor multiplies both iron and body
			-- (FrameTint)
			local function Update()
				-- secret-safe (Slot_Update's rule): a secret IsEnabled keeps the last answer
				local disabled = rep.lastDisabled or false
				if button.IsEnabled then
					local okE, enabled = pcall(button.IsEnabled, button)
					if okE and not Secret(enabled) then
						disabled = enabled == false
					end
				end
				rep.lastDisabled = disabled
				FrameTint(rep, disabled and (rule.disabled or 1) or rep.pressed and (rule.pressed or 1) or rep.hover and (rule.hover or 1) or 1)
			end
			rep.Update = Update
			if frameTints[button] == nil then
				-- the shared handlers (FrameTint_*), the rep kept by its button
				frameTints[button] = rep
				Perf.HookScript(button, "OnEnter", FrameTint_OnEnter)
				Perf.HookScript(button, "OnLeave", FrameTint_OnLeave)
				Perf.HookScript(button, "OnMouseDown", FrameTint_OnMouseDown)
				Perf.HookScript(button, "OnMouseUp", FrameTint_OnMouseUp)
				if type(button.SetEnabled) == "function" then
					hooksecurefunc(button, "SetEnabled", FrameTint_OnSetEnabled)
				end
			else
				-- a second tinted frame on this button: handlers of its own, so
				-- every hook runs where it did
				Perf.HookScript(button, "OnEnter", function() rep.hover = true; Update() end)
				Perf.HookScript(button, "OnLeave", function() rep.hover = nil; rep.pressed = nil; Update() end)
				Perf.HookScript(button, "OnMouseDown", function() rep.pressed = true; pressedLatches[rep] = Update; Update() end)
				Perf.HookScript(button, "OnMouseUp", function() rep.pressed = nil; Update() end)
				if type(button.SetEnabled) == "function" then
					hooksecurefunc(button, "SetEnabled", Update)
				end
			end
			Update()
		end
	elseif rule.kind == "edge" then
		local f = MakeHolder(parent, rect, level, opts.strata)
		local tex = f:CreateTexture(nil, "OVERLAY")
		tex.kitScale = self.scale * (rule.scale or self.frameScale)
		self:Apply(tex, rule.piece, true)   -- (tiled below, once it is placed)
		tex:SetAllPoints(f)
		f.kitTile = tex
		Perf.SetScript(f, "OnSizeChanged", Holder_OnSize)
		Perf.HookScript(f, "OnShow", Holder_OnShow)
		self:Retile(tex)
		rep.object, rep.tex = f, tex
	elseif rule.kind == "strip" then
		local state = opts.state or rule.state
		-- `owner`: the strip's textures are REGIONS of the replaced texture's
		-- frame, in its layer one sublevel up (a button's plate under its
		-- text, whatever frame level the button has); else a child frame
		local owner, layer, sub = nil, "BACKGROUND", 1
		if rule.owner and not isFrame then
			owner = region:GetParent()
			local l, sl = region:GetDrawLayer()
			layer, sub = rule.layer or l or "BACKGROUND", rule.sublevel or ((sl or 0) + 1)
		end
		local strip = self:Strip(parent, rule.base, { state = state, scale = self.scale, layer = layer, sublevel = sub, owner = owner })
		strip:SetFrameLevel(math.max(parent:GetFrameLevel() + level, 0))
		strip:SetAllPoints(rect)
		strip.forceCapless = opts.capless      -- the middle alone (a plate whose caps carry an icon, on a box that has none)
		strip.dropCap = opts.dropCap           -- one cap left out ("l" / "r"): a button that butts against another control on that side
		rep.object, rep.strip = strip, strip
		rep:Refit()
		-- the cap decision (capless when the rect is narrower than two caps)
		-- is made from the rect's width at fit time: a box fitted before its
		-- window laid it out (the backpack's search box, 0 px wide while the
		-- bag was closed at load) kept its caps hidden for good (user,
		-- 2026-09-21). A frame rect refits itself whenever its size changes.
		if rect.HookScript and rect.GetObjectType and rect:GetObjectType() ~= "Texture" then
			local function Refit()
				if rep.object and rep.object:IsShown() then
					rep:Refit()
				end
			end
			Perf.HookScript(rect, "OnSizeChanged", Refit)
			Perf.HookScript(rect, "OnShow", Refit)   -- sized while hidden: no OnSizeChanged came
		end
		local button = opts.button
		if button then
			-- a plate under a button: hover / pressed / disabled from the
			-- button's scripts and SetEnabled, like a slot rim
			local function Update()
				local disabled = button.IsEnabled and button:IsEnabled() == false
				-- a strip's states are painted on its parts: resolve on the mid
				rep:SetState(Kit:ResolveState(rule.base .. "_mid", rep.hover, rep.pressed, nil, disabled))
			end
			Perf.HookScript(button, "OnEnter", function() rep.hover = true; Update() end)
			Perf.HookScript(button, "OnLeave", function() rep.hover = nil; rep.pressed = nil; Update() end)
			Perf.HookScript(button, "OnMouseDown", function() rep.pressed = true; pressedLatches[rep] = Update; Update() end)
			Perf.HookScript(button, "OnMouseUp", function() rep.pressed = nil; Update() end)
			if type(button.SetEnabled) == "function" then
				hooksecurefunc(button, "SetEnabled", Update)
			end
			if button.Enable then
				hooksecurefunc(button, "Enable", Update)
			end
			if button.Disable then
				hooksecurefunc(button, "Disable", Update)
			end
			rep.button = button
			rep.Update = Update
			Update()
		end
		if rule.onRail then
			-- the plate is lifted from the title container onto the outer
			-- rail: its BOTTOM on the band's top edge, above the window's
			-- top edge; the container's TitleText goes with it, centred on
			-- the plate, and is put back on disable
			local window = parent:GetParent()
			local text = parent.TitleText
			local refit = rep.Refit
			rep.Refit = function(self)
				refit(self)
				if not window then
					return
				end
				-- the plate rides the OUTER rail across its whole width (user,
				-- 2026-09-23, layout C): centred on the rail's middle line, its
				-- caps' gems on the rail's top corners, where the frame's own
				-- gems were (they give way: RegisterShell); anchored to the
				-- window's top corners, so no layout is needed
				local lift, reach = Kit:TitleOnRail(self.strip)
				local out = Kit:OuterRailOutset() + reach
				-- with a portrait ring on the corner the plate starts at the
				-- ring's centre, its left cap left out: nothing of it shows
				-- left of the ring, the rest runs into the ring's hole (user,
				-- 2026-09-23: the cap past the ring "mask completely")
				local left = -out
				local ringX = self.behindRing and Kit:RingCentreX(self.behindRing, window)
				self.strip.dropCap = ringX and "l" or nil
				if ringX then
					left = ringX
				end
				-- the title stays over the window's middle, not the shorter plate's
				self.strip.textShift = -(left + out) / 2
				self.strip:ClearAllPoints()
				self.strip:SetPoint("LEFT", window, "TOPLEFT", left, lift)
				self.strip:SetPoint("RIGHT", window, "TOPRIGHT", out, lift)
				self.strip:SetHeight(self.strip.height)
				local w = window:GetWidth()
				if w and w > 0 and not (issecretvalue and issecretvalue(w)) then
					self.strip:FitCaps(w + out - left)
				end
			end
			if text then
				local saved = {}
				for i = 1, text:GetNumPoints() do
					saved[i] = { text:GetPoint(i) }
				end
				-- centred on the plate's PAINTED box, not its canvas (the box
				-- sits lower in the canvas: the text read as riding high —
				-- user, 2026-09-21)
				local function Centre(self)
					text:ClearAllPoints()
					text:SetPoint("CENTER", self.strip, "CENTER", self.strip.textShift or 0, Kit:StripTextOffset(self.strip))
					Kit:TitleFont(text, true)
				end
				rep.onEnable = Centre
				local refit2 = rep.Refit
				rep.Refit = function(self)
					refit2(self)
					if self.object:IsShown() then
						Centre(self)
					end
				end
				rep.onDisable = function()
					Kit:TitleFont(text, false)
					text:ClearAllPoints()
					for _, pt in ipairs(saved) do
						text:SetPoint(unpack(pt))
					end
				end
			end
			-- the window may be laid out only when shown: fit again then
			Perf.SetScript(strip, "OnShow", function() rep:Refit() end)
		elseif rule.centreTitle and parent.TitleText then
			-- (0.20.1, the window titles on the game's title bar: the ribbon, the band) the title text centred on the
			-- strip's painted box, in the title face (WINDOW-RULES 2c); its own anchors back on disable
			local text = parent.TitleText
			local saved = {}
			for i = 1, text:GetNumPoints() do
				saved[i] = { text:GetPoint(i) }
			end
			local function Centre(self)
				text:ClearAllPoints()
				text:SetPoint("CENTER", self.strip, "CENTER", 0, Kit:StripTextOffset(self.strip))
				Kit:TitleFont(text, true)
			end
			rep.onEnable = Centre
			local refit = rep.Refit
			rep.Refit = function(self)
				refit(self)
				if self.object:IsShown() then
					Centre(self)
				end
			end
			rep.onDisable = function()
				Kit:TitleFont(text, false)
				text:ClearAllPoints()
				for _, pt in ipairs(saved) do
					text:SetPoint(unpack(pt))
				end
			end
		end
		local edit = opts.edit
		if edit then
			-- a plate under an edit box: its focused look while it has focus
			Perf.HookScript(edit, "OnEditFocusGained", function() rep:SetState("focused") end)
			Perf.HookScript(edit, "OnEditFocusLost", function() rep:SetState(rule.state or Kit:FirstState(rule.base, "mid")) end)
		end
	elseif rule.kind == "slot" then
		local button = opts.button or parent
		local rim = self:Slot(button, { kind = rule.slot or "slot", scale = self.scale, checked = opts.checked, under = rule.under,
			layer = rule.layer, sublevel = rule.sublevel })
		rim.iconGrow = rule.iconGrow
		rim.iconBleed = rule.iconBleed
		rim:ClearAllPoints()
		rim:SetAllPoints(rect)
		if opts.icon then
			-- the game's icon fitted into the rim's opening (a side tab's
			-- icon is drawn off-centre and clipped by the game's own mask,
			-- which is faded with the tab art); the game's anchors are
			-- restored on disable
			local icon = opts.icon
			local saved = { w = icon:GetWidth(), h = icon:GetHeight() }
			for i = 1, icon:GetNumPoints() do
				saved[i] = { icon:GetPoint(i) }
			end
			rim.icon = icon
			rep.onEnable = function()
				self:SlotPlaceIcon(rim)
			end
			rep.onDisable = function()
				icon:ClearAllPoints()
				for i = 1, #saved do
					icon:SetPoint(unpack(saved[i]))
				end
				icon:SetSize(saved.w, saved.h)
			end
			-- the game re-anchors the icon on press / release and on its own
			-- layout: fit it again after each (SlotIcon_Refit, the rep kept by
			-- its button; a second slot on the button has handlers of its own)
			local shared = slotIcons[button] == nil
			if shared then
				slotIcons[button] = rep
			end
			for _, m in ipairs(ICON_METHODS) do
				if button[m] then
					hooksecurefunc(button, m, shared and SlotIcon_Refit or function()
						if rep.object:IsShown() then
							self:SlotPlaceIcon(rim)
						end
					end)
				end
			end
			-- `keepIcon`: whoever anchors the icon afterwards (a side tab
			-- centres it with an offset on press, release and selection, and
			-- sizes it to its atlas: it spilled over the rim -- user,
			-- 2026-09-23), it goes straight back into the opening
			if rule.keepIcon then
				if keptIcons[icon] == nil then
					keptIcons[icon] = rep
					hooksecurefunc(icon, "SetPoint", SlotIcon_Keep)
				else
					hooksecurefunc(icon, "SetPoint", function()
						if rep.object:IsShown() and not rim.placingIcon then
							self:SlotPlaceIcon(rim)
						end
					end)
				end
			end
		end
		-- the rim's size from the pitch: gemSpan (neighbours share a gem: the
		-- rim larger than the pitch), or pitchSize (a thin rim a little inside
		-- the pitch: the micro buttons, taller than they are apart)
		local function PitchSize(px, py)
			if rule.gemSpan then
				return px / rule.gemSpan[1], py / rule.gemSpan[2]
			elseif rule.pitchSize then
				return px * rule.pitchSize, py * rule.pitchSize
			end
		end
		local pw, ph
		if opts.pitch and opts.pitch[1] > 0 and opts.pitch[2] > 0 then
			pw, ph = PitchSize(opts.pitch[1], opts.pitch[2])
		end
		if pw then
			rim:ClearAllPoints()
			rim:SetPoint("CENTER", rect, "CENTER")
			rim:SetSize(pw, ph)
		end
		-- SetPitch(x, y): re-size the rim to a new pitch (a bar re-laid by
		-- Edit Mode) and fit the icon again
		rep.SetPitch = function(self, px, py)
			local w, h
			if px and py and px > 0 and py > 0 then
				w, h = PitchSize(px, py)
			end
			if w then
				rim:ClearAllPoints()
				rim:SetPoint("CENTER", rect, "CENTER")
				rim:SetSize(w, h)
				if rim.icon then
					Kit:SlotPlaceIcon(rim)
				end
			end
		end
		if rule.rest then
			rim.restState = rule.rest
		end
		if rule.glow then
			local glow = rim.owner:CreateTexture(nil, rule.under and "ARTWORK" or "OVERLAY", nil, 4)
			glow.kitScale = self.scale
			-- the glow is the rim's checked look, or its hover look for a rim
			-- painted without one (the round slot)
			local look = rule.rest or (PIECES[rim.base .. "_checked"] and "checked") or (PIECES[rim.base .. "_hover"] and "hover") or self:FirstStateOf(rim.base)
			self:Apply(glow, rim.base .. "_" .. look)
			glow:SetBlendMode("ADD")
			glow:SetAllPoints(rim)
			glow:Hide()
			rim.glow = glow
		end
		rim:Update()
		rep.object = rim
		if rule.sideTab then
			self:RegisterSideTab(rep, button)
		end
	elseif rule.kind == "state" then
		local button = opts.button or parent
		local tex = self:StateTexture(button, rule.base, { scale = self.scale, layer = rule.layer or "OVERLAY", checked = opts.checked })
		if rule.rect == "normal" and button.GetNormalTexture and button:GetNormalTexture() then
			rect = LOOK.ProxyTo(rep, button:GetNormalTexture())
		end
		tex:ClearAllPoints()
		if rule.natural then
			-- the kit size, its OPAQUE part centred on the rect (a 17 x 11
			-- stepper under a 16 x 15 arrow; an arrow painted off-centre in
			-- its canvas is placed by its box, not its canvas); `fit =
			-- "height"` sizes it to the rect's height instead, aspect kept
			local name = rule.base .. "_" .. (self:FirstStateOf(rule.base) or "normal")
			local p = PIECES[name]
			local w, h = self:Size(name, self.scale)
			if rule.fit == "height" and p and rect:GetHeight() > 0 then
				h = rect:GetHeight()
				w = h * p.w / p.h
			elseif rule.fit == "width" and p and rect:GetWidth() > 0 then
				w = rect:GetWidth()
				h = w * p.h / p.w
			end
			tex:SetSize(w, h)
			local dx, dy = 0, 0
			if p and p.box then
				local k = w / p.w
				dx = (p.w / 2 - (p.box[1] + p.box[3]) / 2) * k
				dy = ((p.box[2] + p.box[4]) / 2 - p.h / 2) * k
			end
			tex:SetPoint("CENTER", rect, "CENTER", dx, dy)
		else
			tex:SetAllPoints(rect)
		end
		rep.object, rep.rect = tex, rect
	elseif rule.kind == "flat" then
		-- (0.19.1; the user, 2026-10-04: "from now on only use the same style as
		-- we have in the Configurator") the Configurator's flat control over
		-- the game's (MelloUI.Widgets.FlatOver: its plate, caret, field, tab,
		-- track or knob; 0.19.9 the kit's NewUI2 check box, close, arrow, + / -
		-- or cog), on a holder of ours on the rect; painted by the control's
		-- state (FlatState) as a rim follows its button: an empty region of the
		-- holder is the rim FollowButton drives, Slot_Update painting the parts
		local button = opts.button or (isFrame and region) or parent
		if rule.rect == "normal" and button and button.GetNormalTexture and button:GetNormalTexture() then
			rect = LOOK.ProxyTo(rep, button:GetNormalTexture())
		end
		local f = MakeHolder(parent, rect, level, opts.strata)
		-- opts.fitHeight (an old dropdown's 24 px box in its taller frame): the
		-- plate that tall, centred on the rect
		local fit = opts.fitHeight
		if fit and fit > 0 then
			f:ClearAllPoints()
			f:SetPoint("LEFT", rect, "LEFT", 0, 0)
			f:SetPoint("RIGHT", rect, "RIGHT", 0, 0)
			f:SetHeight(fit)
		end
		-- (the call's own: an edit box's fill over its glass -- the search
		-- box's only, opts.left -- and body = false, the edge alone)
		local parts = MelloUI.Widgets.FlatOver(f, rule.flat, { dir = rule.dir, left = opts.left, body = opts.body })
		local driver = f:CreateTexture(nil, "BACKGROUND")
		driver:SetAlpha(0)
		driver:SetAllPoints(f)
		Kit.pieceOf[driver] = true   -- ours: never faded as the game's art
		driver.button, driver.flatParts, driver.isChecked = button, parts, opts.checked
		-- (no flat control wears the active look: a ticked check box is its
		-- ticked plate, 0.19.9)
		driver.activeFamily = false
		if button and button.HookScript then
			FollowButton(driver, button)
			local list = flatButtons[button]
			if not list then
				list = {}
				flatButtons[button] = list
				if type(button.Enable) == "function" then
					hooksecurefunc(button, "Enable", FlatButton_Enabled)
				end
				if type(button.Disable) == "function" then
					hooksecurefunc(button, "Disable", FlatButton_Enabled)
				end
			end
			list[#list + 1] = driver
		end
		local edit = opts.edit
		if rule.flat == "edit" and edit and edit.HookScript then
			flatFields[edit] = driver
			Perf.HookScript(edit, "OnEditFocusGained", FlatField_Focus)
			Perf.HookScript(edit, "OnEditFocusLost", FlatField_Focus)
		end
		-- `rotates` (an arrow the game turns by rotating its art: the bag
		-- bar's): the flat arrow follows that rotation, a quarter at a time
		if rule.rotates and rule.flat == "arrow" and not isFrame and region.SetRotation then
			flatTurns[region] = parts
			parts.turnFrom = FLAT_TURN_OF[rule.dir or "left"] or 0
			hooksecurefunc(region, "SetRotation", FlatArrow_Turn)
			if region.GetRotation then
				FlatArrow_Turn(region, region:GetRotation())
			end
		end
		Slot_Update(driver)
		-- `active` (the open tab): the active look round the holder whenever
		-- it shows, as regions of it -- the Configurator's open tab wears it too
		if rule.active then
			self:SetActive(f, true, f, "rect")
		end
		rep.object, rep.rect, rep.flat, rep.flatDriver = f, rect, parts, driver
		-- (a panel that reads a plate's opening: a flat control's face is its whole rect)
		rep.GetOpening = FlatOpening
	elseif rule.kind == "active" then
		-- a check button of the game's own art the kit does not dress (the
		-- extra action button, the vehicle bar's): the active look in place
		-- of its checked art (the region, faded; noFade where the button has
		-- none), following its checked flag as a rim does. The object is an
		-- empty region on the button, drawing nothing, that the rims'
		-- followers read (FollowButton: its SetChecked, clicks, the bars'
		-- events, the pass after a fight)
		local button = opts.button or parent
		local mark = button:CreateTexture(nil, "OVERLAY")
		mark:SetAllPoints(button)
		mark:SetAlpha(0)
		Kit.pieceOf[mark] = true   -- ours: never faded as the game's art
		mark.button, mark.icon, mark.activeFamily = button, opts.icon, "look"
		FollowButton(mark, button)
		Slot_Update(mark)
		rep.object = mark
	elseif rule.kind == "vstrip" then
		-- an upright strip on the rect's height, `widthScale` x the rect's
		-- width, centred; its state follows the button's over / down flags
		local button = opts.button or parent
		local strip = self:VStrip(parent, rule.base, { scale = self.scale, layer = "ARTWORK", sublevel = 1 })
		strip:SetFrameLevel(math.max(parent:GetFrameLevel() + level, 0))
		strip:SetPoint("TOP", rect, "TOP")
		strip:SetPoint("BOTTOM", rect, "BOTTOM")
		rep.object, rep.vstrip, rep.button = strip, strip, button
		rep.Refit = function(self)
			local w = self.rect:GetWidth()
			if w and w > 0 then
				self.vstrip:FitWidth(w * (rule.widthScale or 1))
			end
		end
		rep:Refit()
		if button and button.OnButtonStateChanged then
			hooksecurefunc(button, "OnButtonStateChanged", function() rep:SetState() end)
		elseif button and button.HookScript then
			-- no state mixin: the over / down flags from the button's scripts
			-- (FollowButton drives a slot rim, not a strip)
			for _, script in ipairs({ "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp" }) do
				Perf.HookScript(button, script, function() rep:SetState() end)
			end
		end
		rep:SetState()
	elseif rule.kind == "bar" then
		-- a hollow bar bracket fitted to the rect's height, the trough in its
		-- opening, both as REGIONS of the rect's own frame: the trough in the
		-- replaced background's layer, the bracket in BORDER above the game's
		-- fill and below its ARTWORK text, so the rails cover the fill's edges
		-- `opts.bar`: another bracket than the rule's (a panel's Bar Border
		-- choice: "frame" the ornate P1, "castbar", or a thin rim look
		-- "rim" / "rimhair" / "rimround" / "rimgold" / "rimsunk");
		-- rep:SetBar(bar) swaps it live
		-- a progress bar's bracket follows its group's border (every window's
		-- Progress Bar Border; the nameplates', the unit frames' and the cast
		-- bar's their own, 0.19.8: Nameplate / Unit Frame / Cast Bar Border)
		local group = rule.borderGroup or (rule.bar ~= "castbar" and "bar") or nil
		if opts.ownBorder then
			group = nil   -- (0.20.1: a bar whose own panel lays its border, opts.bar and rep:SetBar: the swing timers')
		end
		local base = "bars/" .. (opts.bar or (group and self:BorderValue(group)) or rule.bar or "frame")
		if not PIECES[StripName(base, "mid")] then
			base = "bars/" .. (rule.bar or "frame")
		end
		rep.base = base
		if group then
			self:RegisterBorderBar(group, rep)
		end
		-- the bracket goes in the layer just above the game's fill (`layer` /
		-- `sublevel` on the rule: the caps at that sublevel, the middle ONE
		-- BELOW it, so the sublevel must be at least the fill's + 2: BORDER 1
		-- over a BORDER 0 fill, ARTWORK 4 over a rank bar's ARTWORK 2 fill),
		-- the trough in BACKGROUND under it
		-- opts.layer / sublevel / troughLayer / troughSub override the rule's
		-- for a fill drawn elsewhere (a unit frame's power bar at ARTWORK: the
		-- bracket at OVERLAY 0, the trough at BORDER)
		-- `state`: a variant of the caps ("red": the red end gems a health bar
		-- keeps, while every other bracket's are iron -- Tools/kit_gems.py)
		local strip = self:Strip(parent, base, { scale = self.scale, owner = parent, layer = opts.layer or rule.layer or "BORDER", sublevel = opts.sublevel or rule.sublevel or 1,
			state = opts.state or rule.state })
		strip:SetPoint("LEFT", rect, "LEFT")
		strip:SetPoint("RIGHT", rect, "RIGHT")
		-- `dropCap` ("l" / "r"): that end is capless, the rails running to the
		-- rect's edge (a unit frame's bar butting into the portrait ring);
		-- `capOut`: the kept cap(s) grow OUTWARD past the rect by their solid
		-- arm, so the opening starts at the rect's edge and the fill keeps its
		-- whole width (B3, user 2026-09-21); the trough's sublevel from
		-- `troughSub` (-1 under a fill drawn at BACKGROUND 0)
		strip.dropCap = opts.dropCap or rule.dropCap
		rep.capOut = opts.capOut or rule.capOut
		-- opts.troughParent: another frame for the trough (one below a fill
		-- that lives on a LOWER strata than the bracket's frame)
		local trough = (opts.troughParent or parent):CreateTexture(nil, opts.troughLayer or rule.troughLayer or "BACKGROUND", nil, opts.troughSub or rule.troughSub or 1)
		trough.kitScale = self.scale
		self:Apply(trough, "bars/trough")
		rep.object, rep.strip, rep.trough = strip, strip, trough
		rep.barParent, rep.borderGroup = parent, group   -- (the border library's: Kit:BarLibraryBorder)
		-- a StatusBar's fill can change layer after the bracket was placed
		-- (Bar Textures sets its own fill texture, which comes up at ARTWORK
		-- where the game's was at BACKGROUND): the bracket and trough follow
		-- the fill's layer on every SetStatusBarTexture (user, 2026-09-21:
		-- the unit frame fills came up over their brackets)
		if opts.layer and parent.SetStatusBarTexture and parent.GetStatusBarTexture then
			-- Some fills are re-set dozens of times a second (the target of
			-- target's, 41 a second in /melloperf 2026-09-24: the game's own
			-- updates, and Bar Textures putting its texture straight back):
			-- the layers are set only when they change. `relayered` is
			-- forgotten when the tuning touches the pieces (Kit:TuneObject).
			rep.Relayer = function(self)
				local layer, sub, tl, ts = Kit:BracketLayers(parent, true)
				if not layer then
					return   -- unreadable (secret) on this bar: the bracket stays where it was placed
				end
				if self.relayered == layer and self.relayeredSub == sub then
					return
				end
				self.relayered, self.relayeredSub = layer, sub
				self.strip.capL:SetDrawLayer(layer, sub)
				self.strip.capR:SetDrawLayer(layer, sub)
				self.strip.mid:SetDrawLayer(layer, sub - 1)
				if self.libraryBorder then
					self.libraryBorder:SetLayer(layer, sub)   -- (0.19.8: a library style in the bracket's place)
				end
				if not opts.troughParent then
					self.trough:SetDrawLayer(tl, ts)
				end
			end
			hooksecurefunc(parent, "SetStatusBarTexture", function()
				if rep.object:IsShown() then
					rep:Relayer()
				end
			end)
		end
		-- the caps' solid arms (from the piece's edge to its opening) in UI px
		rep.GetArms = function(self)
			if self.libraryStyle then
				return 0, 0   -- (0.19.8: a library style lies round the bar: no arm takes its width)
			end
			local sc = self.strip.scale
			local capL, capR = PIECES[StripName(self.base, "cap_l")], PIECES[StripName(self.base, "cap_r")]
			local l = capL and capL.open and capL.open[1] * sc or self.strip.wl or 0
			local r = capR and capR.open and (capR.w - capR.open[3]) * sc or self.strip.wr or 0
			return l, r
		end
		-- the bracket's fill area as insets from the rect: sideways from the
		-- caps' hollow arms (past the gems) a little under the gems' bezels,
		-- top / bottom most of the way into the rails, so the rails cover the edges
		-- (0.20.1) the panel's art scale, and the share of the rect's height a library style's border lies round (the
		-- bracket's own fit: KitBorders' BarLibraryFit)
		rep.ArtScale = function()
			return opts.artScale or rule.artScale or 1
		end
		rep.LibraryShare = function(self)
			return (rule.heightScale or 1) * self:ArtScale()
		end
		-- the bar's frame, top to bottom, in UI px (a library border's band and rails, else the bracket's height):
		-- what a row's highlight fits (CharacterPanel's reputation and skill rows); nil while it reads nothing
		rep.OuterHeight = function(self)
			if self.libraryStyle and self.libBand and self.libraryBorder then
				local ok, h = pcall(self.libBand.GetHeight, self.libBand)
				if not ok or Secret(h) or not (h and h > 0) then
					return nil
				end
				local _, y = self.libraryBorder:Inset()
				return h + 2 * y
			end
			return self.strip and self.strip.height or nil
		end
		rep.GetOpening = function(self)
			if self.libraryStyle then
				-- (0.19.8: round the bar: the fill its whole width; 0.20.1: its height the band the border lies round)
				local rectH = self:RectSize("GetHeight")
				if not (rectH and rectH > 0) then
					rectH = self.fitHeight or 0
				end
				local m = rectH * (1 - self:LibraryShare()) / 2
				return 0, 0, m, m
			end
			local sc = self.strip.scale
			local mid = PIECES[StripName(self.base, "mid")]
			local under = (rule.underGem or 3) * sc
			local armL, armR = self:GetArms()
			-- a dropped or outward cap leaves the rect's whole width to the fill
			local dropL = self.strip.dropCap == "l" or self.strip.capless
			local dropR = self.strip.dropCap == "r" or self.strip.capless
			local l = (dropL or self.capOut) and 0 or armL - under
			local r = (dropR or self.capOut) and 0 or armR - under
			-- the fill's rows in the mid's canvas: `into` of the way through
			-- each rail (1: the bracket's whole height, the rails over fill)
			local into = rule.into or 1
			local rowT, rowB = 0, mid and mid.h or 0
			if mid and mid.open and mid.box then
				rowT = mid.open[2] - (mid.open[2] - mid.box[2]) * into
				rowB = mid.open[4] + (mid.box[4] - mid.open[4]) * into
			end
			-- the strip's canvas is centred on the rect's centre line, shifted
			-- by yoff (FitBox), and is canvasH tall: a canvas row's distance
			-- from the rect's top / bottom edge
			local rectH = self:RectSize("GetHeight")
			if not (rectH and rectH > 0) then
				rectH = self.fitHeight or 0
			end
			local canvasH = (mid and mid.h or 0) * sc
			local yoff = self.stripOffset or 0
			local top = rectH / 2 - yoff - canvasH / 2 + rowT * sc
			local bottom = rectH / 2 + yoff + canvasH / 2 - rowB * sc
			return l, r, top, bottom
		end
		rep.Refit = function(self)
			local h = self:RectSize("GetHeight")
			if not (h and h > 0) then
				h = self.fitHeight
			end
			if not (h and h > 0) then
				return
			end
			-- `thicken`: the bracket is that many UI px taller than the rect,
			-- centred on it (it overhangs the rect top and bottom)
			-- `heightScale`: the bracket that fraction of the rect's height,
			-- centred on it (the character pane's bars at 0.85 — user, 2026-09-21)
			-- `artScale` (opts or rule): the border ART drawn at that fraction
			-- of the scale the fit gives, in every Progress Bar Border look
			-- (thinner rails, smaller caps and gems, the opening with them), for
			-- one set of bars without touching the rule every window shares
			-- (user, 2026-09-24: the Reputation and Skills tabs' bars at 0.85).
			-- Every size below (arms, opening, caps) is read from the strip's
			-- scale, so the fill and the trough follow; kept in `opts`, so a
			-- live look swap (SetBar -> Refit) keeps it too
			local artScale = opts.artScale or rule.artScale or 1
			-- (rep.thicken: set by the panel that sets the fill in from the rect
			-- -- the nameplates', its edges at the rails' centres: NameplatePanel)
			local thicken = self.thicken or opts.thicken or rule.thicken or 0
			local yoff = self.strip:FitBox((h + thicken) * (rule.heightScale or 1) * artScale)
			self.stripOffset = yoff
			local w = self:RectSize("GetWidth")
			if not (w and w > 0) then
				w = self.fitWidth or 0
			end
			-- the caps: one dropped (the mid to that edge), the kept ones inside
			-- the rect or, with capOut, outside it by their solid arm
			local outL, outR = 0, 0
			if self.capOut then
				local armL, armR = self:GetArms()
				outL = self.strip.dropCap ~= "l" and armL or 0
				outR = self.strip.dropCap ~= "r" and armR or 0
			end
			self.strip:ClearAllPoints()
			self.strip:SetPoint("LEFT", self.rect, "LEFT", -outL, yoff)
			self.strip:SetPoint("RIGHT", self.rect, "RIGHT", outR, yoff)
			self.strip:SetHeight(self.strip.height)
			-- the cap test (capless when narrower than two caps) only for a
			-- bracket that drops or grows a cap: a window's P1 bars are meant
			-- to keep both caps even when they overlap (the 160 px stat bars)
			if self.strip.dropCap or self.capOut then
				self.strip:FitCaps(w + outL + outR)
			end
			local l, r, t, b = self:GetOpening()
			self.trough:ClearAllPoints()
			self.trough:SetPoint("TOPLEFT", self.rect, "TOPLEFT", l, -t)
			self.trough:SetPoint("BOTTOMRIGHT", self.rect, "BOTTOMRIGHT", -r, b)
			Kit:Retile(self.trough)
			if self.libraryStyle and Kit.BarLibraryFit then
				Kit:BarLibraryFit(self, h)   -- (0.20.1: the library border fitted to the bar as the bracket is)
			end
		end
		rep.SetBar = function(self, bar)
			-- (0.19.8) a style of the border library's: drawn by it round the
			-- bar, the bracket put out (Modules/KitBorders.lua); another look
			-- puts such a border away first
			if Kit.BarLibraryBorder and Kit:BarLibraryBorder(self, bar) then
				return
			end
			local b = "bars/" .. (bar or "frame")
			if b == self.base or not PIECES[StripName(b, "mid")] then
				return
			end
			self.base = b
			self.strip:SetBase(b)
			self:Refit()
		end
		rep:Refit()
		local show, hide = strip.Show, strip.Hide
		strip.Show = function(f)
			show(f)
			trough:Show()
			if rep.libraryStyle then
				rep.libraryBorder:SetShown(true)
			end
		end
		strip.Hide = function(f)
			hide(f)
			trough:Hide()
			if rep.libraryBorder then
				rep.libraryBorder:SetShown(false)
			end
		end
		-- (0.19.8) the group's look a library style: laid now
		if group and self.BarLibraryBorder then
			self:BarLibraryBorder(rep, opts.bar or self:BorderValue(group))
		end
	elseif rule.kind == "picture" then
		-- a painted picture on the rect, cropped to the rect's aspect (never
		-- stretched): `crop` says which part stays when the rect is wider
		-- than the picture ("bottom" / "top" / "middle"; columns are always
		-- centred). `grey` names the greyscale twin, shown while opts.grey()
		-- is true. `frame` lays the single-rail edges over it.
		-- `owner`: the picture is a REGION of the replaced texture's frame in
		-- that texture's layer and sublevel (a page's backdrop under the page's
		-- own children, whatever their levels: no holder, so no level tie);
		-- else a holder frame at `level`
		local f, tex, inner
		if rule.owner and not isFrame then
			local l, sl = region:GetDrawLayer()
			f = region:GetParent()
			tex = f:CreateTexture(nil, l or "BACKGROUND", nil, sl or 0)
			inner = CreateFrame("Frame", nil, f)
			inner:EnableMouse(false)
			-- opts.inset = { l, r, t, b } UI px: the picture stops short of the
			-- rect (inside the window's outer rail, so the rail stays in front)
			local ins = opts.inset or { 0, 0, 0, 0 }
			inner:SetPoint("TOPLEFT", rect, "TOPLEFT", ins[1], -ins[3])
			inner:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", -ins[2], ins[4])
		else
			f = MakeHolder(parent, rect, level, opts.strata)
			-- the picture stops at the rails' centre lines when a frame is over it
			-- (the rails cover its edges; past them it would show outside the
			-- frame): `inner` is the rect inset by each rail's centre
			inner = CreateFrame("Frame", nil, f)
			inner:EnableMouse(false)
			if rule.frame then
				local pre = self.framePrefix
				inner:SetPoint("TOPLEFT", f, "TOPLEFT", self:RailInset(pre .. "_l", "l"), -self:RailInset(pre .. "_t", "t"))
				inner:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -self:RailInset(pre .. "_r", "r"), self:RailInset(pre .. "_b", "b"))
			elseif opts.inset then
				-- opts.inset = { l, r, t, b }: inside the window's outer rail
				local ins = opts.inset
				inner:SetPoint("TOPLEFT", f, "TOPLEFT", ins[1], -ins[3])
				inner:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ins[2], ins[4])
			else
				inner:SetAllPoints(f)
			end
			tex = f:CreateTexture(nil, "BACKGROUND")
		end
		tex.kitScale = self.scale
		tex:SetAllPoints(inner)
		rep.object, rep.tex, rep.inner, rep.grey = (rule.owner and not isFrame) and tex or f, tex, inner, opts.grey
		-- `desaturate` (0..1): the picture's colour taken down that much (the
		-- secondary professions' cards at 10 % saturation: 0.9; user,
		-- 2026-09-24: "reduce the saturation of this Artwork to 10%")
		if rule.desaturate and tex.SetDesaturation then
			pcall(tex.SetDesaturation, tex, rule.desaturate)
		end
		-- `dim` (0..1): the picture darkened, a backdrop behind text (the
		-- crafting page's schematics: the recipe's name and reagents read
		-- over it -- user, 2026-09-24: "this is a bit hard to read")
		if rule.dim then
			tex:SetVertexColor(rule.dim, rule.dim, rule.dim)
		end
		-- `edge` = "brush": the picture ends in painted strokes on every side
		-- (Kit:PaintedEdge); `edgeMirror` flips them for a left-hand page
		if rule.edge then
			rep.edge = self:PaintedEdge(tex, inner, rule.edgeMirror)
		end
		-- `parchment` (0.20.1): the page is the parchment nine on the picture's rect, in its layer (Kit:ParchmentNine;
		-- a string names its curls), the picture left hidden under it
		if rule.parchment then
			local l, sl = tex:GetDrawLayer()
			rep.paper = self:ParchmentNine(tex:GetParent(), { place = function(p) p:SetAllPoints(inner) end, layer = l,
				sublevel = sl, curls = type(rule.parchment) == "string" and rule.parchment or nil, scale = self.parchment.page })
			tex:Hide()
			if rep.object == tex then
				rep.object = rep.paper
			end
		end
		-- `edgeBacking`: a tiled piece right under the picture, on the same
		-- rect, so the gaps between the strokes show stone and not whatever
		-- lies behind the window (user, 2026-09-23: the quest log over the
		-- world map, MelloUI's quest list: "add the dark cracked concrete
		-- behind")
		if rule.edgeBacking then
			local layer, sub = tex:GetDrawLayer()
			sub = sub or 0
			if sub <= -8 then
				-- no sublevel left under the picture: the picture steps up one
				sub = -7
				tex:SetDrawLayer(layer, sub)
			end
			local backing = tex:GetParent():CreateTexture(nil, layer, nil, sub - 1)
			backing:SetAllPoints(inner)
			backing.kitScale = self.scale * self.frameScale
			if self:Apply(backing, rule.edgeBacking) then
				rep.backing = backing
			else
				backing:Hide()
			end
		end
		rep.Refit = function(self)
			-- rep:SetPiece(value): a panel's background choice in place of
			-- the rule's piece ("dark": a flat fill)
			if self.pieceOverride == "dark" then
				-- the palette's inner panel, by its key: a new palette paints
				-- it again (Kit:Paint)
				Kit:Paint(self.tex, "innerPanel", "fill", 0.95)
				Kit.pieceOf[self.tex], Kit.pieceNameOf[self.tex] = true, nil
				return
			end
			local name = self.pieceOverride or ((self.grey and rule.grey and self.grey()) and rule.grey or rule.piece)
			if Kit.pieceNameOf[self.tex] ~= name then
				Kit:Unpaint(self.tex)   -- (a dark fill before: the piece stays when the palette changes)
				Kit:Apply(self.tex, name)
				-- the parchment in the kit's one parchment tone
				if name == Kit.parchmentPiece then
					local t = Kit.parchmentTint
					self.tex:SetVertexColor(t[1], t[2], t[3])
				elseif rule.dim then
					self.tex:SetVertexColor(rule.dim, rule.dim, rule.dim)
				end
			end
			local p = PIECES[name]
			local w, h = self.inner:GetSize()
			if not (p and w and h and w > 0 and h > 0) then
				return
			end
			if self.edge then
				self.edge:Fit(w, h)
			end
			if self.backing then
				Kit:Retile(self.backing)
			end
			if p.tile then
				-- a background: repeated at the UI's one background
				-- resolution, never fitted by stretching; `crop` says where
				-- it starts (the middle, the top or the bottom of the rect)
				self.tex.kitAlign = (rule.crop == "top" and "top") or (rule.crop == "bottom" and "bottom") or "center"
				Kit:Retile(self.tex)
				return
			end
			local u1, u2, v1, v2 = p.uv[1], p.uv[2], p.uv[3], p.uv[4]
			local pa, ra = p.w / p.h, w / h
			if rule.fit == "right" then
				-- the whole picture at the rect's height, against its right
				-- edge (its subject is there); the rest of the rect, to the
				-- left, is the picture's own left columns mirrored, so the
				-- stone continues without a seam and nothing is cut off
				local picW = h * pa
				self.tex:ClearAllPoints()
				if picW >= w then
					self.tex:SetAllPoints(self.inner)
					self.tex:SetTexCoord(u2 - (u2 - u1) * (w / picW), u2, v1, v2)
					if self.filler then
						self.filler:Hide()
					end
					return
				end
				self.tex:SetPoint("TOPRIGHT", self.inner, "TOPRIGHT")
				self.tex:SetPoint("BOTTOMRIGHT", self.inner, "BOTTOMRIGHT")
				self.tex:SetWidth(picW)
				self.tex:SetTexCoord(u1, u2, v1, v2)
				if not self.filler then
					self.filler = self.object:CreateTexture(nil, "BACKGROUND")
					self.filler.kitScale = self.tex.kitScale
				end
				if Kit.pieceNameOf[self.filler] ~= name then
					Kit:Apply(self.filler, name)
				end
				self.filler:ClearAllPoints()
				self.filler:SetPoint("TOPLEFT", self.inner, "TOPLEFT")
				self.filler:SetPoint("BOTTOMRIGHT", self.tex, "BOTTOMLEFT")
				-- (in an atlas sheet never past the piece's own columns: a
				-- rect over twice the picture's width shows them stretched)
				local share = (w - picW) / picW
				if share > 1 and InSheet(p.file) then
					share = 1
				end
				self.filler:SetTexCoord(u1 + (u2 - u1) * share, u1, v1, v2)
				self.filler:Show()
				return
			end
			if ra > pa + 0.001 then
				local frac = pa / ra                 -- the visible share of the picture's height
				if rule.crop == "top" then
					v2 = v1 + (v2 - v1) * frac
				elseif rule.crop == "middle" then
					local c, half = (v1 + v2) / 2, (v2 - v1) * frac / 2
					v1, v2 = c - half, c + half
				else
					v1 = v2 - (v2 - v1) * frac
				end
			elseif ra < pa - 0.001 then
				local c, half = (u1 + u2) / 2, (u2 - u1) * (ra / pa) / 2
				u1, u2 = c - half, c + half
			end
			self.tex:SetTexCoord(u1, u2, v1, v2)
		end
		rep.SetPiece = function(self, value)
			local piece = value and (Kit.buttonLooks.backgroundPiece[value] or (PIECES[value] and value))
			self.pieceOverride = (value == "dark" and "dark") or piece or nil
			if not self.pieceOverride then
				local k = rule.dim or 1
				self.tex:SetVertexColor(k, k, k, 1)
			end
			self:Refit()
		end
		Perf.SetScript(inner, "OnSizeChanged", function() rep:Refit() end)
		-- a page hidden while the skin is built has no size to fit to (the
		-- whole painting would stay stretched on it): fit again when it shows
		Perf.SetScript(inner, "OnShow", function() rep:Refit() end)
		if rule.frame and rep.object == f then
			rep.skin = self:NineSlice(f, { scale = self.scale * self.frameScale, gems = false, body = false, prefix = self.framePrefix })
		end
		rep:Refit()
	elseif rule.kind == "fade" then
		-- nothing stands in: the region is faded while the skin is on. Its
		-- holder is made when something asks for rep.object (BareRep), or at
		-- once where the editing tools want one to move (their proxy, a tune)
		if tune or self.liveEdit then
			rep.object = MakeHolder(parent, rect, level, opts.strata)
		else
			rep.holderParent, rep.holderLevel, rep.holderStrata, rep.holderShown = parent, level, opts.strata, true
			setmetatable(rep, BareRep)
		end
	elseif rule.kind == "tile" then
		-- `owner`: the tile is a REGION of the replaced texture's frame in its
		-- layer (a list's body under the list's own children); else a holder
		local f, tex
		if rule.owner and not isFrame then
			-- rule.layer / sublevel: a place in the owner's stack other than the
			-- replaced region's (an empty slot's stone UNDER the icon)
			local l, sl = region:GetDrawLayer()
			f = region:GetParent()
			tex = f:CreateTexture(nil, rule.layer or l or "BACKGROUND", nil, rule.sublevel or sl or 0)
			tex:SetAllPoints(rect)
		else
			f = MakeHolder(parent, rect, level, opts.strata)
			tex = f:CreateTexture(nil, "BACKGROUND")
			tex:SetAllPoints(f)
			f.kitTile = tex
			Perf.SetScript(f, "OnSizeChanged", Holder_OnSize)
			Perf.HookScript(f, "OnShow", Holder_OnShow)
		end
		tex.kitScale = self.scale * (rule.scale or 1)
		-- (tiled by Refit below, once the edge is on)
		self:Apply(tex, rule.piece, true)
		rep.object, rep.tex = (rule.owner and not isFrame) and tex or f, tex
		-- `edge` = "brush": the tiled panel ends in painted strokes on every
		-- side (Kit:PaintedEdge), fitted again whenever its size changes
		local edge = rule.edge and self:PaintedEdge(tex, tex, rule.edgeMirror, rule.edgeTight) or nil
		rep.edge = edge
		local function Refit()
			Kit:Retile(tex)
			if edge then
				local okS, w, h = pcall(tex.GetSize, tex)
				if okS then
					edge:Fit(w, h)
				end
			end
		end
		if rep.object == tex then
			-- a region has no OnSizeChanged: re-tile on the rect's. opts.sizer:
			-- the rect itself when it is a frame of the caller's own (an action
			-- slot's opening), whose scripts serve, where a frame was made for it
			-- per slot (user, 2026-09-24: the bags' first open); not when the
			-- editing tools' proxy stands in as the rect
			local sizer = opts.sizer
			if sizer ~= rect then
				sizer = CreateFrame("Frame", nil, f)
				sizer:EnableMouse(false)
				sizer:SetAllPoints(rect)
			end
			sizer.kitRefit = Refit
			Perf.SetScript(sizer, "OnSizeChanged", Sizer_OnSize)
			Perf.HookScript(sizer, "OnShow", Sizer_OnShow)
		elseif edge then
			Perf.SetScript(f, "OnSizeChanged", Refit)
			Perf.HookScript(f, "OnShow", Refit)
		end
		Refit()
	elseif rule.kind == "texture" then
		-- `owner`: the piece is a REGION of the replaced texture's frame in its
		-- layer and sublevel (a level plate under the frame's own text); else
		-- on a holder frame
		local f, tex
		if rule.owner and not isFrame then
			-- rule.layer / sublevel: a place in the owner's stack other than
			-- the replaced region's (a party frame's ring under its name)
			local l, sl = region:GetDrawLayer()
			f = region:GetParent()
			tex = f:CreateTexture(nil, rule.layer or l or "ARTWORK", nil, rule.sublevel or sl or 0)
			tex.kitScale = self.scale
			self:Apply(tex, rule.piece)
		else
			f = MakeHolder(parent, rect, level, opts.strata)
			tex = self:Texture(f, rule.piece, "OVERLAY", 1, self.scale)
		end
		if rule.natural then
			tex:SetSize(self:Size(rule.piece, self.scale * (rule.scale or 1)))
			tex:SetPoint("CENTER", opts.center or rect, opts.centerPoint or "CENTER")
		elseif rule.fit == "height" then
			-- the rect's height, the piece's aspect, on the rect's `anchor`
			-- corner (a wide rail cap standing on a tall gryphon rect)
			local piece = PIECES[rule.piece]
			local okS, _, h = pcall(rect.GetSize, rect)
			if not okS or Secret(h) or not (h and h > 0) then
				h = 1
			end
			tex:SetSize(piece and h * piece.w / piece.h or h, h)
			tex:SetPoint(rule.anchor or "CENTER", rect, rule.anchor or "CENTER")
			if f ~= rect and f.SetScript then
				Perf.SetScript(f, "OnSizeChanged", function(_, _, nh)
					if nh and not Secret(nh) and nh > 0 then
						tex:SetSize(piece and nh * piece.w / piece.h or nh, nh)
					end
				end)
			end
		elseif rule.square or rule.opening then
			local function SquareSize(w, h)
				if not (w and h) or Secret(w) or Secret(h) then
					return 0
				end
				-- (0.19.8: the piece it wears, a ring style's as the portrait ring: rep.ringPiece, KitBorders)
				local piece = PIECES[rep.ringPiece or rule.piece]
				local size = math.min(w > 0 and w or h, h > 0 and h or w)
				-- (0.19.9) `body`: the ring's round body where that piece's would be (the winged border on a
				-- window's corner: the gem ring's body, its wings past the rect)
				local body = rule.body and PIECES[rule.body]
				if body and piece and piece.radius and body.radius and piece.radius > 0 then
					size = size * (piece.w / piece.radius) / (body.w / body.radius)
				end
				if size > 0 and rule.opening and piece and piece.open then
					-- the rect is the OPENING: the canvas grows around it by the
					-- piece's ratio (a ring around the game's own portrait);
					-- `openingScale` shrinks that (the minimap's ring at 0.75, its
					-- rim over the map's edge — user, 2026-09-21)
					size = size * piece.w / (piece.open[3] - piece.open[1]) * (rule.openingScale or 1)
				end
				return size
			end
			local okS, w, h = pcall(rect.GetSize, rect)
			local size = okS and SquareSize(w, h) or 0
			if size <= 0 then
				-- the rect gives no size yet (a proxy made this frame, a region
				-- not laid out, a secret read): the piece at its own size
				-- meanwhile -- never none, which draws it at its FILE's size, a
				-- whole atlas sheet (1024 x 512) -- and fitted once the rect has one
				size = (self:Size(rule.piece, self.scale))
				local sizer = CreateFrame("Frame", nil, f)
				sizer:EnableMouse(false)
				sizer:SetAllPoints(rect)
				Perf.SetScript(sizer, "OnSizeChanged", function(_, nw, nh)
					local s = SquareSize(nw, nh)
					if s > 0 then
						tex:SetSize(s, s)
					end
				end)
				rep.sizer = sizer   -- (it sizes the piece from the proxy, pads and all: LOOK.CenterTune)
			end
			tex:SetSize(size, size)
			tex:SetPoint("CENTER", opts.center or rect, "CENTER")
			-- (0.19.8) sized again for the piece it wears now, coming from piece `from` (Kit:LayPortraitRing): the
			-- opening kept at its size -- never read from the rect again, which a fitted portrait is itself sized
			-- by the ring (Kit:FitPortrait: it would feed back)
			rep.Resquare = function(from)
				local a, b = PIECES[from or rule.piece], PIECES[rep.ringPiece or rule.piece]
				local okW, tw = pcall(tex.GetWidth, tex)
				if not (okW and tw and not Secret(tw) and tw > 0 and a and b and a.open and b.open) then
					return
				end
				local s = tw * ((a.open[3] - a.open[1]) / a.w) / ((b.open[3] - b.open[1]) / b.w)
				tex:SetSize(s, s)
			end
		else
			tex:SetAllPoints(rule.owner and rect or f)
		end
		-- (0.19.1) a piece centred on something other than its rect (a portrait's ring on the portrait) follows the
		-- editor's drag by its own anchor: the holder moved with the proxy and the ring stayed; and it keeps its
		-- place when that something is moved under it (Kit:TuneRegion; user, 2026-10-04)
		if opts.center and (rule.natural or rule.square or rule.opening) then
			rep.centerOn, rep.centerPoint = opts.center, rule.natural and opts.centerPoint or nil
			LOOK.centeredOn[opts.center] = rep
		end
		rep.object, rep.tex = (rule.owner and not isFrame) and tex or f, tex
	end
	local object = rawget(rep, "object")
	if object then
		object:Hide()
		-- (a rim read while it was made, shown: its active look waits for the
		-- rep's Enable too)
		if object.Update == Slot_Update and self:RimDrivesLook(object) then
			self:SetActive(object.button, false)
		end
	else
		rep.holderShown = false
	end
	-- every window's outer rail and title plate are known to the window
	-- mover (UI Modifications), whichever panel dressed the window: the
	-- older panels replace these two by hand, not through SkinWindowShell
	-- (the window: WindowOf)
	if key == "TitleBar" and parent and parent.GetParent then
		local window = WindowOf(parent:GetParent())
		if window and window ~= UIParent then
			RegisterShell(window, { title = rep })
		end
	elseif key == "NineSlicePanelTemplate" and parent then
		local window = WindowOf(parent)
		if window and window ~= UIParent then
			RegisterShell(window, { outer = rep })
		end
	elseif key == "UI-Frame-PortraitMetal-CornerTopLeft" and parent then
		local window = WindowOf(parent)
		if window and window ~= UIParent then
			RegisterShell(window, { ring = rep })
		end
	elseif (key == "MelloUI-Crest" or key == "MelloUI-TitlePlate") and parent then
		-- an own window's crest and the short plate under it (Kit:OwnWindow:
		-- their frames the window's own children): known for their shade,
		-- never a drag handle or a ring. A crest inside a page (the
		-- installer's Keep ring) is no part of the window's outline.
		local window = WindowOf(parent)
		if window and window ~= UIParent and parent:GetParent() == window then
			RegisterShell(window, key == "MelloUI-Crest" and { crest = rep } or { plate = rep })
		end
	end
	rep.window = WindowOf(parent)
	self:RegisterReplacement(rep)
	if tune then
		self:TuneObject(rep, tune)
	end
	return rep
end

-- A MinimalScrollBar (Blizzard_SharedXML/Shared/Scroll/MinimalScrollBar.xml):
-- Track with Begin / Middle / End textures and the Thumb button (its own
-- Begin / Middle / End, re-atlased on hover / press), Back and Forward
-- stepper buttons with one Texture each. The game shows and hides the bar,
-- the track and the thumb itself; the pieces are children of theirs.
-- `replace` is the panel's registering Replace. Returns the reps (or nil).
function Kit:SkinScrollBar(bar, replace)
	if Kit.repOf[bar] ~= nil then
		return Kit.repOf[bar] or nil
	end
	local track, thumb = bar.Track, bar.Track and bar.Track.Thumb
	if not (track and thumb and track.Middle and thumb.Middle) then
		Kit.repOf[bar] = false
		return nil
	end
	local reps = {}
	reps[#reps + 1] = replace(track.Middle, { as = "minimal-scrollbar-track-middle", rect = track, alsoFade = { track.Begin, track.End } })
	reps[#reps + 1] = replace(thumb.Middle, { as = "minimal-scrollbar-small-thumb-middle", rect = thumb, button = thumb, alsoFade = { thumb.Begin, thumb.End } })
	if bar.Back and bar.Back.Texture then
		reps[#reps + 1] = replace(bar.Back.Texture, { as = "minimal-scrollbar-arrow-top", button = bar.Back })
	end
	if bar.Forward and bar.Forward.Texture then
		reps[#reps + 1] = replace(bar.Forward.Texture, { as = "minimal-scrollbar-arrow-bottom", button = bar.Forward })
	end
	-- the thumb's height follows the content: refit when it changes
	Perf.HookScript(thumb, "OnSizeChanged", function()
		for _, rep in ipairs(reps) do
			if rep.vstrip and rep.object:IsShown() then
				rep:Refit()
			end
		end
	end)
	Kit.repOf[bar] = reps
	return reps
end

-- A frame's children without a table per frame (user, 2026-09-24: the
-- walks below built { root:GetChildren() } at every frame they visited, ~0.16
-- KB each, hundreds a walk): packed into a list kept per level of the walk
-- and used again. A list still in use (a walk started from inside another,
-- a walk an error left) is left to it, and that level gets a new one.
local walkLists = {}   -- [depth] = { busy = , [1..n] = children }

-- eight at a time: select() copies only what follows, never a table
local function Fill(list, i, n, a, b, c, d, e, f, g, h, ...)
	list[i], list[i + 1], list[i + 2], list[i + 3] = a, b, c, d
	list[i + 4], list[i + 5], list[i + 6], list[i + 7] = e, f, g, h
	if n > 8 then
		return Fill(list, i + 8, n - 8, ...)
	end
end
local function Pack(list, ...)
	local n = select("#", ...)
	if n > 0 then
		Fill(list, 1, n, ...)
	end
	return n
end

-- the list of `frame`'s children for a walk at `depth`, and how many; hand
-- it back with WalkDone when the walk is through it
local function WalkChildren(frame, depth)
	local list = walkLists[depth]
	if not list or list.busy then
		list = {}
		walkLists[depth] = list
	end
	list.busy = true
	return list, Pack(list, frame:GetChildren())
end
local function WalkDone(list)
	list.busy = false
end

-- Every MinimalScrollBar under `root` (a frame with Track / Thumb / Back /
-- Forward), skinned with `replace`; `skip` is a frame never walked into.
-- The same walk asked for again in one frame (the same root, replace and
-- skip) with no frame made anywhere since (GetNumFrames) has nothing new to
-- find and is not walked again (user, 2026-09-24: the walk asked for twice
-- and three times in the frame a window opened; the world map's and the quest
-- map's shows both ask for it -- the spell book keeps its own once a frame).
-- Only within the frame: a later show walks again, so a scroll bar moved in
-- under the root since (a reparent makes no frame) is still found.
local walked = setmetatable({}, { __mode = "k" })   -- [root] = { at, frames, replace, skip }
local GetNumFrames = _G.GetNumFrames

function Kit:SkinScrollBarsIn(root, replace, skip, depth)
	local top = depth == nil
	depth = depth or 0
	if depth > 7 or root == skip then
		return
	end
	local last = top and GetNumFrames and walked[root]
	if last and last.replace == replace and last.skip == skip and last.at == GetTime() and last.frames == GetNumFrames() then
		return
	end
	local list, n = WalkChildren(root, depth)
	for i = 1, n do
		local child = list[i]
		if child.Track and child.Track.Thumb and child.Back and child.Forward then
			self:SkinScrollBar(child, replace)     -- `replace` enables the reps itself when the skin is active
		else
			self:SkinScrollBarsIn(child, replace, skip, depth + 1)
		end
	end
	WalkDone(list)
	if top and GetNumFrames then
		last = walked[root]
		if not last then
			last = {}
			walked[root] = last
		end
		last.at, last.frames, last.replace, last.skip = GetTime(), GetNumFrames(), replace, skip
	end
end

-- A glyph the game re-atlases with a state (a header's +/-, a toggle's
-- open/closed): one replacement per atlas it has shown, kept on `owner`
-- (Kit.stateIconsOf[owner]), the one for its current atlas shown. `replace` is the
-- panel's registering Replace; `extra` other regions to fade with it.
function Kit:StateIconReps(owner, icon, button, replace, extra)
	if not (owner and icon) then
		return
	end
	Kit.stateIconsOf[owner] = Kit.stateIconsOf[owner] or {}
	local key = self:ArtKey(icon)
	if key and self:RuleFor(key) and Kit.stateIconsOf[owner][key] == nil then
		local rep = replace(icon, { as = key, button = button or owner, rect = icon, alsoFade = extra }) or false
		Kit.stateIconsOf[owner][key] = rep
		if rep then
			local enable = rep.onEnable
			rep.onEnable = function(...)
				if enable then
					enable(...)
				end
				Kit:StateIconReps(owner, icon, button, replace, extra)
			end
		end
	end
	for k, rep in pairs(Kit.stateIconsOf[owner]) do
		if rep then
			rep:SetShown(k == key)
		end
	end
end

-- Distance from a rail piece's outer edge to the centre line of its rail, in
-- UI units at `scale` (the edges carry a transparent pad on the outside).
-- `side` is the piece's outer side: "t", "b", "l" or "r".
function Kit:RailInset(name, side, scale)
	local p = PIECES[name]
	if not (p and p.box) then
		return 0
	end
	scale = scale or (self.scale * self.frameScale)
	if side == "t" then
		return (p.box[2] + p.box[4]) / 2 * scale
	elseif side == "b" then
		return (p.h - (p.box[2] + p.box[4]) / 2) * scale
	elseif side == "l" then
		return (p.box[1] + p.box[3]) / 2 * scale
	end
	return (p.w - (p.box[1] + p.box[3]) / 2) * scale
end

-- A cover on a junction of rails (the RailJoint rule): the piece centred where
-- the vertical rail of `x` (an `edge` replacement) crosses the horizontal
-- line `dy` UI units above the bottom edge of `y` (a frame or region), or
-- its top when opts.yPoint is "TOP", or its centre line ("CENTER", e.g. a
-- rail texture). A point in WoW carries both
-- coordinates, so a helper frame spans from the rail's bottom to that line
-- and the piece sits on the helper's top-left corner: the line must lie above
-- the rail's bottom, and y's right edge right of the rail.
--   Kit:Joint(parent, { x = rep, y = frame, yPoint = , dy = , level = })
function Kit:Joint(parent, opts)
	local rail, rect = opts.x, opts.x.rect
	local w = rect:GetWidth()
	local p = PIECES[rail.rule.piece]
	-- the edge is stretched across its rect: the rail's centre in that width
	local dx = (p and p.box and p.w > 0) and ((p.box[1] + p.box[3]) / 2 / p.w) * w or w / 2
	local helper = CreateFrame("Frame", nil, parent)
	helper:EnableMouse(false)
	helper:SetPoint("BOTTOMLEFT", rect, "BOTTOMLEFT", dx, 0)
	local yp = opts.yPoint == "TOP" and "TOPRIGHT" or opts.yPoint == "CENTER" and "RIGHT" or "BOTTOMRIGHT"
	helper:SetPoint("TOPRIGHT", opts.y, yp, 0, opts.dy or 0)
	return self:Replace(helper, { as = "RailJoint", parent = parent, rect = helper, noFade = true, level = opts.level, centerPoint = "TOPLEFT" })
end

--------------------------------------------------------------------------------
-- Shared window parts (2026-09-21, for the legacy, quest log and guild
-- windows): the same code the character / professions / spell book panels
-- carry inline, once. Every helper takes the panel's registering `replace`
-- (so the reps land in that panel's skin) and returns what it made.
--------------------------------------------------------------------------------

-- The first game texture of a frame (skipping ours).
function Kit:FirstTexture(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not Kit.pieceOf[region] then
			return region
		end
	end
end

-- Every game texture of a button but `keep` (to fade with its normal art).
function Kit:OtherTextures(button, keep)
	local extra = {}
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= keep and not Kit.pieceOf[region] then
			extra[#extra + 1] = region
		end
	end
	return extra
end

-- How far the window's OUTER rail (the NineSlicePanelTemplate rule, grown
-- outward by `outset`) reaches INTO the window on each side, in UI px:
-- { l, r, t, b }. A page picture inset by this stops at the rail's inner
-- bevel, so the rail is in front of it (user, 2026-09-21).
function Kit:OuterRailInset()
	local rule = self:WindowFrameRule()
	local prefix = rule and rule.prefix or "window/frame"
	local sc = self.scale * (rule and rule.scale or self.frameScale)
	local outset = rule and rule.outset or 0
	local function side(name, inner)
		local p = PIECES[name]
		if not (p and p.box) then
			return 0
		end
		local depth = inner == "r" and p.box[3] or inner == "l" and (p.w - p.box[1]) or inner == "b" and p.box[4] or (p.h - p.box[2])
		return math.max((depth - outset) * sc, 0)
	end
	return { side(prefix .. "_l", "r"), side(prefix .. "_r", "l"), side(prefix .. "_t", "b"), side(prefix .. "_b", "t") }
end

-- The class medallion's size in the character window's ring: the size every
-- portrait icon and ring disc is brought to (WINDOW-RULES 2b).
local MEDALLION_TO_RING = 0.759
-- the class medallion's painted disc spans this much of its texture (the
-- plain variant's opaque width: 243 of 256 px)
local MEDALLION_DISC = 0.95

-- The class medallion's size in a ring's texture (0.759 x the gem ring). A
-- ring of another share of opening to width (a ring style, 0.19.8; the
-- windows' winged border, 0.19.9) keeps the gem ring's medallion-to-opening
-- measure. Kit:FitPortrait and Kit:RingDisc size by it.
function Kit:MedallionSize(tex)
	local size = tex:GetWidth() * MEDALLION_TO_RING
	local worn, gem = PIECES[Kit.pieceNameOf[tex] or ""], PIECES["window/portrait_ring"]
	if worn and gem and worn.open and gem.open and worn.w ~= gem.w then
		size = size * ((worn.open[3] - worn.open[1]) / worn.w) / ((gem.open[3] - gem.open[1]) / gem.w)
	end
	return size
end

-- A dark disc in a portrait ring's opening, under the portrait (an agreed
-- addition, user 2026-09-21: the Legacy shield does not fill the ring, the
-- page showed through). A region of the ring holder's parent (the game's
-- PortraitContainer, level 400: its portrait is OVERLAY, the disc goes in
-- BACKGROUND under it), masked round with the game's own circle mask, the
-- class medallion's size on the ring's centre; shown / hidden with the
-- ring's replacement. `color`: a palette key, "innerPanel" when none is
-- given (painted by its key, Kit:Paint, so a new palette paints it again).
-- `parent` / `sublevel` override the frame and BACKGROUND sublevel the disc is
-- a region of, for a window whose portrait lives elsewhere (the guild window's
-- PortraitOverlay at level 300, its portrait BACKGROUND 1: the disc at 0).
function Kit:RingDisc(ring, color, parent, sublevel)
	if not (ring and ring.tex and ring.object) then
		return nil
	end
	parent = parent or ring.object:GetParent()
	local disc = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel or 7)
	Kit.pieceOf[disc] = true
	self:Paint(disc, color or "innerPanel", "fill", 1)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(disc)
	disc:AddMaskTexture(mask)
	-- the disc is the class medallion's size (0.759 x the ring, user
	-- 2026-09-21), the same as a portrait fitted by Kit:FitPortrait
	local function Fit()
		local size = Kit:MedallionSize(ring.tex)
		disc:SetSize(size, size)
		disc:ClearAllPoints()
		disc:SetPoint("CENTER", ring.tex, "CENTER")
	end
	Fit()
	ring.disc = disc
	local onEnable, onDisable = ring.onEnable, ring.onDisable
	ring.onEnable = function(r)
		if onEnable then onEnable(r) end
		Fit()
		disc:Show()
	end
	ring.onDisable = function(r)
		if onDisable then onDisable(r) end
		disc:Hide()
	end
	disc:SetShown(ring.object:IsShown())
	return disc
end

-- The title plate riding the outer rail (the TitleBar rule's `onRail`):
-- the lift of the plate's centre above the window's top edge and how far each
-- end reaches past the rail's outer edge, so that its caps' gems sit where the
-- rail's own corner gems were, their centres on the rail's middle line.
local RAIL_GEM_IN = 20            -- the corner gems' centres, piece px in from the rail's outer corner (window/frame_gem_tl / _tr)
local CAP_GEM = { x = 48, y = 50 } -- the gem's centre in a tabs/top cap's canvas, from its outer end and its top

-- The OUTER rail's middle line, in UI px ABOVE the window's top edge (the band
-- is grown outward by `outset`, its box measured from the piece's top): where
-- the title plate's gems ride (Kit:TitleOnRail) and the configurator's crest
-- is centred (Kit:OwnWindow)
function Kit:RailMiddle()
	local rule = self:WindowFrameRule()
	local prefix = rule and rule.prefix or "window/frame"
	local sc = self.scale * (rule and rule.scale or self.frameScale)
	local rail = PIECES[prefix .. "_t"]
	local top, bottom = 0, 0
	if rail and rail.box then
		top, bottom = rail.box[2], rail.box[4]
	end
	return ((rule and rule.outset or 0) - (top + bottom) / 2) * sc
end

-- How far a title goes up from a strip's centre to sit on its PAINTED box,
-- not its canvas (the box sits lower in the canvas: a title centred on the
-- canvas read as riding high -- user, 2026-09-21). The rail's title plate
-- and the configurator's short plate (Kit:OwnWindow) centre theirs by it.
function Kit:StripTextOffset(strip)
	local mid = strip and PIECES[StripName(strip.base, "mid", strip.state)]
	if not (mid and mid.box) then
		return 0
	end
	return (mid.h / 2 - (mid.box[2] + mid.box[4]) / 2) * (strip.scale or self.scale)
end

function Kit:TitleOnRail(strip)
	local rule = self:WindowFrameRule()
	local sc = self.scale * (rule and rule.scale or self.frameScale)
	local middle = self:RailMiddle()
	local ss = strip.scale or self.scale
	local cap = PIECES[StripName(strip.base, "cap_l", strip.state)]
	local capH = cap and cap.h or 0
	-- the gem sits below the canvas's centre: the plate's centre goes that much higher
	local lift = middle + (CAP_GEM.y - capH / 2) * ss
	local reach = CAP_GEM.x * ss - RAIL_GEM_IN * sc
	return lift, reach
end

-- The title plate and the outer rail run behind the portrait ring (user,
-- 2026-09-23: "mask the overlapping header ... the header is actually going
-- behind the Round border and icon and disappearing", then the rail's corner
-- past the ring too): Masks/ring_corner hides a round hole under the ring, a
-- little inside its body so its rim covers the cut, and the whole quarter
-- above and left of its centre (CLAMP: its top row and left column repeat
-- outward, so that quarter reaches on and all else stays shown). The ring is
-- drawn above the plate, its top gem over it, and stands as the corner.
local RING_HOLE = EDGE_ROOT .. "ring_corner"
local RING_HOLE_FILL = 62 / 64   -- the hole's radius in the mask, as a share of its half-size (Tools/make_ring_corner_mask.py)
local RING_HOLE_IN = 6           -- piece px: the cut this far inside the ring's body radius, under its rim

function Kit:FitRingHole(title, ring)
	local strip, tex = title.strip, ring.tex
	local mask = strip and strip.ringHole
	if not (mask and tex) then
		return
	end
	local ok, w = pcall(tex.GetWidth, tex)
	if not ok or Secret(w) or not (w and w > 0) then
		return
	end
	local piece = PIECES[Kit.pieceNameOf[tex] or "window/portrait_ring"]
	local radius = ((piece and piece.radius) or 84) - RING_HOLE_IN
	local hole = w * radius / ((piece and piece.w) or 197)
	local size = 2 * hole / RING_HOLE_FILL
	for _, m in ipairs({ mask, title.outerCut }) do
		m:ClearAllPoints()
		m:SetPoint("CENTER", tex, "CENTER")
		m:SetSize(size, size)
	end
	-- the ring over the plate
	local holder = ring.object
	if holder and holder.SetFrameLevel and holder ~= tex then
		local level = strip:GetFrameLevel()
		if holder:GetFrameLevel() <= level then
			holder:SetFrameLevel(level + 2)
		end
	end
end

-- (0.19.0) The ring's rim -- its round body, not the gems that stand out of
-- it -- as a share of its texture's width, `tuck` piece px inside the rim's
-- edge (a glow lying under the ring starts under the rim: no gap between the
-- two -- HealerFrames' debuff glow; user, 2026-10-04)
function Kit:RingRim(tex, tuck)
	local piece = PIECES[(tex and Kit.pieceNameOf[tex]) or "window/portrait_ring"]
	local radius = ((piece and piece.radius) or 84) - (tuck or 0)
	return 2 * radius / ((piece and piece.w) or 197)
end

-- The portrait ring's centre, in UI px right of the window's left edge (nil
-- until both are laid out)
function Kit:RingCentreX(ring, window)
	local tex = ring and ring.tex
	if not (tex and window) then
		return nil
	end
	local okC, cx = pcall(tex.GetCenter, tex)
	local okL, left = pcall(window.GetLeft, window)
	if not (okC and okL and cx and left) or Secret(cx) or Secret(left) then
		return nil
	end
	local k = tex:GetEffectiveScale() / window:GetEffectiveScale()
	return cx * k - left
end

-- One cut of the ring's corner on a frame's textures (its own mask: a mask
-- only works on textures of the frame that made it)
local function RingCut(owner, textures)
	local mask = owner:CreateMaskTexture()
	mask:SetTexture(RING_HOLE, "CLAMP", "CLAMP")
	local seen = {}
	for _, t in ipairs(textures) do
		if t and not seen[t] and t.AddMaskTexture and t:GetParent() == owner then
			seen[t] = true
			t:AddMaskTexture(mask)
		end
	end
	return mask
end

function Kit:TitleBehindRing(title, ring, outer)
	local strip = title and title.strip
	if not (strip and ring and ring.tex and strip.CreateMaskTexture) then
		return
	end
	-- the outer rail's corner past the ring (its top and left rails, the
	-- corner, the stone under them)
	local skin = outer and outer.skin
	if skin and not title.outerCut and skin.CreateMaskTexture then
		local list = {}
		for _, t in ipairs(skin.all or {}) do
			list[#list + 1] = t
		end
		for _, t in ipairs(skin.art or {}) do
			list[#list + 1] = t
		end
		title.outerCut = RingCut(skin, list)
	end
	if not strip.ringHole then
		local mask = strip:CreateMaskTexture()
		mask:SetTexture(RING_HOLE, "CLAMP", "CLAMP")
		for _, k in ipairs({ "capL", "mid", "capR", "endL", "endR" }) do
			local t = strip[k]
			if t and t.AddMaskTexture then
				t:AddMaskTexture(mask)
			end
		end
		strip.ringHole = mask
		-- fitted again with the plate
		local refit = title.Refit
		title.Refit = function(me, ...)
			refit(me, ...)
			Kit:FitRingHole(me, ring)
		end
		-- the plate starts at the ring from now on (its Refit reads this)
		title.behindRing = ring
		if title.object and title.object:IsShown() then
			title:Refit()
			return
		end
	end
	self:FitRingHole(title, ring)
end

-- How far the window's OUTER rail grows outward past the window's edge, in
-- UI px (the NineSlicePanelTemplate rule's `outset` at its scale): two
-- windows side by side need twice this between them, or their rails overlap.
function Kit:OuterRailOutset()
	local rule = self:WindowFrameRule()
	if not (rule and rule.outset) then
		return 0
	end
	return rule.outset * self.scale * (rule.scale or self.frameScale)
end

-- A square rect for a slot rim whose OPENING is `iconSize` (a rim on an
-- icon that is not the button's whole rect: a 67 px ring icon, a 50 px
-- masked challenge icon): a child of `parent` centred on `center`, sized from
-- the piece's opening (rim = icon x canvas / opening), so the icon fills the
-- rim's hollow and is never squashed. `kind` is "slot" or "roundslot".
-- `into` (0..1) lets the icon run under the bezel: 0 = the icon fills the
-- hollow only, 1 = it reaches the rim's outer edge; 0.5 (the default for a
-- round icon the game rings thinly) puts the icon's edge under the middle
-- of the bezel, so the rim is smaller than icon x canvas / opening (a 67 px
-- tree icon gets an 84 px rim instead of 110, which overlapped its neighbours).
function Kit:RimRect(parent, kind, iconSize, center, into)
	local name = "buttons/" .. (kind or "slot") .. "_normal"
	local piece = PIECES[name]
	local l, r = self:Insets(name, 1)
	into = into or 0.5
	local size = iconSize * 1.35
	if piece and l then
		local opening = piece.w - l - r
		size = iconSize * piece.w / (opening + (piece.w - opening) * into)
	end
	local f = CreateFrame("Frame", nil, parent)
	f:EnableMouse(false)
	f:SetSize(size, size)
	f:SetPoint("CENTER", center or parent, "CENTER")
	return f
end

-- A PortraitFrameTemplate / ButtonFrameTemplate window's shell: the outer
-- rail with gem corners, the streak band, the ring on the portrait corner,
-- the title plate, the close button and the maximize / minimize pair.
--   Kit:SkinWindowShell(frame, replace, skin, { portrait = , noRing = , streaks = })
-- Returns the ring rep (skin.ring) when made.
function Kit:SkinWindowShell(frame, replace, skin, opts)
	opts = opts or {}
	if frame.NineSlice then
		-- a window whose Bg becomes the page stone (opts.bg) gets the rail
		-- WITHOUT its body: the rail's own stone tile filled the rect in a
		-- holder at the window's level, tied with the window's own stone
		-- region, and which of the two drew on top changed between loads
		-- (user, 2026-09-22: backgrounds "randomly changing between the
		-- dark and the light cracked stone"). One background per window.
		local body = opts.body
		if body == nil and opts.bg then
			body = false
		end
		replace(frame.NineSlice, { as = "NineSlicePanelTemplate", parent = frame, rect = opts.rect or frame, skip = (not opts.noRing) and "tl" or nil, body = body })
	end
	if frame.TopTileStreaks then
		replace(frame.TopTileStreaks, { as = "_UI-Frame-TopTileStreaks", parent = frame })
	end
	if frame.Bg and opts.bg then
		-- ONE picture for the whole window, inside the outer rail (the game's
		-- rock starts below the title area; a second picture for that strip
		-- met the first with a seam — user, 2026-09-21), as the Legacy pages
		replace(frame.Bg, { as = opts.bg, parent = frame, rect = frame, inset = self:OuterRailInset() })
	end
	local portrait = opts.portrait or (frame.PortraitContainer and frame.PortraitContainer.portrait)
	local corner = frame.NineSlice and frame.NineSlice.TopLeftCorner
	if portrait and corner and not opts.noRing then
		skin.ring = replace(corner, { as = "UI-Frame-PortraitMetal-CornerTopLeft", parent = frame.PortraitContainer or frame, center = portrait })
	end
	local tc = frame.TitleContainer
	if tc then
		local bg = self:FirstTexture(tc)
		if bg then
			replace(bg, { as = "TitleBar", parent = tc, rect = tc })
		else
			replace(tc, { as = "TitleBar", parent = tc, rect = tc, noFade = true })
		end
	end
	-- (the shell is registered by Kit:Replace itself, on the TOP window under
	-- UIParent: a page inside a window — the group finder's — must move its
	-- parent, which owns the close button and the side tabs; a second entry
	-- for the page here overrode that mover — user, 2026-09-21)
	local close = frame.CloseButton
	if close and close.GetNormalTexture and close:GetNormalTexture() then
		replace(close:GetNormalTexture(), { as = "RedButton-Exit", button = close, alsoFade = self:OtherTextures(close, close:GetNormalTexture()) })
	end
	-- maximize / minimize: two buttons, the game shows one at a time
	local mm = frame.MaximizeMinimizeFrame or frame.MaximizeMinimizeButton
	for _, entry in ipairs({ { mm and mm.MaximizeButton, "RedButton-Expand" }, { mm and mm.MinimizeButton, "RedButton-Condense" } }) do
		local b, key = entry[1], entry[2]
		if b and b.GetNormalTexture and b:GetNormalTexture() then
			local rep = replace(b:GetNormalTexture(), { as = key, button = b, alsoFade = self:OtherTextures(b, b:GetNormalTexture()) })
			if rep and skin.followers then
				skin.followers[#skin.followers + 1] = { rep = rep, region = b }
			end
		end
	end
	return skin.ring
end

-- The portrait fitted into the ring's opening like the class medallion
-- (0.759 x the ring, its aspect kept, on the portrait's own centre); the
-- game's size and anchors are kept on the portrait and put back by
-- Kit:UnfitPortrait. `ring` is the ring rep (skin.ring).

function Kit:FitPortrait(portrait, ring, mode)
	if not (portrait and ring and ring.tex) then
		return
	end
	if not Kit.portraitSavedOf[portrait] then
		local points = {}
		for i = 1, portrait:GetNumPoints() do
			points[i] = { portrait:GetPoint(i) }
		end
		local cx, cy = portrait:GetCenter()
		local px, py = portrait:GetParent():GetLeft(), portrait:GetParent():GetTop()
		if not (cx and px) then
			return             -- not laid out yet (the window hidden): try again on the next refresh
		end
		Kit.portraitSavedOf[portrait] = { points = points, w = portrait:GetWidth(), h = portrait:GetHeight(),
			cx = cx - px, cy = cy - py }
	end
	local saved = Kit.portraitSavedOf[portrait]
	local size = self:MedallionSize(ring.tex)
	if type(mode) == "number" then
		-- a factor on the medallion size. No window uses it: a window's
		-- portrait stays at the medallion size, on the disc when it does not
		-- cover the opening (WINDOW-RULES 2b; the social window's 1.3 x
		-- outgrew its ring — user, 2026-09-24)
		size = size * mode
	elseif mode == "opening" then
		-- the HUD's unit frames (user, 2026-09-21): the visible disc exactly
		-- the ring's opening — a class medallion's painted disc, else the
		-- whole (round-masked) portrait
		local piece = PIECES[Kit.pieceNameOf[ring.tex] or "window/portrait_ring"]
		local openFrac = piece and piece.open and (piece.open[3] - piece.open[1]) / piece.w or 0.61
		local okT, file = pcall(portrait.GetTexture, portrait)
		local medallion = okT and type(file) == "string" and file:find("MelloUI", 1, true) ~= nil
		size = ring.tex:GetWidth() * openFrac / (medallion and MEDALLION_DISC or 1)
	end
	local w, h = saved.w, saved.h
	if size > 0 and saved.cx and w > 0 and h > 0 then
		local k = size / math.max(w, h)
		portrait:ClearAllPoints()
		portrait:SetPoint("CENTER", portrait:GetParent(), "TOPLEFT", saved.cx, saved.cy)
		portrait:SetSize(w * k, h * k)
		self:RefitRegion(portrait)   -- (a portrait moved in the kit editor stays moved)
	end
end

function Kit:UnfitPortrait(portrait)
	local saved = portrait and Kit.portraitSavedOf[portrait]
	if saved then
		portrait:ClearAllPoints()
		for _, pt in ipairs(saved.points) do
			portrait:SetPoint(unpack(pt))
		end
		portrait:SetSize(saved.w, saved.h)
		Kit.portraitSavedOf[portrait] = nil
		self:RefitRegion(portrait)
	end
end

--------------------------------------------------------------------------------
-- Side tabs (user, 2026-09-23: "all Category Side Tab Buttons should be
-- mimicing the same size and appearence as the ones on the Character Pane and
-- Vice Versa, setting the Character Pane as the Default"): every
-- common-sidetab replacement is registered here. A tab of another window is
-- given the Character window's tab size (the button itself, so it grows the
-- way the game anchors it and its neighbours follow; the rim on it, the icon
-- fitted again); every tab wears one Side Tab Border (UI Modifications'
-- `sideTabBorder`: "slot" the Character window's gem slot, else a thin rim
-- look), changed on all of them at once.
--------------------------------------------------------------------------------

Kit.sideTabLooks = {
	{ value = "slot", label = "Gem slot", piece = "buttons/slot_checked" },
	{ value = "rim", label = "Thin iron", piece = "buttons/rim_checked" },
	{ value = "rimhair", label = "Hairline", piece = "buttons/rimhair_checked" },
	{ value = "rimround", label = "Rounded corners", piece = "buttons/rimround_checked" },
	{ value = "rimgold", label = "Iron with gold line", piece = "buttons/rimgold_checked" },
	{ value = "rimsunk", label = "Sunk", piece = "buttons/rimsunk_checked" },
}
local SIDE_TAB_FALLBACK = 48       -- UI px, until the Character window's tab can be measured
local SIDE_TAB_SCALE = 0.8         -- the rims 20 % smaller than the Character window's tab (user, 2026-09-23: "scale down their border by 20%"), the icons filling them
local sideTabs = {}                -- { tab, rep, reference, saved = { w, h } }

-- The Character window's side tab: its size is every side tab's
local function IsReferenceTab(tab)
	local name = tab and tab.GetName and tab:GetName()
	return name and name:find("^CharacterFrameModeTab%d") ~= nil
end

function Kit:SideTabSize()
	-- the size of the rim it shows: its Background's (the rim's rect there)
	local tab = _G.CharacterFrameModeTab1
	local ref = tab and (tab.Background or tab)
	if ref then
		local ok, w, h = pcall(ref.GetSize, ref)
		if ok and w and h and not Secret(w) and not Secret(h) and w > 1 and h > 1 then
			return w, h
		end
	end
	return SIDE_TAB_FALLBACK, SIDE_TAB_FALLBACK
end

local function SideTabBase()
	local um = MelloUI:GetModule("UIModifications")
	local value = um and um.db and um.db.sideTabBorder or "slot"
	for _, look in ipairs(Kit.sideTabLooks) do
		if look.value == value then
			return "buttons/" .. value
		end
	end
	return "buttons/slot"
end

-- The look on one tab's rim (its glow is its checked look, drawn additively)
local function SideTabLook(entry)
	local rim = entry.rep and entry.rep.object
	if not (rim and rim.base) then
		return
	end
	local base = SideTabBase()
	Kit:SetSlotBase(rim, base)
	if rim.glow and PIECES[base .. "_checked"] then
		Kit:Apply(rim.glow, base .. "_checked")
	end
end

-- The side of its window a tab hangs on ("right" / "left")
local function TabSide(tab)
	local window = tab
	while window:GetParent() and window:GetParent() ~= UIParent do
		window = window:GetParent()
	end
	local ok, tx, wx = pcall(function() return (tab:GetCenter()), (window:GetCenter()) end)
	if ok and tx and wx and not Secret(tx) and not Secret(wx) then
		return tx >= wx and "right" or "left"
	end
	return "right"
end

-- A tab at the Character window's size (another window's button set to it,
-- put back on disable), its rim SIDE_TAB_SCALE x that size, growing away
-- from the window: its window-side edge on the tab's, centred up and down
local function SideTabSize(entry, on)
	local tab, rim = entry.tab, entry.rep and entry.rep.object
	if not (tab and tab.SetSize and rim) then
		return
	end
	local w, h = Kit:SideTabSize()
	local anchor = entry.reference and (tab.Background or tab) or tab
	if on then
		if not entry.reference then
			if not entry.saved then
				local ok, sw, sh = pcall(tab.GetSize, tab)
				if not (ok and sw and sh) or Secret(sw) or Secret(sh) then
					return
				end
				entry.saved = { sw, sh }
			end
			tab:SetSize(w, h)
		end
		local side = TabSide(tab)
		rim:ClearAllPoints()
		if side == "right" then
			rim:SetPoint("LEFT", anchor, "LEFT", 0, 0)
		else
			rim:SetPoint("RIGHT", anchor, "RIGHT", 0, 0)
		end
		rim:SetSize(w * SIDE_TAB_SCALE, h * SIDE_TAB_SCALE)
	elseif entry.saved then
		tab:SetSize(entry.saved[1], entry.saved[2])
	end
	if rim.icon then
		Kit:SlotPlaceIcon(rim)
	end
end

-- The Character window's painted side-tab icons (INV_SideTab_*_c60, tabs 2
-- on) are drawn for the game's tab shape: a clipped corner and a transparent
-- strip down their right side, which the game hides by nudging them left. In
-- the square rim that strip showed the world through the opening (user,
-- 2026-09-23, painted blue on a screenshot): cropped away, the art keeping
-- its aspect (the top and bottom trimmed by the same share); measured on the
-- reputation tab's icon, the art ends at 0.89 of its width, so the icon
-- fills the rim to its inner edge (no backing behind it: user, 2026-09-23,
-- "dont add a background, resize the buttons to fit the borders"). The
-- game's own coordinates (UpdateIconInterior) come back on disable.
local SIDE_TAB_ICON_CROP = { 0.03125, 0.866, 0.0828, 0.9172 }
local SIDE_TAB_ICON_GAME = { 0.03125, 0.96875, 0.03125, 0.96875 }

local function SideTabIcon(entry, on)
	local rim = entry.rep and entry.rep.object
	local icon = rim and rim.icon
	if not icon then
		return
	end
	if not entry.crop then
		return
	end
	if not entry.cropHooked then
		entry.cropHooked = true
		hooksecurefunc(icon, "SetTexCoord", function(self)
			if entry.cropping or not (entry.rep.object and entry.rep.object:IsShown()) then
				return
			end
			entry.cropping = true
			self:SetTexCoord(unpack(SIDE_TAB_ICON_CROP))
			entry.cropping = nil
		end)
	end
	entry.cropping = true
	icon:SetTexCoord(unpack(on and SIDE_TAB_ICON_CROP or SIDE_TAB_ICON_GAME))
	entry.cropping = nil
end

function Kit:RegisterSideTab(rep, tab)
	if not (rep and tab) then
		return
	end
	local entry = { tab = tab, rep = rep, reference = IsReferenceTab(tab) }
	entry.crop = entry.reference and tab.GetID and tab:GetID() ~= 1   -- tab 1 is the character's portrait
	sideTabs[#sideTabs + 1] = entry
	local enable, disable = rep.Enable, rep.Disable
	rep.Enable = function(self, ...)
		enable(self, ...)
		SideTabLook(entry)
		SideTabSize(entry, true)
		SideTabIcon(entry, true)
	end
	rep.Disable = function(self, ...)
		disable(self, ...)
		SideTabSize(entry, false)
		SideTabIcon(entry, false)
	end
	SideTabLook(entry)
	if rep.object and rep.object:IsShown() then
		SideTabSize(entry, true)
		SideTabIcon(entry, true)
	end
end

-- Side Tab Border changed: every registered tab at once
function Kit:SetSideTabBorder()
	for _, entry in ipairs(sideTabs) do
		SideTabLook(entry)
	end
end

--------------------------------------------------------------------------------
-- Borders for every window, one choice per kind (user, 2026-09-23: "Progress
-- bar Borders, Nameplate Borders, ... should all be selectable from 1
-- Dropdown menu and reflect on the connected action bars like the Character
-- Side Panel Tab Borders"; one dropdown per kind). UI Modifications keeps
-- the settings; every element of a kind is registered as it is skinned and
-- takes the kind's look, and a new choice goes to all of them at once
-- (Kit:ApplyBorder). Panels that fit something round a border (a bar's
-- fill, the spell book's rims) listen with Kit:OnBorderChanged (the bus's
-- 'border' topic: kind, value).
--   button     the square rims of the action bars, micro menu, bag bar, bags,
--              gear slots and spells (the thin looks)
--   sidetab    every window's side tabs and the spell book's category tabs
--   bar        every progress bar's bracket (character, professions, legacy,
--              guild, experience, tracker, tooltip, damage meter, unit frames)
--   nameplate  the nameplates' health bar bracket
--------------------------------------------------------------------------------

-- the round rims' looks (Tools/build_kit.py thin_ring; no rounded-corners
-- ring: a ring is round already) and the auras' (the plain black edge they
-- had, or a thin rim)
Kit.roundLooks = {
	{ value = "roundslot", label = "Gem ring", piece = "buttons/roundslot_normal" },
	{ value = "roundrim", label = "Thin iron", piece = "buttons/roundrim_normal" },
	{ value = "roundrimhair", label = "Hairline", piece = "buttons/roundrimhair_normal" },
	{ value = "roundrimgold", label = "Iron with gold line", piece = "buttons/roundrimgold_normal" },
	{ value = "roundrimsunk", label = "Sunk", piece = "buttons/roundrimsunk_normal" },
}
Kit.auraLooks = { { value = "black", label = "Plain black edge" } }
for _, v in ipairs(Kit.buttonLooks.borders) do
	Kit.auraLooks[#Kit.auraLooks + 1] = v
end
-- The windows' frame and title (0.20.1; the user, 2026-10-10: "use thinner borders (yes the thick outer one aswell)"
-- and the header at the game's own size; our own art in the style of the RPG packs they showed, examples 3 and 4 to
-- test): variants of the NineSlicePanelTemplate and TitleBar rules, written into Kit.Replacements before a window is
-- dressed (Kit:SyncWindowLook: at the first window rule asked, once the settings are read, and on a choice). A
-- window already dressed keeps its look until a /reload.
--   classic  the double rail grown outward with gem corners; the red plate riding it (0.19.x)
--   stone    the thin stone rail on the window's edge (window/stone_*, Tools/make_window_stone.py)
--   ribbon   the red ribbon on the game's title bar (window/ribbon_*), the title on it
--   band     a plain band with the stone line under it (window/band_*), the title on it
-- `atBorder`: the rail drawn at the game's border's level, just under it (NineSlicePanelTemplate: 500, its corner ring
-- on it), over the window's panes -- the thin rail lies on the window's edge, where a pane's own border reaches (the
-- user, 2026-10-10: the rail missing beside and under the paperdoll); the double rail lies outside the window and
-- draws the window's stone, so it stays under. `railUnder`: the rail's top edge under the title bar, across the
-- window, as the game's top edge is as tall as its title bar (Kit:TitleRail).
Kit.windowFrames = {
	classic = { prefix = "window/frame", scale = 1.0, corners = "gem", outset = 42 },
	stone = { prefix = "window/stone", scale = 0.5, outset = 3, atBorder = true },
}
Kit.windowTitles = {
	classic = { base = "tabs/top", state = "open", heightScale = 1.5, onRail = true },
	ribbon = { base = "window/ribbon", heightScale = 1.0, centreTitle = true, railUnder = true },
	band = { base = "window/band", heightScale = 1.0, centreTitle = true },
}
Kit.windowFrameLooks = {
	{ value = "stone", label = "Thin stone rail" },
	{ value = "classic", label = "Double rail with gem corners" },
}
Kit.windowTitleLooks = {
	{ value = "ribbon", label = "Red ribbon" },
	{ value = "band", label = "Plain band with a rail line" },
	{ value = "classic", label = "Red plate on the rail (with the double rail)" },
}

-- the rule fields a look sets, written over the rule in place (every reader keeps the same table); `synced` once
-- the settings were read. (One table, no top-level locals: the file is at Lua 5.1's 200.)
Kit.windowLookState = { synced = false,
	frameFields = { "prefix", "scale", "corners", "outset", "atBorder" },
	titleFields = { "base", "state", "heightScale", "onRail", "centreTitle", "railUnder" } }

function Kit:SyncWindowLook()
	local st = self.windowLookState
	local frame = self.windowFrames[self:BorderValue("window") or "stone"] or self.windowFrames.stone
	local title = self.windowTitles[self:BorderValue("windowtitle") or "ribbon"] or self.windowTitles.ribbon
	local fr, tr = self.Replacements["NineSlicePanelTemplate"], self.Replacements["TitleBar"]
	for _, f in ipairs(st.frameFields) do
		fr[f] = frame[f]
	end
	for _, f in ipairs(st.titleFields) do
		tr[f] = title[f]
	end
end

-- (once the settings can be read: before that a read is the defaults, and the first window dressed after it would
-- wear them)
function Kit:SyncWindowLookOnce()
	local st = self.windowLookState
	if st.synced then
		return
	end
	local um = MelloUI:GetModule("UIModifications")
	if um and um.db then
		st.synced = true
		self:SyncWindowLook()
	end
end

function Kit:WindowFrameRule()
	self:SyncWindowLookOnce()
	return self.Replacements["NineSlicePanelTemplate"]
end

-- The game's portrait corner kept on a dressed window (0.20.1; the user, 2026-10-10: "hide the stubs"): its ring and
-- the portrait stay the game's, at the game's size and place, and the stubs of the game's metal rails beside the ring
-- are cut away, the kit's rail running into the ring. A mask made on the corner's own frame (a mask works only on its
-- frame's textures; no key is written on the game's), laid over the corner's whole square: Masks/portrait_corner
-- (Tools/make_portrait_corner_mask.py, measured on the corner's art) keeps the ring with its gold rim and soft halo
-- whole and cuts each stub at the rim (a round cut either left slivers of the stubs or clipped the rim: in game,
-- 2026-10-10); on with the rep, off with it. (A stand-in window's own copy of the corner: KitWindow.)
-- The kit's rail is cut there too (the user, 2026-10-10: its corner peeked out past the ring's top left; the game's
-- window has none, the ring is its corner): the ring's corner cut (Masks/ring_corner: the quarter above and left of
-- the ring's centre and a hole under its rim) on the rail's own textures, centred on the game's ring -- x, y from the
-- corner's top left (its art: the centre at 76, 76 of 190 px for 95 units), `hole` inside the rim's outer edge (30)
-- -- as the rep's `outerCut`, which the shade puts on the rail's partners (KitShade's Cut).
Kit.cornerCut = { mask = EDGE_ROOT .. "portrait_corner", x = 38, y = -38, hole = 27 }

function Kit:CornerCutMask(owner, corner)
	local mask = owner:CreateMaskTexture()
	mask:SetTexture(self.cornerCut.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(corner)
	return mask
end

-- (made once, at the rail's first enable: a window's rail art is laid as it is replaced)
function Kit:CutRailAtRing(rep, corner)
	local skin = rawget(rep, "skin")
	if not (skin and skin.CreateMaskTexture) then
		rep.outerCut = false
		return
	end
	local list = {}
	for _, t in ipairs(skin.all or {}) do
		list[#list + 1] = t
	end
	for _, t in ipairs(skin.art or {}) do
		list[#list + 1] = t
	end
	local c = self.cornerCut
	local size = 2 * c.hole / RING_HOLE_FILL
	local function Place(cut)
		cut:SetPoint("CENTER", corner, "TOPLEFT", c.x, c.y)
		cut:SetSize(size, size)
		return cut
	end
	-- (the skin's: its stone and the shade's partners on it, KitShade; the rails' frame's: the rails)
	rep.outerCut = Place(RingCut(skin, list))
	local rails = rawget(skin, "railHost")
	if rails then
		rep.railCut = Place(RingCut(rails, list))
	end
end

-- (0.20.1; the user, 2026-10-10: the border missing under the title) The game's top edge is as tall as its title bar
-- (the corner's art: its lower edge 26 units down; the title bar 1..21): with a title that sits inside the window's
-- top (the ribbon: Replacements.TitleBar.railUnder), the rail's own top edge runs under the title bar, across the
-- window from the left rail (under the game's ring, cut with the rail) to the right one. A texture of the rail's skin,
-- shown and hidden with it, placed by the title bar's own anchors (PortraitFrameTemplate: 58 and -24 from the sides).
function Kit:TitleRail(rep, region)
	local skin = rawget(rep, "skin")
	local window = region.GetParent and region:GetParent()
	local tc = window and rawget(window, "TitleContainer")
	if not (self.Replacements["TitleBar"].railUnder and skin and tc and tc.GetNumPoints and rep.rule.prefix) then
		return
	end
	local left, right = 58, -24
	for i = 1, tc:GetNumPoints() do
		local ok, point, _, _, x = pcall(tc.GetPoint, tc, i)
		if ok and not Secret(x) and type(x) == "number" then
			if point == "TOPLEFT" then
				left = x
			elseif point == "TOPRIGHT" then
				right = x
			end
		end
	end
	local T = skin.thickness or 0
	local o = (rep.rule.outset or 0) * (skin.kitScale or 0)
	local line = Tiled(rawget(skin, "railHost") or skin, rep.rule.prefix .. "_t", "BORDER", 0, skin.kitScale)
	line:SetPoint("TOPLEFT", tc, "BOTTOMLEFT", -left - o, 0)
	line:SetPoint("TOPRIGHT", tc, "BOTTOMRIGHT", -right + o - T, 0)
	line:SetHeight(T)
	skin.titleRail = line
	table.insert(skin.tiled, line)
	table.insert(skin.art, line)
	table.insert(skin.all, line)
	self:Retile(line)
end

function Kit:CutGameCorner(rep, corner)
	local owner = corner.GetParent and corner:GetParent()
	if not (owner and owner.CreateMaskTexture and corner.AddMaskTexture) then
		return
	end
	local mask = self:CornerCutMask(owner, corner)
	local on = false
	local onEnable, onDisable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if onEnable then
			onEnable(...)
		end
		if not on then
			on = pcall(corner.AddMaskTexture, corner, mask)
		end
		if rawget(rep, "outerCut") == nil then
			Kit:CutRailAtRing(rep, corner)
		end
	end
	rep.onDisable = function(...)
		if onDisable then
			onDisable(...)
		end
		if on then
			on = false
			pcall(corner.RemoveMaskTexture, corner, mask)
		end
	end
	rep.cornerCut = mask
end

Kit.borderKinds = {
	{ kind = "window", key = "windowBorder", default = "stone", name = "Window Border", values = Kit.windowFrameLooks,
	  new = "0.20.1",
	  desc = "The frame round every window: a thin stone rail on the window's edge, or the double rail with gem corners. Windows already opened change after a /reload." },
	{ kind = "windowtitle", key = "windowTitle", default = "ribbon", name = "Window Title", values = Kit.windowTitleLooks,
	  new = "0.20.1",
	  desc = "The title bar of every window, at the game's own size: a red ribbon, or a plain band with a rail line under it. The red plate riding the rail goes with the double rail. Windows already opened change after a /reload." },
	{ kind = "button", key = "buttonBorder", default = "thin", name = "Button Border", values = Kit.buttonLooks.borders, preview = "rim",
	  desc = "The rim on every square button: the action bars, the micro menu, the bag bar, your bags, the equipment slots and the spell book's spells." },
	{ kind = "sidetab", key = "sideTabBorder", default = "slot", name = "Side Tab Border", values = Kit.sideTabLooks, preview = "rim",
	  desc = "The rim on every window's side tabs and the spell book's category tabs, all at the character window's size." },
	{ kind = "bar", key = "barBorder", default = "frame", name = "Progress Bar Border", values = Kit.buttonLooks.barBorders, preview = "bar",
	  desc = "The frame round every progress bar: reputation and skills, the professions' ranks, legacy, guild, experience, the tracker's, the tooltip's and the damage meter's. The unit frames, the nameplates and the cast bar have a border of their own." },
	{ kind = "nameplate", key = "nameplateBorder", default = "frame", name = "Nameplate Border", values = Kit.buttonLooks.barBorders, preview = "bar",
	  desc = "The frame round the nameplates' health bars." },
	{ kind = "round", key = "roundBorder", default = "roundslot", name = "Round Border", values = Kit.roundLooks, preview = "rim",
	  desc = "The rim round every round icon: passive spells, the legacy, guild and group finder windows' rings, the auction house's item, the Services bar's round buttons." },
	{ kind = "aura", key = "auraBorder", default = "thin", name = "Aura Border", values = Kit.auraLooks, preview = "rim",
	  desc = "The rim round your buffs and debuffs, the target's and the nameplates' (Buffs & Debuffs): a plain black edge or one of the thin rims the buttons wear. The debuff colour stays round the icon. Only MelloUI's own aura rows wear it (Buffs & Debuffs, off by default): the game's own buff and debuff icons keep their edge, which Dark Mode's Buffs & Debuffs darkens." },
	{ kind = "colours", key = "kitColours", default = "warm", name = "Kit Colours", values = Kit.colourLooks,
	  desc = "The colours of all the painted art (frames, headers, rows, buttons, slots, bars). With the Ember and Ember Vibrant palettes: Warm iron (the metal in warm browns), Bronze (warm browns with gold bevels), or the Original painted grey iron and bright red. With any other palette: that palette's own colours, or the Original. Pictures keep their own colours." },
}
local BORDER_KIND = {}
for _, k in ipairs(Kit.borderKinds) do
	BORDER_KIND[k.kind] = k
end

-- A kind of the border library's (0.19.8, Modules/KitBorders.lua: Raid Frame
-- Border), placed after the kind `after` (UI Modifications makes its option
-- from the list when it loads, after the library)
function Kit:AddBorderKind(k, after)
	local at = #self.borderKinds + 1
	for i, v in ipairs(self.borderKinds) do
		if v.kind == after then
			at = i + 1
			break
		end
	end
	table.insert(self.borderKinds, at, k)
	BORDER_KIND[k.kind] = k
end

-- [kind] = the look its elements were last given: Kit:ApplyBorder's value,
-- or what the first read answered (the look the first elements were made
-- in). A profile load writes the settings past UI Modifications'
-- OnSettingChanged: the bus's 'restart' compares (below, Kit:ApplyBorder).
Kit.borderApplied = {}

function Kit:BorderValue(kind)
	local k = BORDER_KIND[kind]
	if not k then
		return nil
	end
	local um = MelloUI:GetModule("UIModifications")
	local v = um and um.db and um.db[k.key]
	v = v or k.default
	if Kit.borderApplied[kind] == nil then
		Kit.borderApplied[kind] = v
	end
	if kind == "colours" then
		-- (whoever reads the Kit Colours finds Kit.colourLooks holding the
		-- choices of the palette in use: Core puts a login's palette in place
		-- before anything is drawn, without a switch)
		LOOK.ShowChoices(LOOK.PaletteId())
	end
	return v
end

local buttonRims = setmetatable({}, { __mode = "k" })   -- [button] = true: a skinned button whose rim is a thin look
local borderBars = { bar = setmetatable({}, { __mode = "k" }), nameplate = setmetatable({}, { __mode = "k" }),
	-- (0.19.8: the unit frames' bars and the cast bar, a border of their own each)
	unitframe = setmetatable({}, { __mode = "k" }), castbar = setmetatable({}, { __mode = "k" }) }

function Kit:RegisterButtonRim(button)
	if button then
		buttonRims[button] = true
		self:SetButtonBorder(button, self:BorderValue("button"))
	end
end

function Kit:RegisterBorderBar(group, rep)
	if borderBars[group] and rep then
		borderBars[group][rep] = true
	end
end

-- fn(value) after a new choice of `kind`: an alias of the bus's 'border'
-- topic (audit, 2026-09-24, rank 5), through a small filter made once per
-- listener (a Fire makes none); one that raises goes to the error handler
function Kit:OnBorderChanged(kind, fn)
	MelloUI:On("border", function(changed, value)
		if changed == kind then
			fn(value)
		end
	end)
end

-- every round rim (Kit:Slot with kind "roundslot"), for Round Border
Kit.roundRims = setmetatable({}, { __mode = "k" })

-- A round rim in a look (its glow, the lit look, too)
local function RoundLook(rim, value)
	-- (0.19.8, the border library's stage 4: a ring style stands on the rim)
	if Kit.RoundLibraryRing and Kit:RoundLibraryRing(rim, value) then
		return
	end
	local base = "buttons/" .. value
	if not PIECES[base .. "_normal"] then
		return
	end
	Kit:SetSlotBase(rim, base)
	if rim.glow then
		local look = rim.restState or (PIECES[base .. "_checked"] and "checked") or "hover"
		Kit:Apply(rim.glow, base .. "_" .. look)
	end
end

-- A kind's choice to every element of it
function Kit:ApplyBorder(kind)
	local value = self:BorderValue(kind)
	self.borderApplied[kind] = value
	if kind == "colours" then
		self:SetKitColours(value)
	elseif kind == "round" then
		for rim in pairs(self.roundRims) do
			RoundLook(rim, value)
		end
	elseif kind == "button" then
		for button in pairs(buttonRims) do
			self:SetButtonBorder(button, value)
		end
	elseif kind == "sidetab" then
		self:SetSideTabBorder()
	elseif kind == "raid" then
		self:ApplyRaidBorders()   -- (the border library's: Modules/KitBorders.lua)
	elseif kind == "personal" then
		self:ApplyPersonalBorder()   -- (the border library's: Modules/KitBorders.lua)
	elseif kind == "portrait" then
		self:ApplyPortraitRings()   -- (the border library's rings: Modules/KitBorders.lua)
	elseif kind == "cooldown" then
		self:ApplyCooldownBorders()   -- (the Cooldown Manager's icons: Modules/KitBorders.lua)
	elseif kind == "orb" then
		-- (the frames not dressed yet take it now; the dressed ones after a /reload)
		if MelloUI.Announce then
			MelloUI:Announce("Level orb changed: type /reload to see it on frames already shown.", "info")
		end
	elseif kind == "window" or kind == "windowtitle" then
		-- (the windows not dressed yet take it now; the dressed ones after a /reload)
		self:SyncWindowLook()
		if MelloUI.Announce then
			MelloUI:Announce("Window look changed: type /reload to see it on windows already opened.", "info")
		end
	elseif borderBars[kind] then
		for rep in pairs(borderBars[kind]) do
			if rep.SetBar then
				rep:SetBar(value)
				if rep.onBarChanged then
					pcall(rep.onBarChanged, rep)
				end
			end
		end
	end
	MelloUI:Fire("border", kind, value)
	if kind == "colours" then
		-- the documented topic for the Kit Colours (Core's topic table,
		-- WINDOW-RULES 6), heard by the configurator (review, 2026-09-25)
		MelloUI:Fire("palette")
	end
end

-- The other looks after a profile load (0.14.0: a profile loaded from the
-- configurator, a share string, the macro backup or /mello profile load
-- left the elements in the old Button Border, Round Border ... until a
-- /reload): on the bus's 'restart', and when UI Modifications is switched
-- on ('module'), every kind but the Kit Colours (their own recheck, above)
-- whose setting is not the look its elements were last given
-- (Kit.borderApplied) is applied again, ONE kind a frame (a kind's pass
-- walks every element of it). A kind no element has read yet is left alone,
-- and nothing is done while UI Modifications is off or its settings are not
-- bound. The installer's look refresh applies through ApplyBorder, so the
-- restart after it finds nothing left to do; a kind set again meanwhile (the
-- configurator) is not applied a second time.
do
	local KEY = "Kit borders after a restart"   -- the bus owner and the Kit:NextFrame key
	local due, at, count = {}, 1, 0             -- the kinds to apply, in order (reused), the next, the last

	local function Differs(kind)
		local was = Kit.borderApplied[kind]
		return was ~= nil and Kit:BorderValue(kind) ~= was
	end

	-- one kind applied (those no longer different skipped), the next on the
	-- next frame
	local function Step()
		while at <= count do
			local kind = due[at]
			due[at] = nil
			at = at + 1
			if Differs(kind) then
				Kit:ApplyBorder(kind)
				if at <= count then
					Kit:NextFrame(KEY, Step)
					return
				end
			end
		end
		at, count = 1, 0
	end

	local function Look()
		local um = MelloUI:GetModule("UIModifications")
		if not (um and um.db and um.isEnabled) then
			return
		end
		for _, k in ipairs(Kit.borderKinds) do
			local kind = k.kind
			if kind ~= "colours" and Differs(kind) then
				local queued = false
				for i = at, count do
					if due[i] == kind then
						queued = true
						break
					end
				end
				if not queued then
					count = count + 1
					due[count] = kind
				end
			end
		end
		if at <= count then
			Kit:NextFrame(KEY, Step)
		end
	end

	local RestartBorders = Shared("'restart' on the bus: the border looks", Look)
	-- (a profile load's switch, MelloUI.restartingModules: its 'restart' follows)
	local UmbrellaBorders = Shared("'module' on the bus: the border looks", function(name, enabled)
		if enabled and name == "UIModifications" and not MelloUI.restartingModules then
			Look()
		end
	end)
	if MelloUI.On then
		MelloUI:On("restart", RestartBorders, "Kit borders")
		MelloUI:On("module", UmbrellaBorders, "Kit borders")
	end
end

-- A large side tab (SidePanelTabButtonMixin: Background common-sidetab, Icon,
-- SelectedTexture / TabGlow / HighlightTexture): the gold rim with the icon
-- fitted in, the glow while `checked()` (default: the game's SelectedTexture shown).
function Kit:SkinSideTab(tab, replace, checked)
	if not (tab and tab.Background) or Kit.repOf[tab] ~= nil then
		return tab and Kit.repOf[tab] or nil
	end
	Kit.repOf[tab] = replace(tab.Background, { as = "common-sidetab", button = tab, parent = tab, icon = tab.Icon,
		checked = checked or function() return tab.SelectedTexture and tab.SelectedTexture:IsShown() end,
		alsoFade = { tab.SelectedTexture, tab.TabGlow, tab.HighlightTexture } }) or false
	return Kit.repOf[tab] or nil
end

-- A list header's collapse button (CollapseButtonTemplate: an Icon the game
-- re-atlases with the state, an additive highlight copy): the +/- plate on
-- the glyph's rect, one per atlas seen. Call again after the game's
-- UpdateCollapsedState (or post-hook it).
function Kit:SkinCollapseButton(button, replace)
	if not (button and button.Icon) then
		return
	end
	local extra = {}
	for _, region in ipairs({ button:GetRegions() }) do
		if region ~= button.Icon and region:GetObjectType() == "Texture" and not Kit.pieceOf[region] then
			extra[#extra + 1] = region
		end
	end
	self:StateIconReps(button, button.Icon, button, replace, extra)
end

-- A search box (SearchBoxTemplate): the edit plate with its glass cap in
-- place of the game's icon; the text and instructions start past the cap.
function Kit:SkinSearchBox(search, replace)
	if not (search and search.Middle) or Kit.repOf[search] ~= nil then
		return search and Kit.repOf[search] or nil
	end
	-- (0.19.1: the field flat, the Configurator's search box -- the game's
	-- glass stays inside it and the text where the game has it; the S1 strip
	-- had its own glass cap, the game's faded and the text moved past the cap)
	local rule = self:RuleFor("common-search-border-middle")
	local flat = rule and rule.kind == "flat"
	-- (left: the field reaches over the art's 5 px left of the box, the glass
	-- inside it -- the search box's own span, as W.FlatSearch's)
	local rep = replace(search.Middle, { as = "common-search-border-middle", rect = search, edit = search,
		left = flat and 5 or nil,
		alsoFade = flat and { search.Left, search.Right } or { search.Left, search.Right, search.searchIcon } })
	Kit.repOf[search] = rep or false
	if not rep or flat then
		return rep or nil
	end
	local l, r, t, b = search:GetTextInsets()
	local instr = search.Instructions
	local points = {}
	if instr then
		for i = 1, instr:GetNumPoints() do
			points[i] = { instr:GetPoint(i) }
		end
	end
	rep.onEnable = function()
		local capW = (rep.strip.wl or 0) * 0.45
		search:SetTextInsets(capW, r, t, b)
		if instr then
			instr:ClearAllPoints()
			instr:SetPoint("TOPLEFT", search, "TOPLEFT", capW, 0)
			instr:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", -20, 0)
		end
	end
	rep.onDisable = function()
		search:SetTextInsets(l, r, t, b)
		if instr then
			instr:ClearAllPoints()
			for _, pt in ipairs(points) do
				instr:SetPoint(unpack(pt))
			end
		end
	end
	return rep
end

-- A text button on the red plate (B1): a UIPanelButtonTemplate (Left /
-- Middle / Right file pieces) or a 128-RedButton three-slice (Center).
function Kit:SkinRedButton(button, replace, opts)
	if not button or Kit.repOf[button] ~= nil then
		return button and Kit.repOf[button] or nil
	end
	opts = opts or {}
	local anchor, key, extra
	if button.Center then
		anchor, key = button.Center, "_128-RedButton-Center"
		extra = { button.Left, button.Right }
	elseif button.Middle then
		anchor, key = button.Middle, "UI-Panel-Button-Up"
		extra = { button.Left, button.Right }
	end
	if not anchor then
		Kit.repOf[button] = false
		return nil
	end
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= anchor and region ~= button.Left and region ~= button.Right
			and not Kit.pieceOf[region] and region:GetDrawLayer() == "HIGHLIGHT" then
			extra[#extra + 1] = region
		end
	end
	Kit.repOf[button] = replace(anchor, { as = key, rect = button, button = button, alsoFade = extra, dropCap = opts.dropCap, capless = opts.capless }) or false
	return Kit.repOf[button] or nil
end

-- A check button (CheckButton with the minimal or the classic check box
-- art): the kit's check box off / on / hover on its normal texture's rect.
function Kit:SkinCheckButton(cb, replace, key)
	if not (cb and cb.GetNormalTexture and cb:GetNormalTexture()) or Kit.repOf[cb] ~= nil then
		return cb and Kit.repOf[cb] or nil
	end
	local normal = cb:GetNormalTexture()
	-- the states the button has, gap-free: a radio has no pushed texture, and
	-- a nil in the list ended the fade at it (the checked / highlight /
	-- disabled art stayed the game's)
	local fade = {}
	for _, getter in ipairs({ "GetPushedTexture", "GetCheckedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local t = cb[getter] and cb[getter](cb)
		if t then
			fade[#fade + 1] = t
		end
	end
	Kit.repOf[cb] = replace(normal, { as = key or "checkbox-minimal", button = cb, rect = normal, alsoFade = fade }) or false
	return Kit.repOf[cb] or nil
end

-- P1 on a StatusBar whose bracket art is one of its own textures (`frame`,
-- e.g. LegacyProgressBarTemplate's ProgressBarFrame) and whose background
-- (`bg`) is a texture of the parent the bar is anchored to: the bracket and
-- trough become regions of the bar's frame on the background's rect, the
-- background and the game's bracket are faded, and the StatusBar itself is
-- moved into the opening (its fill spans the bracket's whole height, behind
-- the rails), put back on disable. `key` is the mapping (the bracket's atlas).
function Kit:SkinStatusBar(bar, frame, bg, replace, key)
	if not (bar and frame and bg) or Kit.repOf[bar] ~= nil then
		return bar and Kit.repOf[bar] or nil
	end
	local rep = replace(frame, { as = key or self:ArtKey(frame), rect = bg, parent = bar, alsoFade = { bg } })
	Kit.repOf[bar] = rep or false
	if not rep then
		return nil
	end
	local saved = {}
	for i = 1, bar:GetNumPoints() do
		saved[i] = { bar:GetPoint(i) }
	end
	rep.onEnable = function()
		rep:Refit()
		local l, r, t, b = rep:GetOpening()
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", bg, "TOPLEFT", l, -t)
		bar:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -r, b)
	end
	rep.onDisable = function()
		bar:ClearAllPoints()
		for _, pt in ipairs(saved) do
			bar:SetPoint(unpack(pt))
		end
	end
	return rep
end

-- Every skinned panel tab (Kit:SkinPanelTab), for the shared handlers below
-- (user, 2026-09-24: one handler for all of them, the tab's own state kept
-- here): its two cards, and which tab a hooked region belongs to
local panelTabs = setmetatable({}, { __mode = "k" })     -- [tab] = { plain = rep, open = rep, rep = the one Steady reads, text = }
local panelTabOf = setmetatable({}, { __mode = "k" })    -- [tab.Left / tab.LeftActive / tab.Text] = tab

-- the cards shown with the game's art (the game hides the plain set and
-- shows the active one on select)
local function PanelTab_Follow(tab, st)
	if st.plain then st.plain:SetShown(tab.Left:IsShown()) end
	if st.open then st.open:SetShown(tab.LeftActive:IsShown()) end
end
local PanelTab_OnArt = Shared("Show / Hide on a panel tab's art", function(region)
	local tab = panelTabOf[region]
	PanelTab_Follow(tab, panelTabs[tab])
end)

-- the text held where the plate wants it (below)
local function PanelTab_Steady(tab, st)
	local rep, open, text = st.rep, st.open, st.text
	if Kit.steadyingOf[tab] or not (rep.object:IsShown() or (open and open.object:IsShown())) then
		return
	end
	Kit.steadyingOf[tab] = true
	local dy = 0
	if rep.strip then
		local mid = PIECES[StripName(rep.strip.base, "mid", rep.strip.state)]
		if mid and mid.box then
			dy = (mid.h / 2 - (mid.box[2] + mid.box[4]) / 2) * (rep.strip.scale or Kit.scale)
		end
	end
	local okP, _, _, _, x = pcall(text.GetPoint, text, 1)
	text:SetPoint("CENTER", tab, "CENTER", (okP and x) or 0, dy)
	Kit.steadyingOf[tab] = nil
end
local PanelTab_OnTextPoint = Shared("SetPoint on a panel tab's text", function(text)
	local tab = panelTabOf[text]
	PanelTab_Steady(tab, panelTabs[tab])
end)

-- A PanelTabButtonTemplate / TabSystem tab (Left / Middle / Right plain,
-- LeftActive / MiddleActive / RightActive open; the game shows one set):
-- T1, one plate per set on the tab's rect, following the game's Show / Hide.
-- The open card of a tab not selected now is laid when the tab is first
-- selected (user, 2026-09-24: two cards per tab were the largest part of a
-- tabbed window's first frame, ~200 engine calls a tab, and a tab shows only
-- one): made now, in its place, its textures waiting (Kit:Replace's
-- `layWith`). Only for a panel that follows its cards (skin.followers),
-- syncing them with the game's art whenever it switches the kit on; a card
-- left on screen without its art is laid in its first frame there
-- (Waiting_OnUpdate).
function Kit:SkinPanelTab(tab, replace, skin)
	if not (tab and tab.Left and tab.LeftActive) or Kit.repOf[tab] ~= nil then
		return
	end
	Kit.repOf[tab] = false
	local follows = skin and skin.followers
	local plain = replace(tab.Left, { as = "uiframe-tab-left", rect = tab, button = tab, alsoFade = { tab.Middle, tab.Right, tab.LeftHighlight, tab.MiddleHighlight, tab.RightHighlight } })
	local open = replace(tab.LeftActive, { as = "uiframe-activetab-left", rect = tab, alsoFade = { tab.MiddleActive, tab.RightActive },
		layWith = (follows and not tab.LeftActive:IsShown()) and tab.LeftActive or nil })
	Kit.repOf[tab] = plain or open or false
	if follows then
		if plain then
			follows[#follows + 1] = { rep = plain, region = tab.Left }
		end
		if open then
			follows[#follows + 1] = { rep = open, region = tab.LeftActive }
		end
	end
	local st = { plain = plain, open = open }
	panelTabs[tab] = st
	panelTabOf[tab.Left], panelTabOf[tab.LeftActive] = tab, tab
	-- the game hides the plain set and shows the active one on select
	hooksecurefunc(tab.Left, "Show", PanelTab_OnArt)
	hooksecurefunc(tab.Left, "Hide", PanelTab_OnArt)
	hooksecurefunc(tab.LeftActive, "Show", PanelTab_OnArt)
	hooksecurefunc(tab.LeftActive, "Hide", PanelTab_OnArt)
	PanelTab_Follow(tab, st)
	-- the game bobs the tab's text on select / deselect (a few px up and
	-- down, to sit on its own tab art); on the kit's plate it stays put,
	-- centred on the plate's painted box (user, 2026-09-21). Re-applied
	-- after each of the game's SetPoint calls on the text, only while a
	-- plate is on.
	local text = tab.Text
	local rep = plain or open
	if text and rep then
		st.rep, st.text = rep, text
		panelTabOf[text] = tab
		hooksecurefunc(text, "SetPoint", PanelTab_OnTextPoint)
		PanelTab_Steady(tab, st)
	end
end

-- An InsetFrameTemplate (a marble Bg, a NineSlice at the frame's own level):
-- the single rail, edges only, on a holder at the inset's own level under
-- `parent` (over any list rows the inset frames), the inset faded.
-- `withBody`: the inset filled with the list-box stone (the palette's Inner
-- Panel, a panel sunk into the window) instead of showing the page through it:
-- a list whose text must read (user, 2026-09-23: the social window's lists on
-- the page's cracked stone were "not readable")
function Kit:SkinInset(inset, replace, parent, withBody)
	if not inset or Kit.repOf[inset] ~= nil then
		return
	end
	parent = parent or inset:GetParent()
	local ok, a, b = pcall(function() return inset:GetFrameLevel(), parent:GetFrameLevel() end)
	local level = (ok and a and b) and math.max(a - b, 1) or 1
	-- only the inset's ART is faded (its nine-slice pieces and marble), never
	-- the frame: an inset may hold content (the wardrobe's slots and models)
	local extra = { inset.Bg }
	if inset.NineSlice then
		for _, region in ipairs({ inset.NineSlice:GetRegions() }) do
			if region:GetObjectType() == "Texture" then
				extra[#extra + 1] = region
			end
		end
	end
	Kit.repOf[inset] = replace(inset, { as = "common-insideframe", parent = parent, rect = inset, level = level, body = withBody and true or false, noFade = true, alsoFade = extra }) or false
end

-- The controls every window has, found by what they ARE under `root` (a
-- window, a page): search boxes, red buttons, check boxes, dropdowns, panel
-- tabs, insets, scroll bars — each to its fixed look. `skip` frames are not
-- walked into (a map canvas). The game's own icons and pictures are left.
-- `shownOnly`: every child of a frame walked is looked at, but only the
-- shown ones are walked into, a hidden page left for when it first shows
-- (the walk some panels make themselves over a one-level sweep, in one call
-- and one GetChildren a frame; user, 2026-09-24).
function Kit:SweepControls(root, replace, skin, skip, depth, shownOnly)
	depth = depth or 0
	if not root or depth > 8 or root == skip or root == skin then
		return
	end
	local list, n = WalkChildren(root, depth)
	for i = 1, n do
		local child = list[i]
		local kind = child:GetObjectType()
		if child.Track and child.Track.Thumb and child.Back and child.Forward then
			self:SkinScrollBar(child, replace)
		elseif kind == "EditBox" and child.Middle and child.searchIcon then
			self:SkinSearchBox(child, replace)
		elseif child.Left and child.LeftActive and child.Middle then
			self:SkinPanelTab(child, replace, skin)
		elseif kind == "Button" and (child.Center or (child.Left and child.Middle and child.Right)) and child:GetFontString() and child:GetFontString():GetText()
			and not child.Icon and not child.Background and not child.CollapsedIcon and not (root.LayoutColumns) then
			-- (a column display's header buttons have the same Left / Middle /
			-- Right shape but are the window's to map: GC1, not B1)
			self:SkinRedButton(child, replace)
		elseif kind == "CheckButton" and child.GetCheckedTexture and child:GetCheckedTexture() and child:GetCheckedTexture():GetTexture()
			and not child.Icon and not child.Ring and (child:GetWidth() <= 40 or child:GetWidth() == 0) and Kit.repOf[child] == nil then
			local normal = child.GetNormalTexture and child:GetNormalTexture()
			local key = normal and self:ArtKey(normal)
			self:SkinCheckButton(child, replace, (key and self:RuleFor(key)) and key or "UI-CheckBox-Up")
		elseif child.Background and child.Arrow and child.Text and Kit.repOf[child] == nil then
			Kit.repOf[child] = replace(child.Background, { as = "common-dropdown-textholder", rect = child, button = child, alsoFade = { child.Arrow } }) or false
		elseif child.Background and child.Text and self:ArtKey(child.Background) == "common-dropdown-b-button" and Kit.repOf[child] == nil then
			Kit.repOf[child] = replace(child.Background, { as = "common-dropdown-b-button", rect = child, button = child, parent = child }) or false
		elseif child.NineSlice and child.Bg and (child.layoutType == "InsetFrameTemplate" or child.NineSlice.layoutType == "InsetFrameTemplate"
			or (child.NineSlice.TopLeftCorner and tostring(self:ArtKey(child.NineSlice.TopLeftCorner)):find("^UI%-Frame%-Inner"))) then
			self:SkinInset(child, replace, root)
		end
		if not (child.Track and child.Track.Thumb) and not (shownOnly and not child:IsShown()) then
			self:SweepControls(child, replace, skin, skip, depth + 1, shownOnly)
		end
	end
	WalkDone(list)
end

-- A list's rows as they are acquired by a WowScrollBoxList (and the ones it
-- already holds): `rowSkin(frame)` once per row, guarded by the panel.
-- `initialized`: call `rowSkin` after the row's own Init instead (a pool
-- whose frames serve as header AND row: the look is known only then).
function Kit:HookScrollBoxRows(scrollBox, rowSkin, isActive, initialized)
	if not (scrollBox and ScrollUtil and ScrollUtil.AddAcquiredFrameCallback) or Kit.kitHookedOf[scrollBox] then
		return
	end
	Kit.kitHookedOf[scrollBox] = true
	local add = (initialized and ScrollUtil.AddInitializedFrameCallback) or ScrollUtil.AddAcquiredFrameCallback
	add(scrollBox, function(_, frame)
		if isActive() then
			rowSkin(frame)
		end
	end, scrollBox, false)
	if scrollBox.ForEachFrame then
		scrollBox:ForEachFrame(function(frame)
			if isActive() then
				rowSkin(frame)
			end
		end)
	end
end

-- The dump every window module offers (/xxdump): the visible game textures
-- under `root` (art name, rect, layer), "frames" (the tree with strata and
-- levels), "reps" (ours), or `extra(msg)` for the module's own modes.
function Kit:DumpWindow(root, skin, msg, extra)
	local function Rect(label, f, more)
		local ok, l, b, w, h = pcall(function() return f:GetRect() end)
		if ok and l and not Secret(l) then
			MelloUI:Print("%-44s x=%.0f y=%.0f w=%.0f h=%.0f %s", label, l, b, w, h, more or "")
		else
			MelloUI:Print("%-44s (no rect) %s", label, more or "")
		end
	end
	-- a pooled entry's name can read secret on this client (the damage
	-- meter's rows): printed as such, never handed to format
	local function Name(obj)
		local ok, n = pcall(obj.GetName, obj)
		if ok and n and not Secret(n) then
			return n
		end
		local okD, d = pcall(obj.GetDebugName, obj)
		if okD and d and not Secret(d) then
			return d
		end
		return "[secret name]"
	end
	if extra and extra(msg, Rect, Name) then
		return
	end
	if msg == "frames" then
		local function walk(frame, depth)
			if depth > 6 or frame == skin then
				return
			end
			MelloUI:Print("%s%s  %s L%d%s", string.rep("  ", depth), Name(frame), frame:GetFrameStrata(), frame:GetFrameLevel(), frame:IsShown() and "" or " (hidden)")
			for _, child in ipairs({ frame:GetChildren() }) do
				walk(child, depth + 1)
			end
		end
		walk(root, 0)
		return
	end
	if msg == "reps" then
		if not skin then
			MelloUI:Print("No skin built.")
			return
		end
		for i, rep in ipairs(skin.reps) do
			local more = rep.object:IsShown() and "shown" or "hidden"
			if rep.kind == "picture" and rep.tex then
				local okV, vis = pcall(rep.tex.IsVisible, rep.tex)
				local ok, u1, _, _, _, _, _, u2, v2 = pcall(rep.tex.GetTexCoord, rep.tex)
				local okS, w, h = pcall(rep.inner.GetSize, rep.inner)
				more = string.format("%s visible=%s inner=%sx%s uv=%s..%s,%s piece=%s", more, okV and tostring(vis) or "?",
					okS and string.format("%.0f", w) or "?", okS and string.format("%.0f", h) or "?",
					ok and string.format("%.2f", u1) or "?", ok and string.format("%.2f", u2) or "?", ok and string.format("%.2f", v2) or "?", tostring(Kit.pieceNameOf[rep.tex]))
			end
			if rep.strip then
				-- a strip's fit: its scale, the caps' widths as laid out and
				-- the cap decisions (a plate that lost its caps shows why)
				local st = rep.strip
				more = string.format("%s scale=%.3f wl=%.1f wr=%.1f%s%s%s%s", more, st.scale or 0, st.wl or 0, st.wr or 0,
					st.capless and " CAPLESS" or "", st.dropCap and (" drop=" .. tostring(st.dropCap)) or "",
					st.endL and " endL" or "", st.endR and " endR" or "")
			end
			Rect(string.format("%d %s (%s)", i, rep.key, rep.kind), rep.rect, more)
			local piece = rep.tex or (rep.strip and rep.strip.mid) or nil
			if piece and piece ~= rep.rect then
				Rect("     piece", piece)
			end
			if rep.strip then
				Rect("     cap_l", rep.strip.capL, rep.strip.capL:IsShown() and "shown" or "hidden")
				Rect("     cap_r", rep.strip.capR, rep.strip.capR:IsShown() and "shown" or "hidden")
			end
		end
		return
	end
	local n = 0
	local function walk(frame, depth)
		if depth > 9 or frame == skin then
			return
		end
		for _, region in ipairs({ frame:GetRegions() }) do
			-- shown / alpha / layer can all read secret on a nameplate's
			-- regions (the cast bar's target indicator, user 2026-09-22)
			local okV, visible = pcall(region.IsVisible, region)
			if region:GetObjectType() == "Texture" and not Kit.pieceOf[region] and okV and not Secret(visible) and visible then
				local ok, alpha = pcall(region.GetAlpha, region)
				if ok and alpha and not Secret(alpha) and alpha > 0 then
					n = n + 1
					local okL, layer, sub = pcall(region.GetDrawLayer, region)
					if not okL or Secret(layer) or Secret(sub) then
						layer, sub = "?", "?"
					end
					Rect(string.format("%d %s/%s", n, Name(frame), region:GetName() or Kit.pieceNameOf[region] or region:GetDebugName()), region,
						string.format("%s/%s art=%s", tostring(layer), tostring(sub), tostring(self:ArtKey(region))))
				end
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			walk(child, depth + 1)
		end
	end
	walk(root, 0)
	MelloUI:Print("%d visible game textures", n)
end

--------------------------------------------------------------------------------
-- /kitdemo [scale]: one window with every block, to check the art in the client.
--------------------------------------------------------------------------------

local demo

local function BuildDemo(scale)
	scale = scale or Kit.scale
	local f = CreateFrame("Frame", "MelloUIKitDemo", UIParent)
	f:SetSize(640, 460)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	Perf.SetScript(f, "OnDragStart", f.StartMoving)
	Perf.SetScript(f, "OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)

	local skin = Kit:NineSlice(f, { scale = scale, gems = true, ornament = true })
	local T = Kit:NineSliceInset(skin)

	-- everything else lives above the skin
	local c = CreateFrame("Frame", nil, f)
	c:SetAllPoints(f)
	c:SetFrameLevel(f:GetFrameLevel() + 4)

	-- title plate hanging on the top edge, close button in the corner
	local title = Kit:Strip(c, "window/title", { width = 260, scale = scale })
	title:SetPoint("TOP", f, "TOP", 0, T * 0.6)
	local titleText = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	titleText:SetPoint("CENTER", title, "CENTER", 0, 0)
	titleText:SetText("MelloUI kit  " .. string.format("%.3f", scale))

	local close = CreateFrame("Button", nil, c)
	close:SetSize(Kit:Size("window/close_normal", scale))
	close:SetPoint("TOPRIGHT", -T * 0.4, -T * 0.4)
	Kit:StateTexture(close, "window/close", { scale = scale })
	Perf.SetScript(close, "OnClick", function() f:Hide() end)

	local ring = Kit:Texture(c, "window/portrait_ring", "ARTWORK", 3, scale)
	ring:SetPoint("TOPLEFT", -T * 0.2, T * 0.2)

	local y = -(T + 30)
	local x = T + 20

	-- text buttons
	local btn = Kit:Strip(c, "buttons/textbtn", { width = 180, scale = scale, state = "normal" })
	btn:SetPoint("TOPLEFT", x, y)
	local red = Kit:Strip(c, "buttons/redbtn", { width = 140, scale = scale, state = "hover" })
	red:SetPoint("LEFT", btn, "RIGHT", 12, 0)
	local dis = Kit:Strip(c, "buttons/textbtn", { width = 120, scale = scale, state = "disabled" })
	dis:SetPoint("LEFT", red, "RIGHT", 12, 0)
	y = y - btn.height - 12

	-- bars with a StatusBar in the opening
	for i, kind in ipairs({ "frame", "castbar" }) do
		local bar = Kit:Bar(c, { kind = kind, width = 420, scale = scale })
		bar:SetPoint("TOPLEFT", x, y)
		local sb = CreateFrame("StatusBar", nil, bar.fill)
		sb:SetAllPoints()
		sb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		sb:SetStatusBarColor(i == 1 and 0.75 or 0.85, i == 1 and 0.12 or 0.65, 0.12)
		sb:SetMinMaxValues(0, 1)
		sb:SetValue(i == 1 and 0.62 or 0.4)
		y = y - bar.height - 8
	end

	-- list rows and tabs
	for _, state in ipairs({ "plain", "hover", "selected" }) do
		local row = Kit:Strip(c, "lists/row", { width = 300, scale = scale, state = state })
		row:SetPoint("TOPLEFT", x, y)
		local txt = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		txt:SetPoint("LEFT", row, "LEFT", row:GetInsets() + 4, 0)
		txt:SetText("list row " .. state)
		y = y - row.height + 2 * scale
	end
	y = y - 10
	local tabPlain = Kit:Strip(c, "tabs/top", { width = 110, scale = scale, state = "plain" })
	tabPlain:SetPoint("TOPLEFT", x, y)
	local tabOpen = Kit:Strip(c, "tabs/top", { width = 110, scale = scale, state = "open" })
	tabOpen:SetPoint("LEFT", tabPlain, "RIGHT", 6, 0)
	local edit = Kit:Strip(c, "inputs/edit", { width = 160, scale = scale, state = "focused" })
	edit:SetPoint("LEFT", tabOpen, "RIGHT", 12, 0)

	-- icon slots on the right, with a spell icon under the rim
	local sx = 640 - T - 20
	local sy = -(T + 30)
	local size = Kit:Size("buttons/slot_normal", scale)
	for i, kind in ipairs({ "slot", "slot", "roundslot" }) do
		local b = CreateFrame(i == 2 and "CheckButton" or "Button", nil, c)
		b:SetSize(size, size)
		b:SetPoint("TOPRIGHT", sx, sy)
		local icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		if kind == "roundslot" then
			icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
		end
		Kit:Slot(b, { kind = kind, icon = icon, scale = scale })
		if i == 2 then
			b:SetChecked(true)
		end
		sy = sy - size - 8
	end

	-- small buttons
	local small = { "buttons/cog", "buttons/arrow_up", "buttons/arrow_down", "buttons/checkbox", "buttons/plus", "buttons/minus", "buttons/orb" }
	local px = sx
	for _, base in ipairs(small) do
		local first = Kit:FirstStateOf(base) and (base .. "_" .. Kit:FirstStateOf(base)) or nil
		if first then
			local b = CreateFrame(base == "buttons/checkbox" and "CheckButton" or "Button", nil, c)
			b:SetSize(Kit:Size(first, scale))
			b:SetPoint("TOPRIGHT", px, sy)
			Kit:StateTexture(b, base, { scale = scale })
			px = px - b:GetWidth() - 6
		end
	end
	sy = sy - 60

	-- a tile panel
	local tile = c:CreateTexture(nil, "ARTWORK", nil, 1)
	tile.kitScale = scale
	Kit:Apply(tile, "tiles/quilt_blue")
	tile:SetSize(150, 90)
	tile:SetPoint("TOPRIGHT", sx, sy)
	Kit:Retile(tile)
	local rail = Kit:Strip(c, "deco/rail", { width = 300, scale = scale })
	rail:SetPoint("BOTTOMLEFT", x, T + 6)

	return f
end

-- /kitwhat: every kit texture under the mouse cursor, back to front: the
-- piece, its rect, its texture coordinates (the crop), its tint and
-- alpha, the frame it is on. For a background that is not the one
-- expected (user, 2026-09-22: stone that changed shade, stretched
-- pictures): the answer is in which piece draws there and how it is cut.
SLASH_MELLOKITWHAT1 = "/kitwhat"
SlashCmdList.MELLOKITWHAT = function()
	local okC, cx, cy = pcall(GetCursorPosition)
	if not (okC and cx and cy) then
		return
	end
	-- a read, or `d` when it is nil or secret (a piece on a frame whose
	-- place or look the game hides reads secret, in a fight or on
	-- nameplates: the secret test before anything else, 2026-09-25)
	local function N(v, d)
		if (Secret and Secret(v)) or v == nil then
			return d
		end
		return v
	end
	local rows = {}
	for tex in pairs(SHADED) do
		local ok, visible = pcall(tex.IsVisible, tex)
		if ok and N(visible, false) then
			local okR, l, b, w, h = pcall(tex.GetRect, tex)
			local okS, es = pcall(tex.GetEffectiveScale, tex)
			l, b, w, h, es = N(l), N(b), N(w), N(h), N(es)
			if okR and l and b and w and h and okS and es and es > 0 then
				local x, y = cx / es, cy / es
				if x >= l and x <= l + w and y >= b and y <= b + h then
					local parent = tex:GetParent()
					-- GetTexCoord: UL x y, LL x y, UR x y, LR x y
					local okT, u1, v1, _, _, _, _, u2, v2 = pcall(tex.GetTexCoord, tex)
					u1, v1, u2, v2 = N(u1), N(v1), N(u2), N(v2)
					local okV, r, g, bl = pcall(tex.GetVertexColor, tex)
					r, g, bl = N(r, 1), N(g, 1), N(bl, 1)
					local okL, layer, sub = pcall(tex.GetDrawLayer, tex)
					layer, sub = N(layer), N(sub, 0)
					local _, file = pcall(tex.GetTexture, tex)
					file = N(file, "?")
					local strata = N(parent and parent.GetFrameStrata and parent:GetFrameStrata(), "?")
					local level = N(parent and parent.GetFrameLevel and parent:GetFrameLevel(), 0)
					local order = ({ BACKGROUND = 0, LOW = 1, MEDIUM = 2, HIGH = 3, DIALOG = 4, FULLSCREEN = 5, FULLSCREEN_DIALOG = 6, TOOLTIP = 7 })[strata] or 0
					local layerOrder = ({ BACKGROUND = 0, BORDER = 1, ARTWORK = 2, OVERLAY = 3, HIGHLIGHT = 4 })[okL and layer or ""] or 0
					local kp = type(Kit.pieceOf[tex]) == "table" and Kit.pieceOf[tex] or nil   -- (true: a flat colour of ours)
					local pieceW, pieceH = kp and kp.w or 0, kp and kp.h or 0
					local rimInfo = ""
					if tex.button then
						local bt = tex.button
						local okCk, ck = pcall(function() return bt.GetChecked and bt:GetChecked() end)
						local okSt, st = pcall(function() return bt.GetButtonState and bt:GetButtonState() end)
						rimInfo = string.format("  RIM state=%s hover=%s pressed=%s lastChecked=%s isChecked=%s | button checked=%s state=%s enabled=%s",
							tostring(tex.state), tostring(tex.hover), tostring(tex.pressed), tostring(tex.lastChecked),
							tex.isChecked and tostring(N(select(2, pcall(tex.isChecked)), "secret/nil")) or "-",
							okCk and tostring(N(ck, "secret/nil")) or "err", okSt and tostring(N(st, "secret/nil")) or "err",
							tostring(N(bt.IsEnabled and bt:IsEnabled(), "secret/nil")))
					end
					-- the share of the piece's own uv shown (its rectangle in an
					-- atlas sheet is a small part of the file)
					local shownW = (okT and u2 and u1) and (u2 - u1) or 0
					local shownH = (v2 or 0) - (v1 or 0)
					if kp and type(kp.uv) == "table" and kp.tile ~= "slice" then
						local du, dv = (kp.uv[2] or 1) - (kp.uv[1] or 0), (kp.uv[4] or 1) - (kp.uv[3] or 0)
						shownW = du ~= 0 and shownW / du or 0
						shownH = dv ~= 0 and shownH / dv or 0
					end
					-- a one-texture nine-slice: its family, and its w / h are the painted px it shows
					local isSlice = kp and kp.tile == "slice"
					if isSlice then
						shownW, shownH = 1, 1
					end
					rows[#rows + 1] = {
						key = order * 1e6 + level * 1e3 + layerOrder * 10 + (okL and sub or 0),
						text = string.format("%-34s %4dx%-4d  uv %.3f..%.3f x %.3f..%.3f  (%s: %dx%d px shown on %dx%d)  tint %.2f %.2f %.2f a=%.2f  %s/%s  %s L%d %s  file=%s",
							tostring(Kit.pieceNameOf[tex] or (isSlice and ("slice " .. tostring(kp.prefix)))), w, h, u1 or 0, u2 or 0, v1 or 0, v2 or 0,
							isSlice and "nine-slice" or kp and kp.tile and "tile" or "picture", math.floor(pieceW * shownW + 0.5), math.floor(pieceH * shownH + 0.5), w, h,
							okV and r or 1, okV and g or 1, okV and bl or 1, N(tex:GetAlpha(), 1),
							tostring(okL and layer or "?"), tostring(okL and sub or "?"), tostring(parent and parent:GetName() or (parent and parent:GetDebugName()) or "?"), level, strata,
							tostring(file)) .. rimInfo,
					}
				end
			end
		end
	end
	table.sort(rows, function(a, b) return a.key < b.key end)
	MelloUI:ClearLog()
	MelloUI:Print("Kit textures under the cursor, back to front (%d):", #rows)
	for _, row in ipairs(rows) do
		MelloUI:Print("%s", row.text)
	end
	MelloUI:ShowLog("kitwhat")
end

SLASH_MELLOKITDEMO1 = "/kitdemo"
SlashCmdList.MELLOKITDEMO = function(msg)
	local scale = tonumber(msg)
	if demo and (scale or demo:IsShown()) then
		demo:Hide()
		demo:SetParent(nil)
		demo = nil
		if not scale then
			return
		end
	end
	if not LAYOUT then
		MelloUI:Print("Kit layout missing (Media/KitLayout.lua).")
		return
	end
	demo = BuildDemo(scale)
	demo:Show()
end

--------------------------------------------------------------------------------
-- /mellokit: the one-texture nine-slices' switch and their test (user,
-- 2026-09-24: stage 2 of the performance programme, off by default).
--   /mellokit                   the switch, the data, the client's support
--   /mellokit slices on | off   the switch (saved); the UI reloads, so the
--                               whole kit is laid again the new way
--   /mellokit slices unit <n>   UI units one margin texel covers (1): only if
--                               the test shows the one-texture corners at
--                               another size than the pieces' (then /reload)
--   /mellokit slices count      every nine-slice built so far, per window: its
--                               rail textures in pieces and as one texture
--   /mellokit slicetest         today's rails beside the one-texture ones, at
--                               three sizes per case, and a third copy that
--                               blinks between the two (a difference jumps)
--------------------------------------------------------------------------------

do
	-- the rail textures a skin needs in pieces and as one texture, from what
	-- it holds (edges on the closed sides, each closed corner mitred or a gem).
	-- A skin whose rails wait (NineSlice's `defer`: a tab's open card not yet
	-- selected) is counted as it will be laid, from the options it keeps --
	-- no gem corners there, one texture if the switch was on when it was made
	-- (review, 2026-09-24: the count had them as skins of no pieces)
	local function RailCounts(skin)
		local wait = rawget(skin, "pendingArt")
		local cut = skin.slice and Kit.pieceOf[skin.slice]
		local open = {}
		for _, side in ipairs({ "t", "b", "l", "r" }) do
			if cut then
				open[side] = type(cut) == "table" and cut.open and cut.open:find(side, 1, true) ~= nil or false
			elseif wait then
				open[side] = (wait.open or ""):find(side, 1, true) ~= nil
			else
				open[side] = skin[side] == nil
			end
		end
		if wait then
			local want = wait.slices
			if want == nil then
				want = skin.slicesWas
			end
			local prefix = wait.prefix or "window/frame"
			local entry = want and Slices.api ~= false and SliceFamily(prefix)
			cut = entry and SliceCut(prefix, entry, open.l, open.r, open.t, open.b) or nil
		end
		local edges, mitred, gems = 0, 0, 0
		for _, side in ipairs({ "t", "b", "l", "r" }) do
			edges = edges + (open[side] and 0 or 1)
		end
		for _, c in ipairs({ "tl", "tr", "bl", "br" }) do
			if not open[c:sub(1, 1)] and not open[c:sub(2, 2)] then
				if skin.gemCorner and skin.gemCorner[c] then
					gems = gems + 1
				else
					mitred = mitred + 1
				end
			end
		end
		-- (a skin with a gem corner stays in pieces either way)
		return edges + mitred, (gems > 0) and (edges + mitred) or 1, cut and true or false
	end

	-- the window a frame is in: its last ancestor under UIParent
	local function TopWindow(frame)
		local f = frame
		for _ = 1, 40 do
			local p = f:GetParent()
			if not p or p == UIParent then
				break
			end
			f = p
		end
		local ok, name = pcall(f.GetName, f)
		if not (ok and type(name) == "string") then
			local okD, debugName = pcall(f.GetDebugName, f)
			name = okD and tostring(debugName) or "?"
		end
		return name
	end

	local function Count()
		local windows, order = {}, {}
		local total = { skins = 0, shown = 0, pieces = 0, one = 0, now = 0 }
		local f = EnumerateFrames()
		while f do
			if rawget(f, "melloSkin") and rawget(f, "all") then
				local pieces, one, sliced = RailCounts(f)
				local name = TopWindow(f)
				local w = windows[name]
				if not w then
					w = { skins = 0, shown = 0, pieces = 0, one = 0, now = 0 }
					windows[name] = w
					order[#order + 1] = name
				end
				local okV, visible = pcall(f.IsVisible, f)
				local shown = (okV and not Secret(visible) and visible) and 1 or 0
				for _, t in ipairs({ w, total }) do
					t.skins, t.shown = t.skins + 1, t.shown + shown
					t.pieces, t.one = t.pieces + pieces, t.one + one
					t.now = t.now + (sliced and one or pieces)
				end
			end
			f = EnumerateFrames(f)
		end
		table.sort(order, function(a, b) return windows[a].pieces - windows[a].one > windows[b].pieces - windows[b].one end)
		MelloUI:ClearLog()
		MelloUI:Print("Nine-slice rails built so far (a window's are built when it first opens), per window:")
		MelloUI:Print("%-44s %5s %5s %7s %9s %6s %4s", "window", "skins", "shown", "pieces", "one each", "saved", "now")
		for _, name in ipairs(order) do
			local w = windows[name]
			MelloUI:Print("%-44s %5d %5d %7d %9d %6d %4d", name:sub(1, 44), w.skins, w.shown, w.pieces, w.one, w.pieces - w.one, w.now)
		end
		MelloUI:Print("%-44s %5d %5d %7d %9d %6d %4d", "all", total.skins, total.shown, total.pieces, total.one, total.pieces - total.one, total.now)
		MelloUI:Print("pieces: rail textures as eight pieces; one each: as one texture (and a corner that stays its own); now: as the switch has them (%s)",
			Kit:SlicesOn() and "on" or "off")
		MelloUI:ShowLog("mellokit slices count")
	end

	local function Status()
		local data = SliceData()
		MelloUI:Print("One-texture nine-slices: %s (/mellokit slices on | off); a margin texel covers %s UI units.", Kit:SlicesOn() and "ON" or "off", tostring(SliceUnit()))
		if not data then
			MelloUI:Print("  Media\\KitSlices.lua is not loaded (not in MelloUI.toc?): everything stays in pieces.")
		else
			for prefix, entry in pairs(data) do
				MelloUI:Print("  %s: picture %dx%d texels, corners %d texels, %s; %s", prefix, entry.grid[1], entry.grid[2], entry.corner,
					PieceRoot(prefix .. "_t") .. tostring(entry.full), SliceFamily(prefix) and "ready" or "its pieces were tuned or rebuilt: stays in pieces")
			end
			MelloUI:Print("  a rail with gem corners (a window's outer rail) stays in pieces.")
		end
		if Slices.api == nil then
			-- not tried yet this session: one hidden texture asked, once
			local probe = UIParent:CreateTexture()
			probe:Hide()
			Slices.api = (probe.SetTextureSliceMargins and probe.SetTextureSliceMode and probe.SetScale) and true or false
		end
		MelloUI:Print("  this client %s cut a texture into a nine-slice.", Slices.api and "can" or "can NOT")
	end

	----------------------------------------------------------------------------
	-- The test window: one page per case, three sizes; per size the rails in
	-- pieces, as one texture, and a copy blinking between the two. The body
	-- (the stone) is the same texture in all three.
	----------------------------------------------------------------------------
	local test

	local function BuildTest()
		local SIZES = { { 140, 110 }, { 200, 140 }, { 260, 170 } }
		local COLUMN = 290

		local function Cases()
			-- (a window's outer rail, gem-cornered, stays in pieces: not a case)
			local frameScale = Kit.scale * (Kit.frameScale or 1.6)
			return {
				{ label = "Frames, insets and lists (window/single at the frame scale)", prefix = "window/single", scale = frameScale },
				{ label = "window/frame with its mitred corners", prefix = "window/frame", scale = Kit.scale },
				{ label = "window/single open at the top (an attached box: no top rail, no top corners)", prefix = "window/single", scale = frameScale, open = "t" },
				{ label = "window/single open on the right (the viewport, where it meets the pane divider)", prefix = "window/single", scale = frameScale, open = "r" },
				{ label = "window/frame open on the right, mitred corners", prefix = "window/frame", scale = Kit.scale, open = "r" },
			}
		end

		local function Label(parent, text, font)
			local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
			Kit:Paint(fs, "text", "text")   -- (by its key: a new palette paints it again)
			fs:SetText(text)
			return fs
		end

		-- what the page's one-texture skin is, and what a corner should cover
		local function Notes(case, pieces, sliced)
			local cut = sliced.slice and Kit.pieceOf[sliced.slice]
			local first
			if cut then
				local okS, texScale = pcall(sliced.slice.GetScale, sliced.slice)
				texScale = (okS and type(texScale) == "number") and texScale or 0
				local file = (PieceRoot(cut.prefix .. "_t") .. cut.file):gsub("^.-Media\\", "")
				first = string.format("one texture: %s, %dx%d texels shown, margins %d/%d/%d/%d (l/t/r/b), texture scale %.3f: a corner covers %.2f UI units",
					file, cut.w / cut.texel, cut.h / cut.texel,
					cut.margins[1], cut.margins[2], cut.margins[3], cut.margins[4], texScale, (cut.margins[1] > 0 and cut.margins[1] or cut.margins[3]) * texScale * SliceUnit())
			else
				first = "one texture: NOT drawn (/mellokit says why): both columns are pieces"
			end
			local tl = Kit:Piece(case.prefix .. "_tl")
			local second = string.format("pieces: a corner covers %.2f UI units (%d painted px x %.3f); rail textures per skin: %d in pieces, %d as one texture",
				pieces.thickness or 0, tl and tl.w or 0, case.scale, #pieces.art, #sliced.art)
			return first, second
		end

		local function BuildPage(parent, case, blinks)
			local page = CreateFrame("Frame", nil, parent)
			page:SetAllPoints(parent)
			page:Hide()
			for i, text in ipairs({ "Today (eight pieces)", "One texture", "Blinking between the two" }) do
				local h = Label(page, text, "GameFontNormal")
				h:SetPoint("TOPLEFT", page, "TOPLEFT", 90 + (i - 1) * COLUMN, -56)
			end
			local y = -84
			local first, second
			page.rows = {}
			for _, size in ipairs(SIZES) do
				local sizeLabel = Label(page, string.format("%d x %d", size[1], size[2]))
				sizeLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 16, y - 4)
				local skins = {}
				local row = { label = sizeLabel, size = size, cells = {} }
				page.rows[#page.rows + 1] = row
				for col = 1, 3 do
					local cell = CreateFrame("Frame", nil, page)
					cell:SetSize(size[1], size[2])
					cell:SetPoint("TOPLEFT", page, "TOPLEFT", 90 + (col - 1) * COLUMN, y)
					row.cells[col] = { frame = cell, x = 90 + (col - 1) * COLUMN, y = y }
					local function Skin(sliced)
						return Kit:NineSlice(cell, { prefix = case.prefix, scale = case.scale, corners = case.corners, skip = case.skip,
							open = case.open, gems = false, body = true, slices = sliced })
					end
					if col < 3 then
						skins[col] = Skin(col == 2)
					else
						local a, b = Skin(false), Skin(true)
						b:Hide()
						blinks[#blinks + 1] = { a, b }
					end
				end
				if not first then
					first, second = Notes(case, skins[1], skins[2])
				end
				y = y - size[2] - 28
			end
			local n1 = Label(page, first or "")
			n1:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 16, 58)
			local n2 = Label(page, second or "")
			n2:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 16, 42)
			return page
		end

		-- Zoom x2: the first size alone, its cells at twice the scale (the
		-- rails; the stone keeps the screen's one density), in the same
		-- columns; the window, its notes and buttons stay as they are (the
		-- whole window at x2 ran past the screen, its buttons with it --
		-- review, 2026-09-24)
		local function ZoomPage(page, on)
			for i, row in ipairs(page.rows) do
				local shown, s = not on or i == 1, (on and i == 1) and 2 or 1
				row.label:SetShown(shown)
				row.label:SetText(string.format("%d x %d%s", row.size[1], row.size[2], s > 1 and "\nat x2" or ""))
				for _, cell in ipairs(row.cells) do
					cell.frame:SetShown(shown)
					cell.frame:SetScale(s)
					cell.frame:ClearAllPoints()
					cell.frame:SetPoint("TOPLEFT", page, "TOPLEFT", cell.x / s, cell.y / s)
				end
			end
		end

		local f = CreateFrame("Frame", "MelloUISliceTest", UIParent)
		f:SetSize(960, 640)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		Perf.SetScript(f, "OnDragStart", f.StartMoving)
		Perf.SetScript(f, "OnDragStop", f.StopMovingOrSizing)
		f:SetClampedToScreen(true)
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(f)
		Kit:Paint(bg, "innerPanel", "fill", 0.97)   -- (follows a palette switch)
		local title = Label(f, "", "GameFontNormal")
		title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
		local caseLabel = Label(f, "")
		caseLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -34)
		local blinkLabel = Label(f, "")
		blinkLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 90 + 2 * COLUMN, -40)

		local cases, pages, blinks = Cases(), {}, {}
		for i, case in ipairs(cases) do
			blinks[i] = {}
			pages[i] = BuildPage(f, case, blinks[i])
		end
		local index = 1
		local function ShowPage(i)
			index = ((i - 1) % #pages) + 1
			for n, page in ipairs(pages) do
				page:SetShown(n == index)
			end
			title:SetText(string.format("MelloUI one-texture nine-slices: case %d of %d (switch %s, Kit.scale %.3f)", index, #pages,
				Kit:SlicesOn() and "ON" or "off", Kit.scale))
			caseLabel:SetText(cases[index].label)
		end
		local function Button(text, x, fn)
			local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
			b:SetSize(96, 22)
			b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 10)
			b:SetText(text)
			Perf.SetScript(b, "OnClick", fn)
			return b
		end
		Button("< Previous", 16, function() ShowPage(index - 1) end)
		Button("Next >", 118, function() ShowPage(index + 1) end)
		local zoomed = false
		Button("Zoom x2", 220, function(self)
			zoomed = not zoomed
			for _, page in ipairs(pages) do
				ZoomPage(page, zoomed)
			end
			self:SetText(zoomed and "Zoom x1" or "Zoom x2")
			-- the stone repeats at the screen's one density again; the rails follow the scale
			Kit:RetileBackgrounds()
		end)
		Button("Close", 960 - 112, function() f:Hide() end)

		-- the blink: every 0.6 s the third copy swaps, while the window is open
		local phase, ticker = false, nil
		local function Blink()
			phase = not phase
			for _, pair in ipairs(blinks[index] or {}) do
				pair[1]:SetShown(not phase)
				pair[2]:SetShown(phase)
			end
			blinkLabel:SetText(phase and "showing: one texture" or "showing: pieces")
		end
		Perf.HookScript(f, "OnShow", function()
			if not ticker then
				ticker = C_Timer.NewTicker(0.6, Blink)
			end
		end)
		Perf.HookScript(f, "OnHide", function()
			if ticker then
				ticker:Cancel()
				ticker = nil
			end
		end)
		ShowPage(1)
		return f
	end

	-- luacheck: globals SLASH_MELLOKIT1
	SLASH_MELLOKIT1 = "/mellokit"
	SlashCmdList.MELLOKIT = function(msg)
		local words = {}
		for w in (msg or ""):lower():gmatch("%S+") do
			words[#words + 1] = w
		end
		local cmd, arg, value = words[1], words[2], words[3]
		if cmd == "slicetest" then
			if test then
				-- made afresh each time: the switch, the unit or the look may have changed
				test:Hide()
				test:SetParent(nil)
				test = nil
			end
			if not LAYOUT then
				MelloUI:Print("Kit layout missing (Media/KitLayout.lua).")
				return
			end
			test = BuildTest()
			test:Show()
		elseif cmd == "slices" and (arg == "on" or arg == "off") then
			local db = MelloUI.db
			if type(db) ~= "table" then
				MelloUI:Print("The settings are not loaded yet; try again in a moment.")
				return
			end
			db.kitSlices = (arg == "on") or nil
			-- (never ReloadUI here: the game blocks a reload MelloUI's code asks for, 0.19.9)
			MelloUI:Print("One-texture nine-slices %s: type /reload to lay the kit again.", arg)
		elseif cmd == "slices" and arg == "unit" then
			local db = MelloUI.db
			local n = tonumber(value)
			if type(db) == "table" then
				db.kitSliceUnit = (n and n > 0 and n ~= 1) and n or nil
			end
			MelloUI:Print("A margin texel covers %s UI units at texture scale 1: /mellokit slicetest shows it; /reload for the rest of the UI.", tostring(SliceUnit()))
		elseif cmd == "slices" and arg == "count" then
			Count()
		elseif cmd == "mouse" then
			-- the frames that are no button whose mouse a rim's hooks would have
			-- turned on (FollowButton put it back: Kit.mouseKept), by name
			local rows = 0
			MelloUI:ClearLog()
			for frame, kept in pairs(Kit.mouseKept) do
				rows = rows + 1
				local ok, name = pcall(frame.GetDebugName, frame)
				if not ok or Secret(name) or type(name) ~= "string" then
					name = "?"
				end
				MelloUI:Print("  %s: %s left off", name, kept)
			end
			MelloUI:Print("Frames under a rim that kept their mouse off: %d (open windows add to it).", rows)
			MelloUI:ShowLog("mellokit mouse")
		else
			Status()
			MelloUI:Print("  /mellokit slices on | off, /mellokit slicetest, /mellokit slices count, /mellokit slices unit <n>, /mellokit mouse")
		end
	end
end
