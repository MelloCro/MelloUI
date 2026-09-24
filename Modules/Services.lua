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

local _, ns = ...
local MelloUI = ns.MelloUI

local M = MelloUI:RegisterModule("Services", {
	title = "Services",
	desc = "Minimap button that routes you to the nearest repair, mailbox, innkeeper, flight master, auction house, bank, trainer, barber or transmogrifier.",
	enabledByDefault = true,
	defaults = {
		showBar = true,
		barOffset = -26,
		roundIcons = true,
		showButton = false,
		angle = 205,
	},
	options = {
		{ type = "toggle", key = "showBar", name = "Icon Bar Under The Minimap",
		  desc = "Two rows of service icons under the minimap; it moves with the minimap in Edit Mode. Click an icon to route to the nearest one, right-click to stop the route." },
		{ type = "slider", key = "barOffset", parent = "showBar", name = "Bar Distance From The Minimap", min = -80, max = 20, step = 2 },
		{ type = "toggle", key = "roundIcons", parent = "showBar", name = "Round Icons",
		  desc = "Show the service icons as round medallions with a bronze rim instead of squares." },
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
	if IsSecret(v) or v == nil then
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

-- Professions a trainer can teach, recognised from the trainer's subname
-- ("Journeyman Blacksmith", "Herbalism Trainer", "Fisherman", ...).
local PROFESSIONS = {
	{ key = "alchemy",        label = "Alchemy",        match = { "alchem" } },
	{ key = "blacksmithing",  label = "Blacksmithing",  match = { "blacksmith", "armorsmith", "weaponsmith", "armor crafter", "weapon crafter" } },
	{ key = "enchanting",     label = "Enchanting",     match = { "enchant" } },
	{ key = "engineering",    label = "Engineering",    match = { "engineer" } },
	{ key = "herbalism",      label = "Herbalism",      match = { "herbal" } },
	{ key = "leatherworking", label = "Leatherworking", match = { "leather" } },
	{ key = "mining",         label = "Mining",         match = { "mining", "miner" } },
	{ key = "skinning",       label = "Skinning",       match = { "skinn" } },
	{ key = "tailoring",      label = "Tailoring",      match = { "tailor" } },
	{ key = "cooking",        label = "Cooking",        match = { "cook", "butcher" } },
	{ key = "fishing",        label = "Fishing",        match = { "fish" } },
	{ key = "firstaid",       label = "First Aid",      match = { "first aid", "physician", "trauma surgeon" } },
	{ key = "riding",         label = "Riding",         match = { "riding", "mechanostrider pilot" } },
	{ key = "weapons",        label = "Weapon Skills",  match = { "weapon master" } },
}

local function ProfessionOf(sub)
	sub = (sub or ""):lower()
	if sub == "" then
		return nil
	end
	for _, prof in ipairs(PROFESSIONS) do
		for _, stem in ipairs(prof.match) do
			if sub:find(stem, 1, true) then
				return prof
			end
		end
	end
	return nil
end

-- Names of the professions the character knows, lower case.
local function KnownProfessions()
	local known = {}
	if GetProfessions and GetProfessionInfo then
		local ok, a, b, c, d, e, f = pcall(GetProfessions)
		if ok then
			for _, index in ipairs({ a, b, c, d, e, f }) do
				if index then
					local okI, name = pcall(GetProfessionInfo, index)
					if okI and type(name) == "string" and not IsSecret(name) then
						known[name:lower()] = true
					end
				end
			end
		end
	end
	return known
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
-- profession (optional): only trainers teaching that profession.
local function Candidates(kind, profession)
	local out = {}
	local data = Data()
	local side = PlayerSide()
	local function Wanted(sub)
		if profession then
			return ProfessionOf(sub) == profession
		end
		return not kind.trainer or TrainerMatches(kind, sub)
	end
	if kind.data and type(data) == "table" and type(data.services) == "table" then
		for _, row in ipairs(data.services) do
			if row[1] == kind.data and (row[4] == 0 or row[4] == side) and Wanted(row[3]) then
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
		if l.kind == kind.key or (kind.data and l.kind == kind.data and Wanted(l.sub)) then
			out[#out + 1] = { name = l.name, sub = l.sub or "", mapID = l.mapID, x = l.x, y = l.y }
		end
	end
	return out
end

-- The nearest few by straight line, with their distances.
local function Nearest(kind, count, profession)
	local R = Route()
	if not R then
		return {}
	end
	local list = {}
	for _, c in ipairs(Candidates(kind, profession)) do
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
		MelloUI:Notice(text)
	end
end

local function CleanSub(sub)
	if type(sub) ~= "string" or sub == "" or sub:upper() == "NULL" then
		return ""
	end
	return sub
end

local function GoTo(kind, profession)
	local R = Route()
	if not R then
		Notify("The Route module is off; enable it under /mello.", "fail")
		return
	end
	local what = profession and (profession.label .. " trainer") or kind.label:lower()
	local near = Nearest(kind, 6, profession)
	if #near == 0 then
		Notify("No " .. what .. " known on this continent yet.", "fail")
		return
	end
	local best = R:Cheapest(near) or 1
	local c = near[best]
	local icon = kind.icon and ("|T" .. kind.icon .. ":16:16|t ") or ""
	local label = icon .. (profession and profession.label or kind.label) .. ": " .. c.name
	local big = kind.icon and ("|T" .. kind.icon .. ":22:22|t  ") or ""
	R:SetDestinationTo(c, label, true, string.format("%sTracking nearest %s, closest one {dist} away", big, what))
end

-- The profession trainer button asks which profession: a menu of every
-- profession with a known trainer, the character's own ones first.
local function ProfessionMenu(owner, kind)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		GoTo(kind)
		return
	end
	local known = KnownProfessions()
	local available = {}
	for _, prof in ipairs(PROFESSIONS) do
		if #Candidates(kind, prof) > 0 then
			available[#available + 1] = prof
		end
	end
	table.sort(available, function(a, b)
		local ka, kb = known[a.label:lower()] or false, known[b.label:lower()] or false
		if ka ~= kb then
			return ka
		end
		return a.label < b.label
	end)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Profession Trainer")
		for _, prof in ipairs(available) do
			local text = prof.label
			if known[prof.label:lower()] then
				text = text .. "  |cff40ff40(yours)|r"
			end
			root:CreateButton(text, function() GoTo(kind, prof) end)
		end
		if #available > 0 then
			root:CreateDivider()
		end
		root:CreateButton("Nearest of any", function() GoTo(kind) end)
	end)
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
			-- every kind of this data (the class trainer entry filters its
			-- candidates by class; a profession trainer is in the next one)
			if kind.key == kindKey or kind.data == kindKey then
				for _, c in ipairs(Candidates(kind)) do
					if not c.mapID then
						local d = R:DistanceTo(c)
						if d and math.abs(d - here) < 40 then
							return
						end
					end
				end
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

local KitOn, SetKitBox   -- the kit look (below)

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
	if KitOn() then
		SetKitBox(menu, true)   -- SV1: the L1 box, as the bar
	end
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
		if self.kind.trainer == "profession" then
			GameTooltip:AddLine("Click to pick a profession and route to its nearest trainer. Right-click stops the route.", 0.7, 0.7, 0.7, true)
		else
			GameTooltip:AddLine("Click to route there by road. Right-click stops the route.", 0.7, 0.7, 0.7, true)
		end
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
			elseif self.kind.trainer == "profession" then
				ProfessionMenu(self, self.kind)
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

--------------------------------------------------------------------------------
-- The painted minimap stand (ring, zone bar, scaffold with slots) was removed
-- on 2026-09-21 with the restore-first rule: the minimap is the game's, the
-- service icons sit on the plain bar below it.
--------------------------------------------------------------------------------

local function LayerBar()
	if not (bar and Minimap) then
		return
	end
	bar:SetFrameStrata(Minimap:GetFrameStrata())
	bar:SetFrameLevel(Minimap:GetFrameLevel() + 3)
end

local function ApplyStand()
	LayerBar()
end

-- The objective tracker is an Edit Mode system: Edit Mode owns its position
-- and its width, and nothing here ever moves it (an anchor set by addon code
-- taints what Edit Mode reads back on exit and breaks its party frame reset).
local function TrackerNotice()
end

-- Bar layout: a grid of icons under the minimap (round medallions with a rim
-- when roundIcons is on).
local RIM_RATIO = 31 / 21   -- medallion outer diameter over icon diameter (rim art: 31 px ring, 21 px opening)
local KIT_RIM_RATIO = 130 / 79   -- the kit's round rim (buttons/roundslot: 130 px, 79 px opening)

local function WithStand()
	return false
end

--------------------------------------------------------------------------------
-- The kit look (user's picks SV1 SR2, 2026-09-22, kit_raw/services_catalog.png):
-- the bar and the nearest-service menu on the L1 box (single rail, list-box
-- stone), the icons in the kit's round rims. It goes with the minimap area
-- of the reskin (Kit:IsCovered("minimap")): on while the painted minimap
-- is, the game's own backdrop and tracking rims otherwise. Square icons
-- ("Round Icons" off) get the square R1 rim.
--------------------------------------------------------------------------------

KitOn = function()
	local kit = MelloUI.Kit
	return kit and kit.IsCovered and kit:IsCovered("minimap") and kit.Replace and true or false
end

-- An invisible region for Kit:Replace where the frame has none of its own.
local function KitAnchor(frame)
	local tex = frame:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints(frame)
	tex:SetColorTexture(0, 0, 0, 0)
	return tex
end

-- The L1 box on a frame of ours (the bar, the menu), one level under it.
-- The box's rule lays the palette's inner panel over its stone (the eye
-- strain rule, user 2026-09-24: "apply the eye strain rule to all existing
-- windows"; WINDOW-RULES 2e): kept on the nearest-service menu, a list of
-- text rows; left off the bar, a grid of icons in their rims with no text on
-- the stone, which keeps the plain stone it was picked with (SV1).
local function KitBox(frame)
	if frame.kitBox ~= nil then
		return frame.kitBox
	end
	-- nil: the rule's panel; false: none (an `and false or nil` would give nil)
	local dim = nil
	if frame ~= menu then
		dim = false
	end
	local rep = MelloUI.Kit:Replace(KitAnchor(frame), { as = "Professions-background-summarylist", rect = frame, parent = frame, level = -1, dim = dim })
	frame.kitBox = rep or false
	return frame.kitBox
end

SetKitBox = function(frame, on)
	if not frame then
		return
	end
	if on then
		local rep = KitBox(frame)
		if rep then
			rep:Enable()
			if frame.SetBackdrop then
				frame:SetBackdrop(nil)
			end
			return true
		end
	elseif frame.kitBox then
		frame.kitBox:Disable()
	end
	return false
end

-- A service button's kit rim (round or square), made once each, the icon
-- fitted into the shown one's opening.
local function KitRim(b, round)
	local key = round and "kitRoundRim" or "kitSquareRim"
	if not b[key] then
		b[key] = MelloUI.Kit:Slot(b, { kind = round and "roundslot" or "slot" })
		if MelloUI.Kit.RegisterTexture then
			MelloUI.Kit:RegisterTexture(b[key])   -- Dark Mode's shade
		end
	end
	return b[key]
end

-- Merged into the square minimap's frame (MinimapPanel's Merge With
-- Services; user, 2026-09-23: the header, the minimap and the services "into
-- 1 thing", a header plate between map and services, "D"): the bar spans the
-- map's width under that plate, on the frame's stone instead of its own box.
local function Merged()
	local mp = MelloUI:GetModule("MinimapPanel")
	return KitOn() and mp and mp.isEnabled and mp.WantsServices and mp:WantsServices() and true or false
end

-- the frame's stone under the merged bar
local function BarStone(on)
	if not bar then
		return
	end
	if on and not bar.stone then
		bar.stone = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
		bar.stone:SetAllPoints(bar)
	end
	if bar.stone then
		if on then
			local mp = MelloUI:GetModule("MinimapPanel")
			local piece = mp and mp.BodyPiece and mp:BodyPiece() or "window/frame_body"
			if bar.stone.kitName ~= piece then
				MelloUI.Kit:Apply(bar.stone, piece)
			end
			MelloUI.Kit:Retile(bar.stone)
		end
		bar.stone:SetShown(on and true or false)
	end
end

local function LayoutBar()
	if not bar then
		return
	end
	local rows = math.ceil(#KINDS / PER_ROW)
	local kit = KitOn()
	-- a medallion needs room for its rim; on the kit every icon has one
	-- (round or square), and the BUTTON is the rim: the icon is fitted
	-- into its opening
	local ring = kit and KIT_RIM_RATIO or (M.db.roundIcons and RIM_RATIO or 1)
	local icon, gap = ICON, GAP
	local cell = icon * ring
	local inset = kit and 0 or (cell - icon) / 2
	local merged = Merged()
	local width = PER_ROW * cell + (PER_ROW + 1) * gap
	if merged then
		-- as wide as the map: the cells made smaller where five do not fit
		-- (user, 2026-09-23: "the buttons are not quite fitting the borders"),
		-- then spread evenly across it
		local okW, mapW = pcall(Minimap.GetWidth, Minimap)
		if okW and mapW and not IsSecret(mapW) and mapW > 0 then
			width = mapW
			local minGap = 4
			local fit = (mapW - (PER_ROW + 1) * minGap) / PER_ROW
			if cell > fit then
				local k = fit / cell
				cell, icon = fit, icon * k
				inset = kit and 0 or (cell - icon) / 2
			end
			gap = (mapW - PER_ROW * cell) / (PER_ROW + 1)
		end
	end
	bar:SetSize(width, rows * cell + (rows + 1) * gap)
	for i, b in ipairs(bar.buttons) do
		local col, row = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
		b:SetSize(kit and cell or icon, kit and cell or icon)
		b:ClearAllPoints()
		b:Show()
		b:SetPoint("TOPLEFT", gap + col * (cell + gap) + inset, -(gap + row * (cell + gap) + inset))
		if b.rim then
			local k = icon / 21
			b.rim:SetSize(53 * k, 53 * k)
			b.rim:ClearAllPoints()
			b.rim:SetPoint("TOPLEFT", b, "TOPLEFT", -5 * k, 4 * k)
		end
	end
	if kit then
		for _, b in ipairs(bar.buttons) do
			for _, key in ipairs({ "kitRoundRim", "kitSquareRim" }) do
				local rim = b[key]
				if rim and rim:IsShown() and rim.icon then
					MelloUI.Kit:SlotPlaceIcon(rim)
				end
			end
		end
	end
	bar:ClearAllPoints()
	if merged then
		local mp = MelloUI:GetModule("MinimapPanel")
		bar:SetPoint("TOP", Minimap, "BOTTOM", 0, -(mp.DividerHeight and mp:DividerHeight() or 26))
	else
		bar:SetPoint("TOP", Minimap, "BOTTOM", 0, tonumber(M.db.barOffset) or -26)
	end
end

-- Round medallion icons: the icon under a circular mask with the classic
-- minimap tracking rim around it.
local RIM_TEXTURE = "Interface\\Minimap\\MiniMap-TrackingBorder"
local function ApplyIconShape()
	if not bar then
		return
	end
	-- the painted slots are square, so the medallion rim stands down for them
	local round = M.db.roundIcons and not WithStand() and true or false
	local kit = KitOn()
	for _, b in ipairs(bar.buttons) do
		if not b.mask then
			b.mask = b:CreateMaskTexture()
			b.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			b.mask:SetAllPoints(b.icon)
			b.rim = b:CreateTexture(nil, "OVERLAY")
			b.rim:SetTexture(RIM_TEXTURE)
			-- the rim art sits in the top left of its texture: 53 wide for a 21 wide opening
			local k = b:GetWidth() / 21
			b.rim:SetSize(53 * k, 53 * k)
			b.rim:SetPoint("TOPLEFT", b, "TOPLEFT", -5 * k, 4 * k)
		end
		if round then
			b.icon:AddMaskTexture(b.mask)
			b.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
			b.rim:SetShown(not kit)
		else
			b.icon:RemoveMaskTexture(b.mask)
			b.icon:SetTexCoord(0, 1, 0, 1)
			b.rim:Hide()
		end
		-- the kit's rim (SR2 round; square for square icons), the icon in
		-- its opening; the game's anchors back when the kit is off
		if kit then
			local want = KitRim(b, round)
			for _, key in ipairs({ "kitRoundRim", "kitSquareRim" }) do
				if b[key] then
					b[key]:SetShown(b[key] == want)
				end
			end
			want.icon = b.icon
			MelloUI.Kit:SlotPlaceIcon(want)
		else
			for _, key in ipairs({ "kitRoundRim", "kitSquareRim" }) do
				if b[key] then
					b[key]:Hide()
				end
			end
			b.icon:ClearAllPoints()
			b.icon:SetAllPoints(b)
		end
	end
	if round then
		-- Dark Mode shades the rims with the minimap art.
		local dark = MelloUI:GetModule("DarkMode")
		if dark and dark.isEnabled and dark.Reapply then
			dark:Reapply("minimap")
		end
	end
	local merged = Merged()
	BarStone(merged)
	if bar.SetBackdrop then
		if WithStand() then
			bar:SetBackdrop(nil)   -- the stand is the frame; nothing behind the medallions
		elseif merged then
			SetKitBox(bar, false)   -- the minimap's frame is its border, its stone the ground
			bar:SetBackdrop(nil)
		elseif not SetKitBox(bar, kit) then
			bar:SetBackdrop({
				bgFile = "Interface/Tooltips/UI-Tooltip-Background",
				edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 12,
				insets = { left = 3, right = 3, top = 3, bottom = 3 },
			})
			bar:SetBackdropColor(0.05, 0.05, 0.06, 0.85)
			bar:SetBackdropBorderColor(0.55, 0.45, 0.25, 1)
		end
	end
	-- the nearest-service menu on the same box (SV1)
	if menu and menu.SetBackdrop and not SetKitBox(menu, kit) then
		menu:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		menu:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
		menu:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
	end
end

local function ApplyBar()
	if M.db.showBar and M.isEnabled then
		CreateBar()
	end
	if bar then
		LayerBar()
		bar:SetShown(M.isEnabled and M.db.showBar and true or false)
		if bar:IsShown() then
			RefreshBar()
		end
	end
	ApplyStand()
	ApplyIconShape()
	LayoutBar()
	if M.isEnabled then
		TrackerNotice()
	end
	-- the panels that dress the cluster and the tracker follow the stand
	for _, name in ipairs({ "MinimapPanel", "TrackerPanel" }) do
		local panel = MelloUI:GetModule(name)
		if panel and panel.isEnabled and panel.Relayout then
			panel:Relayout()
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

local relayoutHooked = false
local function HookRelayout()
	if relayoutHooked then
		return
	end
	relayoutHooked = true
	-- the minimap can be resized or moved in Edit Mode: fit the stand and the bar again
	if Minimap and Minimap.HookScript then
		Minimap:HookScript("OnSizeChanged", function() C_Timer.After(0, ApplyBar) end)
	end
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Exit", function() C_Timer.After(0, ApplyBar) end, M)
	end
end

local coverWatched = false

function M:OnEnable(db)
	self.db = db
	HookRelayout()
	ApplyButton()
	ApplyBar()
	if not coverWatched and MelloUI.Kit and MelloUI.Kit.OnCover then
		coverWatched = true
		MelloUI.Kit:OnCover(function(group)
			if group == "minimap" and M.isEnabled then
				ApplyBar()   -- the bar's look goes with the painted minimap
			end
		end)
	end
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
	ApplyStand()
	for _, name in ipairs({ "MinimapPanel", "TrackerPanel" }) do
		local panel = MelloUI:GetModule(name)
		if panel and panel.isEnabled and panel.Relayout then
			panel:Relayout()
		end
	end
end

-- The minimap's frame changed (its shape, border, Merge With Services): the
-- bar laid out again, without calling back (MinimapPanel lays itself out)
function M:LayoutForMinimap()
	if bar and M.isEnabled then
		ApplyIconShape()
		LayoutBar()
	end
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	ApplyButton()
	ApplyBar()
end

MelloUI:Profile("Services", "service window events", eventFrame)
