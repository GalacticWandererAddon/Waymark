local _, ns = ...

-- The pencilled map: the ground you have walked, and what to paint for it. No game calls in this file
-- (tools\pencil_walk_test.lua runs it under plain Lua). The drawing is Pencil.lua.
--
-- A zone map is cut into GW x GH squares. A square is walked once you have stood within reach of its
-- middle. A walked square with an unwalked neighbour is on the rim; the rest are inside.
--   inside squares are painted as plain rectangles, runs of them joined along a row, and a whole
--     256 px tile of art in one piece when everything under it is inside;
--   rim squares are painted as a larger square through a soft round blot, so the colour ends in an
--     uneven blurred line and neighbouring blots run together.
-- A record is a table { [index] = true }, index = row * GW + column + 1, rows from the top.

local W = {}
ns.PencilWalk = W

W.GW, W.GH = 48, 32
W.BLOT = 3.0          -- a rim square's painted square, in squares across: wide, so its soft blot fades out well past the square

local GW, GH = W.GW, W.GH

function W.Index(col, row) return row * GW + col + 1 end

-- Stand at (u, v), 0..1 across and down the map, reaching ru and rv of the map's width and height.
-- Marks the squares whose middle is within reach, and always the one you stand in. Returns the new ones.
function W.Mark(rec, u, v, ru, rv)
    if not (u and v) or u < 0 or u > 1 or v < 0 or v > 1 then return nil end
    local col, row = math.min(GW - 1, math.floor(u * GW)), math.min(GH - 1, math.floor(v * GH))
    local new
    local nc, nr = math.ceil(ru * GW), math.ceil(rv * GH)
    for r = math.max(0, row - nr), math.min(GH - 1, row + nr) do
        for c = math.max(0, col - nc), math.min(GW - 1, col + nc) do
            local du, dv = ((c + 0.5) / GW - u) / ru, ((r + 0.5) / GH - v) / rv
            if (c == col and r == row) or du * du + dv * dv <= 1 then
                local i = W.Index(c, r)
                if not rec[i] then
                    rec[i] = true
                    new = new or {}
                    new[#new + 1] = i
                end
            end
        end
    end
    return new
end

-- Every square whose middle lies in one of the boxes { left, top, right, bottom } (in art pixels) is walked:
-- what the game already calls explored, taken over once.
function W.Seed(rec, boxes, aw, ah)
    local cw, ch = aw / GW, ah / GH
    for _, b in ipairs(boxes) do
        for r = math.max(0, math.floor(b[2] / ch)), math.min(GH - 1, math.floor(b[4] / ch)) do
            for c = math.max(0, math.floor(b[1] / cw)), math.min(GW - 1, math.floor(b[3] / cw)) do
                local x, y = (c + 0.5) * cw, (r + 0.5) * ch
                if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] then rec[W.Index(c, r)] = true end
            end
        end
    end
end

