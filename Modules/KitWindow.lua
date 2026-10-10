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
--                            `mainWindow` ground over the page, the stone (the
--                            kit's, or the plain look's tinted rock) left only
--                            as a band CALM_BAND wide inside the rail
--                            (shell.calm); the window's panels (W.Panel) lie
--                            on that ground
--     background = fn | value,  the page stone's piece in the kit look (0.19.4,
--                            the options audit: the bags' Window Background
--                            on the bag window): a Window Background value
--                            (Kit.buttonLooks.backgrounds: a tile repeated at
--                            the UI's one density, or "dark", the palette's
--                            inner panel) or a function answering one, read
--                            when the kit dresses the page, at every switch
--                            on and show, and on shell:SetBackground(). It
--                            stands in for the stone on the stone's own
--                            texture (one surface); nil: the kit's own stone.
--                            The plain look keeps the game's rock
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
-- shell.crest (the crest's / corner ring's square, both looks), shell.emblem
-- (the kit's, on the ring's disc; made with the kit), shell.plainEmblem,
-- shell.disc, shell.ring (the ring's rep), shell.plate (the plate's frame),
-- shell.plateRep, shell.title (FontString), shell.grab, shell.close,
-- shell.rail (the outer rail's rep), shell.page (the page stone's rep; both
-- made with the kit), shell.mover (Core's entry),
-- shell.reps, shell.replace (fn(region, opts) for Kit helpers that take a
-- replace function), shell.skin ({ reps, followers } for Kit helpers),
-- shell.bounds (what is kept on the screen with the frame).
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
-- The switch: the plain look is the window's own regions, which the kit's
-- replacements fade while they are enabled; switched off, every recorded rep
-- is disabled and they come back. Colours are palette keys (Kit:Paint), so a
-- new palette paints them again. Sounds only through MelloUI:PlayUISound.
-- The plain look is the GAME's window (docs/plans/game-look.md wave 4: the
-- own windows' areas follow the reskin, so the plain look shows with it
-- off): ButtonFrameTemplate's metal NineSlice (PortraitFrameTemplate's with
-- the corner ring, ButtonFrameTemplateNoPortrait's without), its rock in its
-- own colours under the title bar with the top streaks, no palette tint and
-- no calm ground (the panels on it are the game's insets: W.Panel), the
-- title in the game's gold on the bar, the game's close button at its place
-- (UIPanelCloseButton's art, TOPRIGHT -2, 1, 24 px: this client's own).
--
-- And, for the own windows' widgets and questions (the end of the file):
--   Kit:ChoicePicture(tile, kind, choice)   a look choice's picture (the
--                                picture rows, W.PictureRow / W.PictureMenu)
--   MelloUI:Confirm({ text, accept, cancel, onAccept, onCancel })
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Kit window")
local Shared = Perf.Shared
local C_Timer = Perf.C_Timer   -- (an Escape hold ends a frame later: the confirm dialog's, a flyout's)
local Kit = MelloUI.Kit
-- what the kit keeps beside the game's frames (Kit.lua: weak-keyed, never keys on them)
local pieceNameOf = MelloUI.Kept.pieceNameOf
local pieceOf = MelloUI.Kept.pieceOf
local Num = MelloUI.Safe.Number
local Secret = MelloUI.Safe.IsSecret
local W = MelloUI.Widgets   -- (Core/Widgets.lua loads before this file)

