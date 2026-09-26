--------------------------------------------------------------------------------
-- MelloUI - Quest Tracker
--
-- A tracker of MelloUI's own in the game's tracker's place, that SCROLLS
-- (player feedback, 2026-09-23: "Quest Tracker under minimap is static and
-- you cant scroll down or up"; user: "start building the scrollable
-- tracker"). The game's tracker on this client lays out only the quests that
-- fit its Edit Mode height and has no scrolling; changing what it lays out
-- would be running its tracker code from here (taint), so it is switched off
-- and this one stands in:
--
--   * the game's tracker is hidden with the game's own secure visibility
--     driver (and alpha 0 against a flash), only out of combat; it comes
--     back while Edit Mode is open, so it can still be moved and sized there,
--     and this tracker takes its place and height from it
--   * the watched quests with their objectives, coloured by difficulty,
--     rebuilt at most once a frame after the quest events
--   * the list scrolls with the mouse wheel inside a clipping frame (no
--     ScrollFrame): the content is re-anchored by the offset, the offset is
--     kept across rebuilds, and a thumb shows where the view is
--   * click a quest to follow it (super-track), Shift-click to stop watching
--     it, right-click to open it in the quest log; a quest item is used with
--     a click out of combat, through ONE secure button laid over the item
--     under the mouse -- nothing secure lives in the list, so it scrolls and
--     rebuilds in combat too
--   * the painted kit's look (the single rail, the stone, a parchment sheet
--     and the title plate) while its look area is on (Kit:IsOn: the reskin
--     and its own switch), a plain dark panel otherwise; a switch flips it
--     live
--   * as wide on the screen as the minimap (Match The Minimap's Width): the
--     map's size is Edit Mode's, the tracker follows it (FollowWidth)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("QuestTracker")
local C_Timer = Perf.C_Timer

local M = MelloUI:RegisterModule("QuestTracker", {
	title = "Quest Tracker",
	desc = "A quest tracker in the game's tracker's place that scrolls with the mouse wheel, so every watched quest can be reached.",
	icon = "Interface\\Icons\\INV_Misc_Book_08",
	flavour = "Every watched quest within reach: the tracker scrolls when the list runs long.",
	group = "Quests and travel", navOrder = 4,
	role = "replaces",   -- (the game's objective tracker; it has a window but is not a hidden kit panel)
	-- its own kit switch on UI Modifications' Windows tab (a setting there,
	-- not the Objective tracker's: audit, 2026-09-24, rank 1), read by
	-- Kit:IsOn("questTracker")
	window = { label = "Quest Tracker", desc = "MelloUI's scrollable quest tracker under the minimap in the kit. The Objective tracker row dresses the game's own tracker.", tab = "Windows", order = 6,
		switch = "questTrackerKit" },
	area = { key = "questTracker" },
	enabledByDefault = false,
	-- where the layout fit hung the game's tracker (Unplaced, below): this
	-- machine's fact, never in a profile, never set by a setup
	keep = { "fitAnchor", "fitAnchorWas" },
	defaults = {
		-- the user's settings, 2026-09-23 ("Height 500 by default, width 300,
		-- scale 100%, font size 13 and scroll step 25"); 0 in Height / Width
		-- still means the game's tracker's size
		maxHeight = 500,
		width = 300,
		-- the width follows the minimap's (layout E, user, 2026-09-25: "yes,
		-- flip it": the map's size is Edit Mode's, the tracker follows it)
		matchMinimap = true,
		scale = 1,
		textSize = 13,
		headerSize = 16,
		scrollStep = 25,
		itemButtons = true,
		collapsed = false,
	},
	options = {
		{ type = "header", name = "Tracker" },
		{ type = "slider", key = "maxHeight", name = "Height", min = 0, max = 900, step = 20,
		  format = function(v) v = math.floor(v + 0.5) return v == 0 and "Edit Mode's" or tostring(v) end,
		  desc = "How tall the tracker may grow before it scrolls. Edit Mode's: the height set for the game's tracker in Edit Mode. The grip in its bottom-left corner sets it by dragging." },
		{ type = "toggle", key = "matchMinimap", name = "Match The Minimap's Width",
		  desc = "The tracker as wide on the screen as the minimap: the round map's width, or the square map's frame. Make the minimap bigger or smaller in Edit Mode (Minimap, Size) and the tracker follows. Needs the Minimap Kit. Off: the Width below." },
		{ type = "slider", key = "width", name = "Width", min = 0, max = 600, step = 10,
		  format = function(v) v = math.floor(v + 0.5) return v == 0 and "Edit Mode's" or tostring(v) end,
		  desc = "How wide the tracker is when it does not match the minimap's width. Edit Mode's: as wide as the game's tracker. The grip in its bottom-left corner sets width and height by dragging (only the height while it matches the minimap)." },
		{ type = "slider", key = "scale", name = "Scale", min = 0.6, max = 1.6, step = 0.05, percent = true,
		  desc = "The size of the whole tracker, text and frame together." },
		{ type = "slider", key = "textSize", name = "Text Size", min = 10, max = 20, step = 1,
		  format = function(v) return tostring(math.floor(v + 0.5)) end,
		  desc = "The size of the quest titles and the section headers; the objectives are one size smaller." },
		{ type = "slider", key = "headerSize", name = "Header Text Size", min = 10, max = 24, step = 1,
		  format = function(v) return tostring(math.floor(v + 0.5)) end,
		  desc = "The size of the tracker's title, All Objectives (in the Fonts module's title face while the reskin is on, which draws it larger)." },
		{ type = "slider", key = "scrollStep", name = "Scroll Step", min = 10, max = 120, step = 5,
		  format = function(v) return tostring(math.floor(v + 0.5)) end,
		  desc = "How far one turn of the mouse wheel scrolls." },
		{ type = "toggle", key = "itemButtons", name = "Quest Items",
		  desc = "Show a quest's usable item beside it. A click uses it out of combat." },
		{ type = "button", name = "Reset Position", text = "Reset",
		  hint = "back on the game's tracker's place",
		  onClick = function(_, db)
			db.pos = nil
			MelloUI:NotifySettingChanged("QuestTracker", "pos", nil)
		  end },
	},
})

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua); Plain(v)
-- is v, or nil when v is secret
local Secret = MelloUI.Safe.IsSecret
local Plain = MelloUI.Safe.Value

--------------------------------------------------------------------------------
-- Layout constants
--------------------------------------------------------------------------------

local HEADER_H = 28          -- the title plate
local INSET = 10             -- the frame's padding round the list
local THUMB_W = 8            -- the scroll thumb's width, and the room kept for it
-- the game's tracker's look (user, 2026-09-23: "format the text ... as the
-- default one"): a column for the quest's map button, the titles past it,
-- each objective's dash in a column of its own with the text hanging past it
local BLOCK_GAP = 10         -- between two quests
local LINE_GAP = 3           -- between an objective and the next
local TITLE_GAP = 4          -- between a title and its first line
local TEXT_X = 28            -- the titles' left edge, past the map button's column
local BULLET_X = 8           -- an objective's dash (and a turn-in line), from TEXT_X
local LINE_X = 20            -- an objective's text, from TEXT_X: past the dash
local ITEM_SIZE = 26         -- a quest item's button
local PIP_SIZE = 9           -- a difficulty pip on parchment (QuestInk)
local FALLBACK_W, FALLBACK_H = 260, 520

--------------------------------------------------------------------------------
-- The game's tracker: off while ours is on, back in Edit Mode
--------------------------------------------------------------------------------

local gameHidden = false
local savedAlpha = nil
local inEditMode = false
local pendingGame = nil      -- true / false: hide / show once the fight is over

local combatWatcher = CreateFrame("Frame")

local function SetGameTracker(hide)
	local f = ObjectiveTrackerFrame
	if not f or gameHidden == hide then
		return
	end
	if InCombatLockdown() then
		pendingGame = hide
		combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	pendingGame = nil
	if hide then
		savedAlpha = Plain(f:GetAlpha()) or 1
		f:SetAlpha(0)
		RegisterStateDriver(f, "visibility", "hide")
	else
		RegisterStateDriver(f, "visibility", "show")
		UnregisterStateDriver(f, "visibility")
		f:SetAlpha(savedAlpha or 1)
	end
	gameHidden = hide
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

local frame, header, clip, content, thumb, track
local scrollOffset = 0
local contentHeight = 0
local blocks = {}            -- [questID] = block, kept across rebuilds
local freeBlocks = {}
local dirty = false
local sizing = false          -- the grip is being dragged: no rebuild resizes the frame meanwhile
local lastProgress = {}       -- [questID or "r<recipe>"] = { [line] = count }: what each line last showed
local lastComplete = {}       -- [questID] = true once it was ready to turn in
local Scroll                  -- below

-- the height allowed: the set Height (else the game's tracker's), but never
-- past the bottom of the screen (user, 2026-09-24: at a larger UI Scale the
-- 500 of the Height ran off the screen) -- the room from the tracker's top
-- down to the screen's edge, in its own units
local SCREEN_MARGIN = 8

local function SetOrGameHeight()
	local h = tonumber(M.db and M.db.maxHeight) or 0
	if h > 0 then
		return h
	end
	local f = ObjectiveTrackerFrame
	local ok, gh = pcall(function() return f and f:GetHeight() end)
	gh = ok and Plain(gh) or nil
	if gh and gh > HEADER_H * 2 then
		return gh
	end
	return FALLBACK_H
end

local function MaxHeight()
	local h = SetOrGameHeight()
	local ok, top = pcall(function() return frame and frame:GetTop() end)
	top = ok and Plain(top) or nil
	if top and top > HEADER_H * 2 then
		h = math.min(h, top - SCREEN_MARGIN)
	end
	return h
end

-- the width the last Place laid while it followed the minimap (Match The
-- Minimap's Width, below Place's column drop), in its own units; nil while
-- it does not
local followW = nil

-- the tracker's OWN width: the minimap's it follows, a set width, else what
-- its two anchors on the game's tracker give it (in its own units -- the
-- game's tracker may be scaled by the window mover, and its width is then
-- not ours: the lines ran past the list and were cut, user screenshot
-- 2026-09-23)
local function FrameWidth()
	local set = followW or tonumber(M.db and M.db.width) or 0
	if set > 0 then
		return set
	end
	local ok, w = pcall(function() return frame and frame:GetWidth() end)
	w = ok and Plain(w) or nil
	if w and w > 100 then
		return w
	end
	local f = ObjectiveTrackerFrame
	local okG, gw = pcall(function() return f and f:GetWidth() end)
	gw = okG and Plain(gw) or nil
	if gw and gw > 100 then
		return gw
	end
	return FALLBACK_W
end

local function ContentWidth()
	return FrameWidth() - INSET * 2 - THUMB_W - 4
end

-- What the last Place laid the frame by (audit, 2026-09-24: Place runs on
-- every setting of the tracker -- a header's collapse, a section switched --
-- and each time it laid every background in the UI again): asked for the
-- same scale and the same place again, it leaves the frame as it is. A drag
-- of the grip or of the mover leaves the frame's points to the game: the
-- last one is forgotten then (last.valid = false), and the next Place lays
-- the frame again. Kept only once a Place is through, and checked against
-- the frame itself -- its first point and its scale as it reads them back --
-- so a Place that stopped part way, or a frame put elsewhere or scaled by
-- anything else, is laid again by the next setting, as before (review,
-- 2026-09-24). A frame whose point cannot be read plainly is always laid.
-- scale, set, x, y, to, us, sw, sh, gw, drop: the inputs it was laid by; p,
-- rel, rp, ax, ay, got: its first point and its scale, read back once laid
local last = { valid = false }

-- the frame's first point as the last Place read it back (a drag hangs it
-- from the screen, by another corner)
local function SamePoint()
	local ok, p, rel, rp, ax, ay = pcall(frame.GetPoint, frame, 1)
	if not ok or Secret(p) or Secret(rel) or Secret(rp) or Secret(ax) or Secret(ay) then
		return false
	end
	return p == last.p and rel == last.rel and rp == last.rp and ax == last.ax and ay == last.ay
