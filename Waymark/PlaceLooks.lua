local _, ns = ...

-- A look for each place the map lives. The map's header and border are one set of settings (ns.db.zoneName,
-- ns.db.border, and Frames.lua's frame set for each), but the right ones differ by place: a parchment header
-- inside a bronze frame as a window, a bare name in clear view, a name pushed up over the square in the
-- minimap's place. The presets carried those differences; switching place by hand did not, so the look had to
-- be tuned again each time. The user, 2026-11-15, on the Header & borders tab: "It depends on which window you
-- want to use at that time what you choose ect. Prune it, make it better."
--
-- So: each place keeps its own. When the place changes (the settings' three choices, the dock's key, clear
-- view's key, the map's own buttons), the look in use is put away under the place just left and the new place's
-- look is brought out. A place never been to starts from the preset made for it (START). The drawing code is
-- unchanged: it reads the same settings as ever.
--
-- ns.db.placeLooks = { at = "window" | "clear" | "dock", looks = { [place] = { border = {...}, zoneName = {...},
-- frames = { border, header } } } }. The place the map is in has no entry: its look is the live settings.
--   A preset or a saved setup being applied (ns.keepSizeOff, Setups.lua) brings a look of its own for the place
--   it puts the map in: that is kept as it comes, and any look put away for that place is dropped.
--   Settings from before this (a player who has seen the welcome page): the look they have is put away for the
--   other two places as well, so nothing changes for them until they choose a look for a place.

local PLACES = { "window", "clear", "dock" }
local START = { window = "simple", clear = "minimalist", dock = "navigator" }
local GROUPS = { "border", "zoneName" }
local FRAME_PARTS = { "border", "header" }

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function Role()
    local d = ns.db
    return d.dock and d.dock.on and "dock" or d.clearView and d.clearView.on and "clear" or "window"
end

