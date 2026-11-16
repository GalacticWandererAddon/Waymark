local _, ns = ...

-- Collapsing the map: the map picture folds up under the header, leaving only
-- the upper frame; the buttons, coordinates and resize grip hide with it. An
-- attached quest tracker stays (below the map it rides up under the strip). By
-- key (BFI_COLLAPSE) and/or in combat (collapse.combat: open again when the
-- fight ends, unless you'd collapsed it yourself before). Not kept over a reload.
-- Making room (collapse.windows): it also folds while a window you opened lies
-- on it (loot, a quest text, a vendor, bags) and opens when that window closes.
-- Only windows you open move it: never a tooltip, a whisper or a roll window.
-- Each cause is a reason (auto); the map opens when the last reason goes, a
-- short wait after it (a new pull or the next bag keeps it folded: no flapping).
-- The glance: the key held down (GLANCE seconds or longer) only lasts as long as
-- you hold it; let go and the map is as it was, reasons and all. A tap toggles.
-- The ribbon (collapse.ribbon): folded isn't gone but a band of the ground round
-- you (MapControls' ns.MapRibbon does the size and the view); where there's no
-- ribbon to show (docked, another zone's map) it folds away as before.
--
-- The border, the header and the tracker hang off the map's face (ns.MapFace):
-- a frame over the map area, as tall as it, or as the strip while collapsed.

local FOLD_TIME = 0.25  -- seconds
local STRIP = 1         -- what's left of the map area, in map units
local COMBAT_WAIT = 1.5 -- seconds after a fight before the map opens again
local ROOM_WAIT = 0.4   -- seconds after the last window in the way closes
local ROOM_SHARE = 0.10 -- of the smaller of the two that must overlap to count
local GLANCE = 0.3      -- seconds: the key held this long is a glance, shorter a tap

local function Cfg() return ns.db.collapse end

local face
local collapsed      -- folded or folding away
local ribboned       -- ... as a ribbon: the map's still there, small (ns.MapRibbon)
local glance         -- the key is down: { was, auto, at } as it was before
local auto = {}      -- why it's folded by itself: auto.combat, auto.room (none: by your own key)
local waiting = {}   -- [reason] = the wait before that reason lets go
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
    -- the ribbon: the map's own size and view do it, nothing folds
    if on and Cfg().ribbon and ns.MapRibbon and ns.MapRibbon(true) then
        ribboned = true
        HideButtons(map)
        return
    elseif not on and ribboned then
        ribboned = nil
        ns.MapRibbon(false)
        ShowButtons()
        return
    end
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
    wipe(auto)
    wipe(waiting)
    Fold(BattlefieldMapFrame, not collapsed)
end

-- The key, with its state ("down" / "up"; nil: a plain press). Down acts at
-- once. Up after a hold puts back what was: folded or open, and the reasons
-- that still hold (a fight that ended while you looked lets it open).
local RoomNow  -- (below: a window in the way now)
local function ToggleMap()
    if ToggleBattlefieldMap then pcall(ToggleBattlefieldMap) end
end
function ns.CollapseKey(state)
    local map = BattlefieldMapFrame
    local docked = ns.Docked and ns.Docked()
    -- the map's closed: the key brings it, open; held, only while you hold it
    if state ~= "up" and not docked and not (map and map:IsShown()) then
        glance = state == "down" and { closed = true, at = GetTime() } or nil
        wipe(auto)
        wipe(waiting)
        if map then Fold(map, false, true) end
        ToggleMap()
        return
    end
    if state == "up" and glance and glance.closed then
        local g = glance
        glance = nil
        if GetTime() - g.at >= GLANCE and map and map:IsShown() and not docked then ToggleMap() end
        return
    end
    if state ~= "up" then
        glance = state == "down" and { was = collapsed and true or false, auto = {}, at = GetTime() } or nil
        if glance then for k in pairs(auto) do glance.auto[k] = true end end
        ns.ToggleCollapse()
        return
    end
    local g = glance
    glance = nil
    if not g or GetTime() - g.at < GLANCE then return end
    wipe(auto)
    wipe(waiting)
    local fold = g.was
    if g.was then
        -- back to folded: by the reasons it had, those that still hold
        if g.auto.combat and InCombatLockdown() then auto.combat = true end
        if g.auto.room and RoomNow(map) then auto.room = true end
        if next(g.auto) and not next(auto) then fold = false end
    elseif Cfg().combat and InCombatLockdown() then
        -- held folded while a fight began: the fight keeps it
        auto.combat = true
        fold = true
    end
    Fold(map, fold)
end

-- The glance on the map's own key (the game's Toggle Battlefield Map): a tap
-- shows or hides it as ever; held GLANCE seconds or longer, it only lasts while
-- you hold it (closed: the map's there while held; open: out of the way while
-- held). The game's binding runs on key down only, so its keys are bound over
-- to a button of ours that hears both (as Dock.lua's and Tracker.lua's keys).
-- Out of combat only: bindings can't change in a fight, after it then. Docked,
-- the key does nothing (Dock.lua's rule).
-- collapse.glance = false (the settings' "A glance when I hold the map's key"; the night review, 2026-11-15:
-- it had no switch): no key is bound over, the game's own binding opens and closes the map as before
-- the glance was made. On unless switched off.
local MAP_KEYS = { "TOGGLEBATTLEFIELDMINIMAP", "TOGGLEBATTLEFIELDMAP" }
local mapKey = CreateFrame("Button", "WaymarkMapKey", UIParent)
local mapKeyAt, mapKeySet, mapKeyPending

local function MapKey(down)
    if ns.standBy then
        if down then ToggleMap() end
        return
    end
    if ns.Docked and ns.Docked() then mapKeyAt = nil return end
    if down then
        mapKeyAt = GetTime()
        ToggleMap()
    else
        local at = mapKeyAt
        mapKeyAt = nil
        if at and GetTime() - at >= GLANCE then ToggleMap() end
    end
end

-- (only when the keys changed: setting an override fires UPDATE_BINDINGS itself)
local function ApplyMapKey()
    if InCombatLockdown() then mapKeyPending = true return end
    mapKeyPending = nil
    local keys = {}
    local off = ns.db and ns.db.collapse and ns.db.collapse.glance == false
    for _, action in ipairs(off and {} or MAP_KEYS) do
        for _, key in ipairs({ GetBindingKey(action) }) do keys[#keys + 1] = key end
    end
    local set = table.concat(keys, " ")
    if set == mapKeySet then return end
    mapKeySet = set
    ClearOverrideBindings(mapKey)
    for _, key in ipairs(keys) do SetOverrideBindingClick(mapKey, false, key, "WaymarkMapKey") end
end

ns.ApplyMapKey = ApplyMapKey   -- (the settings' switch; in a fight it waits for the fight's end)
mapKey:RegisterForClicks("AnyDown", "AnyUp")
mapKey:SetScript("OnClick", function(_, _, down) ns.Safe("Map key", MapKey, down) end)
mapKey:RegisterEvent("PLAYER_ENTERING_WORLD")
mapKey:RegisterEvent("UPDATE_BINDINGS")
mapKey:RegisterEvent("PLAYER_REGEN_ENABLED")
mapKey:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_REGEN_ENABLED" or mapKeyPending then ApplyMapKey() end
end)

-- A reason to be folded comes or goes. One you folded yourself stays yours: no
-- reason is added to it, so nothing opens it but your key. wait: seconds the
-- reason lingers after it ends (cut short if it comes back).
local function Auto(map, reason, on, wait)
    if on then
        waiting[reason] = nil
        if not collapsed then
            auto[reason] = true
            Fold(map, true)
        elseif next(auto) then
            auto[reason] = true
        end
    elseif auto[reason] then
        if wait and wait > 0 then
            local token = {}
            waiting[reason] = token
            C_Timer.After(wait, function()
                if waiting[reason] ~= token then return end
                waiting[reason] = nil
                Auto(map, reason, false)
            end)
            return
        end
        waiting[reason] = nil
        auto[reason] = nil
        if not next(auto) then Fold(map, false) end
    end
end

-- Making room ------------------------------------------------------------------

-- the game's windows that never come through ShowUIPanel (bags, loot)
local ROOM_NAMES = { "LootFrame", "ContainerFrameCombinedBags", "BankFrame", "MailFrame", "TradeFrame" }
for i = 1, 13 do ROOM_NAMES[#ROOM_NAMES + 1] = "ContainerFrame" .. i end
local watched = {}  -- [window] = true: its OnShow / OnHide ask again
local roomSoon

-- how much two boxes (left, bottom, right, top) overlap, as a share of the smaller
local function Overlap(l1, b1, r1, t1, l2, b2, r2, t2)
    local w = math.min(r1, r2) - math.max(l1, l2)
    local h = math.min(t1, t2) - math.max(b1, b2)
    if w <= 0 or h <= 0 then return 0 end
    local small = math.min((r1 - l1) * (t1 - b1), (r2 - l2) * (t2 - b2))
    return small > 0 and w * h / small or 0
end

local function Box(f)
    local l, b, w, h = f:GetRect()
    if not (l and w) then return end
    local s = f:GetEffectiveScale()
    return l * s, b * s, (l + w) * s, (b + h) * s
end

ns.collapseRoom = nil  -- (the window in the way, for /bfi check)

local function InTheWay(map)
    local l, b, r, t = Box(map)
    if not l then return false end
    for f in pairs(watched) do
        if f:IsVisible() then
            local l2, b2, r2, t2 = Box(f)
            if l2 and Overlap(l, b, r, t, l2, b2, r2, t2) >= ROOM_SHARE then
                ns.collapseRoom = f:GetName() or "?"
                return true
            end
        end
    end
    ns.collapseRoom = nil
    return false
end

RoomNow = function(map)
    return Cfg().windows and not (ns.Docked and ns.Docked()) and InTheWay(map) or false
end

local function RoomCheck()
    roomSoon = nil
    local map = BattlefieldMapFrame
    if not map then return end
    local on = Cfg().windows and map:IsVisible() and not (ns.Docked and ns.Docked()) and InTheWay(map)
    if on then
        Auto(map, "room", true)
    elseif not Cfg().windows or (ns.Docked and ns.Docked()) then
        Auto(map, "room", false)
    else
        Auto(map, "room", false, ROOM_WAIT)
    end
end

-- (a frame later: a window has its place by then, and five bags ask once)
local function RoomSoon()
    if roomSoon then return end
    roomSoon = true
    C_Timer.After(0, function() ns.Safe("Collapse RoomCheck", RoomCheck) end)
end

local function Watch(f)
    if type(f) ~= "table" or watched[f] or f == BattlefieldMapFrame or not f.HookScript then return end
    if f.IsForbidden and f:IsForbidden() then return end
    watched[f] = true
    f:HookScript("OnShow", RoomSoon)
    f:HookScript("OnHide", RoomSoon)
end

-- (for the offline test, tools\collapse_test.lua)
ns.collapseRules = { Overlap = Overlap, Auto = Auto, reasons = auto, MapKey = MapKey }

-- collapse.combat, collapse.windows or the ribbon's settings changed
function ns.ApplyCollapse()
    local map = BattlefieldMapFrame
    -- (folded one way, now to be the other)
    if collapsed and (ribboned and true or false) ~= (Cfg().ribbon and true or false) then
        Fold(map, false, true)
        Fold(map, true)
    elseif ribboned and ns.MapRibbonRefresh then
        ns.MapRibbonRefresh()
    end
    if Cfg().combat then
        if InCombatLockdown() then Auto(map, "combat", true) end
    else
        Auto(map, "combat", false)
    end
    RoomCheck()
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
    map:HookScript("OnShow", RoomSoon)
    map:HookScript("OnSizeChanged", Refit)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if Cfg().combat then Auto(map, "combat", true) end
        else
            Auto(map, "combat", false, COMBAT_WAIT)
        end
    end)
    -- (a reload in a fight)
    if Cfg().combat and InCombatLockdown() then
        auto.combat = true
        Fold(map, true, true)
    end
    -- making room: the game's panels as they open, the bags and loot by name
    if ShowUIPanel then
        hooksecurefunc("ShowUIPanel", function(f)
            Watch(f)
            RoomSoon()
        end)
    end
    for _, name in ipairs(ROOM_NAMES) do
        if _G[name] then Watch(_G[name]) end
    end
    RoomSoon()
end
