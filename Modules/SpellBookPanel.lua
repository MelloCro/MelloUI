--------------------------------------------------------------------------------
-- MelloUI - Spell Book Panel
--
-- The spell book (PlayerSpellsFrame: the Spellbook, Specialization and
-- Talents tabs) dressed in the painted kit (Modules/Kit.lua) the way the
-- character and professions windows are: every kit piece stands in for one
-- of the game's own art regions, on that region's rectangle, as a child of
-- its frame, faded in place of it (docs/WINDOW-RULES.md).
--
-- State: the frame, tabs and the SPELLBOOK page are on the kit (the user's
-- picks P2 C1 H3 K1 T1, docs/KIT-MAPPING.md); the Talents page stays the
-- game's until the user's per-class art arrives (only its shared parts —
-- search box, dropdown arrow, the top tab system — are skinned).
-- /sbdump lists the window's art.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local LOOKS = Kit.buttonLooks


local M = MelloUI:RegisterModule("SpellBookPanel", {
	title = "Spell Book Panel",
	desc = "The spell book dressed in the painted kit on the game's own layout.",
	enabledByDefault = true,
	defaults = {},
	-- (the spells' rim is UI Modifications' Button Border, the category tabs'
	-- its Side Tab Border: every window's)
	options = {},
})

-- A look's rim piece family, and the share of the rim its opening takes.
-- A look is named either way: as a Button Border style ("thin", "rounded"
-- ...: Spell Border) or as its piece family ("rim", "rimround" ...: Side Tab
-- Border) -- the second fell back to thin iron before (user, 2026-09-23:
-- "it does not work with the SpellBook", Side Tab Border on Rounded)
local function RimBase(value)
	if value == "slot" then
		return "buttons/slot"
	end
	if LOOKS.rimKind[value] then
		return "buttons/" .. LOOKS.rimKind[value]
	end
	if type(value) == "string" and Kit:Piece("buttons/" .. value .. "_normal") then
		return "buttons/" .. value
	end
	return "buttons/rim"
end

local function OpenShare(base)
	local name = base .. "_normal"
	local p = Kit:Piece(name)
	local l, r, t, b = Kit:Insets(name, 1)
	if not (p and l) then
		return 0.8, 0.8
	end
	return (p.w - l - r) / p.w, (p.h - t - b) / p.h
end

local function SideTabLook()
	return Kit:BorderValue("sidetab") or "slot"
end

local skin = nil
local active = false
local hooked = false

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Spell book panel: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- The first game texture of a frame.
local function FirstTexture(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			return region
		end
	end
end

-- Extra regions of a button to fade with its normal texture.
local function OtherTextures(button, keep)
	local extra = {}
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= keep and not region.kitPiece then
			extra[#extra + 1] = region
		end
	end
	return extra
end

-- A search box (SearchBoxTemplate): the edit plate, its glass cap in place
-- of the game's icon; the text and the instructions start past the cap.
local function SkinSearchBox(search)
	if not (search and search.Middle) then
		return
	end
	local rep = Replace(search.Middle, { as = "common-search-border-middle", rect = search, edit = search,
		alsoFade = { search.Left, search.Right, search.searchIcon } })
	if not rep then
		return
	end
	local l, r, t, b = search:GetTextInsets()
	local instr = search.Instructions
	local points = {}
	if instr then
		for i = 1, instr:GetNumPoints() do
			points[i] = { instr:GetPoint(i) }
		end
	end
	rep.onEnable = function()
		local capW = rep.strip.capL:GetWidth() * 0.45
		search:SetTextInsets(capW, r, t, b)
		if instr then
			instr:ClearAllPoints()
			instr:SetPoint("TOPLEFT", search, "TOPLEFT", capW, 0)
			instr:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", -20, 0)
		end
	end
	rep.onDisable = function()
		search:SetTextInsets(l, r, t, b)
		if instr then
			instr:ClearAllPoints()
			for _, pt in ipairs(points) do
				instr:SetPoint(unpack(pt))
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The top tab system (TabSystemTemplate: Left / Middle / Right plain pieces
-- and LeftActive / MiddleActive / RightActive, the game shows one set per
-- SetTabSelected): one plate per set on the tab's rect, following the game.
--------------------------------------------------------------------------------
-- One tab, in the mode the game has it in NOW: a text tab (Left / Middle /
-- Right plates) or a square category tab (SquareBackground under the
-- icon). The game pools its tab buttons and sets the mode when a tab is
-- added (TabSystemButtonMixin:Init -> SetSquareMode), which on a reload
-- can come after the first pass over the system: a square tab skinned
-- as a text tab then had no rim and its own frame at full alpha (user,
-- 2026-09-22, /sbdump tabs: tab 2). Each mode is skinned once per tab,
-- when it is first seen in that mode.
local SkinTab

local squareRims = setmetatable({}, { __mode = "k" })   -- [category tab] = the frame its rim is fitted on
local FitSquareRims   -- below, with the refresh

-- The rims are fitted to the tabs' pitch once the tabs have their final
-- places: a frame after the tab strip shows or lays itself out, and after a
-- tab shows or changes size (the spell book's own refresh ran before the
-- layout, and the rims kept the icon's size -- /sbdump tabs, 2026-09-23)
local function FitSoon(system)
	C_Timer.After(0, function()
		if active and FitSquareRims then
			FitSquareRims(system)
		end
	end)
end

local fitWatched = setmetatable({}, { __mode = "k" })
local function WatchForFit(system, tab)
	if not fitWatched[system] then
		fitWatched[system] = true
		system:HookScript("OnShow", function() FitSoon(system) end)
		if type(system.Layout) == "function" then
			hooksecurefunc(system, "Layout", function() FitSoon(system) end)
		end
	end
	if tab and not fitWatched[tab] then
		fitWatched[tab] = true
		tab:HookScript("OnShow", function() FitSoon(system) end)
		tab:HookScript("OnSizeChanged", function() FitSoon(system) end)
	end
end

local function SkinTabSystem(system)
	if not system then
		return
	end
	if not system.melloKitHooked then
		system.melloKitHooked = true
		-- tabs added or re-initialised later: skinned as they come
		if type(system.AddTab) == "function" then
			hooksecurefunc(system, "AddTab", function(sys)
				for _, tab in ipairs(sys.tabs or {}) do
					SkinTab(tab)
					WatchForFit(sys, tab)
				end
				FitSoon(sys)
			end)
		end
	end
	for _, tab in ipairs(system.tabs or {}) do
		SkinTab(tab)
		WatchForFit(system, tab)
	end
	FitSoon(system)
end

SkinTab = function(tab)
	if not tab then
		return
	end
	if not tab.melloModeHooked and type(tab.SetSquareMode) == "function" then
		tab.melloModeHooked = true
		hooksecurefunc(tab, "SetSquareMode", function(t)
			SkinTab(t)
		end)
	end
	do
		if tab.Left and tab.LeftActive and not tab.squareMode and not tab.melloTextSkinned then
			tab.melloTextSkinned = true
			local plain = Replace(tab.Left, { as = "uiframe-tab-left", rect = tab, alsoFade = { tab.Middle, tab.Right, tab.LeftHighlight, tab.MiddleHighlight, tab.RightHighlight } })
			local open = Replace(tab.LeftActive, { as = "uiframe-activetab-left", rect = tab, alsoFade = { tab.MiddleActive, tab.RightActive } })
			local function Follow()
				if active then
					if plain then plain:SetShown(not tab.isSelected) end
					if open then open:SetShown(tab.isSelected and true or false) end
					-- the label centred on the plate's red middle (between the
					-- two rune caps), the game's own y offset kept
					local fs = tab.Text
					local strip = (tab.isSelected and open or plain)
					strip = strip and strip.strip
					if fs and strip and strip.mid then
						local _, _, _, _, y = fs:GetPoint(1)
						fs:ClearAllPoints()
						fs:SetPoint("CENTER", strip.mid, "CENTER", 0, y or 0)
						fs:SetJustifyH("CENTER")
					end
				end
			end
			hooksecurefunc(tab, "SetTabSelected", Follow)
			tab:HookScript("OnShow", Follow)
			Follow()
			skin.tabFollows = skin.tabFollows or {}
			skin.tabFollows[#skin.tabFollows + 1] = Follow
		elseif tab.squareMode and tab.SquareBackground and not tab.melloSquareSkinned then
			tab.melloSquareSkinned = true
			-- a category tab (C1): the slot rim over the icon, gold while selected
			-- the tab is 43 x 38: the rim is a square on the tab's centre, its
			-- opening the icon's 35 px, so it is not squashed
			local square = CreateFrame("Frame", nil, tab)
			square:EnableMouse(false)
			square:SetSize(48, 48)
			square:SetPoint("CENTER", tab, "CENTER")
			squareRims[tab] = square
			-- the icon is the game's (36 x 35 on every tab, dump-checked) and
			-- is not touched; the rim is a square around it, sized once from
			-- that height by the slot piece's opening (never re-measured)
			local piece = Kit:Piece("buttons/slot_normal")
			local l, _, t, b = Kit:Insets("buttons/slot_normal", 1)
			local ih = 35
			local size = (piece and l) and (ih * piece.h / (piece.h - t - b)) or 48
			square:SetSize(size, size)
			square:ClearAllPoints()
			square:SetPoint("CENTER", tab.Icon or tab, "CENTER")
			-- the icon 15 % larger than the game's 36 x 35, the rim as it is
			-- (user, 2026-09-22); the game re-anchors the icon on select
			-- (SetTabSelected: a CENTER point with its y offset), the size
			-- is ours and stays; the mask follows the icon's rect
			local icon = tab.Icon
			if icon and not icon.melloScaled then
				local okW, iw, ihh = pcall(icon.GetSize, icon)
				if okW and iw and ihh and iw > 0 and ihh > 0 then
					icon.melloScaled = { iw, ihh }
					icon:SetSize(iw * 1.15, ihh * 1.15)
					if tab.IconMask then
						tab.IconMask:ClearAllPoints()
						tab.IconMask:SetAllPoints(icon)
					end
				end
			end
			local rep = Replace(tab.SquareBackground, { as = "spellbook-Tab-Frame-C60", button = tab, parent = tab, rect = square,
				checked = function() return tab.isSelected and true or false end,
				alsoFade = { tab.SquareBackgroundActive, tab.SquareBackgroundActiveGlow } })
			-- the game shows its active pair on selection: keep them faded and
			-- refresh the rim's gold state after each SetTabSelected
			hooksecurefunc(tab, "SetTabSelected", function()
				if active and rep then
					Kit:Fade(tab.SquareBackgroundActive)
					Kit:Fade(tab.SquareBackgroundActiveGlow)
					if rep.object and rep.object.Update then
						rep.object:Update()
					end
				end
			end)
		end
	end
end

-- The category tabs' rims share their corner gems with their neighbours, as
-- the action bars' do: each rim is sized to the tabs' pitch (the distance
-- between two neighbours' centres) over the gems' span, so where two tabs
-- meet their gems land on the same spot as one (player report, 2026-09-23:
-- "class tabs in the spellbook violently overlap with the red diamond
-- graphical elements" -- the rims were sized from the icon, about 62 px on
-- tabs about 46 apart, and the gems of neighbours sat side by side).
local GEM_SPAN_X = 97 / 135     -- the slot piece's gems, centre to centre, as a share of its width
local SLOT_ASPECT = 130 / 135

FitSquareRims = function(system)
	local centres = {}
	for _, tab in ipairs(system and system.tabs or {}) do
		local square = squareRims[tab]
		if square and tab:IsShown() then
			local ok, x = pcall(tab.GetCenter, tab)
			if ok and x and not (issecretvalue and issecretvalue(x)) then
				centres[#centres + 1] = x
			end
		end
	end
	table.sort(centres)
	local pitch
	for i = 2, #centres do
		local d = centres[i] - centres[i - 1]
		if d > 1 and (not pitch or d < pitch) then
			pitch = d
		end
	end
	if not pitch then
		return
	end
	-- the look: Side Tab Border (UI Modifications, every window's tabs;
	-- user, 2026-09-23). The gem slot as before; a thin look a square 4 px
	-- narrower than the pitch (the neighbours never touch) with the icon
	-- filling it, 2 px under its inner edge (as the side tabs')
	local look = SideTabLook()
	local base = RimBase(look)
	local w = pitch / GEM_SPAN_X
	local fw = OpenShare(base)
	for _, tab in ipairs(system.tabs or {}) do
		local square = squareRims[tab]
		if square then
			for _, r in ipairs(skin and skin.reps or {}) do
				if r.region == tab.SquareBackground and r.object and r.object.base then
					Kit:SetSlotBase(r.object, base)
				end
			end
			local icon = tab.Icon
			if look == "slot" then
				square:SetSize(w, w * SLOT_ASPECT)
				if icon and icon.melloScaled then
					icon:SetSize(icon.melloScaled[1] * 1.15, icon.melloScaled[2] * 1.15)
				end
			else
				local side = pitch - 4
				square:SetSize(side, side)
				if icon and icon.melloScaled then
					local size = side * fw + 4
					icon:SetSize(size, size)
				end
			end
		end
	end
end

local function RefreshTabs(system)
	FitSquareRims(system)
	for _, tab in ipairs(system and system.tabs or {}) do
		for _, rep in ipairs(skin.reps) do
			if rep.region == tab.SquareBackground and rep.object and rep.object.Update then
				rep.object:Update()
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The spellbook page: the spell items (pooled, re-atlased per spell) and the
-- category headers, both rebuilt by the paged frame; skinned after its update.
--------------------------------------------------------------------------------
local SPELL_RIM_SCALE = 1.0   -- user, 2026-09-21: the spell rims on the game's 52 x 48 frame rect (1.15, then back down 15 %); the icons stay the game's 36 px (not fitted)
local ACTIVE_FRAMES = { ["spellbook-item-iconframe"] = true, ["spellbook-item-iconframe-inactive"] = true }
local SPELL_ICON = 36             -- the game's icon size (Blizzard_SpellBookItem.xml)
local ROUND_ICON_SCALE = 1.20     -- the round (passive) icons 20 % larger, their rims as they are (user, 2026-09-23: 15 %, then "another 5%")

-- A spell's icon at its size: a round one (a passive, the game's round frame
-- or node circle on it) ROUND_ICON_SCALE x the game's, a square one the
-- game's. The buttons are pooled and change spell, so this follows every
-- refresh; the round mask is anchored to the icon and follows it.
local function SizeSpellIcon(button, restore)
	local icon = button and button.Icon
	if not icon then
		return
	end
	local key = not restore and button.Border and Kit:ArtKey(button.Border)
	local round = key and (key:find("passive", 1, true) or key == "talents-node-circle-gray")
	local size = round and SPELL_ICON * ROUND_ICON_SCALE or SPELL_ICON
	icon:SetSize(size, size)
end

-- A spell's rim on the button's centre (the icon is anchored to the button:
-- anchoring the rim to the icon would be a loop): the gem slot and the
-- passives' round rim on the game's active frame rect (52 x 48), a thin
-- look hugging the game's icon, its edge 2 px under the rim's inner edge
-- (as the side tabs' icons)
local function FitSpellRim(button, key, rep)
	local rim = rep.object
	rim:ClearAllPoints()
	rim:SetPoint("CENTER", button, "CENTER")
	local value = Kit:BorderValue("button") or "thin"   -- every window's Button Border
	if not ACTIVE_FRAMES[key] then
		rim:SetSize(52 * SPELL_RIM_SCALE, 48 * SPELL_RIM_SCALE)
		return
	end
	local base = RimBase(value)
	Kit:SetSlotBase(rim, base)
	if value == "slot" then
		rim:SetSize(52 * SPELL_RIM_SCALE, 48 * SPELL_RIM_SCALE)
		return
	end
	-- from the game's icon size, never the icon's current one: the buttons
	-- are pooled, and one that showed a passive still had the round icon's
	-- larger size when it took an active spell -- its rim came out too big
	-- (user, 2026-09-23: "some of them are too big")
	local fw, fh = OpenShare(base)
	rim:SetSize((SPELL_ICON - 4) / fw, (SPELL_ICON - 4) / fh)
end

local function SkinSpellItem(item)
	if not item.Button then
		return
	end
	if item.melloRep == nil then
		item.melloRep = (item.Backplate and Replace(item.Backplate, { as = "spellbook-item-backplate" })) or false
	end
	local button = item.Button
	if button.Border then
		-- the frame atlas changes with the spell (active / passive / unlearned):
		-- one rim per atlas, each sized so the 36 px icon sits in its opening
		-- (the game's passive frame is only 40 px; its square one 52 x 48)
		Kit:StateIconReps(button, button.Border, button, Replace, { button.BorderShadow, button.IconHighlight })
		-- on every refresh (the buttons are pooled and change spell)
		SizeSpellIcon(button)
		for key, rep in pairs(button.melloIcons or {}) do
			if rep and rep.object then
				FitSpellRim(button, key, rep)
			end
		end
		skin.spellButtons = skin.spellButtons or {}
		if not button.melloListed then
			button.melloListed = true
			skin.spellButtons[#skin.spellButtons + 1] = button
		end
	end
end

local function SkinHeader(header)
	if header.melloRep ~= nil then
		return
	end
	header.melloRep = false
	if header.Backplate then
		Replace(header.Backplate, { as = "spellbook-list-backplate" })
	end
	if header.Border then
		header.melloRep = Replace(header.Border, { as = "spellbook-divider", rect = header.Border }) or false
	end
end

local function SkinPagedSpells(paged)
	if not (paged and paged.GetFrames) then
		return
	end
	for _, frame in ipairs(paged:GetFrames()) do
		if frame.Button and frame.Backplate then
			SkinSpellItem(frame)
		elseif frame.Border or frame.Backplate then
			SkinHeader(frame)
		end
	end
end

local function BuildSkin()
	if skin then
		return skin
	end
	local pf = PlayerSpellsFrame
	skin = CreateFrame("Frame", "MelloUISpellBookSkin", pf)
	skin:SetAllPoints()
	skin:SetFrameLevel(pf:GetFrameLevel())
	skin:EnableMouse(false)
	skin.reps = {}
	skin.followers = {}
	skin.Replace = Replace

	-- the window
	if pf.NineSlice then
		Replace(pf.NineSlice, { as = "NineSlicePanelTemplate", parent = pf, rect = pf, skip = "tl" })
	end
	if pf.TopTileStreaks then
		Replace(pf.TopTileStreaks, { as = "_UI-Frame-TopTileStreaks", parent = pf })
	end
	local portrait = pf.PortraitContainer and pf.PortraitContainer.portrait
	local corner = pf.NineSlice and pf.NineSlice.TopLeftCorner
	if portrait and corner then
		local ring = Replace(corner, { as = "UI-Frame-PortraitMetal-CornerTopLeft", parent = pf.PortraitContainer, center = portrait })
		if ring then
			-- 2b: the book / class icon at the medallion size in the ring,
			-- on the dark disc (a square icon does not fill the round
			-- opening); the game's anchors back on disable (user,
			-- 2026-09-22: "rescale the book icon to fit its border")
			local function Fit()
				pcall(Kit.FitPortrait, Kit, portrait, ring)
			end
			ring.onEnable = Fit
			ring.onDisable = function()
				pcall(Kit.UnfitPortrait, Kit, portrait)
			end
			Kit:RingDisc(ring, nil, pf.PortraitContainer, 0)   -- chains onto the fit above
			if active then
				Fit()
			end
			skin.ring = ring
		end
	end
	local tc = pf.TitleContainer
	if tc then
		local bg = FirstTexture(tc)
		if bg then
			Replace(bg, { as = "TitleBar", parent = tc, rect = tc })
		else
			Replace(tc, { as = "TitleBar", parent = tc, rect = tc, noFade = true })
		end
	end
	local close = pf.CloseButton
	if close and close.GetNormalTexture and close:GetNormalTexture() then
		Replace(close:GetNormalTexture(), { as = "RedButton-Exit", button = close, alsoFade = OtherTextures(close, close:GetNormalTexture()) })
	end
	-- maximize / minimize: two buttons, the game shows one
	local mm = pf.MaximizeMinimizeButton
	for _, entry in ipairs({ { mm and mm.MaximizeButton, "RedButton-Expand" }, { mm and mm.MinimizeButton, "RedButton-Condense" } }) do
		local b, key = entry[1], entry[2]
		if b and b.GetNormalTexture and b:GetNormalTexture() then
			local rep = Replace(b:GetNormalTexture(), { as = key, button = b, alsoFade = OtherTextures(b, b:GetNormalTexture()) })
			if rep then
				skin.followers[#skin.followers + 1] = { rep = rep, region = b }
			end
		end
	end
	-- the top tab system (Spellbook / Specialization / Talents)
	SkinTabSystem(pf.TabSystem)

	-- the spellbook page
	local sb = pf.SpellBookFrame
	if sb then
		for _, key in ipairs({ "BookBGHalved", "BookBGLeft", "BookBGRight" }) do
			local tex = sb[key]
			if tex then
				local rep = Replace(tex, { as = Kit:ArtKey(tex) or "spellbook-Page-Right-C60", rect = tex })
				if rep then
					skin.followers[#skin.followers + 1] = { rep = rep, region = tex }
				end
			end
		end
		SkinTabSystem(sb.CategoryTabSystem)
		SkinSearchBox(sb.SearchBox)
		local dd = sb.SettingsDropdown
		if dd and dd.Icon then
			Replace(dd.Icon, { as = "common-dropdown-a-button", button = dd, rect = dd.Icon, alsoFade = OtherTextures(dd, dd.Icon) })
		end
		local paging = sb.PagedSpellsFrame and sb.PagedSpellsFrame.PagingControls
		if paging then
			for key, b in pairs({ ["UI-SpellbookIcon-PrevPage-Up"] = paging.PrevPageButton, ["UI-SpellbookIcon-NextPage-Up"] = paging.NextPageButton }) do
				if b and b.GetNormalTexture and b:GetNormalTexture() then
					Replace(b:GetNormalTexture(), { as = key, button = b, rect = b, alsoFade = OtherTextures(b, b:GetNormalTexture()) })
				end
			end
		end
		if sb.PagedSpellsFrame and sb.PagedSpellsFrame.RegisterCallback and PagedContentFrameBaseMixin then
			sb.PagedSpellsFrame:RegisterCallback(PagedContentFrameBaseMixin.Event.OnUpdate, function()
				if active then
					SkinPagedSpells(sb.PagedSpellsFrame)
				end
			end, M)
		end
		SkinPagedSpells(sb.PagedSpellsFrame)
	end

	-- the talents page: only its shared controls (the page stays the game's)
	local tf = pf.TalentsFrame
	if tf then
		SkinTabSystem(tf.TabSystem)
		SkinSearchBox(tf.SearchBox)
		local dd = tf.SearchOptionsDropdown
		if dd and dd.Arrow then
			Replace(dd.Arrow, { as = "common-dropdown-a-button", button = dd, rect = dd.Arrow })
		end
	end
	return skin
end

function M:RefreshSpellBook()
	if not (skin and active) then
		return
	end
	local pf = PlayerSpellsFrame
	local sb = pf.SpellBookFrame
	if sb then
		SkinPagedSpells(sb.PagedSpellsFrame)
		RefreshTabs(sb.CategoryTabSystem)
	end
	for _, follow in ipairs(skin.tabFollows or {}) do
		follow()
	end
	Kit:SkinScrollBarsIn(pf, Replace, skin)
end

function M:RefreshFollowers()
	if not (skin and active) then
		return
	end
	for _, f in ipairs(skin.followers) do
		f.rep:SetShown(f.region:IsShown())
	end
end

local function Activate()
	if active or not PlayerSpellsFrame then
		return
	end
	BuildSkin()
	active = true
	skin:Show()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	M:RefreshFollowers()
	M:RefreshSpellBook()
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
	-- the spells' icons back to the game's size
	for _, button in ipairs(skin.spellButtons or {}) do
		SizeSpellIcon(button, true)
	end
	-- the category tab icons back to the game's size
	local sys = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame and PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem
	for _, tab in ipairs(sys and sys.tabs or {}) do
		local icon = tab.Icon
		if icon and icon.melloScaled then
			icon:SetSize(icon.melloScaled[1], icon.melloScaled[2])
			icon.melloScaled = nil
		end
	end
end

local function Sync()
	if M.isEnabled and PlayerSpellsFrame then
		Activate()
	else
		Deactivate()
	end
end

local function Hook()
	if hooked or not PlayerSpellsFrame then
		return
	end
	hooked = true
	PlayerSpellsFrame:HookScript("OnShow", function()
		Sync()
		M:RefreshFollowers()
		M:RefreshSpellBook()
	end)
	if PlayerSpellsFrame.SpellBookFrame then
		PlayerSpellsFrame.SpellBookFrame:HookScript("OnShow", function()
			M:RefreshFollowers()
			M:RefreshSpellBook()
		end)
	end
	if PlayerSpellsFrame.SetMinimized then
		hooksecurefunc(PlayerSpellsFrame, "SetMinimized", function() M:RefreshFollowers() end)
	end
end

-- The category tabs, laid again for a new Side Tab Border (UI Modifications'
-- setting, every window's tabs)
local function CategorySystem()
	local sb = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
	return sb and sb.CategoryTabSystem
end

-- a new border for every window: the spells' rims and the category tabs
-- laid again
Kit:OnBorderChanged("sidetab", function()
	if active and CategorySystem() then
		FitSquareRims(CategorySystem())
	end
end)
Kit:OnBorderChanged("button", function()
	for _, button in ipairs(skin and skin.spellButtons or {}) do
		for k, rep in pairs(button.melloIcons or {}) do
			if rep and rep.object then
				FitSpellRim(button, k, rep)
			end
		end
	end
end)

-- Blizzard_PlayerSpells is loaded on demand: wait for it.
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, _, addon)
	if addon == "Blizzard_PlayerSpells" and M.isEnabled then
		Hook()
		Sync()
	end
end)

function M:OnEnable(db)
	self.db = db
	if PlayerSpellsFrame then
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

--------------------------------------------------------------------------------
-- /sbdump: the window's art, for the mapping (regions by default; "frames":
-- the tree with strata and levels; "reps": ours). Opens the copy window.
--------------------------------------------------------------------------------

local function SbDump(msg)
	local pf = PlayerSpellsFrame
	if not pf then
		MelloUI:Print("Spell book window not loaded.")
		return
	end
	local function Rect(label, f, extra)
		local ok, l, b, w, h = pcall(function() return f:GetRect() end)
		if ok and l and not Secret(l) then
			MelloUI:Print("%-40s x=%.0f y=%.0f w=%.0f h=%.0f %s", label, l, b, w, h, extra or "")
		else
			MelloUI:Print("%-40s (no rect) %s", label, extra or "")
		end
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
	if msg == "tabs" then
		local sys = pf.SpellBookFrame and pf.SpellBookFrame.CategoryTabSystem
		for i, tab in ipairs(sys and sys.tabs or {}) do
			Rect(string.format("tab %d", i), tab, string.format("selected=%s L%d", tostring(tab.isSelected), tab:GetFrameLevel()))
			for _, region in ipairs({ tab:GetRegions() }) do
				local layer, sub = region:GetDrawLayer()
				local okA, alpha = pcall(region.GetAlpha, region)
				local art = region.kitName or (region.GetAtlas and Kit:ArtKey(region)) or "?"
				Rect(string.format("  %s%s", region:GetObjectType(), region.kitPiece and " [KIT]" or ""), region,
					string.format("%s/%s shown=%s alpha=%s art=%s", tostring(layer), tostring(sub), tostring(region:IsShown()), okA and tostring(alpha) or "?", tostring(art)))
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


SLASH_MELLOSBDUMP1 = "/sbdump"
-- /sbdump tabs: the category tabs, their centres and sizes, the rim frames
-- and the pitch the rims are fitted to (the gems that did not meet, 2026-09-23)
local function DumpCategoryTabs()
	local sb = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
	local system = sb and sb.CategoryTabSystem
	if not system then
		MelloUI:Print("No category tab system.")
		return
	end
	MelloUI:Print("category tabs: %d, skin active %s", #(system.tabs or {}), tostring(active))
	for i, tab in ipairs(system.tabs or {}) do
		local ok, x, y = pcall(tab.GetCenter, tab)
		local square = squareRims[tab]
		MelloUI:Print("  %d: shown %s, square mode %s, centre %s, size %.1f x %.1f, rim frame %s", i,
			tostring(tab:IsShown()), tostring(tab.squareMode), ok and x and string.format("%.1f, %.1f", x, y) or "?",
			tab:GetWidth(), tab:GetHeight(),
			square and string.format("%.1f x %.1f", square:GetWidth(), square:GetHeight()) or "none")
	end
	FitSquareRims(system)
	MelloUI:Print("after fitting now:")
	for i, tab in ipairs(system.tabs or {}) do
		local square = squareRims[tab]
		if square then
			MelloUI:Print("  %d: rim frame %.1f x %.1f", i, square:GetWidth(), square:GetHeight())
		end
	end
end

SlashCmdList.MELLOSBDUMP = function(msg)
	MelloUI:ClearLog()
	if (msg or ""):lower():find("tab") then
		DumpCategoryTabs()
		MelloUI:ShowLog("sbdump tabs")
		return
	end
	SbDump(msg)
	MelloUI:ShowLog("sbdump " .. (msg or ""))
end
