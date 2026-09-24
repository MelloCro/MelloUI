--------------------------------------------------------------------------------
-- MelloUI - Backpack Panel
--
-- The bag windows (ContainerFrameCombinedBags and ContainerFrame1..7, the
-- flat portrait windows) dressed in the painted kit (Modules/Kit.lua) on the
-- game's own layout, by the rule book's fixed looks and the user's pick
-- (kit_raw/bag_catalog.png, 2026-09-21: B2):
--   the window shell (outer rail, one page stone inside it, the ring on the
--   bag icon with the icon at the medallion size on the dark disc, the title
--   plate on the rail, the close button); the pooled item buttons in the
--   action bars' thin rims (user, 2026-09-23: "onto the backpack icons
--   next"), Item Border and Item Background chosen here or with previews by
--   Dynamic UI Modification, the icons filling them, empty slots on the
--   chosen background, the game's quality border kept on the icon (the rim untinted —
--   user, 2026-09-21); the search box S1; the sort button on the cog; the
--   money strip on the header plate (B2), its frame raised above the rims.
-- The item buttons are re-acquired and re-laid by the game on every open
-- (UpdateItemLayout): skinned from that post-hook. Covers the Dark Mode
-- group "backpack". /bagdump [1-7|combined] [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("BackpackPanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Kit = MelloUI.Kit

local LOOKS = Kit.buttonLooks

-- Window Background (user, 2026-09-23: "the option to change the background
-- in the Backpack is not there"): the cracked concrete the windows wear (the
-- page stone's own middle, repeated), or another of the button backgrounds
-- over the whole window (not None: the world would show through the bag)
local WINDOW_BACKGROUNDS = {}
for _, v in ipairs(LOOKS.backgrounds) do
	if v.value ~= "none" then
		WINDOW_BACKGROUNDS[#WINDOW_BACKGROUNDS + 1] = v
	end
end

local M = MelloUI:RegisterModule("BackpackPanel", {
	title = "Backpack Kit",
	desc = "The bag windows dressed in the painted kit on the game's own layout.",
	enabledByDefault = true,
	defaults = { itemBackground = "stone", windowBackground = "concrete" },
	options = {
		{ type = "dropdown", key = "windowBackground", name = "Window Background", values = WINDOW_BACKGROUNDS,
		  desc = "What the bag windows show behind the items: cracked concrete (the window's own), stone, iron plate, parchment, leather or dark." },
		{ type = "dropdown", key = "itemBackground", name = "Item Background", values = LOOKS.backgrounds,
		  desc = "What an empty bag slot shows inside its rim. Both are also chosen with previews by Dynamic UI Modification, at the top of the configurator. The slots' rim is UI Modifications' Button Border (every window's)." },
	},
})

local skin = nil
local active = false

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Backpack: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- The lists a pass over a bag's buttons works in, kept and filled again (a
-- bag lays out a hundred slots and more, several times on every open:
-- nothing is made per slot -- /melloperf, 2026-09-24)
local itemList, lefts, tops = {}, {}, {}

-- the rim's pitch last set on each skinned button (a side table): a pass
-- that measures the same pitch leaves the rim and its icon as they are
local pitchX = setmetatable({}, { __mode = "k" })
local pitchY = setmetatable({}, { __mode = "k" })

-- a list's first n entries sorted, the rest cleared (table.sort reads #list)
local function SortFirst(list, n)
	for i = #list, n + 1, -1 do
		list[i] = nil
	end
	table.sort(list)
end

local function SmallestGap(list, n, size)
	SortFirst(list, n)
	local best = nil
	for i = 2, n do
		local d = list[i] - list[i - 1]
		if d > 1 and d < size * 2 and (not best or d < best) then
			best = d
		end
	end
	return best
end

-- The grid's pitch: the smallest gap between any two laid-out item
-- buttons on each axis (the pool hands its buttons over in no order; the
-- first two were often not neighbours, their gap was thrown out and the
-- pitch fell back to the button's own size — gems doubled on the first
-- open after a reload, user 2026-09-22). Else the button's own size.
local function ItemPitch(buttons, count)
	local a = buttons[1]
	local ok, w, h = pcall(a.GetSize, a)
	if not ok or Secret(w) or not (w and w > 0) then
		return nil
	end
	local n = 0
	for i = 1, count do
		local b = buttons[i]
		local okL, l = pcall(b.GetLeft, b)
		local okT, t = pcall(b.GetTop, b)
		if okL and okT and l and t and not Secret(l) and not Secret(t) then
			n = n + 1
			lefts[n], tops[n] = l, t
		end
	end
	local px, py = SmallestGap(lefts, n, w) or w, SmallestGap(tops, n, h) or h
	-- a grid: the same spacing on both axes
	local pad = math.max(px - w, py - h, 0)
	return { w + pad, h + pad }
end

-- the same pitch within rounding (the positions are read back as floats)
local function SamePitch(a, b)
	return a ~= nil and b ~= nil and math.abs(a - b) < 0.01
end

local skinning = false   -- a pass under way (one started inside it gets a list of its own)

-- The kit's options for a slot, one table filled again for each (the kit
-- reads them while it skins the button and keeps none of them): a bag's
-- first open skins a hundred slots and more in one frame (/melloperf, user
-- 2026-09-24: 19.1 ms), nothing made per slot that the slot does not keep
local slotOpts = { emptyStone = true }

-- A slot just skinned: its Item Background. The stone the kit just made
-- already wears the default one (its tile, laid and shown): only another
-- choice is put on
local function NewSlotBackground(button)
	local value = M.db and M.db.itemBackground or "stone"
	local stone = button.melloSlotStone
	local tex = stone and stone.tex
	if tex and tex.kitName and tex.kitName == LOOKS.backgroundPiece[value] then
		return
	end
	Kit:SetButtonBackground(button, value)
end

-- The combined bags' slot picture, faded while the skin is on (the Item
-- Background stands in). Faded straight: its rule is a 'fade', and a
-- replacement made for it is an empty holder frame and a table per slot, a
-- hundred slots and more in the first open's layout (user, 2026-09-24:
-- 19.1 ms). Through a replacement as before while the editing tools could
-- list or tune it (they work on replacements), or its rule is tuned into
-- another kind. `plain`: that answer, when the caller has it already.
local SLOT_BG = "BagSlotBackground"

