--------------------------------------------------------------------------------
-- MelloUI - ConfigPreview
--
-- The Configurator's live preview (0.15.0, the rebuild; the user,
-- 2026-09-27/28: "a picker + live preview in the header"): a sample of the
-- frame picked on the Unit Frames page, drawn from the settings as they are
-- now, so a change shows before the real frame is looked for.
--
--   MelloUI.ConfigPreview.Make(parent, kind, skin) -> preview
--       kind  "unitframe" (the one there is; any other: nil, nothing made)
--       skin  the window's shell (Kit:OwnWindow): the portrait wears the
--             kit's round rim while its look is on; nil: the plain rim
--       A Frame 220 x 96 on a flat inner panel, placed by the caller. Made
--       on the Unit Frames page's first build, never at login.
--   preview:SetPick(pick)  "player", "target", "focus", "pet", "party",
--       "raid", "castbars", "personal" (the page's picks; any other shows
--       the player's)
--   preview:Refresh()      every part read from the settings again, now
--
-- SAMPLE values only: no unit value is read at all. The player's own
-- health, class and name may be secret even out of combat on this client
-- (measured on this client), so every name, class, number and portrait here is
-- made up -- except the Player pick's portrait, which the game's own setter
-- is handed the unit for (SetPortraitTexture(texture, "player"): it returns
-- nothing, and Class Icons' hook on it puts the medallion on as on the real
-- frame). The other portraits: the sample's class medallion while Class
-- Icons' Player Portraits are on (players only: an NPC's portrait is never
-- touched, as on the frames), else the game's portrait of a sample creature
-- (SetPortraitTextureFromCreatureDisplayID, a display id, no unit).
--
-- One system per job: what the bars wear and say comes from the modules that
-- put it on the real frames, through their pure preview exports -- Bar
-- Textures (PreviewTexture, PreviewHealthColor, PreviewPowerColor,
-- PreviewCastColor) and Bar Text (PreviewText, PreviewPlace, PreviewShows);
-- the names' form from Unit Frames' own setting (UnitFrames.nameFormat, which
-- UI Modifications' Show Names As drives, with its Centre Names; the
-- painted skin's name plates centre them while it is on), the
-- medallion from Class Icons (MelloUI:ClassIconPath), the Elite mark from the
-- kit's marks (Kit:MarkCrest, Modules/KitMarks.lua). A part whose setting is
-- off is dimmed where the frame would show nothing (the values, the mark),
-- or shows the game's own look where the frame would (the bars' art).
--
-- It follows the bus's 'setting' and 'module' (the modules above), 'palette'
-- and 'fonts' only while a preview is on show, one Kit:NextFrame per preview
-- however many changes came in a frame; on every show it is read again.
-- No OnUpdate, no ticker, nothing made per refresh. Colours: palette keys
-- (W.Paint) for its own ground, name and edge; the bars' colours are the
-- game's (class, reaction, health, power, cast), as on the real frames.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("ConfigPreview")
local Shared = Perf.Shared
local W = MelloUI.Widgets   -- (Core/Widgets.lua loads before this file)

local Preview = {}
MelloUI.ConfigPreview = Preview

