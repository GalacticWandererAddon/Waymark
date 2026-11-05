local _, ns = ...

-- A clock on the Battlefield Map (ns.db.clock): shown, look, where, source ("realm", or
-- "computer"), h24, show ("always", or "hover": with the mouse on the map), size, alpha (%),
-- x, y (where = "FREE", detached: its middle as a share of the screen: it's then the screen's
-- and not the map's, so it stays with the map closed or folded), mx, my (where = "MAP", dragged
-- on or around the map: a share of the map, past its edges too, and it goes with the map), hideGame (the game's
-- own clock on the minimap goes); plain digits only: backing (%), frame (a border style, or
-- "none"), frameColor, frameSize, frameGap (px further out from the digits, or in), font, tint
-- ("parchment", "gold", "white"). The stamp and the two pictures: digitSize (%, apart from the
-- art's size), digitBack (%: more paper behind them), digitBold.
-- Looks: "plain" digits with the coordinates' backing; "head" beside the name in the header
-- (ZoneName.lua asks ns.ClockHeaderText); "sun" the moon dial and "arc" the day's arc, on paper
-- with the digits cut into it (Media\Clock, tools\clock_art.py; plate = false: without
-- the paper; hideDigits; digitsX, digitsY: slid from their spot under the art, by dragging them); "stamp" only the sun or moon and the time, on the paper's halo; "ink" the hour in words, to
-- the nearest 5 minutes. Changes once a minute. Drag it to move it, drag the digits to slide them
-- round the art, right-click or Shift-click either for its menu.

local clock                 -- the frame; the look's parts on it
local shownKey              -- the minute that's drawn
local hoverAlpha = 1
local headHover = false     -- the header's "hover" clock is showing
local dragging, grabX, grabY = false, 0, 0
local sliding, slideX, slideY, slideFromX, slideFromY = false, 0, 0, 0, 0
local SLIDE = 160           -- px the digits go from their spot, at most (well clear of the art at any size)
local OFF_FOOT = 8          -- px slid off the paper's foot: the paper goes short, as for digits elsewhere
local AROUND = 0.6          -- how far past the map's edges an anchored clock goes, as a share of it
local home                  -- the map
local TINTS = { parchment = { 0.96, 0.88, 0.70 }, gold = { 1, 0.82, 0 }, white = { 1, 1, 1 } }
local gameClockHooked, gameClockHidden = false, false

local function Cfg() return ns.db.clock end

local function Now(source)
    if source == "computer" then
        local t = date("*t")
        return t.hour, t.min
    end
    return GetGameTime()
end

local function Digits(h, m, h24)
    if h24 then return string.format("%02d:%02d", h, m) end
    return string.format("%d:%02d %s", (h + 11) % 12 + 1, m, h < 12 and "am" or "pm")
end

local NUM = { [0] = "twelve", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven" }
local AMOUNT = { [5] = "five", [10] = "ten", [20] = "twenty", [25] = "twenty-five" }
local function Words(h, m)
    local r = math.floor((h * 60 + m) / 5 + 0.5) * 5 % 1440
    if r == 0 then return "midnight" elseif r == 720 then return "noon" end
    h, m = math.floor(r / 60), r % 60
    local this, coming = NUM[h % 12], NUM[(h + 1) % 12]
    if m == 0 then return this .. " o'clock" end
    if m == 30 then return "half past " .. this end
    if m == 15 then return "quarter past " .. this end
    if m == 45 then return "quarter to " .. coming end
    if m < 30 then return AMOUNT[m] .. " past " .. this end
    return AMOUNT[60 - m] .. " to " .. coming
end

-- the two pictures, in units of a game pixel at 100% (tools\clock_art.py draws to these)
local DIAL = { w = 72, h = 50, cx = 36, base = 34, r = 30, orbit = 20, sun = 22, moon = 16, digits = 42, art = "Dial" }
local ARC = { w = 78, h = 52, cx = 39, base = 35, r = 26, sun = 18, moon = 14, digits = 42.5, art = "Arc" }
local STAMP = { h = 34, x = 17, sun = 25, moon = 19, digits = 31 }
-- the digits aren't on the paper's foot
local function OffFoot(c)
    return math.abs(c.digitsX or 0) > OFF_FOOT * 3 or math.abs(c.digitsY or 0) > OFF_FOOT
end

-- the size of the digits on the stamp and the pictures, and their font: Felipa, or the heavier
-- cut of it (tools\bold_digits.py)
local function DigitFont(c)
    return math.floor((c.look == "stamp" and 15 or 13) * (c.digitSize or 100) / 100 + 0.5),
        ns.MEDIA .. "Fonts\\" .. (c.digitBold and "WaymarkDigits-Bold.ttf" or "Felipa-Regular.ttf")
end

local function Art(name) return ns.MEDIA .. "Clock\\" .. name end

local function IsDay(t) return t >= 360 and t < 1080 end
local function SunArt(t) return Art((t < 450 or t > 990) and "SunLow" or "Sun") end

-- how much of the night's hatching and the dawn's or dusk's red are in the sky, 0 to 1
local function Sky(t)
    local hr = t / 60
    local night = (hr < 5 or hr >= 20) and 1 or hr < 7 and (7 - hr) / 2 or hr >= 18 and (hr - 18) / 2 or 0
    local dusk = hr >= 5 and hr < 9 and 1 - math.abs(hr - 7) / 2 or hr >= 17 and hr < 21 and 1 - math.abs(hr - 19) / 2 or 0
    return night, dusk
end

local function Build(map)
    local f = CreateFrame("Frame", nil, map)
    f:SetSize(40, 14)
    f:SetFrameLevel(ns.ButtonLevel(map))
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetPoint("TOPLEFT", -3, 1)
    f.bg:SetPoint("BOTTOMRIGHT", 3, -1)
    f.glow = f:CreateTexture(nil, "BACKGROUND")   -- (the paper's halo behind the words)
    f.glow:SetTexture(ns.MEDIA .. "Notes\\Glow")
    f.glow:SetPoint("TOPLEFT", -16, 9)
    f.glow:SetPoint("BOTTOMRIGHT", 16, -9)
    f.edge = CreateFrame("Frame", nil, f, "BackdropTemplate")   -- (plain digits' frame)
    f.edge:Hide()
    f.plate = f:CreateTexture(nil, "BORDER")
    f.plate:SetAllPoints()
    -- the dial's sky: clipped to its top half, under the ridge and rim
    f.window = CreateFrame("Frame", nil, f)
    f.window:SetClipsChildren(true)
    f.sky = f.window:CreateTexture(nil, "BACKGROUND")
    f.sky:SetTexture(Art("SunSky"))
    f.sky:SetAllPoints(f.window)
    f.night = f.window:CreateTexture(nil, "BORDER")
    f.night:SetTexture(Art("Night"))
    f.night:SetAllPoints(f.window)
    f.stars = f.window:CreateTexture(nil, "ARTWORK")
    f.stars:SetTexture(Art("Stars"))
    f.stars:SetPoint("CENTER", f.window, "BOTTOM")
    f.sun = f.window:CreateTexture(nil, "OVERLAY")
    f.moon = f.window:CreateTexture(nil, "OVERLAY")
    f.moon:SetTexture(Art("Moon"))
    -- what's in front: the dial's ridge and rim, the arc's sun or moon, the time
    f.top = CreateFrame("Frame", nil, f)
    f.top:SetAllPoints()
    f.front = f.top:CreateTexture(nil, "ARTWORK")
    f.front:SetAllPoints()
    f.mark = f.top:CreateTexture(nil, "ARTWORK", nil, 1)
    f.text = f.top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.lift = f:CreateTexture(nil, "BACKGROUND", nil, 1)   -- (more paper behind the digits, by setting)
    f.lift:SetTexture(ns.MEDIA .. "Notes\\Glow")
    f.lift:SetPoint("TOPLEFT", f.text, "TOPLEFT", -10, 6)
    f.lift:SetPoint("BOTTOMRIGHT", f.text, "BOTTOMRIGHT", 10, -6)
    f.lift:Hide()
    -- (over the digits on the two pictures: dragged, they slide)
    f.grip = CreateFrame("Frame", nil, f.top)
    f.grip:SetPoint("TOPLEFT", f.text, "TOPLEFT", -2, 2)
    f.grip:SetPoint("BOTTOMRIGHT", f.text, "BOTTOMRIGHT", 2, -2)
    f.grip:EnableMouse(true)
    f.grip:Hide()
    return f
end

-- (the parts sit above the frame, whatever sets its level)
local function Levels()
    local level = clock:GetFrameLevel()
    if clock.top:GetFrameLevel() ~= level + 2 or clock.grip:GetFrameLevel() ~= level + 3 then
        clock.grip:SetFrameLevel(level + 3)
        clock.edge:SetFrameLevel(level + 1)
        clock.window:SetFrameLevel(level + 1)
        clock.top:SetFrameLevel(level + 2)
    end
end

-- digits cut into the paper: dark, the light catching the lower lip. One string and its own
-- shadow (a second string lands on other pixels at some sizes: doubled digits), the lip a whole
-- number of screen pixels, in step with the digits' size. bare: no paper under them, so a
-- touch darker, the lip softer (their halo does the lifting)
local function Engrave(f, size, bare)
    local _, screenH = GetPhysicalScreenSize()
    local pixel = 768 / screenH / f:GetEffectiveScale()
    local lip = math.max(1, math.floor(size / pixel / 24 + 0.5)) * pixel
    if bare then
        f.text:SetTextColor(0.11, 0.07, 0.03)
    else
        f.text:SetTextColor(0.17, 0.11, 0.05)
    end
    f.text:SetShadowColor(0.96, 0.88, 0.70, bare and 0.55 or 0.75)
    f.text:SetShadowOffset(lip, -lip)
end

-- the moon dial: the sun and moon go round behind the ridge, noon at the top
local function DrawDial(f, t, s)
    f.window:ClearAllPoints()
    f.window:SetPoint("TOPLEFT", f, "TOPLEFT", (DIAL.cx - DIAL.r) * s, -(DIAL.base - DIAL.r) * s)
    f.window:SetSize(DIAL.r * 2 * s, DIAL.r * s)
    local night, dusk = Sky(t)
    f.sky:SetVertexColor(0.49, 0.23, 0.13, dusk * 0.38)
    f.night:SetAlpha(night)
    local a = (t - 720) / 1440 * 2 * math.pi
    f.stars:SetSize(DIAL.r * 2 * s, DIAL.r * 2 * s)
    f.stars:SetRotation(-a)
    f.stars:SetAlpha(0.25 + 0.75 * night)
    local x, y = math.sin(a) * DIAL.orbit * s, math.cos(a) * DIAL.orbit * s
    f.sun:SetTexture(SunArt(t))
    f.sun:SetSize(DIAL.sun * s, DIAL.sun * s)
    f.sun:ClearAllPoints()
    f.sun:SetPoint("CENTER", f.window, "BOTTOM", x, y)
    f.moon:SetSize(DIAL.moon * s, DIAL.moon * s)
    f.moon:ClearAllPoints()
    f.moon:SetPoint("CENTER", f.window, "BOTTOM", -x, -y)
end

-- the day's arc: the sun walks the track from 6 to 18, the moon from 18 to 6
local function DrawArc(f, t, s)
    local day = IsDay(t)
    local a = math.pi * (day and (t - 360) / 720 or ((t - 1080) % 1440) / 720)
    local size = (day and ARC.sun or ARC.moon) * s
    f.mark:SetTexture(day and SunArt(t) or Art("Moon"))
    f.mark:SetSize(size, size)
    f.mark:ClearAllPoints()
    f.mark:SetPoint("CENTER", f, "TOPLEFT", (ARC.cx - math.cos(a) * ARC.r) * s, -(ARC.base - math.sin(a) * ARC.r) * s)
end

-- more paper behind digits on the map
local function Lift(f, c)
    local back = (c.digitBack or 0) / 100
    f.lift:SetShown(back > 0)
    f.lift:SetVertexColor(0.78, 0.68, 0.50, back * 0.9)
end

-- the stamp: the sun or the moon, and the time beside it
local function PlaceDigits(f, c, p, scale)
    f.text:ClearAllPoints()
    f.text:SetPoint("CENTER", f, "TOP", c.digitsX or 0, -p.digits * scale + (c.digitsY or 0))
end

local function DrawStamp(f, c, h, m, s)
    local t = h * 60 + m
    local size, file = DigitFont(c)
    local day = IsDay(t)
    local mark = (day and STAMP.sun or STAMP.moon) * s
    f.mark:SetTexture(day and SunArt(t) or Art("Moon"))
    f.mark:SetSize(mark, mark)
    f.mark:ClearAllPoints()
    f.mark:SetPoint("CENTER", f, "LEFT", STAMP.x * s, 0)
    f.text:SetFont(file, size, "")
    Engrave(f, size)
    f.text:SetPoint("LEFT", f, "LEFT", math.floor(STAMP.digits * s + 0.5), 0)
    f.text:SetText(Digits(h, m, c.h24))
    f:SetSize(STAMP.digits * s + f.text:GetStringWidth() + 4, STAMP.h * s)
    f.glow:ClearAllPoints()
    f.glow:SetPoint("TOPLEFT", -8, 5)
    f.glow:SetPoint("BOTTOMRIGHT", 8, -5)
    f.glow:SetVertexColor(0.67, 0.56, 0.38, 0.92)
    Lift(f, c)
end

local function Draw(c, h, m)
    local f, look, scale = clock, c.look, (c.size or 100) / 100
    local dial, arc = look == "sun", look == "arc"
    local paper = dial or arc
    f.bg:SetShown(look == "plain")
    local bare = paper and c.plate == false
    local hidden = paper and c.hideDigits
    local off = paper and (hidden or OffFoot(c))
    local halo = paper and not hidden and (bare or off)   -- (digits straight on the map)
    f.grip:SetShown(paper and not hidden)
    f.glow:SetShown(look == "ink" or look == "stamp" or halo)
    f.plate:SetShown(paper and not bare)
    f.window:SetShown(dial)
    f.front:SetShown(paper)
    f.mark:SetShown(arc or look == "stamp")
    f.lift:Hide()
    if look ~= "plain" then f.edge:Hide() end
    f.text:SetShown(look ~= "head" and not hidden)
    Levels()
    if look == "head" then return end
    local text
    f.text:ClearAllPoints()
    if look == "stamp" then return DrawStamp(f, c, h, m, scale) end
    if paper then
        local p = dial and DIAL or ARC
        local size, file = DigitFont(c)
        size = size + (halo and 1 or 0)
        text = Digits(h, m, c.h24)
        f.text:SetFont(file, size, "")
        Engrave(f, size, halo)
        -- (paper with no room for digits, where they aren't under the art)
        f.plate:SetTexture(Art(p.art .. (off and "PlateShort" or "Plate")))
        f.front:SetTexture(Art(p.art .. "Front"))
        f:SetSize(p.w * scale, p.h * scale)
        PlaceDigits(f, c, p, scale)
        f.text:SetText(text)
        if halo then
            -- (a faint breath of paper behind the digits alone)
            f.glow:ClearAllPoints()
            f.glow:SetPoint("TOPLEFT", f.text, "TOPLEFT", -9, 5)
            f.glow:SetPoint("BOTTOMRIGHT", f.text, "BOTTOMRIGHT", 9, -5)
            f.glow:SetVertexColor(0.78, 0.68, 0.50, 0.75)
            Lift(f, c)
        end
        if dial then DrawDial(f, h * 60 + m, scale) else DrawArc(f, h * 60 + m, scale) end
        return
    end
    if look == "ink" then
        f.text:SetPoint("BOTTOM")
        f.glow:ClearAllPoints()
        f.glow:SetPoint("TOPLEFT", -16, 9)
        f.glow:SetPoint("BOTTOMRIGHT", 16, -9)
        f.text:SetFont(ns.MEDIA .. "Fonts\\NothingYouCouldDo.ttf", math.floor(15 * scale + 0.5), "")
        f.text:SetTextColor(0.18, 0.12, 0.06)
        f.text:SetShadowColor(0.93, 0.86, 0.70, 0.9)
        f.text:SetShadowOffset(1, -1)
        f.glow:SetVertexColor(0.93, 0.86, 0.70, 0.85)
        text = Words(h, m)
    else
        f.text:SetPoint("CENTER")
        ns.SetFontSafe(f.text, c.font, math.floor(14 * scale + 0.5), "")
        local tint = TINTS[c.tint] or TINTS.parchment
        f.text:SetTextColor(tint[1], tint[2], tint[3])
        f.text:SetShadowColor(0, 0, 0, 1)
        f.text:SetShadowOffset(1, -1)
        text = Digits(h, m, c.h24)
    end
    f.text:SetText(text)
    local framed = look == "plain" and (c.frame or "none") ~= "none"
    f.bg:SetColorTexture(0, 0, 0, (c.backing or 50) / 100)
    f:SetSize(math.max(20, f.text:GetStringWidth() + 2), f.text:GetStringHeight() + 2)
    if framed then
        ns.DressBorder(f.edge, f, c.frame, c.frameSize or 0.75, c.frameGap or 0, c.frameColor)
    else
        f.edge:Hide()
    end
end

-- at a spot inside the map, clear of the coordinates, the close button and a soft edge
local function Place(c)
    local area = home.ScrollContainer or home
    local point = c.where or "BOTTOMRIGHT"
    local parent = point == "FREE" and UIParent or home
    if clock:GetParent() ~= parent then
        clock:SetParent(parent)
        -- (on the screen: above the map, whatever layer the dock has put that on)
        clock:SetFrameStrata(point == "FREE" and "HIGH" or home:GetFrameStrata())
        clock:SetFrameLevel(ns.ButtonLevel(home))
        Levels()
        if c.look == "sun" or c.look == "arc" or c.look == "stamp" then
            Engrave(clock, (DigitFont(c)),
                c.look ~= "stamp" and (c.plate == false or OffFoot(c)))
        end
    end
    -- (on the map it has the map's scale; alone on the screen, Waymark's size)
    local g = point == "FREE" and ns.AddonScale() or 1
    if clock:GetScale() ~= g then clock:SetScale(g) end
    if point == "FREE" then
        -- (kept on the screen, whatever its size)
        local aw, ah = UIParent:GetSize()
        local w, h = clock:GetSize()
        local lx, ly = math.min(0.5, w / 2 / aw), math.min(0.5, h / 2 / ah)
        c.x = math.max(lx, math.min(1 - lx, c.x or 0.5))
        c.y = math.max(ly, math.min(1 - ly, c.y or 0.5))
        clock:ClearAllPoints()
        clock:SetPoint("CENTER", UIParent, "TOPLEFT", c.x * aw / g, -c.y * ah / g)
        return
    end
    if point == "MAP" then
        -- (docked: placed from the square, the spot you look for the time. From the map frame, the big
        -- map put it off the screen, and the corner's drag took it along till it snapped back)
        if ns.Docked and ns.Docked() and ns.DockSquareBox then area = ns.DockSquareBox() end
        local aw, ah = area:GetSize()
        local k = area:GetEffectiveScale() / clock:GetEffectiveScale()
        c.mx = math.max(-AROUND, math.min(1 + AROUND, c.mx or 0.5))
        c.my = math.max(-AROUND, math.min(1 + AROUND, c.my or 0.5))
        clock:ClearAllPoints()
        clock:SetPoint("CENTER", area, "TOPLEFT", c.mx * aw * k, -c.my * ah * k)
        return
    end
    local ix, iy = 0, 0
    if ns.SoftEdgeInset then ix, iy = ns.SoftEdgeInset() end
    local top = point:find("TOP") ~= nil
    local dx = point:find("LEFT") and 4 + ix or point:find("RIGHT") and -4 - ix or 0
    local dy = 3 + iy
    local co = ns.db.coords
    if ns.IsShown("coords") and co.side ~= "outside" and (co.where or "BOTTOMLEFT") == point then
        dy = dy + (co.size or 10) + 7
    end
    if point == "TOPRIGHT" then dy = dy + 24 end
    clock:ClearAllPoints()
    clock:SetPoint(point, area, point, dx, top and -dy or dy)
end

-- the header's clock: the time, or nil (ZoneName.lua)
function ns.ClockHeaderText()
    if not (ns.db and ns.IsShown("clock")) then return end
    local c = Cfg()
    if c.look ~= "head" or (c.show == "hover" and not headHover) then return end
    local h, m = Now(c.source)
    return Digits(h, m, c.h24)
end

-- the game's own clock on the minimap
local function GameClock()
    local b = TimeManagerClockButton
    if not b then return end
    local hide = Cfg().hideGame and true or false
    if hide and not gameClockHooked then
        gameClockHooked = true
        hooksecurefunc(b, "Show", function(self) if Cfg().hideGame then self:Hide() end end)
    end
    if hide then
        b:Hide()
    elseif gameClockHidden then
        b:Show()
    end
    gameClockHidden = hide
end

function ns.UpdateClock()
    if not clock then return end
    GameClock()
    local c = Cfg()
    local on = ns.IsShown("clock")
    clock:SetShown(on)
    clock:EnableMouse(on and c.look ~= "head")
    if on then
        local h, m = Now(c.source)
        Draw(c, h, m)
        Place(c)
        shownKey = h * 60 + m
        clock:SetAlpha((c.alpha or 100) / 100 * hoverAlpha)
    end
    if ns.UpdateZoneName then ns.UpdateZoneName() end
end

local function Tip(self)
    local c = Cfg()
    local rh, rm = GetGameTime()
    local t = date("*t")
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddDoubleLine("Realm time", Digits(rh, rm, c.h24), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Your computer", Digits(t.hour, t.min, c.h24), 1, 0.82, 0, 1, 1, 1)
    ns.Hints({ { "Drag", self == clock.grip and "slide the digits" or "move the clock" },
               { "Right-click or Shift-click", "the clock's menu" } })
    GameTooltip:Show()
end

local function Moved()
    ns.UpdateClock()
    if ns.RefreshControls then ns.RefreshControls() end
end

-- where it is now, as a share of the map
local function ShareOfMap(cx, cy)
    local area = home.ScrollContainer or home
    local left, top = area:GetLeft(), area:GetTop()
    if not left then return 0.5, 0.5 end
    return (cx - left) / area:GetWidth(), (top - cy) / area:GetHeight()
end

-- stays where it is on the screen, belonging to the screen / the map from now on
local function Detach()
    local c = Cfg()
    local cx, cy = clock:GetCenter()
    local s = clock:GetEffectiveScale() / UIParent:GetEffectiveScale()
    c.x, c.y = cx * s / UIParent:GetWidth(), 1 - cy * s / UIParent:GetHeight()
    c.where = "FREE"
    Moved()
end

local function Anchor()
    local c = Cfg()
    local cx, cy = clock:GetCenter()
    local s = clock:GetEffectiveScale() / (home.ScrollContainer or home):GetEffectiveScale()
    c.mx, c.my = ShareOfMap(cx * s, cy * s)
    c.where = "MAP"
    Moved()
end

-- the settings' reset: detached, just under the minimap, the digits back under the art
function ns.ResetClock()
    if not clock then return end
    local c = Cfg()
    local cx, bottom = Minimap:GetCenter(), Minimap:GetBottom()
    local s = Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale()
    c.where, c.digitsX, c.digitsY = "FREE", 0, 0
    c.x, c.y = 0.93, 0.22
    if cx and bottom then
        c.x = cx * s / UIParent:GetWidth()
        c.y = 1 - (bottom * s - clock:GetHeight() / 2 - 8) / UIParent:GetHeight()
    end
    Moved()
end

local function Menu()
    GameTooltip:Hide()
    local where = Cfg().where
    local items = { { "settings", function() ns.ShowOption("clock", "look") end } }
    if where == "FREE" then
        items[2] = { "anchor to the map", Anchor }
    else
        items[2] = { "detach from the map", Detach }
    end
    local c = Cfg()
    if c.look == "sun" or c.look == "arc" then
        items[#items + 1] = { c.hideDigits and "show digits" or "hide digits", function()
            c.hideDigits = not c.hideDigits
            Moved()
        end }
    end
    ns.QuillMenu(items)
end

-- following the mouse: detached, on the screen; anchored, on and around the map
local function Follow(c)
    local s = clock:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = x / s - grabX, y / s - grabY
    if c.where == "FREE" then
        local g = ns.AddonScale()
        c.x, c.y = x * g / UIParent:GetWidth(), 1 - y * g / UIParent:GetHeight()
    else
        c.where = "MAP"
        c.mx, c.my = ShareOfMap(x, y)
    end
    Place(c)
end

-- the digits following the mouse
local function Slide(c)
    local s = clock:GetEffectiveScale()
    local x, y = GetCursorPosition()
    c.digitsX = math.max(-SLIDE, math.min(SLIDE, math.floor(slideFromX + x / s - slideX + 0.5)))
    c.digitsY = math.max(-SLIDE, math.min(SLIDE, math.floor(slideFromY + y / s - slideY + 0.5)))
    PlaceDigits(clock, c, c.look == "sun" and DIAL or ARC, (c.size or 100) / 100)
end

local function StartSlide()
    if IsShiftKeyDown() then return end
    GameTooltip:Hide()
    local c, s = Cfg(), clock:GetEffectiveScale()
    local x, y = GetCursorPosition()
    slideX, slideY = x / s, y / s
    slideFromX, slideFromY = c.digitsX or 0, c.digitsY or 0
    sliding = true
end

local function StopSlide()
    if not sliding then return end
    sliding = false
    Moved()
end

local function StartDrag()
    if IsShiftKeyDown() then return end
    GameTooltip:Hide()
    local s = clock:GetEffectiveScale()
    local x, y = GetCursorPosition()
    local cx, cy = clock:GetCenter()
    grabX, grabY = x / s - cx, y / s - cy
    dragging = true
end

local function StopDrag()
    if not dragging then return end
    dragging = false
    if ns.RefreshControls then ns.RefreshControls() end
end

-- on the screen and not the map (Collapse.lua: folding the map leaves it)
function ns.ClockFree() return Cfg().where == "FREE" end

function ns.SetupClock(map)
    home = map
    clock = Build(map)
    ns.debugFrames.clock = clock
    clock:RegisterForDrag("LeftButton")
    clock:SetScript("OnDragStart", StartDrag)
    clock:SetScript("OnDragStop", StopDrag)
    clock:SetScript("OnHide", function() StopDrag() StopSlide() end)
    local function Press(_, button)
        if button == "RightButton" or (button == "LeftButton" and IsShiftKeyDown()) then Menu() end
    end
    for _, f in ipairs({ clock, clock.grip }) do
        f:SetScript("OnEnter", Tip)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f:SetScript("OnMouseUp", Press)
    end
    clock.grip:RegisterForDrag("LeftButton")
    clock.grip:SetScript("OnDragStart", StartSlide)
    clock.grip:SetScript("OnDragStop", StopSlide)
    -- (the Blizzard add-on with the game's clock can load after us)
    local events = CreateFrame("Frame")
    events:RegisterEvent("ADDON_LOADED")
    events:SetScript("OnEvent", function(_, _, name) if name == "Blizzard_TimeManager" then GameClock() end end)
    local since = 0
    clock:SetScript("OnUpdate", ns.Timed("Clock tick", function(_, dt)
        local c = Cfg()
        if dragging then Follow(c) end
        if sliding then Slide(c) end
        local hover = c.show ~= "hover" or (ns.MouseOnMap and ns.MouseOnMap(map)) or dragging
            or clock:IsMouseOver() or false
        local want = hover and 1 or 0
        if hoverAlpha ~= want then
            local step = 5 * dt
            hoverAlpha = math.abs(want - hoverAlpha) <= step and want or hoverAlpha + (want > hoverAlpha and step or -step)
            clock:SetAlpha((c.alpha or 100) / 100 * hoverAlpha)
        end
        if c.look == "head" and headHover ~= (hover and true or false) then
            headHover = hover and true or false
            if ns.UpdateZoneName then ns.UpdateZoneName() end
        end
        since = since + dt
        if since < 0.25 then return end
        since = 0
        Levels()
        local h, m = Now(c.source)
        if h * 60 + m ~= shownKey then ns.UpdateClock() end
    end))
    ns.UpdateClock()
end
