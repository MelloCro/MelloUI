--------------------------------------------------------------------------------
-- MelloUI - Kit (the core look kit)
--
-- The kit's shared parts for every part of MelloUI, painted or not: the
-- pieces and their files (Media/Kit, described by Media/KitLayout.lua, naming
-- per docs/UI-KIT.md, and the Kit Colours' folders), Kit:Apply, the
-- parchment, the title font, the shade registry and the shadow partners,
-- Retile and the backgrounds, state resolution, the nine-slices, the active
-- look, the slot rims (Kit:Slot, Kit:StateTexture), covers and look areas,
-- Fade / Unfade and the border kinds (Kit:ApplyBorder). Not a module with
-- settings; other modules use MelloUI.Kit.
--
-- The painted engine (one look, stage I: Modules/KitPainted.lua, loaded right
-- after this file) adds the strips and bars, the replacement library
-- (Kit.Replacements + Kit:Replace), the slot stones, the button looks, the
-- tuning, the shared window parts, side tabs, its border kinds, the skin
-- helpers and the debug commands (/kitdemo, /mellokit) to the same table. The
-- locals the two share are on Kit.__ (filled at the end of this file).
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
-- (the locals the painted engine shares with this core: one private table, filled at the end of this file;
-- Kit.lua has few locals to spare, so never a new top-level local for them)
Kit.__ = {}

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

-- The folder a piece is read from in the chosen look. The uncoloured pieces
-- (the pictures, the parchment, the rank marks) are only in Media\Kit, in the
-- default look too (2026-10-18, found in the simulator: with UI Modifications
-- off its settings never load, and every picture was asked for in the look's
-- folder, where it is not -- the configurator's stone rails were missing)
local function PieceRoot(name)
	local root = lookRoot
	if not root then
		local um = MelloUI:GetModule("UIModifications")
		local id = LOOK.PaletteId()
		LOOK.ShowChoices(id)
		if um and um.db and Kit.BorderValue then
			lookRoot = Kit:LookFolder(id, Kit:BorderValue("colours"))
			root = lookRoot
		else
			-- the default look, until the settings are loaded (Kit.colourLooks
			-- already the palette's choices: a reader of the Kit Colours' values
			-- need not read the setting first)
			root = (Kit:LookFolder(id))
		end
	end
	if root == ROOT then
		return ROOT
	end
	for _, pattern in ipairs(LOOK.ART_ROOTS[root] and LOOK.ART_UNCOLOURED or UNCOLOURED) do
		if name:find(pattern) then
			return ROOT
		end
	end
	return root
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
-- (one look; the user, 2026-10-15: "the quest tracker the same as the chat does, needs to have the option to enable or
-- disable parchment and not be depending on the reskin on/off") the areas whose sheet lies on a part of MelloUI's
-- own, its switch live whatever the reskin: UI Modifications' option for one needs neither the reskin nor its own
-- switch (PARCHMENTS: `free`), its bus listener switches the sheet while it is off, and Kit:ParchmentOn reads it as
-- saved while its db is not bound (off since the login). The chat's too (the user, 2026-10-15: "for those 2, chat
-- and objective tracker, i want them to have the option for either normal look, and parchment even with the reskin
-- off"): its paper is the Minimal Chat View's and its whisper window's sheet (MelloUI_Chat/ChatView.lua), and the
-- painted chat's (Oldschool's ChatPanel) while that covers the game's windows. The whisper popups' paper
-- (parchment_whisper) stays the painted popup's: its sheet lies on the painted body only
Kit.ownParchments = { questTracker = true, chat = true }

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
	if db == nil and Kit.ownParchments[area] then
		-- (one look) MelloUI's own part's paper with UI Modifications off since the login: as saved
		local modules = MelloUI.db and MelloUI.db.modules
		local saved = type(modules) == "table" and modules.UIModifications
		db = type(saved) == "table" and saved or nil
	end
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
-- 2026-09-25): the one registry is Core/Widgets.lua's MelloUI.Painter (one
-- look D1, out of this file); Kit:Paint(region, key, how, alpha),
-- Kit:Unpaint(region[, how]) and Kit:PaletteKeyOf(colour) are its old names,
-- looked up when called. Without the widget set the kit paints nothing, as
-- W.Paint paints nothing without the kit.
function Kit:Paint(region, key, how, alpha)
	local P = MelloUI.Painter
	if P then
		P.Paint(region, key, how, alpha)
	end