local function PlainSlotFade()
	if Kit.liveEdit then
		return false
	end
	local rule = Kit:RuleFor(SLOT_BG)
	if not (rule and rule.kind == "fade") then
		return false
	end
	local KT = MelloUI.KitTuning
	return not (KT and KT:Tune(SLOT_BG))
end

local function FadeSlotBackground(region, plain)
	if plain == nil then
		plain = PlainSlotFade()
	end
	if not plain then
		Replace(region, { as = SLOT_BG })
		return
	end
	skin.slotBgs[#skin.slotBgs + 1] = region
	if active then
		Kit:Fade(region)
	end
end

local function SkinItems(frame)
	local pool = frame.itemButtonPool
	if not pool then
		return
	end
	local buttons, count = skinning and {} or itemList, 0
	for button in pool:EnumerateActive() do
		count = count + 1
		buttons[count] = button
	end
	for i = #buttons, count + 1, -1 do
		buttons[i] = nil
	end
	if count == 0 then
		return
	end
	local outer = not skinning
	skinning = true
	local pitch = ItemPitch(buttons, count)
	local rimRule, plainFade = nil, nil
	for i = 1, count do
		local button = buttons[i]
		if button.melloRep == nil then
			rimRule = rimRule or Kit:ButtonRimRule()
			slotOpts.as, slotOpts.qualityBorder = rimRule, button.IconBorder
			local rep = Kit:SkinActionButton(button, Replace, pitch, slotOpts)
			slotOpts.qualityBorder = nil
			if rep then
				skin.items[#skin.items + 1] = button
				NewSlotBackground(button)
				if pitch then
					pitchX[button], pitchY[button] = pitch[1], pitch[2]
				end
			end
		elseif button.melloRep and button.melloRep.SetPitch and pitch
			and not (SamePitch(pitchX[button], pitch[1]) and SamePitch(pitchY[button], pitch[2])) then
			-- re-laid on a new pitch only: the same pitch again (every open, the
			-- beat after it, the size changes) would re-anchor every rim and icon
			-- for nothing
			button.melloRep:SetPitch(pitch[1], pitch[2])
			pitchX[button], pitchY[button] = pitch[1], pitch[2]
		end
		-- the combined bags' slot picture is the BUTTON's (made by the game
		-- when the button is set up for the combined bag, Initialize): faded,
		-- the Item Background stands in (a second background under it before)
		if button.ItemSlotBackground and not button.melloSlotBg then
			button.melloSlotBg = true
			if plainFade == nil then
				plainFade = PlainSlotFade()
			end
			FadeSlotBackground(button.ItemSlotBackground, plainFade)
		end
	end
	if outer then
		skinning = false
	end
end

-- A window's background choice: `alt` (a tile on the window's background
-- rect, in its layer) stands in for the window's own, which is see-through
-- meanwhile; the window's own piece is that background itself. One surface
-- either way.
local function ApplyWindowBackground(entry)
	local value = M.db and M.db.windowBackground or "concrete"
	local pic, alt = entry.rep.tex, entry.alt
	local piece = LOOKS.backgroundPiece[value]
	if not active or piece == pic.kitName or not (piece or value == "dark") then
		alt:Hide()
		pic:SetAlpha(1)
		return
	end
	if piece then
		if alt.kitName ~= piece then
			alt:SetVertexColor(1, 1, 1, 1)
			Kit:Apply(alt, piece)
		end
		Kit:Retile(alt)
	else
		alt:SetColorTexture(0.05, 0.045, 0.04, 0.95)
		alt.kitName = nil
	end
	alt:Show()
	pic:SetAlpha(0)
end

local function WatchWindowBackground(frame)
	local picture
	for _, r in ipairs(skin.reps) do
		if r.region == frame.Bg and r.key == "UI-Background-Rock" and r.tex and r.inner then
			picture = r
		end
	end
	if not picture then
		return
	end
	local layer, sub = picture.tex:GetDrawLayer()
	local alt = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
	alt.kitPiece = true   -- ours: never faded
	alt.kitScale = Kit.scale
	alt.kitAlign = "center"   -- as the window's own
	alt:SetAllPoints(picture.inner)
	alt:Hide()
	local entry = { rep = picture, alt = alt }
	skin.windowBgs[#skin.windowBgs + 1] = entry
	local enable, disable = picture.onEnable, picture.onDisable
	picture.onEnable = function(...)
		if enable then
			enable(...)
		end
		ApplyWindowBackground(entry)
	end
	picture.onDisable = function(...)
		if disable then
			disable(...)
		end
		alt:Hide()
		picture.tex:SetAlpha(1)
	end
	-- a tile sized while hidden is laid again when it shows or resizes
	local function Retile()
		if alt:IsShown() and alt.kitName then
			Kit:Retile(alt)
		end
	end
	Perf.HookScript(picture.inner, "OnSizeChanged", Retile)
	Perf.HookScript(frame, "OnShow", Retile)
	if active then
		ApplyWindowBackground(entry)
	end
end

local function SkinBag(frame)
	if not frame or skin.bags[frame] then
		return
	end
	skin.bags[frame] = true
	local portrait = frame.PortraitContainer and frame.PortraitContainer.portrait
	local ring = Kit:SkinWindowShell(frame, Replace, skin, { portrait = portrait, bg = "UI-Background-Rock" })
	WatchWindowBackground(frame)
	if ring and portrait then
		-- the bag icon is a square item icon: at the medallion size on the disc (2b)
		local function Fit()
			pcall(Kit.FitPortrait, Kit, portrait, ring)
		end
		ring.onEnable = Fit
		ring.onDisable = function()
			pcall(Kit.UnfitPortrait, Kit, portrait)
		end
		Kit:RingDisc(ring, nil, frame.PortraitContainer, 0)   -- chains onto the fit above
		if active then
			Fit()
		end
		hooksecurefunc(portrait, "SetTexture", function()
			if active then
				Fit()
			end
		end)
	end
	if frame.Bg then
		for _, key in ipairs({ "BottomLeft", "BottomRight", "BottomEdge", "TopSection" }) do
			if frame.Bg[key] then
				Replace(frame.Bg[key], { as = "uiframebackground-nineslice-cornerbottomleft" })
			end
		end
	end
	if frame.Background1Slot then
		Replace(frame.Background1Slot, { as = "UI-Bag-1Slot" })
	end
	-- the money strip (B2) on the border's rect; the money frame raised above
	-- the item buttons (level 10 in their template) while the skin is on, as
	-- the bottom row's pitch-sized rims reach over it (user, 2026-09-21: the
	-- slot borders covered the gold); put back on disable
	local money = frame.MoneyFrame
	local moneyRep = nil
	if money and money.Border and money.Border.Middle then
		local rep = Replace(money.Border.Middle, { as = "common-coinbox-center", rect = money.Border, alsoFade = { money.Border.Left, money.Border.Right } })
		moneyRep = rep
		if rep then
			local saved = money:GetFrameLevel()
			local function Raise()
				local level = saved
				for button in (frame.itemButtonPool and frame.itemButtonPool:EnumerateActive() or function() end) do
					level = math.max(level, button:GetFrameLevel())
				end
				money:SetFrameLevel(level + 1)
			end
			rep.onEnable = Raise
			rep.onDisable = function()
				money:SetFrameLevel(saved)
			end
			if active then
				Raise()
			end
		end
	end
	-- the first open after a reload lays the slots out before the bag has
	-- its final size, and the pitch measured then was the slots' own size
	-- (gems doubled between neighbours until the bag was reopened — user,
	-- 2026-09-22): measured again on show, on the bag's size change, and
	-- a beat after showing; SetPitch refits the rims already made (and only
	-- those whose pitch changed, SkinItems)
	local function Remeasured()
		if active and frame:IsShown() then
			SkinItems(frame)
		end
	end
	-- the next frame's pass is one pass however many ask for it (an open asks
	-- three times: the layout, the show, the size change)
	local nextFrameAsked = false
	local function NextFrame()
		nextFrameAsked = false
		Remeasured()
	end
	local function Remeasure(delay)
		if not (C_Timer and C_Timer.After) then
			return
		end
		if delay > 0 then
			C_Timer.After(delay, Remeasured)
		elseif not nextFrameAsked then
			nextFrameAsked = true
			C_Timer.After(0, NextFrame)
		end
	end
	Perf.HookScript(frame, "OnShow", function()
		Remeasure(0)
		Remeasure(0.3)
	end)
	Perf.HookScript(frame, "OnSizeChanged", function()
		Remeasure(0)
	end)
	-- the items, on every layout; the combined bags' slot picture once it exists
	if frame.UpdateItemLayout then
		hooksecurefunc(frame, "UpdateItemLayout", function(f)
			if active then
				SkinItems(f)
				-- the first layout after a reload answers with the slots' old
				-- rects (the pitch came out wrong until the bag was reopened
				-- — user, 2026-09-21): measured again on the next frame
				Remeasure(0)
				-- the money frame raised over the slots again (this bag's strip,
				-- kept from above rather than looked for among every rep)
				if moneyRep and moneyRep.rect == (f.MoneyFrame and f.MoneyFrame.Border) and moneyRep.onEnable then
					moneyRep.onEnable()
				end
				if f.ItemSlotBackground and not f.melloSlotBg then
					f.melloSlotBg = true
					FadeSlotBackground(f.ItemSlotBackground)
				end
			end
		end)
	end
	SkinItems(frame)
	if frame.ItemSlotBackground then
		frame.melloSlotBg = true
		FadeSlotBackground(frame.ItemSlotBackground)
	end
