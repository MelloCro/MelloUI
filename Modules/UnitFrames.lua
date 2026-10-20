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
--     party's names, Level Up and XP Gain (Tweaks' since one look C13b), the frames' parts for the frame
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
	desc = "Centred names, a clear name band and no combat flash for player, target and focus; the party's levels and the names' soft bands.",
	icon = "Interface\\Icons\\INV_Misc_GroupLooking",
	flavour = "Player, target and focus, centred and calm.",
	group = "Frames and bars", navOrder = 1,
	role = "replaces",
	tweak = { label = "Unit Frame Tweaks", desc = "Name and glow tweaks on the unit frames, the party's levels and the names' soft bands (they step aside where the reskin covers them).", order = 5 },
	-- (one look C13, the user's yes to the audit's drops, 2026-10-15: the names
	-- centred and the target's and focus's name band transparent while this
	-- module is on, the frame art at its full opacity -- MelloUI's choices,
	-- no rows; Core.lua's MERGES drops the old keys)
	defaults = {
		nameFormat = "both",   -- set by UI Modifications' "Show Names As" (one setting for every name)
		hideCombatGlow = true,
		hideStatusGlow = true,
		hidePvPBadge = true,
		nameFont = "shared",
		frames = true,
	},
	options = {
		-- (2026-10-20, the user: the game's frames as they are, in the set's borders, one picture each; the Frames section)
		{ type = "toggle", key = "frames", name = "MelloUI Frames", new = "0.25.0",
		  desc = "The player, target, focus, target of target, pet and party frames in MelloUI's look, exactly as the game lays them out: a gold ring round the portrait, a dark level badge, and gold-lined iron borders round the name, health and power; the elite's and boss's golden dragon and the rare's silver one round the target. Off: the game's own frame art. The painted skin's frames keep their own (Oldschool)." },
		{ type = "header", name = "Names" },
		{ type = "dropdown", key = "nameFont", name = "Name Font", values = MelloUI.FontFaces, new = "0.25.0",
		  desc = "The face of the names on the player, target, focus and pet frames, their targets' and the party portraits' (their level follows). Shared: the Interface text's face (Look > Fonts)." },
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
		-- (one-look D5: the two below moved from the Unit Frames Kit, keys and
		-- rows kept -- Core.lua's MERGES carries a saved "off"; no header row
		-- of their own: in the schema they sit under Frame Art, on the page
		-- each has its one row, Core/ConfigLayout.lua)
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
	local on = M.isEnabled
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
	local hide = M.isEnabled
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
					if M.isEnabled then
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
			if M.isEnabled and PlayerName then
				OutOfCombat(function()
					if M.isEnabled and PlayerName then
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
-- their reaction strip backs the name. Shown while the module is on, the
-- painted skin does not dress the frame (its own band then, UnitFramePanel's
-- NameShade) and Text Shade is on (Look > General > Text, the one switch of
-- the shade behind MelloUI's text -- the user, 2026-10-16: "i switched it
-- off, but the shade behind the names is still here"). Made out of combat:
-- the player's, pet's and targets' targets' at the module's switch-on, a
-- party member's with its level.
--------------------------------------------------------------------------------

-- Each band inside its name's plate (the user, 2026-10-16: "make sure that
-- the shade ... does not leave its designated place": the player's ran 8 past
-- its plate's right end): its middle the name's box grown by its kind's pads,
-- its soft ends (feather) and its whole height (the texture fades over it) on
-- the plate's border at most. The plates measured on client 70425's art (c60,
-- 2x), in the frame's units: the player's 87-212 x -26.5..-46.75 (its name
-- 116 x 12 centred on 149, -37), the pet's and targets' targets' 46-116.5 x
-- -3.5..-18.5 (their names 68 x 10 at 44, -6 and 44, -5), a party member's
-- 47-116.5 x -5.5..-20.5 (its name from 46, -7, 12 high, on to its level at
-- 101); the left ends under the portrait's ring.
local NameBand = { of = setmetatable({}, { __mode = "k" }),
	LOOK = { colour = "innerPanel", feather = 8, layer = "BACKGROUND", sublevel = -8 },
	PADS = { player = { x = -5, y = 3.5 }, pet = { x = -3.5, y = 2.5 }, tot = { x = -3.5, y = 1.5 },
		party = { x = 4, y = 1.5 } } }

-- Text Shade (Tweaks' textShade, Notice.lua's reader: on unless switched off)
function NameBand.TextShade()
	local look = MelloUI.CentreLook
	return not look or look.Setting("textShade") and true or false
end

function NameBand.Sync(entry)
	local want = (M.isEnabled and entry.shown and not Covered(entry.group) and NameBand.TextShade()) and true or false
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
-- line's other end: a party member's level) or the name's own box, by `pad`
-- (NameBand.PADS: its frame kind's); `group` the skin's cover group it steps
-- aside for
function NameBand.Make(fs, host, group, right, pad)
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
	pad = pad or NameBand.PADS.player
	if right then
		band:Anchor(fs, right, pad.x, pad.y)
	else
		band:Anchor(fs, pad.x, pad.y)
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
		NameBand.Make(PlayerName, container, nil, nil, NameBand.PADS.player)
	end
	local pet = PetFrame
	if pet then
		NameBand.Make(_G.PetName or pet.name, pet, nil, nil, NameBand.PADS.pet)
	end
	for _, frame in ipairs(TargetLikeFrames()) do
		local tot = frame and frame.totFrame
		if tot and tot.Name then
			NameBand.Make(tot.Name, tot, nil, nil, NameBand.PADS.tot)
		end
	end
end

-- (the configurator's frame sample, Core/ConfigPreview.lua's copies of the
-- game's frames: the same band behind its name, made once per name -- no
-- hooks, the sample shows and hides it -- and whether the frames show theirs;
-- `kind` the copy's frame, NameBand.PADS: "player", "pet")
function M:PreviewNameBand(fs, host, kind)
	local Soft = MelloUI.Shade
	if type(fs) ~= "table" or type(host) ~= "table" or not (Soft and Soft.Band and Soft.TEXT) then
		return nil
	end
	NameBand.LOOK.alpha = Soft.TEXT.alpha
	local band = Soft:Band(host, NameBand.LOOK)
	if band then
		local pad = NameBand.PADS[kind] or NameBand.PADS.player
		band:Anchor(fs, pad.x, pad.y)
	end
	return band
end

function M:NameBandShows()
	return (self.isEnabled and not Covered("unitframes") and NameBand.TextShade()) and true or false
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
-- box 19 shorter so the two never meet, a two-digit level 3 px clear of a long
-- name (57 -> 38 on client 70338, 55 -> 36 on 70425; the user's screenshot,
-- 2026-10-16: "Fellaria24" at 15), set again after the game sets its own (UpdateNameTextAnchors, which
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
	SHORTER = 19, X = 101, Y = -12, H = 12, KEY = "Unit Frames: party levels",
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

-- The party frames in the game's own sharp art (the user, 2026-10-16: "the Party Frames Borders are still very low
-- resolution even on 100% size, make them the same as we have on the Player Unitframe"). The member frame's own art
-- (UI-HUD-UnitFrame-Party-PortraitOn) is 1x; client 70425 has the party frame in the player frame's style at 2x --
-- its "Character" art (UI-HUD-UnitFrame-CharacterFrameOnParty-PortraitOn), which no game setting switches on. Laid
-- as the game's own PartyMemberFrameMixin:ToCharacterStyleArt lays it -- the frame art, the combat flash and status
-- glow (ArtLayoutInfo.Character's offsets), the player's portrait mask -- but the bars in the art's own holes as
-- measured on it (Party.HOLES: the game's unused Character numbers put them 2 px high and 3 px wide, and its health
-- mask names an atlas the client has not -- the user's screenshot, 2026-10-16: "the HP and mana bar, they are
-- misaligned"), each bar's mask its own rect (nothing cut, nothing past the hole); the bars' fills stay as the game
-- and Bar Textures have them.
-- While wanted (the module on, the painted skin not dressing the party), a member in its player art (never the
-- vehicle's), out of combat; laid again after the game lays its art again (ToPlayerArt: a post-hook, the sweep
-- out of combat); the game's own layout (ArtLayoutInfo.Player) back when no longer wanted. Kept per member here
-- (Party.art), nothing written as a key on the game's frames. A preview's stand-in (ours) the same
Party.art = setmetatable({}, { __mode = "k" })
-- the art's holes, from the frame's top left (the art at the game's 1, -2): measured on client 70425's art
-- (ui-hud-unitframe-characterframeonparty-portraiton-c60-2x, 240 x 98 px for its 120 x 49): the health hole's inner
-- edges 92-227 x 38-54 px, the mana hole's 92-227 x 61-70 px; the portrait's ring hole 13-77 x 14-77 px (its centre
-- 23.5, -24.5 on the frame): the game's portrait (37 at 7, -6, its centre 2 px right of it) on it at 5, -6 (the user,
-- 2026-10-16: "that gap on the left side"), at 7, -6 again in the game's own art
Party.HOLES = { health = { x = 47, y = -21, w = 68, h = 8.5 }, mana = { x = 47, y = -32.5, w = 68, h = 5 },
	portrait = { x = 5, y = -6 }, gamePortrait = { x = 7, y = -6 } }
Party.ART = {
	Character = { frame = "UI-HUD-UnitFrame-CharacterFrameOnParty-PortraitOn",
		flash = "UI-HUD-UnitFrame-CharacterFrameOnParty-PortraitOn-InCombat",
		status = "UI-HUD-UnitFrame-CharacterFrameOnParty-PortraitOn-Status", portrait = "UI-HUD-UnitFrame-Player-Portrait-Mask" },
	Player = { frame = "UI-HUD-UnitFrame-Party-PortraitOn", flash = "ui-hud-unitframe-party-portraiton-incombat",
		status = "ui-hud-unitframe-party-portraiton-status", portrait = "CircleMask",
		health = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask", mana = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Mana-Mask" },
}

-- the game's layout of a style (its own table; nil on a client without it)
function Party.Layout(style)
	local mixin = rawget(_G, "PartyMemberFrameMixin")
	local info = type(mixin) == "table" and type(mixin.ArtLayoutInfo) == "table" and mixin.ArtLayoutInfo[style]
	if type(info) == "table" and type(info.Health) == "table" and type(info.Mana) == "table" then
		return info
	end
	return nil
end

-- a member laid in a style: `style` "Character" (the sharp art) or "Player" (the game's own) -- out of combat
function Party.Lay(frame, style)
	local L, A = Party.Layout(style), Party.ART[style]
	local tex, hc, mana = rawget(frame, "Texture"), rawget(frame, "HealthBarContainer"), rawget(frame, "ManaBar")
	if not (L and A and type(tex) == "table" and type(hc) == "table" and type(mana) == "table") then
		return false
	end
	local own = style == "Player"   -- (the game's own sizes: its atlases' -- its ToPlayerArt)
	tex:SetAtlas(A.frame, true)
	local flash = rawget(frame, "Flash")
	if type(flash) == "table" and L.Flash then
		flash:SetAtlas(A.flash, true)
		flash:SetPoint("TOPLEFT", frame, "TOPLEFT", L.Flash.OffsetX, L.Flash.OffsetY)
	end
	local overlay = rawget(frame, "PartyMemberOverlay")
	local status = type(overlay) == "table" and rawget(overlay, "Status")
	if type(status) == "table" and L.Status then
		status:SetAtlas(A.status, true)
		status:SetPoint("TOPLEFT", frame, "TOPLEFT", L.Status.OffsetX, L.Status.OffsetY)
	end
	local pm = rawget(frame, "PortraitMask")
	if type(pm) == "table" then
		pm:SetAtlas(A.portrait)
	end
	-- (the portrait on the art's ring: its mask follows it, anchored on it)
	local portrait = rawget(frame, "Portrait")
	if type(portrait) == "table" then
		local at = own and Party.HOLES.gamePortrait or Party.HOLES.portrait
		portrait:ClearAllPoints()
		portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", at.x, at.y)
	end
	local bar = rawget(hc, "HealthBar")
	local hm, mm = rawget(hc, "HealthBarMask"), rawget(mana, "ManaBarMask")
	-- (the fills its masks dress: the health bar's, its max-health-loss bar's, the mana bar's)
	local fills = {}
	for _, b in ipairs({ bar, rawget(hc, "TempMaxHealthLoss"), mana }) do
		if type(b) == "table" and type(b.GetStatusBarTexture) == "function" then
			fills[#fills + 1] = b:GetStatusBarTexture()
		end
	end
	for _, t in ipairs(fills) do
		MelloUI.Widgets.SoftEndsOwn(t, not own)
	end
	if own then
		-- (the game's own: its template's 70 x 10 bar and 74 x 7 mana bar, its masks at its offsets)
		local H, P = L.Health, L.Mana
		if type(bar) == "table" then
			bar:SetSize(H.Width, H.Height)
		end
		hc:SetSize(H.Width, H.Height)
		hc:SetPoint("TOPLEFT", frame, "TOPLEFT", H.OffsetX, H.OffsetY)
		if type(hm) == "table" then
			hm:SetAtlas(A.health, true)
			hm:ClearAllPoints()
			hm:SetPoint("TOPLEFT", H.OffsetXMask, H.OffsetYMask)
		end
		mana:SetSize(P.Width, 7)
		mana:SetPoint("TOPLEFT", frame, "TOPLEFT", P.OffsetX, P.OffsetY)
		if type(mm) == "table" then
			mm:SetAtlas(A.mana, true)
			mm:ClearAllPoints()
			mm:SetPoint("TOPLEFT", frame, "TOPLEFT", P.OffsetXMask, P.OffsetYMask)
		end
		return true
	end
	local HH, MH = Party.HOLES.health, Party.HOLES.mana
	if type(bar) == "table" then
		bar:SetSize(HH.w, HH.h)
	end
	hc:SetSize(HH.w, HH.h)
	hc:SetPoint("TOPLEFT", frame, "TOPLEFT", HH.x, HH.y)
	mana:SetSize(MH.w, MH.h)
	mana:SetPoint("TOPLEFT", frame, "TOPLEFT", MH.x, MH.y)
	-- (each mask the bar's own rect and every bar's soft ends -- W.SoftMask, the same mask as every bar's: the
	-- fill shows exactly in its hole, its edges dimmed, in the game's own mask slot)
	for _, pair in ipairs({ { hm, type(bar) == "table" and bar or hc }, { mm, mana } }) do
		local mask, over = pair[1], pair[2]
		if type(mask) == "table" then
			MelloUI.Widgets.SoftMask(mask, over)
		end
	end
	return true
end

-- a member's art as wanted now (out of combat): the sharp art on a member in its player art, the game's back else
function Party.Art(frame)
	local want = Party.Wanted() and rawget(frame, "state") ~= "vehicle" and not rawget(_G, "UNIT_FRAME_SHOW_HEALTH_ONLY")
		and Party.Layout("Character") ~= nil and C_Texture and C_Texture.GetAtlasInfo
		and C_Texture.GetAtlasInfo(Party.ART.Character.frame) ~= nil
	-- (each lay told on the bus: Dark Mode shades the art again)
	if want then
		if not Party.art[frame] and Party.Lay(frame, "Character") then
			Party.art[frame] = true
			MelloUI:Fire("partyart", frame)
		end
	elseif Party.art[frame] then
		Party.art[frame] = nil
		if rawget(frame, "state") ~= "vehicle" then
			Party.Lay(frame, "Player")
			MelloUI:Fire("partyart", frame)
		end
	end
	-- (MelloUI Frames: its picture on the sharp art, the game's on its own; made below)
	if M.Frames then
		M.Frames.Party(frame)
	end
end

-- the game laid a member's art again (its ToPlayerArt): ours again, out of combat
Party.OnArt = Shared("ToPlayerArt on a party member: the sharp art again", function(frame)
	Party.art[frame] = nil
	Party.Due()
end)

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
	local P = NameBand.PADS.party
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

--------------------------------------------------------------------------------
-- The names' own face (one look C11, Q2: UnitFrames.nameFont, a face from
-- MelloUI.FontFaces): the player's, the pet's, the target's and the focus's,
-- their targets' (each cover copies it: NameCover's SetFont hook) and the
-- party portraits' (their level follows: Party.Font; a level Group Frames
-- moved, Party.Face). Only the face: a name keeps its size and flags -- its
-- font object's as the Fonts module has them, a party name Group Frames moved
-- its part's. Set on the setting change, on 'fonts' and as the party's members
-- are swept; never per update: the game sets a name's text, never its font
-- (ugf-audit.md section 12). Back to Shared: the face, size and flags of the
-- name's own font object (kept before its first face, in a weak table) as the
-- Fonts module has them now, a moved party name at its size -- by SetFont,
-- never SetFontObject, which would put the object's alpha and colour back on a
-- name MelloUI hides (a short name's cover, a part hidden in Group Frames);
-- a name once given a face follows 'fonts' from then on. The module off: every
-- name back. A picked face takes its own size correction (MelloUI:FaceSize);
-- the painted skin's bands measure the name again (Shade:SourceFont).
--------------------------------------------------------------------------------
-- (on the module: Unit Frames' main chunk takes no new local -- onelook/partylevel2 F11; the tests
-- reach it there too, onelook/partfont)
M.NameFace = {
	of = setmetatable({}, { __mode = "k" }),      -- [name] = the font object it had before a face
	sized = setmetatable({}, { __mode = "k" }),   -- [party member] = its name moved in Group Frames (M:PartyLine)
	KEY = "Unit Frames: the names' face",
}

-- a font's face, size and flags (nil for a secret or none)
function M.NameFace.Read(font)
	local ok, path, size, flags = pcall(font.GetFont, font)
	size = ok and Num(size) or nil
	if not (size and size > 0) or Secret(path) or type(path) ~= "string" then
		return nil
	end
	if Secret(flags) or type(flags) ~= "string" then
		flags = ""
	end
	return path, size, flags
end

-- one name in the face picked, or back to its own (`sized`: a party name
-- Group Frames moved -- its size is its part's)
function M.NameFace.Set(fs, sized)
	if type(fs) ~= "table" or type(fs.SetFont) ~= "function" then
		return
	end
	local face = M.isEnabled and M.db and MelloUI:FaceOf(M.db.nameFont) or nil
	local object = M.NameFace.of[fs]
	if not object then
		if not face then
			return   -- (never given a face: the game's own, untouched)
		end
		local ok, o = pcall(fs.GetFontObject, fs)
		object = ok and not Secret(o) and type(o) == "table" and o or rawget(_G, "GameFontNormalSmall")
		if type(object) ~= "table" then
			return
		end
		M.NameFace.of[fs] = object
	end
	-- (its object's face, size and flags as they are now: the Interface text's
	-- face and size and the Outline follow; a moved party name's own size)
	local path, size, flags = M.NameFace.Read(object)
	if sized then
		local _, own, ownFlags = M.NameFace.Read(fs)
		if own then
			size, flags = own, ownFlags
		end
	end
	if not (path and size) then
		return
	end
	if face then
		if not sized then
			size = MelloUI:FaceSize(size, face, path)
		end
		path = face
	end
	pcall(fs.SetFont, fs, path, size, flags)
	local Shade = MelloUI.Shade
	if Shade and Shade.SourceFont then
		Shade:SourceFont(fs)
	end
end

-- a level Group Frames moved: its name's face at its own size and flags
function Party.Face(frame, made)
	local name = rawget(frame, "Name")
	local face = type(name) == "table" and M.NameFace.Read(name)
	local _, size, flags = M.NameFace.Read(made.number)
	if face and size then
		pcall(made.number.SetFont, made.number, face, size, flags)
	end
end

-- every name as the setting is now (out of combat); 'fonts' followed once a
-- face was picked
function M.NameFace.All()
	local face = M.isEnabled and M.db and MelloUI:FaceOf(M.db.nameFont)
	if not face and next(M.NameFace.of) == nil then
		return
	end
	M.NameFace.Set(_G.PlayerName)
	local pet = PetFrame
	if pet then
		M.NameFace.Set(_G.PetName or pet.name)
	end
	for _, frame in ipairs(TargetLikeFrames()) do
		local main = frame and frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
		M.NameFace.Set(main and main.Name)
		local tot = frame and frame.totFrame
		M.NameFace.Set(tot and tot.Name)
	end
	for _, frame in ipairs(Party.Members()) do
		M.NameFace.Set(rawget(frame, "Name"), M.NameFace.sized[frame])
	end
	for frame, made in pairs(Party.of) do
		if made.moved then
			Party.Face(frame, made)
		else
			Party.Font(frame, made)
		end
	end
	if not M.NameFace.listening then
		M.NameFace.listening = true
		MelloUI:On("fonts", M.NameFace.Later, M.NameFace.KEY)
	end
end

function M.NameFace.Later()
	MelloUI.Kit:WhenOutOfCombat(M.NameFace.All, M.NameFace.KEY)
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
	made.entry = NameBand.Make(name, frame, "partyframes", number, NameBand.PADS.party)   -- (its band's entry)
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
		Party.Art(frame)
		if Party.Wanted() and not Party.of[frame] then
			local okS, shown = pcall(frame.IsShown, frame)
			if not okS or Secret(shown) or shown then
				Party.Make(frame)
			end
		end
	end
	-- (one look C11: a member's name in the names' face, before its level
	-- copies it)
	for _, frame in ipairs(Party.Members()) do
		M.NameFace.Set(rawget(frame, "Name"), M.NameFace.sized[frame])
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
	if type(frame.ToPlayerArt) == "function" then
		hooksecurefunc(frame, "ToPlayerArt", Party.OnArt)
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
	M.NameFace.sized[frame] = nameMoved and true or nil   -- (laid in the names' face by Group Frames)
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
-- (Text Shade switched, a profile loaded: the bands as it wants them)
MelloUI:On("setting", function(module, key)
	if module == "Tweaks" and key == "textShade" then
		NameBand.All()
	end
end, "Unit Frames: name bands and Text Shade")
MelloUI:On("restart", NameBand.All, "Unit Frames: name bands and Text Shade")

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
	-- (MelloUI Frames' badge over the game's circle, unseen under it: the badge is what stands over the light -- the
	-- user's screenshot of 2026-10-20, a heal's light over the level)
	local badge = circle and M.Frames and M.Frames.Over(circle)
	if badge then
		orb = badge
	end
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
		Party.Art(frame)
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


-- (/mello player level, /mello player xp) Level Up's and XP Gain's plays to
-- see them: Tweaks' (one look C13b: they moved there), these words their
-- doorway as before
M.SlashWords = {
	level = function()
		local T = MelloUI.modules.Tweaks
		if T and T.SlashLevel then
			T.SlashLevel()
		end
	end,
	xp = function()
		local T = MelloUI.modules.Tweaks
		if T and T.SlashXP then
			T.SlashXP()
		end
	end,
}

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

local function ApplyAll()
	OutOfCombat(function()
		ApplyNames()
		M.NameFace.All()
		ApplyReputationColor()
		ApplyGlows()
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
-- over the login's first frames): that event as it came, to the names'
-- covers' frame (XP Gain's: Tweaks', one look C13b)
function M:OnLoginWorld(...)
	MelloUI:ReplayWorld(Compact.frame, ...)
end

--------------------------------------------------------------------------------
-- MelloUI Frames (2026-10-20, the user: "look at how the original unitframe looks like, take the new art, recreate
-- it exactly how it looks like just with the new borders, make it a single texture and apply it ... you always
-- forget the Party Frames"). The frame pictures of the player, target, focus, their targets of target and the party
-- members, redrawn on the game's own layout in Batch 25's art (Tools/make_icons.py UF_FRAMES: one picture each, the
-- game's ring, slots and borders where the game has them), the level circles the set's badge, and the target's and
-- focus's elite, boss and rare dragons Batch 29's (UF_DRAGONS: round the ring as the game's curl round its own).
-- Each stands exactly where the game's picture stands -- its frame, draw layer and sublevel, its rect -- shown while
-- that one shows (post-hooks on its Show / Hide / SetShown: the vehicle's art, a battle pet's level) and the game's
-- unseen meanwhile (alpha, written once each way, never on a per-frame path). While MelloUI Frames is on and the
-- painted skin leaves the frames (Kit's cover "unitframes"); a party member's while its sharp art is laid (Party.Art).
--------------------------------------------------------------------------------
local Frames = {
	DIR = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\",
	-- [kind] = { file, the picture's share of its file across and down; `at`: its middle that far from the top left
	-- of the frame's own picture -- the ring's centre on it -- and that size, not on the game picture's rect }
	ART = {
		player = { "uf_frame_player", 396 / 512, 142 / 256 }, res = { "uf_frame_player_res", 396 / 512, 148 / 256 },
		target = { "uf_frame_target", 388 / 512, 136 / 256 }, small = { "uf_frame_small", 240 / 256, 98 / 128 },
		badge = { "uf_badge", 1, 1 },
		-- (the dragon round the target's ring: its art 256 texels for 128 units, the ring's centre 159.25 x 33.75 units
		-- into the target's picture, as on its 2x art, 318.5 x 67.5 px)
		elite = { "uf_boss_elite", 1, 1, at = { 159.25, -33.75, 128 } },
		boss = { "uf_boss_boss", 1, 1, at = { 159.25, -33.75, 128 } },
		rare = { "uf_boss_rare", 1, 1, at = { 159.25, -33.75, 128 } },
	},
	cover = setmetatable({}, { __mode = "k" }),    -- [the game's picture] = ours
	kind = setmetatable({}, { __mode = "k" }),     -- [the game's picture] = the kind it wears (false: none)
	shown = setmetatable({}, { __mode = "k" }),    -- [the game's picture] = whether ours shows (its alpha 0 then)
	dressed = setmetatable({}, { __mode = "k" }),  -- [ours] = the kind laid on it
	anchor = setmetatable({}, { __mode = "k" }),   -- [the game's picture] = the picture an `at` kind is laid from
	covered = false,
}

function Frames.On()
	return M.isEnabled and M.db and M.db.frames ~= false and not Frames.covered
end

local function Shown(region)
	local ok, shown = pcall(region.IsShown, region)
	return ok and not Secret(shown) and shown == true
end

-- the boss picture's kind by its atlas: the rare's silver, the boss's winged gold, the elite's gold
function Frames.BossKind(region)
	if type(region) ~= "table" then
		return false
	end
	local ok, atlas = pcall(region.GetAtlas, region)
	atlas = ok and not Secret(atlas) and type(atlas) == "string" and atlas:lower() or ""
	if atlas:find("silver", 1, true) or atlas:find("rare", 1, true) then
		return "rare"
	end
	return atlas:find("winged", 1, true) and "boss" or "elite"
end

-- a frame's pictures and the kind each wears
function Frames.Regions(frame)
	if frame == PlayerFrame then
		local c, content = rawget(frame, "PlayerFrameContainer"), rawget(frame, "PlayerFrameContent")
		local main = content and content.PlayerFrameContentMain
		return { { c and c.FrameTexture, "player" }, { c and c.AlternatePowerFrameTexture, "res" },
			{ main and main.LevelBackgroundCircle, "badge" } }
	end
	local c, content = rawget(frame, "TargetFrameContainer"), rawget(frame, "TargetFrameContent")
	if c then
		local main = content and content.TargetFrameContentMain
		return { { c.FrameTexture, "target" }, { main and main.LevelBackgroundCircle, "badge" },
			{ c.BossPortraitFrameTexture, Frames.BossKind(c.BossPortraitFrameTexture), c.FrameTexture } }
	end
	-- (the pet's -- PetFrameTexture, the target of target's art -- and a target of target's)
	return { { frame == rawget(_G, "PetFrame") and rawget(_G, "PetFrameTexture") or rawget(frame, "FrameTexture"), "small" } }
end

Frames.OnShown = Shared("Show / Hide on a frame picture MelloUI Frames stands on", function(region)
	Frames.Follow(region)
end)

-- whether a text of the frame's regions (...) is drawn on that layer and sublevel
function Frames.TextAt(layer, sub, ...)
	for i = 1, select("#", ...) do
		local r = select(i, ...)
		if r.GetObjectType and r:GetObjectType() == "FontString" then
			local l2, s2 = r:GetDrawLayer()
			if l2 == layer and (Num(s2) or 0) == sub then
				return true
			end
		end
	end
	return false
end

-- ours on a game picture: made once, in its frame at its layer and sublevel; its Show / Hide followed from then on
function Frames.Make(region)
	local okP, parent = pcall(region.GetParent, region)
	if not (okP and type(parent) == "table" and parent.CreateTexture) then
		return nil
	end
	local okL, layer, sub = pcall(region.GetDrawLayer, region)
	if not (okL and type(layer) == "string" and not Secret(layer)) then
		layer, sub = "BACKGROUND", 0
	end
	sub = Num(sub) or 0
	-- (a text of its frame on its very layer and sublevel -- the party member's name, the target's level -- stays
	-- over ours, as over the game's picture: ours a sublevel lower then; read once, as it is made)
	local okT, text = pcall(Frames.TextAt, layer, sub, parent:GetRegions())
	if okT and text then
		sub = math.max(-8, sub - 1)
	end
	local ours = parent:CreateTexture(nil, layer, nil, sub)
	ours:Hide()
	Frames.cover[region] = ours
	for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
		hooksecurefunc(region, method, Frames.OnShown)
	end
	return ours
end

-- its picture and place for a kind (laid again only when the kind changes)
function Frames.Dress(ours, region, kind)
	if Frames.dressed[ours] == kind then
		return
	end
	Frames.dressed[ours] = kind
	local art = Frames.ART[kind]
	ours:SetTexture(Frames.DIR .. art[1])
	ours:SetTexCoord(0, art[2], 0, art[3])
	ours:ClearAllPoints()
	local at, from = art.at, Frames.anchor[region]
	if at and from then
		ours:SetSize(at[3], at[3])
		ours:SetPoint("CENTER", from, "TOPLEFT", at[1], at[2])
	else
		ours:SetAllPoints(region)
	end
end

-- ours shown while wanted and the game's picture shows; the game's unseen meanwhile
function Frames.Follow(region)
	local kind = Frames.kind[region]
	local want = (kind and Frames.On() and Shown(region)) and true or false
	local ours = Frames.cover[region]
	if want and not ours then
		ours = Frames.Make(region)
		want = ours ~= nil
	end
	if ours then
		if want then
			Frames.Dress(ours, region, kind)
		end
		ours:SetShown(want)
	end
	if (Frames.shown[region] or false) ~= want then
		Frames.shown[region] = want
		region:SetAlpha(want and 0 or 1)
	end
end

function Frames.Set(region, kind, from)
	if type(region) == "table" and region.SetAlpha then
		Frames.kind[region] = kind or false
		Frames.anchor[region] = from
		Frames.Follow(region)
	end
end

-- ours on a game picture while it shows (the frame effects lay it over their light: M:CoverOf), else nil
function Frames.Over(region)
	return Frames.shown[region] and Frames.cover[region] or nil
end

function Frames.LayOne(frame)
	for _, pair in ipairs(Frames.Regions(frame)) do
		Frames.Set(pair[1], pair[2], pair[3])
	end
end

-- a party member's picture: ours while its sharp art is laid (Party.Art; the game's own art has another shape)
function Frames.Party(member)
	Frames.Set(rawget(member, "Texture"), Party.art[member] and "small" or false)
end

function Frames.Lay()
	for _, frame in ipairs({ PlayerFrame, TargetFrame, FocusFrame, rawget(_G, "TargetFrameToT"),
		rawget(_G, "FocusFrameToT"), rawget(_G, "PetFrame") }) do
		if type(frame) == "table" then
			Frames.LayOne(frame)
		end
	end
	for member in pairs(Party.art) do
		Frames.Party(member)
	end
end

-- (the target's and focus's boss picture: the game lays it as the unit's classification is read)
Frames.OnClassification = Shared("CheckClassification on the target / focus frame (MelloUI Frames' wing)", function(frame)
	if Frames.On() then
		Frames.LayOne(frame)
	end
end)

function Frames.Start()
	if not Frames.hooked then
		Frames.hooked = true
		for _, frame in ipairs({ TargetFrame, FocusFrame }) do
			if type(frame) == "table" and type(frame.CheckClassification) == "function" then
				hooksecurefunc(frame, "CheckClassification", Frames.OnClassification)
			end
		end
	end
	Frames.Lay()
end
M.Frames = Frames   -- (the tests, the dumps)

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
			end
			-- (MelloUI Frames give way to the painted skin's frames, and come back)
			if group == "unitframes" then
				Frames.covered = covered and true or false
				Frames.Lay()
			end
			-- (the painted skin takes the party or leaves it: the art as wanted then)
			if group == "partyframes" then
				Party.Due()
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
	-- (MelloUI Frames: the painted skin's cover as it stands now, then laid)
	local K = MelloUI.Kit
	Frames.covered = (type(K) == "table" and type(K.IsOn) == "function" and K:IsOn("unitframes")) and true or false
	Frames.Start()
end

function M:OnDisable()
	RefreshNames("both")   -- the game's full names back (first: the covers' release never waits on the rest)
	ApplyParts()
	ApplyAll()
	Frames.Lay()   -- (isEnabled is false: the game's art back)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "nameFormat" then
		RefreshNames(value or "both")
		return
	end
	if key == "frames" then
		Frames.Lay()
		return
	end
	ApplyAll()
end
