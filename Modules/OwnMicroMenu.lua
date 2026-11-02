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
-- Its Size and Orientation stay the layout's (the holder takes the container's size and scale). Out of a fight only
-- (in one, after it).
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

-- the game's micro menu on our holder, by its own anchor point (out of a fight)
local function Onto(game)
	if not OnHolder(game) then
		S.saved = Points(game)   -- (where the game's layout put it last: what a Reset gives back)
	end
	if not S.saved then
		return
	end
	local p = S.saved[1][1]
	if pcall(Raw(game, "ClearAllPoints"), game) then
		pcall(Raw(game, "SetPoint"), game, p, S.holder, p, 0, 0)
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
	local w, h = Finite(Call(game, "GetWidth")), Finite(Call(game, "GetHeight"))
	if w and h and w > 0 and h > 0 then
		holder:SetSize(w, h)
		local ph = S.placeholder
		ph[1], ph[2] = w, h
	end
	if K.Place(holder) then
		Home(game)
		K.StackOrGame(holder, game, {})
	else
		Onto(game)
	end
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

-- /run MelloUI.OwnBars.Micro.Dump(print)
function S.Dump(out)
	out = out or print
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
end
