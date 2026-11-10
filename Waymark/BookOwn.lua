local _, ns = ...

-- The book as a player's own (Notebook.lua draws it; here the rules, as plain table work, so they can
-- be run outside the game: tools\book_own_test.lua). A rule above all: an update never erases or
-- misplaces a player's notes.
--
-- What's a player's lives apart from the shipped book:
--   notebook.mine[id] = { notes = { [i] = { s, gone, crossed, floor, x, y, mark, rs, na, was } },
--                         added = { { s, floor, x, y, mark, rs, na } },
--                         before = { text = { ["diary:2"|"margin"|"bring"] = { s, gone, was } },
--                                    added = { { s } }, marks = { ink }, scene = { ink } } }
--   notebook.marks[id] = { ink on the spread };  db.inkMarks["d<instance>:<floor>"] = { ink on the map }
-- `was` is the book's words a change was made to: notes are kept by number, and new tips shift the
-- numbers, so BookAnchor finds each change's line again by its words.
--
--   ns.BookMigrate(cfg, ink, pages)   1.2's copies (players wrote "as the wanderer" by mistake) into the above
--   ns.BookAnchor(cfg, entry)         each change back on its own line; a line that's gone leaves it as your own
--   ns.BookSetAside / ns.BookBringBack   the reset: nothing is deleted, only set aside
--   ns.BookNoteText / BookPageView / BookBeforeView / BookMapMarks   what a kind of book shows
--     (kinds: "story" all of it, "notes" the tips without the story, "blank" your own pages)

local function Copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = Copy(v) end
    return o
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function Holds(list, m)
    for _, o in ipairs(list or {}) do if Same(o, m) then return true end end
    return false
end

-- a page's own part of mine (made when it's needed)
local function MineOf(cfg, id)
    cfg.mine = cfg.mine or {}
    local m = cfg.mine[id]
    if not m then m = { notes = {}, added = {} } cfg.mine[id] = m end
    return m
end
local function BeforeOf(mine)
    local b = mine.before
    if not b then b = { text = {}, added = {} } mine.before = b end
    b.text, b.added = b.text or {}, b.added or {}
    return b
end
ns.BookMineBefore = BeforeOf

-- Books written in 1.2 ---------------------------------------------------------------------

local NOTE_FIELDS = { "floor", "x", "y", "mark", "rs", "na" }

-- a 1.2 note as a line of your own
local function OwnLine(n)
    local a = { s = n[1] }
    for _, f in ipairs(NOTE_FIELDS) do a[f] = n[f] end
    return a
end

local function TextIndex(list, get)
    local out = {}
    for i, v in ipairs(list or {}) do
        local t = get(v)
        if t and not out[t] then out[t] = i end
    end
    return out
end
local function First(n) return n[1] end
local function Self(s) return s end