end

local function Build()
	if not skin then
		skin = { reps = {}, followers = {}, bags = {}, items = {}, windowBgs = {}, slotBgs = {} }
	end
	SkinBag(ContainerFrameCombinedBags)
	for i = 1, 7 do
		SkinBag(_G["ContainerFrame" .. i])
	end
	if BagItemSearchBox then
		Kit:SkinSearchBox(BagItemSearchBox, Replace)
	end
	local sort = BagItemAutoSortButton
	if sort and sort.GetNormalTexture and sort:GetNormalTexture() and sort.melloRep == nil then
		sort.melloRep = Replace(sort:GetNormalTexture(), { as = "bags-button-autosort-up", button = sort, noFade = true }) or false
	end
end

local function Activate()
	if active then
		return
	end
	active = true
	Build()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for _, region in ipairs(skin.slotBgs) do
		Kit:Fade(region)
	end
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	Kit:Cover("backpack")
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	for _, region in ipairs(skin.slotBgs) do
		Kit:Unfade(region)
	end
	Kit:Uncover("backpack")
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if not skin then
		return
	end
	if key == "windowBackground" then
		for _, entry in ipairs(skin.windowBgs) do
			ApplyWindowBackground(entry)
		end
		return
	end
	for _, button in ipairs(skin.items) do
		if key == "itemBackground" then
			Kit:SetButtonBackground(button, value)
		end
	end
