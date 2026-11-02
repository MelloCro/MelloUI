--------------------------------------------------------------------------------
-- MelloUI - Own Bars: the experience / reputation bars and the bag bar as MelloUI's own (fr-18 stage 1, 2026-11-01;
-- the user, after the installer put the bars back at their default places once more: "Make all of those parts our
-- own" -- EllesmereUI keeps its own bars placed by its own movers, MelloUI kept the game's and placed them through
-- Edit Mode)
--
-- While UI Modifications is on, the experience / reputation bars and the bag bar on the screen are ours:
--   * The status bars: two containers of ours (MelloUIStatusBar1 / 2, where the game's Main / Secondary
--     StatusTrackingBarContainer stood), each with the game's own bars made from the game's own templates
--     (ExpStatusBarTemplate, ReputationStatusBarTemplate, HonorStatusBarTemplate ... -- Blizzard_StatusTrackingBar
--     of this client: the same art, text, rested fill and tick, gain and level-up animations, tooltips), so their
--     look is the game's by construction. Which bar each container shows, its fade in and out, its frame picture and
--     dividers are the game's StatusTrackingManager / StatusTrackingBarContainer logic copied here (never run on a
--     game frame: no ManageFramePositions, no Edit Mode call). The fades are MelloUI.Anim groups (Reduce Motion).
--   * The bag bar: MelloUIBagBar with ItemButtons of ours for the backpack, the four bag slots, the reagent slot and
--     the key ring, carrying the game's own bag-slot mixins (BaseBagSlotButtonMixin, MainMenuBarBackpackMixin,
--     CharacterReagentBagMixin, KeyRingMixin: copied onto our buttons, so a click, a drag, the tooltip, the slot art
--     and the search fade are the game's); what the game's buttons do through the paper doll's own functions
--     (PaperDollItemSlotButton_*: they reach the merchant and paper doll windows) is done here with the same calls.
--     The bar lays itself as BagsBarMixin:Layout lays the game's, with a manager of ours (OB.BagManager: the
--     expandBagBar setting and an item on the cursor, as MainMenuBarBagManager).
--   Both are built with the game's keys (BarFrameTexture, bars[index].StatusBar.Background, HorizontalDividersPool;
--   BorderArt, icon, SlotHighlightTexture ...), so every dresser of MelloUI's dresses them as it dressed the game's:
--   MelloUI Frames' status look and the backdrops (Action Bars), Bar Textures, Dark Mode, the Fader, Tweaks (Hide
--   Bag Bar, Bag Slots On Bag Window, the Collapse Arrow, XP Gain, Reputation Gain, Level Up), the painted skin
--   (MelloUI_Oldschool's Action Bars Kit), the bag window's flights -- through MelloUI.OwnBars (below).
--
-- Places (fr-18 sim, 2026-11-01): a place of their own in MelloUI's mover store (Core's positions) comes only from
-- the player's Edit Layout save, a profile load or the installer, or an import. Until then ours FOLLOW the game's
-- frames: hung by the game's own anchor point on the game's frame (live: the bottom stack, a layout, a skin's micro
-- menu moving it moves ours), at its scale; the status bars always at the game's container's width (the layout's
-- Size; one of their own comes with stage 2). The second status bar with no place of its own stacks as the game's
-- bottom stack stacks it (Camelot's order: the main bar, the second, the first), or stands at its layout place --
-- never at the second container's unlaid default. Followed again whenever the game lays a layout (see Following).
--
-- The game's frames kept away while ours stand in (fr-16 / fr-17's means): StatusTrackingBarManager and BagsBar at
-- alpha 0 (no game code writes either's alpha); the game's bars' and bag buttons' mouse off; Edit Mode's selection
-- boxes on them unseen and click-through; their events let go (MelloUI.Units.Silence, each one's registrations kept
-- to give back exactly). No key written on them or their regions, no hook on them, nothing of them shown, hidden or
-- moved. Given back exactly when UI Modifications (or this module) goes off; ours standing in again after that asks
-- for a /reload once (MelloUI:AskReload: a dresser may have hooked the game's frames meanwhile).
--
-- MelloUI.OwnBars (the one way every module finds these frames):
--   OwnBars.G(name) -> frame | nil       ours standing in for the game's global `name` (MainStatusTrackingBarContainer,
--                                        SecondaryStatusTrackingBarContainer, StatusTrackingBarManager -- our manager
--                                        table --, BagsBar, MainMenuBarBackpackButton, CharacterBag0Slot ..,
--                                        CharacterReagentBag0Slot, KeyRingButton, BagBarExpandToggle,
--                                        MainMenuBarBagManager -- our bag manager), else the game's global
--   OwnBars.Frame(name) -> frame | nil   ours for `name` only (nil while the game's stands)
--   OwnBars.On(part) -> bool             "status" / "bags" standing in now
--   OwnBars.Holds(system, index) -> bool an Edit Mode system ours stand in for (by its Enum.EditModeSystem name)
--   OwnBars.IsKey(key) -> bool           one of our places' keys in Core's store
--   OwnBars.Away(obj) -> bool            obj is one of the game's frames kept away now (or in one)
--   OwnBars.Dump(print)                  what stands where (/run MelloUI.OwnBars.Dump(print))
-- The bus: 'ownbars' (part, on) when ours come or go; 'ownbars:bags' when the bag bar laid itself out again.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("OwnBars")
local Shared = Perf.Shared
local C_Timer = Perf.C_Timer
local hooksecurefunc = Perf.hooksecurefunc
local Safe = MelloUI.Safe
local Secret = Safe.IsSecret
local Finite = Safe.Finite

local WEAK = { __mode = "k" }
local OB = {
	own = {},                              -- [the game's global name] = ours while it stands in
	mine = setmetatable({}, WEAK),         -- [frame] = true: one of ours
	away = setmetatable({}, WEAK),         -- [a game frame kept away] = true (what is in it is away too)
	standing = {},                         -- [part] = true while ours stand in
	stood = {},                            -- [part] = true: ours stood in once this session (a second time asks a /reload)
	keptMouse = setmetatable({}, WEAK),    -- [a game frame] = its mouse before (given back)
	keptAlpha = setmetatable({}, WEAK),    -- [a game frame] = its alpha before (given back)
}
MelloUI.OwnBars = OB

-- our places in Core's store (keys = our frames' names)
local KEYS = { status1 = "MelloUIStatusBar1", status2 = "MelloUIStatusBar2", bags = "MelloUIBagBar" }
local IS_KEY = { [KEYS.status1] = true, [KEYS.status2] = true, [KEYS.bags] = true }
local OWNER = { status = "Own Bars: the status bars", bags = "Own Bars: the bag bar" }

-- the Edit Mode systems ours stand in for (Enum.EditModeSystem names; index nil = every index)
local SYSTEMS = { StatusTrackingBar = "status", Bags = "bags" }

local M = MelloUI:RegisterModule("OwnBars", {
	title = "Own Bars",
	desc = "The experience and reputation bars and the bag bar as MelloUI's own: placed by Edit Layout and the profiles.",
	-- (always on, as Action Bars: no switch of its own; ours stand in while UI Modifications is on)
	hidden = true,
	enabledByDefault = true,
	defaults = { bagVertical = false, bagReverse = false },
	options = {
		-- (fr-18: Edit Mode's Orientation and Direction for the bag bar, now ours: in its Edit Layout box)
		{ type = "toggle", key = "bagVertical", name = "Vertical Bag Bar", new = "2.1.0",
		  desc = "The bag bar stands upright instead of lying flat." },
		{ type = "toggle", key = "bagReverse", name = "Bags On The Other Side", new = "2.1.0",
		  desc = "The bag slots line up on the other side of the backpack (right instead of left, or down instead of up)." },
	},
	-- (the game's Orientation and Direction taken once, the first time ours stood in: this machine's step)
	keep = { "bagTaken", "seedsDropped" },
})
OB.module = M

--------------------------------------------------------------------------------
-- Finding the frames
--------------------------------------------------------------------------------

function OB.Frame(name)
	return OB.own[name]
end

function OB.G(name)
	local f = OB.own[name]
	if f ~= nil then
		return f
	end
	return rawget(_G, name)
end

function OB.On(part)
	return OB.standing[part] == true
end

function OB.Holds(system, index)
	local part = SYSTEMS[system]
	if not part then
		return false
	end
	if part == "status" and index ~= nil and index ~= 1 and index ~= 2 then
		return false
	end
	return OB.standing[part] == true
end

function OB.IsKey(key)
	return IS_KEY[key] == true
end

-- obj is a game frame kept away, or in one (its parents walked; ours never)
function OB.Away(obj)
	if type(obj) ~= "table" or next(OB.away) == nil then
		return false
	end
	local cur = obj
	for _ = 1, 8 do
		if type(cur) ~= "table" or OB.mine[cur] then
			return false
		end
		if OB.away[cur] then
			return true
		end
		local fn = cur.GetParent
		if type(fn) ~= "function" then
			return false
		end
		local ok, p = pcall(fn, cur)
		cur = ok and p or nil
	end
	return false
end

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function Field(t, key)
	if type(t) ~= "table" then
		return nil
	end
	local ok, v = pcall(rawget, t, key)
	if not ok or Secret(v) then
		return nil
	end
	return v
end

local function Call(obj, method, ...)
	if type(obj) ~= "table" or type(obj[method]) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e = pcall(obj[method], obj, ...)
	if not ok or Secret(a) then
		return nil
	end
	return a, b, c, d, e
end

-- a frame's scale against UIParent's (its parents' scales in it), plain; 1 when unreadable
local function ScaleOn(f)
	local fs = Finite(Call(f, "GetEffectiveScale"))
	local us = Finite(Call(UIParent, "GetEffectiveScale"))
	if fs and us and fs > 0 and us > 0 then
		return fs / us
	end
	return 1
end

local function Contains(list, v)
	for i = 1, #list do
		if list[i] == v then
			return true
		end
	end
	return false
end

-- the Units system's event silencer (fr-16 / fr-17's: one system), nil before it loaded
local function Units()
	local U = rawget(MelloUI, "Units")
	return (type(U) == "table" and type(U.Silence) == "function") and U or nil
end

--------------------------------------------------------------------------------
-- The game's frames kept away and given back
--------------------------------------------------------------------------------

-- a game frame unseen (alpha 0: no game code writes the holders' alpha), its old alpha kept
local function Fade(f)
	if type(f) ~= "table" or OB.keptAlpha[f] ~= nil then
		return
	end
	local a = Finite(Call(f, "GetAlpha"))
	OB.keptAlpha[f] = a or 1
	pcall(f.SetAlpha, f, 0)
	OB.away[f] = true
end

local function Unfade(f)
	local a = OB.keptAlpha[f]
	if a == nil then
		return
	end
	OB.keptAlpha[f] = nil
	OB.away[f] = nil
	pcall(f.SetAlpha, f, a)
end

-- a game frame's mouse off (its hover would take the pointer over ours), the old setting kept
local function MouseOff(f)
	if type(f) ~= "table" or type(f.EnableMouse) ~= "function" or OB.keptMouse[f] ~= nil then
		return
	end
	local on = Call(f, "IsMouseEnabled")
	OB.keptMouse[f] = on == true
	if on == true then
		pcall(f.EnableMouse, f, false)
	end
end

local function MouseBack(f)
	local on = OB.keptMouse[f]
	if on == nil then
		return
	end
	OB.keptMouse[f] = nil
	if on then
		pcall(f.EnableMouse, f, true)
	end
end

-- Edit Mode's selection box on a game system: unseen and click-through (it ignores its parent's alpha)
local function SelectionAway(f)
	local sel = Field(f, "Selection")
	if type(sel) == "table" then
		Fade(sel)
		MouseOff(sel)
	end
end

local function SelectionBack(f)
	local sel = Field(f, "Selection")
	if type(sel) == "table" then
		Unfade(sel)
		MouseBack(sel)
	end
end

--------------------------------------------------------------------------------
-- Places: our own movers; following the game's frames until one has a place of its own (fr-18 sim, 2026-11-01:
-- stage 1 took the game's place into the store once, and the game's frames went on moving without ours -- the
-- second bar's place was taken from its unlaid default, the bottom stack re-centred under a skin's micro menu, Mello's
-- layout went in at its own width and places)
--------------------------------------------------------------------------------

OB.gameOf = setmetatable({}, WEAK)   -- [ours] = the game's frame it stands in for
OB.keyOf = setmetatable({}, WEAK)    -- [ours] = its key in Core's store
OB.followed = setmetatable({}, WEAK) -- [ours] = { game, point, scale, lift } as last followed (nil: a place of its own)
OB.ownScale = setmetatable({}, WEAK) -- [ours] = the game's scale last put on ours at a place of its own (fr-18d: OwnScale)

-- ours has a place of its own: the player's Edit Layout save, a profile, the installer, an import
local function OwnPlace(ours)
	local key = OB.keyOf[ours]
	return key ~= nil and MelloUI:GetPosition(key) ~= nil
end

local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
	BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

-- the point the game's frame hangs by (its first anchor's), so a scale of ours (the backdrops' fit) grows it the
-- way the game's grew; CENTER when unreadable
local function GamePoint(game)
	local p = Call(game, "GetPoint", 1)
	return (type(p) == "string" and POINTS[p]) and p or "CENTER"
end

-- ours hung by `point` on `anchor` (the game's frame, or where the game's bottom stack puts it), at the game's
-- scale, `lift` UIParent units up; only what changed is set again (a scale of the backdrops' fit on ours is kept
-- while the game's own scale stays); true when something changed
local function HangOnGame(ours, game, anchor, point, relPoint, lift)
	if type(game) ~= "table" or type(anchor) ~= "table" then
		return false
	end
	local scale = ScaleOn(game)
	local was = OB.followed[ours]
	local changed = false
	if not (was and math.abs(was.scale - scale) < 0.0005) then
		pcall(ours.SetScale, ours, scale)
		changed = true
	end
	local own = Finite(Call(ours, "GetScale")) or scale
	lift = lift or 0
	if changed or not (was and was.anchor == anchor and was.point == point and was.relPoint == relPoint
		and math.abs(was.lift - lift) < 0.01) then
		ours:ClearAllPoints()
		ours:SetPoint(point, anchor, relPoint, 0, lift / (own > 0 and own or 1))
		changed = true
	end
	OB.followed[ours] = { anchor = anchor, point = point, relPoint = relPoint, scale = scale, lift = lift }
	return changed
end

-- ours on the game's frame itself (its own anchor point: live, the game's frame moving moves ours)
local function OnGame(ours, game)
	local p = GamePoint(game)
	return HangOnGame(ours, game, game, p, p, 0)
end

-- a status container at the game's container's width and height (the layout's Size: the game's own
-- UpdateSystemSetting lays its bars and dividers again the same way); kept whatever its place. true: changed
local function FollowSize(c, game)
	local w, h = Finite(Call(game, "GetWidth")), Finite(Call(game, "GetHeight"))
	local cw, ch = Finite(Call(c, "GetWidth")), Finite(Call(c, "GetHeight"))
	if not (w and h and w > 0 and h > 0) or (cw and ch and math.abs(cw - w) < 0.01 and math.abs(ch - h) < 0.01) then
		return false
	end
	c:SetSize(w, h)
	c:ResizeContainerBars()
	c:UpdateDividers(c:GetExpectedSegments())
	c:UpdateShownBarAll()   -- (its fill, text and rested tick laid on the new width)
	return true
end

-- the game's system frame laid by Edit Mode's bottom stack (in its default place), read only
local function StackLaid(game)
	return Call(game, "IsInDefaultPosition") == true
end

-- the stack's first row: where the game's bottom stack lays its first status bar -- on the main action bar, the
-- bar's height and a spacer up (EditModeManagerFrame:UpdateBottomActionBarPositions, the main bar its base); nil
-- without a shown main bar. (Never the game's first container itself: the game's own manager still lays its unseen
-- containers when OverrideActionBar's experience bar calls it on PLAYER_XP_UPDATE, and its stack lifts them)
local function StackSlot()
	local base = rawget(_G, "MainActionBar")
	local h = type(base) == "table" and Call(base, "IsShown") == true and Finite(Call(base, "GetHeight"))
	if not h then
		return nil
	end
	return base, h + (tonumber(rawget(_G, "BOTTOM_ACTION_BARS_SPACER_Y")) or 4)
end

-- (live while ours stand in: Edit Layout's plate, Core's place on show)
local LIVE = {
	status = function() return OB.standing.status == true end,
	bags = function() return OB.standing.bags == true end,
}

OB.followers = {}   -- [part] = its follow pass (set below with each part)

-- every part as it should stand now: a place of its own restored from the store, else following the game's frames
local function FollowAll()
	OB.followSoon = false
	for part, fn in pairs(OB.followers) do
		if OB.standing[part] then
			local ok, err = pcall(fn)
			if not ok then
				geterrorhandler()(err)
			end
		end
	end
end
-- (the game lays its layout: on the next frame, after the game's own pass has placed and sized its frames)
OB.FollowSoon = Shared("Own Bars: the game's frames followed", function()
	if not OB.followSoon and next(OB.standing) ~= nil then
		OB.followSoon = true
		C_Timer.After(0, FollowAll)
	end
end, "script")
-- the store of places replaced or written (a profile, the installer, an import, Edit Layout's save): ours where it
-- says, or following again
local function StoreChanged(module, key)
	if module == "UIModifications" and key == "positions" then
		OB.FollowSoon()
	end
end

-- (fr-18d) Edit Layout's session let go of one of ours (Save, Discard, Revert, a write of the store): laid again
local function Released(what, entry)
	if what == "released" and type(entry) == "table" and OB.keyOf[entry.frame] ~= nil then
		OB.FollowSoon()
	end
end

local FOLLOW_EVENTS = { "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_ENTERING_WORLD", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }
local function FollowListen()
	if OB.waiter then
		return
	end
	OB.waiter = CreateFrame("Frame")
	OB.waiter:SetScript("OnEvent", OB.FollowSoon)
	for _, e in ipairs(FOLLOW_EVENTS) do
		pcall(OB.waiter.RegisterEvent, OB.waiter, e)
	end
	-- (MelloUI's own: a layout put in or made active, a skin switched, Edit Mode closed, the store written)
	MelloUI:On("editmodelayout", OB.FollowSoon, "Own Bars: an Edit Mode layout put in")
	MelloUI:On("skin", OB.FollowSoon, "Own Bars: the skin switched")
	MelloUI:On("editmode", OB.FollowSoon, "Own Bars: Edit Mode opened or closed")
	MelloUI:On("setting", StoreChanged, "Own Bars: the store of places written")
	MelloUI:On("mover", Released, "Own Bars: Edit Layout let go of one of ours")
end

-- (Edit Layout's Reset and Core's default place: ours following the game's frame again)
local function HomeOf()
	OB.followed = setmetatable({}, WEAK)
	FollowAll()
end

local function Register(frame, part, key, label, placeholder, anchor)
	OB.keyOf[frame] = key
	return MelloUI:RegisterMover(frame, frame, { key = key, group = "hud", label = label, category = "bars",
		placeholder = placeholder, anchor = anchor, base = 1, when = LIVE[part], default = HomeOf, reset = HomeOf })
end

-- (fr-18d, the user 2026-11-01: "i cant move the bag bars and exp / reputation bar") Edit Layout's session holds it --
-- under a drag, or at a pending place -- and it is no Reset (Reset and Default place follow the game's frame again:
-- HomeOf): it stands where Edit Layout has it, never put back on the game's frame or on its old place under the
-- pointer; laid again when the session lets go of it ('mover' "released", Released: Core's rule for owners that lay
-- their element, MelloUI.LayoutSession)
local function EditHeld(ours)
	local LS = MelloUI.LayoutSession
	local entry = LS and MelloUI:MoverEntry(ours)
	return entry ~= nil and LS.Holds(entry) and not LS.IsReset(entry)
end

-- (fr-18d) ours' 100 % in Edit Layout (its entry's base) is the game's frame's scale, kept in step with it; at a place
-- of its own with no size of its own ours stand at that scale, as they stood while following and when the place was
-- made (a place is kept in ours' own units: at another scale it lands elsewhere -- Mello's layout's bag bar at 75 % came
-- back at 100 % after a /reload, off where it was dropped). Set only when the game's scale changed (a backdrop's fit on
-- ours is kept, as HangOnGame keeps it)
local function OwnScale(ours, pos)
	local s = ScaleOn(OB.gameOf[ours])
	local entry = MelloUI:MoverEntry(ours)
	if entry then
		entry.base = s
	end
	if pos == nil then
		OB.ownScale[ours] = nil
	elseif pos.scale == nil then
		local was = OB.ownScale[ours]
		if not (was and math.abs(was - s) < 0.0005) then
			pcall(ours.SetScale, ours, s)
		end
		OB.ownScale[ours] = s
	else
		OB.ownScale[ours] = nil
	end
end

-- one of ours placed as it should be now: true when it follows (no place of its own)
local function Place(ours)
	if EditHeld(ours) then
		return false
	end
	local key = OB.keyOf[ours]
	local pos = OwnPlace(ours) and MelloUI:GetPosition(key) or nil
	if type(pos) ~= "table" then
		OwnScale(ours, nil)
		return true
	end
	local was = OB.followed[ours]
	if was and OB.ownScale[ours] == nil then
		OB.ownScale[ours] = was.scale   -- (the scale it followed at is on it already)
	end
	OB.followed[ours] = nil
	OwnScale(ours, pos)
	MelloUI:RestorePosition(key, ours)
	return false
end

--------------------------------------------------------------------------------
-- The status bars (the game's StatusTrackingManager / StatusTrackingBarContainer of this client, copied: our
-- containers, the game's own bar templates in them)
--------------------------------------------------------------------------------

local NONE = -1
local TEMPLATES = {   -- (the game's InitializeBars order)
	{ "Reputation", "ReputationStatusBarTemplate" }, { "Honor", "HonorStatusBarTemplate" },
	{ "Artifact", "ArtifactStatusBarTemplate" }, { "Experience", "ExpStatusBarTemplate" },
	{ "Azerite", "AzeriteBarTemplate" }, { "HouseFavor", "HouseFavorBarTemplate" },
}
local STATUS_EVENTS = { "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN",
	"CVAR_UPDATE", "UPDATE_EXPANSION_LEVEL", "PLAYER_ENTERING_WORLD", "HONOR_XP_UPDATE", "ZONE_CHANGED",
	"ZONE_CHANGED_NEW_AREA", "UNIT_INVENTORY_CHANGED", "ARTIFACT_XP_UPDATE", "AZERITE_ITEM_EXPERIENCE_CHANGED",
	"PLAYER_EQUIPMENT_CHANGED", "TRACKED_HOUSE_CHANGED", "PLAYER_MAX_LEVEL_UPDATE" }
-- (every event the game's manager, containers and bars register: let go on theirs while ours stand in)
local STATUS_GAME_EVENTS = { "UNIT_LEVEL", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP",
	"PLAYER_UPDATE_RESTING", "UNIT_PET_EXPERIENCE", "HONOR_LEVEL_UPDATE" }
for _, e in ipairs(STATUS_EVENTS) do
	STATUS_GAME_EVENTS[#STATUS_GAME_EVENTS + 1] = e
end
local GAME_STATUS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }

-- our manager: a table of ours, the game's StatusTrackingBarManager's shape (barContainers, its two keys) and logic
local S = { barContainers = {}, shownBarIndices = {} }
OB.Status = S

local function BarsEnum()
	local info = rawget(_G, "StatusTrackingBarInfo")
	return type(info) == "table" and type(info.BarsEnum) == "table" and info.BarsEnum or nil
end

function S:GetBarPriority(barIndex)
	local info = rawget(_G, "StatusTrackingBarInfo")
	local p = type(info) == "table" and type(info.BarPriorities) == "table" and info.BarPriorities[barIndex]
	return tonumber(p) or -1
end

-- StatusTrackingManagerMixin:CanShowBar (this client's), each test in a pcall: a client without one shows none
local CAN = {
	Reputation = function()
		local d = C_Reputation.GetWatchedFactionData()
		return d and d.name ~= ""
	end,
	Honor = function()
		return _G.IsWatchingHonorAsXP() or _G.C_PvP.IsActiveBattlefield() or _G.IsInActiveWorldPVP()
	end,
	Artifact = function()
		return _G.HasArtifactEquipped() and not _G.C_ArtifactUI.IsEquippedArtifactMaxed() and not _G.C_ArtifactUI.IsEquippedArtifactDisabled()
	end,
	Experience = function()
		return _G.GameRulesUtil.CanShowExperienceBar()
	end,
	Azerite = function()
		local item = _G.C_AzeriteItem.FindActiveAzeriteItem()
		return not _G.C_AzeriteItem.IsAzeriteItemAtMaxLevel() and item and item:IsEquipmentSlot() and _G.C_AzeriteItem.IsAzeriteItemEnabled(item)
	end,
	HouseFavor = function()
		return _G.C_Housing.GetTrackedHouseGuid()
	end,
}

function S:CanShowBar(name)
	local fn = CAN[name]
	if not fn then
		return false
	end
	local ok, v = pcall(fn)
	return ok and not Secret(v) and v and true or false
end

function S:IsTextLocked()
	return self.textLocked
end

function S:SetTextLocked(locked)
	if self.textLocked ~= locked then
		self.textLocked = locked
		self:UpdateBarTextVisibility()
	end
end

function S:UpdateBarTextVisibility()
	for _, c in ipairs(self.barContainers) do
		c:UpdateBarTextVisibility()
	end
end

function S:CheckForLayoutChange()
	for _, c in ipairs(self.barContainers) do
		c:ResizeContainerBars()
		c:UpdateDividers(c:GetExpectedSegments())
	end
end

-- (a container done animating: the bars again on the next frame -- never inside the pass that is still assigning them,
-- which a fade settled at once under Reduce Motion would otherwise re-enter)
local function UpdateNow()
	S.soon = false
	if OB.standing.status then
		S:UpdateBarsShown()
	end
end

local function OnShownAnimated(c)
	c:UnsubscribeFromOnFinishedAnimating(S)
	if not S.soon then
		S.soon = true
		C_Timer.After(0, UpdateNow)
	end
end

function S:UpdateBarsShown()
	local enum = BarsEnum()
	if not enum then
		return
	end
	-- (a container still fading or a bar still filling: again when it is done)
	for _, c in ipairs(self.barContainers) do
		if c:IsAnimating() then
			c:SubscribeToOnFinishedAnimating(self, OnShownAnimated)
			return
		end
	end
	local show = {}
	for name, index in pairs(enum) do
		if index ~= NONE and self:CanShowBar(name) then
			show[#show + 1] = index
		end
	end
	table.sort(show, function(a, b) return self:GetBarPriority(a) > self:GetBarPriority(b) end)
	while #show > #self.barContainers do
		table.remove(show, #show)
	end
	for i = 1, #self.barContainers do
		local c = self.barContainers[i]
		local new = show[i] or NONE
		local old = self.shownBarIndices[i]
		if new ~= old then
			if (new ~= NONE and Contains(self.shownBarIndices, new)) or (old ~= nil and old ~= NONE and Contains(show, old)) then
				new = NONE
				c:SubscribeToOnFinishedAnimating(self, OnShownAnimated)
			end
		end
		c:SetShownBar(new)
	end
	self.shownBarIndices = show
	-- (a container that cleared its bar with no fade -- one the Fader holds at alpha 0 -- tells now that it is done, so
	-- the bars are laid again on the next frame; the game's own waited for its next event)
	for _, c in ipairs(self.barContainers) do
		local waits = c.animationFinishedCallbacks
		if waits and waits[self] and not c:IsAnimating() then
			c:CheckIfStillAnimating()
		end
	end
	MelloUI:Fire("ownbars:status")
end

S.OnEvent = Shared("Own Bars: the status bars' events", function(_, event)
	if not OB.standing.status then
		return
	end
	if event == "CVAR_UPDATE" then
		S:UpdateBarTextVisibility()
	end
	if UnitExists("player") then
		for _, c in ipairs(S.barContainers) do
			c:UpdateShownBarAll()
		end
		S:UpdateBarsShown()
	end
end, "script")

-- the containers' own methods (StatusTrackingBarContainerMixin of this client, copied: ours only)
local C = {}

function C.GetStatusTrackingManager()
	return S
end

function C.GetShownBar(self)
	return self.bars[self.shownBarIndex]
end

function C.GetExpectedSegments()
	local gamepad = InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
	local n = tonumber(gamepad and rawget(_G, "STATUS_BAR_NUM_SEGMENTS_GAMEPAD") or rawget(_G, "STATUS_BAR_NUM_SEGMENTS"))
	return n or 20
end

function C.ResizeContainerBars(self)
	local adj = tonumber(rawget(_G, "STATUS_BAR_SIZE_ADJUSTMENT")) or 3
	local w, h = (Finite(Call(self, "GetWidth")) or 0) - adj, (Finite(Call(self, "GetHeight")) or 0) - adj
	for _, bar in pairs(self.bars) do
		bar:SetSize(w, h)
		bar.StatusBar:SetSize(w, h)
	end
end

function C.UpdateDividers(self, numSegments)
	-- (this client's own StatusTrackingBarContainerMixin.UpdateDividers run on ours -- never on a game frame -- so the
	-- dividers stand exactly where the client lays its own: one build snaps them to the pixel grid (PixelUtil.SetPoint),
	-- another does not; a copy put them up to half a pixel apart -- fr-18 sim, 2026-11-01. The copy below without it)
	local mixin = rawget(_G, "StatusTrackingBarContainerMixin")
	local own = type(mixin) == "table" and rawget(mixin, "UpdateDividers")
	if type(own) == "function" and pcall(own, self, numSegments) then
		return
	end
	if not self.HorizontalDividersPool then
		if type(_G.CreateFramePool) ~= "function" then
			return
		end
		local ok, pool = pcall(_G.CreateFramePool, "FRAME", self, "StatusBarDividerTemplate")
		if not ok or type(pool) ~= "table" then
			return
		end
		self.HorizontalDividersPool = pool
	end
	local pool = self.HorizontalDividersPool
	pool:ReleaseAll()
	if numSegments <= 1 then
		return
	end
	local w = (Finite(Call(self, "GetWidth")) or 0) / numSegments
	for i = 1, numSegments - 1 do
		local divider = pool:Acquire()
		divider:SetPoint("LEFT", self, "LEFT", w * i, 0)
		divider:Show()
	end
end

function C.SetShownBar(self, barIndex)
	if self.shownBarIndex == barIndex then
		self.pendingBarToShowIndex = nil
		return
	end
	self.pendingBarToShowIndex = barIndex
	if not self:IsVisible() or (Finite(self:GetAlpha()) or 0) <= 0 then
		if barIndex == NONE then
			self:ApplyPendingBarToShow()
		else
			self:FadeIn()
		end
	else
		self:FadeOut()
	end
end

function C.ApplyPendingBarToShow(self)
	if not self.pendingBarToShowIndex then
		return
	end
	if self.shownBarIndex == self.pendingBarToShowIndex then
		self.pendingBarToShowIndex = nil
		return
	end
	local old = self:GetShownBar()
	if old then
		old:Hide()
	end
	local new = self.bars[self.pendingBarToShowIndex]
	if new then
		new:UpdateAll()
		new:Show()
	end
	self.shownBarIndex = self.pendingBarToShowIndex
	self.pendingBarToShowIndex = nil
end

function C.UpdateShownState(self)
	local was = self:IsShown()
	self:SetShown(self.shownBarIndex ~= NONE and OB.standing.status == true)
	S:CheckForLayoutChange()
	-- (the second bar came or went: the stack laid again, as the game's bottom stack lays it when a bar shows or hides)
	if was ~= self:IsShown() and OB.followers.status then
		local ok, err = pcall(OB.followers.status)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

-- the fades: MelloUI.Anim groups (under Reduce Motion they end at once, their end run by the settle)
-- (no alpha written here: a played group ends at its final alpha by itself -- SetToFinalAlpha, as the game's -- and
-- MelloUI.Anim's settle puts a group's final alpha on at once under Reduce Motion. A second write of ours right after
-- either, within the Fader's busy time, made the Fader take it as the game's own and leave the bars shown it held
-- faded -- fr-18 sim, 2026-11-01)
local function FadeInDone(group)
	group:GetParent():CheckIfStillAnimating()
end

local function FadeOutDone(group)
	local c = group:GetParent()
	if c.pendingBarToShowIndex then
		c:FadeIn()
		return
	end
	c:UpdateShownState()
	c:CheckIfStillAnimating()
end

-- (settled at once: the end alpha written only where the group can't put it on itself -- a client without
-- SetToFinalAlpha)
local function Settled(group, alpha)
	if not (group.IsSetToFinalAlpha and group:IsSetToFinalAlpha()) then
		group:GetParent():SetAlpha(alpha)
	end
end

local function FadeInSettled(group)
	Settled(group, 1)
	FadeInDone(group)
end

local function FadeOutSettled(group)
	Settled(group, 0)
	FadeOutDone(group)
end

local function Play(group, settle)
	MelloUI.Anim:StopGroup(group)
	MelloUI.Anim:PlayGroup(group, settle)
end

function C.FadeIn(self)
	self:ApplyPendingBarToShow()
	self:UpdateShownState()
	if self.shownBarIndex == NONE then
		self:CheckIfStillAnimating()
		return
	end
	if self.FadeInAnimation:IsPlaying() or (Finite(self:GetAlpha()) or 0) >= 1 then
		return
	end
	if self.FadeOutAnimation:IsPlaying() or self.MaxLevelFadeOutAnimation:IsPlaying() then
		self.FadeOutAnimation:Stop()
		self.MaxLevelFadeOutAnimation:Stop()
	end
	Play(self.FadeInAnimation, FadeInSettled)
end

function C.FadeOut(self)
	if self.FadeOutAnimation:IsPlaying() or self.MaxLevelFadeOutAnimation:IsPlaying() or (Finite(self:GetAlpha()) or 0) <= 0 then
		return
	end
	if self.FadeInAnimation:IsPlaying() then
		self.FadeInAnimation:Stop()
	end
	Play(self.FadeOutAnimation, FadeOutSettled)
end

function C.IsShownBarAnimating(self)
	local bar = self:GetShownBar()
	local sb = bar and bar.StatusBar
	if not sb then
		return false
	end
	return (Call(sb, "IsAnimating") or Call(sb, "IsDirty")) and true or false
end

local function CleanDone(sb, c)
	pcall(sb.UnsubscribeFromOnClean, sb, c)
	c:CheckIfStillAnimating()
end

local function FilledDone(sb, c)
	pcall(sb.UnsubscribeFromOnFinishedAnimating, sb, c)
	c:CheckIfStillAnimating()
end

function C.SubscribeToShownBarOnFinishedAnimating(self)
	local bar = self:GetShownBar()
	local sb = bar and bar.StatusBar
	if not sb then
		return
	end
	if Call(sb, "IsDirty") then
		pcall(sb.SubscribeToOnClean, sb, self, function(b) CleanDone(b, self) end)
	elseif Call(sb, "IsAnimating") then
		pcall(sb.SubscribeToOnFinishedAnimating, sb, self, function(b) FilledDone(b, self) end)
	end
end

function C.IsAnimating(self)
	return self.FadeInAnimation:IsPlaying() or self.FadeOutAnimation:IsPlaying()
		or self.MaxLevelFadeOutAnimation:IsPlaying() or self:IsShownBarAnimating()
end

function C.CheckIfStillAnimating(self)
	if self:IsAnimating() then
		if self:IsShownBarAnimating() then
			self:SubscribeToShownBarOnFinishedAnimating()
		end
		return
	end
	if self.animationFinishedCallbacks then
		for _, fn in pairs(self.animationFinishedCallbacks) do
			fn(self)
		end
	end
end

function C.SubscribeToOnFinishedAnimating(self, who, fn)
	self.animationFinishedCallbacks = self.animationFinishedCallbacks or {}
	self.animationFinishedCallbacks[who] = fn
	if self:IsShownBarAnimating() then
		self:SubscribeToShownBarOnFinishedAnimating()
	end
end

function C.UnsubscribeFromOnFinishedAnimating(self, who)
	if self.animationFinishedCallbacks then
		self.animationFinishedCallbacks[who] = nil
	end
end

function C.UpdateShownBarAll(self)
	local bar = self:GetShownBar()
	if bar then
		bar:UpdateAll()
	end
end

function C.UpdateBarTextVisibility(self)
	local bar = self:GetShownBar()
	if bar then
		bar:UpdateTextVisibility()
	end
end

function C.UpdateBarTick(self)
	local bar = self:GetShownBar()
	if bar then
		bar:UpdateTick()
	end
end

function C.ShowText(self)
	local bar = self:GetShownBar()
	if bar then
		bar:ShowText()
	end
end

function C.HideText(self)
	local bar = self:GetShownBar()
	if bar then
		bar:HideText()
	end
end

local function FadeGroup(c, from, to, delay)
	local group = MelloUI.Anim:Group(c)
	group:SetToFinalAlpha(true)
	local a = group:CreateAnimation("Alpha")
	a:SetFromAlpha(from)
	a:SetToAlpha(to)
	a:SetDuration(0.5)
	a:SetStartDelay(delay or 0)
	a:SetSmoothing("IN_OUT")
	return group
end

-- one container of ours where the game's `game` stands: its size, strata, level and frame picture the game's, its
-- bars made from the game's own templates; nil when this client can't make the experience bar
local function NewContainer(i, game)
	local c = CreateFrame("Frame", KEYS["status" .. i], UIParent)
	OB.mine[c] = true
	for k, fn in pairs(C) do
		c[k] = fn
	end
	c:SetFrameStrata(Call(game, "GetFrameStrata") or "MEDIUM")
	local level = Finite(Call(game, "GetFrameLevel"))
	if level then
		c:SetFrameLevel(level)
	end
	local w = Finite(Call(game, "GetWidth")) or tonumber(rawget(_G, "STATUS_BAR_CONTAINER_WIDTH")) or 1192
	local h = Finite(Call(game, "GetHeight")) or tonumber(rawget(_G, "STATUS_BAR_CONTAINER_HEIGHT")) or 17
	c:SetSize(w, h)
	c:Hide()
	c:SetAlpha(0)
	c.shownBarIndex = NONE
	c.bars = {}
	-- the frame picture (the template's OVERLAY texture, the game's atlas at its own size, anchored as the game's)
	local gameTex = Field(game, "BarFrameTexture")
	local tex = c:CreateTexture(nil, "OVERLAY")
	local atlas = Call(gameTex, "GetAtlas") or "UI-HUD-ExperienceBar-Frame"
	pcall(tex.SetAtlas, tex, atlas, true)
	local n = Finite(Call(gameTex, "GetNumPoints")) or 0
	for p = 1, n do
		local point, rel, relPoint, x, y = Call(gameTex, "GetPoint", p)
		if point then
			pcall(tex.SetPoint, tex, point, (rel == game or rel == nil) and c or rel, relPoint, Finite(x) or 0, Finite(y) or 0)
		end
	end
	c.BarFrameTexture = tex
	c:SetScript("OnShow", OB.FollowSoon)
	c.FadeInAnimation = FadeGroup(c, 0, 1)
	c.FadeInAnimation:SetScript("OnFinished", FadeInDone)
	c.FadeOutAnimation = FadeGroup(c, 1, 0)
	c.FadeOutAnimation:SetScript("OnFinished", FadeOutDone)
	c.MaxLevelFadeOutAnimation = FadeGroup(c, 1, 0, 1)
	c.MaxLevelFadeOutAnimation:SetScript("OnFinished", FadeOutDone)
	-- the dividers first, then the bars (InitializeBars' order: the dividers' frames made before the bars', as the
	-- game's -- fr-18 sim, 2026-11-01)
	c:UpdateDividers(c:GetExpectedSegments())
	-- the bars (InitializeBars): the game's templates, laid as the game lays them
	local enum = BarsEnum()
	local adj = tonumber(rawget(_G, "STATUS_BAR_SIZE_ADJUSTMENT")) or 3
	local bw, bh = w - adj, h - adj
	for _, spec in ipairs(TEMPLATES) do
		local index = enum and enum[spec[1]]
		if index then
			local ok, bar = pcall(CreateFrame, "Frame", nil, c, spec[2])
			if ok and type(bar) == "table" and type(rawget(bar, "StatusBar")) == "table" and type(bar.UpdateAll) == "function" then
				bar.barIndex = index
				bar.barName = spec[1]
				bar:ClearAllPoints()
				bar:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 1, adj - 1)
				bar.StatusBar:SetSize(bw, bh)
				bar:SetSize(bw, bh)
				if rawget(bar, "fadeOutEntireBarAtMaxLevel") and type(bar.StatusBar.SetLevelUpMaxAlphaAnimation) == "function" then
					pcall(bar.StatusBar.SetLevelUpMaxAlphaAnimation, bar.StatusBar, c.MaxLevelFadeOutAnimation)
				end
				bar:Hide()
				c.bars[index] = bar
			elseif ok and type(bar) == "table" then
				bar:Hide()   -- (a template this client lacks: its empty frame left unseen)
			end
		end
	end
	local xp = enum and c.bars[enum.Experience]
	if not xp then
		return nil
	end
	return c
end

local function BuildStatus()
	if S.built ~= nil then
		return S.built
	end
	S.built = false
	local manager = rawget(_G, "StatusTrackingBarManager")
	local games = {}
	for i, name in ipairs(GAME_STATUS) do
		games[i] = rawget(_G, name) or Field(manager, name)
	end
	if not (games[1] and games[2] and BarsEnum()) then
		return false
	end
	for i = 1, 2 do
		local ok, c = pcall(NewContainer, i, games[i])
		if not ok then
			geterrorhandler()(c)
			return false
		end
		if not c then
			return false
		end
		S.barContainers[i] = c
		OB.gameOf[c] = games[i]
	end
	S.MainStatusTrackingBarContainer, S.SecondaryStatusTrackingBarContainer = S.barContainers[1], S.barContainers[2]
	S.games = games
	S.events = CreateFrame("Frame")
	S.events:SetScript("OnEvent", S.OnEvent)
	S.built = true
	return true
end

local STATUS_LABELS = { "Experience and reputation", "Experience and reputation 2" }

-- The status bars where they should stand (fr-18 sim): one with a place of its own where the store says; the first
-- following the game's first container; the second following the game's second where the layout places it, else
-- stacked as the game's bottom stack stacks it (EditModeManagerFrame:UpdateBottomActionBarPositions, Camelot's order:
-- the main bar, the second, the first) -- on the first's spot, the first one row up while the second shows -- never
-- at the second container's unlaid default (it is laid only while shown, and the game's is kept hidden)
local function StatusFollow()
	if not OB.standing.status then
		return
	end
	local c1, c2, g1, g2 = S.barContainers[1], S.barContainers[2], S.games[1], S.games[2]
	local changed = FollowSize(c1, g1)
	changed = FollowSize(c2, g2) or changed
	local follow1, follow2 = Place(c1), Place(c2)
	local stacked, firstLaid = StackLaid(g2), StackLaid(g1)
	local base, up = StackSlot()
	if follow2 then
		if not stacked then
			changed = OnGame(c2, g2) or changed
		elseif base then
			changed = HangOnGame(c2, g2, base, "BOTTOMLEFT", "BOTTOMLEFT", up * ScaleOn(g2)) or changed
		else
			changed = HangOnGame(c2, g2, g1, "BOTTOMLEFT", "BOTTOMLEFT", 0) or changed
		end
	end
	if follow1 then
		local lift = 0
		if stacked and firstLaid and c2:IsShown() then
			local gap = tonumber(rawget(_G, "PRIMARY_AND_SECONDARY_STATUS_TRACKING_BAR_SPACER_Y")) or -1
			lift = (Finite(Call(c2, "GetHeight")) or 0) * ScaleOn(c2) + gap * ScaleOn(g1)
		end
		if firstLaid and base then
			changed = HangOnGame(c1, g1, base, "BOTTOMLEFT", "BOTTOMLEFT", up * ScaleOn(g1) + lift) or changed
		else
			local p = GamePoint(g1)
			changed = HangOnGame(c1, g1, g1, p, p, lift) or changed
		end
	end
	if changed then
		MelloUI:Fire("bagbar")   -- (Action Bars' backdrops laid round them again)
	end
end
OB.followers.status = StatusFollow

local function StatusAway()
	local manager = rawget(_G, "StatusTrackingBarManager")
	if type(manager) == "table" then
		Fade(manager)
	end
	for _, game in ipairs(S.games) do
		SelectionAway(game)
		local bars = Field(game, "bars")
		for _, bar in pairs(type(bars) == "table" and bars or {}) do
			MouseOff(bar)
			MouseOff(Field(bar, "ExhaustionTick"))
		end
	end
	local U = Units()
	if U and type(manager) == "table" then
		U.Silence(manager, STATUS_GAME_EVENTS, OWNER.status, 3)
	end
end

local function StatusBack()
	local manager = rawget(_G, "StatusTrackingBarManager")
	local U = Units()
	if U then
		U.Unsilence(OWNER.status)
	end
	for _, game in ipairs(S.games or {}) do
		SelectionBack(game)
		local bars = Field(game, "bars")
		for _, bar in pairs(type(bars) == "table" and bars or {}) do
			MouseBack(bar)
			MouseBack(Field(bar, "ExhaustionTick"))
		end
	end
	if type(manager) == "table" then
		Unfade(manager)
	end
end

local function StatusOn()
	if not BuildStatus() then
		return false
	end
	StatusAway()
	OB.own.MainStatusTrackingBarContainer = S.barContainers[1]
	OB.own.SecondaryStatusTrackingBarContainer = S.barContainers[2]
	OB.own.StatusTrackingBarManager = S
	OB.standing.status = true
	-- (fr-18d) a plate while hidden for the first only, as Edit Mode shows its first status bar alone while it is open
	-- (EditModeStatusTrackingBar1SystemMixin:OnEditModeEnter): the hidden second, stacked on the first's spot, lay
	-- over the shown first at its very rect and took its press
	for i, c in ipairs(S.barContainers) do
		local w, h = Finite(Call(c, "GetWidth")) or 100, Finite(Call(c, "GetHeight")) or 17
		Register(c, "status", KEYS["status" .. i], STATUS_LABELS[i], i == 1 and { w, h } or nil, "BOTTOM")
	end
	OB.followed[S.barContainers[1]], OB.followed[S.barContainers[2]] = nil, nil
	StatusFollow()
	FollowListen()
	for _, e in ipairs(STATUS_EVENTS) do
		pcall(S.events.RegisterEvent, S.events, e)
	end
	pcall(S.events.RegisterUnitEvent, S.events, "UNIT_LEVEL", "player")
	S.shownBarIndices = {}
	S:UpdateBarsShown()
	return true
end

local function StatusOff()
	OB.standing.status = nil
	OB.own.MainStatusTrackingBarContainer, OB.own.SecondaryStatusTrackingBarContainer = nil, nil
	OB.own.StatusTrackingBarManager = nil
	if S.events then
		S.events:UnregisterAllEvents()
	end
	-- (each container empty and unseen, so the bars are laid anew when ours stand in again)
	for _, c in ipairs(S.barContainers) do
		MelloUI.Anim:StopGroup(c.FadeInAnimation)
		MelloUI.Anim:StopGroup(c.FadeOutAnimation)
		MelloUI.Anim:StopGroup(c.MaxLevelFadeOutAnimation)
		local bar = c:GetShownBar()
		if bar then
			bar:Hide()
		end
		c.shownBarIndex, c.pendingBarToShowIndex = NONE, nil
		c:SetAlpha(0)
		c:Hide()
	end
	S.shownBarIndices = {}
	StatusBack()
end

--------------------------------------------------------------------------------
-- The bag bar (BagsBar and its bag buttons of this client, made ours)
--------------------------------------------------------------------------------

-- the game's buttons in the game's order (MainMenuBarBagManager's list as it registered them), our names for them
local BAG_ORDER = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
	"CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }
local OUR_NAME = { MainMenuBarBackpackButton = "MelloUIBagBackpack", CharacterBag0Slot = "MelloUIBag0Slot",
	CharacterBag1Slot = "MelloUIBag1Slot", CharacterBag2Slot = "MelloUIBag2Slot", CharacterBag3Slot = "MelloUIBag3Slot",
	CharacterReagentBag0Slot = "MelloUIReagentBag0Slot", KeyRingButton = "MelloUIKeyRing" }
local KIND = { MainMenuBarBackpackButton = "backpack", CharacterReagentBag0Slot = "reagent", KeyRingButton = "keyring" }
-- the game's buttons' own fields their mixins read (KeyValues of their templates), copied onto ours
local BUTTON_FIELDS = { "buttonShape", "commandName", "bagIcon", "bagAtlas", "normalAndPushedTextureWidth",
	"normalAndPushedTextureHeight", "showMatchHighlight", "quickKeybindHighlightAtlas" }
-- every event the game's bag buttons and paper-doll slot code register (let go on theirs while ours stand in)
local BAG_GAME_EVENTS = { "ITEM_PUSH", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "INVENTORY_SEARCH_UPDATE",
	"BAG_UPDATE", "AZERITE_EMPOWERED_ITEM_LOOTED", "CVAR_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "MERCHANT_UPDATE",
	"PLAYERBANKSLOTS_CHANGED", "ITEM_LOCK_CHANGED", "CURSOR_CHANGED", "UPDATE_INVENTORY_ALERTS",
	"AZERITE_ITEM_POWER_LEVEL_CHANGED", "AZERITE_EMPOWERED_ITEM_SELECTION_UPDATED", "UNIT_INVENTORY_CHANGED",
	"BAG_UPDATE_COOLDOWN", "MODIFIER_STATE_CHANGED", "UPDATE_EXTRA_ACTIONBAR" }
-- what an equipped bag slot of ours listens to (the paper doll's events for a bag, PaperDollItemSlotButton_OnShow)
local SLOT_EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "ITEM_LOCK_CHANGED", "CURSOR_CHANGED", "UPDATE_INVENTORY_ALERTS",
	"UNIT_INVENTORY_CHANGED", "BAG_UPDATE" }
-- (MainMenuBarBagManager: an item, a merchant's or a guild bank's on the cursor opens the folded bar)
local CURSOR_OPENS = { "Item", "Merchant", "GuildBank" }

local B = { buttons = {}, byGame = {} }
OB.Bags = B

-- our bag manager (MainMenuBarBagManager's shape and logic, for our buttons)
local BM = { allBagButtons = {}, expandBar = true, expandBarAuto = false }
OB.BagManager = BM

function BM:EnumerateBagButtons()
	return ipairs(self.allBagButtons)
end

function BM:ShouldBarExpand()
	return self.expandBar or self.expandBarAuto
end

function BM:IsBarUserExpanded()
	return self.expandBar
end

function BM:ToggleExpandBar()
	SetCVar("expandBagBar", not GetCVarBool("expandBagBar"))
end

function BM:OnExpandBarChanged()
	local bar = B.bar
	if bar and bar:ShouldShowExpandToggle() then
		local open = self:ShouldBarExpand()
		for _, button in self:EnumerateBagButtons() do
			button:SetBarExpanded(open)
		end
	end
	if bar then
		bar:Layout()
	end
	MelloUI:Fire("ownbars:bagexpand", self)
end

function BM:SetExpandBar(on)
	local was = self.expandBar
	self.expandBar = on and true or false
	if was ~= self.expandBar then
		self:OnExpandBarChanged()
	end
end

function BM:SetExpandBarAuto(on)
	local was = self.expandBarAuto
	self.expandBarAuto = on and true or false
	if was ~= self.expandBarAuto then
		self:OnExpandBarChanged()
	end
end

-- the bar's own methods (BagsBarMixin of this client, copied: ours only)
local BAR = {}

function BAR.IsHorizontal(self)
	return self.isHorizontal
end

function BAR.IsDirectionLeft(self)
	return self:IsHorizontal() and self.direction == B.LEFT
end

function BAR.IsDirectionUp(self)
	return not self:IsHorizontal() and self.direction == B.UP
end

function BAR.ShouldShowExpandToggle(self)
	return not self.hideExpandToggle
end

function BAR.OnUpdateEndCaps()
end

function BAR.MainActionBarStateOverridden()
end

function BAR.GetBagButtonAnchorPoints(self)
	local pad = self.bagPadding or 0
	if self:IsHorizontal() then
		if self:IsDirectionLeft() then
			return "RIGHT", "LEFT", -pad, 0
		end
		return "LEFT", "RIGHT", pad, 0
	end
	if self:IsDirectionUp() then
		return "BOTTOM", "TOP", 0, pad
	end
	return "TOP", "BOTTOM", 0, -pad
end

function BAR.GetBagBarLength(self)
	local horizontal, total = self:IsHorizontal(), 0
	for i, button in BM:EnumerateBagButtons() do
		total = total + (Finite(horizontal and button:GetWidth() or button:GetHeight()) or 0)
		if i ~= 1 then
			total = total + (self.bagPadding or 0)
		end
	end
	if self:ShouldShowExpandToggle() then
		total = total + (horizontal and self.bagBarExpandToggleInitialWidth or self.bagBarExpandToggleInitialHeight)
	end
	return total
end

function BAR.Layout(self)
	local horizontal = self:IsHorizontal()
	for _, button in BM:EnumerateBagButtons() do
		if button.UpdateOrientation then
			button:UpdateOrientation(horizontal)
		end
	end
	local long = self:GetBagBarLength()
	if horizontal then
		self:SetSize(long, self.initialHeight)
	else
		self:SetSize(self.initialHeight, long)
	end
	local point, relativePoint, x, y = self:GetBagButtonAnchorPoints()
	local pack, toggle = B.pack, B.toggle
	pack:ClearAllPoints()
	pack:SetPoint(point, self, point)
	if self:ShouldShowExpandToggle() and toggle then
		if horizontal then
			toggle:SetSize(self.bagBarExpandToggleInitialWidth, self.bagBarExpandToggleInitialHeight)
		else
			toggle:SetSize(self.bagBarExpandToggleInitialHeight, self.bagBarExpandToggleInitialWidth)
		end
		toggle:ClearAllPoints()
		toggle:SetPoint(point, pack, relativePoint)
	end
	local anchor = (self:ShouldShowExpandToggle() and toggle) or pack
	for _, button in BM:EnumerateBagButtons() do
		if button:IsShown() and button ~= pack then
			button:ClearAllPoints()
			button:SetPoint(point, anchor, relativePoint, x, y)
			anchor = button
		end
	end
	if self.useDividers then
		self:UpdateDividers()
	end
end

function BAR.UpdateDividers(self)
	if not self.HorizontalDividersPool then
		if type(_G.CreateFramePool) ~= "function" then
			return
		end
		local okH, h = pcall(_G.CreateFramePool, "FRAME", self, "HorizontalDividerTemplate")
		local okV, v = pcall(_G.CreateFramePool, "FRAME", self, "VerticalDividerTemplate")
		if not (okH and okV and type(h) == "table" and type(v) == "table") then
			self.useDividers = false
			return
		end
		self.HorizontalDividersPool, self.VerticalDividersPool = h, v
	end
	self.HorizontalDividersPool:ReleaseAll()
	self.VerticalDividersPool:ReleaseAll()
	local pool = self.isHorizontal and self.HorizontalDividersPool or self.VerticalDividersPool
	local lastShown = false
	for _, button in BM:EnumerateBagButtons() do
		if button:IsShown() then
			if lastShown then
				local d = pool:Acquire()
				d:ClearAllPoints()
				if self.isHorizontal then
					d:SetPoint("TOP", button, "TOP", 0, 0)
					d:SetPoint("BOTTOM", button, "BOTTOM", 0, 0)
					if self:IsDirectionLeft() then
						d:SetPoint("LEFT", button, "RIGHT", -5, 0)
					else
						d:SetPoint("RIGHT", button, "LEFT", 5, 0)
					end
				else
					d:SetPoint("LEFT", button, "LEFT", 0, 0)
					d:SetPoint("RIGHT", button, "RIGHT", 0, 0)
					if self:IsDirectionUp() then
						d:SetPoint("TOP", button, "BOTTOM", 0, 5)
					else
						d:SetPoint("BOTTOM", button, "TOP", 0, -5)
					end
				end
				d:Show()
			end
			lastShown = true
		else
			lastShown = false
		end
	end
end

-- (the bar laid out: the fold and the backdrops told, as the game's Layout tells its hooks)
local BarLaid = Shared("Own Bars: the bag bar laid out", function()
	MelloUI:Fire("ownbars:bags")
end)

-- The buttons' own code (what the game's bag buttons do through PaperDollItemSlotButton_*, done here on ours:
-- those reach the merchant's and the paper doll's windows)
local BTN = {}

function BTN.Update(self)
	local id = self:GetID()
	local tex = GetInventoryItemTexture("player", id)
	if tex then
		_G.SetItemButtonTexture(self, tex)
		SetItemButtonCount(self, _G.GetInventoryItemCount("player", id))
		local broken = _G.GetInventoryItemBroken("player", id) or _G.GetInventoryItemEquippedUnusable("player", id)
		if broken then
			_G.SetItemButtonTextureVertexColor(self, 0.9, 0, 0)
			_G.SetItemButtonNormalTextureVertexColor(self, 0.9, 0, 0)
		else
			_G.SetItemButtonTextureVertexColor(self, 1, 1, 1)
			_G.SetItemButtonNormalTextureVertexColor(self, 1, 1, 1)
		end
	else
		_G.SetItemButtonTexture(self, self.backgroundTextureName)
		SetItemButtonCount(self, 0)
		_G.SetItemButtonTextureVertexColor(self, 1, 1, 1)
		_G.SetItemButtonNormalTextureVertexColor(self, 1, 1, 1)
	end
	if self.UpdateItemContextMatching then
		self:UpdateItemContextMatching()
	end
	SetItemButtonQuality(self, _G.GetInventoryItemQuality("player", id), GetInventoryItemID("player", id))
	SetItemButtonDesaturated(self, _G.IsInventoryItemLocked(id))
end

-- the backpack's free slots, as MainMenuBarBackpackMixin:UpdateFreeSlots (its tutorials are the game's backpack's)
function BTN.UpdateFreeSlots(self)
	local free = Safe.Number(C_Container.CalculateTotalNumberOfFreeBagSlots()) or 0
	self.freeSlots = free
	self.FreeSlots:SetText(("(%s)"):format(free))
end

function BTN.FreeNow()
	B.freeSoon = false
	if B.pack then
		BTN.UpdateFreeSlots(B.pack)
	end
end

-- the key ring's picture (KeyRingMixin:OnBagUpdate; its tutorial and pulse are the game's key ring's)
function BTN.KeyRingArt(self)
	if C_ActionBar.ShouldShowKeyring() then
		self.bagAtlas = GetCVarBool("showKeyring") and "UI-HUD-ActionBar-Keyring-Small" or "UI-HUD-ActionBar-IconFrame-Slot-Small"
		self:UpdateTextures()
	end
end

function BTN.FlyIn(self, icon)
	if not icon or MelloUI.Anim.reduceMotion or not self.FlyInAnim then
		return
	end
	self.AnimIcon:SetTexture(icon)
	self.AnimIcon:Show()
	MelloUI.Anim:StopGroup(self.FlyInAnim)
	MelloUI.Anim:PlayGroup(self.FlyInAnim)
end

local function FlyDone(group)
	group:GetParent().AnimIcon:Hide()
end

local function Listen(self, on)
	for _, e in ipairs(SLOT_EVENTS) do
		if on then
			pcall(self.RegisterEvent, self, e)
		else
			pcall(self.UnregisterEvent, self, e)
		end
	end
end

BTN.OnEvent = Shared("Own Bars: a bag button's events", function(self, event, a1, a2)
	local kind = self.ownKind
	if event == "ITEM_PUSH" then
		if self:GetID() == a1 then
			BTN.FlyIn(self, a2)
		end
	elseif event == "INVENTORY_SEARCH_UPDATE" then
		self:UpdateBagMatchesSearch()
	elseif kind == "backpack" then
		if event == "BAG_UPDATE" then
			local bag = tonumber(a1)
			if bag and bag >= (_G.BACKPACK_CONTAINER or 0) and bag <= (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5) then
				if not B.freeSoon then   -- (a frame later, as the game's: bags moved settle first; one timer, no closure)
					B.freeSoon = true
					C_Timer.After(0, BTN.FreeNow)
				end
			end
		elseif event == "PLAYER_ENTERING_WORLD" then
			self:SetCountShown(GetCVar("displayFreeBagSlots") == "1")
			BTN.UpdateFreeSlots(self)
			self:UpdateBagMatchesSearch()
		elseif event == "CVAR_UPDATE" and a1 == "displayFreeBagSlots" then
			self:SetCountShown(GetCVar("displayFreeBagSlots") == "1")
		end
	elseif kind == "keyring" then
		if event == "PLAYER_ENTERING_WORLD" or event == "BAG_UPDATE" then
			self:UpdateBagMatchesSearch()
			BTN.KeyRingArt(self)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		self:UpdateBagMatchesSearch()
		BTN.Update(self)
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		if self:GetID() == a1 then
			BTN.Update(self)
		end
	elseif event == "UNIT_INVENTORY_CHANGED" then
		if a1 == "player" then
			BTN.Update(self)
		end
	elseif event == "ITEM_LOCK_CHANGED" then
		if a2 == nil and a1 == self:GetID() then
			SetItemButtonDesaturated(self, _G.IsInventoryItemLocked(self:GetID()))
		end
	elseif event == "CURSOR_CHANGED" then
		if _G.C_PaperDollInfo.CursorCanGoInSlot(self:GetID()) then
			self:LockHighlight()
		else
			self:UnlockHighlight()
		end
	else
		BTN.Update(self)   -- (BAG_UPDATE, BAG_UPDATE_DELAYED, UPDATE_INVENTORY_ALERTS)
	end
end, "script")

-- (what the ItemButton intrinsic's PostOnShow / PostOnHide do, done here too: our OnShow script stands where the
-- intrinsic's may not run, and a button that never worked out its item context is drawn under the 0.8 black
-- ItemContextOverlay -- the backpack and the key ring were, fr-18 sim 2026-11-01. Both calls are the game's own and
-- keyed by the button, so running them twice is the same as once)
local function ItemContextOn(self)
	if self.UpdateItemContextMatching then
		pcall(self.UpdateItemContextMatching, self)
	end
	local util = rawget(_G, "ItemButtonUtil")
	if self.GetItemContextMatchResult and type(util) == "table" and util.RegisterCallback and util.Event then
		pcall(util.RegisterCallback, util.Event.ItemContextChanged, self.OnItemContextChanged, self)
	end
end

local function ItemContextOff(self)
	local util = rawget(_G, "ItemButtonUtil")
	if type(util) == "table" and util.UnregisterCallback and util.Event then
		pcall(util.UnregisterCallback, util.Event.ItemContextChanged, self)
	end
end

local function OnShowSlot(self)
	if self.ownKind == "bag" or self.ownKind == "reagent" then
		Listen(self, true)
		BTN.Update(self)
	end
	ItemContextOn(self)
end

local function OnHideSlot(self)
	if self.ownKind == "bag" or self.ownKind == "reagent" then
		Listen(self, false)
	end
	ItemContextOff(self)
end

local function OnClick(self, button, down)
	self:BagSlotOnClick(button, down)
end

local function OnDragStart(self, button)
	self:BagSlotOnDragStart(button)
end

local function OnReceiveDrag(self)
	self:BagSlotOnReceiveDrag()
end

local function OnEnter(self)
	self:BagSlotOnEnter()
end

local function OnLeave(self)
	self:BagSlotOnLeave()
end

-- the parts the bag slot templates add to an ItemButton (BaseBagSlotButtonTemplate, SquareBagSlotButtonTemplate,
-- MainMenuBarBackpackButtonBase), as the game's own button has them
local function SlotParts(b, game)
	b.AnimIcon = b:CreateTexture(nil, "OVERLAY", nil, 6)
	b.AnimIcon:SetAllPoints(b)
	b.AnimIcon:Hide()
	b.SlotHighlightTexture = b:CreateTexture(nil, "OVERLAY", nil, 6)
	b.SlotHighlightTexture:SetAllPoints(b)
	b.SlotHighlightTexture:Hide()
	local gameMask = Field(game, "SquareMask")
	if b.CreateMaskTexture and b.icon then
		local mask = b:CreateMaskTexture(nil, "OVERLAY", nil, 6)
		local atlas = Call(gameMask, "GetAtlas") or "UI-HUD-ActionBar-IconFrame-Mask"
		pcall(mask.SetAtlas, mask, atlas)
		local mw, mh = Finite(Call(gameMask, "GetWidth")), Finite(Call(gameMask, "GetHeight"))
		if mw and mh and mw > 0 and mh > 0 then
			mask:SetSize(mw, mh)
		end
		pcall(mask.SetWrap, mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetPoint("CENTER", b.icon, "CENTER")
		pcall(b.icon.AddMaskTexture, b.icon, mask)
		b.SquareMask = mask
	end
	-- (the fly-in of an item pushed into the bag: BagSlotItemFlyInMixin's group, MelloUI.Anim's. The game plays its
	-- group in reverse -- FlyIn:Play(true): the icon from up and left into the slot, shrinking and fading -- so it is
	-- built here the way round it plays: the icon starts where the game's path ends, the path's points from there --
	-- fr-18 sim, 2026-11-01: played forward it flew out of the bag, growing)
	b.AnimIcon:ClearAllPoints()
	b.AnimIcon:SetPoint("TOPLEFT", b, "TOPLEFT", -75, 60)
	b.AnimIcon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -75, 60)
	local ok, group = pcall(MelloUI.Anim.Group, MelloUI.Anim, b)
	if ok and type(group) == "table" then
		local okA = pcall(function()
			local s = group:CreateAnimation("Scale")
			s:SetTarget(b.AnimIcon)
			s:SetScaleFrom(1, 1)
			s:SetScaleTo(0.125, 0.125)
			s:SetDuration(1)
			local a = group:CreateAnimation("Alpha")
			a:SetTarget(b.AnimIcon)
			a:SetFromAlpha(1)
			a:SetToAlpha(0)
			a:SetDuration(1)
			local p = group:CreateAnimation("Path")
			p:SetTarget(b.AnimIcon)
			p:SetCurveType("SMOOTH")
			p:SetDuration(1)
			p:CreateControlPoint():SetOffset(60, -30)
			p:CreateControlPoint():SetOffset(75, -60)
		end)
		if okA then
			group:SetScript("OnFinished", FlyDone)
			b.FlyInAnim = group
		end
	end
end

-- one bag button of ours for the game's `gameName`; nil when this client can't make it
local function NewButton(bar, gameName, game)
	local kind = KIND[gameName] or "bag"
	local base = rawget(_G, "BaseBagSlotButtonMixin")
	-- (the game's template chain: BaseBagSlotButtonTemplate's mixin first, then the button's own. The backpack's own
	-- mixin is a copy of the base made before this client's Camelot file adds UpdateTextures and the slot art to the
	-- base, so alone it draws no bag icon and keeps the ItemButton's default frame -- fr-18 sim, 2026-11-01)
	local mixins = { base }
	if kind == "backpack" then
		mixins[2] = rawget(_G, "MainMenuBarBackpackMixin")
	elseif kind == "reagent" then
		mixins[2] = rawget(_G, "CharacterReagentBagMixin")
	elseif kind == "keyring" then
		mixins[2] = rawget(_G, "KeyRingMixin")
	end
	for i = 1, #mixins do
		if type(mixins[i]) ~= "table" then
			return nil
		end
	end
	local ok, b = pcall(CreateFrame, "ItemButton", OUR_NAME[gameName], bar)
	if not (ok and type(b) == "table" and b.icon and b.GetNormalTexture) then
		return nil
	end
	OB.mine[b] = true
	Mixin(b, unpack(mixins))
	for _, k in ipairs(BUTTON_FIELDS) do
		local v = Field(game, k)
		if v ~= nil then
			b[k] = v
		end
	end
	b.ownKind = kind
	b.gameName = gameName
	local w, h = Finite(Call(game, "GetWidth")), Finite(Call(game, "GetHeight"))
	if w and h then
		b:SetSize(w, h)
	end
	b.initialWidth, b.initialHeight = w, h
	-- (the game's button's own level: the bag slots sit in BagSlotCluster, a level above the bar's dividers, which
	-- otherwise drew over their rims -- fr-18 sim, 2026-11-01)
	local level = Finite(Call(game, "GetFrameLevel"))
	if level then
		b:SetFrameLevel(level)
	end
	local id = Finite(Call(game, "GetID"))
	if id then
		b:SetID(id)
	end
	SlotParts(b, game)
	b:RegisterForClicks("AnyUp")
	b.isBag = 1
	b.maxDisplayCount = 999
	b.UpdateTooltip = b.BagSlotOnEnter
	if kind == "backpack" then
		b.FreeSlots = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		b.FreeSlots:SetDrawLayer("OVERLAY", 5)
		b.FreeSlots:Hide()
		b.FreeSlots:SetPoint("CENTER", 0, -10)
		for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE", "INVENTORY_SEARCH_UPDATE", "CVAR_UPDATE" }) do
			pcall(b.RegisterEvent, b, e)
		end
	elseif kind == "keyring" then
		b.Count:ClearAllPoints()
		b.Count:SetPoint("CENTER", 0, -10)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE", "INVENTORY_SEARCH_UPDATE" }) do
			pcall(b.RegisterEvent, b, e)
		end
	else
		b:RegisterForDrag("LeftButton")
		b.Count:ClearAllPoints()
		b.Count:SetPoint("BOTTOMRIGHT", -2, 2)
		local slot = gameName:sub(10)
		local okS, slotId, background = pcall(_G.C_PaperDollInfo.GetInventorySlotInfo, slot)
		if okS then
			b.backgroundTextureName = background
			if not id and slotId then
				b:SetID(slotId)
			end
		end
		for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "INVENTORY_SEARCH_UPDATE" }) do
			pcall(b.RegisterEvent, b, e)
		end
		Listen(b, true)
		if b.RegisterBagButtonUpdateItemContextMatching then
			pcall(b.RegisterBagButtonUpdateItemContextMatching, b)
		end
	end
	pcall(b.RegisterEvent, b, "ITEM_PUSH")
	b:SetScript("OnEvent", BTN.OnEvent)
	b:SetScript("OnShow", OnShowSlot)
	b:SetScript("OnHide", OnHideSlot)
	b:SetScript("OnClick", OnClick)
	b:SetScript("OnDragStart", OnDragStart)
	b:SetScript("OnReceiveDrag", OnReceiveDrag)
	b:SetScript("OnEnter", OnEnter)
	b:SetScript("OnLeave", OnLeave)
	-- (an open bag lit on its button, as the game's: the game's container frames tell it)
	if EventRegistry and EventRegistry.RegisterCallback then
		pcall(EventRegistry.RegisterCallback, EventRegistry, "ContainerFrame.OpenBag", b.UpdateBagButtonHighlight, b)
		pcall(EventRegistry.RegisterCallback, EventRegistry, "ContainerFrame.CloseBag", b.UpdateBagButtonHighlight, b)
	end
	pcall(b.UpdateTextures, b)
	if kind == "keyring" then
		pcall(BTN.KeyRingArt, b)
	elseif kind == "backpack" then
		pcall(b.SetCountShown, b, GetCVar("displayFreeBagSlots") == "1")
		pcall(BTN.UpdateFreeSlots, b)
	else
		pcall(BTN.Update, b)
	end
	-- shown as the game's shows it (the reagent slot and the key ring stay hidden where this client has none)
	b:SetShown(Call(game, "IsShown") == true)
	if b:IsShown() then
		ItemContextOn(b)   -- (made shown: no OnShow to run it)
	end
	return b
end

local function BuildBags()
	if B.built ~= nil then
		return B.built
	end
	B.built = false
	local game = rawget(_G, "BagsBar")
	if type(game) ~= "table" then
		return false
	end
	local E = rawget(_G, "Enum")
	local enum = type(E) == "table" and E.BagsDirection
	enum = type(enum) == "table" and enum or { Left = 0, Right = 1, Up = 2, Down = 3 }
	B.LEFT, B.RIGHT, B.UP, B.DOWN = enum.Left, enum.Right, enum.Up, enum.Down
	local bar = CreateFrame("Frame", KEYS.bags, UIParent)
	OB.mine[bar] = true
	for k, fn in pairs(BAR) do
		bar[k] = fn
	end
	bar:SetFrameStrata(Call(game, "GetFrameStrata") or "MEDIUM")
	local level = Finite(Call(game, "GetFrameLevel"))
	if level then
		bar:SetFrameLevel(level)
	end
	bar.useDividers = Field(game, "useDividers") ~= false
	bar.bagPadding = tonumber(Field(game, "bagPadding")) or 2
	bar.hideExpandToggle = Field(game, "hideExpandToggle") ~= false
	bar.initialHeight = Finite(Field(game, "initialHeight")) or 45
	bar.isHorizontal = Field(game, "isHorizontal") ~= false
	bar.direction = Field(game, "direction") or B.LEFT
	-- the frame art round it (the template's, at its own offsets)
	local art = bar:CreateTexture(nil, "BACKGROUND", nil, -3)
	local gameArt = Field(game, "BorderArt")
	pcall(art.SetAtlas, art, Call(gameArt, "GetAtlas") or "UI-HUD-ActionBar-Frame")
	art:SetPoint("TOPLEFT", bar, "TOPLEFT", -6, 6)
	art:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 5, -5)
	art.ignoreInLayout = true
	bar.BorderArt = art
	-- the buttons, in the game's order
	local order = {}
	local list = Field(rawget(_G, "MainMenuBarBagManager"), "allBagButtons")
	for _, gb in ipairs(type(list) == "table" and list or {}) do
		local name = Call(gb, "GetName")
		if name and OUR_NAME[name] then
			order[#order + 1] = name
		end
	end
	if #order == 0 then
		order = BAG_ORDER
	end
	for _, name in ipairs(order) do
		local gb = rawget(_G, name)
		if type(gb) == "table" then
			local ok, b = pcall(NewButton, bar, name, gb)
			if not ok then
				geterrorhandler()(b)
				b = nil
			end
			if not b then
				if name == "MainMenuBarBackpackButton" then
					return false
				end
			else
				B.buttons[#B.buttons + 1] = b
				B.byGame[name] = b
				BM.allBagButtons[#BM.allBagButtons + 1] = b
			end
		end
	end
	B.pack = B.byGame.MainMenuBarBackpackButton
	if not B.pack then
		return false
	end
	-- the fold's arrow (BagBarExpandToggle: the game's art, unseen until Tweaks' Collapse Arrow shows it)
	local gameToggle = rawget(_G, "BagBarExpandToggle")
	local toggle = CreateFrame("Button", "MelloUIBagBarExpandToggle", bar)
	OB.mine[toggle] = true
	local tw, th = Finite(Call(gameToggle, "GetWidth")) or 10, Finite(Call(gameToggle, "GetHeight")) or 16
	toggle:SetSize(tw, th)
	for _, which in ipairs({ "Normal", "Pushed", "Highlight" }) do
		local t = toggle:CreateTexture(nil, which == "Highlight" and "HIGHLIGHT" or "ARTWORK")
		pcall(t.SetAtlas, t, "bag-arrow")
		t:SetSize(tw, th)
		t:SetPoint("CENTER")
		toggle["Set" .. which .. "Texture"](toggle, t)
		toggle[which .. "Texture"] = t
	end
	local hl = toggle:GetHighlightTexture()
	if hl then
		hl:SetAlpha(0.4)
		hl:SetBlendMode("ADD")
	end
	toggle:RegisterForClicks("LeftButtonUp")
	toggle:SetScript("OnClick", function() BM:ToggleExpandBar() end)
	toggle:Hide()
	B.toggle = toggle
	bar.bagBarExpandToggleInitialWidth = bar.hideExpandToggle and 0 or tw
	bar.bagBarExpandToggleInitialHeight = bar.hideExpandToggle and 0 or th
	hooksecurefunc(bar, "Layout", BarLaid)
	bar:SetScript("OnShow", OB.FollowSoon)
	B.bar = bar
	B.game = game
	OB.gameOf[bar] = game
	-- the expand state as the game's manager keeps it: the setting, an item on the cursor
	BM.expandBar = GetCVarBool("expandBagBar") and true or false
	B.events = CreateFrame("Frame")
	B.events:SetScript("OnEvent", B.OnEvent)
	B.built = true
	return true
end

B.OnEvent = Shared("Own Bars: the bag bar's expand state", function(_, event, a1, a2)
	if not OB.standing.bags then
		return
	end
	if event == "EXPAND_BAG_BAR_CHANGED" then
		BM:SetExpandBar(a1)
	elseif event == "CURSOR_CHANGED" then
		local E = rawget(_G, "Enum")
		local types = type(E) == "table" and E.UICursorType
		local open = false
		for _, name in ipairs(CURSOR_OPENS) do
			if type(types) == "table" and types[name] ~= nil and types[name] == a2 then
				open = true
			end
		end
		BM:SetExpandBarAuto(open)
	end
end, "script")

-- the bar's orientation from our settings (taken from the game's Edit Mode setting the first time)
local function BagOrientation(db)
	local bar = B.bar
	if not (bar and db) then
		return
	end
	if not db.bagTaken then
		db.bagTaken = true
		local game = B.game
		db.bagVertical = Field(game, "isHorizontal") == false
		local dir = Field(game, "direction")
		db.bagReverse = (dir ~= nil) and (dir == B.RIGHT or dir == B.DOWN) or false
	end
	bar.isHorizontal = not db.bagVertical
	if bar.isHorizontal then
		bar.direction = db.bagReverse and B.RIGHT or B.LEFT
	else
		bar.direction = db.bagReverse and B.DOWN or B.UP
	end
end

-- the bag bar where it should stand (fr-18 sim): a place of its own where the store says, else on the game's bag bar
local function BagsFollow()
	if OB.standing.bags and Place(B.bar) and OnGame(B.bar, B.game) then
		MelloUI:Fire("bagbar")   -- (Action Bars' backdrop laid round it again)
	end
end
OB.followers.bags = BagsFollow

local function BagButtonsOf(fn)
	for _, name in ipairs(BAG_ORDER) do
		local gb = rawget(_G, name)
		if type(gb) == "table" then
			fn(gb)
		end
	end
	local gt = rawget(_G, "BagBarExpandToggle")
	if type(gt) == "table" then
		fn(gt)
	end
end

local function BagsAway()
	local game = B.game
	Fade(game)
	SelectionAway(game)
	BagButtonsOf(MouseOff)
	local U = Units()
	if U then
		U.Silence(game, BAG_GAME_EVENTS, OWNER.bags, 3)
	end
end

local function BagsBack()
	local U = Units()
	if U then
		U.Unsilence(OWNER.bags)
	end
	BagButtonsOf(MouseBack)
	SelectionBack(B.game)
	Unfade(B.game)
end

local function BagsOn(db)
	if not BuildBags() then
		return false
	end
	BagsAway()
	OB.own.BagsBar = B.bar
	OB.own.MainMenuBarBagManager = BM
	OB.own.BagBarExpandToggle = B.toggle
	for name, b in pairs(B.byGame) do
		OB.own[name] = b
	end
	OB.standing.bags = true
	BagOrientation(db)
	B.bar:Show()
	B.bar:Layout()
	local anchor = (not B.bar.isHorizontal and (B.bar.direction == B.DOWN and "TOP" or "BOTTOM"))
		or (B.bar.direction == B.RIGHT and "BOTTOMLEFT" or "BOTTOMRIGHT")
	Register(B.bar, "bags", KEYS.bags, "Bags", true, anchor)
	if MelloUI.EditLayoutOptions then
		MelloUI:EditLayoutOptions(B.bar, { module = M.name, keys = { "bagVertical", "bagReverse" } })
	end
	OB.followed[B.bar] = nil
	BagsFollow()
	FollowListen()
	pcall(B.events.RegisterEvent, B.events, "EXPAND_BAG_BAR_CHANGED")
	pcall(B.events.RegisterEvent, B.events, "CURSOR_CHANGED")
	return true
end

local function BagsOff()
	OB.standing.bags = nil
	OB.own.BagsBar, OB.own.MainMenuBarBagManager, OB.own.BagBarExpandToggle = nil, nil, nil
	for name in pairs(B.byGame) do
		OB.own[name] = nil
	end
	if B.events then
		B.events:UnregisterAllEvents()
	end
	if B.bar then
		B.bar:Hide()
	end
	BagsBack()
end

--------------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------------

local PARTS = {
	{ id = "status", on = StatusOn, off = StatusOff },
	{ id = "bags", on = BagsOn, off = BagsOff },
}

local function Want()
	return MelloUI:IsModuleEnabled(M.name) and MelloUI:IsModuleEnabled("UIModifications")
end

-- every part as it should be now; told on the bus as each comes or goes. Ours standing in after the login (UI
-- Modifications switched on, or on again): a dresser may have hooked the game's bars meanwhile, which can't be taken
-- off -- a /reload asked for once (MelloUI:AskReload)
function OB.Sync(atLogin)
	local want = Want()
	for _, part in ipairs(PARTS) do
		local now = OB.standing[part.id] == true
		if want and not now then
			if not atLogin then
				MelloUI:AskReload("UI Modifications is on: type /reload to finish putting the game's bars away.")
			end
			local ok, done = pcall(part.on, M.db)
			if not ok then
				geterrorhandler()(done)
			elseif done then
				OB.stood[part.id] = true
				MelloUI:Fire("ownbars", part.id, true)
			end
		elseif not want and now then
			local ok, err = pcall(part.off)
			if not ok then
				geterrorhandler()(err)
			end
			MelloUI:Fire("ownbars", part.id, false)
		end
	end
end

local listening = false
local function ListenOnce()
	if listening then
		return
	end
	listening = true
	MelloUI:On("module", function(name)
		if name == "UIModifications" then
			OB.Sync()
		end
	end, "Own Bars: UI Modifications switched")
end

-- (fr-18 sim, 2026-11-01) the places the first build of this module wrote into the store by itself (the game's
-- place taken once, the second bar's from its unlaid default) dropped once, so ours follow the game's frames until a
-- place of their own is given: this machine's step (a keep key)
local function DropSeededPlaces(db)
	if not db or db.seedsDropped then
		return
	end
	db.seedsDropped = true
	for _, key in pairs(KEYS) do
		if MelloUI:GetPosition(key) then
			MelloUI:ForgetPosition(key)
		end
	end
end

-- (the login's own frame: ours stand in before any module dresses a bar)
function M:OnLoginFrame(db)
	self.db = db
	DropSeededPlaces(db)
	ListenOnce()
	OB.Sync(true)
end

function M:OnEnable(db)
	self.db = db
	ListenOnce()
	OB.Sync(MelloUI.ModulesStarting ~= nil and MelloUI:ModulesStarting())
end

function M:OnDisable()
	OB.Sync()
end

function M:OnSettingChanged(key, _, db)
	self.db = db
	if (key == "bagVertical" or key == "bagReverse") and OB.standing.bags then
		BagOrientation(db)
		B.bar:Layout()
		MelloUI:Fire("bagbar")
	end
end

-- /run MelloUI.OwnBars.Dump(print): what stands where
function OB.Dump(out)
	out = out or print
	out(("Own Bars: wanted %s; status %s, bags %s"):format(tostring(Want()),
		tostring(OB.standing.status == true), tostring(OB.standing.bags == true)))
	for i, c in ipairs(S.barContainers) do
		local l, b, r, t = Safe.ScreenRect(c)
		out(("  %s: shown %s, bar %s, rect %s, %s"):format(c:GetName() or ("status" .. i), tostring(c:IsShown()),
			tostring(c.shownBarIndex), l and ("%.0f,%.0f-%.0f,%.0f"):format(l, b, r, t) or "-",
			OB.followed[c] and "following the game's" or "its own place"))
	end
	if B.bar then
		local l, b, r, t = Safe.ScreenRect(B.bar)
		out(("  %s: shown %s, %d buttons, rect %s, %s"):format(B.bar:GetName() or "bags", tostring(B.bar:IsShown()), #B.buttons,
			l and ("%.0f,%.0f-%.0f,%.0f"):format(l, b, r, t) or "-", OB.followed[B.bar] and "following the game's" or "its own place"))
	end
	for f, a in pairs(OB.keptAlpha) do
		out(("  kept away: %s (alpha %.2f before)"):format(Call(f, "GetName") or tostring(f), a))
	end
end
