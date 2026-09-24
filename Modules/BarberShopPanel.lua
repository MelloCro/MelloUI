--------------------------------------------------------------------------------
-- MelloUI - Barber Shop Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): the barber shop dressed in the painted kit (Modules/Kit.lua) by
-- the rule book (docs/WINDOW-RULES.md), lightly: every kit piece stands in
-- for one of the game's art regions, on that region's rectangle, the game's
-- art faded in its place, and nothing is ever laid over the character.
--
-- This client's barber shop is the full-screen character customisation
-- (Blizzard_BarbershopUI on Blizzard_CharacterCustomize, both load on
-- demand): BarberShopFrame covers the screen (the game's vignettes at its
-- edges, the body type buttons at the top, Accept / Cancel / Reset at the
-- bottom corners, a high-definition toggle), and CharCustomizeFrame is
-- attached to it (the options panel at the right: the category buttons, the
-- selector rows -- a dropdown between two step arrows, a label over it --
-- check boxes and sliders; the camera buttons' panel at the top left). There
-- is no window, portrait, title or cost string: the price shows on the
-- game's own tooltips. A client with the old small barber window (arrows and
-- labels, the cost, three buttons) gets its buttons, arrows and check boxes
-- by the sweep.
--
--   the options panel    its heavy bronze frame and backdrop -> the L1 box:
--                        single rail, the list-box stone under the palette's
--                        inner panel (2e: the selector rows are text)
--   the selector rows    the dropdown (WowStyle2) -> the dropdown plate D1;
--                        the step arrows -> the kit's arrow_left / _right
--                        (dimmed while disabled, as the merchant's page
--                        arrows); the label in the palette's text colour
--   check boxes          the kit's check box
--   sliders              the kit's slider track and gem thumb, its step
--                        arrows the kit's
--   category / body type / form buttons
--                        their metal ring -> every window's Round Border rim
--                        on a square whose opening is the masked icon
--                        (Kit:RimRect), lit gold while the button is checked
--                        (the game's selection ring faded); the game's
--                        additive hover and flash stay
--   the camera panel     its bronze frame -> the L1 box; its square buttons
--                        (and the dice) -> the cog plate K2 under the glyph
--   Accept / Cancel / Reset
--                        the red plates (B1), their disabled look kept
--   the vignettes        the game's (they frame the character; never covered)
--
-- Taint: nothing of the game's is replaced or re-scripted. Post-hooks on the
-- customisation's own refreshes (UpdateOptionButtons, UpdateAlteredForms,
-- UpdateSex), HookScript and the buttons' Enable / Disable only; what the
-- skin keeps about the game's frames lives in weak side tables; no barber
-- function is ever called. Switching the module off disables every
-- replacement and gives the labels their colours back: the barber shop is
-- the game's again.
--
-- /barberdump [frames | reps | regions]: what the barber shop is made of on
-- this client and what the skin dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("BarberShopPanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("BarberShopPanel", {
	title = "Barber Shop Kit",
	desc = "The barber shop in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local ADDON = "blizzard_barbershopui"     -- (the folder's name, compared without case)
local ARROW_PREV = "UI-SpellbookIcon-PrevPage-Up"
local ARROW_NEXT = "UI-SpellbookIcon-NextPage-Up"

local skin = nil          -- { reps = { every replacement }, built }
local active = false
local hooked = false

-- what this module made or looked at, kept OFF the game's frames (weak keys)
local done = setmetatable({}, { __mode = "k" })          -- [frame / region] = true: looked at once
local labels = setmetatable({}, { __mode = "k" })        -- [label] = its own colour { r, g, b, a } (false: not read yet)
local arrowReps = {}                                     -- { rep, button }
local found = {}                                         -- [part] = a line for /barberdump
local stats = { rings = 0, dropdowns = 0, arrows = 0, checks = 0, sliders = 0, cogs = 0, boxes = 0, buttons = 0, labels = 0 }

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Barber shop kit: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- the non-nil values given, as a list (alsoFade stops at the first nil)
local function List(...)
	local list = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if v then
			list[#list + 1] = v
		end
	end
	return list
end

-- a frame's name, secret-safe (nil when it has none or it reads secret)
local function NameOf(obj)
	if not obj then
		return nil
	end
	local ok, n = pcall(obj.GetName, obj)
	if ok and type(n) == "string" and not Secret(n) then
		return n
	end
	return nil
end

local function Label(obj)
	if not obj then
		return "nil"
	end
	local n = NameOf(obj)
	if n then
		return n
	end
	local ok, d = pcall(obj.GetDebugName, obj)
	return (ok and type(d) == "string" and not Secret(d)) and d or "[unnamed]"
end

-- a font string's text when it can be read (nil when empty or secret)
local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	if ok and type(text) == "string" and not Secret(text) and text ~= "" then
		return text
	end
	return nil
end

local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.0f", v) or "?"
end

local function Width(obj)
	local ok, w = pcall(obj.GetWidth, obj)
	if ok and type(w) == "number" and not Secret(w) then
		return w
	end
	return nil
end

local function Shown(obj)
	local ok, s = pcall(obj.IsShown, obj)
	return (ok and not Secret(s)) and tostring(s) or "?"
end

local function Window()
	return _G.BarberShopFrame
end

-- the character customisation, when it is the one attached to the barber
-- shop (the full-screen barber); nil on a client with the old window
local function Customize()
	return _G.CharCustomizeFrame
end

--------------------------------------------------------------------------------
-- The palette's text colour on a selector's label (WINDOW-RULES 2e: labels
-- in the palette's text colour on the dark panel); the label's own colour
-- read once and given back on disable.
--------------------------------------------------------------------------------
local function LabelOn(fs)
	if not labels[fs] then
		local ok, r, g, b, a = pcall(fs.GetTextColor, fs)
		if not (ok and type(r) == "number") or Secret(r) or Secret(g) or Secret(b) then
			labels[fs] = false
			return
		end
		labels[fs] = { r, g, b, (type(a) == "number" and not Secret(a)) and a or 1 }
	end
	local c = MelloUI.Palette and MelloUI.Palette.text
	if c then
		fs:SetTextColor(c[1], c[2], c[3])
	end
end

local function LabelOff(fs)
	local saved = labels[fs]
	if saved then
		fs:SetTextColor(saved[1], saved[2], saved[3], saved[4])
	end
end

local function TakeLabel(fs)
	if not fs then
		return
	end
	if labels[fs] == nil then
		stats.labels = stats.labels + 1
		labels[fs] = false
	end
	if active then
		LabelOn(fs)
	end
end

--------------------------------------------------------------------------------
-- The step arrows. The customisation's (WowStyle2IconButton: a Background
-- plate re-atlased with the state, the arrow glyph on its Icon) and the old
-- file-art arrows (UI-SpellbookIcon-*Page: a normal texture) -> the kit's
-- arrow_left / arrow_right at the button's height, the game's pieces faded.
-- The kit's arrows have no disabled look: a disabled arrow (the first or
-- last choice) is shown at a lower alpha, read again after the game's own
-- state change, Enable and Disable.
--------------------------------------------------------------------------------
local function ArrowLook(entry)
	local tex = entry.rep.object
	if not (active and tex and tex.SetAlpha) then
		return
	end
	local ok, enabled = pcall(entry.button.IsEnabled, entry.button)
	if ok and not Secret(enabled) then
		tex:SetAlpha(enabled and 1 or 0.4)
	end
	if tex.Update then
		tex:Update()
	end
end

local function SkinArrow(button, key)
	if not button or done[button] then
		return
	end
	done[button] = true
	local region, extra
	if button.Icon then
		region, extra = button.Icon, List(button.Background)
	elseif button.GetNormalTexture and button:GetNormalTexture() then
		region = button:GetNormalTexture()
		extra = Kit:OtherTextures(button, region)
	end
	if not region then
		return
	end
	local rep = Replace(region, { as = key, button = button, rect = button, alsoFade = extra })
	if button.melloRep == nil then
		button.melloRep = rep or false
	end
	if not rep then
		return
	end
	local entry = { rep = rep, button = button }
	arrowReps[#arrowReps + 1] = entry
	for _, method in ipairs({ "Enable", "Disable", "SetEnabled", "OnButtonStateChanged" }) do
		if type(button[method]) == "function" then
			hooksecurefunc(button, method, function()
				ArrowLook(entry)
			end)
		end
	end
	ArrowLook(entry)
	stats.arrows = stats.arrows + 1
end

--------------------------------------------------------------------------------
-- The option rows (pooled by the customisation: dropdown rows, check boxes,
-- sliders), dressed once each as the game acquires them.
--------------------------------------------------------------------------------
local function CheckKey(cb)
	local normal = cb.GetNormalTexture and cb:GetNormalTexture()
	local key = normal and Kit:ArtKey(normal)
	return (key and Kit:RuleFor(key)) and key or "UI-CheckBox-Up"
end

local function SkinOption(opt)
	if not opt or done[opt] then
		return
	end
	done[opt] = true
	local dd = opt.Dropdown
	if dd and dd.Background and dd.melloRep == nil then
		dd.melloRep = Replace(dd.Background, { as = "common-dropdown-textholder", rect = dd, button = dd, alsoFade = List(dd.Arrow) }) or false
		if dd.melloRep then
			stats.dropdowns = stats.dropdowns + 1
		end
	end
	SkinArrow(opt.DecrementButton, ARROW_PREV)
	SkinArrow(opt.IncrementButton, ARROW_NEXT)
	local cb = opt.Button
	if cb and cb.GetCheckedTexture and cb.melloRep == nil then
		if Kit:SkinCheckButton(cb, Replace, CheckKey(cb)) then
			stats.checks = stats.checks + 1
		end
	end
	local slider = opt.Slider
	if slider and slider.Track and not done[slider] then
		done[slider] = true
		local track = Replace(slider.Track, { as = "_Minimal_SliderBar_Middle", rect = slider.Track })
		local thumb = slider.Thumb or (slider.GetThumbTexture and slider:GetThumbTexture())
		if thumb then
			Replace(thumb, { as = "Minimal_SliderBar_Button", button = slider, rect = thumb })
		end
		if track then
			stats.sliders = stats.sliders + 1
		end
	end
	TakeLabel(opt.Label)
end

--------------------------------------------------------------------------------
-- The round buttons (RingedMaskedButtonTemplate: the categories, the body
-- types, the altered forms, the forms dropdown): the icon is the button's
-- normal texture masked round a few px inside it, the metal Ring over it,
-- the selection ring as the checked texture. The Round Border rim on a
-- square whose opening is the masked icon, in place of the Ring (re-atlased
-- -disabled by the game: faded all the same), lit while the button is
-- checked -- the selection ring faded. The additive hover (alpha 0.5 in the
-- template) and the flash stay the game's.
--------------------------------------------------------------------------------
local function SkinRing(b)
	if not (b and b.Ring) or done[b] then
		return
	end
	done[b] = true
	local w = Width(b)
	if not (w and w > 0) then
		done[b] = nil     -- not laid out yet: looked at again on the next refresh
		return
	end
	local inset = tonumber(b.circleMaskSizeOffset) or 2
	local rect = Kit:RimRect(b, "roundslot", math.max(w - 2 * inset, 1), b)
	local rep = Replace(b.Ring, { as = "Legacy-Tree-Frame-Card-Ring", button = b, rect = rect,
		checked = function()
			local ok, c = pcall(b.GetChecked, b)
			return ok and not Secret(c) and c and true or false
		end,
		alsoFade = List(b.CheckedTexture) })
	if b.melloRep == nil then
		b.melloRep = rep or false
	end
	if rep then
		stats.rings = stats.rings + 1
	end
end

-- Every round button under `holder` (its direct children)
local function SkinRings(holder)
	if not (holder and holder.GetChildren) then
		return
	end
	for _, child in ipairs({ holder:GetChildren() }) do
		SkinRing(child)
	end
end

--------------------------------------------------------------------------------
-- The two bronze panels (the options panel and the camera buttons'): their
-- heavy bronze frame (a texture on the panel's rect), backdrop and corner
-- brackets -> the L1 box on the panel's rect, a holder one level under the
-- panel (its rows and buttons are its children, above it).
--------------------------------------------------------------------------------
local function SkinBox(panel, name)
	if not panel or done[panel] then
		return
	end
	done[panel] = true
	local frame = panel.Frame
	local fade = {}
	for _, region in ipairs({ panel:GetRegions() }) do
		if region ~= frame and region:GetObjectType() == "Texture" and not region.kitPiece then
			local key = Kit:ArtKey(region)
			if region == panel.Backdrop or (type(key) == "string" and key:find("^heavybronze")) then
				fade[#fade + 1] = region
			end
		end
	end
	if not frame then
		frame = table.remove(fade, 1)
	end
	if not frame then
		found[name] = string.format("%s: -- no frame art", Label(panel))
		return
	end
	local rep = Replace(frame, { as = "common-insideframe", parent = panel, rect = panel, body = true, alsoFade = fade })
	if rep then
		stats.boxes = stats.boxes + 1
	end
	found[name] = string.format("%s: L1 box %s (frame %s, %d pieces faded with it)", Label(panel), rep and "on" or "NOT made",
		tostring(Kit:ArtKey(frame) or "?"), #fade)
end

-- A square small button (CustomizationSmallButtonTemplate: the gray square
-- as its normal / pushed texture, the glyph on its Icon) -> the cog plate K2
-- under the glyph; its additive hover (alpha 0.4) stays the game's
local function SkinCog(b)
	if not b or done[b] then
		return
	end
	done[b] = true
	local normal = b.GetNormalTexture and b:GetNormalTexture()
	if not normal then
		return
	end
	local rep = Replace(normal, { as = "UI-SquareButton-Up", button = b, alsoFade = List(b.GetPushedTexture and b:GetPushedTexture()) })
	if b.melloRep == nil then
		b.melloRep = rep or false
	end
	if rep then
		stats.cogs = stats.cogs + 1
	end
end

--------------------------------------------------------------------------------
-- What the game makes and re-makes as it refreshes (pooled): the categories,
-- the option rows, the body types, the altered forms
--------------------------------------------------------------------------------
local function SkinDynamic()
	local f, cf = Window(), Customize()
	if not (skin and f) then
		return
	end
	if cf then
		SkinRings(cf.Categories)
		SkinRings(cf.AlteredForms)
		SkinRing(cf.FormsDropdown)
		if cf.Options then
			for _, opt in ipairs({ cf.Options:GetChildren() }) do
				SkinOption(opt)
			end
		end
	end
	SkinRings(f.BodyTypes)
end

--------------------------------------------------------------------------------
-- Building, switching on and off
--------------------------------------------------------------------------------
local BUTTONS = { "AcceptButton", "CancelButton", "ResetButton" }

local function Build()
	local f = Window()
	if not f then
		return
	end
	skin = skin or { reps = {} }
	if skin.built then
		return
	end
	skin.built = true

	-- Accept / Cancel / Reset: the red plates (the 128-RedButton three-slice
	-- keyed on its Center; the game re-atlases it with the state)
	local n = 0
	for _, key in ipairs(BUTTONS) do
		local b = f[key]
		if b and Kit:SkinRedButton(b, Replace) then
			n = n + 1
			b.melloNoInk = true
		end
	end
	stats.buttons = n
	local sd = f.SDToggleButton
	if sd and sd.melloRep == nil and Kit:SkinCheckButton(sd, Replace, CheckKey(sd)) then
		stats.checks = stats.checks + 1
	end

	local cf = Customize()
	if cf then
		SkinBox(cf.CustomizeOptionsContainerFrame, "options")
		SkinBox(cf.SmallButtons, "camera")
		local small = cf.SmallButtons
		if small then
			for _, b in ipairs(small.ControlButtons or { small:GetChildren() }) do
				SkinCog(b)
			end
		end
		local container = cf.CustomizeOptionsContainerFrame
		SkinCog((container and container.RandomizeAppearanceButton) or cf.RandomizeAppearanceButton)
		found.kind = "the full-screen character customisation (CharCustomizeFrame attached)"
	else
		found.kind = "the old barber window (no CharCustomizeFrame): its buttons, arrows and check boxes by the sweep"
		Kit:SweepControls(f, Replace, skin)
		-- its selectors' arrows (file art keyed by hand: a Prev / Next
		-- page button)
		local function Walk(root, depth)
			if depth > 4 then
				return
			end
			for _, child in ipairs({ root:GetChildren() }) do
				local nm = NameOf(child) or ""
				if child:GetObjectType() == "Button" and child.GetNormalTexture and child:GetNormalTexture() then
					if nm:find("Prev") or nm:find("Left") then
						SkinArrow(child, ARROW_PREV)
					elseif nm:find("Next") or nm:find("Right") then
						SkinArrow(child, ARROW_NEXT)
					end
				end
				Walk(child, depth + 1)
			end
		end
		Walk(f, 0)
	end
	SkinDynamic()
end

-- After every show and every refresh of the customisation: what it acquired
-- since, the arrows' looks, the labels' colour; once more a frame later
-- (the pools lay out their buttons after the refresh).
local function Refresh()
	if not (active and skin) then
		return
	end
	SkinDynamic()
	for _, entry in ipairs(arrowReps) do
		ArrowLook(entry)
	end
	for fs in pairs(labels) do
		LabelOn(fs)
	end
	if skin.laterPending then
		return
	end
	skin.laterPending = true
	C_Timer.After(0, function()
		skin.laterPending = nil
		if active then
			SkinDynamic()
			for fs in pairs(labels) do
				LabelOn(fs)
			end
		end
	end)
end

local function Activate()
	if active or not Window() then
		return
	end
	Build()
	if not skin then
		return
	end
	active = true
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	Refresh()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	if skin then
		for _, rep in ipairs(skin.reps) do
			rep:Disable()
		end
	end
	for fs in pairs(labels) do
		LabelOff(fs)
	end
end

-- (user, 2026-09-24: "dress rarely used windows on first open") nothing of
-- the look is built while the barber shop has never been shown this session:
-- a skin already built is switched on (and off), else only a barber shop open
-- right now (a /reload in the chair) is dressed at once; its first show
-- dresses it (the OnShow hook below), in that same frame, so it never draws
-- undressed.
local function Sync()
	local f = Window()
	if M.isEnabled and f and ((skin and skin.built) or f:IsShown()) then
		Activate()
	else
		Deactivate()
	end
end

-- (geometry of the frames' children changes here: out of combat only)
local function SyncSafe()
	if Kit.WhenOutOfCombat then
		Kit:WhenOutOfCombat(Sync)
	else
		Sync()
	end
end

-- A first show in combat (the game hardly allows the chair then) dresses at
-- once all the same: the dressing adds frames and textures of ours and
-- recolours the labels, never moving a frame of the game's, protected or not.
-- A barber shop the game protects waits for the fight's end, as before.
local function DressOnShow()
	local f = Window()
	local ok, protected = pcall(f.IsProtected, f)
	if InCombatLockdown() and ok and not Secret(protected) and not protected then
		Sync()
	else
		SyncSafe()
	end
end

local function Hook()
	local f = Window()
	if hooked or not f then
		return
	end
	hooked = true
	Perf.HookScript(f, "OnShow", function()
		if M.isEnabled and not active then
			DressOnShow()     -- (Activate refreshes what it dressed)
		else
			Refresh()
		end
	end)
	if type(f.UpdateSex) == "function" then
		hooksecurefunc(f, "UpdateSex", Refresh)
	end
	local cf = Customize()
	if cf then
		for _, method in ipairs({ "UpdateOptionButtons", "UpdateAlteredForms" }) do
			if type(cf[method]) == "function" then
				hooksecurefunc(cf, method, Refresh)
			end
		end
	end
end

-- The barber shop loads on demand (Blizzard_BarbershopUI, at the first
-- barber's chair): hooked when it loads, or at once if it already has, and
-- dressed as it first shows.
local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(self, _, name)
	local mine = type(name) == "string" and name:lower() == ADDON
	if (mine or Window()) and Window() then
		self:UnregisterEvent("ADDON_LOADED")
		Hook()
		if M.isEnabled then
			SyncSafe()
		end
	end
end)

function M:OnEnable(db)
	self.db = db
	if Window() then
		Hook()
		SyncSafe()
	else
		eventFrame:RegisterEvent("ADDON_LOADED")
	end
end

function M:OnDisable()
	SyncSafe()
end

--------------------------------------------------------------------------------
-- /barberdump [frames | reps | regions]: with no mode, what the skin found
-- and dressed (every part, found or not) and the option rows one by one;
-- the modes are Kit:DumpWindow's, on BarberShopFrame (and "custom <mode>"
-- on CharCustomizeFrame). Opens the copy window.
--------------------------------------------------------------------------------
local function Line(label, text)
	MelloUI:Print("  %-16s %s", label, text or "-- not looked at yet (the kit has not dressed the barber shop)")
end

local function Rect(obj)
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if ok and l and not Secret(l) and not Secret(b) and not Secret(w) and not Secret(h) then
		return string.format("x=%s y=%s w=%s h=%s", Num(l), Num(b), Num(w), Num(h))
	end
	return "(no rect)"
end

local function Dressed(obj)
	return tostring(obj ~= nil and obj.melloRep ~= nil and obj.melloRep ~= false)
end

local function Enabled(b)
	local ok, e = pcall(b.IsEnabled, b)
	return (ok and not Secret(e)) and tostring(e) or "?"
end

local function DumpRings(label, holder)
	if not (holder and holder.GetChildren) then
		Line(label, "-- none")
		return
	end
	local n, dressed = 0, 0
	for _, child in ipairs({ holder:GetChildren() }) do
		if child.Ring then
			n = n + 1
			if child.melloRep then
				dressed = dressed + 1
			end
		end
	end
	Line(label, string.format("%s: %d round buttons, %d with the rim, shown %s", Label(holder), n, dressed, Shown(holder)))
end

local function Summary(f)
	local cf = Customize()
	MelloUI:Print("BarberShopFrame: shown %s, kit %s, reps %d", Shown(f), active and "on" or "off", skin and #skin.reps or 0)
	Line("kind", found.kind or (cf and "the full-screen character customisation" or "the old barber window"))
	Line("portrait", "-- none (a full-screen customisation, not a window: no ring)")
	Line("title", "-- none (no window title: nothing to put on a plate)")
	Line("tabs", "-- none (the categories are round buttons, below)")
	Line("page picture", "-- none (the character and the world are the backdrop; never covered)")
	Line("cost", "-- no cost string on this client (the price shows on the game's tooltips)")
	for _, key in ipairs(BUTTONS) do
		local b = f[key]
		Line(key, b and string.format("%s shown %s, enabled %s, red plate %s, label '%s'", Label(b), Shown(b), Enabled(b), Dressed(b),
			tostring(b.GetText and TextOf(b) or "?")) or "-- not found")
	end
	local sd = f.SDToggleButton
	Line("HD toggle", sd and string.format("shown %s, kit check box %s", Shown(sd), Dressed(sd)) or "-- not found")
	DumpRings("body types", f.BodyTypes)
	if cf then
		Line("customize", string.format("%s shown %s, parent %s", Label(cf), Shown(cf), Label(cf:GetParent())))
		Line("options panel", found.options)
		local container = cf.CustomizeOptionsContainerFrame
		if container then
			Line("  rect", Rect(container))
		end
		Line("camera panel", found.camera)
		DumpRings("categories", cf.Categories)
		DumpRings("altered forms", cf.AlteredForms)
		local fd = cf.FormsDropdown
		Line("forms dropdown", fd and string.format("shown %s, rim %s", Shown(fd), Dressed(fd)) or "-- none")
		local rnd = (container and container.RandomizeAppearanceButton) or cf.RandomizeAppearanceButton
		Line("dice", rnd and string.format("shown %s, cog %s", Shown(rnd), Dressed(rnd)) or "-- none")
		local small = cf.SmallButtons
		if small then
			for _, b in ipairs(small.ControlButtons or { small:GetChildren() }) do
				Line("  camera button", string.format("%s shown %s, cog %s", Label(b), Shown(b), Dressed(b)))
			end
		end
		local options = cf.Options
		if options then
			for _, opt in ipairs({ options:GetChildren() }) do
				local kind = opt.Dropdown and "dropdown row" or opt.Button and "check box" or opt.Slider and "slider" or "other"
				local label = opt.Label and TextOf(opt.Label)
				local parts = {}
				if opt.Dropdown then
					parts[#parts + 1] = "plate " .. Dressed(opt.Dropdown)
				end
				if opt.DecrementButton then
					parts[#parts + 1] = "arrows " .. Dressed(opt.DecrementButton) .. " / " .. Dressed(opt.IncrementButton)
				end
				if opt.Button then
					parts[#parts + 1] = "box " .. Dressed(opt.Button)
				end
				if opt.Slider then
					parts[#parts + 1] = "slider " .. tostring(done[opt.Slider] == true)
				end
				Line("  " .. kind, string.format("'%s' shown %s, %s, label colour %s", tostring(label or "?"), Shown(opt),
					table.concat(parts, ", "), (opt.Label and labels[opt.Label]) and "palette text" or "the game's"))
			end
		end
	else
		Line("customize", "-- no CharCustomizeFrame (an old barber window)")
	end
	Line("counts", string.format("red plates %d, round rims %d, dropdown plates %d, arrows %d, check boxes %d, sliders %d, cog plates %d, boxes %d, labels %d",
		stats.buttons, stats.rings, stats.dropdowns, stats.arrows, stats.checks, stats.sliders, stats.cogs, stats.boxes, stats.labels))
	Line("inked strings", "-- none (no parchment: the rows lie on the dark panel)")
end

SLASH_MELLOBARBERDUMP1 = "/barberdump"
SlashCmdList.MELLOBARBERDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if not f then
		MelloUI:Print("/barberdump: no BarberShopFrame yet: Blizzard_BarbershopUI loads at the first barber's chair (sit in one, then "
			.. "try again). If it never appears, the barber shop is not on this client.")
	elseif not skin then
		MelloUI:Print("/barberdump: the barber shop is not dressed yet (%s)", M.isEnabled
			and "the kit dresses it the first time it opens: sit in a barber's chair, then try again" or "the Barber Shop Kit is off")
	elseif msg == "" then
		Summary(f)
	else
		-- frames / reps / regions (the visible game textures): the Kit's
		-- dump, on the customisation with "custom <mode>"
		local mode, rest = msg:match("^(%S+)%s*(.*)$")
		local root = f
		if mode == "custom" and Customize() then
			root, msg = Customize(), rest
		end
		Kit:DumpWindow(root, skin, (msg ~= "regions" and msg ~= "") and msg or nil)
	end
	MelloUI:ShowLog("barberdump " .. msg)
end
