local _, ns = ...

-- /bfi check: the addon looks at itself so Claude can read the result from disk.
-- It checks how the map's layers and our frames sit, counts pins per layer,
-- collects our Lua errors, saves it all to WaymarkDB.diag and takes a
-- screenshot. Your /reload then writes the saved variables file.

-- Errors ---------------------------------------------------------------------

-- this session's errors from our files: { msg, stack, count, first, last }
local errors = {}
ns.sessionErrors = errors

function ns.RecordError(msg, stack)
    msg = tostring(msg)
    for _, e in ipairs(errors) do
        if e.msg == msg then
            e.count, e.last = e.count + 1, date("%H:%M:%S")
            return
        end
    end
    if #errors >= 30 then return end
    errors[#errors + 1] = { msg = msg, stack = stack, count = 1, first = date("%H:%M:%S"), last = date("%H:%M:%S") }
end

-- pcall that remembers what went wrong (for our own code, where a silent
-- failure would hide a bug): label says where
local Spent, depth
function ns.Safe(label, fn, ...)
    local trail = ns.Trail  -- (Report.lua: what Waymark did lately, for a report of a blocked action)
    if trail then trail(label) end
    local t = debugprofilestop()
    depth = depth + 1
    local ok, err = pcall(fn, ...)
    depth = depth - 1
    Spent(label, debugprofilestop() - t)
    if not ok then ns.RecordError(label .. ": " .. tostring(err), debugstack and debugstack(2, 6, 0) or nil) end
    return ok, err
end

-- Frame cost -------------------------------------------------------------------

-- How long our code takes, by label, since the last /bfi check (which reads and
-- resets it): ns.Timed wraps a handler, ns.TimedFrame times a ticker frame's
-- scripts, ns.Safe times its call. A label inside another (a ticker's ns.Safe
-- calls) counts in both, but only the outer one in "ours a frame".
local cost = {}  -- [label] = { ms, calls, worst ms }
local costFrames, costFrom, ourFrame, ourWorst, ourTotal, gameWorst = 0, GetTime(), 0, 0, 0, 0
depth = 0

Spent = function(label, ms)
    local c = cost[label]
    if not c then c = { 0, 0, 0, 0 } cost[label] = c end
    c[1], c[2] = c[1] + ms, c[2] + 1
    if ms > c[3] then c[3] = ms end
    if ms >= 8 then c[4] = c[4] + 1 end  -- (a spike: half a frame at 60 fps)
    if depth == 0 then ourFrame = ourFrame + ms end
end
-- a piece of a timed handler, measured by hand: ms since t0
function ns.CostAdd(label, t0) Spent(label, debugprofilestop() - t0) end

function ns.Timed(label, fn)
    return function(...)
        local t = debugprofilestop()
        depth = depth + 1
        local ok, err = pcall(fn, ...)
        depth = depth - 1
        Spent(label, debugprofilestop() - t)
        if not ok then geterrorhandler()(err) end
    end
end

-- a frame whose scripts are timed: OnUpdate under label, others as "label OnEvent"
function ns.TimedFrame(label, parent)
    local f = CreateFrame("Frame", nil, parent)
    local set = f.SetScript
    f.SetScript = function(self, script, fn)
        return set(self, script, fn and ns.Timed(script == "OnUpdate" and label or (label .. " " .. script), fn))
    end
    return f
end

do
    local counter = CreateFrame("Frame")
    counter:SetScript("OnUpdate", function(_, dt)
        costFrames = costFrames + 1
        if ourFrame > ourWorst then ourWorst = ourFrame end
        ourTotal, ourFrame = ourTotal + ourFrame, 0
        -- (the first frames after a loading screen are long anyway)
        if costFrames > 30 and dt > gameWorst then gameWorst = dt end
    end)
end

-- what was measured, as a line and a list (most time first); starts over after
local function FrameCost()
    local secs, list = GetTime() - costFrom, {}
    local n = math.max(1, costFrames)
    for label, c in pairs(cost) do
        list[#list + 1] = { label = label, perFrame = c[1] / n, calls = c[2], worst = c[3], spikes = c[4] }
    end
    table.sort(list, function(a, b) return a.perFrame > b.perFrame end)
    local top, spiky = {}, {}
    for i = 1, math.min(12, #list) do
        local c = list[i]
        top[#top + 1] = string.format("%s %.3f (%d calls, worst %.1f)", c.label, c.perFrame, c.calls, c.worst)
    end
    -- the spikes are what you feel: every label with a call over 8 ms
    for _, c in ipairs(list) do
        if c.spikes > 0 then spiky[#spiky + 1] = string.format("%s %dx (worst %.1f)", c.label, c.spikes, c.worst) end
    end
    -- what made the quest pins rebuild (QuestData.lua counts each change by event)
    local changes = {}
    for event, k in pairs(ns.questChanges or {}) do changes[#changes + 1] = event .. " " .. k end
    table.sort(changes)
    if ns.questChanges then wipe(ns.questChanges) end
    local line = string.format("%.0f s, %d frames (%.0f fps); ours %.2f ms a frame, worst frame of ours %.1f ms, "
        .. "game's slowest frame %.0f ms; calls over 8 ms: %s; quest changes: %s; ms a frame by label: %s",
        secs, costFrames, costFrames / math.max(secs, 0.001), ourTotal / n, ourWorst, gameWorst * 1000,
        #spiky > 0 and table.concat(spiky, ", ") or "none",
        #changes > 0 and table.concat(changes, ", ") or "none", table.concat(top, ", "))
    cost, costFrames, costFrom, ourFrame, ourWorst, ourTotal, gameWorst = {}, 0, GetTime(), 0, 0, 0, 0
    return line, list
end

-- the textures, lines and font strings shown under a frame (and its frames)
local function CountDrawn(f, n)
    n = n or { tex = 0, line = 0, text = 0, frames = 0 }
    if not f:IsVisible() then return n end
    n.frames = n.frames + 1
    local ok, regions = pcall(function() return { f:GetRegions() } end)
    for _, r in ipairs(ok and regions or {}) do
        if r:IsShown() then
            local t = r:GetObjectType()
            if t == "Texture" then n.tex = n.tex + 1
            elseif t == "Line" then n.line = n.line + 1
            elseif t == "FontString" then n.text = n.text + 1 end
        end
    end
    local ok2, kids = pcall(function() return { f:GetChildren() } end)
    for _, c in ipairs(ok2 and kids or {}) do CountDrawn(c, n) end
    return n
end

-- on the map canvas, by layer: our named frames (ns.debugFrames), pins by
-- template, the game's art; then our named frames off the canvas
local function DrawnByLayer(map)
    local canvas, names, by = map:GetCanvas(), {}, {}
    for name, f in pairs(ns.debugFrames) do names[f] = name end
    local all = CountDrawn(canvas)
    local function Add(key, f)
        local n = by[key] or { tex = 0, line = 0, text = 0, frames = 0, count = 0 }
        by[key] = n
        n.count = n.count + 1
        CountDrawn(f, n)
    end
    for _, c in ipairs({ canvas:GetChildren() }) do
        Add(names[c] or c.pinTemplate or (c.layerIndex and "game art") or c:GetName() or "other", c)
    end
    for f, name in pairs(names) do
        if f.GetParent and f:GetParent() ~= canvas and f:IsVisible() then Add(name .. " (off canvas)", f) end
    end
    local list = {}
    for key, n in pairs(by) do
        n.layer = key
        if n.tex + n.line + n.text > 0 then list[#list + 1] = n end
    end
    table.sort(list, function(a, b) return a.tex + a.line > b.tex + b.line end)
    local parts = {}
    for i = 1, math.min(14, #list) do
        local n = list[i]
        parts[#parts + 1] = string.format("%s %d%s%s", n.layer, n.tex, n.line > 0 and ("+" .. n.line .. " lines") or "",
            n.count > 1 and (" (" .. n.count .. " frames)") or "")
    end
    return string.format("on the map: %d textures, %d lines, %d texts in %d frames; by layer: %s",
        all.tex, all.line, all.text, all.frames, table.concat(parts, ", ")), list
end

-- errors that reach the game's error handler from our files (even with the
-- error popups turned off)
do
    local prev = geterrorhandler and geterrorhandler()
    if prev and seterrorhandler then
        seterrorhandler(function(msg, ...)
            -- (one already seen: counted, without its stack or the map dump again, so a storm of
            -- them every frame can't run past the game's time limit)
            local m = tostring(msg)
            for _, e in ipairs(errors) do
                if e.msg == m then
                    e.count, e.last = e.count + 1, date("%H:%M:%S")
                    return prev(msg, ...)
                end
            end
            local stack = debugstack and debugstack(2, 12, 0) or ""
            if tostring(msg):find(ns.ADDON, 1, true) or stack:find(ns.ADDON, 1, true) then  -- (our folder in the path)
                pcall(ns.RecordError, msg, stack)
            elseif tostring(msg):find("MapCanvas") then
                -- the game's map code (the stack names no file of ours): what
                -- the scroll area held then, to see which value was missing
                pcall(function()
                    local sc = BattlefieldMapFrame and BattlefieldMapFrame.ScrollContainer
                    local vals = {}
                    if sc then
                        for k, v in pairs(sc) do
                            if type(v) == "number" or type(v) == "boolean" then
                                vals[#vals + 1] = k .. "=" .. tostring(type(v) == "number" and math.floor(v * 1000) / 1000 or v)
                            end
                        end
                        local levels = sc.zoomLevels
                        vals[#vals + 1] = "levels=" .. (levels and #levels or 0)
                            .. (levels and levels[1] and string.format(" %.3f-%.3f", levels[1].scale, levels[#levels].scale) or "")
                        vals[#vals + 1] = "canvasScale=" .. tostring(sc:GetCanvasScale())
                        -- the canvas's place on screen (the game measures the cursor from its left)
                        local child = sc.Child
                        if child then
                            local pts = {}
                            for i = 1, child:GetNumPoints() do
                                local p, rel, rp, x, y = child:GetPoint(i)
                                pts[#pts + 1] = string.format("%s>%s %s %s,%s", tostring(p), rel == sc and "scroll" or
                                    (rel and (rel:GetName() or "?") or "nil"), tostring(rp), tostring(x), tostring(y))
                            end
                            vals[#vals + 1] = "child: left " .. tostring(child:GetLeft()) .. " top " .. tostring(child:GetTop())
                                .. " size " .. tostring(child:GetWidth()) .. "x" .. tostring(child:GetHeight())
                                .. " scale " .. tostring(child:GetScale()) .. " points [" .. table.concat(pts, "; ") .. "]"
                        end
                        vals[#vals + 1] = "scroll left " .. tostring(sc:GetLeft())
                    end
                    table.sort(vals)
                    ns.RecordError(msg, stack .. "\nscroll area: " .. table.concat(vals, ", "))
                end)
            end
            return prev(msg, ...)
        end)
    end
end

-- the session's errors go into the saved variables on every reload and logout
local saver = CreateFrame("Frame")
saver:RegisterEvent("PLAYER_LOGOUT")
saver:SetScript("OnEvent", function()
    if ns.db then ns.db.lastErrors = (#errors > 0) and errors or nil end
end)

-- Looking ----------------------------------------------------------------------

-- a frame's place on screen, in screen pixels from the bottom-left
local function Rect(f)
    local l, b, w, h = f:GetRect()
    if not l then return nil end
    local s = f:GetEffectiveScale()
    return { x = math.floor(l * s), y = math.floor(b * s), w = math.floor(w * s), h = math.floor(h * s) }
end

local function Dump(f)
    if not f then return nil end
    return {
        shown = f:IsShown(), visible = f:IsVisible(),
        alpha = math.floor((f.GetEffectiveAlpha and f:GetEffectiveAlpha() or f:GetAlpha()) * 100) / 100,
        level = f:GetFrameLevel(), strata = f:GetFrameStrata(),
        scale = math.floor(f:GetEffectiveScale() * 100) / 100,
        rect = Rect(f),
    }
end

-- is a inside b (screen rects), give or take a few pixels
local function Inside(a, b, slack)
    if not (a and b) then return false end
    slack = slack or 4
    return a.x >= b.x - slack and a.y >= b.y - slack
       and a.x + a.w <= b.x + b.w + slack and a.y + a.h <= b.y + b.h + slack
end

function ns.RunCheck(noReload)
    local map = BattlefieldMapFrame
    local checks, frames, pins, costDrawn = {}, {}, {}, nil
    local function Check(name, ok, detail)
        checks[#checks + 1] = { name = name, ok = ok and true or false, detail = detail }
    end

    if not map then
        Check("map loaded", false, "BattlefieldMapFrame doesn't exist yet: open the map once")
    else
        local scroll, canvas = map.ScrollContainer, map:GetCanvas()
        local bf = map.BorderFrame
        frames.map, frames.scroll, frames.canvas = Dump(map), Dump(scroll), Dump(canvas)
        frames.blizzBorder, frames.close, frames.tab = Dump(bf), Dump(bf and bf.CloseButton), Dump(BattlefieldMapTab)
        for name, f in pairs(ns.debugFrames) do frames[name] = Dump(f) end

        Check("map open", map:IsShown())
        -- tooltip size over the map (Pin.lua): the last one scaled, if any
        local tip = ns.lastMapTip
        Check("map tooltips scaled", (ns.db.pins.tipScale or 1) == 1 or tip ~= nil,
            string.format("setting %.2f; last %s", ns.db.pins.tipScale or 1,
                tip and string.format("%s, by %s, tooltip scale %.2f", tostring(tip.owner), tip.how or "?", tip.scale)
                    or "none since login (hover a pin first)"))

        -- layer order: the art under the pins, and our art layers too
        local explore, top, bottom = ns.CanvasLevels(map)
        local cl = canvas:GetFrameLevel()
        Check("map art under the pins", not bottom or cl < bottom,
            string.format("canvas %d, explored art %s, pins %s to %d", cl, tostring(explore), tostring(bottom), top))
        for _, name in ipairs({ "unexplored", "flash", "detail" }) do
            local f = ns.debugFrames[name]
            if f then
                Check(name .. " layer under the pins", not bottom or f:GetFrameLevel() < bottom,
                    "level " .. f:GetFrameLevel() .. ", lowest pin " .. tostring(bottom))
            end
        end
        Check("scroll area at a normal level", scroll and scroll:GetFrameLevel() <= map:GetFrameLevel() + 30,
            string.format("scroll %d, map %d", scroll and scroll:GetFrameLevel() or -1, map:GetFrameLevel()))

        -- the gear and the toggle buttons
        local gear, strip = ns.debugFrames.gear, ns.debugFrames.toggleStrip
        local mapRect = Rect(map)
        -- (collapsed, Collapse.lua: the buttons are meant to be hidden)
        local collapsed = ns.MapCollapsed and ns.MapCollapsed()
        if collapsed then
            Check("map collapsed (info)", true, "buttons hidden on purpose, not checked; " .. tostring(ns.collapseTrim))
        end
        local buttons = ns.db.mapButtons ~= false and not collapsed
        if gear and buttons and ns.db.quickButton then
            Check("gear shown", gear:IsVisible())
            Check("gear over the map art", gear:GetFrameLevel() > cl, "gear " .. gear:GetFrameLevel() .. ", canvas " .. cl)
            Check("gear on the map", Inside(Rect(gear), mapRect, 12))
        end
        if strip and buttons and ns.db.quickToggles ~= false then
            local n = 0
            for id, on in pairs(ns.db.toggles.list) do if on then n = n + 1 end end
            Check("toggle buttons shown", strip:IsVisible() and n > 0, n .. " picked")
            Check("toggle buttons over the map art", strip:GetFrameLevel() > cl, "strip " .. strip:GetFrameLevel() .. ", canvas " .. cl)
            -- (placed outside the map: just beyond its edge, within a button's size)
            local outside = ns.db.toggles.side == "outside"
            local slack = outside and ((ns.db.toggles.size or 18) + 16) or 12
            Check(outside and "toggle buttons beside the map" or "toggle buttons on the map",
                Inside(Rect(strip), mapRect, slack))
            if ns.db.toggles.fadeOut then
                Check("toggle buttons fade (info)", true,
                    "they fade to " .. tostring(ns.db.toggles.fadeAlpha) .. "% off the map; alpha now " .. string.format("%.2f", strip:GetEffectiveAlpha()))
            end
        end

        -- the header
        local header = ns.debugFrames.header
        if header and ns.IsShown("zoneName") and map:IsShown() then
            Check("header shown", header:IsVisible())
            local hl = header:GetFrameLevel()
            local over = bf and bf:GetFrameLevel() or 0
            if bf and bf.CloseButton then over = math.max(over, bf.CloseButton:GetFrameLevel()) end
            if ns.debugFrames.border and ns.debugFrames.border:IsShown() then over = math.max(over, ns.debugFrames.border:GetFrameLevel()) end
            Check("header over the borders", hl > over, "header " .. hl .. ", borders up to " .. over)
            local hr, sr = Rect(header), Rect(scroll)
            local mode = ns.db.zoneName.mode
            if hr and sr then
                local ok
                if mode == "inside" then ok = Inside(hr, sr, 4)
                elseif mode == "below" then ok = hr.y + hr.h <= sr.y + 30
                else ok = hr.y >= sr.y + sr.h - 30 end
                -- (info only: overlapping the edge on purpose is allowed, and liked)
                Check("header position (info)", true,
                    string.format("%s, %s: header y %d-%d, map area y %d-%d", tostring(mode),
                        ok and "within its place" or "over the map's edge", hr.y, hr.y + hr.h, sr.y, sr.y + sr.h))
            end
        end

        -- pins per layer, and whether the layers you show have any
        ns.EachPin(map, function(pin, template)
            local g = (ns.PinGroupOf and ns.PinGroupOf(pin, template)) or template
            pins[g] = (pins[g] or 0) + 1
        end)
        local shownEmpty = {}
        for _, g in ipairs({ "questie", "turnins", "spots", "townsfolk", "rares", "party" }) do
            if ns.db[g] and ns.IsShown(g) and not pins[g] then shownEmpty[#shownEmpty + 1] = g end
        end
        Check("shown layers have pins (info)", true,
            #shownEmpty == 0 and "all have some" or ("none here for: " .. table.concat(shownEmpty, ", ")))

        if ns.GatherInfo then Check("gathering nodes (info)", true, ns.GatherInfo()) end

        Check("sharp map art (info)", true, string.format("%d art pieces made sharp (%s, addon %s)",
            ns.sharpTiles or 0, ns.db.detail.sharpArt and "on" or "off",
            (ns.MapArtAvailable and ns.MapArtAvailable()) and "installed" or "missing"))

        -- (every game function the addon calls, from tools; a client patch can drop one,
        -- and nothing else says so until the line that calls it runs)
        local gone = {}
        for name in ("BreakUpLargeNumbers CanMerchantRepair ClearOverrideBindings CombatLogGetCurrentEventInfo CreateColor CreateFrame CreateFromMixins CreateVector2D FormatLargeNumber GetAbandonQuestName GetAvailableLevel GetAvailableQuestInfo GetAvailableTitle GetBindingKey GetBindingText GetBuildInfo GetCVar GetCoinTextureString GetCurrentBindingSet GetCursorPosition GetGameTime GetInstanceInfo GetItemIcon GetItemInfo GetItemQualityColor GetLocale GetLootSourceInfo GetMaxPlayerLevel GetMerchantItemInfo GetMerchantItemLink GetMerchantNumItems GetMinimapZoneText GetMouseFoci GetMouseFocus GetNumAvailableQuests GetNumGroupMembers GetNumQuestLeaderBoards GetNumQuestLogEntries GetNumQuestWatches GetNumSkillLines GetNumSubgroupMembers GetNumTrackingTypes GetNumTrainerServices GetPhysicalScreenSize GetPlayerFacing GetProfessionInfo GetProfessions GetQuestDifficultyColor GetQuestGreenRange GetQuestID GetQuestLogChoiceInfo GetQuestLogIndexByID GetQuestLogLeaderBoard GetQuestLogPushable GetQuestLogSelection GetQuestLogTitle GetRealZoneText GetRealmName GetSkillLineInfo GetSpellInfo GetSpellLink GetSubZoneText GetTime GetTitleText GetTrackingInfo GetTrackingTexture GetUnitSpeed GetZonePVPInfo GetZoneText HandleModifiedItemClick HideUIPanel InCombatLockdown IsAltKeyDown IsControlKeyDown IsInGroup IsInInstance IsInRaid IsIndoors IsModifiedClick IsModifierKeyDown IsMouseButtonDown IsPlayerSpell IsQuestFlaggedCompleted IsQuestWatched IsResting IsShiftKeyDown IsSpellKnown IsTradeskillTrainer PlaySound QuestLogPushQuest ReloadUI RemoveQuestWatch SaveBindings Screenshot SelectQuestLogEntry SetAbandonQuest SetBinding SetCVar SetOverrideBindingClick ShowUIPanel ToggleBattlefieldMap UnitAffectingCombat UnitCanAttack UnitClass UnitExists UnitFactionGroup UnitGUID UnitHealth UnitHealthMax UnitInParty UnitInRaid UnitIsConnected UnitIsDead UnitIsDeadOrGhost UnitIsPlayer UnitIsUnit UnitLevel UnitName UnitOnTaxi UnitPosition UnitRace UnitSex"):gmatch("%S+") do
            if _G[name] == nil and ns[name] == nil then gone[#gone + 1] = name end
        end
        Check("game functions (info)", true, #gone == 0 and "all there" or ("missing here: " .. table.concat(gone, ", ")))

        Check("client (info)", true, ns.CLIENT .. ", interface " .. tostring(ns.INTERFACE)
            .. ", edition " .. tostring(ns.EDITION) .. ", maps " .. ns.MapEdition()
            .. (ns.ForeverMapDev() and " (dev, /waymark forevermap)" or ""))
        -- Forever's art on a stand-in comes from the dev-only Waymark_DevArt (Art.lua)
        if ns.FOREVER and ns.CheckAllArt then ns.CheckAllArt() end
        local dev, missing = WaymarkDevArt, {}
        for name, why in pairs(ns.artMissing) do missing[#missing + 1] = tostring(name) .. " (" .. tostring(why) .. ")" end
        table.sort(missing)
        local nA, nF = 0, 0
        if dev then
            for _ in pairs(dev.atlas) do nA = nA + 1 end
            for _ in pairs(dev.files) do nF = nF + 1 end
        end
        local subs, nDev, nGame = {}, 0, 0
        for name, from in pairs(ns.artFrom) do
            if from == "substitute" then subs[#subs + 1] = tostring(name)
            elseif from == "dev copy" then nDev = nDev + 1
            else nGame = nGame + 1 end
        end
        table.sort(subs)
        Check("Forever art", #missing == 0 and not (ns.FOREVER and #subs > 0), (ns.FOREVER and "the game's own"
            or not ns.UsingSubstitutes() and string.format("dev copies: %d atlases, %d files (build %s)", nA, nF, tostring(dev.build))
            or (dev and "dev art off (/waymark devart): " or "no Waymark_DevArt: ")
                .. "substitutes, as an Era-only player sees it")
            .. string.format("; in use: %d game, %d dev copy, %d substitute", nGame, nDev, #subs)
            .. (#subs > 0 and (" (" .. table.concat(subs, ", ") .. ")") or "")
            .. (#missing > 0 and ("; missing: " .. table.concat(missing, ", ")) or ""))

        -- town or city view, and the zoom it's at
        local sc = map.ScrollContainer
        Check("town / city view (info)", true, string.format("map %s, %s (town view %s), zoom %.2f",
            tostring(map:GetMapID()),
            (ns.InCityView and ns.InCityView()) and "city view" or (ns.InTownView and ns.InTownView()) and "town view" or "neither",
            ns.db.townView.enabled and "on" or "off",
            sc and sc.GetCanvasScale and sc:GetCanvasScale() or 0))

        if ns.ZoneArtInfo then Check("zone maps on the continent (info)", true, ns.ZoneArtInfo()) end
        if ns.TrackerInfo then Check("quest tracker (info)", true, ns.TrackerInfo()) end
        if ns.DockInfo and ns.db.dock.on then Check("minimap replacement (info)", true, ns.DockInfo()) end
        if ns.DockPatchInfo and ns.db.dock.on then Check("patch of blips (info)", true, ns.DockPatchInfo()) end
        if ns.DockGeometry and ns.db.dock.on then Check("minimap and view places (info)", true, ns.DockGeometry()) end
        if ns.DockMouseFrames and ns.db.dock.on then Check("moved frames with the mouse (info)", true, ns.DockMouseFrames()) end
        if ns.QuestWindowInfo then Check("quest log window (info)", true, ns.QuestWindowInfo()) end
        -- a dungeon's floor on the map (Dungeon.lua): which, its pins (DungeonObjects.lua), the found
        -- notes' route and stairs on it (Data\FoundNotes.lua), and the header naming it (ZoneName.lua)
        local floorName, counter = ns.DungeonFloorTitle and ns.DungeonFloorTitle()
        if floorName then
            local _, key = ns.DungeonInkSurface()
            local inst, fl = (key or ""):match("^d(%d+):(%d+)$")
            local routes, stairs = 0, 0
            for _, dg in ipairs(ns.FoundNotes or {}) do
                if dg.instance == tonumber(inst) then
                    for _, m in ipairs(dg.mapMarks and dg.mapMarks[tonumber(fl)] or {}) do
                        if m.t == "route" then routes = routes + 1 elseif m.t == "stairs" then stairs = stairs + 1 end
                    end
                end
            end
            Check("dungeon map (info)", true, string.format("%s %s (%s), %s; pins %d (%s); route strokes %d, stairs %d",
                floorName, counter or "", tostring(key), ns.DungeonPreviewing and ns.DungeonPreviewing() and "opened from its entrance" or "inside",
                ns.DungeonObjectsShown and ns.DungeonObjectsShown() or 0, tostring(ns.db.dungeon.objects), routes, stairs))
            local header = ns.debugFrames.header
            if ns.IsShown("zoneName") then
                Check("dungeon floor named in the header", header and header:IsVisible() and true or false, floorName)
            end
        end
        -- where the game says you are inside an instance (for showing the room you're in): the floor
        -- map, any position it still gives, and the room's name (subzone, minimap zone text)
        if IsInInstance() then
            local m = C_Map.GetBestMapForUnit("player")
            local pos = m and C_Map.GetPlayerMapPosition(m, "player")
            local y, x, z, inst = UnitPosition("player")
            local okF, facing = pcall(GetPlayerFacing)
            Check("where you are inside (info)", true, string.format("map %s, map position %s, world %s, facing %s, sub zone %q, minimap zone %q, zone %q",
                tostring(m), pos and string.format("%.3f, %.3f", pos.x, pos.y) or "none",
                y and string.format("%.1f, %.1f, %.1f (%s)", x, y, z or 0, tostring(inst)) or "none",
                okF and type(facing) == "number" and string.format("%.2f", facing) or "none",
                GetSubZoneText() or "", GetMinimapZoneText() or "", GetRealZoneText() or ""))
            if ns.DungeonWhereInfo then Check("where you are, guessed (info)", true, ns.DungeonWhereInfo()) end
            -- what the game says of how far things are, inside: your target and the soft targets
            -- (an object the soft-target picks is a few steps away: chests, levers, quest pick-ups)
            local near = {}
            for _, u in ipairs({ "target", "softenemy", "softinteract", "softfriend" }) do
                local okE, exists = pcall(UnitExists, u)
                local okG, g = pcall(UnitGUID, u)
                if okG and issecretvalue and issecretvalue(g) then g = true end
                if okE and issecretvalue and issecretvalue(exists) then exists = true end
                if okE and (exists or (okG and g)) then                -- (an object: no unit, but a GUID and a name)
                    -- (inside on Forever a GUID or name can be secret: shown as such, never indexed)
                    local guid = UnitGUID(u)
                    guid = (issecretvalue and issecretvalue(guid)) and "secret-" or guid or ""
                    local name = UnitName(u)
                    name = (issecretvalue and issecretvalue(name)) and "secret" or name or "?"
                    local ranges = {}
                    for i = 1, 4 do
                        local ok, r = pcall(CheckInteractDistance, u, i)
                        ranges[i] = ok and (r and "y" or "n") or "x"
                    end
                    local okD, d2, checked = pcall(UnitDistanceSquared, u)
                    if okD and (ns.Known(d2) == nil or ns.Known(checked) == nil) then okD = false end
                    local spells = {}
                    for _, s in ipairs({ "Auto Shot", "Arcane Shot", "Scatter Shot", "Wing Clip", "Raptor Strike", "Attack" }) do
                        local ok, r = pcall(IsSpellInRange, s, u)
                        if ok and ns.Known(r) ~= nil then spells[#spells + 1] = s .. "=" .. tostring(r) end
                    end
                    near[#near + 1] = string.format("%s %q (%s) interact 1-4 %s, distance %s, spells %s", u, name,
                        guid:match("^[^-]+") or "?", table.concat(ranges), okD and checked and string.format("%.1f", math.sqrt(d2)) or "none",
                        #spells > 0 and table.concat(spells, " ") or "none")
                else
                    near[#near + 1] = u .. (okE and " none" or " (no such unit here)")
                end
            end
            local cv = {}
            for _, c in ipairs({ "SoftTargetInteract", "SoftTargetEnemy", "SoftTargetFriend", "SoftTargetInteractRange", "nameplateMaxDistance" }) do
                local ok, v = pcall(GetCVar, c)
                cv[#cv + 1] = c .. "=" .. tostring(ok and v or "x")
            end
            near[#near + 1] = "settings " .. table.concat(cv, " ")
            Check("how far things are, inside (info)", true, table.concat(near, "; "))
        end
        if ns.QuestDataInfo then Check("quest data", ns.QuestSource() ~= nil, ns.QuestDataInfo(map:GetMapID())) end
        if ns.QuestGroundInfo then Check("quest ground (info)", true, ns.QuestGroundInfo()) end
        if ns.QuestTargetsInfo then Check("quests in the log, their places (info)", true, ns.QuestTargetsInfo(map:GetMapID())) end
        if ns.WildsInfo then Check("rares & chests (info)", true, ns.WildsInfo()) end

        -- zoom as art on screen (MapControls' ArtX): where it is, its range, and
        -- whether full detail can be reached
        if ns.ArtX and ns.ZoomRange and sc then
            local lo, hi = ns.ZoomRange(sc)
            local x = ns.ArtX(map)
            local k = lo and x / sc:GetCanvasScale() or 0
            local d = ns.db.detail
            Check("zoom and detail (info)", true,
                string.format("art %.2fx now, range %.2fx-%.2fx (closest set %.1fx), detail from %.1fx full %.1fx closer, fade %.2f, %d levels, map %dx%d scale %.2f",
                    x, (lo or 0) * k, (hi or 0) * k, ns.db.zoom.closestX or 0, d.fromZoom or 0, d.fullZoom or 0,
                    ns.DetailFade and ns.DetailFade(map) or -1, sc.zoomLevels and #sc.zoomLevels or 0,
                    map:GetWidth(), map:GetHeight(), map:GetScale()))
        end

        -- townsfolk: merged pins, and what's been learned
        local merged = 0
        ns.EachPin(map, function(pin, template)
            if template == "BFITownsfolkPinTemplate" and pin.info and pin.info.members and #pin.info.members > 1 then
                merged = merged + 1
            end
        end)
        local known, here = 0, 0
        if ns.LearnedTownsfolkStats then known, here = ns.LearnedTownsfolkStats() end
        Check("townsfolk (info)", true, string.format("%d pins (%d merged, within %d yd); learned %d, %d on this map, shown: %s",
            pins.townsfolk or 0, merged, ns.db.townsfolk.mergeYards or 0, known, here,
            ns.db.townsfolk.useLearned and "yes" or "no"))

        if ns.ExploreInfo then
            local shown, total = 0, 0
            ns.EachPin(map, function(pin, template)
                if template == "MapExplorationPinTemplate" then
                    for _, r in ipairs({ pin:GetRegions() }) do
                        if r:IsObjectType("Texture") then
                            total = total + 1
                            if r:IsVisible() and r:GetTexture() then shown = shown + 1 end
                        end
                    end
                end
            end)
            Check("explored areas (info)", true, string.format("%s; game's explored art: %d of %d textures shown",
                ns.ExploreInfo(map:GetMapID()), shown, total))
        end

        -- what the map costs: textures drawn per layer, and our code's time a frame
        local okD, drawnLine, drawnList = pcall(DrawnByLayer, map)
        Check("drawn on the map (info)", true, okD and drawnLine or ("count failed: " .. tostring(drawnList)))
        if okD then costDrawn = drawnList end

        -- nothing near the top frame level (the game caps them at 10000)
        local high = {}
        for name, d in pairs(frames) do
            if d and d.level and d.level > 9000 then high[#high + 1] = name .. " " .. d.level end
        end
        Check("frame levels clear of the cap", #high == 0, table.concat(high, ", "))
    end

    local costLine, costList = FrameCost()
    Check("frame cost (info)", true, costLine)
    -- (each check starts the count over and the next one replaces diag: the last 10 lines kept)
    local costLog = ns.db.costLog or {}
    ns.db.costLog = costLog
    table.insert(costLog, string.format("%s map %s: %s", date("%H:%M:%S"), tostring(map and map:GetMapID()), costLine))
    while #costLog > 10 do table.remove(costLog, 1) end

    Check("no Lua errors this session", #errors == 0, #errors .. " different errors")

    local failed = {}
    for _, c in ipairs(checks) do if not c.ok then failed[#failed + 1] = c.name end end
    local mapID = map and map:GetMapID()
    ns.db.diag = {
        at = date("%Y-%m-%d %H:%M:%S"),
        zone = (GetZoneText and GetZoneText() or "") .. " / " .. (GetSubZoneText and GetSubZoneText() or ""),
        mapID = mapID, mapScale = map and map:GetScale(), uiScale = UIParent:GetEffectiveScale(), addonScale = ns.AddonScale(),
        screen = { GetPhysicalScreenSize and GetPhysicalScreenSize() },
        profile = ns.ActiveProfileKey and ns.ActiveProfileKey() or nil,
        checks = checks, frames = frames, pins = pins, errors = errors,
        problems = #failed,
        view = ns.ViewInfo and ns.ViewInfo() or nil,
        cost = costList, drawn = costDrawn,
    }

    ns.Log(string.format("check: %d checks, %d problem%s%s", #checks, #failed, #failed == 1 and "" or "s",
        #failed > 0 and (": " .. table.concat(failed, "; ")) or ""))
    -- (the game blocks an addon's reload unless it's straight from a key press, so
    -- the /reload that writes the file is yours)
    C_Timer.After(0.4, function() Screenshot() end)
    ns.Log("screenshot taken. Now /reload so the results are saved.")
end
