local _, ns = ...
local GetNumSkillLines = GetNumSkillLines or ns.GetNumSkillLines
local GetSkillLineInfo = GetSkillLineInfo or ns.GetSkillLineInfo
local GetItemInfo = GetItemInfo or ns.GetItemInfo
local GetSpellInfo = GetSpellInfo or ns.GetSpellInfo

-- Quests and townsfolk from QuestieDB: the database addon Questie is built on,
-- read through its public API (LibQuestieDB). Questie itself isn't needed.
-- Quests come from our own data by default (WorldQuests.lua dresses it as
-- QuestieDB's API; questie.source = "questiedb" reads QuestieDB's instead, "both"
-- ours with QuestieDB filling what ours lacks); townsfolk from the same source
-- (ours: sorted by the tool, OwnFolk; with "both", QuestieDB's for NPCs ours doesn't list).
-- The data only holds (who starts and ends which quest, where NPCs
-- and objects stand, what vendors sell); which quests are available to you,
-- which objectives are still to do and which NPCs count as which townsfolk is
-- decided here, from the game's own quest log and character info.
--
--   ns.QDB()                 LibQuestieDB, or nil (not installed, too old)
--   ns.QuestSource()         where quests come from: ours (ns.OwnQuestDB) or LibQuestieDB
--   ns.QuestGround(mapID, all) where your quests' monsters and things are (QuestGround.lua)
--   ns.QuestIcons(mapID)     quest givers, turn-ins and objective spots on a map
--   ns.QuestPoints(mapID)    the tracker's [questID] = { spots, turnin }
--   ns.QuestVersion()        changes whenever those may have changed
--   ns.TownsfolkIds(key)     NPC / object IDs for a townsfolk type, or nil while indexing
--   ns.EachSpawnOnMap(...)   spawn points as (uiMapID, x, y), 0-1
--
-- Icons: Questie's own round icons where Questie is installed (as before),
-- else the game's.

local CONTRACT = 4  -- (Enum.classKeys and Enum.npcFlags)

local lib, libChecked
function ns.QDB()
    if libChecked then return lib end
    local L = rawget(_G, "LibQuestieDB")
    if not L then return nil end  -- (not loaded yet, or not installed: ask again later)
    libChecked = true
    local ok, okContract, msg = pcall(L.RequireContract, CONTRACT)
    if ok and okContract then
        lib = L
    else
        ns.Log("QuestieDB is too old for Waymark:", tostring(msg or okContract))
    end
    return lib
end

local function LoadTable(v)
    if type(v) == "table" then return v end
    if type(v) ~= "string" then return nil end
    local f = loadstring(v)
    local ok, t = pcall(f or error)
    return ok and type(t) == "table" and t or nil
end

