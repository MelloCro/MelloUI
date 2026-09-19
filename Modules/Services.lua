--------------------------------------------------------------------------------
-- MelloUI - Services
--
-- A button on the minimap that leads you to the nearest repair, mailbox,
-- innkeeper, flight master, auction house, bank, trainer, barber or
-- transmogrifier. Vanilla service NPCs and mailboxes come from the Quest
-- List data (placed by the client), flight masters from the flight point
-- data, and anything new (Forever's barbers and transmogrifiers, NPCs the
-- database does not know) is remembered the first time you use it. "Nearest"
-- is by route cost through the Route module, so a flight master across the
-- river is not "near" when the bridge is a long way round.
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI

local M = MelloUI:RegisterModule("Services", {
	title = "Services",
	desc = "Minimap button that routes you to the nearest repair, mailbox, innkeeper, flight master, auction house, bank, trainer, barber or transmogrifier.",
	enabledByDefault = true,
	defaults = {
		showBar = true,
		barOffset = -26,
		showButton = false,
		angle = 205,
	},
	options = {
		{ type = "toggle", key = "showBar", name = "Icon Bar Under The Minimap",
		  desc = "Two rows of service icons under the minimap; it moves with the minimap in Edit Mode. Click an icon to route to the nearest one, right-click to stop the route." },
		{ type = "slider", key = "barOffset", name = "Bar Distance From The Minimap", min = -80, max = 20, step = 2 },
		{ type = "toggle", key = "showButton", name = "Minimap Button",
		  desc = "Also show the round button on the minimap edge that opens the list. /services opens the same list." },
	},
})

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function IsSecret(v)
	return issecretvalue and issecretvalue(v)
end

local function Plain(v)
	if v == nil or IsSecret(v) then
		return nil
	end
	return v
end

local function VectorXY(pos)
	if type(pos) ~= "table" then
		return nil, nil
	end
	local x, y = Plain(pos.x), Plain(pos.y)
	if (x == nil or y == nil) and type(pos.GetXY) == "function" then
		local ok, gx, gy = pcall(pos.GetXY, pos)
		if ok then
			x, y = Plain(gx), Plain(gy)
		end
	end
	return x, y
end

local function Route()
	local R = MelloUI.Route
	if R and R.isEnabled and R.Cheapest then
		return R
	end
	return nil
end

local function Data()
	return MelloUI_QuestListData
end

local function Yards(d)
	if d >= 1000 then
		return string.format("%.1f km", d / 1000)
	end
	return string.format("%d yd", d)
end

local function PlayerMapPoint()
	local okM, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	mapID = okM and Plain(mapID) or nil
	if not mapID then
		return nil
	end
	local okP, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	local x, y
	if okP then
		x, y = VectorXY(pos)
	end
	if not (x and y) then
		return nil
	end
	return mapID, x, y
end

local function NPCName()
	for _, unit in ipairs({ "npc", "target" }) do
		local ok, name = pcall(UnitName, unit)
		if ok and type(name) == "string" and not IsSecret(name) and name ~= "" then
			return name
		end
	end
	return nil
end

-- The NPC's title line ("Warrior Trainer") from its tooltip.
local function NPCSubName()
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return ""
	end
	local ok, data = pcall(C_TooltipInfo.GetUnit, "npc")
	if ok and type(data) == "table" and type(data.lines) == "table" and data.lines[2] then
		local text = Plain(data.lines[2].leftText)
		if type(text) == "string" and not text:find("^Level ") then
			return text
		end
	end
	return ""
end

--------------------------------------------------------------------------------
-- Kinds
--------------------------------------------------------------------------------

