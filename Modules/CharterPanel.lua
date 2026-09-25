--------------------------------------------------------------------------------
-- MelloUI - Guild Charter Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): The guild charter (petition) and the guild registrar in the kit.
--
-- Two ButtonFrameTemplate windows dressed the quest dialogs' way, by the
-- rule book (docs/WINDOW-RULES.md), on the game's own layout:
--   PetitionFrame -- the charter you sign or offer: its name, its leader, the
--   signatures and the instructions on a parchment page; Sign / Request
--   Signature / Rename / Close.
--   GuildRegistrarFrame -- the NPC who sells charters: a greeting page (the
--   services on offer) and a purchase page (the text, the cost, the guild
--   name's edit box); Purchase / Cancel.
-- Each: the window shell -- the outer double rail with its gem corners grown
-- outward, ONE page stone in place of the rock inside it, the title plate
-- riding the top rail with the window's title on it in the title face (2c),
-- the ring with the NPC (the registrar) or the charter's own seal (the
-- petition) at the class medallion's size on the dark disc (2b), the close
-- button; the inset's single rail; the game's parchment page -> the kit's
-- parchment page with the painted brush-stroke edge (the quest dialog's page,
-- "QuestDetailsBackgrounds"), one page on one rect for the registrar's two
-- pages (2a); every text on it in dark ink by the parchment rule (QuestInk);
-- the buttons on the red plates, their labels in their own colour (the rule's
-- exception, melloNoInk) and their disabled look kept; the guild name's box
-- on the edit plate (S1, its glass cap dropped: a name box); the cosmetic
-- scroll bars by the kit's sweep. No text lies on plain stone (2e).
-- The cost stays the game's coins on the page, inked: the window paints no
-- coin box under it, so none is added.
--
-- Nothing of the game's is replaced or re-scripted: hooks, regions and child
-- frames of our own, faded game art and our own texture in the ring, all put
-- back when the switch (UI Modifications, Windows) is turned off. No charter
-- API is called. Nothing is built at login: each window is dressed on its
-- first open (user, 2026-09-24) and kept.
--
-- /charterdump [registrar] [frames|reps|regions]: what a window is made of
-- and what was dressed.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("CharterPanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("CharterPanel", {
	title = "Guild Charter Kit",
	desc = "The guild charter (petition) and the guild registrar in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

-- the ink surface's name (QuestInk): both windows' pages
local AREA = "charter"
-- the charter's seal (the petition's portrait art): the ring's picture when
-- no texture of the window can be read and there is no NPC to draw
local CHARTER_ICON = "Interface\\PetitionFrame\\GuildCharter-Icon"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- the red plates' rule keys (Kit:SkinRedButton): a button on one keeps its
-- label's own colour
local RED_PLATES = { ["UI-Panel-Button-Up"] = true, ["_128-RedButton-Center"] = true }

-- What each window is made of, by the names its XML gives
local WINDOWS = {
	{
		key = "petition", frame = "PetitionFrame", unit = nil,
		pageKeys = { "Bg" },
		portraits = { "PetitionFramePortrait" },
		titles = { "PetitionFrameNpcNameText" },
		buttons = { "PetitionFrameSignButton", "PetitionFrameRequestButton", "PetitionFrameRenameButton", "PetitionFrameCancelButton" },
		-- the page's strings (regions of the window itself)
		strings = { "PetitionFrameCharterTitle", "PetitionFrameCharterName", "PetitionFrameMasterTitle", "PetitionFrameMasterName",
			"PetitionFrameMemberTitle", "PetitionFrameInstructions" },
		stringPattern = "^PetitionFrameMemberName%d+$",
		update = { "PetitionFrame_Update" },
	},
	{
		key = "registrar", frame = "GuildRegistrarFrame", unit = "npc",
		pageKeys = { "Bg" }, pageNames = { "GuildRegistrarFrameBg" },
		portraits = { "GuildRegistrarFramePortrait" },
		titles = { "GuildRegistrarFrameNpcNameText" },
		buttons = { "GuildRegistrarFramePurchaseButton", "GuildRegistrarFrameCancelButton", "GuildRegistrarFrameGoodbyeButton" },
		-- its two pages (full-window frames over the one parchment)
		pages = { "GuildRegistrarGreetingFrame", "GuildRegistrarPurchaseFrame" },
		edit = "GuildRegistrarFrameEditBox",
		money = "GuildRegistrarMoneyFrame",
		update = { "GuildRegistrar_OnShow", "GuildRegistrar_ShowPurchaseFrame" },
	},
}

local skin = nil          -- { reps, followers, windows = { [frame] = win } }
local active = false
local surfaceMade = false

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe and MelloUI.Safe.IsSecret or issecretvalue

