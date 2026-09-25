--------------------------------------------------------------------------------
-- MelloUI - AddOn List Kit
--
-- (user, 2026-09-24: "and the macros menu, edit mode menu, addons list, and
-- the whole options settings menu"): the AddOn list (AddonList: the
-- character dropdown, "Load out of date AddOns", the search box, the AddOn
-- Usage block, the scrolling list of addons, Enable All / Disable All, Okay /
-- Cancel) dressed in the painted kit (Modules/Kit.lua) on the game's own
-- layout, by the rule book's fixed looks (docs/WINDOW-RULES.md):
--   the window shell of a window without a portrait (the outer double rail
--   with its gem corners, the title plate riding the rail, the page stone,
--   the close button); the list's inset on the single rail with the darker
--   list-box stone (a list's text must read on it, as the social window's);
--   the line under the AddOn Usage block on the divider strip, the block's
--   header in the title face; every row's check box on the kit's, its Load
--   AddOn button and the window's buttons on the red plates (B1), a group's
--   expand / collapse glyph on the plus / minus plates, the row's hover on
--   the quest log's hover plate (shown on hover only); the dropdown (D1), the
--   search box (S1) and the scroll bar (T2 / H1 / S1) by the sweep.
-- MelloUI's own row keeps MelloUI's icon: should this client not read the
-- TOC's icon and draw the question mark instead, the logo is put in its
-- place (and the game's put back when the reskin is switched off).
--
-- The window may be made with the interface or only when the game first
-- opens it (a load-on-demand Blizzard_AddOnList): it is hooked whenever it
-- turns up (ADDON_LOADED / PLAYER_LOGIN) and dressed the first time it shows
-- (Sync), its pooled rows each time the list initialises one. Nothing of
-- the game's is replaced or re-scripted: post hooks, HookScript and events
-- only, our own state in weak side tables.
-- Switched off, every piece is hidden and every faded region comes back; the
-- header's font, the logo and the check boxes' grey tick are put back.
--
-- /addonlistdump [entries | art | frames | reps]: what the window is made of
-- on this client, to fit the skin to it.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("AddonListPanel")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("AddonListPanel", {
	title = "AddOn List Kit",
	desc = "The AddOn list dressed in the painted kit on the game's own layout.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local LOGO = "Interface\\AddOns\\MelloUI\\Media\\Textures\\LogoIcon"
local QUESTION_MARK_ID = 134400                  -- Interface\ICONS\INV_Misc_QuestionMark, as the file id it reads back as
local HOVER_KEY = "questlog-quest-glow-yellow"   -- the quest log's row hover plate (lists/plate, hover)
local DIVIDER_KEY = "QuestLog-frame-devider"     -- the window/divider strip

local skin = nil          -- { reps = {}, followers = {} } once built
local active = false
local hooked = false

-- Our state beside the game's frames, never written onto them (weak keys:
-- nothing here holds a frame the game lets go of).
local entries = setmetatable({}, { __mode = "k" })      -- [row] = { plate = rep, checks = {}, toggles = {}, icon = {}, text = {} }
local partial = setmetatable({}, { __mode = "k" })      -- [check box] = true while the game shows "enabled for some characters"
local toggleAsset = setmetatable({}, { __mode = "k" })  -- [toggle button] = the art the game handed it last (a file reads back as an id)
local toggleReps = setmetatable({}, { __mode = "k" })   -- [toggle button] = { plus = rep, minus = rep }
local found = { dividers = {}, dropdowns = {} }         -- what the build found, for the dump
local listOwner = {}                                    -- our own key in the list's callback registry

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe and MelloUI.Safe.IsSecret or issecretvalue

local function Window()
	return _G.AddonList
end

local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("AddOn list: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

local function MouseOver(frame)
	local ok, over = pcall(frame.IsMouseOver, frame)
	return ok and not Secret(over) and over == true
end

-- The list: the game's ScrollBox (a child with a scroll target and
-- ForEachFrame), whatever key this client keeps it under
local function ListBox(al)
	if al.ScrollBox and al.ScrollBox.ForEachFrame then
		return al.ScrollBox
	end
	local function Find(root, depth)
		if depth > 3 then
			return nil
		end
		for _, child in ipairs({ root:GetChildren() }) do
			if child.ForEachFrame and child.ScrollTarget then
				return child
			end
			local deeper = Find(child, depth + 1)
			if deeper then
				return deeper
			end
		end
		return nil
	end
	return Find(al, 0)
end

-- The AddOn Usage block (current / average / peak CPU), under the keys a
-- client may use
local function UsageBlock(al)
	return al.Performance or al.PerformanceFrame or al.AddonUsage or al.Usage
end

--------------------------------------------------------------------------------
-- A row of the list (pooled): its hover plate, the enable check box, the
-- Load AddOn button, a group's expand / collapse glyph, MelloUI's icon.
--------------------------------------------------------------------------------

-- The hover plate is refitted each time it is shown, as the quest log's: a
-- pooled row may have been laid out again while its plate was hidden.
local function ShowPlate(rep, shown)
	rep.object:SetShown(shown and true or false)
	if shown then
		rep:Refit()
	end
end

-- The plate belongs on the row the mouse is on only. The row's own OnLeave
-- fires when the pointer moves onto its check box, so the test is the row's
-- rectangle (IsMouseOver), not the last enter / leave.
local function SyncHover(row)
	local st = entries[row]
	if st and st.plate then
		ShowPlate(st.plate, active and MouseOver(row))
	end
end

local function RowEnterLeave(self)
	-- `self` is the row or one of its controls
	SyncHover(entries[self] and self or self:GetParent())
end

-- The game's own highlight of a row, if it has one (a highlight texture, or
-- a region in the HIGHLIGHT layer): faded under the kit's plate
local function RowHighlights(row)
	local list, seen = {}, {}
	local hl = row.GetHighlightTexture and row:GetHighlightTexture()
	if hl then
		list[1], seen[hl] = hl, true
	end
	for _, region in ipairs({ row:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece and not seen[region] then
			local ok, layer = pcall(region.GetDrawLayer, region)
			if ok and layer == "HIGHLIGHT" then
				list[#list + 1], seen[region] = region, true
			end
		end
	end
	return list
end

-- "Enabled for some characters": the game gives the check box its grey
-- (disabled) tick for it; the kit's tick is shown greyed the same way, its
-- own art desaturated -- no colour of ours
local function SyncPartial(cb)
	local rep = cb.melloRep
	local tex = rep and rep.object
	if tex and tex.SetDesaturated then
		tex:SetDesaturated(active and partial[cb] == true)
	end
end

-- The game may hand the check box a new checked texture on a refresh:
-- should that be another object than the one faded, it is faded too
local function KeepFaded(rep, region)
	if not (rep and region) or region == rep.region then
		return
	end
	for _, r in ipairs(rep.alsoFade) do
		if r == region then
			return
		end
	end
	rep.alsoFade[#rep.alsoFade + 1] = region
	if active then
		Kit:Fade(region)
	end
end

local function PartialFrom(asset)
	if type(asset) == "string" and not Secret(asset) then
		return asset:lower():find("disabled", 1, true) ~= nil
	end
	return nil
end

local function SkinRowCheck(cb, st)
	if st.checks[cb] then
		return
	end
	st.checks[cb] = true
	local normal = cb.GetNormalTexture and cb:GetNormalTexture()
	local key = normal and Kit:ArtKey(normal)
	Kit:SkinCheckButton(cb, Replace, (key and Kit:RuleFor(key)) and key or "UI-CheckBox-Up")
	local function Checked(b, asset)
		local p = PartialFrom(asset)
		if p == nil then
			-- an atlas or a texture object: read what the game made of it
			local tex = b:GetCheckedTexture()
			local ok, d = pcall(function() return tex and tex:IsDesaturated() end)
			p = ok and not Secret(d) and d == true
		end
		partial[b] = p or nil
		if b.melloRep then
			KeepFaded(b.melloRep, b:GetCheckedTexture())
		end
		SyncPartial(b)
	end
	hooksecurefunc(cb, "SetCheckedTexture", Checked)
	if cb.SetCheckedAtlas then
		hooksecurefunc(cb, "SetCheckedAtlas", Checked)
	end
	-- the row's hover stays lit while the pointer is on its check box
	Perf.HookScript(cb, "OnEnter", RowEnterLeave)
	Perf.HookScript(cb, "OnLeave", RowEnterLeave)
	-- what the game set before we came (its file path, where the client
	-- still gives one; the next refresh passes through the hook above)
	local tex = cb:GetCheckedTexture()
	local ok, file = pcall(function() return tex and tex.GetTextureFilePath and tex:GetTextureFilePath() end)
	if ok then
		partial[cb] = PartialFrom(file) or nil
	end
	SyncPartial(cb)
end

-- A group row's expand / collapse glyph: the plus / minus plate for what
-- the game shows there (read from its atlas, or from the art the game handed
-- it last when a file reads back as an id). Art that is neither stays the
-- game's.
local GLYPH_RULE = { plus = "common-button-list-plus", minus = "common-button-list-minus" }

local function GlyphKind(key)
	if type(key) ~= "string" or Secret(key) then
		return nil
	end
	key = key:lower()
	if key:find("plus", 1, true) or key:find("expand", 1, true) or key:find("closed", 1, true) then
		return "plus"
	end
	if key:find("minus", 1, true) or key:find("collapse", 1, true) or key:find("shrink", 1, true) or key:find("open", 1, true) then
		return "minus"
	end
	return nil
end

local function ToggleTexture(button)
	return button.Icon or (button.GetNormalTexture and button:GetNormalTexture())
end

local function SyncToggle(button)
	local tex = ToggleTexture(button)
	if not (tex and active) then
		return
	end
	local kind = GlyphKind(Kit:ArtKey(tex)) or GlyphKind(toggleAsset[button])
	local reps = toggleReps[button]
	if kind and not (reps and reps[kind] ~= nil) then
		reps = reps or {}
		toggleReps[button] = reps
		local extra = {}
		for _, region in ipairs({ button:GetRegions() }) do
			if region ~= tex and region:GetObjectType() == "Texture" and not region.kitPiece then
				extra[#extra + 1] = region
			end
		end
		reps[kind] = Replace(tex, { as = GLYPH_RULE[kind], button = button, rect = tex, alsoFade = extra }) or false
	end
	for k, rep in pairs(reps or {}) do
		if rep then
			if k == kind then
				rep:Enable()           -- idempotent: the glyph faded, the plate shown
			elseif kind then
				rep.object:Hide()      -- the other plate; the glyph stays faded by this one's twin
			else
				rep:Disable()          -- art we have no plate for: the game's glyph back
			end
		end
	end
end

local function SkinRowToggle(button, st)
	if st.toggles[button] then
		return
	end
	st.toggles[button] = true
	local function Asset(b, asset)
		if type(asset) == "string" and not Secret(asset) then
			toggleAsset[b] = asset
		end
		SyncToggle(b)
	end
	for _, method in ipairs({ "SetNormalAtlas", "SetNormalTexture" }) do
		if button[method] then
			hooksecurefunc(button, method, Asset)
		end
	end
	if button.Icon then
		for _, method in ipairs({ "SetAtlas", "SetTexture" }) do
			hooksecurefunc(button.Icon, method, function(_, asset)
				Asset(button, asset)
			end)
		end
	end
	Perf.HookScript(button, "OnEnter", RowEnterLeave)
	Perf.HookScript(button, "OnLeave", RowEnterLeave)
	SyncToggle(button)
end

-- The addon a row shows: its index from the row's data (a tree node's data,
-- a plain table, a number), else from the row itself
local function AddonIndex(row, elementData)
	local data = elementData
	if type(data) == "table" and data.GetData then
		local ok, d = pcall(data.GetData, data)
		data = ok and d or nil
	end
	local index
	if type(data) == "number" then
		index = data
	elseif type(data) == "table" then
		index = data.addonIndex or data.index or data.addon
	end
	if index == nil then
		index = row.addonIndex
	end
	if index == nil and row.GetID then
		local ok, id = pcall(row.GetID, row)
		if ok and not Secret(id) and type(id) == "number" and id > 0 then
			index = id
		end
	end
	if Secret(index) then
		return nil
	end
	return index
end

local function PlainText(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

local function IsMelloUI(row, elementData)
	local index = AddonIndex(row, elementData)
	if index ~= nil then
		local info = (C_AddOns and C_AddOns.GetAddOnInfo) or _G.GetAddOnInfo
		local ok, name = pcall(info, index)
		if ok and type(name) == "string" and not Secret(name) then
			return name:find("^MelloUI") ~= nil
		end
	end
	local title = row.Title
	local ok, text = pcall(function() return title and title:GetText() end)
	if ok and type(text) == "string" and not Secret(text) then
		return PlainText(text):find("MelloUI", 1, true) ~= nil
	end
	return false
end

-- What SyncIcon changed on a row, put back (the row is pooled: it may show
-- another addon now, or the reskin is going off)
local function RestoreIcon(st)
	local t = st.text
	if t.fs and t.ours then
		local ok, now = pcall(t.fs.GetText, t.fs)
		if ok and now == t.ours then
			t.fs:SetText(t.original)
		end
	end
	st.text = {}
	local i = st.icon
	if i.tex and i.ours then
		i.tex:SetTexture(i.original)
	end
	st.icon = {}
end

-- MelloUI's logo in place of the question mark the game draws for an addon
-- whose icon it could not read -- on MelloUI's row only
local function SyncIcon(row, elementData)
	local st = entries[row]
	if not st then
		return
	end
	RestoreIcon(st)
	if not (active and IsMelloUI(row, elementData)) then
		return
	end
	-- an icon region of its own
	local icon = row.Icon or row.AddonIcon
	if icon and icon.GetTexture then
		local ok, file = pcall(icon.GetTexture, icon)
		if ok and not Secret(file) and (file == QUESTION_MARK_ID or (type(file) == "string" and file:lower():find("questionmark", 1, true))) then
			st.icon = { tex = icon, original = file, ours = true }
			icon:SetTexture(LOGO)
		end
	end
	-- or the icon drawn in the title's text (|T...|t before the name)
	local fs = row.Title
	local ok, text = pcall(function() return fs and fs:GetText() end)
	if ok and type(text) == "string" and not Secret(text) then
		local s, e = text:find("|T[^|]-|t")
		if s and text:sub(s, e):lower():find("questionmark", 1, true) then
			local dims = text:sub(s, e):match("^|T[^:|]*(.-)|t$") or ""
			local ours = text:sub(1, s - 1) .. "|T" .. LOGO .. dims .. "|t" .. text:sub(e + 1)
			st.text = { fs = fs, original = text, ours = ours }
			fs:SetText(ours)
		end
	end
end

-- One row: its pieces made once, synced on every initialisation (the game
-- re-uses it for another addon, a group or a child)
local function SkinRow(row, elementData)
	if not (row and row.GetChildren) then
		return
	end
	local st = entries[row]
	if not st then
		st = { checks = {}, toggles = {}, icon = {}, text = {} }
		entries[row] = st
		-- the hover plate: the quest log's, under the row's text (a frame one
		-- level under the row), in place of the game's highlight if it has one
		local plate = Replace(row, { as = HOVER_KEY, parent = row, rect = row, noFade = true, alsoFade = RowHighlights(row) })
		if plate then
			plate.SetShown = ShowPlate
			plate.onEnable = function()
				SyncHover(row)
			end
			st.plate = plate
			Perf.HookScript(row, "OnEnter", RowEnterLeave)
			Perf.HookScript(row, "OnLeave", RowEnterLeave)
		end
	end
	-- its controls (looked at on every init: a row may show a group's toggle
	-- only as a group)
	local controls = { row:GetChildren() }
	local enabled = row.Enabled
	if type(enabled) == "table" and enabled.GetObjectType then
		controls[#controls + 1] = enabled
	end
	for _, child in ipairs(controls) do
		local kind = child:GetObjectType()
		if kind == "CheckButton" then
			SkinRowCheck(child, st)
		elseif kind == "Button" and (child.Center or (child.Left and child.Middle and child.Right)) then
			Kit:SkinRedButton(child, Replace)        -- Load AddOn
		elseif kind == "Button" and ToggleTexture(child) then
			SkinRowToggle(child, st)
		end
	end
	for cb in pairs(st.checks) do
		SyncPartial(cb)
	end
	for button in pairs(st.toggles) do
		SyncToggle(button)
	end
	SyncHover(row)
	SyncIcon(row, elementData)
end

-- Every row the list holds now, or the named rows of a client whose list is
-- the old scroll frame (AddonListEntry1..n)
local function ForEachRow(fn)
	local al = Window()
	local box = al and ListBox(al)
	if box then
		pcall(box.ForEachFrame, box, function(row, elementData)
			fn(row, elementData)
			-- (nothing returned: a value would stop the iteration)
		end)
	end
	for i = 1, 60 do
		local row = _G["AddonListEntry" .. i]
		if not row then
			break
		end
		fn(row, nil)
	end
end

local function RefreshRows()
	ForEachRow(function(row, elementData)
		if active then
			SkinRow(row, elementData)
		elseif entries[row] then
			RestoreIcon(entries[row])
			for cb in pairs(entries[row].checks) do
				SyncPartial(cb)
			end
		end
	end)
end

local function HookList(al)
	local box = ListBox(al)
	if box and ScrollUtil and ScrollUtil.AddInitializedFrameCallback and not found.listHooked then
		found.listHooked = true
		-- after the row's own Init: what it shows (a group, a child, MelloUI)
		-- is known only then; under our own owner key, so no other listener
		-- of the list is displaced
		ScrollUtil.AddInitializedFrameCallback(box, function(_, row, elementData)
			if active then
				SkinRow(row, elementData)
			end
		end, listOwner, false)
	end
	if _G.AddonList_Update and not found.updateHooked then
		found.updateHooked = true
		hooksecurefunc("AddonList_Update", function()
			if active then
				RefreshRows()
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- The window's other parts
--------------------------------------------------------------------------------

-- An old-style dropdown (UIDropDownMenuTemplate: Left / Middle / Right file
-- art 64 px tall round a 24 px box, an arrow Button): D1 on the box, the
-- arrow faded, as the guild window's. A modern one (WowStyle1Dropdown) is
-- the sweep's.
local function SkinOldDropdowns(root, depth)
	depth = depth or 0
	if depth > 3 then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		if child.Middle and child.Left and child.Right and child.Button and child.Text and child:GetObjectType() == "Frame"
			and child.melloRep == nil then
			local extra = { child.Left, child.Right }
			for _, region in ipairs({ child.Button:GetRegions() }) do
				if region:GetObjectType() == "Texture" then
					extra[#extra + 1] = region
				end
			end
			child.melloRep = Replace(child.Middle, { as = "UIDropDownMenu", rect = child, fitHeight = 24, alsoFade = extra }) or false
			found.dropdowns[#found.dropdowns + 1] = child
		elseif not (child.ForEachFrame and child.ScrollTarget) then
			SkinOldDropdowns(child, depth + 1)
		end
	end
end

-- The line between the AddOn Usage block and the list, found by what it IS
-- (a texture a few px tall and wide, or one whose art names a divider or a
-- line), not by a key: among the window's own regions and its plain frames',
-- never inside its border, title, inset, list, scroll bar or controls.
local function DividerCandidate(region)
	if region:GetObjectType() ~= "Texture" or region.kitPiece then
		return false
	end
	local okL, layer = pcall(region.GetDrawLayer, region)
	if not okL or layer == "HIGHLIGHT" then
		return false
	end
	local ok, w, h = pcall(region.GetSize, region)
	if not ok or Secret(w) or Secret(h) or not (w and h) then
		return false
	end
	local key = Kit:ArtKey(region)
	key = type(key) == "string" and key:lower() or ""
	local named = (key:find("divider", 1, true) or key:find("devider", 1, true) or key:find("line", 1, true)) and h <= 24
	return (w >= 60 and h > 0 and h <= 6) or (named and true or false)
end

-- the divider strip's own thickness (its painted box), not the game line's
-- 1 or 2 px: the strip is fitted to that, centred on the line
local function DividerThickness()
	local p = Kit:Piece("window/divider_mid")
	if p and p.box then
		return (p.box[4] - p.box[2]) * Kit.scale
	end
	return p and p.h * Kit.scale or 8
end

local function SkinDividers(al)
	local skipFrames = {}
	for _, key in ipairs({ "NineSlice", "TitleContainer", "Inset", "PortraitContainer", "ScrollBar" }) do
		if al[key] then
			skipFrames[al[key]] = true
		end
	end
	-- the list's stone lies on a holder at least one level above the window
	-- (Kit:SkinInset); the line goes one above that, so the stone never
	-- covers it whichever frame the game made it a region of
	local inset = al.Inset
	local ok, alLevel, insetLevel = pcall(function() return al:GetFrameLevel(), inset and inset:GetFrameLevel() or al:GetFrameLevel() end)
	local lineLevel = ok and (alLevel + math.max(insetLevel - alLevel, 1) + 1) or nil
	local function Scan(frame, depth)
		for _, region in ipairs({ frame:GetRegions() }) do
			if region ~= al.Bg and region ~= al.TopTileStreaks and found.dividers[region] == nil and DividerCandidate(region) then
				local parent = region:GetParent()
				local level = lineLevel and (lineLevel - parent:GetFrameLevel()) or 1
				found.dividers[region] = Replace(region, { as = DIVIDER_KEY, rect = region, parent = parent, level = level,
					fitHeight = DividerThickness() }) or false
			end
		end
		if depth >= 2 then
			return
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			-- plain frames only: buttons, boxes, bars and the list are not walked
			if child:GetObjectType() == "Frame" and not skipFrames[child] and not (child.ForEachFrame and child.ScrollTarget) then
				Scan(child, depth + 1)
			end
		end
	end
	Scan(al, 0)
end

-- The AddOn Usage header in the title face (titles and headers only)
local function UsageHeader(al)
	local block = UsageBlock(al)
	return block and (block.Header or block.Title or block.Label) or nil
end

local function HeaderFont(on)
	local al = Window()
	local fs = al and UsageHeader(al)
	if fs and fs.GetObjectType and fs:GetObjectType() == "FontString" then
		Kit:TitleFont(fs, on)
	end
end

--------------------------------------------------------------------------------
-- Building the skin
--------------------------------------------------------------------------------
local function Build()
	local al = Window()
	if skin or not al then
		return skin
	end
	skin = { reps = {}, followers = {} }
	-- the divider first: found among the game's textures before any of ours exist
	SkinDividers(al)
	-- the shell of a window without a portrait (WINDOW-RULES: no ring, the
	-- corner keeps its gem until the title plate's caps take the top corners),
	-- the rock as the page stone and the rail without its own body (one
	-- background per window)
	Kit:SkinWindowShell(al, Replace, skin, { noRing = true, bg = "UI-Background-Rock" })
	-- the list on the darker list-box stone inside the single rail
	if al.Inset then
		Kit:SkinInset(al.Inset, Replace, al, true)
		-- the rows over their stone (user, 2026-09-24: the list showed empty
		-- -- the inset stands a level above the list here, and its stone,
		-- at the inset's level, hid every row): the stone one level under
		-- the list
		local rep = al.Inset.melloRep
		local list = ListBox(al)
		if rep and rep.object and rep.object.SetFrameLevel and list then
			local okL, listLevel = pcall(list.GetFrameLevel, list)
			if okL and listLevel and not Secret(listLevel) then
				rep.object:SetFrameLevel(math.max(listLevel - 1, 0))
			end
		end
		-- (the inset's box lays the palette's inner panel over its stone
		-- itself: its rule's `dim`, WINDOW-RULES 2e; user, 2026-09-24: "eye
		-- strain again")
	end
	-- the bottom buttons side by side in pairs: their plates meet without the
	-- gems between them (user, 2026-09-24: the caps crowded each other), the
	-- pair's outer ends keep theirs
	for key, drop in pairs({ EnableAllButton = "r", DisableAllButton = "l", OkayButton = "r", CancelButton = "l" }) do
		if al[key] and Kit.SkinRedButton then
			Kit:SkinRedButton(al[key], Replace, { dropCap = drop })
		end
	end
	SkinOldDropdowns(al)
	-- the check box, search box, dropdown, buttons and scroll bar, by what
	-- they are; the list's rows are ours (SkinRow), not the sweep's
	Kit:SweepControls(al, Replace, skin, ListBox(al))
	-- the character dropdown's band has no arrow of its own (user,
	-- 2026-09-24: "add the dropdown arrow too"): the kit's down arrow on its
	-- right end, at its own size, its hover and pressed looks following the
	-- button
	local dd = al.Dropdown
	if dd and dd.CreateTexture and not skin.ddArrow then
		local arrow = Kit:StateTexture(dd, "buttons/arrow_down", { layer = "OVERLAY", sublevel = 6 })
		local w, h = Kit:Size("buttons/arrow_down_normal")
		arrow:ClearAllPoints()
		arrow:SetSize(w, h)
		arrow:SetPoint("RIGHT", dd, "RIGHT", -3, 0)
		arrow:Hide()
		skin.ddArrow = arrow
	end
	HookList(al)
	return skin
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
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	-- the toggles' plates: Enable showed both, the game shows one glyph
	for button in pairs(toggleReps) do
		SyncToggle(button)
	end
	if skin.ddArrow then
		skin.ddArrow:Show()
	end
	HeaderFont(true)
	RefreshRows()
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
		if skin.ddArrow then
			skin.ddArrow:Hide()
		end
	end
	HeaderFont(false)
	RefreshRows()
end

local Sync

local function Hook()
	local al = Window()
	if hooked or not al then
		return
	end
	hooked = true
	Perf.HookScript(al, "OnShow", function(window)
		if not active then
			-- the first open: built and switched on here and now, before the
			-- first frame is drawn (Build and Activate do all of the below)
			if M.isEnabled then
				Sync()
			end
			return
		end
		-- parts a client makes on first show (the list's rows, a dropdown)
		SkinOldDropdowns(window)
		Kit:SweepControls(window, Replace, skin, ListBox(window))
		HookList(window)
		HeaderFont(true)
		RefreshRows()
	end)
end

-- (user, 2026-09-24: "dress rarely used windows on first open") nothing of the
-- look is built while the list has never been shown: its OnShow (Hook above)
-- builds it before its first frame is drawn, in combat too (only frames and
-- textures of ours, the game's art faded; the list has no protected part),
-- or it is built at once when it is open now. Once built it stays for the
-- session, switched on and off as before.
Sync = function()
	local al = Window()
	if M.isEnabled and al then
		Hook()
		if skin or al:IsShown() then
			Activate()
		end
	else
		Deactivate()
	end
end

-- The window comes with the interface or with its own load-on-demand addon
local watcher = CreateFrame("Frame")
Perf.SetScript(watcher, "OnEvent", function()
	if Window() then
		watcher:UnregisterAllEvents()
		if M.isEnabled then
			Sync()
		end
	end
end)

function M:OnEnable(db)
	self.db = db
	if Window() then
		Sync()
	else
		watcher:RegisterEvent("ADDON_LOADED")
		watcher:RegisterEvent("PLAYER_LOGIN")
	end
end

function M:OnDisable()
	watcher:UnregisterAllEvents()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /addonlistdump [entries | art | frames | reps]: the window on this client.
-- No argument: the parts found (and the keys they are under) and what the
-- skin made of them; "entries": every row the list holds, its regions and
-- children; "art": every visible game texture; "frames" / "reps": the frame
-- tree / our pieces. Opens the copy window.
--------------------------------------------------------------------------------

-- The key a frame keeps a child under (its parentKey), for the dump (in a
-- pcall: a field of a game frame may hold a secret, which cannot be compared)
local function KeyOf(parent, obj)
	if not (parent and obj) then
		return nil
	end
	local ok, key = pcall(function()
		for k, v in pairs(parent) do
			if type(k) == "string" and not Secret(v) and v == obj then
				return k
			end
		end
		return nil
	end)
	return ok and key or nil
end

local function Describe(obj)
	local okN, name = pcall(obj.GetName, obj)
	if okN and name and not Secret(name) then
		return name
	end
	local okD, dname = pcall(obj.GetDebugName, obj)
	if okD and dname and not Secret(dname) then
		return dname
	end
	return "[secret name]"
end

local function SizeText(obj)
	local ok, w, h = pcall(obj.GetSize, obj)
	if ok and w and h and not Secret(w) and not Secret(h) then
		return string.format("%.0f x %.0f", w, h)
	end
	return "? x ?"
end

local function LevelText(obj)
	local ok, level = pcall(obj.GetFrameLevel, obj)
	return (ok and level and not Secret(level)) and tostring(level) or "?"
end

local function DumpRow(row, elementData, n)
	MelloUI:Print("row %d  %s %s  %s  level %s  shown %s  MelloUI %s  index %s  skinned %s", n, row:GetObjectType(), Describe(row),
		SizeText(row), LevelText(row), tostring(row:IsShown()), tostring(IsMelloUI(row, elementData)),
		tostring(AddonIndex(row, elementData)), tostring(entries[row] ~= nil))
	for _, region in ipairs({ row:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer = pcall(region.GetDrawLayer, region)
		local what = ""
		if kind == "Texture" then
			what = "art=" .. tostring(Kit:ArtKey(region)) .. (region.kitPiece and " (kit)" or "")
		elseif kind == "FontString" then
			local ok, text = pcall(region.GetText, region)
			what = "text=" .. ((ok and type(text) == "string" and not Secret(text)) and text:gsub("|", "||"):sub(1, 70) or "?")
		end
		MelloUI:Print("   region %s key=%s layer=%s %s %s", kind, tostring(KeyOf(row, region)), okL and tostring(layer) or "?", SizeText(region), what)
	end
	for _, child in ipairs({ row:GetChildren() }) do
		local normal = child.GetNormalTexture and child:GetNormalTexture()
		local skinned = (child.melloRep ~= nil and child.melloRep ~= false) or toggleReps[child] ~= nil
		MelloUI:Print("   child %s key=%s %s level %s shown %s normal=%s icon=%s kit=%s partial=%s", child:GetObjectType(),
			tostring(KeyOf(row, child)), SizeText(child), LevelText(child), tostring(child:IsShown()), tostring(normal and Kit:ArtKey(normal)),
			tostring(child.Icon and Kit:ArtKey(child.Icon)), tostring(skinned), tostring(partial[child] == true))
	end
end

local function DumpSummary(al)
	MelloUI:Print("AddonList: %s, shown %s, size %s, level %s, strata %s; kit %s, pieces %d", Describe(al), tostring(al:IsShown()),
		SizeText(al), LevelText(al), tostring(al:GetFrameStrata()), active and "on" or "off", skin and #skin.reps or 0)
	if not skin then
		MelloUI:Print("  not dressed yet: the AddOn list is dressed the first time it opens")
	end
	for _, key in ipairs({ "NineSlice", "Bg", "TopTileStreaks", "TitleContainer", "CloseButton", "PortraitContainer", "Inset", "ScrollBox",
		"ScrollBar", "SearchBox", "Dropdown", "ForceLoad", "EnableAllButton", "DisableAllButton", "OkayButton", "CancelButton", "Performance" }) do
		local obj = al[key]
		local state = ""
		if obj and obj.melloRep ~= nil then
			state = " skinned " .. tostring(obj.melloRep ~= false)
		end
		MelloUI:Print("  .%-18s %s", key, obj and (obj:GetObjectType() .. " " .. SizeText(obj) .. state) or "-")
	end
	local box = ListBox(al)
	MelloUI:Print("  list: %s (key %s, level %s), hooked %s", box and Describe(box) or "none found", tostring(box and KeyOf(al, box)),
		box and LevelText(box) or "-", tostring(found.listHooked == true))
	local block = UsageBlock(al)
	MelloUI:Print("  usage block: %s, header key %s", block and (KeyOf(al, block) or Describe(block)) or "none found",
		tostring(block and KeyOf(block, UsageHeader(al))))
	if block then
		for _, region in ipairs({ block:GetRegions() }) do
			local kind = region:GetObjectType()
			local ok, text = pcall(function() return kind == "FontString" and region:GetText() or nil end)
			MelloUI:Print("     %s key=%s %s %s", kind, tostring(KeyOf(block, region)), SizeText(region),
				kind == "Texture" and ("art=" .. tostring(Kit:ArtKey(region))) or ("text=" .. tostring(ok and not Secret(text) and text or "?")))
		end
	end
	local nd = 0
	for region, rep in pairs(found.dividers) do
		nd = nd + 1
		MelloUI:Print("  divider in %s key=%s art=%s %s -> %s", Describe(region:GetParent()), tostring(KeyOf(region:GetParent(), region)),
			tostring(Kit:ArtKey(region)), SizeText(region), rep and "strip" or "none")
	end
	if nd == 0 then
		MelloUI:Print("  divider: none found (no thin line among the window's own textures)")
	end
	local rows = 0
	for _ in pairs(entries) do
		rows = rows + 1
	end
	MelloUI:Print("  old-style dropdowns: %d; rows skinned so far: %d", #found.dropdowns, rows)
end

SLASH_MELLOADDONLISTDUMP1 = "/addonlistdump"
SlashCmdList.MELLOADDONLISTDUMP = function(msg)
	msg = (msg or ""):lower()
	MelloUI:ClearLog()
	local al = Window()
	if not al then
		local lod = "?"
		if C_AddOns and C_AddOns.IsAddOnLoadOnDemand then
			local ok, v = pcall(C_AddOns.IsAddOnLoadOnDemand, "Blizzard_AddOnList")
			lod = ok and tostring(v) or "?"
		end
		MelloUI:Print("/addonlistdump: no AddonList yet (Blizzard_AddOnList load on demand: %s); open the AddOn list once and try again", lod)
	elseif msg == "entries" then
		local n = 0
		ForEachRow(function(row, elementData)
			n = n + 1
			DumpRow(row, elementData, n)
		end)
		if n == 0 then
			MelloUI:Print("No rows: the list makes them when it is first shown.")
		end
	elseif msg == "art" or msg == "frames" or msg == "reps" then
		Kit:DumpWindow(al, skin, msg ~= "art" and msg or nil)
	else
		DumpSummary(al)
	end
	MelloUI:ShowLog("addonlistdump " .. msg)
end
