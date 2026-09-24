--------------------------------------------------------------------------------
-- MelloUI - Split Stack Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): The split-stack box in the kit.
--
-- StackSplitFrame (shift-click on a stack): in this client one painted
-- picture (the money frame's box, UI-MoneyFrame; the taller
-- UI-MoneyFrame-Large for splitting into stacks of several) with the amount
-- in its sunken field, the left / right arrows either side of it and Okay /
-- Cancel under it. Dressed as the Dialogs Kit dresses a popup: the single
-- rail with its stone round the box (a frame one level below it) in place
-- of the picture's frame, the picture faded, and in place of its field the
-- kit's edit plate (S1) between the arrows under the amount, its left cap
-- the plate's plain end (the S1 cap carries a search glass: this is no
-- search box). The arrows are the kit's (the table's page arrows at the
-- buttons' height; shown dimmed while the game disables one), Okay / Cancel
-- on the red plates with their labels in their own colours. The Dialogs'
-- parchment option (Parchment: Dialogs) is followed: the sheet on the stone
-- and the text around the plate in dark ink while it is on, the palette's
-- inner panel on the stone while it is off (WINDOW-RULES 2e).
--
-- The box's size, place and behaviour stay the game's (its own OnChar /
-- OnKeyDown typing; no edit box of ours); switching the module off gives
-- back the stock box. /splitdump [frames | reps | regions].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("StackSplitPanel", {
	title = "Split Stack Kit",
	desc = "The split-stack box in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local AREA = "dialog"          -- the Dialogs' parchment option (parchment_dialog)
local SURFACE = "stacksplit"   -- this module's QuestInk surface
local FIELD_HEIGHT = 20        -- the game's own input boxes' height (InputBoxTemplate, SearchBoxTemplate)

local active = false
local hooked = false
local skin = nil               -- { nine, sheet, dim, reps = {}, plate, field, arrows = {}, buttons = {} }
local raised = setmetatable({}, { __mode = "k" })   -- [font string] = { its own layer, sublevel }: raised over the plate
local fadedArt = {}            -- the game's art faded with no piece on its own rect

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

local function Window()
	local f = _G.StackSplitFrame
	if type(f) == "table" and f.GetChildren and f.CreateTexture then
		return f
	end
	return nil
end

local function Replace(region, opts)
	local rep = region and skin and Kit and Kit.Replace and Kit:Replace(region, opts)
	if rep then
		skin.reps[#skin.reps + 1] = rep
		if active then
			rep:Enable()
		end
	end
	return rep
end

-- a frame's name, secret-safe
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

-- a part by its key, else by the global name an older XML gives it
local function Part(f, key, global)
	if f and f[key] then
		return f[key]
	end
	return global and _G[global] or nil
end

-- the picture: by its key, else the box's first BACKGROUND texture (an
-- older box's unnamed picture)
local function Picture(f)
	if f.SingleItemSplitBackground then
		return f.SingleItemSplitBackground
	end
	for _, region in ipairs({ f:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			local okL, layer = pcall(region.GetDrawLayer, region)
			if okL and layer == "BACKGROUND" then
				return region
			end
		end
	end
end

local function Parts(f)
	return {
		single = Picture(f),
		multi = Part(f, "MultiItemSplitBackground"),
		text = Part(f, "StackSplitText", "StackSplitText"),
		count = Part(f, "StackItemCountText"),
		left = Part(f, "LeftButton", "StackSplitLeftButton"),
		right = Part(f, "RightButton", "StackSplitRightButton"),
		okay = Part(f, "OkayButton", "StackSplitOkayButton"),
		cancel = Part(f, "CancelButton", "StackSplitCancelButton"),
	}
end

--------------------------------------------------------------------------------
-- The field: the edit plate between the arrows, as high as the game's input
-- boxes, centred on the amount's line (the amount sits level with the
-- arrows for one item, above them for a split into stacks, the total under
-- it). A frame of our own carries the plate's rect; the plate itself is
-- regions of the box, in the picture's layer one sublevel up, so it is
-- drawn over the rail's stone and under the box's frames; the amount and the
-- total (BACKGROUND strings of the box's own) are raised over it while the
-- kit is on and put back after.
--------------------------------------------------------------------------------
local function CenterY(obj)
	local ok, _, y = pcall(obj.GetCenter, obj)
	if ok and type(y) == "number" and not Secret(y) then
		return y
	end
	return nil
end

local function LayoutField()
	local f = Window()
	local field = skin and skin.field
	if not (f and field) then
		return
	end
	local p = Parts(f)
	if not (p.left and p.right) then
		return
	end
	local dy = 0
	local ay, ty = CenterY(p.left), p.text and CenterY(p.text)
	if ay and ty then
		dy = ty - ay
	end
	field:ClearAllPoints()
	field:SetPoint("LEFT", p.left, "RIGHT", 0, dy)
	field:SetPoint("RIGHT", p.right, "LEFT", 0, dy)
	field:SetHeight(FIELD_HEIGHT)
end

local function RaiseTexts(on)
	for fs, was in pairs(raised) do
		if on then
			pcall(fs.SetDrawLayer, fs, "ARTWORK", 1)
		elseif was[1] then
			pcall(fs.SetDrawLayer, fs, was[1], was[2] or 0)
		end
	end
end

local function SkinField(f, p)
	local picture = p.single or p.multi
	if not (picture and p.left and p.right) then
		return
	end
	local field = CreateFrame("Frame", nil, f)
	field:EnableMouse(false)
	skin.field = field
	LayoutField()
	-- the picture's own field: the plate stands in for it; the rest of the
	-- picture (its frame) is the rail's; both pictures faded with it
	local others = {}
	if p.multi and p.multi ~= picture then
		others[#others + 1] = p.multi
	end
	skin.plate = Replace(picture, { as = "common-search-border-middle", rect = field, dropCap = "l", alsoFade = others })
	for _, fs in ipairs({ p.text or false, p.count or false }) do
		if fs and fs.GetDrawLayer then
			local okL, layer, sub = pcall(fs.GetDrawLayer, fs)
			if okL then
				raised[fs] = { layer, sub }
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The arrows: the kit's left / right arrows at the buttons' height by the
-- page arrows' rule (every other texture of the button faded: its pushed and
-- disabled looks). The arrow pieces have no disabled look: a disabled arrow
-- (at 1, or at the stack's size) is shown dimmed, as the game greys its
-- own, read again after the game's Enable / Disable.
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
	local normal = button and button.GetNormalTexture and button:GetNormalTexture()
	if not normal then
		return
	end
	local rep = Replace(normal, { as = key, button = button, rect = button, alsoFade = Kit:OtherTextures(button, normal) })
	if not rep then
		return
	end
	local entry = { rep = rep, button = button }
	skin.arrows[#skin.arrows + 1] = entry
	for _, method in ipairs({ "Enable", "Disable", "SetEnabled" }) do
		if button[method] then
			hooksecurefunc(button, method, function()
				ArrowLook(entry)
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- Okay / Cancel on the red plates, their labels in their own colours (the
-- parchment rule's button exception, melloNoInk); the plate keeps the
-- button's disabled look
--------------------------------------------------------------------------------
local function SkinButton(button)
	if not button or skin.buttons[button] ~= nil then
		return
	end
	skin.buttons[button] = false
	button.melloNoInk = true
	local QI = MelloUI.QuestInk
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "FontString" and region.melloInk and QI and QI.PlainText then
			pcall(QI.PlainText, region)
		end
	end
	local ok, rep = pcall(Kit.SkinRedButton, Kit, button, Replace)
	skin.buttons[button] = (ok and rep) and true or false
end

--------------------------------------------------------------------------------
-- Building, switching on and off
--------------------------------------------------------------------------------
local function Build()
	local f = Window()
	if skin or not (f and Kit and Kit.NineSlice) then
		return skin
	end
	local ok, nine = pcall(Kit.NineSlice, Kit, f, { prefix = "window/single", scale = Kit.scale * (Kit.frameScale or 1.6),
		gems = false, body = true, level = -1 })
	if not (ok and nine) then
		return nil
	end
	local alive = function() return active end
	skin = { nine = nine, reps = {}, arrows = {}, buttons = {} }
	skin.sheet = Kit.ParchmentSheet and Kit:ParchmentSheet(nine, nine, { area = AREA, fine = true, margin = 2, alive = alive })
	skin.dim = Kit.StoneDim and Kit:StoneDim(nine, { area = AREA, alive = alive })
	nine:SetShown(active)
	local p = Parts(f)
	pcall(SkinField, f, p)
	SkinArrow(p.left, "UI-SpellbookIcon-PrevPage-Up")
	SkinArrow(p.right, "UI-SpellbookIcon-NextPage-Up")
	SkinButton(p.okay)
	SkinButton(p.cancel)
	-- a client's box drawn otherwise (a nine-slice, a backdrop): faded as well
	for _, key in ipairs({ "Border", "NineSlice", "Bg", "BG" }) do
		if f[key] then
			fadedArt[#fadedArt + 1] = f[key]
		end
	end
	return skin
end

-- the ink (the parchment rule): the box's strings on the sheet in dark ink
-- while the Dialogs' parchment is on (the amount on its plate and the
-- buttons' labels keep their colours)
local function InkOn()
	return active and Kit.ParchmentOn and Kit:ParchmentOn(AREA) or false
end

local surfaceMade = false
local function Surface()
	local QI = MelloUI.QuestInk
	if not QI then
		return
	end
	if surfaceMade then
		QI.RefreshSurface(SURFACE)
		return
	end
	surfaceMade = true
	local function Skip(fs)
		local parent = fs.GetParent and fs:GetParent()
		if parent and (parent.melloNoInk or (parent.GetObjectType and parent:GetObjectType() == "Button")) then
			return true
		end
		return QI.DefaultSkip(fs)
	end
	QI.Surface(SURFACE, { on = InkOn, sheet = true, skip = Skip, roots = function() return Window() end })
end

-- the Dialogs' parchment switched: this box's strings follow
if Kit and Kit.SetParchment then
	hooksecurefunc(Kit, "SetParchment", function(_, area)
		if area == AREA and surfaceMade and MelloUI.QuestInk then
			MelloUI.QuestInk.RefreshSurface(SURFACE)
		end
	end)
end

-- after every show and every re-layout of the box (one item or stacks): the
-- field on the amount's line, the arrows' looks, the ink
local function Refresh()
	if not (active and skin) then
		return
	end
	LayoutField()
	if skin.plate then
		skin.plate:Refit()
	end
	for _, entry in ipairs(skin.arrows) do
		ArrowLook(entry)
	end
	if surfaceMade and MelloUI.QuestInk then
		MelloUI.QuestInk.RefreshSurface(SURFACE)
	end
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
	skin.nine:Show()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for _, obj in ipairs(fadedArt) do
		Kit:Fade(obj)
	end
	RaiseTexts(true)
	if Kit.SetParchment then
		Kit:SetParchment(AREA, Kit:ParchmentOn(AREA))
	end
	Surface()
	Refresh()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	if skin then
		skin.nine:Hide()
		for _, rep in ipairs(skin.reps) do
			rep:Disable()
		end
		-- the arrows' own dimming off with them
		for _, entry in ipairs(skin.arrows) do
			entry.rep.object:SetAlpha(1)
		end
	end
	for _, obj in ipairs(fadedArt) do
		Kit:Unfade(obj)
	end
	RaiseTexts(false)
	if surfaceMade and MelloUI.QuestInk then
		MelloUI.QuestInk.RefreshSurface(SURFACE)
	end
end

local function Sync()
	if M.isEnabled and Window() then
		Activate()
	else
		Deactivate()
	end
end

local function SyncSafe()
	if Kit and Kit.WhenOutOfCombat then
		Kit:WhenOutOfCombat(Sync)
	else
		Sync()
	end
end

local function Hook()
	local f = Window()
	if hooked or not f then
		return
	end
	hooked = true
	f:HookScript("OnShow", function()
		if M.isEnabled and not active then
			SyncSafe()
		end
		Refresh()
		C_Timer.After(0, Refresh)
	end)
	-- the game lays the box out for one item or for stacks after showing it
	for _, method in ipairs({ "ChooseFrameType", "UpdateStackSplitFrame", "UpdateStackText" }) do
		if type(f[method]) == "function" then
			hooksecurefunc(f, method, Refresh)
		end
	end
end

function M:OnEnable(db)
	self.db = db
	if Window() then
		Hook()
		SyncSafe()
	end
end

function M:OnDisable()
	SyncSafe()
end

--------------------------------------------------------------------------------
-- /splitdump [frames | reps | regions]: with no mode, every part found (or
-- not) and what it was dressed as, the field against the amount, the inked
-- strings, the box's own regions and children; the modes are
-- Kit:DumpWindow's. Opens the copy window.
--------------------------------------------------------------------------------
local function Label(obj)
	if not obj then
		return "nil"
	end
	local n = NameOf(obj)
	if n then
		return n
	end
	local ok, d = pcall(obj.GetDebugName, obj)
	if ok and type(d) == "string" and not Secret(d) then
		return d
	end
	return "[unnamed]"
end

local function Found(label, obj, more)
	MelloUI:Print("  %-26s %s%s", label, obj and Label(obj) or "-- not found", more or "")
end

local function Shown(obj)
	local ok, s = pcall(obj.IsShown, obj)
	return (ok and not Secret(s)) and tostring(s) or "?"
end

local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.0f", v) or "?"
end

local function Rect(obj)
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if ok and l and not Secret(l) then
		return string.format("x=%s y=%s w=%s h=%s", Num(l), Num(b), Num(w), Num(h))
	end
	return "(no rect)"
end

local function TextOf(fs)
	local ok, t = pcall(fs.GetText, fs)
	if ok and type(t) == "string" and not Secret(t) then
		return (t:gsub("\n", " | ")):sub(1, 50)
	end
	return "?"
end

local function Faded(obj)
	return obj and (Kit.faded[obj] and "faded" or "not faded") or "-"
end

local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer, sub = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "") .. (Kit.faded[region] and " FADED" or "")
		elseif kind == "FontString" then
			art = "text: " .. TextOf(region)
		end
		local okA, alpha = pcall(region.GetAlpha, region)
		MelloUI:Print("    region %s %s %s/%s %s alpha %s shown %s", kind, Label(region), okL and tostring(layer) or "?", okL and tostring(sub) or "?", art,
			(okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?", Shown(region))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local okLv, lv = pcall(child.GetFrameLevel, child)
		MelloUI:Print("    child %s %s level %s shown %s%s", tostring(child:GetObjectType()), Label(child),
			okLv and Num(lv) or "?", Shown(child), child.melloSkin and " (kit skin)" or "")
	end
end

SLASH_MELLOSPLITDUMP1 = "/splitdump"
SlashCmdList.MELLOSPLITDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if not f then
		MelloUI:Print("/splitdump: no StackSplitFrame on this client")
	elseif msg == "" then
		local okLv, lv = pcall(f.GetFrameLevel, f)
		MelloUI:Print("StackSplitFrame: shown %s, %s, level %s, layout %s, multi-stack %s; kit %s, parchment %s", Shown(f), Rect(f),
			okLv and Num(lv) or "?", tostring(f.layoutType), tostring(f.isMultiStack), active and "on" or "off",
			tostring(Kit.ParchmentOn and Kit:ParchmentOn(AREA)))
		Found("kit rail + stone", skin and skin.nine, skin and string.format(" shown %s, sheet shown %s, inner panel shown %s", Shown(skin.nine),
			skin.sheet and Shown(skin.sheet) or "-", skin.dim and Shown(skin.dim) or "-") or " (not built)")
		local p = Parts(f)
		Found("picture (one item)", p.single, p.single and (" " .. Faded(p.single) .. ", shown " .. Shown(p.single)) or nil)
		Found("picture (stacks)", p.multi, p.multi and (" " .. Faded(p.multi) .. ", shown " .. Shown(p.multi)) or nil)
		local plate = skin and skin.plate
		Found("edit plate (the field)", plate and plate.strip, plate and string.format(" %s, shown %s, caps l %s (end %s) r %s",
			Rect(plate.strip), Shown(plate.strip), Shown(plate.strip.capL), tostring(plate.strip.endL), Shown(plate.strip.capR)) or nil)
		for _, key in ipairs({ "text", "count" }) do
			local fs = p[key]
			if fs then
				local okL, layer, sub = pcall(fs.GetDrawLayer, fs)
				Found(key == "text" and "amount" or "total", fs, string.format(" \"%s\" %s, layer %s/%s, inked %s, shown %s", TextOf(fs), Rect(fs),
					okL and tostring(layer) or "?", okL and tostring(sub) or "?", tostring(fs.melloInk ~= nil), Shown(fs)))
			else
				Found(key == "text" and "amount" or "total", nil)
			end
		end
		for _, entry in ipairs({ { "left arrow", p.left }, { "right arrow", p.right } }) do
			local b = entry[2]
			local dressed
			for _, a in ipairs(skin and skin.arrows or {}) do
				if a.button == b then
					dressed = a
				end
			end
			local okE, enabled = false, nil
			if b then
				okE, enabled = pcall(b.IsEnabled, b)
			end
			Found(entry[1], b, b and string.format(" %s, dressed %s, enabled %s, arrow alpha %s", Rect(b), tostring(dressed ~= nil),
				(okE and not Secret(enabled)) and tostring(enabled) or "?", dressed and string.format("%.2f", dressed.rep.object:GetAlpha()) or "-") or nil)
		end
		for _, entry in ipairs({ { "okay", p.okay }, { "cancel", p.cancel } }) do
			local b = entry[2]
			Found(entry[1], b, b and string.format(" red plate %s, label kept %s", tostring(skin and skin.buttons[b]), tostring(b.melloNoInk == true)) or nil)
		end
		local QI = MelloUI.QuestInk
		local def = QI and QI.surfaces and QI.surfaces[SURFACE]
		local n = 0
		MelloUI:Print("inked strings (parchment ink %s):", tostring(InkOn()))
		for fs in pairs(def and def.strings or {}) do
			n = n + 1
			MelloUI:Print("  %s \"%s\"", Label(fs), TextOf(fs))
		end
		MelloUI:Print("  %d inked", n)
		MelloUI:Print("StackSplitFrame's own regions and children:")
		DumpOwn(f)
	else
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	end
	MelloUI:ShowLog("splitdump " .. msg)
end
