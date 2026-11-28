--------------------------------------------------------------------------------
-- MelloUI - Grouped With MelloUI (2.1.76; MelloUI.GroupMoment)
--
-- The user, 2026-11-23: "if 2 players join a group, and both use mello ui, to get a special animation for it"; the
-- sketch BuildData/output/group_moment_sketch (artifact DRmz1gwDbD867gTBB4anrh), the user's pick B, "a moment on
-- screen": your portrait and theirs slide together at the MelloUI seal (its gilded ring, the logo stamped, rays, a
-- wave, sparks), "<Name> uses MelloUI too" and "Now in your group" under a rule; held about two seconds, then it flies
-- into their party frame and lights it (no frame to fly to: it fades in place). Several MelloUI players greeting at
-- once play as one moment. Plan: docs/plans/group-moment.md.
--
-- How the players find each other: the game's addon messages (prefix "MelloUI") on the group's channel. A player whose
-- roster grows from nothing (it joined, or a group formed round it) sends "HI:<version>"; every MelloUI player who
-- hears a HI answers "HEY:<version>" (once in a few seconds, for every HI then). A HI or a HEY plays the moment for its
-- sender when the sender joined in the last minute or I did -- so the newcomer sees everyone, everyone sees the
-- newcomer, and the old members do not see each other again. One moment a player in six hours (db.greeted, this
-- character's, never in a profile). The login and a /reload take the roster as it stands: nothing sent, nothing played.
-- A send the game refuses (its lockdown in an encounter, a throttle) is tried again a few times. A secret name or GUID:
-- that member is left out. The hello runs while the module is on (invisible, always on: a hidden module).
-- An EASTER EGG (the user, 2026-11-23: "This is a easter egg, i dont want people to know what it is until they join a
-- group with another melloui user"): the moment is on by default and nothing tells of it -- no line in the CHANGELOG,
-- What's new, the guide or the Discord text, the module hidden from the configurator's lists. Its switch, "MelloUI
-- Player Joins" on the Animations page, is laid only once the moment has played for this player (db.revealed, set by
-- the first real moment; Core/ConfigLayout.lua's `reveal`), so it can be turned off after it has been seen.
--
-- The moment: frames made at the first one, on UIParent, no mouse, no secure frame; in the middle of the game's screen
-- (MelloUI:PlayArea), above the character, never over it; plays once (one Anim:Drive, a function of its time), nothing
-- repeats. Reduce Motion: the settled moment, held and gone. The easings are Quest Moments' (MelloUI.QuestMoments.__).
--
--   MelloUI.GroupMoment.Play(unit, name)   a sample moment (the Animations page's Play)
--   /mello grouped play | why
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Safe = MelloUI.Safe
local Num, Text = Safe.Number, Safe.Text
local Perf = MelloUI.Perf:Scope("Group moment")
local Shared = Perf.Shared
local C_Timer = Perf.C_Timer
local sin, cos, pi, max, min, exp = math.sin, math.cos, math.pi, math.max, math.min, math.exp

local M = MelloUI:RegisterModule("GroupMoment", {
	title = "MelloUI Players",
	slash = "grouped",   -- /mello grouped play | why
	desc = "Lets other MelloUI players in your group know you use MelloUI too. Its moment, on the Animations page, shows when one of them joins you.",
	icon = "Interface\\AddOns\\MelloUI\\Media\\Textures\\LogoIcon",
	flavour = "Spot a fellow MelloUI player the moment they join.",
	enabledByDefault = true,
	hidden = true,   -- (an easter egg: no page, no switch of its own in the lists; the hello always runs)
	keep = { "greeted", "revealed" },   -- (this character's: the players greeted, the moment seen once; never in a profile)
	defaults = { moment = true },
	options = {
		{ type = "toggle", key = "moment", play = "moment", name = "MelloUI Player Joins",
		  desc = "When someone who uses MelloUI joins your group, your portraits meet at the MelloUI seal for a moment with their name, then it flies into their party frame. Once a player in six hours." },
	},
})

local LIGHT = "Interface\\AddOns\\MelloUI\\Media\\FrameFX\\Light\\"   -- onelook-allow: a moment's light, in both looks
local GLOW = "Interface\\AddOns\\MelloUI\\Media\\FrameFX\\glow_gold"   -- onelook-allow: a moment's light, in both looks
local LOGO = "Interface\\AddOns\\MelloUI\\Media\\Textures\\LogoFull"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- (one table: the file's locals) times in seconds, sizes in UIParent units (the sketch's 1600-wide stage of a
-- 2560-pixel screen, three quarters of its size)
local G = {
	PREFIX = "MelloUI",
	WINDOW = 60,                -- a hello counts for a member who joined, or for me having joined, this long ago
	AGAIN = 6 * 3600,           -- one moment a player in this long (time(), kept over the logout)
	MERGE = 1.5,                -- the hellos gathered into one moment
	ANSWER = 4,                 -- one HEY in this long answers every HI then
	SEED = 5,                   -- after the login or a /reload, the roster's changes this long are its first read
	RETRY = 5, TRIES = 6,       -- a refused send: again every RETRY seconds, TRIES times
	DOWN = 0.28,                -- the moment's middle: this share of the game's screen under its top
	OUT = 3.06, FLY = 0.64,     -- when it leaves (two seconds after its words are in) and its flight
	ARRIVE = 0.62,              -- the light on their frame after the flight
	FADE = 0.55,                -- no frame to fly to: it fades in place
	STILL = 1.6, HOLD = 2.6,    -- (Reduce Motion) the settled moment and how long it stays
	FACE = 44, RING = 70, SPREAD = 74, FROM = 225,   -- the portraits: face, its ring, apart from the middle, where from
	SEAL = 96, LOGO = 63, RAYS = 180, WAVE = 112, GLOW = 128,
	RULE = 300, RULE_Y = 46, LINE_Y = 64, SUB_Y = 86, NAME = 20, SUB = 14,
	SPARKS = 14,
	-- the state
	me = nil,                   -- my GUID
	roster = {}, other = {},    -- [guid] = unit token: the group now, and the table the next read fills
	joined = {},                -- [guid] = GetTime() it came into the group
	inGroup = false, myJoin = -1000, seedUntil = 0,
	pGuid = {}, pUnit = {}, pName = {}, pN = 0,   -- the players gathered for the next moment
	answeredAt = -1000, retries = 0, retryKind = nil,
	last = {}, lastN = 0,       -- the last messages heard and sent (/mello grouped why): text lines in a ring
}
MelloUI.GroupMoment = G
local B = {}                    -- the moment's frames, made at the first one
local eventFrame

local PARTY, RAID = {}, {}      -- the unit tokens, made once (no string per event)
for i = 1, 4 do
	PARTY[i] = "party" .. i
end
for i = 1, 40 do
	RAID[i] = "raid" .. i
end

local function Note(fmt, ...)
	G.lastN = G.lastN + 1
	G.last[(G.lastN - 1) % 12 + 1] = ("%s  " .. fmt):format(date("%H:%M:%S"), ...)
end

--------------------------------------------------------------------------------
-- The group: who is in it, who came in when
--------------------------------------------------------------------------------

local function ReadRoster(into)
	wipe(into)
	local list, n = PARTY, 4
	if IsInRaid() then
		list, n = RAID, 40
	end
	for i = 1, n do
		local unit = list[i]
		if UnitExists(unit) then
			local guid = Text(UnitGUID(unit))
			if guid and guid ~= G.me then
				into[guid] = unit
			end
		end
	end
end

-- the group's channel for an addon message, or nil (not in a group)
local function Channel()
	local instance = rawget(_G, "LE_PARTY_CATEGORY_INSTANCE")
	if instance and IsInGroup(instance) then
		return "INSTANCE_CHAT"
	elseif IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
	return nil
end

local Send   -- (below)

local Retry = Shared("MelloUI Players: a hello sent again", function()
	G.retryTimer = nil
	if G.retryKind then
		Send(G.retryKind)
	end
end)

-- a HI or a HEY to the group; refused by the game (its lockdown, a throttle): again in a few seconds
Send = function(kind)
	local channel = Channel()
	local send = C_ChatInfo and C_ChatInfo.SendAddonMessage
	if not (channel and type(send) == "function") then
		return
	end
	local ok, result = pcall(send, G.PREFIX, kind .. ":" .. tostring(MelloUI.version), channel)
	local sent = ok and (result == nil or result == true or result == 0)
	Note("sent %s on %s: %s", kind, channel, sent and "ok" or tostring(result))
	if sent then
		G.retryKind, G.retries = nil, 0
		return
	end
	G.retries = G.retries + 1
	if G.retries <= G.TRIES and not G.retryTimer then
		G.retryKind = kind
		G.retryTimer = C_Timer.NewTimer(G.RETRY, Retry)
	else
		G.retryKind, G.retries = nil, 0
	end
end

local function OnRoster()
	local now = GetTime()
	local inGroup = IsInGroup() and true or false
	ReadRoster(G.other)
	if now < G.seedUntil then
		-- (the login or a /reload: the group as it stands, nothing sent or played)
		G.myJoin = -1000
	else
		for guid in pairs(G.other) do
			if not G.roster[guid] then
				G.joined[guid] = now
			end
		end
		if inGroup and not G.inGroup then
			G.myJoin = now   -- I came into a group, or one formed round me: my hello
			Send("HI")
		end
	end
	G.roster, G.other = G.other, G.roster
	G.inGroup = inGroup
	if not inGroup then
		wipe(G.joined)
	end
end

-- the group member an addon message came from ("Name-Realm"): its unit and GUID, or nil
local function MemberOf(sender)
	local short = type(Ambiguate) == "function" and Text(Ambiguate(sender, "none")) or sender
	for guid, unit in pairs(G.roster) do
		local name, realm = UnitName(unit)
		name, realm = Text(name), Text(realm)
		if name and (name == short or name == sender
			or (realm and realm ~= "" and (name .. "-" .. realm) == sender)) then
			return unit, guid
		end
	end
	return nil
end

local Gather   -- (below)

local function OnAddon(prefix, text, sender)
	prefix, text, sender = Text(prefix), Text(text), Text(sender)
	if prefix ~= G.PREFIX or not (text and sender) then
		return
	end
	local kind = text:match("^(%u+):")
	if kind ~= "HI" and kind ~= "HEY" then
		return
	end
	local unit, guid = MemberOf(sender)
	if not unit then
		-- (a hello may come before the game's roster event: the group read again, once)
		OnRoster()
		unit, guid = MemberOf(sender)
	end
	if not unit then
		return   -- (myself, or not in the group I can read)
	end
	Note("heard %s from %s", kind, sender)
	local now = GetTime()
	if kind == "HI" and now - G.answeredAt > G.ANSWER then
		G.answeredAt = now
		Send("HEY")
	end
	local came = G.joined[guid]
	if (came and now - came < G.WINDOW) or now - G.myJoin < G.WINDOW then
		Gather(guid, unit)
	end
end

local function OnEvent(_, event, ...)
	if event == "GROUP_ROSTER_UPDATE" then
		OnRoster()
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, text, _, sender = ...
		OnAddon(prefix, text, sender)
	elseif event == "PLAYER_ENTERING_WORLD" then
		local login, reload = ...
		G.me = Text(UnitGUID("player")) or G.me
		if login or reload then
			G.seedUntil = GetTime() + G.SEED
			OnRoster()
		end
	end
end
OnEvent = Shared("MelloUI Players: the group's events", OnEvent, "event")

--------------------------------------------------------------------------------
-- The moment's frames (made at the first moment)
--------------------------------------------------------------------------------

local QM = MelloUI.QuestMoments and MelloUI.QuestMoments.__
local Seg, OutCubic, OutBack, Hump = QM.Seg, QM.OutCubic, QM.OutBack, QM.Hump
local W   -- MelloUI.Widgets, read at the first moment
local function Tr(text)
	local Lang = MelloUI.Lang
	return Lang and Lang.T(text) or text
end

local function Tex(file, layer, sub, add)
	local t = B.root:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
	if file then
		t:SetTexture(file)
	end
	if add then
		t:SetBlendMode("ADD")
	end
	t:Hide()
	return t
end

local function Face(fs, size)
	local Kit = rawget(MelloUI, "Kit")
	local face = Kit and Kit.titleFont or "Interface\\AddOns\\MelloUI\\Media\\Fonts\\Fredoka\\Fredoka-SemiBold.ttf"
	if not MelloUI:SetFace(fs, face, size, "") then
		fs:SetFontObject(W.FontObject("MelloUIFont_GameFontHighlight"))
	end
	fs:SetShadowColor(0, 0, 0, 0.9)
	fs:SetShadowOffset(1, -1)
end

local function Portrait()
	local face = Tex(nil, "ARTWORK", 3)
	local mask = B.root:CreateMaskTexture()
	mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(face)
	face:AddMaskTexture(mask)
	local ring = Tex(LIGHT .. "ring_gold", "OVERLAY", 2, true)
	return face, ring
end

local function Build()
	if B.root then
		return
	end
	W = MelloUI.Widgets
	local root = CreateFrame("Frame", nil, UIParent)
	root:SetAllPoints(UIParent)
	root:SetFrameStrata("HIGH")
	root:EnableMouse(false)
	root:Hide()
	B.root = root
	-- the soft band under it all (MelloUI.Shade, the moments' own), on a box the moment lays
	B.box = CreateFrame("Frame", nil, root)
	B.box:SetSize(1, 1)
	B.band = MelloUI.Shade:Band(root, { colour = "innerPanel", alpha = 0.8, feather = 24 })
	if B.band then
		B.band:Anchor(B.box, 0, 0)
	end
	B.rays = Tex(LIGHT .. "rays_gold", "BACKGROUND", 2, true)
	B.glow = Tex(GLOW, "BORDER", 1, true)
	B.wave = Tex(LIGHT .. "wave_gold", "ARTWORK", 1, true)
	B.seal = Tex(LIGHT .. "seal_gold", "ARTWORK", 2, true)
	B.logo = Tex(LOGO, "ARTWORK", 4)
	B.faceL, B.ringL = Portrait()
	B.faceR, B.ringR = Portrait()
	B.rule = Tex(LIGHT .. "line_h", "ARTWORK", 2, true)
	W.Paint(B.rule, "selectedTrim", "vertex")
	B.line = root:CreateFontString(nil, "OVERLAY")
	B.sub = root:CreateFontString(nil, "OVERLAY")
	Face(B.line, G.NAME)
	Face(B.sub, G.SUB)
	W.Paint(B.line, "text", "text")
	W.Paint(B.sub, "text", "text")
	B.line:Hide()
	B.sub:Hide()
	B.sparks = {}
	B.ang, B.spd, B.life, B.size = {}, {}, {}, {}
	local seed = 7
	for i = 1, G.SPARKS do
		B.sparks[i] = Tex(LIGHT .. "spark_gold", "OVERLAY", 6, true)
		seed = (seed * 1664525 + 1013904223) % 4294967296
		local r = seed / 4294967296
		B.ang[i] = 2 * pi * (i + r * 0.8) / G.SPARKS
		B.spd[i] = 80 + 120 * r
		B.life[i] = 0.5 + 0.45 * ((i * 7) % 10) / 10
		B.size[i] = 9 + 7 * ((i * 3) % 10) / 10
	end
	B.arrive = Tex(LIGHT .. "ring_gold", "OVERLAY", 3, true)
	B.star = Tex(LIGHT .. "star_gold", "OVERLAY", 4, true)
end

-- a piece at a point in UIParent's units, w x h, alpha a (hidden at 0)
local function Place(r, x, y, w, h, a, rot)
	if not a or a <= 0.003 or w <= 0.05 or h <= 0.05 then
		r:Hide()
		return
	end
	r:ClearAllPoints()
	r:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	r:SetSize(w, h)
	r:SetAlpha(a > 1 and 1 or a)
	if rot then
		r:SetRotation(rot)
	end
	r:Show()
end

-- a piece of the moment: its flight (B.fs, B.fdx, B.fdy) and its shake (B.jx, B.jy) on it
local function Put(r, x, y, w, h, a, rot)
	local cx, cy, s = B.cx, B.cy, B.fs
	Place(r, cx + (x - cx) * s + B.fdx + B.jx, cy + (y - cy) * s + B.fdy + B.jy, w * s, h * s, a, rot)
end

local function PutText(fs, x, y, a)
	if not a or a <= 0.003 then
		fs:Hide()
		return
	end
	fs:ClearAllPoints()
	fs:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + B.jx, y + B.jy)
	fs:SetAlpha(a > 1 and 1 or a)
	fs:Show()
end

local function HideAll()
	for _, r in ipairs({ B.rays, B.glow, B.wave, B.seal, B.logo, B.faceL, B.ringL, B.faceR, B.ringR, B.rule, B.line,
		B.sub, B.arrive, B.star }) do
		r:Hide()
	end
	for i = 1, G.SPARKS do
		B.sparks[i]:Hide()
	end
	if B.band then
		B.band:SetShown(false)
	end
end

--------------------------------------------------------------------------------
-- The moment (a function of its time t, in seconds; the sketch's B, line for line)
--------------------------------------------------------------------------------

local function Sparks(t, x, y, a)
	for i = 1, G.SPARKS do
		local s = B.sparks[i]
		local tt = t - (i % 3) * 0.03
		if tt < 0 or tt > B.life[i] then
			s:Hide()
		else
			local d = 18 + B.spd[i] * (1 - exp(-3.2 * tt)) / 3.2
			local life = tt / B.life[i]
			local size = B.size[i] * (1 - 0.55 * life)
			Put(s, x + cos(B.ang[i]) * d, y + sin(B.ang[i]) * d - 30 * tt * tt, size, size, (1 - life) ^ 1.4 * a)
		end
	end
end

local function Draw(t)
	local cx, cy = B.cx, B.cy
	-- the flight after two seconds: every piece toward their frame, smaller, fading; no frame: a fade in place
	local f = B.toX and Seg(t, G.OUT, G.OUT + G.FLY) or 0
	local fe = f * f * f
	B.fs = 1 - 0.88 * fe
	B.fdx = B.toX and (B.toX - cx) * fe or 0
	B.fdy = B.toY and (B.toY - cy) * fe or 0
	local A0 = B.toX and (1 - fe) or (1 - Seg(t, G.OUT, G.OUT + G.FADE))
	local TA = A0 * (1 - Seg(f, 0, 0.35))   -- (the words, which do not shrink, go first)
	-- the stamp's shake
	local k = Seg(t, 0.9, 1.1)
	if k > 0 and k < 1 then
		B.jx, B.jy = 3 * sin(k * pi * 3) * (1 - k), 2 * cos(k * pi * 3) * (1 - k)
	else
		B.jx, B.jy = 0, 0
	end
	-- the band under it
	B.box:ClearAllPoints()
	B.box:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy - 28)
	B.box:SetSize(max(420, (B.lineW or 0) + 110), 230)
	if B.band then
		B.band:SetStrength(0.72 * Seg(t, 0, 0.3) * TA)
		B.band:SetShown(true)
	end
	-- the rule draws out from the middle
	local rp = OutCubic(Seg(t, 0.06, 0.58))
	Put(B.rule, cx, cy - G.RULE_Y, G.RULE * rp, 6, 0.85 * Seg(t, 0.06, 0.3) * A0)
	-- the two portraits slide together
	local pp = Seg(t, 0.12, 0.68)
	local pe = OutBack(pp, 1.3)
	local pa = Seg(t, 0.12, 0.32) * A0
	local off = G.FROM + (G.SPREAD - G.FROM) * pe
	Put(B.faceL, cx - off, cy, G.FACE, G.FACE, pa)
	Put(B.ringL, cx - off, cy, G.RING, G.RING, pa)
	Put(B.faceR, cx + off, cy, G.FACE, G.FACE, pa)
	Put(B.ringR, cx + off, cy, G.RING, G.RING, pa)
	-- the seal turns in and the logo is stamped on it
	local sp = Seg(t, 0.6, 1.02)
	local se = OutCubic(sp)
	Put(B.seal, cx, cy, G.SEAL * (0.6 + 0.4 * se), G.SEAL * (0.6 + 0.4 * se), sp * A0, -0.35 * (1 - se))
	local lp = Seg(t, 0.6, 0.9)
	local ls = lp < 0.7 and (1.7 - 0.76 * lp / 0.7) or (0.94 + 0.06 * (lp - 0.7) / 0.3)
	Put(B.logo, cx, cy, G.LOGO * ls, G.LOGO * ls, min(1, lp * 1.4) * A0)
	Put(B.glow, cx, cy, G.GLOW, G.GLOW, 0.32 * Seg(t, 0.75, 1.0) * (1 - 0.5 * Seg(t, 1.6, 2.6)) * A0)
	-- rays open once, a wave of light, sparks thrown out
	local yp = Seg(t, 0.86, 1.62)
	local ya = yp < 0.3 and yp / 0.3 or 1 - (yp - 0.3) / 0.7
	Put(B.rays, cx, cy, G.RAYS * (0.6 + 0.65 * yp), G.RAYS * (0.6 + 0.65 * yp), 0.9 * (yp > 0 and ya or 0) * A0, t * 0.15)
	local wp = Seg(t, 0.88, 1.78)
	Put(B.wave, cx, cy, G.WAVE * (0.6 + 1.1 * OutCubic(wp)), G.WAVE * (0.6 + 1.1 * OutCubic(wp)),
		0.8 * (wp > 0 and (1 - wp) or 0) * A0)
	Sparks(t - 0.88, cx, cy, A0)
	-- the words rise in under the rule
	local l1 = Seg(t, 0.96, 1.34)
	PutText(B.line, cx, cy - G.LINE_Y - 8 * (1 - OutCubic(l1)), l1 * TA)
	local l2 = Seg(t, 1.06, 1.44)
	PutText(B.sub, cx, cy - G.SUB_Y - 6 * (1 - OutCubic(l2)), l2 * TA)
	-- their frame lights as the moment lands in it
	if B.toX then
		local ap = Seg(t, G.OUT + G.FLY - 0.08, G.OUT + G.FLY - 0.08 + G.ARRIVE)
		Place(B.arrive, B.toX, B.toY, 52 * (0.6 + 0.65 * ap), 52 * (0.6 + 0.65 * ap), Hump(ap))
		Place(B.star, B.toX, B.toY, 40 * (0.5 + 0.7 * ap), 40 * (0.5 + 0.7 * ap), Hump(ap) * (1 - 0.5 * ap))
	end
end

--------------------------------------------------------------------------------
-- Playing: the players gathered for a moment, one moment at a time
--------------------------------------------------------------------------------

-- where it plays: the middle of the game's screen, G.DOWN of it under its top (MelloUI:PlayArea)
local function Middle()
	local l, b, w, h = MelloUI:PlayArea()
	l, b, w, h = Num(l) or 0, Num(b) or 0, Num(w) or 1024, Num(h) or 768
	return l + w / 2, b + h * (1 - G.DOWN)
end

-- where a member's frame shows them: its portrait end (the frame's left, a square of its height), in UIParent's
-- units; nil when it shows nowhere readable
local function FrameOf(unit)
	local frame
	local GF = rawget(MelloUI, "GroupFrames")
	if GF and GF.HostOf then
		local ok, host = pcall(GF.HostOf, GF, unit)
		frame = ok and type(host) == "table" and host.frame or nil
	end
	if not frame then
		local i = type(unit) == "string" and tonumber(unit:match("^party(%d)$"))
		local pf = rawget(_G, "PartyFrame")
		frame = i and type(pf) == "table" and pf["MemberFrame" .. i] or nil
	end
	if type(frame) ~= "table" or not (frame.IsVisible and frame:IsVisible()) then
		return nil
	end
	local l, b, r, t = Safe.ScreenRect(frame)
	local u = Num(UIParent:GetEffectiveScale())
	if not (l and u and u > 0 and r > l and t > b) then
		return nil
	end
	local h = (t - b) / u
	return l / u + min(h, (r - l) / u) / 2, b / u + h / 2
end

local function Hex(c)
	if type(c) ~= "table" then
		return "e0b53a"
	end
	return ("%02x%02x%02x"):format(math.floor((c[1] or 1) * 255 + 0.5), math.floor((c[2] or 1) * 255 + 0.5),
		math.floor((c[3] or 1) * 255 + 0.5))
end

local Done   -- (below)

local function Step(_, share)
	Draw(share * B.dur)
end

local function Start()
	Build()
	HideAll()
	local n = G.pN
	if n == 0 then
		return
	end
	B.cx, B.cy = Middle()
	B.fs, B.fdx, B.fdy, B.jx, B.jy = 1, 0, 0, 0, 0
	local unit = G.pUnit[1]
	pcall(SetPortraitTexture, B.faceL, "player")
	if not pcall(SetPortraitTexture, B.faceR, unit) then
		B.faceR:SetTexture(LOGO)
	end
	-- the words: the names in the selected trim's gold
	local gold = "|cff" .. Hex(MelloUI.Palette.selectedTrim) .. "%s|r"
	local text
	if n == 1 then
		text = W.Tr("%s uses MelloUI too"):format(gold:format(G.pName[1]))
	elseif n == 2 then
		text = W.Tr("%s and %s use MelloUI too"):format(gold:format(G.pName[1]), gold:format(G.pName[2]))
	elseif n == 3 then
		text = W.Tr("%s, %s and %s use MelloUI too"):format(gold:format(G.pName[1]), gold:format(G.pName[2]),
			gold:format(G.pName[3]))
	else
		text = W.Tr("%d players in your group use MelloUI"):format(n)
	end
	Face(B.line, G.NAME)
	Face(B.sub, G.SUB)
	B.line:SetText(text)
	B.sub:SetText(W.Tr("Now in your group"))
	B.lineW = Num(B.line:GetStringWidth()) or 300
	-- one player: the moment flies into their frame; several: it fades in place
	B.toX, B.toY = nil, nil
	if n == 1 and not MelloUI.Anim.reduceMotion then
		B.toX, B.toY = FrameOf(unit)
		if not (B.toX and B.toY) then
			B.toX, B.toY = nil, nil
		end
	end
	B.dur = B.toX and (G.OUT + G.FLY + G.ARRIVE) or (G.OUT + G.FADE)
	G.pN = 0
	G.playing = true
	-- (the easter egg) the first real moment reveals its switch on the Animations page (from the next layout)
	if G.real and M.db then
		M.db.revealed = true
	end
	G.real = false
	B.root:SetAlpha(1)
	B.root:Show()
	if MelloUI.Anim.reduceMotion then
		Draw(G.STILL)
		B.timer = C_Timer.NewTimer(G.HOLD, Done)
		return
	end
	MelloUI.Anim:Drive(B.root, Step, B.dur, "linear", Done)
end

Done = Shared("MelloUI Players: a moment ended", function()
	B.timer = nil
	HideAll()
	B.root:Hide()
	G.playing = false
	if G.pN > 0 and not G.mergeTimer then
		Start()   -- (players gathered while it played: their moment now)
	end
end)

local Flush = Shared("MelloUI Players: the gathered players' moment", function()
	G.mergeTimer = nil
	if not G.playing then
		Start()
	end
end)

-- a player to greet: kept for the next moment (gathered a moment longer, so several play as one)
local function Add(guid, unit, name)
	for i = 1, G.pN do
		if G.pGuid[i] == guid then
			return
		end
	end
	G.pN = G.pN + 1
	G.pGuid[G.pN], G.pUnit[G.pN], G.pName[G.pN] = guid, unit, name
	if not G.mergeTimer then
		G.mergeTimer = C_Timer.NewTimer(G.MERGE, Flush)
	end
end

Gather = function(guid, unit)
	local db = M.db
	if not (M.isEnabled and db and db.moment) then
		return   -- (the moment is off: the hello alone)
	end
	local now = time()
	db.greeted = type(db.greeted) == "table" and db.greeted or {}
	local last = Num(db.greeted[guid])
	if last and now - last < G.AGAIN then
		return
	end
	local name = Text(UnitName(unit))
	if not name then
		return
	end
	db.greeted[guid] = now
	G.real = true   -- (a real moment: once it plays, its switch is revealed)
	Add(guid, unit, name)
end

-- (the Animations page's Play, /mello grouped play) a sample: your group's first member, else yourself
function G.Play(unit, name)
	if not unit then
		unit = "player"
		for i = 1, 4 do
			if UnitExists(PARTY[i]) then
				unit = PARTY[i]
				break
			end
		end
	end
	name = name or Text(UnitName(unit)) or "Mello"
	Add("sample:" .. unit, unit, name)
	return true
end

M.Plays = {
	moment = function()
		if not M.isEnabled then
			return false
		end
		G.Play()
		return true, G.MERGE + G.OUT + G.FLY + G.ARRIVE
	end,
}

M.SlashWords = {
	play = M.Plays.moment,
	-- what it heard and sent, and the group as it reads it (to send with /mellolog)
	why = function()
		local n = 0
		for _ in pairs(G.roster) do
			n = n + 1
		end
		MelloUI:Print("MelloUI Players: %d in the group as read, the moment %s, in a group %s", n,
			Tr((M.db and M.db.moment) and "on" or "off"), Tr(G.inGroup and "yes" or "no"))
		for k = max(1, G.lastN - 11), G.lastN do
			MelloUI:Print("  %s", tostring(G.last[(k - 1) % 12 + 1]))
		end
	end,
}

--------------------------------------------------------------------------------
-- Enable / disable
--------------------------------------------------------------------------------

function M:OnEnable(db)
	self.db = db
	local reg = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix
	if type(reg) == "function" then
		pcall(reg, G.PREFIX)
	end
	-- the greeted players older than the wait: let go
	if type(db.greeted) == "table" then
		local now = time()
		for guid, at in pairs(db.greeted) do
			if not Num(at) or now - Num(at) > G.AGAIN then
				db.greeted[guid] = nil
			end
		end
	end
	if not eventFrame then
		eventFrame = CreateFrame("Frame")
		eventFrame:SetScript("OnEvent", OnEvent)
	end
	G.me = Text(UnitGUID("player")) or G.me
	eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
	eventFrame:RegisterEvent("CHAT_MSG_ADDON")
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	-- (switched on after the login: the group as it stands now, nothing sent)
	G.seedUntil = GetTime() + 0.5
	OnRoster()
end

function M:OnDisable()
	if eventFrame then
		eventFrame:UnregisterAllEvents()
	end
	if G.retryTimer then
		G.retryTimer:Cancel()
		G.retryTimer = nil
	end
	if G.mergeTimer then
		G.mergeTimer:Cancel()
		G.mergeTimer = nil
	end
	G.pN = 0
	if B.root then
		if B.timer then
			B.timer:Cancel()
			B.timer = nil
		end
		MelloUI.Anim:Stop(B.root, "drive")
		HideAll()
		B.root:Hide()
	end
	G.playing = false
end

function M:OnSettingChanged(_, _, db)
	self.db = db
end

-- (the tests')
G.B, G.M, G.OnEvent, G.Draw, G.Start = B, M, OnEvent, Draw, Start
