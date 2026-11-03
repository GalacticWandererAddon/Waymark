local _, ns = ...

-- Rares and treasure chests on a zone map, from our own data (Data\WorldQuests.lua's
-- rares and chests; mock-up mockups\world-extras.html 1-2). Settings ns.db.wilds:
--   shown; rares, elites (rare elites); treasure (chest spots, off at first: a
--   busy zone has dozens); paths: a rare's patrol path while
--   hovered; size (px); bossLoot: "what they carry" in boss menus (BossLoot.lua)
-- Drawn as plain textures on one frame over the map that takes no mouse, like
-- quest ground: hovering is a distance check, and the tooltip names the rare, its
-- level and its own drops with their chances (best first, greys left out by the
-- tool). Redrawn only when the map, the settings or the zoom change. A zone has
-- a handful of rares and a few dozen chest spots at most.

-- overworld chest spots: off for 1.2 (they didn't show; true brings them and their
-- setting back, Options.lua)
local TREASURE = false
ns.WILDS_TREASURE = TREASURE

local MEDIA = ns.MEDIA
local BRUSH = MEDIA .. "InkRim"
local DOT = MEDIA .. "InkDot"
-- a rare's mark (the setting look): "coin", the game's vignette markers (on Forever a dark
-- coin with a white star; Era's is a plain gold star), or "dragon", the classic rare frames:
-- the silver dragon for a rare, the gold for a rare elite. Unset: the coin on Forever, the
-- dragons on Era. Each with fallbacks; a chest spot is a small faint dot. A dot is
-- { r, g, b, a, size (of the setting) }
local ATLAS = {
    coin = {
        rare = { "vignettekill", "VignetteKill" },
        elite = { "vignettekillelite", "VignetteKillElite", "vignettekill" },
    },
    dragon = {
        rare = { "nameplates-icon-elite-silver", "VignetteKill", "vignettekill" },
        elite = { "nameplates-icon-elite-gold", "VignetteKillElite", "VignetteKill" },
    },
}
local CHEST_DOT = { 0.42, 0.26, 0.10, 0.55, 0.35 }
local SHOWN_DROPS = 5
local MANY = 4            -- a rare with more spots than this on a map: one mark, its spots on hover

local function Cfg() return ns.db.wilds end
local function Look()
    local l = Cfg().look
    return ATLAS[l] and l or (ns.FOREVER and "coin" or "dragon")
end

local host, map, pathHost
local icons, nIcons, lines, nLines = {}, 0, {}, 0
local drawn = {}   -- { x, y, kind, id, row } for the hover

local function Dot(x, y, size, r, g, b, a, layer)
    nIcons = nIcons + 1
    local t = icons[nIcons]
    if not t then
        t = host:CreateTexture(nil, "OVERLAY")
        icons[nIcons] = t
    end
    t:SetTexture(DOT)  -- (the pool's textures may have worn an atlas)
    t:SetTexCoord(0, 1, 0, 1)
    t:SetDrawLayer("OVERLAY", layer)
    t:SetVertexColor(r, g, b, a)
    t:SetSize(size, size)
    t:ClearAllPoints()
    t:SetPoint("CENTER", host, "TOPLEFT", x, -y)
    t:Show()
end

local atlasOf = {}  -- look .. kind: the first of its atlas names this client has
local function Icon(kind, x, y, size)
    if kind == "chest" then
        local m = CHEST_DOT
        return Dot(x, y, size * m[5], m[1], m[2], m[3], m[4], 2)
    end
    local look = Look()
    local key = look .. kind
    if atlasOf[key] == nil then
        atlasOf[key] = false
        for _, name in ipairs(ATLAS[look][kind]) do
            if not (C_Texture and C_Texture.GetAtlasInfo) or C_Texture.GetAtlasInfo(name) then
                atlasOf[key] = name
                break
            end
        end
    end
    Dot(x, y, size, 1, 1, 1, 1, 2)
    local t = icons[nIcons]
    if not (atlasOf[key] and t:SetAtlas(atlasOf[key]) ~= false) then
        t:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    end
    t:SetSize(size, size)  -- (SetAtlas may size it to the atlas)
end

local function Clear()
    for i = 1, nIcons do icons[i]:Hide() end
    nIcons = 0
    wipe(drawn)
end

local spots, nSpots = {}, 0   -- (a many-spot rare's spots, while hovered)
local function ClearPath()
    for i = 1, nLines do lines[i]:Hide() end
    for i = 1, nSpots do spots[i]:Hide() end
    nLines, nSpots = 0, 0
end

-- every spot a many-spot rare may stand at, faint, while its mark is hovered
local function DrawSpots(pts)
    local W, H = host:GetWidth(), host:GetHeight()
    local size = (Cfg().size or 16) * 0.35 * UIParent:GetEffectiveScale() / math.max(0.01, host:GetEffectiveScale())
    for _, p in ipairs(pts) do
        nSpots = nSpots + 1
        local t = spots[nSpots]
        if not t then
            t = pathHost:CreateTexture(nil, "ARTWORK")
            t:SetTexture(DOT)
            spots[nSpots] = t
        end
        t:SetVertexColor(0.32, 0.08, 0.05, 0.6)
        t:SetSize(size, size)
        t:ClearAllPoints()
        t:SetPoint("CENTER", pathHost, "TOPLEFT", p[1] * W, -p[2] * H)
        t:Show()
    end
end

-- a rare's path, dashed (every other piece), while it's hovered
local function DrawPath(row)
    local c = Cfg()
    if not (c.paths and row[6]) then return end
    local data = ns.OwnQuestDB and ns.OwnQuestDB()
    local area, pts = data.Wilds.Path(row[6])
    if not (area and pts and #pts > 1) then return end
    local mapID, onMap = map:GetMapID(), false
    ns.EachSpawnOnMap({ [area] = { pts[1] } }, function(m) onMap = onMap or m == mapID end)
    if not onMap then return end
    local W, H = host:GetWidth(), host:GetHeight()
    local scale = UIParent:GetEffectiveScale() / math.max(0.01, host:GetEffectiveScale())
    for i = 2, #pts do
        if i % 2 == 0 then
            local a, b = pts[i - 1], pts[i]
            do
                nLines = nLines + 1
                local l = lines[nLines]
                if not l then
                    l = pathHost:CreateLine(nil, "ARTWORK")
                    l:SetTexture(BRUSH)
                    lines[nLines] = l
                end
                l:SetVertexColor(0.23, 0.16, 0.07, 0.85)
                l:SetThickness(2 * scale)
                l:SetStartPoint("TOPLEFT", pathHost, a[1] / 100 * W, -a[2] / 100 * H)
                l:SetEndPoint("TOPLEFT", pathHost, b[1] / 100 * W, -b[2] / 100 * H)
                l:Show()
            end
        end
    end
end

local function Draw()
    Clear()
    ClearPath()
    local c = Cfg()
    local mapID = map:GetMapID()
    local data = ns.OwnQuestDB and ns.OwnQuestDB()
    if not (c and ns.IsShown("wilds") and mapID and data and data.Wilds) then host:Hide() return end
    local canvas = map:GetCanvas()
    local W, H = canvas:GetWidth(), canvas:GetHeight()
    if not (W and W > 0 and H > 0) then return end
    host:SetParent(canvas)
    host:SetAllPoints(canvas)
    host:SetFrameLevel(ns.ArtLevel and ns.ArtLevel(map, 7) or canvas:GetFrameLevel() + 2)
    host:Show()
    pathHost:SetParent(canvas)
    pathHost:SetAllPoints(canvas)
    pathHost:SetFrameLevel(host:GetFrameLevel())
    pathHost:Show()
    local size = (c.size or 16) * UIParent:GetEffectiveScale() / math.max(0.01, host:GetEffectiveScale())
    local w = data.Wilds
    -- (a rare with many spots it may stand at, Foe Reaper 4000's 41: one mark, at
    -- the spot nearest their middle; hovering it shows them all, faint)
    local function Put(kind, id, row, spawns)
        local pts = {}
        ns.EachSpawnOnMap(w.Spawns(spawns), function(m, x, y)
            if m == mapID then pts[#pts + 1] = { x, y } end
        end)
        if kind ~= "chest" and #pts > MANY then
            local cx, cy = 0, 0
            for _, p in ipairs(pts) do cx, cy = cx + p[1] / #pts, cy + p[2] / #pts end
            local best, bd
            for _, p in ipairs(pts) do
                local d = (p[1] - cx) ^ 2 + (p[2] - cy) ^ 2
                if not bd or d < bd then best, bd = p, d end
            end
            Icon(kind, best[1] * W, best[2] * H, size)
            drawn[#drawn + 1] = { best[1], best[2], kind, id, row, #pts, pts }
            return
        end
        for _, p in ipairs(pts) do
            Icon(kind, p[1] * W, p[2] * H, size)
            drawn[#drawn + 1] = { p[1], p[2], kind, id, row, #pts }
        end
    end
    if TREASURE and c.treasure then
        for id, row in pairs(w.chests) do Put("chest", id, row, row[2]) end
    end
    for id, row in pairs(w.rares) do
        local elite = row[4] == 2
        if (elite and c.elites) or (not elite and c.rares) then Put(elite and "elite" or "rare", id, row, row[5]) end
    end
end

-- Hover -------------------------------------------------------------------------

local tipShown, tipKey, pathFor
local function Quality(item)
    local _, _, q = GetItemInfo(item)
    if not q and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, item) end
    if q and GetItemQualityColor then return GetItemQualityColor(q) end
    return 1, 1, 1
end

local function Hover()
    local over = host:IsVisible() and #drawn > 0 and map.ScrollContainer and map.ScrollContainer:IsMouseOver()
    local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
    if owner and owner ~= host then tipShown = false return end   -- (a pin's tooltip)
    local hit
    if over then
        local x, y = map:GetNormalizedCursorPosition()
        local W, H = host:GetWidth(), host:GetHeight()
        local r = (Cfg().size or 16) * 0.6 * UIParent:GetEffectiveScale() / math.max(0.01, host:GetEffectiveScale())
        local best
        for _, d in ipairs(drawn) do
            local dx, dy = (d[1] - x) * W, (d[2] - y) * H
            local dd = dx * dx + dy * dy
            if dd < r * r and (not best or dd < best) then hit, best = d, dd end
        end
    end
    if not hit then
        if tipShown and owner == host then GameTooltip:Hide() end
        if pathFor then ClearPath() pathFor = nil end
        tipShown = false
        return
    end
    local shift = IsShiftKeyDown()
    local key = hit[3] .. hit[4] .. (shift and "+shift" or "")   -- (Shift shows the drops)
    if tipShown and owner == host and key == tipKey then return end
    tipKey = key
    local row = hit[5]
    GameTooltip:SetOwner(host, "ANCHOR_CURSOR_RIGHT", 12, 12)
    if hit[3] == "chest" then
        local n = 0
        for _, d in ipairs(drawn) do if d[4] == hit[4] then n = n + 1 end end
        GameTooltip:AddLine(row[1], 1, 1, 1)
        GameTooltip:AddLine(n > 1 and string.format("May stand at one of %d spots here", n) or "May stand here",
            0.6, 0.6, 0.6)
        if pathFor then ClearPath() pathFor = nil end
    else
        local level = row[2] == row[3] and tostring(row[2]) or (row[2] .. "-" .. row[3])
        GameTooltip:AddDoubleLine(row[1], hit[3] == "elite" and "Rare Elite" or "Rare", 1, 1, 1, 0.6, 0.6, 0.6)
        -- (its drops only while Shift is held, "(Hold Shift)" until then, as our other tooltips)
        local drops, chances = row[7] or {}, row[8] or {}
        GameTooltip:AddDoubleLine("Level " .. level .. (row[6] and ", walks a path" or "")
            .. (hit[6] > 1 and string.format(", one of %d spots", hit[6]) or ""),
            (drops[1] and not shift) and "(Hold Shift)" or "", 0.6, 0.6, 0.6, 0.43, 0.43, 0.43)
        if drops[1] and shift then GameTooltip:AddLine(" ") end
        local data = ns.OwnQuestDB()
        for i = 1, shift and math.min(SHOWN_DROPS, #drops) or 0 do
            local r, g, b = Quality(drops[i])
            GameTooltip:AddDoubleLine(data.Item.name(drops[i]) or ("Item " .. drops[i]),
                ns.ChanceText and ns.ChanceText(chances[i]) or "", r, g, b, 1, 1, 1)
        end
        if pathFor ~= hit[4] then
            ClearPath()
            DrawPath(row)
            if hit[7] then DrawSpots(hit[7]) end
            pathFor = hit[4]
        end
    end
    GameTooltip:Show()
    tipShown = true
end

-- Setup --------------------------------------------------------------------------

local function Signature()
    local c = Cfg()
    local canvas = map:GetCanvas()
    return table.concat({ tostring(map:GetMapID()), tostring(ns.IsShown("wilds")), tostring(c.rares), tostring(c.elites),
        tostring(c.treasure), tostring(c.size), Look(), tostring(math.floor(canvas:GetWidth() + 0.5)),
        string.format("%.3f", host:GetEffectiveScale()) }, ":")
end

function ns.SetupWilds(m)
    map = m
    host = CreateFrame("Frame", nil, map:GetCanvas())
    host:EnableMouse(false)
    host:Hide()
    pathHost = CreateFrame("Frame", nil, map:GetCanvas())
    pathHost:EnableMouse(false)
    local last, t = nil, 0
    local ticker = ns.TimedFrame and ns.TimedFrame("Wilds tick", map) or CreateFrame("Frame", nil, map)
    ticker:SetScript("OnUpdate", function(_, e)
        t = t + e
        if t < 0.1 then return end
        t = 0
        if not ns.db then return end
        local ok, sig = pcall(Signature)
        if ok and sig ~= last then
            last = sig
            local okD, err = pcall(Draw)
            if not okD then ns.Log("Rares & chests:", tostring(err)) end
        end
        pcall(Hover)
    end)
    -- (for /bfi check)
    function ns.WildsInfo()
        return string.format("%d rares and chest spots drawn, %d textures", #drawn, nIcons)
    end
end
