--------------------------------------------------------------------------------
-- MelloUI - Centre texts
--
-- The game's messages in the middle of the screen take the notice's look, as
-- the zone text does (Core/Notice.lua), so every big text there reads alike
-- (user, 2026-09-26: red error messages, raid warnings and boss emotes get
-- the soft shade, like the zone text). Two of the game's frames:
--   * the error frame (UIErrorsFrame): the red errors ("Not enough energy")
--     and the yellow info lines it shows too (quest progress such as "Boar
--     Meat: 3/8", "Discovered: ...");
--   * the raid warning frame (RaidWarningFrame): raid warnings, hardcore
--     deaths, boss emotes and boss whispers. On this client it holds them
--     all (there is no RaidBossEmoteFrame).
-- Each line gets:
--   * the notice's soft band behind it (MelloUI.Shade.TEXT: its colour,
--     strength, soft ends and side padding; above and below 0.4 of the text
--     size, Shade:LinePadY: 6 for an error line, 8 for a raid warning). The
--     band hangs by its anchors on a measure of the line's text (Shade:Measure,
--     an unseen copy the engine sizes to the text), so it hugs the text however
--     long with no size read; a text wider than its line (it wraps) takes the
--     line's whole span. A secret text is handed to the measure untouched and
--     never measured: only its line count is asked (more than one: the span).
--   * the game's own fade. The game fades each line on its own (an error line
--     held 2 s, then 0.5 s out; a raid warning 0.2 s in, held 10 s -- a boss
--     emote its own time -- and 3 s out), where a texture cannot follow a
--     font string's alpha, so each band lies on a frame of ours whose fade
--     copies its line's (Anim:Mirror: engine-driven, no Lua per frame, not
--     cut by Reduce Motion: the text keeps fading anyway). A repeated error
--     the game only flashes starts its band's fade again with it.
--   * the notice's text look, through the zone text's look core
--     (MelloUI.CentreLook, Notice.lua): no outline unless Outlined Text is
--     on, the game's face and size through MelloUI:StyleFont (Font Style
--     applying), the soft shadow. The game keeps its colours and its places.
-- Not shaded: private boss emotes (a secure frame of the game's, out of
-- reach), boss emotes during a cinematic (drawn on the cinematic's black
-- bar, where a dark band adds nothing), and lines the error frame gets with
-- no ID (system messages, other addons' lines: they cannot be found). Lines
-- sharing an ID: see Older below.
--
-- Setting: Tweaks centreTextShade, Centre Text Shade (on), read when used
-- like the notice's; Outlined Text (noticeOutline) covers these lines too.
-- The strength is the notice's, fixed. Off is the game's own look: every
-- band hidden, the error frame and each raid warning line back on its font
-- object, with its colour and its shadow.
--
-- Hooks only, never a script set on the game's frames, all added at load:
-- the error frame's AddMessage, ResetMessageFadeByID and Clear, after the
-- game's own (every line the error frame shows passes AddMessage, those
-- Error Messages lets through included), FadingFrame_Show (the raid warning
-- lines; the zone text's frames pass there too and are let go at once) and
-- the raid warning frame's UpdateLayout (a line released: its band stops).
-- Nothing is anchored to the game's frames themselves (the raid warning
-- frame is an Edit Mode system): our frames are their children, placed on
-- UIParent, and only the measures hang on the lines.
-- Nothing is made before the first message; then the look, one record per
-- line (a frame, a band of 3 textures and a measure; about 4 per frame) and
-- the bus listeners ('setting', 'restart', 'palette'). Nothing runs per
-- frame, nothing is written onto the game's objects (the records live in
-- weak side tables), and a message makes no garbage once its line's record
-- is made.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("CentreText")

local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text
local Call = MelloUI.Safe.Call
local Anim = MelloUI.Anim
local Shade = MelloUI.Shade
local Look = MelloUI.CentreLook   -- the zone text's look core (Notice.lua)

