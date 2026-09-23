--------------------------------------------------------------------------------
-- MelloUI - Quest Tracker
--
-- A tracker of MelloUI's own in the game's tracker's place, that SCROLLS
-- (player feedback, 2026-09-23: "Quest Tracker under minimap is static and
-- you cant scroll down or up"; user: "start building the scrollable
-- tracker"). The game's tracker on this client lays out only the quests that
-- fit its Edit Mode height and has no scrolling; changing what it lays out
-- would be running its tracker code from here (taint), so it is switched off
-- and this one stands in:
--
--   * the game's tracker is hidden with the game's own secure visibility
--     driver (and alpha 0 against a flash), only out of combat; it comes
--     back while Edit Mode is open, so it can still be moved and sized there,
--     and this tracker takes its place and height from it
--   * the watched quests with their objectives, coloured by difficulty,
--     rebuilt at most once a frame after the quest events
--   * the list scrolls with the mouse wheel inside a clipping frame (no
--     ScrollFrame): the content is re-anchored by the offset, the offset is
--     kept across rebuilds, and a thumb shows where the view is
--   * click a quest to follow it (super-track), Shift-click to stop watching
--     it, right-click to open it in the quest log; a quest item is used with
--     a click out of combat, through ONE secure button laid over the item
--     under the mouse -- nothing secure lives in the list, so it scrolls and
--     rebuilds in combat too
--   * the painted kit's look (the single rail, the stone, a parchment sheet
--     and the title plate) while the reskin covers the tracker, a plain dark
--     panel otherwise
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local M = MelloUI:RegisterModule("QuestTracker", {
	title = "Quest Tracker",
	desc = "A quest tracker in the game's tracker's place that scrolls with the mouse wheel, so every watched quest can be reached.",
	enabledByDefault = false,
	defaults = {
		-- the user's settings, 2026-09-23 ("Height 500 by default, width 300,
		-- scale 100%, font size 13 and scroll step 25"); 0 in Height / Width
		-- still means the game's tracker's size
		maxHeight = 500,
		width = 300,
		scale = 1,
		textSize = 13,
		headerSize = 16,
		scrollStep = 25,
		itemButtons = true,
		collapsed = false,
	},
	options = {
		{ type = "header", name = "Tracker" },
		{ type = "slider", key = "maxHeight", name = "Height", min = 0, max = 900, step = 20,
		  format = function(v) v = math.floor(v + 0.5) return v == 0 and "Edit Mode's" or tostring(v) end,
		  desc = "How tall the tracker may grow before it scrolls. Edit Mode's: the height set for the game's tracker in Edit Mode. The grip in its bottom-left corner sets it by dragging." },
		{ type = "slider", key = "width", name = "Width", min = 0, max = 600, step = 10,
		  format = function(v) v = math.floor(v + 0.5) return v == 0 and "Edit Mode's" or tostring(v) end,
		  desc = "How wide the tracker is. Edit Mode's: as wide as the game's tracker. The grip in its bottom-left corner sets width and height by dragging." },
		{ type = "slider", key = "scale", name = "Scale", min = 0.6, max = 1.6, step = 0.05, percent = true,
		  desc = "The size of the whole tracker, text and frame together." },
		{ type = "slider", key = "textSize", name = "Text Size", min = 10, max = 20, step = 1,
		  format = function(v) return tostring(math.floor(v + 0.5)) end,
		  desc = "The size of the quest titles and the section headers; the objectives are one size smaller." },
		{ type = "slider", key = "headerSize", name = "Header Text Size", min = 10, max = 24, step = 1,
		  format = function(v) return tostring(math.floor(v + 0.5)) end,
		  desc = "The size of the tracker's title, All Objectives (in the Fonts module's title face while the reskin is on, which draws it larger)." },
		{ type = "slider", key = "scrollStep", name = "Scroll Step", min = 10, max = 120, step = 5,
		  format = function(v) return tostring(math.floor(v + 0.5)) end,
		  desc = "How far one turn of the mouse wheel scrolls." },
		{ type = "toggle", key = "itemButtons", name = "Quest Items",
		  desc = "Show a quest's usable item beside it. A click uses it out of combat." },
		{ type = "button", name = "Reset Position", text = "Reset",
		  hint = "back on the game's tracker's place",
		  onClick = function(_, db)
			db.pos = nil
			MelloUI:NotifySettingChanged("QuestTracker", "pos", nil)
		  end },
	},
})

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

local function Plain(v)
	if Secret(v) or v == nil then
		return nil
	end
	return v
end

--------------------------------------------------------------------------------
-- Layout constants
--------------------------------------------------------------------------------

local HEADER_H = 28          -- the title plate
local INSET = 10             -- the frame's padding round the list
local THUMB_W = 8            -- the scroll thumb's width, and the room kept for it
-- the game's tracker's look (user, 2026-09-23: "format the text ... as the
-- default one"): a column for the quest's map button, the titles past it,
-- each objective's dash in a column of its own with the text hanging past it
local BLOCK_GAP = 10         -- between two quests
local LINE_GAP = 3           -- between an objective and the next
local TITLE_GAP = 4          -- between a title and its first line
local TEXT_X = 28            -- the titles' left edge, past the map button's column
local BULLET_X = 8           -- an objective's dash (and a turn-in line), from TEXT_X
local LINE_X = 20            -- an objective's text, from TEXT_X: past the dash
local ITEM_SIZE = 26         -- a quest item's button
local PIP_SIZE = 9           -- a difficulty pip on parchment (QuestInk)
local FALLBACK_W, FALLBACK_H = 260, 520

--------------------------------------------------------------------------------
-- The game's tracker: off while ours is on, back in Edit Mode
--------------------------------------------------------------------------------

local gameHidden = false
local savedAlpha = nil
local inEditMode = false
local pendingGame = nil      -- true / false: hide / show once the fight is over

local combatWatcher = CreateFrame("Frame")

local function SetGameTracker(hide)
	local f = ObjectiveTrackerFrame
	if not f or gameHidden == hide then
		return
	end
	if InCombatLockdown() then
		pendingGame = hide
		combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	pendingGame = nil
	if hide then
		savedAlpha = Plain(f:GetAlpha()) or 1
		f:SetAlpha(0)
		RegisterStateDriver(f, "visibility", "hide")
	else
		RegisterStateDriver(f, "visibility", "show")
		UnregisterStateDriver(f, "visibility")
		f:SetAlpha(savedAlpha or 1)
	end
	gameHidden = hide
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

local frame, header, clip, content, thumb, track
local scrollOffset = 0
local contentHeight = 0
local blocks = {}            -- [questID] = block, kept across rebuilds
local freeBlocks = {}
local dirty = false
local sizing = false          -- the grip is being dragged: no rebuild resizes the frame meanwhile
local lastProgress = {}       -- [questID or "r<recipe>"] = { [line] = count }: what each line last showed
local lastComplete = {}       -- [questID] = true once it was ready to turn in
local Scroll                  -- below

local function MaxHeight()
	local h = tonumber(M.db and M.db.maxHeight) or 0
	if h > 0 then
		return h
	end
	local f = ObjectiveTrackerFrame
	local ok, gh = pcall(function() return f and f:GetHeight() end)
	gh = ok and Plain(gh) or nil
	if gh and gh > HEADER_H * 2 then
		return gh
	end
	return FALLBACK_H
end

-- the tracker's OWN width: a set width, else what its two anchors on the
-- game's tracker give it (in its own units -- the game's tracker may be
-- scaled by the window mover, and its width is then not ours: the lines ran
-- past the list and were cut, user screenshot 2026-09-23)
local function FrameWidth()
	local set = tonumber(M.db and M.db.width) or 0
	if set > 0 then
		return set
	end
	local ok, w = pcall(function() return frame and frame:GetWidth() end)
	w = ok and Plain(w) or nil
	if w and w > 100 then
		return w
	end
	local f = ObjectiveTrackerFrame
	local okG, gw = pcall(function() return f and f:GetWidth() end)
	gw = okG and Plain(gw) or nil
	if gw and gw > 100 then
		return gw
	end
	return FALLBACK_W
