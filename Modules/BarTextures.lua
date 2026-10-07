--------------------------------------------------------------------------------
-- MelloUI - Bar Textures
--
-- Replaces the fill texture of status bars: unit frame health and power bars,
-- nameplate health and cast bars, the personal resource display, the
-- experience / reputation / honor bars, cast bars and cooldown manager bars.
--
-- Blizzard's Dragonflight-style bars use pre-coloured atlases with a white bar
-- colour. When a flat texture is swapped in the module applies the matching
-- colour itself (power type colours, experience purple, reputation colours,
-- cast bar yellow / green / red), so bars keep their meaning.
--
-- Textures: shipped ones in Media\Textures, anything registered with
-- LibSharedMedia-3.0 by another addon, two Blizzard textures, and custom files
-- listed in Media\CustomTextures.lua.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("BarTextures")
local hooksecurefunc = Perf.hooksecurefunc
-- (0.17.0) a write back onto a game region, counted for /melloperf
local WriteBack = MelloUI.Perf.WriteBack or function() end

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Textures\\"

local SHIPPED_TEXTURES = {
	{ value = MEDIA .. "Flat",        label = "Flat" },
	{ value = MEDIA .. "Smooth",      label = "Smooth" },
	{ value = MEDIA .. "Gloss",       label = "Gloss" },
	{ value = MEDIA .. "Minimalist",  label = "Minimalist" },
	{ value = "Interface\\TargetingFrame\\UI-StatusBar", label = "Blizzard Classic" },
	{ value = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",  label = "Blizzard Raid" },
}

local function BuildTextureList()
	local list = {}
	local seen = {}
	local function Add(value, label)
		if value and not seen[value] then
			seen[value] = true
			list[#list + 1] = { value = value, label = label or value }
		end
	end
	-- the game's own bar art, kept as it is (the colour options still apply)
	Add("default", "Default (Blizzard)")
	for _, entry in ipairs(SHIPPED_TEXTURES) do
		Add(entry.value, entry.label)
	end
	if type(MelloUI_CustomTextures) == "table" then
		for _, entry in ipairs(MelloUI_CustomTextures) do
			if type(entry) == "table" and entry.file then
				Add(MEDIA .. entry.file, entry.name or entry.file)
			end
		end
	end
	local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
	if LSM then
		for _, name in ipairs(LSM:List("statusbar")) do
			Add(LSM:Fetch("statusbar", name), name)
		end
	end
	return list
end

local M = MelloUI:RegisterModule("BarTextures", {
	title = "Bar Textures",
	desc = "Change the fill texture of health, power, nameplate, experience, reputation, honor and cast bars.",
	icon = "Interface\\Icons\\Spell_Holy_Renew",
	flavour = "Health and mana bars in the finish you like: flat, smooth, glossy or minimalist.",
	role = "look",
	tweak = { label = "Bar Textures", desc = "The finish of health and mana bars (flat, smooth, glossy, minimalist) and their colours; the fill under the kit's brackets.", order = 7 },
	defaults = {
		texture = MEDIA .. "Flat",
		healthColor = "green",
		overrideThreat = true,   -- the health colour wins over the game's threat / aggro recolouring
		executeRange = false,    -- a tint over an enemy's health bar below executeBelow percent
		executeBelow = 20,
		unitframes = true,
		raidframes = true,
		nameplates = true,
		personal = true,
		statusbars = true,
		castbars = true,
		cooldowns = true,
		tooltip = true,   -- (0.16.0: the tooltip's health bar; its Use Bar Texture was the Tooltip's own)
	},
	options = {
		{ type = "header", name = "Texture" },
		{ type = "dropdown", key = "texture", name = "Bar Texture", values = BuildTextureList(),
		  desc = "Fill texture used for all bars below. Custom files go into MelloUI\\Media\\Textures and are listed in Media\\CustomTextures.lua." },
		{ type = "dropdown", key = "healthColor", name = "Health Bar Colour", values = {
			{ value = "green", label = "Green (Blizzard)" },
			{ value = "class", label = "Class colour for players" },
			{ value = "reaction", label = "Class (players) / reaction (NPCs)" },
			{ value = "health", label = "By health (green, yellow, red)" },
		  },
		  desc = "Colour of unit frame health bars. Blizzard bakes the green into its artwork, so the module has to colour flat textures itself. By health shades the bar from green at full health through yellow at half to red when low, and keeps doing so in combat." },
		{ type = "toggle", key = "overrideThreat", name = "Colour Overrides Threat",
		  desc = "The chosen health bar colour wins over the game's own recolouring of health bars (the aggro / threat display on nameplates and unit frames): whenever the game sets its colour, yours is put back. Off: the game's threat colours show." },
		{ type = "toggle", key = "executeRange", name = "Execute Range",
		  desc = "An enemy's health bar turns purple once its health is below the percentage set here, on the target, focus, target-of-target and boss frames and on nameplates, so you see when finishing moves can be used. Works in combat, when the game hides the exact health, and with every health bar colour." },
		{ type = "slider", key = "executeBelow", parent = "executeRange", name = "Execute Below", min = 5, max = 50, step = 1,
		  format = function(v) return math.floor(v + 0.5) .. "%" end,
		  desc = "The health percentage under which the bar turns purple (20% for most execute abilities, 35% for some)." },
		{ type = "header", name = "Apply To" },
		{ type = "toggle", key = "unitframes", name = "Unit Frames",
		  desc = "Health and power bars of the player, target, focus, pet, party, boss and target-of-target frames." },
		{ type = "toggle", key = "raidframes", name = "Raid Frames",
		  desc = "Raid-style party frames, raid groups and their pet frames." },
		{ type = "toggle", key = "nameplates", name = "Nameplates",
		  desc = "Nameplate health and cast bars." },
		{ type = "toggle", key = "personal", name = "Personal Resource Display",
		  desc = "The health and power bars under your character." },
		{ type = "toggle", key = "statusbars", name = "Experience & Reputation Bars",
		  desc = "Experience, reputation and honor bars, and, in the painted look, the damage meter's race bar (Minimalist there while this is off or the texture is Default)." },
		{ type = "toggle", key = "castbars", name = "Cast Bars",
		  desc = "Player, pet, target, focus and boss cast bars, and, in the painted look, MelloUI's swing timers (Minimalist there while this is off or the texture is Default)." },
		{ type = "toggle", key = "cooldowns", name = "Cooldown Manager Bars",
		  desc = "The bars of the Buff Bar cooldown viewer." },
		{ type = "toggle", key = "tooltip", name = "Tooltip Health Bar",
		  desc = "The health bar under a unit's tooltip (when Tooltip's Hide Health Bar is off)." },
	},
})

--------------------------------------------------------------------------------
-- Colours for bars whose Blizzard atlas carried the colour
--------------------------------------------------------------------------------

local FACTION_FALLBACK = {
	[1] = { r = 0.8, g = 0.3, b = 0.22 },
	[2] = { r = 0.8, g = 0.3, b = 0.22 },
	[3] = { r = 0.75, g = 0.27, b = 0 },
	[4] = { r = 0.9, g = 0.7, b = 0 },
	[5] = { r = 0, g = 0.6, b = 0.1 },
}

local function FactionColor(index)
	local colors = FACTION_BAR_COLORS or FACTION_FALLBACK
	local c = colors[index] or FACTION_FALLBACK[index]
	return c.r, c.g, c.b
end

-- Secret values (e.g. the atlas name of a nameplate cast bar) may not be
-- read by addon code; treat them as if no name was given.
local function IsPlainString(v)
	if type(v) ~= "string" then
		return false
	end
	if issecretvalue and issecretvalue(v) then
		return false
	end
	return true
end

local function IsPlainNumber(v)
	return type(v) == "number" and not (issecretvalue and issecretvalue(v))
end

-- Maps the atlas name Blizzard hands to SetStatusBarTexture to an RGB colour.
local function StatusTrackingColorForAtlas(atlas)
	if not IsPlainString(atlas) then
		return nil
	end
	local a = atlas:lower()
	-- the faction / reputation names first: the reputation bar's atlases are
	-- named "...experiencebar-fill-faction-..." on this client and read as
	-- experience purple otherwise (user, 2026-09-21: both bars purple)
	if a:find("faction%-red") then return FactionColor(2) end
	if a:find("faction%-orange") then return FactionColor(3) end
	if a:find("faction%-yellow") then return FactionColor(4) end
	if a:find("faction%-green") then return FactionColor(5) end
	if a:find("faction%-blue") then return 0.2, 0.5, 1.0 end
	if a:find("reputation") then return FactionColor(5) end
	if a:find("rested") then return 0.0, 0.39, 0.88 end
	if a:find("honor") then return 1.0, 0.24, 0.0 end
	if a:find("experience") then return 0.58, 0.0, 0.55 end
	return nil
end

--------------------------------------------------------------------------------
-- Core apply / hook machinery
--------------------------------------------------------------------------------

local tracked = setmetatable({}, { __mode = "k" })   -- [bar] = group
local originals = setmetatable({}, { __mode = "k" }) -- [bar] = original atlas or file
local hookedBars = setmetatable({}, { __mode = "k" })
local hookedTextures = setmetatable({}, { __mode = "k" }) -- [texture] = bar
local masks = setmetatable({}, { __mode = "k" })     -- [bar] = MaskTexture shaped like the original atlas
local maskedTextures = setmetatable({}, { __mode = "k" }) -- [texture] = mask currently attached
local applied = setmetatable({}, { __mode = "k" })   -- [bar] = true once our texture is on it
local applying = false
local healthBars                                     -- [bar] = true for every health bar seen (filled below)

local function Active(group)
	return M.isEnabled and M.db and M.db[group]
end

-- What the game put on a bar, kept so disabling can restore it. The game
-- re-sets the same art over and over on some bars (the target of target's
-- power bar, 41 times a second in /melloperf 2026-09-24): noted only when it
-- is new, and whether a name is an atlas asked once per name (the answer is
-- a new table every time), so a repeat makes no garbage. A repeat still
-- drops the colour RememberOriginal kept, as a new note always did.
local atlasNames = {}   -- [name] = true (an atlas) / false (a file)

local function NoteOriginal(bar, art)
	local o = originals[bar]
	if o and o.r == nil and (o.atlas == art or o.file == art) then
		return
	end
	local isAtlas = atlasNames[art]
	if isAtlas == nil then
		isAtlas = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(art)) and true or false
		atlasNames[art] = isAtlas
	end
	originals[bar] = isAtlas and { atlas = art } or { file = art }
end

local function RememberOriginal(bar)
	if originals[bar] ~= nil then
		return
	end
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	local value = false
	if tex then
		local atlas = tex.GetAtlas and tex:GetAtlas()
		if IsPlainString(atlas) and atlas ~= "" then
			value = { atlas = atlas }
		else
			local file = tex.GetTexture and tex:GetTexture()
			if IsPlainString(file) then
				value = { file = file }
			end
		end
	end
	if value then
		-- the colour as well: a restore that puts the atlas back under the
		-- module's tint showed it twice coloured (audit, 2026-09-22)
		local r, g, b, a = bar:GetStatusBarColor()
		if IsPlainNumber(r) and IsPlainNumber(g) and IsPlainNumber(b) then
			value.r, value.g, value.b, value.a = r, g, b, IsPlainNumber(a) and a or 1
		end
	end
	originals[bar] = value
end

-- Blizzard draws the bar fills ABOVE the frame border art (the bars live in
-- child frames with a higher frame level) and relies on the shaped bar atlas
-- to stay inside the frame opening. A flat texture fills the whole rectangle
-- and covers the border, so mask the fill with the original atlas: Blizzard's
-- shape, our texture.
local function RemoveMask(bar)
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	local mask = tex and maskedTextures[tex]
	if tex and mask then
		if tex.RemoveMaskTexture then
			tex:RemoveMaskTexture(mask)
		end
		maskedTextures[tex] = nil
	end
end

-- a bar the kit brackets (MelloUI.Kept.bracketOf, set by the bar panels while their
-- bracket shows; none in a world without the kit)
local function KitBracket(bar)
	local bracketed = MelloUI.Kit and MelloUI.Kit.bracketOf
	return bracketed and bracketed[bar]
end

local function UpdateMask(bar)
	local original = originals[bar]
	local atlas = original and original.atlas
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not tex or not tex.AddMaskTexture or not bar.CreateMaskTexture then
		return
	end
	-- a bar the kit brackets (UnitFramePanel) shows its fill on the whole
	-- rect, the bracket's rails covering the edges: no shaped mask
	if not IsPlainString(atlas) or KitBracket(bar) then
		RemoveMask(bar)
		return
	end
	local mask = masks[bar]
	if not mask then
		mask = bar:CreateMaskTexture()
		mask:SetAllPoints(bar)
		masks[bar] = mask
	end
	if mask.GetAtlas and mask:GetAtlas() ~= atlas then
		mask:SetAtlas(atlas)
	elseif not mask.GetAtlas then
		mask:SetAtlas(atlas)
	end
	if maskedTextures[tex] ~= mask then
		if maskedTextures[tex] and tex.RemoveMaskTexture then
			tex:RemoveMaskTexture(maskedTextures[tex])
		end
		tex:AddMaskTexture(mask)
		maskedTextures[tex] = mask
	end
end

local RestoreBar   -- below

-- The bar shows just what a restore would put back: the game's atlas, noted
-- as it is on the bar, no colour kept to put back, none of our masks on it
local function ShowsOriginal(bar)
	local o = originals[bar]
	if not (o and o.atlas) or o.r ~= nil then
		return false
	end
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not tex or maskedTextures[tex] or not tex.GetAtlas then
		return false
	end
	local ok, atlas = pcall(tex.GetAtlas, tex)
	return ok and IsPlainString(atlas) and atlas == o.atlas
end

-- (0.17.0) Default (Blizzard) under a health colour: the game's health art
-- is green, and a class colour multiplied into it came out grey-green (user,
-- 2026-10-01). The game has each of these pictures in white as well,
-- "<name>-Status": the fill it tints for heal prediction, absorbs and mana
-- cost (StatusBarOverlaySegment, by vertex colour). A coloured unit-frame
-- health bar wears that twin, which takes the colour as it is; a bar whose
-- art has none (the minus mob's, the small boss frame's, a party vehicle's)
-- is desaturated instead, the colour then a shade darker. Green keeps the
-- game's own art untouched.
local twinNames = {}                                     -- [atlas] = its white twin, or false
local desaturated = setmetatable({}, { __mode = "k" })   -- [bar] = true while this module greyed its art

local function TwinOf(atlas)
	local twin = twinNames[atlas]
	if twin == nil then
		local name = atlas .. "-Status"
		twin = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) and name or false
		twinNames[atlas] = twin
	end
	return twin
end

-- the game's green art this bar would show coloured: its atlas, when the bar
-- is a unit-frame health bar and the colour is not the game's green
local function ColouredArt(bar)
	if not (healthBars[bar] and tracked[bar] == "unitframes" and M.db.healthColor ~= "green") then
		return nil
	end
	local o = originals[bar]
	return o and IsPlainString(o.atlas) and o.atlas or nil
end

local function SetDesaturated(bar, on)
	if on and not desaturated[bar] then
		desaturated[bar] = true
		bar:SetStatusBarDesaturated(true)
	elseif not on and desaturated[bar] then
		desaturated[bar] = nil
		bar:SetStatusBarDesaturated(false)
	end
end

-- Default's art on a coloured health bar: the white twin (put on only when
-- it is not on already: the game re-sets its art often), or the game's own
-- desaturated. False: not a coloured health bar, Default's usual restore.
local function ColouredDefault(bar)
	local atlas = ColouredArt(bar)
	if not atlas then
		return false
	end
	local twin = TwinOf(atlas)
	if twin then
		local tex = bar:GetStatusBarTexture()
		local ok, now = pcall(tex.GetAtlas, tex)
		if not (ok and IsPlainString(now) and now == twin) then
			applying = true
			RemoveMask(bar)
			bar:SetStatusBarTexture(twin)
			applying = false
		end
		SetDesaturated(bar, false)
	else
		local tex = bar:GetStatusBarTexture()
		local ok, now = pcall(tex.GetAtlas, tex)
		if not (ok and IsPlainString(now) and now == atlas) then
			RestoreBar(bar)
		end
		SetDesaturated(bar, true)
	end
	return true