local TEXTURE_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\"
local LOGO = TEXTURE_PATH .. "LogoIcon.tga"                    -- the round emblem of the logo
local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"      -- the plain look's page (the kit's stone stands in for it)
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local PAGE_INSET = 6         -- the plain look's page (the rock and its tint) inside the frame's edge
local CALM_BAND = 14         -- the stone left round the calm ground, inside the rail (opts.calm)
local PLAIN_CREST = 88       -- the emblem alone on the top edge, without the kit
local PLAIN_CORNER = 62      -- ... in the corner: a game window's portrait
local CORNER_X, CORNER_Y = 26, -24   -- a game window's portrait centre from its top left (PortraitFrameTemplate: 62 px at -5, 7)
-- the game's window (ButtonFrameTemplate on this client): its rock from under
-- the title bar (2 in with the portrait, 7 without, 21 down, 2 in at the
-- bottom), the streaks under the bar, the close button's size and place
local GAME_BG_TOP, GAME_BG_IN, GAME_BG_IN_NOPORTRAIT, GAME_BG_EDGE = 21, 2, 7, 2
local GAME_STREAKS = "_UI-Frame-TopTileStreaks"
local GAME_CLOSE, GAME_CLOSE_X, GAME_CLOSE_Y = 24, -2, 1
local PLATE_FIT = 20         -- the plate's fit height (a game window's title container); its painted part 1.5 x that
local PLATE_OVERLAP = 8      -- the short plate reaches this far up over the crest's bottom (the approved sketch)
local GRAB_BOTTOM = -40      -- the drag strip's bottom edge when none is given
local FIT_MARGIN = 16        -- a window scaled to fit leaves this much of the screen free
-- frame levels over the window's own
local LEVEL_GRAB, LEVEL_CREST, LEVEL_PLATE, LEVEL_CLOSE = 1, 4, 7, 8
-- (ring.game: the game's portrait corner over the title plate, its portrait over the corner art)
local LEVEL_GAME_CORNER, LEVEL_GAME_PORTRAIT = 9, 10
local GAME_CORNER_ATLAS = "UI-Frame-PortraitMetal-CornerTopLeft"
local GAME_CORNER_X, GAME_CORNER_Y = -13, 16   -- NineSliceLayouts' PortraitFrameTemplate TopLeftCorner

local EDGE_WIDE = { edgeFile = WHITE, edgeSize = 2 }

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

-- the short plate's title on its painted box, in the title face (2c), and
-- back on the plain plate (the rep's onEnable / onDisable)
local function Plate_OnEnable(rep)
	local fs = rep.melloTitle
	if fs and rep.strip then
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", rep.strip, "CENTER", 0, Kit:StripTextOffset(rep.strip))
		Kit:TitleFont(fs, true)
	end
end

local function Plate_OnDisable(rep)
	local fs = rep.melloTitle
	if fs then
		Kit:TitleFont(fs, false)
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", rep.melloPlate, "CENTER", 0, 0)
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

-- the crest (or corner ring) and the plate where the look puts them
function Shell:Lay()
	local frame, crest = self.frame, self.crest
	if crest then
		local size, x, y, point
		if self.ringAt == "top" then
			size = self.kit and self.ringSize or PLAIN_CREST
			x, y, point = 0, self.kit and Kit:RailMiddle() or 0, "TOP"
		elseif self.gameCorner then
			-- (a window standing in for a game window: the game's portrait, its size and place, in both looks)
			size, x, y, point = PLAIN_CORNER, CORNER_X, CORNER_Y, "TOPLEFT"
		else
			size = self.kit and self.ringSize or PLAIN_CORNER
			x, y, point = self.kit and self.ringX or CORNER_X, self.kit and self.ringY or CORNER_Y, "TOPLEFT"
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
	-- the calm ground: the page stone's rect (inside the kit's outer rail,
	-- or the plain look's rock) less the band
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

-- the plain look's own extras, made the first time it is shown: the metal
-- frame (the game's own nine-slice, else a plain edge) and the trim line
-- inside it
function Shell:BuildPlain()
	if self.plainBuilt then
		return
	end
	self.plainBuilt = true
	local frame = self.frame
	local framed = false
	if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
		-- the game's own window frame (this client's metal, its Camelot
		-- offsets in the layouts): over the window's content as the game's
		-- (its NineSlice stands over the window), under the corner ring's
		-- emblem's metal opening only where the layout has one; under a
		-- crest on the top edge
		local nine = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
		nine:SetAllPoints(frame)
		nine:SetFrameLevel(frame:GetFrameLevel() + (self.ringAt == "top" and LEVEL_CREST - 1 or LEVEL_CREST + 1))
		nine:EnableMouse(false)
		framed = pcall(NineSliceUtil.ApplyLayoutByName, nine,
			self.ringAt == "tl" and "PortraitFrameTemplate" or "ButtonFrameTemplateNoPortrait")
		if framed then
			self:Plain(nine)
		else
			nine:Hide()
		end
	end
	if not framed then
		local edge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		edge:SetAllPoints(frame)
		edge:SetBackdrop(EDGE_WIDE)
		Kit:Paint(edge, "border", "border")
		self:Plain(edge)
	end
	-- the streaks under the title bar (the template's TopTileStreaks)
	local streaks = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
	if pcall(streaks.SetAtlas, streaks, GAME_STREAKS, true) then
		streaks:SetHorizTile(true)
		streaks:SetPoint("TOPLEFT", self.bg, "TOPLEFT", 4, 0)
		streaks:SetPoint("TOPRIGHT", self.bg, "TOPRIGHT", 0, 0)
		self:Plain(streaks)
	else
		streaks:Hide()
	end
end

-- the close button as the look has it: the kit's on the plate's line, the
-- plate's height; the game's (the plain look) at its own size and place
function Shell:LayClose()
	local close = self.close
	if not close then
		return
	end
	close:ClearAllPoints()
	if self.kit then
		close:SetSize(PLATE_FIT, PLATE_FIT)
		close:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -2, -1)
	else
		close:SetSize(GAME_CLOSE, GAME_CLOSE)
		close:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", GAME_CLOSE_X, GAME_CLOSE_Y)
	end
end

-- the look switched (the shell's own state, then its listeners)
function Shell:Switch(on)
	self.kit = on
	self:Lay()
	self:LayClose()
	local reps = self.reps
	if on then
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
		self:BuildPlain()
	end
	for i = 1, #self.plains do
		self.plains[i]:SetShown(not on)
	end
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
-- corner ring, the plate riding the rail
function Shell:Overhang()
	local out = self.kit and Kit:OuterRailOutset() or 0
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
-- The kit's dressing (through shell:Kit: now, or at the first switch on)
--------------------------------------------------------------------------------

-- the page stone for the plain look's rock, the outer double rail (its
-- shell registration: the rail Edit Layout lights while the window is
-- dragged, Kit.shells[frame].outer, and its shade)
local function DressFrame(K, shell)
	local frame = shell.frame
	shell.page = shell:Replace(shell.bg, { as = "UI-Background-Rock", parent = frame, rect = frame, inset = K:OuterRailInset(), alsoFade = { shell.tint } })
	-- (the window's own choice in the stone's place, opts.background)
	shell:SetBackground()
	-- (body = false: the page stone above is the window's one background)
	local ok, rail = pcall(shell.Replace, shell, shell:Anchor(frame, "BORDER"), { as = "NineSlicePanelTemplate", parent = frame, rect = frame,
		body = false, skip = shell.ringAt == "tl" and "tl" or nil })
	if not ok then
		error(rail, 0)
	end
	if rail then
		shell.rail = rail
		shell.bounds[#shell.bounds + 1] = rail.object
	end
end

-- the ring in place of the plain emblem, its disc in the palette's inner
-- panel, the emblem on the disc (sized by the kit: no size of its own)
local function DressRing(K, shell)
	if shell.gameCorner then
		-- (ring.game: the game's own corner art where the game puts it, shown with the painted look: the plain
		-- look's own frame layout draws it there already; the emblem is the plain one, the game's portrait)
		local holder = CreateFrame("Frame", nil, shell.frame)
		holder:SetFrameLevel(shell.frame:GetFrameLevel() + LEVEL_GAME_CORNER)
		holder:EnableMouse(false)
		holder:SetAllPoints(shell.frame)
		local corner = holder:CreateTexture(nil, "OVERLAY")
		if pcall(corner.SetAtlas, corner, GAME_CORNER_ATLAS, true) then
			corner:SetPoint("TOPLEFT", shell.frame, "TOPLEFT", GAME_CORNER_X, GAME_CORNER_Y)
			-- (its rail stubs cut as on the game's windows, and the kit's rail cut at the ring: Kit:CutGameCorner)
			if holder.CreateMaskTexture and corner.AddMaskTexture then
				corner:AddMaskTexture(K:CornerCutMask(holder, corner))
			end
			if shell.rail and rawget(shell.rail, "outerCut") == nil then
				K:CutRailAtRing(shell.rail, corner)
			end
		else
			corner:Hide()
		end
		shell.gameCornerArt = holder
		shell:OnKit(function(sh, on)
			sh.gameCornerArt:SetShown(on)
		end)
		holder:SetShown(shell.kit)
		return
	end
	-- (`own`: an own window's corner ring; a game window's corner stays the game's, Kit:Replace)
	local rep = shell:Replace(shell.plainEmblem, { as = shell.ringAt == "top" and "MelloUI-Crest" or "UI-Frame-PortraitMetal-CornerTopLeft",
		rect = shell.crest, own = true })
	if not rep then
		return
	end
	shell.ring = rep
	local holder = rep.object
	local disc = K:RingDisc(rep, "innerPanel", holder, 6)
	local emblem = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	pieceOf[emblem] = true
	emblem:SetTexture(shell.emblemTexture)
	emblem:SetAllPoints(disc or rep.tex)
	local mask = holder:CreateMaskTexture()
	mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(emblem)
	emblem:AddMaskTexture(mask)
	shell.emblem, shell.disc = emblem, disc
end

-- the plate: the short one under the crest, or the standard one on the rail
-- (its title carried by the rule, 2c)
local function DressPlate(K, shell)
	local plate = shell.plate
	local rep
	if shell.plateKind == "rail" then
		plate.TitleText = shell.title
		rep = shell:Replace(shell.plateFill, { as = "TitleBar", parent = plate, rect = plate, fitHeight = PLATE_FIT, alsoFade = shell.plateEdges })
		if rep and rep.object then
			shell.bounds[#shell.bounds + 1] = rep.object
		end
	else
		rep = shell:Replace(shell.plateFill, { as = "MelloUI-TitlePlate", parent = plate, rect = plate, fitHeight = PLATE_FIT, alsoFade = shell.plateEdges })
		if rep then
			rep.melloTitle, rep.melloPlate = shell.title, plate
			rep.onEnable, rep.onDisable = Plate_OnEnable, Plate_OnDisable
			if shell.kit then
				Plate_OnEnable(rep)
			end
		end
	end
	shell.plateRep = rep
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
		reps = {}, queue = {}, plains = {}, onKit = {}, bounds = {},
		fit = opts.fit and true or false, sounds = opts.sounds and true or false,
		background = opts.background,
	}, Shell)
	shell.skin = { reps = shell.reps, followers = {} }
	shell.replace = function(region, ropts)
		return shell:Replace(region, ropts)
	end
	shells[frame] = shell
	local base = frame:GetFrameLevel()

	-- the plain look's page: the game's rock, in its own colours, from under
	-- the title bar (the kit's stone stands in for it)
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
	bg:SetTexture(ROCK, "REPEAT", "REPEAT")
	bg:SetHorizTile(true)
	bg:SetVertTile(true)
	local bgIn = (opts.ring and opts.ring.at == "tl") and GAME_BG_IN or GAME_BG_IN_NOPORTRAIT
	bg:SetPoint("TOPLEFT", frame, "TOPLEFT", bgIn, -GAME_BG_TOP)
	bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -GAME_BG_EDGE, GAME_BG_EDGE)
	-- (its palette tint, the painted look's only: none in the game's)
	local tint = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	tint:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_INSET, -PAGE_INSET)
	tint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAGE_INSET, PAGE_INSET)
	self:Paint(tint, "mainWindow", "fill", 0.45)
	MelloUI.Look.Hide(tint)
	shell.bg, shell.tint = bg, tint
	-- the calm ground over them both (sublevel 3: over the kit's stone too,
	-- a region in the rock's layer and sublevel), laid by the look (Lay);
	-- the painted look's only (the game's windows show their rock)
	if opts.calm then
		local calm = frame:CreateTexture(nil, "BACKGROUND", nil, 3)
		self:Paint(calm, "mainWindow", "fill", 1)
		MelloUI.Look.Hide(calm)
		shell.calm = calm
	end

	-- the drag strip across the top (under the crest and the plate, which
	-- take no mouse)
	local grab = CreateFrame("Frame", nil, frame)
	grab:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	grab:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, opts.grabBottom or GRAB_BOTTOM)
	grab:SetFrameLevel(base + LEVEL_GRAB)
	grab:EnableMouse(true)
	shell.grab = grab

	-- the crest (or the corner ring) and the plain look's emblem in it
	local ring = opts.ring
	if ring then
		shell.ringAt = ring.at == "tl" and "tl" or "top"
		-- ring.game (a window standing in for a game window: the bag window): the game's own portrait corner, its
		-- art, its portrait's size and place, in both looks -- no ring of ours (the user, 2026-10-10: the game
		-- windows' top-left portraits stay the game's; "you did not make that change on the backpack")
		shell.gameCorner = (ring.game and shell.ringAt == "tl") and true or nil
		shell.ringSize = (self:Size("window/portrait_ring")) * (ring.scale or 1)
		shell.ringX, shell.ringY = tonumber(ring.x), tonumber(ring.y)
		shell.emblemTexture = ring.texture or LOGO
		local crest = CreateFrame("Frame", nil, frame)
		crest:SetFrameLevel(base + (shell.gameCorner and LEVEL_GAME_PORTRAIT or LEVEL_CREST))
		crest:EnableMouse(false)
		local emblem = crest:CreateTexture(nil, "ARTWORK")
		emblem:SetTexture(shell.emblemTexture)
		emblem:SetAllPoints(crest)
		if shell.gameCorner then
			-- (the game's portrait: round, its circle mask)
			local mask = crest:CreateMaskTexture()
			mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(emblem)
			emblem:AddMaskTexture(mask)
		end
		shell.crest, shell.plainEmblem = crest, emblem
		shell.bounds[#shell.bounds + 1] = crest
	end

	-- the plate and the title on it; plain: a palette box
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
		-- (the game's look: the title alone on the bar, no box)
		MelloUI.Look.Hide(fill)
		for i = 1, #shell.plateEdges do
			MelloUI.Look.Hide(shell.plateEdges[i])
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

	-- the kit's dressing: now, or at the first switch on
	shell:Kit(DressFrame, shell)
	if ring then
		shell:Kit(DressRing, shell)
	end
	if opts.plate then
		shell:Kit(DressPlate, shell)
	end
	if not shell.kit then
		shell:BuildPlain()
	end
	return shell
end

--------------------------------------------------------------------------------
-- Kit:ChoicePicture: a look choice's picture (0.15.0; the Dynamic UI picker's
-- previews, moved here with its window gone): what the choice looks like
-- where it goes, on a small tile -- a picture row's box and its flyout's
-- tiles (W.PictureRow / W.PictureMenu, Core/Widgets.lua). The kinds, as the
-- choices' owners name them (Kit.borderKinds' `preview`, a panel's
-- PickerGroups section `kind`):
--   rim    the rim round a spell icon on the stone, as on the bar (a choice
--          with no rim piece: the icon on the stone, its plain edge)
--   bar    a progress bar in that bracket, a sample fill two thirds along
--   frame  the border piece round the stone (a rail family: a small
--          nine-slice of it); none: the stone darkened, "None"
--   tile   a swatch of the background; Dark: the palette's inner panel;
--          none: "None"
--   Kit:ChoicePicture(tile, kind, choice)
--     tile    the caller's: tile.pic (the picture's square frame), tile.none
--             (a FontString reading "None"), tile.layers (a table, its
--             slots filled here, LAYER_* below), tile.size (the picture's
--             side; TILE when nil)
--     choice  nil: the tile shows nothing
-- A tile's parts are made once and kept: drawn again with another choice (a
-- pooled tile, a row's box after a pick) it makes nothing but a bar strip or
-- a rail family's nine-slice the first time one is shown on it.
--------------------------------------------------------------------------------

local TILE = 52            -- a picture's side when the tile names none (the flyout's tiles)
local NONE_DIM = 0.45      -- the "None" frame's stone, darkened to this much of its light
local SAMPLE_ICON = "Interface\\Icons\\INV_Sword_04"

