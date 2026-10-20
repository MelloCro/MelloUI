--------------------------------------------------------------------------------
-- MelloUI Map - the pins (docs/plans/seamless-map.md, stage M1)
--
-- One layer over the canvas, never scaled: a pin keeps its size at every zoom
-- and moves with the view (rescaling a layer of icons on every frame of a zoom
-- is the cost to avoid). Each pin is tied to a world point (the canvas's
-- world units) and kept in a grid cell; when the canvas cuts its cull box
-- again the pins of the cells in it are gathered, and each view lays only
-- those, one anchor each. A pin out of view is hidden and unanchored, its
-- texture back in its layer's pool when the pin goes.
--
-- Pins take no mouse (the setters that would pass a click through are
-- protected, blocked in a fight): the canvas, which watches the cursor while
-- it is over it, asks At(x, y) for the pin under it, for its tooltip and its
-- click.
--
--   Pins.New(canvas) -> pins
--   pins:Layer(name, order, opts)    a layer of pins (its own frame, `order` its
--                                    place in the stack; opts.minZ / maxZ: the
--                                    zooms it shows at)
--   pins:Show(name, on)              a whole layer on or off
--   pins:Set(name, key, wx, wy, spec) a pin at a world point (made or moved);
--                                    spec: icon (a file) or atlas, size (px),
--                                    rgb { r, g, b }, alpha, rotation, sub
--                                    (draw sublevel), tip (text or fn(pin) ->
--                                    lines), fillTip (fn(tooltip, pin): its
--                                    lines, the whole tooltip), click (fn(pin,
--                                    button)), look (fn(tex, pin): the pin's
--                                    picture its own, after the size), lift
--                                    (the set's icon name its glow or shade
--                                    is baked for: MelloUI.Shade:Lift), data;
--                                    (M4) frame: another addon's icon frame,
--                                    borrowed (MapAddonPins.lua: HereBeDragons'
--                                    pins) -- laid in place of a texture, its
--                                    own mouse and tooltip; release(frame)
--                                    hands it back when the pin goes
--   Pins.Lift(tex, name, size)       the icon set's glow (a disc) or shade
--                                    under a pin's picture (the UI Shade's
--                                    "icons"), where the core has it; name
--                                    false: none (a pooled texture showing
--                                    other art)
--   pins:SetAt(name, key, uiMapID, x, y, spec)  the same at a map's position
--   pins:Remove(name, key) / pins:Clear(name)
--   pins:Lay()                       the canvas's view laid (canvas.onView)
--   pins:At(x, y) -> pin             the topmost tip- or click-pin under a canvas point
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Finite = MelloUI.Safe.Finite
local ipairs, pairs, floor = ipairs, pairs, math.floor
local wipe = wipe

local Pins = {}
Pins.__index = Pins
ns.Pins = Pins

local T = {
	CELL = 16,        -- world units a grid cell (the world 1002 x 668: about 63 x 42 cells)
	MARGIN = 24,      -- px past the view a pin is still laid (its icon half out)
	LEVEL = 400,      -- the pin layer over the canvas's maps (their levels run to its root's + twice the maps' count)
	HIT = 3,          -- px round a pin's icon that still points at it
}
Pins.T = T

local function CellOf(wx, wy)
	return floor(wx / T.CELL) * 4096 + floor(wy / T.CELL)
end

function Pins.New(canvas)
	local frame = CreateFrame("Frame", nil, canvas.frame)
	frame:SetAllPoints(canvas.frame)
	frame:SetFrameLevel(canvas.root:GetFrameLevel() + T.LEVEL)
	frame:EnableMouse(false)
	local self = setmetatable({
		canvas = canvas, frame = frame, layers = {}, cells = {}, near = {}, shownList = {}, gen = 0, cut = nil,
		dirty = true,
	}, Pins)
	return self
end

function Pins:Layer(name, order, opts)
	local layer = self.layers[name]
	if layer then
		return layer
	end
	opts = opts or {}
	local f = CreateFrame("Frame", nil, self.frame)
	f:SetAllPoints(self.frame)
	f:SetFrameLevel(self.frame:GetFrameLevel() + (order or 1))
	f:EnableMouse(false)
	layer = { name = name, frame = f, pins = {}, pool = {}, on = true, minZ = opts.minZ or 0, maxZ = opts.maxZ or math.huge,
		order = order or 1 }
	self.layers[name] = layer
	return layer
end

