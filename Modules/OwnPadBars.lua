--------------------------------------------------------------------------------
-- MelloUI - Own Bars, the gamepad bars (2.1.49; docs/plans/gamepad.md; the user, 2026-11-12: "melloui action bars
-- become our custom gamepad action bars", then the picks of BuildData/output/gamepad_sketch: "3.c" (Split), "4. Yes"
-- (Bars 1-4 the pages, Bars 5-8 stay shown), "1. Your recomendation" (the face buttons with no trigger held stay the
-- game's: Jump, Back, Interact, Inspect); then, with a screenshot of these bars: "Did you see how the default action
-- bar layout looks while having gamepad on, how it animates button combinations, switchs between action bars depending
-- on the button combination, i want that" -- the Artifact "Gamepad Bars Layout", pick "A, as the game"; then, its
-- first test in game: "There is some artifacting happening while im switching the action bars, and i would also like
-- to be able to move each of those bars separatelly"; then, with a video of the game's own binding and one of
-- MelloUI's: "MelloUI Controller Keybinds ... does not work correctly", pick "The game's set")
--
-- In the game's Gamepad UI, while Own Bars' action bars stand (UI Modifications on), MelloUI shows the game's own
-- crossbar -- the controller's action set -- in its own look, laid out as the game lays it:
--   * the game's crossbar (GamepadMainActionBarFrame) does all the work: its keys (the triggers hold its bars, the
--     D-pad and the face buttons press their buttons), its three pages (L1 + D-pad left and right), Bind to Action Bar
--     and Edit Action Bars (a frame of its own), the bars that stand in for one (L1's shortcuts, the targeting bars, a
--     possess or a stance bar). It stands unseen (alpha 0, its mouse off), as the game's bars are for ours. MelloUI
--     binds none of the pad's keys (the first builds bound them to Bars 1-4: the game's binding and editing went to a
--     set MelloUI never showed -- the user's video).
--   * MelloUI's buttons (Own Bars' A.ShowButton: insecure, no clicks) show the slots the game's buttons hold where
--     they act: the middle pair under the thumbs -- the D-pad's diamond (the game's top bar's 1-4) and the face
--     buttons' (the game's own Jump, Back, Interact and Inspect: pictures); each trigger combination's bar in a cluster
--     of its own with a label of the pad's coins under it: L2 (the game's left bar), R2 (its right), L2 + R2 (its
--     bottom); a cluster is a D-pad half and a face half.
--   * the game's active bar followed (post-hooks): the held combination's cluster grows where it stands (at once: the
--     first build's picture-only grow drew the clusters from nothing -- the user's "artifacting"), its buttons' coins
--     show and its label is lit, the middle pair shrinks; a key's press shows on its button. While a bar of the game's
--     other than these four is active (L1's shortcuts, the targeting bars, the possess bar) the game's crossbar shows
--     in place of ours (its own picture of what the keys do then); while the game hides its crossbar (Edit Action Bars
--     shows a copy of its own), ours hide.
--   * the keyboard's Action Bars 1-4 stay apart, as the game's own do (hidden in the Gamepad UI, their keys kept).
--     Once per character, what Bars 1-4 held where the first build's clusters showed them (Bar 1's 1-4 on the D-pad,
--     Bars 2-4's 1-8 on L2, R2, L2 + R2) is copied into the empty slots of its first page (an action the set holds
--     already, as the game places new spells itself, not twice).
-- Five elements of Edit Layout, each moved on its own: the D-pad diamond, the face buttons, the L2, R2 and L2 + R2
-- clusters. Nothing of ours here is protected (so it follows in a fight too); built, turned on and off out of a fight
-- (Bars 1-4's visibility drivers).
--
--   OB.Pad.Holds(n) -> true while bar n stands aside for the pad bars      /run MelloUI.OwnBars.Pad.Dump(print)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local OB = MelloUI.OwnBars
local Perf = MelloUI.Perf:Scope("OwnPadBars")
local C_Timer = Perf.C_Timer
local Shared = Perf.Shared
local K = OB.kit

local pcall, type, ipairs, pairs, rawget = pcall, type, ipairs, pairs, rawget
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text
local Secret = MelloUI.Safe.IsSecret

local P = { on = false, built = false, coins = {}, labels = {}, anchors = {}, shows = {}, active = 1, turn = false }
OB.Pad = P

local PART = "actions"
local BUTTON = 45            -- the bars' button (OwnActionBars' BUTTON)
local STEP = BUTTON + 3      -- a diamond's step
-- (the sketch's, the user's pick A) the clusters' sizes: idle, held; the middle pair's while a cluster is held
local IDLE, GROWN, SHRUNK = 0.6, 0.9, 0.7
local HALFX = 72             -- a cluster's D-pad half and face half from its middle
local LABEL_SIDE = 68        -- a side cluster's label under its middle
local LABEL_BELOW = 75       -- the L2 + R2 cluster's
local COPY_DELAY = 3         -- (s) the one copy waits so long after the bars come (the action slots read by then)
-- a diamond's places: 1 up, 2 right, 3 down, 4 left
local function Spot(k, step)
	if k == 1 then
		return 0, step * 0.82
	elseif k == 2 then
		return step * 0.92, 0
	elseif k == 3 then
		return 0, -step * 0.82
	end
	return -step * 0.92, 0
