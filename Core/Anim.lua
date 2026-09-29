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
--   MelloUI.Anim:Pulse(region, from, to, period[, still][, hold]) -> group
--                                             a looping glow; with a hold it
--                                             pulses that long, then stays
--                                             still (below)
--   MelloUI.Anim:Spin(region[, period]) -> group
--                                             a slow turn round and round
--                                             (below)
--   MelloUI.Anim:Expand(regions, from, opts) / :Collapse(regions, from, opts)
--                                             the soft expand: regions ease
--                                             out of one point and back in
--                                             (below; :Retract, :IsExpanded)
--   MelloUI.Anim:Mirror(frame, fadeIn, hold, fadeOut, smoothing) -> group
--   MelloUI.Anim:StopMirror(frame)            a fade the game runs on a line,
--                                             copied onto our frame (below)
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
-- tween finish at once and every group end at once (the one exception is
-- Mirror, which follows a fade the game runs anyway). UI Modifications'
-- Reduce Motion switch sets it, whether that module is on or off.
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
-- end). Only the curves MelloUI eases along (audit, 2026-09-29: the eight
-- nobody named went).
--------------------------------------------------------------------------------

local exp, abs = math.exp, math.abs

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
--   g:IsGliding()   (the tests' probe)   g.pos, g.target, g.step
-- The step closes the same share of the gap at any frame rate:
-- pos += (target - pos) * (1 - exp(-rate * dt)); it snaps within 0.5. The
-- set runs in a pcall: an error goes to the error handler and halts that
-- glide only. Nothing is made per step or per notch.
--------------------------------------------------------------------------------

Anim.GLIDE_RATE = 16   -- 1/s: the configurator's feel at 60 fps (it closed 14/60 of the gap a frame)

-- that share for one step (the tests measure the feel with it; the driver
-- works the same sum out inline)
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
-- A stopped group is false, not nil: its key stays, so playing it again
-- after a collection finds it (a nil-valued key is marked dead by the
-- collection and inserted anew, which rehashes the table when its slot was
-- taken by a colliding key: work, though no garbage, as the old node array
-- is freed at once)
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
		groups[group] = false
		group:Stop()
	end
end

-- A looping glow (audit rank 10: the configurator's important module; later
-- the Quest List's pulse): a BOUNCE alpha group on `region`, made here once
-- per region so the addon's AnimationGroups are made in this file, played
-- through PlayGroup (under Reduce Motion a still picture at `to`). Asked
-- again, it plays the region's group again. Returns the group: StopGroup it
-- as any other (a stopped one stays stopped through a Reduce Motion switch).
--   MelloUI.Anim:Pulse(region, from (0.45), to (1), period (0.9 s)[, still][, hold])
--     still   the alpha it rests at when still: under Reduce Motion, and
--             after a hold (left out: the `to` given in the same ask, else
--             the one it had)
--     hold    left out (nil or false): it pulses for as long as it plays
--             (the BOUNCE group above). Seconds: it breathes about that long
--             (whole breaths, eased in and out), then eases down to `still`
--             and stays there, its group ended (0.14.0, the round glow's
--             Settle: the user's
--             "pulse for about 10 s, then a steady glow"). That is a second
--             group of the region's own, made on the first ask with a hold;
--             asked again it starts again from its first breath, with the
--             from, to and period given (their defaults when left out).
--   Asking for one kind stops the other. The looping group takes the values
--   given again (one left out keeps its own). Nothing is made per ask once
--   the region's groups are made.
local pulseOf = setmetatable({}, { __mode = "k" })   -- [region] = group
local pulseTo = setmetatable({}, { __mode = "k" })   -- [group] = its still alpha
local breathOf = setmetatable({}, { __mode = "k" })  -- [region] = its breathing group (a hold)
local breathParts = setmetatable({}, { __mode = "k" })   -- [breathing group] = its Alpha animations, in order
local MAX_BREATHS = 8

local function PulseStill(group)
	local region = group:GetParent()
	if region and pulseTo[group] then
		region:SetAlpha(pulseTo[group])
	end
end

-- the breathing group's animations for a hold: up and down in turn, the
-- last one down to `still` (FinalAlpha leaves the region there). Ones made
-- for a longer hold asked before come last, empty, at `still`.
local function Breaths(group, from, to, period, still, hold)
	local list = breathParts[group]
	local n = math.floor(hold / (2 * period) + 0.5)
	if n < 1 then
		n = 1
	elseif n > MAX_BREATHS then
		n = MAX_BREATHS
	end
	local need = 2 * n
	for i = #list + 1, need do
		local a = group:CreateAnimation("Alpha")
		a:SetSmoothing("IN_OUT")
		list[i] = a
	end
	for i = 1, #list do
		local a = list[i]
		a:SetOrder(i)
		if i > need then
			a:SetFromAlpha(still)
			a:SetToAlpha(still)
			a:SetDuration(0)
		elseif i % 2 == 1 then
			a:SetFromAlpha(from)
			a:SetToAlpha(to)
			a:SetDuration(period)
		else
			a:SetFromAlpha(to)
			a:SetToAlpha(i == need and still or from)
			a:SetDuration(period)
		end
	end
end

-- a number to use: a plain one above 0, else the default
local function Positive(v, default)
	if type(v) ~= "number" or Secret(v) or v <= 0 then
		return default
	end
	return v
end

function Anim:Pulse(region, from, to, period, still, hold)
	if hold then
		hold = Positive(hold, 0.9)
		from, to, period = from or 0.45, to or 1, Positive(period, 0.9)
		still = still or to
		local group = breathOf[region]
		if not group then
			group = region:CreateAnimationGroup()
			group:SetToFinalAlpha(true)
			breathParts[group] = {}
			breathOf[region] = group
		end
		local loop = pulseOf[region]
		if loop then
			self:StopGroup(loop)
		end
		group:Stop()
		Breaths(group, from, to, period, still, hold)
		pulseTo[group] = still
		self:PlayGroup(group)   -- under Reduce Motion: stopped at once at `still`
		return group
	end
	local group = pulseOf[region]
	if not group then
		group = region:CreateAnimationGroup()
		group:SetLooping("BOUNCE")
		local a = group:CreateAnimation("Alpha")
		a:SetFromAlpha(from or 0.45)
		a:SetToAlpha(to or 1)
		a:SetDuration(period or 0.9)
		pulseTo[group] = still or to or 1
		pulseOf[region] = group
	elseif from or to or period or still then
		local a = group:GetAnimations()
		if from then
			a:SetFromAlpha(from)
		end
		if to then
			a:SetToAlpha(to)
		end
		if period then
			a:SetDuration(period)
		end
		if still then
			pulseTo[group] = still
		elseif to then
			pulseTo[group] = to   -- (still left out: the new `to`)
		end
	end
	local breath = breathOf[region]
	if breath then
		self:StopGroup(breath)
	end
	self:PlayGroup(group, PulseStill)
	return group
end

-- A slow turn, round and round (0.15.0, Route's Direction Arrow while the
-- roads go in: "working"): a REPEAT Rotation group on `region`, a full turn
-- clockwise every `period` seconds (2.4), made here once per region, played
-- through PlayGroup: under Reduce Motion a still picture, unturned. Asked
-- again, it plays the region's group again with the period given. Returns
-- the group: StopGroup it as any other (the region back to its own turn).
--   MelloUI.Anim:Spin(region[, period])
local spinOf = setmetatable({}, { __mode = "k" })   -- [region] = group

function Anim:Spin(region, period)
	local group = spinOf[region]
	if not group then
		group = region:CreateAnimationGroup()
		group:SetLooping("REPEAT")
		local turn = group:CreateAnimation("Rotation")
		turn:SetDegrees(-360)
		spinOf[region] = group
	end
	group:GetAnimations():SetDuration(Positive(period, 2.4))
	self:PlayGroup(group)
	return group
end

--------------------------------------------------------------------------------
-- The soft expand (0.14.0, the Reminder widget's hover: the user, 2026-09-26:
-- "when hovering over the Widget, the expanding of other unread
-- notifications is animated, with a soft expanding animation"). A few
-- regions ease out of one point to their places while fading in, and ease
-- back in again, run by the engine: no Lua per frame and no timer.
--   MelloUI.Anim:Expand(regions, from, opts)
--   MelloUI.Anim:Collapse(regions, from, opts)
--     regions  a list of OUR regions (kept by the caller: no table per
--              call), each laid where it rests by its FIRST anchor on
--              `from` (CENTER on from's CENTER at (0, 40 * i), say): it
--              comes out of that anchor's point on `from` and goes back
--              into it. One whose first anchor is not on `from`, or cannot
--              be read, only fades. Not protected: a secure button, or a
--              frame one sits on, cannot be shown or hidden in combat (see
--              "In combat" below)
--     from     the region they come out of (the widget's button)
--     opts     optional, one table per caller, its fields read per call:
--              count    how many of `regions` take part (default #regions)
--              time     the way out, Expand's (0.22 s)
--              backTime the way back in, Collapse's (0.16 s)
--              stagger  from one region to the next (0.03 s; the way in
--                       takes them last first)
--              travel   the share of the way they slide (1: from the point
--                       itself; 0: a fade only)
--              grace    the wait before they go in (0.35 s), so the mouse
--                       can travel onto one: an Expand meanwhile keeps them
--                       out
-- Expand: each hidden region is shown and eased out; one on its way in is
-- called back (at its place at full at once); one out, or on its way out,
-- is left as it is. Collapse: after the grace each shown region eases back
-- in and fades, then hides (its alpha back to 1); one still on its way out
-- goes in once it is out. Reduce Motion (as it is when asked): Expand shows
-- them at their places at once, Collapse hides them at once when the grace
-- is over (the grace is no motion: the mouse still needs it).
--   MelloUI.Anim:Retract(regions[, opts])   all in and hidden at once (no
--       motion, no grace: the widget hidden in combat, say)
--   MelloUI.Anim:IsExpanded(region)         shown and not going in
-- In combat: a protected region (asked with IsProtected, a secret answer
-- counting as protected) is never shown or hidden here while the lockdown
-- lasts (the game would block it): Expand leaves it hidden, Collapse and
-- Retract leave it out at its place at full, and a way in whose end comes
-- in combat stops there, out at full. So Retract them at
-- PLAYER_REGEN_DISABLED (it fires before the lockdown) and Collapse again
-- after it; better, keep secure buttons out of `regions`.
-- Per region two AnimationGroups, made on its first Expand and reused (their
-- offsets and times set again per call): nothing is made per hover. They
-- are played directly, not through PlayGroup, so each end is sure to come:
-- the only Lua that runs is that end (one call per region and move).
--------------------------------------------------------------------------------

do
	local outOf = setmetatable({}, { __mode = "k" })    -- [region] = its way-out group
	local inOf = setmetatable({}, { __mode = "k" })     -- [region] = its way-in group
	local partsOf = setmetatable({}, { __mode = "k" })  -- [group] = { jump, slide, fade }
	local goIn = setmetatable({}, { __mode = "k" })     -- [region] = true: in once it is out (false, never nil: no dead key to rehash)
	local ExpandDone, CollapseDone   -- the groups' one end each, made with the first group

	-- a protected region (a secure button, or a frame one sits on): in the
	-- combat lockdown the game will not let us show or hide it. Asked only
	-- in combat (`InCombatLockdown() and Protected(region)`), so out of it no
	-- Lua runs for this; a secret answer counts as protected
	local function Protected(region)
		local isProtected = region.IsProtected
		if type(isProtected) ~= "function" then
			return false
		end
		local protected = isProtected(region)
		return Secret(protected) or (protected and true or false)
	end

	local function OutDone(group)
		local region = group:GetParent()
		if region and goIn[region] then
			goIn[region] = false
			local back = inOf[region]
			if back and not (InCombatLockdown() and Protected(region)) then
				back:Play()
			end
		end
	end

	local function InDone(group)
		local region = group:GetParent()
		if region then
			if not (InCombatLockdown() and Protected(region)) then
				region:Hide()
			end
			region:SetAlpha(1)   -- (protected in combat: left out at its place, at full)
		end
	end

	-- a region's group: a jump (where it starts, at once), a slide and a fade
	local function Group(region, byRegion, done)
		local group = byRegion[region]
		if group then
			return group
		end
		if not ExpandDone then
			ExpandDone = Perf.Shared("OnFinished of a soft expand (a pending way in)", OutDone, "script")
			CollapseDone = Perf.Shared("OnFinished of a soft collapse (hides its region)", InDone, "script")
		end
		group = region:CreateAnimationGroup()
		local jump = group:CreateAnimation("Translation")
		jump:SetOrder(1)
		jump:SetDuration(0)
		local slide = group:CreateAnimation("Translation")
		slide:SetOrder(1)
		local fade = group:CreateAnimation("Alpha")
		fade:SetOrder(1)
		group:SetToFinalAlpha(true)
		Perf.SetScript(group, "OnFinished", done == "out" and ExpandDone or CollapseDone)
		partsOf[group] = { jump, slide, fade }
		byRegion[region] = group
		return group
	end

	-- the way from its place back to the point it comes out of: its first
	-- anchor's offset on `from`, turned round (0, 0 for anything else)
	local function Back(region, from, travel)
		local ok, _, rel, _, x, y = pcall(region.GetPoint, region, 1)
		if not ok or Secret(rel) or rel ~= from or Secret(x) or Secret(y)
			or type(x) ~= "number" or type(y) ~= "number" then
			return 0, 0
		end
		return -x * travel, -y * travel
	end

	-- a time from opts: a plain number from 0 up, else the default
	local function Opt(opts, key, default)
		local v = opts[key]
		if type(v) ~= "number" or Secret(v) or v < 0 then
			return default
		end
		return v
	end

	local function Travel(opts)
		local t = opts.travel
		if type(t) ~= "number" or Secret(t) then
			return 1
		end
		return t < 0 and 0 or (t > 1 and 1 or t)
	end

	local function Count(regions, opts)
		local n = opts.count
		if type(n) ~= "number" or Secret(n) or n > #regions then
			return #regions
		end
		return n
	end

	function Anim:Expand(regions, from, opts)
		if type(regions) ~= "table" then
			return
		end
		opts = opts or NO_OPTS
		local n = Count(regions, opts)
		local time, stagger = Opt(opts, "time", 0.22), Opt(opts, "stagger", 0.03)
		local travel = Travel(opts)
		local combat = InCombatLockdown()
		for i = 1, n do
			local region = regions[i]
			if region then
				goIn[region] = false
				local back = inOf[region]
				if back and back:IsPlaying() then
					-- on its way in (or waiting to go): called back, at its place at full
					back:Stop()
					region:SetAlpha(1)
				elseif not region:IsShown() and not (combat and Protected(region)) then
					if self.reduceMotion then
						region:SetAlpha(1)
						region:Show()
					else
						local group = Group(region, outOf, "out")
						local parts = partsOf[group]
						local dx, dy = Back(region, from, travel)
						local delay = (i - 1) * stagger
						parts[1]:SetOffset(dx, dy)
						local slide, fade = parts[2], parts[3]
						slide:SetOffset(-dx, -dy)
						slide:SetDuration(time)
						slide:SetStartDelay(delay)
						slide:SetSmoothing("OUT")
						fade:SetFromAlpha(0)
						fade:SetToAlpha(1)
						fade:SetDuration(time)
						fade:SetStartDelay(delay)
						fade:SetSmoothing("OUT")
						group:Stop()
						region:SetAlpha(0)
						region:Show()
						group:Play()
					end
				end
			end
		end
	end

	function Anim:Collapse(regions, from, opts)
		if type(regions) ~= "table" then
			return
		end
		opts = opts or NO_OPTS
		local n = Count(regions, opts)
		local time, stagger = Opt(opts, "backTime", 0.16), Opt(opts, "stagger", 0.03)
		local grace, travel = Opt(opts, "grace", 0.35), Travel(opts)
		local still = self.reduceMotion
		if still then
			stagger = 0   -- all at once when the grace is over
		end
		local combat = InCombatLockdown()
		for i = 1, n do
			local region = regions[i]
			if region and region:IsShown() and not (combat and Protected(region)) then
				local group = Group(region, inOf, "in")
				if not group:IsPlaying() then
					local parts = partsOf[group]
					local dx, dy = 0, 0
					if not still then
						dx, dy = Back(region, from, travel)
					end
					local delay = grace + (n - i) * stagger
					local length = still and 0 or time
					parts[1]:SetOffset(0, 0)
					local slide, fade = parts[2], parts[3]
					slide:SetOffset(dx, dy)
					slide:SetDuration(length)
					slide:SetStartDelay(delay)
					slide:SetSmoothing("IN")
					fade:SetFromAlpha(1)
					fade:SetToAlpha(0)
					fade:SetDuration(length)
					fade:SetStartDelay(delay)
					fade:SetSmoothing("IN")
					local out = outOf[region]
					if out and out:IsPlaying() then
						goIn[region] = true   -- once it is out (OutDone)
					else
						group:Play()
					end
				end
			elseif region then
				goIn[region] = false
			end
		end
	end

	-- is a region out (shown, not on its way in)? For the tests and a
	-- caller's hover logic
	function Anim:IsExpanded(region)
		if not region or not region:IsShown() then
			return false
		end
		local back = inOf[region]
		return not (back and back:IsPlaying()) and not goIn[region]
	end

	-- all in at once, with no motion and no grace (the widget hidden in
	-- combat, say): both groups stopped, each region hidden, its alpha back
	-- to 1 (a protected one in combat: left out, at full). opts.count as for
	-- Expand.
	function Anim:Retract(regions, opts)
		if type(regions) ~= "table" then
			return
		end
		local n = Count(regions, opts or NO_OPTS)
		local combat = InCombatLockdown()
		for i = 1, n do
			local region = regions[i]
			if region then
				goIn[region] = false
				local group = outOf[region]
				if group then
					group:Stop()
				end
				group = inOf[region]
				if group then
					group:Stop()
				end
				if not (combat and Protected(region)) then
					region:Hide()
				end
				region:SetAlpha(1)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The mirror (0.14.0, the centre texts' shade): the game's own fade of a
-- line, copied onto a frame of ours (the band under an error line or a raid
-- warning, which the game fades per line, where a texture cannot follow).
--   MelloUI.Anim:Mirror(frame, fadeIn, hold, fadeOut, smoothing) -> group
--       shows the frame, then 0 -> 1 over fadeIn, held `hold`, 1 -> 0 over
--       fadeOut (smoothing "NONE" (default), "IN", "OUT" or "IN_OUT"), then
--       hides it (its alpha left at 0; the next Mirror starts it from 0).
--       Asked again (a line whose fade the game started again) it starts
--       again from the beginning with the times given. A time that is not a
--       plain number (nil, secret, below 0) counts as 0. Engine-driven: one
--       AnimationGroup per frame, made on its first Mirror, its times set
--       again per call (no garbage); the only Lua is its end, which hides
--       the frame. NOT stopped or shortened by Reduce Motion: it follows a
--       fade the game runs anyway (the text keeps fading). Three Alpha
--       animations in turn, none with a start delay: in, the hold (1 -> 1)
--       and out, so an animation always sets the alpha while it plays and
--       nothing rests on the frame's own alpha (0 after a Mirror ended).
--   MelloUI.Anim:StopMirror(frame)   stops it and hides the frame
--------------------------------------------------------------------------------

do
	local mirrorOf = setmetatable({}, { __mode = "k" })     -- [frame] = its group
	local mirrorParts = setmetatable({}, { __mode = "k" })  -- [group] = { fadeIn, held, fadeOut }
	local SMOOTHING = { NONE = true, IN = true, OUT = true, IN_OUT = true }
	local MirrorDone   -- the groups' one end, made with the first

	local function Hidden(group)
		local frame = group:GetParent()
		if frame then
			frame:Hide()
		end
	end

	local function Seconds(v)
		if type(v) ~= "number" or Secret(v) or v < 0 then
			return 0
		end
		return v
	end

	function Anim:Mirror(frame, fadeIn, hold, fadeOut, smoothing)
		if type(frame) ~= "table" or not frame.CreateAnimationGroup then
			return nil
		end
		local group = mirrorOf[frame]
		if not group then
			if not MirrorDone then
				MirrorDone = Perf.Shared("OnFinished of a mirrored fade (hides its frame)", Hidden, "script")
			end
			group = frame:CreateAnimationGroup()
			local a = group:CreateAnimation("Alpha")
			a:SetOrder(1)
			a:SetFromAlpha(0)
			a:SetToAlpha(1)
			local b = group:CreateAnimation("Alpha")
			b:SetOrder(2)
			b:SetFromAlpha(1)
			b:SetToAlpha(1)
			local c = group:CreateAnimation("Alpha")
			c:SetOrder(3)
			c:SetFromAlpha(1)
			c:SetToAlpha(0)
			group:SetToFinalAlpha(true)
			Perf.SetScript(group, "OnFinished", MirrorDone)
			mirrorParts[group] = { a, b, c }
			mirrorOf[frame] = group
		end
		local parts = mirrorParts[group]
		parts[1]:SetDuration(Seconds(fadeIn))
		parts[2]:SetDuration(Seconds(hold))
		local out = parts[3]
		out:SetDuration(Seconds(fadeOut))
		out:SetSmoothing(type(smoothing) == "string" and SMOOTHING[smoothing] and smoothing or "NONE")
		group:Stop()
		frame:Show()
		group:Play()
		return group
	end

	function Anim:StopMirror(frame)
		local group = frame and mirrorOf[frame]
		if group then
			group:Stop()
		end
		if frame and frame.Hide then
			frame:Hide()
		end
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
	for group, listed in pairs(groups) do
		if listed then   -- (false: stopped through StopGroup)
			top = top + 1
			sweep[top] = group
		end
	end
	sweepTop = top
	for i = base + 1, top do
		local group = sweep[i]
		sweep[i] = nil
		-- still listed (a settle before it may have stopped it), with its
		-- settle as it is now
		local settle = groups[group]
		if settle and self.reduceMotion == on then
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