-- the look in use, as a table of its own
local function Take()
    local t = {}
    for _, g in ipairs(GROUPS) do t[g] = Copy(ns.db[g]) end
    if ns.db.frames then
        t.frames = {}
        for _, p in ipairs(FRAME_PARTS) do t.frames[p] = ns.db.frames[p] end
        -- (the header style a frame set's header put away, Frames.lua: the place's own, or it came back in a
        -- place whose look has no frame set: Engraver's corners in a window, then docked, gave the minimap's
        -- place the window's parchment)
        t.frames.headerWas = ns.db.frames.headerWas
    end
    return t
end

-- a place's first look: its preset's
local function Start(place)
    local p = ns.PRESET_SETTINGS and ns.PRESET_SETTINGS[START[place]]
    if not p then return nil end
    local t = { frames = {} }
    for _, g in ipairs(GROUPS) do t[g] = Copy(p[g]) end
    for _, part in ipairs(FRAME_PARTS) do t.frames[part] = p.frames and p.frames[part] or "keep" end
    return t
end

-- a look into use: every setting of the two groups as the look has it (a setting newer than the look: its
-- default), and each part told
local function Put(t)
    for _, g in ipairs(GROUPS) do
        if type(t[g]) == "table" then
            local live = ns.db[g] or {}
            for k in pairs(live) do
                if t[g][k] == nil then live[k] = nil end
            end
            for k, v in pairs(t[g]) do live[k] = Copy(v) end
            if ns.CopyDefaults and ns.DEFAULTS and type(ns.DEFAULTS[g]) == "table" then ns.CopyDefaults(live, ns.DEFAULTS[g]) end
            ns.db[g] = live
        end
    end
    if t.frames and ns.db.frames then
        for _, p in ipairs(FRAME_PARTS) do
            if t.frames[p] ~= nil then ns.db.frames[p] = t.frames[p] end
        end
        ns.db.frames.headerWas = t.frames.headerWas
    end
    for _, g in ipairs(GROUPS) do pcall(ns.OnSettingChanged, g) end
    if ns.db.frames then pcall(ns.OnSettingChanged, "frames") end
end

local busy
local function Check()
    if busy or not ns.db then return end
    local store = ns.db.placeLooks
    if type(store) ~= "table" or type(store.looks) ~= "table" then
        store = { at = Role(), looks = {} }
        ns.db.placeLooks = store
        if ns.db.welcome and ns.db.welcome.done then
            for _, place in ipairs(PLACES) do
                if place ~= store.at then store.looks[place] = Take() end
            end
        end
        return
    end
    local now = Role()
    if now == store.at then return end
    if ns.keepSizeOff then   -- (a preset or a setup: the look it brings is this place's)
        store.looks[now] = nil
        store.at = now
        return
    end
    busy = true
    store.looks[store.at] = Take()
    store.at = now
    local t = store.looks[now] or Start(now)
    store.looks[now] = nil
    if t then
        local ok, err = pcall(Put, t)
        if not ok and ns.Log then ns.Log("Place looks:", tostring(err)) end
    end
    busy = nil
    if ns.RefreshControls then ns.RefreshControls() end
end
ns.PlaceLooksCheck = Check

-- A built-in preset has just been applied (Setups.lua ns.ApplyPreset): it sets up the whole map, the other two
-- places with it. Purist and the Creator's are one look wherever the map goes (the game's own plate and border;
-- no header at all): their look is put away for the other places too. Any other preset: the other places go
-- back to their first looks, so nothing of the preset before lingers there. (The user, 2026-11-15: "sure".)
local ONE_LOOK = { purist = true, creator = true }
function ns.PlaceLooksPreset(id)
    if not ns.db then return end
    Check()
    local store = ns.db.placeLooks
    if type(store) ~= "table" or type(store.looks) ~= "table" then return end
    store.at = Role()
    for _, place in ipairs(PLACES) do
        if place == store.at then
            store.looks[place] = nil
        elseif ONE_LOOK[id] then
            store.looks[place] = Take()
        else
            store.looks[place] = nil
        end
    end
end

-- Ready-made looks: a header and a border that go together, for the place the map is in. The settings' first
-- choice on Header & border; each part can still be set by hand under it.
-- A look names every part of how it looks (the map border's style, colour, thickness, distance; the header's style and
-- its border's), so picking it again puts back what was changed by hand (the user, 2026-11-15: "not switching back
-- individual choices i made when i reselect it"). A boxed header (parchment, plate, tooltip) is text size 11, as in
-- every preset's window: the minimap's place has 14 for its plain lettering, too big in a box (the user, 2026-11-15:
-- "Header size is too big in ready-made look classic on the minimaps place"). Plain lettering keeps its size. Where
-- the header sits, its font, nudge and what it says stay the player's. (Under a header border "auto" its colour, thickness and distance draw nothing: they are the
-- presets' values, so the presets' starts still read as the look.)
-- Each look brings the header's nudge too, for "Above the map": the one nudge had been tuned for the parchment
-- header on the bronze frame, and every other look's header sat wrong with it (the user, 2026-11-16, on the clean
-- client: "Only header that is well positioned is Parchment and bronze"; a look keeping the old nudge: "Bug").
-- The numbers are the user's own, set by eye in the window; the minimap's place starts from the same ("works
-- well"). Plain lettering and no header at all name none: the nudge stays as it is.
-- ns.HeaderLookNudge: also for a frame set's header picked as a theme (Frames.lua).
function ns.HeaderLookNudge(y)
    local z = ns.db and ns.db.zoneName
    if not (z and y) then return end
    z.nudges = type(z.nudges) == "table" and z.nudges or {}
    if z.mode == "below" then
        -- (below the map: its own nudge stays; above gets the look's when the player moves it there)
        z.nudges.header = { z.nudges.header and z.nudges.header[1] or 0, y }
        return
    end
    -- (a header still "inside", not yet laid out: turned here, so ZoneName.lua does not measure a turn over it)
    if z.mode == "inside" then
        z.insideWas = { was = z.offsetY or 0, now = y }
        z.nudges.inside = nil
        z.mode = "header"
    elseif type(z.insideWas) == "table" then
        z.insideWas.now = y     -- (still our own doing, not the player's change: Setups.lua Turned)
    end
    z.offsetY = y
end

local MAP = { shown = true, size = 0.6, gap = -2 }
local function Border(style, color, size)
    return { shown = MAP.shown, size = size or MAP.size, gap = MAP.gap, style = style, color = color }
end
local SETS = {
    { "parchment", "Parchment and bronze", nudge = -14,
      -- (the frame round the map a little heavier than the presets' 0.6: the user, 2026-11-15)
      border = Border("dialog", "bronze", 0.75),
      zoneName = { shown = true, style = "parchment", fontSize = 11, border = "dialog", borderColor = "bronze", borderSize = 0.8, borderGap = -6 } },
    { "classic", "Classic", nudge = 0,
      border = Border("game", "natural"),
      zoneName = { shown = true, style = "plate", fontSize = 11, border = "auto", borderColor = "bronze", borderSize = 0.8, borderGap = -6 } },
    { "dark", "Dark", nudge = -11,
      border = Border("tooltip", "dark"),
      -- (the header's border as the user set it: tooltip, dark, 0.8x, 6 px in; 2026-11-15)
      zoneName = { shown = true, style = "tooltip", fontSize = 11, border = "tooltip", borderColor = "dark", borderSize = 0.8, borderGap = -6 } },
    -- (a frame set's corners round the map and the header, as the user set it (2026-11-15). The header's style
    -- under the frame is the set's own: not named. Only in a build that has the set open: Usable.)
    { "engraver", "Engraver's corners", needs = "engraver", nudge = -4,
      border = Border("dialog", "bronze"),
      zoneName = { shown = true, fontSize = 11, border = "auto", borderColor = "natural", borderSize = 0.8, borderGap = -6 },
      frames = { border = "engraver", header = "engraver" } },
    -- (the header as plain lettering, the border left as it is: what clear view and the minimap's place start with)
    { "name", "The name as plain lettering",
      zoneName = { shown = true, style = "text", border = "none" } },
    { "none", "Nothing round the map",
      border = { shown = false }, zoneName = { shown = false } },
}

-- a look whose frame set this build has (or that needs none)
local function Usable(set)
    return not set.needs or (ns.FrameSetOpen and ns.FrameSetOpen(set.needs) and ns.db.frames and true or false)
end

local function Fits(set)
    if not Usable(set) then return false end
    for _, g in ipairs(GROUPS) do
        for k, v in pairs(set[g] or {}) do
            local live = ns.db[g] and ns.db[g][k]
            -- (plain lettering draws no edge of its own: "auto" there is "none")
            if g == "zoneName" and k == "border" and live == "auto" and ns.db.zoneName.style == "text" then live = "none" end
            -- (a number by a slider comes back a hair off: 0.8 saved as 0.800000011920929)
            local same = live == v or (type(v) == "number" and type(live) == "number" and math.abs(live - v) < 0.001)
            if (live and true or false) ~= (v and true or false) or (type(v) ~= "boolean" and not same) then return false end
        end
    end
    if ns.db.frames then
        for _, p in ipairs(FRAME_PARTS) do
            local v = ns.db.frames[p] or "keep"
            if v ~= (set.frames and set.frames[p] or "keep") then return false end
        end
    end
    return true
end

-- { { key, name }, ... }, and "own" last when the look in use is none of them
function ns.PlaceLookChoices()
    local out, any = {}, false
    for _, s in ipairs(SETS) do
        if Usable(s) then
            out[#out + 1] = { s[1], s[2] }
            any = any or Fits(s)
        end
    end
    if not any then out[#out + 1] = { "own", "Your own" } end
    return out
end

function ns.PlaceLookNow()
    for _, s in ipairs(SETS) do
        if Fits(s) then return s[1] end
    end
    return "own"
end

function ns.PlaceLookSet(key)
    for _, s in ipairs(SETS) do
        if s[1] == key and Usable(s) then
            for _, g in ipairs(GROUPS) do
                ns.db[g] = ns.db[g] or {}
                for k, v in pairs(s[g] or {}) do ns.db[g][k] = v end
            end
            if ns.db.frames then
                for _, p in ipairs(FRAME_PARTS) do ns.db.frames[p] = s.frames and s.frames[p] or "keep" end
                -- (a look that names the header's style is that style: not the one a frame set put away, which
                -- Frames.lua would bring back as the set's header comes off)
                if s.zoneName and s.zoneName.style then ns.db.frames.headerWas = nil end
            end
            -- (clear view's own switches stand over a header and a border: a look that shows them lifts those)
            local cv = ns.db.clearView
            if cv and Role() == "clear" then
                if s.zoneName and s.zoneName.shown and cv.header == "hidden" then
                    cv.header = "shown"
                    pcall(ns.OnSettingChanged, "clearView", "header")
                end
                if s.border and s.border.shown and cv.noFrame then
                    cv.noFrame = false
                    pcall(ns.OnSettingChanged, "clearView", "noFrame")
                end
            end
            ns.HeaderLookNudge(s.nudge)
            for _, g in ipairs(GROUPS) do pcall(ns.OnSettingChanged, g) end
            if ns.db.frames then pcall(ns.OnSettingChanged, "frames") end
            return true
        end
    end
    return false
end

-- for /waymark check
function ns.PlaceLooksInfo()
    local store = ns.db and ns.db.placeLooks
    if not store then return "not set up yet" end
    local kept = {}
    for _, place in ipairs(PLACES) do
        if store.looks[place] then kept[#kept + 1] = place end
    end
    return string.format("at %s (the map is in %s), looks put away for: %s; look in use: %s", tostring(store.at), Role(),
        #kept > 0 and table.concat(kept, ", ") or "none", ns.PlaceLookNow())
end

if ns.OnSettingChanged then
    hooksecurefunc(ns, "OnSettingChanged", function(group)
        if group == "dock" or group == "clearView" then Check() end
    end)
end
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    -- (the dock's key and button go straight to ns.ApplyDock, past OnSettingChanged)
    if ns.ApplyDock then hooksecurefunc(ns, "ApplyDock", Check) end
    C_Timer.After(1, Check)   -- (the first time: where the map is now)
end)
