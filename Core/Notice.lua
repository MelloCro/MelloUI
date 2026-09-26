--------------------------------------------------------------------------------
-- MelloUI - Notice
--
-- One on-screen notice for all of MelloUI (user, 2026-09-25): the line in
-- the upper third of the screen that says a route was set or finished, a
-- service was remembered, a dungeon's quests were listed. It used to be the
-- Route module's own frame, which the Services bar and the Quest List
-- borrowed; it is Core's now, so it works with Route off.
--
--   MelloUI:Announce(text, kind[, mute])
--       kind: "track" (a new destination), "arrive", "learn", "fail",
--       "info" or "silent" (as info, never a sound); anything else is info.
--       mute: true leaves the sound out (a caller's own sound switch, Route's
--       Announce Sound). One line at a time: a new one replaces the one shown
--       and is held 4 s, then fades over 1.5 s (Anim: at once under Reduce
--       Motion). Its text colour is a palette colour per kind, its sound one
--       of Core's UI sounds per kind (PlayUISound, so Custom Sounds sees it).
--       No garbage per call beyond the caller's text.
--   MelloUI:AnnounceSounds(kind[, mute])
--       true when that call would play its sound now (a caller with a
--       sound of its own plays it only when not: one chime, not two).
--
-- The settings are Tweaks' rows beside Chat Notices (read when used, a
-- missing one as its default, so they hold with Tweaks off):
--   noticeOnScreen  On-screen Notices (on): off, nothing is shown or played
--   noticeToChat    Send To Chat Instead (off): the line goes to the chat
--                   through MelloUI:Notice (Chat Notices can mute it)
--   noticeOutline   Outlined Text (off): the text outlined; off, soft text
--   noticeSounds    Notice Sounds (on)
--   zoneTextShade   Zone Text Shade (on): the game's zone text in the same
--                   look (the "Zone text" section below)
--
-- The look: the text in the interface face at about 20 (MelloUI:StyleFont,
-- so Font Style and the size slider apply), not outlined, with a soft shadow,
-- over MelloUI.Shade's soft band (Core/Shade.lua) sized to the text by its
-- anchors. Its place: TOP of the screen, 180 below the top (just under the
-- Route arrow's default place), on MelloUI's one mover and position store
-- (key "notice"): Unlock the Windows shows a sample line there to drag, Reset
-- positions puts it back, and it is kept on the screen.
--
-- Nothing is made at login: the frame, the shade and the mover entry come
-- with the first notice (or the first unlock of the windows). Windows left
-- unlocked over a login get their sample line with the next unlock, or once
-- the first notice's hold is over. At load it takes three bus listeners only
-- ('setting', 'module', 'restart': the windows unlocked, its own settings
-- changed); whether the windows are unlocked is Core's mover's to say
-- (MelloUI:WindowsUnlocked). The zone text section below adds its hooks on
-- the game's zone text frames at load, and makes nothing until they show
-- (the game shows them at every login: see there).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Notice")
local C_Timer = Perf.C_Timer

local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Call = MelloUI.Safe.Call
local Anim = MelloUI.Anim

local OWNER = "Notice"
local KEY = "notice"            -- its place in the store
local HOLD, FADE = 4, 1.5       -- seconds held at full, then fading
local SIZE = 20                 -- the text's base size, in its font object's terms
local HEIGHT = 48               -- the frame's height (the mover's grab)
local PAD_X, PAD_Y = 10, 12     -- the shade's full part past the text
local FEATHER = 36              -- the shade's soft ends
local SHADE_ALPHA = 0.7
local SHADOW_ALPHA = 0.85
local MAX_TEXT = 1100           -- a longer line is cut ("...")
local MIN_WIDTH = 120
local GUESS_WIDTH = 400         -- a width that cannot be read (a secret text)
local PREVIEW = "Notices show here. Drag to move."

-- the text's palette colour and Core's UI sound, per kind. Only the two
-- brightest text colours: over snow or sand, under the shade, trim and
-- mutedText read at about 1.4 : 1, so learn and fail take the body text's
-- colour and are told apart by their sounds
local COLOUR = { track = "selectedTrim", arrive = "selectedTrim", learn = "text", fail = "text",
	info = "text", silent = "text" }
local SOUND = { track = "notice_track", arrive = "notice_arrive", learn = "notice_learn", fail = "notice_fail",
	info = "notice_learn" }

local DEFAULTS = { noticeOnScreen = true, noticeToChat = false, noticeOutline = false, noticeSounds = true,
	zoneTextShade = true }

