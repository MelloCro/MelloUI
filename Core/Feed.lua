--------------------------------------------------------------------------------
-- MelloUI - Feed
--
-- (0.17.0, lifted from Gains' lines when Combat Text's feed came: one engine
-- for every column of soft-shaded lines, never a copy per feature;
-- WINDOW-RULES §6.) A column of lines with no frame round them: newest on
-- top, at most `max`, each held for a while and then faded out, so the older
-- ones go first. A line of a kind and id that is still showing is raised to
-- the top and its hold starts again (Gains: "+2 Defense"); a line with no id
-- is a new line each time (Combat Text). Past `max` the oldest goes at once.
-- The hold and the fades are one engine-driven group per line
-- (MelloUI.Anim:Mirror: in, held, out, then hidden; asked again it starts
-- again); the lines below a new one slide down a slot (Anim:To). Reduce
-- Motion: no slide, the lines jump to their slots, and a plain fade.
--
--   local feed = MelloUI.Feed:New(opts)
--     name       the holder's global name ("MelloUIGains")
--     key        its place in MelloUI's mover store (anchor TOPLEFT); label
--                and page: its Edit Layout plate's name and page; when:
--                function() -> its mover live (the owner module on)
--     width, pitch   the holder's width (the drag area: as wide as the
--                longest line, its soft ends too) and one line's slot
--     max        the most lines shown: a number, or function() -> number
--     home       function(frame): its default place
--     newRow     function(row): fills a fresh line (its texts, its band); the
--                line is a Frame `width` x `pitch` on the holder, hidden,
--                click-through
--     onBuild    function(feed): right after the holder is made, before the
--                first line (Gains: Edit Layout's samples come first)
--     from       "top" (default: the column hangs from the holder's top, its
--                mover anchored TOPLEFT) or "bottom" (it stands on the
--                holder's bottom, the newest still on top, the older ones
--                below it; anchored BOTTOMLEFT: Combat Text's feed over the
--                portrait, which a short column should not leave high up)
--     fadeIn, fadeOut, slide   seconds (0.2, 1.2, 0.2)
--   feed:Put(kind, id, hold, apply, ...) -> row
--       apply(row, new, ...) writes the line's own fields and texts; the
--       feed keeps row.kind, row.id and row.slot (its place, 1 = the top)
--   feed:Row(kind, id)   the line of that kind and id while it shows
--   feed:Rows(kind)      [id] = line, that kind's lines shown
--   feed:Fade(row)       fades it out now
--   feed:Each(fn)        fn(row) for every line made (shown and spare)
--   feed:Clear()         every line gone at once, the holder hidden
--   feed:Place()         its saved place again (else its home)
--   feed:SetPitch(p)     a new slot (its owner's text size changed): every
--                        line laid again at once, the holder sized again
--   feed:Fit()           the holder sized again (`max` changed)
--   feed.ui              nil until the first line (or Build): { holder,
--                        lines (newest first), pool (spare lines), rows,
--                        entry (its mover) }
--
-- Cost: nothing is made until the first line (or Edit Layout's samples);
-- lines are pooled; no OnUpdate of its own, no timer; Anim's driver runs
-- only while a line slides. A line's end is its OnHide (one shared handler).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Feed")

local Num = MelloUI.Safe.Number

local tinsert, tremove = table.insert, table.remove

local Feed = {}
MelloUI.Feed = Feed

local FeedMixin = {}
local FEED_MT = { __index = FeedMixin }

local function IndexOf(lines, row)
	for i = 1, #lines do
		if lines[i] == row then
			return i
		end
	end
	return nil
end

function Feed:New(opts)
	opts = opts or {}
	local feed = setmetatable({ opts = opts, ui = nil }, FEED_MT)
	feed.fadeIn = Num(opts.fadeIn) or 0.2
	feed.fadeOut = Num(opts.fadeOut) or 1.2
	feed.slide = Num(opts.slide) or 0.2
	feed.pitch = Num(opts.pitch) or 26
	feed.width = Num(opts.width) or 420
	feed.bottom = opts.from == "bottom"
	feed.anchor = feed.bottom and "BOTTOMLEFT" or "TOPLEFT"
	return feed
end

function FeedMixin:Max()
	local max = self.opts.max
	if type(max) == "function" then
		max = max()
	end
	return Num(max) or 5
end

-- the lines in their slots, newest at the top; a line that moves slides
-- (Anim: at once under Reduce Motion), a new one is laid in its slot. From
-- the bottom a slot counts up from the holder's bottom, the newest highest
function FeedMixin:Lay()
	local ui = self.ui
	local lines = ui.lines
	local pitch = self.pitch
	local n = #lines
	local bottom = self.bottom
	for i = 1, n do
		local row = lines[i]
		local slot = bottom and (n - i + 1) or i
		if row.slot ~= slot then
			local y = bottom and (slot - 1) * pitch or -(slot - 1) * pitch
			if row.slot then
				MelloUI.Anim:To(row, "y", y, self.slide, "outCubic")
			else
				row:ClearAllPoints()
				row:SetPoint(self.anchor, ui.holder, self.anchor, 0, y)
			end
			row.slot = slot
		end
	end
end

function FeedMixin:Fit()
	if self.ui then
		self.ui.holder:SetHeight(self:Max() * self.pitch)
	end
end

function FeedMixin:SetPitch(pitch)
	pitch = Num(pitch)
	if not pitch or pitch <= 0 or pitch == self.pitch then
		return
	end
	self.pitch = pitch
	local ui = self.ui
	if not ui then
		return
	end
	self:Fit()
	local lines = ui.lines
	for i = 1, #lines do
		MelloUI.Anim:Stop(lines[i], "y")
		lines[i].slot = nil
	end
	self:Lay()
end

-- a line over (its fade ended, dropped, or its holder hidden): out of the
-- list, its kind and id free, the line back with the spares, hidden itself
-- (a parent's hide leaves it shown)
local function RowHidden(row)
	local kind = row.kind
	if not kind then
		return   -- (a spare already)
	end
	local feed = row.feed
	local ui = feed.ui
	row.kind = nil
	local map = ui.rows[kind]
	if map and row.id ~= nil and map[row.id] == row then
		map[row.id] = nil
	end
	local i = IndexOf(ui.lines, row)
	if i then
		tremove(ui.lines, i)
	end
	row.slot = nil
	MelloUI.Anim:Stop(row)
	MelloUI.Anim:StopMirror(row)
	ui.pool[#ui.pool + 1] = row
	feed:Lay()
end
local OnRowHide   -- (RowHidden wrapped once, with the first line of any feed)

local function NewRow(feed)
	local row = CreateFrame("Frame", nil, feed.ui.holder)
	row:SetSize(feed.width, feed.pitch)
	row:EnableMouse(false)
	row:Hide()
	row.feed = feed
	feed.opts.newRow(row)
	if not OnRowHide then
		OnRowHide = Perf.Shared("OnHide on a feed line (its line over)", RowHidden, "script")
	end
	Perf.SetScript(row, "OnHide", OnRowHide)
	return row
end

local function Take(feed)
	local pool = feed.ui.pool
	local n = #pool
	if n > 0 then
		local row = pool[n]
		pool[n] = nil
		return row
	end
	return NewRow(feed)
end

-- a line gone at once (past `max`, the owner off): its OnHide takes it out
-- of the list (RowHidden); one not on the screen is taken out here
function FeedMixin:Drop(row)
	MelloUI.Anim:StopMirror(row)
	if row.kind then
		RowHidden(row)
	end
	local i = IndexOf(self.ui.lines, row)
	if i then
		tremove(self.ui.lines, i)   -- (never left in the list)
	end
end

-- the saved place (kept on the screen), else its home
function FeedMixin:Place()
	local ui = self.ui
	if not ui then
		return
	end
	local entry = ui.entry
	if entry and entry.moving then
		return
	end
	if not MelloUI:RestorePosition(self.opts.key, ui.holder) then
		self.opts.home(ui.holder)
		MelloUI:FitOnScreen(ui.holder)
	end
end

function FeedMixin:Build()
	if self.ui then
		return self.ui
	end
	local opts = self.opts
	local holder = CreateFrame("Frame", opts.name, UIParent)
	holder:SetSize(self.width, self:Max() * self.pitch)
	holder:SetFrameStrata("LOW")
	holder:SetClampedToScreen(true)
	holder:EnableMouse(false)
	self.ui = { holder = holder, lines = {}, pool = {}, rows = {} }
	opts.home(holder)
	-- one mover entry: moved in Edit Layout while its owner is on, its place
	-- in the store, put back on each show (it sets no script of its own)
	self.ui.entry = MelloUI:RegisterMover(holder, holder, { key = opts.key, anchor = self.anchor, default = opts.home,
		min = 0.5, max = 2, base = 1, label = opts.label, page = opts.page, when = opts.when })
	self:Place()
	return self.ui
end

function FeedMixin:Rows(kind)
	local rows = self.ui.rows
	local map = rows[kind]
	if not map then
		map = {}
		rows[kind] = map
	end
	return map
end

function FeedMixin:Row(kind, id)
	local ui = self.ui
	local map = ui and ui.rows[kind]
	return map and id ~= nil and map[id] or nil
end

-- a line: a new one on top, or (an id still showing) the one it adds to,
-- raised to the top with its hold started again
function FeedMixin:Put(kind, id, hold, apply, ...)
	if not self.ui then
		self:Build()
		if self.opts.onBuild then
			self.opts.onBuild(self)
		end
	end
	local ui = self.ui
	local row = self:Row(kind, id)
	local new = not row
	if new then
		row = Take(self)
		row.kind, row.id, row.slot = kind, id, nil
		if id ~= nil then
			self:Rows(kind)[id] = row
		end
		tinsert(ui.lines, 1, row)
	else
		local i = IndexOf(ui.lines, row)
		if i and i > 1 then
			tremove(ui.lines, i)
			tinsert(ui.lines, 1, row)
		end
	end
	apply(row, new, ...)
	local max = self:Max()
	while #ui.lines > max do
		self:Drop(ui.lines[#ui.lines])
	end
	ui.holder:Show()
	self:Lay()
	MelloUI.Anim:Mirror(row, new and self.fadeIn or 0, hold, self.fadeOut)
	return row
end

function FeedMixin:Fade(row)
	MelloUI.Anim:Mirror(row, 0, 0, self.fadeOut)
end

function FeedMixin:Each(fn)
	local ui = self.ui
	if not ui then
		return
	end
	local lines, pool = ui.lines, ui.pool
	for i = 1, #lines do
		fn(lines[i])
	end
	for i = 1, #pool do
		fn(pool[i])
	end
end

function FeedMixin:Clear()
	local ui = self.ui
	if not ui then
		return
	end
	local lines = ui.lines
	while #lines > 0 do
		self:Drop(lines[#lines])
	end
	ui.holder:Hide()
end
