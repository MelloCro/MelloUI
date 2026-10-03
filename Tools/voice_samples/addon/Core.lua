--------------------------------------------------------------------------------
-- MelloUI Voice Samples
--
-- A small addon of its own, shared on Discord (user, 2026-10-03): every voice
-- of the voice pack reads one line -- its own quest dialogue where it has one,
-- else a quest text of the game -- at three speeds, 0.9x, 1.0x (as the voice
-- speaks now) and 1.15x. Players play them, tick the speed that sounds right
-- for each voice, and press Send Feedback: the game cannot reach Discord, so
-- it shows one line to copy (Ctrl+C) and paste into #voiceover-feedback. The
-- line carries a code, MVS1-<data version>-<picks>, that MelloUI's tools read
-- back (Tools/voice_samples/samples.py tally): three voices per character, a
-- pick each (0 none, 1 = 0.9x, 2 = 1.0x, 3 = 1.15x) in Data.lua's order.
-- The picks are saved (MelloUIVoiceSamplesDB), so rating can go on later.
--
--   /voicesamples (or /vsamples)   opens and closes the window
--------------------------------------------------------------------------------
-- luacheck: globals MelloUIVoiceSamplesDB SLASH_MELLOVOICESAMPLES1 SLASH_MELLOVOICESAMPLES2

local ADDON, ns = ...
local DATA = ns.data
local VOICES = DATA.voices

local SPEEDS = { "0.9x", "1.0x", "1.15x" }
local FILES = { "_090", "_100", "_115" }
local ROW_H = 58
local CHANNEL = "Master"
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+="

local db
local frame, scrollBox, search, unratedOnly, progress, empty, feedback
local playing   -- { key, speed, handle, token }