-- a setting of the notice (Tweaks' db, as MelloUI:Notice reads Chat Notices)
local function Setting(key)
	local db = MelloUI.db
	local modules = db and db.modules
	local tweaks = type(modules) == "table" and modules.Tweaks or nil
	local v
	if type(tweaks) == "table" then
		v = tweaks[key]
	end
	if v == nil then
		return DEFAULTS[key]
	end
	return v and true or false
end

-- shown on the screen at all (on, and not sent to the chat)
local function OnScreen()
	return Setting("noticeOnScreen") and not Setting("noticeToChat")
end

-- the sample line wanted: the windows unlocked (Core's mover says so) and
-- the notice shown on the screen
local function WantPreview()
	return MelloUI:WindowsUnlocked() and OnScreen()
end

local frame, text, font   -- made with the first notice (frame.shade: its band)
local state = { holds = 0, kind = "info", preview = false, entry = nil }

-- where it stands with no place saved: top centre, under the Route arrow
local function Home(f)
	f:ClearAllPoints()
	f:SetPoint("TOP", UIParent, "TOP", 0, -180)
end

-- the saved place (kept on the screen), else the default; left alone while
-- it is being dragged
local function Place()
	local entry = state.entry
	if entry and entry.moving then
		return
	end
	if not MelloUI:RestorePosition(KEY, frame) then
		Home(frame)
		MelloUI:FitOnScreen(frame)
	end
end

-- the text's colour (its kind's) and its shadow, from the palette as it is now
local function Paint()
	if not text then
		return
	end
	local palette = MelloUI.Palette
	local c = palette[COLOUR[state.kind] or "text"] or palette.text
	text:SetTextColor(c[1], c[2], c[3], 1)
	local s = palette.innerPanel
	text:SetShadowColor(s[1], s[2], s[3], SHADOW_ALPHA)
end

-- the font: the interface face at SIZE, outlined only with Outlined Text
local function Style()
	if text and font and MelloUI.StyleFont then
		MelloUI:StyleFont(text, "fontText", font, SIZE, "", Setting("noticeOutline"))
	end
end

-- the frame as wide as its text and shade (the mover's grab, the keep-on-
-- screen); the shade follows the text by its anchors, needing none of this
local function Measure()
	if not text then
		return
	end
	text:SetWidth(0)
	local w = Num(Call(text, "GetUnboundedStringWidth")) or Num(Call(text, "GetStringWidth"))
	if w and w > MAX_TEXT then
		text:SetWidth(MAX_TEXT)
		w = MAX_TEXT
	end
	w = (w or GUESS_WIDTH) + 2 * (PAD_X + FEATHER)
	frame:SetWidth(w > MIN_WIDTH and w or MIN_WIDTH)
end

local function Restyle()
	Style()
	Measure()
end

local function Build()
	if frame then
		return frame
	end
	frame = CreateFrame("Frame", "MelloUINotice", UIParent)
	frame:SetSize(MIN_WIDTH, HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:Hide()
	text = frame:CreateFontString(nil, "OVERLAY")
	frame.text = text
	font = _G.GameFont_Gigantic or _G.NumberFont_Outline_Huge or _G.GameFontNormalHuge3 or _G.GameFontNormalHuge
	if font then
		text:SetFontObject(font)
	end
	text:SetPoint("CENTER")
	text:SetJustifyH("CENTER")
	text:SetWordWrap(false)
	text:SetShadowOffset(1, -1)
	frame.shade = MelloUI.Shade:Band(frame, { colour = "innerPanel", alpha = SHADE_ALPHA, feather = FEATHER,
		layer = "BACKGROUND", region = text, padX = PAD_X, padY = PAD_Y })
	Style()
	Paint()
	Home(frame)
	MelloUI:On("palette", Paint, OWNER)
	MelloUI:On("fonts", Measure, OWNER)
	-- one mover entry: dragged while the windows are unlocked, its place in
	-- the store, put back on each show (it sets no script of its own)
	state.entry = MelloUI:RegisterMover(frame, frame, { key = KEY, anchor = "TOP", default = Home,
		min = 0.5, max = 2, base = 1 })
	return frame
end

-- a line on the frame, at full, in its kind's colour
local function Put(msg, kind)
	Build()
	text:SetText(msg)
	state.kind = kind
	Paint()
	Measure()
	Anim:Stop(frame, "alpha")   -- one fading out comes back
	frame:SetAlpha(1)
	Place()
	frame:Show()
end

-- the end of a hold: the last one fades what is shown then (while the
-- windows are unlocked the sample line comes back instead, to drag)
local function Fade()
	state.holds = state.holds - 1
	if state.holds > 0 or not (frame and frame:IsShown()) then
		return
	end
	-- asked again here: windows left unlocked over a login build nothing
	-- then, so the first real line is the first the notice hears of it
	state.preview = WantPreview()
	if state.preview then
		Put(PREVIEW, "info")
		return
	end
	Anim:FadeOut(frame, FADE, "linear")
end

local function HideNow()
	if frame then
		Anim:Stop(frame, "alpha")
		frame:Hide()
		frame:SetAlpha(1)
	end
end

-- the sample line while the windows are unlocked, so it can be dragged
local function Preview()
	local on = WantPreview()
	if on == state.preview then
		return
	end
	state.preview = on
	if on then
		Put(PREVIEW, "info")
	elseif frame and frame:IsShown() and state.holds <= 0 then
		Anim:FadeOut(frame, FADE, "linear")
	end
end

function MelloUI:Announce(msg, kind, mute)
	-- a secret text (a name the game protects) is asked about first: even
	-- comparing it with nil is refused; SetText and the chat take it as it is
	local secret = Secret(msg)
	if (not secret and msg == nil) or not Setting("noticeOnScreen") then
		return
	end
	if not secret and type(msg) ~= "string" then
		msg = tostring(msg)
	end
	if not COLOUR[kind] then
		kind = "info"
	end
	if Setting("noticeToChat") then
		self:Notice(msg)
	else
		Put(msg, kind)
		state.holds = state.holds + 1
		C_Timer.After(HOLD, Fade)
	end
	local sound = SOUND[kind]
	if sound and not mute and Setting("noticeSounds") then
		self:PlayUISound(sound)
	end
end

-- Whether MelloUI:Announce(text, kind, mute) would play a sound now: for a
-- caller with a click sound of its own, played only when the notice's is not
-- (one chime, not two; the Quest List's pins through Route)
function MelloUI:AnnounceSounds(kind, mute)
	return SOUND[COLOUR[kind] and kind or "info"] ~= nil and not mute and Setting("noticeOnScreen")
		and Setting("noticeSounds") or false
end

--------------------------------------------------------------------------------
-- Zone text (user, 2026-09-25: "that also needs to have the shading")
--
-- The game's zone change text takes the notice's look, so the two big texts
-- in the middle of the screen always look alike. Its four lines: the zone's
-- name (ZoneTextString), the PvP line under it (PVPInfoTextString), the
-- subzone's name (SubZoneTextString) and the PvP line under that
-- (PVPArenaTextString). Each line gets:
--   * the notice's soft band behind it (MelloUI.Shade: its colour, strength,
--     soft ends and side padding), one per line. A band lies on a frame of
--     ours made a child of the line's zone frame, so it takes the game's own
--     fade (FadingFrame's alpha) and hides with it; that frame draws in the
--     BACKGROUND strata, under both zone frames, so no band covers the other
--     frame's lines. It is anchored to its line (anchors only, no size read),
--     and while the look is on each line is as wide as its text (width 0:
--     the game's lines are 512 wide), so the band follows the text with no
--     code. A band shows only while its line has text. Its padding above and
--     below is about 0.4 of the line's text size: where two lines' bands
--     meet, their soft edges add up to about the strength of one, so the
--     stack reads as one shade.
--   * no outline unless the notice's Outlined Text is on (noticeOutline),
--     through MelloUI:StyleFont from the line's own font object: the game's
--     face and size, Font Style applying as it does to that object. The
--     shared font objects (ZoneTextFont, SubZoneTextFont, PVPInfoTextFont)
--     are never changed.
--   * the notice's soft text shadow.
-- The game keeps its colours (they tell friendly, hostile, contested,
-- sanctuary), its places, its sizes and its fading.
--
-- Setting: Tweaks zoneTextShade, Zone Text Shade (on), read when used like
-- the notice's. Off is the game's own look: the bands hidden, each line back
-- on its font object, with its colour, shadow and width.
--
-- Hooks only, never a script set on the game's frames: OnShow of
-- ZoneTextFrame and SubZoneTextFrame (the first show builds the bands), the
-- zone frame's OnEvent after the game's own handler (the lines' texts are
-- final then) and ZoneText_Clear. Nothing is made before the first zone text
-- shows (2 frames and 12 textures then), and nothing runs per frame.
-- The game shows the zone text at every login (its ZONE_CHANGED_NEW_AREA
-- then), so that first show, and the build, come with the login: once a
-- session, 2 frames, 4 bands of 3 textures, 4 font entries and one
-- 'palette' listener. This is the HUD's own text, and the HUD is dressed at
-- login (WINDOW-RULES 2f); left undressed there, the login's zone line would
-- show the game's heavy outline every time. No kit piece is made.
--------------------------------------------------------------------------------

local ZoneRefresh   -- the zone text's look again (its setting, the outline, a profile)

do
	local ZONE_OWNER = "Zone text"
	local ZONE_WIDTH = 512   -- the lines' width in the game's ZoneText.xml (1.60.1): given back with Off
	-- the lines, top to bottom: the string, its zone frame, the font object
	-- it inherits, the band's padding above and below
	local LINES = {
		{ name = "ZoneTextString", frame = "ZoneTextFrame", font = "ZoneTextFont", padY = 13 },
		{ name = "PVPInfoTextString", frame = "ZoneTextFrame", font = "PVPInfoTextFont", padY = 9 },
		{ name = "SubZoneTextString", frame = "SubZoneTextFrame", font = "SubZoneTextFont", padY = 10 },
		{ name = "PVPArenaTextString", frame = "SubZoneTextFrame", font = "PVPInfoTextFont", padY = 9 },
	}
	local zoneFrame, subFrame = _G.ZoneTextFrame, _G.SubZoneTextFrame
	local built, styled = false, false

	-- the line has text; a secret one is asked about first (even comparing it
	-- is refused) and counts as text
	local function HasText(fs)
		local t = fs:GetText()
		if Secret(t) then
			return true
		end
		return t ~= nil and t ~= ""
	end

	-- each band shown while the look is on and its line has text
	local function Bands()
		for i = 1, #LINES do
			local line = LINES[i]
			local band = line.band
			if band then
				local want = styled and HasText(line.fs) or false
				if band:IsShown() ~= want then
					band:SetShown(want)
				end
			end
		end
	end

	-- the soft shadow's colour, from the palette as it is now
	local function ZonePaint()
		if not styled then
			return
		end
		local s = MelloUI.Palette.innerPanel
		for i = 1, #LINES do
			local fs = LINES[i].fs
			if fs then
				fs:SetShadowColor(s[1], s[2], s[3], SHADOW_ALPHA)
			end
		end
	end

	-- a frame of ours under the zone frame's lines, fading with it
	local function Holder(parent)
		local h = CreateFrame("Frame", nil, parent)
		h:SetAllPoints(parent)
		h:SetFrameStrata("BACKGROUND")
		return h
	end

	local function ZoneBuild()
		built = true
		local holders = {}
		for i = 1, #LINES do
			local line = LINES[i]
			local fs, parent = _G[line.name], _G[line.frame]
			if type(fs) == "table" and type(parent) == "table" and type(fs.SetWidth) == "function" then
				local holder = holders[parent]
				if not holder then
					holder = Holder(parent)
					holders[parent] = holder
				end
				line.fs = fs
				line.band = MelloUI.Shade:Band(holder, { colour = "innerPanel", alpha = SHADE_ALPHA, feather = FEATHER,
					layer = "BACKGROUND", region = fs, padX = PAD_X, padY = line.padY })
				line.band:SetShown(false)
			end
		end
		MelloUI:On("palette", ZonePaint, ZONE_OWNER)
	end

	-- what the game gave a line, kept before it is first changed: its font
	-- object and its shadow (read secret-safe; a shadow that cannot be read
	-- is left to the font object). Its width is the XML's (ZONE_WIDTH): no
	-- size is read
	local function Keep(line, fs)
		if line.object ~= nil then
			return
		end
		local object = Call(fs, "GetFontObject")
		if type(object) ~= "table" then
			object = _G[line.font]
		end
		line.object = type(object) == "table" and object or false
		local r, g, b, a = Call(fs, "GetShadowColor")
		r, g, b, a = Num(r), Num(g), Num(b), Num(a)
		if r and g and b then
			line.shadow = { r, g, b, a or 1 }
		end
		local x, y = Call(fs, "GetShadowOffset")
		line.sx, line.sy = Num(x), Num(y)
	end

	-- the notice's look on every line (again: the outline may have changed)
	local function ZoneOn()
		local outline = Setting("noticeOutline")
		local s = MelloUI.Palette.innerPanel
		for i = 1, #LINES do
			local line = LINES[i]
			local fs = line.fs
			if fs then
				Keep(line, fs)
				fs:SetWidth(0)
				if line.object and MelloUI.StyleFont then
					MelloUI:StyleFont(fs, nil, line.object, nil, nil, outline)
				end
				fs:SetShadowOffset(1, -1)
				fs:SetShadowColor(s[1], s[2], s[3], SHADOW_ALPHA)
			end
		end
		styled = true
		Bands()
	end

	-- the game's own look again
	local function ZoneOff()
		styled = false
		for i = 1, #LINES do
			local line = LINES[i]
			local fs = line.fs
			if fs and line.object ~= nil then
				if MelloUI.StyleFont then
					MelloUI:StyleFont(fs)   -- out of Font Style's list
				end
				-- back on its font object; that puts the object's colour on
				-- the line too, and the line's own colour is the game's (its
				-- PvP status): kept across
				local r, g, b, a = Call(fs, "GetTextColor")
				r, g, b, a = Num(r), Num(g), Num(b), Num(a)
				if line.object then
					fs:SetFontObject(line.object)
				end
				if r and g and b then
					fs:SetTextColor(r, g, b, a or 1)
				end
				local sh = line.shadow
				if sh then
					fs:SetShadowColor(sh[1], sh[2], sh[3], sh[4])
				end
				if line.sx and line.sy then
					fs:SetShadowOffset(line.sx, line.sy)
				end
				fs:SetWidth(ZONE_WIDTH)
			end
		end
		Bands()
	end

	-- the look as the setting wants it; again = style it again while on
	local function Sync(again)
		if Setting("zoneTextShade") then
			if not built then
				ZoneBuild()
			end
			if again or not styled then
				ZoneOn()
			else
				Bands()
			end
		elseif styled then
			ZoneOff()
		end
	end

	-- a zone frame shown (FadingFrame_Show): the first one builds
	local function OnZoneShow()
		if MelloUI.initialized then
			Sync(false)
		end
	end

	-- the lines' texts changed (the game's handler has run, or cleared them)
	local function OnZoneTexts()
		if styled then
			Bands()
		end
	end

	local hooked = type(zoneFrame) == "table" and type(zoneFrame.HookScript) == "function"
		and type(subFrame) == "table" and type(subFrame.HookScript) == "function"
	if hooked then
		local shown = Perf.Shared("OnShow on the zone text frames", OnZoneShow, "script")
		Perf.HookScript(zoneFrame, "OnShow", shown)
		Perf.HookScript(subFrame, "OnShow", shown)
		Perf.HookScript(zoneFrame, "OnEvent", OnZoneTexts)
		if type(_G.ZoneText_Clear) == "function" then
			Perf.hooksecurefunc("ZoneText_Clear", OnZoneTexts)
		end
	end

	-- asked: the setting or the outline flipped (user), or a profile loaded
	-- (restart). Not made yet, it waits for the next zone text, unless the
	-- user switched it on while one shows
	function ZoneRefresh(user)
		if not built and not (user and hooked and MelloUI.initialized and (zoneFrame:IsShown() or subFrame:IsShown())) then
			return
		end
		Sync(true)
	end
end

-- what changed: the windows unlocked or locked, its own settings (and the
-- zone text's: its switch, the outline both share)
MelloUI:On("setting", function(module, key)
	if module == "Tweaks" then
		if key == "noticeOutline" then
			if frame then
				Restyle()
			end
			ZoneRefresh(true)
		elseif key == "zoneTextShade" then
			ZoneRefresh(true)
		elseif key == "noticeOnScreen" or key == "noticeToChat" then
			if not OnScreen() then
				HideNow()
			end
			Preview()
		end
	elseif module == "UIModifications" and key == "unlock" then
		Preview()
	end
end, OWNER)
MelloUI:On("module", function(module)
	if module == "UIModifications" then
		Preview()
	end
end, OWNER)
-- a profile load, or the settings arriving late at login (Core restarts the
-- modules then): any of it may have changed at once. A notice not made yet
-- stays unmade -- nothing is built at login, even with the windows left
-- unlocked (the sample comes with the next unlock, or after the first line).
-- The zone text's look follows too, once it was made.
MelloUI:On("restart", function()
	ZoneRefresh(false)
	if not frame then
		return
	end
	Restyle()
	if not OnScreen() then
		HideNow()
	end
	Preview()
end, OWNER)