-- list of the copy against list of the page it was made from: what stayed, what's new, what went.
-- A new line and a gone line at the same place are one line rewritten.
local function Diff(mine, base, get, rewritten, kept, added, gone)
    local byText, used = TextIndex(base, get), {}
    local fresh = {}
    for i, v in ipairs(mine or {}) do
        local j = byText[get(v)]
        if j and not used[j] then
            used[j] = true
            kept(j, v)
        else
            fresh[#fresh + 1] = { i, v }
        end
    end
    for _, f in ipairs(fresh) do
        local i, v = f[1], f[2]
        if base and base[i] and not used[i] then
            used[i] = true
            rewritten(i, v)
        else
            added(v)
        end
    end
    for j in ipairs(base or {}) do
        if not used[j] then gone(j) end
    end
end

-- one page's copy, worked out in full before anything of the player's is changed
local function PlanPage(c, base)
    local plan = { notes = {}, added = {}, text = {}, beforeAdded = {}, marks = {}, maps = {} }
    Diff(c.notes, base.notes, First,
        function(j, n)
            local o = { s = n[1], was = base.notes[j][1] }
            for _, f in ipairs(NOTE_FIELDS) do o[f] = n[f] end
            plan.notes[j] = o
        end,
        function(j, n)
            local b, o = base.notes[j], nil
            for _, f in ipairs(NOTE_FIELDS) do
                if n[f] ~= b[f] then o = o or { was = b[1] } o[f] = n[f] end
            end
            plan.notes[j] = o
        end,
        function(n) plan.added[#plan.added + 1] = OwnLine(n) end,
        function(j) plan.notes[j] = { gone = true, was = base.notes[j][1] } end)
    Diff(c.asides, base.asides, First,
        function(_, a) plan.added[#plan.added + 1] = { s = a[1] } end,
        function() end,
        function(a) plan.added[#plan.added + 1] = { s = a[1] } end,
        function() end)
    for _, f in ipairs({ "title", "where", "mapCaption", "margin" }) do
        if c[f] and c[f] ~= base[f] then plan.added[#plan.added + 1] = { s = c[f] } end
    end
    local cb, bb = c.before or {}, base.before or {}
    Diff(cb.diary, bb.diary, Self,
        function(j, s) plan.text["diary:" .. j] = { s = s, was = bb.diary[j] } end,
        function() end,
        function(s) plan.beforeAdded[#plan.beforeAdded + 1] = { s = s } end,
        function(j) plan.text["diary:" .. j] = { gone = true, was = bb.diary[j] } end)
    for _, f in ipairs({ "margin", "bring", "aside" }) do
        if cb[f] and cb[f] ~= bb[f] then plan.text[f] = { s = cb[f], was = bb[f] } end
    end
    if cb.whisper and cb.whisper ~= bb.whisper then plan.beforeAdded[#plan.beforeAdded + 1] = { s = cb.whisper } end
    if cb.ink and not Same(cb.ink, bb.ink) then plan.scene = Copy(cb.ink) end
    for _, m in ipairs(c.marks or {}) do
        if not Holds(base.marks, m) then plan.marks[#plan.marks + 1] = Copy(m) end
    end
    for floor, list in pairs(c.mapMarks or {}) do
        for _, m in ipairs(list) do
            if not Holds(base.mapMarks and base.mapMarks[floor], m) then
                plan.maps[floor] = plan.maps[floor] or {}
                table.insert(plan.maps[floor], Copy(m))
            end
        end
    end
    return plan
end

local function ApplyPlan(cfg, ink, dg, plan)
    local mine = MineOf(cfg, dg.id)
    for j, o in pairs(plan.notes) do
        if not mine.notes[j] then mine.notes[j] = o end
    end
    for _, a in ipairs(plan.added) do mine.added[#mine.added + 1] = a end
    if next(plan.text) or #plan.beforeAdded > 0 or plan.scene then
        local b = BeforeOf(mine)
        for k, t in pairs(plan.text) do if not b.text[k] then b.text[k] = t end end
        for _, a in ipairs(plan.beforeAdded) do b.added[#b.added + 1] = a end
        if plan.scene and not b.scene then b.scene = plan.scene end
    end
    if #plan.marks > 0 then
        cfg.marks = cfg.marks or {}
        cfg.marks[dg.id] = cfg.marks[dg.id] or {}
        for _, m in ipairs(plan.marks) do table.insert(cfg.marks[dg.id], m) end
    end
    for floor, list in pairs(plan.maps) do
        local key = "d" .. dg.instance .. ":" .. floor
        ink[key] = ink[key] or {}
        for _, m in ipairs(list) do
            if not Holds(ink[key], m) then table.insert(ink[key], m) end
        end
    end
end

-- once, on a player's first load: every copy into their own layer. The copies as they were stay in
-- notebook.authorKept for good; a page that can't be read stays a copy, shown as it was.
function ns.BookMigrate(cfg, ink, pages)
    if cfg.migrated then return end
    cfg.migrated = true
    local a = cfg.author
    if not (a and next(a)) then return end
    cfg.authorKept = cfg.authorKept or Copy(a)
    local bases = cfg.authorBase or {}
    local list = a.flyleafMarks
    if list then
        cfg.marks = cfg.marks or {}
        cfg.marks.flyleaf = cfg.marks.flyleaf or {}
        for _, m in ipairs(list) do
            if not Holds(pages.flyleafMarks, m) then table.insert(cfg.marks.flyleaf, Copy(m)) end
        end
        a.flyleafMarks = nil
    end
    for _, dg in ipairs(pages) do
        local c = a[dg.id]
        if c then
            local ok, plan = pcall(PlanPage, c, bases[dg.id] or dg)
            if ok and pcall(ApplyPlan, cfg, ink, dg, plan) then
                a[dg.id], bases[dg.id] = nil, nil
            end
        end
    end
end

-- Your changes stay on their lines ---------------------------------------------------------

-- entry(i): page i as the book has it now
function ns.BookAnchor(cfg, pages, entry)
    for i in ipairs(pages) do
        local dg = entry(i)
        local mine = cfg.mine and cfg.mine[dg.id]
        if mine then
            mine.notes, mine.added = mine.notes or {}, mine.added or {}
            local notes, loose = dg.notes or {}, {}
            local byText = TextIndex(notes, First)
            for k, o in pairs(mine.notes) do
                local here = notes[k] and notes[k][1]
                if o.was == nil then
                    o.was = here   -- (from before `was`: it's on its line now, the first load of this version)
                end
                if o.was ~= here then loose[#loose + 1] = k end
            end
            table.sort(loose)
            local moved = {}
            for _, k in ipairs(loose) do moved[k] = mine.notes[k] mine.notes[k] = nil end
            for _, k in ipairs(loose) do
                local o = moved[k]
                local j = byText[o.was]
                if j and not mine.notes[j] then
                    mine.notes[j] = o
                elseif o.s then
                    local a = { s = o.s }
                    for _, f in ipairs(NOTE_FIELDS) do a[f] = o[f] end
                    mine.added[#mine.added + 1] = a
                elseif o.was ~= nil then
                    mine.orphans = mine.orphans or {}   -- (a mark on a tip the book no longer has)
                    table.insert(mine.orphans, o)
                end
            end
            local b = mine.before
            if b and b.text then
                local diary = dg.before and dg.before.diary or {}
                local index = TextIndex(diary, Self)
                local gone = {}
                for key, t in pairs(b.text) do
                    local k = tonumber(key:match("^diary:(%d+)$") or "")
                    if k then
                        if t.was == nil then t.was = diary[k] end
                        if t.was ~= diary[k] then gone[#gone + 1] = key end
                    end
                end
                table.sort(gone)
                local held = {}
                for _, key in ipairs(gone) do held[key] = b.text[key] b.text[key] = nil end
                for _, key in ipairs(gone) do
                    local t = held[key]
                    local j = index[t.was]
                    if j and not b.text["diary:" .. j] then
                        b.text["diary:" .. j] = t
                    elseif t.s then
                        b.added = b.added or {}
                        table.insert(b.added, { s = t.s })
                    end
                end
            end
        end
    end
end

-- Reset ------------------------------------------------------------------------------------

-- what a page holds of yours, or nil
local function Take(cfg, ink, dg, id)
    local t = {}
    if cfg.mine and cfg.mine[id] then t.mine = cfg.mine[id] cfg.mine[id] = nil end
    if cfg.marks and cfg.marks[id] then t.marks = cfg.marks[id] cfg.marks[id] = nil end
    local a = cfg.author
    if a and id == "flyleaf" and a.flyleafMarks then
        t.flyleaf = a.flyleafMarks
        a.flyleafMarks = nil
    elseif a and a[id] then
        t.author = a[id]
        a[id] = nil
        if cfg.authorBase and cfg.authorBase[id] then t.base = cfg.authorBase[id] cfg.authorBase[id] = nil end
    end
    if dg then
        local prefix = "d" .. dg.instance .. ":"
        for key, list in pairs(ink) do
            if key:sub(1, #prefix) == prefix then
                t.ink = t.ink or {}
                t.ink[key] = list
                ink[key] = nil
            end
        end
    end
    return next(t) and t or nil
end

local function Put(cfg, ink, id, t)
    if t.mine then cfg.mine = cfg.mine or {} cfg.mine[id] = t.mine end
    if t.marks then cfg.marks = cfg.marks or {} cfg.marks[id] = t.marks end
    if t.flyleaf then cfg.author = cfg.author or {} cfg.author.flyleafMarks = t.flyleaf end
    if t.author then cfg.author = cfg.author or {} cfg.author[id] = t.author end
    if t.base then cfg.authorBase = cfg.authorBase or {} cfg.authorBase[id] = t.base end
    for key, list in pairs(t.ink or {}) do ink[key] = list end
end

-- the given pages ({ dg, ... }; the flyleaf with whole) set aside. True if there was anything.
function ns.BookSetAside(cfg, ink, list, whole)
    local entry = { pages = {}, whole = whole or nil, at = time and time() or nil }
    for _, dg in ipairs(list) do
        entry.pages[dg.id] = Take(cfg, ink, dg, dg.id)
    end
    if whole or #list == 0 then entry.pages.flyleaf = Take(cfg, ink, nil, "flyleaf") end
    if not next(entry.pages) then return false end
    cfg.resetAside = cfg.resetAside or {}
    table.insert(cfg.resetAside, entry)
    return true
end

-- is there anything to bring back (for one page id, or at all)?
function ns.BookHasAside(cfg, id)
    for _, e in ipairs(cfg.resetAside or {}) do
        if not id or e.pages[id] then return true end
    end
    return false
end

-- the last reset back (of one page, or the whole of it). What's on those pages now goes aside in its
-- place, so bringing back loses nothing either.
function ns.BookBringBack(cfg, ink, pages, id)
    local stack = cfg.resetAside or {}
    for n = #stack, 1, -1 do
        local e = stack[n]
        if not id or e.pages[id] then
            local now = { pages = {}, at = time and time() or nil }
            for pid, t in pairs(e.pages) do
                if not id or pid == id then
                    local dg
                    for _, p in ipairs(pages) do if p.id == pid then dg = p end end
                    now.pages[pid] = Take(cfg, ink, dg, pid)
                    Put(cfg, ink, pid, t)
                    e.pages[pid] = nil
                end
            end
            if not next(e.pages) then table.remove(stack, n) end
            if next(now.pages) then table.insert(stack, now) end
            return true
        end
    end
    return false
end

-- What a kind of book shows ------------------------------------------------------------------

-- notes that lean on the story, as a plain tip
local PLAIN = {
    ["Faerie dragon siphons mana. The old man shot it before Ewen ran dry"] = "Faerie dragon siphons mana. Kill it before your healer runs dry",
    ["Jergosh curses the arm weak. Ewen lifts it"] = "Jergosh curses the arm weak. Have it lifted",
    ["Bazzalan's blades are poisoned. Ewen cleans that too"] = "Bazzalan's blades are poisoned. Cure it",
    ["Fenrus' bite festers. Ewen keeps the poison off me"] = "Fenrus' bite festers. Keep the poison off the tank",
    ["Jargba tampers a mind. Keep the taken one away from Ewen"] = "Jargba tampers a mind. Keep the taken one away from your healer",
    ["A blind hunter and his bats. Knew he was there before the old man did. Can't say how"] = "A blind hunter and his bats",
    ["Three dwarves, as lost as we were"] = "Three dwarves, lost down here",
}
ns.BookPlainNotes = PLAIN

ns.BOOK_KINDS = { { "story", "The wanderer's story" }, { "notes", "Notes only" }, { "blank", "Blank journal" } }
function ns.BookKindName(kind)
    for _, k in ipairs(ns.BOOK_KINDS) do
        if k[1] == kind then return k[2] end
    end
    return ns.BOOK_KINDS[1][2]
end

-- a note of the book's as this kind of book has it (nil: not in it)
function ns.BookNoteText(kind, text)
    if kind == "blank" then return nil end
    if kind == "notes" then return PLAIN[text] or text end
    return text
end

-- a dungeon's page without the story's lines (the page itself is never changed)
function ns.BookPageView(dg, kind)
    if kind == "story" then return dg end
    local v = {}
    for k, x in pairs(dg) do v[k] = x end
    v.asides, v.margin, v.marginAt, v.mapCaption, v.inkCreep, v.signAt, v.signStruck, v.status = nil, nil, nil, nil, nil, nil, nil, nil
    v.noSign, v.sepia = true, true
    return v
end

-- the "before" page as lines: { lines = { { s, k, yours } }, added = { { s, k } }, margin, marginYours,
-- bring, bringYours, whisper, rule } (mb: your part of the page; none as the wanderer)
function ns.BookBeforeView(b, kind, mb)
    local story = kind == "story"
    local text = mb and mb.text or {}
    local v = { lines = {}, added = {}, whisper = story and b.whisper or nil, rule = story and b.rule or nil }
    for k, s in ipairs(b.diary or {}) do
        local t = text["diary:" .. k]
        if t and t.s then
            v.lines[#v.lines + 1] = { s = t.s, k = k, yours = true }
        elseif story and not (t and t.gone) then
            v.lines[#v.lines + 1] = { s = s, k = k }
        end
    end
    for _, f in ipairs({ "margin", "bring", "aside" }) do
        local t = text[f]
        if t and t.s then
            v[f], v[f .. "Yours"] = t.s, true
        elseif story and not (t and t.gone) then
            v[f] = b[f]
        end
    end
    for k, a in ipairs(mb and mb.added or {}) do v.added[#v.added + 1] = { s = a.s, k = k } end
    return v
end

-- Notes keeps the book's working marks (routes, stairs, locks...) and the wanderer's red ink (ink 2:
-- the gameplay notes on the maps), and leaves the story's out
local TOOL_MARKS = { route = true, wander = true, stairs = true, jump = true, lock = true, chest = true,
                     pass = true, x = true, bang = true }
-- gameplay notes in the deep's blue-black, kept by their words (that ink holds the story too)
local TIP_MARKS = {
    ["runners!"] = true, ["the key's in here"] = true, ["make them climb to you"] = true,
    ["two more when he bleeds"] = true,   -- ("Dont let her touch you": rewritten in red ink, kept as red, 2026-11-10)
    ["when she rises the middle burns"] = true,   -- ("he will run for the gate": struck in the book, 2026-11-08)
}
ns.BookTipMarks = TIP_MARKS
function ns.BookMapMarks(list, kind)
    if kind == "story" or not list then return list end
    local out = {}
    if kind == "notes" then
        for _, m in ipairs(list) do
            if m.gen or TOOL_MARKS[m.t] or (m.ink == 2 and m.t ~= "blot") or TIP_MARKS[m.s] then out[#out + 1] = m end
        end
    end
    return out
end

-- the reset's question, for Options.lua's button (Waymark's own ask box, Ask.lua)
function ns.AskBookReset()
    ns.Ask({ text = "Reset the whole book?", sub = "Your words and ink are set aside, and \"Bring back what was reset\" returns them.",
             ok = "Reset", cancel = "Keep them",
             onAccept = function() if ns.BookReset then ns.BookReset(true) end end })
end
