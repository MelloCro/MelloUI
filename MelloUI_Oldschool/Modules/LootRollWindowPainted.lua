--------------------------------------------------------------------------------
-- MelloUI - Loot Roll Window, the painted reskin's dress (2.1.61)
--
-- The user, 2026-11-20, to the sketch (BuildData/output/oldschool_loot_roll_sketch): "B Looks good", "Yes, build it".
-- The core's window (Modules/LootRollWindow.lua: the rows, the table, the buttons, the win) in Oldschool's frame set:
--   the window   the set's window frame (the chat's: one stretching texture, Kit.Sets.Window) round it, the dark
--                ground of its hole under the rows
--   a medal      the set's level ring round each item (and round the item beside a winner's frame)
--   the header   Oldschool's painted loot mark
-- On while the painted reskin is (Kit:IsOn("effects"), as the quest moments' dress); a new set lays it all again
-- (Kit.Sets.OnChange). Nothing made here at load: the core asks for the pieces when it builds its window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local R = MelloUI.LootRollWindow
local Kit = MelloUI.Kit
local Sets = Kit and Kit.Sets
if not (R and R.SetDress and Sets) then
	return   -- (a MelloUI without the window: nothing to dress)
end

local D = {
	FRAME = 0.27,         -- units a pixel of the set's window frame (the sketch's, as the quest moments' plaque)
	OPEN = 1.2,           -- the ring's opening past the icon
	MARK = "Interface\\AddOns\\MelloUI_Oldschool\\Media\\Icons\\chat_loot",
}

function D.On()
	return Kit:IsOn("effects") and Sets.Data() ~= nil
end

-- the set's window frame round the window and the ground in its hole (made at the first call, laid at each)
function D.Shell(frame, mark)
	local set = Sets.Data()
	if not set then
		return
	end
	if not D.win then
		D.win = Sets.Window(frame, "BACKGROUND", 4)
		D.ground = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
		Sets.Ground(D.ground)
	end
	local rail = set.chat.hole[1] * D.FRAME
	local half = rail / 2
	D.win:Lay(set, frame, rail)
	local g = D.ground
	g:ClearAllPoints()
	g:SetPoint("TOPLEFT", frame, "TOPLEFT", half - 2, 2 - half)
	g:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2 - half, half - 2)
	g:Show()
	if mark then
		MelloUI.Icons.Set(mark, D.MARK, 18)
	end
end

-- taken off again (another look dresses the window)
function D.Off()
	if D.win then
		D.win:Hide()
		D.ground:Hide()
	end
end

-- the set's level ring round a medal of radius hr (the texture's parent: the medal, 2 hr square)
function D.Ring(tex, hr)
	local set = Sets.Data()
	local lv = set and set.level
	if not lv then
		tex:Hide()
		return
	end
	local hole = lv.hole
	local cx, cy = (hole[1] + hole[3]) / 2, (hole[2] + hole[4]) / 2
	local k = (hr + D.OPEN) / ((hole[3] - hole[1]) / 2)
	tex:SetTexture(Sets.File(set, "level"))
	tex:SetTexCoord(0, lv.u, 0, lv.v)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", tex:GetParent(), "CENTER", (lv.w / 2 - cx) * k, -(lv.h / 2 - cy) * k)
	tex:SetSize(lv.w * k, lv.h * k)
	tex:Show()
end

function D.OnChange(fn)
	Sets.OnChange(fn)
end

R.SetDress(D)
