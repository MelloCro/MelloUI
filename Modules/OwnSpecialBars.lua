--------------------------------------------------------------------------------
-- MelloUI - Own Bars, the stance, pet and possess bars as MelloUI's own (fr-18 stage 3, 2026-11-02; the user: "Make
-- all of those parts our own", then "continue to stage 3")
--
-- One system with Modules/OwnBars.lua and Modules/OwnActionBars.lua (MelloUI.OwnBars: its parts, its places, its
-- helpers OB.kit, the game's names answered with ours, the bus 'ownbars'). While UI Modifications is on, the stance,
-- pet and possess bars on the screen are ours:
--   * Each bar a SecureHandlerStateTemplate header of ours (MelloUIStanceBar, MelloUIPetBar, MelloUIPossessBar)
--     where the game's bar stood, its buttons (MelloUIStanceBarButton<i> ...) made from the game's own button
--     templates (StanceButtonTemplate, PetActionButtonTemplate, PossessButtonTemplate: the game's art, cooldown,
--     autocast sparkle, hotkey and tooltip under the game's keys) with SecureActionButtonTemplate LAST, so the click
--     is the secure template's (fr-18c: a later template's scripts lie over an earlier one's).
--   * The click: type "click" on the game's own button of the same index (its "clickbutton"), so the game's code casts
--     the form, the pet action or its autocast (a right click) or cancels the possession -- securely, in a fight too.
--     Keys stay the game's (SHAPESHIFTBUTTON<i>, BONUSACTIONBUTTON<i>: they press the game's buttons). Drag and drop on
--     the pet bar: PickupPetAction, the game's lock and modifier.
--   * When each shows: a state driver of ours ([vehicleui] [possessbar] [overridebar] [petbattle] hide the stance and
--     pet bars; the pet bar while a pet is out; the possess bar while [possessbar]); the stance bar with no form at all,
--     hidden (out of a fight, on UPDATE_SHAPESHIFT_FORMS).
--   * Their look and state from the game's own data (GetShapeshiftFormInfo, GetPetActionInfo, GetPossessInfo), the
--     buttons laid as the game lays its own (each button's place and scale on the game's bar, read: the layout's
--     orientation, rows, icon size and padding, Tweaks' Bar Layout rows); cooldowns as the game sets them while plain,
--     from the game's duration objects while secret.
--   * Places: movers of MelloUI's own store by Modules/OwnBars.lua's rule: a place of its own from the player's Edit
--     Layout save, a profile, the installer or an import; until then each follows the game's bar (its own anchor point
--     on it, live).
--
-- The game's bars kept away as the action bars' are: the bars at alpha 0, their buttons' mouse off, Edit Mode's
-- selection boxes unseen. Nothing written on them but that (the keys stay theirs, the click goes through them). Given
-- back exactly when UI Modifications goes off. Built and taken down out of a fight only.
--
--   OwnBars.Special                     the part: bars[kind], Dump(print)
--   bus 'ownbars' ("special", on)       ours came or went
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local OB = MelloUI.OwnBars
if not (OB and OB.kit and OB.AddPart) then
	return
end
local Perf = MelloUI.Perf:Scope("OwnSpecialBars")
local C_Timer = Perf.C_Timer
local Safe = MelloUI.Safe
local Secret = Safe.IsSecret
local Finite = Safe.Finite
local Plain = Safe.Value
local K = OB.kit
local Call = K.Call

local PART = "special"
local KINDS = {
	stance = { game = "StanceBar", prefix = "StanceButton", n = 10, template = "StanceButtonTemplate",
		name = "MelloUIStanceBar", label = "Stance Bar", command = "SHAPESHIFTBUTTON", index = 11 },
	pet = { game = "PetActionBar", prefix = "PetActionButton", n = 10, template = "PetActionButtonTemplate",
		name = "MelloUIPetBar", label = "Pet Bar", command = "BONUSACTIONBUTTON", index = 12 },
	possess = { game = "PossessActionBar", prefix = "PossessButton", n = 2, template = "PossessButtonTemplate",
		name = "MelloUIPossessBar", label = "Possess Bar", index = 13 },
}
local ORDER = { "stance", "pet", "possess" }
local DRIVERS = {
	stance = "[vehicleui][possessbar][overridebar][petbattle] hide; show",
	pet = "[vehicleui][possessbar][overridebar][petbattle] hide; [@pet,exists,nodead] show; hide",
	possess = "[possessbar] show; hide",
}
local BUTTON = 30   -- (SmallActionButtonTemplate's size)
local EVENTS = { "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORMS", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_USABLE",
	"UPDATE_SHAPESHIFT_COOLDOWN", "PET_BAR_UPDATE", "PET_BAR_UPDATE_COOLDOWN", "PET_BAR_UPDATE_USABLE", "PET_UI_UPDATE",
	"PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_TARGET_CHANGED", "UPDATE_VEHICLE_ACTIONBAR",
	"UPDATE_POSSESS_BAR", "UPDATE_BINDINGS", "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN" }
local UNIT_EVENTS = { "UNIT_PET", "UNIT_FLAGS", "UNIT_AURA" }

local S = { bars = {}, built = nil, gameOf = {} }
OB.Special = S

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function Global(name)
	local fn = rawget(_G, name)
	return type(fn) == "function" and fn or nil
end

-- fn(...) answered plain (nil for a secret or an error), up to four values
local function Ask(name, ...)
	local fn = Global(name)
	if not fn then
		return nil
	end
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then
		return nil
	end
	return Plain(a), Plain(b), Plain(c), Plain(d)
end

-- a cooldown as the game sets it while its values are plain; from the game's duration object (by the spell) while
-- they are secret; cleared when neither reads
local function SetCooldown(cd, start, duration, enable, spellID)
	if not cd then
		return
	end
	if start ~= nil and not Secret(start) and not Secret(duration) and not Secret(enable) then
		local set = Global("CooldownFrame_Set")
		if set and pcall(set, cd, start, duration, enable) then
			return
		end
	end
	local api = rawget(_G, "C_Spell")
	local fn = type(api) == "table" and api.GetSpellCooldownDuration
	if spellID and not Secret(spellID) and type(fn) == "function" and type(cd.SetCooldownFromDurationObject) == "function" then
		local ok, d = pcall(fn, spellID)
		if ok and d ~= nil and pcall(cd.SetCooldownFromDurationObject, cd, d, true) then
			return
		end
	end
	pcall(cd.Clear, cd)
end

local function Hotkey(btn, command)
	local hk = btn.HotKey
	if not (hk and command) then
		return
	end
	local key = Ask("GetBindingKey", command .. btn:GetID())
	local text = key and Global("GetBindingText") and Ask("GetBindingText", key, true) or ""
	if text and text ~= "" then
		hk:SetText(text)
		hk:Show()
	else
		hk:SetText("")
		hk:Hide()
	end
end

--------------------------------------------------------------------------------
-- Each kind's state (the game's own update code, on our buttons)
--------------------------------------------------------------------------------

local UPDATE = {}

function UPDATE.stance(bar)
	local count = Ask("GetNumShapeshiftForms") or 0
	bar.numForms = count
	for i, btn in ipairs(bar.buttons) do
		if i <= count then
			local texture, isActive, isCastable, spellID = Ask("GetShapeshiftFormInfo", i)
			btn.icon:SetTexture(texture)
			btn.icon:Show()
			local start, duration, enable = Ask("GetShapeshiftFormCooldown", i)
			SetCooldown(btn.cooldown, start, duration, enable, spellID)
			btn:SetChecked(isActive and true or false)
			if isCastable then
				btn.icon:SetVertexColor(1, 1, 1)
			else
				btn.icon:SetVertexColor(0.4, 0.4, 0.4)
			end
		end
		Hotkey(btn, KINDS.stance.command)
	end
end

function UPDATE.pet(bar)
	for i, btn in ipairs(bar.buttons) do
		-- (the game's own PetActionButtonMixin:UpdateButtonState, on our button: its icon, token, checked, flash, the
		-- autocast sparkle, usable -- all on our frame and its own parts)
		if type(btn.UpdateButtonState) == "function" then
			pcall(btn.UpdateButtonState, btn)
		end
		local _, _, _, _, _, _, spellID = Ask("GetPetActionInfo", i)
		local start, duration, enable = Ask("GetPetActionCooldown", i)
		SetCooldown(btn.cooldown, start, duration, enable, spellID)
		Hotkey(btn, KINDS.pet.command)
	end
end

function UPDATE.possess(bar)
	for i, btn in ipairs(bar.buttons) do
		local texture = Ask("GetPossessInfo", i)
		btn.icon:SetTexture(texture)
		btn.icon:SetVertexColor(1, 1, 1)
		btn.icon:SetDesaturated(false)
		btn.cooldown:Hide()
		btn:SetChecked(false)
	end
end

local function Update(kind)
	local bar = S.bars[kind]
	if bar and OB.On(PART) then
		local ok, err = pcall(UPDATE[kind], bar)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

local function UpdateAll()
	for _, kind in ipairs(ORDER) do
		Update(kind)
	end
end

--------------------------------------------------------------------------------
-- Building (out of a fight only)
--------------------------------------------------------------------------------

-- the game's "lock action bars" (Settings, as the game's pet buttons read it; the CVar where Settings is not there)
local function Locked()
	local St = rawget(_G, "Settings")
	if type(St) == "table" and type(St.GetValue) == "function" then
		local ok, v = pcall(St.GetValue, "lockActionBars")
		if ok and not Secret(v) then
			return v and true or false
		end
	end
	return Ask("GetCVarBool", "lockActionBars") and true or false