local OWNER = "Centre text"
local TEXT = Shade.TEXT
local ERR_PAD_Y = math.floor(Shade:LinePadY(16) + 0.5)   -- ErrorFont's 16: 6
local RW_PAD_Y = math.floor(Shade:LinePadY(20) + 0.5)    -- GameFontNormalHuge's 20: 8
-- the times the game's own files give, for one that cannot be read
local ERR_HOLD, ERR_FADE = 2, 0.5           -- UIErrorsFrame.xml (displayDuration, fadeDuration)
local RW_IN, RW_HOLD, RW_OUT = 0.2, 10, 3   -- RaidWarning.lua (FADE_IN_TIME, DEFAULT_HOLD_TIME, FADE_OUT_TIME)
local MAX_ERR = 6   -- error records at most (the frame shows about 3 lines)

local errFrame = _G.UIErrorsFrame
local rwFrame = _G.RaidWarningFrame

local state = { built = false, on = false }
local errLook = {}   -- the error frame's own record for the look core
local errRecs, rwRecs = {}, {}
local errOf = setmetatable({}, { __mode = "k" })   -- [the game's line] = its record
local rwOf = setmetatable({}, { __mode = "k" })

-- A line's record: a frame of ours, a child of the game's frame (it hides
-- with it; its own fade copies the line's), placed on UIParent, drawn under
-- every text in the BACKGROUND strata, never taking the mouse; on it the
-- band and the measure the band hangs on. The record is also the line's
-- record for the look core (its font object, its shadow)
local function Record(list, host, line, padY)
	local holder = CreateFrame("Frame", nil, host)
	holder:SetFrameStrata("BACKGROUND")
	holder:SetAllPoints(UIParent)
	holder:Hide()
	local rec = {
		holder = holder,
		band = Shade:Band(holder, TEXT),
		measure = Shade:Measure(holder, line, "TOP"),
		line = line,
		padY = padY,
		hung = nil,      -- "measure" or "span": where the band hangs
		live = false,    -- its fade runs
		at = 0,          -- when it started (the oldest error record is taken when all are in use)
	}
	list[#list + 1] = rec
	return rec
end

-- where the band hangs: on the measure (the text's own width) or on the
-- line's whole span (the text wraps, or the measure refused it); re-anchored
-- only when that changes. A width is read for a plain text only
local function Hang(rec, line, text)
	local m = rec.measure
	local span = not (m and Shade:MeasureText(m, text))
	if not span then
		if Secret(text) then
			local n = Num(Call(line, "GetNumLines"))
			span = n ~= nil and n > 1
		else
			local w = Num(Call(m, "GetUnboundedStringWidth")) or Num(Call(m, "GetStringWidth"))
			local lw = Num(Call(line, "GetWidth"))
			span = w ~= nil and lw ~= nil and lw > 0 and w > lw + 1
		end
	end
	local want = span and "span" or "measure"
	if rec.hung ~= want then
		rec.hung = want
		rec.band:Anchor(span and line or m, TEXT.padX, rec.padY)
	end
end

-- a record's fade stopped, its band hidden, its measure emptied (a secret
-- text's aspect dropped)
local function Stop(rec)
	rec.live = false
	Anim:StopMirror(rec.holder)
	if rec.measure then
		Shade:ClearMeasure(rec.measure)
	end
end

--------------------------------------------------------------------------------
-- The look on and off
--------------------------------------------------------------------------------

-- an error record let go of its line (the line gone, or cleared)
local function ErrFree(rec)
	Stop(rec)
	if rec.line then
		errOf[rec.line] = nil
		rec.line = nil
	end
end

local function StyleRaid(rec)
	Look.Keep(rec, rec.line, _G.GameFontNormalHuge)
	Look.On(rec, rec.line)
	rec.styled = true
	if rec.measure then
		Shade:MeasureFont(rec.measure)
	end
end

-- the notice's look on the error frame and on every raid warning line made
-- (again: the outline may have changed); the measures take the new fonts
local function StyleOn()
	state.on = true
	if errFrame then
		Look.Keep(errLook, errFrame, _G.ErrorFont)
		Look.On(errLook, errFrame)
	end
	for i = 1, #errRecs do
		local rec = errRecs[i]
		if rec.line and rec.measure then
			Shade:MeasureFont(rec.measure)
		end
	end
	for i = 1, #rwRecs do
		StyleRaid(rwRecs[i])
	end
end

-- the game's own look again, every band hidden
local function StyleOff()
	state.on = false
	for i = 1, #errRecs do
		ErrFree(errRecs[i])
	end
	for i = 1, #rwRecs do
		local rec = rwRecs[i]
		if rec.live then
			Stop(rec)
		end
		if rec.styled then
			rec.styled = false
			Look.Off(rec, rec.line)
		end
	end
	if errFrame then
		Look.Off(errLook, errFrame)
	end
end

-- the text shadows from the palette as it is now (the bands repaint on
-- their own, Shade's listener)
local function Paint()
	if not state.on then
		return
	end
	if errFrame and errLook.object ~= nil then
		Look.Shadow(errFrame)
	end
	for i = 1, #rwRecs do
		local rec = rwRecs[i]
		if rec.styled then
			Look.Shadow(rec.line)
		end
	end
end

-- the look as the setting wants it: its switch flipped (user) or a profile
-- loaded (restart). Before the first message nothing is made: that message
-- builds
local function Refresh()
	if Look.Setting("centreTextShade") then
		if state.built then
			StyleOn()
		end
	elseif state.on then
		StyleOff()
	end
end

local function OnSetting(module, key)
	if module ~= "Tweaks" then
		return
	end
	if key == "centreTextShade" then
		Refresh()
	elseif key == "noticeOutline" and state.on then
		StyleOn()
	end
end

-- a message while the look is off: on now if the setting wants it (the
-- first one builds: the listeners, the look). false: not wanted
local function Start()
	if not (MelloUI.initialized and Look.Setting("centreTextShade")) then
		return false
	end
	if not state.built then
		state.built = true
		MelloUI:On("setting", OnSetting, OWNER)
		MelloUI:On("restart", Refresh, OWNER)
		MelloUI:On("palette", Paint, OWNER)
	end
	StyleOn()
	return true
end

--------------------------------------------------------------------------------
-- The error frame
--------------------------------------------------------------------------------

-- the band's fade as the line's: shown at once, held as long as the frame
-- keeps a line, then out as it fades them (its fade eases in: a slow start,
-- as the frame's own)
local function ErrPlay(rec)
	local hold = Num(Call(errFrame, "GetTimeVisible")) or ERR_HOLD
	local fade = Num(Call(errFrame, "GetFadeDuration")) or ERR_FADE
	rec.live = true
	rec.at = GetTime()
	Anim:Mirror(rec.holder, 0, hold, fade, "IN")
end

-- the records of lines the frame no longer shows let go (their fades ended,
-- or the lines pushed out by newer ones)
local function ErrSweep()
	for i = 1, #errRecs do
		local rec = errRecs[i]
		if rec.line and (Call(rec.line, "IsShown") == false or not rec.holder:IsShown()) then
			ErrFree(rec)
		end
	end
end

-- the line's record: its own, a free one (its measure moved onto the line),
-- a new one, or with all in use the oldest
local function ErrRecord(line)
	local rec = errOf[line]
	if rec then
		return rec
	end
	local oldest
	for i = 1, #errRecs do
		local r = errRecs[i]
		if not r.line then
			rec = r
			break
		end
		if not oldest or r.at < oldest.at then
			oldest = r
		end
	end
	if not rec and #errRecs >= MAX_ERR then
		rec = oldest
		ErrFree(rec)
	end
	if rec then
		rec.line = line
		rec.hung = nil
		local m = rec.measure
		if m then
			m:ClearAllPoints()
			m:SetPoint("TOP", line, "TOP", 0, 0)
			Shade:MeasureFont(m, line)
		end
	else
		rec = Record(errRecs, errFrame, line, ERR_PAD_Y)
	end
	errOf[line] = rec
	return rec
end

-- Lines that share one ID (on this client a repeated "Not enough energy"
-- stacks new lines; quest progress lines share their type): the line the ID
-- finds is taken as the one just added. One that already has a band and
-- shows another text is an older line (the client gave the oldest): it keeps
-- its own band and fade, and the new line goes without one. Plain texts only
-- are compared (Safe.Text: a secret is asked first)
local function Older(line, text)
	text = Text(text)
	local now = text and Text(Call(line, "GetText"))
	return now ~= nil and now ~= text
end

-- a line added: found by its message ID (the game adds its errors and info
-- lines with their type as the ID); one without an ID cannot be found
local function OnErrorAdded(frame, text, _, _, _, _, id)
	if not state.on and not Start() then
		return
	end
	ErrSweep()
	-- the secret test first: a secret refuses even the nil test
	if Secret(id) or id == nil then
		return
	end
	local line = Call(frame, "GetFontStringByID", id)
	if type(line) ~= "table" or (errOf[line] and Older(line, text)) then
		return
	end
	local rec = ErrRecord(line)
	Hang(rec, line, text)
	ErrPlay(rec)
end

-- a repeat the game only flashes: its line held again, and the band with it
local function OnErrorReset(frame, id)
	if not state.on or Secret(id) or id == nil then
		return
	end
	local line = Call(frame, "GetFontStringByID", id)
	local rec = type(line) == "table" and errOf[line]
	if rec then
		ErrPlay(rec)
	end
end

local function OnErrorClear()
	for i = 1, #errRecs do
		local rec = errRecs[i]
		if rec.line then
			ErrFree(rec)
		end
	end
end

--------------------------------------------------------------------------------
-- The raid warning frame
--------------------------------------------------------------------------------

-- a line shown (FadingFrame_Show: a new message, or its string taken again
-- for one): its band hung on its text and faded as the line (its own times:
-- in, held, out, even; a boss emote's hold is its own)
local function OnFadingShow(fs)
	if not rwOf[fs] and (type(fs) ~= "table" or Call(fs, "GetParent") ~= rwFrame) then
		return   -- not the raid warning frame's (the zone text's frames)
	end
	if not state.on and not Start() then
		return
	end
	local rec = rwOf[fs]
	if not rec then
		rec = Record(rwRecs, rwFrame, fs, RW_PAD_Y)
		rwOf[fs] = rec
	end
	if not rec.styled then
		StyleRaid(rec)
	end
	Hang(rec, fs, fs:GetText())
	rec.live = true
	rec.at = GetTime()
	Anim:Mirror(rec.holder, Num(fs.fadeInTime) or RW_IN, Num(fs.holdTime) or RW_HOLD, Num(fs.fadeOutTime) or RW_OUT,
		"NONE")
end

-- the frame laid out again (a message added, cleared, or faded and
-- released): the bands of released lines stop
local function OnRaidLayout()
	for i = 1, #rwRecs do
		local rec = rwRecs[i]
		if rec.live and Call(rec.line, "IsShown") == false then
			Stop(rec)
		end
	end
end

--------------------------------------------------------------------------------
-- The hooks (at load; nothing else is made or taken before the first message)
--------------------------------------------------------------------------------

if type(errFrame) == "table" and type(errFrame.AddMessage) == "function"
	and type(errFrame.ResetMessageFadeByID) == "function" and type(errFrame.Clear) == "function" then
	Perf.hooksecurefunc(errFrame, "AddMessage", OnErrorAdded)
	Perf.hooksecurefunc(errFrame, "ResetMessageFadeByID", OnErrorReset)
	Perf.hooksecurefunc(errFrame, "Clear", OnErrorClear)
end
if type(rwFrame) == "table" and type(rwFrame.UpdateLayout) == "function"
	and type(_G.FadingFrame_Show) == "function" then
	Perf.hooksecurefunc("FadingFrame_Show", OnFadingShow)
	Perf.hooksecurefunc(rwFrame, "UpdateLayout", OnRaidLayout)
end