local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Guild charter: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- A frame's name, secret-safe (nil when it has none or it cannot be read)
local function NameOf(f)
	if not (f and f.GetName) then
		return nil
	end
	local ok, name = pcall(f.GetName, f)
	if ok and type(name) == "string" and not Secret(name) then
		return name
	end
	return nil
end

-- A string's text: the text (nil when empty), and whether it read secret
local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	if not ok then
		return nil, false
	end
	if Secret(text) then
		return nil, true
	end
	if type(text) == "string" and text ~= "" then
		return text, false
	end
	return nil, false
end

local function IsTexture(t)
	return type(t) == "table" and t.GetObjectType ~= nil and t:GetObjectType() == "Texture"
end

-- Whether `f` lies under `root` (a few parents up)
local function IsUnder(f, root)
	for _ = 1, 10 do
		if not f then
			return false
		end
		if f == root then
			return true
		end
		f = f.GetParent and f:GetParent()
	end
	return false
end

-- Whether fs's centre lies in region r (their scales apart); nil while
-- either cannot be read yet
local function Inside(fs, r)
	local okF, fx, fy = pcall(fs.GetCenter, fs)
	local okR, l, b, w, h = pcall(r.GetRect, r)
	if not (okF and okR and fx and fy and l and w) or Secret(fx) or Secret(fy) or Secret(l) or Secret(b) or Secret(w) or Secret(h) then
		return nil
	end
	local k = fs:GetEffectiveScale() / r:GetEffectiveScale()
	fx, fy = fx * k, fy * k
	return fx >= l and fx <= l + w and fy >= b and fy <= b + h
end

