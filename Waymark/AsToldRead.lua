local _, ns = ...

-- As told (the Lab): reading a quest's own words for what the giver TOLD you about where. No game calls in
-- here, so it runs without the game: luajit tools/as_told_test.lua. AsTold.lua keeps and draws what this finds.
--
--   ns.AsToldIndex(places) -> index
--       places: { { name = "Fargodeep Mine", map = 1429, cont = 1415, x, y, rx, ry, zone = true|nil }, ... }
--       (x, y the middle, rx, ry half its width and height, all 0..1 of its map; a zone: the whole map)
--   ns.AsToldRead(index, text, home, cont) -> { telling, ... }
--       home, cont: the map and continent the words were said on (which "Ruins" is meant, when two share a name)
--       telling = { kind = "place", place = <a place>, words = "...", said = "the whole sentence" }
--               | { kind = "dir",  dir = "north-west", place = <a place> or nil (nil: from where it was said), ... }
--               | { kind = "part", dir = "north", place = <a place>, ... }       ("northern Westfall")
--   ns.AsToldVec(dir) -> dx, dy   (map space: north is up, -y)
--
-- English only: the directions are read as words. A name is only taken with its capitals, as written.

local LOWER_TAILS = { " Forest", " Mountains", " Vale", " Foothills", " Highlands", " Glades", " Marsh", " Crater", " City" }

local DIRS = {
    north = { 0, -1 }, south = { 0, 1 }, east = { 1, 0 }, west = { -1, 0 },
    ["north-east"] = { 1, -1 }, ["north-west"] = { -1, -1 }, ["south-east"] = { 1, 1 }, ["south-west"] = { -1, 1 },
}
function ns.AsToldVec(dir)
    local v = DIRS[dir]
    if not v then return 0, 0 end
    local n = (v[1] * v[1] + v[2] * v[2]) ^ 0.5
    return v[1] / n, v[2] / n
end

-- "northwest", "north west", "north-west", "northwestern" at s[i..]: the direction, where it ends, whether it had
-- "-ern" (a part of somewhere, not a way to go)
local function DirAt(low, i)
    local a = low:match("^north", i) or low:match("^south", i) or low:match("^east", i) or low:match("^west", i)
    if not a then return nil end
    local j = i + #a
    local dir = a
    if a == "north" or a == "south" then
        local sep, b = low:match("^([%- ]?)(east)", j)
        if not b then sep, b = low:match("^([%- ]?)(west)", j) end
        if b then
            dir = a .. "-" .. b
            j = j + #sep + #b
        end
    end
    local ern = false
    if low:match("^ern", j) then
        ern = true
        j = j + 3
    elseif low:match("^erly", j) then
        j = j + 4
    elseif low:match("^ward", j) then
        j = j + 4
        if low:match("^s", j) then j = j + 1 end
    end
    if low:match("^%a", j) then return nil end   -- "eastvale", "westfall", "northshire"
    return dir, j, ern
end

