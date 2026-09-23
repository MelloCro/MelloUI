--------------------------------------------------------------------------------
-- MelloUI - Action Bar Panel
--
-- The action bars (main bar, the multi bars, stance / pet / possess bars),
-- the micro menu, the bag bar and the experience / reputation / honour bars
-- dressed in the painted kit (Modules/Kit.lua) on the game's own layout.
-- The rule book's fixed looks and the user's picks (kit_raw/actionbar_catalog.png,
-- 2026-09-21: X2 M1, "no custom icons on the micro bar"):
--   R1  every action-style button: the slot rim on its NormalTexture, sized
--       to the bar's pitch so neighbours share a gem, the icon filling the
--       opening, empty slots on stone, the equipped border tinting the rim
--       green; the bar's own frame art lies under the rims and is faded
--   X2  the main bar's gryphon end caps → the rail's orb caps at their height
--   M1  a micro button's plate → the cog plate, the game's glyph on it
--   P1  the status bars' frame → the bracket with the caps outside the bar,
--       the fill behind it on the whole width
-- Bars are re-laid by Edit Mode (UpdateGridLayout): the rims re-size to the
-- new pitch from that post-hook, out of combat. Covers the Dark Mode groups
-- "actionbars", "micromenu", "bagbar" and "statusbars". /abdump [bar|micro|
-- bags|xp] [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("ActionBarPanel", {
	title = "Action Bars Kit",
	desc = "The action bars, micro menu, bag bar and experience bars dressed in the painted kit on the game's own layout.",
	enabledByDefault = true,
	defaults = {
		hidePageArrows = true,
	},
	options = {
		{ type = "toggle", key = "hidePageArrows", name = "Hide Page Arrows",
		  desc = "Hide the main bar's page number and its up / down arrows (the bar still pages with the keybinds)." },
	},
})

local skin = nil
local active = false
local hooked = false

local BAR_NAMES = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
	"MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar" }
local BAG_BUTTONS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
	"CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Action bars: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

--------------------------------------------------------------------------------
-- Action bars
--------------------------------------------------------------------------------

