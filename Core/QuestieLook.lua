--------------------------------------------------------------------------------
-- MelloUI - Questie in MelloUI's look (2.1.39; the user, 2026-11-10: "i want the questie Quest Tracker, with its
-- format inside of our Quest Tracker when Questie is enabled, i want our to step aside, so basically Questie Function
-- but our Look ... if questie has a quest tracker, i want its functions and layout, but our Look and feel").
--
-- Questie's tracker, while its tracker is on (Overlaps' questTracker: MelloUI's own steps aside, Modules/
-- QuestTracker.lua), keeps all it does -- its lines and their order, its clicks and menus, its sizes, its place -- and
-- wears MelloUI's tracker's look:
--   * the panel behind it: the palette's dark inner panel, the gold rim and the UI shade (W.Panel; the tracker's own
--     Art.PANEL_ALPHA), at the Quest Tracker's Background Opacity
--   * its title and its zones' names in the title face and the palette's gold, a hairline under each, as the
--     tracker's title and headings: texts of MelloUI's own laid over Questie's (Questie's rows are as tall as its
--     own size, too small for the title face's), Questie's out of sight
--   * its quests and objectives in the interface text's face at Questie's own sizes, put on the moment Questie sets
--     its font (a hook on each line's text), so Questie measures and wraps them in that face. One font file there,
--     as Questie's own: a face only where it has the client's letters (Fonts' FaceFits), else Questie's stays
--   * its quests' + / - in the Configurator's glyphs (W.FlatOver), its zones' beside their names, its title's icon
--     the game's quest mark (as its icons on MelloUI's map), its quest items on the tracker's tray (W.TrayBox), its
--     quests' focus buttons (Questie 12.6) MelloUI's tracker's own quest marks (the !, the ?, Route's flag)
--   * a leveling guide's steps stay MelloUI's tracker's, docked on top of Questie's (Modules/QuestTracker.lua's Dock;
--     told here when Questie's shows, hides or changes size), on their own while Questie's has nothing to list (Empty)
-- Its quest icons never take the place of MelloUI's (the user, 2026-11-10: "didnt i say that we provide the look? this
-- way we have lost our own function which i like very much"): where MelloUI draws a kind itself -- the minimap's
-- objective marks, the game's map's givers and objective marks (Drawn) -- Questie's of that kind are out of sight, its
-- mouse off; on MelloUI's own map MapAddonPins lends it only what its layers leave out. The others on the minimap (and
-- on the game's map while MelloUI's map is off) wear MelloUI's pictures (QL.ICONS): the quest givers' marks, the icon
-- set's objectives -- put on Questie's own picture when Questie sets it (a hook on its icons' UpdateTexture), so its
-- fading, sizes, glow, clicks and tooltips stay Questie's; all given back when Questie lets the icon go (its Unload).
-- The Quest Tracker's settings on it (2.1.53, the user's word): its width (or the minimap's), height, text sizes, sort
-- and place written into Questie's own while the look is on, its own given back after (Apply, Give). No other setting
-- of Questie's written but two once (KeepOpenInDungeons; the nameplates'); a hook on its tracker's Update (that never
-- yields: never its Initialize, nor its line pool's, which do -- the no-hooks-on-coroutine-addons rule). Questie's own
-- look back whenever MelloUI's
-- Quest Tracker is switched off or Questie's tracker is. Made at its first dressing, never at login.
--   MelloUI.QuestieLook.Dress()   lay it again (after Questie's Update, a palette, a setting)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("QuestieLook")
local Number = MelloUI.Safe.Number
local hooksecurefunc = Perf.hooksecurefunc   -- (their time under this file's name in /melloperf)

local QL = {}
MelloUI.QuestieLook = QL

QL.PANEL_ALPHA = 0.94           -- (the tracker's own panel: Art.PANEL_ALPHA)
QL.TRAY_ALPHA = 0.95            -- (its quest items' tray: Art.TRAY_ALPHA)
QL.FLAT_OPTS = { area = "questTracker" }
QL.EDGE = 8                     -- the title's hairline in from the panel's sides
QL.MARK_ATLAS = "QuestTurnin"   -- the title's icon: the game's quest mark (MapAddonPins' QUESTIE_LOOK.complete)
QL.REDO = 0.2                   -- Questie's Update again once its lines took their faces (its own throttle: 0.1)

local S = { on = false, hooked = false, panel = nil, busy = false, redo = false }
local owners = setmetatable({}, { __mode = "k" })   -- [Questie's line text] = its line (the hook laid)
local heads = setmetatable({}, { __mode = "k" })    -- [Questie's text: title, zone] = our text over it
local glyphs = setmetatable({}, { __mode = "k" })   -- [Questie's + / -, a zone line] = our glyph's holder
local rules = setmetatable({}, { __mode = "k" })    -- [a zone line] = its hairline
local layers = setmetatable({}, { __mode = "k" })   -- [a zone line] = our frame on it (Questie's lines are buttons:
                                                    -- a button colours texts of its own; this one draws ours)
local trays = setmetatable({}, { __mode = "k" })    -- [Questie's quest item] = its tray (false: none)
local marks = setmetatable({}, { __mode = "k" })    -- [Questie's title icon] = our picture on it

-- a module of Questie's (its loader's; nil when it is not there)
local function Questie(name)
	local L = rawget(_G, "QuestieLoader")
	if type(L) ~= "table" or type(L.ImportModule) ~= "function" then
		return nil
	end
	local ok, mod = pcall(L.ImportModule, L, name)
	return ok and type(mod) == "table" and mod or nil
end

local function Tracker()
	local m = MelloUI.modules and MelloUI.modules.QuestTracker
	return type(m) == "table" and m or nil
end

-- (2.1.44) Questie's switch on the Addons page, Use with MelloUI (Core/Integrations.lua): off, Questie in its own look
local function Used()
	local I = rawget(MelloUI, "Integrations")
	return not (I and not I.Use("Questie"))
end
QL.Used = Used

-- (2.1.51; the user, 2026-11-13, Questie's Quest Level Options at a set level below the player and MelloUI's map still
-- full of low quests: "i dont want melloUI Quests to show if Questie is active") Questie decides which quest givers and
-- turn-ins show while it is loaded and used with MelloUI (the Addons page): MelloUI's own step aside on every map (the
-- Quest List's QL.GiverGroups and its dungeon starters) and Questie's are drawn by its own rules -- its level options
-- too -- in MelloUI's pictures; a map's Quest givers switch shows or hides them. MelloUI's objective marks and quest
-- areas stay MelloUI's (the user, 2026-11-10: "our own function which i like very much")
-- (2.1.52, stage 2: MelloUI has no quest data of its own) so whenever Questie is there -- in MelloUI's look or, its
-- switch off, in its own (Core/QuestSource.lua's states) -- and never MelloUI's own
function QL.Givers()
	local QS = rawget(MelloUI, "QuestSource")
	return QS ~= nil and QS.Lib() ~= nil
end

-- dressed: MelloUI's Quest Tracker on, stepped aside for Questie's
local function On()
	local m = Tracker()
	local OV = rawget(MelloUI, "Overlaps")
	return (Used() and m and m.isEnabled and type(OV) == "table" and type(OV.By) == "function"
		and OV.By("questTracker") == "Questie") and true or false
end
QL.InUse = On   -- (2.1.53: the Quest Tracker's rows Questie's tracker has nothing for sleep by it: ownLines)

--------------------------------------------------------------------------------
-- Faces
--------------------------------------------------------------------------------

-- the interface text's face for a one-file text (nil: Questie's stays)
local function BodyFace()
	local face = type(MelloUI.FontFace) == "function" and MelloUI.FontFace("fontText") or nil
	if type(face) ~= "string" or face == "" then
		return nil
	end
	if type(MelloUI.FaceFits) == "function" and not MelloUI.FaceFits(face) then
		return nil
	end
	return face
end

-- Questie set a line's font (its SetMode: every Update, before it measures): the interface face on it at once, at
-- Questie's size and flags; its title lines' (zones) are ours to draw (Heads)
local function OnFont(fs, _, size, flags)
	if S.busy or not S.on then
		return
	end
	local line = owners[fs]
	if not line or rawget(line, "mode") == "zone" then
		return
	end
	local face = BodyFace()
	size = Number(size)
	if not (face and size and size > 0) then
		return
	end
	local k = type(MelloUI.FontFaceFactor) == "function" and MelloUI.FontFaceFactor("fontText", face) or 1
	S.busy = true
	pcall(fs.SetFont, fs, face, math.max(6, math.floor(size * k + 0.5)), type(flags) == "string" and flags or "")
	S.busy = false
end

-- a line's text hooked once (the lines Questie uses: the next Update measures them in the face)
local function Own(line)
	local fs = rawget(line, "label")
	if not fs or owners[fs] then
		return
	end
	owners[fs] = line
	hooksecurefunc(fs, "SetFont", OnFont)
	S.redo = true
end

-- our heading over Questie's text: the title face at Questie's size (the tracker's StyleText + Kit:TitleFont), the
-- palette's gold; its colour codes left out
local function Head(over, parent, width)
	local fs = heads[over]
	if not fs then
		fs = parent:CreateFontString(nil, "OVERLAY", "MelloUIFont_GameFontNormal")
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		heads[over] = fs
	end
	local _, size = over:GetFont()
	size = Number(size) or 12
	if fs.questieSize ~= size then
		fs.questieSize = size
		local Kit, base = MelloUI.Kit, GameFontNormal
		if Kit and Kit.TitleFont and Kit.fontSavedOf and Kit.fontSavedOf[fs] then
			pcall(Kit.TitleFont, Kit, fs, false)
		end
		local ok, path, _, flags = pcall(base.GetFont, base)
		if ok and path then
			MelloUI:SetFace(fs, path, size, flags or "", base)
		end
		if Kit and Kit.TitleFont then
			pcall(Kit.TitleFont, Kit, fs, true, true)
		end
		MelloUI.Look.Paint(fs, "selectedTrim", "text")
	end
	local text = MelloUI.Safe.Text(over:GetText()) or ""
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s*%+$", "")
	fs:SetText(text)
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", over, "LEFT", 0, 0)
	-- (to the panel's right edge, given by the caller: Questie's text is as wide as its own face makes it, and the
	-- title face is wider -- the game, 2026-11-10: "Questie Tracker: 2..." cut short)
	fs:SetWidth(width or Number(over:GetWidth()) or 200)
	over:SetAlpha(0)
	fs:Show()
	return fs
end

local function Unhead(over)
	local fs = heads[over]
	if fs then
		fs:Hide()
		over:SetAlpha(1)
	end
end

--------------------------------------------------------------------------------
-- The pieces
--------------------------------------------------------------------------------

-- the panel behind the whole of it (the tracker's BuildKitLook: the chat's look)
local function Panel(base)
	if S.panel ~= nil then
		return S.panel
	end
	S.panel = false
	local Kit, W = MelloUI.Kit, MelloUI.Widgets
	if not (type(W) == "table" and W.Panel and W.HairSolid) then
		return false
	end
	local holder = CreateFrame("Frame", nil, base)
	holder:SetAllPoints(base)
	holder:SetFrameLevel(base:GetFrameLevel())
	holder:EnableMouse(false)
	W.Panel(holder, { on = true, alpha = QL.PANEL_ALPHA, rim = true })
	local Rims = rawget(MelloUI, "Rims")
	if type(Rims) == "table" and Rims.OwnEdge then
		Rims:OwnEdge(holder)
	end
	if Kit and Kit.ShadeElement then
		Kit:ShadeElement(holder, "tracker"):Add(holder, { shape = "shade/square" })
	end
	local hair = W.HairSolid(holder, "ARTWORK")
	hair:SetHeight(1)
	holder.hair = hair
	S.panel = holder
	-- (2.1.39; the user, 2026-11-10: "did you make sure that other themes got their looks?") the looks MelloUI's own
	-- tracker wears (Modules/QuestTracker.lua's BuildKitLook): the tracker's parchment sheet while its Parchment is on
	-- (Kit:SetParchment shows and hides it), Questie's text in ink on it (QuestInk's surface of the questTracker area:
	-- the parchment's switch refreshes it by that name), and the Default skin's game headers (GameLook, below)
	holder.sheet = Kit and Kit.ParchmentSheet
		and Kit:ParchmentSheet(holder, base, { rect = base, margin = 3, area = "questTracker" }) or nil
	local QI = rawget(MelloUI, "QuestInk")
	if type(QI) == "table" and type(QI.Surface) == "function" then
		QI.Surface("questTracker", { sheet = true,
			on = function() return S.on and Kit and Kit.ParchmentOn and Kit:ParchmentOn("questTracker") or false end,
			roots = function() return rawget(_G, "Questie_BaseFrame") end })
	end
	local Skin = rawget(MelloUI, "Skin")
	if type(Skin) == "table" and Skin.Follow then
		Skin.Follow(holder, QL.GameLook)
	end
	return holder
end

-- (2.1.52; the test VM, 2026-11-14, the user: "Yes, keep it on") the panel's rim on the screen. Questie's default
-- place is the game's quest watch frame's (QuestieCompat.GetWatchFramePoint): its frame's right edge the screen's, and
-- the gold rim stands outward of the panel's edge (MelloUI.Rims.T: its band less its tuck) -- off the screen there.
-- A side of Questie's frame nearer the screen's edge than the rim's room: the panel's side in by what is missing, never
-- by more than that room (a tracker dragged past the screen's edge takes its panel with it). Clear of the edges, and
-- under the Default skin (no rim there: Rims:OwnEdge): the panel on Questie's frame as before. Laid at every dressing
-- (Questie's Update: its tracker moved or sized, the skin switched); Questie's frame and its place untouched
local function Inward(room, out, scale)
	return math.max(0, math.min(out, out - room)) / scale
end

local function Seat(base, panel)
	local inL, inB, inR, inT = 0, 0, 0, 0
	local Rims = rawget(MelloUI, "Rims")
	local T = type(Rims) == "table" and Rims.T or nil
	local out = T and (Number(T.band) or 0) - (Number(T.tuck) or 0) or 0
	if out > 0 and not panel.game then
		local Rect = MelloUI.Safe.ScreenRect
		local l, b, r, t = Rect(base)
		local sl, sb, sr, st = Rect(UIParent)
		local scale = Number(base:GetEffectiveScale())
		if l and sl and scale and scale > 0 then
			local px = out * scale
			inL, inB = Inward(l - sl, px, scale), Inward(b - sb, px, scale)
			inR, inT = Inward(sr - r, px, scale), Inward(st - t, px, scale)
		end
	end
	if panel.inL ~= inL or panel.inB ~= inB or panel.inR ~= inR or panel.inT ~= inT then
		panel.inL, panel.inB, panel.inR, panel.inT = inL, inB, inR, inT
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", base, "TOPLEFT", inL, -inT)
		panel:SetPoint("BOTTOMRIGHT", base, "BOTTOMRIGHT", -inR, inB)
	end
end

-- (2.1.52; the configurator pass in the test VM, 2026-11-14: a taller minimap, or a second row of Services, lay under
-- Questie's tracker -- the user: "Yes, go ahead") where nobody placed it, Questie's tracker hangs under MelloUI's
-- minimap column as MelloUI's own tracker does (Modules/QuestTracker.lua's Glue): its top right corner QL.COLUMN_GAP
-- under the column's bottom, on the frame the column lines up to (MinimapPanel's ColumnAnchor) -- an anchor, so it
-- moves with the map; laid again at each dressing and at the bus's 'column' (the column's foot moved). "Nobody
-- placed it": Questie keeps no place of the player's (its TrackerLocation: nil in a profile until the first drag;
-- Questie's own Reset Tracker writes one too, the screen's middle -- seen in the test VM on 12.9) -- a tracker dragged
-- or reset is the player's, never moved. No setting of Questie's is written: its frame's one
-- anchor only, written when it stands elsewhere, never in a fight (the dressing's own rule). Without MelloUI's
-- minimap, or once the look goes off: back on Questie's own default (QuestieCompat.GetWatchFramePoint, as Questie
-- lays it at its start)
QL.COLUMN_GAP = 8   -- (MelloUI's own tracker's: Modules/QuestTracker.lua's COLUMN_GAP)

-- Questie's profile (its settings; nil before it made them)
local function Profile()
	local Q = rawget(_G, "Questie")
	local qdb = type(Q) == "table" and rawget(Q, "db")
	local profile = type(qdb) == "table" and qdb.profile
	return type(profile) == "table" and profile or nil
end

local function Unplaced()
	local profile = Profile()
	return profile ~= nil and profile.TrackerLocation == nil
end

local function Unfollow(base)
	if not S.followed then
		return
	end
	S.followed = nil
	if not (base and Unplaced()) or InCombatLockdown() then
		return   -- (a place of the player's since: Questie laid it there itself)
	end
	local QC = Questie("QuestieCompat")
	local own = QC and rawget(QC, "GetWatchFramePoint")
	if type(own) == "function" then
		local point = { pcall(own) }
		if point[1] and type(point[2]) == "string" then
			base:ClearAllPoints()
			pcall(base.SetPoint, base, unpack(point, 2))
		end
	end
end

local function HangUnder(base)
	local mp = Unplaced() and MelloUI:GetModule("MinimapPanel")
	if not (mp and mp.isEnabled and type(mp.ColumnAnchor) == "function") then
		Unfollow(base)
		return
	end
	local ok, region, point, dy = pcall(mp.ColumnAnchor, mp)
	dy = ok and Number(dy) or nil
	local scale = Number(base:GetEffectiveScale())
	if not (region and type(point) == "string" and dy and scale and scale > 0) then
		Unfollow(base)
		return
	end
	-- (a thousandth of a unit: a column that did not move lays the same)
	local y = math.floor((dy / scale - QL.COLUMN_GAP) * 1000 + 0.5) / 1000
	local at, rel, relPoint, x0, y0 = base:GetPoint(1)
	if not (base:GetNumPoints() == 1 and at == "TOPRIGHT" and rel == region and relPoint == point
		and Number(x0) == 0 and Number(y0) and math.abs(y0 - y) < 0.005) then
		base:ClearAllPoints()
		base:SetPoint("TOPRIGHT", region, point, 0, y)
	end
	S.followed = true
end

-- the Quest Tracker's Background Opacity on the panel's fill and its shade (Default: the backing band's strength)
local function Opacity(panel)
	local m = Tracker()
	local o = Number(m and m.db and m.db.opacity)
	o = o and math.max(0, math.min(1, o)) or 1
	if panel.panelFill then
		MelloUI.Widgets.Paint(panel.panelFill, "innerPanel", "fill", QL.PANEL_ALPHA * o)
	end
	local spec = m and m.BACKING
	if panel.backing and spec then
		panel.backing:SetStrength(spec.alpha * o)
	end
	local Kit = MelloUI.Kit
	local el = Kit and Kit.ShadeElement and Kit:ShadeElement(panel, "tracker")
	if el and el.SetAlpha then
		el:SetAlpha(o)
	end
end

-- (2.1.53; the user, 2026-11-15: "the Questie Custom Quest Tracker does not Respond to Any setting in the Quest Tracker
-- category in the Configurator", asked whether MelloUI may write them into Questie's own: "Yes, write them") Questie
-- lays its tracker from its own profile only, so while it wears MelloUI's look the Quest Tracker's settings are
-- written there, each only where it differs, and Questie's Update asked for once to lay them:
--   Width, or Match The Minimap's Width -> TrackerWidth (the minimap column's width on the screen, in Questie's units)
--   Height -> TrackerHeight
--   Text Size -> its quests' and zones' text, one size smaller its objectives' (as MelloUI's tracker draws them)
--   Header Text Size -> its title's
--   Nearest Quest First -> its sort By Proximity (off: its own sort, By Zone where its own was a nearness)
--   Reset Position -> its place forgotten (TrackerLocation): back under the minimap column (HangUnder)
-- Questie's own values kept the first time one is written (the Quest Tracker's keep, questieOwn: never in a profile,
-- a reload in between keeps them) and given back as the look goes off (Give). A size dragged on Questie's own corner
-- (Questie writes TrackerWidth / TrackerHeight as it sizes) comes back as MelloUI's Width (Match The Minimap's Width
-- off) and Height; Questie's own text and sort options are MelloUI's while the look is on. The settings Questie's
-- tracker has nothing for sleep in the Configurator (ownLines, Modules/QuestTracker.lua). (After nameplateEnabled and
-- minimizeTrackerInInstances, the third of Questie's settings MelloUI writes at the user's word; these while the look is
-- on only)
QL.SET_KEYS = { "TrackerWidth", "TrackerHeight", "trackerFontSizeQuest", "trackerFontSizeZone",
	"trackerFontSizeObjective", "trackerFontSizeHeader", "trackerSortObjectives" }
QL.SET_BY = { width = true, matchMinimap = true, maxHeight = true, textSize = true, headerSize = true, nearestFirst = true }
QL.SORT_NEAR = "byProximity"
QL.SORT_OWN = "byZone"   -- (Questie's default sort)
S.want, S.wrote = {}, {}   -- [Questie's key] = MelloUI's value; the value it had after the last write (or look)

local function Round(v)
	return math.floor(v + 0.5)
end

-- the minimap column's width in Questie's units, while the tracker matches it (nil: Width's own)
local function ColumnWidth(base, db)
	if db.matchMinimap == false then
		return nil
	end
	local mp = MelloUI:GetModule("MinimapPanel")
	if not (mp and mp.isEnabled and type(mp.ColumnWidth) == "function") then
		return nil
	end
	local ok, _, line = pcall(mp.ColumnWidth, mp)
	line = ok and Number(line) or nil
	local scale = Number(base:GetEffectiveScale())
	if not (line and line > 0 and scale and scale > 0) then
		return nil
	end
	return Round(line / scale)
end

-- Questie dragging its tracker's corner (its own sizer: it writes the size itself meanwhile)
local function Sizing()
	local TB = Questie("TrackerBaseFrame")
	return TB ~= nil and rawget(TB, "isSizing") == true
end

-- what MelloUI's settings make of Questie's (S.want)
local function Wants(base, profile, db)
	local want = S.want
	local text = Round(tonumber(db.textSize) or 13)
	want.TrackerWidth = ColumnWidth(base, db) or math.max(0, Round(tonumber(db.width) or 0))
	want.TrackerHeight = math.max(0, Round(tonumber(db.maxHeight) or 0))
	want.trackerFontSizeQuest = text
	want.trackerFontSizeZone = text
	want.trackerFontSizeObjective = math.max(6, text - 1)
	want.trackerFontSizeHeader = Round(tonumber(db.headerSize) or 16)
	if db.nearestFirst ~= false then
		want.trackerSortObjectives = QL.SORT_NEAR
	else
		local own = type(db.questieOwn) == "table" and db.questieOwn.trackerSortObjectives
		local was = type(own) == "string" and own or profile.trackerSortObjectives
		want.trackerSortObjectives = (type(was) == "string" and not was:find("^byProximity")) and was or QL.SORT_OWN
	end
end

-- a size dragged on Questie's corner since the last write: MelloUI's Width / Height. A 0 is Questie's reset (its
-- Reset Tracker, a right-click on its corner: QuestieTracker:ResetLocation), never a size: MelloUI's written again
local function TakeBack(profile, db)
	local w, h = Number(profile.TrackerWidth), Number(profile.TrackerHeight)
	local ww, wh = S.wrote.TrackerWidth, S.wrote.TrackerHeight
	local newW = w and ww and w >= 1 and math.abs(w - ww) >= 1 and Round(w) or nil
	local newH = h and wh and h >= 1 and math.abs(h - wh) >= 1 and Round(h) or nil
	if not (newW or newH) then
		return
	end
	S.taking = true
	if newW then
		db.width, db.matchMinimap = newW, false
		MelloUI:NotifySettingChanged("QuestTracker", "width", newW)
		MelloUI:NotifySettingChanged("QuestTracker", "matchMinimap", false)
	end
	if newH then
		db.maxHeight = newH
		MelloUI:NotifySettingChanged("QuestTracker", "maxHeight", newH)
	end
	S.taking = false
end

-- MelloUI's settings into Questie's profile -> true when one was written (Questie's Update then lays it)
local function Apply(base)
	local profile, m = Profile(), Tracker()
	local db = m and m.db
	if not (profile and type(db) == "table") or Sizing() then
		return false
	end
	TakeBack(profile, db)
	Wants(base, profile, db)
	local changed = false
	for i = 1, #QL.SET_KEYS do
		local k = QL.SET_KEYS[i]
		local v = S.want[k]
		if v ~= nil and profile[k] ~= v then
			if type(db.questieOwn) ~= "table" then
				db.questieOwn = {}
			end
			if db.questieOwn[k] == nil then
				db.questieOwn[k] = profile[k]
			end
			profile[k] = v
			changed = true
		end
		S.wrote[k] = profile[k]
	end
	return changed
end

-- Questie's own values back (the look gone off)
local function Give()
	local profile, m = Profile(), Tracker()
	local db = m and m.db
	local own = type(db) == "table" and db.questieOwn
	if type(own) == "table" then
		if profile then
			for k, v in pairs(own) do
				profile[k] = v
			end
		end
		db.questieOwn = nil
	end
	for k in pairs(S.wrote) do
		S.wrote[k] = nil
	end
end

-- a setting changed (or the minimap column's width): written, and laid by Questie's Update at once
local function Settle()
	local base = rawget(_G, "Questie_BaseFrame")
	if not (S.on and base) or S.taking or InCombatLockdown() then
		return
	end
	if Apply(base) then
		local QT = Questie("QuestieTracker")
		if QT and type(QT.Update) == "function" then
			pcall(QT.Update, QT)
		end
	end
end

-- Reset Position: Questie's place forgotten, its tracker back under the minimap column (or on its own default place
-- without MelloUI's minimap: Unfollow)
local function Reset()
	local base, profile = rawget(_G, "Questie_BaseFrame"), Profile()
	if not (S.on and base and profile) or InCombatLockdown() then
		return
	end
	profile.TrackerLocation = nil
	S.followed = true
	QL.Dress()
end

-- a + or - of the Configurator's over a button of Questie's (its picture out of sight), or beside a zone's name
local function Glyph(key, parent, kind)
	local holder = glyphs[key]
	if holder == nil then
		local W = MelloUI.Widgets
		if not (type(W) == "table" and W.FlatOver) then
			glyphs[key] = false
			return nil
		end
		holder = CreateFrame("Frame", nil, parent)
		holder:EnableMouse(false)
		holder.flat = W.FlatOver(holder, kind, QL.FLAT_OPTS)
		glyphs[key] = holder
	end
	if not holder then
		return nil
	end
	local W = MelloUI.Widgets
	W.FlatShown(holder.flat, true)
	W.FlatKind(holder.flat, kind)
	W.FlatState(holder.flat, false)
	holder:Show()
	return holder
end

local function Unglyph(key)
	local holder = glyphs[key]
	if holder then
		holder:Hide()
	end
end

-- our frame on a zone line: its heading, hairline and glyph (shown and hidden with the line; the mouse Questie's)
local function Layer(line)
	local layer = layers[line]
	if not layer then
		layer = CreateFrame("Frame", nil, line)
		layer:SetAllPoints(line)
		layer:EnableMouse(false)
		layers[line] = layer
	end
	layer:Show()
	return layer
end

local sections = setmetatable({}, { __mode = "k" })   -- [a zone line] = the game's section bar behind it (Default)

-- the hairline under a zone's name, out to the panel's right edge (the tracker's section rows': the palette's border);
-- under the Default skin the game's module header bar behind the name instead (the tracker's Art.SectionLook)
local function Rule(line, layer, label, width)
	local game = S.panel and S.panel.game or false
	local t = rules[line]
	if not t then
		t = layer:CreateTexture(nil, "ARTWORK")
		t:SetHeight(1)
		MelloUI.Look.Paint(t, "border", "fill", 1)
		rules[line] = t
	end
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
	t:SetWidth(width)
	t:SetShown(not game)
	-- (the user's game, 2026-11-10: "default one looks displaced", then "its still misplaced ingame") the bar on a frame
	-- of ours inside Questie's line -- so its list's scroll frame clips it with the line (on the panel, the bars of
	-- zones scrolled out of view showed over the docked guide) -- one level under the lines, and sized to Questie's
	-- zone line as the game sizes it to its header row (Blizzard_ObjectiveTrackerModule.xml: the 300 x 30 bar on a
	-- 26-high row, its text 7 in and centred in height): Questie's zone line is shorter (its zone font and padding),
	-- and at the bar's own size its lower edge ran across the next line and its ends past the panel. Its middle on the
	-- zone's name, from 7 before the name to the panel's right edge; hidden with the line by DressLine
	local art = sections[line]
	local Skin = rawget(MelloUI, "Skin")
	if game and not art and Skin and Skin.ART then
		local under = CreateFrame("Frame", nil, line)
		under:SetAllPoints(line)
		under:EnableMouse(false)
		under:SetFrameLevel(math.max(0, line:GetFrameLevel() - 1))
		art = under:CreateTexture(nil, "BACKGROUND")
		art:SetAtlas(Skin.ART.trackerSection, false)
		sections[line] = art
	end
	if art then
		local h = Number(line:GetHeight()) or 16
		art:ClearAllPoints()
		art:SetPoint("LEFT", label, "LEFT", -QL.SECTION_IN, 0)
		art:SetSize(width + QL.SECTION_IN, math.max(1, math.floor(h * QL.SECTION_H + 0.5)))
		art:SetShown(game)
	end
end
QL.SECTION_IN = 7          -- (the game's module header: its text 7 in from the bar's start)
QL.SECTION_H = 30 / 26     -- (its bar 30 high on a 26-high row: as much taller than Questie's zone line)

-- (2.1.39) the Default skin's look on Questie's tracker, as on MelloUI's own (its Art.GameLook: the user's pick 4B of
-- default_windows_sketch, "the game's headers, MelloUI's lines" on "a soft dark backing"): the game's tracker header
-- bar behind its title row, the module header bar behind each zone's name (Rule), the soft backing band under the
-- lines (the tracker's own BACKING) and no box -- the panel's fill, edges and hairline stand down; Modern as before.
-- Followed through MelloUI.Skin (laid now and at every switch); the zones' bars at the next dressing
function QL.GameLook(holder, isDefault)
	local game = isDefault and true or false
	holder.game = game
	if holder.panelFill then
		holder.panelFill:SetShown(not game)
	end
	for _, edge in ipairs(holder.panelEdges or {}) do
		edge:SetShown(not game)
	end
	local Skin = rawget(MelloUI, "Skin")
	local header = rawget(_G, "Questie_HeaderFrame")
	if game and not holder.headArt and header and Skin and Skin.ART then
		local art = holder:CreateTexture(nil, "BACKGROUND", nil, 1)
		art:SetAtlas(Skin.ART.trackerHead, true)
		art:SetPoint("CENTER", header, "CENTER", 0, 0)
		holder.headArt = art
		local m = Tracker()
		local spec = m and m.BACKING
		local band = spec and MelloUI.Shade and MelloUI.Shade:Band(holder, spec)
		if band then
			local rect = CreateFrame("Frame", nil, holder)
			rect:EnableMouse(false)
			rect:SetPoint("TOPLEFT", header, "BOTTOMLEFT", spec.feather, 0)
			rect:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -spec.feather, spec.featherY)
			band:Anchor(rect)
		end
		holder.backing = band
	end
	if holder.headArt then
		holder.headArt:SetShown(game)
	end
	if holder.backing then
		holder.backing:SetShown(game)
	end
	if game and holder.hair then
		holder.hair:Hide()
	end
	for _, t in pairs(rules) do
		t:SetShown(not game)
	end
	if not game then
		for _, art in pairs(sections) do
			art:Hide()   -- (shown again only on a zone's line, by the dressing below)
		end
	end
	-- (the zones dressed under the other look: laid again, out of this call -- the first one runs inside the dressing)
	if S.on then
		C_Timer.After(0, function()
			QL.Dress()
		end)
	end
end

-- a quest item on the tracker's tray (made out of a fight: Questie's buttons are secure ones)
local function Tray(btn)
	local tray = trays[btn]
	if tray == nil then
		trays[btn] = false
		local W = MelloUI.Widgets
		if not (type(W) == "table" and W.TrayBox) or InCombatLockdown() then
			trays[btn] = nil
			return
		end
		tray = W.TrayBox(btn, { alpha = QL.TRAY_ALPHA })
		tray:EnableMouse(false)
		tray:SetFrameLevel(math.max(0, btn:GetFrameLevel() - 1))
		tray:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
		tray:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
		trays[btn] = tray
	end
	if tray then
		tray:Show()
	end
end

-- the title's icon: the game's quest mark over Questie's
local function Mark(icon)
	local tex = marks[icon]
	if not tex then
		tex = icon:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints(icon)
		tex:SetAtlas(QL.MARK_ATLAS)
		marks[icon] = tex
	end
	local own = rawget(icon, "texture")
	if own and own.SetAlpha then
		own:SetAlpha(0)
	end
	tex:Show()
end

local function Unmark(icon)
	local tex = marks[icon]
	if tex then
		tex:Hide()
		local own = rawget(icon, "texture")
		if own and own.SetAlpha then
			own:SetAlpha(1)
		end
	end
end

-- (the user's pick A of questie_focus_sketch, 2026-11-10: "A, our marks"; then "i still dont see our buttons to set the
-- route for the quest in the Questie quest tracker"; then, on Questie 12.0.4 in the game, "i dont see the navigation
-- buttons here") a quest line's mark is MelloUI's tracker's own, doing what it does there, whatever Questie's version:
-- the quest's mark (the tracker's Act.MarkIcon: under way the gold !, done the green ?, followed Route's flag -- red
-- with the beads, cream with the line). Its place: Questie 12.6 on, the slot it keeps for its focus button (while its
-- trackerShowQuestFocusButtons, on by default, keeps one; Questie's picture under ours out of sight); before, the
-- line's own left edge -- its - button stands 15 px in at any size (12.0.4's margins) -- or past the quest item that
-- takes that edge (none with two items: no room). A click follows the quest -- the game's super-track, the way Route
-- shows (QuestActs.Follow) -- and again lets it go; a right-click is Questie's own quest menu (its line's right click:
-- its focus there too). The hover's glow the mark added on itself (a HIGHLIGHT layer)
QL.MARK_HINT = "Click: follow it, the way shown  -  Click again: stop following  -  Right-click: Questie's menu"
QL.MARK_MAX = 14   -- (before 12.6: the mark in the 15 px left of the - button)
local routeMarks = setmetatable({}, { __mode = "k" })   -- [a quest line of Questie's] = our mark (a button of ours)
local covered = setmetatable({}, { __mode = "k" })      -- [Questie's focus button] = true while ours lies over it

local MarkClick = Perf.Shared("OnClick on a Questie quest line's MelloUI mark", function(self, button)
	local id = self.questID
	if not id then
		return
	end
	if button == "RightButton" then
		local line = self:GetParent()
		if line and line.Click then
			line:Click("RightButton")   -- (Questie's own quest menu: its line's right click)
		end
		return
	end
	local Act = rawget(MelloUI, "QuestActs")
	if type(Act) == "table" and type(Act.Follow) == "function" then
		Act.Follow(id)
	end
end, "script")

local MarkEnter = Perf.Shared("OnEnter on a Questie quest line's MelloUI mark", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	if not (self.questID and pcall(GameTooltip.SetHyperlink, GameTooltip, "quest:" .. self.questID)) then
		GameTooltip:SetText(" ")
	end
	local c = MelloUI.Look.TipPalette().text   -- (a hint: small text is never mutedText)
	local W = MelloUI.Widgets
	GameTooltip:AddLine(W and W.Tr and W.Tr(QL.MARK_HINT) or QL.MARK_HINT, c[1], c[2], c[3], true)
	GameTooltip:Show()
end, "script")

-- Questie's focus picture back (no mark of ours over it)
local function Uncover(focus)
	if not covered[focus] then
		return
	end
	covered[focus] = nil
	local nt, hl = focus:GetNormalTexture(), focus:GetHighlightTexture()
	if nt then
		nt:SetAlpha(1)
	end
	if hl then
		hl:SetAlpha(1)
	end
end

local function Unroute(line)
	local m = routeMarks[line]
	if m then
		m:Hide()
	end
	local focus = rawget(line, "questFocus")
	if focus then
		Uncover(focus)
	end
end

-- Questie's quest items on a line (before 12.6 they take its left edge): how many, the first one's width
local function ItemsOn(line)
	local n, w = 0, nil
	for i = 1, 50 do
		local btn = rawget(_G, "Questie_ItemButton" .. i)
		if not btn then
			break
		end
		if btn:IsShown() and btn:GetParent() == line then
			n = n + 1
			w = w or Number(btn:GetWidth())
		end
	end
	return n, w
end

-- the mark laid again on a quest's title line (its follow and done state as they are now)
local function RouteMark(line)
	local focus = rawget(line, "questFocus")
	local quest = rawget(line, "Quest")
	local id = type(quest) == "table" and Number(rawget(quest, "Id")) or nil
	local tracker, Act = Tracker(), rawget(MelloUI, "QuestActs")
	local Q = rawget(_G, "Questie")
	local profile = type(Q) == "table" and type(Q.db) == "table" and Q.db.profile
	if not (id and type(profile) == "table" and rawget(line, "mode") == "quest" and line:IsShown() and tracker
		and type(tracker.MarkIcon) == "function" and type(Act) == "table" and type(Act.Followed) == "function") then
		Unroute(line)
		return
	end
	-- (its place: Questie's focus slot from 12.6 on; before, the line's left edge or past its quest item)
	local items, itemW = 0, nil
	if focus then
		if profile.trackerShowQuestFocusButtons == false then
			Unroute(line)
			return
		end
	else
		items, itemW = ItemsOn(line)
		if items > 1 then
			Unroute(line)
			return
		end
	end
	local m = routeMarks[line]
	if not m then
		m = CreateFrame("Button", nil, line)
		m:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		m.icon = m:CreateTexture(nil, "ARTWORK")
		m.icon:SetAllPoints(m)
		m.lit = m:CreateTexture(nil, "HIGHLIGHT")
		m.lit:SetAllPoints(m)
		m.lit:SetBlendMode("ADD")
		Perf.SetScript(m, "OnClick", MarkClick)
		Perf.SetScript(m, "OnEnter", MarkEnter)
		Perf.SetScript(m, "OnLeave", MelloUI.Widgets.TipLeave)
		routeMarks[line] = m
	end
	m.questID = id
	-- (its size Questie's buttons': its quest font's size + 3; over its focus button, a level up)
	local size = (Number(profile.trackerFontSizeQuest) or 10) + 3
	m:ClearAllPoints()
	if focus then
		m:SetSize(size, size)
		m:SetPoint("TOPRIGHT", focus, "TOPRIGHT", 0, 0)
		m:SetFrameLevel(focus:GetFrameLevel() + 1)
	else
		size = math.min(size, QL.MARK_MAX)
		m:SetSize(size, size)
		m:SetPoint("TOPLEFT", line, "TOPLEFT", items == 1 and (itemW or 0) + 3 or 0, 1)
		m:SetFrameLevel(line:GetFrameLevel() + 2)
	end
	local okC, done = pcall(C_QuestLog.IsComplete, id)
	local path = tracker.MarkIcon(okC and MelloUI.Safe.Value(done) == true, Act.Followed() == id)
	if m.path ~= path then
		m.path = path
		MelloUI.Icons.Set(m.icon, path)
		MelloUI.Icons.Set(m.lit, path)
	end
	m:Show()
	if not focus then
		return
	end
	covered[focus] = true
	local nt, hl = focus:GetNormalTexture(), focus:GetHighlightTexture()
	if nt then
		nt:SetAlpha(0)
	end
	if hl then
		hl:SetAlpha(0)
	end
end

-- the game's followed quest changed (a click here, on MelloUI's tracker, Route's own): the marks laid again
function QL.RefreshMarks()
	for line, m in pairs(routeMarks) do
		if m:IsShown() then
			RouteMark(line)
		end
	end
end

--------------------------------------------------------------------------------
-- Dressing
--------------------------------------------------------------------------------

-- the title row: our heading, the icon, the hairline under it (over it with the title at the foot)
local function DressHeader(base, panel)
	local header = rawget(_G, "Questie_HeaderFrame")
	local tracked = header and rawget(header, "trackedQuests")
	local label = tracked and rawget(tracked, "label")
	local icon = header and rawget(header, "questieIcon")
	if icon then
		Mark(icon)
	end
	local hair = panel.hair
	if not (label and header:IsShown()) then
		hair:Hide()
		return
	end
	local right, left = Number(base:GetRight()), Number(label:GetLeft())
	-- (the panel's right edge: Questie's frame's, less what the panel stands in from the screen's edge -- Seat)
	Head(label, panel, right and left and math.max(1, right - (panel.inR or 0) - QL.EDGE - left) or nil)
	local top, bottom = Number(base:GetTop()), Number(base:GetBottom())
	local hTop, hBottom = Number(header:GetTop()), Number(header:GetBottom())
	if not (top and bottom and hTop and hBottom) then
		hair:Hide()
		return
	end
	local atFoot = (hTop + hBottom) / 2 < (top + bottom) / 2
	-- (2.1.52; the game, 2026-11-14, the user: "Yes, move it") under the title the hairline stands inside Questie's
	-- header, in the air under its text (the header is its font's size + 5 high): Questie's first line starts at the
	-- header's bottom with its text at the line's top, and 2 under the header the hairline ran through the top of the
	-- first zone's name. At the foot as before, 2 over the header: the line above ends in its own padding
	local y = (atFoot and (hTop + 2 - top) or (hBottom + 2 - top)) + (panel.inT or 0)   -- (from the panel's top: Seat)
	hair:ClearAllPoints()
	hair:SetPoint("TOPLEFT", panel, "TOPLEFT", QL.EDGE, y)
	hair:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -QL.EDGE, y)
	hair:SetShown(not panel.game)   -- (the Default skin: the game's header bar instead, GameLook)
	-- (the user's game: "its still misplaced ingame") the Default skin's header bar across the panel, on the title
	-- row's middle -- Questie's header frame is not the panel's width, and centred on it the bar hung out to one side
	local art = panel.headArt
	if art then
		art:ClearAllPoints()
		art:SetPoint("CENTER", panel, "TOP", 0, (hTop + hBottom) / 2 - top)
		art:SetWidth(Number(base:GetWidth()) or 300)
	end
end

local function DressLine(line)
	local label = rawget(line, "label")
	if not label then
		return
	end
	Own(line)
	local mode = rawget(line, "mode")
	local zone = mode == "zone"
	if zone and line:IsShown() then
		local layer = Layer(line)
		-- (out to the panel's right edge, as the tracker's headings: Questie's label is as wide as its text)
		local base = rawget(_G, "Questie_BaseFrame")
		local right, left = Number(base and base:GetRight()), Number(label:GetLeft())
		local inR = S.panel and S.panel.inR or 0   -- (the panel in from the screen's edge: Seat)
		local width = right and left and math.max(1, right - inR - QL.EDGE - left) or (Number(label:GetWidth()) or 100)
		-- (its name up to the +/- at the right end)
		Head(label, layer, math.max(1, width - (Number(select(2, label:GetFont())) or 12) - 4))
		Rule(line, layer, label, width)
		local ez = rawget(line, "expandZone")
		local g = Glyph(line, layer, ez and rawget(ez, "mode") == 0 and "plus" or "minus")
		if g then
			local s = Number(select(2, label:GetFont())) or 12
			g:SetSize(s, s)
			g:ClearAllPoints()
			g:SetPoint("RIGHT", label, "LEFT", width, 0)
		end
	else
		Unhead(label)
		Unglyph(line)
		if layers[line] then
			layers[line]:Hide()
		end
		if sections[line] then
			sections[line]:Hide()
		end
	end
	local eq = rawget(line, "expandQuest")
	if eq and eq:IsShown() then
		local g = Glyph(eq, eq, rawget(eq, "mode") == 0 and "plus" or "minus")
		if g then
			g:SetAllPoints(eq)
		end
		local own = rawget(eq, "texture")
		if own and own.SetAlpha then
			own:SetAlpha(0)
		end
	end
	RouteMark(line)   -- (Questie 12.6 on: the focus slot)
end

local function Undress()
	if S.panel then
		S.panel:Hide()
	end
	for over in pairs(heads) do
		Unhead(over)
	end
	for key in pairs(glyphs) do
		Unglyph(key)
		local own = type(key) == "table" and rawget(key, "texture")
		if own and own.SetAlpha then
			own:SetAlpha(1)
		end
	end
	for _, layer in pairs(layers) do
		layer:Hide()
	end
	for _, tray in pairs(trays) do
		if tray then
			tray:Hide()
		end
	end
	for icon in pairs(marks) do
		Unmark(icon)
	end
	for line in pairs(routeMarks) do
		Unroute(line)
	end
end

-- Questie's lines as many as its pool used (its accessors; the line globals named by index as a fallback)
local function Lines(fn)
	local pool = Questie("TrackerLinePool")
	local n = pool and type(pool.GetHighestIndex) == "function" and Number(pool.GetHighestIndex()) or 0
	for i = 1, n do
		local line = pool.GetLine and pool.GetLine(i) or rawget(_G, "linePool" .. i)
		if type(line) == "table" then
			fn(line)
		end
	end
end

-- (2.1.52, Core/QuestMoments.lua: an item picked up flies to its line) Questie's tracker line of a quest's objective,
-- shown: its text (or the line), else nil. Read only: the line's own fields as Questie sets them (TrackerLinePool:
-- mode "objective", Quest.Id, Objective.Index)
local lineFound, lineQuest, lineIndex
local function LineOf(line)
	if lineFound or rawget(line, "mode") ~= "objective" then
		return
	end
	local quest, objective = rawget(line, "Quest"), rawget(line, "Objective")
	if type(quest) == "table" and type(objective) == "table" and rawget(quest, "Id") == lineQuest
		and rawget(objective, "Index") == lineIndex and line:IsVisible() then
		lineFound = rawget(line, "label") or line
	end
end
function QL.ObjectiveLine(questID, index)
	lineFound, lineQuest, lineIndex = nil, questID, index
	Lines(LineOf)
	local found = lineFound
	lineFound = nil
	return found
end

-- (2.1.55, Modules/QuestTrackerPad.lua: the pad's stops on the tracker) Questie's shown quests, top to bottom:
-- { line (its name's line), bottom (its lowest shown line: the last objective), questID, item (its item button, shown) }.
-- Read only: the lines' own fields as Questie sets them (mode "quest" / "objective", Quest.Id)
function QL.TrackerQuests()
	local out, at = {}, nil
	Lines(function(line)
		if not line:IsVisible() then
			return
		end
		local mode, quest = rawget(line, "mode"), rawget(line, "Quest")
		local id = type(quest) == "table" and rawget(quest, "Id") or nil
		if mode == "quest" and id then
			at = { line = line, bottom = line, questID = id }
			out[#out + 1] = at
		elseif mode == "objective" and at and id == at.questID then
			at.bottom = line
		else
			at = nil
		end
	end)
	for i = 1, 50 do
		local btn = rawget(_G, "Questie_ItemButton" .. i)
		if not btn then
			break
		end
		if btn:IsShown() then
			local parent = btn:GetParent()
			for _, q in ipairs(out) do
				if q.line == parent then
					q.item = btn
				end
			end
		end
	end
	return out
end

-- (2.1.39; the user, 2026-11-10: "questie quest tracker does not load inside the dungeon" -- Questie folds its tracker
-- to its heading there, its Minimize In Instances, on by default -- then "Yes, switch it off once") while Questie's
-- tracker stands in MelloUI's place, its quests show in a dungeon as MelloUI's own tracker's did: that setting of
-- Questie's switched off once, as its own option does (the setting, then OnMinimizeInInstancesChanged: a tracker it
-- folded opened again). Remembered in the Quest Tracker's keep (questieInstancesOpen, never in a profile), so a player
-- who switches it on again in Questie keeps it. The second setting of another addon's MelloUI writes, at the user's
-- word, after the nameplates' (Modules/Nameplates.lua's QuestieIconsOff)
function QL.KeepOpenInDungeons()
	local m = Tracker()
	local db = m and m.db
	if type(db) ~= "table" or db.questieInstancesOpen then
		return false
	end
	local Q = rawget(_G, "Questie")
	local qdb = type(Q) == "table" and rawget(Q, "db")
	local profile = type(qdb) == "table" and qdb.profile
	if type(profile) ~= "table" then
		return false
	end
	db.questieInstancesOpen = true
	if profile.minimizeTrackerInInstances ~= false then
		profile.minimizeTrackerInInstances = false
		local QT = Questie("QuestieTracker")
		local changed = QT and rawget(QT, "OnMinimizeInInstancesChanged")
		if type(changed) == "function" then
			pcall(changed, false)
		end
	end
	return true
end

-- (2.1.39) the ink on Questie's lines told again when the dressing starts or ends (the parchment's own switch tells it
-- by itself: QuestInk's 'parchment' on the bus)
local function Inked()
	local QI = rawget(MelloUI, "QuestInk")
	if type(QI) == "table" and type(QI.RefreshSurface) == "function" then
		QI.RefreshSurface("questTracker")
	end
end

function QL.Dress()
	-- (the user, 2026-11-10: "Do not even consider having both Questie Tracker and our own tracker active at the same
	-- time") Questie's tracker switched on or off (its Toggle: then its Update): MelloUI's steps aside or back at once
	-- (asked first: its frame is made only once its tracker runs)
	local OV = rawget(MelloUI, "Overlaps")
	local aside = (type(OV) == "table" and type(OV.By) == "function" and OV.By("questTracker") == "Questie") and true or false
	if aside ~= S.aside then
		S.aside = aside
		MelloUI:Fire("overlap", "questTracker")
	end
	local base = rawget(_G, "Questie_BaseFrame")
	-- (the user, 2026-11-10: "Guide step on Questie's") a leveling guide's steps stay on MelloUI's tracker, docked on
	-- Questie's (Modules/QuestTracker.lua's Dock): told when Questie's shows, hides or changes its size (a script hook
	-- on its frame, once; in a fight too: Questie hides its tracker in one when it is set to)
	if base and not S.watched then
		S.watched = true
		local function Tell()
			MelloUI:Fire("overlap", "questTracker")
		end
		Perf.HookScript(base, "OnShow", Tell)
		Perf.HookScript(base, "OnHide", Tell)
		Perf.HookScript(base, "OnSizeChanged", Tell)
	end
	-- (Questie's Update lays nothing in a fight: nor does this)
	if not base or InCombatLockdown() then
		return
	end
	local on = On()
	if not on then
		if S.on then
			S.on = false
			Undress()
			Unfollow(base)   -- (2.1.52: its own default place again)
			Give()   -- (2.1.53: its own sizes, text and sort again)
			Inked()
			-- (its own fonts back: Questie sets them at its next Update)
			local QT = Questie("QuestieTracker")
			if QT and type(QT.Update) == "function" and not InCombatLockdown() then
				pcall(QT.Update, QT)
			end
		end
		return
	end
	if not S.on then
		S.on = true
		Inked()
	end
	QL.KeepOpenInDungeons()
	local panel = Panel(base)
	if not panel then
		return
	end
	panel:Show()
	HangUnder(base)   -- (2.1.52: under MelloUI's minimap column where nobody placed it; then its rim, at that place)
	Seat(base, panel)
	Opacity(panel)
	-- (2.1.53) the Quest Tracker's sizes, text and sort written into Questie's: laid by its next Update (S.redo)
	if Apply(base) then
		S.redo = true
	end
	DressHeader(base, panel)
	Lines(DressLine)
	for i = 1, 25 do
		local btn = rawget(_G, "Questie_ItemButton" .. i)
		if not btn then
			break
		end
		if btn:IsShown() then
			Tray(btn)
		end
	end
	-- lines hooked just now: Questie measures them in the face at its next Update
	if S.redo then
		S.redo = false
		C_Timer.After(QL.REDO, function()
			local QT = Questie("QuestieTracker")
			if S.on and QT and type(QT.Update) == "function" and not InCombatLockdown() then
				pcall(QT.Update, QT)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Questie's icons in MelloUI's pictures (the user, 2026-11-10: "if Questie is Drawing Icons on the Map and Minimap,
-- replace its icons with ours"; 2.1.4 for MelloUI's map: "Those polestar and questie icons need to be replaced by our
-- own, we have the library for it, and match the themes"). An icon of Questie's is known by its kind (QL.Look: its
-- data.Icon type, 2.1.43), else its picture's file name (Questie.icons); `cover` says what MelloUI's map shows of the
-- quest already (MapAddonPins: nothing twice)
--------------------------------------------------------------------------------

local GIVER_ATLAS, ENDER_ATLAS = "QuestNormal", "QuestTurnin"
QL.ICONS = {
	available = { atlas = GIVER_ATLAS, cover = "giver" },
	available_gray = { atlas = GIVER_ATLAS, grey = true, cover = "giver" },
	repeatable = { atlas = GIVER_ATLAS, cover = "giver" },
	eventquest = { atlas = GIVER_ATLAS, cover = "giver" },
	pvpquest = { atlas = GIVER_ATLAS, cover = "giver" },
	complete = { atlas = ENDER_ATLAS, cover = "ender" },
	incomplete = { atlas = ENDER_ATLAS, grey = true, cover = "ender" },
	repeatable_complete = { atlas = ENDER_ATLAS, cover = "ender" },
	eventquest_complete = { atlas = ENDER_ATLAS, cover = "ender" },
	pvpquest_complete = { atlas = ENDER_ATLAS, cover = "ender" },
	slay = { icon = "kill", cover = "objective" },
	slay_mono = { icon = "kill", cover = "objective" },
	loot = { icon = "pin_collect", cover = "objective" },
	loot_mono = { icon = "pin_collect", cover = "objective" },
	object = { icon = "obj_use", cover = "objective" },
	object_mono = { icon = "obj_use", cover = "objective" },
	interact = { icon = "obj_use", cover = "objective" },
	talk = { icon = "chat_general", cover = "objective" },
	chatbubblegossipicon = { icon = "chat_general", cover = "objective" },
	event = { icon = "obj_explore", cover = "objective" },
	chest = { icon = "ql_chest" },
}
QL.ICON_DIR = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\"
QL.GREY_ALPHA = 0.75   -- (a greyed mark's: MapAddonPins')

-- (2.1.43, MapAddonPins; 2.1.50 here) Questie's townsfolk (its "manual" icons: the game's tracking pictures): one's
-- picture, nil for an icon that is no townsfolk. (2.1.53) Which kind of place that picture stands for, and whether
-- an owner before Questie has that kind, is the map's town marks' to say (MelloUI_Map/MapTownMarks.lua: one owner a
-- kind across every addon) -- the flight masters, MelloUI's own, among them as before
function QL.TownPicture(icon)
	local data = rawget(icon, "data")
	if type(data) ~= "table" or data.Type ~= "manual" then
		return nil
	end
	return MelloUI.Safe.Text(data.Icon)
end

-- a picture's look by its file's name, nil for one of no look of ours
function QL.IconLook(path)
	path = MelloUI.Safe.Text(path)
	local name = type(path) == "string" and path:match("([^\\/]+)%.%w+$")
	return name and QL.ICONS[name:lower()] or nil
end

-- (2.1.43; the user, 2026-11-11, a screenshot of MelloUI's map: Questie's swords and sacks over MelloUI's quest areas,
-- "the Questie icons are just too much") an icon's look by its kind as Questie keeps it: data.Icon, the number of its
-- Questie.ICON_TYPE_* (SLAY 1, LOOT 2 ...: Questie.lua), set before its picture and whatever picture the player picked
-- for that kind in Questie's options; else by its picture's file name (data.Icon a path, then the picture's own)
local typeNames   -- [Questie's ICON_TYPE number] = its name, lower case ("slay", "available" ...)
local function TypeNames()
	if typeNames then
		return typeNames
	end
	local Q = rawget(_G, "Questie")
	if type(Q) ~= "table" then
		return nil
	end
	local names, n = {}, 0
	for k, v in pairs(Q) do
		local name = type(k) == "string" and k:match("^ICON_TYPE_(.+)$")
		if name and Number(v) then
			names[v] = name:lower()
			n = n + 1
		end
	end
	if n > 0 then
		typeNames = names
	end
	return names
end
QL.TypeNames = TypeNames

function QL.Look(icon, path)
	local data = rawget(icon, "data")
	if type(data) == "table" then
		local kind = Number(data.Icon)
		local names = kind and TypeNames()
		local look = names and names[kind] and QL.ICONS[names[kind]]
		if look then
			return look
		end
		look = QL.IconLook(data.Icon)
		if look then
			return look
		end
	end
	return QL.IconLook(path)
end

local swapped = setmetatable({}, { __mode = "k" })   -- [Questie's icon picture] = its overlay, while ours is on it

-- Questie's own picture back (its next SetTexture sets its file; the place in the file and the colour ours had: reset)
local function Unswap(tex)
	local overlay = swapped[tex]
	if overlay == nil then
		return
	end
	swapped[tex] = nil
	MelloUI.Icons.Release(tex)
	tex:SetTexCoord(0, 1, 0, 1)
	tex:SetDesaturated(false)
	tex:SetAlpha(1)
	if overlay then
		overlay:SetAlpha(1)
	end
end

-- MelloUI's map on: its world-map icons are laid there in these pictures already (MapAddonPins)
local function MapOurs()
	local m = MelloUI.modules and MelloUI.modules.Map
	return type(m) == "table" and m.isEnabled and true or false
end

-- (2.1.39; the user, 2026-11-10: "we have lost our quest areas, our icons on the minimap and map because questie
-- replaced them, didnt i say that we provide the look? this way we have lost our own function which i like very much")
-- MelloUI draws this kind of quest mark here itself now -- the Quest List's objective marks on the minimap (its
-- MiniWanted), its givers and objective marks on the game's map (mapPins, objectiveMarks; MelloUI's own map: its
-- MapAddonPins lends it only what its layers leave out) -- so Questie's of that kind stay out of sight there, its
-- mouse off (no tooltip from an icon not seen). The minimap's givers, enders and townsfolk: QL.MiniOwn (2.1.51)
local function Drawn(look, mini)
	local Q = rawget(MelloUI, "QuestList")
	local M = type(Q) == "table" and rawget(Q, "M")
	if not (look.cover and type(M) == "table" and M.isEnabled and type(M.db) == "table") then
		return false
	end
	if mini then
		local O = rawget(Q, "Objectives")
		return look.cover == "objective" and type(O) == "table" and type(O.MiniWanted) == "function"
			and O.MiniWanted() and true or false
	end
	if MapOurs() then
		return false
	end
	if look.cover == "objective" then
		return M.db.objectiveMarks and true or false
	end
	-- (2.1.51) Questie's givers are the givers: the Quest List's Quest Givers On Zone Maps shows or hides them.
	-- (2.1.52: whatever QL.Givers answers -- MelloUI draws no givers of its own any more, so a Questie whose database
	-- MelloUI cannot read keeps its givers too; they were hidden here behind marks MelloUI no longer draws)
	return not M.db.mapPins
end

local iconPaths = setmetatable({}, { __mode = "k" })   -- [Questie's icon] = the picture Questie gave it
local hidden = setmetatable({}, { __mode = "k" })      -- [Questie's icon] = true while MelloUI draws its kind there
local unlisted = setmetatable({}, { __mode = "k" })    -- [Questie's icon] = true while MelloUI's map leaves it out
local ownAlpha = setmetatable({}, { __mode = "k" })    -- [Questie's icon] = its frame's own alpha while out of sight

-- (2.1.51; the user, 2026-11-13, a minimap in Hillsbrad full of Questie's swords beside MelloUI's own marks: "why are we
-- going back and fourth on the Quest Icons on the minimap"; /qlmap questie: every one "out of sight", its picture and
-- glow at 1 or at Questie's fade, 0.71) out of sight by the icon frame's own alpha, never its pictures': on this client
-- a picture's alpha and its vertex colour's are one value, and Questie fades its minimap icons by distance with
-- SetVertexColor (its SetFade, on each change as you move), which wrote MelloUI's 0 back to its fade. The frame's alpha
-- Questie writes only in UpdateTexture and when it lets the frame go (FramePool's UnloadFrame), and MelloUI's hooks on
-- both run right after; its own value (1, or 0.5 for a party member's objective) is kept and given back
local function Unhide(icon)
	if hidden[icon] then
		hidden[icon] = nil
		icon:SetAlpha(ownAlpha[icon] or 1)
		ownAlpha[icon] = nil
		icon:EnableMouse(true)
	end
end

local function Hide(icon, tex)
	Unswap(tex)
	hidden[icon] = true
	local okA, a = pcall(icon.GetAlpha, icon)
	a = okA and Number(a)
	if a and a > 0 then   -- (Questie's own, written since: kept; our 0 never taken for it)
		ownAlpha[icon] = a
	end
	icon:SetAlpha(0)
	icon:EnableMouse(false)
end

-- (2.1.51; the user, 2026-11-13, at Camp Taurajo: "there are double quest icons on the minimap when i use Questie, fix
-- that", then at the Crossroads, two pictures: "Picture1 without questie, picture 2 with questie") the minimap as it is
-- without Questie: this client's minimap marks an NPC's quests itself (the game's ! and ?, the very pictures MelloUI
-- laid on Questie's), its tracking menu the townsfolk, MelloUI's map its flight masters (MapLayers' MiniFlights) -- so
-- every quest giver and ender of Questie's (an NPC's, an object's, an item's, a grey one) and its townsfolk (its
-- "manual" icons: mailboxes, inns, flight masters ...) out of sight there. Its objectives follow MelloUI's own marks
-- (Drawn). On the maps: unchanged
function QL.MiniOwn(icon, look)
	if look and (look.cover == "giver" or look.cover == "ender") then
		return true
	end
	local data = rawget(icon, "data")
	return type(data) == "table" and data.Type == "manual"
end

-- (2.1.51) told when Questie sets the picture of an icon MelloUI's own map dresses (MapAddonPins: its own pictures kept
-- hidden under MelloUI's; Questie's UpdateTexture shows its glow again)
local mapPictures = {}
function QL.OnMapPicture(fn)
	mapPictures[#mapPictures + 1] = fn
end

-- an icon of Questie's laid again: out of sight where MelloUI draws its kind, else MelloUI's picture on it
local function Restyle(icon)
	local tex = rawget(icon, "texture")
	if not tex then
		return
	end
	local look = Used() and QL.Look(icon, iconPaths[icon]) or nil
	local mini = rawget(icon, "miniMapIcon") and true or false
	if look and Drawn(look, mini) then
		Hide(icon, tex)
		return
	end
	-- (2.1.51) its quest marks and townsfolk on the minimap: the game's own and MelloUI's there
	if mini and Used() and QL.MiniOwn(icon, look) then
		Hide(icon, tex)
		return
	end
	Unhide(icon)
	if not look or (not mini and MapOurs()) then
		Unswap(tex)
		if not mini and MapOurs() then
			for _, fn in ipairs(mapPictures) do
				fn(icon)
			end
		end
		return
	end
	if look.atlas then
		MelloUI.Icons.Release(tex)
		tex:SetTexCoord(0, 1, 0, 1)
		tex:SetAtlas(look.atlas)
	else
		MelloUI.Icons.Set(tex, QL.ICON_DIR .. look.icon)
	end
	tex:SetDesaturated(look.grey == true)
	tex:SetAlpha(look.grey and QL.GREY_ALPHA or 1)
	-- (its loot / object overlay: Questie's own picture's part)
	local overlay = rawget(icon, "overlayTexture")
	if overlay and overlay.SetAlpha then
		overlay:SetAlpha(0)
	end
	swapped[tex] = overlay or false
end

-- Questie set an icon's picture (its UpdateTexture: after its SetTexture, its colour and fade on the picture)
local function OnIconTexture(icon, path)
	iconPaths[icon] = path
	Restyle(icon)
end

-- (2.1.50) the others that dress Questie's icons (MelloUI's map: MapAddonPins) told when Questie lets one go, so their
-- dressing goes with it and never follows the pooled frame into its next use (the minimap's)
local releases = {}
function QL.OnRelease(fn)
	releases[#releases + 1] = fn
end
function QL.Released(icon)
	for _, fn in ipairs(releases) do
		fn(icon)
	end
end

local function OnIconUnload(icon)
	iconPaths[icon] = nil
	unlisted[icon] = nil
	Unhide(icon)
	local tex = rawget(icon, "texture")
	if tex then
		Unswap(tex)
	end
	QL.Released(icon)
end

-- (2.1.50; the user, 2026-11-13, a screenshot: "im still seeing Questie Icons on the minimap", Questie's loot sacks
-- beside MelloUI's own marks) an icon laid by these rules whatever way it came: every icon Questie places on the
-- minimap is laid there and then (a post-hook on its pins library's own table, QL.PINS: never a yielding function),
-- not only when Questie sets its picture; a frame whose UpdateTexture is not the hooked one (made before the hook, or
-- given another since) gets the hook on its own copy, once; a picture never seen through the hook read off the frame
local adopted = setmetatable({}, { __mode = "k" })   -- [Questie's icon] = true: the hooks on its own functions
local hookedFn, hookedUnload   -- QuestieFrame.private's UpdateTexture and Unload with MelloUI's hooks (a new frame's)
QL.PINS = "HereBeDragonsQuestie-Pins-2.0"
QL.HBD = "HereBeDragonsQuestie-2.0"
-- (2.1.52; the user, 2026-11-14, on Questie 12.9: "now i dont see a single quest giver on the map") Questie's own copy
-- of HereBeDragons, its pins and its coordinates: a LibStub library under those names until Questie 12.9, a module of
-- Questie's loader since ("HBDPins", "HBD": "a Questie module instead of a LibStub library"). The one lookup, for this
-- file and for MelloUI's map (MapAddonPins' FindLibs); nil while Questie has made neither. The loader is asked only
-- when the library is not there: it makes a module that is asked for
function QL.PinsLib()
	local LS = rawget(_G, "LibStub")
	if type(LS) == "table" or type(LS) == "function" then
		local okP, pins = pcall(LS, QL.PINS, true)
		if okP and type(pins) == "table" then
			local okH, hbd = pcall(LS, QL.HBD, true)
			return pins, okH and type(hbd) == "table" and hbd or nil
		end
	end
	local pins = Questie("HBDPins")
	if pins and type(rawget(pins, "worldmapPins")) == "table" then
		return pins, Questie("HBD")
	end
	return nil
end
-- (the hooks on an adopted frame's own functions: one handler each for every frame, one row in /melloperf)
local FrameTexture = Perf.Shared("UpdateTexture on Questie's adopted icons", OnIconTexture)
local FrameUnload = Perf.Shared("Unload on Questie's adopted icons", OnIconUnload)

local function Adopt(icon)
	local tex = type(icon) == "table" and rawget(icon, "texture")
	if not tex then
		return
	end
	local fn, un = rawget(icon, "UpdateTexture"), rawget(icon, "Unload")
	if type(fn) == "function" and fn ~= hookedFn and not adopted[icon] then
		adopted[icon] = true
		hooksecurefunc(icon, "UpdateTexture", FrameTexture)
		if type(un) == "function" and un ~= hookedUnload then
			hooksecurefunc(icon, "Unload", FrameUnload)
		end
	end
	if iconPaths[icon] == nil then
		local ok, p = pcall(tex.GetTexture, tex)
		iconPaths[icon] = ok and MelloUI.Safe.Text(p) or false
	end
	Restyle(icon)
end
QL.Adopt = Adopt

-- (Questie's pins library placed an icon on the minimap: its own)
local function OnMinimapPin(_, ref, icon)
	if ref ~= nil and ref == rawget(_G, "Questie") then
		Adopt(icon)
	end
end

-- (2.1.50) /qlmap questie (QL.Dump; a mode of the Quest List's dump, MelloUI_QuestList/QuestList.lua): Questie's icons
-- as MelloUI lays them, in the copy window: what decides (Use with MelloUI, MelloUI's minimap marks, MelloUI's map, the
-- hooks), every icon by place, kind and what shows (out of sight, MelloUI's picture, Questie's own), and a few minimap
-- icons that still show Questie's own picture
-- (2.1.51) an icon frame at alpha 0: out of sight whatever its pictures say (MelloUI hides the frame, Hide above)
local function FrameOut(frame)
	local ok, a = pcall(frame.GetEffectiveAlpha, frame)
	return ok and a == 0
end

local function DumpState(tex, icon)
	local okT, path = pcall(tex.GetTexture, tex)
	path = okT and MelloUI.Safe.Text(path) or ""
	local okA, a = pcall(tex.GetAlpha, tex)
	if (okA and a == 0) or (icon and FrameOut(icon)) then
		return "out of sight", a
	end
	if swapped[tex] ~= nil then
		return "MelloUI's picture", a
	end
	return path:find("Questie") and "Questie's own" or "other", a
end

-- the file a region draws, as the client gives it (a path, or a file's number), "?" if it gives none or a secret
local function DumpFile(region)
	local ok, file = pcall(region.GetTextureFilePath or region.GetTexture, region)
	file = ok and (MelloUI.Safe.Text(file) or Number(file)) or nil
	return tostring(file or "?")
end

-- the first picture of a frame still in sight (shown, not out of sight): its file
local function SeenIn(...)
	for i = 1, select("#", ...) do
		local region = select(i, ...)
		local okV, vis = pcall(region.IsVisible, region)
		local okA, a = pcall(region.GetAlpha, region)
		if region.GetTexture and okV and vis == true and okA and Number(a) and a > 0 then
			return DumpFile(region)
		end
	end
end
local function SeenPicture(frame)
	if FrameOut(frame) then
		return nil
	end
	return SeenIn(frame:GetRegions())
end

-- (2.1.50; the user, 2026-11-13: a cog on the minimap while the icons above were all out of sight) every other
-- icon-sized picture still in sight on the minimap, whoever drew it: a Questie icon frame with no quest's data, another
-- addon's pin, a button (its name in the frame tree, its size, the file it draws). Left out: Questie's icons counted
-- above, RareScanner's pins (their POI: MelloUI's look, Core/RareScannerLook.lua), MelloUI's own frames
-- (one child: in sight and counted, a line for the first ten)
local function DumpChild(n, child)
	local name = MelloUI.Safe.Text(child:GetName())
	local questie = rawget(child, "texture") and rawget(child, "glowTexture") and true or false
	local counted = questie and type(rawget(child, "data")) == "table"
	local w = MelloUI.Safe.Finite(child:GetWidth())
	local okV, vis = pcall(child.IsVisible, child)
	if not (okV and vis == true and not counted and rawget(child, "POI") == nil and w and w > 0 and w <= 40
		and not (name and name:find("^MelloUI"))) then
		return n
	end
	local file = SeenPicture(child)
	if not file then
		return n
	end
	n = n + 1
	if n <= 10 then
		local okD, debug = pcall(child.GetDebugName, child)
		MelloUI:Print("  also on the minimap: %s, %d px, draws %s%s", tostring(okD and debug or name),
			math.floor(w + 0.5), file, questie and " (a Questie icon without a quest)" or "")
	end
	return n
end
local function DumpChildren(...)
	local n = 0
	for i = 1, select("#", ...) do
		n = DumpChild(n, (select(i, ...)))
	end
	MelloUI:Print("  other pictures in sight on the minimap: %d", n)
end
-- (2.1.51; the user, 2026-11-13, at the Tidus Stair: "Questie is still showing its Quest Icon on the Minimap aswell as
-- we show our own", while every Questie icon above was out of sight) every picture in sight near you on the minimap,
-- whoever drew it, MelloUI's own too (Route's layer: the Quest List's marks, the goal): within NEAR screen px of the
-- minimap's middle, your place. A mark you see there that the list leaves out is the game's own (its blips are no
-- frames). A dump only: its tables made on the command
local NEAR, NEAR_MAX = 30, 20
local NearIn
local function NearRegions(frame, scale, cx, cy, found, ...)
	for i = 1, select("#", ...) do
		local region = select(i, ...)
		local okV, vis = pcall(region.IsVisible, region)
		local okA, a = pcall(region.GetAlpha, region)
		local okC, x, y = pcall(region.GetCenter, region)
		local okW, w = pcall(region.GetWidth, region)
		x, y, w = okC and MelloUI.Safe.Finite(x), okC and MelloUI.Safe.Finite(y), okW and MelloUI.Safe.Finite(w)
		if region.GetTexture and okV and vis == true and okA and Number(a) and a > 0 and x and y and w and w * scale <= 60 then
			local d = math.sqrt((x * scale - cx) ^ 2 + (y * scale - cy) ^ 2)
			if d <= NEAR then
				local okAt, atlas = pcall(region.GetAtlas or function() end, region)
				atlas = okAt and MelloUI.Safe.Text(atlas) or nil
				local okD, debug = pcall(frame.GetDebugName, frame)
				found[#found + 1] = { d = d, text = string.format("%s, %s, %d px, %d px from you, alpha %.2f",
					tostring(okD and debug or "?"), atlas and ("atlas " .. atlas) or DumpFile(region), math.floor(w * scale + 0.5),
					math.floor(d + 0.5), a) }
			end
		end
	end
end
local function NearChildren(cx, cy, depth, found, ...)
	for i = 1, select("#", ...) do
		local child = select(i, ...)
		local okV, vis = pcall(child.IsVisible, child)
		if okV and vis == true then
			NearIn(child, cx, cy, depth + 1, found)
		end
	end
end
function NearIn(frame, cx, cy, depth, found)
	if FrameOut(frame) then   -- (a frame at alpha 0, its children too: nothing of it in sight)
		return
	end
	local okS, scale = pcall(frame.GetEffectiveScale, frame)
	scale = okS and MelloUI.Safe.Finite(scale) or 1
	NearRegions(frame, scale, cx, cy, found, frame:GetRegions())
	if depth < 5 then
		NearChildren(cx, cy, depth, found, frame:GetChildren())
	end
end
local function DumpNear(mm)
	local okC, x, y = pcall(mm.GetCenter, mm)
	local okS, scale = pcall(mm.GetEffectiveScale, mm)
	x, y, scale = okC and MelloUI.Safe.Finite(x), okC and MelloUI.Safe.Finite(y), okS and MelloUI.Safe.Finite(scale)
	if not (x and y and scale) then
		MelloUI:Print("  near you on the minimap: its place unreadable")
		return
	end
	local found = {}
	NearIn(mm, x * scale, y * scale, 1, found)
	table.sort(found, function(p, q) return p.d < q.d end)
	MelloUI:Print("== Pictures near you on the minimap (within %d px; a mark not listed is the game's own): %d", NEAR, #found)
	for i = 1, math.min(#found, NEAR_MAX) do
		MelloUI:Print("  %s", found[i].text)
	end
end

local function DumpMinimap()
	local mm = rawget(_G, "Minimap")
	if mm then
		DumpChildren(mm:GetChildren())
		DumpNear(mm)
	end
end

function QL.Dump()
	MelloUI:ClearLog()
	local Q = rawget(MelloUI, "QuestList")
	local O = type(Q) == "table" and rawget(Q, "Objectives")
	local okW, wanted = pcall(function()
		return O and O.MiniWanted()
	end)
	MelloUI:Print("== Questie's icons: Use with MelloUI %s, MelloUI's minimap marks %s, MelloUI's map %s; hooks: picture %s, "
		.. "minimap pins %s", tostring(Used()), tostring(okW and wanted), tostring(MapOurs()), tostring(hookedFn ~= nil),
		tostring(S.pinsHooked == true))
	local counts, order, samples = {}, {}, 0
	local names = TypeNames() or {}
	for i = 1, 100000 do
		local icon = rawget(_G, "QuestieFrame" .. i)
		if not icon then
			break
		end
		local data, tex = rawget(icon, "data"), rawget(icon, "texture")
		if type(data) == "table" and tex then
			local kind = Number(data.Icon)
			kind = kind and names[kind] or tostring(data.Type)
			local state, a = DumpState(tex, icon)
			local mini = rawget(icon, "miniMapIcon") and true or false
			local key = (mini and "minimap " or "map ") .. kind .. ": " .. state
			if not counts[key] then
				counts[key] = 0
				order[#order + 1] = key
			end
			counts[key] = counts[key] + 1
			-- (2.1.50; the user, 2026-11-13: "the cogwheel icon is still questies" -- its glow ring too) every part
			-- of a shown minimap icon still in sight: what MelloUI made of it
			local glow = rawget(icon, "glowTexture")
			local okG, ga = pcall(glow and glow.GetAlpha, glow)
			local glowSeen = okG and ga ~= 0 and glow:IsShown() and not FrameOut(icon)
			-- (and every cog: Questie's object and interact icons, whatever MelloUI made of them)
			local cog = kind == "object" or kind == "object_mono" or kind == "interact"
			-- (2.1.51: and one in no state of MelloUI's -- "other": its picture neither Questie's file nor MelloUI's)
			if mini and (state == "Questie's own" or state == "other" or glowSeen or cog) and samples < 6
				and icon:IsShown() then
				samples = samples + 1
				local parent = icon:GetParent()
				local look = QL.Look(icon, iconPaths[icon])
				MelloUI:Print("  QuestieFrame%d: %s, Icon %s, quest %s, alpha %s, glow %s; seen %s, out of sight %s, own "
					.. "hook %s, its UpdateTexture the hooked one %s, on %s; look %s, cover %s, drawn here %s; in sight: %s",
					i, tostring(data.Type), tostring(data.Icon), tostring(data.Id), tostring(a),
					tostring(glowSeen and ga or "off"), tostring(iconPaths[icon] ~= nil), tostring(hidden[icon] == true),
					tostring(adopted[icon] == true), tostring(rawget(icon, "UpdateTexture") == hookedFn),
					tostring(parent and parent:GetName()), tostring(look and (look.icon or look.atlas)),
					tostring(look and look.cover), tostring(look and Drawn(look, true)), SeenPicture(icon) or "nothing")
			end
		end
	end
	table.sort(order)
	for _, key in ipairs(order) do
		MelloUI:Print("  %s  x%d", key, counts[key])
	end
	DumpMinimap()
	MelloUI:ShowLog("qlmap questie")
end

-- (2.1.50) another dresser gave an icon's pictures back (MapAddonPins): laid again by these rules, if Questie shows it
function QL.Relay(icon)
	if iconPaths[icon] ~= nil then
		Restyle(icon)
	end
end

-- a switch of MelloUI's moved (the Quest List's marks, its module, Route's, the map's): every icon Questie shows
-- laid again (its frame pool's frames, by their names; (2.1.50) every one with a quest's data or a picture, Adopt)
function QL.RestyleIcons()
	for i = 1, 100000 do
		local icon = rawget(_G, "QuestieFrame" .. i)
		if not icon then
			break
		end
		if iconPaths[icon] or rawget(icon, "data") then
			Adopt(icon)
		end
	end
end
local ICON_SWITCHES = { QuestList = true, Route = true, Map = true }   -- (the modules)
local ICON_KEYS = { mapPins = true, objectiveMarks = true, objectiveMinimap = true }   -- (the Quest List's settings)

--------------------------------------------------------------------------------
-- Questie's "open it" in MelloUI's map (the user, 2026-11-10: "Clicking on the Quest in the Quest Tracker opens it in
-- the Blizzard Default Map and Quest Log, it should open our Custom map if its enabled"). While MelloUI's map is on
-- (the game's map and quest log keys are its own then: MelloUI_Map/Map.lua), Questie's quest log opener
-- (TrackerUtils:ShowQuestLog: a quest line's click, its menu's) opens the quest's page in MelloUI's map's quest log,
-- as MelloUI's own tracker's click does (QuestActs.Open), and its map opener (QuestieCompat.OpenWorldMap: Show on Map,
-- its icons' clicks, its focus button) opens MelloUI's map on that zone (MelloUI.Map:Show). Lua wrappers put in
-- Questie's own module tables once at login: Questie calls both through those tables, and neither ever yields (not
-- hooksecurefunc: no C function in its call). Its own function runs while MelloUI's map is off, in the Gamepad UI
-- (MelloUI's map is not opened from code there), and when MelloUI's map cannot show it.
--------------------------------------------------------------------------------

-- (the user, 2026-11-10, of the tracked recipes: "Yes, dock them too") Questie's tracker lists the tracked recipes
-- itself (12.6 on: its TrackerRecipes and RecipeSection, always, in MelloUI's look here): then MelloUI's tracker docks
-- none of its own on it (Modules/QuestTracker.lua's Dock) -- never twice; an older Questie: MelloUI's docked
function QL.TracksRecipes()
	local R = Questie("TrackerRecipes")
	if not (R and type(R.IsSupported) == "function") then
		return false
	end
	local ok, yes = pcall(R.IsSupported)
	return ok and yes == true
end

-- (2.1.53; the user, 2026-11-15: "when users use them, and there is no active quest currently, the Leveling Addon
-- Guide Tracker also Disappears") Questie's tracker out of sight because it has nothing to list -- its own rule: no
-- quest tracked and its Always Show Tracker off (TrackerUtils.HasQuest) -- not folded away by it in a fight or in a
-- dungeon with quests in it. Then the steps docked on it (Modules/QuestTracker.lua's Dock) stand on their own, in
-- MelloUI's tracker's own place, until Questie's shows again. Read, never written
function QL.Empty()
	local base = rawget(_G, "Questie_BaseFrame")
	if base and base:IsShown() then
		return false
	end
	local TU = Questie("TrackerUtils")
	local has = TU and rawget(TU, "HasQuest")
	if type(has) ~= "function" then
		return false
	end
	local ok, any = pcall(has)
	return ok and not any
end

local function OursOpen()
	return MapOurs() and not MelloUI.Safe.GamepadUI()
end

local function WrapOpeners()
	local TU = Questie("TrackerUtils")
	local own = TU and rawget(TU, "ShowQuestLog")
	if type(own) == "function" then
		TU.ShowQuestLog = function(self, quest, ...)
			local id = type(quest) == "table" and Number(rawget(quest, "Id")) or nil
			local Act = rawget(MelloUI, "QuestActs")
			if id and OursOpen() and type(Act) == "table" and type(Act.Open) == "function" then
				Act.Open(id, "log")
				return
			end
			return own(self, quest, ...)
		end
	end
	local QC = Questie("QuestieCompat")
	local openMap = QC and rawget(QC, "OpenWorldMap")
	if type(openMap) == "function" then
		QC.OpenWorldMap = function(uiMapId, ...)
			local API = rawget(MelloUI, "Map")
			if OursOpen() and type(API) == "table" and type(API.Show) == "function" then
				local ok, shown = pcall(API.Show, API, uiMapId)
				if ok and shown then
					return true   -- (Questie flashes its quest's icons after: on MelloUI's map its borrowed ones)
				end
			end
			return openMap(uiMapId, ...)
		end
	end
end

--------------------------------------------------------------------------------
-- Questie's map icon tooltip without the icons MelloUI keeps out of sight (2.1.39; the user, 2026-11-10: "why is it
-- showing me all the active quests on the tooltip when i mouseover the Quest Icon on the Map", then "Questie's,
-- trimmed"). Questie's tooltip lists the quests of every icon of its own near the one hovered (a dungeon's quests all
-- on its entrance), counting the ones MelloUI hid there because it draws that kind itself (Restyle's hidden; MelloUI's
-- map's covered ones, Unlist). Questie skips an icon it hid itself (its FakeHide's `hidden`): while its tooltip is
-- made, MelloUI's hidden ones carry that mark too, and get back what they had right after. A Lua wrapper put in its
-- module table once at login, as the openers above: MapIconTooltip.ShowOnTooltip (Questie 12.0.4 on; its icons'
-- OnEnter and its paths' hover call it through that table); it never yields.
--------------------------------------------------------------------------------

-- (MelloUI_Map/MapAddonPins.lua) an icon of Questie's MelloUI's map leaves out (on: its kind drawn there already)
function QL.Unlist(icon, on)
	unlisted[icon] = on and true or nil
end

-- (2.1.52; the user, 2026-11-14, of Questie's givers on MelloUI's map: "it only shows the tooltips of the quests from my
-- Current Zone") Questie gathers a world-map icon's tooltip from the icons pinned on the game's own world map (its
-- pins library's worldmapProvider:GetMap():EnumeratePinsByTemplate), which stays on your zone while MelloUI's map is
-- open: a giver of another zone found nothing there and showed no tooltip. While the hovered icon is one MelloUI's map
-- holds (MapAddonPins tells them: QL.MapIcons), the library's provider -- a field of Questie's own library table, never
-- Blizzard's -- is for that call a stand-in whose map lists the icons MelloUI's map holds; put back right after
local mapIcons   -- fn() -> [Questie's icon] = true: the ones MelloUI's map holds now
function QL.MapIcons(fn)
	mapIcons = fn
end

local function WrapTooltip()
	local T = Questie("MapIconTooltip")
	local show = T and rawget(T, "ShowOnTooltip")
	if type(show) ~= "function" then
		return
	end
	local icons, before = {}, {}   -- (the icons marked for one tooltip, and what each had: emptied after it)
	local function Hold(icon, n)
		local was = rawget(icon, "hidden")
		if was ~= true then
			n = n + 1
			icons[n], before[n] = icon, was
			icon.hidden = true
		end
		return n
	end
	-- (2.1.52) the stand-in: one pin record per icon, kept; the set filled for one tooltip, emptied after it
	local pinOf = setmetatable({}, { __mode = "k" })
	local set = {}
	local standMap = { EnumeratePinsByTemplate = function()
		return next, set
	end }
	local standProvider = { GetMap = function()
		return standMap
	end }
	-- (2.1.65; a player on Discord, 2026-11-21: "Holding shift doesnt expand the quest when you are already hovering the
	-- quest ... it only works when you move your cursor of the icon and back on") Questie draws its tooltip again as
	-- Shift goes down or up only over the game's own world map or minimap (its EventHandler's ModifierStateChanged:
	-- MouseIsOver(WorldMapFrame), MouseIsOver(Minimap)), never over MelloUI's map. Over an icon MelloUI's map holds,
	-- MelloUI's key watch (MelloUI:WatchKeys, Core.lua) does what Questie's handler does there: the tooltip shown again
	-- from the lines it gathered (its _Rebuild, which reads Shift). Questie's keys on the tooltip are only read
	local function Redraw(icon, key)
		if key ~= "LSHIFT" and key ~= "RSHIFT" then
			return
		end
		local tip = GameTooltip
		local rebuild = rawget(tip, "_Rebuild")
		if type(rebuild) ~= "function" or rawget(tip, "_owner") ~= icon or not tip:IsShown()
			or tip:GetOwner() ~= icon then
			return
		end
		tip:Hide()
		tip:ClearLines()
		tip:SetOwner(icon, "ANCHOR_CURSOR")
		if pcall(rebuild, tip) then
			tip:SetFrameStrata("TOOLTIP")
			tip:Show()
		end
	end
	-- the icons MelloUI's map holds now, when the hovered one is one of them; else nil
	local function Held(self)
		if not (mapIcons and MapOurs() and type(self) == "table" and not rawget(self, "miniMapIcon")) then
			return nil
		end
		local held = mapIcons()
		return (type(held) == "table" and held[self]) and held or nil
	end
	local function Lend(held)
		if not held then
			return nil
		end
		local lib = QL.PinsLib()
		if not (lib and rawget(lib, "worldmapProvider")) then
			return nil
		end
		for icon in pairs(held) do
			local pin = pinOf[icon]
			if not pin then
				pin = { icon = icon }
				pinOf[icon] = pin
			end
			set[pin] = true
		end
		local real = lib.worldmapProvider
		lib.worldmapProvider = standProvider
		return lib, real
	end
	T.ShowOnTooltip = function(...)
		local n = 0
		for icon in pairs(hidden) do
			n = Hold(icon, n)
		end
		if MapOurs() then
			for icon in pairs(unlisted) do
				n = Hold(icon, n)
			end
		end
		local hovered, tip, owner = ...
		local held = Held(hovered)
		local lib, real = Lend(held)
		local ok, err = pcall(show, ...)
		if lib then
			lib.worldmapProvider = real
			for pin in pairs(set) do
				set[pin] = nil
			end
		end
		for i = n, 1, -1 do
			local icon = icons[i]
			icon.hidden = before[i]
			icons[i], before[i] = nil, nil
		end
		-- (2.1.65) an icon MelloUI's map holds, hovered: Shift down or up drawn at once (Redraw)
		if ok and held and tip == GameTooltip and owner == nil then
			MelloUI:WatchKeys(hovered, Redraw)
		end
		if not ok then
			error(err, 0)
		end
	end
end

--------------------------------------------------------------------------------
-- At login: the hooks, when Questie is loaded
--------------------------------------------------------------------------------

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
Perf.SetScript(login, "OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	if S.hooked then
		return
	end
	-- its icons' own functions (its frame pool's; each icon takes them when it is made, after this); (2.1.50) first,
	-- before the tracker's openers and tooltip
	local QF = Questie("QuestieFrame")
	local private = QF and rawget(QF, "private")
	if type(private) == "table" and type(private.UpdateTexture) == "function" and type(private.Unload) == "function" then
		hooksecurefunc(private, "UpdateTexture", OnIconTexture)
		hooksecurefunc(private, "Unload", OnIconUnload)
		hookedFn, hookedUnload = private.UpdateTexture, private.Unload
		-- (2.1.50) each icon placed on the minimap by its pins library (Adopt)
		local pins = QL.PinsLib()
		if pins and type(pins.AddMinimapIconMap) == "function" then
			hooksecurefunc(pins, "AddMinimapIconMap", OnMinimapPin)
			S.pinsHooked = true
		end
		MelloUI:On("module", function(name)
			if ICON_SWITCHES[name] then
				QL.RestyleIcons()
			end
		end, OnIconTexture)
		MelloUI:On("setting", function(name, key)
			if name == "QuestList" and ICON_KEYS[key] then
				QL.RestyleIcons()
			end
		end, OnIconTexture)
		-- (2.1.50: another addon took the minimap's objective marks over or gave them back, Overlaps)
		MelloUI:On("overlap", function(job)
			if job == "minimapObjectives" then
				QL.RestyleIcons()
			end
		end, OnIconTexture)
	end
	WrapOpeners()
	WrapTooltip()
	local QT = Questie("QuestieTracker")
	if not (QT and type(QT.Update) == "function") then
		return
	end
	S.hooked = true
	hooksecurefunc(QT, "Update", function()
		QL.Dress()
	end)
	-- (2.1.52) the minimap column's foot moved (the map sized, a row of Services more): Questie's tracker under it
	-- again, where it follows the column (HangUnder)
	MelloUI:On("column", function()
		if S.on and S.followed then
			QL.Dress()
		elseif S.on then
			Settle()   -- (2.1.53: placed by the player, still as wide as the minimap where it matches it)
		end
	end, QL)
	-- (its quest lines' marks: the followed quest changed -- the game's event MelloUI's own tracker lays its marks by)
	local follow = CreateFrame("Frame")
	follow:RegisterEvent("SUPER_TRACKING_CHANGED")
	Perf.SetScript(follow, "OnEvent", function()
		QL.RefreshMarks()
	end)
	local function Again()
		if rawget(_G, "Questie_BaseFrame") then
			QL.Dress()
		end
	end
	MelloUI:On("module", function(name)
		if name == "QuestTracker" then
			Again()
		end
	end, QL)
	MelloUI:On("setting", function(name, key, value)
		if name ~= "QuestTracker" then
			return
		end
		if key == "opacity" and S.panel then
			Opacity(S.panel)
		elseif QL.SET_BY[key] then
			Settle()   -- (2.1.53: written into Questie's)
		elseif key == "pos" and value == nil then
			Reset()   -- (2.1.53: Reset Position)
		end
	end, QL)
end)
