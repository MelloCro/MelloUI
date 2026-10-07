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
--   next"), Item Border and Item Background chosen here or with pictures in
--   the Configurator, the icons filling them, empty slots on the
--   chosen background, the game's quality border kept on the icon (the rim untinted —
--   user, 2026-09-21), every item's quality gem in its slot's corner (Quality
--   Gems, Kit:ItemGem; user, 2026-09-26), a poor item's icon grey (Grey Out
--   Junk, 0.16.0), a special bag's rims in its bag type's colour (0.16.0,
--   TintSlot); the search box S1; the sort button on the cog; the
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
-- what the kit keeps beside the game's frames (Kit.lua: weak-keyed, never keys on them)
local pieceNameOf = MelloUI.Kept.pieceNameOf
local pieceOf = MelloUI.Kept.pieceOf
local repOf = MelloUI.Kept.repOf
local slotStoneOf = MelloUI.Kept.slotStoneOf

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

-- Quality Gems (user, 2026-09-26: "can we also add those tooltip gems onto
-- the items in the backpack themselves, to easy as a glance separate normal
-- items from Junk Items etc"): the one switch for the bags', the bank's and
-- the guild bank's slots, kept with the bags' looks those windows wear (the
-- Item Background, the Window Background); on the UI Modifications page
-- under the Bags row, so it is live while Bags is on (as the Item Background
-- is picked on the bag windows), while the bank and the guild bank follow it
-- either way. The gems themselves are the kit's slot path's (Kit:ItemGem),
-- which hears this switch on the bus.
local M = MelloUI:RegisterModule("BackpackPanel", {
	title = "Backpack Kit",
	desc = "The bag windows dressed in the painted kit on the game's own layout.",
	window = { label = "Bags", desc = "The backpack and bag windows in the kit.", tab = "Windows", order = 11,
		frames = { "ContainerFrameCombinedBags" }, plainGrab = true },
	enabledByDefault = true,
	defaults = { itemBackground = "stone", windowBackground = "concrete", qualityGems = true, greyJunk = true },
	options = {
		{ type = "dropdown", key = "windowBackground", name = "Window Background", values = WINDOW_BACKGROUNDS,
		  desc = "What the bag windows show behind the items (Bags by Kind's window too, and the bank): cracked concrete (the window's own), stone, iron plate, parchment, leather or dark." },
		{ type = "dropdown", key = "itemBackground", name = "Item Background", values = LOOKS.backgrounds,
		  desc = "What an empty bag slot shows inside its rim. Both are chosen with pictures on Windows > Bags. The slots' rim is the Button Border (Look > Borders, every window's)." },
		{ type = "toggle", key = "qualityGems", name = "Quality Gems",
		  desc = "A small gem in the top-left corner of every item in your bags, the bank and the guild bank, in the colour of the item's quality: grey for junk, white for common, then green, blue, purple and orange. Junk and better items stand out at a glance. While the game shows its own mark in that corner (the junk coin at a merchant, the upgrade arrow, the exclamation mark on an item that starts a quest, the quality badge on a crafting reagent), the gem moves to the top-right corner. One switch for all three windows." },
		{ type = "toggle", key = "greyJunk", name = "Grey Out Junk",
		  desc = "Junk (grey quality) items show grey in your bags, the bank and the guild bank, so they stand apart from what you keep. One switch for all three windows." },
	},
})

local skin = nil
local active = false

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret
local SafeCall = MelloUI.Safe.Call                -- obj:method() guarded (nil: none, raised or secret)
local SafeNumber = MelloUI.Safe.Number            -- a plain number, else nil

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
	if not ok or Secret(w) or Secret(h) or not (w and w > 0 and h and h > 0) then
		return nil
	end
	local n = 0
	for i = 1, count do
		local b = buttons[i]
		local okL, l = pcall(b.GetLeft, b)
		local okT, t = pcall(b.GetTop, b)
		-- (secret first: a secret is never tested for truth)
		if okL and okT and not Secret(l) and not Secret(t) and l and t then
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

-- The quality the game gave a slot before the kit dressed it, and whether
-- its item starts a quest: the bag's own record of the slot (the slot's
-- quality gem, Kit:ItemGem, starts from it; the game's own updates of the
-- slot keep it after). Read once per slot, at its first dress
local function SlotQuality(button)
	local bag, slot = SafeCall(button, "GetBagID"), SafeCall(button, "GetID")
	local C = C_Container
	if not (bag and slot and C and C.GetContainerItemInfo) then
		return nil
	end
	local info = C.GetContainerItemInfo(bag, slot)
	local quest = C.GetContainerItemQuestInfo and C.GetContainerItemQuestInfo(bag, slot)
	local id = type(quest) == "table" and SafeNumber(quest.questID) or nil
	local going = type(quest) == "table" and quest.isActive
	if Secret(going) then
		going = true   -- (unknown: not taken for a quest starter)
	end
	return type(info) == "table" and info.quality or nil, id ~= nil and not going
