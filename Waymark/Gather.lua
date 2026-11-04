local _, ns = ...

-- Gathering nodes on the map and minimap (mock-up mockups\gathering-nodes.html). Spots come from
-- GatherMate2's database when it's installed and chosen, always the player's choice, else from the
-- Waymark_Nodes data addon (GPL, load on demand, tools\node_spots.py); on either, what you gather
-- yourself (WaymarkNodesDB.spots[uiMapID] = { { x, y, name, kind, times, last }, ... }).
-- A spot can hold several node types by turns. Settings ns.db.gather:
--   source: "gathermate" or "own" (without GatherMate2: own, whatever this says);
--   follow: with GatherMate2, a type also needs GatherMate to show it;
--   look: "ink" (a small mark per spot: each herb's own plant, a lump of ore in its metal's colour,
--   a chest, footlocker or clam, a fish; ns.NodeMarkCells, tools/node_marks.py) or "gathermate"
--   (GatherMate2's own icons, on its spots)
--   types[key]: the kinds shown; off[name]: node types switched off;
--   canGather: only what your skill allows; tint: by skill-up chance; fadeUnseen; minimap;
--   ringYards: how near a node you're tracking turns into a ring on the minimap
-- Marks are textures on one frame that never takes the mouse: a node frame each cost too much in
-- the busiest zones. Hovering is a grid lookup that puts a single pin under the cursor, so the
-- tooltip, menu and Alt-click work as on any pin. Redraws only when the drawn content changes.

local TEMPLATE = "BFIGatherPinTemplate"
local SHEET = ns.MEDIA .. "NodeMarks"
local MARK = 10          -- a mark's size at Size 1 (pin units, as ApplyCurrentScale)
local PER_FRAME = 400    -- marks laid a frame
local SNAP = 15          -- yards: a sighting this near a known spot is that spot
local SAME = 8           -- yards: a sighting this near your own earlier one is the same
local HOVER_PX = 7       -- how near the cursor a mark counts
local CELLS = 48         -- the hover grid over the map
local RING_MAX = 40      -- marks on the minimap at most
local RING_EDGE = 10     -- yards past gather.ringYards over which a mark turns into a ring
local RING_PX = 12       -- the ring, whatever the Size slider says: a blip fits inside

ns.GATHER_TYPES = {
    { key = "Herb Gathering", label = "Herbs",    kind = "h" },
    { key = "Mining",         label = "Mining",   kind = "m" },
    { key = "Fishing",        label = "Fishing",  kind = "f" },
    { key = "Treasure",       label = "Treasure", kind = "t" },
}
local KEY_OF = {}
for _, t in ipairs(ns.GATHER_TYPES) do KEY_OF[t.kind] = t.key end

local GLYPH = { h = 0, m = 1, t = 2, f = 3, ring = 5 }
local COLOR = { h = { 0.36, 0.86, 0.36 }, m = { 0.93, 0.58, 0.30 }, t = { 1, 0.86, 0.25 }, f = { 0.56, 0.72, 0.80 } }
-- ore by its metal, so a vein says what it is at a glance ("Ooze Covered ..." the same)
local METAL = {
    Copper = { 0.90, 0.50, 0.22 }, Tin = { 0.66, 0.72, 0.70 }, Silver = { 0.86, 0.90, 1 },
    Iron = { 0.78, 0.40, 0.34 }, Gold = { 1, 0.82, 0.16 }, Mithril = { 0.30, 0.85, 0.80 },
    Truesilver = { 1, 1, 1 }, Thorium = { 0.45, 0.92, 0.50 }, Dark = { 0.85, 0.18, 0.18 },
    Incendicite = { 1, 0.36, 0.12 }, Lesser = { 0.85, 0.20, 0.40 }, Indurium = { 0.66, 0.58, 0.90 },
}
local PROFESSION = { h = "Herbalism", m = "Mining" }
local SKILL_LINE = { [182] = "h", [186] = "m" }

local function Cfg() return ns.db.gather end
-- the sheet's 16 x 4 cells
local function Cell(tex, i)
    local col, row = i % 16, math.floor(i / 16)
    tex:SetTexCoord(col / 16, (col + 1) / 16, row / 4, (row + 1) / 4)
end
local function Glyph(tex, name) Cell(tex, GLYPH[name]) end

-- Data ------------------------------------------------------------------------

local data           -- WaymarkNodesData, false when it can't be had
local typeOf = {}    -- node name -> { name, kind, skill }
local spotsOf = {}   -- uiMapID -> { { x, y, names, kind, skill, seen, last }, ... }
local version = 0    -- up by one with every change to the spots

local function Data()
    if data ~= nil then return data end
    if not WaymarkNodesData then
        local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
        if load then pcall(load, "Waymark_Nodes") end
    end
    data = WaymarkNodesData or false
    if data then
        for _, t in ipairs(data.types) do typeOf[t[1]] = t end
    end
    return data
end

-- the kind of a node name, nil for what we've never heard of
function ns.NodeKind(name)
    Data()
    return typeOf[name] and typeOf[name][2]
end

local function GM()
    local gm = _G.GatherMate2
    return gm and gm.GetNodesForZone and gm.gmdbs and gm
end

local function UseGM() return Cfg().source ~= "own" and GM() end

local function Own(mapID)
    local db = WaymarkNodesDB
    return db and db.spots and db.spots[mapID]
end

local function Unpack(mapID)
    local out = {}
    local d = Data()
    local z = d and d.zones[mapID]
    if z then
        local digit = {}
        local abc = d.alphabet
        for i = 1, #abc do digit[abc:byte(i)] = i - 1 end
        local base, steps, s = #abc, d.steps, z.spots
        local fix = not ns.FOREVER and d.eraFix[mapID]   -- (stand-in clients: the map before Forever redrew it)
        for i = 1, #s, 6 do
            local a, b, c, e, f, g = s:byte(i, i + 5)
            local x = (digit[a] * base + digit[b]) / steps
            local y = (digit[c] * base + digit[e]) / steps
            local set = z.sets[digit[f] * base + digit[g]]
            local first = d.types[set[1]]
            local skill, names = nil, {}
            for j, id in ipairs(set) do
                local t = d.types[id]
                names[j] = t[1]
                if not skill or t[3] < skill then skill = t[3] end
            end
            if fix then x, y = (x - fix[2]) / fix[1], (y - fix[4]) / fix[3] end
            out[#out + 1] = { x = x, y = y, names = names, kind = first[2], skill = skill, seen = 0 }
        end
    end
    return out
end

-- a zone's spots from GatherMate2, through its own node filters
local function FromGatherMate(mapID)
    local out, gm = {}, GM()
    Data()   -- (the skill a node needs, where our list knows it)
    local zone = gm.phasing and gm.phasing[mapID] or mapID
    for _, g in ipairs(ns.GATHER_TYPES) do
        if gm.gmdbs[g.key] then
            local icons = gm.nodeTextures and gm.nodeTextures[g.key]
            -- (run the iterator to the end: GatherMate recycles its state when it finishes)
            for coord, id in gm:GetNodesForZone(zone, g.key) do
                id = gm.nodeIDReplacementMap and gm.nodeIDReplacementMap[id] or id
                local name = gm:GetNameForNode(g.key, id)
                if name then
                    local x, y = gm:DecodeLoc(coord)
                    local t = typeOf[name]
                    out[#out + 1] = { x = x, y = y, names = { name }, kind = g.kind, skill = t and t[3] or 0,
                                      skillUnknown = not t, seen = 0, icon = icons and icons[id] }
                end
            end
        end
    end
    return out
end

-- the spot nearest a point, of that kind, within `yards`
local function Nearest(list, mapID, x, y, kind, yards)
    local w, h = ns.MapYards(mapID)
    if not w then w, h = 5000, 3400 end
    local best, bd = nil, yards * yards
    for _, s in ipairs(list) do
        if s.kind == kind then
            local dx, dy = (s.x - x) * w, (s.y - y) * h
            local d = dx * dx + dy * dy
            if d < bd then best, bd = s, d end
        end
    end
    return best
end

-- a sighting on a zone's list: on the spot it belongs to, or a spot of its own
local function Apply(list, mapID, e)
    local s = Nearest(list, mapID, e[1], e[2], e[4], SNAP)
    if not s then
        local t = typeOf[e[3]]
        s = { x = e[1], y = e[2], names = { e[3] }, kind = e[4], skill = t and t[3] or 0, seen = 0, own = true }
        list[#list + 1] = s
    else
        local found
        for _, n in ipairs(s.names) do found = found or n == e[3] end
        if not found then s.names[#s.names + 1] = e[3] end
    end
    s.seen = s.seen + (e[5] or 1)
    if not s.last or (e[6] or 0) > s.last then s.last = e[6] end
end

-- GatherMate2's nodes changed: read them afresh, once however many changed
local gmWatched, gmPending
local function GMChanged()
    if gmPending then return end
    gmPending = true
    C_Timer.After(0.5, function()
        gmPending = false
        if not UseGM() then return end
        wipe(spotsOf)
        version = version + 1
        if ns.RedrawGather then ns.RedrawGather() end
    end)
end

local function WatchGM()
    gmWatched = true
    local events = LibStub and LibStub("AceEvent-3.0", true)
    if not events then return end
    local listener = {}
    events:Embed(listener)
    for _, m in ipairs({ "GatherMate2NodeAdded", "GatherMate2NodeDeleted", "GatherMate2DataImport", "GatherMate2Cleanup",
                         "GatherMate2ConfigChanged" }) do
        listener:RegisterMessage(m, GMChanged)
    end
end

local spotsFromGM
local function Spots(mapID)
    local gm = UseGM() and true or false
    if gm ~= spotsFromGM then
        wipe(spotsOf)
        spotsFromGM = gm
    end
    local list = spotsOf[mapID]
    if not list then
        if gm and not gmWatched then WatchGM() end
        list = gm and FromGatherMate(mapID) or Unpack(mapID)
        for _, e in ipairs(Own(mapID) or {}) do Apply(list, mapID, e) end
        spotsOf[mapID] = list
    end
    return list
end

-- Your skills -------------------------------------------------------------------

local skills

local function ReadSkills()
    skills = {}
    if GetProfessions and GetProfessionInfo then
        local first, second = GetProfessions()
        for _, i in pairs({ first, second }) do
            local name, _, rank, _, _, _, line = GetProfessionInfo(i)
            local k = SKILL_LINE[line]
            if k then skills[k] = rank end
            for kind, n in pairs(PROFESSION) do
                if name == n then skills[kind] = rank end
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, header, _, rank = GetSkillLineInfo(i)
            if not header then
                for kind, n in pairs(PROFESSION) do
                    if name == n then skills[kind] = rank end
                end
            end
        end
    end
end

local function Skill(kind)
    if not skills then pcall(ReadSkills) end
    return skills and skills[kind]
end

-- Which spots are shown ---------------------------------------------------------

local function Wanted(s, c)
    if not c.types[KEY_OF[s.kind]] then return false end
    if c.follow and UseGM() and GM().Visible and not GM().Visible[KEY_OF[s.kind]] then return false end
    if c.canGather and PROFESSION[s.kind] then
        local have = Skill(s.kind)
        if not have or have < s.skill then return false end
    end
    if next(c.off) then
        for _, n in ipairs(s.names) do
            if not c.off[n] then return true end
        end
        return false
    end
    return true
end

local filtered = {}   -- mapID -> { sig =, list = }
local function FilterSig()
    local c = Cfg()
    local gm = UseGM()
    local t = { version, c.canGather and 1 or 0, Skill("h") or 0, Skill("m") or 0, gm and 1 or 0 }
    local shows = gm and c.follow and gm.Visible
    for _, g in ipairs(ns.GATHER_TYPES) do
        t[#t + 1] = c.types[g.key] and 1 or 0
        if shows then t[#t + 1] = shows[g.key] and 1 or 0 end
    end
    for n in pairs(c.off) do t[#t + 1] = n end
    return table.concat(t, ",")
end

local function Filtered(mapID)
    local sig = FilterSig()
    local f = filtered[mapID]
    if f and f.sig == sig then return f.list end
    local c, list = Cfg(), {}
    for _, s in ipairs(Spots(mapID)) do
        if Wanted(s, c) then list[#list + 1] = s end
    end
    filtered[mapID] = { sig = sig, list = list }
    return list
end

-- the classic trade skill colours, by how far your skill is past the node's
local function SkillColor(s)
    local have = Skill(s.kind)
    if not (PROFESSION[s.kind] and have) or s.skillUnknown then return nil end
    local d = have - s.skill
    if d < 0 then return 0.85, 0.15, 0.15 end
    if d < 25 then return 1, 0.5, 0.25 end
    if d < 50 then return 1, 1, 0 end
    if d < 100 then return 0.25, 0.75, 0.25 end
    return 0.55, 0.55, 0.55
end

-- Pin: the one under the cursor -------------------------------------------------

BFIGatherPinMixin = CreateFromMixins(MapCanvasPinMixin)
BFIGatherPinMixin.CheckMouseButtonPassthrough = ns.SafePassthrough  -- see Pin.lua

function BFIGatherPinMixin:OnLoad()
    if self.UseFrameLevelType then
        pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_BFI_GATHER")
    end
    self.Icon:SetTexture(SHEET)
    Glyph(self.Icon, "ring")
    self.Icon:SetVertexColor(1, 0.95, 0.7, 0.9)
end

function BFIGatherPinMixin:ApplyCurrentScale()
    local map = self:GetMap()
    local canvasScale = map and map.GetCanvasScale and map:GetCanvasScale() or 1
    if not canvasScale or canvasScale <= 0 then canvasScale = 1 end
    self:SetScale(ns.PinScale("gather", Cfg().scale) * 1.6 / canvasScale)  -- (PinScale: town view, small map)
    ns.ReanchorPin(self, map)
end

function BFIGatherPinMixin:ApplyCurrentAlpha()
    self:SetAlpha(1)
end

function BFIGatherPinMixin:OnAcquired(x, y, spot)
    self.spot = spot
    self:ApplyCurrentScale()
    self:SetPosition(x, y)
end

local function WhenSeen(t)
    local days = math.floor((time() - t) / 86400)
    if days < 1 then return "today" end
    if days == 1 then return "yesterday" end
    return days .. " days ago"
end

function BFIGatherPinMixin:OnEnter()
    local s = self.spot
    if not s then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(s.names[1])
    local prof = PROFESSION[s.kind]
    if prof then
        local need = math.max(s.skill, 1)
        local have = Skill(s.kind)
        if s.skillUnknown then
            GameTooltip:AddLine(prof, 1, 1, 1)
        elseif have and have >= need then
            GameTooltip:AddLine(prof .. " " .. need, 1, 1, 1)
        else
            GameTooltip:AddLine(prof .. " " .. need, 1, 0.25, 0.25)
        end
    end
    if #s.names > 1 then
        GameTooltip:AddLine("May be: " .. table.concat(s.names, ", ", 2), 1, 0.82, 0, true)
    end
    if s.seen > 0 then
        local line = s.seen == 1 and "You gathered here once" or ("You gathered here " .. s.seen .. " times")
        GameTooltip:AddLine(s.last and (line .. ", last " .. WhenSeen(s.last)) or line, 0.75, 0.75, 0.8)
    else
        GameTooltip:AddLine("Not gathered by you yet", 0.6, 0.6, 0.65)
    end
    ns.PinHints()
    GameTooltip:Show()
end

function BFIGatherPinMixin:OnLeave()
    GameTooltip:Hide()
end
-- the map wires a pin's mouse-over to these (see Pin.xml)
BFIGatherPinMixin.OnMouseEnter = BFIGatherPinMixin.OnEnter
BFIGatherPinMixin.OnMouseLeave = BFIGatherPinMixin.OnLeave

function BFIGatherPinMixin:OnMouseUp(button)
    local s = self.spot
    if button == "RightButton" and s then
        -- (the menu outlives this pin, which goes as the cursor moves off: rows work from the spot)
        local c, items = Cfg(), {}
        for _, n in ipairs(s.names) do
            items[#items + 1] = { "hide " .. n, function()
                c.off[n] = true
                ns.OnSettingChanged("gather", "off")
            end }
        end
        local owner = self:GetMap()
        ns.PinMenu({ normalizedX = s.x, normalizedY = s.y, GetMap = function() return owner end }, items, s.names[1])
        return
    end
    if ns.PinAltClick then ns.PinAltClick(self, button) end  -- line target (Line.lua)
end

-- The layer -----------------------------------------------------------------------

local map, host
local marks, used = {}, 0   -- the texture pool, and how many are in use
local job                   -- what's still to lay: { list, i, ... }
local grid = {}             -- hover: cell -> spots
local drawnSig
local hoverPin, hoverSpot
local info = { spots = 0, textures = 0 }

local function Take()
    used = used + 1
    local t = marks[used]
    if not t then
        t = host:CreateTexture(nil, "ARTWORK")
        t:SetTexture(SHEET)
        marks[used] = t
    end
    return t
end

local function MarkSize()
    local s = map:GetCanvasScale() or 1
    if s <= 0 then s = 1 end
    return MARK * ns.PinScale("gather", Cfg().scale) / s
end

local function Lay(t, x, y, size, W, H)
    t:ClearAllPoints()
    t:SetPoint("CENTER", host, "TOPLEFT", x * W, -y * H)
    t:SetSize(size, size)
    t:Show()
end

local function SpotColor(s)
    if s.kind == "m" then
        local n = s.names[1]:gsub("^Ooze Covered ", ""):gsub("^Rich ", ""):gsub("^Small ", "")
        return METAL[n:match("^%S+")] or COLOR.m
    end
    return COLOR[s.kind]
end

local function PaintMark(t, s, c)
    local a = (c.fadeUnseen and s.seen == 0) and 0.6 or 1
    if c.look == "gathermate" and s.icon then
        t:SetTexture(s.icon)
        t:SetTexCoord(0, 1, 0, 1)
        t:SetVertexColor(1, 1, 1, a)
        t.gmIcon = true
        return
    end
    if t.gmIcon then
        t:SetTexture(SHEET)
        t.gmIcon = nil
    end
    local col = SpotColor(s)
    local r, g, b = col[1], col[2], col[3]
    local tinted
    if c.tint then
        local tr, tg, tb = SkillColor(s)
        if tr then r, g, b, tinted = tr, tg, tb, true end
    end
    -- (a mark in its own colours; skill colours need a white one)
    local own = not tinted and ns.NodeMarkCells[s.names[1]]
    if own then
        Cell(t, own)
        t:SetVertexColor(1, 1, 1, a)
        return
    end
    Glyph(t, s.kind)
    t:SetVertexColor(r, g, b, a)
end

local function StepJob()
    local W, H = job.W, job.H
    local stop = math.min(job.i + PER_FRAME - 1, #job.list)
    local size, c = job.size, Cfg()
    for i = job.i, stop do
        local s = job.list[i]
        local t = Take()
        PaintMark(t, s, c)
        Lay(t, s.x, s.y, size, W, H)
    end
    job.i = stop + 1
    if job.i > #job.list then
        job = nil
        for i = used + 1, #marks do marks[i]:Hide() end
        info.textures = used
    end
end

local function DropHover()
    if hoverPin then
        if GameTooltip:IsOwned(hoverPin) then GameTooltip:Hide() end
        pcall(map.RemoveAllPinsByTemplate, map, TEMPLATE)
        hoverPin, hoverSpot = nil, nil
    end
end

local function Clear()
    job, drawnSig = nil, nil
    used = 0
    wipe(grid)
    info.spots, info.textures = 0, 0
    for _, t in ipairs(marks) do t:Hide() end
    DropHover()
end

local function Draw()
    if not (map and host and ns.db) then return end
    local mapID = map:GetMapID()
    if not (mapID and ns.IsShown("gather")) then
        host:Hide()
        Clear()
        return
    end
    local canvas = map:GetCanvas()
    local W, H = canvas:GetWidth(), canvas:GetHeight()
    if not (W and W > 0 and H > 0) then return end
    host:SetParent(canvas)
    host:SetAllPoints(canvas)
    host:SetFrameLevel(ns.ArtLevel and ns.ArtLevel(map, 7) or canvas:GetFrameLevel() + 1)
    host:SetAlpha(ns.PinAlpha("gather"))
    host:Show()

    local c = Cfg()
    local gm = c.follow and UseGM()
    if gm then
        -- (GatherMate works out what's visible when its display updates: ask it to now)
        local ok, display = pcall(gm.GetModule, gm, "Display", true)
        if ok and display and display.UpdateVisibility then pcall(display.UpdateVisibility, display) end
    end
    local list = Filtered(mapID)
    local sig = table.concat({ mapID, W, H, c.look, c.tint and 1 or 0, c.fadeUnseen and 1 or 0, FilterSig() }, ";")
    if sig == drawnSig then return end
    drawnSig = sig

    wipe(grid)
    for _, s in ipairs(list) do
        local k = math.floor(s.x * CELLS) * 256 + math.floor(s.y * CELLS)
        local cell = grid[k]
        if not cell then cell = {} grid[k] = cell end
        cell[#cell + 1] = s
    end
    DropHover()
    used = 0
    info.spots = #list
    job = { list = list, i = 1, W = W, H = H, size = MarkSize() }
    if #job.list == 0 then
        job = nil
        for _, t in ipairs(marks) do t:Hide() end
        info.textures = 0
    end
end

-- after a zoom: the marks keep their size on screen
local resizing
local function Resize()
    resizing = nil
    if not (map and host and host:IsShown()) then return end
    local size = MarkSize()
    if job then job.size = size end
    for i = 1, used do marks[i]:SetSize(size, size) end
end

local function WantResize()
    if not resizing then
        resizing = true
        C_Timer.After(0.08, Resize)
    end
end

-- the spot under the cursor, within reach
local function SpotAt(mx, my)
    local scale = map:GetCanvasScale() or 1
    local W = map:GetCanvas():GetWidth()
    local H = map:GetCanvas():GetHeight()
    local reach = HOVER_PX / (W * scale)
    local aspect = W / H
    local best, bd = nil, reach * reach
    local cx, cy = math.floor(mx * CELLS), math.floor(my * CELLS)
    for i = -1, 1 do
        for j = -1, 1 do
            local cell = grid[(cx + i) * 256 + cy + j]
            if cell then
                for _, s in ipairs(cell) do
                    local dx, dy = s.x - mx, (s.y - my) / aspect
                    local d = dx * dx + dy * dy
                    if d < bd then best, bd = s, d end
                end
            end
        end
    end
    return best
end

local hoverWait = 0
local function OnUpdate(_, elapsed)
    if job then StepJob() end
    hoverWait = hoverWait + elapsed
    if hoverWait < 0.05 then return end
    hoverWait = 0
    if not next(grid) then return end
    local s
    if map:IsMouseOver() and map.GetNormalizedCursorPosition then
        local ok, mx, my = pcall(map.GetNormalizedCursorPosition, map)
        if ok and mx then s = SpotAt(mx, my) end
    end
    if s == hoverSpot then return end
    DropHover()
    if s then
        local ok, pin = pcall(map.AcquirePin, map, TEMPLATE, s.x, s.y, s)
        if ok and pin then hoverPin, hoverSpot = pin, s end
    end
end

-- The minimap ---------------------------------------------------------------------
-- (Docked, the map is the minimap and carries the marks itself.) Which spots are near is worked out
-- every quarter second, the nearest RING_MAX; where they sit follows you every frame, or they'd
-- step along behind the minimap's smooth scroll.

local ring, ringMarks, ringUsed = nil, {}, 0
local ringZone, ringW, ringH, ringRadius, ringReach, ringTurns
local lastX, lastY, lastTurn
local ringInfo = "off"

-- the yards across the minimap at each zoom, for clients that won't say (Era)
local ACROSS = {
    indoor = { [0] = 300, 240, 180, 120, 80, 50 },
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 6, 200, 133 + 1 / 3 },
}

local function ViewRadius()
    if C_Minimap and C_Minimap.GetViewRadius then return C_Minimap.GetViewRadius() end
    if Minimap.GetViewRadius then return Minimap:GetViewRadius() end
    local zoom = Minimap:GetZoom()
    local outdoors = tonumber(GetCVar("minimapZoom")) == zoom
    return ACROSS[outdoors and "outdoor" or "indoor"][zoom] / 2
end

-- the zone you're in that spots are kept for, and where you are on it. The game can name a mine or
-- cave of its own, or (Era) the continent: then its parents, then the zone on the map.
local function HasSpots(id)
    if UseGM() then return #Spots(id) > 0 end
    local d = Data()
    return d and d.zones[id]
end

local function ZoneHere()
    local id = C_Map.GetBestMapForUnit("player")
    while id and id > 0 do
        if HasSpots(id) or Own(id) then
            local pos = C_Map.GetPlayerMapPosition(id, "player")
            if pos then return id, pos:GetXY() end
        end
        local mapInfo = C_Map.GetMapInfo(id)
        id = mapInfo and mapInfo.parentMapID
    end
    local shown = map and map:GetMapID()
    if shown and HasSpots(shown) then
        local pos = C_Map.GetPlayerMapPosition(shown, "player")
        if pos then return shown, pos:GetXY() end
    end
end

ns.MinimapYards = ViewRadius   -- (DevNodes.lua: /bfinodes range)

local function HideMark(t)
    t:Hide()
    t.circle:Hide()
end

local function ClearRing()
    for i = 1, ringUsed do HideMark(ringMarks[i]) end
    ringUsed = 0
    ringZone = nil
end

local near = {}

-- which kinds the game's tracking is showing you, asked again every few seconds and when it changes
-- (after a /reload the game may not have its tracking list yet, and sends no event when it does)
local TRACKS = { h = 2383, m = 2580, t = 2481, f = 43308 }   -- Find Herbs, Minerals, Treasure, Fish
local tracked, trackTick = nil, 0
local trackInfo = "not read"

local function ReadTracking()
    tracked = {}
    local spellName = C_Spell and C_Spell.GetSpellName or GetSpellInfo
    local spellIcon = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
    local function Note(name, spellID, icon)
        for kind, id in pairs(TRACKS) do
            if spellID == id or (name and name == spellName(id)) or (icon and spellIcon and icon == spellIcon(id)) then
                tracked[kind] = true
            end
        end
    end
    local read = C_Minimap and C_Minimap.GetTrackingInfo or GetTrackingInfo
    local count = C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetNumTrackingTypes()
        or (GetNumTrackingTypes and GetNumTrackingTypes()) or 0
    local on = {}
    for i = 1, read and count or 0 do
        -- (a table on some clients, a list of values on others)
        local x, y, z, _, _, id = read(i)
        local name, active, spellID, icon = x, z, id, y
        if type(x) == "table" then name, active, spellID, icon = x.name, x.active, x.spellID, x.texture end
        if active then
            on[#on + 1] = tostring(name)
            Note(name, spellID, icon)
        end
    end
    local icon = GetTrackingTexture and GetTrackingTexture()
    if icon then Note(nil, nil, icon) end
    trackInfo = string.format("%d types, on: %s, icon %s", count, table.concat(on, " "), tostring(icon))
end

-- A mark would sit on top of the game's blip, so one you're tracking becomes a ring as you come in
-- range, as GatherMate2's: the blip shows inside it. 0: the mark, 1: the ring.
local ringYards = 125
local function RingShare(kind, d2)
    if not (tracked and tracked[kind]) or d2 >= (ringYards + RING_EDGE) ^ 2 then return 0 end  -- (nil: read again next tick)
    local d = math.sqrt(d2)
    if d <= ringYards then return 1 end
    return 1 - (d - ringYards) / RING_EDGE
end

-- where the marks sit, from where you are now
local function PlaceRing()
    if ringUsed == 0 or not ringZone then return end
    local pos = C_Map.GetPlayerMapPosition(ringZone, "player")
    if not pos then return end
    local px, py = pos:GetXY()
    local turn = ringTurns and (GetPlayerFacing() or 0) or 0
    if px == lastX and py == lastY and turn == lastTurn then return end
    lastX, lastY, lastTurn = px, py, turn
    local sin, cos = math.sin(turn), math.cos(turn)
    local k = Minimap:GetWidth() / 2 / ringRadius
    local reach = ringReach
    for i = 1, ringUsed do
        local t, s = ringMarks[i], near[i].s
        local dx, dy = (s.x - px) * ringW, (s.y - py) * ringH
        local d2 = dx * dx + dy * dy
        if d2 < reach then
            local x, y = dx * k, -dy * k
            local share = RingShare(near[i].s.kind, d2)
            local at, up = x * cos - y * sin, x * sin + y * cos
            t:SetAlpha(1 - share)
            t:SetPoint("CENTER", Minimap, "CENTER", at, up)
            t:Show()
            local circle = t.circle
            if share > 0 then
                circle:SetAlpha(share)
                circle:SetPoint("CENTER", Minimap, "CENTER", at, up)
                circle:Show()
            else
                circle:Hide()
            end
        else
            HideMark(t)
        end
    end
end

-- which spots are near
local function UpdateRing()
    local c = ns.db and Cfg()
    if not c or not c.minimap or not ns.IsShown("gather") or (ns.Docked and ns.Docked()) or not (UseGM() or Data()) then
        ringInfo = "off"
        return ClearRing()
    end
    trackTick = trackTick + 1
    if not tracked or trackTick >= 8 then
        trackTick = 0
        local ok, err = pcall(ReadTracking)
        if not ok then trackInfo = tostring(err) end
    end
    ringYards = c.ringYards or 125
    local mapID, px, py = ZoneHere()
    local w, h
    if mapID then w, h = ns.MapYards(mapID) end
    local radius = ViewRadius()
    if not (mapID and w and radius and radius > 0) then
        ringInfo = "no zone here (" .. tostring(C_Map.GetBestMapForUnit("player")) .. ")"
        return ClearRing()
    end
    local n, r2 = 0, radius * radius * 1.3   -- (a little past the edge: marks slide in as you ride)
    for _, s in ipairs(Filtered(mapID)) do
        local dx, dy = (s.x - px) * w, (s.y - py) * h
        local d = dx * dx + dy * dy
        if d < r2 then
            n = n + 1
            local e = near[n]
            if not e then e = {} near[n] = e end
            e.s, e.d = s, d
        end
    end
    for i = n + 1, #near do near[i] = nil end
    if n > RING_MAX then table.sort(near, function(a, b) return a.d < b.d end) end
    local count = math.min(n, RING_MAX)
    local size = MARK * (c.scale or 1)
    for i = 1, count do
        local t = ringMarks[i]
        if not t then
            t = ring:CreateTexture(nil, "OVERLAY")
            t:SetTexture(SHEET)
            if t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false)
                t:SetTexelSnappingBias(0)
            end
            local circle = ring:CreateTexture(nil, "OVERLAY")
            circle:SetTexture(SHEET)
            Glyph(circle, "ring")
            circle:SetSize(RING_PX, RING_PX)
            if circle.SetSnapToPixelGrid then
                circle:SetSnapToPixelGrid(false)
                circle:SetTexelSnappingBias(0)
            end
            t.circle = circle
            ringMarks[i] = t
        end
        PaintMark(t, near[i].s, c)
        t:SetSize(size, size)
        local col = SpotColor(near[i].s)
        t.circle:SetVertexColor(col[1], col[2], col[3], 1)
    end
    for i = count + 1, ringUsed do HideMark(ringMarks[i]) end
    ringUsed = count
    ringZone, ringW, ringH, ringRadius, ringReach = mapID, w, h, radius, radius * radius * 0.94
    ringTurns = GetCVar("rotateMinimap") == "1"
    local on = {}
    for kind in pairs(tracked) do on[#on + 1] = kind end
    table.sort(on)
    ringInfo = string.format("map %d, radius %.0f yd, zoom %s, %d near, %d drawn, tracking [%s] (%s)", mapID, radius,
        tostring(Minimap:GetZoom()), n, count, table.concat(on, " "), trackInfo)
    lastX = nil
    PlaceRing()
end

-- What you gather ------------------------------------------------------------------

local function Yards(mapID, a, b)
    local w, h = ns.MapYards(mapID)
    if not w then return math.huge end
    local dx, dy = (a[1] - b[1]) * w, (a[2] - b[2]) * h
    return math.sqrt(dx * dx + dy * dy)
end

-- adds to your own list; a name with no known kind needs `kind`
local function Record(mapID, x, y, name, kind, times, when)
    local db = WaymarkNodesDB
    db.spots[mapID] = db.spots[mapID] or {}
    local own = db.spots[mapID]
    local e = { x, y, name, kind, times or 1, when }
    local same
    for _, o in ipairs(own) do
        if o[3] == name and Yards(mapID, o, e) < SAME then same = o break end
    end
    if same then
        same[5] = same[5] + e[5]
        same[6] = when
    else
        own[#own + 1] = e
    end
    spotsOf[mapID] = nil
    version = version + 1
end

local gatherSpell = {}   -- spell name -> kind
local function GatherSpells()
    local name = C_Spell and C_Spell.GetSpellName or GetSpellInfo
    for id, kind in pairs({ [2366] = "h", [2575] = "m" }) do
        local n = name and name(id)
        if n then gatherSpell[n] = kind end
    end
    gatherSpell["Herb Gathering"], gatherSpell["Mining"] = "h", "m"
end

local cast = {}   -- what the cast on its way is aimed at
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id))
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit, a, b, c)
    if event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        skills = nil
        if ns.RedrawGather then ns.RedrawGather() end
        return
    end
    if event == "MINIMAP_UPDATE_TRACKING" then
        tracked = nil
        return
    end
    if unit ~= "player" then return end
    if event == "UNIT_SPELLCAST_SENT" then
        -- (unit, target, castGUID, spellID)
        if issecretvalue and issecretvalue(a) then return end
        cast.target, cast.guid, cast.spell = a, b, c
        return
    end
    -- UNIT_SPELLCAST_SUCCEEDED: (unit, castGUID, spellID)
    if a ~= cast.guid or not cast.target or cast.target == "" then return end
    local target = cast.target
    cast.target = nil
    Data()
    local kind = gatherSpell[SpellName(b) or ""] or (typeOf[target] and typeOf[target][2])
    if not kind then return end
    local mapID, x, y = ZoneHere()
    if not mapID then
        -- (a zone with no spots of its own yet)
        mapID = C_Map.GetBestMapForUnit("player")
        local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        local mapInfo = mapID and C_Map.GetMapInfo(mapID)
        if not (pos and mapInfo and mapInfo.mapType == Enum.UIMapType.Zone) then return end
        x, y = pos:GetXY()
    end
    Record(mapID, x, y, target, kind, 1, time())
    if ns.RedrawGather then ns.RedrawGather() end
end)

-- your GatherMate2 spots, copied into your own list; how many
function ns.ImportGatherMate()
    local gm = _G.GatherMate2
    if not (gm and gm.gmdbs and gm.GetNameForNode and gm.DecodeLoc) then return nil end
    local n = 0
    for _, t in ipairs(ns.GATHER_TYPES) do
        for mapID, nodes in pairs(gm.gmdbs[t.key] or {}) do
            for coord, id in pairs(nodes) do
                id = gm.nodeIDReplacementMap and gm.nodeIDReplacementMap[id] or id
                local name = gm:GetNameForNode(t.key, id)
                if name then
                    local x, y = gm:DecodeLoc(coord)
                    Record(mapID, x, y, name, t.kind, 1, nil)
                    n = n + 1
                end
            end
        end
    end
    if ns.RedrawGather then ns.RedrawGather() end
    return n
end

-- how many spots of what you've switched on are within `yards` of a point. For auto-zoom and the
-- Gathering profile, drawn or not.
function ns.GatherNodesNear(mapID, px, py, yards)
    if not (px and (UseGM() or Data())) then return 0 end
    local w, h = ns.MapYards(mapID)
    if not w then return 0 end
    local n, r2 = 0, yards * yards
    for _, s in ipairs(Filtered(mapID)) do
        local dx, dy = (s.x - px) * w, (s.y - py) * h
        if dx * dx + dy * dy <= r2 then n = n + 1 end
    end
    return n
end

-- for /bfi check
function ns.GatherInfo()
    local own, zones = 0, 0
    for _, l in pairs(WaymarkNodesDB and WaymarkNodesDB.spots or {}) do
        own, zones = own + #l, zones + 1
    end
    return string.format("source %s, data %s, %d spots shown, %d textures, look %s, own %d in %d zones, herb %s mine %s; minimap: %s",
        UseGM() and "GatherMate2" or "Waymark", Data() and "loaded" or "missing", info.spots, info.textures, tostring(Cfg().look),
        own, zones, tostring(Skill("h")), tostring(Skill("m")), ringInfo)
end

-- Setup ---------------------------------------------------------------------------

BFIGatherProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function BFIGatherProviderMixin:RemoveAllData() DropHover() end
function BFIGatherProviderMixin:RefreshAllData() Draw() end
function BFIGatherProviderMixin:OnMapChanged() Draw() end
function BFIGatherProviderMixin:OnCanvasScaleChanged() WantResize() end
function BFIGatherProviderMixin:OnCanvasSizeChanged() Draw() end

function ns.SetupGather(frame)
    WaymarkNodesDB = WaymarkNodesDB or {}
    WaymarkNodesDB.spots = WaymarkNodesDB.spots or {}
    GatherSpells()
    if Cfg().look ~= "gathermate" then Cfg().look = "ink" end   -- (earlier looks, Patches and Dots, are gone)
    map = frame
    host = CreateFrame("Frame", nil, map:GetCanvas())
    host:Hide()
    host:EnableMouse(false)
    host:SetScript("OnUpdate", OnUpdate)
    if ns.debugFrames then ns.debugFrames.gather = host end

    local provider = CreateFromMixins(BFIGatherProviderMixin)
    local ok, err = pcall(map.AddDataProvider, map, provider)
    if not ok then
        ns.Log("Gathering layer failed:", err)
        return
    end
    function ns.RedrawGather()
        if map:IsShown() then Draw() end
    end
    hooksecurefunc(ns, "ApplyGroups", function()
        if ns.db then
            if host:IsShown() ~= ns.IsShown("gather") then Draw() end
            host:SetAlpha(ns.PinAlpha("gather"))
        end
    end)
    hooksecurefunc(ns, "ApplyScales", WantResize)

    ring = CreateFrame("Frame", nil, Minimap)
    ring:SetAllPoints(Minimap)
    ring:SetFrameLevel(Minimap:GetFrameLevel() + 3)
    local wait = 0
    ring:SetScript("OnUpdate", function(_, elapsed)
        wait = wait + elapsed
        if wait >= 0.25 then
            wait = 0
            UpdateRing()
        else
            PlaceRing()
        end
    end)

    for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "MINIMAP_UPDATE_TRACKING" }) do
        pcall(events.RegisterEvent, events, e)
    end
end