end

local tintSynced   -- (the execute tint's: below)

local function SetTexture(bar)
	if tintSynced then
		tintSynced[bar] = nil
	end
	local r, g, b, a = bar:GetStatusBarColor()
	-- "Default (Blizzard)": the game's own art stays (put back if a texture
	-- was on the bar), the bar keeps its colour handling below (user,
	-- 2026-09-21: the default textures as a choice)
	if M.db.texture == "default" then
		-- the game's own re-sets land here too (dozens a second on some power
		-- bars) with its art already on: a restore that would change nothing
		-- is left out. A health bar is restored every time, as it always was
		-- (the restore also has the game colour it again)
		if not ColouredDefault(bar) and applied[bar] and (healthBars[bar] or not ShowsOriginal(bar)) then
			RestoreBar(bar)
		end
		applied[bar] = true
		return
	end
	SetDesaturated(bar, false)
	applying = true
	bar:SetStatusBarTexture(M.db.texture)
	UpdateMask(bar)
	applying = false
	applied[bar] = true
	if not (issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b) or issecretvalue(a))) then
		bar:SetStatusBarColor(r, g, b, a)
	end
end

local StatusTrackingColorForAtlasRef -- forward declared below the helper section

-- Some Blizzard code (target classification, boss frames, nameplate styles)
-- changes the bar art directly on the texture object instead of through
-- SetStatusBarTexture. Hook the texture so those changes are undone too.
local function HookBarTexture(bar)
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not tex or hookedTextures[tex] then
		return
	end
	hookedTextures[tex] = bar
	local function OnDirectChange(self, newTexture)
		if applying then
			return
		end
		local owner = hookedTextures[self]
		local grp = owner and tracked[owner]
		if not grp or not Active(grp) then
			return
		end
		if IsPlainString(newTexture) then
			NoteOriginal(owner, newTexture)
		end
		if M.db.texture ~= "default" then
			WriteBack("BarTextures: a bar fill's art put back after the game's")
		end
		SetTexture(owner)
		if grp == "statusbars" and StatusTrackingColorForAtlasRef then
			local r, g, b = StatusTrackingColorForAtlasRef(newTexture)
			if r then
				owner:SetStatusBarColor(r, g, b)
			end
		end
	end
	if type(tex.SetAtlas) == "function" then
		hooksecurefunc(tex, "SetAtlas", OnDirectChange)
	end
	if type(tex.SetTexture) == "function" then
		hooksecurefunc(tex, "SetTexture", OnDirectChange)
	end