local WIDTH, HEIGHT = 220, 96
local PAD = 8                 -- the parts inside the panel's edge
local GAP = 8                 -- a portrait to its bars
local PORTRAIT = 56           -- the portrait's rim (its picture inside)
local CREST = 20              -- the Elite mark on the portrait's top
local DIM = 0.4               -- a part whose setting is off (a gated row's alpha)
local NAME_TOP, BAR1_TOP, BAR2_TOP = -22, -40, -60   -- the unit layout's lines, below the top
local BAR1_H, BAR2_H = 16, 10
local RAID_W, RAID_H = 120, 52   -- the raid cell (its bar), the name inside its top-left corner

-- the game's own bar art, where the settings leave it on the frame (an atlas
-- where the client has it; else the game's plain bar in the game's colour)
local PLAIN_BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local GAME_HEALTH = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"
-- (0.17.0) its white twin, which Default wears under a health colour (Bar
-- Textures' ColouredDefault: the colour on the green art came out grey-green)
local GAME_HEALTH_WHITE = GAME_HEALTH .. "-Status"
local GAME_CAST = "ui-castingbar-filling-standard"
local GAME_RAID = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
local NO_PORTRAIT = "Interface\\Icons\\INV_Misc_QuestionMark"   -- (a client without the creature portrait)
local CAST_ICON = "Interface\\Icons\\Spell_Holy_Renew"

-- The samples, one per pick: made-up people and numbers (a first and a last
-- name, as characters here have). layout: how the pick is drawn; area: Bar
-- Textures' area for its bars; frame: Bar Text's frame key (the frames it
-- writes values on); centre: Unit Frames' Centre Names reaches it (its
-- ApplyNames: the player's, the target's and the focus's name, never the
-- pet's); plate: the painted unit frame skin centres it on its name plate
-- (UnitFramePanel's CenterName: those three and a party member's); right:
-- the portrait on the right, as the game's target and focus frames have it;
-- display: a creature's display id for its portrait (players with Class
-- Icons off, NPCs always; this client's own displays: an orc warrior, a
-- night elf rogue, a wolf pup, a human priest). class / reaction / fraction /
-- execute are what BarTextures.PreviewHealthColor reads.
local SAMPLES = {
	player = { layout = "unit", area = "unitframes", frame = "player", centre = true, plate = true, you = true,
		first = "Aldric", last = "Vale", class = "PALADIN", reaction = 5,
		health = 8640, max = 12000, power = 5200, powerMax = 6400, token = "MANA",
		label = "Your player frame" },
	target = { layout = "unit", area = "unitframes", frame = "target", centre = true, plate = true, right = true, elite = true,
		first = "Garra", last = "Blackthorn", reaction = 2, execute = true, display = 146966,
		health = 1740, max = 12000, power = 35, powerMax = 100, token = "RAGE",
		label = "The target frame, an elite enemy low on health" },
	focus = { layout = "unit", area = "unitframes", frame = "focus", centre = true, plate = true, right = true,
		first = "Seren", last = "Ashby", class = "ROGUE", reaction = 2, execute = true, display = 147598,
		health = 6200, max = 9800, power = 80, powerMax = 100, token = "ENERGY",
		label = "The focus frame, an enemy player" },
	pet = { layout = "unit", area = "unitframes",
		first = "Ember", last = "Ashpaw", reaction = 5, display = 145568,
		health = 3100, max = 4200, power = 60, powerMax = 100, token = "FOCUS",
		label = "Your pet's frame" },
	party = { layout = "unit", area = "unitframes", plate = true,
		first = "Lina", last = "Brightwater", class = "PRIEST", reaction = 5, display = 147599,
		health = 7900, max = 8800, power = 4100, powerMax = 7000, token = "MANA",
		label = "A party member's frame" },
	raid = { layout = "raid", area = "raidframes",
		first = "Tobin", last = "Hale", class = "WARRIOR", reaction = 5, health = 6600, max = 12000,
		label = "A raid frame" },
	castbars = { layout = "cast", area = "castbars", spell = "Renew", fraction = 0.62, time = "0.9",
		label = "Your cast bar" },
	personal = { layout = "personal", area = "personal", reaction = 5,
		health = 8640, max = 12000, power = 5200, powerMax = 6400, token = "MANA",
		label = "The personal resource display" },
}
local FIRST_PICK = "player"
-- a health sample's fraction, for the colour (the cast's is its progress)
for _, s in pairs(SAMPLES) do
	if s.health then
		s.fraction = s.health / s.max
	end
end

-- the modules whose settings the preview shows (the bus's 'setting' and
-- 'module' for any other are passed over)
local WATCH = { BarTextures = true, BarText = true, UnitFrames = true, ClassIcons = true, UnitFramePanel = true,
	UIModifications = true }

local weakKeys = { __mode = "k" }

--------------------------------------------------------------------------------
-- Reads (settings only: never a unit)
--------------------------------------------------------------------------------

-- a module that is loaded and running, or nil
local function Running(name)
	local m = MelloUI:GetModule(name)
	return (m and m.isEnabled and m.db) and m or nil
end

-- a module whose preview exports are there (its settings read, on or off)
local function Exports(name, fn)
	local m = MelloUI:GetModule(name)
	return (m and m.db and type(m[fn]) == "function") and m or nil
end

