--------------------------------------------------------------------------------
-- MelloUI - Unit Frames
--
-- Layout tweaks for the player, target and focus frames:
--   * names centred above the health bar
--   * transparent name band (the reaction coloured strip behind target names)
--   * no red combat flash / status glow around the frames
--   * adjustable frame art opacity
--   (the player frame's Fade Out Of Combat, 0.14.0, is the Fader's since
--   0.17.0: Core/Fader.lua and Modules/Fader.lua, its settings carried over)
--   * (one-look D5, 2026-10-15) the party members' level on the name line,
--     the soft name band behind the player's, pet's, target of target's and
--     party's names, Level Up and XP Gain, the frames' parts for the frame
--     effects (M:PartsOf / M:CoverOf / M:RingOf) and the Reminder widget's
--     anchor (M:ReminderAnchor) -- moved here from the Unit Frames Kit
--     (UnitFramePanel), which fills its painted ring, orb and stand-in
--     dressing in through M:SetSkinHooks
--   * the party and raid frames' names in the chosen form under a cover
--
-- Combined with Dark Mode, Bar Textures (class / reaction health colour) and
-- Bar Text this gives the flat "RougeUI" look.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("UnitFrames")
local hooksecurefunc = Perf.hooksecurefunc
-- (0.17.0) a write back onto a game region, counted for /melloperf
local WriteBack = MelloUI.Perf.WriteBack or function() end
local Shared = Perf.Shared or function(_, fn) return fn end
-- MelloUI.Safe (Core.lua): secret values asked for first
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number

local M = MelloUI:RegisterModule("UnitFrames", {
	title = "Unit Frames",
	slash = "player",   -- (0.21.3: /mello player level; from the Unit Frames Kit since one-look D5)
	desc = "Centred names, transparent name band, no combat flash and frame art opacity for player, target and focus; the party's levels, the names' soft bands, Level Up and XP Gain.",
	icon = "Interface\\Icons\\INV_Misc_GroupLooking",
	flavour = "Player, target and focus, centred and calm. Frame art at the opacity you choose.",
	group = "Frames and bars", navOrder = 1,
	role = "replaces",
	tweak = { label = "Unit Frame Tweaks", desc = "Name and glow tweaks on the unit frames, the party's levels and the names' soft bands (they step aside where the reskin covers them), Level Up and XP Gain.", order = 5 },
	defaults = {
		centerNames = true,
		nameFormat = "both",   -- set by UI Modifications' "Show Names As" (one setting for every name)
		hideReputationColor = true,
		hideCombatGlow = true,
		hideStatusGlow = true,
		hidePvPBadge = true,
		frameAlpha = 1,
		levelUp = true,
		xpGain = true,
	},
	options = {
		{ type = "header", name = "Names" },
		{ type = "toggle", key = "centerNames", name = "Centre Names", desc = "Centre the unit name above the health bar." },
		{ type = "toggle", key = "hideReputationColor", name = "Transparent Name Band",
		  desc = "Hide the reaction coloured strip behind target and focus names." },
		{ type = "header", name = "Glows" },
		{ type = "toggle", key = "hideCombatGlow", name = "Hide Combat Flash",
		  desc = "Hide the red flash around the player, target, focus, pet and party frames while in combat or when a target attacks." },
		{ type = "toggle", key = "hideStatusGlow", name = "Hide Status Glow",
		  desc = "Hide the glow around the player portrait and name that shows resting (yellow) and combat (red), and the pet frame's glow while your pet attacks." },
		-- (the user, 2026-10-09: "remove that awfull diamond icon and its border
		-- and background from the frames": the game's honour badge while
		-- flagged for PvP)
		{ type = "toggle", key = "hidePvPBadge", name = "Hide PvP Badge",
		  desc = "Hide the PvP badge beside the portrait of the player, target and focus frames: the diamond with your honour rank, or the faction icon, that shows while you or they are flagged for PvP." },
		{ type = "header", name = "Frame Art" },
		{ type = "slider", key = "frameAlpha", name = "Frame Art Opacity", min = 0.1, max = 1, step = 0.05, percent = true,
		  desc = "Opacity of the frame art around the bars and portraits. The bars themselves stay solid." },
		-- (one-look D5: the two below moved from the Unit Frames Kit, keys and
		-- rows kept -- Core.lua's MERGES carries a saved "off"; no header row
		-- of their own: in the schema they sit under Frame Art, on the page
		-- each has its one row, Core/ConfigLayout.lua)
		-- (0.21.3; the user, 2026-10-13: "Yes to all" to the animation previews)
		{ type = "toggle", key = "levelUp", name = "Level Up",
		  desc = "When you gain a level, a light runs along the experience bar and the on-screen notice says your new level and, with the Quest List, how many quests it opened in your zone (their givers pop onto the world map the next time it shows them). With the painted reskin, the number in your player frame's level circle also turns over with a ring of light. Not with Reduce Motion: then only the notice." },
		-- (0.22.1; the user, 2026-10-14: "build all 5" to the animation previews)
		{ type = "toggle", key = "xpGain", name = "XP Gain",
		  desc = "When you gain experience, the stretch of the experience bar just gained lights up while a light runs along it to the new end. Not with Reduce Motion." },
	},
})

--------------------------------------------------------------------------------
-- The name's form (user, 2026-09-22): after the game has set a frame's name
-- (UnitFrame_Update for the player, target, focus, pet and target-of-target
-- frames), the text is set again in the chosen form; the party and raid
-- frames' names (one-look D5) wear it on a cover of ours (Compact, below).
-- Nameplates are the Nameplates module's (their compact frames are skipped
-- here). Post-hooks only.
--------------------------------------------------------------------------------

local function IsNamePlateFrame(frame)
	local options = frame.optionTable
	if options and (options == NamePlateEnemyFrameOptions or options == NamePlateFriendlyFrameOptions or options == NamePlatePlayerFrameOptions) then
		return true
	end
	local parent = frame.GetParent and frame:GetParent()
	local name = parent and parent.GetName and parent:GetName()
	return type(name) == "string" and name:sub(1, 9) == "NamePlate"
end

-- The form the names are put in, or nil while the game's own text stands
-- ("both", the default: the full name; or the module off)
local function NameMode()
	local db = M.isEnabled and M.db
	local mode = db and db.nameFormat or "both"
	if mode == "both" then
		return nil
	end
	return mode
end

-- The target of target's name (0.17.0; the user's FPS in combat,
-- docs/plans/fps-portrait-fix.md): its frame runs UnitFrame_Update on EVERY
-- frame (its OnUpdate), so a form written on the game's name was undone by
-- the game each frame and written again here, a text laid out twice a
-- frame. There a COVER of ours shows the form: a string on the name's rect,
-- in its font and colour (copied when the game changes them), the game's
-- name hidden under it by its alpha, which the game never sets. Its text is
-- set only when it changes; the game's own writes land on its hidden name.
-- Back to the full name (or the module off): the cover hidden, the game's
-- name shown again. (One-look D5: the party and raid frames' names wear one
-- too, Compact below; there the game's name is parked, not faded.)
-- Keyed by the frame AND by its name region (two kinds of keys, no clash):
-- the name's hooks find the cover by the name (a parked name's parent is
-- our holder, not its frame)
local nameCovers = setmetatable({}, { __mode = "k" })   -- [frame] / [name] = { fs, text, park, home, parked }
-- (the party and raid frames' names: its fields further down, used only when
-- called -- the functions above them run after the whole file has loaded)
local Compact = {}

local function EveryFrame(frame)
	return frame.frameType == "TargetofTarget"
end

local function CopyNameLook(name)
	local c = name and nameCovers[name]
	if not c then
		return
	end
	-- (one-look D6: the shared cover's copy, Core/Shade.lua -- the font, the
	-- justify (the raid frames' Legacy layout justifies the name left, the
	-- others centre it: the game sets it in its frame setup only), the
	-- shadow, its last colour handed back -- then the name's colour, kept by
	-- the cover so a Font Style copy hands it back too)
	MelloUI.Shade:CoverFont(c.fs)
	local okC, r, g, b, a = pcall(name.GetTextColor, name)
	if okC and type(r) == "number" and type(g) == "number" and type(b) == "number" then
		MelloUI.Shade:CoverColour(c.fs, r, g, b, type(a) == "number" and a or 1)
	end
end

