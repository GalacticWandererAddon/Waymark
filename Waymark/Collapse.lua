local _, ns = ...

-- Collapsing the map: the map picture folds up under the header, leaving only
-- the upper frame; the buttons, coordinates and resize grip hide with it. An
-- attached quest tracker stays (below the map it rides up under the strip). By
-- key (BFI_COLLAPSE) and/or in combat (collapse.combat: open again when the
-- fight ends, unless you'd collapsed it yourself before). Not kept over a reload.
--
-- The border, the header and the tracker hang off the map's face (ns.MapFace):
-- a frame over the map area, as tall as it, or as the strip while collapsed.

local FOLD_TIME = 0.25  -- seconds
local STRIP = 1         -- what's left of the map area, in map units

local function Cfg() return ns.db.collapse end

local face
local collapsed      -- folded or folding away
local byCombat       -- folded because a fight started
local frac = 0       -- 0: open, 1: folded
local held = {}      -- the buttons we've hidden: [frame] = true
local hooked = {}
local hiding         -- (our own Hide calls)
local gamePoints     -- the game border's own anchors, while it follows the face
local baseInsets     -- the map's own hit box insets, while collapsed
local anim = CreateFrame("Frame")

function ns.MapFace(map)
    local sc = map.ScrollContainer
    if not sc then return map end
    if not face then
        face = CreateFrame("Frame", nil, map)
        face:SetPoint("TOPLEFT", sc, "TOPLEFT")
        face:SetPoint("TOPRIGHT", sc, "TOPRIGHT")
        face:SetPoint("BOTTOM", sc, "BOTTOM")
    end
    return face
end

function ns.MapCollapsed() return collapsed and true or false end

-- how much of the map's bottom catches no mouse while collapsed (MouseOnMap)
function ns.CollapsedInset() return baseInsets and baseInsets.bottom or 0 end

-- the strip: nothing of the map area left, so the border's top and bottom
-- edges meet and only the upper frame shows (a header inside the map hangs
-- below it)
local function StripHeight()
    return STRIP
end

-- The border folded flat: its corners and side edges stand up as little caps
-- at the ends (the game's own: and the socket round the X), so only its top
-- edge stays, stretched corner to corner.
-- Ours: the backdrop's pieces, which BackdropTemplateMixin keeps by name.
local TRIM = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
               "LeftEdge", "RightEdge", "BottomEdge", "Center" }
-- The game's: its border frame's pieces (not the X), the top edge by its name
-- (Top..., not a corner), else any piece along the top at least half as wide
local trimmed    -- [piece] = { alpha } or { points, height } while folded
ns.collapseTrim = nil  -- (what was kept, for /bfi check)

local function GamePieces(bf)
    local list, names = {}, {}
    local function Add(f)
        for k, v in pairs(f) do
            if type(k) == "string" and type(v) == "table" then names[v] = k end
        end
        for _, r in ipairs({ f:GetRegions() }) do list[#list + 1] = r end
    end
    Add(bf)
    for _, c in ipairs({ bf:GetChildren() }) do
        if c ~= bf.CloseButton then Add(c) end
    end
    local tops = {}
    for _, r in ipairs(list) do
        local k = names[r]
        if r:IsObjectType("Texture") and k and k:find("Top") and not (k:find("Left") or k:find("Right")
                                                                     or k:find("Corner")) then
            tops[r] = k
        end
    end
    if not next(tops) then
        for _, r in ipairs(list) do
            if r:IsObjectType("Texture") and r:GetTop() and bf:GetTop() and math.abs(r:GetTop() - bf:GetTop()) <= 4
               and r:GetWidth() >= bf:GetWidth() / 2 then
                tops[r] = names[r] or "?"
            end
        end
    end
    return list, tops
end

local function Pieces(b, game)
    if game then return GamePieces(b) end
    local list, tops = {}, {}
    for _, k in ipairs(TRIM) do list[#list + 1] = b[k] end
    if b.TopEdge then
        list[#list + 1] = b.TopEdge
        tops[b.TopEdge] = "TopEdge"
    end
    return list, tops
end

local function TrimBorder(map, on)
    if (trimmed ~= nil) == on then return end
    if not on then
        for r, t in pairs(trimmed) do
            if t.points then
                r:ClearAllPoints()
                for _, p in ipairs(t.points) do r:SetPoint(unpack(p)) end
                r:SetHeight(t.height)
            else
                r:SetAlpha(t.alpha)
            end
        end
        trimmed = nil
        return
    end
    local game = ns.BorderOutset() == nil
    local b = game and map.BorderFrame or ns.debugFrames.border
    if not b then return end
    trimmed = {}
    local list, tops = Pieces(b, game)
    local kept = {}
    for _, r in ipairs(list) do
        if tops[r] and r:GetTop() and b:GetTop() then
            local t = { points = {}, height = r:GetHeight() }
            for i = 1, r:GetNumPoints() do t.points[i] = { r:GetPoint(i) } end
            local dy = r:GetTop() - b:GetTop()
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", b, "TOPLEFT", 0, dy)
            r:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, dy)
            r:SetHeight(t.height)
            trimmed[r] = t
            kept[#kept + 1] = tops[r]
        elseif not tops[r] then
            trimmed[r] = { alpha = r:GetAlpha() }
            r:SetAlpha(0)
        end
    end
    ns.collapseTrim = (game and "game border" or "our border") .. ", kept: "
        .. (#kept > 0 and table.concat(kept, ", ") or "none") .. ", hid " .. (#list - #kept)
end

local function SetFrac(map, f)
    frac = f
    TrimBorder(map, f >= 0.9)  -- (just before the corners meet)
    local sc = map.ScrollContainer
    face:ClearAllPoints()
    face:SetPoint("TOPLEFT", sc, "TOPLEFT")
    face:SetPoint("TOPRIGHT", sc, "TOPRIGHT")
    if f <= 0 then
        face:SetPoint("BOTTOM", sc, "BOTTOM")
    else
        local e = f * f * (3 - 2 * f)  -- slow start, slow finish
        local full = sc:GetHeight()
        face:SetHeight(math.max(1, full + (StripHeight() - full) * e))
    end
    sc:SetAlpha(math.max(0, 1 - f * 2))  -- (the picture's gone by half way)
end

-- The game's own border sits on the map frame's edge, not the face: while
-- collapsed its bottom follows the face, kept as far below it as it was
local function HoldGameBorder(map, on)
    local bf = map.BorderFrame
    if not bf then return end
    if on and not gamePoints and ns.BorderOutset() == nil and bf:GetLeft() then
        local sc = map.ScrollContainer
        local l, t = bf:GetLeft() - map:GetLeft(), bf:GetTop() - map:GetTop()
        local r, b = bf:GetRight() - sc:GetRight(), bf:GetBottom() - sc:GetBottom()
        gamePoints = {}
        for i = 1, bf:GetNumPoints() do gamePoints[i] = { bf:GetPoint(i) } end
        bf:ClearAllPoints()
        bf:SetPoint("TOPLEFT", map, "TOPLEFT", l, t)
        bf:SetPoint("BOTTOMRIGHT", face, "BOTTOMRIGHT", r, b)
    elseif not on and gamePoints then
        bf:ClearAllPoints()
        for _, p in ipairs(gamePoints) do bf:SetPoint(unpack(p)) end
        gamePoints = nil
    end
end

-- the empty space where the map was catches no clicks
local function SetHitBox(map, on)
    if on then
        local fb, mb = face:GetBottom(), map:GetBottom()
        if not (fb and mb) then return end
        if not baseInsets then
            local l, r, t, b = map:GetHitRectInsets()
            baseInsets = { l, r, t, b, bottom = 0 }
        end
        local i = baseInsets
        i.bottom = math.max(i[4], fb - (ns.BorderOutset() or 0) - mb)
        map:SetHitRectInsets(i[1], i[2], i[3], i.bottom)
    elseif baseInsets then
        map:SetHitRectInsets(baseInsets[1], baseInsets[2], baseInsets[3], baseInsets[4])
        baseInsets = nil
    end
end

-- Buttons ---------------------------------------------------------------------

local function Buttons(map)
    local d, list = ns.debugFrames, {}
    for _, k in ipairs({ "gear", "townButton", "cityButton", "dockButton", "toggleStrip", "bigMap", "grip", "coords",
                         "coordsCursor", "clock", "searchButton", "searchBar" }) do
        if d[k] and not (k == "clock" and ns.ClockFree and ns.ClockFree()) then list[#list + 1] = d[k] end
    end
    local close = map.BorderFrame and map.BorderFrame.CloseButton
    if close then list[#list + 1] = close end
    return list
end

-- a button its own code shows while collapsed goes again; one it hides (or
-- shows and hides) stays hidden when the map opens
local function Hook(f)
    if hooked[f] then return end
    hooked[f] = true
    f:HookScript("OnShow", function(self)
        if not collapsed or hiding then return end
        held[self] = true
        hiding = true
        self:Hide()
        hiding = nil
    end)
    hooksecurefunc(f, "Hide", function(self) if not hiding then held[self] = nil end end)
    hooksecurefunc(f, "SetShown", function(self, on) if not (hiding or on) then held[self] = nil end end)
end

local function HideButtons(map)
    hiding = true
    for _, f in ipairs(Buttons(map)) do
        Hook(f)
        if f:IsShown() then
            held[f] = true
            f:Hide()
        end
    end
    hiding = nil
    if ns.HideQuickPanel then ns.HideQuickPanel() end
end

local function ShowButtons()
    hiding = true
    for f in pairs(held) do f:Show() end
    hiding = nil
    wipe(held)
end

-- Folding ---------------------------------------------------------------------

local function Done(map)
    anim:SetScript("OnUpdate", nil)
    if collapsed then
        map.ScrollContainer:Hide()
        SetHitBox(map, true)
    else
        HoldGameBorder(map, false)
        ShowButtons()
    end
end

local function Fold(map, on, instant)
    if not (map and map.ScrollContainer) then return end
    ns.MapFace(map)
    if (collapsed and true or false) == on then return end
    collapsed = on
    if on then
        HoldGameBorder(map, true)
        HideButtons(map)
    else
        SetHitBox(map, false)
        map.ScrollContainer:Show()
    end
    local to = on and 1 or 0
    if instant or not map:IsVisible() then
        SetFrac(map, to)
        Done(map)
        return
    end
    anim:SetScript("OnUpdate", function(_, dt)
        local step = dt / FOLD_TIME
        local f = on and math.min(1, frac + step) or math.max(0, frac - step)
        ns.Safe("Collapse SetFrac", SetFrac, map, f)
        if f == to then Done(map) end
    end)
end

-- folded up under its header now (the header's menu says fold or unfold)
function ns.MapFolded() return collapsed and true or false end

-- the key: collapse, or open it again (also when a fight collapsed it)
function ns.ToggleCollapse()
    byCombat = nil
    Fold(BattlefieldMapFrame, not collapsed)
end

-- collapse.combat changed
function ns.ApplyCollapse()
    local map = BattlefieldMapFrame
    if Cfg().combat then
        if InCombatLockdown() and not collapsed then
            byCombat = true
            Fold(map, true)
        end
    elseif byCombat then
        byCombat = nil
        Fold(map, false)
    end
end

function ns.SetupCollapse(map)
    ns.MapFace(map)
    -- (opened, resized or made big while collapsed: the strip and the empty
    -- space under it follow)
    local function Refit()
        if collapsed and frac == 1 then
            TrimBorder(map, false)  -- (the border's look may have been set afresh: Style's OnShow)
            SetFrac(map, 1)
            SetHitBox(map, true)
        end
    end
    map:HookScript("OnShow", Refit)
    map:HookScript("OnSizeChanged", Refit)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if Cfg().combat and not collapsed then
                byCombat = true
                Fold(map, true)
            end
        elseif byCombat then
            byCombat = nil
            Fold(map, false)
        end
    end)
    -- (a reload in a fight)
    if Cfg().combat and InCombatLockdown() then
        byCombat = true
        Fold(map, true, true)
    end
end
