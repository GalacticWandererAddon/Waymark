local _, ns = ...

-- Exploration: the areas you haven't found yet (hidden as the game does, or shown
-- faded, fogged, in sepia or fully), how much of a zone you've seen, a gold flash
-- where you discover a new area, and the name of the area under the cursor.
-- The full list of each zone's area overlays is ours (Data\MapOverlays.lua, made
-- by tools\map_overlays.py from the game's tables); the game only tells addons
-- which ones you've explored.

local function Cfg() return ns.db.explore end

-- fogStyle: how unexplored areas look. desat = desaturation, tint = vertex colour
local FOG_STYLES = {
    faded   = { desat = 0,    tint = { 1, 1, 1 } },
    fog     = { desat = 0.85, tint = { 0.62, 0.66, 0.72 } },
    sepia   = { desat = 1,    tint = { 0.85, 0.68, 0.45 } },
    ink     = { desat = 1,    tint = { 0.35, 0.30, 0.26 } },
    full    = { desat = 0,    tint = { 1, 1, 1 } },
}
ns.FOG_STYLES = FOG_STYLES

local FLASH_TIME = 3     -- seconds
local FLASH_COLOR = { 1, 0.82, 0.25 }

-- Overlays ----------------------------------------------------------------

local function Key(w, h, x, y) return w .. ":" .. h .. ":" .. x .. ":" .. y end

-- this map's overlays, each with its file IDs split out (cached)
local parsed = {}
local function Overlays(mapID)
    if parsed[mapID] ~= nil then return parsed[mapID] end
    -- (Classic Era, standing in for Forever, has its own art: its own list)
    local all = (ns.MapEdition() == "Era" and ns.MapOverlaysEra) or ns.MapOverlays
    local raw = all and all[mapID]
    if not raw then parsed[mapID] = false return false end
    local list = {}
    for _, o in ipairs(raw) do
        local files = {}
        for fid in o[9]:gmatch("%d+") do files[#files + 1] = tonumber(fid) end
        local areas = {}
        for i = 10, #o do areas[#areas + 1] = o[i] end
        list[#list + 1] = {
            w = o[1], h = o[2], x = o[3], y = o[4],
            top = o[5], bottom = o[6], left = o[7], right = o[8],
            files = files, areas = areas, key = Key(o[1], o[2], o[3], o[4]),
        }
    end
    parsed[mapID] = list
    return list
end

-- keys of the overlays you've explored on this map
local function ExploredKeys(mapID)
    local keys = {}
    if not (C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures) then return keys end
    local ok, list = pcall(C_MapExplorationInfo.GetExploredMapTextures, mapID)
    if not (ok and list) then return keys end
    for _, t in ipairs(list) do
        keys[Key(t.textureWidth, t.textureHeight, t.offsetX, t.offsetY)] = true
    end
    if ns.FOREVER or not ns.ForeverMapDev() then return keys end
    -- Forever's maps on Classic Era (dev): the game names Classic Era's pieces; Forever's
    -- that share an area with one of them count as explored
    local seen, out = {}, {}
    for _, o in ipairs(ns.MapOverlaysEra and ns.MapOverlaysEra[mapID] or {}) do
        if keys[Key(o[1], o[2], o[3], o[4])] then
            for i = 10, #o do seen[o[i]] = true end
        end
    end
    for _, o in ipairs(Overlays(mapID) or {}) do
        for _, a in ipairs(o.areas) do
            if seen[a] then out[o.key] = true break end
        end
    end
    return out
end

-- the size of the map's art in its own pixels (the overlays' units)
local function ArtSize(mapID)
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
    local l = layers and layers[1]
    if l and l.layerWidth and l.layerWidth > 0 then return l.layerWidth, l.layerHeight end
    return 1002, 668
end

