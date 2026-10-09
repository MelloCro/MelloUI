--------------------------------------------------------------------------------
-- MelloUI - the layer over the world map
--
-- (0.19.9: the core's, from the Quest List's page file -- the Quest List is an
-- addon of its own now, MelloUI_QuestList, and Route's trails hang in this
-- layer too: docs/plans/split-addons.md)
--
-- The Quest List's map marks' clip, its page in the quest log's column and
-- Route's trails on the map (RouteRecorder) hang in it. They are MelloUI's
-- own frames, never the map's children: as the map's children they were in
-- every walk the game's gamepad navigation makes of the map (as it opens, on
-- each focus change, for each frame made in it), and a field MelloUI's list
-- wrote was read on the way, so the rest of the walk ran on MelloUI's time
-- (0.15.0, the map's freeze in the Gamepad UI). A plain frame under
-- UIParent, the whole screen, no mouse, a STRATA over the map's: the map is a
-- frame buffer, drawn as ONE picture, and two frame buffers in one strata
-- swap order with every click whatever levels they are given (0.18.0: the
-- side window's holder was one, and the map's marks in it were gone each time
-- the map was clicked -- user's video and test, 2026-10-02); a strata up, the
-- layer is over the map's picture whichever was clicked last (the map's
-- border, a strata over its canvas, still frames the marks). Its alpha (the
-- game's fade while the player moves, PlayerMovementFrameFader; UI
-- Modifications' fade-in), its scale (UI Modifications' saved scale, the
-- mouse wheel on its mover) and its shown state follow the map's, by
-- post-hooks only: nothing is written on the map. Made on its first ask (the
-- Quest List page's, the marks' first lay, a trail's), never at login.
--
--   MelloUI.MapLayer() -> the layer (made the first time)
--   MelloUI.mapLayer      the layer once made, else nil
--   MelloUI.SyncMapLayer()  its strata, alpha, scale and shown state as the
--                         map's now (nothing before the layer is made)
--   MelloUI.STRATA_UP     the strata one over each
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("MapLayer")

-- the strata one over each (the layer over the map's)
MelloUI.STRATA_UP = { BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG", DIALOG = "FULLSCREEN",
	FULLSCREEN = "FULLSCREEN_DIALOG", FULLSCREEN_DIALOG = "TOOLTIP" }

-- a scale on the layer: the page's backgrounds laid again at the UI's one
-- density with it (Kit:SetFrameScale; only when the scale really changed)
local function LayerScale(layer, scale)
	if layer:GetScale() == scale then
		return
	end
	local Kit = MelloUI.Kit
	if Kit and Kit.SetFrameScale then
		Kit:SetFrameScale(layer, scale)
	else
		layer:SetScale(scale)
	end
end

function MelloUI.SyncMapLayer()
end

local function FollowMap(layer)
	local map = WorldMapFrame
	-- the map's strata read each time (the game may change it as the map
	-- opens), its alpha, scale and shown state
	local function Sync()
		local strata = map:GetFrameStrata()
		strata = MelloUI.STRATA_UP[strata] or strata
		if layer:GetFrameStrata() ~= strata then
			layer:SetFrameStrata(strata)
		end
		layer:SetAlpha(map:GetAlpha())
		LayerScale(layer, map:GetScale())
		layer:SetShown(map:IsShown())
	end
	MelloUI.SyncMapLayer = Sync
	Sync()
	Perf.HookScript(map, "OnShow", Sync)
	Perf.HookScript(map, "OnHide", Sync)
	Perf.hooksecurefunc(map, "SetAlpha", function(_, alpha)
		layer:SetAlpha(alpha)
	end)
	Perf.hooksecurefunc(map, "SetScale", function(_, scale)
		LayerScale(layer, scale)
	end)
end

function MelloUI.MapLayer()
	local layer = MelloUI.mapLayer
	if layer then
		return layer
	end
	layer = CreateFrame("Frame", nil, UIParent)
	layer:SetAllPoints(UIParent)
	MelloUI.mapLayer = layer
	FollowMap(layer)
	return layer
end