end

--------------------------------------------------------------------------------
-- For the Dynamic UI Modification picker (Modules/DynamicUI.lua): the bag
-- windows are one group; the picker opens the bags while it runs when none
-- is open, and closes them again after.
--------------------------------------------------------------------------------

local openedForPicker = false

local function BagWindows()
	local list = { ContainerFrameCombinedBags }
	for i = 1, 7 do
		list[#list + 1] = _G["ContainerFrame" .. i]
	end
	return list
end

function M:PickerGroups()
	return { { id = "backpack", title = "Bags", hint = "Click to choose the window's background and the empty slots' background.", sections = {
		{ key = "windowBackground", title = "Window Background", kind = "tile", choices = WINDOW_BACKGROUNDS },
		{ key = "itemBackground", title = "Item Background", kind = "tile", choices = LOOKS.backgrounds },
	} } }
end

-- The shown bag windows' rects (screen px), nil when none is shown
function M:BarOutline()
	if not active then
		return nil
	end
	local rects = {}
	for _, f in ipairs(BagWindows()) do
		if f and f:IsShown() then
			local ok, l, b, w, h = pcall(f.GetRect, f)
			if ok and l and w and not Secret(l) and not Secret(w) and w > 0 then
				local sc = f:GetEffectiveScale()
				rects[#rects + 1] = { l * sc, b * sc, (l + w) * sc, (b + h) * sc }
			end
		end
	end
	return #rects > 0 and rects or nil
end

function M:PickerStart()
	openedForPicker = false
	if active and not self:BarOutline() and OpenAllBags then
		OpenAllBags()
		openedForPicker = true
	end
end

function M:PickerStop()
	if openedForPicker and CloseAllBags then
		CloseAllBags()
	end
	openedForPicker = false
end

function M:OnEnable(db)
	self.db = db
	-- the page picture of the first Window Background is the concrete tile now
	if db.windowBackground == "page" then
		db.windowBackground = "concrete"
	end
	if ContainerFrameCombinedBags then
		Activate()
	end
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /bagdump [1-7|combined] [frames|reps]: a bag window's art. Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOBAGDUMP1 = "/bagdump"
SlashCmdList.MELLOBAGDUMP = function(msg)
	msg = (msg or ""):lower()
	local which, mode = msg:match("^(%w*)%s*(%a*)$")
	if which == "frames" or which == "reps" then
		which, mode = "", which
	end
	local frame = ContainerFrameCombinedBags
	if which ~= "" and which ~= "combined" then
		frame = _G["ContainerFrame" .. which]
	end
	MelloUI:ClearLog()
	if not frame then
		MelloUI:Print("%s: no such bag (1-7, combined)", which)
	else
		MelloUI:Print("== %s  %s L%d %s", frame:GetName() or "?", frame:GetFrameStrata(), frame:GetFrameLevel(), frame:IsShown() and "shown" or "hidden")
		Kit:DumpWindow(frame, skin, mode ~= "" and mode or nil)
	end
	MelloUI:ShowLog("bagdump " .. msg)
end
