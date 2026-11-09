--------------------------------------------------------------------------------
-- MelloUI - SharedMedia: the media other addons share through LibSharedMedia-3.0, read
--
-- (2.1.32; the user, 2026-11-09: "there are SharedMedia addons, complications of different textures, fonts, sounds
-- etc, can we make MelloUI Compatible with them?" -- picked "Only reading theirs": MelloUI's own media are not
-- registered there.) The one reader for every list MelloUI offers them in: the fonts (Modules/Fonts.lua), the bar
-- textures (Modules/BarTextures.lua), the backgrounds (the tooltips, the chat, the party and raid frames) and the
-- borders (the tooltips).
--   SM.List(kind) -> { { value = path, label = name }, ... }
--       the media of a kind ("font", "statusbar", "background", "border") the library lists now, in its order (by
--       name); empty without the library. Paths only: MelloUI's pickers keep a path (a file ID is passed by)
--   SM.Known(kind, value) -> true | nil
--       a path the library lists now (a pick whose pack was taken out: nil -- the look falls back to its own)
--   SM.Flush()
--       the lists caught up with what was registered since (nothing to do: one test); every reader above calls it
--   SM.Into(list, head, fresh)
--       a picker's list refilled in place (the options hold the table): its first `head` entries kept, then fresh's
--   SM.Merge(list, kind) / SM.Pick(kind, value)
--       a picker's own list with the kind's media at its end (in place, again on the bus) / a pick that is one of them
--   SM.Lay(texture, path, alpha) / SM.Unlay(texture)
--       a background laid on a texture: the file tiled at its own size, in its own colours, at that alpha / taken
--       off again (untiled, white) before the texture's own look is painted
--   bus "sharedmedia" (kinds)
--       fired once a batch of new media is in, kinds = { font = true, ... }: a picker refills its list, a look wearing
--       a pick of that kind lays it again
-- The library is often found late: the SharedMedia packs load after MelloUI (addons load by name) and may bring the
-- library themselves. Until it is found every ADDON_LOADED asks LibStub once; from then on its own
-- LibSharedMedia_Registered callback marks the kind, and one timer fires the bus on the next frame (a pack registers
-- its media one by one: never a rebuild per registration). Nothing is made at login but this file's one event frame.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local SM = {
	KINDS = { "font", "statusbar", "background", "border" },
	lists = {},    -- [kind] = the library's media of that kind (made on first ask)
	known = {},    -- [kind] = { [path] = true }
	dirty = {},    -- [kind] = true: registered since the list was made
	fresh = {},    -- [kind] = true: caught up since the bus last fired
}
MelloUI.SharedMedia = SM

local lib            -- the library, once found
local pending = false   -- one timer on its way
local watcher        -- the ADDON_LOADED frame, until the library is found

-- the library, if an addon has brought it (LibStub asked quietly)
local function Find()
	if lib then
		return lib
	end
	local stub = rawget(_G, "LibStub")
	if type(stub) ~= "table" or type(stub.GetLibrary) ~= "function" then
		return nil
	end
	local ok, found = pcall(stub.GetLibrary, stub, "LibSharedMedia-3.0", true)
	if ok and type(found) == "table" and type(found.List) == "function" and type(found.Fetch) == "function" then
		return found
	end
	return nil
end
SM.Find = Find   -- (read only: the tests)

local function Build(kind)
	local list, known = {}, {}
	if lib then
		local ok, names = pcall(lib.List, lib, kind)
		if ok and type(names) == "table" then
			for _, name in ipairs(names) do
				local got, path = pcall(lib.Fetch, lib, kind, name, true)
				if got and type(path) == "string" and path ~= "" and type(name) == "string" and not known[path] then
					known[path] = true
					list[#list + 1] = { value = path, label = name }
				end
			end
		end
	end
	SM.lists[kind], SM.known[kind] = list, known
	return list
end

function SM.Flush()
	if not next(SM.dirty) then
		return
	end
	for kind in pairs(SM.dirty) do
		SM.dirty[kind] = nil
		SM.fresh[kind] = true
		if SM.lists[kind] then
			Build(kind)
		end
	end
end

function SM.List(kind)
	SM.Flush()
	return SM.lists[kind] or Build(kind)
end

function SM.Known(kind, value)
	if type(value) ~= "string" then
		return nil
	end
	SM.Flush()
	if not SM.known[kind] then
		Build(kind)
	end
	return SM.known[kind][value]
end

function SM.Into(list, head, fresh)
	for i = #list, head + 1, -1 do
		list[i] = nil
	end
	for _, e in ipairs(fresh) do
		list[#list + 1] = e
	end
	return list
end

-- a picker's own list with the kind's media at its end, in place: theirs marked `shared`, taken out and put back each
-- time; the picker's own entries stay where they stand (a choice put in at the front by another file included)
function SM.Merge(list, kind)
	for i = #list, 1, -1 do
		if list[i].shared then
			table.remove(list, i)
		end
	end
	for _, e in ipairs(SM.List(kind)) do
		list[#list + 1] = { value = e.value, label = e.label, shared = true }
	end
	return list
end

-- a pick that is one of the kind's media now, else nil (the look's own, or a pack taken out)
function SM.Pick(kind, value)
	return SM.Known(kind, value) and value or nil
end

local laid = setmetatable({}, { __mode = "k" })   -- [texture] = true: wearing a background laid here

function SM.Lay(texture, path, alpha)
	laid[texture] = true
	texture:SetTexture(path, "REPEAT", "REPEAT")
	texture:SetTexCoord(0, 1, 0, 1)
	texture:SetHorizTile(true)
	texture:SetVertTile(true)
	texture:SetVertexColor(1, 1, 1, alpha or 1)
end

-- a texture that wore one, untiled and its colour white again before its own look is painted on it (a colour fill
-- under the background's alpha would come out fainter) -> true when it wore one
function SM.Unlay(texture)
	if not laid[texture] then
		return false
	end
	laid[texture] = nil
	texture:SetHorizTile(false)
	texture:SetVertTile(false)
	texture:SetVertexColor(1, 1, 1, 1)
	return true
end

-- the bus, once a batch is in: the kinds caught up since it last fired
local function Fire()
	pending = false
	SM.Flush()
	if not next(SM.fresh) then
		return
	end
	local kinds = SM.fresh
	SM.fresh = {}
	MelloUI:Fire("sharedmedia", kinds)
	if MelloUI.RefreshConfig then
		MelloUI:RefreshConfig()
	end
end

local function Mark(kind)
	if type(kind) ~= "string" then
		return
	end
	SM.dirty[kind] = true
	if not pending and C_Timer and C_Timer.After then
		pending = true
		C_Timer.After(0, Fire)
	end
end

local function OnRegistered(_, kind)
	Mark(kind)
end

-- the library found: its callback taken, and every kind marked (a pack that brought it registered before this saw it)
local function Found(found)
	lib = found
	if watcher then
		watcher:UnregisterAllEvents()
		watcher:SetScript("OnEvent", nil)
		watcher = nil
		SM.watcher = nil
	end
	if type(lib.RegisterCallback) == "function" then
		pcall(lib.RegisterCallback, SM, "LibSharedMedia_Registered", OnRegistered)
	end
	for _, kind in ipairs(SM.KINDS) do
		Mark(kind)
	end
end

do
	local found = Find()
	if found then
		Found(found)
	else
		watcher = CreateFrame("Frame")
		watcher:RegisterEvent("ADDON_LOADED")
		watcher:SetScript("OnEvent", function()
			local now = Find()
			if now then
				Found(now)
			end
		end)
		SM.watcher = watcher   -- (read only: the tests)
	end
end
