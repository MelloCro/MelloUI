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
--                            disc, never an empty ring (2b)
--     plate = "crest" | "rail", title = "MelloUI", plateWidth = 200,
--                            "crest": the short plate under the crest
--                            (MelloUI-TitlePlate); "rail": the standard plate
--                            riding the outer rail (TitleBar, 2c)
--     close = true,          a close button on the top right corner
--     escape = true,         Escape closes it (UISpecialFrames: the frame
--                            must be named)
--     mover = { key, anchor, default, save, reset, min, max, base, plainDrag },
--                            MelloUI:RegisterMover(frame, shell.grab, ...)
--                            with the crest kept on the screen with it; no
--                            default: centred
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
-- shell.rail (the outer rail's rep), shell.mover (Core's entry),
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
-- The switch: the plain look is the window's own regions, which the kit's
-- replacements fade while they are enabled; switched off, every recorded rep
-- is disabled and they come back. Colours are palette keys (Kit:Paint), so a
-- new palette paints them again. Sounds only through MelloUI:PlayUISound.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Kit window")
local Shared = Perf.Shared
local Kit = MelloUI.Kit
local Num = MelloUI.Safe.Number
local W = MelloUI.Widgets   -- (Core/Widgets.lua loads before this file)

local TEXTURE_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\"
local LOGO = TEXTURE_PATH .. "LogoIcon.tga"                    -- the round emblem of the logo
local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"      -- the plain look's page (the kit's stone stands in for it)
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local PLAIN_CREST = 88       -- the emblem alone on the top edge, without the kit
local PLAIN_CORNER = 62      -- ... in the corner: a game window's portrait
local CORNER_X, CORNER_Y = 26, -24   -- a game window's portrait centre from its top left (PortraitFrameTemplate: 62 px at -5, 7)
local PLATE_FIT = 20         -- the plate's fit height (a game window's title container); its painted part 1.5 x that
local PLATE_OVERLAP = 8      -- the short plate reaches this far up over the crest's bottom (the approved sketch)
local GRAB_BOTTOM = -40      -- the drag strip's bottom edge when none is given
local FIT_MARGIN = 16        -- a window scaled to fit leaves this much of the screen free
-- frame levels over the window's own
local LEVEL_GRAB, LEVEL_CREST, LEVEL_PLATE, LEVEL_CLOSE = 1, 4, 7, 8

local EDGE_THIN = { edgeFile = WHITE, edgeSize = 1 }
local EDGE_WIDE = { edgeFile = WHITE, edgeSize = 2 }

local shells = setmetatable({}, { __mode = "k" })   -- [frame] = its shell
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
		else
			size = self.kit and self.ringSize or PLAIN_CORNER
			x, y, point = CORNER_X, CORNER_Y, "TOPLEFT"
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
		local nine = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
		nine:SetAllPoints(frame)
		framed = pcall(NineSliceUtil.ApplyLayoutByName, nine, "GenericMetal")
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
	local line = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	line:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -7)
	line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -7, 7)
	line:SetBackdrop(EDGE_THIN)
	Kit:Paint(line, "trim", "border")
	line:EnableMouse(false)
	self:Plain(line)
end

