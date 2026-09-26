--------------------------------------------------------------------------------
-- MelloUI - Buffs & Debuffs
--
-- MelloUI's own buff and debuff rows (user, 2026-09-23: "both, 5 then 4" --
-- the target frame, enemy nameplates and your own buffs), drawn by the
-- game's AuraContainer: MelloUI names the unit and the kind of aura and
-- styles each button once, the game fills and updates the rows itself. No
-- aura is ever read here, so the rows keep working in combat, when the
-- game hides aura data from addons (/mello auras on this client,
-- 2026-09-23: the whole container API is there; a dispel border goes
-- through AddDispelTypeTexture).
--
--   * your buffs: buffs, then debuffs on their own row, where the game's
--     buff bar stands, or beside the column under the minimap (Attach To
--     The Minimap Column, below); right-click cancels a buff; temporary
--     weapon enchants too. The game's buff and debuff bars are hidden with
--     the game's own visibility driver (out of combat only) and come back
--     while Edit Mode is open, so they can still be moved there.
--   * target: debuffs, then buffs, in the game's own aura place under the
--     target frame. The game's row is made invisible, not hidden, so the
--     target frame's layout (the cast bar under the auras) stays the game's.
--   * enemy nameplates: your debuffs, with the plate's own debuff filter, in
--     the place of the game's debuff row (invisible, still laid out, so the
--     Nameplates module's crowd-control icon keeps its place above it).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Auras")
local hooksecurefunc = Perf.hooksecurefunc

local M = MelloUI:RegisterModule("Auras", {
	title = "Buffs & Debuffs",
	desc = "Your own buff and debuff rows on the target frame, enemy nameplates and at your buffs, drawn by the game so they keep working in combat.",
	icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
	flavour = "Buffs and debuffs in rows of your own, drawn by the game itself, so they never go dark in a fight.",
	role = "replaces",
	tweak = { label = "Buffs & Debuffs", desc = "MelloUI's own rows of buffs and debuffs: yours in place of the game's buff bar, the target's under its frame, your debuffs on enemy nameplates.", order = 1, off = true },
	enabledByDefault = false,
	defaults = {
		player = true,
		playerSize = 30,
		playerPerRow = 12,
		playerColumn = true,
		target = true,
		targetSize = 22,
		targetOnlyMine = false,
		nameplates = true,
		nameplateSize = 20,
	},
	options = {
		{ type = "header", name = "Your Buffs" },
		{ type = "toggle", key = "player", name = "Your Buffs And Debuffs",
		  desc = "Your buffs, then your debuffs on a row of their own. Right-click a buff to cancel it. Beside the minimap, or where the game's buff bar is: that bar comes back while Edit Mode is open, so it can still be moved, and these follow it." },
		{ type = "toggle", key = "playerColumn", parent = "player", name = "Attach To The Minimap Column",
		  desc = "Your buffs in a line beside the minimap, level with the map's top and growing away from it, your debuffs on the line under them. They follow the minimap when it moves or changes size. Needs the Minimap Kit; off, they stand where the game's buff bar is." },
		{ type = "slider", key = "playerSize", parent = "player", name = "Icon Size", min = 20, max = 48, step = 1 },
		{ type = "slider", key = "playerPerRow", parent = "player", name = "Icons Per Row", min = 6, max = 20, step = 1 },
		{ type = "header", name = "Target" },
		{ type = "toggle", key = "target", name = "Target Frame",
		  desc = "Your target's debuffs, then its buffs, under the target frame, in place of the game's." },
		{ type = "slider", key = "targetSize", parent = "target", name = "Icon Size", min = 14, max = 36, step = 1 },
		{ type = "toggle", key = "targetOnlyMine", parent = "target", name = "Only My Debuffs",
		  desc = "On the target, show only the debuffs you put on it." },
		{ type = "header", name = "Nameplates" },
		{ type = "toggle", key = "nameplates", name = "Enemy Nameplates",
		  desc = "Your debuffs on enemy nameplates, in place of the game's row. Crowd control stays with the game (and the Nameplates module)." },
		{ type = "slider", key = "nameplateSize", parent = "nameplates", name = "Icon Size", min = 12, max = 32, step = 1 },
	},
})

