local _, ns = ...

-- /bfi tour: a dev aid for checking the continent art in the real game. The map goes
-- to each spot of SPOTS in turn (its continent, centred there, zoomed in), waits for
-- the art to load, and takes a screenshot; each spot's name and time go into
-- WaymarkDB.tour, so tools\tour_shots.py (after a /reload) can name the
-- screenshots and lay them on one sheet.
--   /bfi tour          every spot, zoomed about as close as a zone map's own view
--   /bfi tour far      ... further out;  /bfi tour close  ... closer in
--   /bfi tour <word>   only the spots whose name has <word> in it (and far / close too)
--   /bfi tour stop     stops it

-- { name, continent, x, y } (0-1 of the continent's map)
local SPOTS = {
    { "gilneas coast", 1415, 0.4350, 0.3940 },
    { "east coast fill", 1415, 0.6150, 0.5200 },
    { "loch modan top", 1415, 0.5471, 0.5183 },
    { "redridge", 1415, 0.5331, 0.7144 },
    { "badlands searing", 1415, 0.5204, 0.6090 },
    { "duskwood deadwind", 1415, 0.4929, 0.7738 },
    { "burning steppes redridge", 1415, 0.5238, 0.6923 },
    { "elwynn north", 1415, 0.4602, 0.6644 },
    { "stormwind", 1415, 0.4303, 0.6836 },
    { "westfall coast", 1415, 0.3887, 0.7685 },
    { "great sea labels", 1415, 0.3738, 0.7386 },
    { "stv north coast", 1415, 0.4368, 0.8394 },
    { "riverglades", 1415, 0.5496, 0.6489 },
    { "quel thalas", 1415, 0.5800, 0.1100 },
    { "arathi hinterlands", 1415, 0.5404, 0.3445 },
    -- /bfi tour sea: the open sea work (zone maps faded past their hatching and handed over
    -- to a neighbour near their sides; the sea fill under them; Quel'Thalas's new coast)
    { "sea arathi wetlands seam", 1415, 0.5550, 0.4200 },
    { "sea tirisfal north", 1415, 0.4500, 0.1600 },
    { "sea silverpine west", 1415, 0.3850, 0.3000 },
    { "sea quel thalas coast", 1415, 0.5800, 0.1150 },
    { "sea hillsbrad bay", 1415, 0.4640, 0.3980 },
    { "sea wetlands west", 1415, 0.4550, 0.4650 },
    { "sea dun morogh north", 1415, 0.4500, 0.4880 },
    { "sea hinterlands east", 1415, 0.6000, 0.3100 },
}
-- /bfi tour sweep far: both continents in a grid, a far view's width apart (for the
-- glaring issues: every coast and seam once)
for _, cont in ipairs({ { "ek", 1415 }, { "kalimdor", 1414 } }) do
    for _, y in ipairs({ 0.15, 0.35, 0.55, 0.75, 0.90 }) do
        for _, x in ipairs({ 0.42, 0.58 }) do
            SPOTS[#SPOTS + 1] = { string.format("sweep %s %02d %02d", cont[1], y * 100, x * 100), cont[2], x, y }
        end
    end
end
-- (how much of the continent's width fits across the view: a share of the zoom range went
-- far too close once the continent could zoom on into each zone's own map)
local ZOOM = { far = 0.25, normal = 0.12, close = 0.06 }
local SETTLE = 2.5     -- seconds at a spot before the shot (the art's tiles load)
local AFTER = 1.0      -- ... and after it

local running

local function Shoot(list, i, zoom)
    if running ~= list then return end
    local spot = list[i]
    local map = BattlefieldMapFrame
    if not spot or not (map and map:IsShown()) then
        running = nil
        ns.Log(spot and "Tour: the map closed, stopped." or
            string.format("Tour: %d shots. /reload, then: python -I tools\\tour_shots.py", #list))
        return
    end
    -- (through Browse: a plain SetMapID to the other continent was put back on the player's)
    if map:GetMapID() ~= spot[2] then
        if ns.BrowseTo then ns.BrowseTo(spot[2]) else map:SetMapID(spot[2]) end
    end
    C_Timer.After(0.3, function()
        if running ~= list then return end
        local sc = map.ScrollContainer
        local cw = sc and sc.Child and sc.Child:GetWidth()
        if cw and cw > 0 and ns.ApplyMapView then
            ns.ApplyMapView(sc, sc:GetWidth() / (cw * zoom), spot[3], spot[4])
        end
        C_Timer.After(SETTLE, function()
            if running ~= list then return end
            local db = WaymarkDB
            db.tour = db.tour or {}
            db.tour[#db.tour + 1] = { name = spot[1], at = time(), cont = spot[2], x = spot[3], y = spot[4], zoom = zoom }
            Screenshot()
            C_Timer.After(AFTER, function() Shoot(list, i + 1, zoom) end)
        end)
    end)
end

function ns.RunTour(args)
    args = (args or ""):lower()
    if args == "stop" then
        running = nil
        ns.Log("Tour: stopped.")
        return
    end
    local map = BattlefieldMapFrame
    if not (map and map:IsShown()) then ns.Log("Tour: open the map first.") return end
    local zoom = ZOOM.normal
    local words = {}
    for w in args:gmatch("%S+") do
        if ZOOM[w] then zoom = ZOOM[w] else words[#words + 1] = w end
    end
    local list = {}
    for _, s in ipairs(SPOTS) do
        local ok = #words == 0
        for _, w in ipairs(words) do
            if s[1]:find(w, 1, true) then ok = true end
        end
        if ok then list[#list + 1] = s end
    end
    if #list == 0 then ns.Log("Tour: no spot by that name.") return end
    WaymarkDB.tour = {}  -- (this tour's list only)
    running = list
    ns.Log(string.format("Tour: %d spots, about %d s. Keep the mouse off the map. /waymark tour stop to stop.",
        #list, math.ceil(#list * (SETTLE + AFTER + 0.3))))
    Shoot(list, 1, zoom)
end

-- An unattended tour (dev, tools\overnight.py: Data\AutoTour.lua): after every /reload or
-- login its spots are toured by themselves, so one key bound to /reload is all a night of
-- bake, reload, look needs. Empty file: nothing happens.
local auto = CreateFrame("Frame")
auto:RegisterEvent("PLAYER_ENTERING_WORLD")
auto:SetScript("OnEvent", function()
    local a = ns.AutoTour
    if not (a and a.spots and a.spots[1]) then return end
    C_Timer.After(a.wait or 8, function()
        local map = BattlefieldMapFrame
        if map and not map:IsShown() then map:Show() end
        if not (map and map:IsShown()) then ns.Log("Auto tour: no map.") return end
        WaymarkDB.tour = {}
        WaymarkDB.autoTourRan = a.stamp
        running = a.spots
        Shoot(a.spots, 1, a.zoom or ZOOM.normal)
    end)
end)