-- Ours with QuestieDB behind it, by the same API: each answer is ours, and QuestieDB's only where
-- ours has none, so Forever's new quests in either show and our rows are never replaced.
local function Mixed(own, real)
    local function Both(part)
        local a, b = own[part], real[part]
        return setmetatable({}, { __index = function(t, key)
            local f, g = a[key], b[key]
            local fn = f or g
            if f and g then
                fn = function(id, ...)
                    local v = f(id, ...)
                    if v ~= nil and not (type(v) == "table" and next(v) == nil) then return v end
                    local ok, w = pcall(g, id, ...)
                    if ok and w ~= nil then return w end
                    return v
                end
            end
            -- a swept quest (Data\ForeverSwept.lua) is only part of a row: what it lacks, races, earlier
            -- steps and givers, is QuestieDB's, or it read as open to anyone, any time
            if key == "GetAll" and f and g then
                fn = function(id, keys, ...)
                    local v = f(id, keys, ...)
                    if not (ns.ForeverSwept and ns.ForeverSwept[id]) then return v end
                    local ok, w = pcall(g, id, keys, ...)
                    if not (ok and w) then return v end
                    local out = {}
                    for i = 1, #keys do
                        local x = v and v[i]
                        if x == nil or (type(x) == "table" and next(x) == nil) then x = w[i] end
                        out[i] = x
                    end
                    return out
                end
            end
            t[key] = fn
            return fn
        end })
    end
    local ids
    local mixed = {
        contractVersion = "both", readMode = "ours, then QuestieDB", mixed = true,
        Enum = own.Enum, Wilds = own.Wilds, Folk = own.Folk,
        Quest = Both("Quest"), Npc = Both("Npc"), Object = Both("Object"), Item = Both("Item"),
        Support = {
            Get = function(name)
                if name ~= "QuestXP" then return own.Support.Get(name) end
                local db = {}
                local ok, s = pcall(real.Support.Get, name)
                for id, e in pairs(ok and type(s) == "table" and LoadTable(s.db) or {}) do db[id] = e end
                for id, e in pairs(own.Support.Get(name).db) do db[id] = e end
                return { db = db }
            end,
        },
    }
    function mixed.Quest.GetAllIds()
        if not ids then
            local seen = {}
            ids = {}
            for _, L in ipairs({ own, real }) do
                for _, id in ipairs(L.Quest.GetAllIds() or {}) do
                    if not seen[id] then
                        seen[id] = true
                        ids[#ids + 1] = id
                    end
                end
            end
            table.sort(ids)
        end
        return ids
    end
    function mixed.Quest.GetAll(id, keys)
        return own.Quest.GetAll(id, keys) or real.Quest.GetAll(id, keys)
    end
    return mixed
end

-- Where quests come from: our own data (questie.source "own", the default), QuestieDB
-- ("questiedb"), or ours filled from QuestieDB ("both"); whichever is there if the other isn't.
-- Picked once a session (the option says a /reload follows).
local src
function ns.QuestSource()
    if src or not ns.db then return src end
    local qdb, mine = ns.QDB(), ns.OwnQuestDB and ns.OwnQuestDB()
    local want = ns.db.questie.source
    if want == "both" and qdb and mine then
        src = Mixed(mine, qdb)
    elseif want == "questiedb" then
        src = qdb or mine
    else
        src = mine or qdb
    end
    return src
end
local Source = ns.QuestSource

-- "own", "QuestieDB" or "both" (nil: neither)
function ns.QuestSourceName()
    local s = Source()
    return s and (s.mixed and "both" or s == lib and "QuestieDB" or "own") or nil
end

local function Q() return (src or Source()).Quest end
local function N() return (src or Source()).Npc end
local function I() return (src or Source()).Item end
local function O() return (src or Source()).Object end

-- bit `bit` (a power of two) set in `mask`; masks can pass 32 bits, so no bit ops
local function HasBit(mask, bit)
    return mask and bit and mask ~= 0 and math.floor(mask / bit) % 2 == 1
end

-- Zones -----------------------------------------------------------------------

-- QuestieDB keys spawns by the game's area (zone) IDs; the map needs uiMapIDs
local areaToMap, parentArea, dungeonArea

-- (from QuestieDB and from the quest source, when that's ours: the same area IDs)
local function LoadZones()
    if areaToMap then return true end
    local real, s = ns.QDB(), Source()
    if not (real or s) then return false end
    areaToMap, parentArea, dungeonArea = {}, {}, {}
    for _, L in ipairs({ real or false, s ~= real and s or false }) do
        local ok, Z = false, nil
        if L then ok, Z = pcall(L.Support.Get, "ZoneDB") end
        local p = ok and Z and Z.private or {}
        for _, t in ipairs({ LoadTable(p.areaIdToUiMapId) or {}, LoadTable(p.areaIdToUiMapIdOverride) or {} }) do
            for k, v in pairs(t) do areaToMap[k] = v end
        end
        for _, t in ipairs({ LoadTable(p.subZoneToParentZone) or {}, LoadTable(p.subZoneToParentZoneOverride) or {} }) do
            for k, v in pairs(t) do parentArea[k] = v end
        end
        for areaID, d in pairs(type(p.dungeons) == "table" and p.dungeons or {}) do
            dungeonArea[areaID] = true
            for _, alt in ipairs(type(d) == "table" and d[2] or {}) do dungeonArea[alt] = true end
        end
    end
    return true
end

local function MapOfArea(areaID)
    local m = areaToMap[areaID]
    if not m and parentArea[areaID] then m = areaToMap[parentArea[areaID]] end
    if m and m > 0 then return m end
end

-- fn(uiMapID, x, y) for each spawn point, 0-1, outside dungeons. (A key "m<uiMapID>":
-- points learned as you play, Learn.lua, already on that map.)
function ns.EachSpawnOnMap(spawns, fn)
    if not (spawns and LoadZones()) then return end
    for areaID, points in pairs(spawns) do
        local learned = type(areaID) == "string" and tonumber(areaID:match("^m(%d+)$"))
        if learned then
            for _, pt in ipairs(points) do fn(learned, pt[1] / 100, pt[2] / 100) end
        elseif not dungeonArea[areaID] then
            local m = MapOfArea(areaID)
            if m then
                for _, pt in ipairs(points) do
                    if pt[1] and pt[2] and pt[1] >= 0 and pt[2] >= 0 then fn(m, pt[1] / 100, pt[2] / 100) end
                end
            end
        end
    end
end
local EachSpawn = ns.EachSpawnOnMap

-- A capital is its own map, inside its zone: an objective in Darnassus showed on the city's map only, so
-- from Teldrassil's it appeared as you walked in (the user). fn(x, y) for spawns on this map, or in the
-- capital on it, placed by the world. Objectives only: every city giver on the zone map would crowd it.
local CITY_IN = { [1457] = 1438, [1453] = 1429, [1455] = 1426, [1454] = 1411, [1456] = 1412, [1458] = 1420 }
local worldBox = {}
local function WorldBox(mapID)
    local b = worldBox[mapID]
    if b == nil then
        b = false
        if C_Map.GetWorldPosFromMapPos and CreateVector2D then
            local ok1, _, p = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
            local ok2, _, q = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
            if ok1 and ok2 and p and q and p.x ~= q.x and p.y ~= q.y then
                b = { x0 = p.x, y0 = p.y, dx = q.x - p.x, dy = q.y - p.y }
            end
        end
        worldBox[mapID] = b
    end
    return b
end
-- (and the other way: the data files some of a capital's spots under its zone. Eyes of the Sentinels had
-- one of four on Darnassus's own map)
local function EachOnMap(spawns, mapID, fn)
    EachSpawn(spawns, function(m, x, y)
        if m == mapID then
            fn(x, y)
        elseif CITY_IN[m] == mapID or CITY_IN[mapID] == m then
            local a, b = WorldBox(m), WorldBox(mapID)
            if a and b then
                -- (a map's x runs with the world's y)
                local tx, ty = (a.y0 + x * a.dy - b.y0) / b.dy, (a.x0 + y * a.dx - b.x0) / b.dx
                if tx >= 0 and tx <= 1 and ty >= 0 and ty <= 1 then fn(tx, ty) end
            end
        end
    end)
end
ns.EachObjectiveOnMap = EachOnMap

-- where you met a monster the data has no place for (Learn.lua, WaymarkQuestDB.mobs),
-- as spawns keyed "m<uiMapID>", 0-100 as the data's are
local function LearnedSpawns(id)
    local db = WaymarkQuestDB
    local m = db and db.mobs and db.mobs[id]
    if not (m and m.spots) then return nil end
    local out
    for mapID, list in pairs(m.spots) do
        for _, s in ipairs(list) do
            out = out or {}
            local k = "m" .. mapID
            out[k] = out[k] or {}
            out[k][#out[k] + 1] = { s[1] * 100, s[2] * 100 }
        end
    end
    return out
end

-- an NPC's spots: its spawns, or for one that only walks a path, its first point;
-- else where you (or a player whose learned string you took) met it
local function NpcSpawns(id)
    local s = N().spawns(id)
    if s and next(s) then return s end
    local wps = N().waypoints(id)
    if not wps then return LearnedSpawns(id) end
    local out = {}
    for areaID, paths in pairs(wps) do
        local first = paths[1] and paths[1][1]
        if first then out[areaID] = { first } end
    end
    return out
end

local function Friendly(friendly)
    if not friendly or friendly == "AH" then return true end
    local f = UnitFactionGroup("player")
    return (f == "Alliance" and friendly == "A") or (f == "Horde" and friendly == "H")
end

-- What changed ---------------------------------------------------------------

-- Bumped by anything that changes which quest pins show; the map redraws when
-- it changes (BattlefieldInfo.lua's ticker)
local version = 0
local function Bump() version = version + 1 end
ns.BumpQuests = Bump
function ns.QuestVersion() return version end

-- Quest log --------------------------------------------------------------------

local function NumEntries()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then return (C_QuestLog.GetNumQuestLogEntries()) end
    return GetNumQuestLogEntries and (GetNumQuestLogEntries()) or 0
end

-- ready to hand in: the game's complete flag, or a quest with no objectives at
-- all ("Lost Necklace", "Report to Goldshire"), which the game never flags
-- complete (Questie counts those as complete too). index: log index
function ns.QuestReady(id, index, complete, failed)
    if complete then return true end
    if failed or not index then return false end
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
        if ok and objs and #objs > 0 then return false end
    end
    if GetNumQuestLeaderBoards then return (GetNumQuestLeaderBoards(index) or 0) == 0 end
    return false
end

-- [questID] = { complete = bool, index = log index }, as of the current version
local logCache, logVersion = {}, -1
local function Log()
    if logVersion == version then return logCache end
    logVersion = version
    wipe(logCache)
    local under  -- (the log's header the quests below it are filed under: a zone, a cave...)
    for i = 1, NumEntries() do
        local id, header, complete, failed
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info and info.isHeader then under = info.title end
            if info and not info.isHeader and info.questID then
                id = info.questID
                complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) or false
                failed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(id) or false
            end
        elseif GetQuestLogTitle then
            local title, _, _, isHeader, _, done, _, qid = GetQuestLogTitle(i)
            header = isHeader
            if header then under = title end
            if not header and qid then id, complete, failed = qid, done == 1, done == -1 end
        end
        if id and id > 0 then logCache[id] = { complete = ns.QuestReady(id, i, complete, failed), index = i, header = under } end
    end
    return logCache
end
ns.QuestLogState = Log

-- the quests the log files under a header of this name (a cave's: Fargodeep Mine), as a set;
-- nil when there are none (Cave.lua, BattlefieldInfo.lua: a cave's objective spots)
function ns.QuestsUnder(name)
    if not name then return end
    local set
    for id, q in pairs(Log()) do
        if q.header == name then
            set = set or {}
            set[id] = true
        end
    end
    return set
end

-- (turned in this session: the game's completed flag comes a moment after QUEST_TURNED_IN, and the
-- refresh on that event saw the quest neither in the log nor done, so its "!" came back till a /reload:
-- the Sprouted Fronds, the user 2026-11-08)
local turnedIn = {}
local function Done(id)
    if turnedIn[id] then return true end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(id) end
    return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(id) or false
end

-- the game's objectives of a quest in the log: { { text, finished }, ... }
local function GameObjectives(id)
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
        if ok and objs and #objs > 0 then return objs end
    end
    local e = Log()[id]
    local out = {}
    if e and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        for j = 1, GetNumQuestLeaderBoards(e.index) or 0 do
            local text, _, finished = GetQuestLogLeaderBoard(j, e.index)
            out[#out + 1] = { text = text, finished = finished }
        end
    end
    return out
end
ns.QuestGameObjectives = GameObjectives   -- (Pin.lua: a quest's own words for a "Credit" objective)

-- Settings of our own (were Questie's) ------------------------------------------

local function QCfg() return ns.db.questie end

-- grey (low-level) quest givers; the first time, follows Questie's own setting
function ns.GetTrivialQuests()
    local c = QCfg()
    if c.trivial == nil then
        local p = Questie and Questie.db and Questie.db.profile
        c.trivial = p and p.lowLevelStyle == (Questie.LOWLEVEL_ALL or 2) or false
    end
    return c.trivial
end

function ns.SetTrivialQuests(on)
    QCfg().trivial = on and true or false
    Bump()
    if ns.RedrawLearned then ns.RedrawLearned() end   -- (learned givers follow this box too)
    if ns.RedrawQuestie then ns.RedrawQuestie() end
    if ns.RefreshControls then ns.RefreshControls() end  -- main window and quick panel both show it
end

-- quests hidden with Shift-click (questie.hidden[questID] = true)
function ns.HideQuests(ids)
    for _, id in ipairs(ids) do QCfg().hidden[id] = true end
    Bump()
    if ns.RedrawQuestie then ns.RedrawQuestie() end
end

function ns.HiddenQuestCount()
    local n = 0
    for _ in pairs(QCfg().hidden) do n = n + 1 end
    return n
end

function ns.UnhideQuests()
    wipe(QCfg().hidden)
    Bump()
    if ns.RedrawQuestie then ns.RedrawQuestie() end
end

-- Availability -------------------------------------------------------------------

local AVAIL_KEYS = {
    "name", "requiredLevel", "questLevel", "requiredRaces", "requiredClasses", "preQuestGroup",
    "preQuestSingle", "exclusiveTo", "zoneOrSort", "requiredSkill", "requiredMinRep", "requiredMaxRep",
    "nextQuestInChain", "specialFlags", "parentQuest", "breadcrumbForQuestId", "requiredSpell",
    "requiredMaxLevel", "availableUntilCompleted", "availableStartingWith", "disabledByQuest",
}

-- [questID] = the fields above by name (they don't change)
local info = {}
local function Info(id)
    local q = info[id]
    if q then return q end
    q = {}
    local ok, v = pcall(Q().GetAll, id, AVAIL_KEYS)
    if ok and v then
        for i, key in ipairs(AVAIL_KEYS) do q[key] = v[i] end
    end
    info[id] = q
    return q
end

-- holiday and other event quests: the world event decides, and that isn't
-- known here, so they're left out (QuestSort IDs, negative zoneOrSort)
local EVENT_SORTS = {
    [-22] = true, [-284] = true, [-364] = true, [-366] = true, [-368] = true, [-369] = true, [-370] = true,
    [-374] = true, [-375] = true, [-376] = true, [-1002] = true, [-1003] = true, [-1005] = true,
}

-- profession skill IDs by the skill line's (English) name
local SKILL_IDS = {
    ["First Aid"] = 129, Blacksmithing = 164, Leatherworking = 165, Alchemy = 171, Herbalism = 182,
    Cooking = 185, Mining = 186, Tailoring = 197, Engineering = 202, Enchanting = 333, Fishing = 356,
    Skinning = 393, Lockpicking = 633, Riding = 762, Jewelcrafting = 755, Inscription = 773,
}
ns.SKILL_IDS = SKILL_IDS

-- [skill ID] = rank, as of the current version (English skill names: elsewhere
-- every skill counts as known, so no quest is hidden by mistake)
local skills, skillsVersion, skillsKnown = {}, -1, false
local function Skills()
    if skillsVersion == version then return skills, skillsKnown end
    skillsVersion = version
    wipe(skills)
    local locale = GetLocale and GetLocale() or "enUS"
    skillsKnown = locale == "enUS" or locale == "enGB"
    for i = 1, (GetNumSkillLines and GetNumSkillLines() or 0) do
        local name, header, _, rank = GetSkillLineInfo(i)
        if name and not header and SKILL_IDS[name] then skills[SKILL_IDS[name]] = rank or 0 end
    end
    return skills, skillsKnown
end
ns.PlayerSkills = Skills

-- [factionID] = { [standing a quest asks for] = true }: the reputation event
-- below only counts as a change when one of these is crossed
local repAsked = {}
local function Rep(factionID, need)
    repAsked[factionID] = repAsked[factionID] or {}
    repAsked[factionID][need or 0] = true
    if not GetFactionInfoByID then return nil end
    local ok, name, _, _, _, _, value = pcall(GetFactionInfoByID, factionID)
    if ok and name then return value or 0 end
    return nil
end

local function InLogOrDone(id) return Log()[id] ~= nil or Done(id) end

local playerRaceMask, playerClassMask
local function PlayerMasks()
    if playerRaceMask == nil then
        local raceID = select(3, UnitRace("player"))
        playerRaceMask = src.Enum.raceMaskById and src.Enum.raceMaskById[raceID] or false
        local classFile = select(2, UnitClass("player"))
        playerClassMask = src.Enum.classKeys and src.Enum.classKeys[classFile] or false
    end
    return playerRaceMask, playerClassMask
end

-- quest level as the game colours it (scaling quests, -1: your level)
local function QuestLevel(q)
    local l = q.questLevel or 0
    if l <= 0 then return UnitLevel("player") end
    return l
end

local function IsTrivial(level)
    local green = GetQuestGreenRange and GetQuestGreenRange() or 8
    return UnitLevel("player") - level > green
end
ns.IsTrivialQuestLevel = IsTrivial

-- Can you take this quest now? Our own reading of QuestieDB's requirements.
-- Returns true, or false and why (for /bfi quest).
local function Available(id)
    local q = Info(id)
    if not q.name then return false, "unknown quest" end
    if QCfg().hidden[id] then return false, "hidden (Shift-click)" end
    local FQ = ns.FOREVER and ns.ForeverQuestData
    if FQ and ((FQ.gone and FQ.gone[id]) or (FQ.goneNames and FQ.goneNames[q.name])) then
        return false, "not offered on Forever (Data/ForeverQuests.lua gone)"
    end
    if Log()[id] then return false, "in your quest log" end
    local repeatable = HasBit(q.specialFlags or 0, 1)
    if Done(id) and not repeatable then return false, "done" end
    if EVENT_SORTS[q.zoneOrSort or 0] then return false, "world event quest" end
    local level = UnitLevel("player")
    if (q.requiredLevel or 0) > level then return false, "level " .. q.requiredLevel end
    if (q.requiredMaxLevel or 0) > 0 and level > q.requiredMaxLevel then return false, "too high level" end
    local race, class = PlayerMasks()
    if (q.requiredRaces or 0) ~= 0 and race and not HasBit(q.requiredRaces, race) then return false, "race" end
    if (q.requiredClasses or 0) ~= 0 and class and not HasBit(q.requiredClasses, class) then return false, "class" end
    -- (a negative ID: that quest must not be done)
    for _, pre in ipairs(q.preQuestGroup or {}) do
        if pre > 0 and not Done(pre) then return false, "needs quest " .. pre end
        if pre < 0 and Done(-pre) then return false, "after quest " .. -pre end
    end
    if q.preQuestSingle then
        local any = false
        for _, pre in ipairs(q.preQuestSingle) do
            if (pre > 0 and Done(pre)) or (pre < 0 and not Done(-pre)) then any = true break end
        end
        if not any then return false, "needs an earlier quest" end
    end
    for _, ex in ipairs(q.exclusiveTo or {}) do
        if InLogOrDone(ex) then return false, "exclusive with " .. ex end
    end
    if (q.nextQuestInChain or 0) ~= 0 and InLogOrDone(q.nextQuestInChain) then return false, "chain moved on" end
    if (q.breadcrumbForQuestId or 0) ~= 0 and InLogOrDone(q.breadcrumbForQuestId) then return false, "breadcrumb no longer needed" end
    if (q.parentQuest or 0) ~= 0 and not Log()[q.parentQuest] then return false, "needs quest " .. q.parentQuest .. " in the log" end
    if (q.availableUntilCompleted or 0) ~= 0 and Done(q.availableUntilCompleted) then return false, "no longer offered" end
    if (q.availableStartingWith or 0) ~= 0 and not InLogOrDone(q.availableStartingWith) then return false, "not offered yet" end
    if (q.disabledByQuest or 0) ~= 0 and Log()[q.disabledByQuest] then return false, "paused by another quest" end
    if q.requiredSkill then
        local have, known = Skills()
        local need = q.requiredSkill
        if known and need[1] and (have[need[1]] or -1) < (need[2] or 0) then return false, "skill " .. need[1] end
    end
    if q.requiredMinRep then
        local v = Rep(q.requiredMinRep[1], q.requiredMinRep[2]) or 0
        if v < (q.requiredMinRep[2] or 0) then return false, "reputation" end
    end
    if q.requiredMaxRep then
        local v = Rep(q.requiredMaxRep[1], q.requiredMaxRep[2])
        if v and v >= (q.requiredMaxRep[2] or 0) then return false, "reputation too high" end
    end
    if (q.requiredSpell or 0) ~= 0 and IsSpellKnown then
        local s = q.requiredSpell
        if s > 0 and not IsSpellKnown(s) then return false, "spell" end
        if s < 0 and IsSpellKnown(-s) then return false, "spell known" end
    end
    if not ns.GetTrivialQuests() and IsTrivial(QuestLevel(q)) then return false, "trivial (grey)" end
    return true, repeatable
end

-- per-version cache of Available
local avail, availVersion = {}, -1
local function IsAvailable(id)
    if availVersion ~= version then wipe(avail) availVersion = version end
    local a = avail[id]
    if a == nil then
        local ok, yes, rep = pcall(Available, id)
        a = ok and yes and { rep = rep == true } or false
        avail[id] = a
    end
    return a
end

-- Quest givers index -----------------------------------------------------------

-- givers[uiMapID] = { { x, y, name, sub, starterType, quests = { questID, ... } }, ... }
-- One entry per spawn of each NPC / object that starts quests (or drops an item
-- that does; sub: the NPC's title, "Weaponsmith"). Built once in the
-- background; what's available is decided as the map draws.
local givers, giversState = {}, nil  -- state: nil, "building", "done"

local function AddGiver(spawns, name, starterType, quests, sub, key)
    EachSpawn(spawns, function(m, x, y)
        local list = givers[m]
        if not list then list = {} givers[m] = list end
        list[#list + 1] = { x = x, y = y, name = name, sub = sub, starterType = starterType, quests = quests, key = key }
    end)
end

local function BuildGivers()
    local byNpc, byObject, byDropNpc, byDropObject = {}, {}, {}, {}
    local function Add(t, k, q)
        local l = t[k]
        if not l then l = {} t[k] = l end
        l[#l + 1] = q
    end
    local n = 0
    for _, id in ipairs(Q().GetAllIds() or {}) do
        local by = Q().startedBy(id)
        if by then
            for _, npc in ipairs(by[1] or {}) do Add(byNpc, npc, id) end
            for _, obj in ipairs(by[2] or {}) do Add(byObject, obj, id) end
            for _, item in ipairs(by[3] or {}) do
                for _, npc in ipairs(I().npcDrops(item) or {}) do Add(byDropNpc, npc, id) end
                for _, obj in ipairs(I().objectDrops(item) or {}) do Add(byDropObject, obj, id) end
            end
        end
        n = n + 1
        if n % 100 == 0 then coroutine.yield() end
    end
    for npc, quests in pairs(byNpc) do
        if Friendly(N().friendlyToFaction(npc)) then AddGiver(NpcSpawns(npc), N().name(npc), nil, quests, N().subName(npc), "c" .. npc) end
        n = n + 1
        if n % 50 == 0 then coroutine.yield() end
    end
    for obj, quests in pairs(byObject) do
        AddGiver(O().spawns(obj), O().name(obj), "Object", quests, nil, "o" .. obj)
        n = n + 1
        if n % 50 == 0 then coroutine.yield() end
    end
    -- (monsters that drop a quest's item: one "!" a camp, not one on every monster. Captain Sander's
    -- Hidden Treasure put one on each murloc of Westfall's coast, the user. Every dropper of the same
    -- quests together, a mark per DROP_CAMP of the map, at the middle of the spawns in it)
    local DROP_CAMP = 0.08
    local camps = {}   -- [quests key] = { quests, [map] = { [cell] = { x, y, n, names = { name = true } } } }
    for npc, quests in pairs(byDropNpc) do
        table.sort(quests)
        local key = table.concat(quests, ",")
        local c = camps[key]
        if not c then c = { quests = quests, maps = {} } camps[key] = c end
        local name = N().name(npc)
        EachSpawn(NpcSpawns(npc), function(m, x, y)
            local cells = c.maps[m]
            if not cells then cells = {} c.maps[m] = cells end
            local k = math.floor(x / DROP_CAMP) * 100 + math.floor(y / DROP_CAMP)
            local cell = cells[k]
            if not cell then cell = { x = 0, y = 0, n = 0, names = {}, first = name } cells[k] = cell end
            cell.x, cell.y, cell.n = cell.x + x, cell.y + y, cell.n + 1
            cell.names[name] = true
        end)
        n = n + 1
        if n % 50 == 0 then coroutine.yield() end
    end
    for _, c in pairs(camps) do
        for m, cells in pairs(c.maps) do
            local list = givers[m]
            if not list then list = {} givers[m] = list end
            -- (still a lot, the user: the busiest camp a map in full, the others faint)
            local top
            for _, cell in pairs(cells) do
                if not top or cell.n > top.n then top = cell end
            end
            for _, cell in pairs(cells) do
                local more = -1
                for _ in pairs(cell.names) do more = more + 1 end
                list[#list + 1] = { x = cell.x / cell.n, y = cell.y / cell.n, starterType = "itemFromMonster", quests = c.quests,
                                    name = cell.first .. (more > 0 and " and " .. more .. " more" or ""), faint = cell ~= top or nil }
            end
        end
        n = n + 1
        if n % 50 == 0 then coroutine.yield() end
    end
    for obj, quests in pairs(byDropObject) do
        AddGiver(O().spawns(obj), O().name(obj), "itemFromObject", quests)
        n = n + 1
        if n % 50 == 0 then coroutine.yield() end
    end
end

-- Background work -------------------------------------------------------------

-- one coroutine at a time, run a slice each frame
local jobs, runner = {}, CreateFrame("Frame")
local function RunJobs()
    runner:SetScript("OnUpdate", function()
        local job = jobs[1]
        if not job then runner:SetScript("OnUpdate", nil) return end
        local ok, err = coroutine.resume(job.co)
        if not ok then ns.Log(job.name .. " error:", tostring(err)) end
        if coroutine.status(job.co) == "dead" then
            table.remove(jobs, 1)
            if job.done then pcall(job.done, ok) end
        end
    end)
end

-- (no pcall inside: Lua 5.1 can't yield across one; errors come out of resume)
local function StartJob(name, fn, done)
    jobs[#jobs + 1] = { name = name, co = coroutine.create(fn), done = done }
    RunJobs()
end
ns.StartDataJob = StartJob

local function EnsureGivers()
    if giversState or not (Source() and LoadZones()) then return giversState == "done" end
    giversState = "building"
    StartJob("Quest giver index", BuildGivers, function(ok)
        giversState = "done"
        if not ok then wipe(givers) end
        Bump()
        if ns.RedrawQuestie then ns.RedrawQuestie() end
    end)
    return false
end

-- Turn-ins and objectives -----------------------------------------------------

-- where a quest is handed in: { { spawns, name }, ... } (cached)
local finishers = {}
local function Finishers(id)
    local f = finishers[id]
    if f then return f end
    f = {}
    local by = Q().finishedBy(id) or {}
    for _, npc in ipairs(by[1] or {}) do f[#f + 1] = { spawns = NpcSpawns(npc), name = N().name(npc) } end
    for _, obj in ipairs(by[2] or {}) do f[#f + 1] = { spawns = O().spawns(obj), name = O().name(obj) } end
    finishers[id] = f
    return f
end

-- A monster worth learning a spot for (Learn.lua): the data has none for it, and a
-- quest in your log asks you to kill it or wants an item it drops
function ns.QuestMobWanted(npc)
    if not (Source() and npc) then return false end
    local s = N().spawns(npc)
    if (s and next(s)) or N().waypoints(npc) then return false end
    for qid in pairs(Log()) do
        local objs = Q().objectives(qid) or {}
        for _, o in ipairs(objs[1] or {}) do if o[1] == npc then return true end end
        for _, o in ipairs(objs[3] or {}) do
            for _, d in ipairs(o[1] and I().npcDrops(o[1]) or {}) do if d == npc then return true end end
        end
    end
    return false
end

-- a quest's objective targets: { { icon, name, spawnLists = { spawns, ... } }, ... }
-- icon: slay / loot / object / event. (cached)
local MAX_SOURCES = 40  -- an item dropped by more mobs than this: only the first ones
local targets = {}
-- a monster spot learned or taken in (Learn.lua): the targets made afresh, the pins redrawn
function ns.LearnedMobsChanged()
    wipe(targets)
    Bump()
end
-- Taming the Beast: the data's objective is the Taming Rod you're handed, which is nowhere. The beast
-- is only in the quest's text, so here's each quest's
local TAME = { [6061] = 2956, [6087] = 2959, [6088] = 2970, [6062] = 3099, [6083] = 3107, [6082] = 3126,
               [6064] = 1126, [6084] = 1201, [6085] = 1196, [6063] = 1998, [6101] = 2043, [6102] = 1996 }

local function Targets(id)
    local t = targets[id]
    if t then return t end
    t = {}
    local objs = Q().objectives(id) or {}
    for _, o in ipairs(objs[1] or {}) do        -- creatures to kill
        if o[1] then t[#t + 1] = { icon = "slay", name = N().name(o[1]), text = o[2], spawnLists = { NpcSpawns(o[1]) } } end
    end
    for _, o in ipairs(objs[2] or {}) do        -- objects to use
        if o[1] then t[#t + 1] = { icon = "object", name = O().name(o[1]), text = o[2], spawnLists = { O().spawns(o[1]) } } end
    end
    for _, o in ipairs(objs[3] or {}) do        -- items to collect: where they drop
        if o[1] then
            -- (sources[i]: who drops it at spawnLists[i], for the tooltip; chances[i]:
            -- its % chance, our data only)
            local lists, sources, chances, k = {}, {}, {}, 0
            local nc = I().npcDropChances and I().npcDropChances(o[1]) or {}
            local oc = I().objectDropChances and I().objectDropChances(o[1]) or {}
            for j, npc in ipairs(I().npcDrops(o[1]) or {}) do
                k = k + 1
                if k <= MAX_SOURCES then
                    lists[k] = NpcSpawns(npc) or {}
                    sources[k], chances[k] = N().name(npc), nc[j]
                end
            end
            for j, obj in ipairs(I().objectDrops(o[1]) or {}) do
                k = k + 1
                if k <= MAX_SOURCES then
                    lists[k] = O().spawns(obj) or {}
                    sources[k], chances[k] = O().name(obj), oc[j]
                end
            end
            -- (and who sells it: an Empty Vial is anyone's trade goods, and had no place at all, the user)
            local ok, sellers = pcall(function() return I().vendors and I().vendors(o[1]) end)
            for _, npc in ipairs(ok and sellers or {}) do
                k = k + 1
                if k <= MAX_SOURCES then
                    lists[k] = NpcSpawns(npc) or {}
                    sources[k] = N().name(npc)
                end
            end
            t[#t + 1] = { icon = "loot", name = I().name(o[1]), text = o[2], spawnLists = lists, sources = sources,
                          chances = chances }
        end
    end
    -- kill credit: { { npcIDs }, rootNpc, text } (one, or a list of them)
    local kc = objs[5]
    if type(kc) == "table" and type(kc[1]) == "table" and type(kc[1][1]) ~= "table" then kc = { kc } end
    for _, o in ipairs(type(kc) == "table" and kc or {}) do
        if type(o) == "table" and type(o[1]) == "table" then
            local lists = {}
            for _, npc in ipairs(o[1]) do lists[#lists + 1] = NpcSpawns(npc) end
            local root = o[2] and o[2] ~= 0 and N().name(o[2]) or nil
            t[#t + 1] = { icon = "slay", name = root or o[3], text = o[3], spawnLists = lists }
        end
    end
    local trig = Q().triggerEnd(id)               -- explore / event spot
    if trig and trig[2] then t[#t + 1] = { icon = "event", name = trig[1], text = trig[1], spawnLists = { trig[2] } } end
    for _, e in ipairs(Q().extraObjectives(id) or {}) do
        if e[1] then t[#t + 1] = { icon = "event", name = e[3], text = e[3], spawnLists = { e[1] } } end
    end
    local spawns = TAME[id] and NpcSpawns(TAME[id])
    if spawns then
        local name = N().name(TAME[id])
        t = { { icon = "slay", name = name, text = "Tame " .. tostring(name), spawnLists = { spawns } } }
    end
    targets[id] = t
    return t
end

-- the item you use for a quest and carry now, else nil: what the game names for its log line, or
-- what the quest hands you or asks for, if it has a use
function ns.QuestUseItem(id, index)
    local Count = (C_Item and C_Item.GetItemCount) or GetItemCount
    local Spell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if index and GetQuestLogSpecialItemInfo then
        local link = GetQuestLogSpecialItemInfo(index)
        local item = link and tonumber(link:match("item:(%d+)"))
        if item then return item end
    end
    local list = {}
    local ok, extra = pcall(Q().GetAll, id, { "sourceItemId" })
    if ok and extra and (extra[1] or 0) > 0 then list[1] = extra[1] end
    for _, o in ipairs((Q().objectives(id) or {})[3] or {}) do list[#list + 1] = o[1] end
    for _, item in ipairs(list) do
        if Count(item) > 0 and Spell(item) then return item end
    end
end

-- the game objective a target belongs to (by name in its text), else nil
local function MatchObjective(target, game)
    local name = target.name and target.name:lower()
    if not name or name == "" then return nil end
    for _, g in ipairs(game) do
        if g.text and g.text:lower():find(name, 1, true) then return g end
    end
end

-- The data can name someone a quest doesn't ask you to kill or bring anything from: Forever's
-- Camping 101: Skinning lists its trainer, and asks you to raise your skill. So when the game's one
-- objective isn't a kill or an item and doesn't name the target, the game's words go on the spot.
local function GameGoal(game)
    local g = game and #game == 1 and game[1]
    if g and g.type and g.type ~= "monster" and g.type ~= "item" and g.text and g.text ~= "" then return g end
end

-- Icons --------------------------------------------------------------------------

local QUESTIE_ICONS = "Interface\\AddOns\\Questie\\Icons\\"
-- without Questie: the game's own mouse cursors by objective type, the art
-- Questie's icons are drawn after (the sword over an enemy, the bag over a
-- vendor, the cog over something to use); givers and turn-ins fall back in Pin.lua
-- path; crop: the part drawn (l, r, t, b: the picture, no empty edge); mask:
-- the pointer's tip in the top-left corner hidden (Media\CursorMask.tga). The
-- sword's tip is the pointer itself, so it's left whole.
local GAME_SPOT_ICONS = {
    slay   = { path = "Interface\\Cursor\\Attack",   crop = { 0, 1, 0, 1 } },                 -- kill
    loot   = { path = "Interface\\Cursor\\Buy",      crop = { 0, 0.8125, 0, 0.8125 }, mask = true },  -- collect
    object = { path = "Interface\\Cursor\\Interact", crop = { 0, 0.875, 0, 0.875 }, mask = true },    -- use something
    event  = { path = "Interface\\Cursor\\Inspect",  crop = { 0, 1, 0, 1 }, mask = true },            -- go somewhere, an event
}
ns.GAME_OBJECTIVE_ICONS = GAME_SPOT_ICONS

-- Questie's icons are there to borrow (it's installed and loaded)
function ns.QuestieArt()
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)
    return loaded and loaded("Questie") and true or false
end

-- The player's Questie settings, where it's loaded. Its themes (Questie, pfQuest,
-- Blizzard) and icon choices all end up here, so the spots follow them.
local function QuestieProfile()
    return ns.QuestieArt() and Questie and Questie.db and Questie.db.profile or nil
end
local QUESTIE_SPOT_TYPE = { slay = "ICON_TYPE_SLAY", loot = "ICON_TYPE_LOOT",
    object = "ICON_TYPE_OBJECT", event = "ICON_TYPE_EVENT" }

-- Questie's quest log: each quest's own table, with the colours it gave them. They come from a
-- shuffled wheel, once a session, so they're read, not worked out. Nil where it isn't there.
local function QuestieLog()
    local player = QuestieLoader and QuestieLoader.ImportModule and QuestieLoader:ImportModule("QuestiePlayer")
    return player and player.currentQuestlog or nil
end

local function QuestieQuestOf(id)
    local log = ns.QuestieArt() and QuestieLog()
    local q = log and log[id]
    return type(q) == "table" and q or nil
end

-- the colour Questie gave this objective (its glow; the icon takes the quest's)
local function QuestieObjectiveColor(quest, name)
    name = name and name:lower()
    if not name or name == "" then return quest.Color end
    for _, list in ipairs({ quest.Objectives or {}, quest.SpecialObjectives or {} }) do
        for _, o in pairs(list) do
            if o.Color and o.Description and o.Description:lower():find(name, 1, true) then return o.Color end
        end
    end
    return quest.Color
end

-- what the spots take from Questie, as a string: a change redraws them (BattlefieldInfo.lua)
function ns.QuestieLookSig()
    local p = QuestieProfile()
    if not p then return "" end
    local used = Questie.usedIcons and Questie.ICON_TYPE_SLAY and Questie.usedIcons[Questie.ICON_TYPE_SLAY]
    -- (how many colours it has given so far: it hands them out after we've drawn)
    local coloured = 0
    for _, q in pairs(QuestieLog() or {}) do
        if type(q) == "table" then
            if q.Color then coloured = coloured + 1 end
            for _, o in pairs(q.Objectives or {}) do
                if o.Color then coloured = coloured + 1 end
            end
        end
    end
    return tostring(p.iconTheme) .. tostring(p.questObjectiveColors) .. tostring(p.alwaysGlowMap) .. tostring(used) .. coloured
end

-- Questie's own objectives and ours are both in use: the game's are left off then, as
-- its themes set them (only its Blizzard theme has them on). See ns.ApplyGroups.
function ns.QuestieKeepsObjectivesOff()
    local p = QuestieProfile()
    return p and p.iconTheme and p.iconTheme ~= "blizzard" or false
end

-- an objective spot's icon: the one chosen in Questie (spots.questieIcons, where it's loaded), or the
-- game's cursor art (spec): Waymark's look stays Waymark's with Questie on
function ns.SpotsQuestieArt() return ns.QuestieArt() and ns.db.spots.questieIcons and true or false end
function ns.SpotIconsChanged() Bump() end
local function IconPath(kind)
    if ns.SpotsQuestieArt() then
        local key = Questie and QUESTIE_SPOT_TYPE[kind] and Questie[QUESTIE_SPOT_TYPE[kind]]
        local used = key and Questie.usedIcons and Questie.usedIcons[key]
        return used or QUESTIE_ICONS .. kind .. ".blp"
    end
    return GAME_SPOT_ICONS[kind] and GAME_SPOT_ICONS[kind].path
end
local NO_CROP = { 0, 1, 0, 1 }
local function IconSpec(kind)
    if ns.SpotsQuestieArt() then return nil end
    return GAME_SPOT_ICONS[kind]
end

-- a steady colour per quest, for its objective spots (spots.color)
local function QuestColor(id)
    local h = (id * 0.618033988749895) % 1
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local q, t = 1 - f, f
    local r, g, b
    if i == 0 then r, g, b = 1, t, 0 elseif i == 1 then r, g, b = q, 1, 0
    elseif i == 2 then r, g, b = 0, 1, t elseif i == 3 then r, g, b = 0, q, 1
    elseif i == 4 then r, g, b = t, 0, 1 else r, g, b = 1, 0, q end
    return { 0.35 + r * 0.65, 0.35 + g * 0.65, 0.35 + b * 0.65 }
end

-- the glow behind a spot, where Questie's theme has one, Questie has no colour for it yet and
-- "A colour per quest" is off: by what the objective asks (slay red, gather green, use blue)
local SPOT_GLOW = {
    slay = { 0.85, 0.1, 0.1 }, loot = { 0.2, 0.7, 0.2 },
    object = { 0.25, 0.5, 0.95 }, event = { 0.6, 0.3, 0.9 },
}

-- The pins ---------------------------------------------------------------------

local function QuestName(id) return Info(id).name or ("Quest " .. id) end
ns.QuestNameOf = QuestName
function ns.QuestLevelOf(id) return QuestLevel(Info(id)) end

-- For tooltips: the quest's objective text ("Kill 10 Kobold Vermin, then
-- return to Marshal McBride."), whether it repeats, and the items that start it
function ns.QuestDetails(id)
    if not Source() then return {} end
    local text = Q().objectivesText(id)
    local items = {}
    local by = Q().startedBy(id)
    for _, item in ipairs(by and by[3] or {}) do items[#items + 1] = I().name(item) end
    return {
        text = type(text) == "table" and table.concat(text, " ") or text,
        repeatable = HasBit(Info(id).specialFlags or 0, 1),
        items = items,
    }
end

-- For the quest window: who gives the quest and who takes it in, as
-- "Name (Zone)" (an item that starts it: its name). { from = {}, to = {} }
local function SpawnZone(spawns)
    for areaID in pairs(spawns or {}) do
        local name = type(areaID) == "number" and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
        if name then return name end
    end
end
function ns.QuestPeople(id)
    if not Source() then return nil end
    local function List(by)
        local out = {}
        local function Add(name, spawns)
            if not name or #out >= 3 then return end
            local zone = SpawnZone(spawns)
            out[#out + 1] = zone and (name .. " (" .. zone .. ")") or name
        end
        for _, npc in ipairs(by and by[1] or {}) do Add(N().name(npc), NpcSpawns(npc)) end
        for _, obj in ipairs(by and by[2] or {}) do Add(O().name(obj), O().spawns(obj)) end
        -- (an item says so, and where it's found when we know: the user 2026-11-09, the Treaty of
        -- Understanding read like a person)
        for _, item in ipairs(by and by[3] or {}) do
            local name = I().name(item)
            if name and #out < 3 then
                local inst = ns.FOREVER and ns.ForeverQuestData and ns.ForeverQuestData.itemIn
                    and ns.ForeverQuestData.itemIn[item]
                local where = inst and GetRealZoneText and GetRealZoneText(inst)
                out[#out + 1] = "Item: " .. name .. ((where and where ~= "") and (" (in " .. where .. ")") or "")
            end
        end
        return out
    end
    return { from = List(Q().startedBy(id)), to = List(Q().finishedBy(id)) }
end

-- For the tracker: who gives the quest and who takes it in, with one spot
-- each (on mapID where they have one there). { from = { name, map, x, y },
-- to = { ... } }; map nil: an item, or nowhere outside dungeons. (cached)
local ends = {}
function ns.QuestEnds(id, mapID)
    if not Source() then return nil end
    local key = id .. ":" .. tostring(mapID)
    if ends[key] then return ends[key] end
    local function First(by)
        local function Spot(name, spawns)
            local e = { name = name }
            ns.EachSpawnOnMap(spawns, function(m, x, y)
                if not e.map or (m == mapID and e.map ~= mapID) then e.map, e.x, e.y = m, x, y end
            end)
            return e
        end
        for _, npc in ipairs(by and by[1] or {}) do
            local name = N().name(npc)
            if name then return Spot(name, NpcSpawns(npc)) end
        end
        for _, obj in ipairs(by and by[2] or {}) do
            local name = O().name(obj)
            if name then return Spot(name, O().spawns(obj)) end
        end
        for _, item in ipairs(by and by[3] or {}) do
            local name = I().name(item)
            if name then return { name = name } end
        end
    end
    local e = { from = First(Q().startedBy(id)), to = First(Q().finishedBy(id)) }
    ends[key] = e
    return e
end

-- A quest's rewards (our data only): { choice = { { itemID, name, count } },
-- fixed = { the same }, copper }, or nil
function ns.QuestRewards(id)
    if not Source() then return nil end
    local r = Q().rewards and Q().rewards(id)
    if not r then return nil end
    local function List(l)
        local out = {}
        for _, e in ipairs(l or {}) do out[#out + 1] = { e[1], I().name(e[1]) or ("Item " .. e[1]), e[2] or 1 } end
        return out
    end
    return { choice = List(r[1]), fixed = List(r[2]), copper = r[3] }
end

-- a drop chance for a tooltip: "38%", "<1%" (nil: unknown)
function ns.ChanceText(c)
    if not c then return nil end
    if c >= 99.5 then return "always" end
    return c < 1 and "<1%" or string.format("%d%%", math.floor(c + 0.5))
end

-- For the giver tooltip: what a quest asks, in a word ("Slay", "Gather", "Use",
-- "Explore", "Escort", "Deliver", "Speak"; nil: can't tell), and its tag
-- ("Group", "Dungeon", "Raid", "PvP"; nil: none), from the data, not its text
local QUEST_TAGS = { [1] = "Group", [41] = "PvP", [62] = "Raid", [81] = "Dungeon" }
local kinds = {}
function ns.QuestKind(id)
    local k = kinds[id]
    if k then return k[1] or nil, k[2] or nil end
    if not Source() then return nil end
    local word
    local o = Q().objectives(id) or {}
    -- (kill credit with no monster named, a place to visit or a thing to do there: Eyes of the Sentinels
    -- read Slay, the user. Such credit says no word of its own)
    local kc, killing = o[5], false
    if type(kc) == "table" and type(kc[1]) == "table" and type(kc[1][1]) ~= "table" then kc = { kc } end
    for _, c in ipairs(type(kc) == "table" and kc or {}) do
        if type(c) == "table" and c[2] and c[2] ~= 0 then killing = true end
    end
    if (o[1] and o[1][1]) or killing then word = "Slay"
    elseif o[3] and o[3][1] then word = "Gather"
    elseif o[2] and o[2][1] then word = "Use" end
    local trig = not word and Q().triggerEnd(id)
    if trig then word = type(trig[1]) == "string" and trig[1]:find("^Escort") and "Escort" or "Explore" end
    local ok, extra = pcall(Q().GetAll, id, { "sourceItemId", "questType" })
    extra = ok and extra or {}
    -- (the one item it asks for is the one it hands you: you carry it over)
    if word == "Gather" and (extra[1] or 0) > 0 and #o[3] == 1 and o[3][1][1] == extra[1] then word = "Deliver" end
    if not word then
        if (extra[1] or 0) > 0 then
            word = "Deliver"
        else
            local by, to = Q().startedBy(id), Q().finishedBy(id)
            local a, b = by and by[1] and by[1][1], to and to[1] and to[1][1]
            -- (started by an item: nobody hands it to you, you bring it to someone)
            if by and by[3] and by[3][1] then word = "Deliver"
            elseif b and a ~= b then word = "Speak" end
        end
    end
    local tag = QUEST_TAGS[extra[2] or 0]
    local zone = Info(id).zoneOrSort or 0
    if not tag and zone > 0 and LoadZones() and dungeonArea[zone] then tag = "Dungeon" end
    kinds[id] = { word or false, tag or false }
    return word, tag
end

-- In your log the game knows better than the data: Slay only if it asks for a kill
local KindFromData = ns.QuestKind
local GAME_KIND = { item = "Gather", object = "Use" }
function ns.QuestKind(id)
    local word, tag = KindFromData(id)
    if word ~= "Slay" then return word, tag end
    local game = GameObjectives(id)
    if #game == 0 then return word, tag end
    local other
    for _, g in ipairs(game) do
        if not g.type or g.type == "monster" then return word, tag end
        other = other or GAME_KIND[g.type]
    end
    return other, tag
end

-- [questID] = { level, base XP }: QuestieDB's support table (false: none)
local xpTable
local function XPTable()
    if xpTable == nil then
        local ok, s = pcall(src.Support.Get, "QuestXP")
        xpTable = ok and type(s) == "table" and LoadTable(s.db) or false
    end
    return xpTable or nil
end

-- the XP a quest gives you at your level (0: unknown, or at max level). Full
-- XP up to 5 levels above the quest, then 20% less a level down to 10%,
-- rounded as the game does it (to 5 / 10 / 25 / 50). No XP buffs counted.
function ns.QuestXP(id)
    local t = Source() and XPTable()
    local e = t and t[id]
    if not (e and (e[1] or 0) > 0 and (e[2] or 0) > 0) then return 0 end
    local me = UnitLevel("player")
    if me >= (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) then return 0 end
    local over = me - e[1]
    local xp = e[2] * (over <= 5 and 1 or math.max(0.1, 1 - (over - 5) * 0.2))
    local step = xp <= 100 and 5 or xp <= 500 and 10 or xp <= 1000 and 25 or 50
    return step * math.floor(xp / step + 0.5)
end

-- your race and class may take it (chain and breadcrumb lists skip the rest)
local function ForMe(id)
    local q = Info(id)
    if not q.name then return false end
    local race, class = PlayerMasks()
    if (q.requiredRaces or 0) ~= 0 and race and not HasBit(q.requiredRaces, race) then return false end
    if (q.requiredClasses or 0) ~= 0 and class and not HasBit(q.requiredClasses, class) then return false end
    return true
end

local function FactionName(factionID)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, d = pcall(C_Reputation.GetFactionDataByID, factionID)
        if ok and d and d.name then return d.name end
    end
    if GetFactionInfoByID then
        local ok, name = pcall(GetFactionInfoByID, factionID)
        if ok and name then return name end
    end
    return "Faction " .. factionID
end

-- More for a tooltip (with Shift): { rep = { { name, value } }, chain = { ids
-- after this one }, breadcrumbs = { ids leading here, not done }, dungeon }
local MAX_CHAIN = 15
function ns.QuestMore(id)
    if not Source() then return {} end
    local out = { rep = {}, chain = {}, breadcrumbs = {} }
    for _, r in ipairs(Q().reputationReward(id) or {}) do
        if r[1] and r[2] and r[2] ~= 0 then out.rep[#out.rep + 1] = { FactionName(r[1]), r[2] } end
    end
    local seen, nxt = { [id] = true }, Info(id).nextQuestInChain
    while nxt and nxt > 0 and not seen[nxt] and #out.chain < MAX_CHAIN and ForMe(nxt) do
        seen[nxt] = true
        out.chain[#out.chain + 1] = nxt
        nxt = Info(nxt).nextQuestInChain
    end
    for _, b in ipairs(Q().breadcrumbs(id) or {}) do
        if ForMe(b) and not Done(b) and not Log()[b] then out.breadcrumbs[#out.breadcrumbs + 1] = b end
    end
    local zone = Info(id).zoneOrSort or 0
    if zone > 0 and LoadZones() and dungeonArea[zone] and C_Map and C_Map.GetAreaInfo then
        out.dungeon = C_Map.GetAreaInfo(zone)
    end
    return out
end

-- [questID] = { quests whose next in chain it is } (built once, on first use)
local prevOf
local function PrevOf()
    if prevOf then return prevOf end
    prevOf = {}
    for _, q in ipairs(Q().GetAllIds() or {}) do
        local nxt = Info(q).nextQuestInChain
        if nxt and nxt > 0 then
            local l = prevOf[nxt]
            if not l then l = {} prevOf[nxt] = l end
            l[#l + 1] = q
        end
    end
    return prevOf
end

-- For the quest window: the chain a quest is in, every step (your race and
-- class's), and the quests that lead into it. { index = this one's step,
-- steps = { { id, name, level, done, inLog } }, crumbs = { the same } };
-- nil when there's no chain and nothing leads here
-- p is the step before q: p names q as its next, and q needs p (one of its
-- earlier quests) or p is a breadcrumb for q ("crumb": the chain starts
-- there; what came before it is another line that only sends you here).
-- nextQuestInChain alone is set loosely in QuestieDB, which put unrelated
-- quests at the start of chains.
local function StepBefore(p, q)
    if Info(p).breadcrumbForQuestId == q then return "crumb" end
    local info = Info(q)
    for _, list in ipairs({ info.preQuestSingle or {}, info.preQuestGroup or {} }) do
        for _, pre in ipairs(list) do
            if pre == p then return true end
        end
    end
    return false
end

function ns.QuestChain(id)
    if not Source() then return nil end
    local ids, seen = { id }, { [id] = true }
    local cur = id
    while #ids < MAX_CHAIN * 2 do
        local prev, how
        for _, p in ipairs(PrevOf()[cur] or {}) do
            if not seen[p] and ForMe(p) then
                how = StepBefore(p, cur)
                if how then prev = p break end
            end
        end
        if not prev then break end
        table.insert(ids, 1, prev)
        seen[prev], cur = true, prev
        if how == "crumb" then break end
    end
    local index = #ids
    local nxt = Info(id).nextQuestInChain
    while nxt and nxt > 0 and not seen[nxt] and #ids < MAX_CHAIN * 2 and ForMe(nxt) do
        seen[nxt] = true
        ids[#ids + 1] = nxt
        nxt = Info(nxt).nextQuestInChain
    end
    local function Step(q)
        return { id = q, name = QuestName(q), level = ns.QuestLevelOf(q), done = Done(q) and true or false,
                 inLog = Log()[q] and true or false }
    end
    local out = { index = index, steps = {}, crumbs = {} }
    for _, q in ipairs(ids) do out.steps[#out.steps + 1] = Step(q) end
    for _, b in ipairs(Q().breadcrumbs(id) or {}) do
        if ForMe(b) and not seen[b] then out.crumbs[#out.crumbs + 1] = Step(b) end
    end
    if #out.steps < 2 and #out.crumbs == 0 then return nil end
    return out
end

-- What a quest needs done before it (preQuestGroup: all of them; preQuestSingle: one of
-- them), your race and class's: steps as ns.QuestChain's plus all = true / false; nil
-- when nothing. For the quest window's page of a quest you haven't got: what's missing.
function ns.QuestNeeds(id)
    if not Source() then return nil end
    local info, out = Info(id), {}
    local function Add(list, all)
        for _, q in ipairs(list or {}) do
            if ForMe(q) then
                out[#out + 1] = { id = q, name = QuestName(q), level = ns.QuestLevelOf(q), all = all,
                                  done = Done(q) and true or false, inLog = Log()[q] and true or false }
            end
        end
    end
    Add(info.preQuestGroup, true)
    Add(info.preQuestSingle, false)
    return #out > 0 and out or nil
end

-- (Lab\QuestRoute.lua's way in; nothing in a build calls it)
ns.QuestRouteParts = {
    Log = Log, Info = Info, Done = Done, ForMe = ForMe, Available = IsAvailable, Targets = Targets, Finishers = Finishers,
    Objectives = GameObjectives, Match = MatchObjective, EnsureGivers = EnsureGivers,
    Givers = function() return givers end,
}

-- A quest not in your log, for the quest window's preview of a chain step:
-- { name, level, minLevel, text (its objectives), people (giver, turn-in) }
function ns.QuestPreview(id)
    if not Source() then return nil end
    local q = Info(id)
    return { name = QuestName(id), level = ns.QuestLevelOf(id), minLevel = q.requiredLevel,
             text = ns.QuestDetails(id).text, people = ns.QuestPeople(id) }
end

local MAX_SPOTS = 400  -- per objective on one map

-- Fewer pins per objective (spots.spacing, spots.maxPer; Questie's own setting
-- isn't read): points = { {x, y}, ... } (0-1) -> keep[i] = true for the ones drawn.
-- First no two closer than spacing yards (in spawn order), then, above maxPer,
-- the most spread-out ones: each next pick is the point farthest from all picked.
local function ThinSpots(points, mapID)
    local c = ns.db.spots
    local spacing, maxPer = c.spacing or 0, c.maxPer or 0
    local keep, kept = {}, {}
    local w, h = ns.MapYards(mapID)
    if not w then w, h = 1000, 1000 end  -- (size unknown: about a zone's)
    local r2 = spacing * spacing
    for i, p in ipairs(points) do
        local near = false
        if spacing > 0 then
            for _, k in ipairs(kept) do
                local dx, dy = (points[k][1] - p[1]) * w, (points[k][2] - p[2]) * h
                if dx * dx + dy * dy < r2 then near = true break end
            end
        end
        if not near then kept[#kept + 1] = i end
    end
    if maxPer > 0 and #kept > maxPer then
        -- farthest-point picking, starting from the first spawn
        local dist, picked = {}, { kept[1] }
        for j = 2, #kept do dist[j] = math.huge end
        while #picked < maxPer do
            local last, best, bestD = points[picked[#picked]], nil, -1
            for j = 2, #kept do
                if dist[j] then
                    local p = points[kept[j]]
                    local dx, dy = (p[1] - last[1]) * w, (p[2] - last[2]) * h
                    local d = dx * dx + dy * dy
                    if d < dist[j] then dist[j] = d end
                    if dist[j] > bestD then best, bestD = j, dist[j] end
                end
            end
            if not best then break end
            picked[#picked + 1] = kept[best]
            dist[best] = nil
        end
        kept = picked
    end
    for _, i in ipairs(kept) do keep[i] = true end
    return keep
end

-- Every quest pin on a map: { x, y (0-100), id, name, group, level, kind, value,
-- l, r, t, b, starterType, iconColor, quests, who, objective } (Pin.lua draws them)
-- (kept for every map asked about until the quests or your level change: a
-- continent asks for all its zones, and one map kept alone rebuilt them all)
local iconCache, iconStamp = {}, nil
-- whether a map's pins are kept already (a continent builds its zones a few a frame)
function ns.QuestIconsKept(mapID)
    return iconStamp == version .. ":" .. UnitLevel("player") and iconCache[mapID] ~= nil
end
-- The givers on a map, with those the data files under the capital's zone (or the capital's own, on the
-- zone's map) moved onto it, as EachOnMap does for objectives. Kept per map: the index doesn't change.
local giversOn = {}
local function GiversOn(mapID)
    local l = giversOn[mapID]
    if l then return l end
    l = {}
    for _, g in ipairs(givers[mapID] or {}) do l[#l + 1] = g end
    for other, list in pairs(givers) do
        if other ~= mapID and (CITY_IN[other] == mapID or CITY_IN[mapID] == other) then
            local a, b = WorldBox(other), WorldBox(mapID)
            if a and b then
                for _, g in ipairs(list) do
                    local tx, ty = (a.y0 + g.x * a.dy - b.y0) / b.dy, (a.x0 + g.y * a.dx - b.x0) / b.dx
                    if tx >= 0 and tx <= 1 and ty >= 0 and ty <= 1 then
                        local c = {}
                        for k, v in pairs(g) do c[k] = v end
                        c.x, c.y = tx, ty
                        l[#l + 1] = c
                    end
                end
            end
        end
    end
    if giversState == "done" then giversOn[mapID] = l end
    return l
end

-- Who you've seen offering each quest (Learn.lua's givers): [questID] = { [key] = true }, keys "c" .. npc,
-- "o" .. object. Where you have, that's the quest's giver: the data's others lose it (the user, 2026-11-08:
-- Teldrassil from the Oracle Tree Bark on Forever, not Sentinel Arynia). Only a creature or an object counts
-- (Learn.lua's Giver), never an item or a player sharing.
local learnedBy, learnedStamp = {}, nil
local function LearnedBy()
    local stamp = ns.learnedVersion or 0
    if learnedStamp == stamp then return learnedBy end
    learnedStamp = stamp
    wipe(learnedBy)
    for key, g in pairs(WaymarkQuestDB and WaymarkQuestDB.givers or {}) do
        for id in pairs(g.offers or {}) do
            learnedBy[id] = learnedBy[id] or {}
            learnedBy[id][key] = true
        end
    end
    return learnedBy
end
-- the data's givers for a quest don't include this one you met (Learn.lua shows its pin then)
function ns.DataGiverDiffers(id, key)
    if not Source() then return false end
    local ok, by = pcall(Q().startedBy, id)
    if not (ok and by) then return true end
    for _, npc in ipairs(by[1] or {}) do if "c" .. npc == key then return false end end
    for _, obj in ipairs(by[2] or {}) do if "o" .. obj == key then return false end end
    return true
end

function ns.QuestIcons(mapID)
    if not (mapID and Source() and LoadZones()) then return {} end
    local stamp = version .. ":" .. UnitLevel("player") .. ":" .. (ns.learnedVersion or 0) .. tostring(ns.IsShown("learned"))
    if iconStamp ~= stamp then wipe(iconCache) iconStamp = stamp end
    if iconCache[mapID] then return iconCache[mapID] end
    local out = {}
    local art = ns.QuestieArt()

    -- quest givers
    if EnsureGivers() then
        -- (where you met a giver on this map wins over the data's spawn, one pin: Forever moved some,
        -- Byancie in Dolanaar, the user 2026-11-08, and the learned spot is the real one)
        local moved = {}
        for _, g in ipairs(GiversOn(mapID)) do
            local lx, ly
            if g.key and ns.LearnedSpot then lx, ly = ns.LearnedSpot(g.key, mapID) end
            if lx and moved[g.key] then
                -- (another spawn of the same giver: already at the learned spot)
            else
            if lx then moved[g.key] = true end
            local quests, best, bestLevel, anyRep = {}, nil, nil, false
            -- (only while the learned pins show: they're where the quest is then)
            local seen = ns.IsShown("learned") and LearnedBy() or {}
            for _, id in ipairs(g.quests) do
                local a = IsAvailable(id)
                -- (you've met who really gives it, and it isn't this one: not here)
                if a and seen[id] and not (g.key and seen[id][g.key]) then a = nil end
                if a then
                    quests[#quests + 1] = id
                    local lvl = QuestLevel(Info(id))
                    -- the pin: the quest that's least trivial
                    local trivial = IsTrivial(lvl)
                    if not best or (best.trivial and not trivial) or (best.trivial == trivial and lvl > bestLevel) then
                        best, bestLevel = { id = id, trivial = trivial }, lvl
                    end
                    anyRep = anyRep or a.rep
                end
            end
            if best then
                local icon = best.trivial and "available_gray" or (anyRep and #quests == 1 and "repeatable") or "available"
                out[#out + 1] = {
                    x = (lx or g.x) * 100, y = (ly or g.y) * 100, id = best.id, name = QuestName(best.id), group = "questie",
                    level = bestLevel, starterType = g.starterType, who = g.name, sub = g.sub, quests = quests, faint = g.faint,
                    trivial = best.trivial or nil,
                    kind = art and "file" or nil, value = art and (QUESTIE_ICONS .. icon .. ".blp") or nil,
                    l = 0, r = 1, t = 0, b = 1,
                }
            end
            end
        end
    end

    -- turn-ins and objective spots, for the quests in your log
    for id, e in pairs(Log()) do
        if QCfg().hidden[id] then
            -- (hidden: nothing of it)
        elseif e.complete then
            local rep = HasBit(Info(id).specialFlags or 0, 1)
            for _, f in ipairs(Finishers(id)) do
                -- (EachOnMap: a capital's own map too, where the data files the hand-in under its zone. Fandral
                -- Staghelm's two in Darnassus had no "?" while the route knew them, the user 2026-11-08)
                EachOnMap(f.spawns, mapID, function(x, y)
                    out[#out + 1] = {
                        x = x * 100, y = y * 100, id = id, name = QuestName(id), group = "turnins",
                        level = QuestLevel(Info(id)), who = f.name, quests = { id },
                        kind = art and "file" or nil,
                        value = art and (QUESTIE_ICONS .. (rep and "repeatable_complete" or "complete") .. ".blp") or nil,
                        l = 0, r = 1, t = 0, b = 1,
                    }
                end)
            end
        else
            local game = GameObjectives(id)
            -- (Questie's own colours and glow where it has them, so ours match its pins: in Questie's look only.
            -- In Waymark's, Questie's colour setting coloured ours though A colour per quest was off, the user)
            local qp = ns.SpotsQuestieArt() and QuestieProfile() or nil
            local questie = QuestieQuestOf(id)
            local color = (ns.db.spots.color or qp and qp.questObjectiveColors)
                and (questie and questie.Color or QuestColor(id)) or nil
            local glowOn = qp and qp.alwaysGlowMap
            local questGlow = ns.db.spots.color and color or nil
            for _, t in ipairs(Targets(id)) do
                local g = MatchObjective(t, game)
                local goal = not g and GameGoal(game)
                g = g or goal
                if not (g and g.finished) then
                    local icon = goal and "event" or t.icon
                    local spotGlow = glowOn and (questie and QuestieObjectiveColor(questie, t.name)
                        or questGlow or SPOT_GLOW[icon]) or nil
                    local spec = IconSpec(icon)
                    -- (on the map a masked icon is drawn whole, the mask exactly over
                    -- it: pins are small and scaled, a cropped one's mask landed off)
                    local mask = spec and spec.mask or nil
                    local crop = (spec and not mask) and spec.crop or NO_CROP
                    local points = {}
                    for i, spawns in ipairs(t.spawnLists) do
                        EachOnMap(spawns, mapID, function(x, y)
                            if #points < MAX_SPOTS then points[#points + 1] = { x, y, i } end
                        end)
                    end
                    -- every spawn is kept (the tracker's distances use them all);
                    -- thinned ones just aren't drawn
                    local keep = ThinSpots(points, mapID)
                    for k, p in ipairs(points) do
                        out[#out + 1] = {
                            x = p[1] * 100, y = p[2] * 100, id = id, name = QuestName(id), group = "spots",
                            who = goal and goal.text or t.name, source = not goal and t.sources and t.sources[p[3]] or nil,
                            chance = t.chances and t.chances[p[3]],
                            objective = g and g.text or t.text, objIcon = icon,
                            kind = "file", value = IconPath(icon),
                            l = crop[1], r = crop[2], t = crop[3], b = crop[4], mask = mask,
                            iconColor = color, questieGlow = spotGlow, thinned = not keep[k] or nil,
                        }
                    end
                end
            end
        end
    end
    iconCache[mapID] = out
    return out
end

-- For the tracker: [questID] = { spots = { {x, y} }, turnin = { {x, y} } } (0-1)
-- (cached like the icons: the tracker asks every second; don't change what it gives)
local pointsCache, pointsKey
function ns.QuestPoints(mapID)
    local key = mapID and (mapID .. ":" .. version .. ":" .. UnitLevel("player"))
    if key and key == pointsKey then return pointsCache end
    local out = {}
    for _, icon in ipairs(ns.QuestIcons(mapID)) do
        if icon.group ~= "questie" then
            local q = out[icon.id]
            if not q then q = { spots = {}, turnin = {} } out[icon.id] = q end
            local into = icon.group == "turnins" and q.turnin or q.spots
            into[#into + 1] = { icon.x / 100, icon.y / 100 }
        end
    end
    pointsCache, pointsKey = out, key
    return out
end

-- For "find on map" (the quest log's menu, Tracker.lua): the map where a quest in your
-- log is to be done: its unfinished objectives' spots (done: its turn-in), the map
-- with most of them, where you are if it has any. Not in the log: its giver first, you've
-- yet to take it. None known: where it's handed in, then its giver. nil: nowhere known
function ns.QuestFindMap(id)
    if not (id and Source()) then return nil end
    local count, here = {}, C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local function Add(m) count[m] = (count[m] or 0) + 1 end
    local e = Log()[id]
    if not e then
        local ok, ends = pcall(ns.QuestEnds, id)
        if ok and ends and ends.from and ends.from.map then return ends.from.map end
        -- (an item found in a dungeon starts it: the dungeon's entrance, where you've walked in)
        local inst = ns.QuestItemDungeon and ns.QuestItemDungeon(id)
        local em = inst and ns.LearnedEntrance and ns.LearnedEntrance(inst)
        if em then return em end
    end
    if e and not e.complete then
        local game = GameObjectives(id)
        for _, t in ipairs(Targets(id)) do
            local g = MatchObjective(t, game)
            if not (g and g.finished) then
                for _, spawns in ipairs(t.spawnLists) do EachSpawn(spawns, Add) end
            end
        end
    end
    if not next(count) then
        for _, f in ipairs(Finishers(id)) do EachSpawn(f.spawns, Add) end
    end
    if here and count[here] then return here end
    local best, n = nil, 0
    for m, c in pairs(count) do
        if c > n then best, n = m, c end
    end
    if best then return best end
    local ok, ends = pcall(ns.QuestEnds, id)
    if ok and ends and ends.from and ends.from.map then return ends.from.map end
    return ns.QuestFindMapLearned(id, e, here)
end

-- A quest our data doesn't know (Forever's own): who you've met offering it or taking it in
-- (Learn.lua's givers: their offers and takes, and where you stood), the game's own quest marker
-- on your map, else nil. In your log and done: who takes it first; else who gives it. (The user,
-- 2026-11-09: "find on map" did nothing for Forever quests)
function ns.QuestFindMapLearned(id, e, here)
    local db = WaymarkQuestDB and WaymarkQuestDB.givers
    local function From(field)
        local best, bestN
        for _, g in pairs(db or {}) do
            if g[field] and g[field][id] then
                for m, s in pairs(g.spots or {}) do
                    -- (where you are first, then the spot you stood at most)
                    local n = (m == here and 1e6 or 0) + (s[3] or 1)
                    if not bestN or n > bestN then best, bestN = m, n end
                end
            end
        end
        return best
    end
    local m
    if e and e.complete then m = From("takes") or From("offers") else m = From("offers") or From("takes") end
    if m then return m end
    -- (the game's own marker: the quest on the map you're on)
    if here and C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local ok, list = pcall(C_QuestLog.GetQuestsOnMap, here)
        for _, q in ipairs(ok and list or {}) do
            if q.questID == id then return here end
        end
    end
    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        local ok, wm = pcall(C_QuestLog.GetNextWaypoint, id)
        if ok and wm then return wm end
    end
    return nil
end

-- For the quest ground (QuestGround.lua): where the monsters, drops and things
-- of the quests in your log are on a map (not finished objectives), and with
-- all, of the quests you could take from givers on this map. 0-1, cached:
-- { { id, name, level, color, inLog, parts = { { icon, what, item, text, points = { {x, y} } } } } }
local groundCache, groundKey
function ns.QuestGround(mapID, all)
    if not (mapID and Source() and LoadZones()) then return {} end
    local key = mapID .. ":" .. version .. ":" .. UnitLevel("player") .. ":" .. tostring(all and true)
    if groundKey == key then return groundCache end
    local out, seen = {}, {}
    local function Add(id, inLog, game)
        seen[id] = true
        local q = { id = id, name = QuestName(id), level = QuestLevel(Info(id)), color = QuestColor(id),
                    inLog = inLog, parts = {} }
        for _, t in ipairs(Targets(id)) do
            local g = game and MatchObjective(t, game)
            local goal = not g and GameGoal(game)
            g = g or goal
            if not (g and g.finished) then
                for i, spawns in ipairs(t.spawnLists) do
                    local pts = {}
                    EachOnMap(spawns, mapID, function(x, y)
                        if #pts < MAX_SPOTS then pts[#pts + 1] = { x, y } end
                    end)
                    if #pts > 0 then
                        q.parts[#q.parts + 1] = {
                            icon = goal and "event" or t.icon,
                            what = goal and goal.text or t.sources and t.sources[i] or t.name,
                            item = not goal and t.icon == "loot" and t.name or nil, text = g and g.text or t.text, points = pts,
                            chance = t.chances and t.chances[i],
                        }
                    end
                end
            end
        end
        if #q.parts > 0 then out[#out + 1] = q end
    end
    for id, e in pairs(Log()) do
        if not QCfg().hidden[id] and not e.complete then Add(id, true, GameObjectives(id)) end
    end
    if all and EnsureGivers() then
        for _, g in ipairs(givers[mapID] or {}) do
            for _, id in ipairs(g.quests) do
                if not seen[id] and IsAvailable(id) then Add(id, false) end
            end
        end
    end
    groundCache, groundKey = out, key
    return out
end

-- (for /bfi check) each quest in your log: its objectives' places in the data, on this map and in all,
-- and whether it's hidden; for a quest whose marks are missing
function ns.QuestTargetsInfo(mapID)
    if not (Source() and LoadZones()) then return "no quest data" end
    local out = {}
    -- (and what's drawn on the zone's map, the city's zone where you're in a city: pins and ground parts a quest)
    local zone = CITY_IN[mapID] or mapID
    local pins, ground = {}, {}
    pcall(function()
        for _, icon in ipairs(ns.QuestIcons(zone) or {}) do
            if icon.group == "spots" then pins[icon.id] = (pins[icon.id] or 0) + 1 end
        end
        for _, q in ipairs(ns.QuestGround(zone, false) or {}) do ground[q.id] = #q.parts end
    end)
    for id, e in pairs(Log()) do
        local here, all, n, maps = 0, 0, 0, {}
        local ok = pcall(function()
            for _, t in ipairs(Targets(id)) do
                n = n + 1
                for _, spawns in ipairs(t.spawnLists or {}) do
                    EachSpawn(spawns, function(m)
                        all = all + 1
                        maps[m] = (maps[m] or 0) + 1
                    end)
                    EachOnMap(spawns, mapID, function() here = here + 1 end)
                end
            end
        end)
        -- (which maps the spots are filed under, the most first)
        local list = {}
        for m, c in pairs(maps) do list[#list + 1] = { m, c } end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        for k, e in ipairs(list) do list[k] = e[1] .. "=" .. e[2] end
        local o = Q().objectives(id)
        out[#out + 1] = string.format("%d %s: %s targets, %d spots here, %d in all (maps %s), on map " .. zone .. ": " .. (pins[id] or 0) .. " pins, " .. (ground[id] or 0) .. " ground parts%s%s%s", id, tostring(QuestName(id)),
            ok and n or "error", here, all, table.concat(list, " ", 1, math.min(#list, 4)), o and "" or ", no objectives in the data",
            QCfg().hidden[id] and ", hidden" or "", e.complete and ", complete" or "")
    end
    table.sort(out)
    return table.concat(out, "; ")
end

-- the quest data has this quest (for "only quests QuestieDB lacks"; with our
-- own data, only ones it lacks)
function ns.QDBKnowsQuest(id)
    if not Source() then return false end
    return Info(id).name ~= nil
end

-- /bfi quest <id>: why a quest does or doesn't show as available
function ns.ExplainQuest(id)
    if not Source() then return "no quest data (neither ours nor QuestieDB)" end
    local yes, why = Available(id)
    return string.format("%s (%d): %s", QuestName(id), id, yes and "available" or tostring(why))
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
                     "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "UPDATE_FACTION", "LEARNED_SPELL_IN_TAB",
                     "PLAYER_ENTERING_WORLD" }) do
    pcall(events.RegisterEvent, events, e)
end
-- what the quest log holds: each quest, done or not, and its objectives' texts
-- (QUEST_LOG_UPDATE fires for much that changes none of it; a bump throws away
-- every cache here, and rebuilding the icons on a busy map is a spike)
local function LogSignature()
    local parts = {}
    for i = 1, NumEntries() do
        local id, done
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            id = info and not info.isHeader and info.questID
            done = id and C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)
        elseif GetQuestLogTitle then
            local _, _, _, isHeader, _, d, _, qid = GetQuestLogTitle(i)
            if not isHeader then id, done = qid, d end
        end
        if id then
            parts[#parts + 1] = i .. "=" .. id .. ":" .. tostring(done)
            for j = 1, GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0 do
                local text, _, finished = GetQuestLogLeaderBoard(j, i)
                parts[#parts + 1] = tostring(text) .. tostring(finished)
            end
        end
    end
    return table.concat(parts, "|")
end

-- weapon skill-ups and every kill's reputation fire these; the quests change
-- only when a profession's rank or a reputation a quest asks for moved
local function SkillSignature()
    local parts = {}
    for i = 1, (GetNumSkillLines and GetNumSkillLines() or 0) do
        local name, header, _, rank = GetSkillLineInfo(i)
        if name and not header and SKILL_IDS[name] then parts[#parts + 1] = name .. (rank or 0) end
    end
    return table.concat(parts, "|")
end

local function RepSignature()
    local parts = {}
    for factionID, needs in pairs(repAsked) do
        local ok, name, _, _, _, _, value = pcall(GetFactionInfoByID, factionID)
        for need in pairs(needs) do
            parts[#parts + 1] = factionID .. ":" .. need .. ((ok and name and (value or 0) >= need) and "y" or "n")
        end
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

-- how often each event changed the quests (/bfi check shows it, then starts over)
ns.questChanges = {}
local sigs = { QUEST_LOG_UPDATE = LogSignature, SKILL_LINES_CHANGED = SkillSignature,
               UPDATE_FACTION = RepSignature }
local lastSig = {}
events:SetScript("OnEvent", function(_, event, a)
    if event == "QUEST_TURNED_IN" and a then
        turnedIn[a] = true
        C_Timer.After(2, Bump)  -- (once the game's own flag is in too)
    end
    -- (on login every event fires once: noted as they are, so only a real change
    -- later throws the quest caches away)
    if event == "PLAYER_ENTERING_WORLD" then
        for e, f in pairs(sigs) do
            local ok, now = pcall(f)
            lastSig[e] = ok and now or nil
        end
    end
    local sig = sigs[event]
    if sig then
        local ok, now = pcall(sig)
        if ok and now == lastSig[event] then return end
        lastSig[event] = ok and now or nil
    end
    ns.questChanges[event] = (ns.questChanges[event] or 0) + 1
    Bump()
    if event == "PLAYER_LEVEL_UP" or event == "PLAYER_ENTERING_WORLD" then playerRaceMask = nil end
end)

-- Townsfolk ----------------------------------------------------------------------

-- ids[key] = { NPC or object IDs } for each townsfolk type (Townsfolk.lua's
-- keys; profession trainers by skill ID). Our own rules over QuestieDB's NPC
-- flags, titles and vendor lists:
--   services: the NPC's flags (repair, innkeeper, flight master...)
--   trainers: trainer flag plus the title ("Warrior Trainer", "Weapon Master",
--     "Blacksmithing Trainer"; English titles)
--   vendors: what they sell, from the items' class, food type and use
--     (food, drink and ammo for your level: required level within 20 below yours)
--   mailboxes: the objects called "Mailbox"
local folk, folkState, folkLevel = {}, nil, nil

local FLAG_KEYS = {
    Repair = "REPAIR", Innkeeper = "INNKEEPER", ["Flight Master"] = "FLIGHT_MASTER",
    ["Stable Master"] = "STABLEMASTER", Auctioneer = "AUCTIONEER", Banker = "BANKER",
    Battlemaster = "BATTLEMASTER", ["Spirit Healer"] = "SPIRIT_HEALER",
}
-- profession trainers: words in their title, by skill ID
local PROFESSION_WORDS = {
    [129] = { "First Aid" }, [164] = { "Blacksmith" }, [165] = { "Leatherwork" }, [171] = { "Alchem" },
    [182] = { "Herbalis" }, [185] = { "Cook" }, [186] = { "Mining", "Miner" }, [197] = { "Tailor" },
    [202] = { "Engineer" }, [333] = { "Enchant" }, [356] = { "Fishing", "Fisherman" }, [393] = { "Skinn" },
    [755] = { "Jewelcraft" }, [773] = { "Inscription", "Scribe" },
}
ns.PROFESSION_TRAINER_IDS = PROFESSION_WORDS
-- rogue poison ingredients sold by poison vendors
local POISON_ITEMS = { [2928] = true, [2930] = true, [5173] = true, [8923] = true, [8924] = true, [5140] = true }
local folkSkip   -- filling from QuestieDB: { npcs = {}, objects = {} }, what ours already lists
local function Put(key, id)
    if folkSkip and folkSkip[key == "Mailbox" and "objects" or "npcs"][id] then return end
    local l = folk[key]
    if not l then l = {} folk[key] = l end
    l[#l + 1] = id
end

-- ours: sorted by tools/world_quests.py already; here only what's yours: your
-- class's trainers, stable masters for hunters, portal trainers for mages,
-- food and ammo for your level, NPCs of your side
local function OwnFolk(s)
    local _, classFile, classID = UnitClass("player")
    local level = UnitLevel("player")
    local function Mine(id) return Friendly(s.Npc.friendlyToFaction(id)) end
    for _, r in ipairs(s.Folk() or {}) do
        local key, ids = r[1], r[2]
        if key == "Food" or key == "Ammo" then
            for _, v in ipairs(ids) do
                for _, req in ipairs(v[2]) do
                    if req == 0 or (req <= level and req >= level - 20) then
                        if Mine(v[1]) then Put(key, v[1]) end
                        break
                    end
                end
            end
        elseif key == "Mailbox" then
            for _, id in ipairs(ids) do Put(key, id) end
        elseif type(key) == "string" and key:sub(1, 6) == "Class:" then
            if tonumber(key:sub(7)) == classID then
                for _, id in ipairs(ids) do if Mine(id) then Put("Class Trainer", id) end end
            end
        elseif (key ~= "Stable Master" or classFile == "HUNTER") and (key ~= "Portal Trainer" or classFile == "MAGE") then
            for _, id in ipairs(ids) do if Mine(id) then Put(key, id) end end
        end
    end
end

-- everything our list holds, whichever side or level it's for
local function OursListed(s)
    local out = { npcs = {}, objects = {} }
    for _, r in ipairs(s.Folk() or {}) do
        local into = r[1] == "Mailbox" and out.objects or out.npcs
        for _, v in ipairs(r[2]) do into[type(v) == "table" and v[1] or v] = true end
    end
    return out
end

-- QuestieDB's
local function BuildFolk()
    local flags = lib.Enum.npcFlags or {}
    local VENDOR, TRAINER = flags.VENDOR or 4, flags.TRAINER or 16
    local className = UnitClass("player") or ""
    local classFile = select(2, UnitClass("player"))
    local n = 0
    folk.isVendor = {}
    local general = {}  -- [npc] = true: a general supplier by title
    local trainers = {} -- [npc] = true: a trainer selling a bag isn't a general supplier

    -- NPCs by flag and title
    for _, id in ipairs(lib.Npc.GetAllIds() or {}) do
        local f = lib.Npc.npcFlags(id) or 0
        if f ~= 0 and Friendly(lib.Npc.friendlyToFaction(id)) then
            for key, flag in pairs(FLAG_KEYS) do
                if flags[flag] and HasBit(f, flags[flag]) then
                    -- stable masters are for hunters only
                    if key ~= "Stable Master" or classFile == "HUNTER" then Put(key, id) end
                end
            end
            if HasBit(f, TRAINER) then
                trainers[id] = true
                local sub = lib.Npc.subName(id) or ""
                if sub:find("Weapon Master", 1, true) then
                    Put("Weapon Master", id)
                elseif sub:find("Portal Trainer", 1, true) then
                    if classFile == "MAGE" then Put("Portal Trainer", id) end
                elseif className ~= "" and sub:find(className, 1, true) and sub:find("Trainer", 1, true) then
                    Put("Class Trainer", id)
                else
                    for skill, words in pairs(PROFESSION_WORDS) do
                        for _, w in ipairs(words) do
                            if sub:find(w, 1, true) then Put(skill, id) break end
                        end
                    end
                end
            end
            if HasBit(f, VENDOR) then
                folk.isVendor[id] = true
                -- general suppliers by their title ("General Supplies", "General Goods")
                local sub = lib.Npc.subName(id)
                if sub and sub:find("General", 1, true) then general[id] = true end
            end
        end
        n = n + 1
        if n % 200 == 0 then coroutine.yield() end
    end

    -- mailboxes
    local ok, boxes = pcall(lib.Object.IdsByName, MAILBOX or "Mailbox")
    for _, id in ipairs(ok and boxes or {}) do Put("Mailbox", id) end

    -- vendors by what they sell
    local level = UnitLevel("player")
    local vendors = { General = general }  -- [key] = { [npc] = true }
    local uses = {}          -- items to look at once loaded: [itemID] = vendor list
    local function Sells(key, list)
        local t = vendors[key]
        if not t then t = {} vendors[key] = t end
        for _, v in ipairs(list) do
            -- (Forever's Junior Mining and Skinning Trainers came out as general goods)
            if folk.isVendor[v] and not (key == "General" and trainers[v]) then t[v] = true end
        end
    end
    local function ForLevel(req) return req == 0 or (req <= level and req >= level - 20) end
    for _, id in ipairs(lib.Item.GetAllIds() or {}) do
        local list = lib.Item.vendors(id)
        if list then
            local class, foodType, req = lib.Item.class(id), lib.Item.foodType(id), lib.Item.requiredLevel(id)
            if class == 6 then
                if ForLevel(req) then Sells("Ammo", list) end
            elseif class == 1 then Sells("General", list)  -- (bags: general suppliers sell them)
            elseif class == 7 then Sells("Trade Goods", list)
            elseif class == 5 then
                if POISON_ITEMS[id] then Sells("Poisons", list) else Sells("Reagents", list) end
            elseif class == 0 then
                if POISON_ITEMS[id] then Sells("Poisons", list)
                elseif foodType and foodType >= 1 and foodType <= 8 then
                    if ForLevel(req) and foodType <= 6 then Sells("Food", list) end
                else
                    uses[id] = { list = list, req = req }  -- drink or potion? by its use, below
                end
            end
        end
        n = n + 1
        if n % 200 == 0 then coroutine.yield() end
    end

    -- drinks, potions (and food without a food type): by the item's use (the game's own spell names), once
    -- the game has the items loaded
    local DRINK, FOOD = GetSpellInfo and GetSpellInfo(430), GetSpellInfo and GetSpellInfo(433)
    local HEAL, MANA = GetSpellInfo and GetSpellInfo(439), GetSpellInfo and GetSpellInfo(437)
    local GetSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    local pending = 0
    for id in pairs(uses) do
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        pending = pending + 1
    end
    for _ = 1, 120 do  -- (wait up to ~2 s for the items to load)
        local missing = 0
        for id in pairs(uses) do
            if not (GetItemInfo and GetItemInfo(id)) then missing = missing + 1 end
        end
        if missing == 0 then break end
        coroutine.yield()
    end
    for id, u in pairs(uses) do
        local spell = GetSpell and GetSpell(id)
        if spell and spell == DRINK then
            if ForLevel(u.req) then Sells("Food", u.list) end  -- (food & drink are one type)
        elseif spell and spell == FOOD then
            if ForLevel(u.req) then Sells("Food", u.list) end
        elseif spell and (spell == HEAL or spell == MANA) then
            Sells("Potions", u.list)
        end
    end

    for key, set in pairs(vendors) do
        for v in pairs(set) do Put(key, v) end
    end
    folk.isVendor = nil
end

local function EnsureFolk()
    local level = UnitLevel("player")
    if folkState == "done" and folkLevel ~= level then folkState = nil end  -- (food, drink, ammo follow your level)
    local s = Source()
    if folkState or not (s and LoadZones()) then return folkState == "done" end
    folkState, folkLevel = "building", level
    StartJob("Townsfolk index", function()
        wipe(folk)
        if s.Folk then OwnFolk(s) else BuildFolk() end
        if s.mixed then
            folkSkip = OursListed(s)
            BuildFolk()
        end
    end, function(ok)
        folkState = "done"
        folkSkip = nil
        if not ok then
            wipe(folk)
            if s.mixed then pcall(OwnFolk, s) end   -- (QuestieDB's failed: ours still stand)
        end
        if ns.TownsfolkIndexReady then ns.TownsfolkIndexReady() end
    end)
    return false
end

-- the IDs for a townsfolk key, {} when there are none, nil while indexing
function ns.TownsfolkIds(key)
    if not EnsureFolk() then return nil end
    return folk[key] or {}
end

-- the townsfolk index is redone
function ns.ResetTownsfolkIds()
    if folkState == "done" then folkState = nil end
end

-- The player's professions, as skill IDs (English skill names; elsewhere nil:
-- every trainer then counts)
function ns.MyProfessionIDs()
    local have, known = Skills()
    if not known then return nil end
    return have
end

-- for /bfi check: what's loaded and what this map has
function ns.QuestDataInfo(mapID)
    if not Source() then
        return rawget(_G, "LibQuestieDB") and "QuestieDB too old (needs contract " .. CONTRACT .. ")" or "QuestieDB not installed"
    end
    local qdb = ns.QDB() and "QuestieDB contract " .. tostring(lib.contractVersion) .. ", " .. tostring(lib.readMode) .. " mode"
                or "no QuestieDB"
    local counts = { questie = 0, turnins = 0, spots = 0 }
    local thinned = 0
    for _, icon in ipairs(ns.QuestIcons(mapID)) do
        counts[icon.group] = (counts[icon.group] or 0) + 1
        if icon.thinned then thinned = thinned + 1 end
    end
    local folkN = 0
    for k, l in pairs(folk) do if type(l) == "table" and k ~= "isVendor" then folkN = folkN + #l end end
    local ground, parts = 0, 0
    for _, q in ipairs(ns.QuestGround(mapID, ns.db.ground and ns.db.ground.all)) do
        ground = ground + 1
        parts = parts + #q.parts
    end
    return string.format("quests from %s; %s; zones %s; givers index %s (%d maps); townsfolk %s (%d NPCs); "
        .. "this map: %d givers, %d turn-ins, %d spots (%d thinned out), ground %d quests (%d parts); Questie icons %s; hidden quests %d",
        tostring(ns.QuestSourceName()), qdb, areaToMap and "loaded" or "not loaded",
        tostring(giversState or "not started"), (function() local n = 0 for _ in pairs(givers) do n = n + 1 end return n end)(),
        tostring(folkState or "not started"), folkN,
        counts.questie, counts.turnins, counts.spots, thinned, ground, parts, ns.QuestieArt() and "yes" or "no", ns.HiddenQuestCount())
end

-- Objective progress on the game's tooltips --------------------------------------
-- Hovering a monster, an item or a thing in the world that a quest in your log
-- wants: the quest's name and that objective's count ("Kobold Vermin slain: 3/10").
-- Questie does this itself where it's loaded, so then we leave it to Questie.
-- [npcID] / [itemID] / [object name] = { { quest, target }, ... }, made afresh when the log changes
local wantNpc, wantItem, wantObj, wantVersion = {}, {}, {}, -1
local function Want(t, k, qid, name)
    if not k then return end
    local l = t[k] or {}
    t[k] = l
    for _, w in ipairs(l) do if w[1] == qid then return end end
    l[#l + 1] = { qid, name }
end
local function BuildWants()
    if wantVersion == version then return end
    wantVersion = version
    wipe(wantNpc); wipe(wantItem); wipe(wantObj)
    for qid, e in pairs(Log()) do
        if not e.complete then
            local objs = Q().objectives(qid) or {}
            for _, o in ipairs(objs[1] or {}) do Want(wantNpc, o[1], qid, o[1] and N().name(o[1])) end
            for _, o in ipairs(objs[2] or {}) do
                local name = o[1] and O().name(o[1])
                Want(wantObj, name, qid, name)
            end
            for _, o in ipairs(objs[3] or {}) do
                local item = o[1] and I().name(o[1])
                if o[1] then
                    Want(wantItem, o[1], qid, item)
                    for _, npc in ipairs(I().npcDrops(o[1]) or {}) do Want(wantNpc, npc, qid, item) end
                    for _, obj in ipairs(I().objectDrops(o[1]) or {}) do Want(wantObj, O().name(obj), qid, item) end
                end
            end
            local kc = objs[5]
            if type(kc) == "table" and type(kc[1]) == "table" and type(kc[1][1]) ~= "table" then kc = { kc } end
            for _, o in ipairs(type(kc) == "table" and kc or {}) do
                if type(o) == "table" and type(o[1]) == "table" then
                    local name = o[2] and o[2] ~= 0 and N().name(o[2]) or o[3]
                    for _, npc in ipairs(o[1]) do Want(wantNpc, npc, qid, name) end
                end
            end
        end
    end
end

local function TipsOn()
    return ns.db and ns.db.questie and ns.db.questie.unitTips ~= false and Source() and not ns.QuestieArt()
end

-- [level] in the quest's difficulty colour, its name in gold, under it its objective in white (green when done)
-- (a quest the tooltip already names, the game's own lines on newer clients
-- (Forever's, likely) or another addon's, is left to them)
local function Named(tip, name)
    local tname = tip:GetName()
    for i = 1, tip:NumLines() do
        local fs = _G[tname .. "TextLeft" .. i]
        local t = fs and fs:GetText()
        if t and t:find(name, 1, true) then return true end
    end
end
local function AddWants(tip, list)
    if not list then return end
    for _, w in ipairs(list) do
        local game = GameObjectives(w[1])
        if Named(tip, QuestName(w[1])) then game = nil end
        local g = game and MatchObjective({ name = w[2] }, game)
        if game and (g or #game == 0) then
            if ns.QuestLine then
                local line, r, g, b, title = ns.QuestLine(w[1], QuestName(w[1]))
                local level = line:match("^(%[%d+%])") or ""
                tip:AddLine(string.format("|cff%02x%02x%02x%s|r %s", r * 255, g * 255, b * 255, level, title), 1, 0.82, 0)
            else
                tip:AddLine(QuestName(w[1]), 1, 0.82, 0)
            end
            local text = g and g.text or w[2]
            if text and text ~= "" then
                local done = g and g.finished
                if done then tip:AddLine("  " .. text, 0.4, 1, 0.4) else tip:AddLine("  " .. text, 1, 1, 1) end
            end
        end
    end
    tip:Show()
end

local function NpcOf(guid)
    if not guid then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function OnUnit(tip, guid)
    if not TipsOn() then return end
    local npc = NpcOf(ns.Known(guid))  -- (secret inside a dungeon on live Forever)
    if not npc then return end
    BuildWants()
    AddWants(tip, wantNpc[npc])
end
local function OnItem(tip, id)
    if not TipsOn() or not id then return end
    BuildWants()
    AddWants(tip, wantItem[id])
end
-- live Forever has no OnTooltipSetUnit/Item: tooltips are built from data there
local DATA_TIPS = C_TooltipInfo and TooltipDataProcessor and Enum.TooltipDataType
local function ShowsUnitOrItem(tip)
    if DATA_TIPS then
        return tip:IsTooltipType(DATA_TIPS.Unit) or tip:IsTooltipType(DATA_TIPS.Item)
    end
    return tip:GetUnit() or (tip.GetItem and tip:GetItem())
end
-- a thing in the world: no unit, no item, its name on the first line
local function OnPlain(tip)
    if not TipsOn() or ShowsUnitOrItem(tip) then return end
    if tip:GetOwner() ~= UIParent then return end
    local name = GameTooltipTextLeft1 and ns.Known(GameTooltipTextLeft1:GetText())
    if not name or tip:NumLines() > 2 then return end
    BuildWants()
    AddWants(tip, wantObj[name])
end

if DATA_TIPS then
    TooltipDataProcessor.AddTooltipPostCall(DATA_TIPS.Unit, function(tip, data)
        if tip == GameTooltip then ns.Safe("quest unit tip", OnUnit, tip, data and data.guid) end
    end)
    TooltipDataProcessor.AddTooltipPostCall(DATA_TIPS.Item, function(tip, data)
        if tip == GameTooltip or tip == ItemRefTooltip then
            ns.Safe("quest item tip", OnItem, tip, data and data.id)
        end
    end)
else
    GameTooltip:HookScript("OnTooltipSetUnit", function(tip)
        local _, unit = tip:GetUnit()
        ns.Safe("quest unit tip", OnUnit, tip, unit and UnitGUID(unit))
    end)
    for _, t in ipairs({ GameTooltip, ItemRefTooltip }) do
        t:HookScript("OnTooltipSetItem", function(tip)
            local _, link = tip:GetItem()
            ns.Safe("quest item tip", OnItem, tip, link and tonumber(link:match("item:(%d+)")))
        end)
    end
end
GameTooltip:HookScript("OnShow", function(tip) ns.Safe("quest object tip", OnPlain, tip) end)

-- for /bfi check's frame cost: the icons and the ground, built afresh when the
-- quests change (cached calls cost next to nothing, so the worst is the build)
for name, label in pairs({ QuestIcons = "QuestData icons", QuestGround = "QuestData ground" }) do
    local raw = ns[name]
    ns[name] = function(...)
        local t0 = debugprofilestop()
        local r = raw(...)
        ns.CostAdd(label, t0)
        return r
    end
end
