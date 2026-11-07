local _, ns = ...

-- Quest ground: where the monsters, drops and things your quests ask for are,
-- drawn as ground on the zone map rather than pins (ns.QuestGround, QuestData.lua;
-- mock-up mockups\world-quests.html). Settings ns.db.ground:
--   shown, alpha; all: also the quests you could take from givers on this map;
--   look: "haze" (soft ground), "ink" (an inked ring, faintly filled; quests you
--   could take: a dotted ring) or "dots" (a dot per spawn); quiet: see Quiet below;
--   color: coloured (colorBy
--   "quest": each its own; "type": by what it asks, TYPE_COLORS); drops: the tooltip says
--   what drops the item.
-- The spawns are summed on a grid over the map (each reaching REACH cells); the
-- haze lays a soft blob on every cell over EDGE, the rim follows EDGE through
-- the grid (marching squares). Hovering the map over ground names the monster
-- or thing and its quest; the layer itself never takes the mouse.

local MEDIA = ns.MEDIA
local BLOB = MEDIA .. "DungeonGlow"   -- (soft round, white)
local BRUSH = MEDIA .. "InkRim"     -- (opaque core, streaks in shade not alpha: joins overlap unseen)
local DOT = MEDIA .. "InkDot"
-- the dots' art in three sizes (tools/ground_dot_art.py), picked by the pixels it's drawn at (Tier)
local ART = { core = { MEDIA .. "GroundDot", MEDIA .. "GroundDotBig", MEDIA .. "GroundDotHuge" },
              rim = { MEDIA .. "GroundDotRim", MEDIA .. "GroundDotRimBig", MEDIA .. "GroundDotRimHuge" } }