end

-- Under the minimap's column (audit, 2026-09-24, rank 18; user, 2026-09-25:
-- "the Quest Tracker is the one sitting under the Minimap"). Only where
-- nobody placed it: no place of its own, and the game's tracker on Edit
-- Mode's default place and not moved by the window mover (or, without the
-- game's tracker, the stand-in spot). There it is kept clear of the bottom
-- of the column under the minimap (MinimapPanel's: the map, the Services
-- bar, the Route line) when the column stands over it: hung COLUMN_GAP below
-- it, never above the game's place. Placed by the user in any way (the
-- user's own layout places the game's tracker in Edit Mode), it follows that
-- exactly as before. The game's tracker is only read, never anchored (an
-- Edit Mode system). The title plate reaches about 4.6 of its units above
-- the frame (38 on the 28 header, its caps' paint from 1 px down), inside
-- the gap, so its paint stays clear of the column's too.
local COLUMN_GAP = 8

-- The layout fit's own place (user, 2026-09-26: the tracker must never sit
-- on the Services row): the installer's fit hangs the game's tracker right
-- under the minimap column (Edit Mode 12:-1), and Edit Mode counts that as
-- moved, so the keep-clear stopped after an install. Recorded when the
-- fitted layout goes in (the bus's 'installer', below: M.db.fitAnchor, the
-- anchor as Edit Mode saved it) and counted as nobody's place while the
-- game's tracker still hangs exactly there: a later minimap Size, Services'
-- Button Layout or Merge, or UI Scale keeps it under the column. Moved in
-- Edit Mode or by the window mover, it is the player's place again.
local ANCHOR_EPS = 0.5   -- units: Edit Mode keeps the offsets as the fit wrote them (a tenth)

local function FitPlace(f)
	local rec = M.db and M.db.fitAnchor
	if type(rec) ~= "table" or type(rec.x) ~= "number" or type(rec.y) ~= "number" then
		return false
	end
	local okN, n = pcall(f.GetNumPoints, f)
	if not okN or Secret(n) or n ~= 1 then
		return false
	end
	local ok, p, rel, rp, x, y = pcall(f.GetPoint, f, 1)
	if not ok or Secret(p) or Secret(rel) or Secret(rp) or Secret(x) or Secret(y) then
		return false
	end
	return p == rec.point and rp == rec.relativePoint and rel == _G[rec.relativeTo or "UIParent"]
		and type(x) == "number" and type(y) == "number"
		and math.abs(x - rec.x) <= ANCHOR_EPS and math.abs(y - rec.y) <= ANCHOR_EPS
end

local function Unplaced(f)
	if not f then
		return true
	end
	local um = MelloUI:GetModule("UIModifications")
	local positions = um and um.isEnabled and um.db and um.db.positions
	if type(positions) == "table" and positions.ObjectiveTrackerFrame then
		return false
	end
	local ok, default = pcall(f.IsInDefaultPosition, f)
	if ok and not Secret(default) and default == true then
		return true
	end
	return FitPlace(f)
end

-- how far below its home (the game's tracker's top right, or the stand-in
-- spot) it hangs for the column, in its own units at `scale`: 0 or less
local function ColumnDrop(f, scale, set)
	if not Unplaced(f) then
		return 0
	end
	local mp = MelloUI:GetModule("MinimapPanel")
	if not (mp and mp.ColumnRect) then
		return 0
	end
	local cl, cb, cr, ct = mp:ColumnRect()
	local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
	us = okU and Plain(us) or nil
	if not (cl and type(us) == "number" and us > 0) then
		return 0
	end
	local s = us * scale   -- its effective scale once laid (UIParent's child)
	-- its home's right edge and top, and its width, on the screen
	local right, top, width
	if f then
		local ok, l, b, w, h = pcall(f.GetRect, f)
		if not ok then
			return 0
		end
		l, b, w, h = Plain(l), Plain(b), Plain(w), Plain(h)
		local okF, fs = pcall(f.GetEffectiveScale, f)
		fs = okF and Plain(fs) or nil
		if not (type(l) == "number" and type(b) == "number" and type(w) == "number" and type(h) == "number"
			and type(fs) == "number") then
			return 0
		end
		right, top = (l + w) * fs, (b + h) * fs
		width = set > 0 and set * s or w * fs
	else
		local ok, uw, uh = pcall(UIParent.GetSize, UIParent)
		uw, uh = ok and Plain(uw) or nil, ok and Plain(uh) or nil
		if not (type(uw) == "number" and type(uh) == "number") then
			return 0
		end
		right, top = uw * us - 80 * s, uh * us - 260 * s
		width = (set > 0 and set or FALLBACK_W) * s
	end
	-- the column stands over it: across its width, from above its top
	if cr <= right - width or cl >= right or ct <= top then
		return 0
	end
	local drop = cb - COLUMN_GAP * s - top
	if drop >= 0 then
		return 0
	end
	return drop / s
end

-- Match The Minimap's Width (the column's layout E, user, 2026-09-25: "yes,
-- flip it"). The map's size is Edit Mode's (Minimap, Size); the tracker is
-- as wide on the screen as the minimap column: MinimapPanel's
-- M:ColumnWidth() `line` -- the round map's diameter, the square map's
-- side, or the square border's (the merged) frame where it stands wider, so
-- the two frames line up edge to edge -- over its own effective scale (the
-- UI's x its Scale), kept within the grip's bounds. Only while the option
-- is on and the Minimap Kit is on; else its Width setting, as before. Laid
-- on the bus's 'column' (Edit Mode's Size, Edit Mode closed, the UI Scale,
-- the minimap's shape or border) through Place. A width that cannot be read
-- leaves the tracker as it is (the last one it followed).
local FOLLOW_MIN, FOLLOW_MAX = 180, 700   -- (the grip's bounds, SetResizeBounds in Build)
local followPx = nil   -- the column's width last read (screen px)

-- the width to lay at `scale` (its own units), or nil: its Width setting
local function FollowWidth(scale)
	local mp = M.db and M.db.matchMinimap ~= false and MelloUI:GetModule("MinimapPanel")
	if not (mp and mp.isEnabled and mp.ColumnWidth) then
		followPx = nil
		return nil
	end
	local ok, _, line = pcall(mp.ColumnWidth, mp)
	line = ok and Plain(line) or nil
	if type(line) == "number" and line > 0 then
		followPx = line
	end
	local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
	us = okU and Plain(us) or nil
	if not (followPx and type(us) == "number" and us > 0 and scale > 0) then
		return followW
	end
	return math.min(FOLLOW_MAX, math.max(FOLLOW_MIN, followPx / (us * scale)))
end

-- the frame sits where the game's tracker is, as wide as it, from its top
local function Place()
	local scale = tonumber(M.db and M.db.scale) or 1
	local set = tonumber(M.db and M.db.width) or 0
	-- the minimap's width while it follows it, laid as a set width
	followW = FollowWidth(scale)
	if followW then
		set = followW
	end
	local f = ObjectiveTrackerFrame
	-- moved with Unlock the Windows: its own place, hung by its top-right
	-- corner so it still grows downward
	local pos = M.db and M.db.pos
	local px, py = pos and pos.x, pos and pos.y
	-- a place of its own is kept on the screen by the screen's size and
	-- scale, and takes the game's tracker's width when none is set
	local us, sw, sh, gw
	if px and py then
		local okU, u = pcall(UIParent.GetEffectiveScale, UIParent)
		local okP, w, h = pcall(UIParent.GetSize, UIParent)
		us, sw, sh = okU and Plain(u) or nil, okP and Plain(w) or nil, okP and Plain(h) or nil
		if set <= 0 and f then
			local okG, g = pcall(f.GetWidth, f)
			gw = okG and Plain(g) or nil
		end
	end
	-- where nobody placed it: clear of the column under the minimap
	local drop = 0
	if not (px and py) then
		drop = ColumnDrop(f, scale, set)
	end
	if last.valid and last.scale == scale and last.set == set and last.x == px and last.y == py and last.to == f
		and last.us == us and last.sw == sw and last.sh == sh and last.gw == gw and last.drop == drop
		and frame:GetScale() == last.got and SamePoint() then
		return
	end
	-- forgotten until this Place is through
	last.valid = false
	-- the scale first, while it still hangs where it was: the backgrounds in
	-- it are laid again at the UI's one resolution only when its scale on the
	-- screen really changed
	local Kit = MelloUI.Kit
	if Kit and Kit.SetFrameScale then
		Kit:SetFrameScale(frame, scale)
	else
		frame:SetScale(scale)
	end
	frame:ClearAllPoints()
	if px and py then
		-- kept on the screen (user, 2026-09-24: "UI Scaling Break the UI"):
		-- the offsets are in its own units, which grow with the UI scale
		-- while the screen shrinks in them, so a tracker dropped near the
		-- left or the bottom at a small UI scale hung off the screen at a
		-- larger one. Pulled in so its width and its title plate stay on it;
		-- the saved place itself is kept for the old scale. (The screen's
		-- size and scale and the game's tracker's width as read above.)
		-- Not MelloUI:FitOnScreen (audit, 2026-09-24, rank 6, checked
		-- 2026-09-25): that keeps the whole laid frame on the screen, this
		-- keeps the title plate on it from the saved offsets, before the
		-- frame is laid -- the list below grows and shrinks, and MaxHeight
		-- keeps it above the screen's bottom -- and a frame wider than the
		-- screen keeps its right edge on it. Moving onto it would move a
		-- tracker saved low on the screen.
		local x, y = px, py
		local okS, fs = pcall(frame.GetEffectiveScale, frame)
		fs = okS and Plain(fs)
		if fs and us and sw and sh and fs > 0 and us > 0 then
			local k = us / fs
			local w = set > 0 and set or FrameWidth()
			x = math.min(0, math.max(x, -(sw * k - w)))
			y = math.min(0, math.max(y, -(sh * k - HEADER_H)))
		end
		frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x, y)
		if set > 0 then
			frame:SetWidth(set)
		else
			frame:SetWidth((gw and gw > 100) and gw or FALLBACK_W)
		end
	elseif f then
		-- the right edge stays on the game's tracker's (it sits by the
		-- screen's right side); a set width grows to the left; hung lower by
		-- the column's drop where nobody placed it, else exactly on it
		if drop < 0 then
			frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, drop)
		else
			frame:SetPoint("TOPRIGHT", f, "TOPRIGHT")
		end
		if set > 0 then
			frame:SetWidth(set)
		elseif drop < 0 then
			frame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, drop)
		else
			frame:SetPoint("TOPLEFT", f, "TOPLEFT")
		end
	else
		frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -80, -260 + drop)
		frame:SetWidth(set > 0 and set or FALLBACK_W)
	end
	-- laid: kept, with its first point and its scale as the frame reads them
	-- back (not kept when they cannot be read plainly)
	local ok, p, rel, rp, ax, ay = pcall(frame.GetPoint, frame, 1)
	if ok and not (Secret(p) or Secret(rel) or Secret(rp) or Secret(ax) or Secret(ay)) then
		last.scale, last.set, last.x, last.y, last.to = scale, set, px, py, f
		last.us, last.sw, last.sh, last.gw, last.drop = us, sw, sh, gw, drop
		last.p, last.rel, last.rp, last.ax, last.ay = p, rel, rp, ax, ay
		last.got, last.valid = frame:GetScale(), true
	end