end

-- The covered bars (0.17.0; the user's FPS in combat,
-- docs/plans/fps-portrait-fix.md). The target of target's power bar is
-- given its art on EVERY frame (its OnUpdate runs UnitFrame_Update ->
-- UnitFrameManaBar_UpdateType: SetStatusBarTexture(atlas), the colour
-- white, the fill's alpha): putting this module's texture straight back
-- made each of those a real change again, two texture swaps a frame (49 a
-- second in /melloperf). Such a bar is never written: a COVER of ours lies
-- on it, regions of the bar itself between the game's fill and the kit's
-- bracket (the fill's layer, a sublevel over it) --
--   back   an opaque palette ground, so nothing of the game's fill shows
--          through a texture with see-through parts,
--   tex    the chosen texture in the power's colour,
-- both on the bar's whole rect, cut to the game's fill by a mask on the
-- fill's own rect (the engine moves it with the value, a secret one too:
-- the texture is cropped as a fill is, never stretched), to the bar's
-- shape by the shape mask (the game's atlas), and by the fill's own masks.
-- The game's own writes then land on its own unchanged art and cost
-- nothing; ours are made only when the texture, the power or the shape
-- changes. Default (Blizzard), or the group off: the cover hidden.
local WHITE = "Interface\\Buttons\\WHITE8x8"
local covered = setmetatable({}, { __mode = "k" })   -- [bar] = true: drawn by a cover
local coverOf = setmetatable({}, { __mode = "k" })   -- [bar] = { back, tex, crop, file, token, shape, shown }

local function CoverMasks(c, mask)
	if mask and not c.masks[mask] then
		c.masks[mask] = true
		pcall(c.tex.AddMaskTexture, c.tex, mask)
		pcall(c.back.AddMaskTexture, c.back, mask)
	end
end

local function NewCover(bar)
	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not (fill and bar.CreateMaskTexture) then
		return nil
	end
	local okL, layer, sub = pcall(fill.GetDrawLayer, fill)
	if not okL or type(layer) ~= "string" then
		layer, sub = "BACKGROUND", 0
	end
	sub = math.min(7, (tonumber(sub) or 0) + 1)
	local back = bar:CreateTexture(nil, layer, nil, sub)
	back:SetPoint("TOPLEFT", bar, "TOPLEFT")
	back:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
	MelloUI.Widgets.Paint(back, "mainWindow", "vertex")
	back:SetTexture(WHITE)
	local tex = bar:CreateTexture(nil, layer, nil, sub)
	tex:SetPoint("TOPLEFT", bar, "TOPLEFT")
	tex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
	local crop = bar:CreateMaskTexture()
	crop:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	crop:SetPoint("TOPLEFT", fill, "TOPLEFT")
	crop:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	local c = { back = back, tex = tex, crop = crop, masks = {}, shown = true }
	CoverMasks(c, crop)
	-- the fill's own masks (the game's bar shape where it has one)
	local okN, n = pcall(fill.GetNumMaskTextures, fill)
	for i = 1, (okN and type(n) == "number" and n) or 0 do
		CoverMasks(c, fill:GetMaskTexture(i))
	end
	coverOf[bar] = c
	return c
end

local function CoverShown(c, on)
	if c and c.shown ~= on then
		c.shown = on
		c.back:SetShown(on)
		c.tex:SetShown(on)
	end
end

-- the cover as the settings and the bar's power say, written only where
-- something changed (the game calls this path every frame)
local function CoverBar(bar)
	local c = coverOf[bar]
	local group = tracked[bar]
	if not (group and Active(group)) or M.db.texture == "default" then
		CoverShown(c, false)
		return
	end
	c = c or NewCover(bar)
	if not c then
		return
	end
	-- the bar's shape: the game's own atlas as a mask (none under a kit
	-- bracket, whose rails cover the edges)
	local o = originals[bar]
	local shape = not KitBracket(bar) and o and IsPlainString(o.atlas) and o.atlas or nil
	if c.shape ~= shape then
		c.shape = shape
		local mask = masks[bar]
		if shape then
			if not mask then
				mask = bar:CreateMaskTexture()
				mask:SetAllPoints(bar)
				masks[bar] = mask
			end
			mask:SetAtlas(shape)
			CoverMasks(c, mask)
		elseif mask and c.masks[mask] then
			c.masks[mask] = nil
			pcall(c.tex.RemoveMaskTexture, c.tex, mask)
			pcall(c.back.RemoveMaskTexture, c.back, mask)
		end
	end
	local file = M.db.texture
	if c.file ~= file then
		c.file = file
		c.tex:SetTexture(file)
	end
	local info = bar.overrideInfo or (PowerBarColor and bar.powerToken and PowerBarColor[bar.powerToken])
	if c.token ~= info then
		c.token = info
		if info and IsPlainNumber(info.r) and IsPlainNumber(info.g) and IsPlainNumber(info.b) then
			c.tex:SetVertexColor(info.r, info.g, info.b)
		else
			c.tex:SetVertexColor(1, 1, 1)
		end
	end
	CoverShown(c, true)
end

-- (the tests')
function M.CoverOf(bar)
	return coverOf[bar]
end

local function ApplyToBar(bar, group)
	if not bar or type(bar.SetStatusBarTexture) ~= "function" then
		return
	end
	-- a covered bar: never written (its cover above)
	if covered[bar] then
		RememberOriginal(bar)
		tracked[bar] = group
		CoverBar(bar)
		return
	end
	-- Nameplate and cooldown layouts call back in here on every relayout.
	-- Once our texture is on the bar, its hooks keep it there; nothing to do.
	if applied[bar] and tracked[bar] == group then
		local tex = bar:GetStatusBarTexture()
		if tex and hookedTextures[tex] == bar then
			return
		end
	end
	RememberOriginal(bar)
	tracked[bar] = group
	SetTexture(bar)
	HookBarTexture(bar)

	if not hookedBars[bar] then
		hookedBars[bar] = true
		-- Blizzard swaps atlases on power type changes, nameplate style changes,
		-- cast bar states and experience bar states; put ours back afterwards.
		hooksecurefunc(bar, "SetStatusBarTexture", function(self, newTexture)
			if applying then
				return
			end
			local grp = tracked[self]
			if not grp or not Active(grp) then
				return
			end
			-- Keep track of what Blizzard wanted so disabling can restore it.
			if IsPlainString(newTexture) then
				NoteOriginal(self, newTexture)
			end
			if M.db.texture ~= "default" then
				WriteBack("BarTextures: a bar's texture put back after the game's")
			end
			SetTexture(self)
			if grp == "statusbars" then
				local r, g, b = StatusTrackingColorForAtlas(newTexture)
				if r then
					self:SetStatusBarColor(r, g, b)
				end
			end
		end)
	end
end

StatusTrackingColorForAtlasRef = StatusTrackingColorForAtlas

function RestoreBar(bar)
	if covered[bar] then
		CoverShown(coverOf[bar], false)
		return
	end
	local original = originals[bar]
	if not original then
		return
	end
	applying = true
	RemoveMask(bar)
	if original.atlas then
		bar:SetStatusBarTexture(original.atlas)
	elseif original.file then
		bar:SetStatusBarTexture(original.file)
	end
	applying = false
	applied[bar] = nil
	if tintSynced then
		tintSynced[bar] = nil
	end
	SetDesaturated(bar, false)
	if original.r then
		bar:SetStatusBarColor(original.r, original.g, original.b, original.a)
	end
end

local function RestoreGroup(group)
	for bar, grp in pairs(tracked) do
		if grp == group then
			RestoreBar(bar)
			tracked[bar] = nil
		end
	end
end

local function ReapplyGroup(group)
	for bar, grp in pairs(tracked) do
		if grp == group then
			if covered[bar] then
				CoverBar(bar)
			else
				SetTexture(bar)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Unit frames
--------------------------------------------------------------------------------

local function TargetLikeFrames()
	local frames = { TargetFrame, FocusFrame }
	for i = 1, 5 do
		frames[#frames + 1] = _G["Boss" .. i .. "TargetFrame"]
	end
	return frames
end

healthBars = setmetatable({}, { __mode = "k" })

local HookHealthColor   -- below, with the colour code

local function AddHealth(list, bar)
	if bar then
		healthBars[bar] = true
		list[#list + 1] = bar
		HookHealthColor(bar)
	end
end

local function AddPower(list, bar)
	if bar then
		list[#list + 1] = bar
	end
end

local function CollectUnitFrameBars(list)
	if PlayerFrame and PlayerFrame.PlayerFrameContent then
		local main = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
		if main then
			if main.HealthBarsContainer then
				AddHealth(list, main.HealthBarsContainer.HealthBar)
				AddPower(list, main.HealthBarsContainer.PlayerFrameHealthBarAnimatedLoss)
			end
			if main.ManaBarArea then
				AddPower(list, main.ManaBarArea.ManaBar)
			end
		end
	end
	for _, frame in ipairs(TargetLikeFrames()) do
		if frame and frame.TargetFrameContent then
			local main = frame.TargetFrameContent.TargetFrameContentMain
			if main then
				if main.HealthBarsContainer then
					AddHealth(list, main.HealthBarsContainer.HealthBar)
				end
				AddPower(list, main.ManaBar)
			end
			if frame.totFrame then
				AddHealth(list, frame.totFrame.HealthBar)
				AddPower(list, frame.totFrame.ManaBar)
				-- (its art re-set on every frame: covered, never written)
				if frame.totFrame.ManaBar then
					covered[frame.totFrame.ManaBar] = true
				end
			end
		end
	end
	AddHealth(list, PetFrameHealthBar)
	AddPower(list, PetFrameManaBar)
	if PartyFrame then
		for i = 1, 4 do
			local member = PartyFrame["MemberFrame" .. i]
			if member then
				if member.HealthBarContainer then
					AddHealth(list, member.HealthBarContainer.HealthBar)
				end
				AddPower(list, member.ManaBar)
				if member.PetFrame then
					AddHealth(list, member.PetFrame.HealthBar)
				end
			end
		end
	end
end

-- Several Forever health bars lock their colour and rely on a green atlas, so a
-- flat texture has to be coloured here.
-- (the field read through a named function, not a closure made per read:
-- this runs on every value change of a health bar)
local function UnitField(frame)
	return frame.unit
end

local function UnitOf(bar)
	local frame = bar
	for _ = 1, 3 do
		if not frame then
			return nil
		end
		local ok, unit = pcall(UnitField, frame)
		if ok and type(unit) == "string" then
			return unit
		end
		frame = frame.GetParent and frame:GetParent() or nil
	end
	return nil
end

-- By health (user, 2026-09-23: "Health colours that keep working in
-- combat"): green at full, yellow at half, red when low. The game works the
-- colour out itself from this curve and the unit's health percentage
-- (UnitHealthPercent with a colour curve), so it works while the exact health
-- is secret in combat -- the colour comes back secret too and goes straight
-- into the bar, which accepts it; nothing here reads or compares it
-- (/mello secrets on this client, 2026-09-23).
-- its three stops, { at, r, g, b } (the Configurator's preview works them
-- out too, M.PreviewHealthColor below, where a client has no curve)
local HEALTH_STOPS = {
	{ 0, 0.85, 0.1, 0.08 },
	{ 0.5, 0.95, 0.78, 0.1 },
	{ 1, 0.1, 0.8, 0.1 },
}
local healthCurve   -- nil: not built yet; false: this client cannot
local function HealthCurve()
	if healthCurve == nil then
		healthCurve = false
		if C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
			local ok, curve = pcall(function()
				local c = C_CurveUtil.CreateColorCurve()
				if Enum and Enum.LuaCurveType then
					c:SetType(Enum.LuaCurveType.Linear)
				end
				for _, stop in ipairs(HEALTH_STOPS) do
					c:AddPoint(stop[1], CreateColor(stop[2], stop[3], stop[4], 1))
				end
				return c
			end)
			if ok and curve then
				healthCurve = curve
			end
		end
	end
	return healthCurve or nil
end

-- A player's class colour, or (mode "reaction") an NPC's reaction colour;
-- nothing when there is none. Called through pcall.
local function ClassOrReactionColor(unit, mode)
	if UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		if issecretvalue and issecretvalue(class) then
			-- a secret class cannot key the colour table; the
			-- game's own lookup takes it and answers in kind
			local color = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
			if color then
				return color:GetRGB()
			end
			return nil
		end
		local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if color then
			return color.r, color.g, color.b
		end
	elseif mode == "reaction" then
		-- Hostile red, unfriendly orange, neutral yellow, friendly green.
		local reaction = UnitReaction(unit, "player")
		local color = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
		if color then
			return color.r, color.g, color.b
		end
	end
end

local function HealthColorFor(bar)
	local unit = UnitOf(bar)
	if unit then
		-- Blizzard greys only disconnected units (it stores the flag on the bar
		-- before this runs); dead or ghost units keep their colour.
		if bar.disconnected then
			return 0.5, 0.5, 0.5
		end
		-- a mob someone else tapped (no loot for you): the game's grey, as
		-- its own nameplates (0.9) and target frame (0.5) have it (0.17.0;
		-- the user: it kept its reaction colour). A secret answer: not tapped
		local okT, denied = pcall(UnitIsTapDenied, unit)
		local okP, controlled = pcall(UnitPlayerControlled, unit)
		if okT and okP and not (issecretvalue and (issecretvalue(denied) or issecretvalue(controlled)))
			and denied == true and controlled == false then
			if tracked[bar] == "nameplates" then
				return 0.9, 0.9, 0.9
			end
			return 0.5, 0.5, 0.5
		end
		local mode = M.db.healthColor
		if mode == "health" then
			local curve = HealthCurve()
			if curve and UnitHealthPercent then
				local ok, color = pcall(UnitHealthPercent, unit, true, curve)
				if ok and color and color.GetRGB then
					return color:GetRGB()
				end
			end
			return 0.0, 1.0, 0.0
		end
		if mode == "class" or mode == "reaction" then
			local ok2, r, g, b = pcall(ClassOrReactionColor, unit, mode)
			if ok2 and IsPlainNumber(r) and IsPlainNumber(g) and IsPlainNumber(b) then
				return r, g, b
			end
			-- a class colour from a secret class comes back secret: shown as it is
			if ok2 and issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b)) then
				return r, g, b
			end
		end
	end
	-- Green under Default (Blizzard): the game's own green art on a bar the
	-- game keeps white (lockColor: the player, target, focus, pet, party and
	-- boss frames' health) stays white, as the game leaves it; 0, 1, 0 on it
	-- tinted the art (0.19.4, the options audit). Any other bar: the green a
	-- flat texture needs written.
	if bar.lockColor and M.db.texture == "default" and M.db.healthColor == "green" then
		return 1, 1, 1
	end
	return 0.0, 1.0, 0.0
end

-- the unit a plain player: false for an NPC, no unit, or an answer that
-- cannot be read plainly
local function PlainPlayer(unit)
	if not unit then
		return false
	end
	local ok, isPlayer = pcall(UnitIsPlayer, unit)
	return ok and not (issecretvalue and issecretvalue(isPlayer)) and isPlayer == true
end

local recolouring = false
-- [bar] = { r, g, b } last written (plain only): the game's update path runs
-- every frame on the target of target, and the same colour again changes
-- nothing (0.17.0, docs/plans/fps-portrait-fix.md: write only on a change)
local lastColour = setmetatable({}, { __mode = "k" })

local function SetHealthColour(bar, r, g, b)
	if IsPlainNumber(r) and IsPlainNumber(g) and IsPlainNumber(b) then
		local last = lastColour[bar]
		if last and last[1] == r and last[2] == g and last[3] == b then
			local ok, cr, cg, cb = pcall(bar.GetStatusBarColor, bar)
			-- (still on the bar: the game did not recolour it since)
			if ok and IsPlainNumber(cr) and IsPlainNumber(cg) and IsPlainNumber(cb) and cr == r and cg == g and cb == b then
				return
			end
		end
		last = last or {}
		last[1], last[2], last[3] = r, g, b
		lastColour[bar] = last
	else
		lastColour[bar] = nil   -- (a secret colour: written as it is)
	end
	WriteBack("BarTextures: a health bar's colour")
	bar:SetStatusBarColor(r, g, b)
end

local function RecolorHealthBar(bar)
	if not bar or not healthBars[bar] then
		return
	end
	local group = tracked[bar]
	if not (group == "unitframes" or group == "nameplates") or not Active(group) then
		return
	end
	-- the game's own nameplate colouring stands: under Green, and under Class
	-- colour on an NPC's plate (its reaction red, yellow or green; 0.19.4,
	-- the options audit: Class colour turned every NPC plate green). The unit
	-- frames' NPC bars take the green, as under Green.
	if group == "nameplates" then
		local mode = M.db.healthColor
		if mode == "green" or (mode == "class" and not PlainPlayer(UnitOf(bar))) then
			return
		end
	end
	recolouring = true
	SetHealthColour(bar, HealthColorFor(bar))
	recolouring = false
end

-- Execute range (user, 2026-09-23, from the addon study: colours from
-- curves that keep working in combat). A purple tint laid over the bar's
-- fill, shown by the game itself: UnitHealthPercent evaluates a curve whose
-- alpha is 1 below the threshold and 0 above it, and that alpha -- secret in
-- combat -- goes straight into the tint's SetAlpha, which takes it. Nothing
-- here reads or compares the health. The bar's own colour is never touched,
-- so it works over every colour choice, the game's nameplate colours too.
local EXECUTE_COLOR = { 0.72, 0.25, 1.0 }
local executeTints = setmetatable({}, { __mode = "k" })   -- [bar] = the tint over its fill
-- (tintSynced) [bar] = false once the tint's look matches the fill (layer, art, masks);
-- anything else: matched again at the next update. Set back by a change of
-- the fill's art (SetTexture, RestoreBar, the game's own SetStatusBarTexture)
-- and by a setting (0.17.0: no longer read and written on every value change)
tintSynced = setmetatable({}, { __mode = "k" })
local wantMasks = setmetatable({}, { __mode = "k" })      -- UpdateExecute's scratch: the fill's masks
local executeCurve, executeCurveAt = nil, nil

local function ExecuteCurve()
	local at = math.max(1, math.min(99, tonumber(M.db.executeBelow) or 20)) / 100
	if executeCurveAt ~= at then
		executeCurveAt = at
		executeCurve = false
		if C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
			local ok, curve = pcall(function()
				local c = C_CurveUtil.CreateColorCurve()
				if Enum and Enum.LuaCurveType then
					c:SetType(Enum.LuaCurveType.Linear)
				end
				-- a step made of two points a hair apart: on below, off from `at`;
				-- and off at none left (user, 2026-10-03: a dead unit's bar all
				-- purple -- its fill gone, the crop on it had nothing to cut by,
				-- so the tint lay on the whole bar)
				c:AddPoint(0, CreateColor(1, 1, 1, 0))
				c:AddPoint(0.0001, CreateColor(1, 1, 1, 1))
				c:AddPoint(at - 0.0005, CreateColor(1, 1, 1, 1))
				c:AddPoint(at, CreateColor(1, 1, 1, 0))
				c:AddPoint(1, CreateColor(1, 1, 1, 0))
				return c
			end)
			if ok and curve then
				executeCurve = curve
			end
		end
	end
	return executeCurve or nil
end

local function ExecuteTint(bar)
	local tint = executeTints[bar]
	if tint then
		return tint
	end
	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not fill then
		return nil
	end
	local okL, layer, sub = pcall(fill.GetDrawLayer, fill)
	if not okL or type(layer) ~= "string" then
		layer, sub = "ARTWORK", 0
	end
	tint = bar:CreateTexture(nil, layer, nil, math.min(7, (tonumber(sub) or 0) + 1))
	-- the bar's whole rect, cut to the fill by a mask on the fill's own rect:
	-- a file texture then shows as the fill shows it (cropped, not
	-- squeezed) with no texture coordinates written per value
	tint:SetAllPoints(bar)
	if bar.CreateMaskTexture and tint.AddMaskTexture then
		local crop = bar:CreateMaskTexture()
		crop:SetTexture("Interface\\Buttons\\WHITE8x8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		crop:SetPoint("TOPLEFT", fill, "TOPLEFT")
		crop:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
		tint:AddMaskTexture(crop)
		tint.melloCrop = crop
	end
	tint:SetColorTexture(EXECUTE_COLOR[1], EXECUTE_COLOR[2], EXECUTE_COLOR[3], 0.85)
	tint:SetAlpha(0)
	executeTints[bar] = tint
	return tint
end

local SyncTint   -- (below)

-- the picture on a bar's fill: its atlas, else its file (nil: none read)
local function FillArt(bar)
	local fill = bar:GetStatusBarTexture()
	if not fill then
		return nil
	end
	local okA, atlas = pcall(fill.GetAtlas, fill)
	if okA and type(atlas) == "string" and atlas ~= "" then
		return atlas
	end
	local okF, file = pcall(fill.GetTexture, fill)
	if okF and (type(file) == "string" or type(file) == "number") then
		return file
	end
	return nil
end

local function UpdateExecute(bar)
	local tint = executeTints[bar]
	local group = tracked[bar]
	local on = M.isEnabled and M.db.executeRange and (group == "unitframes" or group == "nameplates") and Active(group)
	local unit = on and UnitOf(bar) or nil
	if on and unit and unit ~= "player" then
		local okA, attackable = pcall(UnitCanAttack, "player", unit)
		on = okA and not (issecretvalue and issecretvalue(attackable)) and attackable and true or false
	else
		on = false
	end
	local curve = on and ExecuteCurve()
	local color
	if curve and UnitHealthPercent then
		local ok, c = pcall(UnitHealthPercent, unit, true, curve)
		color = ok and c or nil
	end
	if not color then
		if tint then
			tint:Hide()
		end
		return
	end
	tint = tint or ExecuteTint(bar)
	if not tint then
		return
	end
	-- (its look matched again when the fill changed: a change this module
	-- made, or the fill's picture another than the tint took -- two reads)
	if tintSynced[bar] ~= false or tint.melloArt ~= FillArt(bar) then
		tintSynced[bar] = false
		SyncTint(bar, tint)
	end
	local alpha = color.a
	if alpha == nil and color.GetRGBA then
		alpha = select(4, color:GetRGBA())
	end
	if pcall(tint.SetAlpha, tint, alpha) then
		tint:Show()
	else
		tint:Hide()
	end
end

-- the tint's look matched to the fill: its layer, its picture and its masks
-- (only when the fill changed: tintSynced)
SyncTint = function(bar, tint)
	-- the fill's masks on the tint too (user, 2026-09-23: it spilled under
	-- the border): Bar Textures' shaped mask and the kit's come and go with
	-- the settings, so they are matched again when the fill changes
	local fill = bar:GetStatusBarTexture()
	-- one sublevel above the fill, wherever the fill is now: the kit moves a
	-- bar's fill to another layer after the tint was made (the target frame,
	-- /btdump exec 2026-09-23: the tint on BACKGROUND 1 under an ARTWORK fill)
	if fill then
		local okL, layer, sub = pcall(fill.GetDrawLayer, fill)
		if okL and type(layer) == "string" then
			local want = math.min(7, (tonumber(sub) or 0) + 1)
			local _, tl, ts = pcall(tint.GetDrawLayer, tint)
			if tl ~= layer or ts ~= want then
				tint:SetDrawLayer(layer, want)
			end
		end
	end
	-- the fill's own picture and cut, coloured purple (user, 2026-09-23: a
	-- flat colour still spilled under the border where the fill's texture
	-- fades out; the status bar re-cuts its texture as the value changes)
	if fill then
		local okA, atlas = pcall(fill.GetAtlas, fill)
		local okF, file = pcall(fill.GetTexture, fill)
		atlas = okA and type(atlas) == "string" and atlas ~= "" and atlas or nil
		file = okF and (type(file) == "string" or type(file) == "number") and file or nil
		local art = atlas or file
		if art and tint.melloArt ~= art then
			tint.melloArt = art
			if atlas then
				-- the game's own atlas (Bar Texture: Default) carries its colour
				-- -- the target frame's is green art -- and purple over it came
				-- out near black (user, 2026-10-01): a flat purple instead,
				-- cut to the bar's shape by the fill's masks (the game's
				-- HealthBarMask, copied below)
				tint:SetColorTexture(EXECUTE_COLOR[1], EXECUTE_COLOR[2], EXECUTE_COLOR[3], 0.85)
				tint:SetVertexColor(1, 1, 1, 1)
			else
				tint:SetTexture(file)
				tint:SetVertexColor(EXECUTE_COLOR[1], EXECUTE_COLOR[2], EXECUTE_COLOR[3], 0.85)
			end
		end
	end
	if fill and fill.GetNumMaskTextures and tint.AddMaskTexture then
		-- one scratch set, emptied each time (this runs on every value change)
		local want = wantMasks
		for mask in pairs(want) do
			want[mask] = nil
		end
		local okN, n = pcall(fill.GetNumMaskTextures, fill)
		for i = 1, (okN and type(n) == "number" and n) or 0 do
			local mask = fill:GetMaskTexture(i)
			if mask then
				want[mask] = true
			end
		end
		tint.melloMasks = tint.melloMasks or {}
		for mask in pairs(tint.melloMasks) do
			if not want[mask] and mask ~= tint.melloCrop then
				pcall(tint.RemoveMaskTexture, tint, mask)
				tint.melloMasks[mask] = nil
			end
		end
		for mask in pairs(want) do
			if not tint.melloMasks[mask] and pcall(tint.AddMaskTexture, tint, mask) then
				tint.melloMasks[mask] = true
			end
		end
	end
end

local function UpdateAllExecute()
	for bar in pairs(healthBars) do
		tintSynced[bar] = nil
		pcall(UpdateExecute, bar)
	end
end

local colourHooked = setmetatable({}, { __mode = "k" })   -- [health bar] = true: SetStatusBarColor hooked
-- The game recolours health bars itself (threat / aggro display, reaction
-- on nameplates): with "Colour Overrides Threat" on, the module's colour is
-- put back right after each of those calls (user, 2026-09-21).
HookHealthColor = function(bar)
	if not bar or colourHooked[bar] or type(bar.SetStatusBarColor) ~= "function" then
		return
	end
	colourHooked[bar] = true
	-- By health follows every change of the value
	if bar.HookScript then
		Perf.HookScript(bar, "OnValueChanged", function(self)
			if M.isEnabled and M.db.healthColor == "health" then
				pcall(RecolorHealthBar, self)
			end
			if M.isEnabled and (M.db.executeRange or executeTints[self]) then
				pcall(UpdateExecute, self)
			end
		end)
	end
	hooksecurefunc(bar, "SetStatusBarColor", function(self)
		if recolouring or not M.isEnabled or not M.db.overrideThreat or M.db.healthColor == "green" then
			return
		end
		pcall(RecolorHealthBar, self)
	end)
end

local function RecolorAllHealthBars()
	for bar in pairs(healthBars) do
		RecolorHealthBar(bar)
	end
end


-- Bars that lock their colour expect white so their own green atlas shows.
local function ResetHealthColors()
	for bar in pairs(healthBars) do
		if bar.lockColor then
			bar:SetStatusBarColor(1, 1, 1)
		end
	end
end

local function ApplyUnitFrames()
	local list = {}
	CollectUnitFrameBars(list)
	for _, bar in ipairs(list) do
		ApplyToBar(bar, "unitframes")
	end
	RecolorAllHealthBars()
end

-- Power bars get a pre-coloured atlas plus a white bar colour from Blizzard;
-- with a flat texture the colour has to come from the power type instead.
local function RecolorManaBar(manaBar)
	if not manaBar or tracked[manaBar] ~= "unitframes" or not Active("unitframes") then
		return
	end
	if covered[manaBar] then
		CoverBar(manaBar)
		return
	end
	if M.db.texture == "default" then
		return   -- the game's power atlas is coloured already; it expects white
	end
	local info = manaBar.overrideInfo or (PowerBarColor and manaBar.powerToken and PowerBarColor[manaBar.powerToken])
	if info and info.r then
		manaBar:SetStatusBarColor(info.r, info.g, info.b)
	end
end

--------------------------------------------------------------------------------
-- Raid-style frames (compact party / raid frames)
--------------------------------------------------------------------------------

local function ApplyCompactFrame(frame)
	if not frame or (frame.IsForbidden and frame:IsForbidden()) then
		return
	end
	if frame.healthBar then
		ApplyToBar(frame.healthBar, "raidframes")
	end
	if frame.powerBar then
		ApplyToBar(frame.powerBar, "raidframes")
	end
end

local function ApplyCompactList(list)
	if type(list) == "table" then
		for _, frame in ipairs(list) do
			ApplyCompactFrame(frame)
		end
	end
end

local function ApplyRaidFrames()
	if CompactPartyFrame then
		ApplyCompactList(CompactPartyFrame.memberUnitFrames)
		ApplyCompactList(CompactPartyFrame.petUnitFrames)
	end
	for i = 1, 8 do
		local group = _G["CompactRaidGroup" .. i]
		if group then
			ApplyCompactList(group.memberUnitFrames)
		end
	end
	for i = 1, 80 do
		ApplyCompactFrame(_G["CompactRaidFrame" .. i])
	end
	local container = CompactRaidFrameContainer
	if container and type(container.ApplyToFrames) == "function" then
		pcall(container.ApplyToFrames, container, "normal", ApplyCompactFrame)
		pcall(container.ApplyToFrames, container, "mini", ApplyCompactFrame)
	end
end

--------------------------------------------------------------------------------
-- Cast bars
--------------------------------------------------------------------------------

local hookedCastBars = setmetatable({}, { __mode = "k" })
local CAST_FILL = { 1.0, 0.7, 0.0 }   -- a cast's fill where the game names no colour (the preview's too)

local function RecolorCastBar(bar, isFull)
	local ok, color = pcall(function()
		local info = bar:GetTypeInfo(bar.barType or CastingBarType.Standard)
		return isFull and info.classicFullColor or info.classicFillColor
	end)
	if ok and color and color.GetRGB then
		bar:SetStatusBarColor(color:GetRGB())
	else
		bar:SetStatusBarColor(CAST_FILL[1], CAST_FILL[2], CAST_FILL[3])
	end
end

local function ApplyToCastBar(bar, group)
	if not bar or type(bar.SetStatusBarTexture) ~= "function" then
		return
	end
	ApplyToBar(bar, group)
	if not bar.classicStyleCastBar then
		RecolorCastBar(bar, false)
	end
	if not hookedCastBars[bar] and type(bar.UpdateBarFillTexture) == "function" then
		hookedCastBars[bar] = true
		hooksecurefunc(bar, "UpdateBarFillTexture", function(self, isFull)
			local grp = tracked[self]
			if grp and Active(grp) and not self.classicStyleCastBar then
				RecolorCastBar(self, isFull)
			end
		end)
	end
end

local function ApplyCastBars()
	ApplyToCastBar(PlayerCastingBarFrame, "castbars")
	ApplyToCastBar(PetCastingBarFrame, "castbars")
	for _, frame in ipairs(TargetLikeFrames()) do
		if frame then
			ApplyToCastBar(frame.spellbar, "castbars")
		end
	end
end

--------------------------------------------------------------------------------
-- Nameplates
--------------------------------------------------------------------------------

local hookedNamePlates = setmetatable({}, { __mode = "k" })

local function ApplyNamePlateUnitFrame(unitFrame, relayout)
	if not unitFrame or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then
		return
	end
	local healthBar = unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar
	if healthBar then
		ApplyToBar(healthBar, "nameplates")
		healthBars[healthBar] = true
		HookHealthColor(healthBar)
		-- on a relayout the game may just have set its threat colour: it
		-- stands unless "Colour Overrides Threat" is on (audit, 2026-09-22)
		if not relayout or M.db.overrideThreat then
			pcall(RecolorHealthBar, healthBar)
		end
	end
	local castBar = unitFrame.CastBarsContainer and unitFrame.CastBarsContainer.castBar
	if castBar then
		ApplyToCastBar(castBar, "nameplates")
	end
	if not hookedNamePlates[unitFrame] and type(unitFrame.UpdateAnchors) == "function" then
		hookedNamePlates[unitFrame] = true
		-- UpdateAnchors sets the bar atlas directly on the texture, bypassing
		-- SetStatusBarTexture, so re-apply here.
		hooksecurefunc(unitFrame, "UpdateAnchors", function(self)
			if Active("nameplates") then
				ApplyNamePlateUnitFrame(self, true)
			end
		end)
	end
end

local function ApplyNamePlates()
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			if plate and not (plate.IsForbidden and plate:IsForbidden()) then
				ApplyNamePlateUnitFrame(plate.UnitFrame)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Personal resource display
--------------------------------------------------------------------------------

local function ApplyPersonal()
	local prd = PersonalResourceDisplayFrame
	if not prd then
		return
	end
	if prd.HealthBarsContainer then
		ApplyToBar(prd.HealthBarsContainer.healthBar, "personal")
	end
	ApplyToBar(prd.PowerBar, "personal")
	ApplyToBar(prd.AlternatePowerBar, "personal")
end

--------------------------------------------------------------------------------
-- Experience / reputation / honor bars
--------------------------------------------------------------------------------

local function ApplyStatusBars()
	local manager = StatusTrackingBarManager
	if not manager then
		return
	end
	local containers = manager.barContainers
	if type(containers) ~= "table" then
		containers = { manager.MainStatusTrackingBarContainer, manager.SecondaryStatusTrackingBarContainer }
	end
	for _, container in ipairs(containers) do
		if container and type(container.bars) == "table" then
			for _, bar in pairs(container.bars) do
				local statusBar = bar.StatusBar
				if statusBar then
					local tex = statusBar:GetStatusBarTexture()
					local atlas = tex and tex.GetAtlas and tex:GetAtlas()
					ApplyToBar(statusBar, "statusbars")
					local r, g, b = StatusTrackingColorForAtlas(atlas)
					if r then
						statusBar:SetStatusBarColor(r, g, b)
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Cooldown manager bars
--------------------------------------------------------------------------------

local hookedViewers = setmetatable({}, { __mode = "k" })

local function ApplyCooldownViewer(viewer)
	if not viewer or not viewer.itemFramePool then
		return
	end
	for item in viewer.itemFramePool:EnumerateActive() do
		if item.Bar then
			ApplyToBar(item.Bar, "cooldowns")
		end
	end
	if not hookedViewers[viewer] and type(viewer.RefreshLayout) == "function" then
		hookedViewers[viewer] = true
		hooksecurefunc(viewer, "RefreshLayout", function(self)
			if Active("cooldowns") then
				ApplyCooldownViewer(self)
			end
		end)
	end
end

local function ApplyCooldowns()
	ApplyCooldownViewer(BuffBarCooldownViewer)
end

--------------------------------------------------------------------------------
-- Events & hooks
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" and Active("nameplates") then
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		if plate and not (plate.IsForbidden and plate:IsForbidden()) then
			ApplyNamePlateUnitFrame(plate.UnitFrame)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if Active("personal") then
			ApplyPersonal()
		end
	end
	if M.db and M.db.executeRange then
		UpdateAllExecute()
	end
end)

