local _, ns = ...

-- /bfi check: the addon looks at itself so Claude can read the result from disk.
-- It checks how the map's layers and our frames sit, counts pins per layer,
-- collects our Lua errors, saves it all to BattlefieldInfoDB.diag and takes a
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
function ns.Safe(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then ns.RecordError(label .. ": " .. tostring(err), debugstack and debugstack(2, 6, 0) or nil) end
    return ok, err
end

-- errors that reach the game's error handler from our files (even with the
-- error popups turned off)
do
    local prev = geterrorhandler and geterrorhandler()
    if prev and seterrorhandler then
        seterrorhandler(function(msg, ...)
            local stack = debugstack and debugstack(2, 12, 0) or ""
            if tostring(msg):find("BattlefieldInfo") or stack:find("BattlefieldInfo") then
                pcall(ns.RecordError, msg, stack)
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
    local checks, frames, pins = {}, {}, {}
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
        local buttons = ns.db.mapButtons ~= false
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
        for _, g in ipairs({ "questie", "turnins", "spots", "townsfolk", "rares", "gather", "party" }) do
            if ns.db[g] and ns.IsShown(g) and not pins[g] then shownEmpty[#shownEmpty + 1] = g end
        end
        Check("shown layers have pins (info)", true,
            #shownEmpty == 0 and "all have some" or ("none here for: " .. table.concat(shownEmpty, ", ")))

        Check("sharp map art (info)", true, string.format("%d art pieces made sharp (%s, addon %s)",
            ns.sharpTiles or 0, ns.db.detail.sharpArt and "on" or "off",
            (ns.MapArtAvailable and ns.MapArtAvailable()) and "installed" or "missing"))

        Check("client (info)", true, ns.CLIENT .. ", interface " .. tostring(ns.INTERFACE)
            .. ", edition " .. tostring(ns.EDITION))
        -- Forever's art on a stand-in comes from the dev-only BattlefieldInfo_DevArt (Art.lua)
        local dev, missing = BattlefieldInfoDevArt, {}
        for name in pairs(ns.artMissing) do missing[#missing + 1] = tostring(name) end
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
        Check("Forever art", #missing == 0, (ns.FOREVER and "the game's own"
            or not ns.UsingSubstitutes() and string.format("dev copies: %d atlases, %d files (build %s)", nA, nF, tostring(dev.build))
            or (dev and "dev art off (/bfi devart): " or "no BattlefieldInfo_DevArt: ")
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
        if ns.QuestWindowInfo then Check("quest log window (info)", true, ns.QuestWindowInfo()) end
        if ns.QuestDataInfo then Check("QuestieDB data", ns.QDB() ~= nil, ns.QuestDataInfo(map:GetMapID())) end

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

        -- nothing near the top frame level (the game caps them at 10000)
        local high = {}
        for name, d in pairs(frames) do
            if d and d.level and d.level > 9000 then high[#high + 1] = name .. " " .. d.level end
        end
        Check("frame levels clear of the cap", #high == 0, table.concat(high, ", "))
    end

    Check("no Lua errors this session", #errors == 0, #errors .. " different errors")

    local failed = {}
    for _, c in ipairs(checks) do if not c.ok then failed[#failed + 1] = c.name end end
    local mapID = map and map:GetMapID()
    ns.db.diag = {
        at = date("%Y-%m-%d %H:%M:%S"),
        zone = (GetZoneText and GetZoneText() or "") .. " / " .. (GetSubZoneText and GetSubZoneText() or ""),
        mapID = mapID, mapScale = map and map:GetScale(), uiScale = UIParent:GetEffectiveScale(),
        screen = { GetPhysicalScreenSize and GetPhysicalScreenSize() },
        profile = ns.ActiveProfileKey and ns.ActiveProfileKey() or nil,
        checks = checks, frames = frames, pins = pins, errors = errors,
        problems = #failed,
        view = ns.ViewInfo and ns.ViewInfo() or nil,
    }

    ns.Log(string.format("check: %d checks, %d problem%s%s", #checks, #failed, #failed == 1 and "" or "s",
        #failed > 0 and (": " .. table.concat(failed, "; ")) or ""))
    -- (the game blocks an addon's reload unless it's straight from a key press, so
    -- the /reload that writes the file is yours)
    C_Timer.After(0.4, function() Screenshot() end)
    ns.Log("screenshot taken. Now /reload so the results are saved.")
end