-- the name in the form the frames show it: Unit Frames' own copy of Show
-- Names As (the game's full name while that module is off)
local function NameAs(s)
	local uf = Running("UnitFrames")
	local mode = uf and uf.db.nameFormat or "both"
	if mode == "first" then
		return s.first
	elseif mode == "last" then
		return s.last or s.first
	elseif s.last and mode == "initial" then
		return s.first:sub(1, 1) .. ". " .. s.last
	elseif s.last and mode == "firstinitial" then
		return s.first .. " " .. s.last:sub(1, 1) .. "."
	end
	return s.last and (s.first .. " " .. s.last) or s.first
end

-- is an atlas known to this client? (asked once per name)
local atlasKnown = {}
local function Atlas(name)
	if not name then
		return false
	end
	local known = atlasKnown[name]
	if known == nil then
		known = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) and true or false
		atlasKnown[name] = known
	end
	return known
end

--------------------------------------------------------------------------------
-- Painting the bars
--------------------------------------------------------------------------------

-- a bar's picture: the chosen texture; else the game's own art -- `atlas`
-- where the client has it (true: the art carries its colour), else `file`
-- or the game's plain bar
local function Picture(bar, texture, atlas, file)
	if texture then
		bar:SetStatusBarTexture(texture)
		return false
	end
	if Atlas(atlas) then
		bar:SetStatusBarTexture(atlas)
		return true
	end
	bar:SetStatusBarTexture(file or PLAIN_BAR)
	return false
end

-- (a bar that shows its art's own colour)
local function White(bar)
	bar:SetStatusBarColor(1, 1, 1)
end

local function Fill(bar, value, max)
	bar:SetMinMaxValues(0, max)
	bar:SetValue(value)
end

-- the health bar of a unit, a raid frame or the personal display
local function PaintHealth(bar, s, BT)
	local texture, active = BT.PreviewTexture(s.area)
	if s.layout == "raid" then
		-- the game's raid frames colour a member by class (their default);
		-- Bar Textures changes their fill only
		Picture(bar, texture, nil, GAME_RAID)
		bar:SetStatusBarColor(BT.PreviewHealthColor("class", s))
	elseif s.layout == "personal" then
		Picture(bar, texture)
		bar:SetStatusBarColor(BT.PreviewHealthColor("green", s))
	else
		local white = active and BT.db.healthColor ~= "green" and Atlas(GAME_HEALTH_WHITE)
		local coloured = Picture(bar, texture, white and GAME_HEALTH_WHITE or GAME_HEALTH)
		if s.healthAtlas then
			-- (a party member's replica: the party frame's own bar art, and
			-- its white twin under a health colour)
			local twin = s.healthAtlas .. "-Status"
			coloured = Picture(bar, texture, (active and BT.db.healthColor ~= "green" and Atlas(twin)) and twin
				or s.healthAtlas)
		end
		if active then
			-- the module colours the unit frames' health, the game's art too
			bar:SetStatusBarColor(BT.PreviewHealthColor(nil, s))
		elseif coloured then
			White(bar)
		else
			bar:SetStatusBarColor(BT.PreviewHealthColor("green", s))
		end
	end
	Fill(bar, s.health, s.max)
end

local function PaintPower(bar, s, BT)
	local texture = BT.PreviewTexture(s.area)
	local r, g, b, atlas = BT.PreviewPowerColor(s.token)
	-- a flat texture takes the power's colour (RecolorManaBar); the game's
	-- own art carries it
	if Picture(bar, texture, atlas) then
		White(bar)
	else
		bar:SetStatusBarColor(r, g, b)
	end
	Fill(bar, s.power, s.powerMax)
end

local function PaintCast(bar, s, BT)
	local texture, active = BT.PreviewTexture(s.area)
	-- the module colours a cast on any art (RecolorCastBar); the game's own
	-- art carries its colour
	if Picture(bar, texture, GAME_CAST) and not active then
		White(bar)
	else
		bar:SetStatusBarColor(BT.PreviewCastColor())
	end
	Fill(bar, s.fraction, 1)
end

-- a value on a bar, as Bar Text writes and places it; dimmed while the
-- frame would show none
local function PaintValue(fs, bar, frame, power, value, max)
	local BX = Exports("BarText", "PreviewText")
	local text = BX and BX.PreviewText(value, max)
	if not (frame and text) then
		fs:Hide()
		return
	end
	BX.PreviewPlace(fs, bar)
	fs:SetText(text)
	fs:SetAlpha(BX.PreviewShows(frame, power) and 1 or DIM)
	fs:Show()
end

--------------------------------------------------------------------------------
-- The portrait and the Elite mark
--------------------------------------------------------------------------------

-- the kit's round rim on the portrait (a shell's dressing: handed the kit)
local function KitRim(Kit, p)
	p.portrait:SetKit(Kit)
