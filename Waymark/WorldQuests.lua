local _, ns = ...

-- Our own quest data (Data\WorldQuests.lua, from tools\world_quests.py) dressed as
-- the part of LibQuestieDB's API that QuestData.lua reads, so every quest feature
-- (givers, turn-ins, objective spots, the tracker, the quest window) runs on it
-- unchanged. QuestData picks this or QuestieDB by questie.source.
--
--   ns.OwnQuestDB()    the stand-in, or nil (no data)
--
-- Spawns are kept as world yards and put on the zone map with this client's own
-- zone box (Era's Mulgore map is cut differently from Forever's), keyed by the
-- zone's area ID as QuestieDB keys them, 0-100.

local D = ns.WorldQuestData
-- Forever's new quests (Data\ForeverQuests.lua, by hand) join the generated rows, never over one
if D and ns.FOREVER and ns.ForeverQuestData then
    for _, kind in ipairs({ "quests", "npcs", "items", "bossloot" }) do
        for id, row in pairs(ns.ForeverQuestData[kind] or {}) do
            if not D[kind][id] then D[kind][id] = row end
        end
    end
    -- (a classic quest Forever gives otherwise: those fields of its row replaced)
    for id, fields in pairs(ns.ForeverQuestData.fix or {}) do
        local row = D.quests[id]
        if row then for i, v in pairs(fields) do row[i] = v end end
    end
    -- (new drops on a classic boss, after the ones with chances: a row's chances stay in step)
    for instance, bosses in pairs(ns.ForeverQuestData.lootAdded or {}) do
        D.bossloot[instance] = D.bossloot[instance] or {}
        for boss, items in pairs(bosses) do
            local row
            for _, r in ipairs(D.bossloot[instance]) do
                if r[1] == boss then row = r end
            end
            if not row then
                row = { boss, {}, {} }  -- (a boss the Classic data had no drops for)
                table.insert(D.bossloot[instance], row)
            end
            for _, item in ipairs(items) do row[2][#row[2] + 1] = item end
        end
    end
end
local B64 = {}
do
    local s = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #s do B64[s:byte(i)] = i - 1 end
end
local OFFSET = 20000

-- zone index (0-based, as in the spawn strings) -> { areaID, minX, minY, maxX, maxY, u0, v0, u1, v1 }
local zones, cities
-- the capitals: the tool files a spawn under the zone whose outline holds it, and the capitals other
-- than Stormwind have no outline, so Ironforge's innkeeper was Dun Morogh's. A spot on a capital's
-- map goes on the capital's.
local CITY = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
local function Zones()
    if zones then return zones end
    zones, cities = {}, {}
    for i, z in ipairs(D.zones) do
        local b = (not ns.FOREVER and z[5]) or z[4]
        zones[i - 1] = { z[2], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], z[3] }
        if CITY[z[1]] then cities[#cities + 1] = zones[i - 1] end
    end
    return zones
end

-- world yards -> 0-1 on zone z's map
local function OnZone(z, X, Y)
    return z[6] + (z[5] - Y) / (z[5] - z[3]) * (z[8] - z[6]), z[7] + (z[4] - X) / (z[4] - z[2]) * (z[9] - z[7])
end

local function Num3(s, i)
    local a, b, c = s:byte(i, i + 2)
    return B64[a] * 4096 + B64[b] * 64 + B64[c] - OFFSET
end

-- "zXXXYYY..." -> { [areaID] = { { x, y }, ... } } (cached per string)
local cache = {}
local function Spawns(s)
    if not s then return nil end
    local t = cache[s]
    if t then return t end
    t = {}
    local Z = Zones()
    for i = 1, #s - 6, 7 do
        local z = Z[B64[s:byte(i)]]
        if z then
            local X, Y = Num3(s, i + 1), Num3(s, i + 4)
            local x, y = OnZone(z, X, Y)
            for _, c in ipairs(cities) do
                if c ~= z and c[10] == z[10] then
                    local cx, cy = OnZone(c, X, Y)
                    if cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then z, x, y = c, cx, cy break end
                end
            end
            if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                local l = t[z[1]]
                if not l then l = {} t[z[1]] = l end
                l[#l + 1] = { x * 100, y * 100 }
            end
        end
    end
    cache[s] = t
    return t
end

-- a path ("z" + XXXYYY per point, all on zone z's map) -> areaID, { { x, y } } 0-100
local function Path(s)
    if not s then return nil end
    local z = Zones()[B64[s:byte(1)]]
    if not z then return nil end
    local out = {}
    for i = 2, #s - 5, 6 do
        local X, Y = Num3(s, i), Num3(s, i + 3)
        out[#out + 1] = { (z[6] + (z[5] - Y) / (z[5] - z[3]) * (z[8] - z[6])) * 100,
                          (z[7] + (z[4] - X) / (z[4] - z[2]) * (z[9] - z[7])) * 100 }
    end
    return z[1], out
end

local function Field(tbl, i)
    return function(id)
        local r = tbl[id]
        return r and r[i]
    end
end

-- Quest fields by LibQuestieDB's names (see Data\WorldQuests.lua's header)
local QUEST_FIELD = {
    name = 1, questLevel = 2, requiredLevel = 3, requiredRaces = 4, requiredClasses = 5, zoneOrSort = 6,
    specialFlags = 7, nextQuestInChain = 8, preQuestSingle = 9, preQuestGroup = 10, parentQuest = 11,
    exclusiveTo = 12, requiredSkill = 13, requiredMinRep = 14, requiredMaxRep = 15,
    questType = 22, sourceItemId = 23,   -- (questType: ours only, the game's quest type)
}

-- a quest text with the game's fill-ins: $N your name, $R race, $C class,
-- $Gmale:female; by your sex
local function Fill(t)
    if not t or not t:find("$", 1, true) then return t end
    local female = UnitSex and UnitSex("player") == 3
    t = t:gsub("%$[Gg]%s*([^:;]*):([^;]*);", function(m, f) return female and f or m end)
    return (t:gsub("%$([NnRrCc])", function(k)
        k = k:upper()
        if k == "N" then return UnitName("player") or "" end
        if k == "R" then return UnitRace("player") or "" end
        return UnitClass("player") or ""
    end))
end

local own
function ns.OwnQuestDB()
    if own ~= nil then return own or nil end
    if not (D and D.quests) then own = false return nil end
    local Q, N, O, I = D.quests, D.npcs, D.objects, D.items
    local ids
    local zoneDB = { private = { areaIdToUiMapId = {}, subZoneToParentZone = {}, dungeons = {} } }
    for _, z in ipairs(D.zones) do zoneDB.private.areaIdToUiMapId[z[2]] = z[1] end
    own = {
        contractVersion = "own", readMode = "Waymark's own",
        Enum = {
            -- (RequiredRaces / RequiredClasses bits, as the game's)
            raceMaskById = { 1, 2, 4, 8, 16, 32, 64, 128 },
            classKeys = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64,
                          MAGE = 128, WARLOCK = 256, DRUID = 1024 },
            npcFlags = {},
        },
        -- rares and treasure chests (Wilds.lua): the data's rows, and their decoders
        Wilds = { rares = D.rares or {}, chests = D.chests or {}, bossLoot = D.bossloot or {}, Spawns = Spawns, Path = Path },
        -- townsfolk: { { key, ids } } (QuestData's OwnFolk)
        Folk = function() return D.folk end,
        Support = {
            Get = function(name)
                if name == "ZoneDB" then return zoneDB end
                if name == "QuestXP" then
                    -- (as QuestieDB's: [questID] = { level, full XP })
                    local db = {}
                    for id, r in pairs(Q) do
                        if r[20] then db[id] = { r[2], r[20] } end
                    end
                    return { db = db }
                end
            end,
        },
        Quest = {
            GetAllIds = function()
                if not ids then
                    ids = {}
                    for id in pairs(Q) do ids[#ids + 1] = id end
                    table.sort(ids)
                end
                return ids
            end,
            GetAll = function(id, keys)
                local r = Q[id]
                if not r then return nil end
                local out = {}
                for i, k in ipairs(keys) do
                    local f = QUEST_FIELD[k]
                    out[i] = f and r[f] or nil
                end
                return out
            end,
            startedBy = Field(Q, 16),
            finishedBy = Field(Q, 17),
            objectives = Field(Q, 18),
            rewards = Field(Q, 24),     -- (ours only: { choice, fixed, copper })
            objectivesText = function(id) local r = Q[id] return r and Fill(r[19]) end,
            -- an exploration spot: { text, { [areaID] = { { x, y } } } }
            triggerEnd = function(id)
                local t = Q[id] and Q[id][21]
                return t and { Fill(t[1]), Spawns(t[2]) }
            end,
            extraObjectives = function() return nil end,
            reputationReward = function() return nil end,
            breadcrumbs = function() return nil end,
        },
        Npc = {
            name = Field(N, 1),
            subName = Field(N, 2),
            friendlyToFaction = Field(N, 3),
            spawns = function(id) local r = N[id] return r and Spawns(r[4]) end,
            waypoints = function() return nil end,
        },
        Object = {
            name = Field(O, 1),
            spawns = function(id) local r = O[id] return r and Spawns(r[2]) end,
        },
        Item = {
            name = Field(I, 1),
            npcDrops = Field(I, 2),
            objectDrops = Field(I, 3),
            npcDropChances = Field(I, 4),      -- (ours only: % chance, in npcDrops' order)
            objectDropChances = Field(I, 5),
        },
    }
    return own
end
