--------------------------------------------------------------------------------
-- MelloUI - UI Modifications
--
-- One entry in the configurator for everything that changes how the
-- interface looks and behaves per area (user, 2026-09-21): the painted-kit
-- RESKIN (the first, important option: on or off as a whole, then one
-- toggle per area) and the per-area quality-of-life tweaks (nameplates,
-- tooltips, chat, unit frames), which work whether the reskin is on or
-- off. The only thing that matters is that this module is enabled: off,
-- every reskin panel and every folded tweak goes with it.
--
-- The kit panels (Modules/*Panel.lua) and the folded tweak modules stay
-- separate modules in the code, each with its own /xxdump; they are HIDDEN
-- from the configurator and switched from here. A tweak module's own
-- options are shown on this page under its area (`include`), routed to that
-- module's settings by the configurator.
--
-- Folded in as well (user, 2026-09-21/22): Tweaks, Vendor, FPS / Latency,
-- Fonts, Bar Textures, Bar Text, Class Icons, Cooldown Timers and Dark
-- Mode, each a tab with its switch first. Only the feature modules (Quest
-- List, Route, Services, Voice Over) keep tiles of their own.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

-- The reskin panels: { module name, toggle label, description }
local PANELS = {
	{ sub = "Windows" },
	{ "CharacterPanel",   "Character window",       "Equipment, stats, reputation and skills in the kit." },
	{ "SpellBookPanel",   "Spell book",             "The spell book and its tabs in the kit." },
	{ "ProfessionsPanel", "Professions",            "The profession book and crafting window in the kit." },
	{ "LegacyPanel",      "Legacy window",          "Rewards, challenges and the tree in the kit." },
	{ "QuestLogPanel",    "Quest log",              "The quest log in the world map window and MelloUI's quest list in the kit." },
	{ "GuildPanel",       "Guild & communities",    "Chat, roster, info and settings in the kit." },
	{ "GroupFinderPanel", "Looking for group",      "Listing, browse and who in the kit." },
	{ "CollectionsPanel", "Appearances",            "The wardrobe in the kit." },
	{ "SocialPanel",      "Social window",          "Contacts, raid and quick join in the kit." },
	{ "BackpackPanel",    "Bags",                   "The backpack and bag windows in the kit." },
	{ "GameMenuPanel",    "Game menu",              "The Escape menu on its painted plates." },
	{ sub = "HUD" },
	{ "UnitFramePanel",   "Unit frames",            "Player, target, focus, pet and party frames in the kit." },
	{ "CastBarPanel",     "Cast bars",              "Player, pet, target and focus cast bars in the kit." },
	{ "RaidFramePanel",   "Raid frames",            "Compact raid frames, group borders and totems in the kit." },
	{ "ActionBarPanel",   "Action bars",            "Action bars, stance and pet bars, micro menu, bag bar, experience and reputation bars in the kit." },
	{ "MinimapPanel",     "Minimap",                "The minimap ring, zone band and buttons in the kit." },
	{ "TrackerPanel",     "Objective tracker",      "The tracker's headers and backdrop in the kit." },
	{ "ChatPanel",        "Chat windows",           "Chat frames, tabs, edit box and buttons in the kit (no fade)." },
	{ "DamageMeterPanel", "Damage meter",           "The damage meter and its breakdown window in the kit." },
	{ "TooltipPanel",     "Tooltips",               "Tooltips on the stone box with the single rail." },
	{ "NameplatePanel",   "Nameplates",             "Nameplate health and cast bars in the kit." },
}

-- The folded quality-of-life tweak modules: { module name, area title,
-- switch label, description }. Their options follow the switch on the page.
local TWEAKS = {
	{ "Nameplates", "Nameplates",  "Nameplate quality-of-life", "Large crowd-control icon above the name and a quest marker on enemies you still need. Works with or without the reskin." },
	{ "Tooltip",    "Tooltips",    "Tooltip quality-of-life",   "Class / reaction coloured names and border, the bar-texture fill on the tooltip health bar, placement. The dark backdrop only applies while the tooltip reskin is off." },
	{ "Chat",       "Chat",        "Chat quality-of-life",      "Short channel names, class-coloured names, timestamps, URL copy and the art-hiding toggles (which only apply while the chat reskin is off)." },
	{ "UnitFrames", "Unit frames", "Unit frame quality-of-life", "Name and level tweaks on the unit frames (they step aside where the reskin covers them)." },
	{ "Tweaks",     "Tweaks",      "Tweaks",                    "Hide the micro menu and bag bar, scale the floating combat text." },
	{ "Vendor",     "Vendor",      "Vendor automation",         "Repair your gear and sell junk automatically at a merchant." },
	{ "Stats",      "FPS / Latency", "FPS / latency readout",   "Small coloured FPS and latency readout in the bottom right corner." },
	{ "Fonts",      "Fonts",       "Interface font",            "The font and font size used by the whole interface (titles and headers keep the kit's own face while the reskin is on)." },
	{ "BarTextures", "Bar Textures", "Bar textures",            "The finish of health and mana bars (flat, smooth, glossy, minimalist) and their class colours; the fill under the kit's brackets." },
	{ "BarText",     "Bar Text",     "Bar values",              "Health and power values always shown on the player, target and focus frames." },
	{ "ClassIcons",  "Class Icons",  "Class medallions",        "The painted class medallions in place of the game's class icons and on player portraits." },
	{ "CooldownText", "Cooldown Timers", "Cooldown numbers",    "Countdown numbers on action bar cooldowns and nameplate auras, coloured by the time left." },
	{ "DarkMode",    "Dark Mode",    "Dark Mode",               "Darkens the painted reskin (its brightness below) and, where the reskin is off, the game's own art of unit frames, bars, nameplates, auras and menus." },
}

-- welcomeAsked: the first-login question (take the tour) was asked
-- (Core/Tutorial.lua); layoutApplied: the Edit Mode layout was put in place
-- when the reskin came on (ReskinOn below); flags without option rows
-- defined further down, next to the rest of the switching; declared here so
-- the button on the page can reach them
local Apply, RestoreAreas, NothingWanted

local defaults, options = { reskin = true, unlock = false, positions = {}, welcomeAsked = false, layoutApplied = false, nameFormat = "both" }, {}
options[#options + 1] = { type = "header", name = "Reskin" }
options[#options + 1] = { type = "toggle", key = "reskin", name = "Painted kit reskin", important = true,
	desc = "The whole interface dressed in the painted kit. Off: every area below shows the game's own art; the quality-of-life tweaks keep working." }
options[#options + 1] = { type = "button", name = "Switch every area on",
	hint = "when the list below is all off and nothing is reskinned",
	text = "Switch on",
	onClick = function(_, db)
		local count = RestoreAreas(db)
		if count == 0 then
			MelloUI:Print("Every area is on already.")
			return
		end
		Apply(db, true)
		MelloUI:Print("%d area%s switched back on.", count, count == 1 and "" or "s")
		if MelloUI.RefreshConfig then
			MelloUI:RefreshConfig()
		end
	end }
for _, area in ipairs(PANELS) do
	if area.sub then
		options[#options + 1] = { type = "subheader", name = area.sub }
	else
		defaults[area[1]] = true
		options[#options + 1] = { type = "toggle", key = area[1], name = area[2], desc = area[3] }
	end
end
-- Names (user, 2026-09-22: "make that option global for all of the 3
-- things at the same time"): one dropdown for the unit frames, the
-- nameplates and the name over your own head. Characters here have a first
-- name and a surname. The unit frames and nameplates are re-set by their
-- modules (their `nameFormat`, driven from here); the name the engine draws
-- over heads has ONE setting, the client's `UnitSurnameOwn` cvar ("show
-- player surname over head", the binary's only surname cvar): your own
-- name follows, other players' overhead names are the engine's and have
-- no setting (nameplates on shows them in the chosen form).
options[#options + 1] = { type = "header", name = "Names" }
options[#options + 1] = { type = "dropdown", key = "nameFormat", name = "Show Names As", values = {
	{ value = "first", label = "First name" },
	{ value = "last", label = "Last name" },
	{ value = "both", label = "First and last name" },
}, desc = "Which part of a character's name is shown, everywhere at once: the player, target, focus, pet, party and raid frames, the nameplates, and the name over your own head (the game's own setting for it; Last name shows both there). A character with no surname shows the name it has. Other players' names drawn over their heads without a nameplate are the engine's and have no setting." }
options[#options + 1] = { type = "subheader", name = "Names over other players' heads without a nameplate are the engine's: no setting reaches them" }

for _, tweak in ipairs(TWEAKS) do
	local key = "qol_" .. tweak[1]
	defaults[key] = true
	options[#options + 1] = { type = "header", name = tweak[2] }
	options[#options + 1] = { type = "toggle", key = key, name = tweak[3], desc = tweak[4] }
	options[#options + 1] = { type = "include", module = tweak[1], key = key }
end

local M = MelloUI:RegisterModule("UIModifications", {
	title = "UI Modifications",
	desc = "The painted kit reskin, area by area, and the per-area quality-of-life tweaks: nameplates, tooltips, chat, unit frames.",
	enabledByDefault = true,
	important = true,
	-- it drives every reskin panel and folded tweak, so its OFF state has to
	-- be applied at start-up too, not only when the switch is thrown
	applyWhenDisabled = true,
	defaults = defaults,
	options = options,
	headerButton = { name = "Reset positions",
		desc = "Forget every saved window position and scale: each window returns to the game's own place and size the next time it opens (open ones are closed now)." },
	headerToggle = { key = "unlock", name = "Unlock the Windows",
		desc = "Every window can be dragged by its title strip (the kit's title plate when the reskin is on), the minimap by its zone band, the tracker by its header, the damage meter by grabbing it and a chat window by a strip along its top edge (so its links and buttons keep working); the border lights up while it moves, a grid shows the screen's centre and the corner snaps lightly to it, and the mouse wheel while dragging scales it. Every drag area shows as a gold band while this is on, brighter under the mouse. Positions and scales stay, reloads included, and win over Edit Mode's for those elements. Works with the reskin off as well." },
})

--------------------------------------------------------------------------------
-- The window mover (user, 2026-09-21): while `unlock` is on, a kit window's
-- title plate is a drag handle; the outer rail is lit while it moves; the
-- position is saved and put back on every show and after the game's own
-- panel layout (UpdateUIPanelPositions), so it survives reloads.
--------------------------------------------------------------------------------

local movers = {}   -- [frame] = mover

local function SavedPosition(frame)
	local name = frame.GetName and frame:GetName()
	local db = M.db
	return name and db and db.positions and db.positions[name] or nil, name
end

local function PutBack(frame)
	local pos = SavedPosition(frame)
	if not pos or not M.isEnabled then
		return
	end
	local mover = movers[frame]
	local was = mover and mover.placing
	if mover then
		mover.placing = true
	end
	local ok = pcall(function()
		if pos.scale and pos.scale > 0 and frame.SetScale then
			mover = mover or movers[frame]
			if mover then
				mover.scaling = true
			end
			frame:SetScale(pos.scale)
			if mover then
				mover.scaling = nil
			end
		end
		frame:ClearAllPoints()
		-- the mover anchors BOTTOMLEFT to the screen's CENTRE; an entry
		-- carries the anchor only when it differs
		frame:SetPoint(pos.point or "BOTTOMLEFT", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
	end)
	if mover then
		mover.placing = was
	end
	if not ok then
		MelloUI:Notice("UI Modifications: could not place %s.", tostring(frame:GetName()))
	end
end

-- The lit rail: a tint can only darken painted iron, so the rails are
-- drawn ADDITIVELY while the window moves (the art adds its own light
-- to what is under it: a real glow, gold) — user, 2026-09-21: "500 %"
-- ... and an outer glow around the window while it moves (user,
-- 2026-09-21): four additive gold bands outside the window's edges, each
-- fading out away from it. Made once per window, shown only while dragging.
local GLOW = 28
local SNAP = 16   -- px: the light snap to the nearest grid line on release (each axis on its own)
local SCALE_STEP, SCALE_MIN, SCALE_MAX = 0.05, 0.5, 2   -- the wheel while dragging
-- The grab areas SHOW while the windows are unlocked (user, 2026-09-22):
-- nothing said where a window could be taken hold of, least of all now that
-- a grab is a strip and not the whole window. Each one is a gold wash with a
-- thin edge, brighter under the mouse. (The wash was hidden on 2026-09-21,
-- when a grab covered a whole window and the wash covered it with it.)
local WASH, WASH_LIT = 0.12, 0.25
local EDGE, EDGE_LIT = 0.45, 0.9
local STRIP = 22   -- px: the height of a grab that is only a strip along a window's top edge

local function OuterGlow(frame, mover)
	if mover.glow then
		return mover.glow
	end
	local glow = CreateFrame("Frame", nil, frame)
	glow:SetFrameStrata(frame:GetFrameStrata())
	glow:SetFrameLevel(math.max((frame:GetFrameLevel() or 1) - 1, 0))
	glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -GLOW, GLOW)
	glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", GLOW, -GLOW)
	glow:EnableMouse(false)
	local inner = CreateColor(1, 0.8, 0.3, 0.7)
	local outer = CreateColor(1, 0.8, 0.3, 0)
	local function Band(point1, point2, orientation, fromInner)
		local tex = glow:CreateTexture(nil, "BACKGROUND")
		tex:SetColorTexture(1, 1, 1, 1)
		tex:SetBlendMode("ADD")
		tex:SetPoint(point1[1], frame, point1[2], point1[3], point1[4])
		tex:SetPoint(point2[1], frame, point2[2], point2[3], point2[4])
		if fromInner then
			tex:SetGradient(orientation, inner, outer)
		else
			tex:SetGradient(orientation, outer, inner)
		end
		return tex
	end
	-- top: from the window's top edge upward (VERTICAL runs bottom -> top)
	Band({ "BOTTOMLEFT", "TOPLEFT", 0, 0 }, { "TOPRIGHT", "TOPRIGHT", 0, GLOW }, "VERTICAL", true)
	-- bottom: downward
	Band({ "TOPLEFT", "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, -GLOW }, "VERTICAL", false)
	-- left: leftward (HORIZONTAL runs left -> right)
	Band({ "TOPRIGHT", "TOPLEFT", 0, 0 }, { "BOTTOMLEFT", "BOTTOMLEFT", -GLOW, 0 }, "HORIZONTAL", false)
	-- right: rightward
	Band({ "TOPLEFT", "TOPRIGHT", 0, 0 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", GLOW, 0 }, "HORIZONTAL", true)
	glow:Hide()
	mover.glow = glow
	return glow
end

-- The rest of the screen darkens while a window moves, so the eye stays on
-- it (user, 2026-09-21): one black veil at the window's strata, at level 0
-- under everything drawn there — it dims the world and every lower strata.
local veil = nil

-- ... with a grid on it: a line every GRID px out from the screen's
-- centre, the two centre lines gold and brighter (user, 2026-09-21: "where
-- the middle of the screen is").
local GRID = 50

local function DrawGrid(parent)
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	if not (w and h) or w <= 0 or h <= 0 then
		return
	end
	local cx, cy = w / 2, h / 2
	local function Line(vertical, offset, centre)
		local tex = parent:CreateTexture(nil, "BORDER")
		if centre then
			tex:SetColorTexture(1, 0.82, 0, 0.55)
		else
			tex:SetColorTexture(1, 1, 1, 0.08)
		end
		if vertical then
			tex:SetSize(centre and 2 or 1, h)
			tex:SetPoint("TOP", parent, "TOPLEFT", cx + offset, 0)
		else
			tex:SetSize(w, centre and 2 or 1)
			tex:SetPoint("LEFT", parent, "BOTTOMLEFT", 0, cy + offset)
		end
	end
	local n = 1
	while n * GRID < cx do
		Line(true, n * GRID, false)
		Line(true, -n * GRID, false)
		n = n + 1
	end
	n = 1
	while n * GRID < cy do
		Line(false, n * GRID, false)
		Line(false, -n * GRID, false)
		n = n + 1
	end
	Line(true, 0, true)
	Line(false, 0, true)
end

-- The window's centre relative to the screen's centre, in UIParent units
-- (a panel the manager scaled has its own scale: GetCenter answers in
-- that, the grid is in UIParent's — the first snap landed off-centre, user
-- 2026-09-21), and the factor that turns a UIParent offset into the
-- frame's own anchor units.
-- The window's BOTTOM-LEFT corner (user, 2026-09-21: the corner is what
-- snaps) relative to the screen's centre, in UIParent units ...
local function CornerOffset(frame)
	local left, bottom = frame:GetLeft(), frame:GetBottom()
	local fs, us = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	if not (left and bottom and fs and us and sw and sh) or fs <= 0 or us <= 0 then
		return nil
	end
	local dx = (left * fs - sw / 2 * us) / us
	local dy = (bottom * fs - sh / 2 * us) / us
	return dx, dy, us / fs
end

-- The grid line an offset would snap to (nil: none within SNAP)
local function SnapTarget(offset)
	local nearest = math.floor(offset / GRID + 0.5) * GRID
	if math.abs(offset - nearest) <= SNAP then
		return nearest
	end
	return nil
end

local function Veil(frame, on)
	if on then
		if not veil then
			veil = CreateFrame("Frame", nil, UIParent)
			veil:SetAllPoints(UIParent)
			veil:EnableMouse(false)
			local tex = veil:CreateTexture(nil, "BACKGROUND")
			tex:SetAllPoints()
			tex:SetColorTexture(0, 0, 0, 0.6)
			pcall(DrawGrid, veil)
			-- the lines the window would snap to, lit while it is near them
			veil.hlX = veil:CreateTexture(nil, "ARTWORK")
			veil.hlX:SetColorTexture(1, 0.9, 0.4, 0.9)
			veil.hlX:SetSize(3, UIParent:GetHeight())
			veil.hlY = veil:CreateTexture(nil, "ARTWORK")
			veil.hlY:SetColorTexture(1, 0.9, 0.4, 0.9)
			veil.hlY:SetSize(UIParent:GetWidth(), 3)
		end
		veil:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
		veil:SetFrameLevel(0)
		veil.hlX:Hide()
		veil.hlY:Hide()
		-- the wheel is caught on the veil as well: a window scaled down
		-- slides out from under the cursor, which then no longer sits on
		-- the plate (user, 2026-09-21: could not scale back up)
		-- ... and the veil takes the mouse for the drag's duration: a wheel
		-- turn that reaches nothing zooms the camera (user, 2026-09-21); the
		-- button is held anyway, so no click is lost
		veil:EnableMouse(true)
		veil:EnableMouseWheel(true)
		veil:SetScript("OnMouseWheel", function(_, delta)
			if veil.onWheel then
				veil.onWheel(delta)
			end
		end)
		veil:SetScript("OnUpdate", function(self)
			local dx, dy = CornerOffset(frame)
			if not dx then
				return
			end
			local tx, ty = SnapTarget(dx), SnapTarget(dy)
			local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
			if tx then
				self.hlX:ClearAllPoints()
				self.hlX:SetPoint("TOP", self, "TOPLEFT", sw / 2 + tx, 0)
				self.hlX:Show()
			else
				self.hlX:Hide()
			end
			if ty then
				self.hlY:ClearAllPoints()
				self.hlY:SetPoint("LEFT", self, "BOTTOMLEFT", 0, sh / 2 + ty)
				self.hlY:Show()
			else
				self.hlY:Hide()
			end
		end)
		veil:Show()
	elseif veil then
		veil:SetScript("OnUpdate", nil)
		veil:EnableMouseWheel(false)
		veil:EnableMouse(false)
		veil.onWheel = nil
		veil:Hide()
	end
end

local function Light(shell, on, frame, mover)
	if frame then
		pcall(Veil, frame, on)
	end
	local outer = shell.outer
	if outer and outer.skin and outer.skin.art then
		for _, tex in ipairs(outer.skin.art) do
			if on then
				tex:SetBlendMode("ADD")
				tex:SetVertexColor(1, 0.85, 0.35)
			else
				tex:SetBlendMode("BLEND")
				tex:SetVertexColor(1, 1, 1)
			end
		end
	end
	if frame and mover then
		local ok, glow = pcall(OuterGlow, frame, mover)
		if ok and glow then
			glow:SetShown(on and true or false)
		end
	end
end

local AddHandle   -- below

local function MakeMover(frame, shell)
	local handle = shell.title and (shell.title.object or shell.title)
	local existing = movers[frame]
	if existing then
		-- a second registration for the window: the kit's shell for a
		-- window that already has its plain grab (its lit rail comes
		-- along), or the plain grab for a kit window — one mover, another
		-- handle (user, 2026-09-22: the mover works with the reskin off)
		existing.shell.outer = shell.outer or existing.shell.outer
		AddHandle(existing, handle)
		return
	end
	local usable = handle and handle.EnableMouse and handle.SetScript
	if not usable and not shell.outer then
		return
	end
	-- a shell may bring only its lit rail (`outer`) and leave the handle to
	-- the plain grab that the sweep makes: the mover is still built, and
	-- AddHandle below does nothing until there is one (user, 2026-09-22: the
	-- damage meter is dragged by its header, which only the sweep knows)
	local mover = { shell = shell, handles = {}, washes = {}, frame = frame }
	movers[frame] = mover
	-- the mouse wheel while dragging: the window's scale, 5 % a notch,
	-- 50 % .. 200 % (user, 2026-09-21), saved with the position
	local function Wheel(delta)
		if not mover.moving or not frame.SetScale then
			return
		end
		local ok, current = pcall(frame.GetScale, frame)
		if not ok or type(current) ~= "number" then
			return
		end
		local scale = math.max(SCALE_MIN, math.min(SCALE_MAX, current + delta * SCALE_STEP))
		if math.abs(scale - current) < 0.001 then
			return
		end
		-- the window stays glued to the cursor (user, 2026-09-21): the
		-- point under the cursor is kept under it — the drag is paused,
		-- the frame scaled, re-anchored so that point is back under the
		-- cursor, and the drag resumed (the button is still held)
		local okC, cx, cy = pcall(GetCursorPosition)
		local okR, left, bottom, w, h = pcall(frame.GetRect, frame)
		local fs = frame:GetEffectiveScale()
		mover.scaling = true
		if okC and okR and cx and left and w and h and w > 0 and h > 0 and fs and fs > 0 then
			local fx, fy = (cx / fs - left) / w, (cy / fs - bottom) / h
			frame:StopMovingOrSizing()
			frame:SetScale(scale)
			local fs2 = frame:GetEffectiveScale()
			if fs2 and fs2 > 0 then
				frame:ClearAllPoints()
				frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / fs2 - fx * w, cy / fs2 - fy * h)
			end
			frame:StartMoving()
		else
			frame:SetScale(scale)
		end
		mover.scaling = nil
		mover.scaled = scale
	end
	mover.Wheel = Wheel
	mover.DragStart = function()
		if not (M.isEnabled and M.db and M.db.unlock) then
			return
		end
		frame:SetMovable(true)
		frame:SetClampedToScreen(true)
		frame:StartMoving()
		mover.moving = true
		Light(shell, true, frame, mover)
		if veil then
			veil.onWheel = Wheel
		end
	end
	mover.DragStop = function()
		if not mover.moving then
			return
		end
		frame:StopMovingOrSizing()
		Light(shell, false, frame, mover)
		-- still "moving" through the snap and the save: the SetPoint hook
		-- below would otherwise put the window back to its PREVIOUS saved
		-- place the moment the snap anchors it (user, 2026-09-21: "does not
		-- snap on that spot")
		-- light snapping: a window released with its centre within SNAP px
		-- of a screen centre line is put on that line (each axis on its own)
		pcall(function()
			local dx, dy, k = CornerOffset(frame)
			if not dx then
				return
			end
			local tx, ty = SnapTarget(dx), SnapTarget(dy)
			if tx or ty then
				-- the corner onto the lit lines: anchored from the screen's
				-- centre by the snapped offsets, in the window's own units
				frame:ClearAllPoints()
				frame:SetPoint("BOTTOMLEFT", UIParent, "CENTER", (tx or dx) * k, (ty or dy) * k)
			end
		end)
		local _, name = SavedPosition(frame)
		if name and M.db then
			M.db.positions = M.db.positions or {}
			local ok, point, _, relPoint, x, y = pcall(frame.GetPoint, frame, 1)
			if ok and point and x and y then
				local okS, scale = pcall(frame.GetScale, frame)
				-- compact: the backup holds a few thousand characters for
				-- everything and a raw float took a third of a window's entry.
				-- A tenth of a pixel, the scale to a hundredth, the anchor
				-- only when it is not the mover's own BOTTOMLEFT to CENTER
				M.db.positions[name] = { point = point ~= "BOTTOMLEFT" and point or nil,
					relPoint = relPoint ~= "CENTER" and relPoint or nil,
					x = math.floor(x * 10 + 0.5) / 10, y = math.floor(y * 10 + 0.5) / 10,
					scale = (okS and type(scale) == "number" and math.abs(scale - 1) > 0.001) and (math.floor(scale * 100 + 0.5) / 100) or nil }
				-- the entries saved before this rounding, once
				for _, pos in pairs(M.db.positions) do
					if type(pos) == "table" then
						if type(pos.x) == "number" then pos.x = math.floor(pos.x * 10 + 0.5) / 10 end
						if type(pos.y) == "number" then pos.y = math.floor(pos.y * 10 + 0.5) / 10 end
						if type(pos.scale) == "number" then pos.scale = math.floor(pos.scale * 100 + 0.5) / 100 end
						if pos.point == "BOTTOMLEFT" then pos.point = nil end
						if pos.relPoint == "CENTER" then pos.relPoint = nil end
					end
				end
				-- through the setting path, so the backup this client's saved
				-- variables rely on is written (a plain write was lost on
				-- reload — user, 2026-09-21)
				MelloUI:NotifySettingChanged(M.name, "positions", M.db.positions)
			end
		end
		mover.moving = nil
	end
	frame:HookScript("OnShow", function()
		PutBack(frame)
	end)
	-- whoever re-anchors the window (the panel manager on show, the bag
	-- layout, a page's own code), it goes back where it was put — right
	-- after that SetPoint, never during a drag or our own placing
	hooksecurefunc(frame, "SetPoint", function()
		if mover.moving or mover.placing then
			return
		end
		if SavedPosition(frame) then
			mover.placing = true
			PutBack(frame)
			mover.placing = nil
		end
	end)
	if frame.SetScale then
		hooksecurefunc(frame, "SetScale", function()
			if mover.moving or mover.placing or mover.scaling then
				return
			end
			local pos = SavedPosition(frame)
			if pos and pos.scale then
				mover.placing = true
				PutBack(frame)
				mover.placing = nil
			end
		end)
	end
	mover.SetUnlocked = function(on)
		mover.unlocked = on and true or false
		for h in pairs(mover.handles) do
			h:EnableMouse(mover.unlocked)
			h:EnableMouseWheel(mover.unlocked)
		end
		for _, wash in ipairs(mover.washes) do
			wash:SetShown(mover.unlocked)
		end
	end
	AddHandle(mover, handle)
	mover.SetUnlocked(M.isEnabled and M.db and M.db.unlock)
	PutBack(frame)
end

-- What a grab area looks like while the windows are unlocked: a gold wash
-- inside a thin gold edge, both brighter while the mouse is on it. The
-- textures are made once and shown with the unlocked state.
local function HandleWash(mover, handle)
	local fill = handle:CreateTexture(nil, "OVERLAY", nil, 7)
	fill:SetAllPoints(handle)
	fill:SetColorTexture(1, 0.82, 0, WASH)
	local edges = {}
	local function Edge(a, b, w, h)
		local t = handle:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetColorTexture(1, 0.82, 0, EDGE)
		t:SetPoint(a, handle, a)
		t:SetPoint(b, handle, b)
		if w then
			t:SetWidth(w)
		end
		if h then
			t:SetHeight(h)
		end
		edges[#edges + 1] = t
	end
	Edge("TOPLEFT", "TOPRIGHT", nil, 1)
	Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
	Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
	Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
	local function Lit(on)
		fill:SetColorTexture(1, 0.82, 0, on and WASH_LIT or WASH)
		for _, edge in ipairs(edges) do
			edge:SetColorTexture(1, 0.82, 0, on and EDGE_LIT or EDGE)
		end
	end
	-- hooked, not set: a handle that is a kit plate has its own scripts
	pcall(handle.HookScript, handle, "OnEnter", function()
		Lit(mover.unlocked)
	end)
	pcall(handle.HookScript, handle, "OnLeave", function()
		Lit(false)
	end)
	fill:Hide()
	mover.washes[#mover.washes + 1] = fill
	for _, edge in ipairs(edges) do
		edge:Hide()
		mover.washes[#mover.washes + 1] = edge
	end
end

-- A drag handle of a mover: the drag and wheel scripts on it, the mouse
-- only while unlocked.
AddHandle = function(mover, handle)
	if not (handle and handle.EnableMouse and handle.SetScript) or mover.handles[handle] then
		return
	end
	mover.handles[handle] = true
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnMouseWheel", function(_, delta)
		if mover.moving then
			mover.Wheel(delta)
			return
		end
		-- not dragging: the wheel is the window's (a chat frame scrolls on
		-- it — user, 2026-09-22: could not scroll the chat while unlocked)
		local target = mover.frame
		local script = target and target.GetScript and target:GetScript("OnMouseWheel")
		if script then
			pcall(script, target, delta)
		end
	end)
	handle:SetScript("OnDragStart", mover.DragStart)
	handle:SetScript("OnDragStop", mover.DragStop)
	HandleWash(mover, handle)
	handle:EnableMouse(mover.unlocked and true or false)
	handle:EnableMouseWheel(mover.unlocked and true or false)
	for _, wash in ipairs(mover.washes) do
		wash:SetShown(mover.unlocked and true or false)
	end
end

--------------------------------------------------------------------------------
-- Plain windows (user, 2026-09-22): the mover works with the reskin off.
-- Every window the kit dresses, the interaction windows and the HUD elements
-- get a grab area of their own whether or not a kit panel is on: an
-- invisible frame over the game's title strip (the HUD's band / header /
-- body), mouse-enabled only while unlocked. A kit shell registered for the
-- same window adds its lit rail and its plate as a second handle. Windows
-- loaded on demand are picked up when the game lays its panels out.
--------------------------------------------------------------------------------

local PLAIN_WINDOWS = {
	"CharacterFrame", "PlayerSpellsFrame", "ProfessionsFrame", "ProfessionsBookFrame", "CollectionsJournal",
	"PVEFrame", "CommunitiesFrame", "FriendsFrame", "WorldMapFrame", "LegacySystemFrame", "ContainerFrameCombinedBags",
	"MerchantFrame", "GossipFrame", "QuestFrame", "MailFrame", "BankFrame", "TradeFrame", "MacroFrame", "TaxiFrame",
	"MelloUIConfigFrame",
}
-- HUD elements: the frame, the region its grab covers, a control to stop
-- short of, and how the grab sits on the region ("strip" = the top edge only)
local PLAIN_HUD = {
	{ "MinimapCluster", function(f) return f.BorderTop or f end },
	{ "ObjectiveTrackerFrame", function(f) return f.Header or f end, function(f) return f.Header and f.Header.MinimizeButton end },
	-- the damage meter is dragged by its HEADER, not by its list (user,
	-- 2026-09-22: "the damage meter should be dragable by the windows
	-- header, not the Bar"). The header's controls sit at both ends of the
	-- band -- the timer and the type dropdown on the left, the session
	-- dropdown, the cog and the minimize button on the right -- so the grab
	-- is the span BETWEEN them, over the title, and every control keeps its
	-- clicks (2026-09-21).
	{ "DamageMeter", function(f)
		local win = f.GetPrimarySessionWindow and f:GetPrimarySessionWindow()
		return win and win.Header or nil
	end, function(f)
		local win = f.GetPrimarySessionWindow and f:GetPrimarySessionWindow()
		if not win then
			return nil
		end
		return { left = win.DamageMeterTypeDropdown or win.SessionTimer,
			right = win.SessionDropdown or win.SettingsDropdown or win.MinimizeButton }
	end, "between" },
}
local plainGrabs = {}   -- [frame] = grab

local function PlainGrab(frame, region, avoid, avoidSide)
	local grab = CreateFrame("Frame", nil, frame)
	if avoidSide == "between" and type(avoid) == "table" then
		-- the span between two controls, over the region's full height: a
		-- header band whose ends are buttons is grabbed in the middle
		local band = region or frame
		grab:SetPoint("TOP", band, "TOP")
		grab:SetPoint("BOTTOM", band, "BOTTOM")
		grab:SetPoint("LEFT", avoid.left or band, avoid.left and "RIGHT" or "LEFT", avoid.left and 2 or 0, 0)
		grab:SetPoint("RIGHT", avoid.right or band, avoid.right and "LEFT" or "RIGHT", avoid.right and -2 or 0, 0)
	elseif avoidSide == "strip" then
		-- a strip along the top edge and nothing more: a grab over a whole
		-- window body takes every click and wheel turn under it while the
		-- windows are unlocked, and a chat window's links, scroll buttons and
		-- wheel die with it (user, 2026-09-22; the wheel alone was forwarded
		-- once before, the clicks could not be)
		grab:SetPoint("TOPLEFT", region or frame, "TOPLEFT")
		grab:SetPoint("TOPRIGHT", region or frame, "TOPRIGHT")
		grab:SetHeight(STRIP)
	elseif region and region ~= frame or (region == frame and avoid) then
		grab:SetAllPoints(region)
		if avoid then
			-- a button on the region keeps its clicks while unlocked: the
			-- grab stops short of it — at its left edge (the tracker's
			-- minimize, at the header's right end) or above its top (the
			-- chat's scroll arrow, in the bottom-right corner: the bottom
			-- strip is left out) — user, 2026-09-22
			grab:ClearAllPoints()
			if avoidSide == "bottom" then
				grab:SetPoint("TOPLEFT", region, "TOPLEFT")
				grab:SetPoint("BOTTOMRIGHT", avoid, "TOPRIGHT", 0, 2)   -- no edge set twice
			else
				grab:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT")
				grab:SetPoint("TOPRIGHT", avoid, "TOPLEFT", -2, 0)
			end
		end
	elseif frame.TitleContainer then
		grab:SetAllPoints(frame.TitleContainer)   -- the game's title strip, short of the close button
	elseif region == frame then
		grab:SetAllPoints(frame)
	else
		grab:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, 0)
		grab:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -28, -24)
	end
	grab:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
	grab:EnableMouse(false)
	plainGrabs[frame] = grab
	return grab
end

local function SweepPlain()
	if not M.isEnabled then
		return
	end
	local function Attach(frame, region, avoid, avoidSide)
		if type(frame) == "table" and type(frame.GetObjectType) == "function" and not plainGrabs[frame]
			and not (frame.IsForbidden and frame:IsForbidden()) then
			local ok, grab = pcall(PlainGrab, frame, region, avoid, avoidSide)
			if ok and grab then
				MakeMover(frame, { title = grab })
			end
		end
	end
	for _, name in ipairs(PLAIN_WINDOWS) do
		Attach(_G[name], nil)
	end
	for _, entry in ipairs(PLAIN_HUD) do
		local frame = _G[entry[1]]
		if frame then
			local ok, region = pcall(entry[2], frame)
			local okA, avoid = pcall(entry[3] or function() return nil end, frame)
			if ok and region then
				Attach(frame, region, okA and avoid or nil, entry[4])
			end
		end
	end
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		if frame then
			Attach(frame, frame, nil, "strip")   -- a chat window is grabbed by a strip along its top edge; the messages under it keep their links, buttons and wheel
		end
	end
end

local sweepFrame = CreateFrame("Frame")
sweepFrame:RegisterEvent("ADDON_LOADED")
sweepFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
sweepFrame:SetScript("OnEvent", function()
	SweepPlain()
end)

--------------------------------------------------------------------------------
-- The unlocked state has to say so (user, 2026-09-22): it is kept across
-- sessions, nothing on screen showed it, and the grab areas take the mouse
-- while it is on -- a UI that quietly stops answering the mouse in places.
-- A plate at the top of the screen names the state and locks again when it
-- is clicked.
--------------------------------------------------------------------------------

local ApplyUnlock   -- below
local banner

local function UnlockBanner(on)
	if not on then
		if banner then
			banner:Hide()
		end
		return
	end
	if not banner then
		banner = CreateFrame("Button", "MelloUIUnlockedNotice", UIParent)
		banner:SetSize(420, 32)
		banner:SetPoint("TOP", UIParent, "TOP", 0, -150)
		banner:SetFrameStrata("DIALOG")
		banner:SetClampedToScreen(true)
		local back = banner:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints(banner)
		back:SetColorTexture(0, 0, 0, 0.75)
		-- drawn from plain textures, never a backdrop: this sits over the HUD
		local function Line(a, b, w, h)
			local t = banner:CreateTexture(nil, "BORDER")
			t:SetColorTexture(1, 0.82, 0, 0.5)
			t:SetPoint(a, banner, a)
			t:SetPoint(b, banner, b)
			if w then
				t:SetWidth(w)
			end
			if h then
				t:SetHeight(h)
			end
		end
		Line("TOPLEFT", "TOPRIGHT", nil, 1)
		Line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
		Line("TOPLEFT", "BOTTOMLEFT", 1, nil)
		Line("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
		local text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		text:SetPoint("CENTER", banner, "CENTER", 0, 0)
		text:SetText("Windows unlocked: drag a gold band, wheel to scale.  |cffffd200Click here to lock them|r")
		banner:SetScript("OnClick", function()
			-- the setting itself is changed, so the configurator's toggle and
			-- the grabs follow through OnSettingChanged
			MelloUI:NotifySettingChanged(M.name, "unlock", false)
			if MelloUI.RefreshConfig then
				MelloUI:RefreshConfig()
			end
			MelloUI:Print("Windows locked.")
		end)
	end
	banner:Show()
end

ApplyUnlock = function(on)
	for _, mover in pairs(movers) do
		mover.SetUnlocked(on)
	end
	UnlockBanner(on and M.isEnabled and true or false)
end

-- Reset positions (the header button): the saved places and scales are
-- forgotten, every moved window goes back to scale 1 and, if open, is
-- closed so the game lays it out afresh on its next show.
local function ResetPositions()
	if not M.db then
		return
	end
	local positions = M.db.positions or {}
	for frame, mover in pairs(movers) do
		local name = frame.GetName and frame:GetName()
		if name and positions[name] then
			mover.placing = true
			pcall(function()
				if frame.SetScale then
					mover.scaling = true
					frame:SetScale(1)
					mover.scaling = nil
				end
				if frame:IsShown() then
					frame:Hide()
				end
			end)
			mover.placing = nil
		end
	end
	M.db.positions = {}
	MelloUI:NotifySettingChanged(M.name, "positions", M.db.positions)
	MelloUI:Print("UI Modifications: window positions and scales reset.")
end
M.headerButton.onClick = ResetPositions

local Kit = MelloUI.Kit
if Kit and Kit.OnShell then
	Kit:OnShell(function(frame, shell)
		MakeMover(frame, shell)
	end)
end
-- the plain grabs first, so the kit's plate is the second handle and the
-- plain one stays when the kit goes off
-- the game lays its panels out again on every show / hide of one, and the
-- bags on every open (UpdateContainerFrameAnchors — the backpack went back
-- to its default place after a reload, user 2026-09-21): ours go back where
-- they were put after each of those
local function PutBackShown()
	SweepPlain()   -- a window loaded on demand gets its grab here
	for frame in pairs(movers) do
		if frame:IsShown() then
			PutBack(frame)
		end
	end
end
for _, fn in ipairs({ "UpdateUIPanelPositions", "UpdateContainerFrameAnchors" }) do
	if type(_G[fn]) == "function" then
		hooksecurefunc(fn, PutBackShown)
	end
end

local function PanelWanted(db, name)
	return db.reskin ~= false and db[name] ~= false
end

-- During Core's start-up pass the driven modules must come up in TOC order
-- (Bar Textures before the unit frame panel, and so on): only their flags
-- are set then, and Core enables each in its turn; afterwards (a switch on
-- the page) they are switched at once.
local function Want(name, wanted)
	if MelloUI.initializingModules then
		MelloUI.db.enabled[name] = wanted and true or false
	else
		MelloUI:SetModuleEnabled(name, wanted)
	end
end

-- Is there anything at all for the umbrella to do? Every area and every
-- tweak switched off is a real choice (the window mover and the name format
-- work without the reskin), so it is never undone behind your back -- but it
-- is worth saying, because the switch then looks like it does nothing.
function NothingWanted(db)
	for _, area in ipairs(PANELS) do
		if area[1] and db[area[1]] ~= false then
			return false
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		if db["qol_" .. tweak[1]] ~= false then
			return false
		end
	end
	return true
end

-- Put every area and tweak back on, for the button on the page. Returns how
-- many were off.
function RestoreAreas(db)
	local count = 0
	local function put(key)
		if db[key] == false then
			db[key] = true
			count = count + 1
			MelloUI:NotifySettingChanged(M.name, key, true)
		end
	end
	for _, area in ipairs(PANELS) do
		if area[1] then
			put(area[1])
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		put("qol_" .. tweak[1])
	end
	return count
end

function Apply(db, on)
	local wanted = {}
	for _, area in ipairs(PANELS) do
		local name = area[1]
		if name and MelloUI:GetModule(name) then
			wanted[name] = on and PanelWanted(db, name) or false
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		local name = tweak[1]
		if MelloUI:GetModule(name) then
			wanted[name] = on and db["qol_" .. name] ~= false
		end
	end
	-- in TOC order on every path (Bar Textures before the unit frame panel
	-- when the umbrella is switched on from its tile as well, not only in
	-- Core's start-up pass; audit, 2026-09-22)
	for name in MelloUI:IterateModules() do
		if wanted[name] ~= nil then
			Want(name, wanted[name])
		end
	end
end

-- The driven modules are hidden from the configurator; done once every
-- module is registered (this file loads before them, see the TOC).
function M:OnInit()
	for _, area in ipairs(PANELS) do
		local module = area[1] and MelloUI:GetModule(area[1])
		if module then
			module.hidden = true
		end
	end
	for _, tweak in ipairs(TWEAKS) do
		local module = MelloUI:GetModule(tweak[1])
		if module then
			module.hidden = true
		end
	end
end

-- The name form to the two modules and the engine's own-name cvar.
local SURNAME_CVAR = "UnitSurnameOwn"

local function HasCVar(name)
	if not (C_CVar and C_CVar.GetCVarInfo) then
		return false
	end
	local ok, value = pcall(C_CVar.GetCVarInfo, name)
	return ok and value ~= nil
end

local function ApplyNameFormat(db, on)
	local mode = on and (db.nameFormat or "both") or "both"
	for _, name in ipairs({ "UnitFrames", "Nameplates" }) do
		local module = MelloUI:GetModule(name)
		if module then
			MelloUI:NotifySettingChanged(name, "nameFormat", mode)
		end
	end
	if HasCVar(SURNAME_CVAR) then
		if on then
			if db.savedSurnameOwn == nil then
				local ok, current = pcall(C_CVar.GetCVar, SURNAME_CVAR)
				db.savedSurnameOwn = (ok and current) and tostring(current) or "1"
			end
			pcall(C_CVar.SetCVar, SURNAME_CVAR, mode == "first" and "0" or "1")
		elseif db.savedSurnameOwn ~= nil then
			pcall(C_CVar.SetCVar, SURNAME_CVAR, db.savedSurnameOwn)
			db.savedSurnameOwn = nil
		end
	end
end

-- The reskin switched on by the user (the umbrella from its tile or the
-- reskin toggle; not Core's start-up pass): Custom Sounds comes on with it,
-- and the Edit Mode layout the reskin is drawn for is put in place once
-- (user, 2026-09-22: "if people enable the reskin, it should only auto
-- enable the full reskin and the custom sounds, but it needs to load my
-- current UI layout").
local function ReskinOn(db)
	if MelloUI.initializingModules or not MelloUI.initialized or not db.reskin then
		return
	end
	if MelloUI:GetModule("CustomSounds") and not MelloUI:IsModuleEnabled("CustomSounds") then
		MelloUI:SetModuleEnabled("CustomSounds", true)
		MelloUI:Print("Custom Sounds switched on with the reskin.")
	end
	if not db.layoutApplied and MelloUI.ApplyEditModeLayout then
		local ok, why = MelloUI:ApplyEditModeLayout()
		if ok then
			db.layoutApplied = true
			MelloUI:NotifySettingChanged(M.name, "layoutApplied", true)
		elseif why and not why:find("no layout is baked", 1, true) then
			MelloUI:Print("Edit Mode layout: %s", why)
		end
	end
	if MelloUI.RefreshConfig then
		MelloUI:RefreshConfig()
	end
end

function M:OnEnable(db)
	self.db = db
	if db.reskin ~= false and NothingWanted(db) then
		MelloUI:Notice("UI Modifications is on, but every area of the reskin is switched off, so the game's own art is what you see. Its page has a \"Switch every area on\" button.")
	end
	Apply(db, true)
	SweepPlain()
	ApplyUnlock(db.unlock)
	for frame in pairs(movers) do
		PutBack(frame)
	end
	ApplyNameFormat(db, true)
	ReskinOn(db)
end

function M:OnDisable(db)
	db = db or self.db or {}
	Apply(db, false)
	ApplyUnlock(false)
	ApplyNameFormat(db, false)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "unlock" then
		ApplyUnlock(value)
		return
	elseif key == "positions" or key == "layoutApplied" or key == "welcomeAsked" or key == "savedSurnameOwn" then
		return
	elseif key == "nameFormat" then
		ApplyNameFormat(db, true)
		return
	elseif key == "reskin" then
		Apply(db, true)
		if value then
			ReskinOn(db)
		end
	elseif key:sub(1, 4) == "qol_" then
		local name = key:sub(5)
		if MelloUI:GetModule(name) then
			MelloUI:SetModuleEnabled(name, value and true or false)
		end
	elseif MelloUI:GetModule(key) then
		MelloUI:SetModuleEnabled(key, PanelWanted(db, key))
	end
end
