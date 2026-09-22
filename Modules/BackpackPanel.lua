--------------------------------------------------------------------------------
-- MelloUI - Backpack Panel
--
-- The bag windows (ContainerFrameCombinedBags and ContainerFrame1..7, the
-- flat portrait windows) dressed in the painted kit (Modules/Kit.lua) on the
-- game's own layout, by the rule book's fixed looks and the user's pick
-- (kit_raw/bag_catalog.png, 2026-09-21: B2):
--   the window shell (outer rail, one page stone inside it, the ring on the
--   bag icon with the icon at the medallion size on the dark disc, the title
--   plate on the rail, the close button); the pooled item buttons as R1 rims
--   sized to the grid's pitch with the icons filling them, empty slots on
--   stone, the game's quality border kept on the icon (the rim untinted —
--   user, 2026-09-21); the search box S1; the sort button on the cog; the
--   money strip on the header plate (B2), its frame raised above the rims.
-- The item buttons are re-acquired and re-laid by the game on every open
-- (UpdateItemLayout): skinned from that post-hook. Covers the Dark Mode
-- group "backpack". /bagdump [1-7|combined] [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("BackpackPanel", {
	title = "Backpack Kit",
	desc = "The bag windows dressed in the painted kit on the game's own layout.",
	enabledByDefault = true,
	defaults = {},
	options = {},
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
			Kit:SkinActionButton(button, Replace, pitch, { emptyStone = true, qualityBorder = button.IconBorder })
		elseif button.melloRep and button.melloRep.SetPitch and pitch then
			button.melloRep:SetPitch(pitch[1], pitch[2])
		end
	end
end

local function SkinBag(frame)
	if not frame or skin.bags[frame] then
		return
	end
	skin.bags[frame] = true
	local portrait = frame.PortraitContainer and frame.PortraitContainer.portrait
	local ring = Kit:SkinWindowShell(frame, Replace, skin, { portrait = portrait, bg = "UI-Background-Rock" })
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
		skin = { reps = {}, followers = {}, bags = {} }
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

function M:OnEnable(db)
	self.db = db
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