local function Try(fn, ...)
	local ok = pcall(fn, ...)
	return ok
end

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

local function Available()
	return AnchorUtil and AnchorUtil.FlowLayoutAxis and AuraContainerSortMethod and AuraContainerSortDirection
		and pcall(CreateFrame, "AuraContainer", nil, nil, "CustomAuraContainerTemplate")
end

--------------------------------------------------------------------------------
-- Buttons: set up once, when the container makes each one
--------------------------------------------------------------------------------

-- The texts sized to the icon (user, 2026-09-23: the game's number font at
-- its own size dwarfed a 20 px nameplate icon): the time a little under half
-- the icon, the stacks a little smaller, the game's number face, outlined
local texts = setmetatable({}, { __mode = "k" })   -- [button] = { time, count }

local function SizeTexts(button, size)
	local t = texts[button]
	if not t then
		return
	end
	local face = NumberFontNormal and NumberFontNormal.GetFont and NumberFontNormal:GetFont() or "Fonts\\ARIALN.TTF"
	local below = t.below
	Try(t.time.SetFont, t.time, face, math.max(8, math.floor((below and 11 or size * 0.46) + 0.5)), "OUTLINE")
	Try(t.count.SetFont, t.count, face, math.max(8, math.floor(size * 0.4 + 0.5)), "OUTLINE")
end