local COLS, ROWS = 96, 64             -- the grid over the map (square cells on a zone's 3:2)
local REACH = 2.2                     -- cells a spawn's ground reaches
local EDGE = 0.35                     -- the field's value at the ground's edge
local PLAIN = { 0.62, 0.2, 0.1 }      -- one colour for every quest (color off)
-- a colour per quest (color on): the quests on a map take these in turn, by quest
-- ID, so neighbours never share a shade; all dark enough to stand out on
-- parchment and sand (no yellow or tan)
local PALETTE = {
    { 0.80, 0.20, 0.12 }, { 0.15, 0.42, 0.80 }, { 0.16, 0.58, 0.20 }, { 0.62, 0.20, 0.66 },
    { 0.05, 0.56, 0.58 }, { 0.82, 0.38, 0.05 }, { 0.30, 0.30, 0.78 }, { 0.78, 0.12, 0.42 },
    { 0.38, 0.52, 0.10 }, { 0.42, 0.24, 0.12 },
}
-- colorBy "type": a colour per kind of quest (ns.QuestKind: what it asks, in a word),
-- from the same dark set; slay keeps the deep red the first quest on a map had
local TYPE_COLORS = {
    Slay = PALETTE[1], Gather = PALETTE[3], Use = PALETTE[2], Explore = PALETTE[4],
    Escort = PALETTE[5], Deliver = PALETTE[10], Speak = PALETTE[10],
}
-- a kind's colour for the dark tooltips (lightened); nil: a kind without one
function ns.QuestTypeColor(word)
    local c = TYPE_COLORS[word or ""]
    if not c then return nil end
    return c[1] * 0.7 + 0.3, c[2] * 0.7 + 0.3, c[3] * 0.7 + 0.3
end
local HOVER = 0.022                  -- how near the cursor a spawn counts (map heights)

-- (one look now, spawn dots: haze and the ink rim are retired, the user, 2026-11-07. Their code stays
-- for now, unreached; a saved look of theirs becomes dots here)
local function Cfg()
    local c = ns.db.ground
    if c and c.look ~= "dots" then c.look = "dots" end
    if c and c.arrows ~= false then c.arrows = false end   -- (arrows to lone spots retired, the user, 2026-11-07)
    if c and c.all then c.all = false end                  -- (and quests you could take: givers' pins say that)
    return c
end

local host, map
local glow, fade   -- the lit quests' gold, on its own frame over the ground (Light); its fade-in, 0-1
local pool = { blobs = {}, lines = {}, dots = {}, nb = 0, nl = 0, nd = 0 }
local drawn = {}   -- { x, y, quest, part } for the hover
-- what each quest drew, for lighting it up without a redraw (Light below):
-- groups[questID] = { tex = { { texture, kind "b"/"l"/"d", r, g, b, a, size, x1, y1, x2, y2 } }, sh, cw, th, col }
-- (a quest whose ground another drew shares that one's group)
local groups, cur = {}, nil
local arrowsAt = {}   -- (Arrows, by Draw)

-- Rings and dots are drawn in the map's own units, so they'd grow with it, 8x at the
-- closest zoom (the user: huge). This thins them, leaving them a little bolder close up.
local function ZoomThin()
    local sc = map and map.ScrollContainer
    if not (sc and sc.zoomLevels) then return 1 end   -- (none yet: GetScaleForMinZoom errors)
    local lo, s = sc:GetScaleForMinZoom(), sc:GetCanvasScale()
    if not (lo and s and lo > 0 and s > lo) then return 1 end
    return (lo / s) ^ 0.75
end
local BUDGET = 4   -- ms of drawing a frame: a busy map (Un'Goro, every quest) is laid over a few frames
local t0 = 0

-- inside the drawing job: hand the frame back once this one's budget is spent
local function Pause()
    if debugprofilestop() - t0 > BUDGET and coroutine.running() then
        coroutine.yield()
        t0 = debugprofilestop()
    end
end

local function Take(kind, make)
    local n = "n" .. kind:sub(1, 1)
    pool[n] = pool[n] + 1
    local t = pool[kind][pool[n]]
    if not t then
        t = make()
        pool[kind][pool[n]] = t
    end
    return t
end

local function Clear()
    for _, kind in ipairs({ "blobs", "lines", "dots" }) do
        for _, t in ipairs(pool[kind]) do t:Hide() end
    end
    pool.nb, pool.nl, pool.nd = 0, 0, 0
    wipe(drawn)
    wipe(groups)
    wipe(arrowsAt)
end

local function Blob(x, y, size, r, g, b, a)
    local t = Take("blobs", function()
        local t = host:CreateTexture(nil, "ARTWORK")
        t:SetTexture(BLOB)
        return t
    end)
    t:SetVertexColor(r, g, b, a)
    t:SetSize(size, size)
    t:ClearAllPoints()
    t:SetPoint("CENTER", host, "TOPLEFT", x, -y)
    t:Show()
    if cur then cur[#cur + 1] = { t, "b", r, g, b, a, size, x, y } end
end

local function Segment(x1, y1, x2, y2, th, r, g, b, a, e1, e2, over)
    local l = Take("lines", function()
        local l = host:CreateLine(nil, "ARTWORK", nil, 2)
        l:SetTexture(BRUSH)
        return l
    end)
    l:SetDrawLayer("ARTWORK", over and 3 or 2)   -- (over: an X's colour on its own dark edge)
    l:SetVertexColor(r, g, b, a)
    l:SetThickness(th * ZoomThin())
    -- a piece runs past its ends only as far as its bend needs (e1, e2 px), so
    -- the joins don't notch, nor overlap into darker dots
    local dx, dy = x2 - x1, y2 - y1
    local d = math.sqrt(dx * dx + dy * dy)
    local ux, uy = 0, 0
    if d > 0 then ux, uy = dx / d, dy / d end
    e1, e2 = e1 or 0, e2 or 0
    l:SetStartPoint("TOPLEFT", host, x1 - ux * e1, -(y1 - uy * e1))
    l:SetEndPoint("TOPLEFT", host, x2 + ux * e2, -(y2 + uy * e2))
    l:Show()
    if cur then cur[#cur + 1] = { l, "l", r, g, b, a, th } end
end

-- which art for a dot this size on the canvas: near the pixels it covers, so it's neither skipped nor soft
local function Tier(size)
    local _, h = 0, 1080
    if GetPhysicalScreenSize then _, h = GetPhysicalScreenSize() end
    local px = size * ZoomThin() * host:GetEffectiveScale() * h / 768
    return px <= 12 and 1 or px <= 26 and 2 or 3
end

local function Dot(x, y, size, r, g, b, a, under, art)
    local t = Take("dots", function() return host:CreateTexture(nil, "ARTWORK", nil, 1) end)
    local tier = art and Tier(size)
    t:SetTexture(art and ART[art][tier] or DOT)
    -- (dabs differ: mirrored across the light, which stays upper left; a dot and its rim together,
    -- so the ring round it stays even)
    if art and math.floor(x * 7 + y * 13) % 2 == 0 then
        t:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
    else
        t:SetTexCoord(0, 1, 0, 1)
    end
    t:SetDrawLayer("ARTWORK", under and 0 or 1)
    t:SetVertexColor(r, g, b, a)
    t:SetSize(size * ZoomThin(), size * ZoomThin())
    t:ClearAllPoints()
    t:SetPoint("CENTER", host, "TOPLEFT", x, -y)
    t:Show()
    if cur then cur[#cur + 1] = { t, "d", r, g, b, a, size, x, y, under, art, tier } end
end

-- a quest's dot: its colour on a thin rim, painted more than printed: the colour part way to old
-- parchment, so it's pigment rather than a pure hue
local AGE, PAPER = 0.2, { 0.72, 0.62, 0.45 }
local function Mark(x, y, size, r, g, b, a)
    Dot(x, y, size * 1.58, 1, 1, 1, a, true, "rim")   -- (the pewter is 80% of its art: 1.26 of the dot)
    Dot(x, y, size, r + (PAPER[1] - r) * AGE, g + (PAPER[2] - g) * AGE, b + (PAPER[3] - b) * AGE, a, false, "core")
end

-- the summed reach of a quest's spawns: f[row * COLS + col], cell centres
local function Field(q)
    local f = {}
    local r2 = REACH * REACH
    local span = math.ceil(REACH)
    for _, part in ipairs(q.parts) do
        for _, p in ipairs(part.points) do
            Pause()   -- (a quest with hundreds of spawns: Un'Goro's crystals)
            local cx, cy = p[1] * COLS - 0.5, p[2] * ROWS - 0.5
            for row = math.max(0, math.floor(cy) - span), math.min(ROWS - 1, math.ceil(cy) + span) do
                for col = math.max(0, math.floor(cx) - span), math.min(COLS - 1, math.ceil(cx) + span) do
                    local dx, dy = col - cx, row - cy
                    local d = dx * dx + dy * dy
                    if d < r2 then
                        local k = row * COLS + col
                        f[k] = (f[k] or 0) + (1 - d / r2)
                    end
                end
            end
        end
    end
    return f
end

-- one soft blob per 2x2 cells (the strongest of the four): a quarter of the
-- textures a blob per cell took, which the map redraws every frame
local function Haze(f, cw, r, g, b, a)
    local blocks = {}
    for k, v in pairs(f) do
        local col, row = k % COLS, math.floor(k / COLS)
        local bk = math.floor(row / 2) * COLS + math.floor(col / 2)
        if v > (blocks[bk] or 0) then blocks[bk] = v end
    end
    for bk, v in pairs(blocks) do
        Pause()
        if v >= EDGE * 0.6 then
            local col, row = (bk % COLS) * 2, math.floor(bk / COLS) * 2
            local s = v >= EDGE and math.min(1, 0.6 + (v - EDGE)) or (v - EDGE * 0.6) / (EDGE * 0.4) * 0.45
            Blob((col + 1) * cw, (row + 1) * cw, cw * 4.4, r, g, b, a * 0.42 * s)
        end
    end
end

-- a closed line round a small gap in the ground (a pond, an island no spawn
-- reaches): a ring inside the ring that only looked like a second spot (the user's
-- shot, Grove of the Ancients). Under HOLE cells² and the field low at its middle.
local HOLE = 8
local function SmallHole(line, V, edge)
    local a, cx, cy, n = 0, 0, 0, #line
    for i = 1, n do
        local p, q = line[i], line[i % n + 1]
        a = a + p[1] * q[2] - q[1] * p[2]
        cx, cy = cx + p[1], cy + p[2]
    end
    if math.abs(a) / 2 >= HOLE then return false end
    return V(math.floor(cx / n + 0.5), math.floor(cy / n + 0.5)) < edge
end

-- the rim's outlines: where the field crosses edge (EDGE unless given), between cell centres
-- (marching squares), the pieces joined into lines: { { {x, y}, ... }, closed }
-- in cells. Each crossing sits on a grid edge, its key shared by the two pieces
-- meeting there.
local function Outlines(f, edge)
    local EDGE = edge or EDGE   -- (the haze's gilt traces its fainter edge)
    local function V(col, row) return f[row * COLS + col] or 0 end
    local function Cut(v1, v2) return (EDGE - v1) / (v2 - v1) end
    local at, links = {}, {}
    local function Link(k1, p1, k2, p2)
        at[k1], at[k2] = p1, p2
        links[k1] = links[k1] or {}
        links[k2] = links[k2] or {}
        table.insert(links[k1], k2)
        table.insert(links[k2], k1)
    end
    for row = 0, ROWS - 2 do
        Pause()
        for col = 0, COLS - 2 do
            local tl, tr, br, bl = V(col, row), V(col + 1, row), V(col + 1, row + 1), V(col, row + 1)
            local n = (tl >= EDGE and 8 or 0) + (tr >= EDGE and 4 or 0) + (br >= EDGE and 2 or 0) + (bl >= EDGE and 1 or 0)
            if n ~= 0 and n ~= 15 then
                -- the crossings on each side that has one: key, point
                local pts = {}
                local base = row * COLS + col
                if (tl >= EDGE) ~= (tr >= EDGE) then pts[#pts + 1] = { base * 2, { col + Cut(tl, tr), row } } end
                if (tr >= EDGE) ~= (br >= EDGE) then pts[#pts + 1] = { (base + 1) * 2 + 1, { col + 1, row + Cut(tr, br) } } end
                if (bl >= EDGE) ~= (br >= EDGE) then pts[#pts + 1] = { (base + COLS) * 2, { col + Cut(bl, br), row + 1 } } end
                if (tl >= EDGE) ~= (bl >= EDGE) then pts[#pts + 1] = { base * 2 + 1, { col, row + Cut(tl, bl) } } end
                for i = 1, #pts - 1, 2 do Link(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]) end
            end
        end
    end
    local used, lines = {}, {}
    local function Walk(start)
        local line, k, prev = { at[start] }, start, nil
        used[start] = true
        while true do
            local nxt
            for _, o in ipairs(links[k]) do
                if o ~= prev and not used[o] then nxt = o break end
            end
            if not nxt then
                for _, o in ipairs(links[k]) do
                    if o == start and o ~= prev and #line > 2 then return line, true end
                end
                return line, false
            end
            used[nxt] = true
            line[#line + 1] = at[nxt]
            prev, k = k, nxt
        end
    end
    for k, l in pairs(links) do      -- (open lines first, from an end)
        if #l == 1 and not used[k] then lines[#lines + 1] = { Walk(k) } end
    end
    for k in pairs(links) do
        if not used[k] then
            local line, closed = Walk(k)
            if not (closed and SmallHole(line, V, EDGE)) then lines[#lines + 1] = { line, closed } end
        end
    end
    return lines
end

-- a steady random per quest and line (the same every redraw)
local function Rand(seed)
    local s = seed % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function()
        s = (s * 16807) % 2147483647
        return (s - 1) / 2147483646
    end
end

-- (mock-up mockups\quest-rings.html) the rings are what the map redraws every
-- frame while you pan: Un'Goro with every quest took ~2000 pieces, one per grid
-- crossing. Now each ring is smoothed, then a straight run is one piece: about half.
local TOL, MAXLEN = 0.08, 3      -- cells: how far a run may stray from its piece; the longest piece
local DOT_STEP = 2.1              -- cells between the dots of a quest you could take

-- a line smoothed (neighbours' average, three times): { {x, y}, ... } in cells
local function Smooth(pts, closed)
    local n = #pts
    for _ = 1, 3 do
        local s = {}
        for i = 1, n do
            local p = pts[i]
            local q0 = pts[i - 1] or (closed and pts[n]) or p
            local q1 = pts[i + 1] or (closed and pts[1]) or p
            s[i] = { (q0[1] + 2 * p[1] + q1[1]) / 4, (q0[2] + 2 * p[2] + q1[2]) / 4 }
        end
        pts = s
    end
    if closed then pts[n + 1] = pts[1] end
    return pts
end

-- keep a point only where the line bends: the run since the last kept point
-- stays within TOL of the straight piece, and no piece is longer than MAXLEN
local function Simplify(path, tol, maxLen)
    tol, maxLen = tol or TOL, maxLen or MAXLEN
    local out, a = { path[1] }, 1
    for i = 3, #path do
        local A, B = path[a], path[i]
        local dx, dy = B[1] - A[1], B[2] - A[2]
        local L = math.sqrt(dx * dx + dy * dy)
        local ok = L <= maxLen
        for j = a + 1, i - 1 do
            if not ok then break end
            local P = path[j]
            if L > 0 and math.abs((P[1] - A[1]) * dy - (P[2] - A[2]) * dx) / L > tol then ok = false end
        end
        if not ok then
            out[#out + 1] = path[i - 1]
            a = i - 1
        end
    end
    out[#out + 1] = path[#path]
    return out
end

-- (a short open scrap, where ground just touches the map's edge or another's,
-- reads as a stray hook: left out)
local function Kept(pts, closed) return #pts >= 3 and (closed or #pts >= 10) end

-- the way the pen goes round a ring: mostly closed; some stop short of their
-- start, a little gap. Returns the path
-- and whether it's open. (No run-ons or blots: they read as lumps)
local OPEN, GAP, FEATHER = 0.4, { 0.05, 0.08 }, 2.2   -- share left open; gap, of the ring; cells an end thins over
local function PenPath(path, closed, rnd)
    if not closed then return path, true end
    local k = #path - 1   -- (a closed path repeats its first point last)
    if k < 6 or rnd() >= OPEN then return path, false end
    local per = 0
    for i = 1, k do
        local p, q = path[i], path[i + 1]
        per = per + math.sqrt((q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2)
    end
    if per <= 0 then return path, false end
    local s0 = math.floor(rnd() * k)
    local stop = per * (1 - GAP[1] - rnd() * GAP[2])
    local out, d = { path[s0 + 1] }, 0
    for i = 0, k - 1 do
        local p, q = path[(s0 + i) % k + 1], path[(s0 + i + 1) % k + 1]
        local dx, dy = q[1] - p[1], q[2] - p[2]
        local L = math.sqrt(dx * dx + dy * dy)
        if d + L >= stop then
            local t = L > 0 and (stop - d) / L or 1
            out[#out + 1] = { p[1] + dx * t, p[2] + dy * t }
            break
        end
        out[#out + 1] = q
        d = d + L
    end
    return out, true
end

-- how far a piece runs past a join to cover the bend's outer corner (px)
local function Reach(ax, ay, bx, by, th)
    local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
    if la == 0 or lb == 0 then return 0 end
    local c = math.max(-1, math.min(1, (ax * bx + ay * by) / (la * lb)))
    return math.min(th * 0.35, th * 0.5 * math.sqrt((1 - c) / (1 + c + 1e-6)))
end

-- a quest in your log: an inked ring a patch, its width wandering a little; an
-- open one thins to nothing at both ends (feathered, cut finer there)
local function Rim(lines, cw, th, r, g, b, a, seed)
    for li, l in ipairs(lines) do
        Pause()
        if Kept(l[1], l[2]) then
            l.path = l.path or Simplify(Smooth(l[1], l[2]))
            local rnd = Rand(seed * 7919 + li * 104729)
            local path, open = PenPath(l.path, l[2], rnd)
            local phase = rnd() * 6.3
            local total = 0
            for i = 2, #path do
                total = total + math.sqrt((path[i][1] - path[i - 1][1]) ^ 2 + (path[i][2] - path[i - 1][2]) ^ 2)
            end
            local fe = math.min(FEATHER, total / 4)
            -- the pieces, in px: { x1, y1, x2, y2, width }
            local pcs, run = {}, 0
            for i = 2, #path do
                local p, q = path[i - 1], path[i]
                local dx, dy = q[1] - p[1], q[2] - p[2]
                local L = math.sqrt(dx * dx + dy * dy)
                local cuts = 1
                if open and (run < fe or run + L > total - fe) then cuts = math.max(1, math.ceil(L / 0.5)) end
                for c = 1, cuts do
                    local t0, t1 = (c - 1) / cuts, c / cuts
                    local mid = run + L * (t0 + t1) / 2
                    local w = 1 + 0.18 * math.sin(mid * 0.35 + phase)
                    if open then
                        w = w * (0.3 + 0.7 * math.min(1, mid / fe)) * (0.3 + 0.7 * math.min(1, (total - mid) / fe))
                    end
                    pcs[#pcs + 1] = { (p[1] + dx * t0 + 0.5) * cw, (p[2] + dy * t0 + 0.5) * cw,
                        (p[1] + dx * t1 + 0.5) * cw, (p[2] + dy * t1 + 0.5) * cw, th * w }
                end
                run = run + L
            end
            local m = #pcs
            for i, s in ipairs(pcs) do
                local prev = pcs[i - 1] or (not open and pcs[m])
                local nxt = pcs[i + 1] or (not open and pcs[1])
                local e1 = prev and Reach(prev[3] - prev[1], prev[4] - prev[2], s[3] - s[1], s[4] - s[2], s[5]) or 0
                local e2 = nxt and Reach(s[3] - s[1], s[4] - s[2], nxt[3] - nxt[1], nxt[4] - nxt[2], s[5]) or 0
                Segment(s[1], s[2], s[3], s[4], s[5], r, g, b, a, e1, e2)
            end
        end
    end
end

-- a quest you could take: a dotted ring, no fill (told apart at a glance)
local function Dotted(lines, cw, th, r, g, b, a)
    for _, l in ipairs(lines) do
        Pause()
        if Kept(l[1], l[2]) then
            l.smooth = l.smooth or Smooth(l[1], l[2])
            local path, nextAt, dist = l.smooth, 0, 0
            for i = 2, #path do
                local A, B = path[i - 1], path[i]
                local dx, dy = B[1] - A[1], B[2] - A[2]
                local L = math.sqrt(dx * dx + dy * dy)
                while nextAt <= dist + L do
                    local t = L > 0 and (nextAt - dist) / L or 0
                    Dot((A[1] + dx * t + 0.5) * cw, (A[2] + dy * t + 0.5) * cw, th * 1.9, r, g, b, a)
                    nextAt = nextAt + DOT_STEP
                end
                dist = dist + L
            end
        end
    end
end

-- a quest's field and outlines on this map, kept: the same spawns give the same
-- shapes (several quests can share them: Un'Goro's crystal quests)
local shapes, shapeCount = {}, 0
local function Shape(q, mapID)
    local n, first, last = 0, nil, nil
    for _, part in ipairs(q.parts) do
        for _, p in ipairs(part.points) do
            n = n + 1
            first = first or p
            last = p
        end
    end
    local key = string.format("%s:%d:%.4f:%.4f:%.4f:%.4f", tostring(mapID), n, first[1], first[2], last[1], last[2])
    local sh = shapes[key]
    if sh then return sh end
    if shapeCount > 300 then wipe(shapes) shapeCount = 0 end
    sh = { f = Field(q), key = key }
    shapes[key], shapeCount = sh, shapeCount + 1
    return sh
end

-- Arrows (ground.arrows): a small inked arrow at a spot easy to miss, for a quest in
-- focus or found ("find on map"; drawn in Light): an objective with LONE spawns or
-- fewer on this map (a thing to use, an item to pick up, one named monster), and its
-- turn-in ("?" pins shown). Kept here when drawn: arrowsAt[questID] = { { x, y, off,
-- r, g, b, a } }; off: how far from the spot its tip stays (px), past its ground or pin.
local LONE = 2
local TURNIN = { 0.80, 0.55, 0.12 }   -- (a warm gold ink: brown was lost on the map, bright yellow read as green)
local function KeepArrow(id, x, y, off, r, g, b, a)
    arrowsAt[id] = arrowsAt[id] or {}
    table.insert(arrowsAt[id], { x, y, off, r, g, b, a })
end

-- (groundUp: there's ground to show; docked with dock.splitQuests it only shows on the map face)
local groundUp = false
function ns.QuestGroundFace()
    if host and groundUp then host:SetShown(not ns.SplitHides("ground")) end
end

-- Quiet (ground.quiet) --------------------------------------------------------------
-- 13 quests each drawing everywhere their monsters live filled a zone with loops (the user:
-- not usable). So only the quests at hand have ground: in focus, pointed at, open or found,
-- and the work at the route's next stop. And only the best camp of each objective: the near
-- ones, a big one beating a stray spawn. The rest are a dot at that camp, unless objective
-- spots show them already; pointing at a dot draws its ring. Camps of quests at hand that
-- lie together are one ring. Picked again when you've walked a sixth of the map.
local JOIN = 5     -- cells: spawns this close are one camp
local CAMP = 12    -- cells: the furthest a camp reaches from its near end (spawns can chain across a zone)
local MERGE = 8    -- cells: camps this close are one ring
local WALK = 6     -- the map's parts, for "you've walked"
local FEW = 6      -- an objective with this many spots or fewer keeps them all
local states = {}  -- (the tracker's glow states, Light below: [questID] = { hover, map, page, focus })

-- the best camp of these spawns: { x, y, has = { [point] = true } }. mx, my: you, if on this map
function ns.QuestGroundCamps(points, mx, my)
    local buckets = {}
    for _, p in ipairs(points) do
        local k = math.floor(p[1] * COLS / JOIN) * 1000 + math.floor(p[2] * ROWS / JOIN)
        buckets[k] = buckets[k] or {}
        table.insert(buckets[k], p)
    end
    local best, score
    for k in pairs(buckets) do
        if buckets[k] then
            local camp, x, y, n = { pts = {} }, 0, 0, 0
            local stack = { k }
            while #stack > 0 do
                local at = table.remove(stack)
                local b = buckets[at]
                if b then
                    buckets[at] = false
                    for _, p in ipairs(b) do
                        camp.pts[#camp.pts + 1] = p
                        x, y, n = x + p[1], y + p[2], n + 1
                    end
                    for dx = -1000, 1000, 1000 do
                        for dy = -1, 1 do stack[#stack + 1] = at + dx + dy end
                    end
                end
            end
            -- its near end: the spawn nearest you, or its middle off this map
            local ox, oy, sx, near = mx or x / n, my or y / n, mx and 1.5 or 1, nil
            for _, p in ipairs(camp.pts) do
                local ex, ey = (p[1] - ox) * sx, p[2] - oy
                local d = ex * ex + ey * ey
                if not near or d < near then camp.at, near = p, d end
            end
            local s = mx and (math.sqrt(near) + 0.03) / math.sqrt(math.min(n, 9)) or -n
            if not score or s < score then best, score = camp, s end
        end
    end
    local x, y, n, has = 0, 0, 0, {}
    for _, p in ipairs(best.pts) do
        local dx, dy = (p[1] - best.at[1]) * COLS, (p[2] - best.at[2]) * ROWS
        if dx * dx + dy * dy <= CAMP * CAMP then
            has[p] = true
            x, y, n = x + p[1], y + p[2], n + 1
        end
    end
    return { x = x / n, y = y / n, has = has }
end

-- a quest's parts cut down to its objectives' camps, and those camps
local function Cropped(q, mx, my)
    local spawns, keys = {}, {}
    for _, part in ipairs(q.parts) do
        local k = part.item or part.what or "?"
        if not spawns[k] then
            spawns[k] = {}
            keys[#keys + 1] = k
        end
        for _, p in ipairs(part.points) do table.insert(spawns[k], p) end
    end
    -- (an objective with only a few spots, places to visit: every one is its own camp, all kept. Eyes of
    -- the Sentinels' four places are one objective, and on Darnassus's map the nearest alone was left)
    local byKey, camps, parts = {}, {}, {}
    for _, k in ipairs(keys) do
        if #spawns[k] <= FEW then
            byKey[k] = {}
            for _, p in ipairs(spawns[k]) do
                local camp = { x = p[1], y = p[2], has = { [p] = true }, parts = {}, few = true }
                byKey[k][#byKey[k] + 1] = camp
                camps[#camps + 1] = camp
            end
        else
            local camp = ns.QuestGroundCamps(spawns[k], mx, my)
            camp.parts = {}
            byKey[k] = { camp }
            camps[#camps + 1] = camp
        end
    end
    for _, part in ipairs(q.parts) do
        local pts, seen = {}, {}
        for _, camp in ipairs(byKey[part.item or part.what or "?"]) do
            local hit = false
            for _, p in ipairs(part.points) do
                if camp.has[p] and not seen[p] then
                    seen[p], hit = true, true
                    pts[#pts + 1] = p
                end
            end
            if hit then table.insert(camp.parts, part) end
        end
        if #pts > 0 then parts[#parts + 1] = setmetatable({ points = pts }, { __index = part }) end
    end
    return parts, camps
end

local function AtHand()
    local set = {}
    for id, st in pairs(states) do
        if st.hover or st.map or st.page or st.focus then set[id] = true end
    end
    if ns.RouteNow then
        local route, at = ns.RouteNow()
        local stop = route and route.stops[at]
        for _, s in ipairs(stop and stop.items or {}) do
            if s.kind == "work" then set[s.q] = true end
        end
    end
    return set
end

-- the quests to draw, each with only its camps, and the marks for the rest
local function Quieten(quests, mapID)
    local at, mx, my = AtHand(), nil, nil
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then mx, my = pos.x, pos.y end
    local list, marks = {}, {}
    for _, q in ipairs(quests) do
        Pause()
        local parts, camps = Cropped(q, mx, my)
        if at[q.id] then
            list[#list + 1] = setmetatable({ parts = parts, whole = q.parts, camps = camps }, { __index = q })
        else
            marks[#marks + 1] = { q = q, camps = camps }
        end
    end
    return list, marks
end

local function CampsMeet(a, b)
    for _, p in ipairs(a) do
        for _, o in ipairs(b) do
            local dx, dy = (p.x - o.x) * COLS, (p.y - o.y) * ROWS
            if dx * dx + dy * dy <= MERGE * MERGE then return true end
        end
    end
end

-- quests at hand working the same camp share one ring, the first's (a lone spawn keeps its X)
local function ShareRings(order)
    for i, q in ipairs(order) do
        for j = 1, i - 1 do
            local o = order[j]
            if not q.ringBy and CampsMeet(q.camps, o.camps) then
                local lead = o.ringBy or o
                q.ringBy = lead
                lead.extra = lead.extra or {}
                for _, part in ipairs(q.parts) do
                    if #part.points > 1 then table.insert(lead.extra, part) end
                end
            end
        end
    end
end

-- one pixel of the screen on the canvas, at the map's widest zoom: dots keep a size on screen however
-- small the map is (the user: right on the big map, too small docked and on the small map)
local DOT_PX, SPAWN_PX = 15, 10
local function FitScale()
    local sc = map.ScrollContainer
    return sc and sc.zoomLevels and sc:GetScaleForMinZoom() or nil
end
local function ScreenPixel()
    local _, h = 0, 1080
    if GetPhysicalScreenSize then _, h = GetPhysicalScreenSize() end
    local e = host:GetEffectiveScale()
    local sc, lo = map.ScrollContainer, FitScale()
    local s = sc and sc.GetCanvasScale and sc:GetCanvasScale()
    if lo and s and s > 0 then e = e * lo / s end
    return 768 / h / math.max(0.01, e)
end

local function Draw()
    t0 = debugprofilestop()
    Clear()
    local c = Cfg()
    local mapID = map:GetMapID()
    if not (c and ns.IsShown("ground") and c.look ~= "pins" and mapID and ns.QuestGround) then
        groundUp = false
        host:Hide()
        return
    end
    local canvas = map:GetCanvas()
    local W, H = canvas:GetWidth(), canvas:GetHeight()
    if not (W and W > 0 and H > 0) then return end
    host:SetParent(canvas)
    host:SetAllPoints(canvas)
    host:SetFrameLevel(ns.ArtLevel and ns.ArtLevel(map, 6) or canvas:GetFrameLevel() + 1)
    groundUp = true
    ns.QuestGroundFace()
    glow:SetFrameLevel(host:GetFrameLevel() + 1)
    local cw = W / COLS
    local a = c.alpha or 0.7
    local least = 1.5 * UIParent:GetEffectiveScale() / math.max(0.01, host:GetEffectiveScale())
    local px = ScreenPixel()
    local quests = ns.QuestGround(mapID, c.all)
    local byId = {}
    for i, q in ipairs(quests) do byId[i] = q end
    table.sort(byId, function(x, y) return x.id < y.id end)
    for i, q in ipairs(byId) do
        if c.colorBy == "type" then
            local ok, word = pcall(ns.QuestKind or function() end, q.id)
            q.groundColor = ok and TYPE_COLORS[word or ""] or PLAIN
        else
            -- (its place among this map's quests, so neighbours never share a colour; a quest on two maps
            -- can change colour between them, the lesser trouble, the user)
            q.groundColor = PALETTE[(i - 1) % #PALETTE + 1]
        end
    end
    -- quests in your log first: a monster or thing several quests want (Un'Goro's
    -- crystals) is drawn once, by the first of them, in its colour; a quest whose
    -- every kind is drawn already takes that colour (the tooltip names them all)
    local order, marks = {}, nil
    if c.quiet ~= false then
        order, marks = Quieten(quests, mapID)
    else
        for i, q in ipairs(quests) do order[i] = q end
    end
    table.sort(order, function(x, y)
        if x.inLog ~= y.inLog then return x.inLog end
        return x.id < y.id
    end)
    if marks then ShareRings(order) end
    local done, kinds, xSeen = {}, {}, {}
    for _, q in ipairs(order) do
        Pause()
        -- an objective at one spot alone (Hogger): an inked X there, no ground
        local total, singles = {}, {}
        for _, part in ipairs(q.parts) do
            local k = part.item or part.what or "?"
            total[k] = (total[k] or 0) + #part.points
        end
        -- this quest's kinds not drawn yet
        local own, by = { id = q.id, parts = {} }, nil
        for _, part in ipairs(q.parts) do
            local p1 = part.points[1]
            if total[part.item or part.what or "?"] == 1 then
                singles[#singles + 1] = p1
            else
            local kk = (part.what or "?") .. ":" .. #part.points .. ":" .. string.format("%.4f:%.4f", p1[1], p1[2])
            if kinds[kk] then by = by or kinds[kk] else kinds[kk] = q own.parts[#own.parts + 1] = part end
            end
        end
        for _, part in ipairs(q.extra or {}) do own.parts[#own.parts + 1] = part end
        local sh = not q.ringBy and c.look ~= "dots" and #own.parts > 0 and Shape(own, mapID) or nil
        local same = q.ringBy or (#own.parts == 0 and #singles == 0 and by) or (sh and done[sh.key])
        if same then q.groundColor = same.groundColor end
        local col = c.color ~= false and q.groundColor or PLAIN
        local r, g, b = col[1], col[2], col[3]
        local qa = q.inLog and a or a * 0.6   -- (quests you could take: fainter)
        if same then
            groups[q.id] = groups[same.id]
        else
            cur = {}
            local area
            if sh then   -- (its size, for the hover: small spots before big areas)
                area = sh.area
                if not area then
                    area = 0
                    for _, v in pairs(sh.f) do if v >= EDGE * 0.6 then area = area + 1 end end
                    sh.area = area
                end
            end
            groups[q.id] = { tex = cur, sh = sh, cw = cw, th = math.max(least * 1.5, cw * 0.36), col = col, area = area, xs = {} }
        end
        if same then
            -- (drawn already)
        elseif c.look == "dots" then
            for _, part in ipairs(own.parts) do
                for _, p in ipairs(part.points) do Mark(p[1] * W, p[2] * H, math.max(px * SPAWN_PX, cw * 0.55), r, g, b, qa) end
            end
        elseif sh then
            done[sh.key] = q
            local f = sh.f
            if c.look == "ink" then
                sh.lines = sh.lines or Outlines(f)
                if q.inLog then
                    Haze(f, cw, r, g, b, qa * 0.3)
                    Rim(sh.lines, cw, math.max(least * 1.5, cw * 0.36), r * 0.5, g * 0.5, b * 0.5, math.min(1, qa * 1.4), q.id)
                else   -- (quests you could take: a dotted ring alone)
                    Dotted(sh.lines, cw, math.max(least * 1.5, cw * 0.24), r * 0.55, g * 0.55, b * 0.55, math.min(1, qa * 1.4))
                end
            else
                Haze(f, cw, r, g, b, qa)
            end
        end
        for _, p in ipairs(singles) do
            local k = string.format("%.4f:%.4f", p[1], p[2])
            if not xSeen[k] then
                xSeen[k] = true
                -- (as the dots: the quest's colour, aged, on a dark ink edge. In a dark shade of it, it
                -- was the map's own brown-red and sank into the ridges, the user)
                local x, y, s = p[1] * W, p[2] * H, cw * 0.95
                local th = math.max(least * 2, cw * 0.42)
                local xr, xg, xb, xa = r + (PAPER[1] - r) * AGE, g + (PAPER[2] - g) * AGE, b + (PAPER[3] - b) * AGE, math.min(1, qa * 1.4)
                local function Stroke(x1, y1, x2, y2, w)
                    Segment(x1, y1, x2, y2, w + math.max(least * 1.5, th * 0.5), 0.13, 0.09, 0.06, 0.9 * xa, th * 0.3, th * 0.3)
                    Segment(x1, y1, x2, y2, w, xr, xg, xb, xa, th * 0.3, th * 0.3, true)
                end
                -- the notebook's own hand-drawn X (Data\InkGlyphs.lua), one of its drawings
                -- picked by the spot; two straight strokes if Ink.lua hasn't one
                local seed = math.floor(p[1] * 9973 + p[2] * 7919 * 13) + q.id
                local strokes = ns.InkGlyphStrokes and ns.InkGlyphStrokes("x", seed % 3 + 1, x, y, s * 3.3, seed)
                if strokes then
                    for _, st in ipairs(strokes) do
                        for i = 2, #st do
                            local a, c = st[i - 1], st[i]
                            Stroke(a[1], a[2], c[1], c[2], th * 1.2 * (a[3] + c[3]) / 2)
                        end
                    end
                else
                    Stroke(x - s, y - s, x + s, y + s, th)
                    Stroke(x - s, y + s, x + s, y - s, th)
                end
                local gr = groups[q.id]
                if gr and gr.xs then gr.xs[#gr.xs + 1] = { x, y } end
            end
        end
        cur = nil
        for _, part in ipairs(q.parts) do
            for _, p in ipairs(part.points) do drawn[#drawn + 1] = { p[1], p[2], q, part } end
        end
    end
    -- the quests not at hand: a dot at each camp, a shared one where they meet
    if marks and not ns.IsShown("spots") then
        local seen, dotted = {}, {}
        local function Spot(camp)
            local k = math.floor(camp.x * COLS / 3) .. ":" .. math.floor(camp.y * ROWS / 3)
            seen[k] = seen[k] or { camp.x, camp.y }
            return seen[k], k
        end
        -- (shared dots placed by quest ID: placed by who's lit, a dot moved out from under the
        -- mouse as it lit, went out, came back, and the tooltip flickered)
        local camps = {}
        for _, q in ipairs(order) do camps[q.id] = q.camps end
        for _, m in ipairs(marks) do camps[m.q.id] = m.camps end
        for _, q in ipairs(byId) do
            for _, camp in ipairs(camps[q.id] or {}) do Spot(camp) end
        end
        -- (a quest at hand still answers at its dot's place: lit by pointing there, it mustn't
        -- leave the tooltip, which lit the next quest, and so on round)
        for _, q in ipairs(order) do
            for _, camp in ipairs(q.camps) do
                local at = Spot(camp)
                for _, part in ipairs(camp.parts) do drawn[#drawn + 1] = { at[1], at[2], q, part } end
            end
        end
        for _, m in ipairs(marks) do
            Pause()
            local q = m.q
            local col = c.color ~= false and q.groundColor or PLAIN
            local qa = q.inLog and a or a * 0.6
            cur = {}
            groups[q.id] = { tex = cur, cw = cw, th = math.max(least * 1.5, cw * 0.36), col = col, area = 1, xs = {} }
            for _, camp in ipairs(m.camps) do
                local at, k = Spot(camp)
                if not dotted[k] then
                    dotted[k] = true
                    Mark(at[1] * W, at[2] * H, math.max(px * DOT_PX, cw * 0.8), col[1], col[2], col[3], qa)
                end
                for _, part in ipairs(camp.parts) do drawn[#drawn + 1] = { at[1], at[2], q, part } end
            end
            cur = nil
        end
    end
    if c.arrows ~= false then
        arrowsAt.cw, arrowsAt.th = cw, math.max(least * 1.5, cw * 0.3)
        local off = c.look == "dots" and cw * 0.9 or REACH * cw * 0.95
        for _, q in ipairs(order) do
            if q.inLog then
                local col = c.color ~= false and q.groundColor or PLAIN
                -- (an objective's spots all told: an item many monsters drop isn't
                -- lone because one of them is a single named one)
                local total = {}
                local whole = q.whole or q.parts
                for _, part in ipairs(whole) do
                    local k = part.item or part.what or "?"
                    total[k] = (total[k] or 0) + #part.points
                end
                for _, part in ipairs(whole) do
                    if total[part.item or part.what or "?"] <= LONE then
                        for _, p in ipairs(part.points) do
                            KeepArrow(q.id, p[1] * W, p[2] * H, off, col[1] * 0.5, col[2] * 0.5, col[3] * 0.5, 1)
                        end
                    end
                end
            end
        end
        if ns.IsShown("turnins") and ns.QuestIcons then
            local seen = {}
            for _, icon in ipairs(ns.QuestIcons(mapID)) do
                local k = icon.group == "turnins" and string.format("%.1f:%.1f", icon.x, icon.y)
                if k and not seen[k] then
                    seen[k] = true
                    KeepArrow(icon.id, icon.x / 100 * W, icon.y / 100 * H, cw * 1.4, TURNIN[1], TURNIN[2], TURNIN[3], 0.95)
                end
            end
        end
    end
    if ns.QuestGroundRelight then ns.QuestGroundRelight() end
end

-- Light --------------------------------------------------------------------------

-- A quest lit up on its ground (mock-up mockups\ground-highlight.html), from the
-- tracker's glow states (Tracker.lua GlowPins): hover (its tracker or log line, its
-- ground, a spot), map ("find on map"), page (open in the quest window), focus.
--   haze: gilt edge (a gold line round it, softly glowing, the haze deeper) when in
--     focus, open or found; a warm gold wash under it when only hovered
--   ink: gilt edge (the ring bolder, gold glow behind, fill warmer) for all
--   dots: gilt halo (each dot a little bigger, a gold halo) for all
-- hush (ground.hush): while a quest is hovered or found, the other quests fade.
-- No redraw: the drawn textures change colour and size, and the gold is a few
-- textures of the lit quests only, on their own frame, faded in.
local GOLD = { 0.94, 0.76, 0.32 }
local HUSH = 0.33
-- (fresh: the pieces of quests lit just now, fading in; fresh.on: what's drawn now
-- is one of those. Ones lit before stay as they are: a focused quest's gold and
-- arrow no longer faded in again on every click in the log)
local gpool = { lines = {}, blobs = {}, nl = 0, nb = 0, fresh = {} }
local touched = {}          -- groups changed last time: put back first

local function Fresh(t)
    local f = gpool.fresh
    t:SetAlpha(f.on and 0 or 1)
    if f.on then f[#f + 1] = t end
end
local function GLine(x1, y1, x2, y2, th, r, g, b, a, soft, level)
    gpool.nl = gpool.nl + 1
    local l = gpool.lines[gpool.nl]
    if not l then
        l = glow:CreateLine(nil, "ARTWORK")
        gpool.lines[gpool.nl] = l
    end
    Fresh(l)
    l:SetTexture(soft and BLOB or BRUSH)
    l:SetDrawLayer("ARTWORK", level or 3)
    l:SetVertexColor(r, g, b, a)
    l:SetThickness(th)
    l:SetStartPoint("TOPLEFT", glow, x1, -y1)
    l:SetEndPoint("TOPLEFT", glow, x2, -y2)
    l:Show()
end
local function GBlob(x, y, size, r, g, b, a)
    gpool.nb = gpool.nb + 1
    local t = gpool.blobs[gpool.nb]
    if not t then
        t = glow:CreateTexture(nil, "ARTWORK", nil, 0)
        t:SetTexture(BLOB)
        gpool.blobs[gpool.nb] = t
    end
    Fresh(t)
    t:SetVertexColor(r, g, b, a)
    t:SetSize(size, size)
    t:ClearAllPoints()
    t:SetPoint("CENTER", glow, "TOPLEFT", x, -y)
    t:Show()
end

-- a group's textures: alpha k times as drawn, rim and dots grow times as big
local function Tint(gr, k, grow)
    gr.grow = grow
    local thin = ZoomThin()
    for _, e in ipairs(gr.tex) do
        local t = e[1]
        t:SetVertexColor(e[3], e[4], e[5], math.min(1, e[6] * k))
        if e[2] == "l" then t:SetThickness(e[7] * grow * thin)
        elseif e[2] == "d" then t:SetSize(e[7] * grow * thin, e[7] * grow * thin) end
    end
end

-- the zoom changed: rings and dots to their new width, nothing else is touched
local lastThin = 1
local function Rethin()
    local thin = ZoomThin()
    if math.abs(thin - lastThin) < 0.01 then return end
    lastThin = thin
    for _, gr in pairs(groups) do
        local grow = (gr.grow or 1) * thin
        for _, e in ipairs(gr.tex or {}) do
            if e[2] == "l" then e[1]:SetThickness(e[7] * grow)
            elseif e[2] == "d" then
                e[1]:SetSize(e[7] * grow, e[7] * grow)
                local tier = e[11] and Tier(e[7])
                if tier and tier ~= e[12] then
                    e[12] = tier
                    e[1]:SetTexture(ART[e[11]][tier])
                end
            end
        end
    end
end

-- the ring's lines in px, whole (no pen gaps): fn(x1, y1, x2, y2) for each piece
-- haze: round the haze's visible edge (its soft blobs reach past EDGE, to about
-- HAZE_EDGE), a little finer, so the gold hugs the haze; ink: round the ring, coarser
-- (the gold is soft and wide behind the ink, half the pieces do)
local HAZE_EDGE = EDGE * 0.27   -- (0.5 sat just inside; a spawn's reach falls as 1 - d^2: this is about 5% further out)
local function EachEdge(gr, fn, haze)
    local sh = gr.sh
    if not sh then return end
    local lines
    if haze then
        sh.hazeLines = sh.hazeLines or Outlines(sh.f, HAZE_EDGE)
        lines = sh.hazeLines
    else
        sh.lines = sh.lines or Outlines(sh.f)
        lines = sh.lines
    end
    local cw = gr.cw
    for _, l in ipairs(lines) do
        if Kept(l[1], l[2]) then
            l.gilt = l.gilt or (haze and Simplify(Smooth(l[1], l[2]), 0.1, 4) or Simplify(Smooth(l[1], l[2]), 0.2, 6))
            for i = 2, #l.gilt do
                local p, q = l.gilt[i - 1], l.gilt[i]
                fn((p[1] + 0.5) * cw, (p[2] + 0.5) * cw, (q[1] + 0.5) * cw, (q[2] + 0.5) * cw)
            end
        end
    end
end

-- a kept arrow (see Arrows): pointing down from above, a little right; from below near
-- the map's top
local ARROW = 0.8   -- (its size; the user: 20% smaller)
local function DrawArrow(e)
    local cw, th = arrowsAt.cw * ARROW, arrowsAt.th * ARROW
    local x, y, off = e[1], e[2], e[3]
    local dir = y < arrowsAt.cw * 7 and -1 or 1
    local tx, ty = x, y - dir * off
    local sx, sy = tx + cw * 1.3, ty - dir * cw * 4
    GLine(sx, sy, tx, ty, th, e[4], e[5], e[6], e[7])
    local ang = math.atan2(sy - ty, sx - tx)
    for _, d in ipairs({ 0.5, -0.5 }) do
        GLine(tx, ty, tx + math.cos(ang + d) * cw * 1.4, ty + math.sin(ang + d) * cw * 1.4, th, e[4], e[5], e[6], e[7])
    end
end

-- fadeIn: the gold fades in (what's lit changed); else it stays as it is (a redraw)
local function Relight(fadeIn)
    if not (host and glow) then return end
    local c = Cfg()
    for gr in pairs(touched) do Tint(gr, 1, 1) end
    wipe(touched)
    for _, l in ipairs(gpool.lines) do l:Hide() end
    for _, t in ipairs(gpool.blobs) do t:Hide() end
    gpool.nl, gpool.nb = 0, 0
    -- (what was lit last time: [group] / ["a" .. questID] for its arrows = true)
    local was = gpool.was or {}
    gpool.was = {}
    wipe(gpool.fresh)
    if not host:IsShown() then return end
    local look = c.look
    -- which groups are lit, and how
    local lit, hush = {}, false
    for id, st in pairs(states) do
        local gr = groups[id]
        if gr then
            local how
            if look == "haze" then
                how = (st.focus or st.page or st.map) and "gilt" or st.hover and "wash" or nil
            elseif look == "ink" then
                how = (st.hover or st.map or st.page or st.focus) and "gilt" or nil
            else
                how = (st.hover or st.map or st.page or st.focus) and "gilt" or nil
            end
            if how then
                lit[gr] = lit[gr] or {}
                if how == "gilt" or not lit[gr].how then lit[gr].how = how end
                if st.hover or st.map then hush = true end
            end
        end
    end
    if hush and c.hush ~= false then
        for _, gr in pairs(groups) do
            if not (lit[gr] and lit[gr].how) and not touched[gr] then
                Tint(gr, HUSH, 1)
                touched[gr] = true
            end
        end
    end
    for gr, l in pairs(lit) do
        touched[gr] = true
        gpool.was[gr] = true
        gpool.fresh.on = fadeIn and not was[gr]
        if l.how == "gilt" and look == "dots" then
            Tint(gr, 1.25, 1.25)
            -- (once a dot, not its rim too. Close in the halo is in the map's units, so it grew over
            -- everything: past mid zoom it shrinks and fades. And one to a patch of the map: where
            -- spawns crowd, halos on each stacked into solid gold, the user)
            local k, seen = math.min(1, ZoomThin() / 0.5), {}
            for _, e in ipairs(gr.tex) do
                if e[2] == "d" and not e[10] then
                    local size = e[7] * 3 * k
                    local key = math.floor(e[8] / size) .. ":" .. math.floor(e[9] / size)
                    if not seen[key] then
                        seen[key] = true
                        GBlob(e[8], e[9], size, GOLD[1], GOLD[2], GOLD[3], 0.3 * (0.4 + 0.6 * k))
                    end
                end
            end
        end
        if l.how then   -- (an X: a gold halo behind it, whatever the look)
            for _, xy in ipairs(gr.xs or {}) do GBlob(xy[1], xy[2], gr.cw * 4, GOLD[1], GOLD[2], GOLD[3], 0.55) end
        end
        if l.how == "gilt" and look == "dots" then
            -- (done above)
        elseif l.how == "gilt" then
            local ink = look == "ink"
            -- (close up the gold fades and narrows, and the ring is less bold: at full
            -- strength it swamped the map, the user)
            local thin = ZoomThin()
            local soft = 0.3 + 0.7 * thin
            Tint(gr, ink and 1 + 0.6 * thin or 1.45, ink and 1 + 0.25 * thin or 1)
            local th = gr.th * thin
            EachEdge(gr, function(x1, y1, x2, y2)
                GLine(x1, y1, x2, y2, th * (ink and 1.6 + 1.6 * thin or 2.2), GOLD[1], GOLD[2], GOLD[3], 0.42 * soft, true, 0)
                if not ink then
                    GLine(x1, y1, x2, y2, th * 0.45, GOLD[1] * 0.92, GOLD[2] * 0.85, GOLD[3] * 0.7, 0.95, false, 3)
                end
            end, not ink)
        elseif l.how == "wash" then
            Tint(gr, 0.85, 1)
            for _, e in ipairs(gr.tex) do
                if e[2] == "b" then GBlob(e[8], e[9], e[7] * 1.1, GOLD[1], GOLD[2], GOLD[3], math.min(0.6, e[6] * 1.3)) end
            end
        end
    end
    -- arrows: a quest in focus or found
    if c.arrows ~= false and arrowsAt.cw then
        for id, st in pairs(states) do
            if st.focus or st.map then
                gpool.was["a" .. id] = true
                gpool.fresh.on = fadeIn and not was["a" .. id]
                for _, e in ipairs(arrowsAt[id] or {}) do DrawArrow(e) end
            end
        end
    end
    gpool.fresh.on = nil
    -- the newly lit gold fades in (its pieces' alpha, a few frames)
    if #gpool.fresh > 0 then fade = 0 end
end
ns.QuestGroundRelight = function(fadeIn)
    local ok, err = pcall(Relight, fadeIn)
    if not ok then ns.Log("Quest ground light:", tostring(err)) end
end

-- the tracker's glow states changed (Tracker.lua): s = { [questID] = { hover, map, page, focus } }
-- (the tracker asks again on every pin refresh: only a real change re-lights,
-- else the gold kept fading in again, a flashing)
local stateKey
function ns.QuestGroundLight(s)
    local keys = {}
    for id, st in pairs(s or {}) do
        keys[#keys + 1] = id .. (st.hover and "h" or "") .. (st.map and "m" or "") .. (st.page and "p" or "") .. (st.focus and "f" or "")
    end
    table.sort(keys)
    local key = table.concat(keys, ",")
    if key == stateKey then return end
    stateKey = key
    states = s or {}
    ns.QuestGroundRelight(true)
end

-- Hover --------------------------------------------------------------------------

local tipShown, tipKey, tipQuest, tipInLog   -- (tipQuest: the first quest in the tooltip, a click opens it)
-- (the mouse is on ground: docked, the minimap stands aside for it as it does for a pin, DockPatch.lua;
-- seen: for /bfi check, what the last look found)
local onGround, seenOver, seenHits, seenOwner = false, false, 0, "none"
local glowing = false   -- (we lit a quest by hovering it: it's ours to let go, even with the tooltip long gone)
function ns.QuestGroundUnderMouse() return onGround end
-- a click on ground opens its quest's page, as a spot's or turn-in's click does
-- (the quest window shown, questlog.fromPins)
local function ClickOpens()
    local q = ns.db and ns.db.questlog
    return q and q.shown and q.fromPins and ns.OpenQuest and true or false
end
-- the tooltip up is ground's: ours, or Questie's over it (questie.tooltip)
local function TipOurs()
    local owner = GameTooltip:GetOwner()
    return owner == host or (owner and owner == (ns.QuestTipProxy and ns.QuestTipProxy()))
end
local function Hover()
    local c = Cfg()
    local over = host:IsVisible() and #drawn > 0 and map.ScrollContainer and map.ScrollContainer:IsMouseOver()
    -- (not through a cave view or the dungeon map over the map: the ground under them isn't seen)
    if over and ((ns.caveView and ns.caveView:IsVisible()) or (ns.DungeonMapShown and ns.DungeonMapShown())) then
        over = false
    end
    local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
    -- (ours, or Questie's over this ground, questie.tooltip)
    local mine = owner == host or (tipShown and owner and owner == (ns.QuestTipProxy and ns.QuestTipProxy()))
    -- (the minimap's blip names don't count: it lies over the map docked, and ground goes first)
    local blip = owner and owner == Minimap
    seenOver, seenHits, seenOwner = over and true or false, 0, owner and (owner.GetName and owner:GetName() or "unnamed") or "none"
    onGround = false
    if owner and not mine and not blip then   -- (another tooltip: a pin's, or the log's after a click opened it)
        -- (a spot's own glow is its pin's to end. Any other: ours goes, or it stayed lit beside
        -- the next quest you picked, with the mouse never crossing open map)
        if glowing and owner.bfiGroup ~= "spots" and ns.HoverQuestGlow then ns.HoverQuestGlow(nil) end
        tipShown, glowing = false, false
        return
    end
    -- (a menu up, e.g. this ground's own: no tooltip under it; shown again it
    -- flickered, the menu's opening hiding it each time)
    if ns.QuillMenuShown and ns.QuillMenuShown() then
        if tipShown and mine then ns.QuestTooltipLeave() end
        tipShown = false
        return
    end
    local hits = {}
    if over then
        local x, y = map:GetNormalizedCursorPosition()
        -- haze and rings: inside a quest's ground counts, as drawn (its field over
        -- the edge at the cursor's cell); dots: near a spawn, as before
        local inside = {}
        if c.look ~= "dots" then
            local col, row = math.floor(x * COLS), math.floor(y * ROWS)
            if col >= 0 and col < COLS and row >= 0 and row < ROWS then
                local k, edge = row * COLS + col, c.look == "ink" and EDGE or EDGE * 0.6
                for _, gr in pairs(groups) do
                    if gr.sh and (gr.sh.f[k] or 0) >= edge then inside[gr] = true end
                end
            end
        end
        -- each quest's things: the nearest spawn of each
        local best = {}
        for _, d in ipairs(drawn) do
            local dx, dy = (d[1] - x) * 1.5, d[2] - y
            local d2 = dx * dx + dy * dy
            local gr = groups[d[3].id]
            if d2 < HOVER * HOVER or (gr and inside[gr]) then
                local k = tostring(d[3].id) .. (d[4].what or "")
                if not best[k] then
                    best[k] = { d2, d }
                    hits[#hits + 1] = best[k]
                elseif d2 < best[k][1] then
                    best[k][1], best[k][2] = d2, d
                end
            end
        end
        -- a steady order: the smallest ground first (a small spot inside a big area is
        -- what you're pointing at; it's the one lit), then by quest, then each quest's
        -- own order of things. (Sorting by distance made lines jump as the cursor moved.)
        local rank, size = {}, {}
        for _, h in ipairs(hits) do
            local q = h[2][3]
            if not rank[q] then
                rank[q] = {}
                local n = 0
                -- (by name: quiet has a quest's parts both whole, at its dot, and cut to its camp)
                for i, part in ipairs(q.whole or q.parts) do
                    rank[q][part.what or ""] = i
                    n = n + #part.points
                end
                local gr = groups[q.id]
                -- (quiet: by its spawns, what's drawn changes as it's lit, and the quests swapped)
                size[q] = c.quiet ~= false and n or gr and gr.area or n
            end
        end
        table.sort(hits, function(a, b)
            local qa, qb = a[2][3], b[2][3]
            if qa ~= qb then
                if size[qa] ~= size[qb] then return size[qa] < size[qb] end
                return qa.id < qb.id
            end
            return (rank[qa][a[2][4].what or ""] or 0) < (rank[qb][b[2][4].what or ""] or 0)
        end)
        for i = 1, #hits do hits[i] = hits[i][2] end
        for i = #hits, 13, -1 do hits[i] = nil end   -- (12: an item's many droppers fold to one line)
    end
    seenHits = #hits
    onGround = #hits > 0
    if #hits == 0 then
        if tipShown and mine then ns.QuestTooltipLeave() end
        if glowing and ns.HoverQuestGlow then ns.HoverQuestGlow(nil) end
        tipShown, glowing = false, false
        return
    end
    -- (the same things under the cursor: the tooltip stays as it is, following it)
    local keys = {}
    for i, d in ipairs(hits) do keys[i] = tostring(d[3].id) .. (d[4].what or "") end
    local key = table.concat(keys, "|") .. (IsShiftKeyDown() and "+shift" or "")   -- (Shift shows the droppers)
    if tipShown and mine and key == tipKey then return end
    tipKey = key
    if ns.HoverQuestGlow then   -- (its ground lights up)
        ns.HoverQuestGlow(hits[1][3].id)
        glowing = true
    end
    -- (the quests' lines: Pin.lua's ns.QuestSpotLines, shared with objective pins; Questie's with
    -- questie.tooltip on)
    local rows = {}
    for i, d in ipairs(hits) do rows[i] = { quest = d[3], part = d[4] } end
    local folded = false
    if not (ns.GroundQuestieTip and ns.GroundQuestieTip(host, rows)) then
        GameTooltip:SetOwner(host, "ANCHOR_CURSOR_RIGHT", 12, 12)
        folded = ns.QuestSpotLines(rows, c.drops)
    end
    tipQuest, tipInLog = hits[1][3].id, hits[1][3].inLog
    -- (the hints' "Hold Shift" also covers what's folded away)
    if ns.Hints then
        if not IsShiftKeyDown() then
            ns.Hints({ ClickOpens() and { "Click", "open in quest log" } or nil, { "Right-click", "its menu" } })
        end
    elseif folded and ns.HoldShift then
        ns.HoldShift()
    end
    GameTooltip:Show()
    tipShown = true
end

-- Setup --------------------------------------------------------------------------

-- what's drawn depends on: the map, the settings, and which quests show with how
-- many spots (not every quest log update: most change nothing here)
local sigList, sigQuests
local function Signature()
    local c = Cfg()
    local mapID = map:GetMapID()
    local canvas = map:GetCanvas()
    local parts = { tostring(mapID), tostring(ns.IsShown("ground")), tostring(c.alpha), tostring(c.all),
        tostring(c.look), tostring(c.color), tostring(c.colorBy), tostring(math.floor(canvas:GetWidth() + 0.5)),
        tostring(c.arrows), tostring(ns.IsShown("turnins")),
        -- (turn-ins come and go with the log, not with the ground's list)
        c.arrows ~= false and tostring(ns.QuestVersion and ns.QuestVersion()) or "", tostring(c.quiet), tostring(FitScale()) }
    if c.quiet ~= false and mapID then
        -- (what's at hand, and where you are, in big steps: a few rings, so it's a quick redraw)
        parts[#parts + 1] = tostring(stateKey) .. tostring(ns.IsShown("spots"))
        if ns.RouteNow then
            local route, at = ns.RouteNow()
            parts[#parts + 1] = tostring(route) .. tostring(at)
        end
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then parts[#parts + 1] = math.floor(pos.x * WALK) .. "," .. math.floor(pos.y * WALK) end
    end
    if ns.IsShown("ground") and c.look ~= "pins" and mapID and ns.QuestGround then
        -- (QuestData keeps its list until the quests change: summed again only then)
        local list = ns.QuestGround(mapID, c.all)
        if list ~= sigList then
            local qs = {}
            for _, q in ipairs(list) do
                local n = 0
                for _, part in ipairs(q.parts) do n = n + #part.points end
                qs[#qs + 1] = q.id .. (q.inLog and "l" or "a") .. n
            end
            sigList, sigQuests = list, table.concat(qs, ":")
        end
        parts[#parts + 1] = sigQuests
    end
    return table.concat(parts, ":")
end

function ns.SetupQuestGround(m)
    map = m
    local litAt = 1
    hooksecurefunc(map, "OnCanvasScaleChanged", function()
        ns.Safe("QuestGround zoom", function()
            Rethin()
            -- (the game's quest area: its border is in map units too, and bright. Its own
            -- OnCanvasScaleChanged has marked it to redraw, so this is drawn with it)
            local blob = ns.questAreas and ns.questAreas.pin
            if blob and blob.SetBorderScalar then
                local k = ZoomThin()
                blob:SetBorderScalar(k)
                blob:SetBorderAlpha(192 * (0.3 + 0.7 * k))
            end
            -- (what's lit keeps up with the zoom, in steps: it's a redraw)
            local thin = ZoomThin()
            if next(touched) and math.abs(thin - litAt) > 0.04 then
                litAt = thin
                Relight(false)
            end
        end)
    end)
    host = CreateFrame("Frame", nil, map:GetCanvas())
    host:EnableMouse(false)
    host:Hide()
    glow = CreateFrame("Frame", nil, host)
    glow:SetAllPoints(host)
    glow:SetFrameLevel(host:GetFrameLevel() + 1)
    glow:EnableMouse(false)
    glow:SetScript("OnUpdate", function(_, e)
        if not fade then return end
        fade = math.min(1, fade + e / 0.15)
        for _, t in ipairs(gpool.fresh) do t:SetAlpha(fade) end
        if fade >= 1 then
            fade = nil
            wipe(gpool.fresh)
        end
    end)
    if ns.debugFrames then ns.debugFrames.questGround = host end
    -- a right-click on ground with its tooltip up: the menu an objective spot has (Pin.lua),
    -- not a zoom out (Browse.lua asks this first; the user, 2026-11-03)
    function ns.QuestGroundMenuAt()
        if not (tipShown and tipQuest and GameTooltip:IsShown() and TipOurs() and ns.QuillMenu) then return end
        local id, items = tipQuest, {}
        if ns.OpenQuest then items[#items + 1] = { "quest details", function() ns.OpenQuest(id) end } end
        if tipInLog and ns.ToggleFocus then
            items[#items + 1] = { ns.IsFocused(id) and "out of focus" or "focus quest", function() ns.ToggleFocus(id) end }
        end
        if ns.ToggleQuestGlow then items[#items + 1] = { "its spots lit (again: off)", function() ns.ToggleQuestGlow(id) end } end
        if #items == 0 then return end
        GameTooltip:Hide()
        ns.QuillMenu(items)
        return true
    end
    -- a left click (not a drag) on ground with its tooltip up: the quest's page
    local sc = map.ScrollContainer
    if sc then
        local downX, downY
        sc:HookScript("OnMouseDown", function() downX, downY = GetCursorPosition() end)
        sc:HookScript("OnMouseUp", function(_, button)
            if button ~= "LeftButton" or IsModifierKeyDown() or not downX then return end
            local x, y = GetCursorPosition()
            if math.abs(x - downX) + math.abs(y - downY) > 6 * UIParent:GetEffectiveScale() then return end
            if tipShown and tipQuest and GameTooltip:IsShown() and TipOurs() and ClickOpens() then
                ns.OpenQuest(tipQuest)
            end
        end)
    end
    local last, t, job = nil, 0, nil
    local ticker = ns.TimedFrame("QuestGround tick", map)
    ticker:SetScript("OnUpdate", function(_, e)
        if job then                                  -- (a drawing under way: its next slice)
            t0 = debugprofilestop()
            local ok, err = coroutine.resume(job)
            if not ok then ns.Log("Quest ground:", tostring(err)) end
            if coroutine.status(job) == "dead" then job = nil end
        end
        t = t + e
        if t < 0.1 then return end
        t = 0
        if not ns.db then return end
        local ok, sig = pcall(Signature)
        if ok and sig ~= last then
            last = sig
            job = coroutine.create(Draw)             -- (a new one replaces one under way)
        end
        if not job then pcall(Hover) end
    end)
    -- (for /bfi check)
    function ns.QuestGroundInfo()
        return string.format("%d quest spots drawn, %d blobs, %d rim pieces, %d dots, look %s, %d lit pieces; hover: over %s, %d hits, tooltip %s, shown %s",
            #drawn, pool.nb, pool.nl, pool.nd, tostring(Cfg().look), gpool.nl + gpool.nb,
            tostring(seenOver), seenHits, tostring(seenOwner), tostring(host:IsVisible()))
    end
end
