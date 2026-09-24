--------------------------------------------------------------------------------
-- MelloUI - Macros Kit
--
-- (user, 2026-09-24: "and the macros menu, edit mode menu, addons list, and
-- the whole options settings menu"): the macro window (MacroFrame, from the
-- load-on-demand Blizzard_MacroUI: general and character macros, the icon
-- picker) dressed in the painted kit (Modules/Kit.lua) on the game's own
-- layout, as every other window is (docs/WINDOW-RULES.md): every kit piece
-- stands in for one of the game's art regions, on that region's rectangle,
-- faded in place of it; nothing of the game's is replaced or moved but the
-- portrait (brought to the medallion size and put back on disable).
--
--   the window shell     outer double rail with gem corners, the page stone,
--                        the ring with the window's icon drawn in it by the
--                        kit at the class medallion's size on the dark disc,
--                        the title plate on the rail with the title ON it in
--                        the title face, the close button (Kit:SkinWindowShell)
--   the grid's inset     on the dark panel (the list-box stone under the
--                        palette's inner panel, WINDOW-RULES 2e)
--   the two top tabs     TB6 cards (Kit:SkinPanelTab; an older tab template
--                        with a LeftDisabled set gets the same two cards)
--   the macro grid and   every window's Button Border rim round each icon,
--   the selected macro   gold while the game marks the macro selected; the
--                        game's empty-slot square under it faded
--   the command box      the inset box (single rail, stone under the inner
--                        panel), so the macro text reads on a sunk panel
--   the dividers         the class-trainer bars faded (their rule), the
--                        button bar's gold dividers faded with them
--   buttons, scroll      red plates, the minimal scroll bar, dropdowns,
--   bars, insets         insets by the sweep (Kit:SweepControls)
--   the icon picker      MacroPopupFrame (the icon selector popup): the
--                        single rail with its stone in place of the popup's
--                        own box, the name box on the edit plate, its icons
--                        in the Button Border like the macro grid
--
-- The grids are pooled by their scroll boxes: each button is dressed once,
-- as the box first initialises it, and the rim follows its re-use through
-- the game's own selection texture. Switching the module off disables
-- every replacement (the game's art faded back in, ours hidden), un-fades
-- the dividers and puts the portrait back: the window is the game's again.
--
-- /macrodump [frames | reps | regions | popup [frames | reps | regions]]:
-- what the window (or the icon picker) is made of on this client and what
-- the skin dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("MacroPanel", {
	title = "Macros Kit",
	desc = "The macro window (general and character macros, the icon picker) in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil          -- { reps = { every replacement }, followers = { { rep, region } } }
local active = false
local hooked = false

-- what this module made, kept OFF the game's frames (weak keys: a pooled
-- button the game throws away takes its entry with it)
local done = setmetatable({}, { __mode = "k" })         -- [frame] = true: looked at once
local boxHooked = setmetatable({}, { __mode = "k" })    -- [scroll box] = true: its callback registered
local iconRims = {}                                     -- the icon rims' holders, refitted on a new Button Border
local tabReps = {}                                      -- the tabs' cards { rep, region } (kept hidden while the kit is off)
local fadedArt = {}                                     -- art faded with no piece standing in (the button bar's dividers)
local stats = { icons = 0, tabs = 0, bars = 0 }         -- for /macrodump

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Macros kit: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- A piece the game shows and hides itself (a tab's two looks, the inset):
-- shown with its region while the kit is on.
local function Follow(rep, region)
	if not (rep and region) then
		return
	end
	local function Sync()
		if active then
			rep:SetShown(region:IsShown())
		end
	end
	hooksecurefunc(region, "Show", Sync)
	hooksecurefunc(region, "Hide", Sync)
	hooksecurefunc(region, "SetShown", Sync)
	skin.followers[#skin.followers + 1] = { rep = rep, region = region }
	Sync()
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

-- a frame's name for the dump (a pooled frame's can read secret)
local function NameOf(obj)
	if not obj then
		return "nil"
	end
	local ok, n = pcall(obj.GetName, obj)
	if ok and type(n) == "string" and not Secret(n) then
		return n
	end
	local okD, d = pcall(obj.GetDebugName, obj)
	if okD and type(d) == "string" and not Secret(d) then
		return d
	end
	return "[unnamed]"
end

local function Window()
	return _G.MacroFrame
end

local function Popup()
	return _G.MacroPopupFrame
end

-- The window's portrait: PortraitFrameTemplate's container, else the older
-- named texture.
local function Portrait(f)
	local pc = f and f.PortraitContainer
	return (pc and pc.portrait) or (f and f.portrait) or _G.MacroFramePortrait
end

--------------------------------------------------------------------------------
-- Icons in the Button Border (the macro grid, the selected macro, the icon
-- picker's grid and its current icon): the rim hugs the icon -- its edge
-- 2 px under the rim's inner edge, on the icon's centre -- and the icon
-- stays where the game puts it, so the game's layout of its pooled buttons
-- is never fought (the equipment manager's picker, CharacterPanel, is the
-- same popup and the same recipe). A holder { melloRep = the rim, icon }
-- stands for the icon in the Kit's Button Border registry.
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

-- a new Button Border has a new opening: every icon's rim fitted again
Kit:OnBorderChanged("button", function()
	for _, holder in ipairs(iconRims) do
		FitIconRim(holder)
	end
end)

-- the icon of a macro / picker button: SelectorButtonTemplate's Icon (its
-- NormalTexture), an older template's named "<button>Icon"
local function IconOf(button)
	local icon = button.Icon or button.icon
	if not icon then
		local name = button.GetName and button:GetName()
		icon = type(name) == "string" and not Secret(name) and _G[name .. "Icon"] or nil
	end
	if not icon and button.GetNormalTexture then
		icon = button:GetNormalTexture()
	end
	return icon
end

-- the square the game draws round the icon: the button's BACKGROUND
-- texture (UI-EmptySlot-Disabled in SelectorButtonTemplate)
local function BackOf(button, icon)
	for _, region in ipairs({ button:GetRegions() }) do
		if region ~= icon and region:GetObjectType() == "Texture" and not region.kitPiece then
			local ok, layer = pcall(region.GetDrawLayer, region)
			if ok and layer == "BACKGROUND" then
				return region
			end
		end
	end
end

-- An icon button in the Button Border. `selectable`: the rim turns gold
-- (its checked look) while the game shows the button selected (its
-- SelectedTexture, or a CheckButton's checked state); `art`: the game's
-- frame round the icon when it is not the button's own (the selected
-- macro's slot picture on the window); `more`: other art it stands in for.
local function SkinIconButton(button, selectable, art, more)
	if not button or done[button] or button.melloRep ~= nil then
		return
	end
	done[button] = true
	local icon = IconOf(button)
	local back = BackOf(button, icon)
	art = art or back
	if not (icon and art) then
		return
	end
	local extra = {}
	if back and back ~= art then
		extra[#extra + 1] = back
	end
	for _, region in ipairs(more or {}) do
		extra[#extra + 1] = region
	end
	-- the game's hover square and selection glow give way to the rim's own
	-- hover and checked looks
	local glow = button.Highlight or (button.GetHighlightTexture and button:GetHighlightTexture())
	if glow then
		extra[#extra + 1] = glow
	end
	local checkedTex = button.GetCheckedTexture and button:GetCheckedTexture()
	if checkedTex then
		extra[#extra + 1] = checkedTex
	end
	local sel = selectable and button.SelectedTexture or nil
	if sel then
		extra[#extra + 1] = sel
	end
	local checked
	if sel then
		checked = function() return sel:IsShown() end
	elseif selectable and button.GetChecked then
		checked = function()
			local ok, c = pcall(button.GetChecked, button)
			return ok and not Secret(c) and c == true
		end
	end
	local rep = Replace(art, { as = Kit:ButtonRimRule(), button = button, parent = button, checked = checked, alsoFade = extra })
	-- the Kit's own "dressed" marker, read by its sweep: a 36 px CheckButton
	-- (an older macro button) would read as a check box to it
	button.melloRep = rep or false
	if not rep then
		return
	end
	local holder = { melloRep = rep, icon = icon }
	iconRims[#iconRims + 1] = holder
	Kit:RegisterButtonRim(holder)
	FitIconRim(holder)
	stats.icons = stats.icons + 1
	-- the gold follows the game's own selection as soon as it changes
	local function Update()
		local rim = holder.melloRep.object
		if active and rim and rim.Update then
			rim:Update()
		end
	end
	if sel then
		hooksecurefunc(sel, "Show", Update)
		hooksecurefunc(sel, "Hide", Update)
		hooksecurefunc(sel, "SetShown", Update)
	elseif checked and button.SetChecked then
		hooksecurefunc(button, "SetChecked", Update)
	end
end

-- A grid's scroll box: every button as the box initialises it (it pools
-- and re-uses them; each is dressed once, the rim then follows its re-use),
-- and the ones it holds now. A box with no view yet has nothing to walk.
local function WalkBox(box, selectable)
	if not (box and box.ForEachFrame) then
		return
	end
	if box.HasView and not box:HasView() then
		return
	end
	pcall(box.ForEachFrame, box, function(frame)
		SkinIconButton(frame, selectable)
	end)
end

local function HookBox(box, selectable)
	if not box or boxHooked[box] or not ScrollUtil then
		return
	end
	local add = ScrollUtil.AddInitializedFrameCallback or ScrollUtil.AddAcquiredFrameCallback
	if not add then
		return
	end
	boxHooked[box] = true
	add(box, function(_, frame)
		if active then
			SkinIconButton(frame, selectable)
		end
	end, M, false)
end

--------------------------------------------------------------------------------
-- The window's parts
--------------------------------------------------------------------------------

-- The macro grid: a scroll box selector (MacroSelector on the retail-style
-- window, found by what it is on another), else the older named buttons.
local function GridBox(f)
	local selector = f.MacroSelector
	if selector and selector.ScrollBox then
		return selector.ScrollBox
	end
	local popup = Popup()
	for _, child in ipairs({ f:GetChildren() }) do
		if child ~= popup and child.ScrollBox and child.ScrollBar then
			return child.ScrollBox
		end
	end
end

local function NamedGridButtons()
	local list = {}
	for i = 1, 200 do
		local b = _G["MacroButton" .. i]
		if not b then
			break
		end
		list[#list + 1] = b
	end
	return list
end

-- The tabs' cards and the textures they follow ({ rep, region }, the
-- followers the tab skin registered). The Kit's TB6 cards follow their
-- tab's textures on every Show / Hide, also while the kit is off, which
-- would bring a card back over the game's own tab on the next tab switch;
-- and a switch made with SetShown alone would not reach them. After those
-- hooks, this one sets every card from its texture while the kit is on and
-- hides them all while it is off.
local function GuardTabs()
	for _, entry in ipairs(tabReps) do
		if active then
			entry.rep:SetShown(entry.region:IsShown())
		else
			entry.rep.object:Hide()
		end
	end
end

-- A top tab: PanelTopTabButtonTemplate (Left / LeftActive sets) through the
-- Kit; an older TabButtonTemplate (Left for the closed tab, LeftDisabled for
-- the open one, as the game selects a tab by disabling it) gets the same
-- two TB6 cards, each following the set the game shows.
local function SkinTab(tab)
	if not tab or done[tab] then
		return
	end
	done[tab] = true
	local name = tab.GetName and tab:GetName()
	name = type(name) == "string" and not Secret(name) and name or nil
	local function Part(key)
		return tab[key] or (name and _G[name .. key]) or nil
	end
	local plainTex, openTex
	local first = #skin.followers + 1
	if tab.Left and tab.LeftActive then
		plainTex, openTex = tab.Left, tab.LeftActive
		Kit:SkinPanelTab(tab, Replace, skin)
	else
		plainTex, openTex = Part("Left"), Part("LeftDisabled")
		if not (plainTex and openTex) or tab.melloRep ~= nil then
			return
		end
		tab.melloRep = false
		local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
		local plain = Replace(plainTex, { as = "uiframe-tab-left", rect = tab, button = tab, alsoFade = List(Part("Middle"), Part("Right"), hl) })
		local open = Replace(openTex, { as = "uiframe-activetab-left", rect = tab, alsoFade = List(Part("MiddleDisabled"), Part("RightDisabled")) })
		tab.melloRep = plain or open or false
		Follow(plain, plainTex)
		Follow(open, openTex)
	end
	for i = first, #skin.followers do
		tabReps[#tabReps + 1] = skin.followers[i]
	end
	for _, tex in ipairs({ plainTex, openTex }) do
		hooksecurefunc(tex, "Show", GuardTabs)
		hooksecurefunc(tex, "Hide", GuardTabs)
		hooksecurefunc(tex, "SetShown", GuardTabs)
	end
	stats.tabs = stats.tabs + 1
end

local function Tabs(f)
	local list, seen = {}, {}
	local function Add(tab)
		if tab and not seen[tab] then
			seen[tab] = true
			list[#list + 1] = tab
		end
	end
	for i = 1, 4 do
		Add(_G["MacroFrameTab" .. i])
	end
	for _, tab in ipairs(f.Tabs or {}) do
		Add(tab)
	end
	return list
end

-- The selected macro: its button in the Button Border like the grid's, the
-- window's slot picture behind it (MacroFrameSelectedMacroBackground, a
-- texture on the retail-style window) the art the rim stands in for.
local function SelectedButton(f)
	return _G.MacroFrameSelectedMacroButton or f.SelectedMacroButton
end

local function SkinSelected(f)
	local button = SelectedButton(f)
	if not button then
		return
	end
	local bg = _G.MacroFrameSelectedMacroBackground or f.SelectedMacroBackground
	local art, more = nil, {}
	if bg and bg.GetObjectType then
		if bg:GetObjectType() == "Texture" then
			art = bg
		else
			for _, region in ipairs({ bg:GetRegions() }) do
				if region:GetObjectType() == "Texture" and not region.kitPiece then
					more[#more + 1] = region
				end
			end
		end
	end
	SkinIconButton(button, false, art, more)
end

-- The macro's command box (MacroFrameTextBackground: a tooltip-style
-- backdrop -- a NineSlice child, or a backdrop's own pieces on an older
-- window): the list box L1, the single rail with the list-box stone, so
-- the macro text reads on a sunk panel as every list does (user,
-- 2026-09-23: text on the page's cracked stone was "not readable"). A
-- holder under the text's frame: at the box's own level, never at or over
-- the level of the edit box that writes the text.
local function TextBox(f)
	return _G.MacroFrameTextBackground or f.TextBackground
end

local function SkinTextBox(f)
	local box = TextBox(f)
	if not box or done[box] then
		return
	end
	done[box] = true
	local extra = {}
	for _, region in ipairs({ box:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			extra[#extra + 1] = region
		end
	end
	if box.NineSlice then
		for _, region in ipairs({ box.NineSlice:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not region.kitPiece then
				extra[#extra + 1] = region
			end
		end
	end
	local parent = box:GetParent() or f
	local level = 1
	local ok, bl, pl = pcall(function() return box:GetFrameLevel(), parent:GetFrameLevel() end)
	if ok and bl and pl and not Secret(bl) and not Secret(pl) then
		local target = bl
		local text = _G.MacroFrameText
		local okT, tl = pcall(function() return text and text:GetFrameLevel() end)
		if okT and tl and not Secret(tl) then
			target = math.min(target, tl - 1)
		end
		level = math.max(target - pl, 1)
	end
	local rep = Replace(box, { as = "common-insideframe", parent = parent, rect = box, level = level, body = true, noFade = true, alsoFade = extra })
	if rep then
		Follow(rep, box)
	end
end

-- The horizontal bars across the window (UI-ClassTrainer-HorizontalBar, a
-- file texture that reads back as an id here: found by the name the window
-- gives the left one and by what is anchored to it): faded by their rule.
local function SkinBars(f)
	local named = _G.MacroHorizontalBarLeft
	for _, region in ipairs({ f:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece and not done[region] then
			local name = region:GetName()
			local match = (type(name) == "string" and not Secret(name) and name:find("^MacroHorizontalBar") ~= nil)
				or Kit:ArtKey(region) == "UI-ClassTrainer-HorizontalBar"
			if not match and named then
				local okP, _, rel = pcall(region.GetPoint, region, 1)
				match = okP and rel == named
			end
			if match then
				done[region] = true
				if Replace(region, { as = "UI-ClassTrainer-HorizontalBar" }) then
					stats.bars = stats.bars + 1
				end
			end
		end
	end
end

-- The bottom button bar's gold dividers (MagicButtonTemplate's Left /
-- RightSeparator beside Delete / New / Exit): the frame art of the game's
-- button bar, with no kit piece of its own -- faded while the red plates
-- stand there, back on disable.
local BAR_BUTTONS = { "MacroDeleteButton", "MacroNewButton", "MacroExitButton", "MacroSaveButton", "MacroCancelButton", "MacroEditButton" }
local function CollectDividers()
	for _, bname in ipairs(BAR_BUTTONS) do
		local b = _G[bname]
		for _, key in ipairs({ "LeftSeparator", "RightSeparator" }) do
			local sep = b and b[key]
			if sep and not done[sep] then
				done[sep] = true
				fadedArt[#fadedArt + 1] = sep
				if active then
					Kit:Fade(sep)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The icon picker (MacroPopupFrame, IconSelectorPopupFrameTemplate): its box
-- (BorderBox, a nine-slice of the macropopup pieces, and the black BG) on
-- the single rail with its stone, as the game's popup dialogs; the name box
-- on the edit plate; the current icon and the grid in the Button Border.
--------------------------------------------------------------------------------
local function PopupBox(popup)
	return popup.IconSelector and popup.IconSelector.ScrollBox
end

local function PopupEdit(popup)
	local box = popup.BorderBox
	return (box and box.IconSelectorEditBox) or popup.IconSelectorEditBox or _G.MacroPopupEditBox
end

-- The name box: the S1 edit plate with its LEFT cap dropped (that cap is
-- the search glass; this is a name box: the plain end piece closes it, as
-- the chat's). The game's box art reaches past the edit box on both sides
-- (its left piece is anchored left of the box): the plate spans that
-- reach, read from the game's own anchor, so the typed text clears the rail.
local function SkinPopupEdit(popup)
	local edit = PopupEdit(popup)
	if not edit or done[edit] then
		return
	end
	done[edit] = true
	local left = edit.IconSelectorPopupNameLeft
	local mid = edit.IconSelectorPopupNameMiddle
	local right = edit.IconSelectorPopupNameRight
	if not mid then
		-- another template: the widest texture is the middle, the rest its ends
		local textures = {}
		for _, region in ipairs({ edit:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not region.kitPiece then
				textures[#textures + 1] = region
			end
		end
		local best = 0
		for _, tex in ipairs(textures) do
			local ok, w = pcall(tex.GetWidth, tex)
			if ok and w and not Secret(w) and w > best then
				mid, best = tex, w
			end
		end
		local ends = {}
		for _, tex in ipairs(textures) do
			if tex ~= mid then
				ends[#ends + 1] = tex
			end
		end
		left, right = ends[1], ends[2]
	end
	if not mid then
		return
	end
	local reach = 0
	if left then
		local ok, _, _, _, x = pcall(left.GetPoint, left, 1)
		if ok and type(x) == "number" and not Secret(x) and x < 0 then
			reach = -x
		end
	end
	local rect = CreateFrame("Frame", nil, edit)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", edit, "TOPLEFT", -reach, 0)
	rect:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", reach, 0)
	Replace(mid, { as = "UI-ChatInputBorder-Mid2", rect = rect, parent = edit, edit = edit, dropCap = "l", alsoFade = List(left, right) })
end

local function SkinPopup()
	local popup = Popup()
	if not popup or done[popup] then
		return
	end
	done[popup] = true
	-- the popup's box: every texture of its BorderBox (the nine-slice pieces;
	-- its texts are font strings and its icons live on child frames) and its
	-- own black BG. The rail and stone on a holder at the popup's own level:
	-- under the BorderBox (level 50 in the template) with its texts and the
	-- current icon, under the HIGH-strata icon grid, and over the macro
	-- window's outer rail where that reaches under the popup's edge.
	local extra = {}
	for _, region in ipairs({ popup:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			extra[#extra + 1] = region
		end
	end
	local box = popup.BorderBox
	if box then
		for _, region in ipairs({ box:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not region.kitPiece then
				extra[#extra + 1] = region
			end
		end
	end
	Replace(box or popup, { as = "common-insideframe", parent = popup, rect = popup, level = 0, body = true, noFade = true, alsoFade = extra })
	SkinPopupEdit(popup)
	local area = box and box.SelectedIconArea
	SkinIconButton(area and area.SelectedIconButton, false)
	local grid = PopupBox(popup)
	HookBox(grid, true)
	if active then
		WalkBox(grid, true)
	end
	-- the old named buttons, should this client's picker have them
	for i = 1, 200 do
		local b = _G["MacroPopupButton" .. i]
		if not b then
			break
		end
		SkinIconButton(b, true)
	end
	popup:HookScript("OnShow", function(self)
		if active then
			WalkBox(PopupBox(self), true)
			Kit:SweepControls(self, Replace, skin, PopupBox(self))
		end
	end)
end

--------------------------------------------------------------------------------
-- The portrait in the ring (user, 2026-09-24: the ring stood EMPTY; WINDOW-
-- RULES 2b / 2c: an empty ring is a bug). Which texture carries the macro
-- window's icon differs between the clients' versions of the window (the
-- template's PortraitContainer.portrait, or the window's own older
-- MacroFramePortrait, the other one left blank), and the game's portrait is
-- drawn in the window's own stack, under the kit's ring and page. So the
-- icon is drawn by the kit itself: a texture of the RING's holder (our frame,
-- above the portrait container), round-masked on the dark disc at the class
-- medallion's size (Kit:RingDisc fits the disc: 0.759 x the ring), showing
-- the art the game's portrait holds -- the macro scroll (MacroFrame-Icon)
-- when none can be read. The game's portraits are faded meanwhile and put
-- back on disable.
--------------------------------------------------------------------------------
local MACRO_ICON = "Interface\\MacroFrame\\MacroFrame-Icon"

local function PortraitCandidates(f)
	local list, seen = {}, {}
	local pc = f.PortraitContainer
	for _, t in ipairs({ Portrait(f), pc and pc.portrait, f.portrait, _G.MacroFramePortrait }) do
		if t and not seen[t] and t.GetObjectType and t:GetObjectType() == "Texture" then
			seen[t] = true
			list[#list + 1] = t
		end
	end
	return list
end

-- the art the first portrait with any holds (a file path or id; secret-safe)
local function PortraitArt(list)
	for _, t in ipairs(list) do
		local ok, file = pcall(t.GetTexture, t)
		if ok and file ~= nil and not Secret(file) and (type(file) == "number" and file > 0 or type(file) == "string" and file ~= "") then
			return file
		end
	end
	return MACRO_ICON
end

local function SkinPortrait(f, ring)
	local holder = ring and ring.object
	if not (holder and holder.CreateTexture and ring.tex) then
		return
	end
	local candidates = PortraitCandidates(f)
	-- the disc and the icon on the ring's holder: disc BACKGROUND 6, icon
	-- ARTWORK, the ring itself OVERLAY -- one stack, nothing of the game's
	-- between them
	local disc = Kit:RingDisc(ring, nil, holder, 6)
	local icon = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	icon.kitPiece = true
	if disc then
		icon:SetAllPoints(disc)
	else
		icon:SetPoint("CENTER", ring.tex, "CENTER")
		icon:SetSize(1, 1)
	end
	local mask = holder:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	icon:AddMaskTexture(mask)
	icon:SetTexture(PortraitArt(candidates))
	skin.portraitIcon, skin.portraits = icon, candidates
	local onEnable, onDisable = ring.onEnable, ring.onDisable
	ring.onEnable = function(r)
		if onEnable then
			onEnable(r)
		end
		if not disc then
			local okW, w = pcall(ring.tex.GetWidth, ring.tex)
			if okW and w and not Secret(w) and w > 0 then
				icon:SetSize(w * 0.759, w * 0.759)
			end
		end
		icon:SetTexture(PortraitArt(candidates))
		for _, t in ipairs(candidates) do
			Kit:Fade(t)
		end
	end
	ring.onDisable = function(r)
		if onDisable then
			onDisable(r)
		end
		for _, t in ipairs(candidates) do
			Kit:Unfade(t)
		end
	end
end

--------------------------------------------------------------------------------
-- The title (user, 2026-09-24: "the text header is not on the header,
-- probably not even following the Font Style application"; WINDOW-RULES 2c).
-- The title plate's rule centres the title container's TitleText on the
-- plate in the kit's title face; this window may write its title into
-- another string (the window's own TitleText, an older MacroFrameTitleText,
-- an unnamed string reading "Create Macros"), which stayed at the game's
-- place in the game's font under the plate. Every such string is found and
-- put on the plate in the title face (Kit:TitleFont follows the Fonts
-- options and the Font Style), or faded where the container's TitleText
-- already shows the same words there; its points and font put back on
-- disable.
--------------------------------------------------------------------------------
local titleMoved = {}      -- [fs] = { points } while on the plate
local titleFaded = {}      -- [fs] = true while faded as a duplicate

local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	if ok and type(text) == "string" and not Secret(text) and text ~= "" then
		return text
	end
	return nil
end

local function TitleStrings(f)
	local tc = f.TitleContainer
	local own = tc and tc.TitleText
	local words = {}
	if type(_G.CREATE_MACROS) == "string" then
		words[_G.CREATE_MACROS] = true
	end
	if own and TextOf(own) then
		words[TextOf(own)] = true
	end
	local list, seen = {}, { [own or false] = true }
	local function Add(fs, named)
		if fs and not seen[fs] and fs.GetObjectType and fs:GetObjectType() == "FontString" then
			local text = TextOf(fs)
			if text and (named or words[text]) then
				seen[fs] = true
				list[#list + 1] = fs
			end
		end
	end
	Add(f.TitleText, true)
	Add(_G.MacroFrameTitleText, true)
	for _, holder in ipairs({ f, tc, f.NineSlice }) do
		if holder and holder.GetRegions then
			for _, region in ipairs({ holder:GetRegions() }) do
				Add(region, false)
			end
		end
	end
	return list, own
end

local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
	end
end

local function PlaceTitles(on)
	local f = Window()
	if not f then
		return
	end
	if not on then
		for fs, points in pairs(titleMoved) do
			Kit:TitleFont(fs, false)
			fs:ClearAllPoints()
			for _, pt in ipairs(points) do
				fs:SetPoint(unpack(pt))
			end
		end
		wipe(titleMoved)
		for fs in pairs(titleFaded) do
			Kit:Unfade(fs)
		end
		wipe(titleFaded)
		return
	end
	local rep = TitleRep()
	if not rep then
		return
	end
	-- the plate's own centring of the container's string, again (the game may
	-- have laid it out since)
	if rep.object and rep.object:IsShown() and rep.Refit then
		rep:Refit()
	end
	local list, own = TitleStrings(f)
	local ownText = own and TextOf(own)
	for _, fs in ipairs(list) do
		if ownText and TextOf(fs) == ownText then
			-- the same words already on the plate: this copy gives way
			if not titleFaded[fs] then
				titleFaded[fs] = true
				Kit:Fade(fs)
			end
		else
			if not titleMoved[fs] then
				local points = {}
				for i = 1, fs:GetNumPoints() do
					points[i] = { fs:GetPoint(i) }
				end
				titleMoved[fs] = points
			end
			fs:ClearAllPoints()
			-- on the container's string (the rule centred it on the plate's
			-- painted box), else on the plate itself
			if own then
				fs:SetPoint("CENTER", own, "CENTER")
			else
				fs:SetPoint("CENTER", rep.strip or rep.object, "CENTER")
			end
			Kit:TitleFont(fs, true)
		end
	end
end

--------------------------------------------------------------------------------
-- The macro grid on the dark panel (user, 2026-09-24: the icon grid lay on
-- the plain brown; WINDOW-RULES 2e). The window's inset frames the grid: it
-- is dressed WITH its body (Kit:SkinInset), the list-box stone under the
-- palette's inner panel inside its rail (the inset rule's `dim`), its holder
-- kept under the grid's scroll box so the stone never covers the icons.
-- Should this client's window have no inset there (none, hidden, or one that
-- does not hold the grid), the same box is laid round the grid itself.
--------------------------------------------------------------------------------
local function GridFrame(f, grid)
	return f.MacroSelector or (grid and grid:GetParent() ~= f and grid:GetParent()) or grid or _G.MacroButtonContainer
end

-- The level offset (from the window) that keeps a holder under `frame`
local function LevelUnder(f, frame, fallback)
	local ok, fl, gl = pcall(function() return f:GetFrameLevel(), frame:GetFrameLevel() end)
	if ok and fl and gl and not Secret(fl) and not Secret(gl) then
		return math.max(gl - fl - 1, 1)
	end
	return fallback or 1
end

-- whether `outer`'s rect holds `inner`'s centre (nil: not laid out / secret)
local function Holds(outer, inner)
	local ok, ol, ob, ow, oh = pcall(outer.GetRect, outer)
	local okI, il, ib, iw, ih = pcall(inner.GetRect, inner)
	if not (ok and okI and ol and il and ow and iw) then
		return nil
	end
	for _, v in ipairs({ ol, ob, ow, oh, il, ib, iw, ih }) do
		if Secret(v) then
			return nil
		end
	end
	local cx, cy = il + iw / 2, ib + ih / 2
	return cx >= ol and cx <= ol + ow and cy >= ob and cy <= ob + oh
end

local function SkinGridInset(f, grid)
	local inset = f.Inset
	if not inset then
		return
	end
	Kit:SkinInset(inset, Replace, f, true)
	local rep = inset.melloRep
	if not rep then
		return
	end
	Follow(rep, inset)
	local gridFrame = GridFrame(f, grid)
	local box = grid or gridFrame
	if box and rep.object and rep.object.SetFrameLevel then
		local okL, level, gl = pcall(function() return rep.object:GetFrameLevel(), box:GetFrameLevel() end)
		if okL and level and gl and not Secret(level) and not Secret(gl) and level >= gl then
			rep.object:SetFrameLevel(math.max(gl - 1, 0))
		end
	end
end

-- (on show, once laid out) the box round the grid when the inset does not hold it
local function EnsureGridBox(f)
	if skin.gridBox ~= nil then
		return
	end
	local gridFrame = GridFrame(f, skin.grid)
	if not gridFrame then
		return
	end
	local inset = f.Inset
	local held = inset and inset.melloRep and inset:IsShown() and Holds(inset, gridFrame)
	if held == nil and inset and inset.melloRep and inset:IsShown() then
		return   -- not laid out yet: asked again on the next show
	end
	if held then
		skin.gridBox = false
		return
	end
	local rect = CreateFrame("Frame", nil, f)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", -8, 8)
	rect:SetPoint("BOTTOMRIGHT", gridFrame, "BOTTOMRIGHT", 8, -8)
	skin.gridBox = Replace(gridFrame, { as = "common-insideframe", parent = f, rect = rect, level = LevelUnder(f, skin.grid or gridFrame),
		body = true, noFade = true }) or false
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
	local portrait = Portrait(f)
	local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = portrait, bg = "UI-Background-Rock" })
	if ring then
		-- 2b: the icon at the class medallion's size on the dark disc, drawn
		-- by the kit in the ring (SkinPortrait above: the game's own portrait
		-- left the ring empty)
		SkinPortrait(f, ring)
		skin.ring = ring
	end

	-- the tabs first: the sweep would read an older tab as a red button
	for _, tab in ipairs(Tabs(f)) do
		SkinTab(tab)
	end
	SkinSelected(f)
	SkinTextBox(f)
	SkinBars(f)
	CollectDividers()

	-- the macro grid
	local grid = GridBox(f)
	skin.grid = grid
	HookBox(grid, true)
	for _, b in ipairs(NamedGridButtons()) do
		SkinIconButton(b, true)
	end

	-- the inset (ButtonFrameTemplate's) round the grid, on the dark panel
	-- (SkinGridInset above); its box follows it, should the window hide it
	SkinGridInset(f, grid)

	-- every common control left: red buttons, scroll bars, dropdowns, check
	-- boxes (the grid's box is skipped: its buttons are the rims above)
	Kit:SweepControls(f, Replace, skin, grid)

	SkinPopup()
	local popup = Popup()
	if popup then
		Kit:SweepControls(popup, Replace, skin, PopupBox(popup))
	end
end

-- On every show: what the game made or re-laid since (pooled buttons, the
-- portrait's layout), and the followers' state.
local function Refresh()
	local f = Window()
	if not (active and skin and f) then
		return
	end
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	WalkBox(skin.grid, true)
	SkinSelected(f)
	Kit:SweepControls(f, Replace, skin, skin.grid)
	local popup = Popup()
	if popup and popup:IsShown() then
		WalkBox(PopupBox(popup), true)
	end
	-- the portrait's art (the game may set it only as the window first shows)
	if skin.portraitIcon then
		skin.portraitIcon:SetTexture(PortraitArt(skin.portraits))
	end
	-- the title onto the plate, and the grid's box, once the window is laid
	-- out (a frame after it shows)
	PlaceTitles(true)
	C_Timer.After(0, function()
		if active and f:IsShown() then
			PlaceTitles(true)
			EnsureGridBox(f)
		end
	end)
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
	for _, obj in ipairs(fadedArt) do
		Kit:Fade(obj)
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
	for _, obj in ipairs(fadedArt) do
		Kit:Unfade(obj)
	end
	-- the title strings back where the game put them, in its font
	PlaceTitles(false)
	-- (the ring's onDisable put the portrait back)
end

local function Sync()
	if M.isEnabled and Window() then
		Activate()
	else
		Deactivate()
	end
end

-- (geometry of the window's children changes here: out of combat only)
local function SyncSafe()
	if Kit.WhenOutOfCombat then
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
	f:HookScript("OnShow", function()
		if M.isEnabled and not active then
			SyncSafe()
		end
		Refresh()
	end)
end

-- Blizzard_MacroUI is loaded on demand (the first /macro, the game menu's
-- Macros): dressed as it loads.
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, _, addon)
	if addon == "Blizzard_MacroUI" then
		Hook()
		if M.isEnabled then
			SyncSafe()
		end
	end
end)
eventFrame:RegisterEvent("ADDON_LOADED")

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
-- /macrodump [frames | reps | regions | popup [frames | reps | regions]]:
-- with no mode, what the skin found and dressed (parts, their templates)
-- and the window's own regions and children; the modes are Kit:DumpWindow's.
-- Opens the copy window.
--------------------------------------------------------------------------------
local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "")
		elseif kind == "FontString" then
			local okT, text = pcall(region.GetText, region)
			art = "text: " .. ((okT and type(text) == "string" and not Secret(text)) and text:sub(1, 40) or "?")
		end
		local okA, alpha = pcall(region.GetAlpha, region)
		MelloUI:Print("  region %s %s %s %s alpha %s shown %s", kind, NameOf(region), okL and tostring(layer) or "?", art,
			(okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?", tostring(region:IsShown()))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local okLv, lv = pcall(child.GetFrameLevel, child)
		MelloUI:Print("  child %s %s level %s shown %s%s", tostring(child:GetObjectType()), NameOf(child),
			(okLv and not Secret(lv)) and tostring(lv) or "?", tostring(child:IsShown()), child.melloRep ~= nil and " (dressed)" or "")
	end
end

local function Found(label, obj, more)
	MelloUI:Print("  %-26s %s%s", label, obj and NameOf(obj) or "-- not found", more or "")
end

local function Dressed(obj)
	return tostring(obj ~= nil and obj.melloRep ~= nil and obj.melloRep ~= false)
end

local function Summary(f)
	MelloUI:Print("MacroFrame: shown %s, kit %s, reps %d, followers %d", tostring(f:IsShown()), active and "on" or "off",
		skin and #skin.reps or 0, skin and #skin.followers or 0)
	Found("outer rail (NineSlice)", f.NineSlice, f.NineSlice and (" layout " .. tostring(f.NineSlice.layoutType)) or " (an older frame: no shell)")
	for _, t in ipairs(PortraitCandidates(f)) do
		local okT, file = pcall(t.GetTexture, t)
		local okL, layer, sub = pcall(t.GetDrawLayer, t)
		Found("portrait candidate", t, string.format(" art %s, file %s, layer %s %s, shown %s, parent %s", tostring(Kit:ArtKey(t)),
			(okT and not Secret(file)) and tostring(file) or "?", okL and tostring(layer) or "?", okL and tostring(sub) or "", tostring(t:IsShown()), NameOf(t:GetParent())))
	end
	Found("ring / kit icon", skin and skin.ring and skin.ring.object, skin and skin.portraitIcon and (" icon " .. tostring(skin.portraitIcon:GetTexture())) or " (no icon)")
	Found("title container", f.TitleContainer)
	local titles, own = TitleStrings(f)
	Found("container TitleText", own, own and (" text " .. tostring(TextOf(own))) or nil)
	for _, fs in ipairs(titles) do
		Found("other title string", fs, string.format(" text %s, %s", tostring(TextOf(fs)), titleMoved[fs] and "on the plate" or titleFaded[fs] and "faded (duplicate)" or "not placed"))
	end
	Found("grid box (own)", skin and skin.gridBox and skin.gridBox.object or nil, skin and skin.gridBox == false and " (the inset holds the grid)" or nil)
	Found("page stone (Bg)", f.Bg)
	Found("inset", f.Inset, f.Inset and (" dressed " .. Dressed(f.Inset)) or nil)
	for _, tab in ipairs(Tabs(f)) do
		local kind = "unknown template"
		if tab.Left and tab.LeftActive then
			kind = "TB6 (Left / LeftActive)"
		elseif tab.LeftDisabled or _G[NameOf(tab) .. "LeftDisabled"] then
			kind = "older (Left / LeftDisabled)"
		end
		Found("tab", tab, string.format(" %s, dressed %s", kind, Dressed(tab)))
	end
	local grid = GridBox(f)
	Found("macro grid (scroll box)", grid, grid and (" hooked " .. tostring(boxHooked[grid] == true)) or nil)
	MelloUI:Print("  %-26s %d", "named macro buttons", #NamedGridButtons())
	local sel = SelectedButton(f)
	Found("selected macro button", sel, sel and (" dressed " .. Dressed(sel)) or nil)
	Found("selected macro slot art", _G.MacroFrameSelectedMacroBackground)
	local box = TextBox(f)
	Found("command box", box, box and (box.NineSlice and " (NineSlice backdrop)" or " (backdrop pieces)") or nil)
	Found("command edit box", _G.MacroFrameText)
	local scroll = _G.MacroFrameScrollFrame
	local bar = scroll and scroll.ScrollBar
	Found("command scroll frame", scroll, bar and (" bar " .. (bar.Track and "minimal" or "older template") .. ", dressed " .. Dressed(bar)) or nil)
	for _, bname in ipairs(BAR_BUTTONS) do
		local b = _G[bname]
		Found("button", b, b and (" dressed " .. Dressed(b)) or nil)
	end
	MelloUI:Print("  icons in rims %d, tabs %d, bars faded %d, dividers faded %d", stats.icons, stats.tabs, stats.bars, #fadedArt)
	local popup = Popup()
	local area = popup and popup.BorderBox and popup.BorderBox.SelectedIconArea
	Found("icon picker", popup, popup and string.format(" BorderBox %s, edit %s, grid %s, current icon %s", tostring(popup.BorderBox ~= nil),
		tostring(PopupEdit(popup) ~= nil), tostring(PopupBox(popup) ~= nil), tostring(area ~= nil and area.SelectedIconButton ~= nil)) or nil)
	MelloUI:Print("MacroFrame's own regions and children:")
	DumpOwn(f)
end

SLASH_MELLOMACRODUMP1 = "/macrodump"
SlashCmdList.MELLOMACRODUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local target, mode, label = Window(), msg, "MacroFrame"
	local rest = msg:match("^popup%s*(.*)$")
	if rest then
		target, mode, label = Popup(), rest, "MacroPopupFrame"
	end
	MelloUI:ClearLog()
	if not target then
		MelloUI:Print("/macrodump: no %s yet (the macro window loads with its first opening: /macro, then try again)", label)
	elseif mode == "" then
		if rest then
			MelloUI:Print("MacroPopupFrame: shown %s, kit %s", tostring(target:IsShown()), active and "on" or "off")
			DumpOwn(target)
			if target.BorderBox then
				MelloUI:Print("BorderBox:")
				DumpOwn(target.BorderBox)
			end
		else
			Summary(target)
		end
	else
		-- frames / reps / regions (the visible game textures): the Kit's dump
		Kit:DumpWindow(target, skin, mode ~= "regions" and mode or nil)
	end
	MelloUI:ShowLog("macrodump " .. msg)
end
