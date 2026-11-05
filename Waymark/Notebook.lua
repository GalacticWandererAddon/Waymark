local _, ns = ...

-- The found notes: an earlier wanderer's dungeon notebook (/bfi notes), its pages
-- in Data\FoundNotes.lua, its look agreed in mockups\found-notes.html. It shows
-- closed first (leather cover, the mark blind-pressed, a strap and the wax seal);
-- a click opens it on the spread it was last open at. The first spread is the
-- flyleaf and the contents; then each dungeon has one: its notes on the left
-- (the wanderer's ink stamp in the corner, numbered notes, the "- W." sign-off,
-- a margin remark), and on the right the dungeon's own map (Blizzard's art from
-- your game, OpenMap's tile list) with the numbers ringed in red where they
-- happen. Notes that don't fit on the left page go on under the map.
-- Turning: the page corners or the mouse wheel; the fore-edge tabs go to a
-- dungeon. Escape closes it. The book can be dragged anywhere.
--
-- Thumbprint and sign-off: Media\Notes\Thumb.tga (the Wanderer's, 4 impressions; it took the stamp's place) and SignOff.tga (10
-- sign-offs), white, tinted here. (SetRotation turns the picture inside its box,
-- so each cell's drawing has a wide empty margin, and pieces in Bits.tga are
-- drawn already tilted.) A page's id picks the cell and its own angle,
-- size, shade and alpha (ns.NoteLook), so a page always looks the same and no
-- two look alike. Our own art: mockups\brand\export.py bakes it all.

local NOTES = ns.MEDIA .. "Notes\\"
local FONTS = ns.MEDIA .. "Fonts\\"
local HAND = FONTS .. "Felipa-Regular.ttf"              -- titles, the where line, numbers
local HAND_BODY = FONTS .. "NothingYouCouldDo.ttf"      -- the wanderer's notes
local HAND_YOURS = FONTS .. "ReenieBeanie.ttf"          -- what you write in the book
local HAND_WHISPER = FONTS .. "HomemadeApple-Regular.ttf" -- the other hand: words the wanderer didn't write
local HAND_EWEN = FONTS .. "Kalam-Regular.ttf"            -- Ewen's: the only other one who wrote in the book
local INK = { 0.17, 0.12, 0.07 }
local INK_SOFT = { 0.35, 0.23, 0.11 }
local RED = { 0.54, 0.165, 0.11 }
local PENCIL = { 0.29, 0.29, 0.31 }                      -- your hand: pencil (the reader's, not the wanderer's)
local EWEN = { 0.31, 0.33, 0.19 }                         -- her own ink: a faded olive grey-green, watered down (as INKS[4])
local DEEP_INK = { 0.12, 0.15, 0.22 }  -- the wanderer's hand after Blackfathom (the cult's ink)
local DEEP_SOFT = { 0.25, 0.29, 0.38 }  -- (its lighter lines: where, the margin)
local WHISPER = { 0.30, 0.10, 0.36 }                      -- the whispers' own ink (as Ink.lua's ns.WHISPER_INK)
local BODY, YOURS = 17, 22                               -- their sizes
local MARGIN_W = 240                                     -- the margin remark wraps at this width

