local _, ns = ...

-- The map follows the hour (ns.db.mapHour: on). The zone's own art is tinted by the time of day,
-- the clock's time: warm at dawn and dusk, moonlit blue at night, with a lamp round you in the
-- dark. A tint on the art and no sheet over it, so clear view's cut and soft edges stay right.
-- Zone maps only: not continents or dungeon floors. Once a second with the map open, and through
-- the day, with nothing tinted, not even that.

local RATE = 1               -- s between looks at the time and the art

-- hour of the day, colour the art is multiplied by, how dark it is (0 to 1)
local STOPS = {
    { 0, 0.46, 0.52, 0.78, 1 }, { 5, 0.46, 0.52, 0.78, 1 }, { 6.5, 1, 0.92, 0.83, 0.2 }, { 8.5, 1, 1, 1, 0 },
    { 17, 1, 1, 1, 0 }, { 19, 1, 0.89, 0.79, 0.25 }, { 21, 0.46, 0.52, 0.78, 1 }, { 24, 0.46, 0.52, 0.78, 1 },
}

local mapFrame
local pretend                -- an hour to show instead (the Dev page)
local lampHost, lamp
local own = setmetatable({}, { __mode = "k" })  -- [texture] = { its own r, g, b, a, and ours r, g, b }
local tinted = false

local function Cfg() return ns.db.mapHour end

function ns.MapHourNow()
    if pretend then return pretend end
    local c = ns.db.clock
    if c and c.source == "computer" then
        local t = date("*t")
        return t.hour + t.min / 60
    end
    local h, m = GetGameTime()
    return h + m / 60
end

local function Tint(hour)
    for i = 1, #STOPS - 1 do
        local a, b = STOPS[i], STOPS[i + 1]
        if hour >= a[1] and hour <= b[1] then
            local t = (hour - a[1]) / (b[1] - a[1])
            return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t, a[5] + (b[5] - a[5]) * t
        end
    end
    return 1, 1, 1, 0
end

local function Paint(map, r, g, b)
    ns.EachMapArtFrame(map, function(f)
        if f.bfiNoHour then return end
        for _, t in ipairs({ f:GetRegions() }) do
            if t:GetObjectType() == "Texture" then
                local c = own[t]
                local cr, cg, cb, ca = t:GetVertexColor()
                -- (someone else coloured it since, or it's new: that's its own colour now)
                if not c or math.abs(cr - c[5]) + math.abs(cg - c[6]) + math.abs(cb - c[7]) > 0.02 then
                    c = { cr, cg, cb, ca, 0, 0, 0 }
                    own[t] = c
                end
                c[5], c[6], c[7] = c[1] * r, c[2] * g, c[3] * b
                t:SetVertexColor(c[5], c[6], c[7], c[4])
            end
        end
    end)
end

local function Clear(map)
    if tinted then
        tinted = false
        Paint(map, 1, 1, 1)
    end
    if lampHost then lampHost:Hide() end
end

local function Lamp(map, dark)
    if not lampHost then
        local canvas = map:GetCanvas()
        lampHost = CreateFrame("Frame", nil, canvas)
        lampHost:SetAllPoints(canvas)
        lampHost.bfiOwn, lampHost.bfiNoHour = true, true   -- (clear view and soft edges mask it)
        lamp = lampHost:CreateTexture(nil, "OVERLAY")
        lamp:SetTexture(ns.MEDIA .. "Notes\\Glow")
        lamp:SetBlendMode("ADD")
    end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map:GetMapID(), "player")
    if not pos or dark < 0.05 then return lampHost:Hide() end
    local x, y = pos:GetXY()
    local level = ns.ArtLevel(map, 3)
    if lampHost:GetFrameLevel() ~= level then lampHost:SetFrameLevel(level) end
    local canvas = map:GetCanvas()
    local w, h = canvas:GetSize()
    lamp:ClearAllPoints()
    lamp:SetPoint("CENTER", canvas, "TOPLEFT", x * w, -y * h)
    lamp:SetSize(w * 0.2, w * 0.2)
    lamp:SetVertexColor(1, 0.72, 0.38, 0.5 * dark)
    lampHost:Show()
end

local function Update(map)
    if not Cfg().on or ns.Perf("effects") or (ns.MapOnContinent and ns.MapOnContinent()) or not map:IsShown() then return Clear(map) end
    local r, g, b, dark = Tint(ns.MapHourNow())
    if r == 1 and g == 1 and b == 1 then return Clear(map) end
    Paint(map, r, g, b)
    tinted = true
    Lamp(map, dark)
end

function ns.UpdateMapHour()
    if mapFrame then ns.Safe("MapHour", Update, mapFrame) end
end

-- the Dev page: show this hour (nil: the real one)
function ns.MapHourPretend(hour)
    pretend = hour
    ns.UpdateMapHour()
end

function ns.SetupMapHour(map)
    mapFrame = map
    local since = 0
    local ticker = ns.TimedFrame("MapHour tick")
    ticker:SetScript("OnUpdate", function(_, dt)
        since = since + dt
        if since < RATE then return end
        since = 0
        if map:IsShown() and (Cfg().on or tinted) then ns.UpdateMapHour() end
    end)
    map:HookScript("OnShow", ns.UpdateMapHour)
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", function() C_Timer.After(0, ns.UpdateMapHour) end)
    end
end