-- A tile's textures by what they wear. A texture that once wore a kit piece
-- stays the kit's (Dark Mode's brightness follows its every tint), so the
-- slots that wear kit pieces never wear anything else, and what is not the
-- kit's -- the sample icon, the bar's gold fill, the Dark swatch -- has a
-- slot of its own that never wears a piece.
local LAYER_BACK = 1       -- the stone, or a background's swatch (kit pieces)
local LAYER_PIECE = 2      -- a frame's border piece
local LAYER_RIM = 3        -- a rim's piece
local LAYER_OWN = 4        -- the icon, the fill or the Dark swatch (never a kit piece)

-- the tile's texture `i` over the whole picture (made the first time, kept;
-- what it wore for another choice let go -- a palette fill, a kit piece --
-- so a new palette or Kit Colours leaves what it wears now)
local function Layer(tile, i, level)
	local t = tile.layers[i]
	if not t then
		t = tile.pic:CreateTexture(nil, "ARTWORK", nil, level or 0)
		tile.layers[i] = t
	else
		Kit:Unpaint(t)
		if pieceNameOf[t] then
			Kit:Apply(t, nil)
		end
	end
	t:SetDrawLayer("ARTWORK", level or 0)
	t:ClearAllPoints()
	t:SetAllPoints(tile.pic)
	t:SetTexCoord(0, 1, 0, 1)
	t:SetVertexColor(1, 1, 1, 1)
	t:Show()
	return t