--------------------------------------------------------------------------------
-- The page and the page stone, found by what they are: both windows give the
-- `Bg` key (the registrar also the template's global name) to their own
-- parchment, so the template's rock -- the tiled BACKGROUND texture -- is
-- found by its tiling, and the page is the window's untiled parchment.
--------------------------------------------------------------------------------
local function IsTiled(t)
	local ok, tiled = pcall(t.GetHorizTile, t)
	return ok and tiled == true
end

local function IsParchment(t)
	local ok, atlas = pcall(t.GetAtlas, t)
	if ok and type(atlas) == "string" and not Secret(atlas) then
		local a = atlas:lower()
		return a:find("parchment", 1, true) ~= nil or a:find("questbg", 1, true) ~= nil
	end
	return false
end

local function FindPage(frame, def)
	local list = {}
	for _, key in ipairs(def.pageKeys or {}) do
		list[#list + 1] = frame[key] or false
	end
	for _, name in ipairs(def.pageNames or {}) do
		list[#list + 1] = _G[name] or false
	end
	-- by its atlas first, else the first named one that is not the rock
	for _, t in ipairs(list) do
		if IsTexture(t) and not IsTiled(t) and IsParchment(t) then
			return t
		end
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece and region:GetDrawLayer() == "BACKGROUND" and not IsTiled(region) and IsParchment(region) then
			return region
		end
	end
	for _, t in ipairs(list) do
		if IsTexture(t) and not IsTiled(t) then
			return t
		end
	end
	return nil
end

local function FindRock(frame, page)
	local name = NameOf(frame)
	for _, t in ipairs({ frame.Bg or false, name and _G[name .. "Bg"] or false }) do
		if IsTexture(t) and t ~= page and (IsTiled(t) or Kit:ArtKey(t) == "UI-Background-Rock") then
			return t
		end
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if IsTexture(region) and region ~= page and not region.kitPiece and region:GetDrawLayer() == "BACKGROUND"
			and (IsTiled(region) or Kit:ArtKey(region) == "UI-Background-Rock") then
			return region
		end
	end
	return nil
end

-- The window's inset (ButtonFrameTemplate's, round the page): the single
-- rail, its marble faded, its holder two levels over the window (over the
-- page's edge, under the page's own frames' text: the quest dialogs' way).
-- Without a page on the kit's parchment the inset gets its stone under the
-- inner panel, so no text is on plain brown (2e).
local function DressInset(win, frame)
	local inset = frame.Inset
	if not inset or inset.melloRep ~= nil then
		return
	end
	local extra = { inset.Bg }
	if inset.NineSlice then
		for _, region in ipairs({ inset.NineSlice:GetRegions() }) do
			if region:GetObjectType() == "Texture" then
				extra[#extra + 1] = region
			end
		end
	end
	inset.melloRep = Replace(inset, { as = "common-insideframe", parent = frame, rect = inset, level = 2,
		body = not win.paper, noFade = true, alsoFade = extra }) or false
end

--------------------------------------------------------------------------------
-- The portrait (2b / 2c: an empty ring is a bug). Both windows draw their
-- picture into a texture of their own (the charter's seal, the registrar's
-- NPC by SetPortraitTexture), off the ring's centre and in the window's stack
-- under the kit's ring; the template's portrait stays empty. So the picture
-- is drawn by the kit itself, as the quest dialogs' NPC is: a texture of the
-- RING's holder, round-masked on the dark disc at the class medallion's size
-- (Kit:RingDisc: 0.759 x the ring), showing the NPC's portrait (the unit the
-- game draws) or the art the window's own portrait holds (the seal). The
-- game's portraits are faded meanwhile.
--------------------------------------------------------------------------------
local function PortraitCandidates(frame, def)
	local list, seen = {}, {}
	local function Add(t)
		if IsTexture(t) and not seen[t] and not t.kitPiece then
			seen[t] = true
			list[#list + 1] = t
		end
	end
	for _, name in ipairs(def.portraits or {}) do
		Add(_G[name])
	end
	local pc = frame.PortraitContainer
	Add(pc and pc.portrait)
	Add(frame.portrait)
	return list
end

local function PortraitArt(list)
	for _, t in ipairs(list or {}) do
		local ok, file = pcall(t.GetTexture, t)
		if ok and not Secret(file) and file ~= nil and ((type(file) == "number" and file > 0) or (type(file) == "string" and file ~= "")) then
			return file
		end
	end
	return CHARTER_ICON
end

local function UpdatePortrait(win)
	local icon = win.icon
	if not (icon and active) then
		return
	end
	if win.unit then
		local okE, exists = pcall(UnitExists, win.unit)
		-- a secret answer is taken as yes: the portrait call takes the unit
		-- token, never the answer
		local useUnit = okE and (Secret(exists) or exists == true)
		if useUnit and pcall(SetPortraitTexture, icon, win.unit) then
			return
		end
	end
	icon:SetTexture(PortraitArt(win.portraits))
end

local function SkinPortrait(win, frame)
	local ring = win.ring
	local holder = ring and ring.object
	if not (holder and holder.CreateTexture and ring.tex) then
		return
	end
	win.portraits = PortraitCandidates(frame, win.def)
	-- the disc and the picture on the ring's holder: disc BACKGROUND 6, the
	-- picture ARTWORK, the ring itself OVERLAY -- one stack, nothing of the
	-- game's between them
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
	mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	icon:AddMaskTexture(mask)
	win.icon = icon
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
		UpdatePortrait(win)
		for _, t in ipairs(win.portraits) do
			Kit:Fade(t)
		end
	end
	ring.onDisable = function(r)
		if onDisable then
			onDisable(r)
		end
		for _, t in ipairs(win.portraits) do
			Kit:Unfade(t)
		end
	end
end

--------------------------------------------------------------------------------
-- The title (2c). These windows never write into the title container's
-- TitleText: the petition writes "Guild Charter: <name>" and the registrar
-- the NPC's name into a string of their own (PetitionFrameNpcNameText,
-- GuildRegistrarFrameNpcNameText) on a frame a couple of levels over the
-- window -- far under the title plate, which rides the title container at
-- level 510. While the container's own string is empty, that string is lent
-- to the container (its parent, so it draws over the plate), centred on the
-- plate where the container's string sits, in the kit's title face
-- (Kit:TitleFont: the Fonts options and the Font Style); where the
-- container shows the same words it is faded instead. Its parent, points and
-- font are put back on disable. A name that reads secret is moved all the
-- same (the container's is empty: nothing is doubled).
--------------------------------------------------------------------------------
local function TitleStrings(win)
	local tc = win.frame.TitleContainer
	local own = tc and tc.TitleText
	local list = {}
	for _, name in ipairs(win.def.titles or {}) do
		local fs = _G[name]
		if fs and fs ~= own and fs.GetObjectType and fs:GetObjectType() == "FontString" then
			list[#list + 1] = fs
		end
	end
	local extra = win.frame.TitleText
	if extra and extra ~= own and extra.GetObjectType and extra:GetObjectType() == "FontString" then
		list[#list + 1] = extra
	end
	return list, own
end

local function PutBack(fs, saved)
	Kit:TitleFont(fs, false)
	if saved.parent and fs.SetParent then
		pcall(fs.SetParent, fs, saved.parent)
	end
	if saved.layer then
		pcall(fs.SetDrawLayer, fs, saved.layer, saved.sublevel or 0)
	end
	fs:ClearAllPoints()
	for _, pt in ipairs(saved.points) do
		fs:SetPoint(unpack(pt))
	end
	-- a string the XML gives no anchors fills its frame
	if #saved.points == 0 and saved.parent then
		fs:SetAllPoints(saved.parent)
	end
end

local function PlaceTitles(win, on)
	local moved, faded = win.titleMoved, win.titleFaded
	if not on then
		for fs, saved in pairs(moved) do
			PutBack(fs, saved)
		end
		wipe(moved)
		for fs in pairs(faded) do
			Kit:Unfade(fs)
		end
		wipe(faded)
		return
	end
	local rep = win.title
	if not rep then
		return
	end
	local tc = win.frame.TitleContainer
	local list, own = TitleStrings(win)
	local ownText, ownSecret = nil, false
	if own then
		ownText, ownSecret = TextOf(own)
	end
	for _, fs in ipairs(list) do
		local text, secret = TextOf(fs)
		if text and ownText and text == ownText then
			-- the same words already on the plate: this copy gives way
			if moved[fs] then
				PutBack(fs, moved[fs])
				moved[fs] = nil
			end
			if not faded[fs] then
				faded[fs] = true
				Kit:Fade(fs)
			end
		elseif (text or secret) and not ownText and not ownSecret then
			if faded[fs] then
				faded[fs] = nil
				Kit:Unfade(fs)
			end
			if not moved[fs] then
				local points = {}
				for i = 1, fs:GetNumPoints() do
					points[i] = { fs:GetPoint(i) }
				end
				local layer, sublevel = fs:GetDrawLayer()
				moved[fs] = { points = points, parent = fs:GetParent(), layer = layer, sublevel = sublevel }
				-- the container's frame (level 510) over the plate's holder
				if tc and fs.SetParent then
					pcall(fs.SetParent, fs, tc)
					pcall(fs.SetDrawLayer, fs, "OVERLAY", 1)
				end
			end
			fs:ClearAllPoints()
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
-- Text buttons on the red plates (B1), their labels in their own colour: the
-- parchment rule's exception for button labels (user, 2026-09-24) -- the ink's
-- walk never enters a button marked melloNoInk. The plate follows the
-- button's states, its disabled look included (Sign while the charter cannot
-- be signed, Request once it is full).
--------------------------------------------------------------------------------
local function PlainLabels(button)
	local QI = MelloUI.QuestInk
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "FontString" and region.melloInk and QI and QI.PlainText then
			pcall(QI.PlainText, region)
		end
	end
end

local function SkinTextButton(button)
	if not button then
		return
	end
	button.melloNoInk = true
	PlainLabels(button)
	if button.melloRep == nil then
		Kit:SkinRedButton(button, Replace)
	end
end

-- Buttons the kit's sweep put on a red plate (any this client adds): their
-- labels kept out of the ink too
local function MarkRedButtons(root, depth)
	if not root or depth > 8 then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		local rep = rawget(child, "melloRep")
		if type(rep) == "table" and RED_PLATES[rep.key] and not child.melloNoInk then
			child.melloNoInk = true
			PlainLabels(child)
		end
		MarkRedButtons(child, depth + 1)
	end
end

--------------------------------------------------------------------------------
-- The guild name's box (an EditBox with the chat box's Left / Right file
-- pieces reaching 10 px past it, no middle): the edit plate (S1) on the art's
-- own span, its LEFT cap dropped -- that cap carries the search glass, and
-- this is a name box (the chat box's rule) -- focused while typing. The box
-- is kept out of the ink: its text lies on the plate.
--------------------------------------------------------------------------------
local function EditPieces(box)
	local left, right
	for _, region in ipairs({ box:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece then
			local ok, point = pcall(region.GetPoint, region, 1)
			if ok and point == "LEFT" and not left then
				left = region
			elseif ok and point == "RIGHT" and not right then
				right = region
			end
		end
	end
	return left, right
end

local function SkinEdit(win, box)
	if not box or box.melloRep ~= nil then
		return
	end
	box.melloNoInk = true
	local left, right = EditPieces(box)
	if not (left and right) then
		box.melloRep = false
		return
	end
	local rect = CreateFrame("Frame", nil, box)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", left, "TOPLEFT")
	rect:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT")
	box.melloRep = Replace(left, { as = "UI-ChatInputBorder-Mid2", rect = rect, edit = box, dropCap = "l", alsoFade = { right } }) or false
	win.edit = box
end

--------------------------------------------------------------------------------
-- The ink (the parchment rule, user 2026-09-23 / 24: text on parchment is
-- dark ink, meaningful colours as dark shades of their hue, button labels
-- excepted): a QuestInk surface over the pages of every window whose page is
-- on the kit's parchment, inked with the sheet inks (the quest dialogs'
-- page). The petition's page strings are regions of the window itself: a
-- string of the window is inked when it lies on the page (the title string,
-- lent to the plate, and the buttons are not). The registrar's pages are
-- its greeting and purchase frames: a service there is a button whose label
-- lies on the paper (inked, though the default rules leave a string beside
-- an icon alone), and so are the cost's coins.
--------------------------------------------------------------------------------
local function InkOn()
	if not (active and skin) then
		return false
	end
	for _, win in pairs(skin.windows) do
		if win.paper then
			return true
		end
	end
	return false
end

local function InkRoots()
	local list = {}
	if skin then
		for frame, win in pairs(skin.windows) do
			if win.paper then
				if win.def.pages then
					for _, name in ipairs(win.def.pages) do
						if _G[name] then
							list[#list + 1] = _G[name]
						end
					end
				else
					list[#list + 1] = frame
				end
			end
		end
	end
	return unpack(list)
end

local function PetitionString(win, fs)
	local name = NameOf(fs)
	if name then
		for _, n in ipairs(win.def.strings or {}) do
			if n == name then
				return true
			end
		end
		if win.def.stringPattern and name:find(win.def.stringPattern) then
			return true
		end
	end
	return false
end

local function InkSkip(fs)
	local QI = MelloUI.QuestInk
	for frame, win in pairs(skin and skin.windows or {}) do
		if not win.def.pages and IsUnder(fs, frame) then
			-- the petition: only the window's own strings on its page
			if fs:GetParent() ~= frame then
				return true
			end
			if PetitionString(win, fs) then
				return false
			end
			local inside = win.page and Inside(fs, win.page)
			if inside == nil then
				return nil
			end
			return not inside
		end
	end
	local p = fs.GetParent and fs:GetParent()
	if p and p.GetObjectType and p:GetObjectType() == "Button" and not p.melloNoInk and p.melloRep == nil
		and p.GetFontString and p:GetFontString() == fs then
		return false
	end
	return QI.DefaultSkip(fs)
end

local function Surface()
	local QI = MelloUI.QuestInk
	if not (QI and QI.Surface) then
		return
	end
	if not surfaceMade then
		surfaceMade = true
		QI.Surface(AREA, { on = InkOn, sheet = true, skip = InkSkip, roots = InkRoots })
	else
		QI.RefreshSurface(AREA)
	end
end

--------------------------------------------------------------------------------
-- Building the skin
--------------------------------------------------------------------------------
local function RefreshWindow(frame)
	local win = active and skin and skin.windows[frame]
	if not win then
		return
	end
	UpdatePortrait(win)
	PlaceTitles(win, true)
	for _, f in ipairs(skin.followers) do
		f.rep:SetShown(f.region:IsShown())
	end
	Kit:SweepControls(frame, Replace, skin)
	MarkRedButtons(frame, 0)
	if surfaceMade then
		MelloUI.QuestInk.RefreshSurface(AREA)
	end
end

-- a window shown: dressed again now and once more when the game has laid it
-- out (the registrar writes its NPC's name in its OnShow)
local function OnWindowShown(frame)
	RefreshWindow(frame)
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			RefreshWindow(frame)
		end)
	end
end

local function BuildWindow(frame, def)
	local win = { frame = frame, def = def, unit = def.unit, followers = skin.followers, titleMoved = {}, titleFaded = {} }
	skin.windows[frame] = win
	win.page = FindPage(frame, def)
	win.rock = FindRock(frame, win.page)
	local pc = frame.PortraitContainer
	local portraits = PortraitCandidates(frame, def)
	local first = #skin.reps + 1
	-- the rail without its body when the rock becomes the page stone (one
	-- background per window); with its body when no rock was found
	local body = nil
	if win.rock then
		body = false
	end
	win.ring = Kit:SkinWindowShell(frame, Replace, win, { portrait = (pc and pc.portrait) or portraits[1], body = body })
	for i = first, #skin.reps do
		if skin.reps[i].key == "TitleBar" then
			win.title = skin.reps[i]
		end
	end
	if win.rock then
		win.rockRep = Replace(win.rock, { as = "UI-Background-Rock", parent = frame, rect = frame, inset = Kit:OuterRailInset() })
	end
	if win.ring then
		SkinPortrait(win, frame)
	end
	if win.page then
		win.pageRep = Replace(win.page, { as = "QuestDetailsBackgrounds" })
		win.paper = win.pageRep ~= nil
	end
	DressInset(win, frame)
	for _, name in ipairs(def.buttons or {}) do
		SkinTextButton(_G[name])
	end
	if def.edit then
		SkinEdit(win, _G[def.edit])
	end
	Kit:SweepControls(frame, Replace, skin)
	MarkRedButtons(frame, 0)
	-- (the window's own OnShow is hooked at enable: Hook, below)
	for _, name in ipairs(def.pages or {}) do
		local page = _G[name]
		if page then
			Perf.HookScript(page, "OnShow", function()
				if active then
					OnWindowShown(frame)
				end
			end)
		end
	end
	-- the title strings: placed again whenever the game writes them
	for _, name in ipairs(def.titles or {}) do
		local fs = _G[name]
		if fs and fs.SetText then
			local function Again()
				if active then
					PlaceTitles(win, true)
				end
			end
			hooksecurefunc(fs, "SetText", Again)
			if fs.SetFormattedText then
				hooksecurefunc(fs, "SetFormattedText", Again)
			end
		end
	end
	-- the game's own refreshes (the signatures, the purchase page shown)
	for _, fn in ipairs(def.update or {}) do
		if type(_G[fn]) == "function" then
			hooksecurefunc(fn, function()
				if active and frame:IsShown() then
					RefreshWindow(frame)
				end
			end)
		end
	end
end

-- (user, 2026-09-24: dress rarely used windows on first open): a window is
-- built the first time it shows -- from its OnShow hook (Hook, below), before
-- its first frame is drawn -- never at login; the charter and the registrar
-- each on their own first show. What was built is kept for the session. True
-- once anything is built.
local function Build()
	if not Kit then
		return false
	end
	for _, def in ipairs(WINDOWS) do
		local frame = _G[def.frame]
		if frame and not (skin and skin.windows[frame]) and frame:IsShown() then
			skin = skin or { reps = {}, followers = {}, windows = {} }
			BuildWindow(frame, def)
		end
	end
	return skin ~= nil
end

local function Activate()
	if active or not Build() then
		return
	end
	active = true
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for _, f in ipairs(skin.followers) do
		f.rep:SetShown(f.region:IsShown())
	end
	for frame, win in pairs(skin.windows) do
		PlaceTitles(win, true)
		if frame:IsShown() then
			UpdatePortrait(win)
		end
	end
	Surface()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	for _, win in pairs(skin.windows) do
		PlaceTitles(win, false)
	end
	-- every string back in the game's colours (the surface is off now)
	Surface()
end

-- The windows load with the interface (Blizzard_UIPanels_Game); wait for
-- them if not. The NPC's portrait is drawn again when the game's changes.
local function AnyWindow()
	for _, def in ipairs(WINDOWS) do
		if _G[def.frame] then
			return true
		end
	end
	return false
end

-- A window's show: dressed there and then on its first (Build makes only
-- what shows; while the kit is on its pieces are enabled as they are made),
-- so the first frame it draws is dressed -- also in combat: the build makes
-- frames and textures of ours and moves (lends to the title container) only
-- the game's own title string of these unprotected windows, nothing
-- protected (they were never held back for combat). The hook is installed at
-- enable and does nothing while the module is off.
local hookedFrames = setmetatable({}, { __mode = "k" })   -- [frame] = true: its OnShow hooked
local function Hook()
	for _, def in ipairs(WINDOWS) do
		local frame = _G[def.frame]
		if frame and not hookedFrames[frame] then
			hookedFrames[frame] = true
			Perf.HookScript(frame, "OnShow", function()
				if not M.isEnabled then
					return
				end
				if not active then
					Activate()
				elseif not skin.windows[frame] then
					-- built while the kit is on: its pieces were enabled as they
					-- were made, before their own enable (the ring's picture,
					-- its disc) was chained on -- enabled once more now
					local first = #skin.reps + 1
					Build()
					for i = first, #skin.reps do
						skin.reps[i]:Enable()
					end
				end
				if active and skin.windows[frame] then
					OnWindowShown(frame)
				end
			end)
		end
	end
end

local events = CreateFrame("Frame")
Perf.SetScript(events, "OnEvent", function(_, event)
	if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
		if M.isEnabled and not active and AnyWindow() then
			events:UnregisterEvent("ADDON_LOADED")
			events:UnregisterEvent("PLAYER_LOGIN")
			Hook()
			Activate()
		end
		return
	end
	if active and skin then
		for frame, win in pairs(skin.windows) do
			if frame:IsShown() then
				UpdatePortrait(win)
			end
		end
	end
end)
pcall(events.RegisterEvent, events, "UNIT_PORTRAIT_UPDATE")
pcall(events.RegisterEvent, events, "PORTRAITS_UPDATED")

function M:OnEnable(db)
	self.db = db
	if AnyWindow() then
		Hook()
		Activate()
	else
		events:RegisterEvent("ADDON_LOADED")
		events:RegisterEvent("PLAYER_LOGIN")
	end
end

function M:OnDisable()
	events:UnregisterEvent("ADDON_LOADED")
	events:UnregisterEvent("PLAYER_LOGIN")
	Deactivate()
end

--------------------------------------------------------------------------------
-- /charterdump [registrar] [frames|reps|regions]: the petition (or the
-- registrar) -- what was found and what each part was dressed as: the shell,
-- the portrait against the medallion, the title's position and font, the
-- page's rect on each of the window's pages, the buttons, the edit box, the
-- cost, the scroll bar and the inked strings. The modes are Kit:DumpWindow's.
-- Opens the copy window.
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

local function Num(v)
	if v == nil then
		return "nil"
	end
	if Secret(v) then
		return "[secret]"
	end
	return type(v) == "number" and string.format("%.0f", v) or tostring(v)
end

local function Shown(obj)
	local ok, s = pcall(obj.IsShown, obj)
	return (ok and not Secret(s)) and tostring(s) or "?"
end

local function RectOf(obj)
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if ok and l and not Secret(l) and not Secret(b) and not Secret(w) and not Secret(h) then
		return string.format("x=%.0f y=%.0f w=%.0f h=%.0f", l, b, w, h)
	end
	return "(no rect)"
end

local function Found(label, obj, more)
	MelloUI:Print("  %-26s %s%s", label, obj and Label(obj) or "-- not found", more or "")
end

local function RepState(rep)
	if rep == nil then
		return "not looked at"
	elseif rep == false then
		return "not dressed"
	end
	local shown = rep.object and rep.object.IsShown and rep.object:IsShown()
	return tostring(rep.key) .. (shown and " (shown)" or " (hidden)")
end

local function Colour(r, g, b)
	if type(r) ~= "number" or Secret(r) or type(g) ~= "number" or type(b) ~= "number" then
		return "?"
	end
	return string.format("%.0f %.0f %.0f", r * 255, g * 255, b * 255)
end

local function DumpShell(f, win, label)
	local okLv, lv = pcall(f.GetFrameLevel, f)
	MelloUI:Print("%s: shown %s, rect %s, level %s, kit %s, reps %d (both windows)", label, Shown(f), RectOf(f),
		okLv and Num(lv) or "?", active and "on" or "off", skin and #skin.reps or 0)
	Found("outer rail (NineSlice)", f.NineSlice, f.NineSlice and (" layout " .. tostring(f.NineSlice.layoutType)) or " (no shell)")
	Found("rock -> page stone", win and win.rock, win and (" " .. RepState(win.rockRep)) or nil)
	Found("ring", win and win.ring and win.ring.object, win and win.ring and (" " .. RepState(win.ring)) or nil)
	if win and win.ring and win.ring.tex then
		local okR, rw = pcall(win.ring.tex.GetWidth, win.ring.tex)
		local disc = win.ring.disc
		local okD, dw = false, nil
		if disc then
			okD, dw = pcall(disc.GetWidth, disc)
		end
		local icon = win.icon
		local okI, iw, ih, okT, file = false, nil, nil, false, nil
		if icon then
			okI, iw, ih = pcall(icon.GetSize, icon)
			okT, file = pcall(icon.GetTexture, icon)
		end
		MelloUI:Print("  portrait vs medallion: ring %s, medallion (0.759) %s, disc %s, picture %s x %s, art %s (unit %s)",
			okR and Num(rw) or "?", (okR and type(rw) == "number" and not Secret(rw)) and string.format("%.0f", rw * 0.759) or "?",
			okD and Num(dw) or "none", okI and Num(iw) or "?", okI and Num(ih) or "?", okT and Num(file) or "?", tostring(win.unit or "none"))
		for _, t in ipairs(win.portraits or {}) do
			local okF, art = pcall(t.GetTexture, t)
			Found("  game portrait", t, string.format(" art %s, alpha %s, faded %s", okF and Num(art) or "?", Num(t:GetAlpha()), tostring(Kit.faded[t] == true)))
		end
	end
	local tc = f.TitleContainer
	local own = tc and tc.TitleText
	local plate = win and win.title and (win.title.strip or win.title.object)
	Found("title plate", plate, win and string.format(" %s, rect %s", RepState(win.title), plate and RectOf(plate) or "-") or nil)
	local strings = win and (TitleStrings(win)) or {}
	if own then
		table.insert(strings, 1, own)
	end
	for _, fs in ipairs(strings) do
		local text, secret = TextOf(fs)
		local okF, face, size = pcall(fs.GetFont, fs)
		Found(fs == own and "title (container)" or "title (window's own)", fs, string.format(" text %s, face %s %s, title face %s, moved %s, faded %s, rect %s",
			secret and "[secret]" or tostring(text or "(empty)"), (okF and type(face) == "string" and not Secret(face)) and face or "?", okF and Num(size) or "?",
			tostring(fs.melloFontSaved ~= nil), tostring(win and win.titleMoved[fs] ~= nil), tostring(win and win.titleFaded[fs] == true), RectOf(fs)))
	end
	MelloUI:Print("  tabs: none; close button %s", f.CloseButton and RepState(rawget(f.CloseButton, "melloRep")) or "none")
end

local function DumpParts(f, win, def)
	local page = win and win.page
	local okA, atlas = false, nil
	if page then
		okA, atlas = pcall(page.GetAtlas, page)
	end
	Found("game page", page, page and string.format(" atlas %s, rect %s, alpha %s, faded %s", (okA and not Secret(atlas)) and tostring(atlas) or "?",
		RectOf(page), Num(page:GetAlpha()), tostring(Kit.faded[page] == true)) or nil)
	Found("page picture", win and win.pageRep and win.pageRep.tex, win and string.format(" %s, on parchment %s", RepState(win.pageRep), tostring(win.paper == true)) or nil)
	if def.pages then
		for _, name in ipairs(def.pages) do
			local p = _G[name]
			Found("page " .. name:gsub("^GuildRegistrar", ""), p, p and string.format(" shown %s; the page picture's rect %s (one picture for every page)",
				Shown(p), win and win.pageRep and win.pageRep.tex and RectOf(win.pageRep.tex) or "?") or nil)
		end
	end
	local inset = f.Inset
	Found("inset", inset, inset and (" " .. RepState(rawget(inset, "melloRep"))) or nil)
	for _, name in ipairs(def.buttons or {}) do
		local b = _G[name]
		local okE, enabled = false, nil
		if b then
			okE, enabled = pcall(b.IsEnabled, b)
		end
		local label = b and b.GetFontString and b:GetFontString()
		Found("button", b, b and string.format(" %s, shown %s, enabled %s, noInk %s, label colour %s", RepState(rawget(b, "melloRep")), Shown(b),
			(okE and not Secret(enabled)) and tostring(enabled) or "?", tostring(b.melloNoInk == true), label and Colour(label:GetTextColor()) or "-") or nil)
	end
	if def.edit then
		local box = _G[def.edit]
		Found("name box", box, box and string.format(" %s, rect %s", RepState(rawget(box, "melloRep")), RectOf(box)) or nil)
	end
	if def.money then
		local mf = _G[def.money]
		Found("cost (coins, inked)", mf, mf and string.format(" shown %s, rect %s", Shown(mf), RectOf(mf)) or nil)
	end
	local sb = f.ScrollBar
	Found("scroll bar (cosmetic)", sb, sb and string.format(" %s, shown %s", RepState(rawget(sb, "melloRep")), Shown(sb)) or nil)
end

local function DumpInk(f)
	local QI = MelloUI.QuestInk
	local def = QI and QI.surfaces and QI.surfaces[AREA]
	if not def then
		MelloUI:Print("ink surface: not made")
		return
	end
	local n = 0
	for fs in pairs(def.strings) do
		if IsUnder(fs, f) then
			n = n + 1
			if n <= 30 then
				local text, secret = TextOf(fs)
				MelloUI:Print("  ink %s %s colour %s: %s", tostring(fs.melloInk == true), Label(fs), Colour(fs:GetTextColor()),
					secret and "[secret]" or tostring(text or ""):sub(1, 40))
			end
		end
	end
	MelloUI:Print("ink surface: on %s, strings in this window %d", tostring(def.active == true), n)
end

local function DumpOwn(f)
	for _, region in ipairs({ f:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer, sub = pcall(region.GetDrawLayer, region)
		local what = ""
		if kind == "Texture" then
			what = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "") .. (IsTiled(region) and " tiled" or "")
		elseif kind == "FontString" then
			local text, secret = TextOf(region)
			what = "text: " .. (secret and "[secret]" or tostring(text or ""):sub(1, 40))
		end
		MelloUI:Print("  region %s %s %s/%s %s alpha %s shown %s", kind, Label(region), okL and tostring(layer) or "?", okL and tostring(sub) or "?",
			what, Num(region:GetAlpha()), Shown(region))
	end
	for _, child in ipairs({ f:GetChildren() }) do
		local okLv, lv = pcall(child.GetFrameLevel, child)
		MelloUI:Print("  child %s %s level %s shown %s kit %s", tostring(child:GetObjectType()), Label(child), okLv and Num(lv) or "?",
			Shown(child), RepState(rawget(child, "melloRep")))
	end
end

SLASH_MELLOCHARTERDUMP1 = "/charterdump"
SlashCmdList.MELLOCHARTERDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local which, mode = msg:match("^(%S*)%s*(.-)$")
	local def = WINDOWS[1]
	if which == "registrar" then
		def = WINDOWS[2]
	else
		mode = msg
	end
	local f = _G[def.frame]
	MelloUI:ClearLog()
	if not f then
		MelloUI:Print("/charterdump: %s is not on this client", def.frame)
	elseif mode == "" then
		local win = skin and skin.windows[f]
		MelloUI:Print("Guild charter kit: module %s, dressed %s, built %s", tostring(M.isEnabled == true), tostring(active), tostring(win ~= nil))
		if not win then
			MelloUI:Print("%s: not dressed yet (the kit dresses it on its first open this session)", def.frame)
		end
		DumpShell(f, win, def.frame)
		DumpParts(f, win, def)
		DumpInk(f)
		MelloUI:Print("%s's own regions and children:", def.frame)
		DumpOwn(f)
		if not _G.ArenaRegistrarFrame then
			MelloUI:Print("(ArenaRegistrarFrame: not on this client)")
		end
	else
		if not (skin and skin.windows[f]) then
			MelloUI:Print("%s: not dressed yet (the kit dresses it on its first open this session)", def.frame)
		end
		-- frames / reps / regions (the visible game textures): the Kit's dump
		Kit:DumpWindow(f, skin, mode ~= "regions" and mode or nil)
	end
	MelloUI:ShowLog("charterdump " .. msg)
end
