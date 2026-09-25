--------------------------------------------------------------------------------
-- MelloUI - Battlefield Map Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): The battlefield minimap's frame in the kit (the map itself untouched).
--
-- This client's battlefield minimap is BattlefieldMapFrame of the
-- load-on-demand Blizzard_BattlefieldMap (its Mainline files: the client is
-- of the mainline family): a MapCanvasFrameTemplate map, 300 x 200, whose
-- ScrollContainer is the map, and a BorderFrame (HIGH strata, on the map's
-- rect) carrying eight battlefieldminimap-border-* textures that reach past
-- the map's edge, and a close button. Its name is not on the map: it is
-- BattlefieldMapTab, a chat-style tab (ChatFrameTab file art, the
-- "Battlefield Minimap" label) standing over the map's top-left corner, which
-- the game fades in while the pointer rests on the map.
--
-- Dressed as the flight map is (Modules/TaxiPanel.lua), the frame only:
--   the border       the outer double rail (the window rule), edges only,
--                    grown outward so its inner bevel ends ON the map's edge
--                    and never lies on it; plain corners, since the gem
--                    corners reach some 8 x 15 px into the rect and would sit
--                    on the map's corners
--   the close button the kit's close states on its normal texture
--   the title        the tab: the TB6 card (the chat tabs' CT2, the same
--                    art) on its visible part, its label centred on the card
--                    in the kit's title face (WINDOW-RULES 2c: it is the
--                    map's title)
-- Everything of ours is a child of the BorderFrame or of the tab, so the
-- game's opacity setting (it sets the BorderFrame's alpha) and the tab's
-- fade reach our pieces as they reach the game's.
--
-- The map is a PICTURE: its canvas, pins, fog and players are never faded,
-- covered, tinted or moved, and the opacity is never read back into the map
-- or changed. Nothing of the game's is replaced or re-scripted: post-hooks,
-- HookScript and our own event frame; what we keep lives in weak side
-- tables. Switched off, every piece is hidden, the border art comes back and
-- the tab's label is put back where, and in the font, it was. The frame is
-- dressed on the map's first show, not at login (user, 2026-09-24: "dress
-- rarely used windows on first open"; see Sync).
--
-- /bfmapdump [art | frames | reps]: what the battlefield map is made of on
-- this client and what the skin made of it.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("BattlefieldMapPanel")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("BattlefieldMapPanel", {
	title = "Battlefield Map Kit",
	desc = "The battlefield minimap's frame in the kit (the map itself untouched).",
	window = { label = "Battlefield map", desc = "The battlefield minimap's frame in the kit (the map itself untouched).", tab = "Windows",
		addon = "Blizzard_BattlefieldMap", firstOpen = true },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local ADDON = "Blizzard_BattlefieldMap"
local TAB_TOP_INSET = 8     -- the ChatFrameTab file art: the tab's visible part starts this far under its top (the chat tabs' own inset)

local skin = nil            -- { reps = {}, outer, close, tab, sizer, text, borderArt = {} }
local active = false
local hooked = setmetatable({}, { __mode = "k" })       -- [frame] = true once its OnShow is hooked
local dressed = setmetatable({}, { __mode = "k" })      -- [tab] = true once its card is made
local textPoints = setmetatable({}, { __mode = "k" })   -- [label] = the game's anchors, while the kit holds it on the card

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

local function Window()
	local f = _G.BattlefieldMapFrame
	if type(f) == "table" and f.GetObjectType and f.HookScript then
		return f
	end
	return nil
end

local function Tab()
	local t = _G.BattlefieldMapTab
	if type(t) == "table" and t.GetObjectType and t.HookScript then
		return t
	end
	return nil
end

local function Loaded()
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, ADDON)
		return ok and loaded and true or false
	end
	return Window() ~= nil
end

--------------------------------------------------------------------------------
-- Finding the parts
--------------------------------------------------------------------------------

-- The map canvas (the ScrollContainer: the rect the rail must never reach
-- into), else the frame itself
local function MapRect(f)
	return f.ScrollContainer or f