-- Aura Border (user, 2026-09-23: one border per kind for every window, UI
-- Modifications' Aura Border): the plain black edge the buttons had, or a
-- thin rim the buttons wear round the icon (its edge 2 px under the rim's
-- inner edge, as the side tabs'), the debuff colour above it at the icon's
-- edge. Every button made is kept, so a new choice reaches all of them.
local function AuraLook()
	local Kit = MelloUI.Kit
	return Kit and Kit.BorderValue and Kit:BorderValue("aura") or "black"
end

local function ApplyAuraLook(button)
	local t = texts[button]
	local Kit = MelloUI.Kit
	if not (t and Kit and Kit.Slot) then
		return
	end
	local look = AuraLook()
	local kind = Kit.buttonLooks and Kit.buttonLooks.rimKind[look]
	if not kind then
		if t.rim then
			t.rim:Hide()
		end
		t.edge:Show()
		return
	end
	local base = "buttons/" .. kind
	-- a plain texture in the look's normal state: the aura buttons are the
	-- game's protected buttons, whose scripts may not be hooked (Kit:Slot
	-- follows the button's hover and press through HookScript: "Cannot
	-- assign script handler for 'onenter' (cannot replace a forbidden script
	-- handler)", user 2026-09-23, and the rest of the button's set-up was
	-- lost with it), so the rim does not light on hover
	if not t.rim then
		t.rim = button:CreateTexture(nil, "OVERLAY", nil, 3)
		t.rim.kitScale = Kit.scale
	end
	if t.rim.kitName ~= base .. "_normal" then
		Kit:Apply(t.rim, base .. "_normal")
	end
	local p = Kit:Piece(base .. "_normal")
	local l, r = Kit:Insets(base .. "_normal", 1)
	local share = (p and l) and (p.w - l - r) / p.w or 0.8
	t.rim:ClearAllPoints()
	t.rim:SetPoint("CENTER", button, "CENTER")
	local side = (t.size - 4) / share
	t.rim:SetSize(side, side)
	t.rim:Show()
	t.edge:Hide()
end

-- o: size, swipe (a cooldown spiral), durationBelow (the time under the
-- icon, else in its middle), dispel (a dispel-coloured border on debuffs),
-- cancel (right-click cancels), tooltip (anchor)
local function InitButton(button, o)
	Try(button.SetSize, button, o.size, o.size)
	local edge = button:CreateTexture(nil, "BACKGROUND")
	edge:SetPoint("TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(0, 0, 0, 0.9)
	local icon = button:CreateTexture(nil, "BORDER")
	icon:SetAllPoints(button)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	Try(button.SetIcon, button, icon)
	local cooldown
	if o.swipe then
		cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		cooldown:SetAllPoints(button)
		Try(cooldown.SetDrawEdge, cooldown, false)
		-- the time is the row's own text: no second countdown on the swirl,
		-- neither the game's numbers nor Cooldown Timers' (its opt-out mark)
		Try(cooldown.SetHideCountdownNumbers, cooldown, true)
		cooldown.noCooldownCount = true
		Try(button.SetDurationCooldown, button, cooldown)
	end
	-- the texts above the spiral
	local layer = CreateFrame("Frame", nil, button)
	layer:SetAllPoints(button)
	layer:SetFrameLevel((cooldown or button):GetFrameLevel() + 2)
	local count = layer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -1)
	Try(button.SetApplicationCount, button, count, {})
	local time = layer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	if o.durationBelow then
		time:SetPoint("TOP", button, "BOTTOM", 0, -2)
	else
		time:SetPoint("CENTER", button, "CENTER", 0, 0)
	end
	Try(button.SetDurationText, button, time, {})
	texts[button] = { time = time, count = count, below = o.durationBelow, edge = edge, size = o.size }
	SizeTexts(button, o.size)
	ApplyAuraLook(button)
	if o.dispel and button.AddDispelTypeTexture then
		local border = button:CreateTexture(nil, "OVERLAY", nil, 5)   -- above an Aura Border rim
		border:SetPoint("TOPLEFT", -1, 1)
		border:SetPoint("BOTTOMRIGHT", 1, -1)
		local style = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
		Try(button.AddDispelTypeTexture, button, border, {
			style = style and style.Border,
			showWhenHarmful = true,
			showWhenHelpful = false,
		})
	end
	if o.cancel then
		Try(button.SetCancelAuraButtons, button, "RightButtonUp")
	end
	Try(button.SetTooltipAnchorPoint, button, o.tooltip or "ANCHOR_BOTTOMLEFT", 0, 0)
end

-- A container on `parent` for `unit`, its groups { key, filter, max } in order,
-- each on a line of its own; o: the button look and the flow (anchor, gx, gy,
-- line = the longest line, spacing)
if MelloUI.Kit and MelloUI.Kit.OnBorderChanged then
	MelloUI.Kit:OnBorderChanged("aura", function()
		for button in pairs(texts) do
			ApplyAuraLook(button)
		end
	end)
end

local function NewContainer(parent, unit, groups, o)
	local c = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	c:SetSize(1, 1)
	c:SetFlowLayoutAnchorPoint(o.anchor)
	c:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
	c:SetFlowLayoutMaximumLineSize(o.line)
	c:SetFlowLayoutGrowthDirection(o.gx, o.gy)
	c:SetFlowLayoutPadding(0, 0, 0, 0)
	c.melloGroups = {}
	for _, g in ipairs(groups) do
		c:AddAuraGroup(g.key, g.filter, {
			maxFrameCount = g.max,
			sortMethod = AuraContainerSortMethod.Default,
			sortDirection = AuraContainerSortDirection.Normal,
			layout = {
				elementSpacing = o.spacing,
				lineSpacing = o.lineSpacing or o.spacing,
				groupSpacing = o.spacing,
				groupLineSpacing = o.lineSpacing or o.spacing,
				forceNewLine = true,
			},
			initializeFrame = function(button)
				InitButton(button, o)
			end,
		})
		c.melloGroups[#c.melloGroups + 1] = g.key
	end
	c.melloLook = o
	if unit then
		c:SetUnit(unit)
	end
	return c
end

-- A size setting changed: every button the container has made so far
local function Resize(c, size, line)
	if not c then
		return
	end
	c.melloLook.size = size
	if line then
		Try(c.SetFlowLayoutMaximumLineSize, c, line)
	end
	for _, key in ipairs(c.melloGroups) do
		local ok, n = pcall(c.GetAuraGroupFrameCount, c, key)
		for i = 1, (ok and not Secret(n) and n) or 0 do
			local okF, b = pcall(c.GetAuraGroupFrame, c, key, i)
			if okF and b then
				Try(b.SetSize, b, size, size)
				SizeTexts(b, size)
				if texts[b] then
					texts[b].size = size
					ApplyAuraLook(b)   -- the rim round the new size
				end
			end
		end
	end
	Try(c.UpdateAllAuras, c)
end

--------------------------------------------------------------------------------
-- The game's own rows: invisible (alpha), kept so while we show ours
--------------------------------------------------------------------------------

local veiled = setmetatable({}, { __mode = "k" })
local veilHooked = setmetatable({}, { __mode = "k" })

local function Veil(frame, on)
	if not frame then
		return
	end
	if on then
		veiled[frame] = true
		if not veilHooked[frame] then
			veilHooked[frame] = true
			hooksecurefunc(frame, "SetAlpha", function(f, a)
				if veiled[f] and a ~= 0 then
					f:SetAlpha(0)
				end
			end)
		end
		frame:SetAlpha(0)
	elseif veiled[frame] then
		veiled[frame] = nil
		frame:SetAlpha(1)
	end
end

--------------------------------------------------------------------------------
-- Your buffs
--------------------------------------------------------------------------------

local playerRows
local gameBarsHidden = false
local pendingBars = nil
local inEditMode = false
local combatWatcher = CreateFrame("Frame")

local function GameBars(hide)
	if gameBarsHidden == hide then
		return
	end
	if InCombatLockdown() then
		pendingBars = hide
		combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	pendingBars = nil
	for _, f in ipairs({ BuffFrame, DebuffFrame }) do
		if f then
			if hide then
				RegisterStateDriver(f, "visibility", "hide")
			else
				RegisterStateDriver(f, "visibility", "show")
				UnregisterStateDriver(f, "visibility")
			end
			Veil(f, hide)
		end
	end
	gameBarsHidden = hide
end

Perf.SetScript(combatWatcher, "OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if pendingBars ~= nil then
		GameBars(pendingBars)
	end
end)

local function PlayerLine()
	return (M.db.playerSize + 6) * M.db.playerPerRow
end

local function ItemEnchantments(c)
	local slots = AuraContainerItemEnchantmentSlot
	if type(slots) ~= "table" or not c.AddItemEnchantment then
		return
	end
	for _, slot in pairs(slots) do
		Try(c.AddItemEnchantment, c, slot, {
			hidePermanent = true,
			initializeFrame = function(button)
				InitButton(button, c.melloLook)
			end,
		})
	end
end

--------------------------------------------------------------------------------
-- Attach To The Minimap Column (the minimap column's layout E, user,
-- 2026-09-25: "the buffs lined up left of the map's top edge, growing
-- leftwards, debuffs on a line under them"). The rows' top corner stands
-- ATTACH_GAP UI units beside the column under the minimap, level with the
-- map's top: left of it, growing leftwards; right of it, growing rightwards,
-- when the column stands in the screen's left half, so they never run off
-- the screen. The column is MinimapPanel's contract (M:ColumnPart("frame"):
-- the painted frame's outer left and right edges on the screen, the round
-- ring's rim or the square border, whatever the map's size; the rows' end
-- icon clear of the rim), and the rows follow it on the bus's 'column'. The
-- place is read on the screen and set against UIParent, never anchored to
-- the game's minimap (nothing of ours hangs from an Edit Mode system), and
-- the rows (their right-click cancels a buff: protected) move only out of
-- combat, through the kit's combat queue. Off, or while the column is not
-- MelloUI's (the Minimap Kit off), the rows stand on the game's buff bar's
-- place, set as they always were.
--------------------------------------------------------------------------------

local ATTACH_GAP = 13   -- UI units between the rows and the column
local PLACE_KEY = "Auras: your rows by the minimap column"   -- its key in the combat queue
local Num = MelloUI.Safe.Number
local placedSide, placedX, placedY   -- the place by the column ("left" / "right"); nil on the game's place

-- the game's buff bar's place (the rows' place before the column)
local function GamePlace(c)
	c:ClearAllPoints()
	c:SetPoint("TOPRIGHT", BuffFrame or UIParent, "TOPRIGHT", 0, 0)
end

-- the flow away from the column: leftwards from the top right, as the rows
-- were made, or rightwards from the top left
local function Flow(c, side)
	local right = side == "right"
	Try(c.SetFlowLayoutAnchorPoint, c, right and "TOPLEFT" or "TOPRIGHT")
	Try(c.SetFlowLayoutGrowthDirection, c, right and 1 or -1, -1)
	Try(c.UpdateAllAuras, c)
end

-- MinimapPanel while the column is MelloUI's (the module on), else nil
local function ColumnOwner()
	local mm = MelloUI:GetModule("MinimapPanel")
	if mm and mm.isEnabled and mm.ColumnPart and Minimap then
		return mm
	end
	return nil
end

-- where the rows' top corner goes: x, y in the rows' own units from the
-- screen's bottom left, and the side; nil when any size or place reads
-- secret or cannot be read
local function ColumnPlace(mm, c)
	local ok, l, _, r = pcall(mm.ColumnPart, mm, "frame")
	local okM, _, mb, _, mh = pcall(Minimap.GetRect, Minimap)
	local okS, ms = pcall(Minimap.GetEffectiveScale, Minimap)
	local okR, rs = pcall(c.GetEffectiveScale, c)
	l, r = ok and Num(l), ok and Num(r)
	mb, mh, ms = okM and Num(mb), okM and Num(mh), okS and Num(ms)
	rs = okR and Num(rs)
	-- which half of the screen the column stands in: MinimapPanel's one
	-- answer (Services' tray asks it too), from the edges read here
	local okD, column = false, nil
	if l and r and mm.ColumnSide then
		okD, column = pcall(mm.ColumnSide, mm, l, r)
	end
	if not (l and r and mb and mh and ms and rs and okD and column) or rs <= 0 then
		return nil
	end
	local y = (mb + mh) * ms / rs
	if column == "left" then
		return r / rs + ATTACH_GAP, y, "right"
	end
	return l / rs - ATTACH_GAP, y, "left"
end

local function Near(a, b)
	return b ~= nil and math.abs(a - b) < 0.01
end

-- the rows put in their place (run out of combat by the kit's queue): by
-- the column while attached and it can be read (moved only when the place
-- changed; kept where they are while it cannot be read), else the game's
local function PlaceNow()
	local c = playerRows
	if not c then
		return
	end
	local mm = M.isEnabled and M.db.playerColumn and ColumnOwner()
	if mm then
		local x, y, side = ColumnPlace(mm, c)
		if x then
			if side ~= placedSide or not Near(x, placedX) or not Near(y, placedY) then
				if side ~= (placedSide or "left") then
					Flow(c, side)
				end
				c:ClearAllPoints()
				c:SetPoint(side == "right" and "TOPLEFT" or "TOPRIGHT", UIParent, "BOTTOMLEFT", x, y)
				placedSide, placedX, placedY = side, x, y
			end
			return
		elseif placedSide then
			return
		end
	end
	if placedSide then
		if placedSide ~= "left" then
			Flow(c, "left")
		end
		placedSide, placedX, placedY = nil, nil, nil
	end
	GamePlace(c)
end

-- The rows placed. Never attached and not asked to be: the game's buff
-- bar's place at once, as it always was set. Else through the combat queue
-- (at once out of combat); rows made in a fight (a reload in combat) stand
-- on the game's place meanwhile.
local function PlacePlayer()
	if not playerRows then
		return
	end
	if placedSide == nil and not (M.isEnabled and M.db.playerColumn) then
		GamePlace(playerRows)
		return
	end
	-- (the rows are the game's protected aura frames: their point count can
	-- read secret to our code, so it is tested for a secret first; user,
	-- 2026-09-25: "Auras.lua:492: attempt to compare a secret number value")
	local okN, n = pcall(playerRows.GetNumPoints, playerRows)
	if okN and not Secret(n) and n == 0 then
		GamePlace(playerRows)
	end
	MelloUI.Kit:WhenOutOfCombat(PlaceNow, PLACE_KEY)
end

-- the column re-laid (the bus's 'column') or the Minimap Kit switched: the
-- rows follow while they are attached or asked to be
local function FollowColumn()
	if playerRows and M.isEnabled and (M.db.playerColumn or placedSide) then
		PlacePlayer()
	end
end

local function SetPlayer(on)
	on = on and not inEditMode
	if on and not playerRows then
		local ok, c = pcall(NewContainer, UIParent, "player", {
			{ key = "buffs", filter = "HELPFUL", max = 40 },
			{ key = "debuffs", filter = "HARMFUL", max = 16 },
		}, { size = M.db.playerSize, durationBelow = true, dispel = true, cancel = true, tooltip = "ANCHOR_BOTTOMLEFT",
			anchor = "TOPRIGHT", gx = -1, gy = -1, line = PlayerLine(), spacing = 6, lineSpacing = 16 })
		if not ok then
			MelloUI:Notice("Buffs & Debuffs: your buff rows could not be made (%s).", tostring(c))
			return
		end
		playerRows = c
		ItemEnchantments(c)
	end
	if playerRows then
		PlacePlayer()
		playerRows:SetFrameStrata("LOW")
		Try(playerRows.SetEnabled, playerRows, on and true or false)
		playerRows:SetShown(on and true or false)
	end
	GameBars(on and true or false)
end

--------------------------------------------------------------------------------
-- Target
--------------------------------------------------------------------------------

local targetRows

local function GameTargetRow()
	if TargetFrame and TargetFrame.GetAuraContainer then
		local ok, c = pcall(TargetFrame.GetAuraContainer, TargetFrame)
		if ok then
			return c
		end
	end
	return nil
end

local function TargetFilter()
	return M.db.targetOnlyMine and "HARMFUL|PLAYER" or "HARMFUL"
end

local function SetTarget(on)
	local game = GameTargetRow()
	if on and not targetRows and TargetFrame then
		local ok, c = pcall(NewContainer, TargetFrame, "target", {
			{ key = "debuffs", filter = TargetFilter(), max = 16 },
			{ key = "buffs", filter = "HELPFUL", max = 16 },
		}, { size = M.db.targetSize, swipe = true, dispel = true, tooltip = "ANCHOR_BOTTOMRIGHT",
			anchor = "TOPLEFT", gx = 1, gy = -1, line = 170, spacing = 3 })
		if not ok then
			MelloUI:Notice("Buffs & Debuffs: the target rows could not be made (%s).", tostring(c))
			return
		end
		targetRows = c
	end
	if targetRows then
		targetRows:ClearAllPoints()
		if game then
			targetRows:SetPoint("TOPLEFT", game, "TOPLEFT", 0, 0)
			targetRows:SetFrameLevel(game:GetFrameLevel() + 10)
		else
			targetRows:SetPoint("TOPLEFT", TargetFrame, "BOTTOMLEFT", 6, -4)
		end
		Try(targetRows.SetEnabled, targetRows, on and true or false)
		targetRows:SetShown(on and true or false)
	end
	Veil(game, on and true or false)
end

--------------------------------------------------------------------------------
-- Enemy nameplates
--------------------------------------------------------------------------------

local plateRows = setmetatable({}, { __mode = "k" })   -- [nameplate unit frame] = container

local function GameDebuffRow(uf)
	local auras = uf and uf.AurasFrame
	return auras and auras.DebuffListFrame, auras
end

local function PlateFilter(auras)
	local f = auras and auras.debuffFilterString
	if type(f) == "string" and not Secret(f) and f ~= "" then
		return f
	end
	return "HARMFUL|PLAYER"
end

local function ClearPlate(uf)
	local c = plateRows[uf]
	if c then
		Try(c.SetEnabled, c, false)
		c:Hide()
	end
	Veil((GameDebuffRow(uf)), false)
end

local function FillPlate(uf, unit)
	if not (M.isEnabled and M.db.nameplates and uf and unit) then
		ClearPlate(uf)
		return
	end
	local okA, enemy = pcall(UnitCanAttack, "player", unit)
	if not okA or Secret(enemy) or not enemy then
		ClearPlate(uf)
		return
	end
	local row, auras = GameDebuffRow(uf)
	local c = plateRows[uf]
	if not c then
		local ok, made = pcall(NewContainer, uf, nil, {
			{ key = "debuffs", filter = PlateFilter(auras), max = 8 },
		}, { size = M.db.nameplateSize, swipe = true, dispel = false, tooltip = "ANCHOR_TOP",
			anchor = "BOTTOMLEFT", gx = 1, gy = 1, line = 150, spacing = 2 })
		if not ok then
			return   -- the game's row stays
		end
		c = made
		plateRows[uf] = c
	end
	c:ClearAllPoints()
	if row then
		c:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
		local okL, level = pcall(row.GetFrameLevel, row)
		if okL and not Secret(level) and level then
			c:SetFrameLevel(level + 2)
		end
	else
		c:SetPoint("BOTTOMLEFT", uf, "TOPLEFT", 0, 4)
	end
	Try(c.SetUnit, c, unit)
	Try(c.SetEnabled, c, true)
	-- the game hands the same token (nameplate1 ...) to the next mob: the
	-- container sees no new unit, so it is told to look again
	Try(c.UpdateAllAuras, c)
	c:Show()
	Veil(row, true)
end

local function PlateOf(unit)
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if ok and plate and not (plate.IsForbidden and plate:IsForbidden()) then
		return plate.UnitFrame
	end
	return nil
end

local function AllPlates(fn)
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if ok and type(plates) == "table" then
		for _, plate in ipairs(plates) do
			if plate.UnitFrame and not (plate.IsForbidden and plate:IsForbidden()) then
				fn(plate.UnitFrame, plate.UnitFrame.unit or plate.namePlateUnitToken)
			end
		end
	end
end

local function SetNameplates(on)
	AllPlates(function(uf, unit)
		if on then
			FillPlate(uf, unit)
		else
			ClearPlate(uf)
		end
	end)
end

--------------------------------------------------------------------------------
-- Events, Edit Mode, lifecycle
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		local uf = PlateOf(unit)
		if uf then
			FillPlate(uf, unit)
		end
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		local uf = PlateOf(unit)
		if uf then
			ClearPlate(uf)
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		-- a new target is still "target" to the container: it follows the
		-- unit's aura changes, not who the unit is (user, 2026-09-23: the
		-- last target's buffs stayed), so it is told to look again
		if targetRows and targetRows:IsShown() then
			Try(targetRows.UpdateAllAuras, targetRows)
		end
	end
end)

local editHooked = false

-- (through the kit's one Edit Mode registration, the bus's 'editmode';
-- audit, 2026-09-24) and the column under the minimap (the bus's 'column',
-- told after it was laid again; the Minimap Kit switched on or off). Taken
-- at the first enable, never at login for a player without this module.
local function WatchEditMode()
	if editHooked then
		return
	end
	editHooked = true
	MelloUI:On("editmode", function(entering)
		inEditMode = entering
		if M.isEnabled and M.db.player then
			SetPlayer(not entering)
		end
	end, M)
	MelloUI:On("column", FollowColumn, M)
	MelloUI:On("module", function(name)
		if name == "MinimapPanel" then
			FollowColumn()
		end
	end, M)
end

local function ApplyAll()
	local db = M.db
	SetPlayer(M.isEnabled and db.player)
	SetTarget(M.isEnabled and db.target)
	SetNameplates(M.isEnabled and db.nameplates)
end

function M:OnEnable(db)
	self.db = db
	if not Available() then
		MelloUI:Notice("Buffs & Debuffs: this client has no aura container, so the game's own rows stay.")
		return
	end
	WatchEditMode()
	eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
	ApplyAll()
end

function M:OnDisable()
	eventFrame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
	eventFrame:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
	eventFrame:UnregisterEvent("PLAYER_TARGET_CHANGED")
	SetPlayer(false)
	SetTarget(false)
	SetNameplates(false)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if not M.isEnabled then
		return
	end
	if key == "player" then
		SetPlayer(value)
	elseif key == "target" then
		SetTarget(value)
	elseif key == "nameplates" then
		SetNameplates(value)
	elseif key == "playerColumn" then
		PlacePlayer()
	elseif key == "playerSize" or key == "playerPerRow" then
		Resize(playerRows, db.playerSize, PlayerLine())
	elseif key == "targetSize" then
		Resize(targetRows, db.targetSize)
	elseif key == "nameplateSize" then
		for _, c in pairs(plateRows) do
			Resize(c, db.nameplateSize)
		end
	elseif key == "targetOnlyMine" and targetRows then
		Try(targetRows.SetAuraGroupFilterString, targetRows, "debuffs", TargetFilter())
		Try(targetRows.UpdateAllAuras, targetRows)
	end
end

MelloUI:Profile("Auras", "events", eventFrame)
