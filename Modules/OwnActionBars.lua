--------------------------------------------------------------------------------
-- MelloUI - Own Bars, the action bars 1-8 as MelloUI's own (fr-18 stage 2, 2026-11-01; the user: "Make all of those
-- parts our own", then "right clicking on the action bars, those changes that you make here dont reflect in real
-- time, only after /reload")
--
-- One system with Modules/OwnBars.lua (MelloUI.OwnBars: its parts, its places, its helpers OB.kit, the game's names
-- answered with ours, the bus 'ownbars'). While UI Modifications is on, Action Bars 1-8 on the screen are ours:
--   * Each bar a SecureHandlerStateTemplate header of ours (MelloUIActionBar1 .. 8) where the game's bar stood, with
--     twelve buttons of ours (MelloUIActionBar<n>Button<i>) made from the game's own templates:
--     SecureActionButtonTemplate (the click, self cast, focus and mouseover cast, the game's secure path) and
--     ActionButtonTemplate (the game's art and parts under the game's keys: icon, cooldown, chargeCooldown,
--     lossOfControlCooldown, Count, HotKey, Name, Border, Flash, NormalTexture, SlotArt ...), so MelloUI Frames, the
--     press light and range colours, Cooldown Text, Dark Mode and the painted rims dress them as they dressed the
--     game's. NOT ActionBarButtonTemplate: its OnLoad files every button made from it into the game's own tables
--     (ActionBarButtonEventsFrame.frames, the range and usable watchers, the spell alert manager) -- one made by an
--     addon there taints the game's action bar controller, whose loop then shows protected bars in a fight (hard
--     rule 1: no keys on the game's tables). The template's display code is copied here instead (Update, the state,
--     usable, count, flash, hotkey, tooltip, the spell alert as the game's ActionButtonSpellAlertTemplate), on an
--     event frame of ours; cooldowns as the game's ActionButton_UpdateCooldown while the values are plain, from the
--     game's duration objects while they are secret (a fight: SecretWhenCooldownsRestricted).
--   * The page: Action Bar 1's from a state driver of ours ([vehicleui] the vehicle bar; [overridebar]; [shapeshift];
--     [bar:2-6]; [bonusbar:1-5]: this client's ActionBarController order -- stances, forms, stealth, a possessed
--     creature's bar), each button told through its header's ChildUpdate; Bars 2-8 at the game's own fixed pages (their
--     "actionpage" attribute, read from the game's bars).
--   * Keys: the game's own bindings (each button's commandName, ACTIONBUTTON1 ... MULTIACTIONBAR7BUTTON12) put on ours
--     with SetOverrideBindingClick, read again on UPDATE_BINDINGS out of a fight; a key fires on its press or release
--     as the game's ActionButtonUseKeyDown says, a mouse click on its release (the header's secure click wrapper).
--   * Drag and drop through the secure drag wrappers (the game's "lock action bars" and its pick-up modifier).
--   * Every setting of the bar's Edit Layout box is ours and acts at once (out of a fight; in one, after it, said once):
--     Orientation, # of Rows, # of Icons, Icon Size, Icon Padding, Bar Visible, Always Show Buttons (Own Bars' per-bar
--     options, "bar<n>Rows" ...), Action Bar 1's Hide Bar Art and Hide Page Arrows (Action Bars' own options). A bar's
--     setting not set yet is the game's (its active Edit Mode layout's value), so nothing changes when ours stand in,
--     and a profile that brings none takes the layout the installer puts in.
--   * Places: movers of MelloUI's own store, by Modules/OwnBars.lua's rule (fr-18 sim; fr-18c): a place of its own
--     comes only from the player's Edit Layout save, a profile, the installer or an import; until then each bar follows
--     the game's bar (hung by the game's own anchor point on it, live), and Bars 2 and 3 in the game's bottom stack are
--     stacked on ours as the game's stack stacks them (our main bar its base, our status bars' rows). A setting not set
--     follows the layout the same way: laid again when the active layout changes it.
--
-- The game's bars kept away (fr-16 / stage 1's means): Bars 2-8 at alpha 0; Action Bar 1's frame stays as it is (its
-- end caps are Edit Mode systems of their own inside it) and its own parts go to alpha 0 (its buttons' containers, its
-- art, its page number, its dividers); every game button's and the bars' mouse off; Edit Mode's selection boxes
-- unseen and click-through; the bars' grid events let go (MelloUI.Units.Silence). No key written on them, no hook,
-- nothing shown, hidden or moved. Given back exactly when UI Modifications goes off (out of a fight).
-- Built and taken down out of a fight only: a /reload in a fight keeps the game's bars until it ends.
--
-- Nothing at login beyond the bars themselves (ours replace the game's at the login's own frame); no OnUpdate but an
-- attack button's flash while it flashes.
--
--   OwnBars.Actions                     the part: bars[n], Values(n), Lay(n), Dump(print)
--   bus 'ownbars' ("actions", on)       ours came or went
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local OB = MelloUI.OwnBars
if not (OB and OB.kit and OB.AddPart) then
	return
end
local Perf = MelloUI.Perf:Scope("OwnActionBars")
local Shared = Perf.Shared
local C_Timer = Perf.C_Timer
local Safe = MelloUI.Safe
local Secret = Safe.IsSecret
local Finite = Safe.Finite
local Plain = Safe.Value   -- (v, or nil when it is secret)
local K = OB.kit
local Field, Call = K.Field, K.Call
local M = OB.module
-- (the game's secure helpers, read as the bars are built: the click and drag wrappers, the override bindings)
local WrapScript, OverrideClick

local PART = "actions"
local OWNER = "Own Bars: the action bars"
local NUM = 12             -- buttons a bar
local BUTTON = 45          -- the template's button
local GAME_BARS = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
	"MultiBar5", "MultiBar6", "MultiBar7" }
local GAME_PREFIX = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
	"MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
-- (fallbacks when the game's bar cannot be read: MultiActionBars.xml's pages and commands)
local FIXED_PAGE = { nil, 6, 5, 3, 4, 13, 14, 15 }
local COMMAND = { "ACTIONBUTTON", "MULTIACTIONBAR1BUTTON", "MULTIACTIONBAR2BUTTON", "MULTIACTIONBAR3BUTTON",
	"MULTIACTIONBAR4BUTTON", "MULTIACTIONBAR5BUTTON", "MULTIACTIONBAR6BUTTON", "MULTIACTIONBAR7BUTTON" }
local LABELS = { "Action Bar 1", "Action Bar 2", "Action Bar 3", "Action Bar 4", "Action Bar 5", "Action Bar 6",
	"Action Bar 7", "Action Bar 8" }
local GRID_EVENTS = { "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID" }
local TEXT = {
	later = "The action bars change after the fight.",
	horizontal = "Horizontal", vertical = "Vertical",
	always = "Always", inCombat = "In Combat", outOfCombat = "Out of Combat", hidden = "Hidden",
	mouseover = "On Mouseover",
}

local A = { bars = {}, built = nil, buttons = {}, byAction = {}, gameOf = {}, wantShown = {} }
OB.Actions = A

