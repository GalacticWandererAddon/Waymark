local _, ns = ...

-- Close-up detail: when you zoom in, the game's own minimap tiles (trees, rocks,
-- buildings) fade in over the zone art, which runs out of pixels up close.
-- Technique and tile data from OpenMap (MIT, see LICENSES/OpenMap-LICENSE.txt):
-- ns.MapMinimap[continent][tx * 64 + ty] = file ID, 533.33 yards per tile,
-- tx = floor(32 - worldY / TILE) (east), ty = floor(32 - worldX / TILE) (south).

local TILE = 1600 / 3
-- with "blend" on: softened and warmed toward the map's parchment, as OpenMap does
local DESAT = 0.35
local TINT = { 1, 0.93, 0.80 }

local function Cfg() return ns.db.detail end

local host           -- frame on the canvas holding the tiles
local textures = {}  -- in use
local pool = {}
local builtFor       -- mapID the tiles were laid out for
local builtArea      -- on a continent: { l, r, t, b } (0..1) laid out around the view

local function Release()
    for _, tex in ipairs(textures) do
        tex:Hide()
        pool[#pool + 1] = tex
    end
    wipe(textures)
    builtFor, builtArea = nil, nil
end

local function GetTexture()
    local tex = table.remove(pool) or host:CreateTexture(nil, "ARTWORK")
    -- (no snapping to whole pixels: while the map glides it made the tiles jitter)
    if tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
    end
    if Cfg().blend then
        tex:SetDesaturation(DESAT)
        tex:SetVertexColor(TINT[1], TINT[2], TINT[3])
    else
        tex:SetDesaturation(0)
        tex:SetVertexColor(1, 1, 1)
    end
    return tex
end

-- world yards of a point on the map (north = X, west = Y, as the game gives them)
local function WorldAt(mapID, x, y)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not (ok and cont and pos) then return end
    local wx, wy = pos:GetXY()
    return cont, wx, wy
end

-- a continent or the world: the tiles fade in there only with detail.always,
-- or on the big map by the zone under the view (ZoneArt's ns.ContinentZoneZoom)
local mapTypeOf = {}
local function OnContinent(map)
    local id = map:GetMapID()
    if not id then return false end
    local t = mapTypeOf[id]
    if t == nil then
        local info = C_Map.GetMapInfo(id)
        t = info and info.mapType or false
        mapTypeOf[id] = t
    end
    local T = Enum and Enum.UIMapType
    return t and T and T.Continent and t <= T.Continent or false
end

-- On a continent only the tiles round the view are laid out (all of them are
-- well over a thousand): the view and AREA_MARGIN of its size each side, again
-- once the view gets near that area's edge
local AREA_MARGIN = 1
local function ViewArea(map)
    local sc = map.ScrollContainer
    local s = sc and sc:GetCanvasScale()
    local cw, ch = sc and sc.Child:GetWidth(), sc and sc.Child:GetHeight()
    if not (s and s > 0 and cw and cw > 0 and ch > 0) then return end
    local x, y = sc.currentScrollX or 0.5, sc.currentScrollY or 0.5
    return x, y, sc:GetWidth() / s / cw / 2, sc:GetHeight() / s / ch / 2
end

local function AreaStale(map)
    if not builtArea then return true end
    local x, y, hw, hh = ViewArea(map)
    if not x then return false end
    local a = builtArea
    return x - hw < a[1] or x + hw > a[2] or y - hh < a[3] or y + hh > a[4]
end

local function Build(map)
    Release()
    local mapID = map:GetMapID()
    if not (mapID and ns.MapMinimap) then return end
    -- the surface's tiles don't belong on a cave or dungeon map (Cave.lua)
    local info = C_Map.GetMapInfo(mapID)
    local T = Enum and Enum.UIMapType
    if info and T and (info.mapType == T.Dungeon or info.mapType == T.Micro or info.mapType == T.Orphan) then return end
    local cont, x0, y0 = WorldAt(mapID, 0, 0)  -- top-left: north-most X, west-most Y
    local cont1, x1, y1 = WorldAt(mapID, 1, 1)
    if not (cont and cont == cont1) or x0 == x1 or y0 == y1 then return end
    local tiles = ns.MapMinimap[cont]
    if not tiles then return end  -- not Eastern Kingdoms or Kalimdor

    local canvas = map:GetCanvas()
    local W, H = canvas:GetWidth(), canvas:GetHeight()
    -- map x follows -worldY, map y follows -worldX
    local function MapX(wy) return (y0 - wy) / (y0 - y1) end
    local function MapY(wx) return (x0 - wx) / (x0 - x1) end

    local txA, txB = math.floor(32 - math.max(y0, y1) / TILE), math.floor(32 - math.min(y0, y1) / TILE)
    local tyA, tyB = math.floor(32 - math.max(x0, x1) / TILE), math.floor(32 - math.min(x0, x1) / TILE)
    local area
    if OnContinent(map) then
        local x, y, hw, hh = ViewArea(map)
        if x then
            local k = 1 + 2 * AREA_MARGIN
            area = { x - hw * k, x + hw * k, y - hh * k, y + hh * k }
            -- (back to world yards: map x is -worldY, map y is -worldX)
            local wyL, wyR = y0 - area[1] * (y0 - y1), y0 - area[2] * (y0 - y1)
            local wxT, wxB = x0 - area[3] * (x0 - x1), x0 - area[4] * (x0 - x1)
            txA = math.max(txA, math.floor(32 - math.max(wyL, wyR) / TILE))
            txB = math.min(txB, math.floor(32 - math.min(wyL, wyR) / TILE))
            tyA = math.max(tyA, math.floor(32 - math.max(wxT, wxB) / TILE))
            tyB = math.min(tyB, math.floor(32 - math.min(wxT, wxB) / TILE))
        end
    end
    for tx = txA, txB do
        for ty = tyA, tyB do
            local fid = tiles[tx * 64 + ty]
            if fid then
                -- the tile's edges in world yards, then on the map
                local left, right = MapX((32 - tx) * TILE), MapX((31 - tx) * TILE)
                local top, bottom = MapY((32 - ty) * TILE), MapY((31 - ty) * TILE)
                local tex = GetTexture()
                tex:SetTexture(fid, nil, nil, "LINEAR")
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", host, "TOPLEFT", left * W, -top * H)
                tex:SetSize((right - left) * W, (bottom - top) * H)
                tex:Show()
                textures[#textures + 1] = tex
            end
        end
    end
    builtFor, builtArea = mapID, area
end

-- fades in as you zoom in, to all of `strength` from detail.fullZoom on
-- (MapControls' ns.DetailFade: times closer than fully out, the same at any map size)
local function UpdateAlpha(map)
    local c = Cfg()
    local fade = ns.DetailFade and ns.DetailFade(map) or 1
    if c.always then
        fade = 1  -- full detail at every zoom
    elseif OnContinent(map) then
        -- the open world keeps to the map art (and ZoneArt's zone maps); on the
        -- big map, which stays on it, by the zone under the view as its own map
        local x, reach
        if ns.ContinentZoneZoom then x, reach = ns.ContinentZoneZoom(map) end
        fade = x and ns.DetailFadeAt and ns.DetailFadeAt(x, reach) or 0
    end
    -- the map's own opacity slider fades the map art (its "global alpha"), not
    -- the frame; fade with it, or the tiles stay solid over see-through art
    local mapAlpha = map.GetGlobalAlpha and map:GetGlobalAlpha() or map.globalAlpha or 1
    local a = ns.IsShown("detail") and c.strength * fade * mapAlpha or 0
    host:SetAlpha(a)
    host:SetShown(a > 0.01)
    return a
end

-- just above the explored-area art (else it hides the tiles wherever the zone
-- is explored), below the fog and every other pin. On a continent above
-- ZoneArt's zone maps too (ns.ZoneArtTop: its explored areas). There's no
-- explored-area pin there, and ArtLevel kept under the lowest pin, which can
-- be low enough to squash the levels together: the areas then hid the tiles.
local function PlaceHost(map)
    -- (not found: just under where the game's pins start; never above a pin)
    local want = ns.ArtLevel(map, 1)
    local top = OnContinent(map) and ns.ZoneArtTop and ns.ZoneArtTop()
    if top and want <= top then want = top + 1 end
    if host:GetFrameLevel() ~= want then host:SetFrameLevel(want) end
end

-- for /bfi debug
function ns.DetailInfo()
    if not host then return "detail: not set up" end
    local map = BattlefieldMapFrame
    local explore = map and ns.CanvasLevels(map)
    local pos, n = 1, 1
    if map and ns.ZoomLevelPos then pos, n = ns.ZoomLevelPos(map) end
    return string.format("detail: level %d (explored art %s), alpha %.2f, %d tiles, shown %s, zoom step %.1f of %d, art %.2fx (from %.1fx, full %.1fx closer), map opacity %.2f",
        host:GetFrameLevel(), tostring(explore), host:GetAlpha(), #textures, tostring(host:IsShown()),
        pos, n, map and ns.ArtX and ns.ArtX(map) or 0, Cfg().fromZoom or 0, Cfg().fullZoom or 0,
        map and (map.GetGlobalAlpha and map:GetGlobalAlpha() or map.globalAlpha) or 1)
end

function ns.UpdateDetail(force)
    local map = BattlefieldMapFrame
    if not (host and map) then return end
    if force then Release() end
    ns.Safe("Detail PlaceHost", PlaceHost, map)
    local a = UpdateAlpha(map)
    if a > 0.01 and (builtFor ~= map:GetMapID() or (builtArea and AreaStale(map))) then
        ns.Safe("Detail Build", Build, map)
    end
end

local sharpenTick

-- Sharp map art (detail.sharpArt): the BattlefieldInfo_MapArt addon, made by
-- tools\hd_map_art.py, has 2x upscaled copies of the game's map art files, cut
-- to the same shapes. Where one exists it's drawn instead of the game's.
local MAPART = "Interface\\AddOns\\BattlefieldInfo_MapArt\\x2\\"

function ns.MapArtAvailable()
    return type(BattlefieldInfoMapArt) == "table" and type(BattlefieldInfoMapArt[2]) == "table"
end

-- the sharp copy of a game file, or nil
function ns.MapArtFile(fid)
    if not (Cfg().sharpArt and fid and ns.MapArtAvailable()) then return end
    if BattlefieldInfoMapArt[2][fid] then return MAPART .. fid .. ".png" end
end

-- each game art texture we've touched: what the game had on it, and what we set
local touched = setmetatable({}, { __mode = "k" })  -- [texture] = { orig, set }

local function Redraw(r, file, sharp)
    -- (its crop kept: setting the texture again could reset it)
    local c = { r:GetTexCoord() }
    r:SetTexture(file, nil, nil, sharp and "TRILINEAR" or nil)
    if #c == 8 then r:SetTexCoord(unpack(c)) end
end

local function SharpenArt(map)
    local canvas = map:GetCanvas()
    for _, layer in ipairs({ canvas:GetChildren() }) do
        -- only the game's own art: its detail layers (they have a layer index)
        -- and the explored-area pins; not our frames, nor other pins
        if not layer.bfiOwn and (layer.layerIndex ~= nil or layer.pinTemplate == "MapExplorationPinTemplate") then
            for _, r in ipairs({ layer:GetRegions() }) do
                if r:IsObjectType("Texture") and r:IsShown() then
                    local fid = r.GetTextureFileID and r:GetTextureFileID()
                    local t = touched[r]
                    -- the game put another picture on it since: start over with that one
                    if t and fid ~= t.set then t = nil end
                    local orig = t and t.orig or fid
                    local sharp = ns.MapArtFile(orig)
                    local mode = sharp and "sharp" or "orig"
                    -- (a sharp copy to put on, or one to take off again)
                    if orig and (not t or t.mode ~= mode) and (sharp or t) then
                        Redraw(r, sharp or orig, sharp)
                        touched[r] = { orig = orig, set = r:GetTextureFileID(), mode = mode }
                        if sharp then ns.sharpTiles = (ns.sharpTiles or 0) + 1 end  -- (for /bfi check)
                    end
                end
            end
        end
    end
end

function ns.SharpenMapArt()
    local map = BattlefieldMapFrame
    if map then ns.Safe("Detail SharpenArt", SharpenArt, map) end
end

function ns.SetupDetail(map)
    local canvas = map:GetCanvas()
    host = CreateFrame("Frame", nil, canvas)
    host:SetAllPoints(canvas)
    -- placed properly (just above the explored-area art) by PlaceHost
    host:SetFrameLevel(canvas:GetFrameLevel() + 1998)
    host:Hide()
    ns.debugFrames.detail = host

    host.bfiOwn = true
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", function()
            Release()
            ns.UpdateDetail()
            -- (the game lays out the new map's art just after: sharpen it then)
            C_Timer.After(0.1, ns.SharpenMapArt)
        end)
    end
    -- the canvas resizes with the map's art on map change; lay out again then
    canvas:HookScript("OnSizeChanged", function() Release() ns.UpdateDetail() end)

    local elapsed = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 or not map:IsVisible() then return end
        elapsed = 0
        ns.UpdateDetail()
        -- (art tiles can be swapped while zooming: a cheap look every second)
        sharpenTick = (sharpenTick or 0) + 1
        if sharpenTick >= 10 then sharpenTick = 0 ns.SharpenMapArt() end
    end)
end
