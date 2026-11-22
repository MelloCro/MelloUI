--------------------------------------------------------------------------------
-- MelloUI - Loot All Key (2.1.68; a player on Discord, "Keybind to 'loot All'": "a specific key to loot all when the
-- loot window is open. I have E as a keybind, but when loot window is open with Plumber addon installed, E changes to
-- Loot All. The reason this is handy is because sometimes you wanna see what the Mob has before you commit to loot it
-- all")
--
-- While a loot window is open, one key takes everything in it; once the window closes, the key does what it did.
--   The key     the game's Interact key (both keys of INTERACTTARGET, read as each window opens: a key changed in the
--               game's Key Bindings is the one used), or one picked here. Keyboard and mouse keys only: a pad's
--               buttons stay the game's and MelloUI.Gamepad's.
--   A press     every slot taken (LootSlot), the last first. Left alone: a slot the game holds back (locked: an item
--               being rolled for, an item that is the loot master's to give) and, while you are the loot master, every
--               item at or over the loot threshold (yours to hand out: Roll / Assign on the Loot Rolls window, or the
--               game's own menu). A bind-on-pickup item still asks first: the game's own question, never answered here
--               (ConfirmLootSlot is never called). One take a press: the key's release takes nothing more.
--   A fight     the game lets no addon change a key in a fight (the override bindings are protected then). So the key
--               is let go as a fight starts (PLAYER_REGEN_DISABLED: still allowed then, as MelloUI.Gamepad's Release);
--               a window opened in a fight leaves the key its own job, and the key takes over as the fight ends with
--               the window still open. The window's own clicks work as always meanwhile.
-- How: a priority override binding of the key to a plain button of MelloUI's (MelloUILootAllKey, its own owner) while
-- a window is open, cleared as it closes. The window itself is never touched, so the key works whichever loot window
-- shows: the game's (in every look: Oldschool's LootPanel dresses it, the others leave it the game's) or another
-- addon's.
-- Off by default (no binding and no event until it is switched on: Windows > Loot windows); the button is made at
-- the first window opened with it on.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("LootAllKey")
local Safe = MelloUI.Safe
local Secret, Num = Safe.IsSecret, Safe.Number
local Shared = Perf.Shared

local M = MelloUI:RegisterModule("LootAllKey", {
	title = "Loot All Key",
	desc = "While a loot window is open, your Interact key takes everything in it at once, then goes back to its own job. Not in a fight: the game lets no addon change a key then.",
	icon = "Interface\\Icons\\INV_Misc_Bag_10",
	flavour = "See what it dropped, then take it all with one key.",
	enabledByDefault = false,
	defaults = {
		key = "interact",
	},
	options = {
		{ type = "dropdown", key = "key", name = "Which Key",
		  desc = "The key that takes everything while a loot window is open: your Interact key (as set in the game's Key Bindings), or one of these. In a fight the key keeps its own job; it takes over again once the fight ends.",
		  values = { { value = "interact", label = "Your Interact Key" }, { value = "E", label = "E" },
			{ value = "F", label = "F" }, { value = "R", label = "R" }, { value = "Q", label = "Q" },
			{ value = "G", label = "G" }, { value = "T", label = "T" }, { value = "SPACE", label = "Space" } } },
	},
})
MelloUI.LootAllKey = M

-- (one table: the file's state and parts, no file local spent on each)
local K = {
	NAME = "MelloUILootAllKey",   -- the button the key clicks (its binding names it)
	open = false,                 -- a loot window open now (LOOT_OPENED .. LOOT_CLOSED)
	bound = false,                -- the key bound to the button now
}
M.K = K   -- (for its test)

local function Answer(ok, ...)
	if not ok then
		return nil
	end
	return ...
end

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	return Answer(pcall(fn, ...))
end

local function Fighting()
	return Call(InCombatLockdown) and true or false
end

--------------------------------------------------------------------------------
-- The key
--------------------------------------------------------------------------------

-- a key a pad's button names ("PAD1", "SHIFT-PADLSHOULDER"); a keyboard's NUMPAD keys are not
local function PadKey(key)
	local base = key:match("([^%-]+)$") or key
	return base:sub(1, 3) == "PAD"
end

-- the keys that take the loot now: the Interact binding's two, or the one picked
function K.Keys()
	local list = {}
	local pick = M.db and M.db.key or "interact"
	local a, b
	if pick == "interact" then
		a, b = Call(GetBindingKey, "INTERACTTARGET")
	else
		a = pick
	end
	for _, key in ipairs({ a or false, b or false }) do
		if key and not Secret(key) and type(key) == "string" and key ~= "" and not PadKey(key) then
			list[#list + 1] = key
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- The take
--------------------------------------------------------------------------------

-- true while you are the loot master (MelloUI.LootRollWindow's one reader of it)
local function Master()
	local R = MelloUI.LootRollWindow
	if not (R and type(R.Looter) == "function") then
		return false
	end
	local ok, name, me = pcall(R.Looter)
	return ok and name ~= nil and me == true
end

-- every slot the loot lets you take, taken; how many were asked for
function K.TakeAll()
	local n = Num(Call(GetNumLootItems)) or 0
	if n <= 0 then
		return 0
	end
	local kinds = Enum and Enum.LootSlotType
	local NONE, ITEM = kinds and kinds.None or 0, kinds and kinds.Item or 1
	local master = Master()
	local threshold = master and (Num(Call(_G.GetLootThreshold)) or 2) or nil
	local taken = 0
	for slot = n, 1, -1 do
		local kind = Num(Call(GetLootSlotType, slot))
		if kind and kind ~= NONE then
			local _, _, _, _, quality, locked = Call(GetLootSlotInfo, slot)
			-- (held back: locked by the game -- a secret answer counts as locked -- or the loot master's to give)
			local held = Secret(locked) or locked == true
			if not held and master and kind == ITEM then
				quality = Num(quality)
				held = quality == nil or quality >= threshold
			end
			if not held and pcall(_G.LootSlot, slot) then
				taken = taken + 1
			end
		end
	end
	return taken
end

--------------------------------------------------------------------------------
-- The binding
--------------------------------------------------------------------------------

local Bind, Unbind

-- (a press and its release each click it, a client that sends both; one take a press)
local Button_OnClick = Shared("OnClick on the Loot All Key's button", function(_, _, down)
	if down == false and K.pressed then
		K.pressed = nil
		return
	end
	K.pressed = down == true or nil
	if not K.open then
		Unbind()
		return
	end
	K.TakeAll()
end, "script")

function K.Button()
	local b = K.button
	if b then
		return b
	end
	-- (never drawn and never under the mouse: only its binding clicks it; shown, so a click reaches it)
	b = CreateFrame("Button", K.NAME, UIParent)
	b:SetSize(1, 1)
	b:SetAlpha(0)
	b:EnableMouse(false)
	b:RegisterForClicks("AnyDown", "AnyUp")
	Perf.SetScript(b, "OnClick", Button_OnClick)
	K.button = b
	return b
end

-- the key bound while a window is open (never in a fight)
function Bind()
	if K.bound or not K.open or Fighting() then
		return
	end
	local keys = K.Keys()
	if #keys == 0 then
		return
	end
	local b = K.Button()
	for _, key in ipairs(keys) do
		pcall(SetOverrideBindingClick, b, true, key, K.NAME, "LeftButton")
	end
	K.bound = true
end

-- let go; `starting`: a fight starting (PLAYER_REGEN_DISABLED, still allowed then). In a fight otherwise it stays
-- until the fight ends (PLAYER_REGEN_ENABLED lets go)
function Unbind(starting)
	if not K.bound or (Fighting() and not starting) then
		return
	end
	pcall(ClearOverrideBindings, K.button)
	K.bound = false
end

--------------------------------------------------------------------------------
-- Events: the loot window's while the module is on; a fight's while a window is open or the key bound
--------------------------------------------------------------------------------

local function Sync()
	local f = K.events
	if not f then
		return
	end
	local fights = (M.isEnabled and K.open) or K.bound
	if fights then
		f:RegisterEvent("PLAYER_REGEN_DISABLED")
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
	else
		f:UnregisterEvent("PLAYER_REGEN_DISABLED")
		f:UnregisterEvent("PLAYER_REGEN_ENABLED")
	end
end

local Events_OnEvent = Shared("OnEvent on the Loot All Key's events", function(_, event)
	if event == "LOOT_OPENED" then
		K.open, K.pressed = true, nil
		Bind()
	elseif event == "LOOT_CLOSED" then
		K.open = false
		Unbind()
	elseif event == "PLAYER_REGEN_DISABLED" then
		Unbind(true)
	elseif event == "PLAYER_REGEN_ENABLED" then
		if K.open and M.isEnabled then
			Bind()
		else
			Unbind()
		end
	end
	Sync()
end, "script")

function M:OnEnable(db)
	self.db = db
	local f = K.events
	if not f then
		f = CreateFrame("Frame")
		Perf.SetScript(f, "OnEvent", Events_OnEvent)
		K.events = f
	end
	f:RegisterEvent("LOOT_OPENED")
	f:RegisterEvent("LOOT_CLOSED")
	Sync()
end

function M:OnDisable()
	local f = K.events
	if f then
		f:UnregisterEvent("LOOT_OPENED")
		f:UnregisterEvent("LOOT_CLOSED")
	end
	K.open = false
	Unbind()
	Sync()
end

function M:OnSettingChanged(key)
	if key == "key" and K.bound and not Fighting() then
		Unbind()
		Bind()
	end
end
