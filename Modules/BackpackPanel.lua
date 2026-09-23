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
	defaults = { itemBorder = "thin", itemBackground = "stone", windowBackground = "concrete" },
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

-- The grid's pitch: the smallest gap between any two laid-out item
-- buttons on each axis (the pool hands its buttons over in no order; the
-- first two were often not neighbours, their gap was thrown out and the
-- pitch fell back to the button's own size — gems doubled on the first
-- open after a reload, user 2026-09-22). Else the button's own size.
local function ItemPitch(buttons)
	local a = buttons[1]
	local ok, w, h = pcall(a.GetSize, a)
	if not ok or Secret(w) or not (w and w > 0) then
		return nil
	end
	local lefts, tops = {}, {}
	for _, b in ipairs(buttons) do
		local okP, l, t = pcall(function() return b:GetLeft(), b:GetTop() end)
		if okP and l and t and not Secret(l) and not Secret(t) then
			lefts[#lefts + 1] = l
			tops[#tops + 1] = t
		end
	end
	local function SmallestGap(list, size)
		table.sort(list)
		local best = nil
		for i = 2, #list do
			local d = list[i] - list[i - 1]
			if d > 1 and d < size * 2 and (not best or d < best) then
				best = d
			end
		end
		return best
	end
	local pitch = { SmallestGap(lefts, w) or w, SmallestGap(tops, h) or h }
	-- a grid: the same spacing on both axes
	local pad = math.max(pitch[1] - w, pitch[2] - h, 0)
	return { w + pad, h + pad }
end

local function SkinItems(frame)
	local pool = frame.itemButtonPool
	if not pool then
		return
	end
	local buttons = {}
	for button in pool:EnumerateActive() do
		buttons[#buttons + 1] = button
	end
	if #buttons == 0 then
		return
	end
	local pitch = ItemPitch(buttons)
	for _, button in ipairs(buttons) do
		if button.melloRep == nil then
			local rep = Kit:SkinActionButton(button, Replace, pitch, { as = Kit:ButtonRimRule(),
				emptyStone = true, qualityBorder = button.IconBorder })
			if rep then
				skin.items[#skin.items + 1] = button
				Kit:SetButtonBackground(button, M.db and M.db.itemBackground or "stone")
			end
		elseif button.melloRep and button.melloRep.SetPitch and pitch then
			button.melloRep:SetPitch(pitch[1], pitch[2])
		end
		-- the combined bags' slot picture is the BUTTON's (made by the game
		-- when the button is set up for the combined bag, Initialize): faded,
		-- the Item Background stands in (a second background under it before)
		if button.ItemSlotBackground and not button.melloSlotBg then
			button.melloSlotBg = true
			Replace(button.ItemSlotBackground, { as = "BagSlotBackground" })
		end
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
	picture.inner:HookScript("OnSizeChanged", Retile)
	frame:HookScript("OnShow", Retile)
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
	if money and money.Border and money.Border.Middle then
		local rep = Replace(money.Border.Middle, { as = "common-coinbox-center", rect = money.Border, alsoFade = { money.Border.Left, money.Border.Right } })
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
	-- a beat after showing; SetPitch refits the rims already made
	local function Remeasure(delay)
		if C_Timer and C_Timer.After then
			C_Timer.After(delay, function()
				if active and frame:IsShown() then
					SkinItems(frame)
				end
			end)
		end
	end
	frame:HookScript("OnShow", function()
		Remeasure(0)
		Remeasure(0.3)
	end)
	frame:HookScript("OnSizeChanged", function()
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
				if C_Timer and C_Timer.After then
					C_Timer.After(0, function()
						if active and f:IsShown() then
							SkinItems(f)
						end
					end)
				end
				for _, rep in ipairs(skin.reps) do
					if rep.key == "common-coinbox-center" and rep.rect == (f.MoneyFrame and f.MoneyFrame.Border) and rep.onEnable then
						rep.onEnable()
					end
				end
				if f.ItemSlotBackground and not f.melloSlotBg then
					f.melloSlotBg = true
					Replace(f.ItemSlotBackground, { as = "BagSlotBackground" })
				end
			end
		end)
	end
	SkinItems(frame)
	if frame.ItemSlotBackground then
		frame.melloSlotBg = true
		Replace(frame.ItemSlotBackground, { as = "BagSlotBackground" })
	end
end

local function Build()
	if not skin then
		skin = { reps = {}, followers = {}, bags = {}, items = {}, windowBgs = {} }
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
		if key == "itemBorder" then
			Kit:SetButtonBorder(button, value)
		elseif key == "itemBackground" then
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
