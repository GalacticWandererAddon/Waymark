local _, ns = ...

-- Player and cursor coordinates on an edge of the Battlefield Map. Where, how
-- big and how they're backed are settings (ns.db.coords). Each has its own
-- nudge: the player's from its spot on the edge (offsetX / offsetY), the
-- cursor's from beside the player's (cursorX / cursorY).

local bar          -- the player's
local cursorBar    -- the cursor's, shown while the cursor is on the map
local baseFont, baseFlags  -- the font the text starts with, to resize it

local function Cfg() return ns.db.coords end

-- a line of text with its own dark backing, sized to the text
local function MakeBar(map)
    local b = CreateFrame("Frame", nil, map)
    b:SetSize(220, 14)
    b:SetFrameLevel((map.BorderFrame or map):GetFrameLevel() + 10)
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
    bar:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 then return end
        elapsed = 0
        Update(map)
    end)

    ns.UpdateCoords()
end

-- where: a spot on the map's top or bottom edge; side: inside the map or just
-- outside it (the bar's opposite edge against the map's)
local function Place(map)
    local c = Cfg()
    local point = c.where or "BOTTOMLEFT"
    local area = map.ScrollContainer or map
    bar:ClearAllPoints()
    local top = point:find("TOP") ~= nil
    -- (plus your nudge: offsetX right, offsetY up, in map units)
    local nx, ny = c.offsetX or 0, c.offsetY or 0
    local dx = (point:find("LEFT") and 4 or point:find("RIGHT") and -4 or 0) + nx
    if c.side == "outside" then
        local mine = top and point:gsub("TOP", "BOTTOM") or point:gsub("BOTTOM", "TOP")
        bar:SetPoint(mine, map, point, dx, (top and 4 or -4) + ny)
    else
        bar:SetPoint(point, area, point, dx, (top and -3 or 3) + ny)
    end
    -- the cursor's: beside the player's, toward the map's middle (after it
    -- on a left or middle spot, before it on a right one), plus its own nudge
    local cx, cy = c.cursorX or 0, c.cursorY or 0
    cursorBar:ClearAllPoints()
    if point:find("RIGHT") then
        cursorBar:SetPoint("RIGHT", bar, "LEFT", -12 + cx, cy)
    else
        cursorBar:SetPoint("LEFT", bar, "RIGHT", 12 + cx, cy)
    end
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
