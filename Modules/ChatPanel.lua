--------------------------------------------------------------------------------
-- MelloUI - Chat Panel
--
-- The chat windows (ChatFrame1..10, FloatingChatFrameTemplate; their tabs,
-- minimized tabs, edit boxes, side button frames and the menu / channel /
-- voice buttons) dressed in the painted kit (Modules/Kit.lua) on the game's
-- own layout, by the rule book's fixed looks and the user's picks
-- (kit_raw/chat_catalog.png, 2026-09-21):
--   CH1: the single rail around the window's body in place of the eight
--   border pieces, as regions of the chat frame in their BORDER layer; the
--   body is the list-box stone in place of the game's flat black, at the
--   alpha slider's value and held there (no brightening under the mouse);
--   the rail is always at full alpha.
--   NO CHAT FADE (user, 2026-09-21): the tabs, the side button frame, the
--   edit box and the minimized tabs are held at full alpha too.
--   CT2: the tabs on TB6 (the single rail with the stone card, lit while
--   open, the text held centred), the minimized tabs the same.
--   Fixed: the edit box on the S1 plate with its focused look, the side
--   buttons (menu, channel, voice, minimize / maximize) on the cog plate
--   under the game's glyphs (K2), scroll-to-bottom on the arrow, the scroll
--   bar T2-H1-S1 by the sweep. Left as the game's: the resize grabber, the
--   dock's overflow arrow, the new-message glow and flash FX, the combat
--   log's filter bar.
-- Covers the Dark Mode / Chat tweak group "chat": the Chat module's art
-- toggles act only while this module is off. /chdump [n] [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("ChatPanel", {
	title = "Chat Panel Kit",
	desc = "The chat windows (frame, tabs, edit box, buttons) dressed in the painted kit on the game's own layout.",
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
			MelloUI:Notice("Chat panel: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- The border pieces of a FloatingBorderedFrame (the chat window, its side
-- button frame): `<name>TopLeftTexture` and the seven others around
-- `<name>Background`.
local BORDER_PIECES = { "TopLeftTexture", "TopRightTexture", "BottomLeftTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "TopTexture", "BottomTexture" }

-- No chat fade (user, 2026-09-21): the game dims the tabs, the side button
-- frame, the edit box and the window's own textures when the mouse is away
-- (UIFrameFadeIn / Out, FCFTab_UpdateAlpha, the edit box's inactive 0.35).
-- Every frame given here is held at full alpha while the module is on: a
-- post-hook on its SetAlpha puts 1 back (the game's fades set alpha every
-- frame through the same method). The rail itself never follows an alpha.
local function NoFade(frame)
	if not frame or frame.melloNoFade then
		return
	end
	frame.melloNoFade = true
	hooksecurefunc(frame, "SetAlpha", function(f, a)
		if active and a ~= 1 and not f.melloAlphaing then
			f.melloAlphaing = true
			f:SetAlpha(1)
			f.melloAlphaing = nil
		end
	end)
	skin.noFade[#skin.noFade + 1] = frame
	if active then
		frame:SetAlpha(1)
	end
end

-- The window's background: the stone tile in place of the game's flat
-- translucent black (user, 2026-09-21), at the alpha slider's value,
-- `chatFrame.oldAlpha`, held there instead of brightening under the mouse
-- (the game sets every chat texture's alpha by name; the stone reads the
-- remembered value after each of those calls).
-- The chat window's backdrop -- stone, rails and the parchment sheet -- lies
-- on a rect GROWN past the window's body, so the painted edge of the sheet
-- ends outside the text: the client lays every line out on the window's full
-- width, so the text cannot be set in to fit the sheet (tried, the lines were
-- cut) -- the sheet is fitted round the text instead (user, 2026-09-23: "grow
-- the backdrop"). Much sideways, little up and down: the tabs sit right above
-- the window and the input box right below, so the sheet takes the WIDE
-- strokes, deep on the sides and shallow top and bottom. The window keeps
-- Edit Mode's size and place; only its drawn backdrop reaches further.
local GROW_SIDE, GROW_TOP, GROW_BOTTOM = 22, 5, 4
local grown = setmetatable({}, { __mode = "k" })

local function BackdropRect(cf, background)
	local rect = grown[background]
	if not rect then
		rect = CreateFrame("Frame", nil, cf)
		rect:EnableMouse(false)
		rect:SetPoint("TOPLEFT", background, "TOPLEFT", -GROW_SIDE, GROW_TOP)
		rect:SetPoint("BOTTOMRIGHT", background, "BOTTOMRIGHT", GROW_SIDE, -GROW_BOTTOM)
		grown[background] = rect
	end
	return rect
end

local function StoneBackground(cf, background, frame)
	if not background or background.melloRep ~= nil then
		return
	end
	local rect = frame == cf and BackdropRect(cf, background) or background
	local rep = Replace(background, { as = "ChatFrameBody", rect = rect, parent = frame })
	background.melloRep = rep or false
	if not (rep and rep.tex) then
		return
	end
	-- the parchment laid on the stone, just inside the body (the chat's rails
	-- stand outside it), its edge painted (user, 2026-09-23: "lets make it on
	-- chat and dps meter aswell"); one sublevel above the stone, and as
	-- see-through as the stone at the alpha slider's value. The chat window's
	-- own body only, not the button column beside it. (Setting the lines in
	-- to fit the sheet was tried: this client lays every line out on the
	-- window's full width and its text container only clips them -- the
	-- lines were cut, user 2026-09-23.)
	local sheet
	if Kit.ParchmentSheet and frame == cf then
		local layer, sub = rep.tex:GetDrawLayer()
		sheet = Kit:ParchmentSheet(frame, frame, { rect = rect, margin = 4, wide = true, layer = layer, sublevel = math.min((sub or 0) + 1, 7) })
		if sheet then
			rep.sheet = sheet
		end
	end
	local function Hold()
		local wanted = cf.oldAlpha
		if active and wanted and not Secret(wanted) then
			rep.tex:SetAlpha(wanted)
			if sheet then
				sheet:SetAlpha(wanted)
			end
		end
	end
	hooksecurefunc(background, "SetAlpha", Hold)
	local enable, disable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if enable then
			enable(...)
		end
		if sheet then
			sheet:Show()
		end
		Hold()
	end
	-- the sheet is the chat frame's own region, not the replacement's: it
	-- goes and comes with the chat reskin by hand
	rep.onDisable = function(...)
		if disable then
			disable(...)
		end
		if sheet then
			sheet:Hide()
		end
	end
	if sheet and not active then
		sheet:Hide()
	end
	-- the slider: FCF_SetWindowAlpha sets the textures first and remembers
	-- the value after, so the hold is re-run once the value is known
	if not skin.alphaHooked and FCF_SetWindowAlpha then
		skin.alphaHooked = true
		hooksecurefunc("FCF_SetWindowAlpha", function(f)
			local bg = f and _G[f:GetName() .. "Background"]
			if bg and bg.melloRep and bg.melloRep.tex and active then
				bg.melloRep.tex:SetAlpha(f.oldAlpha or 1)
				if bg.melloRep.sheet then
					bg.melloRep.sheet:SetAlpha(f.oldAlpha or 1)
				end
			end
		end)
	end
	if active then
		Hold()
	end
end

-- A bordered frame: the single rail (CH1) on the background's rect in place
-- of the eight border pieces, in the chat frame's own BORDER layer.
local function SkinBordered(frame, prefix, cf)
	local background = _G[prefix .. "Background"]
	local corner = _G[prefix .. "TopLeftTexture"]
	if not (background and corner) or corner.melloRep ~= nil then
		return
	end
	local others = {}
	for i = 2, #BORDER_PIECES do
		others[#others + 1] = _G[prefix .. BORDER_PIECES[i]]
	end
	local rep = Replace(corner, { as = "ChatFrameBorder", rect = frame == cf and BackdropRect(cf, background) or background, parent = frame, alsoFade = others })
	corner.melloRep = rep or false
	if rep and Kit.RegisterShell and frame == cf then
		-- a chat window has no header to hold: a strip along the top of its
		-- body is its handle for the window mover. It takes the mouse while
		-- the windows are unlocked, so it covers a strip and not the body --
		-- over the whole window it swallowed the links, the scroll buttons
		-- and the wheel (user, 2026-09-22)
		local grab = CreateFrame("Frame", nil, frame)
		grab:SetPoint("TOPLEFT", background, "TOPLEFT")
		grab:SetPoint("TOPRIGHT", background, "TOPRIGHT")
		grab:SetHeight(22)
		grab:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)
		grab:EnableMouse(false)
		Kit:RegisterShell(frame, { title = grab, outer = rep })
	end
end

-- A chat tab (ChatTabTemplate: the plain set at BACKGROUND, the active set
-- at BORDER shown by FCFTab_UpdateColors, highlights at HIGHLIGHT; the art
-- bottom-anchored in the 32 px tab, the text 5 px under its centre) on TB6:
-- the plain card on the art's rows, the lit card while the active set
-- shows, the text held centred on the card.
local TAB_TOP_INSET = 8

-- A chat window's tab in front of the window's backdrop: the backdrop now
-- reaches up past the window's top (BackdropRect) and its top rail and stone
-- drew over the tabs' feet (user, 2026-09-23: "adjust the tabs on the top to
-- be infront of the background"). A higher frame level did not hold: the chat
-- windows are top-level frames, and a click lifts the window over its tabs
-- inside the client, past any hook ("didnt work", the same day). So the tab
-- goes one STRATA above its window -- nothing on the window's strata can
-- then come over it -- and is put back there whenever something sets its
-- strata or level again. Neither is protected state: the game's tab code is
-- left to itself.
local STRATA_ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local STRATA = {}
for i, name in ipairs(STRATA_ORDER) do
	STRATA[name] = i
end
local tabsInFront = setmetatable({}, { __mode = "k" })
local raisingTab = false

-- The highest strata of any chat window: a docked window's tab (Loot, a new
-- window) sits on the DOCK's selected window, not over its own frame, which
-- can be a strata lower ("general and combat log work, but loot and any other
-- created window do not", user 2026-09-23) -- so every tab goes above them all.
local function ChatStrataTop()
	local top = 0
	for _, owner in pairs(tabsInFront) do
		local ok, strata = pcall(owner.GetFrameStrata, owner)
		if ok and STRATA[strata] and STRATA[strata] > top then
			top = STRATA[strata]
		end
	end
	local dock = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.primary
	if dock and dock.GetFrameStrata then
		local strata = dock:GetFrameStrata()
		if STRATA[strata] and STRATA[strata] > top then
			top = STRATA[strata]
		end
	end
	return top > 0 and top or 2
end

-- The tabs of docked windows past the first ones (Loot, a new window) are
-- children of the dock's SCROLL frame, the strip that scrolls tabs when there
-- are many; what a scroll frame holds is drawn with the scroll frame itself,
-- so their own strata did nothing (/chdump tabs: the scroll frame at LOW,
-- level 2, under the chat window's LOW 5 -- user, 2026-09-23). The scroll
-- frame goes above the chat windows with them; back with the reskin off.
local dockHooked = false

local function DockInFront(above)
	local strip = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.scrollFrame
	if not (strip and strip.SetFrameStrata) then
		return
	end
	if not dockHooked then
		dockHooked = true
		hooksecurefunc(strip, "SetFrameStrata", function()
			if active and not raisingTab then
				raisingTab = true
				pcall(strip.SetFrameStrata, strip, STRATA_ORDER[math.min(ChatStrataTop() + 1, #STRATA_ORDER)])
				raisingTab = false
			end
		end)
	end
	if strip:GetFrameStrata() ~= above then
		strip:SetFrameStrata(above)
	end
end

local function TabInFront(tab, cf)
	if raisingTab or not (active and tab and cf) then
		return
	end
	raisingTab = true
	pcall(function()
		local above = STRATA_ORDER[math.min(ChatStrataTop() + 1, #STRATA_ORDER)]
		if tab:GetFrameStrata() ~= above then
			tab:SetFrameStrata(above)
		end
		DockInFront(above)
	end)
	raisingTab = false
end

local function KeepTabInFront(tab, cf)
	if not (tab and cf) or tabsInFront[tab] then
		return
	end
	tabsInFront[tab] = cf
	-- a new window can raise the chat windows' top strata: every tab again
	for other, owner in pairs(tabsInFront) do
		if other ~= tab then
			TabInFront(other, owner)
		end
	end
	hooksecurefunc(tab, "SetFrameLevel", function(self) TabInFront(self, cf) end)
	hooksecurefunc(tab, "SetFrameStrata", function(self) TabInFront(self, cf) end)
	tab:HookScript("OnShow", function(self) TabInFront(self, cf) end)
	cf:HookScript("OnShow", function() TabInFront(tab, cf) end)
	TabInFront(tab, cf)
end

local function SkinTab(tab)
	if not (tab and tab.Left and tab.Middle and tab.Right) or tab.melloRep ~= nil then
		return
	end
	tab.melloRep = false
	local sizer = CreateFrame("Frame", nil, tab)
	sizer:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -TAB_TOP_INSET)
	sizer:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
	local plain = Replace(tab.Left, { as = "uiframe-tab-left", rect = sizer, parent = tab, button = tab,
		alsoFade = { tab.Middle, tab.Right, tab.HighlightLeft, tab.HighlightMiddle, tab.HighlightRight } })
	local open = nil
	if tab.ActiveLeft then
		open = Replace(tab.ActiveLeft, { as = "uiframe-activetab-left", rect = sizer, parent = tab,
			alsoFade = { tab.ActiveMiddle, tab.ActiveRight } })
	end
	tab.melloRep = plain or open or false
	if open then
		local function Follow()
			if active then
				open:SetShown(tab.ActiveLeft:IsShown())
			end
		end
		hooksecurefunc(tab.ActiveLeft, "Show", Follow)
		hooksecurefunc(tab.ActiveLeft, "Hide", Follow)
		local enable = open.onEnable
		open.onEnable = function(...)
			if enable then
				enable(...)
			end
			Follow()
		end
		Follow()
	end
	-- the text centred on the card (the game anchors it 5 px under the
	-- tab's centre, on its own art); re-applied after the game's SetPoint
	-- calls, only while a card is on
	local text = tab.Text or (tab.GetFontString and tab:GetFontString())
	if text and (plain or open) then
		local function Steady()
			if tab.melloSteadying or not active then
				return
			end
			tab.melloSteadying = true
			text:SetPoint("CENTER", sizer, "CENTER", 0, 0)
			tab.melloSteadying = nil
		end
		hooksecurefunc(text, "SetPoint", Steady)
		local rep = plain or open
		local enable, disable = rep.onEnable, rep.onDisable
		rep.onEnable = function(...)
			if enable then
				enable(...)
			end
			Steady()
		end
		rep.onDisable = function(...)
			if disable then
				disable(...)
			end
			text:SetPoint("CENTER", tab, "CENTER", 0, -5)
		end
		Steady()
	end
end

-- A small icon button (menu, channel, voice, minimize, maximize): the cog
-- plate under the game's glyph.
local function SkinIconButton(button)
	if not (button and button.GetNormalTexture and button:GetNormalTexture()) or button.melloRep ~= nil then
		return
	end
	local normal = button:GetNormalTexture()
	if button.Icon then
		-- the channel button: its normal texture IS a plate (the round
		-- `chatframe-button-up` atlas) with the glyph on `Icon`; the plate is
		-- replaced by the cog on its rect, its pushed / highlight art faded
		button.melloRep = Replace(normal, { button = button,
			alsoFade = { button.GetPushedTexture and button:GetPushedTexture(), button.GetHighlightTexture and button:GetHighlightTexture() } }) or false
	else
		button.melloRep = Replace(normal, { as = "ChatIconButton", button = button, noFade = true }) or false
	end
end

local function SkinEditBox(edit)
	if not edit or edit.melloRep ~= nil then
		return
	end
	local name = edit:GetName()
	local mid = name and _G[name .. "Mid"]
	if not mid then
		edit.melloRep = false
		return
	end
	-- the S1 plate with its LEFT cap dropped: that cap carries the search
	-- glyph, and this is a chat box (user, 2026-09-21); the plate closes with
	-- the plain end piece (inputs/edit_end_l, the right cap mirrored), so the
	-- game's own 15 px header inset clears the rail as it is
	edit.melloRep = Replace(mid, { as = "UI-ChatInputBorder-Mid2", rect = edit, parent = edit, edit = edit, dropCap = "l",
		alsoFade = { _G[name .. "Left"], _G[name .. "Right"], edit.focusLeft, edit.focusMid, edit.focusRight } }) or false
end

local function SkinChatFrame(cf)
	if not cf or cf.melloChatSkinned then
		return
	end
	cf.melloChatSkinned = true
	local name = cf:GetName()
	SkinBordered(cf, name, cf)
	StoneBackground(cf, _G[name .. "Background"], cf)
	if cf.buttonFrame then
		SkinBordered(cf.buttonFrame, name .. "ButtonFrame")
		StoneBackground(cf, _G[name .. "ButtonFrameBackground"], cf.buttonFrame)
		SkinIconButton(cf.buttonFrame.minimizeButton)
		NoFade(cf.buttonFrame)
	end
	SkinTab(_G[name .. "Tab"])
	KeepTabInFront(_G[name .. "Tab"], cf)
	NoFade(_G[name .. "Tab"])
	SkinEditBox(cf.editBox)
	NoFade(cf.editBox)
	local toBottom = cf.ScrollToBottomButton
	if toBottom and toBottom.GetNormalTexture and toBottom:GetNormalTexture() and toBottom.melloRep == nil then
		toBottom.melloRep = Replace(toBottom:GetNormalTexture(), { as = "minimal-scrollbar-arrow-returntobottom", button = toBottom }) or false
	end
	Kit:SweepControls(cf, Replace, skin)
end

-- A minimized chat window (FloatingChatFrameMinimizedTemplate, made by
-- FCF_MinimizeFrame on the first minimize): the same card, its maximize
-- button on the cog plate.
local function SkinMinimized(cf)
	local min = cf and _G[cf:GetName() .. "Minimized"]
	if not min or min.melloRep ~= nil then
		return
	end
	SkinTab(min)
	NoFade(min)
	SkinIconButton(_G[min:GetName() .. "MaximizeButton"])
end

-- Every chat window the game has: the whisper windows it opens on the fly are
-- ChatFrame11, 12, ... and listed only in CHAT_FRAMES. The hooks below ran
-- this for each new whisper window, but the loop stopped at NUM_CHAT_WINDOWS,
-- so a whisper tab never got the kit (user, 2026-09-23). Read only.
local function ChatFrames()
	local list = {}
	if type(CHAT_FRAMES) == "table" then
		for _, name in pairs(CHAT_FRAMES) do
			local cf = type(name) == "string" and _G[name]
			if cf then
				list[#list + 1] = cf
			end
		end
	end
	if #list == 0 then
		for i = 1, (NUM_CHAT_WINDOWS or 10) do
			list[#list + 1] = _G["ChatFrame" .. i]
		end
	end
	return list
end

local function SkinAll()
	for _, cf in ipairs(ChatFrames()) do
		SkinChatFrame(cf)
		SkinMinimized(cf)
	end
	for _, key in ipairs({ "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }) do
		SkinIconButton(_G[key])
	end
end

local function Build()
	if skin then
		return
	end
	skin = { reps = {}, followers = {}, noFade = {} }
	SkinAll()
	-- windows and minimized tabs made later: after the game's own setup
	if FCF_MinimizeFrame then
		hooksecurefunc("FCF_MinimizeFrame", function(cf)
			if active then
				SkinMinimized(cf)
			end
		end)
	end
	for _, fn in ipairs({ "FCF_OpenNewWindow", "FCF_OpenTemporaryWindow", "FCF_DockFrame", "FCF_UnDockFrame" }) do
		if _G[fn] then
			hooksecurefunc(fn, function()
				if active then
					SkinAll()
				end
			end)
		end
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
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	for _, frame in ipairs(skin.noFade) do
		frame:SetAlpha(1)
	end
	for tab, cf in pairs(tabsInFront) do
		TabInFront(tab, cf)
	end
	Kit:Cover("chat")
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	-- the tabs back on their window's strata, the dock's tab strip on the
	-- dock's (TabInFront stays off while inactive)
	for tab, cf in pairs(tabsInFront) do
		pcall(tab.SetFrameStrata, tab, cf:GetFrameStrata())
	end
	local dock = GENERAL_CHAT_DOCK
	if dock and dock.scrollFrame and dock.GetFrameStrata then
		pcall(dock.scrollFrame.SetFrameStrata, dock.scrollFrame, dock:GetFrameStrata())
	end
	Kit:Uncover("chat")
end

function M:OnEnable(db)
	self.db = db
	if ChatFrame1 then
		Activate()
	end
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /chdump [n] [frames|reps]: a chat window's art (n = 1 by default). Opens
-- the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOCHDUMP1 = "/chdump"
-- /chdump tabs: every chat tab against its window and the dock -- parent,
-- strata, level, shown -- for the tabs that stayed behind the backdrop
local function DumpTabs()
	local function Describe(label, f)
		if not f then
			MelloUI:Print("%s: none", label)
			return
		end
		local parent = f.GetParent and f:GetParent()
		local pname = parent and (parent:GetName() or parent:GetDebugName()) or "none"
		MelloUI:Print("%s: parent %s, strata %s, level %d, shown %s, visible %s", label, tostring(pname),
			tostring(f:GetFrameStrata()), f:GetFrameLevel(), tostring(f:IsShown()), tostring(f:IsVisible()))
	end
	local dock = GENERAL_CHAT_DOCK
	Describe("dock", dock)
	if dock then
		Describe("dock primary", dock.primary)
		Describe("dock scrollFrame", dock.scrollFrame)
		Describe("dock scroll child", dock.scrollFrame and dock.scrollFrame.GetScrollChild and dock.scrollFrame:GetScrollChild())
	end
	MelloUI:Print("chat windows' top strata: %s, active %s", tostring(STRATA_ORDER[ChatStrataTop()]), tostring(active))
	for _, name in ipairs(CHAT_FRAMES or {}) do
		local cf = _G[name]
		local tab = _G[name .. "Tab"]
		if cf and tab then
			Describe(name, cf)
			Describe("   " .. name .. "Tab", tab)
			MelloUI:Print("      kept in front: %s", tostring(tabsInFront[tab] ~= nil))
		end
	end
end

SlashCmdList.MELLOCHDUMP = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg:find("^tab") then
		MelloUI:ClearLog()
		DumpTabs()
		MelloUI:ShowLog("chdump tabs")
		return
	end
	local n = tonumber(msg:match("^(%d+)")) or 1
	local what = msg:match("%a+")
	MelloUI:ClearLog()
	local cf = _G["ChatFrame" .. n]
	if not cf then
		MelloUI:Print("No chat window %d.", n)
	else
		Kit:DumpWindow(cf, skin, what)
		local tab = _G[cf:GetName() .. "Tab"]
		if tab then
			Kit:DumpWindow(tab, skin, what)
		end
		if cf.editBox then
			Kit:DumpWindow(cf.editBox, skin, what)
		end
	end
	MelloUI:ShowLog("chdump " .. msg)
end
