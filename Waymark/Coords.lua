local _, ns = ...

-- Player and cursor coordinates on an edge of the Battlefield Map. Where, how
-- big and how they're backed are settings (ns.db.coords). Each is placed on its
-- own: the player's at its spot (where, side) plus its nudge (offsetX / offsetY);
-- the cursor's beside the player's or at a spot of its own (cursorWhere,
-- cursorSide) plus its nudge (cursorX / cursorY).

local bar          -- the player's
local cursorBar    -- the cursor's, shown while the cursor is on the map
local baseFont, baseFlags  -- the font the text starts with, to resize it

local function Cfg() return ns.db.coords end

-- a line of text with its own dark backing, sized to the text
local function MakeBar(map)
    local b = CreateFrame("Frame", nil, map)
    b:SetSize(220, 14)
    b:SetFrameLevel(ns.ButtonLevel(map))  -- (over the dungeon map and cave view too)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetPoint("TOPLEFT", -3, 1)
    b.bg:SetPoint("BOTTOMRIGHT", 3, -1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    hooksecurefunc(b.text, "SetText", function(fs)
        b:SetWidth(math.max(20, fs:GetStringWidth() + 2))
    end)
    return b
end

local function Update(map)
    local mapID = map:GetMapID()
    local player = "--"
    if mapID and C_Map and C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")  -- nil in instances
        if pos and pos.x and (pos.x > 0 or pos.y > 0) then
            player = string.format("%.1f, %.1f", pos.x * 100, pos.y * 100)
        end
    end

    local cursor
    if map:IsMouseOver() and map.GetNormalizedCursorPosition then
        local ok, cx, cy = pcall(map.GetNormalizedCursorPosition, map)
        if ok and cx and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
            cursor = string.format("Cursor %.1f, %.1f", cx * 100, cy * 100)
        end
    end

    bar.text:SetText("Player " .. player)
    cursorBar:SetShown(cursor ~= nil and bar:IsShown())
    if cursor then cursorBar.text:SetText(cursor) end
end

function ns.SetupCoords(map)
    bar = MakeBar(map)
    cursorBar = MakeBar(map)
    ns.debugFrames.coords, ns.debugFrames.coordsCursor = bar, cursorBar
    cursorBar:Hide()
    baseFont, _, baseFlags = bar.text:GetFont()

    local elapsed = 0
    bar:SetScript("OnUpdate", ns.Timed("Coords tick", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 then return end
        elapsed = 0
        Update(map)
    end))

    ns.UpdateCoords()
end

-- point: a spot on the map's top or bottom edge; side: inside the map or just
-- outside it (the bar's opposite edge against the map's); nx, ny: the nudge
-- (right, up, in map units)
local function Anchor(b, map, point, side, nx, ny)
    local area = map.ScrollContainer or map
    b:ClearAllPoints()
    local top = point:find("TOP") ~= nil
    local dx = (point:find("LEFT") and 4 or point:find("RIGHT") and -4 or 0) + nx
    if side == "outside" then
        local mine = top and point:gsub("TOP", "BOTTOM") or point:gsub("BOTTOM", "TOP")
        b:SetPoint(mine, map, point, dx, (top and 4 or -4) + ny)
    else
        -- (clear of a soft edge's fade)
        local ix, iy = 0, 0
        if ns.SoftEdgeInset then ix, iy = ns.SoftEdgeInset() end
        dx = dx + (point:find("LEFT") and ix or point:find("RIGHT") and -ix or 0)
        b:SetPoint(point, area, point, dx, (top and -3 - iy or 3 + iy) + ny)
    end
end

local function Place(map)
    local c = Cfg()
    local point = c.where or "BOTTOMLEFT"
    Anchor(bar, map, point, c.side, c.offsetX or 0, c.offsetY or 0)
    local cx, cy = c.cursorX or 0, c.cursorY or 0
    local spot = c.cursorWhere or "beside"
    if spot ~= "beside" then
        -- (a spot of its own: the player's moving leaves it where it is)
        local side = (c.cursorSide == "inside" or c.cursorSide == "outside") and c.cursorSide or c.side
        Anchor(cursorBar, map, spot, side, cx, cy)
        return
    end
    -- beside the player's, toward the map's middle (after it on a left or middle
    -- spot, before it on a right one), plus its own nudge
    cursorBar:ClearAllPoints()
    if point:find("RIGHT") then
        cursorBar:SetPoint("RIGHT", bar, "LEFT", -12 + cx, cy)
    else
        cursorBar:SetPoint("LEFT", bar, "RIGHT", 12 + cx, cy)
    end
end

-- how far a button in the map's bottom-left corner goes up to clear the coordinates (Dungeon.lua and
-- Cave.lua's brass switch)
function ns.CoordsCornerLift()
    local c = ns.db and ns.db.coords
    if not (c and ns.IsShown("coords") and c.side ~= "outside" and (c.where or "BOTTOMLEFT") == "BOTTOMLEFT") then return 0 end
    return (c.size or 10) + 6
end

function ns.UpdateCoords()
    if not bar then return end
    local c = Cfg()
    bar:SetShown(ns.IsShown("coords"))
    local map = bar:GetParent()
    Place(map)
    if not ns.IsShown("coords") then cursorBar:Hide() end
    local size = c.size or 10
    local col = c.color or { 1, 1, 1 }
    for _, b in ipairs({ bar, cursorBar }) do
        if baseFont then b.text:SetFont(baseFont, size, c.outline and "OUTLINE" or (baseFlags or "")) end
        b:SetHeight(size + 4)
        b.text:SetTextColor(col[1], col[2], col[3])
        b.bg:SetColorTexture(0, 0, 0, (c.backing or 50) / 100)
        -- the text's own drop shadow
        if c.shadow ~= false then
            b.text:SetShadowColor(0, 0, 0, 1)
            b.text:SetShadowOffset(1, -1)
        else
            b.text:SetShadowOffset(0, 0)
        end
        b.text:SetText(b.text:GetText() or "")  -- (re-measure the backing)
    end
end