-- The part of the map art the zone itself takes up, plus a margin: the extent of
-- its clear-view outline (Data\ZoneCutBounds.lua; a ticked view of it, its own),
-- else all its areas' hover boxes together. Returns left, top, right, bottom in
-- art pixels and the art's width and height, or nil for maps without area data
-- (continents, caves). The hover boxes alone fell short on zones with few areas:
-- Moonglade's one box is its lake, and fully zoomed out cut off the valley.
local BOUNDS_MARGIN = 0.04   -- of the art's size, each side (hover boxes)
local OUTLINE_MARGIN = 0.015 -- (an outline: already the zone's edge)
local boundsCache = {}

-- the outline name the bounds come from: a ticked view of this map, else its own
local function OutlineName(mapID)
    local cv = ns.db and ns.db.clearView
    if cv and ns.CutViews then
        for _, v in ipairs(ns.CutViews()) do
            if v.base == mapID and cv["view_" .. v.name] then return v.name end
        end
    end
    return mapID
end

local function OutlineBounds(name)
    local all = ns.ZoneCutBounds and ns.ZoneCutBounds[ns.CutEdition and ns.CutEdition() or "Era"]
    return all and all[name]
end

function ns.ZoneBounds(mapID)
    if not mapID then return end
    local name = OutlineName(mapID)
    if boundsCache[name] ~= nil then return unpack(boundsCache[name] or {}) end
    -- (only the maps with area data, as before: cities and battlegrounds have an
    -- outline too, but never fitted)
    local list = Overlays(mapID)
    if not (list and list[1]) then boundsCache[name] = false return end
    local aw, ah = ArtSize(mapID)
    local v
    local o = OutlineBounds(name) or OutlineBounds(mapID)
    if o then
        local mx, my = aw * OUTLINE_MARGIN, ah * OUTLINE_MARGIN
        v = { math.max(0, o[1] * aw - mx), math.max(0, o[2] * ah - my),
              math.min(aw, o[3] * aw + mx), math.min(ah, o[4] * ah + my), aw, ah }
    else
        local l, t, r, b = math.huge, math.huge, -math.huge, -math.huge
        -- the hover boxes, not the overlay images: those are padded out to powers of
        -- two and reach well into the neighbours (the Barrens' into Durotar). Some
        -- of Forever's are empty (all 0): skipped, they pulled the box to the corner
        for _, ov in ipairs(list) do
            if ov.right > ov.left and ov.bottom > ov.top then
                l, t = math.min(l, ov.left), math.min(t, ov.top)
                r, b = math.max(r, ov.right), math.max(b, ov.bottom)
            end
        end
        if l < r then
            local mx, my = aw * BOUNDS_MARGIN, ah * BOUNDS_MARGIN
            v = { math.max(0, l - mx), math.max(0, t - my), math.min(aw, r + mx), math.min(ah, b + my), aw, ah }
        end
    end
    boundsCache[name] = v or false
    if not v then return end
    return unpack(v)
end

-- Whether a spot on a zone map (0..1) lies in another zone: the zone map's art
-- shows bits of its neighbours, and quest pins can land there. Asked of the
-- continent map, which knows the zones' real outlines (not our area boxes).
-- Sea or no answer counts as inside. Cached per map, to 1/200 of the map.
local outsideCache = {}
function ns.IsOutsideZone(mapID, nx, ny)
    if not (mapID and nx and C_Map.GetMapRectOnMap and C_Map.GetMapInfoAtPosition) then return false end
    local c = outsideCache[mapID]
    if not c then
        c = {}
        local info = C_Map.GetMapInfo(mapID)
        if info and info.mapType == Enum.UIMapType.Zone then
            local parent = MapUtil and MapUtil.GetMapParentInfo
                and MapUtil.GetMapParentInfo(mapID, Enum.UIMapType.Continent, true)
            if parent then
                local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, mapID, parent.mapID)
                if ok and minX and maxX > minX then c.rect = { parent.mapID, minX, maxX, minY, maxY } end
            end
        end
        outsideCache[mapID] = c
    end
    if not c.rect then return false end
    local key = math.floor(nx * 200) * 1000 + math.floor(ny * 200)
    if c[key] ~= nil then return c[key] end
    local cont, minX, maxX, minY, maxY = unpack(c.rect)
    local ok, at = pcall(C_Map.GetMapInfoAtPosition, cont, minX + nx * (maxX - minX), minY + ny * (maxY - minY))
    local outside = ok and at and at.mapID ~= mapID and at.mapType == Enum.UIMapType.Zone or false
    c[key] = outside
    return outside
end

-- How much of a zone you've explored: percent, explored, total (nil: unknown map)
function ns.ExplorationProgress(mapID)
    local list = mapID and Overlays(mapID)
    if not list or #list == 0 then return end
    local keys, n = ExploredKeys(mapID), 0
    for _, o in ipairs(list) do
        if keys[o.key] then n = n + 1 end
    end
    return math.floor(n / #list * 100 + 0.5), n, #list
end

-- for /bfi check: what the game says you've explored here, and how much of it our
-- data knows (keys are size and offset: another client's art can differ)
function ns.ExploreInfo(mapID)
    local list = mapID and Overlays(mapID)
    local ok, game = pcall(C_MapExplorationInfo.GetExploredMapTextures, mapID)
    game = ok and game or {}
    local ours = {}
    for _, o in ipairs(list or {}) do ours[o.key] = true end
    local known, sample = 0, {}
    for _, t in ipairs(game) do
        local k = Key(t.textureWidth, t.textureHeight, t.offsetX, t.offsetY)
        if ours[k] then known = known + 1 end
        if #sample < 4 then sample[#sample + 1] = k .. " " .. tostring(t.fileDataIDs and t.fileDataIDs[1]) end
    end
    return string.format("game: %d explored, %d in our data of %d; %s", #game, known, list and #list or 0,
        table.concat(sample, ", "))
end

-- Whether a spot on a map (0..1) lies in an area you haven't explored: inside an
-- unexplored area's hover box and no explored one's. (The boxes are rectangles,
-- so near an area's edge it's approximate.) Maps without area data: never.
local keyCache = {}  -- [mapID] = { t, keys }: asked per pin, so kept a few seconds
function ns.IsUnexploredAt(mapID, nx, ny)
    local list = mapID and Overlays(mapID)
    if not list then return false end
    local c = keyCache[mapID]
    if not c or GetTime() - c.t > 3 then
        c = { t = GetTime(), keys = ExploredKeys(mapID) }
        keyCache[mapID] = c
    end
    local aw, ah = ArtSize(mapID)
    local px, py = nx * aw, ny * ah
    local unexplored = false
    for _, o in ipairs(list) do
        if px >= o.left and px <= o.right and py >= o.top and py <= o.bottom then
            if c.keys[o.key] then return false end
            unexplored = true
        end
    end
    return unexplored
end

-- Lays out one overlay's 256-pixel tiles, as the game draws explored areas:
-- the last row and column are cut to size from power-of-two files
local function PowerOf2(n)
    local p = 16
    while p < n do p = p * 2 end
    return p
end

local function LayOverlay(o, parent, sx, sy, getTexture)
    local across, down = math.ceil(o.w / 256), math.ceil(o.h / 256)
    for row = 1, down do
        local ph = row < down and 256 or (o.h - 256 * (down - 1))
        local fh = row < down and 256 or PowerOf2(ph)
        for col = 1, across do
            local fid = o.files[(row - 1) * across + col]
            if fid then
                local pw = col < across and 256 or (o.w - 256 * (across - 1))
                local fw = col < across and 256 or PowerOf2(pw)
                local tex = getTexture()
                -- (no snapping to whole pixels: while the map glides it made the tiles jitter)
                if tex.SetSnapToPixelGrid then
                    tex:SetSnapToPixelGrid(false)
                    tex:SetTexelSnappingBias(0)
                end
                -- (the sharp copy, where the map art addon has one: Detail.lua)
                tex:SetTexture(ns.MapArtFile and ns.MapArtFile(fid) or fid, nil, nil, "LINEAR")
                tex:SetTexCoord(0, pw / fw, 0, ph / fh)
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", parent, "TOPLEFT", (o.x + 256 * (col - 1)) * sx, -(o.y + 256 * (row - 1)) * sy)
                tex:SetSize(pw * sx, ph * sy)
                tex:Show()
            end
        end
    end
end

-- (for the zones' art on a continent: ZoneArt.lua)
ns.ZoneOverlays, ns.ExploredOverlayKeys, ns.LayMapOverlay, ns.MapArtSize = Overlays, ExploredKeys, LayOverlay, ArtSize

-- Unexplored areas ------------------------------------------------------------

local fogHost, flashHost, seenHost
local fogTextures, fogPool = {}, {}
local seenTextures, seenFor = {}, nil  -- Forever's explored pieces on Classic Era (dev)
local fogFor  -- "mapID|explored count|style" the fog was laid out for

local function ReleaseFog()
    for _, t in ipairs(fogTextures) do
        t:Hide()
        fogPool[#fogPool + 1] = t
    end
    wipe(fogTextures)
    fogFor = nil
end

local function BuildFog(map, mapID, keys)
    ReleaseFog()
    local list = Overlays(mapID)
    if not list then return end
    local style = FOG_STYLES[Cfg().fogStyle] or FOG_STYLES.fog
    local canvas = map:GetCanvas()
    local aw, ah = ArtSize(mapID)
    local sx, sy = canvas:GetWidth() / aw, canvas:GetHeight() / ah
    local function Get()
        local t = table.remove(fogPool) or fogHost:CreateTexture(nil, "ARTWORK")
        t:SetDesaturation(style.desat)
        t:SetVertexColor(style.tint[1], style.tint[2], style.tint[3])
        fogTextures[#fogTextures + 1] = t
        return t
    end
    for _, o in ipairs(list) do
        if not keys[o.key] then LayOverlay(o, fogHost, sx, sy, Get) end
    end
end

-- Forever's maps on Classic Era (/bfi forevermap, dev): the game's explored pieces are
-- Classic Era's (Detail.lua hides them), so Forever's explored ones are laid here
local function UpdateSeen(map, mapID)
    local list = ns.ForeverMapDev() and mapID and Overlays(mapID)
    if not list then
        seenHost:Hide()
        return
    end
    local keys = ExploredKeys(mapID)
    local n = 0
    for _ in pairs(keys) do n = n + 1 end
    local canvas = map:GetCanvas()
    local want = mapID .. "|" .. n .. "|" .. canvas:GetWidth()
    if seenFor ~= want then
        seenFor = want
        local aw, ah = ArtSize(mapID)
        local sx, sy = canvas:GetWidth() / aw, canvas:GetHeight() / ah
        local used = 0
        local function Get()
            used = used + 1
            local t = seenTextures[used]
            if not t then
                t = seenHost:CreateTexture(nil, "ARTWORK")
                seenTextures[used] = t
            end
            return t
        end
        for _, o in ipairs(list) do
            if keys[o.key] then LayOverlay(o, seenHost, sx, sy, Get) end
        end
        for i = used + 1, #seenTextures do seenTextures[i]:Hide() end
    end
    seenHost:SetAlpha(map.GetGlobalAlpha and map:GetGlobalAlpha() or map.globalAlpha or 1)
    seenHost:Show()
end

-- with the game's explored-area art (they don't overlap: these are the others)
local function PlaceHosts(map)
    -- (ArtLevel: never above a pin)
    local base = ns.ArtLevel(map, 0)
    if fogHost:GetFrameLevel() ~= base then fogHost:SetFrameLevel(base) end
    if seenHost:GetFrameLevel() ~= base then seenHost:SetFrameLevel(base) end
    -- the flash: over the area art and the close-up detail, under every pin
    local flash = ns.ArtLevel(map, 3)
    if flashHost:GetFrameLevel() ~= flash then flashHost:SetFrameLevel(flash) end
end

-- Discovery flash -----------------------------------------------------------------

local known = {}  -- [mapID] = explored keys last seen (this session)
local flashTextures, flashPool = {}, {}
local flashStart

local function ReleaseFlash()
    for _, t in ipairs(flashTextures) do
        t:Hide()
        flashPool[#flashPool + 1] = t
    end
    wipe(flashTextures)
    flashStart = nil
    flashHost:Hide()
end

local function Flash(map, mapID, overlays)
    ReleaseFlash()
    local canvas = map:GetCanvas()
    local aw, ah = ArtSize(mapID)
    local sx, sy = canvas:GetWidth() / aw, canvas:GetHeight() / ah
    local function Get()
        local t = table.remove(flashPool) or flashHost:CreateTexture(nil, "OVERLAY")
        t:SetBlendMode("ADD")
        t:SetDesaturation(1)
        t:SetVertexColor(FLASH_COLOR[1], FLASH_COLOR[2], FLASH_COLOR[3])
        flashTextures[#flashTextures + 1] = t
        return t
    end
    for _, o in ipairs(overlays) do LayOverlay(o, flashHost, sx, sy, Get) end
    flashStart = GetTime()
    flashHost:SetAlpha(0)
    flashHost:Show()
end

-- two soft pulses, then gone
local function UpdateFlash()
    if not flashStart then return end
    local t = (GetTime() - flashStart) / FLASH_TIME
    if t >= 1 then ReleaseFlash() return end
    flashHost:SetAlpha(math.sin(t * math.pi * 2) ^ 2 * (1 - t * 0.5))
end

-- new areas on the map you're on since we last looked
local function CheckDiscoveries(map)
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID or not Overlays(mapID) then return end
    local keys = ExploredKeys(mapID)
    local before = known[mapID]
    known[mapID] = keys
    if not before or not Cfg().flash then return end
    local new = {}
    for _, o in ipairs(Overlays(mapID)) do
        if keys[o.key] and not before[o.key] then new[#new + 1] = o end
    end
    if #new > 0 and map:IsShown() and map:GetMapID() == mapID then Flash(map, mapID, new) end
    if #new > 0 and ns.UpdateZoneName then ns.UpdateZoneName() end
end

-- Area names under the cursor ------------------------------------------------------

local hoverLabel, hoverText
local cursorLabel, cursorText  -- the name at the cursor: no frame, zone-text font

local function AreaName(areaID)
    local name = C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
    return name ~= "" and name or nil
end

-- The area (sub-zone) at a point of a zone map (0..1): the smallest area box
-- that holds it, as the hover names do. nil where there's none. (The quest
-- tracker files quests under these.)
function ns.AreaNameAt(mapID, nx, ny)
    local list = mapID and Overlays(mapID)
    if not (list and nx and ny) then return end
    local aw, ah = ArtSize(mapID)
    if not aw then return end
    local px, py = nx * aw, ny * ah
    local best, bestSize
    for _, o in ipairs(list) do
        if px >= o.left and px <= o.right and py >= o.top and py <= o.bottom then
            local size = (o.right - o.left) * (o.bottom - o.top)
            if not best or size < bestSize then best, bestSize = o, size end
        end
    end
    for _, id in ipairs(best and best.areas or {}) do
        local n = AreaName(id)
        if n then return n end
    end
end

-- the cursor is on a button or such over the map (the close X, the gear, the
-- toggles): what the mouse is on isn't the map or a pin on it (nothing, or
-- the world: a click-through map, still the map)
local function OverMapButton(sc)
    local f
    if GetMouseFoci then
        local foci = GetMouseFoci()
        f = foci and foci[1]
    elseif GetMouseFocus then
        f = GetMouseFocus()
    end
    if not f or f == WorldFrame then return false end
    while f do
        if f.bfiCoversMap then return true end  -- (the dungeon map, Dungeon.lua)
        if f == sc then return false end
        f = f.GetParent and f:GetParent()
    end
    return true
end

-- the name (and whether you've found it) of what's under the cursor:
-- on a zone map its area overlay (the smallest hover box that holds the cursor),
-- on a continent the zone
local function UnderCursor(map)
    local mapID = map:GetMapID()
    local sc = map.ScrollContainer
    if not (mapID and sc and sc:IsMouseOver() and sc.GetNormalizedCursorPosition) then return end
    if OverMapButton(sc) then return end
    local ok, nx, ny = pcall(sc.GetNormalizedCursorPosition, sc)
    if not (ok and nx and nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1) then return end

    local list = Overlays(mapID)
    if list then
        local aw, ah = ArtSize(mapID)
        local px, py = nx * aw, ny * ah
        local best, bestSize
        for _, o in ipairs(list) do
            if px >= o.left and px <= o.right and py >= o.top and py <= o.bottom then
                local size = (o.right - o.left) * (o.bottom - o.top)
                if not best or size < bestSize then best, bestSize = o, size end
            end
        end
        if best and best.areas[1] then
            local names = {}
            for _, id in ipairs(best.areas) do
                local n = AreaName(id)
                if n then names[#names + 1] = n end
            end
            if #names > 0 then
                return table.concat(names, " / "), ExploredKeys(mapID)[best.key] or false, nil
            end
        end
        return
    end

    -- a continent or the world: the zone under the cursor, with its level range
    if C_Map.GetMapInfoAtPosition then
        local ok2, info = pcall(C_Map.GetMapInfoAtPosition, mapID, nx, ny)
        if ok2 and info and info.mapID ~= mapID and info.name then
            return info.name, true, info.mapID
        end
    end
end

local function ShowHover(map)
    local c = Cfg()
    local name, found, zoneID
    -- (not over a cave: its art isn't the zone map the area boxes belong to)
    if c.hoverNames and not (ns.InCave and ns.InCave()) then name, found, zoneID = UnderCursor(map) end
    -- (a continent or the world: zone names off, browse.overviewNames)
    if zoneID and not ns.db.browse.overviewNames then
        name, zoneID = nil, nil
    end
    if name and found == false and c.hideUnexplored then
        name, zoneID = nil, nil  -- (nothing at all over unexplored areas)
    end
    if name and zoneID and ns.LevelRangeText then
        local lv = ns.LevelRangeText(zoneID)
        if lv then name = name .. "  " .. lv end
    end
    -- explored: zone-text gold; unexplored: pale silver (grey vanished on the fog)
    local r, g, b = 1, 0.82, 0
    if found == false then r, g, b = 0.8, 0.8, 0.82 end

    local size = c.hoverSize or 15
    if c.hoverWhere == "cursor" then
        hoverLabel:Hide()
        -- a pin (or anything else) showing its own tooltip wins over the area name
        if name and not GameTooltip:IsShown() then
            local font, current, flags = cursorText:GetFont()
            if font and current ~= size then cursorText:SetFont(font, size, flags or "") end
            cursorText:SetText((name:gsub(" / ", "\n")))  -- (one name a line: kept narrow)
            cursorText:SetTextColor(r, g, b)
            cursorLabel.area = map.ScrollContainer or map
            cursorLabel:Show()
        else
            cursorLabel:Hide()
        end
        return
    end
    cursorLabel:Hide()
    if name then
        -- the same size on screen whatever the map's scale, like the tooltip
        local inv = 1 / math.max(0.1, map:GetScale())
        if hoverLabel:GetScale() ~= inv then
            hoverLabel:SetScale(inv)
            if ns.UpdateZoneName then ns.UpdateZoneName() end  -- (it places the label)
        end
        local font, current, flags = hoverText:GetFont()
        if font and current ~= size then
            hoverText:SetFont(font, size, flags or "")
            hoverLabel:SetHeight(size + 8)
        end
        hoverText:SetText(name)
        hoverText:SetTextColor(r, g, b)
        hoverLabel:Show()
    else
        hoverLabel:Hide()
    end
end

-- for /bfi layers
function ns.ExploreInfo()
    if not fogHost then return "unexplored: not set up" end
    return string.format("unexplored: level %d, shown %s, alpha %.2f, %d textures, style %s; flash level %d",
        fogHost:GetFrameLevel(), tostring(fogHost:IsShown()), fogHost:GetAlpha(), #fogTextures,
        tostring(Cfg().fogStyle), flashHost:GetFrameLevel())
end

-- Update ------------------------------------------------------------------

function ns.UpdateExplore(force)
    local map = BattlefieldMapFrame
    if not (fogHost and map) then return end
    if force then ReleaseFog() end
    ns.Safe("Explore PlaceHosts", PlaceHosts, map)
    local c = Cfg()
    local mapID = map:GetMapID()
    if force then seenFor = nil end
    ns.Safe("Explore UpdateSeen", UpdateSeen, map, mapID)
    local show = ns.IsShown("explore") and mapID and Overlays(mapID)
    if not show then
        fogHost:Hide()
        return
    end
    local keys = ExploredKeys(mapID)
    local n = 0
    for _ in pairs(keys) do n = n + 1 end
    local want = mapID .. "|" .. n .. "|" .. tostring(c.fogStyle)
    if fogFor ~= want then
        ns.Safe("Explore BuildFog", BuildFog, map, mapID, keys)
        fogFor = want
    end
    -- faded is see-through by design; the others take the slider as it is.
    -- The map's own opacity fades the map art (its "global alpha"), not the
    -- frame: fade with it, as the close-up detail does, so at 0% the map is clear
    local a = c.fogAlpha or 0.7
    if c.fogStyle == "faded" then a = a * 0.6 end
    a = a * (map.GetGlobalAlpha and map:GetGlobalAlpha() or map.globalAlpha or 1)
    fogHost:SetAlpha(a)
    fogHost:Show()
end

function ns.SetupExplore(map)
    local canvas = map:GetCanvas()
    fogHost = CreateFrame("Frame", nil, canvas)
    fogHost:SetAllPoints(canvas)
    fogHost.bfiOwn = true  -- (map art of ours: clear view cuts it to the zone)
    fogHost:Hide()
    seenHost = CreateFrame("Frame", nil, canvas)
    seenHost:SetAllPoints(canvas)
    seenHost.bfiOwn = true
    seenHost:Hide()
    flashHost = CreateFrame("Frame", nil, canvas)
    flashHost:SetAllPoints(canvas)
    flashHost:Hide()

    -- the area name, at the top of the map (classic world map style)
    local area = map.ScrollContainer or map
    hoverLabel = CreateFrame("Frame", nil, area)
    hoverLabel:SetPoint("TOPLEFT", 0, -26)
    hoverLabel:SetPoint("TOPRIGHT", 0, -26)
    hoverLabel:SetHeight(20)
    hoverLabel:SetFrameLevel(math.min(area:GetFrameLevel() + 5500, 9500))
    -- Morpheus (the zone text's font), outlined and shadowed: map art is busy
    hoverText = hoverLabel:CreateFontString(nil, "OVERLAY")
    hoverText:SetFont("Fonts\\MORPHEUS.ttf", 15, "OUTLINE")
    hoverText:SetPoint("CENTER")
    hoverText:SetShadowOffset(1, -1)
    hoverText:SetShadowColor(0, 0, 0, 1)
    hoverLabel:Hide()
    ns.ExploreHoverLabel = hoverLabel  -- (the header moves it below an inside header)

    -- the name at the cursor, where a tooltip would be: just the text,
    -- following the mouse every frame, kept inside the map
    cursorLabel = CreateFrame("Frame", nil, UIParent)
    cursorLabel:SetFrameStrata("TOOLTIP")
    cursorLabel:SetSize(1, 1)
    cursorText = cursorLabel:CreateFontString(nil, "OVERLAY")
    cursorText:SetFont("Fonts\\MORPHEUS.ttf", 15, "OUTLINE")
    cursorText:SetJustifyH("CENTER")
    cursorText:SetShadowOffset(1, -1)
    cursorText:SetShadowColor(0, 0, 0, 1)
    cursorText:SetPoint("BOTTOM", cursorLabel, "CENTER")
    cursorLabel:SetScript("OnUpdate", ns.Timed("Explore cursor", function(self)
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        x, y = x / s, y / s + 14
        local w, h = cursorText:GetStringWidth(), cursorText:GetStringHeight()
        local area = self.area
        local l, r, t = area and area:GetLeft(), area and area:GetRight(), area and area:GetTop()
        if l and r and t then
            local k = area:GetEffectiveScale() / s
            l, r, t = l * k + 4, r * k - 4, t * k - 4
            if r - l > w then x = math.max(l + w / 2, math.min(r - w / 2, x)) end
            if y + h > t then y = y - 14 - 20 - h end  -- (at the top: below the cursor)
        end
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    end))
    cursorLabel:Hide()
    ns.debugFrames.cursorLabel = cursorLabel
    ns.debugFrames.unexplored, ns.debugFrames.flash, ns.debugFrames.hoverLabel = fogHost, flashHost, hoverLabel

    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", function() ReleaseFog() ReleaseFlash() seenFor = nil ns.UpdateExplore() end)
    end
    canvas:HookScript("OnSizeChanged", function() ReleaseFog() seenFor = nil ns.UpdateExplore() end)

    local events = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
                         "ZONE_CHANGED_NEW_AREA", "UI_INFO_MESSAGE" }) do
        events:RegisterEvent(e)
    end
    pcall(events.RegisterEvent, events, "MAP_EXPLORATION_UPDATED")
    events:SetScript("OnEvent", function()
        -- the game marks the area explored a moment after the message
        C_Timer.After(0.3, function()
            ns.Safe("Explore CheckDiscoveries", CheckDiscoveries, map)
            ns.UpdateExplore()
        end)
    end)

    local elapsed, sinceCheck = 0, 0
    local ticker = ns.TimedFrame("Explore tick")
    ticker:SetScript("OnUpdate", function(_, dt)
        UpdateFlash()
        elapsed = elapsed + dt
        if elapsed < 0.1 then return end
        sinceCheck = sinceCheck + elapsed
        elapsed = 0
        if not map:IsVisible() then
            hoverLabel:Hide()
            cursorLabel:Hide()
            return
        end
        ns.Safe("Explore ShowHover", ShowHover, map)
        if sinceCheck >= 1 then
            sinceCheck = 0
            ns.UpdateExplore()
            ns.Safe("Explore CheckDiscoveries", CheckDiscoveries, map)
        end
    end)
    ns.UpdateExplore()
end
