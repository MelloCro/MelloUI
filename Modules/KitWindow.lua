--------------------------------------------------------------------------------
-- MelloUI - Kit window: the own-window shell (audit item 8, the configurator
-- build of 2026-09-25)
--
-- One shell for every window MelloUI makes itself (the configurator first,
-- the installer next; WINDOW-RULES 6): the look switch between the kit and
-- the plain palette look, the outer rail and the page stone, the emblem as a
-- crest on the top rail or in the corner ring, the title plate, the drag
-- strip and the window mover, the fit to the screen, Escape and the open /
-- close sounds. Nothing is made at load: a window is dressed when it is
-- built, which is its first open (WINDOW-RULES 2f).
--
--   local shell = MelloUI.Kit:OwnWindow(frame, {
--     area = "config",       Kit:IsOn(area) picks the look; 'look:<area>'
--                            switches it (the listener taken here)
--     ring = { at = "top" | "tl", texture = path, scale = 1.25 },
--                            "top": the crest centred on the outer rail's
--                            middle line (MelloUI-Crest); "tl": the standard
--                            corner ring (UI-Frame-PortraitMetal-CornerTopLeft,
--                            the plate behind it, 2c); the emblem on the ring's
--                            disc, never an empty ring (2b). x, y (a "tl"
--                            ring, the kit look): its centre from the top left
--                            (else the game's portrait's, CORNER_X / _Y) -- a
--                            bigger ring set higher so its gems cover the rail
--                            and the plate where they are cut (the bags')
--     plate ="crest" | "rail", title = "MelloUI", plateWidth = 200,
--                            "crest": the short plate under the crest
--                            (MelloUI-TitlePlate); "rail": the standard plate
--                            riding the outer rail (TitleBar, 2c)
--     calm = true,           the cleaner look (0.15.0, Background A): ONE flat
--                            `mainWindow` ground over the page, the kit's
--                            stone left only as a band CALM_BAND wide inside
--                            the rail (shell.calm); the window's panels
--                            (W.Panel) lie on that ground
--     background = fn | value,  the page stone's piece in the kit look (0.19.4,
--                            the options audit: the bags' Window Background
--                            on the bag window): a Window Background value
--                            (Kit.buttonLooks.backgrounds: a tile repeated at
--                            the UI's one density, or "dark", the palette's
--                            inner panel) or a function answering one, read
--                            when the kit dresses the page, at every switch
--                            on and show, and on shell:SetBackground(). It
--                            stands in for the stone on the stone's own
--                            texture (one surface); nil: the kit's own stone
--     close = true,          a close button on the top right corner
--     escape = true,         Escape closes it (UISpecialFrames: the frame
--                            must be named); held while a question of
--                            MelloUI:Confirm is shown
--     mover = { key, anchor, default, save, reset, min, max, base, plainDrag,
--               label, page, group, placeholder, resize },
--                            MelloUI:RegisterMover(frame, shell.grab, ...)
--                            with the crest kept on the screen with it; no
--                            default: centred. label / page / group /
--                            placeholder / resize: its plate in Edit Layout
--                            (its name, the page "All options >" opens, "tool"
--                            for a window never on a plate), as Core takes them
--     grabBottom = -70,      the drag strip, from the top edge down to this y
--                            (the painted look's; the modern look's: the
--                            strip's, or brand.grab)
--     brand = "block" | "row" | { shape = "block" | "row", grab = -48,
--             close = { x, y } },
--                            the modern look's header is a brand at the head
--                            of the window's side column, not the strip:
--                            "block" (the configurator) the emblem's rim
--                            centred in the column, the title under it;
--                            "row" (Fight History) the rim at the column's
--                            left, the title beside it, a hairline under
--                            them. The column is handed later
--                            (shell:Brand). grab: the drag band's bottom in
--                            the modern look (default the strip's); close:
--                            the close's right edge and middle from the
--                            window's top right (default the strip's place)
--     inset = 8,             the modern look's content inset (default FLAT.IN,
--                            the small windows' one inset): the strip's ends
--                            sit on it, shell:Inset answers it
--     fit = true,            scaled down to fit the screen (never up, not
--                            while the mover holds the user's scale), on
--                            every show and UI scale change
--     sounds = true,         MelloUI:PlayUISound "window_open" / "window_close"
--                            on a real open and close (not when only the UI
--                            is hidden and shown again, Alt+Z)
--   })
-- The frame is the caller's (named, sized, parented to UIParent); set its
-- own OnShow / OnHide scripts BEFORE this call (SetScript drops hooks). The
-- shell's show hook runs after the frame's own OnShow script.
--
-- Fields: shell.frame, shell.kit (true while the kit look is on), shell.area,
-- shell.crest (the crest's / corner ring's square, both looks; hidden in the
-- modern one), shell.emblem (the kit's, on the ring's disc; made with the
-- kit), shell.plainEmblem (the crest's emblem: the region the kit's ring
-- replaces, DressRing; under ring.game the bag's portrait), shell.disc,
-- shell.ring (the ring's rep), shell.plate (the plate's frame),
-- shell.plateRep, shell.title (FontString), shell.grab, shell.close,
-- shell.rail (the outer rail's rep), shell.page (the page stone's rep; both
-- made with the kit), shell.mover (Core's entry),
-- shell.reps, shell.replace (fn(region, opts) for Kit helpers that take a
-- replace function), shell.skin ({ reps, followers } for Kit helpers),
-- shell.bounds (what is kept on the screen with the frame); the modern look's
-- (made the first time it shows): shell.ground, shell.groundEdges,
-- shell.shade (the band: UI Shade's Windows area and strength, ShadeWindow),
-- shell.rim (the emblem's), shell.brandLine (a row's hairline, on
-- shell.brandHolder), shell.brandShape ("block" / "row" / nil: the strip),
-- shell.brandColumn, shell.inset, shell.paintedOnly (the kit's anchors).
-- Methods:
--   shell:Replace(region, opts)  Kit:Replace, the rep recorded for the switch
--   shell:Anchor(parent, layer)  THE invisible region to hand to Replace where
--                                a widget has none
--   shell:Kit(fn, ...)           fn(Kit, ...) now while the kit look is on,
--                                else at the next switch on (dressing that
--                                needs the kit); an error in it is reported
--                                and the window is built on without it
--   shell:Plain(region)          a plain-look-only region: hidden while the
--                                kit look is on
--   shell:OnKit(fn)              fn(shell, on) after every switch (a shared fn)
--   shell:SetKit(on)             the look switched now while it is shown; a
--                                hidden window reads Kit:IsOn(area) again on
--                                its next show
--   shell:Fit()   shell:SetEscape(on)
--   shell:SetBackground(value)   the page's piece (opts.background) laid
--                                again: `value` a new choice, nil the
--                                window's own read again (a window without
--                                one: nothing)
--   shell:HoldEscape(on)         the window's Escape held while a piece of it
--                                that Escape closes first is open (a picture
--                                row's flyout, W.PictureMenu): its setting
--                                kept, its name back a frame after
--   Kit:ShellOf(frame)           the shell a window has (nil: none; nothing
--                                made)
--   shell:Inset(edge, top)       -> edge, top: the content's side inset and
--                                top (a negative y) in the look on show: the
--                                caller's own (`edge`, `top`: its painted
--                                look's, under the corner ring and the plate)
--                                while the kit dresses the window, else the
--                                modern look's (opts.inset; under the strip,
--                                or the inset itself with a brand column).
--                                Lay the content with it at build and in an
--                                OnKit
--   shell:Brand(column)          -> room: the brand (opts.brand) laid at the
--                                head of `column` (a region of the window: the
--                                side list's box) in the modern look; room:
--                                how far below the column's top its own
--                                content starts there. The brand stands over
--                                the column's level (a column in a body panel
--                                hides nothing of it)
-- The switch: the plain look is the window's own regions, which the kit's
-- replacements fade while they are enabled; switched off, every recorded rep
-- is disabled and they come back. Colours are palette keys (Kit:Paint), so a
-- new palette paints them again. Sounds only through MelloUI:PlayUISound.
-- The look while the kit does not dress the window is MelloUI's own, the
-- modern shell (onelook stage B, the user's pick C "the brand column",
-- 2026-10-15; docs/plans/onelook-b-sketches/shell.md): no title bar -- one
-- flat `mainWindow` ground in a 1 px `border` edge, a soft shade round it
-- (MelloUI.Shade:Band), the emblem in the kit's round rim on its dark disc
-- (W.GlyphButton: W.RoundIcon's roundslot rim, its round shade), the title
-- in the title face (Kit:TitleFont) in the palette's gold, the close
-- (W.CloseButton). A window with a side column wears the brand at the
-- column's head (opts.brand, shell:Brand); one without wears the strip: a
-- band FLAT.STRIP high, the rim at its left end, the title beside it, the
-- close at its right end, both ends on the content inset, the content from
-- FLAT.TOP. The drag band runs full width from the top; nothing pokes out
-- of the window (no overhang). The kit's anchors (the rock, the tint, the
-- calm ground, the plate's box, the crest) hide in it (shell.paintedOnly).
--
-- The painted dressing (the outer rail and page stone, the ring, the plate),
-- Kit:ChoicePicture (a look choice's picture for the picture rows, W.PictureRow
-- / W.PictureMenu) and the nudges are the painted reskin's (one look, stage I:
-- MelloUI_Oldschool/Modules/KitWindowPainted.lua, the dressing handed over as Kit.__.ShellDress).
-- And, for the own windows' questions (the end of the file):
--   MelloUI:Confirm({ text, accept, cancel, onAccept, onCancel })
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Kit window")
local Shared = Perf.Shared
local C_Timer = Perf.C_Timer   -- (an Escape hold ends a frame later: the confirm dialog's, a flyout's)
local Kit = MelloUI.Kit
local Num = MelloUI.Safe.Number
local W = MelloUI.Widgets   -- (Core/Widgets.lua loads before this file)

local TEXTURE_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\"
local LOGO = TEXTURE_PATH .. "LogoIcon.tga"                    -- the round emblem of the logo
local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"      -- the page stone's region (the kit's stone replaces it)
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local PAGE_INSET = 6         -- the tint inside the frame's edge (the calm ground's rect too while the kit is off: hidden then)
local CALM_BAND = 14         -- the stone left round the calm ground, inside the rail (opts.calm)
local PLAIN_CORNER = 62      -- a game window's portrait (ring.game: the bag window's)
local CORNER_X, CORNER_Y = 26, -24   -- a game window's portrait centre from its top left (PortraitFrameTemplate: 62 px at -5, 7)
-- the rock's rect (the region the kit's page stone replaces; it shows only if the stone is missing): from under the
-- game window's title bar (2 in with the portrait, 7 without, 21 down, 2 in at the bottom)
local GAME_BG_TOP, GAME_BG_IN, GAME_BG_IN_NOPORTRAIT, GAME_BG_EDGE = 21, 2, 7, 2
-- The modern look (onelook stage B, the user's pick C "the brand column", 2026-10-15; the round-3 build notes of
-- docs/plans/onelook-b-sketches/shell.md), in UI units from the window's top left:
--   IN      the small windows' one content inset: the body, the question's panel, the strip's two ends
--   STRIP   the strip (a window without a side column): the rim, the title and the close on its middle line
--   RIM     the strip's rim; GAP the rim to the title (the title at IN + RIM + GAP: 37)
--   TOP     the content's top under the strip (its body panel's edge is the one rule: no hairline)
--   SHADE   the window's soft shade (MelloUI.Shade:Band): a rectangle round the rectangular window; its alpha at
--           UI Shade's default strength, in the Windows area (Shell:ShadeWindow)
--   block   the configurator's brand: a rim `rim` across, its middle `rimY` under the column's top, the title's
--           middle `titleY` under it; the column's own content from `room` (the search box at 126, the rows at 154
--           as before, the column from 16)
--   row     Fight History's brand row: a rim `rim` across at the column's left, its middle `rimY` under the
--           column's top, the title `gap` past it, a hairline `line` under the column's top; its content from `room`
local FLAT = {
	IN = 8, STRIP = 28, RIM = 22, GAP = 7, TOP = 30,
	SHADE = { colour = "innerPanel", alpha = 0.6, feather = 18, featherY = 18, sublevel = -8 },
	GROUND = -7,   -- (the ground's BACKGROUND sublevel: over the shade's, under every region of the window's own)
	block = { rim = 56, rimY = 40, titleY = 86, room = 106 },
	row = { rim = 32, rimY = 17, gap = 8, line = 40, room = 48 },
	RIM_OPTS = { shade = "windows" },   -- (W.GlyphButton's: the rim's round shade partner, in the windows' shade)
}
local PLATE_FIT = 20         -- the plate's fit height (a game window's title container); its painted part 1.5 x that
local PLATE_OVERLAP = 8      -- the short plate reaches this far up over the crest's bottom (the approved sketch)
local GRAB_BOTTOM = -40      -- the drag strip's bottom edge when none is given
local FIT_MARGIN = 16        -- a window scaled to fit leaves this much of the screen free
-- frame levels over the window's own
local LEVEL_GRAB, LEVEL_CREST, LEVEL_PLATE, LEVEL_CLOSE = 1, 4, 7, 8
-- (ring.game: the game's portrait over the title plate, the game's corner art over its portrait's edge -- the
-- painted dressing's, one level over it -- as the game's PortraitFrameBaseTemplate, its NineSlice above the
-- PortraitContainer's 400; 0.20.1, the user: the backpack "still too big and not fitting inside its border")
local LEVEL_GAME_PORTRAIT = 9
-- (the portrait's circle mask, the template's CircleMask: 2 in from each side, its bottom 4 up)
local GAME_MASK_IN, GAME_MASK_UP = 2, 4
-- (the two the painted dressing shares, MelloUI_Oldschool/Modules/KitWindowPainted.lua)
Kit.__.ShellPlateFit, Kit.__.RoundMask = PLATE_FIT, ROUND_MASK

local shells = setmetatable({}, { __mode = "k" })   -- [frame] = its shell
-- the confirm dialog's shell while its question holds the other shells'
-- Escape (MelloUI:Confirm, the end of the file)
local escapeHold = nil
local Shell = {}
Shell.__index = Shell

--------------------------------------------------------------------------------
-- The shared handlers (one for every shell)
--------------------------------------------------------------------------------

-- Show and hide come also when only the parent does: the UI hidden and
-- shown again (Alt+Z, a cinematic) with the window still open. That is no
-- close and no open: no sound. In an OnHide the window is never visible, so
-- a hide with the window still shown (IsShown) is the parent's; the show
-- that follows it is the parent's too. (The look, the fit and the place are
-- checked on every show: the same answers when nothing changed.)
local Shell_OnShow = Shared("OnShow on a kit own window", function(frame)
	local shell = shells[frame]
	if shell then
		local reshown = shell.parentHidden
		shell.parentHidden = false
		shell:Showing(not reshown)
		-- (UI Shade's settings read again: a profile loaded while it was hidden)
		shell:ShadeWindow()
	end
end, "script")

local Shell_OnHide = Shared("OnHide on a kit own window", function(frame)
	local shell = shells[frame]
	if not shell then
		return
	end
	if frame:IsShown() and not frame:IsVisible() then
		shell.parentHidden = true
		return
	end
	shell.parentHidden = false
	if shell.sounds then
		MelloUI:PlayUISound("window_close")
	end
end, "script")

local Close_OnClick = Shared("OnClick on a kit own window's close button", function(button)
	local shell = shells[button:GetParent()]
	if shell then
		shell.frame:Hide()
	end
end, "script")

-- the mover's default place: centred on the screen
local function Centre(frame)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

-- a new UI scale: every shown shell that fits fitted again (one listener
-- for all of them, taken with the first)
local scaleListening = false
local function Shells_OnScale(reason)
	if reason ~= "uiscale" then
		return
	end
	for frame, shell in pairs(shells) do
		if shell.fit and frame:IsShown() then
			shell:Fit()
		end
	end
end

-- UI Shade's Windows area switched or its strength moved: every modern
-- window's soft shade with it (one listener, taken with the first shade)
local shadeListening = false
local function Shells_OnShade(area)
	if area ~= "windows" then
		return
	end
	for _, shell in pairs(shells) do
		if shell.shade then
			shell:ShadeWindow()
		end
	end
end

--------------------------------------------------------------------------------
-- The shell's methods
--------------------------------------------------------------------------------

function Shell:Replace(region, opts)
	if not region then
		return nil
	end
	local rep = Kit:Replace(region, opts)
	if rep then
		self.reps[#self.reps + 1] = rep
		if self.kit then
			rep:Enable()
		end
	end
	return rep
end

function Shell:Anchor(parent, layer)
	local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
	tex:SetAllPoints(parent)
	tex:SetColorTexture(0, 0, 0, 0) -- ratchet-ok: the shell's invisible anchor
	return tex
end

-- (an error in dressing is reported and the window is built on without it,
-- now as from the queue)
local function Reported(ok, ...)
	if not ok then
		geterrorhandler()((...))
		return nil
	end
	return ...
end

function Shell:Kit(fn, ...)
	if self.kit then
		return Reported(pcall(fn, Kit, ...))
	end
	local q = self.queue
	q[#q + 1] = { n = select("#", ...), fn, ... }
end

function Shell:Plain(region)
	if region then
		self.plains[#self.plains + 1] = region
		region:SetShown(not self.kit)
	end
	return region
end

function Shell:OnKit(fn)
	for i = 1, #self.onKit do
		if self.onKit[i] == fn then
			return
		end
	end
	self.onKit[#self.onKit + 1] = fn
end

-- the dressing asked for while the kit look was off, now it is on (each
-- once; an error is reported and the rest still run)
function Shell:RunQueue()
	local q = self.queue
	if #q == 0 then
		return
	end
	self.queue = {}
	for i = 1, #q do
		local item = q[i]
		Reported(pcall(item[1], Kit, unpack(item, 2, item.n + 1)))
	end
end

-- the crest (or corner ring) and the plate where the look puts them (laid in
-- the modern look too, the crest hidden there: the plate's frame holds the
-- title)
function Shell:Lay()
	local frame, crest = self.frame, self.crest
	if crest then
		local size, x, y, point
		if self.ringAt == "top" then
			size = self.ringSize
			x, y, point = 0, self.kit and Kit:RailMiddle() or 0, "TOP"
		elseif self.gameCorner then
			-- (a window standing in for a game window: the game's portrait, its size and place, in both looks)
			size, x, y, point = PLAIN_CORNER, CORNER_X, CORNER_Y, "TOPLEFT"
		else
			size = self.ringSize
			x, y, point = self.ringX or CORNER_X, self.ringY or CORNER_Y, "TOPLEFT"
		end
		crest:SetSize(size, size)
		crest:ClearAllPoints()
		crest:SetPoint("CENTER", frame, point, x, y)
		self.crestTop, self.crestLeft = y + size / 2, point == "TOPLEFT" and (size / 2 - x) or 0
		if self.plateKind == "crest" and self.plate then
			self.plate:ClearAllPoints()
			self.plate:SetPoint("TOP", frame, "TOP", 0, y - size / 2 + PLATE_OVERLAP)
		end
	end
	-- the calm ground: the page stone's rect (inside the kit's outer rail)
	-- less the band
	local calm = self.calm
	if calm then
		local l, r, t, b = PAGE_INSET, PAGE_INSET, PAGE_INSET, PAGE_INSET
		if self.kit then
			local ins = Kit:OuterRailInset()
			l, r, t, b = ins[1], ins[2], ins[3], ins[4]
		end
		calm:ClearAllPoints()
		calm:SetPoint("TOPLEFT", frame, "TOPLEFT", l + CALM_BAND, -(t + CALM_BAND))
		calm:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(r + CALM_BAND), b + CALM_BAND)
	end
end

-- the close button as the look has it: the kit's on the plate's line, the
-- plate's height; the modern look's at its own size on the header's middle
-- line, its right edge on the content inset (a brand row: where opts.brand
-- puts it)
function Shell:LayClose()
	local close = self.close
	if not close then
		return
	end
	close:ClearAllPoints()
	if self.kit then
		close:SetSize(PLATE_FIT, PLATE_FIT)
		close:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -2, -1)
		-- (0.20.1) a plate on the rail takes it inside, left of its right cap, as a game window's (its Refit)
		local rep = self.plateRep
		local strip = rep and rep.strip
		if strip and strip:IsShown() then
			rep:Refit()
		end
	else
		close:SetSize(self.closeSize, self.closeSize)
		local at = self.brandClose
		local x = at and tonumber(at[1]) or -self.inset
		local y = at and tonumber(at[2]) or -FLAT.STRIP / 2
		close:SetPoint("RIGHT", self.frame, "TOPRIGHT", x, y)
	end
end

-- a painted-look-only region (the kit's anchors: the rock its page stone
-- replaces, the tint, the calm ground, the plate's box, the crest): shown
-- only while the kit dresses the window
function Shell:Painted(region)
	if region then
		self.paintedOnly[#self.paintedOnly + 1] = region
		region:SetShown(self.kit)
	end
	return region
end

-- The modern look's own parts, made the first time it shows (a window opened
-- in the painted look makes none until a switch): the flat ground in its
-- edge, the soft shade round the window, the emblem in the kit's round rim on
-- its dark disc (mouse off: it never lights or takes a drag), a brand row's
-- hairline. Each is a plain-look region (shell:Plain): hidden with the kit;
-- the shade also with UI Shade's Windows area (ShadeWindow).
function Shell:BuildModern()
	if self.modernBuilt then
		return
	end
	self.modernBuilt = true
	local frame = self.frame
	local ground = W.Solid(frame, "BACKGROUND", "mainWindow", 1)
	ground:SetDrawLayer("BACKGROUND", FLAT.GROUND)
	ground:SetAllPoints(frame)
	self.ground = self:Plain(ground)
	self.groundEdges = W.Edges(frame, "border", "BORDER")
	for i = 1, #self.groundEdges do
		self:Plain(self.groundEdges[i])
	end
	local shade = MelloUI.Shade and MelloUI.Shade:Band(frame, FLAT.SHADE)
	if shade then
		shade:Anchor(frame)
		self.shade = shade
		self:ShadeWindow()
		if not shadeListening then
			shadeListening = true
			MelloUI:On("shade", Shells_OnShade, "Kit own windows")
		end
	end
	if self.emblemTexture then
		local spec = self.brandShape and FLAT[self.brandShape]
		local rim = W.GlyphButton(frame, spec and spec.rim or FLAT.RIM, nil, FLAT.RIM_OPTS)
		rim:SetFrameLevel(frame:GetFrameLevel() + LEVEL_CREST)
		rim:EnableMouse(false)
		rim:SetIcon(self.emblemTexture)
		rim.icon:SetTexCoord(0, 1, 0, 1)   -- (the whole emblem: a round picture, not a spell icon's trimmed square)
		local C = self.bagPortrait ~= nil and rawget(_G, "C_Container")
		if type(C) == "table" and C.SetBagPortraitTexture then
			-- (ring.bag: the bag's own portrait, as the game's bag window draws it)
			pcall(C.SetBagPortraitTexture, rim.icon, self.bagPortrait)
		end
		rim:SetKit(Kit)
		self.rim = self:Plain(rim)
	end
	if self.brandShape == "row" then
		-- (on a holder of its own over the column, LevelBrand: a region of the
		-- window itself would lie under the column's body, a child frame)
		local holder = CreateFrame("Frame", nil, frame)
		holder:SetFrameLevel(frame:GetFrameLevel() + LEVEL_CREST)
		holder:EnableMouse(false)
		local line = W.Solid(holder, "ARTWORK", "border", 1)
		line:SetHeight(1)
		self.brandHolder = holder
		self.brandLine = self:Plain(line)
	end
end

-- the window's soft shade as UI Shade has it, as the rim's round shade
-- partner: shown in the modern look while the Windows area's shade is on
-- (Kit:ShadeOn), at FLAT.SHADE's alpha scaled by the shade's strength (that
-- alpha at the default strength)
function Shell:ShadeWindow()
	local shade = self.shade
	if not shade then
		return
	end
	local on = not self.kit and not (Kit.ShadeOn and not Kit:ShadeOn("windows"))
	shade:SetShown(on)
	local settings = Kit.shadeSettings
	local default = settings and Num(settings.default)
	if on and default and default > 0 and Kit.ShadeStrength then
		local alpha = FLAT.SHADE.alpha * Kit:ShadeStrength() / default
		if shade.alpha ~= alpha then
			shade:SetStrength(alpha)
		end
	end
end

-- the brand's parts over its column: a column in the window's body (a child
-- frame, or deeper) stands over the window's own regions and its low
-- children, so the rim and a row's hairline go one level over it, the title's
-- plate and the close kept over them (raised only, never lowered)
function Shell:LevelBrand(column)
	local base = Num(self.frame:GetFrameLevel()) or 0
	local owner = column.GetFrameLevel and column or (column.GetParent and column:GetParent())
	local level = math.max(base + LEVEL_CREST, (owner and Num(owner:GetFrameLevel()) or base) + 1)
	if self.rim then
		self.rim:SetFrameLevel(level)
	end
	if self.brandHolder then
		self.brandHolder:SetFrameLevel(level)
	end
	local plate, close = self.plate, self.close
	local top = level
	if plate then
		top = Num(plate:GetFrameLevel()) or level
		if top <= level then
			top = level + 1
			plate:SetFrameLevel(top)
		end
	end
	if close and (Num(close:GetFrameLevel()) or 0) <= top then
		close:SetFrameLevel(top + 1)
	end
end

-- The modern look laid: the emblem's rim and the title on the strip, or at
-- the head of the brand's column (none yet: left where they are, until
-- shell:Brand hands it), the title in the title face
function Shell:LayModern()
	local frame, rim, title = self.frame, self.rim, self.title
	local shape = self.brandShape
	local column = self.brandColumn
	local spec = shape and FLAT[shape]
	if spec and not column then
		return
	end
	if spec then
		self:LevelBrand(column)
	end
	if rim then
		rim:ClearAllPoints()
	end
	if title then
		title:ClearAllPoints()
		Kit:TitleFont(title, true)
	end
	if shape == "block" then
		if rim then
			rim:SetPoint("CENTER", column, "TOP", 0, -spec.rimY)
		end
		if title then
			title:SetJustifyH("CENTER")
			title:SetPoint("CENTER", column, "TOP", 0, -spec.titleY)
		end
	elseif shape == "row" then
		if rim then
			rim:SetPoint("CENTER", column, "TOPLEFT", spec.rim / 2, -spec.rimY)
		end
		if title then
			title:SetJustifyH("LEFT")
			title:SetPoint("LEFT", column, "TOPLEFT", (rim and spec.rim + spec.gap or 0), -spec.rimY)
			title:SetPoint("RIGHT", column, "TOPRIGHT", 0, -spec.rimY)
		end
		local holder, line = self.brandHolder, self.brandLine
		if holder then
			holder:ClearAllPoints()
			holder:SetAllPoints(column)
		end
		if line then
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -spec.line)
			line:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, -spec.line)
		end
	else
		local inset, mid = self.inset, -FLAT.STRIP / 2
		if rim then
			rim:SetPoint("LEFT", frame, "TOPLEFT", inset, mid)
		end
		if title then
			title:SetJustifyH("LEFT")
			title:SetPoint("LEFT", frame, "TOPLEFT", inset + (rim and FLAT.RIM + FLAT.GAP or 0), mid)
			title:SetPoint("RIGHT", frame, "TOPRIGHT", -(inset + (self.close and self.closeSize + FLAT.GAP or 0)), mid)
		end
	end
end

-- the drag band: full width from the top, down to the look's grab line (the
-- painted look's opts.grabBottom; the strip's foot, or opts.brand's grab)
function Shell:LayGrab()
	local grab = self.grab
	grab:ClearAllPoints()
	grab:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
	grab:SetPoint("BOTTOMRIGHT", self.frame, "TOPRIGHT", 0, self.kit and self.grabBottom or self.flatGrab)
end

function Shell:Inset(edge, top)
	if self.kit then
		return edge, top
	end
	return self.inset, self.brandShape and -self.inset or -FLAT.TOP
end

function Shell:Brand(column)
	self.brandColumn = column
	if not self.kit then
		self:LayModern()
		self:LayClose()
	end
	local spec = self.brandShape and FLAT[self.brandShape]
	return spec and spec.room or 0
end

-- the look switched (the shell's own state, then its listeners)
function Shell:Switch(on)
	self.kit = on
	self:Lay()
	local reps, painted = self.reps, self.paintedOnly
	if on then
		-- (the kit's anchors shown first: its reps and its dressing stand on them)
		for i = 1, #painted do
			painted[i]:SetShown(true)
		end
		for i = 1, #reps do
			reps[i]:Enable()
		end
		for _, entry in ipairs(self.skin.followers) do
			entry.rep:SetShown(entry.region:IsShown())
		end
		self:RunQueue()
		-- (a choice made while the kit look was off)
		self:SetBackground()
	else
		for i = 1, #reps do
			reps[i]:Disable()
		end
		for i = 1, #painted do
			painted[i]:SetShown(false)
		end
		self:BuildModern()
		-- (after the plates' own switch -- off, the title and the close back where they found them: 0.20.1)
		self:LayModern()
	end
	self:LayGrab()
	self:LayClose()
	for i = 1, #self.plains do
		self.plains[i]:SetShown(not on)
	end
	self:ShadeWindow()
	for i = 1, #self.onKit do
		local ok, err = pcall(self.onKit[i], self, on)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

function Shell:SetKit(on)
	on = on and true or false
	if on == self.kit or not self.frame:IsShown() then
		return
	end
	self:Switch(on)
	if self.fit then
		self:Fit()
	end
end

-- The page's piece (opts.background) laid on the kit's page stone: the
-- picture's own SetPiece (the one the bank's page takes the same choice
-- through), which repeats a tile at the UI's one density and lays it again
-- as the page shows or changes size; "dark" painted by its palette key (a
-- new palette paints it again). `value`: a new choice (a value or a function
-- answering one); nil: the window's choice read again. A window that has
-- none keeps the kit's stone (nothing done), as does a page not made yet
-- (the kit's dressing reads it then).
function Shell:SetBackground(value)
	if value ~= nil then
		self.background = value
	end
	local page, choice = self.page, self.background
	if choice == nil or not (page and page.SetPiece) then
		return
	end
	if type(choice) == "function" then
		choice = Reported(pcall(choice))
	end
	page:SetPiece(type(choice) == "string" and choice or nil)
end

-- on every show: the look as Kit:IsOn answers now (a switch made while it
-- was hidden), the fit, the sound (`opened`: a real open, not the UI shown
-- again around the open window)
function Shell:Showing(opened)
	local want = Kit:IsOn(self.area) and true or false
	if want ~= self.kit then
		self:Switch(want)
	elseif want then
		-- (a choice made while it was hidden: a profile loaded, ...)
		self:SetBackground()
	end
	if self.fit then
		self:Fit()
	end
	if self.sounds and opened then
		MelloUI:PlayUISound("window_open")
	end
end

-- how far the window's dressing reaches past its edges (left, right, top,
-- bottom, in its own units): the outer rail with the kit, the crest or the
-- corner ring, the plate riding the rail; nothing in the modern look (its
-- shade is no part to keep on the screen)
function Shell:Overhang()
	if not self.kit then
		return 0, 0, 0, 0
	end
	local out = Kit:OuterRailOutset()
	local l, r, t, b = out, out, out, out
	if self.crest then
		t = math.max(t, self.crestTop or 0)
		l = math.max(l, self.crestLeft or 0)
	end
	local rep = self.plateRep
	if self.kit and self.plateKind == "rail" and rep and rep.strip then
		local lift = Kit:TitleOnRail(rep.strip)
		t = math.max(t, lift + (rep.strip.height or 0) / 2)
	end
	return l, r, t, b
end

-- scaled down to fit the screen with its dressing (never up, and not while
-- the mover holds a scale the user gave it), then kept on the screen with
-- its crest
function Shell:Fit()
	local frame = self.frame
	local key = self.mover and self.mover.key
	local pos = key ~= nil and MelloUI:GetPosition(key)
	if not (pos and pos.scale) then
		local okS, sw, sh = pcall(UIParent.GetSize, UIParent)
		sw, sh = okS and Num(sw), okS and Num(sh)
		local w, h = Num(frame:GetWidth()), Num(frame:GetHeight())
		if sw and sh and w and h and sw > 0 and sh > 0 and w > 0 and h > 0 then
			local l, r, t, b = self:Overhang()
			local fit = math.min(1, (sw - FIT_MARGIN) / (w + l + r), (sh - FIT_MARGIN) / (h + t + b))
			local scale = Num(frame:GetScale()) or 1
			if math.abs(scale - fit) > 0.001 then
				Kit:SetFrameScale(frame, fit)
			end
		end
	end
	MelloUI:FitOnScreen(frame, self.bounds)
end

-- a window's name put in UISpecialFrames (once) or taken out
local function Special(name, on)
	local list = UISpecialFrames
	if not name or type(list) ~= "table" then
		return
	end
	for i = #list, 1, -1 do
		if list[i] == name then
			if on then
				return
			end
			table.remove(list, i)
		end
	end
	if on then
		tinsert(list, name)
	end
end

-- (while a question holds Escape, another shell's setting is only
-- recorded: its name comes back when the question closes; the same while
-- the shell's own hold is on)
function Shell:SetEscape(on)
	on = on and true or false
	self.escape = on
	Special(self.frame:GetName(), on and not self.escapeHeld and not (escapeHold and escapeHold ~= self))
end

-- A piece of the window that Escape closes first (a picture row's flyout,
-- W.PictureMenu, in UISpecialFrames itself) holds the window's Escape while
-- it is open, as a question holds every shell's (MelloUI:Confirm, below):
-- the window's name out of the list, its setting kept, and back a frame
-- after the hold ends -- never inside the game's walk of the list, which
-- would still find it there and close the window with its flyout. A hold
-- taken again within that frame keeps it out.
local released = setmetatable({}, { __mode = "k" })   -- [shell] = true: its hold ends at the next frame

local function EndHolds()
	for shell in pairs(released) do
		released[shell] = nil
		shell.escapeHeld = nil
		Special(shell.frame:GetName(), shell.escape and not (escapeHold and escapeHold ~= shell))
	end
end

function Shell:HoldEscape(on)
	if on then
		released[self] = nil
		self.escapeHeld = true
		Special(self.frame:GetName(), false)
	elseif self.escapeHeld and not released[self] then
		released[self] = true
		C_Timer.After(0, EndHolds)
	end
end

--------------------------------------------------------------------------------
-- Kit:OwnWindow
--------------------------------------------------------------------------------

-- the shell a window already has (nil for none; nothing is made): a piece
-- that opens over a window finds its window's shell whatever its caller
-- passed (a picture row's flyout, W.PictureMenu)
function Kit:ShellOf(frame)
	return frame and shells[frame] or nil
end

function Kit:OwnWindow(frame, opts)
	if not frame then
		return nil
	end
	if shells[frame] then
		return shells[frame]
	end
	opts = opts or {}
	local shell = setmetatable({
		frame = frame, area = opts.area, kit = self:IsOn(opts.area) and true or false,
		reps = {}, queue = {}, plains = {}, onKit = {}, bounds = {}, paintedOnly = {},
		fit = opts.fit and true or false, sounds = opts.sounds and true or false,
		background = opts.background,
		-- (the modern look's: its content inset, the drag band of each look)
		inset = tonumber(opts.inset) or FLAT.IN, grabBottom = opts.grabBottom or GRAB_BOTTOM, flatGrab = -FLAT.STRIP,
	}, Shell)
	local brand = opts.brand
	if brand then
		local spec = type(brand) == "table" and brand or {}
		local shape = type(brand) == "table" and brand.shape or brand
		shell.brandShape = shape == "row" and "row" or "block"
		shell.flatGrab = tonumber(spec.grab) or shell.flatGrab
		shell.brandClose = type(spec.close) == "table" and spec.close or nil
	end
	shell.skin = { reps = shell.reps, followers = {} }
	shell.replace = function(region, ropts)
		return shell:Replace(region, ropts)
	end
	shells[frame] = shell
	local base = frame:GetFrameLevel()

	-- the page: the game's rock, the region the kit's page stone replaces
	-- (DressFrame; it shows only if the stone is missing)
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
	bg:SetTexture(ROCK, "REPEAT", "REPEAT")
	bg:SetHorizTile(true)
	bg:SetVertTile(true)
	local bgIn = (opts.ring and opts.ring.at == "tl") and GAME_BG_IN or GAME_BG_IN_NOPORTRAIT
	bg:SetPoint("TOPLEFT", frame, "TOPLEFT", bgIn, -GAME_BG_TOP)
	bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -GAME_BG_EDGE, GAME_BG_EDGE)
	-- (its palette tint, the painted look's only)
	local tint = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	tint:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_INSET, -PAGE_INSET)
	tint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAGE_INSET, PAGE_INSET)
	self:Paint(tint, "mainWindow", "fill", 0.45)
	shell.bg, shell.tint = shell:Painted(bg), shell:Painted(tint)
	-- the calm ground over them both (sublevel 3: over the kit's stone too,
	-- a region in the rock's layer and sublevel), laid by the look (Lay);
	-- the painted look's only (the modern look's ground is its own)
	if opts.calm then
		local calm = frame:CreateTexture(nil, "BACKGROUND", nil, 3)
		self:Paint(calm, "mainWindow", "fill", 1)
		shell.calm = shell:Painted(calm)
	end

	-- the drag strip across the top (under the crest and the plate, which
	-- take no mouse), down to the look's grab line (LayGrab)
	local grab = CreateFrame("Frame", nil, frame)
	grab:SetFrameLevel(base + LEVEL_GRAB)
	grab:EnableMouse(true)
	shell.grab = grab
	shell:LayGrab()

	-- the crest (or the corner ring) and its emblem (the region the kit's ring replaces; under ring.game the bag's
	-- portrait)
	local ring = opts.ring
	if ring then
		shell.ringAt = ring.at == "tl" and "tl" or "top"
		-- ring.game (a window standing in for a game window: the bag window): the game's own portrait corner, its
		-- art, its portrait's size and place, with the painted look -- no ring of ours (the user, 2026-10-10: the game
		-- windows' top-left portraits stay the game's; "you did not make that change on the backpack"); the modern
		-- look's strip wears its portrait in the kit's rim (onelook stage B; waiting for the user's yes)
		shell.gameCorner = (ring.game and shell.ringAt == "tl") and true or nil
		shell.ringSize = (self:Size("window/portrait_ring")) * (ring.scale or 1)
		shell.ringX, shell.ringY = tonumber(ring.x), tonumber(ring.y)
		shell.emblemTexture = ring.texture or LOGO
		shell.bagPortrait = ring.bag   -- (the modern look's rim wears the bag's portrait too)
		local crest = CreateFrame("Frame", nil, frame)
		crest:SetFrameLevel(base + (shell.gameCorner and LEVEL_GAME_PORTRAIT or LEVEL_CREST))
		crest:EnableMouse(false)
		local emblem = crest:CreateTexture(nil, "ARTWORK")
		emblem:SetTexture(shell.emblemTexture)
		emblem:SetAllPoints(crest)
		if shell.gameCorner then
			-- (a bag's own portrait as the game's bag window draws it, C_Container.SetBagPortraitTexture: ring.bag)
			local C = rawget(_G, "C_Container")
			if ring.bag ~= nil and type(C) == "table" and C.SetBagPortraitTexture then
				pcall(C.SetBagPortraitTexture, emblem, ring.bag)
			end
			-- (the game's portrait: round, its circle mask where the template has it)
			local mask = crest:CreateMaskTexture()
			mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetPoint("TOPLEFT", emblem, "TOPLEFT", GAME_MASK_IN, 0)
			mask:SetPoint("BOTTOMRIGHT", emblem, "BOTTOMRIGHT", -GAME_MASK_IN, GAME_MASK_UP)
			emblem:AddMaskTexture(mask)
		end
		shell.crest, shell.plainEmblem = shell:Painted(crest), emblem
		shell.bounds[#shell.bounds + 1] = crest
	end

	-- the plate and the title on it; its palette box the region the kit's plate replaces (DressPlate)
	if opts.plate then
		shell.plateKind = opts.plate == "rail" and "rail" or "crest"
		local plate = CreateFrame("Frame", nil, frame)
		plate:SetFrameLevel(base + LEVEL_PLATE)
		plate:EnableMouse(false)
		if shell.plateKind == "rail" then
			-- a game window's title container
			plate:SetPoint("TOPLEFT", frame, "TOPLEFT", 58, -1)
			plate:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -1)
			plate:SetHeight(PLATE_FIT)
		else
			plate:SetSize(opts.plateWidth or 200, PLATE_FIT * 1.5)
		end
		local fill = plate:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints(plate)
		self:Paint(fill, "raisedPanel", "fill", 1)
		shell.plateFill, shell.plateEdges = fill, W.Edges(plate, "trim")   -- (four 1 px lines, the widget set's)
		-- (the modern look: no box, the title on its strip or brand)
		shell:Painted(fill)
		for i = 1, #shell.plateEdges do
			shell:Painted(shell.plateEdges[i])
		end
		local title = plate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("CENTER", plate, "CENTER", 0, 0)
		title:SetWordWrap(false)
		title:SetText(opts.title or "")
		self:Paint(title, "selectedTrim", "text")
		shell.plate, shell.title = plate, title
	end
	shell:Lay()

	if opts.close then
		-- (0.15.0: the widget set's flat close, "all flat", both looks; on the
		-- title plate's line, the plate's height)
		local close = W.CloseButton(frame, shell)
		close:SetFrameLevel(base + LEVEL_CLOSE)
		Perf.SetScript(close, "OnClick", Close_OnClick)
		shell.close = close
		shell.closeSize = Num(close:GetWidth()) or PLATE_FIT   -- (the widget's own size: the modern look's)
		Kit.ownClose[frame] = close
		shell:LayClose()
	end

	-- show and hide (before the mover, whose hooks come after)
	Perf.HookScript(frame, "OnShow", Shell_OnShow)
	Perf.HookScript(frame, "OnHide", Shell_OnHide)

	-- the look follows its area; the fit follows the UI scale
	if opts.area then
		MelloUI:On("look:" .. opts.area, function(on)
			shell:SetKit(on)
		end, shell)
	end
	if shell.fit and not scaleListening then
		scaleListening = true
		MelloUI:On("scale", Shells_OnScale, "Kit own windows")
	end
	if opts.escape then
		shell:SetEscape(true)
	end

	-- the mover (Core's one registry: its place, and its plate in Edit
	-- Layout), before the kit's dressing
	local mover = opts.mover
	if mover then
		shell.mover = MelloUI:RegisterMover(frame, grab, {
			key = mover.key, anchor = mover.anchor, default = mover.default or Centre, save = mover.save, reset = mover.reset,
			min = mover.min, max = mover.max, base = mover.base, plainDrag = mover.plainDrag, with = shell.bounds,
			label = mover.label, page = mover.page, group = mover.group, placeholder = mover.placeholder,
			resize = mover.resize,
		})
	end

	-- the kit's dressing: now, or at the first switch on (the painted reskin's, MelloUI_Oldschool/Modules/KitWindowPainted.lua; none
	-- without it)
	local dress = Kit.__.ShellDress
	if dress then
		shell:Kit(dress.Frame, shell)
		if ring then
			shell:Kit(dress.Ring, shell)
		end
		if opts.plate then
			shell:Kit(dress.Plate, shell)
		end
	end
	if not shell.kit then
		shell:BuildModern()
		shell:LayModern()
	end
	return shell
end

--------------------------------------------------------------------------------
-- MelloUI:Confirm: the addon's one question dialog
--
--   MelloUI:Confirm({
--     text = "Replace ...?",   the question
--     accept = "Replace",      the accept button's label ("OK" when none)
--     cancel = "Cancel",       the cancel button's label ("Cancel" when none)
--     onAccept = fn,           fn() once the accept button closed it
--     onCancel = fn,           fn() once the cancel button, Escape or a newer
--                              question closed it (optional)
--   })
-- One dialog for all of MelloUI's questions (one system per job): an own
-- window on the shell above -- the corner ring with the emblem, "MelloUI"
-- on the plate on the rail, Escape (which cancels), the fit, the sounds, the
-- calm ground (0.15.0); in the modern look the strip (it has no side column:
-- the emblem's rim, "MelloUI", no close) and the panel on the one inset
-- (ConfirmLay) -- a UIParent child at DIALOG strata, the question on
-- the dark inner panel (W.Panel, 2e) in the palette's text colour, the two
-- buttons the widget set's flat ones (the accept one the main action's
-- gold). Made on its first question, never at login (2f). One question at a
-- time: a second call replaces the one shown, which counts as cancelled.
-- Escape is the question's alone while it is shown: the window it was asked
-- from stays open (the other shells' Escape held, below).
-- It never uses the game's popups (StaticPopup_Show, StaticPopupDialogs):
-- with the Gamepad UI on, their gamepad handler and binding stack would run
-- as MelloUI's code, and the game then blocks its own protected calls (the
-- "blocked" popup, the Escape freeze). The D-pad does not reach this dialog
-- (it is not a game panel; the cursor does), so nothing is asked here on its
-- own while the Gamepad UI is on (the installer's alt question waits).
--------------------------------------------------------------------------------

local CONFIRM_TITLE = "MelloUI"
local CONFIRM_W = 420
local CONFIRM_Y = 120          -- its centre this far above the screen's
local CONFIRM_TOP = -64        -- the question's panel under the corner ring
local CONFIRM_EDGE = 28        -- the panel's margin in the window (on the calm ground, clear of its band)
local CONFIRM_PAD = 14         -- the question's margin in the panel
local CONFIRM_BODY = 64        -- the panel's least height
local CONFIRM_FOOT = 66        -- the band of the buttons under the panel
local CONFIRM_BUTTON_W, CONFIRM_BUTTON_H, CONFIRM_BUTTON_Y = 120, 24, 28
local CONFIRM_GAP = 12         -- between the two buttons
-- (the modern look, pick C: no side column, so the strip; the panel on the one inset from FLAT.TOP, the same 14
-- from the panel to the buttons: a 64 high question stands 150 high, 194 painted)
local CONFIRM_FLAT_FOOT = 56

-- the dialog's parts (made on the first question) and the question shown
local confirm = { frame = nil, shell = nil, body = nil, text = nil, accept = nil, cancel = nil, opts = nil }

-- The game's Escape hides every shown UISpecialFrames window at once
-- (CloseSpecialWindows, after the game's own dialogs had their turn), so the
-- window a question was asked from (the configurator, the Restock List)
-- would close with it, where the game's popup took the key alone. While a
-- question is shown the other shells' names leave the list (their setting
-- kept: a SetEscape meanwhile is only recorded), and they come back a frame
-- after it closes: never inside the game's walk of the list, which would
-- still find them there and hide them all the same.
local function HoldEscape()
	if escapeHold then
		return
	end
	escapeHold = confirm.shell
	for frame, shell in pairs(shells) do
		if shell ~= escapeHold and shell.escape then
			Special(frame:GetName(), false)
		end
	end
end

local function ReleaseEscape()
	-- (a question shown again meanwhile holds on)
	if not escapeHold or confirm.opts then
		return
	end
	escapeHold = nil
	for frame, shell in pairs(shells) do
		if shell.escape and not shell.escapeHeld then
			Special(frame:GetName(), true)
		end
	end
end

-- the question answered: the dialog closed first, then the answer's own
-- function (a question it asks in turn is the one shown then)
local function Answer(accepted)
	local opts = confirm.opts
	confirm.opts = nil
	confirm.frame:Hide()
	C_Timer.After(0, ReleaseEscape)
	if not opts then
		return
	end
	local fn
	if accepted then
		fn = opts.onAccept
	else
		fn = opts.onCancel
	end
	if type(fn) == "function" then
		fn()
	end
end

local Accept_OnClick = Shared("OnClick on the confirm dialog's accept button", function()
	Answer(true)
end, "script")

local Cancel_OnClick = Shared("OnClick on the confirm dialog's cancel button", function()
	Answer(false)
end, "script")

-- Escape (UISpecialFrames) hides it: the question cancelled. A hide while it
-- stays shown is the parent's (Alt+Z, a cinematic): the question waits.
local Confirm_OnHide = Shared("OnHide on the confirm dialog", function(frame)
	if frame:IsShown() or not confirm.opts then
		return
	end
	Answer(false)
end, "script")

-- a button's label, the button widened for a long one
local function Label(button, text)
	button:SetText(text)
	local fs = button:GetFontString()
	local w = fs and Num(fs:GetStringWidth())
	button:SetWidth(math.max(CONFIRM_BUTTON_W, (w or 0) + 2 * CONFIRM_PAD))
end

-- The dialog laid for the look on show and the question in it (at every
-- question, and the shell's OnKit): the panel under the corner ring and the
-- rail's plate (painted), or under the strip on the one inset (the modern
-- look); the question's width in it, the panel as tall as the question, the
-- buttons the same 14 under it, the window round them
local function ConfirmLay(sh)
	local f, body, text = confirm.frame, confirm.body, confirm.text
	local edge, top = sh:Inset(CONFIRM_EDGE, CONFIRM_TOP)
	local foot = sh.kit and CONFIRM_FOOT or CONFIRM_FLAT_FOOT
	body:ClearAllPoints()
	body:SetPoint("TOPLEFT", f, "TOPLEFT", edge, top)
	body:SetPoint("TOPRIGHT", f, "TOPRIGHT", -edge, top)
	text:SetWidth(CONFIRM_W - 2 * (edge + CONFIRM_PAD))
	local h = Num(text:GetStringHeight()) or 0
	local height = math.max(CONFIRM_BODY, h + 2 * CONFIRM_PAD)
	body:SetHeight(height)
	local y = foot - CONFIRM_FOOT + CONFIRM_BUTTON_Y
	confirm.accept:ClearAllPoints()
	confirm.accept:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -CONFIRM_GAP / 2, y)
	confirm.cancel:ClearAllPoints()
	confirm.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", CONFIRM_GAP / 2, y)
	f:SetHeight(-top + height + foot)
end

local function BuildConfirm()
	local f = CreateFrame("Frame", "MelloUIConfirmDialog", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetSize(CONFIRM_W, -CONFIRM_TOP + CONFIRM_BODY + CONFIRM_FOOT)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, CONFIRM_Y)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:Hide()
	-- (its own script before the shell's hooks: SetScript drops hooks)
	Perf.SetScript(f, "OnHide", Confirm_OnHide)
	local shell = Kit:OwnWindow(f, { area = "config", ring = { at = "tl" }, plate = "rail", title = CONFIRM_TITLE,
		escape = true, fit = true, sounds = true, calm = true })
	-- the question on the dark inner panel on the calm ground (the eye strain
	-- rule; one surface, one panel)
	local body = W.Panel(f)
	local text = W.Text(body, "GameFontHighlight", nil, "text")
	text:SetJustifyH("CENTER")
	text:SetJustifyV("MIDDLE")
	text:SetPoint("CENTER", body, "CENTER", 0, 0)
	-- accept on the left, cancel on the right (as the game's dialogs); the
	-- accept one the main action
	local accept = W.Button(f, "", CONFIRM_BUTTON_W, shell, { height = CONFIRM_BUTTON_H, onClick = Accept_OnClick, gold = true })
	local cancel = W.Button(f, "", CONFIRM_BUTTON_W, shell, { height = CONFIRM_BUTTON_H, onClick = Cancel_OnClick })
	confirm.frame, confirm.shell, confirm.body, confirm.text = f, shell, body, text
	confirm.accept, confirm.cancel = accept, cancel
	ConfirmLay(shell)
	-- (a look switched while a question shows, or at its show)
	shell:OnKit(ConfirmLay)
end

function MelloUI:Confirm(opts)
	if type(opts) ~= "table" then
		return
	end
	if not confirm.frame then
		BuildConfirm()
	end
	local f = confirm.frame
	local replaced = confirm.opts
	confirm.opts = opts
	HoldEscape()
	confirm.text:SetText(opts.text or "")
	Label(confirm.accept, opts.accept or "OK")
	Label(confirm.cancel, opts.cancel or "Cancel")
	-- the panel as tall as the question
	ConfirmLay(confirm.shell)
	if f:IsShown() then
		confirm.shell:Fit()
	else
		f:Show()
	end
	f:Raise()
	-- the question it took the place of: cancelled (after, so a question
	-- its answer asks in turn comes last); the same one asked again stays
	if replaced and replaced ~= opts and type(replaced.onCancel) == "function" then
		replaced.onCancel()
	end
end