end

local function ContentWidth()
	return FrameWidth() - INSET * 2 - THUMB_W - 4
end

-- the frame sits where the game's tracker is, as wide as it, from its top
local function Place()
	frame:ClearAllPoints()
	frame:SetScale(tonumber(M.db and M.db.scale) or 1)
	if MelloUI.Kit and MelloUI.Kit.RetileBackgrounds then
		MelloUI.Kit:RetileBackgrounds()   -- the UI's one background resolution, whatever the scale
	end
	local set = tonumber(M.db and M.db.width) or 0
	local f = ObjectiveTrackerFrame
	-- moved with Unlock the Windows: its own place, hung by its top-right
	-- corner so it still grows downward
	local pos = M.db and M.db.pos
	if pos and pos.x and pos.y then
		frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", pos.x, pos.y)
		if set > 0 then
			frame:SetWidth(set)
		else
			local ok, gw = pcall(function() return f and f:GetWidth() end)
			gw = ok and Plain(gw) or nil
			frame:SetWidth((gw and gw > 100) and gw or FALLBACK_W)
		end
		return
	end
	if f then
		-- the right edge stays on the game's tracker's (it sits by the
		-- screen's right side); a set width grows to the left
		frame:SetPoint("TOPRIGHT", f, "TOPRIGHT")
		if set > 0 then
			frame:SetWidth(set)
		else
			frame:SetPoint("TOPLEFT", f, "TOPLEFT")
		end
	else
		frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -80, -260)
		frame:SetWidth(set > 0 and set or FALLBACK_W)
	end
end

--------------------------------------------------------------------------------
-- Looks: the painted kit's, or a plain panel
--------------------------------------------------------------------------------

local looks = {}

local function KitCovers()
	local Kit = MelloUI.Kit
	return Kit and Kit.IsCovered and Kit:IsCovered("tracker")
end

local function BuildKitLook()
	if looks.kit ~= nil then
		return looks.kit
	end
	looks.kit = false
	local Kit = MelloUI.Kit
	if not (Kit and Kit.NineSlice) then
		return false
	end
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetAllPoints(frame)
	holder:SetFrameLevel(frame:GetFrameLevel())
	holder:EnableMouse(false)
	local ok, skin = pcall(Kit.NineSlice, Kit, holder, { prefix = Kit.framePrefix, gems = false,
		scale = (Kit.scale or 1) * (Kit.frameScale or 1) })
	if not ok then
		holder:Hide()
		return false
	end
	if skin and Kit.ParchmentSheet then
		Kit:ParchmentSheet(skin, holder, { area = "questTracker" })
	end
	-- the title plate across the top, as on the game's tracker
	local plateHolder = CreateFrame("Frame", nil, header)
	plateHolder:SetAllPoints(header)
	plateHolder:SetFrameLevel(header:GetFrameLevel())
	local okP, plate = pcall(Kit.Strip, Kit, plateHolder, "tabs/top", { state = "title", scale = Kit.scale })
	if okP and plate then
		plate:ClearAllPoints()
		plate:SetPoint("LEFT", plateHolder, "LEFT", -4, 0)
		plate:SetPoint("RIGHT", plateHolder, "RIGHT", 4, 0)
		if plate.FitHeight then
			pcall(plate.FitHeight, plate, HEADER_H + 10)
			if plate.height then
				plate:SetHeight(plate.height)
			end
		end
	end
	looks.kit = { holder = holder, plate = plateHolder, strip = okP and plate or nil }
	return looks.kit
end

local function BuildPlainLook()
	if looks.plain then
		return looks.plain
	end
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetAllPoints(frame)
	holder:SetFrameLevel(frame:GetFrameLevel())
	holder:EnableMouse(false)
	local bg = holder:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(holder)
	bg:SetColorTexture(0, 0, 0, 0.45)
	local line = holder:CreateTexture(nil, "BORDER")
	line:SetColorTexture(0.8, 0.65, 0.3, 0.8)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
	line:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -1)
	looks.plain = { holder = holder }
	return looks.plain
end

-- A collapse toggle on its plate's rail just short of the right gem
-- (user's sketch, 2026-09-23: the green marks left of the gems -- not on
-- them). The spot as a share of the right cap's canvas, measured on the art
-- (the gems' centres: 0.70 on the title cap, 0.87 on the header cap; the
-- caps carry no gem box); without the kit, at `rel`'s right edge by `x`.
local TITLE_GEM = { 0.47, 0.50 }     -- tabs/top_cap_r_title
local HEADER_GEM = { 0.61, 0.56 }    -- lists/header_cap_r
local function OnGem(toggle, strip, gem, rel, x)
	toggle:ClearAllPoints()
	local cap = strip and strip.capR
	local w, h = strip and strip.wr, strip and strip.height
	if cap and not strip.noR and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
		toggle:SetPoint("CENTER", cap, "TOPLEFT", w * gem[1], -h * gem[2])
	else
		toggle:SetPoint("RIGHT", rel, "RIGHT", x, 0)
	end
end

-- The text at the chosen size (user, 2026-09-23: "the text is too small" --
-- the game's small fonts, 12 and 10): the game's own typeface and flags, so
-- the Fonts module's face and outline still reach it
local function StyleText(fs, size)
	local object = GameFontNormal
	if not (object and object.GetFont and fs.SetFont) then
		return
	end
	local ok, path, _, flags = pcall(object.GetFont, object)
	if ok and path then
		pcall(fs.SetFont, fs, path, size, flags or "")
	end
end

local function TitleSize()
	return math.floor((tonumber(M.db and M.db.textSize) or 13) + 0.5)
end

-- All Objectives' size (user, 2026-09-23: it was the game font's large size,
-- fixed, and could not be changed in the configurator)
local function HeaderSize()
	return math.floor((tonumber(M.db and M.db.headerSize) or 16) + 0.5)
end