end

--------------------------------------------------------------------------------
-- Looks: the painted kit's, or a plain panel
--------------------------------------------------------------------------------

local looks = {}

-- The kit's look for this tracker: its own look area, Kit:IsOn -- the reskin
-- and the tracker's own switch -- read live wherever a look is drawn, and a
-- switch told on the bus ('look:questTracker', below) so it flips at once
-- (audit, 2026-09-24, rank 1: it read the game's tracker's kit module, never
-- heard of a switch, and kept a mixed look until /reload)
local function KitCovers()
	local Kit = MelloUI.Kit
	return Kit and Kit.IsOn and Kit:IsOn("questTracker") or false
end

local function BuildKitLook()
	if looks.kit ~= nil then
		return looks.kit
	end
	looks.kit = false
	local Kit = MelloUI.Kit
	if not (Kit and Kit.NineSlice) then
		return false
	end
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetAllPoints(frame)
	holder:SetFrameLevel(frame:GetFrameLevel())
	holder:EnableMouse(false)
	local ok, skin = pcall(Kit.NineSlice, Kit, holder, { prefix = Kit.framePrefix, gems = false,
		scale = (Kit.scale or 1) * (Kit.frameScale or 1) })
	if not ok then
		holder:Hide()
		return false
	end
	if skin and Kit.ParchmentSheet then
		Kit:ParchmentSheet(skin, holder, { area = "questTracker" })
	end
	-- no eye strain (user, 2026-09-24: "too much small text over a plain
	-- brown border is just an eye strain" / "apply the eye strain rule to all
	-- existing windows"; WINDOW-RULES 2e): the tracker is all quest text, so
	-- on the stone look (its parchment off) the stone inside the rails lies
	-- under the palette's inner panel; a region of the skin between the stone
	-- and the sheet, switched against the sheet by Kit:SetParchment
	if skin and Kit.StoneDim then
		Kit:StoneDim(skin, { area = "questTracker" })
	end
	-- the title plate across the top, as on the game's tracker
	local plateHolder = CreateFrame("Frame", nil, header)
	plateHolder:SetAllPoints(header)
	plateHolder:SetFrameLevel(header:GetFrameLevel())
	local okP, plate = pcall(Kit.Strip, Kit, plateHolder, "tabs/top", { state = "title", scale = Kit.scale })
	if okP and plate then
		plate:ClearAllPoints()
		plate:SetPoint("LEFT", plateHolder, "LEFT", -4, 0)
		plate:SetPoint("RIGHT", plateHolder, "RIGHT", 4, 0)
		if plate.FitHeight then
			pcall(plate.FitHeight, plate, HEADER_H + 10)
			if plate.height then
				plate:SetHeight(plate.height)
			end
		end
	end
	looks.kit = { holder = holder, plate = plateHolder, strip = okP and plate or nil }
	return looks.kit
end

local function BuildPlainLook()
	if looks.plain then
		return looks.plain
	end
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetAllPoints(frame)
	holder:SetFrameLevel(frame:GetFrameLevel())
	holder:EnableMouse(false)
	local bg = holder:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(holder)
	bg:SetColorTexture(0, 0, 0, 0.45)
	local line = holder:CreateTexture(nil, "BORDER")
	line:SetColorTexture(0.8, 0.65, 0.3, 0.8)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
	line:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -1)
	looks.plain = { holder = holder }
	return looks.plain
end

-- A collapse toggle on its plate's rail just short of the right gem
-- (user's sketch, 2026-09-23: the green marks left of the gems -- not on
-- them). The spot as a share of the right cap's canvas, measured on the art
-- (the gems' centres: 0.70 on the title cap, 0.87 on the header cap; the
-- caps carry no gem box); without the kit, at `rel`'s right edge by `x`.
local TITLE_GEM = { 0.47, 0.50 }     -- tabs/top_cap_r_title
local HEADER_GEM = { 0.61, 0.56 }    -- lists/header_cap_r
local function OnGem(toggle, strip, gem, rel, x)
	toggle:ClearAllPoints()
	local cap = strip and strip.capR
	local w, h = strip and strip.wr, strip and strip.height
	if cap and not strip.noR and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
		toggle:SetPoint("CENTER", cap, "TOPLEFT", w * gem[1], -h * gem[2])
	else
		toggle:SetPoint("RIGHT", rel, "RIGHT", x, 0)
	end
end

-- The text at the chosen size (user, 2026-09-23: "the text is too small" --
-- the game's small fonts, 12 and 10): the game's own typeface and flags, so
-- the Fonts module's face and outline still reach it
local function StyleText(fs, size)
	local object = GameFontNormal
	if not (object and object.GetFont and fs.SetFont) then
		return
	end
	local ok, path, _, flags = pcall(object.GetFont, object)
	if ok and path then
		pcall(fs.SetFont, fs, path, size, flags or "")
	end
end

local function TitleSize()
	return math.floor((tonumber(M.db and M.db.textSize) or 13) + 0.5)
end

-- All Objectives' size (user, 2026-09-23: it was the game font's large size,
-- fixed, and could not be changed in the configurator)
local function HeaderSize()
	return math.floor((tonumber(M.db and M.db.headerSize) or 16) + 0.5)
end