end

-- the stone a rim, a bar or a frame lies on
local function Stone(tile)
	local back = Layer(tile, LAYER_BACK, 0)
	back.kitScale, back.kitOwnScale = Kit.scale, true
	Kit:Apply(back, "tiles/stone")
	Kit:Retile(back)
	return back
end

-- the icon a rim is shown round: the first action button's, as on the bar
-- (a secret answer, or none: a sample sword)
local function SampleIcon()
	local icon = GetActionTexture and GetActionTexture(1)
	if Secret(icon) then
		return SAMPLE_ICON
	end
	return icon or SAMPLE_ICON
end

-- a rail family's small nine-slice on the tile, one per family made and kept
-- (a pooled tile shows other families after)
local function Nine(tile, choice, size)
	local nines = rawget(tile, "melloNines")   -- (fields of our own, never a method)
	if not nines then
		nines = {}
		rawset(tile, "melloNines", nines)
	end
	local key = choice.prefix .. (choice.gem and "|gem|" or "|") .. tostring(choice.scale or 1)
	local skin = nines[key]
	if not skin then
		skin = Kit:NineSlice(tile.pic, { prefix = choice.prefix, scale = Kit.scale * (choice.scale or 1) * 0.5 * size / TILE,
			gems = false, body = false, corners = choice.gem and "gem" or nil })
		nines[key] = skin
	end
	skin:Show()