function Pins:Show(name, on)
	local layer = self.layers[name]
	if layer and layer.on ~= (on and true or false) then
		layer.on = on and true or false
		layer.frame:SetShown(layer.on)
		self.dirty = true
	end
end

local function Unhook(self, pin)
	local cell = self.cells[pin.cell]
	if cell then
		cell[pin] = nil
	end
	pin.cell = nil
end

local function Hook(self, pin)
	local key = CellOf(pin.wx, pin.wy)
	if pin.cell == key then
		return
	end
	if pin.cell then
		Unhook(self, pin)
	end
	local cell = self.cells[key]
	if not cell then
		cell = {}
		self.cells[key] = cell
	end
	cell[pin] = true
	pin.cell = key
	self.dirty = true
end

-- the core's icon lift (MelloUI.Shade:Lift), or nil where the core has none
local function LiftAPI()
	local Shade = rawget(MelloUI, "Shade")
	return type(Shade) == "table" and Shade.Lift and Shade or nil
end

local function HideTex(pin)
	local tex = pin.tex
	if tex and pin.spec.frame then
		-- (a borrowed frame: hidden only while it is ours -- its library may have taken it back for the game's map)
		if pin.shown and tex:GetParent() == pin.layer.frame then
			tex:Hide()
			tex:ClearAllPoints()
		end
		pin.shown = false
		return
	end
	if tex and pin.shown then
		tex:Hide()
		tex:ClearAllPoints()
		-- (its lift hidden with it, no stale alpha kept: laid again with the pin's look when it shows again)
		if LiftAPI() then
			Pins.Lift(tex, false)
			pin.dressed = false
		end
	end
	pin.shown = false
end

-- the pin's look on its texture (made from its layer's pool the first time it shows)
function Pins.Lift(tex, name, size)
	local Shade = LiftAPI()
	if Shade then
		pcall(Shade.Lift, Shade, tex, name, size)
	end
end

local function Dress(pin)
	local tex, spec = pin.tex, pin.spec
	if spec.frame then
		-- (another addon's icon on this layer, over its frame; shown as its library shows it on the game's map)
		local lf = pin.layer.frame
		tex:SetParent(lf)
		tex:ClearAllPoints()
		if tex:GetFrameLevel() <= lf:GetFrameLevel() then
			tex:SetFrameLevel(lf:GetFrameLevel() + 1)
		end
		tex:Show()
		pin.dressed = true
		return
	end
	if spec.atlas then
		tex:SetAtlas(spec.atlas)
	elseif spec.icon then
		tex:SetTexture(spec.icon)
		tex:SetTexCoord(0, 1, 0, 1)
	end
	local s = spec.size or 16
	tex:SetSize(s, s)
	local c = spec.rgb
	if c then
		tex:SetVertexColor(c[1], c[2], c[3])
	else
		tex:SetVertexColor(1, 1, 1)
	end
	tex:SetAlpha(spec.alpha or 1)
	tex:SetRotation(pin.rotation or spec.rotation or 0)
	tex:SetDrawLayer("ARTWORK", spec.sub or 0)
	tex:SetDesaturated(false)
	-- (its glow or shade: the spec's; a look of its own may set another after)
	Pins.Lift(tex, spec.lift or false, s)
	if spec.look then
		spec.look(tex, pin)   -- (its own picture: the Quest List's giver icon)
	end
	pin.dressed = true
end

function Pins:Set(name, key, wx, wy, spec)
	wx, wy = Finite(wx), Finite(wy)
	local layer = self.layers[name] or self:Layer(name)
	local pin = layer.pins[key]
	if not (wx and wy) then
		if pin then
			self:Remove(name, key)
		end
		return nil
	end
	if not pin then
		pin = { layer = layer, key = key, shown = false }
		layer.pins[key] = pin
	end
	if pin.spec ~= spec then
		if pin.tex and pin.spec and (pin.spec.frame or spec.frame) then
			-- (a texture for a frame or the other way round: the old one let go first)
			self:Remove(name, key)
			return self:Set(name, key, wx, wy, spec)
		end
		pin.spec = spec
		pin.dressed = false
	end
	pin.wx, pin.wy = wx, wy
	Hook(self, pin)
	return pin
end

-- a pin at a map's position (0..1 on uiMapID), carried to world units by the canvas
function Pins:SetAt(name, key, uiMapID, x, y, spec)
	local wx, wy = self.canvas:ToWorld(uiMapID, x, y)
	return self:Set(name, key, wx, wy, spec)
end

function Pins:Remove(name, key)
	local layer = self.layers[name]
	local pin = layer and layer.pins[key]
	if not pin then
		return
	end
	HideTex(pin)
	if pin.tex then
		local spec = pin.spec
		if spec.frame then
			if spec.release then
				spec.release(pin.tex, layer.frame)   -- (a borrowed frame back where its library keeps it)
			end
		else
			layer.pool[#layer.pool + 1] = pin.tex
		end
		pin.tex = nil
	end
	Unhook(self, pin)
	layer.pins[key] = nil
	self.dirty = true
end

function Pins:Clear(name)
	local layer = self.layers[name]
	if not layer then
		return
	end
	for key in pairs(layer.pins) do
		self:Remove(name, key)
	end
end

-- the pins of the cells in the canvas's cull box (again when it is cut again, or a pin was set or went)
local function Gather(self)
	local c = self.canvas
	local box = c.box
	local near = self.near
	wipe(near)
	self.gen = self.gen + 1
	local gen = self.gen
	local cx0, cy0 = floor(box[1] / T.CELL), floor(box[2] / T.CELL)
	local cx1, cy1 = floor(box[3] / T.CELL), floor(box[4] / T.CELL)
	local cells = self.cells
	for gx = cx0, cx1 do
		for gy = cy0, cy1 do
			local cell = cells[gx * 4096 + gy]
			if cell then
				for pin in pairs(cell) do
					near[#near + 1] = pin
					pin.gen = gen
				end
			end
		end
	end
	-- (shown before, gathered no more: hidden)
	local list = self.shownList
	for i = #list, 1, -1 do
		local pin = list[i]
		if pin.gen ~= gen then
			HideTex(pin)
		end
		list[i] = nil
	end
	self.cut, self.dirty = c.cuts, false
end

function Pins:Lay()
	local c = self.canvas
	if not (c.cx and c.box[1]) then
		return
	end
	if self.dirty or self.cut ~= c.cuts then
		Gather(self)
	end
	local k = c.k1 * c.z
	local x0, y0 = c.cx - c.cw / (2 * k), c.cy - c.ch / (2 * k)
	local w, h, m = c.cw, c.ch, T.MARGIN
	local list = self.shownList
	local n = 0
	for _, pin in ipairs(self.near) do
		local layer = pin.layer
		local x, y = (pin.wx - x0) * k, (pin.wy - y0) * k
		if layer.on and c.z >= layer.minZ and c.z <= layer.maxZ and x > -m and x < w + m and y > -m and y < h + m then
			local tex = pin.tex
			local frame = pin.spec.frame
			if not tex then
				local pool = layer.pool
				tex = frame or pool[#pool]
				if frame then
					pin.shown = false
				elseif tex then
					pool[#pool] = nil
				else
					tex = layer.frame:CreateTexture(nil, "ARTWORK")
				end
				pin.tex = tex
				pin.dressed = false
			elseif frame and tex:GetParent() ~= layer.frame then
				pin.dressed = false   -- (its library took it back for the game's map meanwhile: ours again)
			end
			if not pin.dressed then
				Dress(pin)
			end
			tex:SetPoint("CENTER", layer.frame, "TOPLEFT", x, -y)
			if not pin.shown then
				tex:Show()
				pin.shown = true
			end
			pin.x, pin.y = x, y
			n = n + 1
			list[n] = pin
		elseif pin.shown then
			HideTex(pin)
		end
	end
	for i = n + 1, #list do
		list[i] = nil
	end
	self.count = n
end

-- the pin under a canvas point: the topmost (its layer's order, then the last laid) with a tip or a click
function Pins:At(x, y)
	local best, bestOrder
	for _, pin in ipairs(self.shownList) do
		local spec = pin.spec
		if pin.shown and (spec.tip or spec.fillTip or spec.click) then
			local r = (spec.size or 16) / 2 + T.HIT
			local dx, dy = pin.x - x, pin.y - y
			if dx * dx + dy * dy <= r * r and (not bestOrder or pin.layer.order >= bestOrder) then
				best, bestOrder = pin, pin.layer.order
			end
		end
	end
	return best
end

-- every pin of a layer (the tests and the dump)
function Pins:Each(name, fn)
	local layer = self.layers[name]
	for _, pin in pairs(layer and layer.pins or {}) do
		fn(pin)
	end
end

return Pins
