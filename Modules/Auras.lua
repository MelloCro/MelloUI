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
--     The Minimap Column, below), or under the player frame in the target
--     rows' look (Attach To The Player Frame, 0.20.1); right-click cancels
--     a buff; the weapon buffs first on the first line (MelloUI's own
--     buttons, 0.20.1: Weapon below). The game's buff and debuff bars are hidden with
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
		-- (your rows' layout: set by Unit Frames > Buffs & Debuffs > Layout's
		-- rows, Tweaks' Buff Layout, while these rows show -- 0.19.9)
		playerSize = 30,
		playerPerRow = 12,
		playerSpacing = 6,
		playerGrow = "left",
		playerNewRows = "down",
		playerColumn = true,
		playerFrame = false,
		playerFrameSize = 22,   -- (the target rows' size)
		playerFrameGrow = "right",
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
		{ type = "toggle", key = "playerFrame", parent = "player", name = "Attach To The Player Frame",
		  desc = "Your debuffs, then your buffs and weapon buffs, under your player frame, as the target's are under the target frame: the same icons, spiral and timers. Right-click a buff to cancel it. They move with the player frame. Off, they stand beside the minimap or where the game's buff bar is." },
		{ type = "dropdown", key = "playerFrameGrow", parent = "playerFrame", name = "Direction",
		  values = { { value = "right", label = "Left To Right" }, { value = "left", label = "Right To Left" } },
		  desc = "Which way your icons run under the player frame: from the bars' left end rightwards, or from their right end leftwards." },
		{ type = "slider", key = "playerFrameSize", parent = "playerFrame", name = "Icon Size On The Frame", min = 14, max = 36, step = 1,
		  desc = "The size of your buff and debuff icons under the player frame, in pixels (the target's are 22 by default). The rows keep one width, so a smaller size fits more in a row." },
		{ type = "header", name = "Target" },
		{ type = "toggle", key = "target", name = "Target Frame",
		  desc = "Your target's debuffs, then its buffs, under the target frame, in place of the game's." },
		{ type = "slider", key = "targetSize", parent = "target", name = "Icon Size", min = 14, max = 36, step = 1,
		  desc = "The size of your target's debuff and buff icons under its frame, in pixels. The rows keep one width, so a smaller size fits more in a row." },
		{ type = "toggle", key = "targetOnlyMine", parent = "target", name = "Only My Debuffs",
		  desc = "On the target, show only the debuffs you put on it." },
		{ type = "header", name = "Nameplates" },
		{ type = "toggle", key = "nameplates", name = "Enemy Nameplates",
		  desc = "Your debuffs on enemy nameplates, in place of the game's row. Crowd control stays with the game (and the Nameplates module)." },
		{ type = "slider", key = "nameplateSize", parent = "nameplates", name = "Icon Size", min = 12, max = 32, step = 1,
		  desc = "The size of your debuff icons on enemy nameplates, in pixels." },
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

-- The UI shade (0.14.0; the ui-shade-plan memory: a soft dark shade that
-- follows each element's shape; the Buffs area in Dynamic UI) on your rows
-- and the target's: each button is its own element, drawn by the button
-- itself at BACKGROUND -8, under its edge and its icon -- the rim's own
-- shadow, or a soft square round the black edge (the square's body
-- stretched to the icon and its edge), made for the look in use only. The
-- buttons are the game's protected aura buttons: only our own textures on
-- them are hooked (a partner follows its piece's Show / Hide), never a
-- script of the button (a shade frame of their own would follow the
-- button's). Not on the nameplates' rows (a plate's sizes read secret, and
-- the plates have their own shade). Made once per button at the shade's
-- pace (Kit:ShadeElement), fitted again when the size or the look changes.
-- The reach stays inside the row's gap: a row's buttons are siblings at one
-- frame level, and draw layers order regions only inside one frame, so a
-- partner reaching past the gap would lie over its neighbour's rim and icon
-- (review, 2026-09-26). The room is the gap less how far this button's
-- piece stands past the button, less how far the neighbour's does (at least
-- 1: its black edge, or the dispel border over a rim), less 1; a piece's
-- own reach is cut to it, and no partner is made with less than MIN_REACH
-- (the target's close rows, a rim that fills the gap).
local SQUARE = "shade/square"
local MIN_REACH = 1   -- UI units

-- the widest reach of a shadow shape, painted px (nil: none in the sheet)
local function PadOf(Kit, name)
	local e = Kit:ShadowShape(name)
	local pad = e and e.pad
	if type(pad) ~= "table" then
		return nil, e
	end
	local m = math.max(tonumber(pad[1]) or 0, tonumber(pad[2]) or 0, tonumber(pad[3]) or 0, tonumber(pad[4]) or 0)
	return m > 0 and m or nil, e
end

-- a partner's scale: the piece's own, its reach cut to the room (a made one
-- with no room left keeps a hair's reach: a scale of 0 is no scale to
-- Kit:ShadowFit); made once it has a reach worth having, fitted again
-- whenever the scale changed (one still to make takes it then)
local NO_ROOM = 0.05  -- UI units
local function FitPartner(Kit, so, key, tex, natural, pad, over, gap)
	local room = gap - over - math.max(over, 1) - 1
	local s = natural
	if natural * pad > room then
		s = math.max(room, NO_ROOM) / pad
	end
	local o = so[key]
	if o.scale ~= s then
		o.scale = s
		Kit:ShadowFit(tex, s)
	end
	if not o.added and s * pad >= MIN_REACH then
		o.added = true
		so.el:Add(tex, o)
	end
end

-- `rimSide`, `piece`: the rim drawn at that side (its piece), else the black
-- edge
local function ShadeButton(button, t, rimSide, piece)
	local Kit = MelloUI.Kit
	if not (t.shade and Kit.ShadeElement and Kit.ShadowShape) then
		return
	end
	local so = t.shadeOpts
	if not so then
		so = { el = Kit:ShadeElement(button, "buffs", { host = button }), edge = { shape = SQUARE }, rim = {} }
		t.shadeOpts = so
	end
	local gap = t.gap or 0
	if rimSide then
		local pad = PadOf(Kit, MelloUI.Kept.pieceNameOf[t.rim])
		if pad and piece and piece.w > 0 then
			FitPartner(Kit, so, "rim", t.rim, rimSide / piece.w, pad, (rimSide - t.size) / 2, gap)
		end
		return
	end
	-- the square's body (its picture less its reach) at the icon and its edge
	local pad, e = PadOf(Kit, SQUARE)
	local size = e and type(e.size) == "table" and tonumber(e.size[1])
	local inner = pad and size and size - (tonumber(e.pad[1]) or 0) - (tonumber(e.pad[3]) or 0)
	if inner and inner > 0 then
		FitPartner(Kit, so, "edge", t.edge, (t.size + 2) / inner, pad, 1, gap)
	end
end

local function ApplyAuraLook(button)
	local t = texts[button]
	local Kit = MelloUI.Kit
	if not (t and Kit and Kit.Slot) then
		return
	end
	local look = AuraLook()
	local kind = Kit.buttonLooks and Kit.buttonLooks.rimKind[look]
	-- (0.19.8) a style of the border library's (Single rail, Backdrop:
	-- Modules/KitBorders.lua), at a button's weight, its opening 2 px over the
	-- icon's edge as the thin rims' inner edge is; on an anchor of its own
	-- (an empty texture: the button is the game's, protected, no hook on it)
	local style = not kind and Kit.BorderStyles and Kit.BorderStyles[look] and look
	if style then
		if t.rim then
			t.rim:Hide()
		end
		t.edge:Hide()
		if not t.lib then
			t.libAt = button:CreateTexture(nil, "OVERLAY", nil, 3)
			t.lib = Kit:NewBorder({ rect = t.libAt, owner = button, place = "on", layer = "OVERLAY", sub = 3 })
		end
		t.lib:Lay(style, "light")
		local x, y = t.lib:Inset()
		t.libAt:ClearAllPoints()
		t.libAt:SetPoint("CENTER", button, "CENTER")
		t.libAt:SetSize(t.size - 4 + 2 * x, t.size - 4 + 2 * y)
		t.lib:SetShown(true)
		ShadeButton(button, t)
		return
	end
	if t.lib then
		t.lib:SetShown(false)
	end
	if not kind then
		if t.rim then
			t.rim:Hide()
		end
		t.edge:Show()
		ShadeButton(button, t)
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
	if MelloUI.Kept.pieceNameOf[t.rim] ~= base .. "_normal" then
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
	-- (the rim drawn at its own size: its shadow at that scale)
	ShadeButton(button, t, side, p)
end

-- o: size, swipe (a cooldown spiral), durationBelow (the time under the
-- icon, else in its middle), rawSeconds (the time as the bare number of
-- seconds: MelloUI.Anim:RawSeconds), compactTime (the time with no space
-- before its letter, "59m": MelloUI.Anim:CompactDuration), dispel (a dispel-coloured border on debuffs),
-- cancel (right-click cancels), tooltip (anchor), shade (the UI shade:
-- ShadeButton)
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
	-- (0.20.1, the user: "the debuffs on the nameplates should not have "s" for seconds or minutes, just pure
	-- seconds") the core's bare-seconds formatter where the row asks for it (the game's own "4s" / "2m" elsewhere)
	-- (0.20.1, the user: "make it 59m on both" -- the target's rows and the rows on the player frame)
	local Anim = MelloUI.Anim
	local fmt = Anim and ((o.rawSeconds and Anim:RawSeconds()) or (o.compactTime and Anim:CompactDuration()))
	Try(button.SetDurationText, button, time, fmt and { textFormatter = fmt } or {})
	-- (gap: the room between two buttons of the row, the shade's reach kept in it)
	texts[button] = { time = time, count = count, below = o.durationBelow, edge = edge, size = o.size, shade = o.shade,
		gap = o.shade and math.min(o.spacing or 0, o.lineSpacing or o.spacing or 0) or nil }
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
-- (0.17.0: the Fader's Buffs & Debuffs element fades these rows too)
M.PlayerRows = function()
	-- (0.20.1: the rows on the player frame while they stand in for these)
	local framed = rawget(M, "FrameRows") and M.FrameRows()
	return framed or playerRows
end
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
	return (M.db.playerSize + (M.db.playerSpacing or 6)) * M.db.playerPerRow
end

--------------------------------------------------------------------------------
-- Weapon buffs (0.20.1; players: "some buffs are not showing at all, for
-- example the shaman enhancements to weapons"; /mello auras, 2026-10-10:
-- Forever keeps two enchants a weapon, a Temporary one -- a stone, an oil, a
-- poison -- and an Imbue -- a shaman's weapon --, and lists both in
-- C_Item.GetWeaponEnchantInfo, the call the game's own buff bar reads; the
-- aura container's item enchantments read C_PaperDollInfo's one temporary
-- enchant a slot, so an imbue never reached the rows). MelloUI's own buttons
-- in the rows' look, one for every timed weapon buff the game's bar shows,
-- first on the rows' first line (the user's pick, "First on the buff rows",
-- as the game's bar has them): the rows move over by as many icons, out of
-- combat only (a weapon buff that comes in a fight overlaps the first icon
-- until it ends). No right-click cancel (the game's is protected).
--------------------------------------------------------------------------------

local Weapon = { n = 0, list = {}, sets = setmetatable({}, { __mode = "k" }),
	shiftOf = setmetatable({}, { __mode = "k" }), cornerOf = setmetatable({}, { __mode = "k" }),
	gxOf = setmetatable({}, { __mode = "k" }) }
local WEAPON_KEY = "Auras: the rows moved over for the weapon buffs"   -- its key in the combat queue

-- the rows' move along their first line for the weapon buttons standing first on it (`corner` the flow's, `gx`
-- the line's direction), noted for the buttons; 0 with none (the place as it always was)
function Weapon.DX(c, corner, gx)
	local n = Weapon.n
	Weapon.shiftOf[c], Weapon.cornerOf[c], Weapon.gxOf[c] = n, corner, gx
	if n == 0 then
		return 0
	end
	local look = c.melloLook
	return gx * n * ((look.size or 0) + (look.spacing or 0))
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

-- the rows' flow: away from the column while attached (side), else the
-- Grow setting; New Rows down or up (0.19.9). Its corner and directions.
local function FlowOf(side)
	local right = (side or M.db.playerGrow) == "right"
	local up = M.db.playerNewRows == "up"
	return (up and "BOTTOM" or "TOP") .. (right and "LEFT" or "RIGHT"), right and 1 or -1, up and 1 or -1
end

-- the game's buff bar's place (the rows' place before the column): the
-- flow's corner on the bar's same corner
local function GamePlace(c)
	local corner, gx = FlowOf(nil)
	c:ClearAllPoints()
	c:SetPoint(corner, BuffFrame or UIParent, corner, Weapon.DX(c, corner, gx), 0)
	Weapon.Lay()
end

-- the flow set (only when it changed: the container lays its rows again)
local flowNow
local function Flow(c, side)
	local corner, gx, gy = FlowOf(side)
	local key = corner .. gx .. gy
	if key == flowNow then
		return
	end
	flowNow = key
	Try(c.SetFlowLayoutAnchorPoint, c, corner)
	Try(c.SetFlowLayoutGrowthDirection, c, gx, gy)
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
	-- (level with the map's shown part: its Width x Height, 0.15.0)
	local map = mm.MapFrame and mm:MapFrame() or Minimap
	local okM, _, mb, _, mh = pcall(map.GetRect, map)
	local okS, ms = pcall(map.GetEffectiveScale, map)
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
			if side ~= placedSide or not Near(x, placedX) or not Near(y, placedY) or Weapon.shiftOf[c] ~= Weapon.n then
				Flow(c, side)
				c:ClearAllPoints()
				local corner, gx = FlowOf(side)
				c:SetPoint(corner, UIParent, "BOTTOMLEFT", x + Weapon.DX(c, corner, gx), y)
				placedSide, placedX, placedY = side, x, y
				Weapon.Lay()
			end
			return
		elseif placedSide then
			return
		end
	end
	placedSide, placedX, placedY = nil, nil, nil
	Flow(c, nil)
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

-- (0.19.9) the Buff Layout's spacing, grow or new rows changed: the rows'
-- groups spaced again (their durations under each line: 10 more between
-- lines), the line's length, and placed again with their flow (out of combat)
local function Relayout()
	local c = playerRows
	if not c then
		return
	end
	local spacing = M.db.playerSpacing or 6
	local layout = { elementSpacing = spacing, lineSpacing = spacing + 10, groupSpacing = spacing,
		groupLineSpacing = spacing + 10, forceNewLine = true }
	for _, key in ipairs(c.melloGroups) do
		Try(c.SetAuraGroupLayout, c, key, layout)
	end
	c.melloLook.spacing, c.melloLook.lineSpacing = spacing, spacing + 10
	for button, t in pairs(texts) do
		if t.shade and button:GetParent() == c then
			t.gap = spacing   -- (the shade's reach between two buttons: the smaller room)
		end
	end
	Resize(c, M.db.playerSize, PlayerLine())
	placedX = nil   -- (placed again: its corner may have changed)
	MelloUI.Kit:WhenOutOfCombat(PlaceNow, PLACE_KEY)
end

-- your rows stand by the minimap column (their Grow follows it then)
function M.Attached()
	return (playerRows and placedSide ~= nil) and true or false
end

-- the column re-laid (the bus's 'column') or the Minimap Kit switched: the
-- rows follow while they are attached or asked to be
local function FollowColumn()
	if playerRows and M.isEnabled and (M.db.playerColumn or placedSide) then
		PlacePlayer()
	end
end

--------------------------------------------------------------------------------
-- Attach To The Player Frame (0.20.1, the user: "an option under UnitFrames ->
-- Player to attach their own buffs and debuffs to their unitframe, mimicing
-- the behaviour of how buffs and debuffs are working on the Target
-- Unitframe ... the same formating of the timers"): a container of its own
-- in the target rows' look (the spiral, the time on the icon, the game's
-- formatting; debuffs, then buffs, then the weapon buffs), parented to the
-- player frame as the target's are to the target frame, hung under its art
-- as the game hangs the target's (Blizzard_UnitFrame TargetFrame.lua
-- AnchorAuraContainer: 9 up from the art's bottom); Direction (the user,
-- 2026-10-10: "it needs a anchoring position, from left to right or right
-- to left"): from the bars' left end rightwards (the health bars' left, read
-- against the art: clear of the portrait ring and the level orb), or from
-- 5 in of the art's right end leftwards. Icon Size On The Frame (the user:
-- "the size is a bit off": the target's 22 by default, not the buff bar's
-- 30). Made on the first ask; the rows (their right-click cancels a buff:
-- protected) placed and their flow set out of combat only, then they
-- follow the frame.
--------------------------------------------------------------------------------

local frameRows
local FRAME_PLACE_KEY = "Auras: your rows on the player frame"   -- its key in the combat queue
local FRAME = { IN = 5, UP = 9, BARS = 85 }   -- the game's AURA_START_X / AURA_START_Y; the bars' left (PlayerFrame.xml)

-- the health bars' left end from the art's left (a plain read; the template's 85 while either reads secret)
local function BarsIn(pf, art)
	local content = pf.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	local bars = main and main.HealthBarsContainer
	if bars and bars.GetLeft and art.GetLeft then
		local okB, bl = pcall(bars.GetLeft, bars)
		local okA, al = pcall(art.GetLeft, art)
		bl, al = okB and Num(bl), okA and Num(al)
		if bl and al then
			return bl - al
		end
	end
	return FRAME.BARS
end

local function PlaceOnFrame()
	local c, pf = frameRows, PlayerFrame
	if not (c and pf) then
		return
	end
	local container = pf.PlayerFrameContainer
	local art = (container and container.FrameTexture) or pf
	local right = M.db.playerFrameGrow ~= "left"
	Try(c.SetFlowLayoutAnchorPoint, c, right and "TOPLEFT" or "TOPRIGHT")
	Try(c.SetFlowLayoutGrowthDirection, c, right and 1 or -1, -1)
	c:ClearAllPoints()
	if right then
		c:SetPoint("TOPLEFT", art, "BOTTOMLEFT", BarsIn(pf, art) + Weapon.DX(c, "TOPLEFT", 1), FRAME.UP)
	else
		c:SetPoint("TOPRIGHT", art, "BOTTOMRIGHT", -FRAME.IN + Weapon.DX(c, "TOPRIGHT", -1), FRAME.UP)
	end
	Try(c.UpdateAllAuras, c)
	Weapon.Lay()
end

local function SetFrameRows(on)
	if on and not frameRows and PlayerFrame then
		local ok, c = pcall(NewContainer, PlayerFrame, "player", {
			{ key = "debuffs", filter = "HARMFUL", max = 16 },
			{ key = "buffs", filter = "HELPFUL", max = 40 },
		}, { size = M.db.playerFrameSize or 22, swipe = true, compactTime = true, dispel = true, cancel = true,
			tooltip = "ANCHOR_BOTTOMRIGHT",
			anchor = M.db.playerFrameGrow == "left" and "TOPRIGHT" or "TOPLEFT", gx = M.db.playerFrameGrow == "left" and -1 or 1,
			gy = -1, line = 170, spacing = 3, shade = true })
		if not ok then
			MelloUI:Notice("Buffs & Debuffs: your rows on the player frame could not be made (%s).", tostring(c))
			return
		end
		frameRows = c
	end
	if frameRows then
		if on then
			MelloUI.Kit:WhenOutOfCombat(PlaceOnFrame, FRAME_PLACE_KEY)
		end
		Try(frameRows.SetEnabled, frameRows, on and true or false)
		frameRows:SetShown(on and true or false)
	end
end

-- (0.20.1: the rows under the player frame while they are shown)
function M.FrameRows()
	return (frameRows and frameRows:IsShown()) and frameRows or nil
end

-- The weapon buttons (see Weapon above): the rows shown now (the player frame's, else yours), every timed weapon
-- buff the game's bar lists read into reused entries, a button each (made on its first need, a set per rows, in
-- their look: InitButton through the few container-button calls it makes), the time run by the engine.
local WEAPON_SLOTS = { "MainHand", "OffHand", "Ranged" }
local WEAPON_INV = { MainHand = "INVSLOT_MAINHAND", OffHand = "INVSLOT_OFFHAND", Ranged = "INVSLOT_RANGED" }
local WEAPON_INV_DEFAULT = { MainHand = 16, OffHand = 17, Ranged = 18 }

local WeaponButton = {}
function WeaponButton:SetIcon(tex) self.melloIcon = tex end
function WeaponButton:SetDurationCooldown(cooldown) self.melloCooldown = cooldown end
function WeaponButton:SetApplicationCount(fs) self.melloCount = fs end
function WeaponButton:SetDurationText(fs, opts) self.melloTime, self.melloFormat = fs, opts and opts.textFormatter end
function WeaponButton:SetTooltipAnchorPoint(anchor) self.melloTip = anchor end

local function WeaponButton_OnEnter(b)
	GameTooltip:SetOwner(b, b.melloTip or "ANCHOR_BOTTOMLEFT")
	pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", b.melloInv)
	GameTooltip:Show()
end
local function WeaponButton_OnLeave()
	GameTooltip:Hide()
end

function Weapon.Rows()
	return M.FrameRows() or ((playerRows and playerRows:IsShown()) and playerRows) or nil
end

-- every timed weapon buff into Weapon.list (entries reused); their count
function Weapon.Read()
	local CI, E = rawget(_G, "C_Item"), rawget(_G, "Enum")
	local ws = type(E) == "table" and E.WeaponSlot
	local list, n = Weapon.list, 0
	if not (type(CI) == "table" and CI.GetWeaponEnchantInfo and type(ws) == "table") then
		return 0
	end
	local okV, enchantIcon = false, nil
	if C_CVar and C_CVar.GetCVarBool then
		okV, enchantIcon = pcall(C_CVar.GetCVarBool, "displayTemporaryEnchantIcon")
	end
	enchantIcon = okV and not Secret(enchantIcon) and enchantIcon == true
	for _, name in ipairs(WEAPON_SLOTS) do
		local id = ws[name]
		local ok, enchants = false, nil
		if id ~= nil then
			ok, enchants = pcall(CI.GetWeaponEnchantInfo, id)
		end
		if ok and type(enchants) == "table" and not Secret(enchants) then
			for _, e in ipairs(enchants) do
				local has, left = e.hasEnchant, e.timeLeft
				if not Secret(has) and has == true and not Secret(left) and type(left) == "number" and left > 0 then
					n = n + 1
					local t = list[n] or {}
					list[n] = t
					t.inv = rawget(_G, WEAPON_INV[name]) or WEAPON_INV_DEFAULT[name]
					t.left = left / 1000
					local charges, iconID = e.charges, e.enchantIconID
					t.charges = (not Secret(charges) and type(charges) == "number" and charges > 0) and charges or nil
					local okT, tex = pcall(_G.GetInventoryItemTexture, "player", t.inv)
					tex = okT and not Secret(tex) and tex or nil
					if enchantIcon and not Secret(iconID) and type(iconID) == "number" and iconID > 0 then
						tex = iconID
					end
					t.icon = tex or 134400   -- (the question mark while the item reads nothing)
				end
			end
		end
	end
	return n
end

-- a rows' set of buttons: a holder of ours on the rows (their alpha, show and Edit Mode hiding follow), made on its
-- first need
function Weapon.SetOf(c)
	local set = Weapon.sets[c]
	if not set then
		local holder = CreateFrame("Frame", nil, c)
		holder:SetAllPoints(c)
		set = { holder = holder, buttons = {} }
		Weapon.sets[c] = set
	end
	return set
end

function Weapon.Button(set, k, c)
	local b = set.buttons[k]
	if not b then
		b = CreateFrame("Button", nil, set.holder)
		for name, fn in pairs(WeaponButton) do
			b[name] = fn
		end
		InitButton(b, c.melloLook)
		b:EnableMouse(true)
		b:SetScript("OnEnter", WeaponButton_OnEnter)
		b:SetScript("OnLeave", WeaponButton_OnLeave)
		set.buttons[k] = b
	end
	return b
end

-- the time left run by the engine (a duration and its text binding, made once a button), in the rows' format, or
-- the short one ("59m") where the rows keep the game's
function Weapon.Time(b, seconds)
	local util = rawget(_G, "C_DurationUtil")
	if not (type(util) == "table" and util.CreateDuration and util.CreateDurationTextBinding and b.melloTime) then
		return
	end
	if not b.melloDuration then
		local okD, d = pcall(util.CreateDuration)
		local okB, bind = pcall(util.CreateDurationTextBinding)
		if not (okD and d and okB and bind) then
			return
		end
		pcall(bind.SetFontString, bind, b.melloTime)
		local fmt = b.melloFormat or (MelloUI.Anim and MelloUI.Anim:CompactDuration())
		if fmt then
			pcall(bind.SetFormatter, bind, fmt)
		end
		pcall(bind.SetExpiredText, bind, "")
		pcall(bind.SetZeroDurationText, bind, "")
		b.melloDuration, b.melloBinding = d, bind
	end
	pcall(b.melloDuration.SetTimeFromStart, b.melloDuration, GetTime(), seconds)
	pcall(b.melloBinding.SetDuration, b.melloBinding, b.melloDuration)
	pcall(b.melloBinding.SetEnabled, b.melloBinding, true)
end

-- the buttons on the rows' first line from its flow corner, the rows moved over by Weapon.DX when they were placed
-- (a weapon buff that came in a fight overlaps the first icon until the rows move at its end)
function Weapon.Lay()
	local c = Weapon.Rows()
	local set = c and Weapon.sets[c]
	local corner = c and Weapon.cornerOf[c]
	if not (set and corner) then
		return
	end
	local look = c.melloLook
	local step = (look.size or 0) + (look.spacing or 0)
	local gx, shift = Weapon.gxOf[c] or 1, Weapon.shiftOf[c] or 0
	for k = 1, Weapon.n do
		local b = set.buttons[k]
		if b then
			b:ClearAllPoints()
			b:SetPoint(corner, c, corner, -gx * (shift - k + 1) * step, 0)
		end
	end
end

-- the rows placed again with their new shift (out of combat: the kit's queue)
function Weapon.Replace()
	if M.FrameRows() then
		PlaceOnFrame()
	elseif playerRows and playerRows:IsShown() then
		PlacePlayer()
	end
end

function Weapon.Update()
	local c = Weapon.Rows()
	local n = c and Weapon.Read() or 0
	for rows, set in pairs(Weapon.sets) do
		local upTo = rows == c and n or 0
		for k, b in ipairs(set.buttons) do
			if k > upTo then
				b:Hide()
			end
		end
	end
	if c and n > 0 then
		local set = Weapon.SetOf(c)
		local size = c.melloLook.size
		for k = 1, n do
			local e, b = Weapon.list[k], Weapon.Button(set, k, c)
			b.melloInv = e.inv
			if b.melloIcon then
				b.melloIcon:SetTexture(e.icon)
			end
			if b.melloCount then
				b.melloCount:SetText(e.charges or "")
			end
			Weapon.Time(b, e.left)
			local t = texts[b]
			if t and t.size ~= size then
				Try(b.SetSize, b, size, size)
				SizeTexts(b, size)
				t.size = size
				ApplyAuraLook(b)
			end
			b:Show()
		end
	end
	if n ~= Weapon.n then
		Weapon.n = n
		MelloUI.Kit:WhenOutOfCombat(Weapon.Replace, WEAPON_KEY)
	end
	Weapon.Lay()
end

-- the rows on or off: the weapon buffs' events with them (on the module's own event frame, below: nothing made)
function Weapon.Switch(on)
	local f = Weapon.events
	if f then
		if on then
			f:RegisterEvent("WEAPON_ENCHANT_CHANGED")
			pcall(f.RegisterEvent, f, "WEAPON_SLOT_CHANGED")
			f:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
		else
			f:UnregisterEvent("WEAPON_ENCHANT_CHANGED")
			pcall(f.UnregisterEvent, f, "WEAPON_SLOT_CHANGED")
			f:UnregisterEvent("UNIT_INVENTORY_CHANGED")
		end
	end
	Weapon.Update()
end

-- the rows' icons sized or spaced anew: the buttons with them, the rows moved over by the new step
function Weapon.Resized()
	Weapon.Update()
	if Weapon.n > 0 then
		MelloUI.Kit:WhenOutOfCombat(Weapon.Replace, WEAPON_KEY)
	end
end

M.WeaponCount = function()
	return Weapon.n
end

local function SetPlayer(on)
	on = on and not inEditMode
	-- (0.20.1) Attach To The Player Frame: those rows in place of these
	local onFrame = on and M.db.playerFrame and true or false
	SetFrameRows(onFrame)
	local rows = on and not onFrame
	if rows and not playerRows then
		local ok, c = pcall(NewContainer, UIParent, "player", {
			{ key = "buffs", filter = "HELPFUL", max = 40 },
			{ key = "debuffs", filter = "HARMFUL", max = 16 },
		}, { size = M.db.playerSize, durationBelow = true, compactTime = true, dispel = true, cancel = true,
			tooltip = "ANCHOR_BOTTOMLEFT",
			anchor = (FlowOf(nil)), gx = select(2, FlowOf(nil)), gy = select(3, FlowOf(nil)), line = PlayerLine(),
			spacing = M.db.playerSpacing or 6, lineSpacing = (M.db.playerSpacing or 6) + 10, shade = true })
		if not ok then
			MelloUI:Notice("Buffs & Debuffs: your buff rows could not be made (%s).", tostring(c))
			return
		end
		playerRows = c
		flowNow = nil
	end
	if playerRows then
		PlacePlayer()
		playerRows:SetFrameStrata("LOW")
		Try(playerRows.SetEnabled, playerRows, rows and true or false)
		playerRows:SetShown(rows and true or false)
	end
	GameBars(on and true or false)
	Weapon.Switch(on and true or false)
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
		}, { size = M.db.targetSize, swipe = true, compactTime = true, dispel = true, tooltip = "ANCHOR_BOTTOMRIGHT",
			anchor = "TOPLEFT", gx = 1, gy = -1, line = 170, spacing = 3, shade = true })
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
		}, { size = M.db.nameplateSize, swipe = true, rawSeconds = true, dispel = false, tooltip = "ANCHOR_TOP",
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
Weapon.events = eventFrame   -- (0.20.1: the weapon buffs' events, while your rows show)
Perf.SetScript(eventFrame, "OnEvent", function(_, event, unit)
	if event == "WEAPON_ENCHANT_CHANGED" or event == "WEAPON_SLOT_CHANGED" or event == "UNIT_INVENTORY_CHANGED" then
		Weapon.Update()
	elseif event == "NAME_PLATE_UNIT_ADDED" then
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
	elseif key == "playerFrame" then
		-- (the rows are protected -- right-click cancels a buff --: shown or hidden out of combat only)
		MelloUI.Kit:WhenOutOfCombat(function()
			SetPlayer(M.isEnabled and M.db.player)
		end, FRAME_PLACE_KEY .. ": switched")
	elseif key == "target" then
		SetTarget(value)
	elseif key == "nameplates" then
		SetNameplates(value)
	elseif key == "playerColumn" then
		PlacePlayer()
	elseif key == "playerSize" or key == "playerPerRow" then
		Resize(playerRows, db.playerSize, PlayerLine())
		Weapon.Resized()
	elseif key == "playerFrameSize" then
		Resize(frameRows, db.playerFrameSize)
		Weapon.Resized()
	elseif key == "playerFrameGrow" then
		MelloUI.Kit:WhenOutOfCombat(PlaceOnFrame, FRAME_PLACE_KEY)
	elseif key == "playerSpacing" or key == "playerGrow" or key == "playerNewRows" then
		Relayout()
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