--------------------------------------------------------------------------------
-- The feedback line (pure: the tools' tests run these)
--------------------------------------------------------------------------------

function ns.Encode(picks, voices)
	local out = {}
	for i = 1, #voices, 3 do
		local a = picks[voices[i].key] or 0
		local b = voices[i + 1] and picks[voices[i + 1].key] or 0
		local c = voices[i + 2] and picks[voices[i + 2].key] or 0
		local n = a + 4 * b + 16 * c
		out[#out + 1] = ALPHABET:sub(n + 1, n + 1)
	end
	return table.concat(out)
end

-- how many voices are rated, and how many got each speed
function ns.Summary(picks, voices)
	local counts, rated = { 0, 0, 0 }, 0
	for _, v in ipairs(voices) do
		local p = picks[v.key]
		if p then
			counts[p] = counts[p] + 1
			rated = rated + 1
		end
	end
	return rated, counts
end

function ns.FeedbackLine(picks, data)
	local rated, c = ns.Summary(picks, data.voices)
	return string.format("MelloUI Voice Samples: %d of %d voices rated (0.9x %d, 1.0x %d, 1.15x %d) MVS1-%s-%s",
		rated, #data.voices, c[1], c[2], c[3], data.version, ns.Encode(picks, data.voices))
end

--------------------------------------------------------------------------------
-- Playing
--------------------------------------------------------------------------------

local function Path(v, i)
	return "Interface\\AddOns\\" .. ADDON .. "\\Sounds\\" .. v.key .. FILES[i] .. ".ogg"
end

local function RefreshRows()
	if scrollBox then
		scrollBox:ForEachFrame(function(row)
			ns.PaintRow(row)
		end)
	end
end

local function Stop()
	if playing and playing.handle then
		StopSound(playing.handle)
	end
	playing = nil
	RefreshRows()
end

local function Play(v, i)
	if playing and playing.handle then
		StopSound(playing.handle)
	end
	playing = nil
	local willPlay, handle = PlaySoundFile(Path(v, i), CHANNEL)
	if willPlay then
		local token = {}
		playing = { key = v.key, speed = i, handle = handle, token = token }
		C_Timer.After((v.secs[i] or 10) + 0.3, function()
			if playing and playing.token == token then
				playing = nil
				RefreshRows()
			end
		end)
	else
		print("|cffffd200MelloUI Voice Samples:|r the sample could not play. Is the game's sound on?")
	end
	RefreshRows()
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

local function UpdateProgress()
	if progress then
		local rated = ns.Summary(db.picks, VOICES)
		progress:SetFormattedText("Rated %d of %d", rated, #VOICES)
	end
end

local function Matches(v, q)
	if q == "" then
		return true
	end
	return (v.key .. " " .. v.who .. " " .. v.quest .. " " .. v.group):lower():find(q, 1, true) ~= nil
end

local function Rebuild()
	if not scrollBox then
		return
	end
	local q = (search:GetText() or ""):lower()
	local only = unratedOnly:GetChecked()
	local items = {}
	for _, v in ipairs(VOICES) do
		if Matches(v, q) and (not only or not db.picks[v.key]) then
			items[#items + 1] = v
		end
	end
	scrollBox:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants.RetainScrollPosition)
	empty:SetShown(#items == 0)
end

local function SetPick(v, i)
	if db.picks[v.key] == i then
		db.picks[v.key] = nil
	else
		db.picks[v.key] = i
	end
	UpdateProgress()
	RefreshRows()
end

local function BuildRow(row)
	row:SetHeight(ROW_H)
	local line = row:CreateTexture(nil, "BACKGROUND")
	line:SetColorTexture(1, 1, 1, 0.08)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT", 4, 0)
	line:SetPoint("BOTTOMRIGHT", -4, 0)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("TOPLEFT", 10, -9)
	row.name:SetWidth(340)
	row.name:SetJustifyH("LEFT")
	row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -5)
	row.sub:SetWidth(340)
	row.sub:SetJustifyH("LEFT")
	row.sub:SetWordWrap(true)
	row.sub:SetMaxLines(2)
	row.sub:SetTextColor(0.75, 0.75, 0.75)
	row.play, row.pick = {}, {}
	for i = 1, 3 do
		local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		b:SetSize(66, 22)
		b:SetPoint("TOPLEFT", row, "TOPLEFT", 366 + (i - 1) * 80, -6)
		b:SetText(SPEEDS[i])
		b:SetScript("OnClick", function()
			Play(row.voice, i)
		end)
		row.play[i] = b
		local c = CreateFrame("CheckButton", nil, row, "UIRadioButtonTemplate")
		c:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 10, -5)
		c.text:SetText("Best")
		c:SetScript("OnClick", function()
			SetPick(row.voice, i)
		end)
		row.pick[i] = c
	end
	-- the line itself on hover
	row:SetScript("OnEnter", function(self)
		local v = self.voice
		if not v then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(v.key, 1, 0.82, 0)
		if v.who ~= "" then
			GameTooltip:AddLine(v.quest ~= "" and (v.who .. ", " .. v.quest) or v.who, 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine(v.text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row.built = true
end

function ns.PaintRow(row)
	local v = row.voice
	if not v then
		return
	end
	row.name:SetText(v.key)
	local bits = {}
	if v.who ~= "" then
		bits[#bits + 1] = v.quest ~= "" and (v.who .. ", " .. v.quest) or v.who
	end
	bits[#bits + 1] = v.group
	bits[#bits + 1] = v.packLines > 0 and (v.packLines .. " lines in the voice pack") or "not in the voice pack yet"
	row.sub:SetText(table.concat(bits, "  -  "))
	local pick = db.picks[v.key]
	for i = 1, 3 do
		row.pick[i]:SetChecked(pick == i)
		if playing and playing.key == v.key and playing.speed == i then
			row.play[i]:LockHighlight()
		else
			row.play[i]:UnlockHighlight()
		end
	end
end

local function NextUnrated()
	if not scrollBox then
		return
	end
	local provider = scrollBox:GetDataProvider()
	local found
	if provider then
		for _, v in provider:Enumerate() do
			if not db.picks[v.key] then
				found = v
				break
			end
		end
	end
	if not found then
		print("|cffffd200MelloUI Voice Samples:|r every voice in the list is rated. Thank you! Press Send Feedback.")
		return
	end
	scrollBox:ScrollToElementData(found, ScrollBoxConstants.AlignCenter)
	Play(found, 2)
end

--------------------------------------------------------------------------------
-- Send Feedback: one line to copy
--------------------------------------------------------------------------------

local function ShowFeedback()
	if not feedback then
		feedback = CreateFrame("Frame", "MelloUIVoiceSamplesFeedback", UIParent, "BasicFrameTemplateWithInset")
		feedback:SetSize(600, 176)
		feedback:SetPoint("CENTER", 0, 120)
		feedback:SetFrameStrata("DIALOG")
		feedback:SetToplevel(true)
		feedback:EnableMouse(true)
		feedback.TitleText:SetText("Send Feedback")
		local info = feedback:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		info:SetPoint("TOPLEFT", 18, -34)
		info:SetPoint("RIGHT", -18, 0)
		info:SetJustifyH("LEFT")
		info:SetText("Press Ctrl+C to copy the line below, then paste it into the #voiceover-feedback channel on "
			.. "Discord. You can keep rating and send a new line later.")
		local box = CreateFrame("EditBox", nil, feedback, "InputBoxTemplate")
		box:SetSize(552, 24)
		box:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 6, -14)
		box:SetAutoFocus(false)
		box:SetMaxLetters(0)
		-- read only: whatever is typed, the line comes back, selected
		box:SetScript("OnTextChanged", function(self, userInput)
			if userInput then
				self:SetText(feedback.code)
				self:HighlightText()
			end
		end)
		box:SetScript("OnEditFocusGained", function(self)
			self:HighlightText()
		end)
		box:SetScript("OnEscapePressed", function()
			feedback:Hide()
		end)
		feedback.box = box
		local done = CreateFrame("Button", nil, feedback, "UIPanelButtonTemplate")
		done:SetSize(110, 24)
		done:SetPoint("BOTTOMRIGHT", -16, 14)
		done:SetText("Done")
		done:SetScript("OnClick", function()
			feedback:Hide()
		end)
		tinsert(UISpecialFrames, "MelloUIVoiceSamplesFeedback")
	end
	feedback.code = ns.FeedbackLine(db.picks, DATA)
	feedback.box:SetText(feedback.code)
	feedback:Show()
	feedback.box:SetFocus()
	feedback.box:HighlightText()
end

--------------------------------------------------------------------------------
-- The window (made on its first open)
--------------------------------------------------------------------------------

local function Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 24)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function Create()
	frame = CreateFrame("Frame", "MelloUIVoiceSamplesFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(760, 620)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetScript("OnHide", Stop)
	frame.TitleText:SetText("MelloUI Voice Samples")
	tinsert(UISpecialFrames, "MelloUIVoiceSamplesFrame")

	local intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	intro:SetPoint("TOPLEFT", 18, -34)
	intro:SetPoint("RIGHT", -18, 0)
	intro:SetJustifyH("LEFT")
	intro:SetText("Every voice of the voice pack reads one line at three speeds: 0.9x (slower), 1.0x (as it "
		.. "speaks now) and 1.15x (faster). Play them and tick Best under the speed that sounds most natural "
		.. "for that voice. Point at a voice to read its line. When you are done, or want a break, press Send Feedback.")

	search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	search:SetSize(240, 20)
	search:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 6, -12)
	search:HookScript("OnTextChanged", Rebuild)

	unratedOnly = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	unratedOnly:SetSize(26, 26)
	unratedOnly:SetPoint("LEFT", search, "RIGHT", 18, 0)
	unratedOnly.Text:SetText("Unrated only")
	unratedOnly:SetScript("OnClick", Rebuild)

	progress = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	progress:SetPoint("RIGHT", frame, "RIGHT", -22, 0)
	progress:SetPoint("TOP", search, "TOP", 0, -3)

	scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -12, -10)
	scrollBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 46)
	local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 8, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 8, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_H)
	view:SetElementInitializer("Button", function(row, v)
		if not row.built then
			BuildRow(row)
		end
		row.voice = v
		ns.PaintRow(row)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER", scrollBox, "CENTER")
	empty:SetText("No voice matches.")
	empty:Hide()

	local stop = Button(frame, "Stop", 100, Stop)
	stop:SetPoint("BOTTOMLEFT", 16, 14)
	local nextOne = Button(frame, "Play Next Unrated", 160, NextUnrated)
	nextOne:SetPoint("LEFT", stop, "RIGHT", 8, 0)
	local send = Button(frame, "Send Feedback", 160, ShowFeedback)
	send:SetPoint("BOTTOMRIGHT", -16, 14)

	UpdateProgress()
	Rebuild()
end

local function Toggle()
	if not frame then
		Create()
		frame:Show()
	elseif frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		UpdateProgress()
		Rebuild()
	end
end
ns.Toggle = Toggle

SLASH_MELLOVOICESAMPLES1 = "/voicesamples"
SLASH_MELLOVOICESAMPLES2 = "/vsamples"
SlashCmdList.MELLOVOICESAMPLES = Toggle

--------------------------------------------------------------------------------
-- Saved picks
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name == ADDON then
		MelloUIVoiceSamplesDB = type(MelloUIVoiceSamplesDB) == "table" and MelloUIVoiceSamplesDB or {}
		db = MelloUIVoiceSamplesDB
		db.picks = type(db.picks) == "table" and db.picks or {}
		-- (a pick of a voice no longer in the list, or not a speed, goes)
		local known = {}
		for _, v in ipairs(VOICES) do
			known[v.key] = true
		end
		for key, p in pairs(db.picks) do
			if not known[key] or (p ~= 1 and p ~= 2 and p ~= 3) then
				db.picks[key] = nil
			end
		end
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		print("|cffffd200MelloUI Voice Samples:|r type /voicesamples to listen to the voices and rate them.")
	end
end)
