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
--   MelloUI.Anim:PlayGroup(group, settle)
--       plays an AnimationGroup (one already playing goes on: Stop it first
--       to restart it) and returns true. Under Reduce Motion it is not
--       played but stopped in its end state at once, nothing left running,
--       and false returned: its regions at their own alpha, size and place
--       (as when it finishes), for a group SetToFinalAlpha each Alpha
--       animation's target at its last ToAlpha, then settle(group) when
--       given, for what else its OnFinished does (pass a shared function, not
--       a new closure per call). A looping group has no end: it stops on that
--       still picture and plays again when Reduce Motion is switched off.
--   MelloUI.Anim:StopGroup(group)   stops it; a looping one stays stopped
--   MelloUI.Anim:SetReduceMotion(on)
--
-- A new tween on the same frame and prop replaces the running one, from the
-- value it had reached, so a window opened twice in a row never jumps.
-- Anim.reduceMotion (read it, set it through SetReduceMotion) makes every
-- tween finish at once and every group end at once. UI Modifications' Reduce
-- Motion switch sets it, whether that module is on or off.
-- Nothing here writes a field onto the frames it moves: the running tweens
-- live in the engine's own table.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
-- Core.lua loads before Perf.lua: its /melloperf scope (the mover's shared
-- handlers) is opened here, while the files still load, as a load of its
-- own that Anim's scope closes at once. Asked for by Core after login it
-- would open a file load that never closes (review, 2026-09-25).
MelloUI.CorePerf = MelloUI.Perf:Scope("Core")
local Perf = MelloUI.Perf:Scope("Anim")

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

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

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
Perf.SetScript(driver, "OnUpdate", function(_, elapsed)
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

--------------------------------------------------------------------------------
-- Animation groups (audit, 2026-09-24: MelloUI's own AnimationGroups played
-- on under Reduce Motion, or checked it by hand)
--------------------------------------------------------------------------------

-- [group] = settle or true, for each group played through PlayGroup: when
-- Reduce Motion comes on, the ones still playing end at once; when it goes
-- off, the looping ones play again. Weak keys: being here keeps none alive.
local groups = setmetatable({}, { __mode = "k" })

local function Target(anim, group)
	return anim.GetTarget and anim:GetTarget() or group:GetParent()
end

-- a target's last Alpha animation (the highest order; of equal orders, the
-- later one) leaves it at its ToAlpha
local function FinalAlpha(group, ...)
	local n = select("#", ...)
	for i = 1, n do
		local a = select(i, ...)
		if a:GetObjectType() == "Alpha" then
			local target, last = Target(a, group), true
			for j = 1, n do
				local b = select(j, ...)
				if j ~= i and b:GetObjectType() == "Alpha" and Target(b, group) == target
					and (b:GetOrder() > a:GetOrder() or (b:GetOrder() == a:GetOrder() and j > i)) then
					last = false
					break
				end
			end
			if last and target and target.SetAlpha then
				target:SetAlpha(a:GetToAlpha())
			end
		end
	end
end

local function Settle(group, settle)
	group:Stop()
	if group.IsSetToFinalAlpha and group:IsSetToFinalAlpha() then
		FinalAlpha(group, group:GetAnimations())
	end
	if type(settle) == "function" then
		settle(group)
	end
end

function Anim:PlayGroup(group, settle)
	if not group then
		return false
	end
	groups[group] = settle or true
	if self.reduceMotion then
		Settle(group, settle)
		return false
	end
	group:Play()
	return true
end

function Anim:StopGroup(group)
	if group then
		groups[group] = nil
		group:Stop()
	end
end

-- The Reduce Motion switch. The running tweens end on the driver's next
-- frame; the groups here at once. The groups are listed first and acted on
-- after (review, 2026-09-24): a settle, or a group's own OnPlay / OnFinished,
-- may play another group through PlayGroup, and a key added to `groups`
-- during its pairs() walk is undefined in Lua. The list is reused, filled
-- above what a switch still running (from inside a settle) holds.
local sweep, sweepTop = {}, 0

local function Switch(group, settle, on)
	if on then
		if group:IsPlaying() then
			Settle(group, settle)
		end
	elseif group:GetLooping() ~= "NONE" and not group:IsPlaying() then
		group:Play()
	end
end

function Anim:SetReduceMotion(on)
	on = on and true or false
	if on == self.reduceMotion then
		return
	end
	self.reduceMotion = on
	local base = sweepTop
	local top = base
	for group in pairs(groups) do
		top = top + 1
		sweep[top] = group
	end
	sweepTop = top
	for i = base + 1, top do
		local group = sweep[i]
		sweep[i] = nil
		-- still listed (a settle before it may have stopped it), with its
		-- settle as it is now
		local settle = groups[group]
		if settle ~= nil and self.reduceMotion == on then
			local ok, err = pcall(Switch, group, settle, on)
			if not ok then
				geterrorhandler()(err)
			end
		end
	end
	sweepTop = base
end

MelloUI:Profile("Anim", "tween driver", driver)
