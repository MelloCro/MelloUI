--------------------------------------------------------------------------------
-- MelloUI - Dialogs Kit
--
-- The game's popup dialogs (StaticPopup1..4: the world refresh notice, a
-- confirmation, "Release spirit", ...) in the painted kit (user, 2026-09-24:
-- "this window popus up every now and then, can we reskin this aswell"):
-- the single rail with its stone round the dialog, the game's own box faded,
-- its buttons on the kit's red plates. With the Parchment option for dialogs
-- (Dynamic UI Modification, Parchment: Dialogs; "and also add a parchment to
-- it") a parchment sheet with the painted edge lies on the stone and the
-- message is dark ink by the parchment rule, set for the sheet's darker
-- paper (QuestInk's sheet inks, 4.5 : 1). The dialogs' size, place and
-- behaviour stay the game's; nothing of theirs is replaced.
--
-- The guild invitation too (user, 2026-09-24: "can we also reskin the Guild
-- Invite popup"): a client that asks with a popup dialog is covered above;
-- one with its own invitation window (GuildInviteFrame: the guild's tabard,
-- the inviter's and the guild's names, Join / Decline) gets the same dress,
-- the tabard left as the game draws it. That window may be made only when an
-- invitation comes (GUILD_INVITE_REQUEST): it is dressed then.
--
-- /dialogdump [n | guild]: what a dialog is made of (its regions and
-- children), to fit the skin to a client whose dialog differs.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("DialogPanel", {
	title = "Dialogs Kit",
	desc = "The game's popup dialogs on the kit's stone and rail with red plate buttons, and a parchment sheet if you choose one.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local MAX_POPUPS = 4
local AREA = "dialog"
local active = false
local reps = {}                                         -- every replacement (the buttons), for enable / disable
local skins = setmetatable({}, { __mode = "k" })        -- [dialog] = { nine, sheet }
local fadedArt = setmetatable({}, { __mode = "k" })     -- [dialog] = { the game's art we faded }

local function Replace(region, opts)
	local rep = Kit and Kit.Replace and Kit:Replace(region, opts)
	if rep then
		reps[#reps + 1] = rep
		if active then
			rep:Enable()
		end
	end
	return rep
end

-- the dialogs that are not popups: their frame's name and their buttons'
local OTHER_DIALOGS = {
	{ name = "GuildInviteFrame", buttons = { "GuildInviteFrameJoinButton", "GuildInviteFrameDeclineButton" } },
	-- the world refresh notice ("The world around you will refresh in 8
	-- Minutes"; user, 2026-09-24, /fstack): a toast of its own, its dark box
	-- (a Center piece and its border) under the text and the arrow icon
	{ name = "ShardTransferImminentFrame", buttons = {} },
}
local otherButtons = {}   -- [dialog name] = its buttons' names
for _, d in ipairs(OTHER_DIALOGS) do
	otherButtons[d.name] = d.buttons
end

local function Dialogs()
	local list = {}
	for i = 1, MAX_POPUPS do
		local f = _G["StaticPopup" .. i]
		if f then
			list[#list + 1] = f
		end
	end
	for _, d in ipairs(OTHER_DIALOGS) do
		local f = _G[d.name]
		if f and f.GetChildren then
			list[#list + 1] = f
		end
	end
	return list
end

-- art that is the dialog's content, not its box: the guild's tabard and
-- emblem, an alert icon
local function IsContent(region)
	local name = region.GetName and region:GetName()
	if type(name) == "string" and (name:find("Tabard") or name:find("Emblem") or name:find("Icon")) then
		return true
	end
	return false
end

-- The game's dialog box: its border and background, whatever this client
-- makes them of -- a nine-slice child (Border, NineSlice or one with a
-- layout), a background child, and the dialog's own textures in its
-- BACKGROUND and BORDER layers (the icon, the text and the buttons are in
-- higher layers or are frames of their own, and stay)
local function GameArt(dialog)
	local list, seen = {}, {}
	local function Add(obj)
		if obj and not seen[obj] and obj ~= skins[dialog] and not (skins[dialog] and obj == skins[dialog].nine) then
			seen[obj] = true
			list[#list + 1] = obj
		end
	end
	for _, key in ipairs({ "Border", "NineSlice", "BG", "Bg", "Background", "DialogBG" }) do
		Add(dialog[key])
	end
	for _, child in ipairs({ dialog:GetChildren() }) do
		local name = child.GetName and child:GetName()
		if child.layoutType or (type(name) == "string" and (name:find("Border$") or name:find("NineSlice$"))) then
			Add(child)
		end
	end
	for _, region in ipairs({ dialog:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece and not IsContent(region) then
			local layer = region:GetDrawLayer()
			if layer == "BACKGROUND" or layer == "BORDER" then
				Add(region)
			end
		end
	end
	return list
end

local function DialogButtons(dialog)
	local list = {}
	local name = dialog:GetName()
	for i = 1, 4 do
		local b = dialog["button" .. i] or (name and _G[name .. "Button" .. i])
		if b then
			list[#list + 1] = b
		end
	end
	for _, key in ipairs({ "extraButton", "ExtraButton", "JoinButton", "DeclineButton" }) do
		if dialog[key] then
			list[#list + 1] = dialog[key]
		end
	end
	for _, bname in ipairs(name and otherButtons[name] or {}) do
		if _G[bname] then
			list[#list + 1] = _G[bname]
		end
	end
	return list
end

-- A dialog's button on the kit's red plate. Kit:SkinRedButton knows the
-- game's two button layouts (Left / Middle / Right, or a Center piece);
-- this client builds a popup's buttons otherwise (user, 2026-09-24: the
-- logout dialog's Cancel kept the game's flat red bar), so a button it
-- does not know gets the plate laid on its own rect, its own textures (the
-- bar, its pushed and highlight looks) faded under it.
local dialogButtons = setmetatable({}, { __mode = "k" })   -- [button] = true: a dialog's button (its text is not inked)
local labelLayers = setmetatable({}, { __mode = "k" })     -- [label] = { its own layer, sublevel }: raised over the plate

local function SkinDialogButton(button)
	dialogButtons[button] = true
	-- the exception to the parchment rule (user, 2026-09-24: "maybe we can
	-- add exception to button text"): a button's label is on its red plate,
	-- not on the paper -- the ink's walk never enters the button (the flag
	-- QuestInk's Walk honours, as the tracker's headers use it), and a label
	-- inked already gets its own colour back
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
			return
		end
	end
	-- the plate goes on the button's LOWEST texture (it is drawn in that
	-- texture's layer): on one above the label it covered it (user,
	-- 2026-09-24: the logout dialog's Cancel stayed unreadable, no ink on it)
	local anchor, extra, anchorRank = nil, {}, 99
	local RANK = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4 }
	for _, region in ipairs({ button:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			local rank = RANK[region:GetDrawLayer()]
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
	for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local tex = button[get] and button[get](button)
		if tex and tex ~= anchor then
			extra[#extra + 1] = tex
		end
	end
	if anchor then
		Replace(anchor, { as = "_128-RedButton-Center", rect = button, button = button, alsoFade = extra })
	end
	-- and the label on top of everything the button draws, while dressed
	local label = button.GetFontString and button:GetFontString()
	if label and label.GetDrawLayer then
		local layer, sub = label:GetDrawLayer()
		labelLayers[label] = { layer, sub }
		if active then
			pcall(label.SetDrawLayer, label, "OVERLAY", 7)
		end
	end
end

-- the labels raised while the dialogs are dressed, back when they are not
local function RaiseLabels(on)
	for label, was in pairs(labelLayers) do
		if on then
			pcall(label.SetDrawLayer, label, "OVERLAY", 7)
		elseif was[1] then
			pcall(label.SetDrawLayer, label, was[1], was[2] or 0)
		end
	end
end

-- the kit on one dialog, made once: the rail and stone under it (a frame one
-- level below the dialog, so its text and icon stay over it), the parchment
-- sheet on the stone, the buttons on the red plates
local function Dress(dialog)
	if skins[dialog] or not (Kit and Kit.NineSlice) then
		return skins[dialog]
	end
	local ok, nine = pcall(Kit.NineSlice, Kit, dialog, { prefix = "window/single", scale = Kit.scale * (Kit.frameScale or 1.6),
		gems = false, body = true, level = -1 })
	if not (ok and nine) then
		return nil
	end
	local sheet = Kit.ParchmentSheet and Kit:ParchmentSheet(nine, nine, { area = AREA, fine = true, margin = 2,
		alive = function() return active end })
	-- no eye strain (user, 2026-09-24: "too much small text over a plain
	-- brown border is just an eye strain" / "apply the eye strain rule to all
	-- existing windows"; WINDOW-RULES 2e): a dialog is its message, so on the
	-- stone look (the dialogs' parchment off) the stone inside the rail lies
	-- under the palette's inner panel -- a region of our skin between the
	-- stone and the sheet, under the dialog's text (the skin is a level below
	-- the dialog); Kit:SetParchment switches it against the sheet
	local dim = Kit.StoneDim and Kit:StoneDim(nine, { area = AREA, alive = function() return active end })
	skins[dialog] = { nine = nine, sheet = sheet, dim = dim }
	for _, button in ipairs(DialogButtons(dialog)) do
		pcall(SkinDialogButton, button)
	end
	nine:SetShown(active)
	return skins[dialog]
end

local function FadeArt(dialog)
	fadedArt[dialog] = fadedArt[dialog] or {}
	for _, obj in ipairs(GameArt(dialog)) do
		Kit:Fade(obj)
		fadedArt[dialog][obj] = true
	end
end

local function UnfadeArt(dialog)
	for obj in pairs(fadedArt[dialog] or {}) do
		Kit:Unfade(obj)
	end
	fadedArt[dialog] = nil
end

-- the dialogs' text on the parchment: a QuestInk surface (on while the
-- dialogs are dressed and their parchment is on), its strings on a sheet
local function InkOn()
	return active and Kit.ParchmentOn and Kit:ParchmentOn(AREA) or false
end

local surfaceMade = false
local function Surface()
	local QI = MelloUI.QuestInk
	if not QI then
		return
	end
	if not surfaceMade then
		surfaceMade = true
		-- a button's label stays in its own colour on its red plate (user,
		-- 2026-09-24: the inked Cancel was "hard to read")
		local function Skip(fs)
			local p = fs.GetParent and fs:GetParent()
			for _ = 1, 3 do
				if not p then
					break
				end
				-- one of the dialog's buttons, or any button at all (this
				-- client may keep a popup's buttons in a container of their
				-- own, their labels not where the buttons were found)
				if dialogButtons[p] or (p.GetObjectType and p:GetObjectType() == "Button") then
					return true
				end
				p = p.GetParent and p:GetParent()
			end
			return QI.DefaultSkip(fs)
		end
		-- the world refresh notice is written in the game's system blue,
		-- which means nothing on it: the body ink (user, 2026-09-24: "the text
		-- is blue, probably because its a blizzard message")
		local function PlainInk(fs)
			local notice = _G.ShardTransferImminentFrame
			local p = fs.GetParent and fs:GetParent()
			return notice ~= nil and (p == notice or (p and p.GetParent and p:GetParent() == notice))
		end
		QI.Surface(AREA, { on = InkOn, sheet = true, skip = Skip, plainInk = PlainInk, roots = function() return unpack(Dialogs()) end })
	else
		QI.RefreshSurface(AREA)
	end
end

local function Activate()
	if active then
		return
	end
	active = true
	for _, dialog in ipairs(Dialogs()) do
		local skin = Dress(dialog)
		if skin then
			skin.nine:Show()
			FadeArt(dialog)
		end
	end
	for _, rep in ipairs(reps) do
		rep:Enable()
	end
	RaiseLabels(true)
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
	for _, dialog in ipairs(Dialogs()) do
		local skin = skins[dialog]
		if skin then
			skin.nine:Hide()
			if skin.sheet then
				skin.sheet:Hide()
			end
		end
		UnfadeArt(dialog)
	end
	for _, rep in ipairs(reps) do
		rep:Disable()
	end
	RaiseLabels(false)
	Surface()
end

-- a dialog shown: dressed (a client may make its frames late), its art
-- faded again (the game re-lays its border on every show), its text inked
local hookedDialogs = setmetatable({}, { __mode = "k" })
local HookDialogs
local invites = CreateFrame("Frame")
invites:SetScript("OnEvent", function()
	-- the invitation window is made (or shown) by the game now: hooked and
	-- dressed a moment later, once it exists
	C_Timer.After(0, function()
		HookDialogs()
		local f = _G.GuildInviteFrame
		if active and f and skins[f] == nil and f:IsShown() then
			local skin = Dress(f)
			if skin then
				skin.nine:Show()
				FadeArt(f)
			end
		end
	end)
end)
pcall(invites.RegisterEvent, invites, "GUILD_INVITE_REQUEST")
pcall(invites.RegisterEvent, invites, "ADDON_LOADED")

local hooked = false
local function Hook()
	if hooked then
		return
	end
	hooked = true
	HookDialogs()
end

-- every dialog there is now watched once (the invitation window may come
-- later: GUILD_INVITE_REQUEST / ADDON_LOADED call this again)
function HookDialogs()
	for _, dialog in ipairs(Dialogs()) do
		if not hookedDialogs[dialog] then
			hookedDialogs[dialog] = true
			dialog:HookScript("OnShow", function(self)
				if not active then
					return
				end
				local skin = Dress(self)
				if skin then
					skin.nine:Show()
					FadeArt(self)
				end
				local QI = MelloUI.QuestInk
				if QI and surfaceMade then
					QI.RefreshSurface(AREA)
				end
			end)
		end
	end
end

function M:OnEnable()
	Hook()
	if Kit and Kit.WhenOutOfCombat then
		Kit:WhenOutOfCombat(Activate)
	else
		Activate()
	end
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /dialogdump [n]: dialog n (1 by default) -- its regions and children, what
-- the skin faded and made; opens the copy window
--------------------------------------------------------------------------------
SLASH_MELLODIALOGDUMP1 = "/dialogdump"
SlashCmdList.MELLODIALOGDUMP = function(msg)
	local n = tonumber(msg) or 1
	local dialog = _G["StaticPopup" .. n]
	local label = "StaticPopup" .. n
	if msg == "guild" then
		dialog, label = _G.GuildInviteFrame, "GuildInviteFrame"
	elseif not tonumber(msg) and msg ~= "" and type(_G[msg]) == "table" and _G[msg].GetRegions then
		-- any frame by its name (the world refresh notice: ShardTransferImminentFrame)
		dialog, label = _G[msg], msg
	end
	MelloUI:ClearLog()
	if not dialog then
		MelloUI:Print("/dialogdump: no %s on this client%s", label,
			msg == "guild" and " (a guild invitation comes as a popup dialog here, dressed with the others)" or "")
		MelloUI:ShowLog("dialogdump")
		return
	end
	MelloUI:Print("%s: shown %s, size %.0f x %.0f, level %d, strata %s; kit %s, parchment %s", label, tostring(dialog:IsShown()),
		dialog:GetWidth(), dialog:GetHeight(), dialog:GetFrameLevel(), tostring(dialog:GetFrameStrata()),
		active and "on" or "off", tostring(Kit.ParchmentOn and Kit:ParchmentOn(AREA)))
	for _, region in ipairs({ dialog:GetRegions() }) do
		local kind = region:GetObjectType()
		local layer = region.GetDrawLayer and region:GetDrawLayer() or "?"
		local art = kind == "Texture" and (Kit:ArtKey(region) or "?") or (kind == "FontString" and ("text: " .. tostring(region:GetText()):sub(1, 40)) or "")
		MelloUI:Print("  region %s %s %s alpha %.2f shown %s", kind, tostring(layer), tostring(art), region:GetAlpha(), tostring(region:IsShown()))
	end
	for _, child in ipairs({ dialog:GetChildren() }) do
		MelloUI:Print("  child %s %s layout %s level %d alpha %.2f shown %s", tostring(child:GetObjectType()),
			tostring(child:GetName() or child:GetDebugName()), tostring(child.layoutType), child:GetFrameLevel(), child:GetAlpha(), tostring(child:IsShown()))
	end
	local faded = 0
	for _ in pairs(fadedArt[dialog] or {}) do
		faded = faded + 1
	end
	MelloUI:Print("  kit: dressed %s, game art faded %d, buttons %d", tostring(skins[dialog] ~= nil), faded, #DialogButtons(dialog))
	MelloUI:ShowLog("dialogdump")
end
