local _, ns = ...
local GetZonePVPInfo = GetZonePVPInfo or ns.GetZonePVPInfo

-- The header: where you are, by name (the sub-zone, or the zone where there's no
-- sub-zone), on the zone map and in caves alike. zoneName:
--   shown      on/off
--   mode       "header" above the map, "inside" at the top inside it, "below" under it
--   style      the art behind it (STYLES below)
--   font, fontSize, align, fullWidth (as wide as the map)
--   showZone   "Sentinel Hill, Westfall"; levels: the zone's level range, coloured
--              by how hard it is for you; progress: how much of the zone you've explored
--   pvpColors  the name coloured like the game's zone text (friendly, hostile...)

local function Cfg() return ns.db.zoneName end

local FRIZ = "Fonts\\FRIZQT__.TTF"  -- (the subzone's; the name's font: Fonts.lua)

local INK = { 0.20, 0.12, 0.04 }
local GOLD = { 1, 0.82, 0 }
-- a map you're not in (Browse.lua): text on dark styles, ink on paper ones,
-- the paper's tint (desaturated) and a backdrop's edge
local SILVER = { 0.86, 0.88, 0.92 }
local SILVER_INK = { 0.14, 0.15, 0.19 }
local SILVER_PAPER = { 0.82, 0.84, 0.88 }
local SILVER_EDGE = { 0.62, 0.65, 0.72 }

-- Each style: how the backing is made, the text colour, and its padding
local STYLES = {
    plate     = { text = GOLD, padX = 10 },  -- the classic dialog header plate
    stone     = { text = GOLD, padX = 16, backdrop = {
                    bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
                    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                    tile = true, tileSize = 128, edgeSize = 16,
                    insets = { left = 4, right = 4, top = 4, bottom = 4 } } },
    tan       = { text = INK, padX = 18, paper = ns.MEDIA .. "HeaderTan",
                  paperCoords = { 0, 1, 0, 1 }, backdrop = {
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } },
                  edgeColor = { 0.36, 0.25, 0.12 } },
    parchment = { text = INK, padX = 18, parchment = true, paperTint = { 0.88, 0.80, 0.67 }, backdrop = {
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } },
                  edgeColor = { 0.42, 0.30, 0.16 } },
    tooltip   = { text = GOLD, padX = 14, backdrop = {
                    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 14,
                    insets = { left = 3, right = 3, top = 3, bottom = 3 } },
                  bgColor = { 0, 0, 0, 0.85 } },
    text      = { text = GOLD, padX = 4, outline = true },
}
ns.HEADER_STYLES = STYLES

local PVP_COLORS = {
    friendly  = { 0.1, 1, 0.1 },
    hostile   = { 1, 0.1, 0.1 },
    contested = { 1, 0.7, 0 },
    sanctuary = { 0.41, 0.8, 0.94 },
    arena     = { 1, 0.1, 0.1 },
    combat    = { 1, 0.1, 0.1 },
}

local header, text, sub
local edge                -- the header's border, when not its style's own
local plate = {}          -- left, middle, right pieces of the plate style
local parchment           -- the parchment style's paper

-- Level ranges ------------------------------------------------------------------

-- the zone a map belongs to (caves and dungeons inside a zone count as that zone)
local function ZoneOf(mapID)
    local T = Enum and Enum.UIMapType
    local seen = 0
    while mapID and seen < 6 do
        local info = C_Map.GetMapInfo(mapID)
        if not info then return end
        if not T or info.mapType == T.Zone then return mapID end
        if info.mapType == T.Continent or info.mapType == T.World or info.mapType == T.Cosmic then return end
        mapID, seen = info.parentMapID, seen + 1
    end
end

function ns.LevelRange(mapID)
    if not mapID then return end
    if C_Map.GetMapLevels then
        local ok, lo, hi = pcall(C_Map.GetMapLevels, mapID)
        if ok and lo and hi and lo > 0 and hi > 0 then return lo, hi end
    end
    local r = ns.ZoneLevels and ns.ZoneLevels[mapID]
    if r then return r[1], r[2] end
end