-- The bar's button pitch { x, y }: the first button's size plus the bar's
-- padding (Edit Mode's), secret-safe.
local function BarPitch(bar, button)
	local ok, w, h = pcall(button.GetSize, button)
	if not ok or Secret(w) or Secret(h) or not (w and w > 0 and h and h > 0) then
		return nil
	end
	local pad = tonumber(bar.buttonPadding) or 0
	if Secret(pad) then
		pad = 0
	end
	return { w + pad, h + pad }
end

local function BarButtons(bar)
	if type(bar.actionButtons) == "table" and #bar.actionButtons > 0 then
		return bar.actionButtons
	end
	local list = {}
	local prefix = bar:GetName()
	prefix = prefix and prefix:gsub("ActionBar$", "") or ""
	for i = 1, 12 do
		local button = _G[prefix .. "Button" .. i]
		if button then
			list[#list + 1] = button
		end
	end
	return list
end

local function RefitBar(bar)
	local entry = skin.bars[bar]
	if not (active and entry) then
		return
	end
	local first = entry.buttons[1]
	local pitch = first and BarPitch(bar, first)
	if pitch then
		for _, button in ipairs(entry.buttons) do
			local rep = button.melloRep
			if rep and rep.SetPitch then
				rep:SetPitch(pitch[1], pitch[2])
			end
		end
	end
end

local function SkinBar(bar)
	if not bar or skin.bars[bar] then
		return
	end
	local buttons = BarButtons(bar)
	if #buttons == 0 then
		return
	end
	skin.bars[bar] = { buttons = buttons }
	local pitch = BarPitch(bar, buttons[1])
	for _, button in ipairs(buttons) do
		Kit:SkinActionButton(button, Replace, pitch)
	end
	if bar.UpdateGridLayout then
		hooksecurefunc(bar, "UpdateGridLayout", function()
			Kit:WhenOutOfCombat(function() RefitBar(bar) end)
		end)
	end
	-- the bar's own art (the main bar's frame, the gryphons, the page arrows,
	-- the pooled dividers between its buttons)
	if bar.BorderArt then
		Replace(bar.BorderArt, { as = "UI-HUD-ActionBar-Frame" })
	end
	local function FadeDividers()
		for _, key in ipairs({ "HorizontalDividersPool", "VerticalDividersPool" }) do
			local pool = bar[key]
			if pool then
				for divider in pool:EnumerateActive() do
					if divider.melloRep == nil then
						divider.melloRep = true
						for _, region in ipairs({ divider:GetRegions() }) do
							if region:GetObjectType() == "Texture" then
								Replace(region, { as = Kit:ArtKey(region) })
							end
						end
					end
				end
			end
		end
	end
	if bar.UpdateDividers then
		hooksecurefunc(bar, "UpdateDividers", function()
			if active then
				Kit:WhenOutOfCombat(FadeDividers)
			end
		end)
	end
	FadeDividers()
	-- the end caps: on holders at the BACKGROUND strata (under every bar and
	-- the status bars, whatever their strata and level — user, 2026-09-21:
	-- the caps behind all the bars), following the caps' rects and the
	-- EndCaps frame's show / hide (Edit Mode's 'hide bar art')
	if bar.EndCaps then
		local caps = bar.EndCaps
		local reps = {}   -- { rep, cap }
		local left, right = caps.LeftEndCap, caps.RightEndCap
		if left and left.Texture then
			local rep = Replace(left.Texture, { as = "ui-hud-actionbar-gryphon-left", parent = bar, level = 0, strata = "BACKGROUND" })
			if rep then
				reps[#reps + 1] = { rep = rep, cap = left }
			end
		end
		if right and right.Texture then
			local rep = Replace(right.Texture, { as = "ui-hud-actionbar-gryphon-right", parent = bar, level = 0, strata = "BACKGROUND" })
			if rep then
				reps[#reps + 1] = { rep = rep, cap = right }
			end
		end
		-- each orb shows only while its gryphon would: the EndCaps frame, the
		-- cap frame itself AND its texture (player report, 2026-09-23: "the
		-- new gryphons Icons dont want to Hide in edit mode" -- Edit Mode's
		-- Hide Bar Art did not only hide the EndCaps frame, so the orbs,
		-- which followed that frame alone, stayed)
		local function Wanted(cap)
			if not caps:IsShown() then
				return false
			end
			if cap.IsShown and not cap:IsShown() then
				return false
			end
			if cap.Texture and cap.Texture.IsShown and not cap.Texture:IsShown() then
				return false
			end
			return true
		end
		local function Sync()
			if active then
				for _, entry in ipairs(reps) do
					entry.rep:SetShown(Wanted(entry.cap))
				end
			end
		end
		local function Watch(obj)
			if obj then
				for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
					if type(obj[method]) == "function" then
						hooksecurefunc(obj, method, Sync)
					end
				end
			end
		end
		Watch(caps)
		for _, entry in ipairs(reps) do
			Watch(entry.cap)
			Watch(entry.cap.Texture)
		end
		-- the bar's own updates of its art (Edit Mode's setting applied)
		for _, method in ipairs({ "UpdateEndCaps", "UpdateSystemSettingHideBarArt" }) do
			if type(bar[method]) == "function" then
				hooksecurefunc(bar, method, Sync)
			end
		end
		skin.capSync[#skin.capSync + 1] = Sync
	end
	local page = bar.ActionBarPageNumber
	if page then
		skin.page = page
		for key, art in pairs({ UpButton = "ui-hud-actionbar-pageuparrow-up", DownButton = "ui-hud-actionbar-pagedownarrow-up" }) do
			local button = page[key]
			if button and button.GetNormalTexture and button:GetNormalTexture() then
				Replace(button:GetNormalTexture(), { as = art, button = button,
					alsoFade = { button:GetPushedTexture(), button:GetHighlightTexture(), button:GetDisabledTexture() } })
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Micro menu (M1: the cog plate under the game's own glyphs), bag bar (R1)
--------------------------------------------------------------------------------

local function SkinMicroMenu()
	local menu = MicroMenu
	if not menu or skin.micro then
		return
	end
	skin.micro = true
	if menu.BorderArt then
		Replace(menu.BorderArt, { as = "UI-HUD-ActionBar-Frame" })
	end
	if menu.BackgroundArt then
		Replace(menu.BackgroundArt, { as = "MicroMenuBackgroundArt" })
	end
	-- every button in a SQUARE slot rim at the bar's PITCH (the distance
	-- between neighbouring buttons: the game's plates overlap, 32 px wide
	-- buttons 27 px apart), so neighbours share one gem (user, 2026-09-22:
	-- "the gems overlap one another to not show duplicates"); the game's
	-- glyph fitted inside
	local shown = {}
	for _, button in ipairs({ menu:GetChildren() }) do
		if button.Background and button:IsShown() then
			local okL, left = pcall(button.GetLeft, button)
			if okL and left and not Secret(left) then
				shown[#shown + 1] = left
			end
		end
	end
	table.sort(shown)
	local spacing = nil
	for i = 2, #shown do
		local d = shown[i] - shown[i - 1]
		if d > 1 and (not spacing or d < spacing) then
			spacing = d   -- the smallest gap between neighbours: the pitch
		end
	end
	for _, button in ipairs({ menu:GetChildren() }) do
		if button.Background and button.melloRep == nil then
			local ok, w = pcall(button.GetSize, button)
			local step = spacing or ((ok and not Secret(w) and w and w > 0) and w or nil)
			local pitch = step and { step, step } or nil
			-- the glyph (the normal texture) fitted into the rim's opening the
			-- way an action button's icon is (user, 2026-09-22: "they don't
			-- fit"); its other states and the character button's portrait
			-- follow it
			local glyph = button.GetNormalTexture and button:GetNormalTexture() or nil
			-- the character button has no atlas glyph: its portrait is the
			-- icon fitted into the opening (user, 2026-09-22: the stone for
			-- it too)
			local isPortrait = false
			if not glyph and button.Portrait then
				glyph, isPortrait = button.Portrait, true
			end
			-- the character button's portrait shadow art (atlas-sized, centred)
			-- would show outside the rim: faded with the plate
			local rep = Replace(button.Background, { as = "UI-HUD-MicroMenu-ButtonBG-Up", button = button, rect = button,
				pitch = pitch, icon = glyph, alsoFade = { button.PushedBackground, button.Shadow, button.PushedShadow } })
			button.melloRep = rep or false
			if rep and glyph then
				local others = {}
				for _, tex in ipairs({ button.GetPushedTexture and button:GetPushedTexture(), button.GetHighlightTexture and button:GetHighlightTexture(),
					button.GetDisabledTexture and button:GetDisabledTexture(), (not isPortrait) and button.Portrait or nil }) do
					if tex and tex ~= glyph then
						others[#others + 1] = tex
					end
				end
				local function Follow()
					for _, tex in ipairs(others) do
						tex:ClearAllPoints()
						tex:SetAllPoints(glyph)
					end
				end
				Follow()
				-- the character button re-anchors its portrait on press and
				-- release (CharacterMicroButtonMixin:SetPushed / SetNormal):
				-- back onto the glyph after each
				for _, m in ipairs({ "SetPushed", "SetNormal" }) do
					if type(button[m]) == "function" then
						hooksecurefunc(button, m, function()
							if active and rep.object and rep.object:IsShown() then
								if isPortrait then
									Kit:SlotPlaceIcon(rep.object)   -- the game just re-anchored the portrait
								end
								Follow()
							end
						end)
					end
				end
				-- setting a button's state texture anchors it to fill the
				-- button again, and the game sets the glyph atlas after load
				-- (LoadMicroButtonTextures: the spellbook button on its
				-- update, the guild one on a tabard change; the game menu
				-- one on every net-stats tick): the glyph back into the rim's
				-- opening after each (user, 2026-09-22: "they still don't fit")
				local function Refit()
					if not (active and rep.object and rep.object:IsShown()) then
						return
					end
					local current = button:GetNormalTexture()
					if current and current ~= glyph then
						glyph = current   -- a new texture object: the rim follows it
						rep.object.icon = current
					end
					Kit:SlotPlaceIcon(rep.object)
					Follow()
					if button.melloStone then
						button.melloStone:ClearAllPoints()
						button.melloStone:SetAllPoints(glyph)   -- the stone stays on the (possibly new) glyph
					end
				end
				for _, m in ipairs({ "SetNormalAtlas", "SetNormalTexture", "SetPushedAtlas", "SetHighlightAtlas", "SetDisabledAtlas" }) do
					if type(button[m]) == "function" then
						hooksecurefunc(button, m, Refit)
					end
				end
				button.melloRefitGlyph = Refit
				-- the stone in the rim's opening under the glyph, as an empty
				-- action slot has it (user, 2026-09-22: "a background to those
				-- icons"); a region of the button under the ARTWORK glyph, on
				-- the glyph's rect (the opening), shown and hidden with the rim
				local stone = button:CreateTexture(nil, "BACKGROUND", nil, 1)
				stone.kitScale = Kit.scale
				Kit:Apply(stone, "tiles/stone")
				stone:SetAllPoints(glyph)
				Kit:Retile(stone)
				stone:SetShown(rep.object:IsShown())
				local enable1, disable1 = rep.onEnable, rep.onDisable
				rep.onEnable = function(...)
					if enable1 then
						enable1(...)
					end
					stone:Show()
					Kit:Retile(stone)
				end
				rep.onDisable = function(...)
					if disable1 then
						disable1(...)
					end
					stone:Hide()
				end
				if Kit.RegisterTexture then
					Kit:RegisterTexture(stone)   -- Dark Mode's shade
				end
				button.melloStone = stone
				local enable0 = rep.onEnable
				rep.onEnable = function(...)
					if enable0 then
						enable0(...)   -- the glyph into the opening
					end
					Follow()   -- the game may have re-anchored the portrait while the skin was off
				end
				local disable0 = rep.onDisable
				rep.onDisable = function(...)
					if disable0 then
						disable0(...)
					end
					-- the game's anchors: the state textures fill the button,
					-- the portrait sits 7 px in (its XML)
					for _, tex in ipairs(others) do
						tex:ClearAllPoints()
						if tex == button.Portrait then
							tex:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -7)
							tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -7, 7)
						else
							tex:SetAllPoints(button)
						end
					end
					if isPortrait then
						-- (the slot's own onDisable put the icon's saved points
						-- back; the game's 7 px inset is what those were)
						glyph:ClearAllPoints()
						glyph:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -7)
						glyph:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -7, 7)
					end
				end
			end
		end
	end
end

local function SkinBagBar()
	local bar = BagsBar
	if not bar or skin.bags then
		return
	end
	skin.bags = true
	if bar.BorderArt then
		Replace(bar.BorderArt, { as = "UI-HUD-ActionBar-Frame" })
	end
	for _, name in ipairs(BAG_BUTTONS) do
		local button = _G[name]
		if button and button.icon and button.GetNormalTexture then
			local ok, w, h = pcall(button.GetSize, button)
			local pitch = (ok and not Secret(w) and w and w > 0) and { w, h } or nil
			Kit:SkinActionButton(button, Replace, pitch)
		end
	end
end

--------------------------------------------------------------------------------
-- Status bars (P1 on each container's frame; the shown bar's fill behind it)
--------------------------------------------------------------------------------

local function SkinStatusContainer(container)
	if not (container and container.BarFrameTexture) or skin.status[container] then
		return
	end
	skin.status[container] = true
	-- the fill is a LOW-strata status bar under the MEDIUM container: the
	-- bracket as the container's OVERLAY regions (over the fill, as the
	-- game's hollow frame art was), the trough on a holder at LOW one level
	-- under the status bar
	local shown = container.GetShownBar and container:GetShownBar()
	local fill = shown and shown.StatusBar
	if not fill then
		for _, bar in pairs(container.bars or {}) do
			fill = fill or bar.StatusBar
		end
	end
	local under = CreateFrame("Frame", nil, container)
	under:EnableMouse(false)
	under:SetAllPoints(container)
	under:SetFrameStrata(fill and fill:GetFrameStrata() or "LOW")
	under:SetFrameLevel(math.max((fill and fill:GetFrameLevel() or 1) - 1, 0))
	local rep = Replace(container.BarFrameTexture, { as = "UI-HUD-ExperienceBar-Frame", parent = container, rect = container,
		layer = "OVERLAY", sublevel = 1, troughParent = under, troughLayer = "ARTWORK", troughSub = 0 })
	local textures = MelloUI:GetModule("BarTextures")
	local function Flag(on)
		for _, bar in pairs(container.bars or {}) do
			if bar.StatusBar then
				bar.StatusBar.melloKitBracket = on or nil
				if textures and textures.RefreshMask then
					textures:RefreshMask(bar.StatusBar)
				end
			end
		end
	end
	if rep then
		rep.onEnable = function() Flag(true) end
		rep.onDisable = function() Flag(false) end
		if active then
			Flag(true)
		end
		container:HookScript("OnSizeChanged", function()
			if active then
				Kit:WhenOutOfCombat(function() rep:Refit() end)
			end
		end)
	end
	for _, bar in pairs(container.bars or {}) do
		if bar.StatusBar and bar.StatusBar.Background then
			Replace(bar.StatusBar.Background, { as = "UI-HUD-ExperienceBar-Background" })
		end
	end
end

-- The container's pooled segment dividers → ticks (re-acquired on every
-- UpdateDividers: skinned once per divider frame)
local function SkinDividers(container)
	local pool = container.HorizontalDividersPool
	if not pool then
		return
	end
	for divider in pool:EnumerateActive() do
		if divider.BarDividerTexture and divider.melloRep == nil then
			divider.melloRep = Replace(divider.BarDividerTexture, { as = "UI-HUD-ExperienceBar-Divider" }) or false
		end
	end
end

local function SkinStatusBars()
	local manager = StatusTrackingBarManager
	if not manager then
		return
	end
	local containers = {}
	for _, container in ipairs(manager.barContainers or {}) do
		containers[#containers + 1] = container
	end
	for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
		if _G[name] then
			containers[#containers + 1] = _G[name]
		end
	end
	for _, container in ipairs(containers) do
		SkinStatusContainer(container)
		SkinDividers(container)
		if container.UpdateDividers and not container.melloDividerHook then
			container.melloDividerHook = true
			hooksecurefunc(container, "UpdateDividers", function(c)
				if active then
					Kit:WhenOutOfCombat(function() SkinDividers(c) end)
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- Build / lifecycle
--------------------------------------------------------------------------------

local function Build()
	if not skin then
		skin = { reps = {}, bars = {}, status = {}, capSync = {} }
	end
	-- each part on its own, so one failing part reports and the rest builds
	local function Try(label, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			MelloUI:Print("Action bars: %s failed: %s", label, tostring(err))
		end
	end
	for _, name in ipairs(BAR_NAMES) do
		Try(name, SkinBar, _G[name])
	end
	Try("micro menu", SkinMicroMenu)
	Try("bag bar", SkinBagBar)
	Try("status bars", SkinStatusBars)
end

-- The main bar's page number and arrows hidden (user, 2026-09-21): faded
-- and their mouse off, put back on disable or when the option goes off.
local function ApplyPageArrows()
	local page = skin and skin.page
	if not page then
		return
	end
	local hide = active and M.db and M.db.hidePageArrows
	if hide then
		Kit:Fade(page)
	else
		Kit:Unfade(page)
	end
	for _, key in ipairs({ "UpButton", "DownButton" }) do
		local button = page[key]
		if button and button.EnableMouse then
			button:EnableMouse(not hide)
		end
	end
end

local function Activate()
	if active then
		return
	end
	active = true
	Build()
	ApplyPageArrows()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for bar in pairs(skin.bars) do
		RefitBar(bar)
	end
	for _, sync in ipairs(skin.capSync) do
		sync()
	end
	for _, group in ipairs({ "actionbars", "micromenu", "bagbar", "statusbars" }) do
		Kit:Cover(group)
	end
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	for _, group in ipairs({ "actionbars", "micromenu", "bagbar", "statusbars" }) do
		Kit:Uncover(group)
	end
	ApplyPageArrows()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "hidePageArrows" then
		ApplyPageArrows()
	end
end

local function Hook()
	if hooked then
		return
	end
	hooked = true
	-- the status bars appear and stack at runtime (a reputation watched, a
	-- level gained): skin whatever the manager lays out
	if StatusTrackingBarManager then
		for _, method in ipairs({ "LayoutBars", "UpdateBarsShown" }) do
			if StatusTrackingBarManager[method] then
				hooksecurefunc(StatusTrackingBarManager, method, function()
					if active then
						Kit:WhenOutOfCombat(function()
							SkinStatusBars()
							for container in pairs(skin.status) do
								for _, rep in ipairs(skin.reps) do
									if rep.kind == "bar" and rep.rect == container then
										rep:Refit()
									end
								end
							end
						end)
					end
				end)
			end
		end
	end
end

function M:OnEnable(db)
	self.db = db
	Hook()
	Kit:WhenOutOfCombat(Activate)
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /abdump [bar|micro|bags|xp] [frames|reps]: the art of the main bar (or
-- the micro menu, the bag bar, the main status bar). Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOABDUMP1 = "/abdump"
SlashCmdList.MELLOABDUMP = function(msg)
	msg = (msg or ""):lower()
	local which, mode = msg:match("^(%a*)%s*(%a*)$")
	if which == "frames" or which == "reps" then
		which, mode = "", which
	end
	MelloUI:ClearLog()
	if which == "states" then
		-- every action button's rim against the button's own state (user,
		-- 2026-09-22: rims that looked pressed at rest)
		for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }) do
			for i = 1, 12 do
				local button = _G[prefix .. i]
				local rep = button and button.melloRep
				local rim = rep and rep.object
				if rim and rim.state and button:IsShown() then
					local okS, state = pcall(button.GetButtonState, button)
					local okC, checked = pcall(button.GetChecked, button)
					local okO, over = pcall(button.IsMouseOver, button)
					local okE, enabled = pcall(button.IsEnabled, button)
					local hk = button.HotKey and button.HotKey.GetText and button.HotKey:GetText() or ""
					if rim.state ~= "normal" then
						MelloUI:Print("%s [%s]: rim %s (hover=%s pressed=%s) | button state=%s checked=%s mouseover=%s enabled=%s",
							button:GetName(), tostring(hk), tostring(rim.state), tostring(rim.hover), tostring(rim.pressed),
							okS and tostring(state) or "?", okC and tostring(checked) or "?", okO and tostring(over) or "?", okE and tostring(enabled) or "?")
					end
				end
			end
		end
		MelloUI:ShowLog("abdump states")
		return
	end
	local roots = { bar = MainActionBar, micro = MicroMenu, bags = BagsBar, xp = MainStatusTrackingBarContainer }
	local root = roots[which ~= "" and which or "bar"]
	if root == MicroMenu and root then
		-- every micro button: the rim's own rect against the glyph's (the
		-- glyph should sit inside the rim's opening, user 2026-09-22)
		for _, button in ipairs({ root:GetChildren() }) do
			local rep = button.melloRep
			local rim = rep and rep.object
			local glyph = button.GetNormalTexture and button:GetNormalTexture()
			if rim and glyph then
				local rl, rb, rw, rh = rim:GetRect()
				local gl, gb, gw, gh = glyph:GetRect()
				local n = glyph:GetNumPoints()
				local p1, rel1 = glyph:GetPoint(1)
				MelloUI:Print("%s: rim %s..%s x %s..%s (%sx%s)  glyph %s..%s x %s..%s (%sx%s)  glyph points=%d first=%s to %s  atlas=%s",
					button:GetName() or "?", rl and math.floor(rl) or "?", rl and math.floor(rl + rw) or "?", rb and math.floor(rb) or "?", rb and math.floor(rb + rh) or "?",
					rw and math.floor(rw) or "?", rh and math.floor(rh) or "?",
					gl and math.floor(gl) or "?", gl and math.floor(gl + gw) or "?", gb and math.floor(gb) or "?", gb and math.floor(gb + gh) or "?",
					gw and math.floor(gw) or "?", gh and math.floor(gh) or "?",
					n or 0, tostring(p1), tostring(rel1 == rim and "rim" or rel1 == button and "button" or rel1 and rel1:GetName() or rel1),
					tostring(glyph.GetAtlas and glyph:GetAtlas()))
			end
		end
	end
	if not root then
		MelloUI:Print("%s: no such frame (bar, micro, bags, xp)", which)
	else
		MelloUI:Print("== %s  %s L%d %s", root:GetName() or "?", root:GetFrameStrata(), root:GetFrameLevel(), root:IsShown() and "shown" or "hidden")
		Kit:DumpWindow(root, skin, mode ~= "" and mode or nil)
		if root == MainStatusTrackingBarContainer then
			MelloUI:Print("status container skinned: %s; bars: %d; manager containers: %d; container %s L%d alpha=%.2f", tostring(skin and skin.status[root]),
				root.bars and #root.bars or 0, StatusTrackingBarManager and StatusTrackingBarManager.barContainers and #StatusTrackingBarManager.barContainers or -1,
				root:GetFrameStrata(), root:GetFrameLevel(), root:GetAlpha())
			local shown = root.GetShownBar and root:GetShownBar()
			local sb = shown and shown.StatusBar
			if sb then
				local tex = sb:GetStatusBarTexture()
				local r, g, b, a = tex:GetVertexColor()
				local l, sl = tex:GetDrawLayer()
				local okT, file = pcall(tex.GetTexture, tex)
				local okA, atlas = pcall(tex.GetAtlas, tex)
				MelloUI:Print("shown bar %s L%d alpha=%.2f; StatusBar %s L%d alpha=%.2f shown=%s; fill %s/%s alpha=%.2f rgb=%.2f %.2f %.2f a=%.2f tex=%s atlas=%s min/max/val=%s/%s/%s",
					shown:GetName() or "?", shown:GetFrameLevel(), shown:GetAlpha(), sb:GetFrameStrata(), sb:GetFrameLevel(), sb:GetAlpha(), tostring(sb:IsShown()),
					tostring(l), tostring(sl), tex:GetAlpha(), r or 0, g or 0, b or 0, a or 0, okT and tostring(file) or "?", okA and tostring(atlas) or "?",
					tostring(select(1, sb:GetMinMaxValues())), tostring(select(2, sb:GetMinMaxValues())), tostring(sb:GetValue()))
			end
		end
		if root == MainActionBar and ActionButton1 and ActionButton2 then
			local ok1, l1 = pcall(ActionButton1.GetLeft, ActionButton1)
			local ok2, l2 = pcall(ActionButton2.GetLeft, ActionButton2)
			if ok1 and ok2 and l1 and l2 and not Secret(l1) and not Secret(l2) then
				MelloUI:Print("button pitch x=%.1f padding=%s", l2 - l1, tostring(MainActionBar.buttonPadding))
			end
		end
	end
	MelloUI:ShowLog("abdump " .. msg)
end
