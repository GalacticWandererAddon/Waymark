local _, ns = ...

-- Where you are inside a dungeon, a guess. The game gives no position inside, but it does name the
-- monsters around you: their nameplates, your target, and who you fight (the combat log). We know
-- where each kind stands (Data\DungeonObjects.lua's DungeonParts: each floor cut into parts by its
-- spawns), so the part whose monsters you've been meeting lately is where you most likely are. A
-- kind found all over counts little; one that stands in a single part, a lot. Lit softly on the
-- dungeon map (dungeon.where), on that part's floor only. Sightings fade fast (FADE: the last few
-- fights decide; with nothing fresh the light stays where it was); a new
-- part takes over only when clearly ahead (LEAD), so the light doesn't flicker between neighbours;
-- a part far from yours in the world (not on the page: SFK's Darksoul wing is drawn on The
-- Courtyard but is next door to the Dining Hall, up a stair) counts less (NEXT).
-- Inside the part the light sits on one of its spots (spawns close together): it comes in at the
-- spot nearest where it was (you walked in from there), then drifts to the spot whose monsters you
-- meet, if they stand in few places (SPOT_SURE); between alike spots the nearer one (NEAR). Monsters
-- found all over the part don't move it: it waits for one that tells.

local GLOW = ns.MEDIA .. "DungeonGlow"
local T = ns.WhereTune or {}                               -- (tools\where_replay.lua: other values to try)
local FADE = T.FADE or 12                                  -- s: a sighting's weight halves about this often
local LEAD = T.LEAD or 1.1                                 -- a new part must score this much more to take over
local LEAST = T.LEAST or 0.6                               -- below this nothing new: the light stays where it was
local WEIGHT = { plate = T.PLATE or 2, target = T.TARGET or 2, fight = 3, died = T.DIED or 4 }
local ONE = T.ONE or 1.2                                   -- at most what one kind gives a part (a boss you killed isn't an anchor)
local NEXT = T.NEXT or 30                                  -- yd: a part this far past the edge of yours counts half (you walk, you don't jump)
local ANCHOR = T.ANCHOR or 15                             -- s: an object the soft target picked holds the light this long
local CLEAR = T.CLEAR or 1.3                              -- ...unless it's this much ahead of yours on what you met
local BEHIND = T.BEHIND or 1                               -- what a part behind the last boss killed counts (off: our way is not the way people go)
local SLACK = T.SLACK or 0.03                              -- ...how far behind it may be and still count fully
local LEARN = T.LEARN or 0.7                               -- how much a page earlier runs seldom saw counts less
local DWELL = T.DWELL or 8                                -- s: after the light changes part, it holds this long unless far outdone
local changedAt
local NEAR = T.NEAR or 0.5                                 -- a spot's score lost per picture width away
local SPOT_SURE = T.SPOT_SURE or 0.6                       -- the light moves in a part only for monsters this sure of a spot
local SPOT_FADE = T.SPOT_FADE or 4                         -- s: and for the spot, only the last fight or two count
local STEP = T.STEP or 3                                   -- floor cells the light walks each half second
local DRIFT = T.DRIFT or 0.15                              -- how far the light goes toward its spot each half second
local SPOT_R = 0.1                                         -- the light's size at most (as a part's r)
-- Under the sky or not (IsIndoors; each part knows how much of it is, p[8], tools\dungeon_marks.py):
-- out there, parts mostly under a roof count little, and the light goes out at once (SFK's Wall
-- Walk: the only place the keep is open to the sky); inside, parts all under the sky count less.
local SKY_IN = T.SKY_IN or 0                             -- inside: what a part wholly under the sky loses
local SKY_OUT = T.SKY_OUT or 0.75                          -- outside: what a part wholly under a roof loses
local SKY_SURE = 1                                         -- s: outside this long before it counts (a doorway)
local skySince                                             -- when you went under the sky (nil: under a roof)
local skyParts, out = {}, {}                               -- inst -> has parts under the sky; (Guess's open parts)

local seen = {}                                            -- name -> { t = when, w = weight }
local here, hereInst                                       -- the part guessed: { inst, floor, i, part }
local at                                                   -- where the light is: { floor, x, y }
local turnedTo                                             -- the floor the map was last turned to
local totals = {}                                          -- inst -> name -> spawns in the whole dungeon

local function Inst()
    local inInstance = IsInInstance()
    if not inInstance then return nil end
    return select(8, GetInstanceInfo())
end

local function Totals(inst)
    if totals[inst] then return totals[inst] end
    local t = {}
    for _, parts in pairs(ns.DungeonParts and ns.DungeonParts[inst] or {}) do
        for _, p in ipairs(parts) do
            for name, n in pairs(p[4]) do t[name] = (t[name] or 0) + n end
        end
    end
    totals[inst] = t
    return t
end

-- /bfi where rec: every sighting and your "I'm here" clicks, kept for tools\where_replay.lua to
-- score the guess against (WaymarkDB.whereLog: { on, ev = { { t, what, ... } }, old = { earlier runs' ev } })
local function Log(...)
    local L = WaymarkDB and WaymarkDB.whereLog
    if not (L and L.on) or #L.ev >= 30000 then return end
    L.ev[#L.ev + 1] = { GetTime(), ... }
end
local lastLogged = {}

local function Saw(name, kind)
    if not name or not hereInst then return end
    if not Totals(hereInst)[name] then return end          -- (not one of this dungeon's)
    local key = name .. kind
    if not lastLogged[key] or GetTime() - lastLogged[key] >= 1 then
        lastLogged[key] = GetTime()
        Log("s", name, kind)
    end
    local s = seen[name]
    local w = WEIGHT[kind] or 1
    if not s or GetTime() - s.t > 2 or w > s.w then seen[name] = { t = GetTime(), w = math.max(w, s and s.w or 0), a = s and s.a, f = s and s.f, k = s and s.k } end
    if kind ~= "plate" then seen[name].a = GetTime() end    -- (targeted or fought: that moves the light in a part; a plate seen through bars doesn't)
    if kind == "fight" or kind == "died" then seen[name].f = GetTime() end   -- (fought: a boss's extra weight)
end

-- Where you can walk on the page (Data\DungeonWalk.lua, tools\dungeon_walk.py): the light sits on
-- the floor, never in a wall, and goes round walls through the doorways when it moves.
local grids = {}
local function Grid(inst, floor)
    local key = inst .. ":" .. tostring(floor)
    if grids[key] ~= nil then return grids[key] end
    local rows = ns.DungeonWalk and ns.DungeonWalk[inst] and ns.DungeonWalk[inst][floor]
    local g = false
    if rows then
        g = { w = ns.DUNGEON_WALK_W, h = ns.DUNGEON_WALK_H }
        for y, row in ipairs(rows) do
            local x = 0
            for n, ch in row:gmatch("(%d*)([%.#])") do
                n = tonumber(n) or 1
                if ch == "#" then for k = x, x + n - 1 do g[(y - 1) * g.w + k] = true end end
                x = x + n
            end
        end
    end
    grids[key] = g
    return g
end

local function Cell(g, x, y)
    return math.max(0, math.min(g.w - 1, math.floor(x * g.w))), math.max(0, math.min(g.h - 1, math.floor(y * g.h)))
end

-- the floor cell nearest (x, y): its middle; the spot itself where there's no grid
local function Snap(inst, floor, x, y)
    local g = Grid(inst, floor)
    if not g then return x, y end
    local cx, cy = Cell(g, x, y)
    for r = 0, 12 do
        local best, bd
        for dy = -r, r do
            for dx = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r and g[(cy + dy) * g.w + cx + dx] and cx + dx >= 0 and cx + dx < g.w then
                    local d = dx * dx + dy * dy
                    if not bd or d < bd then best, bd = (cy + dy) * g.w + cx + dx, d end
                end
            end
        end
        if best then return (best % g.w + 0.5) / g.w, (math.floor(best / g.w) + 0.5) / g.h end
    end
    return x, y
end

-- STEP floor cells along the way from (x, y) toward (tx, ty), round walls; straight where there's no grid
-- or no way between them
local function Walk(inst, floor, x, y, tx, ty)
    local g = Grid(inst, floor)
    if not g then return x + (tx - x) * DRIFT, y + (ty - y) * DRIFT end
    local sx, sy = Cell(g, x, y)
    local ex, ey = Cell(g, tx, ty)
    local s, e = sy * g.w + sx, ey * g.w + ex
    if s == e or not g[e] then return tx, ty end
    local from, queue, head = { [s] = s }, { s }, 1
    while queue[head] do
        local c = queue[head]
        head = head + 1
        if c == e then break end
        local cx, cy = c % g.w, math.floor(c / g.w)
        for dy = -1, 1 do
            for dx = -1, 1 do
                local nx, ny = cx + dx, cy + dy
                local n = ny * g.w + nx
                if (dx ~= 0 or dy ~= 0) and nx >= 0 and nx < g.w and ny >= 0 and ny < g.h and g[n] and not from[n] then
                    from[n] = c
                    queue[#queue + 1] = n
                end
            end
        end
    end
    if not from[e] then return x + (tx - x) * DRIFT, y + (ty - y) * DRIFT end
    local path, c = {}, e
    while c ~= s do table.insert(path, 1, c) c = from[c] end
    local c2 = path[math.min(STEP, #path)]
    if c2 == e then return tx, ty end
    return (c2 % g.w + 0.5) / g.w, (math.floor(c2 / g.w) + 0.5) / g.h
end

-- an object the soft target picks (a lever, chest, door, quest pick-up: within ~10 yd): you're
-- right there. Of those with its name, the one nearest the light (SFK has three levers).
local anchor                                               -- { floor, x, y, t }
local function Object(name, npc)
    local list = hereInst and ns.DungeonObjects and ns.DungeonObjects[hereInst]
    if not (list and name) then return end
    local best, bd
    for floor, pins in pairs(list) do
        for _, p in ipairs(pins) do
            if p[4] == name and (p[1] == "npc") == (npc or false) then
                local d = at and (at[1] == floor and math.sqrt(((p[2] - at[2]) * 1.5) ^ 2 + (p[3] - at[3]) ^ 2) or 2) or 0
                if not bd or d < bd then best, bd = { floor, p[2], p[3] }, d end
            end
        end
    end
    if best then anchor = { best[1], best[2], best[3], t = GetTime() } end
end

-- how far your target is, as the game tells it inside: within 28 yd (its follow check) or not.
-- Recorded only for now (the replay can try: you're within that of one of that kind's spawns).
local lastRange = {}
local function Range()
    if not (UnitExists("target") and UnitCanAttack("player", "target")) or UnitIsDead("target") then return end
    local ok, near = pcall(CheckInteractDistance, "target", 4)
    if not ok then return end
    local name = UnitName("target")
    local key = name .. tostring(near)
    if lastRange.key == key and GetTime() - lastRange.t < 2 then return end
    lastRange.key, lastRange.t = key, GetTime()
    Log("r", name, near and 28 or -28)
end

-- a boss or rare of this dungeon (Data\DungeonEncounters.lua): never a stray, one alone tells
local bosses = {}
local function Boss(inst, name)
    local b = bosses[inst]
    if not b then
        b = {}
        for _, e in ipairs(ns.DungeonEncounters and ns.DungeonEncounters[inst] or {}) do b[e[1]] = true end
        bosses[inst] = b
    end
    return b[name]
end

-- Kills: monsters don't come back, so a part whose kind you've killed off holds no more of it, and
-- the next of that kind you meet is elsewhere (SFK: Springvale's Guardsmen killed, the next are on
-- the Wall Walk). Each kill goes to the part you're in if it has that kind left, else to the part
-- with most of it left. used["floor:i"][name] = killed there; usedAll[name] = killed in all.
local used, usedAll = {}, {}
local done                                                 -- how far along the usual way the last boss you killed stands
local function Left(floor, i, name, n)
    local u = used[floor .. ":" .. i]
    return math.max(0, n - (u and u[name] or 0))
end
local function Died(name)
    local parts = hereInst and ns.DungeonParts and ns.DungeonParts[hereInst]
    if not (parts and name and Totals(hereInst)[name]) then return end
    local key
    if here and here[4][4][name] and Left(here[2], here[3], name, here[4][4][name]) > 0 then
        key = here[2] .. ":" .. here[3]
    else
        local most = 0
        for floor, list in pairs(parts) do
            for i, p in ipairs(list) do
                local l = p[4][name] and Left(floor, i, name, p[4][name]) or 0
                if l > most then key, most = floor .. ":" .. i, l end
            end
        end
    end
    if Boss(hereInst, name) then                           -- (a boss: the run is at least this far along)
        for _, list in pairs(parts) do
            for _, p in ipairs(list) do
                if p[4][name] and p[7] and p[7] > (done or 0) then done = p[7] end
            end
        end
    end
    if not key then return end
    used[key] = used[key] or {}
    used[key][name] = (used[key][name] or 0) + 1
    usedAll[name] = (usedAll[name] or 0) + 1
    if seen[name] then seen[name].k = GetTime() end        -- (its death is no sign of elsewhere: Guess's tells)
end
local function Total(name)
    return math.max(0.5, Totals(hereInst)[name] - (usedAll[name] or 0))
end

-- What earlier runs taught (Data\DungeonWhereLearned.lua, tools\where_replay.lua): by how many of a
-- kind you've killed so far, which page you were on when you met the next. A page it was seldom on
-- counts less (LEARN), where enough runs say so.
local function Learned(inst, name, floor)
    local L = ns.DungeonWhereLearned and ns.DungeonWhereLearned[inst]
    local byk = L and L[name]
    if not byk then return 1 end
    local by = byk[math.min(12, usedAll[name] or 0)]
    if not by then return 1 end
    local all = 0
    for _, n in pairs(by) do all = all + n end
    if all < 3 then return 1 end
    return 1 - LEARN * (1 - (by[floor] or 0) / all)
end

-- How far along the run (Data\DungeonWhereLearned.lua's DungeonWhereStage): by how many monsters
-- you've killed in all, which pages earlier runs were on. A soft hint, never a rule (routes vary,
-- people go back): a page runs seldom reached by now counts a little less (STAGE), and the
-- neighbouring steps count too, so a slower or faster run isn't thrown off.
local STAGE = T.STAGE or 0.4
local STAGE_BY = 8                                         -- kills a step (tools\where_replay.lua's)
local function Stage(inst, floor)
    local S = ns.DungeonWhereStage and ns.DungeonWhereStage[inst]
    if not S then return 1 end
    local killed = 0
    for _, n in pairs(usedAll) do killed = killed + n end
    local k = math.floor(killed / STAGE_BY)
    local on, all = 0, 0
    for d = -1, 1 do
        for f, n in pairs(S[k + d] or {}) do
            local w = d == 0 and 2 or 1
            all = all + n * w
            if f == floor then on = on + n * w end
        end
    end
    if all < 6 then return 1 end
    return 1 - STAGE * (1 - on / all)
end

-- pages joined by a stair or drop (Data\DungeonWalk.lua's DungeonPageLinks, from the routes)
local function Joined(inst, a, b)
    local l = ns.DungeonPageLinks and ns.DungeonPageLinks[inst]
    for _, o in ipairs(l and l[a] or {}) do if o == b then return true end end
    return false
end

-- A part further along than yours: a nearer one along the usual way takes it instead when nothing you
-- met lately stands only in the further one, and some of it stands there (NEARER of LEAST), so the
-- light goes a part at a time and never skips to where they stand thickest (Deadmines: the bridge's
-- pirates and shipbuilders stand on the ship's deck too, in numbers; its Blackguards don't).
-- list: { { pick, score, raw } }
local NEARER = T.NEARER or 0.3
local cands = {}
local function Nearer(pick, score, list)
    local h = here and here[4][7]
    local f = pick and pick[4][7]
    if not (h and f and f > h + SLACK) then return pick end
    local now = GetTime()
    local least, lf = pick, f
    for _, c in ipairs(list) do
        local p = c[1][4]
        if p ~= here[4] and p[7] and p[7] >= h - SLACK and p[7] < lf and (c[3] or c[2]) >= LEAST * NEARER then
            local only = false
            for name, s in pairs(seen) do
                if pick[4][4][name] and not p[4][name] and s.w * 0.5 ^ ((now - s.t) / FADE) > 0.5 then only = true break end
            end
            if not only then least, lf = c[1], p[7] end
        end
    end
    return least
end

local function Guess()
    local inst = hereInst
    local parts = inst and ns.DungeonParts and ns.DungeonParts[inst]
    if not parts then here, at = nil, nil return end
    if anchor and GetTime() - anchor.t < ANCHOR and parts[anchor[1]] then
        -- (by an object: its floor's part nearest it, the light on it)
        local near, nd
        for i, p in ipairs(parts[anchor[1]]) do
            local d = ((p[1] - anchor[2]) * 1.5) ^ 2 + (p[2] - anchor[3]) ^ 2
            if not nd or d < nd then near, nd = i, d end
        end
        here = { inst, anchor[1], near, parts[anchor[1]][near] }
        local ax, ay = Snap(inst, anchor[1], anchor[2], anchor[3])
        if at and at[1] == anchor[1] then                  -- (on the page: it walks there, no jump)
            at[2], at[3] = Walk(inst, anchor[1], at[2], at[3], ax, ay)
            at.part = here
        else
            at = { anchor[1], ax, ay, part = here }
        end
        if here[2] ~= turnedTo then
            turnedTo = here[2]
            if ns.DungeonFollowFloor then ns.DungeonFollowFloor() end
        end
        return
    end
    local tot, now = Totals(inst), GetTime()
    local best, bestScore, curScore, bestRaw
    if skyParts[inst] == nil then                          -- (a dungeon with some of it under the sky)
        skyParts[inst] = false
        for _, list in pairs(parts) do
            for _, p in ipairs(list) do if (p[8] or 0) >= 0.5 then skyParts[inst] = true end end
        end
    end
    local sky = skyParts[inst] and skySince and now - skySince >= SKY_SURE
    local stepped
    local function Sky(p)
        local o = p[8] or 0
        if sky then return 1 - SKY_OUT * (1 - o) end
        return 1 - SKY_IN * o
    end
    -- (where you were holds only while what you meet there still says so: a guess gone stale
    -- doesn't keep the far side down)
    local held, heldRaw = false, 0
    if here then
        local s = 0
        for name, seenIt in pairs(seen) do
            local n = here[4][4][name]
            n = n and Left(here[2], here[3], name, n)
            if n and n > 0 then s = s + math.min(ONE, seenIt.w * 0.5 ^ ((now - seenIt.t) / FADE) * n / Total(name)) end
        end
        held, heldRaw = s >= LEAST, s
    end
    for floor, list in pairs(parts) do
        for i, p in ipairs(list) do
            local score, kinds, pack, two, tells = 0, 0, false, false, false
            for name, s in pairs(seen) do
                local n = p[4][name]
                n = n and (Boss(inst, name) and n or Left(floor, i, name, n))   -- (a boss: where it lies still tells)
                if n and n > 0 then
                    -- (a sign of its own: a kind your part hasn't, or your part is cleared of it and one
                    -- was met since the last kill. Not one standing thicker there: Deadmines' deck has
                    -- the bridge's pirates, many more of them)
                    local hn = here and here[4][4][name]
                    local sign = not hn
                    if hn and not Boss(inst, name) then
                        sign = Left(here[2], here[3], name, hn) == 0 and s.t > (s.k or -1) + 1
                    end
                    if sign and s.w * 0.5 ^ ((now - s.t) / FADE) > 0.5 then tells = true end
                    -- (one kind gives a part at most ONE; a boss you're fighting more, a dead one not)
                    local cap = (s.w < WEIGHT.died and Boss(inst, name) and s.f and now - s.f < 2 * FADE) and 3 * ONE or ONE   -- (fought, not just targeted or its plate)
                    local add = math.min(cap, s.w * 0.5 ^ ((now - s.t) / FADE) * n / (Boss(inst, name) and tot[name] or Total(name)))
                    add = add * Learned(inst, name, floor)
                    score = score + add
                    if add > 0.1 then kinds = kinds + 1 pack = pack or n >= 3 or Boss(inst, name) two = two or n >= 2 end
                end
            end
            -- (behind the last boss you killed, on the usual way: you seldom go back)
            if done and p[7] and p[7] < done - SLACK then score = score * BEHIND end
            score = score * Sky(p) * Stage(inst, floor)
            -- (in the world, not on the page: the part next door may be drawn on another page)
            local raw = score
            local w, hw = p[6], here and here[4][6]
            if held and raw < heldRaw * CLEAR and w and hw and p ~= here[4] then   -- (clearly ahead: it wins, far or not)
                local d = math.sqrt((w[1] - hw[1]) ^ 2 + (w[2] - hw[2]) ^ 2 + (w[3] - hw[3]) ^ 2) - w[4] - hw[4]
                if d > 0 then score = score / (1 + (d / NEXT) ^ 2) end
            end
            if here and here[2] == floor and here[3] == i then curScore = score end
            -- (another floor takes two kinds met there, or one that stands there in numbers:
            -- a lone one may be a stray, or summoned)
            -- (a page joined to yours by a stair: a kind with two or more there will do; another: as above)
            local ok = not here or here[2] == floor or kinds >= 2 or pack or (two and Joined(inst, here[2], floor))
                       or (sky and (p[8] or 0) >= 0.5)   -- (under the sky: where it's open is where you are)
            -- (further along the usual way: only on a sign of its own. Kills alone never move it on:
            -- a part holds more than you clear (Deadmines' first hall: its side tunnels' miners), so
            -- "most of that kind left is ahead" isn't where you are)
            if ok and not tells and here and p ~= here[4] and p[7] and here[4][7] and p[7] > here[4][7] + SLACK then ok = false end
            if ok and score > (bestScore or 0) then best, bestScore, bestRaw = { inst, floor, i, p }, score, raw end
            if ok then cands[#cands + 1] = { { inst, floor, i, p }, score, raw } end
            if sky and (p[8] or 0) >= 0.5 then out[#out + 1] = { { inst, floor, i, p }, score } end
        end
    end
    -- (just stepped out under the sky from a part under a roof: out at once, to the open part you met
    -- most in, or with nothing met yet, the one nearest where you were)
    if sky and #out > 0 and not (here and (here[4][8] or 0) >= 0.5) then
        local pick, ps, pd
        local hw = here and here[4][6]
        for _, o in ipairs(out) do
            local w = o[1][4][6]
            local d = (hw and w) and ((w[1] - hw[1]) ^ 2 + (w[2] - hw[2]) ^ 2 + (w[3] - hw[3]) ^ 2) or 0
            if not pick or o[2] > ps + 0.1 or (o[2] > ps - 0.1 and d < pd) then pick, ps, pd = o[1], o[2], d end
        end
        pick = Nearer(pick, ps, out)
        changedAt, here, stepped = now, pick, true
        best, bestScore, bestRaw = nil, nil, nil
    end
    wipe(out)
    if best and bestRaw >= LEAST then
        local b = Nearer(best, bestScore, cands)
        if b ~= best then
            for _, c in ipairs(cands) do if c[1] == b then best, bestScore, bestRaw = b, c[2], c[3] end end
        end
    end
    wipe(cands)
    if best and bestRaw >= LEAST then                      -- (enough met there, however far: a wrong guess doesn't lock it)
    -- (a new part only when clearly ahead; for DWELL s after a change, much more clearly: no back and forth)
        local lead = (changedAt and now - changedAt < DWELL) and LEAD * 1.8 or LEAD
        if not (here and curScore and curScore >= LEAST and bestScore < curScore * lead) then
            if not here or best[2] ~= here[2] or best[3] ~= here[3] then changedAt = now end
            here = best
        end
    elseif not stepped then
        return
    end
    -- the spot in it: what you've met there, less how far from the light
    local spots = here[4][5] or { { here[4][1], here[4][2], here[4][4] } }
    if not (at and at[1] == here[2]) then at = nil end
    local pick, pickScore, pickSure
    for _, s in ipairs(spots) do
        local score = 0
        for name, n in pairs(s[3]) do
            local seenIt = seen[name]
            if seenIt and seenIt.a then score = score + seenIt.w * 0.5 ^ ((now - seenIt.a) / SPOT_FADE) * n / tot[name] end
        end
        local sure = score
        if at then score = score - NEAR * math.sqrt(((s[1] - at[2]) * 1.5) ^ 2 + (s[2] - at[3]) ^ 2) end
        if not pickScore or score > pickScore then pick, pickScore, pickSure = s, score, sure end
    end
    if not at then
        at = { here[2], Snap(inst, here[2], pick[1], pick[2]) }
    elseif here ~= at.part then
        -- (a new part: in at its spot nearest the light, the way you came)
        local near, d
        for _, s in ipairs(spots) do
            local e = ((s[1] - at[2]) * 1.5) ^ 2 + (s[2] - at[3]) ^ 2
            if not d or e < d then near, d = s, e end
        end
        local nx, ny = Snap(inst, here[2], near[1], near[2])
        at[2], at[3] = Walk(inst, here[2], at[2], at[3], nx, ny)  -- (walking, no jump)
    elseif pickSure >= SPOT_SURE then                      -- (monsters found all over the part: it stays put)
        local tx, ty = Snap(inst, here[2], pick[1], pick[2])
        at[2], at[3] = Walk(inst, here[2], at[2], at[3], tx, ty)
    end
    at.part = here
    if here[2] ~= turnedTo then                            -- (a new floor: the map turns there, DungeonFollowFloor)
        turnedTo = here[2]
        if ns.DungeonFollowFloor then ns.DungeonFollowFloor() end
    end
end

-- the guess: instance, floor, and the part { x, y, r, names }; nil when there's none
function ns.DungeonWhere()
    if here then return here[1], here[2], here[4] end
end

-- The light: on a page with a walk grid, soft dots on the floor cells you could walk to from its
-- spot within LIGHT cells, fainter further off, so it lights the floor around you and stops at walls
-- (never spilling over a wall or into the next room). Without a grid, one round glow.
local LIGHT = 8                                            -- cells: how far along the floor the light reaches
local DOT = 2.4                                            -- a dot's size, in cells (they overlap into one smooth light)...
local DOT_EDGE = 1.2                                       -- ...and on a cell by a wall, small, so the light stops there
local EDGE_ALPHA = 0.85
local FEW = 15                                             -- fewer floor cells in reach than this: the round glow instead
local DOT_ALPHA = 0.7                                      -- one dot at the spot's own cell (overlapping, they add up)
local holder, glow, why
local dots, dotsUsed, dotsKey = {}, 0, nil
local function Dots(inst, floor, x, y)
    local g = Grid(inst, floor)
    if not g then return false end
    local sx, sy = Cell(g, x, y)
    local key = inst .. ":" .. tostring(floor) .. ":" .. sx .. ":" .. sy
    if key == dotsKey then return true end
    dotsKey = key
    -- (walking distance over floor cells, 8 ways)
    local s = sy * g.w + sx
    local dist, queue, head = { [s] = 0 }, { s }, 1
    while queue[head] do
        local c = queue[head]
        head = head + 1
        local cx, cy, d = c % g.w, math.floor(c / g.w), dist[c]
        if d < LIGHT then
            for dy = -1, 1 do
                for dx = -1, 1 do
                    local nx, ny = cx + dx, cy + dy
                    local n = ny * g.w + nx
                    if (dx ~= 0 or dy ~= 0) and nx >= 0 and nx < g.w and ny >= 0 and ny < g.h and g[n] then
                        local nd = d + ((dx ~= 0 and dy ~= 0) and 1.4 or 1)
                        if not dist[n] or nd < dist[n] then dist[n] = nd queue[#queue + 1] = n end
                    end
                end
            end
        end
    end
    local reach = 0
    for _, d in pairs(dist) do if d < LIGHT then reach = reach + 1 end end
    if reach < FEW then dotsKey = nil return false end   -- (hardly any floor there in the grid: the round glow)
    local cw, ch = 1002 / g.w, 668 / g.h
    dotsUsed = 0
    for c, d in pairs(dist) do
        if d < LIGHT then
            dotsUsed = dotsUsed + 1
            local dot = dots[dotsUsed]
            if not dot then
                dot = holder:CreateTexture(nil, "ARTWORK")
                dot:SetTexture(GLOW)
                dot:SetBlendMode("BLEND")                  -- (adding light vanishes on the bright paper)
                dot:SetVertexColor(1, 0.72, 0.25)
                dots[dotsUsed] = dot
            end
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", holder, "TOPLEFT", (c % g.w + 0.5) * cw, -(math.floor(c / g.w) + 0.5) * ch)
            local cx, cy = c % g.w, math.floor(c / g.w)
            local edge = not (g[c - 1] and g[c + 1] and g[c - g.w] and g[c + g.w] and g[c - g.w - 1] and g[c - g.w + 1]
                              and g[c + g.w - 1] and g[c + g.w + 1]) or cx == 0 or cx == g.w - 1
            local size = edge and DOT_EDGE or DOT
            dot:SetSize(cw * size, ch * size)
            dot:SetAlpha((edge and EDGE_ALPHA or DOT_ALPHA) * (1 - d / LIGHT) ^ 0.5)
            dot:Show()
        end
    end
    for i = dotsUsed + 1, #dots do dots[i]:Hide() end
    return true
end

local function Draw()
    local canvas, key
    if ns.DungeonInkSurface then canvas, key = ns.DungeonInkSurface() end  -- (not "a and f()": that keeps one value)
    local c = ns.db and ns.db.dungeon
    local inst, floor = (key or ""):match("^d(%d+):(%w+)$")
    inst, floor = tonumber(inst), tonumber(floor) or floor
    local show = canvas and c and c.where ~= false and here and at and here[1] == inst and here[2] == floor
                 and not (ns.DungeonPreviewing and ns.DungeonPreviewing())
    why = not canvas and "no dungeon map" or not (c and c.where ~= false) and "option off" or not here and "no guess"
          or (here[1] ~= inst or here[2] ~= floor) and ("map on " .. tostring(key)) or not show and "previewing" or nil
    if not show then
        if holder then holder:Hide() end
        return
    end
    if not holder then
        holder = CreateFrame("Frame", nil, canvas)         -- (over the art, under the found notes' ink and the pins)
        glow = holder:CreateTexture(nil, "ARTWORK")
        glow:SetTexture(GLOW)
        glow:SetBlendMode("BLEND")
        glow:SetVertexColor(1, 0.72, 0.25)
    end
    if holder:GetParent() ~= canvas then holder:SetParent(canvas) dotsKey = nil end
    holder:SetAllPoints(canvas)
    holder:SetFrameLevel(canvas:GetFrameLevel() + 1)
    holder:SetAlpha(0.8 + 0.1 * math.sin(GetTime() * 1.6))    -- (breathing a little)
    holder:Show()
    if Dots(inst, floor, at[2], at[3]) then
        glow:Hide()
        return
    end
    dotsKey = nil
    for i = 1, #dots do dots[i]:Hide() end
    local r = math.min(here[4][3], SPOT_R) * 668           -- (r is in the picture's height units, x stretched 1.5)
    glow:ClearAllPoints()
    glow:SetPoint("CENTER", canvas, "TOPLEFT", at[2] * 1002, -at[3] * 668)
    glow:SetSize(r * 2, r * 2)
    glow:SetAlpha(0.6)
    glow:Show()
end

local f = ns.TimedFrame("DungeonWhere")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
-- (live Forever forbids it to addons, and asking brings the "blocked" popup: plates and target only there)
if not ns.FOREVER then pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED") end
f:RegisterEvent("PLAYER_LOGOUT")
pcall(f.RegisterEvent, f, "PLAYER_SOFT_INTERACT_CHANGED")  -- (a chest, lever or pick-up a few steps away)
pcall(f.RegisterEvent, f, "PLAYER_SOFT_FRIEND_CHANGED")    -- (a friendly NPC ahead: recorded only, it reaches far)
for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "MINIMAP_ZONE_CHANGED" }) do
    pcall(f.RegisterEvent, f, e)                           -- (passing between a building's sections? recorded, to see if floors show)
end
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "MERCHANT_SHOW" }) do
    pcall(f.RegisterEvent, f, e)                           -- (one you talk to: you're at their side)
end
local HOSTILE_NPC = bit.bor(COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40, COMBATLOG_OBJECT_TYPE_NPC or 0x800)
local MINE = bit.bor(COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1, COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x2, COMBATLOG_OBJECT_AFFILIATION_RAID or 0x4)
f:SetScript("OnEvent", function(_, event, unit, reloading)
    if event == "PLAYER_LOGOUT" then                       -- (a /reload keeps what was met, in this dungeon)
        if WaymarkCharDB then
            WaymarkCharDB.where = hereInst and { inst = hereInst, t = GetTime(), seen = seen, used = used, usedAll = usedAll, done = done,
                floor = here and here[2], i = here and here[3], at = at and { at[2], at[3] } } or nil
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        local inst = Inst()
        local kept = WaymarkCharDB and WaymarkCharDB.where
        -- (only after a /reload: entering the dungeon again is a new run, even within minutes)
        if kept and inst and not hereInst and reloading and kept.inst == inst and GetTime() - kept.t >= 0 and GetTime() - kept.t < 600 then
            seen, used, usedAll, done = kept.seen or {}, kept.used or {}, kept.usedAll or {}, kept.done
            local p = kept.floor and ns.DungeonParts and ns.DungeonParts[inst] and ns.DungeonParts[inst][kept.floor]
            p = p and p[kept.i]
            if p then
                here = { inst, kept.floor, kept.i, p }
                if kept.at then at = { kept.floor, kept.at[1], kept.at[2], part = here } end
            end
        elseif inst ~= hereInst then
            seen, here, at, turnedTo, used, usedAll, done = {}, nil, nil, nil, {}, {}, nil
        end
        if WaymarkCharDB then WaymarkCharDB.where = nil end
        hereInst = inst
        if inst then Log("i", inst, here and here[2], here and here[3], at and at[2], at and at[3]) end
    elseif not hereInst then
        return
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "MINIMAP_ZONE_CHANGED" then
        Log("z", event, GetSubZoneText() or "", GetMinimapZoneText() or "", IsIndoors() and 1 or 0)
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        local ok, name = pcall(UnitName, "softinteract")
        local guid = ok and name and UnitGUID("softinteract")
        if name then Log("o", name, guid and guid:match("^[^-]+") or "?", guid and select(6, strsplit("-", guid)) or nil) end
        if name and guid and guid:match("^GameObject") then Object(name) end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if unit and UnitCanAttack("player", unit) then Saw(UnitName(unit), "plate") end
    elseif event == "PLAYER_SOFT_FRIEND_CHANGED" or event == "GOSSIP_SHOW" or event == "QUEST_GREETING" or event == "QUEST_DETAIL"
           or event == "QUEST_PROGRESS" or event == "MERCHANT_SHOW" then
        local u = event == "PLAYER_SOFT_FRIEND_CHANGED" and "softfriend" or "npc"
        local ok, name = pcall(UnitName, u)
        if ok and name and not UnitIsPlayer(u) then
            Log("n", name, event)
            if u == "npc" then Object(name, true) end      -- (the soft friend reaches far: only talking puts you at their side)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") and UnitCanAttack("player", "target") then
            -- (a target past 28 yd says which part, not where you are: you don't go there yet)
            local ok, near = pcall(CheckInteractDistance, "target", 4)
            Saw(UnitName("target"), (ok and not near) and "plate" or "target")
            Range()
        end
    else
        local _, sub, _, _, srcName, srcFlags, _, _, dstName, dstFlags = CombatLogGetCurrentEventInfo()
        -- (only fights with you, your pet or your group: the log reaches far, and monsters
        -- fighting or buffing each other a hall away aren't where you are)
        local srcMine = bit.band(srcFlags or 0, MINE) ~= 0
        local dstMine = bit.band(dstFlags or 0, MINE) ~= 0
        if bit.band(srcFlags or 0, HOSTILE_NPC) == HOSTILE_NPC and dstMine then Saw(srcName, "fight") end
        if bit.band(dstFlags or 0, HOSTILE_NPC) == HOSTILE_NPC then
            if sub == "UNIT_DIED" then Saw(dstName, "died") elseif srcMine then Saw(dstName, "fight") end
        end
        if sub == "UNIT_DIED" and ns.DungeonUnitDied then ns.DungeonUnitDied(dstName) end  -- (a rare's X: no encounter ends for it)
        if sub == "UNIT_DIED" and bit.band(dstFlags or 0, HOSTILE_NPC) == HOSTILE_NPC then
            Died(dstName)
            Log("k", dstName)
        end
    end
end)

local ticks, wasInside = 0, nil
C_Timer.NewTicker(0.5, ns.Timed("DungeonWhere tick", function()
    ticks = ticks + 1
    if hereInst and ticks % 4 == 0 then Range() end
    if hereInst then                                       -- (inside or under the sky: recorded when it changes)
        local inside = IsIndoors() and 1 or 0
        if inside ~= wasInside then wasInside = inside Log("x", inside) end
        if inside == 1 then skySince = nil elseif not skySince then skySince = GetTime() end
    end
    if hereInst and ticks % 2 == 0 and C_NamePlate and C_NamePlate.GetNamePlates then
        -- (a plate still up: in sight and within its ~20 yd, so still counts; plates show no further, nor through walls)
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local u = plate.namePlateUnitToken
            if u and UnitCanAttack("player", u) and not UnitIsDead(u) then Saw(UnitName(u), "plate") end
        end
    end
    if hereInst then Guess() end
    Draw()
end))

-- for /bfi check (Check.lua): the guess and what it rests on
function ns.DungeonWhereInfo()
    if not hereInst then return "not inside" end
    local names = {}
    for name, s in pairs(seen) do names[#names + 1] = string.format("%s (%d, %ds ago)", name, s.w, GetTime() - s.t) end
    table.sort(names)
    local where = here and string.format("floor %s part %d at %.2f, %.2f, lit at %.2f, %.2f", tostring(here[2]), here[3], here[4][1], here[4][2],
                                         at and at[2] or 0, at and at[3] or 0) or "no guess"
    local lit = holder and holder:IsVisible() and (glow:IsShown() and string.format("glow shown (%.0f px)", glow:GetWidth())
                or string.format("light on the floor (%d dots)", dotsUsed)) or ("light hidden: " .. (why or "?"))
    return string.format("instance %s: %s; %s; seen: %s", tostring(hereInst), where, lit, #names > 0 and table.concat(names, ", ") or "none")
end

-- for the replay (tools\where_replay.lua): a sighting as if from the game
ns.DungeonWhereSaw = function(name, kind) Saw(name, kind) end
ns.DungeonWhereObject = function(name, npc) Object(name, npc) end
ns.DungeonWhereDied = function(name) Died(name) end

function ns.DungeonWhereRecording()
    local L = WaymarkDB and WaymarkDB.whereLog
    return L and L.on or false
end

function ns.DungeonWhereRecord()
    if not WaymarkDB then return end
    local L = WaymarkDB.whereLog
    if L and L.on then
        L.on = false
        ns.Log(string.format("where: recording stopped, %d events kept. /reload, then: luajit tools/where_replay.lua", #L.ev))
    else
        local old = L and L.old or {}                      -- (the earlier runs kept, the last 10: a new one never wipes them)
        if L and L.ev and #L.ev > 0 then table.insert(old, 1, L.ev) end
        while #old > 10 do table.remove(old) end
        WaymarkDB.whereLog = { on = true, ev = {}, old = old }
        if hereInst then Log("i", hereInst, here and here[2], here and here[3], at and at[2], at and at[3]) end
        ns.Log("where: recording. Click the dungeon map where you really are, now and then (a click marks, it doesn't open the book). /waymark where rec again to stop.")
    end
end

-- a click on the dungeon map while recording: where you really are, beside what the guess said
function ns.DungeonWhereMark(inst, floor, x, y)
    Log("m", inst, floor, x, y, here and here[2], here and here[3], at and at[2], at and at[3])
    local said = not here and "no guess" or here[2] ~= floor and ("floor " .. tostring(here[2]))
                 or string.format("%.2f off", math.sqrt(((at[2] - x) * 1.5) ^ 2 + (at[3] - y) ^ 2))
    ns.Log(string.format("where: marked %.2f, %.2f (floor %s); the guess: %s", x, y, tostring(floor), said))
end

-- where the light is (the replay scores it): floor, x, y on the picture
function ns.DungeonWhereLit()
    if here and at then return at[1], at[2], at[3] end
end