end

function Kit:Unpaint(region, how)
	local P = MelloUI.Painter
	if P then
		P.Unpaint(region, how)
	end
end

function Kit:PaletteKeyOf(colour)
	local P = MelloUI.Painter
	return P and P.KeyOf(colour) or nil
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
-- whole; the torn outline is in the edges' and corners' own alpha, no mask; the edges opaque to their inner side and
-- the paper starting there (0.20.5, bodyInset 1: nothing under anything -- a fading tooltip showed the paper laid
-- under the edges as a box, every layer fading on its own). In the pack's own tone (the user's pick):
-- no tint. `curls` ("tl", "br", "tl br"): a big page's curled corners (the user's pick: the quest and spell book
-- pages, the character stats pane's top left): the page family (parchment/page_*), its corners big enough to hold
-- a curl and the shading under it whole (a sheet's cut them off and its square showed -- in game, 2026-10-10), the
-- corners without a curl its plain ones (_plain). `place(f)` anchors the frame the regions are laid out on; the
-- returned frame's Show / Hide / SetShown / SetAlpha act on the regions. scale (UI units per painted px; the paper
-- at the same, so its grain is the edges' own): a sheet's 80 px corner at 0.375 (30 UI units), a small panel's at
-- 0.3; a page at 0.6, the pack's own proportions on a quest page's width.
-- `tone`: the brightness every piece is drawn at, the hue the pack's (the user, 2026-10-10, the spell book: "perfect,
-- its just a bit too bright"); kept as the pieces' base under the kit's shade (Kit.tintBaseOf).
-- `layParent` (0.20.3): the frame the layout frame hangs from (a paper, Kit:Paper: hidden, all of it is), else `owner`.
Kit.parchment = { prefix = "parchment/sheet", pagePrefix = "parchment/page", body = "parchment/sheet_body", scale = 0.375,
	small = 0.3, page = 0.6, tone = 0.86 }

function Kit:ParchmentNine(owner, opts)
	opts = opts or {}
	local P = self.parchment
	local lay = CreateFrame("Frame", nil, opts.layParent or owner)
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
		bodyScale = scale, gems = false, slices = false, bodyLayer = layer, bodySub = sub, edgeLayer = layer, edgeSub = sub + 1,
		bodyInset = 1 })
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
	-- (a paper's look, Kit:Paper: its paper and edges laid again)
	nine.Fit = function(me)
		for _, t in ipairs(me.tiled) do
			Kit:Retile(t)
		end
	end
	return nine
end

-- The Parchment Style (0.20.3; the user, 2026-10-11: "the new one is the default but some people liked how the old
-- one looked aswell"): UI Modifications' parchmentStyle, "paper" (the RPG pack's, Kit:ParchmentNine) or "classic"
-- (0.20.0's: the vellum tile in Kit.parchmentTint ending in the painted brush strokes, Kit:PaintedEdge). Every
-- parchment sheet and page is a paper (Kit:Paper) wearing the style's look; Kit:SetParchmentStyle hands them over.
Kit.papers = setmetatable({}, { __mode = "k" })   -- [paper] = true: every sheet and page made

function Kit:ParchmentStyle()
	local um = MelloUI:GetModule("UIModifications")
	local v = um and um.db and um.db.parchmentStyle
	return v == "classic" and "classic" or "paper"
end

do
	-- a classic look's methods (a paper's look: SetShown, SetAlpha, Fit and its paper region `body`); `refit`, when
	-- given, fits it in its place (a page: the picture's own Refit)
	local Classic = {}
	local ClassicMeta = { __index = Classic }
	function Classic:SetShown(on)
		for _, r in ipairs(self.all) do
			r:SetShown(on)
		end
	end
	function Classic:SetAlpha(a)
		for _, r in ipairs(self.all) do
			r:SetAlpha(a)
		end
	end
	function Classic:Fit()
		if self.refit then
			self.refit()
			return
		end
		local tex = self.body
		local ok, w, h = pcall(tex.GetSize, tex)
		if not (ok and w and h) or Secret(w) or Secret(h) or w <= 0 or h <= 0 then
			return
		end
		Kit:Retile(tex)
		if self.edge then
			self.edge:Fit(w, h)
		end
	end

	-- the paper wears its style's look, built on its first need (a paper made hidden builds nothing), the other
	-- style's hidden; laid again on every wear (a look hidden while its rect changed size)
	local function Wear(paper)
		local shown, style = paper:IsShown() and true or false, paper.style
		local look = paper.looks[style]
		if shown and look == nil then
			look = paper.build[style](paper) or false
			paper.looks[style] = look
			if look then
				look:SetAlpha(paper.alpha)
			end
		end
		for s, other in pairs(paper.looks) do
			if other then
				other:SetShown(shown and s == style)
			end
		end
		paper.body = look and look.body or nil
		if shown and look then
			look:Fit()
		end
	end

	-- A paper: the frame a parchment sheet's or page's caller holds (a child of `owner`, laid by place(frame));
	-- build[style](paper) makes that style's look. Show / Hide / SetShown / SetAlpha act on the look worn, IsShown
	-- is the paper's own; paper:Fit() lays the worn look again.
	function Kit:Paper(owner, place, build, shown)
		local paper = CreateFrame("Frame", nil, owner)
		paper:EnableMouse(false)
		place(paper)
		paper.build, paper.looks, paper.alpha, paper.style = build, {}, 1, self:ParchmentStyle()
		local show, hide = paper.Show, paper.Hide
		paper.Show = function(me)
			show(me)
			Wear(me)
		end
		paper.Hide = function(me)
			hide(me)
			Wear(me)
		end
		paper.SetShown = function(me, on)
			if on then
				me:Show()
			else
				me:Hide()
			end
		end
		paper.SetAlpha = function(me, a)
			me.alpha = a
			local look = me.looks[me.style]
			if look then
				look:SetAlpha(a)
			end
		end
		paper.Fit = function(me)
			local look = me.looks[me.style]
			if look and me:IsShown() then
				look:Fit()
			end
		end
		self.papers[paper] = true
		paper:SetShown(shown ~= false)
		return paper
	end

	-- a classic look made of `all` (its regions), `body` the paper among them, `edge` its painted edge
	function Kit:ClassicLook(all, body, edge, refit)
		return setmetatable({ all = all, body = body, edge = edge, refit = refit }, ClassicMeta)
	end

	-- every paper in the style (nil: the setting's)
	function Kit:SetParchmentStyle(style)
		style = style or self:ParchmentStyle()
		for paper in pairs(self.papers) do
			if paper.style ~= style then
				paper.style = style
				Wear(paper)
			end
		end
	end
end

-- the classic sheet (0.20.0's): the vellum tile on `anchor`'s rect, a region of `skin`, in the kit's one parchment
-- tone, ending in the painted strokes (opts as Kit:ParchmentSheet's)
function Kit:ClassicSheet(skin, anchor, opts)
	local tex = skin:CreateTexture(nil, opts.layer or "BACKGROUND", nil, opts.sublevel or 3)
	tex:SetAllPoints(anchor)
	if not self:Apply(tex, opts.piece or self.parchmentPiece) then
		tex:Hide()
		return nil
	end
	tex.kitAlign = "center"
	local tint = opts.tint or self.parchmentTint
	tex:SetVertexColor(tint[1], tint[2], tint[3])
	local edge = self:PaintedEdge(tex, tex, opts.mirror, opts.tight, opts.wide and "wide" or opts.fine)
	return self:ClassicLook({ tex }, tex, edge)
end

-- (0.20.1: the parchment nine, Kit:ParchmentNine; 0.20.3: a paper, Kit:Paper, in the Parchment Style's look -- the
-- classic one Kit:ClassicSheet, `piece` / `tint` / `mirror` / `wide` its own; the returned sheet is the paper, the
-- second value nil -- no caller read the painted edge)
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
	local on = not opts.area or self:ParchmentOn(opts.area)
	local sheet = self:Paper(skin, Place, {
		paper = function(paper)
			return self:ParchmentNine(skin, { layParent = paper, place = function(f) f:SetAllPoints(paper) end,
				layer = opts.layer, sublevel = opts.sublevel, curls = opts.curls, scale = opts.scale or ((opts.tight or opts.fine) and P.small) or P.scale })
		end,
		classic = function(paper)
			return self:ClassicSheet(skin, paper, opts)
		end,
	}, (on and (not opts.area or not opts.alive or opts.alive())) and true or false)
	-- (laid again as the frame it follows changes size or shows: a skin sized while hidden gets no OnSizeChanged)
	local function Fit()
		sheet:Fit()
	end
	watch = watch or skin
	if watch.HookScript then
		Perf.HookScript(watch, "OnSizeChanged", Fit)
		Perf.HookScript(watch, "OnShow", Fit)
	end
	if opts.area then
		local list = self.parchmentSheets[opts.area] or {}
		self.parchmentSheets[opts.area] = list
		list[#list + 1] = { sheet = sheet, alive = opts.alive }
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
		-- (0.20.3) and the Parchment Style, written past it the same way
		Kit:SetParchmentStyle()
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

-- How many background tiles are registered now (/uiscaledump, Core/Schedule.lua)
function Kit:BackgroundCount()
	local n = 0
	for tex in pairs(BACKGROUNDS) do
		if Kit.backgroundOf[tex] then
			n = n + 1
		end
	end
	return n
end

-- Kit:SetFrameScale(frame, scale, setScale): the frame's scale set and the backgrounds in it laid again when its scale
-- on the screen changed: Core/Schedule.lua's since one look D1 (the same function; the kit's part looked up there).
Kit.SetFrameScale = MelloUI.Schedule.SetFrameScale

--------------------------------------------------------------------------------
-- The UI scale watcher: Core/Schedule.lua since one look D1, the one source of
-- the bus's 'scale' and 'editmode'; these are its old names, the same functions.
--------------------------------------------------------------------------------
Kit.OnUIScaleChanged, Kit.RefitForScale, Kit.ScheduleScaleRefit = MelloUI.Schedule.OnUIScaleChanged, MelloUI.Schedule.RefitForScale, MelloUI.Schedule.ScheduleScaleRefit

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

-- (0.20.1) A strip family's own weight: its mid's painted box (the opaque rows) at the kit's scale, in UI units. Every
-- window's divider line stands at it (the rules' `natural`, the panels' own line strips: one thickness everywhere)
function Kit:StripWeight(base, state)
	local p = PIECES[StripName(base, "mid", state)]
	if not p then
		return 8
	end
	if p.box then
		return (p.box[4] - p.box[2]) * self.scale
	end
	return p.h * self.scale
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
		-- the body reaches half way under the edges: the interior shows inside the gem corners' rounded elbows (they
		-- lie a whole rail in), and none of it past a gem's diamond at the frame's outer corner (0.20.1, the user: two
		-- "black spots" -- with the body run under the whole edge, the stone and the gem's baked shadow filled the
		-- corner square beyond the diamond once the double rail hugged the window). `bodyInset` (0.20.5): another share
		-- of the edge (the parchment's 1: its edges opaque to their inner side, the paper from there -- nothing under
		-- anything, so a fade shows no edge of a hidden layer)
		local inset = T * (opts.bodyInset or 0.5)
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
				-- (0.20.1: on the rails' frame with them -- a pane drew over a gem corner left on the skin)
				local tex = self:Texture(edgeHost, name, "ARTWORK", 1, scale)
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
		-- (each corner's entry is { its point, its open side }: the gem centred T / 2 in from the point)
		for c, a in pairs(corners) do
			local gem = self:Texture(skin, c == "tl" and "deco/gem_large" or "deco/gem_small", "ARTWORK", 1, scale)
			local sx = (c == "tl" or c == "bl") and 1 or -1
			local sy = (c == "tl" or c == "tr") and -1 or 1
			gem:SetPoint("CENTER", skin, a[1], sx * T / 2, sy * T / 2)
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
-- was asked for before then: Core/Schedule.lua's since one look D1 (the same function).
Kit.NextFrame = MelloUI.Schedule.NextFrame

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
-- on the bus's 'shell' topic (frame, shell): Core/EditLayoutWindows.lua registers a
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
			elseif rail and rawget(rail, "keptCorner") then
				Kit:TitleBehindGameCorner(known.title, rail.keptCorner, rail)   -- (0.20.1)
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
-- mixed look until /reload). Kit:IsOn(area), one answer per area, of three
-- kinds (onelook stage C, 2026-10-15):
--   the cover groups   the game's windows and HUD (the 16 first in LIST):
--                      on while a kit module covers one (Kit:IsCovered) --
--                      Oldschool's painted skins
--   always on          MelloUI's own parts, in MelloUI's look whatever the
--                      reskin: own (the widget column, the meter, Combat
--                      Text, the notices ... through MelloUI.Look),
--                      questTracker (the Quest Tracker), questList (the
--                      Quest List page) and loot (the loot window's own
--                      parts: the Discard button). Never told on the bus.
--   Oldschool's handshakes   on: the painted kit dresses a part of
--                      MelloUI's; off: MelloUI's plain palette look (the
--                      plain shell until the modern one, stage B1)
--     whisper          the whisper popups: as the chat windows ('chat')
--     services         the Services bar: as the minimap ('minimap')
--     config, copy     the configurator and the copy window (and the windows
--                      on the shell, Restock's tray, the widget panel's
--                      shade): the reskin (UI Modifications on, its reskin
--                      switch on); config through the installer's showcase
--                      too
--     installer        the installer: the reskin, and the kit's look on its
--                      first run whatever the reskin (the showcase)
-- Kit.Areas[area] = { name, topic = "look:<area>", and cover | follows = area
-- | reskin | always (+ showcase) }; a name not listed is read as a cover
-- group. (AreaOn's `module = name` and `switch = key` kinds have no entry
-- since stage C -- questList and loot followed QuestLogPanel and LootPanel,
-- questTracker the reskin and questTrackerKit -- and go in stage E.) The
-- bus's 'look:<area>' (on) goes out when an area's answer
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
		-- (onelook stage C) MelloUI's Quest Tracker: always in MelloUI's look
		-- (it followed the reskin and its Painted Skin, questTrackerKit, which
		-- the look no longer reads; the key goes in stage E)
		{ "questTracker", always = true },
		-- (Oldschool's handshakes: the painted kit as the chat / minimap cover)
		{ "whisper", follows = "chat" },
		{ "services", follows = "minimap" },
		-- (stage C) the Quest List page and the loot window's own parts: always
		-- in MelloUI's look (they followed QuestLogPanel / LootPanel)
		{ "questList", always = true },
		{ "loot", always = true },
		-- (the settings windows; on through the installer's showcase too: its
		-- confirm boxes and the windows it opens wear the same look --
		-- Oldschool's handshakes: the painted shell on, the plain one off)
		{ "config", reskin = true, showcase = true }, { "copy", reskin = true },
		-- (0.17.1, docs/plans/game-look.md) MelloUI's own parts -- the widget
		-- column, the meter, Combat Text, the notices ... (MelloUI.Look).
		-- onelook stage C: always in MelloUI's look (the game's own look
		-- with the reskin off before)
		{ "own", always = true },
		-- (docs/plans/game-look.md wave 4) the installer: the kit's look on
		-- its first run (the showcase, before the player chooses:
		-- Kit:Showcase), the reskin's after it -- Oldschool's handshake
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
		elseif area.module then   -- (no entry since onelook stage C: goes in stage E)
			local module = MelloUI:GetModule(area.module)
			return (module and module.isEnabled) and true or false
		elseif area.reskin then
			if not Reskin() then
				return false
			end
			local s = area.switch and Switches()   -- (no `switch` entry since stage C: goes in stage E)
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
	-- showcase (the installer's and the settings windows')
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
-- player is in combat: the combat queue is Core/Schedule.lua's since one look
-- D1 (MelloUI.Schedule); Kit:WhenOutOfCombat(fn, key), Kit:WhenQueueIdle(fn)
-- and Kit:IsQueueBusy() are its old names, the same functions.
--------------------------------------------------------------------------------
Kit.WhenOutOfCombat, Kit.WhenQueueIdle, Kit.IsQueueBusy = MelloUI.Schedule.WhenOutOfCombat, MelloUI.Schedule.WhenQueueIdle, MelloUI.Schedule.IsQueueBusy

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
-- The kinds (UI Modifications makes one option of each, in this order). The core holds the round rims'
-- and the Kit Colours; the painted engine (Modules/KitPainted.lua) adds its own kinds round them
-- (Kit:AddBorderKind), the window's and title's, the buttons', side tabs', bars', nameplates' and auras'.
Kit.borderKinds = {
	{ kind = "round", key = "roundBorder", default = "roundslot", name = "Round Border", values = Kit.roundLooks, preview = "rim",
	  desc = "The rim round every round icon: passive spells, the legacy, guild and group finder windows' rings, the auction house's item, the Services bar's round buttons." },
	{ kind = "colours", key = "kitColours", default = "warm", name = "Kit Colours", values = Kit.colourLooks,
	  desc = "The colours of all the painted art (frames, headers, rows, buttons, slots, bars). With the Ember and Ember Vibrant palettes: Warm iron (the metal in warm browns), Bronze (warm browns with gold bevels), or the Original painted grey iron and bright red. With any other palette: that palette's own colours, or the Original. Pictures keep their own colours." },
}
local BORDER_KIND = {}
for _, k in ipairs(Kit.borderKinds) do
	BORDER_KIND[k.kind] = k
end

-- A kind of the border library's (0.19.8, Modules/KitBorders.lua: Raid Frame
-- Border), placed after the kind `after`, or before the kind `before` (the
-- painted engine's kinds round the core's); neither: at the end (UI
-- Modifications makes its option from the list when it loads, after the
-- library)
function Kit:AddBorderKind(k, after, before)
	local at = #self.borderKinds + 1
	for i, v in ipairs(self.borderKinds) do
		if v.kind == after then
			at = i + 1
			break
		elseif before and v.kind == before then
			at = i
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
	elseif Kit.__.ApplyBorderKind then
		-- (the painted engine's kinds: Modules/KitPainted.lua)
		Kit.__.ApplyBorderKind(self, kind, value)
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

--------------------------------------------------------------------------------
-- What the painted engine (Modules/KitPainted.lua, loaded after this file) uses of this core's locals: on the
-- private table, set once everything above is made (FollowButton and RegisterShell, declared early, are
-- filled in their blocks by now)
--------------------------------------------------------------------------------
do
	local K = Kit.__
	K.Shared = Shared   -- (its wrapper, for a scope that has none)
	K.LAYOUT, K.PIECES, K.Kept, K.LOOK, K.EDGE_ROOT, K.SHADED, K.Slices, K.resolved, K.pressedLatches =
		LAYOUT, PIECES, Kept, LOOK, EDGE_ROOT, SHADED, Slices, resolved, pressedLatches
	K.PieceRoot, K.StripName, K.Slot_Update, K.FollowButton, K.RegisterShell, K.Tiled, K.NineSlice_Lay =
		PieceRoot, StripName, Slot_Update, FollowButton, RegisterShell, Tiled, NineSlice_Lay
	K.SliceUnit, K.SliceData, K.SliceFamily, K.SliceCut =
		SliceUnit, SliceData, SliceFamily, SliceCut
end
