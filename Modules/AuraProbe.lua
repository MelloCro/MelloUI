--------------------------------------------------------------------------------
-- MelloUI - Aura probe (/melloaura)
--
-- A developer probe for 0.20.0's Raid Frame Designer (docs/plans/
-- raid-frame-designer.md, "Aura research"): it tries the game's secret-safe
-- aura widget, CustomAuraContainerTemplate (Blizzard_AuraContainer), on a
-- stand-in raid frame for one unit -- you, solo, by default: the game shows
-- party frames only in a group (GroupFrameVisibility.lua). The containers read
-- the auras themselves, secret or not, and fill the regions handed to their
-- buttons; MelloUI never reads an aura here, and nothing it is told back is
-- compared (a secret is printed as "secret").
--   /melloaura                 the box for you (made on its first use, never at login)
--   /melloaura unit <unit>     another unit (party1, target ...)
--   /melloaura spell <id>      the top-left icon shows only that spell (matched by
--                              spell ID: the game allows it for helpful auras on
--                              you and your group, in a fight too)
--   /melloaura ids             the unit's buffs with their spell IDs (out of a fight)
--   /melloaura report          what was made, and what the containers show now
--   /melloaura off             hide it
-- On the box: top right a square (a buff of your own, draining as it runs
-- out), top left an icon (the listed spell: its sweep and stacks), along the
-- bottom a bar (a debuff your group can dispel); under the box a row of the
-- buffs and a row of the debuffs.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("AuraProbe")
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number

