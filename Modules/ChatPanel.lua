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
local function StoneBackground(cf, background, frame)
	if not background or background.melloRep ~= nil then
		return
	end
	local rep = Replace(background, { as = "ChatFrameBody", rect = background, parent = frame })
	background.melloRep = rep or false
	if not (rep and rep.tex) then
		return
	end
	local function Hold()
		local wanted = cf.oldAlpha
		if active and wanted and not Secret(wanted) then
			rep.tex:SetAlpha(wanted)
		end
	end
	hooksecurefunc(background, "SetAlpha", Hold)
	local enable = rep.onEnable
	rep.onEnable = function(...)
		if enable then
			enable(...)
		end
		Hold()
	end
	-- the slider: FCF_SetWindowAlpha sets the textures first and remembers
	-- the value after, so the hold is re-run once the value is known
	if not skin.alphaHooked and FCF_SetWindowAlpha then
		skin.alphaHooked = true
		hooksecurefunc("FCF_SetWindowAlpha", function(f)
			local bg = f and _G[f:GetName() .. "Background"]
			if bg and bg.melloRep and bg.melloRep.tex and active then
				bg.melloRep.tex:SetAlpha(f.oldAlpha or 1)
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
	local rep = Replace(corner, { as = "ChatFrameBorder", rect = background, parent = frame, alsoFade = others })
	corner.melloRep = rep or false
	if rep and Kit.RegisterShell and frame == cf then
		-- a chat window has no header to hold: a grab frame over the whole
		-- window is its handle for the window mover (it takes the mouse only
		-- while the windows are unlocked, so links stay clickable otherwise)
		local grab = CreateFrame("Frame", nil, frame)
		grab:SetAllPoints(background)
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

local function SkinAll()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if cf then
			SkinChatFrame(cf)
			SkinMinimized(cf)
		end
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
SlashCmdList.MELLOCHDUMP = function(msg)
	msg = (msg or ""):lower()
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