local function ApplyLook()
	local kitOn = KitCovers() and BuildKitLook()
	if kitOn then
		kitOn.holder:Show()
		kitOn.plate:Show()
		if looks.plain then
			looks.plain.holder:Hide()
		end
	else
		BuildPlainLook().holder:Show()
		if looks.kit then
			looks.kit.holder:Hide()
			looks.kit.plate:Hide()
		end
	end
	-- the title at Header Text Size: the base font first, then the title face
	-- over it (the face keeps the size it was given, as the section headers)
	local Kit = MelloUI.Kit
	if header then
		if Kit and Kit.TitleFont and header.text.melloFontSaved then
			pcall(Kit.TitleFont, Kit, header.text, false)
		end
		StyleText(header.text, HeaderSize())
		if kitOn and Kit and Kit.TitleFont then
			pcall(Kit.TitleFont, Kit, header.text, true)
		end
		-- on the plate's painted band, not its canvas: the band sits lower in
		-- the canvas, and the title rode high on it (user, 2026-09-23: "move
		-- this All Objectives Text to be in the Middle of the Red Background")
		local dy = 0
		local strip = kitOn and kitOn.strip
		local pieces = MelloUI_KitLayout and MelloUI_KitLayout.pieces
		if strip and pieces and Kit.StripPieceName then
			local mid = pieces[Kit:StripPieceName(strip.base, "mid", strip.state)]
			if mid and mid.box then
				dy = (mid.h / 2 - (mid.box[2] + mid.box[4]) / 2) * (strip.scale or Kit.scale or 1)
			end
		end
		header.text:ClearAllPoints()
		header.text:SetPoint("CENTER", header, "CENTER", 0, dy)
	end
	if header and header.toggle then
		OnGem(header.toggle, kitOn and kitOn.strip, TITLE_GEM, header, -4)
	end
end

--------------------------------------------------------------------------------
-- Quest items: one secure button, laid over the item under the mouse
--------------------------------------------------------------------------------

local itemOverlay

local function DetachOverlay()
	if itemOverlay and not InCombatLockdown() then
		itemOverlay:ClearAllPoints()
		itemOverlay:Hide()
		itemOverlay.over = nil
	end
end

local function AttachOverlay(button)
	if InCombatLockdown() or not button.itemLink then
		return
	end
	if not itemOverlay then
		itemOverlay = CreateFrame("Button", "MelloUIQuestTrackerItem", UIParent, "SecureActionButtonTemplate")
		itemOverlay:SetAttribute("type", "item")
		itemOverlay:RegisterForClicks("AnyUp", "AnyDown")
		itemOverlay:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
			if not self:IsMouseOver() then
				DetachOverlay()
			end
		end)
		itemOverlay:SetScript("OnEnter", function(self)
			if self.over and self.over.itemLink then
				GameTooltip:SetOwner(self, "ANCHOR_LEFT")
				pcall(GameTooltip.SetHyperlink, GameTooltip, self.over.itemLink)
				GameTooltip:Show()
			end
		end)
		itemOverlay:EnableMouseWheel(true)
		itemOverlay:SetScript("OnMouseWheel", function(_, delta)
			Scroll(delta)
		end)
	end
	itemOverlay:SetAttribute("item", button.itemLink)
	itemOverlay:SetFrameStrata(button:GetFrameStrata())
	itemOverlay:SetFrameLevel(button:GetFrameLevel() + 5)
	itemOverlay:ClearAllPoints()
	itemOverlay:SetAllPoints(button)
	itemOverlay.over = button
	itemOverlay:Show()
end

-- a fight is starting: the secure button leaves the list while it still can
-- (PLAYER_REGEN_DISABLED comes before the lockdown), so nothing secure hangs
-- on the list while it scrolls in combat
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatcher:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_REGEN_DISABLED" then
		DetachOverlay()
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		if pendingGame ~= nil then
			SetGameTracker(pendingGame)
		end
	end
end)

--------------------------------------------------------------------------------
-- A quest's block: its title, its objectives, its item
--------------------------------------------------------------------------------

local function OpenRecipe(recipeID)
	-- next frame, out of this click's execution
	C_Timer.After(0, function()
		if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
			pcall(C_TradeSkillUI.OpenRecipe, recipeID)
		end
	end)
end

local function OnBlockClick(block, button)
	if block.recipeID then
		if IsShiftKeyDown() and button ~= "RightButton" then
			if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then
				pcall(C_TradeSkillUI.SetRecipeTracked, block.recipeID, false, block.recraft and true or false)
			end
		else
			OpenRecipe(block.recipeID)
		end
		return
	end
	local id = block.questID
	if not id then
		return
	end
	if button == "RightButton" then
		-- next frame, out of this click's (MelloUI's) execution
		C_Timer.After(0, function()
			if QuestMapFrame_OpenToQuestDetails then
				pcall(QuestMapFrame_OpenToQuestDetails, id)
			end
		end)
	elseif IsShiftKeyDown() then
		if C_QuestLog and C_QuestLog.RemoveQuestWatch then
			pcall(C_QuestLog.RemoveQuestWatch, id)
		end
	elseif C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
		local current = C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
		local want = (Plain(current) == id) and 0 or id
		if securecallfunction then
			securecallfunction(C_SuperTrack.SetSuperTrackedQuestID, want)
		else
			pcall(C_SuperTrack.SetSuperTrackedQuestID, want)
		end
	end
end