local P = { unit = "player", spell = nil, errors = {} }
MelloUI.AuraProbe = P   -- (the tests')

-- the box: the game's raid frame (72 x 36) twice; the marks and the rows' icons
local SIZE = { boxW = 144, boxH = 72, icon = 20, mark = 14, bar = 4, pad = 4, gap = 2, row = 8 }
local WHITE = "Interface\\Buttons\\WHITE8X8"   -- look-ok: the drain bars' fill, tinted by palette key

local TEXT = {
	title = "Aura probe: %s",
	made = "Aura probe: the box for %s (top right your own buff, top left the listed spell, the bottom bar a debuff your group can dispel; the buffs and debuffs under it). Fight something, then /melloaura report.",
	failed = "Aura probe: the game's aura container could not be made: %s",
	hidden = "Aura probe: hidden (/melloaura shows it again).",
	unit = "Aura probe: now %s.",
	spell = "Aura probe: the top-left icon shows only spell %d.",
	spellUsage = "Aura probe: /melloaura spell <spell ID>, e.g. /melloaura spell 774 (Rejuvenation).",
	usage = "Aura probe: /melloaura [unit <unit> | spell <id> | ids | report | off]",
	ids = "Aura probe: the buffs on %s now, spell ID and name (give one to /melloaura spell):",
	idsSecret = "  (the rest are secret now: try again out of a fight)",
	noIds = "Aura probe: this client has no aura list to read.",
	noBuffs = "  (no buffs)",
}

local function Say(fmt, ...)
	MelloUI:Print(fmt, ...)
end

-- a value told back by the game: "secret" for a secret, else as it is
local function Shown(v)
	if Secret(v) then
		return "secret"
	end
	return tostring(v)
end

-- one call into the container: its result, or nil with the error kept for
-- the report
local function Try(label, fn, ...)
	if type(fn) ~= "function" then
		P.errors[#P.errors + 1] = label .. ": no such call"
		return nil
	end
	local ok, a = pcall(fn, ...)
	if not ok then
		P.errors[#P.errors + 1] = label .. ": " .. tostring(a)
		return nil
	end
	return a == nil and true or a
end

--------------------------------------------------------------------------------
-- The buttons: each is the container's own (CustomAuraButtonTemplate); we
-- hand it its parts, children of it, and the game fills them
--------------------------------------------------------------------------------

local function Paint(region, key, how)
	local W = MelloUI.Widgets
	if W and W.Paint then
		W.Paint(region, key, how)
	end
end

-- an icon: the aura's picture, its time as a sweep, its stacks
local function IconButton(b)
	b:SetSize(SIZE.icon, SIZE.icon)
	local tex = b:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints(b)
	Try("icon", b.SetIcon, b, tex)
	local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	cd:SetAllPoints(b)
	Try("icon sweep", b.SetDurationCooldown, b, cd)
	local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
	Try("icon stacks", b.SetApplicationCount, b, count)
end

-- a square in the palette's highlight, a bar over it draining with the time left
local function SquareButton(b)
	b:SetSize(SIZE.mark, SIZE.mark)
	local sq = b:CreateTexture(nil, "BACKGROUND")
	sq:SetAllPoints(b)
	Paint(sq, "innerPanel", "fill")
	local bar = CreateFrame("StatusBar", nil, b)
	bar:SetAllPoints(b)
	bar:SetStatusBarTexture(WHITE)
	Paint(bar.GetStatusBarTexture and bar:GetStatusBarTexture(), "selectedTrim", "vertex")
	Try("square drain", b.SetDurationBar, b, bar)
end

-- a thin bar along the box's bottom edge, its length the time left
local function BarButton(b)
	b:SetSize(SIZE.boxW - 2 * SIZE.pad, SIZE.bar)
	local bar = CreateFrame("StatusBar", nil, b)
	bar:SetAllPoints(b)
	bar:SetStatusBarTexture(WHITE)
	Paint(bar.GetStatusBarTexture and bar:GetStatusBarTexture(), "selectedTrim", "vertex")
	Try("bottom bar", b.SetDurationBar, b, bar)
end

-- each dressing run for the game's frame provider, which makes the button:
-- an error of ours kept for the report, never thrown into the container
local function Dress(label, fn)
	return function(b)
		local ok, err = pcall(fn, b)
		if not ok then
			P.errors[#P.errors + 1] = label .. ": " .. tostring(err)
		end
	end
end
local DRESS = { icon = Dress("icon button", IconButton), square = Dress("square button", SquareButton),
	bar = Dress("bar button", BarButton) }

--------------------------------------------------------------------------------
-- The box and its containers (made on the first /melloaura)
--------------------------------------------------------------------------------

-- a container of the game's template; nil and why when the client made none,
-- or made a frame without the template's calls (no Blizzard_AuraContainer)
local function NewContainer(parent)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if not ok then
		return nil, c
	end
	if type(c) ~= "table" or type(c.SetUnit) ~= "function" or type(c.AddAuraSlot) ~= "function" then
		return nil, "no AuraContainer with the template's calls (SetUnit, AddAuraSlot)"
	end
	return c
end

local function SetName()
	local box = P.box
	if box then
		box.title:SetText(TEXT.title:format(P.unit))
		local ok, name = pcall(UnitName, P.unit)
		box.name:SetText(ok and name or "")   -- (SetText takes a secret as it is)
	end
end

local function Build()
	if P.box then
		return true
	end
	local W = MelloUI.Widgets
	local box = CreateFrame("Frame", "MelloUIAuraProbe", UIParent)
	box:SetSize(SIZE.boxW, SIZE.boxH)
	box:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
	box:SetFrameStrata("MEDIUM")
	W.Panel(box, { on = true })
	box.title = W.Text(box, "GameFontNormalSmall", nil, "selectedTrim")
	box.title:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, SIZE.gap)
	box.name = W.Text(box, "GameFontHighlight", nil, "text")
	box.name:SetPoint("CENTER", box, "CENTER", 0, 0)
	P.box = box
	-- the marks on the box: slots we place ourselves
	local marks, err = NewContainer(box)
	if not marks then
		Say(TEXT.failed, tostring(err))
		P.errors[#P.errors + 1] = "marks: " .. tostring(err)
		return false
	end
	marks:SetAllPoints(box)
	P.marks = marks
	Try("marks unit", marks.SetUnit, marks, P.unit)
	local mine = Try("square slot", marks.AddAuraSlot, marks, "mine", "HELPFUL|PLAYER", { initializeFrame = DRESS.square })
	if type(mine) == "table" then
		mine:SetPoint("TOPRIGHT", box, "TOPRIGHT", -SIZE.pad, -SIZE.pad)
	end
	-- (an empty spell list admits nothing until /melloaura spell <id>)
	local list = Try("icon slot", marks.AddAuraSlot, marks, "list", "HELPFUL",
		{ initializeFrame = DRESS.icon, candidateFilters = { includeSpellIDs = {} } })
	if type(list) == "table" then
		list:SetPoint("TOPLEFT", box, "TOPLEFT", SIZE.pad, -SIZE.pad)
	end
	local dispel = Try("bar slot", marks.AddAuraSlot, marks, "dispel", "HARMFUL|RAID_PLAYER_DISPELLABLE", { initializeFrame = DRESS.bar })
	if type(dispel) == "table" then
		dispel:SetPoint("BOTTOM", box, "BOTTOM", 0, SIZE.pad)
	end
	-- the rows under the box: groups the container lays out itself (it sizes
	-- itself then: anchored to the box, nothing anchored to it)
	local rows = NewContainer(box)
	if rows then
		rows:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -SIZE.pad)
		P.rows = rows
		Try("rows unit", rows.SetUnit, rows, P.unit)
		local layout = { elementSpacing = SIZE.gap, lineSpacing = SIZE.gap }
		Try("buff row", rows.AddAuraGroup, rows, "buffs", "HELPFUL",
			{ initializeFrame = DRESS.icon, maxFrameCount = SIZE.row, layout = layout })
		Try("debuff row", rows.AddAuraGroup, rows, "debuffs", "HARMFUL",
			{ initializeFrame = DRESS.icon, maxFrameCount = SIZE.row,
				layout = { elementSpacing = SIZE.gap, lineSpacing = SIZE.gap, forceNewLine = true } })
	end
	SetName()
	return true
end

local function SetSpell(id)
	P.spell = id
	if P.marks then
		Try("spell list", P.marks.SetAuraSlotCandidateFilters, P.marks, "list", { includeSpellIDs = { [id] = true } })
	end
end

local function SetUnit(unit)
	P.unit = unit
	for _, c in ipairs({ P.marks, P.rows }) do
		Try("unit " .. unit, c.SetUnit, c, unit)
	end
	SetName()
end

--------------------------------------------------------------------------------
-- The report: what was made, and what the game shows now (secret or not)
--------------------------------------------------------------------------------

local function SlotState(key)
	local f = P.marks and Try("slot " .. key, P.marks.GetAuraSlotFrame, P.marks, key)
	if type(f) ~= "table" then
		return "none"
	end
	local ok, shown = pcall(f.IsShown, f)
	return ok and Shown(shown) or "unreadable"
end

local function Report()
	local okS, secret = pcall(C_Secrets and C_Secrets.ShouldAurasBeSecret or function() return nil end)
	Say("Aura probe report: unit %s, in a fight %s, auras secret now %s, made: box %s, marks %s, rows %s",
		P.unit, tostring(InCombatLockdown() and true or false), okS and Shown(secret) or "?",
		tostring(P.box ~= nil), tostring(P.marks ~= nil), tostring(P.rows ~= nil))
	if P.marks then
		Say("  square (your own buff) shown: %s; icon (spell %s) shown: %s; bar (dispellable debuff) shown: %s",
			SlotState("mine"), tostring(P.spell or "none"), SlotState("list"), SlotState("dispel"))
	end
	if P.rows then
		local b = Try("buff count", P.rows.GetAuraGroupFrameCount, P.rows, "buffs")
		local d = Try("debuff count", P.rows.GetAuraGroupFrameCount, P.rows, "debuffs")
		Say("  rows: %s buff, %s debuff frames", Shown(Num(b) or b), Shown(Num(d) or d))
	end
	if #P.errors > 0 then
		Say("  %d errors (first: %s)", #P.errors, P.errors[1])
		for i = 2, math.min(#P.errors, 6) do
			Say("  - %s", P.errors[i])
		end
	else
		Say("  no errors")
	end
end

-- the unit's buffs now with their spell IDs, to pick one for /melloaura
-- spell: plain out of a fight; a secret one stops the list (nothing compared)
local function Ids()
	local get = C_UnitAuras and C_UnitAuras.GetUnitAuras
	local ok, list = false, nil
	if type(get) == "function" then
		ok, list = pcall(get, P.unit, "HELPFUL")
	end
	if not ok or type(list) ~= "table" then
		Say(TEXT.noIds)
		return
	end
	Say(TEXT.ids, P.unit)
	local n = 0
	for _, aura in ipairs(list) do
		local id, name = aura.spellId, aura.name
		if Secret(id) or Secret(name) then
			Say(TEXT.idsSecret)
			return
		end
		n = n + 1
		Say("  %s  %s", tostring(id), tostring(name))
	end
	if n == 0 then
		Say(TEXT.noBuffs)
	end
end

--------------------------------------------------------------------------------
-- /melloaura
--------------------------------------------------------------------------------

SLASH_MELLOAURA1 = "/melloaura"
SlashCmdList.MELLOAURA = Perf.Shared("/melloaura", function(msg)
	local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
	if cmd == "" then
		if Build() then
			P.box:Show()
			Say(TEXT.made, P.unit)
		end
	elseif cmd == "off" then
		if P.box then
			P.box:Hide()
		end
		Say(TEXT.hidden)
	elseif cmd == "unit" and arg ~= "" then
		if Build() then
			SetUnit(arg)
			P.box:Show()
			Say(TEXT.unit, arg)
		end
	elseif cmd == "spell" then
		local id = tonumber(arg)
		if not id then
			Say(TEXT.spellUsage)
		elseif Build() then
			SetSpell(id)
			P.box:Show()
			Say(TEXT.spell, id)
		end
	elseif cmd == "report" then
		Report()
	elseif cmd == "ids" then
		Ids()
	else
		Say(TEXT.usage)
	end
end, "script")