end

function Kit:ChoicePicture(tile, kind, choice)
	local pic = tile.pic
	if not tile.layers then
		tile.layers = {}
	end
	local layers = tile.layers
	for i = LAYER_BACK, LAYER_OWN do
		local t = layers[i]   -- (a slot is made when first worn: they may have gaps)
		if t then
			t:Hide()
		end
	end
	local nines = rawget(tile, "melloNines")
	if nines then
		for _, skin in pairs(nines) do
			skin:Hide()
		end
	end
	local strip = rawget(tile, "melloStrip")
	if strip then
		strip:Hide()
	end
	tile.none:Hide()
	if self.BorderPictureOff then
		self:BorderPictureOff(tile)   -- (a border of the library's, drawn by the choice shown before)
		self:BorderBarPictureOff(tile)
	end
	if not choice then
		return
	end
	local size = tonumber(tile.size) or TILE
	if kind == "rim" and choice.style and self.BorderPicture then
		-- (0.19.8) a style of the border library's (Modules/KitBorders.lua):
		-- drawn by it round the sample icon, at a button's weight
		Stone(tile)
		local icon = Layer(tile, LAYER_OWN, 1)
		icon:SetTexture(SampleIcon())
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		self:BorderPicture(tile, choice, icon)
	elseif kind == "rim" then
		-- the rim round a spell icon on stone, as on the bar
		Stone(tile)
		local icon = Layer(tile, LAYER_OWN, 1)
		icon:SetTexture(SampleIcon())
		local p = choice.piece and self:Piece(choice.piece)
		if p and p.open then
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", pic, "TOPLEFT", size * p.open[1] / p.w, -size * p.open[2] / p.h)
			icon:SetPoint("BOTTOMRIGHT", pic, "BOTTOMRIGHT", -size * (p.w - p.open[3]) / p.w, size * (p.h - p.open[4]) / p.h)
		elseif not choice.piece then
			-- no rim of the kit's (the auras' plain edge): the stone's edge
			-- round the icon
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", pic, "TOPLEFT", 2, -2)
			icon:SetPoint("BOTTOMRIGHT", pic, "BOTTOMRIGHT", -2, 2)
		end
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		if choice.piece then
			self:Apply(Layer(tile, LAYER_RIM, 2), choice.piece)
		end
	elseif kind == "bar" and choice.style and self.BorderBarPicture then
		-- (0.19.8) a style of the border library's round a sample fill
		Stone(tile)
		local fill = Layer(tile, LAYER_OWN, 1)
		self:Paint(fill, "selectedTrim", "fill", 1)
		self:BorderBarPicture(tile, choice, fill, size)
	elseif kind == "bar" and self.Strip then
		-- a progress bar in that bracket: a fill two thirds along, on stone
		Stone(tile)
		local base = "bars/" .. (choice.bar or "frame")
		if not strip then
			strip = self:Strip(pic, base, { scale = self.scale, layer = "ARTWORK", sublevel = 2 })
			rawset(tile, "melloStrip", strip)
		elseif strip.SetBase then
			strip:SetBase(base)
		end
		local yoff = strip:FitBox(size * 0.36)
		strip:ClearAllPoints()
		strip:SetPoint("LEFT", pic, "LEFT", 2, yoff)
		strip:SetPoint("RIGHT", pic, "RIGHT", -2, yoff)
		strip:SetHeight(strip.height)
		strip:FitCaps(size - 4)
		strip:Show()
		-- (the fill in the palette's gold: a sample, not a bar's meaning)
		local fill = Layer(tile, LAYER_OWN, 1)
		fill:ClearAllPoints()
		fill:SetPoint("LEFT", pic, "LEFT", 4, 0)
		fill:SetSize((size - 8) * 0.66, size * 0.36 * 0.5)
		self:Paint(fill, "selectedTrim", "fill", 1)
	elseif kind == "frame" and choice.style and self.BorderPicture then
		-- (0.19.8) a style of the border library's round the stone (its studs on)
		Stone(tile)
		self:BorderPicture(tile, choice, nil)
	elseif kind == "frame" then
		-- the border piece itself: its corner gems and rim round the stone
		local back = Stone(tile)
		if choice.prefix and self.NineSlice then
			-- a rail family (the minimap's square borders): a small nine-slice
			-- of it round the stone, as it is laid on the real frame
			Nine(tile, choice, size)
		elseif choice.piece then
			self:Apply(Layer(tile, LAYER_PIECE, 2), choice.piece)
		else
			-- no border: the stone darkened (a dim of the art's light, as the
			-- kit's `dim`; the recoloured stone keeps its palette's hue)
			back:SetVertexColor(NONE_DIM, NONE_DIM, NONE_DIM)
			tile.none:Show()
		end
	else
		-- a swatch of the background
		if choice.piece then
			local back = Layer(tile, LAYER_BACK, 0)
			back.kitScale, back.kitOwnScale = self.scale * 0.5, true   -- a swatch: more of the tile than the UI's resolution would show
			self:Apply(back, choice.piece)
			self:Retile(back)
		elseif choice.value == "dark" then
			-- the Dark background: the palette's inner panel
			self:Paint(Layer(tile, LAYER_OWN, 0), "innerPanel", "fill", 0.88)
		else
			tile.none:Show()
		end
	end
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
-- calm ground (0.15.0) -- a UIParent child at DIALOG strata, the question on
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
	body:SetPoint("TOPLEFT", f, "TOPLEFT", CONFIRM_EDGE, CONFIRM_TOP)
	body:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CONFIRM_EDGE, CONFIRM_TOP)
	body:SetHeight(CONFIRM_BODY)
	local text = W.Text(body, "GameFontHighlight", nil, "text")
	text:SetJustifyH("CENTER")
	text:SetJustifyV("MIDDLE")
	text:SetWidth(CONFIRM_W - 2 * (CONFIRM_EDGE + CONFIRM_PAD))
	text:SetPoint("CENTER", body, "CENTER", 0, 0)
	-- accept on the left, cancel on the right (as the game's dialogs); the
	-- accept one the main action
	local accept = W.Button(f, "", CONFIRM_BUTTON_W, shell, { height = CONFIRM_BUTTON_H, onClick = Accept_OnClick, gold = true })
	accept:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -CONFIRM_GAP / 2, CONFIRM_BUTTON_Y)
	local cancel = W.Button(f, "", CONFIRM_BUTTON_W, shell, { height = CONFIRM_BUTTON_H, onClick = Cancel_OnClick })
	cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", CONFIRM_GAP / 2, CONFIRM_BUTTON_Y)
	confirm.frame, confirm.shell, confirm.body, confirm.text = f, shell, body, text
	confirm.accept, confirm.cancel = accept, cancel
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
	local h = Num(confirm.text:GetStringHeight()) or 0
	local body = math.max(CONFIRM_BODY, h + 2 * CONFIRM_PAD)
	confirm.body:SetHeight(body)
	f:SetHeight(-CONFIRM_TOP + body + CONFIRM_FOOT)
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
