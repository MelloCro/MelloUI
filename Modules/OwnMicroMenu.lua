--------------------------------------------------------------------------------
-- MelloUI - Own Bars, the micro menu's place as MelloUI's own (fr-18 stage 4, 2026-11-02; the user's pick A of fr-18:
-- "the game's own micro buttons moved into our holder", then "Stage 4")
--
-- One system with Modules/OwnBars.lua (MelloUI.OwnBars: its parts, its places, its helpers OB.kit). The micro buttons
-- stay the game's (their clicks open the game's windows -- some only the game's own code may open in a fight --, their
-- alerts and pulses, their tooltips; the Fader, Dark Mode and the backdrops dress them as before). What is ours is the
-- PLACE: a holder of ours (MelloUIMicroMenu), a mover of MelloUI's own store, where the game's micro menu stood:
--   * no place of its own (the player's Edit Layout save, a profile, the installer or an import give one): the holder
--     follows the game's micro menu (hung on it, live, by Modules/OwnBars.lua's rule) and the game's stays where its
--     Edit Mode layout puts it -- nothing of the game's moved;
--   * a place of its own: the holder stands there and the game's micro menu (MicroMenuContainer) hangs on it by its own
--     anchor point, moved with Edit Mode's kept-aside methods (ClearAllPointsBase / SetPointBase: CLAUDE.md rule 2) --
--     again after each time the game lays its layout (EDIT_MODE_LAYOUTS_UPDATED and the rest of Own Bars' follow cues);
--     back to its own anchors (read before ours moved it) on a Reset or when UI Modifications goes off.
-- Its Size and Orientation stay the layout's (the holder takes the shown buttons' extent). Out of a fight only (in one,
-- after it).
--
--   OwnBars.Micro                       the part: holder, Dump(print)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local OB = MelloUI.OwnBars
if not (OB and OB.kit and OB.AddPart) then
	return
end
local Safe = MelloUI.Safe
local Finite = Safe.Finite
local K = OB.kit
local Call = K.Call
local Perf = MelloUI.Perf:Scope("OwnMicroMenu")

local PART = "micro"
local KEY = "MelloUIMicroMenu"
local LABEL = "Micro Menu"
local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
	BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

local S = {}
OB.Micro = S

local function Game()
	local f = rawget(_G, "MicroMenuContainer")
	return type(f) == "table" and f or nil
end

-- Edit Mode's kept-aside method where the frame has it (Core.lua's Raw: the overrides leave tainted state)
local function Raw(f, method)
	return f[method .. "Base"] or f[method]
end

-- the game's frame's anchors as they are (plain), to put back
local function Points(f)
	local out = {}
	local n = Finite(Call(f, "GetNumPoints")) or 0
	for i = 1, n do
		local ok, point, rel, relPoint, x, y = pcall(f.GetPoint, f, i)
		x, y = ok and Finite(x), ok and Finite(y)
		if not (ok and x and y and POINTS[point] and POINTS[relPoint]) then
			return nil
		end
		out[i] = { point, rel, relPoint, x, y }
	end
	return #out > 0 and out or nil
end

local function OnHolder(f)
	local ok, _, rel = pcall(f.GetPoint, f, 1)
	return ok and rel == S.holder
end

-- (the user, 2026-11-02: "micro menu edit layout moveable frame does not fit the Micromenu size") the micro buttons as
-- they show against the container: a skin lays them wider than the game's container is (Oldschool's rims at the bag
-- slots' size and pitch, squares wider than the buttons), so the holder takes the SHOWN buttons' extent as the
-- backdrop measures it (ActionBars' MicroRect, the rims counted) -- its offset from the container's bottom left in the
-- container's own units (S.dx, S.dy) and its size on the screen (S.pw, S.ph: px, the holder sized from them at its own
-- scale, Fit); the container's own rect where no button reads
local rect = {}
local function Measure(game)
	local cl, cb, cr, ct = Safe.ScreenRect(game)
	local es = Finite(Call(game, "GetEffectiveScale"))
	if not (cl and es and es > 0) then
		return false
	end
	local bars = MelloUI:GetModule("ActionBars")
	local got = bars and bars.MicroRect and bars.MicroRect(rect)
	local l, b, r, t = cl, cb, cr, ct
	if got then
		l, b, r, t = got[1], got[2], got[3], got[4]
	end
	S.dx, S.dy = (l - cl) / es, (b - cb) / es
	S.pw, S.ph = r - l, t - b
	return S.pw > 0 and S.ph > 0
