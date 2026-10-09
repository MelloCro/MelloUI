--------------------------------------------------------------------------------
-- MelloUI - Cooldown Tweaks: the game's Cooldown Manager made to read better
-- (0.19.8; the addon study's item 7, "all as recommended", 2026-10-06)
--
-- On the game's own viewers (Essential, Utility, Buff icons; Blizzard_
-- CooldownViewer, loaded with the game), never a copy of them:
--   Centre Rows        a row shorter than the others centred under them, in
--                      the way the grid grows (a post-hook of each viewer's
--                      Layout: it runs when the icons change, not each frame;
--                      a point is written only when it differs)
--   Key Bindings       the key of the action button that holds an icon's
--                      spell, on the icon's corner in the buttons' own font
--   Light While Pressed  the icon lights with the button whose spell it shows
--                      (Action Buttons' light and its "actionpress" on the bus:
--                      one light, one look)
--   Count Size         the charges' and stacks' numbers larger or smaller
--   and its rim: Look > Borders' Cooldown Manager Border (Modules/KitBorders.lua)
-- The game already has ready alerts (sound and a visual on each spell) and
-- hiding a spell in its own Cooldown Manager settings: not made again here.
-- Nothing is written on the game's frames as a key (side tables); every value
-- read secret-safe -- the Cooldown Manager is the game's secret-aware part: a
-- point, a size or a spell that reads secret is left as the game has it.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("CooldownTweaks")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit

local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Plain = MelloUI.Safe.Value