end
local DIAMOND_W, DIAMOND_H = 2 * (STEP * 0.92 + BUTTON / 2), 2 * (STEP * 0.82 + BUTTON / 2)

-- the five elements (Edit Layout's, each its own place): their key, name, home (the first build's layout: the middle
-- pair 318 above the screen's bottom middle, the side clusters beside it, L2 + R2 under it), size (a cluster's: held)
local ELEMENTS = {
	{ id = "dpad", bar = 1, key = "MelloUIPadBarsDpad", label = "Gamepad D-pad", x = -200, y = 318,
		w = DIAMOND_W, h = DIAMOND_H },
	{ id = "face", key = "MelloUIPadBarsFace", label = "Gamepad Face Buttons", x = 200, y = 318,
		w = DIAMOND_W, h = DIAMOND_H },
	{ id = "l2", bar = 2, key = "MelloUIPadBarsL2", label = "Gamepad L2 Bar", x = -392, y = 318,
		w = (2 * HALFX + DIAMOND_W) * GROWN, h = DIAMOND_H * GROWN, coins = { "PADLTRIGGER" }, labelY = -LABEL_SIDE },
	{ id = "r2", bar = 3, key = "MelloUIPadBarsR2", label = "Gamepad R2 Bar", x = 392, y = 318,
		w = (2 * HALFX + DIAMOND_W) * GROWN, h = DIAMOND_H * GROWN, coins = { "PADRTRIGGER" }, labelY = -LABEL_SIDE },
	{ id = "both", bar = 4, key = "MelloUIPadBarsL2R2", label = "Gamepad L2 + R2 Bar", x = 0, y = 187,
		w = (2 * HALFX + DIAMOND_W) * GROWN, h = DIAMOND_H * GROWN, coins = { "PADLTRIGGER", "PADRTRIGGER" },
		labelY = -LABEL_BELOW },
}
P.ELEMENTS = ELEMENTS

-- a cluster's size with cluster `held` held (1: none)
local function ScaleOf(n, held)
	if n == 1 then
		return held == 1 and 1 or SHRUNK
	end
	return n == held and GROWN or IDLE
end
P.ScaleOf = ScaleOf

-- the pad's keys for the eight slots: the D-pad's (up, right, down, left), then the face buttons' (Y, B, A, X)
local KEYS = { "PADDUP", "PADDRIGHT", "PADDDOWN", "PADDLEFT", "PAD4", "PAD2", "PAD1", "PAD3" }
P.KEYS = KEYS

-- the game's four pageable bars, as our clusters: 1 its top bar (no trigger), 2 its left (L2), 3 its right (R2), 4
-- its bottom (both) -- Blizzard_GamepadActionBars/PageUnit.lua, ActionBarModKeyDownStateCheck
local GAME_BARS = { "topBar", "leftBar", "rightBar", "bottomBar" }
-- the game's index (its GAMEPADACTIONBUTTON1-8, a bar's actionButtons) of each of our eight slots when its own
-- bindings cannot tell: its slot map (ActionBindingUtil.lua): 1 left, 2 up, 3 right, 4 down, 5 X, 6 Y, 7 B, 8 A
local GAME_INDEX = { 2, 3, 4, 1, 6, 7, 8, 5 }
P.GAME_INDEX = GAME_INDEX
local PAGES, PAGE_SLOTS = 3, 32   -- the crossbar's standard pages, the slots of a page (4 of each 8 of its top bar its own)

-- the game's own fixed actions on the face buttons with no trigger held (its crossbar's, in the face diamond's places)
local FACE = {
	{ key = "PAD4", atlas = "crosshair_inspect_32" },            -- Y: Inspect
	{ key = "PAD2", atlas = "128-redbutton-exit" },              -- B: Back
	{ key = "PAD1", atlas = "gamepad-ability-icon-jump" },       -- A: Jump
	{ key = "PAD3", file = "Interface\\Cursor\\Interact" },      -- X: Interact
}