-- the open book (the board around the pages: left, top, right, bottom)
local W, H = 900, 590
local PAD_L, PAD_T, PAD_R, PAD_B = 14, 14, 22, 14
local PW, PH = (W - PAD_L - PAD_R) / 2, H - PAD_T - PAD_B
local PAGE_V = 660 / 1024           -- the page's part of Page.tga
local COVER_W, COVER_H = 330, 440   -- the closed book (Cover.tga's left 384 x 512)
local MAP_W = PW - 44 - 34          -- the dungeon map on the right page
local MAP_H = MAP_W * 668 / 1002

local function Cfg() return ns.db.notebook end
-- (the book's pages: all but those set hidden = true, which stay in the file, out of the book; the
-- list kept on ns, this chunk being at Lua's 200 locals)
local function Data()
    local all = ns.FoundNotes or {}
    if ns.notebookPagesOf ~= all then
        local shown = {}
        for _, dg in ipairs(all) do if not dg.hidden then shown[#shown + 1] = dg end end
        for k, v in pairs(all) do  -- (and the book's own: flyleaf, its marks and print, the hands)
            if type(k) ~= "number" then shown[k] = v end
        end
        ns.notebookPagesOf, ns.notebookPages = all, shown
    end
    return ns.notebookPages
end

-- (a page not finished for this release, spread i: its tab faded and not to be opened. The book's
-- locked list (the release build's), or its unfinished list as a preview with /bfi notes ship)
function ns.NotebookLocked(i)
    local d = Data()
    local list = d.locked or (Cfg().shipView and d.unfinished)
    if not (d[i] and list) then return false end
    for _, id in ipairs(list) do
        if id == d[i].id then return true end
    end
    return false
end

local function Sound(key)
    local id = SOUNDKIT and SOUNDKIT[key]
    if id then PlaySound(id) end
end

-- a page's own look ------------------------------------------------------------

local function Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

-- Park-Miller: small enough to stay exact in a double
local function Rand(seed)
    local a = seed % 2147483646 + 1
    return function()
        a = a * 16807 % 2147483647
        return (a - 1) / 2147483646
    end
end
local function Between(r, lo, hi) return lo + (hi - lo) * r() end

-- { stamp = { cell 0-3, rotation, alpha }, sign = { cell 0-9, rotation, scale, shade, alpha } }
function ns.NoteLook(id)
    local s, g = Rand(Hash("stamp:" .. id)), Rand(Hash("sign:" .. id))
    return {
        stamp = { cell = math.floor(s() * 4), rot = math.rad(Between(s, -24, 18)), alpha = Between(s, 0.7, 0.95) },
        sign = { cell = math.floor(g() * 10), rot = math.rad(Between(g, -6, 6)), scale = Between(g, 0.9, 1.1),
                 shade = Between(g, 0.75, 1.25), alpha = Between(g, 0.8, 0.95) },
    }
end

-- Stamp.tga: 2 x 2 cells of 256, the stamp 168 across;  SignOff.tga: 4 x 4 cells of 128,
-- the sign-off 52 high
local SIGN_K = 128 / 52
local function StampCoords(c)
    local l, t = (c % 2) * 0.5, math.floor(c / 2) * 0.5
    return l, l + 0.5, t, t + 0.5
end
local function SignCoords(c)
    local l, t = (c % 4) * 0.25, math.floor(c / 4) * 0.25
    return l, l + 0.25, t, t + 0.25
end

-- pieces -------------------------------------------------------------------------

local function SetHand(fs, size, font)
    if not (pcall(fs.SetFont, fs, font or HAND, size, "") and fs:GetFont()) then
        fs:SetFont("Fonts\\FRIZQT__.TTF", math.floor(size * 0.85), "")
    end
end

-- Bits.tga (256 x 512, baked at twice that): pixel box -> texcoords
local function Bits(t, x0, y0, x1, y1, mirror)
    t:SetTexture(NOTES .. "Bits")
    local l, r = x0 / 256, x1 / 256
    if mirror then l, r = r, l end
    t:SetTexCoord(l, r, y0 / 512, y1 / 512)
end

-- each page keeps pools of what it draws, emptied when the spread changes
local function Reset(p)
    for _, pool in pairs(p.pools) do
        for i = 1, pool.n do pool[i]:Hide() end
        pool.n = 0
    end
end

local function Take(p, kind, make)
    local pool = p.pools[kind]
    pool.n = pool.n + 1
    local o = pool[pool.n]
    if not o then
        o = make()
        pool[pool.n] = o
    end
    o:ClearAllPoints()
    o:Show()
    return o
end

local function Text(p, size, color, parent, font)
    local fs = Take(p, parent and "mapText" or "text", function()
        return (parent or p):CreateFontString(nil, "OVERLAY")
    end)
    SetHand(fs, size, font)
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWidth(0)
    fs:SetSpacing(2)
    fs:SetAlpha(1)
    fs:SetShadowColor(0, 0, 0, 0)  -- (a pressed hand's thickening isn't carried to the next use)
    fs:SetHeight(0)  -- (nor a whisper's taller box)
    return fs
end

local function Tex(p, layer, sub, parent)
    local t = Take(p, parent and "mapTex" or "tex", function()
        return (parent or p):CreateTexture(nil, "ARTWORK")
    end)
    t:SetDrawLayer(layer or "ARTWORK", sub or 0)
    t:SetTexCoord(0, 1, 0, 1)
    t:SetRotation(0)
    t:SetVertexColor(1, 1, 1, 1)
    t:SetDesaturation(0)
    t:SetAlpha(1)
    return t
end

-- Handwriting: a note set word by word, as a hand sits on the page: each word
-- a little off the line, the ink thinning along it and the pen dipped again now
-- and then, ~words~ struck through. Laid out first (to know its height), then
-- put down; the seed keeps a note's look the same each time.
local probe
local function Layout(text, width, size, font)
    if not probe then
        probe = UIParent:CreateFontString(nil, "OVERLAY")
        probe:Hide()
    end
    SetHand(probe, size, font)
    local words, x, line, crossed = {}, 0, 0, false
    local space = size * 0.3
    for para in (text .. "\n"):gmatch("(.-)\n") do
        for w in para:gmatch("%S+") do
            local cross = crossed
            if w:sub(1, 1) == "~" then
                cross, crossed = true, true
                w = w:sub(2)
            end
            local closes = w:sub(-1) == "~"
            if closes then w = w:sub(1, -2) end
            if w ~= "" then
                probe:SetText(w)
                local ww = probe:GetStringWidth()
                if x > 0 and x + ww > width then x, line = 0, line + 1 end
                words[#words + 1] = { w = w, x = x, line = line, width = ww, crossed = cross }
                x = x + ww + space
            end
            if closes then crossed = false end
        end
        x, line = 0, line + 1
    end
    return words, math.max(1, line) * size * 1.18
end

-- The wanderer's hand on this page: how the ink goes down, not what it says (FoundNotes.hands[id],
-- and [id .. ":before"] for its "before we go" page; set by Show). The state of mind in the hand:
--   wobble  how far each word strays off the line (1 as usual; 0.2 eerily neat, 2 shaking)
--   even    0-1: 1 never fades or dips again, too steady for a campfire
--   press   pressure: above 1 the strokes thicken (anger, holding on), below 1 they're faint
--   drift   px the line climbs (+) or sinks (-) across 100 px of it
-- Only the wanderer's own words: the whispers, Ewen, the reader's pencil keep their own hands.
-- A line can have its own (over: { press, wobble }, as a page line's own fields), and its ink can
-- turn partway: over.turnAt = the word from which it's in the deep's blue-black (the hand reaching for it).
-- over.ink: the line's own colour (the page's ink with the deep's creeping in, a darker violet).
local pageHand

-- (returns what it put down: hidden while the note is being rewritten)
local function Place(p, words, x0, y0, size, color, font, seed, parent, over)
    local put = {}
    local r = Rand(Hash(seed))
    local ink = Between(r, 0.9, 1)
    local lh, to = size * 1.18, parent or p
    local own = color ~= WHISPER and color ~= EWEN and color ~= PENCIL and color ~= RED
    local hd = own and pageHand or {}
    over = over or {}
    local wob, even = over.wobble or hd.wobble or 1, hd.even or 0
    local press, drift = over.press or hd.press or 1, hd.drift or 0
    local lineDrift = {}  -- (each line tilts its own way, a little more or less: never the same slope twice)
    for wi, wd in ipairs(words) do
        ink = ink - Between(r, 0.015, 0.04)
        if ink < 0.68 or r() < 0.07 then ink = Between(r, 0.9, 1) end  -- (the pen dipped)
        local c = (over.turnAt and wi >= over.turnAt) and DEEP_INK or over.ink or color
        local fs = Text(p, size, c, parent, font)
        fs:SetText(wd.w)
        if font == HAND_WHISPER then fs:SetHeight(size * 2) end  -- (their long tails aren't cut off)
        lineDrift[wd.line] = lineDrift[wd.line] or drift * Between(r, 0.2, 1.4)
        local dx, dy = Between(r, -0.7, 0.7) * wob, Between(r, -1.3, 1.3) * wob
        local x, y = x0 + wd.x + dx, y0 - wd.line * lh + dy + lineDrift[wd.line] * wd.x / 100
        fs:SetPoint("TOPLEFT", to, "TOPLEFT", x, y)
        local whisper = color == WHISPER  -- (struck, their words won't take it: strokes above and below, not across)
        local a = (ink + (0.97 - ink) * even) * math.min(1, press)
        fs:SetAlpha(a * (wd.crossed and not whisper and 0.6 or 1))
        -- (pressed hard: the same word laid down again a hair off, once or twice: the stroke really
        -- thicker, the ink darker where it pooled)
        if press >= 1.2 then  -- (below that the hand's only firm, not pressing)
            -- (copies under half a pixel apart, round the word, so they merge into one wider stroke
            -- rather than reading as two words)
            local d = math.min(0.6, 0.25 + (press - 1) * 0.35)
            local offs = press >= 1.5 and { { d, 0 }, { 0, -d }, { d, -d }, { -d * 0.5, -d * 0.5 } } or { { d, 0 }, { 0, -d } }
            for _, o in ipairs(offs) do
                local f2 = Text(p, size, c, parent, font)
                f2:SetText(wd.w)
                f2:SetPoint("TOPLEFT", to, "TOPLEFT", x + o[1], y + o[2])
                f2:SetAlpha(math.min(1, a))
                put[#put + 1] = f2
            end
            -- (dug in hard, the nib spits: a fleck or two beside the word, and where the line ends,
            -- a blot where the pen stopped and pressed)
            if press >= 1.5 then
                local function Spot(sx, sy, d)
                    local t = Tex(p, "OVERLAY", 3, parent)
                    t:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                    t:SetVertexColor(c[1], c[2], c[3], Between(r, 0.65, 0.9))
                    t:SetSize(d, d * Between(r, 0.7, 1))
                    t:SetPoint("CENTER", to, "TOPLEFT", sx, sy)
                    put[#put + 1] = t
                end
                for _ = 1, (r() < 0.6 and 1 or 2) do
                    Spot(x + Between(r, 0, wd.width), y - size * Between(r, 0.15, 1.05), Between(r, 1.2, 2.6))
                end
                local nxt = words[wi + 1]
                if not nxt or nxt.line ~= wd.line then
                    Spot(x + wd.width + Between(r, 1, 3), y - size * Between(r, 0.6, 0.8), Between(r, 3.5, 5.5))
                    Spot(x + wd.width + Between(r, 5, 9), y - size * Between(r, 0.3, 0.9), Between(r, 1, 1.8))
                end
            end
        end
        put[#put + 1] = fs
        if wd.crossed and whisper then
            -- (hard strokes back and forth across the word, under it: the word stays whole on top)
            local by, w = y - size * 0.6, wd.width
            for _, sl in ipairs({ { -0.1, 0.1, 1.05, -0.15 }, { 0.05, -0.4, 0.95, 0.4 }, { 0.4, 0.45, 1.05, -0.35 } }) do
                local l = Take(p, "wline", function() return p:CreateLine(nil, "ARTWORK", nil, 2) end)
                l:SetColorTexture(DEEP_INK[1], DEEP_INK[2], DEEP_INK[3], Between(r, 0.7, 0.9))
                l:SetThickness(Between(r, 1.5, 2.3))
                l:SetStartPoint("TOPLEFT", to, x + w * sl[1] + Between(r, -2, 2), by + size * sl[2] + Between(r, -2, 2))
                l:SetEndPoint("TOPLEFT", to, x + w * sl[3] + Between(r, -2, 3), by + size * sl[4] + Between(r, -2, 2))
                put[#put + 1] = l
            end
        elseif wd.crossed then
            local l = Take(p, "line", function() return p:CreateLine(nil, "OVERLAY", nil, 2) end)
            l:SetColorTexture(color[1], color[2], color[3], 0.8)
            l:SetThickness(1.4)
            local ly = y - size * 0.6
            l:SetStartPoint("TOPLEFT", to, x - 2, ly + Between(r, -1, 1))
            l:SetEndPoint("TOPLEFT", to, x + wd.width + 3, ly + Between(r, -1.5, 1.5))
            put[#put + 1] = l
        end
    end
    return put
end

local function Button(p, w, h, onClick)
    local b = Take(p, "button", function()
        local b = CreateFrame("Button", nil, p)
        b.label = b:CreateFontString(nil, "OVERLAY")
        SetHand(b.label, 16)
        b.label:SetPoint("LEFT")
        b.num = b:CreateFontString(nil, "OVERLAY")
        SetHand(b.num, 16)
        b.num:SetPoint("RIGHT")
        b:SetScript("OnEnter", function(self) self.label:SetAlpha(0.65) self.num:SetAlpha(0.65) end)
        b:SetScript("OnLeave", function(self) self.label:SetAlpha(1) self.num:SetAlpha(1) end)
        return b
    end)
    b:SetSize(w, h)
    b:SetAlpha(1)
    b:SetFrameLevel(p:GetFrameLevel() + 1)
    b:SetScript("OnClick", onClick)
    b.label:SetText("")
    b.num:SetText("")
    return b
end

-- the book --------------------------------------------------------------------------

local book, cover, open, left, right, prevCorner, nextCorner
local tabs = {}
local spread = 0         -- 0: flyleaf and contents; n: the nth dungeon
local mapFloor = {}      -- [dungeon id] = the floor its map shows
local beforeOf          -- the spread whose "before we go" page is open (Before)

local Show  -- (ahead)

-- Writing in the book (the quill, or /bfi notes write) -----------------------------
-- As yourself: your words over the book's, in your own hand and ink, kept in
-- ns.db.notebook.mine[id] = { notes = { [i] = { s, crossed, gone, floor, x, y } },
-- added = { { s, floor, x, y } } }; nothing of the book is lost.
-- As the wanderer (writing the book itself): edits go on a copy of the dungeon's
-- entry, ns.db.notebook.author[id], read in place of Data\FoundNotes.lua's;
-- tools\export_notes.py writes them into that file so they ship.
-- Marks (Ink.lua's tools and look) go on the open spread, 0-1 across the book:
-- yours in ns.db.notebook.marks[spread id], the wanderer's in the entry's marks
-- (the flyleaf's: author.flyleafMarks / FoundNotes.flyleafMarks).
local writing, who, tool, inkIdx = false, "you", "words", 3
local whisperHand = false  -- the note tool, as the wanderer: in the other hand (the whispers')
local placing      -- a note whose ring goes where the map is clicked next
local notesVersion = 0  -- (bumped each time the book is drawn: the dungeon map's numbers follow)
local inkHost, cur, undo = nil, nil, {}
local whoKept  -- (who's writing comes back from notebook.who once, at the first use)
-- Players write as themselves. The wanderer's hand is the dev copy's alone (ns.BOOK_AUTHOR, set in
-- DevCommands.lua, which doesn't ship); /bfi notes me: the dev copy writing as a player would.
local function KeptWho()
    if whoKept or not (ns.db and Cfg()) then return end
    whoKept = true
    who = ns.BOOK_AUTHOR and not Cfg().asPlayer and "wanderer" or "you"
    inkIdx = who == "wanderer" and 1 or 3
end

-- what this book holds: "story", "notes" or "blank" (BookOwn.lua). The wanderer always has the whole book.
function ns.BookKindNow()
    KeptWho()
    if who == "wanderer" then return "story" end
    return Cfg().kind or "story"
end

local function Copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = Copy(v) end
    return o
end

-- the dungeon as the book has it now: the wanderer's edits made in game, or the shipped entry
local function Entry(i)
    local dg = Data()[i]
    local a = dg and Cfg().author and Cfg().author[dg.id]
    return a or dg
end

-- the wanderer's copy to change (made on the first edit); the page it was made from is kept
-- beside it (notebook.authorBase, not exported), so a newer page in the file can be merged
-- with your edits instead of hiding them (DropShipped)
local function AuthorCopy(i)
    local dg = Data()[i]
    Cfg().author = Cfg().author or {}
    if not Cfg().author[dg.id] then
        Cfg().author[dg.id] = Copy(dg)
        Cfg().authorBase = Cfg().authorBase or {}
        Cfg().authorBase[dg.id] = Copy(dg)
    end
    return Cfg().author[dg.id]
end

local function Mine(id, make)
    Cfg().mine = Cfg().mine or {}
    if make and not Cfg().mine[id] then Cfg().mine[id] = { notes = {}, added = {} } end
    return Cfg().mine[id]
end

-- the notes as they read now: { text, yours, crossed, floor, x, y, book = i | added = j }
-- (writing as the wanderer: the book's own, without yours)
local function NoteViews(dg)
    local mine = who ~= "wanderer" and Mine(dg.id) or { notes = {}, added = {} }
    local out = {}
    local kind = ns.BookKindNow()
    for i, n in ipairs(dg.notes or {}) do
        local m = mine.notes[i] or {}
        local text = m.s or ns.BookNoteText(kind, n[1] or "")
        if text and not m.gone then
            out[#out + 1] = { text = text, yours = m.s ~= nil, crossed = m.crossed, mark = m.mark or n.mark,
                              floor = m.floor or n.floor, x = m.x or n.x, y = m.y or n.y, rs = m.rs or n.rs, na = m.na or n.na,
                              turn = n.turn, book = i }
        end
    end
    for j, a in ipairs(mine.added) do
        out[#out + 1] = { text = a.s or "", yours = true, floor = a.floor, x = a.x, y = a.y, mark = a.mark, rs = a.rs, na = a.na, added = j }
    end
    return out
end

local function Spreads() return #Data() end

local function Turn(to)
    to = math.max(0, math.min(Spreads(), to))
    local dir = to < spread and -1 or 1
    while to > 0 and to <= Spreads() and ns.NotebookLocked(to) do to = to + dir end  -- (locked pages passed over)
    if to > Spreads() then return end
    if to == spread and not beforeOf then return end
    beforeOf = nil
    placing = nil
    Sound("IG_ABILITY_PAGE_TURN")
    Show(to)
end

local function SavePos()
    local p, _, rp, x, y = book:GetPoint()
    Cfg().pos = { p, rp, x, y }
end

local function Draggable(f)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() book:StartMoving() end)
    f:SetScript("OnDragStop", function() book:StopMovingOrSizing() SavePos() end)
end

local function NewPage(x, mirror)
    local p = CreateFrame("Frame", nil, open)
    p:SetPoint("TOPLEFT", open, "TOPLEFT", x, -PAD_T)
    p:SetSize(PW, PH)
    -- the paper (a window of Paper.tga, chosen per page in PaperLook), and over it
    -- the page's gutter and worn edges
    p.paper = p:CreateTexture(nil, "BACKGROUND", nil, 0)
    p.paper:SetAllPoints()
    p.paper:SetTexture(NOTES .. "Paper")
    local bg = p:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAllPoints()
    bg:SetTexture(NOTES .. "Page")
    p.over, p.mirror = bg, mirror
    p.stain = p:CreateTexture(nil, "BACKGROUND", nil, 2)
    -- the page's outer edges uneven (PageEdgeL/R1-3.tga, one per page): the page block shows in the gaps
    if p.CreateMaskTexture then
        -- (and the outline's own shadow on the pages under it, so the edge reads)
        p.edgeShadow = p:CreateTexture(nil, "BACKGROUND", nil, -1)
        p.edgeShadow:SetPoint("TOPLEFT", mirror and -2 or 2, -2)
        p.edgeShadow:SetPoint("BOTTOMRIGHT", mirror and -2 or 2, -2)
        p.edgeShadow:SetVertexColor(0.1, 0.05, 0.02, 0.6)
        p.mask = p:CreateMaskTexture()
        p.mask:SetAllPoints()
        for _, t in ipairs({ p.paper, bg, p.stain }) do t:AddMaskTexture(p.mask) end
    end
    p.pools = { text = { n = 0 }, tex = { n = 0 }, button = { n = 0 }, mapText = { n = 0 }, mapTex = { n = 0 },
                line = { n = 0 }, wline = { n = 0 }, hit = { n = 0 } }
    -- the hand's prints: on a layer clipped to the paper (a thumb holding the page by its edge
    -- shows only partly), over the paper and the words, under the page's map
    p.prints = CreateFrame("Frame", nil, p)
    p.prints:SetAllPoints()
    p.prints:SetClipsChildren(true)
    p.prints.ink = CreateFrame("Frame", nil, p.prints)
    p.prints.ink:SetAllPoints()
    p.prints.used, p.prints.pairs = 0, {}
    -- the dungeon map's own layer, so the rings sit over its tiles
    p.map = CreateFrame("Frame", nil, p)
    p.map:SetSize(MAP_W, MAP_H)
    p.number = p:CreateFontString(nil, "OVERLAY")
    SetHand(p.number, 13)
    p.number:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
    p.number:SetPoint(mirror and "BOTTOMLEFT" or "BOTTOMRIGHT", mirror and 44 or -40, 14)
    return p
end

local function Corner(page, mirror, step)
    local b = CreateFrame("Button", nil, page)
    b:SetSize(44, 44)
    b:SetPoint(mirror and "BOTTOMLEFT" or "BOTTOMRIGHT")
    b:SetFrameLevel(page:GetFrameLevel() + 5)
    local t = b:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    Bits(t, 40, 96, 104, 160, mirror)
    b:SetAlpha(0.85)
    b:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    b:SetScript("OnLeave", function(self) self:SetAlpha(0.85) end)
    b:SetScript("OnClick", function() Turn(spread + step) end)
    return b
end

-- the stamp, the sign-off ---------------------------------------------------------

-- The Wanderer's thumbprint (Media\\Notes\\Thumb.tga, tools\\notebook_thumb.py: 2 x 2 cells of 256,
-- the print about 120 across): on each dungeon's page where a stamp would be, and in the dungeon
-- map's corner (a way into the book). pr = { cell, ink = 1 | 3 (Ink.lua's sepia, the deep's
-- blue-black), bleed = 0-1 (the whispers' violet in it), alpha }; turned as the page's look.
-- (size: the print's own; the box is bigger by its cell's margin, so anchor by the centre)
local THUMB_K = 256 / 120
local function ApplyThumb(t, b, id, pr, size)
    local look = ns.NoteLook(id).stamp
    local ink = (ns.INK_COLORS or {})[pr.ink or 1] or INK
    local l, r, tp, bt = StampCoords(pr.cell or 0)
    if pr.flip then l, r = r, l end  -- (mirrored: its smudge the other way)
    for _, x in ipairs({ t, b }) do
        x:SetTexture(NOTES .. "Thumb")
        x:SetTexCoord(l, r, tp, bt)
        x:SetRotation(pr.rot or look.rot)
    end
    t:SetSize(size * THUMB_K, size * THUMB_K)
    t:SetVertexColor(ink[1], ink[2], ink[3])
    t:SetAlpha(look.alpha * (pr.alpha or 1))
    -- (the violet: the same print a touch larger under it, as ink spreading into the paper)
    b:ClearAllPoints()
    b:SetPoint("CENTER", t, "CENTER", 1, -1)
    b:SetSize(size * THUMB_K * 1.07, size * THUMB_K * 1.07)
    b:SetVertexColor(WHISPER[1], WHISPER[2], WHISPER[3])
    b:SetAlpha(pr.bleed or 0)
    b:SetShown((pr.bleed or 0) > 0)
end

-- (height: the sign-off's own; anchor by the centre, as the stamp)
local function SignOff(p, id, height, ink)  -- (ink: the page's, sepia when none)
    local look = ns.NoteLook(id).sign
    local INK = ink or INK
    local t = Tex(p, "OVERLAY", 1)
    t:SetTexture(NOTES .. "SignOff")
    t:SetTexCoord(SignCoords(look.cell))
    local side = height * SIGN_K * look.scale
    t:SetSize(side, side)
    t:SetVertexColor(math.min(1, INK[1] * look.shade), math.min(1, INK[2] * look.shade), math.min(1, INK[3] * look.shade))
    t:SetAlpha(look.alpha)
    t:SetRotation(look.rot)
    return t
end

-- the first spread: flyleaf and contents ---------------------------------------------

local function Flyleaf()
    local d = Data()
    local line = Text(left, 24, INK)
    line:SetPoint("CENTER", left, "CENTER", 0, 40)
    local story = ns.BookKindNow() == "story"
    line:SetText(story and d.flyleaf or not story and "A field journal" or "")
    if story then
        local s = SignOff(left, "flyleaf", 50)
        s:SetPoint("CENTER", line, "BOTTOM", 30, -36)
    else
        local note = Text(left, 15, INK_SOFT)
        note:SetWidth(PW - 130)
        note:SetJustifyH("CENTER")
        note:SetText(ns.BookKindNow() == "notes" and "Dungeon tips and maps. The story is still in here: change the plate to read it."
            or "Your own pages. The story is still in here: change the plate to read it.")
        note:SetPoint("TOP", line, "BOTTOM", 0, -12)
    end
    -- the bookplate: what the book holds, the choice in the book itself (not while writing the book)
    if who ~= "wanderer" then
        local mid, py = PW / 2, -46  -- (the page's top: "the company" and its names fill the foot)
        local plate = Tex(left, "ARTWORK", 2)
        plate:SetTexture(NOTES .. "Bookplate")  -- (tools\bookplate.py: the label, its writing line at 80 of 128)
        plate:SetSize(256, 128)
        plate:SetPoint("TOP", left, "TOPLEFT", mid, py)
        local lab = Text(left, 14, INK_SOFT)
        lab:SetPoint("TOP", left, "TOPLEFT", mid, py - 28)
        lab:SetText("This book holds")
        -- (each sized to its words, so they sit in the middle of the plate)
        local function Words(y, size, font, color, text, fn)
            local b = Button(left, 200, size + 6, fn)
            SetHand(b.label, size, font)
            b.label:SetTextColor(color[1], color[2], color[3])
            b.label:SetText(text)
            b:SetWidth(b.label:GetStringWidth() + 2)
            b:SetPoint("TOP", left, "TOPLEFT", mid, y)
        end
        Words(py - 52, 20, HAND_BODY, INK, ns.BookKindName(Cfg().kind), ns.BookKindMenu)
        Words(py - 83, 14, HAND_BODY, INK_SOFT, "more in the settings", function() ns.ShowOption("notebook", "kind") end)
    end

    local head = Text(right, 28, INK)
    head:SetPoint("TOPLEFT", 48, -34)
    head:SetText("Contents")
    local y = -86
    local step = math.min(30, (PH - 86 - 40) / math.max(1, #d))  -- (closer lines for a long book)
    for i, dg in ipairs(d) do
        local b = Button(right, PW - 48 - 46, step - 2, function() if not ns.NotebookLocked(i) then Turn(i) end end)
        b:SetPoint("TOPLEFT", 48, y)
        b:SetAlpha(ns.NotebookLocked(i) and 0.35 or 1)
        SetHand(b.label, step < 26 and 15 or 18)
        b.label:SetTextColor(INK[1], INK[2], INK[3])
        local e = Entry(i)
        b.label:SetText(e.title or e.tab or e.id)
        SetHand(b.num, 16)
        b.num:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
        b.num:SetText(2 * i + 1)
        y = y - step
    end
end

-- a dungeon's spread -----------------------------------------------------------------

local function Floors(dg)
    local data = ns.MapDungeonMaps and ns.MapDungeonMaps[dg.instance]
    local out = {}
    for i, f in ipairs(data or {}) do
        if f.tiles and #f.tiles == 12 then out[#out + 1] = { tiles = f.tiles, name = f.name, index = i } end
    end
    return out
end

local function FirstNotedFloor(dg, floors)
    if dg.mapFloor then return dg.mapFloor end
    for _, n in ipairs(dg.notes or {}) do
        for k, f in ipairs(floors) do
            if f.index == n.floor then return k end
        end
    end
    return 1
end

-- Marks on a dungeon map belong to its floor, on the 1002 x 668 picture: yours
-- are map ink (Ink.lua, ns.db.inkMarks["d<instance>:<floor>"]), so they show on
-- the dungeon map itself too; the wanderer's are the entry's mapMarks[floor]
-- (shipped, and shown there as well: ns.InkExtra)
local function MapMarks(dg, floor, wanderer, make)
    if wanderer then
        if make then
            local c = AuthorCopy(spread)
            c.mapMarks = c.mapMarks or {}
            c.mapMarks[floor] = c.mapMarks[floor] or {}
            return c.mapMarks[floor]
        end
        local e = Cfg().author and Cfg().author[dg.id] or dg  -- (the copy once there is one)
        return e.mapMarks and e.mapMarks[floor] or {}
    end
    local all, key = ns.db.inkMarks, "d" .. dg.instance .. ":" .. floor
    if make and not all[key] then all[key] = {} end
    return all[key] or {}
end

local function MapInkList(dg, floor)
    local list = {}
    for _, m in ipairs(ns.DevRouteMarks and ns.DevRouteMarks(dg.instance, floor) or {}) do list[#list + 1] = m end
    for _, m in ipairs(ns.DevDeathMarks and ns.DevDeathMarks(dg.instance, floor) or {}) do list[#list + 1] = m end
    for _, m in ipairs(ns.BookMapMarks(MapMarks(dg, floor, true), ns.BookKindNow())) do list[#list + 1] = m end
    for _, m in ipairs(MapMarks(dg, floor, false)) do list[#list + 1] = m end
    return list
end

-- the wanderer's map marks on the dungeon map itself (Ink.lua asks per key)
function ns.InkExtra(key)
    local inst, floor = key:match("^d(%d+):(%d+)$")
    if not inst then return end
    inst, floor = tonumber(inst), tonumber(floor)
    for i, dg in ipairs(Data()) do
        if dg.instance == inst then
            local e = Entry(i)
            local dev = ns.DevRouteMarks and ns.DevRouteMarks(inst, floor)  -- (DevRoutes.lua, not shipped)
            local deaths = ns.DevDeathMarks and ns.DevDeathMarks(inst, floor)  -- (DevDeaths.lua, not shipped)
            local book = ns.BookMapMarks(e.mapMarks and e.mapMarks[floor], ns.BookKindNow())
            if not dev and not deaths then return book end
            local list = { unpack(dev or {}) }
            for _, m in ipairs(deaths or {}) do list[#list + 1] = m end
            for _, m in ipairs(book or {}) do list[#list + 1] = m end
            return list
        end
    end
end

-- the map: 12 tiles of 256 (4 x 3), the picture their top-left 1002 x 668; aged a
-- little. Each note's number beside its spot, ringed (small enough to circle a
-- boss's icon) unless it's just the number, by a drawing of its own.
-- (sized on the picture, so they grow and shrink with the map: a boss's skull is about 30 of its px)
local RING_PX = 44
local NoteSpots
local function MapTiles(owner, m, f, w, ringSize, views)
    local sx = w / 1002
    for i = 1, 12 do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local pw, ph = math.min(256, 1002 - col * 256), math.min(256, 668 - row * 256)
        local t = Tex(owner, "ARTWORK", 0, m)
        t:SetTexture(f.tiles[i])
        t:SetTexCoord(0, pw / 256, 0, ph / 256)
        t:SetPoint("TOPLEFT", m, "TOPLEFT", col * 256 * sx, -row * 256 * sx)
        t:SetSize(pw * sx, ph * sx)
        t:SetDesaturation(0.3)
        t:SetVertexColor(1, 0.92, 0.78)
    end
    return NoteSpots(owner, m, f.index, w, ringSize, views)
end

-- (and on the dungeon map itself) Each spot: where it is (px from the map's
-- top-left), its ring and number (to move them while it's dragged), its size.
NoteSpots = function(owner, m, floor, w, ringSize, views)
    local spots = {}
    for i, v in ipairs(views) do
        if v.floor == floor and v.x and v.y and v.mark ~= "off" then
            local c = v.yours and PENCIL or RED
            local px, py = v.x * w, -v.y * w * 668 / 1002
            local rsz = ringSize * (v.rs or 1)  -- (the note's ring at its own size: Ctrl + wheel over it)
            local num = Text(owner, math.max(6, math.floor(rsz * 0.8)), c, m)
            num:SetText(i)
            local sp = { x = px, y = py, view = v, n = i, r = rsz, num = num, dx = 0, dy = 0 }
            if v.mark == "x" then
                -- (an X on the spot instead of the ring: two strokes of the ink's brush, crossing a little
                -- off true and of a little different length, smaller than the ring; the same each time)
                local th = math.max(1.5, rsz * 0.085)
                for j, a in ipairs({ 0.74 + (i % 3) * 0.05, -0.82 - (i % 2) * 0.06 }) do
                    local t = Tex(owner, "OVERLAY", 4, m)
                    t:SetTexture(ns.MEDIA .. "InkBrush")
                    t:SetVertexColor(c[1], c[2], c[3], 0.95)
                    t:SetSize(rsz * (j == 1 and 0.62 or 0.54), th)
                    t:SetRotation(a)
                    if j == 1 then sp.ring = t else sp.ring2 = t end
                end
            elseif v.mark ~= "number" then
                sp.ring = Tex(owner, "OVERLAY", 4, m)
                Bits(sp.ring, 136, 150, 200, 214)
                sp.ring:SetSize(rsz, rsz)
                sp.ring:SetVertexColor(c[1], c[2], c[3])
            end
            if v.mark ~= "number" then
                -- (the number round the ring: na degrees, anticlockwise from the right; up and to the right
                -- unless the number's been dragged elsewhere round it)
                sp.nd = rsz * 0.78
                local a = math.rad(v.na or 38)
                sp.dx, sp.dy = math.cos(a) * sp.nd, math.sin(a) * sp.nd
            end
            spots[#spots + 1] = sp
            sp.Put = function(x, y)
                if sp.ring then sp.ring:SetPoint("CENTER", m, "TOPLEFT", x, y) end
                if sp.ring2 then sp.ring2:SetPoint("CENTER", m, "TOPLEFT", x + 0.6, y - 0.4) end
                num:SetPoint("CENTER", m, "TOPLEFT", x + sp.dx, y + sp.dy)
            end
            sp.Put(px, py)
        end
    end
    m.spots = spots
    return spots
end

local MapSurface, WireMap  -- (further down: marks on a map, a map's mouse)
local dm  -- (further down: the found notes on the Battlefield dungeon map; the bar lights its quill)
local SpotUnder, SpotSize  -- (further down: a note's ring under the cursor; its size)

local zoom  -- the map, big, over the book (a click on the page's map); the wheel turns its floors
local function DrawZoom()
    local z = zoom
    Reset(z)
    local w = z.m:GetWidth()
    local f = z.floors[z.k]
    z.m.floor, z.m.dg, z.m.tiles = f.index, z.dg, f
    local spots = MapTiles(z, z.m, f, w, w * RING_PX / 1002, z.views)
    -- each spot's note on hover
    for _, s in ipairs(spots) do
        local b = Take(z, "hit", function()
            local b = CreateFrame("Frame", nil, z.m)
            -- (its press handed on to the map under it, to drag the ring or open its menu: a
            -- hover-only frame kept the clicks on the client, so nothing reached the map)
            b:EnableMouse(true)
            b:SetScript("OnMouseDown", function(_, button)
                local f = z.m:GetScript("OnMouseDown")
                if f then f(z.m, button) end
            end)
            b:SetScript("OnMouseUp", function(_, button)
                local f = z.m:GetScript("OnMouseUp")
                if f then f(z.m, button) end
            end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.n .. ".  " .. ((self.text or ""):gsub("~", "")), 1, 0.93, 0.78, true)
                ns.Hints({ { ns.QuillOut() and "Drag" or "Ctrl-drag", "move it (its number: round it)" }, { "Right-click", "its menu" } })
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return b
        end)
        b:SetSize(s.r * 1.2, s.r * 1.2)
        b:SetFrameLevel(z.m:GetFrameLevel() + 6)
        b:SetPoint("CENTER", z.m, "TOPLEFT", s.x, s.y)
        b.n, b.text = s.n, s.view.text
    end
    z.name:SetText((f.name or ("floor " .. z.k)) .. (#z.floors > 1 and ("   (" .. z.k .. "/" .. #z.floors .. ")") or "")
                   .. (writing and "      -  a click beside the map puts it back" or ""))
    if z.m.ink then z.m.ink.avoid = ns.DungeonBossSpots and ns.DungeonBossSpots(z.dg.instance, f.index) end  -- (paths lift off the skulls)
    if ns.InkDrawList then ns.InkDrawList(z.m.ink, MapInkList(z.dg, f.index)) end
end

-- the big map is a window onto the map: zf its zoom (1-4), ox, oy where the map's centre sits
-- from the window's (kept so no edge comes inside it). The wheel zooms at the cursor, a drag
-- (right-drag while writing) moves it; the map's marks and rings are drawn at its size.
local ZOOM_W = W - 90
local ZOOM_H = ZOOM_W * 668 / 1002
local function ZoomPlace()
    local zf = zoom.zf
    local mx, my = (ZOOM_W * zf - ZOOM_W) / 2, (ZOOM_H * zf - ZOOM_H) / 2
    zoom.ox = math.max(-mx, math.min(mx, zoom.ox))
    zoom.oy = math.max(-my, math.min(my, zoom.oy))
    zoom.m:SetSize(ZOOM_W * zf, ZOOM_H * zf)
    zoom.m:ClearAllPoints()
    zoom.m:SetPoint("CENTER", zoom.view, "CENTER", zoom.ox, zoom.oy)
end
-- (cx, cy: the point kept still, from the window's centre; the cursor's when not given)
local function ZoomBy(d, cx, cy)
    local old = zoom.zf
    local new = math.max(1, math.min(4, old * (d > 0 and 1.25 or 0.8)))
    if math.abs(new - old) < 0.001 then return end
    if not cx then
        local x, y = GetCursorPosition()
        local s = zoom.view:GetEffectiveScale()
        cx, cy = x / s - zoom.view:GetLeft() - ZOOM_W / 2, y / s - zoom.view:GetBottom() - ZOOM_H / 2
    end
    zoom.ox = cx - (cx - zoom.ox) * new / old
    zoom.oy = cy - (cy - zoom.oy) * new / old
    zoom.zf = new
    ZoomPlace()
    DrawZoom()
end

-- (fx, fy: open it zoomed in on that spot of the map, 0-1 across it)
local function ZoomMap(dg, floors, k, views, fx, fy)
    if not zoom then
        zoom = CreateFrame("Button", nil, open)
        zoom:SetAllPoints()
        zoom:SetFrameLevel(open:GetFrameLevel() + 40)
        zoom.pools = { text = { n = 0 }, tex = { n = 0 }, mapText = { n = 0 }, mapTex = { n = 0 }, hit = { n = 0 } }
        local dim = zoom:CreateTexture(nil, "BACKGROUND")
        dim:SetAllPoints()
        dim:SetColorTexture(0.05, 0.03, 0.01, 0.6)
        zoom.view = CreateFrame("Frame", nil, zoom)
        zoom.view:SetSize(ZOOM_W, ZOOM_H)
        zoom.view:SetPoint("CENTER", 0, 10)
        zoom.view:SetClipsChildren(true)
        zoom.m = CreateFrame("Frame", nil, zoom.view)
        zoom.zf, zoom.ox, zoom.oy = 1, 0, 0
        ZoomPlace()
        local sh = zoom:CreateTexture(nil, "BORDER")
        sh:SetPoint("TOPLEFT", zoom.view, "TOPLEFT", 5, -7)
        sh:SetPoint("BOTTOMRIGHT", zoom.view, "BOTTOMRIGHT", 5, -7)
        sh:SetColorTexture(0, 0, 0, 0.45)
        zoom.name = zoom:CreateFontString(nil, "OVERLAY")
        SetHand(zoom.name, 16)
        zoom.name:SetTextColor(0.93, 0.85, 0.68)
        zoom.name:SetPoint("TOP", zoom.view, "BOTTOM", 0, -6)
        zoom.m.ink = ns.InkHost and ns.InkHost(zoom.m)
        if zoom.m.ink then
            zoom.m.ink.paper = true  -- (the big map: the whispers' rim where they're drawn over; not the page's small one)
            zoom.m.ink:SetFrameLevel(zoom.m:GetFrameLevel() + 3)
            zoom.m.ink.goFloor = function(_, floor)  -- (stairs leading there)
                for k, f in ipairs(zoom.floors or {}) do
                    if f.index == floor then
                        zoom.k = k
                        mapFloor[zoom.dg.id] = k
                        Sound("IG_ABILITY_PAGE_TURN")
                        DrawZoom()
                        return
                    end
                end
            end
        end
        WireMap(zoom.m, true)
        zoom:SetScript("OnClick", function(self)
            self:Hide()
            Sound("IG_ABILITY_PAGE_TURN")
            Show(spread)
        end)
        zoom:EnableMouseWheel(true)
        -- the wheel, as on every map: zoom; Ctrl over a mark: its size; Shift: the floors
        zoom:SetScript("OnMouseWheel", function(self, d)
            if IsControlKeyDown() then
                if writing and not SpotSize(SpotUnder(self.m), d) then MapSurface(self.m):Resize(d) end
                return
            end
            if IsShiftKeyDown() then
                if #self.floors < 2 then return end
                self.k = (self.k - 1 - d) % #self.floors + 1
                mapFloor[self.dg.id] = self.k
                Sound("IG_ABILITY_PAGE_TURN")
                DrawZoom()
                return
            end
            ZoomBy(d)
        end)
    end
    local fresh = not zoom:IsShown()  -- (opened now: from the whole map; a redraw keeps the view)
    zoom.dg, zoom.floors, zoom.k, zoom.views = dg, floors, k, views
    if fresh and zoom.keep then
        zoom.zf, zoom.ox, zoom.oy = zoom.keep[1], zoom.keep[2], zoom.keep[3]
        ZoomPlace()
    elseif fresh then
        zoom.zf, zoom.ox, zoom.oy = 1, 0, 0
        if fx then
            zoom.zf = 1.6
            zoom.ox, zoom.oy = -(fx - 0.5) * ZOOM_W * 1.6, (fy - 0.5) * ZOOM_H * 1.6
        end
        ZoomPlace()
    end
    zoom:Show()
    DrawZoom()
end

-- the wheel over the page's own map: Ctrl sizes what's under it, Shift turns the floors; a plain wheel
-- does nothing (it used to open the big map; the user turned that off, a click or the button does it)
local function PageMapWheel(m, d)
    if not m.dg then return end
    if IsControlKeyDown() then
        if writing and not SpotSize(SpotUnder(m), d) then MapSurface(m):Resize(d) end
        return
    end
    if IsShiftKeyDown() then
        if #(m.floors or {}) > 1 then
            mapFloor[m.dg.id] = (m.k - 1 - d) % #m.floors + 1
            Sound("IG_ABILITY_PAGE_TURN")
            Show(spread)
        end
        return
    end
end

-- the spread drawn again after a change, and the big map with it when it's open
local function Redraw()
    local k = zoom and zoom:IsShown() and zoom.k
    -- (the big map's view kept: picking a tool, or any redraw, put it back to the whole map)
    if k then zoom.keep = { zoom.zf, zoom.ox, zoom.oy } end
    Show(spread)
    local m = right.map
    if k and m.dg then ZoomMap(m.dg, m.floors, k, m.views) end
    if zoom then zoom.keep = nil end
end

local function DrawMap(dg, floors, k, top, views)
    local f = floors[k]
    local m = right.map
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", right, "TOPLEFT", 44, top)
    m:Show()
    m.floor, m.dg, m.views, m.tiles, m.floors, m.k = f.index, dg, views, f, floors, k
    -- tipped in: pasted along its top edge only, so the rest lifts off the page a
    -- little (the shadow grows toward the bottom), and the paste shows as a darker
    -- band where it soaked into both sheets, squeezed out a hair past the edge
    local shadow = Tex(right, "BORDER", 0)
    shadow:SetColorTexture(0.2, 0.12, 0.05, 0.22)
    shadow:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -2)
    shadow:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 3, -4)
    local lift = Tex(right, "BORDER", 1)
    lift:SetColorTexture(0.15, 0.08, 0.03, 0.22)
    lift:SetPoint("TOPLEFT", m, "BOTTOMLEFT", 4, 0)
    lift:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 5, -6)
    MapTiles(right, m, f, MAP_W, MAP_W * RING_PX / 1002, views)
    if m.ink then m.ink.avoid = ns.DungeonBossSpots and ns.DungeonBossSpots(dg.instance, f.index) end
    if m.ink and ns.InkDrawList then ns.InkDrawList(m.ink, MapInkList(dg, f.index)) end
    local paste = Tex(right, "OVERLAY", 3, m)
    paste:SetColorTexture(0.38, 0.24, 0.09, 0.2)
    paste:SetPoint("TOPLEFT", m, "TOPLEFT", -2, 1)
    paste:SetPoint("BOTTOMRIGHT", m, "TOPRIGHT", 2, -7)
    local seam = Tex(right, "OVERLAY", 4, m)
    seam:SetColorTexture(0.28, 0.16, 0.06, 0.28)
    seam:SetPoint("TOPLEFT", m, "TOPLEFT", -2, -7)
    seam:SetPoint("BOTTOMRIGHT", m, "TOPRIGHT", 2, -8)
    -- the floor's name, and arrows when there are more
    local name = Text(right, 15, INK_SOFT)
    name:SetPoint("TOP", m, "BOTTOM", 0, -10)
    name:SetText(placing and "click the map: where it happens" or f.name or ("floor " .. k))
    if #floors > 1 then
        for _, step in ipairs({ -1, 1 }) do
            local to = (k - 1 + step) % #floors + 1
            local b = Button(right, 22, 20, function()
                mapFloor[dg.id] = to
                Sound("IG_ABILITY_PAGE_TURN")
                Show(spread)
            end)
            b:SetFrameLevel(right:GetFrameLevel() + 14)  -- (over the drawing catcher)
            SetHand(b.label, 18)
            b.label:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
            b.label:SetText(step < 0 and "\226\128\185" or "\226\128\186")  -- single guillemets
            b:SetPoint(step < 0 and "RIGHT" or "LEFT", name, step < 0 and "LEFT" or "RIGHT", step * 8, 0)
        end
    end
    return name
end

-- where a click on a map is, 0-1 across its picture; on a boss's spot (within 12 px), exactly there
local function MapPoint(m)
    local x, y = GetCursorPosition()
    local s = m:GetEffectiveScale()
    x, y = (x / s - m:GetLeft()) / m:GetWidth(), (m:GetTop() - y / s) / m:GetHeight()
    local bosses = ns.DungeonBosses and m.dg and ns.DungeonBosses[m.dg.instance]
    local best = 12
    for _, b in pairs(bosses or {}) do
        if b[1] == m.floor then
            local d = math.sqrt(((b[2] - x) * m:GetWidth()) ^ 2 + ((b[3] - y) * m:GetHeight()) ^ 2)
            if d < best then best, x, y = d, b[2], b[3] end
        end
    end
    return math.floor(x * 10000 + 0.5) / 10000, math.floor(y * 10000 + 0.5) / 10000
end

-- a click on a map: the note being placed goes there; on the page's, otherwise the map, big
local function MapClick(m, button)
    if button ~= "LeftButton" or not m.dg then return end
    if placing then
        local x, y = MapPoint(m)
        local p = placing
        placing = nil
        p.set(m.floor, x, y)
        return
    end
    if m == right.map then
        ZoomMap(m.dg, m.floors, m.k, m.views)
        Sound("IG_ABILITY_PAGE_TURN")
    end
end

-- In write mode: what's under a click ------------------------------------------------

-- a click target over something written (left: rewrite it; right: what else)
-- (onDrag(dx, dy): it can be dragged too, the box following the cursor; let go a few px
-- away and that's a move by dx, dy in the page's units, else a click)
local function Hit(p, x, y, w, h, onLeft, onRight, onDrag)
    local b = Take(p, "hit", function()
        local b = CreateFrame("Button", nil, p)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.55, 0.35, 0.12, 0.12)
        return b
    end)
    b:SetFrameLevel(p:GetFrameLevel() + (tool == "text" and 14 or 6))  -- (jotting: over the catcher, so the lines stay editable)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", p, "TOPLEFT", x - 4, y + 3)
    b:SetSize(w + 8, h + 5)
    b.down = nil
    b:SetScript("OnUpdate", nil)
    b:SetScript("OnEnter", nil)
    b:SetScript("OnLeave", nil)
    b:SetScript("OnMouseDown", onDrag and function(self, button)
        if button ~= "LeftButton" then return end
        local cx, cy = GetCursorPosition()
        self.down = { cx, cy }
        self:SetScript("OnUpdate", function(s)
            local nx, ny = GetCursorPosition()
            local sc = s:GetEffectiveScale()
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", p, "TOPLEFT", x - 4 + (nx - s.down[1]) / sc, y + 3 + (ny - s.down[2]) / sc)
        end)
    end or nil)
    b:SetScript("OnClick", function(self, button)
        self:SetScript("OnUpdate", nil)
        local d = self.down
        self.down = nil
        if button == "RightButton" then
            if onRight then onRight() end
            return
        end
        if d then
            local nx, ny = GetCursorPosition()
            local sc = self:GetEffectiveScale()
            local dx, dy = (nx - d[1]) / sc, (ny - d[2]) / sc
            if dx * dx + dy * dy > 16 then onDrag(dx, dy) return end
        end
        if onLeft then onLeft() end
    end)
    return b
end

-- a spot on the open book (0-1 across it, as the spread's marks) and back: the page it's
-- on and the offsets on that page (y down from its top, negative)
local function BookPoint(p, x, y)
    local bx = (p == right and PAD_L + PW or PAD_L) + x
    return { math.floor(bx / W * 10000 + 0.5) / 10000, math.floor((PAD_T - y) / H * 10000 + 0.5) / 10000 }
end
local function PagePoint(at)
    local bx, by = at[1] * W, at[2] * H
    if bx >= PAD_L + PW then return right, bx - PAD_L - PW, PAD_T - by end
    return left, bx - PAD_L, PAD_T - by
end

-- one box laid over what's being rewritten (its old words hidden meanwhile): Enter
-- keeps it, Escape drops it (breaks: Shift + Enter starts a new line, kept)
local edit
local function EditAt(p, x, y, w, size, font, color, text, done, old, breaks)
    if not edit then
        edit = CreateFrame("EditBox", nil, open)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(400)
        local bg = edit:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", -5, 4)
        bg:SetPoint("BOTTOMRIGHT", 5, -4)
        bg:SetColorTexture(1, 0.95, 0.8, 0.4)
        edit:SetScript("OnEscapePressed", function(self)
            self.done = nil
            self:ClearFocus()
        end)
        edit:SetScript("OnEnterPressed", function(self)
            if self.breaks and IsShiftKeyDown() then
                local at, t = self:GetCursorPosition(), self:GetText() or ""
                if t:sub(at, at) ~= "\n" then self:Insert("\n") end  -- (unless the box put one in itself)
                return
            end
            self:ClearFocus()
        end)
        edit:SetScript("OnEditFocusLost", function(self)
            local d = self.done
            self.done = nil
            for _, o in ipairs(self.old or {}) do o:Show() end
            self.old = nil
            self:Hide()
            local t = self:GetText() or ""
            if self.breaks then
                t = t:gsub("[ \t]*\n[ \t]*", "\n"):gsub("\n\n+", "\n")
            else
                t = t:gsub("\n", " ")
            end
            if d then d(strtrim(t)) end
        end)
    end
    edit:SetFrameLevel(p:GetFrameLevel() + 20)
    edit:ClearAllPoints()
    edit:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
    edit:SetWidth(w)
    edit:SetHeight(size * 3.6)
    if not pcall(edit.SetFont, edit, font, size, "") then edit:SetFont(HAND, size, "") end
    edit:SetTextColor(color[1], color[2], color[3])
    edit:SetText(text or "")
    for _, o in ipairs(edit.old or {}) do o:Show() end
    edit.old = old
    for _, o in ipairs(old or {}) do o:Hide() end
    edit.done = done
    edit.breaks = breaks
    edit:Show()
    edit:SetFocus()
    edit:HighlightText()
end

-- a little list at the cursor (in a do block: the file is at Lua's 200 locals)
local Menu
do
local menu, submenu
-- items: { label, fn, mark = an ink mark to show instead of words ({ t, v }), font, color, on = chosen,
-- sub = items: a row that opens a second list beside it (hover or click) }
local MARK_ROW = 30
local function MenuFrame()
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ns.AddonWindow(f)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    f:SetBackdropColor(0.88, 0.8, 0.6, 0.97)
    f:SetBackdropBorderColor(0.4, 0.27, 0.12)
    f:EnableMouse(true)
    f.rows = {}
    return f
end
local FillMenu
local function OpenSub(row, items)
    if not submenu then
        submenu = MenuFrame()
        submenu:SetFrameLevel(menu:GetFrameLevel() + 10)
    end
    FillMenu(submenu, items)
    submenu:ClearAllPoints()
    submenu:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 4)
    submenu:Show()
end
function FillMenu(f, items)
    local wMax, y = 0, -4
    for i, it in ipairs(items) do
        local r = f.rows[i]
        if not r then
            r = CreateFrame("Button", nil, f)
            r.label = r:CreateFontString(nil, "OVERLAY")
            r.label:SetPoint("LEFT", 10, 0)
            local hl = r:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.55, 0.35, 0.12, 0.18)
            r.on = r:CreateTexture(nil, "BACKGROUND")
            r.on:SetAllPoints()
            r.on:SetColorTexture(0.55, 0.35, 0.12, 0.14)
            r.arrow = r:CreateTexture(nil, "OVERLAY")
            r.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
            r.arrow:SetSize(12, 12)
            r.arrow:SetPoint("RIGHT", -4, 0)
            r.arrow:SetVertexColor(0.4, 0.27, 0.12)
            f.rows[i] = r
        end
        r.arrow:SetShown(it.sub ~= nil)
        local h = it.mark and MARK_ROW or 20
        SetHand(r.label, 15, it.font)
        local c = it.color or INK
        r.label:SetTextColor(c[1], c[2], c[3])
        r.on:SetShown(it.on or false)
        -- (a mark: drawn in ink on the row, as the tool will draw it)
        if it.mark then
            r.label:SetText("")
            if not r.ink and ns.InkHost then
                r.ink = ns.InkHost(r)
                r.ink:ClearAllPoints()
                r.ink:SetPoint("LEFT", 8, 0)
                r.ink:SetSize(44, MARK_ROW)
            end
            if r.ink then
                r.ink:Show()
                if ns.InkDrawList then
                    ns.InkDrawList(r.ink, { { t = it.mark[1], v = it.mark[2], ink = 1, r = 4242 + i, p = { 0.5, 0.5 }, sc = 16 } })
                end
            end
            wMax = math.max(wMax, 44)
        else
            if r.ink then r.ink:Hide() end
            r.label:SetText(it[1])
            wMax = math.max(wMax, r.label:GetStringWidth() + (it.sub and 14 or 0))
        end
        r:SetScript("OnClick", function()
            if it.sub then OpenSub(r, it.sub) return end
            menu:Hide()
            it[2]()
        end)
        -- (on the first list, hovering a row opens its second list or shuts the one open)
        r:SetScript("OnEnter", f == menu and function()
            if it.sub then OpenSub(r, it.sub) elseif submenu then submenu:Hide() end
        end or nil)
        r:SetHeight(h)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 4, y)
        r:SetPoint("RIGHT", -4, 0)
        r:Show()
        y = y - h
    end
    for i = #items + 1, #f.rows do f.rows[i]:Hide() end
    f:SetSize(wMax + 28, -y + 4)
end

function Menu(items)
    if not menu then
        menu = MenuFrame()
        if pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN") then
            menu:SetScript("OnEvent", function(self)
                if self:IsShown() and not self:IsMouseOver()
                    and not (submenu and submenu:IsShown() and submenu:IsMouseOver()) then self:Hide() end
            end)
        end
        menu:SetScript("OnHide", function() if submenu then submenu:Hide() end end)
    end
    if submenu then submenu:Hide() end
    FillMenu(menu, items)
    local x, y = GetCursorPosition()
    local s = menu:GetEffectiveScale()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 4, y / s - 4)
    menu:Show()
end
-- (the menu up: hover tooltips under it wait, QuestGround.lua)
function ns.QuillMenuShown() return menu and menu:IsShown() or false end
end

-- changing a note: as yourself on your layer, as the wanderer on the book's copy
-- (view.dgi: its dungeon, when it's from the dungeon map rather than the open spread)
local NotesChanged  -- (further down: the dungeon map's numbers follow)
local function NoteChange(view, fn)
    local i = view.dgi or spread
    if who == "wanderer" then
        local dg = AuthorCopy(i)
        fn(dg.notes[view.book], "wanderer", dg)
    else
        local dg = Entry(i)
        local mine = Mine(dg.id, true)
        if view.added then
            fn(mine.added[view.added], "added", mine)
        else
            mine.notes[view.book] = mine.notes[view.book] or {}
            local o, n = mine.notes[view.book], dg.notes and dg.notes[view.book]
            if o.was == nil and n then o.was = n[1] end  -- (the words it belongs to: BookAnchor keeps it there)
            fn(o, "book", mine)
        end
    end
    if open and open:IsShown() then Redraw() end
    NotesChanged()
end

-- a note's field changed with an undo for it (the ring taken off the map, its size)
local function NoteSet(view, field, value)
    local old
    NoteChange(view, function(n)
        old = n[field]
        n[field] = value
    end)
    undo[#undo + 1] = { noteView = view, field = field, old = old, who = who }
end

-- (onMap: a ring's menu on a map, only what's about the ring there; the note's words have
-- their own menu on its page. extra: rows after)
local function NoteMenu(view, extra, onMap)
    local items = {}
    local wanderer = who == "wanderer"
    -- how its spot is marked: a ring and an X swap; just the number; off the map (yours say "ring"
    -- outright, over a book's "number")
    local function MarkItems(onPage)
        local function Set(mk)
            NoteChange(view, function(n, kind)
                if mk == "ring" then n.mark = kind ~= "wanderer" and "ring" or nil else n.mark = mk end
            end)
        end
        local cur = view.mark == "ring" and "ring" or view.mark or "ring"
        if cur == "x" then
            items[#items + 1] = { "a ring instead", function() Set("ring") end }
        elseif cur == "ring" then
            items[#items + 1] = { "an X instead", function() Set("x") end }
        end
        items[#items + 1] = { cur == "number" and (onPage and "ring it on the map" or "a ring round its number")
                              or (onPage and "just its number on the map" or "just its number"),
                              function() Set(cur == "number" and "ring" or "number") end }
        items[#items + 1] = { "take it off the map", function() Set("off") end }
    end
    if onMap then
        MarkItems(false)
        for _, it in ipairs(extra or {}) do items[#items + 1] = it end
        Menu(items)
        return
    end
    if view.rewrite then
        items[#items + 1] = { "rewrite it", function()
            if zoom then zoom:Hide() end  -- (its words are on the page under the big map)
            view.rewrite()
        end }
    end
    if not view.added then
        local crossed = view.crossed or (wanderer and view.text:match("^~.*~$"))
        items[#items + 1] = { crossed and "uncross it" or "cross it out", function()
            NoteChange(view, function(n, kind)
                if kind == "wanderer" then
                    local t = n[1] or ""
                    n[1] = t:match("^~(.*)~$") or ("~" .. t .. "~")
                else
                    n.crossed = not n.crossed or nil
                end
            end)
        end }
    end
    local onMap = view.x and view.mark ~= "off"
    if not view.dgi then items[#items + 1] = { onMap and "put it somewhere else on the map" or "put it on the map", function()
        placing = { set = function(floor, x, y)
            NoteChange(view, function(n, kind)
                n.floor, n.x, n.y = floor, x, y
                if view.mark == "off" then n.mark = kind ~= "wanderer" and "ring" or nil end
            end)
        end }
        Redraw()
    end } end
    if onMap then MarkItems(true) end
    -- the order: as the wanderer the book's notes, as yourself your own added ones
    local i = view.dgi or spread
    local pos, count
    if wanderer and view.book then
        pos, count = view.book, #(Entry(i).notes or {})
    elseif not wanderer and view.added then
        pos, count = view.added, #Mine(Entry(i).id, true).added
    end
    local function Swap(d)
        local list = wanderer and AuthorCopy(i).notes or Mine(Entry(i).id, true).added
        list[pos], list[pos + d] = list[pos + d], list[pos]
        if open and open:IsShown() then Redraw() end
        NotesChanged()
    end
    if wanderer and view.book then
        items[#items + 1] = { "make it a line of its own (no number)", function()
            local c = AuthorCopy(view.dgi or spread)
            local n = table.remove(c.notes, view.book)
            local after = view.book - 1
            c.asides = c.asides or {}
            -- (lines after it are now after one fewer note; it goes last among those before it)
            for _, o in ipairs(c.asides) do
                if (o.after or #c.notes + 1) > after then o.after = (o.after or #c.notes + 1) - 1 end
            end
            local at = #c.asides + 1
            for j, o in ipairs(c.asides) do
                if (o.after or #c.notes) > after then at = j break end
            end
            table.insert(c.asides, at, { n[1] })
            c.asides[at].after = after
            if open and open:IsShown() then Redraw() end
            NotesChanged()
        end }
    end
    if pos and pos > 1 then items[#items + 1] = { "move it up", function() Swap(-1) end } end
    if pos and pos < count then items[#items + 1] = { "move it down", function() Swap(1) end } end
    items[#items + 1] = { "remove it", function()
        NoteChange(view, function(n, kind, owner)
            if kind == "wanderer" then table.remove(owner.notes, view.book)
            elseif kind == "added" then table.remove(owner.added, view.added)
            else n.gone = true end
        end)
    end }
    if not wanderer and view.book and view.yours then
        items[#items + 1] = { "back to the book's words", function()
            NoteChange(view, function(n) n.s = nil end)
        end }
    end
    for _, it in ipairs(extra or {}) do items[#items + 1] = it end
    Menu(items)
end

-- "Before we go": a spread of its own for each dungeon (dg.before), written the night before the
-- delve, opened from the ribbon on the dungeon's page and not met by turning pages. Left: the road
-- there under a pen-and-ink scene (Data\InkScenes.lua's pieces through Ink.lua's brush, so it's the
-- same hand as the map marks), the diary, a margin line, now and then the whispers. Right: who asked
-- us (hover: the quest as the game tooltips it; click: the quest window, and the giver on the
-- Battlefield map), what to bring, and once in a while what the old man said.
--   before = { where = "...", scene = { { piece, x, y, scale }, ... } (in a 360 x 170 scene),
--              diary = { "...", ... }, margin = "...", whisper = "...",
--              asked = { { quest = id, side = "H", "Who", ", where. What they want." }, ... },
--              bring = "...", rule = { "who said it", "what" } }
local SCENE_W, SCENE_H = 360, 170

-- pages from here on are in the deep's ink (the one after Blackfathom's)
local function DeepFrom()
    for i, dg in ipairs(Data()) do
        if dg.id == "blackfathom" then return i + 1 end
    end
    return math.huge
end

-- the scene as ink: one sketch mark a piece (Ink.lua), placed in the scene's box (0-1); the
-- wanderer's own copy of them (before.ink) once any is moved, sized, rubbed out or drawn beside
-- who drew it (a scene's by, or a piece's own): not always the wanderer. Their inks (Ink.lua's INKS)
-- and how heavy their hand is; the wanderer's own ink otherwise
local DRAWN_BY = {
    tam = { ink = 5, w = 0.65 },    -- charcoal from the fire, light and careful, always an animal in it
    ewen = { ink = 4, w = 0.8 },    -- her grey-green
    brakk = { ink = 1, w = 1.35 },  -- a guide's sketch: heavy, plain, the way marked
}
local function SceneSketch(scene, ink, seed, by)
    local out, pieces = {}, ns.INK_SCENES or {}
    for n, s in ipairs(scene or {}) do
        local piece = pieces[s[1]]
        if piece then
            local x, y = 0, 0
            if not piece.wide then x, y = (s[2] or 0) / SCENE_W, (s[3] or 0) / SCENE_H end
            local hand = DRAWN_BY[s.by or by or ""]
            out[#out + 1] = { t = "sketch", piece = s[1], ink = hand and hand.ink or ink, w = hand and hand.w or nil,
                              r = (seed + n * 131) % 2000000000 + 1,
                              p = { x, y }, sc = not piece.wide and s[4] ~= 1 and s[4] or nil }
        end
    end
    return out
end
local function SceneInk(dg, spreadIndex)
    local b = dg.before
    local mine = who ~= "wanderer" and Mine(dg.id)
    if mine and mine.before and mine.before.scene then return mine.before.scene end  -- (your copy of it, once changed)
    return b.ink or SceneSketch(b.scene, spreadIndex >= DeepFrom() and not dg.sepia and 3 or 1, Hash(dg.id), b.by)
end

-- a quest in your log ("have"), done ("done"), or neither
local function QuestState(id)
    if type(id) ~= "number" then return end   -- (a Forever page's quest, no id yet)
    local i = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
    if not i and GetQuestLogIndexByID then
        i = GetQuestLogIndexByID(id)
        i = i and i > 0 and i or nil
    end
    if i then return "have" end
    local checks = {}
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then checks[#checks + 1] = C_QuestLog.IsQuestFlaggedCompleted end
    if IsQuestFlaggedCompleted then checks[#checks + 1] = IsQuestFlaggedCompleted end
    for _, f in ipairs(checks) do
        local ok, done = pcall(f, id)
        if ok and done then return "done" end
    end
end

-- Your pencil on "Who asked us": a loose ring round a quest in your log; a stroke through one
-- done and a tick in the margin. The reader marks the book, the wanderer's words stay as written.
-- (p: the page; x0, y0: the line's top left; words, h: its Layout; size: its text size; seed:
-- the line's, so each ring and stroke is a little different and always the same.)
function ns.NotebookPencil(p, st, x0, y0, words, h, size, seed)
    if st ~= "have" and st ~= "done" then return end
    local r = Rand(Hash("pencil:" .. seed))
    local function Stroke(x1, y1, x2, y2, a, th)
        local l = Take(p, "line", function() return p:CreateLine(nil, "OVERLAY", nil, 2) end)
        l:SetColorTexture(PENCIL[1], PENCIL[2], PENCIL[3], a)
        l:SetThickness(th)
        l:SetStartPoint("TOPLEFT", p, x1, y1)
        l:SetEndPoint("TOPLEFT", p, x2, y2)
    end
    local lh = size * 1.18
    if st == "have" then
        local bw = 0
        for _, wd in ipairs(words) do bw = math.max(bw, wd.x + wd.width) end
        local cx, cy = x0 + bw / 2, y0 - h / 2 + 3
        local rx, ry = bw / 2 + 12, h / 2 + 7
        -- (once round and a little past where it began, the hand never quite closing it)
        local a0, turns, n = Between(r, 0, 2 * math.pi), Between(r, 1.06, 1.14), 40
        local wob, phase = Between(r, 0.03, 0.06), Between(r, 0, 6)
        local px, py
        for i = 0, n do
            local t = i / n
            local ang = a0 + t * turns * 2 * math.pi
            local k = 1 + wob * math.sin(phase + t * 7) + (t > 1 / turns and 0.06 * (t - 1 / turns) * turns or 0)
            local x, y = cx + math.cos(ang) * rx * k, cy + math.sin(ang) * ry * k
            if px then Stroke(px, py, x, y, 0.55 + 0.2 * math.sin(phase + t * 5), 1.4) end
            px, py = x, y
        end
        return
    end
    -- done: each line struck through, slanting a little, and a tick by the first
    local lines = {}
    for _, wd in ipairs(words) do
        local L = lines[wd.line]
        if not L then L = { wd.x, wd.x + wd.width } lines[wd.line] = L end
        L[1], L[2] = math.min(L[1], wd.x), math.max(L[2], wd.x + wd.width)
    end
    for ln, L in pairs(lines) do
        local y = y0 - ln * lh - size * 0.62
        Stroke(x0 + L[1] - 3, y + Between(r, -1.2, 1.2), x0 + L[2] + 4, y + Between(r, -2, 2), 0.7, 1.5)
    end
    local tx, ty = x0 - 26, y0 - 5
    Stroke(tx, ty - 5, tx + 5, ty - 11, 0.75, 1.7)
    Stroke(tx + 5, ty - 11, tx + 15, ty + 3, 0.75, 1.6)
end

-- does this page show who asked? A Forever dungeon's only once its quests have ids
function ns.NotebookAskedOn(dg)
    if not dg.forever then return true end
    for _, a in ipairs(dg.before and dg.before.asked or {}) do
        if a.quest then return true end
    end
    return false
end

-- the book's quests for a dungeon (instance mapID): your side's, from its "before we go" page,
-- each { quest = id, state = "have" | "done" | nil, who }; nil when the book has no page on it
function ns.NotebookQuests(instance)
    local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
    for _, dg in ipairs(Data()) do
        if dg.instance == instance then
            if not ns.NotebookAskedOn(dg) then return end
            local out = {}
            for _, a in ipairs(dg.before and dg.before.asked or {}) do
                if a.quest and not (a.side and a.side ~= faction) then
                    out[#out + 1] = { quest = a.quest, state = QuestState(a.quest), who = a[1] }
                end
            end
            return out
        end
    end
end

-- the dungeon (instance mapID) whose "before we go" page names this quest, or nil
function ns.NotebookQuestPage(id)
    for _, dg in ipairs(Data()) do
        for _, a in ipairs(dg.before and dg.before.asked or {}) do
            if a.quest == id then return dg.instance end
        end
    end
end

-- the giver lit on the Battlefield map a while (where QuestieDB has them): the map browsed to
-- their zone (Browse.lua's way, so it isn't put straight back on yours) and a soft glow there.
-- The book folds shut so the map can be seen; a click on its cover opens it on the same page.
local ping, pingToken = nil, 0
local function ShowGiver(id)
    local ok, e = pcall(ns.QuestEnds or function() end, id)
    local f = ok and e and e.from
    if not (f and f.map and BattlefieldMapFrame) then return end
    if not BattlefieldMapFrame:IsShown() and ToggleBattlefieldMap then ToggleBattlefieldMap() end
    if not BattlefieldMapFrame:IsShown() then return end
    if ns.BrowseTo then ns.BrowseTo(f.map) else BattlefieldMapFrame:SetMapID(f.map) end
    if open:IsShown() then
        open:Hide()
        cover:Show()
        Sound("IG_SPELLBOOK_CLOSE")
    end
    if not ping then
        ping = CreateFrame("Frame")
        ping.glow = ping:CreateTexture(nil, "OVERLAY")
        ping.glow:SetAllPoints()
        ping.glow:SetTexture(NOTES .. "Glow")
        ping.glow:SetVertexColor(1, 0.8, 0.15)
        ping.glow:SetBlendMode("ADD")
        local ag = ping.glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.35)
        a:SetDuration(0.8)
        ping.ag = ag
    end
    pingToken = pingToken + 1
    local token = pingToken
    -- (a moment later: the map has its new size by then)
    C_Timer.After(0.05, function()
        local canvas = BattlefieldMapFrame.ScrollContainer and BattlefieldMapFrame.ScrollContainer.Child
        if not canvas or pingToken ~= token then return end
        local side = 46 * UIParent:GetEffectiveScale() / math.max(0.01, canvas:GetEffectiveScale())
        ping:SetParent(canvas)
        ping:SetFrameLevel(canvas:GetFrameLevel() + 2290)
        ping:ClearAllPoints()
        ping:SetSize(side, side)
        ping:SetPoint("CENTER", canvas, "TOPLEFT", f.x * canvas:GetWidth(), -f.y * canvas:GetHeight())
        ping:Show()
        ping.ag:Play()
    end)
    C_Timer.After(12, function()
        if ping and pingToken == token then ping.ag:Stop() ping:Hide() end
    end)
end

local function AskedTip(owner, a)
    local ok, pv = pcall(ns.QuestPreview or function() end, a.quest)
    pv = ok and pv or nil
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(pv and pv.name or a[1], 1, 0.82, 0)
    if pv and pv.level then
        local from = pv.minLevel and pv.minLevel ~= pv.level and ("  (from " .. pv.minLevel .. ")") or ""
        GameTooltip:AddLine("Level " .. pv.level .. from, 1, 1, 1)
    end
    local from = pv and pv.people and pv.people.from and pv.people.from[1]
    if from then GameTooltip:AddLine(from, 0.8, 0.8, 0.8) end
    if a.side == "H" then GameTooltip:AddLine("The Horde's", 1, 0.25, 0.25) end
    if a.side == "A" then GameTooltip:AddLine("The Alliance's", 0.35, 0.6, 1) end
    local st = QuestState(a.quest)
    if st == "have" then GameTooltip:AddLine("In your quest log", 0.12, 1, 0)
    elseif st == "done" then GameTooltip:AddLine("Done", 0.62, 0.62, 0.62)
    else GameTooltip:AddLine("Not taken yet", 0.8, 0.8, 0.8) end
    ns.Hints({ { "Click", st == "have" and "open it in your log" or "read it" }, { "Shift-click", "show the giver on the map" } })
    GameTooltip:Show()
end

-- click: the quest (the book stays open); Shift-click: its giver on the map (the book folds)
local function AskedClick(a)
    if not a.quest then return end  -- (a line with no quest behind it yet)
    if IsShiftKeyDown() then ShowGiver(a.quest) return end
    if ns.OpenQuest then ns.OpenQuest(a.quest) end   -- (the quest window off: the game's log)
end

-- the ribbon at the top of the left page, by the gutter (Media\\Notes\\Ribbon.tga: silk, a
-- swallowtail): to the "before" spread and back. Its word sits on the page beside it.
local function Ribbon(label, tip, onClick)
    local r = left.ribbon
    if not r then
        r = CreateFrame("Button", nil, left)
        r:SetSize(17, 92)
        local sh = r:CreateTexture(nil, "BACKGROUND")
        sh:SetTexture(NOTES .. "Ribbon")
        sh:SetTexCoord(8 / 64, 56 / 64, 0, 251 / 256)
        sh:SetVertexColor(0, 0, 0, 0.25)
        sh:SetPoint("TOPLEFT", 3, -2)
        sh:SetPoint("BOTTOMRIGHT", 3, -2)
        r.silk = r:CreateTexture(nil, "ARTWORK")
        r.silk:SetTexture(NOTES .. "Ribbon")
        r.silk:SetTexCoord(8 / 64, 56 / 64, 0, 251 / 256)
        r.silk:SetAllPoints()
        -- (aged: some of its colour gone, darker, so it sits in the book rather than on it)
        if r.silk.SetDesaturation then r.silk:SetDesaturation(0.45) end
        r.silk:SetVertexColor(0.66, 0.58, 0.54)
        r:SetScript("OnEnter", function(self)
            self.silk:SetVertexColor(0.82, 0.74, 0.7)
            if self.tip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.tip, 1, 0.93, 0.78, true)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function(self)
            self.silk:SetVertexColor(0.66, 0.58, 0.54)
            GameTooltip:Hide()
        end)
        r.label = left:CreateFontString(nil, "OVERLAY")
        SetHand(r.label, 14, HAND_BODY)
        r.label:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
        r.label:SetPoint("TOPRIGHT", left, "TOPRIGHT", -52, -8)
        left.ribbon = r
    end
    r:SetFrameLevel(left:GetFrameLevel() + 13)
    r:ClearAllPoints()
    r:SetPoint("TOPRIGHT", left, "TOPRIGHT", -28, 4)
    r.label:SetText(label)
    r.label:Show()
    r.tip = tip
    r:SetScript("OnClick", onClick)
    r:Show()
end

local function Before(dg)
    local book, id = dg.before, dg.id
    local kind = ns.BookKindNow()
    local story = kind == "story"
    local mine = who ~= "wanderer" and Mine(id)
    -- (the page as lines, yours over the book's; BookOwn.lua)
    local b = ns.BookBeforeView(book, kind, mine and mine.before)
    b.title, b.where, b.asked = book.title, book.where, book.asked
    local i = spread
    local editing = writing and (tool == "words" or tool == "text")
    local deep = story and i >= DeepFrom() and not dg.sepia  -- (sepia: a page written in the old brown ink again)
    local hand = deep and DEEP_INK or INK
    local INK, INK_SOFT = INK, INK_SOFT  -- (the whole page in the deep's ink: title, margin, lists)
    if deep then INK, INK_SOFT = DEEP_INK, DEEP_SOFT end
    local function Edit(field, k)  -- (as the wanderer: rewrite a line in place; empty removes it)
        return function(p, x, y, w, size, font, color, text, put)
            Hit(p, x, y, w, select(2, Layout(text, w, size, font)), function()
                EditAt(p, x, y, w, size, font, color, text, function(t)
                    if who ~= "wanderer" then  -- (yours: over the book's line, which stays underneath)
                        local own = ns.BookMineBefore(Mine(id, true))
                        if field == "added" then
                            if t == "" then table.remove(own.added, k) else own.added[k].s = t end
                        else
                            local was = book[field]
                            if k then was = was[k] end
                            own.text[k and (field .. ":" .. k) or field] = t ~= "" and { s = t, was = was } or { gone = true, was = was }
                        end
                        Show(spread)
                        return
                    end
                    local c = AuthorCopy(spread).before
                    if k then
                        if t == "" then table.remove(c[field], k) else c[field][k] = t end
                    elseif field == "rule" then
                        c.rule[2] = t ~= "" and t or nil
                        if not c.rule[2] then c.rule = nil end
                    else
                        c[field] = t ~= "" and t or nil
                    end
                    Show(spread)
                end, put, true)
            end)
        end
    end
    -- words down a page; gives the y under them
    local function Put(p, text, x, y, w, size, font, color, key, edit)
        local wds, h = Layout(text, w, size, font)
        local put = Place(p, wds, x, y, size, color, font, id .. ":before:" .. key)
        if editing and edit then edit(p, x, y, w, size, font, color, text, put) end
        return y - h
    end
    -- a new line: yours under the page's, or as the wanderer the diary's own
    local function NewLine(p, x, y, w)
        EditAt(p, x, y, w, BODY, who == "wanderer" and HAND_BODY or HAND_YOURS, who == "wanderer" and hand or PENCIL, "", function(t)
            if t == "" then return end
            if who == "wanderer" then
                local c = AuthorCopy(spread).before
                c.diary = c.diary or {}
                c.diary[#c.diary + 1] = t
            else
                local own = ns.BookMineBefore(Mine(id, true)).added
                own[#own + 1] = { s = t }
            end
            Show(spread)
        end, nil, true)
    end
    local function AddButton(p, x, y, label, width, fn)
        local add = Button(p, width, 22, fn)
        SetHand(add.label, 16, HAND_BODY)
        add.label:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
        add.label:SetText(label)
        add:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
        add:SetAlpha(0.75)
    end
    local function AddButtons(p, x, y, w)
        if not editing then return end
        AddButton(p, x, y, "+ a line", 80, function() NewLine(p, x, y, w) end)
        if who ~= "wanderer" then return end
        local bx = x + 86
        for _, f in ipairs({ { "margin", "+ a remark", 100 }, { "bring", "+ what to bring", 130 } }) do
            if not b[f[1]] then
                AddButton(p, bx, y, f[2], f[3], function()
                    EditAt(p, x, y, w, 15, HAND_BODY, hand, "", function(t)
                        AuthorCopy(spread).before[f[1]] = t ~= "" and t or nil
                        Show(spread)
                    end, nil, true)
                end)
                bx = bx + f[3] + 6
            end
        end
    end

    Ribbon("back to the page", "Back to the dungeon's own page.", function()
        beforeOf = nil
        Sound("IG_ABILITY_PAGE_TURN")
        Show(spread)
    end)
    left.ribbon.label:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])  -- (in the page's ink)

    -- left: the road there
    local title = Text(left, 28, INK)
    title:SetPoint("TOPLEFT", 40, -26)
    title:SetText(b.title or ("Before " .. (dg.title or dg.tab or id)))
    local where = Text(left, 15, INK_SOFT)
    where:SetPoint("TOPLEFT", 40, -62)
    where:SetText(b.where or "")
    -- (the scene takes what room the words leave it: never past the page's foot)
    local width = PW - 40 - 34
    local textH = 0
    for _, l in ipairs(b.lines) do textH = textH + select(2, Layout(l.s, width, BODY, HAND_BODY)) + 7 end
    for _, l in ipairs(b.added) do textH = textH + select(2, Layout(l.s, width, BODY, HAND_YOURS)) + 7 end
    if b.margin then textH = textH + select(2, Layout(b.margin, width - 20, 15, HAND_BODY)) + 10 end
    if b.whisper then textH = textH + 30 end
    local sceneH = math.max(96, math.min((PW - 70) * SCENE_H / SCENE_W, PH - 80 - 8 - 34 - textH))
    if not story then sceneH = 0 end  -- (the scene is the story's)
    local sceneW = sceneH * SCENE_W / SCENE_H
    local scene = left.scene
    if story and not scene and ns.InkHost then
        scene = ns.InkHost(left)
        scene.paper = true  -- (on bare paper: the whispers' words keep their rim)
        left.scene = scene
    end
    if scene and story then
        scene:ClearAllPoints()
        scene:SetPoint("TOP", left, "TOPLEFT", 36 + (PW - 70) / 2, -80)
        scene:SetSize(sceneW, sceneH)
        scene:SetFrameLevel(left:GetFrameLevel() + 2)
        scene:Show()
        if ns.InkDrawList then ns.InkDrawList(scene, SceneInk(dg, i)) end
    end
    local y = -80 - sceneH - 8
    for _, l in ipairs(b.lines) do
        y = Put(left, l.s, 40, y, width, BODY, l.yours and HAND_YOURS or HAND_BODY, l.yours and PENCIL or hand, "diary" .. l.k, Edit("diary", l.k)) - 7
    end
    -- (your own lines after the page's; what doesn't fit goes on under the facing page's)
    local spill = {}
    for _, l in ipairs(b.added) do
        local _, h = Layout(l.s, width, BODY, HAND_YOURS)
        if #spill > 0 or y - h < -(PH - 60) then
            spill[#spill + 1] = l
        else
            y = Put(left, l.s, 40, y, width, BODY, HAND_YOURS, PENCIL, "added" .. l.k, Edit("added", l.k)) - 7
        end
    end
    local room = #spill == 0 and y - 26 > -(PH - 40)
    if room then
        AddButtons(left, 40, y, width)
        if editing then y = y - 26 end
    end
    if b.margin then
        y = Put(left, b.margin, 52, y - 4, width - 20, 15, HAND_BODY, b.marginYours and PENCIL or INK_SOFT, "margin", Edit("margin")) - 6
    end
    if b.whisper then
        Put(left, b.whisper, 120, math.min(y - 6, -(PH - 70)), width - 90, 15, HAND_WHISPER, WHISPER, "whisper", who == "wanderer" and Edit("whisper") or nil)
    end

    -- right: who asked us (a Forever dungeon's once its quests have ids)
    local askedOn = ns.NotebookAskedOn(dg)
    local asked = askedOn and b.asked or {}
    y = -26
    if askedOn then
        local head = Text(right, 24, INK)
        head:SetPoint("TOPLEFT", 44, -26)
        head:SetText("Who asked us")
        y = -62
    end
    local rw = PW - 44 - 34 - 58
    -- (an errand of the other side's: soft ink, marked whose, and its words as overheard: heard)
    local faction = UnitFactionGroup("player")
    for k, a in ipairs(asked) do
        local other = a.side and a.side ~= (faction == "Horde" and "H" or "A")
        local text = a[1] .. (other and story and a.heard or a[2] or "")
        local wds, h = Layout(text, rw, 15, HAND_BODY)
        Place(right, wds, 44, y, 15, other and INK_SOFT or hand, HAND_BODY, id .. ":asked:" .. k)
        -- (your quests: your pencil on the line, ns.NotebookPencil; the other side's: whose, in soft ink)
        if other then
            local mark = Text(right, 13, INK_SOFT)
            mark:SetPoint("TOPRIGHT", right, "TOPLEFT", PW - 30, y - 2)
            mark:SetText(a.side == "H" and "the Horde's" or "the Alliance's")
        else
            ns.NotebookPencil(right, QuestState(a.quest), 44, y, wds, h, 15, id .. ":asked:" .. k)
        end
        local row = Hit(right, 44, y, rw + 50, h, function() AskedClick(a) end)
        row:SetScript("OnEnter", function(self) AskedTip(self, a) end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        y = y - h - 9
    end
    if b.bring then
        local h5 = Text(right, 18, INK)
        h5:SetPoint("TOPLEFT", 44, y - 6)
        h5:SetText("What to bring")
        y = Put(right, b.bring, 44, y - 30, PW - 44 - 34, 15, b.bringYours and HAND_YOURS or HAND_BODY, b.bringYours and PENCIL or hand, "bring", Edit("bring")) - 6
    end
    if b.rule then
        local who5 = Text(right, 16, INK_SOFT)
        who5:SetPoint("TOPLEFT", 44, y - 8)
        who5:SetText(b.rule[1])
        y = Put(right, b.rule[2], 44, y - 30, PW - 44 - 34, 17, HAND_BODY, hand, "rule", who == "wanderer" and Edit("rule") or nil) - 6
    end
    y = y - 8
    for _, l in ipairs(spill) do
        y = Put(right, l.s, 44, y, PW - 44 - 34, BODY, HAND_YOURS, PENCIL, "added" .. l.k, Edit("added", l.k)) - 7
    end
    if not room then AddButtons(right, 44, y, PW - 44 - 34) end
end

-- The hand's prints on a page: not put there, left there. Where a hand holds a book (the outer
-- edges, the bottom corners, now and then the top), often cut off by the paper's edge. The cult's
-- ink never quite dries, so after Blackfathom the Wanderer's fingers carry it onto most pages, more
-- as the book goes on, the whispers' violet in it from the Kraul. Before: one faint sepia print now
-- and then. The Temple: a smear dragged through the words. Depths: one brown print pressed hard (the
-- old ink again); the Spire: the deep's back, violet in it. Dire Maul: a faint brown one; Scholomance,
-- Stratholme: brown and a deep one at the edge. Onyxia: half a print
-- by the line that stops. { cell, ink, bleed, alpha, rot, size, side = "left"|"right", x, y |
-- at = "last" }; a page's own list in dg.prints.
local function PrintsOf(dg, i)
    if dg.prints then return dg.prints end
    local id = dg.id
    local r = Rand(Hash("prints:" .. id))
    local function Spot(kind, side)
        local x, y
        if kind == "edge" then
            x = side == "left" and Between(r, -16, 8) or Between(r, PW - 8, PW + 16)
            y = -Between(r, 190, 470)
        elseif kind == "corner" then
            x = side == "left" and Between(r, 12, 54) or Between(r, PW - 54, PW - 12)
            y = -Between(r, PH - 40, PH - 6)
        else  -- the top
            x, y = Between(r, 120, PW - 120), Between(r, -16, 6)
        end
        return x, y
    end
    local function One(ink, alpha, bleed, cell, kind, side)
        side = side or (r() < 0.5 and "left" or "right")
        kind = kind or ({ "edge", "edge", "corner", "corner", "top" })[math.floor(r() * 5) + 1]
        local x, y = Spot(kind, side)
        return { cell = cell or math.floor(r() * 2), ink = ink, bleed = bleed, alpha = alpha, rot = Between(r, -0.9, 0.9),
                 size = Between(r, 70, 92), side = side, x = x, y = y }
    end
    -- (after the Temple: sepia again, one print pressed hard; the black creeps back by the Spire;
    -- the old man's return warm and light; then sepia with the deep's at the edge)
    if id == "depths" then return { One(1, 0.9, 0, 2, "edge") } end
    if id == "spire" then return { One(3, 0.85, 0.5), One(3, 0.75, 0.55), One(3, 0.8, 0.45) } end
    if id == "diremaul" then return { One(1, 0.45, 0, nil, "corner") } end
    if id == "scholomance" or id == "stratholme" then return { One(1, 0.45, 0, nil, "corner"), One(3, 0.6, 0.3, nil, "edge") } end
    if id == "temple" then
        return { { cell = 2, ink = 3, bleed = 0.55, alpha = 0.8, rot = Between(r, -0.3, 0.3), size = 104, side = "left",
                   x = Between(r, 190, 260), y = -Between(r, 260, 340) },
                 One(3, 0.8, 0.5, 0, "edge", "right") }
    end
    if id == "onyxia" then return { { cell = 3, ink = 3, bleed = 0.45, alpha = 0.85, rot = Between(r, -0.5, 0.2), size = 88, at = "last" } } end
    local deep = DeepFrom()
    if i < deep - 1 then return r() < 0.35 and { One(1, 0.45) } or {} end
    if i == deep - 1 then return { One(3, 0.8, 0, 0, "edge", "right") } end  -- (Blackfathom: the first black one)
    local from
    for k, d in ipairs(Data()) do if d.id == "kraul" then from = k end end
    local bleed = from and i >= from and math.min(0.45, 0.12 + (i - from) * 0.07) or 0
    local out = {}
    for _ = 1, math.min(3, 1 + math.floor((i - deep) / 3)) do out[#out + 1] = One(3, Between(r, 0.6, 0.88), bleed) end
    return out
end

-- the prints on a page's clipped layer (last: where the page's last line ended, { page, x, y });
-- with no page, they're all put away
local function DrawPrints(dg, i, last)
    for _, p in ipairs({ left, right }) do p.prints.used = 0 end
    for _, pr in ipairs(dg and PrintsOf(dg, i) or {}) do
        local p, x, y = pr.side == "right" and right or left, pr.x, pr.y
        if pr.at == "last" and last then p, x, y = last[1], last[2] + 250, last[3] - 6 end
        if type(pr.at) == "table" then p, x, y = PagePoint(pr.at) end  -- (a spot on the open book, as the marks')
        local L = p.prints
        L.used = L.used + 1
        local t = L.pairs[L.used]
        if not t then
            t = { b = L.ink:CreateTexture(nil, "ARTWORK", nil, 1), m = L.ink:CreateTexture(nil, "ARTWORK", nil, 2) }
            L.pairs[L.used] = t
        end
        ApplyThumb(t.m, t.b, dg.id, pr, pr.size or 80)
        t.m:ClearAllPoints()
        t.m:SetPoint("CENTER", p, "TOPLEFT", x, y)
        t.m:Show()
    end
    for _, p in ipairs({ left, right }) do
        for k = p.prints.used + 1, #p.prints.pairs do
            p.prints.pairs[k].m:Hide()
            p.prints.pairs[k].b:Hide()
        end
    end
end

local function Dungeon(dg)
    local story = ns.BookKindNow() == "story"
    dg = ns.BookPageView(dg, ns.BookKindNow())  -- (without the story's lines in a notes or blank book)
    local id = dg.id or tostring(spread)
    local editing = tool == "words" or tool == "text"  -- (edit, or jot: the page's lines can be rewritten)
    local wanderer = writing and who == "wanderer" and editing
    local words = writing and editing
    -- (from Blackfathom's own page on, written after the cult's ink was taken: the deep's blue-black)
    local INK, INK_SOFT = INK, INK_SOFT
    if spread >= DeepFrom() - 1 and not dg.sepia then INK, INK_SOFT = DEEP_INK, DEEP_SOFT end

    -- the wanderer's own lines: title, where, caption (rewritable as the wanderer; p, x, y: where it's put)
    local function Line(fs, p, x, y, field, size, font, color)
        if not wanderer then return end
        local w = math.max(60, fs:GetStringWidth())
        Hit(p, x, y, w, fs:GetStringHeight(), function()
            EditAt(p, x, y, math.max(w + 40, 220), size, font, color, dg[field] or "", function(v)
                AuthorCopy(spread)[field] = v ~= "" and v or nil
                Show(spread)
            end, { fs })
        end)
    end

    -- (laid out top-down by measured heights: y is from the page's top)
    local y = -30
    local title = Text(left, 30, INK)
    title:SetWidth(PW - 40 - 112)
    title:SetText(dg.title or dg.tab or id)
    title:SetPoint("TOPLEFT", 40, y)
    Line(title, left, 40, y, "title", 30, HAND, INK)
    y = y - title:GetStringHeight() - 4
    local where = Text(left, 15, INK_SOFT)
    where:SetWidth(PW - 40 - 112)
    where:SetText(dg.where or "")
    where:SetPoint("TOPLEFT", 40, y)
    Line(where, left, 40, y, "where", 15, HAND, INK_SOFT)
    y = y - where:GetStringHeight() - 18

    -- the facing page: the map, under its line
    -- (status: our own pencil note on a page still being made, in red, over the caption; the release
    -- build drops it, and locks the page if it's on the book's unfinished list)
    local capY = -30
    if dg.status then
        local st = Text(right, 15, RED, nil, HAND_YOURS)
        st:SetPoint("TOPLEFT", 44, -12)
        st:SetWidth(PW - 44 - 34)
        st:SetText(dg.status)
        capY = -12 - st:GetStringHeight() - 8
    end
    local views = NoteViews(dg)
    local cap = Text(right, 18, INK, nil, HAND_BODY)
    cap:SetPoint("TOPLEFT", 44, capY)
    cap:SetWidth(PW - 44 - 34)
    cap:SetText(dg.mapCaption or "")
    Line(cap, right, 44, capY, "mapCaption", 18, HAND_BODY, INK)
    local floors = Floors(dg)
    local rightY = capY - cap:GetStringHeight() - 18
    if #floors > 0 then
        local k = mapFloor[id] or FirstNotedFloor(dg, floors)
        k = math.max(1, math.min(#floors, k))
        DrawMap(dg, floors, k, rightY, views)
        rightY = rightY - MAP_H - 50
    end

    -- the notes: down the left page (room kept for the sign-off, the margin
    -- remark and the page number), then on under the map
    -- (the margin remark wraps at MARGIN_W: at the foot it keeps its height free; dragged
    -- elsewhere (marginAt), the notes make way for it there instead)
    local mWords, mH, mPage, mX, mY
    if dg.margin then
        mWords, mH = Layout(dg.margin, MARGIN_W, 15, HAND_BODY)
        mPage, mX, mY = left, 58, -(PH - 42 - mH)
        if dg.marginAt then mPage, mX, mY = PagePoint(dg.marginAt) end
    end
    local floorY = -(PH - (dg.margin and not dg.marginAt and 42 + mH + 14 or 50))
    local function MakeWay(pg, nx, nw, ny, nh)
        if dg.marginAt and mPage == pg and nx < mX + MARGIN_W and nx + nw > mX and ny > mY - mH - 6 and ny - nh < mY + 6 then
            return mY - mH - 10
        end
        return ny
    end
    local page, x, width = left, 62, PW - 62 - 36

    -- the page's own lines (dg.asides): the evening's writing, not numbered, a little larger,
    -- in among the notes: { "words", after = the note they follow (0: before the first, none:
    -- after the last), hand = "whisper" (the other hand, smaller, in their own violet-black) or "ewen"
    -- (Ewen's own few lines, her hand and her green ink) }
    -- every line laid out, in order (as the wanderer: a line dragged up or down takes its new
    -- place in it; notes carry their rings with them, page lines their place between notes)
    local slots = {}
    local function Reorder(from, dx, dy)
        local sx, sy = from.x + dx, from.top + dy
        local pi = from.page == right and 2 or 1
        if pi == 1 and sx > PW then pi = 2 elseif pi == 2 and sx < 0 then pi = 1 end
        local at = 0
        for _, s in ipairs(slots) do
            if s ~= from then
                local spi = s.page == right and 2 or 1
                if spi < pi or (spi == pi and s.top - s.h / 2 > sy) then at = at + 1 end
            end
        end
        local seq = {}
        for _, s in ipairs(slots) do if s ~= from then seq[#seq + 1] = s end end
        table.insert(seq, at + 1, from)
        local c = AuthorCopy(spread)
        local notes, asides, n = {}, {}, 0
        local turned = false  -- (the first one meant for the right page starts it: turn)
        for _, s in ipairs(seq) do
            local line
            if s.kind == "note" then
                line = c.notes[s.i]
                notes[#notes + 1] = line
                n = n + 1
            else
                line = c.asides[s.k]
                line.after = n
                asides[#asides + 1] = line
            end
            local onRight = (s == from and pi or (s.page == right and 2 or 1)) == 2
            line.turn = (onRight and not turned) or nil
            if onRight then turned = true end
        end
        c.notes, c.asides = notes, #asides > 0 and asides or nil
        Show(spread)
    end
    local asides = {}
    for k, a in ipairs(dg.asides or {}) do
        local at = math.min(a.after or #views, #views)
        asides[at] = asides[at] or {}
        table.insert(asides[at], k)
    end
    local function Aside(k)
        local a = dg.asides[k]
        local whisper = a.hand == "whisper"
        local size, font, color = whisper and 15 or 19, whisper and HAND_WHISPER or HAND_BODY, whisper and WHISPER or INK
        if a.hand == "ewen" then size, font, color = 17, HAND_EWEN, EWEN end  -- (Ewen's, in her own ink)
        local ax = x - 14
        local w = (page == left and y > -150 and width - 64 or width) + 14
        y = y - 4
        local wds, h = Layout(a[1], w, size, font)
        y = MakeWay(page, ax, w, y, h)
        if page == left and (a.turn or y - h < floorY) then
            page, x, y = right, 66, rightY
            ax, w = x - 14, width + 14
            wds, h = Layout(a[1], w, size, font)
            y = MakeWay(page, ax, w, y, h)
        end
        -- (a.ink: how far the deep's blue-black is in its ink, 0 the page's own, 1 the deep's; a.deep on a
        -- whisper: darker, heavier violet, them at full strength)
        local own
        if a.deep and whisper then
            own = { 0.20, 0.03, 0.26 }
        elseif a.ink and not a.hand then
            local t = a.ink
            own = { INK[1] + (DEEP_INK[1] - INK[1]) * t, INK[2] + (DEEP_INK[2] - INK[2]) * t, INK[3] + (DEEP_INK[3] - INK[3]) * t }
        end
        local put = Place(page, wds, ax, y, size, color, font, id .. ":aside:" .. k, nil,
                          { press = a.press, wobble = a.wobble, turnAt = a.inkTurn, ink = own })
        local slot = { kind = "aside", k = k, page = page, x = ax, top = y, h = h }
        slots[#slots + 1] = slot
        if wanderer then
            local p, px, py = page, ax, y
            Hit(p, px, py, w, h, function()
                EditAt(p, px, py, w, size, font, color, a[1], function(t)
                    local c = AuthorCopy(spread)
                    if t == "" then table.remove(c.asides, k) else c.asides[k][1] = t end
                    Show(spread)
                end, put, true)
            end, function()
                Menu({
                    { "make it a numbered note", function()
                        local c = AuthorCopy(spread)
                        local line = table.remove(c.asides, k)
                        local after = line.after or #(c.notes or {})
                        c.notes = c.notes or {}
                        table.insert(c.notes, after + 1, { line[1] })
                        -- (page lines after it now come after the new note)
                        for j, o in ipairs(c.asides) do
                            local oa = o.after or #c.notes
                            if oa > after or (oa == after and j >= k) then o.after = oa + 1 end
                        end
                        if #c.asides == 0 then c.asides = nil end
                        Show(spread)
                    end },
                    { whisper and "in the wanderer's own hand" or "in the other hand (the whispers)", function()
                        AuthorCopy(spread).asides[k].hand = not whisper and "whisper" or nil
                        Show(spread)
                    end },
                    { "remove it", function()
                        local c = AuthorCopy(spread)
                        table.remove(c.asides, k)
                        if #c.asides == 0 then c.asides = nil end
                        Show(spread)
                    end },
                })
            end, function(dx, dy) Reorder(slot, dx, dy) end)
        end
        y = y - h - 10
    end
    for _, k in ipairs(asides[0] or {}) do Aside(k) end

    for i, v in ipairs(views) do
        local size, font, color = BODY, HAND_BODY, INK
        if v.yours then size, font, color = YOURS, HAND_YOURS, PENCIL end
        local text = v.crossed and ("~" .. v.text .. "~") or v.text
        -- (narrower beside the stamp in the top corner)
        local w = page == left and y > -150 and width - 64 or width
        local wds, h = Layout(text, w, size, font)
        y = MakeWay(page, x, w, y, h)
        local need = h + (i == #views and 50 or 0)
        if page == left and (v.turn or y - need < floorY) then
            page, x, y = right, 66, rightY  -- doesn't fit (or dragged there): this one and the rest under the map
            w = width
            wds, h = Layout(text, w, size, font)
            y = MakeWay(page, x, w, y, h)
        end
        -- (dg.inkCreep = { from, to }: the deep's blue-black creeping into the page's ink note by note,
        -- the first note that much in, the last this much)
        local creep
        if dg.inkCreep and not v.yours then
            local cr = dg.inkCreep
            local t = cr[1] + (cr[2] - cr[1]) * (i - 1) / math.max(1, #views - 1)
            creep = { ink = { INK[1] + (DEEP_INK[1] - INK[1]) * t, INK[2] + (DEEP_INK[2] - INK[2]) * t, INK[3] + (DEEP_INK[3] - INK[3]) * t } }
        end
        local put = Place(page, wds, x, y, size, color, font, id .. ":" .. i .. ":" .. v.text, nil, creep)
        local num = Text(page, 16, v.yours and PENCIL or RED)
        num:SetPoint("TOPRIGHT", page, "TOPLEFT", x - 6, y - 1)
        num:SetText(i)
        if writing then  -- (the menu on its spot on a map can rewrite it with any tool in hand)
            local p, nx, ny = page, x, y
            v.rewrite = function()
                EditAt(p, nx, ny, w, size, font, color, v.text, function(t)
                    if t == "" or t == v.text then return end
                    NoteChange(v, function(n, kind)
                        if kind == "wanderer" then n[1] = t else n.s = t end
                    end)
                end, put)
            end
            local slot = v.book and { kind = "note", i = v.book, page = page, x = x, top = y, h = h }
            if slot then slots[#slots + 1] = slot end
            if words then
                Hit(page, x, y, w, h, v.rewrite, function() NoteMenu(v) end,
                    wanderer and slot and function(dx, dy) Reorder(slot, dx, dy) end or nil)
            end
        end
        y = y - h - 6
        for _, k in ipairs(i > 0 and asides[i] or {}) do Aside(k) end
    end

    if story then DrawPrints(dg, spread, { page, x, y + 26 }) end  -- (the hand's prints; Onyxia's half one by the last line)

    -- a new note, at the end
    y = MakeWay(page, x, width, y, 22)
    if words then
        local p, nx, ny = page, x, y
        local function AddNote()
            local yours = who ~= "wanderer"
            EditAt(p, nx, ny, width, yours and YOURS or BODY, yours and HAND_YOURS or HAND_BODY,
                   yours and PENCIL or INK, "", function(t)
                if t == "" then return end
                if yours then
                    local mine = Mine(id, true)
                    mine.added[#mine.added + 1] = { s = t }
                else
                    local c = AuthorCopy(spread)
                    c.notes = c.notes or {}
                    c.notes[#c.notes + 1] = { t }
                end
                Show(spread)
            end)
        end
        local add = Button(page, who == "wanderer" and 90 or width, 22, AddNote)
        SetHand(add.label, 16, HAND_BODY)
        add.label:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
        add.label:SetText(who == "wanderer" and "+ a note" or "+ a note of your own")
        add:SetPoint("TOPLEFT", page, "TOPLEFT", x, y - 2)
        add:SetAlpha(0.75)
        add:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local mine = Mine(id)
        local gone = false
        for _, n in pairs(mine and mine.notes or {}) do if n.gone then gone = true end end
        if who == "wanderer" then
            -- (beside it: a line of the page's own, not numbered; right-click it: in the other hand)
            local function AddLine(whisper)
                EditAt(p, nx, ny, width, whisper and 15 or 19, whisper and HAND_WHISPER or HAND_BODY,
                       whisper and WHISPER or INK, "", function(t)
                    if t == "" then return end
                    local c = AuthorCopy(spread)
                    c.asides = c.asides or {}
                    c.asides[#c.asides + 1] = { t, hand = whisper and "whisper" or nil }
                    Show(spread)
                end, nil, true)
            end
            local line = Button(page, 90, 22, function(_, button) AddLine(button == "RightButton") end)
            line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            SetHand(line.label, 16, HAND_BODY)
            line.label:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
            line.label:SetText("+ a line")
            line:SetPoint("LEFT", add, "RIGHT", 6, 0)
            line:SetAlpha(0.75)
        elseif gone then
            add:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    Menu({ { "bring back the book's removed notes", function()
                        for _, n in pairs(Mine(id).notes) do n.gone = nil end
                        Show(spread)
                    end } })
                else
                    AddNote()
                end
            end)
        end
        y = y - 26
    end

    -- the sign-off after the notes, or where the wanderer dragged it (signAt: its centre on the book)
    -- (noSign: a page left unsigned; right-click the sign-off as the wanderer to leave it off)
    local sp, sx, sy = page, x + 170, y - 20
    if dg.signAt then sp, sx, sy = PagePoint(dg.signAt) end
    if not dg.noSign then
        local sign = SignOff(sp, id, 44, INK)
        sign:SetPoint("CENTER", sp, "TOPLEFT", sx, sy)
        if dg.signStruck then
            -- (struck by the whispers: one calm, thin line in their violet, no effort in it)
            -- (one stroke, sure of itself: a little jagged, pressed at the start and lifting at the end)
            local half = sign:GetWidth() * 0.3
            local r = Rand(Hash("signStruck:" .. id))
            local n = 6
            local px, py = sx - half, sy + 2
            for j = 1, n do
                local t = j / n
                local nx = sx - half + half * 2.2 * t
                local ny = sy + 2 - 4 * t + Between(r, -1.4, 1.4) + (j == 1 and -1.5 or 0)
                local l = Take(sp, "line", function() return sp:CreateLine(nil, "OVERLAY", nil, 2) end)
                l:SetColorTexture(WHISPER[1], WHISPER[2], WHISPER[3], 0.92 - 0.2 * t)
                l:SetThickness(2.1 - 1.1 * t)
                l:SetStartPoint("TOPLEFT", sp, px, py)
                l:SetEndPoint("TOPLEFT", sp, nx, ny)
                px, py = nx, ny
            end
        end
        if wanderer then
            local side = sign:GetWidth() * 0.5
            Hit(sp, sx - side / 2, sy + side / 4, side, side / 2, nil, function()
                Menu({ { "leave this page unsigned", function()
                    AuthorCopy(spread).noSign = true
                    Show(spread)
                end } })
            end, function(dx, dy)
                AuthorCopy(spread).signAt = BookPoint(sp, sx + dx, sy + dy)
                Show(spread)
            end)
        end
    elseif wanderer then
        local b = Button(sp, 90, 20, function()
            AuthorCopy(spread).noSign = nil
            Show(spread)
        end)
        SetHand(b.label, 15, HAND_BODY)
        b.label:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.6)
        b.label:SetText("+ sign it")
        b:SetPoint("CENTER", sp, "TOPLEFT", sx, sy)
    end

    -- the ribbon: this dungeon's "before we go" page
    if dg.before then
        Ribbon("before we go", "The night before: the road there, who asked us, what to bring.", function()
            beforeOf = spread
            Sound("IG_ABILITY_PAGE_TURN")
            Show(spread)
        end)
        left.ribbon.label:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])  -- (in the page's ink)
    end

    -- the margin remark: the left page's foot, or where the wanderer dragged it (marginAt: its top left)
    -- (wrapped by the page; Shift + Enter breaks a line where the wanderer wants it)
    local function SetMargin(v)
        v = strtrim(v or "")
        AuthorCopy(spread).margin = v ~= "" and v or nil
        Show(spread)
    end
    if dg.margin then
        local mp, mx, my = mPage, mX, mY
        local put = Place(mp, mWords, mx, my, 15, INK_SOFT, HAND_BODY, id .. ":margin")
        if wanderer then
            Hit(mp, mx, my, MARGIN_W, mH, function()
                EditAt(mp, mx, my, MARGIN_W + 20, 15, HAND_BODY, INK_SOFT, dg.margin, SetMargin, put, true)
            end, nil, function(dx, dy)
                AuthorCopy(spread).marginAt = BookPoint(mp, mx + dx, my + dy)
                Show(spread)
            end)
        end
    elseif wanderer then
        local b = Button(left, 180, 20, function()
            EditAt(left, 58, -(PH - 48), MARGIN_W + 20, 15, HAND_BODY, INK_SOFT, "", SetMargin, nil, true)
        end)
        SetHand(b.label, 15, HAND_BODY)
        b.label:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.6)
        b.label:SetText("+ a remark in the margin")
        b:SetPoint("TOPLEFT", left, "TOPLEFT", 58, -(PH - 48))
    end
end

-- The quill and its bar -------------------------------------------------------------

local quill, wbar, catcher

local function SpreadId()
    local dg = Data()[spread]
    return dg and dg.id or "flyleaf"
end

-- the wanderer's marks on this spread (make: on the copy to change)
local function BookMarks(make)
    if beforeOf then  -- (the "before" page's own ink, beside its scene)
        if make then
            local c = AuthorCopy(spread).before
            c.marks = c.marks or {}
            return c.marks
        end
        local b = Entry(spread).before
        return b and b.marks or {}
    end
    if spread == 0 then
        local a = Cfg().author
        if make then
            Cfg().author = a or {}
            a = Cfg().author
            a.flyleafMarks = a.flyleafMarks or Copy(Data().flyleafMarks or {})
            return a.flyleafMarks
        end
        return a and a.flyleafMarks or Data().flyleafMarks or {}
    end
    if make then
        local c = AuthorCopy(spread)
        c.marks = c.marks or {}
        return c.marks
    end
    return Entry(spread).marks or {}
end

local function MyMarks(make)
    if beforeOf then
        local id = SpreadId()
        local mine = Mine(id, make)
        if not mine then return {} end
        if not make and not mine.before then return {} end
        local b = ns.BookMineBefore(mine)
        b.marks = b.marks or {}
        return b.marks
    end
    Cfg().marks = Cfg().marks or {}
    local k = SpreadId()
    if make and not Cfg().marks[k] then Cfg().marks[k] = {} end
    return Cfg().marks[k] or {}
end

local function DrawInk()
    if not (inkHost and ns.InkDrawList) then return end
    local list = {}
    if ns.BookKindNow() == "story" then
        for _, m in ipairs(BookMarks()) do list[#list + 1] = m end
    end
    for _, m in ipairs(MyMarks()) do list[#list + 1] = m end
    ns.InkDrawList(inkHost, list)
end

-- Where marks go: the open spread (0-1 across the book) or a map (0-1 across its
-- picture, kept with its floor). A surface: its ink host, its list of marks
-- (yours, or as the wanderer the book's), and how it's drawn again.
local surfaceMeta = {}
surfaceMeta.__index = surfaceMeta

function surfaceMeta:Cursor()
    local h = self.host
    local x, y = GetCursorPosition()
    local s = h:GetEffectiveScale()
    return (x / s - h:GetLeft()) / h:GetWidth(), (h:GetTop() - y / s) / h:GetHeight()
end

-- the mark of yours (as the wanderer: the book's) under the cursor: within 10 px
-- of a line, anywhere on a ring or a sign as big as it's drawn, along a note's words
-- (other: the other hand's, to say whose it is)
function surfaceMeta:Nearest(other)
    local x, y = self:Cursor()
    local saved = who
    if other then who = who == "wanderer" and "you" or "wanderer" end
    local list = self.list(false)
    who = saved
    local w, h = self.host:GetWidth(), self.host:GetHeight()
    local k = w / 1002
    local best, bd = nil, 10
    for i, m in ipairs(list) do
        local sc = m.sc or 1
        local px, py = m.p[1] * w, m.p[2] * h
        local cx, cy = x * w, y * h
        local d
        if m.t == "sketch" then
            d = ns.InkSketchDist(m, w, h, cx, cy)
        elseif m.t == "text" then
            local len = #(m.s or "") * 17 * k * sc * 0.42
            local tx = math.max(px, math.min(px + len, cx))
            d = math.sqrt((cx - tx) ^ 2 + (cy - py) ^ 2) - 9 * k * sc
        elseif #m.p == 2 then
            d = math.sqrt((cx - px) ^ 2 + (cy - py) ^ 2) - 24 * k * sc * 0.75
        else
            d = ns.InkPathDist(m.p, w, h, cx, cy)
        end
        if d < bd then best, bd = i, d end
    end
    return best, list
end

-- (changes go on list(true): as the wanderer that's the book's copy, never the shipped entry;
-- undo: { list, add } took one in, { list, back, at } rubbed one out, { mark, p } moved one)
function surfaceMeta:Add(m)
    local list = self.list(true)
    list[#list + 1] = m
    undo[#undo + 1] = { list = list, add = m, surf = self }
    self.redraw()
end

function surfaceMeta:RubOut(i)
    local list = self.list(true)
    undo[#undo + 1] = { list = list, back = list[i], at = i, surf = self }
    table.remove(list, i)
    self.redraw()
end

-- a mark's size: a step up or down (d), or by Ctrl + wheel over it (true when there was one)
function surfaceMeta:Size(i, d)
    local m = self.list(true)[i]
    local sc = math.max(0.4, math.min(3, (m.sc or 1) * (d > 0 and 1.12 or 1 / 1.12)))
    sc = math.floor(sc * 100 + 0.5) / 100
    m.sc = math.abs(sc - 1) > 0.03 and sc or nil
    self.redraw()
end

function surfaceMeta:Resize(d)
    local i = self:Nearest()
    if not i then return false end
    self:Size(i, d)
    return true
end

-- a written mark's words, again (empty: it goes)
function surfaceMeta:Rewrite(i)
    local m = self.list(true)[i]
    ns.InkAsk(who == "wanderer" and "The wanderer's words:" or "Your words in the book:", m.s or "", function(v)
        if v == "" then self:RubOut(i) else m.s = v self.redraw() end
    end)
end

local function SpreadSurface()
    return setmetatable({ host = inkHost,
        list = function(make) return who == "wanderer" and BookMarks(make) or MyMarks(make) end,
        draw = DrawInk, redraw = DrawInk }, surfaceMeta)
end

MapSurface = function(m)
    local function draw()
        if ns.InkDrawList then ns.InkDrawList(m.ink, MapInkList(m.dg, m.floor)) end
    end
    return setmetatable({ host = m.ink, map = m,
        list = function(make) return MapMarks(m.dg, m.floor, who == "wanderer", make) end,
        draw = draw,
        redraw = function()
            draw()
            if ns.UpdateInk then ns.UpdateInk() end  -- (the dungeon map shows the same ink)
        end }, surfaceMeta)
end

-- the mark under the cursor and the surface it's on: the map's ink, else (on the
-- page's map) the page's ink over it, as marks drawn there before the map had its own
-- (other: the other hand's)
local function Picked(surf, other)
    local i = surf:Nearest(other)
    if i then return surf, i end
    if surf.map and surf.map == right.map then
        local s = SpreadSurface()
        i = s:Nearest(other)
        if i then return s, i end
    end
end

local drawOn  -- the surface the mark being drawn goes on

-- rubbing out on a surface while the button's down: { surf, list, snap, changed } (one undo for it all)
local rubbing
local function RubAt()
    local r = rubbing
    local h = r and r.surf.host
    if not h then return end
    local x, y = r.surf:Cursor()
    if not x then return end
    local radius = 9 * UIParent:GetEffectiveScale() / math.max(0.01, h:GetEffectiveScale())
    if ns.InkErase(r.list, x, y, h:GetWidth(), h:GetHeight(), radius) then
        r.changed = true
        r.surf.draw()
    end
end

local function Round(v) return math.floor(v * 10000 + 0.5) / 10000 end

-- the tools that draw a line as you drag (Ink.lua's)
local PATHS = { pen = true, feather = true, route = true, wander = true, pass = true, tracks = true }

-- a note's spot on a map under the cursor (its ring or its number)
SpotUnder = function(m)
    if not (m and m.spots and m:IsVisible()) then return end
    local cx, cy = GetCursorPosition()
    local s = m:GetEffectiveScale()
    cx, cy = cx / s - m:GetLeft(), cy / s - m:GetTop()
    for i = #m.spots, 1, -1 do
        local sp = m.spots[i]
        local r = math.max(7, sp.r * 0.6)
        if sp.nd and (cx - sp.x - sp.dx) ^ 2 + (cy - sp.y - sp.dy) ^ 2 < (r * 0.6) ^ 2 then return sp, true end
        if (cx - sp.x) ^ 2 + (cy - sp.y) ^ 2 < r * r
            or (cx - sp.x - sp.dx) ^ 2 + (cy - sp.y - sp.dy) ^ 2 < (r * 0.8) ^ 2 then
            return sp
        end
    end
end

-- a note's number dragged round its ring: it follows the cursor's angle from the ring's middle
local function SpotTurnNumber(sp, m)
    local cx, cy = GetCursorPosition()
    local s = m:GetEffectiveScale()
    cx, cy = cx / s - m:GetLeft(), cy / s - m:GetTop()
    local a = math.atan2(cy - sp.y, cx - sp.x)
    sp.dx, sp.dy = math.cos(a) * sp.nd, math.sin(a) * sp.nd
    sp.Put(sp.x, sp.y)
    return math.floor(math.deg(a) + 0.5) % 360
end

-- Ctrl + wheel over a note's ring: its size (rs, a half to two and a half), kept with the note
SpotSize = function(sp, d)
    if not sp then return false end
    local rs = math.max(0.5, math.min(2.5, (sp.view.rs or 1) * (d > 0 and 1.12 or 1 / 1.12)))
    NoteSet(sp.view, "rs", math.floor(rs * 100 + 0.5) / 100)
    return true
end

-- rubbing out what's the other hand's: say whose it is
local function Whose(surf)
    if not Picked(surf, true) then return end
    UIErrorsFrame:AddMessage(who == "wanderer" and "That's your own ink: rub it out writing as yourself."
        or "This ink is old and doesn't rub out easily.", 1, 0.82, 0.5)
end

local function DrawDown(surf)
    if not surf.host then return end
    if tool == "erase" then
        local sp = SpotUnder(surf.map)
        if sp then
            NoteSet(sp.view, "mark", "off")  -- (the note stays; its menu, or undo, puts it back)
            return
        end
        -- (the page's map: its own ink, else the page's ink over it, as Picked)
        if surf.map and not Picked(surf) and surf.map == right.map then
            local s2 = SpreadSurface()
            if Picked(s2) then surf = s2 end
        end
        local list = surf.list(true)
        rubbing = { surf = surf, list = list, snap = ns.InkCopyList(list), changed = false }
        RubAt()
        if not rubbing.changed then Whose(surf) end
        return
    end
    local x, y = surf:Cursor()
    if PATHS[tool] then
        cur, drawOn = ns.InkNewMark(tool, inkIdx, x, y), surf
        cur.sx, cur.sy = GetCursorPosition()
    elseif tool == "text" then
        local yours = who ~= "wanderer"
        ns.InkAsk(yours and "Your words in the book:" or "The wanderer's words:", "", function(v)
            if v ~= "" then surf:Add(ns.InkNewMark("text", inkIdx, x, y, v, ns.QuillHand())) end
        end)
    else
        local m = ns.InkNewMark(tool, inkIdx, x, y)
        surf:Add(m)
        if tool == "stairs" and surf.map and ns.InkStairsMenu then
            ns.InkStairsMenu(m, "d" .. surf.map.dg.instance .. ":" .. surf.map.floor, surf.redraw)
        end
    end
end

local function DrawUp()
    if rubbing then
        local r = rubbing
        rubbing = nil
        if r.changed then ns.QuillUndo({ list = r.list, snapshot = r.snap, surf = r.surf }) end
        return
    end
    if not cur then return end
    local m, surf = cur, drawOn
    cur, drawOn = nil, nil
    m.sx, m.sy = nil, nil
    ns.InkDrawLive(surf.host, nil)
    if #m.p >= 4 then surf:Add(m) end
end

local function DrawUpdate()
    if rubbing then
        if IsMouseButtonDown("LeftButton") then RubAt() else DrawUp() end
        return
    end
    if not cur then return end
    if not IsMouseButtonDown("LeftButton") then DrawUp() return end
    local sx, sy = GetCursorPosition()
    if math.sqrt((sx - cur.sx) ^ 2 + (sy - cur.sy) ^ 2) / UIParent:GetEffectiveScale() < 3 then return end
    cur.sx, cur.sy = sx, sy
    local x, y = drawOn:Cursor()
    cur.p[#cur.p + 1] = Round(x)
    cur.p[#cur.p + 1] = Round(y)
    ns.InkDrawLive(drawOn.host, cur)
end

local function Drawing() return writing and tool ~= nil and tool ~= "words" end

-- Picking up (any tool but the pen and the rubber): a note's spot on a map or a
-- mark, dragged somewhere else (a note's spot snaps onto a boss's). Let go where
-- it was and it's a click: a written mark's words again (words or note tool),
-- else the tool's own click.
local grab

-- (a note's ring with any tool; a mark with any but the path tools)
-- (Ctrl: pick it up whatever's in hand, the drawing tools and rub out too; Ctrl + a click alone does nothing)
local function Press(surf)
    local alt = IsControlKeyDown()
    if (tool == "erase" and not alt) or placing then return false end
    local sp, onNum = SpotUnder(surf.map)
    local i
    if not sp then
        if PATHS[tool] and not alt then return false end
        surf, i = Picked(surf)
    end
    if not (sp or i) then return false end
    local sx, sy = GetCursorPosition()
    local cx, cy = surf:Cursor()
    grab = { surf = surf, spot = sp, num = onNum, i = i, sx = sx, sy = sy, cx = cx, cy = cy, alt = alt }
    return true
end

local function GrabUpdate()
    local g = grab
    if not g then return end
    local sx, sy = GetCursorPosition()
    if not g.moved then
        if math.sqrt((sx - g.sx) ^ 2 + (sy - g.sy) ^ 2) / UIParent:GetEffectiveScale() < 4 then return end
        g.moved = true
        if g.i then
            g.mark = g.surf.list(true)[g.i]
            g.p0 = Copy(g.mark.p)
        end
    end
    if g.mark then
        local x, y = g.surf:Cursor()
        for j = 1, #g.p0 - 1, 2 do
            g.mark.p[j], g.mark.p[j + 1] = Round(g.p0[j] + x - g.cx), Round(g.p0[j + 1] + y - g.cy)
        end
        g.surf.draw()
    elseif g.spot and g.num then
        g.na = SpotTurnNumber(g.spot, g.surf.map)
    elseif g.spot then
        local m = g.surf.map
        local s = m:GetEffectiveScale()
        g.spot.Put(math.max(0, math.min(m:GetWidth(), sx / s - m:GetLeft())),
                   math.max(-m:GetHeight(), math.min(0, sy / s - m:GetTop())))
    end
end

-- let go: true when it was a move (else the press, for the click)
local function GrabUp()
    local g = grab
    grab = nil
    if not (g and g.moved) then return false, g end
    if g.mark then
        undo[#undo + 1] = { mark = g.mark, p = g.p0, surf = g.surf }
        g.surf.redraw()
    elseif g.num then
        if g.na then NoteSet(g.spot.view, "na", g.na) end
    else
        local m = g.surf.map
        local x, y = MapPoint(m)
        x, y = math.max(0, math.min(1, x)), math.max(0, math.min(1, y))
        NoteChange(g.spot.view, function(n) n.floor, n.x, n.y = m.floor, x, y end)
    end
    return true
end

local function Clicked(g)
    if not (g.i and (tool == "words" or tool == "text")) then return false end
    local m = g.surf.list(false)[g.i]
    if not (m and m.t == "text") then return false end
    g.surf:Rewrite(g.i)
    return true
end

-- right-click in write mode: a note's spot -> the note's menu; a mark -> its own
local function Context(surf)
    local sp = SpotUnder(surf.map)
    if sp then
        NoteMenu(sp.view, nil, true)
        return true
    end
    local i
    surf, i = Picked(surf)
    if not i then return false end
    local items = {}
    local m = surf.list(false)[i]
    if m.t == "text" then items[1] = { "rewrite it", function() surf:Rewrite(i) end } end
    if m.t == "stairs" and surf.map and ns.InkStairsMenu then
        local key = "d" .. surf.map.dg.instance .. ":" .. surf.map.floor
        items[#items + 1] = { "where they lead", function() ns.InkStairsMenu(m, key, surf.redraw) end }
    end
    if m.t == "lock" and ns.InkLockItems then ns.InkLockItems(m, items, surf.redraw) end
    if ns.InkHandItem then ns.InkHandItem(m, items, surf.redraw) end
    if ns.InkTurnItems then ns.InkTurnItems(m, items, surf.redraw, function() return surf.list(true)[i] end) end
    items[#items + 1] = { "bigger", function() surf:Size(i, 1) end }
    items[#items + 1] = { "smaller", function() surf:Size(i, -1) end }
    items[#items + 1] = { "rub it out", function() surf:RubOut(i) end }
    Menu(items)
    return true
end

-- over the spread: on the page's map if the cursor's on it
-- the "before" page's scene: its pieces move, size and rub out, and new ink goes beside them (kept
-- in the wanderer's copy's before.ink, or your own copy of the scene). Off the scene, the page's own
-- ink: anywhere on the spread (BookMarks, MyMarks).
local function BeforeSurface()
    local h = left.scene
    if not (beforeOf and h and h:IsShown()) then return end
    -- (a change always goes in the wanderer's copy: the shipped page can carry its own before.ink, as
    -- Deadmines does, and changing that one was lost on reload)
    local function list(make)
        if not make then return SceneInk(Entry(spread), spread) end
        if who ~= "wanderer" then
            local dg = Entry(spread)
            local own = ns.BookMineBefore(Mine(dg.id, true))
            if not own.scene then own.scene = Copy(SceneInk(dg, spread)) end
            return own.scene
        end
        local e = AuthorCopy(spread)
        if not e.before.ink then e.before.ink = SceneInk(e, spread) end
        return e.before.ink
    end
    return setmetatable({ host = h, list = list,
        draw = function() if ns.InkDrawList then ns.InkDrawList(h, list(false)) end end,
        redraw = function() Show(spread) end }, surfaceMeta)
end

local function SurfaceUnderCursor()
    if beforeOf then
        local sc = left.scene
        if sc and sc:IsShown() and sc:IsMouseOver() then return BeforeSurface() end
        return SpreadSurface()
    end
    local m = right.map
    if m:IsShown() and m.dg and m.ink and m:IsMouseOver() then return MapSurface(m) end
    return SpreadSurface()
end

-- Ctrl + wheel anywhere in the book, the quill in hand: the note ring or the ink mark under the
-- cursor grows or shrinks, as on the Battlefield map (true when there was one)
local function SizeUnderCursor(d)
    if not writing then return false end
    local m = right.map
    if m:IsShown() and m.dg and m:IsMouseOver() and SpotSize(SpotUnder(m), d) then return true end
    local surf = SurfaceUnderCursor()
    local s, i
    if surf then s, i = Picked(surf) end
    if s then
        s:Size(i, d)
        return true
    end
    return false
end

local function CatcherDown(_, button)
    if button ~= "LeftButton" then return end
    local surf = SurfaceUnderCursor()
    if not surf then return end
    if not Press(surf) and not IsControlKeyDown() and tool ~= "words" then DrawDown(surf) end
end

-- a book map's dungeon and floor on the Battlefield map; the book (and the big map) shut so it's seen
local function OpenOnBattlefield(m)
    if not (m and m.dg) then return end
    if BattlefieldMapFrame and not BattlefieldMapFrame:IsShown() and ToggleBattlefieldMap then ToggleBattlefieldMap() end
    if ns.PreviewDungeon then ns.PreviewDungeon(m.dg.instance) end
    if ns.DungeonGoFloor then ns.DungeonGoFloor(m.dg.instance, m.floor) end
    if zoom and zoom:IsShown() then
        zoom:Hide()
        Show(spread)
    end
    if open:IsShown() then
        open:Hide()
        cover:Show()
        Sound("IG_SPELLBOOK_CLOSE")
    end
end

local function CatcherUp(_, button)
    if button == "RightButton" then
        -- (a mark's or a ring's menu; off them, the map's menu or the quill's: Controls.lua)
        local surf = SurfaceUnderCursor()
        if surf and not Context(surf) then
            if surf.map and surf.map.emptyMenu then surf.map.emptyMenu() else ns.BookPageMenu() end
        end
    elseif grab then
        local moved, g = GrabUp()
        if not moved and not g.alt and not Clicked(g) and tool ~= "words" then DrawDown(g.surf) end
    else
        DrawUp()
    end
end

-- a book map's mouse, as every map's (Controls.lua): a press on a ring, its number or a mark
-- picks it up (Ctrl, or the quill out with any tool or none but rub out; a drawing tool draws
-- over marks, not rings); right-click a thing: its menu, quill or not; right-click empty map:
-- the page's map, its menu (big, on the Battlefield map), the big one back to the page, the
-- quill out the map's menu; a drawing tool in hand draws; else a click places a note, opens
-- the page's map big, or closes the big one. The big map pans with a drag (right-drag always).
WireMap = function(m, big)
    m:EnableMouse(true)
    -- (right-click on empty map)
    m.emptyMenu = function()
        if not m.dg then return end
        if big then
            ns.MapRightClick(function() zoom:Click() end, "back to the page")
            return
        end
        local items = { { "bigger, here in the book", function() MapClick(m, "LeftButton") end },
                        { "open on the Battlefield Map", function() OpenOnBattlefield(m) end } }
        if writing then
            if #undo > 0 then table.insert(items, 1, { "undo", ns.QuillUndoLast }) end
            items[#items + 1] = { "put the quill down", function() ns.SetQuill(false) end }
        end
        Menu(items)
    end
    m:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not placing and ns.PicksUp() and Press(MapSurface(self)) then return end
        -- (the big map: right-drag moves the view; without a drawing tool a left-drag does too)
        if big and (button == "RightButton" or not Drawing()) then
            local sx, sy = GetCursorPosition()
            zoom.pan = { sx = sx, sy = sy, ox = zoom.ox, oy = zoom.oy, button = button }
            return
        end
        if button == "LeftButton" and Drawing() and not placing then DrawDown(MapSurface(self)) end
    end)
    m:SetScript("OnMouseUp", function(self, button)
        if big and zoom.pan then
            local p = zoom.pan
            zoom.pan = nil
            if p.moved then return end
        end
        if grab then
            local moved, g = GrabUp()
            if moved or Clicked(g) then return end
            if Drawing() then DrawDown(g.surf) return end
            if g.alt then return end  -- (Ctrl + a click alone does nothing)
        elseif cur then
            DrawUp()
            return
        elseif button == "RightButton" then
            if not placing and not Context(MapSurface(self)) then self.emptyMenu() end
            return
        elseif Drawing() and not placing then
            return
        end
        if big and not placing then
            zoom:Click()
            return
        end
        MapClick(self, button)
    end)
    m:SetScript("OnUpdate", function()
        local p = big and zoom.pan
        if p and IsMouseButtonDown(p.button) then
            local sx, sy = GetCursorPosition()
            local s = zoom.view:GetEffectiveScale()
            if p.moved or math.sqrt((sx - p.sx) ^ 2 + (sy - p.sy) ^ 2) / s > 4 then
                p.moved = true
                zoom.ox, zoom.oy = p.ox + (sx - p.sx) / s, p.oy + (sy - p.sy) / s
                ZoomPlace()
            end
        end
        if grab and grab.surf.host == m.ink then GrabUpdate() end
        if rubbing and rubbing.surf.host == m.ink then DrawUpdate() end
        if cur and drawOn and drawOn.host == m.ink then DrawUpdate() end
    end)
end

-- One quill for the book and the Battlefield map: one bar, one tool, one ink, one
-- who. Each frame catches its own clicks (here the pages and maps, in Ink.lua the
-- map), so a mark goes on whatever's under the cursor. The bar sits under the
-- open book, else along the map's bottom edge; dragged by its grip, it stays
-- where it's put (notebook.barPos; right-click the grip: back to its place).
local TOOLS = {
    { "words", "edit", "The page's own lines: click one to rewrite it, drag it to move it, right-click it for more. \"+ a note\" and \"+ a line\" add one. On a map: drag a note's ring or a mark to move it, right-click it for more." },
    "|",
    { "pen", "quill", "Drag to draw." },
    { "feather", "feather", "Drag to draw with a feathered quill: thick or thin with the stroke's direction, a drop of ink where you start, drier as it goes." },
    { "route", "route", "Drag your path; the arrow goes where you stop." },
    { "wander", "wanders", "Drag where it walks; end near the start for a loop." },
    { "pass", "passage", "Drag across a wall: a secret door or a drop." },
    { "tracks", "paws", "Drag where the dog went: paw prints." },
    "|",
    { "ring", "ring", "Click: a ring." },
    { "x", "X", "Click: an X." },
    { "q", "?", "Click: a question mark. Right-click (or the arrow): how it's written." },
    { "bang", "!", "Click: an exclamation mark. Right-click (or the arrow): how it's written." },
    { "stairs", "stairs", "Click: stairs. On a dungeon map, choose the floor they lead to: with the quill put down, a click on them turns the map there. Right-click (or the arrow): how they're drawn." },
    { "jump", "drop", "Click: a ledge and the way down over it. Right-click (or the arrow): how it's drawn." },
    { "lock", "lock", "Click: a way shut. Right-click (or the arrow): a lock, a key or a barred door." },
    { "chest", "chest", "Click: a treasure chest. Right-click (or the arrow): how it's drawn." },
    { "blot", "blot", "Click: a blot of spilt ink, never the same twice." },
    "|",
    { "text", "jot", "Jot words anywhere, as ink: click where they go, then type them. A click on one of the page's own lines still rewrites it. As the wanderer, right-click (or the arrow): whose hand, the wanderer's or the whispers'." },
    { "erase", "rub out", "Rub over ink to take it away: a line only where you rub, a small mark or words whole. A note's ring: off the map (its menu puts it back). One undo takes back the whole rub." },
}

local UpdateBar, BuildBar
local function SetWriting(on)
    KeptWho()
    if on and not writing then tool = nil end  -- (taken up: no tool in hand yet, the map works as usual)
    writing = on and true or false
    cur, placing, grab = nil, nil, nil
    if edit then edit.done = nil edit:Hide() edit.old = nil end
    if menu then menu:Hide() end
    if writing and not wbar then BuildBar() end
    UpdateBar()
    if ns.InkQuill then ns.InkQuill(writing and tool ~= nil) end  -- (no tool: the map works as usual)
    if ns.DungeonQuillChanged then ns.DungeonQuillChanged() end  -- (the boss markers let clicks through to the ink)
    if book and book:IsShown() and open:IsShown() then Redraw() end  -- (the big map stays: pick a tool and draw on it)
    NotesChanged()
end

-- a tool's looks for its dropdown (the note: whose hand; Ink.lua's choices for the rest)
local function ToolChoices(kind)
    local items
    if kind == "text" then
        if who ~= "wanderer" then return end
        items = { { "the wanderer's own hand", not whisperHand, function() whisperHand = false end, font = HAND_BODY },
                  { "the other hand", whisperHand, function() whisperHand = true end, font = HAND_WHISPER, color = WHISPER } }
    else
        items = ns.InkChoices and ns.InkChoices(kind)
    end
    if not items then return end
    local out = {}
    for _, it in ipairs(items) do
        out[#out + 1] = { it[1], function()
            it[3]()
            UpdateBar()
        end, on = it[2], mark = it[4], font = it.font, color = it.color }
    end
    return out
end

local function BarButton(label, onClick, tip)
    local b = CreateFrame("Button", nil, wbar)
    b.label = b:CreateFontString(nil, "OVERLAY")
    SetHand(b.label, 16)
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b:SetSize(math.max(22, b.label:GetStringWidth() + 14), 24)
    b.on = b:CreateTexture(nil, "BACKGROUND")
    b.on:SetAllPoints()
    b.on:SetColorTexture(0.24, 0.14, 0.06, 0.85)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.55, 0.35, 0.12, 0.2)
    b:SetScript("OnClick", onClick)
    if tip then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    wbar.items[#wbar.items + 1] = b
    return b
end

local function Gap()
    local g = CreateFrame("Frame", nil, wbar)
    g:SetSize(9, 24)
    g.line = g:CreateTexture(nil, "ARTWORK")
    g.line:SetColorTexture(0.24, 0.14, 0.06, 0.3)
    g.line:SetPoint("TOP", 0, -3)
    g.line:SetPoint("BOTTOM", 0, 3)
    g.line:SetWidth(1)
    wbar.items[#wbar.items + 1] = g
end

-- where it sits (see above), its buttons flowed in rows as wide as there's room for
local function PlaceBar()
    if not wbar then return end
    local maxW = W
    wbar:ClearAllPoints()
    local pos = Cfg().barPos
    local area = ns.InkBarArea and ns.InkBarArea()
    if pos then
        wbar:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    elseif book and book:IsShown() and open:IsShown() then
        wbar:SetPoint("TOP", open, "BOTTOM", 0, -6)
    elseif area then
        wbar:SetPoint("BOTTOM", area, "BOTTOM", 0, 4)
        maxW = math.max(200, area:GetWidth() * area:GetEffectiveScale() / wbar:GetEffectiveScale() - 8)
    else
        wbar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
    end
    local x, y, widest, row, rowEnd = 20, -4, 0, 1, {}
    for _, b in ipairs(wbar.items) do
        local w = b:GetWidth()
        if x + w > maxW and x > 20 then x, y, row = 20, y - 26, row + 1 end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", wbar, "TOPLEFT", x, y - (24 - b:GetHeight()) / 2)
        x = x + w + 2
        rowEnd[row] = x
        widest = math.max(widest, x)
    end
    -- the book's button: the right end of the second row (one of its own when there's one row)
    if wbar.book then
        wbar.bookLabel()
        local by = -4 - 26
        widest = math.max(widest, (rowEnd[2] or 20) + wbar.book:GetWidth() + 2)
        if y > by then y = by end
        wbar.book:ClearAllPoints()
        wbar.book:SetPoint("TOPRIGHT", wbar, "TOPRIGHT", -6, by)
    end
    wbar:SetSize(widest + 6, -y + 28)
end

BuildBar = function()
    wbar = CreateFrame("Frame", "WaymarkQuillBar", UIParent, "BackdropTemplate")
    ns.AddonWindow(wbar, function()
        if Cfg().barPos then
            local p, _, rp, x, y = wbar:GetPoint()
            Cfg().barPos = { p, rp, x, y }
        end
    end)
    wbar:SetFrameStrata("DIALOG")
    wbar:SetClampedToScreen(true)
    -- the notebook's paper, a strip of it
    local paper = wbar:CreateTexture(nil, "BACKGROUND")
    paper:SetPoint("TOPLEFT", 2, -2)
    paper:SetPoint("BOTTOMRIGHT", -2, 2)
    paper:SetTexture(NOTES .. "Paper")
    paper:SetTexCoord(0.08, 0.62, 0.34, 0.40)
    paper:SetVertexColor(0.97, 0.93, 0.85)
    wbar:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
    wbar:SetBackdropBorderColor(0.3, 0.19, 0.08)
    wbar:EnableMouse(true)
    wbar:SetMovable(true)
    -- the grip: drag the bar by it
    local grip = CreateFrame("Button", nil, wbar)
    grip:SetPoint("TOPLEFT", 3, -3)
    grip:SetPoint("BOTTOMLEFT", 3, 3)
    grip:SetWidth(14)
    grip.label = grip:CreateFontString(nil, "OVERLAY")
    SetHand(grip.label, 20)
    grip.label:SetPoint("CENTER", 0, 2)
    grip.label:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
    grip.label:SetText(":")
    grip:RegisterForDrag("LeftButton")
    grip:RegisterForClicks("RightButtonUp")
    grip:SetScript("OnDragStart", function() wbar:StartMoving() end)
    grip:SetScript("OnDragStop", function()
        wbar:StopMovingOrSizing()
        local p, _, rp, x, y = wbar:GetPoint()
        Cfg().barPos = { p, rp, x, y }
    end)
    grip:SetScript("OnClick", function()
        Cfg().barPos = nil
        PlaceBar()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("The quill's bar")
        ns.Hints({ { "Drag", "put it somewhere else" }, { "Right-click", "back under the book or the map" } })
        -- (the same on every map: the Battlefield map, its dungeon map, the book's maps; Controls.lua)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("On every map, with the quill out:", 1, 0.82, 0)
        GameTooltip:AddDoubleLine("Click, Drag", "the tool", 0.9, 0.9, 0.9, 1, 1, 1)
        GameTooltip:AddDoubleLine("Drag a thing", "moves it (drawing tools: rings only)", 0.9, 0.9, 0.9, 1, 1, 1)
        GameTooltip:AddDoubleLine("Ctrl-drag", "moves anything, quill or not", 0.9, 0.9, 0.9, 1, 1, 1)
        GameTooltip:AddDoubleLine("Right-click a thing", "its menu, quill or not", 0.9, 0.9, 0.9, 1, 1, 1)
        GameTooltip:AddDoubleLine("Right-click empty map", "undo, out, the quill down", 0.9, 0.9, 0.9, 1, 1, 1)
        GameTooltip:AddDoubleLine("Right-drag", "moves the map", 0.9, 0.9, 0.9, 1, 1, 1)
        GameTooltip:AddDoubleLine("Wheel", "zoom", 0.9, 0.9, 0.9, 1, 1, 1)
        GameTooltip:AddDoubleLine("Shift-wheel", "the floors", 0.9, 0.9, 0.9, 1, 1, 1)
        GameTooltip:AddDoubleLine("Ctrl-wheel on a thing", "its size", 0.9, 0.9, 0.9, 1, 1, 1)
        GameTooltip:AddDoubleLine("Shift-click a mark", "its tooltip", 0.9, 0.9, 0.9, 1, 1, 1)
        ns.Hints({ { "Right-click a tool with an arrow", "how it looks" } })
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    wbar.items, wbar.tools, wbar.who, wbar.inks = {}, {}, {}, {}
    for _, w in ipairs({ { "you", "as yourself", "Your words go over the book's in your own hand and ink; the book's stay underneath. On the map: your own ink." },
                         { "wanderer", "as the wanderer", "Writing the book itself: what you change here is the book (tools\\export_notes.py writes it into Data\\FoundNotes.lua). On a found-notes dungeon map: the book's marks for that floor; elsewhere on the map it's your own ink." } }) do
        if ns.BOOK_AUTHOR and w[1] == "wanderer" then
            wbar.who[w[1]] = BarButton(w[2], function()
                who = w[1]
                Cfg().asPlayer = nil  -- (out of /bfi notes me for good, not just till the next reload)
                inkIdx = who == "wanderer" and 1 or 3
                SetWriting(true)
                ns.NotebookRefresh()  -- (the whole book again, on the page and the maps)
            end, w[3])
        end
    end
    Gap()
    for _, t in ipairs(TOOLS) do
        if t == "|" then
            Gap()
        else
            local kind = t[1]
            local b
            b = BarButton(t[2], function(self, button)
                tool = kind
                SetWriting(true)
                -- (right-click, or the little arrow: how it looks)
                if button == "RightButton" or (self.arrow and self.arrow:IsShown() and self.arrow:IsMouseOver(4, -4, -2, 2)) then
                    local items = ToolChoices(kind)
                    if items then Menu(items) end
                end
            end, t[3])
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            if kind == "text" or (ns.InkChoices and ns.InkChoices(kind)) then
                b.arrow = b:CreateTexture(nil, "OVERLAY")
                b.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
                b.arrow:SetSize(9, 9)
                b.arrow:SetPoint("RIGHT", -3, -1)
                b.arrow:SetVertexColor(INK[1], INK[2], INK[3], 0.8)
                b:SetWidth(b:GetWidth() + 9)
                b.label:ClearAllPoints()
                b.label:SetPoint("CENTER", -4, 0)
            end
            wbar.tools[kind] = b
        end
    end
    Gap()
    -- the inks: blots
    for i, c in ipairs(ns.INK_COLORS or {}) do
        local b = BarButton("", function() inkIdx = i UpdateBar() end, ({ "Sepia", "Red", "Blue-black", "Ewen's grey-green", "Tam's charcoal" })[i])
        b:SetSize(24, 24)
        b.on:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        b.on:SetVertexColor(0.24, 0.14, 0.06, 0.85)
        b.swatch = b:CreateTexture(nil, "ARTWORK")
        b.swatch:SetPoint("TOPLEFT", 4, -4)
        b.swatch:SetPoint("BOTTOMRIGHT", -4, 4)
        b.swatch:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        b.swatch:SetVertexColor(c[1], c[2], c[3])
        wbar.inks[i] = b
    end
    Gap()
    BarButton("reset", function()
        if not (open and open:IsShown()) then return end
        local items = { { "reset this page (your words and ink are set aside)", function() ns.BookReset(false) end } }
        if ns.BookHasAside(Cfg(), SpreadId()) then
            items[2] = { "bring back what was reset here", function() ns.BookBack(false) end }
        end
        Menu(items)
    end, "This page back to the book's own. Your words and ink on it are set aside, and can be brought back.")
    BarButton("undo", function() ns.QuillUndoLast() end, "Takes back the last mark, move or rubbing out, on the book or the map. (Ctrl + wheel over a mark: its size.)")
    -- (the bar's undo, also in the maps' menus: Controls.lua)
    ns.QuillCanUndo = function() return #undo > 0 end
    ns.QuillUndoLast = function()
        local u = table.remove(undo)
        if not u then return end
        if u.noteView then  -- (a note's ring: off the map, or sized; as whoever changed it)
            local saved = who
            who = u.who or who
            NoteChange(u.noteView, function(n) n[u.field] = u.old end)
            who = saved
            return
        elseif u.snapshot then  -- (a rubbing out: the list as it was)
            for i = #u.list, 1, -1 do u.list[i] = nil end
            for i, m in ipairs(u.snapshot) do u.list[i] = m end
        elseif u.p then
            u.mark.p = u.p
        elseif u.back then
            table.insert(u.list, math.min(u.at, #u.list + 1), u.back)
        else
            for i = #u.list, 1, -1 do
                if u.list[i] == u.add then table.remove(u.list, i) break end
            end
        end
        u.surf.redraw()
    end
    BarButton("done", function()
        tool = nil
        SetWriting(true)
    end, "No tool in hand: the maps and the book work as usual, the quill's bar stays out.")
    BarButton("close", function() SetWriting(false) end, "Put the quill away (the book's and the map's).")
    -- the book opened or put away from the bar (PlaceBar puts it bottom left, the user 2026-11-03)
    wbar.book = BarButton("open notebook", function() ns.ToggleNotebook() end)
    table.remove(wbar.items)  -- (not in the rows)
    wbar.bookLabel = function()
        local shown = book and book:IsShown()
        wbar.book.label:SetText(shown and "close notebook" or "open notebook")
        wbar.book:SetWidth(wbar.book.label:GetStringWidth() + 14)
    end
end

UpdateBar = function()
    if quill then quill.lit:SetShown(writing) end
    if dm and dm.quill then dm.quill.lit:SetShown(writing) end
    if ns.RefreshToggles then ns.RefreshToggles() end  -- (the map's quill button, lit in hand)
    if catcher then
        -- (over both pages; with the edit tool, only over a "before" page's scene, so its pieces can be
        -- moved while the lines stay clickable)
        local sc = beforeOf and tool == "words" and left.scene
        if sc and not sc:IsShown() then sc = nil end
        catcher:SetShown(writing and tool ~= nil and (tool ~= "words" or sc ~= nil))
        catcher:ClearAllPoints()
        if sc then
            catcher:SetAllPoints(sc)
        else
            catcher:SetPoint("TOPLEFT", open, "TOPLEFT", PAD_L, -PAD_T)
            catcher:SetSize(2 * PW, PH)
        end
        catcher:SetFrameLevel(right:GetFrameLevel() + 12)
        right.map.big:SetShown(writing)
        right.map.big:SetFrameLevel(right:GetFrameLevel() + 14)
    end
    if not wbar then return end
    wbar:SetShown(writing)
    local function Lit(b, on)
        b.on:SetShown(on)
        b.label:SetTextColor(on and 0.95 or INK[1], on and 0.88 or INK[2], on and 0.7 or INK[3])
    end
    for k, b in pairs(wbar.who) do Lit(b, k == who) end
    for k, b in pairs(wbar.tools) do Lit(b, k == tool) end
    if ns.InkVersionLabel then
        -- (the dropdown says how they're written; the lock's label says which of the three it is)
        wbar.tools.lock.label:SetText(ns.InkVersionLabel("lock", "lock"))
        wbar.tools.text.label:SetText(who == "wanderer" and whisperHand and "whisper" or "jot")
    end
    for i, b in ipairs(wbar.inks) do b.on:SetShown(i == inkIdx) end
    PlaceBar()
end

-- the quill's button: our own quill (Media\Quill.tga, tools\quill_icon.py), no square behind it
-- as the map moves under it; ringed in red ink while it's in hand (Media\QuillRing.tga, one brush
-- stroke lifting off in a feathered end, the quest ground's red: tools\quill_ring.py). The book's,
-- and the dungeon map's beside the book's stamp.
function ns.QuillButton(parent, size)  -- (on ns: the file is at Lua's 200 locals)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.lit = b:CreateTexture(nil, "BACKGROUND")
    b.lit:SetPoint("CENTER")
    b.lit:SetSize(size * 1.45, size * 1.45)
    b.lit:SetTexture(ns.MEDIA .. "QuillRing")
    b.lit:SetVertexColor(0.62, 0.2, 0.1)
    b.lit:SetShown(writing)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ns.MEDIA .. "Quill")
    local hi = b:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetTexture(ns.MEDIA .. "Quill")
    hi:SetBlendMode("ADD")
    hi:SetAlpha(0.45)
    b:SetScript("OnClick", function() if ns.QuillToggle then ns.QuillToggle() end end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Write in the book")
        GameTooltip:AddLine("Rewrite its lines, add your own, mark its pages and maps; the Battlefield map too while it's open.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function BuildQuill()
    quill = ns.QuillButton(open, 42)
    quill:SetPoint("BOTTOMLEFT", open, "BOTTOMRIGHT", -2, 26)

    -- drawing: over both pages while a tool other than words is in hand
    catcher = CreateFrame("Frame", nil, open)
    catcher:SetPoint("TOPLEFT", open, "TOPLEFT", PAD_L, -PAD_T)
    catcher:SetSize(2 * PW, PH)
    catcher:EnableMouse(true)
    catcher:SetScript("OnMouseDown", CatcherDown)
    catcher:SetScript("OnMouseUp", CatcherUp)
    catcher:SetScript("OnUpdate", function()
        GrabUpdate()
        DrawUpdate()
    end)
    catcher:EnableMouseWheel(true)
    catcher:SetScript("OnMouseWheel", function(_, d)
        local m = right.map
        if m:IsShown() and m.dg and m:IsMouseOver() then PageMapWheel(m, d) return end
        if IsControlKeyDown() and SizeUnderCursor(d) then return end
        Turn(spread - d)
    end)
    catcher:Hide()
end

-- showing a spread ----------------------------------------------------------------

-- each page its own window of Paper.tga (half across, any way up), its worn
-- edges either way up, now and then a stain from Bits.tga (cup ring, water mark,
-- thumb smudge) and one of three uneven outlines, so no two pages carry the same
-- marks; seeded by the page's number, so a page keeps them
local STAINS = { { 36, 336, 146, 446, 80, 80 }, { 146, 336, 256, 446, 84, 84 }, { 36, 450, 146, 510, 76, 42 } }
local function PaperLook(p, n)
    local r = Rand(Hash("page:" .. n))
    local up = r() < 0.5
    local ol, orr = 0, 1
    if p.mirror then ol, orr = 1, 0 end
    p.over:SetTexCoord(ol, orr, up and 0 or PAGE_V, up and PAGE_V or 0)
    local u, v = r() * 0.5, r() * (1 - PAGE_V)
    local l, rt, t, b = u, u + 0.5, v, v + PAGE_V
    if r() < 0.5 then l, rt = rt, l end
    if r() < 0.5 then t, b = b, t end
    p.paper:SetTexCoord(l, rt, t, b)
    p.stain:Hide()
    if r() < 0.4 then
        local s = STAINS[math.floor(r() * #STAINS) + 1]
        Bits(p.stain, s[1], s[2], s[3], s[4], r() < 0.5)
        p.stain:SetSize(s[5] * Between(r, 0.9, 1.3), s[6] * Between(r, 0.9, 1.3))
        p.stain:ClearAllPoints()
        p.stain:SetPoint("CENTER", p, "TOPLEFT", Between(r, 60, PW - 60), -Between(r, 70, PH - 60))
        p.stain:SetAlpha(Between(r, 0.6, 1))
        p.stain:Show()
    end
    if p.mask then
        local edge = NOTES .. "PageEdge" .. (p.mirror and "L" or "R") .. (math.floor(r() * 3) + 1)
        p.mask:SetTexture(edge, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        p.edgeShadow:SetTexture(edge)
    end
end

Show = function(to)
    notesVersion = notesVersion + 1
    spread = to
    Cfg().spread = to
    Reset(left)
    Reset(right)
    PaperLook(left, 2 * to + 1)
    PaperLook(right, 2 * to + 2)
    right.map:Hide()
    right.map.dg = nil
    if zoom then zoom:Hide() end
    if left.ribbon then left.ribbon:Hide() left.ribbon.label:Hide() end
    DrawPrints(nil)
    if left.scene then left.scene:Hide() end
    if beforeOf ~= to then beforeOf = nil end
    local dg = Entry(to)
    local hands = Data().hands or {}
    pageHand = ns.BookKindNow() == "story" and dg and (beforeOf and dg.before and (hands[dg.id .. ":before"] or hands[dg.id]) or hands[dg.id]) or nil
    if dg and beforeOf and dg.before then Before(dg) elseif dg then Dungeon(dg) else
        Flyleaf()
        if ns.BookKindNow() == "story" then
            DrawPrints({ id = "flyleaf", prints = Data().flyleafPrints or {} }, 0)  -- (a print over a name not struck)
        end
    end
    DrawInk()  -- (a "before" page has its own: BookMarks, MyMarks)
    left.number:SetText(2 * to + 1)
    right.number:SetText(2 * to + 2)
    if writing and UpdateBar then UpdateBar() end  -- (the quill's catcher: the scene on a "before" page, else the spread)
    prevCorner:SetShown(to > 0)
    nextCorner:SetShown(to < Spreads())
    local step = math.min(30, (H - 40 - 72) / math.max(1, #tabs))  -- (closer together in a long book; above the quill)
    for i, tab in ipairs(tabs) do
        Bits(tab.bg, 40, i == to and 44 or 0, 216, i == to and 80 or 36)
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", open, "TOPRIGHT", i == to and -PAD_R + 2 or -PAD_R - 4, -40 - (i - 1) * step)
    end
end

local function BuildTabs()
    for i, dg in ipairs(Data()) do
        local t = tabs[i]
        if not t then
            t = CreateFrame("Button", nil, open)
            t:SetSize(118, 26)
            t:SetFrameLevel(open:GetFrameLevel())
            t.bg = t:CreateTexture(nil, "BACKGROUND")
            t.bg:SetAllPoints()
            t.label = t:CreateFontString(nil, "OVERLAY")
            SetHand(t.label, 13)
            t.label:SetTextColor(INK[1], INK[2], INK[3])
            t.label:SetPoint("LEFT", 28, 0)
            tabs[i] = t
        end
        t.label:SetText(dg.tab or dg.title or dg.id)
        local locked = ns.NotebookLocked(i)
        t:SetAlpha(locked and 0.35 or 1)
        t:SetScript("OnClick", not locked and function() Turn(i) end or nil)
        t:Show()
    end
end

-- the book shut onto its cover (from the spine); a click on the cover opens it on the same page
local function Fold()
    if not (open and open:IsShown()) then return end
    open:Hide()
    cover:Show()
    Sound("IG_SPELLBOOK_CLOSE")
    if writing then UpdateBar() end
end

local function Open()
    cover:Hide()
    open:Show()
    BuildTabs()
    Sound("IG_SPELLBOOK_OPEN")
    local at = math.max(0, math.min(Spreads(), Cfg().spread or 0))
    Show(ns.NotebookLocked(at) and 0 or at)
    if writing then UpdateBar() end  -- (the bar under the book now)
end

-- the book's shadow on whatever's behind it (Board.tga's 0-480 x 690-1010, a soft blurred block)
-- (k: how far it reaches; the closed book lies closer to what's under it)
local function DropShadow(f, k)
    local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    t:SetTexture(NOTES .. "Board")
    t:SetTexCoord(0, 480 / 1024, 690 / 1024, 1010 / 1024)
    t:SetPoint("TOPLEFT", -26 * k, 20 * k)
    t:SetPoint("BOTTOMRIGHT", 40 * k, -38 * k)
end

-- the wanderer's copies that Data\FoundNotes.lua now has (written by tools\export_notes.py)
-- go, so later edits to the file aren't hidden by an old copy
local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- A copy made from an older rev of its page (the file changed since: a tool, or a session's
-- edit) is merged, not set aside (the user, 2026-11-02: their redrawn ink and notes kept coming
-- back as ours). Against the page the copy was made from: what you changed stays yours (each
-- part of the page; the map ink floor by floor), what you didn't takes the file's newer version.
-- Changed on both sides: yours wins. The copy as it was is still kept aside (notebook.stale; an
-- earlier one there under "<id>@<rev>", never overwritten). A copy with no page beside it
-- (made before this) can't be told apart from the file's changes: it stays as it is, the file's
-- newer page waiting under it, until tools\export_notes.py writes it in.
local function DropShipped()
    local a = Cfg().author
    if not a then return end
    Cfg().authorBase = Cfg().authorBase or {}
    local bases = Cfg().authorBase
    local function SetAside(id, c)
        Cfg().stale = Cfg().stale or {}
        local st = Cfg().stale
        if st[id] and not Same(st[id], c) then st[id .. "@" .. tostring(st[id].rev)] = st[id] end
        st[id] = Copy(c)
    end
    -- base -> mine and base -> file, part by part: mine where I changed it, else the file's
    local function Merge(mine, base, file)
        local out = Copy(file)
        for k, v in pairs(mine) do
            if k ~= "rev" and k ~= "mapMarks" and not Same(v, base[k]) then out[k] = Copy(v) end
        end
        for k in pairs(base) do
            if k ~= "rev" and mine[k] == nil then out[k] = nil end  -- (you took it out)
        end
        local mm, bm = mine.mapMarks or {}, base.mapMarks or {}
        local floors = {}
        for f in pairs(mm) do floors[f] = true end
        for f in pairs(bm) do floors[f] = true end
        for f in pairs(floors) do
            if not Same(mm[f], bm[f]) then
                out.mapMarks = out.mapMarks or {}
                out.mapMarks[f] = Copy(mm[f])
            end
        end
        out.rev = file.rev
        return out
    end
    -- (the easy pulls' "!" under their pins, gone 2026-11-02: out of your copies too)
    for _, t in ipairs({ a, bases }) do
        for id, c in pairs(t) do
            for _, list in pairs(id ~= "flyleafMarks" and type(c) == "table" and c.mapMarks or {}) do
                for i = #list, 1, -1 do
                    if list[i].gen == 2 and list[i].t == "bang" then table.remove(list, i) end
                end
            end
        end
    end
    for id, c in pairs(a) do
        if id == "flyleafMarks" then
            if Same(c, Data().flyleafMarks or {}) then a[id] = nil end
        else
            for _, dg in ipairs(Data()) do
                if dg.id == id then
                    -- (the same page, whatever its rev or our status note says: the file has it)
                    local cr, cs, fr, fs = c.rev, c.status, dg.rev, dg.status
                    c.rev, c.status, dg.rev, dg.status = nil, nil, nil, nil
                    local same = Same(c, dg)
                    c.rev, c.status, dg.rev, dg.status = cr, cs, fr, fs
                    if same then
                        a[id], bases[id] = nil, nil  -- (the file has it: tools\export_notes.py wrote it in)
                    elseif dg.rev and c.rev ~= dg.rev and bases[id] then
                        SetAside(id, c)
                        local merged = Merge(c, bases[id], dg)
                        if Same(merged, dg) then
                            a[id], bases[id] = nil, nil
                        else
                            a[id], bases[id] = merged, Copy(dg)
                        end
                    end
                end
            end
        end
    end
    for id in pairs(bases) do if not a[id] then bases[id] = nil end end
end

-- (once, 2026-10-31: the user drew the Deadmines map ink as themselves by accident; it's the wanderer's,
-- so it moves into the book's copy, mapMarks[floor], and tools\export_notes.py takes it into the file)
local function DeadminesInkToWanderer()
    if Cfg().dmInkMoved or not ns.BOOK_AUTHOR then return end  -- (a player's ink is theirs)
    Cfg().dmInkMoved = true
    local all = ns.db and ns.db.inkMarks
    if not all then return end
    for i, dg in ipairs(Data()) do
        if dg.id == "deadmines" then
            for key, list in pairs(all) do
                local floor = tonumber(key:match("^d" .. dg.instance .. ":(%d+)$") or "")
                if floor and #list > 0 then
                    local c = AuthorCopy(i)
                    c.mapMarks = c.mapMarks or {}
                    c.mapMarks[floor] = c.mapMarks[floor] or {}
                    for _, m in ipairs(list) do table.insert(c.mapMarks[floor], m) end
                    all[key] = nil
                end
            end
        end
    end
end

local function Create()
    KeptWho()
    -- (a player's book through an update: BookOwn.lua. Each in its own pcall: an odd saved page must
    -- not keep the book shut, and nothing is lost by a step not run)
    if not ns.BOOK_AUTHOR then pcall(ns.BookMigrate, Cfg(), ns.db.inkMarks, Data()) end
    DropShipped()
    DeadminesInkToWanderer()
    pcall(ns.BookAnchor, Cfg(), Data(), Entry)
    book = CreateFrame("Frame", "WaymarkNotebook", UIParent)
    ns.AddonWindow(book, function() if Cfg().pos then SavePos() end end)
    book:SetSize(W, H)
    book:SetFrameStrata("HIGH")
    book:SetToplevel(true)
    book:SetMovable(true)
    book:SetClampedToScreen(true)
    local pos = Cfg().pos
    if pos then book:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else book:SetPoint("CENTER") end
    book:Hide()
    tinsert(UISpecialFrames, "WaymarkNotebook")
    book:HookScript("OnShow", function() if wbar then PlaceBar() end end)  -- (its book button: "close notebook")
    -- (put away: the quill stays in hand for the map while it's open, the bar going there)
    book:SetScript("OnHide", function()
        Sound("IG_SPELLBOOK_CLOSE")
        if wbar then PlaceBar() end  -- (its book button: "open notebook")
        if not writing then return end
        if ns.InkBarArea and ns.InkBarArea() then PlaceBar() else SetWriting(false) end
    end)

    cover = CreateFrame("Button", nil, book)
    cover:SetSize(COVER_W, COVER_H)
    cover:SetPoint("CENTER")
    DropShadow(cover, 0.55)
    local ct = cover:CreateTexture(nil, "ARTWORK")
    ct:SetAllPoints()
    ct:SetTexture(NOTES .. "Cover")
    ct:SetTexCoord(0, 0.75, 0, 1)
    Draggable(cover)
    -- (the closed book: a click opens it; a right-click puts it away)
    cover:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cover:SetScript("OnClick", function(_, button)
        if button == "RightButton" then book:Hide() else Open() end
    end)
    cover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("The found notes", 1, 0.93, 0.78)
        ns.Hints({ { "Click", "open it" }, { "Drag", "move it" }, { "Right-click", "put it away" } })
        GameTooltip:Show()
    end)
    cover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    open = CreateFrame("Frame", nil, book)
    open:SetAllPoints()
    open:EnableMouse(true)
    open:EnableMouseWheel(true)
    Draggable(open)
    open:SetScript("OnMouseWheel", function(_, d)
        if IsControlKeyDown() and SizeUnderCursor(d) then return end
        Turn(spread - d)
    end)
    DropShadow(open, 1)
    local board = open:CreateTexture(nil, "BACKGROUND")
    board:SetAllPoints()
    board:SetTexture(NOTES .. "Board")
    board:SetTexCoord(0, 1, 0, 672 / 1024)  -- (the book in the top 1024 x 672)

    left = NewPage(PAD_L, true)
    right = NewPage(PAD_L + PW, false)
    -- the spine: a click shuts the book onto its cover, a right-click puts it away (only a faint
    -- shadow on hover shows it's there; under the quill's catcher while drawing)
    local spine = CreateFrame("Button", nil, open)
    spine:SetPoint("TOP", open, "TOPLEFT", PAD_L + PW, -PAD_T)
    spine:SetSize(24, PH)
    spine:SetFrameLevel(right:GetFrameLevel() + 7)
    spine:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local shade = spine:CreateTexture(nil, "HIGHLIGHT")
    shade:SetAllPoints()
    shade:SetColorTexture(0.15, 0.08, 0.03, 0.14)
    spine:SetScript("OnClick", function(_, button)
        if button == "RightButton" then book:Hide() else Fold() end
    end)
    spine:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ns.Hints({ { "Click", "close the book" }, { "Right-click", "put it away" } })
        GameTooltip:Show()
    end)
    spine:SetScript("OnLeave", function() GameTooltip:Hide() end)
    prevCorner = Corner(left, true, -1)
    nextCorner = Corner(right, false, 1)
    if ns.InkHost then
        inkHost = ns.InkHost(open)
        inkHost.paper = true
        inkHost:SetFrameLevel(right:GetFrameLevel() + 4)
        right.map.ink = ns.InkHost(right.map)
        right.map.ink:SetFrameLevel(right.map:GetFrameLevel() + 3)
        -- (stairs drawn to lead somewhere: a click turns the page's map to that floor)
        right.map.ink.goFloor = function(_, floor)
            local m = right.map
            for k, f in ipairs(m.floors or {}) do
                if f.index == floor then
                    mapFloor[m.dg.id] = k
                    Sound("IG_ABILITY_PAGE_TURN")
                    Show(spread)
                    return
                end
            end
        end
    end
    WireMap(right.map, false)
    right.map:EnableMouseWheel(true)
    right.map:SetScript("OnMouseWheel", function(self, d) PageMapWheel(self, d) end)
    -- the page's map, big (while a drawing tool is in hand a click on the map draws)
    local big = CreateFrame("Button", nil, right.map)
    big:SetSize(26, 26)
    big:SetPoint("TOPRIGHT", right.map, "TOPRIGHT", 6, 6)
    big:SetNormalTexture("Interface\\Minimap\\UI-Minimap-ZoomInButton-Up")
    big:SetPushedTexture("Interface\\Minimap\\UI-Minimap-ZoomInButton-Down")
    big:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    big:SetScript("OnClick", function()
        local m = right.map
        if not m.dg then return end
        ZoomMap(m.dg, m.floors, m.k, m.views)
        Sound("IG_ABILITY_PAGE_TURN")
    end)
    big:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("The map, big")
        GameTooltip:Show()
    end)
    big:SetScript("OnLeave", function() GameTooltip:Hide() end)
    right.map.big = big
    ns.NotebookRedraw = function() if open:IsShown() then Redraw() end end  -- (dev layers turned on or off)
    if ns.DevRoutesButton then
        ns.DevRoutesButton(open, function() if open:IsShown() then Redraw() end end,
                           function() local dg = Entry(spread) return dg and dg.instance end)
    end
    BuildQuill()
    UpdateBar()
end

-- /bfi notes: the book, closed; again (or Escape) puts it away
function ns.ToggleNotebook()
    if not book then Create() end
    if book:IsShown() then
        book:Hide()
        return
    end
    -- (in a dungeon the book has a page on, or the zone its door is in: turned to it; elsewhere
    -- the page it was last open at)
    local here = ns.NotebookHere()
    if here and here ~= Cfg().spread then
        Cfg().spread = here
        beforeOf = nil
    end
    open:Hide()
    cover:Show()
    book:Show()
    Sound("IG_SPELLBOOK_OPEN")
end

-- the spread of the dungeon you're in, or of one whose door is in your zone (the first in the
-- book's order; the page open now if it's one of them); nil elsewhere
function ns.NotebookHere()
    local inside = IsInInstance() and select(8, GetInstanceInfo())
    local doors = {}
    if not inside and ns.EntrancesOnZone then
        for _, e in ipairs(ns.EntrancesOnZone() or {}) do doors[e.id] = true end
    end
    local first
    for i, dg in ipairs(Data()) do
        if ns.NotebookLocked(i) then  -- (not this release's)
        elseif dg.instance == inside then return i
        elseif doors[dg.instance] then
            if i == Cfg().spread then return i end
            first = first or i
        end
    end
    return first
end

-- the book open at a dungeon's page (instance mapID), e.g. from a stamp on its map
-- (floor: OpenMap's floor index, for the facing page's map; before: on its "before we go" page)
function ns.OpenNotebook(instance, floor, before)
    if not book then Create() end
    beforeOf = nil
    for i, dg in ipairs(Data()) do
        if dg.instance == instance and not ns.NotebookLocked(i) then
            Cfg().spread = i
            if before and dg.before then beforeOf = i end
            for k, f in ipairs(Floors(dg)) do
                if f.index == floor then mapFloor[dg.id] = k end
            end
        end
    end
    book:Show()
    Open()
end

-- /bfi notes shots (dev): the book open, a screenshot of every spread and every "before we go" page
-- in turn (Screenshots\ of the client), for looking the whole book over
function ns.NotebookShots()
    if not book then Create() end
    if writing then SetWriting(false) end
    book:Show()
    if not open:IsShown() then Open() end
    local steps = { { 0 } }
    for i, dg in ipairs(Data()) do
        local e = Entry(i)
        steps[#steps + 1] = { i }
        if e and e.before then steps[#steps + 1] = { i, true } end
    end
    local k = 0
    local function Next()
        k = k + 1
        local st = steps[k]
        if not st then
            print("|cffd4b47aWaymark|r: " .. #steps .. " page shots taken.")
            return
        end
        beforeOf = st[2] and st[1] or nil
        Show(st[1])
        C_Timer.After(0.7, function()
            Screenshot()
            C_Timer.After(0.9, Next)
        end)
    end
    print("|cffd4b47aWaymark|r: taking " .. #steps .. " page shots; leave the mouse still.")
    Next()
end

-- /bfi notes ship (dev): the book as the release has it, its unfinished pages locked; again: whole
function ns.NotebookShipView()
    if not book then Create() end
    Cfg().shipView = not Cfg().shipView or nil
    print("|cffd4b47aWaymark|r: the book " .. (Cfg().shipView and "as it ships, unfinished pages locked." or "whole again."))
    if open:IsShown() then Open() end
end

-- /bfi notes me (dev): writing as a player would, your own layer and the book kinds; again: the wanderer
function ns.NotebookAsPlayer()
    if not book then Create() end
    Cfg().asPlayer = not Cfg().asPlayer or nil
    who = Cfg().asPlayer and "you" or "wanderer"
    inkIdx = who == "wanderer" and 1 or 3
    print("|cffd4b47aWaymark|r: the book as " .. (Cfg().asPlayer and "a player." or "the wanderer."))
    ns.NotebookRefresh()
end

-- the book drawn again, here and on the dungeon map (a reset, the kind of book changed)
function ns.NotebookRefresh()
    if not book then return end
    wipe(undo)
    if open:IsShown() then Show(spread) end
    if UpdateBar then UpdateBar() end
    NotesChanged()
    if ns.UpdateInk then ns.UpdateInk() end
end

-- the kind of book, chosen on the bookplate or the map's book button
function ns.BookSetKind(kind)
    Cfg().kind = kind
    if ns.RefreshControls then ns.RefreshControls() end
    if who == "wanderer" then print("|cffd4b47aWaymark|r: the wanderer always has the whole book (/bfi notes me to see it).") end
    ns.NotebookRefresh()
end

local function KindItems()
    local out, kind = {}, Cfg().kind or "story"
    for _, k in ipairs(ns.BOOK_KINDS) do
        out[#out + 1] = { k[2], function() ns.BookSetKind(k[1]) end, on = k[1] == kind }
    end
    return out
end
function ns.BookKindMenu() Menu(KindItems()) end

-- the book button on the map: a right-click
function ns.BookMenu()
    Menu({ { "open the book", ns.ToggleNotebook }, { "what's in the book", nil, sub = KindItems() },
           { "the book's settings", function() ns.ShowOption("notebook", "kind") end } })
end

-- a right-click on a page with the quill in hand
function ns.BookPageMenu()
    local items = {}
    if ns.QuillCanUndo and ns.QuillCanUndo() then items[1] = { "undo", ns.QuillUndoLast } end
    items[#items + 1] = { "reset this page", function() ns.BookReset(false) end }
    local dg = Data()[spread]
    if ns.BookHasAside(Cfg(), dg and dg.id or "flyleaf") then
        items[#items + 1] = { "bring back what was reset here", function() ns.BookBack(false) end }
    end
    items[#items + 1] = { "put the quill down", function() ns.SetQuill(false) end }
    Menu(items)
end

-- reset: this page, or the whole book, set aside (BookOwn.lua); ns.BookBack brings it back
function ns.BookReset(whole)
    if not book then Create() end
    local list = {}
    if whole then
        for _, dg in ipairs(Data()) do list[#list + 1] = dg end
    elseif Data()[spread] then
        list[1] = Data()[spread]
    end
    local done = ns.BookSetAside(Cfg(), ns.db.inkMarks, list, whole)
    print("|cffd4b47aWaymark|r: " .. (done and "set aside. \"Bring back\" returns it." or "nothing of yours there to reset."))
    ns.NotebookRefresh()
end

function ns.BookBack(whole)
    if not book then Create() end
    local id
    if not whole then
        local dg = Data()[spread]
        id = dg and dg.id or "flyleaf"
    end
    local done = ns.BookBringBack(Cfg(), ns.db.inkMarks, Data(), id)
    print("|cffd4b47aWaymark|r: " .. (done and "brought back." or "nothing set aside."))
    ns.NotebookRefresh()
end

-- /bfi notes write: the book open, the quill in hand
function ns.NotebookWrite()
    if not book then Create() end
    book:Show()
    if not open:IsShown() then Open() end
    SetWriting(true)
end

-- On the dungeon map itself (Dungeon.lua's view) -------------------------------------
-- The notes' numbers on their floor (rings small enough to circle a boss's icon;
-- hover: the note), and in the corner the wanderer's stamp: a click opens the
-- book on that dungeon's page. On a layer on the map's canvas, in the picture's
-- own pixels, so they grow and shrink with the map as it zooms; looked at a few
-- times a second.
local function DungeonMapNotes()
    local canvas, key = ns.DungeonInkSurface()
    local inst, floor = (key or ""):match("^d(%d+):(%d+)$")
    local idx
    inst, floor = tonumber(inst), tonumber(floor)
    for i, dg in ipairs(Data()) do
        if inst and dg.instance == inst then idx = i end
    end
    if not idx then
        if dm then dm.layer:Hide() dm.stamp:Hide() dm.sig = nil end
        return
    end
    if not dm then
        dm = {}
        dm.layer = CreateFrame("Frame", nil, canvas)
        dm.layer.pools = { text = { n = 0 }, tex = { n = 0 }, mapText = { n = 0 }, mapTex = { n = 0 }, hit = { n = 0 } }
        dm.stamp = CreateFrame("Button", nil, ns.dungeonOverlay)
        dm.stamp:SetSize(40, 40)
        dm.stamp:SetPoint("BOTTOMRIGHT", -6, 6)
        dm.stamp.bleed = dm.stamp:CreateTexture(nil, "ARTWORK", nil, 1)
        dm.stamp.tex = dm.stamp:CreateTexture(nil, "ARTWORK", nil, 2)
        dm.stamp.tex:SetPoint("CENTER")
        -- (the book open: a click shuts it again)
        dm.stamp:SetScript("OnClick", function(self)
            if book and book:IsShown() and open:IsShown() then
                book:Hide()
                Sound("IG_SPELLBOOK_CLOSE")
            else
                ns.OpenNotebook(self.inst, self.floor)
            end
        end)
        dm.stamp:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(self.title or "The found notes")
            ns.Hints({ { "Click", (book and book:IsShown() and open:IsShown()) and "close the book" or "the found notes on this dungeon" } })
            GameTooltip:Show()
        end)
        dm.stamp:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- the quill, as the book's, beside it (and gone with it)
        dm.quill = ns.QuillButton(dm.stamp, 34)
        dm.quill:SetPoint("RIGHT", dm.stamp, "LEFT", -6, 0)
    end
    local layer = dm.layer
    if layer:GetParent() ~= canvas then layer:SetParent(canvas) end
    local dg = Entry(idx)
    -- (the book as who's writing has it: the wanderer's in the dev copy, as the
    -- book shows it, so the rings sit in the same place with the quill or without)
    KeptWho()
    local as = who
    local sig = key .. ":" .. notesVersion .. ":" .. as
    if sig ~= dm.sig then
        dm.sig = sig
        Reset(layer)
        layer:ClearAllPoints()
        layer:SetPoint("TOPLEFT", canvas, "TOPLEFT")
        layer:SetSize(1002, 668)
        layer:SetFrameLevel(canvas:GetFrameLevel() + 4)
        layer.dg, layer.floor = dg, floor  -- (for MapPoint: a moved spot snaps onto a boss)
        local saved = who
        who = as
        local views = NoteViews(dg)
        who = saved
        for _, v in ipairs(views) do v.dgi = idx end
        for _, sp in ipairs(NoteSpots(layer, layer, floor, 1002, RING_PX, views)) do
            local b = Take(layer, "hit", function()
                local b = CreateFrame("Frame", nil, layer)
                b.bfiTag = "notes ring"
                b:SetSize(RING_PX * 1.2, RING_PX * 1.2)
                -- (its presses handed on: the quill's catcher, else the dungeon map, Dungeon.lua; a
                -- hover-only frame kept the clicks on the client, so only the catcher's own ever worked)
                b:EnableMouse(true)
                b:SetScript("OnMouseDown", function(_, button)
                    if not ns.InkCatcherPress(true, button) and ns.DungeonMapDown then ns.DungeonMapDown(button) end
                end)
                b:SetScript("OnMouseUp", function(_, button)
                    if not ns.InkCatcherPress(false, button) and ns.DungeonMapUp then ns.DungeonMapUp(button) end
                end)
                b:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(self.n .. ".  " .. ((self.text or ""):gsub("~", "")), 1, 0.93, 0.78, true)
                    ns.Hints({ { "Click", "the found notes" }, { ns.QuillOut() and "Drag" or "Ctrl-drag", "move it (its number: round it)" },
                               { "Right-click", "its menu" } })
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                return b
            end)
            b:SetFrameLevel(layer:GetFrameLevel() + 2)
            b:SetPoint("CENTER", layer, "TOPLEFT", sp.x, sp.y)
            b.n, b.text = sp.n, sp.view.text
        end
        -- (the closed notebook: this place is in the book; a click opens it there)
        local s = dm.stamp
        s.tex:SetTexture(NOTES .. "Cover")
        s.tex:SetTexCoord(0, 0.75, 0, 1)
        s.tex:SetSize(27, 36)
        s.tex:SetRotation(-0.12)
        s.tex:SetVertexColor(1, 1, 1)
        s.tex:SetAlpha(1)
        s.bleed:SetTexture(NOTES .. "Cover")
        s.bleed:SetTexCoord(0, 0.75, 0, 1)
        s.bleed:ClearAllPoints()
        s.bleed:SetPoint("CENTER", s.tex, "CENTER", 2, -2)
        s.bleed:SetSize(27, 36)
        s.bleed:SetRotation(-0.12)
        s.bleed:SetVertexColor(0, 0, 0)
        s.bleed:SetAlpha(0.4)
        s.bleed:Show()
        s.inst, s.floor, s.title = inst, floor, dg.title
        s:SetFrameLevel(ns.dungeonOverlay:GetFrameLevel() + 20)
    end
    layer:Show()
    -- (over the quill's catcher, which lies 4 above the dungeon map: else, the quill out, the stamp and
    -- the feather couldn't be clicked, and the quill couldn't be put away from here)
    dm.stamp:SetFrameLevel(ns.dungeonOverlay:GetFrameLevel() + 8)
    if dm.quill then dm.quill:SetFrameLevel(dm.stamp:GetFrameLevel() + 1) end
    dm.stamp:Show()
end

C_Timer.NewTicker(0.3, ns.Timed("Notebook tick", function()
    if ns.db and ns.dungeonOverlay and ns.DungeonInkSurface then DungeonMapNotes() end
end))

NotesChanged = function()
    notesVersion = notesVersion + 1
    if ns.db and ns.dungeonOverlay and ns.DungeonInkSurface then DungeonMapNotes() end
end

-- what the found notes say at a spot on a dungeon floor (the boss list asks at a
-- boss's spot): the note's number and words, the book as you have it
function ns.FoundNoteAt(instance, floor, x, y)
    for i, dg in ipairs(Data()) do
        if dg.instance == instance then
            local saved = who
            who = "you"
            local views = NoteViews(Entry(i))
            who = saved
            for n, v in ipairs(views) do
                if v.floor == floor and v.x and v.mark ~= "off"
                    and math.abs(v.x - x) < 0.015 and math.abs(v.y - y) < 0.015 then  -- (a ring dropped by hand near the skull counts)
                    return n, v.text
                end
            end
        end
    end
end

-- The quill, for Ink.lua (the Battlefield map) -------------------------------------
function ns.Quill() return writing, who, tool, inkIdx end
-- the quill taken up or put down from outside the book (the dungeon map's Quill button)
function ns.QuillToggle()
    if not book then Create() end
    SetWriting(not writing)
end
-- the hand new written words take: yours, the wanderer's, or the whispers' (note tool clicked again)
function ns.QuillHand()
    if who ~= "wanderer" then return "reenie" end
    return whisperHand and "apple" or "nothing"
end
function ns.SetQuill(on) SetWriting(on) end
function ns.QuillMenu(items) Menu(items) end
function ns.QuillUndo(u) undo[#undo + 1] = u end
function ns.QuillPlace() if writing then PlaceBar() end end
function ns.NotebookOpen() return book and book:IsShown() and open:IsShown() or false end

-- as the wanderer on a found-notes dungeon's floor ("d<instance>:<floor>"): the book's
-- marks on its map (make: on the copy to change); nil anywhere else
function ns.QuillWanderer(key, make)
    local inst, floor = (key or ""):match("^d(%d+):(%d+)$")
    if not inst then return end
    inst, floor = tonumber(inst), tonumber(floor)
    for i, dg in ipairs(Data()) do
        if dg.instance == inst then
            if make then
                local c = AuthorCopy(i)
                c.mapMarks = c.mapMarks or {}
                c.mapMarks[floor] = c.mapMarks[floor] or {}
                return c.mapMarks[floor]
            end
            local e = Entry(i)
            return e.mapMarks and e.mapMarks[floor] or {}
        end
    end
end

-- the notes' numbers on the dungeon map, with the quill: dragged to move (snapping
-- onto a boss), rubbed out (off the map), right-click: the note's menu
local spotGrab
function ns.QuillSpotDown(erase, any)
    local layer = dm and dm.layer
    if not ((writing or any) and layer and layer:IsVisible()) then return false end
    KeptWho()
    local sp, onNum = SpotUnder(layer)
    if not sp then return false end
    if erase then
        NoteSet(sp.view, "mark", "off")
    else
        local sx, sy = GetCursorPosition()
        spotGrab = { sp = sp, sx = sx, sy = sy, num = onNum }
    end
    return true
end

-- Ctrl + wheel on the Battlefield dungeon map: a note's ring under the cursor (true when there was one)
function ns.QuillSpotSize(d)
    local layer = dm and dm.layer
    if not (writing and layer and layer:IsVisible()) then return false end
    return SpotSize(SpotUnder(layer), d)
end

function ns.QuillSpotUpdate()
    local g = spotGrab
    if not g then return end
    local sx, sy = GetCursorPosition()
    if not g.moved then
        if math.sqrt((sx - g.sx) ^ 2 + (sy - g.sy) ^ 2) / UIParent:GetEffectiveScale() < 4 then return end
        g.moved = true
    end
    local layer = dm.layer
    if g.num then g.na = SpotTurnNumber(g.sp, layer) return end
    local s = layer:GetEffectiveScale()
    g.sp.Put(math.max(0, math.min(layer:GetWidth(), sx / s - layer:GetLeft())),
             math.max(-layer:GetHeight(), math.min(0, sy / s - layer:GetTop())))
end

-- (true when it was a move)
function ns.QuillSpotUp()
    local g = spotGrab
    spotGrab = nil
    if not (g and g.moved) then return false end
    if g.num then
        if g.na then NoteSet(g.sp.view, "na", g.na) end
        return true
    end
    local x, y = MapPoint(dm.layer)
    x, y = math.max(0, math.min(1, x)), math.max(0, math.min(1, y))
    NoteChange(g.sp.view, function(n) n.floor, n.x, n.y = dm.layer.floor, x, y end)
    return true
end

-- (any: the quill away too; extra: rows after the note's, the boss under it; spot: the
-- ring, taken when an earlier menu opened, ns.FoundSpotGrab: by now the cursor is on that menu)
function ns.QuillSpotMenu(any, extra, spot)
    local layer = dm and dm.layer
    if not ((writing or any) and layer and layer:IsVisible()) then return false end
    local sp = spot or SpotUnder(layer)
    if not sp then return false end
    KeptWho()
    local rows = { { "the found notes", function() ns.OpenNotebook(layer.dg.instance, layer.floor) end } }
    for _, it in ipairs(extra or {}) do rows[#rows + 1] = it end
    NoteMenu(sp.view, rows, true)
    return true
end

-- a note's ring under the cursor on the dungeon map: its number, or nil
function ns.FoundSpotUnder()
    local layer = dm and dm.layer
    if not (layer and layer:IsVisible()) then return end
    local sp = SpotUnder(layer)
    return sp and sp.n
end

-- the note's ring under the cursor itself, to open its menu later (ns.QuillSpotMenu)
function ns.FoundSpotGrab()
    local layer = dm and dm.layer
    if not (layer and layer:IsVisible()) then return end
    return (SpotUnder(layer))
end

-- a click on a note's ring on the dungeon map: the book, on that dungeon and floor
function ns.FoundSpotOpen()
    local layer = dm and dm.layer
    if not (layer and layer:IsVisible() and SpotUnder(layer) and layer.dg) then return false end
    ns.OpenNotebook(layer.dg.instance, layer.floor)
    return true
end