local function ApplyLook()
	local kitOn = KitCovers() and BuildKitLook()
	if kitOn then
		kitOn.holder:Show()
		kitOn.plate:Show()
		if looks.plain then
			looks.plain.holder:Hide()
		end
	else
		BuildPlainLook().holder:Show()
		if looks.kit then
			looks.kit.holder:Hide()
			looks.kit.plate:Hide()
		end
	end
	-- the title at Header Text Size: the base font first, then the title face
	-- over it (the face keeps the size it was given, as the section headers)
	local Kit = MelloUI.Kit
	if header then
		if Kit and Kit.TitleFont and header.text.melloFontSaved then
			pcall(Kit.TitleFont, Kit, header.text, false)
		end
		StyleText(header.text, HeaderSize())
		if kitOn and Kit and Kit.TitleFont then
			pcall(Kit.TitleFont, Kit, header.text, true)
		end
		-- on the plate's painted band, not its canvas: the band sits lower in
		-- the canvas, and the title rode high on it (user, 2026-09-23: "move
		-- this All Objectives Text to be in the Middle of the Red Background")
		local dy = 0
		local strip = kitOn and kitOn.strip
		local pieces = MelloUI_KitLayout and MelloUI_KitLayout.pieces
		if strip and pieces and Kit.StripPieceName then
			local mid = pieces[Kit:StripPieceName(strip.base, "mid", strip.state)]
			if mid and mid.box then
				dy = (mid.h / 2 - (mid.box[2] + mid.box[4]) / 2) * (strip.scale or Kit.scale or 1)
			end
		end
		header.text:ClearAllPoints()
		header.text:SetPoint("CENTER", header, "CENTER", 0, dy)
	end
	if header and header.toggle then
		OnGem(header.toggle, kitOn and kitOn.strip, TITLE_GEM, header, -4)
	end
end

--------------------------------------------------------------------------------
-- Quest items: one secure button, laid over the item under the mouse
--------------------------------------------------------------------------------

local itemOverlay

local function DetachOverlay()
	if itemOverlay and not InCombatLockdown() then
		itemOverlay:ClearAllPoints()
		itemOverlay:Hide()
		itemOverlay.over = nil
	end
end

local function AttachOverlay(button)
	if InCombatLockdown() or not button.itemLink then
		return
	end
	if not itemOverlay then
		itemOverlay = CreateFrame("Button", "MelloUIQuestTrackerItem", UIParent, "SecureActionButtonTemplate")
		itemOverlay:SetAttribute("type", "item")
		itemOverlay:RegisterForClicks("AnyUp", "AnyDown")
		Perf.SetScript(itemOverlay, "OnLeave", function(self)
			GameTooltip:Hide()
			if not self:IsMouseOver() then
				DetachOverlay()
			end
		end)
		Perf.SetScript(itemOverlay, "OnEnter", function(self)
			if self.over and self.over.itemLink then
				GameTooltip:SetOwner(self, "ANCHOR_LEFT")
				pcall(GameTooltip.SetHyperlink, GameTooltip, self.over.itemLink)
				GameTooltip:Show()
			end
		end)
		itemOverlay:EnableMouseWheel(true)
		Perf.SetScript(itemOverlay, "OnMouseWheel", function(_, delta)
			Scroll(delta)
		end)
	end
	itemOverlay:SetAttribute("item", button.itemLink)
	itemOverlay:SetFrameStrata(button:GetFrameStrata())
	itemOverlay:SetFrameLevel(button:GetFrameLevel() + 5)
	itemOverlay:ClearAllPoints()
	itemOverlay:SetAllPoints(button)
	itemOverlay.over = button
	itemOverlay:Show()
end

-- a fight is starting: the secure button leaves the list while it still can
-- (PLAYER_REGEN_DISABLED comes before the lockdown), so nothing secure hangs
-- on the list while it scrolls in combat
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
Perf.SetScript(combatWatcher, "OnEvent", function(self, event)
	if event == "PLAYER_REGEN_DISABLED" then
		DetachOverlay()
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		if pendingGame ~= nil then
			SetGameTracker(pendingGame)
		end
	end
end)

--------------------------------------------------------------------------------
-- A quest's block: its title, its objectives, its item
--------------------------------------------------------------------------------

local function OpenRecipe(recipeID)
	-- next frame, out of this click's execution
	C_Timer.After(0, function()
		if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
			pcall(C_TradeSkillUI.OpenRecipe, recipeID)
		end
	end)
end

local function OnBlockClick(block, button)
	if block.recipeID then
		if IsShiftKeyDown() and button ~= "RightButton" then
			if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then
				pcall(C_TradeSkillUI.SetRecipeTracked, block.recipeID, false, block.recraft and true or false)
			end
		else
			OpenRecipe(block.recipeID)
		end
		return
	end
	local id = block.questID
	if not id then
		return
	end
	if button == "RightButton" then
		-- next frame, out of this click's (MelloUI's) execution
		C_Timer.After(0, function()
			if QuestMapFrame_OpenToQuestDetails then
				pcall(QuestMapFrame_OpenToQuestDetails, id)
			end
		end)
	elseif IsShiftKeyDown() then
		if C_QuestLog and C_QuestLog.RemoveQuestWatch then
			pcall(C_QuestLog.RemoveQuestWatch, id)
		end
	elseif C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
		local current = C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
		local want = (Plain(current) == id) and 0 or id
		if securecallfunction then
			securecallfunction(C_SuperTrack.SetSuperTrackedQuestID, want)
		else
			pcall(C_SuperTrack.SetSuperTrackedQuestID, want)
		end
	end
end

