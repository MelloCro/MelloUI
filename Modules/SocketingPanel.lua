--------------------------------------------------------------------------------
-- MelloUI - Socketing Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): the item socketing window (ItemSocketingFrame, the load-on-demand
-- Blizzard_ItemSocketingUI: a ButtonFrameTemplate window with the item's
-- description in a scroll frame, one to three gem sockets under it and the
-- Apply button) dressed in the painted kit (Modules/Kit.lua) on the game's
-- own layout, by the rule book (docs/WINDOW-RULES.md): every kit piece
-- stands in for one of the game's art regions, on that region's rectangle,
-- the game's art faded in its place.
--
--   the window shell     outer double rail with gem corners, the page stone,
--                        the ring with the item's icon (SetPortraitToAsset)
--                        at the class medallion's size on the dark disc
--                        (2b), the title plate on the rail with the window's
--                        own "Item Socketing" string ON it in the title face
--                        (2c: the window writes its title into an unnamed
--                        string of its own, not the title container's), the
--                        close button (Kit:SkinWindowShell)
--   the frame trims      the parchment-coloured frame round the content
--                        (ParchmentFrame-*: a trim, no text lies on it), the
--                        Apply button's box (ButtonFrame-*, ButtonBorder-Mid)
--                        and the rivets (*Nub): bands the game paints over
--                        its rock, faded (the one page stone runs on under
--                        them); the inset under them has its art faded too
--                        (the game covers it with those bands: a rail there
--                        would be a second rail a few px inside the outer one)
--   the description      the gold-bordered box round the item's tooltip
--                        (GoldBorder-*, its inner shadow and blue wash) ->
--                        the list box L1: single rail, stone under the
--                        palette's inner panel (2e: text-dense)
--   the socket box       SocketFrame-Left / -Right (the dark bed under the
--                        sockets) -> one L1 box on both halves
--   the sockets          every window's Round Border rim (O2, the kit's
--                        round rim; Kit:RimRect: a square whose opening is
--                        the 38 px gem icon) in place of the socket's ring,
--                        the gem icon masked round inside it while the rim is
--                        on; the connecting filigree faded; the socket's
--                        colour bed and its brackets (the socket colour and
--                        whether a new gem sits in it) stay the game's
--   Apply                the red plate (B1), its label never inked
--   the scroll bar       THE scroll bar, by the sweep
--
-- Taint: nothing of the game's is replaced or re-scripted. Post-hooks
-- (ItemSocketingFrame_Update, HookScript, the sockets' Enable / Disable)
-- only; what the skin keeps about the game's frames lives in weak side
-- tables; no socketing function is ever called. The window is never moved.
-- Switching the module off disables every replacement (the game's art faded
-- back in, ours hidden), takes the round mask off the gem icons and puts the
-- portrait and the title back: the window is the game's again.
--
-- /socketdump [frames | reps | regions]: what the window is made of on this
-- client and what the skin dressed, in the copy window.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("SocketingPanel", {
	title = "Socketing Kit",
	desc = "The item socketing window in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local ADDON = "Blizzard_ItemSocketingUI"
local GEM_ICON = 38          -- GenericSocketButtonTemplate's Icon (38 x 38 on a 40 px button)
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local skin = nil          -- { reps = { every replacement }, followers = {}, built, ring, portrait }
local active = false
local hooked = false

-- what this module made or looked at, kept OFF the game's frames (weak keys)
local done = setmetatable({}, { __mode = "k" })          -- [frame / region] = true: looked at once
local titleMoved = setmetatable({}, { __mode = "k" })    -- [fs] = its points while it rides the plate
local titleFaded = setmetatable({}, { __mode = "k" })    -- [fs] = true while faded as a duplicate
local socketRims = {}                                    -- { socket, rep, mask, ring, icon, masked }
local fadedArt = {}                                      -- game art faded with no piece on its own rect
local found = {}                                         -- [part] = a line for /socketdump
local built = {}                                         -- [part] = true once made (the boxes)

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

-- A replacement the library knows; registered so enable / disable reach it.
local function Replace(region, opts)
	if not (region and skin) then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Socketing kit: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- the non-nil values given, as a list (alsoFade stops at the first nil)
local function List(...)
	local list = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if v then
			list[#list + 1] = v
		end
	end
	return list
end

-- a frame's name, secret-safe (nil when it has none or it reads secret)
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

local function Label(obj)
	if not obj then
		return "nil"
	end
	local n = NameOf(obj)
	if n then
		return n
	end
	local ok, d = pcall(obj.GetDebugName, obj)
	return (ok and type(d) == "string" and not Secret(d)) and d or "[unnamed]"
end

-- a font string's text when it can be read (nil when empty or secret)
local function TextOf(fs)
	local ok, text = pcall(fs.GetText, fs)
	if ok and type(text) == "string" and not Secret(text) and text ~= "" then
		return text
	end
	return nil
end

-- whether a font string shows anything (a secret text is shown all the same)
local function HasText(fs)
	local ok, text = pcall(fs.GetText, fs)
	if not ok then
		return false
	end
	if Secret(text) then
		return true
	end
	return type(text) == "string" and text ~= ""
end

local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.0f", v) or "?"
end

local function Width(obj)
	local ok, w = pcall(obj.GetWidth, obj)
	if ok and type(w) == "number" and not Secret(w) then
		return w
	end
	return nil
end

-- Art faded while the kit is on, with no piece on its own rect
local function FadeArt(obj)
	if not obj or done[obj] then
		return
	end
	done[obj] = true
	fadedArt[#fadedArt + 1] = obj
	if active then
		Kit:Fade(obj)
	end
end

local function Window()
	return _G.ItemSocketingFrame
end

local function Container(f)
	return f and f.SocketingContainer or nil
end

-- the sockets: the container's array, else its three keys
local function Sockets(f)
	local c = Container(f)
	if not c then
		return {}
	end
	if c.SocketFrames and #c.SocketFrames > 0 then
		return c.SocketFrames
	end
	return List(c.Socket1, c.Socket2, c.Socket3)
end

local function Portrait(f)
	local pc = f and f.PortraitContainer
	return (pc and pc.portrait) or (f and f.portrait) or _G.ItemSocketingFramePortrait
end

--------------------------------------------------------------------------------
-- The portrait (WINDOW-RULES 2b / 2c: an empty ring is a bug). The game puts
-- the item's icon into the PortraitContainer's portrait on every update
-- (SetPortraitToAsset: masked round): the kit's ring on the corner, the icon
-- at the class medallion's size in it (Kit:FitPortrait, its aspect kept) on
-- the dark disc (Kit:RingDisc: an icon with a transparent edge never shows
-- the page through the ring). Fitted again on every update; put back on
-- disable.
--------------------------------------------------------------------------------
local function FitPortrait()
	local portrait = skin and skin.portrait
	if active and skin.ring and portrait then
		pcall(Kit.FitPortrait, Kit, portrait, skin.ring)
	end
end

local function SkinPortrait(f, ring)
	local portrait = Portrait(f)
	if not (ring and portrait) then
		found.portrait = "-- no ring (no NineSlice corner or no portrait on this client)"
		return
	end
	skin.ring, skin.portrait = ring, portrait
	ring.onEnable = function()
		pcall(Kit.FitPortrait, Kit, portrait, ring)
	end
	ring.onDisable = function()
		pcall(Kit.UnfitPortrait, Kit, portrait)
	end
	-- (chains onto the fit above; a region of the portrait's own container,
	-- BACKGROUND under its OVERLAY portrait)
	local disc = Kit:RingDisc(ring, nil, f.PortraitContainer or ring.object:GetParent(), 0)
	found.portrait = string.format("%s in the ring, disc %s", Label(portrait), disc and "made" or "NOT made")
end

--------------------------------------------------------------------------------
-- The title (WINDOW-RULES 2c, user 2026-09-24: "the text header is not on the
-- header"). The title plate's rule centres the title container's TitleText
-- on the plate in the title face; this window leaves that string empty and
-- writes "Item Socketing" (ITEM_SOCKETING) into an unnamed OVERLAY string of
-- its own at its top. That string is moved onto the plate (on the
-- container's string, which the rule centred there) in Kit:TitleFont, or
-- faded when the container shows the same words; its points and font come
-- back on disable.
--------------------------------------------------------------------------------
local function TitleStrings(f)
	local tc = f.TitleContainer
	local own = tc and tc.TitleText
	local list = {}
	for _, region in ipairs({ f:GetRegions() }) do
		if region ~= own and region:GetObjectType() == "FontString" and HasText(region) then
			local text = TextOf(region)
			-- the window's own title: ITEM_SOCKETING, else a short string
			-- hung from the window's top (a sentence is never a title)
			local okP, point = pcall(region.GetPoint, region, 1)
			if text == _G.ITEM_SOCKETING or (text and #text <= 40 and okP and type(point) == "string" and point:find("^TOP")) then
				list[#list + 1] = region
			end
		end
	end
	return list, own
end

local function TitleRep()
	for _, rep in ipairs(skin and skin.reps or {}) do
		if rep.key == "TitleBar" then
			return rep
		end
	end
end

local function PlaceTitles(on)
	local f = Window()
	if not f then
		return
	end
	if not on then
		for fs, points in pairs(titleMoved) do
			Kit:TitleFont(fs, false)
			fs:ClearAllPoints()
			for _, pt in ipairs(points) do
				fs:SetPoint(unpack(pt))
			end
		end
		wipe(titleMoved)
		for fs in pairs(titleFaded) do
			Kit:Unfade(fs)
		end
		wipe(titleFaded)
		return
	end
	local rep = TitleRep()
	if not rep then
		return
	end
	if rep.Refit and rep.object and rep.object:IsShown() then
		rep:Refit()
	end
	local list, own = TitleStrings(f)
	local ownText = own and TextOf(own)
	for _, fs in ipairs(list) do
		if ownText and TextOf(fs) == ownText then
			-- the same words already on the plate: this copy gives way
			if not titleFaded[fs] then
				titleFaded[fs] = true
				Kit:Fade(fs)
			end
		else
			if not titleMoved[fs] then
				local points = {}
				for i = 1, fs:GetNumPoints() do
					points[i] = { fs:GetPoint(i) }
				end
				titleMoved[fs] = points
			end
			fs:ClearAllPoints()
			-- on the container's string (the rule centred it on the plate's
			-- painted box), else on the plate itself
			if own then
				fs:SetPoint("CENTER", own, "CENTER")
			else
				fs:SetPoint("CENTER", rep.strip or rep.object, "CENTER")
			end
			Kit:TitleFont(fs, true)
		end
	end
end

--------------------------------------------------------------------------------
-- The frame's bands (the parchment-coloured trim round the content, the
-- Apply button's box, the rivets) and the inset under them: faded, the page
-- stone runs on. The inset is marked with the Kit's own marker so the sweep
-- does not give it a rail of its own.
--------------------------------------------------------------------------------
local TRIMS = { "ParchmentFrame-Top", "ParchmentFrame-Bottom", "ParchmentFrame-Left", "ParchmentFrame-Right",
	"ButtonFrame-Left", "ButtonFrame-Right", "ButtonBorder-Mid",
	"BottomLeftNub", "BottomRightNub", "MiddleLeftNub", "MiddleRightNub", "TopLeftNub", "TopRightNub" }

local function SkinTrims(f)
	local n = 0
	for _, key in ipairs(TRIMS) do
		if f[key] then
			FadeArt(f[key])
			n = n + 1
		end
	end
	local inset = f.Inset or _G.ItemSocketingFrameInset
	local ni = 0
	if inset then
		if inset.Bg then
			FadeArt(inset.Bg)
			ni = ni + 1
		end
		if inset.NineSlice then
			for _, region in ipairs({ inset.NineSlice:GetRegions() }) do
				if region:GetObjectType() == "Texture" and not region.kitPiece then
					FadeArt(region)
					ni = ni + 1
				end
			end
		end
		if inset.melloRep == nil then
			inset.melloRep = false
		end
	end
	found.trims = string.format("%d of %d frame trims faded; inset %s (%d art pieces faded)", n, #TRIMS,
		inset and Label(inset) or "-- none", ni)
end

--------------------------------------------------------------------------------
-- The description box (WINDOW-RULES 2e: the item's tooltip is the window's
-- text). The game frames the scroll frame with a gold border (GoldBorder-*:
-- four corners and four tiled edges), a soft inner shadow (BorderShadow-*),
-- a translucent blue wash (BackgroundColor) and a picture over it
-- (BackgroundHighlight). The L1 box stands in for all of them on the gold
-- border's own extent: the single rail, the list-box stone under the
-- palette's inner panel, on a holder one level over the window (whose own
-- regions are the page stone) -- the tooltip draws in its own strata above.
--------------------------------------------------------------------------------
local GOLD = { "GoldBorder-TopLeft", "GoldBorder-TopRight", "GoldBorder-BottomLeft", "GoldBorder-BottomRight",
	"GoldBorder-Left", "GoldBorder-Right", "GoldBorder-Top", "GoldBorder-Bottom" }
local SHADOW = { "BorderShadow-TopLeftCorner", "BorderShadow-TopRightCorner", "BorderShadow-BottomLeftCorner",
	"BorderShadow-BottomRightCorner", "BorderShadow-Top", "BorderShadow-Left", "BorderShadow-Bottom", "BorderShadow-Right",
	"BackgroundColor", "BackgroundHighlight" }

local function SkinDescription(f)
	if built.description then
		return
	end
	built.description = true
	local tl, br = f["GoldBorder-TopLeft"], f["GoldBorder-BottomRight"]
	local fade = {}
	for i = 2, #GOLD do
		if f[GOLD[i]] then
			fade[#fade + 1] = f[GOLD[i]]
		end
	end
	for _, key in ipairs(SHADOW) do
		if f[key] then
			fade[#fade + 1] = f[key]
		end
	end
	local scroll = f.ScrollFrame or _G.ItemSocketingScrollFrame
	local rect = CreateFrame("Frame", nil, f)
	rect:EnableMouse(false)
	if tl and br then
		rect:SetPoint("TOPLEFT", tl, "TOPLEFT")
		rect:SetPoint("BOTTOMRIGHT", br, "BOTTOMRIGHT")
	elseif scroll then
		rect:SetPoint("TOPLEFT", scroll, "TOPLEFT", -9, 9)
		rect:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 9, -9)
	else
		found.description = "-- no gold border and no scroll frame"
		return
	end
	-- a box with no game corner of its own is handed over as an invisible
	-- texture of ours (never faded: noFade)
	local region = tl
	if not region then
		region = f:CreateTexture(nil, "BACKGROUND")
		region:SetAllPoints(rect)
		region:SetColorTexture(0, 0, 0, 0)
		region.kitPiece = true
	end
	local rep = Replace(region, { as = "common-insideframe", parent = f, rect = rect, level = 1, body = true,
		noFade = tl == nil, alsoFade = fade })
	found.description = string.format("gold border %s, L1 box %s (%d game pieces faded with it), dim %s",
		tl and "found" or "-- missing (the box on the scroll frame)", rep and "dressed" or "NOT dressed", #fade,
		tostring(rep ~= nil and rep.skin ~= nil and rep.skin.dimFill ~= nil))
end

--------------------------------------------------------------------------------
-- The socket box: the two dark halves under the sockets (SocketFrame-Left /
-- -Right, 158 x 51 each, side by side) -> one L1 box on both, a holder one
-- level over the window (the socket buttons sit two levels up).
--------------------------------------------------------------------------------
local function SkinSocketBox(f)
	if built.socketBox then
		return
	end
	built.socketBox = true
	local left, right = f["SocketFrame-Left"], f["SocketFrame-Right"]
	if not left then
		found.socketBox = "-- no SocketFrame-Left on this client"
		return
	end
	local rect = CreateFrame("Frame", nil, f)
	rect:EnableMouse(false)
	rect:SetPoint("TOPLEFT", left, "TOPLEFT")
	rect:SetPoint("BOTTOMRIGHT", right or left, "BOTTOMRIGHT")
	local rep = Replace(left, { as = "common-insideframe", parent = f, rect = rect, level = 1, body = true, alsoFade = List(right) })
	found.socketBox = string.format("L1 box %s on %s%s", rep and "dressed" or "NOT dressed", Label(left), right and (" + " .. Label(right)) or "")
end

--------------------------------------------------------------------------------
-- The sockets (GenericSocketButtonTemplate, 40 px buttons: the filigree
-- joining them in BACKGROUND, the socket's ring -- an unnamed 72 x 74 BORDER
-- texture of UI-ItemSockets -- and its colour bed (Background, BORDER), the
-- 38 px gem icon in ARTWORK, the brackets on a child frame over it). The
-- round rim (O2, every window's Round Border: Kit:Slot registers it) on a
-- square whose opening is the gem icon (Kit:RimRect), in place of the ring;
-- the filigree and the square pushed / highlight looks faded (the rim
-- carries hover and press). The gem icons are square pictures: while the
-- rim is on they are masked round by a mask of our own (taken off on
-- disable), so no corner shows past the round rim. The game enables and
-- disables the sockets while it applies: the rim's look is read again then.
--------------------------------------------------------------------------------
local function RingOf(socket)
	for _, region in ipairs({ socket:GetRegions() }) do
		if region ~= socket.Background and region:GetObjectType() == "Texture" and not region.kitPiece then
			local ok, layer = pcall(region.GetDrawLayer, region)
			if ok and layer == "BORDER" then
				return region
			end
		end
	end
end

local function Filigree(socket)
	local list = {}
	for _, region in ipairs({ socket:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			local ok, layer = pcall(region.GetDrawLayer, region)
			if ok and layer == "BACKGROUND" then
				list[#list + 1] = region
			end
		end
	end
	return list
end

local function SkinSocket(socket)
	if not socket or done[socket] then
		return
	end
	done[socket] = true
	local icon = socket.Icon or _G[(NameOf(socket) or "") .. "IconTexture"]
	if not icon then
		if socket.melloRep == nil then
			socket.melloRep = false
		end
		return
	end
	local ring = RingOf(socket)
	local extra = Filigree(socket)
	for _, t in ipairs(List(socket.GetPushedTexture and socket:GetPushedTexture(), socket.GetHighlightTexture and socket:GetHighlightTexture())) do
		extra[#extra + 1] = t
	end
	local size = Width(icon)
	if not (size and size > 0) then
		size = GEM_ICON
	end
	local rect = Kit:RimRect(socket, "roundslot", size, icon)
	local rep = Replace(ring or icon, { as = "communities-ring-gold", button = socket, rect = rect, noFade = ring == nil, alsoFade = extra })
	socket.melloRep = rep or false
	if not rep then
		return
	end
	-- the gem icon masked round while the rim is on
	local mask = socket:CreateMaskTexture()
	mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	local entry = { socket = socket, rep = rep, mask = mask, ring = ring, icon = icon, masked = false }
	socketRims[#socketRims + 1] = entry
	local enable, disable = rep.onEnable, rep.onDisable
	rep.onEnable = function(...)
		if enable then
			enable(...)
		end
		if not entry.masked and icon.AddMaskTexture then
			entry.masked = pcall(icon.AddMaskTexture, icon, mask)
		end
	end
	rep.onDisable = function(...)
		if disable then
			disable(...)
		end
		if entry.masked and icon.RemoveMaskTexture then
			pcall(icon.RemoveMaskTexture, icon, mask)
			entry.masked = false
		end
	end
	if active then
		rep.onEnable(rep)
	end
	for _, method in ipairs({ "Enable", "Disable", "SetEnabled" }) do
		if socket[method] then
			hooksecurefunc(socket, method, function()
				local rim = rep.object
				if active and rim and rim.Update then
					rim:Update()
				end
			end)
		end
	end
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

	-- the shell: outer rail, one page stone, the ring with the item, the
	-- title plate on the rail, the close button
	local ring = Kit:SkinWindowShell(f, Replace, skin, { portrait = Portrait(f), bg = "UI-Background-Rock" })
	found.shell = string.format("NineSlice %s, page stone (Bg) %s, title container %s, close %s", tostring(f.NineSlice ~= nil),
		tostring(f.Bg ~= nil), tostring(f.TitleContainer ~= nil), tostring(f.CloseButton ~= nil))
	SkinPortrait(f, ring)

	SkinTrims(f)
	SkinDescription(f)
	SkinSocketBox(f)
	local n = 0
	for _, socket in ipairs(Sockets(f)) do
		SkinSocket(socket)
		n = n + 1
	end
	found.sockets = string.format("%d socket buttons, %d with the round rim", n, #socketRims)

	local c = Container(f)
	local apply = c and c.ApplySocketsButton
	local rep = apply and Kit:SkinRedButton(apply, Replace)
	if apply then
		-- a plate's label keeps its own colour on any paper (the ink rule's
		-- button exception)
		apply.melloNoInk = true
	end
	found.apply = apply and string.format("%s: red plate %s", Label(apply), rep and "on" or "NOT made") or "-- not found"

	-- the scroll bar and whatever else the sweep knows
	Kit:SweepControls(f, Replace, skin)
end

-- After every show and every game update (a gem put in, the item changed):
-- the portrait (a new icon), the title, the rims' looks; once more a frame
-- later, when the window is laid out.
local function Refresh()
	local f = Window()
	if not (active and skin and f) then
		return
	end
	FitPortrait()
	PlaceTitles(true)
	for _, entry in ipairs(socketRims) do
		local rim = entry.rep.object
		if rim and rim.Update then
			rim:Update()
		end
	end
	if skin.laterPending then
		return
	end
	skin.laterPending = true
	C_Timer.After(0, function()
		skin.laterPending = nil
		if active and f:IsShown() then
			FitPortrait()
			PlaceTitles(true)
		end
	end)
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
	for _, obj in ipairs(fadedArt) do
		Kit:Fade(obj)
	end
	Refresh()
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
	for _, obj in ipairs(fadedArt) do
		Kit:Unfade(obj)
	end
	-- the title back where the game put it, in its font (the ring's
	-- onDisable put the portrait back, the rims' the icons' masks)
	PlaceTitles(false)
end

local function Sync()
	if M.isEnabled and Window() then
		Activate()
	else
		Deactivate()
	end
end

-- (geometry of the window's children changes here: out of combat only)
local function SyncSafe()
	if Kit.WhenOutOfCombat then
		Kit:WhenOutOfCombat(Sync)
	else
		Sync()
	end
end

local function Hook()
	local f = Window()
	if hooked or not f then
		return
	end
	hooked = true
	f:HookScript("OnShow", function()
		if M.isEnabled and not active then
			SyncSafe()
		end
		Refresh()
	end)
	if type(_G.ItemSocketingFrame_Update) == "function" then
		hooksecurefunc("ItemSocketingFrame_Update", Refresh)
	end
end

-- The window is load on demand (Blizzard_ItemSocketingUI, with the first
-- socketing): dressed when that addon loads, or at once if it already has.
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, _, name)
	if (name == ADDON or Window()) and Window() then
		self:UnregisterEvent("ADDON_LOADED")
		Hook()
		if M.isEnabled then
			SyncSafe()
		end
	end
end)

function M:OnEnable(db)
	self.db = db
	if Window() then
		Hook()
		SyncSafe()
	else
		eventFrame:RegisterEvent("ADDON_LOADED")
	end
end

function M:OnDisable()
	SyncSafe()
end

--------------------------------------------------------------------------------
-- /socketdump [frames | reps | regions]: with no mode, what the skin found
-- and dressed (every part, found or not), the portrait against the
-- medallion, the title's place and font, and the window's own regions and
-- children; the modes are Kit:DumpWindow's. Opens the copy window.
--------------------------------------------------------------------------------
local function Line(label, text)
	MelloUI:Print("  %-18s %s", label, text or "-- not looked at yet (the kit has not dressed the window)")
end

local function Shown(obj)
	local ok, s = pcall(obj.IsShown, obj)
	return (ok and not Secret(s)) and tostring(s) or "?"
end

local function Rect(obj)
	local ok, l, b, w, h = pcall(obj.GetRect, obj)
	if ok and l and not Secret(l) and not Secret(b) and not Secret(w) and not Secret(h) then
		return string.format("x=%s y=%s w=%s h=%s", Num(l), Num(b), Num(w), Num(h))
	end
	return "(no rect)"
end

local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer, sub = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "")
		elseif kind == "FontString" then
			art = "text: " .. tostring(TextOf(region) or (HasText(region) and "[secret]" or "")):sub(1, 40)
		end
		local okA, alpha = pcall(region.GetAlpha, region)
		MelloUI:Print("  region %s %s %s %s %s alpha %s shown %s faded %s", kind, Label(region), okL and tostring(layer) or "?",
			okL and tostring(sub) or "", art, (okA and not Secret(alpha)) and string.format("%.2f", alpha) or "?", Shown(region),
			tostring(Kit.faded[region] == true))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local okLv, lv = pcall(child.GetFrameLevel, child)
		MelloUI:Print("  child %s %s level %s shown %s%s", tostring(child:GetObjectType()), Label(child),
			okLv and Num(lv) or "?", Shown(child), child.melloRep ~= nil and " (marked)" or "")
	end
end

local function Summary(f)
	local okLv, lv = pcall(f.GetFrameLevel, f)
	MelloUI:Print("ItemSocketingFrame: shown %s, level %s, kit %s, reps %d, faded art %d", Shown(f), okLv and Num(lv) or "?",
		active and "on" or "off", skin and #skin.reps or 0, #fadedArt)
	Line("shell", found.shell)
	-- the portrait against the class medallion (0.759 x the ring)
	local portrait = Portrait(f)
	if portrait then
		local okT, file = pcall(portrait.GetTexture, portrait)
		local okS, w, h = pcall(portrait.GetSize, portrait)
		local ringW = skin and skin.ring and skin.ring.tex and Width(skin.ring.tex)
		Line("portrait", string.format("%s file %s, size %s x %s, medallion %s, fitted %s, shown %s", Label(portrait),
			(okT and not Secret(file)) and tostring(file) or "?", okS and Num(w) or "?", okS and Num(h) or "?",
			ringW and Num(ringW * 0.759) or "?", tostring(portrait.melloSaved ~= nil), Shown(portrait)))
	else
		Line("portrait", "-- not found")
	end
	Line("ring", found.portrait)
	-- the title: the container's string and the window's own
	local titles, own = TitleStrings(f)
	local rep = TitleRep()
	Line("title plate", rep and string.format("%s, %s", (rep.object and rep.object:IsShown()) and "shown" or "hidden",
		rep.strip and Rect(rep.strip) or "") or "-- none")
	Line("container title", own and string.format("%s text '%s'", Label(own), tostring(TextOf(own) or (HasText(own) and "[secret]" or "(empty)"))) or "-- none")
	if #titles == 0 then
		Line("title string", "-- no string of the window's own with text")
	end
	for _, fs in ipairs(titles) do
		local okF, face, size = pcall(fs.GetFont, fs)
		Line("title string", string.format("%s '%s' at %s, face %s %s, %s", Label(fs), tostring(TextOf(fs) or "[secret]"), Rect(fs),
			(okF and type(face) == "string" and not Secret(face)) and face or "?", okF and Num(size) or "?",
			titleMoved[fs] and "ON the plate (title face)" or titleFaded[fs] and "faded (duplicate)" or "not placed"))
	end
	Line("tabs", "-- none (the window has no tabs)")
	Line("page picture", f.Bg and string.format("Bg at %s, faded %s (the page stone stands on the window's rect inside the outer rail)",
		Rect(f.Bg), tostring(Kit.faded[f.Bg] == true)) or "-- no Bg")
	Line("trims", found.trims)
	Line("description", found.description)
	local scroll = f.ScrollFrame or _G.ItemSocketingScrollFrame
	local bar = scroll and scroll.ScrollBar
	Line("scroll frame", scroll and string.format("%s at %s, scroll bar %s", Label(scroll), Rect(scroll),
		bar and tostring(bar.melloRep ~= nil and bar.melloRep ~= false) or "-- none") or "-- not found")
	local desc = _G.ItemSocketingDescription
	Line("item tooltip", desc and string.format("%s shown %s, its own NineSlice shown %s", Label(desc), Shown(desc),
		desc.NineSlice and Shown(desc.NineSlice) or "-") or "-- not found")
	Line("socket box", found.socketBox)
	Line("sockets", found.sockets)
	for i, socket in ipairs(Sockets(f)) do
		local entry
		for _, e in ipairs(socketRims) do
			if e.socket == socket then
				entry = e
			end
		end
		local okE, enabled = pcall(socket.IsEnabled, socket)
		Line("  socket " .. i, string.format("shown %s, enabled %s, ring %s, rim %s (%s), icon masked %s, colour bed shown %s",
			Shown(socket), (okE and not Secret(enabled)) and tostring(enabled) or "?",
			(entry and entry.ring) and ("faded " .. tostring(Kit.faded[entry.ring] == true)) or "-- none found",
			entry and "on" or "none", (entry and entry.rep.object) and tostring(entry.rep.object.base) or "-",
			entry and tostring(entry.masked) or "-", socket.Background and Shown(socket.Background) or "-"))
	end
	Line("apply", found.apply)
	Line("inked strings", "-- none (no parchment page on this window: its text lies on the dark panel)")
	MelloUI:Print("ItemSocketingFrame's own regions and children:")
	DumpOwn(f)
end

SLASH_MELLOSOCKETDUMP1 = "/socketdump"
SlashCmdList.MELLOSOCKETDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local f = Window()
	MelloUI:ClearLog()
	if not f then
		MelloUI:Print("/socketdump: no ItemSocketingFrame yet: %s loads with the first socketing (open an item with sockets, then try "
			.. "again). If it never appears, the window is not on this client.", ADDON)
	elseif msg == "" then
		Summary(f)
	else
		-- frames / reps / regions (the visible game textures): the Kit's dump
		Kit:DumpWindow(f, skin, msg ~= "regions" and msg or nil)
	end
	MelloUI:ShowLog("socketdump " .. msg)
end
