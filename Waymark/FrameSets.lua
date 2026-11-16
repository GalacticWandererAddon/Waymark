local _, ns = ...

-- The cleaner frame sets (out of the Lab for 1.3, 2026-11-14; mock-up mockups\frame-suggestions.html, art tools\frame_suggestions.py).
-- A set's art in Media\Frames (the cleared sets) or Media\Lab (the rest): Set<Name>Corners, EdgeH, EdgeV (square frames), Ring (round minimap), Tab
-- (zone name). The edges repeat, so stitches and ticks keep their size at any length.
--   out    units the frame reaches past what it holds, at scale 1
--   tab    the zone name's colour     metal  buttons' tint     fill  the ground behind panels
--   roundOnly  a ring and tab, no square frame
--   vine   a metal rod with a thread growing along it from each corner, the two meeting and twining in
--          the middle of each side: Vine<H|V> repeats from the corner, Mid<H|V> is the meeting, the far
--          half is the near one mirrored. Sides too short for it wear the plain rod (Edge<H|V>).

local UNIT = 32           -- units a corner, at scale 1
local TILE = 64           -- units an edge repeat
local PANEL = 0.55        -- panels wear the art smaller
local MID = 64            -- units of a vine's meeting piece

local SETS = {
    bronze   = { name = "Forever bronze", out = 5, tab = { 1, 0.82, 0 }, metal = { 0.73, 0.54, 0.28 }, fill = { 0.047, 0.04, 0.03, 0.82 } },
    leather  = { name = "Book cover", out = 7, tab = { 0.93, 0.85, 0.71 }, metal = { 0.69, 0.54, 0.33 }, fill = { 0.047, 0.04, 0.03, 0.82 } },
    engraver = { name = "Engraver's corners", size = 1.6, out = 2.2, tab = { 1, 0.82, 0 }, metal = { 0.56, 0.39, 0.19 }, fill = { 0.047, 0.04, 0.03, 0.82 }, hand = true },
    silver   = { name = "Moonlit silver", vine = true, out = 3.6, tab = { 0.93, 0.95, 1 }, metal = { 0.78, 0.82, 0.9 }, fill = { 0.043, 0.047, 0.07, 0.84 } },
    gold     = { name = "Sun gold", vine = true, out = 3.6, tab = { 1, 0.85, 0.47 }, metal = { 0.84, 0.63, 0.24 }, fill = { 0.047, 0.04, 0.03, 0.82 } },
    survey   = { name = "Survey line", out = 10.7, tab = { 0.91, 0.85, 0.69 }, metal = { 0.85, 0.74, 0.52 }, fill = { 0.047, 0.04, 0.03, 0.82 }, roundOnly = true },
}
-- (the Engraver's first cut was removed on 2026-11-15 at the user's word)
local FRAMES = { "bronze", "leather", "engraver", "silver", "gold" }
-- Cleared for 1.3 by the user (2026-11-14): the Engraver's corners (the one they use), Moonlit silver and Sun gold.
-- The other sets are the user's to check off: offered, drawn and found on disk only where the Lab is
-- (ns.LabPage, Lab\Lab.lua; their art stays in Media\Lab, which no build takes).
local CLEARED = { engraver = true, silver = true, gold = true }
function ns.FrameSetOpen(key) return SETS[key] ~= nil and (CLEARED[key] or ns.LabPage ~= nil) end

local GRIP = 1            -- units a frame's inner edge reaches onto what it holds: tight, no gap

-- how far a frame's points go out past what it holds, at a scale
function ns.LabSetOut(key, scale) return math.max(0, (SETS[key].out - GRIP) * (scale or 1)) end

-- a map border's scale: a set's own size, smaller only while docked on the minimap (not the big map)
local DOCKED = 0.6
function ns.LabSetScale(key)
    local s = SETS[key].size or 1
    local docked = ns.Docked and ns.Docked() and not (ns.DockBigMovable and ns.DockBigMovable())
    return docked and s * DOCKED or s
end

ns.LAB_PANEL = PANEL

function ns.LabSet(key) return SETS[key] end

function ns.LabSetArt(key, part)
    return ns.MEDIA .. (CLEARED[key] and "Frames\\" or "Lab\\") .. "Set" .. key:gsub("^%l", string.upper) .. part
end

