--------------------------------------------------------------------------------
-- MelloUI - Shields: a unit's absorb shield on a health bar of ours (2.1.0;
-- the user, 2026-11-03: "The only thing that we are missing from the
-- Party/Raid Unitframes, Player, Target, Target of Target, Focus, Personal
-- Nameplate is the Overshields, like this one on the photo";
-- docs/plans/shields.md)
--
-- One system for the shield on every health bar of ours (one system per job).
-- It draws; its callers say when:
--   Healer Frames (Modules/HealerFrames.lua) on every bar with incoming heals
--     -- the player, target and focus frames and their targets', the pet's,
--     the party and raid buttons, the portrait party: its calculator's
--     amounts, after its heals, under its Incoming Heals switch
--   the Personal Display's health (no heals there): Shields.Update
-- On a bar, two strips of the game's own shield art (Interface\RaidFrame\
-- Shield-Fill under its striped Shield-Overlay, tiled), masked as the bar's
-- own fill is:
--   attached   the shield while it fits in the missing health: a strip laid
--              from where the health (or the heals after it) ends, the bar's
--              own size and direction, its value the calculator's damage
--              absorbs clamped to what is missing -- its fill is the shield's
--              share of the maximum, no sum in Lua
--   over       an overshield (the calculator's "clamped": more than fits): the
--              whole shield (UnitGetTotalAbsorbs) from the bar's far end back
--              over the health, in place of the attached strip
-- Every value, secret or not, goes to the client as it is: the strips'
-- values, and "clamped" through SetAlphaFromBoolean -- nothing compared,
-- nothing added up. The strips stand at the bar's own frame level, on its
-- fill's own draw layer T.SUB sublevels up (the stripes one more: over Healer
-- Frames' two heal segments), following the fill when Bar Textures lifts it;
-- under every text (a higher layer on every frame of ours).
--   Shields.Attach(bar) -> parts   once per bar
--   Shields.Paint(bar, fit, whole, max, clamped[, after])   the amounts its
--        caller's calculator read; after: the texture the attached strip
--        starts from (the heals' end; nil: the health fill's)
--   Shields.Update(bar, unit)   read here: the calculator clamped to the
--        missing health, no heals (the Personal Display's)
--   Shields.Sample(bar, share[, over[, after]])   a made-up shield: share
--        (0..1) of the maximum, over: an overshield (the previews)
--   Shields.Hide(bar)
-- Nothing is made at login: the strips with a bar's first Attach.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Shields")
local Secret = MelloUI.Safe.IsSecret
local ipairs, pcall, type = ipairs, pcall, type

local Shields = {}
MelloUI.Shields = Shields

local T = {
	FILL = "Interface\\RaidFrame\\Shield-Fill",        -- the game's shield (CompactUnitFrame's totalAbsorb)
	STRIPES = "Interface\\RaidFrame\\Shield-Overlay",  -- its stripes over it (totalAbsorbOverlay), tiled at their size
	SUB = 3,      -- the strips' fill this many sublevels over the health fill's (Healer Frames' heals at 1 and 2)
	CLAMP = 1,    -- Update's: Enum.UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals (its bars show no heals)
}
Shields.T = T

local parts = setmetatable({}, { __mode = "k" })   -- [health bar] = { attached, over, masked, ... }
local calc = nil   -- Update's calculator, one shared (read at once after each fill); false: none on this client

local function Calculator()
	if calc == nil then
		local make = rawget(_G, "CreateUnitHealPredictionCalculator")
		local ok, c = false, nil
		if type(make) == "function" then
			ok, c = pcall(make)
		end
		calc = ok and c or false
		if calc then
			pcall(calc.SetDamageAbsorbClampMode, calc, T.CLAMP)
		end
	end
	return calc or nil
end

-- a strip: a status bar at the bar's own level (its regions drawn by layer among the bar's), the shield's fill and
-- the stripes tiled over it (their layers: Layers)
local function Strip(bar)
	local s = CreateFrame("StatusBar", nil, bar)
	if s.SetUsingParentLevel then
		s:SetUsingParentLevel(true)
	else
		s:SetFrameLevel(bar:GetFrameLevel())
	end
	s:EnableMouse(false)
	s:SetStatusBarTexture(T.FILL)
	-- (the stripes follow the fill's own size: anchored to it, tiled at their own size; the getter tested for, as
	-- Lay does)
	local stripes = s:CreateTexture(nil, "ARTWORK")
	stripes:SetTexture(T.STRIPES, "REPEAT", "REPEAT")
	stripes:SetHorizTile(true)
	stripes:SetVertTile(true)
	stripes:SetAllPoints(s.GetStatusBarTexture and s:GetStatusBarTexture() or s)
	s.stripes = stripes
	s:SetMinMaxValues(0, 1)
	s:SetValue(0)
	s:Hide()
	return s
end

-- the strips on the fill's draw layer now, T.SUB sublevels up (the stripes one more); set when the fill's changed
local function Layers(p, fill)
	local ok, layer, sub = pcall(fill.GetDrawLayer, fill)
	if not ok or Secret(layer) or Secret(sub) or type(layer) ~= "string" then
		return
	end
	sub = type(sub) == "number" and sub or 0
	if layer == p.layer and sub == p.sub then
		return
	end
	p.layer, p.sub = layer, sub
	for _, s in ipairs({ p.attached, p.over }) do
		s:GetStatusBarTexture():SetDrawLayer(layer, math.min(7, sub + T.SUB))
		s.stripes:SetDrawLayer(layer, math.min(7, sub + T.SUB + 1))
	end
end

-- the fill's masks on the strips' fills and stripes, each once (the game cuts the player's and the target's fill with
-- its HealthBarMask: an unmasked strip would show the fill's whole height over the bar's edges; a texture takes three)
local function Masks(p, fill)
	local okN, n = pcall(fill.GetNumMaskTextures, fill)
	if not okN or Secret(n) or type(n) ~= "number" then
		return
	end
	for i = 1, math.min(n, 3) do
		local okM, mask = pcall(fill.GetMaskTexture, fill, i)
		if okM and mask and not p.masked[mask] then
			p.masked[mask] = true
			for _, s in ipairs({ p.attached, p.over }) do
				s:GetStatusBarTexture():AddMaskTexture(mask)
				s.stripes:AddMaskTexture(mask)
			end
		end
	end
end

-- the strips laid by the bar's direction now: attached from `from` outward (the bar's own size), over on the bar from
-- its far end; false: the bar has no fill (or no getter for it: then nothing is drawn)
local function Lay(bar, p, after)
	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not fill then
		return false
	end
	Layers(p, fill)
	if p.fill ~= fill then
		p.fill, p.laid = fill, nil
		Masks(p, fill)
	end
	local vertical = bar.GetOrientation and bar:GetOrientation() == "VERTICAL"
	local reverse = bar.GetReverseFill and bar:GetReverseFill() and true or false
	local from = after or fill
	local key = (vertical and "v" or "h") .. (reverse and "r" or "n")
	if p.laid == key and p.from == from then
		return true
	end
	p.laid, p.from = key, from
	local a, o = p.attached, p.over
	for _, s in ipairs({ a, o }) do
		s:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
	end
	a:SetReverseFill(reverse)
	o:SetReverseFill(not reverse)
	a:ClearAllPoints()
	a:SetSize(bar:GetWidth(), bar:GetHeight())
	if vertical then
		if reverse then
			a:SetPoint("TOP", from, "BOTTOM")
		else
			a:SetPoint("BOTTOM", from, "TOP")
		end
		a:SetPoint("LEFT", bar, "LEFT")
		a:SetPoint("RIGHT", bar, "RIGHT")
	else
		if reverse then
			a:SetPoint("RIGHT", from, "LEFT")
		else
			a:SetPoint("LEFT", from, "RIGHT")
		end
		a:SetPoint("TOP", bar, "TOP")
		a:SetPoint("BOTTOM", bar, "BOTTOM")
	end
	o:ClearAllPoints()
	o:SetAllPoints(bar)
	return true
