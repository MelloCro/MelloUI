--------------------------------------------------------------------------------
-- MelloUI - Trainer Kit
--
-- (user, 2026-09-24: "we didnt do quest dialogs, shops, Auction House,
-- profession training window, class trainers, Guild Crest Vendors, Flight
-- map, all should follow the rules"): the trainers' window (ClassTrainerFrame,
-- the load-on-demand Blizzard_TrainerUI), which the class trainers and the
-- profession trainers share, dressed in the painted kit (Modules/Kit.lua) on
-- the game's own layout, by the rule book's fixed looks (docs/WINDOW-RULES.md):
--   the window shell (outer rail, the page stone, the title plate on the
--   rail with the trainer's name on it in the title face, the close button),
--   the trainer's face in the portrait ring at the class medallion's size on
--   the dark disc (2b / 2c); the list's inset on the single rail with the
--   list-box stone under the palette's inner panel (2e), kept under the list;
--   every service row on the list plate (its hover look under the mouse, its
--   selected look on the row the game marks, a red tint on the rows the game
--   marks unavailable), the category headers on the category plate with the
--   kit's plus / minus glyphs, the row icons in every window's Button Border;
--   the profession's rank bar in the Progress Bar Border (P1); the Filter
--   button on the filter band, the Train button on the red plate, the money
--   on the coin plate (as the bags'), the scroll bar the kit's.
--
-- The game's source for this window is not at hand for this client, so every
-- part is FOUND at run time by what it is (a key the templates use, a global
-- name, else its shape), never assumed; what was found and how it was dressed
-- is written by /trainerdump, to fit the skin to the client from.
--
-- Taint: nothing of the game's is replaced or re-scripted, and no trainer
-- function is called: post hooks (hooksecurefunc on the frames' own methods
-- and the update functions, HookScript), ScrollBox callbacks under our own
-- owner key, events on our own frame; our row state in weak side tables.
-- Switched off, every piece is hidden, every faded region comes back, the
-- title strings and the portrait are put back.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("TrainerPanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("TrainerPanel", {
	title = "Trainer Kit",
	desc = "The class and profession trainers' window in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

-- The looks, by the rule keys that already carry them (Kit.Replacements):
-- the same element gets the same piece in every window, no rule of its own.
local PLATE_KEY = "GuildNewsRow"                  -- lists/plate (plain / hover / selected), regions of the row under its text
local CATEGORY_KEY = "LFGBrowse-Grouping"         -- lists/catplate closed, regions of the row under its text
local RIM_KEY = "Profession-square-frame"         -- a slot rim, swapped to every window's Button Border
local BAR_KEY = "UI-Character-Skills-BarBorder"   -- P1, following every window's Progress Bar Border
local GLYPH_RULE = { plus = "common-button-list-plus", minus = "common-button-list-minus" }
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Book_11"

local skin = nil          -- { reps = {}, followers = {} } once built
local active = false
local hooked = false

-- Our state beside the game's frames (weak keys: nothing here keeps a frame
-- the game lets go of)
local rows = setmetatable({}, { __mode = "k" })        -- [row] = its pieces and what was read of it
local assets = setmetatable({}, { __mode = "k" })      -- [button or texture] = the art name the game handed it last
local hookedOnce = setmetatable({}, { __mode = "k" })  -- [object] = true once our hooks are on it
local found = { hooks = {}, syncs = 0, triggers = {} } -- what the build found, for the dump
local listOwner = {}                                   -- our key in the list's callback registry

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe and MelloUI.Safe.IsSecret or issecretvalue

local function Window()
	return _G.ClassTrainerFrame
end

local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Trainer kit: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

local function Shown(region)
	local ok, shown = pcall(region.IsShown, region)
	return ok and not Secret(shown) and shown == true
end

local function MouseOver(frame)
	local ok, over = pcall(frame.IsMouseOver, frame)
	return ok and not Secret(over) and over == true
end

local function IsTexture(obj)
	return type(obj) == "table" and obj.GetObjectType ~= nil and obj:GetObjectType() == "Texture"
end

local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	if ok and type(text) == "string" and not Secret(text) and text ~= "" then
		return text
	end
	return nil
end

local function NameOf(obj)
	local ok, name = pcall(obj.GetName, obj)
	if ok and type(name) == "string" and not Secret(name) then
		return name
	end
	return nil
end

-- A script hooked only where the widget has it (a plain Frame row has no
-- OnClick: HookScript would raise)
local function HookScriptSafe(frame, script, fn)
	if frame.HasScript and frame:HasScript(script) then
		Perf.HookScript(frame, script, fn)
		return true
	end
	return false
end

-- The first field of `obj` that is present, else the global `<name><suffix>`
local function Part(obj, keys, suffixes)
	for _, k in ipairs(keys) do
		local v = obj[k]
		if v ~= nil then
			return v, k
		end
	end
	local name = NameOf(obj)
	if name then
		for _, s in ipairs(suffixes or {}) do
			local v = _G[name .. s]
			if v ~= nil then
				return v, "$parent" .. s
			end
		end
	end
	return nil
end

local function NpcName()
	local ok, name = pcall(UnitName, "npc")
	if ok and type(name) == "string" and not Secret(name) and name ~= "" then
		return name
	end
	return nil
end

-- Whenever the game may have laid the list out again: once, a frame later
-- (after the game's own update, whatever called it)
local RefreshRows   -- below
local pending = false
local function RefreshSoon(why)
	if not active then
		return
	end
	if why then
		found.triggers[why] = (found.triggers[why] or 0) + 1
	end
	if pending then
		return
	end
	pending = true
	C_Timer.After(0, function()
		pending = false
		if active and RefreshRows then
			RefreshRows()
		end
	end)
end

--------------------------------------------------------------------------------
-- The list: the game's ScrollBox (a child with a scroll target and
-- ForEachFrame), or an older scroll frame holding its row buttons (.buttons),
-- whatever key this client keeps it under.
--------------------------------------------------------------------------------
local function FindList(f)
	local box = f.ScrollBox or (f.Inset and f.Inset.ScrollBox)
	if box and box.ForEachFrame then
		return box, "ScrollBox"
	end
	local sf = f.scrollFrame or f.ScrollFrame or _G.ClassTrainerScrollFrame
	if sf and (sf.buttons or sf.scrollChild or sf.ScrollChild) then
		return sf, "scroll frame"
	end
	local function Find(root, depth)
		if depth > 3 then
			return nil
		end
		for _, child in ipairs({ root:GetChildren() }) do
			if child.ForEachFrame and child.ScrollTarget then
				return child, "ScrollBox"
			end
			if type(child.buttons) == "table" and (child.scrollBar or child.ScrollBar) then
				return child, "scroll frame"
			end
			local deeper, kind = Find(child, depth + 1)
			if deeper then
				return deeper, kind
			end
		end
		return nil
	end
	return Find(f, 0)
end

-- The header row above the list that names the next rank to learn (a
-- profession trainer's "Journeyman Cook"): a row like the others
local function StepButton(f)
	return (Part(f, { "skillStepButton", "SkillStepButton", "stepButton", "StepButton" }, { "SkillStepButton" }))
end

--------------------------------------------------------------------------------
-- A row of the list (a service or a category header; an older list re-uses
-- one button for both): one list plate whose state is chosen from the game's
-- own marks, one category plate, the plus / minus glyph, the icon's rim.
--------------------------------------------------------------------------------

-- The glyph a header shows: what its art is called ("UI-PlusButton-Up",
-- "common-button-list-minus", ...). A category PLATE's atlas names both
-- (collapseExpand) and is no glyph.
local function GlyphKind(name)
	if type(name) ~= "string" or Secret(name) then
		return nil
	end
	name = name:lower()
	if name:find("collapseexpand", 1, true) then
		return nil
	end
	if name:find("plus", 1, true) or name:find("expand", 1, true) or name:find("closed", 1, true) then
		return "plus"
	end
	if name:find("minus", 1, true) or name:find("collapse", 1, true) or name:find("shrink", 1, true) or name:find("open", 1, true) then
		return "minus"
	end
	return nil
end

-- The art the game hands a button or texture, remembered as it passes (a
-- file reads back as a number in this client: its name is only seen here)
local function WatchAsset(obj, methods, owner)
	if hookedOnce[obj] then
		return
	end
	hookedOnce[obj] = true
	for _, method in ipairs(methods) do
		if type(obj[method]) == "function" then
			hooksecurefunc(obj, method, function(_, asset)
				if type(asset) == "string" and not Secret(asset) then
					assets[owner or obj] = asset
				elseif asset == nil or asset == "" then
					assets[owner or obj] = nil
				end
				RefreshSoon("glyph art")
			end)
		end
	end
end

-- An entry's data (a tree node's data, a plain table), for the header /
-- collapsed flags a ScrollBox list may carry
local function DataOf(data)
	if type(data) == "table" and data.GetData then
		local ok, d = pcall(data.GetData, data)
		data = ok and d or nil
	end
	return type(data) == "table" and data or nil
end

local function DataFlag(d, keys)
	if not d then
		return nil
	end
	for _, k in ipairs(keys) do
		local ok, v = pcall(function() return d[k] end)
		if ok and not Secret(v) and type(v) == "boolean" then
			return v
		end
	end
	return nil
end

local function IsHeaderData(d)
	if not d then
		return false
	end
	if DataFlag(d, { "isHeader", "isCategory" }) then
		return true
	end
	local ok, kind = pcall(function() return d.type or d.serviceType or d.kind end)
	return ok and type(kind) == "string" and not Secret(kind) and kind:lower() == "header"
end

-- The +/- the game shows on a header, where this client keeps it: a
-- collapse button (its Icon or normal art), an icon region of the row, or
-- the row's own normal art (the older lists)
local GLYPH_BUTTON_KEYS = { "CollapseButton", "ExpandButton", "collapseButton", "expandButton", "ExpandCollapseButton", "toggleButton", "Toggle" }
local GLYPH_REGION_KEYS = { "CollapseIcon", "ExpandIcon", "collapseIcon", "expandIcon", "CollapsedIcon", "ExpandedIcon", "collapsedIcon", "expandedIcon" }

local function GlyphCandidates(row)
	local list = {}
	for _, k in ipairs(GLYPH_BUTTON_KEYS) do
		local b = row[k]
		if type(b) == "table" and b.GetObjectType then
			local tex = b.Icon or (b.GetNormalTexture and b:GetNormalTexture())
			if IsTexture(tex) then
				list[#list + 1] = { tex = tex, owner = b, source = k }
				WatchAsset(b, { "SetNormalAtlas", "SetNormalTexture" })
				WatchAsset(tex, { "SetAtlas", "SetTexture" }, b)
			end
		end
	end
	for _, k in ipairs(GLYPH_REGION_KEYS) do
		local tex = row[k]
		if IsTexture(tex) then
			list[#list + 1] = { tex = tex, owner = row, source = k }
			WatchAsset(tex, { "SetAtlas", "SetTexture" })
		end
	end
	local normal = row.GetNormalTexture and row:GetNormalTexture()
	if IsTexture(normal) then
		list[#list + 1] = { tex = normal, owner = row, source = "normal", normal = true }
		-- (a pooled button that served as a header keeps no stale glyph: a
		-- cleared normal art clears what was remembered)
		WatchAsset(row, { "SetNormalAtlas", "SetNormalTexture", "ClearNormalTexture" })
	end
	return list
end

-- The header's glyph now: the candidate and plus / minus (nil when the art
-- cannot be told)
local function ReadGlyph(row, st)
	for _, c in ipairs(st.glyphCandidates) do
		if Shown(c.tex) and (c.owner == row or Shown(c.owner)) then
			local kind = GlyphKind(Kit:ArtKey(c.tex)) or GlyphKind(assets[c.owner]) or GlyphKind(assets[c.tex])
			if kind then
				return c, kind
			end
		end
	end
	return nil
end

-- The row's icon (a service's spell or recipe), by key, else a square
-- texture at its left end
local function FindIcon(row)
	local icon = Part(row, { "icon", "Icon", "IconTexture", "iconTexture" }, { "Icon", "IconTexture" })
	if IsTexture(icon) then
		return icon
	end
	local okR, rl, rh = pcall(function() return row:GetLeft(), row:GetHeight() end)
	if not (okR and rl and rh) or Secret(rl) or Secret(rh) or rh <= 0 then
		return nil
	end
	for _, region in ipairs({ row:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece and Shown(region) then
			local okL, layer = pcall(region.GetDrawLayer, region)
			local ok, w, h, l = pcall(function() return region:GetWidth(), region:GetHeight(), region:GetLeft() end)
			if okL and layer ~= "HIGHLIGHT" and ok and w and h and l and not (Secret(w) or Secret(h) or Secret(l))
				and w >= 12 and math.abs(w - h) <= 2 and h <= rh + 4 and l - rl <= rh then
				return region
			end
		end
	end
	return nil
end

-- The game's marks on a row, by what they are called: its selected overlay
-- and its unavailable (disabled) backing, as keys or names
local function Mark(st, obj, name)
	local lower = name:lower()
	if lower:find("select", 1, true) then
		st.sel[#st.sel + 1] = obj
	elseif lower:find("disab", 1, true) or lower:find("unavail", 1, true) then
		st.dis[#st.dis + 1] = obj
	end
end

local function FindMarks(row, st)
	local ok = pcall(function()
		for k, v in pairs(row) do
			if type(k) == "string" and IsTexture(v) then
				Mark(st, v, k)
			end
		end
	end)
	if not ok then
		wipe(st.sel)
		wipe(st.dis)
	end
	local seen = {}
	for _, t in ipairs(st.sel) do seen[t] = true end
	for _, t in ipairs(st.dis) do seen[t] = true end
	for _, region in ipairs({ row:GetRegions() }) do
		local name = IsTexture(region) and not seen[region] and NameOf(region)
		if name then
			Mark(st, region, name)
		end
	end
end

local function IsSelected(st)
	if st.locked then
		return true
	end
	for _, t in ipairs(st.sel) do
		if Shown(t) then
			return true
		end
	end
	return false
end

-- Unavailable: the game's disabled backing shown, or its plate tinted red
local function IsUnavailable(row, st)
	for _, t in ipairs(st.dis) do
		if Shown(t) then
			return true
		end
	end
	local normal = row.GetNormalTexture and row:GetNormalTexture()
	if IsTexture(normal) and normal ~= st.icon then
		local ok, r, g, b = pcall(normal.GetVertexColor, normal)
		if ok and r and not (Secret(r) or Secret(g) or Secret(b)) and r > 0.4 and g < r * 0.75 and b < r * 0.75 then
			return true
		end
	end
	return false
end

-- The red of an unavailable row: the palette's selected-row red laid over
-- the plate as a hue (every colour MelloUI draws comes from the palette),
-- three quarters of the way, so the plate's own light and dark stay readable
local WHITE = { 1, 1, 1 }
local UNAVAILABLE_TINT = { 1, 0.5, 0.45 }
do
	local c = MelloUI.Palette and MelloUI.Palette.selectedTab
	if c and c[1] and c[1] > 0 then
		UNAVAILABLE_TINT = { 1, 1 - 0.75 * (1 - c[2] / c[1]), 1 - 0.75 * (1 - c[3] / c[1]) }
	end
end

local function TintPlate(rep, red)
	local strip = rep and rep.strip
	if not strip then
		return
	end
	local t = red and UNAVAILABLE_TINT or WHITE
	for _, tex in ipairs({ strip.capL, strip.mid, strip.capR }) do
		tex:SetVertexColor(t[1], t[2], t[3])
	end
end

-- The game textures a row paints its plate, highlight and marks with: its
-- button art, its selected / disabled overlays, anything in the HIGHLIGHT
-- layer, and every texture at least half the row's size (a backing)
local function PlateRegions(row, st)
	local list, seen = {}, { [st.icon or false] = true }
	local function Add(t)
		if IsTexture(t) and not seen[t] and not t.kitPiece then
			seen[t] = true
			list[#list + 1] = t
		end
	end
	for _, m in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		if row[m] then
			local ok, t = pcall(row[m], row)
			if ok then
				Add(t)
			end
		end
	end
	for _, t in ipairs(st.sel) do Add(t) end
	for _, t in ipairs(st.dis) do Add(t) end
	local okS, rw, rh = pcall(row.GetSize, row)
	local sized = okS and rw and rh and not Secret(rw) and not Secret(rh) and rw > 0 and rh > 0
	for _, region in ipairs({ row:GetRegions() }) do
		if IsTexture(region) and not region.kitPiece and not seen[region] then
			local okL, layer = pcall(region.GetDrawLayer, region)
			if okL and layer == "HIGHLIGHT" then
				Add(region)
			elseif sized then
				local ok, w, h = pcall(region.GetSize, region)
				if ok and w and h and not Secret(w) and not Secret(h) and w >= rw * 0.5 and h >= rh * 0.5 then
					Add(region)
				end
			end
		end
	end
	return list
end

-- Exactly `want` of the row's game textures faded; the others it faded
-- before come back
local function ApplyFades(st, want)
	for region in pairs(st.faded) do
		if not want[region] then
			Kit:Unfade(region)
			st.faded[region] = nil
		end
	end
	for region in pairs(want) do
		if not st.faded[region] then
			Kit:Fade(region)
			st.faded[region] = true
		end
	end
end

-- Every window's Button Border on the icon, hugging it: its edge 2 px under
-- the rim's inner edge (the professions' recipe icons')
local function FitIconRim(st)
	local rim = st.rim and st.rim.object
	local icon = st.icon
	if not (rim and rim.base and icon) then
		return
	end
	local name = rim.base .. "_normal"
	local p = Kit:Piece(name)
	local l, r, t, b = Kit:Insets(name, 1)
	local ok, iw, ih = pcall(icon.GetSize, icon)
	if not (p and l and ok and iw and ih) or Secret(iw) or Secret(ih) or iw <= 4 then
		return
	end
	rim:ClearAllPoints()
	rim:SetPoint("CENTER", icon, "CENTER")
	rim:SetSize((iw - 4) * p.w / (p.w - l - r), (ih - 4) * p.h / (p.h - t - b))
end

Kit:OnBorderChanged("button", function()
	for _, st in pairs(rows) do
		FitIconRim(st)
	end
end)

local function MakeRim(row, st)
	if st.rim ~= nil or not st.icon then
		return
	end
	st.rim = Replace(st.icon, { as = RIM_KEY, button = row, parent = row, rect = st.icon, noFade = true }) or false
	if st.rim then
		-- Kit's Button Border reaches a rim through its button's `melloRep`:
		-- a stand-in of ours carries it, the game's row is not written on
		st.rimKey = { melloRep = st.rim }
		Kit:RegisterButtonRim(st.rimKey)
		FitIconRim(st)
	end
end

-- The plate's look from the game's marks (selected, hover, unavailable)
local function SyncState(row)
	local st = rows[row]
	if not (st and st.plate and active) or st.kind ~= "service" then
		return
	end
	local selected = IsSelected(st)
	local state = selected and "selected" or ((st.hover or MouseOver(row)) and "hover") or "plain"
	st.plate:SetState(state)
	st.unavailable = (not selected) and IsUnavailable(row, st)
	TintPlate(st.plate, st.unavailable)
end

local function FollowMarks(row, st)
	local function Follow()
		if active then
			SyncState(row)
		end
	end
	for _, list in ipairs({ st.sel, st.dis }) do
		for _, t in ipairs(list) do
			if not hookedOnce[t] then
				hookedOnce[t] = true
				hooksecurefunc(t, "Show", Follow)
				hooksecurefunc(t, "Hide", Follow)
				hooksecurefunc(t, "SetShown", Follow)
			end
		end
	end
	local normal = row.GetNormalTexture and row:GetNormalTexture()
	if IsTexture(normal) then
		hooksecurefunc(normal, "SetVertexColor", Follow)
	end
	if row.LockHighlight then
		hooksecurefunc(row, "LockHighlight", function() st.locked = true; Follow() end)
		hooksecurefunc(row, "UnlockHighlight", function() st.locked = nil; Follow() end)
	end
	HookScriptSafe(row, "OnEnter", function() st.hover = true; Follow() end)
	HookScriptSafe(row, "OnLeave", function() st.hover = nil; Follow() end)
	-- a click selects: the game's own update marks the row, a frame later
	HookScriptSafe(row, "OnClick", function() RefreshSoon("row click") end)
end

local function MakeRow(row)
	local st = { faded = {}, sel = {}, dis = {}, glyphs = {} }
	rows[row] = st
	-- the texture our plates hang on: a region of the row (the plates are
	-- regions of the row too, in its BACKGROUND under its icon and text), no
	-- art of its own
	local anchor = row:CreateTexture(nil, "BACKGROUND", nil, -8)
	anchor.kitPiece = true
	anchor:SetAllPoints(row)
	anchor:SetColorTexture(0, 0, 0, 0)
	st.anchor = anchor
	st.plate = Replace(anchor, { as = PLATE_KEY, rect = row, noFade = true })
	st.cat = Replace(anchor, { as = CATEGORY_KEY, rect = row, noFade = true })
	st.icon = FindIcon(row)
	FindMarks(row, st)
	st.glyphCandidates = GlyphCandidates(row)
	FollowMarks(row, st)
	return st
end

local function ShowRep(rep, shown)
	if not rep then
		return
	end
	local was = rep.object:IsShown()
	rep:SetShown(shown)
	if shown and not was then
		rep:Refit()   -- a pooled row may have been laid out again while its plate was hidden
	end
end

-- What the row is now: a category "header", a "service", or "empty"
local function RowKind(row, data, st)
	local d = DataOf(data)
	local header = IsHeaderData(d) or (row.isHeader == true)
	local glyph, gkind = ReadGlyph(row, st)
	if glyph then
		header = true
	end
	if header and not gkind then
		-- the art could not be told: the data's own collapsed flag
		local collapsed = DataFlag(d, { "isCollapsed", "collapsed" })
		local expanded = DataFlag(d, { "isExpanded", "expanded" })
		if collapsed ~= nil then
			gkind = collapsed and "plus" or "minus"
		elseif expanded ~= nil then
			gkind = expanded and "minus" or "plus"
		end
		if gkind then
			for _, c in ipairs(st.glyphCandidates) do
				if Shown(c.tex) and not c.normal then
					glyph = c
					break
				end
			end
		end
	end
	if header then
		return "header", glyph, gkind
	end
	if st.icon and Shown(st.icon) then
		return "service"
	end
	for _, region in ipairs({ row:GetRegions() }) do
		if region:GetObjectType() == "FontString" and Shown(region) and TextOf(region) then
			return "service"
		end
	end
	return "empty"
end

-- The glyph's plate for this header (made once per glyph texture and kind)
local function SyncGlyph(st, glyph, gkind)
	local shownRep = nil
	if glyph and gkind then
		local reps = st.glyphs[glyph.tex]
		if not reps then
			reps = {}
			st.glyphs[glyph.tex] = reps
		end
		if reps[gkind] == nil then
			reps[gkind] = Replace(glyph.tex, { as = GLYPH_RULE[gkind], button = glyph.owner, rect = glyph.tex, noFade = true }) or false
		end
		shownRep = reps[gkind] or nil
	end
	for _, reps in pairs(st.glyphs) do
		for _, rep in pairs(reps) do
			if rep then
				rep:SetShown(active and rep == shownRep)
			end
		end
	end
	return shownRep ~= nil
end

local function SyncRow(row, data)
	if not (active and row and row.GetRegions and row.CreateTexture) then
		return
	end
	local st = rows[row] or MakeRow(row)
	found.syncs = found.syncs + 1
	if not Shown(row) then
		return
	end
	local kind, glyph, gkind = RowKind(row, data, st)
	st.kind, st.glyphKind, st.glyphSource = kind, gkind, glyph and glyph.source or nil
	if kind == "service" then
		st.icon = st.icon or FindIcon(row)
		if st.icon then
			MakeRim(row, st)
		end
	end
	ShowRep(st.plate, kind == "service")
	ShowRep(st.cat, kind == "header")
	local hasGlyph = SyncGlyph(st, glyph, gkind)
	if st.rim then
		st.rim.object:SetShown(kind == "service" and Shown(st.icon))
		FitIconRim(st)
	end
	-- the game's art under ours: the plates and marks of a row that shows
	-- anything; a header's glyph only where ours stands in for it (a glyph
	-- we cannot tell stays the game's)
	local want = {}
	if kind ~= "empty" then
		for _, region in ipairs(PlateRegions(row, st)) do
			want[region] = true
		end
	end
	if kind == "header" and glyph then
		want[glyph.tex] = hasGlyph or nil
	end
	ApplyFades(st, want)
	SyncState(row)
end

-- Every row the window holds now: the list's (its ScrollBox, or the older
-- frame's buttons) and the rank header above it
local function ForEachRow(fn)
	local f = Window()
	if not f then
		return
	end
	local list, kind = FindList(f)
	if list and kind == "ScrollBox" then
		pcall(list.ForEachFrame, list, function(row, elementData)
			fn(row, elementData)
			-- (nothing returned: a value would stop the iteration)
		end)
	elseif list then
		for _, row in ipairs(type(list.buttons) == "table" and list.buttons or {}) do
			fn(row, nil)
		end
	end
	local step = StepButton(f)
	if type(step) == "table" and step.GetRegions then
		fn(step, nil)
	end
end

RefreshRows = function()
	ForEachRow(SyncRow)
end

-- Switched off: every row's game art back, our tints off (the pieces
-- themselves are hidden with the rest of skin.reps)
local function ReleaseRows()
	for _, st in pairs(rows) do
		ApplyFades(st, {})
		TintPlate(st.plate, false)
		st.hover = nil
	end
end

--------------------------------------------------------------------------------
-- The list's hooks: a ScrollBox tells us each row after its Init; an older
-- scroll frame is followed through its update function, its scroll bar and
-- the window's own update functions (post hooks), and the trainer's events.
--------------------------------------------------------------------------------
local UPDATE_FUNCTIONS = { "ClassTrainerFrame_Update", "ClassTrainer_SetSelection", "ClassTrainerFrame_SetServiceButton" }
local WINDOW_METHODS = { "Update", "Refresh", "RefreshList", "UpdateList", "SetSelection", "SelectService" }

local function HookList(f)
	local list, kind = FindList(f)
	found.list, found.listKind = list, kind
	if not list or hookedOnce[list] then
		return
	end
	hookedOnce[list] = true
	if kind == "ScrollBox" and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
		-- after the row's own Init: what it shows is known only then; under our
		-- own owner key, so no other listener of the list is displaced
		ScrollUtil.AddInitializedFrameCallback(list, function(_, row, elementData)
			SyncRow(row, elementData)
		end, listOwner, false)
		found.hooks[#found.hooks + 1] = "ScrollBox initialized"
	elseif kind == "scroll frame" then
		if type(list.update) == "function" then
			hooksecurefunc(list, "update", function() RefreshSoon("list update") end)
			found.hooks[#found.hooks + 1] = "list.update"
		end
		local bar = list.scrollBar or list.ScrollBar
		if type(bar) == "table" and HookScriptSafe(bar, "OnValueChanged", function() RefreshSoon("scroll") end) then
			found.hooks[#found.hooks + 1] = "scroll bar"
		end
		HookScriptSafe(list, "OnMouseWheel", function() RefreshSoon("wheel") end)
	end
end

local function HookUpdates(f)
	for _, name in ipairs(UPDATE_FUNCTIONS) do
		if type(_G[name]) == "function" then
			if name == "ClassTrainerFrame_SetServiceButton" then
				-- one row laid out: that row, now
				hooksecurefunc(name, function(row)
					if type(row) == "table" and row.GetRegions then
						SyncRow(row, nil)
					end
				end)
			else
				hooksecurefunc(name, function() RefreshSoon(name) end)
			end
			found.hooks[#found.hooks + 1] = name
		end
	end
	for _, method in ipairs(WINDOW_METHODS) do
		if type(f[method]) == "function" then
			hooksecurefunc(f, method, function() RefreshSoon(method) end)
			found.hooks[#found.hooks + 1] = "window:" .. method
		end
	end
end

--------------------------------------------------------------------------------
-- The portrait (WINDOW-RULES 2b / 2c: an empty ring is a bug): the trainer's
-- face drawn by the kit itself, round, at the class medallion's size on the
-- dark disc, on the RING's holder (above the window's own stack, so no page
-- or plate of ours can cover it) -- the same face the game paints with
-- SetPortraitTexture; the game's portrait textures are faded meanwhile.
-- Where no NPC can be read, the art the game's portrait holds; a trainer's
-- book as the last resort.
--------------------------------------------------------------------------------
local function PortraitCandidates(f)
	local list, seen = {}, {}
	local pc = f.PortraitContainer
	for _, t in ipairs({ pc and pc.portrait, f.portrait, f.Portrait, _G.ClassTrainerFramePortrait }) do
		if IsTexture(t) and not seen[t] then
			seen[t] = true
			list[#list + 1] = t
		end
	end
	return list
end

local function PaintPortrait()
	local icon = skin and skin.portraitIcon
	if not icon then
		return
	end
	local okE, exists = pcall(UnitExists, "npc")
	if okE and not Secret(exists) and exists and SetPortraitTexture then
		if pcall(SetPortraitTexture, icon, "npc") then
			skin.portraitSource = "npc"
			return
		end
	end
	for _, t in ipairs(skin.portraits or {}) do
		local ok, file = pcall(t.GetTexture, t)
		if ok and not Secret(file) and file ~= nil and ((type(file) == "number" and file > 0) or (type(file) == "string" and file ~= "")) then
			icon:SetTexture(file)
			skin.portraitSource = "game portrait"
			return
		end
	end
	icon:SetTexture(FALLBACK_ICON)
	skin.portraitSource = "fallback"
end

local function SkinPortrait(f, ring)
	local holder = ring and ring.object
	if not (holder and holder.CreateTexture and ring.tex) then
		return
	end
	local candidates = PortraitCandidates(f)
	-- disc BACKGROUND 6, face ARTWORK, the ring itself OVERLAY: one stack on
	-- the ring's holder, nothing of the game's between them
	local disc = Kit:RingDisc(ring, nil, holder, 6)
	local icon = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	icon.kitPiece = true
	if disc then
		icon:SetAllPoints(disc)
	else
		icon:SetPoint("CENTER", ring.tex, "CENTER")
		icon:SetSize(1, 1)
	end
	local mask = holder:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	icon:AddMaskTexture(mask)
	skin.portraitIcon, skin.portraits = icon, candidates
	PaintPortrait()
	local onEnable, onDisable = ring.onEnable, ring.onDisable
	ring.onEnable = function(r)
		if onEnable then
			onEnable(r)
		end
		if not disc then
			local okW, w = pcall(ring.tex.GetWidth, ring.tex)
			if okW and w and not Secret(w) and w > 0 then
				icon:SetSize(w * 0.759, w * 0.759)
			end
		end
		PaintPortrait()
		for _, t in ipairs(candidates) do
			Kit:Fade(t)
		end
	end
	ring.onDisable = function(r)
		if onDisable then
			onDisable(r)
		end
		for _, t in ipairs(candidates) do
			Kit:Unfade(t)
		end
	end
end

--------------------------------------------------------------------------------
-- The title (WINDOW-RULES 2c): the plate's rule centres the title
-- container's TitleText on the plate in the kit's title face; the trainer's
-- name may be written into another string (an older <window>TitleText or
-- NameText, an unnamed string holding the NPC's name). Every such string is
-- put on the plate in the title face (Kit:TitleFont follows the Fonts
-- options and the Font Style), or faded where the container's string already
-- shows the same words there; points and font put back on disable.
--------------------------------------------------------------------------------
local titleMoved = {}      -- [fs] = { points } while on the plate
local titleFaded = {}      -- [fs] = true while faded as a duplicate

local function TitleStrings(f)
	local tc = f.TitleContainer
	local own = tc and tc.TitleText
	local words = {}
	local npc = NpcName()
	if npc then
		words[npc] = true
	end
	if own and TextOf(own) then
		words[TextOf(own)] = true
	end
	local list, seen = {}, { [own or false] = true }
	local function Add(fs, named)
		if fs and not seen[fs] and fs.GetObjectType and fs:GetObjectType() == "FontString" then
			local text = TextOf(fs)
			if text and (named or words[text]) then
				seen[fs] = true
				list[#list + 1] = fs
			end
		end
	end
	Add(f.TitleText, true)
	for _, name in ipairs({ "ClassTrainerFrameTitleText", "ClassTrainerNameText", "ClassTrainerTitleText" }) do
		Add(_G[name], true)
	end
	for _, holder in ipairs({ f, tc, f.NineSlice }) do
		if holder and holder.GetRegions then
			for _, region in ipairs({ holder:GetRegions() }) do
				Add(region, false)
			end
		end
	end
	return list, own
end

local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
	end
end

local function RestoreTitles()
	for fs, points in pairs(titleMoved) do
		Kit:TitleFont(fs, false)
		fs:ClearAllPoints()
		for _, pt in ipairs(points) do
			fs:SetPoint(unpack(pt))
		end
	end
	wipe(titleMoved)
	for fs in pairs(titleFaded) do
		Kit:Unfade(fs)
	end
	wipe(titleFaded)
end

local function PlaceTitles()
	local f = Window()
	local rep = f and TitleRep()
	if not rep then
		return
	end
	-- the plate's own centring of the container's string, again (the game
	-- writes the trainer's name when the window opens)
	if rep.object and rep.object:IsShown() and rep.Refit then
		rep:Refit()
	end
	local list, own = TitleStrings(f)
	local ownText = own and TextOf(own)
	for _, fs in ipairs(list) do
		if ownText and TextOf(fs) == ownText then
			if not titleFaded[fs] then
				titleFaded[fs] = true
				Kit:Fade(fs)
			end
		else
			if not titleMoved[fs] then
				local points = {}
				for i = 1, fs:GetNumPoints() do
					points[i] = { fs:GetPoint(i) }
				end
				titleMoved[fs] = points
			end
			fs:ClearAllPoints()
			if own then
				fs:SetPoint("CENTER", own, "CENTER")
			else
				fs:SetPoint("CENTER", rep.strip or rep.object, "CENTER")
			end
			Kit:TitleFont(fs, true)
		end
	end
end

--------------------------------------------------------------------------------
-- The other parts: the rank bar, the Filter button, the Train button, the
-- money box, an older scroll bar
--------------------------------------------------------------------------------

-- The first StatusBar under the window outside the list (a profession
-- trainer's rank bar; the game hides it for a class trainer)
local function FindRankBar(f, list)
	local bar = Part(f, { "statusBar", "StatusBar", "skillBar", "rankBar", "RankBar" }, { "StatusBar" }) or _G.ClassTrainerStatusBar
	if type(bar) == "table" and bar.GetObjectType and bar:GetObjectType() == "StatusBar" then
		return bar
	end
	local function Find(root, depth)
		if depth > 3 or root == list then
			return nil
		end
		for _, child in ipairs({ root:GetChildren() }) do
			if child ~= list then
				if child:GetObjectType() == "StatusBar" then
					return child
				end
				local deeper = Find(child, depth + 1)
				if deeper then
					return deeper
				end
			end
		end
		return nil
	end
	return Find(f, 0)
end

-- P1 on the rank bar (the professions' rank bars' look): the bracket in the
-- layer above its fill, the trough under it, the caps OUTSIDE the bar (a
-- StatusBar's fill is its whole rect: the fill keeps its full width); the
-- bar's own border and backing faded. Every window's Progress Bar Border
-- (the rule's `bar` group).
local function SkinRankBar(bar)
	if not bar or bar.melloRep ~= nil then
		return
	end
	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	local art = {}
	local function Collect(frame)
		for _, region in ipairs({ frame:GetRegions() }) do
			if IsTexture(region) and region ~= fill and not region.kitPiece then
				art[#art + 1] = region
			end
		end
	end
	Collect(bar)
	for _, child in ipairs({ bar:GetChildren() }) do
		Collect(child)
	end
	local layer, sublevel, troughLayer, troughSub = Kit:BracketLayers(bar)
	local region = table.remove(art, 1)
	local ours = false
	if not region then
		-- no art of its own to stand in for: an empty region to hang it on
		region = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
		region.kitPiece = true
		region:SetColorTexture(0, 0, 0, 0)
		region:SetAllPoints(bar)
		ours = true
	end
	bar.melloRep = Replace(region, { as = BAR_KEY, parent = bar, rect = bar, capOut = true, noFade = ours or nil,
		layer = layer, sublevel = sublevel, troughLayer = troughLayer, troughSub = troughSub, alsoFade = art }) or false
	found.barArt = #art + (ours and 0 or 1)
end

-- The Filter button, by key or name, else the button reading "Filter"
local function FindFilter(f)
	local filter, key = Part(f, { "FilterButton", "FilterDropdown", "filterButton", "filterDropdown", "FilterDropDown" }, { "FilterButton", "FilterDropDown", "FilterDropdown" })
	if filter then
		return filter, key
	end
	local label = _G.FILTER
	if type(label) ~= "string" then
		return nil
	end
	local function Find(root, depth)
		if depth > 3 then
			return nil
		end
		for _, child in ipairs({ root:GetChildren() }) do
			local fs = child.GetFontString and child:GetFontString()
			if (fs and TextOf(fs) == label) or (type(child.Text) == "table" and child.Text.GetText and TextOf(child.Text) == label) then
				return child
			end
			local deeper = Find(child, depth + 1)
			if deeper then
				return deeper
			end
		end
		return nil
	end
	return Find(f, 0), "text"
end

-- The filter band (the rule "common-dropdown-b-button", the professions'
-- filter) on a modern filter dropdown's Background or a stretch button's
-- nine pieces, its arrow glyph kept; an older dropdown's box gets D1
local function SkinFilter(filter)
	if not (type(filter) == "table" and filter.GetRegions) or filter.melloRep ~= nil then
		return
	end
	if IsTexture(filter.Background) then
		found.filterKind = "filter dropdown"
		filter.melloRep = Replace(filter.Background, { as = "common-dropdown-b-button", rect = filter, button = filter, parent = filter }) or false
		return
	end
	if filter.Middle and filter.Left and filter.Right and filter.Button then
		found.filterKind = "old dropdown"
		local extra = { filter.Left, filter.Right }
		for _, region in ipairs({ filter.Button:GetRegions() }) do
			if IsTexture(region) then
				extra[#extra + 1] = region
			end
		end
		filter.melloRep = Replace(filter.Middle, { as = "UIDropDownMenu", rect = filter, fitHeight = 24, alsoFade = extra }) or false
		return
	end
	local arrow = filter.Icon or filter.Arrow or filter.icon
	local art = {}
	for _, region in ipairs({ filter:GetRegions() }) do
		if IsTexture(region) and region ~= arrow and not region.kitPiece then
			art[#art + 1] = region
		end
	end
	local first = table.remove(art, 1)
	if first then
		found.filterKind = "stretch button"
		filter.melloRep = Replace(first, { as = "common-dropdown-b-button", rect = filter, button = filter, parent = filter, alsoFade = art }) or false
	end
end

-- The Train button on the red plate (B1) with the game's label on it
local function SkinTrain(f)
	local train, key = Part(f, { "trainButton", "TrainButton" }, {})
	if not train then
		train, key = _G.ClassTrainerTrainButton, "ClassTrainerTrainButton"
	end
	found.train, found.trainKey = train, key
	if not (type(train) == "table" and train.GetRegions) then
		return
	end
	local rep = Kit:SkinRedButton(train, Replace)
	if rep then
		-- a magic button's separator lines (between it and the window's edge)
		-- go with the plate
		for _, sep in ipairs({ train.LeftSeparator, train.RightSeparator }) do
			if IsTexture(sep) then
				rep.alsoFade[#rep.alsoFade + 1] = sep
				if active then
					Kit:Fade(sep)
				end
			end
		end
	end
end

-- The frame under the window that paints the coin box's art (a coinbox
-- atlas among its regions), when no key names it
local function FindCoinBox(root, depth)
	if depth > 2 then
		return nil
	end
	for _, child in ipairs({ root:GetChildren() }) do
		for _, region in ipairs({ child:GetRegions() }) do
			local key = IsTexture(region) and Kit:ArtKey(region)
			if type(key) == "string" and key:lower():find("coinbox", 1, true) then
				return child
			end
		end
		local deeper = FindCoinBox(child, depth + 1)
		if deeper then
			return deeper
		end
	end
	return nil
end

-- The money box (a thin gold edge round the coins): the coin plate (B2, the
-- bags' money strip), the coins on it
local function SkinMoney(f)
	local bg, key = Part(f, { "moneyBg", "MoneyBg", "MoneyBackground", "moneyBackground" }, { "MoneyBg" })
	if not bg then
		-- a money frame carrying its own border (the bags' kind), else the
		-- frame that paints a coin box
		local money = Part(f, { "MoneyFrame", "moneyFrame" }, { "MoneyFrame" })
		bg, key = type(money) == "table" and money.Border or nil, "MoneyFrame.Border"
		if not bg then
			bg, key = FindCoinBox(f, 0), "coinbox art"
		end
	end
	found.moneyBg, found.moneyKey = bg, key
	if not (type(bg) == "table" and bg.GetRegions) or bg.melloRep ~= nil then
		return
	end
	local mid = bg.Middle or bg.Center
	local extra = {}
	for _, region in ipairs({ bg:GetRegions() }) do
		if IsTexture(region) and region ~= mid and not region.kitPiece then
			extra[#extra + 1] = region
		end
	end
	if not mid then
		mid = table.remove(extra, 1)
	end
	if mid then
		bg.melloRep = Replace(mid, { as = "common-coinbox-center", rect = bg, alsoFade = extra }) or false
	end
end

-- An older list's scroll bar (a Slider with a thumb texture and up / down
-- buttons): THE scroll bar (T2 / H1 / S1), as a MinimalScrollBar gets it
local ARROWS = {
	["minimal-scrollbar-arrow-top"] = { "ScrollUpButton", "scrollUp", "UpButton" },
	["minimal-scrollbar-arrow-bottom"] = { "ScrollDownButton", "scrollDown", "DownButton" },
}

local function SkinOldScrollBar(sb)
	if not (type(sb) == "table" and sb.GetObjectType) or sb.melloRep ~= nil then
		return
	end
	if sb.Track and sb.Track.Thumb and sb.Back and sb.Forward then
		Kit:SkinScrollBar(sb, Replace)
		found.scrollKind = "minimal"
		return
	end
	if sb:GetObjectType() ~= "Slider" then
		return
	end
	found.scrollKind = "slider"
	local thumb = sb.GetThumbTexture and sb:GetThumbTexture()
	local track = {}
	for _, region in ipairs({ sb:GetRegions() }) do
		if IsTexture(region) and region ~= thumb and not region.kitPiece then
			track[#track + 1] = region
		end
	end
	local reps = {}
	local first = table.remove(track, 1)
	reps[#reps + 1] = Replace(first or sb, { as = "minimal-scrollbar-track-middle", rect = sb, parent = sb, noFade = (first == nil) or nil, alsoFade = track })
	if thumb then
		reps[#reps + 1] = Replace(thumb, { as = "minimal-scrollbar-small-thumb-middle", rect = thumb, button = sb })
	end
	for key, names in pairs(ARROWS) do
		local b = Part(sb, names, { names[1] })
		local normal = type(b) == "table" and b.GetNormalTexture and b:GetNormalTexture()
		if normal then
			reps[#reps + 1] = Replace(normal, { as = key, button = b, alsoFade = Kit:OtherTextures(b, normal) })
		end
	end
	sb.melloRep = reps
end

--------------------------------------------------------------------------------
-- Building the skin
--------------------------------------------------------------------------------

-- The list's stone must lie UNDER the list (the AddOn list's lesson: an
-- inset standing at or above the list hid every row): its holder one level
-- under the lowest of the list and the rank header
local function KeepInsetUnder(f, list, step)
	local rep = f.Inset and f.Inset.melloRep
	local holder = rep and rep.object
	if not (holder and holder.SetFrameLevel and list) then
		return
	end
	local ok, holderLevel, listLevel, windowLevel = pcall(function() return holder:GetFrameLevel(), list:GetFrameLevel(), f:GetFrameLevel() end)
	if not ok or Secret(holderLevel) or Secret(listLevel) or Secret(windowLevel) then
		return
	end
	local lowest = listLevel
	if type(step) == "table" and step.GetFrameLevel then
		local okS, stepLevel = pcall(step.GetFrameLevel, step)
		if okS and not Secret(stepLevel) and stepLevel < lowest then
			lowest = stepLevel
		end
	end
	if holderLevel >= lowest then
		-- (at worst the window's own level, as the AddOn list's: a list or
		-- header a level above the window leaves no room between; the rows
		-- over their stone matter more than the stone over the window's page)
		holder:SetFrameLevel(math.max(lowest - 1, windowLevel))
	end
	found.insetLevels = { holder = holder:GetFrameLevel(), list = listLevel, window = windowLevel }
end

local function Build()
	local f = Window()
	if skin or not f then
		return skin
	end
	skin = { reps = {}, followers = {} }
	local candidates = PortraitCandidates(f)
	-- the shell (the outer rail with its ring corner left to the ring, the
	-- page stone as the one background, the title plate on the rail, close)
	local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = candidates[1] or f.PortraitContainer, bg = f.Bg and "UI-Background-Rock" or nil })
	found.ring = ring ~= nil
	if ring then
		SkinPortrait(f, ring)
	end
	-- the list on the list-box stone under the palette's inner panel (the
	-- inset rule's `dim`, WINDOW-RULES 2e: rows of small text never on the
	-- plain brown), kept under the list and the rank header
	local list = FindList(f)
	if f.Inset then
		Kit:SkinInset(f.Inset, Replace, f, true)
		KeepInsetUnder(f, list, StepButton(f))
	end
	SkinRankBar(FindRankBar(f, list))
	local filter, filterKey = FindFilter(f)
	found.filter, found.filterKey = filter, filterKey
	SkinFilter(filter)
	SkinTrain(f)
	SkinMoney(f)
	if list then
		local name = NameOf(list)
		SkinOldScrollBar(list.scrollBar or list.ScrollBar or (name and _G[name .. "ScrollBar"]))
	end
	-- the rest by what it is (other insets, buttons, check boxes, dropdowns,
	-- a MinimalScrollBar beside a ScrollBox); the list's rows are ours
	-- (SyncRow), not the sweep's
	Kit:SweepControls(f, Replace, skin, list)
	HookList(f)
	HookUpdates(f)
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
	PlaceTitles()
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
	end
	ReleaseRows()
	RestoreTitles()
end

-- The name and the face are written by the game as the window opens: put
-- on the plate and in the ring a frame after
local function AfterOpen()
	C_Timer.After(0, function()
		if active then
			PaintPortrait()
			PlaceTitles()
		end
	end)
end

-- The trainer's own events, on our frame: the window's contents change with
-- them (a new trainer, a service learned, the filter). Registered through a
-- pcall: an event this client does not have is refused, not an error.
local events = CreateFrame("Frame")
Perf.SetScript(events, "OnEvent", function(_, event, arg)
	if event == "UNIT_PORTRAIT_UPDATE" then
		if active and arg == "npc" then
			PaintPortrait()
		end
		return
	end
	RefreshSoon(event)
	if event == "TRAINER_SHOW" then
		AfterOpen()
	end
end)

local function Hook()
	local f = Window()
	if hooked or not f then
		return
	end
	hooked = true
	Perf.HookScript(f, "OnShow", function(window)
		if not active then
			-- the first show dresses the window (see Sync below), in this
			-- same frame: the build takes what the game made for it just now.
			-- A show in combat too: the dressing adds frames of ours and moves
			-- only the window's own title strings, never a protected frame
			-- (it never waited for a fight's end at the trainer's first talk
			-- either).
			if not M.isEnabled then
				return
			end
			Activate()
			if not active then
				return
			end
		else
			-- parts a client makes on first show (the list's rows, a dropdown)
			local list = FindList(window)
			Kit:SweepControls(window, Replace, skin, list)
			HookList(window)
			KeepInsetUnder(window, list, StepButton(window))
		end
		AfterOpen()
		RefreshSoon("show")
	end)
	for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_DESCRIPTION_UPDATE", "TRAINER_SERVICE_INFO_NAME_UPDATE", "UNIT_PORTRAIT_UPDATE" }) do
		if pcall(events.RegisterEvent, events, event) then
			found.events = (found.events or 0) + 1
		end
	end
end

-- (user, 2026-09-24: "dress rarely used windows on first open") nothing of
-- the look is built while the window has never been shown this session: the
-- hooks go on (they wait for the skin), a skin already built is switched on,
-- else only a window open right now (a /reload with it open) is dressed at
-- once; its first show dresses it (the OnShow hook above), in that same
-- frame, so it never draws undressed.
local function Sync()
	local f = Window()
	if M.isEnabled and f then
		Hook()
		if skin or f:IsShown() then
			Activate()
		end
	else
		Deactivate()
	end
end

-- Blizzard_TrainerUI is loaded on demand: hook it when it comes (dressed as
-- it first shows)
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
	end
end

function M:OnDisable()
	watcher:UnregisterAllEvents()
	Deactivate()
end

-- /mello cpu: what the first open and a list refresh cost
MelloUI:Profile("TrainerPanel", "skin build (first open)", Build)
MelloUI:Profile("TrainerPanel", "list refresh", RefreshRows)

--------------------------------------------------------------------------------
-- /trainerdump [rows | art | frames | reps]: the window on this client.
-- No argument: every part the skin looks for, where it was found (key or
-- name) and what it was dressed as; "rows": every row the list holds, what
-- it was read as (header / service, selected, unavailable, glyph, icon) and
-- its regions and children; "art": every visible game texture; "frames" /
-- "reps": the frame tree / our pieces. Opens the copy window.
--------------------------------------------------------------------------------

-- The key a frame keeps a child or region under (its parentKey), in a
-- pcall: a field of a game frame may hold a secret, which cannot be compared
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
	if type(obj) ~= "table" then
		return tostring(obj)
	end
	local name = NameOf(obj)
	if name then
		return name
	end
	local ok, dname = pcall(obj.GetDebugName, obj)
	if ok and dname and not Secret(dname) then
		return dname
	end
	return "[unnamed]"
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
	return (ok and level and not Secret(level)) and tostring(level) or "-"
end

local function Dressed(obj)
	if type(obj) ~= "table" or obj.melloRep == nil then
		return "not dressed"
	end
	return obj.melloRep and "dressed" or "looked at, nothing to dress"
end

local function Found(label, obj, how)
	if type(obj) == "table" and obj.GetObjectType then
		MelloUI:Print("  %-14s %s %s, %s, level %s, shown %s%s", label, obj:GetObjectType(), Describe(obj), SizeText(obj),
			LevelText(obj), tostring(Shown(obj)), how and (" -- " .. how) or "")
	else
		MelloUI:Print("  %-14s not found%s", label, how and (" -- " .. how) or "")
	end
end

local function Counts(t)
	local parts = {}
	for k, c in pairs(t) do
		parts[#parts + 1] = tostring(k) .. " " .. tostring(c)
	end
	return #parts > 0 and table.concat(parts, ", ") or "none"
end

local function DumpSummary(f)
	MelloUI:Print("ClassTrainerFrame: %s, size %s, level %s, strata %s; kit %s, pieces %d", Shown(f) and "shown" or "hidden",
		SizeText(f), LevelText(f), tostring(f:GetFrameStrata()), active and "on" or "off", skin and #skin.reps or 0)
	for _, key in ipairs({ "NineSlice", "Bg", "TopTileStreaks", "TitleContainer", "CloseButton", "PortraitContainer", "Inset" }) do
		Found("." .. key, f[key])
	end
	local candidates = PortraitCandidates(f)
	MelloUI:Print("  portrait: %d game texture(s) (%s); ring %s; face from %s", #candidates,
		#candidates > 0 and Describe(candidates[1]) or "none", tostring(found.ring == true), tostring(skin and skin.portraitSource))
	local list, own = TitleStrings(f)
	MelloUI:Print("  title: container string %s = \"%s\"; other strings %d; npc %s", own and Describe(own) or "none",
		own and (TextOf(own) or "") or "", #list, tostring(NpcName()))
	for _, fs in ipairs(list) do
		MelloUI:Print("     %s \"%s\" %s", Describe(fs), TextOf(fs) or "", titleMoved[fs] and "on the plate" or titleFaded[fs] and "faded (duplicate)" or "untouched")
	end
	local box, kind = FindList(f)
	Found("list", box, kind and (kind .. ((box and type(box.buttons) == "table") and (", " .. #box.buttons .. " buttons") or "")) or nil)
	Found("list's inset", f.Inset, Dressed(f.Inset))
	local lv = found.insetLevels
	if lv then
		MelloUI:Print("  inset stone holder level %s (list %s, window %s)", tostring(lv.holder), tostring(lv.list), tostring(lv.window))
	end
	Found("rank header", StepButton(f))
	local bar = FindRankBar(f, box)
	Found("rank bar", bar, bar and (Dressed(bar) .. ", " .. tostring(found.barArt) .. " art region(s) faded") or nil)
	Found("filter", found.filter, tostring(found.filterKey) .. ", " .. tostring(found.filterKind or "sweep / none") .. ", " .. Dressed(found.filter))
	Found("train", found.train, tostring(found.trainKey) .. ", " .. Dressed(found.train))
	Found("money box", found.moneyBg, tostring(found.moneyKey) .. ", " .. Dressed(found.moneyBg))
	MelloUI:Print("  scroll bar: %s", tostring(found.scrollKind or "the sweep's (or none)"))
	MelloUI:Print("  hooks: %s; events registered %s", #found.hooks > 0 and table.concat(found.hooks, ", ") or "none", tostring(found.events))
	local n, kinds = 0, {}
	for _, st in pairs(rows) do
		n = n + 1
		kinds[st.kind or "?"] = (kinds[st.kind or "?"] or 0) + 1
	end
	MelloUI:Print("  rows seen %d (%s); row syncs %d", n, Counts(kinds), found.syncs)
	MelloUI:Print("  refreshes by: %s", Counts(found.triggers))
end

local function FadedCount(st)
	local c = 0
	for _ in pairs(st.faded) do
		c = c + 1
	end
	return c
end

local function DumpRegion(row, region)
	local kind = region:GetObjectType()
	local okL, layer, sub = pcall(region.GetDrawLayer, region)
	local what = ""
	if kind == "Texture" then
		local okC, r, g, b = pcall(region.GetVertexColor, region)
		what = string.format("art=%s%s colour=%s", tostring(Kit:ArtKey(region)), region.kitPiece and " (kit)" or "",
			(okC and r and not Secret(r)) and string.format("%.2f,%.2f,%.2f", r, g, b) or "?")
	elseif kind == "FontString" then
		what = "text=" .. (TextOf(region) or ""):gsub("|", "||"):sub(1, 60)
	end
	MelloUI:Print("   region %s key=%s %s %s/%s %s shown %s %s", kind, tostring(KeyOf(row, region)), NameOf(region) or "",
		okL and tostring(layer) or "?", okL and tostring(sub) or "?", SizeText(region), tostring(Shown(region)), what)
end

local function DumpRow(row, n)
	local st = rows[row]
	if st then
		MelloUI:Print("row %d %s %s level %s shown %s: kind %s, selected %s, unavailable %s, glyph %s (%s), icon %s, faded %d", n, Describe(row),
			SizeText(row), LevelText(row), tostring(Shown(row)), tostring(st.kind), tostring(IsSelected(st)), tostring(st.unavailable),
			tostring(st.glyphKind), tostring(st.glyphSource), st.icon and Describe(st.icon) or "none", FadedCount(st))
		MelloUI:Print("   marks: selected %d, unavailable %d; glyph candidates %d", #st.sel, #st.dis, #st.glyphCandidates)
	else
		MelloUI:Print("row %d %s %s level %s shown %s: not dressed yet", n, Describe(row), SizeText(row), LevelText(row), tostring(Shown(row)))
	end
	for _, region in ipairs({ row:GetRegions() }) do
		DumpRegion(row, region)
	end
	for _, child in ipairs({ row:GetChildren() }) do
		local normal = child.GetNormalTexture and child:GetNormalTexture()
		MelloUI:Print("   child %s key=%s %s level %s shown %s normal=%s icon=%s", child:GetObjectType(), tostring(KeyOf(row, child)),
			SizeText(child), LevelText(child), tostring(Shown(child)), tostring(normal and Kit:ArtKey(normal)),
			tostring(IsTexture(child.Icon) and Kit:ArtKey(child.Icon)))
	end
end

SLASH_MELLOTRAINERDUMP1 = "/trainerdump"
SlashCmdList.MELLOTRAINERDUMP = function(msg)
	msg = (msg or ""):lower()
	MelloUI:ClearLog()
	local f = Window()
	if not f then
		local lod = "?"
		if C_AddOns and C_AddOns.IsAddOnLoadOnDemand then
			local ok, v = pcall(C_AddOns.IsAddOnLoadOnDemand, "Blizzard_TrainerUI")
			lod = ok and tostring(v) or "?"
		end
		MelloUI:Print("/trainerdump: no ClassTrainerFrame yet (Blizzard_TrainerUI load on demand: %s); talk to a trainer and try again", lod)
	elseif not skin then
		MelloUI:Print("/trainerdump: the trainer's window is not dressed yet (%s)", M.isEnabled
			and "the kit dresses it the first time it opens: talk to a trainer, then try again" or "the Trainer Kit is off")
	elseif msg == "rows" then
		local n = 0
		ForEachRow(function(row)
			n = n + 1
			DumpRow(row, n)
		end)
		if n == 0 then
			MelloUI:Print("No rows: the list makes them when it is first shown.")
		end
	elseif msg == "art" or msg == "frames" or msg == "reps" then
		Kit:DumpWindow(f, skin, msg ~= "art" and msg or nil)
	else
		DumpSummary(f)
	end
	MelloUI:ShowLog("trainerdump " .. msg)
end
