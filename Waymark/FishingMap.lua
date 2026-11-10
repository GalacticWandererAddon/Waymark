local _, ns = ...

-- Fisherman's mode (ns.db.fishing): the water on the map washed by how your fishing does there,
-- like a watercolour laid on the chart: the map's own sea grain (Media\ZoneShapes\Sea.tga), tinted,
-- through each zone's outline (Media\ZoneShapes\<edition>\<zone>.tga) and its water (Media\Fishing\
-- <edition>\<zone>.blp, listed in Data\FishingWater.lua; tools\fishing_water.py traces it from the
-- zone's own map: sea, lakes and rivers, soft at the shore). Land and pins stay as they are. The
-- capitals have none (their water is painted in their stone's greys). Mockup: mockups\fishing.html.
--   sage    from the zone's level on: no fish gets away
--   ochre   up to 50 below it: some do
--   madder  further below: most do
-- On a continent's map every zone is washed; on a zone's map, that zone, but not in clear view (the
-- user, 2026-11-09: the map is see-through there, the wash would float over the world). Drawn once per map, and
-- again when your skill changes (a lure counts): nothing per frame.
--   shown   on/off (the quick panel's "Fisherman's mode"); alpha: the wash's strength
-- The zone header (ZoneName.lua) shows the level with a small ink fish, coloured the same way,
-- while the mode is on and you know Fishing (ns.FishingHeaderText).
-- Levels: Data\FishingLevels.lua. Forever's new zones aren't in it: a "Your fish got away!" there
-- is noted with your skill (ns.db.fishingLearned[zone] = the highest skill a fish got away at), so
-- the header says "Fishing 75+" (above that) instead of "?".

local function Cfg() return ns.db.fishing end

local SHAPES = ns.MEDIA .. "ZoneShapes\\"
local SEA = SHAPES .. "Sea"
local SEA_TILES = 10   -- the grain's tiles across a continent, as the zone fills have it (ZoneArt.lua)
local FISH = ns.MEDIA .. "Marks\\FishOutlined"  -- (a thin dark rim: the tint alone faded into the plate)
-- watercolours, laid thin over parchment and the game's own art alike
local TINT = {
    good = { 0.36, 0.56, 0.44 },
    some = { 0.80, 0.60, 0.26 },
    most = { 0.68, 0.30, 0.22 },
}
local CITIES = { [1453] = 1429, [1454] = 1411, [1455] = 1426, [1456] = 1412, [1457] = 1438, [1458] = 1420 }

-- Your fishing ------------------------------------------------------------------------------------

local skillCache
local function Skill()
    if skillCache ~= nil then return skillCache or nil end
    skillCache = false
    -- Forever (mainline's professions): fishing is GetProfessions' fourth; its rank and a lure's bonus
    if GetProfessions and GetProfessionInfo then
        local _, _, _, fishing = GetProfessions()
        if fishing then
            local ok, _, _, rank, _, _, _, _, mod = pcall(GetProfessionInfo, fishing)
            if ok and rank then skillCache = rank + (mod or 0) end
        end
        if skillCache then return skillCache end
    end
    local name = PROFESSIONS_FISHING or "Fishing"
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local ok, n, header, _, rank, _, mod = pcall(GetSkillLineInfo, i)
            if ok and not header and n == name and rank then
                skillCache = rank + (mod or 0)
                break
            end
        end
    end
    return skillCache or nil
end
ns.FishingSkill = Skill

local function ZoneOf(id) return CITIES[id] or id end

-- the zone's level, and whether it's learned (a floor: "75+") rather than known
function ns.FishingLevel(id)
    id = ZoneOf(id)
    local lvl = ns.FishingLevels and ns.FishingLevels[id]
    if lvl then return lvl end
    local seen = ns.db.fishingLearned and ns.db.fishingLearned[id]
    if seen then return seen + 1, true end
end

local function State(lvl, skill)
    if skill >= lvl then return "good" end
    if skill >= lvl - 50 then return "some" end
    return "most"
end

-- "<fish> 75" for the header while Fisherman's mode is on: the fish in the wash's colour for your
-- skill there, the number in the header's own text colour (a coloured number read doubled against the
-- plate's shadow, and the strong colours stood out: the user, 2026-11-09); nil if you don't fish,
-- the mode is off, or there's no water
function ns.FishingHeaderText(id)
    local skill = Skill()
    if not (skill and id and ns.IsShown("fishing")) then return end
    local lvl, floor = ns.FishingLevel(id)
    if not lvl and not ns.FishingWaterFile(id) then return end
    local c = lvl and TINT[State(lvl, skill)] or { 0.6, 0.56, 0.48 }
    local text = lvl and (floor and (lvl - 1) .. "+" or tostring(lvl)) or "?"
    -- (twice the header's text height: the user; a size in pixels, as the inline texture wants it)
    local px = 2 * ((ns.db.zoneName and ns.db.zoneName.fontSize) or 13)
    return string.format("|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t%s", FISH, px, px,
        math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255), text)
end

-- a zone's water mask, made for this client (Forever's)
local function WaterFile(zone)
    local edition = ns.MapEdition()
    local list = ns.FishingWater and ns.FishingWater[edition]
    return list and list[zone] and (ns.MEDIA .. "Fishing\\" .. edition .. "\\" .. zone) or nil
end
local function ContinentOf(id)
    local info = C_Map.GetMapInfo(id)
    local guard = 0
    while info and info.mapType ~= Enum.UIMapType.Continent and info.parentMapID and info.parentMapID > 0 and guard < 6 do
        info = C_Map.GetMapInfo(info.parentMapID)
        guard = guard + 1
    end
    return info and info.mapType == Enum.UIMapType.Continent and info.mapID or nil
end
function ns.FishingWaterFile(id) return WaterFile(ZoneOf(id)) end

-- The wash -----------------------------------------------------------------------------------------

local host
local washes = {}   -- [zone] = { frame, tex, shape mask, water mask }
local drawnFor

local function Wash(zone, shape, water)
    local w = washes[zone]
    if w then return w end
    w = { frame = CreateFrame("Frame", nil, host) }
    w.tex = w.frame:CreateTexture(nil, "ARTWORK")
    w.tex:SetTexture(SEA, "REPEAT", "REPEAT")
    w.tex:SetAllPoints(w.frame)
    w.shape = w.frame:CreateMaskTexture()
    w.shape:SetTexture(shape, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    w.shape:SetAllPoints(w.frame)
    w.tex:AddMaskTexture(w.shape)
    w.water = w.frame:CreateMaskTexture()
    w.water:SetTexture(water, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    w.water:SetAllPoints(w.frame)
    w.tex:AddMaskTexture(w.water)
    washes[zone] = w
    return w
end

local function HideAll()
    for _, w in pairs(washes) do w.frame:Hide() end
end

-- one zone's wash over (l, t)-(r, b) of the canvas (0-1); cl..cr, ct..cb: its continent's rectangle
-- there (maybe far past the canvas), so the grain lines up across zones
local function Lay(zone, cont, l, r, t, b, cl, cr, ct, cb, W, H, skill)
    local lvl = ns.FishingLevel(zone)
    local shape = ns.ZoneShapeFile and ns.ZoneShapeFile(zone)
    local water = WaterFile(zone)
    if not (lvl and shape and water) then return end
    local w = Wash(zone, shape, water)
    w.frame:ClearAllPoints()
    w.frame:SetPoint("TOPLEFT", host, "TOPLEFT", l * W, -t * H)
    w.frame:SetSize(math.max(1, (r - l) * W), math.max(1, (b - t) * H))
    -- the grain lined up across zones: tiles counted from the continent's corner
    local tw, th = (cr - cl) / SEA_TILES, (cb - ct) / SEA_TILES
    w.tex:SetTexCoord((l - cl) / tw, (r - cl) / tw, (t - ct) / th, (b - ct) / th)
    local c = TINT[State(lvl, skill)]
    w.tex:SetVertexColor(c[1], c[2], c[3], 1)
    w.frame:Show()
end

local function Draw(map)
    if not host then return end
    local c = Cfg()
    local id = map:GetMapID()
    local skill = Skill() or 0
    if not (id and c and ns.IsShown("fishing") and not ns.Perf("effects")) then
        host:Hide()
        drawnFor = nil
        return
    end
    local info = C_Map.GetMapInfo(id)
    local canvas = map:GetCanvas()
    local W, H = canvas:GetWidth(), canvas:GetHeight()
    local clear = ns.ClearView and ns.ClearView() or false
    local key = table.concat({ id, skill, W, H, tostring(clear) }, ":")
    host:SetFrameLevel(ns.ArtLevel(map, 2))
    -- (moved to 0.8 for a few minutes on 2026-11-09, then back: the wash was fine)
    if c.alphaMoved then
        if c.alpha == 0.8 then c.alpha = 0.55 end
        c.alphaMoved = nil
    end
    host:SetAlpha(c.alpha or 0.55)
    host:Show()
    if drawnFor == key then return end
    drawnFor = key
    HideAll()
    if info and info.mapType == Enum.UIMapType.Continent then
        local ok, children = pcall(C_Map.GetMapChildrenInfo, id, Enum.UIMapType.Zone)
        for _, z in ipairs(ok and children or {}) do
            if not CITIES[z.mapID] then
                local ok2, l, r, t, b = pcall(ns.MapRectOnMap, z.mapID, id)
                if ok2 and l and r > l then Lay(z.mapID, id, l, r, t, b, 0, 1, 0, 1, W, H, skill) end
            end
        end
    elseif not CITIES[id] and not clear then   -- (a capital's own map is a close-up; in clear view the
                                               -- zone's map is see-through: no wash on either)
        local zone = id
        local cont = ContinentOf(zone)
        if not cont then return end
        local ok, l, r, t, b = pcall(ns.MapRectOnMap, zone, cont)
        if not (ok and l and r > l) then return end
        -- the continent seen from this zone's map: its corners in this canvas's 0-1
        local sx, sy = 1 / (r - l), 1 / (b - t)
        Lay(zone, cont, 0, 1, 0, 1, -l * sx, (1 - l) * sx, -t * sy, (1 - t) * sy, W, H, skill)
    end
end

-- Learning a new zone's level: a fish that got away, at your skill ------------------------------

local learn = CreateFrame("Frame")
learn:RegisterEvent("UI_ERROR_MESSAGE")
learn:RegisterEvent("SKILL_LINES_CHANGED")
learn:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
learn:RegisterEvent("PLAYER_ENTERING_WORLD")
learn:SetScript("OnEvent", function(_, event, _, message)
    if event ~= "UI_ERROR_MESSAGE" then   -- (your skill may have changed: a level up, a lure, logging in)
        local before = skillCache
        skillCache = nil
        if Skill() ~= (before or nil) then
            if ns.RedrawFishing then ns.RedrawFishing() end
            if ns.UpdateZoneName then ns.UpdateZoneName() end
        end
        return
    end
    if message ~= ERR_FISH_ESCAPED then return end
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local zone = mapID and ZoneOf(mapID)
    local skill = Skill()
    if not (zone and skill) or (ns.FishingLevels and ns.FishingLevels[zone]) then return end
    ns.db.fishingLearned = ns.db.fishingLearned or {}
    if skill > (ns.db.fishingLearned[zone] or -1) then
        ns.db.fishingLearned[zone] = skill
        if ns.UpdateZoneName then ns.UpdateZoneName() end
    end
end)

BFIFishingProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)
function BFIFishingProviderMixin:RemoveAllData() end
function BFIFishingProviderMixin:RefreshAllData() ns.Safe("Fisherman's mode", Draw, self:GetMap()) end
function BFIFishingProviderMixin:OnMapChanged() self:RefreshAllData() end

function ns.SetupFishing(map)
    local canvas = map:GetCanvas()
    host = CreateFrame("Frame", nil, canvas)
    host:SetAllPoints(canvas)
    host:Hide()
    local provider = CreateFromMixins(BFIFishingProviderMixin)
    if not pcall(map.AddDataProvider, map, provider) then return end
    function ns.RedrawFishing()
        drawnFor = nil
        provider:RefreshAllData()
        if WaymarkFishingChanged then pcall(WaymarkFishingChanged) end
    end
end

-- for other addons that draw their own fishing marks (the user's Satchel): whether the mode is on,
-- and WaymarkFishingChanged (theirs, if they set it) is called when it's switched
function WaymarkFishermansMode() return ns.db and ns.IsShown("fishing") or false end
