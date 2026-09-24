--------------------------------------------------------------------------------
-- MelloUI - Guild Panel
--
-- The Guild & Communities window (CommunitiesFrame: the communities list,
-- the chat, roster, guild benefits and guild info pages) dressed in the
-- painted kit (Modules/Kit.lua) on the game's own layout, as the character,
-- professions and spell book windows are: every kit piece stands in for one
-- of the game's art regions, on that region's rectangle, as a child (or
-- region) of its frame, faded in place of it (docs/WINDOW-RULES.md).
--
-- Most of this window's art is file textures (the GuildFrame and
-- bluemenu sheets), which this client reads back as numeric ids: every
-- piece is keyed by hand from the templates (Blizzard_Communities/*.xml).
--
-- State (2026-09-21): the window shell (outer rail, page stone, title,
-- close, maximize / minimize, the ring on the portrait), the inset, the
-- side tabs, the communities list (box, entries, selection, icon rings),
-- the member list (inset, rows, profession headers, offline check box),
-- the chat (inset, edit box), the dropdowns, the red buttons, the guild
-- reputation bar (P1) and the scroll bars are on the kit. Pending the
-- user's picks (kit_raw/guild_catalog.png): the roster's column headers,
-- the guild info / news / perks / rewards pages' own art. /gdump lists the art.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("GuildPanel")
local hooksecurefunc = Perf.hooksecurefunc
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("GuildPanel", {
	title = "Guild Panel",
	desc = "The guild and communities window dressed in the painted kit on the game's own layout.",
	enabledByDefault = true,
	defaults = {},
	options = {},
})

local skin = nil
local active = false
local hooked = false

local function IsActive()
	return active
end

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Guild panel: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

-- A rep shown while the game shows `region` (art the game toggles itself).
local function Follow(rep, region)
	if not (rep and region) then
		return
	end
	local function Sync()
		if active then
			rep:SetShown(region:IsShown())
		end
	end
	hooksecurefunc(region, "Show", Sync)
	hooksecurefunc(region, "Hide", Sync)
	hooksecurefunc(region, "SetShown", Sync)
	skin.followers[#skin.followers + 1] = { rep = rep, region = region }
	Sync()
end

-- The portrait art: the community's avatar, or the guild's tabard (three
-- textures the game shows instead), all on the corner; each is fitted into
-- the ring like the class medallion.
local function PortraitTextures()
	local ov = CommunitiesFrame and CommunitiesFrame.PortraitOverlay
	if not ov then
		return {}
	end
	return { ov.Portrait, ov.TabardBackground, ov.TabardEmblem, ov.TabardBorder }
end

-- The level a holder under `parent` needs to sit at the level of `frame`
-- (a game inset at a fixed high level, e.g. 100 or 200, over its list's rows):
-- relative to `parent`, as Kit:Replace takes it.
local function LevelAbove(parent, frame)
	local ok, a, b = pcall(function() return frame:GetFrameLevel(), parent:GetFrameLevel() end)
	if ok and a and b and not (issecretvalue and (issecretvalue(a) or issecretvalue(b))) then
		return math.max(a - b, 1)
	end
	return 5
end

-- The eye-strain panel (WINDOW-RULES 2e; user, 2026-09-24: "too much small
-- text over a plain brown border is just an eye strain" / "apply the eye
-- strain rule to all existing windows"): the palette's inner panel laid over
-- the stone under an area that is mostly text (Kit:StoneDim), as a REGION of
-- `host`, the frame that holds that text: under the host's own children (the
-- rows, the messages) and above the window's page stone, which is a region of
-- the window at a lower frame level. A frame of ours at the host's level
-- would tie with the host's own regions (a header plate, a label) and could
-- draw over them. A tint over the one stone, never a second stone; shown only
-- while the skin is on.
local function EyePanel(host, opts)
	if not (host and Kit.StoneDim) or skin.eyePanels[host] ~= nil then
		return
	end
	local tex = Kit:StoneDim(host, opts)
	skin.eyePanels[host] = tex or false
	if tex then
		-- ours: never taken for the game's art (the info page's sheets are
		-- found as its tall BACKGROUND textures and faded)
		tex.kitPiece = true
		tex:SetShown(active)
	end
end

-- The distance from an inset rail's outer edge to its centre line: a panel
-- inside a rail starts there, so the rail's inner half lies over its edge
-- and no brown seam shows between them.
local function RailMargin()
	return Kit:RailInset(Kit.framePrefix .. "_l", "l")
end

-- A card lying on a dimmed list (the communities list's entries) takes the
-- main window's tone over its stone: a row a step lighter than the panel
-- around it, as 2e stripes rows.
local CARD_TONE = MelloUI.Palette and MelloUI.Palette.mainWindow

-- A text dropdown (WowStyle1DropdownTemplate: Background textholder, Arrow,
-- Text): the dropdown plate (D1) on the button, its painted cap in place of
-- the arrow, hover from the button.
local function SkinDropdown(dd)
	if not (dd and dd.Background) or dd.melloRep ~= nil then
		return
	end
	dd.melloRep = Replace(dd.Background, { as = "common-dropdown-textholder", rect = dd, button = dd, alsoFade = { dd.Arrow } }) or false
end

--------------------------------------------------------------------------------
-- The communities list (left column): its box, its pooled entries.
--------------------------------------------------------------------------------
local function SkinListEntry(entry)
	if entry.melloRep ~= nil then
		return
	end
	entry.melloRep = false
	if entry.Background then
		-- a tall row (R3): the card, lit while the game shows the Selection
		local highlight = entry.GetHighlightTexture and entry:GetHighlightTexture()
		-- the card's stone in the main window's tone (2e: its name must not
		-- lie on the plain stone; a step lighter than the dimmed list box)
		entry.melloRep = Replace(entry.Background, { as = "CommunitiesListEntry", rect = entry, button = entry,
			dim = CARD_TONE and 0.85 or nil, dimColor = CARD_TONE,
			checked = function() return entry.Selection and entry.Selection:IsShown() or false end,
			alsoFade = highlight and { highlight } or nil }) or false
	end
	if entry.Selection then
		Replace(entry.Selection, { as = "bluemenu-main-selected" })
		local function Sync()
			if active and entry.melloRep and entry.melloRep.SetState then
				entry.melloRep:SetState()
			end
		end
		hooksecurefunc(entry.Selection, "Show", Sync)
		hooksecurefunc(entry.Selection, "Hide", Sync)
		hooksecurefunc(entry.Selection, "SetShown", Sync)
	end
	if entry.IconRing and entry.Icon then
		-- the ring's opening is the icon (38 px, masked round by the game)
		entry.melloRim = Kit:RimRect(entry, "roundslot", entry.Icon:GetWidth() > 0 and entry.Icon:GetWidth() or 38, entry.Icon)
		local rep = Replace(entry.IconRing, { as = "communities-ring-gold", rect = entry.melloRim, button = entry })
		Follow(rep, entry.IconRing)
	end
end

--------------------------------------------------------------------------------
-- The member list (roster): its inset, its pooled rows (a row plate on the
-- normal texture; a profession header's category plate and +/- glyphs).
--------------------------------------------------------------------------------
local function SkinMemberRow(row)
	if row.melloRep ~= nil then
		return
	end
	row.melloRep = false
	local normal = row.GetNormalTexture and row:GetNormalTexture()
	if normal then
		local highlight = row.GetHighlightTexture and row:GetHighlightTexture()
		row.melloRep = Replace(normal, { as = "bluemenu-main", rect = row, button = row, alsoFade = highlight and { highlight } or nil }) or false
	end
	local header = row.ProfessionHeader
	if header and header.Middle then
		Replace(header.Middle, { as = "common-button-list-collapseExpand", rect = header, button = header, alsoFade = { header.Left, header.Right } })
		for _, entry in ipairs({ { header.CollapsedIcon, "common-button-list-plus" }, { header.ExpandedIcon, "common-button-list-minus" } }) do
			local icon, key = entry[1], entry[2]
			if icon then
				Follow(Replace(icon, { as = key, button = header, rect = icon }), icon)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The guild reputation bar (CommunitiesGuildProgressBarTemplate: Left /
-- Middle / Right art, BG, a Progress texture the game widens to its value):
-- P1 on the BG with the fill moved into the bracket's opening (its width
-- scaled from the game's frame-based value onto the opening's width).
--------------------------------------------------------------------------------
local function SkinFactionBar(bar)
	if not (bar and bar.BG and bar.Progress) or bar.melloRep ~= nil then
		return
	end
	local rep = Replace(bar.BG, { as = "GuildFrame-Bar", rect = bar, alsoFade = { bar.Left, bar.Middle, bar.Right, bar.Shadow } })
	bar.melloRep = rep or false
	if not rep then
		return
	end
	local fill = bar.Progress
	local saved = { h = fill:GetHeight() }
	for i = 1, fill:GetNumPoints() do
		saved[i] = { fill:GetPoint(i) }
	end
	local fitting = false
	local function FitFill()
		if not active then
			return
		end
		local l, r, t, b = rep:GetOpening()
		local w, h = bar:GetSize()
		if not (w and w > 0) then
			return
		end
		local maxBar = w - 4                     -- the game's maxBarWidth (SetProgress)
		local okW, fw = pcall(fill.GetWidth, fill)
		local pct = (okW and fw and not (issecretvalue and issecretvalue(fw)) and maxBar > 0) and math.min(fw / maxBar, 1) or 0
		fill:ClearAllPoints()
		fill:SetPoint("LEFT", bar, "LEFT", l, (b - t) / 2)
		fill:SetHeight(h - t - b)
		fitting = true
		fill:SetWidth(math.max(pct * (w - l - r), 0.001))
		fitting = false
	end
	rep.onEnable = function()
		rep:Refit()
		FitFill()
	end
	rep.onDisable = function()
		fill:ClearAllPoints()
		for i = 1, #saved do
			fill:SetPoint(unpack(saved[i]))
		end
		if saved.h and saved.h > 0 then
			fill:SetHeight(saved.h)
		end
	end
	hooksecurefunc(fill, "SetWidth", function()
		if active and not fitting then
			FitFill()
		end
	end)
end

--------------------------------------------------------------------------------
-- Building the skin
--------------------------------------------------------------------------------
local function BuildSkin()
	if skin then
		return skin
	end
	local cf = CommunitiesFrame
	skin = CreateFrame("Frame", "MelloUIGuildSkin", cf)
	skin:SetAllPoints()
	skin:SetFrameLevel(cf:GetFrameLevel())
	skin:EnableMouse(false)
	skin.reps = {}
	skin.followers = {}
	skin.eyePanels = setmetatable({}, { __mode = "k" })   -- [text area] = its inner panel (EyePanel)
	skin.Replace = Replace

	-- the window: outer rail, page stone on the rock, streaks, the ring on
	-- the portrait corner, title, close, maximize / minimize
	Kit:SkinWindowShell(cf, Replace, skin, { portrait = cf.PortraitOverlay and cf.PortraitOverlay.Portrait, bg = "UI-Background-Rock" })
	-- the guild's tabard does not cover the ring's opening: the dark disc behind it (WINDOW-RULES 2b)
	Kit:RingDisc(skin.ring, nil, cf.PortraitOverlay, 0)
	-- the inset (ButtonFrameTemplate's InsetFrameTemplate): the single rail
	-- under everything at the window's level. Without the rule's inner panel
	-- (2e, user 2026-09-24): its holder lies a level under the window, whose
	-- page stone is a region of the window itself, so a panel there would
	-- not be seen; each text area below gets its own (EyePanel) instead, and
	-- one here would double them if it ever showed
	if cf.Inset then
		cf.Inset.melloRep = Replace(cf.Inset, { as = "common-insideframe", parent = cf, rect = cf.Inset, level = -1, dim = false }) or false
	end
	-- the side tabs (RightSideTabTemplate: the 64 px tab plate, the icon)
	for _, key in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "GuildPreferredPlaySettingsTab" }) do
		local tab = cf[key]
		if tab and tab.Icon then
			local plate = Kit:FirstTexture(tab)
			if plate and plate ~= tab.Icon then
				local extra = {}
				for _, region in ipairs({ tab:GetRegions() }) do
					if region:GetObjectType() == "Texture" and region ~= plate and region ~= tab.Icon and not region.kitPiece then
						extra[#extra + 1] = region
					end
				end
				Replace(plate, { as = "common-sidetab", button = tab, parent = tab, rect = tab, icon = tab.Icon,
					checked = function() return tab:GetChecked() end, alsoFade = extra })
			end
		end
	end

	-- the communities list: the box (L1) in two parts — the stone body as a
	-- region of the list under its rows, the rail on the InsetFrame's rect at
	-- that frame's own level (200), OVER the rows (user, 2026-09-21: the
	-- border was behind the bars)
	local list = cf.CommunitiesList
	if list then
		if list.Bg then
			Replace(list.Bg, { as = "CommunitiesListBody", alsoFade = { list.TopFiligree, list.BottomFiligree } })
		end
		local extra = {}
		local overlay = list.FilligreeOverlay
		if overlay then
			for _, region in ipairs({ overlay:GetRegions() }) do
				if region:GetObjectType() == "Texture" then
					extra[#extra + 1] = region
				end
			end
		end
		if list.InsetFrame then
			list.InsetFrame.melloRep = Replace(list.InsetFrame, { as = "CommunitiesListBox", parent = list, rect = list.InsetFrame, level = LevelAbove(list, list.InsetFrame), alsoFade = extra }) or false
		end
		-- the list box's stone under the inner panel (2e): a region of the
		-- list over its body tile (ARTWORK 1, the game's Bg sublevel) and
		-- under its entries, inside the rail
		EyePanel(list, { rect = list.InsetFrame or list, margin = RailMargin(), layer = "ARTWORK", sublevel = 2 })
		Kit:HookScrollBoxRows(list.ScrollBox, SkinListEntry, IsActive)
	end
	SkinDropdown(cf.CommunitiesListDropdown)
	SkinDropdown(cf.StreamDropdown)
	SkinDropdown(cf.GuildMemberListDropdown)
	SkinDropdown(cf.CommunityMemberListDropdown)
	SkinDropdown(cf.AddToChatButton)

	-- the member list
	local members = cf.MemberList
	if members then
		if members.InsetFrame then
			-- the rail at the inset's own level (100), over the rows: edges
			-- only (the rule's stone body would cover them; the game's inset
			-- has no body here either)
			members.InsetFrame.melloRep = Replace(members.InsetFrame, { as = "common-insideframe", parent = members, rect = members.InsetFrame, level = LevelAbove(members, members.InsetFrame), body = false }) or false
			-- ... so the inner panel (2e) is a region of the member list
			-- itself, under its rows and watermark, inside that rail (the
			-- roster's rows lay on the page's stone between their plates)
			EyePanel(members, { rect = members.InsetFrame, margin = RailMargin() })
		end
		local columns = members.ColumnDisplay
		if columns then
			if columns.Background then
				Replace(columns.Background, { as = "UI-Background-Rock" })
			end
			if columns.TopTileStreaks then
				Replace(columns.TopTileStreaks, { as = "_UI-Frame-TopTileStreaks", parent = columns })
			end
		end
		Kit:SkinCheckButton(members.ShowOfflineButton, Replace, "UI-CheckBox-Up")
		if members.ScrollBar and members.ScrollBar.Background then
			Replace(members.ScrollBar.Background, { as = "UI-Background-Marble" })
		end
		Kit:HookScrollBoxRows(members.ScrollBox, SkinMemberRow, IsActive)
	end

	-- the chat
	local chat = cf.Chat
	if chat and chat.InsetFrame then
		chat.InsetFrame.melloRep = Replace(chat.InsetFrame, { as = "common-insideframe", parent = chat, rect = chat.InsetFrame, level = LevelAbove(chat, chat.InsetFrame), body = false }) or false
		-- the messages on the inner panel (2e), a region of the chat under
		-- its message frame, on the inset's rect (which the game keeps round
		-- the chat when it hides the inset in the minimized window)
		EyePanel(chat, { rect = chat.InsetFrame, margin = RailMargin() })
	end
	-- the guild chat's input line: the edit plate's middle only (no search
	-- glass — it is a chat line, not a search box; user, 2026-09-21)
	local edit = cf.ChatEditBox
	if edit and edit.Mid then
		Replace(edit.Mid, { as = "UI-ChatInputBorder-Mid2", rect = edit, edit = edit, capless = true, alsoFade = { edit.Left, edit.Right } })
	end
	Kit:SkinRedButton(_G.JumpToUnreadButton, Replace)

	-- the buttons
	for _, key in ipairs({ "InviteButton", "GuildLogButton" }) do
		Kit:SkinRedButton(cf[key], Replace)
	end
	local control = cf.CommunitiesControlFrame
	if control then
		for _, key in ipairs({ "CommunitiesSettingsButton", "GuildControlButton", "GuildRecruitmentButton" }) do
			Kit:SkinRedButton(control[key], Replace)
		end
	end

	-- the guild benefits page: the reputation bar (the rest after the dump)
	local benefits = cf.GuildBenefitsFrame
	if benefits and benefits.FactionFrame then
		SkinFactionBar(benefits.FactionFrame.Bar)
	end

	-- the roster's column band: its loose inset-border pieces faded (the
	-- member list's rail frames the band); the column buttons on header
	-- plates (GC1), re-skinned whenever the game lays the columns out
	if members and members.ColumnDisplay then
		local columns = members.ColumnDisplay
		for _, key in ipairs({ "InsetBorderTopLeft", "InsetBorderTopRight", "InsetBorderBottomLeft", "InsetBorderTop", "InsetBorderLeft" }) do
			if columns[key] then
				Replace(columns[key], { as = "UI-Frame-InnerBorderPiece" })
			end
		end
		local function SkinColumns()
			for _, button in ipairs({ columns:GetChildren() }) do
				if button.Middle and button.Left and button.Right and button.melloRep == nil then
					local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
					-- cap-less on every column: the one wide column (Note) took
					-- the caps, its gem under the text, while the narrow ones could not
					button.melloRep = Replace(button.Middle, { as = "ColumnDisplayButton", rect = button, button = button, capless = true,
						alsoFade = { button.Left, button.Right, highlight } }) or false
				end
			end
		end
		if columns.LayoutColumns then
			hooksecurefunc(columns, "LayoutColumns", function()
				if active then
					SkinColumns()
				end
			end)
		end
		SkinColumns()
	end

	-- the guild info page (GuildDetailsFrame: the Info column, the News column):
	-- the two columns' loose inset borders faded but the shared vertical
	-- line, which is the pane divider; the sheet backgrounds faded; the
	-- horizontal bars are divider lines; the headers wait for the GH pick
	local details = cf.GuildDetailsFrame
	if details then
		for _, key in ipairs({ "InsetBorderTopLeft", "InsetBorderTopRight", "InsetBorderBottomLeft", "InsetBorderBottomRight", "InsetBorderLeft",
			"InsetBorderTopLeft2", "InsetBorderBottomLeft2", "InsetBorderLeft2" }) do
			if details[key] then
				Replace(details[key], { as = "UI-Frame-InnerBorderPiece" })
			end
		end
		if details.InsetBorderRight then
			Replace(details.InsetBorderRight, { as = "common-framedivider" })
		end
		local info = details.Info
		-- the two columns' text (the message of the day, the guild's details,
		-- the news) on the inner panel (2e) now that their sheets are faded:
		-- a region of each column under everything the column holds, below
		-- the header plates (BACKGROUND 2, owner strips) at sublevel -1; each
		-- column's own rect, so the divider between them stays clear
		for _, column in ipairs({ info, details.News }) do
			EyePanel(column, { rect = column, sublevel = -1 })
		end
		if info then
			local name = info:GetName() or ""
			-- each horizontal bar is TWO textures (a left and a right piece):
			-- one divider strip across both, following the left piece's
			-- visibility (the challenges section is hidden in this client)
			local bars = {}
			for _, region in ipairs({ info:GetRegions() }) do
				if region:GetObjectType() == "Texture" and not region.kitPiece then
					local layer = region:GetDrawLayer()
					local h = region:GetHeight()
					if layer == "ARTWORK" and h and h > 0 and h <= 20 then
						bars[#bars + 1] = region
					elseif layer == "BACKGROUND" and region ~= info.Header1 and region ~= _G[name .. "Header2"] and region ~= _G[name .. "Header3"] and region ~= info.BG and h and h > 100 then
						Replace(region, { as = "GuildFrame-Sheet" })
					end
				end
			end
			-- pair the pieces by their row (the same top), left piece first
			table.sort(bars, function(a, b)
				local at, bt = a:GetTop() or 0, b:GetTop() or 0
				if math.abs(at - bt) > 2 then
					return at > bt
				end
				return (a:GetLeft() or 0) < (b:GetLeft() or 0)
			end)
			local i = 1
			while i <= #bars do
				local left, right = bars[i], bars[i + 1]
				if right and math.abs((left:GetTop() or 0) - (right:GetTop() or 0)) <= 2 then
					local span = CreateFrame("Frame", nil, info)
					span:EnableMouse(false)
					span:SetPoint("TOPLEFT", left, "TOPLEFT")
					span:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT")
					Follow(Replace(left, { as = "UI-ClassTrainer-HorizontalBar", rect = span, alsoFade = { right } }), left)
					i = i + 2
				else
					Follow(Replace(left, { as = "UI-ClassTrainer-HorizontalBar", rect = left }), left)
					i = i + 1
				end
			end
		end
		-- the page headers (GH1): the header plate under their text
		if info then
			local name = info:GetName() or ""
			for _, header in ipairs({ info.Header1, _G[name .. "Header2"], _G[name .. "Header3"] }) do
				if header then
					Follow(Replace(header, { as = "GuildFrame-Header", rect = header }), header)
				end
			end
		end
		local news = details.News
		if news then
			for _, region in ipairs({ news:GetRegions() }) do
				if region:GetObjectType() == "Texture" and not region.kitPiece and region ~= news.Header and region:GetDrawLayer() == "BACKGROUND" and (region:GetHeight() or 0) > 100 then
					Replace(region, { as = "GuildFrame-Sheet" })
				end
			end
			if news.Header then
				Replace(news.Header, { as = "GuildFrame-Header", rect = news.Header })
			end
			if news.ScrollBar and news.ScrollBar.Background then
				Replace(news.ScrollBar.Background, { as = "UI-Background-Marble" })
			end
			-- the news rows (GP1): the plain plate, hover from the row; the blue highlight faded
			Kit:HookScrollBoxRows(news.ScrollBox, function(row)
				if row.melloRep == nil then
					local highlight = row.GetHighlightTexture and row:GetHighlightTexture()
					local anchor = highlight or row.header
					row.melloRep = anchor and Replace(anchor, { as = "GuildNewsRow", rect = row, button = row, noFade = anchor ~= highlight,
						alsoFade = highlight and anchor ~= highlight and { highlight } or nil }) or false
				end
			end, IsActive)
		end
	end

	-- the preferred play settings page: two old-style dropdowns (D1 on the
	-- box in the middle of their 64 px art, the arrow button faded), Apply buttons
	local prefs = cf.GuildPreferredPlaySettingsFrame
	if prefs then
		-- a page of settings (title, labels, dropdowns) on the inner panel
		-- (2e), a region of the page under its labels (ARTWORK) and controls
		EyePanel(prefs, { rect = prefs })
		for _, key in ipairs({ "LocaleDropdown", "DatacenterDropdown" }) do
			local dd = prefs[key]
			if dd and dd.melloRep == nil then
				local middle, extra = nil, {}
				for _, region in ipairs({ dd:GetRegions() }) do
					if region:GetObjectType() == "Texture" then
						if not middle and region:GetWidth() > 100 then
							middle = region
						else
							extra[#extra + 1] = region
						end
					end
				end
				for _, child in ipairs({ dd:GetChildren() }) do
					for _, region in ipairs({ child:GetRegions() }) do
						if region:GetObjectType() == "Texture" then
							extra[#extra + 1] = region
						end
					end
				end
				dd.melloRep = middle and Replace(middle, { as = "UIDropDownMenu", rect = dd, fitHeight = 24, alsoFade = extra }) or false
			end
		end
	end

	-- every common control left (scroll bars, the info page's scroll frames,
	-- the settings page's Apply buttons); explicit reps above carry melloRep
	Kit:SweepControls(cf, Replace, skin)

	return skin
end

function M:RefreshFollowers()
	if not (skin and active) then
		return
	end
	for _, f in ipairs(skin.followers) do
		f.rep:SetShown(f.region:IsShown())
	end
	Kit:SweepControls(CommunitiesFrame, Replace, skin)
	for _, tex in ipairs(PortraitTextures()) do
		Kit:FitPortrait(tex, skin.ring)
	end
end

local function Activate()
	if active or not CommunitiesFrame then
		return
	end
	BuildSkin()
	active = true
	skin:Show()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	for _, tex in pairs(skin.eyePanels) do
		if tex then
			tex:Show()
		end
	end
	M:RefreshFollowers()
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	skin:Hide()
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	for _, tex in pairs(skin.eyePanels) do
		if tex then
			tex:Hide()
		end
	end
	for _, tex in ipairs(PortraitTextures()) do
		Kit:UnfitPortrait(tex)
	end
end

-- Dressed on the window's first open (user, 2026-09-24: "dress rarely used
-- windows on first open"): Blizzard_Communities is loaded at login on this
-- client (no LoadOnDemand in its TOC), but nothing of the look is built while
-- the window has never been shown. Its OnShow (Hook) builds it before the
-- first frame is drawn, and it then stays built for the session, switched
-- with the module. In combat too: the skin adds frames and textures of ours,
-- fits the portrait, sizes the side tabs and lays the reputation bar's fill
-- into its bracket, none of it secure.
local function Sync()
	local cf = CommunitiesFrame
	if M.isEnabled and cf and (skin or cf:IsShown()) then
		Activate()
	else
		Deactivate()
	end
end

local function Hook()
	if hooked or not CommunitiesFrame then
		return
	end
	hooked = true
	Perf.HookScript(CommunitiesFrame, "OnShow", function()
		Sync()
		M:RefreshFollowers()
	end)
	if CommunitiesFrame.SetDisplayMode then
		hooksecurefunc(CommunitiesFrame, "SetDisplayMode", function() M:RefreshFollowers() end)
	end
	if CommunitiesFrame.UpdatePortrait then
		hooksecurefunc(CommunitiesFrame, "UpdatePortrait", function() M:RefreshFollowers() end)
	end
end

-- Blizzard_Communities is loaded at login on this client; the event is the
-- fallback should it ever come later.
local eventFrame = CreateFrame("Frame")
Perf.SetScript(eventFrame, "OnEvent", function(_, _, addon)
	if addon == "Blizzard_Communities" and M.isEnabled then
		Hook()
		Sync()
	end
end)

function M:OnEnable(db)
	self.db = db
	if CommunitiesFrame then
		Hook()
		Sync()
	else
		eventFrame:RegisterEvent("ADDON_LOADED")
	end
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /gdump: the window's art (regions by default; "frames", "reps"). Opens
-- the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOGDUMP1 = "/gdump"
SlashCmdList.MELLOGDUMP = function(msg)
	if not CommunitiesFrame then
		MelloUI:Print("Guild window not loaded.")
		return
	end
	MelloUI:ClearLog()
	if not skin then
		MelloUI:Print("Guild window not dressed yet (it is dressed on its first open): the game's own art only.")
	end
	Kit:DumpWindow(CommunitiesFrame, skin, msg)
	MelloUI:ShowLog("gdump " .. (msg or ""))
end