end

local previews = setmetatable({}, weakKeys)   -- [preview] = true

-- a shell switched its look: its previews' rims follow (one shared fn)
local function OnShellKit(shell, on)
	for p in pairs(previews) do
		if p.skin == shell then
			if on then
				shell:Kit(KitRim, p)
			else
				p.portrait:SetKit(false)
			end
		end
	end
end

-- (a portrait is drawn again only when what it shows changes -- not for
-- every value a slider passes -- and on every show: OnShow forgets it)
local function PaintPortrait(p, s)
	local tex = p.portrait.icon
	local ci = Running("ClassIcons")
	local medallions = ci and ci.db.portraits and true or false
	local medallion = medallions and s.class and MelloUI:ClassIconPath(s.class) or nil
	local want = s.you and (medallions and "you, medallion" or "you") or medallion or s.display or NO_PORTRAIT
	if p.portraitShows == want then
		return
	end
	p.portraitShows = want
	tex:SetTexCoord(0, 1, 0, 1)
	-- the game's own portrait of the player (and Class Icons' medallion on
	-- it, through its hook): a setter handed the unit, nothing read
	if s.you and type(SetPortraitTexture) == "function" and pcall(SetPortraitTexture, tex, "player") then
		return
	end
	if medallion then
		tex:SetTexture(medallion)
	elseif s.display and type(_G.SetPortraitTextureFromCreatureDisplayID) == "function"
		and pcall(_G.SetPortraitTextureFromCreatureDisplayID, tex, s.display) then
		return
	else
		tex:SetTexture(NO_PORTRAIT)
		tex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	end
end

-- the Elite mark: shown while the unit frames wear the painted skin (the
-- marks live on its ring), dimmed with the marks off
local function PaintCrest(p, s)
	local crest = p.crest
	local ufp = Running("UnitFramePanel")
	local Kit = MelloUI.Kit
	local piece = s.elite and ufp and Kit and Kit.MarkCrest and Kit:MarkCrest("elite")
	if not piece then
		crest:Hide()
		return
	end
	if crest.kitName ~= piece then
		Kit:Apply(crest, piece)   -- look-ok: the preview of the kit's elite mark (only while the unit frames wear the kit)
	end
	crest:SetAlpha(ufp.db.marks == false and DIM or 1)
	crest:Show()
end