local function NameCover(frame)
	local c = nameCovers[frame]
	if c then
		return c
	end
	local name = frame.name
	-- (a party or raid frame's cover on its frame: its name gets parked in a
	-- holder of ours)
	local compact = Compact.Is(frame)
	local parent = compact and frame or (name.GetParent and name:GetParent() or frame)
	-- (one-look D6: the one cover maker, Shade:Cover -- the name's rect, draw
	-- layer and sublevel, font, justify and shadow, no wrap; its colour set
	-- with SetTextColor, the unit frames' names'. A compact frame's is made
	-- hidden: shown only once the game's name is parked, Compact.Park --
	-- never the form over a full name still seen)
	local fs = MelloUI.Shade:Cover(parent, name, { hidden = compact, textColour = true })
	if not fs then
		return nil
	end
	c = { fs = fs, text = nil }
	nameCovers[frame] = c
	nameCovers[name] = c
	CopyNameLook(name)
	hooksecurefunc(name, "SetTextColor", CopyNameLook)
	hooksecurefunc(name, "SetFontObject", CopyNameLook)
	hooksecurefunc(name, "SetFont", CopyNameLook)
	-- (set in the game's frame setup only, CompactUnitFrame.lua's
	-- DefaultCompactUnitFrameSetup / its mini frame's: never per update)
	hooksecurefunc(name, "SetJustifyH", CopyNameLook)
	return c
end

-- the form on a per-frame name's cover (text set only when it changed)
local function CoverName(frame, unit, mode)
	local c = NameCover(frame)
	if not c then
		return
	end
	local text = MelloUI:UnitNameAs(unit, mode)
	-- (asked for secret first: a secret text cannot be compared, set as it is)
	local secret = Secret(text)
	if not secret and text == nil then
		return
	end
	if secret or c.text ~= text then
		c.text = not secret and text or nil
		c.fs:SetText(text)
	end
	local okA, a = pcall(frame.name.GetAlpha, frame.name)
	if not c.fs:IsShown() or not okA or Secret(a) or a ~= 0 then
		c.fs:Show()
		frame.name:SetAlpha(0)
	end
end

-- the full name back on a per-frame name: the cover away
local function UncoverName(frame)
	local c = nameCovers[frame]
	if c and c.fs:IsShown() then
		c.fs:Hide()
		c.text = nil
		frame.name:SetAlpha(1)
	end
end

local function ApplyNameFormat(frame, unit, mode)
	if EveryFrame(frame) then
		CoverName(frame, unit, mode)
		return
	end
	local text = MelloUI:UnitNameAs(unit, mode)
	if Secret(text) or text ~= nil then
		WriteBack("UnitFrames: a name's form written over the game's")
		pcall(frame.name.SetText, frame.name, text)
	end
end

-- The cheap tests first (the review, 2026-09-24): the target of target runs
-- UnitFrame_Update on every frame (its OnUpdate, 41 a second in /melloperf)
-- and at the default form there is nothing to do, so the form is asked
-- before the nameplate test (a parent's name read and cut) -- as the
-- Nameplates module's own name hook already does.
local function OnUnitFrameUpdate(frame)
	local mode = NameMode()
	if not (mode and frame and frame.name) then
		return
	end
	local unit = frame.overrideName or frame.unit
	if unit and not IsNamePlateFrame(frame) then
		ApplyNameFormat(frame, unit, mode)
	end
end

-- (one-look D5: the party and raid frames' names are no longer set again
-- after the game's CompactUnitFrame_UpdateName -- it runs on every health
-- update, so the form was written over the game's name every tick, hard
-- rule 1. A cover shows the form now: Compact, below; its post-hook is on
-- CompactUnitFrame_SetUnit, a roster change, never per update)
local nameHooked = false
local function InstallNameHooks()
	if nameHooked then
		return
	end
	nameHooked = true
	if type(UnitFrame_Update) == "function" then
		hooksecurefunc("UnitFrame_Update", OnUnitFrameUpdate)
	end
	if type(CompactUnitFrame_SetUnit) == "function" then
		hooksecurefunc("CompactUnitFrame_SetUnit", Compact.OnSetUnit)
	end
end

-- Every frame again in the given form (a setting changed, the module
-- off): the known unit frames, the text set directly, no game code run; the
-- compact party / raid members (their pets too, and every raid frame the
-- game has made: CompactRaidFrame<n> counts up past 40 with pets) handed to
-- their covers (Compact: swept out of combat).
local function RefreshNames(mode)
	local frames = { PlayerFrame, TargetFrame, FocusFrame, PetFrame, TargetFrameToT, FocusFrameToT }
	for i = 1, 5 do
		frames[#frames + 1] = _G["CompactPartyFrameMember" .. i]
		frames[#frames + 1] = _G["CompactPartyFramePet" .. i]
	end
	-- (the game's own frames only: rawget, a table, and a bound well past a
	-- 40-man raid with its pets)
	for n = 1, 120 do
		local f = rawget(_G, "CompactRaidFrame" .. n)
		if type(f) ~= "table" then
			break
		end
		frames[#frames + 1] = f
	end
	for g = 1, 8 do
		for i = 1, 5 do
			frames[#frames + 1] = _G["CompactRaidGroup" .. g .. "Member" .. i]
		end
	end
	for _, frame in ipairs(frames) do
		if Compact.Is(frame) then
			-- (never set here: the cover's, out of combat)
			Compact.seen[frame] = true
		elseif frame and frame.name and frame.unit then
			if EveryFrame(frame) then
				-- (the per-frame names: a cover, or none for the full name)
				if mode == "both" then
					UncoverName(frame)
				else
					pcall(CoverName, frame, frame.overrideName or frame.unit, mode)
				end
			else
				local text = MelloUI:UnitNameAs(frame.overrideName or frame.unit, mode)
				if Secret(text) or text ~= nil then
					pcall(frame.name.SetText, frame.name, text)
				end
			end
		end
	end
	Compact.Due()
	Compact.Listen()
end

local hiddenParent = CreateFrame("Frame", "MelloUIUnitFramesHidden", UIParent)
hiddenParent:Hide()

local originalParents = setmetatable({}, { __mode = "k" })
local originalNameLayout = setmetatable({}, { __mode = "k" })
local hooksInstalled = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function TargetLikeFrames()
	return { TargetFrame, FocusFrame }
end

local function SetHidden(region, hidden)
	if not region or not region.SetParent then
		return
	end
	if hidden then
		if region:GetParent() ~= hiddenParent then
			originalParents[region] = region:GetParent()
			region:SetParent(hiddenParent)
		end
	elseif region:GetParent() == hiddenParent then
		region:SetParent(originalParents[region] or UIParent)
	end
end

--------------------------------------------------------------------------------
-- Names
--------------------------------------------------------------------------------

local function RememberName(fs)
	if originalNameLayout[fs] then
		return
	end
	local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
	-- (the width only when it reads plain: a secret one is never kept or compared)
	originalNameLayout[fs] = {
		point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y,
		width = Num(fs:GetWidth()), justify = fs:GetJustifyH(),
	}
end

local function CenterName(fs, container)
	if not fs or not container then
		return
	end
	RememberName(fs)
	fs:ClearAllPoints()
	fs:SetPoint("BOTTOM", container, "TOP", 0, 1)
	fs:SetWidth(container:GetWidth() or 124)
	fs:SetJustifyH("CENTER")
end

local function RestoreName(fs)
	local saved = fs and originalNameLayout[fs]
	if not saved then
		return
	end
	fs:ClearAllPoints()
	if saved.point then
		fs:SetPoint(saved.point, saved.relativeTo, saved.relativePoint, saved.x or 0, saved.y or 0)
	end
	local w = Num(saved.width)
	if w and w > 0 then
		fs:SetWidth(w)
	end
	fs:SetJustifyH(saved.justify or "LEFT")
end

local function PlayerNameContainer()
	local content = PlayerFrame and PlayerFrame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	return main and main.HealthBarsContainer
end

local function ApplyNames()
	-- the kit's unit frame skin owns the names while it covers the frames
	-- (it centres them on its name plates): leave them to it
	if MelloUI.Kit and MelloUI.Kit:IsCovered("unitframes") then
		return
	end
	local on = M.isEnabled and M.db.centerNames
	if PlayerName then
		if on then
			CenterName(PlayerName, PlayerNameContainer())
		else
			RestoreName(PlayerName)
		end
	end
	for _, frame in ipairs(TargetLikeFrames()) do
		local main = frame and frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
		if main and main.Name then
			if on then
				CenterName(main.Name, main.HealthBarsContainer)
			else
				RestoreName(main.Name)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Name band, glows, frame art
--------------------------------------------------------------------------------

local hookedBands = setmetatable({}, { __mode = "k" })

local function ApplyReputationColor()
	local hide = M.isEnabled and M.db.hideReputationColor
	for _, frame in ipairs(TargetLikeFrames()) do
		local main = frame and frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
		local band = main and main.ReputationColor
		if band then
			band:SetAlpha(hide and 0 or 1)
			if not hookedBands[band] then
				hookedBands[band] = true
				-- Blizzard recolours the band on every target change with
				-- SetVertexColor(r, g, b, a), which also resets its alpha.
				hooksecurefunc(band, "SetVertexColor", function(self)
					if M.isEnabled and M.db.hideReputationColor then
						self:SetAlpha(0)
					end
				end)
			end
		end
	end
end

local function CombatFlashTextures()
	local list = {}
	if PlayerFrame and PlayerFrame.PlayerFrameContainer then
		list[#list + 1] = PlayerFrame.PlayerFrameContainer.FrameFlash
	end
	for _, frame in ipairs(TargetLikeFrames()) do
		if frame and frame.TargetFrameContainer then
			list[#list + 1] = frame.TargetFrameContainer.Flash
		end
	end
	list[#list + 1] = PetFrameFlash
	if PartyFrame then
		for i = 1, 4 do
			local member = PartyFrame["MemberFrame" .. i]
			if member then
				list[#list + 1] = member.Flash
				if member.PetFrame then
					list[#list + 1] = member.PetFrame.Flash
				end
			end
		end
	end
	return list
end

local function StatusGlowTextures()
	local list = {}
	local content = PlayerFrame and PlayerFrame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	if main then
		list[#list + 1] = main.StatusTexture
	end
	list[#list + 1] = PetAttackModeTexture
	return list
end

-- the PvP badge: the honour diamond (PrestigePortrait, its rank PrestigeBadge)
-- and the faction icon, on the player, target and focus frames (their
-- GetPvPIndicatorElements' regions)
local function PvPBadgeTextures()
	local list = {}
	local content = PlayerFrame and PlayerFrame.PlayerFrameContent
	local ctx = content and content.PlayerFrameContentContextual
	if ctx then
		list[#list + 1] = ctx.PrestigePortrait
		list[#list + 1] = ctx.PrestigeBadge
		list[#list + 1] = ctx.PVPIcon
	end
	for _, frame in ipairs(TargetLikeFrames()) do
		local tc = frame and frame.TargetFrameContent
		local tctx = tc and tc.TargetFrameContentContextual
		if tctx then
			list[#list + 1] = tctx.PrestigePortrait
			list[#list + 1] = tctx.PrestigeBadge
			list[#list + 1] = tctx.PvpIcon
		end
	end
	return list
end

local function ApplyGlows()
	local hidePvP = M.isEnabled and M.db.hidePvPBadge
	for _, tex in ipairs(PvPBadgeTextures()) do
		SetHidden(tex, hidePvP)
	end
	local hideCombat = M.isEnabled and M.db.hideCombatGlow
	for _, tex in ipairs(CombatFlashTextures()) do
		SetHidden(tex, hideCombat)
	end
	local hideStatus = M.isEnabled and M.db.hideStatusGlow
	for _, tex in ipairs(StatusGlowTextures()) do
		SetHidden(tex, hideStatus)
	end
end

--------------------------------------------------------------------------------
-- The status glows kept HIDDEN, not only parked or faded (user, 2026-09-24:
-- the game-side switch-offs that survived the adversarial review). The
-- player's resting / combat glow and the pet's attack-mode glow pulse from
-- their frames' OnUpdate for as long as the texture is SHOWN
-- (PlayerFrame_OnUpdate, PetFrameMixin:OnUpdate: an IsShown() test, then a
-- SetAlpha / SetVertexColor every frame), wherever it is parked and however
-- faded, and every pulse went through the kit's fade hooks (/melloperf
-- 2026-09-24: "MelloUIUnitFramesHidden.<child>:SetAlpha every frame", some
-- 80 hook calls a second while resting or in combat). Hidden, the test fails
-- and the pulse stops. Held while Hide Status Glow is on, or while the kit's
-- unit frame skin covers the frames (it fades them anyway): a post-hook on
-- the texture's Show / SetShown hides it again after the game shows it. Let
-- go, it is shown as the game would have it (resting or in combat; the
-- pet's while it attacks), so a kit switched off with Hide Status Glow off
-- does not leave it hidden until the next rest / combat change (the review's
-- restore gap). Texture regions only (never protected, Hide works in
-- combat), post-hooks, no field of the game's written. The threat flashes
-- are not held: the game recolours them on its threat timer whether they
-- show or not, so hiding them would only add a call (the review).
--------------------------------------------------------------------------------

local glowHooked = setmetatable({}, { __mode = "k" })
local glowHeld = false

-- v, or nil when v is secret: MelloUI.Safe (Core.lua), one set for the addon
local Plain = MelloUI.Safe.Value

local function GlowHeldWanted()
	if M.isEnabled and M.db and M.db.hideStatusGlow then
		return true
	end
	local Kit = MelloUI.Kit
	return Kit and Kit.IsCovered and Kit:IsCovered("unitframes") or false
end

-- after the game's Show / SetShown: hidden again while held (one test when not)
local OnGlowShown = Shared("Show / SetShown on the status glows", function(tex)
	if glowHeld then
		tex:Hide()
	end
end)

-- Shown again as the game would show it now (PlayerFrame_UpdateStatus:
-- resting or in combat; PetFrame: while the pet attacks). Read-only
-- questions; a pet whose state cannot be asked waits for its next
-- PET_ATTACK_START.
local function ReleaseGlows()
	local content = PlayerFrame and PlayerFrame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	local status = main and main.StatusTexture
	if status and status.SetShown then
		local isResting = _G.IsResting
		local resting = type(isResting) == "function" and Plain(isResting())
		status:SetShown((resting or Plain(PlayerFrame.inCombat)) and true or false)
	end
	local petAttacking = _G.IsPetAttackActive
	if PetAttackModeTexture and type(petAttacking) == "function" then
		local ok, attacking = pcall(petAttacking)
		if ok and Plain(attacking) then
			PetAttackModeTexture:Show()
		end
	end
end

function M:HoldStatusGlows()
	local hold = GlowHeldWanted()
	local was = glowHeld
	glowHeld = hold
	if hold then
		for _, tex in ipairs(StatusGlowTextures()) do
			if tex and tex.Hide then
				if not glowHooked[tex] then
					glowHooked[tex] = true
					hooksecurefunc(tex, "Show", OnGlowShown)
					hooksecurefunc(tex, "SetShown", OnGlowShown)
				end
				tex:Hide()
			end
		end
	elseif was then
		ReleaseGlows()
	end
end

-- the kit's unit frame skin coming on or going off (UnitFramePanel's
-- Kit:Cover / Kit:Uncover) holds or lets go, the module on or off
if MelloUI.Kit and MelloUI.Kit.OnCover then
	MelloUI.Kit:OnCover(function(group)
		if group == "unitframes" then
			M:HoldStatusGlows()
		end
	end)
end

local function FrameArtTextures()
	local list = {}
	local container = PlayerFrame and PlayerFrame.PlayerFrameContainer
	if container then
		list[#list + 1] = container.FrameTexture
		list[#list + 1] = container.VehicleFrameTexture
		list[#list + 1] = container.AlternatePowerFrameTexture
	end
	for _, frame in ipairs(TargetLikeFrames()) do
		local c = frame and frame.TargetFrameContainer
		if c then
			list[#list + 1] = c.FrameTexture
			list[#list + 1] = c.BossPortraitFrameTexture
		end
		if frame and frame.totFrame then
			list[#list + 1] = frame.totFrame.FrameTexture
		end
	end
	list[#list + 1] = PetFrameTexture
	if PartyFrame then
		for i = 1, 4 do
			local member = PartyFrame["MemberFrame" .. i]
			if member then
				list[#list + 1] = member.Texture
				list[#list + 1] = member.VehicleTexture
				if member.PetFrame then
					list[#list + 1] = member.PetFrame.Texture
				end
			end
		end
	end
	return list
end

-- (0.19.4, the options audit) The kit's unit frame skin fades this same art
-- and puts every write back to 0 (Kit:Fade): nothing is set while it covers
-- the frames. When it goes off, Kit:Unfade leaves 1 and the cover listener
-- (OnEnable) sets the chosen opacity again.
local function ApplyFrameAlpha()
	if MelloUI.Kit and MelloUI.Kit:IsCovered("unitframes") then
		return
	end
	local alpha = M.isEnabled and (tonumber(M.db.frameAlpha) or 1) or 1
	for _, tex in ipairs(FrameArtTextures()) do
		if tex and tex.SetAlpha then
			tex:SetAlpha(alpha)
		end
	end
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

-- The unit frames are protected: their regions are anchored out of combat
-- only (a vehicle swap in a fight re-anchors the name; audit 2026-09-22).
-- (Kit.lua loads before this file, so its combat queue is always there:
-- audit 2026-09-24, a dead guard gone)
local function OutOfCombat(fn)
	MelloUI.Kit:WhenOutOfCombat(fn)
end

--------------------------------------------------------------------------------
-- The party and raid frames' names: a cover (one-look D5; the build plan's
-- section 6 step 13). The game's CompactUnitFrame_UpdateName runs on every
-- health update (CompactUnitFrame.lua: UpdateHealth -> UpdateName, through
-- the healthDirty OnUpdate) and sets the name's text, its SetVertexColor and
-- Show each time; the form used to be written back after it, every tick. Now
-- a string of ours stands on the name's rect (NameCover: its font, size,
-- justify and shadow copied when the game changes them) with the form, set on
-- our own events only -- a member set (the CompactUnitFrame_SetUnit
-- post-hook), UNIT_NAME_UPDATE, GROUP_ROSTER_UPDATE, PLAYER_ENTERING_WORLD --
-- its colour copied from the game's name then. The game's name is PARKED,
-- not faded: this client's SetVertexColor puts a region's alpha back (Kit.lua's
-- Faded_OnSetAlpha, MerchantPanel; the target's ReputationColor above), and
-- the game calls it every update. Parked = moved into a hidden holder of ours,
-- a child of its own frame (the same scale; never the shared
-- MelloUIUnitFramesHidden, UIParent's child), where the game's writes land
-- unseen. Region:SetParent is protected (SimpleScriptRegionAPIDocumentation:
-- CheckAllowChangeParent), so parking and unparking run out of combat, one
-- keyed job: a member who joins in a fight shows the game's full name until
-- it ends. The game's party and raid frames only (by their names: the
-- Settings panel's preview frame, the arena's and the nameplates' are left to
-- the game). Back to the full name, or the module off: unparked, the cover
-- hidden. One cover and one holder per frame, ever; nothing made while the
-- form is the full name. (one-look D6, 2026-10-15: the user's probe B found a
-- plate NAME's SetAlpha(0) held while the mob was hit -- the game's per-update
-- SetText / SetVertexColor / Show never put it back -- so the nameplates' cover
-- hides the game's glyphs by alpha, Modules/Nameplates.lua; the alpha reset
-- noted here was seen on other regions and is not re-checked for these names:
-- they stay parked. Both covers come from MelloUI.Shade:Cover.)
--------------------------------------------------------------------------------

Compact.KEY = "Unit Frames: compact names"
Compact.seen = setmetatable({}, { __mode = "k" })   -- [frame] = true: a party / raid frame met
Compact.PREFIXES = { "CompactPartyFrame", "CompactRaidFrame", "CompactRaidGroup" }

-- a party or raid frame of the game's (a compact unit frame with a name, not
-- forbidden, not a nameplate's, named as the game names its party / raid ones)
function Compact.Is(frame)
	if type(frame) ~= "table" then
		return false
	end
	-- (asked first: a forbidden frame -- an instance's nameplate -- is never read)
	if frame.IsForbidden then
		local okF, forbidden = pcall(frame.IsForbidden, frame)
		if not okF or Secret(forbidden) or forbidden then
			return false
		end
	end
	if type(rawget(frame, "optionTable")) ~= "table" or type(rawget(frame, "name")) ~= "table" then
		return false
	end
	local okN, n = false, nil
	if frame.GetName then
		okN, n = pcall(frame.GetName, frame)
	end
	if not okN or Secret(n) or type(n) ~= "string" or IsNamePlateFrame(frame) then
		return false
	end
	for _, prefix in ipairs(Compact.PREFIXES) do
		if n:sub(1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- the form on the cover (our own regions only: safe in combat); false when
-- there is no form to show (no unit, no name to give)
function Compact.Text(frame, c, mode)
	local unit = rawget(frame, "unit")
	if Secret(unit) or type(unit) ~= "string" then
		return false
	end
	local text = MelloUI:UnitNameAs(unit, mode)
	local secret = Secret(text)
	if not secret and text == nil then
		return false
	end
	if secret or c.text ~= text then
		c.text = not secret and text or nil
		c.fs:SetText(text)
	end
	-- (the game's colour as it is now, handed on untouched: a secret one too)
	local name = frame.name
	local ok, r, g, b, a = pcall(name.GetVertexColor, name)
	if ok then
		pcall(c.fs.SetVertexColor, c.fs, r, g, b, a)
	end
	return true
end

-- the game's name into the holder, the cover shown (out of combat)
function Compact.Park(frame, c)
	if not c.park then
		local park = CreateFrame("Frame", nil, frame)
		park:SetAllPoints(frame)
		park:Hide()
		c.park = park
	end
	local name = frame.name
	if not c.home then
		local okH, home = pcall(name.GetParent, name)
		c.home = okH and home or frame
	end
	if pcall(name.SetParent, name, c.park) then
		c.parked = true
		c.fs:Show()
	else
		-- (refused -- CheckAllowChangeParent: the game's full name stays seen,
		-- so the cover stays hidden; the next sweep tries again)
		c.fs:Hide()
	end
end

-- the game's name back on its own parent, the cover hidden (out of combat)
function Compact.Unpark(frame, c)
	local name = frame.name
	if pcall(name.SetParent, name, c.home or frame) then
		c.parked = nil
		c.fs:Hide()
		c.text = nil
	end
end

-- every frame met, as the form is now (out of combat: Compact.Due)
function Compact.Sweep()
	local mode = NameMode()
	for frame in pairs(Compact.seen) do
		local c = nameCovers[frame]
		if mode and Compact.Is(frame) and type(rawget(frame, "unit")) == "string" then
			-- (none where the frame makes no font string, Shade:Cover: that
			-- frame skipped, the game's full name stays)
			c = c or NameCover(frame)
			if c and Compact.Text(frame, c, mode) then
				if not c.parked then
					Compact.Park(frame, c)
				end
			elseif c and c.parked then
				Compact.Unpark(frame, c)
			end
		elseif c and c.parked then
			Compact.Unpark(frame, c)
		end
	end
end

function Compact.Due()
	MelloUI.Kit:WhenOutOfCombat(Compact.Sweep, Compact.KEY)
end

-- a member set (a roster change, a frame's unit given or taken): its text at
-- once on a parked cover, else a sweep out of combat
Compact.OnSetUnit = Shared("CompactUnitFrame_SetUnit: a party / raid name's cover", function(frame)
	if not (NameMode() and Compact.Is(frame)) then
		return
	end
	Compact.seen[frame] = true
	local c = nameCovers[frame]
	if c and c.parked and Compact.Text(frame, c, NameMode()) then
		return
	end
	Compact.Due()
end)

Compact.OnEvent = Shared("OnEvent of the party / raid names' covers", function(_, event, unit)
	if event == "UNIT_NAME_UPDATE" then
		if Secret(unit) or type(unit) ~= "string" then
			return
		end
		local mode = NameMode()
		local due = false
		for frame in pairs(Compact.seen) do
			local c = nameCovers[frame]
			if c and c.parked and rawget(frame, "unit") == unit and not (mode and Compact.Text(frame, c, mode)) then
				due = true
			end
		end
		-- (one sweep for them all, after the walk)
		if due then
			Compact.Due()
		end
	else
		Compact.Due()
	end
end, "event")

-- its events while a form is chosen (and the module on)
function Compact.Listen()
	local on = M.isEnabled and NameMode() ~= nil
	if not (on or Compact.frame) then
		return
	end
	if not Compact.frame then
		Compact.frame = CreateFrame("Frame")
		Perf.SetScript(Compact.frame, "OnEvent", Compact.OnEvent)
	end
	if on then
		Compact.frame:RegisterEvent("UNIT_NAME_UPDATE")
		Compact.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
		Compact.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	else
		Compact.frame:UnregisterAllEvents()
	end
end

local function InstallHooks()
	if hooksInstalled then
		return
	end
	hooksInstalled = true
	-- Blizzard re-anchors the player name when switching to / from vehicle art.
	if type(PlayerFrame_UpdatePlayerNameTextAnchor) == "function" then
		hooksecurefunc("PlayerFrame_UpdatePlayerNameTextAnchor", function()
			if M.isEnabled and M.db.centerNames and PlayerName then
				OutOfCombat(function()
					if M.isEnabled and M.db.centerNames and PlayerName then
						originalNameLayout[PlayerName] = nil
						CenterName(PlayerName, PlayerNameContainer())
					end
				end)
			end
		end)
	end
	-- Art swaps (vehicle, alternate power) re-show textures; re-apply then.
	for _, name in ipairs({ "PlayerFrame_ToPlayerArt", "PlayerFrame_ToVehicleArt" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function()
				if M.isEnabled then
					OutOfCombat(function()
						if M.isEnabled then
							ApplyGlows()
							ApplyFrameAlpha()
						end
					end)
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- The painted skin's hooks (one-look D5). The Unit Frames Kit (UnitFramePanel;
-- MelloUI_Oldschool after the split) dresses the frames in the painted kit and
-- hands its pieces in here once, at its load:
--   M:SetSkinHooks{ RingOf, OrbOf, PlayerRing, FarEnd, PartyCircle, DressStandIn }
--     RingOf(portrait)       -> the kit's ring texture round it while shown
--     OrbOf(circle, number)  -> the kit's orb on a level circle, and its disc
--     PlayerRing()           -> the player's kit ring while shown
--     FarEnd(health)         -> the kit's bracket strip on the player's
--                               health bar while shown
--     PartyCircle(frame)     -> a party member's painted level circle and
--                               its number
--     DressStandIn(frame)    a party stand-in dressed as a member while the
--                            skin is on
-- Each answers nil (or does nothing) while the skin is off; without the skin
-- (the modern look) none is there.
--------------------------------------------------------------------------------

local Skin = { NAMES = { "RingOf", "OrbOf", "PlayerRing", "FarEnd", "PartyCircle", "DressStandIn" } }

function M:SetSkinHooks(hooks)
	if type(hooks) ~= "table" then
		return
	end
	for _, key in ipairs(Skin.NAMES) do
		if type(hooks[key]) == "function" then
			Skin[key] = hooks[key]
		end
	end
end

-- the painted skin dresses these frames now (its Kit:Cover groups:
-- "unitframes" the player, target, focus, pet and their targets;
-- "partyframes" the party)
local function Covered(group)
	local Kit = MelloUI.Kit
	return Kit ~= nil and Kit:IsCovered(group or "unitframes")
end

--------------------------------------------------------------------------------
-- The names' soft band (one-look D5; the user's pick 6C, "Soft band, the
-- name's line": docs/plans/onelook-b-sketches/ufparts.md). Behind the
-- player's, the pet's, the targets' targets' and each party member's name,
-- the soft dark band the nameplates and the notice wear (MelloUI.Shade:Band at
-- the soft text look's strength, Shade.TEXT; feather 8), on the name's own
-- fixed line -- one length per frame kind, so the ends line up (a party
-- member's runs on to its level: Party, below). Anchors only: no measure of
-- the text, no SetText hook, no work per frame; shown and hidden with the
-- name (post-hooks on its Show / Hide / SetShown). Under the frame's art
-- (BACKGROUND -8 on the frame that holds it). None on the target and focus:
-- their reaction strip backs the name. Shown while the module is on and the
-- painted skin does not dress the frame (its own band then, UnitFramePanel's
-- NameShade). Made out of combat: the player's, pet's and targets' targets'
-- at the module's switch-on, a party member's with its level.
--------------------------------------------------------------------------------

local NameBand = { of = setmetatable({}, { __mode = "k" }),
	LOOK = { colour = "innerPanel", feather = 8, layer = "BACKGROUND", sublevel = -8 },
	PAD = { x = 4, y = 5 } }

function NameBand.Sync(entry)
	local want = (M.isEnabled and entry.shown and not Covered(entry.group)) and true or false
	if entry.band:IsShown() ~= want then
		entry.band:SetShown(want)
	end
end

function NameBand.All()
	for _, entry in pairs(NameBand.of) do
		NameBand.Sync(entry)
	end
end

function NameBand.Shown(fs, on)
	local entry = NameBand.of[fs]
	if entry then
		entry.shown = on
		NameBand.Sync(entry)
	end
end

NameBand.OnShow = Shared("Show on a unit frame's name: its band", function(fs)
	NameBand.Shown(fs, true)
end)
NameBand.OnHide = Shared("Hide on a unit frame's name: its band", function(fs)
	NameBand.Shown(fs, false)
end)
NameBand.OnSetShown = Shared("SetShown on a unit frame's name: its band", function(fs, on)
	-- (asked for secret first: a secret answer counts as shown)
	NameBand.Shown(fs, Secret(on) or (on and true or false))
end)

-- the band behind the name `fs` on `host` (once per name), to `right` (the
-- line's other end: a party member's level) or the name's own box; `group`
-- the skin's cover group it steps aside for
function NameBand.Make(fs, host, group, right)
	if type(fs) ~= "table" or type(fs.SetText) ~= "function" or type(host) ~= "table" then
		return nil
	end
	local entry = NameBand.of[fs]
	if entry then
		return entry
	end
	local Soft = MelloUI.Shade
	if not (Soft and Soft.Band and Soft.TEXT) then
		return nil
	end
	NameBand.LOOK.alpha = Soft.TEXT.alpha
	local band = Soft:Band(host, NameBand.LOOK)
	if not band then
		return nil
	end
	if right then
		band:Anchor(fs, right, NameBand.PAD.x, NameBand.PAD.y)
	else
		band:Anchor(fs, NameBand.PAD.x, NameBand.PAD.y)
	end
	entry = { fs = fs, band = band, group = group or "unitframes" }
	NameBand.of[fs] = entry
	local okS, shown = pcall(fs.IsShown, fs)
	entry.shown = not okS or Secret(shown) or (shown and true or false)
	hooksecurefunc(fs, "Show", NameBand.OnShow)
	hooksecurefunc(fs, "Hide", NameBand.OnHide)
	hooksecurefunc(fs, "SetShown", NameBand.OnSetShown)
	NameBand.Sync(entry)
	return entry
end

-- the player's, the pet's and the targets' targets' bands (out of combat)
function NameBand.Frames()
	local pf = PlayerFrame
	local container = pf and pf.PlayerFrameContainer
	if PlayerName and container then
		NameBand.Make(PlayerName, container)
	end
	local pet = PetFrame
	if pet then
		NameBand.Make(_G.PetName or pet.name, pet)
	end
	for _, frame in ipairs(TargetLikeFrames()) do
		local tot = frame and frame.totFrame
		if tot and tot.Name then
			NameBand.Make(tot.Name, tot)
		end
	end
end

--------------------------------------------------------------------------------
-- The party members' level on the name line (one-look D5; the user's pick
-- 6C, "On the name line": ufparts.md). No circle: the member's level at the
-- end of its name's line, one column for the whole group (its right edge 101
-- in, left of the game's role icon), in the palette's text colour with the
-- soft text shadow (Shade.TEXT). Its font is the NAME's as it is now (face,
-- size, flags: Party.Font -- the user's screenshot of 2026-10-15, "17" in
-- the font object's size 10 beside a name Group Frames had sized 7), and its
-- middle the name's (Party.Place: read from the name's own anchor, so a name
-- Group Frames moved takes the level along on its line); both laid again
-- whenever the line is laid (the member made or swept, Group Frames' parts
-- laid: M:PartyLine) and, for the font, on the bus's 'fonts' (a face, a size,
-- the Outline: one listener, the next frame). A level the player moved or
-- sized in Group Frames keeps what Group Frames gave it. Every member's name
-- box 15 shorter so the two never meet (57 -> 42; the vehicle art's 56 ->
-- 41), set again after the game sets its own (UpdateNameTextAnchors, which
-- every To*Art calls right after its Name:SetWidth -- a state change, never
-- per frame), out of combat. The name's band runs on to the level. Made on
-- the member's first show, out of combat; the level read on its show and on
-- UNIT_LEVEL / GROUP_ROSTER_UPDATE (one event frame for every member); a
-- preview's stand-in (ours, no unit) says its sample's level. Away while the
-- painted skin dresses the party (its level circle then: UnitFramePanel's
-- PartyLevel) or the module is off, the game's name width back. Group Frames
-- (when on) lays it as a part the player can move, its region through
-- M:PartyLevelText(member) (nothing written on the game's frame). Of the
-- game's only the level, the name's font and its anchor are read (pcall +
-- Safe: a secret answer leaves the level as it was, or on the game's line).
--------------------------------------------------------------------------------

local Party = { of = setmetatable({}, { __mode = "k" }), hooked = setmetatable({}, { __mode = "k" }),
	alone = setmetatable({}, { __mode = "k" }),   -- [member] = true: Group Frames parted its name and level
	SHORTER = 15, X = 101, Y = -12, H = 12, KEY = "Unit Frames: party levels",
	-- (Party.Place) an anchor point's side of the box, the member's edge the
	-- level hangs from on that side, and where a box's middle lies from its
	-- point on that side, in its heights
	SIDE = { TOPLEFT = "TOP", TOP = "TOP", TOPRIGHT = "TOP", LEFT = "MID", CENTER = "MID", RIGHT = "MID",
		BOTTOMLEFT = "BOTTOM", BOTTOM = "BOTTOM", BOTTOMRIGHT = "BOTTOM" },
	EDGE = { TOP = "TOPLEFT", MID = "LEFT", BOTTOM = "BOTTOMLEFT" },
	MIDDLE = { TOP = -0.5, MID = 0, BOTTOM = 0.5 } }

-- the level and the band wanted on the party now
function Party.Wanted()
	return M.isEnabled and not Covered("partyframes")
end

function Party.Shadow(number)
	local s = MelloUI.Palette.innerPanel
	local T = MelloUI.Shade and MelloUI.Shade.TEXT
	if not (s and T) then
		return
	end
	number:SetShadowColor(s[1], s[2], s[3], T.shadow)
	number:SetShadowOffset(T.shadowX, T.shadowY)
end

function Party.Repaint()
	for _, made in pairs(Party.of) do
		Party.Shadow(made.number)
	end
end

-- the level now (none: hidden)
function Party.Update(frame)
	local made = Party.of[frame]
	if not made then
		return
	end
	local level
	if Party.Wanted() then
		local unit = rawget(frame, "unit")
		if not Secret(unit) and type(unit) == "string" then
			local okE, there = pcall(UnitExists, unit)
			if okE and not Secret(there) and there == true then
				local okL, lv = pcall(UnitLevel, unit)
				level = okL and Num(lv) or nil
			end
		else
			-- (a preview's stand-in, ours: no unit -- its sample's level, Core/ConfigPreview.lua)
			local s = rawget(frame, "sample")
			level = type(s) == "table" and Num(s.level) or nil
		end
	end
	if level then
		made.number:SetText(level > 0 and tostring(level) or "??")
	end
	made.number:SetShown(level ~= nil)
end

-- the name box: the game's less SHORTER while wanted, the game's own else;
-- never while the skin lays the name (out of combat)
function Party.Width(frame)
	local made = Party.of[frame]
	local name = rawget(frame, "Name")
	if not (made and type(name) == "table") or Covered("partyframes") then
		return
	end
	local okW, w = pcall(name.GetWidth, name)
	w = okW and Num(w) or nil
	if not w then
		return
	end
	-- (first met before we ever narrowed it: the game's)
	made.gameW = made.gameW or w
	local want = Party.Wanted() and math.max(1, made.gameW - Party.SHORTER) or made.gameW
	if math.abs(w - want) > 0.01 then
		name:SetWidth(want)
	end
end

-- the member's band on its name alone (`alone`: Group Frames has moved its
-- name or its level, the line's two ends no longer one line -- else the band
-- would stretch between them or turn inside out), else from the name on to
-- its level; anchors only, set again only when it changes
function Party.Band(frame, alone)
	alone = alone and true or false
	local made = Party.of[frame]
	local name = made and made.entry and rawget(frame, "Name")
	if not name or made.alone == alone then
		return
	end
	made.alone = alone
	local P = NameBand.PAD
	if alone then
		made.entry.band:Anchor(name, P.x, P.y)
	else
		made.entry.band:Anchor(name, made.number, P.x, P.y)
	end
end

-- the level on its name's line: its right edge on the group's one column
-- (X), its middle the name's and its box the name's height -- from the name's
-- own anchor on the member (the game's 46,-6 / 49,-6, the zh clients' -4, a
-- place Group Frames gave it) -- so in the name's font the two share a
-- baseline; the game's line (Y) for a name anchored anywhere else or read
-- secret. Anchors only: no text measured.
function Party.Place(frame, made)
	local edge, y, h = "TOPLEFT", Party.Y, Party.H
	local name = rawget(frame, "Name")
	if type(name) == "table" then
		local okP, point, rel, relPoint, _, py = pcall(name.GetPoint, name, 1)
		local okH, nh = pcall(name.GetHeight, name)
		py, nh = okP and Num(py) or nil, okH and Num(nh) or nil
		local side = okP and not Secret(point) and type(point) == "string" and Party.SIDE[point]
		local onto = okP and not Secret(relPoint) and type(relPoint) == "string" and Party.SIDE[relPoint]
		if side and onto and py and nh and nh > 0 and not Secret(rel) and rel == frame then
			edge, y, h = Party.EDGE[onto], py + Party.MIDDLE[side] * nh, nh
		end
	end
	local number = made.number
	number:ClearAllPoints()
	number:SetPoint("RIGHT", frame, edge, Party.X, y)
	number:SetHeight(h)
end

-- the name's font on the level as it is now (its font object's, the Fonts
-- module's, a size Group Frames gave the name): face, size, flags and text
-- scale; a secret or refused answer leaves the level's as it is. The colour
-- stays the palette's (SetFont keeps it).
function Party.Font(frame, made)
	local name = rawget(frame, "Name")
	if type(name) ~= "table" then
		return
	end
	local ok, face, size, flags = pcall(name.GetFont, name)
	size = ok and Num(size) or nil
	if not (size and size > 0) or Secret(face) or type(face) ~= "string" then
		return
	end
	if Secret(flags) or type(flags) ~= "string" then
		flags = ""
	end
	local number = made.number
	number:SetFont(face, size, flags)
	local okS, scale = pcall(name.GetTextScale, name)
	scale = okS and Num(scale) or nil
	if scale and scale > 0 then
		pcall(number.SetTextScale, number, scale)
	end
end

-- the level at its own place, in the name's font, right-justified, seen
-- (made; swept; the line laid by Group Frames with the level at its default
-- -- after its part reset, or a stand-in of its own with every part laid)
function Party.Home(frame, made)
	Party.Place(frame, made)
	made.number:SetJustifyH("RIGHT")
	Party.Font(frame, made)
	made.number:SetAlpha(1)
end

-- the fonts changed (the bus's 'fonts'): each level the player did not size
-- in Group Frames in its name's font again, on the next frame (after the
-- lines' own restyle, as Shade's measures)
function Party.Refont()
	for frame, made in pairs(Party.of) do
		if not made.moved then
			Party.Font(frame, made)
		end
	end
end

function Party.OnFonts()
	local Kit = MelloUI.Kit
	if Kit and Kit.NextFrame then
		Kit:NextFrame(Party.KEY, Party.Refont)
	else
		Party.Refont()
	end
end

-- the member's level and band, made once (out of combat)
function Party.Make(frame)
	local made = Party.of[frame]
	if made then
		return made
	end
	local name = rawget(frame, "Name")
	if type(name) ~= "table" or type(name.SetText) ~= "function" or not frame.CreateFontString then
		return nil
	end
	local number = frame:CreateFontString(nil, "OVERLAY")
	-- (a font to start from: the name's object; Party.Home then copies the
	-- name's font as it is, and the palette's colour goes on after this)
	local okO, object = pcall(name.GetFontObject, name)
	if okO and not Secret(object) and type(object) == "table" then
		number:SetFontObject(object)
	elseif _G.GameFontNormalSmall then
		number:SetFontObject(_G.GameFontNormalSmall)
	end
	number:SetWordWrap(false)
	local W = MelloUI.Widgets
	if W and W.Paint then
		W.Paint(number, "text", "text")
	end
	Party.Shadow(number)
	made = { number = number }
	Party.of[frame] = made
	Party.Home(frame, made)
	made.entry = NameBand.Make(name, frame, "partyframes", number)   -- (its band's entry)
	-- (Group Frames may have parted the line before the member was made)
	made.alone = false
	Party.Band(frame, Party.alone[frame])
	Party.Listen()
	Party.Update(frame)
	return made
end

-- the game's party members (the pool's active ones)
function Party.Members()
	local pf = PartyFrame
	local pool = type(pf) == "table" and pf.PartyMemberFramePool
	local list = {}
	if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
		for frame in pool:EnumerateActive() do
			list[#list + 1] = frame
		end
	end
	return list
end

-- every member: hooked, made when shown and wanted, then every level, band
-- and name box as wanted now, and each level the player did not move on its
-- name's line in its font (the game may have laid the name again: its art
-- changed) (out of combat: Party.Due)
function Party.Sweep()
	for _, frame in ipairs(Party.Members()) do
		Party.Hook(frame)
		if Party.Wanted() and not Party.of[frame] then
			local okS, shown = pcall(frame.IsShown, frame)
			if not okS or Secret(shown) or shown then
				Party.Make(frame)
			end
		end
	end
	for frame, made in pairs(Party.of) do
		Party.Update(frame)
		Party.Width(frame)
		if not made.moved then
			Party.Place(frame, made)
			Party.Font(frame, made)
		end
	end
	NameBand.All()
end

function Party.Due()
	MelloUI.Kit:WhenOutOfCombat(Party.Sweep, Party.KEY)
end

Party.OnShow = Shared("OnShow on a party member: its level", function(frame)
	if Party.of[frame] then
		Party.Update(frame)
	elseif Party.Wanted() then
		Party.Due()
	end
end, "script")

-- the game laid the name again (its art changed): its own width just set
-- (read now), ours again out of combat
Party.OnAnchors = Shared("UpdateNameTextAnchors on a party member: its name box", function(frame)
	local made = Party.of[frame]
	local name = rawget(frame, "Name")
	if made and type(name) == "table" then
		local okW, w = pcall(name.GetWidth, name)
		w = okW and Num(w) or nil
		if w then
			made.gameW = w
		end
		Party.Due()
	end
end)

-- a member's two post-hooks, once
function Party.Hook(frame)
	if Party.hooked[frame] then
		return
	end
	Party.hooked[frame] = true
	Perf.HookScript(frame, "OnShow", Party.OnShow)
	if type(frame.UpdateNameTextAnchors) == "function" then
		hooksecurefunc(frame, "UpdateNameTextAnchors", Party.OnAnchors)
	end
end

Party.OnEvent = Shared("OnEvent of the party levels", function()
	for frame in pairs(Party.of) do
		Party.Update(frame)
	end
end, "event")

-- the levels' events while the module is on and a level is made; the
-- palette's listener with the first one
function Party.Listen()
	local on = M.isEnabled and next(Party.of) ~= nil
	if not (on or Party.frame) then
		return
	end
	if not Party.frame then
		Party.frame = CreateFrame("Frame")
		Perf.SetScript(Party.frame, "OnEvent", Party.OnEvent)
		MelloUI:On("palette", Party.Repaint, Party.KEY)
		MelloUI:On("fonts", Party.OnFonts, Party.KEY)
	end
	if on then
		Party.frame:RegisterEvent("UNIT_LEVEL")
		Party.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
	else
		Party.frame:UnregisterAllEvents()
	end
end

M.Compact, M.Party, M.NameBand = Compact, Party, NameBand   -- (the tests)

-- (Group Frames' "Level" part, MelloUI_GroupFrames/GroupParts.lua) a party
-- member's level text, once made, else nil
function M:PartyLevelText(frame)
	local made = type(frame) == "table" and Party.of[frame]
	return made and made.number or nil
end

-- (Group Frames, GroupParts.lua's Parts:Lay) a party member's name line as
-- the player laid it: the band on the name alone while its name or its level
-- is moved, else on to its level (kept for a member made later); a level the
-- player did not move at its own place on the name's line in the name's font
-- (the name just laid: moved, sized; its part reset; a frame of Group Frames'
-- own, every part laid at its default) -- one the player moved keeps Group
-- Frames' place and size
function M:PartyLine(frame, nameMoved, levelMoved)
	if type(frame) ~= "table" then
		return
	end
	local alone = (nameMoved or levelMoved) and true or nil
	Party.alone[frame] = alone
	local made = Party.of[frame]
	if made then
		if not levelMoved then
			Party.Home(frame, made)
		end
		made.moved = levelMoved and true or nil
	end
	Party.Band(frame, alone)
end

-- the party members' parts as their skin is now: the painted skin coming or
-- going (Kit:Cover / Kit:Uncover, the bus's 'cover'), the module on or not
-- (a listener at load: the skin's switch is followed with the module off too)
MelloUI:On("cover", function(group)
	if group == "unitframes" or group == "partyframes" then
		NameBand.All()
	end
	if group == "partyframes" then
		Party.Due()
	end
end, "Unit Frames: name bands and party levels")

--------------------------------------------------------------------------------
-- The frames' parts (one-look D5: from the Unit Frames Kit, which fills in
-- its painted pieces through M:SetSkinHooks)
--   M:RingOf(portrait) -> the kit's ring round it while the skin is on, else
--       nil (HealerFrames' debuff glow hugs its rim: Kit:RingRim)
--   M:PartsOf(frame) -> portrait, health, mana, name, circle, number: a
--       portrait-and-bars frame's parts -- the player frame's, a party
--       member's (the game's pool, or a stand-in built like one:
--       ConfigPreview's MakeParty, Group Frames' solo frame) -- read from the
--       game's own keys; the level badge's circle and number the player
--       frame's, a party member's the painted skin's (none without it: its
--       level on the name line stands clear of the frame effects); nil for
--       any other frame. MelloUI.FrameFX splits such a frame's effects
--       (FX.Split: a round form on the ring, the square one on the bars)
--   M:CoverOf(frame, portrait, circle, number) -> ring, orb, disc, number:
--       what stands over a frame effect there (Core/FrameFX.lua draws copies
--       of them over its light -- the user, 2026-10-09: "dont cut anything,
--       just place the effect under"): the portrait's ring (the kit's, else
--       the game's frame art, its ring drawn in it) and the level badge's
--       orb (the kit's, else the game's circle), its disc and its number
--   M:DressStandIn(frame) a party stand-in (ours, the game's member frame's
--       keys and geometry) dressed as a member: its level and band, and the
--       painted skin's dressing while that is on
--   M:ReminderAnchor() -> region, side, reach, far | nil: where the Reminder
--       widget (Core/Reminders.lua) hangs (user, 2026-09-26: "left of the
--       player ring", Above and Right as options, its own mover when the
--       player frame is hidden)
--     region  the kit's portrait ring while the skin dresses the frames (a
--             texture whose rect is the ring's whole outline), else the
--             game's own portrait (PlayerFrame.PlayerFrameContainer.PlayerPortrait)
--     side    the ring's free side, away from the bars and the name: "LEFT"
--     reach   how far the frame's art stands past `region`'s edges, in UI
--             units of region's scale: 0 on the kit ring, 4 on the game's
--             portrait (its own ring round it), 13 there while the game's
--             PvP badge shows (its circle over the ring's left rim); add it
--             to the gap. Read at each call (ask again at each raise)
--     far     the frame's other end, for the "Right" place: the health
--             bar's kit bracket while it is on, else the game's health bar;
--             nil when there is none
--   nil while the player frame is hidden: the widget takes its own mover
--   then. The kit coming or going is told on the bus's 'cover' (area
--   "unitframes"): anchor again then. Reads no size and makes nothing (no
--   garbage per call).
--------------------------------------------------------------------------------

local REACH = { ring = 4, badge = 13 }   -- the game's ring round its 60 px portrait / its PvP badge circle, past the portrait

-- the player frame's health bar, or the kit's bracket on it while shown
local function FarEnd(main)
	local bars = main and main.HealthBarsContainer
	local health = bars and bars.HealthBar or nil
	local strip = health and Skin.FarEnd and Skin.FarEnd(health)
	return strip or health
end

function M:RingOf(portrait)
	if not (portrait and Skin.RingOf) then
		return nil
	end
	return Skin.RingOf(portrait)
end

function M:PartsOf(frame)
	if type(frame) ~= "table" then
		return nil
	end
	if frame == PlayerFrame then
		local c = frame.PlayerFrameContainer
		local content = frame.PlayerFrameContent
		local main = content and content.PlayerFrameContentMain
		local bars = main and main.HealthBarsContainer
		local area = main and main.ManaBarArea
		return c and c.PlayerPortrait, bars and bars.HealthBar, area and area.ManaBar, PlayerName,
			main and main.LevelBackgroundCircle, _G.PlayerLevelText
	end
	-- (a party member's shape: no other frame has these three -- the compact
	-- and Group Frames' buttons no portrait, the pets and target of target no
	-- health bar container)
	local bars = rawget(frame, "HealthBarContainer")
	local health = type(bars) == "table" and rawget(bars, "HealthBar") or nil
	local portrait, mana = rawget(frame, "Portrait"), rawget(frame, "ManaBar")
	if not (portrait and health and mana) then
		return nil
	end
	-- (0.21.3: the painted level circle and number -- the frame effects laid
	-- under them as under the player's: the user's screenshot of 2026-10-13)
	local circle, number
	if Skin.PartyCircle then
		local ok, c, n = pcall(Skin.PartyCircle, frame)
		if ok then
			circle, number = c, n
		end
	end
	return portrait, health, mana, rawget(frame, "Name"), circle, number
end

function M:CoverOf(frame, portrait, circle, number)
	if type(frame) ~= "table" then
		return nil
	end
	local ring = self:RingOf(portrait)
	if not ring then
		local c = rawget(frame, "PlayerFrameContainer")
		ring = (type(c) == "table" and rawget(c, "FrameTexture")) or rawget(frame, "Texture")
	end
	local orb, disc = circle, nil
	if circle and Skin.OrbOf then
		local o, d = Skin.OrbOf(circle, number)
		if o then
			orb, disc = o, d
		end
	end
	return ring, orb, disc, number
end

function M:DressStandIn(frame)
	if type(frame) ~= "table" then
		return
	end
	if Party.Wanted() then
		Party.Make(frame)
	end
	Party.Update(frame)
	-- (a stand-in of Group Frames' may be a secure button of its own: its
	-- name's box out of combat)
	if InCombatLockdown() then
		Party.Due()
	else
		Party.Width(frame)
	end
	local made = Party.of[frame]
	if made and made.entry then
		NameBand.Sync(made.entry)
	end
	if Skin.DressStandIn then
		Skin.DressStandIn(frame)
	end
end

function M:ReminderAnchor()
	local pf = PlayerFrame
	if not pf then
		return nil
	end
	-- (a secret or refused answer counts as shown)
	local ok, shown = pcall(pf.IsShown, pf)
	if ok and not Secret(shown) and not shown then
		return nil
	end
	local content = pf.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	local tex = Skin.PlayerRing and Skin.PlayerRing()
	if tex then
		return tex, "LEFT", 0, FarEnd(main)
	end
	local container = pf.PlayerFrameContainer
	local portrait = container and container.PlayerPortrait
	if not portrait then
		return nil
	end
	-- the game's PvP badge over the ring's left rim: the widget clears it
	-- (a secret or refused answer: the ring's reach)
	local reach = REACH.ring
	local badge = main and main.PvpBackgroundCircle
	if badge then
		local okB, on = pcall(badge.IsShown, badge)
		if okB and not Secret(on) and on then
			reach = REACH.badge
		end
	end
	return portrait, "LEFT", reach, FarEnd(main)
end

--------------------------------------------------------------------------------
-- Level Up (0.21.3; the user, 2026-10-13: "Yes to all" to BuildData/output/
-- animation_previews, 5. Level up; one-look D5: the Unit Frames module's,
-- following Unit Frame Tweaks): a light runs along the game's XP bar (its
-- rect only: nothing of the bar's written), and NOTICE_AT seconds in the
-- notice says the level and, with the Quest List, the quests it opened in the
-- player's zone (its NewQuestsAt; their givers pop on the map there). While
-- the painted skin dresses the frames, the player frame's level badge also
-- turns over to the new level with a ring of light (MelloUI.FrameFX:
-- FX.LevelRoll on the badge's copy, its "level" landings: it needs the kit's
-- orb disc). The motion not under Reduce Motion; the notice always while the
-- option is on. Its event (PLAYER_LEVEL_UP) only while the option is on.
--------------------------------------------------------------------------------

local Level = { NOTICE_AT = 0.8, ORB_SPILL = { 70, 70 }, BAR_SPILL = { 8, 12 }, new = nil }

function Level.Notice()
	local new = Level.new
	if not new then
		return
	end
	local text = "Level " .. new
	local ql = MelloUI:GetModule("QuestList")
	if ql and ql.isEnabled and type(ql.NewQuestsAt) == "function" then
		local ok, n = pcall(ql.NewQuestsAt, ql, new)
		n = ok and Num(n) or nil
		if n and n > 0 then
			text = text .. " \194\183 " .. n .. (n == 1 and " new quest nearby" or " new quests nearby")
		end
	end
	MelloUI:Announce(text)
end

function Level.Up(new)
	new = Num(new)
	if not (new and M.isEnabled and M.db and M.db.levelUp ~= false) then
		return
	end
	Level.new = new
	local FX, anim = MelloUI.FrameFX, MelloUI.Anim
	local motion = FX and anim and not anim.reduceMotion
	if motion then
		-- (the badge's roll needs the painted skin's orb and disc)
		local sp = Covered() and FX.Split and FX.Split(PlayerFrame)
		if sp then
			FX.LevelRoll(sp, new - 1, new)
			local badge = sp.orb or sp.disc
			if badge then
				FX.ShowOn(badge, "level", "orb", Level.ORB_SPILL)
			end
		end
		local bar = rawget(_G, "MainStatusTrackingBarContainer")
		if bar and bar:IsVisible() then
			FX.ShowOn(bar, "level", "bar", Level.BAR_SPILL)
		end
	end
	Perf.C_Timer.After(motion and Level.NOTICE_AT or 0, Level.Notice)
end

Level.OnEvent = Shared("OnEvent of Level Up", function(_, _, level)
	Level.Up(level)
end, "event")

-- its event while the option is on (and the module)
function Level.Listen()
	local on = M.isEnabled and M.db ~= nil and M.db.levelUp ~= false
	if not (on or Level.frame) then
		return
	end
	if not Level.frame then
		Level.frame = CreateFrame("Frame")
		Perf.SetScript(Level.frame, "OnEvent", Level.OnEvent)
	end
	if on then
		Level.frame:RegisterEvent("PLAYER_LEVEL_UP")
	else
		Level.frame:UnregisterAllEvents()
	end
end
M.Level = Level   -- (the tests)

--------------------------------------------------------------------------------
-- XP Gain (0.22.1; the user, 2026-10-14: "build all 5" to BuildData/output/animation_previews_2, 1. XP bar): the
-- stretch of the game's XP bar just gained lights up while a light runs along it to the new end (MelloUI.FrameFX, its
-- "xp" landing, on that stretch's rect: FX.ShowAt). Nothing of the game's bar is written or held back -- its fill
-- moves as it always has. Not a level gained (Level Up's), a bar not shown, XP that reads secret; not under Reduce
-- Motion. (One-look D5: the Unit Frames module's, following Unit Frame Tweaks.)
--------------------------------------------------------------------------------

local XP = { SPILL = { 16, 8 }, MIN_W = 4, ROWS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" },
	EXPERIENCE = 4, PREVIEW = 0.08, at = nil, max = nil }

-- the game's XP bar shown now (the main or the second status bar row's Experience bar): its StatusBar
function XP.Bar()
	local info = rawget(_G, "StatusTrackingBarInfo")
	local index = info and info.BarsEnum and info.BarsEnum.Experience or XP.EXPERIENCE
	for _, name in ipairs(XP.ROWS) do
		local row = rawget(_G, name)
		local bar = type(row) == "table" and type(row.bars) == "table" and row.bars[index]
		local sb = type(bar) == "table" and bar.StatusBar
		if sb and sb:IsVisible() then
			return sb
		end
	end
	return nil
end

-- the player's XP and the level's (nil: secret, none)
function XP.Read()
	local okX, x = pcall(UnitXP, "player")
	local okM, m = pcall(UnitXPMax, "player")
	x, m = okX and Num(x) or nil, okM and Num(m) or nil
	if x and m and m > 0 then
		return x, m
	end
	return nil
end

-- the light from `old` to `now` (of `max`) on the bar
function XP.Play(old, now, max)
	local FX = MelloUI.FrameFX
	local sb = XP.Bar()
	if not (FX and FX.ShowAt and sb) or MelloUI.Anim.reduceMotion then
		return
	end
	local l, b, r, t = FX.Rect(sb)
	if not l then
		return
	end
	local w = r - l
	local x1 = l + w * math.min(1, now / max)
	local x0 = math.min(l + w * math.max(0, old / max), x1 - XP.MIN_W)
	FX.ShowAt(math.max(l, x0), b, x1, t, "xp", "gain", XP.SPILL)
end

function XP.Update()
	local old, oldMax = XP.at, XP.max
	local now, max = XP.Read()
	XP.at, XP.max = now, max
	if now and old and max == oldMax and now > old and M.isEnabled and M.db and M.db.xpGain ~= false then
		XP.Play(old, now, max)
	end
end

XP.OnEvent = Perf.Shared("OnEvent of XP Gain", function(_, event, unit)
	if event == "PLAYER_ENTERING_WORLD" then
		XP.at, XP.max = XP.Read()
	elseif unit == "player" then
		XP.Update()
	end
end, "event")

-- its events while the option is on (and the module)
function XP.Listen()
	local on = M.isEnabled and M.db ~= nil and M.db.xpGain ~= false
	if not (on or XP.frame) then
		return
	end
	if not XP.frame then
		XP.frame = CreateFrame("Frame")
		Perf.SetScript(XP.frame, "OnEvent", XP.OnEvent)
	end
	if on then
		XP.frame:RegisterEvent("PLAYER_XP_UPDATE")
		XP.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
		XP.at, XP.max = XP.Read()
	else
		XP.frame:UnregisterAllEvents()
		XP.at, XP.max = nil, nil
	end
end
M.XP = XP   -- (the tests)

-- (/mello player level) the level-up played on the level you have, to see it
-- (the badge turning from the one before; the notice and the quests as at a
-- level gained)
M.SlashWords = {
	level = function()
		local lv = Num(UnitLevel("player"))
		if not (lv and M.isEnabled and M.db and M.db.levelUp ~= false) then
			MelloUI:Print("Unit Frames: Level Up is off (Unit Frames > Frame > Look), or Unit Frame Tweaks are.")
			return
		end
		Level.Up(lv)
	end,
	-- (/mello player xp, 0.22.1) XP Gain's light on the bar as for a gain of PREVIEW of the level
	xp = function()
		local now, max = XP.Read()
		if not (now and M.isEnabled and M.db and M.db.xpGain ~= false and XP.Bar()) then
			MelloUI:Print("Unit Frames: XP Gain is off (Unit Frames > Frame > Look), Unit Frame Tweaks are, or no experience bar shows.")
			return
		end
		XP.Play(math.max(0, now - max * XP.PREVIEW), math.max(now, max * XP.PREVIEW), max)
	end,
}

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

local function ApplyAll()
	OutOfCombat(function()
		ApplyNames()
		ApplyReputationColor()
		ApplyGlows()
		ApplyFrameAlpha()
	end)
	M:HoldStatusGlows()   -- textures: at once, in combat too
end

-- (one-look D5) the names' bands and the party's levels as the module is now:
-- made out of combat on the switch-on, shown or hidden at once
local function ApplyParts()
	if M.isEnabled then
		OutOfCombat(NameBand.Frames)
	end
	NameBand.All()
	Party.Due()
	Party.Listen()
end

function M:OnInit(db)
	self.db = db
end

local coverWatched = false

-- switched on after the login's PLAYER_ENTERING_WORLD (Core's start-up pass
-- over the login's first frames): that event as it came, to XP Gain's and
-- the names' covers' frames
function M:OnLoginWorld(...)
	MelloUI:ReplayWorld(XP.frame, ...)
	MelloUI:ReplayWorld(Compact.frame, ...)
end

function M:OnEnable(db)
	self.db = db
	InstallHooks()
	InstallNameHooks()
	RefreshNames(db.nameFormat or "both")
	if not coverWatched and MelloUI.Kit then
		coverWatched = true
		MelloUI.Kit:OnCover(function(group, covered)
			if group == "unitframes" and not covered and M.isEnabled then
				ApplyNames()
				ApplyFrameAlpha()   -- (after the skin's Unfade, which left the art at 1)
			end
		end)
		-- (the party's members as the game makes them: a post-hook, the
		-- pool's members swept out of combat -- their levels made on a
		-- member's first show)
		local pf = PartyFrame
		if pf and type(pf.InitializePartyMemberFrames) == "function" then
			hooksecurefunc(pf, "InitializePartyMemberFrames", Party.Due)
		end
	end
	ApplyAll()
	ApplyParts()
	Level.Listen()
	XP.Listen()
end

function M:OnDisable()
	RefreshNames("both")   -- the game's full names back (first: the covers' release never waits on the rest)
	Level.Listen()
	XP.Listen()
	ApplyParts()
	ApplyAll()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "nameFormat" then
		RefreshNames(value or "both")
		return
	elseif key == "levelUp" then
		Level.Listen()
		return
	elseif key == "xpGain" then
		XP.Listen()
		return
	end
	ApplyAll()
end
