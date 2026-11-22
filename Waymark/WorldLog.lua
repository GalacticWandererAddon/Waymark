local _, ns = ...

-- The world map of our own, level 3 of the user's plan (2026-11-19: "Build level 3. Our world map."): what the
-- log KNOWS. No frames here; Lab\WorldPanel.lua draws it, Lab\BeforeYouGo.lua speaks at the flight master.
-- The full notes for whoever polishes this: mockups\world-map-level3-notes.md. The ideas: mockups\quest-log-ideas.html,
-- reports\2026-11-18 The quest log, idea hunt.md, and the user's picks quoted in the notes.
--
-- What this file answers (everything cached until the log changes, W.version):
--   W.Held()            the quests in your log: { id, name, level, complete, map, progress, days, greyNext, grey }
--   W.Groups(map)       a zone's held quests as the log shows them: ready to hand in here, then BY GROUND (the
--                       tracker's own idea: under the place each one happens, nearest first), then the rest
--   W.Beads(id)         a chain as beads: { index, n, steps = { { done, now, far, dungeon, group, name } } }
--   W.Loose()           loose ends: chains begun and left, quests set aside, offers read and not taken
--   W.Tally(map)        done and all of a zone's quests that are yours to do (the completionist's x of y)
--   W.DoneHere(map)     what you did there; W.People(map) who you worked for there
--   W.Search(text, book) your log, what you were told, and (only when asked) the whole book of quests
--   W.WhyNot(id)        what stands between you and a quest you do not hold, in sentences
--   W.Counts()          per zone: held, ready, loose (for the little world)
-- What it writes down as you play (WaymarkCharDB.worldLog, per character; small, on events):
--   taken[id] = time    when a quest was taken (the dust on old quests)
--   aside[id] = { t, l }   a quest dropped from the log without a hand-in (abandoned)
--   offered[id] = { t }    a quest whose offer you read and did not take
-- Nothing here calls the game's quest log frames. Reading only, through QuestData.lua's own way in
-- (ns.QuestRouteParts: Log, Info, Done, ForMe, Available) and its ns.Quest* answers.

local W = { version = 1 }
ns.WorldLog = W

-- (on: the world map is the big map you use. On by default, the user, 2026-11-22: "Worldmap becomes the default
-- instead of "bigmap" from now on". MapControls.lua ns.MapKind reads a save without it as on too)
local DEFAULTS = { on = true, sidebar = true, aimsOpen = false, logKind = "new", aloneL = false, aloneLMap = false, width = 300, scale = 100, sort = "ground",
                   loose = true, before = true, mode = "held", chainNames = false,
                   fold = false, frame = "engraver", title = "morpheus", top = "glass", list = "places", zones = "painted" }
-- The world map's settings: ns.db.worldLog (out of the Lab for 1.3.2, BattlefieldInfo.lua DEFAULTS). Carried over
-- once from the Lab's store (WaymarkDB.lab.worldLog), where they lived till then; before the settings are read, the
-- defaults. ns.WorldCfg: the same, for other files and the Lab's test bench
local readyCfg
function W.Cfg()
    local c = ns.db and ns.db.worldLog
    if not c then return DEFAULTS end
    if not readyCfg then
        readyCfg = true
        local old = WaymarkDB and WaymarkDB.lab and WaymarkDB.lab.worldLog
        if old and not old.moved then
            for k, v in pairs(old) do c[k] = v end
            old.moved = true
        end
        for k, v in pairs(DEFAULTS) do if c[k] == nil then c[k] = v end end
    end
    return c
end
ns.WorldCfg = W.Cfg

local function Store()
    WaymarkCharDB = WaymarkCharDB or {}
    local s = WaymarkCharDB.worldLog
    if not s then
        s = {}
        WaymarkCharDB.worldLog = s
    end
    s.taken, s.aside, s.offered, s.done = s.taken or {}, s.aside or {}, s.offered or {}, s.done or {}
    return s
end
W.Store = Store

local function P() return ns.QuestRouteParts end
-- A quest you have handed in: the game's own flag, else what this character saw handed in (s.done, from
-- QUEST_TURNED_IN), else As told's record of it. The user, 2026-11-22, of Teldrassil's "Turned in here" at 0 of 44
-- with quests handed in: "Turned in ones dont save"; As told had them marked done, the game's flag said no
function W.IsDone(id)
    local parts = P()
    if parts and parts.Done and parts.Done(id) then return true end
    local s = WaymarkCharDB and WaymarkCharDB.worldLog
    if s and s.done and s.done[id] then return true end
    local told = ns.ToldQuest and ns.ToldQuest(id)
    return told and told.done and true or false