local M = MelloUI:RegisterModule("CooldownTweaks", {
	title = "Cooldown Manager Tweaks",
	desc = "Centred rows, key bindings, a light while pressed and the count size on the game's Cooldown Manager.",
	icon = "Interface\\Icons\\Spell_Holy_BorrowedTime",
	flavour = "Your cooldowns, in the middle, with their keys on them.",
	role = "adds",
	-- (not on the installer's Features step: its rows are on Bars & Meters > Cooldown Manager)
	installer = false,
	enabledByDefault = true,
	defaults = {
		centreRows = true,
		keybinds = true,
		pressLight = true,
		countSize = 100,
	},
	options = {
		{ type = "toggle", key = "centreRows", name = "Centre Rows",
		  desc = "A row with fewer icons than the others sits centred under them, so the icons grow from the middle. "
			.. "The essential and utility cooldowns and the buff icons." },
		{ type = "toggle", key = "keybinds", name = "Key Bindings",
		  desc = "The key of the action button that holds a cooldown's spell, on the icon's corner." },
		{ type = "toggle", key = "pressLight", name = "Light While Pressed",
		  desc = "A cooldown's icon lights up while you press the action button with its spell, as the button does "
			.. "(Action Buttons)." },
		{ type = "slider", key = "countSize", name = "Count Size", min = 70, max = 160, step = 5,
		  format = function(v) return math.floor(v + 0.5) .. "%" end,
		  desc = "The size of the charges and stacks numbers on the icons." },
	},
})

local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local GRID = { EssentialCooldownViewer = true, UtilityCooldownViewer = true, BuffIconCooldownViewer = true }
local SPELLS = { EssentialCooldownViewer = true, UtilityCooldownViewer = true }   -- (the buff icons are auras: no key)
local BEVEL = "UI-HUD-CoolDownManager-IconOverlay"

local hooked = setmetatable({}, { __mode = "k" })      -- [viewer] = true
local shifted = setmetatable({}, { __mode = "k" })     -- [item] = { x, y }: the point Centre Rows wrote
local keyText = setmetatable({}, { __mode = "k" })     -- [item] = its key's font string
local baseFont = setmetatable({}, { __mode = "k" })    -- [font string] = { font, size, flags } as the game set it
local bevels = setmetatable({}, { __mode = "k" })      -- [item] = { its bevel regions } (looked for once)
local lit = setmetatable({}, { __mode = "k" })         -- [item] = true while lit by a press

local function Call(obj, method, ...)
	local fn = obj and obj[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e = pcall(fn, obj, ...)
	if not ok then
		return nil
	end
	return a, b, c, d, e
end

local function Items(viewer)
	local pool = viewer and viewer.itemFramePool
	if not pool or type(pool.EnumerateActive) ~= "function" then
		return function() return nil end
	end
	return pool:EnumerateActive()
end

-- an item's spells: its spell and its base spell (an override shows the one, the button may hold the other)
local function SpellsOf(item)
	local a = Num(Call(item, "GetSpellID"))
	local b = Num(Call(item, "GetBaseSpellID"))
	return a, b
end

--------------------------------------------------------------------------------
-- Centre Rows: the last row (the only one a grid leaves short) moved by half
-- of what it lacks, in the way the grid grows
--------------------------------------------------------------------------------
local order = {}   -- (the laid-out items in their order: reused)
local function ByIndex(a, b)
	return (Num(a.layoutIndex) or 0) < (Num(b.layoutIndex) or 0)
end

local function Centre(viewer)
	wipe(order)
	for item in Items(viewer) do
		if Plain(Call(item, "IsShown")) and Num(item.layoutIndex) then
			order[#order + 1] = item
		end
	end
	local n, stride = #order, Num(viewer.stride)
	if not stride or stride < 1 or n <= stride then
		return   -- (one row: the viewer is as wide as it, nothing to centre)
	end
	table.sort(order, ByIndex)
	local short = n % stride
	if short == 0 then
		return
	end
	local w, h = Num(Call(order[1], "GetWidth")), Num(Call(order[1], "GetHeight"))
	local gx, gy = Num(viewer.childXPadding) or 0, Num(viewer.childYPadding) or 0
	if not (w and h) then
		return
	end
	local dx, dy = 0, 0
	if Plain(viewer.isHorizontal) then
		dx = (stride - short) * (w + gx) / 2 * (Plain(viewer.layoutFramesGoingRight) and 1 or -1)
	else
		dy = (stride - short) * (h + gy) / 2 * (Plain(viewer.layoutFramesGoingUp) and 1 or -1)
	end
	for i = n - short + 1, n do
		local item = order[i]
		local point, rel, relPoint, x, y = Call(item, "GetPoint", 1)
		x, y = Num(x), Num(y)
		if point and x and y and not Secret(rel) then
			local done = shifted[item]
			-- (the game's Layout put it back: moved again; already where it was moved to: left)
			if not (done and done[1] == x and done[2] == y) then
				local tx, ty = x + dx, y + dy
				item:SetPoint(point, rel, relPoint, tx, ty)
				shifted[item] = done or {}
				-- (where it was moved to, and from: Uncentre puts it back)
				shifted[item][1], shifted[item][2], shifted[item][3], shifted[item][4] = tx, ty, x, y
			end
		end
	end
end

-- Centre Rows off (or the module): each icon it moved put back where it took
-- it from, while it still stands where it was moved to (else the game's own
-- layout has placed it since: left as it is)
local function Uncentre(viewer)
	for item in Items(viewer) do
		local done = shifted[item]
		if done then
			shifted[item] = nil
			local point, rel, relPoint, x, y = Call(item, "GetPoint", 1)
			x, y = Num(x), Num(y)
			if point and x == done[1] and y == done[2] and done[3] and not Secret(rel) then
				item:SetPoint(point, rel, relPoint, done[3], done[4])
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Key Bindings: the action slots that hold the spell (C_ActionBar), their
-- buttons' key as the buttons show it (each button's HotKey: the game's own
-- short form)
--------------------------------------------------------------------------------
local slotButton = {}   -- [action slot] = a button that shows it (made again as the bars change)
local slotsDirty = true

local function MapSlots()
	wipe(slotButton)
	local AB = MelloUI:GetModule("ActionButtons")
	for _, button in ipairs(AB and AB.Buttons and AB.Buttons() or {}) do
		local slot = Num(button.action)
		if slot and slotButton[slot] == nil then
			slotButton[slot] = button
		end
	end
	slotsDirty = false
end

local function KeyOf(spell)
	if not spell or not (C_ActionBar and C_ActionBar.FindSpellActionButtons) then
		return nil
	end
	if slotsDirty then
		MapSlots()
	end
	local ok, slots = pcall(C_ActionBar.FindSpellActionButtons, spell)
	if not ok or type(slots) ~= "table" then
		return nil
	end
	for _, slot in ipairs(slots) do
		local button = slotButton[Num(slot) or -1]
		local hot = button and button.HotKey
		local text = hot and Plain(Call(hot, "GetText"))
		if type(text) == "string" and text ~= "" and text ~= (RANGE_INDICATOR or "\226\128\162") then
			return text, hot
		end
	end
	return nil
end

local function ShowKey(item, on)
	local fs = keyText[item]
	if not on then
		if fs then
			fs:Hide()
		end
		return
	end
	local a, b = SpellsOf(item)
	local text, hot = KeyOf(a)
	if not text and b and b ~= a then
		text, hot = KeyOf(b)
	end
	if not text then
		if fs then
			fs:Hide()
		end
		return
	end
	if not fs then
		fs = item:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
		fs:SetPoint("TOPRIGHT", item, "TOPRIGHT", -2, -2)
		fs:SetJustifyH("RIGHT")
		keyText[item] = fs
	end
	local font = hot and Call(hot, "GetFontObject")
	if font and fs:GetFontObject() ~= font then
		fs:SetFontObject(font)
	end
	if fs:GetText() ~= text then
		fs:SetText(text)
	end
	fs:Show()
end

--------------------------------------------------------------------------------
-- Count Size: the charges' and the stacks' numbers, from the size the game gave
--------------------------------------------------------------------------------
local function Size(fs, scale)
	if not fs then
		return
	end
	local base = baseFont[fs]
	if not base then
		local font, size, flags = Call(fs, "GetFont")
		size = Num(size)
		if not (font and size) then
			return
		end
		base = { font, size, flags }
		baseFont[fs] = base
	end
	local want = base[2] * scale
	local _, now = Call(fs, "GetFont")
	if Num(now) ~= want then
		fs:SetFont(base[1], want, base[3])
	end
end

local function CountSize(item, scale)
	Size(item.ChargeCount and item.ChargeCount.Current, scale)
	Size(item.Applications and item.Applications.Applications, scale)
	if item.Icon and item.Icon.Applications and item.Icon.Applications.GetFont then
		Size(item.Icon.Applications, scale)   -- (a buff bar's: its count on its icon)
	end
end

--------------------------------------------------------------------------------
-- The bevels (Look > Borders' Cooldown Manager Border, Modules/KitBorders.lua)
--------------------------------------------------------------------------------
local function BevelsOf(item)
	local list = bevels[item]
	if list then
		return list
	end
	list = {}
	for i = 1, select("#", item:GetRegions()) do
		local r = select(i, item:GetRegions())
		local atlas = Call(r, "GetAtlas")
		if not Secret(atlas) and atlas == BEVEL then
			list[#list + 1] = r
		end
	end
	bevels[item] = list
	return list
end

--------------------------------------------------------------------------------
-- One viewer as its icons are now
--------------------------------------------------------------------------------
local function Dress(viewer)
	if not (M.isEnabled and M.db) then
		return
	end
	local name = viewer.GetName and viewer:GetName()
	local scale = (Num(M.db.countSize) or 100) / 100
	for item in Items(viewer) do
		CountSize(item, scale)
		if SPELLS[name] then
			ShowKey(item, M.db.keybinds)
		end
		if GRID[name] and item.Icon and item.Icon.GetObjectType and Kit.CooldownIconBorder then
			Kit:CooldownIconBorder(item, item.Icon, BevelsOf(item))
		end
	end
	if GRID[name] and M.db.centreRows then
		Centre(viewer)
	end
end

local OnLayout = Perf.Shared("Layout on a Cooldown Manager viewer", function(viewer)
	Dress(viewer)
end)

local function Each(fn)
	for _, name in ipairs(VIEWERS) do
		local viewer = rawget(_G, name)
		if viewer then
			fn(viewer, name)
		end
	end
end

local function HookAll()
	Each(function(viewer)
		if not hooked[viewer] and type(viewer.Layout) == "function" then
			hooked[viewer] = true
			hooksecurefunc(viewer, "Layout", OnLayout)
		end
	end)
end

-- every viewer dressed again as its icons stand, Centre Rows off its moves
-- put back. Never the game's own refresh or layout: run from here, it writes
-- its data and caches tainted, and the game's next read of a secret aura
-- fails (0.19.8, the user's Cooldown Manager errors; hard rule 1)
local function Relayout()
	Each(function(viewer)
		if not (M.isEnabled and M.db and M.db.centreRows) then
			Uncentre(viewer)
		end
		Dress(viewer)
	end)
end

--------------------------------------------------------------------------------
-- Light While Pressed: an action button pressed lights the icons of its spell
--------------------------------------------------------------------------------
local function ActionSpell(button)
	local slot = Num(button and button.action)
	if not slot then
		return nil
	end
	local ok, kind, id = pcall(GetActionInfo, slot)
	kind, id = ok and Plain(kind) or nil, ok and Num(id) or nil
	if kind == "spell" then
		return id
	elseif kind == "macro" and id and GetMacroSpell then
		local okM, spell = pcall(GetMacroSpell, id)
		return okM and Num(spell) or nil
	end
	return nil
end

local OnPress = Perf.Shared("actionpress on the bus: the Cooldown Manager's light", function(button, down)
	if not (M.isEnabled and M.db and M.db.pressLight) then
		return
	end
	local AB = MelloUI:GetModule("ActionButtons")
	if not (AB and AB.Light) then
		return
	end
	local spell = down and ActionSpell(button)
	Each(function(viewer, name)
		if SPELLS[name] then
			for item in Items(viewer) do
				local a, b = SpellsOf(item)
				local on = spell ~= nil and (a == spell or b == spell)
				if on or lit[item] then
					lit[item] = on or nil
					AB:Light(item, on)
				end
			end
		end
	end)
end)

--------------------------------------------------------------------------------
-- Events: the bars' slots and keys changed (the labels again)
--------------------------------------------------------------------------------
local frame
local OnEvent = Perf.Shared("Cooldown Tweaks' events", function()
	slotsDirty = true
	Each(function(viewer, name)
		if SPELLS[name] then
			for item in Items(viewer) do
				ShowKey(item, M.db and M.db.keybinds)
			end
		end
	end)
end, "script")

function M:OnEnable(db)
	self.db = db
	HookAll()
	if not frame then
		frame = CreateFrame("Frame")
		Perf.SetScript(frame, "OnEvent", OnEvent)
	end
	frame:RegisterEvent("UPDATE_BINDINGS")
	frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	frame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
	MelloUI:On("actionpress", OnPress, "Cooldown Tweaks' light")
	Relayout()
end

function M:OnDisable()
	if frame then
		frame:UnregisterAllEvents()
	end
	-- (the game's own look back: the icons Centre Rows moved put back, its fonts, its bevels; the keys and lights away)
	for fs, base in pairs(baseFont) do
		fs:SetFont(base[1], base[2], base[3])
	end
	for _, fs in pairs(keyText) do
		fs:Hide()
	end
	local AB = MelloUI:GetModule("ActionButtons")
	for item in pairs(lit) do
		if AB and AB.Light then
			AB:Light(item, false)
		end
		lit[item] = nil
	end
	if Kit.CooldownBordersOff then
		Kit:CooldownBordersOff()
	end
	Each(Uncentre)
	wipe(shifted)
end

function M:OnSettingChanged()
	Relayout()
end

-- (for its test)
M.Centre, M.KeyOf, M.Dress = Centre, KeyOf, Dress
