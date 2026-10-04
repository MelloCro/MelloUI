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
--   alpha slider's value and held there (no brightening under the mouse;
--   the Chat module's Background Opacity sets that value for every window,
--   through the game's own function, with Chat Tweaks off too); the rail is
--   always at full alpha.
--   NO CHAT FADE (user, 2026-09-21): the tabs, the side button frame, the
--   edit box and the minimized tabs are held at full alpha too.
--   CT2: the tabs on TB6 (the single rail with the stone card, lit while
--   open, the text held centred), the minimized tabs the same.
--   Fixed: the edit box on the S1 plate with its focused look, the side
--   buttons (voice, minimize / maximize) on the cog plate under the game's
--   glyphs (K2); the column's chat menu, Channels and Friends in the round
--   glyph look (0.17.0, pick C: SkinColumnButton); scroll-to-bottom on the arrow, the scroll
--   bar T2-H1-S1 by the sweep. Left as the game's: the resize grabber, the
--   dock's overflow arrow, the new-message glow and flash FX, the combat
--   log's filter bar.
-- Covers the Dark Mode / Chat tweak group "chat": the Chat module's art
-- toggles act only while this module is off. /chdump [n] [frames|reps],
-- /chdump tabs, /chdump shade.
-- THE SHADE (0.14.0): the pieces on a chat window's outline get the kit's
-- soft shade (Modules/KitShade.lua, area "chat"; below, "The shade").
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("ChatPanel")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("ChatPanel", {
	title = "Chat Panel Kit",
	desc = "The chat windows (frame, tabs, edit box, buttons) dressed in the painted kit on the game's own layout.",
	window = { label = "Chat windows", desc = "Chat frames, tabs, edit box and buttons in the kit (no fade).", tab = "HUD" },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil
local active = false

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

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
-- The chat's and the whisper windows' ink follows the chat reskin and its
-- parchment (QuestInk's rule, user 2026-09-23)
local function InkFollows()
	local QI = MelloUI.QuestInk
	if not QI then
		return
	end
	for _, name in ipairs({ "chat", "whisper" }) do
		if QI.surfaces[name] then
			QI.RefreshSurface(name)
		end
	end
end

--------------------------------------------------------------------------------
-- The shade (0.14.0, the whole UI's soft shade: Kit:ShadeElement, area
-- "chat", which covers the whisper popups too -- Modules/Chat.lua). Only the
-- pieces on a chat window's outline against the world get a partner:
--   the window's rail: its family's nine, outside only (nothing under the
--     see-through stone or the parchment inside it), drawn one level under
--     the chat frame, under every part of the window. The rail keeps full
--     alpha under the Background Opacity, and so does its shade;
--   the button column's rail (menu, channel and voice buttons, beside the
--     window): the same nine, its side toward the window open, cut by a
--     mask at the window rail's outer edge. The column reaches about ten
--     units past the window's rail, so its outer rail is on the outline;
--     the cut keeps its shade off the window (the window's own shade and
--     stone are there). It follows the game's FCF_SetButtonSide. The
--     window's own shade stays whole under the column: the window's rail
--     shows through the column's see-through stone there, and its shade
--     with it (opening that side would drop the window's corner shade);
--   each tab's card: the same nine with its foot open (the tab stands on
--     the window's top rail), drawn under the tab, on the tab's strata, cut
--     by a mask at the rail's inner edge: the sides' shade lies on the
--     rail beside the foot, never below it on the stone or the parchment;
--   a minimized window's card: the whole nine (it stands alone);
--   the edit box's plate: its own pieces' shadows, cut to reach past its
--     ends and its free side only, never toward the window it sits on (the
--     box is a strata above the window: a shade reaching into the window
--     would lie on its stone and parchment). Below the window, the game's
--     place; above it with Chat Tweaks' Edit Box On Top (M.EditBoxSide).
-- The side buttons sit inside the column's rail: inner pieces, no partner.
-- Each element's shade is made when its frame is first seen, while the
-- reskin is on (chat windows never opened add nothing, nor a column that
-- Hide Chat Buttons keeps hidden); after that the partners follow their
-- pieces (the reskin off hides them with its replacements). Nothing polls,
-- nothing is made per frame.
-- A chat window is an Edit Mode system: its shade is drawn by a frame of
-- ours anchored to the window's grown backdrop (BackdropRect, on the
-- window's Background region), never to the window itself.
--------------------------------------------------------------------------------

local SHADE_AREA = "chat"
local shade = {
	pending = setmetatable({}, { __mode = "k" }),   -- [root] = { obj, opts or false, ... }: made at its first show
	made = setmetatable({}, { __mode = "k" }),      -- [root] = its element, once made
	hooked = setmetatable({}, { __mode = "k" }),    -- [root] = true: its OnShow hooked
	anchor = setmetatable({}, { __mode = "k" }),    -- [chat window] = the rect its shade frame lies on
	rail = setmetatable({}, { __mode = "k" }),      -- [chat window] = its rail (the ChatFrameBorder replacement)
	cut = setmetatable({}, { __mode = "k" }),       -- [tab or button column] = { kind, root, cf, rep, opts, mask }: its shade's mask
	plates = setmetatable({}, { __mode = "k" }),    -- [edit box plate] = the cut of each part (EDIT_PARTS order)
	editTop = false,                                -- the edit boxes above their windows (Chat's Edit Box On Top)
	-- a cut's mask: the plain white square, clamped (nothing outside it), and
	-- how far it reaches past the shade on its free sides (UI units; a
	-- shade reaches about 13 at the kit's scale)
	MASK = "Interface\\Buttons\\WHITE8X8",
	REACH = 96,
}
local EDIT_PARTS = { "capL", "mid", "capR" }
local Border   -- (Border Opacity: below, before the bordered frames)

-- the element of a root: a chat window's drawn by its own shade frame (one
-- level under the window, as the kit's shade frames are, on the rect)
local function ShadeElement(root)
	local rect = shade.anchor[root]
	if not rect then
		return Kit:ShadeElement(root, SHADE_AREA)
	end
	local host = CreateFrame("Frame", nil, root)
	host:SetFrameLevel(math.max(root:GetFrameLevel() - 1, 0))
	host:EnableMouse(false)
	host:SetAllPoints(rect)
	host.ignoreInLayout = true
	host.kitShadeHost = true
	return Kit:ShadeElement(root, SHADE_AREA, { host = host })
end

-- The open side of a button column's shade: toward its window ("left", the
-- game's default, puts the column left of the window)
function shade.ColumnOpen(cf)
	return cf and cf.buttonSide == "right" and "l" or "r"
end

-- A cut's mask laid (again), on its window's rail (rep.skin: the rail's
-- outer edge; its top edge's bottom: the rail's inner edge):
--   a tab: from well above the tab down to the rail's inner edge;
--   a button column: from well past the column up to the rail's outer edge
--     on the column's side.
-- A docked tab's own window lies on the dock's first one, so the rail is
-- always the one under the tab.
function shade.LayCut(rec)
	local mask, rail = rec.mask, shade.rail[rec.cf]
	local railSkin = rail and rail.skin
	if not (mask and railSkin) then
		return
	end
	local R = shade.REACH
	mask:ClearAllPoints()
	if rec.kind == "tab" then
		mask:SetPoint("TOPLEFT", rec.root, "TOPLEFT", -R, R)
		local edge = Kit.RailAnchor and Kit:RailAnchor(railSkin, "t")
		if edge then
			mask:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", R, 0)
		else
			mask:SetPoint("BOTTOMRIGHT", railSkin, "TOPRIGHT", R, -(railSkin.thickness or 0))
		end
	elseif rec.opts.open == "r" then
		mask:SetPoint("TOPRIGHT", railSkin, "TOPLEFT", 0, R)
		mask:SetPoint("BOTTOMLEFT", railSkin, "BOTTOMLEFT", -R, -R)
	else
		mask:SetPoint("TOPLEFT", railSkin, "TOPRIGHT", 0, R)
		mask:SetPoint("BOTTOMRIGHT", railSkin, "BOTTOMRIGHT", R, -R)
	end
end

-- a root's waiting parts made, as one element of its own (only while the
-- reskin is on: else they wait for a show while it is); a tab's or a
-- column's mask made first, on the element's shade frame (a mask works on
-- the textures of the frame that made it)
local function MakeShade(root)
	local list = shade.pending[root]
	if not (list and active) then
		return
	end
	shade.pending[root] = nil
	local el = shade.made[root] or ShadeElement(root)
	shade.made[root] = el
	local rec = shade.cut[root]
	if rec and not rec.mask then
		local host = el:Host()
		if host and host.CreateMaskTexture then
			local mask = host:CreateMaskTexture()
			mask:SetTexture(shade.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			rec.mask, rec.opts.mask = mask, mask
			shade.LayCut(rec)
		end
	end
	for i = 1, #list, 2 do
		el:Add(list[i], list[i + 1] or nil)
	end
	-- (a rail's shade: at the rail's Border Opacity)
	local rail = Border.rails[root]
	if rail then
		Border.Lay(root, rail)
	end
end

local Shade_OnShow = Perf.Shared("OnShow on a chat window, tab or edit box: its first shade", function(root)
	MakeShade(root)
end, "script")

local function Seen(frame)
	local ok, seen = pcall(frame.IsVisible, frame)
	return ok and not Secret(seen) and seen and true or false
end

-- one part of a root's shade: made now when the root is seen, else at its
-- first show (a shared hook, once per root)
local function ShadeLater(root, obj, opts)
	if not (root and obj and Kit.ShadeElement) then
		return
	end
	local list = shade.pending[root]
	if not list then
		list = {}
		shade.pending[root] = list
	end
	list[#list + 1] = obj
	list[#list + 1] = opts or false
	if not shade.hooked[root] then
		shade.hooked[root] = true
		Perf.HookScript(root, "OnShow", Shade_OnShow)
	end
	if Seen(root) then
		MakeShade(root)
	end
end

-- the reskin on again: every root seen whose shade still waits
local function ShadeSeen()
	for root in pairs(shade.pending) do
		if Seen(root) then
			MakeShade(root)
		end
	end
end

-- A part whose shade a mask cuts (a tab's card on its window, `cf`; a
-- button column's rail beside it), made at its root's first show
function shade.Cut(kind, root, cf, rep, open)
	if not (root and cf and rep) or shade.cut[root] then
		return
	end
	local rec = { kind = kind, root = root, cf = cf, rep = rep, opts = { open = open } }
	shade.cut[root] = rec
	ShadeLater(root, rep, rec.opts)
end

-- The game moved a window's button column to its other side
-- (FCF_SetButtonSide, by the window's place on the screen): its shade opens
-- toward the window again and its cut moves with it (a shade not made yet
-- is made so)
function shade.ColumnMoved(cf)
	local column = cf and cf.buttonFrame
	local rec = column and shade.cut[column]
	if not rec then
		return
	end
	local open = shade.ColumnOpen(cf)
	if rec.opts.open == open then
		return
	end
	rec.opts.open = open
	shade.LayCut(rec)
	local colSkin = rec.rep.skin
	local nine = colSkin and colSkin.kitShadeNine
	if nine and Kit.ShadowFit then
		Kit:ShadowFit(nine, nil, open)
	end
end

-- An edit box plate's parts cut to their free sides: each part's whole
-- piece (painted px) with its pads on the ends' and the free side only. The
-- cut tables the parts are made with follow (a part not made yet takes the
-- side of its making), and a made partner is cut again
local function CutPlate(strip)
	local cuts = shade.plates[strip]
	if not (cuts and Kit.Size) then
		return
	end
	local sides = shade.editTop and "lrt" or "lrb"
	for i = 1, #EDIT_PARTS do
		local part, cut = strip[EDIT_PARTS[i]], cuts[i]
		local w, h = Kit:Size(part and part.kitName, 1)
		if w > 0 and h > 0 then
			cut[2], cut[4], cut.sides = w, h, sides
			if part.kitShadow and Kit.ShadowCut then
				Kit:ShadowCut(part, 0, w, 0, h, sides)
			end
		end
	end
end

local function ShadePlate(edit, rep)
	local strip = rep and rep.strip
	if not (strip and Kit.ShadeElement and Kit.ShadowCut) or shade.plates[strip] then
		return
	end
	local cuts = {}
	for i = 1, #EDIT_PARTS do
		cuts[i] = { 0, 0, 0, 0 }
	end
	shade.plates[strip] = cuts
	CutPlate(strip)
	for i = 1, #EDIT_PARTS do
		local part = strip[EDIT_PARTS[i]]
		if part and cuts[i][2] > 0 then
			ShadeLater(edit, part, { cut = cuts[i] })
		end
	end
end

-- The side the edit boxes sit on (Chat Tweaks' Edit Box On Top, told by
-- Modules/Chat.lua whenever it places them): the plates' shade reaches away
-- from the window
function M.EditBoxSide(top)
	top = top and true or false
	if shade.editTop == top then
		return
	end
	shade.editTop = top
	for strip in pairs(shade.plates) do
		CutPlate(strip)
	end
end

local function NoFade(frame)
	if not frame or frame.melloNoFade then
		return
	end
	frame.melloNoFade = true
	hooksecurefunc(frame, "SetAlpha", function(f, a)
		-- (0.17.0: the Fader's fade of the chat's line is not undone here)
		local Fader = MelloUI.Fader
		if active and a ~= 1 and not f.melloAlphaing and not (Fader and Fader:Holds(f)) then
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
-- [chat window] = the holds of its stones (its body and its button column):
-- the one hold each, re-run after the game's FCF_SetWindowAlpha
local holds = setmetatable({}, { __mode = "k" })

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
		sheet = Kit:ParchmentSheet(frame, frame, { rect = rect, margin = 4, wide = true, layer = layer, sublevel = math.min((sub or 0) + 1, 7),
			area = "chat", alive = function() return active end })
		if sheet then
			rep.sheet = sheet
		end
	end
	-- no eye strain (user, 2026-09-24: "too much small text over a plain
	-- brown border is just an eye strain" / "apply the eye strain rule to all
	-- existing windows"; WINDOW-RULES 2e): on the stone look (the chat's
	-- parchment off) the window's body lies under the palette's inner panel,
	-- a region of the chat frame on the sheet's rect and sublevel (the two
	-- never show together: Kit:SetParchment switches one against the other),
	-- at the alpha slider's value as the stone. The chat window's own body
	-- only; the button column beside it holds no text. The Chat module's
	-- "Hide Window Background" acts only while this reskin is off, and the
	-- panel is gone with the reskin, so the two never meet.
	local dim
	if Kit.StoneDim and frame == cf then
		local layer, sub = rep.tex:GetDrawLayer()
		dim = Kit:StoneDim(frame, { rect = rect, margin = 2, layer = layer, sublevel = math.min((sub or 0) + 1, 7),
			area = "chat", alive = function() return active end })
		rep.dim = dim
	end
	local function Hold()
		local wanted = cf.oldAlpha
		if active and wanted and not Secret(wanted) then
			rep.tex:SetAlpha(wanted)
			if sheet then
				sheet:SetAlpha(wanted)
			end
			if dim then
				dim:SetAlpha(wanted)
			end
		end
	end
	hooksecurefunc(background, "SetAlpha", Hold)
	local list = holds[cf]
	if not list then
		list = {}
		holds[cf] = list
	end
	list[#list + 1] = Hold
	local enable, disable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if enable then
			enable(...)
		end
		if sheet then
			sheet:SetShown(Kit:ParchmentOn("chat"))
		end
		if dim then
			dim:SetShown(not Kit:ParchmentOn("chat"))
		end
		Hold()
		InkFollows()
	end
	-- the sheet and the panel are the chat frame's own regions, not the
	-- replacement's: they go and come with the chat reskin by hand
	rep.onDisable = function(...)
		if disable then
			disable(...)
		end
		if sheet then
			sheet:Hide()
		end
		if dim then
			dim:Hide()
		end
		InkFollows()
	end
	if sheet and not active then
		sheet:Hide()
	end
	if dim and not active then
		dim:Hide()
	end
	-- the slider: FCF_SetWindowAlpha sets the textures first and remembers
	-- the value after, so the holds are re-run once the value is known --
	-- every stone of that window, its button column's too (only the body's
	-- was, so the column kept the old value until the next fade). The Chat
	-- module's Background Opacity comes through this same function.
	if not skin.alphaHooked and FCF_SetWindowAlpha then
		skin.alphaHooked = true
		hooksecurefunc("FCF_SetWindowAlpha", function(f)
			local held = active and f and holds[f]
			if held then
				for i = 1, #held do
					held[i]()
				end
			end
		end)
	end
	if active then
		Hold()
	end
end

--------------------------------------------------------------------------------
-- Border Opacity (user, 2026-10-04: "we have a background opacity slider for
-- the chat, can we also make a Border opacity aswell?"): the Chat module's
-- borderAlpha on the painted rail of every chat window and of its button
-- column, and on their shade with it (each rail's own shade frame: a window's
-- holds its rail's shade only, a column's its own). The rails are ours: one
-- write a piece when the value changes, a rail is made or its shade is.
-- (One table: the rails, by the frame they border.)
--------------------------------------------------------------------------------
Border = { rails = setmetatable({}, { __mode = "k" }) }

function Border.Alpha()
	local db = MelloUI:GetModuleDB("Chat")
	local a = db and db.borderAlpha
	if type(a) ~= "number" or Secret(a) then
		return 1
	end
	return math.max(0, math.min(1, a))
end

-- one rail (and its shade, once made)
function Border.Lay(frame, rep, a)
	a = a or Border.Alpha()
	local pieces = rep.skin and rep.skin.all
	for i = 1, pieces and #pieces or 0 do
		pieces[i]:SetAlpha(a)
	end
	local el = shade.made[frame]
	local host = el and el.Host and el:Host()
	if host then
		host:SetAlpha(a)
	end
end

function Border.Add(frame, rep)
	Border.rails[frame] = rep
	Border.Lay(frame, rep)
end

function Border.LayAll()
	local a = Border.Alpha()
	for frame, rep in pairs(Border.rails) do
		Border.Lay(frame, rep, a)
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
	if rep then
		Border.Add(frame, rep)
	end
	if rep and Kit.RegisterShell and frame == cf then
		-- its rail on the kit's list of dressed windows: the rail Edit Layout
		-- lights while the chat is dragged, and its shade (a chat window has
		-- no header: its plate in Edit Layout covers the whole window)
		Kit:RegisterShell(frame, { outer = rep })
	end
	-- the window's rail on its outline (the button column's: SkinChatFrame)
	if rep and frame == cf then
		shade.anchor[cf], shade.rail[cf] = BackdropRect(cf, background), rep
		ShadeLater(cf, rep)
	end
	return rep
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

-- (one function for every tab: a closure made per call was garbage at each
-- show of a window or a tab)
local function RaiseTab(tab)
	local above = STRATA_ORDER[math.min(ChatStrataTop() + 1, #STRATA_ORDER)]
	if tab:GetFrameStrata() ~= above then
		tab:SetFrameStrata(above)
	end
	DockInFront(above)
end

local function TabInFront(tab, cf)
	if raisingTab or not (active and tab and cf) then
		return
	end
	raisingTab = true
	pcall(RaiseTab, tab)
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
	Perf.HookScript(tab, "OnShow", function(self) TabInFront(self, cf) end)
	Perf.HookScript(cf, "OnShow", function() TabInFront(tab, cf) end)
	TabInFront(tab, cf)
end

-- (`cf`: the window the tab stands on; nil for a minimized window's card,
-- standing alone)
local function SkinTab(tab, cf)
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
	-- the card's shade (the plain card: the lit one lies on the same rect):
	-- on its window, its foot open and cut at the rail's inner edge; alone,
	-- the whole nine
	local card = plain or open
	if card and cf then
		shade.Cut("tab", tab, cf, card, "b")
	elseif card then
		ShadeLater(tab, card)
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

-- The column's three game buttons (0.17.0; the user's pick C of
-- BuildData/output/chat_menu_sketch: "the game's own column, dressed"): the
-- chat menu, Channels and Friends in the whisper header's look -- the kit's
-- round rim (ChatColumnButton) on a rect of ours centred in the column, the
-- palette's inner-panel disc in its opening and our glyph on it (the rim's
-- icon: Kit:Slot fits it) -- over the game's button, which keeps every click,
-- menu and tooltip (the rim lights with the button's own hover and press).
-- The game's own art faded; the friends count raised over the disc. Each
-- follows its button's show and hide (regions and a frame of it).
local COLUMN_SIZE = 22
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- hidden: art of the game's that its animations bring back (the Friends
-- button's quick-join picture, its flash and count: the toast animations
-- set their alpha in the engine, past a fade -- user, 2026-10-04: "there are
-- two borders and backgrounds under the Social button", "remove the old
-- one"). The game never shows or hides them itself, so they are hidden while
-- ours shows and shown again with the game's look: one write each, no fight.
local function SkinColumnButton(button, art, glyph, fade, count, hidden)
	if not (button and art) or button.melloRep ~= nil then
		return
	end
	local W = MelloUI.Widgets
	local rect = CreateFrame("Frame", nil, button)
	rect:SetSize(COLUMN_SIZE, COLUMN_SIZE)
	rect:SetPoint("CENTER")
	rect:EnableMouse(false)
	local icon = button:CreateTexture(nil, "ARTWORK", nil, 2)
	W.Glyph(icon, glyph)
	W.Paint(icon, "text", "vertex")
	local disc = button:CreateTexture(nil, "ARTWORK", nil, 1)
	disc:SetTexture(ROUND_MASK)
	disc:SetAllPoints(icon)
	W.Paint(disc, "innerPanel", "vertex", 0.95)
	local layer, sub
	if count then
		layer, sub = count:GetDrawLayer()
	end
	local function Ours(on)
		icon:SetShown(on)
		disc:SetShown(on)
		if count then
			count:SetDrawLayer(on and "OVERLAY" or (layer or "BORDER"), on and 7 or (sub or 0))
		end
		for _, region in ipairs(hidden or {}) do
			region:SetShown(not on)
		end
	end
	Ours(false)
	local rep = Replace(art, { as = "ChatColumnButton", button = button, rect = rect, icon = icon, alsoFade = fade })
	button.melloRep = rep or false
	if not rep then
		return
	end
	local enable, disable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if enable then
			enable(...)
		end
		Ours(true)
	end
	rep.onDisable = function(...)
		if disable then
			disable(...)
		end
		Ours(false)
	end
	Ours(active)
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
	if edit.melloRep then
		ShadePlate(edit, edit.melloRep)
	end
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
		local column = SkinBordered(cf.buttonFrame, name .. "ButtonFrame")
		StoneBackground(cf, _G[name .. "ButtonFrameBackground"], cf.buttonFrame)
		SkinIconButton(cf.buttonFrame.minimizeButton)
		NoFade(cf.buttonFrame)
		shade.Cut("column", cf.buttonFrame, cf, column, shade.ColumnOpen(cf))
	end
	SkinTab(_G[name .. "Tab"], cf)
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
	-- the column's three (the Chat module's Chat Buttons shows them)
	local menu, channel, social = _G.ChatFrameMenuButton, _G.ChatFrameChannelButton, _G.QuickJoinToastButton
	if menu and menu.GetNormalTexture then
		SkinColumnButton(menu, menu:GetNormalTexture(), "chat",
			{ menu:GetPushedTexture(), menu:GetDisabledTexture(), menu:GetHighlightTexture() })
	end
	if channel and channel.GetNormalTexture then
		SkinColumnButton(channel, channel:GetNormalTexture(), "channels",
			{ channel.Icon, channel:GetPushedTexture(), channel:GetHighlightTexture() })
	end
	if social and social.FriendsButton then
		local hidden = {}
		for _, key in ipairs({ "QueueButton", "FlashingLayer", "QueueCount" }) do
			if social[key] and social[key].SetShown then
				hidden[#hidden + 1] = social[key]
			end
		end
		SkinColumnButton(social, social.FriendsButton, "friends", nil, social.FriendCount, hidden)
	end
	for _, key in ipairs({ "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }) do
		SkinIconButton(_G[key])
	end
end

-- The Chat module's Background Opacity while Chat Tweaks is off (user,
-- 2026-09-26: with Reskin only a new character's stone and parchment stayed
-- at the game's faint default): Chat's own code, run from here; it does
-- nothing while Chat Tweaks is on, which applies it alone
local function ChatAlpha(on)
	local chat = MelloUI:GetModule("Chat")
	if chat and chat.ReskinAlpha then
		chat.ReskinAlpha(on)
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
	-- a button column moved to the window's other side: its shade follows
	local setSide = "FCF_SetButtonSide"
	if type(_G[setSide]) == "function" then
		hooksecurefunc(setSide, shade.ColumnMoved)
	end
	for _, fn in ipairs({ "FCF_OpenNewWindow", "FCF_OpenTemporaryWindow", "FCF_DockFrame", "FCF_UnDockFrame" }) do
		if _G[fn] then
			-- (a whisper window: the opacity too, as Chat Tweaks does it)
			local whisper = fn == "FCF_OpenTemporaryWindow"
			hooksecurefunc(fn, function()
				if active then
					SkinAll()
					if whisper then
						ChatAlpha(true)
					end
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
	-- (a shade that waited while the reskin was off)
	ShadeSeen()
	Kit:Cover("chat")
	InkFollows()
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
	InkFollows()
end

function M:OnEnable(db)
	self.db = db
	if ChatFrame1 then
		Activate()
	end
	if active then
		ChatAlpha(true)
	end
	-- the Chat module's Border Opacity (its setting, on the bus): the rails
	MelloUI:On("setting", function(module, key)
		if module == "Chat" and key == "borderAlpha" then
			Border.LayAll()
		end
	end, "ChatPanel border opacity")
end

function M:OnDisable()
	Deactivate()
	ChatAlpha(false)
	MelloUI:Off("ChatPanel border opacity", "setting")
end

--------------------------------------------------------------------------------
-- /chdump [n] [frames|reps]: a chat window's art (n = 1 by default). Opens
-- the copy window. Also /chdump tabs, shade, edit (below).
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

-- /chdump shade: each chat window's, tab's and edit box's shade (made, or
-- waiting for its first show) and the frame that draws it against its own
local function DumpShade()
	MelloUI:Print("chat shade: on %s, strength %.2f, partners made %d, edit boxes %s, reskin active %s",
		tostring(Kit.ShadeOn and Kit:ShadeOn(SHADE_AREA)), Kit.ShadeStrength and Kit:ShadeStrength() or 0,
		Kit.shadeState and Kit.shadeState.made[SHADE_AREA] or 0, shade.editTop and "on top" or "below", tostring(active))
	local function One(label, root)
		if not root then
			return
		end
		local el = shade.made[root]
		local host = el and el.host
		local rec = shade.cut[root]
		if host then
			MelloUI:Print("%-24s made: drawn at %s %d (its frame %s %d), shown %s%s", label, tostring(host:GetFrameStrata()),
				host:GetFrameLevel(), tostring(root:GetFrameStrata()), root:GetFrameLevel(), tostring(host:IsVisible()),
				rec and (", open " .. tostring(rec.opts.open) .. ", cut " .. (rec.mask and "on" or "none")) or "")
		elseif el then
			MelloUI:Print("%-24s made, nothing drawn yet", label)
		else
			MelloUI:Print("%-24s %s", label, shade.pending[root] and "waiting for its first show" or "none")
		end
	end
	for _, cf in ipairs(ChatFrames()) do
		local name = cf:GetName() or "?"
		One(name, cf)
		One(name .. "ButtonFrame", cf.buttonFrame)
		One(name .. "Tab", _G[name .. "Tab"])
		One(name .. "EditBox", cf.editBox)
		One(name .. "Minimized", _G[name .. "Minimized"])
	end
end

-- /chdump edit: the main window's edit box and what the game lays its text
-- by (ChatFrameEditBoxMixin:UpdateHeader: the text's left inset is 15 + the
-- header's width + its suffix's; a header measured wider than half the box
-- is cut to half, the suffix shown -- the text then starts mid-line); every
-- read guarded (a secret or refused one prints "?")
local function DumpEdit()
	local cf = DEFAULT_CHAT_FRAME
	local box = cf and cf.editBox
	if not box then
		MelloUI:Print("no edit box")
		return
	end
	local Num = MelloUI.Safe.Number
	local function N(obj, method, ...)
		if not (obj and obj[method]) then
			return "-"
		end
		local ok, v = pcall(obj[method], obj, ...)
		v = ok and Num(v) or nil
		return v and string.format("%.1f", v) or "?"
	end
	local function T(obj, method)
		local ok, v = pcall(obj[method], obj)
		return ok and type(v) == "string" and not MelloUI.Safe.IsSecret(v) and v or "?"
	end
	local function Points(obj)
		local out = {}
		for i = 1, obj:GetNumPoints() do
			local ok, p, rel, rp, x, y = pcall(obj.GetPoint, obj, i)
			if ok then
				local rn = rel and (rel.GetName and rel:GetName() or rel.GetDebugName and rel:GetDebugName()) or "?"
				out[#out + 1] = string.format("%s>%s:%s(%s,%s)", tostring(p), tostring(rn), tostring(rp),
					tostring(Num(x) or "?"), tostring(Num(y) or "?"))
			end
		end
		return table.concat(out, " ")
	end
	local function Font(fs)
		local ok, face, size, flags = pcall(fs.GetFont, fs)
		local okO, object = pcall(fs.GetFontObject, fs)
		local oname = okO and object and object.GetName and object:GetName() or "?"
		return string.format("%s %s %s (object %s)", ok and tostring(face) or "?", ok and tostring(Num(size) or "?") or "?",
			ok and tostring(flags) or "?", tostring(oname))
	end
	local okI, l, r, t, b = pcall(box.GetTextInsets, box)
	MelloUI:Print("edit box %s: width %s, shown %s, insets L %s R %s T %s B %s, justify %s, chat type %s, language %s",
		tostring(box:GetName()), N(box, "GetWidth"), tostring(box:IsShown()), okI and tostring(Num(l) or "?") or "?",
		okI and tostring(Num(r) or "?") or "?", okI and tostring(Num(t) or "?") or "?", okI and tostring(Num(b) or "?") or "?",
		T(box, "GetJustifyH"), tostring(box:GetAttribute("chatType")), tostring(box.language))
	MelloUI:Print("  its font: %s", Font(box))
	local header = _G[box:GetName() .. "Header"]
	local suffix = _G[box:GetName() .. "HeaderSuffix"]
	if header then
		MelloUI:Print("  header \"%s\": width %s (string %s), left %s right %s, shown %s, points %s",
			T(header, "GetText"), N(header, "GetWidth"), N(header, "GetStringWidth"), N(header, "GetLeft"),
			N(header, "GetRight"), tostring(header:IsShown()), Points(header))
		MelloUI:Print("  header font: %s", Font(header))
	end
	if suffix then
		MelloUI:Print("  suffix \"%s\": shown %s, width %s, points %s", T(suffix, "GetText"), tostring(suffix:IsShown()),
			N(suffix, "GetWidth"), Points(suffix))
	end
	local lang = box.languageHeader
	if lang then
		MelloUI:Print("  the game's language header: shown %s, width %s", tostring(lang:IsShown()), N(lang, "GetWidth"))
	end
	local Chat = MelloUI:GetModule("Chat")
	MelloUI:Print("  Chat module on %s, Chat Buttons %s (the language you speak at the line's right end)",
		tostring(Chat and Chat.isEnabled), tostring(Chat and Chat.db and Chat.db.chatButtons))
end

SlashCmdList.MELLOCHDUMP = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg:find("^edit") then
		MelloUI:ClearLog()
		DumpEdit()
		MelloUI:ShowLog("chdump edit")
		return
	end
	if msg:find("^tab") then
		MelloUI:ClearLog()
		DumpTabs()
		MelloUI:ShowLog("chdump tabs")
		return
	end
	if msg:find("^shade") then
		MelloUI:ClearLog()
		DumpShade()
		MelloUI:ShowLog("chdump shade")
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
