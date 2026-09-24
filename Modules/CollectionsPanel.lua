--------------------------------------------------------------------------------
-- MelloUI - Collections Panel
--
-- The Collections window (CollectionsJournal: Mounts, Pets, Toys, Heirlooms
-- and Wardrobe on side tabs) dressed in the painted kit (Modules/Kit.lua)
-- on the game's own layout, as the other windows are: every kit piece
-- stands in for one of the game's art regions, on that region's rectangle,
-- as a child (or region) of its frame, faded in place of it
-- (docs/WINDOW-RULES.md).
--
-- State (2026-09-21): first pass from the templates — the window shell and
-- side tabs, the mount list's rows (plate, selected plate, icon rim), the
-- pages' icon-grid backdrops, and every common control (`Kit:SweepControls`:
-- insets, search boxes, filter dropdowns, red buttons, check boxes, page
-- arrows, scroll bars). The pet list, the toy / heirloom grids' slots and
-- the wardrobe's own art wait for the dump. /coldump lists the window's art.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit

local M = MelloUI:RegisterModule("CollectionsPanel", {
	title = "Collections Panel",
	desc = "The collections window dressed in the painted kit on the game's own layout.",
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
			MelloUI:Notice("Collections panel: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

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

local function Portrait()
	local cj = CollectionsJournal
	return cj and cj.PortraitContainer and cj.PortraitContainer.portrait
end

-- A mount list row (MountListButtonTemplate): the plain plate on its
-- background (hover from the button), the selected plate on its selection
-- (shown / hidden by the game), the square rim on its icon; the highlight
-- and new-glow faded.
local function SkinMountRow(row)
	if row.melloRep ~= nil then
		return
	end
	row.melloRep = false
	if row.background then
		local highlight = row.GetHighlightTexture and row:GetHighlightTexture()
		row.melloRep = Replace(row.background, { as = "PetList-ButtonBackground", rect = row, button = row,
			alsoFade = highlight and { highlight } or nil }) or false
	end
	if row.selectedTexture then
		Follow(Replace(row.selectedTexture, { as = "PetList-ButtonSelect", rect = row }), row.selectedTexture)
	end
	if row.iconBorder and row.icon then
		local rect = Kit:RimRect(row, "slot", row.icon:GetWidth() > 0 and row.icon:GetWidth() or 40, row.icon, 0)
		Replace(row.iconBorder, { as = "WhiteIconFrame", rect = rect, button = row })
	end
end

-- A page's icon grid backdrop (CollectionsBackgroundTemplate: an inset with
-- a tiled picture): the page stone as a region under the slots.
local function SkinIconsFrame(frame)
	if not frame or frame.melloBackdrop ~= nil then
		return
	end
	frame.melloBackdrop = false
	if frame.BackgroundTile then
		frame.melloBackdrop = Replace(frame.BackgroundTile, { as = "collections-background-tile" }) or false
	end
	-- the single rail around the grid (the frame is an inset), above its slots
	Kit:SkinInset(frame, Replace, frame:GetParent())
	-- the shadowed edges and corners over the tile: faded
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and not region.kitPiece then
			local key = Kit:ArtKey(region)
			if key and key:find("^collections%-background%-") and key ~= "collections-background-tile" then
				Replace(region, { as = key })
			end
		end
	end
end

-- The eye-strain panel (WINDOW-RULES 2e; user, 2026-09-24: "too much small
-- text over a plain brown border is just an eye strain" / "apply the eye
-- strain rule to all existing windows"): the palette's inner panel inside the
-- rail of an inset that holds text -- a list of names, a grid of named icons
-- -- (Kit:StoneDim), as a REGION of the inset itself, over its stone (the
-- page's, or the icon grid's tile at BACKGROUND 0) at BACKGROUND 2: where
-- the game drew the inset's own marble, so the rows and slots the game draws
-- over that are drawn over the panel too. A tint over the one stone, never a
-- second stone; shown only while the skin is on. The wardrobe's grid of item
-- models and the mount / pet / set pictures are picture areas and get none.
local function EyePanel(host)
	if not (host and Kit.StoneDim) or skin.eyePanels[host] ~= nil then
		return
	end
	local tex = Kit:StoneDim(host)
	skin.eyePanels[host] = tex or false
	if tex then
		tex.kitPiece = true            -- ours: never taken for the game's art
		tex:SetShown(active)
	end
end

--------------------------------------------------------------------------------
-- Building the skin
--------------------------------------------------------------------------------
local function BuildSkin()
	if skin then
		return skin
	end
	local cj = CollectionsJournal
	skin = CreateFrame("Frame", "MelloUICollectionsSkin", cj)
	skin:SetAllPoints()
	skin:SetFrameLevel(cj:GetFrameLevel())
	skin:EnableMouse(false)
	skin.reps = {}
	skin.followers = {}
	skin.eyePanels = setmetatable({}, { __mode = "k" })   -- [inset] = its inner panel (EyePanel)
	skin.Replace = Replace

	-- the body OFF (its holder sat over the wardrobe's slot buttons): the
	-- window's rock is the page stone as a region under everything instead
	Kit:SkinWindowShell(cj, Replace, skin, { portrait = Portrait(), body = false, bg = "UI-Background-Rock" })
	local tabs = cj.TabContainer and cj.TabContainer.Tabs
	for _, tab in ipairs(tabs or {}) do
		Kit:SkinSideTab(tab, Replace)
	end

	-- the mount journal's list
	if MountJournal and MountJournal.ScrollBox then
		Kit:HookScrollBoxRows(MountJournal.ScrollBox, SkinMountRow, IsActive)
	end
	-- the icon grids' backdrops; the toys' and heirlooms' names on the inner
	-- panel (2e), the wardrobe's models not (a picture area)
	for _, page in ipairs({ ToyBox, HeirloomsJournal }) do
		if page then
			SkinIconsFrame(page.iconsFrame)
			EyePanel(page.iconsFrame)
		end
	end
	if WardrobeCollectionFrame then
		SkinIconsFrame(WardrobeCollectionFrame.ItemsCollectionFrame)
		if WardrobeCollectionFrame.SetsCollectionFrame then
			SkinIconsFrame(WardrobeCollectionFrame.SetsCollectionFrame.RightInset)
		end
	end
	-- the lists of names (mounts, pets, the wardrobe's sets) on the inner
	-- panel (2e): their insets' rails come from the sweep below, edges only
	for _, inset in ipairs({ MountJournal and MountJournal.LeftInset, _G.PetJournal and _G.PetJournal.LeftInset,
		WardrobeCollectionFrame and WardrobeCollectionFrame.SetsCollectionFrame and WardrobeCollectionFrame.SetsCollectionFrame.LeftInset }) do
		EyePanel(inset)
	end

	-- every common control in the window
	Kit:SweepControls(cj, Replace, skin)
	return skin
end

function M:RefreshFollowers()
	if not (skin and active) then
		return
	end
	for _, f in ipairs(skin.followers) do
		f.rep:SetShown(f.region:IsShown())
	end
	Kit:SweepControls(CollectionsJournal, Replace, skin)
	Kit:FitPortrait(Portrait(), skin.ring)
end

local function Activate()
	if active or not CollectionsJournal then
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
	Kit:UnfitPortrait(Portrait())
end

local function Sync()
	if M.isEnabled and CollectionsJournal then
		Activate()
	else
		Deactivate()
	end
end

local function Hook()
	if hooked or not CollectionsJournal then
		return
	end
	hooked = true
	CollectionsJournal:HookScript("OnShow", function()
		Sync()
		M:RefreshFollowers()
	end)
	if CollectionsJournal_UpdateSelectedTab then
		hooksecurefunc("CollectionsJournal_UpdateSelectedTab", function()
			M:RefreshFollowers()
		end)
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, _, addon)
	if addon == "Blizzard_Collections" and M.isEnabled then
		Hook()
		Sync()
	end
end)

function M:OnEnable(db)
	self.db = db
	if CollectionsJournal then
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
-- /coldump: the window's art (regions by default; "frames", "reps"). Opens
-- the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOCOLDUMP1 = "/coldump"
SlashCmdList.MELLOCOLDUMP = function(msg)
	if not CollectionsJournal then
		MelloUI:Print("Collections window not loaded.")
		return
	end
	MelloUI:ClearLog()
	Kit:DumpWindow(CollectionsJournal, skin, msg)
	MelloUI:ShowLog("coldump " .. (msg or ""))
end
