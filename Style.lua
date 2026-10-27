local _, ns = ...

-- The map's look: its border (the game's own, or classic dialog, gold, tooltip,
-- wood, a thin line or none), and the frame opacity of the border and header.

-- A file the client has? (GetFileIDFromPath where it exists; else assume so)
local function HasFile(path)
    if not GetFileIDFromPath then return true end
    local ok, id = pcall(GetFileIDFromPath, path)
    return not ok or id ~= nil
end

-- Border ------------------------------------------------------------------

-- size: the edge's thickness at 100%; overlap: how much of it lies over the map
-- (these edge files leave the inner part of the edge see-through, so less
-- overlap leaves a gap between the map and the visible frame)
local BORDERS = {
    dialog  = { edge = "Interface\\DialogFrame\\UI-DialogBox-Border", size = 24, overlap = 0.6 },
    gold    = { edge = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", size = 24, overlap = 0.6, fallback = "dialog" },
    tooltip = { edge = "Interface\\Tooltips\\UI-Tooltip-Border", size = 14, overlap = 0.5 },
    wood    = { edge = "Interface\\AchievementFrame\\UI-Achievement-WoodBorder", size = 36, overlap = 0.55, fallback = "dialog" },
    line    = { edge = "Interface\\Buttons\\WHITE8X8", size = 1, overlap = 0 },
}
ns.BORDER_STYLES = BORDERS

local COLORS = {
    natural = { 1, 1, 1 },
    gold    = { 1, 0.82, 0.35 },
    bronze  = { 0.80, 0.55, 0.30 },
    silver  = { 0.78, 0.80, 0.86 },
    dark    = { 0.28, 0.26, 0.24 },
}

local border
local hidden = {}  -- the game's border pieces we've hidden: [region] = true
local outset       -- how far our border reaches outside the map area (nil: the game's border)

-- for the header: how far outside the map area the frame reaches (nil when it's
-- the game's own border, which sits on the map frame's edge), and the frame
-- level to stay above
function ns.BorderOutset() return outset end
function ns.BorderLevel()
    local lvl = 0
    if border and border:IsShown() then lvl = border:GetFrameLevel() end
    return lvl
end

-- the game's own border art (not its close button)
local function ShowGameBorder(map, show)
    local bf = map.BorderFrame
    if not bf then return end
    for _, r in ipairs({ bf:GetRegions() }) do
        if show and hidden[r] then
            r:SetAlpha(1)
            hidden[r] = nil
        elseif not show and r:GetAlpha() > 0 then
            r:SetAlpha(0)
            hidden[r] = true
        end
    end
    for _, child in ipairs({ bf:GetChildren() }) do
        if child ~= bf.CloseButton then
            if show and hidden[child] then
                child:SetAlpha(1)
                hidden[child] = nil
            elseif not show and child:GetAlpha() > 0 then
                child:SetAlpha(0)
                hidden[child] = true
            end
        end
    end
end

-- c: { style, color } (the map's border settings, or the header's)
local function BorderColor(c)
    if c.color == "class" then
        local _, class = UnitClass("player")
        local cc = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
        if cc then return cc.r, cc.g, cc.b end
    end
    local col = COLORS[c.color] or COLORS.natural
    if c.style == "line" and c.color == "natural" then return 0, 0, 0 end
    return col[1], col[2], col[3]
end

-- A border of one of our styles round `frame` (any frame with BackdropTemplate):
-- style, size (thickness), gap (pixels further out), color. Returns how far it
-- reaches outside the frame, or nil if the style is none or unknown.
function ns.DressBorder(edgeFrame, frame, style, size, gap, color)
    local def = BORDERS[style]
    if def and def.fallback and not HasFile(def.edge) then def = BORDERS[def.fallback] end
    if not def then
        edgeFrame:Hide()
        return nil
    end
    local px = math.max(1, math.floor(def.size * (size or 1) + 0.5))
    local out = math.max(0, math.floor(px * (1 - def.overlap) + 0.5) + (gap or 0))
    edgeFrame:SetBackdrop({ edgeFile = def.edge, edgeSize = px })
    edgeFrame:SetBackdropBorderColor(BorderColor({ style = style, color = color }))
    edgeFrame:ClearAllPoints()
    edgeFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -out, out)
    edgeFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", out, -out)
    edgeFrame:Show()
    return out
end

function ns.UpdateStyle()
    local map = BattlefieldMapFrame
    if not (border and map) then return end
    local c = ns.db.border
    local area = map.ScrollContainer or map

    local style = ns.MapBorderStyle()
    local def = BORDERS[style]
    if def and def.fallback and not HasFile(def.edge) then def = BORDERS[def.fallback] end
    ShowGameBorder(map, style == "game")
    outset = style ~= "game" and 0 or nil
    if def then
        local size = math.max(1, math.floor(def.size * (c.size or 1) + 0.5))
        -- gap: your own nudge, out from (or in over) the map
        local out = math.floor(size * (1 - def.overlap) + 0.5) + (c.gap or 0)
        outset = math.max(0, out)
        border:SetBackdrop({ edgeFile = def.edge, edgeSize = size })
        border:SetBackdropBorderColor(BorderColor({ style = style, color = c.color }))
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", area, "TOPLEFT", -out, out)
        border:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", out, -out)
        border:SetFrameLevel((map.BorderFrame or map):GetFrameLevel() + 1)
        border:Show()
    else
        border:Hide()
    end
    if ns.UpdateZoneName then ns.UpdateZoneName() end  -- the header sits on the frame's edge
    ns.ApplyFrameAlpha()
end

-- Frame opacity (ns.FrameAlpha): our border, the game's own border frame (it
-- holds the close X too) and the header. The buttons take it in their fader
-- (Options). The game sets its border frame's alpha with the map's own opacity
-- (RefreshAlpha), so this runs again after that.
function ns.ApplyFrameAlpha()
    local map = BattlefieldMapFrame
    if not (border and map) then return end
    local a = ns.FrameAlpha()
    border:SetAlpha(a)
    if map.BorderFrame then map.BorderFrame:SetAlpha(a) end
    if ns.debugFrames.header then ns.debugFrames.header:SetAlpha(a) end
end

-- Setup -----------------------------------------------------------------------

function ns.SetupStyle(map)
    border = CreateFrame("Frame", nil, map, "BackdropTemplate")
    border:Hide()

    ns.debugFrames.border = border

    map:HookScript("OnShow", ns.UpdateStyle)
    if map.RefreshAlpha then hooksecurefunc(map, "RefreshAlpha", ns.ApplyFrameAlpha) end
    ns.UpdateStyle()
end
