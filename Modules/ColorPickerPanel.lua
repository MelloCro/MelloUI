--------------------------------------------------------------------------------
-- MelloUI - Colour Picker Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): The colour picker in the kit.
--
-- ColorPickerFrame is a popup: it is dressed as the Dialogs Kit dresses the
-- game's popups -- the single rail with its stone round it (a frame below
-- it) in place of its dialog border, which is faded; its header band
-- (DialogHeaderTemplate's diamond-metal band, or an older picker's header
-- picture) gives way to the kit's title plate, as tall as every window's,
-- with the title centred on it in the kit's title face (WINDOW-RULES 2c);
-- Okay / Cancel on the red plates with their labels in their own colours;
-- the hex box on the kit's edit plate (S1, its left cap the plain end: no
-- search glass on a box that searches nothing); the two swatches (the new
-- colour and the one it replaces) in the Button Border's thin rim; the
-- opacity control in the kit slider's look: a slider widget gets the kit's
-- trough and gem thumb (an upright one the scroll bar's trough), and the
-- selector's own value and opacity bars keep their gradients, only their
-- thumbs become the gem. The colour wheel and every gradient the selector
-- draws are never covered, faded or tinted.
--
-- The Dialogs' parchment option (Parchment: Dialogs) is followed: the sheet
-- on the stone and the picker's labels in dark ink while it is on, the
-- palette's inner panel on the stone while it is off (WINDOW-RULES 2e).
-- The picker's size, place and behaviour stay the game's; switching the
-- module off gives back the stock picker. Nothing is built before the picker
-- first shows (Sync). /colorpickerdump [frames | reps | regions].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("ColorPickerPanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("ColorPickerPanel", {
	title = "Colour Picker Kit",
	desc = "The colour picker in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local AREA = "dialog"            -- the Dialogs' parchment option (parchment_dialog)
local SURFACE = "colorpicker"    -- this module's QuestInk surface
local HEADER_PADDING = 64        -- DialogHeaderTemplate's headerTextPadding

local active = false
local hooked = false
local skin = nil                 -- { nine, sheet, dim, reps = {}, title, hex, swatches = {}, thumbs = {}, sliders = {}, buttons = {} }
local fadedArt = {}              -- the game's art faded with no piece on its own rect
local rims = {}                  -- the swatch rims' holders { melloRep } (Kit:RegisterButtonRim keeps them weakly)

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe and MelloUI.Safe.IsSecret or issecretvalue

local function Window()
	local f = _G.ColorPickerFrame
	if type(f) == "table" and f.GetChildren and f.CreateTexture then
		return f
	end
	return nil
end

local function Replace(region, opts)
	local rep = region and skin and Kit and Kit.Replace and Kit:Replace(region, opts)
	if rep then
		skin.reps[#skin.reps + 1] = rep
		if active then
			rep:Enable()
		end
	end
	return rep
end

-- a frame's name, secret-safe
local function NameOf(obj)
	if not obj then
		return nil
	end
	local ok, n = pcall(obj.GetName, obj)
	if ok and type(n) == "string" and not Secret(n) then
		return n
	end
	return nil
end

local function IsType(obj, kind)
	if type(obj) ~= "table" or not obj.GetObjectType then
		return false
	end
	local ok, t = pcall(obj.GetObjectType, obj)
	return ok and t == kind
end

-- the non-nil values given, as a list
local function List(...)
	local list = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if v then
			list[#list + 1] = v
		end
	end
	return list
end

-- every frame under `root` to `depth` (the root first)
local function Frames(root, depth, list)
	list = list or {}
	list[#list + 1] = root
	if depth > 0 then
		for _, child in ipairs({ root:GetChildren() }) do
			if not child.melloSkin then
				Frames(child, depth - 1, list)
			end
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- The picker's parts, by what they ARE: the colour selector (the frame
-- itself on an older picker, a ColorSelect inside it on this one), its
-- wheel / value / opacity textures and thumbs, the swatches, the hex box,
-- an opacity slider widget, the header, the buttons
--------------------------------------------------------------------------------
local function Selectors(f)
	local list = {}
	for _, frame in ipairs(Frames(f, 3)) do
		if IsType(frame, "ColorSelect") then
			list[#list + 1] = frame
		end
	end
	return list
end

-- a selector's textures: { wheel, wheelThumb, value, valueThumb, alpha, alphaThumb }
local SELECT_PARTS = {
	{ "wheel", "GetColorWheelTexture" }, { "wheelThumb", "GetColorWheelThumbTexture" },
	{ "value", "GetColorValueTexture" }, { "valueThumb", "GetColorValueThumbTexture" },
	{ "alpha", "GetColorAlphaTexture" }, { "alphaThumb", "GetColorAlphaThumbTexture" },
}

local function SelectorParts(cs)
	local parts = {}
	for _, entry in ipairs(SELECT_PARTS) do
		local fn = cs[entry[2]]
		if type(fn) == "function" then
			local ok, tex = pcall(fn, cs)
			if ok and type(tex) == "table" then
				parts[entry[1]] = tex
			end
		end
	end
	return parts
end

-- the swatches: the known keys and names, else any texture keyed or named
-- a swatch on the picker or its content
local function Swatches(f)
	local list, seen = {}, {}
	local function Add(tex)
		if IsType(tex, "Texture") and not seen[tex] then
			seen[tex] = true
			list[#list + 1] = tex
		end
	end
	local content = f.Content
	for _, holder in ipairs(List(f, content)) do
		Add(holder.ColorSwatchCurrent)
		Add(holder.ColorSwatchOriginal)
		Add(holder.ColorSwatch)
		for key, value in pairs(holder) do
			if type(key) == "string" and key:find("Swatch") then
				Add(value)
			end
		end
	end
	Add(_G.ColorSwatch)
	return list
end

-- what is never touched: every region of a selector (the wheel, the value
-- and opacity gradients and their thumbs -- two thumbs are stood in for
-- deliberately, below), the swatches, the opacity chequer behind them
local function Untouchable(f)
	local keep = {}
	for _, cs in ipairs(Selectors(f)) do
		keep[cs] = true
		-- (an older picker IS the selector: its own box art is among its
		-- regions, so only the selector's own textures are kept there)
		if cs ~= f then
			for _, region in ipairs({ cs:GetRegions() }) do
				keep[region] = true
			end
		end
		for _, tex in pairs(SelectorParts(cs)) do
			keep[tex] = true
		end
	end
	for _, tex in ipairs(Swatches(f)) do
		keep[tex] = true
	end
	local content = f.Content
	for _, holder in ipairs(List(f, content)) do
		if holder.AlphaBackground then
			keep[holder.AlphaBackground] = true
		end
	end
	return keep
end

local function HexBox(f)
	local content = f.Content
	local box = (content and content.HexBox) or f.HexBox
	if IsType(box, "EditBox") then
		return box
	end
	for _, frame in ipairs(Frames(f, 3)) do
		if IsType(frame, "EditBox") then
			return frame
		end
	end
end

local function OpacitySliders(f)
	local list = {}
	if IsType(_G.OpacitySliderFrame, "Slider") then
		list[1] = _G.OpacitySliderFrame
	end
	for _, frame in ipairs(Frames(f, 3)) do
		if IsType(frame, "Slider") and frame ~= list[1] then
			list[#list + 1] = frame
		end
	end
	return list
end

-- the header: DialogHeaderTemplate (Left / Center / Right band pieces, the
-- Text on it), else an older picker's header picture and its string
local function Header(f)
	local h = f.Header
	if h and h.Text then
		return { frame = h, text = h.Text, art = List(h.LeftBG, h.CenterBG, h.RightBG), anchor = h, padding = h.headerTextPadding }
	end
	local tex = _G.ColorPickerFrameHeader or f.ColorPickerFrameHeader
	local text = _G.ColorPickerFrameHeaderText
	if not text then
		local want = _G.COLOR_PICKER
		for _, region in ipairs({ f:GetRegions() }) do
			if IsType(region, "FontString") then
				local ok, t = pcall(region.GetText, region)
				if ok and type(t) == "string" and not Secret(t) and want and t == want then
					text = region
				end
			end
		end
	end
	if text then
		return { text = text, art = List(tex), anchor = tex or text }
	end
end

local function Buttons(f)
	local list, seen = {}, {}
	local function Add(b)
		if IsType(b, "Button") and not seen[b] then
			seen[b] = true
			list[#list + 1] = b
		end
	end
	local footer = f.Footer
	for _, holder in ipairs(List(f, footer)) do
		Add(holder.OkayButton)
		Add(holder.CancelButton)
	end
	Add(_G.ColorPickerOkayButton)
	Add(_G.ColorPickerCancelButton)
	-- any other text button of the picker's
	for _, frame in ipairs(Frames(f, 2)) do
		if IsType(frame, "Button") and not frame.Icon and (frame.Left or frame.Middle or frame.Center) and frame.GetFontString and frame:GetFontString() then
			Add(frame)
		end
	end
	return list
end

-- The game's box: its dialog border (a nine-slice, a backdrop's pieces), its
-- background, and the picker's own BACKGROUND / BORDER textures that are
-- none of the untouchable parts
local BACKDROP_KEYS = { "Center", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner" }

local function GameArt(f)
	local list, seen = {}, {}
	local keep = Untouchable(f)
	local function Add(obj)
		if obj and not seen[obj] and not keep[obj] and not obj.kitPiece and not obj.melloSkin then
			seen[obj] = true
			list[#list + 1] = obj
		end
	end
	for _, key in ipairs({ "Border", "NineSlice", "Bg", "BG", "DialogBG" }) do
		Add(f[key])
	end
	for _, key in ipairs(BACKDROP_KEYS) do
		if IsType(f[key], "Texture") then
			Add(f[key])
		end
	end
	for _, region in ipairs({ f:GetRegions() }) do
		if IsType(region, "Texture") then
			local okL, layer = pcall(region.GetDrawLayer, region)
			if okL and (layer == "BACKGROUND" or layer == "BORDER") then
				Add(region)
			end
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- The title plate (WINDOW-RULES 2c): the kit's title plate standing in for
-- the header band, centred on it, as tall as every window's plate (1.5 x the
-- 20 px title bar) and as wide as the title between the plate's two caps
-- (never narrower than the game's band); the title centred on the plate's
-- painted box in the title face (it follows the Font Style), put back on
-- disable. The plate is a frame just under the picker's own level (under
-- the header's text and an older picker's own string), over the rail.
--------------------------------------------------------------------------------
local function PlateHeight()
	local rule = Kit.Replacements and Kit.Replacements.TitleBar
	return 20 * (rule and rule.heightScale or 1.5)
end

local function FitTitle()
	local t = skin and skin.title
	if not (t and t.rep and t.band) then
		return
	end
	local strip = t.rep.strip
	local h = PlateHeight()
	local mid = strip and Kit:Piece(Kit:StripPieceName(strip.base, "mid", strip.state))
	local cap = strip and Kit:Piece(Kit:StripPieceName(strip.base, "cap_l", strip.state))
	local capW = 0
	if mid and mid.box and cap then
		capW = cap.w * h / (mid.box[4] - mid.box[2])
	end
	local okT, tw = pcall(t.text.GetStringWidth, t.text)
	if not okT or Secret(tw) or not tw then
		tw = 0
	end
	local w = tw + 2 * capW
	local okH, hw = false, nil
	if t.frame then
		okH, hw = pcall(t.frame.GetWidth, t.frame)
	end
	if okH and type(hw) == "number" and not Secret(hw) and hw > w then
		w = hw
	end
	t.band:SetSize(math.max(w, tw + (t.padding or HEADER_PADDING)), h)
	t.rep:Refit()
	local dy = 0
	if mid and mid.box then
		dy = (mid.h / 2 - (mid.box[2] + mid.box[4]) / 2) * (strip.scale or Kit.scale)
	end
	t.text:ClearAllPoints()
	t.text:SetPoint("CENTER", strip or t.band, "CENTER", 0, dy)
end

local function SkinTitle(f)
	local hd = Header(f)
	if not hd then
		return
	end
	local band = CreateFrame("Frame", nil, f)
	band:EnableMouse(false)
	band:SetPoint("CENTER", hd.anchor, "CENTER")
	band:SetSize(1, PlateHeight())
	local rep = Replace(band, { as = "ui-questtracker-primary-objective-header", parent = f, rect = band, level = -1, noFade = true, alsoFade = hd.art })
	if not rep then
		return
	end
	local text = hd.text
	local saved = {}
	for i = 1, text:GetNumPoints() do
		saved[i] = { text:GetPoint(i) }
	end
	skin.title = { rep = rep, band = band, text = text, frame = hd.frame, padding = hd.padding }
	rep.onEnable = function()
		Kit:TitleFont(text, true)
		FitTitle()
	end
	rep.onDisable = function()
		Kit:TitleFont(text, false)
		text:ClearAllPoints()
		for _, pt in ipairs(saved) do
			text:SetPoint(unpack(pt))
		end
	end
end

--------------------------------------------------------------------------------
-- The buttons (the Dialogs Kit's way): red plates, labels in their own
-- colours (melloNoInk; a label inked already given its colour back), the
-- button's disabled look kept by the plate
--------------------------------------------------------------------------------
local function SkinButton(button)
	if skin.buttons[button] ~= nil then
		return
	end
	skin.buttons[button] = false
	button.melloNoInk = true
	local QI = MelloUI.QuestInk
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "FontString" and region.melloInk and QI and QI.PlainText then
			pcall(QI.PlainText, region)
		end
	end
	local ok, rep = pcall(Kit.SkinRedButton, Kit, button, Replace)
	skin.buttons[button] = (ok and rep) and true or false
end

--------------------------------------------------------------------------------
-- The hex box on the edit plate (S1) with the plain end in place of the
-- glass cap, focused while typing (InputBoxTemplate's Left / Middle /
-- Right, or whatever textures an older box has)
--------------------------------------------------------------------------------
local function SkinHexBox(box)
	if not box then
		return
	end
	local mid = box.Middle or box.Mid
	local others = {}
	for _, region in ipairs({ box:GetRegions() }) do
		if IsType(region, "Texture") and not region.kitPiece then
			if not mid then
				mid = region
			elseif region ~= mid then
				others[#others + 1] = region
			end
		end
	end
	if mid then
		skin.hex = Replace(mid, { as = "common-search-border-middle", rect = box, edit = box, dropCap = "l", alsoFade = others })
	end
end

--------------------------------------------------------------------------------
-- The swatches in the Button Border's thin rim (the look every window's
-- square buttons wear; a new Button Border swaps it): the rim on the
-- swatch's own rect, on a holder over the swatch's frame, its look held at
-- rest (a swatch is no button: no hover, no press). Nothing is laid over
-- the colour but the rim's own thin edge.
--------------------------------------------------------------------------------
local function SkinSwatch(tex)
	local owner = tex:GetParent()
	if not owner then
		return
	end
	local host = CreateFrame("Frame", nil, owner)
	host:EnableMouse(false)
	host:SetAllPoints(tex)
	local rep = Replace(tex, { as = Kit:ButtonRimRule(), button = host, parent = host, rect = tex, noFade = true })
	if not rep then
		return
	end
	if rep.object then
		rep.object.restState = "normal"
		if rep.object.Update then
			rep.object:Update()
		end
	end
	local holder = { melloRep = rep }
	rims[#rims + 1] = holder
	Kit:RegisterButtonRim(holder)
	skin.swatches[#skin.swatches + 1] = { tex = tex, rep = rep }
end

--------------------------------------------------------------------------------
-- The opacity control in the kit slider's look (SL1):
--  * a slider widget (an older picker's OpacitySliderFrame): its own art
--    (backdrop pieces, track) faded, the kit's trough on its rect -- the
--    scroll bar's upright trough for an upright slider, the slider track
--    for a level one -- and the gem thumb on its thumb;
--  * the selector's value and opacity bars: their gradients are colour and
--    stay; their thumbs become the gem thumb at its size, on a holder over
--    the selector, following the game's thumb wherever the game puts it.
--------------------------------------------------------------------------------
local function SkinSlider(slider)
	local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
	local art = {}
	for _, region in ipairs({ slider:GetRegions() }) do
		if IsType(region, "Texture") and region ~= thumb and not region.kitPiece then
			art[#art + 1] = region
		end
	end
	for _, child in ipairs({ slider:GetChildren() }) do
		if child.layoutType or child.TopLeftCorner then
			art[#art + 1] = child   -- a nine-slice / backdrop child
		end
	end
	local okO, orient = pcall(slider.GetOrientation, slider)
	local upright = okO and orient == "VERTICAL"
	local track
	if upright then
		track = Replace(slider, { as = "minimal-scrollbar-track-middle", parent = slider, rect = slider, noFade = true, alsoFade = art })
	else
		local p = Kit:Piece("inputs/slider_mid")
		local fit = (p and p.box) and (p.box[4] - p.box[2]) * Kit.scale or nil
		track = Replace(slider, { as = "_Minimal_SliderBar_Middle", parent = slider, rect = slider, noFade = true, alsoFade = art, fitHeight = fit })
	end
	local gem = thumb and Replace(thumb, { as = "Minimal_SliderBar_Button", button = slider, rect = thumb })
	skin.sliders[#skin.sliders + 1] = { slider = slider, track = track, gem = gem, upright = upright }
end

local function SkinThumbs(cs)
	local parts = SelectorParts(cs)
	local host
	for _, key in ipairs({ "valueThumb", "alphaThumb" }) do
		local thumb = parts[key]
		if thumb then
			if not host then
				host = CreateFrame("Frame", nil, cs)
				host:EnableMouse(false)
				host:SetAllPoints(cs)
			end
			local rep = Replace(thumb, { as = "Minimal_SliderBar_Button", button = host, rect = thumb })
			if rep then
				if rep.object then
					rep.object.restState = "normal"
					if rep.object.Update then
						rep.object:Update()
					end
				end
				skin.thumbs[#skin.thumbs + 1] = { key = key, thumb = thumb, rep = rep, selector = cs }
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Building, the ink, switching on and off
--------------------------------------------------------------------------------
local function Build()
	local f = Window()
	if skin or not (f and Kit and Kit.NineSlice) then
		return skin
	end
	-- two levels below the picker: the title plate goes between (under the
	-- picker's own strings, over the rail)
	local ok, nine = pcall(Kit.NineSlice, Kit, f, { prefix = "window/single", scale = Kit.scale * (Kit.frameScale or 1.6),
		gems = false, body = true, level = -2 })
	if not (ok and nine) then
		return nil
	end
	local alive = function() return active end
	skin = { nine = nine, reps = {}, swatches = {}, thumbs = {}, sliders = {}, buttons = {} }
	skin.sheet = Kit.ParchmentSheet and Kit:ParchmentSheet(nine, nine, { area = AREA, fine = true, margin = 2, alive = alive })
	skin.dim = Kit.StoneDim and Kit:StoneDim(nine, { area = AREA, alive = alive })
	nine:SetShown(active)
	pcall(SkinTitle, f)
	for _, b in ipairs(Buttons(f)) do
		pcall(SkinButton, b)
	end
	pcall(SkinHexBox, HexBox(f))
	for _, tex in ipairs(Swatches(f)) do
		pcall(SkinSwatch, tex)
	end
	for _, slider in ipairs(OpacitySliders(f)) do
		pcall(SkinSlider, slider)
	end
	for _, cs in ipairs(Selectors(f)) do
		pcall(SkinThumbs, cs)
	end
	-- whatever other common control the picker has (a scroll bar, a check
	-- box): its fixed look; the selector is never walked into
	local selectors = Selectors(f)
	pcall(Kit.SweepControls, Kit, f, Replace, nine, selectors[1])
	for _, obj in ipairs(GameArt(f)) do
		fadedArt[#fadedArt + 1] = obj
	end
	return skin
end

-- the ink (the parchment rule): the picker's labels on the sheet in dark ink
-- while the Dialogs' parchment is on; the title on its plate, the buttons'
-- labels, the hex on its plate keep their colours; the selector is never
-- walked into
local function InkOn()
	return active and Kit.ParchmentOn and Kit:ParchmentOn(AREA) or false
end

local surfaceMade = false
local function Surface()
	local QI = MelloUI.QuestInk
	if not QI then
		return
	end
	if surfaceMade then
		QI.RefreshSurface(SURFACE)
		return
	end
	surfaceMade = true
	local function Skip(fs)
		local p = fs.GetParent and fs:GetParent()
		for _ = 1, 3 do
			if not p then
				break
			end
			if p.melloNoInk or IsType(p, "Button") or IsType(p, "EditBox") or (IsType(p, "ColorSelect") and p ~= Window()) then
				return true
			end
			p = p.GetParent and p:GetParent()
		end
		if skin and skin.title and fs == skin.title.text then
			return true
		end
		return QI.DefaultSkip(fs)
	end
	QI.Surface(SURFACE, { on = InkOn, sheet = true, skip = Skip, roots = function() return Window() end })
end

-- the Dialogs' parchment switched: the picker's strings follow
if Kit and Kit.SetParchment then
	hooksecurefunc(Kit, "SetParchment", function(_, area)
		if area == AREA and surfaceMade and MelloUI.QuestInk then
			MelloUI.QuestInk.RefreshSurface(SURFACE)
		end
	end)
end

-- after every show: the title plate fitted to the title, the ink
local function Refresh()
	if not (active and skin) then
		return
	end
	FitTitle()
	if surfaceMade and MelloUI.QuestInk then
		MelloUI.QuestInk.RefreshSurface(SURFACE)
	end
end

local function Activate()
	if active or not Window() then
		return
	end
	Build()
	if not skin then
		return
	end
	active = true
	skin.nine:Show()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for _, obj in ipairs(fadedArt) do
		Kit:Fade(obj)
	end
	if Kit.SetParchment then
		Kit:SetParchment(AREA, Kit:ParchmentOn(AREA))
	end
	Surface()
	Refresh()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	if skin then
		skin.nine:Hide()
		for _, rep in ipairs(skin.reps) do
			rep:Disable()
		end
	end
	for _, obj in ipairs(fadedArt) do
		Kit:Unfade(obj)
	end
	if surfaceMade and MelloUI.QuestInk then
		MelloUI.QuestInk.RefreshSurface(SURFACE)
	end
end

-- (user, 2026-09-24: "dress rarely used windows on first open") nothing of the
-- look is built while the picker has never been shown: its OnShow (Hook
-- below) builds it before its first frame is drawn, or it is built at once
-- when it is open now. Once built it stays for the session, switched on and
-- off as before.
local function Sync()
	local f = Window()
	if M.isEnabled and f and (skin or f:IsShown()) then
		Activate()
	else
		Deactivate()
	end
end

-- (the switch and a late picker: out of combat only, as they always were)
local function SyncSafe()
	if Kit and Kit.WhenOutOfCombat then
		Kit:WhenOutOfCombat(Sync)
	else
		Sync()
	end
end

local function Hook()
	local f = Window()
	if hooked or not f then
		return
	end
	hooked = true
	Perf.HookScript(f, "OnShow", function()
		if M.isEnabled and not active then
			-- the first open, dressed here and now, in combat too: the dress
			-- adds frames and textures of ours, fades the game's box and puts
			-- the header's own title on the plate -- the picker has no secure
			-- or protected part, and nothing protected is called. Activate
			-- fades, inks and fits it all.
			Sync()
		elseif active then
			-- the game's own border and header may be laid again on show: faded again
			for _, obj in ipairs(fadedArt) do
				Kit:Fade(obj)
			end
			Refresh()
		end
		C_Timer.After(0, Refresh)
	end)
end

-- a picker made by an addon the game loads later: hooked once it exists
local watcher = CreateFrame("Frame")
Perf.SetScript(watcher, "OnEvent", function()
	if not hooked and Window() and M.isEnabled then
		Hook()
		SyncSafe()
	end
end)
pcall(watcher.RegisterEvent, watcher, "ADDON_LOADED")

function M:OnEnable(db)
	self.db = db
	if Window() then
		Hook()
		SyncSafe()
	end
end

function M:OnDisable()
	SyncSafe()
end

--------------------------------------------------------------------------------
-- /colorpickerdump [frames | reps | regions]: with no mode, every part found
-- (or not) and what it was dressed as -- the selector's textures (never
-- touched) and thumbs against the gems, the swatches' rims, the hex plate,
-- the slider, the title against its plate and its face, the buttons, the
-- inked strings, the picker's and its content's own regions and children;
-- the modes are Kit:DumpWindow's. Opens the copy window.
--------------------------------------------------------------------------------
local function Label(obj)
	if not obj then
		return "nil"
	end
	local n = NameOf(obj)
	if n then
		return n
	end
	local ok, d = pcall(obj.GetDebugName, obj)
	if ok and type(d) == "string" and not Secret(d) then
		return d
	end
	return "[unnamed]"
end

local function Found(label, obj, more)
	MelloUI:Print("  %-26s %s%s", label, obj and Label(obj) or "-- not found", more or "")
end

local function Shown(obj)
	local ok, s = pcall(obj.IsShown, obj)
	return (ok and not Secret(s)) and tostring(s) or "?"
end

local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.0f", v) or "?"
end

local function Rect(obj)
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if ok and l and not Secret(l) then
		return string.format("x=%s y=%s w=%s h=%s", Num(l), Num(b), Num(w), Num(h))
	end
	return "(no rect)"
end

local function Centre(obj)
	local ok, x, y = pcall(obj.GetCenter, obj)
	if ok and x and not Secret(x) then
		return Num(x) .. "," .. Num(y)
	end
	return "?"
end

local function Alpha(obj)
	local ok, a = pcall(obj.GetAlpha, obj)
	return (ok and not Secret(a) and a) and string.format("%.2f", a) or "?"
end

local function TextOf(fs)
	local ok, t = pcall(fs.GetText, fs)
	if ok and type(t) == "string" and not Secret(t) then
		return (t:gsub("\n", " | ")):sub(1, 50)
	end
	return "?"
end

local function FontOf(fs)
	local ok, face, size = pcall(fs.GetFont, fs)
	if ok and type(face) == "string" and not Secret(face) then
		return (face:match("([^\\/]+)$") or face) .. " " .. Num(size)
	end
	return "?"
end

local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "") .. (Kit.faded[region] and " FADED" or "")
		elseif kind == "FontString" then
			art = "text: " .. TextOf(region) .. (region.melloInk and " (inked)" or "")
		end
		MelloUI:Print("    region %s %s %s %s alpha %s shown %s", kind, Label(region), okL and tostring(layer) or "?", art, Alpha(region), Shown(region))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local okLv, lv = pcall(child.GetFrameLevel, child)
		MelloUI:Print("    child %s %s level %s shown %s%s%s", tostring(child:GetObjectType()), Label(child),
			okLv and Num(lv) or "?", Shown(child), child.layoutType and (" layout " .. tostring(child.layoutType)) or "",
			(Kit.faded[child] and " FADED") or (child.melloSkin and " (kit skin)") or "")
	end
end

local function DumpParts(f)
	local okLv, lv = pcall(f.GetFrameLevel, f)
	MelloUI:Print("ColorPickerFrame (%s): shown %s, %s, level %s, strata %s; kit %s, parchment %s", tostring(f:GetObjectType()), Shown(f), Rect(f),
		okLv and Num(lv) or "?", tostring(f:GetFrameStrata()), active and "on" or "off", tostring(Kit.ParchmentOn and Kit:ParchmentOn(AREA)))
	if not skin then
		MelloUI:Print("  not dressed yet: the colour picker is dressed the first time it opens")
	end
	Found("kit rail + stone", skin and skin.nine, skin and string.format(" shown %s, sheet shown %s, inner panel shown %s", Shown(skin.nine),
		skin.sheet and Shown(skin.sheet) or "-", skin.dim and Shown(skin.dim) or "-") or " (not built)")
	for _, key in ipairs({ "Border", "NineSlice", "Bg", "Content", "Footer", "Header" }) do
		local part = f[key]
		Found("game " .. key, part, part and (" " .. (Kit.faded[part] and "faded" or "not faded")) or nil)
	end
	MelloUI:Print("  game art faded: %d", #fadedArt)
	-- the title against its plate
	local t = skin and skin.title
	local hd = Header(f)
	if hd then
		Found("title", hd.text, string.format(" \"%s\" font %s, title face %s, centre %s, plate centre %s, plate %s",
			TextOf(hd.text), FontOf(hd.text), tostring(hd.text.melloFontSaved ~= nil), Centre(hd.text),
			t and t.rep.strip and Centre(t.rep.strip) or "-", t and t.rep.strip and Rect(t.rep.strip) or "-"))
		for _, piece in ipairs(hd.art) do
			Found("  header art", piece, " " .. (Kit.faded[piece] and "faded" or "not faded"))
		end
	else
		Found("title", nil)
	end
	-- the selector: every texture it draws, untouched
	local selectors = Selectors(f)
	if #selectors == 0 then
		Found("colour selector", nil)
	end
	for _, cs in ipairs(selectors) do
		Found("colour selector", cs, " " .. Rect(cs))
		local parts = SelectorParts(cs)
		for _, entry in ipairs(SELECT_PARTS) do
			local tex = parts[entry[1]]
			Found("  " .. entry[1], tex, tex and string.format(" %s, alpha %s, shown %s%s", Rect(tex), Alpha(tex), Shown(tex),
				Kit.faded[tex] and " (faded: a gem stands in)" or "") or nil)
		end
	end
	for _, entry in ipairs(skin and skin.thumbs or {}) do
		Found("gem on " .. entry.key, entry.rep.object, string.format(" centre %s vs thumb %s, shown %s", Centre(entry.rep.object), Centre(entry.thumb),
			Shown(entry.rep.object)))
	end
	-- the swatches, the hex box, the sliders, the buttons
	local swatches = Swatches(f)
	if #swatches == 0 then
		Found("swatch", nil)
	end
	for _, tex in ipairs(swatches) do
		local rim
		for _, s in ipairs(skin and skin.swatches or {}) do
			if s.tex == tex then
				rim = s.rep
			end
		end
		local okC, r, g, b = pcall(tex.GetVertexColor, tex)
		Found("swatch", tex, string.format(" %s, colour %s, alpha %s, rim %s%s", Rect(tex),
			(okC and not Secret(r)) and string.format("%.2f/%.2f/%.2f", r or 0, g or 0, b or 0) or "?", Alpha(tex), tostring(rim ~= nil),
			rim and rim.object and (" (" .. tostring(rim.object.base) .. ", " .. Rect(rim.object) .. ")") or ""))
	end
	local box = HexBox(f)
	Found("hex box", box, box and string.format(" %s, plate %s%s", Rect(box), tostring(skin and skin.hex ~= nil),
		(skin and skin.hex and skin.hex.strip) and (" " .. Rect(skin.hex.strip) .. ", left end " .. tostring(skin.hex.strip.endL)) or "") or nil)
	local sliders = OpacitySliders(f)
	if #sliders == 0 then
		Found("opacity slider widget", nil, " (the selector's opacity bar is the control; its thumb is the gem)")
	end
	for _, slider in ipairs(sliders) do
		local entry
		for _, s in ipairs(skin and skin.sliders or {}) do
			if s.slider == slider then
				entry = s
			end
		end
		Found("opacity slider", slider, string.format(" %s, trough %s, gem %s%s", Rect(slider), tostring(entry and entry.track ~= nil),
			tostring(entry and entry.gem ~= nil), entry and (entry.upright and " (upright)" or " (level)") or ""))
	end
	for _, b in ipairs(Buttons(f)) do
		local fs = b.GetFontString and b:GetFontString()
		Found("button", b, string.format(" \"%s\" red plate %s, label kept %s, shown %s", fs and TextOf(fs) or "",
			tostring(skin and skin.buttons[b]), tostring(b.melloNoInk == true), Shown(b)))
	end
	local QI = MelloUI.QuestInk
	local def = QI and QI.surfaces and QI.surfaces[SURFACE]
	local n = 0
	MelloUI:Print("inked strings (parchment ink %s):", tostring(InkOn()))
	for fs in pairs(def and def.strings or {}) do
		n = n + 1
		MelloUI:Print("  %s \"%s\"", Label(fs), TextOf(fs))
	end
	MelloUI:Print("  %d inked", n)
	MelloUI:Print("ColorPickerFrame's own regions and children:")
	DumpOwn(f)
	if f.Content then
		MelloUI:Print("its Content's regions and children:")
		DumpOwn(f.Content)
	end
end

SLASH_MELLOCOLORPICKERDUMP1 = "/colorpickerdump"
SlashCmdList.MELLOCOLORPICKERDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if not f then
		MelloUI:Print("/colorpickerdump: no ColorPickerFrame on this client")
	elseif msg == "" then
		DumpParts(f)
	else
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	end
	MelloUI:ShowLog("colorpickerdump " .. msg)
end
