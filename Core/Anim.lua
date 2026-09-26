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
--   MelloUI.Anim:Land(frame, prop)      a running move jumps to its end (all
--                                       props: nil); its onDone does NOT run
--   MelloUI.Anim:Target(frame, prop)    where a running move is going, or nil
--   MelloUI.Anim:IsRunning(frame, prop)
--   MelloUI.Anim:FadeIn(frame, duration, easing, onDone)
--                                             shows it and fades 0 -> its alpha
--   MelloUI.Anim:FadeOut(frame, duration)     fades to 0, then hides it
--   MelloUI.Anim:Pop(frame, duration, rise)   fades in while rising `rise`
--                                             (8) units into its place
--   MelloUI.Anim:CrossFade(old, new, opts)    one frame for another (pages,
--                                             tabs, steps; below)
--   MelloUI.Anim:Glide(target, opts) -> g     the one smooth scroll (below)
--   MelloUI.Anim:Pulse(region, from, to, period) -> group   a looping glow
--   MelloUI.Anim:Busy() -> tweens, glides     what runs (tests, /melloperf)
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
-- live in the engine's own table. Nothing is made per move once warm: the
-- tween tables are reused (configurator build, 2026-09-25).
-- Never tween the scale of anything with a background (the backgrounds keep
-- one resolution), and never touch frames the kit fades (Kit:Fade).
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

local sin, cos, pi, sqrt, exp, abs = math.sin, math.cos, math.pi, math.sqrt, math.exp, math.abs
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

-- the glides (below) share this driver: it sleeps only when neither a tween
-- nor a glide runs
local nGliding = 0

-- Spare tables (a hover wash, a page switch, a marker's move made a tween
-- table and a prop table per move): taken back when a tween ends, is
-- replaced or stopped. One released while the driver walks its tweens (an
-- onDone that stops or replaces another) waits in `limbo` until the walk is
-- over, so a finished tween the walk still holds is never handed out again
-- under it (configurator build, 2026-09-25).
local spare, nSpare = {}, 0
local limbo, nLimbo = {}, 0
local spareProps, nSpareProps = {}, 0
local walking = false

local function Release(tw)
	tw.frame, tw.onDone, tw.ease = nil, nil, nil
	if walking then
		nLimbo = nLimbo + 1
		limbo[nLimbo] = tw
	else
		nSpare = nSpare + 1
		spare[nSpare] = tw
	end
end

local function NewTween()
	if nSpare > 0 then
		local tw = spare[nSpare]
		spare[nSpare] = nil
		nSpare = nSpare - 1
		return tw
	end
	return {}
end

local function Sleep()
	if count <= 0 and nGliding <= 0 then
		count = 0
		driver:Hide()
	end
end

local function Remove(frame, prop)
	local props = running[frame]
	local tw = props and props[prop]
	if tw then
		props[prop] = nil
		count = count - 1
		Release(tw)
		if next(props) == nil then
			running[frame] = nil
			nSpareProps = nSpareProps + 1
			spareProps[nSpareProps] = props
		end
	end
	Sleep()
end

local StepGlides   -- (the glides, below)

