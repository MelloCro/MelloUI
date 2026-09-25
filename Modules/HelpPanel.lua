--------------------------------------------------------------------------------
-- MelloUI - Help Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): the help / customer support window in the painted kit
-- (Modules/Kit.lua), on the game's own layout, by the rule book
-- (docs/WINDOW-RULES.md).
--
-- This client's support window is HelpFrame of Blizzard_HelpFrame: a
-- DefaultPanelTemplate window (974 x 628, no portrait) whose whole body is
-- an embedded web page, HelpBrowser (a Browser at HIGH strata, the
-- knowledge base and the tickets are pages of the support site), framed by
-- its own BrowserInset (an InsetFrameTemplate at MEDIUM). Dressed:
--
--   the window shell     outer double rail with gem corners grown outward,
--                        the page stone inside it, the title plate on the
--                        rail with the window's title ON it in the title
--                        face (2c), the kit's close button
--                        (Kit:SkinWindowShell); no ring, as the window has
--                        no portrait (a client whose window has one gets the
--                        ring with the icon at the medallion size on the
--                        disc, 2b, and a help icon should it be blank)
--   the browser          NEVER covered, dimmed or touched: its BrowserInset
--                        is the list box L1 round it (single rail, the list
--                        stone under the palette's inner panel -- 2e: the
--                        knowledge base's text and the "unavailable" notice
--                        lie on that panel while the page loads), a holder
--                        of the window at MEDIUM, so the HIGH browser is
--                        always drawn over everything of ours
--   buttons              red plates (B1) with readable labels (the browser
--                        settings' Delete Cookies button too)
--   the ticket status    TicketStatusFrame (the small "open ticket" notice
--                        by the minimap): its black tooltip box faded, the
--                        single rail with stone under the inner panel on the
--                        box's rect instead, under the frame's two lines
--
-- A client with an older, small help window (no NineSlice: a dialog box
-- with a header) gets the small-window dress instead: the single rail and
-- stone under the inner panel round it, its box faded, the header band on
-- the header plate with the title in the title face, the kit's close
-- button, red plates, and every inset on the dark panel (the knowledge
-- base's text).
--
-- Taint: nothing of the game's is replaced or re-scripted, no ticket,
-- survey or browser function is ever called; post-hooks and HookScript
-- only, our state in weak side tables. The windows are never moved or
-- reparented. Switched off, every piece is hidden and the game's art faded
-- back in: the windows are the game's again. Each window is dressed the
-- first time it shows, never at login (Activate).
--
-- /helpdump [frames | reps | regions | ticket]: what the windows are made of
-- on this client and what the skin made of them, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("HelpPanel")
-- a handler made once and run for many asks, wrapped once: its time stays
-- on this file's own /melloperf row (review, 2026-09-24)
local Shared = Perf.Shared or function(_, fn) return fn end
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("HelpPanel", {
	title = "Help Kit",
	desc = "The help / customer support window in the kit.",
	window = { label = "Help window", desc = "The help / customer support window in the kit.", tab = "Windows",
		addon = "Blizzard_HelpFrame", firstOpen = true },
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local ADDON = "Blizzard_HelpFrame"
local HELP_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"   -- a portrait ring left blank by the game gets this (2c: never empty)

local skin = nil          -- { reps = {}, followers = {}, small = the small-window dress, browser, ring, portrait }
local ticket = nil        -- the ticket status box: { nine, art = {}, box }
local active = false
local hooked = setmetatable({}, { __mode = "k" })       -- [frame] = true once its OnShow is hooked

local portraitFilled = setmetatable({}, { __mode = "k" })   -- [texture] = { art = set by us }

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local Secret = MelloUI.Safe.IsSecret

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local ok, rep, key = pcall(Kit.Replace, Kit, region, opts)
	if not ok then
		MelloUI:Notice("Help kit: could not dress %s (%s)", tostring(opts and opts.as), tostring(rep))
		return nil
	end
	if not rep then
		if key then
			MelloUI:Notice("Help kit: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

local function Compact(...)
	local list = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if v then
			list[#list + 1] = v
		end
	end
	return list
end

local function NameOf(obj)
	if not obj then
		return nil
	end
	local ok, n = pcall(obj.GetName, obj)
	if ok and type(n) == "string" and not Secret(n) then
		return n
	end
	return nil
end

local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	if ok and type(text) == "string" and not Secret(text) and text ~= "" then
		return text
	end
	return nil
end

local function Shown(obj)
	local ok, s = pcall(obj.IsShown, obj)
	return ok and not Secret(s) and s == true
end

local function ObjectType(obj)
	local ok, t = pcall(obj.GetObjectType, obj)
	return ok and t or nil
end

local function Window()
	return _G.HelpFrame
end

-- The embedded web page: the window's Browser (HelpBrowser), else the first
-- Browser among its children. The one frame nothing of ours may cover.
local function Browser(f)
	if not f then
		return nil
	end
	local b = f.Browser or _G.HelpBrowser
	if b then
		return b
	end
	for _, child in ipairs({ f:GetChildren() }) do
		if ObjectType(child) == "Browser" then
			return child
		end
	end
	return nil
end

-- A portrait only when the window shows one (DefaultPanelTemplate has none)
local function Portrait(f)
	local pc = f.PortraitContainer
	local p = (pc and pc.portrait) or f.portrait or f.Icon
	if p and pc and not Shown(pc) then
		return nil
	end
	return p
end

-- the window's title string, whatever this client calls it
local function TitleString(f)
	local tc = f.TitleContainer
	local header = f.Header
	for _, fs in ipairs(Compact(tc and tc.TitleText, f.TitleText, header and header.Text, _G.HelpFrameTitleText, f.Title)) do
		if ObjectType(fs) == "FontString" then
			return fs
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- The portrait, where the window has one (WINDOW-RULES 2b: at the class
-- medallion's size, on the dark disc; 2c: never an empty ring)
--------------------------------------------------------------------------------
local function PortraitArt(t)
	local ok, file = pcall(t.GetTexture, t)
	if ok and not Secret(file) and file ~= nil and (type(file) == "number" and file > 0 or type(file) == "string" and file ~= "") then
		return file
	end
	return nil
end

local function SkinPortrait(f, ring, portrait)
	if not (ring and portrait) then
		return
	end
	skin.ring, skin.portrait = ring, portrait
	ring.onEnable = function()
		if not PortraitArt(portrait) then
			pcall(portrait.SetTexture, portrait, HELP_ICON)
			portraitFilled[portrait] = { art = true }
		end
		pcall(Kit.FitPortrait, Kit, portrait, ring)
	end
	ring.onDisable = function()
		pcall(Kit.UnfitPortrait, Kit, portrait)
		if portraitFilled[portrait] then
			pcall(portrait.SetTexture, portrait, nil)
			portraitFilled[portrait] = nil
		end
	end
	Kit:RingDisc(ring, nil, f.PortraitContainer or f, 0)
end

--------------------------------------------------------------------------------
-- The title (WINDOW-RULES 2c): the shell's plate centres the container's
-- TitleText on itself in the title face; fitted again on every show, the
-- face put on again should anything have reset the string's font.
--------------------------------------------------------------------------------
local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
	end
end

local function PlaceTitle()
	local f = Window()
	if not (active and f and skin) then
		return
	end
	local rep = TitleRep()
	if rep and rep.object and rep.object:IsShown() and rep.Refit then
		rep:Refit()
	end
	local fs = TitleString(f)
	if fs and not fs.melloFontSaved and (rep or (skin.small and skin.small.title == fs)) then
		Kit:TitleFont(fs, true)
	end
end

--------------------------------------------------------------------------------
-- A small box of ours (the ticket status box, an older small help window):
-- the single rail with its stone round `rect`, the palette's inner panel over
-- the stone (2e), a frame one level under `host` so the host's own texts
-- and icons stay over it; the game's box art in `art` is faded while shown.
--------------------------------------------------------------------------------
local function SmallBox(host, rect)
	local ok, nine = pcall(Kit.NineSlice, Kit, host, { prefix = "window/single", scale = Kit.scale * (Kit.frameScale or 1.6),
		gems = false, body = true, level = -1 })
	if not (ok and nine) then
		return nil
	end
	if rect and rect ~= host then
		nine:ClearAllPoints()
		nine:SetAllPoints(rect)
	end
	if Kit.StoneDim then
		Kit:StoneDim(nine)
	end
	nine:SetShown(active)
	return nine
end

local function ShowBox(entry, on)
	if not entry then
		return
	end
	entry.nine:SetShown(on and true or false)
	for _, obj in ipairs(entry.art) do
		if on then
			Kit:Fade(obj)
		else
			Kit:Unfade(obj)
		end
	end
	if entry.title then
		if on then
			if not entry.title.melloFontSaved then
				Kit:TitleFont(entry.title, true)
			end
		else
			Kit:TitleFont(entry.title, false)
		end
	end
end

-- A texture that is a picture, not box art: more than half the frame both
-- ways (unknown sizes count as not)
local function IsPicture(region, frame)
	local ok, w, h, fw, fh = pcall(function()
		local a, b = region:GetSize()
		local c, d = frame:GetSize()
		return a, b, c, d
	end)
	if not ok or Secret(w) or Secret(h) or Secret(fw) or Secret(fh) or not (w and h and fw and fh) or fw <= 0 or fh <= 0 then
		return false
	end
	return w > fw * 0.5 and h > fh * 0.5
end

-- a frame's box art: its border / backdrop children and its own BACKGROUND /
-- BORDER textures (never a picture, the browser, or anything of ours)
local function BoxArt(frame, keep)
	local list, seen = {}, {}
	local function Add(obj)
		if obj and not seen[obj] and not (keep and keep[obj]) and not obj.kitPiece and not obj.melloSkin then
			seen[obj] = true
			list[#list + 1] = obj
		end
	end
	for _, key in ipairs({ "Border", "NineSlice", "BG", "Bg", "Background", "DialogBG" }) do
		Add(frame[key])
	end
	for _, region in ipairs({ frame:GetRegions() }) do
		if ObjectType(region) == "Texture" and not region.kitPiece then
			local okL, layer = pcall(region.GetDrawLayer, region)
			if okL and (layer == "BACKGROUND" or layer == "BORDER") and not IsPicture(region, frame) then
				Add(region)
			end
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- The older small help window (no NineSlice): the small box round the
-- window, the header band on the header plate, the close button the kit's
--------------------------------------------------------------------------------
local function BuildSmall(f, browser)
	local nine = SmallBox(f)
	if not nine then
		return
	end
	local entry = { nine = nine, art = BoxArt(f, { [browser or false] = true }) }
	local header = f.Header
	if header then
		local center = header.CenterBG or header.Center
		if center then
			entry.header = Replace(center, { as = "battlenet-friends-main", rect = header,
				alsoFade = Compact(header.LeftBG, header.RightBG, header.Left, header.Right) })
		end
	end
	entry.title = TitleString(f)
	local close = f.CloseButton or _G.HelpFrameCloseButton
	local normal = close and close.GetNormalTexture and close:GetNormalTexture()
	if normal then
		Replace(normal, { as = "RedButton-Exit", button = close, alsoFade = Kit:OtherTextures(close, normal) })
	end
	skin.small = entry
end

--------------------------------------------------------------------------------
-- The text panes (WINDOW-RULES 2e: the knowledge base's articles, the
-- browser's frame): every inset of the window on the dark panel, the
-- browser's own inset first. The browser itself is never walked into.
--------------------------------------------------------------------------------
local function IsInset(child)
	return child.NineSlice and child.Bg and (child.layoutType == "InsetFrameTemplate" or child.NineSlice.layoutType == "InsetFrameTemplate"
		or (child.NineSlice.TopLeftCorner and tostring(Kit:ArtKey(child.NineSlice.TopLeftCorner)):find("^UI%-Frame%-Inner") ~= nil))
end

local function DarkInsets(f, root, browser, depth)
	depth = depth or 0
	if not root or depth > 6 then
		return
	end
	for _, child in ipairs({ root:GetChildren() }) do
		if child ~= browser then
			if IsInset(child) and child.melloRep == nil then
				Kit:SkinInset(child, Replace, f, true)
			end
			DarkInsets(f, child, browser, depth + 1)
		end
	end
end

--------------------------------------------------------------------------------
-- The ticket status box (TicketStatusFrame: two lines of text and an icon on
-- a frame whose box is the TicketStatusFrameButton child, a black tooltip
-- backdrop): the box's backdrop faded, the small box on its rect, a frame
-- under the status frame's own level so the two lines and the icon (its
-- regions) stay over it. The button keeps its click.
--------------------------------------------------------------------------------
local function TicketArt(box)
	local list = {}
	for _, region in ipairs({ box:GetRegions() }) do
		if ObjectType(region) == "Texture" and not region.kitPiece then
			list[#list + 1] = region
		end
	end
	if box.NineSlice then
		list[#list + 1] = box.NineSlice
	end
	return list
end

local function BuildTicket()
	local ts = _G.TicketStatusFrame
	if not ts or ticket then
		return
	end
	local box = _G.TicketStatusFrameButton or ts
	local nine = SmallBox(ts, box)
	if not nine then
		return
	end
	ticket = { nine = nine, art = TicketArt(box), box = box, frame = ts }
	ShowBox(ticket, active)
end

-- the backdrop may be (re)made as the box first shows: its art looked for again
local function RefreshTicket()
	if not ticket then
		return
	end
	local seen = {}
	for _, obj in ipairs(ticket.art) do
		seen[obj] = true
	end
	for _, obj in ipairs(TicketArt(ticket.box)) do
		if not seen[obj] then
			ticket.art[#ticket.art + 1] = obj
		end
	end
	ShowBox(ticket, active)
end

--------------------------------------------------------------------------------
-- Building, switching on and off
--------------------------------------------------------------------------------
local function Build()
	local f = Window()
	if not f then
		return
	end
	skin = skin or { reps = {}, followers = {} }
	if skin.built then
		return
	end
	skin.built = true
	local browser = Browser(f)
	skin.browser = browser

	if f.NineSlice then
		-- the shell: outer rail, one page stone, the title plate on the rail,
		-- the close button; the ring only where the window shows a portrait
		local portrait = Portrait(f)
		local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = portrait, noRing = portrait == nil, bg = f.Bg and "UI-Background-Rock" or nil })
		SkinPortrait(f, ring, portrait)
	else
		BuildSmall(f, browser)
	end

	-- the browser's frame on the dark panel (never the browser itself), then
	-- every other inset of the window
	local inset = browser and browser.BrowserInset
	if inset and inset.melloRep == nil then
		Kit:SkinInset(inset, Replace, f, true)
	end
	DarkInsets(f, f, browser)

	-- the buttons on red plates (labels readable on them), scroll bars and
	-- the rest of the common controls; the browser is never walked into
	for _, child in ipairs({ f:GetChildren() }) do
		if ObjectType(child) == "Button" and (child.Left or child.Center) then
			child.melloNoInk = true
		end
	end
	Kit:SweepControls(f, Replace, skin, browser)
	local tip = _G.BrowserSettingsTooltip
	local cookies = tip and tip.CookiesButton
	if cookies then
		cookies.melloNoInk = true
		Kit:SkinRedButton(cookies, Replace)
	end
end

-- Refresh's pass a frame later, once the window is laid out (made once:
-- Kit:NextFrame runs it once however often it was asked -- audit, 2026-09-24;
-- timed on this window's own /melloperf row, not the Kit's timer -- review)
local RefreshLater = Shared("Refresh a frame later", function()
	local f = Window()
	if active and skin and f and f:IsShown() then
		if skin.ring and skin.portrait then
			pcall(Kit.FitPortrait, Kit, skin.portrait, skin.ring)
		end
		PlaceTitle()
	end
end, "timer")

local function Refresh()
	local f = Window()
	if not (active and skin and f) then
		return
	end
	for _, entry in ipairs(skin.followers) do
		entry.rep:SetShown(entry.region:IsShown())
	end
	if skin.ring and skin.portrait then
		pcall(Kit.FitPortrait, Kit, skin.portrait, skin.ring)
	end
	PlaceTitle()
	Kit:NextFrame(skin, RefreshLater)
end

-- (user, 2026-09-24: "dress rarely used windows on first open") the help window
-- and the ticket status box are each built the first time they show -- their
-- OnShow (Hook below), before the first frame is drawn -- never at login:
-- most sessions open neither. One open right now is built at once; one built
-- before is simply switched back on. Once built it stays for the session.
local function Activate()
	if active or not (Window() or _G.TicketStatusFrame) then
		return
	end
	local f, ts = Window(), _G.TicketStatusFrame
	if f and Shown(f) then
		Build()
	end
	if ts and Shown(ts) then
		BuildTicket()
	end
	active = true
	for _, rep in ipairs(skin and skin.reps or {}) do
		rep:Enable()
	end
	ShowBox(skin and skin.small, true)
	ShowBox(ticket, true)
	Refresh()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin and skin.reps or {}) do
		rep:Disable()
	end
	ShowBox(skin and skin.small, false)
	ShowBox(ticket, false)
	-- (the title plate's onDisable put the title back, the ring's the portrait)
	local f = Window()
	local fs = f and TitleString(f)
	if fs and fs.melloFontSaved then
		Kit:TitleFont(fs, false)
	end
end

local function Sync()
	if M.isEnabled and (Window() or _G.TicketStatusFrame) then
		Activate()
	else
		Deactivate()
	end
end

-- (the switch and the addon's load: out of combat only, as they always were)
local function SyncSafe()
	Kit:WhenOutOfCombat(Sync)
end

-- The help window's first show while the kit is on: built now, the way
-- Activate builds -- the pieces made first, then each enabled once, so a
-- handler fixed on a piece after it was made (the portrait ring's help icon,
-- a search box's text insets) runs on this first open too. Never for a module
-- switched off whose Deactivate still waits for the end of combat.
local function DressHelp()
	local f = Window()
	if not (active and M.isEnabled and f and Shown(f)) or (skin and skin.built) then
		return
	end
	active = false      -- (Replace enables nothing while the dress is made)
	Build()
	active = true
	for _, rep in ipairs(skin and skin.reps or {}) do
		rep:Enable()
	end
	ShowBox(skin and skin.small, true)
end

local function Hook()
	local f = Window()
	if f and not hooked[f] then
		hooked[f] = true
		Perf.HookScript(f, "OnShow", function()
			-- dressed here and now on the first open, in combat too: the dress
			-- adds frames and textures of ours and fades the game's art (the
			-- portrait a window may have is fitted on every show already); the
			-- help window has no secure or protected part, and nothing
			-- protected is called
			if M.isEnabled and not active then
				Sync()      -- (Activate refreshes it)
			else
				DressHelp()
				Refresh()
			end
		end)
	end
	local ts = _G.TicketStatusFrame
	if ts and not hooked[ts] then
		hooked[ts] = true
		Perf.HookScript(ts, "OnShow", function()
			if active then
				-- (built only while switched on: not while a switch-off waits
				-- for the end of combat)
				if M.isEnabled then
					BuildTicket()
				end
				RefreshTicket()
			end
		end)
	end
end

-- The help window comes with Blizzard_HelpFrame (loaded with the interface
-- or on demand, depending on the client): hooked as it loads, dressed as it
-- first shows (or at once when it is open already).
local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(_, event, addon)
	if event == "PLAYER_LOGIN" or addon == ADDON then
		Hook()
		if M.isEnabled then
			SyncSafe()
			-- a window that came after the kit went on and is open already
			local f = Window()
			if active and f and Shown(f) and not (skin and skin.built) then
				DressHelp()
				Refresh()
			end
			local ts = _G.TicketStatusFrame
			if active and not ticket and ts and Shown(ts) then
				BuildTicket()
			end
		end
	end
end)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

function M:OnEnable(db)
	self.db = db
	Hook()
	SyncSafe()
end

function M:OnDisable()
	SyncSafe()
end

--------------------------------------------------------------------------------
-- /helpdump [frames | reps | regions | ticket]: with no mode, which help
-- window this client has, the parts found and what the skin made of each,
-- the browser's place against every kit piece (nothing of ours may lie over
-- it), the title's place and font; "ticket" the ticket status box; the other
-- modes Kit:DumpWindow's. Opens the copy window.
--------------------------------------------------------------------------------
local function Label(obj)
	if not obj then
		return "nil"
	end
	local n = NameOf(obj)
	if n then
		return n
	end
	local ok, d = pcall(obj.GetDebugName, obj)
	if ok and type(d) == "string" and not Secret(d) then
		return d
	end
	return "[unnamed]"
end

local function Found(label, obj, more)
	MelloUI:Print("  %-26s %s%s", label, obj and Label(obj) or "-- not found", more or "")
end

local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.0f", v) or "?"
end

local function Rect(obj)
	if not obj then
		return nil
	end
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if ok and l and b and w and h and not Secret(l) and not Secret(b) and not Secret(w) and not Secret(h) then
		return l, b, w, h
	end
	return nil
end

local function RectText(obj)
	local l, b, w, h = Rect(obj)
	if l then
		return string.format("x=%.0f y=%.0f w=%.0f h=%.0f", l, b, w, h)
	end
	return "no rect"
end

local function LevelText(obj)
	if not (obj and obj.GetFrameLevel) then
		return "-"
	end
	local ok, lv = pcall(obj.GetFrameLevel, obj)
	return ok and Num(lv) or "?"
end

local function StrataOf(obj)
	local ok, s = pcall(obj.GetFrameStrata, obj)
	return (ok and not Secret(s)) and s or "?"
end

local function FontText(fs)
	local ok, face, size = pcall(fs.GetFont, fs)
	if ok and type(face) == "string" and not Secret(face) then
		return string.format("%s %s", face:match("([^\\/]+)$") or face, Num(size))
	end
	return "?"
end

local STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

-- whether a kit piece's frame could be drawn over the browser: its rect
-- overlaps the browser's and it stands at a higher strata, or at the same
-- one at or above the browser's level
local function OverBrowser(obj, browser)
	if not (obj and browser and obj.GetFrameStrata) then
		return false
	end
	local l1, b1, w1, h1 = Rect(obj)
	local l2, b2, w2, h2 = Rect(browser)
	if not (l1 and l2) then
		return false
	end
	local overlap = l1 < l2 + w2 and l2 < l1 + w1 and b1 < b2 + h2 and b2 < b1 + h1
	if not overlap then
		return false
	end
	local s1, s2 = STRATA_RANK[StrataOf(obj)] or 0, STRATA_RANK[StrataOf(browser)] or 0
	if s1 ~= s2 then
		return s1 > s2
	end
	local okA, la = pcall(obj.GetFrameLevel, obj)
	local okB, lb = pcall(browser.GetFrameLevel, browser)
	return okA and okB and not Secret(la) and not Secret(lb) and la >= lb
end

local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. ((region.kitPiece or region.kitScale) and " (kit)" or "")
		elseif kind == "FontString" then
			art = "text: " .. (TextOf(region) or "?"):sub(1, 40)
		end
		local okA, alpha = pcall(region.GetAlpha, region)
		MelloUI:Print("  region %s %s %s %s alpha %s shown %s%s", kind, Label(region), okL and tostring(layer) or "?", art,
			(okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?", tostring(Shown(region)), Kit.faded[region] and " (faded)" or "")
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		MelloUI:Print("  child %s %s strata %s level %s shown %s%s", tostring(child:GetObjectType()), Label(child), StrataOf(child),
			LevelText(child), tostring(Shown(child)), child.melloRep ~= nil and " (dressed)" or "")
	end
end

local function DumpHelp(f)
	MelloUI:Print("HelpFrame: shown %s, %s, strata %s, level %s; kit %s, pieces %d", tostring(Shown(f)), RectText(f),
		StrataOf(f), LevelText(f), active and "on" or "off", skin and #skin.reps or 0)
	if not (skin and skin.built) then
		MelloUI:Print("  not dressed yet: the help window is dressed the first time it opens")
	end
	MelloUI:Print("  template parts: NineSlice %s (layout %s), TitleContainer %s, PortraitContainer %s, CloseButton %s, Header %s; dress: %s",
		tostring(f.NineSlice ~= nil), tostring(f.NineSlice and f.NineSlice.layoutType), tostring(f.TitleContainer ~= nil),
		tostring(f.PortraitContainer ~= nil), tostring(f.CloseButton ~= nil), tostring(f.Header ~= nil),
		skin and (skin.small and "small window (rail + stone round it)" or "window shell") or "not built")
	local bgRep
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.region == f.Bg then
			bgRep = rep
		end
	end
	Found("page stone (Bg)", f.Bg, bgRep and (" -> page picture, inner " .. RectText(bgRep.inner or bgRep.object)) or " (not dressed)")
	local portrait = skin and skin.portrait
	if portrait then
		local okS, w, h = pcall(portrait.GetSize, portrait)
		local rw
		if skin.ring and skin.ring.tex then
			local okR, v = pcall(skin.ring.tex.GetWidth, skin.ring.tex)
			rw = okR and v or nil
		end
		Found("portrait", portrait, string.format(" size %s x %s, medallion %s, filled by the kit %s", okS and Num(w) or "?", okS and Num(h) or "?",
			Num((type(rw) == "number" and not Secret(rw)) and rw * 0.759 or nil), tostring(portraitFilled[portrait] ~= nil)))
	else
		MelloUI:Print("  portrait: none shown by this window (no ring)")
	end
	local fs = TitleString(f)
	local rep = TitleRep()
	local plate = rep and (rep.strip or rep.object) or (skin and skin.small and skin.small.header and skin.small.header.object)
	if fs then
		local okC, cx, cy = pcall(fs.GetCenter, fs)
		local okP, px, py = false, nil, nil
		if plate then
			okP, px, py = pcall(plate.GetCenter, plate)
		end
		local off = "?"
		if okC and okP and cx and cy and px and py and not Secret(cx) and not Secret(cy) and not Secret(px) and not Secret(py) then
			off = string.format("%.0f, %.0f", cx - px, cy - py)
		end
		Found("title", fs, string.format(" text %s, font %s, title face %s, off the plate's centre %s", tostring(TextOf(fs)), FontText(fs),
			tostring(fs.melloFontSaved ~= nil), off))
	else
		Found("title", nil)
	end
	Found("title plate", plate, plate and (" " .. RectText(plate)) or nil)
	Found("close button", f.CloseButton or _G.HelpFrameCloseButton)
	local browser = skin and skin.browser or Browser(f)
	if browser then
		Found("browser", browser, string.format(" %s, strata %s, level %s, shown %s, faded by the kit %s", RectText(browser), StrataOf(browser),
			LevelText(browser), tostring(Shown(browser)), tostring(Kit.faded[browser] == true)))
		local inset = browser.BrowserInset
		Found("browser's inset", inset, inset and string.format(" dressed %s, dim %s, strata %s", tostring(inset.melloRep ~= nil and inset.melloRep ~= false),
			tostring(inset.melloRep and inset.melloRep.skin and inset.melloRep.skin.dimFill ~= nil), StrataOf(inset)) or nil)
		local over = 0
		for i, r in ipairs(skin and skin.reps or {}) do
			local obj = r.object
			if obj and obj.GetFrameStrata and Shown(obj) and OverBrowser(obj, browser) then
				over = over + 1
				MelloUI:Print("    OVER THE BROWSER: piece %d %s (%s) strata %s level %s", i, tostring(r.key), tostring(r.kind), StrataOf(obj), LevelText(obj))
			end
		end
		MelloUI:Print("  kit pieces that could be drawn over the browser: %d", over)
	else
		MelloUI:Print("  browser: none (a small help window on this client)")
	end
	local nButtons, nPlated = 0, 0
	for _, child in ipairs({ f:GetChildren() }) do
		if ObjectType(child) == "Button" and child.GetFontString and child:GetFontString() and TextOf(child:GetFontString()) then
			nButtons = nButtons + 1
			if child.melloRep then
				nPlated = nPlated + 1
			end
		end
	end
	local tip = _G.BrowserSettingsTooltip
	MelloUI:Print("  text buttons %d, on red plates %d; browser settings' cookies button %s; tabs: none; inked strings: none (no parchment)",
		nButtons, nPlated, tip and tip.CookiesButton and tostring(tip.CookiesButton.melloRep ~= nil and tip.CookiesButton.melloRep ~= false) or "not on this client")
end

local function DumpTicket()
	local ts = _G.TicketStatusFrame
	if not ts then
		MelloUI:Print("TicketStatusFrame: not on this client")
		return
	end
	MelloUI:Print("TicketStatusFrame: shown %s, %s, strata %s, level %s; box %s level %s; kit box %s (level %s, shown %s), box art faded %d",
		tostring(Shown(ts)), RectText(ts), StrataOf(ts), LevelText(ts), Label(ticket and ticket.box or _G.TicketStatusFrameButton),
		LevelText(ticket and ticket.box or _G.TicketStatusFrameButton), tostring(ticket ~= nil), ticket and LevelText(ticket.nine) or "-",
		ticket and tostring(Shown(ticket.nine)) or "-", ticket and #ticket.art or 0)
	if not ticket then
		MelloUI:Print("  not dressed yet: the ticket status box is dressed the first time it shows")
	end
	for _, name in ipairs({ "TicketStatusTitleText", "TicketStatusTime" }) do
		local fs = _G[name]
		Found(name, fs, fs and string.format(" text %s, font %s", tostring(TextOf(fs)), FontText(fs)) or nil)
	end
	DumpOwn(ts)
	local box = _G.TicketStatusFrameButton
	if box then
		MelloUI:Print("TicketStatusFrameButton's own regions and children:")
		DumpOwn(box)
	end
end

SLASH_MELLOHELPDUMP1 = "/helpdump"
SlashCmdList.MELLOHELPDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if msg == "ticket" then
		DumpTicket()
	elseif not f then
		local loaded = "?"
		if C_AddOns and C_AddOns.IsAddOnLoaded then
			local ok, v = pcall(C_AddOns.IsAddOnLoaded, ADDON)
			loaded = ok and tostring(v) or "?"
		end
		MelloUI:Print("/helpdump: no HelpFrame on this client yet (%s loaded: %s); open Support from the game menu once and try again", ADDON, loaded)
		DumpTicket()
	elseif msg == "" then
		DumpHelp(f)
		MelloUI:Print("HelpFrame's own regions and children:")
		DumpOwn(f)
		DumpTicket()
	else
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	end
	MelloUI:ShowLog("helpdump " .. msg)
end
