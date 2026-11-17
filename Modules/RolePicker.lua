--------------------------------------------------------------------------------
-- MelloUI - Role Picker (2.1.55; MelloUI.RolePicker)
--
-- A role choice above your character as you enter a dungeon or a raid. The user, 2026-11-16: "every time i enter a
-- instance, above my character there appears a role selection, either tank heal or dps depending on what the class
-- can do, and when i click on it, it assigns that role to me", then "And a checkbox that asks if i want to save that
-- role for future dungeons, so that i dont have to reselect it every time". The sketches
-- (BuildData/output/role_picker_sketch): look A, three pictures in the open with their names under them and the box
-- on a small dark plate; then "B, 4, B": the pictures on MelloUI's gold ring (Modern; Oldschool's painted ones, the
-- Default skin's the game's group finder medallions -- MelloUI.Icons and Skin.Icon pick by the look), they drop in
-- from above and bounce once, one after another, and your pick swells over the icon set's star burst, then fades.
--
-- When: entering a dungeon or a raid (IsInInstance: "party" / "raid") while in a group -- a role exists only in one --
-- or a group formed while inside; never after a /reload inside, never in a group the game's finder made (its roles
-- are its own: HasLFGRestrictions). Once an entry. Only the roles the class can take (UnitGetAvailableRoles, the
-- game's own answer; a class table if it says nothing readable); a class with one role gets it set with no picker.
-- Your role now is lit. A click: UnitSetRole and the on-screen line; the box ticked: that role kept (Role On
-- Entering, per profile, so per character) and set by itself at the next entries, with no picker. It hides in a
-- fight and comes back after it if nothing was picked; Escape (the game's own walk), the pad's B or leaving the
-- dungeon or the group closes it. Its place: above the character on the game's screen (MelloUI:PlayPoint: with
-- Offhand's two screens on its main one, laid again as Offhand lays its screens anew, until the player gives it a
-- place of their own), moved and sized in Edit Layout ("Role Picker"). The pad walks it (MelloUI.Gamepad). On from the
-- start (the user, 2026-11-16: "Turn it on"), its switch in Quality of Life > Role Picker; its motion's switch on the
-- Animations page. Nothing at login: its frame is made at its first show.
--
--   MelloUI.RolePicker.Show(preview) -> shown   the picker now (preview: the Animations page's Play, a pick sets
--                                              nothing)
--   /mello roles show | pick                   the picker as it would come, the Play
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Safe = MelloUI.Safe
local Secret, Num = Safe.IsSecret, Safe.Number
local Perf = MelloUI.Perf:Scope("Role picker")
local Shared = Perf.Shared
local C_Timer = Perf.C_Timer
local max, min = math.max, math.min

local M = MelloUI:RegisterModule("RolePicker", {
	title = "Role Picker",
	play = "pick",   -- its motion row's Play, the Animations page
	slash = "roles",   -- /mello roles show | pick
	desc = "As you enter a dungeon or a raid in a group, the roles your class can take appear above your character: click one and it is yours. Tick Remember for future dungeons and the next ones set it by themselves.",
	icon = "Interface\\Icons\\INV_Shield_06",
	flavour = "Tank, heal or hit: one click at the door.",
	enabledByDefault = true,   -- (the user, 2026-11-16: "Turn it on")
	defaults = {
		remember = "ask",
		motion = true,
	},
	options = {
		{ type = "dropdown", key = "remember", name = "Role On Entering",
		  desc = "Ask Every Time shows the roles as you enter. A role set here is yours at every dungeon and raid you enter in a group, with no picker. Remember for future dungeons on the picker sets it too.",
		  values = { { value = "ask", label = "Ask Every Time" }, { value = "TANK", label = "Tank" },
			{ value = "HEALER", label = "Healer" }, { value = "DAMAGER", label = "Damage" } } },
		{ type = "toggle", key = "motion", name = "Role Picker Motion", play = "pick",
		  desc = "The roles drop in above your character one after another, and the one you pick swells over a star burst. Off: they show and go at once." },
	},
})
MelloUI.RolePicker = M

-- (one table: the file's numbers and its parts) sizes in UIParent units
local R = {
	KEY = "RolePicker",            -- its place in Edit Layout's store
	SIZE = 44,                     -- a picture's size
	GAP = 14,                      -- between the pictures
	NAME_GAP = 3, NAME_H = 12,     -- the picture to its name, the name's height
	BOX_GAP = 7, BOX_H = 20,       -- the names to the box's plate, the plate's height
	CHECK = 16, CHECK_PAD = 5, LABEL_PAD = 6, END_PAD = 10,
	UP = 50,                       -- its foot over the game screen's middle (just over the character's head)
	DROP = 40, BOUNCE = 7,         -- the drop's height, the bounce's
	STAGGER = 0.09, FALL = 0.48,   -- one picture after the other, each one's fall
	NAMES_AFTER = 0.3, NAMES_T = 0.22, BOX_T = 0.26,
	PICK = 0.92,                   -- the pick's whole length
	SWELL = 1.25, BURST = 2.5,     -- the pick's swell, the burst's size against the picture
	LEAVE = 0.26,                  -- closed without a pick
	PREVIEW_PICK = 1.4,            -- the Play's pick after its drop
	ROLES = { "TANK", "HEALER", "DAMAGER" },
	ICON = { TANK = "role_tank", HEALER = "role_healer", DAMAGER = "role_damage" },
	WORD = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" },
	-- the game's own names for the roles (its language)
	GLOBAL = { TANK = "TANK", HEALER = "HEALER", DAMAGER = "DAMAGER" },
	-- what each class can take when the game's own answer reads as nothing (its classes in this client)
	CLASS = { WARRIOR = { "TANK", "DAMAGER" }, PALADIN = { "TANK", "HEALER", "DAMAGER" },
		DRUID = { "TANK", "HEALER", "DAMAGER" }, PRIEST = { "HEALER", "DAMAGER" }, SHAMAN = { "HEALER", "DAMAGER" } },
	ICONS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\",
}
-- the texts it draws or says (Tools/languages/strings.py reads this table)
local TEXT = {
	said = "Role: %s",
	saidKept = "Role: %s (remembered)",
	remember = "Remember for future dungeons",
	off = "The Role Picker is off: switch it on in Quality of Life > Role Picker.",
}
local S = { roles = {} }   -- the state: inside, handled, waiting, assign, preview, picked, remember, shown roles
local B = {}               -- the parts: frame, medals, box, plate, check, tick, label

--------------------------------------------------------------------------------
-- The game's answers (secret-safe: every one asked in a pcall and tested before it is used)
--------------------------------------------------------------------------------

local function Ask(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c = pcall(fn, ...)
	if not ok or Secret(a) or Secret(b) or Secret(c) then
		return nil
	end
	return a, b, c
end

local function InDungeon()
	local inside, kind = Ask(IsInInstance)
	return inside == true and (kind == "party" or kind == "raid")
end

local function Grouped()
	return Ask(IsInGroup) == true
end

-- a group the game's finder made: its roles are the finder's
local function FinderGroup()
	return Ask(rawget(_G, "HasLFGRestrictions")) == true
end

local function Current()
	local role = Ask(rawget(_G, "UnitGroupRolesAssigned"), "player")
	return type(role) == "string" and role or "NONE"
end

-- the roles the class can take, in the game's order
local function ClassRoles()
	local t, h, d = Ask(rawget(_G, "UnitGetAvailableRoles"), "player")
	if t or h or d then
		local list = {}
		if t then list[#list + 1] = "TANK" end
		if h then list[#list + 1] = "HEALER" end
		if d then list[#list + 1] = "DAMAGER" end
		return list
	end
	local _, class = Ask(UnitClass, "player")
	return R.CLASS[class] or { "DAMAGER" }
end

local function Has(list, role)
	for i = 1, #list do
		if list[i] == role then
			return true
		end
	end
	return false
end

local function Label(role)
	local g = rawget(_G, R.GLOBAL[role] or "")
	if type(g) == "string" and g ~= "" then
		return g
	end
	return MelloUI.Lang.T(R.WORD[role] or role)
end

local function Moving()
	return M.db and M.db.motion ~= false and not MelloUI.Anim.reduceMotion
end

--------------------------------------------------------------------------------
-- Setting the role
--------------------------------------------------------------------------------

-- the role set (out of a fight: a fight waits for its end); said once on the screen when it changed
local function Assign(role, remembered)
	if Current() == role then
		return true
	end
	if InCombatLockdown() then
		S.assign, S.assignKept = role, remembered
		return false
	end
	local set = rawget(_G, "UnitSetRole")
	if type(set) ~= "function" then
		return false
	end
	local ok, done = pcall(set, "player", role)
	ok = ok and not Secret(done) and done ~= false
	if ok then
		MelloUI:Announce(MelloUI.Lang.F(remembered and TEXT.saidKept or TEXT.said, Label(role)), "info")
	end
	return ok
end

--------------------------------------------------------------------------------
-- The picker's frame (made at its first show)
--------------------------------------------------------------------------------

-- its own place: its foot over the game screen's middle (the rule: MelloUI:PlayPoint, never the UI's middle)
local function Home(f)
	MelloUI:PlayPoint(f, "BOTTOM", "CENTER", 0, R.UP)
	return true
end

-- a picture at (x, y) from the frame's top middle (its middle), at scale s: kept on its spot while it grows
local function Put(b, x, y, s)
	s = s or 1
	if b.s ~= s then
		b:SetScale(s)
		b.s = s
		MelloUI.Widgets.RoundIconRefit(b)
	end
	b:ClearAllPoints()
	b:SetPoint("CENTER", B.frame, "TOP", x / s, y / s)
end

local function Width(n)
	return n * R.SIZE + (n - 1) * R.GAP
end

local function Close(moving)
	local f = B.frame
	if not f or not f:IsShown() then
		return
	end
	S.waiting = nil
	MelloUI.Anim:Stop(f, "drive")
	if moving and Moving() then
		MelloUI.Anim:To(f, "alpha", 0, R.LEAVE, "inQuad", function(frame)
			frame:Hide()
		end)
	else
		f:Hide()
	end
end

-- the lit picture: your role now
local function Light()
	local now = Current()
	for _, role in ipairs(R.ROLES) do
		local b = B.medals[role]
		b.glow:SetShown(b:IsShown() and role == now and not S.picked)
	end
end

local PickClick   -- (below)

local CheckClick = Shared("OnClick on the role picker's box", function()
	S.remember = not S.remember
	B.tick:SetShown(S.remember)
	MelloUI:PlayUISound(S.remember and "check_on" or "check_off")
end, "script")

local Hidden = Shared("OnHide on the role picker", function(f)
	MelloUI.Anim:Stop(f, "drive")
	MelloUI.Anim:Stop(f, "alpha")
	f:SetAlpha(1)
	S.preview = nil
end, "script")

local function Build()
	local W = MelloUI.Widgets
	local f = CreateFrame("Frame", "MelloUIRolePicker", UIParent)
	f:SetFrameStrata("MEDIUM")
	f:SetFrameLevel(20)
	f:SetSize(Width(3), R.SIZE + R.NAME_GAP + R.NAME_H + R.BOX_GAP + R.BOX_H)
	f:EnableMouse(false)
	f:Hide()
	Home(f)
	B.frame = f
	B.medals = {}
	for _, role in ipairs(R.ROLES) do
		local b = W.RoundIcon(f, R.SIZE, R.ICONS .. R.ICON[role])
		b.role = role
		-- your role now: the set's gold light behind it
		local glow = b:CreateTexture(nil, "BACKGROUND", nil, -6)
		glow:SetSize(R.SIZE * 1.7, R.SIZE * 1.7)
		glow:SetPoint("CENTER", b, "CENTER", 0, 0)
		W.Icon(glow, "hover_glow", R.SIZE * 1.7)
		glow:SetBlendMode("ADD")
		glow:Hide()
		b.glow = glow
		local name = W.Text(f, "MelloUIFont_GameFontHighlightSmall", nil, "text")
		name:SetJustifyH("CENTER")
		name:SetText(Label(role))
		b.name = name
		Perf.SetScript(b, "OnClick", PickClick)
		B.medals[role] = b
	end
	-- the box on its small dark plate
	local box = CreateFrame("Button", nil, f)
	box:SetHeight(R.BOX_H)
	local label = W.Text(box, "MelloUIFont_GameFontHighlightSmall", TEXT.remember, "text")
	label:SetPoint("LEFT", box, "LEFT", R.CHECK_PAD + R.CHECK + R.LABEL_PAD, 0)
	local textW = Num(label:GetStringWidth()) or 150
	box:SetWidth(R.CHECK_PAD + R.CHECK + R.LABEL_PAD + textW + R.END_PAD)
	B.plate = W.RoundPlate(box, { shape = "pill", fill = "innerPanel", fillAlpha = 0.86, edge = "border" })
	local check = box:CreateTexture(nil, "ARTWORK")
	check:SetSize(R.CHECK, R.CHECK)
	check:SetPoint("LEFT", box, "LEFT", R.CHECK_PAD, 0)
	W.Icon(check, "ctl_check_off", R.CHECK)
	local tick = box:CreateTexture(nil, "ARTWORK", nil, 1)
	tick:SetSize(R.CHECK, R.CHECK)
	tick:SetPoint("CENTER", check, "CENTER", 0, 0)
	W.Icon(tick, "ctl_check_on", R.CHECK)
	tick:Hide()
	Perf.SetScript(box, "OnClick", CheckClick)
	B.box, B.tick, B.label = box, tick, label
	-- a burst of light behind the pick: the icon set's quest-done star burst (8 frames, played smooth: W.Flipbook)
	local burst = {}
	for i = 1, 2 do
		local t = f:CreateTexture(nil, "BACKGROUND", nil, -7)
		t:SetTexture(W.IconPath("fx_questdone"))
		t:SetBlendMode("ADD")
		t:SetSize(R.SIZE * R.BURST, R.SIZE * R.BURST)
		t:Hide()
		burst[i] = t
	end
	B.burst, B.burstNext = burst[1], burst[2]
	f:SetScript("OnHide", Hidden)   -- (before the mover: it hooks the frame's scripts)
	-- Escape closes it (the game's own walk of the list hides it)
	tinsert(UISpecialFrames, "MelloUIRolePicker")
	-- the pad: the D-pad walks the pictures and the box, A picks, B closes
	local G = MelloUI.Gamepad
	if G and G.Window then
		G.Window(f, { back = function()
			Close(true)
			return true
		end, first = function()
			local lit = B.medals[Current()]
			if lit and lit:IsShown() then
				return lit
			end
			return B.medals[S.roles[1]]
		end })
	end
	B.entry = MelloUI:RegisterMover(f, f, { key = R.KEY, anchor = "BOTTOM", default = Home, min = 0.5, max = 2, base = 1,
		label = "Role Picker", page = "RolePicker", category = "misc", placeholder = true,
		when = function() return M.isEnabled == true end })
	return f
end

-- the pictures of these roles in a row, their names under them, the box under the names
local function Lay(roles)
	local f = B.frame or Build()
	S.roles = roles
	local n = #roles
	local total = Width(n)
	f:SetWidth(max(total, Num(B.box:GetWidth()) or total))
	for _, role in ipairs(R.ROLES) do
		local b = B.medals[role]
		b:Hide()
		b.name:Hide()
	end
	for i, role in ipairs(roles) do
		local b = B.medals[role]
		b.x = -total / 2 + R.SIZE / 2 + (i - 1) * (R.SIZE + R.GAP)
		b.i = i
		Put(b, b.x, -R.SIZE / 2, 1)
		b:SetAlpha(1)
		b:Show()
		b.name:ClearAllPoints()
		b.name:SetPoint("TOP", f, "TOP", b.x, -(R.SIZE + R.NAME_GAP))
		b.name:SetAlpha(1)
		b.name:Show()
	end
	B.box:ClearAllPoints()
	B.box:SetPoint("TOP", f, "TOP", 0, -(R.SIZE + R.NAME_GAP + R.NAME_H + R.BOX_GAP))
	B.box:SetAlpha(1)
	B.burst:Hide()
	B.burstNext:Hide()
end

--------------------------------------------------------------------------------
-- The motions (each one Anim:Drive over the whole picker, a function of its time; Reduce Motion or the motion's
-- switch off: its end at once)
--------------------------------------------------------------------------------

local function Smooth(p)
	p = p < 0 and 0 or (p > 1 and 1 or p)
	return p * p * (3 - 2 * p)
end

-- 4, Drop: each picture falls in from above, lands, bounces once; its name after it, the box last
function R.DropStep(f, u)
	local n = #S.roles
	local t = u * R.DropLength(n)
	for _, role in ipairs(S.roles) do
		local b = B.medals[role]
		local local_t = (t - (b.i - 1) * R.STAGGER) / R.FALL
		local y
		if local_t <= 0 then
			y = R.DROP
		elseif local_t < 0.55 then
			local p = local_t / 0.55
			y = R.DROP * (1 - p * p)   -- falling, faster as it goes
		elseif local_t < 0.75 then
			y = R.BOUNCE * Smooth((local_t - 0.55) / 0.2)
		else
			y = R.BOUNCE * (1 - Smooth((local_t - 0.75) / 0.25))
		end
		Put(b, b.x, -R.SIZE / 2 + y, 1)
		b:SetAlpha(min(1, max(0, local_t / 0.3)))
		local nt = t - (b.i - 1) * R.STAGGER - R.NAMES_AFTER
		b.name:SetAlpha(min(1, max(0, nt / R.NAMES_T)))
	end
	local bt = t - (n * R.STAGGER + R.NAMES_AFTER)
	B.box:SetAlpha(min(1, max(0, bt / R.BOX_T)))
end

function R.DropLength(n)
	return (n - 1) * R.STAGGER + max(R.FALL, R.NAMES_AFTER + R.NAMES_T) + R.STAGGER + R.BOX_T
end

-- b, Star burst: the pick swells over the burst and settles, the others shrink away, the names and the box go; then
-- the pick fades and the picker hides
function R.PickStep(f, u)
	local t = u * R.PICK
	local pick = S.picked and B.medals[S.picked]
	for _, role in ipairs(S.roles) do
		local b = B.medals[role]
		local a = 1 - Smooth(t / 0.16)
		b.name:SetAlpha(a)
		if b == pick then
			local s
			if t < 0.15 then
				s = 1 + (R.SWELL - 1) * Smooth(t / 0.15)
			else
				s = R.SWELL - (R.SWELL - 1) * Smooth((t - 0.15) / 0.27)
			end
			Put(b, b.x, -R.SIZE / 2, s)
			b:SetAlpha(1 - Smooth((t - 0.62) / 0.3))
		else
			local p = Smooth(t / 0.2)
			Put(b, b.x, -R.SIZE / 2, 1 - 0.2 * p)
			b:SetAlpha(1 - p)
		end
	end
	B.box:SetAlpha(1 - Smooth(t / 0.18))
	if pick then
		MelloUI.Widgets.Flipbook(B.burst, B.burstNext, t / 0.45, 8, 1 - Smooth((t - 0.35) / 0.15))
	end
end

local function PickDone(f)
	B.burst:Hide()
	B.burstNext:Hide()
	f:Hide()
end

local function DropDone()
	for _, role in ipairs(S.roles) do
		local b = B.medals[role]
		Put(b, b.x, -R.SIZE / 2, 1)
		b:SetAlpha(1)
		b.name:SetAlpha(1)
	end
	B.box:SetAlpha(1)
	if S.preview == "auto" then
		C_Timer.After(R.PREVIEW_PICK, function()
			local first = S.preview == "auto" and B.medals[S.roles[1]]
			if first and first:IsShown() and B.frame:IsShown() then
				PickClick(first)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Showing and picking
--------------------------------------------------------------------------------

-- the picker for these roles: dropped in (or there at once)
local function Open(roles, preview)
	Lay(roles)
	local f = B.frame
	S.picked, S.remember, S.preview = nil, false, preview
	B.tick:Hide()
	MelloUI.Anim:Stop(f, "drive")
	MelloUI.Anim:Stop(f, "alpha")
	f:SetAlpha(1)
	f:Show()
	Light()
	if Moving() then
		R.DropStep(f, 0)
		MelloUI.Anim:Drive(f, R.DropStep, R.DropLength(#roles), "linear", DropDone)
	else
		DropDone()
	end
	return true
end

PickClick = Shared("OnClick on a role picker's picture", function(b)
	local role = b.role
	if not role or S.picked or not B.frame:IsShown() then
		return
	end
	S.picked = role
	S.waiting = nil
	MelloUI:PlayUISound("option_on")
	if not S.preview then
		if S.remember and M.db then
			MelloUI:NotifySettingChanged("RolePicker", "remember", role)
		end
		Assign(role, false)
	end
	Light()
	local f = B.frame
	MelloUI.Anim:Stop(f, "drive")
	if Moving() then
		for _, t in ipairs({ B.burst, B.burstNext }) do
			t:ClearAllPoints()
			t:SetPoint("CENTER", f, "TOP", b.x, -R.SIZE / 2)
			t:Show()
		end
		MelloUI.Anim:Drive(f, R.PickStep, R.PICK, "linear", PickDone)
	else
		PickDone(f)
	end
end, "script")

-- an entry into a dungeon or a raid (or a group formed inside): the remembered role, the one role, or the picker
local function Check()
	if not M.isEnabled or S.handled or not InDungeon() or not Grouped() or FinderGroup() then
		return
	end
	S.handled = true
	local roles = ClassRoles()
	local kept = M.db and M.db.remember
	if kept and kept ~= "ask" and Has(roles, kept) then
		Assign(kept, true)
		return
	end
	if #roles < 2 then
		if roles[1] then
			Assign(roles[1], false)
		end
		return
	end
	if InCombatLockdown() then
		S.waiting = roles
		return
	end
	Open(roles, nil)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = {}

function events.PLAYER_ENTERING_WORLD(_, reloading)
	if InDungeon() then
		S.inside = true
		-- (a /reload inside: nothing again; the entry was handled before it)
		S.handled = reloading == true
		Check()
	else
		S.inside, S.handled, S.waiting, S.assign = nil, nil, nil, nil
		Close(false)
	end
end

function events.GROUP_ROSTER_UPDATE()
	if not Grouped() then
		S.waiting = nil
		if not S.preview then
			Close(false)
		end
		return
	end
	if S.inside and not S.handled then
		Check()
	end
end

function events.PLAYER_REGEN_DISABLED()
	local f = B.frame
	if f and f:IsShown() and not S.preview and not S.picked then
		S.waiting = S.roles
		f:Hide()
	end
end

function events.PLAYER_REGEN_ENABLED()
	if S.assign then
		local role, kept = S.assign, S.assignKept
		S.assign, S.assignKept = nil, nil
		Assign(role, kept)
	end
	local roles = S.waiting
	if roles and M.isEnabled and InDungeon() and Grouped() then
		S.waiting = nil
		Open(roles, nil)
	end
end

function events.PLAYER_ROLES_ASSIGNED()
	if B.frame and B.frame:IsShown() then
		Light()
	end
end

local eventFrame
local OnEvent = Shared("OnEvent on the role picker", function(_, event, ...)
	local fn = events[event]
	if fn then
		fn(...)
	end
end, "script")

--------------------------------------------------------------------------------
-- The Play, the chat line, Edit Layout's plate
--------------------------------------------------------------------------------

-- the Animations page's Play: the class's roles drop in, the first one is picked (nothing set)
M.Plays = {
	pick = function()
		if not M.isEnabled then
			return false
		end
		local roles = ClassRoles()
		if #roles < 2 then
			roles = R.ROLES
		end
		Open(roles, "auto")
		return true, R.DropLength(#roles) + R.PREVIEW_PICK + R.PICK
	end,
}

-- /mello roles show: the picker as it comes at a dungeon's door (in a group a pick sets your role; alone it is a
-- preview); /mello roles pick: the Play
M.SlashWords = {
	show = function()
		if not M.isEnabled then
			MelloUI:Announce(TEXT.off, "info")
			return
		end
		local roles = ClassRoles()
		if #roles < 2 then
			roles = R.ROLES
		end
		Open(roles, (not Grouped()) and "slash" or nil)
	end,
	pick = function()
		M.Plays.pick()
	end,
}

-- Edit Layout's plate: the picker's frame made when Edit Layout opens while the Role Picker is on
if MelloUI.AddMoverSource then
	MelloUI:AddMoverSource(function()
		if M.isEnabled and not B.frame then
			Build()
		end
	end)
end

--------------------------------------------------------------------------------
-- Enable / disable
--------------------------------------------------------------------------------

function M:OnEnable(db)
	self.db = db
	if not eventFrame then
		eventFrame = CreateFrame("Frame")
		Perf.SetScript(eventFrame, "OnEvent", OnEvent)
	end
	for event in pairs(events) do
		eventFrame:RegisterEvent(event)
	end
	-- (switched on inside a dungeon: this entry counts. At the login the world's own event comes first and decides --
	-- after a /reload inside, nothing -- so this looks only once that had its chance)
	C_Timer.After(2, R.LateLook)
end

function R.LateLook()
	if M.isEnabled and S.inside == nil and InDungeon() then
		S.inside = true
		Check()
	end
end

-- the login's own world event (the start-up pass switches the modules on after it, Core.lua): inside a dungeon at the
-- login, the entry; after a /reload inside, nothing
function M:OnLoginWorld(isLogin, reloading)
	events.PLAYER_ENTERING_WORLD(isLogin, reloading)
end

function M:OnDisable()
	if eventFrame then
		eventFrame:UnregisterAllEvents()
	end
	S.inside, S.handled, S.waiting, S.assign = nil, nil, nil, nil
	Close(false)
end

function M:OnSettingChanged(_, _, db)
	self.db = db
end

-- (the tests')
M.R, M.S, M.B, M.events, M.Check, M.Open, M.ClassRoles = R, S, B, events, Check, Open, ClassRoles
