local _, ns = ...

-- Boats where they are: the clock (out of the Lab for 1.3, 2026-11-14). Plain reckoning, no frames, no game calls:
-- tested outside the game by tools\boats_test.lua.
--
-- A boat sails one fixed round (Data\TransportPaths.lua: the game's own path, timed the game's way). What
-- nobody can know from the files is where in its round it is now. That takes one sighting, a "fix": a moment
-- we knew the boat's place. From a fix and the time gone since, the place follows.
--
-- How sure:
--   the route              certain (the game's own table)
--   the round's length     as good as certain (seven of eight match the reference to 0.01 s)
--   a fix                  as good as the sighting: riding the boat gives it to a second or two
--   a fix an hour old      good; a fix a day old: unproved (a server restart may start the rounds anew, and a
--                          round's length a hundredth off is a ship's length a day). MAX_AGE holds it short
--                          until rides have shown how long a fix lasts: every new fix says how far the old one was off.
-- Never a place without a fix: Where() gives nothing then.

local Clock = {}
ns.BoatClock = Clock

Clock.MAX_AGE = 24 * 3600   -- seconds a fix is believed (see above)
Clock.NEAR = 30             -- yards off its route within which a moving player is on that boat
Clock.OFF = 12              -- seconds a new fix may differ from the old one's forecast before the old one counts as wrong

local paths      -- [id] = { id, kind, only, period, stops, legs = { { inst, n, x = {}, y = {}, t = {} } } }

local function Build()
    paths = {}
    for _, p in ipairs(ns.TransportPaths or {}) do
        local path = { id = p[1], kind = p[2], only = p[3], period = p[4], stops = p.stops, legs = {} }
        for _, leg in ipairs(p.legs) do
            local l = { inst = leg[1], x = {}, y = {}, t = {}, n = 0 }
            for i = 2, #leg, 3 do
                l.n = l.n + 1
                l.x[l.n], l.y[l.n], l.t[l.n] = leg[i], leg[i + 1], leg[i + 2]
            end
            path.legs[#path.legs + 1] = l
        end
        paths[path.id] = path
    end
end

function Clock.Paths()
    if not paths then Build() end
    return paths
end

-- seconds from a to b going forward round the clock
local function Ahead(a, b, period)
    return (b - a) % period
end

-- Where a boat is t seconds into its round: instance, x, y (world yards), the way it heads (dx, dy, a unit
-- vector; nil lying still), and the stop's name while it lies at one. Nothing in the instant of a jump.
function Clock.At(id, t)
    local path = Clock.Paths()[id]
    if not path then return end
    t = t % path.period
    for _, l in ipairs(path.legs) do
        for i = 1, l.n - 1 do
            local span = Ahead(l.t[i], l.t[i + 1], path.period)
            local into = Ahead(l.t[i], t, path.period)
            if into <= span and span < path.period / 2 then
                local dx, dy = l.x[i + 1] - l.x[i], l.y[i + 1] - l.y[i]
                local len = (dx * dx + dy * dy) ^ 0.5
                if len < 0.5 then
                    -- lying at a stop: heading as it came in
                    local name
                    for _, s in ipairs(path.stops) do
                        if s[2] == l.inst and math.abs(s[3] - l.x[i]) < 2 and math.abs(s[4] - l.y[i]) < 2 then name = s[1] end
                    end
                    local px, py = l.x[i] - (l.x[i - 1] or l.x[i]), l.y[i] - (l.y[i - 1] or l.y[i])
                    local pl = (px * px + py * py) ^ 0.5
                    if pl < 0.5 and l.x[i + 2] then
                        px, py = l.x[i + 2] - l.x[i + 1], l.y[i + 2] - l.y[i + 1]
                        pl = (px * px + py * py) ^ 0.5
                    end
                    if pl < 0.5 then px, py, pl = 1, 0, 1 end
                    return l.inst, l.x[i], l.y[i], px / pl, py / pl, name or true
                end
                local f = span > 0 and into / span or 0
                return l.inst, l.x[i] + dx * f, l.y[i] + dy * f, dx / len, dy / len
            end
        end
    end
end

-- The round's second at which this boat is at (x, y) heading (vx, vy), or nil if that is not on its route.
-- (vx, vy): the way the player is carried; where a route passes one place twice (out and home by one
-- channel) it tells the two apart. Also gives how far off the route, yards.
function Clock.Locate(id, inst, x, y, vx, vy)
    local path = Clock.Paths()[id]
    if not path then return end
    local best, bestT, bestD
    for _, l in ipairs(path.legs) do
        if l.inst == inst then
            for i = 1, l.n - 1 do
                local ax, ay = l.x[i], l.y[i]
                local dx, dy = l.x[i + 1] - ax, l.y[i + 1] - ay
                local len2 = dx * dx + dy * dy
                local span = Ahead(l.t[i], l.t[i + 1], path.period)
                if len2 > 0.25 and span < path.period / 2 then
                    local f = ((x - ax) * dx + (y - ay) * dy) / len2
                    f = f < 0 and 0 or f > 1 and 1 or f
                    local ex, ey = ax + dx * f - x, ay + dy * f - y
                    local d = (ex * ex + ey * ey) ^ 0.5
                    if d <= Clock.NEAR then
                        local along = 1
                        if vx then
                            local vl = (vx * vx + vy * vy) ^ 0.5
                            along = vl > 0 and (vx * dx + vy * dy) / (vl * len2 ^ 0.5) or 0
                        end
                        -- going the route's way, and of those the nearest
                        if along > 0.6 then
                            local score = d - along * 5
                            if not best or score < best then
                                best, bestT, bestD = score, (l.t[i] + span * f) % path.period, d
                            end
                        end
                    end
                end
            end
        end
    end
    return bestT, bestD
end

-- Which boat carries a player moving at (x, y) by (vx, vy) yards a second: its path and the round's second.
-- Boats sail 30 yards a second at most: faster is no boat, and under 4 says too little about the heading.
function Clock.Riding(inst, x, y, vx, vy, client)
    local speed = (vx * vx + vy * vy) ^ 0.5
    if speed < 4 or speed > 34 then return end
    local bestId, bestT, bestD
    for id, path in pairs(Clock.Paths()) do
        if not path.only or path.only == client then
            local t, d = Clock.Locate(id, inst, x, y, vx, vy)
            if t and (not bestD or d < bestD) then bestId, bestT, bestD = id, t, d end
        end
    end
    return bestId, bestT, bestD
end

-- Fixes: store[id] = { at = the server's time of the sighting, t = the round's second then, n = sightings,
-- off = how many seconds the fix before this one was out (nil: there was none in date) }

-- Take a sighting in. Says how far the old fix was off, if there was one in date.
function Clock.Fix(store, id, now, t)
    local path = Clock.Paths()[id]
    if not path then return end
    local old = store[id]
    local off
    if old and now - old.at <= Clock.MAX_AGE then
        local forecast = (old.t + (now - old.at)) % path.period
        off = (t - forecast + path.period / 2) % path.period - path.period / 2
    end
    store[id] = { at = now, t = t, n = (old and old.n or 0) + 1, off = off, age = old and (now - old.at) or nil }
    return off
end

-- The round's second now, from this boat's fix; nil without one in date. Also the fix's age.
function Clock.Phase(store, id, now)
    local path = Clock.Paths()[id]
    local fix = store and store[id]
    if not (path and fix) then return end
    local age = now - fix.at
    if age < 0 or age > Clock.MAX_AGE then return end
    return (fix.t + age) % path.period, age
end

-- Where this boat is now: as At(), or nothing without a fix in date.
function Clock.Where(store, id, now)
    local t = Clock.Phase(store, id, now)
    if not t then return end
    return Clock.At(id, t)
end
