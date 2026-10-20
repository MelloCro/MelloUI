--------------------------------------------------------------------------------
-- MelloUI Map - the layers (docs/plans/seamless-map.md, stage M1)
--
-- What the map shows over its art, each a layer of pins (MapPins.lua) fed
-- from the client and from MelloUI's own data, across the whole world at once
-- -- never only the zone under the view:
--
--   the player     the game's own map arrow, turned by the facing
--   the group      your party or raid on the player's continent, a dot in each
--                  one's class colour, the name on hover
--
-- Read while the window shows (its OnUpdate, a tenth of a second at most);
-- nothing runs while it is closed. Positions and the facing are read through
-- MelloUI.Safe: a secret or missing one leaves the pin where it was, or takes
-- it away (an instance's own map: no place on the world).
--
--   Layers.Init(canvas, pins)   the layers made (the window's first open)
--   Layers.Tick(elapsed)        the window's OnUpdate
--   Layers.FindMe()             a glide to the player
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Finite = MelloUI.Safe.Finite
local Text = MelloUI.Safe.Text
local pairs, pcall, type = pairs, pcall, type

local Layers = {}
ns.Layers = Layers

local T = {
	EVERY = 0.1,             -- the positions read at most this often
	ARROW_SIZE = 26,
	DOT_SIZE = 12,
	FIND_ZOOM = 6,           -- Find me: at least this close
	ICONS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\",
	ARROW_ATLAS = "UI-WorldMapArrow",                 -- the game's own map arrow
	ARROW_FILE = "Interface\\Minimap\\MinimapArrow",  -- (if the atlas is missing)
	-- the stack (MapPins' layer order): the group under the player
	ORDER = { group = 40, player = 50 },
}
Layers.T = T

local S = { canvas = nil, pins = nil, wait = 0, seen = {} }

--------------------------------------------------------------------------------
-- Reading a unit's place
--------------------------------------------------------------------------------

local function XY(pos)
	if type(pos) ~= "table" then
		return nil
	end
	local ok, x, y = pcall(pos.GetXY, pos)
	if not ok then
		return nil
	end
	return Finite(x), Finite(y)
end

-- the player's map (the best the client has for them), or nil
local function PlayerMap()
	local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
	return ok and Finite(id) or nil
end

local function UnitXY(mapID, unit)
	local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, unit)
	if not ok then
		return nil
	end
	return XY(pos)
end

--------------------------------------------------------------------------------
-- The player
--------------------------------------------------------------------------------

local PLAYER = { size = T.ARROW_SIZE, sub = 2, tip = nil }

local function ArrowLook()
	local info = C_Texture and C_Texture.GetAtlasInfo and select(2, pcall(C_Texture.GetAtlasInfo, T.ARROW_ATLAS))
	if type(info) == "table" then
		PLAYER.atlas = T.ARROW_ATLAS
	else
		PLAYER.icon = T.ARROW_FILE
	end
end

local function Player(mapID)
	local pins = S.pins
	local x, y = UnitXY(mapID, "player")
	local pin = x and pins:SetAt("player", "player", mapID, x, y, PLAYER)
	if not pin then
		pins:Remove("player", "player")
		return
	end
	local facing = Finite(GetPlayerFacing and GetPlayerFacing())
	if facing and pin.rotation ~= facing then
		pin.rotation = facing
		if pin.tex then
			pin.tex:SetRotation(facing)
		end
	end
end

--------------------------------------------------------------------------------
-- The group
--------------------------------------------------------------------------------

local classSpec = {}   -- [class] = a dot in that class's colour (one table a class, shared by every member)

local function MemberTip(pin)
	local name = Text(UnitName(pin.data))
	return name
end

local function DotOf(class)
	local spec = classSpec[class or "?"]
	if not spec then
		local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		spec = { icon = T.ICONS .. "map_dot", size = T.DOT_SIZE, rgb = c and { c.r, c.g, c.b } or nil, sub = 1,
			tip = MemberTip }
		classSpec[class or "?"] = spec
	end
	return spec
end

local function Group(mapID)
	local pins, seen = S.pins, S.seen
	for key in pairs(seen) do
		seen[key] = false
	end
	local raid = IsInRaid and IsInRaid()
	local n = raid and 40 or 4
	local prefix = raid and "raid" or "party"
	for i = 1, n do
		local unit = prefix .. i
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			local x, y = UnitXY(mapID, unit)
			if x then
				local _, class = UnitClass(unit)
				local pin = pins:SetAt("group", unit, mapID, x, y, DotOf(Text(class)))
				if pin then
					pin.data = unit
					seen[unit] = true
				end
			end
		end
	end
	for key, on in pairs(seen) do
		if not on then
			pins:Remove("group", key)
			seen[key] = nil
		end
	end
end

--------------------------------------------------------------------------------
-- The window's beat
--------------------------------------------------------------------------------

function Layers.Tick(elapsed)
	if not S.pins then
		return
	end
	S.wait = S.wait - (elapsed or 0)
	if S.wait > 0 then
		return
	end
	S.wait = T.EVERY
	local mapID = PlayerMap()
	if mapID then
		Player(mapID)
		Group(mapID)
	else
		S.pins:Clear("player")
		S.pins:Clear("group")
	end
	S.pins:Lay()
end

-- a glide to the player: at least FIND_ZOOM close, the zoom kept when closer
function Layers.FindMe()
	local c, pins = S.canvas, S.pins
	local pin = pins and pins.layers.player and pins.layers.player.pins.player
	if not (c and pin) then
		return false
	end
	local z = c.z < T.FIND_ZOOM and T.FIND_ZOOM or c.z
	c:Glide(pin.wx, pin.wy, z)
	return true
end

function Layers.Init(canvas, pins)
	S.canvas, S.pins = canvas, pins
	ArrowLook()
	pins:Layer("group", T.ORDER.group)
	pins:Layer("player", T.ORDER.player)
	S.wait = 0
end

return Layers
