--------------------------------------------------------------------------------
-- MelloUI - Pet Stable Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): the hunter's pet stable dressed in the painted kit
-- (Modules/Kit.lua) on the game's own layout, by the rule book
-- (docs/WINDOW-RULES.md): every kit piece stands in for one of the game's art
-- regions, on that region's rectangle, the game's art faded in its place.
--
-- This client's stable is PetStableFrame (Blizzard_StableUI, Camelot/: a
-- PortraitFrameTemplate window, 384 x 512): the selected pet's 3D model in a
-- ModelScene (its inset, a shadow vignette, the model's control strip, the
-- happiness icon, the experience bar under it), the pet's name / level /
-- family and loyalty over it, the loyalty level circle, the current pet's
-- slot and the stabled pets' slots under the model, the purchase button with
-- the next slot's cost, and the player's money on a coin strip. A client
-- with the newer stable (StableFrame, a list of pets) gets the window shell
-- and the sweep only.
--
--   the window shell     outer double rail with gem corners, the page stone,
--                        the ring with the stable master's (or the player's)
--                        portrait at the class medallion's size on the dark
--                        disc (2b), the title plate on the rail with the
--                        title container's string on it in the title face
--                        (2c), the close button (Kit:SkinWindowShell)
--   the model            NEVER covered: its inset's single rail round it
--                        (edges only, the inset's marble faded: the one page
--                        stone runs on behind the pet, as behind the
--                        character's model), the spec picture and the shadow
--                        vignette left as the game's; the control strip's
--                        square buttons on the cog plate (K2)
--   the pet info         the name / level / family and loyalty strings on a
--                        band of the palette's inner panel hugging them (2e:
--                        no text on the plain stone); the loyalty circle on
--                        the kit's orb, as the unit frames' level circle
--   the experience bar   P1: the bracket on the bar (the game's two-piece
--                        frame art faded), the trough under its fill
--   the pet slots        every window's Button Border rim on each slot (the
--                        game's quickslot square, its pushed / highlight /
--                        checked looks faded: the rim carries hover, press
--                        and the selected pet's gold), the pet's icon in
--                        the opening, the stone in the opening where the
--                        empty-slot picture was -- tinted red while the game
--                        tints that picture red (a slot not bought yet)
--   slots and cost       the area under the model (the slots' labels, the
--                        "stable slot" line, the cost) on the palette's
--                        inner panel (2e)
--   purchase             the red plate (B1)
--   the money            the coin plate (B2) on the money frame's border
--
-- Taint: nothing of the game's is replaced or re-scripted, nothing moved
-- but the portrait (brought to the medallion size) and the title (onto the
-- plate), each put back on disable. Post-hooks (the window's Update /
-- SelectPet, HookScript, the slots' own SetVertexColor) only; what the skin
-- keeps about the game's frames lives in weak side tables; no stable
-- function is ever called. The pet slots are check buttons: only textures
-- and frames of our own are added to them, their art faded.
--
-- /stabledump [frames | reps | regions]: what the window is made of on this
-- client and what the skin dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("StablePanel")
local hooksecurefunc = Perf.hooksecurefunc
-- a handler made once and run for many asks, wrapped once: its time stays
-- on this file's own /melloperf row (review, 2026-09-24)
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("StablePanel", {
	title = "Pet Stable Kit",
	desc = "The hunter's pet stable in the kit.",
	window = { label = "Pet stable", desc = "The hunter's pet stable in the kit.", tab = "Windows",
		frames = { "PetStableFrame", "StableFrame" }, plainGrab = true, addon = "Blizzard_StableUI", firstOpen = true },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local ADDON = "Blizzard_StableUI"
local MAX_SLOTS = 12         -- PetStableStabledPet1..n: looked for until the first missing one
local PANEL_SUB = -4         -- the inner panel: over the page stone (the window's Bg), under the portrait's disc
local INFO_PAD = 12          -- px the pet info band reaches past its longest string on each side
local RING_ROOM = 70         -- px kept free at each end of the band (the ring on the left, the loyalty circle on the right)

local skin = nil          -- { reps = { every replacement }, built, ring, portrait }
local active = false
local hooked = false

-- what this module made or looked at, kept OFF the game's frames (weak keys)
local done = setmetatable({}, { __mode = "k" })          -- [frame / region] = true: looked at once
local slotStones = {}                                    -- { button, stone (Kit:SlotStone's rep), bg (the game's empty-slot picture) }
local panels = {}                                        -- our inner-panel textures
local found = {}                                         -- [part] = a line for /stabledump
local info = nil                                         -- the pet info band { rect, tex, strings }

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
			MelloUI:Notice("Pet stable kit: no kit piece mapped for %s", tostring(key))
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

-- a frame's name, secret-safe (nil when it has none or it reads secret)
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

-- a font string's text when it can be read (nil when empty or secret)
local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	if ok and type(text) == "string" and not Secret(text) and text ~= "" then
		return text
	end
	return nil
end

local function HasText(fs)
	local ok, text = pcall(fs.GetText, fs)
	if not ok then
		return false
	end
	if Secret(text) then
		return true
	end
	return type(text) == "string" and text ~= ""
end

local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.0f", v) or "?"
end

local function Width(obj)
	local ok, w = pcall(obj.GetWidth, obj)
	if ok and type(w) == "number" and not Secret(w) then
		return w
	end
	return nil
end

local function Shown(obj)
	local ok, s = pcall(obj.IsShown, obj)
	return (ok and not Secret(s)) and tostring(s) or "?"
end

-- The window: the classic stable (PetStableFrame), else the newer list
-- stable (StableFrame)
local function Window()
	return _G.PetStableFrame or _G.StableFrame
end

local function IsClassic(f)
	return f ~= nil and f == _G.PetStableFrame
end

local function ModelScene(f)
	return f and (f.modelScene or f.ModelScene) or nil
end

local function Portrait(f)
	local pc = f and f.PortraitContainer
	return (pc and pc.portrait) or (f and f.portrait) or _G.PetStableFramePortrait
end

-- the pet slots: the current pet's, then the stabled ones'
local function Slots()
	local list = List(_G.PetStableCurrentPet)
	for i = 1, MAX_SLOTS do
		local b = _G["PetStableStabledPet" .. i]
		if not b then
			break
		end
		list[#list + 1] = b
	end
	return list
end

-- An inner-panel texture of `host` on `rect` (WINDOW-RULES 2e), shown while
-- the kit is on
local function Panel(host, rect)
	if not (host and Kit.StoneDim) then
		return nil
	end
	local tex = Kit:StoneDim(host, { rect = rect, sublevel = PANEL_SUB })
	if tex then
		tex.kitPiece = true      -- ours: never taken for the game's art
		tex:SetShown(active)
		panels[#panels + 1] = tex
	end
	return tex
end

--------------------------------------------------------------------------------
-- The portrait (WINDOW-RULES 2b / 2c: an empty ring is a bug). The game draws
-- the stable master (or the player) into the PortraitContainer's portrait on
-- every show (SetPortraitToUnit): the kit's ring on the corner, the portrait
-- at the class medallion's size in it on the dark disc; put back on disable.
--------------------------------------------------------------------------------
local function FitPortrait()
	if active and skin and skin.ring and skin.portrait then
		pcall(Kit.FitPortrait, Kit, skin.portrait, skin.ring)
	end
end

local function SkinPortrait(f, ring)
	local portrait = Portrait(f)
	if not (ring and portrait) then
		found.portrait = "-- no ring (no NineSlice corner or no portrait on this client)"
		return
	end
	skin.ring, skin.portrait = ring, portrait
	ring.onEnable = function()
		pcall(Kit.FitPortrait, Kit, portrait, ring)
	end
	ring.onDisable = function()
		pcall(Kit.UnfitPortrait, Kit, portrait)
	end
	local disc = Kit:RingDisc(ring, nil, f.PortraitContainer or ring.object:GetParent(), 0)
	found.portrait = string.format("%s in the ring, disc %s", Label(portrait), disc and "made" or "NOT made")
end

-- The title plate's rule (the shell) centres the title container's string on
-- the plate in the title face; fitted again on every show
local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
	end
end

local function PlaceTitle()
	local rep = TitleRep()
	if not (active and rep and rep.object and rep.object:IsShown()) then
		return
	end
	if rep.Refit then
		rep:Refit()
	end
	local f = Window()
	local text = f and f.TitleContainer and f.TitleContainer.TitleText
	if text and not text.melloFontSaved then
		Kit:TitleFont(text, true)
	end
end

--------------------------------------------------------------------------------
-- The model (never covered). Its inset (InsetFrameTemplate on the scene's
-- rect, at the scene's level) -> the single rail, edges only, the inset's
-- marble faded (Kit:SkinInset): behind the pet the one page stone runs on,
-- as behind the character's model (one stone per surface). The spec picture
-- (Background, set only for pets with a specialization, alpha 0.8), the
-- ground shadow and the vignette stay the game's. The control strip's square
-- buttons (common-button-square-gray-*) -> the cog plate K2 under the game's
-- glyph; their additive hover stays the game's.
--------------------------------------------------------------------------------
local function SkinModel(f)
	local ms = ModelScene(f)
	if not ms then
		found.model = "-- no model scene"
		return
	end
	local inset = ms.Inset
	if inset and inset.melloRep == nil then
		Kit:SkinInset(inset, Replace, ms)
	end
	local strip = ms.ControlFrame
	local n, total = 0, 0
	if strip then
		for _, b in ipairs({ strip:GetChildren() }) do
			if b:GetObjectType() == "Button" and not done[b] then
				done[b] = true
				total = total + 1
				local normal = b.GetNormalTexture and b:GetNormalTexture()
				if normal then
					local rep = Replace(normal, { as = "UI-SquareButton-Up", button = b, alsoFade = List(b.GetPushedTexture and b:GetPushedTexture()) })
					if rep then
						n = n + 1
					end
				end
			end
		end
	end
	found.model = string.format("%s at level %s; inset %s (rail %s); control strip %s: %d of %d buttons on the cog plate; spec picture %s (left as the game's)",
		Label(ms), Num(ms:GetFrameLevel()), inset and Label(inset) or "-- none",
		tostring(inset ~= nil and inset.melloRep ~= nil and inset.melloRep ~= false),
		strip and Label(strip) or "-- none", n, total, ms.Background and tostring(Kit:ArtKey(ms.Background) or "(empty)") or "-- none")
end

--------------------------------------------------------------------------------
-- The pet info (WINDOW-RULES 2e): PetStableLevelText (name, level, family:
-- GameFontNormal) and PetStableLoyaltyText under it (the loyalty's name,
-- small) centred at the window's top, beside the ring. A band of the inner
-- panel hugs them: centred as they are, from the first string's top to the
-- last one's bottom, as wide as the longer one plus a margin (kept clear of
-- the ring and the loyalty circle), re-measured after each SetText; hidden
-- while neither string has text.
--------------------------------------------------------------------------------
local function InfoStrings()
	return List(_G.PetStableLevelText, _G.PetStableLoyaltyText)
end

local function FitInfo()
	if not info then
		return
	end
	local widest, any = 0, false
	for _, fs in ipairs(info.strings) do
		if HasText(fs) then
			any = true
			local ok, w = pcall(fs.GetStringWidth, fs)
			if ok and type(w) == "number" and not Secret(w) and w > widest then
				widest = w
			end
		end
	end
	local f = Window()
	local fw = f and Width(f)
	local w = widest + 2 * INFO_PAD
	if fw and fw > 2 * RING_ROOM then
		w = math.min(w, fw - 2 * RING_ROOM)
	end
	info.rect:SetWidth(math.max(w, 1))
	info.tex:SetShown((active and any) and true or false)
end

local function SkinInfo(f)
	local strings = InfoStrings()
	if #strings == 0 then
		found.info = "-- no PetStableLevelText / PetStableLoyaltyText"
		return
	end
	if info then
		return
	end
	local first, last = strings[1], strings[#strings]
	local rect = CreateFrame("Frame", nil, f)
	rect:EnableMouse(false)
	rect:SetPoint("TOP", first, "TOP", 0, 4)
	rect:SetPoint("BOTTOM", last, "BOTTOM", 0, -4)
	rect:SetWidth(1)
	-- (not one of the panels shown with the kit: this one follows the text)
	local tex = Kit.StoneDim and Kit:StoneDim(f, { rect = rect, sublevel = PANEL_SUB }) or nil
	if not tex then
		found.info = "-- the band could not be made"
		return
	end
	tex.kitPiece = true
	tex:Hide()
	info = { rect = rect, tex = tex, strings = strings }
	for _, fs in ipairs(strings) do
		hooksecurefunc(fs, "SetText", FitInfo)
	end
	FitInfo()
	found.info = string.format("band on %s%s", Label(first), last ~= first and (" .. " .. Label(last)) or "")
end

-- The loyalty level circle (PetStableLoyaltyLevelTemplate: the boss icon
-- ring in BACKGROUND, the level number on it) -> the kit's orb plate, as the
-- unit frames' level circle, under the frame's own number
local function SkinLoyalty(f)
	local lv = f.loyaltyLevel
	if not lv then
		found.loyalty = "-- none"
		return
	end
	if done[lv] then
		return
	end
	done[lv] = true
	local circle = Kit:FirstTexture(lv)
	local rep = circle and Replace(circle, { as = "UI-HUD-UnitFrame-SmallCircle" }) or nil
	found.loyalty = string.format("%s: circle %s, orb %s", Label(lv), circle and tostring(Kit:ArtKey(circle) or "?") or "-- none",
		rep and "on" or "NOT made")
end

--------------------------------------------------------------------------------
-- The experience bar (PetExpStatusBarTemplate: a StatusTrackingBar -- its
-- StatusBar at the bar's own strata, the trough art in its Background -- with
-- an overlay frame at HIGH carrying the old two-piece bar frame and the
-- text): P1, the bracket as ARTWORK regions of the overlay (over the fill,
-- under its OVERLAY text), the trough on a holder one level under the fill
-- at the fill's strata; the frame art and the trough art faded. Hidden with
-- the bar at the pet's top level.
--------------------------------------------------------------------------------
local function SkinExpBar(f)
	local bar = f.expBar
	if not bar then
		found.exp = "-- none"
		return
	end
	if done[bar] then
		return
	end
	done[bar] = true
	local overlay, fill = bar.overlay, bar.StatusBar
	if not (overlay and fill) then
		found.exp = string.format("%s: -- no overlay / StatusBar on this client", Label(bar))
		return
	end
	local art = {}
	for _, region in ipairs({ overlay:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			art[#art + 1] = region
		end
	end
	local first = table.remove(art, 1)
	if not first then
		found.exp = string.format("%s: -- no frame art on the overlay", Label(bar))
		return
	end
	local under = CreateFrame("Frame", nil, bar)
	under:EnableMouse(false)
	under:SetAllPoints(fill)
	local okS, strata = pcall(fill.GetFrameStrata, fill)
	under:SetFrameStrata((okS and type(strata) == "string") and strata or "LOW")
	local okL, level = pcall(fill.GetFrameLevel, fill)
	under:SetFrameLevel(math.max(((okL and type(level) == "number" and not Secret(level)) and level or 1) - 1, 0))
	local rep = Replace(first, { as = "UI-HUD-ExperienceBar-Frame", parent = overlay, rect = fill, layer = "ARTWORK", sublevel = 2,
		troughParent = under, troughLayer = "ARTWORK", troughSub = 0, alsoFade = art })
	if fill.Background then
		Replace(fill.Background, { as = "UI-HUD-ExperienceBar-Background" })
	end
	found.exp = string.format("%s: P1 %s (%d frame pieces faded), shown %s", Label(bar), rep and "on" or "NOT made", #art + 1, Shown(bar))
end

--------------------------------------------------------------------------------
-- The pet slots (PetStableSlotTemplate: 37 px check buttons with the pet's
-- icon ($parentIconTexture, BORDER), the empty-slot picture (UI-EmptySlot,
-- BACKGROUND, tinted red by the game for a slot not bought yet), the
-- quickslot square as the normal texture, pushed / highlight / checked
-- looks). Every window's Button Border rim on the button (its states: the
-- selected pet's slot is the checked one, gold), the icon fitted into its
-- opening; the kit's slot stone (Kit:SlotStone) in the opening under the
-- icon in place of the empty-slot picture, always shown and tinted as the
-- game tints that picture. The Kit's own marker is set on each slot (the
-- sweep would take a 37 px check button for a check box).
--------------------------------------------------------------------------------
local function EmptyPicture(b)
	if b.background then
		return b.background
	end
	for _, region in ipairs({ b:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			local ok, layer = pcall(region.GetDrawLayer, region)
			if ok and layer == "BACKGROUND" then
				return region
			end
		end
	end
end

local function SkinSlot(b)
	if not b or done[b] then
		return
	end
	done[b] = true
	local normal = b.GetNormalTexture and b:GetNormalTexture()
	local icon = b.Icon or b.icon or _G[(NameOf(b) or "") .. "IconTexture"]
	if not (normal and icon) then
		if b.melloRep == nil then
			b.melloRep = false
		end
		return
	end
	local extra = List(b.GetPushedTexture and b:GetPushedTexture(), b.GetHighlightTexture and b:GetHighlightTexture(),
		b.GetCheckedTexture and b:GetCheckedTexture())
	local rep = Replace(normal, { as = Kit:ButtonRimRule(), button = b, rect = b, icon = icon, alsoFade = extra })
	b.melloRep = rep or false
	if not rep then
		return
	end
	-- the one Button Border of every window, changed on all rims at once
	Kit:RegisterButtonRim(b)
	-- the stone in the rim's opening, in place of the empty-slot picture: the
	-- kit's one slot stone (audit, 2026-09-24: this window kept a copy of its
	-- fit, which missed the kit's fixes), shown always -- not only while the
	-- slot is empty, as on the action buttons -- and tinted from the picture
	-- (red while the game tints it red: a slot not bought yet). Fitted again
	-- by the kit whenever the rim changes or was not laid out yet.
	local bg = EmptyPicture(b)
	local stone = Kit:SlotStone(rep, b, bg, { replace = Replace, base = "buttons/rim", showWhen = "always", tintFrom = bg, icon = icon })
	slotStones[#slotStones + 1] = { button = b, stone = stone, bg = bg }
end

--------------------------------------------------------------------------------
-- The area under the model (WINDOW-RULES 2e): the slots' "Current Pet" /
-- "Stabled Pets" labels, the "stable slot" line and the cost are small text
-- on the stone; the palette's inner panel lies under them, from just below
-- the model to the money strip, on the model's width. The coin strip itself
-- (PetStableMoneyFrame.Border, ContainerFrameCurrencyBorderTemplate: Left /
-- Middle / Right on the coinbox atlases) -> the coin plate B2, one level
-- under the coins.
--------------------------------------------------------------------------------
local function SkinLower(f)
	if done.lower then
		return
	end
	done.lower = true
	local ms = ModelScene(f)
	local money = _G.PetStableMoneyFrame
	if ms and money then
		local rect = CreateFrame("Frame", nil, f)
		rect:EnableMouse(false)
		rect:SetPoint("TOPLEFT", ms, "BOTTOMLEFT", 0, -2)
		rect:SetPoint("BOTTOMRIGHT", money, "TOPRIGHT", 0, 0)
		local tex = Panel(f, rect)
		found.lower = string.format("inner panel %s (model's bottom to the money strip)", tex and "on" or "NOT made")
	else
		found.lower = "-- no model scene or money frame to lay the panel between"
	end
	local border = money and money.Border
	if border and border.Middle then
		local rep = Replace(border.Middle, { as = "common-coinbox-center", parent = border, rect = border, level = -1,
			alsoFade = List(border.Left, border.Right) })
		found.money = string.format("%s: coin plate %s", Label(money), rep and "on" or "NOT made")
	else
		found.money = money and string.format("%s: -- no Border with Left / Middle / Right", Label(money)) or "-- no PetStableMoneyFrame"
	end
end

--------------------------------------------------------------------------------
-- Building, switching on and off
--------------------------------------------------------------------------------
local function Build()
	local f = Window()
	if not f then
		return
	end
	skin = skin or { reps = {}, followers = {} }
	if skin.built then
		return
	end
	skin.built = true

	-- the shell: outer rail, one page stone, the ring, the title plate on the
	-- rail, the close button
	local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = Portrait(f), bg = "UI-Background-Rock" })
	found.shell = string.format("%s: NineSlice %s, page stone (Bg) %s, title container %s, close %s",
		IsClassic(f) and "the classic stable" or "the newer list stable", tostring(f.NineSlice ~= nil),
		tostring(f.Bg ~= nil), tostring(f.TitleContainer ~= nil), tostring(f.CloseButton ~= nil))
	SkinPortrait(f, ring)

	if IsClassic(f) then
		SkinModel(f)
		SkinInfo(f)
		SkinLoyalty(f)
		SkinExpBar(f)
		local n = 0
		for _, b in ipairs(Slots()) do
			SkinSlot(b)
			n = n + 1
		end
		found.slots = string.format("%d slots, %d with the rim", n, #slotStones)
		SkinLower(f)
		local buy = f.purchaseButton
		local rep = buy and Kit:SkinRedButton(buy, Replace)
		if buy then
			buy.melloNoInk = true
		end
		found.purchase = buy and string.format("%s: red plate %s", Label(buy), rep and "on" or "NOT made") or "-- not found"
	else
		found.model = "-- the newer list stable: its model and list are left as the game's (shell and controls only)"
	end

	-- whatever else the sweep knows (the model is not walked into: its
	-- buttons are the cog plates above; the slots carry the Kit's marker)
	Kit:SweepControls(f, Replace, skin, ModelScene(f))
end

-- Refresh's pass a frame later, once the window is laid out (made once:
-- Kit:NextFrame runs it once however often it was asked -- audit, 2026-09-24;
-- timed on this window's own /melloperf row, not the Kit's timer -- review).
-- The slots' stones are the kit's to fit again (Kit:SlotStone: on a new rim
-- art, and a frame later when a rim was not laid out yet).
local RefreshLater = Shared("Refresh a frame later", function()
	local f = Window()
	if active and f and f:IsShown() then
		FitPortrait()
		PlaceTitle()
		FitInfo()
	end
end, "timer")

-- After every show and every game update (a pet selected, swapped, a slot
-- bought): the portrait, the title, the band, the slots' tints and the
-- rims; once more a frame later, when the window is laid out.
local function Refresh()
	local f = Window()
	if not (active and skin and f) then
		return
	end
	FitPortrait()
	PlaceTitle()
	FitInfo()
	for _, entry in ipairs(slotStones) do
		Kit:SyncSlotStone(entry.button)
		local rep = entry.button.melloRep
		local rim = rep and rep.object
		if rim and rim.Update then
			rim:Update()
		end
	end
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
	for _, tex in ipairs(panels) do
		tex:Show()
	end
	Refresh()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	if skin then
		for _, rep in ipairs(skin.reps) do
			rep:Disable()
		end
	end
	for _, tex in ipairs(panels) do
		tex:Hide()
	end
	if info then
		info.tex:Hide()
	end
end

-- (user, 2026-09-24: "dress rarely used windows on first open") nothing of
-- the look is built while the window has never been shown this session: a
-- skin already built is switched on (and off), else only a window open right
-- now (a /reload with it open) is dressed at once; its first show dresses it
-- (the OnShow hook below), in that same frame, so it never draws undressed.
-- The window's mover (UI Modifications) comes with the kit's shell, so it too
-- first exists on that show (its saved place put back there); a stable the
-- kit was switched off for before it ever opened has none, as with the kit
-- off at login (the stable has no plain grab of its own).
local function Sync()
	local f = Window()
	if M.isEnabled and f and ((skin and skin.built) or f:IsShown()) then
		Activate()
	else
		Deactivate()
	end
end

-- (geometry of the window's children changes here: out of combat only)
local function SyncSafe()
	Kit:WhenOutOfCombat(Sync)
end

-- The first show in combat dresses at once all the same: the dressing adds
-- frames and textures of ours (the pet slots only get textures and frames
-- added) and moves or sizes only the window's own portrait and title, never
-- a protected frame (the stable has none). A window the game protects waits
-- for the fight's end, as before.
local function DressOnShow()
	local f = Window()
	local ok, protected = pcall(f.IsProtected, f)
	if InCombatLockdown() and ok and not Secret(protected) and not protected then
		Sync()
	else
		SyncSafe()
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
			DressOnShow()     -- (Activate refreshes what it dressed)
		else
			Refresh()
		end
	end)
	-- the window's own refresh and pet selection (methods of its instance)
	for _, method in ipairs({ "Update", "SelectPet" }) do
		if type(f[method]) == "function" then
			hooksecurefunc(f, method, Refresh)
		end
	end
end

-- The stable may be load on demand (Blizzard_StableUI; this client loads it
-- with the interface): hooked when that addon loads, or at once if it
-- already has, and dressed as it first shows.
local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(self, _, name)
	if (name == ADDON or Window()) and Window() then
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
-- /stabledump [frames | reps | regions]: with no mode, what the skin found
-- and dressed (every part, found or not), the portrait against the
-- medallion, the title's place and font, the slots, and the window's own
-- regions and children; the modes are Kit:DumpWindow's. Opens the copy window.
--------------------------------------------------------------------------------
local function Line(label, text)
	MelloUI:Print("  %-16s %s", label, text or "-- not looked at yet (the kit has not dressed the window)")
end

-- whether the game tints a slot's empty-slot picture red (a slot not bought
-- yet: its stone wears that red)
local function Locked(bg)
	local ok, r, g = pcall(bg.GetVertexColor, bg)
	return ok and not Secret(r) and not Secret(g) and type(r) == "number" and type(g) == "number" and r > 0.5 and g < 0.5
end

local function Rect(obj)
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if ok and l and not Secret(l) and not Secret(b) and not Secret(w) and not Secret(h) then
		return string.format("x=%s y=%s w=%s h=%s", Num(l), Num(b), Num(w), Num(h))
	end
	return "(no rect)"
end

local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer, sub = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "")
		elseif kind == "FontString" then
			art = "text: " .. tostring(TextOf(region) or (HasText(region) and "[secret]" or "")):sub(1, 40)
		end
		local okA, alpha = pcall(region.GetAlpha, region)
		MelloUI:Print("  region %s %s %s %s %s alpha %s shown %s faded %s", kind, Label(region), okL and tostring(layer) or "?",
			okL and tostring(sub) or "", art, (okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?", Shown(region),
			tostring(Kit.faded[region] == true))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local okLv, lv = pcall(child.GetFrameLevel, child)
		MelloUI:Print("  child %s %s level %s shown %s%s", tostring(child:GetObjectType()), Label(child),
			okLv and Num(lv) or "?", Shown(child), child.melloRep ~= nil and " (marked)" or "")
	end
end

local function Summary(f)
	local okLv, lv = pcall(f.GetFrameLevel, f)
	MelloUI:Print("%s: shown %s, level %s, kit %s, reps %d", Label(f), Shown(f), okLv and Num(lv) or "?",
		active and "on" or "off", skin and #skin.reps or 0)
	Line("shell", found.shell)
	local portrait = Portrait(f)
	if portrait then
		local okT, file = pcall(portrait.GetTexture, portrait)
		local okS, w, h = pcall(portrait.GetSize, portrait)
		local ringW = skin and skin.ring and skin.ring.tex and Width(skin.ring.tex)
		Line("portrait", string.format("%s file %s, size %s x %s, medallion %s, fitted %s, shown %s", Label(portrait),
			(okT and not Secret(file)) and tostring(file) or "?", okS and Num(w) or "?", okS and Num(h) or "?",
			ringW and Num(ringW * 0.759) or "?", tostring(portrait.melloSaved ~= nil), Shown(portrait)))
	else
		Line("portrait", "-- not found")
	end
	Line("ring", found.portrait)
	local rep = TitleRep()
	Line("title plate", rep and string.format("%s, %s", (rep.object and rep.object:IsShown()) and "shown" or "hidden",
		rep.strip and Rect(rep.strip) or "") or "-- none")
	local title = f.TitleContainer and f.TitleContainer.TitleText
	if title then
		local okF, face, size = pcall(title.GetFont, title)
		Line("title text", string.format("%s '%s' at %s, face %s %s, title face %s%s", Label(title),
			tostring(TextOf(title) or (HasText(title) and "[secret]" or "(empty)")), Rect(title),
			(okF and type(face) == "string" and not Secret(face)) and face or "?", okF and Num(size) or "?",
			tostring(title.melloFontSaved ~= nil), HasText(title) and "" or " -- the game gives this window no title string"))
	else
		Line("title text", "-- no TitleContainer.TitleText")
	end
	Line("tabs", "-- none (the window has no tabs)")
	Line("page picture", f.Bg and string.format("Bg at %s, faded %s (the page stone stands on the window's rect inside the outer rail)",
		Rect(f.Bg), tostring(Kit.faded[f.Bg] == true)) or "-- no Bg")
	Line("model", found.model)
	local ms = ModelScene(f)
	if ms then
		Line("  model rect", Rect(ms))
	end
	Line("pet info", found.info)
	for _, fs in ipairs(InfoStrings()) do
		Line("  string", string.format("%s '%s' shown %s", Label(fs), tostring(TextOf(fs) or (HasText(fs) and "[secret]" or "(empty)")), Shown(fs)))
	end
	if info then
		Line("  band", string.format("%s shown %s", Rect(info.rect), Shown(info.tex)))
	end
	Line("loyalty", found.loyalty)
	Line("experience", found.exp)
	Line("slots", found.slots)
	for _, b in ipairs(Slots()) do
		local entry
		for _, e in ipairs(slotStones) do
			if e.button == b then
				entry = e
			end
		end
		local okC, checked = pcall(b.GetChecked, b)
		local rim = b.melloRep and b.melloRep.object
		Line("  slot", string.format("%s shown %s, checked %s, rim %s (%s), stone %s, locked (red) %s", Label(b), Shown(b),
			(okC and not Secret(checked)) and tostring(checked) or "?", tostring(rim ~= nil), rim and tostring(rim.base) or "-",
			tostring(entry ~= nil and entry.stone ~= nil), entry and tostring(entry.stone ~= nil and Locked(entry.bg)) or "-"))
	end
	Line("lower panel", found.lower)
	Line("purchase", found.purchase)
	for _, fs in ipairs(List(_G.PetStableSlotText, _G.PetStableCostLabel)) do
		Line("  text", string.format("%s '%s' shown %s", Label(fs), tostring(TextOf(fs) or "(empty)"), Shown(fs)))
	end
	Line("cost", _G.PetStableCostMoneyFrame and string.format("%s shown %s", Label(_G.PetStableCostMoneyFrame), Shown(_G.PetStableCostMoneyFrame)) or "-- none")
	Line("money", found.money)
	Line("inner panels", string.format("%d (and the pet info band)", #panels))
	Line("inked strings", "-- none (no parchment page on this window: its text lies on the dark panels)")
	MelloUI:Print("%s's own regions and children:", Label(f))
	DumpOwn(f)
end

SLASH_MELLOSTABLEDUMP1 = "/stabledump"
SlashCmdList.MELLOSTABLEDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if not f then
		MelloUI:Print("/stabledump: no PetStableFrame or StableFrame: not on this client (or %s not loaded yet: visit a stable master, "
			.. "then try again)", ADDON)
	elseif not skin then
		MelloUI:Print("/stabledump: the stable is not dressed yet (%s)", M.isEnabled
			and "the kit dresses it the first time it opens: visit a stable master, then try again" or "the Pet Stable Kit is off")
	elseif msg == "" then
		Summary(f)
	else
		-- frames / reps / regions (the visible game textures): the Kit's dump
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	end
	MelloUI:ShowLog("stabledump " .. msg)
end
