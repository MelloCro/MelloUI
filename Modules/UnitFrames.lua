--------------------------------------------------------------------------------
-- MelloUI - Unit Frames
--
-- Layout tweaks for the player, target and focus frames:
--   * names centred above the health bar
--   * transparent name band (the reaction coloured strip behind target names)
--   * no red combat flash / status glow around the frames
--   * adjustable frame art opacity
--   * the player frame (and the pet frame with it) faded out of combat
--     while nothing needs it (0.14.0, off by default; below)
--
-- Combined with Dark Mode, Bar Textures (class / reaction health colour) and
-- Bar Text this gives the flat "RougeUI" look.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("UnitFrames")
local hooksecurefunc = Perf.hooksecurefunc
local Shared = Perf.Shared or function(_, fn) return fn end
local C_Timer = Perf.C_Timer

local M = MelloUI:RegisterModule("UnitFrames", {
	title = "Unit Frames",
	desc = "Centred names, transparent name band, no combat flash and frame art opacity for player, target and focus. The player frame can fade out of combat.",
	icon = "Interface\\Icons\\INV_Misc_GroupLooking",
	flavour = "Player, target and focus, centred and calm. Frame art at the opacity you choose.",
	group = "Frames and bars", navOrder = 1,
	role = "replaces",
	tweak = { label = "Unit Frame Tweaks", desc = "Name and glow tweaks on the unit frames (they step aside where the reskin covers them), and the player frame faded out of combat.", order = 5 },
	defaults = {
		centerNames = true,
		nameFormat = "both",   -- set by UI Modifications' "Show Names As" (one setting for every name)
		hideReputationColor = true,
		hideCombatGlow = true,
		hideStatusGlow = true,
		frameAlpha = 1,
		fadeOutOfCombat = false,
		fadeAlpha = 0,
		fadePet = true,
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
		  desc = "Hide the glow around the player portrait and name that shows resting (yellow) and combat (red)." },
		{ type = "header", name = "Frame Art" },
		{ type = "slider", key = "frameAlpha", name = "Frame Art Opacity", min = 0.1, max = 1, step = 0.05, percent = true,
		  desc = "Opacity of the frame art around the bars and portraits. The bars themselves stay solid." },
		{ type = "header", name = "Out Of Combat" },
		{ type = "toggle", key = "fadeOutOfCombat", name = "Fade Out Of Combat", new = "0.14.0",
		  desc = "Your player frame fades away while nothing needs it. It comes back in combat, with a target, while your health or mana is below full, when you are dead, when you point at where it sits, and while the windows are unlocked or Edit Mode is open." },
		{ type = "slider", key = "fadeAlpha", parent = "fadeOutOfCombat", name = "Faded Opacity", new = "0.14.0", min = 0, max = 0.5, step = 0.05, percent = true,
		  desc = "How much of the frame stays while it is faded. At 0 % it is gone until it is needed." },
		{ type = "toggle", key = "fadePet", parent = "fadeOutOfCombat", name = "Pet Frame Too", new = "0.14.0",
		  desc = "Your pet's frame fades and comes back with the player frame, and also comes back while your pet is hurt. Off: the pet frame always stays." },
	},
})

--------------------------------------------------------------------------------
-- The name's form (user, 2026-09-22): after the game has set a frame's name
-- (UnitFrame_Update for the player, target, focus, pet and target-of-target
-- frames; CompactUnitFrame_UpdateName for the party and raid frames), the
-- text is set again in the chosen form. Nameplates are the Nameplates
-- module's (their compact frames are skipped here). Post-hooks only.
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

local function ApplyNameFormat(frame, unit, mode)
	local text = MelloUI:UnitNameAs(unit, mode)
	if text ~= nil then
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

local function OnCompactName(frame)
	local mode = NameMode()
	if mode and frame and frame.name and frame.unit and not IsNamePlateFrame(frame) then
		ApplyNameFormat(frame, frame.unit, mode)
	end
end

local nameHooked = false
local function InstallNameHooks()
	if nameHooked then
		return
	end
	nameHooked = true
	if type(UnitFrame_Update) == "function" then
		hooksecurefunc("UnitFrame_Update", OnUnitFrameUpdate)
	end
	if type(CompactUnitFrame_UpdateName) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateName", OnCompactName)
	end