-- the look switched (the shell's own state, then its listeners)
function Shell:Switch(on)
	self.kit = on
	self:Lay()
	local reps = self.reps
	if on then
		for i = 1, #reps do
			reps[i]:Enable()
		end
		for _, entry in ipairs(self.skin.followers) do
			entry.rep:SetShown(entry.region:IsShown())
		end
		self:RunQueue()
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

-- on every show: the look as Kit:IsOn answers now (a switch made while it
-- was hidden), the fit, the sound (`opened`: a real open, not the UI shown
-- again around the open window)
function Shell:Showing(opened)
	local want = Kit:IsOn(self.area) and true or false
	if want ~= self.kit then
		self:Switch(want)
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

function Shell:SetEscape(on)
	on = on and true or false
	self.escape = on
	local name = self.frame:GetName()
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

--------------------------------------------------------------------------------
-- The kit's dressing (through shell:Kit: now, or at the first switch on)
--------------------------------------------------------------------------------

-- the page stone for the plain look's rock, the outer double rail (its
-- lit rail joins the window's mover: its shell registration)
local function DressFrame(K, shell)
	local frame = shell.frame
	shell:Replace(shell.bg, { as = "UI-Background-Rock", parent = frame, rect = frame, inset = K:OuterRailInset(), alsoFade = { shell.tint } })
	-- The rail's registration builds the window's one mover in UI
	-- Modifications (its lit rail). Core's entry and its handle go with it,
	-- as a registered window's mover is made there, so that mover is Core's
	-- whether it comes now or later: no put-back of its own, the drag strip
	-- its handle. Taken off again after it, so a plate or ring registered
	-- later is a handle as on any kit window.
	local entry = shell.mover
	local known
	if entry then
		known = K.shells[frame] or {}
		known.entry, known.title = entry, known.title or entry.handle
		K.shells[frame] = known
	end
	-- (body = false: the page stone above is the window's one background)
	local ok, rail = pcall(shell.Replace, shell, shell:Anchor(frame, "BORDER"), { as = "NineSlicePanelTemplate", parent = frame, rect = frame,
		body = false, skip = shell.ringAt == "tl" and "tl" or nil })
	if known then
		known.entry = nil
		if known.title == entry.handle then
			known.title = nil
		end
	end
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
	local rep = shell:Replace(shell.plainEmblem, { as = shell.ringAt == "top" and "MelloUI-Crest" or "UI-Frame-PortraitMetal-CornerTopLeft",
		rect = shell.crest })
	if not rep then
		return
	end
	shell.ring = rep
	local holder = rep.object
	local disc = K:RingDisc(rep, "innerPanel", holder, 6)
	local emblem = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	emblem.kitPiece = true
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

local function DressClose(K, shell)
	local close = shell.close
	local normal = close and close.GetNormalTexture and close:GetNormalTexture()
	if normal then
		shell:Replace(normal, { as = "RedButton-Exit", button = close, alsoFade = K:OtherTextures(close, normal) })
	end
end

--------------------------------------------------------------------------------
-- Kit:OwnWindow
--------------------------------------------------------------------------------

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
	}, Shell)
	shell.skin = { reps = shell.reps, followers = {} }
	shell.replace = function(region, ropts)
		return shell:Replace(region, ropts)
	end
	shells[frame] = shell
	local base = frame:GetFrameLevel()

	-- the plain look's page: the rock, tinted (the kit's stone stands in for both)
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
	bg:SetTexture(ROCK, "REPEAT", "REPEAT")
	bg:SetHorizTile(true)
	bg:SetVertTile(true)
	bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
	bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
	self:Paint(bg, "border", "vertex")
	local tint = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	tint:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
	tint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
	self:Paint(tint, "mainWindow", "fill", 0.45)
	shell.bg, shell.tint = bg, tint

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
		shell.ringSize = (self:Size("window/portrait_ring")) * (ring.scale or 1)
		shell.emblemTexture = ring.texture or LOGO
		local crest = CreateFrame("Frame", nil, frame)
		crest:SetFrameLevel(base + LEVEL_CREST)
		crest:EnableMouse(false)
		local emblem = crest:CreateTexture(nil, "ARTWORK")
		emblem:SetTexture(shell.emblemTexture)
		emblem:SetAllPoints(crest)
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
		local title = plate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("CENTER", plate, "CENTER", 0, 0)
		title:SetWordWrap(false)
		title:SetText(opts.title or "")
		self:Paint(title, "selectedTrim", "text")
		shell.plate, shell.title = plate, title
	end
	shell:Lay()

	if opts.close then
		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 0)
		close:SetFrameLevel(base + LEVEL_CLOSE)
		Perf.SetScript(close, "OnClick", Close_OnClick)
		shell.close = close
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

	-- the mover before the kit's dressing: the rail's registration with the
	-- kit (DressFrame) carries Core's entry, whichever look comes first
	local mover = opts.mover
	if mover then
		shell.mover = MelloUI:RegisterMover(frame, grab, {
			key = mover.key, anchor = mover.anchor, default = mover.default or Centre, save = mover.save, reset = mover.reset,
			min = mover.min, max = mover.max, base = mover.base, plainDrag = mover.plainDrag, with = shell.bounds,
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
	if opts.close then
		shell:Kit(DressClose, shell)
	end
	if not shell.kit then
		shell:BuildPlain()
	end
	return shell
end