--------------------------------------------------------------------------------
-- Layout (a pick's parts where they go; made once, moved per pick)
--------------------------------------------------------------------------------

local function Lay(p)
	local s = SAMPLES[p.pick]
	local portrait, crest, name, bar1, bar2 = p.portrait, p.crest, p.name, p.bar1, p.bar2
	local layout = s.layout
	portrait:SetShown(layout == "unit")
	crest:Hide()
	name:SetShown(layout == "unit")
	p.cellName:SetShown(layout == "raid")
	bar2:SetShown(layout == "unit" or layout == "personal")
	p.icon:SetShown(layout == "cast")
	p.castText:SetShown(layout == "cast")
	p.castTime:SetShown(layout == "cast")
	p.text1:Hide()
	p.text2:Hide()
	bar1:ClearAllPoints()
	bar2:ClearAllPoints()
	name:ClearAllPoints()
	if layout == "unit" then
		local w = WIDTH - 2 * PAD - PORTRAIT - GAP
		local x = s.right and PAD or (PAD + PORTRAIT + GAP)
		portrait:ClearAllPoints()
		if s.right then
			portrait:SetPoint("RIGHT", p, "RIGHT", -PAD, 0)
		else
			portrait:SetPoint("LEFT", p, "LEFT", PAD, 0)
		end
		name:SetPoint("TOPLEFT", p, "TOPLEFT", x, NAME_TOP)
		name:SetWidth(w)
		bar1:SetSize(w, BAR1_H)
		bar1:SetPoint("TOPLEFT", p, "TOPLEFT", x, BAR1_TOP)
		bar2:SetSize(w, BAR2_H)
		bar2:SetPoint("TOPLEFT", p, "TOPLEFT", x, BAR2_TOP)
	elseif layout == "raid" then
		bar1:SetSize(RAID_W, RAID_H)
		bar1:SetPoint("CENTER", p, "CENTER", 0, 0)
	elseif layout == "cast" then
		p.icon:ClearAllPoints()
		p.icon:SetPoint("LEFT", p, "LEFT", 16, 0)
		bar1:SetSize(160, 18)
		bar1:SetPoint("LEFT", p.icon, "RIGHT", 4, 0)
	else   -- personal
		bar1:SetSize(150, BAR2_H)
		bar1:SetPoint("CENTER", p, "CENTER", 0, 5)
		bar2:SetSize(150, 6)
		bar2:SetPoint("TOP", bar1, "BOTTOM", 0, -3)
	end
end

--------------------------------------------------------------------------------
-- The preview's methods
--------------------------------------------------------------------------------

local function Refresh(p)
	local s = SAMPLES[p.pick]
	local BT = Exports("BarTextures", "PreviewHealthColor")
	if s.layout == "unit" then
		PaintPortrait(p, s)
		PaintCrest(p, s)
		-- centred as the frame's name is: on its plate while the painted skin
		-- is on (Unit Frames' Centre Names then leaves the names to it), else
		-- by Centre Names where it reaches
		local uf = Running("UnitFrames")
		local centred = (s.plate and Running("UnitFramePanel")) or (s.centre and uf and uf.db.centerNames)
		p.name:SetJustifyH(centred and "CENTER" or "LEFT")
		p.name:SetText(NameAs(s))
	elseif s.layout == "raid" then
		p.cellName:SetText(NameAs(s))
	end
	if BT then
		if s.layout == "cast" then
			PaintCast(p.bar1, s, BT)
		else
			PaintHealth(p.bar1, s, BT)
			if s.token then
				PaintPower(p.bar2, s, BT)
			end
		end
	end
	if s.frame then
		PaintValue(p.text1, p.bar1, s.frame, false, s.health, s.max)
		PaintValue(p.text2, p.bar2, s.frame, true, s.power, s.powerMax)
	end
end

-- (a hidden preview is read on its show)
local function SetPick(p, pick)
	p.pick = SAMPLES[pick] and pick or FIRST_PICK
	Lay(p)
	if p:IsVisible() then
		Refresh(p)
	end
end

--------------------------------------------------------------------------------
-- Following the settings while on show
--------------------------------------------------------------------------------

local shown = setmetatable({}, weakKeys)   -- [preview] = true while on show
local nShown = 0

-- the frame after the changes: read again if still on show
local function Later(p)
	if p:IsVisible() then
		Refresh(p)
	end
end

local function AskAll()
	local Kit = MelloUI.Kit
	for p in pairs(shown) do
		Kit:NextFrame(p, Later)
	end
end

-- 'setting' (module, key, value) and 'module' (name, enabled)
local function OnSetting(name)
	if WATCH[name] then
		AskAll()
	end
end

local OnShow = Shared("OnShow on the Configurator's preview", function(p)
	if not shown[p] then
		shown[p] = true
		nShown = nShown + 1
		if nShown == 1 then
			MelloUI:On("setting", OnSetting, Preview)
			MelloUI:On("module", OnSetting, Preview)
			MelloUI:On("palette", AskAll, Preview)
			MelloUI:On("fonts", AskAll, Preview)
		end
	end
	-- (a change made while it was hidden reached no listener: read again,
	-- the portrait too)
	p.portraitShows = nil
	Refresh(p)
end, "script")

local OnHide = Shared("OnHide on the Configurator's preview", function(p)
	if shown[p] then
		shown[p] = nil
		nShown = nShown - 1
		if nShown == 0 then
			MelloUI:Off(Preview)
		end
	end
end, "script")

local OnEnter = Shared("OnEnter on the Configurator's preview (tooltip)", function(p)
	local s = SAMPLES[p.pick]
	W.ShowTooltip(p, "Preview", s.label .. ", drawn with your settings as they are now. The name and the numbers "
		.. "are made up.")
end, "script")

--------------------------------------------------------------------------------
-- Make
--------------------------------------------------------------------------------

local function Bar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetMinMaxValues(0, 1)
	bar:SetStatusBarTexture(PLAIN_BAR)
	return bar
end

function Preview.Make(parent, kind, skin)
	if kind ~= "unitframe" or not parent then
		return nil
	end
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(WIDTH, HEIGHT)
	W.Panel(p, { on = true })
	p.skin = skin
	p.SetPick, p.Refresh = SetPick, Refresh

	local portrait = W.RoundIcon(p, PORTRAIT)
	portrait:EnableMouse(false)   -- (a picture: no hover light, the preview's tooltip stands)
	p.portrait = portrait
	p.crest = portrait:CreateTexture(nil, "OVERLAY", nil, 7)
	p.crest:SetSize(CREST, CREST)
	p.crest:SetPoint("CENTER", portrait, "TOP", 0, -2)
	p.name = W.Text(p, "GameFontNormal", nil, "text")
	p.name:SetWordWrap(false)
	p.bar1, p.bar2 = Bar(p), Bar(p)
	-- the raid cell's name: a region of its bar (one of the preview's own
	-- would draw under the bar's fill, a child frame's)
	p.cellName = W.Text(p.bar1, "GameFontNormal", nil, "text")
	p.cellName:SetWordWrap(false)
	p.cellName:SetPoint("TOPLEFT", p.bar1, "TOPLEFT", 4, -4)
	p.cellName:SetWidth(RAID_W - 8)
	p.text1 = p.bar1:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	p.text2 = p.bar2:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	p.icon = p:CreateTexture(nil, "ARTWORK")
	p.icon:SetSize(24, 24)
	p.icon:SetTexture(CAST_ICON)
	p.castText = p.bar1:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	p.castText:SetPoint("LEFT", p.bar1, "LEFT", 4, 0)
	p.castText:SetText(SAMPLES.castbars.spell)
	p.castTime = p.bar1:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	p.castTime:SetPoint("RIGHT", p.bar1, "RIGHT", -4, 0)
	p.castTime:SetText(SAMPLES.castbars.time)

	previews[p] = true
	if skin and skin.OnKit then
		skin:OnKit(OnShellKit)
		if skin.kit then
			skin:Kit(KitRim, p)
		end
	end
	p:EnableMouse(true)
	p:SetScript("OnShow", OnShow)
	p:SetScript("OnHide", OnHide)
	p:SetScript("OnEnter", OnEnter)
	p:SetScript("OnLeave", W.TipLeave)
	p.pick = FIRST_PICK
	Lay(p)
	if p:IsVisible() then
		OnShow(p)   -- (made on show: no OnShow comes)
	end
	return p
end

-- a new copy of the party pick's sample (0.17.0: Preview's stand-ins, below)
function Preview.PartySample()
	local s = {}
	for k, v in pairs(SAMPLES.party) do
		s[k] = v
	end
	return s
end

--------------------------------------------------------------------------------
-- A party member's replica (0.17.0: Preview's stand-ins, Core/Preview.lua; the
-- user, 2026-10-01: "the party frames are not a 1-1 replica on how they
-- actually look ingame"): the game's party member frame as its own template
-- draws it (Blizzard_UnitFrame PartyFrameTemplates.xml, PartyMemberFrameTemplate,
-- and PartyMemberFrame.lua's ToPlayerArt: 120 x 53; the portrait 37 at 7,-6
-- in its circle mask under the frame's picture at 1,-2; the name 57 x 12 at
-- 46,-6; the health bar 70 x 10 at 45,-19 in its container, its fill masked
-- by the health mask at -29,3; the mana bar 74 x 7 at 41,-30, its fill masked
-- at 14,-26 of the frame), with the same keys, so the unit frame skin dresses
-- it as it dresses a member (UnitFramePanel:DressStandIn) -- never a secure
-- template of the game's: no unit, no events, no scripts of the game's.
-- Painted from a sample as the configurator's preview is: the bars wear what
-- the settings put on the real ones (Bar Textures' preview exports), the name
-- in Unit Frames' form, the portrait Class Icons' medallion or a creature's.
--   Preview.MakeParty(parent) -> frame
--   Preview.PaintParty(frame, sample)   (a PartySample() with its own name,
--       class, health and power)
--------------------------------------------------------------------------------

local PARTY_W, PARTY_H = 120, 53
local PARTY_ART = "UI-HUD-UnitFrame-Party-PortraitOn"
local PARTY_HEALTH = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health"

local function Masked(region, parent, atlas, rel, x, y)
	local mask = parent:CreateMaskTexture()
	if Atlas(atlas) then
		mask:SetAtlas(atlas, true)
	end
	mask:SetPoint("TOPLEFT", rel, "TOPLEFT", x, y)
	if region and region.AddMaskTexture then
		region:AddMaskTexture(mask)
	end
	return mask
end

function Preview.MakeParty(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(PARTY_W, PARTY_H)
	f.Portrait = f:CreateTexture(nil, "BACKGROUND")
	f.Portrait:SetSize(37, 37)
	f.Portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -6)
	local circle = f:CreateMaskTexture()
	circle:SetAtlas("CircleMask")
	circle:SetAllPoints(f.Portrait)
	f.Portrait:AddMaskTexture(circle)
	f.PortraitMask = circle
	f.Texture = f:CreateTexture(nil, "ARTWORK")
	f.Texture:SetAtlas(PARTY_ART, true)
	f.Texture:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -2)
	f.Flash = f:CreateTexture(nil, "ARTWORK")
	f.Flash:SetAtlas("UI-HUD-UnitFrame-Party-PortraitOn-InCombat", true)
	f.Flash:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -2)
	f.Flash:Hide()
	f.Name = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	f.Name:SetSize(57, 12)
	f.Name:SetJustifyH("LEFT")
	f.Name:SetPoint("TOPLEFT", f, "TOPLEFT", 46, -6)
	local hc = CreateFrame("Frame", nil, f)
	hc:SetSize(70, 10)
	hc:SetPoint("TOPLEFT", f, "TOPLEFT", 45, -19)
	local health = Bar(hc)
	health:SetSize(70, 10)
	health:SetPoint("TOPLEFT", hc, "TOPLEFT", 0, 0)
	health:SetStatusBarTexture(PARTY_HEALTH)
	hc.HealthBar = health
	hc.HealthBarMask = Masked(health:GetStatusBarTexture(), hc, PARTY_HEALTH .. "-Mask", hc, -29, 3)
	f.HealthBarContainer = hc
	local mana = Bar(f)
	mana:SetSize(74, 7)
	mana:SetPoint("TOPLEFT", f, "TOPLEFT", 41, -30)
	mana.ManaBarMask = Masked(mana:GetStatusBarTexture(), mana, "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Mana-Mask", f, 14, -26)
	f.ManaBar = mana
	f.PartyMemberOverlay = CreateFrame("Frame", nil, f)
	f.PartyMemberOverlay:SetAllPoints(f)
	return f