local hooksInstalled = false

local function InstallHooks()
	if hooksInstalled then
		return
	end
	hooksInstalled = true
	if type(UnitFrameManaBar_UpdateType) == "function" then
		hooksecurefunc("UnitFrameManaBar_UpdateType", function(manaBar)
			pcall(RecolorManaBar, manaBar)
		end)
	end
	if type(UnitFrameManaBar_UpdateTypeOld) == "function" then
		hooksecurefunc("UnitFrameManaBar_UpdateTypeOld", function(manaBar)
			pcall(RecolorManaBar, manaBar)
		end)
	end
	if type(UnitFrameHealthBar_Update) == "function" then
		hooksecurefunc("UnitFrameHealthBar_Update", function(statusbar)
			pcall(RecolorHealthBar, statusbar)
		end)
	end
	-- Compact frames are (re)configured through these whenever they are created
	-- or the raid layout changes.
	for _, fname in ipairs({ "DefaultCompactUnitFrameSetup", "DefaultCompactMiniFrameSetup" }) do
		if type(_G[fname]) == "function" then
			hooksecurefunc(fname, function(frame)
				if Active("raidframes") then
					ApplyCompactFrame(frame)
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

local appliers = {
	unitframes = ApplyUnitFrames,
	raidframes = ApplyRaidFrames,
	nameplates = ApplyNamePlates,
	personal = ApplyPersonal,
	statusbars = ApplyStatusBars,
	castbars = ApplyCastBars,
	cooldowns = ApplyCooldowns,
}

local function ApplyAll()
	for group, apply in pairs(appliers) do
		if M.db[group] then
			apply()
		end
	end
	-- Power bars need their colour re-derived after the texture swap.
	local list = {}
	CollectUnitFrameBars(list)
	for _, bar in ipairs(list) do
		if bar and bar.powerToken then
			pcall(RecolorManaBar, bar)
		end
	end
end

-- The kit modules call this after bracketing / releasing a bar.
function M:RefreshMask(bar)
	if bar and self.isEnabled then
		pcall(UpdateMask, bar)
	end
end

--------------------------------------------------------------------------------
-- The Configurator's unit frame preview (0.15.0, Core/ConfigPreview.lua):
-- what this module puts on the bars, for SAMPLE bars the preview makes. Pure:
-- no bar of the game is touched and no unit is read -- the player's own
-- health may be secret even out of combat on this client, so the live
-- HealthColorFor (which reads the bar's unit) is never called for it.
--   M.PreviewTexture(area) -> texture, active
--       texture  the chosen texture's path, or nil where the game's own art
--                shows ("Default (Blizzard)"; with an `area` -- a group of
--                `appliers`: "unitframes", "raidframes", "castbars",
--                "personal" ... -- also while the module or that area is off)
--       active   the module works on that area's bars (its colours apply)
--   M.PreviewHealthColor(mode, sample) -> r, g, b
--       mode    a Health Bar Colour ("green", "class", "reaction",
--               "health"); nil: the one chosen
--       sample  plain values only: { class = "MAGE" (a player's class
--               file), reaction = 1..8 (an NPC's, read when there is no
--               class), fraction = 0..1 (1 when not given), execute = true
--               (an enemy: Execute Range tints it below its line), area =
--               the group its bar is in ("unitframes" when not given) }
--       as HealthColorFor answers for such a unit: the class colour
--       (RAID_CLASS_COLORS), the reaction colour (FACTION_BAR_COLORS), By
--       health from this module's own curve at the plain fraction (its
--       Evaluate, else the same three stops worked out here), the game's
--       green otherwise; purple under the execute line while the module
--       works on that area and it is the unit frames or the nameplates (as
--       the live tint), whatever mode is asked for
--   M.PreviewPowerColor(token) -> r, g, b, atlas   a power type's colour
--       (the game's PowerBarColor, which RecolorManaBar puts on a flat
--       texture) and the game's own art for it on a player frame
--   M.PreviewCastColor() -> r, g, b   a cast's fill (RecolorCastBar's)
--------------------------------------------------------------------------------