end

-- The kit's options for a slot, one table filled again for each (the kit
-- reads them while it skins the button and keeps none of them): a bag's
-- first open skins a hundred slots and more in one frame (/melloperf, user
-- 2026-09-24: 19.1 ms), nothing made per slot that the slot does not keep.
-- Every slot wears its item's quality gem (the switch is the kit's to read)
local slotOpts = { emptyStone = true, qualityGem = SlotQuality }

-- A slot just skinned: its Item Background. The stone the kit just made
-- already wears the default one (its tile, laid and shown): only another
-- choice is put on
local function NewSlotBackground(button)
	local value = M.db and M.db.itemBackground or "stone"
	local stone = slotStoneOf[button]
	local tex = stone and stone.tex
	if tex and pieceNameOf[tex] and pieceNameOf[tex] == LOOKS.backgroundPiece[value] then
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

-- A special bag's slots (a mining pack, an herb bag, a quiver ...) wear
-- their bag type's colour on the rim (user, 2026-09-30: "those slots usually
-- ... have a different color slot borders ... ours have the same color";
-- pick C of BuildData/output/bag_family_sketch, only the border): the rim
-- itself grey-toned and tinted with the bag type's colour
-- (MelloUI.Meaning.bagFamily; as the loot rolls' rims wear their quality),
-- and two copies of its own art added over it for the metal's light (the
-- kit's rims are dark iron, a mean grey of 0.2: tinted alone the colour went
-- near black; 2.5 times its light is the sketch's). The copies follow the
-- rim's art (its hover and press, the Button Border, Kit Colours: each comes
-- through the rim's SetTexture / SetTexCoord) and its show and hide. Made the
-- first time a slot sits in such a bag and kept with the rim, in tables of
-- this file's (nothing on the game's button); the rim back to its own look
-- in a normal bag and while the skin is off. The bag type read once per bag
-- per layout (the bag slots' own family, GetContainerNumFreeSlots).
local LIGHT = { 1, 0.5 }                             -- the copies' strengths (the rim's 1 + 1 + 0.5 = 2.5x)
local lights = setmetatable({}, { __mode = "k" })   -- [rim] = its light copies
local tinted = setmetatable({}, { __mode = "k" })   -- [rim] = true while it wears a bag type's colour
local familyOf = {}                                -- [bag ID] = its type's colour this layout (false: none)
local familyBits = nil                             -- the bag types, lowest bit first (listed at the first read)