local KINDS = {
	{ key = "repair", label = "Repair", data = "repair", event = "MERCHANT_SHOW", icon = "Interface/Minimap/Tracking/Repair" },
	{ key = "mailbox", label = "Mailbox", data = "mailbox", event = "MAIL_SHOW", object = true, icon = "Interface/Minimap/Tracking/Mailbox" },
	{ key = "innkeeper", label = "Innkeeper", data = "innkeeper", icon = "Interface/Minimap/Tracking/Innkeeper" },
	{ key = "flight", label = "Flight Master", taxi = true, event = "TAXIMAP_OPENED", icon = "Interface/Minimap/Tracking/FlightMaster" },
	{ key = "auction", label = "Auction House", data = "auction", event = "AUCTION_HOUSE_SHOW", icon = "Interface/Minimap/Tracking/Auctioneer" },
	{ key = "banker", label = "Bank", data = "banker", event = "BANKFRAME_OPENED", icon = "Interface/Minimap/Tracking/Banker" },
	{ key = "classtrainer", label = "Class Trainer", data = "trainer", trainer = "class", icon = "Interface/Minimap/Tracking/Class" },
	{ key = "proftrainer", label = "Profession Trainer", data = "trainer", trainer = "profession", icon = "Interface/Minimap/Tracking/Profession" },
	{ key = "barber", label = "Barber", event = "BARBER_SHOP_OPEN", icon = "Interface/Minimap/Tracking/BarberShop" },
	{ key = "transmog", label = "Transmogrifier", event = "TRANSMOGRIFY_OPEN", icon = "Interface/Minimap/Tracking/Transmogrifier" },
}

local function PlayerSide()
	return UnitFactionGroup("player") == "Horde" and 2 or 1
end