end

-- (the user's dump, 2026-11-02: the holder at its own place's scale 1.2 was sized in the container's units, scale 1:
-- 1.2 times the buttons' width) the holder at the buttons' size on the screen in ITS units, after its place set its
-- scale; Edit Layout's placeholder in UI units
local function Fit(holder)
	local hs = Finite(Call(holder, "GetEffectiveScale"))
	local us = Finite(Call(UIParent, "GetEffectiveScale"))
	if not (hs and us and hs > 0 and us > 0) then
		return
	end
	local w, h = S.pw / hs, S.ph / hs
	local ok, ow, oh = pcall(holder.GetSize, holder)
	if not (ok and math.abs((Finite(ow) or 0) - w) < 0.01 and math.abs((Finite(oh) or 0) - h) < 0.01) then
		holder:SetSize(w, h)
	end
	local ph = S.placeholder
	ph[1], ph[2] = S.pw / us, S.ph / us
end

-- the game's micro menu on our holder: its bottom left where the shown buttons' extent puts it (out of a fight)
local function Onto(game)
	if not OnHolder(game) then
		S.saved = Points(game)   -- (where the game's layout put it last: what a Reset gives back)
	end
	if not S.saved then
		return
	end
	if pcall(Raw(game, "ClearAllPoints"), game) then
		pcall(Raw(game, "SetPoint"), game, "BOTTOMLEFT", S.holder, "BOTTOMLEFT", -(S.dx or 0), -(S.dy or 0))
		S.moved = true
	end
end

-- the game's micro menu back on its own anchors (read before ours moved it)
local function Home(game)
	if S.moved and S.saved and game and OnHolder(game) then
		if pcall(Raw(game, "ClearAllPoints"), game) then
			local set = Raw(game, "SetPoint")
			for _, pt in ipairs(S.saved) do
				pcall(set, game, pt[1], pt[2], pt[3], pt[4], pt[5])
			end
		end
	end
	S.moved = false
end

local function Later(fn, key)
	if InCombatLockdown() then
		MelloUI.Kit:WhenOutOfCombat(fn, key)
		return true
	end
	return false
end

-- the holder at the game's micro menu's size; the place: following the game's, or its own with the game's on it
local function Placed()
	local game, holder = Game(), S.holder
	if not (OB.On(PART) and game and holder) or Later(Placed, "Own Bars: the micro menu placed") then
		return
	end
	if not Measure(game) then
		local es = Finite(Call(game, "GetEffectiveScale")) or Finite(Call(UIParent, "GetEffectiveScale")) or 1
		S.dx, S.dy = 0, 0
		S.pw, S.ph = (Finite(Call(game, "GetWidth")) or 100) * es, (Finite(Call(game, "GetHeight")) or 30) * es
	end
	if K.Place(holder) then
		Home(game)
		-- (hung on the game's container over its shown buttons: the stack's slot form, the container's own units)
		K.StackOrGame(holder, game, { [holder] = { base = game, x = S.dx, y = S.dy } })
	else
		Onto(game)
	end
	Fit(holder)
end
OB.followers[PART] = Placed

local function On()
	local game = Game()
	if not game or InCombatLockdown() then
		return false
	end
	if not S.holder then
		S.holder = CreateFrame("Frame", KEY, UIParent)
		OB.mine[S.holder] = true
		S.holder:SetFrameStrata(Call(game, "GetFrameStrata") or "MEDIUM")
		-- (Edit Layout fires nothing while a plate is dragged: the holder's own SetPoint, post-hooked -- ours -- hangs
		-- the game's micro menu on it the moment it stands anywhere but on the game's, so the menu moves with its plate;
		-- never while the holder hangs on the game's, which would anchor the two on each other)
		hooksecurefunc(S.holder, "SetPoint", function(holder, _, rel)
			local g = Game()
			if OB.On(PART) and g and rel ~= g and not InCombatLockdown() and not OnHolder(g) then
				Onto(g)
			end
		end)
	end
	OB.gameOf[S.holder] = game
	OB.standing[PART] = true
	S.placeholder = S.placeholder or { Finite(Call(game, "GetWidth")) or 100, Finite(Call(game, "GetHeight")) or 30 }
	local anchor = Points(game)
	K.Register(S.holder, PART, KEY, LABEL, S.placeholder, anchor and anchor[1][1] or "BOTTOMRIGHT")
	OB.followed[S.holder] = nil
	S.holder:Show()
	Placed()
	K.FollowListen()
	if not S.listening then
		S.listening = true
		-- (the plate's fit counts in Edit Layout: the buttons measured again as it opens -- a skin may have laid them anew)
		MelloUI:On("editlayout", function(showing)
			if showing and OB.On(PART) then
				OB.FollowSoon()
			end
		end, "Own Bars: the micro menu measured for Edit Layout")
		-- (the game's menu narrower or wider -- a button shown or hidden by the game, a skin's pitch: measured again)
		Perf.HookScript(game, "OnSizeChanged", OB.FollowSoon)
	end
	return true
end

local function Off()
	OB.standing[PART] = nil
	Home(Game())
	S.saved = nil
	if S.holder then
		S.holder:Hide()
	end
end

OB.AddPart({ id = PART, on = On, off = Off })
OB.AddSystem("MicroMenu", PART)
OB.AddKey(KEY)

-- /run MelloUI.OwnBars.Micro.Dump() -- (into /mellolog too) the holder, the game's menu, and each of the menu's buttons:
-- its slot (layoutIndex), shown / seen / enabled, its alpha as seen, its rect (screen px) and its skin's rim's
function S.Dump(out)
	out = out or function(s) MelloUI:Print(s) end
	local game, holder = Game(), S.holder
	local l, b, r, t, gl, gb, gr, gt
	if holder then
		l, b, r, t = Safe.ScreenRect(holder)
	end
	if game then
		gl, gb, gr, gt = Safe.ScreenRect(game)
	end
	out(("Own Bars, the micro menu: standing %s, %s; holder %s, the game's %s, on ours %s"):format(
		tostring(OB.On(PART)), holder and (OB.followed[holder] and "following the game's" or "its own place") or "-",
		l and ("%.0f,%.0f-%.0f,%.0f"):format(l, b, r, t) or "-", gl and ("%.0f,%.0f-%.0f,%.0f"):format(gl, gb, gr, gt) or "-",
		tostring(game and OnHolder(game))))
	local menu = rawget(_G, "MicroMenu")
	-- (each one's scale, its own and as seen: the plate is the holder's rect, the measure in the container's units)
	local function Scales(f)
		return ("%s / %s"):format(tostring(Finite(Call(f, "GetScale"))), tostring(Finite(Call(f, "GetEffectiveScale"))))
	end
	local got = S.pw and (" measured %.1f x %.1f px at %.1f, %.1f"):format(S.pw, S.ph, S.dx or 0, S.dy or 0) or ""
	out(("  holder%s; scales (own / seen): holder %s, container %s, menu %s, UIParent %s"):format(got,
		holder and Scales(holder) or "-", game and Scales(game) or "-", type(menu) == "table" and Scales(menu) or "-",
		Scales(UIParent)))
	local bars = MelloUI:GetModule("ActionBars")
	local mr = bars and bars.MicroRect and bars.MicroRect({})
	out("  the buttons' rect (rims counted): " .. (mr and ("%.0f,%.0f-%.0f,%.0f"):format(mr[1], mr[2], mr[3], mr[4]) or "-"))
	local ok, kids = false, nil
	if type(menu) == "table" then
		ok, kids = pcall(function() return { menu.GetChildren(menu) } end)
	end
	local repOf = MelloUI.Kept and MelloUI.Kept.repOf or {}
	local function Rect(f)
		local fl, _, fr = Safe.ScreenRect(f)
		return fl and ("%.0f-%.0f"):format(fl, fr) or "-"
	end
	for _, k in ipairs(ok and kids or {}) do
		local rep = repOf[k]
		out(("  %s slot %s: shown %s, seen %s, enabled %s, alpha %s, x %s, rim %s"):format(tostring(Call(k, "GetName")),
			tostring(Safe.Value(rawget(k, "layoutIndex"))), tostring(Call(k, "IsShown")), tostring(Call(k, "IsVisible")),
			tostring(Call(k, "IsEnabled")), tostring(Finite(Call(k, "GetEffectiveAlpha"))), Rect(k),
			rep and rep.object and (tostring(Call(rep.object, "IsShown")) .. " " .. Rect(rep.object)) or "-"))
	end
end