-- "(10-20)" coloured like a quest of the range's middle level would be for you
function ns.LevelRangeText(mapID)
    local lo, hi = ns.LevelRange(mapID)
    if not lo then return end
    local mid = math.floor((lo + hi) / 2)
    local r, g, b = 1, 0.82, 0
    if GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, mid)
        if ok and c and c.r then r, g, b = c.r, c.g, c.b end
    end
    local range = lo == hi and tostring(lo) or (lo .. "-" .. hi)
    return string.format("|cff%02x%02x%02x(%s)|r", r * 255, g * 255, b * 255, range)
end

-- Text ----------------------------------------------------------------------

-- another map you're looking at (Browse.lua): its name, and a zone's levels and
-- how much you've explored of it
local function ComposeBrowsed(id)
    local c = Cfg()
    local info = C_Map.GetMapInfo(id)
    if not info then return end
    local extras = {}
    local zoneID = ZoneOf(id)
    if c.levels then
        local lv = ns.LevelRangeText(zoneID)
        if lv then extras[#extras + 1] = lv end
    end
    if c.progress and ns.ExplorationProgress then
        local pct = ns.ExplorationProgress(zoneID)
        if pct then extras[#extras + 1] = pct .. "%" end
    end
    return info.name, table.concat(extras, "  ")
end

local function Compose()
    local c = Cfg()
    -- a dungeon's floor on the map (Dungeon.lua): its name, and "(2/5)" where it has several
    local floor, counter = ns.DungeonFloorTitle and ns.DungeonFloorTitle()
    if floor then return floor, counter or "" end
    if ns.BrowsedMap and ns.BrowsedMap() then return ComposeBrowsed(ns.BrowsedMap()) end
    local zone = GetZoneText and GetZoneText() or ""
    local subzone = GetSubZoneText and GetSubZoneText() or ""
    local name = subzone ~= "" and subzone or zone
    if name == "" then return end
    -- docked over the minimap (Dock.lua): the zone with the sub-zone on the
    -- big map, never on the small square (no room); else your setting
    local showZone = c.showZone
    if ns.Docked and ns.Docked() then showZone = ns.MapIsBig and ns.MapIsBig() end
    if showZone and subzone ~= "" and zone ~= "" and subzone ~= zone then
        name = name .. ", " .. zone
    end
    local extras = {}
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local zoneID = ZoneOf(mapID)
    if c.levels then
        local lv = ns.LevelRangeText(zoneID)
        if lv then extras[#extras + 1] = lv end
    end
    if c.progress and ns.ExplorationProgress then
        local pct = ns.ExplorationProgress(zoneID)
        if pct then extras[#extras + 1] = pct .. "%" end
    end
    return name, table.concat(extras, "  ")
end

-- Layout --------------------------------------------------------------------

local function ApplyStyle()
    local c = Cfg()
    local st = STYLES[c.style] or STYLES.plate
    -- on a map you're not in (Browse.lua), silver if you like: plate, paper,
    -- edge and text
    local silver = ns.Browsing and ns.Browsing() and ns.db.browse.silver and true or false
    for _, t in pairs(plate) do
        t:SetShown(c.style == "plate")
        t:SetDesaturated(silver)
    end
    -- the paper behind the text: the map parchment's middle band, or a texture of its own
    if st.paper then
        parchment:SetTexture(st.paper)
        parchment:SetTexCoord(unpack(st.paperCoords))
    elseif st.parchment then
        parchment:SetTexture(ns.MEDIA .. "Parchment")
        parchment:SetTexCoord(0.08, 0.92, 0.38, 0.62)
    end
    -- the parchment's middle is its lightest part: darkened toward the map's own
    -- tone (the ink stays readable on it)
    local tint = silver and SILVER_PAPER or st.paperTint or { 1, 1, 1 }
    parchment:SetDesaturated(silver)
    parchment:SetVertexColor(tint[1], tint[2], tint[3])
    parchment:SetShown((st.paper or st.parchment) and true or false)
    -- the edge: the style's own ("auto"), or one of the map border's styles
    local own = c.border == nil or c.border == "auto"
    local bd = st.backdrop
    if bd and not own then
        bd = bd.bgFile and { bgFile = bd.bgFile, tile = bd.tile, tileSize = bd.tileSize, insets = bd.insets } or nil
    end
    if bd then
        header:SetBackdrop(bd)
        local bg = st.bgColor or { 1, 1, 1, 1 }
        if silver then bg = { bg[1] * 0.8, bg[2] * 0.82, bg[3] * 0.88, bg[4] } end
        if bd.bgFile then header:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]) end
        if bd.edgeFile then
            local e = silver and SILVER_EDGE or st.edgeColor or { 1, 1, 1 }
            header:SetBackdropBorderColor(e[1], e[2], e[3], 1)
        end
    else
        header:SetBackdrop(nil)
    end
    if own or not ns.DressBorder then
        edge:Hide()
    else
        ns.DressBorder(edge, header, c.border, c.borderSize, c.borderGap, silver and "silver" or c.borderColor)
    end

    local size = c.fontSize or 13
    local flags = st.outline and "OUTLINE" or ""
    ns.SetFontSafe(text, c.font, size, flags)
    sub:SetFont(FRIZ, math.max(8, size - 2), flags)
    local ink = st.text == INK
    local col = silver and (ink and SILVER_INK or SILVER) or st.text
    text:SetTextColor(col[1], col[2], col[3])
    if ink then
        sub:SetTextColor(silver and 0.25 or 0.30, silver and 0.26 or 0.22, silver and 0.30 or 0.12)
    else
        sub:SetTextColor(0.85, 0.85, 0.85)
    end
    for _, fs in ipairs({ text, sub }) do
        if ink then
            fs:SetShadowColor(1, 0.95, 0.8, 0.4)
            fs:SetShadowOffset(1, -1)
        else
            fs:SetShadowColor(0, 0, 0, 1)
            fs:SetShadowOffset(st.outline and 0 or 1, st.outline and 0 or -1)
        end
    end
end

-- Size and place: on screen the same size whatever the map's scale (the header
-- is the map's child, so it fades with it, and is scaled by 1 / the map's scale)
local function Layout(map)
    local c = Cfg()
    local st = STYLES[c.style] or STYLES.plate
    local inv = ns.AddonScale() / math.max(0.1, map:GetScale())
    header:SetScale(inv)
    local size = c.fontSize or 13
    local h = c.style == "plate" and math.floor(size * 3.1) or math.floor(size * 1.9 + 6)
    local w = text:GetStringWidth() + (sub:GetText() and sub:GetText() ~= "" and sub:GetStringWidth() + 10 or 0)
    w = w + st.padX * 2
    if c.style == "plate" then w = w + h * 1.2 end
    -- (the header's units are the map's times inv)
    if c.fullWidth then w = math.max(w, (map.ScrollContainer or map):GetWidth() / inv) end
    header:SetSize(w, h)

    -- the plate's caps are 3/4 as wide as it's tall
    plate.left:SetWidth(h * 0.75)
    plate.right:SetWidth(h * 0.75)

    -- name and extras side by side, as a line
    text:ClearAllPoints()
    sub:ClearAllPoints()
    local subW = (sub:GetText() and sub:GetText() ~= "") and (sub:GetStringWidth() + 10) or 0
    local align = c.fullWidth and c.align or "CENTER"
    local pad = st.padX + (c.style == "plate" and h * 0.6 or 0)
    local dy = c.style == "plate" and 1 or 0
    if align == "LEFT" then
        text:SetPoint("LEFT", header, "LEFT", pad, dy)
    elseif align == "RIGHT" then
        text:SetPoint("RIGHT", header, "RIGHT", -pad - subW, dy)
    else
        text:SetPoint("CENTER", header, "CENTER", -subW / 2, dy)
    end
    sub:SetPoint("LEFT", text, "RIGHT", 10, 0)

    header:ClearAllPoints()
    local area = ns.MapFace(map)  -- (collapsed: the strip that's left, Collapse.lua)
    -- the frame's outer edge: our border reaches `out` past the map area;
    -- the game's own border sits on the map frame's edge
    local out = ns.BorderOutset and ns.BorderOutset()
    local anchor = out and area or map.BorderFrame or map
    out = (out or 0) / inv  -- (in the header's units)
    -- the plate overlaps the frame's edge a little, as dialog headers do
    local overlap = c.style == "plate" and h * 0.28 or 0
    -- your nudge (offsets are in the header's own units, so they stay the same on
    -- screen at any map scale)
    local dx, dy = c.offsetX or 0, c.offsetY or 0
    if c.mode == "inside" then
        header:SetPoint("TOP", area, "TOP", dx, -2 + dy)
    elseif c.mode == "below" then
        header:SetPoint("TOP", anchor, "BOTTOM", dx, overlap - out - 2 + dy)
    else
        header:SetPoint("BOTTOM", anchor, "TOP", dx, out + 2 - overlap + dy)
    end
    -- above the map's border (the game's, its close button, and ours) and, inside
    -- the map, above its pins
    local top = (map.BorderFrame or map):GetFrameLevel()
    local close = map.BorderFrame and map.BorderFrame.CloseButton
    if close then top = math.max(top, close:GetFrameLevel()) end
    if ns.BorderLevel then top = math.max(top, ns.BorderLevel()) end
    if c.mode == "inside" then top = math.max(top, area:GetFrameLevel() + 5600) end
    header:SetFrameLevel(math.min(top + 10, 9800))
    edge:SetFrameLevel(header:GetFrameLevel() + 1)
    header.front:SetFrameLevel(header:GetFrameLevel() + 3)

    -- the hover label (Explore) goes under a header that sits inside the map
    local hl = ns.ExploreHoverLabel
    if hl then
        hl:ClearAllPoints()
        -- (in the label's own units: it's counter-scaled like the header)
        -- (from where the header's bottom really is: nudged up over the edge,
        -- it covers less of the map, or none)
        local y = -8
        if c.shown and c.mode == "inside" then y = math.min(y, -2 + dy - h - 6) end
        hl:SetScale(inv)
        hl:SetPoint("TOPLEFT", area, "TOPLEFT", 0, y)
        hl:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, y)
        hl:SetHeight(20)
    end
end

function ns.UpdateZoneName()
    local map = BattlefieldMapFrame
    if not (header and map) then return end
    local c = Cfg()
    local name, extras = Compose()
    local browsing = ns.Browsing and ns.Browsing()
    if not (ns.IsShown("zoneName") and map:IsShown() and name) then
        header:Hide()
        ns.Safe("ZoneName Layout", Layout, map)  -- (still moves the hover label back up)
        return
    end
    ApplyStyle()
    local time = ns.ClockHeaderText and ns.ClockHeaderText()
    text:SetText(time and (name .. "   " .. time) or name)
    sub:SetText(extras ~= "" and extras or nil)
    -- drag it to move the map; right-click: back to your own map (when you're looking at another)
    header:EnableMouse(true)
    if c.pvpColors and GetZonePVPInfo and not browsing and not (ns.DungeonFloorTitle and ns.DungeonFloorTitle()) then
        local pvp = GetZonePVPInfo()
        local col = PVP_COLORS[pvp or "contested"] or PVP_COLORS.contested
        text:SetTextColor(col[1], col[2], col[3])
    end
    ns.Safe("ZoneName Layout", Layout, map)
    header:Show()
end
ns.ScaleHeader = ns.UpdateZoneName

function ns.SetupZoneName(map)
    header = CreateFrame("Frame", nil, map, "BackdropTemplate")
    header:SetFrameStrata((map.BorderFrame or map):GetFrameStrata())

    -- the classic dialog header plate in three pieces, so it can grow with the name
    local PLATE = "Interface\\DialogFrame\\UI-DialogBox-Header"
    plate.left = header:CreateTexture(nil, "BACKGROUND")
    plate.left:SetTexture(PLATE)
    plate.left:SetTexCoord(0.21, 0.31, 0, 0.63)
    plate.left:SetPoint("TOPLEFT")
    plate.left:SetPoint("BOTTOMLEFT")
    plate.right = header:CreateTexture(nil, "BACKGROUND")
    plate.right:SetTexture(PLATE)
    plate.right:SetTexCoord(0.67, 0.77, 0, 0.63)
    plate.right:SetPoint("TOPRIGHT")
    plate.right:SetPoint("BOTTOMRIGHT")
    plate.middle = header:CreateTexture(nil, "BACKGROUND")
    plate.middle:SetTexture(PLATE)
    plate.middle:SetTexCoord(0.31, 0.67, 0, 0.63)
    plate.middle:SetPoint("TOPLEFT", plate.left, "TOPRIGHT")
    plate.middle:SetPoint("BOTTOMRIGHT", plate.right, "BOTTOMLEFT")

    -- the parchment style's paper: a band from the middle of the map parchment
    parchment = header:CreateTexture(nil, "BACKGROUND", nil, -1)
    parchment:SetTexture(ns.MEDIA .. "Parchment")
    parchment:SetTexCoord(0.08, 0.92, 0.38, 0.62)
    parchment:SetPoint("TOPLEFT", 3, -3)
    parchment:SetPoint("BOTTOMRIGHT", -3, 3)

    edge = CreateFrame("Frame", nil, header, "BackdropTemplate")
    edge:Hide()
    ns.debugFrames.header, ns.debugFrames.headerBorder = header, edge

    -- the text on a frame of its own above the edge, so a thick border can't cover it
    local front = CreateFrame("Frame", nil, header)
    front:SetAllPoints()
    front:SetFrameLevel(header:GetFrameLevel() + 3)
    header.front = front
    text = front:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sub = front:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:Hide()
    ns.ZoneHeader = header

    -- drag: move the map (MapControls.lua); right-click: the map's menu (big map, dock,
    -- frame settings, fold), in words for the state it's in; middle-click: back to your
    -- own map from another (Browse.lua) or a dungeon opened from its entrance (Dungeon.lua)
    local function Away()
        return (ns.Browsing and ns.Browsing()) or (ns.DungeonPreviewing and ns.DungeonPreviewing())
    end
    header:EnableMouse(false)
    header:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and ns.MapMoveStart then ns.MapMoveStart() end
    end)
    header:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            if ns.MapMoveStop then ns.MapMoveStop() end
        elseif button == "MiddleButton" and Away() then
            if ns.DungeonPreviewing and ns.DungeonPreviewing() and ns.EndDungeonPreview then ns.EndDungeonPreview() end
            if ns.Browsing and ns.Browsing() and ns.BrowseHome then ns.BrowseHome() end
        elseif button == "RightButton" and ns.QuillMenu then
            ns.MapFrameMenu()
        end
    end)
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        ns.Hints({ not ns.db.mapFrame.locked and { "Drag", "move the map" } or nil, { "Right-click", "the map's menu" },
                   Away() and { "Middle-click", "back to " .. (ns.HomeMapName and ns.HomeMapName() or "your map") } or nil })
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function() GameTooltip:Hide() end)
    header:HookScript("OnHide", function() if ns.MapMoveStop then ns.MapMoveStop() end end)  -- (no move left hanging)

    local events = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
                         "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP" }) do
        events:RegisterEvent(e)
    end
    events:SetScript("OnEvent", ns.UpdateZoneName)
    map:HookScript("OnShow", ns.UpdateZoneName)
    map:HookScript("OnHide", ns.UpdateZoneName)
    ns.UpdateZoneName()
end

-- the map frame's own menu: its header's, and the docked square's rim
function ns.MapFrameMenu()
    GameTooltip:Hide()
    local docked = ns.Docked and ns.Docked()
    local items = {
        { (ns.MapIsBig and ns.MapIsBig()) and "normal size" or "big map",
          function() if ns.ToggleBigMap then ns.ToggleBigMap() end end },
        { docked and "undock from the minimap" or "dock to the minimap",
          function() if ns.ToggleDock then ns.ToggleDock() end end },
        { "frame settings", function() if ns.ShowOption then ns.ShowOption("border", "style") end end },
        { ns.db.mapFrame.locked and "unlock the map" or "lock the map in place",
          function() if ns.ToggleMapLock then ns.ToggleMapLock() end end },
    }
    if docked and ns.DockHasSpot and ns.DockHasSpot() then
        items[#items + 1] = { "back to the minimap's spot", ns.DockSpotReset }
    end
    -- (folding is the window's: not over the minimap)
    if not docked and ns.ToggleCollapse then
        items[#items + 1] = { (ns.MapFolded and ns.MapFolded()) and "unfold the map" or "fold the map", ns.ToggleCollapse }
    end
    ns.QuillMenu(items)
end