end

-- Every frame again in the given form (a setting changed, the module
-- off): the known unit frames and the compact party / raid members, the
-- text set directly, no game code run.
local function RefreshNames(mode)
	local frames = { PlayerFrame, TargetFrame, FocusFrame, PetFrame, TargetFrameToT, FocusFrameToT }
	for i = 1, 5 do
		frames[#frames + 1] = _G["CompactPartyFrameMember" .. i]
	end
	for i = 1, 40 do
		frames[#frames + 1] = _G["CompactRaidFrame" .. i]
	end
	for g = 1, 8 do
		for i = 1, 5 do
			frames[#frames + 1] = _G["CompactRaidGroup" .. g .. "Member" .. i]
		end
	end
	for _, frame in ipairs(frames) do
		if frame and frame.name and frame.unit then
			local text = MelloUI:UnitNameAs(frame.overrideName or frame.unit, mode)
			if text ~= nil then
				pcall(frame.name.SetText, frame.name, text)
			end
		end
	end
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
	originalNameLayout[fs] = {
		point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y,
		width = fs:GetWidth(), justify = fs:GetJustifyH(),
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
	if saved.width and saved.width > 0 then
		fs:SetWidth(saved.width)
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

local function ApplyGlows()
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

local function ApplyFrameAlpha()
	local alpha = M.isEnabled and (tonumber(M.db.frameAlpha) or 1) or 1
	for _, tex in ipairs(FrameArtTextures()) do
		if tex and tex.SetAlpha then
			tex:SetAlpha(alpha)
		end
	end
end

--------------------------------------------------------------------------------
-- Fade Out Of Combat (0.14.0; a player's wish on 0.13.7, "hide the player /
-- pet frame out of combat", put in by the user 2026-09-26). While nothing
-- needs them, the player frame -- and the pet frame with it -- fade to
-- Faded Opacity (0 by default: gone). They come back while any of these
-- holds, and stay:
--   * combat (PLAYER_REGEN_DISABLED: back at once, never faded in a fight)
--   * a target
--   * the player's health below full
--   * mana below full while the power bar shows mana (the drink after a
--     fight); rage, energy and the rest never count, they rest empty or full
--     (a health or mana this client hands over secret -- the health always,
--     out of combat too -- is never compared: a change of it heard lately
--     stands for "below full", FADE_RECENT below)
--   * dead or a ghost
--   * the pointer on the frame (or on the pet's, while it follows)
--   * the windows unlocked for placing (Unlock the Windows), Edit Mode open
-- The pet frame follows the player frame (shown while it is) and comes back
-- for its own health too; Pet Frame Too off leaves it alone.
-- Out slowly after a short hold (FADE_HOLD, then FADE_OUT), in fast
-- (FADE_IN), through MelloUI.Anim (Reduce Motion: at once); a frame not seen
-- (a pet not summoned) takes its alpha at once, so a pet summoned while the
-- frames are faded appears faded. Only the frames' OWN alpha is set, allowed
-- in a fight (they are secure unit buttons: never shown, hidden or moved
-- here). The pet frame is the player frame's child: while the fade is on it
-- ignores its parent's alpha (set out of combat; its old setting put back
-- after), so its own rule decides and never the player's times its own.
-- The player's cast bar the same: Edit Mode's lock to the player frame makes
-- it the frame's child (PlayerFrame_AttachCastBar), and a cast out of combat
-- shows in full. The rest under the frame fades with it (the class
-- resources and totems, the game's; the kit's dressing and the UI shade).
-- Who else sets an alpha there sets it on the frames' regions (Frame Art
-- Opacity above, Dark Mode's colours, the kit's faded pictures, the UI
-- shade's partners): that multiplies with this and is never touched.
-- Nothing else in MelloUI sets these two frames' own alpha, nor does the
-- game's unit frame code (its vehicle and Edit Mode code moves and
-- re-dresses them; its alpha writes are on a status texture, the party and
-- compact frames); the fade writes the alpha only when its answer changes
-- and never answers a write (no loop).
-- The UI shade (Modules/KitShade.lua, area "unitframes") is drawn on the
-- player's container and on the pet frame's own shade frame: it fades with
-- them. The Reminder widget (Core/Reminders.lua) is UIParent's, only
-- anchored to the portrait: it stays whole.
-- Nothing is made, hooked or registered while the option is off: the event
-- frame, its events and the bus listeners come with the first switch on;
-- the events and listeners go with the switch or the module off, the
-- frames' alpha back to 1 at once; the pointer hooks (post-hooks, which
-- cannot be taken off) are inert then. No ticker, no OnUpdate: the hold is a
-- timer (looked at again only while the pointer rests on a bar or button of
-- the frame after the frame heard it leave: none of the frame's own leaves
-- comes when it goes), the end of a secret health's or mana's window is one
-- more (one pending at most), the fades are Anim's.
--   M.fadeState   the state (read only; the tests')
--------------------------------------------------------------------------------

local FADE_IN, FADE_OUT, FADE_HOLD = 0.2, 0.6, 1.5
-- A secret health or mana (user, 2026-09-26, RC5: "The Fade of Unitframes is
-- not working" -- issecretvalue(UnitHealth("player")) true out of combat;
-- the game's API documentation: UnitHealth SecretReturns, always; UnitPower
-- secret for every power type not flagged never-secret) is never compared.
-- The game's own events answer instead: each change of the health fires
-- UNIT_HEALTH, of the mana UNIT_POWER_UPDATE (what its own bars redraw on);
-- while it fills out of combat the regen ticks every 2 s (a drink or food
-- adds its own ticks), at full they stop. So a change within FADE_RECENT --
-- one tick's 2 s and a half-second margin for the server's and the frame's
-- lag -- is "below full"; after the last tick the frame waits FADE_RECENT,
-- then the hold, then fades (it goes 4 s after the last change).
-- FADE_CAST: a spell's mana cost stops the mana's regen for five seconds,
-- then the next 2-s tick comes (up to 7 s with no event): a cost (a cast and
-- a power event within FADE_PAIR of each other) keeps the mana's window open
-- that long, with the same margin.
local FADE_RECENT, FADE_CAST, FADE_PAIR = 2.5, 7.5, 0.5
local FADE_MAX = 0.5                           -- Faded Opacity's top
local FADE_OWNER = "UnitFrames: fade"          -- the bus owner
local OWN_ALPHA_KEY = "UnitFrames: the pet frame's and cast bar's own alpha"   -- (Kit:WhenOutOfCombat's keys)
local HOOK_KEY = "UnitFrames: the fade's pointer hooks"
local FADE_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "PLAYER_DEAD",
	"PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD" }
local HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
local POWER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_SPELLCAST_SUCCEEDED" }
local Secret = MelloUI.Safe.IsSecret
local Finite = MelloUI.Safe.Finite

-- on: the fade runs; pet: the pet frame follows; mana: the power bar shows
-- mana (its events registered); combat, editMode: as told; holding, holdDue:
-- the hold; lost: a frame heard the pointer leave while it is still over
-- it (on a bar or button of the frame's own, which takes the pointer: no
-- leave of the frame comes when it goes, so the hold looks again);
-- state[frame] = "shown" / "faded" (nil: not touched); kept[frame]: the pet
-- frame's and the cast bar's own ignore-parent-alpha before the fade (nil:
-- not set); hpUntil, manaUntil, petUntil: the GetTime a secret health's /
-- mana's / pet health's "below full" window ends; manaAt, castAt: the last
-- power event and cast (FADE_PAIR); armed: the windows' timer pending
local Fade = { on = false, pet = false, mana = false, combat = false, editMode = false, holding = false,
	holdDue = 0, lost = false, state = {}, kept = {}, events = nil, hooked = false,
	hpUntil = 0, manaUntil = 0, petUntil = 0, manaAt = -math.huge, castAt = -math.huge, armed = false }
M.fadeState = Fade

local function FadeWanted()
	local db = M.isEnabled and M.db
	return db and db.fadeOutOfCombat == true or false
end

local function FadedAlpha()
	local a = Finite(tonumber(M.db and M.db.fadeAlpha)) or 0
	return a < 0 and 0 or a > FADE_MAX and FADE_MAX or a
end

-- a yes / no question about a unit (a target, dead, a pet, in a fight). A
-- secret answer is no: none of these is ever secret by the game's API
-- documentation, and as yes it would hold the frame for good (nothing asks
-- again until the next event -- the RC5 bug); a fight still shows it
-- (PLAYER_REGEN_DISABLED, InCombatLockdown)
local function Yes(fn, unit)
	if type(fn) ~= "function" then
		return false
	end
	local ok, v = pcall(fn, unit)
	if not ok or Secret(v) then
		return false
	end
	return v and true or false
end

local RecentTimer   -- (below)

-- a secret value's window (hpUntil ...) still open: not full; the one timer
-- armed to look again when it ends, FADE_RECENT ahead at most. One pending
-- at most (C_Timer.After cannot be taken back), and every window opened
-- after the arm runs FADE_RECENT or more from its event: none ends before
-- the armed look, whichever window still counts by then. (Review of the RC5
-- fix: armed for a cost's whole 7.5 s, a druid gone to cat form -- the mana
-- no longer counts -- whose health's window, opened after, ended first got
-- no look of its own: the fade came 5 s late.) A cost's long window just
-- gets two or three looks.
local function Open(untilAt)
	local now = GetTime()
	if now >= untilAt then
		return false
	end
	if not Fade.armed then
		Fade.armed = true
		local wait = untilAt - now
		C_Timer.After(wait < FADE_RECENT and wait or FADE_RECENT, RecentTimer)
	end
	return true
end

-- cur below max (health, or power of `kind`). A secret or refused answer is
-- never compared: its window answers (`untilAt`, a change heard lately)
local function Below(curFn, maxFn, unit, kind, untilAt)
	if type(curFn) ~= "function" or type(maxFn) ~= "function" then
		return false
	end
	local okC, cur = pcall(curFn, unit, kind)
	local okM, max = pcall(maxFn, unit, kind)
	if not (okC and okM) or Secret(cur) or Secret(max) then
		return Open(untilAt)
	end
	cur, max = tonumber(cur), tonumber(max)
	if not (cur and max) or max <= 0 then
		return false
	end
	return cur < max
end

local function ManaType()
	local types = type(Enum) == "table" and Enum.PowerType
	return type(types) == "table" and Finite(types.Mana) or 0
end

-- the player's power bar shows mana (a secret answer: not known, not held)
local function OnMana()
	local fn = _G.UnitPowerType
	if type(fn) ~= "function" then
		return false
	end
	local ok, kind = pcall(fn, "player")
	if not ok or Secret(kind) then
		return false
	end
	return kind == ManaType()
end

-- the pointer on the frame, on screen (a secret answer: not). IsMouseOver
-- asks only the frame's rectangle, shown or not: the hidden pet frame of a
-- character with no pet, under the player frame, never counts
local function Over(frame)
	if not frame then
		return false
	end
	local okV, shown = pcall(frame.IsVisible, frame)
	if not okV or Secret(shown) or not shown then
		return false
	end
	local ok, over = pcall(frame.IsMouseOver, frame)
	return ok and not Secret(over) and over and true or false
end

local function Hovered()
	return Over(PlayerFrame) or (Fade.pet and Over(PetFrame))
end

-- the player frame is needed now (the cheap and likely answers first: a
-- fight's health and power events end at the first test)
local function PlayerNeeded()
	if Fade.combat or InCombatLockdown() then
		return true
	end
	if Yes(UnitExists, "target") or Yes(_G.UnitIsDeadOrGhost, "player") then
		return true
	end
	if Below(UnitHealth, UnitHealthMax, "player", nil, Fade.hpUntil) then
		return true
	end
	if Fade.mana and Below(UnitPower, _G.UnitPowerMax, "player", ManaType(), Fade.manaUntil) then
		return true
	end
	if Fade.editMode or Hovered() then
		return true
	end
	return MelloUI:WindowsUnlocked() and true or false
end

local function PetNeeded()
	return Yes(UnitExists, "pet") and Below(UnitHealth, UnitHealthMax, "pet", nil, Fade.petUntil)
end

-- seen: a secret answer counts as seen (the move is only a tween)
local function Seen(frame)
	local ok, seen = pcall(frame.IsVisible, frame)
	if ok and Secret(seen) then
		return true
	end
	return ok and seen and true or false
end

-- the frame to `alpha` through Anim, at once where it is not seen
local function FadeTo(frame, alpha, duration)
	if Seen(frame) then
		MelloUI.Anim:To(frame, "alpha", alpha, duration, duration == FADE_IN and "outQuad" or "inOutQuad")
	else
		MelloUI.Anim:Stop(frame, "alpha")
		frame:SetAlpha(alpha)
	end
end

local function Bring(frame)
	if frame and Fade.state[frame] ~= "shown" then
		Fade.state[frame] = "shown"
		FadeTo(frame, 1, FADE_IN)
	end
end

local function Dim(frame)
	if frame and Fade.state[frame] ~= "faded" then
		Fade.state[frame] = "faded"
		FadeTo(frame, FadedAlpha(), FADE_OUT)
	end
end

-- a frame touched by the fade back to 1 at once, and let go
local function Release(frame)
	if frame and Fade.state[frame] ~= nil then
		Fade.state[frame] = nil
		MelloUI.Anim:Stop(frame, "alpha")
		frame:SetAlpha(1)
	end
end

local HoldTimer   -- (below)

-- the hold, from now (one shared function for every timer: one that finds
-- a later due time leaves it to the later one)
local function Hold()
	Fade.holding = true
	Fade.holdDue = GetTime() + FADE_HOLD
	C_Timer.After(FADE_HOLD, HoldTimer)
end

-- The answer now: a frame needed comes back at once; one no longer needed
-- waits for the hold (settle: the hold is over, it fades now). A reason
-- back ends the hold; the pointer still over a frame that heard it leave
-- keeps one running, to look again (Fade.lost).
local function Evaluate(settle)
	if not Fade.on then
		return
	end
	local player = PlayerNeeded()
	local wait = false
	if player then
		Bring(PlayerFrame)
	elseif PlayerFrame and Fade.state[PlayerFrame] ~= "faded" then
		if settle then
			Dim(PlayerFrame)
		else
			wait = true
		end
	end
	if Fade.pet then
		if player or PetNeeded() then
			Bring(PetFrame)
		elseif PetFrame and Fade.state[PetFrame] ~= "faded" then
			if settle then
				Dim(PetFrame)
			else
				wait = true
			end
		end
	end
	if wait or (Fade.lost and Hovered()) then
		if not Fade.holding then
			Hold()
		end
	else
		Fade.holding = false
	end
end

HoldTimer = Shared("the fade's hold: the unit frames", function()
	if not (Fade.on and Fade.holding) or GetTime() + 0.05 < Fade.holdDue then
		return
	end
	Fade.holding = false
	Evaluate(true)
end)

-- a secret value's window ran out, or the armed look came (a window still
-- open: Evaluate arms again); then the hold, then the fade
RecentTimer = Shared("the fade's secret health / mana window: the unit frames", function()
	Fade.armed = false
	Evaluate()
end)

-- the mana's window open until `t` at least (a cost's window runs longer)
local function ManaUntil(t)
	if t > Fade.manaUntil then
		Fade.manaUntil = t
	end
end

-- a change heard: its window opened from now. False: nothing for the fade to
-- look at (a cast only widens the mana's window; the pet's health while Pet
-- Frame Too is off; another power of the player's, a combo point or a rune).
-- A max's change (UNIT_MAXHEALTH, UNIT_MAXPOWER) opens none: it says nothing
-- of the value (a higher max: the regen's own ticks follow)
local function Stamp(event, unit, kind)
	local now = GetTime()
	if event == "UNIT_HEALTH" then
		if not Secret(unit) and unit == "pet" then
			if not Fade.pet then
				return false
			end
			Fade.petUntil = now + FADE_RECENT
		else
			Fade.hpUntil = now + FADE_RECENT
		end
	elseif event == "UNIT_POWER_UPDATE" then
		if not Secret(kind) and kind ~= nil and kind ~= "MANA" then
			return false
		end
		Fade.manaAt = now
		ManaUntil(now + FADE_RECENT)
		if now - Fade.castAt <= FADE_PAIR then
			ManaUntil(Fade.castAt + FADE_CAST)
		end
	else   -- UNIT_SPELLCAST_SUCCEEDED
		Fade.castAt = now
		if now - Fade.manaAt <= FADE_PAIR then
			ManaUntil(now + FADE_CAST)
		end
		return false
	end
	return true
end

-- the values not known yet (switched on, the world entered, a fight over,
-- back alive): the windows of a frame not faded open for FADE_RECENT, so it
-- stays until the regen's first tick has had its time (no fade and straight
-- back); a faded frame is left faded (a tick brings it when it is needed)
local function Seed()
	local t = GetTime() + FADE_RECENT
	if Fade.state[PlayerFrame] ~= "faded" then
		if t > Fade.hpUntil then
			Fade.hpUntil = t
		end
		ManaUntil(t)
	end
	if Fade.state[PetFrame] ~= "faded" and t > Fade.petUntil then
		Fade.petUntil = t
	end
end

-- a frame under the player frame that keeps its own alpha while the fade is
-- on: it ignores its parent's (its own old setting back after)
local function OwnAlpha(frame)
	if not (frame and frame.SetIgnoreParentAlpha) then
		return
	end
	if Fade.on then
		if Fade.kept[frame] == nil then
			local ok, was = pcall(frame.IsIgnoringParentAlpha, frame)
			Fade.kept[frame] = (ok and not Secret(was) and was) and true or false
		end
		frame:SetIgnoreParentAlpha(true)
	elseif Fade.kept[frame] ~= nil then
		frame:SetIgnoreParentAlpha(Fade.kept[frame])
		Fade.kept[frame] = nil
	end
end

-- the pet frame (its own rule) and the player's cast bar (a cast in full);
-- out of combat (the pet frame is a secure unit button)
local function OwnAlphaNow()
	OwnAlpha(PetFrame)
	OwnAlpha(_G.PlayerCastingBarFrame)
end

local function SyncOwnAlpha()
	MelloUI.Kit:WhenOutOfCombat(OwnAlphaNow, OWN_ALPHA_KEY)
end

-- the health events for the player (and the pet while it follows); the
-- power events only while the power bar shows mana
local function RegisterUnits()
	local f = Fade.events
	for i = 1, #HEALTH_EVENTS do
		if Fade.pet then
			f:RegisterUnitEvent(HEALTH_EVENTS[i], "player", "pet")
		else
			f:RegisterUnitEvent(HEALTH_EVENTS[i], "player")
		end
	end
	Fade.mana = OnMana()
	for i = 1, #POWER_EVENTS do
		if Fade.mana then
			f:RegisterUnitEvent(POWER_EVENTS[i], "player")
		else
			f:UnregisterEvent(POWER_EVENTS[i])
		end
	end
end

local Fade_OnEvent = function(_, event, unit, kind)
	if not Fade.on then
		return
	end
	if event == "UNIT_HEALTH" or event == "UNIT_POWER_UPDATE" or event == "UNIT_SPELLCAST_SUCCEEDED" then
		if not Stamp(event, unit, kind) then
			return
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		Fade.combat = true
	elseif event == "PLAYER_REGEN_ENABLED" then
		Fade.combat = false
		Seed()
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- (a loading screen: no fight goes on through one)
		Fade.combat = InCombatLockdown() or Yes(_G.UnitAffectingCombat, "player")
		Seed()
	elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
		Seed()
	elseif event == "UNIT_DISPLAYPOWER" then
		RegisterUnits()
	elseif event == "UNIT_MAXHEALTH" and not Fade.pet and not Secret(unit) and unit == "pet" then
		return
	end
	Evaluate()
end

-- the pointer on the frames (and their bars, which take it from the frame)
local Fade_OnEnter = Shared("OnEnter on the player / pet frame: the fade", function()
	if Fade.on then
		Fade.lost = false
		Evaluate()
	end
end, "script")
local Fade_OnLeave = Shared("OnLeave on the player / pet frame: the fade", function()
	if Fade.on then
		Fade.lost = true
		Fade.holding = false   -- (the hold from this leave)
		Evaluate()
	end
end, "script")

local function HookPointer()
	if Fade.hooked then
		return
	end
	Fade.hooked = true
	local main = PlayerFrame and PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
	local bars = main and main.HealthBarsContainer
	local mana = main and main.ManaBarArea
	local list = { PlayerFrame, bars and bars.HealthBar, mana and mana.ManaBar, PetFrame, _G.PetFrameHealthBar, _G.PetFrameManaBar }
	for i = 1, 6 do
		local f = list[i]
		if type(f) == "table" and f.HookScript then
			Perf.HookScript(f, "OnEnter", Fade_OnEnter)
			Perf.HookScript(f, "OnLeave", Fade_OnLeave)
		end
	end
end

-- the bus: the windows unlocked, Edit Mode
local Fade_OnSetting = Shared("'setting' on the bus: the unit frames' fade", function(name, key)
	if name == "UIModifications" and key == "unlock" then
		Evaluate()
	end
end)
local Fade_OnEditMode = Shared("'editmode' on the bus: the unit frames' fade", function(entering)
	Fade.editMode = entering and true or false
	Evaluate()
end)

local function FadeOn()
	Fade.on = true
	Fade.pet = M.db.fadePet ~= false
	if not Fade.events then
		local f = CreateFrame("Frame")
		Perf.SetScript(f, "OnEvent", Fade_OnEvent)
		Fade.events = f
	end
	local f = Fade.events
	for i = 1, #FADE_EVENTS do
		f:RegisterEvent(FADE_EVENTS[i])
	end
	f:RegisterUnitEvent("UNIT_PET", "player")
	f:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
	RegisterUnits()
	MelloUI:On("setting", Fade_OnSetting, FADE_OWNER)
	MelloUI:On("editmode", Fade_OnEditMode, FADE_OWNER)
	-- (the frames are secure unit buttons: hooked out of combat)
	MelloUI.Kit:WhenOutOfCombat(HookPointer, HOOK_KEY)
	Fade.combat = InCombatLockdown() or Yes(_G.UnitAffectingCombat, "player")
	Fade.editMode = MelloUI.EditModeOpen and MelloUI.EditModeOpen() or false
	Fade.holding, Fade.lost = false, false
	Seed()
	SyncOwnAlpha()
	Evaluate()
end

local function FadeOff()
	if not Fade.on then
		return
	end
	Fade.on = false
	Fade.holding = false
	Fade.events:UnregisterAllEvents()
	MelloUI:Off(FADE_OWNER)
	Release(PlayerFrame)
	Release(PetFrame)
	SyncOwnAlpha()
end

local function Refade(frame)
	if frame and Fade.state[frame] == "faded" then
		FadeTo(frame, FadedAlpha(), FADE_IN)
	end
end

-- the option, the module or a fade setting changed: on, off or followed
local function FadeSync()
	if not FadeWanted() then
		FadeOff()
		return
	end
	if not Fade.on then
		FadeOn()
		return
	end
	local pet = M.db.fadePet ~= false
	if pet ~= Fade.pet then
		Fade.pet = pet
		if not pet then
			Release(PetFrame)   -- (left alone from now: the game's alpha, 1)
		end
		RegisterUnits()
	end
	-- a new Faded Opacity on the frames faded now
	Refade(PlayerFrame)
	Refade(PetFrame)
	Evaluate()
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

function M:OnInit(db)
	self.db = db
end

local coverWatched = false

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
		end)
	end
	ApplyAll()
	FadeSync()
end

function M:OnDisable()
	ApplyAll()
	RefreshNames("both")   -- the game's full names back
	FadeSync()             -- (off: the frames' alpha back to 1, the events gone)
end

-- the fade's own settings (Fade Out Of Combat and the rows under it)
local FADE_KEYS = { fadeOutOfCombat = true, fadeAlpha = true, fadePet = true }

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "nameFormat" then
		RefreshNames(value or "both")
		return
	end
	if FADE_KEYS[key] then
		FadeSync()
		return
	end
	ApplyAll()
end
