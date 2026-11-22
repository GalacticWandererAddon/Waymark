local _, ns = ...

-- The quest log alone (Lab only): the world map's quest log up without the map, on the quest log key (L). The
-- user, 2026-11-22: "Our new questlog is so good at this point. We should almost add it as an option standalone",
-- then of mockups\world-log-alone.html: "B", the log never moves, and "what if i have the log on the left side?".
--
--   L          the log alone opens where it last stood (first time: where it stands beside the world map), on the
--              zone you stand in. L again, its X or Escape closes it. Its plaque drags it.
--   M          with the log up: the world map opens out of the log's side, the window round both, the log where it
--              was. A log kept in the left half of the screen has the map on its right (W.LogSide); only where
--              the log was last dragged decides, never a screen edge.
--   M again    the map closes, the log stays, where the window had it. The window's X closes both.
--   L, map up  folds and unfolds the log (the book's own job), the map stays; a folded log does not stay when the map goes.
--
-- The same column as the world map's (Lab/WorldPanel.lua): its parts, page and search are shared, so what you
-- read alone is what the world map shows. Only with the new log picked (ns.QuestLogKind "new", below: the world
-- map in use and not Classic) and its column on (worldLog.sidebar; picking New puts it back on). With Classic, L is
-- the classic quest window's (Tracker.lua) and M still brings the world map with this log beside it. Setting
-- `aloneL` (OFF unless ticked: "we dont hijack bindings, but we make them VERY easy to find", the user, 2026-11-22):
-- L opens this. W.AloneTakesL / W.SetAloneTakesL are its one home: the settings window's Quest log page, the log's
-- own cog panel and the test bench all go through them.
-- Saved: ns.db.worldLog.alonePos (WaymarkDB.lab.worldLog until 1.3.2) { x, y, left } (UIParent units, the log's top-left), aloneH (its height),
-- logKind ("classic" or nil).
-- Notes: desk/notes/world-log-alone.md.

local W = ns.WorldLog
if not W then return end

local A = { up = false, first = false }   -- (up: the log alone is shown; first: it was up before the map, so it stays)

local function Cfg() return W.Cfg() end
local function Kind() return ns.MapKind and ns.MapKind() == "world" or false end
local function UI() return UIParent:GetEffectiveScale() end
local function ColScale()
    local c = Cfg()
    return (c.scale or 100) / 100 * (ns.AddonScale and ns.AddonScale() or 1)
end
local function Tick() if ns.WorldMapShowNow then ns.Safe("Quest log alone", ns.WorldMapShowNow) end end

function W.Alone() return A.up end
-- the zone the log alone lists: where you stand (the log's own place, a right-click on its title, wins in Refresh)
function W.AloneMap()
    if not A.up then return nil end
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end
-- a drag by the plaque just ended (or is going on): its mouse-up is not a click on it. The player critic's find: a
-- drag by the plaque went back to your own zone and shut the quest page you were reading
function W.AloneJustDragged()
    return A.moving or (A.dragEnd and GetTime() - A.dragEnd < 0.3) or false
end

function W.LogSide()
    local p = Cfg().alonePos
    return p and p.left and "left" or "right"
end

-- Which quest log is the player's: "new" (this one, the world map's log, the default) or "classic" (Tracker.lua's
-- quest window). The user, 2026-11-22: "Its either or, new log or classic log", "new log is default log and we have
-- choice to use a classic questlog", "If that is selected, M still opens the worldmap but the qlog is the old one".
-- One owner of L: the new log takes it here (ApplyKey), the classic one in Tracker.lua (ApplyQuestKey, which asks
-- this). Without the world map in use there is no new log: "classic". Saved: worldLog.logKind ("classic" or nil).
-- The settings window's pick calls ns.SetQuestLogKind (Settings small fixes owns the row).
-- The log and the map go together (the user, 2026-11-22: "With classic ticked, worldmap is off. if classic log on, old
-- bigmap rules apply"): the new log is the world map's, the classic one the big map's. So the kind follows the map's
-- kind, and an old save with the world map and the classic log can't come back (worldLog.logKind is kept in step).
function ns.QuestLogKind()
    return Kind() and "new" or "classic"
end
function ns.SetQuestLogKind(kind)
    if not (ns.db and ns.db.worldLog) then return end
    kind = kind == "classic" and "classic" or "new"
    Cfg().logKind = kind
    if ns.SetMapKind then ns.Safe("Quest log kind, the map with it", ns.SetMapKind, kind == "classic" and "big" or "world") end
    if kind == "classic" and W.AloneClose then W.AloneClose() end
    if ns.WorldPanelResized then ns.Safe("Quest log kind", ns.WorldPanelResized) end
    Tick()
    -- L handed over: each owner clears its own and the picked one takes it, out of a fight (else when it ends)
    if W.AloneApplyKey then ns.Safe("Quest log alone, its key", W.AloneApplyKey) end
    if ns.ApplyQuestWindow then ns.Safe("Quest log kind", ns.ApplyQuestWindow, "keyL") end
end

-- Escape closes it, as it does every window of the game's (a hidden stand-in in UISpecialFrames)
local escape, escapeOurs
local function EscapeOn(on)
    if on and not escape then
        escape = CreateFrame("Frame", "WaymarkWorldLogAloneEscape", UIParent)
        escape:SetSize(1, 1)
        escape:Hide()
        escape:SetScript("OnHide", function()
            if escapeOurs or not A.up then return end
            ns.Safe("Quest log alone", W.AloneClose)
        end)
        tinsert(UISpecialFrames, "WaymarkWorldLogAloneEscape")
    end
    if escape and escape:IsShown() ~= on then
        escapeOurs = true
        escape:SetShown(on)
        escapeOurs = nil
    end
end

-- where it stands the first time: where the column stands beside the world map's own place, else right of middle
-- its height before it has stood beside the world map: the world map's own (its saved size, in the map frame's
-- units), so it is as tall as the window it opens into. The user, 2026-11-22: "On first run the height was about
-- half of the worldmap, it sized to it when i hit m"
local function FirstHeight()
    local mc, map = ns.db and ns.db.mapFrame, BattlefieldMapFrame
    local h = mc and (mc.worldH or mc.bigHeight)
    if h and map then
        local face = ns.MapFace and ns.MapFace(map)
        -- (the picture's share of the frame, when the map has been up once at that size)
        local fh, mh = face and face:GetHeight(), map:GetHeight()
        local share = (fh and mh and fh > 0 and mh > 0 and fh <= mh) and fh / mh or 1   -- (a map never laid out: 0)
        return h * share * map:GetEffectiveScale() / UI()
    end
    return 560
end

local function FirstPlace()
    local c, k = Cfg(), ColScale()
    local width, h = (c.width or 300) * k, c.aloneH or FirstHeight()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local wp = ns.db and ns.db.mapFrame and ns.db.mapFrame.worldPos
    if wp and wp.kind == "topleft" and wp.w then
        return { x = math.min(sw - width, wp.x + wp.w + W.GAP * k), y = wp.y, left = false }
    end
    return { x = math.max(0, sw * 0.62), y = math.min(sh, sh / 2 + h / 2), left = false }
end

-- The log alone, placed: called by WorldPanel's Place while W.Alone()
function W.AlonePlace()
    local panel, slot, head = W.Parts()
    if not (panel and slot) then return end
    local c, k = Cfg(), ColScale()
    local p = c.alonePos or FirstPlace()
    local width = c.width or 300
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local h = math.min(c.aloneH or FirstHeight(), sh - 8)
    local x = math.max(0, math.min(sw - width * k, p.x))
    -- (no higher than the map's own top band lets the map follow: else M put the map lower and the log with it, and
    -- that lower place was kept. The ship check's find)
    local y = math.max(h, math.min(sh - (c.mapFit and c.mapFit.T or 0), p.y))
    slot:SetScale(k)
    panel:SetScale(k)
    slot:SetWidth(width)
    slot:SetHeight(h / k)
    slot:ClearAllPoints()
    slot:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / k, y / k)
    slot.side, slot.foot = "right", 0
    -- (the world map's size for this place and height, ahead of M: it opens at it, no resize once up)
    if W.FitAhead then W.FitAhead(x, x + width * k, y, h) end
    panel:ClearAllPoints()
    panel:SetAllPoints(slot)
    panel:SetFrameStrata("MEDIUM")
    panel:SetFrameLevel(20)
    if panel.gut then panel.gut:Hide() end
    -- its own glass, solid; the brass rules only where no frame is worn
    local key = W.FrameKey and W.FrameKey()
    local dress = not key and W.DressOf and W.DressOf()
    local SL = W.SLATE
    panel.bg:SetColorTexture(SL[1], SL[2], SL[3], 1)
    for i, tex in ipairs(panel.own) do tex:SetShown(i == 1 or not (key or dress)) end
    -- the frame: the window's own set, round the log alone (its child, so it keeps the log's scale)
    if not A.frame then
        A.frame = CreateFrame("Frame", nil, panel)
        A.frame:SetAllPoints(panel)
        A.frame:EnableMouse(false)
    end
    A.frame:SetFrameLevel(panel:GetFrameLevel() + 40)
    local art = W.CLOSE_ART
    if key then
        if not A.set then A.set = ns.LabFrame(A.frame) end
        local sc = (ns.LabSetScale and ns.LabSetScale(key) or 1) * (art.scale[key] or 1)
        local out = ns.LabSetOut and ns.LabSetOut(key, sc) or 0
        A.set:ClearAllPoints()
        A.set:SetPoint("TOPLEFT", panel, "TOPLEFT", -out, out)
        A.set:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", out, -out)
        A.set:SetLook(key, sc)
        A.set:Show()
    elseif A.set then
        A.set:Hide()
    end
    if dress and ns.DressBorder then
        if not A.dress then
            A.dress = CreateFrame("Frame", nil, A.frame, "BackdropTemplate")
            A.dress:EnableMouse(false)
        end
        ns.DressBorder(A.dress, panel, dress[1], dress[2], dress[4] or 0, dress[3])
    elseif A.dress then
        A.dress:Hide()
    end
    -- the close, as the window's: the Engraver's boss cut as an X, else the game's red X in the corner
    if not A.close then
        A.close = CreateFrame("Button", nil, A.frame)
        A.close:SetSize(20, 20)
        for _, s in ipairs({ { "Normal", "redbutton-exit-2x" }, { "Pushed", "redbutton-exit-pressed-2x" }, { "Highlight", "redbutton-highlight-2x" } }) do
            A.close["Set" .. s[1] .. "Texture"](A.close, "Interface\\Buttons\\WHITE8X8")
            local tex = A.close["Get" .. s[1] .. "Texture"](A.close)
            if tex and ns.SetArt then
                ns.SetArt(tex, s[2])
                tex:ClearAllPoints()
                tex:SetPoint("CENTER")
                tex:SetSize(16, 16)
            end
        end
        A.close:SetScript("OnClick", function() ns.Safe("Quest log alone", W.AloneClose) end)
        A.boss = CreateFrame("Button", nil, A.frame)
        A.boss:SetScript("OnClick", function() ns.Safe("Quest log alone", W.AloneClose) end)
    end
    A.close:SetFrameLevel(A.frame:GetFrameLevel() + 5)
    A.boss:SetFrameLevel(A.frame:GetFrameLevel() + 5)
    local spec = key and art.boss[key]
    local piece = key and A.set and A.set.pieces and A.set.pieces[2]
    local boss = key == "engraver" and spec and piece
    A.close:SetShown(not boss)
    A.boss:SetShown(boss and true or false)
    if boss then
        if A.boss.art ~= spec[1] then
            A.boss.art = spec[1]
            A.boss:SetNormalTexture(spec[1])
            A.boss:SetHighlightTexture(spec[1] .. "Lit", "BLEND")
            A.boss:SetPushedTexture(spec[1] .. "Lit")
            local pushed = A.boss:GetPushedTexture()
            if pushed then pushed:SetVertexColor(0.8, 0.8, 0.8) end
        end
        A.boss:ClearAllPoints()
        A.boss:SetAllPoints(piece)
        local w, ph = piece:GetWidth() or 0, piece:GetHeight() or 0
        local cx, cy, r = spec[2], spec[3], spec[4]
        A.boss:SetHitRectInsets(w * (cx - r) / 128, w * (128 - cx - r) / 128, ph * (cy - r) / 128, ph * (128 - cy - r) / 128)
    else
        A.close:ClearAllPoints()
        if piece then
            local at = spec and { spec[2] / 128, spec[3] / 128 } or art.at[key] or art.at.other
            A.close:SetPoint("CENTER", piece, "TOPLEFT", (piece:GetWidth() or 0) * at[1], -(piece:GetHeight() or 0) * at[2])
        else
            A.close:SetPoint("CENTER", panel, "TOPRIGHT", -7, -7)
        end
    end
    -- the size grip in its bottom-right corner, as the map's: width and height. The width is the column's own
    -- (worldLog.width, the same beside the map, so the log keeps its width when the map opens); the height is the
    -- log alone's (aloneH). The user, 2026-11-22: "How about being able to size it? the qlog i mean"
    if not A.grip then
        local g = CreateFrame("Button", nil, A.frame)
        g:SetSize(16, 16)
        g:SetHitRectInsets(-7, -7, -7, -7)
        g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        local sizer = CreateFrame("Frame")
        A.sizer = sizer
        local x0, y0, w0, h0, since = 0, 0, 0, 0, 0
        local function Size(e)
            local cx, cy = GetCursorPosition()
            local sc = slot:GetEffectiveScale()
            local cf = Cfg()
            local sh = UIParent:GetHeight() * UI() / sc
            local top = slot:GetTop() or sh
            cf.width = math.floor(math.max(240, math.min(420, w0 + (cx - x0) / sc)) + 0.5)
            local hh = math.max(300, math.min(top - 4, h0 - (cy - y0) / sc))
            cf.aloneH = hh * sc / UI()
            slot:SetWidth(cf.width)
            slot:SetHeight(hh)
            -- (the lines laid again now and then while it moves, not every frame)
            since = since + (e or 0)
            if since > 0.1 then
                since = 0
                if ns.WorldPanelChanged then ns.WorldPanelChanged() end
            end
        end
        g:SetScript("OnMouseDown", function(_, button)
            -- (right-click: as tall as the world map, to the pixel: the height it had beside the map, else the map's
            -- saved size. The user, 2026-11-22: "it will be annoying never getting to 100% match the log height to
            -- the map. What about a rightclick on corner drag to match?")
            if button == "RightButton" and A.up then
                local cf = Cfg()
                cf.aloneH = cf.mapH or FirstHeight()
                W.AlonePlace()
                if ns.WorldPanelChanged then ns.WorldPanelChanged() end
                return
            end
            if button ~= "LeftButton" or not A.up then return end
            x0, y0 = GetCursorPosition()
            w0, h0, since = slot:GetWidth() or 300, slot:GetHeight() or 500, 0
            sizer:SetScript("OnUpdate", function(_, e) Size(e) end)
        end)
        g:SetScript("OnMouseUp", function()
            if not sizer:GetScript("OnUpdate") then return end
            sizer:SetScript("OnUpdate", nil)
            Size(0)
            if ns.WorldPanelResized then ns.WorldPanelResized() end
        end)
        g:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        g:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Drag: size the quest log", 1, 1, 1)
            GameTooltip:AddLine("Right-click: as tall as the world map", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        g:SetScript("OnLeave", function(self) if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
        A.grip = g
    end
    A.grip:SetFrameLevel(A.frame:GetFrameLevel() + 6)
    A.grip:ClearAllPoints()
    A.grip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, 3)
    A.frame:Show()
    -- the plaque and the glass drag it (only alone: in the window the bar is the handle)
    if not A.drag then
        A.drag = true
        -- (our own drag, the cursor followed each frame: the game's StartMoving on the scaled slot left the log's
        -- glass, frame and plaque behind and shifted its lines while the button was held, the user's shot,
        -- 2026-11-22: "Dragging it to move it doesnt work ... all but the penciled art is gone while i hold")
        if not A.mover then A.mover = CreateFrame("Frame") end
        local function Follow()
            local s = slot:GetEffectiveScale()
            if not (s and s > 0) then return end
            local cx, cy = GetCursorPosition()
            local x, y = cx / s + A.dx, cy / s + A.dy
            -- (all of it on the screen)
            local sw, sh = UIParent:GetWidth() * UI() / s, UIParent:GetHeight() * UI() / s
            local w, h = slot:GetWidth() or 0, slot:GetHeight() or 0
            x = math.max(0, math.min(sw - w, x))
            y = math.max(h, math.min(sh, y))
            slot:ClearAllPoints()
            slot:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        end
        local function Start()
            if not A.up or A.moving then return end
            local s = slot:GetEffectiveScale()
            local l, t = slot:GetLeft(), slot:GetTop()
            if not (s and s > 0 and l and t) then return end
            local cx, cy = GetCursorPosition()
            A.dx, A.dy = l - cx / s, t - cy / s
            A.moving = true
            A.mover:SetScript("OnUpdate", Follow)
        end
        local function Stop()
            if not A.moving then return end
            A.moving = false
            A.mover:SetScript("OnUpdate", nil)
            A.dragEnd = GetTime()
            Follow()
            local s = slot:GetEffectiveScale() / UI()
            local l, t = slot:GetLeft(), slot:GetTop()
            if l and t then
                local w = slot:GetWidth() * s
                -- (which half of the screen it stands in now decides the map's side: only here, at a let-go)
                Cfg().alonePos = { x = l * s, y = t * s, left = l * s + w / 2 < UIParent:GetWidth() / 2 }
            end
            W.AlonePlace()
        end
        for _, f in ipairs({ panel, head }) do
            if f and f.RegisterForDrag then
                f:RegisterForDrag("LeftButton")
                f:SetScript("OnDragStart", Start)
                f:SetScript("OnDragStop", Stop)
            end
        end
    end
end

function W.AloneOpen()
    if A.up or not (Kind() and Cfg().on and W.Ready and W.Ready()) then return end
    if ns.QuestLogKind() ~= "new" then return end   -- (the classic log picked: L is its window's)
    if ns.WorldSidebarOff and ns.WorldSidebarOff() then return end   -- (the log beside the world map off)
    if ns.WorldMapUp and ns.WorldMapUp() then return end
    -- (the game's own world map up, with its own quest log: never two logs. Only read, never driven)
    if WorldMapFrame and WorldMapFrame:IsShown() then return end
    if not BattlefieldMapFrame then
        if InCombatLockdown() then return end
        pcall(C_AddOns and C_AddOns.LoadAddOn or LoadAddOn, "Blizzard_BattlefieldMap")
        if not BattlefieldMapFrame then return end
    end
    Cfg().logAt = nil   -- (opens on the zone you stand in)
    A.up, A.first = true, false
    EscapeOn(true)
    Tick()
    if ns.WorldPanelChanged then ns.WorldPanelChanged() end
end

function W.AloneClose()
    A.first = false   -- (also with the map up from the log: it must not come back when the map goes. The critic's find)
    -- (a drag or a size going on: stopped, else it went on moving the column with the cursor. The ship check's find)
    A.moving = false
    if A.mover then A.mover:SetScript("OnUpdate", nil) end
    if A.sizer then A.sizer:SetScript("OnUpdate", nil) end
    if not A.up then return end
    A.up = false
    EscapeOn(false)
    if A.frame then A.frame:Hide() end
    Tick()
end

-- Find on a quest's page, alone: the world map opens beside the log, then finds it there; only on the world map
-- (docked in a fight the map opens when the fight ends: the square must not browse away meanwhile. The ship check)
function W.AloneFind(id)
    W.AloneOpenMap()
    if not C_Timer then return end
    C_Timer.After(0.15, function()
        if ns.WorldMapUp and ns.WorldMapUp() then
            if ns.FindQuestOnMap then ns.Safe("World log find", ns.FindQuestOnMap, id) end
        else
            A.findDue = id
        end
    end)
end
-- Find on a quest's page, alone: the world map opens beside the log
function W.AloneOpenMap()
    if ns.ToggleBigMap and not (ns.WorldMapUp and ns.WorldMapUp()) then ns.Safe("Quest log alone, the map", ns.ToggleBigMap) end
end

-- the quest log key
function W.AloneKey()
    if not Kind() then return end
    if ns.WorldMapUp and ns.WorldMapUp() then
        -- (L opens the world map with it: L again closes both, as the window's X does)
        if W.LOpensMap() then
            A.first = false
            if ns.ToggleBigMap then ns.Safe("Quest log key, the map", ns.ToggleBigMap) end
            return
        end
        -- (the map up: L is the log's key, it folds and unfolds; a folded log does not stay when the map goes)
        local _, _, _, _, bar = W.Parts()
        local click = bar and bar.fold and bar.fold:GetScript("OnClick")   -- (the book's own: fold, then draw)
        if click then click(bar.fold) else W.Fold() end
        return
    end
    if A.up then W.AloneClose() return end
    W.AloneOpen()
    -- (L opens the world map with it: the log, then the map out of its side, as M in the log does. The user,
    -- 2026-11-22, on "L opens the world map with it": "Yes make")
    if A.up and W.LOpensMap() then W.AloneOpenMap() end
end

-- The world map opens (MapControls' WorldOpen, after the map has its size and place): with the log alone up, the
-- map fits the log. The user, 2026-11-22, on the player critic's pick: "Yes, map fits log". Its picture is as tall
-- as the log, as wide as its own shape asks or as the room on the log's side allows, and put beside it, so the log
-- does not move and keeps its height. That size is the world map's own (worldW / worldH).
-- It is worked out AHEAD, while the log stands alone (W.FitAhead, each time it is placed, dragged or sized), so the
-- map opens at that size and is not resized once it is up: a resize after opening refitted its picture round your
-- arrow (the user, 2026-11-22: "Map tried to fit the playerarrow in picture. If im at the edge of a zone, it will
-- adjust right ... it pans"). What it needs of the map (the frame's bands round the picture, the picture's own
-- shape, the map's scale) is measured whenever the map is up beside the log and kept (worldLog.mapFit).
local function FitNumbers(fit, logL, logR, logT, logH)
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local left = W.LogSide() == "left"
    local gap = fit.gap or 6
    -- as tall as the log (no taller than the screen lets the map be: MapControls' FitScreen keeps it to 95%)
    local faceH = math.min(logH, sh * 0.95 - fit.T - fit.B)
    -- as wide as its own shape, no wider than the room on the log's side
    local room = left and (sw - logR - gap - fit.L - fit.R) or (logL - gap - fit.L - fit.R)
    local faceW = math.max(120, math.min(faceH * fit.aspect, room))
    local mapW, mapH = faceW + fit.L + fit.R, faceH + fit.T + fit.B
    local faceL = left and (logR + gap) or (logL - gap - faceW)
    return mapW, mapH, faceL - fit.L, logT + fit.T, faceW, faceH
end
-- the world map's size from the log's place and height (UIParent units), set before the map opens
function W.FitAhead(logL, logR, logT, logH)
    local c, mc = Cfg(), ns.db and ns.db.mapFrame
    local fit = c.mapFit
    if not (fit and fit.M and fit.M > 0 and mc) then return end
    local mapW, mapH, _, _, faceW, faceH = FitNumbers(fit, logL, logR, logT, logH)
    mc.worldW, mc.worldH = mapW / fit.M, mapH / fit.M
    fit.setW, fit.setH = faceW, faceH
end
local function PutMapBeside()
    local map = BattlefieldMapFrame
    local panel = W.Parts()
    local face = map and (ns.MapFace and ns.MapFace(map) or map)
    local mc = ns.db and ns.db.mapFrame
    if not (map and face and panel and mc and ns.RestoreMapPosition) then return end
    local fl, ft, fr, fb = face:GetLeft(), face:GetTop(), face:GetRight(), face:GetBottom()
    local ml, mt, mr, mb = map:GetLeft(), map:GetTop(), map:GetRight(), map:GetBottom()
    local pl, pt, pr, pb = panel:GetLeft(), panel:GetTop(), panel:GetRight(), panel:GetBottom()
    if not (fl and ft and fr and fb and ml and mt and mr and mb and pl and pt and pr and pb) then return end
    local ui, fs, ms, ps = UI(), face:GetEffectiveScale(), map:GetEffectiveScale(), panel:GetEffectiveScale()
    local F, M, P = fs / ui, ms / ui, ps / ui   -- (each frame's units to UIParent's)
    local c = Cfg()
    local fit = c.mapFit or {}
    -- the frame's bands round the picture, measured now and kept
    fit.L, fit.R = fl * F - ml * M, mr * M - fr * F
    fit.T, fit.B = mt * M - ft * F, fb * F - mb * M
    fit.M, fit.gap = M, W.GAP * P
    -- the picture's own shape: as it is now, unless it is only the shape we fitted it to last time (a fit to a
    -- narrow room must not become the map's shape); a map sized by its own grip since gives its new shape
    local faceW0, faceH0 = (fr - fl) * F, (ft - fb) * F
    local ours = fit.setW and math.abs(faceW0 - fit.setW) < 2 and math.abs(faceH0 - fit.setH) < 2
    if not (ours and fit.aspect) then fit.aspect = faceH0 > 0 and faceW0 / faceH0 or 1.5 end
    c.mapFit = fit
    local logL, logR, logT, logH = pl * P, pr * P, pt * P, (pt - pb) * P
    local mapW, mapH, x, y, faceW, faceH = FitNumbers(fit, logL, logR, logT, logH)
    mc.worldW, mc.worldH = mapW / M, mapH / M
    fit.setW, fit.setH = faceW, faceH
    mc.pos = { kind = "topleft", x = x, y = y, w = mapW, right = x + mapW / 2 > UIParent:GetWidth() / 2 }
    -- (worked out ahead, the size is already right and this changes nothing; the first time, or a log sized while
    -- the map was never measured, it is resized here once)
    if ns.UpdateMapShape then ns.UpdateMapShape(true, true) end
    ns.RestoreMapPosition()
end

-- the column's place and height as the window leaves it: where the log alone stands next
local function KeepColumn()
    local panel = W.Parts()
    if not (panel and panel:IsShown()) then return end
    local s = panel:GetEffectiveScale() / UI()
    local l, t, h = panel:GetLeft(), panel:GetTop(), panel:GetHeight()
    if not (l and t and h) then return end
    local c = Cfg()
    -- (which half it stands in, as a drag decides: the window may have been dragged across the middle. The critic's
    -- find: a stale side opened the map off the screen's edge next time and shoved the log)
    local w = (panel:GetWidth() or 0) * s
    c.alonePos = { x = l * s, y = t * s, left = l * s + w / 2 < UIParent:GetWidth() / 2 }
    -- (its own height is kept once you have sized it: beside the map it is the map's height, alone your own)
    c.aloneH = c.aloneH or h * s
    c.mapH = h * s   -- (its height beside the map, exactly: a right-click on its grip matches it)
end

local hooked
local function HookClose()
    -- (the window's X closes both, the log too)
    local _, _, _, _, bar = W.Parts()
    if hooked or not bar then return end
    hooked = true
    for _, b in ipairs({ bar.close, bar.boss }) do
        if b then b:HookScript("PreClick", function() A.first = false end) end
    end
end

local showNow, hideNow = ns.WorldMapShowNow, ns.WorldMapHideNow
if showNow and hideNow then
    function ns.WorldMapShowNow(...)
        if A.up and ns.WorldMapUp and ns.WorldMapUp() then
            A.up, A.first = false, true
            EscapeOn(false)
            if A.frame then A.frame:Hide() end
            -- (unfolded first, so the map has its size with the log beside it, then put beside it)
            if Cfg().fold then W.Fold(false) end
            ns.Safe("Quest log alone, the map beside it", PutMapBeside)
        end
        local from = A.first and Cfg().logAt
        local r = showNow(...)
        HookClose()
        -- (Find from the log alone, the map opened later, after a fight: found now, on the world map)
        local due = A.findDue
        A.findDue = nil
        if due and C_Timer and ns.FindQuestOnMap then
            C_Timer.After(0.15, function()
                if ns.WorldMapUp and ns.WorldMapUp() then ns.Safe("World log find", ns.FindQuestOnMap, due) end
            end)
        end
        -- (the log was browsed to another zone: the map opens on it too, and the log follows the map from here. The
        -- player critic: "I'm reading Westfall, show me Westfall")
        if from and ns.BrowseTo then
            Cfg().logAt = nil
            ns.Safe("Quest log alone, the map on its zone", ns.BrowseTo, from)
        end
        return r
    end
    function ns.WorldMapHideNow(...)
        local stay = A.first and Kind() and not Cfg().fold
        A.first = false
        if stay then ns.Safe("Quest log alone, its place", KeepColumn) end
        -- (its height beside the map, whichever way the map was opened: the grip's right-click matches it)
        local panel = W.Parts()
        if panel and panel:IsShown() and panel:GetHeight() then
            Cfg().mapH = panel:GetHeight() * panel:GetEffectiveScale() / UI()
        end
        hideNow(...)
        -- (a frame later: one Escape closes the map, not the log with it)
        if stay and C_Timer then
            C_Timer.After(0, function()
                if A.up or (ns.WorldMapUp and ns.WorldMapUp()) or not Kind() then return end
                if ns.QuestLogKind() ~= "new" or (ns.WorldSidebarOff and ns.WorldSidebarOff()) then return end
                A.up = true
                EscapeOn(true)
                Tick()
            end)
        end
    end
end

-- The quest log key: an override binding on the keys bound to the game's quest log, only with the world map
-- picked (with the big map picked, L is the quest window's: Tracker.lua). Bindings change only out of a fight.
local keyButton, keyPending, keysAt
local function QuestKeys() return table.concat({ GetBindingKey("TOGGLEQUESTLOG") }, " ") end
local function ApplyKey()
    if not keyButton then
        keyButton = CreateFrame("Button", "WaymarkWorldLogKey", UIParent)
        keyButton:SetScript("OnClick", function() ns.Safe("Quest log key", W.AloneKey) end)
    end
    if InCombatLockdown() then keyPending = true return end
    keyPending = nil
    keysAt = QuestKeys()
    ClearOverrideBindings(keyButton)
    if not (ns.db and ns.db.worldLog and Kind() and Cfg().aloneL == true) then return end
    -- (the classic log picked: L is its window's, Tracker.lua. The log beside the world map off: no log alone either)
    if ns.QuestLogKind() ~= "new" then return end
    if ns.WorldSidebarOff and ns.WorldSidebarOff() then return end
    for _, key in ipairs({ GetBindingKey("TOGGLEQUESTLOG") }) do
        SetOverrideBindingClick(keyButton, false, key, "WaymarkWorldLogKey")
    end
end
W.AloneApplyKey = ApplyKey
-- L opens the new log: only when the player ticked it (worldLog.aloneL true). The ticks: the settings window's Quest
-- log page, the log's own cog panel (WorldPanel FillOptions), the welcome page (Settings small fixes)
function W.AloneTakesL() return ns.db and ns.db.worldLog and Cfg().aloneL == true or false end
function W.SetAloneTakesL(on)
    if not (ns.db and ns.db.worldLog) then return end
    Cfg().aloneL = on and true or false
    ns.Safe("Quest log alone, its key", ApplyKey)
end
-- L opens the world map with the log (worldLog.aloneLMap, off unless ticked; its row under "L opens this log", the
-- settings window's Quest log page)
function W.LOpensMap() return ns.db and ns.db.worldLog and Cfg().aloneLMap == true or false end
function W.SetLOpensMap(on)
    if not (ns.db and ns.db.worldLog) then return end
    Cfg().aloneLMap = on and true or false
end
-- the keys bound to the quest log, as words for a tick ("L"), nil when none
function W.QuestKeyName()
    local k = GetBindingKey and GetBindingKey("TOGGLEQUESTLOG")
    return k and (GetBindingText and GetBindingText(k) or k) or nil
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UPDATE_BINDINGS")
-- the game's own world map opened (M left as the game's): it has its own quest log, so ours goes, never two logs.
-- Only watched, never steered (HookScript on its OnShow). The player critic's find.
local gameMapHooked
local function HookGameMap()
    if gameMapHooked or not (WorldMapFrame and WorldMapFrame.HookScript) then return end
    gameMapHooked = true
    WorldMapFrame:HookScript("OnShow", function()
        if A.up then ns.Safe("Quest log alone, the game's map", W.AloneClose) end
    end)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then pcall(HookGameMap) end
    if event == "PLAYER_REGEN_ENABLED" and not keyPending then return end
    -- (the quest log rebound: follow it now, not at the next loading screen. Only when its keys really changed:
    -- our own override binding fires this event too, and the key list it reads is the binding's, not ours)
    if event == "UPDATE_BINDINGS" and (not keyButton or QuestKeys() == keysAt) then return end
    ns.Safe("Quest log alone, its key", ApplyKey)
end)
-- the map switched: the key follows; the log alone goes with the world map
if ns.SetMapKind and hooksecurefunc then
    hooksecurefunc(ns, "SetMapKind", function()
        if not Kind() then W.AloneClose() end
        ns.Safe("Quest log alone, its key", ApplyKey)
    end)
end
-- the quest log's settings changed (Tracker.lua's ApplyQuestWindow; /worldlog sidebar calls it too): the key follows,
-- and with the log beside the world map switched off there is no log alone either
if ns.ApplyQuestWindow and hooksecurefunc then
    hooksecurefunc(ns, "ApplyQuestWindow", function()
        if ns.QuestLogKind() ~= "new" or (ns.WorldSidebarOff and ns.WorldSidebarOff()) then W.AloneClose() end
        ns.Safe("Quest log alone, its key", ApplyKey)
    end)
end

function W.AloneInfo()
    local p = Cfg().alonePos
    return ("alone: %s; L opens it: %s; with the world map picked: %s; side: %s; place: %s"):format(
        A.up and "up" or "closed", Cfg().aloneL == true and "yes" or "no (not ticked)", Kind() and "yes" or "no (L is the quest window's)",
        W.LogSide(), p and ("%d, %d"):format(p.x, p.y) or "not yet (beside the world map's place)")
end