-- The ground between the areas: a square in no box at all belongs to the box nearest its middle, and is
-- walked once that area is found (boxes: every area's, { left, top, right, bottom, on = found }). So
-- mountains and shore no area covers fill with their neighbour, and a zone with every area found is whole.
function W.SeedNear(rec, boxes, aw, ah)
    local cw, ch = aw / GW, ah / GH
    for r = 0, GH - 1 do
        for c = 0, GW - 1 do
            local i = W.Index(c, r)
            if not rec[i] then
                local x, y = (c + 0.5) * cw, (r + 0.5) * ch
                local best, on
                for _, b in ipairs(boxes) do
                    local dx = math.max(b[1] - x, 0, x - b[3])
                    local dy = math.max(b[2] - y, 0, y - b[4])
                    local d = dx * dx + dy * dy
                    if d == 0 then best = 0 on = false break end     -- in a box: that area's own business
                    if not best or d < best then best, on = d, b.on end
                end
                if on then rec[i] = true end
            end
        end
    end
end

-- The same, from what each area really paints (Data\PencilCover.lua: cover = { sets, runs }): a square
-- is walked once any piece that paints it is found (found[piece's place in the zone's list] = true). Every
-- square has pieces (the bake gives bare ones their neighbour's), so a zone with every area found is whole.
local function Cells(cover)
    local cells = cover.cells
    if not cells then
        cells = {}
        local runs = cover.runs
        for i = 1, #runs, 2 do
            for _ = 1, runs[i + 1] do cells[#cells + 1] = runs[i] end
        end
        cover.cells = cells
    end
    return cells
end

function W.SeedCover(rec, cover, found)
    local cells = Cells(cover)
    local on = {}
    for s, set in ipairs(cover.sets) do
        for _, k in ipairs(set) do
            if found[k] then on[s] = true break end
        end
    end
    for i = 1, GW * GH do
        if on[cells[i]] then rec[i] = true end
    end
end

-- The zone's border (cover.edge, from the outline the pencil is cut to: 0 inside, 1 border, 2 outside).
local function Edge(cover)
    local e = cover and cover.edgeCells
    if e or not (cover and cover.edge) then return e end
    e = {}
    for i = 1, #cover.edge, 2 do
        for _ = 1, cover.edge[i + 1] do e[#e + 1] = cover.edge[i] end
    end
    cover.edgeCells = e
    return e
end

-- No pencil line left along the zone's border beside ground you have filled (the user, 2026-11-14: "This
-- penciled line is still showing between darkshore and felwood": the ridge on the border belonged to an
-- area not yet found). A border square within two squares of walked ground is walked too. One pass, from
-- the ground as it was: it does not creep along the border.
function W.SeedBorder(rec, cover)
    local e = Edge(cover)
    if not e then return false end
    local add
    for i = 1, GW * GH do
        if e[i] == 1 and not rec[i] then
            local c, r = (i - 1) % GW, math.floor((i - 1) / GW)
            local near = false
            for rr = math.max(0, r - 2), math.min(GH - 1, r + 2) do
                for cc = math.max(0, c - 2), math.min(GW - 1, c + 2) do
                    if rec[W.Index(cc, rr)] then near = true break end
                end
                if near then break end
            end
            if near then
                add = add or {}
                add[#add + 1] = i
            end
        end
    end
    if not add then return false end
    for _, i in ipairs(add) do rec[i] = true end
    return true
end

-- Takes the border squares out of a record again. (Until 2026-11-14 SeedBorder was run on the saved record at
-- every repaint, so each repaint walked the colour two squares farther along the border: the user saw the zone
-- fill by clicking a switch. The border is now filled on a copy, for the picture only; this cleans what the
-- old way left behind. What the game calls explored comes back by SeedCover, the rest by the border rule.)
function W.DropBorder(rec, cover)
    local e = Edge(cover)
    if not e then return end
    for i in pairs(rec) do
        if e[i] == 1 then rec[i] = nil end
    end
end

-- state[index]: 1 on the rim, 2 inside (the map's own edge is no neighbour: a square there can be inside;
-- nor is a square outside the zone's outline, when cover is given: no pencil is drawn there, so painted
-- ground ends at the outline instead of fading into a line of pencil along it)
function W.States(rec, cover)
    local e = Edge(cover)
    local state = {}
    for i in pairs(rec) do
        local c, r = (i - 1) % GW, math.floor((i - 1) / GW)
        local inside = true
        for dr = -1, 1 do
            for dc = -1, 1 do
                local cc, rr = c + dc, r + dr
                if cc >= 0 and cc < GW and rr >= 0 and rr < GH and not rec[W.Index(cc, rr)]
                    and not (e and e[W.Index(cc, rr)] == 2) then inside = false end
            end
        end
        state[i] = inside and 2 or 1
    end
    return state
end

-- Sighted land -----------------------------------------------------------------------------------------
-- (the user, 2026-11-14: "land you've seen, or atleast land you've been kind of near, rest staying
-- unexplored. Because a zone in full pencil is a bit overwhelming on the eye.")
-- What you see from where you stand, on the zone's baked ground (Data\PencilHeights.lua: FW x FH
-- cells, two a square each way):
--   everything within `near` yards, always: the land you are kind of near;
--   farther land when it lies well below you or stands well above you: each yard of difference in height
--     (past `clutter`, the trees and roofs between) reaches `gain` yards farther, out to `far`. So level
--     ground shows only what is near, a hilltop shows the valley, and a mountain shows from the plain;
--   and only with a clear line to it: the ground between, with its trees, must not stand in the way (the
--     land within `near` never does: you see past what is round you).
-- up: yards above the ground you are (a flight path). No heights for the zone: the near land only.
W.FW, W.FH = 96, 64
W.SIGHT = { near = 220, far = 900, gain = 12, clutter = 8, eye = 2.5, saddle = 80, share = 0.2 }
local FW, FH = W.FW, W.FH

local function Heights(h)
    local cells = h.cells
    if not cells then
        cells = {}
        local s, lv = h.s, h.lv
        for i = 1, #s do cells[i] = lv[s:byte(i) - 34] end
        h.cells = cells
    end
    return cells
end

-- The squares in sight from (u, v), 0..1 across and down a map zw by zh yards: { [index] = true }, or nil
-- off the map.
function W.Sight(h, u, v, zw, zh, up)
    if not (u and v) or u < 0 or u > 1 or v < 0 or v > 1 then return nil end
    local o = W.SIGHT
    local cells = h and Heights(h)
    local cw, ch = zw / FW, zh / FH
    local fc, fr = math.min(FW - 1, math.floor(u * FW)), math.min(FH - 1, math.floor(v * FH))
    local ground = cells and cells[fr * FW + fc + 1]
    local eye = ground and ground + o.eye + (up or 0)
    local reach = cells and o.far or o.near
    local nc, nr = math.ceil(reach / cw), math.ceil(reach / ch)
    local seen = {}
    for r = math.max(0, fr - nr), math.min(FH - 1, fr + nr) do
        for c = math.max(0, fc - nc), math.min(FW - 1, fc + nc) do
            local dx, dy = (c - fc) * cw, (r - fr) * ch
            local d = math.sqrt(dx * dx + dy * dy)
            local ok = d <= o.near
            if not ok and cells and d <= o.far then
                local there = cells[r * FW + c + 1]
                if d <= o.near + o.gain * (math.abs(there - eye) - o.clutter) then
                    local top = there + o.clutter
                    local n = math.max(math.abs(c - fc), math.abs(r - fr))
                    ok = true
                    for k = 1, n - 1 do
                        local t = k / n
                        if t * d > o.near then
                            local cc, rr = math.floor(fc + (c - fc) * t + 0.5), math.floor(fr + (r - fr) * t + 0.5)
                            if cells[rr * FW + cc + 1] + o.clutter > eye + (top - eye) * t + 0.01 then ok = false break end
                        end
                    end
                end
            end
            if ok then seen[W.Index(math.floor(c / 2), math.floor(r / 2))] = true end
        end
    end
    return seen
end

-- The squares within rc, rr squares (they need not be whole numbers) of walked ground, in the round: what a
-- character who walked here before Sighted land existed has been near.
-- With cover, walked squares outside the zone's outline are no ground to have been near from (a found area
-- fills out to the sheet's edge, over sea and the neighbouring zones: that is not land you stood on).
function W.Near(rec, rc, rr, cover)
    local seen = {}
    local e = cover and Edge(cover)
    local nc, nr = math.floor(rc), math.floor(rr)
    for i in pairs(rec) do
        local c, r = (i - 1) % GW, math.floor((i - 1) / GW)
        if e and e[i] == 2 then c = nil end
        if c then
        for y = math.max(0, r - nr), math.min(GH - 1, r + nr) do
            for x = math.max(0, c - nc), math.min(GW - 1, c + nc) do
                local dx, dy = (x - c) / rc, (y - r) / rr
                if dx * dx + dy * dy <= 1 then seen[W.Index(x, y)] = true end
            end
        end
        end
    end
    return seen
end

-- Which areas has that sighted? An area (a piece of the zone's art, by its place in the zone's list) is
-- sighted once you have seen a good part of it: W.SIGHT.share of the squares it paints, counted over
-- everything you have seen so far (`seen` is kept and added to: Pencil.lua). Squares outside the zone's
-- outline do not count. Returns the pieces not yet in `have`, or nil.
-- (It was "an eighth, six squares at most, in view at once": six squares at the edge of a large area sketched
-- all of it. The user, 2026-11-14, of a Westfall sketched to its far corner: "Can one really spot the lower
-- southeast from sentinel hill?")
function W.SightPieces(cover, seen, have)
    local cells, e = Cells(cover), Edge(cover)
    local size = cover.size
    if not size then
        size = {}
        for i = 1, GW * GH do
            if not (e and e[i] == 2) then
                for _, k in ipairs(cover.sets[cells[i]] or {}) do size[k] = (size[k] or 0) + 1 end
            end
        end
        cover.size = size
    end
    local count = {}
    for i in pairs(seen) do
        if not (e and e[i] == 2) then
            for _, k in ipairs(cover.sets[cells[i]] or {}) do count[k] = (count[k] or 0) + 1 end
        end
    end
    local new
    for k, n in pairs(count) do
        if not have[k] and n >= math.max(1, math.ceil((size[k] or 0) * W.SIGHT.share)) then
            new = new or {}
            new[#new + 1] = k
        end
    end
    return new
end

-- Only the part seen (the user, 2026-11-15, of whole areas sketched once a fifth of them was seen: "I thought
-- this was how it was supposed to work? not fill in big areas if i get closeish").
-- An area's sketch is still laid whole, and the part of it you have not seen is put back as the map was:
-- Pencil.lua lays the game's own ground over it, by the same squares and soft blots as the walked paint.
--   hide   the squares to put back: inside the outline, not seen, and no seen square beside them. (The one
--          square of grace is for the blots: a rim square's blot reaches a square past its own, so without it
--          the sketch would stop a square short of what you saw and a lone seen square would not show at all.)
--   show   the areas with anything to show: those that paint a square not hidden.
-- A seen square outside the outline is no ground to be beside.
function W.Unseen(cover, seen)
    local cells, e = Cells(cover), Edge(cover)
    local hide, show = {}, {}
    for i = 1, GW * GH do
        if not (e and e[i] == 2) then
            local open = seen[i]
            if not open then
                local c, r = (i - 1) % GW, math.floor((i - 1) / GW)
                for rr = math.max(0, r - 1), math.min(GH - 1, r + 1) do
                    for cc = math.max(0, c - 1), math.min(GW - 1, c + 1) do
                        local j = W.Index(cc, rr)
                        if seen[j] and not (e and e[j] == 2) then open = true end
                    end
                end
            end
            if open then
                for _, k in ipairs(cover.sets[cells[i]] or {}) do show[k] = true end
            else
                hide[i] = true
            end
        end
    end
    return hide, show
end

-- What to paint. sources: the zone's art as tiles { x, y, w, h, ... } in art pixels (the base tiles, then
-- each piece's, in the order they lie over one another). Returns a list of
--   { src = source, l, t, r, b [, cell = index, cx, cy] }   in art pixels
-- source by source, so laying them in this order keeps each piece over the ones under it. A quad with
-- `cell` is a rim square's: it goes through the blot centred at (cx, cy).
function W.Quads(sources, state, aw, ah)
    local cw, ch = aw / GW, ah / GH
    -- runs of inside squares along each row, and the rim squares
    local runs, rim = {}, {}
    for r = 0, GH - 1 do
        local c = 0
        while c < GW do
            local s = state[W.Index(c, r)]
            if s == 2 then
                local c0 = c
                while c + 1 < GW and state[W.Index(c + 1, r)] == 2 do c = c + 1 end
                runs[#runs + 1] = { c0 * cw, r * ch, (c + 1) * cw, (r + 1) * ch, r }
            elseif s == 1 then
                local cx, cy = (c + 0.5) * cw, (r + 0.5) * ch
                local hw, hh = cw * W.BLOT / 2, ch * W.BLOT / 2
                rim[#rim + 1] = { math.max(0, cx - hw), math.max(0, cy - hh), math.min(aw, cx + hw), math.min(ah, cy + hh),
                                  cell = W.Index(c, r), cx = cx, cy = cy }
            end
            c = c + 1
        end
    end
    local out = {}
    local function Cut(src, rect, extra)
        local l, t = math.max(src.x, rect[1]), math.max(src.y, rect[2])
        local r, b = math.min(src.x + src.w, rect[3]), math.min(src.y + src.h, rect[4])
        if r - l > 0.01 and b - t > 0.01 then
            local q = { src = src, l = l, t = t, r = r, b = b }
            if extra then q.cell, q.cx, q.cy = extra.cell, extra.cx, extra.cy end
            out[#out + 1] = q
        end
    end
    for _, src in ipairs(sources) do
        -- is everything under this tile inside? Then the tile goes down whole.
        local c0, c1 = math.max(0, math.floor(src.x / cw)), math.min(GW - 1, math.ceil((src.x + src.w) / cw) - 1)
        local r0, r1 = math.max(0, math.floor(src.y / ch)), math.min(GH - 1, math.ceil((src.y + src.h) / ch) - 1)
        local whole = true
        for r = r0, r1 do
            for c = c0, c1 do
                if state[W.Index(c, r)] ~= 2 then whole = false break end
            end
            if not whole then break end
        end
        if whole then
            out[#out + 1] = { src = src, l = src.x, t = src.y, r = src.x + src.w, b = src.y + src.h }
        else
            for _, run in ipairs(runs) do
                if run[5] >= r0 and run[5] <= r1 then Cut(src, run) end
            end
        end
        for _, sq in ipairs(rim) do Cut(src, sq, sq) end
    end
    return out, #rim
end
