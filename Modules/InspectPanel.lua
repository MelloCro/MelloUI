--------------------------------------------------------------------------------
-- MelloUI - Inspect Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): the inspect window (InspectFrame: another player's gear, from the
-- load-on-demand inspect addon, Blizzard_InspectUI) dressed in the painted
-- kit (Modules/Kit.lua) the way the character window is (Modules/
-- CharacterPanel.lua), on the game's own layout, by the rule book
-- (docs/WINDOW-RULES.md). The inspect addon's source is not on disk: every
-- part is found at run time by its global name, its key or what it is, with
-- fallbacks, and /inspectdump says what this client really has.
--
--   the window shell     outer double rail with gem corners, ONE page stone
--                        for every tab (the window's Bg -> the page picture
--                        inside the outer rail, 2a), the ring with the
--                        inspected player's portrait at the class medallion's
--                        size on the dark disc (2b), the title plate on the
--                        rail with the player's name ON it in the title face
--                        (2c), the close button (Kit:SkinWindowShell)
--   the paper doll       as the character window's: the slots' frame art
--                        faded, every slot in the Button Border rim with its
--                        icon in the opening and the quality border kept on
--                        the icon (Kit:SkinActionButton); the model's race
--                        landscape faded so the page stone runs on behind the
--                        model (one stone), its vignette the game's; the
--                        single-rail viewport frame round the model (the
--                        character window's agreed addition) -- or, where the
--                        window has an inset round the model, that inset's
--                        rail in its place (replace, never add)
--   the model controls   the cog plate (K2) under the game's glyphs
--   the character art    any of the character window's own atlases found
--                        here (the level plate, the pane pictures, a divider)
--                        get the same piece they get there
--   the other tabs       (PvP / Honor, Talents, Guild: whatever this client
--                        has) their text on the palette's inner panel over the
--                        page stone while the paper doll is not shown (2e),
--                        as the character window's panes off the paper doll;
--                        their buttons, check boxes, dropdowns and scroll
--                        bars by the sweep
--   the tabs             TB6 cards (Kit:SkinPanelTab; an older tab template
--                        gets the same two cards), hidden while the kit is off
--
-- No parchment: the character window's parchment is its right pane's (the
-- stats, which the inspect window has not) and its own Window Background
-- setting, neither shared, so the inspect window is on stone and nothing is
-- inked.
--
-- Taint: nothing of the game's is replaced or re-scripted; the skin is made
-- and kept from post-hooks (HookScript, hooksecurefunc on the game's own
-- regions and on PanelTemplates_SetTab); state lives in weak side tables; no
-- inspect or item function is ever called. The portrait (brought to the
-- medallion size) and the title (moved onto the plate) are put back on
-- disable; switching the module off gives back the stock window.
--
-- /inspectdump [frames | reps | regions]: what the window is made of on this
-- client and what the skin found and dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("InspectPanel")
local hooksecurefunc = Perf.hooksecurefunc
-- a handler made once and run for many asks, wrapped once: its time stays
-- on this file's own /melloperf row (review, 2026-09-24)
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("InspectPanel", {
	title = "Inspect Kit",
	desc = "The inspect window (another player's gear) in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local INSPECT_ADDON = "Blizzard_InspectUI"
local DIM_ALPHA = 0.8                 -- WINDOW-RULES 2e: the inner panel over the stone
local MEDALLION_TO_RING = 0.759       -- WINDOW-RULES 2b (Kit:FitPortrait), for the dump

-- the equipment slots, as the character window names them ("Inspect<key>Slot")
local SLOT_KEYS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
	"Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1",
	"MainHand", "SecondaryHand", "Ranged", "Ammo" }

-- the tabs' pages, by the names the inspect addons of the game's clients give them
local PAGE_NAMES = { "InspectPaperDollFrame", "InspectPVPFrame", "InspectHonorFrame", "InspectArenaFrame",
	"InspectTalentFrame", "InspectGuildFrame" }

-- The character window's own atlases: found anywhere in this window (outside
-- the slots and the model), each gets the piece it gets there, by its rule
-- (docs/KIT-MAPPING.md). Nothing else is dressed by atlas here.
local CHARACTER_ART = {
	["UI-Character-Info-General-BG"] = true,        -- a pane's picture: faded (one stone)
	["UI-Character-Info-Stat-BG"] = true,           -- a pane's picture: faded (one stone)
	["UI-Character-Info-GearSlot"] = true,          -- a slot's frame art: faded (the rim stands in)
	["UI-Character-Info-ItemLevel-Bounce"] = true,  -- the level plate: lists/header
	["UI-Character-Info-Title"] = true,             -- a category plate: lists/header
	["UI-Character-Info-Honor-LevelBG"] = true,     -- the PvP rank line: the divider
	["UI-Character-Info-ScrollLine"] = true,        -- a detail line: the divider
	["UI-Character-Info-ScrollLine-Long"] = true,
	["common-framedivider"] = true,                 -- a pane divider: the single rail's edge
}

local skin = nil          -- { reps, followers, built, ring, portrait, page (the page picture), dim, model }
local active = false
local hooked = false

-- what this module made or looked at, kept OFF the game's frames (weak keys)
local done = setmetatable({}, { __mode = "k" })         -- [frame / region] = true: looked at once
local titleMoved = setmetatable({}, { __mode = "k" })   -- [fs] = its points while on the plate
local titleFaded = setmetatable({}, { __mode = "k" })   -- [fs] = true while faded as a duplicate
local pageHooked = setmetatable({}, { __mode = "k" })   -- [page] = true: its show / hide heard
local fadedArt = {}                                     -- game art faded with no piece on its own rect
local tabReps = {}                                      -- the tabs' cards { rep, region }
local slotList = {}                                     -- the slots dressed, in order
local controls = {}                                     -- the model's control buttons { button, rep }
local known = {}                                        -- the character art dressed { key, region, rep }
local found = {}                                        -- [part] = a line for /inspectdump

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe and MelloUI.Safe.IsSecret or issecretvalue

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Inspect kit: no kit piece mapped for %s", tostring(key))
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

-- a font string's text when it can be read (nil when empty or secret)
local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	if ok and type(text) == "string" and not Secret(text) and text ~= "" then
		return text
	end
	return nil
end

-- whether a font string shows anything: a secret text (a player's name may
-- come secret on this client) is shown by the game all the same
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

-- a part of the window: the key the template gives it, else its global name
local function Part(owner, key, suffix)
	if not owner then
		return nil
	end
	local v = key and owner[key]
	if v then
		return v
	end
	local n = NameOf(owner)
	return n and suffix and _G[n .. suffix] or nil
end

local function IsTexture(obj)
	return obj and obj.GetObjectType and obj:GetObjectType() == "Texture" or false
end

-- Art faded while the kit is on with no piece on its own rect (the rim that
-- stands in for a slot's frame lies on the button)
local function FadeArt(obj)
	if not obj or done[obj] then
		return
	end
	done[obj] = true
	fadedArt[#fadedArt + 1] = obj
	if active then
		Kit:Fade(obj)
	end
end

local function Window()
	return _G.InspectFrame
end

local function PaperDoll(f)
	return _G.InspectPaperDollFrame or (f and (f.PaperDollFrame or f.PaperDoll)) or nil
end

local function Model(f)
	local doll = PaperDoll(f)
	return _G.InspectModelFrame or _G.InspectModelScene
		or (doll and (doll.ModelScene or doll.InspectModelScene or doll.ModelFrame or doll.Model))
		or (f and (f.ModelScene or f.ModelFrame)) or nil
end

--------------------------------------------------------------------------------
-- The portrait in the ring (WINDOW-RULES 2b / 2c: an empty ring is a bug).
-- The game draws the inspected player into the portrait container's portrait
-- (SetPortraitTexture on the inspect unit; on an older window its own
-- InspectFramePortrait): the kit's ring on the corner, the portrait brought
-- to the class medallion's size in it (Kit:FitPortrait, its aspect kept) with
-- the dark disc under it (Kit:RingDisc), so the ring is never empty even
-- before the game has a portrait to give. Put back on disable.
--------------------------------------------------------------------------------
local function PortraitCandidates(f)
	local list, seen = {}, {}
	local pc = f.PortraitContainer
	for _, t in ipairs({ pc and pc.portrait or false, _G.InspectFramePortrait or false, f.portrait or false }) do
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
-- The title (WINDOW-RULES 2c: the title ON the plate, in the title face).
-- The shell's title plate centres the title container's TitleText on it in
-- Kit:TitleFont (the Fonts options, the Font Style) and puts it back on
-- disable; the game writes the inspected player's name there (SetTitle). An
-- older window writes it into its own string (InspectNameText): that string
-- is moved onto the plate in the title face, or faded where the container
-- shows the same words; its points and font put back on disable.
--------------------------------------------------------------------------------
local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
	end
end

local function TitleStrings(f)
	local tc = f.TitleContainer
	local own = tc and tc.TitleText
	local list, seen = {}, {}
	if own then
		seen[own] = true
	end
	for _, fs in ipairs({ _G.InspectNameText or false, _G.InspectFrameTitleText or false, f.TitleText or false, f.NameText or false }) do
		if fs and not seen[fs] and fs.GetObjectType and fs:GetObjectType() == "FontString" then
			seen[fs] = true
			if HasText(fs) then
				list[#list + 1] = fs
			end
		end
	end
	return list, own
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
	if not (rep and rep.object and rep.object:IsShown()) then
		return
	end
	if rep.Refit then
		rep:Refit()
	end
	local list, own = TitleStrings(f)
	if own and not own.melloFontSaved then
		Kit:TitleFont(own, true)
	end
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
-- The tabs (Character / PvP or Honor / Talents or Guild, whatever this client
-- has): TB6 cards by Kit:SkinPanelTab; an older CharacterFrameTabButton-
-- Template (Left for the closed tab, LeftDisabled for the open one: the game
-- selects a tab by disabling it) gets the same two cards. The Kit's cards
-- follow their tab's textures on every Show / Hide, also while the kit is
-- off, which would bring a card back over the game's own tab on the next tab
-- switch; after those hooks this one sets every card from its texture while
-- the kit is on and hides them all while it is off (the merchant's guard).
--------------------------------------------------------------------------------
local function GuardTabs()
	for _, entry in ipairs(tabReps) do
		if active then
			entry.rep:SetShown(entry.region:IsShown())
		else
			entry.rep.object:Hide()
		end
	end
end

-- A piece the game shows and hides itself: shown with its region while on.
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

local function SkinTab(tab)
	if not tab or done[tab] then
		return
	end
	done[tab] = true
	local plainTex, openTex
	local first = #skin.followers + 1
	local kind
	if tab.Left and tab.LeftActive then
		plainTex, openTex = tab.Left, tab.LeftActive
		Kit:SkinPanelTab(tab, Replace, skin)
		kind = "TB6 (Left / LeftActive)"
	else
		plainTex, openTex = Part(tab, "Left", "Left"), Part(tab, "LeftDisabled", "LeftDisabled")
		if not (plainTex and openTex) or tab.melloRep ~= nil then
			found.tabs = found.tabs or {}
			found.tabs[tab] = "-- unknown template: left as the game's"
			-- (the Kit's marker: the sweep leaves it, never a red plate on a tab)
			if tab.melloRep == nil then
				tab.melloRep = false
			end
			return
		end
		local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
		local plain = Replace(plainTex, { as = "uiframe-tab-left", rect = tab, button = tab,
			alsoFade = List(Part(tab, "Middle", "Middle"), Part(tab, "Right", "Right"), hl) })
		local open = Replace(openTex, { as = "uiframe-activetab-left", rect = tab,
			alsoFade = List(Part(tab, "MiddleDisabled", "MiddleDisabled"), Part(tab, "RightDisabled", "RightDisabled")) })
		-- the Kit's own "dressed" marker, as its tab helper sets it
		tab.melloRep = plain or open or false
		Follow(plain, plainTex)
		Follow(open, openTex)
		kind = "TB6 cards on an older tab (Left / LeftDisabled)"
	end
	for i = first, #skin.followers do
		tabReps[#tabReps + 1] = skin.followers[i]
	end
	for _, tex in ipairs(List(plainTex, openTex)) do
		hooksecurefunc(tex, "Show", GuardTabs)
		hooksecurefunc(tex, "Hide", GuardTabs)
		hooksecurefunc(tex, "SetShown", GuardTabs)
	end
	found.tabs = found.tabs or {}
	found.tabs[tab] = kind
end

local function Tabs(f)
	local list, seen = {}, {}
	local function Add(tab)
		if tab and not seen[tab] then
			seen[tab] = true
			list[#list + 1] = tab
		end
	end
	for i = 1, 8 do
		Add(_G["InspectFrameTab" .. i])
	end
	for _, tab in ipairs(f.Tabs or {}) do
		Add(tab)
	end
	return list
end

--------------------------------------------------------------------------------
-- The equipment slots, as the character window's (user, 2026-09-23: "onto the
-- Character Pane next"): every window's Button Border rim on the slot button
-- itself, the icon fitted into its opening, the quality border kept on the
-- icon (Kit:SkinActionButton); the game's frame art round the slot faded (a
-- template's BorderFrame picture, as the character window's; an older one's
-- "<slot>Frame" texture); an empty slot keeps the game's silhouette. Found by
-- the character window's names ("Inspect<X>Slot"), then any other item
-- button of the paper doll whose name ends in "Slot".
--------------------------------------------------------------------------------
local function SkinSlot(slot)
	if not slot or done[slot] or not slot.icon then
		return
	end
	done[slot] = true
	local art
	if slot.BorderFrame then
		art = Kit:FirstTexture(slot.BorderFrame)
		if art then
			Replace(art, { as = "UI-Character-Info-GearSlot" })
		end
	end
	local named = Part(slot, nil, "Frame")
	if IsTexture(named) and named ~= slot.icon then
		FadeArt(named)
		art = art or named
	end
	local rep = Kit:SkinActionButton(slot, Replace, nil, { as = Kit:ButtonRimRule(), qualityBorder = slot.IconBorder })
	slotList[#slotList + 1] = { slot = slot, rim = rep ~= nil, art = art }
end

local function SlotCandidates(f)
	local list, seen = {}, {}
	local function Add(b)
		if b and not seen[b] and b.icon and b.GetObjectType and b:GetObjectType() ~= "Texture" then
			seen[b] = true
			list[#list + 1] = b
		end
	end
	for _, key in ipairs(SLOT_KEYS) do
		Add(_G["Inspect" .. key .. "Slot"])
	end
	local doll = PaperDoll(f)
	for _, holder in ipairs({ _G.InspectPaperDollItemsFrame or false, doll or false, doll and doll.ItemsFrame or false }) do
		if holder and holder.GetChildren then
			for _, child in ipairs({ holder:GetChildren() }) do
				local n = NameOf(child)
				if n and n:find("Slot$") then
					Add(child)
				end
			end
		end
	end
	return list
end

local function SkinSlots(f)
	for _, slot in ipairs(SlotCandidates(f)) do
		SkinSlot(slot)
	end
end

--------------------------------------------------------------------------------
-- The model, as the character window's: its four race-landscape quadrants
-- faded (their union the replacement's rect), so the page stone runs on
-- behind the model -- one stone, no second tile with its own seam; the
-- game's vignette overlay stays on top. Round it, the single-rail viewport
-- frame (the character window's agreed addition, closed on every side: no
-- pane divider meets it here) -- unless the window has an inset, which is
-- the game's own frame round that area and gets the rail instead (replace,
-- never add).
--------------------------------------------------------------------------------
local QUADS = { { "BackgroundTopLeft", "BGTopLeft" }, { "BackgroundTopRight", "BGTopRight" },
	{ "BackgroundBotLeft", "BGBottomLeft" }, { "BackgroundBotRight", "BGBottomRight" } }

local function Quadrants(model)
	local n = NameOf(model)
	local list = {}
	for i, keys in ipairs(QUADS) do
		local t = model[keys[1]] or model[keys[2]] or (n and _G[n .. keys[1]]) or _G["InspectModelFrame" .. keys[1]]
		list[i] = IsTexture(t) and t or false
	end
	return list
end

local function SkinModel(f)
	local model = Model(f)
	if not model then
		found.model = "-- not found (no InspectModelFrame / InspectModelScene / paper doll model on this client)"
		return
	end
	if done[model] then
		return
	end
	done[model] = true
	skin.model = model
	local quads = Quadrants(model)
	local present = List(quads[1], quads[2], quads[3], quads[4])
	local faded = "none found"
	if #present > 0 then
		local union = model
		if quads[1] and quads[4] then
			union = CreateFrame("Frame", nil, model)
			union:EnableMouse(false)
			union:SetPoint("TOPLEFT", quads[1], "TOPLEFT")
			union:SetPoint("BOTTOMRIGHT", quads[4], "BOTTOMRIGHT")
		end
		local first = table.remove(present, 1)
		local rep = Replace(first, { as = "ModelSceneBackground", parent = model, rect = union, level = 0, alsoFade = present })
		faded = string.format("%d quadrants %s", #present + 1, rep and "faded" or "NOT faded")
	end
	local inset = f.Inset or _G.InspectFrameInset
	local frame
	if inset then
		Kit:SkinInset(inset, Replace, f)
		frame = string.format("the inset's rail (%s, dressed %s)", Label(inset), tostring(inset.melloRep ~= nil and inset.melloRep ~= false))
	else
		local rep = Replace(model, { as = "ViewportFrame", parent = model, rect = model, noFade = true, open = "" })
		frame = "viewport frame " .. (rep and "on" or "NOT made")
	end
	found.model = string.format("%s (%s): landscape %s, %s", Label(model), tostring(model:GetObjectType()), faded, frame)
end

--------------------------------------------------------------------------------
-- The model's control buttons: K2, the cog plate under the game's glyph. A
-- scene's control strip (square buttons: a grey plate NormalTexture and the
-- glyph on Icon) gets the cog in place of the plate, the glyph on top, as
-- the group finder's refresh button; an older model's round rotate buttons
-- (their curved-arrow glyph is their plate) get the cog UNDER them, not
-- faded, as the bags' sort button and the tabard vendor's.
--------------------------------------------------------------------------------
local function ControlButtons(model)
	local list, seen = {}, {}
	local function Add(b)
		if b and not seen[b] and b.GetObjectType and b:GetObjectType() == "Button" then
			seen[b] = true
			list[#list + 1] = b
		end
	end
	Add(_G.InspectModelFrameRotateLeftButton)
	Add(_G.InspectModelFrameRotateRightButton)
	if not model then
		return list
	end
	local n = NameOf(model)
	local strip = model.ControlFrame or (n and _G[n .. "ControlFrame"]) or nil
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
	for _, b in ipairs(ControlButtons(Model(f))) do
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
-- The character window's own art, wherever this window shows it (the level
-- plate, the pane pictures, a divider, the PvP tab's line): the same piece
-- by the same rule. Walked from the window down, past the slots and the
-- model (theirs above) and our own skin.
--------------------------------------------------------------------------------
local function SkinCharacterArt(root, depth)
	depth = depth or 0
	if not root or depth > 7 or root == (skin and skin.model) then
		return
	end
	for _, region in ipairs({ root:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece and not done[region] then
			local key = Kit:ArtKey(region)
			if key and CHARACTER_ART[key] then
				done[region] = true
				local rep = Replace(region, {})
				known[#known + 1] = { key = key, region = region, rep = rep }
			end
		end
	end
	for _, child in ipairs({ root:GetChildren() }) do
		if not (child.icon and child.IconBorder) then   -- a slot: SkinSlot's
			SkinCharacterArt(child, depth + 1)
		end
	end
end

--------------------------------------------------------------------------------
-- The other tabs' text on the palette's inner panel (WINDOW-RULES 2e; user,
-- 2026-09-24: "too much small text over a plain brown border is just an eye
-- strain"). The PvP / Honor, Talents and Guild pages are text (ranks, points,
-- names) straight on the page stone, with no inset of the game's to dress:
-- the panel is laid as a tint OVER that stone -- a region of the window in
-- the page picture's own layer, two sublevels up, on the picture's rect
-- inside the outer rail -- so every page's own art and text stay above it
-- (a talent tree's picture covers it); never a second stone (one stone per
-- surface). Shown while the kit is on and the paper doll is not: the paper
-- doll keeps its stone round the model, as the character window's does.
--------------------------------------------------------------------------------
local function PageRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "UI-Background-Rock" then
			return rep
		end
	end
end

local function MakeDim(f)
	if skin.dim ~= nil then
		return
	end
	skin.dim = false
	if not Kit.StoneDim then
		return
	end
	local page = PageRep()
	local rect
	local host, layer, sub = f, "BACKGROUND", 0
	if page and page.tex and page.inner then
		rect, host = page.inner, page.tex:GetParent() or f
		local ok, l, s = pcall(page.tex.GetDrawLayer, page.tex)
		if ok and l then
			layer, sub = l, s or 0
		end
	else
		-- no page picture (a window without its Bg): inside the outer rail
		local ins = Kit:OuterRailInset()
		rect = CreateFrame("Frame", nil, f)
		rect:EnableMouse(false)
		rect:SetPoint("TOPLEFT", f, "TOPLEFT", ins[1], -ins[3])
		rect:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ins[2], ins[4])
		sub = -6
	end
	local tex = Kit:StoneDim(host, { rect = rect, layer = layer, sublevel = math.min(sub + 2, 7), alpha = DIM_ALPHA })
	if tex then
		tex.kitPiece = true   -- ours: never faded as the game's art
		tex:Hide()
		skin.dim = tex
	end
end

local function Pages(f)
	local list, seen = {}, {}
	for _, n in ipairs(PAGE_NAMES) do
		local p = _G[n]
		if p and not seen[p] then
			seen[p] = true
			list[#list + 1] = p
		end
	end
	local doll = PaperDoll(f)
	if doll and not seen[doll] then
		table.insert(list, 1, doll)
	end
	return list
end

local function RefreshDims()
	local dim = skin and skin.dim
	if not dim then
		return
	end
	local f = Window()
	local doll = PaperDoll(f)
	dim:SetShown((active and not (doll and Shown(doll))) and true or false)
end

--------------------------------------------------------------------------------
-- Building, switching on and off
--------------------------------------------------------------------------------

-- What the window may make later (a page, a tab or a slot the game builds on
-- demand, a tab's controls): looked for again on every show and tab switch.
local function Discover(f)
	for _, tab in ipairs(Tabs(f)) do
		SkinTab(tab)
	end
	SkinSlots(f)
	SkinControls(f)
	for _, page in ipairs(Pages(f)) do
		if not pageHooked[page] then
			pageHooked[page] = true
			Perf.HookScript(page, "OnShow", RefreshDims)
			Perf.HookScript(page, "OnHide", RefreshDims)
		end
	end
	SkinCharacterArt(f)
	-- red buttons (the paper doll's view button), check boxes, dropdowns,
	-- scroll bars and insets on every page; the model is not walked into
	Kit:SweepControls(f, Replace, skin, skin.model)
end

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

	-- the shell: outer rail, ONE page stone for every tab, the ring on the
	-- inspected player's portrait, the title plate on the rail, the close
	-- (no Bg on the window: the rail keeps its own stone body instead)
	local portrait = Portrait(f)
	local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = portrait, bg = f.Bg and "UI-Background-Rock" or nil })
	found.shell = string.format("NineSlice %s, page stone (Bg) %s, title container %s, close %s", tostring(f.NineSlice ~= nil),
		tostring(f.Bg ~= nil), tostring(f.TitleContainer ~= nil), tostring(f.CloseButton ~= nil))
	if not f.NineSlice then
		found.shell = found.shell .. " -- an older window: no outer rail, no ring, no title plate"
	end
	skin.ring = ring
	SkinPortrait(portrait, ring)

	-- the model first (the inset, when there is one, is its frame), then the
	-- tabs, slots and controls, the character art, the sweep
	SkinModel(f)
	Discover(f)
	MakeDim(f)
end

-- Refresh's pass a frame later, once the game's own layout has run (made
-- once: Kit:NextFrame runs it once however often it was asked -- audit,
-- 2026-09-24; timed on this window's own /melloperf row, not the Kit's
-- timer -- review)
local RefreshLater = Shared("Refresh a frame later", function()
	local f = Window()
	if active and f and f:IsShown() then
		FitRing()
		PlaceTitles(true)
		RefreshDims()
	end
end, "timer")

-- After every show and tab switch: what the game re-laid or re-showed since
-- (the portrait's size, the title's plate, the tabs' cards, the pages'
-- panel), and once more a frame later, once the game's own layout has run.
local function Refresh()
	local f = Window()
	if not (active and skin and f) then
		return
	end
	Discover(f)
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	GuardTabs()
	RefreshDims()
	FitRing()
	PlaceTitles(true)
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
	-- the tabs' cards and the pages' panel hidden for good while off; the
	-- player's name back where the game put it, in its font (the ring's
	-- onDisable put the portrait back, the title plate's the title's points)
	GuardTabs()
	RefreshDims()
	PlaceTitles(false)
end

-- (user, 2026-09-24: "dress rarely used windows on first open") nothing of
-- the look is built while the window has never been shown this session: a
-- skin already built is switched on (and off), else only a window open right
-- now (a /reload with it open) is dressed at once; its first show dresses it
-- (the OnShow hook below), in that same frame, so it never draws undressed.
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

-- The first show in combat (a player inspected mid-fight) dresses at once
-- all the same: the dressing adds frames and textures of ours and moves or
-- sizes only the window's own unprotected parts (the portrait, the name
-- strings, the slots' icons in their rims), never a protected frame (the
-- inspect window has none). A window the game protects waits for the
-- fight's end, as before.
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
	-- a tab switch (the game's own tab helper; this window's only)
	if type(_G.PanelTemplates_SetTab) == "function" then
		hooksecurefunc("PanelTemplates_SetTab", function(frame)
			if frame == f then
				Refresh()
			end
		end)
	end
end

-- The window comes with the load-on-demand inspect addon: hooked when that
-- loads, or at once when it already has, and dressed as it first shows; the
-- inspected player's portrait and name arrive with INSPECT_READY, after the
-- window has shown.
local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(self, event)
	if event == "INSPECT_READY" then
		if active then
			Refresh()
		end
		return
	end
	-- (any addon's load: the window is looked for until it exists)
	if Window() then
		self:UnregisterEvent("ADDON_LOADED")
		Hook()
		if M.isEnabled then
			SyncSafe()
		end
	end
end)
eventFrame:RegisterEvent("ADDON_LOADED")
pcall(eventFrame.RegisterEvent, eventFrame, "INSPECT_READY")

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
-- /inspectdump [frames | reps | regions]: with no mode, what the skin found
-- and dressed (every part, found or not), the portrait against the class
-- medallion, the title's place and face, the tabs and the page picture per
-- tab, the slots, the model, and the window's own regions and children; the
-- modes are Kit:DumpWindow's. Opens the copy window.
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
	Line("title plate", rep and string.format("%s, shown %s", RectText(rep.strip or rep.object), tostring(Shown(rep.object))) or "-- none")
	local list, own = TitleStrings(f)
	local all = List(own, unpack(list))
	if #all == 0 then
		Line("title text", "-- no title string with text")
	end
	local plate = rep and (rep.strip or rep.object)
	for _, fs in ipairs(all) do
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
		Line("title text", string.format("%s '%s' %s; face %s %s, title face %s%s", Label(fs),
			tostring(TextOf(fs) or (HasText(fs) and "[secret]" or "(empty)")), where,
			(okF and type(face) == "string" and not Secret(face)) and face or "?", okF and Num(size) or "?",
			tostring(fs.melloFontSaved ~= nil),
			titleMoved[fs] and " (moved onto the plate)" or titleFaded[fs] and " (faded: duplicate)" or ""))
	end
end

local function DumpTabs(f)
	local okS, selected = pcall(function() return f.selectedTab end)
	Line("selected tab", (okS and not Secret(selected)) and tostring(selected) or "?")
	local page = PageRep()
	Line("page picture", page and string.format("%s (the one picture on every tab), inner %s, shown %s",
		RectText(page.tex), RectText(page.inner), tostring(Shown(page.tex))) or "-- none (no Bg on this window)")
	local tabs = Tabs(f)
	if #tabs == 0 then
		Line("tab", "-- none found")
	end
	for i, tab in ipairs(tabs) do
		local text = tab.Text or (tab.GetFontString and tab:GetFontString())
		Line("tab " .. i, string.format("%s '%s' %s, shown %s, cards %s", Label(tab), tostring(text and TextOf(text) or "?"),
			tostring(found.tabs and found.tabs[tab] or "not looked at"), tostring(Shown(tab)),
			tostring(tab.melloRep ~= nil and tab.melloRep ~= false)))
	end
	for _, p in ipairs(Pages(f)) do
		Line("page", string.format("%s shown %s, rect %s", Label(p), tostring(Shown(p)), RectText(p)))
	end
	Line("inner panel", skin and skin.dim and string.format("%s, shown %s (off the paper doll only)",
		RectText(skin.dim), tostring(Shown(skin.dim))) or "-- not made")
end

local function DumpParts(f)
	for _, key in ipairs(SLOT_KEYS) do
		local slot = _G["Inspect" .. key .. "Slot"]
		if not slot then
			Line("slot", string.format("Inspect%sSlot -- not found", key))
		end
	end
	for _, e in ipairs(slotList) do
		local q = e.slot.IconBorder
		Line("slot", string.format("%s rim %s, quality border %s, frame art %s", Label(e.slot), tostring(e.rim),
			q and (Shown(q) and "shown (kept)" or "hidden") or "none",
			e.art and (Label(e.art) .. (Kit.faded[e.art] and " faded" or " not faded")) or "none"))
	end
	Line("model", found.model)
	if #controls == 0 then
		Line("controls", "-- none found")
	end
	for _, c in ipairs(controls) do
		Line("control", string.format("%s cog %s, shown %s", Label(c.button), tostring(c.rep ~= nil), tostring(Shown(c.button))))
	end
	for _, k in ipairs(known) do
		Line("character art", string.format("%s on %s: %s", k.key, Label(k.region), k.rep and (k.rep.kind .. " piece") or "NOT dressed"))
	end
	local view = PaperDoll(f) and PaperDoll(f).ViewButton
	Line("view button", view and string.format("%s dressed %s", Label(view), tostring(view.melloRep ~= nil and view.melloRep ~= false)) or "-- none")
	Line("inked strings", "none: the window is on stone (no parchment option: the character window's parchment is its stats pane's and its own Window Background, neither shared)")
end

local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer, sub = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "")
		elseif kind == "FontString" then
			art = "text: " .. tostring(TextOf(region) or (HasText(region) and "[secret]" or "")):sub(1, 50)
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
	MelloUI:Print("InspectFrame: shown %s, level %s, kit %s, reps %d, faded art %d", tostring(Shown(f)), tostring(LevelOf(f) or "?"),
		active and "on" or "off", skin and #skin.reps or 0, #fadedArt)
	Line("shell", found.shell)
	DumpPortrait(f)
	DumpTitle(f)
	DumpTabs(f)
	DumpParts(f)
	MelloUI:Print("InspectFrame's own regions and children:")
	DumpOwn(f)
end

SLASH_MELLOINSPECTDUMP1 = "/inspectdump"
SlashCmdList.MELLOINSPECTDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if not f then
		local state = "the inspect addon's state could not be read"
		if C_AddOns and C_AddOns.IsAddOnLoaded then
			local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, INSPECT_ADDON)
			if ok and not Secret(loaded) then
				state = loaded and ("the inspect addon is loaded but made no InspectFrame: not on this client") or "the inspect addon is not loaded yet"
			end
		end
		MelloUI:Print("/inspectdump: no InspectFrame (%s; it loads with the first inspect: inspect a player, then try again)", state)
	elseif not skin then
		MelloUI:Print("/inspectdump: the inspect window is not dressed yet (%s)", M.isEnabled
			and "the kit dresses it the first time it opens: inspect a player, then try again" or "the Inspect Kit is off")
	elseif msg == "" then
		Summary(f)
	else
		-- frames / reps / regions (the visible game textures): the Kit's dump
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	end
	MelloUI:ShowLog("inspectdump " .. msg)
end