local finished = {}
Perf.SetScript(driver, "OnUpdate", function(_, elapsed)
	walking = true
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
		-- (released under an earlier onDone this frame: its frame is gone)
		local frame, prop, onDone = tw.frame, tw.prop, tw.onDone
		if frame and running[frame] and running[frame][prop] == tw then
			Remove(frame, prop)
			if onDone then
				local ok, err = pcall(onDone, frame)
				if not ok then
					geterrorhandler()(err)
				end
			end
		end
	end
	walking = false
	for i = 1, nLimbo do
		nSpare = nSpare + 1
		spare[nSpare] = limbo[i]
		limbo[i] = nil
	end
	nLimbo = 0
	if nGliding > 0 then
		StepGlides(elapsed)
	end
	Sleep()
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
		if nSpareProps > 0 then
			props = spareProps[nSpareProps]
			spareProps[nSpareProps] = nil
			nSpareProps = nSpareProps - 1
		else
			props = {}
		end
		running[frame] = props
	end
	local old = props[prop]
	if old then
		Release(old)          -- replaced: its onDone never runs
	else
		count = count + 1
	end
	local tw = NewTween()
	tw.frame, tw.prop, tw.from, tw.to, tw.t, tw.duration = frame, prop, from, to, 0, duration
	tw.ease = self.easing[easing or "outCubic"] or self.easing.outCubic
	tw.onDone = onDone
	props[prop] = tw
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

-- A running move (all props: nil) jumps to where it was going; its onDone
-- does NOT run (a page landed at once must not be hidden by the fade out it
-- was in).
function Anim:Land(frame, prop)
	local props = running[frame]
	if not props then
		return
	end
	if prop then
		local tw = props[prop]
		if tw then
			Write(frame, prop, tw.to)
			Remove(frame, prop)
		end
		return
	end
	for p, tw in pairs(props) do
		Write(frame, p, tw.to)
		Remove(frame, p)
	end
end

-- where a running move is going (nil when none runs)
function Anim:Target(frame, prop)
	local props = running[frame]
	local tw = props and props[prop]
	return tw and tw.to or nil
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

function Anim:FadeIn(frame, duration, easing, onDone)
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
	self:To(frame, "alpha", target, duration or 0.2, easing or "outQuad", onDone)
end

-- one function for every FadeOut's end (it made a closure per call)
local function HideAndReset(f)
	f:Hide()
	f:SetAlpha(1)
end

function Anim:FadeOut(frame, duration, easing)
	self:To(frame, "alpha", 0, duration or 0.15, easing or "inQuad", HideAndReset)
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
-- Switching one frame for another (audit rank 10: the configurator's pages
-- and tabs, the installer's steps). The old one fades out and hides (its
-- alpha back to 1); the new one fades in from where its alpha is (a page
-- still fading out turns back without a jump) and, with `slide`, eases from
-- `slide` units off its anchor back onto it (a frame held by ONE anchor
-- point: its first).
--   MelloUI.Anim:CrossFade(old, new, opts)
--     old      the frame going (nil, or the same as new: nothing goes)
--     opts     slide (0: none; the sign is the side it comes from), axis
--              ("x"), outTime (0.10), inTime (0.15), outEasing ("outQuad"),
--              inEasing ("outCubic"), instant (false), outInstant (false:
--              the old one hides at once, only the new one fades and
--              slides -- for a page area that cannot clip the one leaving),
--              onDone (fn(new), once, when new is fully in; a shared
--              function, not a closure per call). Keep one opts table per
--              caller and change its fields: no table per switch.
-- With Reduce Motion or opts.instant everything lands at once (a slide under
-- way included) and onDone runs before CrossFade returns.
--------------------------------------------------------------------------------

local NO_OPTS = {}

function Anim:CrossFade(old, new, opts)
	opts = opts or NO_OPTS
	local axis = opts.axis or "x"
	local instant = opts.instant or self.reduceMotion
	if old and old ~= new then
		if instant or opts.outInstant then
			self:Land(old, axis)
			self:Stop(old, "alpha")
			old:Hide()
			old:SetAlpha(1)
		else
			self:FadeOut(old, opts.outTime or 0.10, opts.outEasing or "outQuad")
		end
	end
	if not new then
		return
	end
	if instant or old == new then
		self:Land(new, axis)
		self:Stop(new, "alpha")
		new:SetAlpha(1)
		new:Show()
		if opts.onDone then
			opts.onDone(new)
		end
		return
	end
	local inTime = opts.inTime or 0.15
	local easing = opts.inEasing or "outCubic"
	local slide = opts.slide or 0
	if slide ~= 0 then
		-- from its anchor (a slide still running: the place it was going to)
		local base = self:Target(new, axis)
		if base == nil then
			base = Read(new, axis)
		end
		if not Secret(base) and type(base) == "number" then
			Write(new, axis, base + slide)
			self:To(new, axis, base, inTime, easing)
		end
	end
	self:FadeIn(new, inTime, easing, opts.onDone)
end

--------------------------------------------------------------------------------
-- Smooth scrolling (audit rank 9): one glide for every own list, lifted from
-- the configurator's (user, 2026-09-23: the wheel moves a target and the list
-- glides to it, quick at first and easing in; each notch adds to the target,
-- so a fast spin runs on smoothly). Run by the driver above: no frame of its
-- own, and nothing runs while nothing moves.
--   local g = MelloUI.Anim:Glide(target, opts)   -- one per target, kept
--     target   one of OUR ScrollFrames: its SetVerticalScroll is followed (a
--              set that is not the glide's own -- the bar dragged, a page
--              opened -- stops it where it lands) and its OnMouseWheel taken
--              (opts.wheel = false leaves the wheel to its owner);
--              or any frame with opts.get / opts.set / opts.range: an offset
--              surface (the Quest Tracker's list), no hooks; its owner sends
--              the wheel to g:Wheel(delta) and calls g:Sync(offset) when it
--              moves by itself
--     opts     step (80 per notch), rate (Anim.GLIDE_RATE), wheel, get, set,
--              range (functions of the target, made once by the owner, not
--              closures per call)
--   g:To(offset)    glides there (kept within the range); at once under
--                   Reduce Motion, while the target is hidden, or for < 0.5
--   g:Jump(offset)  there at once, the glide stopped
--   g:Wheel(delta)  a notch: each adds to the running target
--   g:Stop()        where it is;   g:Sync(offset)  it moved by itself
--   g:IsGliding()   g.pos, g.target, g.step
-- The step closes the same share of the gap at any frame rate:
-- pos += (target - pos) * (1 - exp(-rate * dt)); it snaps within 0.5. The
-- set runs in a pcall: an error goes to the error handler and halts that
-- glide only. Nothing is made per step or per notch.
--------------------------------------------------------------------------------

Anim.GLIDE_RATE = 16   -- 1/s: the configurator's feel at 60 fps (it closed 14/60 of the gap a frame)

function Anim.GlideFactor(rate, dt)
	return 1 - exp(-(rate or Anim.GLIDE_RATE) * dt)
end

local glideOf = setmetatable({}, { __mode = "k" })   -- [target] = g
local gliding = {}                                    -- [g] = true while it moves
local stepList = {}                                   -- the walk's list, reused

local Glide = {}
Glide.__index = Glide

local function Halt(g)
	if gliding[g] then
		gliding[g] = nil
		nGliding = nGliding - 1
	end
end

local function ScrollGet(f)
	return f:GetVerticalScroll()
end
local function ScrollSet(f, v)
	f:SetVerticalScroll(v)
end
local function ScrollRange(f)
	return f:GetVerticalScrollRange()
end

local function Range(g)
	local r = g.range(g.frame)
	if Secret(r) or type(r) ~= "number" then
		return nil
	end
	return r > 0 and r or 0
end

-- where it really is, read before a glide starts (a set the hook could not
-- see, an offset its owner clamped)
local function Live(g)
	local pos = g.get(g.frame)
	if not Secret(pos) and type(pos) == "number" then
		g.pos = pos
	end
end

local function Put(g, v)
	g.pos = v
	g.busy = true
	g.set(g.frame, v)
	g.busy = false
end

function Glide:Jump(offset)
	Halt(self)
	local r = Range(self) or 0
	offset = offset < 0 and 0 or (offset > r and r or offset)
	self.target = offset
	local ok, err = pcall(Put, self, offset)
	self.busy = false
	if not ok then
		geterrorhandler()(err)
	end
	Sleep()
end

function Glide:To(offset)
	local r = Range(self)
	if not r then
		return self:Stop()
	end
	offset = offset < 0 and 0 or (offset > r and r or offset)
	self.target = offset
	if not gliding[self] then
		Live(self)
	end
	if Anim.reduceMotion or not self.frame:IsVisible() or abs(offset - self.pos) < 0.5 then
		return self:Jump(offset)
	end
	if not gliding[self] then
		gliding[self] = true
		nGliding = nGliding + 1
		driver:Show()
	end
end

function Glide:Wheel(delta)
	if Secret(delta) or type(delta) ~= "number" then
		return
	end
	local base
	if gliding[self] then
		base = self.target
	else
		Live(self)
		base = self.pos
	end
	self:To(base - delta * self.step)
end

function Glide:Stop()
	Halt(self)
	self.target = self.pos
	Sleep()
end

function Glide:Sync(v)
	if Secret(v) or type(v) ~= "number" then
		return
	end
	self.pos, self.target = v, v
	Halt(self)
	Sleep()
end

function Glide:IsGliding()
	return gliding[self] ~= nil
end

-- one wheel handler and one scroll hook for every gliding ScrollFrame
local GlideWheel = Perf.Shared("OnMouseWheel on a gliding scroll", function(frame, delta)
	local g = glideOf[frame]
	if g then
		g:Wheel(delta)
	end
end, "script")
local GlideSet = Perf.Shared("SetVerticalScroll on a gliding scroll", function(frame, v)
	local g = glideOf[frame]
	if g and not g.busy then
		g:Sync(v)
	end
end, "hook")

function Anim:Glide(frame, opts)
	local g = glideOf[frame]
	if g then
		return g
	end
	opts = opts or NO_OPTS
	local surface = opts.get ~= nil
	g = setmetatable({ frame = frame, step = opts.step or 80, rate = opts.rate or Anim.GLIDE_RATE,
		get = opts.get or ScrollGet, set = opts.set or ScrollSet, range = opts.range or ScrollRange,
		pos = 0, target = 0, busy = false }, Glide)
	Live(g)
	g.target = g.pos
	glideOf[frame] = g
	if not surface then
		Perf.hooksecurefunc(frame, "SetVerticalScroll", GlideSet)   -- our own ScrollFrame
		if opts.wheel ~= false then
			frame:EnableMouseWheel(true)
			Perf.SetScript(frame, "OnMouseWheel", GlideWheel)
		end
	end
	return g
end

-- one frame of every glide: listed first (a set's hooks may start or stop a
-- glide, and a key added during a pairs() walk is undefined in Lua), then
-- stepped
StepGlides = function(elapsed)
	local n = 0
	for g in pairs(gliding) do
		n = n + 1
		stepList[n] = g
	end
	for i = 1, n do
		local g = stepList[i]
		stepList[i] = nil
		if gliding[g] then
			local r = Range(g)
			if not r or not g.frame:IsVisible() then
				g:Jump(g.target)
			else
				local target = g.target
				if target > r then
					target = r
					g.target = r
				end
				local pos = g.pos + (target - g.pos) * (1 - exp(-g.rate * elapsed))
				if Anim.reduceMotion or abs(target - pos) < 0.5 then
					pos = target
					Halt(g)
				end
				local ok, err = pcall(Put, g, pos)
				if not ok then
					g.busy = false
					Halt(g)
					geterrorhandler()(err)
				end
			end
		end
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

-- A looping glow (audit rank 10: the configurator's important module; later
-- the Quest List's pulse): a BOUNCE alpha group on `region`, made here once
-- per region so the addon's AnimationGroups are made in this file, played
-- through PlayGroup (under Reduce Motion a still picture at `to`). Asked
-- again, it plays the region's group again. Returns the group: StopGroup it
-- as any other (a stopped one stays stopped through a Reduce Motion switch).
--   MelloUI.Anim:Pulse(region, from (0.45), to (1), period (0.9 s))
local pulseOf = setmetatable({}, { __mode = "k" })   -- [region] = group
local pulseTo = setmetatable({}, { __mode = "k" })   -- [group] = its still alpha

local function PulseStill(group)
	local region = group:GetParent()
	if region and pulseTo[group] then
		region:SetAlpha(pulseTo[group])
	end
end

function Anim:Pulse(region, from, to, period)
	local group = pulseOf[region]
	if not group then
		group = region:CreateAnimationGroup()
		group:SetLooping("BOUNCE")
		local a = group:CreateAnimation("Alpha")
		a:SetFromAlpha(from or 0.45)
		a:SetToAlpha(to or 1)
		a:SetDuration(period or 0.9)
		pulseTo[group] = to or 1
		pulseOf[region] = group
	end
	self:PlayGroup(group, PulseStill)
	return group
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

-- for the tests and /melloperf: how many tweens and glides run
function Anim:Busy()
	return count, nGliding
end

MelloUI:Profile("Anim", "tween driver", driver)
