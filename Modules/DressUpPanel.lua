--------------------------------------------------------------------------------
-- MelloUI - Dressing Room Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): the dressing room (DressUpFrame: a ButtonFrameTemplateMinimizable
-- window of the game's UI panels, Mainline/DressUpFrames.xml / .lua with
-- this client's Camelot/DressUpFramesOverrides.lua, which turns the class
-- backgrounds off: the model stands on the race pictures) dressed in the
-- painted kit (Modules/Kit.lua) on the game's own layout, by the rule book
-- (docs/WINDOW-RULES.md): every kit piece stands in for one of the game's art
-- regions, on that region's rectangle, the game's art faded in its place.
--
--   the window shell     outer double rail with gem corners, ONE page stone
--                        inside it (the window's Bg -> the page picture), the
--                        ring with the player's portrait at the class
--                        medallion's size on the dark disc (2b), the title
--                        plate on the rail with "Dressing Room" ON it in the
--                        title face (2c), close and maximize / minimize
--                        (Kit:SkinWindowShell)
--   the model area       NEVER covered: its race picture (or class picture)
--                        stays the game's, nothing is laid over it; the
--                        window's inset round it gets the single rail in
--                        place of its own frame (edges only), held a level
--                        over the model so the rail frames its edge as the
--                        character window's viewport frame does
--   the model controls   the cog plate (K2) under the game's glyphs (zoom,
--                        rotate, reset), as the tabard designer's
--   the buttons          Reset / Close / Undress / Link (and the outfit
--                        dropdown's Save) on the red plates (B1), the game's
--                        labels on them, their disabled look kept
--   the outfit dropdown  the kit's dropdown plate (D1)
--   the side panels      the outfit's item list (CustomSetDetailsPanel) and a
--                        transmog set's list (SetSelectionPanel): the L1 box
--                        in place of their dressing-room frame art -- single
--                        rail, stone, the palette's inner panel over it (2e:
--                        a list of names is text); their black and picture
--                        backings faded under it; every item icon in the
--                        Button Border rim, its quality border kept; a set
--                        row's plate and selected plate on the list plates
--
-- The appearance-list toggle (dressingroom-button-appearancelist, its glyph
-- painted into its own plate) is left the game's: a cog under it would not
-- show, and one in its place would lose the glyph.
--
-- Taint: nothing of the game's is replaced or re-scripted; the skin is made
-- and kept from post-hooks (HookScript, hooksecurefunc on the game's own
-- regions and instance methods); state lives in weak side tables; no
-- dressing, transmog or link function is ever called. The portrait (brought
-- to the medallion size) is put back on disable, the title's points and face
-- with the plate; switching the module off gives back the stock window.
-- Nothing is built at login: the window is dressed on its first open (user,
-- 2026-09-24) and kept.
--
-- /dressupdump [frames | reps | regions]: what the window is made of on this
-- client and what the skin found and dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("DressUpPanel")
local hooksecurefunc = Perf.hooksecurefunc
-- a handler made once and run for many asks, wrapped once: its time stays
-- on this file's own /melloperf row (review, 2026-09-24)
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("DressUpPanel", {
	title = "Dressing Room Kit",
	desc = "The dressing room in the kit.",
	window = { label = "Dressing room", desc = "The dressing room in the kit.", tab = "Windows",
		frames = { "DressUpFrame" }, plainGrab = true, firstOpen = true },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local MEDALLION_TO_RING = 0.759   -- WINDOW-RULES 2b (Kit:FitPortrait), for the dump

local skin = nil          -- { reps, followers, built, ring, portrait, disc, inset }
local active = false
local hooked = false

-- what this module made or looked at, kept OFF the game's frames (weak keys)
local done = setmetatable({}, { __mode = "k" })         -- [frame / region] = true: looked at once
local rims = {}                                         -- the item icons' rim holders { melloRep, icon }
local controls = {}                                     -- the model's control buttons { button, rep }
local buttons = {}                                      -- the text buttons { label, button, rep }
local panels = {}                                       -- the side panels { label, panel, rep }
local found = {}                                        -- [part] = a line for /dressupdump

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Dressing room kit: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- the non-nil values given, as a list (alsoFade stops at the first nil)
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

-- a frame's name for the finders (a name can read secret)
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

-- ... and for the dump
local function Label(obj)
	if not obj then
		return "nil"
	end
	local n = NameOf(obj)
	if n then
		return n
	end
	local ok, d = pcall(obj.GetDebugName, obj)
	return (ok and type(d) == "string" and not Secret(d)) and d or "[unnamed]"
end

local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	if ok and type(text) == "string" and not Secret(text) and text ~= "" then
		return text
	end
	return nil
end

local function LevelOf(frame)
	local ok, lv = pcall(frame.GetFrameLevel, frame)
	if ok and type(lv) == "number" and not Secret(lv) then
		return lv
	end
	return nil
end

local function Shown(obj)
	local ok, s = pcall(obj.IsShown, obj)
	return (ok and not Secret(s)) and s or false
end

local function IsTexture(obj)
	return obj and obj.GetObjectType and obj:GetObjectType() == "Texture" or false
end

local function Window()
	return _G.DressUpFrame
end

local function Model(f)
	return f and (f.ModelScene or f.Model or _G.DressUpModelFrame or _G.DressUpModel) or nil
end

local function InsetOf(f)
	return f and (f.Inset or _G.DressUpFrameInset) or nil
end

--------------------------------------------------------------------------------
-- The portrait in the ring (WINDOW-RULES 2b / 2c: an empty ring is a bug).
-- The game draws the player into DressUpFramePortrait (SetPortraitTexture on
-- "player" as the window shows), the portrait container's portrait: the
-- kit's ring on the corner, the portrait brought to the class medallion's
-- size in it (Kit:FitPortrait, its aspect kept) with the dark disc under it
-- (Kit:RingDisc). Fitted again on every show (the window is laid out only
-- while shown); put back on disable.
--------------------------------------------------------------------------------
local function PortraitCandidates(f)
	local list, seen = {}, {}
	local pc = f.PortraitContainer
	for _, t in ipairs({ pc and pc.portrait or false, _G.DressUpFramePortrait or false, f.portrait or false }) do
		if t and not seen[t] and IsTexture(t) then
			seen[t] = true
			list[#list + 1] = t
		end
	end
	return list
end

local function Portrait(f)
	local list = PortraitCandidates(f)
	for _, t in ipairs(list) do
		local ok, file = pcall(t.GetTexture, t)
		if ok and file ~= nil then
			return t
		end
	end
	return list[1]
end

local function SkinPortrait(portrait, ring)
	if not (portrait and ring and ring.tex) then
		found.portrait = "-- no ring (no NineSlice corner or no portrait on this client)"
		return
	end
	ring.onEnable = function()
		pcall(Kit.FitPortrait, Kit, portrait, ring)
	end
	ring.onDisable = function()
		pcall(Kit.UnfitPortrait, Kit, portrait)
	end
	-- the disc one sublevel under a portrait that is a BACKGROUND region of the
	-- window itself; else in the ring's container under its OVERLAY portrait
	local okL, layer, sub = pcall(portrait.GetDrawLayer, portrait)
	local parent = portrait:GetParent()
	local disc
	if okL and layer == "BACKGROUND" and parent and parent ~= ring.object:GetParent() then
		disc = Kit:RingDisc(ring, nil, parent, math.max((sub or 0) - 1, -8))
	else
		disc = Kit:RingDisc(ring)   -- (chains onto the fit above)
	end
	skin.portrait, skin.disc = portrait, disc
	found.portrait = string.format("%s (layer %s %s), disc %s", Label(portrait), okL and tostring(layer) or "?",
		okL and tostring(sub) or "", disc and "made" or "NOT made")
end

local function FitRing()
	if active and skin and skin.portrait and skin.ring then
		pcall(Kit.FitPortrait, Kit, skin.portrait, skin.ring)
	end
end

--------------------------------------------------------------------------------
-- The title (WINDOW-RULES 2c). The shell's title plate centres the title
-- container's TitleText ("Dressing Room", SetTitle at load) on the plate in
-- Kit:TitleFont (the Fonts options, the Font Style) and puts both back on
-- disable; fitted again on every show and resize (maximize / minimize), and
-- the face put on again should anything have reset the string's font.
--------------------------------------------------------------------------------
local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
	end
end

local function TitleText(f)
	local tc = f and f.TitleContainer
	return (tc and tc.TitleText) or _G.DressUpFrameTitleText
end

local function PlaceTitle()
	local rep = TitleRep()
	if not (active and rep and rep.object and rep.object:IsShown()) then
		return
	end
	if rep.Refit then
		rep:Refit()
	end
	local text = TitleText(Window())
	if text and not text.melloFontSaved then
		Kit:TitleFont(text, true)
	end
end

--------------------------------------------------------------------------------
-- The model area (the user's brief: "the model area never covered"). The
-- race pictures under the model (the scene's BGTopLeft .. BGBottomRight; the
-- window's ModelBackground where a client uses class pictures) are the
-- window's picture and stay the game's: nothing is faded there and nothing
-- is laid over them. The window's inset round the model (ButtonFrameTemplate's
-- Inset) gets the single rail in place of its own frame, edges only
-- (Kit:SkinInset: no stone, no panel), held one level over the model so the
-- rail frames the model's edge -- the character window's viewport frame, which
-- stands one level above its scene. Re-held on every refresh (the game may
-- raise the scene).
--------------------------------------------------------------------------------
local function SkinInsetRail(f)
	local inset = InsetOf(f)
	if not inset then
		found.inset = "-- not found"
		return
	end
	if done[inset] then
		return
	end
	done[inset] = true
	Kit:SkinInset(inset, Replace, f)
	skin.inset = inset
	found.inset = string.format("%s: single rail, edges only, %s", Label(inset),
		(inset.melloRep ~= nil and inset.melloRep ~= false) and "dressed" or "NOT dressed")
end

local function KeepRailOverModel(f)
	local inset = skin and skin.inset
	local rep = inset and inset.melloRep
	local model = Model(f)
	local holder = rep and rep.object
	if not (holder and holder.SetFrameLevel and model) then
		return
	end
	local ml = LevelOf(model)
	if ml then
		holder:SetFrameLevel(ml + 1)
		if rep.skin and rep.skin.SetFrameLevel then
			rep.skin:SetFrameLevel(ml + 1)
		end
	end
end

-- the model's picture regions, for the dump
local function ModelPictures(f)
	local model = Model(f)
	local list = {}
	for _, t in ipairs({ f.ModelBackground or false, model and model.BGTopLeft or false, model and model.BGTopRight or false,
		model and model.BGBottomLeft or false, model and model.BGBottomRight or false }) do
		if t then
			list[#list + 1] = t
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- The model's control buttons: K2, the cog plate under the game's glyph. The
-- scene's control strip (ModelSceneControlButtonTemplate: the grey square
-- common-button-square-gray-up on NormalTexture, the glyph on Icon) gets the
-- cog in place of the square, the glyph on top, as the tabard designer's; an
-- older model's round rotate buttons (their curved-arrow glyph is their plate)
-- get the cog UNDER them, not faded, as the bags' sort button.
--------------------------------------------------------------------------------
local OLD_ROTATE = { "DressUpModelFrameRotateLeftButton", "DressUpModelFrameRotateRightButton",
	"DressUpModelRotateLeftButton", "DressUpModelRotateRightButton" }

local function ControlButtons(f)
	local list, seen = {}, {}
	local function Add(b)
		if b and not seen[b] and b.GetObjectType and b:GetObjectType() == "Button" then
			seen[b] = true
			list[#list + 1] = b
		end
	end
	for _, n in ipairs(OLD_ROTATE) do
		Add(_G[n])
	end
	local model = Model(f)
	if not model then
		return list
	end
	local strip = model.ControlFrame
	if strip then
		for _, key in ipairs({ "zoomInButton", "zoomOutButton", "rotateLeftButton", "rotateRightButton", "resetButton" }) do
			Add(strip[key])
		end
	end
	for _, holder in ipairs({ model, strip or false }) do
		if holder and holder.GetChildren then
			for _, child in ipairs({ holder:GetChildren() }) do
				local cn = NameOf(child) or ""
				if child ~= strip and (holder == strip or cn:find("Rotate") or cn:find("Zoom") or cn:find("Reset")) then
					Add(child)
				end
			end
		end
	end
	return list
end

local function SkinControls(f)
	for _, b in ipairs(ControlButtons(f)) do
		if not done[b] then
			done[b] = true
			local icon = b.Icon or b.icon
			local normal = (b.GetNormalTexture and b:GetNormalTexture()) or b.bg or b.Bg
			local rep
			if normal and icon and normal ~= icon then
				rep = Replace(normal, { as = "UI-SquareButton-Up", button = b, alsoFade = Kit:OtherTextures(b, icon) })
			elseif normal then
				rep = Replace(normal, { as = "bags-button-autosort-up", button = b, noFade = true })
			end
			controls[#controls + 1] = { button = b, rep = rep }
		end
	end
end

--------------------------------------------------------------------------------
-- The text buttons on the red plates (B1: Kit:SkinRedButton; the plate
-- follows the button's hover, press and disabled look): Reset, Close, the
-- Link dropdown button (a UIPanelButtonTemplate the sweep does not know as a
-- button: its widget type is a dropdown button), Undress where a client has
-- one, and the outfit dropdown's Save. The dropdown itself on the dropdown
-- plate (D1), its painted cap in place of the arrow.
--------------------------------------------------------------------------------
local function TextButtons(f)
	local dd = f.CustomSetDropdown or _G.DressUpFrameCustomSetDropdown
	return {
		{ "Reset", f.ResetButton or _G.DressUpFrameResetButton },
		{ "Close", _G.DressUpFrameCancelButton or f.CancelButton },
		{ "Undress", f.UndressButton or _G.DressUpFrameUndressButton },
		{ "Link", f.LinkButton or _G.DressUpFrameLinkButton },
		{ "Save (outfits)", dd and dd.SaveButton },
	}
end

local function SkinButtons(f)
	for _, entry in ipairs(TextButtons(f)) do
		local b = entry[2]
		if b and not done[b] then
			done[b] = true
			local rep = Kit:SkinRedButton(b, Replace)
			buttons[#buttons + 1] = { label = entry[1], button = b, rep = rep }
		end
	end
	local dd = f.CustomSetDropdown or _G.DressUpFrameCustomSetDropdown
	if not dd then
		found.dropdown = "-- not found"
	elseif not done[dd] then
		done[dd] = true
		if dd.Background and dd.melloRep == nil then
			dd.melloRep = Replace(dd.Background, { as = "common-dropdown-textholder", rect = dd, button = dd, alsoFade = List(dd.Arrow) }) or false
		end
		found.dropdown = string.format("%s: dropdown plate %s", Label(dd), (dd.melloRep ~= nil and dd.melloRep ~= false) and "on" or "NOT dressed (no Background)")
	end
end

--------------------------------------------------------------------------------
-- An item icon's rim (every window's Button Border) round the icon: the rim
-- hugs the icon (its edge 2 px under the rim's inner edge, on the icon's
-- centre -- the character window's equipment-manager recipe), the icon stays
-- where the game puts it and is not faded (the rim stands in for no art of
-- its own: the lists draw none round the icon), and the game's quality border
-- (IconBorder) stays on the icon. The game sizes the icons per row (14 or
-- 20 px, SetDetails): the rim is fitted again after it.
--------------------------------------------------------------------------------
local function FitIconRim(holder)
	local rim = holder.melloRep and holder.melloRep.object
	local icon = holder.icon
	if not (rim and rim.base and icon) then
		return
	end
	local name = rim.base .. "_normal"
	local p = Kit:Piece(name)
	local l, r, t, b = Kit:Insets(name, 1)
	local ok, iw, ih = pcall(icon.GetSize, icon)
	if not (p and l and ok and iw and ih) or Secret(iw) or Secret(ih) or iw <= 0 or ih <= 0 then
		return
	end
	rim:ClearAllPoints()
	rim:SetPoint("CENTER", icon, "CENTER")
	rim:SetSize((iw - 4) * p.w / (p.w - l - r), (ih - 4) * p.h / (p.h - t - b))
end

-- a new Button Border has a new opening: every rim fitted again
Kit:OnBorderChanged("button", function()
	for _, holder in ipairs(rims) do
		FitIconRim(holder)
	end
end)

local function SkinIconRim(row, icon)
	if not (row and icon) or done[icon] then
		return nil
	end
	done[icon] = true
	local rep = Replace(icon, { as = Kit:ButtonRimRule(), button = row, parent = row, rect = icon, noFade = true })
	if not rep then
		return nil
	end
	local holder = { melloRep = rep, icon = icon }
	rims[#rims + 1] = holder
	Kit:RegisterButtonRim(holder)
	FitIconRim(holder)
	return holder
end

--------------------------------------------------------------------------------
-- The side panels (WINDOW-RULES 2e: a list of names is text). Each is framed
-- by the dressing room's own art (dressingroom-sideframe, OVERLAY) round a
-- black backing (and, on the outfit list, the race picture at a quarter
-- alpha): the L1 box in place of that frame -- single rail, stone, the
-- palette's inner panel over it (the inset rule's `dim`) -- on the panel's
-- rect, a holder at the panel's level (its own regions are all faded; its
-- rows are frames above it); the backings faded under it (one stone).
--------------------------------------------------------------------------------
local function SideFrameArt(panel)
	if panel.Border and IsTexture(panel.Border) then
		return panel.Border
	end
	for _, region in ipairs({ panel:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece and Kit:ArtKey(region) == "dressingroom-sideframe" then
			return region
		end
	end
end

local function SkinSidePanel(label, panel)
	if not panel then
		panels[#panels + 1] = { label = label }
		return
	end
	if done[panel] then
		return
	end
	done[panel] = true
	local art = SideFrameArt(panel)
	local rep
	if art then
		rep = Replace(art, { as = "common-insideframe", parent = panel, rect = panel, level = 0,
			alsoFade = List(panel.BlackBackground, panel.ClassBackground) })
	end
	panels[#panels + 1] = { label = label, panel = panel, rep = rep, art = art }
end

-- An outfit list row (DressUpCustomSetSlotFrameTemplate, pooled): its icon's
-- rim, fitted again whenever the game sets the row up (the icon's size).
local function SkinSlotRow(row)
	if not row or done[row] then
		return
	end
	done[row] = true
	local holder = SkinIconRim(row, row.Icon)
	if holder and row.SetDetails then
		hooksecurefunc(row, "SetDetails", function()
			if active then
				FitIconRim(holder)
			end
		end)
	end
end

local function RefreshSlotRows()
	local panel = Window() and Window().CustomSetDetailsPanel
	local pool = panel and panel.slotPool
	if not (active and pool and pool.EnumerateActive) then
		return
	end
	for row in pool:EnumerateActive() do
		SkinSlotRow(row)
	end
	for _, holder in ipairs(rims) do
		FitIconRim(holder)
	end
end

-- A transmog set row (DressUpFrameTransmogSetButtonTemplate, from the set
-- panel's scroll box): its backing on the list plate, its selected glow on
-- the plate's selected look (shown while the game shows the glow), the
-- icon's rim; the additive hover stays the game's.
local function SkinSetRow(row)
	if not row or done[row] then
		return
	end
	done[row] = true
	if row.BackgroundTexture then
		Replace(row.BackgroundTexture, { as = "PetList-ButtonBackground", rect = row })
	end
	local sel = row.SelectedTexture
	if sel then
		local rep = Replace(sel, { as = "PetList-ButtonSelect", rect = row })
		if rep then
			local function Sync()
				if active then
					rep:SetShown(sel:IsShown())
				end
			end
			hooksecurefunc(sel, "Show", Sync)
			hooksecurefunc(sel, "Hide", Sync)
			hooksecurefunc(sel, "SetShown", Sync)
			skin.followers[#skin.followers + 1] = { rep = rep, region = sel }
			Sync()
		end
	end
	SkinIconRim(row, row.Icon)
end

local function SkinPanels(f)
	local details = f.CustomSetDetailsPanel
	SkinSidePanel("outfit list", details)
	if details and details.Refresh and not done[details.Refresh] then
		done[details.Refresh] = true
		hooksecurefunc(details, "Refresh", RefreshSlotRows)
	end
	local sets = f.SetSelectionPanel
	SkinSidePanel("transmog set list", sets)
	local box = sets and sets.ScrollBox
	if box and not done[box] and ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
		done[box] = true
		ScrollUtil.AddAcquiredFrameCallback(box, function(_, row)
			if active then
				SkinSetRow(row)
			end
		end, M, false)
	end
end

-- the set list's rows the scroll box already holds (a list shown before the
-- kit was switched on)
local function RefreshSetRows(f)
	local box = f.SetSelectionPanel and f.SetSelectionPanel.ScrollBox
	if active and box and box.ForEachFrame and (not box.HasView or box:HasView()) then
		pcall(box.ForEachFrame, box, SkinSetRow)
	end
end

--------------------------------------------------------------------------------
-- Building, switching on and off
--------------------------------------------------------------------------------
-- (user, 2026-09-24: dress rarely used windows on first open): nothing is
-- built while the window has never been shown this session; its first show
-- builds it (the OnShow hook in Hook, below, before its first frame is drawn)
-- and it is kept from then on.
local function Build()
	local f = Window()
	if not f or (skin and skin.built) or not f:IsShown() then
		return
	end
	skin = skin or { reps = {}, followers = {} }
	skin.built = true

	-- the shell: outer rail, one page stone, the ring on the player's
	-- portrait, the title plate on the rail, close and maximize / minimize
	-- (no Bg on the window: the rail keeps its own stone body instead)
	local portrait = Portrait(f)
	local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = portrait, bg = f.Bg and "UI-Background-Rock" or nil })
	found.shell = string.format("NineSlice %s, page stone (Bg) %s, title container %s, close %s, maximize / minimize %s",
		tostring(f.NineSlice ~= nil), tostring(f.Bg ~= nil), tostring(f.TitleContainer ~= nil), tostring(f.CloseButton ~= nil),
		tostring(f.MaximizeMinimizeFrame ~= nil))
	skin.ring = ring
	SkinPortrait(portrait, ring)

	SkinInsetRail(f)
	SkinControls(f)
	SkinButtons(f)
	SkinPanels(f)
	-- whatever else the sweep knows (the set list's scroll bar); the model is
	-- not walked into (its buttons are the cogs above)
	Kit:SweepControls(f, Replace, skin, Model(f))
end

-- Refresh's pass a frame later, once the game's own layout has run (made
-- once: Kit:NextFrame runs it once however often it was asked -- audit,
-- 2026-09-24; timed on this window's own /melloperf row, not the Kit's
-- timer -- review)
local RefreshLater = Shared("Refresh a frame later", function()
	local f = Window()
	if active and f and f:IsShown() then
		FitRing()
		PlaceTitle()
		KeepRailOverModel(f)
		for _, holder in ipairs(rims) do
			FitIconRim(holder)
		end
	end
end, "timer")

-- After every show and resize: what the game re-laid or re-showed since (the
-- portrait's size, the title's plate, the page picture's crop, the rail over
-- the model, the rows' rims), and once more a frame later, once the game's
-- own layout has run.
local function Refresh()
	local f = Window()
	if not (active and skin and f) then
		return
	end
	SkinControls(f)
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	for _, rep in ipairs(skin.reps) do
		if rep.kind == "picture" then
			rep:Refit()
		end
	end
	KeepRailOverModel(f)
	RefreshSlotRows()
	RefreshSetRows(f)
	FitRing()
	PlaceTitle()
	Kit:NextFrame(skin, RefreshLater)
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
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	Refresh()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	if skin then
		-- (the ring's onDisable puts the portrait back, the title plate's the
		-- title's points and face)
		for _, rep in ipairs(skin.reps) do
			rep:Disable()
		end
	end
end

local function Sync()
	if M.isEnabled and Window() then
		Activate()
	else
		Deactivate()
	end
end

-- (the module's switch: queued out of combat as the other windows' skins are)
local function SyncSafe()
	Kit:WhenOutOfCombat(Sync)
end

-- (listen-only until the window is built: every handler here does nothing
-- while the kit is off)
local function Hook()
	local f = Window()
	if hooked or not f then
		return
	end
	hooked = true
	-- the window's show: on its first, the look built and switched on there
	-- and then (Activate), so the first frame it draws is dressed. Also in
	-- combat: the build makes frames and textures of ours, and what of the
	-- game's it moves or sizes are regions of this unprotected window (the
	-- portrait, the title string) -- nothing protected -- so a first open in
	-- a fight (an item previewed mid-combat) is dressed at once instead of
	-- showing the stock window until it ends.
	Perf.HookScript(f, "OnShow", function()
		if M.isEnabled and not active then
			Sync()
		end
		Refresh()
	end)
	-- maximize / minimize (ConfigureSize) resizes the window
	Perf.HookScript(f, "OnSizeChanged", Refresh)
	-- the side panels come and go with the appearance-list toggle
	for _, panel in ipairs({ f.CustomSetDetailsPanel or false, f.SetSelectionPanel or false }) do
		if panel then
			Perf.HookScript(panel, "OnShow", Refresh)
		end
	end
end

-- The window is in the game's UI panels on this client; a client that makes
-- it later is caught on the next addon load, until it exists.
local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(self)
	if Window() then
		self:UnregisterEvent("ADDON_LOADED")
		Hook()
		if M.isEnabled then
			SyncSafe()
		end
	end
end)

function M:OnEnable(db)
	self.db = db
	if Window() then
		Hook()
		SyncSafe()
	else
		eventFrame:RegisterEvent("ADDON_LOADED")
	end
end

function M:OnDisable()
	SyncSafe()
end

--------------------------------------------------------------------------------
-- /dressupdump [frames | reps | regions]: with no mode, what the skin found
-- and dressed (every part, found or not), the portrait against the class
-- medallion, the title's place and face, the page picture and the model's
-- pictures, and the window's own regions and children; the modes are
-- Kit:DumpWindow's. Opens the copy window.
--------------------------------------------------------------------------------
local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.0f", v) or "?"
end

local function RectText(obj)
	if not obj then
		return "(none)"
	end
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if ok and l and not (Secret(l) or Secret(b) or Secret(w) or Secret(h)) then
		return string.format("x=%.0f y=%.0f w=%.0f h=%.0f", l, b, w, h)
	end
	return "(no rect)"
end

local function Line(label, text)
	MelloUI:Print("  %-16s %s", label, text or "-- not looked at yet (the kit has not dressed the window)")
end

local function Dressed(obj)
	return tostring(obj ~= nil and obj.melloRep ~= nil and obj.melloRep ~= false)
end

local function DumpPortrait(f)
	for _, t in ipairs(PortraitCandidates(f)) do
		local okT, file = pcall(t.GetTexture, t)
		local okL, layer, sub = pcall(t.GetDrawLayer, t)
		Line("portrait cand.", string.format("%s art %s, layer %s %s, shown %s, parent %s%s", Label(t),
			okT and (Secret(file) and "[secret]" or tostring(file)) or "?", okL and tostring(layer) or "?", okL and tostring(sub) or "",
			tostring(Shown(t)), Label(t:GetParent()), (skin and skin.portrait == t) and "  <- in the ring" or ""))
	end
	Line("portrait", found.portrait)
	local p, ring = skin and skin.portrait, skin and skin.ring
	if p and ring and ring.tex then
		local okP, pw, ph = pcall(p.GetSize, p)
		local okR, rw = pcall(ring.tex.GetWidth, ring.tex)
		local medal = (okR and type(rw) == "number" and not Secret(rw)) and rw * MEDALLION_TO_RING or nil
		Line("vs medallion", string.format("portrait %s x %s, ring %s, medallion (0.759 x ring) %s, fitted %s, disc %s",
			okP and Num(pw) or "?", okP and Num(ph) or "?", okR and Num(rw) or "?", medal and string.format("%.0f", medal) or "?",
			tostring(p.melloSaved ~= nil), skin.disc and (Shown(skin.disc) and "shown" or "hidden") or "none"))
	end
end

local function DumpTitle(f)
	local rep = TitleRep()
	local plate = rep and (rep.strip or rep.object)
	Line("title plate", rep and string.format("%s, shown %s", RectText(plate), tostring(Shown(rep.object))) or "-- none")
	local fs = TitleText(f)
	if not fs then
		Line("title text", "-- not found")
		return
	end
	local okF, face, size = pcall(fs.GetFont, fs)
	local where = "?"
	local okC, cx, cy = pcall(fs.GetCenter, fs)
	local okP, px, py = false, nil, nil
	if plate then
		okP, px, py = pcall(plate.GetCenter, plate)
	end
	if okC and okP and cx and px and not (Secret(cx) or Secret(cy) or Secret(px) or Secret(py)) then
		where = string.format("%+.0f, %+.0f from the plate's centre", cx - px, cy - py)
	end
	Line("title text", string.format("%s '%s' %s; face %s %s, title face %s", Label(fs), tostring(TextOf(fs) or "?"), where,
		(okF and type(face) == "string" and not Secret(face)) and face or "?", okF and Num(size) or "?", tostring(fs.melloFontSaved ~= nil)))
end

local function DumpParts(f)
	Line("tabs", "none: the dressing room has no tabs")
	local page
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "UI-Background-Rock" then
			page = rep
		end
	end
	Line("page picture", page and string.format("%s, inner %s, shown %s", RectText(page.tex), RectText(page.inner), tostring(Shown(page.tex)))
		or "-- none (no Bg on this window)")
	Line("inset", found.inset)
	local model = Model(f)
	Line("model", model and string.format("%s (%s) level %s, rect %s, shown %s -- never covered", Label(model), tostring(model:GetObjectType()),
		tostring(LevelOf(model) or "?"), RectText(model), tostring(Shown(model))) or "-- not found")
	local ir = skin and skin.inset and skin.inset.melloRep
	Line("inset rail", (ir and ir.object) and string.format("level %s (the model's + 1)", tostring(LevelOf(ir.object) or "?")) or "-- none")
	for _, t in ipairs(ModelPictures(f)) do
		local okA, alpha = pcall(t.GetAlpha, t)
		Line("model picture", string.format("%s art %s, shown %s, alpha %s, faded %s (the game's)", Label(t), tostring(Kit:ArtKey(t) or "?"),
			tostring(Shown(t)), (okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?", tostring(Kit.faded[t] ~= nil)))
	end
	if #controls == 0 then
		Line("controls", "-- none found")
	end
	for _, c in ipairs(controls) do
		Line("control", string.format("%s cog %s, shown %s", Label(c.button), tostring(c.rep ~= nil), tostring(Shown(c.button))))
	end
	for _, entry in ipairs(TextButtons(f)) do
		local b = entry[2]
		local okE, enabled = false, nil
		if b then
			okE, enabled = pcall(b.IsEnabled, b)
		end
		Line("button", string.format("%s: %s", entry[1], b and string.format("%s (%s) red plate %s, shown %s, enabled %s", Label(b),
			tostring(b:GetObjectType()), Dressed(b), tostring(Shown(b)), (okE and not Secret(enabled)) and tostring(enabled) or "?")
			or "-- not on this client"))
	end
	Line("dropdown", found.dropdown)
	local toggle = f.ToggleCustomSetDetailsButton
	Line("list toggle", toggle and string.format("%s left the game's (its glyph is painted into its plate), shown %s", Label(toggle), tostring(Shown(toggle))) or "-- none")
	for _, p in ipairs(panels) do
		if p.panel then
			local dim = p.rep and p.rep.skin and p.rep.skin.dimFill
			Line("side panel", string.format("%s (%s): L1 box %s, inner panel %s, shown %s, rect %s", p.label, Label(p.panel),
				p.rep and "on" or (p.art and "NOT dressed" or "NOT dressed (no frame art found)"), dim and "on" or "none",
				tostring(Shown(p.panel)), RectText(p.panel)))
		else
			Line("side panel", p.label .. " -- not on this client")
		end
	end
	Line("icon rims", string.format("%d item icons in the Button Border rim (quality borders kept)", #rims))
	Line("inked strings", "none: the window is on stone (no parchment)")
end

local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer, sub = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "")
		elseif kind == "FontString" then
			art = "text: " .. tostring(TextOf(region) or ""):sub(1, 50)
		end
		local okA, alpha = pcall(region.GetAlpha, region)
		MelloUI:Print("  region %s %s %s %s %s alpha %s shown %s", kind, Label(region), okL and tostring(layer) or "?", okL and tostring(sub) or "",
			art, (okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?", tostring(Shown(region)))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		MelloUI:Print("  child %s %s level %s shown %s%s", tostring(child:GetObjectType()), Label(child),
			tostring(LevelOf(child) or "?"), tostring(Shown(child)), child.melloRep ~= nil and " (dressed)" or "")
	end
end

local function Summary(f)
	MelloUI:Print("DressUpFrame: shown %s, level %s, kit %s, reps %d", tostring(Shown(f)), tostring(LevelOf(f) or "?"),
		active and "on" or "off", skin and #skin.reps or 0)
	if not (skin and skin.built) then
		MelloUI:Print("DressUpFrame: not dressed yet (the kit dresses it on its first open this session)")
	end
	Line("shell", found.shell)
	DumpPortrait(f)
	DumpTitle(f)
	DumpParts(f)
	MelloUI:Print("DressUpFrame's own regions and children:")
	DumpOwn(f)
end

SLASH_MELLODRESSUPDUMP1 = "/dressupdump"
SlashCmdList.MELLODRESSUPDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if not f then
		MelloUI:Print("/dressupdump: no DressUpFrame: not on this client")
	elseif msg == "" then
		Summary(f)
	else
		if not (skin and skin.built) then
			MelloUI:Print("DressUpFrame: not dressed yet (the kit dresses it on its first open this session)")
		end
		-- frames / reps / regions (the visible game textures): the Kit's dump
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	end
	MelloUI:ShowLog("dressupdump " .. msg)
end