local TEXT = {
	copied = "Your Action Bars 1-4 were copied to the controller's action bars.",
	bindAsk = "Press the button combination for %s.\nHold %s, %s or both for their bars; %s alone cancels.",
	bindOwn = "That button is the game's own there (Jump, Back, Interact or Inspect): hold a trigger for its bars.",
	bound = "%s is on %s.",
	bindFailed = "The game did not take that item on the controller's bars.",
	bindFight = "The controller's bars cannot change in a fight.",
}

--------------------------------------------------------------------------------
-- The game's crossbar (read only: its fields, its own reckoning)
--------------------------------------------------------------------------------

local function Crossbar()
	return rawget(_G, "GamepadMainActionBarFrame")
end

local function PageUnit()
	local pu = K.Field(Crossbar(), "PageUnit")
	return type(pu) == "table" and pu or nil
end

local function GameBar(n)
	local bars = K.Field(PageUnit(), "actionBars")
	local bar = type(bars) == "table" and rawget(bars, GAME_BARS[n])
	return type(bar) == "table" and bar or nil
end

-- the game's page now (1-3; 4 its special page)
local function Page()
	return Num(K.Field(K.Field(PageUnit(), "PageTracker"), "currentPage"))
end

-- our slot -> the game's index, read from its own bindings (a key off the pad's eight, or one of ours unbound: its
-- slot map)
local function IndexMap()
	local map = {}
	for k = 1, 8 do
		local ok, key = pcall(GetBindingKey, "GAMEPADACTIONBUTTON" .. k)
		key = ok and Text(key) or nil
		for i = 1, 8 do
			if KEYS[i] == key and not map[i] then
				map[i] = k
			end
		end
	end
	for i = 1, 8 do
		if not map[i] then
			return GAME_INDEX
		end
	end
	return map
end

-- the cluster the game's active bar is (1-4), and whether it is a bar of another kind (the game's turn to show)
local function ActiveBar()
	local active = K.Field(PageUnit(), "activeBar")
	if type(active) ~= "table" then
		return 1, false
	end
	for n = 1, 4 do
		if active == GameBar(n) then
			return n, false
		end
	end
	return 1, true
end

-- the game's storage slot of a page's slot (its own reckoning; nil for a slot of its own)
local function Storage(page, slot)
	local util = rawget(_G, "GamepadActionBarBindingUtil")
	local fn = type(util) == "table" and rawget(util, "GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID")
	if type(fn) ~= "function" then
		return nil
	end
	local ok, s = pcall(fn, page, slot)
	return ok and Num(s) or nil
end

-- a slot holds an action: true, false, or nil (unreadable)
local function Has(slot)
	local fn = rawget(_G, "HasAction")
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, slot)
	if not ok or Secret(v) then
		return nil
	end
	return v and true or false
end

--------------------------------------------------------------------------------
-- The look: the face diamond's slots (pictures of the game's actions), the clusters' labels, the held one lit
--------------------------------------------------------------------------------

local function SlotFrame(parent, size)
	local W = MelloUI.Widgets
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	f:EnableMouse(false)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(f)
	W.Paint(bg, "innerPanel", "fill", 0.85)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
	f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
	W.Edges(f, "border", "OVERLAY")
	return f
end

-- a cluster's label: the pad's coins of its combination ("L2", "R2", "L2 + R2") under it, a steady glow round each,
-- lit while held (made at the build, on its anchor)
local function Label(el)
	local G, W = MelloUI.Gamepad, MelloUI.Widgets
	local a = P.anchors[el.id]
	local f = CreateFrame("Frame", nil, a)
	f:SetSize(1, 1)
	f:SetPoint("CENTER", a, "CENTER", 0, el.labelY)
	f:SetFrameLevel(a:GetFrameLevel() + 5)
	f:EnableMouse(false)
	f.coins, f.glows = {}, {}
	local plus
	if #el.coins == 2 then
		plus = W.Text(f, "GameFontHighlight", "+", "text")
		plus:SetPoint("CENTER", f, "CENTER", 0, 0)
	end
	for i, key in ipairs(el.coins) do
		local c = G.Coin()
		c:SetParent(f)
		c:SetFrameLevel(f:GetFrameLevel() + 2)
		if not plus then
			c:SetPoint("CENTER", f, "CENTER", 0, 0)
		elseif i == 1 then
			c:SetPoint("RIGHT", plus, "LEFT", -3, 0)
		else
			c:SetPoint("LEFT", plus, "RIGHT", 3, 0)
		end
		G.SetCoin(c, key)
		c:Show()
		f.coins[i] = c
		local glow = MelloUI.Shade:Glow(f, { region = c, size = 36, strength = "reach" })
		glow:Still()
		f.glows[i] = glow
	end
	P.labels[el.bar] = f