end
local function Ready() return P() and ns.WorldQuestData and ns.QuestChain and true or false end
W.Ready = Ready

local T = Enum and Enum.UIMapType or {}
local cache = {}                       -- everything below, thrown away when the log changes
local function Cached(key, fn)
    if cache.v ~= W.version then cache = { v = W.version } end
    local c = cache[key]
    if c == nil then
        c = fn()
        cache[key] = c == nil and false or c
    end
    return c or nil
end

-- Zones ---------------------------------------------------------------------------------

local areaMap
local function AreaMap()
    if areaMap then return areaMap end
    areaMap = {}
    for _, z in ipairs(ns.WorldQuestData and ns.WorldQuestData.zones or {}) do areaMap[z[2]] = z[1] end
    return areaMap
end

-- a map lifted to its zone (a cave or a city's floor: the zone it lies in), nil for a continent
local function ZoneMap(map)
    for _ = 1, 4 do
        local info = map and C_Map.GetMapInfo(map)
        if not info then return nil end
        if info.mapType == T.Zone then return map end
        if info.mapType and T.Zone and info.mapType < T.Zone then return nil end
        map = info.parentMapID
    end
end
W.ZoneMap = ZoneMap

function W.Continent(map)
    for _ = 1, 5 do
        local info = map and C_Map.GetMapInfo(map)
        if not info then return nil end
        if info.mapType == T.Continent then return map end
        map = info.parentMapID
    end
end

-- where a quest belongs by the data alone (its sort): steady, for the tallies
local function Row(id)
    local q = ns.WorldQuestData and ns.WorldQuestData.quests
    return type(q) == "table" and q[id] or nil
end
function W.HomeZone(id)
    local row = Row(id)
    local z = row and row[6] or (P().Info(id).zoneOrSort)
    return z and z > 0 and AreaMap()[z] or nil
end
function W.TypeOf(id)
    local row = Row(id)
    return row and row[22] or nil
end

-- where a quest is to be done now (its open objectives, else who takes it): moves as you go
function W.ZoneOf(id)
    return Cached("zone" .. id, function()
        local ok, map = pcall(ns.QuestFindMap, id)
        map = ok and map and (ZoneMap(map) or map) or nil
        return map or W.HomeZone(id)
    end)
end

local byZone
local function Index()
    if byZone then return byZone end
    byZone = {}
    local quests = ns.WorldQuestData and ns.WorldQuestData.quests
    if type(quests) ~= "table" then return byZone end
    local am = AreaMap()
    for id, row in pairs(quests) do
        local z = type(row) == "table" and row[6]
        -- (a quest filed under a sub-area, Shadowglen in Teldrassil, lifted to its zone: the zone lists counted only
        -- the zone's own area, so Teldrassil's "Turned in here" said 0 of 44 with Shadowglen's quests handed in. The
        -- user, 2026-11-22: "Turned in ones dont save", "still no turnins")
        local m = z and z > 0 and (am[z] or (ns.MapOfArea and ns.MapOfArea(z)))
        if m and not am[z] then m = ZoneMap(m) or m end
        if m then
            byZone[m] = byZone[m] or {}
            byZone[m][#byZone[m] + 1] = id
        end
    end
    return byZone
end
W.Index = Index

-- The log -------------------------------------------------------------------------------

local function Title(id)
    local t = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    if t and t ~= "" then return t end
    return ns.QuestNameOf and ns.QuestNameOf(id) or ("Quest " .. id)
end
W.Title = Title

-- "5/8", "1 of 3", or nil: how far along a quest is
local function Progress(id)
    local ok, objs = pcall(function() return C_QuestLog.GetQuestObjectives(id) end)
    if not (ok and objs and #objs > 0) then return nil, 0, 0 end
    local done, short, most = 0, 0, 0
    for _, o in ipairs(objs) do
        if o.finished then done = done + 1 end
        if o.numRequired and o.numRequired > 0 then
            short = short + math.max(0, o.numRequired - (o.numFulfilled or 0))
            most = most + o.numRequired
        end
    end
    if #objs == 1 and (objs[1].numRequired or 0) > 1 then
        return (objs[1].numFulfilled or 0) .. "/" .. objs[1].numRequired, short, most
    end
    if #objs > 1 then return done .. " of " .. #objs, short, most end
    return nil, short, most
end
W.Progress = Progress

-- days a quest has been carried (nil: not known), from our own note or As told's
function W.Days(id)
    local t = Store().taken[id]
    if not t and ns.ToldQuest then
        local q = ns.ToldQuest(id)
        t = q and q.t
    end
    return t and math.max(0, (time() - t) / 86400) or nil
end

function W.Held()
    return Cached("held", function()
        local out = {}
        local me = UnitLevel("player")
        local green = GetQuestGreenRange and GetQuestGreenRange() or 8
        for id, e in pairs(P().Log()) do
            local level = ns.QuestLevelOf(id)
            local progress, short, most = Progress(id)
            out[#out + 1] = { id = id, name = Title(id), level = level, complete = e.complete and true or false,
                              map = W.ZoneOf(id), progress = progress, short = short, most = most, days = W.Days(id),
                              grey = me - level > green, greyNext = me - level == green }
        end
        table.sort(out, function(a, b) return a.name < b.name end)
        return out
    end)
end

function W.IsHeld(id) return P().Log()[id] ~= nil end

-- A zone's quests as the log lists them. The tracker's own rule (Tracker.lua): under the place each quest
-- happens, the nearest place first. Here: the place of a quest's first open spot on this map.
function W.Groups(map)
    return Cached("groups" .. tostring(map) .. W.Cfg().sort, function()
        local out = { ready = {}, groups = {}, count = 0 }
        local spot = {}
        local ok, ground = pcall(ns.QuestGround, map)
        for _, q in ipairs(ok and ground or {}) do
            local pt = q.parts[1] and q.parts[1].points[1]
            if pt then spot[q.id] = pt end
        end
        local px, py
        local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
        if pos then px, py = pos:GetXY() end
        local by = {}
        for _, h in ipairs(W.Held()) do
            if h.map == map then
                out.count = out.count + 1
                if h.complete then
                    local okE, ends = pcall(ns.QuestEnds, h.id, map)
                    h.to = okE and ends and ends.to and ends.to.name or nil
                    h.toHere = okE and ends and ends.to and ends.to.map == map or false
                    out.ready[#out.ready + 1] = h
                else
                    local pt = spot[h.id]
                    local area = pt and ns.AreaNameAt and ns.AreaNameAt(map, pt[1], pt[2]) or nil
                    local key = area or "Somewhere here"
                    local g = by[key]
                    if not g then
                        -- (x, y: the first spot of the group's first quest, where the list draws the place: WorldPanel)
                        g = { name = key, quests = {}, dist = 9, x = pt and pt[1], y = pt and pt[2] }
                        by[key] = g
                        out.groups[#out.groups + 1] = g
                    end
                    h.dist = pt and px and math.sqrt((pt[1] - px) ^ 2 + (pt[2] - py) ^ 2) or 9
                    if h.dist < g.dist then g.dist = h.dist end
                    g.quests[#g.quests + 1] = h
                end
            end
        end
        local sort = W.Cfg().sort
        local function Order(a, b)
            if sort == "oldest" then return (a.days or -1) > (b.days or -1) end
            if sort == "level" then return a.level < b.level end
            if a.dist ~= b.dist then return a.dist < b.dist end
            return a.name < b.name
        end
        for _, g in ipairs(out.groups) do table.sort(g.quests, Order) end
        table.sort(out.groups, function(a, b)
            if (a.name == "Somewhere here") ~= (b.name == "Somewhere here") then return b.name == "Somewhere here" end
            if a.dist ~= b.dist then return a.dist < b.dist end
            return a.name < b.name
        end)
        return out
    end)
end

-- Chains --------------------------------------------------------------------------------

-- A chain as beads. What lies ahead shows only its shape: far (another zone than the step you are on), a
-- dungeon, wants a group. Names are there too, for the page's "the whole chain" (the user likes both).
function W.Beads(id)
    return Cached("beads" .. id, function()
        local ok, c = pcall(ns.QuestChain, id)
        if not (ok and c and c.steps and #c.steps > 1) then return nil end
        local here = W.HomeZone(id)
        local out = { index = c.index, n = #c.steps, steps = {}, far = 0, dungeon = false, group = false }
        for i, s in ipairs(c.steps) do
            local kind = W.TypeOf(s.id)
            local zone = W.HomeZone(s.id)
            local b = { id = s.id, name = s.name, done = s.done, now = i == c.index, inLog = s.inLog,
                        far = i > c.index and here and zone and zone ~= here or false,
                        dungeon = kind == 81 or kind == 62, group = kind == 1 }
            if i > c.index then
                if b.far then out.far = out.far + 1 end
                out.dungeon = out.dungeon or b.dungeon
                out.group = out.group or b.group
            end
            out.steps[i] = b
        end
        return out
    end)
end

-- "Five more steps. Two in other zones. The last is a group quest." (plain, 2026-11-21: "Quests dont want anything")
local NUM = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten" }
function W.BeadsLine(b)
    if not b then return nil end
    local left = b.n - b.index
    if left <= 0 then return "The last step." end
    local s = (NUM[left] or left) .. (left == 1 and " more step." or " more steps.")
    if b.far > 0 then
        if b.far == left then
            s = s .. (left == 1 and " In another zone." or " All in other zones.")
        else
            s = s .. " " .. (NUM[b.far] or b.far) .. (b.far == 1 and " in another zone." or " in other zones.")
        end
    end
    local last = b.steps[b.n]
    if last and last.dungeon then s = s .. " The last is a dungeon quest."
    elseif b.dungeon then s = s .. " One is a dungeon quest." end
    if last and last.group then s = s .. " The last is a group quest."
    elseif b.group then s = s .. " One is a group quest." end
    return s
end

-- Loose ends ----------------------------------------------------------------------------

local function CompletedIDs()
    if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
        local ok, list = pcall(C_QuestLog.GetAllCompletedQuestIDs)
        if ok and list then return list end
    end
    local out = {}
    if GetQuestsCompleted then
        local ok, set = pcall(GetQuestsCompleted)
        for id in pairs(ok and set or {}) do out[#out + 1] = id end
    end
    return out
end

-- Where a quest begins or ends by the givers Waymark learned as you played (Learn.lua's WaymarkQuestDB): for the
-- quests our data has no ends for (Forever's new ones while QuestieDB is off). ending: who takes it in first.
-- { name, map, x, y } or nil
function W.LearnedEnd(id, ending)
    local db = WaymarkQuestDB and WaymarkQuestDB.givers
    if not (id and db) then return nil end
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local function From(field)
        local best, bestN
        for _, g in pairs(db) do
            if type(g) == "table" and g[field] and g[field][id] then
                for m, s in pairs(g.spots or {}) do
                    -- (a zone's own map, not the continent's; where you are first, then where you stood most)
                    local info = C_Map.GetMapInfo(m)
                    if s[1] and info and not (Enum and Enum.UIMapType and info.mapType <= Enum.UIMapType.Continent) then
                        local n = (m == here and 1e6 or 0) + (s[3] or 1)
                        if not bestN or n > bestN then best, bestN = { name = g.name, map = m, x = s[1], y = s[2] }, n end
                    end
                end
            end
        end
        return best
    end
    if ending then return From("takes") or From("offers") end
    return From("offers") or From("takes")
end

-- The game's own marker for a held quest on a map: { map, x, y, spread } or nil
function W.GameMarker(id, map)
    if not (id and map and C_QuestLog and C_QuestLog.GetQuestsOnMap) then return nil end
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, map)
    for _, q in ipairs(ok and type(list) == "table" and list or {}) do
        if q.questID == id and q.x and q.y then return { map = map, x = q.x, y = q.y, spread = 0.04 } end
    end
    return nil
end

local function Giver(id)
    local ok, ends = pcall(ns.QuestEnds, id)
    local from = ok and ends and ends.from
    if not (from and from.name) then from = W.LearnedEnd(id, false) end   -- (Forever's new quests, QuestieDB off)
    return from and from.name or nil, from and from.map and (ZoneMap(from.map) or from.map) or nil
end
W.Giver = Giver

-- Your own threads only, never every quest in a zone: a chain you began (its next step is not done and not in
-- your log), a quest you set aside, an offer you read and left. { id, kind, who, map, step, of, level, grey }
function W.Loose()
    return Cached("loose", function()
        local out, seen = {}, {}
        local parts = P()
        local me = UnitLevel("player")
        local green = GetQuestGreenRange and GetQuestGreenRange() or 8
        local function Add(id, kind, extra)
            if seen[id] or W.IsDone(id) or parts.Log()[id] or not parts.ForMe(id) then return end
            seen[id] = true
            local who, map = Giver(id)
            local level = ns.QuestLevelOf(id)
            local e = { id = id, kind = kind, who = who, map = map or W.HomeZone(id), level = level,
                        grey = me - level > green, tooHigh = (parts.Info(id).requiredLevel or 0) > me }
            if kind == "chain" then
                local b = W.Beads(id)
                if b then e.step, e.of = b.index, b.n end
            end
            for k, v in pairs(extra or {}) do e[k] = v end
            out[#out + 1] = e
        end
        for _, id in ipairs(CompletedIDs()) do
            local nxt = parts.Info(id).nextQuestInChain
            if nxt and nxt > 0 then Add(nxt, "chain", { after = id }) end
        end
        local s = Store()
        for id, a in pairs(s.aside) do Add(id, "aside", { at = a.l, t = a.t }) end
        for id, o in pairs(s.offered) do Add(id, "offered", { t = o.t }) end
        return out
    end)
end

function W.LooseOn(map)
    local out = {}
    for _, e in ipairs(W.Loose()) do
        if e.map == map then out[#out + 1] = e end
    end
    -- (a chain first, then what you set aside, then offers; what you can take now before what you cannot)
    local rank = { chain = 1, aside = 2, offered = 3 }
    table.sort(out, function(a, b)
        if a.tooHigh ~= b.tooHigh then return b.tooHigh end
        if rank[a.kind] ~= rank[b.kind] then return rank[a.kind] < rank[b.kind] end
        return a.level < b.level
    end)
    return out
end

-- one loose end said plainly
function W.LooseLine(e)
    local who = e.who or "someone"
    if e.kind == "chain" then
        if e.step and e.of then
            return ("%s has the next step (%d of %d)."):format(who, e.step, e.of)
        end
        return ("%s has the next step."):format(who)
    elseif e.kind == "aside" then
        return ("Abandoned: %s.%s"):format(W.Title(e.id), e.at and (" At level %d."):format(e.at) or "")
    end
    return ("%s has a quest you didn't take."):format(who)
end

-- Per zone, for the little world ------------------------------------------------------------

function W.Counts()
    return Cached("counts", function()
        local c = {}
        local function Z(m)
            c[m] = c[m] or { held = 0, ready = 0, loose = 0 }
            return c[m]
        end
        for _, h in ipairs(W.Held()) do
            if h.map then
                local z = Z(h.map)
                z.held = z.held + 1
                if h.complete then z.ready = z.ready + 1 end
            end
        end
        if W.Cfg().loose then
            for _, e in ipairs(W.Loose()) do
                if e.map and not e.tooHigh then Z(e.map).loose = Z(e.map).loose + 1 end
            end
        end
        return c
    end)
end

-- What happened here ----------------------------------------------------------------------

local EVENT = 1          -- (specialFlags bit 1: repeatable)
local tally = {}         -- [map] = { v, done, all, open }
function W.Tally(map)
    local t = tally[map]
    if t and t.v == W.version then return t end
    local parts = P()
    t = { v = W.version, done = 0, all = 0, open = 0, low = nil, high = nil }
    for _, id in ipairs(Index()[map] or {}) do
        local info = parts.Info(id)
        local flags = info.specialFlags or 0
        if parts.ForMe(id) and flags % 2 < EVENT then
            t.all = t.all + 1
            if W.IsDone(id) then
                t.done = t.done + 1
                local l = ns.QuestLevelOf(id)
                t.low = math.min(t.low or l, l)
                t.high = math.max(t.high or l, l)
            elseif not parts.Log()[id] and parts.Available(id) then
                t.open = t.open + 1
            end
        end
    end
    tally[map] = t
    return t
end
function W.Tallied(map)
    local t = tally[map]
    return t and t.v == W.version and t or nil
end

function W.DoneHere(map)
    return Cached("done" .. tostring(map), function()
        local out = {}
        local parts = P()
        for _, id in ipairs(Index()[map] or {}) do
            if parts.ForMe(id) and W.IsDone(id) then
                out[#out + 1] = { id = id, name = W.Title(id), level = ns.QuestLevelOf(id) }
            end
        end
        table.sort(out, function(a, b)
            if a.level ~= b.level then return a.level < b.level end
            return a.name < b.name
        end)
        return out
    end)
end

-- who you worked for in a zone: { name, done, held }, the most work first
function W.People(map)
    return Cached("people" .. tostring(map), function()
        local by, out = {}, {}
        local parts = P()
        local function Add(id, key)
            local who = Giver(id)
            if not who then return end
            local p = by[who]
            if not p then
                p = { name = who, done = 0, held = 0, open = 0, doneIds = {}, openIds = {} }
                by[who] = p
                out[#out + 1] = p
            end
            p[key] = p[key] + 1
            if key == "done" then p.doneIds[#p.doneIds + 1] = id elseif key == "open" then p.openIds[#p.openIds + 1] = id end
        end
        -- (open: one you can take now, as the tally's "more quests available": who still has work for you here)
        for _, id in ipairs(Index()[map] or {}) do
            if parts.ForMe(id) then
                if W.IsDone(id) then Add(id, "done")
                elseif parts.Log()[id] then Add(id, "held")
                elseif parts.Available and parts.Available(id) then Add(id, "open") end
            end
        end
        table.sort(out, function(a, b)
            if a.done + a.held ~= b.done + b.held then return a.done + a.held > b.done + b.held end
            return a.name < b.name
        end)
        return out
    end)
end

-- Search ----------------------------------------------------------------------------------

local function Has(s, needle) return type(s) == "string" and s:lower():find(needle, 1, true) ~= nil end

-- the sentence a word stands in, for a found line
local function Sentence(text, needle)
    local at = text:lower():find(needle, 1, true)
    if not at then return nil end
    local a = at
    while a > 1 and not text:sub(a - 1, a - 1):find("[%.%!%?\n]") do a = a - 1 end
    local b = text:find("[%.%!%?\n]", at) or #text
    local s = text:sub(a, b):gsub("^%s+", ""):gsub("%$[Bb]", " ")
    if #s > 160 then s = s:sub(1, 157) .. "..." end
    return s
end

-- log: your quests; told: what givers said to this character (As told's book: no spoilers, you were told it);
-- book: every quest that is yours to do and not in your log, ONLY when asked (book = true): it shows what
-- you have not met.
function W.Search(text, book)
    local needle = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local out = { log = {}, told = {}, book = {}, bookCount = 0 }
    if #needle < 2 then return out end
    for _, h in ipairs(W.Held()) do
        local d = ns.QuestDetails and ns.QuestDetails(h.id)
        if Has(h.name, needle) or Has(d and d.text, needle) then out.log[#out.log + 1] = h end
    end
    local told = WaymarkCharDB and WaymarkCharDB.told and WaymarkCharDB.told.quests
    for id, q in pairs(told or {}) do
        for _, words in ipairs({ q.text, q.last }) do
            if Has(words, needle) and #out.told < 12 then
                out.told[#out.told + 1] = { id = id, who = q.who, said = Sentence(words, needle), name = W.Title(id),
                                            done = q.done and true or false }
                break
            end
        end
    end
    local parts = P()
    local quests = ns.WorldQuestData and ns.WorldQuestData.quests
    if type(quests) == "table" then
        for id, row in pairs(quests) do
            if type(row) == "table" and Has(row[1], needle) and not parts.Log()[id] and parts.ForMe(id) then
                out.bookCount = out.bookCount + 1
                if book and #out.book < 30 then
                    out.book[#out.book + 1] = { id = id, name = row[1], level = row[2] or 0, done = W.IsDone(id),
                                                map = W.HomeZone(id) }
                end
            end
        end
    end
    table.sort(out.book, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.name < b.name
    end)
    return out
end

-- Why can I not get this quest --------------------------------------------------------------

-- sentences, for the page of a quest you do not hold
function W.WhyNot(id)
    local parts = P()
    local lines = {}
    if W.IsDone(id) then return { "You've done this quest." } end
    if parts.Log()[id] then return lines end
    local me = UnitLevel("player")
    local need = parts.Info(id).requiredLevel or 0
    if need > me then lines[#lines + 1] = ("Requires level %d. You are %d."):format(need, me) end
    local ok, needs = pcall(ns.QuestNeeds, id)
    local any, anyDone = {}, false
    for _, n in ipairs(ok and needs or {}) do
        if n.all then
            if not n.done then
                lines[#lines + 1] = ("Finish %s first."):format(n.name)
            end
        else
            any[#any + 1] = n.name
            anyDone = anyDone or n.done
        end
    end
    if #any > 0 and not anyDone then
        lines[#lines + 1] = (#any == 1 and "Comes after %s." or "Comes after one of these: %s."):format(table.concat(any, ", "))
    end
    local who, map = Giver(id)
    local where = map and C_Map.GetMapInfo(map)
    if #lines == 0 then
        if parts.Available(id) then
            lines[1] = who and ("Available from %s%s."):format(who, where and (", in " .. where.name) or "")
                or "Available."
        else
            lines[1] = "Not available. It may need a profession, reputation or a holiday."
        end
    elseif who then
        lines[#lines + 1] = ("Then %s has it%s."):format(who, where and (", in " .. where.name) or "")
    end
    return lines
end

-- Writing down, and when to think again -------------------------------------------------------

local turned, offer = {}, nil
local events = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_DETAIL", "QUEST_FINISHED",
                     "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
                     "QUEST_WATCH_LIST_CHANGED" }) do
    pcall(events.RegisterEvent, events, e)
end
local bumpAt = 0
local function Bump()
    -- (the log tells of itself many times a second while you fight: thought through again once a second at most)
    local now = GetTime()
    if now - bumpAt < 1 then
        if not events.later then
            events.later = true
            C_Timer.After(1.05, function()
                events.later = nil
                Bump()
            end)
        end
        return
    end
    bumpAt = now
    W.version = W.version + 1
    if ns.WorldPanelChanged then ns.WorldPanelChanged() end
end
W.Bump = Bump

events:SetScript("OnEvent", function(_, event, a, b)
    if not (ns.db and ns.db.worldLog) then return end
    -- (a quest tracked or untracked anywhere, the tracker too: the log's checks redrawn at once, not after the
    -- once-a-second wait. The user, 2026-11-22: "untracking a quest is slow to react/update")
    if event == "QUEST_WATCH_LIST_CHANGED" then
        W.trackedAt = nil
        if ns.WorldPanelChanged then ns.WorldPanelChanged() end
        return
    end
    local s = Store()
    if event == "QUEST_ACCEPTED" then
        local id = type(b) == "number" and b or a          -- (Era: index, id; Forever: id)
        if type(id) == "number" then
            s.taken[id] = s.taken[id] or time()
            s.aside[id], s.offered[id] = nil, nil
            if offer == id then offer = nil end
        end
    elseif event == "QUEST_TURNED_IN" then
        if type(a) == "number" then
            turned[a] = GetTime()
            s.taken[a], s.aside[a], s.offered[a] = nil, nil, nil
            s.done[a] = time()
        end
    elseif event == "QUEST_REMOVED" then
        local id = a
        if type(id) == "number" then
            -- (a hand-in removes it too, and tells of the hand-in a moment before or after: looked at a little later)
            C_Timer.After(1, function()
                if turned[id] and GetTime() - turned[id] < 5 then return end
                local parts = P()
                if not parts or W.IsDone(id) or parts.Log()[id] then return end
                Store().aside[id] = { t = time(), l = UnitLevel("player") }
                Store().taken[id] = nil
                Bump()
            end)
        end
    elseif event == "QUEST_DETAIL" then
        offer = GetQuestID and GetQuestID() or nil
    elseif event == "QUEST_FINISHED" then
        local id = offer
        offer = nil
        if type(id) == "number" and id > 0 then
            C_Timer.After(1, function()
                local parts = P()
                if not parts or W.IsDone(id) or parts.Log()[id] then return end
                Store().offered[id] = Store().offered[id] or { t = time() }
                Bump()
            end)
        end
    end
    Bump()
end)
