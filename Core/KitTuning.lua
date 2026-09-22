--------------------------------------------------------------------------------
-- MelloUI - Kit Tuning
--
-- The override layer the editing tools write and the kit reads. Nothing in
-- the addon creates tuning; it only obeys it, so the addon ships and works
-- with an empty tuning table and behaves exactly as before.
--
-- Two sources, layered in this order (later wins):
--   1. Media\KitTuning.lua   MelloUI_KitTuning -- baked defaults, written by
--                            the desktop tool (tools\kitforge) into the repo
--   2. MelloUIDB.kitTuning   live edits made in the game by the companion
--                            editor addon (MelloUIKitEditor); saved by the
--                            client, so they survive the editor being removed
--
-- Schema (version 1). Every section is optional, every field inside is optional:
--
--   globals  = { scale, frameScale, framePrefix }            Kit-wide numbers
--   pieces   = { ["group/name"] = { w, h, uv, box, open,     a painted piece's
--                                   tile, overhang, radius,  geometry, merged
--                                   file } }                 onto KitLayout
--   rules    = { ["<atlas key>"] = { rule = {...},           what the kit draws
--                                    tune = {...} } }        for a game element
--   elements = { ["<frame name>"] = { pos, size, scale,      a whole window or
--                                     alpha, hidden,         a custom element
--                                     regions = {...} } }
--
-- `rule` fields are merged straight onto Kit.Replacements[key] (piece, base,
-- state, kind, scale, heightScale, widthScale, level, outset, ...), so the
-- editor can re-point an element at another painted piece or resize it the
-- way the library already understands.
--
-- `tune` fields are applied to what was built, and are the editor's drag /
-- resize / recolour output:
--   x, y                 move the replacement, in UI units
--   padL, padR, padT, padB  grow (+) or shrink (-) its rectangle, UI units
--   alpha                0..1 on the whole replacement
--   tint = { r, g, b }   multiplied onto every painted texture in it
--   desat                true: greyscale
--   blend                "BLEND", "ADD", "MOD", "ALPHAKEY", "DISABLE"
--   coord = { l, r, t, b }  crop the art (fractions of the piece, 0..1)
--   flipH, flipV         mirror the art
--   layer, sublevel      draw layer of its textures
--   level                frame level offset (same meaning as a rule's `level`)
--   texture              an arbitrary texture path instead of the kit piece
--   hidden               true: do not replace at all, the game's art stays
--
-- A `regions` entry inside an element takes the same `tune` fields and is
-- keyed by the region's name, its key in the frame table, or its atlas /
-- texture name -- whatever the editor could read.
--
-- Editing API (used by the editor addon, safe to call from anywhere):
--   MelloUI.KitTuning:Set(section, key, path, value)   nil value clears
--   MelloUI.KitTuning:Reset(section, key)              nil key clears the section
--   MelloUI.KitTuning:Export()                         Lua source text
--   MelloUI.KitTuning:Import(text)                     replace the live tuning
--   MelloUI.KitTuning:Reload()                         re-merge and re-apply
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local SCHEMA = 1

local KT = { schema = SCHEMA }
MelloUI.KitTuning = KT

--------------------------------------------------------------------------------
-- Merging
--------------------------------------------------------------------------------

local SECTIONS = { "globals", "pieces", "rules", "elements" }

local function Copy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = Copy(v)
	end
	return out
end
KT.Copy = function(_, value) return Copy(value) end

-- `over` onto `base`, in place, deeply. A value of the string "\0nil" removes
-- the key: the tables travel through saved variables, which cannot carry nil.
local NIL = "\0nil"
KT.NIL = NIL

local function Merge(base, over)
	for k, v in pairs(over) do
		if v == NIL then
			base[k] = nil
		elseif type(v) == "table" then
			-- an array (uv, box, open, tint, coord) is replaced whole: half a
			-- rectangle from one source and half from another is never wanted
			if v[1] ~= nil then
				base[k] = Copy(v)
			else
				if type(base[k]) ~= "table" then
					base[k] = {}
				end
				Merge(base[k], v)
			end
		else
			base[k] = v
		end
	end
	return base
end
KT.Merge = function(_, base, over) return Merge(base, over) end

-- The live (editable) tuning table: MelloUIDB.kitTuning, created on demand.
function KT:Live()
	local db = MelloUI.db
	if type(db) ~= "table" then
		return nil
	end
	if type(db.kitTuning) ~= "table" then
		db.kitTuning = { schema = SCHEMA }
	end
	return db.kitTuning
end

-- The baked defaults from Media\KitTuning.lua.
function KT:Baked()
	return type(MelloUI_KitTuning) == "table" and MelloUI_KitTuning or nil
end

-- The effective tuning: baked defaults with the live edits on top. Rebuilt
-- whenever either side changes; `KT.serial` counts the rebuilds so code that
-- caches a lookup can tell when it went stale.
KT.serial = 0
KT.data = { globals = {}, pieces = {}, rules = {}, elements = {} }

function KT:Rebuild()
	local data = { globals = {}, pieces = {}, rules = {}, elements = {} }
	-- built one at a time, not from a list literal: with no baked file the
	-- first entry is nil and ipairs would stop there, losing the live edits
	local sources = {}
	sources[#sources + 1] = self:Baked()
	sources[#sources + 1] = self:Live()
	for _, source in ipairs(sources) do
		for _, section in ipairs(SECTIONS) do
			if type(source[section]) == "table" then
				Merge(data[section], source[section])
			end
		end
	end
	self.data = data
	self.serial = self.serial + 1
	return data
end

function KT:Section(name)
	return self.data[name] or {}
end

function KT:Globals()
	return self.data.globals
end

function KT:Piece(name)
	return name and self.data.pieces[name] or nil
end

-- The rule override for an element key, case-insensitively (this client hands
-- back the canonical case of an atlas, which is not always the case a rule
-- was written in -- the same lookup Kit:RuleFor does).
local lowerRules
function KT:Entry(key)
	if not key then
		return nil
	end
	local entry = self.data.rules[key]
	if entry then
		return entry
	end
	if not lowerRules or lowerRules.serial ~= self.serial then
		lowerRules = { serial = self.serial }
		for k, v in pairs(self.data.rules) do
			lowerRules[k:lower()] = v
		end
	end
	return lowerRules[key:lower()]
end

function KT:Rule(key)
	local entry = self:Entry(key)
	return entry and entry.rule or nil
end

function KT:Tune(key)
	local entry = self:Entry(key)
	return entry and entry.tune or nil
end

function KT:Element(name)
	return name and self.data.elements[name] or nil
end

function KT:HasAny()
	for _, section in ipairs(SECTIONS) do
		if next(self.data[section]) then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Writing (the editor's side)
--------------------------------------------------------------------------------

-- Look up a value by dotted path without creating anything. Used to tell
-- whether the BAKED defaults have something at a path: clearing a live value
-- that stands over a baked one has to leave a marker, not just a hole, or
-- the baked value comes back through the merge.
local function Peek(root, path)
	local node = root
	for part in tostring(path):gmatch("[^%.]+") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return node
end

-- Walk down a dotted path inside a table, creating the tables on the way.
local function Reach(root, path, create)
	local node = root
	for part in tostring(path):gmatch("[^%.]+") do
		local nextNode = node[part]
		if type(nextNode) ~= "table" then
			if not create then
				return nil
			end
			nextNode = {}
			node[part] = nextNode
		end
		node = nextNode
	end
	return node
end

-- Set one value. `section` is "globals", "pieces", "rules" or "elements";
-- `key` the piece / element name (nil for globals); `path` a dotted path
-- inside that entry ("rule.scale", "tune.tint", "pos.x"); `value` nil clears.
function KT:Set(section, key, path, value)
	local live = self:Live()
	if not live then
		return false
	end
	live.schema = SCHEMA
	if type(live[section]) ~= "table" then
		live[section] = {}
	end
	local target = live[section]
	if key ~= nil then
		if type(target[key]) ~= "table" then
			target[key] = {}
		end
		target = target[key]
	end
	local field = path
	if path and path:find("%.") then
		local head, tail = path:match("^(.*)%.([^%.]+)$")
		target = Reach(target, head, value ~= nil)
		field = tail
		if not target then
			return false
		end
	end
	if value == nil then
		-- a cleared field must survive the merge over the baked defaults
		local baked = self:Baked()
		local bakedSection = baked and baked[section] or nil
		local bakedEntry = key ~= nil and (type(bakedSection) == "table" and bakedSection[key] or nil) or bakedSection
		if bakedEntry ~= nil and Peek(bakedEntry, path or field) ~= nil then
			target[field] = NIL
		else
			target[field] = nil
		end
	else
		target[field] = Copy(value)
	end
	self:Changed()
	return true
end

-- Drop a whole entry (or a whole section when `key` is nil).
function KT:Reset(section, key)
	local live = self:Live()
	if not live or type(live[section]) ~= "table" then
		self:Changed()
		return false
	end
	if key == nil then
		live[section] = nil
	else
		live[section][key] = nil
	end
	self:Changed()
	return true
end

function KT:ResetAll()
	local live = self:Live()
	if live then
		for _, section in ipairs(SECTIONS) do
			live[section] = nil
		end
	end
	self:Changed()
end

-- Something changed: re-merge, re-apply, and tell the listeners (the editor
-- refreshes its inspector from here).
KT.listeners = {}

function KT:OnChanged(fn)
	self.listeners[#self.listeners + 1] = fn
end

function KT:Changed()
	self:Rebuild()
	self:Apply()
	for _, fn in ipairs(self.listeners) do
		pcall(fn, self)
	end
	if MelloUI.ScheduleBackup then
		MelloUI:ScheduleBackup("kit tuning")
	end
end

--------------------------------------------------------------------------------
-- Applying
--------------------------------------------------------------------------------

-- Globals and piece geometry are applied to the Kit itself; everything else
-- is read by the Kit while it builds, so a change needs the panels rebuilt
-- (`/mellokit reload` in the editor, or a UI reload).
function KT:Apply()
	-- elements are not the kit's business: a window that was moved has to be
	-- put back whether or not the painted kit is there at all
	local Kit = MelloUI.Kit
	if Kit and Kit.ApplyTuning then
		Kit:ApplyTuning(self)
	end
	self:ApplyElements()
end

--------------------------------------------------------------------------------
-- Elements: whole windows and custom pieces of UI, by frame name
--------------------------------------------------------------------------------

-- Frames the editor should offer even though nothing in the kit maps them:
-- MelloUI's own windows and any element a module wants exposed.
KT.registry = {}
KT.registryOrder = {}

function KT:Register(name, frame, label, group)
	if not name or not frame then
		return
	end
	if not self.registry[name] then
		self.registryOrder[#self.registryOrder + 1] = name
	end
	self.registry[name] = { name = name, frame = frame, label = label or name, group = group or "MelloUI" }
	self:ApplyElement(name)
end

function KT:Registered()
	return self.registryOrder, self.registry
end

-- The frame an element name points at. Three ways, in order:
--   a frame a module registered with KT:Register
--   a global name ("MelloUIConfigFrame", "MinimapCluster")
--   a PATH from a named ancestor, for the many frames and textures the game
--   never named: "MinimapCluster/MinimapContainer" walks the key in the
--   parent's table, "MinimapCluster/#3" takes its third child. Without this
--   most of what you can point at on screen could not be written down, so
--   clicking it gave you nothing to edit.
function KT:Frame(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local entry = self.registry[name]
	if entry and entry.frame then
		return entry.frame
	end
	local direct = _G[name]
	if type(direct) == "table" and direct.GetObjectType then
		return direct
	end
	if not name:find("/", 1, true) then
		return nil
	end
	local node
	for part in name:gmatch("[^/]+") do
		if not node then
			node = _G[part]
			if type(node) ~= "table" or not node.GetObjectType then
				return nil
			end
		elseif part:sub(1, 1) == "#" then
			local index = tonumber(part:sub(2))
			if not (index and node.GetChildren) then
				return nil
			end
			local ok, children = pcall(function() return { node:GetChildren() } end)
			node = ok and children[index] or nil
		else
			local ok, child = pcall(function() return node[part] end)
			node = ok and child or nil
		end
		if type(node) ~= "table" or not node.GetObjectType then
			return nil
		end
	end
	return node
end

local applied = setmetatable({}, { __mode = "k" })

-- Every element this session has actually touched. Clearing one has to put it
-- back, and the frame is usually the game's own, which no module registered:
-- without this list nothing knew there was anything to undo.
KT.appliedNames = {}

function KT:ApplyElement(name, spec)
	spec = spec or self:Element(name)
	local frame = self:Frame(name)
	if not frame then
		return false
	end
	local was = applied[frame]
	if not spec then
		-- the element was tuned earlier in this session and is not any more
		self.appliedNames[name] = nil
		if was then
			if was.pos then
				frame:ClearAllPoints()
				for _, point in ipairs(was.pos) do
					-- 1 to 5 explicitly: GetPoint can hand back a nil relative
					-- frame, and a plain unpack stops at that hole, which put
					-- the anchor back without its offsets
					pcall(frame.SetPoint, frame, unpack(point, 1, 5))
				end
			end
			if was.size then
				pcall(frame.SetSize, frame, was.size[1], was.size[2])
			end
			if was.scale then
				pcall(frame.SetScale, frame, was.scale)
			end
			if was.alpha then
				pcall(frame.SetAlpha, frame, was.alpha)
			end
			if was.shown ~= nil then
				pcall(frame.SetShown, frame, was.shown)
			end
			-- and the textures inside it: an empty list means "put back
			-- anything that was changed and is not listed any more"
			if MelloUI.Kit and MelloUI.Kit.TuneRegions then
				MelloUI.Kit:TuneRegions(frame, {})
			end
			applied[frame] = nil
		end
		return false
	end
	self.appliedNames[name] = true
	-- remember what the frame looked like before the first tuning, so a reset
	-- puts it back without a reload
	if not was then
		was = {}
		local points = {}
		for i = 1, (frame.GetNumPoints and frame:GetNumPoints() or 0) do
			points[i] = { frame:GetPoint(i) }
		end
		if #points > 0 then
			was.pos = points
		end
		local ok, w, h = pcall(frame.GetSize, frame)
		if ok and type(w) == "number" then
			was.size = { w, h }
		end
		was.scale = frame.GetScale and frame:GetScale() or nil
		was.alpha = frame.GetAlpha and frame:GetAlpha() or nil
		applied[frame] = was
	end
	if spec.pos then
		local p = spec.pos
		local relative = (p.relative and self:Frame(p.relative)) or UIParent
		frame:ClearAllPoints()
		pcall(frame.SetPoint, frame, p.point or "CENTER", relative, p.relativePoint or p.point or "CENTER", p.x or 0, p.y or 0)
	end
	if spec.size then
		local w = spec.size.w or spec.size[1]
		local h = spec.size.h or spec.size[2]
		if w and h then
			pcall(frame.SetSize, frame, w, h)
		end
	end
	if spec.scale and frame.SetScale then
		pcall(frame.SetScale, frame, spec.scale)
	end
	if spec.alpha and frame.SetAlpha then
		pcall(frame.SetAlpha, frame, spec.alpha)
	end
	if spec.hidden ~= nil and frame.SetShown then
		was.shown = was.shown == nil and frame:IsShown() or was.shown
		pcall(frame.SetShown, frame, not spec.hidden)
	end
	if spec.regions and MelloUI.Kit and MelloUI.Kit.TuneRegions then
		MelloUI.Kit:TuneRegions(frame, spec.regions)
	end
	return true
end

function KT:ApplyElements()
	for name in pairs(self.data.elements) do
		self:ApplyElement(name)
	end
	-- Anything changed earlier this session and not tuned any more has to be
	-- put back. This used to run over the REGISTERED elements only, so a game
	-- frame -- which nothing registers -- stayed where the editor had dragged
	-- it and "Reset to default" looked like it did nothing.
	for name in pairs(self.appliedNames) do
		if not self.data.elements[name] then
			self:ApplyElement(name, nil)
		end
	end
	for _, name in ipairs(self.registryOrder) do
		if not self.data.elements[name] and not self.appliedNames[name] then
			self:ApplyElement(name, nil)
		end
	end
end

--------------------------------------------------------------------------------
-- Export / import (the bridge to the desktop tool and the repo)
--------------------------------------------------------------------------------

local function Quote(s)
	s = tostring(s)
	if s == NIL then
		-- the "this key was cleared" marker: written as an escape so the
		-- file stays plain text (a raw zero byte in a .lua does not travel)
		return '"' .. [[\0nil]] .. '"'
	end
	s = s:gsub("\\", "\\\\")
	s = s:gsub('"', '\\"')
	s = s:gsub("\n", "\\n")
	return '"' .. s .. '"'
end


local function IsArray(t)
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" then
			return false
		end
		n = n + 1
	end
	return n > 0 and n == #t
end

local function SortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then
			return tostring(a) < tostring(b)
		end
		return type(a) == "number"
	end)
	return keys
end

local function Serialise(value, indent, out)
	local t = type(value)
	if t == "number" then
		-- short, stable numbers: the tool diffs this file
		if value == math.floor(value) then
			out[#out + 1] = tostring(math.floor(value))
		else
			out[#out + 1] = (string.format("%.6g", value))
		end
	elseif t == "boolean" then
		out[#out + 1] = tostring(value)
	elseif t == "string" then
		out[#out + 1] = Quote(value)
	elseif t == "table" then
		if IsArray(value) then
			local parts = {}
			for i = 1, #value do
				local sub = {}
				Serialise(value[i], indent, sub)
				parts[i] = table.concat(sub)
			end
			out[#out + 1] = "{ " .. table.concat(parts, ", ") .. " }"
		elseif not next(value) then
			out[#out + 1] = "{}"
		else
			local pad = string.rep("\t", indent + 1)
			out[#out + 1] = "{\n"
			for _, k in ipairs(SortedKeys(value)) do
				out[#out + 1] = pad
				if type(k) == "string" and k:match("^[%a_][%w_]*$") then
					out[#out + 1] = k .. " = "
				else
					out[#out + 1] = "[" .. (type(k) == "string" and Quote(k) or tostring(k)) .. "] = "
				end
				Serialise(value[k], indent + 1, out)
				out[#out + 1] = ",\n"
			end
			out[#out + 1] = string.rep("\t", indent) .. "}"
		end
	else
		out[#out + 1] = "nil"
	end
end

-- The live tuning as the text of Media\KitTuning.lua: paste it into the repo
-- (or let the desktop tool write it) and the edits ship as defaults.
function KT:Export(what)
	local source = what == "effective" and self.data or (self:Live() or {})
	local out = {
		"-- MelloUI kit tuning -- written by the kit editor (MelloUIKitEditor / tools\\kitforge).\n",
		"-- Overrides for Media\\KitLayout.lua and Modules\\Kit.lua; see Core\\KitTuning.lua for the schema.\n\n",
		"MelloUI_KitTuning = ",
	}
	local body = {}
	Serialise({
		schema = SCHEMA,
		globals = source.globals,
		pieces = source.pieces,
		rules = source.rules,
		elements = source.elements,
	}, 0, body)
	out[#out + 1] = table.concat(body)
	out[#out + 1] = "\n"
	return table.concat(out)
end

-- Read a table back in, either the text of an exported file or a bare table
-- literal. Returns true, or false plus the error.
function KT:Import(text, mode)
	if type(text) ~= "string" then
		return false, "no text"
	end
	local body = text:gsub("^%s*MelloUI_KitTuning%s*=%s*", "")
	local chunk = loadstring("return " .. body, "KitTuning")
	if not chunk then
		-- a whole file with comments: run it in a sandbox and take the global
		local sandbox = {}
		local err
		chunk, err = loadstring(text, "KitTuning")
		if not chunk then
			return false, err
		end
		setfenv(chunk, sandbox)
		local ok, runErr = pcall(chunk)
		if not ok then
			return false, runErr
		end
		if type(sandbox.MelloUI_KitTuning) ~= "table" then
			return false, "no MelloUI_KitTuning table in the text"
		end
		return self:Adopt(sandbox.MelloUI_KitTuning, mode)
	end
	local ok, value = pcall(chunk)
	if not ok or type(value) ~= "table" then
		return false, ok and "not a table" or value
	end
	return self:Adopt(value, mode)
end

-- mode "merge" keeps what is already there; anything else replaces it.
function KT:Adopt(tbl, mode)
	local live = self:Live()
	if not live then
		return false, "saved variables are not ready"
	end
	if mode ~= "merge" then
		for _, section in ipairs(SECTIONS) do
			live[section] = nil
		end
	end
	live.schema = SCHEMA
	for _, section in ipairs(SECTIONS) do
		if type(tbl[section]) == "table" then
			live[section] = live[section] or {}
			Merge(live[section], Copy(tbl[section]))
		end
	end
	self:Changed()
	return true
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function KT:Reload()
	self:Rebuild()
	self:Apply()
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:RegisterEvent("VARIABLES_LOADED")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 ~= "MelloUI" then
		return
	end
	-- the db may be adopted late on this client: re-merge at every stage
	KT:Reload()
end)

-- Applied once as the file loads too, so the kit sees piece overrides from
-- the baked defaults before the first panel draws anything.
KT:Rebuild()
