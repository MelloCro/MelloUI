--------------------------------------------------------------------------------
-- MelloUI - Anim
--
-- One tween engine for the whole addon (user, 2026-09-23: "go with 1", the
-- shared animation engine from the study of how polished UI addons move
-- things). Any frame's alpha, scale or offset is eased from where it is to a
-- target over a duration along an easing curve; one hidden driver frame runs
-- every tween in a single OnUpdate and switches itself off when nothing moves,
-- so an idle UI costs nothing.
--
--   MelloUI.Anim:To(frame, prop, to, duration, easing, onDone)
--       prop     "alpha" | "scale" | "x" | "y"  (x / y move the frame's first
--                anchor's offset; the anchor itself is kept)
--       easing   a name from Anim.easing ("outCubic" when left out)
--       onDone   called with the frame once the target is reached (not when
--                the tween is stopped or replaced)
--   MelloUI.Anim:From(frame, prop, from, duration, easing, onDone)
--       jumps to `from`, then eases back to the value it had
--   MelloUI.Anim:Stop(frame, prop)      stops it where it is (all props: nil)
--   MelloUI.Anim:IsRunning(frame, prop)
--   MelloUI.Anim:FadeIn(frame, duration)      shows it and fades 0 -> its alpha
--   MelloUI.Anim:FadeOut(frame, duration)     fades to 0, then hides it
--   MelloUI.Anim:Pop(frame, duration, rise)   fades in while rising `rise`
--                                             (8) units into its place
--
-- A new tween on the same frame and prop replaces the running one, from the
-- value it had reached, so a window opened twice in a row never jumps.
-- Anim.reduceMotion (set by the caller) makes every tween finish at once.
-- Nothing here writes a field onto the frames it moves: the running tweens
-- live in the engine's own table.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local Anim = { reduceMotion = false }
MelloUI.Anim = Anim

--------------------------------------------------------------------------------
-- Easing curves: t from 0 to 1 in, progress out (0 at the start, 1 at the
-- end; "outBack" overshoots a little before it settles).
--------------------------------------------------------------------------------

local sin, cos, pi, sqrt = math.sin, math.cos, math.pi, math.sqrt
local BACK = 1.70158

Anim.easing = {
	linear = function(t) return t end,
	inQuad = function(t) return t * t end,
	outQuad = function(t) return 1 - (1 - t) * (1 - t) end,
	inOutQuad = function(t)
		if t < 0.5 then
			return 2 * t * t
		end
		return 1 - (-2 * t + 2) ^ 2 / 2
	end,
	outCubic = function(t) return 1 - (1 - t) ^ 3 end,
	inOutCubic = function(t)
		if t < 0.5 then
			return 4 * t * t * t
		end
		return 1 - (-2 * t + 2) ^ 3 / 2
	end,
	outQuart = function(t) return 1 - (1 - t) ^ 4 end,
	inSine = function(t) return 1 - cos(t * pi / 2) end,
	outSine = function(t) return sin(t * pi / 2) end,
	inOutSine = function(t) return -(cos(pi * t) - 1) / 2 end,
	outExpo = function(t)
		if t >= 1 then
			return 1
		end
		return 1 - 2 ^ (-10 * t)
	end,
	outCirc = function(t) return sqrt(1 - (t - 1) ^ 2) end,
	outBack = function(t)
		local u = t - 1
		return 1 + (BACK + 1) * u * u * u + BACK * u * u
	end,
}

--------------------------------------------------------------------------------
-- Reading and writing a prop
--------------------------------------------------------------------------------

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

local function Read(frame, prop)
	if prop == "alpha" then
		return frame:GetAlpha()
	elseif prop == "scale" then
		return frame:GetScale()
	end
	local ok, point, rel, relPoint, x, y = pcall(frame.GetPoint, frame, 1)
	if not (ok and point) then
		return nil
	end
	return prop == "x" and x or y, point, rel, relPoint, x, y
end

local function Write(frame, prop, value)
	if prop == "alpha" then
		frame:SetAlpha(value)
	elseif prop == "scale" then
		if value > 0 then
			frame:SetScale(value)
		end
	else
		local _, point, rel, relPoint, x, y = Read(frame, prop)
		if point then
			if prop == "x" then
				x = value
			else
				y = value
			end
			frame:SetPoint(point, rel, relPoint, x, y)
		end
	end
end

--------------------------------------------------------------------------------
-- The driver
--------------------------------------------------------------------------------

local running = {}      -- [frame] = { [prop] = tween }
local count = 0
local driver = CreateFrame("Frame")
driver:Hide()

local function Remove(frame, prop)
	local props = running[frame]
	if props and props[prop] then
		props[prop] = nil
		count = count - 1
		if next(props) == nil then
			running[frame] = nil
		end
	end
	if count <= 0 then
		count = 0
		driver:Hide()
	end
end

local finished = {}
driver:SetScript("OnUpdate", function(_, elapsed)
	for frame, props in pairs(running) do
		for prop, tw in pairs(props) do
			tw.t = tw.t + elapsed
			local p = tw.t / tw.duration
			if p >= 1 or Anim.reduceMotion then
				Write(frame, prop, tw.to)
				finished[#finished + 1] = tw
			else
				local e = tw.ease(p)
				Write(frame, prop, tw.from + (tw.to - tw.from) * e)
			end
		end
	end
	-- the finished ones leave after the walk (removing them during it would
	-- disturb the pairs() above), their callbacks last: one may start a tween
	for i = 1, #finished do
		local tw = finished[i]
		finished[i] = nil
		if running[tw.frame] and running[tw.frame][tw.prop] == tw then
			Remove(tw.frame, tw.prop)
			if tw.onDone then
				local ok, err = pcall(tw.onDone, tw.frame)
				if not ok then
					geterrorhandler()(err)
				end
			end
		end
	end
end)

function Anim:To(frame, prop, to, duration, easing, onDone)
	if not frame or to == nil then
		return
	end
	local from = Read(frame, prop)
	if Secret(from) or from == nil then
		-- a value we cannot read (not anchored, or secret): straight there
		Write(frame, prop, to)
		if onDone then
			onDone(frame)
		end
		return
	end
	duration = tonumber(duration) or 0.2
	if duration <= 0 or self.reduceMotion then
		Remove(frame, prop)
		Write(frame, prop, to)
		if onDone then
			onDone(frame)
		end
		return
	end
	local props = running[frame]
	if not props then
		props = {}
		running[frame] = props
	end
	if not props[prop] then
		count = count + 1
	end
	props[prop] = { frame = frame, prop = prop, from = from, to = to, t = 0, duration = duration,
		ease = self.easing[easing or "outCubic"] or self.easing.outCubic, onDone = onDone }
	driver:Show()
end

function Anim:From(frame, prop, from, duration, easing, onDone)
	local to = Read(frame, prop)
	if Secret(to) or to == nil then
		return
	end
	-- a tween already running there: aim for ITS target, not the midway value
	local props = running[frame]
	if props and props[prop] then
		to = props[prop].to
	end
	Write(frame, prop, from)
	self:To(frame, prop, to, duration, easing, onDone)
end

function Anim:Stop(frame, prop)
	if prop then
		Remove(frame, prop)
		return
	end
	local props = running[frame]
	if props then
		for p in pairs(props) do
			Remove(frame, p)
		end
	end
end

function Anim:IsRunning(frame, prop)
	local props = running[frame]
	if not props then
		return false
	end
	if prop then
		return props[prop] ~= nil
	end
	return next(props) ~= nil
end

--------------------------------------------------------------------------------
-- The common moves
--------------------------------------------------------------------------------

function Anim:FadeIn(frame, duration, easing)
	local props = running[frame]
	local target = props and props.alpha and props.alpha.to or frame:GetAlpha()
	if Secret(target) or not target or target <= 0 then
		target = 1
	end
	if not frame:IsShown() then
		frame:SetAlpha(0)
		frame:Show()
	elseif not (props and props.alpha) then
		frame:SetAlpha(0)
	end
	self:To(frame, "alpha", target, duration or 0.2, easing or "outQuad")
end

function Anim:FadeOut(frame, duration, easing)
	self:To(frame, "alpha", 0, duration or 0.15, easing or "inQuad", function(f)
		f:Hide()
		f:SetAlpha(1)
	end)
end

-- Fades in while rising a few units into place. Not a scale pop: a frame
-- scales about its anchor, so a window anchored by a corner would swing.
function Anim:Pop(frame, duration, rise)
	duration = duration or 0.22
	self:FadeIn(frame, duration * 0.8)
	local y = Read(frame, "y")
	if y and not Secret(y) then
		self:From(frame, "y", y - (rise or 8), duration, "outCubic")
	end
end

MelloUI:Profile("Anim", "tween driver", driver)