end

-- The border art: the BorderFrame's eight pieces by key (and the older
-- file's close button corner), then any other game texture of the
-- BorderFrame (never the map's: they live on the canvas, not here)
local BORDER_KEYS = { "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Top", "Bottom", "Left", "Right", "CloseButtonBorder" }

local function BorderArt(bf)
	local list, seen = {}, {}
	local function Add(region)
		if region and not seen[region] and region.GetObjectType and region:GetObjectType() == "Texture" and not region.kitPiece then
			seen[region] = true
			list[#list + 1] = region
		end
	end
	for _, key in ipairs(BORDER_KEYS) do
		Add(bf[key])
	end
	for _, region in ipairs({ bf:GetRegions() }) do
		Add(region)
	end
	return list
end

-- The tab's label: its ButtonText key, else its font string
local function TabText(tab)
	if not tab then
		return nil
	end
	local fs = tab.Text or (tab.GetFontString and tab:GetFontString())
	if type(fs) == "table" and fs.GetObjectType and fs:GetObjectType() == "FontString" then
		return fs
	end
	return nil
end

--------------------------------------------------------------------------------
-- Building the skin
--------------------------------------------------------------------------------

local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local ok, rep, key = pcall(Kit.Replace, Kit, region, opts)
	if not ok then
		MelloUI:Notice("Battlefield map: could not dress %s (%s)", tostring(opts and opts.as), tostring(rep))
		return nil
	end
	if not rep then
		if key then
			MelloUI:Notice("Battlefield map: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- An invisible region of OUR frame to hand to Kit:Replace where the game has
-- no one piece to stand in for (the rail over eight loose border textures)
local function Anchor(host)
	local tex = host:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints(host)
	tex:SetColorTexture(0, 0, 0, 0)
	tex.kitPiece = true
	return tex
end

-- The rail's rect: the map grown by how far the outer rail reaches into its
-- rect (Kit:OuterRailInset), so the rail's inner bevel ends on the map's
-- edge. A frame of ours under the BorderFrame (its alpha is the opacity).
local function RailRect(bf, map)
	local rect = CreateFrame("Frame", nil, bf)
	rect:EnableMouse(false)
	local ins = Kit:OuterRailInset()
	rect:SetPoint("TOPLEFT", map, "TOPLEFT", -ins[1], ins[3])
	rect:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", ins[2], -ins[4])
	return rect
end

-- The tab: the TB6 card on its visible part (the chat tabs' own recipe, the
-- same ChatFrameTab file art), the game's pieces and its highlight faded;
-- the card is a child of the tab, so it fades in and out with it.
local function SkinTab(tab)
	if not tab or not (tab.Left and tab.Middle and tab.Right) or dressed[tab] then
		return
	end
	dressed[tab] = true
	local sizer = CreateFrame("Frame", nil, tab)
	sizer:EnableMouse(false)
	sizer:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -TAB_TOP_INSET)
	sizer:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
	skin.sizer = sizer
	local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
	skin.tab = Replace(tab.Left, { as = "uiframe-tab-left", rect = sizer, parent = tab, button = tab,
		alsoFade = { tab.Middle, tab.Right, hl } })
	-- the label held centred on the card (the game anchors it 5 px under
	-- the tab's middle, on its own art), re-applied after the game's own
	-- SetPoint, only while the kit is on
	local text = TabText(tab)
	skin.text = text
	if text then
		local function Steady()
			if not active or not skin.tab or textPoints[text] == nil then
				return
			end
			if skin.steadying then
				return
			end
			skin.steadying = true
			pcall(function()
				text:ClearAllPoints()
				text:SetPoint("CENTER", sizer, "CENTER", 0, 0)
			end)
			skin.steadying = nil
		end
		skin.Steady = Steady
		hooksecurefunc(text, "SetPoint", Steady)
	end
end

local function Build()
	local f = Window()
	if not f or (skin and skin.built) then
		return
	end
	local bf = f.BorderFrame
	skin = skin or { reps = {}, borderArt = {} }
	skin.built = true
	if bf then
		local host = CreateFrame("Frame", nil, bf)
		host:SetAllPoints(bf)
		host:EnableMouse(false)
		skin.host = host
		skin.railRect = RailRect(bf, MapRect(f))
		skin.borderArt = BorderArt(bf)
		-- the outer rail, edges only (a body would lie on the map), plain
		-- corners (skip: the gem corners reach into the map's corners), at
		-- the BorderFrame's own level and strata: it lies outside the map's
		-- rect, so the level decides nothing over the map
		skin.outer = Replace(Anchor(host), { as = "NineSlicePanelTemplate", parent = bf, rect = skin.railRect, body = false,
			skip = "tl tr bl br", noFade = true, alsoFade = skin.borderArt })
		local close = bf.CloseButton
		local normal = close and close.GetNormalTexture and close:GetNormalTexture()
		if normal then
			skin.close = Replace(normal, { as = "RedButton-Exit", button = close, alsoFade = Kit:OtherTextures(close, normal) })
		end
	end
	SkinTab(Tab())
end

--------------------------------------------------------------------------------
-- On / off
--------------------------------------------------------------------------------

-- The tab's label in the title face, held on the card (or back as it was).
-- The game sizes the tab to its label when the map shows (its OnShow): a
-- label that changed size while the tab is up is measured again then, or at
-- once when the tab is shown now.
local function Resize(tab)
	if tab and tab:IsShown() and type(_G.PanelTemplates_TabResize) == "function" then
		pcall(_G.PanelTemplates_TabResize, tab, 0)
	end
end

local function HoldLabel(on)
	local text, tab = skin and skin.text, Tab()
	if not text then
		return
	end
	if on then
		if textPoints[text] == nil then
			local points = {}
			for i = 1, text:GetNumPoints() do
				points[i] = { text:GetPoint(i) }
			end
			-- the template gives the label a fixed 8 px height (its 10 px
			-- font overhangs it); the title face is half again as tall, so
			-- the label sizes itself while the kit holds it (put back after)
			local ok, h = pcall(text.GetHeight, text)
			points.height = (ok and type(h) == "number" and not Secret(h)) and h or nil
			textPoints[text] = points
		end
		Kit:TitleFont(text, true)
		pcall(text.SetHeight, text, 0)
		if skin.Steady then
			skin.Steady()
		end
	elseif textPoints[text] then
		local points = textPoints[text]
		textPoints[text] = nil
		Kit:TitleFont(text, false)
		text:ClearAllPoints()
		for _, pt in ipairs(points) do
			text:SetPoint(unpack(pt))
		end
		if points.height then
			pcall(text.SetHeight, text, points.height)
		end
	end
	Resize(tab)
end

local function Activate()
	if active or not Window() then
		return
	end
	Build()
	if not skin then
		return
	end
	active = true
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	HoldLabel(true)
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	if skin then
		for _, rep in ipairs(skin.reps) do
			rep:Disable()
		end
	end
	HoldLabel(false)
end

-- the map shown now (secret-safe)
local function IsOpen(f)
	local ok, shown = pcall(f.IsShown, f)
	return ok and not Secret(shown) and shown == true
end

local Sync

-- The map or its tab shown (a zone with a battlefield map, the key binding):
-- dressed now if this is the map's first show; else the label held on the
-- card again (the game's OnShow re-sizes the tab). Dressing makes frames of
-- ours only and moves nothing of the game's but the tab's label (the map is
-- no protected frame): at once, in combat too, as it always was here.
local function OnShow()
	if M.isEnabled and not active then
		Sync()
		return
	end
	if not active or not skin then
		return
	end
	if skin.Steady then
		skin.Steady()
	end
end

local function Hook()
	for _, frame in ipairs({ Window() or false, Tab() or false }) do
		if frame and not hooked[frame] then
			hooked[frame] = true
			Perf.HookScript(frame, "OnShow", OnShow)
		end
	end
end

-- (user, 2026-09-24: "dress rarely used windows on first open") nothing of
-- the skin is made while the map has never been shown this session: it is
-- dressed on its first show (the OnShow hook, before the first frame is
-- drawn), or at once when it is up already (a /reload with the map open, the
-- game bringing it back as the zone loads), then kept for the session. The
-- hooks above only listen until then.
Sync = function()
	Hook()
	local f = Window()
	if M.isEnabled and f and ((skin and skin.built) or IsOpen(f)) then
		Activate()
	else
		Deactivate()
	end
end

-- The map comes with its own load-on-demand addon: hooked when it loads, or
-- at once when it is already in; dressed on its first show
local watcher = CreateFrame("Frame")
Perf.SetScript(watcher, "OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name ~= ADDON then
		return
	end
	Sync()
	if Window() then
		watcher:UnregisterEvent("ADDON_LOADED")
	end
end)

function M:OnEnable(db)
	self.db = db
	if not Window() then
		watcher:RegisterEvent("ADDON_LOADED")
	end
	Sync()
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /bfmapdump [art | frames | reps]: the battlefield map on this client. No
-- argument: whether the addon is loaded, the parts found (by key) and what
-- the skin made of each, the map's own state (it must read untouched: never
-- faded by the kit), the opacity as the game keeps it, the rail's rect
-- against the map's (the rail must end at the map's edge), the close button
-- and the tab with its label's font and place. "art" / "frames" / "reps":
-- the kit's window dump. Opens the copy window.
--------------------------------------------------------------------------------

local function Describe(obj)
	if not obj then
		return "-"
	end
	local okN, name = pcall(obj.GetName, obj)
	if okN and name and not Secret(name) then
		return name
	end
	local okD, dname = pcall(obj.GetDebugName, obj)
	if okD and dname and not Secret(dname) then
		return dname
	end
	return "[secret name]"
end

local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.1f", v) or "?"
end

local function RectText(obj)
	if not obj then
		return "-"
	end
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if ok and l and not Secret(l) and not Secret(w) then
		return string.format("x=%s y=%s w=%s h=%s", Num(l), Num(b), Num(w), Num(h))
	end
	return "(no rect)"
end

local function Shown(obj)
	local ok, s = pcall(obj.IsShown, obj)
	return (ok and not Secret(s)) and tostring(s) or "?"
end

local function AlphaText(obj)
	local ok, a = pcall(obj.GetAlpha, obj)
	return (ok and not Secret(a)) and string.format("%.2f", a) or "?"
end

local function KeyOf(parent, obj)
	for _, key in ipairs(BORDER_KEYS) do
		if parent[key] == obj then
			return key
		end
	end
	return nil
end

local function DumpMap(f)
	local bf = f.BorderFrame
	local map = MapRect(f)
	MelloUI:Print("BattlefieldMapFrame: shown %s, %s, strata %s, level %s; kit %s, pieces %d", Shown(f), RectText(f),
		tostring(f:GetFrameStrata()), tostring(f:GetFrameLevel()), active and "on" or "off", skin and #skin.reps or 0)
	MelloUI:Print("  template parts: ScrollContainer %s, BorderFrame %s, CloseButton %s", tostring(f.ScrollContainer ~= nil),
		tostring(bf ~= nil), tostring(bf and bf.CloseButton ~= nil))
	-- the map: found, untouched?
	MelloUI:Print("  map (ScrollContainer): %s alpha %s, faded by the kit %s -- never touched", RectText(map), AlphaText(map),
		tostring(Kit.faded[map] == true))
	local child = f.ScrollContainer and f.ScrollContainer.Child
	if child then
		MelloUI:Print("  map canvas child: %s alpha %s, faded by the kit %s", RectText(child), AlphaText(child), tostring(Kit.faded[child] == true))
	end
	-- the opacity as the game keeps it (read only)
	local opts = _G.BattlefieldMapOptions
	local opacity = type(opts) == "table" and opts.opacity or nil
	MelloUI:Print("  opacity setting %s (the game's), BorderFrame alpha %s (1 - opacity; our pieces are its children)",
		Num(opacity), bf and AlphaText(bf) or "-")
	if bf then
		MelloUI:Print("  BorderFrame: %s strata %s level %s", RectText(bf), tostring(bf:GetFrameStrata()), tostring(bf:GetFrameLevel()))
		for _, region in ipairs({ bf:GetRegions() }) do
			if not region.kitPiece then
				local okL, layer = pcall(region.GetDrawLayer, region)
				local art = region.GetObjectType and region:GetObjectType() == "Texture" and tostring(Kit:ArtKey(region) or "?") or "(font string)"
				MelloUI:Print("   region key=%s %s layer %s alpha %s shown %s -> %s", tostring(KeyOf(bf, region)), art,
					okL and tostring(layer) or "?", AlphaText(region), Shown(region),
					Kit.faded[region] and "faded: the outer rail stands in" or "the game's")
			end
		end
	end
	if skin and skin.railRect then
		MelloUI:Print("  rail rect %s (the map grown by the outer rail's reach; its inner bevel on the map's edge)", RectText(skin.railRect))
		local rep = skin.outer
		MelloUI:Print("  outer rail: %s, shown %s, holder %s", rep and "made" or "NOT made", rep and Shown(rep.object) or "-",
			rep and RectText(rep.object) or "-")
	else
		MelloUI:Print("  outer rail: not built")
	end
	local close = bf and bf.CloseButton
	if close then
		MelloUI:Print("  close button: %s level %s, kit %s", RectText(close), tostring(close:GetFrameLevel()),
			tostring(skin and skin.close ~= nil and skin.close.object:IsShown()))
	end
end

local function DumpTab()
	local tab = Tab()
	if not tab then
		MelloUI:Print("  tab (BattlefieldMapTab): not found")
		return
	end
	MelloUI:Print("  tab %s: shown %s, alpha %s (the game fades it in on hover), %s, strata %s; card %s", Describe(tab), Shown(tab),
		AlphaText(tab), RectText(tab), tostring(tab:GetFrameStrata()), tostring(skin and skin.tab ~= nil and skin.tab.object:IsShown()))
	local text = TabText(tab)
	if text then
		local okT, t = pcall(text.GetText, text)
		local okF, face, size = pcall(text.GetFont, text)
		local okP, point, rel = pcall(text.GetPoint, text, 1)
		MelloUI:Print("  title (the tab's label): text %s, font %s %s, title face %s, anchored %s on %s (the card: %s)",
			(okT and type(t) == "string" and not Secret(t)) and t or "?",
			(okF and type(face) == "string" and not Secret(face)) and (face:match("([^\\/]+)$") or face) or "?",
			okF and Num(size) or "?", tostring(text.melloFontSaved ~= nil), okP and tostring(point) or "?",
			okP and rel and Describe(rel) or "-", skin and skin.sizer and RectText(skin.sizer) or "-")
	end
end

SLASH_MELLOBFMAPDUMP1 = "/bfmapdump"
SlashCmdList.MELLOBFMAPDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	MelloUI:ClearLog()
	local f = Window()
	if not f then
		local lod = "?"
		if C_AddOns and C_AddOns.IsAddOnLoadOnDemand then
			local ok, v = pcall(C_AddOns.IsAddOnLoadOnDemand, ADDON)
			lod = ok and tostring(v) or "?"
		end
		MelloUI:Print("/bfmapdump: no BattlefieldMapFrame yet (%s loaded %s, load on demand %s): open the battlefield map once (its key binding) and try again",
			ADDON, tostring(Loaded()), lod)
	else
		if not (skin and skin.built) then
			MelloUI:Print("/bfmapdump: the battlefield map is not dressed yet (the kit dresses it the first time it shows: open it once for the kit's side)")
		end
		if msg == "art" or msg == "frames" or msg == "reps" then
			Kit:DumpWindow(f, skin, msg ~= "art" and msg or nil)
		else
			DumpMap(f)
			DumpTab()
			MelloUI:Print("  inked strings: none (no parchment on this frame)")
		end
	end
	MelloUI:ShowLog("bfmapdump " .. msg)
end