end

-- the portrait: Class Icons' medallion while its player portraits are on,
-- else the game's portrait of a sample creature (as on the real frame: a
-- player's own picture; none of this client's units is read here)
local function PaintPartyPortrait(f, s)
	local tex = f.Portrait
	local ci = Running("ClassIcons")
	local medallion = ci and ci.db.portraits and s.class and MelloUI:ClassIconPath(s.class) or nil
	local want = medallion or s.display or NO_PORTRAIT
	if f.portraitShows == want then
		return
	end
	f.portraitShows = want
	tex:SetTexCoord(0, 1, 0, 1)
	if medallion then
		tex:SetTexture(medallion)
	elseif s.display and type(_G.SetPortraitTextureFromCreatureDisplayID) == "function"
		and pcall(_G.SetPortraitTextureFromCreatureDisplayID, tex, s.display) then
		return
	else
		tex:SetTexture(NO_PORTRAIT)
	end
end

function Preview.PaintParty(f, s)
	s.healthAtlas = PARTY_HEALTH
	f.sample = s
	f.Name:SetText(NameAs(s))
	PaintPartyPortrait(f, s)
	local BT = Exports("BarTextures", "PreviewHealthColor")
	if BT then
		PaintHealth(f.HealthBarContainer.HealthBar, s, BT)
		PaintPower(f.ManaBar, s, BT)
	else
		Fill(f.HealthBarContainer.HealthBar, s.health, s.max)
		Fill(f.ManaBar, s.power, s.powerMax)
	end
end
