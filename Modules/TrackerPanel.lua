--------------------------------------------------------------------------------
-- MelloUI - Tracker Panel
--
-- The objective tracker (ObjectiveTrackerFrame and its modules: quests,
-- campaign, achievements, scenarios, bonus / world quests, recipes …)
-- dressed in the painted kit (Modules/Kit.lua) on the game's own layout.
-- User's pick (kit_raw/minimap_catalog.png, 2026-09-21): T2. The rule
-- book's fixed looks for the rest:
--   T2  the tracker's header band → the title plate (as the band's regions,
--       under its text); a module's header band → the header plate
--   the collapse / expand glyphs → the kit's minus / plus, switched with
--   the atlas the game puts there; the filter button on the cog
--   the tracker's backdrop → the single rail with stone on the game's
--   NineSlice rect, at Edit Mode's opacity, retracting to the header while
--   the tracker is collapsed; its stone under the palette's inner panel
--   while the tracker's parchment is off (the eye strain rule, 2026-09-24)
--   quest item buttons → R1 rims (Kit:SkinActionButton); progress bars → P1
-- Blocks, item buttons and bars are pooled per module: swept after the
-- container's updates (once a frame, while it can be seen). Block hover is
-- a text colour: nothing to replace.
-- Covers the Dark Mode group "tracker". /trdump [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("TrackerPanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("TrackerPanel", {
	title = "Objective Tracker Kit",
	desc = "The objective tracker dressed in the painted kit on the game's own layout.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil
local active = false

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Tracker: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- A collapse / expand button: the minus / plus following the atlas the game
-- sets on its normal texture (SetCollapsed re-atlases it).
local function SkinToggle(button)
	if not (button and button.GetNormalTexture and button:GetNormalTexture()) or button.melloToggle then
		return
	end
	button.melloToggle = true
	local normal = button:GetNormalTexture()
	local extra = { button:GetPushedTexture(), button:GetHighlightTexture() }
	Kit:StateIconReps(button, normal, button, Replace, extra)
	hooksecurefunc(normal, "SetAtlas", function()
		if active then
			Kit:StateIconReps(button, normal, button, Replace, extra)
		end
	end)
end

-- The header's text centred on its plate (user, 2026-09-21), the game's
-- anchor put back on disable.
local function CenterText(header, rep)
	local fs = header.Text
	if not (fs and rep) then
		return
	end
	local saved = { justify = fs:GetJustifyH() }
	for i = 1, fs:GetNumPoints() do
		saved[i] = { fs:GetPoint(i) }
	end
	local function Place()
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", header, "CENTER", 0, 0)
		fs:SetJustifyH("CENTER")
		Kit:TitleFont(fs, true)
	end
	local enable, disable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if enable then
			enable(...)
		end
		Place()
	end
	rep.onDisable = function(...)
		if disable then
			disable(...)
		end
		Kit:TitleFont(fs, false)
		fs:ClearAllPoints()
		for _, pt in ipairs(saved) do
			if type(pt) == "table" then
				fs:SetPoint(unpack(pt))
			end
		end
		fs:SetJustifyH(saved.justify or "LEFT")
	end
	if active then
		Place()
	end
end

-- The gem's share of a plate's right cap (measured on the pieces): the
-- minimize button moves left past it, onto the cap's plate part (user,
-- 2026-09-21: the button sat on the gem)
local GEM_SHARE = { ["tabs/top"] = 0.57, ["lists/header"] = 0.23 }

local function MoveToggle(header, rep)
	local button = header.MinimizeButton
	if not (button and rep and rep.strip) then
		return
	end
	local saved = {}
	for i = 1, button:GetNumPoints() do
		saved[i] = { button:GetPoint(i) }
	end
	local function Place()
		local share = GEM_SHARE[rep.strip.base] or 0
		local offset = (rep.strip.wr or 0) * share
		button:ClearAllPoints()
		button:SetPoint("RIGHT", header, "RIGHT", -offset, 0)
	end
	local enable, disable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if enable then
			enable(...)
		end
		Place()
	end
	rep.onDisable = function(...)
		if disable then
			disable(...)
		end
		button:ClearAllPoints()
		for _, pt in ipairs(saved) do
			button:SetPoint(unpack(pt))
		end
	end
	if active then
		Place()
	end
end

-- A module header's AddAnim fades its Background in (an Alpha animation,
-- setToFinalAlpha) on the C side, past the fade's SetAlpha hook: the game's
-- band came back over the plate's middle (user, 2026-09-21). That one
-- animation is retargeted to 0 -> 0 while the kit is on; the glow, shine
-- and button parts of the animation stay.
local function SilenceAddAnim(header, rep)
	local group = header.AddAnim
	if not (group and group.GetAnimations) then
		return
	end
	local alphas = {}
	for _, anim in ipairs({ group:GetAnimations() }) do
		if anim.GetTarget and anim.SetToAlpha and anim:GetTarget() == header.Background then
			alphas[#alphas + 1] = { anim = anim, from = anim:GetFromAlpha(), to = anim:GetToAlpha() }
		end
	end
	if #alphas == 0 then
		return
	end
	local function Silence()
		for _, entry in ipairs(alphas) do
			entry.anim:SetFromAlpha(0)
			entry.anim:SetToAlpha(0)
		end
	end
	local enable, disable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if enable then
			enable(...)
		end
		Silence()
	end
	rep.onDisable = function(...)
		if disable then
			disable(...)
		end
		for _, entry in ipairs(alphas) do
			entry.anim:SetFromAlpha(entry.from)
			entry.anim:SetToAlpha(entry.to)
		end
	end
	Perf.HookScript(group, "OnFinished", function()
		if active then
			header.Background:SetAlpha(0)
		end
	end)
	if active then
		Silence()
	end
end

local function SkinHeader(header, key)
	if not (header and header.Background) or header.melloRep ~= nil then
		return
	end
	header.melloRep = Replace(header.Background, { as = key, rect = header }) or false
	if header.melloRep then
		CenterText(header, header.melloRep)
		MoveToggle(header, header.melloRep)
		SilenceAddAnim(header, header.melloRep)
	end
	SkinToggle(header.MinimizeButton)
	local filter = header.FilterButton
	if filter and filter.GetNormalTexture and filter:GetNormalTexture() and filter.melloRep == nil then
		filter.melloRep = Replace(filter:GetNormalTexture(), { as = "ui-questtrackerbutton-filter", button = filter, noFade = true }) or false
	end
end

-- The modules' right-edge frames (quest item buttons, progress bars), pooled
-- and re-used: swept after every update.
local function SkinRightEdge(frame)
	if frame.icon and frame.NormalTexture then
		if frame.melloRep == nil then
			local ok, w = pcall(frame.GetWidth, frame)
			Kit:SkinActionButton(frame, Replace, ok and w and w > 0 and { w, w } or nil, { emptyStone = false })
		end
	elseif frame.Bar and frame.Bar.BorderMid and frame.Bar.melloRep == nil then
		local bar = frame.Bar
		local layer, sublevel, troughLayer, troughSub = Kit:BracketLayers(bar)
		bar.melloRep = Replace(bar.BorderMid, { as = "UI-Character-Skills-BarBorder", parent = bar, rect = bar,
			layer = layer, sublevel = sublevel, troughLayer = troughLayer, troughSub = troughSub,
			alsoFade = { bar.BorderLeft, bar.BorderRight } }) or false
	end
end

-- A header's title in the kit's title font, left alone when it already
-- shows that font and the same text (the 2026-09-24 review: every tracker
-- update set the font again on each module's header). [fontString] = the
-- face, size, flags and text it showed once dressed; a font object the game
-- changes (the tracker's text size) or a new header text dresses it again.
local dressed = setmetatable({}, { __mode = "k" })

local function Readback(fs)
	local ok, path, size, flags = pcall(fs.GetFont, fs)
	local okT, text = pcall(fs.GetText, fs)
	if not (ok and okT) or Secret(path) or Secret(size) or Secret(text) then
		return nil
	end
	return path, size, flags, text
end

local function DressTitle(fs)
	local was = dressed[fs]
	if was then
		local path, size, flags, text = Readback(fs)
		if path ~= nil and path == was[1] and size == was[2] and flags == was[3] and text == was[4] then
			return
		end
	end
	Kit:TitleFont(fs, true)
	-- kept only when the face took: one the client has not read yet (Kit
	-- puts the game's back and counts a try) is tried again next sweep, as
	-- every sweep always did
	local path, size, flags, text
	if not fs.melloFontTries then
		path, size, flags, text = Readback(fs)
	end
	if path ~= nil then
		if was then
			was[1], was[2], was[3], was[4] = path, size, flags, text
		else
			dressed[fs] = { path, size, flags, text }
		end
	else
		dressed[fs] = nil
	end
end

local function Sweep()
	local tracker = ObjectiveTrackerFrame
	if not (active and tracker) then
		return
	end
	if tracker.Header and tracker.Header.Text then
		DressTitle(tracker.Header.Text)
	end
	for _, module in ipairs(tracker.modules or {}) do
		SkinHeader(module.Header, "UI-QuestTracker-Secondary-Objective-Header")
		if module.Header and module.Header.Text and module.Header.melloRep then
			DressTitle(module.Header.Text)
		end
		for _, frame in pairs(module.usedRightEdgeFrames or {}) do
			SkinRightEdge(frame)
		end
	end
end

-- After the game's tracker updates: swept once a frame, only while the
-- tracker can be seen (the 2026-09-24 review: it ran after every update,
-- also while MelloUI's Quest Tracker keeps the game's hidden). The first
-- update of a frame sweeps at once (nothing is seen undressed); more in the
-- same frame ask for one sweep on the next. One not seen is swept when the
-- tracker is seen again (its OnShow: Edit Mode, the UI shown; its alpha
-- back: Quest Tracker off or in Edit Mode).
local sweptAt = nil
local sweepPending = false
local sweepStale = false

-- Seen: shown, and not at alpha 0. MelloUI's Quest Tracker hides the game's
-- with SetAlpha(0) and a hide state driver, and the game's Update ends in
-- Show() whenever it has content (ObjectiveTrackerContainerMixin:Update):
-- right after an update the tracker IS shown, at alpha 0, until the
-- driver's next tick hides it, so a test of shown alone still swept after
-- every update (the 2026-09-24 review, checked again). Nothing in the game
-- sets the tracker's own alpha; a secret one counts as seen.
local function Seen(tracker)
	if not tracker:IsVisible() then
		return false
	end
	local alpha = tracker:GetAlpha()
	return Secret(alpha) or not alpha or alpha > 0
end

local function SweepQueued()
	Kit:WhenOutOfCombat(Sweep, Sweep)
end

local function SweepNextFrame()
	sweepPending = false
	if active then
		SweepQueued()
	end
end

local function AfterTrackerUpdate()
	if not active then
		return
	end
	local tracker = ObjectiveTrackerFrame
	if not Seen(tracker) then
		sweepStale = true
		return
	end
	local now = GetTime()
	if sweptAt ~= now then
		sweptAt = now
		SweepQueued()
	elseif not sweepPending then
		sweepPending = true
		C_Timer.After(0, SweepNextFrame)
	end
end

-- its OnShow and its SetAlpha: the sweep it missed, once it is seen (the
-- game's Update shows a tracker Quest Tracker keeps at alpha 0: not yet)
local function OnTrackerShown()
	if active and sweepStale and Seen(ObjectiveTrackerFrame) then
		sweepStale = false
		sweptAt = GetTime()
		SweepQueued()
	end
end

local function Build()
	if skin then
		return
	end
	skin = { reps = {} }
	local tracker = ObjectiveTrackerFrame
	if not tracker then
		return
	end
	SkinHeader(tracker.Header, "ui-questtracker-primary-objective-header")
	-- the backdrop with its border (user, 2026-09-21): on the game's NineSlice
	-- rect (the whole tracker, sized by the game) but as the TRACKER's child
	-- at its own level, under the headers and blocks — the game's NineSlice
	-- carries Edit Mode's opacity (0 by default) and would hide it
	if tracker.NineSlice then
		-- the game's own opacity box (the NineSlice's pieces) faded — its
		-- frame keeps its alpha, which is the opacity we follow
		local pieces = {}
		for _, region in ipairs({ tracker.NineSlice:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not region.kitPiece then
				pieces[#pieces + 1] = region
			end
		end
		local rep = Replace(tracker.NineSlice, { as = "ObjectiveTrackerBackground", parent = tracker, rect = tracker.NineSlice, level = 0, noFade = true, alsoFade = pieces })
		if rep and tracker.Header and tracker.Header.melloRep and Kit.RegisterShell then
			-- the header is the tracker's drag handle for the window mover
			Kit:RegisterShell(tracker, { title = tracker.Header.melloRep, outer = rep })
		end
		if rep then
			-- its alpha follows Edit Mode's opacity setting (the game sets it on
			-- the NineSlice: SetBackgroundAlpha), and it retracts to the header
			-- while the tracker is collapsed (the game leaves the NineSlice's
			-- bottom on the last module then) — user, 2026-09-21
			local holder = rep.object
			-- a parchment sheet on the stone, inside the rails, ending in the
			-- kit's dry-brush strokes (user, 2026-09-23: "leave the background
			-- how it was and the borders, but add the parchment layer on top
			-- of that and mask it")
			if rep.skin and Kit.ParchmentSheet then
				Kit:ParchmentSheet(rep.skin, holder, { area = "tracker" })
			end
			local function Opacity()
				local ok, alpha = pcall(tracker.NineSlice.GetAlpha, tracker.NineSlice)
				holder:SetAlpha(ok and alpha or 1)
			end
			-- sideways the backdrop is CENTRED on the header plate (user,
			-- 2026-09-21: the game's opacity box sits further out on the
			-- left than on the right): the same margin past the header's
			-- ends on both sides, the margin being the game's own on the
			-- right; top and bottom stay the NineSlice's
			local function Margin()
				local header = tracker.Header
				local ok, hr = pcall(header.GetRight, header)
				local okN, nr = pcall(tracker.NineSlice.GetRight, tracker.NineSlice)
				if ok and okN and hr and nr and not Secret(hr) and not Secret(nr) and nr - hr > 0 and nr - hr < 40 then
					return nr - hr
				end
				return 8
			end
			-- ... and 15 % wider than that, still centred (user, 2026-09-21)
			local WIDEN = 0.15
			local function Extent()
				local header = tracker.Header
				local m = header and Margin() or 0
				if header then
					local okW, hw = pcall(header.GetWidth, header)
					if okW and hw and not Secret(hw) and hw > 0 then
						m = m + hw * WIDEN / 2
					end
				end
				holder:ClearAllPoints()
				holder:SetPoint("TOP", tracker.NineSlice, "TOP")
				if header then
					holder:SetPoint("LEFT", header, "LEFT", -m, 0)
					holder:SetPoint("RIGHT", header, "RIGHT", m, 0)
				else
					holder:SetPoint("LEFT", tracker.NineSlice, "LEFT")
					holder:SetPoint("RIGHT", tracker.NineSlice, "RIGHT")
				end
				if tracker.IsCollapsed and tracker:IsCollapsed() and header then
					holder:SetPoint("BOTTOM", tracker.NineSlice, "TOP", 0, -(header:GetHeight() + 4))
				else
					holder:SetPoint("BOTTOM", tracker.NineSlice, "BOTTOM")
				end
			end
			if tracker.SetBackgroundAlpha then
				hooksecurefunc(tracker, "SetBackgroundAlpha", Opacity)
			end
			if tracker.SetCollapsed then
				hooksecurefunc(tracker, "SetCollapsed", Extent)
			end
			-- no eye strain (user, 2026-09-24: "too much small text over a
			-- plain brown border is just an eye strain" / "apply the eye
			-- strain rule to all existing windows"; WINDOW-RULES 2e): the
			-- tracker is a column of quest text, so on the stone look (its
			-- parchment off) the stone inside the rails lies under the
			-- palette's inner panel, a region of the box's skin between the
			-- stone and the sheet, following the opacity with the holder.
			-- It takes the place of the black shade that was darkest down
			-- the middle (user, 2026-09-22): under the panel the shade only
			-- blackened the middle further, and it left the sides brown.
			if not holder.melloShade and rep.skin and Kit.StoneDim then
				holder.melloShade = Kit:StoneDim(rep.skin, { area = "tracker" })
			end
			rep.onEnable = function()
				Opacity()
				Extent()
			end
			if active then
				rep.onEnable()
			end
		end
	end
	if tracker.Update then
		hooksecurefunc(tracker, "Update", AfterTrackerUpdate)
		Perf.HookScript(tracker, "OnShow", OnTrackerShown)
		hooksecurefunc(tracker, "SetAlpha", OnTrackerShown)
	end
	Sweep()
end

-- The game's tracker on its parchment sheet: the quest headers and objective
-- lines in ink (QuestInk's rule, user 2026-09-23); its title and the module
-- headers stay on their plates, the bars and item buttons as they are
local function InkSurface()
	local QI = MelloUI.QuestInk
	if not QI then
		return
	end
	if not QI.surfaces.tracker then
		QI.Surface("tracker", {
			roots = function()
				local tracker = _G.ObjectiveTrackerFrame
				if tracker then
					if tracker.Header then
						tracker.Header.melloNoInk = true
					end
					for _, module in ipairs(tracker.modules or {}) do
						if module.Header then
							module.Header.melloNoInk = true
						end
					end
				end
				return tracker
			end,
			on = function()
				return active and Kit:ParchmentOn("tracker")
			end,
		})
	else
		QI.RefreshSurface("tracker")
	end
end

local function Activate()
	if active then
		return
	end
	active = true
	Build()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	Sweep()
	Kit:Cover("tracker")
	InkSurface()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	Kit:Uncover("tracker")
	if MelloUI.QuestInk and MelloUI.QuestInk.surfaces.tracker then
		MelloUI.QuestInk.RefreshSurface("tracker")
	end
end

function M:OnEnable(db)
	self.db = db
	if ObjectiveTrackerFrame then
		Activate()
	end
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /trdump [frames|reps]: the tracker's art. Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOTRDUMP1 = "/trdump"
SlashCmdList.MELLOTRDUMP = function(msg)
	msg = (msg or ""):lower()
	MelloUI:ClearLog()
	if not ObjectiveTrackerFrame then
		MelloUI:Print("No objective tracker.")
	else
		MelloUI:Print("== ObjectiveTrackerFrame  %s L%d; modules: %d", ObjectiveTrackerFrame:GetFrameStrata(), ObjectiveTrackerFrame:GetFrameLevel(),
			ObjectiveTrackerFrame.modules and #ObjectiveTrackerFrame.modules or 0)
		Kit:DumpWindow(ObjectiveTrackerFrame, skin, msg ~= "" and msg or nil)
	end
	MelloUI:ShowLog("trdump " .. msg)
end
