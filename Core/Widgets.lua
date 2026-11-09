--------------------------------------------------------------------------------
-- MelloUI - Widgets
--
-- One widget set for the windows MelloUI makes itself (audit item 11, the
-- configurator build of 2026-09-25): the configurator first, the installer
-- next. Lifted from the configurator's own helpers, taking get / set instead
-- of a module's settings, so any window's data can sit behind them.
--
--   W.Paint(region, key, how, alpha)   a palette colour by its KEY (below)
--   W.Repaint()
--   W.Text(parent, font, text, key)    a FontString, left and top justified
--   W.Solid(parent, layer, key, alpha) a flat texture in a palette colour
--   W.Box(parent, bg, border, alpha)   a backdrop box, its fill and 1 px edge
--   W.Edges(frame, key, layer)         four 1 px lines round a frame, by key
--   W.Panel(parent, opts)              THE content panel of the own windows
--                                      (0.15.0): a flat inner panel in a 1 px
--                                      edge, in both looks
--   W.Header(parent, y, text, opts)    a section's heading: a gold title and
--                                      a hairline (0.15.0)
--   W.ShowTooltip(owner, title, body, line, anchor)   W.TipLeave (a shared OnLeave)
--   W.Switch(parent, get, set, opts)   a flat check box (0.15.0)
--   W.Dropdown(parent, width, get, set, values, opts)   dd:SetValues(values)
--                                      a flat box and MelloUI's own list
--                                      (0.15.0: never the game's menu; a
--                                      long list capped and scrolled)
--   W.Slider(parent, width, get, set, opts)   a thin track, a round knob and
--                                      a box to type the value in (0.15.0)
--   W.NumberBox(parent, width, get, set, opts)   a number to type, in the
--                                      slider box's look (0.15.0)
--   W.ColorWheel(parent, size, get, set)   a colour of the player's own on a
--                                      wheel and a brightness bar (0.20.0)
--   W.CanvasRow(parent, y, height, build, opts)   a row that is one frame a
--                                      module builds (0.20.0)
--   W.CanvasHeight(canvas, height)     that row's new height: what it holds
--                                      grew or shrank (2.1.13)
--   W.OrderList(parent, width, spec)   rows put in order by dragging them,
--                                      ticks, lines and groups (0.20.4)
--   W.OrderListHeight(rows)            the height of an order list of so many
--                                      rows (2.1.13)
--   W.Caret(tex, size, dir, lit)       the kit's gold caret (a fold arrow)
--   W.PlusMark(tex, size, lit)         the kit's gold plus glyph
--   W.ColourRow(parent, y, label, hint, desc, get, set, opts)   a colour
--                                      setting: a swatch, the wheel in a
--                                      flyout (0.20.0; W.ColourValue / Hex)
--   W.Button(parent, text, width, skin, opts)   a flat plate (0.15.0), and
--     W.FlatButton(button, gold): the same look on a button made by hand
--   W.CloseButton(parent, skin)        a flat plate with a cross (0.15.0)
--   W.FlatTab(tab, skin)               a page's tab made by hand: its label
--                                      alone, a gold line under the selected
--                                      one (1.2.4); W.TabFit(tab, pad) sizes it
--   W.FlatField(box)                   a text field or search box made by
--                                      hand, flat (0.15.0; W.FlatSearch)
--   W.IconBox(parent, size, texture, skin)
--   W.HoverLight(b, shape, region, out)   a button's mouseover light in its
--                                      border's shape: round or square (0.18.4)
--   W.RoundIcon(parent, size, texture, opts)   a round icon button in a rim
--                                      (the kit's round rim, or the minimap's)
--   W.Glyph(tex, name)                 a widget glyph (pause, list, friend, ...)
--                                      from the one glyph sheet (0.16.0)
--   W.GlyphButton(parent, size, glyph, opts)   a round button with a glyph
--                                      on a dark disc (0.16.0)
--   W.TrayBox(parent, opts)            a small list's box beside a window (the
--                                      kit's list box, or a plain fill and edge)
--   W.RowPlate(row, opts)              W.RowPlateOff(row), W.RowPlateChild(row, child)
--   W.Flash(row, hold)                 a row's hover look lit for a moment (a
--                                      jump's target: the configurator's search)
--   W.Tag(parent, text, snug)          ONE small gold word on a plate (a card's
--                                      "Recommended", an option's "New"), and
--     W.NewTag(parent, after, new, room), W.Badge(frame, new, inset),
--     W.ButtonTag(button, new): an option's New tag while its update runs
--     (MelloUI:IsNew); W.TagShown, W.TagAlpha
--   W.Row(parent, y, height, label, hint, desc, opts) and the typed rows
--     W.ToggleRow / SliderRow / DropdownRow / ButtonRow, W.Gate, W.ClipRow
--   W.PictureRow(parent, y, label, hint, desc, get, set, choices, kind, opts)
--                                      a look chosen by its picture (0.15.0),
--     its flyout W.PictureMenu(host, skin), one per window (a dropdown's
--     list opens in it too), W.ClosePictureMenu(host), W.CloseFlyouts()
--   W.Card(parent, spec, skin)         a choice card (the installer's picks;
--                                      spec.palette: a palette's card)
--   W.PaletteSwatch(parent, spec)      a palette shown by its colours, and
--     W.PaletteValues(), W.PaletteName(id), W.PaletteFill(tex, id, role):
--     the one palette picker's parts
--   W.Dress(root, skin, depth)         the kit's control sweep over a root
--   W.NavRail(parent, spec)            a side list / a steps rail (and a
--                                      search's results in its place)
--   W.Pager(parent, opts)              pages that cross-fade in one scroll
--   W.RevealInPager(region, margin)    a part of a Pager's page glided into view
--   W.PagerOf(region)                  the Pager holding a part of its page (2.1.13)
--   W.RowBudget                        ONE budget of rows a frame for every
--                                      own window: Begin(ms), End(), Spent(ms)
--
-- `skin` is the window's shell (Kit:OwnWindow, Modules/KitWindow.lua), or nil
-- for the plain palette look. A builder never reaches for MelloUI.Kit itself
-- for dressing: it asks skin:Kit(fn, ...) (fn(Kit, ...) now while the kit look
-- is on, else at its first switch on), hands skin.replace / skin.skin to the
-- kit's helpers, and takes the region to replace, where a widget has none,
-- from skin:Anchor(parent, layer) -- this file makes no invisible anchor and
-- holds no numeric colour. Colours go only through W.Paint (a picture of
-- ANOTHER palette -- W.PaletteFill: a swatch's chips -- reads that palette's
-- own colours from Core's registry, as a card's picture reads its file), sounds only
-- through MelloUI:PlayUISound, motion only through MelloUI.Anim (Reduce Motion
-- honoured by every helper). Kit and Fonts load after this file (the TOC):
-- nothing of theirs is bound here, everything is looked up when a builder
-- runs (the kit in one place, KitNow: a colour painted, a choice's picture
-- drawn). Nothing is made at load but the shared handlers and weak tables.
-- 0.15.0, the cleaner look the user picked (v150 configurator rebuild): the
-- own windows' panels, buttons, sliders and section headings are flat in
-- both looks (W.Panel, W.Button, W.Slider, W.Header) on the shell's calm
-- ground; the kit's list box, red plate, slider and header plate stay the
-- game windows'. Then "all flat" (user, 2026-09-29): the check boxes, the
-- dropdowns and their list, a page's tabs, the search box and the text
-- fields, and the close button too (W.Switch, W.Dropdown, W.FlatTab,
-- W.FlatField, W.CloseButton), the kit's active look (Kit:SetActive) still
-- marking a ticked box and the selected tab in the kit's look. Unchanged:
-- the row plate, W.Card, W.TrayBox.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Widgets")
local Shared = Perf.Shared
local C_Timer = Perf.C_Timer   -- (a flash's hold: W.Flash)
local Secret = MelloUI.Safe.IsSecret   -- (Core.lua's, one set for the addon)
local Num = MelloUI.Safe.Number

local W = {}
MelloUI.Widgets = W
-- (the languages, Core.lua's Languages section: every label, hint, tooltip, choice and heading a builder draws passes
-- through W.Tr -- the English as it is while no language table is in use; never a chat line, a name or a number. A
-- field, not a local: Widgets.lua's headroom. A world without Core.lua's: the text as it is)
W.Tr = MelloUI.Lang and MelloUI.Lang.T or function(text) return text end

local WHITE = "Interface\\Buttons\\WHITE8x8"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- a round icon's, a slider's knob
local TEXTURE_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\"
local ICON_MASK = "UI-HUD-ActionBar-IconFrame-Mask"    -- the icon boxes' rounded corners (the action button's)
local RIM_GROW = 1.1        -- the kit rim's rect: the icon box grown about its centre
local FADE_IN, FADE_OUT = 0.10, 0.12   -- a row's hover
local GATE_ALPHA = 0.4      -- a row that sleeps until a switch is on
local FLAT_OFF = 0.5        -- a disabled flat control: its fill and edge at this

-- the typed rows' heights (the configurator's ledger)
W.ROW_HEIGHT, W.SLIDER_ROW_HEIGHT = 34, 40

local weakKeys = { __mode = "k" }
local NO_OPTS = {}   -- (a builder called without options reads this empty table)

-- The window's one flyout (a picture row's tiles, a dropdown's list): filled
-- by W.PictureMenu's block, below; the dropdowns' box opens it from here
local Flyout = {}

--------------------------------------------------------------------------------
-- Paint ("Palette-ready", user 2026-09-25): every colour an
-- own window draws is a palette KEY, looked up when it is painted (never an
-- { r, g, b } held from load: a palette switch puts a new table in
-- MelloUI.Palette) and remembered per region, so the bus's 'palette' paints
-- them all again. ONE registry for the addon: MelloUI.Painter, the block
-- below (one look D1, out of Kit.lua; Kit:Paint / Kit:Unpaint /
-- Kit:PaletteKeyOf are its old names). W.Paint still hands a paint to the
-- kit's Kit:Paint while a kit is loaded (that routing goes when the kit is
-- the core's, stages E / I).
--   W.Paint(region, key, how, alpha)
--     how    "fill" (SetColorTexture, the default), "vertex" (SetVertexColor),
--            "text" (SetTextColor), "swipe" (a Cooldown's SetSwipeColor),
--            "backdrop" (SetBackdropColor), "border"
--            (SetBackdropBorderColor); a backdrop and its border are kept
--            apart, so one frame holds both
--     alpha  the colour's alpha (1)
--   W.Repaint()   the palette topic fired: every painted region from the
--                 palette as it is now (a palette change is a NEW table, so
--                 the same table repaints nothing: the kit's contract)
-- Without the kit (a world that never loaded Kit.lua) nothing is painted, as
-- before.
--------------------------------------------------------------------------------

-- The kit as it is now, looked up in this one place when a colour is painted
-- or a choice's picture drawn (Kit.lua loads after this file: nothing of it
-- is bound here)
local function KitNow()
	return MelloUI.Kit
end

-- An own control the kit's sweeps pass by (false: no plate of the kit's), or
-- its rep, kept in the kit's table beside it (MelloUI.Kept.repOf; hard rule 1 keeps
-- the game's frames free of keys, and the controls follow the same table).
-- Without the kit (a world that never loaded Kit.lua) there is no sweep
local function KitRep(control, rep)
	local Kept = MelloUI.Kept
	if KitNow() and Kept then
		Kept.repOf[control] = rep
	end
end

-- (the palette's registry, MelloUI.Painter: begin -- one look D1, out of
-- Modules/Kit.lua; self-contained, it reads only MelloUI and Secret)
-- Palette colours by key ("Palette-ready", user 2026-09-25: more palettes
-- are planned). Every region coloured from MelloUI.Palette -- the kit's
-- eye-strain panels (Kit:StoneDim), a frame rule's `dim` fill (the L1
-- boxes), a ring's disc given a palette key, the own-window shell's plain
-- parts (Kit:OwnWindow), the own windows' controls (W.Paint) -- is painted by
-- its KEY, looked up when painted, and kept in a weak list; the bus's
-- 'palette' paints them all again from the table MelloUI.Palette holds then.
--   MelloUI.Painter.Paint(region, key, how, alpha)
--     key    a MelloUI.Palette role ("innerPanel", "selectedTrim", ...)
--     how    "fill" (SetColorTexture, the default), "vertex"
--            (SetVertexColor), "text" (SetTextColor), "backdrop"
--            (SetBackdropColor), "border" (SetBackdropBorderColor) or
--            "swipe" (SetSwipeColor); a backdrop and its border are kept
--            apart, so one frame has both
--     alpha  the colour's alpha (1)
--   MelloUI.Painter.KeyOf(colour) -> the role a palette colour table is, or nil
--   MelloUI.Painter.Unpaint(region[, how])   the region out of the lists
--     again (a flat fill that gave way to a kit piece: a new palette leaves
--     the piece)
--   MelloUI.Painter.Colours() -> the palette as the look shows it now
-- 'palette' also goes out for a Kit Colours change (the topic's contract,
-- Core.lua: after both are in place; a new palette is always a NEW table):
-- while MelloUI.Palette is the table last painted from, nothing is painted.
-- The listener is taken on the first Paint, never at load; a Paint of a
-- region painted before reuses its entry (no garbage).
-- The colours are the palette as MelloUI.Look shows it (Look.Palette):
-- MelloUI.Palette whatever the reskin since the one look (Look:On is always
-- true); the 'look:own' repaint below is no longer told (stage E removes it
-- with the game's colours).
do
	local P = {}
	local weak = { __mode = "k" }
	local lists = {
		main = setmetatable({}, weak),       -- [region] = { key, how, alpha }: fill, vertex, text
		backdrop = setmetatable({}, weak),   -- [frame] = { key, how, alpha }
		border = setmetatable({}, weak),
	}
	local paintedFrom, listening = nil, false
	local paintedDim = 0   -- (1.2.4) Dark Mode's dim painted last (Look.DimStamp)

	-- the palette as the look shows it now (MelloUI.Look; without it, the palette); `text`: for text, never
	-- dimmed by Dark Mode (Look.Palette's own); (1.2.4, lk-11) `region`: the part painted, at its Dark Mode area's
	-- brightness (the area of the frame it hangs on)
	local function Colours(text, region)
		local Look = MelloUI.Look
		return type(Look) == "table" and type(Look.Palette) == "function" and Look.Palette(nil, text, region)
			or MelloUI.Palette
	end

	-- (1.2.4) a hairline (P.Hair) under the Default skin: the game's own line (MelloUI.Skin); back in a colour, its
	-- plain white ground again first
	local function Hair(region, how, alpha, e)
		local Skin = rawget(MelloUI, "Skin")
		if Skin and Skin.IsDefault() then
			Skin.LayHair(region, alpha)
			e.laid = true
			return true
		end
		if e.laid then
			e.laid = false
			if how == "vertex" then
				region:SetTexture(WHITE)
				region:SetTexCoord(0, 1, 0, 1)
			else
				region:SetVertexColor(1, 1, 1, 1)
			end
		end
		return false
	end

	local function Apply(region, key, how, alpha, e)
		local c = Colours(how == "text", region)[key]
		if not c then
			return
		end
		alpha = alpha or 1
		if e and e.hair and Hair(region, how, alpha, e) then
			return
		end
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
			-- (the configurator walk, 2026-11-04: every row lit after a skin switch) this client's SetVertexColor sets
			-- the texture's own alpha too: a repaint keeps it (a resting row wash, a faded edge stay out)
			local was = P.repainting and region:GetAlpha()
			region:SetVertexColor(c[1], c[2], c[3], alpha)
			if was and not Secret(was) then
				local now = region:GetAlpha()
				if not Secret(now) and now ~= was then
					region:SetAlpha(was)
				end
			end
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
		P.repainting = true   -- (Apply: the colours again, never the alpha)
		for _, list in pairs(lists) do
			for region, e in pairs(list) do
				Apply(region, e.key, e.how, e.alpha, e)
			end
		end
		P.repainting = false
	end

	local function OnPalette()
		local palette = MelloUI.Palette
		local Look = MelloUI.Look
		local stamp = type(Look) == "table" and Look.DimStamp and Look.DimStamp() or 0
		if palette == paintedFrom and stamp == paintedDim then
			return
		end
		paintedFrom, paintedDim = palette, stamp
		RepaintAll()
	end

	function P.Paint(region, key, how, alpha)
		if not (region and key) then
			return
		end
		how = how or "fill"
		local list = lists[how] or lists.main
		local e = list[region]
		if e then
			e.key, e.how, e.alpha = key, how, alpha
		else
			e = { key = key, how = how, alpha = alpha }
			list[region] = e
		end
		Apply(region, key, how, alpha, e)
		if not listening and MelloUI.On then
			listening = true
			paintedFrom = MelloUI.Palette
			MelloUI:On("palette", OnPalette, "Kit palette")
			MelloUI:On("look:own", RepaintAll, "Kit palette")   -- (the reskin switched: the game's colours or the palette)
		end
	end

	-- (1.2.4) a region painted (fill or vertex) that is a hairline: the game's own line under the Default skin
	function P.Hair(region)
		local e = region and lists.main[region]
		if e and not e.hair then
			e.hair = true
			Apply(region, e.key, e.how, e.alpha, e)
		end
	end

	-- a region that no longer shows a palette fill (a kit piece put on it
	-- again): out of the lists, so a new palette leaves it as it is
	function P.Unpaint(region, how)
		if region == nil then
			return
		end
		local list = lists[how or "fill"] or lists.main
		list[region] = nil
	end

	function P.KeyOf(colour)
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

	P.Colours = Colours
	MelloUI.Painter = P
end
-- (the palette's registry: end)

function W.Paint(region, key, how, alpha)
	local Kit = KitNow()
	if region and key and Kit and Kit.Paint then
		Kit:Paint(region, key, how or "fill", alpha)
	end
end

function W.Repaint()
	MelloUI:Fire("palette")
end

-- The fill texture of MelloUI's own bars (0.17.1, lifted from the race bar's
-- for the swing timers): the Bar Texture of a Bar Textures area (`area`, an
-- Apply To key; nil: "statusbars", the XP & Reputation bars', which the race
-- bar wears; the swing timers ask for "castbars", 0.19.4, the options audit),
-- else MelloUI's Minimalist. Read when a bar is (re)dressed;
-- W.OnBarTexture(area) tells when to dress it again.
local BAR_FILL = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Minimalist"
function W.BarFill(area)
	local bt = MelloUI:GetModule("BarTextures")
	local texture = bt and bt.PreviewTexture and bt.PreviewTexture(area or "statusbars")
	return type(texture) == "string" and texture or BAR_FILL
end

-- W.SoftEnds(bar[, off[, tex]]): a bar's soft ends (the user, 2026-10-16, of the party bars' look: "can you reflect
-- that change to every texture in the UI i really low the dimmed edges"; "make them share the same texture"): the
-- party bars' own mask on every bar -- the plain white mask clamped to black all round, over the bar's rect: its
-- edges dim to half over the last half texel (a 16th of the bar each way). One mask a bar, made once and kept (never
-- per call), put on its fill (the one texture a bar keeps through SetStatusBarTexture) or on `tex` (a cover of the
-- bar's fill); `off` takes it off again. The client takes three masks a texture, no more (the user's error,
-- 2026-10-16: "Texture already has the maximum number of mask textures (3)"): a fill wearing three already is
-- passed by. -> the mask worn (nil for none)
-- W.SoftMask(mask, over): a mask made that same one, over `over` (the party's sharp art dresses the game's own masks
-- so: no second mask, no slot taken).
-- W.SoftEndsOwn(tex, on): `tex` wears its own (a W.SoftMask): W.SoftEnds passes it by and takes its own off it.
do
	local MAX_MASKS = 3
	local WHITE8 = "Interface\\Buttons\\WHITE8X8"
	local soft = setmetatable({}, { __mode = "k" })   -- [bar] = its mask
	local wearing = setmetatable({}, { __mode = "k" })   -- [texture] = the mask it wears of its bar's
	local own = setmetatable({}, { __mode = "k" })   -- [texture] = true: dimmed by a W.SoftMask of its own

	function W.SoftMask(mask, over)
		mask:SetTexture(WHITE8, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:ClearAllPoints()
		mask:SetAllPoints(over)
		return mask
	end

	local function TakeOff(tex)
		local worn = wearing[tex]
		if worn then
			pcall(tex.RemoveMaskTexture, tex, worn)
			wearing[tex] = nil
		end
	end

	function W.SoftEndsOwn(tex, on)
		if type(tex) ~= "table" then
			return
		end
		if on then
			TakeOff(tex)
		end
		own[tex] = on and true or nil
	end

	function W.SoftEnds(bar, off, tex)
		if type(bar) ~= "table" or type(bar.CreateMaskTexture) ~= "function" then
			return nil
		end
		tex = tex or (type(bar.GetStatusBarTexture) == "function" and bar:GetStatusBarTexture()) or nil
		if not tex then
			return nil
		end
		if off then
			TakeOff(tex)
			return nil
		end
		local worn = wearing[tex]
		if worn or own[tex] or type(tex.AddMaskTexture) ~= "function" then
			return worn
		end
		local okN, n = pcall(tex.GetNumMaskTextures, tex)
		if not (okN and type(n) == "number") or n >= MAX_MASKS then
			return nil
		end
		local mask = soft[bar]
		if not mask then
			mask = W.SoftMask(bar:CreateMaskTexture(), bar)
			soft[bar] = mask
		end
		tex:AddMaskTexture(mask)
		wearing[tex] = mask
		return mask
	end
end

-- W.OnBarTexture(area, fn, owner): fn() once a Bar Textures fill for that
-- area may read differently: the shared Bar Texture or the area's own (one
-- look Q3: "<area>Texture"; an area of W.BarFill's; "tooltip", the tooltip's
-- health bar), or the module switched on or off (0.19.4, the options audit:
-- the race bar, the swing timers and the tooltip's bar kept the old fill
-- until a look change or a /reload). The bus's 'setting' and 'module', one
-- listener each per owner (MelloUI:On keeps one per owner), made when asked,
-- never per event.
function W.OnBarTexture(area, fn, owner)
	local own = tostring(area) .. "Texture"   -- (made once here, not per Fire)
	MelloUI:On("setting", function(module, key)
		if module == "BarTextures" and (key == "texture" or key == own) then
			fn()
		end
	end, owner)
	MelloUI:On("module", function(name)
		if name == "BarTextures" then
			fn()
		end
	end, owner)
end

--------------------------------------------------------------------------------
-- MelloUI's own font objects (2026-10-20, the user: one font for the modern look, "to fit this theme": Fredoka):
-- a copy of each game font object MelloUI's text names (MelloUIFont_GameFontNormal ...), its size, colour, shadow
-- and outline the game object's, its face MelloUI's: the Fonts module's interface face while it is on and chose one
-- (the game object wears it then: the copy copies it), else Fredoka. The Fonts module passes them by (its "^MelloUI"
-- rule); every 'fonts' Fire lays them again. Made at load (a dozen font objects, nothing drawn).
-- (the languages, docs/plans/languages.md) Each copy is a font FAMILY where the client makes them (CreateFontFamily):
-- Fredoka draws only Latin, so the other alphabets keep the game font's own members (its Cyrillic, Korean and
-- Chinese faces) -- the configurator in Russian, Chinese or Korean, and such names in MelloUI's windows, never boxes.
-- The game's members are read, never written. A client without families: one face, as before.
--   W.FontObject(name) -> the name of MelloUI's copy of the game font object `name` (`name` itself for one it has
--       no copy of): for CreateFontString's template and SetFontObject
--------------------------------------------------------------------------------
do
	local FACE = TEXTURE_PATH:gsub("Textures\\$", "") .. "Fonts\\Fredoka\\Fredoka-Medium.ttf"
	local NAMES = { "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall", "GameFontNormalSmall",
		"GameFontNormalLarge", "GameFontHighlightLarge", "GameFontNormalHuge", "GameFontDisable", "GameFontDisableSmall" }
	local ALPHABETS = { "roman", "korean", "simplifiedchinese", "traditionalchinese", "russian" }
	local own = {}      -- [game name] = MelloUI's copy's name
	local family = {}   -- [game name] = { [alphabet] = true }: a family's members (nil: a copy of one face)

	-- a font object's member for an alphabet (nil: none, or a client without families)
	local function Member(obj, alphabet)
		if type(obj) ~= "table" or type(obj.GetFontObjectForAlphabet) ~= "function" then
			return nil
		end
		local ok, m = pcall(obj.GetFontObjectForAlphabet, obj, alphabet)
		return ok and type(m) == "table" and m or nil
	end

	-- the face a member wears now: the chosen face (the game's own Latin member wears it) or Fredoka for Latin, the
	-- game member's own for the other alphabets
	local function Wear(copy, chosen)
		local ok, _, size, flags = pcall(copy.GetFont, copy)
		size = ok and Num(size)
		if not chosen and size and size > 0 then
			pcall(copy.SetFont, copy, FACE, size, ok and type(flags) == "string" and flags or "")
		end
	end

	local function Lay()
		local fonts = MelloUI.modules and MelloUI.modules.Fonts
		local db = fonts and fonts.isEnabled and fonts.db
		-- (1.2.4, the Default skin -- MelloUI.Skin: the game object's own face, as a face of the player's choosing)
		local Skin = rawget(MelloUI, "Skin")
		local chosen = type(db) == "table" and type(db.fontText) == "string" and db.fontText ~= "" and db.fontText ~= "default"
			or (Skin and Skin.IsDefault())
		for _, name in ipairs(NAMES) do
			local game, copy = _G[name], _G[own[name]]
			local members = family[name]
			if game and copy and members then
				-- (the family's own look: its alignment and spacing as the game font's, each member the game member's
				-- whole look copied, Latin then in the face)
				pcall(copy.SetJustifyH, copy, game:GetJustifyH())
				pcall(copy.SetJustifyV, copy, game:GetJustifyV())
				-- (1.2.4, lk-03: the family's own height the game font's Latin one first -- the Interface text size
				-- reaches the game's members; copied into ours alone they left our family, and every string wearing
				-- it, at the height it was made with. SetFontHeight is the client's own way to size a family, every
				-- alphabet's face kept: Blizzard's TextSizeManager. The members are copied after it)
				local latin, height = Member(game, "roman"), nil
				if latin then
					local okH, _, h = pcall(latin.GetFont, latin)
					height = okH and Num(h) or nil
				end
				if height and height > 0 and type(copy.SetFontHeight) == "function" then
					pcall(copy.SetFontHeight, copy, height)
				end
				for alphabet in pairs(members) do
					local mine, theirs = Member(copy, alphabet), Member(game, alphabet)
					if mine and theirs and mine ~= theirs then
						pcall(mine.CopyFontObject, mine, theirs)
						if alphabet == "roman" then
							Wear(mine, chosen)
						end
					end
				end
			elseif game and copy then
				pcall(copy.CopyFontObject, copy, game)
				Wear(copy, chosen)
			end
		end
	end

	-- a family of MelloUI's own from the game font's members (Fredoka for Latin); nil where the client has none
	local function Family(name, game)
		if type(CreateFontFamily) ~= "function" or not Member(game, "roman") then
			return nil
		end
		local list, members = {}, {}
		for _, alphabet in ipairs(ALPHABETS) do
			local m = Member(game, alphabet)
			local ok, path, size, flags = false, nil, nil, nil
			if m then
				ok, path, size, flags = pcall(m.GetFont, m)
			end
			path, size = ok and MelloUI.Safe.Text(path), ok and Num(size)
			if path and size and size > 0 then
				list[#list + 1] = { alphabet = alphabet, file = alphabet == "roman" and FACE or path, height = size,
					flags = type(flags) == "string" and flags or "" }
				members[alphabet] = true
			end
		end
		if #list < 2 then
			return nil
		end
		local ok, fam = pcall(CreateFontFamily, own[name], list)
		if not (ok and type(fam) == "table") then
			return nil
		end
		-- (named as CreateFont names one: a template by that name)
		if _G[own[name]] == nil then
			_G[own[name]] = fam
		end
		return members
	end

	if type(CreateFont) == "function" then
		for _, name in ipairs(NAMES) do
			local game = _G[name]
			if game then
				own[name] = "MelloUIFont_" .. name
				family[name] = Family(name, game)
				if not family[name] and not _G[own[name]] then
					CreateFont(own[name])
				end
			end
		end
		Lay()
		MelloUI:On("fonts", Lay, "the widgets' own fonts")
		MelloUI:On("skin", Lay, "the widgets' own fonts (skin)")
		MelloUI:On("module", function(name)
			if name == "Fonts" then
				Lay()
			end
		end, "the widgets' own fonts (Fonts module)")
	end

	function W.FontObject(name)
		return own[name] or name
	end

	-- (tests, /mello languages) whether the copy of `name` is a family, and its members
	function W.FontFamilyOf(name)
		return family[name]
	end
end

function W.Text(parent, font, text, key)
	local fs = parent:CreateFontString(nil, "OVERLAY", W.FontObject(font or "MelloUIFont_GameFontHighlight"))
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	if text then
		fs:SetText(text)
	end
	if key then
		W.Paint(fs, key, "text")
	end
	return fs
end

function W.Solid(parent, layer, key, alpha)
	local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
	tex:SetTexture(WHITE)
	W.Paint(tex, key, "vertex", alpha or 1)
	return tex
end

local BOX_BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

function W.Box(parent, bg, border, alpha)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetBackdrop(BOX_BACKDROP)
	W.Paint(f, bg, "backdrop", alpha or 1)
	W.Paint(f, border, "border", 1)
	return f
end

-- four 1 px lines round a frame, painted by key (a box's edge without a
-- backdrop: a region each, so the kit look can hide them): { top, bottom,
-- left, right }. The one copy: the own-window shell's plate uses it too.
-- `rect`: the region they lie round, when not the frame itself (a check
-- box's box, a tab's plate: regions of the frame); `alpha` theirs (1)
local function Edges(frame, key, layer, rect, alpha)
	local out = {}
	for i = 1, 4 do
		out[i] = frame:CreateTexture(nil, layer or "BORDER")
		W.Paint(out[i], key, "fill", alpha or 1)
	end
	rect = rect or frame
	out[1]:SetPoint("TOPLEFT", rect, "TOPLEFT", 0, 0)
	out[1]:SetPoint("BOTTOMRIGHT", rect, "TOPRIGHT", 0, -1)
	out[2]:SetPoint("TOPLEFT", rect, "BOTTOMLEFT", 0, 1)
	out[2]:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", 0, 0)
	out[3]:SetPoint("TOPLEFT", rect, "TOPLEFT", 0, 0)
	out[3]:SetPoint("BOTTOMRIGHT", rect, "BOTTOMLEFT", 1, 0)
	out[4]:SetPoint("TOPLEFT", rect, "TOPRIGHT", -1, 0)
	out[4]:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", 0, 0)
	return out
end
W.Edges = Edges

-- (1.2.0; the user's pick C of gilded_windows_sketch: "every inner line" of MelloUI's windows gold) THE hairline of
-- the windows' inner lines -- a panel's edge, a title's rule, a divider, the seam of two snapped windows: the
-- Personal Display's joint hairline, the palette's trim at HAIR_ALPHA. W.Hairline(region) paints a line in it
-- (painted again with the palette); W.HairEdges(frame[, layer[, rect]]) four of them round a frame (W.Edges')
-- (1.2.4) under the Default skin each is the game's own line (MelloUI.Painter's Hair: MelloUI.Skin);
-- W.HairSolid(parent[, layer]) a line of its own (W.Solid's), made a hairline
W.HAIR_KEY, W.HAIR_ALPHA = "trim", 0.55

do   -- (in a block: the main chunk is near Lua's 200 locals)
	local function Hair(region)
		local P = MelloUI.Painter
		if P and P.Hair then
			P.Hair(region)
		end
		return region
	end

	function W.Hairline(region)
		W.Paint(region, W.HAIR_KEY, "fill", W.HAIR_ALPHA)
		return Hair(region)
	end

	function W.HairSolid(parent, layer)
		return Hair(W.Solid(parent, layer, W.HAIR_KEY, W.HAIR_ALPHA))
	end

	function W.HairEdges(frame, layer, rect)
		local edges = Edges(frame, W.HAIR_KEY, layer or "BORDER", rect, W.HAIR_ALPHA)
		for i = 1, #edges do
			Hair(edges[i])
		end
		return edges
	end
end

--------------------------------------------------------------------------------
-- Panel (0.15.0, the cleaner look the user picked: Background A): THE
-- content panel of the own windows, in both looks -- a flat `innerPanel`
-- fill in a 1 px `border` edge (W.Box's look, as regions: no backdrop). It
-- stands where the kit's list box (L1, Professions-background-summarylist)
-- stood in them: the configurator's sections and side list, the installer's
-- body, the question dialog's text, a picture row's flyout. One surface, one
-- panel: it lies on the calm ground (Kit:OwnWindow's `calm`), never on
-- another panel. The kit's list box stays the game windows'.
--   W.Panel(parent, opts) -> panel   a Frame, sized and placed by the caller
--     opts: on (true: the look laid on `parent` itself, which is returned --
--           a section that is its own panel), alpha (the fill's, 1),
--           rim (1.2.0: a window of its own -- the Quest Tracker, the minimap
--           column, the chat, the whisper window: the gold rim round it,
--           MelloUI.Rims; a look area's name: none while the painted look
--           dresses that area)
--   (1.2.0) its edge the windows' gold hairline (W.HairEdges: the user's
--   pick C of gilded_windows_sketch, every inner line gold)
--   panel.panelFill, panel.panelEdges   (painted by key: a new palette
--                                       paints them again)
--------------------------------------------------------------------------------

-- the panel's regions on a frame: its fill under everything the frame
-- draws, its edge over the fill
local function PanelLook(frame, alpha)
	local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	fill:SetAllPoints(frame)
	W.Paint(fill, "innerPanel", "fill", alpha or 1)
	return fill, W.HairEdges(frame)
end

function W.Panel(parent, opts)
	opts = opts or NO_OPTS
	local panel = opts.on and parent or CreateFrame("Frame", nil, parent)
	local alpha = opts.alpha
	if type(alpha) ~= "number" or Secret(alpha) then
		alpha = 1
	end
	panel.panelFill, panel.panelEdges = PanelLook(panel, alpha)
	local Rims = opts.rim and rawget(MelloUI, "Rims")
	if type(Rims) == "table" and Rims.Add then
		Rims:Add(panel, { area = type(opts.rim) == "string" and opts.rim or nil })
	end
	return panel
end

--------------------------------------------------------------------------------
-- RoundPlate (1.2.4, Edit Layout's dock -- the user's pick A of
-- MelloUI-BuildData/output/editlayout_dock_sketch): a plate with round
-- corners in palette colours, drawn from the round mask (no art of its own):
-- a fill inside an edge. Its corners are quarters of the mask's disc, its
-- straight parts plain rects; one system for every round plate: the dock (its
-- bottom corners round, flush with the screen's top: no top edge), its round
-- buttons (a circle) and the pills under it.
--   W.RoundPlate(frame, spec) -> plate   on `frame`, sized by the caller once
--     (the corners keep spec.radius); spec: shape ("rounded" | "bottom":
--     only the bottom corners round, the top open | "pill": radius half the
--     height | "circle"), radius (6; a pill's and a circle's from the size),
--     fill ("innerPanel"), edge ("border"), edgeWidth (1), fillAlpha (1),
--     edgeAlpha (1), layer ("BACKGROUND"), sub (-7: the edge, the fill one up)
--   plate:Paint(fill, edge[, fillAlpha, edgeAlpha])   its colours by key
--------------------------------------------------------------------------------

do   -- (in a block: the main chunk is near Lua's 200 locals)
	local QUAD = {
		TOPLEFT = { 0, 0.5, 0, 0.5 }, TOPRIGHT = { 0.5, 1, 0, 0.5 },
		BOTTOMLEFT = { 0, 0.5, 0.5, 1 }, BOTTOMRIGHT = { 0.5, 1, 0.5, 1 },
	}
	local CENTRE = { TOPLEFT = "BOTTOMRIGHT", TOPRIGHT = "BOTTOMLEFT", BOTTOMLEFT = "TOPRIGHT", BOTTOMRIGHT = "TOPLEFT" }
	local SIGN = { TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 } }
	local ALL_CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
	local BOTTOM_CORNERS = { "BOTTOMLEFT", "BOTTOMRIGHT" }

	local function Rect(frame, layer, sub, list, p1, x1, y1, p2, x2, y2)
		local t = frame:CreateTexture(nil, layer, nil, sub)
		t:SetPoint("TOPLEFT", frame, p1, x1, y1)
		t:SetPoint("BOTTOMRIGHT", frame, p2, x2, y2)
		list[#list + 1] = t
	end

	-- one shape (the edge's, or the fill's inset by `i`): its discs and its rects
	local function Shape(frame, spec, r, i, sub)
		local layer = spec.layer or "BACKGROUND"
		local s = { discs = {}, rects = {} }
		if spec.shape == "circle" then
			local t = frame:CreateTexture(nil, layer, nil, sub)
			t:SetTexture(ROUND_MASK)
			t:SetPoint("TOPLEFT", frame, "TOPLEFT", i, -i)
			t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -i, i)
			s.discs[1] = t
			return s
		end
		local open = spec.shape == "bottom"
		for _, c in ipairs(open and BOTTOM_CORNERS or ALL_CORNERS) do
			local t = frame:CreateTexture(nil, layer, nil, sub)
			t:SetTexture(ROUND_MASK)
			local q = QUAD[c]
			t:SetTexCoord(q[1], q[2], q[3], q[4])
			t:SetSize(r - i, r - i)
			local sx, sy = SIGN[c][1], SIGN[c][2]
			t:SetPoint(CENTRE[c], frame, c, sx * r, sy * r)
			s.discs[#s.discs + 1] = t
		end
		if open then
			Rect(frame, layer, sub, s.rects, "TOPLEFT", i, 0, "BOTTOMRIGHT", -i, r)
			Rect(frame, layer, sub, s.rects, "BOTTOMLEFT", r, r, "BOTTOMRIGHT", -r, i)
		else
			Rect(frame, layer, sub, s.rects, "TOPLEFT", r, -i, "BOTTOMRIGHT", -r, i)
			if spec.shape ~= "pill" then
				Rect(frame, layer, sub, s.rects, "TOPLEFT", i, -r, "BOTTOMLEFT", r, r)
				Rect(frame, layer, sub, s.rects, "TOPRIGHT", -r, -r, "BOTTOMRIGHT", -i, r)
			end
		end
		return s
	end

	local function PaintShape(s, key, alpha)
		for _, t in ipairs(s.discs) do
			W.Paint(t, key, "vertex", alpha)
		end
		for _, t in ipairs(s.rects) do
			W.Paint(t, key, "fill", alpha)
		end
	end

	local function PlatePaint(plate, fill, edge, fillAlpha, edgeAlpha)
		PaintShape(plate.edgeShape, edge or plate.edgeKey, edgeAlpha or plate.edgeAlpha)
		PaintShape(plate.fillShape, fill or plate.fillKey, fillAlpha or plate.fillAlpha)
	end

	function W.RoundPlate(frame, spec)
		spec = type(spec) == "table" and spec or NO_OPTS
		local w, h = Num(frame:GetWidth()) or 0, Num(frame:GetHeight()) or 0
		local r = spec.radius or 6
		if spec.shape == "pill" then
			r = h / 2
		end
		-- (the in-game test, 2026-11-04: Edit Layout's View panel, its plate made before its size -- 0 wide, its
		-- corners 0, which the game draws at the mask's own size: big gold quarter discs) a frame not sized yet
		-- keeps the radius
		if w > 0 then
			r = math.min(r, w / 2)
		end
		local sub = spec.sub or -7
		local edgeW = spec.edgeWidth or 1
		local plate = {
			fillKey = spec.fill or "innerPanel", edgeKey = spec.edge or "border",
			fillAlpha = spec.fillAlpha or 1, edgeAlpha = spec.edgeAlpha or 1,
			Paint = PlatePaint,
		}
		plate.edgeShape = Shape(frame, spec, r, 0, sub)
		plate.fillShape = Shape(frame, spec, r, edgeW, sub + 1)
		plate:Paint()
		return plate
	end
end

--------------------------------------------------------------------------------
-- Header (0.15.0, Headers 1): a section's heading in the own windows -- its
-- title in gold (`selectedTrim`, GameFontNormal) and a 1 px `border`
-- hairline from 12 px past the title to 8 px short of the row's right edge,
-- on the title's middle. No plate, no gem caps, no hover, in both looks (the
-- kit's header plate, SH3, stays the game windows'): the configurator's
-- sections and subheadings, Home's cards, the installer's steps.
--   W.Header(parent, y, text, opts) -> header   a Frame W.HEADER_HEIGHT high,
--     `y` below the parent's top, as wide as the parent less opts.inset (0)
--     at both sides; opts.x: the title's left (8)
--   header.label, header.line
--------------------------------------------------------------------------------

do
	W.HEADER_HEIGHT = 28
	local HEADER_X, HEADER_GAP, HEADER_END = 8, 12, 8   -- the title's left, the title to its line, the line's end
	-- (2026-10-20, the user's pick 1: the diamond divider, MelloUI's icon set) the line is a gold line tapering to
	-- points with a diamond in its middle: piece_div_diamond (Tools/make_icons.py PIECES: 512 wide, its picture the
	-- top 26 of 32 rows), the diamond between u 0.4772 and 0.5228; the halves stretch, the diamond keeps its shape
	local DIV = TEXTURE_PATH .. "Icons\\piece_div_diamond"
	local DIV_V, DIV_L, DIV_R, DIV_H = 26 / 32, 0.4772, 0.5228, 10
	local DIV_W = DIV_H * (DIV_R - DIV_L) * 512 / 26

	local function Slice(h, l, r)
		local t = h:CreateTexture(nil, "ARTWORK")
		t:SetTexture(DIV)
		t:SetTexCoord(l, r, 0, DIV_V)
		t:SetHeight(DIV_H)
		return t
	end

	-- (1.2.4, the Default skin: MelloUI.Skin) the game's Settings divider in the diamond line's place, on its middle
	-- (its 630 px drawn shorter); made at its first need
	local function HeaderSkin(h, game)
		for i = 1, 3 do
			h.lineParts[i]:SetShown(not game)
		end
		if game and not h.gameLine then
			local g = h:CreateTexture(nil, "ARTWORK")
			g:SetAtlas(MelloUI.Skin.ART.divider)
			g:SetHeight(1)
			g:SetPoint("LEFT", h.line, "LEFT", 0, 0)
			g:SetPoint("RIGHT", h.line, "RIGHT", 0, 0)
			h.gameLine = g
		end
		if h.gameLine then
			h.gameLine:SetShown(game)
		end
	end

	function W.Header(parent, y, text, opts)
		opts = opts or NO_OPTS
		local inset = opts.inset or 0
		local h = CreateFrame("Frame", nil, parent)
		h:SetHeight(W.HEADER_HEIGHT)
		h:SetPoint("TOPLEFT", inset, -(y or 0))
		h:SetPoint("RIGHT", parent, "RIGHT", -inset, 0)
		h:EnableMouse(false)
		h.label = W.Text(h, "GameFontNormal", W.Tr(text), "selectedTrim")
		h.label:SetWordWrap(false)
		h.label:SetPoint("LEFT", h, "LEFT", opts.x or HEADER_X, 0)
		-- the line's span (an empty region), the diamond on its middle, a half each side of it
		h.line = h:CreateTexture(nil, "ARTWORK")
		h.line:SetHeight(DIV_H)
		h.line:SetPoint("LEFT", h.label, "RIGHT", HEADER_GAP, 0)
		h.line:SetPoint("RIGHT", h, "RIGHT", -HEADER_END, 0)
		local mid = Slice(h, DIV_L, DIV_R)
		mid:SetWidth(DIV_W)
		mid:SetPoint("CENTER", h.line, "CENTER", 0, 0)
		local left, right = Slice(h, 0, DIV_L), Slice(h, DIV_R, 1)
		left:SetPoint("LEFT", h.line, "LEFT", 0, 0)
		left:SetPoint("RIGHT", mid, "LEFT", 0, 0)
		right:SetPoint("LEFT", mid, "RIGHT", 0, 0)
		right:SetPoint("RIGHT", h.line, "RIGHT", 0, 0)
		h.lineParts = { left, mid, right }
		if rawget(MelloUI, "Skin") then
			MelloUI.Skin.Follow(h, HeaderSkin)
		end
		return h
	end
end

--------------------------------------------------------------------------------
-- W.RowBudget: ONE budget of rows a frame, whoever makes them -- the
-- configurator's pages (a click, the scroll hook, its worker) and the
-- installer's (review, 2026-09-25: each kept one of its own, and two of them
-- in one frame came to 6 ms). `at` is the frame (GetTime is the same all
-- through one), `ms` the rows it has made, `from` when the rows under way
-- began: none begin inside them.
--   W.RowBudget.Begin(ms) -> deadline | nil
--       up to `ms` of rows now, less those this frame has made: the
--       debugprofilestop time to stop at; nil when none are left or rows are
--       under way. End() counts them (call it whatever Begin returned).
--   W.RowBudget.End()
--   W.RowBudget.Spent(ms)
--       this frame's rows counted as at least `ms` (a page's first open whose
--       own parts are this frame's work: its rows start the next frame)
--------------------------------------------------------------------------------

do
	local spend = { at = false, ms = 0, from = false }
	local function ThisFrame()
		local now = GetTime()
		if spend.at ~= now then
			spend.at, spend.ms, spend.from = now, 0, false
			return true
		end
		return false
	end
	W.RowBudget = {
		Begin = function(ms)
			if not ThisFrame() and (spend.from or spend.ms >= ms) then
				return nil
			end
			local start = debugprofilestop()
			spend.from = start
			return start + ms - spend.ms
		end,
		End = function()
			if spend.from then
				spend.ms = spend.ms + debugprofilestop() - spend.from
				spend.from = false
			end
		end,
		Spent = function(ms)
			ThisFrame()
			if spend.ms < ms then
				spend.ms = ms
			end
		end,
	}
end

--------------------------------------------------------------------------------
-- Tooltips: the title in gold, the body in the text colour, both looked up
-- in the palette when shown. `line`, when given, goes between them (a hint
-- the row cut short). `anchor`: where it hangs ("ANCHOR_RIGHT" when nil; a
-- window's top bar wants "ANCHOR_BOTTOM").
--------------------------------------------------------------------------------

function W.ShowTooltip(owner, title, body, line, anchor)
	local P = MelloUI.Look.TipPalette()   -- (the palette's gold and text colour)
	local gold, text = P.selectedTrim, P.text
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	GameTooltip:SetText(W.Tr(title), gold[1], gold[2], gold[3])
	if line and line ~= "" then
		GameTooltip:AddLine(W.Tr(line), text[1], text[2], text[3], true)
	end
	if body and body ~= "" then
		GameTooltip:AddLine(W.Tr(body), text[1], text[2], text[3], true)
	end
	GameTooltip:Show()
end

-- The handlers every row and control shares (user, 2026-09-24: a page of two
-- hundred rows made a dozen functions per row): one function each, wrapped
-- once, reading what it shows from the frame it runs on
local TipLeave = Shared("OnLeave on MelloUI's rows and controls (tooltip)", function()
	GameTooltip:Hide()
end, "script")
W.TipLeave = TipLeave

local clipped = setmetatable({}, weakKeys)   -- [row] = true: its texts end at its control (W.ClipRow)

-- a row's tooltip: its label and description (`tipTitle`, `tipBody`), and a
-- hint the row cut short
local RowTipEnter = Shared("OnEnter on MelloUI's rows (tooltip)", function(self)
	local cut
	if clipped[self] then
		local hint = self.hint
		if hint and hint:IsShown() and hint.IsTruncated and hint:IsTruncated() then
			cut = hint:GetText()
		end
		local label = self.label
		if not (cut or self.tipBody or (label and label.IsTruncated and label:IsTruncated())) then
			return
		end
	end
	W.ShowTooltip(self, self.tipTitle, self.tipBody, cut)
end, "script")
-- a row's switch or button: the row's tooltip, on the row, when the option
-- has a description
local ControlTipEnter = Shared("OnEnter on MelloUI's row controls (tooltip)", function(self)
	if self.tipBody then
		W.ShowTooltip(self.tipOwner, self.tipTitle, self.tipBody)
	end
end, "script")

-- a row's control carries the row's tooltip
local function ControlTip(control, row, title, body)
	control.tipOwner, control.tipTitle, control.tipBody = row, title, body
	Perf.HookScript(control, "OnEnter", ControlTipEnter)
	Perf.HookScript(control, "OnLeave", TipLeave)
end

--------------------------------------------------------------------------------
-- The kit's dressing (run through skin:Kit: now, or at the kit look's first
-- switch on). Shared functions, handed the widget: no closure per widget.
--------------------------------------------------------------------------------

local function DressSweep(K, root, skin, depth)
	K:SweepControls(root, skin.replace, skin.skin, nil, depth)
end

-- The kit's control sweep over `root` (Kit:SweepControls: red plates, check
-- boxes, dropdowns, tabs, found by what they are): the one way a window's
-- controls the kit knows are dressed. `depth`: where the sweep starts (the
-- configurator's rows at 2, as a sweep of the page reaches them). The own
-- windows' controls are flat (0.15.0: their rep false in MelloUI.Kept.repOf, the sweep passes
-- them by); what a root holds of the game's own is dressed.
function W.Dress(root, skin, depth)
	if skin and root then
		skin:Kit(DressSweep, root, skin, depth)
	end
end

-- (0.15.0: the own windows' buttons, sliders, check boxes, dropdowns, tabs,
-- search box and close button are flat in both looks -- the kit's red
-- plate, B1, slider, SL1, check box, dropdown plate, D1, tab, TB6, search
-- box, S1, and red cross stay the game windows')

--------------------------------------------------------------------------------
-- The active look (Kit:SetActive, 0.15.0: the one look for whatever is
-- active or selected, the game's windows and MelloUI's own) on a widget: a
-- chosen card, an icon-less side list's marker, a ticked box, the selected
-- tab. It is the kit's art, so it shows only while the widget's window wears
-- the kit. The kit is the one the shell hands over (skin:Kit) the first time
-- a look shows, kept for the switches after: never reached for. `rect`: the
-- region the ring lies round (the widget), `shape`: the kit's ("rect": a
-- card, a tab; "square": a box).
--------------------------------------------------------------------------------

local activeKit = nil
local function ActiveNow(K, frame, on, rect, shape)
	activeKit = K
	K:SetActive(frame, on, rect or frame, shape or "rect")
end

local function WidgetActive(skin, frame, on, rect, shape)
	if not skin then
		return
	end
	if skin.kit then
		skin:Kit(ActiveNow, frame, on and true or false, rect, shape)
	elseif activeKit then
		activeKit:SetActive(frame, false)
	end
end

-- the flat widgets of each shell that wear the active look, laid again at
-- its switches (a ticked box, the selected tab): each answers
-- widget:melloActive() -> on, rect, shape, and widget:melloKitLook(), when
-- it has one, lays its own look again (a selected tab's gold edge gives way
-- to the ring in the kit's look)
local activeOf = setmetatable({}, weakKeys)   -- [shell] = { [widget] = true } (weak)
local function Actives_OnKit(shell)
	local set = activeOf[shell]
	if set then
		for widget in pairs(set) do
			if widget.melloKitLook then
				widget:melloKitLook()
			end
			WidgetActive(shell, widget, widget:melloActive())
		end
	end
end

local function FollowLook(skin, widget)
	if not (skin and skin.OnKit) then
		return
	end
	local set = activeOf[skin]
	if not set then
		set = setmetatable({}, weakKeys)
		activeOf[skin] = set
	end
	set[widget] = true
	skin:OnKit(Actives_OnKit)
end

--------------------------------------------------------------------------------
-- The flat controls' one set of handlers (0.15.0): the pointer on a control
-- and its state (enabled or not, shown) paint it again through its kind's
-- own look, control.melloLook(control, whole) (`whole`: its state changed,
-- every part painted; else only what the hover changes). The colours are
-- looked up when painted (a new palette paints them again).
--------------------------------------------------------------------------------

local flatHover = setmetatable({}, weakKeys)   -- [control] = true while the pointer is on it

local FlatEnter = Shared("OnEnter on MelloUI's flat controls", function(c)
	flatHover[c] = true
	c.melloLook(c)
end, "script")

local FlatLeave = Shared("OnLeave on MelloUI's flat controls", function(c)
	flatHover[c] = nil
	c.melloLook(c)
end, "script")

local FlatState = Shared("OnEnable / OnDisable / OnShow on MelloUI's flat controls", function(c)
	c.melloLook(c, true)
end, "script")

-- `shows`: its look laid again on every show too (a button's own fonts
-- change its label's colour while it is hidden)
local function FlatHooks(c, look, shows)
	c.melloLook = look
	Perf.HookScript(c, "OnEnter", FlatEnter)
	Perf.HookScript(c, "OnLeave", FlatLeave)
	Perf.HookScript(c, "OnEnable", FlatState)
	Perf.HookScript(c, "OnDisable", FlatState)
	if shows then
		Perf.HookScript(c, "OnShow", FlatState)
	end
	look(c, true)
end

--------------------------------------------------------------------------------
-- Kit controls (0.19.9; the user's picks 2026-10-08, "0A 1A 2B 3B",
-- docs/plans/newui2-glyphs-close-portrait.md): the NewUI2 plates are the one
-- control style. The close button, the check box, the arrows, the + / - and
-- the settings cog of the flat controls (W.FlatOver over the game's, W.Switch,
-- W.CloseButton, a dropdown's caret) are kit pieces (Tools/make_newui2_glyphs.py:
-- buttons/<kind>_<state>, window/close_<state>), recoloured per look as every
-- kit piece; and (the user's pick A, 2026-10-09) every icon button's plate
-- (the "button" kind: W.PlateButton, the plates under the game's glyphs) the
-- cog plate blank, buttons/iconplate_<state>. States: steel at rest, gold under the pointer, dim pressed (the
-- close: dark red); a + / - has no pressed one (its rest); disabled = the rest
-- piece at FLAT_OFF; a ticked box under the pointer = checkbox_onhover. Under
-- SMALL UI px an arrow or a + / - is its glyph alone (glyphs/<kind>_<state>,
-- no plate: a 13 px plate is a speckle). One texture per control on its
-- frame's middle: a plate's solid box at the frame's shorter side (but never
-- under MIN: a 14 px tick box or the quest log's 15 px settings button gets
-- the plate at about its natural size, centred over the rect, as the kit's
-- cog plate always stood -- K2), a glyph fitted into the frame at
-- GLYPH_FILL. Without the kit (a world that never loaded Kit.lua) nothing
-- is drawn.
--   KC.State(kind, hover, pressed, checked, disabled) -> the piece's state
--   KC.Lay(tex, w, h, kind, dir, state, alpha, glyph) -> true when drawn: the
--     piece on `tex` (re-applied only when it changed) for a w x h frame,
--     centred on tex.melloOn (its frame; tex.melloPoint / melloX: on that
--     point of it, so far right); `glyph` forces the glyph alone (a
--     dropdown's caret)
--------------------------------------------------------------------------------
local KC = { SMALL = 20, GLYPH_FILL = 0.9, MIN = { check = 18, cog = 19, button = 19 },
	STEM = { check = "checkbox", close = "close", cog = "cog", plus = "plus", minus = "minus", button = "iconplate" },
	GLYPHS = { arrow = true, plus = true, minus = true } }

-- (0.25.0; the user, 2026-10-19: "and the Configurator, checkboxes, sliders etc", the controls of MelloUI's icon set,
-- Media/Textures/Icons by Tools/make_icons.py) A control wears MelloUI's own icon while its part is not in
-- Oldschool's painted look (KC.Painted: an area that is always MelloUI's never is; the others as the kit answers --
-- the configurator's own 'config', the reskin's handshake), the NewUI2 plate with it: the check box empty or
-- ticked, Close the red cross, + / - the fold buttons, the cog the chat's Settings button, a dropdown's arrow and a
-- title bar's (turned by its direction). Under the pointer the icon full, at rest a step down, pressed a step more.
KC.ICON = { check = { off = "ctl_check_off", hover = "ctl_check_off", on = "ctl_check_on", onhover = "ctl_check_on" },
	close = "btn_decline", plus = "btn_expand", minus = "btn_collapse", cog = "chat_settings", arrow = "ctl_dropdown",
	titlearrow = "btn_arrow" }
KC.TURN = { arrow = { down = 0, up = math.pi, left = -math.pi / 2, right = math.pi / 2 },
	titlearrow = { up = 0, down = math.pi } }
KC.LIT = { hover = 1, onhover = 1, pressed = 0.72 }
KC.REST = 0.88

function KC.Painted(area)
	local Kit = KitNow()
	if not (type(Kit) == "table" and type(Kit.IsOn) == "function" and type(Kit.Areas) == "table") then
		return false
	end
	area = area or "config"
	local entry = Kit.Areas[area]
	if entry and entry.always then
		return false
	end
	return Kit:IsOn(area) and true or false
end

function KC.LayIcon(tex, w, h, kind, dir, state, alpha, glyph, icon)
	w, h = Num(w), Num(h)
	if not (w and h and w > 0 and h > 0) then
		return false
	end
	if type(icon) == "table" then
		icon = icon[state] or icon.off
	end
	tex:SetAlpha((alpha or 1) * (KC.LIT[state] or KC.REST))
	local name = icon .. (dir or "")
	if tex.melloPiece == name and tex.melloW == w and tex.melloH == h then
		return true
	end
	if tex.melloPiece ~= name then
		tex.melloPiece = name
		MelloUI.Icons.Set(tex, icon, w)   -- (fitted to its own size below)
		tex:SetVertexColor(1, 1, 1, 1)
		local turn = KC.TURN[kind]
		tex:SetRotation(turn and turn[dir or (kind == "arrow" and "down" or "up")] or 0)
		tex.melloTurned = true   -- (a painted plate laid after it turns it back)
	end
	tex.melloW, tex.melloH = w, h
	local s
	if kind == "arrow" or (glyph and KC.GLYPHS[kind] and kind ~= "plus" and kind ~= "minus") then
		s = math.min(w, h) * KC.GLYPH_FILL
	else
		s = math.max(math.min(w, h), KC.MIN[kind] or 0)
	end
	tex:SetSize(s, s)
	MelloUI.Icons.Fit(tex, s)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", tex.melloOn or tex:GetParent(), tex.melloPoint or "CENTER", tex.melloX or 0, 0)
	return true
end

function KC.State(kind, hover, pressed, checked, disabled)
	if kind == "check" then
		local lit = (hover or pressed) and not disabled
		return (checked and (lit and "onhover" or "on")) or (lit and "hover") or "off"
	end
	if disabled then
		return "normal"
	end
	if pressed and kind ~= "plus" and kind ~= "minus" then
		return "pressed"
	end
	return (hover or pressed) and "hover" or "normal"
end

-- (0.25.0) every control laid, by its texture (weak), with its last lay: when its area's look switches (bus
-- 'look:<area>': Oldschool's painted plate or the set's icon) each is laid again in the new look; the listener taken
-- at an area's first lay, never at login
KC.laid = setmetatable({}, { __mode = "k" })
do
	local listened = {}
	local function ReLayAll()
		for tex, a in pairs(KC.laid) do
			tex.melloPiece = nil   -- (the other look's art: laid anew)
			KC.Lay(tex, a[1], a[2], a[3], a[4], a[5], a[6], a[7])
		end
	end
	function KC.Remember(tex, w, h, kind, dir, state, alpha, glyph)
		local a = KC.laid[tex]
		if a then
			a[1], a[2], a[3], a[4], a[5], a[6], a[7] = w, h, kind, dir, state, alpha, glyph
		else
			KC.laid[tex] = { w, h, kind, dir, state, alpha, glyph }
		end
		local area = tex.melloArea or "config"
		if not listened[area] and MelloUI.On then
			listened[area] = true
			MelloUI:On("look:" .. area, ReLayAll, "the controls' look (" .. area .. ")")
		end
	end
end

function KC.Lay(tex, w, h, kind, dir, state, alpha, glyph)
	KC.Remember(tex, w, h, kind, dir, state, alpha, glyph)
	local icon = KC.ICON[kind]
	if icon and not KC.Painted(tex.melloArea) then
		return KC.LayIcon(tex, w, h, kind, dir, state, alpha, glyph, icon)
	end
	local Kit = KitNow()
	if not (Kit and Kit.Piece and Kit.Apply) then
		return false
	end
	w, h = Num(w), Num(h)
	if not (w and h and w > 0 and h > 0) then
		return false
	end
	-- (0.20.1: a frame within a hair of SMALL counts as SMALL -- the Legacy cards' 20 px +, pooled at fractional offsets,
	-- read 19.99 on some cards and 20 on others and wore the two looks side by side)
	glyph = KC.GLYPHS[kind] and (glyph or math.min(w, h) < KC.SMALL - 0.05) or false
	-- (0.20.1, the user's pick A: "titlearrow", a title bar's maximize / minimize on the close button's steel plate,
	-- Tools/make_title_arrows.py -- always its plate, as the close button)
	local stem = (kind == "arrow" and ("arrow_" .. (dir or "down"))) or (kind == "titlearrow" and ("titlearrow_" .. (dir or "up")))
		or KC.STEM[kind]
	local name = (glyph and "glyphs/" or ((kind == "close" or kind == "titlearrow") and "window/" or "buttons/")) .. stem .. "_" .. state
	local p = Kit:Piece(name)
	if not p then
		return false
	end
	tex:SetAlpha(alpha or 1)
	if tex.melloPiece == name and tex.melloW == w and tex.melloH == h then
		return true
	end
	if tex.melloPiece ~= name then
		tex.melloPiece = name
		if tex.melloTurned then
			tex:SetRotation(0)   -- (0.25.0: the set's icon turned it, KC.TURN)
			tex.melloTurned = nil
		end
		Kit:Apply(tex, name)
	end
	tex.melloW, tex.melloH = w, h
	local s, dx, dy
	if glyph then
		s, dx, dy = math.min(w / p.w, h / p.h) * KC.GLYPH_FILL, 0, 0
	else
		local b = p.box or { 0, 0, p.w, p.h }
		s = math.max(math.min(w, h), KC.MIN[kind] or 0) / math.max(b[3] - b[1], b[4] - b[2])
		dx, dy = (p.w - b[1] - b[3]) / 2 * s, (b[2] + b[4] - p.h) / 2 * s
	end
	tex:SetSize(p.w * s, p.h * s)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", tex.melloOn or tex:GetParent(), tex.melloPoint or "CENTER", dx + (tex.melloX or 0), dy)
	return true
end

--------------------------------------------------------------------------------
-- Switch (0.15.0, flat: user, 2026-09-29 "all flat"; it was the game's
-- check box, the kit's in its look; 0.19.9 the NewUI2 check box, the user's
-- pick 0A 2026-10-08 -- it was a box SWITCH_BOX px in an `innerPanel` fill and
-- a 1 px `trim` edge, ticked a check mark in `selectedTrim`, the active look
-- round it in the kit's look): a check button SWITCH px square with none of
-- the game's art, the kit's check box plate on it (KC: off, on, hover, and
-- onhover for a ticked box under the pointer; disabled, the plate at half),
-- laid again whenever it is ticked or unticked (its SetChecked, hooked: who
-- ever ticks it). The ticked plate shows "on": no active look round it. Its
-- rep is false (MelloUI.Kept.repOf), so the kit's sweep (Kit:SweepControls,
-- Kit:SkinCheckButton) passes it by.
-- SetValue(on, silent) sets it without (silent) or with set(on); Refresh()
-- takes get() again. A refresh that changes nothing leaves the box alone (a
-- tab's refresh set every box on it again -- user, 2026-09-24).
--   W.Switch(parent, get, set, opts) -> switch   (opts.skin: kept for the callers)
--   switch.melloPlate (the kit's plate)
--------------------------------------------------------------------------------

local SWITCH = 26

-- the plate as the switch is: ticked or not, lit under the pointer, at half
-- while disabled
local function SwitchLook(cb)
	local on = cb:IsEnabled() and true or false
	KC.Lay(cb.melloPlate, SWITCH, SWITCH, "check", nil,
		KC.State("check", flatHover[cb], false, cb:GetChecked(), not on), on and 1 or FLAT_OFF)
end

local SwitchChecked = Shared("SetChecked on MelloUI's switches", function(cb)
	SwitchLook(cb)
end, "hook")

local function SwitchSetValue(self, on, silent)
	on = on and true or false
	if silent and on == self.value and (self:GetChecked() and true or false) == on then
		return
	end
	self.value = on
	self:SetChecked(on)
	if not silent and self.melloSet then
		self.melloSet(on)
	end
end

local function SwitchRefresh(self)
	if self.melloGet then
		self:SetValue(self.melloGet() and true or false, true)
	end
end

local SwitchClick = Shared("OnClick on MelloUI's switches", function(self)
	local value = self:GetChecked() and true or false
	MelloUI:PlayUISound(value and "check_on" or "check_off")
	self:SetValue(value)
end, "script")

function W.Switch(parent, get, set)
	local cb = CreateFrame("CheckButton", nil, parent)
	cb:SetSize(SWITCH, SWITCH)
	KitRep(cb, false)   -- (the kit's sweep passes it by: no kit check box)
	local plate = cb:CreateTexture(nil, "ARTWORK")
	plate.melloOn = cb
	cb.melloPlate = plate
	cb.value = false
	cb.melloGet, cb.melloSet = get, set
	cb.SetValue, cb.Refresh = SwitchSetValue, SwitchRefresh
	Perf.SetScript(cb, "OnClick", SwitchClick)
	Perf.hooksecurefunc(cb, "SetChecked", SwitchChecked)
	FlatHooks(cb, SwitchLook)
	return cb
end

--------------------------------------------------------------------------------
-- Dropdown (0.15.0, flat: user, 2026-09-29 "all flat"; it was the game's
-- dropdown button and its menu): a box that names the choice and opens
-- MelloUI's own list of them under it, in the window's one flyout (a
-- picture row's too: W.PictureMenu, below). Never the game's menu: a game
-- menu opened from MelloUI code runs the Gamepad UI's frame manager in
-- MelloUI's run and blocks its bindings (the Gamepad UI freeze, v150 freeze
-- plan WP5b), so the list is MelloUI's own whatever the mode. The box is a
-- picture row's: an `innerPanel` fill in a 1 px `border` edge, the choice in
-- `text` from its left, a small caret at its right (0.19.9: the kit's arrow
-- glyph, KC, gold under the pointer); `hover` under the pointer; disabled, at
-- half and the choice in `mutedText`. `values` is
-- a list of { value, label, tooltip }, read whenever the box names the
-- choice or the list opens (a list filled again in place, or renamed in
-- place -- the Voice Over voices once the game has them, the Kit Colours
-- under a new palette -- is picked up by a refresh).
--   W.Dropdown(parent, width, get, set, values, opts) -> box   DD_H high
--     opts: default (the text shown while the value has no entry), tooltip
--     (the box's own tooltip body; its title is `default`), skin
--   box:Refresh()          the choice named again from get() (its text set
--                          only when it changed: nothing made)
--   box:SetValues(values)  another list on the box (0.15.0: a row whose
--                          setting is another key per pick): the choice
--                          named from it; a list open on the old one closes
--   box.Text, box.melloGet / melloSet / melloValues
-- The list (the flyout's list mode): a row per entry, LIST_ROW_H high, the
-- chosen one marked in gold, a row's tooltip its entry's; a click on a row
-- sets it and closes the list. A long list (user, 2026-09-26: "the list
-- does not have a slider option and is way too big" -- the Fonts dropdown's
-- sixty faces ran off the screen) shows at most MENU_ROWS entries and never
-- more than MENU_SCREEN of the screen, the rest by the wheel or its scroll
-- bar, the chosen one in view as it opens. It closes as the flyout does:
-- Escape, a click outside, the page scrolling, the box or the window
-- hidden, W.ClosePictureMenu (a tab, a page or a pick changed). Unlike a
-- picture row's it opens in combat, as the game's menu did. Nothing is made
-- until a list opens.
--------------------------------------------------------------------------------

local DropdownTip = Shared("OnEnter on MelloUI's dropdowns (tooltip)", function(self)
	W.ShowTooltip(self, self.melloTipTitle or "", self.melloTip)
end, "script")

-- Where `value` stands in the list (nil when it has no such entry): its
-- row's place in the list too, one row per entry
local function ChoiceIndex(values, value)
	if values then
		for i = 1, #values do
			if values[i].value == value then
				return i
			end
		end
	end
	return nil
end

-- An entry's text: its label, else its value as text (a string value as it
-- is: a refresh makes no string)
local function EntryText(entry)
	local value = entry.label
	if value then
		-- (`own`: a text shown as it is -- the Language dropdown's languages, each in its own words)
		return entry.own and value or W.Tr(value)
	end
	value = entry.value
	return (type(value) == "string" and value) or tostring(value)
end

-- The text the box shows for `value` (nil when the list has no such entry:
-- the box then shows its default text)
local function ChoiceLabel(values, value)
	local i = ChoiceIndex(values, value)
	return i and EntryText(values[i]) or nil
end

local CARET = 11               -- the caret: the kit's arrow glyph in a square this big (0.19.9, KC; it was four 1 px lines)

do
local DD_H = 25                -- the box's height
local DD_TEXT_X = 12           -- the choice's left in the box (2026-10-20: inside the piece's rounded left end)

-- (2026-10-20, the user's sheet: "go all the way with the new icons") the box is the dropdown piece -- its slate
-- trough in a gold rim, the arrow in a well at its right end -- at rest and under the pointer (piece_dd_closed,
-- piece_dd_hover: Tools/make_icons.py PIECES, 512 wide, the picture the top `h` of 64 rows, its ends `l` and `r`
-- of 512), three slices at the box's height: the ends keep their shape, the middle stretches
local DD_PIECE = {
	normal = { tex = TEXTURE_PATH .. "Icons\\piece_dd_closed", h = 42, l = 21.8, r = 54.6 },
	hover = { tex = TEXTURE_PATH .. "Icons\\piece_dd_hover", h = 43, l = 21.4, r = 54.3 },
}

local function DropdownSlices(dd)
	local s = {}
	for i = 1, 3 do
		s[i] = dd:CreateTexture(nil, "BACKGROUND", nil, 2)
	end
	s[1]:SetPoint("TOPLEFT")
	s[1]:SetPoint("BOTTOMLEFT")
	s[3]:SetPoint("TOPRIGHT")
	s[3]:SetPoint("BOTTOMRIGHT")
	s[2]:SetPoint("TOPLEFT", s[1], "TOPRIGHT")
	s[2]:SetPoint("BOTTOMRIGHT", s[3], "BOTTOMLEFT")
	dd.melloSlices = s
end

local function DropdownPiece(dd, state, alpha)
	local p, s = DD_PIECE[state], dd.melloSlices
	if dd.melloPiece ~= state then
		dd.melloPiece = state
		local v, k = p.h / 64, DD_H / p.h
		for i = 1, 3 do
			s[i]:SetTexture(p.tex)
		end
		s[1]:SetTexCoord(0, p.l / 512, 0, v)
		s[1]:SetWidth(p.l * k)
		s[2]:SetTexCoord(p.l / 512, 1 - p.r / 512, 0, v)
		s[3]:SetTexCoord(1 - p.r / 512, 1, 0, v)
		s[3]:SetWidth(p.r * k)
	end
	for i = 1, 3 do
		s[i]:SetAlpha(alpha)
	end
end

-- the box as it is: its piece (the hover) always; `whole`, its state
-- (enabled or not) too -- the choice's colour
local DropdownLook
do   -- (in a block: the main chunk is near Lua's 200 locals)
	-- (1.2.4, the Default skin: MelloUI.Skin) the game's own dropdown in the piece's place (WowStyle1DropdownTemplate's
	-- art and anchors, the box the game's 25 high: its text holder at its own 41 px height, its arrow button at its
	-- own 27 px, by state); made at its first need
	local function DropdownGame(dd, game, on)
		local g = dd.melloSkinParts
		if game and not g then
			g = { bg = dd:CreateTexture(nil, "BACKGROUND", nil, 2), arrow = dd:CreateTexture(nil, "ARTWORK", nil, 1) }
			g.bg:SetAtlas(MelloUI.Skin.ART.ddHolder)
			g.bg:SetPoint("TOPLEFT", dd, "TOPLEFT", -8, 7)
			g.bg:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", 8, -9)
			g.arrow:SetPoint("RIGHT", dd, "RIGHT", 1, -3)
			dd.melloSkinParts = g
		end
		for i = 1, 3 do
			dd.melloSlices[i]:SetShown(not game)
		end
		if not g then
			return
		end
		g.bg:SetShown(game)
		g.arrow:SetShown(game)
		if game then
			local A = MelloUI.Skin.ART
			g.arrow:SetAtlas((not on and A.ddArrowOff) or (flatHover[dd] and A.ddArrowLit) or A.ddArrow, true)
		end
	end

	DropdownLook = function(dd, whole)
		local on = dd:IsEnabled() and true or false
		local alpha = on and 1 or FLAT_OFF
		local Skin = rawget(MelloUI, "Skin")
		local game = Skin and Skin.IsDefault() or false
		if game or dd.melloSkinParts then
			DropdownGame(dd, game, on)
		end
		if not game then
			DropdownPiece(dd, (on and flatHover[dd]) and "hover" or "normal", alpha)
		end
		if whole then
			W.Paint(dd.Text, on and "text" or "mutedText", "text")
		end
	end
end

local function DropdownRefresh(self)
	local label = ChoiceLabel(self.melloValues, self.melloGet and self.melloGet()) or W.Tr(self.melloDefault) or ""
	if label ~= self.shownLabel then
		self.shownLabel = label
		self.Text:SetText(label)
	end
end

local function DropdownSetValues(self, values)
	if values == self.melloValues then
		return
	end
	self.melloValues = values
	Flyout.BoxHidden(self)   -- (a list open on the old one closes)
	self:Refresh()
end

local DropdownClick = Shared("OnClick on MelloUI's dropdowns (its list)", function(self)
	Flyout.Toggle(self)
end, "script")

function W.Dropdown(parent, width, get, set, values, opts)
	opts = opts or NO_OPTS
	local dd = CreateFrame("Button", nil, parent)
	dd:SetSize(width, DD_H)
	KitRep(dd, false)   -- (the kit's sweep passes it by: no dropdown plate)
	dd.melloList = true   -- (it opens the flyout's list: W.PictureMenu's block)
	-- (2026-10-20) the dropdown piece of the user's sheet in three slices, the arrow in its right end's well (it was
	-- 0.20.1's pick A: THE text field's look and the kit's gold caret)
	DropdownSlices(dd)
	local text = W.Text(dd, "GameFontHighlight", nil, "text")
	text:SetJustifyV("MIDDLE")
	text:SetWordWrap(false)
	text:SetPoint("LEFT", dd, "LEFT", DD_TEXT_X, 0)
	text:SetPoint("RIGHT", dd, "RIGHT", -(DD_PIECE.normal.r * DD_H / DD_PIECE.normal.h + 4), 0)
	dd.Text = text
	dd.melloGet, dd.melloSet, dd.melloValues = get, set, values
	dd.melloDefault, dd.melloSkin = opts.default, opts.skin
	dd.Refresh, dd.SetValues = DropdownRefresh, DropdownSetValues
	Perf.SetScript(dd, "OnClick", DropdownClick)
	Perf.SetScript(dd, "OnHide", Flyout.BoxHidden)
	FlatHooks(dd, DropdownLook)
	if rawget(MelloUI, "Skin") then
		MelloUI.Skin.followers[dd] = DropdownLook   -- (1.2.4: the skin switched, the box in its look)
	end
	if opts.tooltip then
		dd.melloTipTitle, dd.melloTip = opts.default, opts.tooltip
		Perf.HookScript(dd, "OnEnter", DropdownTip)
		Perf.HookScript(dd, "OnLeave", TipLeave)
	end
	dd:Refresh()
	return dd
end
end   -- (the dropdown's do-block, 2026-10-20)

--------------------------------------------------------------------------------
-- Slider (0.15.0, Sliders 1, the cleaner look the user picked; it was the
-- game's minimal slider with steppers and the kit's SL1 pieces): a thin track
-- 4 px high (`innerPanel` in a 1 px `border` edge), the part from the least
-- value to the knob in `trim`, a round knob 14 px in `selectedTrim` in a
-- 1 px `innerPanel` ring, and the value in a small box you can type in
-- (46 x 20, `innerPanel` in a `border` edge, the text colour; wider, up to
-- 96, where the format names a value in words -- "Edit Mode's", "no limit"
-- -- the track the shorter for it). No steppers, no gem ends, in both looks.
-- The wheel is not taken: the page scrolls.
-- The box never takes the keyboard by itself (an edit box made shown takes
-- the focus, and a page of them would hold the movement keys while the
-- window is open): only a click gives it the focus. Enter, Tab or leaving it
-- takes the number (a percent slider "40" or "40%"), kept in the range and
-- rounded to the step, and lets the focus go; Escape puts the value back and
-- lets it go (the window never sees that Escape); the window's hide lets it
-- go too, the value put back.
--   W.Slider(parent, width, get, set, opts) -> slider   a Frame `width` wide
--     and 20 high: the track `width - W.SLIDER_BOX` (54) from its left, the
--     box at its right (a box wider for its words: the track that much
--     shorter)
--     opts: min (0), max (1), step (0.05), percent, format (fn(v) -> text),
--     skin (kept for the callers: a flat slider has nothing to dress)
--   slider:Refresh()   get() again (the box left alone while it is typed in)
--   slider:SetRange(min, max, step[, percent, format])   another range (a
--     row whose setting is another key per pick): the value put in it
--   slider.Slider (the track's Slider frame), slider.box (the EditBox),
--   slider.melloGet / melloSet; W.Round(value, step)
-- Its handlers are shared (no closure per slider); nothing runs while it is
-- left alone.
--------------------------------------------------------------------------------

do
	local function Round(value, step)
		if not step or step <= 0 then
			return value
		end
		local n = math.floor(value / step + 0.5) * step
		local digits, s = 0, step
		while s < 1 and digits < 6 do
			s = s * 10
			digits = digits + 1
		end
		local mult = 10 ^ digits
		return math.floor(n * mult + 0.5) / mult
	end
	W.Round = Round

	local function PercentText(v)
		return string.format("%d%%", math.floor(v * 100 + 0.5))
	end
	local function PlainText(v)
		if math.abs(v - math.floor(v + 0.5)) < 0.001 then
			return tostring(math.floor(v + 0.5))
		end
		return string.format("%.2f", v)
	end

	local SLIDER_H = 20          -- the slider's frame: the box's height
	local TRACK_H = 4            -- the track, its 1 px edge included
	local KNOB = 14              -- the knob, its 1 px ring included
	local BOX_W, BOX_GAP = 46, 8 -- the value box (its least width), and the room between the track and it
	local BOX_MAX = 96           -- the widest a box grows for its texts
	local BOX_INSET = 3          -- the box's text insets, left and right
	local BOX_LETTERS = 10       -- the least a box takes typed (more when a text of its value is longer)
	local BOX_FONT = "GameFontHighlight"
	W.SLIDER_BOX = BOX_W + BOX_GAP   -- the slider's width less the track's (a box wider for its words takes more)

	-- the value as the box shows it
	local function ValueText(slider, v)
		local fmt = slider.melloFormat or (slider.melloPercent and PercentText) or PlainText
		return fmt(v)
	end

	-- the one hidden text the boxes' texts are measured on (made with the
	-- first slider, never at load)
	local measure = nil

	local function MeasuredWidth(parent, text)
		if not measure then
			measure = parent:CreateFontString(nil, "BACKGROUND", BOX_FONT)
			measure:Hide()
		end
		measure:SetText(text)
		local get = measure.GetUnboundedStringWidth or measure.GetStringWidth
		return Num(get(measure)) or 0
	end

	-- The box as wide as the widest text its value shows at the range's ends
	-- and at 0, where a format names the value in words ("Edit Mode's", "no
	-- limit", "Default"): BOX_W to BOX_MAX, the track giving the room (the
	-- slider keeps its width); it takes as many letters as its longest text.
	-- At the make and on SetRange only.
	local function FitBox(slider)
		local min, max = slider.melloMin, slider.melloMax
		local widest, letters = 0, BOX_LETTERS
		for i = 1, 3 do
			if i < 3 or (min <= 0 and max >= 0) then
				local text = tostring(ValueText(slider, (i == 1 and min) or (i == 2 and max) or 0))
				widest = math.max(widest, MeasuredWidth(slider, text))
				letters = math.max(letters, #text)
			end
		end
		local boxW = math.max(BOX_W, math.min(BOX_MAX, math.ceil(widest) + 2 * BOX_INSET + 2))
		slider.box:SetMaxLetters(letters)
		slider.box:SetWidth(boxW)
		slider.Slider:SetWidth(math.max(KNOB, slider.melloWidth - boxW - BOX_GAP))
	end

	-- the box shows `v` (the value only when it changed: a refresh of an
	-- unchanged row makes no string)
	local function ShowValue(slider, v)
		if v ~= slider.shownValue then
			slider.shownValue = v
			slider.box:SetText(ValueText(slider, v))
		end
	end

	-- the slider's value moved (a drag, a click on the track, a SetValue): kept
	-- to the step and handed to set, the box following
	local SliderChanged = Shared("OnValueChanged on MelloUI's sliders", function(track, value)
		local slider = track.melloSlider
		if not slider or slider.refreshing then
			return
		end
		value = Round(value, slider.melloStep)
		if slider.melloGet() ~= value then
			slider.melloSet(value)
		end
		ShowValue(slider, value)
	end, "script")

	local function SliderRefresh(self)
		local v = self.melloGet() or self.melloMin
		self.refreshing = true
		self.Slider:SetValue(v)
		self.refreshing = false
		if not self.box:HasFocus() then
			ShowValue(self, v)
		end
	end

	local function SliderSetRange(self, min, max, step, percent, format)
		self.melloMin, self.melloMax, self.melloStep = min or 0, max or 1, step or 0.05
		if percent ~= nil or format ~= nil then
			self.melloPercent, self.melloFormat = percent and true or false, format
		end
		self.refreshing = true
		self.Slider:SetMinMaxValues(self.melloMin, self.melloMax)
		self.Slider:SetValueStep(self.melloStep)
		self.refreshing = false
		FitBox(self)
		self.shownValue = nil   -- (the text again: another format, or the same number in a new range)
		self:Refresh()
	end

	-- The number typed in the box: its first number ("40%", "40", "1.5x"),
	-- a hundredth of it on a percent slider, kept in the range and rounded to
	-- the step; nil for none
	local function TypedValue(slider, text)
		local n = tonumber(tostring(text or ""):match("%-?%d*%.?%d+"))
		if not n then
			return nil
		end
		if slider.melloPercent then
			n = n / 100
		end
		n = Round(n, slider.melloStep)
		return math.max(slider.melloMin, math.min(slider.melloMax, n))
	end

	-- the typed number taken (none: the value put back); the box shows the
	-- value as it is after
	local function TakeTyped(box)
		local slider = box.melloSlider
		local v = TypedValue(slider, box:GetText())
		if v ~= nil then
			slider.Slider:SetValue(v)
			if slider.melloGet() ~= v then
				slider.melloSet(v)   -- (the slider was there already: no OnValueChanged)
			end
		else
			v = slider.melloGet() or slider.melloMin
		end
		slider.shownValue = nil
		ShowValue(slider, v)
	end

	-- the focus let go, the number taken (`take`) or the value put back; the
	-- focus-lost that follows takes nothing again
	local function LetGo(box, take)
		if take then
			TakeTyped(box)
		else
			local slider = box.melloSlider
			slider.shownValue = nil
			ShowValue(slider, slider.melloGet() or slider.melloMin)
		end
		if box:HasFocus() then
			box.melloLetGo = true
			box:ClearFocus()
		end
	end

	local BoxTake = Shared("OnEnterPressed / OnTabPressed on a slider's value box", function(box)
		LetGo(box, true)
	end, "script")

	local BoxEscape = Shared("OnEscapePressed on a slider's value box", function(box)
		LetGo(box, false)
	end, "script")

	local BoxFocusGained = Shared("OnEditFocusGained on a slider's value box", function(box)
		box.field:SetState(true)
		box:HighlightText()
	end, "script")

	-- a click elsewhere: the number taken (the box's own Enter, Tab or Escape
	-- already had its say)
	local BoxFocusLost = Shared("OnEditFocusLost on a slider's value box", function(box)
		box.field:SetState(false)
		if box.melloLetGo then
			box.melloLetGo = nil
			return
		end
		TakeTyped(box)
	end, "script")

	-- the window hidden (the box with it): the focus let go, the value back
	local BoxHidden = Shared("OnHide on a slider's value box", function(box)
		if box:HasFocus() then
			LetGo(box, false)
		end
	end, "script")

	-- the track: its edge and fill, the value's part in `trim`, the round knob
	-- (the thumb: the ring, the knob's disc on it, each under its round mask)
	local function SliderTrack(slider, width)
		local track = CreateFrame("Slider", nil, slider)
		track:SetOrientation("HORIZONTAL")
		track:SetSize(width - W.SLIDER_BOX, KNOB)
		track:SetPoint("LEFT", slider, "LEFT", 0, 0)
		track:EnableMouse(true)
		track:EnableMouseWheel(false)
		track.melloSlider = slider
		local edge = W.Solid(track, "BACKGROUND", "border", 1)
		edge:SetHeight(TRACK_H)
		edge:SetPoint("LEFT", track, "LEFT", 0, 0)
		edge:SetPoint("RIGHT", track, "RIGHT", 0, 0)
		local fill = W.Solid(track, "BACKGROUND", "innerPanel", 1)
		fill:SetDrawLayer("BACKGROUND", 1)
		fill:SetHeight(TRACK_H - 2)
		fill:SetPoint("LEFT", track, "LEFT", 1, 0)
		fill:SetPoint("RIGHT", track, "RIGHT", -1, 0)
		-- (0.25.0) the knob: the gold knob of MelloUI's icon set (Media/Textures/Icons/ctl_knob), a touch over the
		-- track's height; it was a palette disc in an innerPanel ring under two round masks
		local ring = track:CreateTexture(nil, "OVERLAY", nil, 0)
		ring:SetSize(KNOB + 2, KNOB + 2)
		MelloUI.Icons.Set(ring, "ctl_knob", KNOB + 2)
		track:SetThumbTexture(ring)
		local knob = ring
		-- (from the least value to the knob's middle: it moves with the knob)
		local part = W.Solid(track, "ARTWORK", "trim", 1)
		part:SetHeight(TRACK_H - 2)
		part:SetPoint("LEFT", track, "LEFT", 1, 0)
		part:SetPoint("RIGHT", ring, "CENTER", 0, 0)
		track.edge, track.fill, track.part, track.knob, track.ring = edge, fill, part, knob, ring
		Perf.SetScript(track, "OnValueChanged", SliderChanged)
		return track
	end

	-- the value's box: never the keyboard's until clicked
	local function SliderBox(slider)
		local box = CreateFrame("EditBox", nil, slider)
		box:SetAutoFocus(false)
		box:SetSize(BOX_W, SLIDER_H)
		box:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
		box:SetFontObject(BOX_FONT)
		box:SetJustifyH("CENTER")
		box:SetTextInsets(BOX_INSET, BOX_INSET, 0, 0)
		box:SetMaxLetters(BOX_LETTERS)
		box:EnableMouse(true)
		box:EnableMouseWheel(false)
		W.Paint(box, "text", "text")
		box.field = W.Field(box)   -- (0.20.1: THE text field)
		box.melloSlider = slider
		Perf.SetScript(box, "OnEnterPressed", BoxTake)
		Perf.SetScript(box, "OnTabPressed", BoxTake)
		Perf.SetScript(box, "OnEscapePressed", BoxEscape)
		Perf.SetScript(box, "OnEditFocusGained", BoxFocusGained)
		Perf.SetScript(box, "OnEditFocusLost", BoxFocusLost)
		Perf.SetScript(box, "OnHide", BoxHidden)
		return box
	end

	function W.Slider(parent, width, get, set, opts)
		opts = opts or NO_OPTS
		local min, max, step = opts.min or 0, opts.max or 1, opts.step or 0.05
		local slider = CreateFrame("Frame", nil, parent)
		slider:SetSize(width, SLIDER_H)
		slider:EnableMouseWheel(false)
		slider.melloGet, slider.melloSet = get, set
		slider.melloMin, slider.melloMax, slider.melloStep = min, max, step
		slider.melloPercent, slider.melloFormat = opts.percent and true or false, opts.format
		slider.melloWidth = width
		slider.refreshing = false
		slider.box = SliderBox(slider)
		local track = SliderTrack(slider, width)
		slider.Slider = track
		slider.refreshing = true
		track:SetMinMaxValues(min, max)
		track:SetValueStep(step)
		track:SetObeyStepOnDrag(true)
		slider.refreshing = false
		FitBox(slider)
		slider.Refresh, slider.SetRange = SliderRefresh, SliderSetRange
		slider:Refresh()
		return slider
	end
end

--------------------------------------------------------------------------------
-- Buttons (0.15.0, Buttons 1, the cleaner look the user picked; they were
-- the kit's red plate, B1): the game's panel button, flat in both looks --
-- the template's plate art hidden, a `raisedPanel` fill in a 1 px `border`
-- edge (W.Edges), the label in the text colour. Under the mouse the fill
-- takes `hover`; pressed, the label goes 1 px down (the button's own pushed
-- text offset); disabled, the fill and the edge at half and the label in
-- `mutedText`. The main action (opts.gold: Install..., Install again, the
-- installer's forward button, Restock's Buy, a question's accept) wears its
-- edge and label in `selectedTrim` (its label `text` on the hover fill). No
-- gem caps: its rep is false (MelloUI.Kept.repOf) before any sweep, so the kit's
-- (Kit:SweepControls, Kit:SkinRedButton) passes it by, whatever window it
-- is in.
--   W.Button(parent, text, width, skin, opts) -> button
--     opts: height (22), onClick (a shared handler), gold, filled (1.2.4:
--     with gold, the gold on the selected fill, its label the text colour)
--     (`skin` kept for the callers: a flat button has nothing to dress)
--   W.FlatButton(button, gold) -> button   the same look on a button made
--     by hand from UIPanelButtonTemplate (its creation line kept); once
--   button.melloFill, button.melloEdges (button.melloOutline: the gold edge)
-- The flat controls' one set of handlers (FlatHooks); the colours looked
-- up in the palette when painted (a new palette paints them again).
--   W.CloseButton(parent, skin) -> button   (0.15.0, flat: user, 2026-09-29
--     "all flat"; it was the game's red cross, RedButton-Exit in the kit's
--     look; 0.19.9 the NewUI2 close plate, the user's pick 0A 2026-10-08 --
--     it was a flat plate with the search box's cross): a button CLOSE px
--     square with the kit's close plate on it (KC: steel, gold under the
--     pointer, dark red while the mouse is down on it, at half disabled), the
--     one close of the own windows. The click is the caller's (the
--     configurator's, the shell's), as it always was; `skin` kept for the
--     callers.
--   button.melloPlate
--------------------------------------------------------------------------------

do
	local PLATE_PARTS = { "Left", "Middle", "Right", "Center" }   -- the template's plate (the older and the 128 red one)
	local PLATE_TEXTURES = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }
	local flatGold = setmetatable({}, weakKeys)    -- [button] = true: the main action's
	local flatFilled = setmetatable({}, weakKeys)  -- [button] = true: (1.2.4) its gold filled, not outlined
	local CLOSE = 22                               -- the close button
	local closeDown = setmetatable({}, weakKeys)   -- [close button] = true while the mouse is down on it

	-- the template's own plate hidden, once at build (UIPanelButtonTemplate's
	-- scripts only set its textures: SecureUIPanelTemplates.lua)
	local function HidePlate(b)
		for _, key in ipairs(PLATE_PARTS) do
			local part = rawget(b, key)
			if part then
				part:SetAlpha(0)
				part:Hide()
			end
		end
		for _, getter in ipairs(PLATE_TEXTURES) do
			local tex = b[getter] and b[getter](b)
			if tex then
				tex:SetAlpha(0)
			end
		end
	end

	-- The look as the button is (`edges`: its edge too -- it changes only
	-- with the button's state, not its hover). The label is painted every time:
	-- the button's own font changes (normal / highlight / disabled) take its
	-- colour. A gold label on the hover fill would be too faint (the
	-- palette's rule: only `text` on `hover`), so under the pointer the main
	-- action's label is `text`, its edge still gold.
	-- (1.2.4, the Default skin: MelloUI.Skin) the game's own red panel button in the flat plate's place: the three
	-- pieces of UIPanelButtonTemplate's own file (its art the top 22 of 32 rows: never taller than that, centred), its
	-- highlight added over them under the pointer, its disabled file while disabled; the label the game's gold (white
	-- under the pointer). Made at its first need
	local function GameSlices(b, layer, sub)
		local s = {}
		local h = math.min(Num(b:GetHeight()) or 22, 22)
		for i = 1, 3 do
			s[i] = b:CreateTexture(nil, layer, nil, sub)
		end
		s[1]:SetSize(12, h)
		s[1]:SetPoint("LEFT")
		s[3]:SetSize(12, h)
		s[3]:SetPoint("RIGHT")
		s[2]:SetPoint("TOPLEFT", s[1], "TOPRIGHT")
		s[2]:SetPoint("BOTTOMRIGHT", s[3], "BOTTOMLEFT")
		return s
	end
	local function GameFile(s, file)
		for i = 1, 3 do
			s[i]:SetTexture(file)
		end
		s[1]:SetTexCoord(0, 0.09375, 0, 0.6875)
		s[2]:SetTexCoord(0.09375, 0.53125, 0, 0.6875)
		s[3]:SetTexCoord(0.53125, 0.625, 0, 0.6875)
	end
	local function GamePlate(b, game, on, lit)
		local g = b.melloSkinParts
		if game and not g then
			g = { plate = GameSlices(b, "BACKGROUND", 3), lit = GameSlices(b, "ARTWORK", 1) }
			GameFile(g.lit, MelloUI.Skin.ART.buttonLit)
			for i = 1, 3 do
				g.lit[i]:SetBlendMode("ADD")
			end
			b.melloSkinParts = g
		end
		b.melloFill:SetShown(not game)
		for i = 1, 4 do
			b.melloEdges[i]:SetShown(not game)
		end
		if not g then
			return
		end
		local file = on and MelloUI.Skin.ART.button or MelloUI.Skin.ART.buttonOff
		if g.file ~= file then
			g.file = file
			GameFile(g.plate, file)
		end
		for i = 1, 3 do
			g.plate[i]:SetShown(game)
			g.lit[i]:SetShown(game and lit and true or false)
		end
	end

	local function FlatLook(b, edges)
		local on = b:IsEnabled() and true or false
		local alpha = on and 1 or FLAT_OFF
		local gold = flatGold[b]
		local lit = on and flatHover[b]
		local Skin = rawget(MelloUI, "Skin")
		local game = Skin and Skin.IsDefault() or false
		if game or b.melloSkinParts then
			GamePlate(b, game, on, lit)
		end
		if game then
			local fs = b:GetFontString()
			if fs then
				W.Paint(fs, (not on and "mutedText") or (lit and "text") or "selectedTrim", "text")
			end
			return
		end
		-- (1.2.4, Edit Layout's dock: the user's pick A of editlayout_dock_sketch) a filled gold one, the main action
		-- on a bar of its own: the selected fill under its gold edge, its label in the text colour
		local filled = gold and flatFilled[b]
		W.Paint(b.melloFill, (lit and "hover") or (filled and "selectedTab") or "raisedPanel", "fill", alpha)
		if edges then
			local key = gold and "selectedTrim" or "border"
			for i = 1, 4 do
				W.Paint(b.melloEdges[i], key, "fill", alpha)
			end
		end
		local fs = b:GetFontString()
		if fs then
			W.Paint(fs, (not on and "mutedText") or (gold and not lit and not filled and "selectedTrim") or "text", "text")
		end
	end

	local function FlatLookWhole(b)
		FlatLook(b, true)
	end

	function W.FlatButton(b, gold)
		if not b or b.melloFill then
			return b
		end
		KitRep(b, false)   -- (the kit's sweep passes it by: no red plate, no gem caps)
		b.melloFill = b:CreateTexture(nil, "BACKGROUND", nil, 2)
		b.melloFill:SetAllPoints(b)
		b.melloEdges = Edges(b, "border", "BORDER")
		flatGold[b] = gold and true or nil
		if gold then
			b.melloOutline = b.melloEdges
		end
		if b.SetPushedTextOffset then
			b:SetPushedTextOffset(0, -1)
		end
		HidePlate(b)
		FlatHooks(b, FlatLook, true)
		local Skin = rawget(MelloUI, "Skin")
		if Skin then
			Skin.followers[b] = FlatLookWhole   -- (1.2.4: the skin switched, its plate in the skin's look)
		end
		return b
	end

	-- (one look) a flat button's gold on or off: the picked one of a row of
	-- chips (W.Chips) -- its edge and label `selectedTrim`; painted again
	-- only when it changes
	function W.FlatGold(b, on)
		if not (b and b.melloFill) then
			return
		end
		on = on and true or nil
		if flatGold[b] ~= on then
			flatGold[b] = on
			FlatLook(b, true)
		end
	end

	function W.Button(parent, text, width, skin, opts)
		local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		b:SetSize(width or 110, opts and opts.height or 22)
		b:SetText(W.Tr(text) or "")
		W.FitButton(b)
		if opts and opts.onClick then
			Perf.SetScript(b, "OnClick", opts.onClick)
		end
		if opts and opts.gold and opts.filled then
			flatFilled[b] = true
		end
		return W.FlatButton(b, opts and opts.gold)
	end

	-- (the languages: a German or French label runs about 30% longer) a text button made wider when its text would
	-- run past its edges (BUTTON_PAD kept at each side); never narrower than it was made, so an English label that
	-- fits leaves its button as it was (the sim's English sweep: no button changed)
	local BUTTON_PAD = 4
	function W.FitButton(b)
		local fs = b.GetFontString and b:GetFontString()
		if not fs then
			return
		end
		local get = fs.GetUnboundedStringWidth or fs.GetStringWidth
		local w, now = Num(get(fs)), Num(b:GetWidth())
		if w and now and w + 2 * BUTTON_PAD > now then
			b:SetWidth(math.ceil(w + 2 * BUTTON_PAD))
		end
	end

	-- the close button as it is: our plate in the state's piece
	local function CloseLook(b)
		local on = b:IsEnabled() and true or false
		KC.Lay(b.melloPlate, CLOSE, CLOSE, "close", nil, KC.State("close", flatHover[b], closeDown[b], nil, not on),
			on and 1 or FLAT_OFF)
	end

	local CloseDown = Shared("OnMouseDown on MelloUI's close buttons", function(b)
		closeDown[b] = true
		b.melloLook(b)
	end, "script")
	local CloseUp = Shared("OnMouseUp on MelloUI's close buttons", function(b)
		closeDown[b] = nil
		b.melloLook(b)
	end, "script")

	function W.CloseButton(parent)
		local close = CreateFrame("Button", nil, parent)
		close:SetSize(CLOSE, CLOSE)
		KitRep(close, false)   -- (the kit's sweep passes it by)
		local plate = close:CreateTexture(nil, "ARTWORK")
		plate.melloOn = close
		close.melloPlate = plate
		Perf.HookScript(close, "OnMouseDown", CloseDown)
		Perf.HookScript(close, "OnMouseUp", CloseUp)
		FlatHooks(close, CloseLook)
		return close
	end
end

--------------------------------------------------------------------------------
-- Tabs (1.2.4, text tabs: the user's pick A of MelloUI-BuildData/output/config_tabs_sketch, 2026-10-28, "A: text
-- tabs"; before them the 0.15.0 flat plates, then 2026-10-20's peaked pieces): a page's tab -- the game's top tab
-- (PanelTopTabButtonTemplate), made by the caller (the configurator's pages, Fight History, Dungeon Info, the map's
-- quest log) -- its art hidden, the tab TAB_H high: its label alone, at full size in every state (the widgets' own
-- GameFontHighlight), `text` at rest; the selected one `selectedTrim`, a short line of that gold along its foot
-- (TAB_IN inside its sides, LINE_H high) in MelloUI.Shade's soft light of the same gold; the one under the pointer a
-- faint line (HOVER_A of the gold, one unit high, HOVER_IN further in). The Default skin keeps the game's tabs'
-- colours: `selectedTrim` gold at rest, `text` selected and under the pointer. Under Oldschool's painted reskin the
-- selected label is `text` (the painted palettes' gold is darker than their text: Ember's 5.1:1 against 8:1). No plate
-- and no active look round the selected one, in any skin. The label rides LABEL_UP over the tab's middle, clear of the
-- line (the game's select bobs it up and down), and is never cut short: its width is the text's own (an owner that
-- sized the tab with PanelTemplates_TabResize at the template's small font keeps that width, the label at full size
-- in it). Its rep is false (MelloUI.Kept.repOf), so the kit's sweep (Kit:SkinPanelTab) passes it by. The tab keeps
-- the width its owner gives it: the template's own resize on a show and on a display change is dropped (it undid the
-- owner's padding: the tabs' gaps jumped).
--   W.FlatTab(tab, skin) -> tab   once per tab; then
--   tab:SetSelected(on)   the selected look; the selected tab disabled, as the game's select makes it (a click on it
--                         does nothing), its tooltip hidden; then tab.melloOnSelect(tab), when its owner set one
--   W.TabFit(tab, pad) -> width   the tab as wide as its label and `pad` at each side (the configurator's row)
--   tab.melloLine (the line), tab.melloGlow (its light: a Shade band, made at the tab's first select)
--------------------------------------------------------------------------------

do
	local TAB_H, TAB_IN = 24, 4            -- the tab's height; the selected line inside its sides
	local LINE_H, LABEL_UP = 2, 3          -- the selected line's height; the label's middle over the tab's
	local HOVER_A, HOVER_IN = 0.5, 2       -- the line under the pointer: its strength of the gold, further in each side
	local TAB_FONT = "GameFontHighlight"   -- (full size: the option rows' labels -- CLAUDE.md rule 8)
	-- the selected line's light: a hollow soft band round it, light (ADD) in its gold (Frame Hover's way)
	local GLOW = { colour = "selectedTrim", alpha = 0.5, feather = 6, featherY = 3, blend = "ADD", hollow = true,
		layer = "BACKGROUND", sublevel = 1 }
	local TAB_ART = { "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
		"LeftHighlight", "MiddleHighlight", "RightHighlight" }
	local tabOn = setmetatable({}, weakKeys)   -- [tab] = true: the selected one

	-- the template's own art (PanelTopTabButtonTemplate: Left / Middle /
	-- Right at rest, the *Active three while selected, the *Highlight three
	-- under the pointer) at alpha 0 and hidden, again at every lay: the
	-- game's select (PanelTemplates_SelectTab) shows the *Active three again
	-- after its Disable, so their alpha keeps them unseen; the open tab's
	-- middle as tall as the tab (the owner lays the tab row by it)
	local function TabArt(tab)
		for _, key in ipairs(TAB_ART) do
			local art = rawget(tab, key)
			if art then
				art:SetAlpha(0)
				art:Hide()
			end
		end
		local open = rawget(tab, "MiddleActive")
		if open then
			open:SetHeight(TAB_H)
		end
	end

	-- Oldschool's painted reskin on (its palettes' gold darker than their text: a picked label takes the text colour;
	-- the tabs' and the chips')
	function W.PaintedReskin()
		local Kit = rawget(MelloUI, "Kit")
		return type(Kit) == "table" and type(Kit.IsOn) == "function" and Kit:IsOn("copy") == true
	end
	local Painted = W.PaintedReskin

	-- the line along the tab's foot: the selected one's (its light with it), or the one under the pointer; laid again
	-- only when the state changes
	local function TabLine(tab, on, lit)
		local line, want = tab.melloLine, (on and "on") or (lit and "lit") or nil
		if tab.melloLineState ~= want then
			tab.melloLineState = want
			line:SetShown(want ~= nil)
			if want then
				local inset = on and TAB_IN or (TAB_IN + HOVER_IN)
				line:ClearAllPoints()
				line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", inset, 0)
				line:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -inset, 0)
				line:SetHeight(on and LINE_H or 1)
				W.Paint(line, "selectedTrim", "fill", on and 1 or HOVER_A)
			end
		end
		local glow = tab.melloGlow
		if on and not glow then
			local Shade = rawget(MelloUI, "Shade")
			glow = Shade and Shade.Band and Shade:Band(tab, GLOW) or nil
			if glow then
				glow:Anchor(line)
				tab.melloGlow = glow
			end
		end
		if glow then
			glow:SetShown(on)
		end
	end

	-- the whole look, every time (a tab has few parts): its line by state and hover, the label painted again (the
	-- button's own fonts change its colour)
	local function TabLook(tab)
		local on = tabOn[tab] == true
		TabArt(tab)
		local lit = (flatHover[tab] and not on) and true or false
		TabLine(tab, on, lit)
		local fs = tab.Text
		if fs then
			fs:SetWidth(0)   -- (never cut short: PanelTemplates_TabResize fixes it at the width it measured)
			local Skin = rawget(MelloUI, "Skin")
			local key
			if Skin and Skin.IsDefault() then
				key = (on or lit) and "text" or "selectedTrim"
			else
				key = (on and not Painted()) and "selectedTrim" or "text"
			end
			W.Paint(fs, key, "text")
		end
	end

	-- (widget:melloActive: no active look round a text tab, in any skin -- the selected one is its label and line)
	local function TabActive(tab)
		return false, tab, "rect"
	end

	local function TabSetSelected(tab, on)
		on = on and true or false
		tabOn[tab] = on or nil
		tab:SetEnabled(not on)
		if on and GameTooltip:GetOwner() == tab then
			GameTooltip:Hide()
		end
		TabLook(tab)
		-- (its owner told: the configurator's row scrolls its selected tab into view)
		local told = on and rawget(tab, "melloOnSelect")
		if told then
			told(tab)
		end
	end

	function W.TabFit(tab, pad)
		local fs = tab and tab.Text
		local width = 0
		if fs then
			fs:SetWidth(0)
			local get = fs.GetUnboundedStringWidth or fs.GetStringWidth
			width = Num(get(fs)) or 0
		end
		width = math.ceil(width + 2 * (Num(pad) or 0))
		tab:SetWidth(width)
		return width
	end

	function W.FlatTab(tab, skin)
		if not tab or tab.melloLine then
			return tab
		end
		KitRep(tab, false)   -- (the kit's sweep passes it by: no TB6)
		-- (the tab as tall as TAB_H, and its hidden open-tab art too: the height its owner lays the tab row by; a New
		-- badge on its top edge)
		tab:SetHeight(TAB_H)
		-- (the label at full size in every state: the template's are GameFontNormalSmall / GameFontHighlightSmall)
		if tab.SetNormalFontObject then
			local font = W.FontObject(TAB_FONT)
			tab:SetNormalFontObject(font)
			tab:SetHighlightFontObject(font)
			tab:SetDisabledFontObject(font)
		end
		local line = tab:CreateTexture(nil, "BORDER")
		line:Hide()
		tab.melloLine = line
		local fs = tab.Text
		if fs then
			fs:ClearAllPoints()
			fs:SetPoint("CENTER", tab, "CENTER", 0, LABEL_UP)
			fs:SetWidth(0)
		end
		-- (the owner's width kept: the template sizes the tab again on a show
		-- and on a display change, to its own padding)
		Perf.SetScript(tab, "OnShow", nil)
		tab:UnregisterEvent("DISPLAY_SIZE_CHANGED")
		tab.melloSkin = skin
		tab.SetSelected, tab.melloActive, tab.melloKitLook = TabSetSelected, TabActive, TabLook
		FlatHooks(tab, TabLook)
		FollowLook(skin, tab)
		local Skin = rawget(MelloUI, "Skin")
		if Skin then
			Skin.followers[tab] = TabLook   -- (1.2.4: the skin switched, the tab in its colours)
		end
		return tab
	end
end

--------------------------------------------------------------------------------
-- Scroll rows (1.2.4; the user's pick for a row too long for its room, 2026-10-28: "Tighten, then scroll" -- the
-- configurator's page tabs first, then the designers' Parts line: one row, never two): a row of frames side by side
-- in a clip of its own (its children clipped), on a strip that slides inside it. A row longer than its room scrolls:
-- at a cut edge, while the row hides more that way, MelloUI.Shade's soft band in the window's colour over the frames
-- -- its full middle the `cover` at the clip's edge, so no label shows under the arrow on it, its soft end `edge`
-- further in -- and a small arrow (the icon set's btn_arrow on W.RoundIcon: the game's picture under Default) that
-- scrolls it a `step`; the mouse wheel over the row a `wheel` (the wheel taken only while the row scrolls: else it
-- goes on to what lies under the row, a page's own scroll). The frame shown (row:Show: a tab or chip picked) stays in
-- view, clear of the band beside it, at every lay. The clip reaches `pad` past the room at each side, `below` under
-- the frames and `above` over them (a picked line's light, a New badge); its caller anchors it, the frames' start
-- `pad` in from its left and their foot `below` over its bottom. The edges' parts are made at the row's first scroll;
-- a row that fits makes none and lies still.
--   W.ScrollRow(parent[, spec]) -> row   spec (read once): pad (8), below (6), above (14), cover (32), edge (24),
--       arrow (18), arrowY (the arrows' middle over the clip's: 0), step (80), wheel (60), fade (the band's strength:
--       0.9; false: no band, the arrows alone), paper (the picture the row lies on, a texture: the band that picture
--       itself rather than the dark shade -- PaperBand)
--   row:Lay(frames, room, high[, gap]) -> width   the frames (made on row.strip) from its left, `gap` apart
--   row:Show(frame)   that frame brought into view, and kept so at the next lays
--   row.clip, row.strip, row.room, row.max (its reach: the width past the room), row.scroll, row.xs[frame],
--   row.fadeL / fadeR, row.arrowL / arrowR (once made)
--------------------------------------------------------------------------------

do
	local ROW = { pad = 8, below = 6, above = 14, cover = 32, edge = 24, arrow = 18, arrowY = 0, step = 80, wheel = 60,
		fade = 0.9, paper = false }

	local function Scroll(row, s)
		s = math.max(0, math.min(row.max, s or 0))
		row.scroll = s
		row.strip:ClearAllPoints()
		row.strip:SetPoint("BOTTOMLEFT", row.clip, "BOTTOMLEFT", row.pad - s, row.below)
		local left, right = s > 0.5, s < row.max - 0.5
		if row.arrowL then
			row.arrowL:SetShown(left)
			row.arrowR:SetShown(right)
		end
		if row.fadeL then
			row.fadeL:SetShown(left)
			row.fadeR:SetShown(right)
		end
	end

	local Arrow = Shared("OnClick on a scroll row's arrows", function(self)
		local row = self.melloRow
		Scroll(row, row.scroll + self.melloDir * row.step)
	end, "script")

	local Wheel = Shared("OnMouseWheel on a scroll row", function(self, delta)
		local row = self.melloRow
		if row.max > 0 then
			Scroll(row, row.scroll - delta * row.wheel)
		end
	end, "script")

	-- (1.2.4, Oldschool -- the user's pick "b: parchment band" of MelloUI-BuildData/output/oldschool_edge_sketch, and
	-- "The parchment itself") a row on a picture (`paper`: the configurator's painting under the kit's look) bands a cut
	-- edge with that picture: its file and crop on its own points, so the band lies on it wherever the row goes, at
	-- `fade`, cut by the shade's soft end (Shade:EdgeMask) -- solid `cover` from the edge, fading over `edge` toward
	-- the text. No colour of its own, nothing to paint again; nil with no picture there yet
	local function PaperBand(row, inner, Shade)
		local paper = row.paper
		local file = paper.GetTexture and paper:GetTexture()
		if not file then
			return nil
		end
		local band = row.cover:CreateTexture(nil, "ARTWORK")
		band:SetTexture(file)
		band:SetTexCoord(paper:GetTexCoord())
		band:SetVertexColor(paper:GetVertexColor())
		band:SetAllPoints(paper)
		band:SetAlpha(row.fade)
		local mask = Shade:EdgeMask(row.cover, inner, row.coverW, row.edge)
		mask:SetPoint("TOP" .. inner, row.clip, "TOP" .. inner)
		mask:SetPoint("BOTTOM" .. inner, row.clip, "BOTTOM" .. inner)
		band:AddMaskTexture(mask)
		band:Hide()
		return band
	end

	-- a cut edge's parts, `side` -1 the left, 1 the right: its band (the dark shade, or the picture the row lies on;
	-- none without `fade`) and its arrow, hidden
	local function Edge(row, side)
		local inner = side < 0 and "LEFT" or "RIGHT"
		local band
		local Shade = rawget(MelloUI, "Shade")
		if row.fade and row.paper and Shade and Shade.EdgeMask then
			band = PaperBand(row, inner, Shade)
		elseif row.fade and Shade and Shade.Band then
			-- (the band's full middle the clip's edge, `cover` wide: the arrow on it)
			local spot = row.cover:CreateTexture(nil, "ARTWORK")
			spot:SetPoint("TOP" .. inner, row.clip, "TOP" .. inner)
			spot:SetPoint("BOTTOM" .. inner, row.clip, "BOTTOM" .. inner)
			spot:SetWidth(row.coverW)
			band = Shade:Band(row.cover, { colour = "mainWindow", alpha = row.fade, feather = row.edge, layer = "ARTWORK",
				region = spot })
			if band then
				band:SetShown(false)
			end
		end
		local arrow = W.RoundIcon(row.cover, row.arrow, W.IconPath("btn_arrow"))
		arrow.icon:SetRotation(side < 0 and math.pi / 2 or -math.pi / 2)   -- (the set's arrow points up)
		arrow:SetPoint(inner, row.clip, inner, -side * (row.pad + 2), row.arrowY)
		arrow.melloRow, arrow.melloDir = row, side
		Perf.SetScript(arrow, "OnClick", Arrow)
		arrow:Hide()
		return band, arrow
	end

	local function RowShow(row, frame)
		row.shown = frame
		local x = row.xs[frame]
		if not (x and row.max > 0) then
			return
		end
		local clear, s, w = row.coverW - row.pad + row.edge, row.scroll, Num(frame:GetWidth()) or 0
		if x + w + clear > s + row.room then
			s = x + w + clear - row.room
		end
		if x - clear < s then
			s = x - clear
		end
		Scroll(row, s)
	end

	local function RowLay(row, frames, room, high, gap)
		gap = Num(gap) or 0
		row.room = room
		row.clip:SetSize(room + 2 * row.pad, row.below + high + row.above)
		local x, n = 0, #frames
		for i, f in ipairs(frames) do
			f:ClearAllPoints()
			f:SetPoint("BOTTOMLEFT", row.strip, "BOTTOMLEFT", x, 0)
			row.xs[f] = x
			x = x + (Num(f:GetWidth()) or 0) + (i < n and gap or 0)
		end
		row.strip:SetSize(math.max(1, x), high)
		row.max = math.max(0, x - room)
		row.clip:EnableMouseWheel(row.max > 0)
		if row.max > 0 and not row.arrowR then
			row.fadeL, row.arrowL = Edge(row, -1)
			row.fadeR, row.arrowR = Edge(row, 1)
		end
		Scroll(row, row.scroll)
		if row.shown then
			RowShow(row, row.shown)
		end
		return x
	end

	function W.ScrollRow(parent, spec)
		spec = type(spec) == "table" and spec or NO_OPTS
		local clip = CreateFrame("Frame", nil, parent)
		if clip.SetClipsChildren then
			clip:SetClipsChildren(true)
		end
		local strip = CreateFrame("Frame", nil, clip)
		strip:SetSize(1, 1)
		local cover = CreateFrame("Frame", nil, clip)
		cover:SetAllPoints(clip)
		cover:SetFrameLevel(strip:GetFrameLevel() + 10)   -- (over the frames)
		local row = { clip = clip, strip = strip, cover = cover, scroll = 0, max = 0, room = 0, xs = {} }
		for key, value in pairs(ROW) do
			local v = spec[key]
			if v == nil then
				v = value
			end
			row[key == "cover" and "coverW" or key] = v
		end
		row.Lay, row.Show = RowLay, RowShow
		clip.melloRow = row
		clip:EnableMouseWheel(false)
		Perf.SetScript(clip, "OnMouseWheel", Wheel)
		return row
	end
end

--------------------------------------------------------------------------------
-- Field (0.20.1; the user's pick E, 2026-10-10: "search bar in spell book, we need to define how the search box is
-- going to look like, and i want the same look on the whole UI, that goes for the Editbox in chat and in whisper
-- window aswell"; the sheet: MelloUI-BuildData/output/editbox_sketch): THE look of every text field -- the game's
-- search boxes and the chat's edit box (the kit's flat "edit": W.FlatOver), MelloUI's own (W.FlatField: the
-- configurator's search and name boxes, the bag window's search, the whisper windows' answer), the number and slider
-- value boxes; the dropdowns' boxes too, the game's and MelloUI's own (0.20.1, the user's pick A of
-- MelloUI-BuildData/output/dropdown_sketch: the flat box "too modern"), lit while hovered. The border library's Stone rail at its light weight on the field (Kit:NewBorder, style "rpg"), its own
-- dark trough under the text; the library's glow while the field has the keyboard, its darken disabled. The rail is
-- made at the field's first show (a field never seen makes none). Without the library (a world without the kit),
-- the `innerPanel` fill in a 1 px edge it stands in for (`trim` with the keyboard).
--   W.Field(host, rect) -> field   its parts regions of `host`, on `rect` (host itself, or a region of host's)
--   field:SetState(focus, disabled, alpha)   field:SetShown(on)
--------------------------------------------------------------------------------
do
	local STYLE, WEIGHT = "rpg", "light"
	local Field = {}
	Field.__index = Field
	local fieldOf = setmetatable({}, weakKeys)   -- [host] = its field (one per host)

	-- the Stone rail, made at the first lay that shows it (false: no library here)
	local function Stone(f)
		if f.border == nil then
			local Kit = KitNow()
			local b = false
			if Kit and Kit.NewBorder and type(Kit.BorderStyles) == "table" and Kit.BorderStyles[STYLE] then
				b = Kit:NewBorder({ rect = f.rect, owner = f.host, layer = "BORDER", sub = 2, place = "on" })
				if not b:Lay(STYLE, WEIGHT) then
					b = false
				end
			end
			f.border = b
		end
		return f.border
	end

	local FieldSeen   -- (its OnShow: below)

	-- (1.2.4, the Default skin: MelloUI.Skin) the game's own text box on the rect, InputBoxTemplate's three pieces at
	-- its height (20); made at its first need
	local GAME_H = 20

	local function GameBox(f, game)
		if game and not f.game then
			local ART = MelloUI.Skin.ART
			local l = f.host:CreateTexture(nil, "BACKGROUND", nil, 2)
			l:SetAtlas(ART.inputLeft)
			l:SetSize(8, GAME_H)
			l:SetPoint("LEFT", f.rect, "LEFT", 0, 0)
			local r = f.host:CreateTexture(nil, "BACKGROUND", nil, 2)
			r:SetAtlas(ART.inputRight)
			r:SetSize(8, GAME_H)
			r:SetPoint("RIGHT", f.rect, "RIGHT", 0, 0)
			local m = f.host:CreateTexture(nil, "BACKGROUND", nil, 2)
			m:SetAtlas(ART.inputMiddle)
			m:SetPoint("TOPLEFT", l, "TOPRIGHT", 0, 0)
			m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT", 0, 0)
			f.game = { l, m, r }
		end
		if f.game then
			for i = 1, 3 do
				f.game[i]:SetShown(game)
				f.game[i]:SetAlpha(f.alpha)
			end
		end
	end

	local function Lay(f)
		-- (the rail made only while the field is on the screen: a field seen while it was hidden (SetShown(false))
		-- and shown again while its host is off the screen makes it at its next show, drawing nothing till then; the
		-- test world's hard3/ownlook G3 counted one such dropdown's 18)
		local want = f.seen and f.shown
		local Skin = rawget(MelloUI, "Skin")
		local game = Skin and Skin.IsDefault() or false
		local stone = false
		f.pending = nil
		want = want and not game   -- (the game's box in the rail's place: no rail made)
		if want and f.border == nil and not f.host:IsVisible() then
			f.pending = true
			if not f.hooked then
				f.hooked = true
				Perf.HookScript(f.host, "OnShow", FieldSeen)
			end
		elseif want then
			stone = Stone(f)
		end
		if f.border then
			f.border:SetShown(stone and true or false)
			if stone then
				f.border:SetLit(f.focus, nil, f.disabled)
			end
		end
		GameBox(f, f.shown and game)
		local plain = f.shown and not game and not stone and not f.pending and f.seen and true or false
		if plain and not f.fill then
			local fill = f.host:CreateTexture(nil, "BACKGROUND", nil, 2)
			fill:SetAllPoints(f.rect)
			f.fill, f.edges = fill, Edges(f.host, "border", "BORDER", f.rect)
		end
		if f.fill then
			f.fill:SetShown(plain)
			for i = 1, 4 do
				f.edges[i]:SetShown(plain)
			end
			if plain then
				W.Paint(f.fill, "innerPanel", "fill", f.alpha)
				for i = 1, 4 do
					W.Paint(f.edges[i], f.focus and "trim" or "border", "fill", f.alpha)
				end
			end
		end
	end

	function Field:SetState(focus, disabled, alpha)
		self.focus, self.disabled, self.alpha = focus and true or false, disabled and true or false, alpha or 1
		Lay(self)
	end

	function Field:SetShown(on)
		self.shown = on and true or false
		Lay(self)
	end

	FieldSeen = Shared("OnShow on a text field's frame (the field's first lay; a rail waiting for the screen)", function(host)
		local f = fieldOf[host]
		if f and (not f.seen or f.pending) then
			f.seen = true
			Lay(f)
		end
	end, "script")

	function W.Field(host, rect)
		local f = setmetatable({ host = host, rect = rect or host, shown = true, focus = false, disabled = false,
			alpha = 1 }, Field)
		fieldOf[host] = f
		if host:IsVisible() then
			f.seen = true
		else
			f.hooked = true
			Perf.HookScript(host, "OnShow", FieldSeen)
		end
		local Skin = rawget(MelloUI, "Skin")
		if Skin then
			Skin.Follow(f, Lay)
		else
			Lay(f)
		end
		return f
	end
end

--------------------------------------------------------------------------------
-- The search box (0.15.0, flat: user, 2026-09-29 "all flat"; it was the
-- kit's S1 in the kit's look): the game's
-- search box (SearchBoxTemplate), made by the caller (the configurator's
-- side list), in THE text field's look (W.Field, 0.20.1: the Stone rail and
-- its trough, lit while it has the keyboard) -- its Left / Middle / Right
-- art hidden -- over the art's own span (from SEARCH_LEFT px left of the
-- box: the magnifying glass inside it). The prompt in `mutedText` (the
-- palette's hint colour); the glass `mutedText` while the box is idle and
-- `text` in use (the game's own two shades of it, by key); the clear
-- button's cross in `text`. What is typed is the caller's to colour (the
-- configurator's is `text`). Its rep is false (MelloUI.Kept.repOf), so the kit's sweep
-- (Kit:SkinSearchBox) passes it by. A plain text field made by hand from
-- InputBoxTemplate (the Profiles page's name, Help's links: review,
-- 2026-09-29, "all flat") takes the same look: its Left / Middle / Right are
-- the same art at the same span, and it has no glass, prompt or cross.
--   W.FlatField(box) -> box   once per box (a search box or a plain field)
--   W.FlatSearch(box)         the same (the configurator's search box)
--   box.melloField            its W.Field
--------------------------------------------------------------------------------

do
	local SEARCH_LEFT = 5   -- the game's art reaches this far left of the box
	local FIELD_PAD = 3     -- (0.20.1) a plain field's text this far in from its rail, in MelloUI's look (no glass)
	local SEARCH_ART = { "Left", "Middle", "Right" }

	-- the glass in use (the keyboard in the box, or a text in it) or idle:
	-- after the game's own scripts, which tint it themselves
	local function Glass(box)
		local glass = box.searchIcon
		if glass then
			local text = box:GetText()
			local used = box:HasFocus() or (text and text ~= "")
			W.Paint(glass, used and "text" or "mutedText", "vertex")
		end
	end

	-- the field's look, laid once: the template's own border (Left / Middle /
	-- Right) unseen, a plain field's text padded off the rail, the prompt and
	-- the clear button's cross painted
	local SearchFocus
	local function FieldLook(box)
		for _, key in ipairs(SEARCH_ART) do
			local art = rawget(box, key)
			if art then
				art:SetAlpha(0)
			end
		end
		local pad = rawget(box, "melloInsets")
		if pad then
			box:SetTextInsets(pad[1] + FIELD_PAD, pad[2] + FIELD_PAD, pad[3], pad[4])
		end
		local clear = box.clearButton
		if box.Instructions then
			W.Paint(box.Instructions, "mutedText", "text")
		end
		if clear and clear.Icon then
			W.Paint(clear.Icon, "text", "vertex")
		end
		SearchFocus(box)
	end

	SearchFocus = Shared("OnEditFocusGained / OnEditFocusLost on MelloUI's text fields", function(box)
		box.melloField:SetState(box:HasFocus())
		Glass(box)
	end, "script")

	local SearchText = Shared("OnTextChanged on MelloUI's search boxes (the glass)", function(box)
		Glass(box)
	end, "script")

	-- (2026-11-08; the user, a shot of the Restock List's search: "why are some search boxes and input boxes texts
	-- centered? they need to behave normally") a field's text from its left edge: MelloUI's fonts are made at runtime
	-- (Modules/Fonts.lua's families), and a font made at runtime brings a CENTER of its own where the game's XML fonts
	-- leave it unset -- an edit box takes it over (the chat's boxes, 2026-10-03: Fonts' Family.EditBoxesLeft). Set as
	-- the field is made and again after every pass over the fonts (the bus 'fonts'), as the chat's are; a box meant
	-- centred (a slider's value, W.NumberBox) is never a flat field
	local flatFields = setmetatable({}, weakKeys)
	local fieldsHeard = false
	local function FieldsLeft()
		for box in pairs(flatFields) do
			pcall(box.SetJustifyH, box, "LEFT")
		end
	end

	function W.FlatField(box)
		if not box or box.melloField then
			return box
		end
		flatFields[box] = true
		pcall(box.SetJustifyH, box, "LEFT")
		if not fieldsHeard then
			fieldsHeard = true
			MelloUI:On("fonts", FieldsLeft, "W.FlatField")
		end
		KitRep(box, false)   -- (the kit's sweep passes it by: no S1)
		local span = box:CreateTexture(nil, "BACKGROUND")   -- (the field's span: an empty region)
		span:SetPoint("TOPLEFT", box, "TOPLEFT", -SEARCH_LEFT, 0)
		span:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
		box.melloField = W.Field(box, span)
		if not box.searchIcon and box.GetTextInsets then
			local l, r, t, b = box:GetTextInsets()   -- (the game's; FieldLook pads them in MelloUI's look)
			box.melloInsets = { l or 0, r or 0, t or 0, b or 0 }
		end
		Perf.HookScript(box, "OnEditFocusGained", SearchFocus)
		Perf.HookScript(box, "OnEditFocusLost", SearchFocus)
		if box.searchIcon then
			Perf.HookScript(box, "OnTextChanged", SearchText)
		end
		FieldLook(box)
		return box
	end
	W.FlatSearch = W.FlatField
end

--------------------------------------------------------------------------------
-- FlatOver (0.19.1; the user, 2026-10-04: "you made new icons for the
-- checkboxes, dropdowns, sliders etc ... now we have a lot of different
-- looking icons which serve the same function ... from now on only use the
-- same style as we have in the Configurator"): the controls above laid over
-- the GAME's own in every window the kit dresses -- the kit's control pieces
-- (B1's red plate, D1, B6, S1 / N1, TB6, the slider's and the scroll bar's
-- pieces) gave way to these. One look: the same keys and sizes as the
-- switch, the dropdown, the button, the tab, the search box and the list's
-- scroll bar. 0.19.9 (the user's picks 2026-10-08, "0A 1A 2B 3B"): the close
-- button, the check box, the arrows, the + / - and the settings cog are the
-- NewUI2 kit pieces (KC, above: one texture on the holder's middle, its
-- state's piece; under KC.SMALL an arrow or a + / - is its glyph alone), a
-- dropdown's caret the arrow's glyph; the other kinds keep their flat plate.
-- The parts are regions of `holder` (the kit's holder frame on the control's
-- rect: Modules/Kit.lua's "flat" kind, which fades the game's art and
-- follows the control's state as its rims do; or a button of MelloUI's own)
-- and are painted by FlatState.
--   W.FlatOver(holder, kind, opts) -> parts
--     kind: "button" (an icon button's plate, under its glyph: 0.19.9 the
--     NewUI2 icon plate), "check", "dropdown", "edit", "close", "arrow" (opts.dir
--     "up" / "down" / "left" / "right"), "titlearrow" (0.20.1: a title bar's
--     maximize / minimize on the close button's steel plate; opts.dir "up" / "down"), "plus", "minus", "cog" (a settings
--     button: the cog plate in place of the game's gear), "tab" (at rest),
--     "tabActive" (the open one), "track" (a scroll bar's), "thumb" (its
--     handle), "slider" (a slider's track), "knob" (its handle); opts.left:
--     the fill reaching that far left of the rect (an edit box's art: the
--     search glass inside it); opts.body = false: a plate's edge alone;
--     opts.glyph: a + / - / arrow as its bare glyph at any size (no plate);
--     opts.area (0.25.0): the look area a kit kind follows -- the set's icon, or Oldschool's painted piece while that
--     area is painted (KC.Painted); the configurator's ("config") when none
--   W.FlatState(parts, hover, pressed, checked, disabled, focus)
--   W.FlatDir(parts, dir)   an arrow turned ("up" / "down" / "left" / "right")
--   W.FlatKind(parts, kind) a + become a - and back (the Quest Tracker's folds)
--   W.FlatShown(parts, on)  every part shown or hidden (a look switched)
--   parts.piece: a kit kind's texture; parts.partial: a check ticked for some
--   characters only (its plate greyed)
--------------------------------------------------------------------------------

do
	local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
	local THIN = 4                       -- a scroll bar's track and handle, a slider's track: this thick
	local KNOB = 14                      -- the slider's knob (its ring 1 px round it)
	local CARET_AT = -12                 -- a dropdown's caret (the own dropdown's CARET square): its centre from the right
	local KITTED = { check = true, close = true, arrow = true, titlearrow = true, plus = true, minus = true, cog = true, button = true }
	local PARTS = { "piece", "fill", "caret", "ring", "disc" }

	-- a kit kind's piece for its last state, at the holder's size
	local function LayPiece(p)
		local w, h = p.holder:GetSize()
		KC.Lay(p.piece, w, h, p.kind, p.dir, p.state or KC.State(p.kind), p.alpha, p.glyph)
		if p.kind == "check" then
			p.piece:SetDesaturated(p.partial and p.checked and true or false)
		end
	end
	local FlatSized = Shared("OnSizeChanged on a kit flat control's holder", function(holder)
		local p = holder.melloFlat
		if p then
			LayPiece(p)
		end
	end, "script")

	local function Plate(holder, p, left)
		local fill = holder:CreateTexture(nil, "BACKGROUND", nil, 2)
		fill:SetPoint("TOPLEFT", holder, "TOPLEFT", -(left or 0), 0)
		fill:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
		p.fill, p.edges = fill, Edges(holder, "border", "BORDER", fill)
	end

	function W.FlatOver(holder, kind, opts)
		opts = opts or NO_OPTS
		local p = { kind = kind, holder = holder }
		if KITTED[kind] then
			-- (an icon button's plate under the game's glyph or the caller's: BACKGROUND)
			local tex = holder:CreateTexture(nil, kind == "button" and "BACKGROUND" or "ARTWORK", nil, 2)
			tex.melloOn = holder
			tex.melloArea = opts.area   -- (0.25.0: the look area it follows, KC.Painted; the configurator's when none)
			p.piece, p.dir = tex, (kind == "arrow" and (opts.dir or "down")) or (kind == "titlearrow" and (opts.dir or "up")) or nil
			p.glyph = opts.glyph   -- (a + / - / arrow as its bare glyph at any size: the rule's `glyph`)
			holder.melloFlat = p
			Perf.HookScript(holder, "OnSizeChanged", FlatSized)
			LayPiece(p)
		elseif kind == "track" or kind == "thumb" then
			local bar = holder:CreateTexture(nil, "ARTWORK", nil, 1)
			bar:SetPoint("TOP", holder, "TOP", 0, 0)
			bar:SetPoint("BOTTOM", holder, "BOTTOM", 0, 0)
			bar:SetWidth(THIN)
			p.fill = bar
		elseif kind == "slider" then
			local track = holder:CreateTexture(nil, "BACKGROUND", nil, 2)
			track:SetPoint("LEFT", holder, "LEFT", 0, 0)
			track:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
			track:SetHeight(THIN)
			p.fill, p.edges = track, Edges(holder, "border", "BORDER", track)
		elseif kind == "knob" then
			local ring = holder:CreateTexture(nil, "ARTWORK", nil, 1)
			ring:SetTexture(ROUND)
			ring:SetSize(KNOB + 2, KNOB + 2)
			ring:SetPoint("CENTER", holder, "CENTER", 0, 0)
			local disc = holder:CreateTexture(nil, "ARTWORK", nil, 2)
			disc:SetTexture(ROUND)
			disc:SetSize(KNOB, KNOB)
			disc:SetPoint("CENTER", holder, "CENTER", 0, 0)
			p.ring, p.disc = ring, disc
		elseif kind == "edit" then
			-- (0.20.1) THE text field (W.Field); `left`: over the art's span left of the rect (a search box's glass
			-- inside it)
			local rect = holder
			if opts.left and opts.left ~= 0 then
				rect = holder:CreateTexture(nil, "BACKGROUND")
				rect:SetPoint("TOPLEFT", holder, "TOPLEFT", -opts.left, 0)
				rect:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
			end
			p.field = W.Field(holder, rect)
		elseif kind == "dropdown" then
			-- (0.20.1, the user's pick A of output/dropdown_sketch: "too modern") THE text field (W.Field), lit while
			-- hovered, the kit's gold caret at its right
			p.field = W.Field(holder, holder)
			local caret = holder:CreateTexture(nil, "ARTWORK", nil, 2)
			caret.melloOn, caret.melloPoint, caret.melloX = holder, "RIGHT", CARET_AT
			p.caret = caret
		else
			-- a plate: the button's, a tab's
			Plate(holder, p, opts.left)
		end
		if opts.body == false and p.edges then
			-- the edge alone (a frame round something: the calendar's today)
			p.fill:Hide()
			p.noBody = true
		end
		return p
	end

	-- an arrow turned (a flat arrow that follows the rotation the game gives
	-- its art: Kit's `rotates`)
	function W.FlatDir(p, dir)
		if not (p and p.piece and p.dir) or p.dir == dir then
			return
		end
		p.dir = dir
		LayPiece(p)
	end

	-- a + become a - and back
	function W.FlatKind(p, kind)
		if not (p and p.piece) or p.kind == kind or not KITTED[kind] then
			return
		end
		p.kind = kind
		LayPiece(p)
	end

	function W.FlatShown(p, on)
		for _, key in ipairs(PARTS) do
			local region = p[key]
			if region and not (key == "fill" and p.noBody) then
				region:SetShown(on)
			end
		end
		if p.edges then
			for i = 1, #p.edges do
				p.edges[i]:SetShown(on)
			end
		end
		if p.field then
			p.field:SetShown(on)
		end
	end

	local function PaintAll(list, key, how, alpha)
		if list then
			for i = 1, #list do
				W.Paint(list[i], key, how, alpha)
			end
		end
	end

	function W.FlatState(p, hover, pressed, checked, disabled, focus)
		local kind = p.kind
		local alpha = disabled and FLAT_OFF or 1
		local lit = (hover or pressed) and not disabled
		if p.piece then
			p.state, p.alpha, p.checked = KC.State(kind, hover, pressed, checked, disabled), alpha, checked
			LayPiece(p)
		elseif kind == "track" then
			W.Paint(p.fill, "border", "fill", 1)
		elseif kind == "thumb" then
			W.Paint(p.fill, lit and "selectedTrim" or "trim", "fill", alpha)
		elseif kind == "slider" then
			W.Paint(p.fill, "innerPanel", "fill", alpha)
			PaintAll(p.edges, "border", "fill", alpha)
		elseif kind == "knob" then
			W.Paint(p.ring, "innerPanel", "vertex", alpha)
			W.Paint(p.disc, lit and "text" or "selectedTrim", "vertex", alpha)
		elseif kind == "tabActive" then
			W.Paint(p.fill, "selectedTab", "fill", 1)
			PaintAll(p.edges, "selectedTrim", "fill", 1)
		elseif kind == "edit" then
			p.field:SetState(focus, disabled, alpha)
		elseif kind == "dropdown" then
			p.field:SetState(lit, disabled, alpha)
			KC.Lay(p.caret, CARET, CARET, "arrow", "down", lit and "hover" or "normal", alpha, true)
		else
			-- a tab's plate at rest
			W.Paint(p.fill, lit and "hover" or "raisedPanel", "fill", alpha)
			PaintAll(p.edges, "border", "fill", alpha)
		end
	end
end

--------------------------------------------------------------------------------
-- IconBox: a framed icon -- the client's action button bevel around a
-- rounded icon, grey at rest, gold when selected, the text colour while
-- hovered; with the kit, the rim every window's buttons wear (UI
-- Modifications' Button Border, swapped live with it, in the Kit Colours
-- look -- user, 2026-09-24) over the icon in its square opening.
--   box:SetIcon(texture)   box:SetSelected(on)
--   box:SetHovered(on)     box:SetOn(on)         box:SetGlow(on)
--   box:SetKit(on)         the icon laid again for the look (a box made with
--                          a shell follows its switches)
--------------------------------------------------------------------------------

do   -- (the IconBox's parts in a block: the main chunk is near Lua's 200 locals)
	-- MelloUI's own logo art is shown whole; a game icon loses its baked border
	local NO_CROP = { [TEXTURE_PATH .. "LogoIcon.tga"] = true, [TEXTURE_PATH .. "LogoFull.tga"] = true }

	local maskOf = setmetatable({}, weakKeys)   -- [box] = its icon's mask (no field: a box's parts keep their names)

	-- (1.2.4, the Default skin: MelloUI.Skin) the box in the game's look (`game`; nil: as it was): every picture cut
	-- round (IconBox_SetKit's mask), a framed one in the game's gold ring in the frame's place (the ring's opening the box,
	-- as the round buttons'), a bare one alone -- the sketch the user approved; the ring made at its first need
	local IconBoxGame
	do
		local OPENING = 0.775   -- (the gold ring's opening: W.RoundIcon's)
		IconBoxGame = function(self, game)
			if game ~= nil then
				self.gameLaid = game or nil
			end
			local ringed = self.gameLaid and not self.bare
			if ringed and not self.gameRing then
				local ring = self:CreateTexture(nil, "OVERLAY")
				ring:SetAtlas(MelloUI.Skin.ART.ring)
				ring:SetSize(self.size / OPENING, self.size / OPENING)
				ring:SetPoint("CENTER", self, "CENTER", 0, 0)
				self.gameRing = ring
			end
			if self.gameRing then
				self.gameRing:SetShown(ringed and true or false)
			end
			self.frame:SetShown(not self.gameLaid and not self.bare)
		end
	end

	local IconBox_SetIcon
	do
		-- (2026-10-20, the user's pick A: "bare") a picture of MelloUI's icon set is shown whole and alone: no bevel, no
		-- rounded mask (with the kit, the rim still round it, as everywhere the set is)
		local SET_DIR = TEXTURE_PATH .. "Icons\\"

		local function Bare(self, bare)
			self.bare = bare or nil
			IconBoxGame(self)
			local mask = maskOf[self]
			if self.gameLaid then
				return   -- (the Default skin: every picture cut round, its mask kept)
			end
			if bare and self.masked and mask then
				self.icon:RemoveMaskTexture(mask)
				self.masked = false
			elseif not bare and not self.masked and not self.kitLaid and mask then
				self.icon:AddMaskTexture(mask)
				self.masked = true
			end
		end

		IconBox_SetIcon = function(self, texture)
			local bare = type(texture) == "string" and texture:sub(1, #SET_DIR) == SET_DIR
			if (self.bare or false) ~= bare then
				Bare(self, bare)
			end
			-- (2026-10-21: through MelloUI.Icons, the copy for its size; a game icon cropped of its baked border)
			local c = (not bare and texture ~= nil and not NO_CROP[texture]) and 0.06 or 0
			self.cropped = c > 0
			MelloUI.Icons.Set(self.icon, texture, nil, c, 1 - c, c, 1 - c)
		end
	end

	local function IconBox_SetSelected(self, selected)
		self.selected = selected and true or false
		W.Paint(self.frame, self.selected and "selectedTrim" or "mutedText", "vertex", 1)
		if self.rim and self.rim.Update then
			self.rim:Update()
		end
	end

	local function IconBox_SetHovered(self, hovered)
		if hovered then
			W.Paint(self.frame, "text", "vertex", 1)
		else
			self:SetSelected(self.selected)
		end
		if self.rim and self.rim.Update then
			self.rim.hover = hovered and true or nil
			self.rim:Update()
		end
	end

	local function IconBox_SetOn(self, on)
		self.icon:SetDesaturated(not on)
		self.icon:SetAlpha(on and 1 or 0.45)
	end

	-- the glow's size: from the rim with the kit (centred on the box, the rim's
	-- centre), so the light is symmetric around the iron (user, 2026-09-22)
	local function GlowSize(self)
		local rim = self.kitLaid and self.size * RIM_GROW or self.size
		return rim * 1.45
	end

	-- a pulsing gold glow over the rim (the action button's proc glow, additive
	-- light on top of the iron -- user, 2026-09-22), for an important module;
	-- under Reduce Motion a still glow at full strength (Anim:Pulse)
	local function IconBox_SetGlow(self, on)
		if on and not self.glow then
			local glow = self:CreateTexture(nil, "OVERLAY", nil, 7)
			-- (0.25.0, the visual sweep: the set's bright gold frame, added as light; the game's 64 px glow was stretched
			-- round the box)
			W.FrameArt(glow, "active", 6)
			glow:SetBlendMode("ADD")
			local size = GlowSize(self)
			glow:SetSize(size, size)
			glow:SetPoint("CENTER", self, "CENTER", 0, 0)
			self.glow = glow
			self.glowAnim = MelloUI.Anim:Pulse(glow, 0.45, 1, 0.9)
		elseif self.glow then
			self.glow:SetShown(on and true or false)
			if on then
				MelloUI.Anim:Pulse(self.glow)   -- its group, played again
			else
				MelloUI.Anim:StopGroup(self.glowAnim)   -- not played again when Reduce Motion goes off
			end
		end
	end

	-- The icon for the look: with the kit at 0.9 of the box, centred, until the
	-- rim fits it into its square opening (no rounded mask, as on the action
	-- bars); without it the whole box with the bevel's rounded corners. Same
	-- construction as an action button (a 45 px icon, the 46 x 45 bevel on its
	-- top left corner, the corner mask at its native size centred on the icon),
	-- scaled to this size.

	local function IconBox_SetKit(self, on)
		on = on and true or false
		local Skin = rawget(MelloUI, "Skin")
		local game = not on and Skin and Skin.IsDefault() or false
		IconBoxGame(self, game)
		local size, icon, mask = self.size, self.icon, maskOf[self]
		icon:ClearAllPoints()
		if on then
			icon:SetPoint("CENTER", self, "CENTER")
			icon:SetSize(size * 0.9, size * 0.9)
		else
			icon:SetAllPoints()
		end
		MelloUI.Icons.Fit(icon, on and size * 0.9 or size)
		mask:ClearAllPoints()
		if game then
			mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(icon)
		else
			mask:SetAtlas(ICON_MASK)
			local k = size / 45
			local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ICON_MASK)
			if info and info.width and info.height then
				local ik = on and k * 0.9 or k   -- the corner mask at the icon's size
				mask:SetSize(info.width * ik, info.height * ik)
				mask:SetPoint("CENTER", icon, "CENTER")
			else
				mask:SetAllPoints(icon)
			end
		end
		local want = not on and (game or not self.bare)
		if self.masked and not want then
			icon:RemoveMaskTexture(mask)
			self.masked = false
		elseif want and not self.masked then
			icon:AddMaskTexture(mask)
			self.masked = true
		end
		self.kitLaid = on
		if self.glow then
			local s = GlowSize(self)
			self.glow:SetSize(s, s)
		end
	end

	-- (1.2.4) the skin switched (MelloUI.Skin): the box laid again in the skin's look
	local function IconBox_Skin(self)
		IconBox_SetKit(self, self.kitLaid)
	end

	-- the rim, as regions of the BOX (the icon's own frame) so it draws over the
	-- icon; its rect the box grown by 10 % about its centre; its states the
	-- box's: pressed, hover, and selected (checked: the kit's active look,
	-- Kit:SetActive, round the rim)
	local function DressIconBox(K, box, skin)
		local size = box.size
		local rimRect = CreateFrame("Frame", nil, box)
		rimRect:SetPoint("CENTER", box, "CENTER")
		rimRect:SetSize(size * RIM_GROW, size * RIM_GROW)
		rimRect:EnableMouse(false)
		local rep = skin:Replace(box.frame, { as = K:ButtonRimRule(), rect = rimRect, button = box, icon = box.icon,
			checked = box.melloChecked })
		box.rim = rep and rep.object or nil
		if rep then
			if MelloUI.Kept then
				MelloUI.Kept.repOf[box] = rep
			end
			K:RegisterButtonRim(box)
		end
	end

	-- the boxes of each shell, laid again at its switches (one shared fn per
	-- shell: shell:OnKit keeps it once)
	local boxesOf = setmetatable({}, weakKeys)   -- [shell] = { [box] = true } (weak)
	local function Boxes_OnKit(shell, on)
		local set = boxesOf[shell]
		if set then
			for box in pairs(set) do
				box:SetKit(on)
			end
		end
	end

	function W.IconBox(parent, size, texture, skin)
		local box = CreateFrame("Frame", nil, parent)
		box:SetSize(size, size)
		box.size = size
		box.icon = box:CreateTexture(nil, "ARTWORK")
		box.frame = box:CreateTexture(nil, "OVERLAY")
		-- (0.25.0, the visual sweep: the set's own button frame round the box, sharp at its size -- the game's 46 px bevel
		-- was stretched to it)
		W.FrameArt(box.frame, "normal", math.max(3, math.floor(size / 12 + 0.5)))
		box.frame:SetAllPoints(box)
		local mask = box:CreateMaskTexture()
		mask:SetAtlas(ICON_MASK)
		maskOf[box] = mask
		box.SetIcon, box.SetSelected = IconBox_SetIcon, IconBox_SetSelected
		box.SetHovered, box.SetOn, box.SetGlow, box.SetKit = IconBox_SetHovered, IconBox_SetOn, IconBox_SetGlow, IconBox_SetKit
		box.masked = false
		box:SetKit(skin and skin.kit)
		if texture ~= nil then
			box:SetIcon(texture)
		end
		box.selected = false
		if skin then
			box.melloChecked = function() return box.selected end
			skin:Kit(DressIconBox, box, skin)
			if skin.OnKit then
				local set = boxesOf[skin]
				if not set then
					set = setmetatable({}, weakKeys)
					boxesOf[skin] = set
				end
				set[box] = true
				skin:OnKit(Boxes_OnKit)
			end
		end
		box:SetSelected(false)
		local Skin = rawget(MelloUI, "Skin")
		if Skin then
			Skin.followers[box] = IconBox_Skin
		end
		return box
	end
end

--------------------------------------------------------------------------------
-- HoverLight (0.18.4): a button's mouseover light in the shape of its border
-- (user, 2026-10-04: "every round border should have the round mouseover
-- glow, and every Square one should have square mouseover glow"): the game's
-- round light (its round minimap buttons') on a round border, its square one
-- (an action button's) on a square border. It is the button's highlight
-- texture: the engine shows it while the mouse is over the button, no script.
-- (A round border wore the square light cut by a circle until then: its
-- straight bright edges still showed.)
--   W.HoverLight(b, shape[, region[, out]]) -> the texture   shape "round" or
--       "square"; laid over region (default the button: the border's rect),
--       out units past each side; called again to switch the shape live (a
--       call that changes nothing sets nothing: a layout pass may call it)
--------------------------------------------------------------------------------

do
	-- (0.25.0, the user: the widget's "low resolution textures like the borders") the round light: the gold glow of
	-- MelloUI's icon set (Media/Textures/Icons/hover_glow), its band drawn out to hug the rim -- the light laid 0.175
	-- of the region's width past each side (1.35 x); it was the minimap's 32 px zoom-button light, stretched
	local LIGHT = {
		round = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\hover_glow",
		square = "Interface\\Buttons\\ButtonHilight-Square",
	}
	local ROUND_OUT = 0.175
	-- (1.2.4, the Default skin: MelloUI.Skin) the game's own round highlight (114 px, drawn smaller) on the region; each
	-- light kept with its asking, laid again at a switch
	local asked = setmetatable({}, weakKeys)   -- [b] = { shape, region, out }
	local listening = false

	function W.HoverLight(b, shape, region, out)
		shape = LIGHT[shape] and shape or "square"
		region, out = region or b, out or 0
		local a = asked[b]
		if a then
			a[1], a[2], a[3] = shape, region, out
		else
			asked[b] = { shape, region, out }
		end
		if not listening and MelloUI.On then
			listening = true
			MelloUI:On("skin", function()
				for lb, la in pairs(asked) do
					W.HoverLight(lb, la[1], la[2], la[3])
				end
			end, "the hover lights (skin)")
		end
		local Skin = rawget(MelloUI, "Skin")
		local game = shape == "round" and Skin and Skin.IsDefault() or false
		if shape == "round" and not game then
			local okW, rw = pcall(region.GetWidth, region)
			rw = okW and Num(rw) or nil
			if rw and rw > 0 then
				out = out + rw * ROUND_OUT
			end
		end
		local key = game and "game round" or shape
		if b.hoverShape ~= key then
			if game then
				b:SetHighlightTexture(LIGHT.round, "ADD")
				local t = b:GetHighlightTexture()
				if t then
					t:SetAtlas(MelloUI.Skin.ART.roundLight)
				end
			else
				b:SetHighlightTexture(LIGHT[shape], "ADD")
			end
			b.hoverShape, b.hoverRegion = key, nil   -- (laid again below)
		end
		local hl = b.GetHighlightTexture and b:GetHighlightTexture()
		if hl and (b.hoverRegion ~= region or b.hoverOut ~= out) then
			hl:ClearAllPoints()
			hl:SetPoint("TOPLEFT", region, "TOPLEFT", -out, out)
			hl:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", out, -out)
			b.hoverRegion, b.hoverOut = region, out
		end
		return hl
	end

	-- (1.2.4) W.RoundGlow(t) -> t: the round light on `t` (sized and blended by its caller) -- a state's light round
	-- a round button (a mode shown, a button lit): the set's glow, the game's round highlight under the Default skin
	-- (MelloUI.Skin), laid again at a switch. (2.1.0, qu-04; the user, 2026-10-31: the round lit glow over Oldschool's
	-- square buttons, "Fix it?" -- "Yes") the square light, as its hover light is, while the button `t` lights wears its
	-- look's square frame (W.RoundIcon's square mode, b.square: MelloUI.Icons.Square), laid again when the set switches
	-- (the bus's 'icons', after the round buttons')
	local glows = setmetatable({}, weakKeys)
	local glowsHeard = false

	local function RoundGlowLay(t)
		local b = t:GetParent()
		local Skin = rawget(MelloUI, "Skin")
		if type(b) == "table" and b.square then
			t:SetTexture(LIGHT.square)
			t:SetTexCoord(0, 1, 0, 1)
		elseif Skin and Skin.IsDefault() then
			t:SetAtlas(Skin.ART.roundLight)
		else
			t:SetTexture(LIGHT.round)
			t:SetTexCoord(0, 1, 0, 1)
		end
	end

	function W.RoundGlow(t)
		glows[t] = true
		if not glowsHeard and MelloUI.On then
			glowsHeard = true
			MelloUI:On("icons", function()
				for g in pairs(glows) do
					RoundGlowLay(g)
				end
			end, "the round lights (a look's own set)")
		end
		local Skin = rawget(MelloUI, "Skin")
		if Skin then
			Skin.Follow(t, RoundGlowLay)
		else
			RoundGlowLay(t)
		end
		return t
	end
end

--------------------------------------------------------------------------------
-- Icons (0.25.0; the user, 2026-10-19: the cartoon map-marker icons from their ChatGPT sheets, docs/plans/
-- icons-and-palette.md): MelloUI's own icon set, Media/Textures/Icons (Tools/make_icons.py), one path for all of it
--   W.IconPath(name) -> the file's path   W.Icon(tex, name[, units]) -> tex   (the whole picture, untinted)
--   W.IconMarkup(name, size) -> inline text markup, size x size of the line's units
-- (2026-10-21, the user: "all icons and its borders should always stay smooth") drawn through MelloUI.Icons
-- (Core/Icons.lua): the copy of the picture made for its size on screen, picked again when that changes
--------------------------------------------------------------------------------
do
	local DIR = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\"
	local Icons = MelloUI.Icons

	function W.IconPath(name)
		return Icons.Path(name)
	end

	-- (0.25.0) a flipbook strip of `frames` frames in a row (the set's fx_*) played smooth: `a` shows the frame `u`
	-- (0..1 of the run) is in, `b` the next one, each at its share of the step between them (u at a frame's middle:
	-- a alone), `alpha` over both -- the user, 2026-10-20: "it should be smooth" (8 frames stepped read as a low
	-- frame rate). Both textures the strip's, laid alike, ADD blend for light
	function W.Flipbook(a, b, u, frames, alpha)
		local x = math.max(0, math.min(1, u)) * frames - 0.5
		local f = math.max(0, math.min(frames - 1, math.floor(x)))
		local p = math.max(0, math.min(1, x - f))
		if x < 0 then
			p = 0
		end
		local g = math.min(frames - 1, f + 1)
		alpha = alpha or 1
		a:SetTexCoord(f / frames, (f + 1) / frames, 0, 1)
		a:SetAlpha(alpha * (1 - p))
		b:SetTexCoord(g / frames, (g + 1) / frames, 0, 1)
		b:SetAlpha(alpha * p)
	end

	-- (units: tex's width, when it is not sized yet or is sized after; Icons.Set reads it otherwise)
	function W.Icon(tex, name, units)
		Icons.Set(tex, name, units)
		tex:SetVertexColor(1, 1, 1, 1)
		return tex
	end

	function W.IconMarkup(name, size)
		return Icons.Markup(name, size)
	end

	-- (0.25.0) the set's square button frame, frame_<state> (normal, hover, pressed, active, empty, range), on `t` as
	-- a nine-slice: its 22 px corners kept, its band `band` UI px wide (5 when left out) -- the action buttons'
	-- MelloUI Frames and the icon boxes' (2026-10-20, the visual sweep: the game's bevel stretched there)
	local FRAME_CORNER = 22
	function W.FrameArt(t, state, band)
		t:SetTexture(DIR .. "frame_" .. state)
		-- (1.2.4, lk-11) a frame's art: under Dark Mode, at its area's brightness (the kit's shade)
		local Kit = KitNow()
		if Kit and Kit.RegisterTexture then
			Kit:RegisterTexture(t)
		end
		if t.SetTextureSliceMargins and t.SetTextureSliceMode and t.SetScale then
			t:SetTextureSliceMargins(FRAME_CORNER, FRAME_CORNER, FRAME_CORNER, FRAME_CORNER)
			t:SetTextureSliceMode(Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0)
			t:SetScale((band or 5) / FRAME_CORNER)
		end
	end

	-- (1.2.0; the user's pick A of BuildData/output/animation_previews/prd_looks.html, 2026-10-22: the Personal
	-- Display's bars, its cast bar and its shield column) MelloUI's gold rim round a bar, on `t` as a nine-slice:
	-- Textures/GildedRim (Tools/make_widget_art.py), white metal lit from above between dark casings, tinted the
	-- palette's selectedTrim; its rail `band` UI px deep. The caller lays `t` round what it frames, `band` past it on
	-- every side: the rail's inner casing on that edge, its inner corners rounded over the corners inside
	local RIM_ART = "Interface\\AddOns\\MelloUI\\Media\\Textures\\GildedRim"
	local RIM_CORNER, RIM_RAIL = 7, 4   -- the texture's corners and its rail (texels)

	local function GoldRim(t, band)
		t:SetTexture(RIM_ART)
		W.Paint(t, "selectedTrim", "vertex", 1)
		if t.SetTextureSliceMargins and t.SetTextureSliceMode and t.SetScale then
			t:SetTextureSliceMargins(RIM_CORNER, RIM_CORNER, RIM_CORNER, RIM_CORNER)
			t:SetTextureSliceMode(Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0)
			t:SetScale(band / RIM_RAIL)
		end
	end

	-- (1.2.4, the Default skin: MelloUI.Skin) a rim in the game's look: the tooltip's border on its rect in the gold's
	-- place (the gold drawn as nothing), shown and hidden with it; made at its first need, laid again at a switch. A
	-- rim whose owner lays the skin itself (`own`: MelloUI.Rims' window rims) is left to it
	local rimBand = setmetatable({}, weakKeys)     -- [t] = its rail's depth (every rim laid here)
	local rimBorder = setmetatable({}, weakKeys)   -- [t] = its game border (a frame of t's parent's)

	local RimShown = Shared("a rim's Show / Hide / SetShown (its game border with it)", function(t)
		local b = rimBorder[t]
		if b then
			b:SetShown(t:IsShown() and b.on)
		end
	end, "hook")

	local function RimLay(t)
		local band = rimBand[t]
		local Skin = rawget(MelloUI, "Skin")
		local game = Skin and Skin.IsDefault() or false
		local b = rimBorder[t]
		if game and not b then
			b = Skin.Border(t:GetParent(), "tooltip", t)
			rimBorder[t] = b
			hooksecurefunc(t, "Show", RimShown)
			hooksecurefunc(t, "Hide", RimShown)
			hooksecurefunc(t, "SetShown", RimShown)
		end
		if b then
			b.on = game
			b:SetShown(game and t:IsShown())
		end
		if game then
			t:SetTexture(nil)
		else
			GoldRim(t, band)
		end
	end

	function W.RimArt(t, band, own)
		local Skin = rawget(MelloUI, "Skin")
		if own or not Skin then
			GoldRim(t, band)
			return
		end
		rimBand[t] = band
		Skin.Follow(t, RimLay)
	end

	-- the kit to hand a round button's SetKit for a part in `area`: the kit while Oldschool's painted look dresses
	-- that area (its rims), else none -- MelloUI's own ring and the set's pictures (KC.Painted)
	function W.KitFor(area)
		return KC.Painted(area) and KitNow() or false
	end

	-- a path to one of the set's round buttons and pins (Services, the chat, the buttons, the pins, Route's goal):
	-- pictures with their own disc and ring, which a round button shows whole, with no rim of its own over them (a
	-- path in a look's own set's folder too, 1.2.4: Oldschool's, its square frames -- MelloUI.Icons)
	local RINGED = { "svc_", "track_", "pin_", "chat_", "chan_", "btn_", "goal_", "obj_" }
	function W.IconRinged(texture)
		if type(texture) ~= "string" or not texture:find("\\", 1, true) then
			return false
		end
		local name = MelloUI.Icons.NameOf(texture)
		if not name then
			return false
		end
		for i = 1, #RINGED do
			local p = RINGED[i]
			if name:sub(1, #p) == p then
				return true
			end
		end
		return false
	end
end

--------------------------------------------------------------------------------
-- RoundIcon (0.14.0, the Reminder widget; lifted from the Services bar's
-- round medallions, which can move onto it later): a round button, its icon
-- under a round mask inside a rim, with the round light (W.HoverLight) over
-- the whole rim. Two looks,
-- switched live with b:SetKit(Kit):
--   the kit's round rim (buttons/roundslot through Kit:Slot: every window's
--   Round Border, swapped with it, its hover and pressed art its own, Dark
--   Mode's shade), the icon fitted into its opening;
--   plain: (0.25.0) the gold ring of MelloUI's icon set round the icon (its
--   opening 0.775 of the ring; the minimap's 1x tracking rim until then, 31 : 21).
--   W.RoundIcon(parent, size, texture[, opts]) -> b   a Button, size x size
--       (the rim's outer size: the whole button), left and right clicks
--       registered, in the plain look. opts (read once): name; shade (a
--       shade area of Kit.shadeAreas: the kit rim wears the whole UI's
--       shade, a partner drawn by the button itself, so it fades and moves
--       with it, following the rim's own show and hide: none in the plain
--       look; made with the first kit look, at the shade's pace)
--   b:SetIcon(texture)   b:SetOn(on) (grey and dimmed while off)
--   b:SetCrop(share)     (2026-10-21) every picture cut by `share` of each
--                        side (nil: the usual, a game icon's border); the
--                        icon drawn from its copy for its size (MelloUI.Icons)
--   b:SetKit(Kit)        the kit's look while handed the kit (MelloUI.Kit, as
--                        a shell hands it to its dressing: this file never
--                        reaches for it), the plain look for nil or false; the
--                        kit's rim is made the first time. Set the button's
--                        own scripts BEFORE the first kit look: the kit's rim
--                        hooks them, and SetScript drops hooks. A button
--                        whose mouse its maker turned off (a picture in a
--                        rim) keeps it off through the rim's hooks
--   b.icon, b.mask, b.plainRim, b.kitRim (nil until the first kit look),
--   b.size, b.kitLaid (true while the kit's rim shows), b.square (1.2.4: one
--   of the set's round buttons drawn by a look's own set that frames them
--   square -- Oldschool's, MelloUI.Icons.Square -- shown whole in its own
--   frame: no rim, no kit rim, the square light; switched with the set)
-- It sets no script and holds no colour; nothing is made per call after.
--------------------------------------------------------------------------------

do
	-- (0.25.0, the user: "the Widget is still using low resolution textures like the borders etc") the plain rim:
	-- the gold ring of MelloUI's icon set at the button's size, the icon in its opening
	local PLAIN_RIM = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\ring_gold"
	local OPENING = 0.775
	local NONE = {}

	-- (0.25.0) one of the set's own round buttons or pins (W.IconRinged) is shown whole in the plain look: the
	-- button's size, unmasked, its own ring in place of the plain rim
	-- (2026-10-21) the icon from its copy for its size (MelloUI.Icons): one of the set's buttons whole, any other
	-- cropped to its art inside the mask
	local CROP = 0.06
	local function IconArt(b)
		local c = b.crop or (b.ringed and 0 or CROP)
		MelloUI.Icons.Set(b.icon, b.texture, nil, c, 1 - c, c, 1 - c)
	end

	-- a crop of its own for every picture it shows (a share of each side: a medallion cut inside its own ring), nil
	-- for the usual one
	local function SetCrop(b, crop)
		b.crop = crop
		IconArt(b)
	end

	-- (1.2.4, the Default skin) a game picture alone (b.alone, its spec): never bigger than its own size, on the game's
	-- chat button plate when it asks for one (`plate`, at the plate's own size), at the opening's size then
	local function AloneLay(b, icon, alone)
		local most = alone.plate and b.size * OPENING or b.size
		local w, h = most, most
		local info = alone.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(alone.atlas)
		local aw, ah = info and Num(info.width), info and Num(info.height)
		if aw and ah and aw > 0 and ah > 0 then
			local s = math.min(1, most / aw, most / ah)
			w, h = aw * s, ah * s
		end
		icon:SetSize(w, h)
		if alone.plate and not b.alonePlate then
			b.alonePlate = b:CreateTexture(nil, "BACKGROUND", nil, 2)
			b.alonePlate:SetPoint("CENTER", b, "CENTER", 0, 0)
		end
		if b.alonePlate then
			if alone.plate then
				b.alonePlate:SetAtlas(alone.plate, true)   -- (its own size)
			end
			b.alonePlate:SetShown(alone.plate and true or false)
		end
	end

	local function PlainLay(b)
		local icon, rim = b.icon, b.plainRim
		icon:ClearAllPoints()
		icon:SetPoint("CENTER", b, "CENTER", 0, 0)
		if b.disc then
			b.disc:SetShown(b.discOn and true or false)
		end
		if b.alonePlate and not b.alone then
			b.alonePlate:Hide()
		end
		if b.alone then
			AloneLay(b, icon, b.alone)
			rim:Hide()
			return
		end
		if b.ringed then
			icon:SetSize(b.size, b.size)
			rim:Hide()
			MelloUI.Icons.Fit(icon)
			return
		end
		local d = b.size * OPENING
		icon:SetSize(d, d)
		MelloUI.Icons.Fit(icon)
		rim:ClearAllPoints()
		rim:SetSize(b.size, b.size)
		MelloUI.Icons.Fit(rim, b.size)
		rim:SetPoint("CENTER", b, "CENTER", 0, 0)
		rim:Show()
	end

	-- (1.2.4, the Default skin: MelloUI.Skin) one of the set's round buttons with a game picture for it shows that picture in
	-- the plain rim (the game's gold ring then), masked; a picture with a clear ground (the map's service icons) on a
	-- dark disc, made at its first need
	local function GameDisc(b, on)
		if on and not b.disc then
			local disc = b:CreateTexture(nil, "BACKGROUND")
			disc:SetTexture(ROUND_MASK)
			W.Paint(disc, "mainWindow", "vertex", 0.9)
			disc:SetPoint("CENTER", b, "CENTER", 0, 0)
			disc:SetSize(b.size * OPENING, b.size * OPENING)
			b.disc = disc
		end
		b.discOn = on or nil
	end

	-- (1.2.4, the sketch the user approved) a game picture in the place of one of the set's own round buttons shows
	-- alone, as the set's showed alone; in the gold ring only one with a clear ground (`disc`) or a page's picture
	-- from RING_AT up. A game picture of the atlas's own shape unmasked; an icon file cut round
	local RING_AT = 36

	-- (1.2.4; the user's pick B, "B: painted") one of the set's round buttons drawn by a look's own set that frames
	-- its buttons square (Oldschool's: a square dark-iron frame, a red leather inset): shown whole at the button's size,
	-- no rim of MelloUI's or the kit's round it, the square light under the pointer. Laid again as it changes
	local function Square(b, square)
		square = square and true or false
		if square == (b.square or false) then
			return false
		end
		b.square = square or nil
		W.HoverLight(b, square and "square" or "round")
		return true
	end

	local function SetIcon(b, texture)
		local Skin = rawget(MelloUI, "Skin")
		local game = Skin and Skin.Icon(texture)
		local own = W.IconRinged(texture)
		local ringed = own and not game
		local alone = own and game and not game.disc and not (game.round and b.size >= RING_AT) and game or nil
		if Square(b, ringed and MelloUI.Icons.Square(texture)) and b.askedKit then
			b.texture = texture
			b:SetKit(b.askedKit)   -- (the kit's round rim off -- the frame is the picture's own -- or back on)
		end
		b.texture = texture
		local disc = game and game.disc or false
		if disc ~= (b.discOn or false) then
			GameDisc(b, disc)
			if not b.kitLaid then
				PlainLay(b)
			end
		end
		if ringed ~= (b.ringed or false) or alone ~= b.alone then
			b.ringed, b.alone = ringed or nil, alone
			local off = (ringed or (alone and alone.atlas)) and true or false
			if off ~= (b.maskOff or false) then
				b.maskOff = off or nil
				if off then
					b.icon:RemoveMaskTexture(b.mask)
				else
					b.icon:AddMaskTexture(b.mask)
				end
			end
			if not b.kitLaid then
				PlainLay(b)
			end
		end
		IconArt(b)
	end

	local function SetOn(b, on)
		b.icon:SetDesaturated(not on)
		b.icon:SetAlpha(on and 1 or 0.45)
	end


	-- the kit rim's shade partner (opts.shade): the rim drawn at the
	-- button's size, so the partner's scale is that against its piece's
	-- painted width; an unknown area is reported, and the button goes without
	local function ShadeRim(b, rim, Kit)
		local ok, el = pcall(Kit.ShadeElement, Kit, b, b.shadeArea, { host = b })
		if not ok then
			geterrorhandler()(el)
			return
		end
		local name = MelloUI.Kept and MelloUI.Kept.pieceNameOf[rim]
		local pw = Kit.Size and name and Kit:Size(name, 1)
		pw = Secret(pw) and nil or tonumber(pw)
		el:Add(rim, { scale = (pw and pw > 0) and b.size / pw or nil })
	end

	local function SetKit(b, Kit)
		-- (1.2.4) the kit's rim never under the Default skin (MelloUI.Skin): the plain rim, the game's gold ring there;
		-- the look asked kept for a switch
		b.askedKit = Kit or false
		local Skin = rawget(MelloUI, "Skin")
		local on = (type(Kit) == "table" and Kit.Slot and Kit.SlotPlaceIcon) and not (Skin and Skin.IsDefault())
			and not b.square and true or false
		if on then
			local rim = b.kitRim
			if not rim then
				-- (0.25.0) the mouse as the button's maker left it: the rim's
				-- hooks (Kit:Slot's OnEnter, OnMouseDown ...) turn a button's
				-- mouse on, and the kit keeps that for a button (its hover is
				-- the point). A RoundIcon made click-through (a picture in a
				-- rim: a shell's emblem, a whisper face, a fold icon) stays so,
				-- whenever its first kit look comes
				local okM, mouse = pcall(b.IsMouseEnabled, b)
				rim = Kit:Slot(b, { kind = "roundslot" })
				if okM and not Secret(mouse) and mouse == false then
					b:EnableMouse(false)
				end
				if Kit.RegisterTexture then
					Kit:RegisterTexture(rim)   -- Dark Mode's shade
				end
				b.kitRim = rim
				if b.shadeArea and Kit.ShadeElement then
					ShadeRim(b, rim, Kit)
				end
			end
			rim:Show()
			b.plainRim:Hide()
			rim.icon = b.icon
			Kit:SlotPlaceIcon(rim)
			MelloUI.Icons.Fit(b.icon)   -- (the rim's opening: another size)
		else
			if b.kitRim then
				b.kitRim:Hide()
			end
			PlainLay(b)
		end
		b.kitLaid = on
	end

	local function RoundSkin(b)
		if b.texture ~= nil then
			SetIcon(b, b.texture)
		end
		if b.askedKit then
			b:SetKit(b.askedKit)
		end
	end

	-- (1.2.4) a look's own set switched (MelloUI.Icons' 'icons': Oldschool's painted reskin on or off): every round
	-- button's picture again, square or round
	local rounds = setmetatable({}, weakKeys)
	local roundsHeard = false
	local function RoundsAgain()
		for b in pairs(rounds) do
			RoundSkin(b)
		end
	end

	function W.RoundIcon(parent, size, texture, opts)
		opts = type(opts) == "table" and opts or NONE
		local b = CreateFrame("Button", opts.name, parent)
		b:SetSize(size, size)
		b.size = size
		b.shadeArea = type(opts.shade) == "string" and opts.shade or nil
		b:EnableMouse(true)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
		b.icon = icon
		local mask = b:CreateMaskTexture()
		mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(icon)
		icon:AddMaskTexture(mask)
		b.mask = mask
		W.HoverLight(b, "round")   -- over the whole rim: the kit's (on the button) and the plain medallion alike
		b.plainRim = b:CreateTexture(nil, "OVERLAY")
		MelloUI.Icons.Set(b.plainRim, PLAIN_RIM, size)
		b.SetIcon, b.SetOn, b.SetKit, b.SetCrop = SetIcon, SetOn, SetKit, SetCrop
		if texture ~= nil then
			b:SetIcon(texture)
		end
		SetKit(b, false)
		-- (1.2.4) the skin switched: its picture again in the skin's look (MelloUI.Skin); a look's own set too
		local Skin = rawget(MelloUI, "Skin")
		if Skin then
			Skin.followers[b] = RoundSkin
		end
		rounds[b] = true
		if not roundsHeard and MelloUI.On then
			roundsHeard = true
			MelloUI:On("icons", RoundsAgain, "the round icons (a look's own set)")
		end
		return b
	end

	-- (1.2.0; the user, 2026-10-22: "make sure that the icon borders stay sharp in all animations") a round icon a
	-- motion scales, drawn again for the size it shows at now: its ring and picture from the set's sharp copy for that
	-- size where the set has copies (MelloUI.Icons). Call it after each scale a motion sets
	function W.RoundIconRefit(b)
		local I = MelloUI.Icons
		if I and I.Fit and not b.kitLaid then
			I.Fit(b.plainRim, b.size)
			I.Fit(b.icon)
		end
	end
end

--------------------------------------------------------------------------------
-- ThinScrollBar (0.23.0; lifted from the dropdown lists' own, for the chat
-- view's rail too): MelloUI's thin scroll bar for its own lists -- a vertical
-- Slider, a `border` track, a `trim` thumb, its value in rows (step 1). The
-- caller places it, sets its range and its OnValueChanged, and may size the
-- thumb (bar.thumb) to the share of the list in view.
--   W.ThinScrollBar(parent, width) -> bar
--------------------------------------------------------------------------------

function W.ThinScrollBar(parent, width)
	local bar = CreateFrame("Slider", nil, parent)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(width)
	bar:EnableMouseWheel(false)
	local track = W.Solid(bar, "BACKGROUND", "border", 1)
	track:SetAllPoints(bar)
	local thumb = bar:CreateTexture(nil, "ARTWORK")
	thumb:SetWidth(width)
	W.Paint(thumb, "trim", "fill", 1)
	bar:SetThumbTexture(thumb)
	bar:SetValueStep(1)
	bar:SetObeyStepOnDrag(true)
	bar.thumb = thumb
	return bar
end

--------------------------------------------------------------------------------
-- Glyph (0.16.0): the widget glyphs, one sheet (Media/Textures/WidgetGlyphs,
-- 8 x 6 cells of 32 px, white: made by Tools/make_widget_art.py; 8 x 2 until
-- 0.17.0, 8 x 4 until 1.2.4) for the widget column's buttons, the whisper
-- window's header buttons, the chat column's (0.17.0) and Edit Layout's dock
-- and Elements picker (1.2.4); painted by the caller (the
-- palette's text, its gold on hover). Cell 15 is empty: Report's link.
--   W.Glyph(tex, name) -> true   the glyph's cell on the texture; false for a
--                                name the sheet has not (nothing set)
--   W.GLYPHS                     [name] = its cell
--   W.GlyphButton(parent, size, glyph, opts) -> b   a W.RoundIcon (opts as
--                                its) on a dark disc (the palette's
--                                innerPanel), its glyph on it in the
--                                palette's text colour (nil: none yet)
--   b:SetGlyph(name) -> true     another glyph; b.disc
--------------------------------------------------------------------------------

do
	local GLYPH_TEX = "Interface\\AddOns\\MelloUI\\Media\\Textures\\WidgetGlyphs"
	W.GLYPHS = { pause = 0, play = 1, skip = 2, stop = 3, list = 4, padlock = 5, padlockOpen = 6, check = 7,
		cross = 8, way = 9, reply = 10, friend = 11, invite = 12, ignore = 13, report = 14,
		-- (0.21.3: an empty cell, W.SpacerMarkup's)
		blank = 15,
		chat = 16, channels = 17, friends = 18,
		-- (0.17.0: Combat Text's feed, a mark per kind)
		hit = 19, heal = 20, proc = 21, avoid = 22, gain = 23,
		-- (0.17.0: the damage meter's values and the Fight History's chat button)
		sword = 24, hourglass = 25, chart = 26,
		-- (0.18.2: the Discard button on the bag and loot windows)
		bin = 27,
		-- (0.19.5: the Quest List's objective marks: collect, use, explore; kill is the sword)
		bag = 28, cog = 29, flag = 30,
		-- (1.2.4: Edit Layout's dock and Elements picker)
		grid = 31, magnet = 32, moon = 33, crosshair = 34, layers = 35, keys = 36, reset = 37, question = 38,
		eye = 39, eyeOff = 40, solo = 41, search = 42, pin = 43,
		-- (2.1.24: the chat's Copy Chat button)
		copy = 44 }
	local ROWS = 6
	W.GLYPH_ROWS = ROWS   -- (the sheet's rows of cells: its height is ROWS x 32 px)

	-- (share, 0.21.3: only the glyph's left part, a share of its width -- a
	-- tick drawn in; the texture as wide as that share)
	function W.Glyph(tex, name, share)
		local i = W.GLYPHS[name]
		if not i then
			return false
		end
		local c, r = i % 8, math.floor(i / 8)
		tex:SetTexture(GLYPH_TEX)
		tex:SetTexCoord(c / 8, (c + (share or 1)) / 8, r / ROWS, (r + 1) / ROWS)
		return true
	end

	-- a glyph as inline text markup (0.17.1: the meter's tooltip lines on a
	-- raid-style frame), size in the line's units, tinted r, g, b (0..1); ""
	-- for a name the sheet has not
	local CELL = 32
	function W.GlyphMarkup(name, size, r, g, b)
		local i = W.GLYPHS[name]
		if not i then
			return ""
		end
		local c, row = i % 8, math.floor(i / 8)
		local function Byte(v)
			return math.floor(math.max(0, math.min(1, tonumber(v) or 1)) * 255 + 0.5)
		end
		return string.format("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d:%d:%d:%d|t", GLYPH_TEX, size, size, 8 * CELL, ROWS * CELL,
			c * CELL, (c + 1) * CELL, row * CELL, (row + 1) * CELL, Byte(r), Byte(g), Byte(b))
	end

	-- (0.21.3, the Quest Tracker's rolling count) an empty stretch of a line,
	-- `width` of its units wide: the blank cell as inline markup, so the
	-- text after it keeps its place while something else is drawn there
	function W.SpacerMarkup(width)
		local i = W.GLYPHS.blank
		local c, row = i % 8, math.floor(i / 8)
		return string.format("|T%s:1:%d:0:0:%d:%d:%d:%d:%d:%d|t", GLYPH_TEX, math.max(1, math.floor((tonumber(width) or 1) + 0.5)),
			8 * CELL, ROWS * CELL, c * CELL, (c + 1) * CELL, row * CELL, (row + 1) * CELL)
	end

	-- (0.25.0; the user's Batches 8 and 10, 2026-10-19) the glyphs that have a button of MelloUI's icon set: in the
	-- plain look the button is that picture -- its own slate disc and gold ring, so no rim, disc or glyph of ours over
	-- it; in the kit's look (Oldschool's rim) the glyph on the disc as before
	W.GLYPH_BUTTON = { pause = "btn_pause", play = "btn_play", skip = "btn_next", stop = "btn_stop", list = "btn_list",
		padlock = "btn_locked", padlockOpen = "btn_unlocked", check = "btn_accept", cross = "btn_decline",
		way = "btn_way", reply = "btn_reply", chart = "btn_meter", friend = "btn_friend", invite = "btn_invite",
		ignore = "btn_ignore", report = "btn_report", bin = "btn_discard", cog = "chat_settings",
		chat = "chat_general", channels = "chat_channels", friends = "chat_friends" }
	-- a set button named straight (the chat's tabs and row: chat_combat, chan_say ...) and the glyph it wears in the
	-- kit's look; one with no glyph there shows its rim and disc alone (a letter, the caller's: b.label)
	W.GLYPH_OF = { chat_general = "chat", chat_combat = "sword", chat_loot = "bag", chan_guild = "flag",
		chat_whispers = "reply", chat_channels = "channels", chat_friends = "friends", chat_history = "chart",
		chat_settings = "cog" }

	-- the button as its glyph and look are: the set's picture, or the rim, the disc and the glyph (and the caller's
	-- letter, b.label)
	-- (1.2.4, the Default skin: MelloUI.Skin) a set picture with a game picture for it: that picture in the plain rim (the
	-- game's gold ring), on the disc -- a channel key whole, the game's chat button with its letter
	local function LayArt(b)
		local art = (not b.kitLaid) and b.glyphArt or nil
		local Skin = rawget(MelloUI, "Skin")
		local game = art and Skin and Skin.Icon(art)
		local plate = game and game.plate or false   -- (a chat button: the game's chat button plate under the picture)
		local ringIt = game and not game.letter and not plate or false
		if plate and not b.gamePlate then
			b.gamePlate = b:CreateTexture(nil, "BACKGROUND", nil, 2)
			b.gamePlate:SetPoint("CENTER")
		end
		if b.gamePlate then
			if plate then
				b.gamePlate:SetAtlas(plate, true)   -- (its own size: the game's 27 x 26)
			end
			b.gamePlate:SetShown(plate and true or false)
		end
		if art then
			if not b.art then
				b.art = b:CreateTexture(nil, "ARTWORK", nil, 3)
			end
			b.art:ClearAllPoints()
			if ringIt or plate then
				b.art:SetAllPoints(b.icon)
			else
				b.art:SetAllPoints(b)
			end
			W.Icon(b.art, art, (ringIt or plate) and b.icon:GetWidth() or b.size)
			b.art:Show()
		elseif b.art then
			b.art:Hide()
		end
		local plain = art ~= nil
		b.icon:SetShown(not plain)
		b.disc:SetShown(not plain or ringIt)
		if b.label then
			b.label:SetShown(not plain)
		end
		if not b.kitLaid then
			b.plainRim:SetShown(not plain or ringIt)
		end
	end

	local function SetGlyph(b, name)
		local cell = W.Glyph(b.icon, W.GLYPH_OF[name] or name)
		if cell then
			W.Paint(b.icon, "text", "vertex")
		end
		local art = W.GLYPH_BUTTON[name] or (W.IconRinged(W.IconPath(name)) and name) or nil
		if cell or art then
			b.glyphName, b.glyphArt = name, art
			LayArt(b)
			return true
		end
		return false
	end

	local function GlyphSetKit(b, Kit)
		b.RoundSetKit(b, Kit)
		LayArt(b)
	end

	-- (1.2.4) the skin switched: its rim and picture in the skin's look (MelloUI.Skin)
	local function GlyphSkin(b)
		if b.askedKit then
			GlyphSetKit(b, b.askedKit)
		else
			LayArt(b)
		end
	end

	local function GlyphSetOn(b, on)
		b.RoundSetOn(b, on)
		if b.art then
			b.art:SetDesaturated(not on)
			b.art:SetAlpha(on and 1 or 0.45)
		end
	end

	function W.GlyphButton(parent, size, glyph, opts)
		local b = W.RoundIcon(parent, size, nil, opts)
		local disc = b:CreateTexture(nil, "BACKGROUND", nil, 1)
		disc:SetTexture(ROUND_MASK)
		disc:SetAllPoints(b.icon)
		W.Paint(disc, "innerPanel", "vertex", 0.95)
		b.disc = disc
		b.SetGlyph = SetGlyph
		b.RoundSetKit, b.SetKit = b.SetKit, GlyphSetKit
		b.RoundSetOn, b.SetOn = b.SetOn, GlyphSetOn
		if glyph ~= nil then
			SetGlyph(b, glyph)
		end
		local Skin = rawget(MelloUI, "Skin")
		if Skin then
			Skin.followers[b] = GlyphSkin
		end
		return b
	end
end

--------------------------------------------------------------------------------
-- PlateButton (0.19.0; flat since 0.19.1, the user, 2026-10-04: "from now on
-- only use the same style as we have in the Configurator" -- it was the kit's
-- cog plate with a black opening): a small square button with a glyph on the
-- controls' icon plate (W.FlatOver's "button": 0.19.9 the NewUI2 icon plate,
-- steel, gold under the pointer -- the user's pick A 2026-10-09; it was the
-- flat `raisedPanel` plate), the glyph in the text colour.
-- The Discard buttons and the bag window's Settings. `kind` "cog" (the
-- bag window's Settings): the NewUI2 cog plate, its own cog in place of the
-- caller's glyph, which stays hidden.
--   W.PlateButton(parent, w, h, glyphSize, area, scripts, kind) -> b, glyph
--     scripts: { OnClick = fn, OnEnter = fn, OnLeave = fn }, set first (the
--     plate's own hover is hooked after them); the caller puts its art on
--     `glyph` (W.Glyph, or a picture of the game's); `area` kept for the
--     callers
--   b.plate (its plate)
--------------------------------------------------------------------------------
do
	local plates = setmetatable({}, weakKeys)   -- [button] = its flat parts
	local function PlatePaint(b, hover)
		local p = plates[b]
		if p then
			W.FlatState(p, hover, false, false, not b:IsEnabled())
		end
	end
	local PlateEnter = Shared("OnEnter on MelloUI's plate buttons", function(b)
		PlatePaint(b, true)
	end, "script")
	local PlateLeave = Shared("OnLeave on MelloUI's plate buttons", function(b)
		PlatePaint(b, false)
	end, "script")

	-- (0.25.0) the set's round button in place of the plate and its glyph, while the button's area is not in
	-- Oldschool's painted look: kind "cog" the chat's Settings button, "bin" (Discard) the bin button
	local PLATE_ART = { cog = "chat_settings", bin = "btn_discard" }
	local artButtons = setmetatable({}, weakKeys)   -- [b] = its area: the buttons that wear a picture of the set
	local artAreas = {}

	-- the set's picture, or the painted plate and its glyph, as the button's area looks now: laid at its making and
	-- again on 'look:<area>' (the reskin switched while it stands)
	local function PlateLook(b)
		local painted = KC.Painted(b.plateArea)
		local plate = plates[b] and plates[b].piece
		b.art:SetShown(not painted)
		if plate then
			plate:SetShown(painted)   -- (hidden, not faded: KC.Lay sets the piece's alpha on each size and state change)
		end
		b.plateGlyph:SetAlpha(painted and 1 or 0)
		if b.artLight then
			b.artLight:SetAlpha(painted and 0 or 1)   -- (the plate lights itself, W.FlatState)
		end
	end

	local function PlateLooks(area)
		for b, a in pairs(artButtons) do
			if a == area then
				PlateLook(b)
			end
		end
	end

	function W.PlateButton(parent, w, h, glyphSize, area, scripts, kind)
		local b = CreateFrame("Button", nil, parent)
		b:SetSize(w, h)
		for script, fn in pairs(scripts or NO_OPTS) do
			b:SetScript(script, fn)
		end
		local p = W.FlatOver(b, kind == "cog" and "cog" or "button")
		plates[b] = p
		Perf.HookScript(b, "OnEnter", PlateEnter)
		Perf.HookScript(b, "OnLeave", PlateLeave)
		PlatePaint(b, false)
		local glyph = b:CreateTexture(nil, "ARTWORK", nil, 2)
		glyph:SetSize(glyphSize, glyphSize)
		glyph:SetPoint("CENTER")
		W.Paint(glyph, "text", "vertex")
		if kind == "cog" then
			glyph:Hide()   -- (the cog plate has its own cog)
		end
		b.plate = p.piece
		local art = PLATE_ART[kind]
		if art then
			local t = b:CreateTexture(nil, "ARTWORK", nil, 4)
			local side = math.min(w, h)
			t:SetSize(side, side)
			t:SetPoint("CENTER")
			W.Icon(t, art, side)
			b.art, b.plateArea, b.plateGlyph = t, area, glyph
			b.artLight = W.HoverLight(b, "round", t)
			local key = area or "config"
			artButtons[b] = key
			if not artAreas[key] and MelloUI.On then
				artAreas[key] = true
				MelloUI:On("look:" .. key, function()
					PlateLooks(key)
				end, "the plate buttons' look (" .. key .. ")")
			end
			PlateLook(b)
		end
		return b, glyph
	end
end

--------------------------------------------------------------------------------
-- TrayBox (0.14.0: the Restock panel beside the shop, the Services trays;
-- lifted from the Services bar's menu box, which can move onto it later): the
-- box of a small list that hangs beside a window. Two looks, switched live
-- with box:SetKit(Kit) (handed the kit while its look is on, nil or false
-- for the plain look, as W.RoundIcon):
--   the kit's list box (Professions-background-summarylist: the single rail
--   round the list-box stone, the Services menu's look), the rule's inner
--   panel over the stone so text rows read on it (the eye strain rule;
--   opts.dim = false leaves the plain stone: a box of icons, no text);
--   plain: a fill in the palette's inner panel inside a 1 px trim edge (the
--   look of W.Box), the regions the kit's box fades while it shows.
--   W.TrayBox(parent[, opts]) -> box   a Frame, sized and placed by the
--       caller. opts (read once): name, strata, dim, alpha (the plain
--       fill's, 0.95)
--   box:SetKit(Kit) -> true while the kit's box shows (made the first time)
--   box.fill, box.edges   the plain look's regions
--------------------------------------------------------------------------------

do
	local NONE = {}

	local function SetKit(box, Kit)
		local rep = box.kitBox
		local on = type(Kit) == "table"
		if on and rep == nil and Kit.Replace then
			rep = Kit:Replace(box.fill, { as = "Professions-background-summarylist", rect = box, parent = box,
				level = -1, dim = box.kitDim, alsoFade = box.edges })
			box.kitBox = rep or false
		end
		if on and rep then
			rep:Enable()
			return true
		end
		if rep then
			rep:Disable()
		end
		return false
	end

	function W.TrayBox(parent, opts)
		opts = type(opts) == "table" and opts or NONE
		local box = CreateFrame("Frame", opts.name, parent)
		if type(opts.strata) == "string" then
			box:SetFrameStrata(opts.strata)
		end
		local alpha = opts.alpha
		if type(alpha) ~= "number" or Secret(alpha) then
			alpha = 0.95
		end
		box.fill = W.Solid(box, "BACKGROUND", "innerPanel", alpha)
		box.fill:SetAllPoints(box)
		box.edges = Edges(box, "trim", "BORDER")
		box.kitDim = opts.dim   -- (nil: the rule's panel; false: none)
		box.SetKit = SetKit
		return box
	end
end

--------------------------------------------------------------------------------
-- RowPlate (audit rank 10): the one hover look of a row, faded through Anim
-- (0.10 s in, 0.12 s out; at once under Reduce Motion), with one pair of
-- shared handlers for every row of every window -- no OnUpdate of the row's
-- own, nothing made per hover.
--   W.RowPlate(row, opts) -> the region that shows, and true when it is the
--   kit's plate
--   opts.look  "palette": the palette's hover fill at `strength` (0.5), with
--              a 2 px `selectedTrim` edge when `edge`; it rests at alpha 0
--              "plate": the kit's row plate (FriendsRowHighlight, CR4) through
--              opts.skin while its kit is on (else the palette look); it
--              rests hidden and fades in and out (it showed and hid at once)
--   opts.selected  fn(row) -> true while the row is the selected one: no
--              wash on it (gold on the hover colour is 2.96:1, under 4.5)
-- W.RowPlateOff(row): back to rest at once (a row just selected).
-- W.RowPlateChild(row, child): a frame on the row that takes the mouse (its
--   switch, button, dropdown, a slider's bar and steppers, a gate's cover).
--   The game gives the row its OnLeave as the pointer moves onto one; the
--   palette wash stays lit while the pointer is still over the row (as the
--   configurator's always did: it polled the row) and fades once the pointer
--   has left the row, from the row or from the child. The typed rows and
--   W.Gate hand theirs over; a window laying its own rows calls it. (The
--   kit's plate goes with the row's own enter and leave, as it did.)
--------------------------------------------------------------------------------

local plateOf = setmetatable({}, weakKeys)      -- [row] = the region that shows
local faderOf = setmetatable({}, weakKeys)      -- [row] = what the fade moves (the region, or its pieces' stand-in)
local edgeOf = setmetatable({}, weakKeys)       -- [row] = its gold edge (palette, edge = true)
local strengthOf = setmetatable({}, weakKeys)   -- [row] = the wash's alpha
local hiddenOf = setmetatable({}, weakKeys)     -- [row] = true: the plate rests hidden (the kit's)
local selectedOf = setmetatable({}, weakKeys)   -- [row] = fn(row): true while it is the selected one
local rowOfChild = setmetatable({}, weakKeys)   -- [a row's control] = the row whose wash it keeps lit
-- the row whose wash stays lit because the pointer, off the row's own
-- frame, is still over it (on one of its controls, or on a frame that is
-- not the row's -- a dropdown's menu over its edge -- from which no leave
-- comes back to the row): let go when the pointer enters another row
local held = nil

-- The kit's plate whose pieces are regions of the ROW (an `owner` strip, as
-- FriendsRowHighlight's rule makes it: Kit:Strip): the strip frame only lays
-- them out, so its alpha never reaches them (review, 2026-09-25: the plate
-- showed at full at once and vanished after the fade out). The fade moves the
-- pieces themselves, through this stand-in that Anim moves as it moves a
-- frame (alpha, shown, hidden): one per row, made with it.
local PieceFader = {}
PieceFader.__index = PieceFader
function PieceFader:GetAlpha()
	return self.alpha
end
function PieceFader:SetAlpha(a)
	self.alpha = a
	local strip = self.strip
	strip.capL:SetAlpha(a)
	strip.mid:SetAlpha(a)
	strip.capR:SetAlpha(a)
end
function PieceFader:IsShown()
	return self.strip:IsShown()
end
function PieceFader:Show()
	self.strip:Show()
end
function PieceFader:Hide()
	self.strip:Hide()
end

local function FaderOf(region)
	local mid = region.mid
	if region.capL and region.capR and mid and mid.GetParent and mid:GetParent() ~= region then
		return setmetatable({ strip = region, alpha = 1 }, PieceFader)
	end
	return region
end

-- the pointer over the row's rect (a secret answer counts as not over)
local function OverRow(row)
	local over = row:IsMouseOver()
	if Secret(over) then
		return false
	end
	return over and true or false
end

-- a wash or edge fades out; one that has not started to show (the mouse
-- passed straight over: nothing drawn yet) is at rest at once, no tween
-- running on for nothing
local function Out(region)
	local Anim = MelloUI.Anim
	if region:GetAlpha() <= 0 then
		Anim:Stop(region, "alpha")
	else
		Anim:To(region, "alpha", 0, FADE_OUT, "inQuad")
	end
end

-- a wash or edge fades in, unless it is there or on its way (the pointer back
-- on the row from one of its controls: no tween running on for nothing)
local function In(region, to)
	local Anim = MelloUI.Anim
	local going = Anim:Target(region, "alpha")
	if going == nil then
		local a = region:GetAlpha()
		if not Secret(a) and a > to - 0.01 and a < to + 0.01 then
			return
		end
	elseif going == to then
		return
	end
	Anim:To(region, "alpha", to, FADE_IN, "outQuad")
end

-- the row's hover back to rest, faded
local function PlateOut(row)
	if held == row then
		held = nil
	end
	local p = faderOf[row]
	if not p then
		return
	end
	if hiddenOf[row] then
		if not p:IsShown() then
			return
		end
		if p:GetAlpha() <= 0 then
			MelloUI.Anim:Stop(p, "alpha")
			p:Hide()
			p:SetAlpha(1)
		else
			MelloUI.Anim:FadeOut(p, FADE_OUT, "inQuad")
		end
	else
		Out(p)
		local e = edgeOf[row]
		if e then
			Out(e)
		end
	end
end

local PlateEnter = Shared("OnEnter on MelloUI's rows (hover)", function(row)
	if held then
		local was = held
		held = nil
		if was ~= row then
			PlateOut(was)
		end
	end
	local p = faderOf[row]
	local sel = selectedOf[row]
	if not p or (sel and sel(row)) then
		return
	end
	if hiddenOf[row] then
		MelloUI.Anim:FadeIn(p, FADE_IN, "outQuad")
	else
		In(p, strengthOf[row])
		local e = edgeOf[row]
		if e then
			In(e, 1)
		end
	end
end, "script")

local PlateLeave = Shared("OnLeave on MelloUI's rows (hover)", function(row)
	if not hiddenOf[row] and OverRow(row) then
		held = row      -- onto one of its controls: lit until the pointer leaves the row
		return
	end
	PlateOut(row)
end, "script")

local PlateChildLeave = Shared("OnLeave on the controls of MelloUI's rows (hover)", function(child)
	local row = rowOfChild[child]
	if not row then
		return
	end
	if OverRow(row) then
		held = row      -- back on the row, or on another of its controls
		return
	end
	PlateOut(row)
end, "script")

-- the palette's wash on a row (under its texts), resting at alpha 0, and its
-- 2 px gold edge unless `edge` is false: the plain hover look (and a
-- flash's, W.Flash; the wash through MelloUI.Look.Mark, the palette's hover)
local function Wash(row, strength, edge)
	local region = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	region:SetAllPoints()
	MelloUI.Look.Mark(region, "hover", "hover", 1)
	region:SetAlpha(0)
	strengthOf[row] = strength or 0.5
	if edge ~= false then
		local e = row:CreateTexture(nil, "BACKGROUND", nil, 2)
		e:SetTexture(WHITE)
		e:SetWidth(2)
		e:SetPoint("TOPLEFT")
		e:SetPoint("BOTTOMLEFT")
		W.Paint(e, "selectedTrim", "vertex", 1)
		e:SetAlpha(0)
		edgeOf[row] = e
	end
	return region
end

do   -- (in a block: the main chunk is near Lua's 200 locals)
	-- (the in-game test, 2026-11-04: Edit Layout picked in the configurator's list, the window back after it -- the entry
	-- still lit) a row hidden while lit, its window closed under the pointer, puts its wash out: no leave comes then
	local PlateHidden = Shared("OnHide on MelloUI's rows (hover)", function(row)
		local p = faderOf[row]
		local sel = selectedOf[row]
		if p and (held == row or (Num(p:GetAlpha()) or 0) > 0) and not (sel and sel(row)) then
			W.RowPlateOff(row)
		end
	end, "script")

	function W.RowPlate(row, opts)
		opts = opts or {}
		local skin = opts.skin
		local region, kit
		if opts.look == "plate" and skin and skin.kit then
			-- the region to replace comes from the shell (its one invisible
			-- anchor): no anchor and no colour literal here
			local rep = skin:Replace(skin:Anchor(row, "BACKGROUND"), { as = "FriendsRowHighlight", rect = row })
			region = rep and rep.object
			if region then
				region:Hide()
				hiddenOf[row], strengthOf[row], kit = true, 1, true
			end
		end
		if not region then
			region = Wash(row, opts.strength, opts.edge)
		end
		plateOf[row] = region
		faderOf[row] = kit and FaderOf(region) or region
		selectedOf[row] = opts.selected
		row:EnableMouse(true)
		Perf.HookScript(row, "OnEnter", PlateEnter)
		Perf.HookScript(row, "OnLeave", PlateLeave)
		Perf.HookScript(row, "OnHide", PlateHidden)
		return region, kit
	end
end

function W.RowPlateChild(row, child)
	if child and child.HookScript and faderOf[row] and not hiddenOf[row] and rowOfChild[child] == nil then
		rowOfChild[child] = row
		Perf.HookScript(child, "OnLeave", PlateChildLeave)
	end
end

function W.RowPlateOff(row)
	local p = faderOf[row]
	if not p then
		return
	end
	if held == row then
		held = nil
	end
	local Anim = MelloUI.Anim
	Anim:Stop(p, "alpha")
	if hiddenOf[row] then
		p:Hide()
		p:SetAlpha(1)
	else
		p:SetAlpha(0)
		local e = edgeOf[row]
		if e then
			Anim:Stop(e, "alpha")
			e:SetAlpha(0)
		end
	end
end

--------------------------------------------------------------------------------
-- Flash: a row's hover look lit for a moment, so the eye finds the row a
-- jump brought into view (the configurator's search, 0.14.0). The row's own
-- RowPlate when it has one (the kit's plate or the palette's wash); a frame
-- without one (a Your setup row, a card, the top bar's Layout group) gets
-- the palette's wash and gold edge at its first flash, lit only by flashes
-- (no hover of its own). Faded in and out through Anim, held by a one-shot
-- timer: nothing runs between flashes. Reduce Motion: on and off at once,
-- still held. A new flash puts the one before out at once; a row the
-- pointer is on keeps its hover when the flash ends.
--   W.Flash(row[, hold])   `hold` in seconds (W.FLASH_HOLD, 1.2); the row ringed in
--                          gold meanwhile (W.FlashRing(): the ring, nil before the first)
--   W.Flashing()           the row a flash holds now, or nil
--------------------------------------------------------------------------------

W.FLASH_HOLD = 1.2
local flashOnly = setmetatable({}, weakKeys)   -- [frame] = true: its wash is a flash's only
local flash = { row = nil, holds = 0, ring = nil, RING = 2 }

-- (Suggestion 1, point 10, 2026-11-04) the row ringed in gold for the hold too, over whatever plate it has: the hover
-- look alone read, on a slate row, as the row losing its fill (the walk). The selected look's 2 px gold edge, all
-- round; ONE ring, made at the first flash, laid on each flashed row (above its controls, no mouse). (A field of
-- `flash`: no new top-level local, the file is near Lua's 200)
function flash.Ring(row)
	local RING = flash.RING
	local ring = flash.ring
	if not ring then
		ring = CreateFrame("Frame", nil, row)
		ring.edges = {}
		for i = 1, 4 do
			local t = ring:CreateTexture(nil, "OVERLAY", nil, 7)
			t:SetTexture(WHITE)
			W.Paint(t, "selectedTrim", "vertex", 1)
			ring.edges[i] = t
		end
		local e = ring.edges
		e[1]:SetPoint("TOPLEFT") e[1]:SetPoint("TOPRIGHT") e[1]:SetHeight(RING)
		e[2]:SetPoint("BOTTOMLEFT") e[2]:SetPoint("BOTTOMRIGHT") e[2]:SetHeight(RING)
		e[3]:SetPoint("TOPLEFT") e[3]:SetPoint("BOTTOMLEFT") e[3]:SetWidth(RING)
		e[4]:SetPoint("TOPRIGHT") e[4]:SetPoint("BOTTOMRIGHT") e[4]:SetWidth(RING)
		ring:Hide()
		flash.ring = ring
	end
	if ring:GetParent() ~= row then
		ring:SetParent(row)
	end
	ring:ClearAllPoints()
	ring:SetAllPoints(row)
	ring:SetFrameLevel((Num(row:GetFrameLevel()) or 0) + 8)
	return ring
end

local function FlashOver()
	flash.holds = flash.holds - 1
	if flash.holds > 0 then
		return
	end
	flash.holds = 0
	local row = flash.row
	flash.row = nil
	if row and (flashOnly[row] or not OverRow(row)) then
		PlateOut(row)
	end
	local ring = flash.ring
	if ring and ring:IsShown() then
		MelloUI.Anim:FadeOut(ring, FADE_OUT, "inQuad")
	end
end

function W.Flash(row, hold)
	if not row then
		return
	end
	local was = flash.row
	if was and was ~= row then
		W.RowPlateOff(was)
	end
	if not faderOf[row] then
		local region = Wash(row, 0.5, true)
		plateOf[row], faderOf[row], flashOnly[row] = region, region, true
	end
	flash.row = row
	local p = faderOf[row]
	if hiddenOf[row] then
		MelloUI.Anim:FadeIn(p, FADE_IN, "outQuad")
	else
		In(p, strengthOf[row])
		local e = edgeOf[row]
		if e then
			In(e, 1)
		end
	end
	if row.GetFrameLevel then
		local ring = flash.Ring(row)
		MelloUI.Anim:Stop(ring, "alpha")
		ring:SetAlpha(0)
		ring:Show()
		MelloUI.Anim:FadeIn(ring, FADE_IN, "outQuad")
	end
	flash.holds = flash.holds + 1
	C_Timer.After(tonumber(hold) or W.FLASH_HOLD, FlashOver)
end

function W.Flashing()
	return flash.row
end

function W.FlashRing()
	return flash.ring
end

--------------------------------------------------------------------------------
-- Tag: ONE small plate with a short gold word for every place that marks a
-- thing -- the installer card's "Recommended" (W.Card's spec.tag, the
-- approved look) and an option's "New" (the user's rule, 2026-09-26: every
-- new dropdown, slider, check box ... carries a New tag for its update, so
-- players find it and try it). The selected tab's colour behind the word,
-- laid on the word itself (no width to measure), both painted by key (a new
-- palette paints them again). Two regions of `parent`, made when asked.
--   local tag = W.Tag(parent, text, snug) -> the word (a FontString),
--       tag.plate (the caller places the word, the plate follows it: W.TAG_PAD
--       round it; `snug`: a narrower one, where room is scarce -- the side list)
--   W.TagShown(tag, shown)    W.TagAlpha(tag, alpha)    (the word and its plate)
-- New tags: an option names the update it came with (`new`); its tag is made
-- and shown only while that update runs (Core's MelloUI:IsNew), so the next
-- update's configurator makes none of the old ones.
--   W.NEW    the word ("New")
--   W.NewTag(parent, after, new, room) -> tag | nil   right after the region
--       `after` (a label); `room`: the width `after` and the tag may take
--       together (a label of a fixed width is narrowed to its text, and cut
--       when the tag would not fit)
--   W.Badge(frame, new, inset) -> tag | nil   on a frame's top edge at its
--       right (a tab): half over it, well inside its sides. `new` true: shown
--       (the caller has asked MelloUI:IsNew of what the frame leads to).
--       `inset`: its plate's right side that far in from the frame's (a
--       control at the frame's right kept clear: the search box's clear
--       button); BADGE_IN when nil
--   W.ButtonTag(button, new) -> tag | nil   INSIDE a text button, at its
--       right and centred on its height (a badge would lie on its label): the
--       button made wider by the tag's room, its label centred in the width
--       it had
--------------------------------------------------------------------------------

local TAG_PAD_X, TAG_PAD_Y = 6, 3   -- the plate round the word
local TAG_SNUG_X = 4                -- a snug plate's sides (the side list)
local TAG_GAP = 6                   -- a label to its tag's plate
local BADGE_IN = 12                 -- a badge's plate inside its frame's right side
local BUTTON_TAG_IN = 8             -- a button's tag plate inside its right side (clear of its end cap)
local LABEL_SLACK = 2               -- a label narrowed to its text keeps this much more (never cut at an odd scale)
W.TAG_PAD = TAG_PAD_X
W.NEW = "New"
W.SHARED = "Shared"   -- (one look: W.Row's opts.shared)

function W.Tag(parent, text, snug)
	local tag = W.Text(parent, "GameFontHighlightSmall", W.Tr(text), "selectedTrim")
	tag:SetWordWrap(false)
	local pad = snug and TAG_SNUG_X or TAG_PAD_X
	local plate = parent:CreateTexture(nil, "ARTWORK")
	plate:SetPoint("TOPLEFT", tag, "TOPLEFT", -pad, TAG_PAD_Y)
	plate:SetPoint("BOTTOMRIGHT", tag, "BOTTOMRIGHT", pad, -TAG_PAD_Y)
	MelloUI.Look.Paint(plate, "badge", "fill", 1)
	tag.plate, tag.padX = plate, pad
	return tag
end

function W.TagShown(tag, shown)
	if tag then
		shown = shown and true or false
		tag:SetShown(shown)
		tag.plate:SetShown(shown)
	end
end

function W.TagAlpha(tag, alpha)
	if tag then
		tag:SetAlpha(alpha)
		tag.plate:SetAlpha(alpha)
	end
end

-- a text's width as written (not cut by a width set on it)
local function TextWidth(fs)
	local get = fs.GetUnboundedStringWidth or fs.GetStringWidth
	return Num(get(fs))
end

-- the room a tag takes after a label: its plate and the gap before it
local function TagSpan(tag)
	local w = TextWidth(tag)
	return w and (w + 2 * TAG_PAD_X + TAG_GAP) or nil
end

function W.NewTag(parent, after, new, room)
	if not (new and after and MelloUI:IsNew(new)) then
		return nil
	end
	local tag = W.Tag(parent, W.NEW)
	tag:SetPoint("LEFT", after, "RIGHT", TAG_GAP + TAG_PAD_X, 0)
	if room then
		local w, span = TextWidth(after), TagSpan(tag)
		if w and span then
			-- (its text's width and a little more: a text set exactly as wide
			-- as it measures can be cut at an odd UI scale)
			after:SetWidth(math.max(1, math.min(w + LABEL_SLACK, room - span)))
		end
	end
	return tag
end

-- (`new` true: the caller asked MelloUI:IsNew of what the frame leads to)
local function Shows(new)
	return new == true or (new ~= nil and new ~= false and MelloUI:IsNew(new))
end

function W.Badge(frame, new, inset)
	if not Shows(new) then
		return nil
	end
	local tag = W.Tag(frame, W.NEW)
	-- (the word's middle on the frame's top edge)
	tag:SetPoint("RIGHT", frame, "TOPRIGHT", -((tonumber(inset) or BADGE_IN) + TAG_PAD_X), 0)
	return tag
end

function W.ButtonTag(button, new)
	if not Shows(new) then
		return nil
	end
	local tag = W.Tag(button, W.NEW)
	tag:SetPoint("RIGHT", button, "RIGHT", -(BUTTON_TAG_IN + TAG_PAD_X), 0)
	local width, word = Num(button:GetWidth()), TextWidth(tag)
	if width and word then
		-- the tag's room added at the right (its plate, and the cap's inset
		-- past it); the label stays centred in the width it had, so it never
		-- reaches under the tag
		local extra = word + 2 * TAG_PAD_X + BUTTON_TAG_IN
		button:SetWidth(width + extra)
		local fs = button.GetFontString and button:GetFontString()
		if fs then
			local _, _, _, x, y = fs:GetPoint(1)
			fs:ClearAllPoints()
			fs:SetPoint("CENTER", button, "CENTER", (Num(x) or 0) - extra / 2, Num(y) or 0)
		end
	end
	return tag
end

--------------------------------------------------------------------------------
-- Rows: a ledger row with its label on the left, an optional hint after it,
-- the description in its tooltip, a control on the right.
--   W.Row(parent, y, height, label, hint, desc, opts) -> row
--     parent  the section the row lies in, `y` below its top
--     opts.skin
--     opts.inset   the row's margin at both sides (0)
--     opts.indent  the label's extra step right (0: a sub-option's level)
--     opts.zebra   a stripe under it (`mainWindow` at 0.85)
--     opts.line    a 1 px `border` line along its bottom at 0.6 (the plain
--                  look's ledger)
--     opts.look    the hover (W.RowPlate): "plate" | "palette" | false
--     opts.gate    fn() -> live, why, line: the row sleeps while not live
--                  (W.Gate)
--     opts.note    (true) while it sleeps, the hint slot reads "Switch on
--                  "why" first." -- or `line` as it is, when the gate gives
--                  one ("Not for Pet") (the row keeps its height)
--     opts.onCover fn(row): a click on the sleeping row (the configurator's
--                  jump to the switch that wakes it)
--     opts.clip    (true, typed rows) the label and hint end 10 px left of
--                  the control, cut there, the full text in the tooltip
--     opts.new     the update the option came with: its New tag right after
--                  the label while that update runs (W.NewTag; the hint after
--                  the tag), dimmed with the row while it sleeps; a label with
--                  a tag and no hint keeps its text's width, cut only where
--                  the two would reach the control (row.newTag)
--     opts.colW    (1.2.4, the configurator's two columns) a half row: this
--                  wide at opts.colX from its parent's left, opts.colH tall
--                  (not its own height); its Shared mark and hint a second
--                  line under the label (row.stacked), each cut at the control
--   row:Refresh()  the row's control (get again) and its gate
-- The typed rows (a row and its control, which takes get / set; the
-- controls flat in both looks, 0.15.0: nothing of theirs for the kit's
-- sweep):
--   W.ToggleRow(parent, y, label, hint, desc, get, set, opts) -> row, switch
--   W.SliderRow(parent, y, label, hint, desc, get, set, opts) -> row, slider
--     (opts.min, max, step, percent, format, width: the whole slider, its
--     box included, at the row's right; 256 when none is given, the span
--     such a row always had)
--   W.DropdownRow(parent, y, label, hint, desc, get, set, values, opts)
--     -> row, dropdown (opts.width 200; the label is its default text)
--   W.ButtonRow(parent, y, label, hint, desc, text, onClick, opts)
--     -> row, button (opts.width 70; onClick a shared handler)
--   W.ControlOf(row)   the typed row's control
--------------------------------------------------------------------------------

local controlOf = setmetatable({}, weakKeys)   -- [row] = its control
local gateOf = setmetatable({}, weakKeys)      -- [row] = its cover (W.Gate)
local clipAt = setmetatable({}, weakKeys)      -- [row] = the region its texts end at (W.ClipRow)

function W.ControlOf(row)
	return controlOf[row]
end

local function RowRefresh(row)
	local control = controlOf[row]
	if control and control.Refresh then
		control:Refresh()
	end
	local cover = gateOf[row]
	if cover then
		cover:Refresh()
	end
end

-- the line a sleeping row says (one per switch, made once, not a new
-- string per hover or refresh)
local function GateLine(cover, why)
	local lines = cover.gateLines
	if not lines then
		lines = {}
		cover.gateLines = lines
	end
	local line = lines[why]
	if not line then
		line = MelloUI.Lang.F("Switch on \"%s\" first.", W.Tr(why))
		lines[why] = line
	end
	return line
end

-- the line a sleeping row says: the gate's own (as it is), or the switch
-- that wakes it
local function SleepLine(cover, why, line)
	if line then
		return W.Tr(line)
	end
	return why and GateLine(cover, why) or nil
end

-- the cover's tooltip: the row's label, and what wakes it
local CoverEnter = Shared("OnEnter on MelloUI's sleeping rows", function(self)
	local _, why, line = self.gate()
	local row = self.gateRow
	W.ShowTooltip(self, row.label and row.label:GetText() or "", SleepLine(self, why, line))
end, "script")

-- a click on a sleeping row: the caller's (opts.onCover), a left click only
local CoverClick = Shared("OnMouseUp on MelloUI's sleeping rows (to the switch that wakes it)", function(self, button)
	local fn = self.onCover
	if fn and button ~= "RightButton" then
		fn(self.gateRow)
	end
end, "script")

local function GateRefresh(cover)
	local live, why, line = cover.gate()
	local row = cover.gateRow
	row:SetAlpha(live and 1 or GATE_ALPHA)
	cover:SetShown(not live)
	local hint = cover.note and row.hint
	if hint then
		local text = cover.hintText
		if not live then
			text = SleepLine(cover, why, line) or text
		end
		hint:SetText(text or "")
		-- (the languages: a sleeping row's long line -- "Switch on X first (Look)." -- that the row cuts short gives
		-- way to the short one; the tooltip keeps the long)
		if not live and line and why and hint.IsTruncated and hint:IsTruncated() then
			hint:SetText(GateLine(cover, why))
		end
		-- (and a line still cut -- a long label leaves the slot narrow -- says nothing: the row stays dimmed, its
		-- tooltip and its click keep what wakes it)
		if not live and hint.IsTruncated and hint:IsTruncated() then
			hint:SetText("")
		end
		hint:SetShown(text ~= nil and text ~= "")
	end
end

-- A row that only means something while a switch is on (user, 2026-09-24:
-- "people will get overwhelmed by all the options"): `gate()` returns whether
-- it is live and, when not, the switch to turn on -- or a line of its own to
-- say instead (0.15.0: "Not for Pet", a row that has no setting on this
-- pick). Off, the row is dimmed and a cover over it takes the clicks and
-- says what wakes it.
--   opts.note (true): the hint slot reads that line while it sleeps
--   opts.onCover (0.15.0): fn(row), a click on the cover (the configurator
--   jumps to the switch, on another page or pick)
function W.Gate(row, gate, opts)
	local cover = CreateFrame("Frame", nil, row)
	cover:SetAllPoints(row)
	cover:SetFrameLevel(row:GetFrameLevel() + 30)
	cover:EnableMouse(true)
	cover.gate, cover.gateRow = gate, row
	Perf.SetScript(cover, "OnEnter", CoverEnter)
	Perf.SetScript(cover, "OnLeave", TipLeave)
	if opts and opts.onCover then
		cover.onCover = opts.onCover
		Perf.SetScript(cover, "OnMouseUp", CoverClick)
	end
	W.RowPlateChild(row, cover)
	cover:Hide()
	cover.Refresh = GateRefresh
	if not (opts and opts.note == false) then
		cover.note = true
		if not row.hint then
			row.hint = W.Text(row, "GameFontHighlight", nil, "text")   -- (Suggestion 1 point 7: body size)
			-- (after the row's last tag, as W.Row lays its hint: the Shared / "also ..." mark too -- the user's
			-- screenshot, 2026-10-16: the gate's line over the "also Target, Focus ..." mark)
			local last = row.sharedTag or row.newTag
			if row.stacked and row.sharedTag then
				row.hint:SetPoint("LEFT", row.sharedTag, "RIGHT", 10 + TAG_PAD_X, 0)
			elseif row.colW then
				-- (a half row: under its label -- its second line; a row with none shows it only while asleep)
				row.hint:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -W.HALF_GAP)
			else
				row.hint:SetPoint("LEFT", last or row.label, "RIGHT", last and (10 + TAG_PAD_X) or 10, 0)
			end
			row.hint:SetWordWrap(false)
			local at = clipped[row] and clipAt[row]
			if at then
				row.hint:SetPoint("RIGHT", at, "LEFT", -10, 0)
			end
		end
		cover.hintText = row.hint:GetText()
	end
	gateOf[row] = cover
	return cover
end

-- A label with a New tag and no hint: its text's width, the tag right after
-- it; narrowed (cut, the whole text in the tooltip) only where the two would
-- reach 10 px short of the control. `span`: the control's left edge from the
-- row's right one (the typed rows know it); the row as wide as its parent
-- less the row's margins (a section's set width). Unknown: left as it is.
local function FitLabel(row, span)
	local label, parent = row.label, row:GetParent()
	local width = span and parent and Num(parent:GetWidth())
	local text, tag = TextWidth(label), TagSpan(row.newTag)
	if not (width and width > 0 and text and tag) then
		return
	end
	local room = width - 2 * (row.rowInset or 0) - (row.labelX or 14) - span - 10 - tag
	if row.colW then
		room = row.colW - (row.labelX or 14) - span - 10 - tag   -- (a half row: its own width)
	end
	if text > room then
		label:SetWidth(math.max(20, room))
	end
end

-- (1.2.4) a half row with a second line (W.Row's opts.colW): the label, its New tag after it, cut where they would
-- reach 10 px short of the control; the hint under it (after the Shared mark) cut the same. `span` unknown (a link
-- row's value): left as it is. (In a block with W.ClipRow, its one caller: no local of the main chunk's)
do
local function FitHalf(row, span)
	local room = span and row.colW and row.colW - (row.labelX or 14) - span - 10
	if not room then
		return
	end
	local text = TextWidth(row.label)
	local tag = row.newTag and TagSpan(row.newTag) or 0
	if text and tag and text + tag > room then
		row.label:SetWidth(math.max(20, room - tag))
	end
	local hint = row.hint
	if hint then
		local used = row.sharedTag and TagSpan(row.sharedTag) or 0
		local w = TextWidth(hint)
		if w and used and w > room - used then
			hint:SetWidth(math.max(20, room - used))
		end
	end
end

-- The label and hint kept left of the control: the last of them ends 10 px
-- left of it (word wrap off: the game cuts it there), the full text in the
-- row's tooltip when cut; a label with a New tag and no hint: FitLabel.
-- `control` may be any region the texts end at (a link row's value).
function W.ClipRow(row, control, span)
	local last = row.hint or row.label
	if not (last and control) then
		return
	end
	if row.stacked then
		FitHalf(row, span)
	elseif last == row.label and row.newTag then
		FitLabel(row, span)
	else
		last:SetPoint("RIGHT", control, "LEFT", -10, 0)
		-- (the configurator walk, 2026-11-04: Minimap > Services' "Bar Distance From The Minimap" ran under its
		-- slider) a half row's hint that is not stacked is its gate's line UNDER the label (W.Gate): the label ends
		-- at the control too
		if last ~= row.label and row.colW then
			if row.newTag then
				FitLabel(row, span)
			else
				row.label:SetPoint("RIGHT", control, "LEFT", -10, 0)
			end
		end
	end
	clipped[row], clipAt[row] = true, control
	if not row.tipTitle then
		row.tipTitle = row.label and row.label:GetText() or ""
		Perf.HookScript(row, "OnEnter", RowTipEnter)
		Perf.HookScript(row, "OnLeave", TipLeave)
	end
end
end   -- (the block of FitHalf and W.ClipRow)

local PLATE_OPTS = {}   -- a row's RowPlate options (one table, filled per row)
-- (1.2.4) a half row's second line: the label lifted this much over the row's middle, the line this far under it
W.HALF_LIFT, W.HALF_GAP = 7, 3

function W.Row(parent, y, height, label, hint, desc, opts)
	opts = opts or NO_OPTS
	label, hint, desc = W.Tr(label), W.Tr(hint), W.Tr(desc)
	local inset = opts.inset or 0
	local row = CreateFrame("Frame", nil, parent)
	local half = opts.colW
	if half then
		-- (1.2.4, the configurator's two columns: a half row its own width at its column's place, its column's height)
		row:SetHeight(opts.colH or height)
		row:SetPoint("TOPLEFT", opts.colX or inset, -y)
		row:SetWidth(half)
		row.colW = half
	else
		row:SetHeight(height)
		row:SetPoint("TOPLEFT", inset, -y)
		row:SetPoint("RIGHT", parent, "RIGHT", -inset, 0)
	end
	row:EnableMouse(true)
	if opts.zebra then
		-- CR4 (user, 2026-09-21): a faint band on every other row
		row.band = row:CreateTexture(nil, "BACKGROUND")
		row.band:SetAllPoints(row)
		W.Paint(row.band, "mainWindow", "fill", 0.85)
	end
	if opts.line then
		local line = W.Solid(row, "BORDER", "border", 0.6)
		line:SetHeight(1)
		line:SetPoint("BOTTOMLEFT")
		line:SetPoint("BOTTOMRIGHT")
	end
	local look = opts.look
	if look then
		local plate = PLATE_OPTS
		plate.look, plate.skin, plate.strength = look, opts.skin, opts.strength
		local region, kit = W.RowPlate(row, plate)
		plate.look, plate.skin, plate.strength = nil, nil, nil
		-- (the fields such rows always had: a heading's `hover` is taken away)
		if kit then
			row.hover = region
		else
			row.hoverGlow = region
		end
	end
	row.label = W.Text(row, "GameFontHighlight", label, opts.labelKey or "text")
	row.labelX, row.rowInset = 14 + (opts.indent or 0), inset
	-- (a half row with a Shared mark or a hint: those a second line under the label, the label lifted)
	local second = half and ((hint and hint ~= "") or opts.shared) and true or nil
	row.stacked = second
	row.label:SetPoint("LEFT", row.labelX, second and W.HALF_LIFT or 0)
	row.label:SetWordWrap(false)
	-- (the option's New tag: made only while its update runs)
	row.newTag = opts.new and W.NewTag(row, row.label, opts.new) or nil
	-- (one look, the designers: a value other elements share -- "Shared",
	-- or the text given -- after the label and its New tag)
	if opts.shared then
		row.sharedTag = W.Tag(row, type(opts.shared) == "string" and opts.shared or W.SHARED)
		if second then
			row.sharedTag:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", TAG_PAD_X, -W.HALF_GAP - 2)
		else
			row.sharedTag:SetPoint("LEFT", row.newTag or row.label, "RIGHT",
				TAG_GAP + TAG_PAD_X + (row.newTag and TAG_PAD_X or 0), 0)
		end
	end
	local last = row.sharedTag or row.newTag
	if hint and hint ~= "" then
		-- (Suggestion 1, point 7, 2026-11-04: a helper line at body size)
		row.hint = W.Text(row, "GameFontHighlight", hint, opts.hintKey or "text")
		if second and row.sharedTag then
			row.hint:SetPoint("LEFT", row.sharedTag, "RIGHT", 10 + TAG_PAD_X, 0)
		elseif second then
			row.hint:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -W.HALF_GAP)
		else
			row.hint:SetPoint("LEFT", last or row.label, "RIGHT", last and (10 + TAG_PAD_X) or 10, 0)
		end
		row.hint:SetWordWrap(false)
	end
	if desc and desc ~= "" then
		row.tipTitle, row.tipBody = label, desc
		Perf.HookScript(row, "OnEnter", RowTipEnter)
		Perf.HookScript(row, "OnLeave", TipLeave)
	end
	row.Refresh = RowRefresh
	if opts.gate then
		W.Gate(row, opts.gate, opts)
	end
	return row
end

-- a typed row's control in place: known to the row, the texts cut at it
-- (0.15.0: every typed row's control is flat -- its rep false in MelloUI.Kept.repOf -- so no
-- sweep of the kit's is asked per row). `span`: the control's left edge from
-- the row's right one (where a New tag's label may end: ClipRow)
local function Finish(row, control, opts, span)
	controlOf[row] = control
	-- the control's frames that take the mouse keep the row's wash lit (a
	-- slider's are its track and its value box)
	W.RowPlateChild(row, control)
	W.RowPlateChild(row, rawget(control, "Slider"))
	W.RowPlateChild(row, rawget(control, "box"))
	if opts.clip ~= false then
		W.ClipRow(row, control, span)
	end
	return row, control
end

function W.ToggleRow(parent, y, label, hint, desc, get, set, opts)
	opts = opts or NO_OPTS
	label, desc = W.Tr(label), W.Tr(desc)
	local row = W.Row(parent, y, W.ROW_HEIGHT, label, hint, desc, opts)
	local switch = W.Switch(row, get, set, opts)
	switch:SetPoint("RIGHT", -12, 0)
	ControlTip(switch, row, label, desc)
	return Finish(row, switch, opts, 12 + 26)
end

do
	-- `opts.width` is the whole control's, the track and its box (the track
	-- `width - W.SLIDER_BOX`), so a caller that places the slider itself (the
	-- Restock List's lines) keeps the footprint it asked for. None given: the
	-- span such a row always had -- 200 for the old slider and the 56 px its
	-- value took right of it -- the track where the old slider was, the box
	-- in that room, its right edge with the other rows' controls.
	local SLIDER_WIDTH, SLIDER_END = 256, 14

	function W.SliderRow(parent, y, label, hint, desc, get, set, opts)
		opts = opts or NO_OPTS
		local row = W.Row(parent, y, W.SLIDER_ROW_HEIGHT, label, hint, desc, opts)
		local width = opts.width or SLIDER_WIDTH
		local slider = W.Slider(row, width, get, set, opts)
		slider:SetPoint("RIGHT", -SLIDER_END, 0)
		return Finish(row, slider, opts, SLIDER_END + width)
	end
end

-- (the dropdown's own options: its default text is the row's label)
local DROPDOWN_OPTS = {}

function W.DropdownRow(parent, y, label, hint, desc, get, set, values, opts)
	opts = opts or NO_OPTS
	label, desc = W.Tr(label), W.Tr(desc)
	local row = W.Row(parent, y, W.ROW_HEIGHT, label, hint, desc, opts)
	DROPDOWN_OPTS.default, DROPDOWN_OPTS.tooltip = label, nil
	local width = opts.width or 200
	local dd = W.Dropdown(row, width, get, set, values, DROPDOWN_OPTS)
	dd:SetPoint("RIGHT", -14, 0)
	return Finish(row, dd, opts, 14 + width)
end

-- (the button flat, as every typed row's control)
function W.ButtonRow(parent, y, label, hint, desc, text, onClick, opts)
	opts = opts or NO_OPTS
	label, desc = W.Tr(label), W.Tr(desc)
	local row = W.Row(parent, y, W.ROW_HEIGHT, label, hint, desc, opts)
	local width = opts.width or 70
	local button = W.Button(row, text or "Run", width, nil)
	button:SetPoint("RIGHT", -12, 0)
	if onClick then
		Perf.SetScript(button, "OnClick", onClick)
	end
	ControlTip(button, row, label, desc)
	row.button = button
	return Finish(row, button, opts, 12 + width)
end

--------------------------------------------------------------------------------
-- ShapeRow (0.19.9: Action Bars > Bars > Layout, L1 of keybind_layout_sketch):
-- a bar's shape in small cells -- its rows (or columns on a bar stood
-- upright), how many icons, their size and the room between them -- laid
-- again on every refresh. Its cells come with the row (a page builds on its
-- first open), painted by palette key.
--   W.ShapeRow(parent, y, label, hint, desc, get, opts) -> row, box
--     get() -> { rows, icons, size (100: the game's), padding, vertical } | nil
--------------------------------------------------------------------------------
do
	local BOX_W, BOX_H = 220, 56   -- the preview's room
	local CELL = 14                -- a cell at 100 %
	local MOST = 12                -- the most icons a bar shows
	local PAD = 1 / 3              -- a pixel of the game's padding, in the preview's

	local function Lay(box)
		local s = box.get and box.get()
		local cells = box.cells
		if type(s) ~= "table" then
			for i = 1, MOST do
				cells[i].edge:Hide()
				cells[i].fill:Hide()
			end
			return
		end
		local icons = math.max(1, math.min(MOST, math.floor(tonumber(s.icons) or MOST)))
		local rows = math.max(1, math.min(icons, math.floor(tonumber(s.rows) or 1)))
		local per = math.ceil(icons / rows)
		local cols, lines = per, rows
		if s.vertical then
			cols, lines = rows, per
		end
		local gap = math.max(1, (tonumber(s.padding) or 2) * PAD)
		local size = CELL * (tonumber(s.size) or 100) / 100
		size = math.min(size, (BOX_W - (cols - 1) * gap) / cols, (BOX_H - (lines - 1) * gap) / lines)
		size = math.max(3, math.floor(size))
		local w, h = cols * size + (cols - 1) * gap, lines * size + (lines - 1) * gap
		local x0, y0 = BOX_W - w, -(BOX_H - h) / 2
		for i = 1, MOST do
			local c = cells[i]
			if i <= icons then
				local col, line = (i - 1) % per, math.floor((i - 1) / per)
				if s.vertical then
					col, line = line, col
				end
				c.edge:ClearAllPoints()
				c.edge:SetPoint("TOPLEFT", box, "TOPLEFT", x0 + col * (size + gap), y0 - line * (size + gap))
				c.edge:SetSize(size, size)
				c.edge:Show()
				c.fill:Show()
			else
				c.edge:Hide()
				c.fill:Hide()
			end
		end
	end

	W.SHAPE_ROW_HEIGHT = BOX_H + 14

	function W.ShapeRow(parent, y, label, hint, desc, get, opts)
		opts = opts or NO_OPTS
		local row = W.Row(parent, y, W.SHAPE_ROW_HEIGHT, label, hint, desc, opts)
		local box = CreateFrame("Frame", nil, row)
		box:SetSize(BOX_W, BOX_H)
		box:SetPoint("RIGHT", -14, 0)
		box.get, box.cells = get, {}
		for i = 1, MOST do
			local edge = W.Solid(box, "ARTWORK", "selectedTrim", 0.85)
			local fill = W.Solid(box, "ARTWORK", "innerPanel", 1)
			fill:SetDrawLayer("ARTWORK", 1)
			fill:SetPoint("TOPLEFT", edge, "TOPLEFT", 1, -1)
			fill:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -1, 1)
			box.cells[i] = { edge = edge, fill = fill }
		end
		box.Refresh = Lay
		Lay(box)
		return Finish(row, box, opts, 14 + BOX_W)
	end
end

--------------------------------------------------------------------------------
-- CanvasRow (0.20.0, the Raid Frame Designer): a row that is one frame of a
-- module's own, built by the module -- for a page no ledger of rows can say
-- (a frame to drag parts on, a list beside it). No label, no control of the
-- row's: the canvas fills the row and draws what it likes on the dark ground
-- the module gives it.
--   W.CanvasRow(parent, y, height, build, opts) -> row, canvas
--     build(canvas, width)   once, at the row's making (width: the row's)
--     canvas:Refresh()       on the row's refresh (a setting changed, the
--                            page shown again): the module's, if it set one
--   opts: W.Row's (inset, gate, new ...)
--------------------------------------------------------------------------------

do
	local function NoRefresh()
	end

	function W.CanvasRow(parent, y, height, build, opts)
		opts = opts or NO_OPTS
		-- (no hover wash or band over the whole canvas: its own parts light)
		-- (nor the row's own New tag, at its label's place in the canvas's
		-- middle: its tab carries the tag)
		local look, zebra, line, new = opts.look, opts.zebra, opts.line, opts.new
		opts.look, opts.zebra, opts.line, opts.new = nil, nil, nil, nil
		local row = W.Row(parent, y, height, nil, nil, nil, opts)
		opts.look, opts.zebra, opts.line, opts.new = look, zebra, line, new
		local canvas = CreateFrame("Frame", nil, row)
		canvas:SetAllPoints(row)
		canvas.Refresh = NoRefresh
		canvas.melloRow = row
		local width = Num(parent:GetWidth())
		width = (width and width > 0 and width or 700) - 2 * (opts.inset or 0)
		local ok, err = pcall(build, canvas, width)
		if not ok then
			geterrorhandler()(err)
		end
		controlOf[row] = canvas
		return row, canvas
	end

	-- (2.1.13; Nixxen, Discord, 2026-11-07, the Kinds list) a canvas that grew or shrank: its row takes the height and
	-- tells whoever laid it (row.melloOnHeight(row, height): the configurator moves the rows under it, the page's scroll
	-- with them). Nothing for a frame that is no canvas row's
	function W.CanvasHeight(canvas, height)
		local row = canvas.melloRow
		height = Num(height)
		if not (row and height) or Num(row:GetHeight()) == height then
			return
		end
		row:SetHeight(height)
		if row.melloOnHeight then
			row.melloOnHeight(row, height)
		end
	end
end

--------------------------------------------------------------------------------
-- ColorWheel (0.20.0; the user, 2026-10-09: "there should be a color wheel for
-- people to self decide the colour of it"): a colour of the player's own,
-- picked on a wheel of MelloUI's -- a ColorSelect, the engine drawing the wheel
-- and the brightness bar; never the game's colour picker window. Such a colour
-- is the player's data, so it is the one colour MelloUI draws that is not a
-- palette key.
--   W.ColorWheel(parent, size, get, set) -> wheel   the wheel `size` square,
--     its brightness bar right of it (W.WHEEL_BAR wide, W.WHEEL_GAP apart);
--     placed by the caller
--     get() -> r, g, b (0..1); set(r, g, b) on every move of a thumb (live)
--   wheel:Refresh()   get() again, nothing set
--------------------------------------------------------------------------------

W.WHEEL_BAR, W.WHEEL_GAP = 14, 10

do
	local THUMBS = "Interface\\Buttons\\UI-ColorPicker-Buttons"   -- look-ok: the game's own wheel and bar thumbs

	local Select = Shared("OnColorSelect on a colour wheel", function(cs, r, g, b)
		if not cs.melloQuiet then
			cs.melloSet(r, g, b)
		end
	end, "script")

	local function WheelRefresh(cs)
		local r, g, b = cs.melloGet()
		if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
			return
		end
		cs.melloQuiet = true
		cs:SetColorRGB(r, g, b)
		cs.melloQuiet = false
	end

	function W.ColorWheel(parent, size, get, set)
		local cs = CreateFrame("ColorSelect", nil, parent)
		cs:SetSize(size + W.WHEEL_GAP + W.WHEEL_BAR, size)
		local wheel = cs:CreateTexture(nil, "ARTWORK")
		wheel:SetSize(size, size)
		wheel:SetPoint("TOPLEFT", cs, "TOPLEFT", 0, 0)
		cs:SetColorWheelTexture(wheel)
		local thumb = cs:CreateTexture(nil, "OVERLAY")
		thumb:SetTexture(THUMBS)
		thumb:SetTexCoord(0, 0.15625, 0, 0.625)
		thumb:SetSize(10, 10)
		cs:SetColorWheelThumbTexture(thumb)
		local value = cs:CreateTexture(nil, "ARTWORK")
		value:SetSize(W.WHEEL_BAR, size)
		value:SetPoint("TOPLEFT", wheel, "TOPRIGHT", W.WHEEL_GAP, 0)
		cs:SetColorValueTexture(value)
		local valueThumb = cs:CreateTexture(nil, "OVERLAY")
		valueThumb:SetTexture(THUMBS)
		valueThumb:SetTexCoord(0.25, 1, 0, 0.875)
		valueThumb:SetSize(W.WHEEL_BAR + 12, 8)
		cs:SetColorValueThumbTexture(valueThumb)
		cs.edges = Edges(cs, "border", "BORDER", value)
		cs.melloGet, cs.melloSet = get, set
		cs.Refresh = WheelRefresh
		Perf.SetScript(cs, "OnColorSelect", Select)
		WheelRefresh(cs)
		return cs
	end
end

--------------------------------------------------------------------------------
-- A colour setting (0.20.0, Group Frames' colours): its value is a string --
-- "#rrggbb" (the colour wheel's), "palette:<key>" (a palette colour, which
-- follows the palette) or the name of one of the game's colours
-- ("GREEN_FONT_COLOR": a default with no literal of ours; 2.1.9: "class:MAGE",
-- "power:MANA", "reaction:4", MelloUI.Colours.Game's)
--   W.ColourValue(v) -> r, g, b        (white for anything else)
--   W.ColourHex(r, g, b) -> "#rrggbb"
--   W.ColourRow(parent, y, label, hint, desc, get, set, opts) -> row, swatch
--     the colour as a swatch at the row's right; a click opens the colour
--     wheel under it (W.ColourMenu: one per host window, opts.host -- the
--     configurator's frame -- made on its first open), a thumb's move sets
--     "#rrggbb" at once; a click outside, Escape or Done closes it; with
--     opts.default (2.1.9) its Default button sets that value back
--------------------------------------------------------------------------------

function W.ColourValue(v)
	if type(v) ~= "string" then
		return 1, 1, 1
	end
	local hex = v:match("^#?(%x%x%x%x%x%x)$")
	if hex then
		return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
	end
	local key = v:match("^palette:(%w+)$")
	if key then
		local c = MelloUI.Palette[key]
		if type(c) == "table" and type(c[1]) == "number" then
			return c[1], c[2], c[3]
		end
		return 1, 1, 1
	end
	if MelloUI.Colours then
		local r, g, b = MelloUI.Colours.Game(v)
		if r then
			return r, g, b
		end
	end
	local named = rawget(_G, v)
	if type(named) == "table" and named.GetRGB then
		local r, g, b = named:GetRGB()
		if type(r) == "number" then
			return r, g, b
		end
	end
	return 1, 1, 1
end

function W.ColourHex(r, g, b)
	local function Byte(x)
		x = tonumber(x) or 1
		return math.floor(math.max(0, math.min(1, x)) * 255 + 0.5)
	end
	return string.format("#%02x%02x%02x", Byte(r), Byte(g), Byte(b))
end

do
	local WHEEL_SIZE, PAD = 110, 10
	local menuOf = setmetatable({}, weakKeys)   -- [host] = its colour flyout
	local DONE, DEFAULT = "Done", "Default"
	local DONE_W, DEFAULT_W, BUTTON_GAP = 70, 84, 8

	local function Close(menu)
		menu:Hide()
		menu.catcher:Hide()
		menu.row = nil
	end

	local CatcherClick = Shared("OnMouseDown on the colour flyout's catcher", function(catcher)
		Close(catcher.menu)
	end, "script")
	local DoneClick = Shared("OnClick on the colour flyout's Done", function(b)
		Close(b.menu)
	end, "script")
	-- (2.1.9: the way back from a pick: the row's default, the game's own colour where it names one)
	local DefaultClick = Shared("OnClick on the colour flyout's Default", function(b)
		local menu = b.menu
		local row = menu.row
		if row and row.melloDefault ~= nil then
			row.melloSet(row.melloDefault)
			row:Refresh()
			menu.wheel:Refresh()
		end
	end, "script")
	-- (its window's Escape held while it is open, as the picture flyout's: a press closes it alone)
	local function Hold(menu, on)
		local K = KitNow()
		local shell = K and K.ShellOf and K:ShellOf(menu.host)
		if shell and shell.HoldEscape then
			shell:HoldEscape(on)
		end
	end
	local MenuHidden = Shared("OnHide on the colour flyout", function(menu)
		menu.catcher:Hide()
		menu.row = nil
		Hold(menu, false)
	end, "script")

	function W.ColourMenu(host)
		local menu = menuOf[host]
		if menu then
			return menu
		end
		local name = (host:GetName() or "MelloUIWindow") .. "ColourMenu"
		menu = W.Panel(CreateFrame("Frame", name, host), { on = true })
		menu:SetSize(math.max(WHEEL_SIZE + W.WHEEL_GAP + W.WHEEL_BAR + 6, DEFAULT_W + BUTTON_GAP + DONE_W) + 2 * PAD,
			WHEEL_SIZE + 2 * PAD + 30)
		menu:SetFrameStrata("FULLSCREEN_DIALOG")
		menu:EnableMouse(true)
		menu:SetClampedToScreen(true)
		menu:Hide()
		menu.host = host
		menu.wheel = W.ColorWheel(menu, WHEEL_SIZE, function()
			local row = menu.row
			if row then
				return W.ColourValue(row.melloGet())
			end
			return 1, 1, 1
		end, function(r, g, b)
			local row = menu.row
			if row then
				row.melloSet(W.ColourHex(r, g, b))
				row:Refresh()
			end
		end)
		menu.wheel:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD, -PAD)
		local done = W.Button(menu, DONE, DONE_W, nil, { height = 20, onClick = DoneClick })
		done:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -PAD, PAD - 2)
		done.menu = menu
		local default = W.Button(menu, DEFAULT, DEFAULT_W, nil, { height = 20, onClick = DefaultClick })
		default:SetPoint("RIGHT", done, "LEFT", -BUTTON_GAP, 0)
		default.menu = menu
		menu.default = default
		local catcher = CreateFrame("Frame", nil, host)
		catcher:SetAllPoints(host)
		catcher:SetFrameStrata("FULLSCREEN_DIALOG")
		catcher:EnableMouse(true)
		catcher.menu = menu
		Perf.SetScript(catcher, "OnMouseDown", CatcherClick)
		catcher:Hide()
		menu.catcher = catcher
		Perf.SetScript(menu, "OnHide", MenuHidden)
		Perf.HookScript(host, "OnHide", function()
			Close(menu)
		end)
		tinsert(UISpecialFrames, name)   -- (Escape closes it; hidden, the game passes it by)
		menuOf[host] = menu
		return menu
	end

	local function Open(row)
		local host = row.melloHost or row:GetParent()
		local menu = W.ColourMenu(host)
		if menu:IsShown() and menu.row == row then
			Close(menu)
			return
		end
		menu.row = row
		menu.default:SetShown(row.melloDefault ~= nil)
		menu.catcher:SetFrameLevel(math.max(1, menu:GetFrameLevel() - 1))
		menu.catcher:Show()
		menu:ClearAllPoints()
		menu:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", 0, -2)
		menu:Show()
		Hold(menu, true)
		menu.wheel:Refresh()
	end

	local SwatchClick = Shared("OnClick on a colour row's swatch", function(swatch)
		MelloUI:PlayUISound("tab")
		Open(swatch)
	end, "script")

	local function SwatchRefresh(swatch)
		swatch.fill:SetColorTexture(W.ColourValue(swatch.melloGet()))
	end

	local SWATCH_W, SWATCH_H = 50, 18

	function W.ColourRow(parent, y, label, hint, desc, get, set, opts)
		opts = opts or NO_OPTS
		local row = W.Row(parent, y, W.ROW_HEIGHT, label, hint, desc, opts)
		local swatch = CreateFrame("Button", nil, row)
		swatch:SetSize(SWATCH_W, SWATCH_H)
		swatch:SetPoint("RIGHT", -14, 0)
		swatch.fill = swatch:CreateTexture(nil, "ARTWORK")
		swatch.fill:SetPoint("TOPLEFT", swatch, "TOPLEFT", 1, -1)
		swatch.fill:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)
		swatch.edges = Edges(swatch, "border", "OVERLAY")
		swatch.melloGet, swatch.melloSet, swatch.melloHost = get, set, opts.host
		swatch.melloDefault = opts.default
		swatch.Refresh = SwatchRefresh
		Perf.SetScript(swatch, "OnClick", SwatchClick)
		SwatchRefresh(swatch)
		return Finish(row, swatch, opts, 14 + SWATCH_W)
	end
end

--------------------------------------------------------------------------------
-- PictureRow (0.15.0: Dynamic UI Modification's pictures, folded into the
-- configurator's pages): a look chosen by its picture -- a border, a
-- backdrop, a background, the minimap's shape. The row's box shows the
-- chosen one's picture (28 px) and its name; a click opens the window's
-- flyout under the box, a tile per choice with its picture (Kit:ChoicePicture,
-- looked up when drawn, as W.Paint looks up the kit), the chosen one outlined
-- in gold; a tile sets it at once (the real bars and windows change as you
-- pick) and closes the flyout.
--   W.PictureRow(parent, y, label, hint, desc, get, set, choices, kind, opts)
--     -> row, box
--     choices  { { value, label, piece | bar | prefix ... } } (the choice
--              lists the kit and the panels keep: Kit.borderKinds' values, a
--              PickerGroups section's choices)
--     kind     "rim" | "bar" | "frame" | "tile" (Kit:ChoicePicture)
--     opts     host (the window whose flyout it opens: the configurator's
--              frame), skin (its shell), width (200), and W.Row's
--   box:SetChoices(choices, kind)   another list (a row whose setting is
--                                   another key per pick)
--   box:Refresh()                   the chosen one drawn again (row:Refresh)
-- The flyout (W.PictureMenu): ONE per host window, made on its first open,
-- never at login; a child of the host (not of a scrolling page, which would
-- clip it), over the page, under the box (over it when there is no room
-- below). Its tiles come from a pool: an open makes no frame once the pool
-- holds enough. Closed by a tile, Escape (the flyout in UISpecialFrames, the
-- host's own Escape held meanwhile: shell:HoldEscape), a click outside (a
-- clear catcher over the host, shown only while the flyout is: no mouse
-- listener of its own), the box's page scrolling, the box hidden (a tab or
-- page switched away), the host hidden, W.ClosePictureMenu(host) (a pick
-- changed), and combat. It never opens in combat (the providers' own
-- changes were never meant for it: Dynamic UI refused a fight too): a click
-- then says "Not in combat." in the box's tooltip, and nothing else; a fight
-- that starts while it is open closes it (PLAYER_REGEN_DISABLED, listened to
-- only while it is open). With the host's shell it wears the UI shade of the
-- windows (Kit:ShadeElement, area "windows"), as the window it opens from.
-- The shell is the host's own (Kit:ShellOf), whatever skin a row passes (a
-- row in the plain look passes none): `skin` counts only for a host that
-- has no shell.
--   W.PictureMenu(host, skin) -> the host's flyout (made the first time)
--   W.ClosePictureMenu(host)   closes it if it is open (nothing is made)
--   W.CloseFlyouts() -> true when one was open: every open flyout closed (a
--     window that keeps its own Escape, Edit Layout's keys, closes an open
--     list with it first: one step a press, the game's Escape never reaching
--     the flyout there)
-- A dropdown's list opens in the same flyout (0.15.0, W.Dropdown: one
-- flyout of MelloUI's own for a window's choices, never the game's menu):
-- its host the window the box lies in (the nearest with a shell, else the
-- top one: HostOf), made on the box's first click; rows in place of the
-- tiles, left under the box (over it when the screen has no room below; by
-- the box's right when it would pass the screen's right edge), the same
-- closing but for combat -- a list opens in a fight and stays open in one,
-- as the game's menu did. The flyout is clamped to the screen, as the
-- game's menu was.
--------------------------------------------------------------------------------

do
	local PICTURE_W, PICTURE_H = 200, 28   -- a picture row's box, its picture the box's height
	local TILE, TILE_STEP, TILE_COLS = 52, 78, 6   -- a flyout's pictures, tile to tile, tiles to a line
	local TILE_BOX = TILE + 8                      -- a tile: its picture with room for its outline
	local TILE_NAME = 16                           -- the choice's name under a tile
	local TILE_LINE = TILE_BOX + TILE_NAME + 6     -- a line of tiles
	local MENU_PAD = 12                            -- the flyout's margin round its tiles
	local MENU_GAP = 4                             -- the box to the flyout
	local MENU_LIFT = 50                           -- the catcher over the box's level (over a sleeping row's cover: +30)
	local NOT_IN_COMBAT = "Not in combat."
	local SQUARE_SHADE = { shape = "shade/square" }   -- (the flyout's shade: a plain frame's)
	-- a dropdown's list (the flyout's list mode)
	local LIST_ROW_H = 20        -- a row: the game's menu's line
	local LIST_PAD = 4           -- the list's margin round its rows
	local LIST_MARK = 6          -- the chosen entry's mark, a square at its row's left
	local LIST_TEXT_X = 16       -- a row's text from its left, the mark before it
	local LIST_BAR = 6           -- a long list's scroll bar
	local LIST_GAP = 2           -- the box to the list
	local LIST_MAX_W = 420       -- the widest a list grows for its entries
	local MENU_ROWS = 18         -- a long list shows this many entries, and scrolls
	local MENU_MIN_ROWS = 6      -- however small the screen
	local MENU_SCREEN = 0.5      -- and it is never taller than this share of the screen
	local WHEEL_ROWS = 2         -- the rows a notch of the wheel moves
	local unnamed = 0            -- the flyouts of hosts without a name (each its own global name)

	local menuOf = setmetatable({}, weakKeys)      -- [host] = its flyout
	local openMenus = setmetatable({}, weakKeys)   -- [flyout] = true while it is open
	local scrollsHooked = setmetatable({}, weakKeys)   -- [a ScrollFrame] = true: its scrolls close a flyout opened in it
	local Menu = {}                                -- the flyout's methods

	-- the choice of a list that has `value` (nil: none)
	local function ChoiceOf(choices, value)
		local i = ChoiceIndex(choices, value)
		return i and choices[i] or nil
	end

	-- a tile's (or a box's) picture: the kit's drawing, looked up when drawn;
	-- nil: nothing shown
	local function DrawChoice(tile, kind, choice)
		local Kit = KitNow()
		if Kit and Kit.ChoicePicture then
			Kit:ChoicePicture(tile, kind, choice)
		end
	end

	-- a tile's two outlines: the chosen one's (2 px, a faint gold wash) and the
	-- hover's (1 px)
	local function Outline(tile, px, wash)
		local out = {}
		for i = 1, 4 do
			out[i] = tile:CreateTexture(nil, "OVERLAY", nil, 7)
			W.Paint(out[i], "selectedTrim", "fill", 0.95)
		end
		out[1]:SetPoint("TOPLEFT")
		out[1]:SetPoint("TOPRIGHT")
		out[1]:SetHeight(px)
		out[2]:SetPoint("BOTTOMLEFT")
		out[2]:SetPoint("BOTTOMRIGHT")
		out[2]:SetHeight(px)
		out[3]:SetPoint("TOPLEFT")
		out[3]:SetPoint("BOTTOMLEFT")
		out[3]:SetWidth(px)
		out[4]:SetPoint("TOPRIGHT")
		out[4]:SetPoint("BOTTOMRIGHT")
		out[4]:SetWidth(px)
		if wash then
			out[5] = tile:CreateTexture(nil, "OVERLAY", nil, 6)
			out[5]:SetAllPoints(tile)
			W.Paint(out[5], "selectedTrim", "fill", wash)
		end
		return out
	end

	local function OutlineShown(out, shown)
		for i = 1, #out do
			out[i]:SetShown(shown)
		end
	end

	-- (one look C6) a box with a melloTry (a designer stage's TryFor) tries the
	-- choice under the mouse on its stage only; nil when it leaves or the
	-- flyout closes
	local TileEnter = Shared("OnEnter on a picture flyout's tile", function(tile)
		OutlineShown(tile.hover, true)
		local choice = tile.choice
		if choice then
			W.ShowTooltip(tile, choice.label or tostring(choice.value), nil, nil, "ANCHOR_TOP")
			local box = tile.menu and tile.menu.box
			if box and box.melloTry then
				box.melloTry(choice.value)
			end
		end
	end, "script")

	local TileLeave = Shared("OnLeave on a picture flyout's tile", function(tile)
		OutlineShown(tile.hover, false)
		GameTooltip:Hide()
		local box = tile.menu and tile.menu.box
		if box and box.melloTry then
			box.melloTry(nil)
		end
	end, "script")

	-- a tile picked: the flyout closed, the choice set (the live UI changes),
	-- the box drawn again
	local TileClick = Shared("OnClick on a picture flyout's tile", function(tile)
		local menu = tile.menu
		local box = menu and menu.box
		local choice = tile.choice
		if not (box and choice) then
			return
		end
		MelloUI:PlayUISound("option_on")
		Menu.Close(menu)
		if box.melloSet then
			box.melloSet(choice.value)
		end
		box:Refresh()
	end, "script")

	local function NewTile(menu, i)
		local tile = CreateFrame("Button", nil, menu)
		tile:SetSize(TILE_BOX, TILE_BOX)
		tile.pic = CreateFrame("Frame", nil, tile)
		tile.pic:SetSize(TILE, TILE)
		tile.pic:SetPoint("CENTER")
		tile.layers = {}
		tile.size = TILE
		tile.none = tile.pic:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontNormalSmall")
		tile.none:SetPoint("CENTER")
		tile.none:SetText(W.Tr("None"))
		W.Paint(tile.none, "text", "text")
		tile.label = W.Text(tile, "GameFontHighlightSmall", nil, "text")
		tile.label:SetJustifyH("CENTER")
		tile.label:SetPoint("TOP", tile, "BOTTOM", 0, -1)
		tile.label:SetWidth(TILE_STEP - 4)
		tile.label:SetWordWrap(false)
		tile.mark = Outline(tile, 2, 0.12)
		tile.hover = Outline(tile, 1)
		OutlineShown(tile.hover, false)
		tile.menu = menu
		Perf.SetScript(tile, "OnEnter", TileEnter)
		Perf.SetScript(tile, "OnLeave", TileLeave)
		Perf.SetScript(tile, "OnClick", TileClick)
		menu.tiles[i] = tile
		return tile
	end

	-- the box's page scrolled away from where the flyout opened: it closes
	local PictureScrolled = Shared("SetVerticalScroll on a page with a picture row (its flyout closes)", function(scroll, offset)
		for menu in pairs(openMenus) do
			if menu.scroll == scroll then
				local at = Num(offset)
				if not (at and menu.scrollAt and math.abs(at - menu.scrollAt) < 0.5) then
					Menu.Close(menu)
				end
			end
		end
	end, "hook")

	-- the ScrollFrame the box lies in (the page's), up to the host; nil for none
	local function ScrollOf(box, host)
		local f = box:GetParent()
		for _ = 1, 20 do
			if not f or f == host then
				return nil
			end
			if f:GetObjectType() == "ScrollFrame" then
				return f
			end
			f = f:GetParent()
		end
		return nil
	end

	-- the flyout closed by what is not one of its tiles: the catcher (a click or
	-- the wheel outside it), a fight, its own hide (Escape) or its host's
	local CatcherClick = Shared("OnMouseDown / OnMouseWheel on a picture flyout's catcher", function(catcher)
		Menu.Close(catcher.menu)
	end, "script")

	local MenuEvent = Shared("OnEvent on a picture flyout (a fight starts)", function(menu)
		Menu.Close(menu)
	end, "script")

	local MenuHidden = Shared("OnHide on a picture flyout (Escape, the window hidden)", function(menu)
		Menu.Close(menu)
	end, "script")

	local ListWheel -- (the wheel over a list: below, with the list's rows)

	local HostHidden = Shared("OnHide on a window with a picture flyout", function(host)
		local menu = menuOf[host]
		if menu then
			Menu.Close(menu)
		end
	end, "script")

	-- the flyout's UI shade (with the host's shell: through skin:Kit, the kit
	-- handed over, never reached for)
	local function ShadeMenu(K, menu)
		local el = K:ShadeElement(menu, "windows", { host = menu })
		el:Add(menu, SQUARE_SHADE)
	end

	-- The flyout's shell: its host's own (a window in the plain look has one
	-- too, though a row there is given none), else the one its caller gave.
	-- Its Escape is held while the flyout is open, and the shade asked
	-- through it (now with the kit look on, else at the switch to it); taken
	-- once, when there is one.
	local function AdoptShell(menu, skin)
		if menu.skin then
			return
		end
		local K = KitNow()
		skin = (K and K.ShellOf and K:ShellOf(menu.host)) or skin
		if skin then
			menu.skin = skin
			skin:Kit(ShadeMenu, menu)
		end
	end

	function W.PictureMenu(host, skin)
		local menu = menuOf[host]
		if menu then
			AdoptShell(menu, skin)
			return menu
		end
		local own = host:GetName()
		if not own then
			unnamed = unnamed + 1
			own = unnamed == 1 and "MelloUIWindow" or ("MelloUIWindow" .. unnamed)
		end
		local name = own .. "PictureMenu"
		menu = W.Panel(CreateFrame("Frame", name, host), { on = true })
		menu:EnableMouse(true)
		menu:SetClampedToScreen(true)   -- (a window by the screen's edge: the screen holds it)
		menu:Hide()
		menu.host, menu.tiles, menu.rows = host, {}, {}
		-- (the wheel: a list's own while one is open, else the catcher's)
		Perf.SetScript(menu, "OnMouseWheel", ListWheel)
		menu:EnableMouseWheel(false)
		local catcher = CreateFrame("Frame", nil, host)
		catcher:SetAllPoints(host)
		catcher:EnableMouse(true)
		catcher:EnableMouseWheel(true)
		catcher.menu = menu
		Perf.SetScript(catcher, "OnMouseDown", CatcherClick)
		Perf.SetScript(catcher, "OnMouseWheel", CatcherClick)
		catcher:Hide()
		menu.catcher = catcher
		Perf.SetScript(menu, "OnEvent", MenuEvent)
		Perf.SetScript(menu, "OnHide", MenuHidden)
		Perf.HookScript(host, "OnHide", HostHidden)
		tinsert(UISpecialFrames, name)   -- (Escape closes it; hidden, the game passes it by)
		menuOf[host] = menu
		AdoptShell(menu, skin)
		return menu
	end

	function W.ClosePictureMenu(host)
		local menu = host and menuOf[host]
		if menu then
			Menu.Close(menu)
		end
	end

	function W.CloseFlyouts()
		local any = false
		for menu in pairs(openMenus) do
			Menu.Close(menu)   -- (its entry cleared while walked: allowed)
			any = true
		end
		return any
	end

	-- the tiles for the box's choices, the chosen one marked; the flyout sized
	-- to them
	local function LayTiles(menu, box)
		local choices, kind = box.melloChoices, box.melloKind
		local chosen = box.melloGet and box.melloGet()
		local n = #choices
		-- (a list's rows away, if one opened here before)
		for i = 1, #menu.rows do
			menu.rows[i]:Hide()
		end
		if menu.listBar then
			menu.listBar:Hide()
		end
		for i = 1, n do
			local tile = menu.tiles[i] or NewTile(menu, i)
			local choice = choices[i]
			tile.choice = choice
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", menu, "TOPLEFT", MENU_PAD + ((i - 1) % TILE_COLS) * TILE_STEP,
				-(MENU_PAD + math.floor((i - 1) / TILE_COLS) * TILE_LINE))
			tile.label:SetText(choice.label and W.Tr(choice.label) or tostring(choice.value))
			DrawChoice(tile, kind, choice)
			local on = choice.value == chosen
			OutlineShown(tile.mark, on)
			OutlineShown(tile.hover, false)
			W.Paint(tile.label, on and "selectedTrim" or "text", "text")
			tile:Show()
		end
		for i = n + 1, #menu.tiles do
			menu.tiles[i]:Hide()
		end
		local cols, lines = math.min(n, TILE_COLS), math.ceil(n / TILE_COLS)
		menu:SetSize(2 * MENU_PAD + (cols - 1) * TILE_STEP + TILE_BOX, 2 * MENU_PAD + lines * TILE_LINE - 6)
	end


	-- A dropdown's list: a row per entry from a pool (an open makes no frame
	-- once the pool holds enough), ListRows of them shown from the list's top
	-- entry (menu.listTop, 0 the first), the others by the wheel over the
	-- list or its scroll bar (a Slider: its thumb dragged, its track
	-- clicked), the chosen entry in the middle of the view as it opens. As
	-- wide as its box, or its widest entry (to LIST_MAX_W). The row under the
	-- pointer in `hover`, its text `text`; the chosen one's text in gold (but
	-- on the hover: `text`, the palette's rule) with a gold mark before it.

	-- the rows a list of `count` shows: every one of a short list; at most
	-- MENU_ROWS of a long one, never more than MENU_SCREEN of the screen (its
	-- height in the flyout's own units: the UI scale and the window's are in
	-- it), MENU_MIN_ROWS however small
	local function ListRows(menu, count)
		local rows = MENU_ROWS
		local screen = Num(UIParent:GetHeight())
		local ui, own = Num(UIParent:GetEffectiveScale()), Num(menu:GetEffectiveScale())
		if screen and ui and own and own > 0 then
			local fit = math.floor((screen * ui / own * MENU_SCREEN - 2 * LIST_PAD) / LIST_ROW_H)
			rows = math.max(MENU_MIN_ROWS, math.min(rows, fit))
		end
		return math.min(count, rows)
	end

	local function RowLook(row)
		local lit = row.lit and true or false
		row.fill:SetShown(lit)
		W.Paint(row.label, (row.chosen and not lit) and "selectedTrim" or "text", "text")
	end

	local ListRowEnter = Shared("OnEnter on a dropdown list's row", function(row)
		row.lit = true
		RowLook(row)
		local entry = row.entry
		if entry and entry.tooltip then
			W.ShowTooltip(row, EntryText(entry), entry.tooltip)
		end
		local box = row.menu and row.menu.box
		if entry and box and box.melloTry then
			box.melloTry(entry.value)
		end
	end, "script")

	local ListRowLeave = Shared("OnLeave on a dropdown list's row", function(row)
		row.lit = nil
		RowLook(row)
		if GameTooltip:GetOwner() == row then
			GameTooltip:Hide()
		end
		local box = row.menu and row.menu.box
		if box and box.melloTry then
			box.melloTry(nil)
		end
	end, "script")

	-- an entry picked: the list closed, the value set, the box naming it
	local ListRowClick = Shared("OnClick on a dropdown list's row", function(row)
		local menu = row.menu
		local box = menu and menu.box
		local entry = row.entry
		if not (box and entry) then
			return
		end
		MelloUI:PlayUISound("option_on")
		Menu.Close(menu)
		if box.melloSet then
			box.melloSet(entry.value)
		end
		box:Refresh()
	end, "script")

	local function NewListRow(menu, i)
		local row = CreateFrame("Button", nil, menu)
		row:SetHeight(LIST_ROW_H)
		row.fill = row:CreateTexture(nil, "BACKGROUND")
		row.fill:SetAllPoints(row)
		-- (the palette's hover through MelloUI.Look.Mark, as Wash)
		MelloUI.Look.Mark(row.fill, "hover", "hover", 1)
		row.fill:Hide()
		row.mark = row:CreateTexture(nil, "ARTWORK")
		row.mark:SetSize(LIST_MARK, LIST_MARK)
		row.mark:SetPoint("LEFT", row, "LEFT", (LIST_TEXT_X - LIST_MARK) / 2, 0)
		W.Paint(row.mark, "selectedTrim", "fill", 1)
		row.label = W.Text(row, "GameFontHighlight", nil, "text")
		row.label:SetJustifyV("MIDDLE")
		row.label:SetWordWrap(false)
		row.label:SetPoint("LEFT", row, "LEFT", LIST_TEXT_X, 0)
		row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
		row.menu = menu
		Perf.SetScript(row, "OnEnter", ListRowEnter)
		Perf.SetScript(row, "OnLeave", ListRowLeave)
		Perf.SetScript(row, "OnClick", ListRowClick)
		menu.rows[i] = row
		return row
	end

	-- the shown rows from the list's top entry
	local function FillList(menu)
		local values, chosen = menu.listValues, menu.listChosen
		local top, rows = menu.listTop, menu.rows
		for i = 1, menu.listShown do
			local row = rows[i]
			local entry = values[top + i]
			if entry then
				row.entry = entry
				row.label:SetText(EntryText(entry))
				row.chosen = entry.value == chosen
				row.mark:SetShown(row.chosen)
				RowLook(row)
				row:Show()
			else
				row.entry = nil
				row:Hide()
			end
		end
		for i = menu.listShown + 1, #rows do
			rows[i]:Hide()
		end
	end

	-- the list moved (the thumb dragged, the track clicked, the wheel): the
	-- rows from the new top (a row's tooltip goes with its entry)
	local ListBarMoved = Shared("OnValueChanged on a dropdown list's scroll bar", function(bar, value)
		local menu = bar.menu
		if menu.listLaying then
			return
		end
		value = math.floor((Num(value) or 0) + 0.5)
		if value == menu.listTop then
			return
		end
		menu.listTop = value
		FillList(menu)
		local owner = GameTooltip:GetOwner()
		if owner and owner.menu == menu then
			GameTooltip:Hide()
		end
	end, "script")

	-- a long list's scroll bar: MelloUI's thin one (W.ThinScrollBar), made
	-- with the first long list
	local function ListBar(menu)
		local bar = menu.listBar
		if bar then
			return bar
		end
		bar = W.ThinScrollBar(menu, LIST_BAR)
		bar:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -LIST_PAD, -LIST_PAD)
		bar:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -LIST_PAD, LIST_PAD)
		bar.menu = menu
		Perf.SetScript(bar, "OnValueChanged", ListBarMoved)
		menu.listBar = bar
		return bar
	end

	ListWheel = Shared("OnMouseWheel on a dropdown list", function(menu, delta)
		local bar, count, shown = menu.listBar, menu.listCount, menu.listShown
		if not (bar and count and shown and count > shown) then
			return
		end
		local top = menu.listTop - (Num(delta) or 0) * WHEEL_ROWS
		bar:SetValue(math.max(0, math.min(count - shown, top)))   -- (its OnValueChanged moves the list)
	end, "script")

	-- the rows for the box's list, the chosen one marked and in view; the
	-- flyout sized to them (the tiles away, if pictures opened here before)
	local function LayList(menu, box)
		local values = box.melloValues
		local n = #values
		for i = 1, #menu.tiles do
			menu.tiles[i]:Hide()
		end
		local shown = ListRows(menu, n)
		local long = n > shown
		local chosen = box.melloGet and box.melloGet()
		menu.listValues, menu.listChosen, menu.listCount, menu.listShown = values, chosen, n, shown
		-- as wide as the box, or its widest entry (measured on the list's own
		-- hidden text, made with its first open)
		local measure = menu.listMeasure
		if not measure then
			measure = menu:CreateFontString(nil, "BACKGROUND", "MelloUIFont_GameFontHighlight")
			measure:Hide()
			menu.listMeasure = measure
		end
		local width = measure.GetUnboundedStringWidth or measure.GetStringWidth
		local widest = 0
		for i = 1, n do
			measure:SetText(EntryText(values[i]))
			widest = math.max(widest, Num(width(measure)) or 0)
		end
		local right = LIST_PAD + (long and (LIST_BAR + 2) or 0)
		local w = math.max(Num(box:GetWidth()) or 0, math.ceil(widest) + LIST_TEXT_X + 6 + LIST_PAD + right)
		menu:SetSize(math.min(LIST_MAX_W, w), 2 * LIST_PAD + shown * LIST_ROW_H)
		for i = 1, shown do
			local row = menu.rows[i] or NewListRow(menu, i)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", menu, "TOPLEFT", LIST_PAD, -(LIST_PAD + (i - 1) * LIST_ROW_H))
			row:SetPoint("RIGHT", menu, "RIGHT", -right, 0)
			row.lit = nil
		end
		-- the chosen one in the middle of the view (as near as the ends allow)
		local at = ChoiceIndex(values, chosen)
		local top = 0
		if long and at then
			top = math.max(0, math.min(n - shown, at - 1 - math.floor(shown / 2)))
		end
		menu.listTop = top
		local bar = long and ListBar(menu) or menu.listBar
		if bar then
			if long then
				menu.listLaying = true
				bar:SetMinMaxValues(0, n - shown)
				bar:SetValue(top)
				menu.listLaying = nil
				bar.thumb:SetHeight(math.max(16, math.floor(shown * LIST_ROW_H * shown / n)))
				bar:Show()
			else
				bar:Hide()
			end
		end
		FillList(menu)
	end

	-- a list laid from its box's left would pass the screen's right edge (a
	-- long entry in a narrow box by the screen's edge: review, 2026-09-29).
	-- In screen pixels: the UI scale and the window's own are in them
	local function PastRight(menu, box)
		local left, width, screen = Num(box:GetLeft()), Num(menu:GetWidth()), Num(UIParent:GetRight())
		if not (left and width and screen) then
			return false
		end
		local own = Num(box:GetEffectiveScale()) or 1
		local ui = Num(UIParent:GetEffectiveScale()) or 1
		return left * own + width * (Num(menu:GetEffectiveScale()) or own) > screen * ui + 0.5
	end

	-- under the box, or over it when there is no room below: the pictures
	-- right under it, inside the host; a list left under it, on the screen
	-- (a window as small as Edit Layout's bar would put every list over it),
	-- by the box's right instead when it would pass the screen's right edge
	local function PlaceMenu(menu, box, list)
		menu:ClearAllPoints()
		local below = Num(box:GetBottom())
		local floor = list and 0 or Num(menu.host:GetBottom())
		local h = Num(menu:GetHeight()) or 0
		local gap = list and LIST_GAP or MENU_GAP
		local up = below and floor and below - floor < h + gap + (list and 0 or MENU_PAD)
		if list then
			local right = PastRight(menu, box)
			if up then
				menu:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", box, right and "TOPRIGHT" or "TOPLEFT", 0, gap)
			else
				menu:SetPoint(right and "TOPRIGHT" or "TOPLEFT", box, right and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -gap)
			end
		elseif up then
			menu:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", 0, gap)
		else
			menu:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -gap)
		end
	end

	function Menu.Open(menu, box)
		local list = box.melloList
		local entries = list and box.melloValues or box.melloChoices
		if not (entries and #entries > 0) then
			return
		end
		if openMenus[menu] then
			Menu.Close(menu)
		end
		if list then
			LayList(menu, box)
		else
			LayTiles(menu, box)
		end
		PlaceMenu(menu, box, list)
		-- over the page and every row of it (a sleeping row's cover too), the
		-- catcher right under it
		local level = math.max(Num(box:GetFrameLevel()) or 0, Num(menu.host:GetFrameLevel()) or 0) + MENU_LIFT
		menu.catcher:SetFrameLevel(level)
		menu:SetFrameLevel(level + 2)
		menu.box = box
		openMenus[menu] = true
		local scroll = ScrollOf(box, menu.host)
		menu.scroll, menu.scrollAt = scroll, scroll and Num(scroll:GetVerticalScroll()) or nil
		if scroll and not scrollsHooked[scroll] then
			scrollsHooked[scroll] = true
			Perf.hooksecurefunc(scroll, "SetVerticalScroll", PictureScrolled)
		end
		-- (pictures close as a fight starts; a list stays, as the game's menu did)
		if not list then
			menu:RegisterEvent("PLAYER_REGEN_DISABLED")
		end
		menu:EnableMouseWheel(list and true or false)
		local skin = menu.skin
		if skin and skin.HoldEscape then
			skin:HoldEscape(true)
		end
		menu.catcher:Show()
		menu:Show()
		MelloUI:PlayUISound("tab")
	end

	function Menu.Close(menu)
		if not openMenus[menu] then
			return
		end
		openMenus[menu] = nil
		local box = menu.box
		menu.box = nil
		menu:UnregisterEvent("PLAYER_REGEN_DISABLED")
		-- (a tile's tooltip goes with it: the pointer may still be on it)
		local owner = GameTooltip:GetOwner()
		if owner and owner.menu == menu then
			GameTooltip:Hide()
		end
		menu.catcher:Hide()
		menu:Hide()
		local skin = menu.skin
		if skin and skin.HoldEscape then
			skin:HoldEscape(false)
		end
		-- (the box's try ended last, guarded: the list closed whatever it does)
		if box and box.melloTry then
			pcall(box.melloTry, nil)
		end
	end

	local PictureBoxClick = Shared("OnClick on a picture row's box", function(box)
		if InCombatLockdown() then
			W.ShowTooltip(box, box.tipTitle or "", nil, NOT_IN_COMBAT)
			return
		end
		local host = box.melloHost
		if not host then
			return
		end
		local menu = W.PictureMenu(host, box.melloSkin)
		if menu.box == box then
			Menu.Close(menu)
		else
			Menu.Open(menu, box)
		end
	end, "script")

	-- the box hidden (its tab or page switched away, its window closed): its
	-- flyout with it (a picture row's box or a dropdown's)
	local PictureBoxHidden = Shared("OnHide on a picture row's box or a dropdown", function(box)
		local menu = box.melloHost and menuOf[box.melloHost]
		if menu and menu.box == box then
			Menu.Close(menu)
		end
	end, "script")
	Flyout.BoxHidden = PictureBoxHidden

	-- the window a dropdown lies in, its flyout's host: the nearest frame up
	-- its parents that has a shell (Kit:ShellOf: the configurator, the
	-- installer, the Restock List), else the top one under UIParent (Edit
	-- Layout's bar and box); nil for a box on UIParent itself
	local function HostOf(box)
		local K = KitNow()
		local f, top = box:GetParent(), nil
		for _ = 1, 30 do
			if not f or f == UIParent then
				break
			end
			if K and K.ShellOf and K:ShellOf(f) then
				return f
			end
			top = f
			f = f:GetParent()
		end
		return top
	end

	-- a dropdown's click: its list opened in its window's flyout, or closed
	-- (the same box again); the host found on the first click and kept
	function Flyout.Toggle(box)
		local host = box.melloHost or HostOf(box)
		if not host then
			return
		end
		box.melloHost = host
		local menu = W.PictureMenu(host, box.melloSkin)
		if menu.box == box then
			Menu.Close(menu)
		else
			Menu.Open(menu, box)
		end
	end
	-- (one look C6) the list of any box carrying melloList / melloValues /
	-- melloGet / melloSet / Refresh, opened or closed as a dropdown's (a
	-- designer stage's right-click list)
	W.OpenList = Flyout.Toggle

	-- (its hover a mark of its own over the ground: the palette's hover
	-- painted)
	local PictureBoxEnter = Shared("OnEnter on a picture row's box (hover)", function(box)
		box.lit:Show()
	end, "script")

	local PictureBoxLeave = Shared("OnLeave on a picture row's box (hover)", function(box)
		box.lit:Hide()
	end, "script")

	-- the chosen one's picture and name (drawn again only when it changed)
	local function PictureBoxRefresh(box)
		local choice = box.melloChoices and ChoiceOf(box.melloChoices, box.melloGet())
		if choice == box.shownChoice and box.melloKind == box.shownKind then
			return
		end
		box.shownChoice, box.shownKind = choice, box.melloKind
		box.name:SetText(choice and (choice.label and W.Tr(choice.label) or tostring(choice.value)) or "")
		DrawChoice(box, box.melloKind, choice)
	end

	local function PictureBoxSetChoices(box, choices, kind)
		box.melloChoices = choices
		if kind then
			box.melloKind = kind
		end
		box.shownChoice = false   -- (drawn again)
		PictureBoxHidden(box)     -- (a flyout open on the old list closes)
		box:Refresh()
	end

	function W.PictureRow(parent, y, label, hint, desc, get, set, choices, kind, opts)
		opts = opts or NO_OPTS
		local row = W.Row(parent, y, W.ROW_HEIGHT, label, hint, desc, opts)
		local width = opts.width or PICTURE_W
		local box = CreateFrame("Button", nil, row)
		box:SetSize(width, PICTURE_H)
		box:SetPoint("RIGHT", -14, 0)
		box.fill = box:CreateTexture(nil, "BACKGROUND")
		box.fill:SetAllPoints(box)
		W.Paint(box.fill, "innerPanel", "fill", 1)
		box.lit = box:CreateTexture(nil, "BACKGROUND", nil, 1)
		box.lit:SetAllPoints(box)
		MelloUI.Look.Mark(box.lit, "hover", "hover", 1)
		box.lit:Hide()
		box.edges = Edges(box, "border", "BORDER")
		box.pic = CreateFrame("Frame", nil, box)
		box.pic:SetSize(PICTURE_H, PICTURE_H)
		box.pic:SetPoint("LEFT", box, "LEFT", 0, 0)
		box.layers, box.size = {}, PICTURE_H
		box.none = box.pic:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontNormalSmall")
		box.none:SetPoint("CENTER")
		box.none:SetText(W.Tr("None"))
		W.Paint(box.none, "text", "text")
		box.none:Hide()
		box.name = W.Text(box, "GameFontHighlight", nil, "text")
		box.name:SetPoint("LEFT", box.pic, "RIGHT", 8, 0)
		box.name:SetPoint("RIGHT", box, "RIGHT", -8, 0)
		box.name:SetWordWrap(false)
		box.melloGet, box.melloSet, box.melloChoices, box.melloKind = get, set, choices, kind
		box.melloHost, box.melloSkin = opts.host, opts.skin
		box.shownChoice = false
		box.Refresh, box.SetChoices = PictureBoxRefresh, PictureBoxSetChoices
		Perf.SetScript(box, "OnClick", PictureBoxClick)
		Perf.SetScript(box, "OnHide", PictureBoxHidden)
		Perf.HookScript(box, "OnEnter", PictureBoxEnter)
		Perf.HookScript(box, "OnLeave", PictureBoxLeave)
		ControlTip(box, row, label, desc)
		box:Refresh()
		return Finish(row, box, opts, 14 + width)
	end
end

--------------------------------------------------------------------------------
-- Card: one choice among a few, shown whole (the installer's steps: its skins,
-- layouts, party frames, chat, bags, sounds): a box with a title, a
-- line under it, a tag at its top right (W.Tag: "Recommended") and a picture
-- above the texts when given. ONE "selected" look for the addon, the NavRail
-- marker's: the raised panel's fill, a 2 px selectedTrim edge, the title in
-- gold. At rest the main window's tone at 0.85 (a stripe on the dark inner
-- panel, as rows have it: WINDOW-RULES 2e) inside a 1 px border edge, the
-- title in the text colour. The hover is W.RowPlate's palette wash with its
-- gold edge, none on the selected card (gold on the hover colour is under
-- 4.5:1).
--   local card = W.Card(parent, spec, skin)
--   spec: width (279), height (72), title, text, tag, picture (a texture
--         path) with pictureHeight (40), titleFont ("GameFontNormal"),
--         textFont ("GameFontHighlight"), key (the caller's value: card.key),
--         onClick (a shared fn(card): the caller's pick; the card plays the
--         "tab" sound itself), palette (a palette's id: a palette's card --
--         that palette's swatch where a picture goes, pictureHeight 12 high,
--         the palette's name for a title not given, the id for a key not
--         given, the texts 8 px in from the sides, as the swatch; the
--         installer's Look step)
--   card:SetSelected(on)   card:IsSelected()   card:SetTexts(title, text)
--   card.title, card.text, card.picture, card.tag (the plate's FontString),
--   card.swatch (a palette's card)
-- A frame of the caller's laid on a card that takes the mouse is handed to
-- W.RowPlateChild(card, frame). The approved card is the palette look in both
-- looks; with the kit on (its `skin`: a shell) the chosen card wears the
-- active look too (0.15.0, Kit:SetActive: the one look for whatever is
-- selected). Colours by key only (a new palette paints it again); nothing is
-- made per click or hover.
--------------------------------------------------------------------------------

local cardOn = setmetatable({}, weakKeys)   -- [card] = true while it is the selected one

local function CardSelected(card)
	return cardOn[card] == true
end

-- (the chosen card's active look: WidgetActive, with the flat controls')

-- the cards of each shell, their looks put back at its switches (the chosen
-- card's edge too: Card_SetSelected)
local cardsOf = setmetatable({}, weakKeys)   -- [shell] = { [card] = true } (weak)
local function Cards_OnKit(shell)
	local set = cardsOf[shell]
	if set then
		for card in pairs(set) do
			card:SetSelected(cardOn[card] == true)
		end
	end
end

-- the four edges `px` thick, inside the card's rect (a point set again
-- replaces the one of that name: nothing is cleared, nothing made)
local function CardEdges(card, px)
	local e = card.edges
	e[1]:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
	e[1]:SetPoint("BOTTOMRIGHT", card, "TOPRIGHT", 0, -px)
	e[2]:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, px)
	e[2]:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
	e[3]:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
	e[3]:SetPoint("BOTTOMRIGHT", card, "BOTTOMLEFT", px, 0)
	e[4]:SetPoint("TOPLEFT", card, "TOPRIGHT", -px, 0)
	e[4]:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
end

local function Card_SetSelected(card, on)
	on = on and true or false
	cardOn[card] = on or nil
	W.Paint(card.fill, on and "raisedPanel" or "mainWindow", "fill", on and 1 or 0.85)
	-- the gold edge gives way to the active look while that shows (its ring,
	-- added as light, lies on the edge: gold on gold burned out to a pale
	-- yellow, near white under Obsidian; review 2026-09-28): the resting
	-- 1 px edge under it
	local gold = on and not (card.melloSkin and card.melloSkin.kit)
	CardEdges(card, gold and 2 or 1)
	for i = 1, 4 do
		W.Paint(card.edges[i], gold and "selectedTrim" or "border", "fill", 1)
	end
	W.Paint(card.title, on and "selectedTrim" or "text", "text")
	if on then
		W.RowPlateOff(card)   -- (just picked: its wash goes at once)
	end
	WidgetActive(card.melloSkin, card, on)
end

local function Card_IsSelected(card)
	return cardOn[card] == true
end

local function Card_SetTexts(card, title, text)
	card.title:SetText(W.Tr(title) or "")
	card.text:SetText(W.Tr(text) or "")
end

local CardClick = Shared("OnClick on MelloUI's cards", function(card)
	MelloUI:PlayUISound("tab")
	if card.melloClick then
		card.melloClick(card)
	end
end, "script")

local CARD_PLATE = { look = "palette", edge = true, selected = CardSelected }

function W.Card(parent, spec, skin)
	spec = spec or NO_OPTS
	local card = CreateFrame("Button", nil, parent)
	local width = spec.width or 279
	card:SetSize(width, spec.height or 72)
	local palette = spec.palette
	card.key, card.melloClick = spec.key == nil and palette or spec.key, spec.onClick
	card.fill = card:CreateTexture(nil, "BACKGROUND", nil, 0)
	card.fill:SetAllPoints(card)
	card.edges = {}
	for i = 1, 4 do
		card.edges[i] = card:CreateTexture(nil, "BORDER")
	end
	local top, inset = -10, 12
	if palette then
		-- a palette's card: its swatch (a picture of that palette) where a
		-- picture goes, its name under it at the swatch's own 8 px sides (a
		-- small card: "Royal Azure Vibrant" needs 116 of a 136 card's 120)
		local h = spec.pictureHeight or 12
		card.swatch = W.PaletteSwatch(card, { id = palette, width = width - 16, height = h })
		card.swatch:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -8)
		top, inset = -8 - h - 4, 8
	elseif spec.picture then
		local h = spec.pictureHeight or 40
		card.picture = card:CreateTexture(nil, "ARTWORK")
		card.picture:SetTexture(spec.picture)
		card.picture:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -8)
		card.picture:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
		card.picture:SetHeight(h)
		top = -8 - h - 6
	end
	card.title = W.Text(card, spec.titleFont or "GameFontNormal", W.Tr(spec.title) or (palette and W.PaletteName(palette)))
	card.title:SetWordWrap(false)
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", inset, top)
	if spec.tag then
		-- the tag (W.Tag, the one plate: an option's New tag is the same)
		card.tag = W.Tag(card, spec.tag)
		card.tag:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, top - 1)
		card.tagPlate = card.tag.plate
		card.title:SetPoint("RIGHT", card.tagPlate, "LEFT", -8, 0)
	else
		card.title:SetPoint("RIGHT", card, "RIGHT", -inset, 0)
	end
	card.text = W.Text(card, spec.textFont or "GameFontHighlight", W.Tr(spec.text), "text")
	card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -5)
	card.text:SetPoint("RIGHT", card, "RIGHT", -inset, 0)
	card.text:SetWordWrap(true)
	card.SetSelected, card.IsSelected, card.SetTexts = Card_SetSelected, Card_IsSelected, Card_SetTexts
	W.RowPlate(card, CARD_PLATE)
	Perf.SetScript(card, "OnClick", CardClick)
	if skin and skin.OnKit then
		-- (the chosen card's active look follows the window's look switch)
		card.melloSkin = skin
		local set = cardsOf[skin]
		if not set then
			set = setmetatable({}, weakKeys)
			cardsOf[skin] = set
		end
		set[card] = true
		skin:OnKit(Cards_OnKit)
	end
	card:SetSelected(false)
	return card
end

--------------------------------------------------------------------------------
-- Palettes (0.14.0, user 2026-09-26: "A palette picker"): ONE set of parts
-- for every place a palette is chosen -- the configurator's Look page (its
-- Home shows it), the installer's Look step -- over Core's registry
-- (MelloUI.Palettes, MelloUI:PaletteId, MelloUI:SetPalette, which applies it).
--   W.PaletteSwatch(parent, spec) -> swatch   a frame: a strip of chips, one
--       per role of W.SWATCH_ROLES left to right, inside a 1 px `border`
--       edge (swatch.back, painted by key: it follows a switch)
--     spec: width (60), height (14), id (a palette's id: a PICTURE of that
--       palette, its own colours, which no switch repaints -- the installer's
--       cards, a list of palettes; nil: the palette in use, its chips painted
--       by key, so a switch paints them again -- the Home row)
--     swatch:SetPalette(id)   a picture shows another palette (nil or an
--       unknown id: Ember); the palette in use's swatch is left as it is
--     swatch.chips, swatch.back, swatch.id (nil: the palette in use)
--   W.PaletteValues() -> values   the palettes in their order as a
--       dropdown's values ({ value = id, label = name, tooltip = blurb }),
--       made the first time it is asked for, the same table after
--   W.PaletteName(id) -> name     (Ember's for nil or an unknown id)
--   W.PaletteFill(texture, id, role)   a texture in that palette's colour
--       for `role`: a picture, never repainted (a swatch's chips; the
--       installer's picture of a drafted look)
--   W.Card(parent, { palette = id, ... }, skin)   a palette's card (Card)
-- Nothing is made at load; a swatch makes its textures once, and showing
-- another palette makes nothing.
--------------------------------------------------------------------------------

W.SWATCH_ROLES = { "mainWindow", "selectedTab", "trim", "selectedTrim", "text" }

-- a palette's entry in Core's registry (Ember's for nil or an unknown id:
-- Core's one rule, MelloUI:KnownPalette)
local function PaletteEntry(id)
	return MelloUI.Palettes[MelloUI:KnownPalette(id)]
end

function W.PaletteName(id)
	return PaletteEntry(id).name
end

-- a texture in one role's colour of a NAMED palette (a picture of that
-- palette -- a swatch's chip, a picture of a drafted look -- which no switch
-- repaints; nil or an unknown id: Ember). Never on a region painted by key.
function W.PaletteFill(region, id, role)
	local c = PaletteEntry(id).roles[role]
	region:SetColorTexture(c[1], c[2], c[3], 1)
end

do
	local values = nil
	-- the painted reskin's choices (0.25.0: the modern look's own palette, Gilded Slate -- `modern` -- is no choice:
	-- it is the palette whenever the reskin's are not, MelloUI:PaintedPalettes)
	function W.PaletteValues()
		if not values then
			values = {}
			for _, id in ipairs(MelloUI.Palettes.order) do
				local entry = MelloUI.Palettes[id]
				if not entry.modern then
					values[#values + 1] = { value = id, label = entry.name, tooltip = entry.blurb }
				end
			end
		end
		return values
	end
end

local function Swatch_SetPalette(swatch, id)
	if swatch.id == nil then
		return   -- (the palette in use: its chips are painted by key)
	end
	local entry = PaletteEntry(id)
	swatch.id = entry.id
	local chips = swatch.chips
	for i = 1, #chips do
		W.PaletteFill(chips[i], entry.id, W.SWATCH_ROLES[i])
	end
end

function W.PaletteSwatch(parent, spec)
	spec = spec or NO_OPTS
	local width, height = spec.width or 60, spec.height or 14
	local swatch = CreateFrame("Frame", nil, parent)
	swatch:SetSize(width, height)
	local roles = W.SWATCH_ROLES
	local n = #roles
	local w = (width - 2) / n
	-- the edge: the swatch's ground in `border`, the chips 1 px inside it
	-- (one texture, not four: a Look step lays seven swatches)
	swatch.back = swatch:CreateTexture(nil, "BACKGROUND")
	swatch.back:SetAllPoints(swatch)
	W.Paint(swatch.back, "border", "fill", 1)
	swatch.chips = {}
	for i = 1, n do
		local chip = swatch:CreateTexture(nil, "ARTWORK")
		chip:SetPoint("TOPLEFT", swatch, "TOPLEFT", 1 + (i - 1) * w, -1)
		chip:SetSize(w, height - 2)
		swatch.chips[i] = chip
		if spec.id == nil then
			W.Paint(chip, roles[i], "fill", 1)
		end
	end
	swatch.SetPalette = Swatch_SetPalette
	if spec.id ~= nil then
		swatch.id = false   -- (a picture: SetPalette fills it)
		swatch:SetPalette(spec.id)
	end
	return swatch
end

--------------------------------------------------------------------------------
-- Chips (one look, the designers: the Parts line, the stage's state chips, Edit Layout's picker, the Group Frames
-- designer's styles -- one system, rule 5): small quiet buttons side by side (1.2.4, the user's pick A of
-- MelloUI-BuildData/output/config_chips_sketch, 2026-10-28; before them the pills): each in a hairline box (`trim`;
-- the Default skin: the game's grey, `border`), its label `text`; the picked one's box `selectedTrim` over a faint
-- `selectedTab` fill, its label `selectedTrim` (`text` under Oldschool's painted reskin, as the tabs'); the one under
-- the pointer on the `hover` fill. The Default skin's labels the game's gold, the picked one and the one under the
-- pointer white. Wrapping at `width`, or one row (`row`: tightened, then scrolled -- W.ScrollRow -- never two).
--   W.Chips(parent, spec) -> chips   spec: height (22), gap (6; a row's tightens to 4), width (the room; nil: one
--     line; a row's must be given), row (true: one row in `width` -- its padding and gaps tightened, CHIP_PADS and
--     CHIP_GAPS in turn, then scrolled, the picked one kept in view), select (false: no pick kept), onPick fn(chips,
--     key, item), ink ("box": in ink on parchment, Oldschool's configurator -- InkLook), paper (a row in ink: the
--     picture it lies on, its cut edges banded with it -- W.ScrollRow's paper)
--   chips:SetItems(items)   items { key, label, state (nil, "off" or "locked": dimmed, still clickable), new (its New
--     tag), tip }; the buttons come from the chips' own pool (a set again makes none after the first); a pick no
--     longer among them is let go; a row back at its start
--   chips:Select(key)   chips:Selected()   chips:SetState(key, state)
--   chips:Height()   the height the rows take
--   chips:Refit()   measured and laid again (a font changed: the Interface text size, a skin), as they are
--   chips:SetFlow(width, wrap)   a row's chips at another width, wrapping there (`wrap`: a narrow column -- the
--     configurator's Parts under a stage beside its rows, layout C) or back in their row; measured and laid again
--   chips.buttons, chips.count, chips.row (a row's W.ScrollRow), chips.wrap
--------------------------------------------------------------------------------

do
	local CHIP_PADS = { 10, 7 }   -- each side of a chip's label (a row's tightened in turn)
	local CHIP_GAPS = { 6, 4 }    -- between two chips (the same)
	local CHIP_MIN = 36           -- the narrowest chip
	local CHIP_DIM = 0.5          -- an "off" or "locked" chip's alpha
	-- the colours' strengths: the box at rest, the picked one's fill, the hover's; the Default skin's own (its
	-- `selectedTab` the game's gold darkened (el-06: 0.3 of it the sketch's 0.08 of the full gold) and its `hover`
	-- its grey: a faint touch of each, the sketch's)
	local QUIET = { edge = 0.45, fill = 0.55, hover = 1, gameEdge = 0.7, gameFill = 0.3, gameHover = 0.2 }
	-- a row's scroll (W.ScrollRow): nothing round a chip to keep clear (a hairline box, a New tag inside it); on
	-- parchment the arrows alone, or banded with the parchment itself where the chips name it (spec.paper)
	local ROW_SPEC = { pad = 2, below = 2, above = 2 }
	local ROW_INK = { pad = 2, below = 2, above = 2, fade = false }

	local ChipEnter = Shared("OnEnter on a chip (tooltip)", function(b)
		local item = b.melloItem
		if item and item.tip then
			W.ShowTooltip(b, item.label or tostring(item.key), item.tip)
		end
	end, "script")

	-- (2026-10-20, the user's sheet: "go all the way with the new icons") the pill: slate in a bronze rim,
	-- the picked one gold (piece_pill_off / piece_pill_on: Tools/make_icons.py PIECES, 256 wide, the picture the top
	-- 60 of 64 rows, its rounded ends `l` and `r` of 256), three slices at the chip's height; its label `text`, gold
	-- under the pointer, dark ink (`mainWindow`) on the gold pill
	local PILL = {
		off = { tex = TEXTURE_PATH .. "Icons\\piece_pill_off", h = 60, l = 25.0, r = 22.7 },
		on = { tex = TEXTURE_PATH .. "Icons\\piece_pill_on", h = 60, l = 23.8, r = 25.4 },
	}

	local function PillSlices(b, layer, sublevel)
		local s = {}
		for i = 1, 3 do
			s[i] = b:CreateTexture(nil, layer, nil, sublevel)
		end
		s[1]:SetPoint("TOPLEFT")
		s[1]:SetPoint("BOTTOMLEFT")
		s[3]:SetPoint("TOPRIGHT")
		s[3]:SetPoint("BOTTOMRIGHT")
		s[2]:SetPoint("TOPLEFT", s[1], "TOPRIGHT")
		s[2]:SetPoint("BOTTOMRIGHT", s[3], "BOTTOMLEFT")
		return s
	end

	local function CutPill(s, p, v, k)
		for i = 1, 3 do
			s[i]:SetTexture(p.tex)
		end
		s[1]:SetTexCoord(0, p.l / 256, 0, v)
		s[1]:SetWidth(p.l * k)
		s[2]:SetTexCoord(p.l / 256, 1 - p.r / 256, 0, v)
		s[3]:SetTexCoord(1 - p.r / 256, 1, 0, v)
		s[3]:SetWidth(p.r * k)
	end

	-- W.Pill(b, state[, light]): a button drawn as the pill, state "off" (slate in a bronze rim) or "on" (gold): its
	-- three slices made on the first call (BACKGROUND 3, under its label), cut at its height then. `light` (0..1):
	-- the same pill again in its HIGHLIGHT layer, added as light in the palette's gold at that strength, so it
	-- brightens under the pointer (asked once, kept). The game menu's MelloUI button (2026-10-20, the user's pick B:
	-- the gold pill; the chips' look until 1.2.4's quiet chips)
	function W.Pill(b, state, light)
		local s = b.melloSlices
		if not s then
			s = PillSlices(b, "BACKGROUND", 3)
			b.melloSlices = s
		end
		if light and not b.melloPillLight then
			local l = PillSlices(b, "HIGHLIGHT", 0)
			for i = 1, 3 do
				l[i]:SetBlendMode("ADD")
				W.Paint(l[i], "selectedTrim", "vertex", light)
			end
			b.melloPillLight = l
			b.melloPill = nil   -- (cut again below, the light with it)
		end
		-- (1.2.4, the Default skin: MelloUI.Skin) the game's Settings tab in the pill's place: Options_Tab, the picked
		-- one the active tab -- its 7 px ends kept, the 1 px middle drawn along (as the game's own tabs)
		local Skin = rawget(MelloUI, "Skin")
		local game = Skin and Skin.IsDefault() or false
		local want = game and ("game " .. state) or state
		if b.melloPill == want then
			return
		end
		b.melloPill = want
		if game then
			local pre = MelloUI.Skin.ART[state == "on" and "tabOn" or "tab"]
			for _, set in ipairs({ s, b.melloPillLight or NO_OPTS }) do
				if set[1] then
					set[1]:SetAtlas(pre .. "Left")
					set[2]:SetAtlas(pre .. "Middle")
					set[3]:SetAtlas(pre .. "Right")
					set[1]:SetWidth(7)
					set[3]:SetWidth(7)
				end
			end
			return
		end
		local p = PILL[state]
		local v, k = p.h / 64, (Num(b:GetHeight()) or 22) / p.h
		CutPill(s, p, v, k)
		if b.melloPillLight then
			CutPill(b.melloPillLight, p, v, k)
		end
	end
	-- the quiet chip as it is: its fill (the picked one's, the hover's, else none), its box, its label
	local function QuietLook(b, picked, on)
		local Skin = rawget(MelloUI, "Skin")
		local game = Skin and Skin.IsDefault() or false
		local lit = on and flatHover[b] and not picked
		local fill = (picked and (game and QUIET.gameFill or QUIET.fill)) or (lit and (game and QUIET.gameHover or
			QUIET.hover)) or 0
		W.Paint(b.melloFill, picked and "selectedTab" or "hover", "fill", fill)
		local edge = (picked and "selectedTrim") or (game and "border") or "trim"
		local alpha = picked and 1 or (game and QUIET.gameEdge or QUIET.edge)
		for i = 1, #b.melloEdges do
			W.Paint(b.melloEdges[i], edge, "fill", alpha)
		end
		local fs = b:GetFontString()
		if fs then
			local key
			if game then
				key = (not on and "mutedText") or ((picked or lit) and "text") or "selectedTrim"
			else
				key = (not on and "mutedText") or (picked and not W.PaintedReskin() and "selectedTrim") or "text"
			end
			W.Paint(fs, key, "text")
		end
	end

	-- (1.2.4, Oldschool's configurator -- the user, 2026-10-27, its preview "hard to read"; their pick 1 of
	-- oldschool_readable_sketch) a chip in ink on the parchment, spec.ink: its label in QuestInk's inks two sizes up
	-- and without an outline, in a thin faded-ink box; the picked one's box and label in the mark ink, a faint wash of
	-- the faded ink under the pointer (the chips sketch's paper)
	local INK_UP = 2
	local INK_A = { edge = 0.55, picked = 0.9, wash = 0.12 }
	local function InkLook(b, picked, on)
		local INK = MelloUI.QuestInk.INK
		local fs, ink = b:GetFontString(), b.melloInk
		local lit = on and flatHover[b] and not picked
		local c = (not on and INK.faded) or (picked and INK.mark) or (lit and INK.title) or INK.text
		if fs then
			-- (its face each time from the button's own font: the template swaps font objects on hover, and the
			-- Fonts module may change the face)
			local base = b.GetNormalFontObject and b:GetNormalFontObject()
			local ok, face, size = false, nil, nil
			if base and base.GetFont then
				ok, face, size = pcall(base.GetFont, base)
			end
			if ok and face and Num(size) then
				MelloUI:SetFace(fs, face, size + INK_UP, "", base)
			end
			fs:SetShadowOffset(0, 0)   -- (ink casts no shadow: under the glyph, unseen)
			fs:SetTextColor(c[1], c[2], c[3], 1)
		end
		local e = picked and INK.mark or INK.faded
		for i = 1, #ink.box do
			ink.box[i]:SetVertexColor(e[1], e[2], e[3], picked and INK_A.picked or INK_A.edge)
		end
		local f = INK.faded
		ink.wash:SetVertexColor(f[1], f[2], f[3], lit and INK_A.wash or 0)
	end

	local function ChipLook(b)
		local chips, item = b.melloChips, b.melloItem
		local picked = (chips and item and chips.picked ~= nil and item.key == chips.picked) and true or false
		local on = b:IsEnabled() and true or false
		if b.melloInk then
			InkLook(b, picked, on)
		else
			QuietLook(b, picked, on)
		end
	end

	-- a chip button made quiet once: the flat button's own fill and edges its box (QuietLook paints them), the Default
	-- skin's panel button art (if a look made it) hidden
	local function MakeQuiet(b)
		local g = b.melloSkinParts
		if g then
			for i = 1, 3 do
				g.plate[i]:Hide()
				g.lit[i]:Hide()
			end
			b.melloSkinParts = nil
		end
		b.melloFill:Show()
		for i = 1, #b.melloEdges do
			b.melloEdges[i]:Show()
		end
		b.melloLook = ChipLook
	end

	-- a chip button made an ink chip once (spec.ink, InkLook): the flat plate hidden, the label off the palette's
	-- paint, two sizes up without an outline, its box and wash made
	local function MakeInk(b)
		b.melloFill:Hide()
		for i = 1, #b.melloEdges do
			b.melloEdges[i]:Hide()
		end
		local fs = b:GetFontString()
		if fs then
			MelloUI.Painter.Unpaint(fs, "text")
		end
		local ink = { box = {} }
		ink.wash = b:CreateTexture(nil, "BACKGROUND", nil, 2)
		ink.wash:SetTexture(WHITE)
		ink.wash:SetAllPoints(b)
		-- (W.Edges' four lines, in ink: not the palette's paint, which a palette switch would lay over them)
		for i = 1, 4 do
			ink.box[i] = b:CreateTexture(nil, "BORDER")
			ink.box[i]:SetTexture(WHITE)
		end
		local e = ink.box
		e[1]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
		e[1]:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 0, -1)
		e[2]:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, 1)
		e[2]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
		e[3]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
		e[3]:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", 1, 0)
		e[4]:SetPoint("TOPLEFT", b, "TOPRIGHT", -1, 0)
		e[4]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
		b.melloInk = ink
		b.melloLook = ChipLook
	end

	-- every chip in its look and alpha; a row's picked one brought into view
	local function Paint(chips)
		local shown
		for i = 1, chips.count do
			local b = chips.buttons[i]
			local item = b.melloItem
			ChipLook(b)
			b:SetAlpha((item.state == "off" or item.state == "locked") and CHIP_DIM or 1)
			if chips.picked ~= nil and item.key == chips.picked then
				shown = b
			end
		end
		if chips.row and not chips.wrap then
			chips.row:Show(shown)
		end
	end

	local ChipClick = Shared("OnClick on a chip", function(b)
		local chips, item = b.melloChips, b.melloItem
		if not (chips and item) then
			return
		end
		MelloUI:PlayUISound("tab")
		if chips.spec.select ~= false then
			chips.picked = item.key
			Paint(chips)
		end
		local fn = chips.spec.onPick
		if fn then
			fn(chips, item.key, item)
		end
	end, "script")

	-- a chip's label measured (at each set): its text and, while its update runs, its New tag
	local function Measure(b, item)
		if b.melloInk then
			ChipLook(b)   -- (the ink's larger face first: the width is the label's in it)
		end
		local fs = b:GetFontString()
		if fs and b.melloCut then
			fs:SetWidth(0)   -- (cut at a lay before: measured whole again)
			b.melloCut = nil
		end
		b.melloTextW = fs and TextWidth(fs) or 24
		local new = item.new ~= nil and MelloUI:IsNew(item.new)
		if new and not b.melloNewTag then
			b.melloNewTag = W.Tag(b, W.NEW)
		end
		W.TagShown(b.melloNewTag, new)
		b.melloTagW = new and (TagSpan(b.melloNewTag) or 0) or 0
	end

	-- a chip as wide as its label and `pad` at each side (its New tag at its right, inside the pad) -> the width
	local function Fit(b, pad)
		if b.melloTagW > 0 then
			b.melloNewTag:ClearAllPoints()
			b.melloNewTag:SetPoint("RIGHT", b, "RIGHT", -(pad - 4 + TAG_PAD_X), 0)
		end
		local w = math.max(CHIP_MIN, math.ceil(b.melloTextW + 2 * pad)) + b.melloTagW
		b:SetWidth(w)
		return w
	end

	-- the chips at padding step `t` (CHIP_PADS[t], CHIP_GAPS[t] unless the spec has a gap) -> the row they make
	local function FitAll(chips, t)
		local width = 0
		for i = 1, chips.count do
			width = width + Fit(chips.buttons[i], CHIP_PADS[t])
		end
		return width + math.max(0, chips.count - 1) * (chips.spec.gap or CHIP_GAPS[t])
	end

	-- what the chips lie on: a row's strip, or the chips themselves (wrapping: a row's too while it wraps)
	local function Holder(chips)
		return chips.row and not chips.wrap and chips.row.strip or chips
	end

	local function Lay(chips)
		local spec = chips.spec
		local h, room = spec.height or 22, Num(spec.width)
		local row = chips.row
		if row then
			-- (a row that wraps lays its chips on itself, its clip hidden; back in the row they go on its strip)
			local holder = Holder(chips)
			for i = 1, chips.count do
				local b = chips.buttons[i]
				if b:GetParent() ~= holder then
					b:SetParent(holder)
				end
			end
			row.clip:SetShown(not chips.wrap)
		end
		if row and room and not chips.wrap then
			-- (one row: tightened step by step, then scrolled -- the user's "Tighten, then scroll")
			local t = 1
			while FitAll(chips, t) > room and t < #CHIP_PADS do
				t = t + 1
			end
			local list = chips.list
			for i = 1, math.max(#list, chips.count) do
				list[i] = i <= chips.count and chips.buttons[i] or nil
			end
			row:Lay(list, room, h, spec.gap or CHIP_GAPS[t])
			chips.rows = chips.count > 0 and 1 or 0
			chips:SetSize(room, h)
			return
		end
		local gap = spec.gap or CHIP_GAPS[1]
		local x, y, rows, widest = 0, 0, 0, 1
		for i = 1, chips.count do
			local b = chips.buttons[i]
			local w = Fit(b, CHIP_PADS[1])
			-- (the in-game test, 2026-11-04: a link chip, "Health Bar Colour: Class (players) / reaction (NPCs)", past its
			-- line's end) a chip wider than the room is cut to it, its label ending in "..."
			if room and w > room then
				w = math.floor(room)
				b:SetWidth(w)
				local fs = b:GetFontString()
				if fs then
					fs:SetWordWrap(false)
					fs:SetWidth(math.max(1, w - 2 * CHIP_PADS[1] - b.melloTagW))
					b.melloCut = true
				end
			end
			if room and x > 0 and x + w > room then
				x, y = 0, y + h + gap
			end
			if x == 0 then
				rows = rows + 1
			end
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", chips, "TOPLEFT", x, -y)
			x = x + w + gap
			widest = math.max(widest, x - gap)
		end
		chips.rows = rows
		-- (a width of its own, never only a height: a frame with one point and no width has no rect in the game, and
		-- nothing anchored to it is drawn -- the user, 2026-10-16: no chips on any designer page)
		chips:SetSize(widest, math.max(1, rows > 0 and (rows * h + (rows - 1) * gap) or 0))
	end

	local function SetItems(chips, items)
		local h = chips.spec.height or 22
		local holder = Holder(chips)
		local found = false
		chips.count = 0
		for i, item in ipairs(type(items) == "table" and items or NO_OPTS) do
			local b = chips.buttons[i]
			if not b then
				b = W.Button(holder, "", CHIP_MIN, nil, { height = h })
				if chips.spec.ink then
					MakeInk(b)
				else
					MakeQuiet(b)
				end
				local Skin = rawget(MelloUI, "Skin")
				if Skin then
					Skin.followers[b] = ChipLook   -- (1.2.4: the skin switched, the chip in its look)
				end
				b.melloChips = chips
				Perf.SetScript(b, "OnClick", ChipClick)
				Perf.HookScript(b, "OnEnter", ChipEnter)
				Perf.HookScript(b, "OnLeave", TipLeave)
				chips.buttons[i] = b
			end
			b.melloItem = item
			b:SetText(item.label and W.Tr(item.label) or tostring(item.key))
			Measure(b, item)
			b:Show()
			chips.count = i
			found = found or (chips.picked ~= nil and item.key == chips.picked)
		end
		for i = chips.count + 1, #chips.buttons do
			chips.buttons[i].melloItem = nil
			chips.buttons[i]:Hide()
		end
		if not found then
			chips.picked = nil
		end
		if chips.row then
			chips.row.shown, chips.row.scroll = nil, 0   -- (new chips: the row from its start)
		end
		Lay(chips)
		Paint(chips)
	end

	local function Select(chips, key)
		chips.picked = key
		Paint(chips)
	end

	local function Selected(chips)
		return chips.picked
	end

	local function SetState(chips, key, state)
		for i = 1, chips.count do
			local item = chips.buttons[i].melloItem
			if item.key == key then
				item.state = state
			end
		end
		Paint(chips)
	end

	local function Height(chips)
		return Num(chips:GetHeight()) or 0
	end

	-- the chips measured and laid again where they are (their labels' font changed: a text size, a skin), a row's
	-- scroll and its picked one kept
	local function Refit(chips)
		for i = 1, chips.count do
			local b = chips.buttons[i]
			Measure(b, b.melloItem)
		end
		Lay(chips)
		Paint(chips)
	end

	-- a row's chips at `width`, wrapping there or in their row (laid with their labels measured anew, as Refit)
	local function SetFlow(chips, width, wrap)
		chips.spec.width = width
		chips.wrap = (wrap and chips.row ~= nil) or nil
		Refit(chips)
	end

	function W.Chips(parent, spec)
		local chips = CreateFrame("Frame", nil, parent)
		chips.spec = type(spec) == "table" and spec or {}
		chips.buttons, chips.count, chips.rows, chips.list = {}, 0, 0, {}
		chips.SetItems, chips.Select, chips.Selected, chips.SetState, chips.Height = SetItems, Select, Selected, SetState,
			Height
		chips.Refit, chips.SetFlow = Refit, SetFlow
		chips:SetSize(1, 1)   -- (a rect from the start: Lay)
		if chips.spec.row then
			local rowSpec = ROW_SPEC
			if chips.spec.ink then
				rowSpec = chips.spec.paper and { pad = 2, below = 2, above = 2, paper = chips.spec.paper } or ROW_INK
			end
			local row = W.ScrollRow(chips, rowSpec)
			row.clip:SetPoint("BOTTOMLEFT", chips, "BOTTOMLEFT", -row.pad, -row.below)
			chips.row = row
		end
		return chips
	end
end

--------------------------------------------------------------------------------
-- NavRail: the configurator's side list AND the installer's steps rail, one
-- code.
--   local rail = W.NavRail(parent, spec)
--   spec: width, rowHeight (30), headerHeight (24), gap (1), iconSize (22;
--         0: no icons), inset (10), numbered (false: "3. Review"), scroll
--         (true: a ScrollFrame whose wheel glides at step 68; false: the box
--         as tall as its rows), box (true: the box -- W.Panel's look, the
--         palette's `innerPanel` in a `border` edge, in both looks:
--         rail.plainParts), skin, iconMaker (fn(row, size, skin) -> an icon
--         with :SetIcon and :SetOn, made once per row; nil: a plain texture),
--         onSelect (a shared fn(rail, key, entry)), clickable (nil: all;
--         fn(rail, key, entry) -> bool), doneGlyph (an atlas shown after a
--         done step's name), bar (a width: a scrolling list's thin scroll
--         bar, W.ThinScrollBar, in its right inset -- shown while the list is
--         taller than its view, following the glide; dragged, the list
--         follows: rail.bar; Suggestion 1 point 6, the configurator's side
--         list), tipAnchor (its rows' and results' tooltips; nil:
--         "ANCHOR_RIGHT" -- the configurator's "ANCHOR_LEFT": off its page),
--         groupGap (0: the room between a group without a header -- a page
--         of its own -- and the groups beside it)
--   rail:SetGroups(groups)   groups = { { key, title (nil: no header),
--                            collapsible, entries = { { key, text, icon,
--                            tip, new } } } }; rows and headers come from a pool
--                            (switching the installer's paths makes no frames).
--                            `new`: true (the caller asked MelloUI:IsNew of
--                            what the entry leads to) or an update's version:
--                            a snug New tag (W.Tag) near the row's right edge,
--                            and on its group's header while the group is
--                            folded; made with the first row or header that
--                            needs one
--   rail:Select(key, instant)   the one marker glides there (0.15 s); the
--                               same key again does nothing
--   rail:SetState(key, state)   nil | "off" (icon dimmed, name kept in the
--                               text colour) | "done" (doneGlyph) | "todo"
--   rail:Fold(groupKey, folded, instant)
--   rail:Reveal(key)   unfolds its group and scrolls the row into view AT
--                      ONCE (a help tip's target); returns the row
--   rail.rows[key], rail.selected, rail.box, rail.content, rail.scroll,
--   rail.glide, rail.marker
-- A search's results in the same list (0.14.0, the configurator's search
-- box; user, 2026-09-26: "search box in the next build"):
--   spec.head (0: none)   a strip that tall at the top of the box, over the
--                         list (rail.head: the caller's control goes there,
--                         the box's search field); the list starts under it
--   spec.resultHeight (38: the least a result row is; taller while the
--                         fonts are: its two lines' sizes and their room,
--                         read at each search, rail.resultHeight),
--                         spec.onResult (a shared fn(rail, entry): a result
--                         clicked)
--   rail:ShowResults(list, n, note)   the groups swapped for list[1..n] (the
--       caller's entries, read as they are laid: `name`, `path` (the small
--       line over it, "Page > Tab"; nil: the name alone; too wide for the
--       row, its first parts are left out -- " > " -- so its end, the part
--       that tells two results apart, stays: measured once per entry for the
--       row's room and font, kept in the entry as `pathShown`), `new` (true:
--       its snug New tag), `full`, `section` and `tip` (the tooltip: the
--       whole path)), one row
--       each from a pool of their own (made once, reused by every search;
--       new ones within the frame's one budget of rows), `note` a quiet line
--       under them (nothing found, how many more); the first one selected
--       (the marker), the list at its top. True when rows are still owed
--       (the budget spent): the caller asks rail:MoreResults() on a later
--       frame (Kit:NextFrame), again while it returns true
--   rail:HideResults(instant)   the groups back as they were (folds, the
--       marker on the selected entry, the list's own scroll)
--   rail:MoveResult(delta)   the marker to the next / previous result, kept
--       in view; rail:SelectResult(i); rail:Result() the selected result's
--       entry (nil: none); rail.resultsShown, rail.resultRows,
--       rail.resultCount, rail.resultIndex, rail.note
-- While results show, Select / SetState / Fold only record (the marker
-- stays on the result); nothing of them runs per frame.
-- Look (the approved sketch, kit or not): entries in the text colour (the
-- palette's muted text is 3.2:1, for large or bold labels only), the
-- selected one in gold on a `raisedPanel` marker with a 2 px gold edge;
-- headers in gold at full size, a folded one in the text colour unless it
-- holds the selected entry. A name is one line, cut at the row's edge, and
-- then shown whole in the row's tooltip.
--------------------------------------------------------------------------------

local Rail = {}
Rail.__index = Rail
local railOf = setmetatable({}, weakKeys)   -- [row or header] = its rail
local PLUS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\btn_expand"     -- (0.25.0: the set's; the game's 1x UI-PlusButton-Up until then)
local MINUS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\btn_collapse"
local RAIL_TAG_IN = 2    -- a New tag's (snug) plate inside the row's right edge
local RAIL_TAG_GAP = 3   -- a name to its New tag's plate

local function IsSelected(row)
	local rail = railOf[row]
	return rail ~= nil and rail.selected == row.key
end

local RowClick = Shared("OnClick on a NavRail entry", function(row)
	local rail = railOf[row]
	if rail and rail.spec.onSelect then
		rail.spec.onSelect(rail, row.key, row.entry)
	end
end, "script")

local HeaderClick = Shared("OnClick on a NavRail group", function(header)
	local rail = railOf[header]
	if rail then
		rail:Fold(header.key, not rail.folded[header.key])
	end
end, "script")

-- the row's tooltip: the full name when the row cuts it (one line, word wrap
-- off), then the entry's tip; with neither, none. Hooked after RowPlate's
-- pair, so the wash and the tooltip both run on one enter.
local RailTipEnter = Shared("OnEnter on a NavRail entry (tooltip)", function(row)
	local icon = row.icon
	if icon and icon.SetHovered and icon:IsShown() then
		icon:SetHovered(true)
	end
	local e = row.entry
	local clippedName = row.text.IsTruncated and row.text:IsTruncated()
	local tip = e and W.Tr(e.tip)
	if not (clippedName or tip) then
		return
	end
	local P = MelloUI.Look.TipPalette()   -- (the palette's gold and text colour)
	local gold, text = P.selectedTrim, P.text
	local rail = railOf[row]
	GameTooltip:SetOwner(row, rail and rail.spec.tipAnchor or "ANCHOR_RIGHT")
	if clippedName then
		GameTooltip:SetText(row.text:GetText(), gold[1], gold[2], gold[3], 1, true)
		if tip then
			GameTooltip:AddLine(tip, text[1], text[2], text[3], true)
		end
	else
		GameTooltip:SetText(tip, text[1], text[2], text[3], 1, true)
	end
	GameTooltip:Show()
end, "script")

local RailTipLeave = Shared("OnLeave on a NavRail entry (tooltip)", function(row)
	local icon = row.icon
	if icon and icon.SetHovered and icon:IsShown() then
		icon:SetHovered(false)
	end
	if GameTooltip:IsOwned(row) then
		GameTooltip:Hide()
	end
end, "script")

-- a kit rep shown or hidden (its holder when the rep has no SetShown)
local function RepShown(rep, shown)
	if not rep then
		return
	end
	if rep.SetShown then
		rep:SetShown(shown)
	elseif rep.object then
		rep.object:SetShown(shown)
	end
end

-- The marker's active look: on a list of text rows always (the installer's
-- steps), on a list of icon boxes while a search's results show (the chosen
-- entry's icon box wears it otherwise; a result row has none). Its own gold
-- edge gives way while the look shows (the look's ring over it burned out to
-- a pale yellow; review 2026-09-28)
local function MarkerLook(rail)
	local shell = rail.lookShell
	if not shell then
		return
	end
	local on = (rail.activeMarker or rail.resultsShown) and true or false
	WidgetActive(shell, rail.marker, on)
	rail.marker.edge:SetShown(not (on and shell.kit))
end

-- the rails of each shell, their glyphs and states put back at its switches
local railsOf = setmetatable({}, weakKeys)   -- [shell] = { [rail] = true } (weak)
local function Rails_OnKit(shell)
	local set = railsOf[shell]
	if set then
		for rail in pairs(set) do
			rail:Paint()
			MarkerLook(rail)
		end
	end
end

-- the kit's look of the rail's header glyphs (through skin:Kit)
local function DressHeader(K, h, skin)
	h.plusRep = skin:Replace(h.glyph, { as = "common-button-list-plus", button = h, rect = h.glyph })
	h.minusRep = skin:Replace(h.glyph, { as = "common-button-list-minus", button = h, rect = h.glyph })
	local rail = railOf[h]
	if rail then
		rail:Paint()
	end
end

local function NewRow(rail)
	local spec = rail.spec
	local row = CreateFrame("Button", nil, rail.content)
	row:SetHeight(spec.rowHeight)
	row:SetFrameLevel(rail.content:GetFrameLevel() + 1)
	row.text = row:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontHighlight")
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	W.RowPlate(row, { look = "palette", strength = 0.5, edge = false, selected = IsSelected })
	Perf.HookScript(row, "OnEnter", RailTipEnter)
	Perf.HookScript(row, "OnLeave", RailTipLeave)
	if spec.doneGlyph then
		-- (made with the row: a pooled row may carry a done step later)
		row.check = row:CreateTexture(nil, "OVERLAY")
		row.check:SetSize(14, 14)
		row.check:SetPoint("RIGHT", -6, 0)
		row.check:SetAtlas(spec.doneGlyph)
		row.check:Hide()
	end
	Perf.SetScript(row, "OnClick", RowClick)
	railOf[row] = rail
	return row
end

local function NewHeader(rail)
	local h = CreateFrame("Button", nil, rail.content)
	h:SetHeight(rail.spec.headerHeight)
	h:SetFrameLevel(rail.content:GetFrameLevel() + 1)
	h.text = h:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontNormal")
	h.text:SetJustifyH("LEFT")
	h.text:SetWordWrap(false)
	h.text:SetPoint("LEFT", 26, 0)
	h.text:SetPoint("RIGHT", -6, 0)
	h.glyph = h:CreateTexture(nil, "ARTWORK")
	h.glyph:SetSize(14, 14)
	h.glyph:SetPoint("LEFT", 6, 0)
	Perf.SetScript(h, "OnClick", HeaderClick)
	railOf[h] = rail
	local skin = rail.spec.skin
	if skin then
		skin:Kit(DressHeader, h, skin)
	end
	return h
end

function W.NavRail(parent, spec)
	spec.rowHeight = spec.rowHeight or 30
	spec.headerHeight = spec.headerHeight or 24
	spec.gap = spec.gap or 1
	spec.inset = spec.inset or 10
	spec.iconSize = spec.iconSize or 22
	spec.head = spec.head or 0
	spec.resultHeight = spec.resultHeight or 38
	local rail = setmetatable({ spec = spec, rows = {}, headers = {}, order = {}, folded = {}, groupOf = {},
		state = {}, rowPool = {}, headerPool = {}, selected = nil, resultRows = {}, resultCount = 0,
		resultsShown = false, resultHeight = spec.resultHeight }, Rail)
	local skin = spec.skin
	local box = CreateFrame("Frame", nil, parent)
	box:SetWidth(spec.width)
	rail.box = box
	if spec.box ~= false then
		-- (W.Panel's look in both looks, 0.15.0: the kit's list box, L1, is
		-- the game windows')
		local fill, edges = PanelLook(box, 1)
		rail.plainParts = edges   -- (the four edges, then the fill)
		rail.plainParts[5] = fill
	end
	rail.width = spec.width - 2 * spec.inset   -- the rows' width
	-- (the caller's strip over the list: the configurator's search box)
	local top = spec.inset + spec.head
	if spec.head > 0 then
		rail.head = CreateFrame("Frame", nil, box)
		rail.head:SetPoint("TOPLEFT", spec.inset, -spec.inset)
		rail.head:SetPoint("TOPRIGHT", -spec.inset, -spec.inset)
		rail.head:SetHeight(spec.head)
	end
	if spec.scroll ~= false then
		local scroll = CreateFrame("ScrollFrame", nil, box)
		scroll:SetPoint("TOPLEFT", spec.inset, -top)
		scroll:SetPoint("BOTTOMRIGHT", -spec.inset, spec.inset)
		rail.content = CreateFrame("Frame", nil, scroll)
		rail.content:SetWidth(rail.width)
		scroll:SetScrollChild(rail.content)
		rail.scroll = scroll
		rail.glide = MelloUI.Anim:Glide(scroll, { step = 68 })
		if spec.bar then
			local bar = W.ThinScrollBar(box, spec.bar)
			local x = -math.floor((spec.inset - spec.bar) / 2)
			bar:SetPoint("TOPRIGHT", box, "TOPRIGHT", x, -top)
			bar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", x, spec.inset)
			bar:SetMinMaxValues(0, 0)
			bar:SetValue(0)
			bar:Hide()
			railOf[bar], railOf[scroll] = rail, rail
			Perf.SetScript(bar, "OnValueChanged", Rail.BarMoved)
			Perf.hooksecurefunc(scroll, "SetVerticalScroll", Rail.ListScrolled)   -- (our own ScrollFrame, as the glide)
			Perf.HookScript(scroll, "OnSizeChanged", Rail.ListSized)
			rail.bar = bar
		end
	else
		rail.content = CreateFrame("Frame", nil, box)
		rail.content:SetPoint("TOPLEFT", spec.inset, -top)
		rail.content:SetWidth(rail.width)
	end
	-- the one marker, at the content's level; the rows one above it, so their
	-- text draws over it
	local marker = CreateFrame("Frame", nil, rail.content)
	marker:SetFrameLevel(rail.content:GetFrameLevel())
	marker:SetHeight(spec.rowHeight)
	rail.markerHeight = spec.rowHeight
	marker.fill = marker:CreateTexture(nil, "BACKGROUND")
	marker.fill:SetAllPoints(marker)
	MelloUI.Look.Mark(marker.fill, "selected", "raisedPanel", 1)
	marker.edge = marker:CreateTexture(nil, "BORDER")
	marker.edge:SetWidth(2)
	marker.edge:SetPoint("TOPLEFT")
	marker.edge:SetPoint("BOTTOMLEFT")
	W.Paint(marker.edge, "selectedTrim", "fill", 1)
	marker:SetPoint("TOPLEFT", rail.content, "TOPLEFT", 0, 0)
	marker:SetWidth(rail.width)
	marker:Hide()
	rail.marker = marker
	if skin and skin.OnKit then
		local set = railsOf[skin]
		if not set then
			set = setmetatable({}, weakKeys)
			railsOf[skin] = set
		end
		set[rail] = true
		skin:OnKit(Rails_OnKit)
		-- the active look on the marker, shown and gliding with it (0.15.0),
		-- where the rows carry no icon box of their own to wear it (the
		-- installer's steps; the configurator's side list lights the chosen
		-- entry's icon box instead, and its search results the marker:
		-- MarkerLook); made on the marker's first show
		rail.lookShell = skin
		rail.activeMarker = not (spec.iconSize > 0 and spec.iconMaker) or nil
		MarkerLook(rail)
	end
	return rail
end

function Rail:SetGroups(groups)
	local spec = self.spec
	-- (a search's results give the list back first: the groups are laid anew)
	if self.resultsShown then
		self:HideResults(true)
	end
	-- every row and header back to the pools, then taken again in order
	for key, row in pairs(self.rows) do
		row:Hide()
		W.RowPlateOff(row)
		self.rowPool[#self.rowPool + 1] = row
		self.rows[key] = nil
	end
	for key, h in pairs(self.headers) do
		h:Hide()
		self.headerPool[#self.headerPool + 1] = h
		self.headers[key] = nil
	end
	for i = #self.order, 1, -1 do
		self.order[i] = nil
	end
	for key in pairs(self.groupOf) do
		self.groupOf[key] = nil
	end
	local n = 0
	local right = spec.doneGlyph and -24 or -6
	for gi, g in ipairs(groups) do
		local gkey = g.key or gi
		if g.title then
			local h = table.remove(self.headerPool) or NewHeader(self)
			h.key, h.collapsible = gkey, g.collapsible
			h.text:SetText(W.Tr(g.title))
			h:EnableMouse(g.collapsible and true or false)
			h.glyph:SetShown(g.collapsible and true or false)
			-- (2026-10-20) a group's emblem (its `icon`, MelloUI's icon set, bare) between the fold and the title
			if g.icon then
				if not h.emblem then
					h.emblem = h:CreateTexture(nil, "ARTWORK")
					h.emblem:SetSize(18, 18)
					h.emblem:SetPoint("LEFT", 24, 0)
				end
				MelloUI.Icons.Set(h.emblem, g.icon, 18)   -- (2026-10-21: the copy for its size)
				h.emblem:Show()
				h.text:SetPoint("LEFT", 46, 0)
			else
				if h.emblem then
					h.emblem:Hide()
				end
				h.text:SetPoint("LEFT", 26, 0)
			end
			self.headers[gkey] = h
			self.order[#self.order + 1] = h
		end
		local groupNew = false
		for _, e in ipairs(g.entries) do
			n = n + 1
			local row = table.remove(self.rowPool) or NewRow(self)
			row.key, row.entry, row.group = e.key, e, gkey
			row.text:SetText(spec.numbered and (n .. ". " .. W.Tr(e.text)) or W.Tr(e.text))
			row.text:ClearAllPoints()
			local x = 8
			if spec.iconSize > 0 and e.icon then
				if not row.icon then
					-- made once per row: the window's icon maker (the
					-- configurator's IconBox with the Button Border rim) or a
					-- plain texture
					row.icon = spec.iconMaker and spec.iconMaker(row, spec.iconSize, spec.skin)
						or row:CreateTexture(nil, "ARTWORK")
					row.icon:SetSize(spec.iconSize, spec.iconSize)
					row.icon:SetPoint("LEFT", 8, 0)
					if row.icon.EnableMouse then
						row.icon:EnableMouse(false)
					end
				end
				local icon = row.icon
				if icon.SetIcon then
					icon:SetIcon(e.icon)
				else
					MelloUI.Icons.Set(icon, e.icon, spec.iconSize)
				end
				icon:Show()
				x = 8 + spec.iconSize + 8
			elseif row.icon then
				row.icon:Hide()
			end
			row.text:SetPoint("LEFT", x, 0)
			-- a New tag at the right (snug, near the row's edge: the name
			-- keeps its room -- "UI Modifications" whole at the largest Font
			-- Style), the name cut before it only when it must be
			local tagged = Shows(e.new)
			if tagged and not row.newTag then
				row.newTag = W.Tag(row, W.NEW, true)
				row.newTag:SetPoint("RIGHT", row, "RIGHT", (spec.doneGlyph and right or -RAIL_TAG_IN) - TAG_SNUG_X, 0)
			end
			W.TagShown(row.newTag, tagged)
			if tagged then
				row.text:SetPoint("RIGHT", row.newTag.plate, "LEFT", -RAIL_TAG_GAP, 0)
				groupNew = true
			else
				row.text:SetPoint("RIGHT", right, 0)
			end
			local click = spec.clickable == nil or spec.clickable(self, e.key, e)
			row:EnableMouse(click and true or false)
			self.rows[e.key] = row
			self.groupOf[e.key] = gkey
			self.order[#self.order + 1] = row
		end
		local h = self.headers[gkey]
		if h then
			h.holdsNew = groupNew
			if groupNew and not h.newTag then
				h.newTag = W.Tag(h, W.NEW, true)
				h.newTag:SetPoint("RIGHT", h, "RIGHT", -(RAIL_TAG_IN + TAG_SNUG_X), 0)
				W.TagShown(h.newTag, false)
			end
		end
	end
	self:Layout(true)
	self:Paint()
end

-- the rows and headers from the top, the folded groups' rows hidden (coming
-- back they fade in, 0.12 s); the marker put on the selected row at once (a
-- fold is not a move). Each is held by ONE anchor, its top left, at the
-- content's width (the marker's glide moves that one anchor).
function Rail:Layout(instant)
	-- (while a search's results show, the groups stay hidden: HideResults
	-- lays them again)
	if self.resultsShown then
		return
	end
	local spec = self.spec
	local content = self.content
	local y, last = 0, nil
	for _, f in ipairs(self.order) do
		local isRow = f.entry ~= nil
		if isRow and self.folded[f.group] then
			f:Hide()
		else
			-- (Suggestion 1 point 6; the in-game test, 2026-11-04: Chat right under Damage Meter read as one of
			-- "Frames and bars") a group without a header stands spec.groupGap apart from the groups beside it
			local g = isRow and f.group or f.key
			if last ~= nil and g ~= last and not (self.headers[g] and self.headers[last]) then
				y = y + (spec.groupGap or 0)
			end
			last = g
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
			f:SetWidth(self.width)
			if isRow and not f:IsShown() and not instant then
				MelloUI.Anim:FadeIn(f, 0.12)
			else
				f:Show()
			end
			f.y = y
			y = y + (isRow and spec.rowHeight or spec.headerHeight) + spec.gap
		end
	end
	content:SetHeight(math.max(y, 1))
	if not self.scroll then
		self.box:SetHeight(math.max(y, 1) + 2 * spec.inset + spec.head)
	end
	self:PlaceMarker(true)
	self:BarRange()
end

-- (Suggestion 1 point 6) the list's thin bar (spec.bar): its range the list's height past its view, shown while there
-- is one, its thumb the view's share, its value the list's scroll; a drag moves the list, the list's scroll the bar
Rail.BarMoved = Shared("OnValueChanged on a NavRail's scroll bar", function(bar, value)
	local rail = railOf[bar]
	if rail and not rail.barSync and rail.glide then
		rail.glide:Jump(Num(value) or 0)
	end
end, "script")
Rail.ListScrolled = Shared("SetVerticalScroll on a NavRail's list (its bar)", function(scroll, offset)
	local rail = railOf[scroll]
	local bar = rail and rail.bar
	if bar then
		rail.barSync = true
		bar:SetValue(Num(offset) or 0)
		rail.barSync = nil
	end
end, "hook")
Rail.ListSized = Shared("OnSizeChanged on a NavRail's list (its bar)", function(scroll)
	local rail = railOf[scroll]
	if rail then
		rail:BarRange()
	end
end, "script")
function Rail:BarRange()
	local bar = self.bar
	if not bar then
		return
	end
	local view = Num(self.scroll:GetHeight()) or 0
	local range = math.max(0, math.floor((Num(self.content:GetHeight()) or 0) - view + 0.5))
	self.barSync = true
	bar:SetMinMaxValues(0, range)
	bar:SetValue(math.min(self.glide and self.glide.pos or 0, range))
	self.barSync = nil
	bar:SetShown(range > 0)
	if range > 0 and view > 0 then
		bar.thumb:SetHeight(math.max(16, (Num(bar:GetHeight()) or view) * view / (view + range)))
	end
end

-- the one marker on `row` (an entry's, or a search result's: its height),
-- gliding there unless `instant`; hidden when there is none on show
local function MarkRow(rail, row, height, instant)
	local marker = rail.marker
	local Anim = MelloUI.Anim
	if not (row and row:IsShown()) then
		Anim:Stop(marker)
		marker:Hide()
		return
	end
	if rail.markerHeight ~= height then
		rail.markerHeight = height
		marker:SetHeight(height)
	end
	local y = -row.y
	if instant or not marker:IsShown() then
		Anim:Stop(marker, "y")
		marker:ClearAllPoints()
		marker:SetPoint("TOPLEFT", rail.content, "TOPLEFT", 0, y)
		marker:Show()
	else
		Anim:To(marker, "y", y, 0.15, "outCubic")
	end
end

function Rail:PlaceMarker(instant)
	if self.resultsShown then
		MarkRow(self, self.resultIndex and self.resultRows[self.resultIndex], self.resultHeight, instant)
		return
	end
	MarkRow(self, self.selected and self.rows[self.selected], self.spec.rowHeight, instant)
end

-- the texts, icons, glyphs as the state is: gold on the selected entry, every
-- other one in the text colour; a module that is off shows it on its icon
-- (desaturated, 0.45); a done step its glyph; a folded group holding the
-- selected entry its header in gold
function Rail:Paint()
	local skin = self.spec.skin
	for key, row in pairs(self.rows) do
		local st = self.state[key]
		local selected = key == self.selected
		W.Paint(row.text, selected and "selectedTrim" or "text", "text")
		local icon = row.icon
		if icon then
			if icon.SetOn then
				icon:SetOn(st ~= "off")
			else
				icon:SetAlpha(st == "off" and 0.45 or 1)
			end
			if icon.SetSelected then
				icon:SetSelected(selected)
			end
		end
		if row.check then
			row.check:SetShown(st == "done")
		end
	end
	for gkey, h in pairs(self.headers) do
		local folded = self.folded[gkey] and true or false
		local holds = folded and self.selected ~= nil and self.groupOf[self.selected] == gkey
		W.Paint(h.text, (holds or not folded) and "selectedTrim" or "text", "text")
		-- a folded group holding a New entry: its tag on the header, the
		-- title cut before it (only when that changes)
		local tagShown = folded and h.holdsNew and true or false
		if h.newTag and h.tagShown ~= tagShown then
			h.tagShown = tagShown
			W.TagShown(h.newTag, tagShown)
			h.text:SetPoint("RIGHT", tagShown and h.newTag.plate or h, tagShown and "LEFT" or "RIGHT", tagShown and -RAIL_TAG_GAP or -6, 0)
		end
		MelloUI.Icons.Set(h.glyph, folded and PLUS or MINUS, 14)
		-- (the kit's glyphs only while its look is on: a switch off disabled them)
		local kitOpen = h.collapsible and skin and skin.kit and true or false
		RepShown(h.plusRep, kitOpen and folded)
		RepShown(h.minusRep, kitOpen and not folded)
	end
	if self.resultsShown then
		for i = 1, self.resultCount do
			local row = self.resultRows[i]
			W.Paint(row.label, i == self.resultIndex and "selectedTrim" or "text", "text")
		end
	end
end

function Rail:Select(key, instant)
	if key == self.selected then
		return
	end
	self.selected = key
	local row = key and self.rows[key]
	if row then
		W.RowPlateOff(row)
	end
	self:PlaceMarker(instant)
	self:Paint()
end

function Rail:SetState(key, state)
	if self.state[key] ~= state then
		self.state[key] = state
		self:Paint()
	end
end

function Rail:Fold(gkey, folded, instant)
	folded = folded and true or false
	if (self.folded[gkey] or false) == folded then
		return
	end
	self.folded[gkey] = folded or nil
	self:Layout(instant)
	self:Paint()
end

function Rail:Reveal(key)
	local row = self.rows[key]
	if not row then
		return nil
	end
	local gkey = self.groupOf[key]
	if self.folded[gkey] then
		self:Fold(gkey, false, true)
	end
	if self.glide and self.scroll then
		local top, height = row.y, self.scroll:GetHeight()
		local offset = self.glide.pos or 0
		if top < offset then
			self.glide:Jump(top)
		elseif top + self.spec.rowHeight > offset + height then
			self.glide:Jump(top + self.spec.rowHeight - height)
		end
	end
	return row
end

-- The search results' rows (see the NavRail header): two lines each -- the
-- small path over the name in full size, both in the text colour on the
-- list's inner panel (2e), the selected one's name in gold on the marker --
-- the palette's hover wash, a snug New tag at the right. A pool of their
-- own, each made whole the first time a search needs it: a keystroke after
-- makes no frame or region.
local RESULT_X, RESULT_PAD = 8, 5   -- the texts' inset and their room over and under
local RESULT_LINE_GAP = 6           -- between the two lines (10 and 12 high: the least height, 38)
local PATH_SEP = " > "              -- a path's parts (the caller's "Page > Tab")

-- A result row's height: the least (spec.resultHeight), or taller while its
-- two lines' fonts are (the Fonts module's sizes, up to 150 %: the path's
-- descenders never on the name's capitals), read from the pool's first row
-- (review of the search box, 2026-09-26). No table, no string: asked at each
-- search
local function ResultHeight(rail)
	local h = rail.spec.resultHeight
	local row = rail.resultRows[1]
	if row then
		local _, a = row.path:GetFont()
		local _, b = row.label:GetFont()
		a, b = Num(a), Num(b)
		if a and b then
			h = math.max(h, math.ceil(a + b + 2 * RESULT_PAD + RESULT_LINE_GAP))
		end
	end
	return h
end

-- The path as the row has room for it: whole when it fits, else its first
-- parts left out, so its end -- the tab, the parent: what tells two results
-- apart -- stays (review of the search box, 2026-09-26: "UI Modifications >
-- Combat > Y..." for three Icon Size rows). Measured once per entry for the
-- room and the font, the answer kept in the entry (`pathShown`, and what it
-- was measured for); a keystroke after measures nothing and makes no string.
local function FitPath(fs, e, room)
	local path = e.path
	local file, size = fs:GetFont()
	size = Num(size)
	if e.pathShown and e.pathRoom == room and e.pathSize == size and e.pathFont == file then
		return e.pathShown
	end
	local shown, at = path, 1
	fs:SetText(path)
	while (TextWidth(fs) or 0) > room do
		local _, stop = string.find(path, PATH_SEP, at, true)
		if not stop then
			break   -- (its last part alone and still too wide: cut at the row's edge)
		end
		at = stop + 1
		shown = path:sub(at)
		fs:SetText(shown)
	end
	e.pathShown, e.pathRoom, e.pathSize, e.pathFont = shown, room, size, file
	return shown
end

local function IsResultSelected(row)
	local rail = railOf[row]
	return rail ~= nil and rail.resultsShown and rail.resultIndex == row.index
end
-- (one options table for every result row's hover)
local RESULT_PLATE = { look = "palette", strength = 0.5, edge = false, selected = IsResultSelected }

local ResultClick = Shared("OnClick on a NavRail search result", function(row)
	local rail = railOf[row]
	if not (rail and rail.resultsShown and row.entry) then
		return
	end
	rail:SelectResult(row.index)
	if rail.spec.onResult then
		rail.spec.onResult(rail, row.entry)
	end
end, "script")

-- the result's tooltip: the whole of where it is (a path cut at the row's
-- edge too), the section it lies in, and what it does
local ResultTipEnter = Shared("OnEnter on a NavRail search result (tooltip)", function(row)
	local e = row.entry
	if e then
		local rail = railOf[row]
		W.ShowTooltip(row, e.full or e.name or "", e.tip, e.section, rail and rail.spec.tipAnchor)
	end
end, "script")

local function NewResultRow(rail, i)
	local row = CreateFrame("Button", nil, rail.content)
	row:SetHeight(rail.resultHeight)
	row.height = rail.resultHeight
	row:SetFrameLevel(rail.content:GetFrameLevel() + 1)
	row.path = W.Text(row, "GameFontHighlightSmall", nil, "text")
	row.path:SetWordWrap(false)
	row.label = W.Text(row, "GameFontHighlight", nil, "text")
	row.label:SetWordWrap(false)
	-- (its New tag made with it, shown when a result needs it: a keystroke
	-- makes no region either)
	row.newTag = W.Tag(row, W.NEW, true)
	row.newTag:SetPoint("RIGHT", row, "RIGHT", -(RAIL_TAG_IN + TAG_SNUG_X), 0)
	W.TagShown(row.newTag, false)
	W.RowPlate(row, RESULT_PLATE)
	Perf.HookScript(row, "OnEnter", ResultTipEnter)
	Perf.HookScript(row, "OnLeave", TipLeave)
	Perf.SetScript(row, "OnClick", ResultClick)
	row.index = i
	railOf[row] = rail
	rail.resultRows[i] = row
	return row
end

-- a result laid on its row at `y`: its texts (the caller's strings, the
-- path kept to its end when it is too wide: FitPath), its tag, the texts
-- ending before the tag, the row as tall as its fonts want (ResultHeight)
local function LayResult(rail, row, e, y)
	row.entry = e
	local path = e.path
	local hasPath = path ~= nil and path ~= ""
	local tagged = Shows(e.new)
	W.TagShown(row.newTag, tagged)
	local right = 6
	if tagged then
		right = RAIL_TAG_IN + (TextWidth(row.newTag) or 20) + 2 * TAG_SNUG_X + RAIL_TAG_GAP
	end
	row.path:SetText(hasPath and FitPath(row.path, e, rail.width - RESULT_X - right) or "")
	row.path:SetShown(hasPath)
	row.label:SetText(e.name or "")
	if row.height ~= rail.resultHeight then
		row.height = rail.resultHeight
		row:SetHeight(row.height)
	end
	row.path:ClearAllPoints()
	row.path:SetPoint("TOPLEFT", RESULT_X, -RESULT_PAD)
	row.path:SetPoint("TOPRIGHT", -right, -RESULT_PAD)
	row.label:ClearAllPoints()
	if hasPath then
		row.label:SetPoint("BOTTOMLEFT", RESULT_X, RESULT_PAD)
		row.label:SetPoint("BOTTOMRIGHT", -right, RESULT_PAD)
	else
		row.label:SetPoint("LEFT", RESULT_X, 0)
		row.label:SetPoint("RIGHT", -right, 0)
	end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", rail.content, "TOPLEFT", 0, -y)
	row:SetWidth(rail.width)
	row.y = y
	row:Show()
end

local function PaintResult(rail, i)
	local row = i and rail.resultRows[i]
	if row then
		W.Paint(row.label, i == rail.resultIndex and "selectedTrim" or "text", "text")
	end
end

local function PutAway(row)
	row:Hide()
	row.entry = nil
	W.RowPlateOff(row)
end

-- New result rows keep to the frame's one budget of rows (W.RowBudget, as
-- the pages' rows): those the budget leaves are owed, made by the caller's
-- rail:MoreResults() on a later frame (the top ones first); the first
-- searches make the pool
local RESULT_BUDGET = 3   -- ms of new result rows in the frame of a keystroke

function Rail:ShowResults(list, n, note, more)
	local spec = self.spec
	if not self.resultsShown then
		-- the groups put away, their folds and the list's scroll kept for
		-- HideResults
		-- (a row still fading back in from a fold lands at its end: it comes
		-- back whole)
		local Anim = MelloUI.Anim
		for _, f in ipairs(self.order) do
			Anim:Land(f, "alpha")
			f:Hide()
		end
		self.listScroll = self.glide and self.glide.pos or 0
		self.resultsShown = true
		MarkerLook(self)
	end
	self.resultList, self.resultWanted, self.resultNote = list, n, note
	self.resultHeight = ResultHeight(self)
	local step = self.resultHeight + spec.gap
	local y, laid = 0, 0
	local deadline, begun = nil, false
	for i = 1, n do
		local row = self.resultRows[i]
		if not row then
			if not begun then
				begun = true
				deadline = W.RowBudget.Begin(RESULT_BUDGET)   -- (nil: this frame's rows are made)
			end
			if not (deadline and debugprofilestop() < deadline) then
				break
			end
			row = NewResultRow(self, i)
			if i == 1 then
				-- (the pool's first row: its fonts give the height from now on)
				self.resultHeight = ResultHeight(self)
				step = self.resultHeight + spec.gap
			end
		end
		LayResult(self, row, list[i], y)
		y = y + step
		laid = i
	end
	if begun then
		W.RowBudget.End()
	end
	for i = laid + 1, #self.resultRows do
		PutAway(self.resultRows[i])
	end
	self.resultsOwed = laid < n
	-- the quiet line under them, once they are all laid (full size:
	-- WINDOW-RULES 2e)
	local line = self.note
	if note and note ~= "" and not self.resultsOwed then
		if not line then
			line = W.Text(self.content, "GameFontHighlight", nil, "text")
			line:SetWordWrap(true)
			self.note = line
		end
		line:SetWidth(self.width - 2 * RESULT_X)
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", self.content, "TOPLEFT", RESULT_X, -(y + 6))
		line:SetText(W.Tr(note))
		line:Show()
		y = y + 12 + (Num(line:GetStringHeight()) or 14)
	elseif line then
		line:Hide()
	end
	self.resultCount = laid
	if not more or not self.resultIndex then
		-- a new search: its first result selected, the list at its top
		self.resultIndex = laid > 0 and 1 or nil
	end
	self.content:SetHeight(math.max(y, 1))
	if self.glide and not more then
		self.glide:Jump(0)
	end
	self:BarRange()
	self:PlaceMarker(not more)
	for i = 1, laid do
		PaintResult(self, i)
	end
	return self.resultsOwed
end

-- the rows a search still owes, laid now (within the frame's budget); true
-- while some are still owed after
function Rail:MoreResults()
	if self.resultsShown and self.resultsOwed then
		return self:ShowResults(self.resultList, self.resultWanted, self.resultNote, true)
	end
	return false
end

function Rail:HideResults(instant)
	if not self.resultsShown then
		return
	end
	self.resultsShown = false
	MarkerLook(self)
	for i = 1, #self.resultRows do
		PutAway(self.resultRows[i])
	end
	if self.note then
		self.note:Hide()
	end
	self.resultCount, self.resultIndex, self.resultsOwed, self.resultList = 0, nil, false, nil
	-- (the rows fade back in unless `instant`; the marker on the selected entry)
	self:Layout(instant)
	self:Paint()
	if self.glide then
		self.glide:Jump(self.listScroll or 0)
	end
end

function Rail:SelectResult(i)
	if not (self.resultsShown and i and i >= 1 and i <= self.resultCount) or i == self.resultIndex then
		return
	end
	local was = self.resultIndex
	self.resultIndex = i
	W.RowPlateOff(self.resultRows[i])   -- (no wash on the selected one)
	self:PlaceMarker(false)
	PaintResult(self, was)
	PaintResult(self, i)
end

function Rail:MoveResult(delta)
	if not (self.resultsShown and self.resultCount > 0) then
		return nil
	end
	local i = math.max(1, math.min(self.resultCount, (self.resultIndex or 0) + delta))
	self:SelectResult(i)
	local row = self.resultRows[i]
	if self.glide and self.scroll then
		-- (kept in view: the list glides by the least it must)
		local top, h = row.y, self.resultHeight
		local height = Num(self.scroll:GetHeight()) or 0
		local offset = self.glide.pos or 0
		if top < offset then
			self.glide:To(top)
		elseif height > 0 and top + h > offset + height then
			self.glide:To(top + h - height)
		end
	end
	return row.entry
end

function Rail:Result()
	local row = self.resultsShown and self.resultIndex and self.resultRows[self.resultIndex]
	return row and row.entry or nil
end

--------------------------------------------------------------------------------
-- Pager: one ScrollFrame whose scroll child is a CANVAS; pages are children
-- of the canvas held by one TOPLEFT point, so two can show at once in the
-- ScrollFrame's clip. A switch puts the new page at the top and cross-fades
-- to it (sliding in from the side `dir` says); a shield over the page area
-- takes the mouse until the new page is in.
--   local pager = W.Pager(parent, opts)
--   opts: step (80: the wheel), slide (12), outTime (0.10), inTime (0.15),
--         outInstant (true: the leaving page hides at once and only the new
--         one fades and slides; false: the leaving one fades out, pinned
--         where it is on screen -- the safe fallback is the default until
--         the clip test in game says otherwise), name,
--         template ("UIPanelScrollFrameTemplate": the classic scroll bar),
--         bleed (0: units the clip reaches past the pages' left and right
--         edges, the pages laid that far in: the caller anchors the scroll
--         frame that much wider. A chosen card's active look reaches its
--         halo past the card, and a card flush with the page's edge had it
--         cut off there; review 2026-09-28)
--   pager:NewPage() -> page       pager:Show(page, dir, instant)  dir -1 | 0 | 1
--   pager:SetPageHeight(page, h)  the canvas follows only the page on show
--   pager:AlphaOnly(page, on)     that page only fades, it never slides (a page
--                                 of many rows: a slide lays them all out
--                                 again every frame -- the fallback for
--                                 pages over 40 rows)
--   pager:Current()  pager:Offset()  pager:ScrollTo(offset, instant)
--   pager:Contains(region)        region is inside the current page
--   pager:Reveal(region, margin)  that part glided whole into view (the least
--                                 scroll); W.RevealInPager(region) finds its pager
--   pager.scroll, pager.canvas, pager.glide, pager.shield, pager.cf (the
--   CrossFade options, one table: change its fields, never replace it)
-- The switch is instant under Reduce Motion, while the scroll frame is not
-- visible, or when asked.
--------------------------------------------------------------------------------

local Pager = {}
Pager.__index = Pager
local pagerOf = setmetatable({}, weakKeys)   -- [page] = its pager

-- (the CrossFade's end: the shield off once the page on show is in)
local function ShieldOff(page)
	local pager = pagerOf[page]
	if pager and pager.current == page then
		pager.shield:Hide()
	end
end

function W.Pager(parent, opts)
	opts = opts or {}
	local p = setmetatable({ current = nil, alphaOnly = setmetatable({}, weakKeys) }, Pager)
	local scroll = CreateFrame("ScrollFrame", opts.name, parent, opts.template)
	p.scroll = scroll
	p.canvas = CreateFrame("Frame", nil, scroll)
	p.canvas:SetSize(1, 1)
	scroll:SetScrollChild(p.canvas)
	p.glide = MelloUI.Anim:Glide(scroll, { step = opts.step or 80 })
	p.shield = CreateFrame("Frame", nil, scroll)
	p.shield:SetAllPoints(scroll)
	p.shield:SetFrameLevel(scroll:GetFrameLevel() + 50)
	p.shield:EnableMouse(true)
	p.shield:Hide()
	p.slide = opts.slide or 12
	p.bleed = opts.bleed or 0
	p.cf = { slide = 0, axis = "x", outTime = opts.outTime or 0.10, inTime = opts.inTime or 0.15,
		outInstant = opts.outInstant ~= false, onDone = ShieldOff, instant = false }
	return p
end

function Pager:NewPage()
	local page = CreateFrame("Frame", nil, self.canvas)
	page:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", self.bleed, 0)
	page:Hide()
	pagerOf[page] = self
	return page
end

function Pager:AlphaOnly(page, on)
	self.alphaOnly[page] = on and true or nil
end

local function Pin(page, canvas, y)
	local pager = pagerOf[page]
	page:ClearAllPoints()
	page:SetPoint("TOPLEFT", canvas, "TOPLEFT", pager and pager.bleed or 0, y)
end

function Pager:Show(page, dir, instant)
	local old = self.current
	if old == page then
		page:Show()
		return
	end
	local Anim = MelloUI.Anim
	instant = (instant or Anim.reduceMotion or not self.scroll:IsVisible()) and true or false
	if old then
		Anim:Land(old, "x")
		Pin(old, self.canvas, self.glide.pos or 0)   -- where it is on screen while it goes
	end
	self.current = page
	Pin(page, self.canvas, 0)
	self.canvas:SetWidth(page:GetWidth() + 2 * self.bleed)
	self.canvas:SetHeight(math.max(page:GetHeight(), 1))
	self.glide:Jump(0)
	local cf = self.cf
	cf.slide = self.alphaOnly[page] and 0 or (dir or 0) * self.slide
	cf.instant = instant
	if instant then
		self.shield:Hide()
	else
		self.shield:Show()
	end
	Anim:CrossFade(old, page, cf)
end

function Pager:Current()
	return self.current
end

function Pager:SetPageHeight(page, h)
	page:SetHeight(h)
	if page == self.current then
		self.canvas:SetHeight(math.max(h, 1))
	end
end

function Pager:Offset()
	return self.glide.pos or 0
end

function Pager:ScrollTo(offset, instant)
	if instant then
		self.glide:Jump(offset)
	else
		self.glide:To(offset)
	end
end

-- (Suggestion 1, point 2, 2026-11-04) a part of the page on show brought
-- whole into view by the least glide (`margin` beyond its edges, 8): one
-- below the view's foot rises until its foot shows, never its top past the
-- view's top; one above comes down to the top. Nothing for a part in view,
-- outside the page on show, or not laid out yet
function Pager:Reveal(region, margin)
	if not (region and region.GetTop and self:Contains(region)) then
		return
	end
	margin = margin or 8
	local scroll = self.scroll
	local k = (Num(region:GetEffectiveScale()) or 1) / (Num(scroll:GetEffectiveScale()) or 1)
	local top, foot = Num(region:GetTop()), Num(region:GetBottom())
	local viewTop, viewFoot = Num(scroll:GetTop()), Num(scroll:GetBottom())
	if not (top and foot and viewTop and viewFoot) then
		return
	end
	top, foot = top * k, foot * k
	local delta = 0
	if top > viewTop - margin then
		delta = -(top - viewTop + margin)
	elseif foot < viewFoot + margin then
		delta = math.min(viewFoot + margin - foot, viewTop - margin - top)
	end
	if delta ~= 0 then
		-- (2.1.13: a page grown just now -- a kind's settings opened -- the engine's range is a frame late, and a glide
		-- stops at the range)
		scroll:UpdateScrollChildRect()
		self:ScrollTo(self:Offset() + delta, false)
	end
end

-- the Pager holding `region` (its page's); nil outside one
function W.PagerOf(region)
	local f = region
	for _ = 1, 40 do
		if not f then
			return nil
		end
		local pager = pagerOf[f]
		if pager then
			return pager
		end
		f = f.GetParent and f:GetParent() or nil
	end
	return nil
end

-- the Pager holding `region`, its Reveal asked; nothing outside one
function W.RevealInPager(region, margin)
	local pager = W.PagerOf(region)
	if pager then
		return pager:Reveal(region, margin)
	end
end

function Pager:Contains(region)
	local page = self.current
	local f = region
	for _ = 1, 40 do
		if not f or not page then
			return false
		end
		if f == page then
			return true
		end
		f = f.GetParent and f:GetParent() or nil
	end
	return false
end

--------------------------------------------------------------------------------
-- NumberBox (0.15.0, Edit Layout's right-click box: an element's X and Y): a
-- number to type, in the slider value box's look -- `innerPanel` in a 1 px
-- `border` edge, the text colour, centred. Like the slider's box it never
-- takes the keyboard by itself (only a click gives it the focus). Enter, Tab
-- or leaving it takes the number typed (its first number: "-320", "320 px";
-- the typographic minus too), kept in the range and rounded to the step, and
-- hands it to set when it changed; the box then shows the value as get()
-- gives it. Escape puts the value back and lets the focus go (the window
-- never sees that Escape); the box's hide does too.
--   W.NumberBox(parent, width, get, set, opts) -> box   an EditBox `width` x
--     20, sized and placed by the caller
--     opts: min, max (none: no limit), step (1), suffix (shown after the
--     number, never typed: " %"), format (fn(v) -> text, before the suffix)
--   box:Refresh()   get() again (left alone while it has the focus)
--   box.melloNext   an edit box Tab moves to after taking the number (the
--     caller's: Edit Layout's X -> Y -> Size)
--   box.melloGet / melloSet, box.field (THE text field, W.Field)
-- Its handlers are shared (no closure per box); nothing runs while it is
-- left alone.
--------------------------------------------------------------------------------

do
	local BOX_H, BOX_INSET = 20, 3
	local BOX_FONT = "GameFontHighlight"
	local TYPO_MINUS = "\226\136\146"   -- (U+2212, the minus a readout shows)

	local function NumberText(box, v)
		local fmt = box.melloFormat
		local text
		if fmt then
			text = fmt(v)
		elseif math.abs(v - math.floor(v + 0.5)) < 0.001 then
			text = tostring(math.floor(v + 0.5))
		else
			text = string.format("%.2f", v)
		end
		return box.melloSuffix and (text .. box.melloSuffix) or text
	end

	-- the number typed, kept in the range and rounded to the step; nil for none
	local function Typed(box, text)
		text = tostring(text or ""):gsub(TYPO_MINUS, "-")
		local n = tonumber(text:match("%-?%d*%.?%d+"))
		if not n or n ~= n then
			return nil
		end
		n = W.Round(n, box.melloStep)
		if box.melloMin and n < box.melloMin then
			n = box.melloMin
		end
		if box.melloMax and n > box.melloMax then
			n = box.melloMax
		end
		return n
	end

	local function Show(box)
		local v = Num(box.melloGet())
		box:SetText(v and NumberText(box, v) or "")
	end

	-- the number taken (none: the value put back), the box showing the value
	-- after; `take` false: only put back
	local function LetGo(box, take)
		if take then
			local v = Typed(box, box:GetText())
			if v ~= nil and v ~= box.melloGet() then
				box.melloSet(v)
			end
		end
		Show(box)
		if box:HasFocus() then
			box.melloLetGo = true
			box:ClearFocus()
		end
	end

	local NumberEnter = Shared("OnEnterPressed on a number box", function(box)
		LetGo(box, true)
	end, "script")

	local NumberTab = Shared("OnTabPressed on a number box", function(box)
		LetGo(box, true)
		local nextBox = box.melloNext
		if nextBox and nextBox.SetFocus and nextBox:IsVisible() then
			nextBox:SetFocus()
		end
	end, "script")

	local NumberEscape = Shared("OnEscapePressed on a number box", function(box)
		LetGo(box, false)
	end, "script")

	local NumberFocusGained = Shared("OnEditFocusGained on a number box", function(box)
		box.field:SetState(true)
		box:HighlightText()
	end, "script")

	-- a click elsewhere: the number taken (Enter, Tab and Escape had their say)
	local NumberFocusLost = Shared("OnEditFocusLost on a number box", function(box)
		box.field:SetState(false)
		if box.melloLetGo then
			box.melloLetGo = nil
			return
		end
		LetGo(box, true)
	end, "script")

	local NumberHidden = Shared("OnHide on a number box", function(box)
		if box:HasFocus() then
			LetGo(box, false)
		end
	end, "script")

	local function NumberRefresh(box)
		if not box:HasFocus() then
			Show(box)
		end
	end

	function W.NumberBox(parent, width, get, set, opts)
		opts = opts or NO_OPTS
		local box = CreateFrame("EditBox", nil, parent)
		box:SetAutoFocus(false)
		box:SetSize(width or 60, BOX_H)
		box:SetFontObject(BOX_FONT)
		box:SetJustifyH("CENTER")
		box:SetTextInsets(BOX_INSET, BOX_INSET, 0, 0)
		box:EnableMouse(true)
		box:EnableMouseWheel(false)
		W.Paint(box, "text", "text")
		box.field = W.Field(box)   -- (0.20.1)
		box.melloGet, box.melloSet = get, set
		box.melloMin, box.melloMax = Num(opts.min), Num(opts.max)
		box.melloStep = Num(opts.step) or 1
		box.melloSuffix, box.melloFormat = opts.suffix, opts.format
		box.Refresh = NumberRefresh
		Perf.SetScript(box, "OnEnterPressed", NumberEnter)
		Perf.SetScript(box, "OnTabPressed", NumberTab)
		Perf.SetScript(box, "OnEscapePressed", NumberEscape)
		Perf.SetScript(box, "OnEditFocusGained", NumberFocusGained)
		Perf.SetScript(box, "OnEditFocusLost", NumberFocusLost)
		Perf.SetScript(box, "OnHide", NumberHidden)
		Show(box)
		return box
	end
end

--------------------------------------------------------------------------------
-- OrderList (0.20.4; the user, 2026-10-11, Bags by Kind's kinds: "the categories have a priority, whats shown on
-- top" -- look A of MelloUI-BuildData/output/bag_kinds_sketch, the drag list): rows put in order by dragging them,
-- a tick on the rows that have one, a name to type on the rows that take one (double-click it), a cross on the rows
-- that may go, buttons under the list. The list is its owner's: the widget lays the rows `spec.rows()` gives and
-- hands every change back; list:Refresh() lays them again.
--   W.OrderList(parent, width, spec) -> list
--     spec.rows() -> { { kind = "item" | "line" | "group", label, note, ticked (nil: no tick), indent (0 / 1),
--                       removable, renamable }, ... }
--     spec.block(i) -> the rows that move with row i (a group: itself and its members), else 1
--     spec.move(from, count, to)   rows from .. from + count - 1 put before row `to` (#rows + 1: at the end)
--     spec.tick(i, on), spec.remove(i), spec.rename(i, text)
--     spec.buttons = { { text, onClick }, ... } under the list; spec.title, spec.help: its heading and help line
--     (0.21.1, Bags by Kind's own kinds: the user's pick 2A of bag_own_kinds_sketch) a row with `settings` (and an
--     `id`) shows a cog: its settings open under it, in the list (one at a time; a click on the cog again, or a row
--     picked up to drag, closes them). spec.detailRows(r) -> how many rows' height they take; spec.detail(holder, r, i)
--     fills the holder (a Frame, made once, the list's) for that row, each time they are laid
--   list:Open(id)   the settings of the row with that id opened (nil: closed), the list laid again, the settings
--     glided whole into view (W.RevealInPager)
--   list.height     its height; list.onHeight(list, height) when it changes
--   W.OrderListHeight(rows)   the height of a list of so many rows, for the room its owner keeps before it is built
-- A held row runs an OnUpdate while it is held, nothing else does.
-- (2.1.13; Nixxen, Discord, 2026-11-07: "you are unable to scroll to see the full menu of the edit options") No scroll
-- of its own: it had a fixed height and a hidden offset, no bar, inside a page that scrolls, and a kind's settings
-- raised only that offset, so the page's bar ended at the same place and the settings stayed cut at the list's foot.
-- It is as tall as its rows and the open settings, and the page's scroll carries it (the wheel over it too); a held row
-- near the top or foot of the view moves the page.
--------------------------------------------------------------------------------

-- W.Caret(tex, size, dir, lit): the kit's gold caret (a dropdown's) on a texture, pointing "down", "right", "up" or
-- "left", lit under the mouse -- a group's fold arrow (the order list's, the bag window's group headings)
function W.Caret(tex, size, dir, lit)
	if not KC.Painted(tex.melloArea) then
		-- (0.25.0) a group's fold in MelloUI's look: the set's - while open, + while folded (as the Quest List's)
		return KC.Lay(tex, size, size, (dir or "down") == "down" and "minus" or "plus", nil, lit and "hover" or "normal", 1)
	end
	return KC.Lay(tex, size, size, "arrow", dir or "down", lit and "hover" or "normal", 1, true)
end

-- W.PlusMark(tex, size, lit): the kit's gold plus glyph on a texture, lit under the mouse (0.20.4: the bag window's
-- drop slots)
function W.PlusMark(tex, size, lit)
	return KC.Lay(tex, size, size, "plus", nil, lit and "hover" or "normal", 1, true)
end

do
	local ROW_H = 26
	local HEAD_H = 46            -- the title and its help line over the list
	local FOOT_H = 40            -- the buttons under it
	local GRIP_X, TEXT_X, INDENT = 10, 32, 20
	-- px the cursor goes before a held row is dragged; the view's edges while dragging (px), a row every this long
	-- (one table: the file's main chunk is at Lua 5.1's 200 locals)
	local DRAG = { START = 4, EDGE = 18, EVERY = 0.08 }
	local TEXT = { line = "line", rename = "Double-click to rename." }

	local List = {}
	List.__index = List

	local function CursorY(frame)
		local _, y = GetCursorPosition()
		local s = Num(frame:GetEffectiveScale()) or 1
		return (Num(y) or 0) / s
	end

	-- the grip: three short bars
	local function Grip(row)
		row.grip = {}
		for i = 1, 3 do
			local bar = W.Solid(row, "ARTWORK", "mutedText", 1)
			bar:SetSize(12, 2)
			bar:SetPoint("LEFT", row, "LEFT", GRIP_X, 6 - (i - 1) * 5)
			row.grip[i] = bar
		end
	end

	local function GripKey(row, key)
		for i = 1, 3 do
			W.Paint(row.grip[i], key, "fill", 1)
		end
	end

	local RowEnter, RowLeave, RowDown, RowUp, RowDouble, Held   -- (scripts, below)
	-- (0.21.1) the cog of a row with settings: its size, its tooltip, its look and scripts -- one table (the file's
	-- main chunk is at Lua 5.1's 200 locals)
	local Cog = { SIZE = 18, TIP = "Settings" }
	-- the text colour, gold under the pointer and while its settings are open
	function Cog.Look(cog, lit)
		local list = cog.row.list
		local r = cog.row.data
		local open = r and r.id ~= nil and list.open == r.id
		W.Paint(cog.glyph, (lit or open) and "selectedTrim" or "text", "vertex", 1)
	end
	Cog.Click = Shared("OnClick on an order list row's cog", function(cog)
		local row = cog.row
		local r = row.data
		if not (r and r.id ~= nil) then
			return
		end
		MelloUI:PlayUISound("menu_button")
		row.list:Open(row.list.open ~= r.id and r.id or nil)
	end, "script")
	Cog.Enter = Shared("OnEnter on an order list row's cog", function(cog)
		Cog.Look(cog, true)
		W.ShowTooltip(cog, cog.row.data and cog.row.data.label or "", Cog.TIP)
	end, "script")
	Cog.Leave = Shared("OnLeave on an order list row's cog", function(cog)
		Cog.Look(cog, false)
		W.TipLeave(cog)
	end, "script")

	local function MakeRow(list)
		local row = CreateFrame("Button", nil, list.content)
		row:SetHeight(ROW_H)
		row:RegisterForClicks("LeftButtonUp")
		row.list = list
		row.hover = W.Solid(row, "BACKGROUND", "hover", 0.35)
		row.hover:SetAllPoints(row)
		row.hover:Hide()
		Grip(row)
		row.label = W.Text(row, "GameFontHighlight", nil, "text")
		row.label:SetWordWrap(false)
		row.note = W.Text(row, "GameFontHighlightSmall", nil, "text")   -- (small: never muted, Suggestion 1 point 7)
		row.note:SetPoint("LEFT", row.label, "RIGHT", 10, 0)
		row.rule = W.Solid(row, "ARTWORK", "trim", 0.8)
		row.rule:SetHeight(1)
		row.caret = row:CreateTexture(nil, "ARTWORK")   -- (a group's: the kit's gold caret, as a dropdown's)
		row.caret:SetSize(CARET, CARET)
		W.Caret(row.caret, CARET, "down")
		row.tick = W.Switch(row, function()
			local r = row.data
			return r and r.ticked == true
		end, function(on)
			if row.index then
				pcall(list.spec.tick, row.index, on and true or false)
				list:Refresh()
			end
		end)
		row.tick:SetPoint("RIGHT", row, "RIGHT", -10, 0)
		row.cross = W.Button(row, "x", 22, nil, { height = 18, onClick = function()
			if row.index then
				MelloUI:PlayUISound("check_off")
				pcall(list.spec.remove, row.index)
				list:Refresh()
			end
		end })
		row.cross:SetPoint("RIGHT", row, "RIGHT", -8, 0)
		-- (0.21.1) the cog: the row's settings, opened under it
		row.cog = CreateFrame("Button", nil, row)
		row.cog:SetSize(Cog.SIZE, Cog.SIZE)
		row.cog.glyph = row.cog:CreateTexture(nil, "ARTWORK")
		row.cog.glyph:SetAllPoints(row.cog)
		W.Glyph(row.cog.glyph, "cog")
		row.cog.row = row
		Perf.SetScript(row.cog, "OnClick", Cog.Click)
		Perf.SetScript(row.cog, "OnEnter", Cog.Enter)
		Perf.SetScript(row.cog, "OnLeave", Cog.Leave)
		Perf.SetScript(row, "OnEnter", RowEnter)
		Perf.SetScript(row, "OnLeave", RowLeave)
		Perf.SetScript(row, "OnMouseDown", RowDown)
		Perf.SetScript(row, "OnMouseUp", RowUp)
		Perf.SetScript(row, "OnDoubleClick", RowDouble)
		return row
	end

	-- a row dressed for its entry (r), at its index
	local function Dress(row, r, i)
		row.data, row.index = r, i
		local x = TEXT_X + (r.indent or 0) * INDENT
		row.label:ClearAllPoints()
		row.caret:Hide()
		row.rule:Hide()
		if r.kind == "group" then
			row.caret:SetPoint("LEFT", row, "LEFT", x, 0)
			row.caret:Show()
			row.label:SetPoint("LEFT", row, "LEFT", x + 16, 0)
			row.label:SetText(r.label or "")
			row.label:SetFontObject("MelloUIFont_GameFontNormal")
			W.Paint(row.label, "selectedTrim", "text")
		elseif r.kind == "line" then
			row.label:SetPoint("RIGHT", row, "RIGHT", -38, 0)
			row.label:SetText(TEXT.line)
			row.label:SetFontObject("MelloUIFont_GameFontHighlightSmall")
			W.Paint(row.label, "mutedText", "text")
			row.rule:ClearAllPoints()
			row.rule:SetPoint("LEFT", row, "LEFT", x, 0)
			row.rule:SetPoint("RIGHT", row.label, "LEFT", -6, 0)
			row.rule:Show()
		else
			row.label:SetPoint("LEFT", row, "LEFT", x, 0)
			row.label:SetText(r.label or "")
			row.label:SetFontObject("MelloUIFont_GameFontHighlight")
			W.Paint(row.label, "text", "text")
		end
		row.note:SetText(r.kind == "item" and r.note or "")
		row.tick:SetShown(r.ticked ~= nil)
		if r.ticked ~= nil then
			row.tick:Refresh()
		end
		row.cross:SetShown(r.removable and true or false)
		-- (0.21.1) the cog left of the tick (or of the cross, or at the end)
		row.cog:SetShown(r.settings and r.id ~= nil and true or false)
		if r.settings then
			row.cog:ClearAllPoints()
			row.cog:SetPoint("RIGHT", row, "RIGHT", (r.ticked ~= nil or r.removable) and -44 or -12, 0)
			Cog.Look(row.cog, false)
		end
		GripKey(row, "mutedText")
	end

	function List:Rows()
		local ok, rows = pcall(self.spec.rows)
		self.data = ok and type(rows) == "table" and rows or {}
		return self.data
	end

	-- (2.1.13) the height of a list of so many rows: its heading, the rows, its buttons
	function W.OrderListHeight(rows)
		return HEAD_H + 8 + rows * ROW_H + FOOT_H
	end

	-- (0.21.1) the open settings' row and how many rows' height they take (0: none open)
	function List:DetailRows()
		if self.open == nil or self.drag or not self.spec.detail then
			return 0
		end
		for _, r in ipairs(self.data) do
			if r.id == self.open and r.settings then
				local ok, n = pcall(self.spec.detailRows, r)
				return ok and Num(n) and math.max(0, math.floor(n)) or 0
			end
		end
		return 0
	end

	function List:Open(id)
		self.open = id
		self:Refresh()
		-- (their row with them, right over them)
		if id ~= nil and self.detail and self.detail:IsShown() then
			W.RevealInPager(self.detail, ROW_H + 8)
		end
	end

	-- the rows laid from the top (a held block left out and its landing place open)
	function List:Lay()
		local data, drag = self.data, self.drag
		local n = 0
		local y = 0
		local landed = false
		local function Gap()
			self.gap:ClearAllPoints()
			self.gap:SetPoint("TOPLEFT", self.content, "TOPLEFT", 4, y - 1)
			self.gap:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -4, y - 1)
			self.gap:SetHeight(ROW_H - 2)
			self.gap:Show()
			y = y - ROW_H
			landed = true
		end
		local pos = 0   -- (where a held block lands: its place among the rows left)
		local detailRows, detailShown = self:DetailRows(), false
		if detailRows > 0 and not self.detail then
			self.detail = CreateFrame("Frame", nil, self.content)
		end
		for i = 1, #data do
			-- (a held row is not laid)
			if not (drag and i >= drag.from and i < drag.from + drag.count) then
				if drag and not landed and pos == drag.to then
					Gap()
				end
				n = n + 1
				local row = self.rows[n] or MakeRow(self)
				self.rows[n] = row
				Dress(row, data[i], i)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, y)
				row:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
				row:Show()
				y = y - ROW_H
				pos = pos + 1
				-- (0.21.1) its settings under it, while open
				if detailRows > 0 and data[i].id == self.open then
					local d = self.detail
					d:ClearAllPoints()
					d:SetPoint("TOPLEFT", self.content, "TOPLEFT", 26, y)
					d:SetPoint("RIGHT", self.content, "RIGHT", -8, 0)
					d:SetHeight(detailRows * ROW_H - 6)
					d:Show()
					pcall(self.spec.detail, d, data[i], i)
					y = y - detailRows * ROW_H
					detailShown = true
				end
			end
		end
		if drag and not landed then
			Gap()
		end
		if not drag then
			self.gap:Hide()
		end
		if self.detail and not detailShown then
			self.detail:Hide()
		end
		for i = n + 1, #self.rows do
			self.rows[i]:Hide()
			self.rows[i].index, self.rows[i].data = nil, nil
		end
	end

	-- (2.1.13) as tall as its rows and the open settings
	function List:Fit()
		local h = W.OrderListHeight(#self.data + self:DetailRows())
		if h ~= self.height then
			self.height = h
			self.frame:SetHeight(h)
			if self.onHeight then
				self.onHeight(self, h)
			end
		end
	end

	function List:Refresh()
		self:Rows()
		self:Lay()
		-- (not while a row is held: what is under the cursor stays where it is until it lands, List:Drop)
		if not self.drag then
			self:Fit()
		end
	end

	-- (2.1.13) a held row near the top or foot of the view, with more of the list past it: the page a row further
	-- (top, bottom: the list's own)
	function List:EdgeScroll(y, top, bottom)
		local pager = W.PagerOf(self.frame)
		local scroll = pager and pager.scroll
		if not scroll then
			return
		end
		local k = (Num(scroll:GetEffectiveScale()) or 1) / (Num(self.clip:GetEffectiveScale()) or 1)
		local viewTop, viewFoot = Num(scroll:GetTop()), Num(scroll:GetBottom())
		if not (viewTop and viewFoot) then
			return
		end
		viewTop, viewFoot = viewTop * k, viewFoot * k
		if top > viewTop and y > viewTop - DRAG.EDGE then
			pager:ScrollTo(pager:Offset() - ROW_H, true)
		elseif bottom < viewFoot and y < viewFoot + DRAG.EDGE then
			pager:ScrollTo(pager:Offset() + ROW_H, true)
		end
	end

	-- the place among the rows left (not held) the cursor points at
	function List:DropAt()
		local top = Num(self.clip:GetTop()) or 0
		local y = CursorY(self.clip)
		local left = #self.data - self.drag.count
		local at = math.floor((top - y) / ROW_H + 0.5)
		return math.max(0, math.min(at, left))
	end

	-- the held block put where it was dropped (a place among the rows left -> the index it goes before)
	function List:Drop()
		local d = self.drag
		self.drag = nil
		self.ghost:Hide()
		self.ticker:SetScript("OnUpdate", nil)
		if d.started then
			local to = d.to < d.from and d.to + 1 or d.to + d.count + 1
			if to ~= d.from and to ~= d.from + d.count then
				MelloUI:PlayUISound("check_on")
				pcall(self.spec.move, d.from, d.count, to)
			end
		end
		self:Refresh()
	end

	Held = Shared("OnUpdate of a held row of an order list (only while held)", function(ticker, elapsed)
		local list = ticker.list
		local d = list.drag
		if not d then
			ticker:SetScript("OnUpdate", nil)
			return
		end
		if not IsMouseButtonDown("LeftButton") then
			list:Drop()
			return
		end
		local y = CursorY(list.clip)
		if not d.started then
			if math.abs(y - d.y0) < DRAG.START then
				return
			end
			d.started = true
			list.open = nil   -- (0.21.1: the settings close as a row is dragged)
			local r = list.data[d.from]
			list.ghost.label:SetText(r and (r.kind == "line" and TEXT.line or r.label) or "")
			list.ghost:Show()
		end
		-- (near the view's top or foot: a row at a time)
		d.wait = (d.wait or 0) - elapsed
		local top, bottom = Num(list.clip:GetTop()) or 0, Num(list.clip:GetBottom()) or 0
		if d.wait <= 0 then
			d.wait = DRAG.EVERY
			list:EdgeScroll(y, top, bottom)
		end
		local to = list:DropAt()
		if to ~= d.to then
			d.to = to
			list:Lay()
		end
		list.ghost:ClearAllPoints()
		list.ghost:SetPoint("LEFT", list.clip, "LEFT", 18, 0)
		list.ghost:SetPoint("RIGHT", list.clip, "RIGHT", -10, 0)
		list.ghost:SetPoint("TOP", list.clip, "BOTTOM", 0, math.max(math.min(y - bottom + ROW_H / 2, top - bottom), ROW_H))
	end, "script")

	RowEnter = Shared("OnEnter on an order list's row", function(row)
		if row.list.drag then
			return
		end
		row.hover:Show()
		GripKey(row, "selectedTrim")
		local r = row.data
		if r and r.renamable then
			W.ShowTooltip(row, r.label, TEXT.rename)
		end
	end, "script")

	RowLeave = Shared("OnLeave on an order list's row", function(row)
		row.hover:Hide()
		GripKey(row, "mutedText")
		W.TipLeave(row)
	end, "script")

	RowDown = Shared("OnMouseDown on an order list's row", function(row, button)
		local list = row.list
		if button ~= "LeftButton" or list.drag or not row.index then
			return
		end
		local count = 1
		local ok, n = pcall(list.spec.block, row.index)
		if ok and Num(n) and n >= 1 then
			count = n
		end
		row.hover:Hide()
		W.TipLeave(row)
		list.drag = { from = row.index, count = count, y0 = CursorY(list.clip), to = nil }
		list.ticker:SetScript("OnUpdate", Held)
	end, "script")

	RowUp = Shared("OnMouseUp on an order list's row", function(row)
		local list = row.list
		if list.drag then
			list:Drop()
		end
	end, "script")

	local function EndRename(box, keep)
		local list = box.list
		local i = box.index
		box.index = nil
		box:ClearFocus()
		box:Hide()
		local text = box:GetText()
		if keep and i and type(text) == "string" and text:match("%S") then
			pcall(list.spec.rename, i, (text:gsub("^%s+", ""):gsub("%s+$", "")))
		end
		list:Refresh()
	end

	RowDouble = Shared("OnDoubleClick on an order list's row", function(row)
		local list = row.list
		local r = row.data
		if not (r and r.renamable and row.index) then
			return
		end
		local box = list.box
		box.index = row.index
		box:ClearAllPoints()
		box:SetPoint("LEFT", row.label, "LEFT", -4, 0)
		box:SetWidth(220)
		box:SetText(r.label or "")
		box:Show()
		box:SetFocus()
		box:HighlightText()
	end, "script")

	local BoxEnter = Shared("OnEnterPressed in an order list's name box", function(box)
		EndRename(box, true)
	end, "script")
	local BoxEscape = Shared("OnEscapePressed in an order list's name box", function(box)
		EndRename(box, false)
	end, "script")
	local BoxLost = Shared("OnEditFocusLost in an order list's name box", function(box)
		if box.index then
			EndRename(box, true)
		end
	end, "script")

	function W.OrderList(parent, width, spec)
		local list = setmetatable({ spec = spec, rows = {}, data = {} }, List)
		local f = CreateFrame("Frame", nil, parent)
		f:SetWidth(width)
		list.frame = f
		local title = W.Text(f, "GameFontNormalLarge", spec.title, "text")
		title:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
		local help = W.Text(f, "GameFontHighlightSmall", spec.help, "text")   -- (small: never muted, Suggestion 1 point 7)
		help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
		local panel = W.Panel(f)
		panel:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEAD_H)
		panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, FOOT_H)
		local clip = CreateFrame("Frame", nil, panel)
		clip:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -4)
		clip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, 4)
		clip:SetClipsChildren(true)
		list.clip = clip
		local content = CreateFrame("Frame", nil, clip)
		content:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
		content:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
		list.content = content
		-- where a held block will land: its room, outlined in gold
		local gap = CreateFrame("Frame", nil, content)
		Edges(gap, "selectedTrim", "BORDER")
		gap:Hide()
		list.gap = gap
		-- the held row, following the cursor over the list
		local ghost = CreateFrame("Frame", nil, clip)
		ghost:SetHeight(ROW_H - 2)
		ghost:SetFrameLevel(clip:GetFrameLevel() + 20)
		local fill = ghost:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints(ghost)
		W.Paint(fill, "raisedPanel", "fill", 1)
		Edges(ghost, "selectedTrim", "BORDER")
		ghost.label = W.Text(ghost, "GameFontHighlight", nil, "text")
		ghost.label:SetPoint("LEFT", ghost, "LEFT", TEXT_X - 8, 0)
		ghost:Hide()
		list.ghost = ghost
		-- the held row's OnUpdate runs on this frame only while a row is held
		local ticker = CreateFrame("Frame", nil, f)
		ticker.list = list
		list.ticker = ticker
		-- a group's name typed in its row
		local box = CreateFrame("EditBox", nil, content)
		box:SetAutoFocus(false)
		box:SetHeight(20)
		box:SetFontObject("MelloUIFont_GameFontHighlight")
		box:SetTextInsets(4, 4, 0, 0)
		box:SetMaxLetters(32)
		box:SetFrameLevel(content:GetFrameLevel() + 10)
		box.field = W.Field(box)
		box.list = list
		Perf.SetScript(box, "OnEnterPressed", BoxEnter)
		Perf.SetScript(box, "OnEscapePressed", BoxEscape)
		Perf.SetScript(box, "OnEditFocusLost", BoxLost)
		box:Hide()
		list.box = box
		local x = 0
		for _, b in ipairs(spec.buttons or {}) do
			local width_ = math.max(90, 24 + 8 * #(b[1] or ""))
			local button = W.Button(f, b[1], width_, nil, { onClick = function()
				MelloUI:PlayUISound("menu_button")
				pcall(b[2])
				list:Refresh()
			end })
			button:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 8)
			x = x + width_ + 8
		end
		list:Refresh()
		return list
	end
end
