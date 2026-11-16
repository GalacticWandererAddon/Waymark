local _, ns = ...

-- What kills here: the Wanderer's own list of a dungeon's real dangers, on and beside the dungeon map, apart from
-- his book (2026-11-11; cleared by the user and on the ship list since 2026-11-14, Forever). Data\DungeonDangers.lua.
--
-- Three pieces, one list:
--   Marks  a red ringed "!" in the map's own ink at each danger's real spots on the floor shown (where its
--          monsters stand thickest, its boss, or the place itself). Hover: the tag. Click: the note, at its row.
--   Tag    a slip of the book's paper by the cursor: the Wanderer's own words in his hand, then in plain type
--          what it is and what to do.
--   Note   "What kills here": dark glass with a gold rule, As told's panel (ns.GlassPanel in Dungeon.lua; the
--          user, 2026-11-14, over the pale paper card it was: "Dark glass for what kills here FOR SURE"). It is
--          its own thing on the screen, not part of the map: it opens beside the dungeon map, can be dragged
--          anywhere and locked there, and stays up when the map is shut or folded, showing the dungeon you are
--          in, or else the one last looked at. How it reads (the user's own rules, the same day):
--            show all     every danger one line: his rating and its title, the worst first. The default.
--            show less    (the menu, or a click on the heading) one danger alone, the one that LEADS. The
--                         pointer on the note unfolds the rest under it; it folds again when the pointer leaves.
--            the lead     in gold. Picked by the run: one that is "now", else the one in front of the next boss
--                         alive, else the worst not yet behind you. A left click on another danger makes that
--                         one lead WITH its details open, and stops the picking (the user after the first
--                         look in game: "pins it and reveals details, not just pins"); "Follow the run" in the
--                         menu starts it again, and so does the chosen one falling behind you.
--            details      his words in his hand, then what to do, which adds to his line and never says it
--                         again (the data's job: mockups\dangers-repeats.md). A left click on the leading danger opens
--                         them under it, another closes them; folding never hides them.
--            soft         what comes (rows unfolding, details opening) fades in over 0.3 s while the glass
--                         grows to fit, as As told's panel does; the first look in game was "too snappy". Pointing at any
--                         danger shows its details in a glass slip beside the note (beside, not under it: rows
--                         that grow under the pointer make the list jump). "Now" shows its details by itself.
--            anywhere     drag: moves it; right-click: the menu (show less / all, follow the run, its size,
--                         his line in plain type, this dungeon's map, lock in place, put away)
--            size         five sizes in the menu (dangersScale; the user plays with the map and the note
--                         small in a corner, others will want it large: "We need to be able to make panel
--                         bigger for the ones that want"). His line is larger and lighter than it began, and
--                         the menu can set it in plain type: a hand is hard to read in the middle of a pull.
--          A danger that comes when a boss dies ("men from behind") is marked "now" for a while after the kill.
--          It follows the run by boss deaths alone, the one thing known for sure inside a dungeon (no place,
--          no target, no count of kills): each danger lies IN FRONT OF a boss (data: before = { "boss" }); that
--          boss dead this run, the danger is behind you: struck through on the note, a stroke through its mark
--          on the map. At a fork (fork = true) the run picks nothing by the order.
--          The "!" tab beside the map's Bosses list (the same dark glass and gold rule as the list's heading,
--          his "!" in red; a leather tab for an hour on 2026-11-14, the user: "'!' gets what bosses list has")
--          opens the note and puts it away; its right-click is a small menu, never "off" (the user: "rightclicking it
--          does NOT remove it").
-- No count, share or percentage of deaths is shown or kept anywhere here: the user ruled them out ("it breaks
-- immersion"), and their source may not ship. The rating is the Wanderer's.
-- Editing (the book's author only, ns.BOOK_AUTHOR): right-click a row: its title, what to do, his words, its
-- rating, what's still to check, a mark on the floor shown, off the list; right-click the note: a new danger;
-- a mark on the map: a drag with Ctrl held or the quill out moves it, the wheel the same way sizes it,
-- right-click: "rub out". Kept in ns.db.dangerEdits[instance][the title in the
-- file] and laid over the file's list; tools\dangers_bake.py writes them into Data\DungeonDangers.lua, and the
-- next load drops what the file then has.
-- The "to check" notes (the author's own questions about a danger, shown small on the slip; the "?" on its
-- row is gone since 2026-11-16) are NOT in the shipped data: they live in Data\DevDangerChecks.lua, a dev file the release builds leave
-- out, and are read only for the author. A question the user forgot to settle can't reach a player.
-- Nothing here tracks or scores the player. ns.db.dungeon.dangers = false: all of it off (/waymark dangers);
-- dangersOpen = false: the note put away; dangersFolded, dangersLocked, dangersAt = { left, top } (where it was
-- dragged to; nil: beside the map), dangersInst: the dungeon last shown.
-- Cost: at most a few dozen ink lines and a handful of buttons on the floor shown, redrawn only when the floor,
-- the hovered danger or a "now" changes; the note's rows are laid out when its content changes. Looked at 4 times
-- a second: with all of it off or nothing to show, that look is a few comparisons.

local NOTES = ns.MEDIA .. "Notes\\"
local FELIPA = ns.MEDIA .. "Fonts\\Felipa-Regular.ttf"
local HAND = ns.MEDIA .. "Fonts\\NothingYouCouldDo.ttf"
local PLAIN = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local ROUND = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local P_INK, P_SOFT, P_RED = { 0.17, 0.12, 0.07 }, { 0.35, 0.23, 0.11 }, { 0.54, 0.165, 0.11 }
local CARD_W, TAG_W = 268, 268
local HEAD_H = 26        -- the note's heading: its name and the dungeon's
local EDGE = 26          -- the glass fades out over this much at the right
local HAND_ON_GLASS = true    -- his own words on the note and its slip (the user: keep them; the tip under them adds, never repeats)
local SOFT_IN = 0.3      -- what comes fades in, and the glass grows, over this (As told's own figure)
local TEXT_X = 36        -- where a row's words begin (his rating is left of it)
local TEXT_W = CARD_W - TEXT_X - EDGE - 2
local G_TEXT, G_SOFT, G_FAINT = { 0.91, 0.89, 0.85 }, { 0.66, 0.64, 0.58 }, { 0.46, 0.44, 0.40 }
local G_GOLD, G_HAND, G_RED = { 0.73, 0.55, 0.32 }, { 0.95, 0.84, 0.63 }, { 0.86, 0.40, 0.30 }
local SIZES = { { "Small", 0.85 }, { "Normal", 1 }, { "Large", 1.2 }, { "Larger", 1.45 }, { "Largest", 1.75 } }
local NOW_FOR = 150      -- seconds a danger stays "now" after its boss dies
local NEAR = 0.07        -- monsters closer than this (0-1 of the picture) are one cluster
local MARK = 30          -- a mark's button, px on the 1002 x 668 picture
local TOGETHER = 0.045   -- dangers closer than this on a floor share one mark

local function Cfg() return ns.db and ns.db.dungeon end
local function On() local c = Cfg() return c and c.dangers ~= false end

local function Font(fs, font, size)
    if not (pcall(fs.SetFont, fs, font, size, "") and fs:GetFont()) then fs:SetFont(PLAIN, size, "") end
end
-- his own line on the glass: in his hand, or (the menu) in plain type for reading in a pull
local function HandFont(fs)
    local c = Cfg()
    if c and c.dangersPlainHand then Font(fs, PLAIN, 12) else Font(fs, HAND, 15) end
end

-- The list ------------------------------------------------------------------------------------------

-- where a set of monsters stands thickest: up to `most` cluster middles, { floor, x, y }
local function Clusters(inst, names, most)
    local data = ns.DungeonMobs and ns.DungeonMobs[inst]
    if not data then return {} end
    local want = {}
    for k, kind in ipairs(data.kinds or {}) do
        for _, n in ipairs(names) do if kind[1] == n then want[k] = true end end
    end
    local groups = {}
    for floor, pts in pairs(data) do
        if type(floor) == "number" then
            for i = 1, #pts - 2, 3 do
                if want[pts[i + 2]] then
                    local x, y, g = pts[i], pts[i + 1], nil
                    for _, o in ipairs(groups) do
                        if o.floor == floor and (o.x / o.n - x) ^ 2 + ((o.y / o.n - y) * 0.667) ^ 2 < NEAR * NEAR then g = o break end
                    end
                    if g then g.x, g.y, g.n = g.x + x, g.y + y, g.n + 1 else groups[#groups + 1] = { floor = floor, x = x, y = y, n = 1 } end
                end
            end
        end
    end
    table.sort(groups, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.x < b.x end)
    local out = {}
    for i = 1, math.min(most or 2, #groups) do
        local g = groups[i]
        out[#out + 1] = { g.floor, g.x / g.n, g.y / g.n }
    end
    return out
end

local function BossSpot(inst, name)
    local mine = ns.db and ns.db.bossSpots and ns.db.bossSpots[inst]
    if mine and mine[name] ~= nil then return mine[name] or nil end
    local shipped = ns.DungeonBosses and ns.DungeonBosses[inst]
    return shipped and shipped[name]
end

-- the author's edits to a dungeon's list (ns.db.dangerEdits[inst][title in the file] = { title, tip, w, level,
-- gone }; a new danger: ["+..."] = { new = true, title, tip, w, level })
local function EditsOf(inst, make)
    local db = ns.db
    if not db then return end
    if not db.dangerEdits then
        if not make then return end
        db.dangerEdits = {}
    end
    local t = db.dangerEdits[inst]
    if not t and make then
        t = {}
        db.dangerEdits[inst] = t
    end
    return t
end

-- (once a session for each dungeon: an edit the file now has, or to a danger the file no longer has, is let go:
-- tools\dangers_bake.py wrote it in)
local cleaned = {}
local function DropBaked(inst, src)
    if cleaned[inst] then return end
    cleaned[inst] = true
    local t = EditsOf(inst)
    if not t then return end
    local have = {}
    for _, d in ipairs(src) do have[d[1]] = d end
    for key, x in pairs(t) do
        local d = have[key]
        if x.new then
            if have[x.title or ""] then t[key] = nil end
        elseif not d then
            t[key] = nil
        else
            if x.title == d[1] then x.title = nil end
            if x.tip == d.tip then x.tip = nil end
            if x.w ~= nil and (x.w == d.w or (x.w == "" and d.w == nil)) then x.w = nil end
            if x.level == d.level then x.level = nil end
            if x.before and d.before and table.concat(x.before, "|") == table.concat(d.before, "|") then x.before = nil end
            if x.fork ~= nil and (x.fork or false) == (d.fork or false) then x.fork = nil end
            if next(x) == nil then t[key] = nil end
        end
    end
    if next(t) == nil then ns.db.dangerEdits[inst] = nil end
end

-- a dungeon's dangers as the note shows them (the worst first, then the file's order), each with its spots
-- found: { key, title, level, who, tip, w, after, check, spots = { { floor, x, y }, ... }, n }
local lists = {}
local function List(inst)
    if lists[inst] ~= nil then return lists[inst] or nil end
    local src = ns.DungeonDangers and ns.DungeonDangers[inst]
    if not src then lists[inst] = false return end
    DropBaked(inst, src)
    local edits = EditsOf(inst) or {}
    local checks = ns.BOOK_AUTHOR and ns.DevDangerChecks and ns.DevDangerChecks[inst] or {}
    local out = {}
    for i, d in ipairs(src) do
        local x = edits[d[1]]
        if not (x and x.gone) then
            x = x or {}
            local w = d.w
            if x.w ~= nil then w = x.w ~= "" and x.w or nil end
            local check = checks[d[1]]
            if x.check ~= nil then check = x.check ~= "" and x.check or nil end
            if not ns.BOOK_AUTHOR then check = nil end
            local e = { key = d[1], title = x.title or d[1], level = x.level or d.level or 1, who = d.who, tip = x.tip or d.tip, w = w,
                        after = d.after, check = check, order = i, spots = {}, edited = next(x) ~= nil }
            -- (x.spots: where the author put its marks, { { floor, x, y }, ... }, in place of the file's)
            -- (extra, boss: what the spot was before any of the danger's marks was touched: one shown only when
            -- the danger is pointed at, a bare "!" by its boss. Kept, so moving ONE mark leaves the others as they
            -- were: until 2026-11-16 the first move turned every other place into a ring shown always.)
            for _, sp in ipairs(x.spots or {}) do e.spots[#e.spots + 1] = { sp[1], sp[2], sp[3], sp[4], extra = sp.extra, boss = sp.boss, auto = sp.auto } end
            for ai, a in ipairs(not x.spots and d.at or {}) do
                if a.boss then
                    local s = BossSpot(inst, a.boss)
                    -- (beside the boss's own marker, up and to the right of it, not on it)
                    if s then e.spots[#e.spots + 1] = { s[1], math.min(0.98, s[2] + 0.026), math.max(0.02, s[3] - 0.036), boss = a.boss } end
                elseif a.mobs then
                    -- (the thickest of them is its mark; the others show when the danger is pointed at)
                    -- (worked out here from every monster's place where that file is, the dev copy; a release leaves
                    -- it out, and takes the same spots worked out beforehand: Data\DungeonDangerSpots.lua, written
                    -- by tools\dangers_spots.lua. Until 2026-11-16 a build had no mark at all for these dangers.)
                    local found = Clusters(inst, a.mobs, a.most)
                    if #found == 0 then
                        local baked = ns.DungeonDangerSpots and ns.DungeonDangerSpots[inst] and ns.DungeonDangerSpots[inst][d[1]]
                        for _, s in ipairs(baked and baked[ai] or {}) do found[#found + 1] = { s[1], s[2], s[3] } end
                    end
                    for k, s in ipairs(found) do
                        s.auto = true   -- (worked out, not put there by hand: may step aside for a book's number)
                        s.extra = k > 1 or nil
                        e.spots[#e.spots + 1] = s
                    end
                elseif type(a[1]) == "number" then
                    e.spots[#e.spots + 1] = { a[1], a[2], a[3], a[4], extra = a.extra }   -- (a[4]: its size, 1 if none; extra: shown only when pointed at)
                end
            end
            -- (bossNames: the bosses it lies with, for their tooltips. pastWith: the bosses it lies in front
            -- of: all of them dead this run, it's behind you. Said in the data (before), or by the author
            -- (false: no boss ends it); unsaid, a danger that IS a boss and nothing else lies with that boss)
            local only = d.at and #d.at > 0 and not d.after
            for _, a in ipairs(d.at or {}) do
                if a.boss then
                    e.bossNames = e.bossNames or {}
                    e.bossNames[#e.bossNames + 1] = a.boss
                else
                    only = false
                end
            end
            e.pastWith = only and e.bossNames or nil
            if d.before then e.pastWith = d.before end
            if x.before ~= nil then e.pastWith = x.before or nil end
            if e.pastWith and #e.pastWith == 0 then e.pastWith = nil end
            e.fork = d.fork
            if x.fork ~= nil then e.fork = x.fork or nil end
            out[#out + 1] = e
        end
    end
    for key, x in pairs(edits) do
        if x.new and x.title then
            local e = { key = key, title = x.title, level = x.level or 1, tip = x.tip or "", w = x.w ~= "" and x.w or nil,
                        check = x.check ~= "" and x.check or nil, order = 1000 + #out, spots = {}, edited = true, new = true }
            for _, sp in ipairs(x.spots or {}) do e.spots[#e.spots + 1] = { sp[1], sp[2], sp[3], sp[4] } end
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.order < b.order
    end)
    for n, e in ipairs(out) do e.n = n end
    lists[inst] = out
    return out
end
function ns.DangersOf(inst) return List(inst) end

-- a boss's own tooltip (Dungeon.lua's list and markers): the dangers that lie with it, his rating and what to do
-- said: words the tooltip has already (the book's own note on that boss): his line is the same note, so it is
-- not said a second time (the user, 2026-11-15: "We have a lot of doubled information presenting")
local function Same(a, b)
    local function Bare(s) return (tostring(s or ""):lower():gsub("[^%a%d]", "")) end
    return a ~= nil and b ~= nil and Bare(a) ~= "" and Bare(a) == Bare(b)
end
function ns.DangersBossLines(inst, boss, said)
    if not (On() and inst and boss) then return end
    local list = List(inst)
    if not list then return end
    for _, e in ipairs(list) do
        for _, name in ipairs(e.bossNames or {}) do
            if name == boss then
                GameTooltip:AddLine(string.rep("!", e.level or 1) .. "  " .. e.title, 1, 0.42, 0.3)
                -- (his own line first, as on the note: the tips are written to ADD to it since 2026-11-14, and
                -- alone some no longer say what happens)
                if e.w and e.w ~= "" and not Same(e.w, said) then GameTooltip:AddLine(e.w, 0.85, 0.73, 0.54, true) end
                if e.tip and e.tip ~= "" then GameTooltip:AddLine(e.tip, 1, 0.93, 0.78, true) end
                break
            end
        end
    end
end

-- Now: a danger that follows a boss's death, for a while after the kill --------------------------------

local seenKill = {}   -- [boss, lower case] = GetTime() when its kill was first seen (false: already dead when this run was first looked at)
local primed          -- the run (instance) whose kills so far have been set aside as old
-- (looked at whether or not the map is up, so "now" starts at the kill, not when the map next opens)
local function TrackKills()
    local run = ns.db and ns.db.dungeonRun
    local inst = run and run.id
    local list = inst and run.kills and ns.DungeonDangers and ns.DungeonDangers[inst]
    if not list then primed = nil return end
    local fresh = primed == inst
    for _, d in ipairs(list) do
        for _, boss in ipairs(d.after or {}) do
            local key = boss:lower()
            if run.kills[key] then
                if seenKill[key] == nil then seenKill[key] = fresh and GetTime() or false end
            else
                seenKill[key] = nil
            end
        end
    end
    primed = inst
end
-- (a test, for looking at "now" outside a run: /waymark dangers now, or its button on the test bench. For a
-- minute every danger that comes after a boss's death is "now" in whichever dungeon is shown; again: it ends.)
local testNow
function ns.DangersTestNow()
    testNow = (not testNow or GetTime() - testNow >= 60) and GetTime() or nil
    print("Waymark: " .. (testNow and "for a minute, every danger that follows a boss's death is \"now\". Open a dungeon map (the Deadmines: the ambush by the x). Again: ends it."
          or "the \"now\" test is over."))
end
local function Live(inst, e)
    if not e.after then return false end
    if testNow and GetTime() - testNow < 60 then return true end
    local run = ns.db and ns.db.dungeonRun
    if not (run and run.id == inst and run.kills) then return false end
    local now = GetTime()
    for _, boss in ipairs(e.after) do
        local at = seenKill[boss:lower()]
        if at and run.kills[boss:lower()] and now - at < NOW_FOR then return true end
    end
    return false
end

-- behind you: a danger that is a boss (or bosses) and nothing else, all of them dead this run
local function Past(inst, e)
    if not e.pastWith then return false end
    local run = ns.db and ns.db.dungeonRun
    if not (run and run.id == inst and run.kills) then return false end
    for _, boss in ipairs(e.pastWith) do
        if not run.kills[boss:lower()] then return false end
    end
    return true
end

-- the dungeon's bosses in the order they're usually killed
local function BossOrder(inst)
    if ns.DungeonBossesInOrder then return ns.DungeonBossesInOrder(inst) end
    local out = {}
    for _, b in ipairs(ns.DungeonEncounters and ns.DungeonEncounters[inst] or {}) do
        if not b.rare and not b.friend then out[#out + 1] = b[1] end
    end
    return out
end
-- next: on a run here, not behind you, in front of ONE boss, and the boss before that one in the usual order
-- is dead (or there is none). Never at a fork, where the usual order says nothing.
local function Next(inst, e)
    if e.fork or not e.pastWith or #e.pastWith ~= 1 then return false end
    local run = ns.db and ns.db.dungeonRun
    if not (run and run.id == inst and run.kills) then return false end
    if run.kills[e.pastWith[1]:lower()] then return false end
    local prev
    for _, name in ipairs(BossOrder(inst)) do
        if name == e.pastWith[1] then return prev == nil or run.kills[prev:lower()] and true or false end
        prev = name
    end
    return false
end

-- The tag: a slip of paper by the cursor -------------------------------------------------------------

local tags = {}   -- paper: by a mark on the map; glass: beside the note
local function Glass(f, edge, alpha)
    if ns.GlassPanel then return ns.GlassPanel(f, edge, alpha) end
    local back = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    back:SetAllPoints()
    back:SetColorTexture(0.055, 0.06, 0.07, alpha or 0.8)
    return back
end
local function Paper(f, l, r, t, b)
    -- (the notes' paper: torn edges and a soft shadow, Dungeon.lua's ns.PaperSlip; without it, a plain window)
    if ns.PaperSlip then return ns.PaperSlip(f, l, r, t, b) end
    local paper = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    paper:SetAllPoints()
    paper:SetTexture(NOTES .. "Paper")
    paper:SetTexCoord(l, r, t, b)
    paper:SetVertexColor(0.96, 0.92, 0.84)
    return paper
end
local function Tag(glass)
    local kind = glass and "glass" or "paper"
    local tag = tags[kind]
    if tag then return tag end
    tag = CreateFrame("Frame", nil, UIParent)
    tags[kind] = tag
    tag:SetFrameStrata("TOOLTIP")
    tag:SetWidth(TAG_W)
    tag:EnableMouse(false)
    if glass then Glass(tag, 0, 0.93) else Paper(tag, 0.18, 0.44, 0.55, 0.80) end
    local function Line(font, size, color)
        local fs = tag:CreateFontString(nil, "OVERLAY")
        Font(fs, font, size)
        fs:SetTextColor(color[1], color[2], color[3])
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWidth(TAG_W - 28)
        fs:SetSpacing(2)
        return fs
    end
    tag.w = Line(HAND, glass and 14 or 18, glass and G_HAND or P_RED)   -- (18 on paper: at 15 "a bit small", the user 2026-11-15)
    tag.rule = tag:CreateTexture(nil, "ARTWORK")
    if glass then tag.rule:SetColorTexture(G_GOLD[1], G_GOLD[2], G_GOLD[3], 0.35) else tag.rule:SetColorTexture(P_SOFT[1], P_SOFT[2], P_SOFT[3], 0.3) end
    tag.rule:SetHeight(1)
    tag.title = glass and Line(PLAIN, 12, G_GOLD) or Line(FELIPA, 17, P_INK)
    tag.tip = Line(PLAIN, 11, glass and G_TEXT or P_INK)
    tag.foot = Line(PLAIN, glass and 10 or 11, glass and G_FAINT or P_SOFT)
    tag.head = Line(PLAIN, glass and 10 or 11, glass and G_FAINT or P_SOFT)   -- (ns.PaperNote: the boss the ring is on)
    tag.head:Hide()
    tag:Hide()
    return tag
end

-- the book's own ring, at this mark or at the boss the danger lies with, says his line already (it is the same
-- note: Data\FoundNotes.lua). Then the tag by the mark leaves it out, so the two hovers side by side do not
-- say one sentence twice (the user, 2026-11-15: "lets try that")
local function BookSays(inst, e, k)
    if not (ns.FoundNoteAt and inst and e.w and e.w ~= "") then return false end
    local function At(s)
        if not s then return false end
        local n, text = ns.FoundNoteAt(inst, s[1], s[2], s[3])
        return n ~= nil and Same(e.w, text)
    end
    if At(k and e.spots[k]) then return true end
    for _, boss in ipairs(e.bossNames or {}) do
        if At(BossSpot(inst, boss)) then return true end
    end
    return false
end

-- One place, one mark, one hover (the user, 2026-11-15, with two shots of the Deadmines' ambush told four ways:
-- "Doubled info, doubled marks, etc. We need a rule or system to solve this. I cannot check every single mark on
-- every dungeon"). The rule, for every dungeon at once:
--   1. the book owns the place: where a note's mark (ring, x, number) already is, the danger draws no ring and takes no hover of its own. A small "!" beside the book's mark
--      is all it adds: there is a danger here, larger when it is "now", struck when it is behind you;
--   2. one hover a place: the book's mark says its note and, under it, the danger (ns.PaperNote); its click
--      menu opens the danger on the note (ns.DangersAtNote, ns.DangersLead);
--   3. words written on the map in front of you are not said again on a tag.
-- tools\dangers_doubles.lua lists what the rule catches in the shipped files, and fails on what it can't.
local BOOK_REACH = 0.03   -- of the picture: a danger's place this near a book mark is that mark's place
local atNote = {}         -- [the note's number] = { dangers at its mark }, on the floor shown
local paperHover, SetHovered
local function Bare(s) return (tostring(s or ""):lower():gsub("[^%a%d]", "")) end
local bookAt, bookAtT = {}, 0
-- the book's mark this spot lies at: the note's number and where its mark is (kept a second: asked at every redraw)
local function BookAt(inst, s)
    if not ns.FoundNoteAt then return end
    local now = GetTime and GetTime() or 0
    if now - bookAtT > 1 then bookAt, bookAtT = {}, now end
    local c = bookAt[s]
    if c == nil then
        local at = s.boss and BossSpot(inst, s.boss) or s
        local n, _, x, y, kind, na = ns.FoundNoteAt(inst, at[1], at[2], at[3], s.boss and 0.015 or BOOK_REACH)
        -- (crowded: the "!" would sit by the note's number. The "!" goes up and to the right of the mark, about
        -- 43 degrees; the number stands at na degrees round it, 38 unless it was dragged; a bare number IS the mark)
        -- (kept: the side the "!" goes when it shows, across the mark from its number, so the two never lie on
        -- each other. The user, 2026-11-15, with the "now" test: "'!' ends up under the number 3". A bare number
        -- is on the spot itself: the "!" up and to the right of it.)
        local a = math.rad(kind == "number" and 43 or ((na or 38) + 180))
        c = n and { n, x + math.cos(a) * 0.034, y - math.sin(a) * 0.051 } or false
        bookAt[s] = c
    end
    if c then return c[1], c[2], c[3], c[4] end
end
-- his line is written in ink on this floor; with a spot: that spot lies on the writing (returns its top left)
local function Inked(inst, floor, e, s)
    if not (ns.FoundInkWords and e.w and e.w ~= "") then return end
    local w = Bare(e.w)
    for _, m in ipairs(ns.FoundInkWords(inst, floor) or {}) do
        local t = Bare(m[1])
        if #t >= 6 and w:find(t, 1, true) then
            if not s then return m[2], m[3] end
            if s[2] - m[2] > -0.04 and s[2] - m[2] < 0.35 and math.abs(s[3] - m[3]) < 0.07 then return m[2], m[3] end
        end
    end
end

-- also: other dangers at the same place, named under this one; hint: what a click does, said small
local function ShowTag(e, owner, side, onMap, also, hint)
    local t = Tag(not onMap)
    local other = tags[onMap and "glass" or "paper"]
    if other then other:Hide() end
    t.head:Hide()   -- (the book's slip's own: ns.PaperNote)
    local y = -12
    local function Put(fs, text, gap)
        if text and text ~= "" then
            fs:SetText(text)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", t, "TOPLEFT", 14, y)
            fs:Show()
            y = y - fs:GetStringHeight() - (gap or 6)
        else
            fs:Hide()
        end
    end
    local w = (onMap or HAND_ON_GLASS) and e.w or nil
    if onMap and w and (BookSays(owner.inst, e, owner.k) or Inked(owner.inst, owner.floor, e)) then w = nil end
    if not onMap then
        HandFont(t.w)
        t:SetScale(Cfg().dangersScale or 1)   -- (the slip beside the note is the note's size)
    end
    Put(t.w, w, 7)
    if w and w ~= "" then
        t.rule:ClearAllPoints()
        t.rule:SetPoint("TOPLEFT", t, "TOPLEFT", 14, y + 3)
        t.rule:SetPoint("TOPRIGHT", t, "TOPRIGHT", -14, y + 3)
        t.rule:Show()
        y = y - 4
    else
        t.rule:Hide()
    end
    Put(t.title, e.title, 4)
    Put(t.tip, e.tip, 7)
    local foot = e.who and (e.who:sub(1, 1):upper() .. e.who:sub(2) .. ".") or nil   -- (who is meant; never a count)
    local function More(line) foot = (foot and (foot .. "\n") or "") .. line end
    if also and #also > 0 then
        local names = {}
        for _, o in ipairs(also) do names[#names + 1] = o.title end
        More("Here too: " .. table.concat(names, "; ") .. ".")
    end
    -- (the author's own lines only with the quill out or Shift held: without them the tag is what a player
    -- sees. The user, 2026-11-15: "its hard to remember all that is dev only")
    if ns.BOOK_AUTHOR and ((ns.QuillOut and ns.QuillOut()) or IsShiftKeyDown()) then
        if e.check then More("To check: " .. e.check) end
        More(e.pastWith and ("Behind you when " .. table.concat(e.pastWith, " and ") .. (#e.pastWith > 1 and " are" or " is") .. " dead." .. (e.fork and " At a fork: never marked next." or ""))
             or "No boss ends it: never struck.")
        if e.edited then More("Yours, not yet in the file.") end
        if onMap then More("Ctrl or the quill out: drag moves this mark, the wheel sizes it. Right-click: rub out.") end
    end
    if hint then More(hint) end
    Put(t.foot, foot, 4)
    t:SetHeight(-y + 10)
    t:ClearAllPoints()
    if side == "left" then
        t:SetPoint("TOPRIGHT", owner, "TOPLEFT", -10, 4)
    elseif side == "right" then
        t:SetPoint("TOPLEFT", owner, "TOPRIGHT", 10, 4)
    else
        t:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", 4, 4)
    end
    t:Show()
end
local function HideTag() for _, t in pairs(tags) do t:Hide() end end

-- The same slip of paper for the book's own ring on the dungeon map (Notebook.lua): his note in his hand, and
-- one small line under it. So the two things one can point at side by side, a ring and a danger mark, answer
-- in one dress (the user, 2026-11-15: "paper for both").
-- n: the note's number. A danger that lies at its mark is said under the note, on the same slip (the rule above).
-- head: the boss whose skull the ring is on, and "Defeated" (Notebook.lua asks Dungeon.lua). The ring's frame lies
-- over the skull, so the boss's own tooltip cannot be had there; the user, 2026-11-16, of the three ways out
-- (this, two tooltips on one spot, or leaving the name to the Bosses list): "Yes, build it".
function ns.PaperNote(owner, words, foot, n, head)
    local t = Tag(false)
    if tags.glass then tags.glass:Hide() end
    t.rule:Hide()
    t.title:Hide()
    t.tip:Hide()
    local y = -12
    if head and head ~= "" then
        t.head:SetText(head)
        t.head:ClearAllPoints()
        t.head:SetPoint("TOPLEFT", t, "TOPLEFT", 14, y)
        t.head:Show()
        y = y - t.head:GetStringHeight() - 5
    else
        t.head:Hide()
    end
    t.w:SetText(words or "")
    t.w:ClearAllPoints()
    t.w:SetPoint("TOPLEFT", t, "TOPLEFT", 14, y)
    t.w:Show()
    y = y - t.w:GetStringHeight() - 7
    local here = n and atNote[n]
    local e = here and here[1]
    if e then
        t.rule:ClearAllPoints()
        t.rule:SetPoint("TOPLEFT", t, "TOPLEFT", 14, y + 3)
        t.rule:SetPoint("TOPRIGHT", t, "TOPRIGHT", -14, y + 3)
        t.rule:Show()
        y = y - 4
        for _, fs in ipairs({ t.title, t.tip }) do
            fs:SetText(fs == t.title and e.title or e.tip or "")
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", t, "TOPLEFT", 14, y)
            fs:Show()
            y = y - fs:GetStringHeight() - (fs == t.title and 4 or 7)
        end
        if #here > 1 then
            local names = {}
            for i = 2, #here do names[#names + 1] = here[i].title end
            foot = "Here too: " .. table.concat(names, "; ") .. "." .. (foot and foot ~= "" and ("\n" .. foot) or "")
        end
        paperHover = true
        if SetHovered then SetHovered(e) end   -- (its other places on this floor show while it is pointed at)
    end
    if foot and foot ~= "" then
        t.foot:SetText(foot)
        t.foot:ClearAllPoints()
        t.foot:SetPoint("TOPLEFT", t, "TOPLEFT", 14, y)
        t.foot:Show()
        y = y - t.foot:GetStringHeight() - 4
    else
        t.foot:Hide()
    end
    t:SetHeight(-y + 10)
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", 4, 4)
    t:Show()
end
function ns.PaperNoteHide()
    HideTag()
    if paperHover then
        paperHover = nil
        if SetHovered then SetHovered(nil) end
    end
end
function ns.DangersAtNote(n) return n and atNote[n] or nil end

-- State shared by the marks and the note ---------------------------------------------------------------

local shownInst, shownFloor   -- the dungeon and floor whose marks are up (nil: no dungeon map showing)
local noteInst                -- the dungeon the note is about
local hovered                 -- the danger under the cursor (on the map or the note): its marks grow
local picked                  -- the key of the danger the user made lead (nil: the run picks)
local pickedPast              -- it was behind you already when chosen (so falling behind doesn't let it go)
local details                 -- the leading danger's details are open under it
local over                    -- the pointer is on the note (show less: the rest unfolds)
local Refresh                 -- (below)

SetHovered = function(e)
    if hovered ~= e then
        hovered = e
        if Refresh then Refresh() end
    end
end

-- the dungeon's map, at a floor: the Battlefield map up if it's shut, the dungeon looked into from outside
local function OpenMap(inst, floor)
    if not inst then return end
    local map = BattlefieldMapFrame
    if map and not map:IsShown() and not ns.standBy then map:Show() end
    if shownInst ~= inst and ns.PreviewDungeon then ns.PreviewDungeon(inst) end
    if floor and ns.DungeonGoFloor then ns.DungeonGoFloor(inst, floor) end
end

-- The marks on the map --------------------------------------------------------------------------------

local layer, host
local buttons = {}

local function Seed(s)
    local h = 7
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2000000000 end
    return h + 1
end

local SetSpots  -- (below, with the author's edits)
local function CopySpots(e)
    local spots = {}
    for k, sp in ipairs(e.spots) do spots[k] = { sp[1], sp[2], sp[3], sp[4], extra = sp.extra, boss = sp.boss, auto = sp.auto } end
    return spots
end
-- the author has a mark in hand: Ctrl held, or the quill out with any tool but the rubber (Controls.lua's rule
-- for everything movable on a map)
local function InHand()
    if not ns.BOOK_AUTHOR then return false end
    if ns.PicksUp then return ns.PicksUp() and true or false end
    return IsControlKeyDown() and true or false
end
-- where the cursor is on the map's picture, 0-1 across and down
local function CursorOnMap()
    local s = layer:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local left, top, w, h = layer:GetLeft(), layer:GetTop(), layer:GetWidth(), layer:GetHeight()
    if not (left and top and w and h and w > 0 and h > 0) then return end
    return math.max(0.01, math.min(0.99, (cx / s - left) / w)), math.max(0.01, math.min(0.99, (top - cy / s) / h))
end
local byKey = {}
local function MarkButton(key)
    local b = byKey[key]
    if b then return b end
    b = CreateFrame("Button", nil, layer)
    byKey[key] = b
    buttons[#buttons + 1] = b
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if ns.BOOK_AUTHOR then
        -- (the author: a drag with the mark in hand puts it somewhere else on this floor; the wheel sizes it)
        b:SetScript("OnMouseWheel", function(self, delta)
            local spots = CopySpots(self.e)
            local sp = spots[self.k]
            if not sp then return end
            sp[4] = math.floor(math.max(0.5, math.min(2.5, (sp[4] or 1) * (delta > 0 and 1.1 or 1 / 1.1))) * 100 + 0.5) / 100
            SetSpots(self.inst, self.e, spots)
        end)
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function(self)
            if not InHand() then return end
            self.moving = true
            HideTag()
            self:SetScript("OnUpdate", function(me)
                local x, y = CursorOnMap()
                if not x then return end
                me:ClearAllPoints()
                me:SetPoint("CENTER", layer, "TOPLEFT", x * 1002, -y * 668)
            end)
        end)
        b:SetScript("OnDragStop", function(self)
            if not self.moving then return end
            self.moving = nil
            self:SetScript("OnUpdate", nil)
            local x, y = CursorOnMap()
            if x and self.e.spots[self.k] then
                local spots = CopySpots(self.e)
                spots[self.k] = { spots[self.k][1], math.floor(x * 10000 + 0.5) / 10000, math.floor(y * 10000 + 0.5) / 10000, spots[self.k][4] }
                SetSpots(self.inst, self.e, spots)
            else
                Refresh()
            end
        end)
    end
    b:SetScript("OnEnter", function(self)
        if self.moving then return end
        hovered = self.e
        ShowTag(self.e, self, nil, true, self.also)
        Refresh()
    end)
    b:SetScript("OnLeave", function()
        hovered = nil
        HideTag()
        Refresh()
    end)
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if not (ns.BOOK_AUTHOR and ns.QuillMenu) then return end
            local me = self
            HideTag()
            ns.QuillMenu({ { "Rub out", function()
                local spots = CopySpots(me.e)
                table.remove(spots, me.k)
                SetSpots(me.inst, me.e, spots)
                -- (one click takes a mark off; say where it comes back from)
                print("Waymark: mark rubbed out. To get it back: right-click \"" .. me.e.title .. "\" on the note, \"Its marks as written again\".")
            end } })
            return
        end
        Cfg().dangersOpen = true
        picked, pickedPast, details = self.e.key, Past(self.inst, self.e), true
        Refresh()
    end)
    return b
end
-- a danger made to lead on the note with its details open, as a click on its mark does (for the book's mark
-- a danger lies at: Notebook.lua's menu)
function ns.DangersLead(e)
    if not (e and Cfg()) then return end
    Cfg().dangersOpen = true
    picked, pickedPast, details = e.key, shownInst and Past(shownInst, e) or false, true
    Refresh()
end

local function DrawMarks(canvas, inst, floor, list)
    if not layer then
        layer = CreateFrame("Frame", nil, canvas)
        if ns.InkHost then
            host = ns.InkHost(layer)
            host:ClearAllPoints()
            host:SetPoint("TOPLEFT", layer, "TOPLEFT")
            host:SetSize(1002, 668)
        end
    end
    if layer:GetParent() ~= canvas then layer:SetParent(canvas) end
    layer:ClearAllPoints()
    layer:SetPoint("TOPLEFT", canvas, "TOPLEFT")
    layer:SetSize(1002, 668)
    layer:SetFrameLevel(canvas:GetFrameLevel() + 7)
    -- Fewer rings (the user, 2026-11-11: three near each other is all right, four is a lot, and worse when they
    -- speak of the same thing; the book's own rings and the quest pins are on this map too):
    --   * a danger that IS a boss gets no ring: a small "!" by the skull, which has the book's ring already, and
    --     the boss's own tooltip says the danger too (ns.DangersBossLines);
    --   * of the places a danger's monsters stand, only the thickest is marked;
    --   * two dangers at one place share one mark: the worse one's, the other named on its slip.
    -- Pointed at (on the map or on the note), open on the note, or "now", a danger shows all its places,
    -- ringed and larger. What the author put somewhere by hand always shows.
    -- (and one place, one mark: the rule above ShowTag. For the author with Ctrl held a mark is drawn where it
    -- really is, ring and all, so it can be seen and moved. Ctrl alone, not the quill being out: the user has
    -- the quill out much of the time, saw both hovers at VanCleef and took the rule for broken, 2026-11-15.)
    -- Off the book's numbers (the user, 2026-11-16: "that the numbers aren't hidden behind another ring that only
    -- appears when you hover one danger"). A ring that would take in a note's number, an x or a bare number
    -- steps straight away from it until its line is clear, sized as it is when pointed at, so it stands in one
    -- place at rest and on hover. Only a place that was worked out (where the monsters stand thickest, a boss's
    -- "!"): a mark put somewhere by hand is where it was put (tools\dangers_overlap.lua lists those).
    -- The same for a ring that would land right on a boss it is not about.
    local numbers = ns.FoundNumbersOn and ns.FoundNumbersOn(inst, floor) or {}
    local function Aside(e, s)
        if not (s.auto or s.boss) then return end
        local R = 20 * (0.66 + 0.11 * (e.level or 1)) * 1.25 * (s[4] or 1)
        local x, y, moved = s[2], s[3], false
        local function Off(ox, oy, r, only)
            local dx, dy = (x - ox) * 1002, (y - oy) * 668
            local d = math.sqrt(dx * dx + dy * dy)
            local need = R + r + 2
            if d < (only or need) then
                if d < 0.5 then dx, dy, d = 0.7, -0.7, 1 end
                x, y, moved = ox + dx / d * need / 1002, oy + dy / d * need / 668, true
            end
        end
        for _ = 1, 2 do
            for _, o in ipairs(numbers) do Off(o[1], o[2], o[3]) end
            for name, b in pairs(ns.DungeonBosses and ns.DungeonBosses[inst] or {}) do
                local at = name ~= s.boss and BossSpot(inst, name)
                -- (R + 11: until its line is clear of the skull's own frame, 22 px. It was 12 px, only "right on
                -- it": Stratholme's sorcerers' ring stood 17 px from the Hammersmith's skull and read as his.)
                if at and at[1] == floor then Off(at[2], at[3], 15, R + 11) end
            end
        end
        if moved then return math.max(0.02, math.min(0.98, x)), math.max(0.02, math.min(0.98, y)) end
    end
    local cand = {}
    local inHand = InHand()
    local real = ns.BOOK_AUTHOR and IsControlKeyDown() and true or false
    for n in pairs(atNote) do atNote[n] = nil end
    for _, e in ipairs(list) do   -- (the worst first, as the list is)
        local on = e == hovered or e.key == picked
        local live = Live(inst, e)
        for k, s in ipairs(e.spots) do
            if s[1] == floor then
                local n, bx, by = BookAt(inst, s)
                if n then
                    atNote[n] = atNote[n] or {}
                    local have
                    for _, o in ipairs(atNote[n]) do have = have or o == e end
                    if not have then table.insert(atNote[n], e) end
                end
                -- (at the book's x: nothing at rest. His x says "something bad here" already, and with its
                -- number and a "!" one thing had three marks; the user, 2026-11-15: "Either we remove the x or
                -- we remove the !". The "!" comes only while the danger is "now", the one thing the x can't say.)
                -- (And beside a ring or a number the same, an hour later: "same thing on vancleef. ! showing".
                -- I had kept it there, a ring saying only "a note"; the user wants one rule: the book's mark alone.)
                -- (Then, the same morning: "You misunderstand. I didnt want the tip gone. I wanted the drawn (!)
                -- gone if having it there meant it sat basically under the number, or ring. Its cluttery." So:
                -- the "!" is left out only where it would sit by the number; where the number has been dragged
                -- to another side of the mark, the "!" is drawn. The tip is on the book mark's slip either way.)
                -- (And the rule in the user's own words, minutes later: "1 mechanic, 1 tooltip, 1 visual for each
                -- spot. Hovering can show more '!' like the bfd cultists". So at a book mark the book's mark is
                -- the one visual, wherever its number stands; `crowded` is no longer asked. Pointing at the mark
                -- brings up the danger's OTHER places, as pointing at any danger does.)
                if n and not real and not live then
                    -- (nothing drawn)
                elseif on or live or not s.extra then
                    local c = { e = e, k = k, s = s, on = on, live = live }
                    if n and not real then
                        c.book = n
                        -- (beside the book's mark, on the side its number is not)
                        c.px, c.py = math.max(0.02, math.min(0.98, bx)), math.max(0.02, math.min(0.98, by))
                    elseif not real then
                        c.px, c.py = Aside(e, s)
                    end
                    -- (a mark by his own writing keeps its ring, where it was put: for a day it lost the ring
                    -- and was moved left of the first word. The user moved one beside "These spirits bind
                    -- throat" and it "dissapeared": a mark placed by hand is deliberate, and stays, 2026-11-15.
                    -- Its tag still leaves the written words out.)
                    cand[#cand + 1] = c
                end
            end
        end
    end
    -- (the danger pointed at goes first: another danger's mark at one of its places joins ITS ring, named on its
    -- slip, where until 2026-11-16 the two rings were drawn on top of each other. And with Ctrl held nothing
    -- joins: a mark dropped on another danger's mark lay under it and could not be picked up again.)
    do
        local first, rest = {}, {}
        for _, c in ipairs(cand) do if c.on then first[#first + 1] = c else rest[#rest + 1] = c end end
        for _, c in ipairs(rest) do first[#first + 1] = c end
        cand = first
    end
    local kept = {}
    for _, c in ipairs(cand) do
        local with, twice
        if not real then
            for _, o in ipairs(kept) do
                if (o.s[2] - c.s[2]) ^ 2 + ((o.s[3] - c.s[3]) * 0.667) ^ 2 < TOGETHER * TOGETHER then
                    -- (the same danger a second time at one place draws nothing: the Temple's dragonkin halls had two
                    -- rings 25 px apart, its two sets of monsters standing thickest in the same hall)
                    -- (pointed at too, since 2026-11-16: the second ring came up under the pointer, took the
                    -- hover, the first let go, the second went away: a flicker. tools\dangers_overlap.lua, STEALS)
                    if o.e == c.e then twice = true break end
                    if not c.on then with = o break end
                end
            end
        end
        if twice then
            -- (nothing)
        elseif with then
            with.also = with.also or {}
            with.also[#with.also + 1] = c.e
        else
            kept[#kept + 1] = c
        end
    end
    local marks, used = {}, {}
    for _, c in ipairs(kept) do
        local e, s = c.e, c.s
        local past = not c.live and Past(inst, e)
        local owned = c.book or c.ink
        local px, py = c.px or s[2], c.py or s[3]
        local ringed = not owned and (c.on or c.live or not s.boss)
        local sc = (0.66 + 0.11 * (e.level or 1)) * (c.on and 1.25 or 1) * (c.live and 1.2 or 1) * (s[4] or 1)   -- (a worse one, a bigger ring; s[4]: the author's own size)
        local seed = Seed(inst .. ":" .. e.key .. c.k)
        if ringed then marks[#marks + 1] = { t = "ring", ink = 2, v = 1 + seed % 3, r = seed, p = { px, py }, sc = sc } end
        marks[#marks + 1] = { t = "bang", ink = 2, v = 1 + seed % 2, r = seed + 1, p = { px, py }, sc = sc * (ringed and 0.6 or 0.7) }
        if past then  -- (behind you: struck through, in the book's brown, not the warning's red)
            local dx, dy = 0.017 * sc, 0.019 * sc
            marks[#marks + 1] = { t = "pen", ink = 1, r = seed + 2, p = { math.max(0, px - dx), math.min(1, py + dy), math.min(1, px + dx), math.max(0, py - dy) } }
        end
        -- (a button of its own for each mark, kept by what it marks: the one under the cursor is still there, in
        -- the same place, when pointing at it brings the danger's other marks up)
        -- (none at a book mark: that mark is the one thing to point at there, and it says the danger too)
        if not c.book then
            local b = MarkButton(e.key .. ":" .. c.k)
            b.inst, b.e, b.k, b.also, b.floor = inst, e, c.k, c.also, floor
            b:EnableMouseWheel(inHand)   -- (in hand: the wheel sizes it; else it zooms the map as ever)
            local size = MARK * (ringed and 1 or 0.7)
            b:SetSize(size, size)
            if not b.moving then
                b:ClearAllPoints()
                b:SetPoint("CENTER", layer, "TOPLEFT", px * 1002, -py * 668)
            end
            b:SetFrameLevel(layer:GetFrameLevel() + 2)
            b:Show()
            used[b] = true
        end
    end
    for _, b in ipairs(buttons) do if not used[b] then b:Hide() end end
    if host and ns.InkDrawList then
        host:SetFrameLevel(layer:GetFrameLevel() + 1)
        ns.InkDrawList(host, marks)
    end
    layer:Show()
    return #kept
end

-- The author's edits -----------------------------------------------------------------------------------

local function Changed(inst)
    lists[inst] = nil
    hovered = nil
    Refresh()
end

local function SetEdit(inst, e, field, value)
    local t = EditsOf(inst, true)
    if not t then return end
    local x = t[e.key]
    if not x then
        x = {}
        t[e.key] = x
    end
    x[field] = value
    cleaned[inst] = nil   -- (set back to what the file says: let go again)
    Changed(inst)
end

SetSpots = function(inst, e, spots) SetEdit(inst, e, "spots", spots) end

local function AskWords(inst, e, field, text, sub, max)
    if not ns.Ask then return end
    ns.Ask({ text = text, sub = sub, edit = e[field] or "", maxLetters = max or 255, ok = "Write it", onAccept = function(words)
        words = (words or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if field == "title" and words == "" then return end
        SetEdit(inst, e, field, words)
    end })
end

local function AddDanger(inst)
    if not ns.Ask then return end
    ns.Ask({ text = "A new danger here", sub = "A few words: what it is.", edit = "", maxLetters = 60, ok = "Write it", onAccept = function(words)
        words = (words or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if words == "" then return end
        local t = EditsOf(inst, true)
        local key = "+" .. (time and time() or 0) .. ":" .. words
        t[key] = { new = true, title = words, tip = "", level = 1 }
        picked = key
        Changed(inst)
        AskWords(inst, { key = key, tip = "" }, "tip", words, "What to do about it, plainly.", 400)
    end })
end

-- The note ---------------------------------------------------------------------------------------------

local card, tab
local rows = {}

local function Lock() local c = Cfg() return c and c.dangersLocked end

-- (dragged anywhere unless locked; where it's let go is kept)
local function DragStart()
    if Lock() or not card then return end
    card.moving = true
    HideTag()
    card:StartMoving()
end
local function DragStop()
    if not (card and card.moving) then return end
    card.moving = nil
    card:StopMovingOrSizing()
    local c = Cfg()
    local left, top = card:GetLeft(), card:GetTop()
    if c and left and top then c.dangersAt = { left, top } end
    Refresh()
end
local function Drags(f)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", DragStart)
    f:SetScript("OnDragStop", DragStop)
end

-- the note's menu: on a row, as the book's author, that danger's words first
local SetNoteScale  -- (below, with where the note is)
local function NoteMenu(e)
    if not ns.QuillMenu then return end
    local c, inst = Cfg(), noteInst
    local items = {}
    if e and inst and ns.BOOK_AUTHOR then
        items[#items + 1] = { "Edit its title", function() AskWords(inst, e, "title", "Its title", "A few words, as on the note.", 60) end }
        items[#items + 1] = { "Edit what to do", function() AskWords(inst, e, "tip", e.title, "What to do about it, plainly.", 400) end }
        items[#items + 1] = { "Edit his words", function() AskWords(inst, e, "w", e.title, "The Wanderer's own line, in his hand on the slip. Empty: none.", 120) end }
        local rate = {}
        for n = 1, 3 do
            rate[n] = { string.rep("!", n), function() SetEdit(inst, e, "level", n) end, on = e.level == n }
        end
        items[#items + 1] = { "Its rating", function() end, sub = rate }
        local ends = { { "No boss ends it", function() SetEdit(inst, e, "before", false) end, on = not e.pastWith } }
        for _, boss in ipairs(BossOrder(inst)) do
            local has = false
            for _, b in ipairs(e.pastWith or {}) do if b == boss then has = true end end
            ends[#ends + 1] = { boss, function()
                -- (a click adds it or takes it away: two bosses, where either path leads past it)
                local list = {}
                for _, b in ipairs(e.pastWith or {}) do if b ~= boss then list[#list + 1] = b end end
                if not has then list[#list + 1] = boss end
                SetEdit(inst, e, "before", #list > 0 and list or false)
            end, on = has }
        end
        items[#items + 1] = { "Behind you when dead", function() end, sub = ends }
        items[#items + 1] = { e.fork and "At a fork: mark it next again" or "At a fork: never mark it next", function() SetEdit(inst, e, "fork", not e.fork) end }
        items[#items + 1] = { "Edit what's to check", function() AskWords(inst, e, "check", e.title, "A question still open about it, for you alone: never in a release. Empty: none.", 200) end }
        if shownInst == inst and shownFloor then
            items[#items + 1] = { "A mark on this floor", function()
                local spots = CopySpots(e)
                spots[#spots + 1] = { shownFloor, 0.5, 0.5 }   -- (in the middle: drag it to its place)
                SetSpots(inst, e, spots)
            end }
        end
        -- (marks moved, sized, added or rubbed out by hand: back to where the file has them, the words untouched)
        local mine = EditsOf(inst) and EditsOf(inst)[e.key]
        if mine and mine.spots and not e.new then
            items[#items + 1] = { "Its marks as written again", function() SetEdit(inst, e, "spots", nil) end }
        end
        if e.edited and not e.new then
            items[#items + 1] = { "Back to the written one", function()
                local t = EditsOf(inst)
                if t then t[e.key] = nil end
                Changed(inst)
            end }
        end
        items[#items + 1] = { "Take it off the list", function()
            local t = EditsOf(inst, true)
            if e.new then t[e.key] = nil else t[e.key] = t[e.key] or {} t[e.key].gone = true end
            if picked == e.key then picked = nil end
            Changed(inst)
        end }
    end
    if inst and ns.BOOK_AUTHOR then
        items[#items + 1] = { "Add a danger", function() AddDanger(inst) end }
    end
    if inst then items[#items + 1] = { "This dungeon's map", function() OpenMap(inst) end } end
    items[#items + 1] = { c.dangersLocked and "Unlock note" or "Lock note in place", function()
        c.dangersLocked = not c.dangersLocked or nil
        Refresh()
    end }
    items[#items + 1] = { c.dangersFolded and "Show all" or "Show less", function()
        c.dangersFolded = not c.dangersFolded or nil
        Refresh()
    end }
    if picked then
        items[#items + 1] = { "Follow the run", function()
            picked, pickedPast, details = nil, nil, nil
            Refresh()
        end }
    end
    local sizes = {}
    for k, sz in ipairs(SIZES) do
        sizes[k] = { sz[1], function() SetNoteScale(sz[2]) end, on = (c.dangersScale or 1) == sz[2] }
    end
    items[#items + 1] = { "Size", function() end, sub = sizes }
    items[#items + 1] = { c.dangersPlainHand and "His line in his hand" or "His line in plain type", function()
        c.dangersPlainHand = not c.dangersPlainHand or nil
        Refresh()
    end }
    if c.dangersAt then
        items[#items + 1] = { "Back beside the map", function()
            c.dangersAt = nil
            Refresh()
        end }
    end
    items[#items + 1] = { "Put away", function()
        c.dangersOpen = false
        Refresh()
    end }
    ns.QuillMenu(items)
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, card)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Drags(r)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT")
    hl:SetPoint("BOTTOMRIGHT", -EDGE + 6, 0)
    hl:SetColorTexture(G_GOLD[1], G_GOLD[2], G_GOLD[3], 0.14)
    r.share = r:CreateFontString(nil, "OVERLAY")   -- (his rating)
    Font(r.share, HAND, 15)
    r.share:SetPoint("TOPRIGHT", r, "TOPLEFT", TEXT_X - 8, -3)
    r.share:SetJustifyH("RIGHT")
    r.share:SetTextColor(G_RED[1], G_RED[2], G_RED[3])
    r.title = r:CreateFontString(nil, "OVERLAY")
    Font(r.title, PLAIN, 12)
    r.title:SetPoint("TOPLEFT", TEXT_X, -4)
    r.title:SetWidth(TEXT_W)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(true)
    r.w = r:CreateFontString(nil, "OVERLAY")       -- (his own words, in his hand)
    Font(r.w, HAND, 13)
    r.w:SetWidth(TEXT_W)
    r.w:SetJustifyH("LEFT")
    r.w:SetSpacing(2)
    r.w:SetTextColor(G_HAND[1], G_HAND[2], G_HAND[3])
    r.tip = r:CreateFontString(nil, "OVERLAY")
    Font(r.tip, PLAIN, 11)
    r.tip:SetWidth(TEXT_W)
    r.tip:SetJustifyH("LEFT")
    r.tip:SetSpacing(2)
    r.tip:SetTextColor(G_TEXT[1], G_TEXT[2], G_TEXT[3])
    r.away = r:CreateFontString(nil, "OVERLAY")
    Font(r.away, PLAIN, 9)
    r.away:SetTextColor(G_FAINT[1], G_FAINT[2], G_FAINT[3])
    r.strike = r:CreateLine(nil, "OVERLAY")
    r.strike:SetColorTexture(G_FAINT[1], G_FAINT[2], G_FAINT[3], 0.9)
    r.strike:SetThickness(1.1)
    r.strike:Hide()
    r:SetScript("OnEnter", function(self)
        if card.moving then return end
        hovered = self.e
        -- (its details beside the note, unless they are open under it already)
        if not self.inline then
            ShowTag(self.e, self, card.side, nil, nil, "Click: pin this open on the note.")
        end
        Refresh()
    end)
    r:SetScript("OnLeave", function()
        hovered = nil
        HideTag()
        Refresh()
    end)
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            HideTag()
            NoteMenu(self.e)
            return
        end
        local e = self.e
        if self.isLead then
            -- (the one that leads: its details open under it, or close; chosen from here on)
            if picked ~= e.key then picked, pickedPast = e.key, Past(self.inst, e) end
            details = not details or nil
        else
            -- (another one: it leads now with its details open, and the run stops picking)
            picked, pickedPast, details = e.key, Past(self.inst, e), true
        end
        -- (the dungeon's map up, and this danger on another floor: that floor. A shut map stays shut.)
        local here, first = false, e.spots[1]
        for _, sp in ipairs(e.spots) do if sp[1] == shownFloor then here = true end end
        if shownInst == self.inst and not here and first then OpenMap(self.inst, first[1]) end
        HideTag()
        Refresh()
    end)
    rows[i] = r
    return r
end

local function CreateCard()
    card = CreateFrame("Frame", nil, UIParent)
    card:SetFrameStrata("MEDIUM")
    card:SetWidth(CARD_W)
    card:EnableMouse(true)  -- (a click between rows isn't one on the world)
    card:SetMovable(true)
    card:SetClampedToScreen(true)
    Drags(card)
    card:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then NoteMenu(nil) end
    end)
    card:SetScript("OnEnter", function() Refresh() end)   -- (show less: the pointer on it unfolds the rest)
    Glass(card, EDGE)
    -- the heading: its name small, the dungeon's beside it. A click: show less, or all; a right-click: the menu
    local head = CreateFrame("Button", nil, card)
    head:SetPoint("TOPLEFT", 0, -1)
    head:SetSize(CARD_W - EDGE - 20, HEAD_H - 2)
    head:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Drags(head)
    card.title = head:CreateFontString(nil, "OVERLAY")
    Font(card.title, PLAIN, 10)
    card.title:SetTextColor(G_SOFT[1], G_SOFT[2], G_SOFT[3])
    card.title:SetPoint("LEFT", head, "LEFT", 12, -1)
    card.title:SetText("WHAT KILLS HERE")
    card.sub = head:CreateFontString(nil, "OVERLAY")
    Font(card.sub, PLAIN, 10)
    card.sub:SetTextColor(G_GOLD[1], G_GOLD[2], G_GOLD[3])
    card.sub:SetPoint("LEFT", card.title, "RIGHT", 8, 0)
    card.sub:SetPoint("RIGHT", head, "RIGHT", -2, 0)
    card.sub:SetJustifyH("LEFT")
    card.sub:SetWordWrap(false)
    head:SetScript("OnClick", function(_, button)
        local c = Cfg()
        GameTooltip:Hide()
        if button == "RightButton" then
            NoteMenu(nil)
        else
            c.dangersFolded = not c.dangersFolded or nil
            Refresh()
        end
    end)
    head:SetScript("OnEnter", function(self)
        if card.moving then return end
        card.title:SetTextColor(G_TEXT[1], G_TEXT[2], G_TEXT[3])
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("What kills here")
        GameTooltip:AddLine("This dungeon's real dangers, the worst first. Gold is the one coming up. Crossed out is behind you.", 1, 1, 1, true)
        if ns.Hints then
            ns.Hints({ { "Click", Cfg().dangersFolded and "show all" or "show less" }, { "Drag", Lock() and "locked in place" or "move it" },
                       { "Right-click", "menu" } })
        end
        GameTooltip:Show()
        Refresh()
    end)
    head:SetScript("OnLeave", function()
        card.title:SetTextColor(G_SOFT[1], G_SOFT[2], G_SOFT[3])
        GameTooltip:Hide()
    end)
    local close = CreateFrame("Button", nil, card)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -EDGE + 2, -4)
    close.x = close:CreateFontString(nil, "OVERLAY")
    Font(close.x, PLAIN, 11)
    close.x:SetTextColor(G_FAINT[1], G_FAINT[2], G_FAINT[3])
    close.x:SetPoint("CENTER")
    close.x:SetText("x")
    close:SetScript("OnClick", function()
        Cfg().dangersOpen = false
        GameTooltip:Hide()
        Refresh()
    end)
    close:SetScript("OnEnter", function(self)
        self.x:SetTextColor(G_TEXT[1], G_TEXT[2], G_TEXT[3])
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Put away")
        GameTooltip:AddLine("The \"!\" beside the map's Bosses list brings it back.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    close:SetScript("OnLeave", function(self)
        self.x:SetTextColor(G_FAINT[1], G_FAINT[2], G_FAINT[3])
        GameTooltip:Hide()
    end)
    card:Hide()
end

-- the danger that leads: the one the user chose; else the run's: one that is "now", the one in front of the next
-- boss alive, the worst not yet behind you. A chosen one that falls behind you is let go (the run picks again).
local function Lead(inst, list)
    if picked then
        local found
        for _, e in ipairs(list) do if e.key == picked then found = e end end
        if found and (pickedPast or Live(inst, found) or not Past(inst, found)) then return found end
        picked, pickedPast, details = nil, nil, nil
    end
    for _, e in ipairs(list) do if Live(inst, e) then return e end end
    for _, e in ipairs(list) do if Next(inst, e) then return e end end
    for _, e in ipairs(list) do if not Past(inst, e) then return e end end
    return list[1]
end

-- what comes fades in while the glass grows to fit (As told's panel: soft, the rest standing still)
local anim = {}   -- { hFrom, hTo, hT }: the note's height on its way
local function Animate(_, e)
    local busy = false
    for _, r in ipairs(rows) do
        if r.fadeT then
            r.fadeT = r.fadeT + e
            local k = math.min(1, r.fadeT / SOFT_IN)
            r:SetAlpha(k)
            if k >= 1 then r.fadeT = nil else busy = true end
        end
        if r.moreT then
            r.moreT = r.moreT + e
            local k = math.min(1, r.moreT / SOFT_IN)
            r.w:SetAlpha(k)
            r.tip:SetAlpha(k)
            if k >= 1 then r.moreT = nil else busy = true end
        end
    end
    if anim.hT then
        anim.hT = anim.hT + e
        local k = math.min(1, anim.hT / SOFT_IN)
        local done = k >= 1
        k = k * k * (3 - 2 * k)
        card:SetHeight(anim.hFrom + (anim.hTo - anim.hFrom) * k)
        if done then anim.hT = nil else busy = true end
    end
    if not busy then card:SetScript("OnUpdate", nil) end
end

-- the note's rows for a dungeon; its height follows them
local function FillCard(inst, list, name)
    card.sub:SetText(name or "")
    local first = not card:IsShown()   -- (just brought out: as it is, nothing fades)
    local moving = false
    local less = Cfg().dangersFolded and true or false
    local lead = Lead(inst, list)
    -- (show less: the lead alone, and with the pointer on the note the rest under it. Show all: "now" first;
    -- then as sorted; last, struck through, what lay with a boss now dead: behind you)
    local order = {}
    if less and lead then order[1] = lead end
    if not less or over then
        for _, e in ipairs(list) do if Live(inst, e) and not (less and e == lead) then order[#order + 1] = e end end
        for _, e in ipairs(list) do if not Live(inst, e) and not Past(inst, e) and not (less and e == lead) then order[#order + 1] = e end end
        for _, e in ipairs(list) do if not Live(inst, e) and Past(inst, e) and not (less and e == lead) then order[#order + 1] = e end end
    end
    local y = -HEAD_H
    for i, e in ipairs(order) do
        local r = Row(i)
        local live = Live(inst, e)
        local past = not live and Past(inst, e)
        -- (fresh: this danger was not on this row a moment ago)
        local fresh = not first and not (r:IsShown() and r.key == e.key)
        local wasInline = not fresh and r.inline
        r.key = e.key
        r.inst, r.e, r.isLead = inst, e, e == lead
        r.share:SetText(string.rep("!", e.level or 1))  -- (his own rating, not a count)
        r.share:SetAlpha(past and 0.35 or 1)
        -- (no "?" on the row for an open "to check" note any more: the user, 2026-11-16, for the release's pictures.
        -- The note itself still shows on the slip, for the author only)
        local dev = ns.BOOK_AUTHOR and (e.edited and "  *" or "") or ""
        r.title:SetText((live and "Now: " or "") .. e.title .. dev)
        local c = live and G_RED or e == lead and G_GOLD or G_TEXT
        r.title:SetTextColor(c[1], c[2], c[3])
        r.title:SetAlpha(past and 0.45 or 1)
        r.strike:SetShown(past)
        if past then
            local tw = math.min(r.title:GetStringWidth() or 0, TEXT_W)
            r.strike:SetStartPoint("TOPLEFT", r, TEXT_X - 2, -10.5)
            r.strike:SetEndPoint("TOPLEFT", r, TEXT_X + 3 + tw, -10.5)
        end
        local h = math.max(20, r.title:GetStringHeight() + 8)
        -- (the map up, and it's not on the floor shown: said small, under the title)
        local here, other = #e.spots == 0, nil
        for _, s in ipairs(e.spots) do
            if s[1] == shownFloor then here = true else other = other or s[1] end
        end
        if shownInst == inst and not here and other then
            r.away:SetText("on another floor: click")
            r.away:ClearAllPoints()
            r.away:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -2)
            r.away:Show()
            h = h + 12
        else
            r.away:Hide()
        end
        -- (details under it: the leading danger's when opened by a click, and "now" by itself)
        r.inline = (e == lead and details) or live or false
        -- (his own line first, in his hand. Where a tip said it over again ("repeats gameplay note", the user
        -- 2026-11-14) the TIP is what changes: it adds to his line. mockups\dangers-repeats.md)
        if HAND_ON_GLASS and r.inline and e.w and e.w ~= "" then
            HandFont(r.w)
            r.w:SetText(e.w)
            r.w:ClearAllPoints()
            r.w:SetPoint("TOPLEFT", r, "TOPLEFT", TEXT_X, -h)
            r.w:Show()
            h = h + r.w:GetStringHeight() + 5
        else
            r.w:Hide()
        end
        if r.inline then
            r.tip:SetText((e.tip and e.tip ~= "") and e.tip or (ns.BOOK_AUTHOR and "(nothing written yet: right-click)" or ""))
            r.tip:ClearAllPoints()
            r.tip:SetPoint("TOPLEFT", r, "TOPLEFT", TEXT_X, -h)
            r.tip:Show()
            h = h + r.tip:GetStringHeight() + 8
        else
            r.tip:Hide()
        end
        if first then
            r.fadeT, r.moreT = nil, nil
            r:SetAlpha(1)
            r.w:SetAlpha(1)
            r.tip:SetAlpha(1)
        elseif fresh then
            r.fadeT, r.moreT = 0, nil
            r:SetAlpha(0)
            r.w:SetAlpha(1)
            r.tip:SetAlpha(1)
        elseif r.inline and not wasInline then
            r.moreT = 0
            r.w:SetAlpha(0)
            r.tip:SetAlpha(0)
        end
        if r.fadeT or r.moreT then moving = true end
        r:SetSize(CARD_W, h)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", card, "TOPLEFT", 0, y)
        r:Show()
        y = y - h - 1
    end
    for i = #order + 1, #rows do
        local r = rows[i]
        r.key, r.fadeT, r.moreT, r.inline = nil, nil, nil, nil
        r:Hide()
    end
    local h = -y + 6
    local from = not first and card.GetHeight and card:GetHeight() or nil
    if not from or math.abs(from - h) < 0.5 then
        anim.hT = nil
        card:SetHeight(h)
    elseif not (anim.hT and anim.hTo == h) then
        anim.hFrom, anim.hTo, anim.hT = from, h, 0
    end
    if moving or anim.hT then card:SetScript("OnUpdate", Animate) end
end

-- where the note is: where it was dragged to; else beside the dungeon map, on the side with room, or ON the
-- map under its corner buttons when it fills the screen (the user, 2026-11-11: with the big map up the note sat
-- behind it and seemed gone); else (the map shut, never moved) where it last was, or the screen's right side.
-- With a dungeon map up it is in that map's layer, over it, wherever it lies.
local lastAt
-- (a place is kept in the note's own units: a new size keeps it where it is on the screen)
SetNoteScale = function(v)
    local c = Cfg()
    local old = c.dangersScale or 1
    if c.dangersAt then c.dangersAt = { c.dangersAt[1] * old / v, c.dangersAt[2] * old / v } end
    lastAt = nil
    c.dangersScale = v ~= 1 and v or nil
    Refresh()
end
local function PlaceCard(overlay, mapUp)
    if card.moving then return end
    local c = Cfg()
    card:SetScale(c.dangersScale or 1)
    -- Over the whole map whenever the map is on the screen, dungeon or not: above its header, buttons and
    -- hover label too (ns.ButtonLevel: the top of the map's own layers). It was 60 over the dungeon overlay,
    -- under those, and with a zone map up it had no level at all: the user, 2026-11-14, "Dangers panel opens
    -- behind map".
    local map = BattlefieldMapFrame
    -- (and over the map's own border frame, which the game keeps in a higher strata than the map: under it the
    -- note could not be laid over the map at all, it went behind and the pointer never reached it. The user,
    -- 2026-11-16: "I cant place what kills here over the map". As the Bosses slip does it, Dungeon.lua)
    local border = map and map.BorderFrame
    if map and map:IsShown() and type(border) == "table" and border.GetFrameStrata then
        card:SetFrameStrata(border:GetFrameStrata())
        card:SetFrameLevel(math.min(9960, border:GetFrameLevel() + 22))
    elseif map and map:IsShown() and (overlay or map.ScrollContainer) then
        card:SetFrameStrata((overlay or map.ScrollContainer):GetFrameStrata())
        local top = ns.ButtonLevel and ns.ButtonLevel(map) or ((overlay and overlay:GetFrameLevel() or 0) + 700)
        card:SetFrameLevel(math.min(9900, top + 20))
    else
        card:SetFrameStrata("MEDIUM")
    end
    card:ClearAllPoints()
    if c.dangersAt then
        card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", c.dangersAt[1], c.dangersAt[2])
    elseif mapUp and overlay then
        local sw = UIParent:GetWidth() * UIParent:GetEffectiveScale()
        local es = overlay:GetEffectiveScale()
        local right, left = (overlay:GetRight() or 0) * es, (overlay:GetLeft() or 0) * es
        local wide = (CARD_W + 22) * card:GetEffectiveScale()
        if right + wide < sw then
            card:SetPoint("TOPLEFT", overlay, "TOPRIGHT", 12, 0)
        elseif left - wide > 0 then
            card:SetPoint("TOPRIGHT", overlay, "TOPLEFT", -12, 0)
        else
            card:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -16, -46)
        end
        local l, t = card:GetLeft(), card:GetTop()
        if l and t then lastAt = { l, t } end
    elseif lastAt then
        card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", lastAt[1], lastAt[2])
    else
        card:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -60, -220)
    end
    -- (the hover slip goes on the side with more room)
    local mid = ((card:GetLeft() or 0) + CARD_W / 2) * (c.dangersScale or 1)
    card.side = mid > UIParent:GetWidth() / 2 and "left" or "right"
end

-- the tab beside the map's Bosses list: a small piece of the list's own glass with its gold rule, his "!" in red
-- (before 2026-11-14 a torn scrap of pale paper). Click: the note, or put it away. Right-click: a small menu.
-- It never turns the dangers off (the user: "rightclicking it does NOT remove it").
local BANG, BANG_LIT = G_RED, { 1, 0.58, 0.45 }
local function TabMenu()
    if not ns.QuillMenu then return end
    local c = Cfg()
    local open = c.dangersOpen ~= false
    local items = { { open and "Put the note away" or "Show the note", function()
        c.dangersOpen = not open
        Refresh()
    end } }
    items[#items + 1] = { c.dangersFolded and "Show all" or "Show less", function()
        c.dangersFolded = not c.dangersFolded or nil
        Refresh()
    end }
    if picked then
        items[#items + 1] = { "Follow the run", function()
            picked, pickedPast, details = nil, nil, nil
            Refresh()
        end }
    end
    if c.dangersAt then
        items[#items + 1] = { "Note back beside the map", function()
            c.dangersAt = nil
            Refresh()
        end }
    end
    ns.QuillMenu(items)
end
local function Tab(overlay)
    if tab then return tab end
    tab = CreateFrame("Button", nil, overlay)
    tab:SetSize(24, 24)   -- (as high as the Bosses count beside it; it takes the count's scale: Update)
    tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Glass(tab, 0)
    ns.dangersTab = tab   -- (Dungeon.lua: the Bosses slip under the count runs as far as this)
    -- (a faint line where it joins the Bosses count: one bar, two things to press)
    local seam = tab:CreateTexture(nil, "ARTWORK")
    seam:SetColorTexture(G_FAINT[1], G_FAINT[2], G_FAINT[3], 0.45)
    seam:SetPoint("TOPLEFT", 0, -5)
    seam:SetPoint("BOTTOMLEFT", 0, 4)
    seam:SetWidth(1)
    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(G_GOLD[1], G_GOLD[2], G_GOLD[3], 0.14)
    tab.mark = tab:CreateFontString(nil, "OVERLAY")
    Font(tab.mark, HAND, 17)
    tab.mark:SetTextColor(BANG[1], BANG[2], BANG[3])
    tab.mark:SetPoint("CENTER", 0, -1)
    tab.mark:SetText("!")
    tab:SetScript("OnClick", function(_, button)
        local c = Cfg()
        GameTooltip:Hide()
        if button == "RightButton" then
            TabMenu()
            return
        end
        c.dangersOpen = c.dangersOpen == false   -- (open at first: nil)
        Refresh()
    end)
    tab:SetScript("OnEnter", function(self)
        self.mark:SetTextColor(BANG_LIT[1], BANG_LIT[2], BANG_LIT[3])
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("What kills here")
        GameTooltip:AddLine("The dungeon's real dangers, the worst first, and where they are on the map.", 1, 1, 1, true)
        if ns.Hints then ns.Hints({ { "Click", Cfg().dangersOpen ~= false and "put the note away" or "the note" }, { "Right-click", "menu" } }) end
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function(self)
        self.mark:SetTextColor(BANG[1], BANG[2], BANG[3])
        GameTooltip:Hide()
    end)
    return tab
end

-- Drawing it all, when something changed --------------------------------------------------------------

local sig
local function HideAll()
    if layer then layer:Hide() end
    if card then card:Hide() end
    if tab then tab:Hide() end
    HideTag()
    sig, shownInst, shownFloor = nil, nil, nil
end

-- the dungeon you are standing in, if it has a list
local function Here()
    if not (IsInInstance and IsInInstance()) then return end
    local id = select(8, GetInstanceInfo())
    return id and List(id) and id or nil
end

local function Update()
    local c = Cfg()
    if not c then return end
    if not On() then
        if sig ~= false then HideAll() sig = false end
        return
    end
    local canvas, key = nil, nil
    if ns.DungeonInkSurface then canvas, key = ns.DungeonInkSurface() end
    local inst, floor = (key or ""):match("^d(%d+):(%d+)$")
    inst, floor = tonumber(inst), tonumber(floor)
    local overlay = ns.dungeonOverlay
    local mapList = inst and canvas and overlay and overlay:IsVisible() and List(inst) or nil
    if mapList then c.dangersInst = inst end
    -- (the note: the map's dungeon while a dungeon map is up; else the one you're in; else the last one shown)
    local open = c.dangersOpen ~= false
    local about = mapList and inst or (open and (Here() or c.dangersInst)) or nil
    local list = about and List(about) or nil
    if not mapList and not (open and list) then
        if sig ~= false then HideAll() sig = false end
        return
    end
    shownInst, shownFloor = mapList and inst or nil, mapList and floor or nil
    noteInst = about
    local live = ""
    if list then for _, e in ipairs(list) do if Live(about, e) then live = live .. e.n .. "," end end end
    if list then for _, e in ipairs(list) do if Past(about, e) then live = live .. "p" .. e.n .. "," elseif Next(about, e) then live = live .. "n" .. e.n .. "," end end end
    local slip = ns.dungeonBossList
    -- (the pointer on the note: looked at here, so the note folds again a moment after it leaves)
    if not (card and card.moving) then
        over = card and card:IsShown() and card.IsMouseOver and card:IsMouseOver() and true or false
    end
    local s = table.concat({ tostring(key), tostring(about), tostring(open), tostring(c.dangersFolded), tostring(hovered and hovered.n), tostring(picked), live,
                             tostring(over), tostring(details), tostring(c.dangersScale), tostring(c.dangersPlainHand),
                             tostring(canvas), mapList and string.format("%.0f", overlay:GetRight() or 0) or "-", tostring(list),
                             tostring(slip and slip:IsShown()), tostring(c.dangersAt and c.dangersAt[1]), tostring(mapList and InHand()), tostring(mapList and ns.BOOK_AUTHOR and IsControlKeyDown()) }, ":")
    if s == sig then return end
    sig = s
    if mapList then
        DrawMarks(canvas, inst, floor, mapList)
        local t = Tab(overlay)
        -- (in the Bosses count's own layer when it is up: that one is over the map's border frame, where the
        -- pointer reaches it; Dungeon.lua)
        if slip and slip:IsShown() and slip.GetFrameStrata then
            t:SetFrameStrata(slip:GetFrameStrata())
            t:SetFrameLevel(slip:GetFrameLevel())
        else
            t:SetFrameLevel(overlay:GetFrameLevel() + 12)
        end
        t:ClearAllPoints()
        if slip and slip:IsShown() then
            t:SetScale(slip.GetScale and slip:GetScale() or 1)
            t:SetPoint("TOPLEFT", slip, "TOPRIGHT", 0, 0)   -- (joined to the count: one bar)
        else
            t:SetPoint("TOPLEFT", overlay, "TOPLEFT", 6, -18)
        end
        t.mark:SetAlpha(open and 0.6 or 1)   -- (the note's out: the tab has less to say)
        t:Show()
    else
        if layer then layer:Hide() end
        if tab then tab:Hide() end
    end
    if open and list then
        if not card then CreateCard() end
        local name = ns.DungeonEntranceInfo and ns.DungeonEntranceInfo(about)
        FillCard(about, list, name and name[1])
        PlaceCard(overlay, mapList ~= nil)
        card:Show()
    elseif card then
        card:Hide()
    end
end
Refresh = function()
    sig = nil
    local ok, err = pcall(Update)
    if not ok and ns.Log then ns.Log("Dangers:", tostring(err)) end
end

function ns.SetupDangers()
    -- (its own frame, not the map's: the note stays up, and "now" starts at the kill, with the map shut)
    local t = 0
    local ticker = ns.TimedFrame and ns.TimedFrame("Dangers tick", UIParent) or CreateFrame("Frame", nil, UIParent)
    ticker:SetScript("OnUpdate", function(_, e)
        t = t + e
        if t < (ns.Tick and ns.Tick(0.25) or 0.25) then return end
        t = 0
        if not ns.db then return end
        pcall(TrackKills)
        local ok, err = pcall(Update)
        if not ok and ns.Log then ns.Log("Dangers:", tostring(err)) end
    end)
    -- (for /bfi check)
    function ns.DangersInfo()
        local n = 0
        for _, b in ipairs(buttons) do if b:IsShown() then n = n + 1 end end
        return string.format("%d danger marks up, note %s", n, card and card:IsShown() and "open" or "shut")
    end
end

-- the settings' switch (Caves & dungeons): all of it on or off, said to nobody
function ns.DangersOn() return On() end
function ns.DangersSet(on)
    local c = Cfg()
    if not c then return end
    c.dangers = on and true or false
    if c.dangers then c.dangersOpen = true end
    Refresh()
end

-- /waymark dangers: the same switch from chat (the tab itself never turns it off)
function ns.DangersToggle()
    local c = Cfg()
    if not c then return end
    c.dangers = c.dangers == false and true or false
    if c.dangers then c.dangersOpen = true end
    print("Waymark: what kills here " .. (c.dangers and "on" or "off"))
    Refresh()
end
