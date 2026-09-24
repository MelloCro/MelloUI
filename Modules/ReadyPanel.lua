--------------------------------------------------------------------------------
-- MelloUI - Ready Check Kit
--
-- (user, 2026-09-24: "do all of them, then we are done with the UI
-- reskin"): The ready check and the dungeon / battleground ready popups in the kit.
--
-- They are dressed as the Dialogs Kit dresses the game's popups: the single
-- rail with its stone round the popup (a frame one level below the part
-- that draws it, so its text, icons and buttons stay over it), the game's
-- own box faded, the buttons on the kit's red plates with their labels in
-- their own colours. The Dialogs' parchment option (Dynamic UI
-- Modification, Parchment: Dialogs) is theirs too: with it on, the
-- parchment sheet with its painted edge lies on the stone and the text is
-- dark ink (the parchment rule, the sheet's inks); with it off, the
-- palette's inner panel lies on the stone (no eye strain, WINDOW-RULES 2e).
--
--   ReadyCheckFrame          the ready check: the initiator's portrait in the
--                            kit's portrait ring at the class medallion's size
--                            (WINDOW-RULES 2b, on the dark disc), the message,
--                            Ready / Not Ready; a client that gives it a title
--                            bar gets the title plate with the title in the
--                            kit's title face (2c)
--   LFGDungeonReadyDialog /  the dungeon finder's "your group is ready" popup
--   LFGDungeonReadyStatus    and its who-is-ready status; the dungeon's own
--                            picture on it is left as the game draws it
--   PVPReadyDialog           the battleground's "enter battle" popup, the same
--
-- A client without one of them (this one may ask to enter a battleground
-- with a popup dialog, which the Dialogs Kit dresses) simply has nothing to
-- dress: the dump says so. The ready check's and the queues' buttons may be
-- protected: nothing of theirs is moved, resized or scripted; only textures
-- and frames of our own are added and the game's art faded. Switching the
-- module off gives back the stock popups.
--
-- /readydump [ready | lfg | pvp] [frames | reps | regions]: what each popup
-- is made of and what the kit made of it.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("ReadyPanel", {
	title = "Ready Check Kit",
	desc = "The ready check and the dungeon / battleground ready popups in the kit.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local AREA = "dialog"            -- the Dialogs' parchment option (parchment_dialog)
local SURFACE = "readycheck"     -- this module's QuestInk surface
local MEDALLION_TO_RING = 0.759  -- the class medallion's size in the portrait ring (WINDOW-RULES 2b)

-- The popups, by the names the game gives them
local POPUPS = {
	{ key = "ready", label = "ready check", name = "ReadyCheckFrame", group = "ready" },
	{ key = "lfgready", label = "dungeon ready dialog", name = "LFGDungeonReadyDialog", group = "lfg" },
	{ key = "lfgstatus", label = "dungeon ready status", name = "LFGDungeonReadyStatus", group = "lfg" },
	{ key = "pvpready", label = "battleground ready dialog", name = "PVPReadyDialog", group = "pvp" },
}

local active = false
local reps = {}                                          -- every replacement, for enable / disable
local skins = setmetatable({}, { __mode = "k" })         -- [popup] = { nine, sheet, dim, ring, title, ... }
local fadedArt = setmetatable({}, { __mode = "k" })      -- [popup] = { [the game's art we faded] = true }
local popupButtons = setmetatable({}, { __mode = "k" })  -- [button] = "plate" / "close" / "none"
local hookedPopups = setmetatable({}, { __mode = "k" })  -- [popup] = true: its OnShow is watched

local function Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

local function Replace(region, opts)
	local rep = region and Kit and Kit.Replace and Kit:Replace(region, opts)
	if rep then
		reps[#reps + 1] = rep
		if active then
			rep:Enable()
		end
	end
	return rep
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

-- The popups this client has (a frame of that name that is a frame)
local function Popups()
	local list = {}
	for _, e in ipairs(POPUPS) do
		local f = _G[e.name]
		if type(f) == "table" and f.GetChildren and f.CreateTexture then
			list[#list + 1] = f
		end
	end
	return list
end

-- The frame that draws a popup: the ready check's listener (the part the
-- game shows to the players asked; the frame itself carries no art and is
-- shown to the one who asked as well), else the popup itself
local function Body(popup)
	if popup == _G.ReadyCheckFrame then
		local listener = _G.ReadyCheckListenerFrame
		if type(listener) == "table" and listener.GetRegions then
			return listener
		end
	end
	return popup
end

-- the popup and, for the ready check, its listener: where its parts live
local function Owners(popup)
	local body = Body(popup)
	if body ~= popup then
		return { popup, body }
	end
	return { popup }
end

--------------------------------------------------------------------------------
-- The ready check's parts, found by key or by the global name the XML gives
-- them (a portrait container and a title container on one client, loose
-- named regions on another)
--------------------------------------------------------------------------------
local function Portrait(popup)
	if popup ~= _G.ReadyCheckFrame then
		return nil
	end
	local body = Body(popup)
	local pc = body.PortraitContainer
	return (pc and (pc.Portrait or pc.portrait)) or body.Portrait or _G.ReadyCheckPortrait
end

local function TitleText(popup)
	local tc = Body(popup).TitleContainer
	return tc and tc.TitleText or nil, tc
end

local function MessageText(popup)
	local body = Body(popup)
	return body.Text or body.label or (popup == _G.ReadyCheckFrame and _G.ReadyCheckFrameText) or _G[(NameOf(popup) or "?") .. "Label"]
end

-- art that is the popup's content, not its box: the role and status icons,
-- the dungeon's picture
local function IsContent(region)
	local name = NameOf(region)
	return type(name) == "string" and (name:find("Icon") or name:find("Background$")) and true or false
end

-- What is never faded: the portrait, the dungeon's picture, the ready
-- check's listener (a frame WITH a layout type that holds everything), ours
local function Keep(popup)
	local keep = {}
	local body = Body(popup)
	for _, obj in pairs({ Portrait(popup) or false, popup.background or false, body.background or false }) do
		if obj then
			keep[obj] = true
		end
	end
	if body ~= popup then
		keep[body] = true
	end
	local skin = skins[popup]
	if skin then
		keep[skin.nine] = true
	end
	return keep
end

-- The game's popup box, whatever the client makes it of: a nine-slice
-- (Border / NineSlice, or a child that is one), a background texture, and
-- the frame's own box textures -- on the ready check every texture of its
-- own (the classic check is one painted picture in its ARTWORK layer),
-- elsewhere those in BACKGROUND and BORDER only (the icons, pictures and
-- text are higher or frames of their own, and stay)
local function GameArt(popup)
	local list, seen = {}, {}
	local keep = Keep(popup)
	local all = popup == _G.ReadyCheckFrame
	local function Add(obj)
		if obj and not seen[obj] and not keep[obj] and not obj.kitPiece and not obj.melloSkin then
			seen[obj] = true
			list[#list + 1] = obj
		end
	end
	for _, owner in ipairs(Owners(popup)) do
		for _, key in ipairs({ "Border", "NineSlice", "BG", "Bg", "DialogBG" }) do
			Add(owner[key])
		end
		for _, child in ipairs({ owner:GetChildren() }) do
			local name = NameOf(child)
			if (child.layoutType and child.TopLeftCorner) or (type(name) == "string" and (name:find("Border$") or name:find("NineSlice$"))) then
				Add(child)
			end
		end
		for _, region in ipairs({ owner:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not IsContent(region) then
				local okL, layer = pcall(region.GetDrawLayer, region)
				if all or (okL and (layer == "BACKGROUND" or layer == "BORDER")) then
					Add(region)
				end
			end
		end
	end
	return list
end

local function FadeArt(popup)
	fadedArt[popup] = fadedArt[popup] or {}
	for _, obj in ipairs(GameArt(popup)) do
		Kit:Fade(obj)
		fadedArt[popup][obj] = true
	end
end

local function UnfadeArt(popup)
	for obj in pairs(fadedArt[popup] or {}) do
		Kit:Unfade(obj)
	end
	fadedArt[popup] = nil
end

--------------------------------------------------------------------------------
-- Buttons (the Dialogs Kit's way): a text button on the red plate with its
-- label in its own colour (the parchment rule's button exception: marked
-- melloNoInk, a label inked already given its colour back); a close button
-- on the kit's close states. Only textures and frames of our own are added
-- and the game's art faded (the ready check's and the queues' buttons may
-- be protected); the plate keeps the button's disabled look.
--------------------------------------------------------------------------------
local function SkinButton(button)
	if not button or popupButtons[button] then
		return
	end
	popupButtons[button] = "none"
	button.melloNoInk = true
	local QI = MelloUI.QuestInk
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "FontString" and region.melloInk and QI and QI.PlainText then
			pcall(QI.PlainText, region)
		end
	end
	if Kit.SkinRedButton then
		local ok, rep = pcall(Kit.SkinRedButton, Kit, button, Replace)
		if ok and rep then
			popupButtons[button] = "plate"
			return
		end
	end
	-- a button of another layout: the plate on its LOWEST texture (drawn in
	-- that texture's layer, under the label), its other looks faded
	local anchor, extra, anchorRank = nil, {}, 99
	local RANK = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4 }
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			local okL, layer = pcall(region.GetDrawLayer, region)
			local rank = okL and RANK[layer]
			if rank and rank < anchorRank then
				if anchor then
					extra[#extra + 1] = anchor
				end
				anchor, anchorRank = region, rank
			else
				extra[#extra + 1] = region
			end
		end
	end
	if anchor and Replace(anchor, { as = "_128-RedButton-Center", rect = button, button = button, alsoFade = extra }) then
		popupButtons[button] = "plate"
	end
end

local function SkinClose(button)
	if not button or popupButtons[button] then
		return
	end
	popupButtons[button] = "none"
	button.melloNoInk = true
	local normal = button.GetNormalTexture and button:GetNormalTexture()
	if normal and Replace(normal, { as = "RedButton-Exit", button = button, alsoFade = Kit:OtherTextures(button, normal) }) then
		popupButtons[button] = "close"
	end
end

-- a popup's buttons: its text buttons (a label, or a plate's shape) and its
-- close button, on the popup and on the ready check's listener
local function Buttons(popup)
	local list, closes = {}, {}
	for _, owner in ipairs(Owners(popup)) do
		for _, child in ipairs({ owner:GetChildren() }) do
			if child:GetObjectType() == "Button" then
				local name = NameOf(child) or ""
				if child == owner.CloseButton or name:find("CloseButton$") then
					closes[#closes + 1] = child
				elseif not child.Icon then
					local fs = child.GetFontString and child:GetFontString()
					local okT, text = false, nil
					if fs then
						okT, text = pcall(fs.GetText, fs)
					end
					if child.Left or child.Middle or child.Center or (okT and type(text) == "string" and not Secret(text) and text ~= "") then
						list[#list + 1] = child
					end
				end
			end
		end
	end
	return list, closes
end

--------------------------------------------------------------------------------
-- The ready check's portrait (WINDOW-RULES 2b / 2c: an empty ring is a bug).
-- The game draws the initiator into the portrait (SetPortraitTexture). A
-- client that frames the check with a portrait window's nine-slice has the
-- portrait corner: the window's ring on it (the shell's ring rule), as on
-- every window. The classic check paints its ring into its one picture,
-- which is faded: the kit's ring stands in for that painted ring, a region
-- of the portrait's own frame over the portrait, sized so that the portrait
-- at the class medallion's size (0.759 x the ring) keeps its own size.
-- Either way the portrait is fitted to the medallion size (Kit:FitPortrait)
-- on the dark disc (Kit:RingDisc), and put back on disable.
--------------------------------------------------------------------------------
local function PortraitSize(portrait)
	local ok, w, h = pcall(portrait.GetSize, portrait)
	if ok and w and h and not Secret(w) and not Secret(h) and w > 0 and h > 0 then
		return math.min(w, h)
	end
	return 50   -- the classic check's portrait
end

local function FitRing(popup)
	local skin = skins[popup]
	local portrait = Portrait(popup)
	if active and skin and skin.ring and portrait then
		pcall(Kit.FitPortrait, Kit, portrait, skin.ring)
	end
end

local function SkinPortrait(popup, skin)
	local portrait = Portrait(popup)
	if not portrait then
		return
	end
	local body = Body(popup)
	local owner = portrait:GetParent()
	local corner = body.NineSlice and body.NineSlice.TopLeftCorner
	local ring
	if corner then
		ring = Replace(corner, { as = "UI-Frame-PortraitMetal-CornerTopLeft", parent = owner, center = portrait })
		skin.ringKind = "the window ring on the portrait corner"
	else
		-- the ring's OPENING, centred on the portrait: the ring round it is
		-- then the portrait's size / 0.759 across
		local s = PortraitSize(portrait)
		local p = Kit:Piece("window/portrait_ring")
		local open = (p and p.open) and (p.open[3] - p.open[1]) / p.w or 0.61
		local hole = CreateFrame("Frame", nil, owner)
		hole:EnableMouse(false)
		hole:SetPoint("CENTER", portrait, "CENTER")
		hole:SetSize(s / MEDALLION_TO_RING * open, s / MEDALLION_TO_RING * open)
		skin.hole = hole
		ring = Replace(portrait, { as = "UnitFramePortraitRingParty", rect = hole, noFade = true })
		skin.ringKind = "the kit ring round the portrait (the painted ring was the faded picture's)"
	end
	if not ring then
		return
	end
	skin.ring = ring
	ring.onEnable = function()
		pcall(Kit.FitPortrait, Kit, portrait, ring)
	end
	ring.onDisable = function()
		pcall(Kit.UnfitPortrait, Kit, portrait)
	end
	-- the disc under the portrait: in its layer, one sublevel below it
	local okL, layer, sub = pcall(portrait.GetDrawLayer, portrait)
	local discSub = 7
	if okL and layer == "BACKGROUND" then
		discSub = math.max((sub or 0) - 1, -8)
	end
	skin.disc = Kit:RingDisc(ring, nil, owner, discSub)
end

--------------------------------------------------------------------------------
-- The title (WINDOW-RULES 2c), where the client gives the check one (a title
-- container on a portrait window's frame): the kit's title plate across the
-- container at 1.5 x its height as on every window, the title centred on
-- the plate's painted box in the title face, put back on disable. The
-- classic check has no title: its message is its only text.
--------------------------------------------------------------------------------
local function SkinTitle(popup, skin)
	local text, tc = TitleText(popup)
	if not (text and tc) then
		return
	end
	local body = Body(popup)
	local titleRule = Kit.Replacements and Kit.Replacements.TitleBar
	local ok, h = pcall(tc.GetHeight, tc)
	if not ok or Secret(h) or not (h and h > 0) then
		h = 20
	end
	local band = CreateFrame("Frame", nil, body)
	band:EnableMouse(false)
	band:SetPoint("LEFT", tc, "LEFT")
	band:SetPoint("RIGHT", tc, "RIGHT")
	band:SetHeight(h * (titleRule and titleRule.heightScale or 1.5))
	local rep = Replace(band, { as = "ui-questtracker-primary-objective-header", parent = body, rect = band, level = 0, noFade = true })
	if not rep then
		return
	end
	skin.title = rep
	local saved = {}
	for i = 1, text:GetNumPoints() do
		saved[i] = { text:GetPoint(i) }
	end
	rep.onEnable = function()
		local strip = rep.strip
		local mid = strip and Kit:Piece(Kit:StripPieceName(strip.base, "mid", strip.state))
		local dy = 0
		if mid and mid.box then
			dy = (mid.h / 2 - (mid.box[2] + mid.box[4]) / 2) * (strip.scale or Kit.scale)
		end
		text:ClearAllPoints()
		text:SetPoint("CENTER", strip or band, "CENTER", 0, dy)
		Kit:TitleFont(text, true)
	end
	rep.onDisable = function()
		Kit:TitleFont(text, false)
		text:ClearAllPoints()
		for _, pt in ipairs(saved) do
			text:SetPoint(unpack(pt))
		end
	end
end

--------------------------------------------------------------------------------
-- A popup dressed, once: the rail and stone under it (a frame one level
-- below the part that draws it), the parchment sheet on the stone and the
-- inner panel for the stone look (Kit:SetParchment switches the two), the
-- buttons, the portrait and the title.
--------------------------------------------------------------------------------
local function Dress(popup)
	if skins[popup] or not (Kit and Kit.NineSlice) then
		return skins[popup]
	end
	local body = Body(popup)
	local ok, nine = pcall(Kit.NineSlice, Kit, body, { prefix = "window/single", scale = Kit.scale * (Kit.frameScale or 1.6),
		gems = false, body = true, level = -1 })
	if not (ok and nine) then
		return nil
	end
	local alive = function() return active end
	local sheet = Kit.ParchmentSheet and Kit:ParchmentSheet(nine, nine, { area = AREA, fine = true, margin = 2, alive = alive })
	local dim = Kit.StoneDim and Kit:StoneDim(nine, { area = AREA, alive = alive })
	local skin = { nine = nine, sheet = sheet, dim = dim }
	skins[popup] = skin
	local buttons, closes = Buttons(popup)
	for _, b in ipairs(buttons) do
		pcall(SkinButton, b)
	end
	for _, b in ipairs(closes) do
		pcall(SkinClose, b)
	end
	pcall(SkinPortrait, popup, skin)
	pcall(SkinTitle, popup, skin)
	nine:SetShown(active)
	return skin
end

--------------------------------------------------------------------------------
-- The ink (the parchment rule): the popups' strings on the sheet are dark
-- ink while the Dialogs' parchment is on, set for the sheet's darker paper;
-- a button's label, the title on its plate and a string on the dungeon's
-- picture keep their colours
--------------------------------------------------------------------------------
local function InkOn()
	return active and Kit.ParchmentOn and Kit:ParchmentOn(AREA) or false
end

-- whether fs lies on `region` (the dungeon's picture); nil when unknown
local function Over(fs, region)
	local okF, fx, fy = pcall(fs.GetCenter, fs)
	local okR, l, b, w, h = pcall(region.GetRect, region)
	if not (okF and okR and fx and l and w) or Secret(fx) or Secret(l) then
		return nil
	end
	local k = fs:GetEffectiveScale() / region:GetEffectiveScale()
	fx, fy = fx * k, fy * k
	return fx >= l and fx <= l + w and fy >= b and fy <= b + h
end

local surfaceMade = false
local function Surface()
	local QI = MelloUI.QuestInk
	if not QI then
		return
	end
	if surfaceMade then
		QI.RefreshSurface(SURFACE)
		return
	end
	surfaceMade = true
	local function Skip(fs)
		local p = fs.GetParent and fs:GetParent()
		for _ = 1, 3 do
			if not p then
				break
			end
			if popupButtons[p] or (p.GetObjectType and p:GetObjectType() == "Button") then
				return true
			end
			p = p.GetParent and p:GetParent()
		end
		for _, popup in ipairs(Popups()) do
			local pic = popup.background
			if pic and pic.IsShown and pic:IsShown() then
				local over = Over(fs, pic)
				if over == nil then
					return nil
				elseif over then
					return true
				end
			end
		end
		return QI.DefaultSkip(fs)
	end
	QI.Surface(SURFACE, { on = InkOn, sheet = true, skip = Skip, roots = function() return unpack(Popups()) end })
end

-- the Dialogs' parchment switched: this module's strings follow (the ink
-- engine refreshes by itself only the surface named after the area)
if Kit and Kit.SetParchment then
	hooksecurefunc(Kit, "SetParchment", function(_, area)
		if area == AREA and surfaceMade and MelloUI.QuestInk then
			MelloUI.QuestInk.RefreshSurface(SURFACE)
		end
	end)
end

--------------------------------------------------------------------------------
-- Switching on and off
--------------------------------------------------------------------------------
local function ShowSkin(popup)
	local skin = Dress(popup)
	if skin then
		skin.nine:Show()
		FadeArt(popup)
	end
	return skin
end

local function Activate()
	if active then
		return
	end
	active = true
	for _, popup in ipairs(Popups()) do
		ShowSkin(popup)
	end
	for _, rep in ipairs(reps) do
		rep:Enable()
	end
	if Kit.SetParchment then
		Kit:SetParchment(AREA, Kit:ParchmentOn(AREA))
	end
	Surface()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, popup in ipairs(Popups()) do
		local skin = skins[popup]
		if skin then
			skin.nine:Hide()
		end
		UnfadeArt(popup)
	end
	for _, rep in ipairs(reps) do
		rep:Disable()
	end
	if surfaceMade and MelloUI.QuestInk then
		MelloUI.QuestInk.RefreshSurface(SURFACE)
	end
end

local function Safe(fn)
	if Kit and Kit.WhenOutOfCombat then
		Kit:WhenOutOfCombat(fn)
	else
		fn()
	end
end

-- a popup shown: dressed (a client may make it late), its art faded again
-- (the game may re-lay its border on every show), its portrait fitted once
-- laid out, its text inked
local function OnPopupShown(popup)
	if not active then
		return
	end
	Safe(function()
		if not active then
			return
		end
		ShowSkin(popup)
		FitRing(popup)
		C_Timer.After(0, function()
			FitRing(popup)
		end)
		if surfaceMade and MelloUI.QuestInk then
			MelloUI.QuestInk.RefreshSurface(SURFACE)
		end
	end)
end

local function HookPopups()
	for _, popup in ipairs(Popups()) do
		if not hookedPopups[popup] then
			hookedPopups[popup] = true
			popup:HookScript("OnShow", function(self)
				OnPopupShown(self)
			end)
			local body = Body(popup)
			if body ~= popup then
				body:HookScript("OnShow", function()
					OnPopupShown(popup)
				end)
			end
			if active then
				ShowSkin(popup)
			end
		end
	end
end

-- a popup made by an addon the game loads later (the dungeon finder, the
-- battleground helper): watched and dressed once it exists
local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function()
	C_Timer.After(0, function()
		if M.isEnabled then
			Safe(HookPopups)
		end
	end)
end)
pcall(watcher.RegisterEvent, watcher, "ADDON_LOADED")

function M:OnEnable(db)
	self.db = db
	Safe(function()
		HookPopups()
		Activate()
	end)
end

function M:OnDisable()
	Safe(Deactivate)
end

--------------------------------------------------------------------------------
-- /readydump [ready | lfg | pvp] [frames | reps | regions]: for each popup
-- (or the group asked for) what was found and what it was dressed as, the
-- portrait against the medallion, the title's place and face, the inked
-- strings, the popup's own regions and children; a mode is Kit:DumpWindow's
-- for the first popup of the group. Opens the copy window.
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

local function Shown(obj)
	local ok, s = pcall(obj.IsShown, obj)
	return (ok and not Secret(s)) and tostring(s) or "?"
end

local function Num(v)
	return (type(v) == "number" and not Secret(v)) and string.format("%.0f", v) or "?"
end

local function Size(obj)
	local ok, w, h = pcall(obj.GetSize, obj)
	return ok and (Num(w) .. " x " .. Num(h)) or "?"
end

local function TextOf(fs)
	local ok, t = pcall(fs.GetText, fs)
	if ok and type(t) == "string" and not Secret(t) then
		return (t:gsub("\n", " | ")):sub(1, 50)
	end
	return "?"
end

local function FontOf(fs)
	local ok, face, size = pcall(fs.GetFont, fs)
	if ok and type(face) == "string" and not Secret(face) then
		return (face:match("([^\\/]+)$") or face) .. " " .. Num(size)
	end
	return "?"
end

local function Alpha(obj)
	local ok, a = pcall(obj.GetAlpha, obj)
	return (ok and not Secret(a) and a) and string.format("%.2f", a) or "?"
end

local function DumpOwn(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		local kind = region:GetObjectType()
		local okL, layer = pcall(region.GetDrawLayer, region)
		local art = ""
		if kind == "Texture" then
			art = tostring(Kit:ArtKey(region) or "?") .. (region.kitPiece and " (kit)" or "") .. (Kit.faded[region] and " FADED" or "")
		elseif kind == "FontString" then
			art = "text: " .. TextOf(region)
		end
		MelloUI:Print("    region %s %s %s %s alpha %s shown %s", kind, Label(region), okL and tostring(layer) or "?", art, Alpha(region), Shown(region))
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local okLv, lv = pcall(child.GetFrameLevel, child)
		MelloUI:Print("    child %s %s level %s shown %s%s%s", tostring(child:GetObjectType()), Label(child),
			okLv and Num(lv) or "?", Shown(child), child.layoutType and (" layout " .. tostring(child.layoutType)) or "",
			(Kit.faded[child] and " FADED") or (child.melloSkin and " (kit skin)") or "")
	end
end

local function DumpPopup(e)
	local popup = _G[e.name]
	if not (type(popup) == "table" and popup.GetChildren) then
		MelloUI:Print("%s (%s): not on this client", e.label, e.name)
		return
	end
	local skin = skins[popup]
	local okLv, lv = pcall(popup.GetFrameLevel, popup)
	MelloUI:Print("%s (%s): shown %s, size %s, level %s, strata %s; kit %s, parchment %s", e.label, e.name, Shown(popup), Size(popup),
		okLv and Num(lv) or "?", tostring(popup:GetFrameStrata()), active and "on" or "off", tostring(Kit.ParchmentOn and Kit:ParchmentOn(AREA)))
	local body = Body(popup)
	Found("drawn by", body, body ~= popup and " (the listener: the part shown to those asked)" or " (the popup itself)")
	Found("kit rail + stone", skin and skin.nine, skin and string.format(" shown %s, sheet %s (shown %s), inner panel %s (shown %s)",
		Shown(skin.nine), tostring(skin.sheet ~= nil), skin.sheet and Shown(skin.sheet) or "-", tostring(skin.dim ~= nil),
		skin.dim and Shown(skin.dim) or "-") or " (not dressed yet)")
	for _, key in ipairs({ "Border", "NineSlice", "Bg" }) do
		local part = body[key] or popup[key]
		if part then
			Found("game " .. key, part, Kit.faded[part] and " faded" or " NOT faded")
		end
	end
	local n = 0
	for _ in pairs(fadedArt[popup] or {}) do
		n = n + 1
	end
	MelloUI:Print("  game art faded: %d", n)
	if popup.background then
		Found("picture (kept)", popup.background, string.format(" art %s, alpha %s", tostring(Kit:ArtKey(popup.background)), Alpha(popup.background)))
	end
	if e.key == "ready" then
		local portrait = Portrait(popup)
		if portrait then
			local okT, file = pcall(portrait.GetTexture, portrait)
			local ringTex = skin and skin.ring and skin.ring.tex
			local okR, ringW = false, nil
			if ringTex then
				okR, ringW = pcall(ringTex.GetWidth, ringTex)
			end
			local okP, pw = pcall(portrait.GetWidth, portrait)
			Found("portrait", portrait, string.format(" file %s, size %s, fitted %s, shown %s", (okT and not Secret(file)) and tostring(file) or "?",
				Size(portrait), tostring(portrait.melloSaved ~= nil), Shown(portrait)))
			Found("ring", ringTex, skin and skin.ring and string.format(" %s, %s px; medallion %s px vs portrait %s px; disc %s",
				tostring(skin.ringKind), okR and Num(ringW) or "?", (okR and type(ringW) == "number" and not Secret(ringW)) and Num(ringW * MEDALLION_TO_RING) or "?",
				okP and Num(pw) or "?", tostring(skin.disc ~= nil)) or nil)
		else
			Found("portrait", nil)
		end
		local title, tc = TitleText(popup)
		if title then
			local okC, cx, cy = pcall(title.GetCenter, title)
			local strip = skin and skin.title and skin.title.strip
			local okS, sx, sy = false, nil, nil
			if strip then
				okS, sx, sy = pcall(strip.GetCenter, strip)
			end
			Found("title", title, string.format(" \"%s\" font %s, title face %s, centre %s,%s, plate centre %s,%s", TextOf(title), FontOf(title),
				tostring(title.melloFontSaved ~= nil), okC and Num(cx) or "?", okC and Num(cy) or "?", okS and Num(sx) or "-", okS and Num(sy) or "-"))
		else
			Found("title", tc, " (no title on this client's check: its message is its only text)")
		end
	end
	local msg = MessageText(popup)
	if msg then
		Found("message", msg, string.format(" \"%s\" font %s, inked %s", TextOf(msg), FontOf(msg), tostring(msg.melloInk ~= nil)))
	end
	local buttons, closes = Buttons(popup)
	for _, b in ipairs(buttons) do
		local okP, prot = pcall(b.IsProtected, b)
		local fs = b.GetFontString and b:GetFontString()
		Found("button", b, string.format(" \"%s\" as %s, protected %s, shown %s", fs and TextOf(fs) or "", tostring(popupButtons[b] or "not dressed"),
			(okP and not Secret(prot)) and tostring(prot) or "?", Shown(b)))
	end
	for _, b in ipairs(closes) do
		Found("close button", b, " as " .. tostring(popupButtons[b] or "not dressed"))
	end
	MelloUI:Print("  own regions and children:")
	DumpOwn(popup)
	if body ~= popup then
		MelloUI:Print("  the listener's regions and children:")
		DumpOwn(body)
	end
end

SLASH_MELLOREADYDUMP1 = "/readydump"
SlashCmdList.MELLOREADYDUMP = function(msg)
	msg = ((msg or ""):lower()):match("^%s*(.-)%s*$")
	local group, mode = msg:match("^(%S*)%s*(.-)$")
	if group ~= "ready" and group ~= "lfg" and group ~= "pvp" then
		group, mode = nil, msg
	end
	MelloUI:ClearLog()
	if mode == "" then
		for _, e in ipairs(POPUPS) do
			if not group or e.group == group then
				DumpPopup(e)
			end
		end
		local QI = MelloUI.QuestInk
		local def = QI and QI.surfaces and QI.surfaces[SURFACE]
		local n = 0
		MelloUI:Print("inked strings (parchment ink %s):", tostring(InkOn()))
		for fs in pairs(def and def.strings or {}) do
			n = n + 1
			MelloUI:Print("  %s \"%s\"", Label(fs), TextOf(fs))
		end
		MelloUI:Print("  %d inked", n)
	else
		local target
		for _, e in ipairs(POPUPS) do
			local f = _G[e.name]
			if not target and (not group or e.group == group) and type(f) == "table" and f.GetChildren then
				target = f
			end
		end
		if target then
			Kit:DumpWindow(target, { reps = reps }, mode ~= "regions" and mode or nil)
		else
			MelloUI:Print("/readydump: no such popup on this client")
		end
	end
	MelloUI:ShowLog("readydump " .. msg)
end
