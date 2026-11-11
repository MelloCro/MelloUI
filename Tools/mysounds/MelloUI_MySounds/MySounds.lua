--------------------------------------------------------------------------------
-- MelloUI My Sounds: your own sounds, for MelloUI's Custom Sounds (its Your Sounds tab) and every other addon that
-- uses SharedMedia. The whole guide:
--   https://github.com/MelloCro/MelloUI/blob/main/docs/custom-sounds.md
--
--   1. Put your .ogg or .mp3 files in this folder's Sounds folder. Simple names: letters, numbers, - and _ only.
--   2. Add one line for each sound at the bottom of this file, like this:
--          Sound("Air Horn", "air_horn.ogg")
--      The first name is what you see in the lists (any words you like); the second is the file's name exactly,
--      its ending included. Keep the quotes, the comma and the brackets.
--   3. Save this file and restart the game completely (a /reload does not find new files).
--
-- MelloUI updates never touch this folder, so your sounds stay. A sound the game cannot find is named in your chat
-- after you log in.
--------------------------------------------------------------------------------

local FOLDER = "Interface\\AddOns\\MelloUI_MySounds\\Sounds\\"
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local missing = {}

local function Sound(name, file)
	if not (LSM and type(name) == "string" and name ~= "" and type(file) == "string" and file ~= "") then
		return
	end
	local ok, added = pcall(LSM.Register, LSM, "sound", name, FOLDER .. file)
	if not (ok and added) and not LSM:IsValid("sound", name) then
		missing[#missing + 1] = file
	end
end

-- (after login, so it shows in chat) the files the game could not find
local watch = CreateFrame("Frame")
watch:RegisterEvent("PLAYER_LOGIN")
watch:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	if #missing > 0 then
		print("|cffe0b53aMelloUI My Sounds|r: not found in the Sounds folder: " .. table.concat(missing, ", ")
			.. ". Check each name and ending, then restart the game completely.")
	end
end)

--------------------------------------------------------------------------------
-- Your sounds, one line each, below. The two lines here are examples, switched off by the two dashes in front of
-- them: write your own lines without the dashes.
--------------------------------------------------------------------------------

-- Sound("Air Horn", "air_horn.ogg")
-- Sound("My Gong", "gong-2.mp3")