local function OnBlockEnter(block)
	if block.recipeID then
		GameTooltip:SetOwner(block, "ANCHOR_LEFT")
		local link
		if C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink then
			local ok, l = pcall(C_TradeSkillUI.GetRecipeLink, block.recipeID)
			link = ok and Plain(l) or nil
		end
		if not (link and pcall(GameTooltip.SetHyperlink, GameTooltip, link)) then
			GameTooltip:SetText(block.title:GetText() or "")
		end
		GameTooltip:AddLine("Click: open the recipe  -  Shift-click: stop tracking", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
		if block.highlight then
			block.highlight:Show()
		end
		return
	end
	if not block.questID then
		return
	end
	GameTooltip:SetOwner(block, "ANCHOR_LEFT")
	if not pcall(GameTooltip.SetHyperlink, GameTooltip, "quest:" .. block.questID) then
		GameTooltip:SetText(block.title:GetText() or "")
	end
	GameTooltip:AddLine("Click: follow  -  Shift-click: stop watching  -  Right-click: quest log", 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
	if block.highlight then
		block.highlight:Show()
	end
end

local function OnBlockLeave(block)
	GameTooltip:Hide()
	if block.highlight then
		block.highlight:Hide()
	end
end

local function NewBlock()
	local block = table.remove(freeBlocks)
	if block then
		return block
	end
	block = CreateFrame("Button", nil, content)
	block:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	block:SetScript("OnClick", OnBlockClick)
	block:SetScript("OnEnter", OnBlockEnter)
	block:SetScript("OnLeave", OnBlockLeave)
	block:EnableMouseWheel(true)
	block:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
	block.highlight = block:CreateTexture(nil, "BACKGROUND")
	block.highlight:SetAllPoints(block)
	block.highlight:SetColorTexture(1, 0.85, 0.4, 0.08)
	block.highlight:Hide()
	block.followed = block:CreateTexture(nil, "ARTWORK")
	block.followed:SetSize(10, 10)
	local Kit = MelloUI.Kit
	if not (Kit and Kit.Apply and Kit:Apply(block.followed, "deco/gem_small")) then
		block.followed:SetColorTexture(1, 0.8, 0.2, 1)
	end
	-- the quest's map button, the game's own (POIButtonTemplate, as on the
	-- game's tracker: "..." in progress, "?" ready to turn in, lit while
	-- followed). Its click is the block's (follow / stop following), never
	-- the template's own, so no MelloUI value runs through the game's code.
	-- A client without the template keeps the small gem for the followed one.
	local okP, poi = pcall(CreateFrame, "Button", nil, block, "POIButtonTemplate")
	if okP and poi and poi.SetQuestID then
		poi:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		poi:SetScript("OnClick", function(_, button) OnBlockClick(block, button) end)
		poi:SetScript("OnEnter", function() OnBlockEnter(block) end)
		poi:SetScript("OnLeave", function() OnBlockLeave(block) end)
		poi:EnableMouseWheel(true)
		poi:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
		poi:Hide()
		block.poi = poi
	elseif okP and poi then
		poi:Hide()
	end
	block.title = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	block.title:SetJustifyH("LEFT")
	block.title:SetWordWrap(true)
	block.lines = {}
	local item = CreateFrame("Button", nil, block)
	item:SetSize(ITEM_SIZE, ITEM_SIZE)
	item.icon = item:CreateTexture(nil, "ARTWORK")
	item.icon:SetAllPoints(item)
	item.border = item:CreateTexture(nil, "OVERLAY")
	item.border:SetPoint("TOPLEFT", -2, 2)
	item.border:SetPoint("BOTTOMRIGHT", 2, -2)
	if not (Kit and Kit.Apply and Kit:Apply(item.border, "buttons/slot_normal")) then
		item.border:SetColorTexture(0, 0, 0, 0)
	end
	item.cooldown = CreateFrame("Cooldown", nil, item, "CooldownFrameTemplate")
	item.cooldown:SetAllPoints(item)
	item:SetScript("OnEnter", function(self)
		AttachOverlay(self)
		if InCombatLockdown() then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			pcall(GameTooltip.SetHyperlink, GameTooltip, self.itemLink)
			GameTooltip:AddLine("Out of combat, a click uses it.", 0.7, 0.7, 0.7, true)
			GameTooltip:Show()
		end
	end)
	item:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	item:EnableMouseWheel(true)
	item:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
	block.item = item
	return block
end

local function ReleaseBlock(block)
	block:Hide()
	block:ClearAllPoints()
	block.questID, block.recipeID, block.recraft = nil, nil, nil
	if itemOverlay and itemOverlay.over == block.item then
		DetachOverlay()
	end
	freeBlocks[#freeBlocks + 1] = block
end

-- On the parchment sheet the text is dark ink and a quest's difficulty is
-- in pips beside its title (QuestInk; user, 2026-09-23)
local function Inked()
	local Kit = MelloUI.Kit
	return MelloUI.QuestInk ~= nil and KitCovers() and Kit and Kit.ParchmentOn and Kit:ParchmentOn("questTracker") or false
end

-- A line's colour on parchment: done or greyed lines faded, the rest ink
local function InkLine(fs, ink, r)
	local QI = MelloUI.QuestInk
	if not QI then
		return
	end
	if ink then
		QI.Ink(fs, (r and r < 0.8) and "faded" or "text")
	else
		QI.Plain(fs)
	end
end

local function Line(block, i)
	local fs = block.lines[i]
	if not fs then
		fs = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
		fs.dash = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs.dash:SetText("-")
		-- a gold glow behind the line when it counts up (user, 2026-09-23:
		-- the study's progress flash), at rest fully clear
		fs.flash = block:CreateTexture(nil, "BACKGROUND", nil, 1)
		fs.flash:SetColorTexture(1, 0.82, 0.3, 1)
		fs.flash:SetAlpha(0)
		block.lines[i] = fs
	end
	StyleText(fs, TitleSize() - 1)
	StyleText(fs.dash, TitleSize() - 1)
	return fs
end

-- Line i under a title at y: with `dash`, the dash in its column and the
-- text hanging past it (a wrapped line starts under the text, as on the
-- game's tracker); else the text from the dash's column. Returns the next y.
local function PutLine(block, i, text, y, width, dash, r, g, b)
	local fs = Line(block, i)
	local x = TEXT_X + (dash and LINE_X or BULLET_X)
	fs:SetText(text)
	fs:SetTextColor(r, g, b)
	InkLine(fs, block.ink, r)
	InkLine(fs.dash, block.ink, r)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", block, "TOPLEFT", x, -y)
	fs:SetWidth(width - x)
	fs:Show()
	if dash then
		fs.dash:ClearAllPoints()
		fs.dash:SetPoint("TOPLEFT", block, "TOPLEFT", TEXT_X + BULLET_X, -y)
		fs.dash:SetTextColor(r, g, b)
		fs.dash:Show()
	else
		fs.dash:Hide()
	end
	local h = fs:GetStringHeight()
	fs.flash:ClearAllPoints()
	fs.flash:SetPoint("TOPLEFT", block, "TOPLEFT", TEXT_X + BULLET_X - 4, -y + 1)
	fs.flash:SetPoint("RIGHT", block, "RIGHT", 0, 0)
	fs.flash:SetHeight(h + 2)
	return y + h + LINE_GAP, fs
end

-- A line counted up since the last rebuild: its glow flares and fades.
-- `key` / `i` name the line across rebuilds; the first sight of it never
-- flashes (a quest just watched, a login). Reduce Motion: no flash at all.
local function Progress(key, i, count, fs)
	local seen = lastProgress[key]
	if not seen then
		seen = {}
		lastProgress[key] = seen
	end
	local before = seen[i]
	seen[i] = count
	if before and count and count > before and fs and MelloUI.Anim then
		MelloUI.Anim:From(fs.flash, "alpha", 0.45, 0.9, "outQuad")
	end
end

local function HideLines(block, from)
	for i = from, #block.lines do
		block.lines[i]:Hide()
		block.lines[i].dash:Hide()
		if MelloUI.Anim then
			MelloUI.Anim:Stop(block.lines[i].flash, "alpha")
		end
		block.lines[i].flash:SetAlpha(0)
	end
end

local function DifficultyColor(level)
	if level and GetQuestDifficultyColor then
		local ok, c = pcall(GetQuestDifficultyColor, level)
		if ok and c and c.r then
			return c.r, c.g, c.b
		end
	end
	return 1, 0.82, 0
end

-- Fill a block from the quest log; returns its height.
local function FillBlock(block, questID, width, followedID)
	local logIndex = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
	local info = logIndex and C_QuestLog.GetInfo and C_QuestLog.GetInfo(logIndex)
	local title = (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)) or (info and info.title) or ("Quest " .. questID)
	local level = info and Plain(info.level)
	local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
	block.questID, block.recipeID, block.recraft = questID, nil, nil

	-- the item first: the text keeps clear of it
	local textWidth = width
	local item = block.item
	local link, icon
	if M.db.itemButtons and logIndex and GetQuestLogSpecialItemInfo then
		local ok, l, tex = pcall(GetQuestLogSpecialItemInfo, logIndex)
		if ok then
			link, icon = Plain(l), Plain(tex)
		end
		-- a finished quest keeps its item only when the game says so
		if complete then
			local okS, _, _, _, showWhenComplete = pcall(GetQuestLogSpecialItemInfo, logIndex)
			if not (okS and showWhenComplete) then
				link, icon = nil, nil
			end
		end
	end
	if link and icon then
		item.itemLink = link
		item.icon:SetTexture(icon)
		item:ClearAllPoints()
		item:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, -2)
		item:Show()
		if GetQuestLogSpecialItemCooldown then
			local ok, start, duration, enable = pcall(GetQuestLogSpecialItemCooldown, logIndex)
			if ok and Plain(start) and Plain(duration) then
				pcall(item.cooldown.SetCooldown, item.cooldown, start, duration, enable)
			end
		end
		textWidth = width - ITEM_SIZE - 6
	else
		item.itemLink = nil
		item:Hide()
	end

	local followed = followedID == questID
	local poi = block.poi
	if poi then
		-- the game's style for the quest (its own pick where it has one)
		local util = POIButtonUtil
		local style = util and util.Style and (complete and util.Style.QuestComplete or util.Style.QuestInProgress)
		if util and util.GetStyle then
			local okG, st = pcall(util.GetStyle, questID)
			if okG and st ~= nil and not Secret(st) then
				style = st
			end
		end
		pcall(poi.SetQuestID, poi, questID)
		if style ~= nil and poi.SetStyle then
			pcall(poi.SetStyle, poi, style)
		end
		if poi.SetSelected then
			pcall(poi.SetSelected, poi, followed)
		end
		if poi.UpdateButtonStyle then
			pcall(poi.UpdateButtonStyle, poi)
		end
		-- centred on the title's first line
		poi:ClearAllPoints()
		poi:SetPoint("CENTER", block, "TOPLEFT", TEXT_X / 2 - 1, -TitleSize() / 2 - 1)
		poi:Show()
	end
	block.followed:SetShown(followed and not poi)
	block.followed:ClearAllPoints()
	block.followed:SetPoint("CENTER", block, "TOPLEFT", TEXT_X / 2 - 1, -TitleSize() / 2 - 1)

	local t = block.title
	StyleText(t, TitleSize())
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", block, "TOPLEFT", TEXT_X, 0)
	-- on parchment: the title in ink, the difficulty in pips at the right of
	-- its first line (left of the item); else the game's difficulty colour
	local QI = MelloUI.QuestInk
	local ink = Inked()
	block.ink = ink
	local tier = ink and QI.TierForQuest(questID, level) or nil
	local pipsRoom = 0
	if tier then
		block.pips = block.pips or QI.Pips(block, PIP_SIZE)
		block.pips:ClearAllPoints()
		block.pips:SetPoint("RIGHT", block, "TOPLEFT", textWidth, -TitleSize() / 2 - 1)
		block.pips:SetTier(tier)
		pipsRoom = QI.PipsWidth(PIP_SIZE) + 6
	elseif block.pips then
		block.pips:SetTier(nil)
	end
	t:SetWidth(textWidth - TEXT_X - pipsRoom)
	t:SetText(level and string.format("[%d] %s", level, title) or title)
	t:SetTextColor(DifficultyColor(level))
	if ink then
		QI.Ink(t, tier == 1 and "faded" or "title")
	elseif QI then
		QI.Plain(t)
	end
	local y = t:GetStringHeight() + TITLE_GAP

	local n = 0
	local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID) or {}
	if complete then
		-- what to do now, white under the title (the game's turn-in line)
		n = n + 1
		local text = logIndex and GetQuestLogCompletionText and GetQuestLogCompletionText(logIndex)
		local fs
		y, fs = PutLine(block, n, Plain(text) or "Ready for turn-in", y, textWidth, false, 0.95, 0.95, 0.95)
		if lastComplete[questID] == false and MelloUI.Anim then
			MelloUI.Anim:From(fs.flash, "alpha", 0.45, 0.9, "outQuad")
		end
		lastComplete[questID] = true
	else
		lastComplete[questID] = false
		for i, obj in ipairs(objectives) do
			local text = Plain(obj.text)
			if text and text ~= "" then
				n = n + 1
				local shade = obj.finished and 0.55 or 0.95
				local fs
				y, fs = PutLine(block, n, text, y, textWidth, true, shade, shade, shade)
				Progress(questID, i, Plain(obj.numFulfilled), fs)
			end
		end
	end
	HideLines(block, n + 1)
	local h = math.max(y, link and ITEM_SIZE + 4 or 0, poi and 22 or 0)
	block:SetHeight(h)
	block:Show()
	return h
end

--------------------------------------------------------------------------------
-- Scrolling
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Moving it: by its header while the windows are unlocked, through UI
-- Modifications' mover (MelloUI:RegisterMover, where the frame is built)
--------------------------------------------------------------------------------

-- where it was dropped, as offsets of its top-right corner from the screen's
-- top-right, in its own units (it hangs from that corner, growing downward)
local function SavePosition()
	local fs = frame:GetEffectiveScale()
	local us = UIParent:GetEffectiveScale()
	local right, top = frame:GetRight(), frame:GetTop()
	if not (right and top and fs and fs > 0) then
		return
	end
	M.db.pos = {
		x = (right * fs - UIParent:GetRight() * us) / fs,
		y = (top * fs - UIParent:GetTop() * us) / fs,
	}
end

local function ClipHeight()
	local ok, h = pcall(clip.GetHeight, clip)
	h = ok and Plain(h) or 0
	return h
end

local function MaxScroll()
	return math.max(0, contentHeight - ClipHeight())
end

local function UpdateThumb()
	local visible = ClipHeight()
	if contentHeight <= visible + 0.5 or visible <= 0 then
		thumb:Hide()
		track:Hide()
		return
	end
	track:Show()
	thumb:Show()
	local h = math.max(18, visible * visible / contentHeight)
	local travel = visible - h
	local y = travel * (scrollOffset / MaxScroll())
	thumb:ClearAllPoints()
	thumb:SetPoint("TOPRIGHT", clip, "TOPRIGHT", THUMB_W + 3, -y)
	thumb:SetHeight(h)
end

local function SetOffset(offset)
	scrollOffset = math.max(0, math.min(offset, MaxScroll()))
	content:ClearAllPoints()
	content:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, scrollOffset)
	content:SetWidth(ContentWidth())
	UpdateThumb()
	if itemOverlay and itemOverlay.over and not InCombatLockdown() then
		-- the item the secure button lies over moved with the list
		if not itemOverlay.over:IsMouseOver() then
			DetachOverlay()
		end
	end
end

Scroll = function(delta)
	local step = tonumber(M.db and M.db.scrollStep) or 25
	SetOffset(scrollOffset - delta * step)
end

--------------------------------------------------------------------------------
-- Rebuild
--------------------------------------------------------------------------------

-- The recipes tracked in the professions window, the recrafts after them
-- (user, 2026-09-23: "when i track a recipe it does not show the
-- Professions category like the default one does").
local function TrackedRecipes()
	local list = {}
	local ui = C_TradeSkillUI
	if not (ui and ui.GetRecipesTracked) then
		return list
	end
	for _, recraft in ipairs({ false, true }) do
		local ok, ids = pcall(ui.GetRecipesTracked, recraft)
		if ok and type(ids) == "table" then
			for _, id in ipairs(ids) do
				id = Plain(id)
				if id then
					list[#list + 1] = { id = id, recraft = recraft }
				end
			end
		end
	end
	return list
end

local function ReagentCount(itemID)
	if C_Item and C_Item.GetItemCount then
		local ok, n = pcall(C_Item.GetItemCount, itemID, true, false, true, true)
		n = ok and Plain(n) or nil
		if n then
			return n
		end
	end
	if GetItemCount then
		local ok, n = pcall(GetItemCount, itemID, true)
		return ok and Plain(n) or 0
	end
	return 0
end

local function ItemName(itemID)
	if C_Item and C_Item.GetItemNameByID then
		local ok, name = pcall(C_Item.GetItemNameByID, itemID)
		if ok and Plain(name) then
			return name
		end
	end
	local ok, name = pcall(GetItemInfo, itemID)
	return ok and Plain(name) or ("item " .. itemID)
end

-- A tracked recipe: its name, and each basic reagent as have / need, grey
-- once there are enough (the game's tracker's Professions lines)
local function FillRecipeBlock(block, entry, width)
	block.questID, block.recipeID, block.recraft = nil, entry.id, entry.recraft
	block.item.itemLink = nil
	block.item:Hide()
	block.followed:Hide()
	if block.poi then
		block.poi:Hide()
	end
	local ui = C_TradeSkillUI
	local name
	if ui.GetRecipeInfo then
		local ok, info = pcall(ui.GetRecipeInfo, entry.id)
		name = ok and info and Plain(info.name) or nil
	end
	local okS, schematic = false, nil
	if ui.GetRecipeSchematic then
		okS, schematic = pcall(ui.GetRecipeSchematic, entry.id, entry.recraft and true or false)
	end
	if not name and okS and schematic then
		name = Plain(schematic.name)
	end
	local t = block.title
	StyleText(t, TitleSize())
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", block, "TOPLEFT", TEXT_X, 0)
	t:SetWidth(width - TEXT_X)
	t:SetText((name or ("Recipe " .. entry.id)) .. (entry.recraft and " (recraft)" or ""))
	t:SetTextColor(1, 0.82, 0)
	-- a recipe on parchment: its name in ink, no pips (no difficulty)
	block.ink = Inked()
	if block.pips then
		block.pips:SetTier(nil)
	end
	InkLine(t, block.ink, 1)
	if block.ink and MelloUI.QuestInk then
		MelloUI.QuestInk.Ink(t, "title")
	end
	local y = t:GetStringHeight() + TITLE_GAP
	local n = 0
	local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
	if okS and schematic and type(schematic.reagentSlotSchematics) == "table" then
		for _, slot in ipairs(schematic.reagentSlotSchematics) do
			local reagent = slot.reagents and slot.reagents[1]
			local itemID = reagent and Plain(reagent.itemID)
			local need = Plain(slot.quantityRequired) or 1
			if itemID and (basic == nil or slot.reagentType == basic) and slot.required ~= false then
				n = n + 1
				local have = ReagentCount(itemID)
				local shade = have >= need and 0.55 or 0.95
				local fs
				y, fs = PutLine(block, n, string.format("%d/%d %s", math.min(have, need), need, ItemName(itemID)), y, width, true, shade, shade, shade)
				Progress("r" .. entry.id .. (entry.recraft and "/1" or "/0"), n, math.min(have, need), fs)
			end
		end
	end
	HideLines(block, n + 1)
	block:SetHeight(y)
	block:Show()
	return y
end

-- A section's header in the list ("Quests", "Professions"): the kit's list
-- header band under the name while the reskin covers the tracker, a thin
-- gold line otherwise
local SECTION_H = 24
local sections = {}

-- A collapse toggle, the kit's minus / plus (the game's without the kit):
-- `IsCollapsed()` picks the icon, `OnClick` flips the state
local function MakeToggle(parent, size, IsCollapsed, OnClick)
	local toggle = CreateFrame("Button", nil, parent)
	toggle:SetSize(size, size)
	toggle.icon = toggle:CreateTexture(nil, "ARTWORK")
	toggle.icon:SetAllPoints(toggle)
	function toggle.Refresh()
		local Kit = MelloUI.Kit
		local collapsed = IsCollapsed()
		local piece = collapsed and "buttons/plus_normal" or "buttons/minus_normal"
		if not (Kit and Kit.Apply and Kit:Apply(toggle.icon, piece)) then
			toggle.icon:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
		end
	end
	toggle:SetScript("OnClick", OnClick)
	toggle.Refresh()
	return toggle
end

-- A section folded away (user, 2026-09-23: Quests and Professions each with
-- a minus like All Objectives'), kept per section key
local function SectionCollapsed(key)
	local c = M.db and M.db.collapsedSections
	return type(c) == "table" and c[key] == true
end

local function Section(key, label)
	local row = sections[key]
	if not row then
		row = CreateFrame("Frame", nil, content)
		row:SetHeight(SECTION_H)
		row:EnableMouse(false)
		local Kit = MelloUI.Kit
		if Kit and Kit.Strip then
			local ok, plate = pcall(Kit.Strip, Kit, row, "lists/header", { scale = Kit.scale })
			if ok and plate then
				local yoff = 0
				if plate.FitBox then
					local okF, off = pcall(plate.FitBox, plate, SECTION_H)
					yoff = okF and tonumber(off) or 0
				end
				plate:ClearAllPoints()
				plate:SetPoint("LEFT", row, "LEFT", 0, yoff)
				plate:SetPoint("RIGHT", row, "RIGHT", 0, yoff)
				if plate.height then
					plate:SetHeight(plate.height)
				end
				row.plate = plate
			end
		end
		row.line = row:CreateTexture(nil, "ARTWORK")
		row.line:SetColorTexture(0.8, 0.65, 0.3, 0.8)
		row.line:SetHeight(1)
		row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
		row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 1)
		-- the name above the band (a child frame draws over its parent's regions)
		local layer = CreateFrame("Frame", nil, row)
		layer:SetAllPoints(row)
		layer:SetFrameLevel(row:GetFrameLevel() + 6)
		-- centred as All Objectives is (user, 2026-09-23)
		row.text = layer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.text:SetPoint("CENTER", row, "CENTER", 0, 0)
		row.toggle = MakeToggle(layer, 14, function() return SectionCollapsed(key) end, function()
			local c = type(M.db.collapsedSections) == "table" and M.db.collapsedSections or {}
			M.db.collapsedSections = c
			c[key] = not c[key] or nil
			MelloUI:NotifySettingChanged(M.name, "collapsedSections", c)
		end)
		sections[key] = row
	end
	local kit = KitCovers() and row.plate
	if row.plate then
		row.plate:SetShown(kit and true or false)
	end
	row.line:SetShown(not kit)
	-- the header font (Fonts' title face) while the reskin covers the
	-- tracker, as on All Objectives: the base font first (the face keeps
	-- the size it was given, so a Text Size change must reach it)
	local Kit = MelloUI.Kit
	if Kit and Kit.TitleFont and row.text.melloFontSaved then
		pcall(Kit.TitleFont, Kit, row.text, false)
	end
	StyleText(row.text, TitleSize())
	if kit and Kit and Kit.TitleFont then
		pcall(Kit.TitleFont, Kit, row.text, true)
	end
	row.toggle.Refresh()
	OnGem(row.toggle, kit and row.plate, HEADER_GEM, row, -6)
	row.text:SetText(label)
	row.text:SetTextColor(1, 0.82, 0)
	return row
end

local function WatchedQuests()
	local list = {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex) then
		return list
	end
	local ok, n = pcall(C_QuestLog.GetNumQuestWatches)
	n = ok and Plain(n) or 0
	for i = 1, n do
		local okI, id = pcall(C_QuestLog.GetQuestIDForQuestWatchIndex, i)
		id = okI and Plain(id) or nil
		if id and id > 0 then
			list[#list + 1] = id
		end
	end
	return list
end

local function Rebuild()
	if sizing then
		return   -- stays dirty: the rebuild follows the release
	end
	dirty = false
	if not (frame and M.isEnabled) then
		return
	end
	-- scrolled to the end: the view follows the list's end when it grows
	local wasMax = MaxScroll()
	local atEnd = wasMax > 0 and scrollOffset >= wasMax - 1
	local width = ContentWidth()
	local followedID
	if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
		local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
		followedID = ok and Plain(id) or nil
	end
	local quests = WatchedQuests()
	local recipes = TrackedRecipes()
	-- a block per quest (keyed by its ID) and per recipe ("r<id>/<recraft>"),
	-- the same block for the same entry across rebuilds
	local function RecipeKey(entry)
		return "r" .. entry.id .. (entry.recraft and "/1" or "/0")
	end
	-- a folded section keeps its header only: its blocks are let go
	local questsOpen = not SectionCollapsed("quests")
	local recipesOpen = not SectionCollapsed("professions")
	local keep = {}
	for _, id in ipairs(quests) do
		keep[id] = questsOpen or nil
	end
	for _, entry in ipairs(recipes) do
		keep[RecipeKey(entry)] = recipesOpen or nil
	end
	for key, block in pairs(blocks) do
		if not keep[key] then
			ReleaseBlock(block)
			blocks[key] = nil
		end
	end
	for _, row in pairs(sections) do
		row:Hide()
	end
	local y = 0
	local function Head(key, label)
		local row = Section(key, label)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		row:SetWidth(width)
		row:Show()
		y = y + SECTION_H + 4
	end
	local function Put(key, fill, ...)
		local block = blocks[key] or NewBlock()
		blocks[key] = block
		block:ClearAllPoints()
		block:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		block:SetWidth(width)
		local ok, h = pcall(fill, block, ...)
		if not ok then
			h = 0
			block:Hide()
		end
		y = y + h + BLOCK_GAP
	end
	if #quests > 0 then
		Head("quests", QUESTS_LABEL or "Quests")
		for _, id in ipairs(questsOpen and quests or {}) do
			Put(id, FillBlock, id, width, followedID)
		end
	end
	if #recipes > 0 then
		if #quests > 0 then
			y = y + 2
		end
		Head("professions", TRADE_SKILLS or "Professions")
		for _, entry in ipairs(recipesOpen and recipes or {}) do
			Put(RecipeKey(entry), FillRecipeBlock, entry, width)
		end
	end
	contentHeight = math.max(0, y - BLOCK_GAP)
	content:SetHeight(math.max(1, contentHeight))
	local entries = #quests + #recipes

	-- the frame's height: the header and the list, up to the height allowed
	local collapsed = M.db.collapsed
	clip:SetShown(not collapsed)
	local listH = collapsed and 0 or math.min(contentHeight, MaxHeight() - HEADER_H - INSET * 2)
	local total = HEADER_H + (collapsed and 6 or (INSET + listH + INSET))
	frame:SetHeight(math.max(HEADER_H + 6, total))
	-- nothing watched: nothing shown, as the game's tracker; in Edit Mode the
	-- game's own is out to be moved, and this one waits
	frame:SetShown(entries > 0 and not inEditMode)
	-- the view stays where it was (clamped to the new length), or at the
	-- end when it was there
	SetOffset(atEnd and math.huge or scrollOffset)
end

-- One rebuild a frame at most, whatever number of events came. Driven from
-- the event frame (always shown), not the tracker: a tracker hidden because
-- nothing is watched must still wake up when a quest is watched.
local eventFrame = CreateFrame("Frame")

local function Tick(self)
	self:SetScript("OnUpdate", nil)
	if dirty then
		Rebuild()
	end
end

local function MarkDirty()
	dirty = true
	eventFrame:SetScript("OnUpdate", Tick)
end

--------------------------------------------------------------------------------
-- Building the frame
--------------------------------------------------------------------------------

local function Build()
	if frame then
		return
	end
	frame = CreateFrame("Frame", "MelloUIQuestTracker", UIParent)
	frame:SetFrameStrata("LOW")
	frame:SetClampedToScreen(true)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
	Place()

	header = CreateFrame("Button", nil, frame)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	header:SetHeight(HEADER_H)
	header:SetFrameLevel(frame:GetFrameLevel() + 4)
	-- the title and the toggle on a layer ABOVE the title plate: the plate is
	-- a child frame of the header, which would draw over the header's own
	-- regions (the title was hidden behind it)
	local textLayer = CreateFrame("Frame", nil, header)
	textLayer:SetAllPoints(header)
	textLayer:SetFrameLevel(header:GetFrameLevel() + 8)
	header.text = textLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	header.text:SetPoint("CENTER", header, "CENTER", 0, 0)
	header.text:SetText(TRACKER_ALL_OBJECTIVES or "All Objectives")
	-- the collapse toggle, the kit's minus / plus, on the title plate's
	-- right gem (placed by ApplyLook)
	local toggle = MakeToggle(textLayer, 16, function() return M.db.collapsed end, function()
		M.db.collapsed = not M.db.collapsed
		MelloUI:NotifySettingChanged(M.name, "collapsed", M.db.collapsed)
	end)
	toggle:SetPoint("RIGHT", header, "RIGHT", -4, 0)
	header.toggle, header.ToggleIcon = toggle, toggle.Refresh

	-- moved like every other window while the windows are unlocked (UI
	-- Modifications' mover: the screen darkens with its grid, the border
	-- lights, the corner snaps, the wheel scales it -- user, 2026-09-23: "does
	-- not have the same darkening ... also the mousewheel does not increase
	-- its scale"); it keeps its own place, hung by its top-right corner, and
	-- the wheel's scale is its Scale setting
	if MelloUI.RegisterMover then
		MelloUI:RegisterMover(frame, header, {
			min = 0.6, max = 1.6,   -- the Scale slider's range
			save = function()
				SavePosition()
				M.db.scale = math.floor(frame:GetScale() * 100 + 0.5) / 100
				Place()
				MelloUI:NotifySettingChanged(M.name, "pos", M.db.pos)
				MelloUI:NotifySettingChanged(M.name, "scale", M.db.scale)
			end,
			reset = function()
				M.db.pos, M.db.scale = nil, 1
				Place()
				MelloUI:NotifySettingChanged(M.name, "pos", nil)
				MelloUI:NotifySettingChanged(M.name, "scale", 1)
			end,
		})
	end

	clip = CreateFrame("Frame", nil, frame)
	clip:SetPoint("TOPLEFT", header, "BOTTOMLEFT", INSET, -INSET + 4)
	clip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(INSET + THUMB_W + 4), INSET)
	clip:SetClipsChildren(true)
	clip:EnableMouseWheel(true)
	clip:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
	clip:SetScript("OnSizeChanged", function() SetOffset(scrollOffset) end)

	-- the resize grip, bottom-left (the tracker hangs from its top-right
	-- corner): dragging sets its width and the height it may grow to
	-- (user, 2026-09-23: "the quest window should have the option to be
	-- rescaled")
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(180, HEADER_H + 60, 700, 1200)
	end
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 3, 3)
	grip:SetFrameLevel(frame:GetFrameLevel() + 10)
	local gripTex = grip:CreateTexture(nil, "OVERLAY")
	gripTex:SetAllPoints(grip)
	gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	gripTex:SetTexCoord(1, 0, 0, 1)   -- mirrored: it points to the bottom-left
	grip:SetAlpha(0.35)
	grip:SetScript("OnEnter", function(self)
		self:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Drag to size the tracker")
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function(self)
		self:SetAlpha(0.35)
		GameTooltip:Hide()
	end)
	grip:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then
			return
		end
		sizing = true
		frame:StartSizing("BOTTOMLEFT")
	end)
	grip:SetScript("OnMouseUp", function()
		if not sizing then
			return
		end
		sizing = false
		frame:StopMovingOrSizing()
		local w, h = frame:GetWidth(), frame:GetHeight()
		M.db.width = math.floor(w + 0.5)
		M.db.maxHeight = math.floor(h + 0.5)
		MelloUI:NotifySettingChanged(M.name, "width", M.db.width)
		MelloUI:NotifySettingChanged(M.name, "maxHeight", M.db.maxHeight)
	end)
	frame.grip = grip
	content = CreateFrame("Frame", nil, clip)
	content:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
	content:SetSize(ContentWidth(), 1)

	-- the scroll thumb: the kit's, or a plain bar, beside the list
	track = frame:CreateTexture(nil, "ARTWORK")
	track:SetColorTexture(0, 0, 0, 0.35)
	track:SetWidth(3)
	track:SetPoint("TOP", clip, "TOPRIGHT", THUMB_W / 2 + 3, 0)
	track:SetPoint("BOTTOM", clip, "BOTTOMRIGHT", THUMB_W / 2 + 3, 0)
	local Kit = MelloUI.Kit
	local okT, vstrip = false, nil
	if Kit and Kit.VStrip then
		okT, vstrip = pcall(Kit.VStrip, Kit, frame, "lists/scrollthumb", { state = "normal", scale = Kit.scale })
	end
	if okT and vstrip then
		thumb = vstrip
		thumb:SetWidth(THUMB_W + 2)
	else
		thumb = CreateFrame("Frame", nil, frame)
		thumb:SetWidth(THUMB_W - 2)
		local t = thumb:CreateTexture(nil, "ARTWORK")
		t:SetAllPoints(thumb)
		t:SetColorTexture(0.85, 0.7, 0.35, 0.8)
	end
	thumb:SetFrameLevel(frame:GetFrameLevel() + 6)
	thumb:Hide()
	track:Hide()

	ApplyLook()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local EVENTS = {
	"QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_ACCEPTED",
	"QUEST_REMOVED", "QUEST_TURNED_IN", "SUPER_TRACKING_CHANGED", "PLAYER_ENTERING_WORLD",
	"ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_COOLDOWN",
	-- the professions section: a recipe tracked or untracked, reagents gained
	"TRACKED_RECIPE_UPDATE", "BAG_UPDATE_DELAYED",
}

eventFrame:SetScript("OnEvent", function(_, event, unit)
	if event == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then
		return
	end
	MarkDirty()
end)

-- Edit Mode: the game's tracker comes back to be moved and sized; ours
-- steps aside, then takes the new place and height
local editHooked = false
local function HookEditMode()
	if editHooked or not (EventRegistry and EventRegistry.RegisterCallback) then
		return
	end
	editHooked = true
	EventRegistry:RegisterCallback("EditMode.Enter", function()
		inEditMode = true
		if M.isEnabled then
			SetGameTracker(false)
			if frame then
				frame:Hide()
			end
		end
	end, M)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		inEditMode = false
		if M.isEnabled then
			SetGameTracker(true)
			if frame then
				Place()
				MarkDirty()
			end
		end
	end, M)
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	Build()
	HookEditMode()
	for _, event in ipairs(EVENTS) do
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
	pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_QUEST_LOG_CHANGED", "player")
	if not inEditMode then
		SetGameTracker(true)
	end
	ApplyLook()
	frame:Show()
	-- the parchment sheet switched on or off: ink or colour again
	local Kit = MelloUI.Kit
	if Kit and Kit.SetParchment and not M.parchmentHooked then
		M.parchmentHooked = true
		hooksecurefunc(Kit, "SetParchment", function(_, area)
			if area == "questTracker" and M.isEnabled then
				MarkDirty()
			end
		end)
	end
	MarkDirty()
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	DetachOverlay()
	if frame then
		frame:Hide()
	end
	SetGameTracker(false)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if frame and not sizing then
		Place()   -- width, scale; and back on the game's tracker after a drag
	end
	if header and header.ToggleIcon then
		header.ToggleIcon()
	end
	ApplyLook()
	MarkDirty()
end

MelloUI:Profile("QuestTracker", "tracker rebuild", Rebuild)