-- Lower-cased stems of the player's professions ("leat", "blac", "mini"...).
local function ProfessionStems()
	local stems = {}
	if GetProfessions and GetProfessionInfo then
		local ok, a, b, c, d, e, f = pcall(GetProfessions)
		if ok then
			for _, index in ipairs({ a, b, c, d, e, f }) do
				if index then
					local okI, name = pcall(GetProfessionInfo, index)
					if okI and type(name) == "string" and not IsSecret(name) then
						stems[#stems + 1] = name:lower():sub(1, 4)
					end
				end
			end
		end
	end
	return stems
end

local function TrainerMatches(kind, sub)
	sub = (sub or ""):lower()
	if kind.trainer == "class" then
		local class = UnitClass("player")
		return type(class) == "string" and sub:find(class:lower() .. " trainer", 1, true) ~= nil
	end
	-- Profession trainer: one of the player's professions, else any trade one.
	local stems = ProfessionStems()
	if #stems == 0 then
		return not sub:find(" trainer") or sub:find("journeyman") or sub:find("expert") or sub:find("artisan")
	end
	for _, stem in ipairs(stems) do
		if sub:find(stem, 1, true) then
			return true
		end
	end
	return false
end

-- Recorded services, kept with the Route module's learned paths.
local function Learned()
	local R = MelloUI.Route
	local store = R and R.Pins and R:Pins()
	if store then
		store.services = store.services or {}
		return store.services
	end
	M.db.learned = M.db.learned or {}
	return M.db.learned
end

-- Candidates of a kind: { name, sub, cont/wx/wy or mapID/x/y }.
local function Candidates(kind)
	local out = {}
	local data = Data()
	local side = PlayerSide()
	if kind.data and type(data) == "table" and type(data.services) == "table" then
		for _, row in ipairs(data.services) do
			if row[1] == kind.data and (row[4] == 0 or row[4] == side) and (not kind.trainer or TrainerMatches(kind, row[3])) then
				out[#out + 1] = { name = row[2], sub = row[3], cont = row[5], wx = row[6], wy = row[7] }
			end
		end
	end
	if kind.taxi and type(data) == "table" and type(data.taxiNodes) == "table" then
		local R = Route()
		for id, n in pairs(data.taxiNodes) do
			if (n[5] == 0 or n[5] == side) and (not R or R:IsTaxiUsable(id)) then
				out[#out + 1] = { name = n[1], sub = "", cont = n[2], wx = n[3], wy = n[4] }
			end
		end
	end
	for _, l in pairs(Learned()) do
		if l.kind == kind.key or (kind.data and l.kind == kind.data and (not kind.trainer or TrainerMatches(kind, l.sub))) then
			out[#out + 1] = { name = l.name, sub = l.sub or "", mapID = l.mapID, x = l.x, y = l.y }
		end
	end
	return out
end

-- The nearest few by straight line, with their distances.
local function Nearest(kind, count)
	local R = Route()
	if not R then
		return {}
	end
	local list = {}
	for _, c in ipairs(Candidates(kind)) do
		local d = R:DistanceTo(c)
		if d then
			c.distance = d
			list[#list + 1] = c
		end
	end
	table.sort(list, function(a, b) return a.distance < b.distance end)
	while #list > count do
		list[#list] = nil
	end
	return list
end

-- The Route module draws the tracking notice; chat when it is off.
local function Notify(text, kind)
	local R = MelloUI.Route
	if R and R.Notify then
		R:Notify(text, kind)
	else
		MelloUI:Print(text)
	end
end

local function CleanSub(sub)
	if type(sub) ~= "string" or sub == "" or sub:upper() == "NULL" then
		return ""
	end
	return sub
end

local function GoTo(kind)
	local R = Route()
	if not R then
		Notify("The Route module is off; enable it under /mello.", "fail")
		return
	end
	local near = Nearest(kind, 6)
	if #near == 0 then
		Notify("No " .. kind.label:lower() .. " known on this continent yet.", "fail")
		return
	end
	local best = R:Cheapest(near) or 1
	local c = near[best]
	local sub = CleanSub(c.sub)
	local icon = kind.icon and ("|T" .. kind.icon .. ":16:16|t ") or ""
	local label = icon .. kind.label .. ": " .. c.name
	local big = kind.icon and ("|T" .. kind.icon .. ":22:22|t  ") or ""
	R:SetDestinationTo(c, label, true, string.format("%sTracking nearest %s, closest one {dist} away", big, kind.label:lower()))
end

--------------------------------------------------------------------------------
-- Learning
--------------------------------------------------------------------------------

local function Remember(kindKey, name, sub)
	if not name then
		return
	end
	local mapID, x, y = PlayerMapPoint()
	if not mapID then
		return
	end
	local key = kindKey .. "|" .. name .. "|" .. mapID
	local learned = Learned()
	if learned[key] then
		return
	end
	-- The database may already know this one: skip when a known candidate of
	-- the kind stands within 40 yards.
	local R = Route()
	local me = { mapID = mapID, x = x, y = y }
	if R then
		local here = R:DistanceTo(me) or 0
		for _, kind in ipairs(KINDS) do
			if kind.key == kindKey or kind.data == kindKey then
				for _, c in ipairs(Candidates(kind)) do
					if not c.mapID then
						local d = R:DistanceTo(c)
						if d and math.abs(d - here) < 40 then
							return
						end
					end
				end
				break
			end
		end
	end
	learned[key] = { kind = kindKey, name = name, sub = sub or "", mapID = mapID, x = x, y = y }
	local icon = ""
	for _, kind in ipairs(KINDS) do
		if (kind.key == kindKey or kind.data == kindKey) and kind.icon then
			icon = "|T" .. kind.icon .. ":22:22|t  "
			break
		end
	end
	Notify(icon .. "Remembered " .. name .. " as a " .. kindKey, "learn")
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
	if event == "MERCHANT_SHOW" then
		local ok, can = pcall(CanMerchantRepair)
		if ok and can then
			Remember("repair", NPCName(), NPCSubName())
		end
	elseif event == "MAIL_SHOW" then
		Remember("mailbox", "Mailbox", "")
	elseif event == "GOSSIP_SHOW" then
		if C_GossipInfo and C_GossipInfo.GetOptions then
			local ok, options = pcall(C_GossipInfo.GetOptions)
			if ok and type(options) == "table" then
				for _, option in ipairs(options) do
					local text = Plain(option.name)
					if type(text) == "string" and text:lower():find("inn your home", 1, true) then
						Remember("innkeeper", NPCName(), NPCSubName())
						break
					end
				end
			end
		end
	elseif event == "TAXIMAP_OPENED" then
		Remember("flight", NPCName(), NPCSubName())
	elseif event == "AUCTION_HOUSE_SHOW" then
		Remember("auction", NPCName(), NPCSubName())
	elseif event == "BANKFRAME_OPENED" then
		Remember("banker", NPCName(), NPCSubName())
	elseif event == "TRAINER_SHOW" then
		Remember("trainer", NPCName(), NPCSubName())
	elseif event == "BARBER_SHOP_OPEN" then
		Remember("barber", NPCName() or "Barber", NPCSubName())
	elseif event == "TRANSMOGRIFY_OPEN" then
		Remember("transmog", NPCName() or "Transmogrifier", NPCSubName())
	end
end)

local EVENTS = { "MERCHANT_SHOW", "MAIL_SHOW", "GOSSIP_SHOW", "TAXIMAP_OPENED", "AUCTION_HOUSE_SHOW", "BANKFRAME_OPENED",
	"TRAINER_SHOW", "BARBER_SHOP_OPEN", "TRANSMOGRIFY_OPEN" }

--------------------------------------------------------------------------------
-- Menu
--------------------------------------------------------------------------------

local menu = nil
local ROW_HEIGHT = 20
local MENU_WIDTH = 300

local function CreateMenu()
	if menu then
		return menu
	end
	menu = CreateFrame("Frame", "MelloUIServicesMenu", UIParent, "BackdropTemplate")
	menu:SetFrameStrata("DIALOG")
	menu:SetClampedToScreen(true)
	menu:SetWidth(MENU_WIDTH)
	if menu.SetBackdrop then
		menu:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		menu:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
		menu:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
	end
	menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	menu.title:SetPoint("TOPLEFT", 12, -10)
	menu.title:SetText("Nearest ...")
	menu.rows = {}
	for i, kind in ipairs(KINDS) do
		local row = CreateFrame("Button", nil, menu)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 8, -30 - (i - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT", -8, 0)
		row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.label:SetPoint("LEFT", 6, 0)
		row.label:SetText(kind.label)
		row.where = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.where:SetPoint("RIGHT", -6, 0)
		row.where:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
		row.where:SetJustifyH("RIGHT")
		row.where:SetWordWrap(false)
		row.kind = kind
		row:SetScript("OnClick", function(self)
			menu:Hide()
			GoTo(self.kind)
		end)
		menu.rows[i] = row
	end
	menu.stop = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
	menu.stop:SetSize(110, 20)
	menu.stop:SetPoint("TOPLEFT", 12, -34 - #KINDS * ROW_HEIGHT)
	menu.stop:SetText("Stop route")
	menu.stop:SetScript("OnClick", function()
		menu:Hide()
		local R = MelloUI.Route
		if R and R.Clear then
			R:Clear()
		end
		if C_Map.ClearUserWaypoint then
			pcall(C_Map.ClearUserWaypoint)
		end
	end)
	menu.hint = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	menu.hint:SetPoint("LEFT", menu.stop, "RIGHT", 8, 0)
	menu.hint:SetPoint("RIGHT", -12, 0)
	menu.hint:SetJustifyH("LEFT")
	menu.hint:SetText("nearest by road")
	menu:SetHeight(30 + #KINDS * ROW_HEIGHT + 34)
	menu:Hide()
	-- Close when clicking elsewhere.
	menu:SetScript("OnUpdate", function(self)
		if not self:IsMouseOver(20, -20, -20, 20) and not (M.button and M.button:IsMouseOver()) then
			local down = IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
			if down then
				self:Hide()
			end
		end
	end)
	return menu
end

local function FillMenu()
	local R = Route()
	local hasDest = R and R.HasDestination and R:HasDestination()
	for _, row in ipairs(menu.rows) do
		local near = Nearest(row.kind, 1)
		if #near > 0 then
			local c = near[1]
			row.where:SetText(string.format("%s  |cffaaaaaa%s|r", c.name, Yards(c.distance)))
			row.where:SetTextColor(1, 0.82, 0.25)
			row:Enable()
			row.label:SetTextColor(1, 1, 1)
		else
			row.where:SetText(R and "none known here" or "Route module off")
			row.where:SetTextColor(0.5, 0.5, 0.5)
			row.label:SetTextColor(0.6, 0.6, 0.6)
		end
	end
	menu.stop:SetShown(hasDest and true or false)
	menu.hint:SetShown(not hasDest)
end

local function ToggleMenu(anchor)
	CreateMenu()
	if menu:IsShown() then
		menu:Hide()
		return
	end
	FillMenu()
	menu:ClearAllPoints()
	if anchor then
		menu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0)
	else
		menu:SetPoint("CENTER", UIParent, "CENTER")
	end
	menu:Show()
end

--------------------------------------------------------------------------------
-- Icon bar under the minimap
--------------------------------------------------------------------------------

local bar = nil
local ICON = 26
local GAP = 5
local PER_ROW = 5

local function StopRoute()
	local R = MelloUI.Route
	if R and R.Clear then
		R:Clear()
	end
	if C_Map.ClearUserWaypoint then
		pcall(C_Map.ClearUserWaypoint)
	end
end

local function RefreshBar()
	if not (bar and bar:IsShown()) then
		return
	end
	local R = Route()
	for _, b in ipairs(bar.buttons) do
		local near = R and Nearest(b.kind, 1) or {}
		b.nearest = near[1]
		b.icon:SetDesaturated(b.nearest == nil)
		b.icon:SetAlpha(b.nearest and 1 or 0.45)
	end
	bar.refreshed = GetTime()
end

local function BarTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(self.kind.label, 1, 1, 1)
	if self.nearest then
		local c = self.nearest
		local sub = CleanSub(c.sub)
		GameTooltip:AddLine(string.format("Nearest: %s%s, %s", c.name, sub ~= "" and (" (" .. sub .. ")") or "", Yards(c.distance)), 1, 0.82, 0.25)
		GameTooltip:AddLine("Click to route there by road. Right-click stops the route.", 0.7, 0.7, 0.7, true)
	elseif Route() then
		GameTooltip:AddLine("None known on this continent yet; it is remembered the first time you use one.", 0.6, 0.6, 0.6, true)
	else
		GameTooltip:AddLine("The Route module is off.", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function CreateBar()
	if bar or not Minimap then
		return
	end
	local rows = math.ceil(#KINDS / PER_ROW)
	bar = CreateFrame("Frame", "MelloUIServicesBar", Minimap, "BackdropTemplate")
	bar:SetSize(PER_ROW * ICON + (PER_ROW + 1) * GAP, rows * ICON + (rows + 1) * GAP)
	bar:SetFrameStrata("MEDIUM")
	bar:SetFrameLevel(Minimap:GetFrameLevel() + 3)
	if bar.SetBackdrop then
		bar:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		bar:SetBackdropColor(0.05, 0.05, 0.06, 0.85)
		bar:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
	end
	bar.buttons = {}
	for i, kind in ipairs(KINDS) do
		local b = CreateFrame("Button", nil, bar)
		b:SetSize(ICON, ICON)
		local col, row = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
		b:SetPoint("TOPLEFT", GAP + col * (ICON + GAP), -(GAP + row * (ICON + GAP)))
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b.icon:SetTexture(kind.icon)
		b:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
		b.kind = kind
		b:SetScript("OnClick", function(self, mouse)
			if mouse == "RightButton" then
				StopRoute()
			else
				GoTo(self.kind)
			end
		end)
		b:SetScript("OnEnter", function(self)
			if not bar.refreshed or GetTime() - bar.refreshed > 5 then
				RefreshBar()
			end
			BarTooltip(self)
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		bar.buttons[i] = b
	end
	-- The nearest-known state refreshes now and then while the bar is visible.
	local acc = 0
	bar:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + elapsed
		if acc > 15 then
			acc = 0
			RefreshBar()
		end
	end)
	bar:SetScript("OnShow", RefreshBar)
end

local function ApplyBar()
	if M.db.showBar and M.isEnabled then
		CreateBar()
	end
	if bar then
		bar:ClearAllPoints()
		bar:SetPoint("TOP", Minimap, "BOTTOM", 0, tonumber(M.db.barOffset) or -26)
		bar:SetShown(M.isEnabled and M.db.showBar and true or false)
		if bar:IsShown() then
			RefreshBar()
		end
	end
end

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------

local function UpdateButtonPosition()
	local button = M.button
	if not button then
		return
	end
	local angle = math.rad(tonumber(M.db.angle) or 205)
	local radius = 80
	local x, y = math.cos(angle) * radius, math.sin(angle) * radius
	-- A square minimap wants the button on its edge, not on a circle.
	if GetMinimapShape then
		local ok, shape = pcall(GetMinimapShape)
		if ok and shape == "SQUARE" then
			local q = math.max(math.abs(math.cos(angle)), math.abs(math.sin(angle)))
			x, y = math.cos(angle) / q * radius, math.sin(angle) / q * radius
		end
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CreateButton()
	if M.button or not Minimap then
		return
	end
	local button = CreateFrame("Button", "MelloUIServicesButton", Minimap)
	M.button = button
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")
	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface/Minimap/UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetTexture("Interface/Icons/INV_Misc_Map_01")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetPoint("TOPLEFT", 7, -6)
	button.icon = icon
	button:SetScript("OnClick", function(self, mouse)
		if mouse == "RightButton" then
			local R = MelloUI.Route
			if R and R.Clear then
				R:Clear()
			end
			if C_Map.ClearUserWaypoint then
				pcall(C_Map.ClearUserWaypoint)
			end
			if menu then
				menu:Hide()
			end
			return
		end
		ToggleMenu(self)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Services", 1, 1, 1)
		GameTooltip:AddLine("Click: route to the nearest repair, mailbox, innkeeper, flight master, auction house, bank, trainer, barber or transmogrifier.", nil, nil, nil, true)
		GameTooltip:AddLine("Right-click: stop the route.  Drag: move the button.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(self)
		self.dragging = true
		GameTooltip:Hide()
		self:SetScript("OnUpdate", function(btn)
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			cx, cy = cx / scale, cy / scale
			M.db.angle = math.deg(math.atan2(cy - my, cx - mx))
			UpdateButtonPosition()
		end)
	end)
	button:SetScript("OnDragStop", function(self)
		self.dragging = nil
		self:SetScript("OnUpdate", nil)
		MelloUI:NotifySettingChanged(M.name, "angle", M.db.angle)
	end)
	UpdateButtonPosition()
end

local function ApplyButton()
	if M.db.showButton and M.isEnabled then
		CreateButton()
	end
	if M.button then
		M.button:SetShown(M.isEnabled and M.db.showButton and true or false)
		UpdateButtonPosition()
	end
end

--------------------------------------------------------------------------------
-- Slash command and lifecycle
--------------------------------------------------------------------------------

SLASH_MELLOSERVICES1 = "/services"
SlashCmdList.MELLOSERVICES = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "" then
		ToggleMenu(M.button)
		return
	end
	for _, kind in ipairs(KINDS) do
		if kind.key == msg or kind.label:lower() == msg or kind.label:lower():find(msg, 1, true) == 1 then
			GoTo(kind)
			return
		end
	end
	MelloUI:Print("/services  |  /services repair | mailbox | innkeeper | flight | auction | bank | class trainer | profession trainer | barber | transmog")
end

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	ApplyButton()
	ApplyBar()
	for _, event in ipairs(EVENTS) do
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	if M.button then
		M.button:Hide()
	end
	if bar then
		bar:Hide()
	end
	if menu then
		menu:Hide()
	end
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	ApplyButton()
	ApplyBar()
end

MelloUI:Profile("Services", "service window events", eventFrame)