end

-- a pad button's coin (the pad's button for it, where its key's number would be)
local function Coin(btn, key)
	local G = MelloUI.Gamepad
	local coin = G.Coin()
	coin:SetParent(btn)
	coin:SetPoint("CENTER", btn, "TOPRIGHT", -6, -6)
	coin:SetFrameLevel(btn:GetFrameLevel() + 5)
	G.SetCoin(coin, key)
	P.coins[btn] = coin
end

-- the coins where they act (the middle pair always, a cluster's while it is held: fitted again for their size now),
-- the held cluster's label lit
local function Lit()
	local G = MelloUI.Gamepad
	local held = P.active
	for n = 1, 4 do
		for _, btn in ipairs(P.shows[n] or {}) do
			local coin = P.coins[btn]
			if coin then
				if P.on and (n == 1 or n == held) then
					G.SetCoin(coin, coin.key)
					coin:Show()
				else
					coin:Hide()
				end
			end
		end
	end
	for _, s in ipairs(P.faceSlots or {}) do
		G.SetCoin(s.coin, s.coin.key)
	end
	for n, label in pairs(P.labels) do
		for _, glow in ipairs(label.glows) do
			glow:SetShown(P.on and n == held)
		end
	end
end

-- the sizes: the held cluster grown, the rest small, the middle pair shrunk while one is held (a button's offset is in
-- its own units: it stands nearer its anchor's middle as it shrinks)
local function Layout()
	local held = P.active
	for n = 1, 4 do
		local s = ScaleOf(n, held)
		for _, btn in ipairs(P.shows[n] or {}) do
			btn:SetScale(s)
		end
	end
	if P.face then
		P.face:SetScale(ScaleOf(1, held))
	end
	Lit()
end

--------------------------------------------------------------------------------
-- Following the game's crossbar (its post-hooks; a fight too: nothing of ours here is protected)
--------------------------------------------------------------------------------

-- each of our buttons shows the slot the game's button holds where it acts
local function Mirror()
	local map = P.map or GAME_INDEX
	local changed = false
	for n = 1, 4 do
		local list = K.Field(GameBar(n), "actionButtons")
		for i, btn in ipairs(P.shows[n] or {}) do
			local g = type(list) == "table" and list[map[i]] or nil
			local a = Num(K.Field(g, "action"))
			if a and a <= 0 then
				a = nil
			end
			if btn.slot ~= a or not btn.mirrored then
				btn.slot = a
				btn.mirrored = true
				btn:UpdateAction(true)
				changed = true
			end
		end
	end
	if changed then
		MelloUI:Fire("ownbars:padslots")
	end
end

-- ours shown (the game's crossbar shown, one of its four bars active) or the game's (another bar of its active)
local function Apply()
	local h = P.header
	if not h then
		return
	end
	local cb = Crossbar()
	local shown = P.on and cb ~= nil and cb:IsShown() and not P.turn
	h:SetShown(shown and true or false)
	if P.on and cb then
		if P.turn then
			K.Unfade(cb)
		else
			K.Fade(cb)
		end
	end
end

local function Track()
	if not P.on then
		return
	end
	P.active, P.turn = ActiveBar()
	Mirror()
	Layout()
	Apply()
end
P.Track = Track

local Track_Post = Shared("the game's crossbar changed (the gamepad bars follow it)", Track)

-- a key on the game's crossbar: its press shown on ours
local Press_Post = Shared("a key on the game's crossbar (shown on the gamepad bars)", function(_, index, _, down)
	if not P.on or P.turn then
		return
	end
	local i = P.ours and P.ours[Num(index) or 0]
	local list = P.shows[P.active]
	local btn = i and list and list[i]
	if btn then
		btn:SetButtonState(down and "PUSHED" or "NORMAL")
	end
end)

-- the post-hooks (once, while the game's crossbar is there; its methods its own fields, as its mixins lay them)
local function Hook()
	if P.hooked then
		return true
	end
	local cb, pu = Crossbar(), PageUnit()
	if not (type(K.Field(pu, "SetActiveActionBar")) == "function" and type(K.Field(pu, "OnPageChange")) == "function"
		and type(K.Field(cb, "PressActionButton")) == "function") then
		return false
	end
	P.hooked = true
	Perf.hooksecurefunc(pu, "SetActiveActionBar", Track_Post)
	Perf.hooksecurefunc(pu, "OnPageChange", Track_Post)
	Perf.hooksecurefunc(cb, "PressActionButton", Press_Post)
	Perf.HookScript(cb, "OnShow", Track_Post)
	Perf.HookScript(cb, "OnHide", Track_Post)
	return true
end

--------------------------------------------------------------------------------
-- Building (out of a fight, the first time the pad bars come on)
--------------------------------------------------------------------------------

local function Live()
	return P.on
end

-- an element's home (its default and its reset)
local function Homes()
	local homes = {}
	for _, el in ipairs(ELEMENTS) do
		homes[el.id] = function(frame)
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", UIParent, "BOTTOM", el.x, el.y)
		end
	end
	return homes
end

-- a cluster's anchor (cluster 1: the D-pad's)
local function AnchorOf(n)
	for _, el in ipairs(ELEMENTS) do
		if el.bar == n then
			return P.anchors[el.id]
		end
	end
	return nil
end

local function Build()
	if P.built then
		return true
	end
	if InCombatLockdown() then
		return false
	end
	local A = OB.Actions
	local G = MelloUI.Gamepad
	-- (every pad button in actionButtons: what dresses the bars finds them by this name -- ActionButtons, the
	-- Oldschool skin; empty slots seen, the plain slot, as the game's crossbar shows its own)
	local h = CreateFrame("Frame", "MelloUIPadBars", UIParent)
	h:SetSize(1, 1)
	h:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
	h:SetFrameStrata("MEDIUM")
	h:Hide()
	h.actionButtons = {}
	P.header = h
	-- the five elements: an anchor each, its own place in Edit Layout
	local homes = Homes()
	for _, el in ipairs(ELEMENTS) do
		local a = CreateFrame("Frame", el.key, h)
		a:SetSize(el.w, el.h)
		a:EnableMouse(false)
		a.showGrid, a.hideBarArt = true, true
		homes[el.id](a)
		P.anchors[el.id] = a
		el.mover = MelloUI:RegisterMover(a, a, { key = el.key, group = "hud", label = el.label, category = "bars",
			default = homes[el.id], reset = homes[el.id], when = Live })
	end
	-- the pad buttons: about their cluster's middle at full size (the D-pad's diamond alone; a cluster's D-pad half
	-- and face half)
	for n = 1, 4 do
		local a = AnchorOf(n)
		local list = {}
		for i = 1, (n == 1 and 4 or 8) do
			local btn = A.ShowButton(a, "MelloUIPadBar" .. n .. "Button" .. i)
			if btn then
				local x, y = Spot(((i - 1) % 4) + 1, STEP)
				if n > 1 then
					x = x + (i <= 4 and -HALFX or HALFX)
				end
				btn:SetPoint("CENTER", a, "CENTER", x, y)
				btn:SetFrameLevel(a:GetFrameLevel() + 2)
				Coin(btn, KEYS[i])
				list[#list + 1] = btn
				h.actionButtons[#h.actionButtons + 1] = btn
			end
		end
		P.shows[n] = list
	end
	-- the face diamond's game actions
	local fa = P.anchors.face
	local face = CreateFrame("Frame", nil, fa)
	face:SetSize(DIAMOND_W, DIAMOND_H)
	face:SetPoint("CENTER", fa, "CENTER", 0, 0)
	P.faceSlots = {}
	for k, act in ipairs(FACE) do
		local s = SlotFrame(face, BUTTON)
		local x, y = Spot(k, STEP)
		s:SetPoint("CENTER", face, "CENTER", x, y)
		if act.atlas then
			pcall(s.icon.SetAtlas, s.icon, act.atlas)
		else
			pcall(s.icon.SetTexture, s.icon, act.file)
		end
		local coin = G.Coin()
		coin:SetParent(s)
		coin:SetPoint("CENTER", s, "TOPRIGHT", -6, -6)
		coin:SetFrameLevel(s:GetFrameLevel() + 5)
		G.SetCoin(coin, act.key)
		coin:Show()
		s.coin = coin
		P.faceSlots[k] = s
	end
	P.face = face
	-- the clusters' labels
	for _, el in ipairs(ELEMENTS) do
		if el.coins then
			Label(el)
		end
	end
	P.built = true
	-- (the bars' dressers, told as when Own Bars' action bars come: these buttons are of that part)
	MelloUI:Fire("ownbars", PART, true)
	return true
end

--------------------------------------------------------------------------------
-- The keyboard's Bars 1-4 aside (out of a fight; OwnActionBars' UpdateGridLayout asks after each lay)
--------------------------------------------------------------------------------

function P.Holds(n)
	return P.on and type(n) == "number" and n >= 1 and n <= 4
end

function P.LayBar(bar)
	if not (P.on and bar) or InCombatLockdown() then
		return
	end
	RegisterStateDriver(bar, "visibility", "hide")
end

--------------------------------------------------------------------------------
-- The one copy: Bars 1-4 into the controller's set, once per character (out of a fight; only by id from the
-- spellbook, the bags and the macros, only into a slot empty that moment: nothing of the player's is ever taken off a
-- bar or lost)
--------------------------------------------------------------------------------

local function Pickup(kind, id)
	local fn
	if kind == "spell" then
		local spell = rawget(_G, "C_Spell")
		fn = (type(spell) == "table" and spell.PickupSpell) or rawget(_G, "PickupSpell")
	elseif kind == "item" then
		fn = (C_Item and C_Item.PickupItem) or rawget(_G, "PickupItem")
	elseif kind == "macro" then
		fn = rawget(_G, "PickupMacro")
	elseif kind == "equipmentset" then
		local sets = rawget(_G, "C_EquipmentSet")
		fn = type(sets) == "table" and sets.PickupEquipmentSet
	end
	if type(fn) == "function" then
		pcall(fn, id)
	end
end

-- an action's kind and id ("spell:6673"), nil while unreadable
local function ActionKey(slot)
	local ok, kind, id = pcall(GetActionInfo, slot)
	if not ok or Secret(kind) or Secret(id) or kind == nil or id == nil then
		return nil
	end
	return tostring(kind) .. ":" .. tostring(id), kind, id
end

-- this character's own key (its GUID; nil while unreadable): the copy is once per character (the profile may be
-- another's: each character's mark kept under its own key, as Action Bars keeps its Edit Mode records)
local function CharKey()
	local ok, guid = pcall(UnitGUID, "player")
	if not ok or Secret(guid) or type(guid) ~= "string" or guid == "" then
		return nil
	end
	return "char_" .. (guid:gsub("[^%w]", ""))
end

-- this character's copy done (true / false; nil: unreadable), or marked done (`mark`)
local function Copied(mark)
	local db = OB.module and OB.module.db
	local key = CharKey()
	if not (db and key) then
		return nil
	end
	if mark then
		if type(db.padCopied) ~= "table" then
			db.padCopied = {}
		end
		db.padCopied[key] = true
		return true
	end
	return type(db.padCopied) == "table" and db.padCopied[key] == true
end

-- (the user's first test, 2026-11-12: "the keybinding is actually missing the actual keybinds" -- the game had put a
-- few spells on its set itself, so the first build's "only an empty set" never copied) once per character: every
-- empty slot of page 1 where the first build showed a Bars 1-4 button gets that button's action, unless the set
-- holds that action already somewhere (the game places new spells itself: never twice). `again` (/run
-- MelloUI.OwnBars.Pad.CopyOnce(true)): once more, the empty slots only.
function P.CopyOnce(again)
	if (P.copyTried and not again) or not P.on or GetCursorInfo() then
		return
	end
	if InCombatLockdown() then
		MelloUI.Schedule.WhenOutOfCombat(function()
			P.CopyOnce(again)
		end, "Own Bars: the gamepad bars' one copy")
		return
	end
	if not Storage(1, 1) then
		return
	end
	local done = Copied()
	if done == nil or (done and not again) then
		P.copyTried = true
		return
	end
	P.copyTried = true
	-- what the set holds already
	local held = {}
	for page = 1, PAGES do
		for slot = 1, PAGE_SLOTS do
			local s = Storage(page, slot)
			if s and Has(s) then
				local key = ActionKey(s)
				if key then
					held[key] = true
				end
			end
		end
	end
	local A = OB.Actions
	local map = P.map or GAME_INDEX
	local copied = 0
	for n = 1, 4 do
		local bar = A.bars[n]
		for i = 1, (n == 1 and 4 or 8) do
			local btn = bar and bar.actionButtons[i]
			local from = btn and Num(btn.action)
			local to = Storage(1, (n - 1) * 8 + map[i])
			if from and to and Has(from) and Has(to) == false then
				local key, kind, id = ActionKey(from)
				if key and not held[key] then
					Pickup(kind, id)
					if GetCursorInfo() then
						pcall(rawget(_G, "PlaceAction"), to)
						if Has(to) then
							copied = copied + 1
							held[key] = true
						end
					end
					ClearCursor()
				end
			end
		end
	end
	Copied(true)
	P.copied = copied
	if copied > 0 then
		MelloUI:Announce(TEXT.copied, "info")
	end
end

--------------------------------------------------------------------------------
-- Bind to Action Bar (2.1.49; the user: "how to people bind items from inventory to the action bar", then "Yes, as
-- the game"): the bag window's Y > Bind to Action Bar. The game's own (GamepadActionBarEditFrame:BindItem) is its frame
-- manager's and its edit frame's code -- called from MelloUI it would run tainted through them (the 0.15.0 freeze's
-- kind) -- so MelloUI asks with its own question (MelloUI:Confirm, answered by the pad's buttons) and places the item
-- as the game's own util does (C_Item.PickupItem, PlaceAction) into the slot of the combination pressed: the triggers
-- held (the keys of the game's GAMEPADLEFTMOD / GAMEPADRIGHTMOD: its bars), the key (its index), the game's page. A
-- slot holding something: replaced, as the game's Bind replaces it. Out of a fight.
--------------------------------------------------------------------------------

local BIND_KEYS = {}   -- the question's keys: each of the eight pad keys under its own name
for i, key in ipairs(KEYS) do
	BIND_KEYS[key] = "SLOT" .. i
end

local function KeyDown(key)
	local fn = rawget(_G, "IsKeyDown")
	if type(key) ~= "string" or type(fn) ~= "function" then
		return false
	end
	local ok, down = pcall(fn, key)
	return ok and down == true
end

-- a binding held, as the game reads its own (GamepadMode.IsBindingDown: its keys down); its default key unbound
local function Held(command, fallback)
	local ok, k1, k2 = pcall(GetBindingKey, command)
	k1, k2 = ok and Text(k1) or nil, ok and Text(k2) or nil
	if k1 or k2 then
		return KeyDown(k1) or KeyDown(k2)
	end
	return KeyDown(fallback)
end

-- a pad key's name as the pad's own labels say it (MelloUI.Gamepad's faces)
local DPAD_NAMES = { PADDUP = "D-pad Up", PADDRIGHT = "D-pad Right", PADDDOWN = "D-pad Down", PADDLEFT = "D-pad Left" }
local function KeyName(key)
	if DPAD_NAMES[key] then
		return DPAD_NAMES[key]
	end
	local G = MelloUI.Gamepad
	local faces = G and G.FACES and G.FACES[G.Style and G.Style() or "Letters"] or nil
	local name = faces and faces[key] or key
	if name:sub(1, 1) == "@" then
		name = name:sub(2, 2):upper() .. name:sub(3)
	end
	return name
end

local function Combo(lt, rt, key)
	local parts = {}
	if lt then
		parts[#parts + 1] = KeyName("PADLTRIGGER")
	end
	if rt then
		parts[#parts + 1] = KeyName("PADRTRIGGER")
	end
	parts[#parts + 1] = KeyName(key)
	return table.concat(parts, " + ")
end

-- the question's answer to a key of the eight: the item placed in that combination's slot ("done"), B alone
-- ("cancel"), a slot of the game's own (asked on)
local function BindPress(item, name, i)
	local lt = Held("GAMEPADLEFTMOD", "PADLTRIGGER")
	local rt = Held("GAMEPADRIGHTMOD", "PADRTRIGGER")
	local bar = (lt and rt) and 4 or lt and 2 or rt and 3 or 1
	local page = Page()
	if not page or page > PAGES then
		page = 1
	end
	local map = P.map or IndexMap()
	local slot = Storage(page, (bar - 1) * 8 + map[i])
	if not slot then
		if KEYS[i] == "PAD2" then
			return "cancel"
		end
		MelloUI:Announce(TEXT.bindOwn, "info")
		return nil
	end
	if InCombatLockdown() then
		MelloUI:Announce(TEXT.bindFight, "info")
		return "cancel"
	end
	ClearCursor()
	local I = rawget(_G, "C_Item")
	local pick = (type(I) == "table" and I.PickupItem) or rawget(_G, "PickupItem")
	if type(pick) == "function" then
		pcall(pick, item)
	end
	if not GetCursorInfo() then
		MelloUI:Announce(TEXT.bindFailed, "info")
		return "cancel"
	end
	pcall(rawget(_G, "PlaceAction"), slot)
	ClearCursor()   -- (what the slot held, replaced)
	if ActionKey(slot) == "item:" .. item then
		MelloUI:Announce(TEXT.bound:format(name, Combo(lt, rt, KEYS[i])), "info")
		return "done"
	end
	MelloUI:Announce(TEXT.bindFailed, "info")
	return "cancel"
end
P.BindPress = BindPress

-- asked for an item (its id, its link for the question); false when the game has no controller bars or in a fight
function P.BindItem(item, link)
	item = Num(item)
	if not item or not PageUnit() or InCombatLockdown() then
		return false
	end
	local name = link or ("item " .. item)
	MelloUI:Confirm({
		text = TEXT.bindAsk:format(name, KeyName("PADLTRIGGER"), KeyName("PADRTRIGGER"), KeyName("PAD2")),
		pad = { keys = BIND_KEYS, press = function(key, down)
			local i = down and tonumber(tostring(key):match("^SLOT(%d)$"))
			if not i then
				return nil
			end
			return BindPress(item, name, i)
		end },
	})
	return true
end

--------------------------------------------------------------------------------
-- On and off
--------------------------------------------------------------------------------

local function On()
	if not (Hook() and Build()) then
		return false
	end
	P.on = true
	P.map = IndexMap()
	P.ours = {}
	for i, k in ipairs(P.map) do
		P.ours[k] = i
	end
	local A = OB.Actions
	for n = 1, 4 do
		P.LayBar(A.bars[n])
	end
	local cb = Crossbar()
	K.MouseOff(cb)
	Track()
	C_Timer.After(COPY_DELAY, P.CopyOnce)
	return true
end

local function Off()
	P.on = false
	P.turn = false
	local h = P.header
	if not h then
		return
	end
	h:Hide()
	Lit()
	local cb = Crossbar()
	if cb then
		K.Unfade(cb)
		K.MouseBack(cb)
	end
	-- (Bars 1-4 laid as their own settings say again: their visibility)
	if OB.On(PART) then
		local A = OB.Actions
		for n = 1, 4 do
			A.Lay(n)
		end
	end
end

local function Want()
	local G = MelloUI.Gamepad
	local A = OB.Actions
	return G ~= nil and G.On() and OB.On(PART) and A ~= nil and A.bars[4] ~= nil and A.ShowButton ~= nil
		and PageUnit() ~= nil
end

function P.Sync()
	local want = Want() and true or false
	if want == P.on then
		return
	end
	if InCombatLockdown() then
		MelloUI.Schedule.WhenOutOfCombat(P.Sync, "Own Bars: the gamepad bars")
		return
	end
	if want then
		On()
	else
		Off()
	end
end

MelloUI:On("gamepad", function()
	P.Sync()
end, "Own Bars: the gamepad bars (the mode)")
MelloUI:On("ownbars", function(part)
	if part == PART then
		C_Timer.After(0, P.Sync)
	end
end, "Own Bars: the gamepad bars (the action bars came or went)")

--------------------------------------------------------------------------------
-- /run MelloUI.OwnBars.Pad.Dump(print)
--------------------------------------------------------------------------------

function P.Dump(out)
	out = out or print
	local cb = Crossbar()
	out(("Gamepad bars: on %s, held %s, the game's turn %s, the game's page %s, its crossbar %s"):format(tostring(P.on),
		tostring(P.active), tostring(P.turn), tostring(Page()),
		cb and ("shown " .. tostring(cb:IsShown()) .. " at alpha " .. tostring(cb:GetAlpha())) or "absent"))
	local map = P.map or GAME_INDEX
	local idx = {}
	for i = 1, 8 do
		idx[i] = KEYS[i] .. "=" .. tostring(map[i])
	end
	out("  our slots -> the game's index: " .. table.concat(idx, " ")
		.. (P.map and P.map ~= GAME_INDEX and " (its bindings)" or " (its slot map)"))
	for n = 1, 4 do
		local slots = {}
		for i, btn in ipairs(P.shows[n] or {}) do
			slots[i] = tostring(btn.slot or "-") .. (btn.hasAction and "" or "(empty)")
		end
		out(("  %s: %s"):format(GAME_BARS[n], table.concat(slots, " ")))
	end
	for _, el in ipairs(ELEMENTS) do
		local a = P.anchors[el.id]
		local x, y
		if a then
			x, y = a:GetCenter()
		end
		out(("  %s: its middle at %s, %s"):format(el.label, x and ("%.0f"):format(x) or "-", y and ("%.0f"):format(y) or "-"))
	end
	out(("  the one copy: tried %s, %s slots copied"):format(tostring(P.copyTried and true or false), tostring(P.copied or 0)))
	for k = 1, 8 do
		local ok, key = pcall(GetBindingKey, "GAMEPADACTIONBUTTON" .. k)
		out(("  GAMEPADACTIONBUTTON%d <- %s"):format(k, tostring(ok and key or "?")))
	end
end