local function OnBlockEnter(block)
	if block.recipeID then
		GameTooltip:SetOwner(block, "ANCHOR_LEFT")
		local link
		if C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink then
			local ok, l = pcall(C_TradeSkillUI.GetRecipeLink, block.recipeID)
			link = ok and Plain(l) or nil
		end
		if not (link and pcall(GameTooltip.SetHyperlink, GameTooltip, link)) then
			GameTooltip:SetText(block.title:GetText() or "")
		end
		GameTooltip:AddLine("Click: open the recipe  -  Shift-click: stop tracking", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
		if block.highlight then
			block.highlight:Show()
		end
		return
	end
	if not block.questID then
		return
	end
	GameTooltip:SetOwner(block, "ANCHOR_LEFT")
	if not pcall(GameTooltip.SetHyperlink, GameTooltip, "quest:" .. block.questID) then
		GameTooltip:SetText(block.title:GetText() or "")
	end
	GameTooltip:AddLine("Click: follow  -  Shift-click: stop watching  -  Right-click: quest log", 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
	if block.highlight then
		block.highlight:Show()
	end
end

local function OnBlockLeave(block)
	GameTooltip:Hide()
	if block.highlight then
		block.highlight:Hide()
	end
end

local function NewBlock()
	local block = table.remove(freeBlocks)
	if block then
		return block
	end
	block = CreateFrame("Button", nil, content)
	block:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	Perf.SetScript(block, "OnClick", OnBlockClick)
	Perf.SetScript(block, "OnEnter", OnBlockEnter)
	Perf.SetScript(block, "OnLeave", OnBlockLeave)
	block:EnableMouseWheel(true)
	Perf.SetScript(block, "OnMouseWheel", function(_, delta) Scroll(delta) end)
	block.highlight = block:CreateTexture(nil, "BACKGROUND")
	block.highlight:SetAllPoints(block)
	block.highlight:SetColorTexture(1, 0.85, 0.4, 0.08)
	block.highlight:Hide()
	block.followed = block:CreateTexture(nil, "ARTWORK")
	block.followed:SetSize(10, 10)
	local Kit = MelloUI.Kit
	if not (Kit and Kit.Apply and Kit:Apply(block.followed, "deco/gem_small")) then
		block.followed:SetColorTexture(1, 0.8, 0.2, 1)
	end
	-- the quest's map button, the game's own (POIButtonTemplate, as on the
	-- game's tracker: "..." in progress, "?" ready to turn in, lit while
	-- followed). Its click is the block's (follow / stop following), never
	-- the template's own, so no MelloUI value runs through the game's code.
	-- A client without the template keeps the small gem for the followed one.
	local okP, poi = pcall(CreateFrame, "Button", nil, block, "POIButtonTemplate")
	if okP and poi and poi.SetQuestID then
		poi:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		Perf.SetScript(poi, "OnClick", function(_, button) OnBlockClick(block, button) end)
		Perf.SetScript(poi, "OnEnter", function() OnBlockEnter(block) end)
		Perf.SetScript(poi, "OnLeave", function() OnBlockLeave(block) end)
		poi:EnableMouseWheel(true)
		Perf.SetScript(poi, "OnMouseWheel", function(_, delta) Scroll(delta) end)
		poi:Hide()
		block.poi = poi
	elseif okP and poi then
		poi:Hide()
	end
	block.title = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	block.title:SetJustifyH("LEFT")
	block.title:SetWordWrap(true)
	block.lines = {}
	local item = CreateFrame("Button", nil, block)
	item:SetSize(ITEM_SIZE, ITEM_SIZE)
	item.icon = item:CreateTexture(nil, "ARTWORK")
	item.icon:SetAllPoints(item)
	item.border = item:CreateTexture(nil, "OVERLAY")
	item.border:SetPoint("TOPLEFT", -2, 2)
	item.border:SetPoint("BOTTOMRIGHT", 2, -2)
	if not (Kit and Kit.Apply and Kit:Apply(item.border, "buttons/slot_normal")) then
		item.border:SetColorTexture(0, 0, 0, 0)
	end
	item.cooldown = CreateFrame("Cooldown", nil, item, "CooldownFrameTemplate")
	item.cooldown:SetAllPoints(item)
	Perf.SetScript(item, "OnEnter", function(self)
		AttachOverlay(self)
		if InCombatLockdown() then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			pcall(GameTooltip.SetHyperlink, GameTooltip, self.itemLink)
			GameTooltip:AddLine("Out of combat, a click uses it.", 0.7, 0.7, 0.7, true)
			GameTooltip:Show()
		end
	end)
	Perf.SetScript(item, "OnLeave", function()
		GameTooltip:Hide()
	end)
	item:EnableMouseWheel(true)
	Perf.SetScript(item, "OnMouseWheel", function(_, delta) Scroll(delta) end)
	block.item = item
	return block
end

local function ReleaseBlock(block)
	block:Hide()
	block:ClearAllPoints()
	block.questID, block.recipeID, block.recraft = nil, nil, nil
	if itemOverlay and itemOverlay.over == block.item then
		DetachOverlay()
	end
	freeBlocks[#freeBlocks + 1] = block
end

-- On the parchment sheet the text is dark ink and a quest's difficulty is
-- in pips beside its title (QuestInk; user, 2026-09-23)
local function Inked()
	local Kit = MelloUI.Kit
	return MelloUI.QuestInk ~= nil and KitCovers() and Kit and Kit.ParchmentOn and Kit:ParchmentOn("questTracker") or false
end

-- A line's colour on parchment: done or greyed lines faded, the rest ink
local function InkLine(fs, ink, r)
	local QI = MelloUI.QuestInk
	if not QI then
		return
	end
	if ink then
		QI.Ink(fs, (r and r < 0.8) and "faded" or "text")
	else
		QI.Plain(fs)
	end
end

-- A line's colour on the stone look (user, 2026-09-24: the eye strain rule,
-- WINDOW-RULES 2e -- text on the dark panel in the palette's colours): the
-- plain white of a line to do becomes the palette's text, the gold of a
-- recipe's name its gold; a done line's grey and a quest title's difficulty
-- colour keep their meaning. On parchment the ink colours it; without the kit
-- (the plain dark box) it keeps the game tracker's colours.
local function StoneColour(block, r, g, b)
	if block.ink or not KitCovers() then
		return r, g, b
	end
	local P = MelloUI.Palette
	if r == g and g == b and r >= 0.8 then
		return P.text[1], P.text[2], P.text[3]
	elseif r == 1 and g == 0.82 and b == 0 then
		return P.selectedTrim[1], P.selectedTrim[2], P.selectedTrim[3]
	end
	return r, g, b
end

local function Line(block, i)
	local fs = block.lines[i]
	if not fs then
		fs = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
		fs.dash = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs.dash:SetText("-")
		-- a gold glow behind the line when it counts up (user, 2026-09-23:
		-- the study's progress flash), at rest fully clear
		fs.flash = block:CreateTexture(nil, "BACKGROUND", nil, 1)
		fs.flash:SetColorTexture(1, 0.82, 0.3, 1)
		fs.flash:SetAlpha(0)
		block.lines[i] = fs
	end
	StyleText(fs, TitleSize() - 1)
	StyleText(fs.dash, TitleSize() - 1)
	return fs
end

-- Line i under a title at y: with `dash`, the dash in its column and the
-- text hanging past it (a wrapped line starts under the text, as on the
-- game's tracker); else the text from the dash's column. Returns the next y.
local function PutLine(block, i, text, y, width, dash, r, g, b)
	local fs = Line(block, i)
	local x = TEXT_X + (dash and LINE_X or BULLET_X)
	fs:SetText(text)
	-- the palette's colour on the stone; the ink below still judges the
	-- game's shade (`r`), done or not
	local sr, sg, sb = StoneColour(block, r, g, b)
	fs:SetTextColor(sr, sg, sb)
	InkLine(fs, block.ink, r)
	InkLine(fs.dash, block.ink, r)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", block, "TOPLEFT", x, -y)
	fs:SetWidth(width - x)
	fs:Show()
	if dash then
		fs.dash:ClearAllPoints()
		fs.dash:SetPoint("TOPLEFT", block, "TOPLEFT", TEXT_X + BULLET_X, -y)
		fs.dash:SetTextColor(sr, sg, sb)
		fs.dash:Show()
	else
		fs.dash:Hide()
	end
	local h = fs:GetStringHeight()
	fs.flash:ClearAllPoints()
	fs.flash:SetPoint("TOPLEFT", block, "TOPLEFT", TEXT_X + BULLET_X - 4, -y + 1)
	fs.flash:SetPoint("RIGHT", block, "RIGHT", 0, 0)
	fs.flash:SetHeight(h + 2)
	return y + h + LINE_GAP, fs
end

-- A line counted up since the last rebuild: its glow flares and fades.
-- `key` / `i` name the line across rebuilds; the first sight of it never
-- flashes (a quest just watched, a login). Reduce Motion: no flash at all.
local function Progress(key, i, count, fs)
	local seen = lastProgress[key]
	if not seen then
		seen = {}
		lastProgress[key] = seen
	end
	local before = seen[i]
	seen[i] = count
	if before and count and count > before and fs and MelloUI.Anim then
		MelloUI.Anim:From(fs.flash, "alpha", 0.45, 0.9, "outQuad")
	end
end

local function HideLines(block, from)
	for i = from, #block.lines do
		block.lines[i]:Hide()
		block.lines[i].dash:Hide()
		if MelloUI.Anim then
			MelloUI.Anim:Stop(block.lines[i].flash, "alpha")
		end
		block.lines[i].flash:SetAlpha(0)
	end
end

local function DifficultyColor(level)
	if level and GetQuestDifficultyColor then
		local ok, c = pcall(GetQuestDifficultyColor, level)
		if ok and c and c.r then
			return c.r, c.g, c.b
		end
	end
	return 1, 0.82, 0
end

-- Fill a block from the quest log; returns its height.
local function FillBlock(block, questID, width, followedID)
	local logIndex = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
	local info = logIndex and C_QuestLog.GetInfo and C_QuestLog.GetInfo(logIndex)
	local title = (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)) or (info and info.title) or ("Quest " .. questID)
	local level = info and Plain(info.level)
	local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
	block.questID, block.recipeID, block.recraft = questID, nil, nil

	-- the item first: the text keeps clear of it
	local textWidth = width
	local item = block.item
	local link, icon
	if M.db.itemButtons and logIndex and GetQuestLogSpecialItemInfo then
		local ok, l, tex = pcall(GetQuestLogSpecialItemInfo, logIndex)
		if ok then
			link, icon = Plain(l), Plain(tex)
		end
		-- a finished quest keeps its item only when the game says so
		if complete then
			local okS, _, _, _, showWhenComplete = pcall(GetQuestLogSpecialItemInfo, logIndex)
			if not (okS and showWhenComplete) then
				link, icon = nil, nil
			end
		end
	end
	if link and icon then
		item.itemLink = link
		item.icon:SetTexture(icon)
		item:ClearAllPoints()
		item:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, -2)
		item:Show()
		if GetQuestLogSpecialItemCooldown then
			local ok, start, duration, enable = pcall(GetQuestLogSpecialItemCooldown, logIndex)
			if ok and Plain(start) and Plain(duration) then
				pcall(item.cooldown.SetCooldown, item.cooldown, start, duration, enable)
			end
		end
		textWidth = width - ITEM_SIZE - 6
	else
		item.itemLink = nil
		item:Hide()
	end

	local followed = followedID == questID
	local poi = block.poi
	if poi then
		-- the game's style for the quest (its own pick where it has one)
		local util = POIButtonUtil
		local style = util and util.Style and (complete and util.Style.QuestComplete or util.Style.QuestInProgress)
		if util and util.GetStyle then
			local okG, st = pcall(util.GetStyle, questID)
			if okG and not Secret(st) and st ~= nil then
				style = st
			end
		end
		pcall(poi.SetQuestID, poi, questID)
		if style ~= nil and poi.SetStyle then
			pcall(poi.SetStyle, poi, style)
		end
		if poi.SetSelected then
			pcall(poi.SetSelected, poi, followed)
		end
		if poi.UpdateButtonStyle then
			pcall(poi.UpdateButtonStyle, poi)
		end
		-- centred on the title's first line
		poi:ClearAllPoints()
		poi:SetPoint("CENTER", block, "TOPLEFT", TEXT_X / 2 - 1, -TitleSize() / 2 - 1)
		poi:Show()
	end
	block.followed:SetShown(followed and not poi)
	block.followed:ClearAllPoints()
	block.followed:SetPoint("CENTER", block, "TOPLEFT", TEXT_X / 2 - 1, -TitleSize() / 2 - 1)

	local t = block.title
	StyleText(t, TitleSize())
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", block, "TOPLEFT", TEXT_X, 0)
	-- on parchment: the title in ink, the difficulty in pips at the right of
	-- its first line (left of the item); else the game's difficulty colour
	local QI = MelloUI.QuestInk
	local ink = Inked()
	block.ink = ink
	local tier = ink and QI.TierForQuest(questID, level) or nil
	local pipsRoom = 0
	if tier then
		block.pips = block.pips or QI.Pips(block, PIP_SIZE)
		block.pips:ClearAllPoints()
		block.pips:SetPoint("RIGHT", block, "TOPLEFT", textWidth, -TitleSize() / 2 - 1)
		block.pips:SetTier(tier)
		pipsRoom = QI.PipsWidth(PIP_SIZE) + 6
	elseif block.pips then
		block.pips:SetTier(nil)
	end
	t:SetWidth(textWidth - TEXT_X - pipsRoom)
	t:SetText(level and string.format("[%d] %s", level, title) or title)
	t:SetTextColor(DifficultyColor(level))
	if ink then
		QI.Ink(t, tier == 1 and "faded" or "title")
	elseif QI then
		QI.Plain(t)
	end
	local y = t:GetStringHeight() + TITLE_GAP

	local n = 0
	local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID) or {}
	if complete then
		-- what to do now, white under the title (the game's turn-in line)
		n = n + 1
		local text = logIndex and GetQuestLogCompletionText and GetQuestLogCompletionText(logIndex)
		local fs
		y, fs = PutLine(block, n, Plain(text) or "Ready for turn-in", y, textWidth, false, 0.95, 0.95, 0.95)
		if lastComplete[questID] == false and MelloUI.Anim then
			MelloUI.Anim:From(fs.flash, "alpha", 0.45, 0.9, "outQuad")
		end
		lastComplete[questID] = true
	else
		lastComplete[questID] = false
		for i, obj in ipairs(objectives) do
			local text = Plain(obj.text)
			if text and text ~= "" then
				n = n + 1
				local shade = obj.finished and 0.55 or 0.95
				local fs
				y, fs = PutLine(block, n, text, y, textWidth, true, shade, shade, shade)
				Progress(questID, i, Plain(obj.numFulfilled), fs)
			end
		end
	end
	HideLines(block, n + 1)
	local h = math.max(y, link and ITEM_SIZE + 4 or 0, poi and 22 or 0)
	block:SetHeight(h)
	block:Show()
	return h
end

--------------------------------------------------------------------------------
-- Scrolling
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Moving it: by its header while the windows are unlocked, through UI
-- Modifications' mover (MelloUI:RegisterMover, where the frame is built)
--------------------------------------------------------------------------------

-- where it was dropped, as offsets of its top-right corner from the screen's
-- top-right, in its own units (it hangs from that corner, growing downward)
local function SavePosition()
	local fs = frame:GetEffectiveScale()
	local us = UIParent:GetEffectiveScale()
	local right, top = frame:GetRight(), frame:GetTop()
	if not (right and top and fs and fs > 0) then
		return
	end
	M.db.pos = {
		x = (right * fs - UIParent:GetRight() * us) / fs,
		y = (top * fs - UIParent:GetTop() * us) / fs,
	}
end

local function ClipHeight()
	local ok, h = pcall(clip.GetHeight, clip)
	h = ok and Plain(h) or 0
	return h
end

local function MaxScroll()
	return math.max(0, contentHeight - ClipHeight())
end

local function UpdateThumb()
	local visible = ClipHeight()
	if contentHeight <= visible + 0.5 or visible <= 0 then
		thumb:Hide()
		track:Hide()
		return
	end
	track:Show()
	thumb:Show()
	local h = math.max(18, visible * visible / contentHeight)
	local travel = visible - h
	local y = travel * (scrollOffset / MaxScroll())
	thumb:ClearAllPoints()
	thumb:SetPoint("TOPRIGHT", clip, "TOPRIGHT", THUMB_W + 3, -y)
	thumb:SetHeight(h)
end

local function SetOffset(offset)
	scrollOffset = math.max(0, math.min(offset, MaxScroll()))
	content:ClearAllPoints()
	content:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, scrollOffset)
	content:SetWidth(ContentWidth())
	UpdateThumb()
	if itemOverlay and itemOverlay.over and not InCombatLockdown() then
		-- the item the secure button lies over moved with the list
		if not itemOverlay.over:IsMouseOver() then
			DetachOverlay()
		end
	end
end

Scroll = function(delta)
	local step = tonumber(M.db and M.db.scrollStep) or 25
	SetOffset(scrollOffset - delta * step)
end

--------------------------------------------------------------------------------
-- Rebuild
--------------------------------------------------------------------------------

-- The recipes tracked in the professions window, the recrafts after them
-- (user, 2026-09-23: "when i track a recipe it does not show the
-- Professions category like the default one does").
local function TrackedRecipes()
	local list = {}
	local ui = C_TradeSkillUI
	if not (ui and ui.GetRecipesTracked) then
		return list
	end
	for _, recraft in ipairs({ false, true }) do
		local ok, ids = pcall(ui.GetRecipesTracked, recraft)
		if ok and type(ids) == "table" then
			for _, id in ipairs(ids) do
				id = Plain(id)
				if id then
					list[#list + 1] = { id = id, recraft = recraft }
				end
			end
		end
	end
	return list
end

local function ReagentCount(itemID)
	if C_Item and C_Item.GetItemCount then
		local ok, n = pcall(C_Item.GetItemCount, itemID, true, false, true, true)
		n = ok and Plain(n) or nil
		if n then
			return n
		end
	end
	if GetItemCount then
		local ok, n = pcall(GetItemCount, itemID, true)
		return ok and Plain(n) or 0
	end
	return 0
end

local function ItemName(itemID)
	if C_Item and C_Item.GetItemNameByID then
		local ok, name = pcall(C_Item.GetItemNameByID, itemID)
		if ok and Plain(name) then
			return name
		end
	end
	local ok, name = pcall(GetItemInfo, itemID)
	return ok and Plain(name) or ("item " .. itemID)
end

-- A tracked recipe: its name, and each basic reagent as have / need, grey
-- once there are enough (the game's tracker's Professions lines)
local function FillRecipeBlock(block, entry, width)
	block.questID, block.recipeID, block.recraft = nil, entry.id, entry.recraft
	block.item.itemLink = nil
	block.item:Hide()
	block.followed:Hide()
	if block.poi then
		block.poi:Hide()
	end
	local ui = C_TradeSkillUI
	local name
	if ui.GetRecipeInfo then
		local ok, info = pcall(ui.GetRecipeInfo, entry.id)
		name = ok and info and Plain(info.name) or nil
	end
	local okS, schematic = false, nil
	if ui.GetRecipeSchematic then
		okS, schematic = pcall(ui.GetRecipeSchematic, entry.id, entry.recraft and true or false)
	end
	if not name and okS and schematic then
		name = Plain(schematic.name)
	end
	local t = block.title
	StyleText(t, TitleSize())
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", block, "TOPLEFT", TEXT_X, 0)
	t:SetWidth(width - TEXT_X)
	t:SetText((name or ("Recipe " .. entry.id)) .. (entry.recraft and " (recraft)" or ""))
	-- a recipe on parchment: its name in ink, no pips (no difficulty); on
	-- the stone, the palette's gold
	block.ink = Inked()
	t:SetTextColor(StoneColour(block, 1, 0.82, 0))
	if block.pips then
		block.pips:SetTier(nil)
	end
	InkLine(t, block.ink, 1)
	if block.ink and MelloUI.QuestInk then
		MelloUI.QuestInk.Ink(t, "title")
	end
	local y = t:GetStringHeight() + TITLE_GAP
	local n = 0
	local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
	if okS and schematic and type(schematic.reagentSlotSchematics) == "table" then
		for _, slot in ipairs(schematic.reagentSlotSchematics) do
			local reagent = slot.reagents and slot.reagents[1]
			local itemID = reagent and Plain(reagent.itemID)
			local need = Plain(slot.quantityRequired) or 1
			if itemID and (basic == nil or slot.reagentType == basic) and slot.required ~= false then
				n = n + 1
				local have = ReagentCount(itemID)
				local shade = have >= need and 0.55 or 0.95
				local fs
				y, fs = PutLine(block, n, string.format("%d/%d %s", math.min(have, need), need, ItemName(itemID)), y, width, true, shade, shade, shade)
				Progress("r" .. entry.id .. (entry.recraft and "/1" or "/0"), n, math.min(have, need), fs)
			end
		end
	end
	HideLines(block, n + 1)
	block:SetHeight(y)
	block:Show()
	return y
end

-- A section's header in the list ("Quests", "Professions"): the kit's list
-- header band under the name while the reskin covers the tracker, a thin
-- gold line otherwise
local SECTION_H = 24
local sections = {}

-- A collapse toggle, the kit's minus / plus (the game's without the kit):
-- `IsCollapsed()` picks the icon, `OnClick` flips the state
local function MakeToggle(parent, size, IsCollapsed, OnClick)
	local toggle = CreateFrame("Button", nil, parent)
	toggle:SetSize(size, size)
	toggle.icon = toggle:CreateTexture(nil, "ARTWORK")
	toggle.icon:SetAllPoints(toggle)
	function toggle.Refresh()
		local Kit = MelloUI.Kit
		local collapsed = IsCollapsed()
		local piece = collapsed and "buttons/plus_normal" or "buttons/minus_normal"
		if not (Kit and Kit.Apply and Kit:Apply(toggle.icon, piece)) then
			toggle.icon:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
		end
	end
	Perf.SetScript(toggle, "OnClick", OnClick)
	toggle.Refresh()
	return toggle
end

-- A section folded away (user, 2026-09-23: Quests and Professions each with
-- a minus like All Objectives'), kept per section key
local function SectionCollapsed(key)
	local c = M.db and M.db.collapsedSections
	return type(c) == "table" and c[key] == true
end

local function Section(key, label)
	local row = sections[key]
	if not row then
		row = CreateFrame("Frame", nil, content)
		row:SetHeight(SECTION_H)
		row:EnableMouse(false)
		local Kit = MelloUI.Kit
		if Kit and Kit.Strip then
			local ok, plate = pcall(Kit.Strip, Kit, row, "lists/header", { scale = Kit.scale })
			if ok and plate then
				local yoff = 0
				if plate.FitBox then
					local okF, off = pcall(plate.FitBox, plate, SECTION_H)
					yoff = okF and tonumber(off) or 0
				end
				plate:ClearAllPoints()
				plate:SetPoint("LEFT", row, "LEFT", 0, yoff)
				plate:SetPoint("RIGHT", row, "RIGHT", 0, yoff)
				if plate.height then
					plate:SetHeight(plate.height)
				end
				row.plate = plate
			end
		end
		row.line = row:CreateTexture(nil, "ARTWORK")
		row.line:SetColorTexture(0.8, 0.65, 0.3, 0.8)
		row.line:SetHeight(1)
		row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
		row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 1)
		-- the name above the band (a child frame draws over its parent's regions)
		local layer = CreateFrame("Frame", nil, row)
		layer:SetAllPoints(row)
		layer:SetFrameLevel(row:GetFrameLevel() + 6)
		-- centred as All Objectives is (user, 2026-09-23)
		row.text = layer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.text:SetPoint("CENTER", row, "CENTER", 0, 0)
		row.toggle = MakeToggle(layer, 14, function() return SectionCollapsed(key) end, function()
			local c = type(M.db.collapsedSections) == "table" and M.db.collapsedSections or {}
			M.db.collapsedSections = c
			c[key] = not c[key] or nil
			MelloUI:NotifySettingChanged(M.name, "collapsedSections", c)
		end)
		sections[key] = row
	end
	local kit = KitCovers() and row.plate
	if row.plate then
		row.plate:SetShown(kit and true or false)
	end
	row.line:SetShown(not kit)
	-- the header font (Fonts' title face) while the reskin covers the
	-- tracker, as on All Objectives: the base font first (the face keeps
	-- the size it was given, so a Text Size change must reach it)
	local Kit = MelloUI.Kit
	if Kit and Kit.TitleFont and row.text.melloFontSaved then
		pcall(Kit.TitleFont, Kit, row.text, false)
	end
	StyleText(row.text, TitleSize())
	if kit and Kit and Kit.TitleFont then
		pcall(Kit.TitleFont, Kit, row.text, true)
	end
	row.toggle.Refresh()
	OnGem(row.toggle, kit and row.plate, HEADER_GEM, row, -6)
	row.text:SetText(label)
	row.text:SetTextColor(1, 0.82, 0)
	return row
end

local function WatchedQuests()
	local list = {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex) then
		return list
	end
	local ok, n = pcall(C_QuestLog.GetNumQuestWatches)
	n = ok and Plain(n) or 0
	for i = 1, n do
		local okI, id = pcall(C_QuestLog.GetQuestIDForQuestWatchIndex, i)
		id = okI and Plain(id) or nil
		if id and id > 0 then
			list[#list + 1] = id
		end
	end
	return list
end

local function Rebuild()
	if sizing then
		return   -- stays dirty: the rebuild follows the release
	end
	dirty = false
	if not (frame and M.isEnabled) then
		return
	end
	-- scrolled to the end: the view follows the list's end when it grows
	local wasMax = MaxScroll()
	local atEnd = wasMax > 0 and scrollOffset >= wasMax - 1
	local width = ContentWidth()
	local followedID
	if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
		local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
		followedID = ok and Plain(id) or nil
	end
	local quests = WatchedQuests()
	local recipes = TrackedRecipes()
	-- a block per quest (keyed by its ID) and per recipe ("r<id>/<recraft>"),
	-- the same block for the same entry across rebuilds
	local function RecipeKey(entry)
		return "r" .. entry.id .. (entry.recraft and "/1" or "/0")
	end
	-- a folded section keeps its header only: its blocks are let go
	local questsOpen = not SectionCollapsed("quests")
	local recipesOpen = not SectionCollapsed("professions")
	local keep = {}
	for _, id in ipairs(quests) do
		keep[id] = questsOpen or nil
	end
	for _, entry in ipairs(recipes) do
		keep[RecipeKey(entry)] = recipesOpen or nil
	end
	for key, block in pairs(blocks) do
		if not keep[key] then
			ReleaseBlock(block)
			blocks[key] = nil
		end
	end
	for _, row in pairs(sections) do
		row:Hide()
	end
	local y = 0
	local function Head(key, label)
		local row = Section(key, label)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		row:SetWidth(width)
		row:Show()
		y = y + SECTION_H + 4
	end
	local function Put(key, fill, ...)
		local block = blocks[key] or NewBlock()
		blocks[key] = block
		block:ClearAllPoints()
		block:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		block:SetWidth(width)
		local ok, h = pcall(fill, block, ...)
		if not ok then
			h = 0
			block:Hide()
		end
		y = y + h + BLOCK_GAP
	end
	if #quests > 0 then
		Head("quests", QUESTS_LABEL or "Quests")
		for _, id in ipairs(questsOpen and quests or {}) do
			Put(id, FillBlock, id, width, followedID)
		end
	end
	if #recipes > 0 then
		if #quests > 0 then
			y = y + 2
		end
		Head("professions", TRADE_SKILLS or "Professions")
		for _, entry in ipairs(recipesOpen and recipes or {}) do
			Put(RecipeKey(entry), FillRecipeBlock, entry, width)
		end
	end
	contentHeight = math.max(0, y - BLOCK_GAP)
	content:SetHeight(math.max(1, contentHeight))
	local entries = #quests + #recipes

	-- the frame's height: the header and the list, up to the height allowed
	local collapsed = M.db.collapsed
	clip:SetShown(not collapsed)
	local listH = collapsed and 0 or math.min(contentHeight, MaxHeight() - HEADER_H - INSET * 2)
	local total = HEADER_H + (collapsed and 6 or (INSET + listH + INSET))
	frame:SetHeight(math.max(HEADER_H + 6, total))
	-- nothing watched: nothing shown, as the game's tracker; in Edit Mode the
	-- game's own is out to be moved, and this one waits
	frame:SetShown(entries > 0 and not inEditMode)
	-- the view stays where it was (clamped to the new length), or at the
	-- end when it was there
	SetOffset(atEnd and math.huge or scrollOffset)
end

-- One rebuild a frame at most, whatever number of events came. Driven from
-- the event frame (always shown), not the tracker: a tracker hidden because
-- nothing is watched must still wake up when a quest is watched.
local eventFrame = CreateFrame("Frame")

local function Tick(self)
	Perf.SetScript(self, "OnUpdate", nil)
	if dirty then
		Rebuild()
	end
end

local function MarkDirty()
	dirty = true
	Perf.SetScript(eventFrame, "OnUpdate", Tick)
end

--------------------------------------------------------------------------------
-- Building the frame
--------------------------------------------------------------------------------

local function Build()
	if frame then
		return
	end
	frame = CreateFrame("Frame", "MelloUIQuestTracker", UIParent)
	-- MEDIUM, over the minimap's column (user, 2026-09-26: "Quest Tracker
	-- should have the Priority there"): the cluster and every part of the
	-- column are LOW, and the cluster is toplevel -- a click in it lifted the
	-- whole column over a LOW tracker until /reload. Strata beats level, so
	-- no click or re-skin puts a column part over it; its children, the kit's
	-- look and the item button (which copies it) are MEDIUM with it, and the
	-- Services tray (DIALOG) still opens above it.
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:EnableMouseWheel(true)
	Perf.SetScript(frame, "OnMouseWheel", function(_, delta) Scroll(delta) end)
	Place()

	header = CreateFrame("Button", nil, frame)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	header:SetHeight(HEADER_H)
	header:SetFrameLevel(frame:GetFrameLevel() + 4)
	-- the title and the toggle on a layer ABOVE the title plate: the plate is
	-- a child frame of the header, which would draw over the header's own
	-- regions (the title was hidden behind it)
	local textLayer = CreateFrame("Frame", nil, header)
	textLayer:SetAllPoints(header)
	textLayer:SetFrameLevel(header:GetFrameLevel() + 8)
	header.text = textLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	header.text:SetPoint("CENTER", header, "CENTER", 0, 0)
	header.text:SetText(TRACKER_ALL_OBJECTIVES or "All Objectives")
	-- the collapse toggle, the kit's minus / plus, on the title plate's
	-- right gem (placed by ApplyLook)
	local toggle = MakeToggle(textLayer, 16, function() return M.db.collapsed end, function()
		M.db.collapsed = not M.db.collapsed
		MelloUI:NotifySettingChanged(M.name, "collapsed", M.db.collapsed)
	end)
	toggle:SetPoint("RIGHT", header, "RIGHT", -4, 0)
	header.toggle, header.ToggleIcon = toggle, toggle.Refresh

	-- moved like every other window while the windows are unlocked (UI
	-- Modifications' mover: the screen darkens with its grid, the border
	-- lights, the corner snaps, the wheel scales it -- user, 2026-09-23: "does
	-- not have the same darkening ... also the mousewheel does not increase
	-- its scale"); it keeps its own place, hung by its top-right corner, and
	-- the wheel's scale is its Scale setting
	if MelloUI.RegisterMover then
		MelloUI:RegisterMover(frame, header, {
			min = 0.6, max = 1.6,   -- the Scale slider's range
			save = function()
				SavePosition()
				M.db.scale = math.floor(frame:GetScale() * 100 + 0.5) / 100
				last.valid = false   -- (dragged and scaled by the mover: laid again)
				Place()
				MelloUI:NotifySettingChanged(M.name, "pos", M.db.pos)
				MelloUI:NotifySettingChanged(M.name, "scale", M.db.scale)
			end,
			reset = function()
				M.db.pos, M.db.scale = nil, 1
				last.valid = false
				Place()
				MelloUI:NotifySettingChanged(M.name, "pos", nil)
				MelloUI:NotifySettingChanged(M.name, "scale", 1)
			end,
		})
	end

	clip = CreateFrame("Frame", nil, frame)
	clip:SetPoint("TOPLEFT", header, "BOTTOMLEFT", INSET, -INSET + 4)
	clip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(INSET + THUMB_W + 4), INSET)
	clip:SetClipsChildren(true)
	clip:EnableMouseWheel(true)
	Perf.SetScript(clip, "OnMouseWheel", function(_, delta) Scroll(delta) end)
	Perf.SetScript(clip, "OnSizeChanged", function() SetOffset(scrollOffset) end)

	-- the resize grip, bottom-left (the tracker hangs from its top-right
	-- corner): dragging sets its width and the height it may grow to
	-- (user, 2026-09-23: "the quest window should have the option to be
	-- rescaled"); while it follows the minimap's width, the height only (the
	-- width held by the bounds for the drag, its own Width setting kept)
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(FOLLOW_MIN, HEADER_H + 60, FOLLOW_MAX, 1200)
	end
	local widthHeld = false
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 3, 3)
	grip:SetFrameLevel(frame:GetFrameLevel() + 10)
	local gripTex = grip:CreateTexture(nil, "OVERLAY")
	gripTex:SetAllPoints(grip)
	gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	gripTex:SetTexCoord(1, 0, 0, 1)   -- mirrored: it points to the bottom-left
	grip:SetAlpha(0.35)
	Perf.SetScript(grip, "OnEnter", function(self)
		self:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Drag to size the tracker")
		GameTooltip:Show()
	end)
	Perf.SetScript(grip, "OnLeave", function(self)
		self:SetAlpha(0.35)
		GameTooltip:Hide()
	end)
	Perf.SetScript(grip, "OnMouseDown", function(_, button)
		if button ~= "LeftButton" then
			return
		end
		sizing = true
		last.valid = false   -- (the game sizes it by its points now: laid again after)
		widthHeld = followW ~= nil and frame.SetResizeBounds ~= nil
		if widthHeld then
			frame:SetResizeBounds(followW, HEADER_H + 60, followW, 1200)
		end
		frame:StartSizing("BOTTOMLEFT")
	end)
	Perf.SetScript(grip, "OnMouseUp", function()
		if not sizing then
			return
		end
		sizing = false
		frame:StopMovingOrSizing()
		local w, h = frame:GetWidth(), frame:GetHeight()
		if widthHeld then
			widthHeld = false
			frame:SetResizeBounds(FOLLOW_MIN, HEADER_H + 60, FOLLOW_MAX, 1200)
			M.db.maxHeight = math.floor(h + 0.5)
			MelloUI:NotifySettingChanged(M.name, "maxHeight", M.db.maxHeight)
			return
		end
		M.db.width = math.floor(w + 0.5)
		M.db.maxHeight = math.floor(h + 0.5)
		MelloUI:NotifySettingChanged(M.name, "width", M.db.width)
		MelloUI:NotifySettingChanged(M.name, "maxHeight", M.db.maxHeight)
	end)
	frame.grip = grip
	content = CreateFrame("Frame", nil, clip)
	content:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
	content:SetSize(ContentWidth(), 1)

	-- the scroll thumb: the kit's, or a plain bar, beside the list
	track = frame:CreateTexture(nil, "ARTWORK")
	track:SetColorTexture(0, 0, 0, 0.35)
	track:SetWidth(3)
	track:SetPoint("TOP", clip, "TOPRIGHT", THUMB_W / 2 + 3, 0)
	track:SetPoint("BOTTOM", clip, "BOTTOMRIGHT", THUMB_W / 2 + 3, 0)
	local Kit = MelloUI.Kit
	local okT, vstrip = false, nil
	if Kit and Kit.VStrip then
		okT, vstrip = pcall(Kit.VStrip, Kit, frame, "lists/scrollthumb", { state = "normal", scale = Kit.scale })
	end
	if okT and vstrip then
		thumb = vstrip
		thumb:SetWidth(THUMB_W + 2)
	else
		thumb = CreateFrame("Frame", nil, frame)
		thumb:SetWidth(THUMB_W - 2)
		local t = thumb:CreateTexture(nil, "ARTWORK")
		t:SetAllPoints(thumb)
		t:SetColorTexture(0.85, 0.7, 0.35, 0.8)
	end
	thumb:SetFrameLevel(frame:GetFrameLevel() + 6)
	thumb:Hide()
	track:Hide()

	ApplyLook()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local EVENTS = {
	"QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_ACCEPTED",
	"QUEST_REMOVED", "QUEST_TURNED_IN", "SUPER_TRACKING_CHANGED", "PLAYER_ENTERING_WORLD",
	"ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_COOLDOWN",
	-- the professions section: a recipe tracked or untracked, reagents gained
	"TRACKED_RECIPE_UPDATE", "BAG_UPDATE_DELAYED",
}

Perf.SetScript(eventFrame, "OnEvent", function(_, event, unit)
	if event == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then
		return
	end
	MarkDirty()
end)

-- Edit Mode: the game's tracker comes back to be moved and sized; ours
-- steps aside, then takes the new place and height (told through the kit's
-- one Edit Mode registration, the bus's 'editmode'; audit, 2026-09-24)
local editHooked = false
local function HookEditMode()
	if editHooked then
		return
	end
	editHooked = true
	-- the UI Scale changed (user, 2026-09-24: "UI Scaling Break the UI"):
	-- placed again (a saved place kept on the new screen, the width and the
	-- height taken from the game's tracker, which Edit Mode fits to the new
	-- screen) and rebuilt at that height
	local Kit = MelloUI.Kit
	if Kit and Kit.OnUIScaleChanged then
		Kit:OnUIScaleChanged(function(reason)
			if reason == "uiscale" and M.isEnabled and frame then
				-- out of combat: its quest item button is a secure frame on it
				Kit:WhenOutOfCombat(function()
					if M.isEnabled and not inEditMode and not sizing then
						Place()
						MarkDirty()
					end
				end)
			end
		end)
	end
	MelloUI:On("editmode", function(entering)
		inEditMode = entering
		if M.isEnabled then
			SetGameTracker(not entering)
			if frame then
				if entering then
					frame:Hide()
				else
					Place()
					MarkDirty()
				end
			end
		end
	end, M)
end

-- The kit's look switched on or off for this tracker (the bus's
-- 'look:questTracker', told on the frame after the reskin or the tracker's
-- own switch changed): its frame's look at once, every line's ink and colour
-- on the next rebuild -- the same as a tracker built in that look
local function OnLook()
	if M.isEnabled and frame then
		ApplyLook()
		MarkDirty()
	end
end

-- its parchment sheet switched on or off: ink or colour again (the bus's
-- 'parchment', fired at the end of Kit:SetParchment, where this hooked that
-- function; audit, 2026-09-24, rank 5)
local function OnParchment(area)
	if area == "questTracker" and M.isEnabled then
		MarkDirty()
	end
end

-- the column under the minimap re-laid (the bus's 'column', MinimapPanel):
-- where nobody placed it, it follows the column's bottom, and the map's
-- width while it matches it (FollowWidth); otherwise Place has the same
-- inputs and leaves the frame as it is. Its list laid again only when it
-- moved or its width changed. Out of combat: its quest item button is a
-- secure frame on it.
local function PlaceForColumn()
	if M.isEnabled and frame and not inEditMode and not sizing then
		local was, wasW = last.drop, followW
		Place()
		if last.drop ~= was or followW ~= wasW then
			MarkDirty()
		end
	end
end

local function OnColumn()
	local Kit = MelloUI.Kit
	if Kit and Kit.WhenOutOfCombat then
		Kit:WhenOutOfCombat(PlaceForColumn, "Quest Tracker column")
	else
		PlaceForColumn()
	end
end

-- The fitted layout's tracker anchor as Edit Mode saved it (the layout of
-- that name, the game's tracker's system): { point, relativeTo,
-- relativePoint, x, y }; nil on its default place or when it cannot be read
-- plainly. Read once an install put the layout in.
local function SavedAnchor(name)
	if type(name) ~= "string" or not (C_EditMode and C_EditMode.GetLayouts) then
		return nil
	end
	local ok, info = pcall(C_EditMode.GetLayouts)
	if not (ok and type(info) == "table" and type(info.layouts) == "table") then
		return nil
	end
	local system = Enum and Enum.EditModeSystem and Enum.EditModeSystem.ObjectiveTracker
	if Secret(system) or type(system) ~= "number" then
		system = 12
	end
	for _, layout in ipairs(info.layouts) do
		local lname = type(layout) == "table" and layout.layoutName
		if not Secret(lname) and lname == name and type(layout.systems) == "table" then
			for _, s in ipairs(layout.systems) do
				local a = type(s) == "table" and not Secret(s.system) and s.system == system and s.anchorInfo
				if type(a) == "table" then
					local p, to, rp, x, y = a.point, a.relativeTo, a.relativePoint, a.offsetX, a.offsetY
					if Secret(s.isInDefaultPosition) or s.isInDefaultPosition ~= false or Secret(p) or Secret(to)
						or Secret(rp) or Secret(x) or Secret(y) or type(p) ~= "string" or type(rp) ~= "string"
						or type(x) ~= "number" or type(y) ~= "number" then
						return nil
					end
					return { point = p, relativeTo = type(to) == "string" and to or "UIParent", relativePoint = rp, x = x, y = y }
				end
			end
			return nil
		end
	end
	return nil
end

-- The installer's answers (the bus's 'installer', heard whether this module
-- is on or not): an install that put the fitted layout in records where it
-- hung the game's tracker (FitPlace), read on the next frame (the install's
-- frame is long already; Edit Mode's saved layouts are a big read). The
-- record it replaced stays as long as the installer's restore point does
-- (Revert stays possible after Keep, until the next install): a revert puts
-- it back; an install that did not put the layout in has nothing to put back.
do
	local pendingName = nil   -- the fitted layout's name, its tracker read on the next frame

	local function Record()
		local name = pendingName
		pendingName = nil
		local db = MelloUI:GetModuleDB(M.name)
		if name == nil or type(db) ~= "table" then
			return
		end
		db.fitAnchor = SavedAnchor(name)
		-- (the column laid again on the next frame: the tracker takes it)
		local mp = MelloUI:GetModule("MinimapPanel")
		if mp and mp.LayColumn then
			mp:LayColumn()
		end
	end

	MelloUI:On("installer", function(what)
		local db = MelloUI:GetModuleDB(M.name)
		if type(db) ~= "table" then
			return
		end
		if what == "installed" then
			local rp = MelloUI.db and MelloUI.db.installer
			if type(rp) == "table" and rp.layoutPut and type(rp.layout) == "table" and type(rp.layout.name) == "string" then
				db.fitAnchorWas = db.fitAnchor or false
				pendingName = rp.layout.name
				local Kit = MelloUI.Kit
				if Kit and Kit.NextFrame then
					Kit:NextFrame("Quest Tracker fit place", Record)
				else
					Record()
				end
			else
				pendingName = nil
				db.fitAnchorWas = nil
			end
		elseif what == "reverted" then
			pendingName = nil
			if db.fitAnchorWas ~= nil then
				db.fitAnchor = db.fitAnchorWas or nil
				db.fitAnchorWas = nil
			end
		end
	end, "Quest Tracker fit place")
end

local listening = false
local function Listen()
	if listening then
		return
	end
	listening = true
	MelloUI:On("look:questTracker", OnLook, M)
	MelloUI:On("parchment", OnParchment, M)
	MelloUI:On("column", OnColumn, M)
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	local again = frame ~= nil   -- (switched on again: Build keeps its frame)
	Build()
	HookEditMode()
	for _, event in ipairs(EVENTS) do
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
	pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_QUEST_LOG_CHANGED", "player")
	if not inEditMode then
		SetGameTracker(true)
	end
	ApplyLook()
	frame:Show()
	-- switched on again: placed again for what changed while it was off
	-- (the 'column' it missed: the minimap's width it follows, the column's
	-- drop; review, 2026-09-25), as a 'column' is, after a fight. Place
	-- leaves it as it is when nothing changed.
	if again then
		OnColumn()
	end
	-- the look and the parchment sheet switched: followed live
	Listen()
	MarkDirty()
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	DetachOverlay()
	if frame then
		frame:Hide()
	end
	SetGameTracker(false)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if frame and not sizing then
		Place()   -- width, scale; and back on the game's tracker after a drag
	end
	if header and header.ToggleIcon then
		header.ToggleIcon()
	end
	ApplyLook()
	MarkDirty()
end

MelloUI:Profile("QuestTracker", "tracker rebuild", Rebuild)