function ns.AsToldIndex(places)
    local index = { first = {}, n = 0 }
    local function Add(name, p, alias)
        if #name < 4 then return end
        local first = name:match("^[^%s]+")
        local list = index.first[first]
        if not list then
            list = {}
            index.first[first] = list
        end
        local e
        for _, o in ipairs(list) do
            if o.name == name then e = o break end
        end
        if not e then
            e = { name = name, places = {}, alias = alias }
            list[#list + 1] = e
        end
        e.places[#e.places + 1] = p
        index.n = index.n + 1
    end
    for _, p in ipairs(places) do
        local name = p.name:gsub("^The ", "")
        -- (a short single word, "Den", "Park": only with "the" in front of it, as the giver would say a place)
        p.needsThe = (p.name ~= name) and not name:find(" ") and #name < 6 or nil
        Add(name, p)
        for _, tail in ipairs(LOWER_TAILS) do
            if #name > #tail + 3 and name:sub(-#tail) == tail and (p.zone or tail == " City") then
                Add(name:sub(1, -#tail - 1), p, true)
            end
        end
    end
    for _, list in pairs(index.first) do
        table.sort(list, function(a, b) return #a.name > #b.name end)
    end
    return index
end

local function Pick(e, home, cont)
    local best, score = nil, -1
    for _, p in ipairs(e.places) do
        local s = (p.map == home and 4 or 0) + (p.cont == cont and 2 or 0) + (p.zone and 0 or 1)
        if s > score then best, score = p, s end
    end
    return best
end

-- every place named in s: { from, to, place }, in order, the longest name at each spot
local function Names(index, s, home, cont)
    local out = {}
    local i = 1
    while true do
        local a, b = s:find("%u[%a']*", i)
        if not a then break end
        local word = s:sub(a, b)
        local list = index.first[word] or index.first[word:gsub("'s$", "")]
        local hit
        if list then
            for _, e in ipairs(list) do
                if s:sub(a, a + #e.name - 1) == e.name and not s:match("^%a", a + #e.name) then
                    local p = Pick(e, home, cont)
                    if p and (not p.needsThe or s:sub(math.max(1, a - 4), a - 1):lower() == "the ") then
                        hit = { from = a, to = a + #e.name - 1, place = p, alias = e.alias }
                        break
                    end
                end
            end
        end
        if hit then
            out[#out + 1] = hit
            i = hit.to + 1
        else
            i = b + 1
        end
    end
    return out
end

local function Sentences(text)
    local out = {}
    text = text:gsub("%s*\r?\n%s*", "\n")
    for para in text:gmatch("[^\n]+") do
        local from = 1
        while from <= #para do
            local a, b = para:find("[%.%!%?]+[\"']?%s+", from)
            local s = para:sub(from, a and b or #para):gsub("^%s+", ""):gsub("%s+$", "")
            if #s > 0 then out[#out + 1] = s end
            if not a then break end
            from = b + 1
        end
    end
    return out
end

-- the few words round s[from..to] that say it, short enough to pencil by a ring: back to the clause's start,
-- five words at most, and on to the clause's end, three at most
local LEADS = { "as well as ", "and ", "or ", "but ", "then " }
local function Words(s, from, to)
    if #s <= 44 then return s end
    local head = s:sub(1, from - 1)
    local cut = 1
    for pos in head:gmatch("()[,;:]%s") do cut = pos + 2 end
    head = head:sub(cut)
    local words = {}
    for w in head:gmatch("%S+") do words[#words + 1] = w end
    local keep = 5
    local lead = #words > keep
    if lead then
        local t = {}
        for k = #words - keep + 1, #words do t[k - (#words - keep)] = words[k] end
        words = t
    end
    local before = table.concat(words, " ")
    for _ = 1, 2 do
        for _, lead in ipairs(LEADS) do
            if before:sub(1, #lead):lower() == lead then before = before:sub(#lead + 1) lead = nil break end
        end
    end
    local tail = s:sub(to + 1)
    local stop = tail:find("[,;:%.%!%?]") or (#tail + 1)
    for _, w in ipairs({ " and ", " or ", " as ", " where ", " but ", " until " }) do
        local at = tail:find(w, 1, true)
        if at and at < stop then stop = at end
    end
    local after, n = "", 0
    for w in tail:sub(1, stop - 1):gmatch("%S+") do
        n = n + 1
        if n > 3 then after = after .. "..." break end
        after = after .. " " .. w
    end
    local out = ((lead or cut > 1) and "..." or "") .. before .. (before ~= "" and " " or "") .. s:sub(from, to) .. after
    return out
end

local PREP = {}
for w in ("in at to near from around by inside outside toward towards into within through past beyond on above below under behind across over reach visit find search scout"):gmatch("%a+") do PREP[w] = true end
local HERE = { "of here", "from here", "of town", "of us", "of this", "of the camp", "of camp", "of my", "of our" }
local GO = { "to the ", "head ", "travel ", "go ", "lies ", "lie ", "ride ", "walk ", "journey ", "far ", "due ", "directly ", "just " }

function ns.AsToldRead(index, text, home, cont)
    local out, seen = {}, {}
    local function Tell(t)
        local key = t.kind .. ":" .. (t.dir or "") .. ":" .. (t.place and (t.place.map .. t.place.name) or "here")
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = t
    end
    local prev   -- the last place the sentence before named
    for _, s in ipairs(Sentences(text or "")) do
        local names = Names(index, s, home, cont)
        local low = s:lower()
        local used = {}
        -- the directions in it
        local i = 1
        for a in low:gmatch("%f[%a]()") do
            local dir, j, ern
            if a >= i then dir, j, ern = DirAt(low, a) end
            if dir then
                local rest = low:sub(j)
                local told
                if ern then
                    -- "northern Westfall", "the western edge of Elwynn"
                    for n, nm in ipairs(names) do
                        if nm.from >= j and nm.from - j <= 28 and not s:sub(j, nm.from - 1):find("[,;%.]") then
                            told = { kind = "part", dir = dir, place = nm.place, from = a, to = nm.to }
                            used[n] = true
                            break
                        end
                    end
                elseif rest:match("^ of ") or rest:match("^ from ") then
                    local skip = rest:match("^ of ()") or rest:match("^ from ()")
                    local inPart = low:sub(math.max(1, a - 7), a - 1) == "in the "
                    for n, nm in ipairs(names) do
                        if nm.from >= j + skip - 1 and nm.from - (j + skip - 1) <= 5 then
                            told = { kind = inPart and "part" or "dir", dir = dir, place = nm.place, from = a, to = nm.to }
                            used[n] = true
                            break
                        end
                    end
                    if not told then
                        for _, h in ipairs(HERE) do
                            if rest:sub(2, #h + 1) == h then told = { kind = "dir", dir = dir, from = a, to = j + #h } break end
                        end
                    end
                else
                    for _, g in ipairs(GO) do
                        if a > #g and low:sub(a - #g, a - 1) == g then
                            -- ("cut right into the west and east sides": "into the" is no way to go; "if a
                            -- scouting party went that far south": nor is "that far". The checker, 2026-11-15.)
                            local at = a - #g
                            local no = (g == "to the " and low:sub(at - 1, at - 1):match("%a") ~= nil)
                                    or (g == "far " and low:sub(math.max(1, at - 5), at - 1) == "that ")
                            if not no then told = { kind = "dir", dir = dir, from = at, to = j - 1 } end
                            break
                        end
                    end
                end
                -- ("the Fargodeep Mine to the south", "at Stone Cairn Lake north of here": the place itself says it)
                if told and not told.place then
                    for _, nm in ipairs(names) do
                        if nm.to < told.from and told.from - nm.to <= 2 then told = nil break end
                    end
                end
                -- ("...until you reach the Tower of Azora, then head north": north from the tower, not from here)
                if told and not told.place then
                    for n = #names, 1, -1 do
                        local nm = names[n]
                        if nm.to < told.from then
                            local between = low:sub(nm.to + 1, told.from - 1)
                            if between:find("then ") or between:find("from there") or between:find("after that") then
                                told.place = nm.place
                            end
                            break
                        end
                    end
                    -- ("From the tower, head north": the place the sentence before ended on)
                    local lead = low:sub(1, told.from - 1)
                    if not told.place and prev and (lead:find("^from th") or lead:find("from there")) then told.place = prev end
                end
                if told then
                    told.said = s
                    told.words = Words(s, told.from, told.to)
                    told.from, told.to = nil, nil
                    Tell(told)
                end
                i = j
            end
        end
        -- the places in it. One of this map's own is taken as said; a zone or a far place only where the words
        -- put something there ("in Lakeshire", "to Stormwind"), not where it's only spoken of ("Stormwind has
        -- abandoned us"); the zone you stand in is never news
        local chain = false
        for n, nm in ipairs(names) do
            local p = nm.place
            local ok = not used[n]
            if ok and p.zone and p.map == home then ok = false end
            -- ("the Stormwind Army", "Westfall Stew": a name on something else)
            if ok and s:match("^ %u", nm.to + 1) then ok = false end
            if ok and (p.zone or p.map ~= home or nm.alias) then
                local before = low:sub(math.max(1, nm.from - 14), nm.from - 1):gsub("the $", "")
                local word = before:match("(%a+)[%s]*$")
                local sep = before:match("([,%a]+)%s*$")
                ok = (word and PREP[word]) or (chain and (word == "and" or word == "or" or (sep and sep:sub(-1) == ","))) or false
            end
            if ok then
                Tell({ kind = "place", place = p, said = s, words = Words(s, nm.from, nm.to) })
            end
            chain = ok or used[n] or false
        end
        prev = names[#names] and names[#names].place or nil
    end
    return out
end

-- A town you are sent back to, or where the one you bring it to stands, is no place to find (the user,
-- 2026-11-13: "Return to x-town, go east of X-town, Talk to x in x town, doesnt give a circle"):
--   "return to / back to / report to <place>", and "to|for|with|from <Name Name> in|at <place>".
-- "Kill 8 Defias Pillagers in Moonbrook" still rings Moonbrook: no "to" before the capitals.
-- "Travel to Lakeshire in the Redridge Mountains" is a place in a place, not a person: places = the names this
-- quest tells of. Also true for a place measured from: "east of Auberdine".
-- And where the one who asks stands, as an objective line says it: "Shayla Nightbreeze on the road outside of
-- Darnassus wants you to bring her 15 Gnarlpine Fangs" (the user's shots, 2026-11-24: Darnassus marked for a
-- bounty on the furbolgs by Dolanaar). The place, then what they want of you or how many of a thing.
-- "... in Goldshire wants to see you" still sends you there: no "you to", no number.
local ASKS = { "wants you to ", "needs you to ", "asks you to ", "wishes you to ", "requires you to ", "expects you to ",
               "would like you to ", "has asked you to ", "is asking you to ", "wants %d", "needs %d", "would like %d",
               "requests %d", "requires %d" }
local function Errand(said, name, places)
    local at = said and name and said:lower():find(name:lower(), 1, true)
    if not at then return false end
    local after = said:sub(at + #name):lower():gsub("^%s+", "")
    for _, a in ipairs(ASKS) do
        if after:find("^" .. a) then return true, "back" end
    end
    local before = said:sub(1, at - 1):gsub("[Tt]he%s+$", "")
    local low = before:lower()
    -- ("the shores of Lake Everstill" is the place itself: only a direction measures)
    local way = low:match("(%a+)%s+of%s+$")
    if way and (way:find("north") or way:find("south") or way:find("east") or way:find("west")) then return true, "from" end
    if low:match("return to%s+$") or low:match("back to%s+$") or low:match("report to%s+$") or low:match("returning to%s+$") then return true, "back" end
    local head = before:match("^(.-)%s+[Ii]n%s+$") or before:match("^(.-)%s+[Aa]t%s+$")
    if not head then return false end
    -- ("bring it back to her in Menethil Harbor", "Return to him in Booty Bay": the checker, 2026-11-15)
    do
        local w, pro = low:match("(%a+)%s+(%a+)%s+%a+%s+$")
        if (pro == "him" or pro == "her" or pro == "me" or pro == "them") and (w == "to" or w == "for" or w == "with" or w == "from") then
            local home = w == "for" or (w == "to" and (low:find("return", 1, true) or low:find("back to", 1, true)) ~= nil)
            return true, home and "back" or "who"
        end
    end
    local names, who = 0, nil
    while true do
        local rest, w = head:match("^(.-)%s*(%S+)$")
        if not w then return false end
        if w:match("^%u") then
            names = names + 1
            who = who and (w .. " " .. who) or w
            head = rest
        elseif names > 0 and (w == "the" or w == "del" or w == "de" or w == "van" or w == "von") and rest:match("%u%S*$") then
            -- ("Uthek the Wise", "Talvash del Kissel": a small word inside a name)
            who = w .. " " .. who
            head = rest
        else
            if places and who and places[who] then return false end
            -- (the second word back: "for" a person there, or brought "to" one in a sentence that returns, is
            -- the town the quest comes home to; "talk to", "speak with", "deliver to" may send you away to it)
            local ok = names > 0 and (w == "to" or w == "for" or w == "with" or w == "from")
            local home = ok and (w == "for" or (w == "to" and (low:find("return", 1, true) or low:find("back to", 1, true)) ~= nil))
            return ok, ok and (home and "back" or "who") or nil
        end
    end
end
ns.ToldErrand = Errand

-- The towns a quest comes home to or measures from, anywhere in its words: { [name] = true }. A telling keeps
-- only the first sentence that names a place, so the rule above alone missed a town spoken of early and returned
-- to at the end (the user, 2026-11-15, The Cliffspring River: "I fear the wash will affect Auberdine soon" ...
-- "Return to Thundris Windweaver in Auberdine", and Auberdine was ringed). Not a town you are sent to: "talk to
-- Wiley in Lakeshire" unrings Lakeshire only in its own sentence, as before; "Travel to Lakeshire" still rings it.
function ns.AsToldErrands(text, names)
    local out = {}
    local list = Sentences(text or "")
    for name in pairs(names) do
        for _, s in ipairs(list) do
            local ok, kind = Errand(s, name, names)
            if ok and kind ~= "who" then out[name] = true break end
        end
    end
    return out
end

-- Places a quest only speaks of in passing, by hand: [questID] = "the place's name" (more than one: "A|B").
-- Word rules can't tell "my brother and I run an apothecary in Stormwind" from "seek out Felicia Gump in her
-- shop in Stormwind". Each was listed by the checker (tools/as_told_audit.lua, "far": a ring with nothing of
-- the quest within 500 yards) and then read; a listed ring the giver does send you to was left alone.
local ASIDE = {
    [60] = "Stormwind City", [729] = "Ironforge", [89] = "Stormwind City", [112] = "The Maclure Vineyards", [122] = "Goldshire",
    [125] = "Goldshire", [216] = "Splintertree Post", [224] = "Ironforge", [255] = "Ironforge", [382] = "Brill",
    [464] = "Grim Batol", [536] = "Stormwind City", [543] = "Ironforge", [562] = "Stormwind City",
    [568] = "Stonard", [580] = "Stormwind City", [581] = "Zul'Gurub", [608] = "Crystal Lake",
    [658] = "Tarren Mill", [699] = "Stonard", [706] = "Ironforge", [757] = "Thunder Bluff",
    [833] = "Thunder Bluff", [868] = "Orgrimmar", [877] = "The Forgotten Pools", [879] = "The Crossroads",
    [951] = "The Master's Glaive", [966] = "Auberdine", [1187] = "Gadgetzan", [1648] = "Stormwind City",
    [1802] = "Menethil Harbor", [1803] = "Ironforge", [2875] = "Gadgetzan", [2877] = "Ironforge",
    [4921] = "Gold Road", [5168] = "Darrowshire", [5181] = "Darrowshire", [5501] = "Shadowprey Village",
    [6441] = "Ratchet", [7223] = "Ironforge", [8856] = "Cenarion Hold", [8963] = "Starbreeze Village",
    [8985] = "Starbreeze Village",
}

-- And ways the giver only speaks of, by hand: [questID] = the direction, for an arrow "from here". "The human
-- and dwarven lands to the south" reads like "wolves and bats to the south"; only one of them is where to go.
-- Each was listed by the checker ("arrow") and then read.
local NOWAY = { [421] = "south", [1465] = "south", [8465] = "south" }

-- What each telling of a quest becomes on the map, by the words alone (where things lie is the caller's part):
--   out[i] = "ring", "plain" (a ring without the name: a place only spoken of as the quest opens, when it names
--            others after), "part", "arrow", or nil (a town to go back to or to measure from: nothing).
-- One rule for the game (AsTold.lua) and for the checker (tools/as_told_audit.lua).
function ns.AsToldMarks(tellings, text, obj, id)
    text = text or ""
    local aside = id and ASIDE[id]
    local named = {}
    for _, t in ipairs(tellings) do
        if t.place then named[t.place.name] = true end
    end
    local errands = ns.AsToldErrands(text .. "\n" .. (obj or ""), named)
    -- ("Thanks to you we know the Fargodeep Mine is infested" is not where this quest sends you when it names
    -- other places after it)
    local function Opening(t)
        local at = t.said and text:find(t.said, 1, true)
        return at and at <= 3
    end
    local later = false
    for _, t in ipairs(tellings) do
        if t.kind == "place" and t.place and not Opening(t) then later = true end
    end
    local out = {}
    for i, t in ipairs(tellings) do
        if t.kind == "place" and t.place then
            if not (Errand(t.said, t.place.name, named) or errands[t.place.name] or (aside and aside:find(t.place.name, 1, true))) then
                out[i] = (later and Opening(t)) and "plain" or "ring"
            end
        elseif t.kind == "part" then out[i] = "part"
        elseif t.kind == "dir" and not (id and not t.place and NOWAY[id] == t.dir) then out[i] = "arrow" end
    end
    return out
end
-- An arrow toward where a ring of the same quest already lies says nothing the ring doesn't: is the way to the
-- ring (vx, vy) within 60 degrees of the arrow (dx, dy, one long)? Both in the same flat measure.
function ns.AsToldToward(dx, dy, vx, vy)
    local d = math.sqrt(vx * vx + vy * vy)
    return d > 0 and (vx * dx + vy * dy) / d >= 0.5
end

-- The places on our maps, from the overlays' own list (Data\MapOverlays.lua): each area a zone map names, with
-- the box it's drawn in, and each zone whole. AreaName(areaID) and MapInfo(mapID) -> name, parent map: the
-- game's in the game, the tables' in the test.
local ART_W, ART_H = 1002, 668
function ns.AsToldPlaces(overlays, AreaName, MapInfo)
    local places = {}
    for mapID, list in pairs(overlays) do
        local zone, cont = MapInfo(mapID)
        if zone then
            places[#places + 1] = { name = zone, map = mapID, cont = cont, x = 0.5, y = 0.5, rx = 0.5, ry = 0.5, zone = true }
            local byName = {}
            for _, o in ipairs(list) do
                local l, r, t, b = o[7], o[8], o[5], o[6]
                if r - l < 8 or b - t < 8 then
                    l, r, t, b = o[3] + o[1] * 0.2, o[3] + o[1] * 0.8, o[4] + o[2] * 0.2, o[4] + o[2] * 0.8
                end
                for i = 10, #o do
                    local name = AreaName(o[i])
                    if name and name ~= "" and name ~= zone then
                        local p = byName[name]
                        if not p then
                            p = { name = name, map = mapID, cont = cont, l = l, r = r, t = t, b = b }
                            byName[name] = p
                            places[#places + 1] = p
                        else
                            p.l, p.r, p.t, p.b = math.min(p.l, l), math.max(p.r, r), math.min(p.t, t), math.max(p.b, b)
                        end
                    end
                end
            end
            for _, p in pairs(byName) do
                p.x, p.y = (p.l + p.r) / 2 / ART_W, (p.t + p.b) / 2 / ART_H
                p.rx, p.ry = (p.r - p.l) / 2 / ART_W, (p.b - p.t) / 2 / ART_H
                p.l, p.r, p.t, p.b = nil, nil, nil, nil
            end
        end
    end
    return places
end