end

-- the pet bar's drag and drop, ours (the template's would call the game's PetActionBar:Update from our code)
local function PetDragStart(self)
	local locked = Locked()
	local modified = Ask("IsModifiedClick", "PICKUPACTION")
	if not locked or modified then
		self:SetChecked(false)
		pcall(rawget(_G, "PickupPetAction"), self:GetID())
		Update("pet")
	end
end

local function PetReceiveDrag(self)
	if Ask("GetCursorInfo") == "petaction" then
		self:SetChecked(false)
		pcall(rawget(_G, "PickupPetAction"), self:GetID())
		Update("pet")
	end
end

local function NewButton(bar, kind, i)
	local spec = KINDS[kind]
	local name = spec.name .. "Button" .. i
	local ok, btn = pcall(CreateFrame, "CheckButton", name, bar, spec.template .. ", SecureActionButtonTemplate")
	if not ok or type(btn) ~= "table" then
		return nil
	end
	OB.mine[btn] = true
	btn:SetID(i)
	btn.index = i
	btn:RegisterForClicks("AnyUp")
	-- the click: the game's own button of this index (its code, securely)
	local game = rawget(_G, spec.prefix .. i)
	btn:SetAttribute("type", "click")
	btn:SetAttribute("clickbutton", game)
	if kind == "pet" then
		btn:RegisterForDrag("LeftButton", "RightButton")
		btn:SetScript("OnDragStart", PetDragStart)
		btn:SetScript("OnReceiveDrag", PetReceiveDrag)
		btn:SetScript("OnUpdate", nil)   -- (the template's range and flash timer: no idle OnUpdate of ours)
		btn:SetScript("OnEvent", nil)    -- (its hotkey events: ours on our one frame)
		btn:UnregisterAllEvents()
	end
	btn:SetFrameLevel(bar:GetFrameLevel() + 2)
	return btn
end

local function BuildBar(kind)
	local spec = KINDS[kind]
	local game = rawget(_G, spec.game)
	if type(game) ~= "table" then
		return nil
	end
	local bar = CreateFrame("Frame", spec.name, UIParent, "SecureHandlerStateTemplate")
	OB.mine[bar] = true
	bar.kind = kind
	bar.buttons = {}
	bar.actionButtons = bar.buttons   -- (the game's key for a bar's buttons: what dresses the game's bars finds ours)
	bar:SetFrameStrata(Call(game, "GetFrameStrata") or "MEDIUM")
	local level = Finite(Call(game, "GetFrameLevel"))
	if level then
		bar:SetFrameLevel(level)
	end
	bar:SetSize(BUTTON * spec.n, BUTTON)
	for i = 1, spec.n do
		local btn = NewButton(bar, kind, i)
		if not btn then
			return nil
		end
		bar.buttons[i] = btn
	end
	bar:Hide()
	return bar
end

local function Build()
	if S.built ~= nil then
		return S.built
	end
	S.built = false
	for _, kind in ipairs(ORDER) do
		local ok, bar = pcall(BuildBar, kind)
		if not ok then
			geterrorhandler()(bar)
			return false
		end
		if not bar then
			return false
		end
		S.bars[kind] = bar
		S.gameOf[bar] = rawget(_G, KINDS[kind].game)
		OB.gameOf[bar] = S.gameOf[bar]
	end
	S.events = CreateFrame("Frame")
	S.built = true
	return true
end

--------------------------------------------------------------------------------
-- Layout and visibility (out of a fight; in one, after it)
--------------------------------------------------------------------------------

-- how many buttons a bar shows now
local function Shown(kind, bar)
	if kind == "stance" then
		return bar.numForms or 0
	end
	return KINDS[kind].n
end

-- our buttons laid as the game lays its own on its bar: each button's offset from the bar's top left and its scale,
-- read (the layout's orientation, rows, icon size, padding); a row of the template's size where the game's bar was
-- never laid
local function Lay(kind)
	local bar = S.bars[kind]
	if not bar or InCombatLockdown() then
		return
	end
	local game = S.gameOf[bar]
	local gl, gt = Finite(Call(game, "GetLeft")), Finite(Call(game, "GetTop"))
	local gw, gh = Finite(Call(game, "GetWidth")), Finite(Call(game, "GetHeight"))
	local gs = Finite(Call(game, "GetEffectiveScale")) or 1
	local count = Shown(kind, bar)
	local maxR, maxB = 0, 0
	for i, btn in ipairs(bar.buttons) do
		local gb = rawget(_G, KINDS[kind].prefix .. i)
		local bl, bt = Finite(Call(gb, "GetLeft")), Finite(Call(gb, "GetTop"))
		local bs = Finite(Call(gb, "GetScale")) or 1
		btn:ClearAllPoints()
		btn:SetScale(bs)
		local x, y
		if gl and gt and bl and bt and (Finite(Call(gb, "GetEffectiveScale")) or 0) > 0 then
			local es = Finite(Call(gb, "GetEffectiveScale"))
			x, y = (bl * es - gl * gs) / gs, (bt * es - gt * gs) / gs
		else
			x, y = (i - 1) * (BUTTON + 2) * bs, 0
		end
		btn:SetPoint("TOPLEFT", bar, "TOPLEFT", x / bs, y / bs)
		btn:SetShown(i <= count)
		if i <= count then
			maxR = math.max(maxR, x + BUTTON * bs)
			maxB = math.max(maxB, -y + BUTTON * bs)
		end
	end
	bar:SetSize(math.max(gw or maxR, 1), math.max(gh or maxB, 1))
	local driver = DRIVERS[kind]
	if kind == "stance" and count == 0 then
		driver = "hide"
	end
	if bar.driver ~= driver then
		bar.driver = driver
		RegisterStateDriver(bar, "visibility", driver)
	end
end

local function LayAll()
	for _, kind in ipairs(ORDER) do
		Lay(kind)
	end
end

local function Later(fn, key)
	if InCombatLockdown() then
		MelloUI.Kit:WhenOutOfCombat(fn, key)
		return true
	end
	return false
end

-- laid again on the next frame (the game shows and lays its own bar in the same event: after it), out of a fight
local layQueued = false
local function LaySoon()
	if layQueued then
		return
	end
	layQueued = true
	C_Timer.After(0, function()
		layQueued = false
		if OB.On(PART) and not Later(LayAll, "Own Bars: the stance, pet and possess bars laid") then
			LayAll()
		end
	end)
end

--------------------------------------------------------------------------------
-- Events (one frame of ours for all three bars)
--------------------------------------------------------------------------------

function S.OnEvent(_, event, unit)
	if not OB.On(PART) then
		return
	end
	if event == "UPDATE_SHAPESHIFT_FORMS" or event == "PLAYER_ENTERING_WORLD" then
		UpdateAll()
		LaySoon()
	elseif event == "UPDATE_BINDINGS" then
		UpdateAll()
	elseif event:find("^UPDATE_SHAPESHIFT") then
		Update("stance")
	elseif event == "PET_BAR_UPDATE" or event == "PET_UI_UPDATE" then
		Update("pet")
		LaySoon()
	elseif event:find("^PET_") or event == "PLAYER_CONTROL_LOST" or event == "PLAYER_CONTROL_GAINED"
		or event == "PLAYER_TARGET_CHANGED" then
		Update("pet")
	elseif event == "UNIT_PET" or event == "UNIT_FLAGS" or event == "UNIT_AURA" then
		if unit == "pet" or unit == "player" then
			Update("pet")
			if event == "UNIT_PET" then
				LaySoon()   -- (a pet out: the game lays its pet bar as it shows)
			end
		end
	elseif event == "UPDATE_POSSESS_BAR" or event == "UPDATE_VEHICLE_ACTIONBAR" then
		Update("possess")
		Update("pet")
		LaySoon()
	else
		Update("stance")
		Update("pet")
	end
end

--------------------------------------------------------------------------------
-- The game's bars kept away and given back
--------------------------------------------------------------------------------

local function GameParts(fn)
	for _, kind in ipairs(ORDER) do
		local spec = KINDS[kind]
		local game = rawget(_G, spec.game)
		if type(game) == "table" then
			fn("alpha", game)
			fn("select", game)
			for i = 1, spec.n do
				fn("mouse", rawget(_G, spec.prefix .. i))
			end
		end
	end
end

local function Away()
	GameParts(function(what, f)
		if what == "alpha" then
			K.Fade(f)
		elseif what == "select" then
			K.SelectionAway(f)
		else
			K.MouseOff(f)
		end
	end)
end

local function Back()
	GameParts(function(what, f)
		if what == "alpha" then
			K.Unfade(f)
		elseif what == "select" then
			K.SelectionBack(f)
		else
			K.MouseBack(f)
		end
	end)
end

--------------------------------------------------------------------------------
-- Places, on and off
--------------------------------------------------------------------------------

local function BarsPlaced()
	if not OB.On(PART) or Later(BarsPlaced, "Own Bars: the stance, pet and possess bars placed") then
		return
	end
	LayAll()
	for _, kind in ipairs(ORDER) do
		local bar = S.bars[kind]
		if K.Place(bar) then
			K.StackOrGame(bar, S.gameOf[bar], {})
		end
	end
end
OB.followers[PART] = BarsPlaced

local function On()
	if InCombatLockdown() or not Build() then
		return false
	end
	Away()
	for _, kind in ipairs(ORDER) do
		local spec, bar = KINDS[kind], S.bars[kind]
		OB.own[spec.game] = bar
		for i, btn in ipairs(bar.buttons) do
			OB.own[spec.prefix .. i] = btn
		end
	end
	OB.standing[PART] = true
	S.placeholders = S.placeholders or {}
	for _, kind in ipairs(ORDER) do
		local spec, bar = KINDS[kind], S.bars[kind]
		local ph = S.placeholders[kind] or { BUTTON * spec.n, BUTTON }
		S.placeholders[kind] = ph
		K.Register(bar, PART, spec.name, spec.label, ph, "BOTTOM")
		OB.followed[bar] = nil
	end
	S.events:SetScript("OnEvent", S.OnEvent)
	for _, e in ipairs(EVENTS) do
		pcall(S.events.RegisterEvent, S.events, e)
	end
	for _, e in ipairs(UNIT_EVENTS) do
		pcall(S.events.RegisterUnitEvent, S.events, e, "player", "pet")
	end
	UpdateAll()
	BarsPlaced()
	K.FollowListen()
	return true
end

local function Off()
	OB.standing[PART] = nil
	for _, kind in ipairs(ORDER) do
		local spec, bar = KINDS[kind], S.bars[kind]
		if OB.own[spec.game] == bar then
			OB.own[spec.game] = nil
		end
		for i = 1, spec.n do
			OB.own[spec.prefix .. i] = nil
		end
		if bar then
			UnregisterStateDriver(bar, "visibility")
			bar.driver = nil
			bar:Hide()
		end
	end
	if S.events then
		S.events:UnregisterAllEvents()
	end
	Back()
end

OB.AddPart({ id = PART, on = On, off = Off, secure = true })
OB.AddSystem("ActionBar", PART, { [11] = true, [12] = true, [13] = true })
for _, kind in ipairs(ORDER) do
	OB.AddKey(KINDS[kind].name)
end

--------------------------------------------------------------------------------
-- /run MelloUI.OwnBars.Special.Dump(print)
--------------------------------------------------------------------------------

function S.Dump(out)
	out = out or print
	out(("Own Bars, the stance / pet / possess bars: standing %s, built %s"):format(tostring(OB.On(PART)),
		tostring(S.built)))
	for _, kind in ipairs(ORDER) do
		local bar = S.bars[kind]
		if bar then
			local l, b, r, t = Safe.ScreenRect(bar)
			out(("  %s: %s, %s buttons, driver %s, %s"):format(kind, bar:IsShown() and "shown" or "hidden",
				tostring(Shown(kind, bar)), tostring(bar.driver),
				l and ("%.0f,%.0f-%.0f,%.0f"):format(l, b, r, t) or "-"))
		end
	end
end