end

-- (a bar resized: the attached strip's length follows -- the bar's own length is its maximum)
local OnBarSize = Perf.Shared("a shielded bar resized", function(bar)
	local p = parts[bar]
	if p then
		p.attached:SetSize(bar:GetWidth(), bar:GetHeight())
	end
end, "script")

function Shields.Attach(bar)
	local p = parts[bar]
	if p then
		return p
	end
	p = { masked = {} }
	p.attached = Strip(bar)
	p.over = Strip(bar)
	parts[bar] = p
	Perf.HookScript(bar, "OnSizeChanged", OnBarSize)
	return p
end

function Shields.Hide(bar)
	local p = parts[bar]
	if p then
		p.attached:Hide()
		p.over:Hide()
	end
end

-- the strips' values: `fit` the shield within what is missing, `whole` all of it, `max` the maximum, `clamped`
-- whether it is more than fits (any of them secret; clamped nil: not known, the whole from the far end)
function Shields.Paint(bar, fit, whole, max, clamped, after)
	local p = parts[bar]
	if not p then
		return
	end
	if not Lay(bar, p, after) then
		Shields.Hide(bar)
		return
	end
	local a, o = p.attached, p.over
	pcall(a.SetMinMaxValues, a, 0, max)
	pcall(a.SetValue, a, fit)
	pcall(o.SetMinMaxValues, o, 0, max)
	pcall(o.SetValue, o, whole)
	if Secret(clamped) then
		a:SetAlphaFromBoolean(clamped, 0, 1)
		o:SetAlphaFromBoolean(clamped, 1, 0)
	elseif clamped == nil then
		a:SetAlpha(0)
		o:SetAlpha(1)
	else
		a:SetAlpha(clamped and 0 or 1)
		o:SetAlpha(clamped and 1 or 0)
	end
	a:Show()
	o:Show()
end

function Shields.Update(bar, unit)
	if not parts[bar] then
		return
	end
	local okE, there = pcall(UnitExists, unit)
	if not unit or not okE or (not Secret(there) and not there) then
		Shields.Hide(bar)
		return
	end
	local okW, whole = pcall(UnitGetTotalAbsorbs, unit)
	local okM, max = pcall(UnitHealthMax, unit)
	if not (okW and okM) then
		Shields.Hide(bar)
		return
	end
	local fit, clamped = whole, nil
	local c = Calculator()
	if c and pcall(UnitGetDetailedHealPrediction, unit, nil, c) then
		local ok, amount, over = pcall(c.GetDamageAbsorbs, c)
		if ok then
			fit, clamped = amount, over
		end
	end
	Shields.Paint(bar, fit, whole, max, clamped)
end

-- the calculator made again at the next update (the tests' way in: a stand-in client)
function Shields.Reset()
	calc = nil
end

function Shields.Sample(bar, share, over, after)
	if not share or share <= 0 then
		Shields.Hide(bar)
		return
	end
	Shields.Paint(bar, share, share, 1, over and true or false, after)
end
