--------------------------------------------------------------------------------
-- MelloUI - Professions Panel
--
-- The professions window (ProfessionsFrame: the book page with the profession
-- cards, the crafting page with the recipe list and the schematic, the
-- profession tabs down the right side) dressed in the painted kit
-- (Modules/Kit.lua), the way the character window is: every kit piece stands
-- in for one of the game's own art regions, on that region's rectangle, as
-- a child of its frame, faded in place of it. Nothing is moved or re-laid;
-- the game's layout and behaviour stay (docs/WINDOW-RULES.md).
--
-- RULE (user, 2026-09-21): a window is restored to its default state and
-- functionality before anything is changed. The earlier painted-page version
-- of this module (two pictures with the game's frames laid over them, in git
-- history) is gone; this file starts from the default window.
--
-- State: the window frame, tabs, the book page (picks A / F crop 1, the page
-- stone) and the crafting page (picks S1 D1 B1 N1 R1 O1 K2 L1 T1) are on the
-- kit; docs/KIT-MAPPING.md has every row.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("ProfessionsPanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Kit = MelloUI.Kit

local LOOKS = Kit.buttonLooks

-- The crafting page's backgrounds (user, 2026-09-23: "onto the Crafting Tab
-- next"): the page behind everything (the cracked concrete by default) and
-- the recipe list's box (its darker list stone by default), each one of the
-- backgrounds the bars and windows offer (not None: the world would show)
local PAGE_BACKGROUNDS, LIST_BACKGROUNDS = {}, { { value = "list", label = "List stone", piece = "window/single_body" } }
for _, v in ipairs(LOOKS.backgrounds) do
	if v.value ~= "none" then
		PAGE_BACKGROUNDS[#PAGE_BACKGROUNDS + 1] = v
		LIST_BACKGROUNDS[#LIST_BACKGROUNDS + 1] = v
	end
end

local M = MelloUI:RegisterModule("ProfessionsPanel", {
	title = "Professions Panel",
	desc = "The professions window dressed in the painted kit on the game's own layout.",
	enabledByDefault = true,
	defaults = { pageBackground = "concrete", listBackground = "list", bookBackground = "concrete" },
	options = {
		{ type = "dropdown", key = "bookBackground", name = "Book Page Background", values = PAGE_BACKGROUNDS,
		  desc = "What the professions' book page shows behind the profession cards: cracked concrete, stone, iron plate, parchment, leather or dark. The spells' rims wear UI Modifications' Button Border, the rank bars its Progress Bar Border." },
		{ type = "dropdown", key = "pageBackground", name = "Crafting Page Background", values = PAGE_BACKGROUNDS,
		  desc = "What the crafting page shows behind the recipe list and the recipe: cracked concrete, stone, iron plate, parchment, leather or dark." },
		{ type = "dropdown", key = "listBackground", name = "Recipe List Background", values = LIST_BACKGROUNDS,
		  desc = "What the recipe list shows behind its rows: its darker list stone, or one of the other backgrounds. Both are also in Dynamic UI Modification. The reagent slots wear UI Modifications' Button Border, the rank bar its Progress Bar Border, the finished item its Round Border (every window's)." },
	},
})

local skin = nil        -- the registry of replacements, built once the window exists
local active = false
local hooked = false

--------------------------------------------------------------------------------
-- Helpers (the character panel's)
--------------------------------------------------------------------------------

-- A value the client hides from addons (secret): never do arithmetic on it.
-- The test is MelloUI.Safe's (Core.lua), one set for the addon.
local Secret = MelloUI.Safe and MelloUI.Safe.IsSecret or issecretvalue

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Professions panel: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()               -- made after activation (a row, a reagent slot): shown now
	end
	return rep
end

-- The first game texture of a frame (the picture a Blizzard frame paints).
local function FirstArt(frame, key, layer)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece and Kit:ArtKey(region) == key and (not layer or region:GetDrawLayer() == layer) then
			return region
		end
	end
end
local function FirstTexture(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			return region
		end
	end
end

local function SavePoints(region)
	local saved = { w = region:GetWidth(), h = region:GetHeight() }
	for i = 1, region:GetNumPoints() do
		saved[i] = { region:GetPoint(i) }
	end
	return saved
end

local function RestorePoints(region, saved)
	region:ClearAllPoints()
	for i = 1, #saved do
		region:SetPoint(unpack(saved[i]))
	end
	region:SetSize(saved.w, saved.h)
end

-- A ProfessionsRankBar (Blizzard_ProfessionsTemplates/Blizzard_ProfessionsRankBar.xml):
-- Background and Border atlases on the bar, a full-width Fill (a flipbook
-- animation) revealed by the Mask, whose WIDTH is the progress (the bar's
-- width x ratio, interpolated), the Flare glow at the mask's right, the rank
-- text in a child frame. The bracket replaces Background + Border; the fill
-- moves onto the bracket's whole height (the fill-behind rule) and the
-- mask's width is scaled from the bar's width to the opening's; the mask's
-- height stays the atlas's (see Fit). Put back when the skin is off.
local function SkinRankBar(bar)
	if not bar or bar.melloRep ~= nil then
		return
	end
	local bg, border, fill, mask = bar.Background, bar.Border, bar.Fill, bar.Mask
	local key = bg and Kit:ArtKey(bg)
	if not (key and Kit.Replacements[key]) then
		key = "Profession-ProgressBar-BG"
	end
	local rep = bg and Replace(bg, { as = key, rect = bg, alsoFade = border and { border } or nil })
	bar.melloRep = rep or false
	if not (rep and fill) then
		return
	end
	local savedFill, savedMask = SavePoints(fill), mask and SavePoints(mask)
	local function Share()
		-- the opening's share of the bar's width (what the mask's width is scaled by)
		local l, r = rep:GetOpening()
		local w = bg:GetWidth()
		if not (w and w > 0) then
			return 1, 0
		end
		return (w - l - r) / w, l
	end
	local function Fit()
		if not active then
			return
		end
		local l, r, t, b = rep:GetOpening()
		local w, h = bg:GetSize()
		if not (w and h and w > 0 and h > 0) then
			return
		end
		fill:ClearAllPoints()
		fill:SetPoint("LEFT", bg, "LEFT", l, (b - t) / 2)
		fill:SetSize(w - l - r, h - t - b)
		if mask then
			-- the mask keeps its atlas height: resizing a MaskTexture's height
			-- blanks everything it masks in this client (/profdump fill mask);
			-- at 18 px it clips the fill to a band centred in the bracket, and
			-- the rails cover the band's edges anyway
			local okW, mw = pcall(mask.GetWidth, mask)
			if okW and mw and not Secret(mw) and not mask.melloScaled then
				mask.melloFitting = true
				mask:SetWidth(mw * (w - l - r) / w)
				mask.melloFitting = nil
				mask.melloScaled = true
			end
		end
	end
	-- the rank text ("Blacksmithing 31/75") in the interface's text face, as
	-- the labels round it (user, 2026-09-24: the bar text kept the numbers
	-- face, the Font Styles' narrow one): GameFontHighlight, which the Fonts
	-- module retargets, so a Font Style or size reaches it; the game's own
	-- font object back when the skin is off
	local rankTexts = {}
	local function FindTexts(frame, depth)
		for _, region in ipairs({ frame:GetRegions() }) do
			if region.GetObjectType and region:GetObjectType() == "FontString" then
				local okO, object = pcall(region.GetFontObject, region)
				rankTexts[#rankTexts + 1] = { fs = region, object = okO and object or nil }
			end
		end
		if depth < 2 then
			for _, child in ipairs({ frame:GetChildren() }) do
				FindTexts(child, depth + 1)
			end
		end
	end
	FindTexts(bar, 0)
	local function TextFace(on)
		for _, entry in ipairs(rankTexts) do
			if on and _G.GameFontHighlight then
				entry.fs:SetFontObject(_G.GameFontHighlight)
			elseif entry.object then
				entry.fs:SetFontObject(entry.object)
			end
		end
	end
	rep.onEnable = function()
		rep:Refit()
		Fit()
		TextFace(true)
	end
	if active then
		TextFace(true)
	end
	rep.onBarChanged = Fit   -- a new Progress Bar Border (every window's)
	rep.onDisable = function()
		TextFace(false)
		RestorePoints(fill, savedFill)
		if mask then
			-- anchors only: the width is the game's progress, its height untouched
			mask:ClearAllPoints()
			for i = 1, #savedMask do
				mask:SetPoint(unpack(savedMask[i]))
			end
			mask.melloScaled = nil
		end
	end
	rep.experiment = function(what)
		-- /profdump fill <what>: bisecting what hides the fill
		if what == "reset" then
			rep.onDisable()
		elseif what == "anchor" then
			local l, r, t, b = rep:GetOpening()
			local w, h = bg:GetSize()
			fill:ClearAllPoints()
			fill:SetPoint("LEFT", bg, "LEFT", l, (b - t) / 2)
			fill:SetSize(w - l - r, h - t - b)
		elseif what == "nomid" then
			rep.strip.mid:Hide()
		elseif what == "notrough" then
			rep.trough:Hide()
		elseif what == "fit" then
			Fit()
		end
	end
	if mask then
		-- the game sets the mask to ratio x the bar's width (UpdateBar): scale
		-- that onto the opening right after
		hooksecurefunc(mask, "SetWidth", function(self, width)
			if active and not self.melloFitting and not Secret(width) then
				local share = Share()
				self.melloFitting = true
				self:SetWidth(width * share)
				self.melloFitting = nil
				self.melloScaled = true
			end
		end)
	end
end

-- A reagent slot's or a profession spell's rim in every window's Button
-- Border (a thin look hugging the icon, its edge 2 px under the rim's inner
-- edge, as the spell book's), on the icon's centre
local iconRims = {}
local function FitIconRim(button)
	local rep = button.melloRep
	local rim = rep and rep.object
	local icon = button.Icon or button.icon or button.IconTexture
	if not (rim and rim.base and icon) then
		return
	end
	local name = rim.base .. "_normal"
	local p = Kit:Piece(name)
	local l, r, t, b = Kit:Insets(name, 1)
	local ok, iw, ih = pcall(icon.GetSize, icon)
	if not (p and l and ok and iw and ih) or Secret(iw) or Secret(ih) or iw <= 0 then
		return
	end
	rim:ClearAllPoints()
	rim:SetPoint("CENTER", icon, "CENTER")
	rim:SetSize((iw - 4) * p.w / (p.w - l - r), (ih - 4) * p.h / (p.h - t - b))
end

-- A profession card of the book page: its Background — a primary card's is
-- re-atlased per profession in FormatProfession (-Blacksmithing, ...; the
-- bare atlas when no profession is in the slot), so one replacement per
-- atlas the card has shown, the one for its current atlas visible; a
-- secondary's is fixed (the still-life, grey while the card says the
-- profession is missing). Plus the spell buttons' square frames over their
-- icons and the rank bar.
local function CardKey(card)
	local key = Kit:ArtKey(card.Background)
	if not (key and Kit.Replacements[key]) then
		key = card.isPrimary and "Profession-overview-Card" or nil
	end
	return key
end

local function RefreshCard(card)
	if not (card and card.melloReps) then
		return
	end
	local key = CardKey(card)
	if key and not card.melloReps[key] then
		local grey = (not card.isPrimary) and function()
			return card.missingHeader and card.missingHeader:IsShown()
		end or nil
		-- the empty primary card is no picture but the stone box, and it holds
		-- only text (what is missing, where to learn it): that stone under the
		-- palette's inner panel (user, 2026-09-24: "apply the eye strain rule
		-- to all existing windows"; WINDOW-RULES 2e). The profession cards
		-- are pictures and stay as they are.
		local dim = (key == "Profession-overview-Card") and 0.8 or nil
		card.melloReps[key] = Replace(card.Background, { as = key, rect = card, grey = grey, dim = dim }) or false
	end
	for k, rep in pairs(card.melloReps) do
		if rep then
			rep:SetShown(k == key)
			if k == key then
				rep:SetState()
			end
		end
	end
end

local function SkinCard(card)
	if not card or card.melloReps then
		return
	end
	card.melloReps = {}
	RefreshCard(card)
	-- the spells' rims: every window's Button Border, hugging the icon
	-- (user, 2026-09-23: "onto the Professions Tab next")
	for _, button in ipairs(card.spellButtons or {}) do
		if button.IconTextureOverlay and button.melloRep == nil then
			button.melloRep = Replace(button.IconTextureOverlay, { as = "Profession-square-frame", button = button, parent = button }) or false
			if button.melloRep then
				iconRims[#iconRims + 1] = button
				Kit:RegisterButtonRim(button)
				FitIconRim(button)
			end
		end
	end
	SkinRankBar(card.StatusBar)
end

--------------------------------------------------------------------------------
-- The crafting page: recipe list (box, search box, filter dropdown, category
-- headers, recipe rows, scroll bar), the schematic (its backdrop per
-- profession, inset frame, output icon, reagent slots, track checkbox), the
-- rank bar, the create buttons, the quantity spinner, the link button.
--------------------------------------------------------------------------------

-- A recipe row (ProfessionsRecipeListRecipeTemplate): HighlightOverlay is a
-- HIGHLIGHT-layer texture the engine shows on mouse-over, SelectedOverlay
-- one the game shows / hides. Ours follow the same two signals.
local function SkinRecipeRow(row)
	if row.melloRep ~= nil then
		return
	end
	row.melloRep = false
	if row.HighlightOverlay then
		local hover = Replace(row.HighlightOverlay, { as = "Professions_Recipe_Hover", rect = row.HighlightOverlay, level = -1 })
		if hover then
			hover:SetShown(false)
			Perf.HookScript(row, "OnEnter", function() if active then hover:SetShown(true) end end)
			Perf.HookScript(row, "OnLeave", function() if active then hover:SetShown(false) end end)
			row.melloRep = hover
		end
	end
	if row.SelectedOverlay then
		local sel = Replace(row.SelectedOverlay, { as = "Professions_Recipe_Active", rect = row.SelectedOverlay, level = -1 })
		if sel then
			local overlay = row.SelectedOverlay
			local function Follow()
				if active then
					sel:SetShown(overlay:IsShown())
				end
			end
			hooksecurefunc(overlay, "Show", Follow)
			hooksecurefunc(overlay, "Hide", Follow)
			hooksecurefunc(overlay, "SetShown", Follow)
			skin.followers[#skin.followers + 1] = { rep = sel, region = overlay }
			Follow()
		end
	end
end

-- A category header's +/- glyph (CollapseButton.Icon, re-atlased with the
-- collapse state; a HIGHLIGHT copy of it for the hover): the kit's plus /
-- minus plate for the current atlas.
local function RefreshCategoryIcon(header)
	local button = header.CollapseButton
	if button and button.Icon then
		local extra = {}
		for _, region in ipairs({ button:GetRegions() }) do
			if region ~= button.Icon and region:GetObjectType() == "Texture" and not region.kitPiece then
				extra[#extra + 1] = region
			end
		end
		Kit:StateIconReps(button, button.Icon, button, Replace, extra)
	end
end

-- A category header (ListHeaderVisualTemplate): the collapse plate is an
-- unnamed ARTWORK texture, with an additive HIGHLIGHT copy for the hover.
local function SkinCategory(header)
	if header.melloRep ~= nil then
		return
	end
	local plate = FirstArt(header, "common-button-list-collapseExpand", "ARTWORK")
	local hover = FirstArt(header, "common-button-list-collapseExpand", "HIGHLIGHT")
	header.melloRep = (plate and Replace(plate, { as = "common-button-list-collapseExpand", alsoFade = hover and { hover } or nil })) or false
	RefreshCategoryIcon(header)
end

local function SkinListRow(frame)
	if frame.HighlightOverlay or frame.SelectedOverlay then
		SkinRecipeRow(frame)
	elseif frame.CollapseButton then
		SkinCategory(frame)
	end
end

local function HookRecipeList(list)
	local box = list and list.ScrollBox
	if not (box and ScrollUtil and ScrollUtil.AddAcquiredFrameCallback) or box.melloKitHooked then
		return
	end
	box.melloKitHooked = true
	ScrollUtil.AddAcquiredFrameCallback(box, function(_, frame)
		if active then
			SkinListRow(frame)
		end
	end, M, false)
	if ScrollUtil.AddInitializedFrameCallback then
		ScrollUtil.AddInitializedFrameCallback(box, function(_, frame)
			if active and frame.melloRep and frame.melloRep.Refit then
				frame.melloRep:Refit()
			end
			if active and frame.CollapseButton then
				RefreshCategoryIcon(frame)        -- the glyph follows the collapse state
			end
		end, M, false)
	end
	if box.ForEachFrame then
		box:ForEachFrame(function(frame)
			if active then
				SkinListRow(frame)
			end
		end)
	end
end

-- A reagent slot (ProfessionsReagentSlotTemplate's Button): the frame over
-- its icon; the slots are pooled by the schematic form, skinned once each.
local function SkinReagentSlot(button)
	if not button or button.melloRep ~= nil then
		return
	end
	button.melloRep = (button.IconBorder and Replace(button.IconBorder, { as = "Professions-Slot-Frame", button = button, parent = button })) or false
	if button.melloRep then
		iconRims[#iconRims + 1] = button
		Kit:RegisterButtonRim(button)
		FitIconRim(button)
	end
end

Kit:OnBorderChanged("button", function()
	for _, button in ipairs(iconRims) do
		FitIconRim(button)
	end
end)

local function SkinReagents(form)
	if not (form and form.Reagents) then
		return
	end
	for _, slot in ipairs({ form.Reagents:GetChildren() }) do
		SkinReagentSlot(slot.Button)
	end
end

-- The schematic backdrop: the game re-atlases it per profession
-- (Profession-background-card-<Profession>, ProfessionsCraftingPageMixin:Refresh)
-- and hides it for the minimized view; one replacement per atlas seen.
local function RefreshSchematic(form)
	if not (form and form.Background and form.melloReps) then
		return
	end
	local key = Kit:ArtKey(form.Background)
	if key and Kit.Replacements[key] and not form.melloReps[key] then
		-- one level under the form (over the page's backdrop, which is one
		-- under the page: the form may sit at the page's own level); the
		-- picture carries the inset rail itself, the form's inset texture
		-- is faded with the first picture
		form.melloReps[key] = Replace(form.Background, { as = key, rect = form.Background, level = -1, alsoFade = form.melloInset and { form.melloInset } or nil }) or false
	end
	for k, rep in pairs(form.melloReps) do
		if rep then
			rep:SetShown(k == key and form.Background:IsShown())
		end
	end
	-- no picture behind the recipe (the game hides it: the minimized view)
	-- and the form's inset faded with the pictures: the recipe's text would
	-- lie on the plain page stone, so the inset box with its dark panel
	-- stands there instead (skin.schematicBox, SkinCraftingPage)
	if skin and skin.schematicBox then
		skin.schematicBox:SetShown(active and not form.Background:IsShown())
	end
end

local function SkinCraftingPage(page)
	if not page then
		return
	end
	-- the page's backdrop: the page stone
	local pageBg = FirstArt(page, "Profession-Background-Template2")
	if pageBg then
		skin.pageBg = Replace(pageBg, { as = "Profession-Background-Template2" })
	end
	-- the recipe list: its box, search box, filter dropdown, rows, scroll bar
	local list = page.RecipeList
	if list then
		if list.Background then
			skin.listBox = Replace(list.Background, { as = "Professions-background-summarylist" })
		end
		local search = list.SearchBox
		if search and search.Middle then
			local rep = Replace(search.Middle, { as = "common-search-border-middle", rect = search, edit = search,
				alsoFade = { search.Left, search.Right, search.searchIcon } })
			if rep then
				-- the plate's left cap carries its own magnifying glass: the
				-- text and the "Search" instructions start past it (the
				-- game's 16 px inset was for its own icon); put back on disable
				local l, r, t, b = search:GetTextInsets()
				local saved = { l, r, t, b }
				local instr = search.Instructions
				local instrPoints = {}
				if instr then
					for i = 1, instr:GetNumPoints() do
						instrPoints[i] = { instr:GetPoint(i) }
					end
				end
				local function Fit()
					local capW = rep.strip.capL:GetWidth() * 0.45
					search:SetTextInsets(capW, r, t, b)
					if instr then
						instr:ClearAllPoints()
						instr:SetPoint("TOPLEFT", search, "TOPLEFT", capW, 0)
						instr:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", -20, 0)
					end
				end
				rep.onEnable = Fit
				rep.onDisable = function()
					search:SetTextInsets(unpack(saved))
					if instr then
						instr:ClearAllPoints()
						for _, pt in ipairs(instrPoints) do
							instr:SetPoint(unpack(pt))
						end
					end
				end
			end
		end
		local filter = list.FilterDropdown
		if filter and filter.Background then
			-- the frame is a child of the button one level under it (under its text)
			Replace(filter.Background, { as = "common-dropdown-b-button", rect = filter, button = filter, parent = filter })
		end
		HookRecipeList(list)
	end
	-- the schematic: backdrop, inset frame, output icon, reagent slots, checkbox
	local form = page.SchematicForm
	if form then
		form.melloReps = {}
		form.melloInset = FirstArt(form, "common-insideframe")   -- drawn by the picture's own rail
		-- ... and, while the game shows no picture there, the inset box on
		-- the inset's rect with the palette's inner panel over its stone (the
		-- rule's `dim`; user, 2026-09-24: "apply the eye strain rule to all
		-- existing windows"), one level under the form as the pictures are,
		-- so the recipe's text and slots stay above it (RefreshSchematic)
		if form.melloInset then
			skin.schematicBox = Replace(form.melloInset, { as = "common-insideframe", level = -1 })
		end
		RefreshSchematic(form)
		-- the game re-atlases the backdrop per profession and shows / hides it
		-- (the minimized view): follow both directly
		for _, method in ipairs({ "SetAtlas", "Show", "Hide", "SetShown" }) do
			hooksecurefunc(form.Background, method, function()
				if active then
					RefreshSchematic(form)
				end
			end)
		end
		local out = form.OutputIcon
		if out and out.IconBorder then
			local extra = {}
			for _, region in ipairs({ out:GetRegions() }) do
				if region ~= out.IconBorder and region:GetObjectType() == "Texture" and Kit:ArtKey(region) == "auctionhouse-itemicon-border-white" then
					extra[#extra + 1] = region
				end
			end
			local rep = Replace(out.IconBorder, { as = "auctionhouse-itemicon-border-white", button = out, parent = out, alsoFade = extra })
			if rep then
				-- the game colours the border by the item's quality: the rim takes the same colour
				local border = out.IconBorder
				local function Tint()
					local ok, r, g, b = pcall(border.GetVertexColor, border)
					if ok and r and not Secret(r) then
						rep.object:SetVertexColor(r, g, b)
					end
				end
				hooksecurefunc(border, "SetVertexColor", Tint)
				Perf.HookScript(out, "OnEnter", Tint)      -- after the rim's own state change
				Perf.HookScript(out, "OnLeave", Tint)
				Tint()
				-- the game shows the border for the item's quality and hides it otherwise
				local function Follow()
					if active then
						rep:SetShown(border:IsShown())
					end
				end
				hooksecurefunc(border, "Show", Follow)
				hooksecurefunc(border, "Hide", Follow)
				hooksecurefunc(border, "SetShown", Follow)
				skin.followers[#skin.followers + 1] = { rep = rep, region = border }
			end
		end
		SkinReagents(form)
		if form.Init then
			hooksecurefunc(form, "Init", function()
				if active then
					SkinReagents(form)
					RefreshSchematic(form)
				end
			end)
		end
		local cb = form.TrackRecipeCheckbox
		if cb and cb.GetNormalTexture and cb:GetNormalTexture() then
			Replace(cb:GetNormalTexture(), { as = "checkbox-minimal", button = cb, alsoFade = { cb:GetHighlightTexture(), cb:GetCheckedTexture(), cb:GetPushedTexture() } })
		end
	end
	-- the rank bar
	SkinRankBar(page.RankBar)
	-- the create buttons: Left / Right / Center plates + the highlight, re-atlased with the state
	-- Create All sits left of the count spinner, Create right of it: the gem
	-- cap facing the spinner is left out (user, 2026-09-21)
	for _, entry in ipairs({ { page.CreateButton, "l" }, { page.CreateAllButton, "r" } }) do
		local button, drop = entry[1], entry[2]
		if button and button.Center then
			local extra = { button.Left, button.Right }
			for _, region in ipairs({ button:GetRegions() }) do
				if region:GetObjectType() == "Texture" and region ~= button.Center and region ~= button.Left and region ~= button.Right and region:GetDrawLayer() == "HIGHLIGHT" then
					extra[#extra + 1] = region
				end
			end
			button.melloPlate = Replace(button.Center, { as = "_128-RedButton-Center", rect = button, button = button, alsoFade = extra, dropCap = drop })
		end
	end
	-- the quantity spinner: the box (two border sets: the search-border
	-- atlases and the Common-Input-Border files) and its - / + buttons
	local spin = page.CreateMultipleInputBox
	if spin then
		local mid, extra = nil, {}
		for _, region in ipairs({ spin:GetRegions() }) do
			if region:GetObjectType() == "Texture" then
				if not mid and Kit:ArtKey(region) == "common-search-border-middle" then
					mid = region
				else
					extra[#extra + 1] = region
				end
			end
		end
		if mid then
			-- the game's box art runs from its Left texture (5 px left of the
			-- edit box) to its Right: the plate covers that, between the
			-- two arrow buttons
			local rect = spin
			if spin.Left and spin.Right then
				rect = CreateFrame("Frame", nil, spin)
				rect:EnableMouse(false)
				rect:SetPoint("TOPLEFT", spin.Left, "TOPLEFT")
				rect:SetPoint("BOTTOMRIGHT", spin.Right, "BOTTOMRIGHT")
			end
			-- the edit plate's caps carry the search glass: a count box has none
			local rep = Replace(mid, { as = "common-search-border-middle", rect = rect, edit = spin, alsoFade = extra, capless = true })
			if rep then
				-- the count sits in the middle of the plate (the game's is left
				-- of centre for its own border); put back on disable
				local justify = spin:GetJustifyH()
				local l, r, t, b = spin:GetTextInsets()
				rep.onEnable = function()
					spin:SetJustifyH("CENTER")
					-- centred on the plate, which starts left of the edit box
					local ok, over = pcall(function() return spin:GetLeft() - rect:GetLeft() end)
					over = (ok and over and not Secret(over) and over > 0) and over or 0
					spin:SetTextInsets(0, over, t, b)
				end
				rep.onDisable = function()
					spin:SetJustifyH(justify)
					spin:SetTextInsets(l, r, t, b)
				end
				-- the - / + buttons sit against the plate's sides (user,
				-- 2026-09-21); the game keeps them 6 px off its own box art.
				-- Their anchors are put back on disable.
				local saved = {}
				for _, entry in ipairs({ { spin.DecrementButton, "RIGHT", "LEFT" }, { spin.IncrementButton, "LEFT", "RIGHT" } }) do
					local button, point, relPoint = entry[1], entry[2], entry[3]
					if button then
						local points = {}
						for i = 1, button:GetNumPoints() do
							points[i] = { button:GetPoint(i) }
						end
						saved[button] = points
						local enable, disable = rep.onEnable, rep.onDisable
						local function Bind()
							button:ClearAllPoints()
							button:SetPoint(point, rect, relPoint, 0, 0)
						end
						rep.onEnable = function()
							enable()
							Bind()
						end
						Perf.HookScript(spin, "OnShow", function()
							if active then
								Bind()
							end
						end)
						rep.onDisable = function()
							disable()
							button:ClearAllPoints()
							for _, pt in ipairs(saved[button]) do
								button:SetPoint(unpack(pt))
							end
						end
					end
				end
			end
		end
		for key, button in pairs({ ["UI-SpellbookIcon-PrevPage-Up"] = spin.DecrementButton, ["UI-SpellbookIcon-NextPage-Up"] = spin.IncrementButton }) do
			if button and button.GetNormalTexture and button:GetNormalTexture() then
				Replace(button:GetNormalTexture(), { as = key, button = button, rect = button,
					alsoFade = { button:GetPushedTexture(), button:GetDisabledTexture(), button:GetHighlightTexture() } })
			end
		end
	end
	-- the buttons against the count spinner (user, 2026-09-21): the game
	-- anchors them to the page's corner (SetControlAnchors); re-anchored to
	-- the spinner's - / + after it, put back on disable
	if spin and spin.DecrementButton and spin.IncrementButton and page.CreateAllButton and page.CreateButton then
		local saved = {}
		local function Save(b)
			local points = {}
			for i = 1, b:GetNumPoints() do
				points[i] = { b:GetPoint(i) }
			end
			saved[b] = points
		end
		local function Bind()
			skin.bindRuns = (skin.bindRuns or 0) + 1
			if not active then
				return
			end
			local all, one = page.CreateAllButton, page.CreateButton
			if not saved[all] then
				Save(all); Save(one)
			end
			-- flush against the spinner's arrows, on the spinner's centre line:
			-- one continuous bar (the user's mockup)
			all:ClearAllPoints()
			all:SetPoint("RIGHT", spin.DecrementButton, "LEFT", 0, 0)
			one:ClearAllPoints()
			one:SetPoint("LEFT", spin.IncrementButton, "RIGHT", 0, 0)
			-- the text centred on the plate's red middle (the run between the gem
			-- cap and the plain end: its own texture), not on the button (user,
			-- 2026-09-24: "create all text should be moved a bit on the right,
			-- and create text a bit more to the left")
			for _, b in ipairs({ all, one }) do
				local fs = b.GetFontString and b:GetFontString()
				if not fs and not b.melloTextRetry then
					-- its label not made yet: once more a moment later
					b.melloTextRetry = true
					C_Timer.After(0.2, Bind)
				end
				if fs and b.melloTextShift == nil then
					local ok, x, y = pcall(function() local _, _, _, px, py = fs:GetPoint(1); return px, py end)
					b.melloTextShift = { ok and x or 0, ok and y or 0 }
					b.melloTextJustify = fs:GetJustifyH()
				end
				-- the plate: the replacement's strip, or found among the button's
				-- children (the sweep may have dressed the button first: the
				-- replace here then made none -- user, 2026-09-24: "nothing
				-- changed")
				local strip = b.melloPlate and b.melloPlate.strip
				if not strip then
					for _, child in ipairs({ b:GetChildren() }) do
						if rawget(child, "base") and rawget(child, "mid") and child:IsShown() then
							strip = child
							break
						end
					end
				end
				if fs and strip and strip.mid then
					fs:ClearAllPoints()
					fs:SetPoint("CENTER", strip.mid, "CENTER", 0, b.melloTextShift[2] or 0)
					fs:SetJustifyH("CENTER")
				end
			end
		end
		hooksecurefunc(page, "SetControlAnchors", Bind)
		skin.bindCreate = Bind
		-- the game lays the buttons out on its own schedule (SetControlAnchors
		-- is not called on every path: the labels were never placed -- user,
		-- 2026-09-24, /profdump create): again each time the page shows, a
		-- frame after it has laid itself out
		Perf.HookScript(page, "OnShow", function()
			C_Timer.After(0, Bind)
		end)
		if active then
			C_Timer.After(0, Bind)
		end
		skin.unbindCreate = function()
			for b, points in pairs(saved) do
				b:ClearAllPoints()
				for _, pt in ipairs(points) do
					b:SetPoint(unpack(pt))
				end
				local fs = b.GetFontString and b:GetFontString()
				if fs and b.melloTextShift then
					fs:ClearAllPoints()
					fs:SetPoint("CENTER", b, "CENTER", b.melloTextShift[1] or 0, b.melloTextShift[2] or 0)
					if b.melloTextJustify then
						fs:SetJustifyH(b.melloTextJustify)
					end
				end
			end
			wipe(saved)
		end
	end
	-- the link button's plate (the game's chain-link icon stays on it)
	local link = page.LinkButton
	if link and link.Background then
		Replace(link.Background, { as = "common-button-tertiary-square-normal", button = link, rect = link.Background })
	end
	-- the schematic backdrop follows the page's refresh (the profession)
	if page.Refresh then
		hooksecurefunc(page, "Refresh", function()
			if active then
				RefreshSchematic(page.SchematicForm)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- The portrait: the game puts the professions side-tab icon there on the
-- book page (ProfessionsMixin:SelectBookPage) and the profession's spell
-- icon on a crafting page (ProfessionsMixin:Refresh), through
-- SetPortraitToAsset. The user's round icons stand in (sheets 4ea91585 /
-- 4f78b4a9, 2026-09-21): the crossed pick and hammer for the book, each
-- profession's own on its tab. The game's last asset is put back on disable.
--------------------------------------------------------------------------------

local PORTRAITS = {
	alchemy = "icons/profession_alchemy", blacksmithing = "icons/profession_blacksmithing",
	enchanting = "icons/profession_enchanting", engineering = "icons/profession_engineering",
	herbalism = "icons/profession_herbalism", leatherworking = "icons/profession_leatherworking",
	mining = "icons/profession_mining", skinning = "icons/profession_skinning",
	tailoring = "icons/profession_tailoring", cooking = "icons/profession_cooking",
	fishing = "icons/profession_fishing", firstaid = "icons/profession_firstaid",
	jewelcrafting = "icons/profession_jewelcrafting", inscription = "icons/profession_inscription",
	archaeology = "icons/profession_archaeology",
}
local lastAsset = nil
local MEDALLION_TO_RING = 0.66 * 1.15   -- the class medallions' fit in the character window's ring (0.759 x the ring)
local portraitSaved = nil

-- The icon sits in the ring like the class medallion does: 0.759 x the
-- ring's size, on the portrait's own centre; the game's size and anchors
-- are put back on disable.
local function FitPortrait(portrait)
	local ring = skin and skin.ring
	if not (ring and ring.tex) then
		return
	end
	if not portraitSaved then
		local points = {}
		for i = 1, portrait:GetNumPoints() do
			points[i] = { portrait:GetPoint(i) }
		end
		local cx, cy = portrait:GetCenter()
		local px, py = portrait:GetParent():GetLeft(), portrait:GetParent():GetTop()
		if not (cx and px) then
			return   -- not laid out yet (the window never shown): the next refresh fits it
		end
		portraitSaved = { points = points, w = portrait:GetWidth(), h = portrait:GetHeight(),
			cx = cx - px, cy = cy - py }
	end
	local size = ring.tex:GetWidth() * MEDALLION_TO_RING
	if size > 0 and portraitSaved.cx then
		portrait:ClearAllPoints()
		portrait:SetPoint("CENTER", portrait:GetParent(), "TOPLEFT", portraitSaved.cx, portraitSaved.cy)
		portrait:SetSize(size, size)
	end
end

local function UnfitPortrait(portrait)
	if portraitSaved then
		portrait:ClearAllPoints()
		for _, pt in ipairs(portraitSaved.points) do
			portrait:SetPoint(unpack(pt))
		end
		portrait:SetSize(portraitSaved.w, portraitSaved.h)
		portraitSaved = nil
	end
end

local function ApplyPortrait()
	local pf = ProfessionsFrame
	local portrait = pf and pf.PortraitContainer and pf.PortraitContainer.portrait
	if not (portrait and skin and active) then
		return
	end
	local piece
	if pf.BookPage and pf.BookPage:IsShown() then
		piece = "icons/professions"
	else
		local info = pf.professionInfo
		local name = info and (info.professionName or info.parentProfessionName)
		if type(name) == "string" then
			piece = PORTRAITS[name:lower():gsub("%s", "")]
		end
	end
	if piece and Kit:Piece(piece) then
		if lastAsset == nil and not portrait.kitPiece then
			-- the game's own icon, for the restore, when the window was
			-- already open when the module came on (no SetPortraitToAsset seen)
			local okT, current = pcall(portrait.GetTexture, portrait)
			if okT and (type(current) == "string" or type(current) == "number") then
				lastAsset = current
			end
		end
		Kit:Apply(portrait, piece)
		FitPortrait(portrait)
	end
end

local function RestorePortrait()
	local pf = ProfessionsFrame
	local portrait = pf and pf.PortraitContainer and pf.PortraitContainer.portrait
	if portrait and portrait.kitPiece then
		portrait.kitPiece, portrait.kitName = nil, nil
		portrait:SetTexCoord(0, 1, 0, 1)
		if lastAsset then
			portrait:SetTexture(lastAsset)
		end
	end
	if portrait then
		UnfitPortrait(portrait)
	end
end

--------------------------------------------------------------------------------
-- Building the skin
--------------------------------------------------------------------------------

local function BuildSkin()
	if skin then
		return skin
	end
	local pf = ProfessionsFrame
	skin = CreateFrame("Frame", "MelloUIProfessionsSkin", pf)
	skin:SetAllPoints()
	skin:SetFrameLevel(pf:GetFrameLevel())
	skin:EnableMouse(false)
	skin.reps = {}         -- every replacement, for enable / disable
	skin.followers = {}    -- replacements of art the game shows and hides itself: { rep, region }

	-- the window: its nine-slice frame; no gem corner at the top-left, the
	-- portrait ring is that corner
	if pf.NineSlice then
		-- (with its body: the pages' backgrounds are on child frames above
		-- the rail, no tie, and the body fills the band under the title
		-- that no page covers — user, 2026-09-22: "a background disappeared")
		skin.window = Replace(pf.NineSlice, { as = "NineSlicePanelTemplate", parent = pf, rect = pf, skip = "tl" })
	end
	-- the page backdrop (the game's soft picture behind the cards): the
	-- crackle stone (K1). The region is the frame's "$parentBg" texture; in
	-- this client it may carry no parentKey, so it is found by name, then by
	-- its atlas among the frame's own regions.
	local bg = pf.Bg or _G[(pf:GetName() or "") .. "Bg"]
	if not bg then
		for _, region in ipairs({ pf:GetRegions() }) do
			if region:GetObjectType() == "Texture" and Kit:ArtKey(region) == "Profession-Background-Overview" then
				bg = region
				break
			end
		end
	end
	if bg then
		skin.bookBg = Replace(bg, { as = "Profession-Background-Overview" })
	else
		MelloUI:Notice("Professions panel: the page backdrop texture was not found")
	end
	if pf.TopTileStreaks then
		Replace(pf.TopTileStreaks, { as = "_UI-Frame-TopTileStreaks", parent = pf })
	end
	-- the ring around the profession's portrait
	local portrait = pf.PortraitContainer and pf.PortraitContainer.portrait
	local corner = pf.NineSlice and pf.NineSlice.TopLeftCorner
	if portrait and corner then
		skin.ring = Replace(corner, { as = "UI-Frame-PortraitMetal-CornerTopLeft", parent = pf.PortraitContainer, center = portrait })
	end
	-- the title bar (no background art in this client: the plate is the agreed addition)
	local tc = pf.TitleContainer
	if tc then
		local titleBg = FirstTexture(tc)
		if titleBg then
			Replace(titleBg, { as = "TitleBar", parent = tc, rect = tc })
		else
			Replace(tc, { as = "TitleBar", parent = tc, rect = tc, noFade = true })
		end
	end
	local close = pf.CloseButton
	if close and close.GetNormalTexture and close:GetNormalTexture() then
		local extra = {}
		for _, region in ipairs({ close:GetRegions() }) do
			if region:GetObjectType() == "Texture" and region ~= close:GetNormalTexture() then
				extra[#extra + 1] = region
			end
		end
		Replace(close:GetNormalTexture(), { as = "RedButton-Exit", button = close, alsoFade = extra })
	end

	-- the side tabs: the overview tab and the profession tabs; selected =
	-- the game's SelectedTexture shown (SidePanelTabButtonMixin:SetChecked)
	local tabs = { pf.ProfessionsOverviewTab }
	for _, tab in ipairs(pf.rightProfessionTabs or {}) do
		tabs[#tabs + 1] = tab
	end
	skin.tabReps = {}
	for _, tab in ipairs(tabs) do
		if tab.Background then
			local rep = Replace(tab.Background, { as = "common-sidetab", button = tab, parent = tab, icon = tab.Icon,
				checked = function() return tab.SelectedTexture and tab.SelectedTexture:IsShown() end,
				alsoFade = { tab.SelectedTexture, tab.TabGlow, tab.HighlightTexture } })
			if rep then
				skin.tabReps[#skin.tabReps + 1] = rep
			end
		end
	end

	-- the book page: two primary cards, three secondary cards
	local content = pf.BookPage and pf.BookPage.ProfessionsContentFrame
	if content then
		for _, key in ipairs({ "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1", "SecondaryProfession2", "SecondaryProfession3" }) do
			SkinCard(content[key])
		end
		-- a card's picture follows the game's formatting (the profession in
		-- a primary slot, learned / missing on a secondary)
		if pf.BookPage.FormatProfession then
			hooksecurefunc(pf.BookPage, "FormatProfession", function(_, card)
				if active then
					RefreshCard(card)
				end
			end)
		end
	end

	-- the crafting page, and every scroll bar under the window
	SkinCraftingPage(pf.CraftingPage)
	Kit:SkinScrollBarsIn(pf, Replace, skin)
	return skin
end

function M:RefreshCrafting()
	if not (skin and active) then
		return
	end
	local page = ProfessionsFrame.CraftingPage
	if page then
		RefreshSchematic(page.SchematicForm)
		SkinReagents(page.SchematicForm)
		HookRecipeList(page.RecipeList)
	end
	Kit:SkinScrollBarsIn(ProfessionsFrame, Replace, skin)
end

function M:RefreshTabs()
	if not (skin and active) then
		return
	end
	for _, rep in ipairs(skin.tabReps) do
		rep:SetState()
	end
end

function M:RefreshCards()
	if not (skin and active) then
		return
	end
	local content = ProfessionsFrame.BookPage and ProfessionsFrame.BookPage.ProfessionsContentFrame
	if not content then
		return
	end
	for _, key in ipairs({ "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1", "SecondaryProfession2", "SecondaryProfession3" }) do
		RefreshCard(content[key])
	end
end

function M:RefreshFollowers()
	if not (skin and active) then
		return
	end
	for _, f in ipairs(skin.followers) do
		f.rep:SetShown(f.region:IsShown())
	end
end

--------------------------------------------------------------------------------
-- Activation
--------------------------------------------------------------------------------

-- The crafting page's two backgrounds as chosen: the page picture's piece
-- The recipe list on a Parchment list background: its recipes and
-- categories in ink, a recipe's skill-up colour as a dark shade of it
-- (QuestInk's rule, user 2026-09-23)
local function InkSurface()
	local QI = MelloUI.QuestInk
	if not QI then
		return
	end
	if QI.surfaces.professionsList then
		QI.RefreshSurface("professionsList")
		return
	end
	QI.Surface("professionsList", {
		roots = function()
			local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
			return page and page.RecipeList
		end,
		on = function()
			return active and M.isEnabled and M.db and M.db.listBackground == "parchment"
		end,
	})
end

-- swapped (Kit's picture SetPiece), the list box's stone body re-applied
local function ApplyBackgrounds()
	if not skin then
		return
	end
	if skin.pageBg and skin.pageBg.SetPiece then
		skin.pageBg:SetPiece(M.db and M.db.pageBackground or "concrete")
	end
	if skin.bookBg and skin.bookBg.SetPiece then
		skin.bookBg:SetPiece(M.db and M.db.bookBackground or "concrete")
	end
	local body = skin.listBox and skin.listBox.skin and skin.listBox.skin.body
	if body then
		local value = M.db and M.db.listBackground or "list"
		local piece = value == "list" and "window/single_body" or LOOKS.backgroundPiece[value]
		if piece then
			if body.kitName ~= piece then
				body:SetVertexColor(1, 1, 1, 1)
				Kit:Apply(body, piece)
			end
			Kit:Retile(body)
		elseif value == "dark" then
			body:SetColorTexture(0.05, 0.045, 0.04, 0.95)
			body.kitPiece, body.kitName = true, nil
		end
		-- the list box's dark panel (its rule's `dim`, WINDOW-RULES 2e) lies
		-- over any stone, never over the parchment: on paper the rows are in
		-- dark ink (the parchment ink rule), a dark panel there would drown them
		local fill = skin.listBox.skin.dimFill
		if fill then
			fill:SetShown(value ~= "parchment")
		end
	end
	InkSurface()
end

local function Activate()
	if active or not ProfessionsFrame then
		return
	end
	BuildSkin()
	active = true
	skin:Show()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	M:RefreshFollowers()
	M:RefreshTabs()
	M:RefreshCards()
	M:RefreshCrafting()
	ApplyBackgrounds()
	ApplyPortrait()
	if skin.bindCreate then
		skin.bindCreate()
	end
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	skin:Hide()
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	RestorePortrait()
	if skin.unbindCreate then
		skin.unbindCreate()
	end
	InkSurface()
end

-- Dressed on the window's first open (user, 2026-09-24: "dress rarely used
-- windows on first open"): Blizzard_Professions loads on demand, but other
-- UI can pull it in before the window opens (the tracker's recipes, a
-- profession alert), and nothing of the look is built while the window has
-- never been shown. Its OnShow (Hook) builds it before the first frame is
-- drawn, and it then stays built for the session, switched with the module.
-- In combat too: the skin adds frames and textures of ours, fits the
-- portrait, the rank bars' fills and the side tabs, and re-anchors the create
-- buttons and the count spinner's arrows, none of them secure; the book
-- page's spell buttons (secure) only get a rim of ours, never moved.
local function Sync()
	local pf = ProfessionsFrame
	if M.isEnabled and pf and (skin or pf:IsShown()) then
		Activate()
	else
		Deactivate()
	end
end

local function Hook()
	if hooked or not ProfessionsFrame then
		return
	end
	hooked = true
	Perf.HookScript(ProfessionsFrame, "OnShow", function()
		Sync()
		M:RefreshFollowers()
		M:RefreshTabs()
		M:RefreshCards()
		M:RefreshCrafting()
	end)
	if ProfessionsFrame.RightTabSelected then
		hooksecurefunc(ProfessionsFrame, "RightTabSelected", function()
			M:RefreshTabs()
			ApplyPortrait()
		end)
	end
	if ProfessionsFrame.SetPortraitToAsset then
		hooksecurefunc(ProfessionsFrame, "SetPortraitToAsset", function(_, asset)
			lastAsset = asset
			ApplyPortrait()
		end)
	end
end

-- Blizzard_Professions is loaded on demand: wait for it.
local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(_, _, addon)
	if addon == "Blizzard_Professions" and M.isEnabled then
		Hook()
		Sync()
	end
end)

function M:OnSettingChanged(key, _, db)
	self.db = db
	if key == "pageBackground" or key == "listBackground" or key == "bookBackground" then
		ApplyBackgrounds()
	end
end

-- For the Dynamic UI Modification picker (Modules/DynamicUI.lua): the
-- crafting page while it is open
function M:PickerGroups()
	return {
		{ id = "crafting", title = "Crafting", hint = "Click to choose the crafting page's and the recipe list's backgrounds.", sections = {
			{ key = "pageBackground", title = "Page Background", kind = "tile", choices = PAGE_BACKGROUNDS },
			{ key = "listBackground", title = "Recipe List Background", kind = "tile", choices = LIST_BACKGROUNDS },
		} },
		{ id = "profbook", title = "Professions", hint = "Click to choose the book page's background.", sections = {
			{ key = "bookBackground", title = "Book Page Background", kind = "tile", choices = PAGE_BACKGROUNDS },
		} },
	}
end

-- The window's outline for the group whose page is open
function M:BarOutline(id)
	local pf = ProfessionsFrame
	local page = pf and (id == "profbook" and pf.BookPage or pf.CraftingPage)
	if not (active and pf and pf:IsShown() and page and page:IsShown()) then
		return nil
	end
	local ok, l, b, w, h = pcall(pf.GetRect, pf)
	if not (ok and l and w) or Secret(l) or Secret(w) or w <= 0 then
		return nil
	end
	local sc = pf:GetEffectiveScale()
	return { { l * sc, b * sc, (l + w) * sc, (b + h) * sc } }
end

function M:OnEnable(db)
	self.db = db
	if ProfessionsFrame then
		Hook()
		Sync()
	else
		eventFrame:RegisterEvent("ADDON_LOADED")
	end
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	Deactivate()
end

-- /mello cpu: what the window's first open and its tab switches cost
MelloUI:Profile("ProfessionsPanel", "skin build (first open)", BuildSkin)
MelloUI:Profile("ProfessionsPanel", "skin switch-on", Activate)
MelloUI:Profile("ProfessionsPanel", "crafting page refresh", M.RefreshCrafting)
MelloUI:Profile("ProfessionsPanel", "cards refresh", M.RefreshCards)

--------------------------------------------------------------------------------
-- /profdump: the window's art, for the mapping. Default: every visible game
-- texture under the window (frame / region, rect, layer, alpha, art name).
-- "frames": the frame tree with strata and levels. "reps": our replacements.
--------------------------------------------------------------------------------

SLASH_MELLOPROFDUMP1 = "/profdump"
local function ProfDump(msg)
	local pf = ProfessionsFrame
	if not pf then
		MelloUI:Print("Professions window not loaded.")
		return
	end
	if not skin then
		MelloUI:Print("Professions window not dressed yet (it is dressed on its first open): the game's own art only.")
	end
	local function Rect(label, f, extra)
		local ok, l, b, w, h = pcall(function() return f:GetRect() end)
		if ok and l and not Secret(l) then
			MelloUI:Print("%-40s x=%.0f y=%.0f w=%.0f h=%.0f %s", label, l, b, w, h, extra or "")
		else
			MelloUI:Print("%-40s (no rect) %s", label, extra or "")
		end
	end
	-- /profdump create: the Create buttons' labels, their plates and anchors
	if type(msg) == "string" and msg:lower():find("create", 1, true) then
		local page = pf.CraftingPage
		MelloUI:Print("active=%s bindRuns=%s bindCreate=%s", tostring(active), tostring(skin and skin.bindRuns), tostring(skin and skin.bindCreate ~= nil))
		for _, key in ipairs({ "CreateAllButton", "CreateButton" }) do
			local b = page and page[key]
			if b then
				Rect(key, b, "melloPlate=" .. tostring(b.melloPlate ~= nil) .. " shift=" .. tostring(b.melloTextShift ~= nil))
				for _, child in ipairs({ b:GetChildren() }) do
					Rect("  child " .. tostring(rawget(child, "base")), child, "shown=" .. tostring(child:IsShown()) .. " mid=" .. tostring(rawget(child, "mid") ~= nil))
					if rawget(child, "mid") then
						Rect("    mid", child.mid)
					end
				end
				local fs = b.GetFontString and b:GetFontString()
				if fs then
					Rect("  text " .. tostring(fs:GetText()), fs, "justify=" .. tostring(fs:GetJustifyH()))
					for i = 1, fs:GetNumPoints() do
						local pt, rel, relPt, x, y = fs:GetPoint(i)
						MelloUI:Print("    point %s -> %s %s %.1f %.1f", tostring(pt), tostring(rel and rel.GetDebugName and rel:GetDebugName()), tostring(relPt), x or 0, y or 0)
					end
				end
			end
		end
		return
	end
	local function Name(obj)
		return obj:GetName() or obj:GetDebugName()
	end
	if msg == "frames" then
		local function walk(frame, depth)
			if depth > 5 or frame == skin then
				return
			end
			MelloUI:Print("%s%s  %s L%d%s", string.rep("  ", depth), Name(frame), frame:GetFrameStrata(), frame:GetFrameLevel(), frame:IsShown() and "" or " (hidden)")
			for _, child in ipairs({ frame:GetChildren() }) do
				walk(child, depth + 1)
			end
		end
		walk(pf, 0)
		return
	end
	if msg == "bar" then
		-- everything drawn on the first primary card's rank bar, ours included
		local card = pf.BookPage and pf.BookPage.ProfessionsContentFrame and pf.BookPage.ProfessionsContentFrame.PrimaryProfession1
		local bar = card and card.StatusBar
		if not bar then
			MelloUI:Print("No rank bar.")
			return
		end
		Rect("card", card, string.format("%s L%d", card:GetFrameStrata(), card:GetFrameLevel()))
		Rect("bar", bar, string.format("%s L%d shown=%s", bar:GetFrameStrata(), bar:GetFrameLevel(), tostring(bar:IsShown())))
		for _, region in ipairs({ bar:GetRegions() }) do
			local layer, sub = region:GetDrawLayer()
			local okA, alpha = pcall(region.GetAlpha, region)
			local art = region.kitName or (region.GetAtlas and Kit:ArtKey(region)) or "?"
			Rect(string.format("  %s %s%s", region:GetObjectType(), region:GetName() or region:GetDebugName(), region.kitPiece and " [KIT]" or ""), region,
				string.format("%s/%s shown=%s alpha=%s art=%s", tostring(layer), tostring(sub), tostring(region:IsShown()), okA and tostring(alpha) or "?", tostring(art)))
		end
		for _, child in ipairs({ bar:GetChildren() }) do
			Rect("  child " .. Name(child), child, string.format("%s L%d", child:GetFrameStrata(), child:GetFrameLevel()))
		end
		for k, rep in pairs(card.melloReps or {}) do
			if rep then
				Rect("card holder " .. k, rep.object, string.format("%s L%d %s", rep.object:GetFrameStrata(), rep.object:GetFrameLevel(), rep.object:IsShown() and "shown" or "hidden"))
			end
		end
		return
	end
	local what = msg and msg:match("^fill%s+(%S+)")
	if what then
		local card = pf.BookPage and pf.BookPage.ProfessionsContentFrame and pf.BookPage.ProfessionsContentFrame.PrimaryProfession1
		local bar = card and card.StatusBar
		if bar and bar.melloRep and bar.melloRep.experiment then
			bar.melloRep.experiment(what)
			MelloUI:Print("rank bar experiment: %s", what)
		end
		return
	end
	if msg == "card" then
		-- the first primary card: its rect, the game's background, and every
		-- replacement it has (holder, picture texture, rail frame)
		local card = pf.BookPage and pf.BookPage.ProfessionsContentFrame and pf.BookPage.ProfessionsContentFrame.PrimaryProfession1
		if not card then
			MelloUI:Print("No card.")
			return
		end
		Rect("card", card, string.format("%s L%d", card:GetFrameStrata(), card:GetFrameLevel()))
		local okA, alpha = pcall(card.Background.GetAlpha, card.Background)
		Rect("card.Background", card.Background, string.format("alpha=%s art=%s", okA and tostring(alpha) or "?", tostring(Kit:ArtKey(card.Background))))
		for k, rep in pairs(card.melloReps or {}) do
			if rep then
				Rect("rep " .. k, rep.object, string.format("%s L%d %s", rep.object:GetFrameStrata(), rep.object:GetFrameLevel(), rep.object:IsShown() and "shown" or "hidden"))
				if rep.tex then
					local ulx, uly, llx, lly, urx, ury, lrx, lry = rep.tex:GetTexCoord()
					Rect("  picture", rep.tex, string.format("uv UL %.2f,%.2f LL %.2f,%.2f UR %.2f,%.2f LR %.2f,%.2f", ulx or 0, uly or 0, llx or 0, lly or 0, urx or 0, ury or 0, lrx or 0, lry or 0))
				end
				if rep.skin then
					Rect("  rails", rep.skin, string.format("L%d", rep.skin:GetFrameLevel()))
					if rep.skin.t then
						Rect("  rail t", rep.skin.t)
						Rect("  rail r", rep.skin.r)
					end
				end
			end
		end
		return
	end
	if msg == "control" then
		-- the filter dropdown and the Create All button: every region, ours included
		local page = pf.CraftingPage
		local spin = page and page.CreateMultipleInputBox
		if spin then
			Rect("spinner", spin)
			Rect("  Left", spin.Left); Rect("  Right", spin.Right)
			Rect("  DecrementButton", spin.DecrementButton, spin.DecrementButton and select(2, spin.DecrementButton:GetPoint(1)) and Name(select(2, spin.DecrementButton:GetPoint(1))) or "")
			Rect("  IncrementButton", spin.IncrementButton, spin.IncrementButton and select(2, spin.IncrementButton:GetPoint(1)) and Name(select(2, spin.IncrementButton:GetPoint(1))) or "")
		end
		for _, f in ipairs({ page and page.RecipeList and page.RecipeList.FilterDropdown, page and page.CreateAllButton }) do
			if f then
				Rect(Name(f), f, string.format("%s L%d shown=%s", f:GetFrameStrata(), f:GetFrameLevel(), tostring(f:IsShown())))
				for _, region in ipairs({ f:GetRegions() }) do
					local layer, sub = region:GetDrawLayer()
					local okA, alpha = pcall(region.GetAlpha, region)
					local art = region.kitName or (region.GetAtlas and Kit:ArtKey(region)) or "?"
					Rect(string.format("  %s%s", region:GetObjectType(), region.kitPiece and " [KIT]" or ""), region,
						string.format("%s/%s shown=%s alpha=%s art=%s", tostring(layer), tostring(sub), tostring(region:IsShown()), okA and tostring(alpha) or "?", tostring(art)))
				end
				for _, child in ipairs({ f:GetChildren() }) do
					Rect("  child " .. Name(child), child, string.format("L%d shown=%s", child:GetFrameLevel(), tostring(child:IsShown())))
				end
			end
		end
		return
	end
	if msg == "reps" then
		if not skin then
			MelloUI:Print("No skin built.")
			return
		end
		for i, rep in ipairs(skin.reps) do
			Rect(string.format("%d %s (%s)", i, rep.key, rep.kind), rep.rect, rep.object:IsShown() and "shown" or "hidden")
		end
		return
	end
	local n = 0
	local function walk(frame, depth)
		if depth > 8 or frame == skin then
			return
		end
		for _, region in ipairs({ frame:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not region.kitPiece and region:IsVisible() then
				local ok, alpha = pcall(region.GetAlpha, region)
				if ok and alpha and not Secret(alpha) and alpha > 0 then
					n = n + 1
					Rect(string.format("%d %s/%s", n, Name(frame), region:GetName() or region:GetDebugName()), region,
						string.format("%s art=%s", tostring(region:GetDrawLayer()), tostring(Kit:ArtKey(region))))
				end
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			walk(child, depth + 1)
		end
	end
	walk(pf, 0)
	MelloUI:Print("%d visible game textures", n)
end

-- the dump goes to chat and to the copy window (/mellolog), as text
SlashCmdList.MELLOPROFDUMP = function(msg)
	MelloUI:ClearLog()
	ProfDump(msg)
	MelloUI:ShowLog("profdump " .. (msg or ""))
end