--------------------------------------------------------------------------------
-- The settings (Own Bars' options, one set a bar): Edit Mode's names and ranges; not set = the game's
--------------------------------------------------------------------------------

local ORIENT_VALUES = { { value = 0, label = TEXT.horizontal }, { value = 1, label = TEXT.vertical } }
-- (Edit Mode's Bar Visible; and the Fader's On Mouseover, its "show_bar<n>" the one store, as the box offered it)
local VISIBLE_VALUES = { { value = 0, label = TEXT.always }, { value = 1, label = TEXT.inCombat },
	{ value = 2, label = TEXT.outOfCombat }, { value = 3, label = TEXT.hidden }, { value = "mouseover", label = TEXT.mouseover } }
local MOUSEOVER = "mouseover"
local function Percent(v)
	return ("%d%%"):format(math.floor((tonumber(v) or 0) + 0.5))
end

-- suffix -> { the game's setting name, kind, its default }
local SPEC = {
	Orientation = { "Orientation", "dropdown", 0 },
	Rows = { "NumRows", "slider", 1 },
	Icons = { "NumIcons", "slider", 12 },
	IconSize = { "IconSize", "slider", 100 },
	Padding = { "IconPadding", "slider", 2 },
	Visible = { "VisibleSetting", "dropdown", 0 },
	ShowButtons = { "AlwaysShowButtons", "toggle", true },
}
local SUFFIXES = { "Orientation", "Rows", "Icons", "IconSize", "Padding", "Visible", "ShowButtons" }
A.SUFFIXES = SUFFIXES

local function Key(n, suffix)
	return "bar" .. n .. suffix
end
A.Key = Key

-- the active Edit Mode layout's value of the game's bar n (display value), or nil
local function EditModeValue(n, suffix)
	local E = rawget(_G, "Enum")
	local sys = type(E) == "table" and type(E.EditModeSystem) == "table" and E.EditModeSystem.ActionBar
	local settings = type(E) == "table" and E.EditModeActionBarSetting
	local setting = type(settings) == "table" and settings[SPEC[suffix][1]]
	if type(sys) ~= "number" or type(setting) ~= "number" or not MelloUI.EditModeSystemSettings then
		return nil
	end
	local ok, values = pcall(MelloUI.EditModeSystemSettings, MelloUI, sys, n)
	local raw = ok and type(values) == "table" and values[setting] or nil
	if Secret(raw) or type(raw) ~= "number" then
		return nil
	end
	if suffix == "IconSize" then
		return raw * 10 + 50
	elseif suffix == "ShowButtons" then
		return raw == 1
	end
	return raw
end

-- a bar's setting as it acts now: ours, else the game's layout's, else the game's default (Bar Visible: On Mouseover
-- while the Fader holds the bar so)
local function Value(n, suffix, db)
	db = db or M.db
	if suffix == "Visible" then
		local F = MelloUI:GetModuleDB("Fader")
		if F and F["show_bar" .. n] == "mouseover" then
			return "mouseover"
		end
	end
	local v = db and db[Key(n, suffix)]
	if v ~= nil then
		return v
	end
	v = EditModeValue(n, suffix)
	if v ~= nil then
		return v
	end
	if suffix == "Orientation" and (n == 4 or n == 5) then
		return 1   -- (the side bars stand upright in the game's presets)
	end
	return SPEC[suffix][3]
end
A.Value = Value

local function Values(n)
	local out = {}
	for _, s in ipairs(SUFFIXES) do
		out[s] = Value(n, s)
	end
	local vis = out.Visible
	if vis == MOUSEOVER then
		out.Visible = 0
	end
	out.Rows = math.max(1, math.min(4, math.floor(tonumber(out.Rows) or 1)))
	out.Icons = math.max(6, math.min(NUM, math.floor(tonumber(out.Icons) or NUM)))
	out.IconSize = math.max(50, math.min(200, tonumber(out.IconSize) or 100))
	out.Padding = math.max(2, math.min(10, tonumber(out.Padding) or 2))
	return out
end
A.Values = Values

-- the options (appended to Own Bars' schema; their rows live in each bar's Edit Layout box, and Bars > Action Bars'
-- Layout rows set the picked bar's: Tweaks' Bar Layout)
do
	local NEW = "2.1.0"
	for n = 1, #GAME_BARS do
		local function Get(suffix)
			return function(db)
				return Value(n, suffix, db)
			end
		end
		local list = M.options
		list[#list + 1] = { type = "dropdown", key = Key(n, "Orientation"), name = "Orientation", new = NEW,
			values = ORIENT_VALUES, get = Get("Orientation"),
			desc = "Whether the bar's buttons lie in a row or stand in a column." }
		list[#list + 1] = { type = "slider", key = Key(n, "Rows"), name = "# of Rows", new = NEW, min = 1, max = 4, step = 1,
			get = Get("Rows"), desc = "How many rows (or columns, upright) the bar's buttons stand in." }
		list[#list + 1] = { type = "slider", key = Key(n, "Icons"), name = "# of Icons", new = NEW, min = 6, max = 12,
			step = 1, get = Get("Icons"), desc = "How many of the bar's buttons show." }
		list[#list + 1] = { type = "slider", key = Key(n, "IconSize"), name = "Icon Size", new = NEW, min = 50, max = 200,
			step = 10, format = Percent, get = Get("IconSize"), desc = "The size of the bar's buttons. 100% is the game's size." }
		list[#list + 1] = { type = "slider", key = Key(n, "Padding"), name = "Icon Padding", new = NEW, min = 2, max = 10,
			step = 1, get = Get("Padding"), desc = "The space between the bar's buttons." }
		list[#list + 1] = { type = "dropdown", key = Key(n, "Visible"), name = "Bar Visible", new = NEW,
			values = VISIBLE_VALUES, get = Get("Visible"),
			desc = "When the bar shows: always, only in a fight, only out of one, never, or while the pointer is over it." }
		list[#list + 1] = { type = "toggle", key = Key(n, "ShowButtons"), name = "Always Show Buttons", new = NEW,
			get = Get("ShowButtons"), desc = "Empty buttons show their slot too." }
	end
end

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function Api(name)
	local api = rawget(_G, "C_ActionBar")
	local fn = type(api) == "table" and api[name]
	return type(fn) == "function" and fn or nil
end

-- C_ActionBar.<name>(action, ...) plain, or nil (a secret, an error)
local function Ask(name, action, ...)
	local fn = Api(name)
	if not fn or type(action) ~= "number" then
		return nil
	end
	local ok, v, w, x = pcall(fn, action, ...)
	if not ok or Secret(v) then
		return nil
	end
	return v, Plain(w), Plain(x)
end

local function GetInfo(action)
	if type(action) ~= "number" then
		return nil
	end
	local ok, kind, id, sub = pcall(GetActionInfo, action)
	if not ok or Secret(kind) then
		return nil
	end
	return kind, Plain(id), Plain(sub)
end

--------------------------------------------------------------------------------
-- The buttons' own code (the game's ActionBarActionButtonMixin's display part, ours)
--------------------------------------------------------------------------------

local B = {}   -- copied onto each button of ours
local RANGE = "\226\151\143"   -- (the game's RANGE_INDICATOR, a dot)
local HOTKEY_COLOR = { 0.6, 0.6, 0.6 }

local function RangeIndicator()
	local v = rawget(_G, "RANGE_INDICATOR")
	return type(v) == "string" and v or RANGE
end

local function HotkeyColour(fs)
	local c = rawget(_G, "ACTIONBAR_HOTKEY_FONT_COLOR")
	if type(c) == "table" and type(c.GetRGB) == "function" then
		fs:SetVertexColor(c:GetRGB())
	else
		fs:SetVertexColor(HOTKEY_COLOR[1], HOTKEY_COLOR[2], HOTKEY_COLOR[3])
	end
end

-- the slot this button shows now (its page and ID, as the game's CalculateAction reads them)
function B.CalcAction(self)
	local page = tonumber(self:GetAttribute("actionpage"))
	if not page then
		return nil
	end
	return self:GetID() + (page - 1) * NUM
end

-- range checks: one switch per slot for all of ours (the game's own watcher's slots are left as they are)
local rangeRefs = {}
local function RangeOn(action)
	local fn = Api("EnableActionRangeCheck")
	if not fn or type(action) ~= "number" then
		return
	end
	local n = (rangeRefs[action] or 0) + 1
	rangeRefs[action] = n
	if n == 1 then
		pcall(fn, action, true)
	end
end

local function GameWatches(action)
	local frame = rawget(_G, "ActionBarButtonRangeCheckFrame")
	local actions = type(frame) == "table" and rawget(frame, "actions")
	local t = type(actions) == "table" and actions[action]
	return type(t) == "table" and next(t) ~= nil
end

local function RangeOff(action)
	local fn = Api("EnableActionRangeCheck")
	local n = rangeRefs[action]
	if not (fn and n) then
		return
	end
	n = n - 1
	rangeRefs[action] = n > 0 and n or nil
	if n <= 0 and not GameWatches(action) then
		pcall(fn, action, false)
	end
end

function B.UpdateAction(self, force)
	local action = self:CalcAction()
	if action == self.action and not force then
		return
	end
	local old = self.action
	if old ~= action then
		if old then
			RangeOff(old)
			local list = A.byAction[old]
			if list then
				list[self] = nil
			end
		end
		self.action = action
		if action then
			RangeOn(action)
			local list = A.byAction[action]
			if not list then
				list = {}
				A.byAction[action] = list
			end
			list[self] = true
			local reg = Api("RegisterActionUIButton")
			if reg then
				pcall(reg, self, action, self.cooldown)
			end
		end
	end
	self:Update()
	self:UpdateShown()
end

-- an empty button within the bar's count: seen while Always Show Buttons is on, a spell is on the cursor (the
-- game's grid) or the configurator or Edit Layout is open (A.setupOpen), else unseen (alpha: allowed in a fight; its
-- place kept, as the game keeps an empty slot's)
function B.UpdateShown(self)
	local bar = self.bar
	local has = self.action and Ask("HasAction", self.action) and true or false
	local show = has or bar.showGrid or (A.grid > 0) or A.setupOpen
	self:SetAlpha(show and 1 or 0)
end

function B.Update(self)
	local action = self.action
	local icon = self.icon
	icon:SetDesaturated(false)
	self.hasAction = (action and Ask("HasAction", action)) and true or false
	if self.hasAction then
		self:UpdateState()
		self:UpdateUsable()
		self:UpdateCooldown()
		self:UpdateFlash()
	else
		self.cooldown:Clear()
		self.chargeCooldown:Clear()
		if self.lossOfControlCooldown then
			self.lossOfControlCooldown:Clear()
		end
		self:StopFlash()
		self:SetChecked(false)
		if self.LevelLinkLockIcon then
			self.LevelLinkLockIcon:Hide()
		end
	end
	-- the green border round an equipped item
	local border = self.Border
	if border then
		if action and Ask("IsEquippedAction", action) then
			border:SetVertexColor(0, 1, 0, 0.5)
			border:Show()
		else
			border:Hide()
		end
	end
	-- a macro's name
	local name = self.Name
	if name then
		if action and Ask("UsesActionText", action) then
			local fn = Api("GetActionText")
			local ok, text = pcall(fn, action)
			name:SetText(ok and text or "")
		else
			name:SetText("")
		end
	end
	local texture
	if action then
		local fn = Api("GetActionTexture")
		local ok, t = pcall(fn, action)
		texture = ok and t or nil
	end
	if texture ~= nil then
		icon:SetTexture(texture)
		icon:Show()
		self:UpdateCount()
	else
		self.Count:SetText("")
		icon:Hide()
		local hotkey = self.HotKey
		if hotkey:GetText() == RangeIndicator() then
			hotkey:Hide()
		else
			HotkeyColour(hotkey)
		end
	end
	if self.UpdateFlyout then
		pcall(self.UpdateFlyout, self)
	end
	self:UpdateSpellAlert()
	if GameTooltip:GetOwner() == self then
		self:SetTooltip()
	end
end

function B.UpdateState(self)
	local action = self.action
	local checked = action and (Ask("IsCurrentAction", action) or Ask("IsAutoRepeatAction", action))
		and not Ask("IsAutoCastPetAction", action)
	self:SetChecked(checked and true or false)
end

-- (the game's colours: white, pale blue short of mana, grey unusable; MelloUI's range and resource colours cover it)
function B.UpdateUsable(self, action, isUsable, notEnoughMana)
	action = action or self.action
	if action ~= self.action then
		return
	end
	if isUsable == nil or notEnoughMana == nil then
		isUsable, notEnoughMana = Ask("IsUsableAction", action)
	end
	local icon = self.icon
	if isUsable then
		icon:SetVertexColor(1, 1, 1)
	elseif notEnoughMana then
		icon:SetVertexColor(0.5, 0.5, 1)
	else
		icon:SetVertexColor(0.4, 0.4, 0.4)
	end
	local LL = rawget(_G, "C_LevelLink")
	if type(LL) == "table" and type(LL.IsActionLocked) == "function" then
		local ok, locked = pcall(LL.IsActionLocked, action)
		locked = ok and Plain(locked)
		if locked then
			icon:SetDesaturated(true)
		end
		if self.LevelLinkLockIcon then
			self.LevelLinkLockIcon:SetShown(locked and true or false)
		end
	end
end

function B.UpdateCount(self)
	local fn = Api("GetActionDisplayCount")
	if not (fn and self.action) then
		self.Count:SetText("")
		return
	end
	local ok, text = pcall(fn, self.action, self.maxDisplayCount)
	self.Count:SetText(ok and text or "")   -- (a secret string is taken as it is: SetText allows it)
end

-- the game's own cooldown path while its values are plain (Cooldown Text reads it); the game's duration objects
-- while they are secret (in a fight: the cooldowns are restricted for addon code)
local function FromDuration(cd, name, action)
	if not cd then
		return
	end
	local fn = Api(name)
	local ok, d
	if fn then
		ok, d = pcall(fn, action)
	end
	if ok and d ~= nil and type(cd.SetCooldownFromDurationObject) == "function" then
		if not pcall(cd.SetCooldownFromDurationObject, cd, d, true) then
			cd:Clear()
		end
	else
		cd:Clear()
	end
end

function B.UpdateCooldown(self)
	local action = self.action
	if not action then
		return
	end
	local apply = rawget(_G, "ActionButton_UpdateCooldown")
	if type(apply) == "function" and pcall(apply, self) then
		return
	end
	FromDuration(self.cooldown, "GetActionCooldownDuration", action)
	FromDuration(self.chargeCooldown, "GetActionChargeDuration", action)
	FromDuration(self.lossOfControlCooldown, "GetActionLossOfControlCooldownDuration", action)
end

-- the attack / auto-repeat flash (the game's ATTACK_BUTTON_FLASH_TIME blink; one OnUpdate of ours while any flashes)
local FLASH_TIME = 0.4
local flashing = {}
local flasher
local function FlashStep(_, elapsed)
	local any = false
	for btn in pairs(flashing) do
		any = true
		local t = (btn.flashtime or 0) - elapsed
		if t <= 0 then
			local over = -t
			if over >= FLASH_TIME then
				over = 0
			end
			t = FLASH_TIME - over
			btn.Flash:SetShown(not btn.Flash:IsShown())
		end
		btn.flashtime = t
	end
	if not any then
		flasher:SetScript("OnUpdate", nil)
	end
end

function B.StartFlash(self)
	if flashing[self] then
		return
	end
	flashing[self] = true
	self.flashtime = 0
	if not flasher then
		flasher = CreateFrame("Frame")
	end
	flasher:SetScript("OnUpdate", FlashStep)
end

function B.StopFlash(self)
	flashing[self] = nil
	if self.Flash then
		self.Flash:Hide()
	end
end

function B.UpdateFlash(self)
	local action = self.action
	if action and ((Ask("IsAttackAction", action) and Ask("IsCurrentAction", action)) or Ask("IsAutoRepeatAction", action)) then
		self:StartFlash()
		local _, _, sub = GetInfo(action)
		local t = self:GetCheckedTexture()
		if t then
			t:SetAlpha(sub == "pet" and 0.5 or 1)
		end
	else
		self:StopFlash()
	end
end

-- the key's text (the game's binding of the button's command, or a click binding on ours)
function B.UpdateHotkeys(self)
	local hotkey = self.HotKey
	local key = GetBindingKey(self.commandName) or GetBindingKey("CLICK " .. self:GetName() .. ":Keybind")
	local text = key and GetBindingText(key, 1) or ""
	if text == "" then
		hotkey:SetText(RangeIndicator())
		hotkey:Hide()
	else
		local w = Finite(self:GetWidth()) or BUTTON
		hotkey:SetSize(w - 8, 10)
		hotkey:ClearAllPoints()
		hotkey:SetPoint("TOPRIGHT", self, "TOPRIGHT", self.hotkeyTextKeyboardX or -4, self.hotkeyTextKeyboardY or -5)
		hotkey:SetText(text)
		hotkey:Show()
	end
end

function B.SetTooltip(self)
	if GetCVar("UberTooltips") == "1" then
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
	else
		local n = self.bar and self.bar.index
		GameTooltip:SetOwner(self, (n == 3 or n == 4 or n == 5) and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
	end
	if self.action and GameTooltip:SetAction(self.action) then
		self.UpdateTooltip = self.SetTooltip
	else
		self.UpdateTooltip = nil
	end
end

-- the spell alert (the proc glow): the game's ActionButtonSpellAlertTemplate on our button, shown and played as
-- ActionButtonSpellAlertManager shows its own -- kept here, never in the game's manager's table
local function AlertFrame(self, make)
	local f = self.SpellActivationAlert
	if not f and make then
		local ok, made = pcall(CreateFrame, "Frame", nil, self, "ActionButtonSpellAlertTemplate")
		if not ok then
			return nil
		end
		f = made
		self.SpellActivationAlert = f
		local w, h = self:GetSize()
		f:SetSize((Finite(w) or BUTTON) * 1.4, (Finite(h) or BUTTON) * 1.4)
		f:SetPoint("CENTER", self, "CENTER", 0, 0)
	end
	return f
end

function B.ShowAlert(self)
	if self.alertShown then
		return
	end
	local f = AlertFrame(self, true)
	if not f then
		return
	end
	self.alertShown = true
	f:Show()
	if f.ProcStartFlipbook then
		f.ProcStartFlipbook:Show()
	end
	if f.ProcLoopFlipbook then
		f.ProcLoopFlipbook:Show()
	end
	if f.ProcAltGlow then
		f.ProcAltGlow:Hide()
	end
	if f.ProcStartAnim then
		f.ProcStartAnim:Play()
	elseif f.ProcLoop then
		f.ProcLoop:Play()
	end
end

function B.HideAlert(self)
	if not self.alertShown then
		return
	end
	self.alertShown = nil
	local f = AlertFrame(self)
	if f then
		f:Hide()
		if f.ProcStartAnim then
			f.ProcStartAnim:Stop()
		end
	end
end

-- the alert's spell on this button (a spell, or a macro's spell)
local function AlertSpell(self)
	local kind, id, sub = GetInfo(self.action)
	if kind == "spell" or (kind == "macro" and sub == "spell") then
		return id
	end
	return nil
end

function B.UpdateSpellAlert(self)
	local spell = AlertSpell(self)
	local api = rawget(_G, "C_SpellActivationOverlay")
	local on = false
	if spell and type(api) == "table" and type(api.IsSpellOverlayed) == "function" then
		local ok, v = pcall(api.IsSpellOverlayed, spell)
		on = ok and Plain(v) and true or false
	end
	if on then
		self:ShowAlert()
	else
		self:HideAlert()
	end
end

-- (the restricted page change: its snippet calls this, isolated -- CallMethod)
function B.MelloAction(self)
	self:UpdateAction()
end

--------------------------------------------------------------------------------
-- The buttons' scripts (ours, insecure, visual only: the click itself is the game's secure path)
--------------------------------------------------------------------------------

local OnEnter = Shared("OnEnter on an action button of ours", function(self)
	self:SetTooltip()
end, "script")

local OnLeave = Shared("OnLeave on an action button of ours", function(self)
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end, "script")

-- after the click (the secure one has run): the checked state, and a key's press shown as the game's ActionButtonDown
-- shows it (the button's pushed state)
local PostClick = Shared("OnClick after an action button of ours", function(self, button, down)
	if button == "Keybind" then
		self:SetButtonState(down and "PUSHED" or "NORMAL")
	end
	self:UpdateState()
end, "script")

local PostDrag = Shared("OnDragStart / OnReceiveDrag after an action button of ours", function(self)
	self:UpdateState()
	self:UpdateFlash()
end, "script")

-- the secure wrappers (the header's restricted snippets)
local PRE_CLICK = [[
	if button == "Keybind" then
		self:SetAttribute("useOnKeyDown", self:GetParent():GetAttribute("mellokeydown") and true or false)
		return "LeftButton"
	end
	self:SetAttribute("useOnKeyDown", false)
]]
local DRAG_START = [[
	if self:GetParent():GetAttribute("mellolocked") and not IsModifiedClick("PICKUPACTION") then
		return false
	end
	local page = self:GetAttribute("actionpage")
	if not page then
		return false
	end
	return "action", self:GetID() + (page - 1) * 12
]]
local RECEIVE_DRAG = [[
	local page = self:GetAttribute("actionpage")
	if not (kind and page) then
		return false
	end
	return "action", self:GetID() + (page - 1) * 12
]]
local CHILD_PAGE = [[
	self:SetAttribute("actionpage", message)
	self:CallMethod("MelloAction")
]]
local ON_PAGE = [[
	self:SetAttribute("actionpage", newstate)
	control:ChildUpdate("actionpage", newstate)
]]

--------------------------------------------------------------------------------
-- Building (out of a fight only)
--------------------------------------------------------------------------------

local function GamePage(game, n)
	local p = Call(game, "GetAttribute", "actionpage")
	p = tonumber(p)
	return p or FIXED_PAGE[n]
end

-- Action Bar 1's page: this client's ActionBarController order as macro conditions (its indices read once)
local function PageDriver()
	local function Index(name, default)
		local fn = Api(name)
		local v
		if fn then
			local ok, r = pcall(fn)
			v = ok and Plain(r) or nil
		end
		return tonumber(v) or default
	end
	local vehicle = Index("GetVehicleBarIndex", 12)
	local override = Index("GetOverrideBarIndex", 14)
	local shift = Index("GetTempShapeshiftBarIndex", 13)
	return ("[vehicleui] %d; [overridebar] %d; [shapeshift] %d; [bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; "
		.. "[bar:6] 6; [bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; [bonusbar:5] 11; 1"):format(vehicle,
		override, shift)
end
A.PageDriver = PageDriver

local function GameButton(n, i)
	return rawget(_G, GAME_PREFIX[n] .. i)
end

local function NewButton(bar, n, i, page)
	local name = "MelloUIActionBar" .. n .. "Button" .. i
	-- (fr-18c, the sim proof: a click or a key on our button cast nothing) the secure template LAST: a template list is
	-- laid in its order, a later template's scripts over an earlier one's, and ActionButtonTemplate inherits
	-- FlyoutButtonTemplate, whose OnClick (Flyout_OnClick: TogglePopup) took the click from SecureActionButton_OnClick
	local ok, btn = pcall(CreateFrame, "CheckButton", name, bar, "ActionButtonTemplate, SecureActionButtonTemplate")
	if not ok or type(btn) ~= "table" then
		return nil
	end
	OB.mine[btn] = true
	for k, fn in pairs(B) do
		btn[k] = fn
	end
	-- (fr-18c, the sim proof: Action Bar 1's dividers drew over our buttons' frame corners) the game's buttons stand
	-- in containers a level over the bar, so two over it, above its dividers (the bar's children, one over it)
	btn:SetFrameLevel(bar:GetFrameLevel() + 2)
	local game = GameButton(n, i)
	btn:SetID(i)
	btn.bar, btn.index = bar, i
	btn.commandName = Field(game, "commandName") or (COMMAND[n] .. i)
	btn.bindingAction = btn.commandName
	btn:SetAttribute("type", "action")
	btn:SetAttribute("typerelease", "actionrelease")
	btn:SetAttribute("checkselfcast", true)
	btn:SetAttribute("checkfocuscast", true)
	btn:SetAttribute("checkmouseovercast", true)
	btn:SetAttribute("useOnKeyDown", false)
	btn:SetAttribute("actionpage", page)
	btn:SetAttribute("_childupdate-actionpage", CHILD_PAGE)
	-- (pings pass through ours: the game's ping reads a button's own fields, which addon code wrote here)
	pcall(btn.ClearAttribute, btn, "ping-receiver")
	btn:RegisterForClicks("AnyUp", "AnyDown")
	btn:RegisterForDrag("LeftButton", "RightButton")
	WrapScript(btn, "OnClick", bar, PRE_CLICK)
	WrapScript(btn, "OnDragStart", bar, DRAG_START)
	WrapScript(btn, "OnReceiveDrag", bar, RECEIVE_DRAG)
	-- (after the wrappers: these see the click as the engine gave it)
	Perf.HookScript(btn, "OnClick", PostClick)
	Perf.HookScript(btn, "OnDragStart", PostDrag)
	Perf.HookScript(btn, "OnReceiveDrag", PostDrag)
	Perf.HookScript(btn, "OnEnter", OnEnter)
	Perf.HookScript(btn, "OnLeave", OnLeave)
	if type(btn.UpdateButtonArt) == "function" then
		pcall(btn.UpdateButtonArt, btn)
	end
	local hidden = rawget(_G, "ActionButton_UpdateCooldownNumberHidden")
	if type(hidden) == "function" then
		pcall(hidden, btn)
	end
	btn.flashtime = 0
	return btn
end

-- the bar's art (Action Bar 1: the game's BorderArt and page number, MainActionBar.xml's, at its offsets)
local function PageText(bar)
	local page = bar.ActionBarPageNumber
	local fn = Api("GetActionBarPage")
	if page and fn then
		local ok, v = pcall(fn)
		page.Text:SetText(ok and tostring(Plain(v) or "") or "")
	end
end

local function PageButton(parent, name, action, atlas)
	local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	b:SetSize(17, 14)
	b:SetAttribute("type", "actionbar")
	b:SetAttribute("action", action)
	b:RegisterForClicks("AnyUp")
	-- (2.1.1) on the release, as every secure button of ours: with ActionButtonUseKeyDown on the template acts on a
	-- press, which a release-only button never hears (OwnSpecialBars.lua's stance buttons did nothing)
	b:SetAttribute("useOnKeyDown", false)
	b:SetNormalAtlas(atlas .. "-up")
	b:SetPushedAtlas(atlas .. "-down")
	b:SetDisabledAtlas(atlas .. "-disabled")
	b:SetHighlightAtlas(atlas .. "-mouseover")
	OB.mine[b] = true
	return b
end

local function MainArt(bar)
	local art = bar:CreateTexture(nil, "BACKGROUND", nil, -3)
	art:SetAtlas("UI-HUD-ActionBar-Frame")
	bar.BorderArt = art
	local page = CreateFrame("Frame", nil, bar)
	-- (fr-18c, the sim proof: half a pixel off the game's) the game's is a ResizeLayoutFrame round its children: its
	-- text (17 wide, its centre 1 left) and arrows (17 wide, centred) make it 18 wide
	page:SetSize(18, 34)
	-- (fr-18c, the sim proof: the page's number hidden under the gryphon) over the game's end caps, which stand at the
	-- game's page number's own level (100: both its bar's children there, the page number drawn over them)
	local caps = Field(rawget(_G, GAME_BARS[1]), "EndCaps")
	page:SetFrameLevel(math.max(bar:GetFrameLevel() + 50, (Finite(Call(caps, "GetFrameLevel")) or 0) + 1))
	page:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", -4, 9)
	page.Text = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	page.Text:SetSize(17, 10)
	page.Text:SetPoint("CENTER", page, "CENTER", -1, 0)
	page.UpButton = PageButton(page, "MelloUIActionBar1PageUp", "increment", "ui-hud-actionbar-pageuparrow")
	page.UpButton:SetPoint("CENTER", page, "CENTER", 0, 10)
	page.DownButton = PageButton(page, "MelloUIActionBar1PageDown", "decrement", "ui-hud-actionbar-pagedownarrow")
	page.DownButton:SetPoint("CENTER", page, "CENTER", 0, -10)
	bar.ActionBarPageNumber = page
	PageText(bar)
end

-- (the game's keys: the painted skin finds them as it found the game's)
local function DividerPool(bar)
	if bar.HorizontalDividersPool == nil then
		local make = rawget(_G, "CreateFramePool")
		local ok, pool = false, nil
		if type(make) == "function" then
			ok, pool = pcall(make, "FRAME", bar, "HorizontalDividerTemplate")
		end
		bar.HorizontalDividersPool = ok and pool or false
		local okV, vpool = false, nil
		if type(make) == "function" then
			okV, vpool = pcall(make, "FRAME", bar, "VerticalDividerTemplate")
		end
		bar.VerticalDividersPool = okV and vpool or false
	end
	return bar.HorizontalDividersPool, bar.VerticalDividersPool
end

-- the game's dividers between Action Bar 1's buttons (MainActionBarMixin:UpdateDividers): with its art, one row,
-- the least padding
local function LayDividers(bar, v)
	local h, vp = DividerPool(bar)
	if h then
		h:ReleaseAll()
	end
	if vp then
		vp:ReleaseAll()
	end
	if bar.hideBarArt or v.Rows > 1 or v.Padding > 2 then
		return
	end
	local pool = (v.Orientation == 0) and h or vp
	if not pool then
		return
	end
	local last = false
	for i, btn in ipairs(bar.actionButtons) do
		if i <= v.Icons then
			if last then
				local d = pool:Acquire()
				d:ClearAllPoints()
				if v.Orientation == 0 then
					d:SetPoint("TOP", btn, "TOP", 0, 0)
					d:SetPoint("BOTTOM", btn, "BOTTOM", 0, 0)
					d:SetPoint("RIGHT", btn, "LEFT", 5, 0)
				else
					d:SetPoint("LEFT", btn, "LEFT", 0, 0)
					d:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
					d:SetPoint("BOTTOM", btn, "TOP", 0, -5)
				end
				d:Show()
			end
			last = true
		end
	end
end

-- Action Bar 1's art shown or hidden (Action Bars' Hide Bar Art) and its page number (its Hide Page Arrows: the
-- module fades it -- Modules/ActionBars.lua's ApplyPageArrows reaches ours through MelloUI.OwnBars)
local function ArtWanted()
	local db = MelloUI:GetModuleDB("ActionBars")
	return not (db and db.hideBarArt == true)
end

local function LayArt(bar, v)
	if bar.index ~= 1 then
		return
	end
	bar.hideBarArt = not ArtWanted()
	local s = v.IconSize / 100
	local art = bar.BorderArt
	art:ClearAllPoints()
	art:SetPoint("TOPLEFT", bar, "TOPLEFT", -6 * s, 6 * s)
	art:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 4 * s, -5 * s)
	art:SetShown(not bar.hideBarArt)
	bar.ActionBarPageNumber:SetScale(s < 1 and s or 1)
	for _, btn in ipairs(bar.actionButtons) do
		if type(btn.UpdateButtonArt) == "function" then
			pcall(btn.UpdateButtonArt, btn)
		end
	end
	bar:UpdateDividers()
	A.CapsFollow()   -- (fr-18c: the end caps go with the art)
end

-- (the bar's methods under the game's names for the same jobs: a dresser that follows the game's bar -- the
-- backdrops, the painted rims and dividers -- follows ours)
local BAR = {}
function BAR.UpdateDividers(self)
	if self.index == 1 then
		LayDividers(self, Values(self.index))
	end
end

local function BuildBar(n)
	local game = rawget(_G, GAME_BARS[n])
	if type(game) ~= "table" then
		return nil
	end
	local bar = CreateFrame("Frame", "MelloUIActionBar" .. n, UIParent, "SecureHandlerStateTemplate")
	OB.mine[bar] = true
	bar.index = n
	bar.actionButtons = {}
	bar.numButtonsShowable = NUM
	bar:SetFrameStrata(Call(game, "GetFrameStrata") or "MEDIUM")
	local level = Finite(Call(game, "GetFrameLevel"))
	if level then
		bar:SetFrameLevel(level)
	end
	bar:SetSize(BUTTON * NUM, BUTTON)
	bar.GetSpellFlyoutDirection = function(self)
		return self.isHorizontal == false and "LEFT" or "UP"
	end
	for k, fn in pairs(BAR) do
		bar[k] = fn
	end
	-- (fr-18c, the sim proof: our Bars 2-8 wore the winged slot) the game's multi bars have no bar art: their buttons
	-- lay their art (BaseActionButtonMixin:UpdateButtonArt) before their bar is set and never again -- the plain slot
	-- and the AddRow frame; only Action Bar 1's art follows Hide Bar Art (LayArt)
	if n ~= 1 then
		bar.hideBarArt = true
	end
	Perf.HookScript(bar, "OnShow", A.BarShown)
	if n == 1 then
		-- (fr-18c: the game's end caps go with our Action Bar 1 -- A.CapsFollow; post-hooks on our own frame)
		Perf.HookScript(bar, "OnShow", A.CapsFollow)
		Perf.HookScript(bar, "OnHide", A.CapsGone)
		Perf.hooksecurefunc(bar, "SetAlpha", A.CapsFollow)
	end
	local page = (n == 1) and 1 or GamePage(game, n)
	if n == 1 then
		local fn = Api("GetActionBarPage")
		if fn then
			local ok, p = pcall(fn)
			page = ok and tonumber(Plain(p)) or 1
		end
		bar:SetAttribute("_onstate-page", ON_PAGE)
	end
	bar:SetAttribute("actionpage", page)
	for i = 1, NUM do
		local btn = NewButton(bar, n, i, page)
		if not btn then
			return nil
		end
		bar.actionButtons[i] = btn
		A.buttons[#A.buttons + 1] = btn
	end
	if n == 1 then
		MainArt(bar)
	end
	bar:Hide()
	return bar
end

-- a bar of ours shown (its driver): what its buttons show laid again (the frequent events pass hidden ones by)
A.BarShown = Shared("OnShow on an action bar of ours", function(bar)
	if OB.On(PART) then
		for _, btn in ipairs(bar.actionButtons) do
			if btn.action then
				btn:Update()
			end
		end
	end
end, "script")

local function Build()
	if A.built ~= nil then
		return A.built
	end
	WrapScript = rawget(_G, "SecureHandlerWrapScript")
	OverrideClick = rawget(_G, "SetOverrideBindingClick")
	if type(WrapScript) ~= "function" or type(OverrideClick) ~= "function" then
		return false
	end
	A.built = false
	for n = 1, #GAME_BARS do
		if type(rawget(_G, GAME_BARS[n])) ~= "table" then
			return false
		end
	end
	for n = 1, #GAME_BARS do
		local ok, bar = pcall(BuildBar, n)
		if not ok then
			geterrorhandler()(bar)
			return false
		end
		if not bar then
			return false
		end
		A.bars[n] = bar
		A.gameOf[bar] = rawget(_G, GAME_BARS[n])
		OB.gameOf[bar] = A.gameOf[bar]
	end
	A.events = CreateFrame("Frame")
	A.keys = CreateFrame("Frame")
	A.built = true
	return true
end

--------------------------------------------------------------------------------
-- Layout, visibility, keys (out of a fight; a change in one waits for its end, said once)
--------------------------------------------------------------------------------

A.grid = 0   -- a spell on the cursor (the game's ACTIONBAR_SHOWGRID): every empty button seen

local said = false
-- (quiet: a change the player did not make -- the game's keys or settings -- waits without a word)
local function Later(fn, key, quiet)
	if InCombatLockdown() then
		if not (said or quiet) then
			said = true
			MelloUI:Announce(TEXT.later)
		end
		MelloUI.Kit:WhenOutOfCombat(function()
			said = false
			fn()
		end, key)
		return true
	end
	return false
end

-- the game wants bar n shown (Options > Action Bars; Action Bar 1 always): its own flag, read (the game's bar itself
-- while ours are not built: the Fader's rows ask too, Fader.lua's BarOff)
local function GameWantsShown(n)
	if n == 1 then
		return true
	end
	local game = (A.bars[n] and A.gameOf[A.bars[n]]) or rawget(_G, GAME_BARS[n] or "")
	if type(game) ~= "table" then
		return true   -- (no bar to read: taken as shown)
	end
	local v = Field(game, "isShownExternal")
	if v == nil then
		return Call(game, "IsShown") and true or false
	end
	return v and true or false
end
A.GameWantsShown = GameWantsShown

local function VisibilityDriver(n, v)
	if not GameWantsShown(n) then
		return "hide"
	end
	local vis = v.Visible
	if vis == 1 then
		return "[petbattle] hide; [combat] show; hide"
	elseif vis == 2 then
		return "[petbattle] hide; [combat] hide; show"
	elseif vis == 3 then
		return "hide"
	end
	return "[petbattle] hide; show"
end

-- one bar laid from its settings: its buttons' grid (the game's GridLayoutUtil rule: a row of `stride` buttons, rows
-- growing up; upright, columns of `stride` growing down and to the right), their size, the bar's size, its art,
-- when it shows. Out of a fight. (The bar's UpdateGridLayout, the game's name.)
function BAR.UpdateGridLayout(bar)
	if InCombatLockdown() then
		return
	end
	local n = bar.index
	local v = Values(n)
	local s = v.IconSize / 100
	local pad = v.Padding
	local count = v.Icons
	local stride = math.ceil(count / v.Rows)
	-- (fr-18c, the sim proof: at an Icon Size under 100% our bars came out wider than the game's) the game scales each
	-- button's container by the Icon Size and lays them a padding apart in the container's own units
	-- (EditModeActionBarSystemMixin:UpdateSystemSettingIconSize, GridLayoutUtil): the padding scales with the icons.
	-- A step is a button and a padding in the button's units; the bar is the steps at the button's scale
	local step = BUTTON + pad
	local horizontal = v.Orientation == 0
	bar.isHorizontal = horizontal
	bar.numButtonsShowable = count
	bar.numRows = v.Rows
	bar.buttonPadding = pad
	bar.showGrid = v.ShowButtons and true or false
	for i, btn in ipairs(bar.actionButtons) do
		btn:ClearAllPoints()
		btn:SetScale(s)
		if i <= count then
			local k = i - 1
			if horizontal then
				local col, row = k % stride, math.floor(k / stride)
				btn:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", col * step, row * step)
			else
				local row, col = k % stride, math.floor(k / stride)
				btn:SetPoint("TOPLEFT", bar, "TOPLEFT", col * step, -row * step)
			end
			btn:Show()
		else
			btn:Hide()
		end
	end
	local lines = math.ceil(count / stride)
	local w, h
	local long, short = (stride * BUTTON + (stride - 1) * pad) * s, (lines * BUTTON + (lines - 1) * pad) * s
	if horizontal then
		w, h = long, short
	else
		w, h = short, long
	end
	bar:SetSize(w, h)
	local ph = A.placeholders and A.placeholders[n]
	if ph then
		ph[1], ph[2] = w, h
	end
	LayArt(bar, v)
	RegisterStateDriver(bar, "visibility", VisibilityDriver(n, v))
	for _, btn in ipairs(bar.actionButtons) do
		btn:UpdateShown()
		btn:UpdateHotkeys()
	end
	bar.laidFrom = A.Signature(n)
	-- (the Fader's On Mouseover is that module's own: the box's pick goes there)
	MelloUI:Fire("ownbars:actions", n)
end

local function LayNow(n)
	local bar = A.bars[n]
	if bar and not InCombatLockdown() then
		bar:UpdateGridLayout()
	end
end

-- (fr-18c) what a bar is laid from (its settings as they act now, the game's Options switch, Action Bar 1's art): a
-- follow pass lays again only a bar whose signature changed (the active layout's value of a setting not set)
function A.Signature(n)
	local v = Values(n)
	return table.concat({ v.Orientation, v.Rows, v.Icons, v.IconSize, v.Padding, tostring(v.Visible),
		tostring(v.ShowButtons), tostring(GameWantsShown(n)), n == 1 and tostring(ArtWanted()) or "" }, ":")
end

function A.Lay(n)
	if not OB.On(PART) then
		return
	end
	if Later(function() A.Lay(n) end, "Own Bars: the action bars laid again") then
		return
	end
	if n then
		LayNow(n)
	else
		for i = 1, #A.bars do
			LayNow(i)
		end
	end
	local P = MelloUI.EditLayout and MelloUI.EditLayout.Movers
	if P and P.SyncSoon then
		P.SyncSoon()   -- (Edit Layout's plates over the new sizes)
	end
	OB.FollowSoon()   -- (fr-18c: a bar's new size moves the bars stacked over it)
end

-- the game's settings the headers carry into the restricted snippets (out of a fight)
local function HeaderSettings()
	local keydown = GetCVarBool("ActionButtonUseKeyDown") and true or false
	local locked
	local S = rawget(_G, "Settings")
	if type(S) == "table" and type(S.GetValue) == "function" then
		local ok, v = pcall(S.GetValue, "lockActionBars")
		v = ok and Plain(v)
		if v ~= nil then
			locked = v and true or false
		end
	end
	-- (fr-18c, the sim proof: a plain drag took a spell off a locked bar) at the login's own frame the setting is not
	-- read yet -- the CVar it stands on then, and the setting again as the world is entered (the events, below)
	if locked == nil then
		locked = GetCVarBool("lockActionBars") and true or false
	end
	for _, bar in ipairs(A.bars) do
		bar:SetAttribute("mellokeydown", keydown)
		bar:SetAttribute("mellolocked", locked)
	end
end

-- the game's bindings on ours (its commands' keys, override bindings of ours); out of a fight
local function Bind()
	if not (A.keys and OB.On(PART)) then
		return
	end
	if Later(Bind, "Own Bars: the action bars' keys", true) then
		return
	end
	ClearOverrideBindings(A.keys)
	for _, btn in ipairs(A.buttons) do
		local keys = { GetBindingKey(btn.commandName) }
		for _, key in ipairs(keys) do
			if type(key) == "string" and key ~= "" then
				OverrideClick(A.keys, false, key, btn:GetName(), "Keybind")
			end
		end
		btn:UpdateHotkeys()
	end
end
A.Bind = Bind

--------------------------------------------------------------------------------
-- Events (one frame of ours for all our buttons)
--------------------------------------------------------------------------------

local function Each(fn)
	for _, btn in ipairs(A.buttons) do
		fn(btn)
	end
end

-- (the frequent events: only the buttons that hold an action and show -- a bar shown again lays its own, OnShow)
local function Live(fn)
	for _, btn in ipairs(A.buttons) do
		if btn.hasAction and btn:IsVisible() then
			fn(btn)
		end
	end
end

local function OnSlot(slot)
	slot = Plain(slot)
	if slot == 0 or slot == nil then
		Each(function(b) b:UpdateAction(true) end)
		return
	end
	local list = A.byAction[slot]
	for btn in pairs(list or {}) do
		btn:UpdateAction(true)
	end
end

local function ForAction(slot, fn)
	local list = A.byAction[Plain(slot) or -1]
	for btn in pairs(list or {}) do
		fn(btn)
	end
end

local function AlertEvent(spell, show)
	spell = Plain(spell)
	if not spell then
		return
	end
	Each(function(b)
		if AlertSpell(b) == spell then
			if show then
				b:ShowAlert()
			else
				b:HideAlert()
			end
		end
	end)
end

local EVENTS = { "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "GAME_PAD_ACTIVE_CHANGED",
	"UPDATE_SHAPESHIFT_FORM", "ACTIONBAR_UPDATE_STATE", "ACTIONBAR_UPDATE_USABLE", "ACTION_USABLE_CHANGED",
	"PLAYER_MOUNT_DISPLAY_CHANGED", "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "LOSS_OF_CONTROL_ADDED",
	"LOSS_OF_CONTROL_UPDATE", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
	"START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
	"SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "SPELL_UPDATE_CHARGES", "BAG_UPDATE_DELAYED", "SPELL_UPDATE_ICON",
	"UPDATE_SUMMONPETS_ACTION", "ACTION_RANGE_CHECK_UPDATE", "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID",
	"ACTIONBAR_PAGE_CHANGED", "CVAR_UPDATE", "PET_BAR_UPDATE", "PLAYER_REGEN_ENABLED", "COMPANION_UPDATE",
	"LEARNED_SPELL_IN_SKILL_LINE", "PET_STABLE_UPDATE" }
local UNIT_EVENTS = { "UNIT_INVENTORY_CHANGED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }

A.OnEvent = Shared("Own Bars: the action bars' events", function(_, event, a1, a2, a3)
	if not OB.On(PART) then
		return
	end
	if event == "ACTIONBAR_SLOT_CHANGED" then
		OnSlot(a1)
		A.DividersSoon()   -- (the game's main bar lays its dividers again: one made now faded)
	elseif event == "ACTION_USABLE_CHANGED" then
		if type(a1) == "table" and not Secret(a1) then
			for _, change in ipairs(a1) do
				if type(change) == "table" then
					local slot, usable, noMana = Plain(change.slot), Plain(change.usable), Plain(change.noMana)
					ForAction(slot, function(b) b:UpdateUsable(slot, usable, noMana) end)
				end
			end
		else
			Live(function(b) b:UpdateUsable() end)
		end
	elseif event == "ACTIONBAR_UPDATE_USABLE" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
		Live(function(b) b:UpdateUsable() end)
	elseif event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" or event == "LOSS_OF_CONTROL_ADDED"
		or event == "LOSS_OF_CONTROL_UPDATE" then
		Live(function(b)
			b:UpdateCooldown()
			if GameTooltip:GetOwner() == b then
				b:SetTooltip()
			end
		end)
	elseif event == "ACTIONBAR_UPDATE_STATE" or event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_CLOSE"
		or event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" or event == "COMPANION_UPDATE"
		or event == "PET_BAR_UPDATE" then
		Live(function(b) b:UpdateState() end)
	elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_SUMMONPETS_ACTION" then
		Each(function(b)
			local fn = Api("GetActionTexture")
			if b.action and fn then
				local ok, t = pcall(fn, b.action)
				if ok and t ~= nil then
					b.icon:SetTexture(t)
				end
			end
		end)
	elseif event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_LEAVE_COMBAT" or event == "START_AUTOREPEAT_SPELL"
		or event == "STOP_AUTOREPEAT_SPELL" then
		Live(function(b) b:UpdateFlash() end)
	elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
		AlertEvent(a1, true)
	elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
		AlertEvent(a1, false)
	elseif event == "SPELL_UPDATE_CHARGES" or event == "BAG_UPDATE_DELAYED" or event == "UNIT_INVENTORY_CHANGED" then
		Live(function(b) b:UpdateCount() end)
		if event == "UNIT_INVENTORY_CHANGED" then
			Each(function(b)
				if GameTooltip:GetOwner() == b then
					b:SetTooltip()
				end
			end)
		end
	elseif event == "ACTION_RANGE_CHECK_UPDATE" then
		local update = rawget(_G, "ActionButton_UpdateRangeIndicator")
		if type(update) == "function" and not (Secret(a2) or Secret(a3)) then
			ForAction(a1, function(b) pcall(update, b, a3, a2) end)
		end
	elseif event == "ACTIONBAR_SHOWGRID" or event == "ACTIONBAR_HIDEGRID" then
		A.grid = (event == "ACTIONBAR_SHOWGRID") and 1 or 0
		Each(function(b) b:UpdateShown() end)
		A.DividersSoon()
	elseif event == "ACTIONBAR_PAGE_CHANGED" then
		local bar = A.bars[1]
		if bar then
			PageText(bar)
		end
	elseif event == "UPDATE_BINDINGS" or event == "GAME_PAD_ACTIVE_CHANGED" then
		Bind()
	elseif event == "CVAR_UPDATE" then
		local cvar = Plain(a1)
		if (cvar == "ActionButtonUseKeyDown" or cvar == "lockActionBars" or cvar == nil)
			and not Later(HeaderSettings, "Own Bars: the action bars' key and lock settings", true) then
			HeaderSettings()
		end
		Each(function(b)
			local hidden = rawget(_G, "ActionButton_UpdateCooldownNumberHidden")
			if type(hidden) == "function" then
				pcall(hidden, b)
			end
		end)
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- (a bar the game showed or hid in the fight: laid with the rest of the queue)
		A.ShownAgain()
	else   -- PLAYER_ENTERING_WORLD, SPELL_UPDATE_ICON, LEARNED_SPELL_IN_SKILL_LINE, PET_STABLE_UPDATE
		Each(function(b) b:UpdateAction(true) end)
		-- (fr-18c: the game's key and lock settings and Action Bar 1's page number read again as the world is entered:
		-- the login's frame came first -- the sim proof: the page number stood empty, its page not read yet)
		if event == "PLAYER_ENTERING_WORLD" then
			if A.bars[1] then
				PageText(A.bars[1])
			end
			if not Later(HeaderSettings, "Own Bars: the action bars' key and lock settings", true) then
				HeaderSettings()
			end
		end
	end
end, "script")

-- a bar the game's Options turned on or off (its MultiActionBar_Update, post-hooked: visuals and our own frames
-- only): its driver again, out of a fight
function A.ShownAgain()
	if not OB.On(PART) then
		return
	end
	local changed = false
	for n = 2, #A.bars do
		local want = GameWantsShown(n)
		if A.wantShown[n] ~= want then
			A.wantShown[n] = want
			changed = true
		end
	end
	if changed then
		A.Lay()
	end
end

--------------------------------------------------------------------------------
-- The game's bars kept away and given back
--------------------------------------------------------------------------------

-- every part of the game's bar n that shows or takes the pointer (Action Bar 1: not the frame -- its end caps)
local function GameParts(n, fn)
	local game = A.gameOf[A.bars[n]]
	if type(game) ~= "table" then
		return
	end
	local buttons = Field(game, "actionButtons")
	for _, btn in ipairs(type(buttons) == "table" and buttons or {}) do
		fn("mouse", btn)
		if n == 1 then
			fn("alpha", Field(btn, "container"))
		end
	end
	fn("select", game)
	if n == 1 then
		fn("mouse", game)
		fn("alpha", Field(game, "BorderArt"))
		local page = Field(game, "ActionBarPageNumber")
		fn("alpha", page)
		fn("mouse", Field(page, "UpButton"))
		fn("mouse", Field(page, "DownButton"))
	else
		fn("alpha", game)
	end
end

-- (fr-18c, the sim proof: the game's Action Bar 1 dividers were drawn over ours) the game lays its main bar's
-- dividers again whenever its buttons' shown state changes (MainActionBarMixin:UpdateDividers from
-- UpdateShownButtons: a slot changed, the grid, its layout), from two pools of its own -- one made after ours stood
-- in was seen. Each divider faded once keeps its alpha in the pool; one made later is faded on the next look (ours
-- stand in, a follow pass, the slot and grid events, on the next frame). Read only: nothing acquired, nothing hooked.
A.dividersAway = setmetatable({}, { __mode = "k" })
local function DividersAway()
	A.dividersSoon = false
	local game = OB.On(PART) and A.gameOf[A.bars[1]]
	if type(game) ~= "table" then
		return
	end
	for _, key in ipairs({ "HorizontalDividersPool", "VerticalDividersPool" }) do
		local pool = Field(game, key)
		if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
			local ok, iter, state, start = pcall(pool.EnumerateActive, pool)
			if ok and type(iter) == "function" then
				for d in iter, state, start do
					if not A.dividersAway[d] then
						A.dividersAway[d] = true
						K.Fade(d)
					end
				end
			end
		end
	end
end
A.DividersAway = DividersAway
A.DividersSoon = Shared("Own Bars: the game's main bar dividers", function()
	if not A.dividersSoon and OB.On(PART) then
		A.dividersSoon = true
		C_Timer.After(0, DividersAway)
	end
end, "script")

-- (the configurator walk's round 2, 2026-11-04: Action Bar 3 to 8 switched on with no spell in them showed nothing, the
-- switch looked dead) while the configurator or Edit Layout is open every empty button is seen, in the bars' own slot
-- look; closed, an empty bar is unseen again (the buses 'configurator' and 'editlayout')
A.setupOpen, A.setupBy = false, { config = false, layout = false }
A.ShowEmpty = function(b)
	b:UpdateShown()
end
function A.SetupOpen(which, on)
	A.setupBy[which] = on and true or false
	local open = A.setupBy.config or A.setupBy.layout
	if open ~= A.setupOpen then
		A.setupOpen = open
		Each(A.ShowEmpty)
		A.DividersSoon()
	end
end
MelloUI:On("configurator", function(shown)
	A.SetupOpen("config", shown)
end, "Own Bars: empty buttons while the configurator shows")
MelloUI:On("editlayout", function(showing)
	A.SetupOpen("layout", showing)
end, "Own Bars: empty buttons while Edit Layout shows")

-- (fr-18c, the sim proof: the gryphons stayed while our Action Bar 1 faded) the game's end caps -- an Edit Mode system
-- of their own inside the game's Action Bar 1, which stays the game's -- went with that bar: faded with it (the Fader)
-- and gone with it (Bar Visible). They go with ours so: our bar's alpha (its own SetAlpha, post-hooked: ours) and its
-- shown state (its OnShow / OnHide) carried onto them, alpha only; their own alpha given back with the rest.
A.caps = {}   -- base: the end caps' alpha before ours (nil: never written)
local function CapsTo(gone)
	local bar = A.bars[1]
	local caps = Field(A.gameOf[bar], "EndCaps")
	if not (bar and type(caps) == "table" and OB.On(PART)) then
		return
	end
	if A.caps.base == nil then
		A.caps.base = Finite(Call(caps, "GetAlpha")) or 1
	end
	-- (and with the bar's art: the game's main bar hides its end caps with its art -- UpdateEndCaps(hideBarArt))
	local a = (gone or bar.hideBarArt or not bar:IsShown()) and 0 or (Finite(Call(bar, "GetAlpha")) or 1)
	pcall(caps.SetAlpha, caps, A.caps.base * a)
	-- (the bus, on a change: what dresses the caps with frames of its own on the game's bar -- the painted skin's orbs
	-- and their shadows -- takes the same alpha)
	if A.caps.told ~= a then
		A.caps.told = a
		MelloUI:Fire("ownbars:caps", a)
	end
end
function A.CapsFollow()
	CapsTo(false)
end
-- (its OnHide: gone, whatever IsShown answers while the script runs)
function A.CapsGone()
	CapsTo(true)
end

local function CapsBack()
	local caps = Field(A.gameOf[A.bars[1]], "EndCaps")
	if A.caps.base ~= nil and type(caps) == "table" then
		pcall(caps.SetAlpha, caps, A.caps.base)
	end
	A.caps.base = nil
	if A.caps.told ~= nil and A.caps.told ~= 1 then
		MelloUI:Fire("ownbars:caps", 1)
	end
	A.caps.told = nil
end

local function Away()
	for n = 1, #A.bars do
		GameParts(n, function(kind, f)
			if kind == "mouse" then
				K.MouseOff(f)
			elseif kind == "alpha" then
				K.Fade(f)
			elseif kind == "select" then
				K.SelectionAway(f)
			end
		end)
		local U = K.Units()
		local game = A.gameOf[A.bars[n]]
		if U and type(game) == "table" then
			U.Silence(game, GRID_EVENTS, OWNER, 0)
		end
	end
end

local function Back()
	local U = K.Units()
	if U then
		U.Unsilence(OWNER)
	end
	for n = 1, #A.bars do
		GameParts(n, function(kind, f)
			if kind == "mouse" then
				K.MouseBack(f)
			elseif kind == "alpha" then
				K.Unfade(f)
			elseif kind == "select" then
				K.SelectionBack(f)
			end
		end)
	end
	for d in pairs(A.dividersAway) do
		K.Unfade(d)
	end
	A.dividersAway = setmetatable({}, { __mode = "k" })
	CapsBack()
end

--------------------------------------------------------------------------------
-- Places, on and off
--------------------------------------------------------------------------------

-- (fr-18c) every bar where it should stand: a place of its own where the store says; else following the game's bar,
-- or in the bottom stack laid on ours (Bars 2 and 3 with the game's in its default place). A bar whose settings act
-- differently now (the active layout changed one not set) is laid again first, so the stack sees its size. Secure
-- frames: out of a fight; in one, after it, quietly.
local function BarsFollow()
	DividersAway()   -- (alpha only: in a fight too)
	if not OB.On(PART) or Later(BarsFollow, "Own Bars: the action bars placed", true) then
		return
	end
	for n, bar in ipairs(A.bars) do
		if bar.laidFrom ~= A.Signature(n) then
			LayNow(n)
		end
	end
	local slots = K.StackPlaces()
	local changed = false
	for _, bar in ipairs(A.bars) do
		if K.Place(bar) then
			changed = K.StackOrGame(bar, A.gameOf[bar], slots) or changed
		end
	end
	if changed then
		MelloUI:Fire("bagbar")   -- (Action Bars' backdrops laid round them again)
	end
end
OB.followers[PART] = BarsFollow

-- (the stack takes a bar of ours as the game's takes its bar: while the game's Options show it -- its visibility
-- setting does not free its row, EditModeActionBarMixin:IsShownOverride)
for n = 1, 3 do
	OB.shownInStack[GAME_BARS[n]] = function()
		return GameWantsShown(n)
	end
end

local hooked = false
local function HookOnce()
	if hooked then
		return
	end
	hooked = true
	-- (the game's Options > Action Bars turned a bar on or off: MultiActionBar_Update, a post-hook)
	if type(rawget(_G, "MultiActionBar_Update")) == "function" then
		Perf.hooksecurefunc("MultiActionBar_Update", function()
			if OB.On(PART) then
				C_Timer.After(0, A.ShownAgain)
			end
		end)
	end
end

local function On()
	if InCombatLockdown() or not Build() then
		return false
	end
	Away()
	for n, bar in ipairs(A.bars) do
		OB.own[GAME_BARS[n]] = bar
		for i, btn in ipairs(bar.actionButtons) do
			OB.own[GAME_PREFIX[n] .. i] = btn
		end
	end
	OB.own.MainMenuBar = A.bars[1]
	OB.standing[PART] = true
	A.placeholders = A.placeholders or {}
	for n, bar in ipairs(A.bars) do
		A.wantShown[n] = GameWantsShown(n)
		local ph = A.placeholders[n] or {}
		A.placeholders[n] = ph
		LayNow(n)
		local anchor = Values(n).Orientation == 0 and "BOTTOM" or "RIGHT"
		K.Register(bar, PART, bar:GetName(), LABELS[n], ph, anchor)
		local keys = {}
		for _, s in ipairs(SUFFIXES) do
			keys[#keys + 1] = Key(n, s)
		end
		if n == 1 then
			keys[#keys + 1] = "ActionBars.hideBarArt"
			keys[#keys + 1] = "ActionBars.hidePageArrows"
		end
		if MelloUI.EditLayoutOptions then
			MelloUI:EditLayoutOptions(bar, { module = M.name, keys = keys })
		end
	end
	for _, bar in ipairs(A.bars) do
		OB.followed[bar] = nil
	end
	BarsFollow()
	K.FollowListen()
	-- Action Bar 1's page from the game's state (its driver: the page changes in a fight, securely)
	RegisterStateDriver(A.bars[1], "page", PageDriver())
	HeaderSettings()
	A.events:SetScript("OnEvent", A.OnEvent)
	for _, e in ipairs(EVENTS) do
		pcall(A.events.RegisterEvent, A.events, e)
	end
	for _, e in ipairs(UNIT_EVENTS) do
		pcall(A.events.RegisterUnitEvent, A.events, e, "player")
	end
	HookOnce()
	Each(function(b) b:UpdateAction(true) end)
	Bind()
	DividersAway()
	A.CapsFollow()
	return true
end

local function Off()
	OB.standing[PART] = nil
	for n, bar in ipairs(A.bars) do
		if OB.own[GAME_BARS[n]] == bar then
			OB.own[GAME_BARS[n]] = nil
		end
		for i = 1, NUM do
			OB.own[GAME_PREFIX[n] .. i] = nil
		end
		UnregisterStateDriver(bar, "visibility")
		bar:Hide()
	end
	if A.bars[1] then
		UnregisterStateDriver(A.bars[1], "page")
	end
	OB.own.MainMenuBar = nil
	if A.events then
		A.events:UnregisterAllEvents()
	end
	if A.keys then
		ClearOverrideBindings(A.keys)
	end
	for btn in pairs(flashing) do
		btn:StopFlash()
	end
	Back()
end

OB.AddPart({ id = PART, on = On, off = Off, secure = true })
OB.AddSystem("ActionBar", PART, { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
	[8] = true })
for n = 1, #GAME_BARS do
	OB.AddKey("MelloUIActionBar" .. n)
end

--------------------------------------------------------------------------------
-- A setting changed (Own Bars' per-bar options; Action Bars' Hide Bar Art, its bus)
--------------------------------------------------------------------------------

-- "bar<n><Suffix>" -> n, suffix
local function Parse(key)
	if type(key) ~= "string" then
		return nil
	end
	local n, suffix = key:match("^bar(%d)(%a+)$")
	n = tonumber(n)
	if n and n >= 1 and n <= #GAME_BARS and SPEC[suffix] then
		return n, suffix
	end
	return nil
end
A.Parse = Parse

-- (the box's On Mouseover is the Fader's own: its "show_bar<n>", the bar itself Always meanwhile; another pick puts
-- a bar the Fader held back to Always there)
local function FaderPick(n, value)
	local F = MelloUI:GetModuleDB("Fader")
	local key = "show_bar" .. n
	if value == MOUSEOVER then
		if F and F[key] ~= MOUSEOVER then
			MelloUI:NotifySettingChanged("Fader", key, MOUSEOVER)
		end
	elseif F and F[key] == MOUSEOVER then
		MelloUI:NotifySettingChanged("Fader", key, "always")
	end
end

function A.SettingChanged(key, value)
	local n, suffix = Parse(key)
	if not n then
		return false
	end
	if suffix == "Visible" then
		FaderPick(n, value)
	end
	A.Lay(n)
	return true
end

MelloUI:On("setting", function(module, key)
	if module == "ActionBars" and key == "hideBarArt" and OB.On(PART) then
		A.Lay(1)
	end
end, "Own Bars: Action Bar 1's art")

--------------------------------------------------------------------------------
-- /run MelloUI.OwnBars.Actions.Dump(print)
--------------------------------------------------------------------------------

function A.Dump(out)
	out = out or print
	out(("Own Bars, the action bars: standing %s, built %s, %d buttons, keys bound by override"):format(
		tostring(OB.On(PART)), tostring(A.built), #A.buttons))
	for n, bar in ipairs(A.bars) do
		local v = Values(n)
		local l, b, r, t = Safe.ScreenRect(bar)
		out(("  %s: shown %s, page %s, %s, rows %d, icons %d, size %d%%, padding %d, visible %s, rect %s"):format(
			bar:GetName(), tostring(bar:IsShown()), tostring(bar:GetAttribute("actionpage")),
			v.Orientation == 0 and "horizontal" or "vertical", v.Rows, v.Icons, v.IconSize, v.Padding, tostring(v.Visible),
			l and ("%.0f,%.0f-%.0f,%.0f"):format(l, b, r, t) or "-"))
	end
end
