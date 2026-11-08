--------------------------------------------------------------------------------
-- MelloUI Chat - Copy Chat (2.1.24; a player, S1lver, 2026-11-08: "can we add a copy chat text"; the user's picks of
-- BuildData/output/copychat_tracked_sketch: B, a button that shows only while the pointer is on the chat, each line
-- with its time)
--
-- A small round button (W.GlyphButton, the widget glyph "copy") at the chat's top right corner, faded in while the
-- pointer is on the chat and out after: on the Minimal Chat View's lines (ChatView.lua), and on each of the game's
-- chat windows with the Game Windows view. A click puts the tab's lines into MelloUI's copy window (MelloUI:ShowText,
-- the one /mellolog uses), selected: Ctrl+C copies them. Each line plain (colours gone, a link its name, an icon left
-- out) with its time in front ([17:32]) -- the game's own time stamps when the chat shows them (the Chat Timestamps
-- setting), else the time the line came. A line the game keeps secret from addons is left out.
--
-- Nothing made at login: the button the first time the pointer comes onto the chat; the game's windows hooked once
-- each (OnEnter and OnLeave, post-hooks: the Fader's way), out of combat. A leave asks a moment later whether the
-- pointer is still on the chat (a window's own parts -- its scroll bar, its resize grip -- take it from the window
-- without leaving the chat): still there, asked again POLL seconds on, until it goes; nothing runs while it is hidden.
--
--   ns.Copy.Hook()     the windows hooked (the module's Apply; again harmless)
--   ns.Copy.Lines(src) the plain lines of a game window (a frame) or of the Minimal view's open tab (nil), and a name
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Chat (ChatCopy)")
local C_Timer = Perf.C_Timer
local Secret = MelloUI.Safe.IsSecret
local W = MelloUI.Widgets
local M = MelloUI:GetModule("Chat")

local SIZE = 22       -- the button (UI units)
local INSET = 4       -- from the chat's top right corner
local LEFT = 0.1      -- seconds after a leave: the pointer still on the chat?
local POLL = 0.25     -- and again while it is on the chat's own parts (only while the button shows)
local FADE_IN, FADE_OUT = 0.15, 0.2
local TEXT = {
	tip = "Copy Chat",
	tipLine = "This tab's lines in a window, ready to copy.",
	title = "Chat",
	none = "Nothing to copy in this tab yet.",
}

local Copy = {}
ns.Copy = Copy
M.Copy = Copy

local S = { button = nil, over = nil, asking = false, hooked = {} }

local function On()
	return M.isEnabled and M.db and M.db.copyButton ~= false
end

--------------------------------------------------------------------------------
-- The text
--------------------------------------------------------------------------------

-- a chat string as plain text: no colours, a link its name, no pictures (a secret one: nil)
local function PlainText(s)
	if Secret(s) or type(s) ~= "string" then
		return nil
	end
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
	s = s:gsub("|H.-|h(.-)|h", "%1")
	s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", "")
	s = s:gsub("||", "|")
	return s
end

-- the game's own chat time stamps are on (the Chat Timestamps setting): its lines carry their time already
local function GameStamps()
	local get = C_CVar and C_CVar.GetCVar or rawget(_G, "GetCVar")
	local ok, v = false, nil
	if type(get) == "function" then
		ok, v = pcall(get, "showTimestamps")
	end
	return ok and type(v) == "string" and v ~= "" and v ~= "none"
end

-- a Minimal view record as one line: its time, the channel's tag, the name, the words
local function RecordLine(rec)
	local body = PlainText(rec.body)
	if not body then
		return nil
	end
	local stamp = type(rec.time) == "string" and not Secret(rec.time) and ("[" .. rec.time .. "] ") or ""
	if rec.headed then
		local name = PlainText(rec.name)
		if not name then
			return nil
		end
		local tag = PlainText(rec.tag)
		return stamp .. ((tag and tag ~= "") and (tag .. " ") or "") .. name .. ": " .. body
	end
	return stamp .. body
end

-- a game window's lines, oldest first: its history's entries (their time GetTime's, turned into the clock)
local function WindowLines(frame, out)
	local stamps = not GameStamps()
	local entries = {}
	if type(frame.ForEachMessage) == "function" then
		pcall(frame.ForEachMessage, frame, function(entry)
			entries[#entries + 1] = entry
		end)
		-- (the history's own order is the newest first)
		for i = #entries, 1, -1 do
			local e = entries[i]
			local text = type(e) == "table" and PlainText(e.message)
			if text then
				local ts = type(e.timestamp) == "number" and not Secret(e.timestamp) and e.timestamp
				local stamp = (stamps and ts) and ("[" .. date("%H:%M", time() - math.floor(GetTime() - ts)) .. "] ") or ""
				out[#out + 1] = stamp .. text
			end
		end
		return out
	end
	-- (no history to walk: the lines alone)
	local okN, n = pcall(frame.GetNumMessages, frame)
	n = okN and not Secret(n) and tonumber(n) or 0
	for i = 1, n do
		local ok, msg = pcall(frame.GetMessageInfo, frame, i)
		local text = ok and PlainText(msg)
		if text then
			out[#out + 1] = text
		end
	end
	return out
end

local function WindowName(frame)
	local id = frame.GetID and frame:GetID()
	local info = rawget(_G, "GetChatWindowInfo")
	if type(info) == "function" and type(id) == "number" then
		local ok, name = pcall(info, id)
		if ok and type(name) == "string" and not Secret(name) and name ~= "" then
			return name
		end
	end
	return TEXT.title
end

function Copy.Lines(src)
	local out = {}
	if src then
		return WindowLines(src, out), WindowName(src)
	end
	local view = M.View
	if not (view and view.Records) then
		return out, TEXT.title
	end
	local recs, name = view.Records(view.tab)
	for _, rec in ipairs(recs) do
		local line = RecordLine(rec)
		if line then
			out[#out + 1] = line
		end
	end
	return out, name or TEXT.title
end

local function CopyNow()
	local lines, name = Copy.Lines(S.over ~= "view" and S.over or nil)
	if #lines == 0 then
		MelloUI:Print(TEXT.none)
		return
	end
	MelloUI:PlayUISound("click")
	MelloUI:ShowText(string.format("%s  (%d lines)", name, #lines), table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- The button
--------------------------------------------------------------------------------

-- the frame the pointer is on: the Minimal view's, or a game window
local function Holder()
	if S.over == "view" then
		local view = M.View
		return view and view.area
	end
	return S.over
end

local function Hide()
	local b = S.button
	if b and b:IsShown() then
		MelloUI.Anim:FadeOut(b, FADE_OUT)
	end
	S.over = nil
end

-- the pointer still on the chat or the button: stays (asked again in a moment); else away
local function Look()
	S.asking = false
	local b, holder = S.button, Holder()
	if not (b and b:IsShown()) then
		return
	end
	local on = holder and holder.IsMouseOver and holder:IsVisible() and holder:IsMouseOver()
	if (on or b:IsMouseOver()) and On() then
		S.asking = true
		C_Timer.After(POLL, Look)
		return
	end
	Hide()
end

local function Left()
	if not S.asking and S.button and S.button:IsShown() then
		S.asking = true
		C_Timer.After(LEFT, Look)
	end
end

local function Button()
	if S.button then
		return S.button
	end
	local b = W.GlyphButton(UIParent, SIZE, "copy")
	b:Hide()
	b:SetScript("OnClick", CopyNow)
	b:HookScript("OnEnter", function(self)
		W.ShowTooltip(self, TEXT.tip, TEXT.tipLine)
	end)
	b:HookScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
		Left()
	end)
	S.button = b
	return b
end

-- the pointer came onto the chat (`over`: "view", or a game window)
local function Shown(over)
	if not On() then
		return
	end
	local holder
	if over == "view" then
		local view = M.View
		holder = view and view.on and view.area
	else
		holder = over
	end
	if not (holder and holder:IsVisible()) then
		return
	end
	local b = Button()
	S.over = over
	b:ClearAllPoints()
	b:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -INSET, -INSET)
	b:SetFrameStrata(holder:GetFrameStrata())
	b:SetFrameLevel(holder:GetFrameLevel() + 20)
	if not b:IsShown() or b:GetAlpha() < 1 then
		MelloUI.Anim:FadeIn(b, FADE_IN)
	end
end

local function ViewEnter()
	Shown("view")
end

local function WindowEnter(frame)
	local view = M.View
	if view and view.hiding then
		return   -- (the Minimal view keeps the game's windows out of sight: its own lines take it)
	end
	Shown(frame)
end

--------------------------------------------------------------------------------
-- The hooks (once each; out of combat)
--------------------------------------------------------------------------------

local function HookOnce(f, fn)
	if type(f) == "table" and f.HookScript and not S.hooked[f] then
		if pcall(f.HookScript, f, "OnEnter", fn) and pcall(f.HookScript, f, "OnLeave", Left) then
			S.hooked[f] = true
		end
	end
end

local function HookNow()
	local view = M.View
	if view and view.frame then
		HookOnce(view.frame, ViewEnter)
		HookOnce(view.area, ViewEnter)
	end
	for i = 1, tonumber(rawget(_G, "NUM_CHAT_WINDOWS")) or 10 do
		HookOnce(rawget(_G, "ChatFrame" .. i), WindowEnter)
	end
end

function Copy.Hook()
	if not On() then
		Hide()
		return
	end
	MelloUI.Schedule:WhenOutOfCombat(HookNow, "Chat: Copy Chat's hooks")
end

-- (the setting switched off: the button away at once)
function Copy.Off()
	Hide()
end