-- { key, name } rows for a settings choice; every set if ring, else those with a square frame
function ns.LabSetChoices(rows, ring)
    for _, key in ipairs(FRAMES) do
        if ns.FrameSetOpen(key) then rows[#rows + 1] = { key, SETS[key].name } end
    end
    if ring and ns.LabPage then rows[#rows + 1] = { "survey", SETS.survey.name .. " (round only)" } end
    return rows
end

function ns.LabSetKeys() return FRAMES end

-- how far a set's frame goes out, a texture's ring width to the map's
function ns.LabSetRing(key) return 300 / (300 - 2 * SETS[key].out) end

local function Layout(self)
    local key = self.key
    if not key then return end
    local w, h = self:GetWidth(), self:GetHeight()
    local c = math.max(1, math.min(UNIT * self.scale, w / 2, h / 2))
    -- whole repeats of a quarter tile: lace and stitches then meet the far corner as they left the near one
    local tile = TILE * c / UNIT
    local across = math.floor(math.max(0, w - 2 * c) / tile * 4 + 0.5) / 4
    local down = math.floor(math.max(0, h - 2 * c) / tile * 4 + 0.5) / 4
    local t = self.pieces
    for i = 1, 4 do t[i]:SetSize(c, c) end
    t[5]:SetHeight(c)
    t[6]:SetHeight(c)
    t[7]:SetWidth(c)
    t[8]:SetWidth(c)
    t[5]:SetTexCoord(0, across, 0, 0.5)
    t[6]:SetTexCoord(0, across, 0.5, 1)
    t[7]:SetTexCoord(0, 0.5, 0, down)
    t[8]:SetTexCoord(0.5, 1, 0, down)
    local vine = SETS[key].vine
    local mid = MID * c / UNIT
    for side = 1, 4 do
        local a, m, b = t[6 + side * 3], t[7 + side * 3], t[8 + side * 3]
        local horiz = side <= 2
        local len = horiz and (w - 2 * c) or (h - 2 * c)
        local half = (len - mid) / 2
        local on = vine and half >= tile * 0.35
        t[4 + side]:SetShown(not on)
        a:SetShown(on and true or false)
        m:SetShown(on and true or false)
        b:SetShown(on and true or false)
        if on then
            local n = math.max(1, math.floor(half / tile + 0.5))
            local lo, hi = (side % 2 == 1) and 0 or 0.5, (side % 2 == 1) and 0.5 or 1
            if horiz then
                a:SetSize(half, c)
                m:SetSize(mid, c)
                b:SetHeight(c)
                a:SetTexCoord(0, n, lo, hi)
                m:SetTexCoord(0, 1, lo, hi)
                b:SetTexCoord(n, 0, lo, hi)
            else
                a:SetSize(c, half)
                m:SetSize(c, mid)
                b:SetWidth(c)
                a:SetTexCoord(lo, hi, 0, n)
                m:SetTexCoord(lo, hi, 0, 1)
                b:SetTexCoord(lo, hi, n, 0)
            end
        end
    end
end

-- the vine's pieces: near half (from the first corner), the meeting, the far half (mirrored)
local VINE_POINTS = {
    { "TOPLEFT", 1, "TOPRIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMRIGHT", 2, "BOTTOMLEFT" },
    { "BOTTOMLEFT", 3, "BOTTOMRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "TOPRIGHT", 4, "TOPLEFT" },
    { "TOPLEFT", 1, "BOTTOMLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", 3, "TOPRIGHT" },
    { "TOPRIGHT", 2, "BOTTOMRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMLEFT", 4, "TOPLEFT" },
}

-- a frame of a set's art: f:SetLook(key, scale), points set by the caller
function ns.LabFrame(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:EnableMouse(false)
    local t = {}
    for i = 1, 20 do t[i] = f:CreateTexture(nil, "OVERLAY") end
    f.pieces = t
    t[1]:SetPoint("TOPLEFT")
    t[2]:SetPoint("TOPRIGHT")
    t[3]:SetPoint("BOTTOMLEFT")
    t[4]:SetPoint("BOTTOMRIGHT")
    t[1]:SetTexCoord(0, 0.5, 0, 0.5)
    t[2]:SetTexCoord(0.5, 1, 0, 0.5)
    t[3]:SetTexCoord(0, 0.5, 0.5, 1)
    t[4]:SetTexCoord(0.5, 1, 0.5, 1)
    t[5]:SetPoint("TOPLEFT", t[1], "TOPRIGHT")
    t[5]:SetPoint("TOPRIGHT", t[2], "TOPLEFT")
    t[6]:SetPoint("BOTTOMLEFT", t[3], "BOTTOMRIGHT")
    t[6]:SetPoint("BOTTOMRIGHT", t[4], "BOTTOMLEFT")
    t[7]:SetPoint("TOPLEFT", t[1], "BOTTOMLEFT")
    t[7]:SetPoint("BOTTOMLEFT", t[3], "TOPLEFT")
    t[8]:SetPoint("TOPRIGHT", t[2], "BOTTOMRIGHT")
    t[8]:SetPoint("BOTTOMRIGHT", t[4], "TOPRIGHT")
    for side, p in ipairs(VINE_POINTS) do
        local a, m, b = t[6 + side * 3], t[7 + side * 3], t[8 + side * 3]
        a:SetPoint(p[1], t[p[2]], p[3])
        m:SetPoint(p[4], a, p[5])
        b:SetPoint(p[4], m, p[5])
        b:SetPoint(p[6], t[p[7]], p[8])
        a:Hide()
        m:Hide()
        b:Hide()
    end
    f:SetScript("OnSizeChanged", Layout)
    function f:SetLook(key, scale)
        self.scale = scale or 1
        if key ~= self.key then
            self.key = key
            for i = 1, 4 do t[i]:SetTexture(ns.LabSetArt(key, "Corners")) end
            t[5]:SetTexture(ns.LabSetArt(key, "EdgeH"), "REPEAT", "REPEAT")
            t[6]:SetTexture(ns.LabSetArt(key, "EdgeH"), "REPEAT", "REPEAT")
            t[7]:SetTexture(ns.LabSetArt(key, "EdgeV"), "REPEAT", "REPEAT")
            t[8]:SetTexture(ns.LabSetArt(key, "EdgeV"), "REPEAT", "REPEAT")
            if SETS[key].vine then
                for side = 1, 4 do
                    local hv = side <= 2 and "H" or "V"
                    t[6 + side * 3]:SetTexture(ns.LabSetArt(key, "Vine" .. hv), "REPEAT", "REPEAT")
                    t[7 + side * 3]:SetTexture(ns.LabSetArt(key, "Mid" .. hv))
                    t[8 + side * 3]:SetTexture(ns.LabSetArt(key, "Vine" .. hv), "REPEAT", "REPEAT")
                end
            end
        end
        Layout(self)
    end
    return f
end