local function FamilyBits()
	if not familyBits then
		familyBits = {}
		for bitValue in pairs(MelloUI.Meaning.bagFamily) do
			familyBits[#familyBits + 1] = bitValue
		end
		table.sort(familyBits)
	end
	return familyBits
end

local function BagColour(bag)
	if not bag or bag == 0 then
		return false   -- (the backpack itself: a normal bag)
	end
	local c = familyOf[bag]
	if c == nil then
		c = false
		local C = C_Container
		if C and C.GetContainerNumFreeSlots then
			local ok, _, family = pcall(C.GetContainerNumFreeSlots, bag)
			family = ok and SafeNumber(family) or nil
			if family and family > 0 then
				local bits = FamilyBits()
				for i = 1, #bits do
					local b = bits[i]
					if bit.band(family, b) ~= 0 then
						c = MelloUI.Meaning.bagFamily[b]
						break
					end
				end
			end
		end
		familyOf[bag] = c
	end
	return c
end

local function Lights_Shown(rim)
	local list = lights[rim]
	local on = (tinted[rim] and rim:IsShown()) and true or false
	for i = 1, #list do
		list[i]:SetShown(on)
	end
end
local function Lights_Texture(rim, ...)
	local list = lights[rim]
	for i = 1, #list do
		list[i]:SetTexture(...)
	end
end
local function Lights_TexCoord(rim, ...)
	local list = lights[rim]
	for i = 1, #list do
		list[i]:SetTexCoord(...)
	end
end

local function Untint(rim)
	tinted[rim] = nil
	rim:SetDesaturated(false)
	rim:SetVertexColor(1, 1, 1)
	Lights_Shown(rim)
end

local function TintSlot(button)
	local rep = repOf[button]
	local rim = rep and rep.object
	if not (rim and rim.owner and pieceNameOf[rim]) then
		return
	end
	local c = active and BagColour(SafeCall(button, "GetBagID")) or false
	if not c then
		if tinted[rim] then
			Untint(rim)
		end
		return
	end
	local list = lights[rim]
	if not list then
		list = {}
		local layer, sub = rim:GetDrawLayer()
		for i = 1, #LIGHT do
			-- (above the rim; beside its glow, which adds as these do)
			local t = rim.owner:CreateTexture(nil, layer or "OVERLAY", nil, math.min((sub or 0) + 1, 7))
			t:SetAllPoints(rim)
			Kit:Apply(t, pieceNameOf[rim])
			t:SetDesaturated(true)
			t:SetBlendMode("ADD")
			t:SetAlpha(LIGHT[i])
			t:Hide()
			list[i] = t
		end
		lights[rim] = list
		hooksecurefunc(rim, "SetTexture", Lights_Texture)
		hooksecurefunc(rim, "SetTexCoord", Lights_TexCoord)
		hooksecurefunc(rim, "Show", Lights_Shown)
		hooksecurefunc(rim, "Hide", Lights_Shown)
		hooksecurefunc(rim, "SetShown", Lights_Shown)
	end
	for i = 1, #list do
		list[i]:SetVertexColor(c[1], c[2], c[3])
	end
	tinted[rim] = true
	rim:SetDesaturated(true)
	rim:SetVertexColor(c[1], c[2], c[3])
	Lights_Shown(rim)
end

local slotBgFaded = setmetatable({}, { __mode = "k" })   -- [item button / bag frame] = true: its slot picture faded
-- The slots dressed: the kit's rim, the Item Background, the slot picture
-- faded, the bag type's colour. `pitch` is the grid's ({ x, y }; nil: the
-- button's own size). The game's bag windows' buttons (SkinItems) and the
-- bag window by kind's (M:DressSlots) alike: one dressing for every bag slot
local function DressButtons(buttons, count, pitch)
	local outer = not skinning
	skinning = true
	if outer then
		wipe(familyOf)   -- (a bag may have been swapped since the last layout)
	end
	local rimRule, plainFade = nil, nil
	for i = 1, count do
		local button = buttons[i]
		if repOf[button] == nil then
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
		elseif repOf[button] and repOf[button].SetPitch and pitch
			and not (SamePitch(pitchX[button], pitch[1]) and SamePitch(pitchY[button], pitch[2])) then
			-- re-laid on a new pitch only: the same pitch again (every open, the
			-- beat after it, the size changes) would re-anchor every rim and icon
			-- for nothing
			repOf[button]:SetPitch(pitch[1], pitch[2])
			pitchX[button], pitchY[button] = pitch[1], pitch[2]
		end
		-- the combined bags' slot picture is the BUTTON's (made by the game
		-- when the button is set up for the combined bag, Initialize): faded,
		-- the Item Background stands in (a second background under it before)
		if button.ItemSlotBackground and not slotBgFaded[button] then
			slotBgFaded[button] = true
			if plainFade == nil then
				plainFade = PlainSlotFade()
			end
			FadeSlotBackground(button.ItemSlotBackground, plainFade)
		end
		TintSlot(button)
	end
	if outer then
		skinning = false
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
	DressButtons(buttons, count, ItemPitch(buttons, count))
end

-- The bag window by kind (Modules/BagWindow.lua, 0.19.0) hands its item
-- buttons here (the game's ContainerFrameItemButtonTemplate, as the game's
-- bag windows' are): dressed by the same code while the kit is on, so the
-- two windows' slots never differ. `pitch`: its grid ({ x, y }). False while
-- the kit is off (the buttons keep the game's look; the window asks again on
-- its 'look:backpack').
function M:DressSlots(buttons, count, pitch)
	if not (active and skin) or count < 1 then
		return false
	end
	DressButtons(buttons, count, pitch)
	return true
end

-- The Window Background as saved, read whether this module is on or off (0.19.4, the options audit): the bag window
-- by kind lays it on its own page (Kit:OwnWindow's `background`), with the kit look as these windows do; the bags'
-- old first choice ('page') is the concrete now
function M:WindowBackground()
	local db = MelloUI.GetModuleDB and MelloUI:GetModuleDB("BackpackPanel")
	local value = db and db.windowBackground
	if type(value) ~= "string" or value == "page" then
		return "concrete"
	end
	return value
end

-- A window's background choice: `alt` (a tile on the window's background
-- rect, in its layer) stands in for the window's own, which is see-through
-- meanwhile; the window's own piece is that background itself. One surface
-- either way.
local function ApplyWindowBackground(entry)
	local value = M.db and M.db.windowBackground or "concrete"
	local pic, alt = entry.rep.tex, entry.alt
	local piece = LOOKS.backgroundPiece[value]
	if not active or piece == pieceNameOf[pic] or not (piece or value == "dark") then
		alt:Hide()
		pic:SetAlpha(1)
		return
	end
	if piece then
		if pieceNameOf[alt] ~= piece then
			Kit:Unpaint(alt)   -- (the dark fill's palette colour no longer on it)
			alt:SetVertexColor(1, 1, 1, 1)
			Kit:Apply(alt, piece)
		end
		Kit:Retile(alt)
	else
		-- Dark: the palette's inner panel, by its key (a new palette paints
		-- it again), as the kit's own dark background (Kit:SetButtonBackground)
		Kit:Paint(alt, "innerPanel", "fill", 0.95)
		pieceNameOf[alt] = nil
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
	pieceOf[alt] = true   -- ours: never faded
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
		if alt:IsShown() and pieceNameOf[alt] then
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
				if f.ItemSlotBackground and not slotBgFaded[f] then
					slotBgFaded[f] = true
					FadeSlotBackground(f.ItemSlotBackground)
				end
			end
		end)
	end
	SkinItems(frame)
	if frame.ItemSlotBackground then
		slotBgFaded[frame] = true
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
	if sort and sort.GetNormalTexture and sort:GetNormalTexture() and repOf[sort] == nil then
		repOf[sort] = Replace(sort:GetNormalTexture(), { as = "bags-button-autosort-up", button = sort, noFade = true }) or false
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
	for rim in pairs(tinted) do
		Untint(rim)
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
-- For the Configurator's picture rows (PickerGroups, Core/Config.lua): the
-- bag windows are one group.
--------------------------------------------------------------------------------

function M:PickerGroups()
	return { { id = "backpack", title = "Bags", sections = {
		{ key = "windowBackground", title = "Window Background", kind = "tile", choices = WINDOW_BACKGROUNDS },
		{ key = "itemBackground", title = "Item Background", kind = "tile", choices = LOOKS.backgrounds },
	} } }
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

-- What this module keeps beside the game's frames (hard rule 1: weak-keyed
-- tables, never keys on the frames), for the dumps and the tests: read only
M.kept = { slotBgFaded = slotBgFaded }