do
	local NONE = {}
	local EXECUTE_AREAS = { unitframes = true, nameplates = true }   -- (the groups UpdateExecute tints)

	function M.PreviewTexture(area)
		local db = M.db
		local active = (area ~= nil and M.isEnabled and db and db[area]) and true or false
		if not db or db.texture == "default" or (area ~= nil and not active) then
			return nil, active
		end
		local texture = db.texture
		return IsPlainString(texture) and texture or nil, active
	end

	-- the fraction as a plain number from 0 to 1 (1: none given)
	local function Fraction(v)
		if not IsPlainNumber(v) then
			return 1
		end
		return math.max(0, math.min(1, v))
	end

	-- By health at a plain fraction: the curve's own answer where it can
	-- give one, else its three stops
	local function ByHealth(fraction)
		local curve = HealthCurve()
		if curve and curve.Evaluate then
			local ok, color = pcall(curve.Evaluate, curve, fraction)
			if ok and color and color.GetRGB then
				local r, g, b = color:GetRGB()
				if IsPlainNumber(r) and IsPlainNumber(g) and IsPlainNumber(b) then
					return r, g, b
				end
			end
		end
		for i = 2, #HEALTH_STOPS do
			local a, b = HEALTH_STOPS[i - 1], HEALTH_STOPS[i]
			if fraction <= b[1] then
				local t = (fraction - a[1]) / (b[1] - a[1])
				return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
			end
		end
		local last = HEALTH_STOPS[#HEALTH_STOPS]
		return last[2], last[3], last[4]
	end

	function M.PreviewHealthColor(mode, sample)
		sample = type(sample) == "table" and sample or NONE
		local db = M.db or NONE
		mode = mode or db.healthColor or "green"
		local fraction = Fraction(sample.fraction)
		-- the tint is this module's, on the unit frames' and the nameplates'
		-- bars only, while it works on them (UpdateExecute's test)
		local area = IsPlainString(sample.area) and sample.area or "unitframes"
		if sample.execute and db.executeRange and M.isEnabled and EXECUTE_AREAS[area] and db[area] then
			-- ExecuteCurve's line: on below it, off from it (and off at none
			-- left: a dead unit)
			local at = math.max(1, math.min(99, tonumber(db.executeBelow) or 20)) / 100
			if fraction > 0 and fraction < at then
				return EXECUTE_COLOR[1], EXECUTE_COLOR[2], EXECUTE_COLOR[3]
			end
		end
		if mode == "health" then
			return ByHealth(fraction)
		end
		if mode == "class" or mode == "reaction" then
			local class = IsPlainString(sample.class) and sample.class or nil
			if class then
				local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
				if color then
					return color.r, color.g, color.b
				end
			elseif mode == "reaction" then
				local reaction = IsPlainNumber(sample.reaction) and sample.reaction or nil
				local color = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
				if color then
					return color.r, color.g, color.b
				end
			end
		end
		return 0.0, 1.0, 0.0
	end

	function M.PreviewPowerColor(token)
		local info = IsPlainString(token) and PowerBarColor and PowerBarColor[token]
		if type(info) ~= "table" or not IsPlainNumber(info.r) then
			return 0.0, 0.0, 1.0, nil   -- (the game's mana blue)
		end
		local atlas = info.atlasElementName and ("UI-HUD-UnitFrame-Player-PortraitOn-Bar-" .. info.atlasElementName)
			or info.atlas
		return info.r, info.g, info.b, IsPlainString(atlas) and atlas or nil
	end

	-- the game's standard cast fill (its type table; a client without it
	-- raises, answered by the pcall below)
	local function StandardFill()
		return _G.CastingBarTypeInfo[CastingBarType.Standard].classicFillColor:GetRGB()
	end

	function M.PreviewCastColor()
		local ok, r, g, b = pcall(StandardFill)
		if ok and IsPlainNumber(r) and IsPlainNumber(g) and IsPlainNumber(b) then
			return r, g, b
		end
		return CAST_FILL[1], CAST_FILL[2], CAST_FILL[3]
	end
end

function M:OnInit(db)
	self.db = db
end

-- (0.19.8) switched on after the login's PLAYER_ENTERING_WORLD (Core's
-- start-up pass over the login's first frames): that event as it came
function M:OnLoginWorld(...)
	MelloUI:ReplayWorld(eventFrame, ...)
end

function M:OnEnable(db)
	self.db = db
	InstallHooks()
	ApplyAll()
	eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
	eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
	UpdateAllExecute()
end

function M:OnDisable()
	eventFrame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
	eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
	eventFrame:UnregisterEvent("PLAYER_TARGET_CHANGED")
	eventFrame:UnregisterEvent("PLAYER_FOCUS_CHANGED")
	for group in pairs(appliers) do
		RestoreGroup(group)
	end
	ResetHealthColors()
	for _, tint in pairs(executeTints) do
		tint:Hide()
	end
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if appliers[key] then
		if value then
			appliers[key]()
			if key == "unitframes" then
				local list = {}
				CollectUnitFrameBars(list)
				for _, bar in ipairs(list) do
					if bar and bar.powerToken then
						pcall(RecolorManaBar, bar)
					end
				end
			end
		else
			RestoreGroup(key)
			if key == "unitframes" then
				ResetHealthColors()
			end
		end
	elseif key == "texture" then
		for group in pairs(appliers) do
			if db[group] then
				ReapplyGroup(group)
			end
		end
		RecolorAllHealthBars()
	elseif key == "executeRange" or key == "executeBelow" then
		UpdateAllExecute()
	elseif key == "healthColor" or key == "overrideThreat" then
		-- under Default the art follows the colour: the white twin for a
		-- colour, the game's green for green
		if key == "healthColor" and db.texture == "default" and db.unitframes then
			ReapplyGroup("unitframes")
		end
		RecolorAllHealthBars()
	end
end

MelloUI:Profile("BarTextures", "nameplate events", eventFrame)
MelloUI:Profile("BarTextures", "nameplate relayout", ApplyNamePlateUnitFrame)
MelloUI:Profile("BarTextures", "texture (re)apply", SetTexture)
MelloUI:Profile("BarTextures", "health recolour", RecolorHealthBar)

--------------------------------------------------------------------------------
-- /btdump exec: the execute tint on your target's health bars, step by step
-- (user, 2026-09-23: "the execute range didnt work")
--------------------------------------------------------------------------------
SLASH_MELLOBTDUMP1 = "/btdump"
SlashCmdList.MELLOBTDUMP = function()
	MelloUI:ClearLog()
	local function S(v)
		if issecretvalue and issecretvalue(v) then
			return "<secret>"
		end
		return tostring(v)
	end
	MelloUI:Print("Bar Textures on: %s   Execute Range: %s   below: %s%%   unit frames: %s   nameplates: %s",
		S(M.isEnabled), S(M.db and M.db.executeRange), S(M.db and M.db.executeBelow), S(Active("unitframes")), S(Active("nameplates")))
	local curve = ExecuteCurve()
	MelloUI:Print("curve: %s   C_CurveUtil: %s   UnitHealthPercent: %s", S(curve), S(C_CurveUtil ~= nil), S(UnitHealthPercent ~= nil))
	-- the curve on plain inputs: does it carry the alpha (1 below, 0 above)?
	if curve then
		local names = {}
		local mt = getmetatable(curve)
		local index = mt and mt.__index
		if type(index) == "table" then
			for k, v in pairs(index) do
				if type(v) == "function" then
					names[#names + 1] = k
				end
			end
		end
		table.sort(names)
		MelloUI:Print("curve methods: %s", table.concat(names, ", "))
		for _, x in ipairs({ 0.1, 0.5, 0.9 }) do
			local ok, c = pcall(function() return curve:Evaluate(x) end)
			if ok and c and c.GetRGBA then
				local r, g, b, a = c:GetRGBA()
				MelloUI:Print("   curve at %.1f: %s %s %s alpha %s", x, S(r), S(g), S(b), S(a))
			else
				MelloUI:Print("   curve at %.1f: %s", x, ok and S(c) or ("error: " .. S(c)))
			end
		end
	end
	local okP, php = pcall(UnitHealthPercent, "target", true)
	MelloUI:Print("target's health percent (no curve): %s", okP and S(php) or ("error: " .. S(php)))
	-- the target's nameplate bar, if it has one
	local okN, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
	local uf = okN and plate and plate.UnitFrame
	local targetPlateBar = uf and uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
	local found = 0
	for bar in pairs(healthBars) do
		local unit = UnitOf(bar)
		if unit and (unit == "target" or bar == targetPlateBar) then
			found = found + 1
			local okA, attackable = pcall(UnitCanAttack, "player", unit)
			MelloUI:Print("bar %d: unit %s, group %s, attackable %s", found, S(unit), S(tracked[bar]), okA and S(attackable) or "error")
			local color
			if curve then
				local ok, c = pcall(UnitHealthPercent, unit, true, curve)
				MelloUI:Print("   curve answer: %s (%s)", ok and S(c) or "error", ok and type(c) or S(c))
				color = ok and c or nil
			end
			if color then
				local a = color.a
				local okR, r, g, b, a2 = pcall(function() return color:GetRGBA() end)
				MelloUI:Print("   alpha field: %s   GetRGBA: %s %s %s %s", S(a), okR and S(r) or "error", S(g), S(b), S(a2))
			end
			local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
			local okL, layer, sub = pcall(function() return fill:GetDrawLayer() end)
			MelloUI:Print("   fill: %s, layer %s %s", S(fill ~= nil), okL and S(layer) or "?", S(sub))
			local tint = executeTints[bar]
			if tint then
				local okT, tl, ts = pcall(tint.GetDrawLayer, tint)
				MelloUI:Print("   tint: shown %s, alpha %s, layer %s %s, points %s", S(tint:IsShown()), S(tint:GetAlpha()), okT and S(tl) or "?", S(ts), S(tint:GetNumPoints()))
			else
				MelloUI:Print("   no tint made on this bar yet")
			end
		end
	end
	if found == 0 then
		MelloUI:Print("No health bar of your target is known to Bar Textures (target something first).")
	end
	MelloUI:ShowLog("btdump exec")
end

-- What this module keeps beside the game's frames (hard rule 1: weak-keyed
-- tables, never keys on the frames), for the dumps and the tests: read only
M.kept = { colourHooked = colourHooked }
