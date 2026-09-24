--------------------------------------------------------------------------------
-- MelloUI - Quest Dialogs Kit
--
-- (user, 2026-09-24: "we didnt do quest dialogs, shops, Auction House,
-- profession training window, class trainers, Guild Crest Vendors, Flight
-- map, all should follow the rules"): the quest giver's dialogs (QuestFrame:
-- its greeting, offer, progress and reward panels) and the gossip window
-- (GossipFrame) dressed in the painted kit on the game's own layout, by the
-- rule book (docs/WINDOW-RULES.md):
--   the window shell -- the outer double rail with its gem corners grown
--   outward, the page stone, the title plate riding the top rail with the
--   NPC's name on it in the title face (2c), the portrait ring with the NPC's
--   portrait at the class medallion's size on the dark disc (2b), the close
--   button; the inset's single rail; the game's parchment page -> the kit's
--   parchment page with the painted brush-stroke edge (the quest log's own
--   details page, "QuestDetailsBackgrounds"), ONE page on one rect for all
--   four quest panels (2a); every text on it in dark ink by the parchment
--   rule (QuestInk), the red plate buttons excepted; the Accept / Decline /
--   Complete / Continue / Cancel / Goodbye buttons on the red plates; item,
--   reward and spell buttons in every window's Button Border rim with the
--   plain plate under their names; scroll bars by the kit's sweep.
-- No text lies on plain stone (2e): the dialogs' text is all on the page.
-- Should a client's dialog have no parchment region to replace, its inset
-- is filled with the list-box stone under the palette's inner panel instead
-- and its text keeps the game's colours.
--
-- Nothing of the game's is replaced or re-scripted: the dress is hooks,
-- regions and child frames of our own, faded game art and our own texture in
-- the ring, all put back when the switch (UI Modifications, Windows: "Quest
-- dialogs") is turned off. No quest API is called.
--
-- /questdialogdump [gossip]: what the window is made of and what was dressed.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("QuestDialogPanel", {
	title = "Quest Dialogs Kit",
	desc = "The quest giver's dialogs (offer, progress, reward) and the gossip window in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

-- the ink surface's name (QuestInk): the dialogs' pages
local AREA = "questdialog"
-- what the game shows in the ring when there is no NPC to draw (a quest
-- taken from an item): QuestFrame_SetPortrait's own fallback
local BOOK_ICON = "Interface\\QuestFrame\\UI-QuestLog-BookIcon"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- the quest frame's four pages, each with its own copy of the parchment
local QUEST_PANELS = { "QuestFrameGreetingPanel", "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel" }
-- its text buttons (UIPanelButtonTemplate), by the names the template gives them
local QUEST_BUTTONS = { "QuestFrameAcceptButton", "QuestFrameDeclineButton", "QuestFrameCompleteButton", "QuestFrameGoodbyeButton",
	"QuestFrameCompleteQuestButton", "QuestFrameGreetingGoodbyeButton" }
-- a title string an older layout of the window may write the NPC's name into
-- instead of the title container's TitleText
local EXTRA_TITLES = { QuestFrame = { "QuestFrameNpcNameText" }, GossipFrame = { "GossipFrameNpcNameText" } }
-- the quest text frames the game shares between the dialog and the quest
-- log's details view (QuestInfo_Display parents them to whichever shows)
local QUEST_INFO = { "QuestInfoFrame", "QuestInfoObjectivesFrame", "QuestInfoSpecialObjectivesFrame", "QuestInfoTimerFrame",
	"QuestInfoRequiredMoneyFrame", "QuestInfoSealFrame", "QuestInfoSpacerFrame" }
-- the red plates' rule keys (Kit:SkinRedButton): a button on one keeps its
-- label's own colour (the parchment rule's exception for button labels)
local RED_PLATES = { ["UI-Panel-Button-Up"] = true, ["_128-RedButton-Center"] = true }

local skin = nil           -- { reps, followers, windows = { [frame] = win }, paper }
local active = false
local surfaceMade = false
local itemButtons = {}     -- every item button given a rim (refitted on a new Button Border)
local labelLayers = setmetatable({}, { __mode = "k" })   -- [label] = { layer, sublevel }: a fallback plate's label, raised over it

local function Secret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end

local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Quest dialogs: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- A rep shown while the game shows `region` (art the game toggles itself:
-- the greeting's horizontal break).
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

-- A frame's name, secret-safe (nil when it has none or it cannot be read)
local function NameOf(f)
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

--------------------------------------------------------------------------------
-- The page: the game's parchment region of every panel replaced by the kit's
-- parchment page with the painted edge, on ONE rect (2a: the four quest
-- panels' pages lie in the same place with the same crop, so switching from
-- the offer to the reward never moves the paper). The rect is the game's own
-- parchment region -- the detail panel's, whose size stays the atlas's (the
-- progress panel re-atlases its own for a quest's theme) -- or, should that
-- have no size on this client, the text's scroll area.
--------------------------------------------------------------------------------
local function FitPageRect(win)
	local rect, bg, area = win.pageRect, win.pageBg, win.pageArea
	local ok, w = false, nil
	if bg then
		ok, w = pcall(bg.GetWidth, bg)
	end
	local target = (ok and w and not Secret(w) and w > 1) and bg or area
	if target and win.pageTarget ~= target then
		win.pageTarget = target
		rect:ClearAllPoints()
		rect:SetAllPoints(target)
	end
end

-- The game's art laid over a panel's parchment for some quests (the stone,
-- marble or silver materials, a campaign seal's picture): faded with the
-- parchment it lies on, so every quest's page is the kit's one parchment and
-- its text keeps the ink it is set for.
local function PanelArt(panel, bg)
	local list = {}
	if not panel then
		return list
	end
	for _, region in ipairs({ panel:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= bg and not region.kitPiece then
			local layer = region:GetDrawLayer()
			if layer == "BACKGROUND" or layer == "BORDER" then
				list[#list + 1] = region
			end
		end
	end
	return list
end

local function DressPage(win, bg, art)
	if not bg then
		return nil
	end
	local rep = Replace(bg, { as = "QuestDetailsBackgrounds", rect = win.pageRect, alsoFade = art })
	if rep then
		win.paper = true
		skin.paper = true
	end
	return rep
end

-- The window's inset (ButtonFrameTemplate's, round the page): the single
-- rail, its marble faded. Its holder goes two levels over the window --
-- above the panels (one level up, the page is their region), below their
-- scroll frames' text: the rail lies over the page's edge and never ties with
-- the panels (the kit's own SkinInset puts it at the panels' level). A window
-- whose page could not be dressed gets the inset's stone under the inner
-- panel instead, so its text is not on plain brown (2e).
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
-- The portrait (2b / 2c: an empty ring is a bug). The quest frame draws its
-- NPC into a texture of its own (QuestFramePortrait, off the ring's centre),
-- the gossip window into the template's portrait; both sit in the window's
-- own stack under the kit's ring. So the NPC is drawn by the kit itself, as
-- the macro window's icon is: a texture of the RING's holder, round-masked on
-- the dark disc at the class medallion's size (Kit:RingDisc: 0.759 x the
-- ring), showing the NPC's portrait (SetPortraitTexture on the unit the game
-- draws) or, with no NPC, the art the game's portrait holds (the quest book).
-- The game's portraits are faded meanwhile and put back on disable.
--------------------------------------------------------------------------------
local function PortraitCandidates(frame)
	local list, seen = {}, {}
	local pc = frame.PortraitContainer
	local function Add(t)
		if t and not seen[t] and t.GetObjectType and t:GetObjectType() == "Texture" then
			seen[t] = true
			list[#list + 1] = t
		end
	end
	if frame == _G.QuestFrame then
		Add(_G.QuestFramePortrait)
	end
	Add(pc and pc.portrait)
	Add(frame.portrait)
	return list
end

-- the art the first portrait with a file holds (secret-safe)
local function PortraitArt(list)
	for _, t in ipairs(list or {}) do
		local ok, file = pcall(t.GetTexture, t)
		if ok and file ~= nil and not Secret(file) and ((type(file) == "number" and file > 0) or (type(file) == "string" and file ~= "")) then
			return file
		end
	end
	return BOOK_ICON
end

local function UpdatePortrait(win)
	local icon = win.icon
	if not (icon and active) then
		return
	end
	local okE, exists = pcall(UnitExists, win.unit)
	-- a secret answer is taken as yes: the portrait call takes the unit
	-- token, never the answer
	local useUnit = okE and (Secret(exists) or exists == true)
	if useUnit and pcall(SetPortraitTexture, icon, win.unit) then
		return
	end
	icon:SetTexture(PortraitArt(win.portraits))
end

local function SkinPortrait(win, frame)
	local ring = win.ring
	local holder = ring and ring.object
	if not (holder and holder.CreateTexture and ring.tex) then
		return
	end
	win.portraits = PortraitCandidates(frame)
	-- the disc and the NPC on the ring's holder: disc BACKGROUND 6, NPC
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
-- The title (2c). The title plate's rule centres the title container's
-- TitleText (where SetTitle writes the NPC's name) on the plate in the kit's
-- title face (Kit:TitleFont: the Fonts options and the Font Style). An older
-- layout of these windows writes the name into a string of its own
-- (QuestFrameNpcNameText in QuestNpcNameFrame, GossipFrameNpcNameText): such
-- a string is put on the plate in the title face while the container's is
-- empty, or faded where the container already shows the same words; its
-- points and font put back on disable. Where the two cannot be compared (a
-- name read secret) it is left alone, never doubled on the plate.
--------------------------------------------------------------------------------
local function TitleStrings(frame)
	local tc = frame.TitleContainer
	local own = tc and tc.TitleText
	local list, seen = {}, {}
	if own then
		seen[own] = true
	end
	local function Add(fs)
		if fs and not seen[fs] and fs.GetObjectType and fs:GetObjectType() == "FontString" then
			seen[fs] = true
			list[#list + 1] = fs
		end
	end
	for _, name in ipairs(EXTRA_TITLES[NameOf(frame) or ""] or {}) do
		Add(_G[name])
	end
	Add(frame.TitleText)
	local npcName = frame == _G.QuestFrame and _G.QuestNpcNameFrame or nil
	if npcName and npcName.GetRegions then
		for _, region in ipairs({ npcName:GetRegions() }) do
			Add(region)
		end
	end
	return list, own
end

local function PlaceTitles(win, on)
	local moved, faded = win.titleMoved, win.titleFaded
	if not on then
		for fs, points in pairs(moved) do
			Kit:TitleFont(fs, false)
			fs:ClearAllPoints()
			for _, pt in ipairs(points) do
				fs:SetPoint(unpack(pt))
			end
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
	local list, own = TitleStrings(win.frame)
	local ownText, ownSecret = nil, false
	if own then
		ownText, ownSecret = TextOf(own)
	end
	for _, fs in ipairs(list) do
		local text = TextOf(fs)
		if text and ownText and text == ownText then
			-- the same words already on the plate: this copy gives way
			if not faded[fs] then
				faded[fs] = true
				Kit:Fade(fs)
			end
		elseif text and not ownText and not ownSecret then
			if faded[fs] then
				faded[fs] = nil
				Kit:Unfade(fs)
			end
			if not moved[fs] then
				local points = {}
				for i = 1, fs:GetNumPoints() do
					points[i] = { fs:GetPoint(i) }
				end
				moved[fs] = points
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
-- Text buttons on the red plates (B1), their labels in their own colour: the
-- parchment rule's exception for button labels (user, 2026-09-24) -- the ink's
-- walk never enters a button marked melloNoInk. Kit:SkinRedButton knows the
-- game's two button layouts; a button laid out otherwise gets the plate on
-- its LOWEST texture (DialogPanel's way: on one above the label it covered
-- it), its other art faded, and its label raised over the plate while dressed.
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
	if button.melloRep ~= nil then
		return
	end
	local ok, rep = pcall(Kit.SkinRedButton, Kit, button, Replace)
	if ok and rep then
		return
	end
	local anchor, extra, anchorRank = nil, {}, 99
	local RANK = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4 }
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			local rank = RANK[region:GetDrawLayer()]
			if rank and rank < anchorRank then
				if anchor then
					extra[#extra + 1] = anchor
				end
				anchor, anchorRank = region, rank
			else
				extra[#extra + 1] = region
			end
		end
	end
	for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local tex = button[get] and button[get](button)
		if tex and tex ~= anchor then
			extra[#extra + 1] = tex
		end
	end
	button.melloRep = anchor and Replace(anchor, { as = "_128-RedButton-Center", rect = button, button = button, alsoFade = extra }) or false
	local label = button.GetFontString and button:GetFontString()
	if button.melloRep and label and label.GetDrawLayer then
		local layer, sub = label:GetDrawLayer()
		labelLayers[label] = { layer, sub }
		if active then
			pcall(label.SetDrawLayer, label, "OVERLAY", 7)
		end
	end
end

local function RaiseLabels(on)
	for label, was in pairs(labelLayers) do
		if on then
			pcall(label.SetDrawLayer, label, "OVERLAY", 7)
		elseif was[1] then
			pcall(label.SetDrawLayer, label, was[1], was[2] or 0)
		end
	end
end

-- Buttons the kit's sweep put on a red plate (any this client adds to the
-- dialogs): their labels kept out of the ink too
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
-- Item buttons (the required items, the rewards, a spell or reputation
-- reward: LargeItemButtonTemplate and its kin -- an Icon and a NameFrame
-- plate with the name on it). The icon in every window's Button Border rim
-- (R1), hugging it as the professions' reagents do (its edge 2 px under the
-- rim's inner edge, on the icon's centre; the game's quality border stays
-- inside, as the bags'), the name plate on the plain gemless plate from the
-- icon's right edge to the button's, the icon's height. The name and the
-- count keep their colours: they lie on a plate, not on the paper (QuestInk
-- skips a string whose button shows a rep).
--------------------------------------------------------------------------------
local function IconOf(button)
	local icon = button.Icon or button.icon
	local name = NameOf(button)
	if not icon and name then
		icon = _G[name .. "IconTexture"]
	end
	if icon and icon.GetObjectType and icon:GetObjectType() == "Texture" then
		return icon
	end
	return nil
end

local function NameFrameOf(button)
	local nf = button.NameFrame
	local name = NameOf(button)
	if not nf and name then
		nf = _G[name .. "NameFrame"]
	end
	if nf and nf.GetObjectType and nf:GetObjectType() == "Texture" then
		return nf
	end
	return nil
end

local function FitIconRim(button)
	local rep = button.melloRep
	local rim = type(rep) == "table" and rep.object
	local icon = IconOf(button)
	if not (rim and rim.base and icon) then
		return
	end
	local name = rim.base .. "_normal"
	local p = Kit:Piece(name)
	local l, r, t, b = Kit:Insets(name, 1)
	local ok, iw, ih = pcall(icon.GetSize, icon)
	if not (p and l and ok and iw and ih) or Secret(iw) or Secret(ih) or iw <= 4 or ih <= 4 then
		return
	end
	rim:ClearAllPoints()
	rim:SetPoint("CENTER", icon, "CENTER")
	rim:SetSize((iw - 4) * p.w / (p.w - l - r), (ih - 4) * p.h / (p.h - t - b))
end

-- the plate's width: from the icon's right edge to the button's (both of the
-- button's own frame, so one scale)
local function FitNamePlate(button)
	local rect, icon = button.melloPlateRect, IconOf(button)
	if not (rect and icon) then
		return
	end
	local okB, br = pcall(button.GetRight, button)
	local okI, ir = pcall(icon.GetRight, icon)
	if okB and okI and br and ir and not Secret(br) and not Secret(ir) and br - ir > 1 then
		rect:SetWidth(br - ir)
	end
end

local function SkinItemButton(button)
	if button.melloRep ~= nil then
		return
	end
	local icon, nameFrame = IconOf(button), NameFrameOf(button)
	if not (icon and nameFrame) then
		button.melloRep = false
		return
	end
	local rim = Replace(icon, { as = Kit:ButtonRimRule(), button = button, parent = button, noFade = true })
	button.melloRep = rim or false
	if rim then
		itemButtons[#itemButtons + 1] = button
		Kit:RegisterButtonRim(button)
		FitIconRim(button)
	end
	local rect = CreateFrame("Frame", nil, button)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", icon, "TOPRIGHT")
	rect:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT")
	rect:SetWidth(1)
	button.melloPlateRect = rect
	button.melloPlate = Replace(nameFrame, { as = "UI-QuestItemNameFrame", rect = rect }) or false
	FitNamePlate(button)
	button:HookScript("OnShow", function(b)
		if active then
			FitIconRim(b)
			FitNamePlate(b)
		end
	end)
end

-- every item button under `root`, found by what it is (the reward buttons
-- and the spell / reputation rewards are made on demand)
local function SkinItemsIn(root, depth)
	depth = depth or 0
	if not root or depth > 8 or not root.GetChildren then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		if child:GetObjectType() == "Button" and child.melloRep == nil and IconOf(child) and NameFrameOf(child) then
			SkinItemButton(child)
		elseif not child.melloNoInk then
			SkinItemsIn(child, depth + 1)
		end
	end
end

-- a new Button Border has a new opening: every rim fitted again
Kit:OnBorderChanged("button", function()
	for _, button in ipairs(itemButtons) do
		FitIconRim(button)
	end
end)

--------------------------------------------------------------------------------
-- The ink (the parchment rule, user 2026-09-23 / 24: text on parchment is
-- dark ink, meaningful colours as dark shades of their hue, button labels
-- excepted): a QuestInk surface over the pages of every window whose page is
-- on the kit's parchment, inked with the sheet inks (the page is the vellum
-- in the kit's one parchment tone, as a sheet). A quest title or a gossip
-- option is a button whose label lies on the paper: it is inked, though the
-- default rules leave a string beside an icon alone.
--------------------------------------------------------------------------------
local function InkOn()
	return active and skin ~= nil and skin.paper == true
end

local function InkRoots()
	local list = {}
	if skin then
		local qwin = _G.QuestFrame and skin.windows[_G.QuestFrame]
		if qwin and qwin.paper then
			for _, name in ipairs(QUEST_PANELS) do
				if _G[name] then
					list[#list + 1] = _G[name]
				end
			end
		end
		local gf = _G.GossipFrame
		local gwin = gf and skin.windows[gf]
		if gwin and gwin.paper and gf.GreetingPanel then
			list[#list + 1] = gf.GreetingPanel
		end
	end
	return unpack(list)
end

local function InkSkip(fs)
	local QI = MelloUI.QuestInk
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

-- The quest text shown in the quest log instead (QuestInfo_Display parents
-- the shared frames there): its strings in the game's colours again, as the
-- quest log draws them
local function PlainQuestInfo()
	local QI = MelloUI.QuestInk
	if not (QI and QI.PlainText) then
		return
	end
	local function Walk(frame, depth)
		if not frame or depth > 8 then
			return
		end
		for _, region in ipairs({ frame:GetRegions() }) do
			if region:GetObjectType() == "FontString" and region.melloInk then
				QI.PlainText(region)
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			Walk(child, depth + 1)
		end
	end
	for _, name in ipairs(QUEST_INFO) do
		Walk(_G[name], 0)
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
	FitPageRect(win)
	UpdatePortrait(win)
	PlaceTitles(win, true)
	for _, f in ipairs(skin.followers) do
		f.rep:SetShown(f.region:IsShown())
	end
	-- controls made since (pooled rewards, a scroll bar laid out late)
	SkinItemsIn(frame)
	Kit:SweepControls(frame, Replace, skin)
	MarkRedButtons(frame, 0)
	if surfaceMade then
		MelloUI.QuestInk.RefreshSurface(AREA)
	end
end

-- a window shown: dressed again now and once more when the game has laid it
-- out (the gossip window sets its page's picture after it shows)
local function OnWindowShown(frame)
	RefreshWindow(frame)
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			RefreshWindow(frame)
		end)
	end
end

-- The shell every dialog shares: rail, page stone, ring, title, close.
local function BuildShell(frame, unit)
	local win = { frame = frame, unit = unit, followers = skin.followers, titleMoved = {}, titleFaded = {} }
	skin.windows[frame] = win
	local pc = frame.PortraitContainer
	local portrait = (pc and pc.portrait) or (frame == _G.QuestFrame and _G.QuestFramePortrait) or nil
	local first = #skin.reps + 1
	win.ring = Kit:SkinWindowShell(frame, Replace, win, { portrait = portrait, bg = "UI-Background-Rock" })
	for i = first, #skin.reps do
		if skin.reps[i].key == "TitleBar" then
			win.title = skin.reps[i]
		end
	end
	if win.ring then
		SkinPortrait(win, frame)
	end
	win.pageRect = CreateFrame("Frame", nil, frame)
	win.pageRect:EnableMouse(false)
	return win
end

local function BuildQuest(qf)
	local win = BuildShell(qf, "questnpc")
	local detail = _G.QuestFrameDetailPanel
	win.pageBg = detail and (detail.Bg or _G.QuestFrameDetailPanelBg) or nil
	win.pageArea = _G.QuestDetailScrollFrame or detail
	FitPageRect(win)
	for _, name in ipairs(QUEST_PANELS) do
		local panel = _G[name]
		if panel then
			local bg = panel.Bg or _G[name .. "Bg"]
			DressPage(win, bg, PanelArt(panel, bg))
			panel:HookScript("OnShow", function()
				if active then
					OnWindowShown(qf)
				end
			end)
		end
	end
	DressInset(win, qf)
	for _, name in ipairs(QUEST_BUTTONS) do
		SkinTextButton(_G[name])
	end
	-- the greeting's line between the current and the available quests,
	-- shown by the game only when both are listed
	local brk = _G.QuestGreetingFrameHorizontalBreak
	if brk then
		Follow(Replace(brk, { as = "UI-HorizontalBreak" }), brk)
	end
	for _, name in ipairs(QUEST_PANELS) do
		SkinItemsIn(_G[name])
	end
	Kit:SweepControls(qf, Replace, skin)
	MarkRedButtons(qf, 0)
	qf:HookScript("OnShow", function()
		if active then
			OnWindowShown(qf)
		end
	end)
	if type(_G.QuestFrame_SetPortrait) == "function" then
		hooksecurefunc("QuestFrame_SetPortrait", function()
			if active then
				UpdatePortrait(win)
				PlaceTitles(win, true)
			end
		end)
	end
end

local function BuildGossip(gf)
	local win = BuildShell(gf, "npc")
	local gp = gf.GreetingPanel
	win.pageBg = gf.Background
	win.pageArea = gp and gp.ScrollBox or gp
	FitPageRect(win)
	DressPage(win, gf.Background, PanelArt(gp, nil))
	DressInset(win, gf)
	SkinTextButton(gp and gp.GoodbyeButton)
	Kit:SweepControls(gf, Replace, skin)
	MarkRedButtons(gf, 0)
	gf:HookScript("OnShow", function()
		if active then
			OnWindowShown(gf)
		end
	end)
	-- the game sets the portrait and the page's picture in its own update
	-- after the window shows: follow them (post-hooks on the instance; the
	-- update also runs on quest log changes, so only while it is shown)
	for _, method in ipairs({ "HandleShow", "Update" }) do
		if type(gf[method]) == "function" then
			hooksecurefunc(gf, method, function()
				if active and gf:IsShown() then
					RefreshWindow(gf)
				end
			end)
		end
	end
end

local hooked = false
local function Hook()
	if hooked then
		return
	end
	hooked = true
	-- the quest text frames go where the game shows them: dressed and inked
	-- on the dialog's page, in the game's colours in the quest log
	if type(_G.QuestInfo_Display) == "function" then
		hooksecurefunc("QuestInfo_Display", function(_, parentFrame)
			if not active then
				return
			end
			local qf = _G.QuestFrame
			if qf and IsUnder(parentFrame, qf) then
				SkinItemsIn(parentFrame)
				if surfaceMade then
					MelloUI.QuestInk.RefreshSurface(AREA)
				end
			else
				PlainQuestInfo()
			end
		end)
	end
end

local function Build()
	local qf, gf = _G.QuestFrame, _G.GossipFrame
	if not (qf or gf) or not Kit then
		return false
	end
	if not skin then
		skin = { reps = {}, followers = {}, windows = {} }
	end
	if qf and not skin.windows[qf] then
		BuildQuest(qf)
	end
	if gf and not skin.windows[gf] then
		BuildGossip(gf)
	end
	Hook()
	return true
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
	RaiseLabels(true)
	for frame, win in pairs(skin.windows) do
		FitPageRect(win)
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
	RaiseLabels(false)
	for _, win in pairs(skin.windows) do
		PlaceTitles(win, false)
	end
	-- every string back in the game's colours (the surface is off now)
	Surface()
	PlainQuestInfo()
end

-- The dialogs load with the interface; wait for them if not. The NPC's
-- portrait is drawn again when the game's changes.
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
		if M.isEnabled and not active and (_G.QuestFrame or _G.GossipFrame) then
			events:UnregisterEvent("ADDON_LOADED")
			events:UnregisterEvent("PLAYER_LOGIN")
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
	if _G.QuestFrame or _G.GossipFrame then
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
-- /questdialogdump [gossip]: the quest frame (or the gossip window) -- its
-- regions and children, the page, portrait, title, buttons, item buttons,
-- scroll bars and inked strings found and dressed; opens the copy window.
--------------------------------------------------------------------------------
local function Num(v)
	if v == nil then
		return "nil"
	end
	if Secret(v) then
		return "[secret]"
	end
	return type(v) == "number" and string.format("%.0f", v) or tostring(v)
end

local function Size(obj)
	local ok, w, h = pcall(obj.GetSize, obj)
	if not ok then
		return "?"
	end
	return Num(w) .. " x " .. Num(h)
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

local function DumpFrame(label, frame)
	MelloUI:Print("%s: shown %s, size %s, level %s, strata %s", label, tostring(frame:IsShown()), Size(frame),
		Num(frame:GetFrameLevel()), tostring(frame:GetFrameStrata()))
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local layer = region.GetDrawLayer and region:GetDrawLayer() or "?"
		local what = ""
		if kind == "Texture" then
			what = (region.kitPiece and "kit " or "") .. tostring(Kit:ArtKey(region) or "?")
		elseif kind == "FontString" then
			local text, secret = TextOf(region)
			what = "text: " .. (secret and "[secret]" or tostring(text or ""):sub(1, 40))
		end
		MelloUI:Print("  region %s %s %s %s alpha %s shown %s faded %s", kind, tostring(NameOf(region) or ""), tostring(layer), what,
			Num(region:GetAlpha()), tostring(region:IsShown()), tostring(Kit.faded[region] == true))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		MelloUI:Print("  child %s %s layout %s level %s alpha %s shown %s kit %s", tostring(child:GetObjectType()),
			tostring(NameOf(child) or (child.GetDebugName and child:GetDebugName()) or "?"), tostring(child.layoutType),
			Num(child:GetFrameLevel()), Num(child:GetAlpha()), tostring(child:IsShown()), RepState(rawget(child, "melloRep")))
	end
end

local function DumpButtons(root, depth, counts)
	if not root or depth > 8 then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		if child:GetObjectType() == "Button" then
			local label = child.GetFontString and child:GetFontString()
			local text = label and TextOf(label)
			local rep = rawget(child, "melloRep")
			if IconOf(child) and NameFrameOf(child) then
				counts.items = counts.items + 1
				local name = rawget(child, "Name") or (NameOf(child) and _G[NameOf(child) .. "Name"])
				MelloUI:Print("  item %s shown %s rim %s plate %s name %s", tostring(NameOf(child) or "?"), tostring(child:IsShown()),
					RepState(rep), RepState(rawget(child, "melloPlate")), tostring(name and name.GetText and TextOf(name) or ""))
			elseif rep ~= nil or text then
				MelloUI:Print("  button %s shown %s plate %s noInk %s label %s", tostring(NameOf(child) or "?"), tostring(child:IsShown()),
					RepState(rep), tostring(child.melloNoInk == true), tostring(text or ""):sub(1, 30))
			end
		end
		if child.Track and child.Track.Thumb and child.Back and child.Forward then
			counts.bars = counts.bars + 1
			MelloUI:Print("  scroll bar %s shown %s kit %s", tostring(NameOf(child) or "?"), tostring(child:IsShown()), RepState(rawget(child, "melloRep")))
		elseif child.ScrollUpButton or child.ScrollDownButton then
			MelloUI:Print("  scroll bar (old layout, not dressed) %s", tostring(NameOf(child) or "?"))
		end
		DumpButtons(child, depth + 1, counts)
	end
end

SLASH_MELLOQUESTDIALOGDUMP1 = "/questdialogdump"
SlashCmdList.MELLOQUESTDIALOGDUMP = function(msg)
	msg = (msg or ""):lower()
	local gossip = msg == "gossip"
	local frame = gossip and _G.GossipFrame or _G.QuestFrame
	local label = gossip and "GossipFrame" or "QuestFrame"
	MelloUI:ClearLog()
	if not frame then
		MelloUI:Print("/questdialogdump: no %s on this client", label)
		MelloUI:ShowLog("questdialogdump " .. msg)
		return
	end
	local win = skin and skin.windows[frame]
	MelloUI:Print("Quest dialogs kit: module %s, dressed %s, built %s, page on parchment %s", tostring(M.isEnabled == true),
		tostring(active), tostring(win ~= nil), tostring(win and win.paper or false))
	DumpFrame(label, frame)
	if win then
		MelloUI:Print("shell: ring %s, title plate %s, NPC portrait %s (unit %s)", RepState(win.ring), RepState(win.title),
			win.icon and tostring(win.icon:GetTexture()) or "none", tostring(win.unit))
		for _, t in ipairs(win.portraits or {}) do
			local ok, file = pcall(t.GetTexture, t)
			MelloUI:Print("  game portrait %s art %s alpha %s faded %s", tostring(NameOf(t) or "?"), ok and Num(file) or "?",
				Num(t:GetAlpha()), tostring(Kit.faded[t] == true))
		end
		local list, own = TitleStrings(frame)
		local ownText, ownSecret = nil, false
		if own then
			ownText, ownSecret = TextOf(own)
		end
		MelloUI:Print("  title container text %s", ownSecret and "[secret]" or tostring(ownText or "(empty)"))
		for _, fs in ipairs(list) do
			local text, secret = TextOf(fs)
			MelloUI:Print("  other title string %s text %s moved %s faded %s", tostring(NameOf(fs) or "?"),
				secret and "[secret]" or tostring(text or "(empty)"), tostring(win.titleMoved[fs] ~= nil), tostring(win.titleFaded[fs] == true))
		end
		MelloUI:Print("page: rect %s on %s; game page %s (%s, size %s); inset %s", Size(win.pageRect),
			win.pageTarget == win.pageBg and "the game's page" or "the text area", tostring(win.pageBg and NameOf(win.pageBg) or "none"),
			tostring(win.pageBg and Kit:ArtKey(win.pageBg) or "?"), win.pageBg and Size(win.pageBg) or "-", RepState(frame.Inset and rawget(frame.Inset, "melloRep")))
		if not gossip then
			for _, name in ipairs(QUEST_PANELS) do
				local panel = _G[name]
				if panel then
					local bg = panel.Bg or _G[name .. "Bg"]
					MelloUI:Print("  %s shown %s page %s art %s alpha %s", name, tostring(panel:IsShown()), bg and "found" or "none",
						tostring(bg and Kit:ArtKey(bg) or "?"), bg and Num(bg:GetAlpha()) or "-")
				end
			end
		end
	end
	local counts = { items = 0, bars = 0 }
	DumpButtons(frame, 0, counts)
	MelloUI:Print("item buttons %d, scroll bars %d", counts.items, counts.bars)
	local QI = MelloUI.QuestInk
	local def = QI and QI.surfaces and QI.surfaces[AREA]
	if def then
		local n = 0
		for fs in pairs(def.strings) do
			if IsUnder(fs, frame) then
				n = n + 1
				if n <= 30 then
					local text, secret = TextOf(fs)
					local r, g, b = fs:GetTextColor()
					MelloUI:Print("  ink %s %s colour %s %s %s: %s", tostring(fs.melloInk == true), tostring(NameOf(fs) or ""),
						Num(r and r * 255), Num(g and g * 255), Num(b and b * 255), secret and "[secret]" or tostring(text or ""):sub(1, 40))
				end
			end
		end
		MelloUI:Print("ink surface: on %s, strings in this window %d", tostring(def.active == true), n)
	else
		MelloUI:Print("ink surface: not made")
	end
	MelloUI:ShowLog("questdialogdump " .. msg)
end
